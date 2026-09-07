# NC/ND de venta sobre cualquier factura y NC/ND libre — Diseño (sprint 2 de la hoja 2026-09-07)

**Fecha:** 2026-09-07
**Estado:** implementado en rama `feat/notas-venta` (2026-09-07) · 15 tests nuevos, suite 257/257 verde · Edge Function tipada con `deno check` · pendiente: correr la 075 en el SQL Editor, redeployar la Edge Function, mergear y probar E2E (primera NC/ND real contra ARCA).
**Origen:** hoja manuscrita, sección VENTAS: "cómo hago NC/ND no a partir de FC" + Pieza B pendiente del spec de factura directa (2026-08-13).

## Contexto

Hoy la NC de venta sólo se emite desde una **venta facturada** (`openNotaCredito(ventaId)`): las facturas directas (sin venta) no tienen botón, no existe la ND de venta, y no hay forma de emitir una NC/ND que no referencie una factura del ERP. ARCA (RG 4540 + WSFEv1) exige que toda NC/ND lleve **comprobantes asociados** (`CbtesAsoc`) **o un período asociado** (`PeriodoAsoc` FchDesde/FchHasta): esa segunda vía es la respuesta al punto de la hoja.

## Decisiones

- **Un solo modal `modal-nota-credito` para NC y ND sobre una factura del ERP** (con venta o directa), con toggle de clase. Tipos AFIP: NC {A:3, B:8, C:13, M:53}, ND {A:2, B:7, C:12, M:52}. La NC mantiene el tope server-side (`nc_reservar` + `trg_nc_tope`); la ND no tiene tope y **no cuenta** para el tope de las NC (migración 075 re-emite ambos filtrando por tipo NC).
- **Cliente de la nota:** por la venta si existe; si no (factura directa), por CUIT (`doc_nro`) contra la lista de clientes (`resolverClienteFactura`, pura).
- **NC/ND libre (`modal-nota-libre`):** cliente de la lista, clase NC/ND, moneda ARS/USD (USD → pesos al TC BNA vendedor como la factura directa), ítems con descripción libre (reusa `facturaDirectaItems`/`facturaDirectaTotales`), y **asociación** obligatoria: *Período* (desde/hasta → `PeriodoAsoc`) o *Comprobante externo* (tipo/PV/número/fecha de una factura propia emitida fuera del ERP → `CbtesAsoc`). Se guarda con `venta_id` y `factura_asociada_id` nulos + columnas nuevas `periodo_asoc_desde/hasta` y `cbte_asoc_externo`.
- **Asiento único para ambas clases** (`armarLineasNota`, pura): NC = debe Ventas + IVA Débito / haber Deudores (`tipo 'auto-nc'`, `origen_tipo 'nota-credito'`); ND = debe Deudores / haber Ventas + IVA Débito (`tipo 'auto-nd'`, `origen_tipo 'nota-debito'`). `computeCtaCte` suma la ND como cargo (vence el mismo día). Backfill (`facturasSinAsiento`, `regenerarAsientosFaltantes`) cubre ND.
- **Edge Function:** `FacturaReq.periodo_asociado?: {desde, hasta}`; una NC/ND exige `comprobantes_asociados` **o** `periodo_asociado`; `<ar:PeriodoAsoc>` va después de `<ar:Iva>` (orden del WSDL). Deploy: `npx supabase functions deploy facturacion --no-verify-jwt` (lo corre el usuario: no hay login de CLI en esta máquina).
- **Entradas:** botón "NC/ND" en la fila de ventas facturadas, en cada factura de "Ver facturas directas" (que pasa a listar también las notas) y botón "+ NC/ND libre" en la toolbar de Ventas. Ctrl+K: "Nueva NC/ND libre".

## Componentes

### Migración `075_notas_venta.sql`
1. `facturas_emitidas.periodo_asoc_desde/hasta date`, `cbte_asoc_externo text`.
2. `fn_nc_tope` RE-EMITIDA (base 069): sólo aplica tope a tipos NC y suma sólo NC.
3. `nc_reservar` RE-EMITIDA (base 069): la suma de acreditado filtra tipos NC.

### Puras (tests en `tests/notas-venta.test.js`)
`NOTA_TIPOS`, `tipoNota(tipoFactura, clase)`, `claseNota(tipo)`, `computeSaldoNC` (ignora ND), `armarLineasNota`, `resolverClienteFactura`, `validarAsociacionNota`, `tipoNotaPorLetra`.

### Fuera de alcance
NC/ND de proveedor sin factura asociada (compras), notas con más de un comprobante asociado, moneda extranjera real ante ARCA (siempre `PES`).
