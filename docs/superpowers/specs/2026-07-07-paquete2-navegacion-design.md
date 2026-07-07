# Paquete 2 — Navegación y productividad: palette, deep-links, sort, fechas, sticky

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano (diseño conversado en sesión)
**Contexto:** segundo paquete del roadmap de mejoras (P1 Producción LIVE 2026-07-06). Todo frontend, sin migraciones.

## 2A. Command palette (Ctrl+K / Cmd+K)

- Modal `#modal-palette` (overlay estándar del sistema): input arriba, lista de resultados agrupados por categoría abajo. Botón de búsqueda en el sidebar (acceso mobile).
- Atajos: `Ctrl+K`/`Cmd+K` abre SIEMPRE (listener `keydown` global con preventDefault, incluso con foco en un input); `Esc` cierra solo el palette; `↑/↓` mueve la selección; `Enter` ejecuta el ítem seleccionado.
- **Índice en memoria** construido al abrir desde los globals de `loadAll` (sin red):
  - clientes → `{cat:'Clientes', label:razon social, page:'clientes', id}`
  - ventas → `nro_remito · cliente · total` → page `ventas`
  - presupuestos → `nro · cliente · estado` → `presupuestos`
  - ops → `nro · pieza` → `op`
  - barras → `lote · material` → `mp`
  - pts → `lote · pieza` → `pt`
  - certs → `nro · material · colada` → `cert`
  - proveedores → `nombre` → `compras`
  - cheques → `nro · tercero · monto` → `cheques`
  - NCRs → `nro/desc` → `ncr`
  - Páginas: labels de `GROUP_TABS` + nav (prefijo "Ir a")
  - Acciones: Nueva venta / Nuevo presupuesto / Nueva OP / Nueva OC (abren su modal)
- **Matching**: función pura `paletteMatch(query, items) → items ordenados`. Multi-término AND (cada término debe matchear), scoring: match exacto de número > empieza-con > contiene. Máx 4 resultados por categoría, categorías en orden fijo. Con query vacía: acciones + páginas frecuentes.
- Enter en registro → `showPage(page, id)` (deep-link 2B). Enter en acción → ejecuta y cierra.
- Tests: `paletteMatch` en `tests/palette.test.js` (harness vm).

## 2B. Deep-links entre registros

- `showPage(p, recordId)` acepta segundo parámetro opcional. Guarda `_pendingHighlight={page:p, id:recordId}`; al final de `renderPage(p)` (hook único) se resuelve: busca `[data-id="<id>"]` dentro de la página, `scrollIntoView({block:'center'})` + clase `.row-flash` (animación de fondo accent 2s; anulada por `prefers-reduced-motion`, que ya tiene bloque global).
- `data-id` en las filas (`<tr data-id="${x.id}">`) de: ventas, presupuestos, clientes, ops, mp (barras), pt, cert, compras (OCs), cheques, ncr.
- Cross-links clickeables (span con estilo link, `onclick="showPage('...','id')"`):
  - cliente en fila de venta → ficha en `clientes`
  - badge presupuesto en fila OP (agregado en P1) → `presupuestos`
  - badge "N OPs" en fila presupuesto (P1) → `op` (primera OP vinculada)
- El "Ver" del digest queda a nivel módulo (sin cambio en esta versión).

## 2C. Ordenamiento de tablas — global por delegación

- Un listener global (delegación en `document`) sobre clicks en `th` de cualquier `thead`: si el th tiene texto (no columnas de acciones vacías), ordena las filas actuales del `tbody`.
- Comparador puro `compareCells(a, b, tipo)` + detector `detectColType(values) → 'num'|'fecha'|'texto'`: números con `US$/%/.,`, fechas `YYYY-MM-DD` o `DD/MM/YYYY`, resto texto (localeCompare es-AR). Tests en `tests/sort.test.js`.
- Orden DOM: reordena los `<tr>` existentes (no toca los datos ni los renders). Filas de empty-state (colspan) se ignoran.
- Estado `_tableSorts = { [tablaKey]: {col, dir} }` donde tablaKey = id del tbody. Toggle asc→desc→asc. Indicador `▲/▼` inyectado en el th + `aria-sort` en el th activo.
- Re-aplicación: al final de `renderPage(p)`, para cada tbody de la página con sort guardado, re-ordenar. (Un solo hook, ningún render se toca.)

## 2D. Filtros de fecha

- Inputs `type="date"` desde/hasta junto al search-box en: **ventas, presupuestos, compras (OCs), op, cheques**. Ids: `<mod>-fdesde`, `<mod>-fhasta`, con `onchange` que re-llama el render del módulo.
- Cada render lee sus inputs (si existen) y filtra por su campo fecha: ventas→`fecha`, presupuestos→`fecha`, OCs→`fecha`, ops→`fecha`, cheques→`fecha_emision` (verificar nombre real al implementar; si difiere, usar el del módulo). Filtro combinable con el texto (AND).
- Helper puro `enRango(fecha, desde, hasta) → bool` (strings YYYY-MM-DD, límites inclusive, vacío = sin límite). Test en `tests/sort.test.js` o propio.

## 2E. Sticky headers

- CSS global: `.table-wrap{max-height:calc(100vh - 230px);overflow:auto}` y `thead th{position:sticky;top:0;z-index:2}` (el th ya tiene fondo de superficie; verificar que quede opaco — si es transparente, darle `background:var(--surface)`).
- Verificar que los `estadoSelect` inline y dropdowns no queden por debajo (z-index de th = 2, contenido normal sin z-index).
- Mobile: mantener el comportamiento actual (el max-height aplica igual; si molesta en ≤768px, override `max-height:none` en la media query).

## Orden de implementación

2E (CSS) → 2C (sort global + tests) → 2B (deep-links + data-id + cross-links) → 2A (palette + tests, usa 2B) → 2D (filtros de fecha). Commit por bloque; deploy (push) al cierre de 2E+2C, de 2B+2A y de 2D; verificación en prod entre deploys. Reglas CLAUDE.md vigentes (esc(), node --check, node --test, voseo).

## Fuera de alcance

Digest "Ver" a nivel registro, saved views/facetas, paginación de tablas (P5), export ampliado.
