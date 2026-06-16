# Controles contables estilo SAP para VitalStock — Diseño

**Fecha:** 2026-06-16
**Estado:** Aprobado para planificación
**Autor:** Giuliano + Claude

## Contexto

VitalStock es el ERP single-tenant de Vitalmet (un archivo `index.html` ~8.050 líneas + Supabase/Postgres con 30 migraciones). Maneja plan de cuentas jerárquico, compras (OC → recepción → remito/certificado MTC), facturación AFIP con asiento contable automático, stock y CRM.

Se identificaron controles del mundo SAP que aportan valor real a un distribuidor MRO chico sin caer en la complejidad de un ERP corporativo. Este spec cubre los 5 elegidos, en 2 fases.

### Hallazgos relevantes del codebase (estado actual)

- **Audit trail ya existe parcialmente:** migración `023_integridad.sql` tiene tabla `audit_log` + trigger `fn_audit()` cubriendo `ventas`, `venta_items`, `asientos`, `asiento_lineas`, `barras`, `productos_terminados`, `clientes`, `presupuestos`, `facturas_emitidas`. **No cubre compras ni tesorería.**
- **Asiento de compra hoy:** `generarAsientoCompra()` (client-side en `index.html`) se dispara en la **recepción** (`saveRecepcion()`), debita stock/gasto + IVA y acredita Proveedores directo. La factura del proveedor son campos de texto sueltos en `ordenes_compra` (`factura_nro`, `factura_fecha`, `factura_vto`) — **no hay tabla de facturas recibidas**.
- **Asiento de venta:** `generarAsientoFactura()` se dispara al emitir factura AFIP. Idempotente vía `origen_tipo`/`origen_id`.
- **Numeración de asientos:** ya garantizada DB-side (trigger `fn_asiento_numero()`, MAX+1 por empresa bajo advisory lock, migración 023). OC y cheques son texto client-side.
- **Roles:** no hay tabla de roles; cada `usuarios` tiene columna `es_admin boolean`. Permisos por módulo son solo visuales (REST accesible a todo autenticado). RLS por `empresa_id` vía `current_empresa_id()` (SECURITY DEFINER).
- **Ejercicios:** existe tabla `ejercicios` (migración 013, anual, con estado abierto/cerrado) pero **sin enforcement** que bloquee asientos en períodos cerrados.
- **Tesorería:** existe tabla `cheques` (migración 027). **No hay** `cuentas_bancarias` ni `movimientos_bancarios`; los bancos son cuentas del plan (111003 BANCO HSBC, etc.). Conciliación 100% manual.
- **Config contable:** tabla `config_contable` mapea cuentas para auto-asientos (ventas, IVA débito/crédito, proveedores, compras por tipo, caja, banco).

## Decisiones tomadas

| Decisión | Elección |
|---|---|
| Modelo 3-way match | **GR/IR estilo SAP** (cuenta puente "Mercaderías/Facturas a recibir") |
| Timing del IVA crédito fiscal | En la **factura recibida**, no en el remito (fiscalmente correcto; el crédito solo es válido con factura) |
| Tolerancia de match | **% + tope $ configurable**, default **2% o $5.000 (lo que sea menor)** |
| Acción si el match falla | **Bloquea + override admin con motivo** (queda en audit_log) |
| Cierre de períodos | **Bloqueo duro a nivel mensual** (no anual) + reapertura solo `es_admin` |
| Granularidad del match v1 | Nivel **OC** (cant total recibida vs facturada); múltiples facturas acumulan contra saldo GR/IR |

## Fase A — Alto valor (items 1-4)

### 1. Audit trail (extender existente)

Enganchar el trigger `fn_audit()` ya existente a las tablas hoy ciegas:
`ordenes_compra`, `oc_items`, `recepciones_oc`, `proveedores`, `cheques`, y las nuevas
`facturas_recibidas`, `periodos_contables`, `cuentas_bancarias`.

**Migración:** `031_audit_compras.sql` — solo `CREATE TRIGGER ... fn_audit()` por tabla. Sin cambios de esquema en `audit_log`.

### 2. Períodos contables cerrados (bloqueo duro mensual)

Motivación: en Argentina el IVA se declara mensualmente; el objetivo es impedir asientos retroactivos en un mes ya declarado.

- **Tabla `periodos_contables`:** `id`, `empresa_id`, `anio int`, `mes int (1-12)`, `estado text ('abierto'|'cerrado')`, `cerrado_por uuid`, `cerrado_at timestamptz`. UNIQUE(empresa_id, anio, mes). RLS por empresa_id.
- **Helper `current_usuario_es_admin()`** SECURITY DEFINER (mismo patrón que `current_empresa_id()`): lee `usuarios.es_admin` del usuario del JWT.
- **Trigger `fn_periodo_cerrado()`** BEFORE INSERT/UPDATE en `asientos`: si `NEW.fecha` cae en un período `cerrado` → `RAISE EXCEPTION`. (Un período no listado se considera abierto.)
- **Reapertura:** UPDATE de `periodos_contables.estado` a `abierto` permitido solo si `current_usuario_es_admin()`; trigger lo valida y `fn_audit()` lo registra.
- **UI:** panel "Cierre de períodos" en la sección contable — listar meses, cerrar/reabrir, ver estado y quién cerró.

### 3. 3-way match GR/IR (OC ↔ Remito ↔ Factura)

**a) Cuenta puente.** Nueva cuenta pasivo en el plan: "Mercaderías/Facturas a recibir" (GR/IR). Mapeada en `config_contable.cta_gr_ir`.

**b) Cambio en el asiento de recepción** (`generarAsientoCompra()` en `index.html`):
```
HOY:   Debe Stock/Gasto (neto) + Debe IVA CF | Haber Proveedores (total)
NUEVO: Debe Stock/Gasto (neto)               | Haber Fact. a recibir / GR/IR (neto)
```
Se quita el IVA y Proveedores del asiento de recepción; pasan al asiento de la factura.

**c) Tabla `facturas_recibidas`:** `id`, `empresa_id`, `proveedor_id`, `oc_id (FK ordenes_compra)`, `nro text`, `fecha date`, `fecha_vto date`, `neto numeric`, `iva numeric`, `total numeric`, `moneda text`, `tipo_cambio numeric`, `estado_match text ('pendiente'|'ok'|'discrepancia'|'override')`, `asiento_id uuid`, `override_por uuid`, `override_motivo text`, `created_by`, `created_at`. RLS por empresa_id.

**d) RPC `registrar_factura_recibida()`** (transaccional):
1. Calcula el match a nivel OC: precio/cant de `oc_items` ↔ cant en `recepciones_oc` ↔ montos de la factura.
2. Tolerancia: diferencia ≤ `match_tolerancia_pct` del total **O** ≤ `match_tolerancia_monto` (lo que sea menor).
3. **Match OK o `current_usuario_es_admin()` con override+motivo** → crea asiento IR:
   ```
   Debe GR/IR (neto) + Debe IVA CF | Haber Proveedores (total)
   ```
   Setea `estado_match` = `ok` u `override`.
4. **Match falla y no es admin** → `RAISE EXCEPTION` (bloquea); `estado_match` = `discrepancia` no se persiste (rollback).

**e) Config de tolerancia:** agregar a `config_contable`: `match_tolerancia_pct numeric DEFAULT 0.02`, `match_tolerancia_monto numeric DEFAULT 5000`, `cta_gr_ir uuid`.

**f) UI:** sección en Compras para cargar la factura del proveedor contra una OC. Muestra comparación lado a lado (cant/precio OC vs remito vs factura) con discrepancias resaltadas; botón de override visible solo a admin (pide motivo).

**Migración:** `033_gr_ir_3way_match.sql` — cuenta GR/IR (seed), columnas en `config_contable`, tabla `facturas_recibidas`, RPC `registrar_factura_recibida()`.

> **Alcance v1:** match a nivel OC. Múltiples facturas contra una OC acumulan contra el saldo GR/IR. No se parten facturas por línea individual.

### 4. Control de correlatividad

- Asientos: numeración ya garantizada DB-side. ✓ (sin cambios)
- `UNIQUE(empresa_id, nro)` en `ordenes_compra` (si falta) + sugerencia de próximo nº (MAX+1 con prefijo) al crear OC en la UI.
- **Reporte "Control de correlatividad":** vista/query que detecta huecos y duplicados en asientos (`numero`), OCs (`nro` numérico) y facturas emitidas (`punto_venta`+`numero`). Tabla en UI.

**Migración:** `034_correlatividad.sql` — unique OC + vista de huecos/duplicados.

## Fase B — Conciliación bancaria (item 7)

Módulo net-new.

- **Tabla `cuentas_bancarias`:** `id`, `empresa_id`, `nombre`, `banco`, `nro_cuenta`, `cbu`, `moneda`, `cuenta_contable_id (FK cuentas_contables — enlaza con 111003 etc.)`, `activa bool`. RLS por empresa_id.
- **Tabla `extracto_bancario`:** `id`, `empresa_id`, `cuenta_bancaria_id`, `fecha`, `descripcion`, `importe numeric (con signo)`, `saldo numeric`, `referencia text`, `conciliado bool DEFAULT false`, `asiento_linea_id uuid (FK, nullable — el movimiento del libro que matchea)`, `import_batch_id`, `created_at`. RLS por empresa_id.
- **Importación:** pegado/CSV del resumen bancario.
- **Auto-match:** contra `asiento_lineas` que tocan la `cuenta_contable_id` del banco y no están conciliadas, por importe + cercanía de fecha. Match manual para el resto.
- **UI:** pantalla de conciliación con dos columnas (extracto vs libro), marcar conciliado, ver diferencia/saldo.

**Migración:** `035_conciliacion_bancaria.sql`.

## Resumen de migraciones nuevas

| # | Archivo | Contenido | Fase |
|---|---------|-----------|------|
| 031 | `audit_compras.sql` | triggers `fn_audit` en compras/tesorería | A |
| 032 | `periodos_contables.sql` | tabla + trigger bloqueo + helper `es_admin` | A |
| 033 | `gr_ir_3way_match.sql` | cuenta GR/IR, config, `facturas_recibidas`, RPC match | A |
| 034 | `correlatividad.sql` | unique OC + vista huecos/duplicados | A |
| 035 | `conciliacion_bancaria.sql` | `cuentas_bancarias` + `extracto_bancario` | B |

Más cambios en `index.html`: asiento de recepción GR/IR + UIs nuevas (cierre de períodos, factura recibida con match, reporte de correlatividad, conciliación bancaria).

## Fuera de alcance (YAGNI)

- Multi-tenancy / multi-sociedad (VitalStock es single-tenant a propósito).
- MRP / planificación de producción.
- Segregación de funciones completa por roles DB (se mantiene `es_admin` boolean).
- Costeo de inventario PPP/FIFO formal (es otro item, no entra acá).
- Match 3-way a nivel línea individual de factura (v1 es a nivel OC).

## Criterios de éxito

- Cualquier cambio en OC/recepción/factura recibida/cheque queda en `audit_log`.
- No se puede imputar un asiento con fecha en un mes cerrado (salvo reapertura admin).
- Una factura de proveedor que no matchea OC+remito dentro de tolerancia queda bloqueada salvo override admin con motivo registrado.
- La cuenta GR/IR neta a cero cuando recepción y factura coinciden.
- El reporte de correlatividad lista huecos y duplicados reales.
- (Fase B) Las líneas del extracto se concilian contra movimientos del libro con saldo cuadrado.
