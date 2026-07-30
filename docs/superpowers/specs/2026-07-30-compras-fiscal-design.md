# Compras fiscal completo — diseño

**Fecha:** 2026-07-30
**Estado:** aprobado por Giuliano (sesión 2026-07-30)
**Migración:** `054_compras_fiscal.sql`

## Objetivo

Llevar el circuito de facturas de proveedor al nivel de un ERP argentino completo
(Tango/SAP/Odoo): alícuotas múltiples de IVA (10,5 / 21 / 27 / exento / no gravado),
percepciones (IVA, IIBB, Ganancias), tipo y letra de comprobante, notas de
crédito/débito de proveedor, facturas sin OC, y condición fiscal del proveedor.

## Qué NO cambia

- OC, recepción, cuarentena/inspección de entrada.
- Lógica de 3-way match y tolerancias (`match_tolerancia_pct/monto`).
- Circuito GR/IR y el asiento de recepción (`generarAsientoCompra`).
- Las NC **no mueven stock** — solo ajuste contable/fiscal. Devoluciones físicas
  siguen saliendo por el circuito de inspección/rechazo existente.

## 1. Modelo de datos (migración 054)

### `proveedores`
- `condicion_fiscal text NOT NULL DEFAULT 'RI'`
  CHECK IN (`'RI'`, `'monotributo'`, `'exento'`, `'consumidor_final'`).

### `facturas_recibidas` (cabecera)
- `tipo text NOT NULL DEFAULT 'factura'` CHECK IN (`'factura'`,`'nota_credito'`,`'nota_debito'`).
- `letra text NOT NULL DEFAULT 'A'` CHECK IN (`'A'`,`'B'`,`'C'`,`'M'`,`'X'`).
- `no_gravado numeric NOT NULL DEFAULT 0`.
- `exento numeric NOT NULL DEFAULT 0`.
- `factura_asociada_id uuid REFERENCES facturas_recibidas(id)` — NC/ND → factura original.
- `cta_imputacion_id uuid REFERENCES cuentas_contables(id)` — solo facturas sin OC
  (y contrapartida de NC).
- Semántica de montos: **siempre positivos**; el signo lo aplica `tipo` en
  exportables y asientos. `neto` pasa a significar "suma de bases gravadas".
- `oc_id` ya es nullable — pasa a ser opcional de verdad (factura de gastos).

### Nueva tabla `factura_recibida_impuestos`
| campo | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid NOT NULL | RLS patrón tenant_isolation estándar (mig 020/022) |
| factura_id | uuid NOT NULL REFERENCES facturas_recibidas ON DELETE CASCADE | |
| tipo | text CHECK | `'iva'`,`'percepcion_iva'`,`'percepcion_iibb'`,`'percepcion_ganancias'`,`'otros'` |
| alicuota | numeric NULL | solo tipo `iva`: 0, 2.5, 5, 10.5, 21, 27 |
| base | numeric NOT NULL DEFAULT 0 | base imponible (solo IVA) |
| monto | numeric NOT NULL | importe del impuesto |
| jurisdiccion | text NULL | solo `percepcion_iibb` (CABA, PBA, Córdoba, …) |

Índice por `(empresa_id, factura_id)`. Trigger `fn_audit` como el resto.

### `config_contable`
Tres campos nuevos, apuntados por default a cuentas del plan real de Vitalmet SA
(seed 007). El plan ya separa retenciones de percepciones (113005 RETENCIONES IVA
vs 113007 PERCEPCION IVA), así que respetamos ese criterio:
- `cta_percep_iva` → **113007 PERCEPCION IVA** (ya existe, se reutiliza)
- `cta_percep_iibb` → **113010 PERCEPCIONES IIBB SUFRIDAS** (nueva — código libre;
  cuenta única, la jurisdicción es dato de la fila de impuesto)
- `cta_percep_ganancias` → **113011 PERCEPCIONES GANANCIAS SUFRIDAS** (nueva — código libre)

Las cuentas nuevas se crean con el patrón idempotente NOT EXISTS de la mig 033.

Si una cuenta queda sin configurar, esa pata del asiento no se genera (mismo
patrón "no rompe nada" del resto de la imputación contable).

### Backfill de datos existentes
No se fabrica desglose: las facturas ya cargadas conservan `neto/iva/total`.
Se les crea una fila `iva` con `alicuota=21` **solo si** `iva ≈ neto*0.21` (±1%);
si no, quedan sin desglose y el exportable las muestra en columna "sin desglose".

## 2. RPC `registrar_factura_recibida` v2

Firma: `(p_factura jsonb, p_impuestos jsonb, p_override boolean, p_motivo text)`.
`p_impuestos` = array de filas de `factura_recibida_impuestos`.

**Validaciones nuevas:**
- Aritmética obligatoria: `total = Σbases_iva + no_gravado + exento + Σmontos_iva + Σpercepciones`
  con tolerancia $0,01. Hoy nadie valida que neto+IVA=total.
- `neto` (cabecera) = `Σbases_iva` (solo lo gravado). El match compara
  `neto + no_gravado + exento` contra el valor recibido de la OC (misma base
  que el crédito GR/IR).
- Letra C (monotributo/exento): no admite filas tipo `iva` con monto > 0 —
  todo el importe es costo/gasto (IVA no computable).
- NC/ND: `factura_asociada_id` debe existir y ser de la misma empresa/proveedor;
  requiere `cta_imputacion_id` (contrapartida).

**3-way match:** misma lógica y tolerancias actuales; solo aplica a `tipo='factura'`
con `oc_id`. Facturas sin OC y NC/ND → `estado_match='ok'` (no matchean contra nada;
en render se muestran como "s/OC" y "NC/ND", no como match verificado).

**Asientos (estado confirmado, vía `crear_asiento`):**
- Factura con OC: DEBE GR/IR (neto) · DEBE IVA CF (Σiva) · DEBE percepciones
  (cada tipo a su cuenta) — HABER Proveedores (total).
- Factura sin OC: DEBE `cta_imputacion_id` (neto + no_gravado + exento) · DEBE IVA CF
  · DEBE percepciones — HABER Proveedores (total).
- Nota de crédito: DEBE Proveedores (total) — HABER `cta_imputacion_id` (neto+ng+ex)
  · HABER IVA CF · HABER percepciones.
- Nota de débito: como factura sin OC (aumenta deuda).
- Factura letra C: sin línea de IVA; todo el total menos percepciones va a la
  cuenta de imputación / GR-IR.

## 3. UI (index.html)

### Modal factura recibida (rediseño)
- Fila superior: tipo de comprobante (Factura / NC / ND) + letra (A/B/C/M/X) +
  nro + fecha + vto. Letra sugerida por condición fiscal del proveedor
  (RI→A, monotributo→C); warning suave si no coincide.
- **Grilla IVA**: filas dinámicas alícuota → base → IVA autocalculado
  (`base*alicuota`, editable por redondeos del proveedor). Oculta con letra C.
- Campos `No gravado` y `Exento`.
- **Grilla percepciones**: tipo + jurisdicción (visible solo IIBB) + monto.
- Total autocalculado, comparado contra el campo Total tipeado del papel:
  si no cierra (>$0,01) no deja guardar.
- Preview de 3-way match: igual que hoy (solo facturas con OC).
- Para NC/ND: selector de factura asociada (facturas del mismo proveedor) +
  cuenta de contrapartida (default: `cta_imputacion_id` de la asociada si era
  sin OC; si era con OC, sin default — el usuario elige).

### Tab Facturas recibidas
- Botón **"+ Factura sin OC"**: mismo modal con selector de proveedor +
  cuenta de gasto (obligatoria) y sin bloque de match.
- Acción **"NC/ND"** por fila → abre el modal pre-vinculado.
- Columna Tipo con badge (FA/NC/ND + letra); montos de NC en negativo y en coral.
- Stats del tab: el total facturado descuenta NC.

### Modal proveedor
- Select `Condición fiscal` (RI / Monotributo / Exento / Consumidor final).

### Alertas dashboard
- Vencimientos de facturas: además de `oc.factura_vto`, incluir
  `facturas_recibidas.fecha_vto` de facturas sin OC no pagadas/anuladas.

## 4. Exportables

### IVA Compras (reforma a libro real)
Columnas: Fecha · Tipo cbte (FA-A, NC-B, …) · Nro · Proveedor · CUIT ·
Neto 10,5 · IVA 10,5 · Neto 21 · IVA 21 · Neto 27 · IVA 27 ·
Otras alícuotas (neto/IVA) · No gravado · Exento · Percep IVA · Percep IIBB
(con jurisdicción) · Percep Gcias · Total. NC con **signo negativo** en todas
las columnas. Facturas viejas sin desglose → columna "Sin desglose".
Fila de totales al pie.

### Subdiario de compras
Incluye los nuevos comprobantes (sin OC, NC/ND) con tipo y signo.

## 5. Criterios de aceptación

1. Cargar factura A con mezcla 21% + 10,5% + percepción IIBB PBA → asiento con
   IVA CF por la suma, percepción a su cuenta, y libro IVA con desglose correcto.
2. Cargar factura C de monotributista → sin IVA discriminado, todo a gasto.
3. NC de proveedor sobre factura existente → deuda y crédito IVA reducidos,
   negativo en libro.
4. Factura de gastos sin OC contra cuenta "Servicios de Terceros" → asiento
   correcto, sin match, alerta de vencimiento activa.
5. Facturas históricas siguen visibles y exportables sin romper totales.
6. Suma que no cierra (total ≠ componentes) → el modal y la RPC la rechazan.
