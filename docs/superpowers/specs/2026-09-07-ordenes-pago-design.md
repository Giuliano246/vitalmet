# Órdenes de pago a proveedores (multi-medio + imputación) — Diseño

**Fecha:** 2026-09-07
**Estado:** implementado en rama `feat/ordenes-pago` (2026-09-07) · 17 tests nuevos, suite 242/242 verde · migración 074 validada con smoke funcional en Postgres 17 local (esquema stub), NO contra prod · pendiente: correr la 074 en el SQL Editor, deployar y probar E2E.
**Origen:** hoja manuscrita "Arreglos para el ERP" (2026-09-07), sección PAGOS:
"para una misma FC: TF + CH / varios CH", "anular registro", "banco BBVA no
HSBC", "pago FC: contado (caja/bco/TC) vs a cuenta → orden de pago".

## Contexto

Hoy el pago a un proveedor se registra en Contabilidad → Cobros y Pagos con
**un solo método** (caja, banco o cheque) y **sin imputar** a ninguna
factura: el asiento es Proveedores / Medio y la deuda por proveedor se
calcula sumando OCs en estado "facturada" (`renderProveedores`), que no
descuenta pagos parciales ni NC. No existe el concepto de Orden de Pago
(comprobante numerado que se entrega al proveedor con los cheques).

## Decisiones

- **Una OP = un proveedor, N medios, M imputaciones.** Medios: caja,
  transferencia (cuenta bancaria real de `cuentas_bancarias`), cheque
  diferido (se crea el cheque emitido en la misma transacción) y tarjeta
  de crédito (cuenta 213014, nueva config `cta_tarjeta_credito`).
- **Imputación opcional.** Σ imputaciones ≤ total; el remanente queda
  "a cuenta" del proveedor. Cada imputación se valida contra el **saldo
  pendiente** de la factura con lock (`FOR UPDATE`), server-side.
- **Saldo de factura** = total − Σ NC asociadas + Σ ND asociadas −
  Σ imputaciones de OPs confirmadas. Todo en la moneda de la factura; la
  imputación guarda `monto` (moneda OP) y `monto_factura` (moneda factura)
  convertidos por el TC de la OP.
- **Numeración OP-nnnn** server-side por trigger con advisory lock (molde
  `fn_bien_uso_nro` de la 073). No colisiona con órdenes de producción:
  su `nro` es texto libre (placeholder "OT-2024-001").
- **Asiento** lo arma la RPC (única fuente): debe Proveedores por el total,
  haber por cada medio agrupado por cuenta. `tipo 'auto-pago'`,
  `origen_tipo 'orden_pago'`, `origen_id` = OP, `comprobante_nro` = nro OP,
  `proveedor_id`. Los asientos `auto-pago` viejos (origen_tipo `pago`)
  siguen contando como pagos a cuenta en la cta cte.
- **Anular** = RPC `anular_orden_pago(id, motivo)`: asiento → anulado
  (nunca se borra), OP → anulada, cheques que creó → anulado. Bloquea si
  algún cheque ya fue debitado/rechazado (plata movida).
- **Cobros y Pagos, tab "Pago a proveedor"** abre el modal de OP (un solo
  flujo). `irAPagarFactura` abre la OP con esa factura ya imputada.
- **HSBC → BBVA:** la migración renombra 111003 sólo si todavía se llama
  "BANCO HSBC" (idempotente, respeta renombres manuales).
- **PDF de la OP** (jsPDF, mismo encabezado que remito/presupuesto):
  proveedor, facturas imputadas, medios (con nro de cheque y fecha de
  pago), total, a cuenta.

## Componentes

### Migración `074_ordenes_pago.sql`
1. `ordenes_pago` (nro, fecha, proveedor_id, moneda, tipo_cambio, total,
   estado confirmada/anulada, asiento_id, observaciones, motivo_anulacion).
2. `orden_pago_medios` (tipo caja/banco/cheque/tarjeta, monto,
   cuenta_contable_id, cuenta_bancaria_id, cheque_id, detalle).
3. `orden_pago_imputaciones` (factura_id → facturas_recibidas ON DELETE
   RESTRICT, monto, monto_factura).
4. Batería RLS completa + trg_audit en las tres.
5. `config_contable.cta_tarjeta_credito` (default 213014).
6. RPC `registrar_orden_pago(p_cabecera, p_medios, p_imputaciones)` → jsonb
   `{id, nro, asiento_id, asiento_numero}`.
7. RPC `anular_orden_pago(p_id, p_motivo)`.
8. `anular_factura_recibida` RE-EMITIDA (base 062): bloquea si la factura
   tiene imputaciones de OPs confirmadas.
9. Rename 111003 HSBC → BBVA.

### Puras (tests en `tests/ordenes-pago.test.js`)
- `saldoFacturaProveedor(f, facturas, imputaciones)` → `{total, ncnd,
  pagado, saldo}` en moneda de la factura.
- `convertirMontoImputacion(monto, monedaOP, tc, monedaFactura)`.
- `validarOrdenPago({total, medios, imputaciones, saldos})` → `{ok,
  errores, aCuenta}`.
- `computeCtaCteProveedores({proveedores, facturas, imputaciones,
  ordenesPago, asientos, asientoLineas})` → por proveedor `{saldoUSD,
  facturasPendientes, aCuentaUSD}`.
- `resumenMediosOP(medios)` → texto corto para la tabla ("Transf. + 2 ch").

### UI
- Compras → tab **Órdenes de pago**: stats, "+ Orden de pago", buscador,
  tabla (nro, fecha, proveedor, medios, imputado, a cuenta, total, asiento,
  PDF, anular).
- Modal `modal-orden-pago`: proveedor, fecha, moneda/TC, facturas
  pendientes con checkbox y monto, filas de medios, barra de totales.
- Facturas recibidas: columna **Saldo**.
- Proveedores: "Deuda USD" pasa a salir de `computeCtaCteProveedores`.
- Cashflow proyectado y alertas de compras usan el saldo de cada factura.
- Ctrl+K: acción "Nueva orden de pago".

### Fuera de alcance
Retenciones practicadas como agente (SICORE), pago de OPs con más de un
proveedor, y NC de proveedor sin factura asociada.
