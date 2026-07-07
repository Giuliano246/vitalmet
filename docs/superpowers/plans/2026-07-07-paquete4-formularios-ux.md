# Paquete 4 — Formularios/UX: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validación por campo con foco en 9 formularios, modales con Esc/foco inicial/guard de cambios, y accesibilidad básica (aria-live, role=dialog, contraste).

**Architecture:** Todo en `index.html`. Dos helpers globales de validación aplicados 1:1 sobre los guard-clauses existentes (sin validaciones nuevas). Esc/foco/guard centralizados en `openModal`/`closeModal` + un listener global. Sin migraciones ni tablas nuevas.

**Tech Stack:** vanilla JS. Validación: `node --check` + suite existente (48 tests, sin tests nuevos — todo es glue de DOM).

**Spec:** `docs/superpowers/specs/2026-07-07-paquete4-formularios-ux-design.md`

## Global Constraints

- Reglas CLAUDE.md: snippet python + `node --check` + `node --test tests/*.test.js` antes de cada commit; voseo; un deploy al cierre del paquete.
- Las condiciones de validación existentes se traducen 1:1 — NO agregar reglas nuevas.
- El guard del palette (Esc propio) tiene prioridad: el Esc global debe ignorar `modal-palette`.

---

### Task 1: Helpers de validación + aplicación a 9 formularios (4A)

**Files:**
- Modify: `index.html` — helpers junto a `esc()`; guards de `saveVenta`, `saveOP`, `savePresupuesto` (buscar el save real de presupuestos), `registrarCobroOPago`, recepción de compra (buscar `saveRecepcion`/equivalente), alta de barra (buscar el save del modal mp), alta de certificado, `saveOperacionPaso`, `saveTemplate`.

**Interfaces:**
- Produces: `marcarInvalido(id)`, `validarCampos(pares) → boolean` con `pares = [[idCampo, condiciónOk, mensaje], …]`.

- [ ] **Step 1: Helpers**

```js
function marcarInvalido(id){
  const el=document.getElementById(id);if(!el)return;
  el.style.borderColor='var(--red)';el.style.boxShadow='0 0 0 3px rgba(220,80,80,.15)';
  const clear=()=>{el.style.borderColor='';el.style.boxShadow='';el.removeEventListener('input',clear);el.removeEventListener('change',clear);};
  el.addEventListener('input',clear);el.addEventListener('change',clear);
}
function validarCampos(pares){
  const malos=pares.filter(p=>!p[1]);
  if(!malos.length)return true;
  malos.forEach(p=>marcarInvalido(p[0]));
  const first=document.getElementById(malos[0][0]);if(first)first.focus();
  notify(malos[0][2]||'Revisá los campos marcados','err');
  return false;
}
```

- [ ] **Step 2: Aplicar a los 9 forms** — patrón de traducción (ejemplo `saveVenta`):

Antes: `if(!g('v-remito')||!g('v-cliente'))return notify('Completá nro pedido y razón social','err');`
Después:
```js
if(!validarCampos([
  ['v-remito',!!g('v-remito'),'Completá el nro de pedido'],
  ['v-cliente',!!g('v-cliente'),'Completá la razón social'],
]))return;
```
Repetir en cada save listado (leer cada guard real y traducir campo por campo; los guards que validan condiciones no atadas a un input — p.ej. "sin ítems" — quedan como notify simple).

- [ ] **Step 3: Validar (snippet + suite 48 PASS), commit**

```bash
git add index.html && git commit -m "feat(ux): validación por campo con foco en los 9 formularios principales"
```

---

### Task 2: Modales — Esc, foco inicial y dirty-guard (4B)

**Files:**
- Modify: `index.html` — `openModal` (final de la función), `closeModal`, listener global nuevo, y el handler de click en backdrop (buscar dónde se cierra por click en `.modal-overlay`, ~2612 según auditoría).

**Interfaces:**
- Consumes: `openModal(id)`/`closeModal(id)` (clase `.open`).
- Produces: `_modalDirty={}` global; `closeModal` consulta el guard.

- [ ] **Step 1: Foco inicial + dirty tracking en openModal** (al final de `openModal`, después de agregar la clase `.open`):

```js
  // foco al primer control visible + tracking de cambios (guard de cierre)
  const ov=document.getElementById(id);
  if(ov){
    setTimeout(()=>{const f=ov.querySelector('.modal input:not([type=hidden]),.modal select,.modal textarea');if(f&&f.offsetParent!==null)f.focus();},80);
    const m=ov.querySelector('.modal');
    if(m){m.setAttribute('role','dialog');m.setAttribute('aria-modal','true');}
    _modalDirty[id]=false;
    if(!ov._dirtyHooked){ov._dirtyHooked=true;ov.addEventListener('input',()=>{_modalDirty[id]=true;});ov.addEventListener('change',()=>{_modalDirty[id]=true;});}
  }
```

Global: `let _modalDirty={};` junto a los otros globals. Los saves de venta/presupuesto/OP ya cierran vía `closeModal` — resetear ahí (Step 2).

- [ ] **Step 2: Guard en closeModal** (solo los 3 modales grandes):

```js
const MODALES_CON_GUARD=new Set(['modal-venta','modal-presupuesto','modal-op']);
function closeModal(id,force){
  if(!force&&MODALES_CON_GUARD.has(id)&&_modalDirty[id]){
    if(!confirm('Tenés cambios sin guardar. ¿Cerrar igual?'))return;
  }
  _modalDirty[id]=false;
  document.getElementById(id).classList.remove('open');
  if(id==='modal-venta')window.editingVentaId=null;
}
```
En los saves exitosos de esos 3 modales, setear `_modalDirty['modal-x']=false;` ANTES del `closeModal(...)` (o llamar `closeModal(id,true)`).

- [ ] **Step 3: Esc global** (junto al listener del palette; el del palette ya hace preventDefault y este debe ignorar ese modal):

```js
document.addEventListener('keydown',e=>{
  if(e.key!=='Escape')return;
  const abiertos=[...document.querySelectorAll('.modal-overlay.open')].filter(o=>o.id!=='modal-palette');
  if(!abiertos.length)return;
  e.preventDefault();
  closeModal(abiertos[abiertos.length-1].id);
});
```

Verificar el handler de click en backdrop: si cierra con `classList.remove` directo, cambiarlo a `closeModal(id)` para que pase por el guard.

- [ ] **Step 4: Validar, commit**

```bash
git add index.html && git commit -m "feat(ux): modales con Esc, foco inicial y protección de cambios sin guardar"
```

---

### Task 3: Accesibilidad + deploy (4C)

**Files:**
- Modify: `index.html` — HTML de `#notif`, variable CSS `--text3` (tema dark, `:root`).

- [ ] **Step 1:** En el HTML del toast (buscar `id="notif"`), agregar `role="status" aria-live="polite"`.
- [ ] **Step 2:** En `:root` (tema dark), cambiar `--text3:#8a8073` → `--text3:#98917f`. NO tocar el light theme.
- [ ] **Step 3:** Validar, commit, push, verificar en prod (form de venta vacío marca y enfoca; Esc cierra; modal sucio pide confirmación; headers/labels legibles).

```bash
git add index.html && git commit -m "feat(a11y): toast anunciado (aria-live), role=dialog en modales y contraste de texto terciario"
git push origin main
```

## Self-review

- Cobertura: 4A→T1, 4B→T2 (+role/aria-modal que la spec pone en 4C pero se setea en openModal, T2), 4C→T3. ✓
- Placeholders: los "buscar el save real" son lookups explícitos con instrucción. ✓
- Consistencia: `validarCampos/marcarInvalido` (T1) independientes; `_modalDirty`/`MODALES_CON_GUARD`/`closeModal(id,force)` coherentes en T2. ✓
