# Modo Planta — Tiempos de producción desde el móvil

**Fecha:** 2026-07-12
**Estado:** Aprobado (diseño + lockdown RLS)

## Objetivo

Que los operarios en planta registren los tiempos de producción (iniciar / pausar / finalizar operaciones de una OP) desde un celular, escaneando un QR impreso en la carpeta de la orden. Sin atribución por persona: solo importa el tiempo por operación/máquina.

## Contexto

El ERP ya captura tiempos por operación (`op_operaciones` + `op_time_entries`, migraciones 001 y 047) con multi-timer simultáneo y análisis de paradas por motivo. Hoy los timers se operan solo desde el ERP de escritorio. Este proyecto agrega la puerta de entrada móvil; **no cambia el modelo de datos de tiempos**.

## Decisiones tomadas

| Decisión | Elección |
|---|---|
| Usuario | Operarios en planta (celular propio o compartido) |
| Identidad | No se atribuye a personas — cuenta compartida `planta` |
| Descubrimiento de la OP | QR impreso por OP (lista de OPs en-proceso como respaldo) |
| Arquitectura | `planta.html` standalone en el mismo repo/Netlify (NO tocar el index.html salvo el botón QR) |
| Seguridad | Lockdown RLS del usuario planta (migración 052) — solo tablas de producción |

## Componentes

### 1. `planta.html` (nuevo, ~400-500 líneas)

Archivo standalone en la raíz del repo, servido en `https://erp.vitalmetsa.com/planta.html`. Vanilla JS + CSS embebido, mobile-first, botones grandes aptos para taller. Única dependencia: Supabase REST (mismos endpoints `fetch` que el ERP; se copian los helpers mínimos `GET/POST/PATCH`, no se importa nada del index.html).

**Rutas (por query string):**
- `?op=<orden_id>` — pantalla de la OP: encabezado (nro, pieza, cantidad, estado) + lista de operaciones ordenadas, cada una con cronómetro y acciones.
- Sin parámetro — lista de OPs con `estado='en-proceso'` (nro, pieza, cantidad); tocar una navega a `?op=`.

**Acciones por operación (semántica idéntica al escritorio):**
- **▶ Iniciar:** cierra la entry `pausa` abierta de esa operación (PATCH por filtro), POST entry `productivo` (`empresa_id`, `operacion_id`, `operario_id` = usuario planta, `started_at`), y si el paso estaba `pendiente` lo pasa a `en_curso`.
- **⏸ Pausa:** exige motivo — misma botonera de 8 motivos del ERP (Setup / cambio herramienta, Almuerzo / descanso, Fin de turno, Falta de material, Rotura de máquina, Reproceso / control, Esperando operario, Otro). Cierra la `productivo` abierta y crea entry `pausa` con motivo.
- **■ Finalizar:** confirmación, cierra todas las entries abiertas del paso y marca `estado='completada'`.

**Reglas:**
- Paso `completada`: sin acciones.
- Paso con `tipo_punto` hold/witness sin `signoff_at`: se muestra bloqueado ("requiere liberación de calidad") — la firma sigue siendo exclusiva del ERP de escritorio.
- El índice único `ux_op_time_entries_abierta` (migración 047) es la garantía de integridad ante operación concurrente planta/escritorio; los errores 409/23505 se muestran como "ese paso ya tiene un timer corriendo" y se re-sincroniza.
- Cronómetros con tick de 1 s; re-fetch de datos al recuperar el foco (`visibilitychange`) y tras cada acción.
- Textos en español argentino (voseo), igual que el ERP.

**Auth:** login Supabase (email + password) con la cuenta compartida; sesión persistida en localStorage (login una sola vez por dispositivo). Sin registro ni recupero de clave en esta pantalla.

### 2. Botón "QR planta" en el ERP (`index.html`)

En el modal Tiempos de la OP (`openTiempos`): botón que genera el QR de `https://erp.vitalmetsa.com/planta.html?op=<orden_id>`, lo muestra en pantalla y lo descarga como PDF (jsPDF, ya presente) con nro de OP y pieza como rótulo, para imprimir y abrochar a la carpeta de la OP. Lib de QR desde cdnjs (mismo origen ya permitido por el CSP de `netlify.toml`; verificar al implementar y agregar el origen si hiciera falta — regla del repo).

### 3. Migración 052 — usuario planta + lockdown RLS

- Columna `usuarios.es_planta boolean NOT NULL DEFAULT false` (o equivalente según el esquema real de `usuarios`).
- Función `public.es_planta()` (STABLE, `SET search_path = public`): devuelve si el usuario del JWT está marcado como planta.
- Guard sobre las policies `tenant_isolation` de **todas** las tablas con RLS excepto la whitelist, agregando `AND NOT public.es_planta()` (implementado con un DO-loop idempotente sobre `pg_policies`).
- Whitelist del usuario planta:
  - `ordenes_produccion`: SELECT.
  - `op_operaciones`: SELECT + UPDATE. (RLS no restringe por columna: la UI de planta solo toca `estado`, y se acepta que el usuario planta técnicamente podría actualizar otras columnas de esta tabla — riesgo bajo y acotado a producción.)
  - `op_time_entries`: SELECT, INSERT, UPDATE (cerrar entries).
- Convención del repo: BEGIN/COMMIT, idempotente, retrocompatible, query de verificación comentada al pie. Se corre en el SQL Editor ANTES de deployar el frontend.
- Alta manual del usuario `planta@vitalmetsa.com` en Supabase Auth + fila en `usuarios` con `es_planta=true` y `empresa_id` de Vitalmet.

### 4. Deploy y CSP

- Netlify sirve `planta.html` automáticamente (mismo site `vitalmetstock`). Verificar que los headers/CSP de `netlify.toml` apliquen también a `/planta.html` y permitan `dqvlqhaxgvtilhiuatpv.supabase.co`.
- Si se agrega redirect amigable `/planta` → `/planta.html`, va en `netlify.toml`.

## Fuera de alcance (YAGNI)

- Identidad por operario, PINes, cuentas individuales.
- Modo offline / cola de sincronización (escanear el QR ya requiere conectividad).
- PWA instalable, push, notificaciones.
- Firmar hold points desde el móvil.
- Editar/borrar registros de tiempo desde el móvil (solo desde el ERP).

## Errores y casos borde

- Sin sesión o sesión vencida → pantalla de login.
- `?op=` inexistente o OP no en-proceso → mensaje claro + link a la lista.
- Falla de red en una acción → notificación de error, estado local sin cambiar, botón reintentar (re-fetch).
- Carrera con el escritorio (índice único viola) → mensaje "ya tiene un timer corriendo" + re-sync.

## Testing

- `node --check` sobre el script extraído de `planta.html` y de `index.html` (regla del repo).
- Verificación de la migración: queries comentadas al pie (policies con guard, whitelist accesible, tabla sensible inaccesible logueado como planta).
- Prueba manual end-to-end: login planta en un celular real → escanear QR impreso → iniciar/pausar/finalizar → verificar en el ERP de escritorio que los tiempos y la Eficiencia reflejan lo cargado.
- Prueba de seguridad manual: con el token del usuario planta, GET a `ventas`/`asientos` debe devolver 0 filas o error.

## Orden de implementación

1. Migración 052 en el SQL Editor + alta del usuario planta → verificar.
2. `planta.html` completo.
3. Botón "QR planta" en `index.html` (+ CSP si hace falta).
4. Tests + push a `main` (deploy automático) → prueba en celular real.
