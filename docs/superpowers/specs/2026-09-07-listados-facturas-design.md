# Listados de facturas emitidas y recibidas con filtros — Diseño (sprint 3 de la hoja 2026-09-07)

**Fecha:** 2026-09-07
**Estado:** LIVE en producción 2026-09-07 (sin migración; merge a main y deploy Netlify) · 10 tests nuevos, suite 267/267 verde · pendiente user: usarlo con datos reales y avisar si falta alguna columna o filtro.
**Origen:** hoja manuscrita: PAGOS "listar FC por proveedor y por fecha (informes)" + VENTAS "cómo acceder al listado de FC, ordenar".

## Contexto

- **Ventas:** las facturas emitidas (`facturas_emitidas`) no tienen listado propio. Están repartidas entre el botón CAE de cada venta, el modal "Ver facturas directas" (sólo las sin venta) y los exportables Subdiario/IVA ventas. No se pueden filtrar por cliente ni por fecha en un solo lugar.
- **Compras → Facturas recibidas:** hay buscador por texto (nro, proveedor, OC) pero no filtro por fecha ni por proveedor, ni exportable de la lista.
- **Orden por columna:** ya existe en todas las tablas (commit d5ced67: click en el encabezado alterna ▲/▼, se reaplica tras cada render). No está documentado en el manual; por eso la hoja pregunta "cómo ordenar".

## Decisiones

- **Nueva página Ventas → Facturas emitidas** (`page-femitidas`, clave `femitidas`, mismo permiso que el módulo Ventas). Lista **todas** las facturas, NC y ND emitidas con CAE (con venta, directas y libres). Reemplaza al modal "Ver facturas directas", que se elimina.
  - Datos: `facturas_emitidas` pasa a cargarse como tabla del `TBL` (global `facturasEmitidas`, sin `qr_url`/`observaciones`) y se recarga tras cada emisión.
  - Filtros: texto (cliente, CUIT, número, CAE, remito), **cliente** (select), **tipo** (Todos / Facturas / NC / ND), **desde / hasta**. Todos combinables; el orden por columna es el global.
  - Columnas: Fecha · Comprobante (FA/NC/ND-letra PV-nro) · Cliente · CUIT · Origen (remito de la venta con link, "Directa", o la asociación de la nota: "s/ FA A 0004-…", período, comprobante externo) · Neto · IVA · Total (NC en negativo y rojo) · CAE · Asiento · acciones (Ver CAE; NC/ND sobre facturas; ir a la venta).
  - Stats de lo filtrado: comprobantes, facturado (Σ FA), NC, ND, **neto** (FA − NC + ND), en pesos (los importes de `facturas_emitidas` ya están en pesos: las USD se emiten con `moneda 'PES'` convertidas al TC).
  - Botón **Excel** exporta la lista filtrada (CSV `;` con coma decimal, como el resto).
- **Compras → Facturas recibidas:** se agregan **proveedor** (select), **tipo** (Todos / Facturas / NC / ND) y **desde / hasta** (por fecha de emisión) al buscador existente, más botón **Excel**. Los stats pasan a reflejar la lista filtrada (eso es lo que pide "informes": total de un proveedor en un período).
- **Manual:** sección 3 explica el orden por columna; 7.4 y nueva 8.4 "Facturas emitidas" describen los filtros.

## Componentes

### Puras (tests en `tests/listados-facturas.test.js`)
- `filtrarFacturasEmitidas(list, {texto, clienteId, tipo, desde, hasta}, {ventas, clientes})` → filas enriquecidas `{f, cliente, cliente_id, venta, clase, signo}`; `tipo` ∈ `''|'fa'|'nc'|'nd'`.
- `resumenFacturasEmitidas(rows)` → `{n, fa, nc, nd, neto}`.
- `filtrarFacturasRecibidas(list, {texto, proveedorId, tipo, desde, hasta}, {proveedores, ordenesCompra})` → filas `{r, prov, oc, signo}`; `tipo` ∈ `''|'factura'|'nota_credito'|'nota_debito'`.
- `origenFacturaEmitida(f, venta)` → texto corto del origen ("Remito R-0012", "Directa", "s/ …", "período …").

### UI
- `renderFacturasEmitidas()` (en `PAGE_RENDERS.femitidas`), `exportFacturasEmitidasCSV()`, `_femFiltros()`.
- `renderFacturasRecibidas(filter)` usa `filtrarFacturasRecibidas` + `_frFiltros()`; `exportFacturasRecibidasCSV()`.
- Los selects de cliente/proveedor se repueblan en cada render conservando la selección.

### Fuera de alcance
Paginación server-side (PostgREST devuelve hasta 1000 filas; alcanza para años de facturación de Vitalmet), listados por vendedor, y cambios en los exportables Subdiario/IVA.
