# Paquete 4 — Formularios y UX: validación por campo, modales, accesibilidad

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano
**Alcance acordado:** SIN cards mobile (casi no usan el celular — queda fuera). Sin migraciones.

## 4A. Validación por campo con foco

- Helpers globales:
  - `marcarInvalido(id)`: borde `var(--red)` + glow suave; se limpia solo con `input`/`change`.
  - `validarCampos(pares)`: recibe `[[id, condiciónOk, mensaje], …]` → si hay inválidos: los marca todos, enfoca el primero, `notify(mensajeDelPrimero,'err')`, devuelve `false`; si no, `true`.
- Reemplazar los guard-clauses toast-genérico de: `saveVenta`, `saveOP`, `savePresupuesto` (o su save real), `registrarCobroOPago`, recepción de compra, alta de barra MP, alta de certificado, `saveOperacionPaso`, `saveTemplate`. Cada condición existente se traduce 1:1 (no se agregan validaciones nuevas).

## 4B. Modales: Esc, foco inicial y guard de cambios

- **Esc global**: listener `keydown` que cierra el último `.modal-overlay.open` del DOM (si el palette está abierto, su handler propio tiene prioridad — el global lo ignora).
- **Foco inicial**: `openModal(id)` enfoca el primer `input, select, textarea` visible del modal (con `setTimeout` corto para la animación).
- **Dirty-guard** en `modal-venta`, `modal-presupuesto`, `modal-op`: flag `_modalDirty[id]` que se activa con `input`/`change` dentro del modal (delegación), se resetea al abrir y al guardar. `closeModal(id)` y el click en backdrop consultan: si dirty → `confirm('Tenés cambios sin guardar. ¿Cerrar igual?')`.

## 4C. Accesibilidad

- `#notif`: `role="status"` + `aria-live="polite"` en el HTML.
- `openModal`: setear `role="dialog"` y `aria-modal="true"` en el `.modal` interno.
- Contraste dark: `--text3` de `#8a8073` → `#98917f` (un paso más claro; light theme queda igual).

## Verificación

`node --check` + suite de 48 tests sin regresiones + prueba manual: form de venta vacío marca y enfoca el campo; Esc cierra; modal sucio pide confirmación; VoiceOver anuncia el toast. Un solo deploy al cierre del paquete.

## Fuera de alcance
Cards mobile, focus-trap completo, validación en tiempo real (on-blur), error summary.
