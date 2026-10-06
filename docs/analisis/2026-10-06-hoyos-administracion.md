# Hoyos del circuito administrativo — relevamiento 2026-10-06

Origen: cuatro observaciones de la contadora (5/10/2026) y un barrido completo de `index.html`,
migraciones y Edge Functions buscando casos del mismo tipo. Todo sale de leer el código; nada
se probó contra la base de producción.

## Resuelto en la rama `feat/retenciones-libros-op` (migración 086)

| # | Qué pasaba | Qué se hizo |
|---|---|---|
| 1 | No se podían practicar retenciones al pagar | Regímenes de retención, regímenes por proveedor, cálculo en la OP (RG 830 acumulado mensual, escala, por pago), certificado PDF, pestaña Compras → Retenciones, exportable |
| 2 | La OP "desaparecía" después de registrarla | **Causa real: ids HTML duplicados.** El listado de órdenes de pago se dibujaba en la tabla de Órdenes de producción y la pestaña quedaba vacía; la fecha de la OP tampoco se leía del campo visible (salía siempre con la fecha de hoy). Ids renombrados (`opg-*`) + test que impide repetir ids |
| 3 | Diario y Mayor sin impresión | PDF con hojas numeradas y transporte, más Excel |
| 4 | IVA ventas/compras sin versión imprimible | PDF apaisado desde Exportables, con transporte y totales |
| — | Pantallas de consulta sin ninguna salida (balances, estado de resultados, ratios, conciliación, etc.) | Botonera Imprimir / Excel genérica en 23 pantallas |
| — | Comprobantes sin vínculo entre sí | Links asiento ↔ OP ↔ factura ↔ cheque; NC/ND muestran su factura; la factura muestra con qué OP se pagó |
| — | Sin recibo de cobranza | Recibo PDF al registrar el cobro y desde la lista |
| — | Cobros y Pagos mostraba sólo los últimos 30, sin buscar | Buscador, filtros, anulados visibles |
| — | Sin cuenta corriente de proveedores | Detalle por proveedor con saldo por moneda, imprimible |
| — | Retenciones sufridas invisibles en pantalla y vivas tras anular el cobro | Listado mensual en Cobros y Pagos; las de cobros anulados ya no suman en el exportable ni en la posición de IVA |
| — | IVA ventas y posición de IVA incluían facturas de homologación | Filtran `afip_environment = produccion`, igual que el Libro IVA Digital |

## Pendiente — requiere sprint propio y definiciones de la contadora

Prioridad alta:

1. **Cuenta corriente de clientes sobre comprobantes.** Hoy se arma con `ventas.total` en USD y cobros convertidos al TC del cobro: mezcla bases y monedas, un cobro en pesos sin TC no baja la cuenta, y las facturas directas no generan cargo. Rehacer `computeCtaCte` sobre `facturas_emitidas`.
2. **Recibo con imputación a facturas y varios medios** (espejo de la 074 del lado ventas): tablas `recibos` / `recibo_medios` / `recibo_imputaciones`, saldo por factura emitida. Destraba diferencias de cambio y anticipos de clientes.
3. ~~PDF de factura / NC / ND con CAE y QR.~~ **Hecho el 2026-10-06 (migración 087):** botón PDF por comprobante y PDF de todos los filtrados; el detalle se guarda en `facturas_emitidas.items` desde la bitácora de ARCA.
4. **Factura de Crédito Electrónica MiPyME.** No hay tipos FCE en el frontend ni en la Edge Function. Confirmar si algún cliente grande ya la exige.
5. **Liquidación mensual de IVA.** La posición no arrastra saldos del período anterior y no hay asiento de liquidación.
6. **Ingresos Brutos mensual.** No hay base por jurisdicción ni exportable; clientes sin provincia.
7. **Gastos e impuestos bancarios.** El asiento desde el extracto admite una sola contracuenta: el IVA de comisiones y las percepciones bancarias no llegan a IVA compras ni a la posición.

Prioridad media:

8. Aplicar después un **pago a cuenta** o una **NC de proveedor** a una factura (hoy la factura sigue figurando impaga).
9. **Endoso de cheques de terceros** a proveedores como medio de la OP; elegir cuenta bancaria y fecha al depositar.
10. **Cuenta bancaria en el cobro** (hoy siempre la cuenta por defecto).
11. **Diferencias de cambio** al cobrar o pagar a un TC distinto del comprobante.
12. **Datos fiscales en maestros** (condición y número de IIBB, jurisdicción, CBU) y datos de la empresa configurables en lugar de escritos en cada PDF.
13. **Archivo de importación de retenciones para ARCA** (SICORE / SIRE): hoy sale el listado en Excel; el TXT se hace cuando la contadora confirme aplicativo y diseño de registro.

Prioridad baja: facturar en USD y servicios; anticipos de clientes; planilla resumen de liquidación de sueldos; historial de conteos físicos; ABM de retenciones sufridas con fecha de certificado propia.
