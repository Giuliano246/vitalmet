# Atajo "Cobrar" / "Pagar" desde Ventas y Compras

**Fecha:** 2026-08-05 · **Estado:** aprobado (opción A)

## Problema

Para registrar cómo se cobra una venta (efectivo/banco/cheque) hay que ir a
Contabilidad → Cobros y Pagos y cargar todo "en frío": elegir el cliente,
tipear el monto, etc. Lo mismo para pagar una factura de compra. El formulario
existente funciona bien (métodos, retenciones, cheques, asiento automático)
pero no hay ningún camino directo desde la venta o la factura.

## Solución

Botones-atajo que abren el formulario existente con todo precargado. **Cero
lógica nueva de negocio**: la contabilidad, la imputación FIFO por cliente y
el flujo de cheques quedan exactamente igual.

### 1. Ventas → botón "Cobrar"

- En cada fila de la tabla de Ventas cuyo estado sea `entregado` o
  `facturado`, se agrega un botón **Cobrar** (ícono $, color verde) junto a
  los botones existentes.
- Al tocarlo, `irACobrarVenta(ventaId)`:
  - navega a la página `cobpag` (`showPage('cobpag')`),
  - `switchCobPag('cobro')`,
  - fecha = hoy,
  - cliente preseleccionado en `cp-tercero-sel` (si el nombre no está en la
    lista de clientes, cae en "Otro…" con el texto cargado — mismo criterio
    de match por nombre que ya usa el formulario),
  - monto = importe de la venta (suma de ítems), editable,
  - observaciones = `Remito <nro_remito>`,
  - moneda queda en USD con TC auto (comportamiento actual del formulario).
- El usuario solo elige el **método** (caja/banco/cheque), ajusta el monto si
  el pago es parcial o agrupa varios remitos, y toca Registrar.

### 2. Compras → botón "Pagar"

- En cada fila de Facturas recibidas cuyo `tipo` sea factura (no NC/ND) se
  agrega un botón **Pagar**.
- `irAPagarFactura(facturaId)`: igual que arriba pero `switchCobPag('pago')`,
  proveedor precargado, monto = total de la factura, moneda = la de la
  factura, observaciones = `Factura <nro>`.

## Qué NO cambia

- No se agrega estado "cobrada/pagada" a ventas ni facturas: el saldo vive en
  la cuenta corriente (imputación FIFO por tercero), como hasta ahora.
- No se persiste nada nuevo: sin migración, solo frontend (`index.html`).
- Permisos: la página Cobros y Pagos ya está protegida por el permiso de
  Contabilidad; el atajo solo navega, no lo elude.

## Testing

- Los tests node existentes deben seguir en verde (no se toca lógica pura).
- Smoke manual: Cobrar desde una venta entregada → formulario precargado →
  Registrar → asiento y cta. cte. correctos. Ídem Pagar desde una factura.
