# Paquete 1 — Producción: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-timer simultáneo por paso (misma OP y entre OPs), botón "Generar OP" desde presupuesto aprobado, y página de eficiencia de producción agregada.

**Architecture:** Todo vive en `index.html` (single-file, vanilla JS + Supabase/PostgREST). La DB ya soporta timers paralelos (`op_time_entries` con `started_at/ended_at`); el cambio es de lógica UI + 2 migraciones chicas (índice de integridad y columna `presupuesto_id`). El panel global y la página Eficiencia cargan datos on-demand, fuera de `loadAll()`.

**Tech Stack:** HTML/CSS/JS vanilla en `index.html`, Supabase (PostgREST + SQL Editor para migraciones), tests con `node --test` + harness vm (`tests/_harness.js`), deploy Netlify al pushear a `main`.

**Spec:** `docs/superpowers/specs/2026-07-06-paquete1-produccion-design.md`

## Global Constraints (CLAUDE.md del proyecto)

- **SQL en Supabase ANTES del frontend**: la migración se corre en el SQL Editor y se verifica; recién después se pushea el frontend que la usa.
- **Un cambio a la vez**: commit al final de cada task; push (= deploy Netlify) al cerrar cada bloque funcional (1A, 1B, 1C); verificar en prod entre bloques.
- Migraciones: `BEGIN/COMMIT`, idempotentes (`IF NOT EXISTS`), retrocompatibles, query de verificación comentada al pie.
- `empresa_id: currentEmpresa.id` obligatorio en todo POST.
- TODO dato de usuario interpolado en HTML pasa por `esc()`.
- Antes de commitear frontend: extraer el `<script>` y `node --check`, y `node --test tests/*.test.js`.
- Texto de UI en español argentino (voseo). Sin emojis como íconos estructurales nuevos (los ▶/⏸/✓ del timer ya son parte del lenguaje existente del módulo — mantener coherencia, no introducir otros).
- Los números de línea citados son orientativos (el archivo cambia); anclar por nombre de función o string único.

---

### Task 1: Migración 047 — índice de integridad multi-timer

**Files:**
- Create: `migrations/047_multi_timer.sql`

**Interfaces:**
- Produces: garantía DB de a lo sumo UNA entrada abierta por (operacion_id, tipo). Los POST de Tasks 2-4 confían en esto contra doble click / carreras.

- [ ] **Step 1: Crear el archivo de migración**

```sql
-- 047_multi_timer.sql — Multi-timer simultáneo (Paquete 1A)
-- Garantiza a lo sumo UNA entrada abierta de cada tipo (productivo/pausa)
-- por operación. Habilita timers paralelos entre operaciones con integridad.
BEGIN;

-- Higiene previa: si quedó más de una entrada abierta del mismo tipo para
-- la misma operación (bug histórico o carrera), cerrar todas menos la más nueva.
WITH dup AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY operacion_id, tipo ORDER BY started_at DESC
  ) AS rn
  FROM op_time_entries WHERE ended_at IS NULL
)
UPDATE op_time_entries e SET ended_at = now()
FROM dup WHERE e.id = dup.id AND dup.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_op_time_entries_abierta
  ON op_time_entries(operacion_id, tipo) WHERE ended_at IS NULL;

COMMIT;

-- Verificación:
-- SELECT indexname FROM pg_indexes WHERE tablename='op_time_entries' AND indexname='ux_op_time_entries_abierta';
-- SELECT operacion_id, tipo, count(*) FROM op_time_entries WHERE ended_at IS NULL GROUP BY 1,2 HAVING count(*)>1;  -- debe dar 0 filas
```

- [ ] **Step 2: Pasarle el SQL a Giuliano para el SQL Editor y esperar el "listo"**

Pegar el contenido en el chat con la instrucción: correrlo en Supabase SQL Editor y confirmar que la query de verificación devuelve el índice y 0 duplicados.

- [ ] **Step 3: Commit**

```bash
git add migrations/047_multi_timer.sql
git commit -m "feat(produccion): migración 047 — índice de integridad para multi-timer"
```

---

### Task 2: Lógica multi-timer — helpers puros + start/pause/complete por paso

**Files:**
- Modify: `index.html` — sección "⏱ CAPTURA DE TIEMPOS" (funciones `activeEntry`, `startTiempoOp`, `openPauseTiempo`, `confirmPauseTiempo`, `completeTiempoOp`, `selectTiempoPaso`, `openTiempos`)
- Create: `tests/timers.test.js`

**Interfaces:**
- Consumes: globals existentes `opTimeEntries`, `opOperaciones`, `currentTiempoOpId`, `GET/POST/PATCH`, `notify`, `renderTiempos`, `loadTiemposData`.
- Produces (usadas por Tasks 3-4): `openEntryOf(entries, opId, tipo) → entry|null` (pura), `activeProductivos(entries) → entry[]` (pura), `startTiempoOp(pasoId)`, `openPauseTiempo(pasoId)`, `completeTiempoOp(pasoId)` (async, por paso), variable de módulo `pausaCtx = {operacionId} | null`, y stub `refreshTimersActivos()` (no-op hasta Task 4).

- [ ] **Step 1: Escribir tests que fallan para los helpers puros**

Crear `tests/timers.test.js` siguiendo el patrón de `tests/calculos.test.js` (mirar cómo ese archivo usa `tests/_harness.js` para cargar el script y copiar el mismo boilerplate de carga):

```js
const {test}=require('node:test');
const assert=require('node:assert');
const {loadApp}=require('./_harness.js'); // ajustar al export real del harness (ver calculos.test.js)
const app=loadApp();

const E=(op,tipo,ended)=>({operacion_id:op,tipo,started_at:'2026-07-06T10:00:00Z',ended_at:ended||null});

test('openEntryOf encuentra la entrada abierta del tipo pedido',()=>{
  const entries=[E('a','productivo','2026-07-06T11:00:00Z'),E('a','productivo'),E('b','pausa')];
  assert.strictEqual(app.openEntryOf(entries,'a','productivo'),entries[1]);
  assert.strictEqual(app.openEntryOf(entries,'a','pausa'),null);
  assert.strictEqual(app.openEntryOf(entries,'b','pausa'),entries[2]);
});

test('activeProductivos devuelve solo productivos abiertos',()=>{
  const entries=[E('a','productivo'),E('b','productivo','2026-07-06T11:00:00Z'),E('c','pausa'),E('d','productivo')];
  assert.deepStrictEqual(app.activeProductivos(entries).map(e=>e.operacion_id),['a','d']);
});
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Run: `node --test tests/timers.test.js`
Expected: FAIL — `openEntryOf is not a function` (o equivalente según el harness).

- [ ] **Step 3: Implementar los helpers puros en index.html**

En la sección de tiempos, reemplazar `function activeEntry(){...}` por:

```js
function openEntryOf(entries,opId,tipo){return entries.find(e=>e.operacion_id===opId&&e.tipo===tipo&&!e.ended_at)||null;}
function activeProductivos(entries){return entries.filter(e=>e.tipo==='productivo'&&!e.ended_at);}
function refreshTimersActivos(){} // se implementa con el panel global (Task 4)
```

Buscar TODOS los usos restantes de `activeEntry()` (hay en `renderTimerDisplay`, `updateTiemposButtons`, `selectTiempoPaso`, `startTiempoOp`, `confirmPauseTiempo`, `completeTiempoOp`, y el guard de `deleteTimeEntry`/renders) — se reescriben en este task y el siguiente; al final de Task 3 no debe quedar ninguna referencia a `activeEntry`.

- [ ] **Step 4: Reescribir startTiempoOp parametrizado por paso**

```js
async function startTiempoOp(pasoId){
  const paso=opOperaciones.find(o=>o.id===pasoId);
  if(!paso)return;
  if(paso.estado==='completada'){notify('Ese paso ya está completado');return;}
  if(openEntryOf(opTimeEntries,pasoId,'productivo')){notify('Ese paso ya tiene un timer corriendo');return;}
  try{
    // cerrar la pausa abierta de ESTE paso (los demás pasos no se tocan)
    const openPause=openEntryOf(opTimeEntries,pasoId,'pausa');
    if(openPause){
      const nowP=new Date().toISOString();
      await PATCH('op_time_entries',{ended_at:nowP},`?id=eq.${openPause.id}`);
      openPause.ended_at=nowP;
    }
    const res=await POST('op_time_entries',[{empresa_id:currentEmpresa.id,operacion_id:pasoId,operario_id:currentUser.id,tipo:'productivo',started_at:new Date().toISOString()}]);
    if(res&&res[0])opTimeEntries.push(res[0]);
    else await loadTiemposData(currentTiempoOpId);
    if(paso.estado==='pendiente'){await PATCH('op_operaciones',{estado:'en_curso'},`?id=eq.${paso.id}`);paso.estado='en_curso';}
    notify('▶ Timer iniciado · '+paso.nombre);
    renderTiempos();refreshTimersActivos();
  }catch(e){console.error('startTiempoOp error:',e);notify('Error al iniciar: '+e.message,'err');}
}
```

Nota: desaparecen el guard global "Ya hay un timer corriendo", el `setBusy('tiempos-btn-play')` (el botón global ya no existe tras Task 3) y `currentTiempoPasoId` como fuente de verdad.

- [ ] **Step 5: Reescribir pausa por paso con contexto**

```js
let pausaCtx=null; // {operacionId} — seteado al abrir el modal de motivos

function openPauseTiempo(pasoId){
  if(!openEntryOf(opTimeEntries,pasoId,'productivo')&&!timersActivosTiene(pasoId)){notify('Ese paso no tiene timer corriendo');return;}
  pausaCtx={operacionId:pasoId};
  openModal('modal-pausa-motivo');
}
function timersActivosTiene(){return false;} // Task 4 lo reemplaza (soporte panel global)

async function confirmPauseTiempo(motivo){
  closeModal('modal-pausa-motivo');
  const ctx=pausaCtx;pausaCtx=null;
  if(!ctx)return;
  try{
    const now=new Date().toISOString();
    // cierre por filtro: funciona tanto desde el modal como desde el panel global,
    // sin depender de tener la entry en memoria
    await PATCH('op_time_entries',{ended_at:now},`?operacion_id=eq.${ctx.operacionId}&tipo=eq.productivo&ended_at=is.null`);
    await POST('op_time_entries',[{empresa_id:currentEmpresa.id,operacion_id:ctx.operacionId,operario_id:currentUser.id,tipo:'pausa',motivo,started_at:now}]);
    // sincronizar memoria local si el modal de esa OP está abierto
    if(currentTiempoOpId){await loadTiemposData(currentTiempoOpId);renderTiempos();}
    notify('⏸ Pausado · '+motivo);
    refreshTimersActivos();
  }catch(e){notify('Error: '+e.message,'err');}
}
```

Los botones del `modal-pausa-motivo` (HTML, 8 botones `onclick="confirmPauseTiempo('...')"`) no cambian.

- [ ] **Step 6: Reescribir completeTiempoOp por paso**

```js
async function completeTiempoOp(pasoId){
  const paso=opOperaciones.find(o=>o.id===pasoId);
  if(!paso)return;
  if(!confirm(`¿Marcar "${paso.nombre}" como completado?`))return;
  try{
    const now=new Date().toISOString();
    await PATCH('op_time_entries',{ended_at:now},`?operacion_id=eq.${pasoId}&ended_at=is.null`);
    opTimeEntries.forEach(e=>{if(e.operacion_id===pasoId&&!e.ended_at)e.ended_at=now;});
    await PATCH('op_operaciones',{estado:'completada'},`?id=eq.${pasoId}`);
    paso.estado='completada';
    const pendientes=opOperaciones.filter(o=>o.estado==='pendiente'||o.estado==='en_curso').length;
    notify(pendientes?`✓ ${paso.nombre} completado`:'🎉 Todos los pasos completados');
    renderTiempos();refreshTimersActivos();
  }catch(e){notify('Error: '+e.message,'err');}
}
```

- [ ] **Step 7: Eliminar selectTiempoPaso y limpiar currentTiempoPasoId**

- Borrar `function selectTiempoPaso(...)` completa.
- En `openTiempos`: borrar las 2 líneas que setean `currentTiempoPasoId` (la detección de `activa`); dejar el resto igual.
- En `deletePaso`: borrar el bloque `if(currentTiempoPasoId===id)...`.
- Borrar la declaración `currentTiempoPasoId` de la línea de `let currentTiempoOpId=null,currentTiempoPasoId=null;` (dejar solo `currentTiempoOpId`).
- `grep -n "currentTiempoPasoId\|selectTiempoPaso" index.html` debe devolver 0 resultados al terminar (los usos en `renderTiemposOps`/`updateTiemposButtons`/`renderTimerDisplay` se eliminan en Task 3 — si este grep todavía los muestra acá, dejarlos para Task 3 pero anotar que quedan).

- [ ] **Step 8: Correr los tests y node --check**

```bash
node --test tests/timers.test.js          # PASS (2 tests)
node --test tests/                        # PASS (suite completa, sin regresiones)
# extraer el <script> y validar sintaxis como hace el CI (ver .github/workflows/tests.yml para el comando exacto)
```

- [ ] **Step 9: Commit**

```bash
git add index.html tests/timers.test.js
git commit -m "feat(produccion): lógica multi-timer — start/pausa/completar por paso, sin exclusión global"
```

---

### Task 3: UI del modal de tiempos — controles por fila + resumen compacto

**Files:**
- Modify: `index.html` — HTML del modal de tiempos (bloque del display grande, buscar `id="tiempos-timer"`) y funciones `renderTiemposOps`, `renderTimerDisplay`, `updateTiemposButtons`, `openTiempos`.

**Interfaces:**
- Consumes: `openEntryOf`, `activeProductivos`, `startTiempoOp(pasoId)`, `openPauseTiempo(pasoId)`, `completeTiempoOp(pasoId)` (Task 2), `fmtTimerSec`, `secSince`, `fmtHMfromMin`.
- Produces: celdas de tiempo con `id="paso-time-<opId>"` actualizadas por tick; `renderTiemposActiveSummary()` reemplaza a `renderTimerDisplay`.

- [ ] **Step 1: Reemplazar el display grande por el resumen compacto (HTML)**

Buscar el `<div>` con el gradiente (`background:linear-gradient(135deg,#003a8c,var(--accent))`) que contiene `#tiempos-timer`, `#tiempos-status` y los 3 botones globales (`tiempos-btn-play/pause/stop`). Reemplazar TODO ese div por:

```html
<div id="tiempos-active-summary" style="background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:14px">
  <div class="section-label">Timers de esta OP</div>
  <div id="tiempos-summary-body" style="margin-top:8px;font-size:12px;color:var(--text3)">Sin timers corriendo</div>
</div>
```

El bloque "Métricas en vivo" y el "Tip" quedan como están.

- [ ] **Step 2: Reescribir renderTiemposOps con controles por fila**

Dentro del `.map(o=>{...})` de `renderTiemposOps`, después de calcular `totalMin`, reemplazar el cálculo de `active` y el retorno del template por:

```js
const openProd=openEntryOf(opTimeEntries,o.id,'productivo');
const openPausa=openEntryOf(opTimeEntries,o.id,'pausa');
let controls='';
if(o.estado==='completada'){
  controls='<span class="badge badge-ok">✓ listo</span>';
}else if(openProd){
  controls=`<button class="btn btn-sm" style="background:#f59e0b;color:white;min-width:34px" onclick="openPauseTiempo('${o.id}')" aria-label="Pausar" title="Pausar">⏸</button>
    <button class="btn btn-ghost btn-sm" style="min-width:34px" onclick="completeTiempoOp('${o.id}')" aria-label="Completar" title="Completar paso">✓</button>`;
}else{
  controls=`<button class="btn btn-sm" style="background:var(--green);color:white;min-width:34px" onclick="startTiempoOp('${o.id}')" aria-label="${openPausa?'Reanudar':'Iniciar'}" title="${openPausa?'Reanudar':'Iniciar'}">▶</button>
    <button class="btn btn-ghost btn-sm" style="min-width:34px" onclick="completeTiempoOp('${o.id}')" aria-label="Completar" title="Completar paso">✓</button>`;
}
const estadoBadge=openProd?'<span class="badge badge-warn">▶ corriendo</span>':openPausa?`<span class="badge badge-coral">⏸ ${esc(openPausa.motivo||'pausa')}</span>`:o.estado==='completada'?'':'<span class="badge badge-blue">○</span>';
```

Y en el template de la fila: quitar los `onclick="selectTiempoPaso(...)"` y `cursor:pointer` de todas las celdas, quitar el borde condicional `active` (borde fijo `var(--border)`, resaltar con `border-color:var(--accent)` solo si `openProd`), mostrar `estadoBadge` donde estaba `badge`, darle a la celda de tiempo `id="paso-time-${o.id}"`, y agregar `controls` en una celda nueva antes del botón de eliminar (la grid pasa de `auto 1fr auto auto auto` a `auto 1fr auto auto auto auto`).

- [ ] **Step 3: Reescribir renderTimerDisplay como resumen + tick de celdas**

```js
function renderTimerDisplay(){
  // tick por fila: solo textContent, sin re-render (no rompe hover/click)
  opOperaciones.forEach(o=>{
    const el=document.getElementById('paso-time-'+o.id);
    if(!el)return;
    const entries=opTimeEntries.filter(e=>e.operacion_id===o.id&&e.tipo==='productivo');
    const finished=entries.filter(e=>e.ended_at).reduce((s,e)=>s+(new Date(e.ended_at)-new Date(e.started_at))/60000,0);
    const live=entries.find(e=>!e.ended_at);
    el.textContent=live?fmtTimerSec(secSince(live.started_at)+Math.round(finished*60)):fmtHMfromMin(finished);
  });
  const body=document.getElementById('tiempos-summary-body');
  if(!body)return;
  const act=activeProductivos(opTimeEntries);
  const pausados=opTimeEntries.filter(e=>e.tipo==='pausa'&&!e.ended_at);
  if(!act.length&&!pausados.length){body.textContent='Sin timers corriendo';return;}
  body.innerHTML=[
    act.length?`<span style="color:var(--green);font-weight:600">▶ ${act.length} corriendo</span>`:'',
    pausados.length?`<span style="color:var(--coral);font-weight:600">⏸ ${pausados.length} en pausa</span>`:''
  ].filter(Boolean).join(' · ');
}
```

- [ ] **Step 4: Eliminar updateTiemposButtons**

Borrar la función y su llamada dentro de `renderTiempos()` (queda `renderTiempos(){renderTiemposOps();renderTiemposEntries();renderTiemposMetrics();renderTimerDisplay();}`). Verificar con grep que no quedan referencias a `tiempos-btn-play|tiempos-btn-pause|tiempos-btn-stop|updateTiemposButtons|activeEntry\b|currentTiempoPasoId|selectTiempoPaso`.

- [ ] **Step 5: Validar sintaxis y suite**

```bash
node --test tests/    # PASS
# node --check del script extraído (comando del CI)
```

- [ ] **Step 6: Prueba manual local + commit + deploy + verificación en prod**

Prueba manual (abrir `index.html` servido local o directamente en prod tras deploy): crear OP de prueba con 3 pasos → iniciar paso 1 y paso 2 a la vez (ambos corren) → pausar paso 1 con motivo (paso 2 sigue) → reanudar paso 1 → completar paso 2 (paso 1 sigue) → completar todos → verificar bitácora y métricas.

```bash
git add index.html
git commit -m "feat(produccion): UI multi-timer — controles por paso en el modal de tiempos"
git push origin main   # deploy Netlify → verificar en https://erp.vitalmetsa.com
```

---

### Task 4: Panel global "⏱ Timers activos" en la página Producción

**Files:**
- Modify: `index.html` — HTML de `#page-op` (después del `.page-header`), sección de tiempos (reemplazar stubs `refreshTimersActivos`/`timersActivosTiene`), registro en `PAGE_RENDERS`.

**Interfaces:**
- Consumes: `openPauseTiempo(pasoId)` + `pausaCtx` (Task 2), `openTiempos(ordenId)`, globals `ops` (órdenes cargadas por `loadAll`), `GET`, `esc`, `fmtTimerSec`, `secSince`.
- Produces: global `timersActivos=[]`; `refreshTimersActivos()` real (reemplaza el stub); `timersActivosTiene(opId)` real.

- [ ] **Step 1: Agregar el contenedor en el HTML de #page-op**

Dentro de `<div class="page" id="page-op">`, inmediatamente después del cierre del `.page-header`, insertar:

```html
<div id="timers-activos-panel" style="display:none;margin-bottom:14px"></div>
```

- [ ] **Step 2: Implementar loader + render + tick**

Reemplazar los stubs de Task 2 (`refreshTimersActivos`, `timersActivosTiene`) por:

```js
let timersActivos=[];
async function refreshTimersActivos(){
  timersActivos=await GET('op_time_entries','?ended_at=is.null&select=id,tipo,motivo,started_at,operacion_id,op_operaciones(id,nombre,maquina,orden_id)').catch(()=>[]);
  renderTimersActivosPanel();
}
function timersActivosTiene(opId){return timersActivos.some(e=>e.operacion_id===opId&&e.tipo==='productivo');}

function renderTimersActivosPanel(){
  const panel=document.getElementById('timers-activos-panel');
  if(!panel)return;
  if(!timersActivos.length){panel.style.display='none';panel.innerHTML='';return;}
  panel.style.display='block';
  const rows=timersActivos.map(e=>{
    const paso=e.op_operaciones||{};
    const orden=ops.find(o=>o.id===paso.orden_id);
    const enPausa=e.tipo==='pausa';
    const accion=enPausa
      ?`<button class="btn btn-sm" style="background:var(--green);color:white" onclick="event.stopPropagation();startTiempoOp('${e.operacion_id}');" aria-label="Reanudar" title="Reanudar">▶</button>`
      :`<button class="btn btn-sm" style="background:#f59e0b;color:white" onclick="event.stopPropagation();openPauseTiempo('${e.operacion_id}')" aria-label="Pausar" title="Pausar">⏸</button>`;
    return `<div onclick="openTiempos('${paso.orden_id}')" style="display:grid;grid-template-columns:1fr auto auto auto;gap:12px;align-items:center;padding:8px 12px;border-bottom:1px solid var(--border);cursor:pointer">
      <div><span class="mono" style="color:var(--accent);font-weight:600">${esc(orden?orden.nro:'—')}</span> ${esc(orden?orden.pieza:'')} <span style="color:var(--text3)">· ${esc(paso.nombre||'')}${paso.maquina?' · '+esc(paso.maquina):''}</span></div>
      <span class="badge ${enPausa?'badge-coral':'badge-warn'}">${enPausa?'⏸ '+esc(e.motivo||'pausa'):'▶'}</span>
      <span class="mono" id="panel-timer-${e.id}" style="font-weight:700;font-size:13px">${fmtTimerSec(secSince(e.started_at))}</span>
      ${accion}
    </div>`;
  }).join('');
  panel.innerHTML=`<div style="background:var(--surface);border:1px solid var(--border);border-radius:6px">
    <div class="section-label" style="padding:10px 12px 0">⏱ Timers activos (${timersActivos.length})</div>${rows}</div>`;
}

setInterval(()=>{
  const page=document.getElementById('page-op');
  if(!page||!page.classList.contains('active')||!timersActivos.length)return;
  timersActivos.forEach(e=>{const el=document.getElementById('panel-timer-'+e.id);if(el)el.textContent=fmtTimerSec(secSince(e.started_at));});
},1000);
```

Nota sobre `startTiempoOp` desde el panel: si el modal de esa OP no está abierto, `opTimeEntries`/`opOperaciones` corresponden a otra OP. Ajustar el inicio de `startTiempoOp` para tolerar eso:

```js
async function startTiempoOp(pasoId){
  let paso=opOperaciones.find(o=>o.id===pasoId);
  if(!paso){ // llamado desde el panel global: operar directo contra la DB
    const rows=await GET('op_operaciones',`?id=eq.${pasoId}`).catch(()=>[]);
    paso=rows[0];
    if(!paso)return;
    // cerrar pausa abierta y abrir productivo por filtro (sin estado local)
    const now=new Date().toISOString();
    await PATCH('op_time_entries',{ended_at:now},`?operacion_id=eq.${pasoId}&tipo=eq.pausa&ended_at=is.null`);
    await POST('op_time_entries',[{empresa_id:currentEmpresa.id,operacion_id:pasoId,operario_id:currentUser.id,tipo:'productivo',started_at:now}]);
    if(paso.estado==='pendiente')await PATCH('op_operaciones',{estado:'en_curso'},`?id=eq.${pasoId}`);
    notify('▶ Timer reanudado · '+paso.nombre);
    refreshTimersActivos();
    return;
  }
  /* ...resto igual que Task 2... */
}
```

- [ ] **Step 3: Registrar la carga al entrar a la página**

En `PAGE_RENDERS`, en la entrada `op:[...]`, agregar `refreshTimersActivos` al final del array. Además, `confirmPauseTiempo` y `completeTiempoOp` ya llaman `refreshTimersActivos()` (Task 2).

- [ ] **Step 4: Validar, commit, deploy, verificar**

```bash
node --test tests/   # PASS
git add index.html
git commit -m "feat(produccion): panel global de timers activos en la página de OPs"
git push origin main
```

Verificación en prod: iniciar timers en 2 OPs distintas desde sus modales → volver a la lista de OPs → el panel muestra ambos corriendo con tiempos en vivo → pausar uno desde el panel (pide motivo) → reanudarlo desde el panel → click en la fila abre el modal correcto. **Cierra el bloque 1A.**

---

### Task 5: Migración 048 + "Generar OP" desde presupuesto aprobado (1B)

**Files:**
- Create: `migrations/048_op_desde_presupuesto.sql`
- Modify: `index.html` — `renderPresupuestos` (acciones de fila + badge), `saveOP` (campo nuevo), función de apertura del modal de OP (localizar el `onclick` del botón "Nueva orden" en `#page-op` para conocer la función que resetea el modal), HTML: nuevo mini-modal selector de ítem.

**Interfaces:**
- Consumes: globals `presupuestos` (con `presupuesto_items` embebidos), `ops`, modal `modal-op` y sus campos `op-nro`, `op-pieza`, `op-cant`, `op-desc`, `op-precio` (ids confirmados en `saveOP`), `g(id)` getter, `esc`, `openModal`.
- Produces: columna `ordenes_produccion.presupuesto_id`; global `opPresupuestoOrigen=null`; `generarOPDesdePresupuesto(presupuestoId)`.

- [ ] **Step 1: Crear la migración**

```sql
-- 048_op_desde_presupuesto.sql — Vínculo presupuesto → OP (Paquete 1B)
BEGIN;
ALTER TABLE ordenes_produccion ADD COLUMN IF NOT EXISTS presupuesto_id uuid REFERENCES presupuestos(id);
CREATE INDEX IF NOT EXISTS ix_ordenes_produccion_presupuesto ON ordenes_produccion(presupuesto_id);
COMMIT;
-- Verificación:
-- SELECT column_name FROM information_schema.columns WHERE table_name='ordenes_produccion' AND column_name='presupuesto_id';
```

- [ ] **Step 2: Pasarle el SQL a Giuliano, esperar el "listo", commitear la migración**

```bash
git add migrations/048_op_desde_presupuesto.sql
git commit -m "feat(produccion): migración 048 — vínculo presupuesto_id en ordenes_produccion"
```

- [ ] **Step 3: Implementar generarOPDesdePresupuesto + selector de ítem**

Agregar el mini-modal al HTML (junto a los otros modales):

```html
<!-- MODAL: elegir ítem del presupuesto para generar OP -->
<div class="modal-overlay" id="modal-gen-op-item">
  <div class="modal" style="width:440px">
    <div class="modal-header"><div class="modal-title">¿Qué ítem fabricar?</div><button class="modal-close" onclick="closeModal('modal-gen-op-item')">×</button></div>
    <div class="modal-body">
      <div id="gen-op-items" style="display:flex;flex-direction:column;gap:6px"></div>
    </div>
  </div>
</div>
```

JS (cerca de `saveOP`):

```js
let opPresupuestoOrigen=null;

function generarOPDesdePresupuesto(pid){
  const p=presupuestos.find(x=>x.id===pid);
  if(!p)return;
  const items=(p.presupuesto_items||[]);
  if(!items.length){notify('El presupuesto no tiene ítems','err');return;}
  if(items.length===1){abrirOPPrecargada(pid,items[0].id);return;}
  document.getElementById('gen-op-items').innerHTML=items.map(it=>
    `<button class="btn btn-ghost" style="text-align:left;padding:10px" onclick="closeModal('modal-gen-op-item');abrirOPPrecargada('${pid}','${it.id}')">${esc(it.descripcion||it.pieza||'ítem')} <span class="mono" style="color:var(--text3)">× ${it.cantidad||1}</span></button>`
  ).join('');
  openModal('modal-gen-op-item');
}

function abrirOPPrecargada(pid,itemId){
  const p=presupuestos.find(x=>x.id===pid);
  const item=(p.presupuesto_items||[]).find(i=>i.id===itemId);
  if(!p||!item)return;
  // abrir el modal de OP "nueva" con el mismo flujo del botón Nueva orden
  // (localizar el onclick real del botón en #page-op y llamar a esa función acá)
  openNuevaOPModal(); // ← reemplazar por el nombre real
  document.getElementById('op-pieza').value=item.descripcion||item.pieza||'';
  document.getElementById('op-cant').value=item.cantidad||1;
  document.getElementById('op-precio').value=item.precio_unitario||'';
  document.getElementById('op-desc').value=`Según presupuesto ${p.nro||''} — ${p.cliente||''}`.trim();
  opPresupuestoOrigen=pid;
  notify('OP pre-cargada desde el presupuesto '+(p.nro||''));
}
```

(Los nombres de campos de `presupuesto_items` — `descripcion/pieza/cantidad/precio_unitario` — verificarlos contra `renderPresupuestos`/`savePresupuesto` al implementar; usar los reales.)

- [ ] **Step 4: Persistir el vínculo en saveOP y resetearlo**

En el objeto del `POST('ordenes_produccion',{...})` de `saveOP`, agregar `presupuesto_id:opPresupuestoOrigen||null,`. Después del POST exitoso (junto al `resetF([...])`), agregar `opPresupuestoOrigen=null;`. En la función que abre el modal de OP para una orden NUEVA (la del botón "Nueva orden"), setear `opPresupuestoOrigen=null;` al principio (que un alta manual no herede el vínculo de una pre-carga abandonada).

- [ ] **Step 5: Botón + badge en renderPresupuestos, referencia en la tabla de OPs**

En `renderPresupuestos`, dentro del `.map` de filas:

```js
const opsVinc=ops.filter(o=>o.presupuesto_id===p.id);
const genOPBtn=(p.estado==='aprobado')?`<button class="btn btn-ghost btn-sm" style="border-color:var(--teal);color:var(--teal)" onclick="generarOPDesdePresupuesto('${p.id}')" title="Generar orden de producción desde este presupuesto">⚙ OP</button>`:'';
const opsBadge=opsVinc.length?`<span class="badge ${opsVinc.every(o=>o.estado==='completada')?'badge-ok':'badge-warn'}" title="${esc(opsVinc.map(o=>o.nro+' ('+o.estado+')').join(', '))}">${opsVinc.length} OP${opsVinc.length>1?'s':''}</span>`:'';
```

Insertar `genOPBtn` junto a las demás acciones de la fila y `opsBadge` junto al estado. En `renderOPs` (tabla de OPs), en la celda de descripción/pieza, si `o.presupuesto_id` existe agregar: `<span class="mono" style="color:var(--teal);font-size:10px" title="Generada desde presupuesto">${esc((presupuestos.find(p=>p.id===o.presupuesto_id)||{}).nro||'presup.')}</span>`.

- [ ] **Step 6: Validar, commit, deploy, verificar (cierra 1B)**

```bash
node --test tests/   # PASS
git add index.html
git commit -m "feat(produccion): Generar OP desde presupuesto aprobado con vínculo presupuesto_id"
git push origin main
```

Verificación en prod: presupuesto aprobado con 2 ítems → ⚙ OP → elegir ítem → modal pre-cargado → guardar → la OP aparece con referencia al presupuesto y el presupuesto muestra el badge "1 OP".

---

### Task 6: Funciones puras de eficiencia + tests (1C, parte 1)

**Files:**
- Modify: `index.html` — nuevas funciones puras en la sección de tiempos.
- Create: `tests/eficiencia.test.js`

**Interfaces:**
- Consumes: nada nuevo (funciones puras sobre arrays).
- Produces (usadas por Task 7): `minutosEntry(e, ahoraMs) → number`; `computeEficienciaPorOperacion(operaciones, entries) → [{nombre, estMin, realMin, eff, n}]` (eff = est/real ×100 redondeado, null si falta dato; ordenado por realMin desc); `computePausasPorMotivo(entries) → [{motivo, min, count}]` ordenado por min desc; `computeEficienciaPorPieza(ordenes, operaciones, entries) → [{pieza, estMin, realMin, eff, nOps}]`.

- [ ] **Step 1: Escribir tests que fallan**

```js
const {test}=require('node:test');
const assert=require('node:assert');
const {loadApp}=require('./_harness.js'); // mismo boilerplate que calculos.test.js
const app=loadApp();

const OPR=(id,orden,nombre,est)=>({id,orden_id:orden,nombre,tiempo_estimado_min:est,estado:'completada'});
const ENT=(op,tipo,startMin,endMin,motivo)=>({operacion_id:op,tipo,motivo:motivo||null,
  started_at:new Date(1700000000000+startMin*60000).toISOString(),
  ended_at:endMin==null?null:new Date(1700000000000+endMin*60000).toISOString()});

test('computeEficienciaPorOperacion agrupa por nombre y calcula eff',()=>{
  const opers=[OPR('a','o1','Torneado',60),OPR('b','o2','torneado ',30),OPR('c','o1','Fresado',45)];
  const entries=[ENT('a','productivo',0,80),ENT('b','productivo',0,40),ENT('c','productivo',0,45),ENT('a','pausa',80,90,'Setup')];
  const r=app.computeEficienciaPorOperacion(opers,entries);
  const torneado=r.find(x=>x.nombre==='torneado');
  assert.strictEqual(torneado.estMin,90);
  assert.strictEqual(torneado.realMin,120);       // pausas NO cuentan
  assert.strictEqual(torneado.eff,75);            // 90/120
  assert.strictEqual(torneado.n,2);
  assert.strictEqual(r[0].realMin>=r[r.length-1].realMin,true); // orden desc por realMin
});

test('computePausasPorMotivo suma minutos por motivo',()=>{
  const entries=[ENT('a','pausa',0,30,'Setup / cambio herramienta'),ENT('b','pausa',0,15,'Setup / cambio herramienta'),ENT('c','pausa',0,10,'Rotura de máquina'),ENT('a','productivo',30,60)];
  const r=app.computePausasPorMotivo(entries);
  assert.deepStrictEqual(r[0],{motivo:'Setup / cambio herramienta',min:45,count:2});
  assert.strictEqual(r.length,2);
});

test('computeEficienciaPorPieza agrega por pieza de la orden',()=>{
  const ordenes=[{id:'o1',pieza:'Anillo BX-156'},{id:'o2',pieza:'Anillo BX-156'},{id:'o3',pieza:'Unión 2"'}];
  const opers=[OPR('a','o1','Torneado',60),OPR('b','o2','Torneado',60),OPR('c','o3','Fresado',30)];
  const entries=[ENT('a','productivo',0,50),ENT('b','productivo',0,70),ENT('c','productivo',0,60)];
  const r=app.computeEficienciaPorPieza(ordenes,opers,entries);
  const bx=r.find(x=>x.pieza==='Anillo BX-156');
  assert.strictEqual(bx.estMin,120);assert.strictEqual(bx.realMin,120);assert.strictEqual(bx.eff,100);assert.strictEqual(bx.nOps,2);
});
```

- [ ] **Step 2: Correr y verificar que fallan**

Run: `node --test tests/eficiencia.test.js` → FAIL (`computeEficienciaPorOperacion is not a function`).

- [ ] **Step 3: Implementar las funciones puras**

```js
function minutosEntry(e,ahoraMs){const end=e.ended_at?new Date(e.ended_at).getTime():(ahoraMs||Date.now());return Math.max(0,Math.floor((end-new Date(e.started_at).getTime())/60000));}

function computeEficienciaPorOperacion(operaciones,entries){
  const porOp={};
  entries.forEach(e=>{if(e.tipo!=='productivo')return;porOp[e.operacion_id]=(porOp[e.operacion_id]||0)+minutosEntry(e);});
  const grupos={};
  operaciones.forEach(o=>{
    const k=(o.nombre||'—').trim().toLowerCase();
    if(!grupos[k])grupos[k]={nombre:k,estMin:0,realMin:0,n:0};
    grupos[k].estMin+=o.tiempo_estimado_min||0;
    grupos[k].realMin+=porOp[o.id]||0;
    grupos[k].n++;
  });
  return Object.values(grupos)
    .map(x=>({...x,eff:x.realMin>0&&x.estMin>0?Math.round(x.estMin/x.realMin*100):null}))
    .sort((a,b)=>b.realMin-a.realMin);
}

function computePausasPorMotivo(entries){
  const g={};
  entries.forEach(e=>{if(e.tipo!=='pausa')return;const k=e.motivo||'Sin motivo';if(!g[k])g[k]={motivo:k,min:0,count:0};g[k].min+=minutosEntry(e);g[k].count++;});
  return Object.values(g).sort((a,b)=>b.min-a.min);
}

function computeEficienciaPorPieza(ordenes,operaciones,entries){
  const porOp={};
  entries.forEach(e=>{if(e.tipo!=='productivo')return;porOp[e.operacion_id]=(porOp[e.operacion_id]||0)+minutosEntry(e);});
  const ordenPieza={};ordenes.forEach(o=>ordenPieza[o.id]=o.pieza||'—');
  const g={};const opsDeOrden={};
  operaciones.forEach(op=>{
    const pieza=ordenPieza[op.orden_id];if(pieza===undefined)return;
    if(!g[pieza])g[pieza]={pieza,estMin:0,realMin:0,_ordenes:new Set()};
    g[pieza].estMin+=op.tiempo_estimado_min||0;
    g[pieza].realMin+=porOp[op.id]||0;
    g[pieza]._ordenes.add(op.orden_id);
  });
  return Object.values(g)
    .map(x=>({pieza:x.pieza,estMin:x.estMin,realMin:x.realMin,nOps:x._ordenes.size,eff:x.realMin>0&&x.estMin>0?Math.round(x.estMin/x.realMin*100):null}))
    .sort((a,b)=>b.realMin-a.realMin);
}
```

- [ ] **Step 4: Correr tests → PASS, y suite completa → PASS**

```bash
node --test tests/eficiencia.test.js   # PASS (3 tests)
node --test tests/                     # PASS
```

- [ ] **Step 5: Commit**

```bash
git add index.html tests/eficiencia.test.js
git commit -m "feat(produccion): funciones puras de eficiencia por operación, pieza y motivo de pausa"
```

---

### Task 7: Página "Eficiencia" — nav, carga on-demand y render (1C, parte 2)

**Files:**
- Modify: `index.html` — `PAGE_TO_GROUP`, `GROUP_TABS`, `groupMods` en `aplicarPermisos`, `PAGE_RENDERS`, HTML nueva `page-eficiencia`, y agregar `<div class="tabs"></div>` al `.page-header` de `#page-op` (hoy el grupo producción no tiene tabs).

**Interfaces:**
- Consumes: `computeEficienciaPorOperacion`, `computeEficienciaPorPieza`, `computePausasPorMotivo`, `minutosEntry` (Task 6), `fmtHMfromMin`, `esc`, `GET`, `ops` global, `TARIFA_OPERARIO_USD`.
- Produces: página `eficiencia` navegable; globals `effOperaciones=null`, `effEntries=null`; `renderEficiencia()`.

- [ ] **Step 1: Registrar la página en la navegación (convención CLAUDE.md, 3 estructuras + tabs)**

1. `PAGE_TO_GROUP`: agregar `eficiencia:'produccion'` (y verificar que `op:'produccion'` ya está).
2. `GROUP_TABS`: agregar la clave `produccion:[{k:'op',l:'Órdenes'},{k:'eficiencia',l:'Eficiencia'}]`.
3. `aplicarPermisos` → `groupMods`: verificar que el grupo `produccion` ya está mapeado (la página `op` existe); no requiere entrada nueva porque el gate es por grupo.
4. `PAGE_RENDERS`: agregar `eficiencia:[renderEficiencia]`.
5. HTML: verificar que el `.page-header` de `#page-op` tenga `<div class="tabs"></div>`; si no lo tiene, agregarlo (requisito de `showPage` para inyectar tabs).

- [ ] **Step 2: HTML de la página**

Después del cierre de `#page-op`, agregar:

```html
<div class="page" id="page-eficiencia">
  <div class="page-header">
    <div><h1>Eficiencia de producción</h1><p>Estimado vs. real por operación y por pieza · dónde se pierde tiempo</p></div>
    <div class="tabs"></div>
    <div style="display:flex;gap:8px;align-items:center">
      <select id="eff-rango" onchange="renderEficiencia()" style="width:auto">
        <option value="90">Últimos 90 días</option>
        <option value="30">Últimos 30 días</option>
        <option value="365">Último año</option>
        <option value="0">Todo</option>
      </select>
    </div>
  </div>
  <div id="eff-stats" class="stats-bar"></div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px" class="dash-grid">
    <div class="card"><div class="section-label">Estimado vs. real por operación</div><div class="table-wrap"><table><thead><tr><th>Operación</th><th>OPs</th><th>Estimado</th><th>Real</th><th>Eficiencia</th></tr></thead><tbody id="eff-ops-tbody"></tbody></table></div></div>
    <div class="card"><div class="section-label">Eficiencia por pieza</div><div class="table-wrap"><table><thead><tr><th>Pieza</th><th>OPs</th><th>Estimado</th><th>Real</th><th>Eficiencia</th></tr></thead><tbody id="eff-piezas-tbody"></tbody></table></div></div>
  </div>
  <div class="card" style="margin-top:14px"><div class="section-label">Paradas por motivo</div><div class="table-wrap"><table><thead><tr><th>Motivo</th><th>Veces</th><th>Tiempo total</th></tr></thead><tbody id="eff-pausas-tbody"></tbody></table></div></div>
</div>
```

(Adaptar clases `card`/`stats-bar` a las realmente existentes en el CSS — verificar con grep un uso existente y copiar el patrón.)

- [ ] **Step 3: Loader on-demand + render**

```js
let effOperaciones=null,effEntries=null;
async function ensureEficienciaData(){
  if(effOperaciones)return;
  [effOperaciones,effEntries]=await Promise.all([
    GET('op_operaciones','?select=id,orden_id,nombre,maquina,tiempo_estimado_min,tarifa_maquina_usd,estado').catch(()=>[]),
    GET('op_time_entries','?select=operacion_id,tipo,motivo,started_at,ended_at&order=started_at.asc').catch(()=>[])
  ]);
}
async function renderEficiencia(){
  await ensureEficienciaData();
  const dias=parseInt(document.getElementById('eff-rango')?.value||'90');
  const desde=dias?Date.now()-dias*86400000:0;
  const entries=effEntries.filter(e=>new Date(e.started_at).getTime()>=desde);
  const opIds=new Set(entries.map(e=>e.operacion_id));
  const opers=effOperaciones.filter(o=>opIds.has(o.id));

  const porOperacion=computeEficienciaPorOperacion(opers,entries);
  const porPieza=computeEficienciaPorPieza(ops,opers,entries);
  const pausas=computePausasPorMotivo(entries);

  const totProd=entries.filter(e=>e.tipo==='productivo').reduce((s,e)=>s+minutosEntry(e),0);
  const totPausa=entries.filter(e=>e.tipo==='pausa').reduce((s,e)=>s+minutosEntry(e),0);
  const totEst=opers.reduce((s,o)=>s+(o.tiempo_estimado_min||0),0);
  const effGlobal=totProd>0&&totEst>0?Math.round(totEst/totProd*100):null;
  document.getElementById('eff-stats').innerHTML=[
    ['Horas productivas',fmtHMfromMin(totProd)],['Horas de parada',fmtHMfromMin(totPausa)],
    ['Eficiencia global',effGlobal?effGlobal+'%':'—'],['OPs con registro',new Set(opers.map(o=>o.orden_id)).size]
  ].map(([l,v])=>`<div class="stat-card"><div class="stat-label">${l}</div><div class="stat-value">${v}</div></div>`).join('');

  const effBadge=e=>e==null?'<span class="badge">—</span>':e>=100?`<span class="badge badge-ok">${e}%</span>`:e>=80?`<span class="badge badge-warn">${e}%</span>`:`<span class="badge badge-coral">${e}%</span>`;
  document.getElementById('eff-ops-tbody').innerHTML=porOperacion.length?porOperacion.map(x=>`<tr><td>${esc(x.nombre)}</td><td class="mono">${x.n}</td><td class="mono">${fmtHMfromMin(x.estMin)}</td><td class="mono">${fmtHMfromMin(x.realMin)}</td><td>${effBadge(x.eff)}</td></tr>`).join(''):'<tr><td colspan="5" style="text-align:center;color:var(--text3);padding:18px">Sin registros de tiempo en el rango</td></tr>';
  document.getElementById('eff-piezas-tbody').innerHTML=porPieza.length?porPieza.map(x=>`<tr><td>${esc(x.pieza)}</td><td class="mono">${x.nOps}</td><td class="mono">${fmtHMfromMin(x.estMin)}</td><td class="mono">${fmtHMfromMin(x.realMin)}</td><td>${effBadge(x.eff)}</td></tr>`).join(''):'<tr><td colspan="5" style="text-align:center;color:var(--text3);padding:18px">Sin datos</td></tr>';
  document.getElementById('eff-pausas-tbody').innerHTML=pausas.length?pausas.map(x=>`<tr><td>${esc(x.motivo)}</td><td class="mono">${x.count}</td><td class="mono">${fmtHMfromMin(x.min)}</td></tr>`).join(''):'<tr><td colspan="3" style="text-align:center;color:var(--text3);padding:18px">Sin paradas registradas</td></tr>';
}
```

Además: al mutar timers (start/pausa/completar) invalidar el cache con `effOperaciones=null;effEntries=null;` para que la próxima visita recargue (agregar esa línea en `refreshTimersActivos()`).

- [ ] **Step 4: Validar, commit, deploy, verificar (cierra 1C y el Paquete 1)**

```bash
node --test tests/   # PASS
# node --check del script extraído
git add index.html
git commit -m "feat(produccion): página Eficiencia — est vs real por operación/pieza y paradas por motivo"
git push origin main
```

Verificación en prod: entrar a Producción → tab Eficiencia → carga on-demand, stats y 3 tablas con datos reales; cambiar el rango recalcula; los timers nuevos aparecen tras registrar tiempos.

---

## Self-review (hecho al escribir el plan)

- **Cobertura de spec:** 1A → Tasks 1-4; 1B → Task 5; 1C → Tasks 6-7. Reglas de CLAUDE.md en Global Constraints. ✓
- **Sin placeholders:** el único nombre a resolver en sitio es la función real del botón "Nueva orden" (`openNuevaOPModal()` marcado explícitamente como "reemplazar por el nombre real") y el export exacto del harness (mirar `calculos.test.js`) — ambos son lookups de 1 minuto con instrucción explícita, no diseño pendiente. ✓
- **Consistencia de tipos/nombres:** `openEntryOf/activeProductivos/refreshTimersActivos/timersActivosTiene/pausaCtx/opPresupuestoOrigen/minutosEntry/computeEficienciaPorOperacion/computePausasPorMotivo/computeEficienciaPorPieza` usados idéntico entre tasks. ✓
