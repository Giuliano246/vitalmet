# Paquete 5 — Performance: recargas dirigidas, refetch on focus, lazy extracto

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano
**Problema (auditoría SEV-1):** `loadAll()` = 38 GETs full-table, re-ejecutado en ~70 call sites (después de casi cada guardado). Escala mal con `asientos`/`asiento_lineas`/`ventas` creciendo sin límite.

## Restricciones descubiertas en la exploración

- `asientoLineas` NO es lazy-loadeable: `_cobroEnUSD` → `computeCtaCte` → digest de cobranzas + generador de recordatorios (P3) la necesitan al arranque.
- Las tablas de calidad (`registrosCalidad`, `pqpPlantillas/Ops`, `documentosControlados`, `calibraciones`) las consumen los modales de OP y el digest → quedan en el arranque.
- Único candidato limpio a lazy: `extracto_bancario` (solo Conciliación).

## 5A. Registro de tablas + reload dirigido

- `loadAll()` se refactoriza sobre un registro: cada entrada define `{q: querystring, set: rows=>global=rows, nombre: 'para _loadFail'}`. `loadAll()` = iterar TODO el registro con `Promise.all` (comportamiento, orden de asignación, `_loadFail`, fallbacks `||[]` y banner idénticos a hoy).
- `reload(...nombres)`: baja solo esas tablas con las mismas queries/set/_loadFail.
- Los ~70 `await loadAll()` se reemplazan por `await reload(...)` con las tablas que la mutación toca. **Regla superset**: ante la duda, incluir tablas de más. Mantienen `loadAll()` completo: init de login, `retryLoad`, `convertirPresupuesto`, operaciones de cierre/apertura de ejercicio, ajuste por inflación, importaciones masivas (XLSX), y cualquier sitio donde el mapeo no sea obvio.
- Los casos especiales del loadAll actual se respetan: `get_usuarios_empresa` (RPC), `configContable` (singleton `[0]||null`), selects con embed (`ventas` con items, `ordenes_produccion` con barras, etc.) — las queries se copian VERBATIM al registro.

## 5B. Refetch al volver a la pestaña

- Global `_lastLoadAllAt` (timestamp seteado al final de `loadAll`).
- Listener `visibilitychange`: al volver a visible, si pasaron >5 min desde la última carga completa → `loadAll()` + `renderAll()` en background (sin bloquear la UI), con guard para no solapar cargas.

## 5C. Lazy-load de extracto_bancario

- Sale del registro de arranque; pasa a `ensureExtractoData()` (patrón Eficiencia/Mailings) invocado por el render de Conciliación y por `reload('extracto_bancario')` cuando la página ya lo cargó.
- `importarExtracto`/`conciliarLinea` siguen funcionando: sus recargas pasan por el mismo camino.

## Fuera de alcance (documentado para el futuro)

- **Acotar `asientos`/`asiento_lineas`/`ventas` por fecha/ejercicio**: rompería la cta. cte. FIFO (histórico completo) y los balances si se hace mal. Disparador para retomarlo: `asientos` > ~5.000 filas o payload de arranque > 3 MB.
- Virtualización de tablas, realtime de Supabase.

## Verificación

Suite completa (48 tests) en cada task + `node --check`. Manual en prod por bloque: guardar un insumo dispara 1 GET (verificable en Network), la venta actualiza stock PT y cta cte, conciliación carga su extracto on-demand, y volver a la pestaña tras >5 min refresca solo.
