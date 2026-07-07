# Paquete 1 — Producción: multi-timer, Generar OP, Eficiencia

**Fecha:** 2026-07-06 · **Estado:** aprobado por Giuliano (diseño conversado en sesión)
**Contexto:** primera fase del plan de mejoras surgido de la auditoría integral del ERP (UX/UI + flujos + arquitectura). Orden acordado de paquetes: 1-Producción, 2-Navegación, 3-Comercial, 4-Formularios/UX, 5-Performance, 6-Precios/Facturación, 7-Calidad.

---

## 1A. Multi-timer simultáneo (feature pedida por Giuliano)

### Problema
Hoy solo puede correr UN timer en todo el sistema: `activeEntry()` (index.html:7574) devuelve la única entrada abierta y los guards "Ya hay un timer corriendo" (7704) y "Pausá el timer antes de cambiar de paso" (7697) bloquean el paralelismo. En el taller real una pieza puede tener procesos simultáneos (ej. tratamiento térmico mientras se mecaniza otra cara) y varias OPs corren a la vez en distintas máquinas.

### Alcance acordado
Timers simultáneos en **pasos de la misma OP y también entre OPs distintas** — cualquier combinación.

### Base de datos (migración 047)
`op_time_entries` ya soporta N entradas abiertas (no hay constraint que lo impida). Se agrega solo un guard de integridad:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS ux_op_time_entries_abierta
  ON op_time_entries(operacion_id, tipo) WHERE ended_at IS NULL;
```

Permite a lo sumo UNA entrada abierta de cada tipo (productivo/pausa) por paso — previene dobles por doble click o carreras entre pestañas. Sin cambios de esquema, retrocompatible, idempotente.

### Frontend — modelo de estado
- `activeEntry()` → se reemplaza por `activeEntriesFor(operacionId)` / helper `openEntry(operacionId, tipo)`. Desaparece el concepto de "paso seleccionado" para operar (queda solo como highlight visual opcional; los botones actúan por fila).
- Se eliminan los guards de exclusión (7697, 7704).
- `startTiempoOp(pasoId)`, `openPauseTiempo(pasoId)` + `confirmPauseTiempo(motivo)` (guarda el paso target en variable de módulo), `completeTiempoOp(pasoId)` — todas parametrizadas por paso.
- Semántica de pausa **por paso**: pausar el paso X cierra la entrada productiva de X y abre la pausa de X con motivo (modal de motivos existente, sin cambios). Iniciar X cierra solo la pausa abierta de X. Los demás pasos no se tocan.
- Completar paso: cierra productivo+pausa abiertos de ESE paso y marca `completada` (igual que hoy pero sin tocar otros pasos). Hold/witness points sin cambios.

### Frontend — UI del modal de tiempos
- Cada fila de paso (`renderTiemposOps`, 7594) incorpora: tiempo transcurrido en vivo (ya existe) + botones ▶ / ⏸ / ✓ propios según estado del paso.
- El display grande único (1830-1838, gradiente con INICIAR/PAUSAR/COMPLETAR globales) se reemplaza por un resumen compacto: "N timers corriendo en esta OP" + métricas en vivo (bloque 1840-1848 se conserva tal cual).
- `renderTimerDisplay`/`updateTiemposButtons` se reescriben para el modelo por fila. El `setInterval` de 1s se mantiene.
- Costeo sin cambios: `renderTiemposMetrics` ya suma por entrada; tiempos paralelos = costos de máquina aditivos (correcto: dos máquinas trabajando cuestan doble).

### Frontend — panel global "⏱ Timers activos"
- Card siempre visible arriba de la tabla de OPs en `#page-op`, visible al entrar a Producción.
- Fuente de datos: query liviana `op_time_entries?ended_at=is.null&select=id,tipo,motivo,started_at,operacion_id,op_operaciones(nombre,maquina,orden_id)` — se carga al entrar a la página y tras cada mutación de timers. NO se suma a `loadAll()`.
- Cada fila: nro OP + pieza (vía global `ops`) · paso · máquina · tiempo transcurrido en vivo (tick local 1s, sin refetch) · estado (▶ productivo / ⏸ en pausa con motivo).
- Acciones rápidas: ⏸ pausa directa (reusa modal de motivos), y click en la fila abre `openTiempos(ordenId)` para operar completo. Completar se hace desde el modal (tiene implicancias QC).
- Si no hay timers activos el panel se colapsa a una línea discreta (no ocupa espacio).

## 1B. Generar OP desde presupuesto aprobado

### Problema
No existe ningún vínculo venta/presupuesto→OP: `saveOP` es re-tipeo manual de ~12 campos. Además `guardar_venta` valida stock de PT al guardar, por lo que la venta no puede existir antes de producir → el punto de inserción correcto es el **presupuesto aprobado** (decisión aprobada por Giuliano).

### Flujo resultante
presupuesto aprobado → **Generar OP** → producir (multi-timer) → stock PT → convertir a venta → remito/factura. No se toca la RPC `guardar_venta` ni la validación de stock.

### Base de datos (migración 048)
```sql
ALTER TABLE ordenes_produccion ADD COLUMN IF NOT EXISTS presupuesto_id uuid REFERENCES presupuestos(id);
CREATE INDEX IF NOT EXISTS ix_ordenes_produccion_presupuesto ON ordenes_produccion(presupuesto_id);
```

### Frontend
- Botón "Generar OP" en la fila de presupuestos con estado aprobado (`renderPresupuestos`, 8663).
- Si el presupuesto tiene varios ítems: selector simple de qué ítem fabricar (un click si hay uno solo).
- Abre el modal de OP existente pre-cargado: pieza (desde `presupuesto_items`), cantidad, nro autogenerado como hoy; guarda `presupuesto_id`.
- En la fila del presupuesto: badge con sus OPs vinculadas y estado (pendiente/en curso/completada) — de un vistazo se ve si el pedido ya se está fabricando.
- En la OP: referencia al presupuesto de origen (nro + cliente).
- El `select=*` de `ordenes_produccion` en `loadAll` ya trae la columna nueva; el join de presupuestos ya está cargado.

## 1C. Rollup de eficiencia de producción

### Problema
`op_time_entries` captura tiempo por operación, pausas con motivo, tarifas — pero solo se analiza dentro del modal de UNA OP (`renderTiemposMetrics`, 7668). No hay vista agregada.

### Diseño
- Nueva sub-página **"Eficiencia"** en el grupo Producción (tocar `PAGE_TO_GROUP`, `GROUP_TABS`, `groupMods`, `PAGE_RENDERS` según convención CLAUDE.md).
- **Carga on-demand**: al entrar por primera vez baja `op_operaciones` + `op_time_entries` completas (todas las OPs) y las cachea en globals propias. NO entra en `loadAll()` (alineado con el fix de performance del paquete 5).
- Contenido (filtro por rango de fechas, default últimos 90 días):
  1. **Estimado vs. real por tipo de operación** (agrupado por `nombre` normalizado): detecta el cuello de botella. Tabla + barra.
  2. **Eficiencia por pieza**: promedio est/real de OPs completadas, con tendencia (últimas 5 vs. anteriores).
  3. **Productivo vs. pausas por mes** + desglose de motivos de pausa (planificada/no planificada) — dónde se pierde tiempo/plata.
  4. **Costo real de mano de obra + máquina por OP** (reusa la fórmula de `renderTiemposMetrics` con `TARIFA_OPERARIO_USD`).
- Cálculos nuevos en funciones puras testeables → tests en `tests/` (regla 9 del proyecto).

## Orden de implementación y reglas

1. **1A** multi-timer (migración 047 en SQL Editor → verificar → frontend → test manual → commit/push/deploy → verificar en prod).
2. **1B** Generar OP (migración 048 → frontend → commit/deploy).
3. **1C** Eficiencia (sin migración → frontend + tests → commit/deploy).

Aplican todas las reglas de CLAUDE.md: un cambio a la vez, SQL antes que frontend, `esc()` en toda interpolación, `node --check` + `node --test` antes de commitear, texto UI en español argentino (voseo).

## Fuera de alcance (paquetes siguientes)
Command palette y deep-links (P2), mailings/alertas nuevas (P3), validación por campo (P4), fix de `loadAll` (P5), listas de precios (P6), auto-NCR (P7).
