# Factura directa con CAE (sin venta) — Pieza A — Diseño

**Fecha:** 2026-08-13
**Estado:** implementado · 6 tests nuevos + suite 174/174 verde · sin commitear a main (rama local). No se pudo probar end-to-end contra ARCA sin emitir un CAE real; la prueba real es la primera emisión del usuario.
**Rama:** `feat/factura-directa`

## Contexto

Hoy solo se puede emitir factura electrónica desde una venta registrada
(`emitirFactura(ventaId)`). El usuario necesita emitir facturas con CAE
**sin** registrar la venta — incluye el caso de "facturas preventivas" que
luego se revierten con NC y se re-facturan cuando la venta se concreta.

Descomposición acordada:
- **Pieza A (este spec):** factura directa con CAE, sin venta. Frontend puro.
- **Pieza B (spec aparte, después):** Nota de Crédito sobre una factura
  directa (hoy la NC entra solo desde una venta).

## Decisiones (confirmadas con el usuario)

- **Concepto:** solo productos (`concepto=1`). → **No toca la Edge Function.**
- **Moneda:** ARS o USD, elegible por factura. USD se convierte a pesos al
  TC BNA vendedor del día (igual que las ventas); a AFIP siempre va `PES`
  con `cotizacion_moneda=1`. Cuando es USD se deja nota del TC en
  `observaciones`.
- **Cliente:** de la lista de clientes (reusa CUIT + condición fiscal).
- **Lista de facturas directas:** botón que abre un modal-lista.

## Feasibilidad verificada

- `facturas_emitidas.venta_id` es **nullable** (FK opcional, `ON DELETE SET
  NULL`, migración 016). Se inserta con `venta_id=null`.
- La Edge Function acepta `venta_id` opcional (default null) y `concepto`
  configurable — sin cambios.
- `generarAsientoFactura(id, data, venta)` sólo usa `venta?.cliente` (con
  fallback); funciona pasándole `{cliente: nombre}`.

## Componentes

### Puros (testeables)
- `facturaDirectaItems(filas, tc)` — mapea filas `{descripcion, cantidad,
  precio, ivaPct}` a items del payload `{descripcion, cantidad, precio_unit,
  iva_pct}`, con `precio_unit = round(precio*tc, 2)` (tc=1 si ARS). Filtra
  filas incompletas (cantidad/precio ≤ 0). El precio ingresado es **neto**.
- `facturaDirectaTotales(items)` — `{neto, iva, total}` para mostrar en vivo
  (los importes que se guardan son los que devuelve AFIP).

### Orquestador (frontend, DOM/red — no unit-test)
- `emitirFacturaDirecta()` — lee el modal, resuelve cliente
  (`resolverClienteVenta`) y CUIT (`cuitParaFacturar`), letra
  (`tipoComprobanteVentaAFIP`), valida (≥1 ítem; Factura A ⇒ CUIT 11 díg.),
  obtiene TC si USD, arma payload (`venta_id:null`, `concepto:1`), POST a la
  Edge Function `/facturar`, inserta en `facturas_emitidas` (`venta_id:null`,
  nota de TC en `observaciones` si USD), genera asiento con `{cliente}`,
  notifica con el CAE.

### UI
- Página **Ventas**: botones **"+ Factura directa"** (abre
  `modal-factura-directa`) y **"Ver facturas directas"** (abre
  `modal-facturas-directas`).
- `modal-factura-directa`: cliente (datalist + autofill CUIT/condición/letra),
  moneda (ARS/USD, muestra TC si USD), ítems dinámicos (descripción · cant ·
  precio neto · % IVA) con total en vivo, observaciones, botón "Emitir
  factura (CAE)" con confirm de irreversibilidad.
- `modal-facturas-directas`: lista `facturas_emitidas` con `venta_id is null`
  (fecha, comprobante, doc receptor, total, CAE) + botón "Ver CAE"
  (`verFactura`). El botón NC llega en Pieza B.
- Estado de ítems en memoria `fdItems` + `renderFdItems()` (espeja
  `ventaItemsList` / `renderVentaItems`).

## Data flow

```
"+ Factura directa" → modal → emitirFacturaDirecta()
  → resolverClienteVenta + cuitParaFacturar + tipoComprobanteVentaAFIP
  → facturaDirectaItems(filas, tc)   (tc=1 ARS | cotización USD)
  → POST Edge Function /facturar  (venta_id:null, concepto:1, moneda:PES)
  → POST facturas_emitidas (venta_id:null)
  → generarAsientoFactura(id, data, {cliente})
```

## Tests

`tests/factura-directa.test.js` (harness `node --test`):
- `facturaDirectaItems`: ARS (tc=1) sin conversión; USD (tc>1) convierte;
  filtra filas vacías; corta descripción a 200; iva_pct por línea.
- `facturaDirectaTotales`: neto/iva/total con redondeo; multi-alícuota.
- Escenario: cliente RI + ítems → letra A y doc 80; sin CUIT → bloquea A.

## Riesgo

**Frontend puro.** No toca la Edge Function ni la DB (`venta_id` ya
nullable). No afecta el circuito de ventas ni el path legal existente.
Aditivo. Deploy a prod = merge a `main` (Netlify), sólo con OK del usuario.

## Fuera de alcance (Pieza B)

Generalizar la NC para emitirla sobre una factura directa (sin venta):
`openNotaCredito` desde una `factura_emitida`, `emitirNotaCredito` sin
requerir el objeto venta, `generarAsientoNC` sin venta.
