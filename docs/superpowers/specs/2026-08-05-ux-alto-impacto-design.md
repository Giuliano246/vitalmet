# Mejoras UX de alto impacto (auditoría 2026-08-05)

**Fecha:** 2026-08-05 · **Estado:** aprobado ("resolvé los de alto impacto")

Auditoría UI/UX de tres revisores (visual, formularios/feedback, navegación/
mobile) sobre `index.html` y `planta.html`. Este spec cubre los 6 hallazgos de
alto impacto; el resto queda listado en la conversación para futuros paquetes.

## 1. Filtro de búsqueda desincronizado

`renderAll()`/`renderPage()` renderizan sin argumento (`filter=''`) mientras el
texto tipeado sigue visible en el buscador. **Fix:** `renderPage` re-dispara el
evento `input` de todo `.search-box input` con valor dentro de la página
renderizada — el `oninput="renderX(this.value)"` existente re-filtra la tabla.

## 2. Guard de cambios sin guardar en todos los modales

`MODALES_CON_GUARD` cubría solo venta/presupuesto/OP. **Fix:** se invierte la
lógica — `MODALES_SIN_GUARD` excluye los modales de solo lectura o efímeros
(palette, ficha-cliente, kardex, qr-planta, tiempos); todo el resto pide
confirmación si `_modalDirty`. Los cierres programáticos post-guardado (los
`closeModal('modal-x')` literales del script, 50 sitios) pasan `force=true`;
los del HTML (X/Cancelar) y Escape/backdrop quedan guardados.

## 3. Deep-linking por hash

`showPage()` escribe `location.hash` vía `history.replaceState` (sin spam de
historial); al iniciar sesión se restaura la página del hash, y un listener de
`hashchange` navega si pegan un link con la app abierta. F5 ya no vuelve al
dashboard. Mismo criterio que el `?op=` de planta.html.

## 4. Errores técnicos traducidos

`msgError(e)` centraliza la traducción de errores Postgres/Supabase/red
(duplicados, FK, RLS, check, sin conexión, sesión vencida) a castellano; los
mensajes de las RPCs (ya en castellano) pasan sin tocar. Reemplaza 77 catch
que mostraban `e.message` crudo.

## 5. Anti doble-tap en Modo Planta

`iniciar`/`pausar`/`finalizar` en planta.html: flag global `accionBusy` +
deshabilitado inmediato del botón tocado ("…") hasta que `loadOP` re-renderiza.
Evita time-entries duplicados con wifi lento.

## 6. Navegación por teclado

`.nav-item`, `.tab` y `.subtab` (divs con onclick) reciben `tabindex="0"` +
`role="button"`, un delegado global activa con Enter/Espacio, y se agrega
`:focus-visible` para tabs/subtabs (nav-item ya lo tenía).

## Qué NO cambia

- Sin migraciones; solo frontend + un stub en `tests/_harness.js`
  (`window.addEventListener`/`history` para el listener nuevo).
- Permisos, RLS y lógica de negocio intactos.

## Testing

- `node --test tests/*.test.js` → 120 pass.
- Syntax check de los `<script>` de ambos HTML con `new Function`.
- Smoke manual sugerido: buscar un cliente → editar y guardar → el filtro
  persiste; tipear en un modal → Escape → confirm; F5 en Cta. corriente;
  guardar cualquier alta → cierra sin confirm; doble-tap INICIAR en planta.
