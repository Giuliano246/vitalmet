# Paquete 2 — Navegación: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Command palette Ctrl+K, deep-links entre registros con highlight, sort global de tablas, filtros de fecha en 5 módulos y sticky headers.

**Architecture:** Todo en `index.html` (single-file, vanilla JS). Sort y palette usan funciones puras testeadas en el harness vm. Sort por delegación global de clicks sobre `thead th` reordenando el DOM (ningún render se toca), con re-aplicación en el hook `renderPage()`. Deep-links vía `showPage(p, recordId)` + `data-id` en filas + resolución post-render. Palette indexa los globals en memoria (cero red). Sin migraciones.

**Tech Stack:** HTML/CSS/JS vanilla, tests `node --test` + `tests/_harness.js` (vm), deploy Netlify por push a `main`.

**Spec:** `docs/superpowers/specs/2026-07-07-paquete2-navegacion-design.md`

## Global Constraints (CLAUDE.md del proyecto)

- Un cambio a la vez: commit por task; push (deploy) al cierre de cada bloque indicado; verificar en prod entre deploys.
- TODO dato de usuario interpolado en HTML pasa por `esc()`.
- Antes de commitear: extraer `<script>` con el snippet python + `node --check`, y `node --test tests/*.test.js`.
- Texto UI en español argentino (voseo).
- Mecanismos existentes confirmados: modales usan `openModal(id)`/`closeModal(id)` con clase `.modal-overlay.open`; botones de alta: Nueva venta=`openModal('modal-venta')`, Nuevo presupuesto=`openPresupuestoModal()`, Nueva OP=`openModal('modal-op')`, Nueva OC=`openOCModal()`.
- Campos confirmados: clientes→`nombre`,`cuit` · ventas→`nro_remito`,`nro_pedido`,`cliente`,`total`,`fecha` · presupuestos→`nro`,`cliente`,`estado`,`fecha` · ops→`nro`,`pieza`,`fecha`,`presupuesto_id` · barras→`lote`,`material` · pts→`lote`,`pieza` · certs→`nro`,`material`,`colada` · proveedores→`nombre` · ordenesCompra→`nro`,`fecha` · cheques→`numero`,`banco`,`tipo`,`estado`,`fecha_pago`,`fecha_recepcion` · noConformidades→`numero`,`descripcion`,`fecha`.

Comando de validación (usar en cada task, es el mismo del CI):

```bash
cd ~/vitalmet-erp && python3 -c "
import re
html = open('index.html').read()
scripts = re.findall(r'<script>(.*?)</script>', html, re.S)
open('/tmp/erp_script.js','w').write(max(scripts, key=len))
" && node --check /tmp/erp_script.js && node --test tests/*.test.js
```

---

### Task 1: Sticky headers (2E) — solo CSS

**Files:**
- Modify: `index.html` — regla `.table-wrap` (línea ~104) y `thead th` (línea ~106), media query mobile (~227+).

**Interfaces:**
- Produces: headers fijos en todas las tablas. Nada consumido por otras tasks.

- [ ] **Step 1: Editar el CSS**

Reemplazar la regla `.table-wrap{...}` por:

```css
.table-wrap{background:var(--surface);border:1px solid var(--border);border-radius:6px;overflow:auto;max-height:calc(100vh - 230px)}
```

Y agregarle a la regla existente `thead th{...}` (que ya tiene `background:var(--surface2)`) las propiedades: `position:sticky;top:0;z-index:2`.

- [ ] **Step 2: Verificación visual local**

Abrir la app y scrollear una tabla larga (libro diario o ventas): el header queda fijo, los `estadoSelect` inline pasan por debajo, sin transparencias. En una tabla corta no cambia nada (max-height solo limita si excede). En mobile (DevTools ≤768px) verificar que no rompa; si el max-height molesta, agregar `.table-wrap{max-height:none}` dentro de la media query.

- [ ] **Step 3: Commit**

```bash
git add index.html && git commit -m "feat(ux): sticky headers en todas las tablas"
```

---

### Task 2: Sort global de tablas (2C)

**Files:**
- Modify: `index.html` — funciones puras junto a la sección de helpers (cerca de `esc()`), listener de delegación + `applyTableSort` al final del script (zona de listeners), hook en `renderPage`.
- Create: `tests/sort.test.js`

**Interfaces:**
- Consumes: `renderPage(p)` (hook existente), CSS de Task 1.
- Produces: `parseCellValue(str) → {tipo:'num'|'fecha'|'texto'|'vacio', v}`; `detectColType(values[]) → 'num'|'fecha'|'texto'`; `compareCells(a, b, tipo) → number`; `applyTableSort(tbodyId)`; estado global `_tableSorts={[tbodyId]:{col,dir}}`. Usados también por la verificación de Task 5 (los filtros re-renderizan y el sort debe persistir).

- [ ] **Step 1: Tests que fallan (`tests/sort.test.js`)**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('parseCellValue detecta números con formato US$/miles', () => {
  const r = erp.run(`[parseCellValue('US$ 1.234,50').v,parseCellValue('US$ 1.234,50').tipo,parseCellValue('85%').v,parseCellValue('12,5').v]`);
  assert.deepStrictEqual(Array.from(r), [1234.5, 'num', 85, 12.5]);
});

test('parseCellValue detecta fechas ISO y DD/MM/YYYY', () => {
  const r = erp.run(`[parseCellValue('2026-07-07').v,parseCellValue('07/03/2026').v,parseCellValue('—').tipo,parseCellValue('').tipo]`);
  assert.deepStrictEqual(Array.from(r), ['2026-07-07', '2026-03-07', 'vacio', 'vacio']);
});

test('detectColType decide por mayoría (60%)', () => {
  const r = erp.run(`[detectColType(['US$ 10','US$ 20','—','texto']),detectColType(['2026-01-01','2026-02-01','—']),detectColType(['Anillo BX','Unión 2"','10'])]`);
  assert.deepStrictEqual(Array.from(r), ['num', 'fecha', 'texto']);
});

test('compareCells ordena y manda vacíos al final', () => {
  const r = erp.run(`(()=>{
    const vals=['US$ 300','—','US$ 25','US$ 1.000'];
    return vals.slice().sort((a,b)=>compareCells(a,b,'num'));
  })()`);
  assert.deepStrictEqual(Array.from(r), ['US$ 25', 'US$ 300', 'US$ 1.000', '—']);
});
```

- [ ] **Step 2: Correr y ver fallar**

Run: `node --test tests/sort.test.js` → FAIL con `parseCellValue is not defined`.

- [ ] **Step 3: Implementar las funciones puras** (junto a `esc()` en el script)

```js
// ─── Sort de tablas: parsers puros (tests/sort.test.js) ──────────
function parseCellValue(s){
  const t=(s||'').trim();
  if(!t||t==='—')return{tipo:'vacio',v:null};
  let m=t.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if(m)return{tipo:'fecha',v:t.slice(0,10)};
  m=t.match(/^(\d{2})\/(\d{2})\/(\d{4})/);
  if(m)return{tipo:'fecha',v:`${m[3]}-${m[2]}-${m[1]}`};
  const num=t.replace(/US\$|\$|%|\s/g,'').replace(/\.(?=\d{3}(\D|$))/g,'').replace(',','.');
  if(num&&!isNaN(Number(num)))return{tipo:'num',v:Number(num)};
  return{tipo:'texto',v:t.toLowerCase()};
}
function detectColType(values){
  const parsed=values.map(parseCellValue).filter(p=>p.tipo!=='vacio');
  if(!parsed.length)return'texto';
  const counts={};parsed.forEach(p=>counts[p.tipo]=(counts[p.tipo]||0)+1);
  if((counts.num||0)>=parsed.length*0.6)return'num';
  if((counts.fecha||0)>=parsed.length*0.6)return'fecha';
  return'texto';
}
function compareCells(a,b,tipo){
  const pa=parseCellValue(a),pb=parseCellValue(b);
  if(pa.tipo==='vacio'&&pb.tipo==='vacio')return 0;
  if(pa.tipo==='vacio')return 1;
  if(pb.tipo==='vacio')return -1;
  if(tipo==='num'){const va=pa.tipo==='num'?pa.v:-Infinity,vb=pb.tipo==='num'?pb.v:-Infinity;return va-vb;}
  if(tipo==='fecha'){const va=pa.tipo==='fecha'?pa.v:'',vb=pb.tipo==='fecha'?pb.v:'';return va<vb?-1:va>vb?1:0;}
  return String(pa.v).localeCompare(String(pb.v),'es');
}
```

- [ ] **Step 4: Tests → PASS** (`node --test tests/sort.test.js`)

- [ ] **Step 5: Delegación global + re-aplicación**

Al final del script (zona de listeners globales):

```js
// ─── Sort de tablas: delegación global ──────────
let _tableSorts={};
document.addEventListener('click',e=>{
  const th=e.target.closest('thead th');
  if(!th||e.target.closest('button,select,input,a'))return;
  if(!th.textContent.replace(/[▲▼\s]/g,''))return; // columnas de acciones vacías
  const tbody=th.closest('table')?.querySelector('tbody');
  if(!tbody||!tbody.id)return;
  const col=Array.from(th.parentNode.children).indexOf(th);
  const prev=_tableSorts[tbody.id];
  _tableSorts[tbody.id]={col,dir:prev&&prev.col===col&&prev.dir==='asc'?'desc':'asc'};
  applyTableSort(tbody.id);
});
function applyTableSort(tbodyId){
  const st=_tableSorts[tbodyId];if(!st)return;
  const tbody=document.getElementById(tbodyId);if(!tbody)return;
  const rows=Array.from(tbody.querySelectorAll(':scope > tr')).filter(r=>!r.querySelector('td[colspan]'));
  if(rows.length>1){
    const vals=rows.map(r=>(r.children[st.col]?.textContent)||'');
    const tipo=detectColType(vals);
    rows.map((r,i)=>({r,v:vals[i]}))
      .sort((a,b)=>{const c=compareCells(a.v,b.v,tipo);return st.dir==='asc'?c:-c;})
      .forEach(x=>tbody.appendChild(x.r));
  }
  const table=tbody.closest('table');if(!table)return;
  table.querySelectorAll('thead th').forEach((th,i)=>{
    th.querySelector('.sort-ind')?.remove();
    th.removeAttribute('aria-sort');
    if(i===st.col){
      th.setAttribute('aria-sort',st.dir==='asc'?'ascending':'descending');
      const s=document.createElement('span');s.className='sort-ind';s.textContent=st.dir==='asc'?' ▲':' ▼';
      th.appendChild(s);
    }
  });
}
```

CSS: agregar a la regla de `thead th` → `cursor:pointer;user-select:none`, y nueva regla `.sort-ind{color:var(--accent);font-size:9px}`.

En `renderPage(p)` (busca `function renderPage`), después de `animateNumbers();applyIconButtonLabels();` agregar:

```js
  document.querySelectorAll(`#page-${p} tbody[id]`).forEach(tb=>{if(_tableSorts[tb.id])applyTableSort(tb.id);});
```

- [ ] **Step 6: Validar (comando global), commit, deploy, verificar**

```bash
git add index.html tests/sort.test.js
git commit -m "feat(ux): sort por columna en todas las tablas (delegación global + reaplicación post-render)"
git push origin main
```

Verificar en prod: click en "Total" de Ventas ordena asc/desc con ▲▼; guardar algo re-renderiza y el orden persiste; columnas de fecha y texto ordenan bien.

---

### Task 3: Deep-links entre registros (2B)

**Files:**
- Modify: `index.html` — `showPage`, `renderPage`, CSS `.row-flash`, `<tr>` de 10 renders, cross-links en renderVentas/renderOP/renderPresupuestos.

**Interfaces:**
- Consumes: `showPage(p)`/`renderPage(p)`/`_dirtyPages` existentes.
- Produces: `showPage(p, recordId)` (segundo parámetro opcional, usado por el palette en Task 4); `resolveHighlight(p)`; filas con `data-id` en: ventas, presupuestos, clientes, op, mp, pt, cert, compras (OCs), cheques, ncr.

- [ ] **Step 1: showPage con recordId + resolución post-render**

En `function showPage(p){` cambiar la firma a `function showPage(p,recordId){` y, justo antes del cierre de la función, agregar:

```js
  if(recordId){
    _pendingHighlight={page:p,id:recordId};
    if(!_dirtyPages.has(p))resolveHighlight(p); // ya estaba renderizada
  }
```

Nueva variable y función (junto a showPage):

```js
let _pendingHighlight=null;
function resolveHighlight(p){
  if(!_pendingHighlight||_pendingHighlight.page!==p)return;
  const id=_pendingHighlight.id;_pendingHighlight=null;
  const el=document.querySelector(`#page-${p} [data-id="${id}"]`);
  if(!el)return;
  el.scrollIntoView({block:'center',behavior:'smooth'});
  el.classList.add('row-flash');
  setTimeout(()=>el.classList.remove('row-flash'),2100);
}
```

En `renderPage(p)`, después de la línea de sort agregada en Task 2: `resolveHighlight(p);`

CSS nuevo: `.row-flash{animation:rowFlash 2s ease-out}` + `@keyframes rowFlash{0%{background:rgba(227,161,66,.35)}100%{background:transparent}}` (el bloque `prefers-reduced-motion` existente ya anula animaciones).

- [ ] **Step 2: data-id en las filas**

En cada render, el `<tr>` raíz del `.map` pasa a llevar `data-id`. Funciones y variable del map (verificar el nombre del `<tr>` con grep dentro de cada función antes de editar):

| Render | Variable | Edit |
|---|---|---|
| `renderVentas` | `v` | `<tr data-id="${v.id}">` |
| `renderPresupuestos` | `p` | `<tr data-id="${p.id}">` |
| `renderClientes` | `c` | `<tr data-id="${c.id}">` |
| `renderOP` | `o` | `<tr data-id="${o.id}">` |
| render de materia prima (buscar `mp-tbody`) | según código | ídem |
| render de PT (buscar `pt-tbody`) | según código | ídem |
| render de certificados (buscar `cert-tbody`) | según código | ídem |
| render de OCs (buscar `oc-tbody` o similar) | `oc` | ídem |
| `renderCheques` | `c` | ídem |
| `renderNCR` | `n` | ídem |

- [ ] **Step 3: Cross-links clickeables**

1. **Venta → cliente**: en `renderVentas`, la celda del cliente pasa de `${esc(v.cliente)}` a:
```js
`<span onclick="event.stopPropagation();linkCliente('${esc(v.cliente)}')" style="cursor:pointer;text-decoration:underline dotted;text-underline-offset:3px">${esc(v.cliente)}</span>`
```
con helper (junto a resolveHighlight):
```js
function linkCliente(nombre){
  const c=clientes.find(x=>(x.nombre||'').toLowerCase()===nombre.toLowerCase());
  showPage('clientes',c?c.id:undefined);
}
```
2. **OP → presupuesto**: al span `⚙ ${presupOP.nro}` agregado en P1 (buscar `presupOP` en `renderOP`), agregarle `onclick="event.stopPropagation();showPage('presupuestos','${o.presupuesto_id}')" ` y `cursor:pointer` en el style.
3. **Presupuesto → OP**: al badge `opsBadge` de P1 (buscar `opsVinc` en `renderPresupuestos`), agregarle `onclick="event.stopPropagation();showPage('op','${opsVinc[0]?.id}')"` y `cursor:pointer`.

- [ ] **Step 4: Validar (comando global — 41 tests deben pasar), commit**

```bash
git add index.html
git commit -m "feat(ux): deep-links entre registros — showPage(page,id), data-id, flash y cross-links"
```

---

### Task 4: Command palette Ctrl+K (2A)

**Files:**
- Modify: `index.html` — HTML del modal (junto a los otros modales), botón en el sidebar (junto al toggle de tema, línea ~383), funciones + listeners al final del script.
- Create: `tests/palette.test.js`

**Interfaces:**
- Consumes: `showPage(p, id)` (Task 3), globals de datos, `GROUP_TABS`, `openModal`, `openPresupuestoModal()`, `openOCModal()`, `esc()`.
- Produces: `paletteMatch(query, items) → items ordenados` (pura); `openPalette()`; `buildPaletteIndex() → [{cat,label,page?,id?,run?}]`.

- [ ] **Step 1: Tests que fallan (`tests/palette.test.js`)**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('paletteMatch: multi-término AND, scoring exacto > empieza > contiene', () => {
  const r = erp.run(`(()=>{
    const items=[
      {cat:'Clientes',label:'Yacimientos del Sur SA'},
      {cat:'Ventas',label:'V-00212 · Yacimientos del Sur SA'},
      {cat:'Clientes',label:'Sur Metal SRL'},
      {cat:'Ventas',label:'V-00212'},
    ];
    return {
      yaci: paletteMatch('yacim',items).map(i=>i.label),
      exact: paletteMatch('V-00212',items)[0].label,
      and: paletteMatch('sur metal',items).map(i=>i.label),
      vacio: paletteMatch('zzz',items).length,
    };
  })()`);
  assert.deepStrictEqual(Array.from(r.yaci), ['Yacimientos del Sur SA', 'V-00212 · Yacimientos del Sur SA']);
  assert.strictEqual(r.exact, 'V-00212');
  assert.deepStrictEqual(Array.from(r.and), ['Sur Metal SRL']);
  assert.strictEqual(r.vacio, 0);
});

test('paletteMatch limita a 4 por categoría', () => {
  const r = erp.run(`(()=>{
    const items=Array.from({length:9},(_,i)=>({cat:'Ventas',label:'V-'+i+' pepe'}));
    return paletteMatch('pepe',items).length;
  })()`);
  assert.strictEqual(r, 4);
});
```

- [ ] **Step 2: Correr y ver fallar** → `paletteMatch is not defined`.

- [ ] **Step 3: Implementar paletteMatch (pura, junto a los parsers de sort)**

```js
// ─── Command palette: matching puro (tests/palette.test.js) ──────────
function paletteMatch(query,items){
  const terms=query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  if(!terms.length)return[];
  const scored=[];
  items.forEach(it=>{
    const l=(it.label||'').toLowerCase();
    if(!terms.every(t=>l.includes(t)))return;
    let score=1;
    if(l===terms.join(' '))score=3;
    else if(terms.some(t=>l.startsWith(t)))score=2;
    scored.push({it,score});
  });
  scored.sort((a,b)=>b.score-a.score||a.it.label.localeCompare(b.it.label,'es'));
  const porCat={},out=[];
  scored.forEach(({it})=>{
    porCat[it.cat]=(porCat[it.cat]||0)+1;
    if(porCat[it.cat]<=4)out.push(it);
  });
  return out;
}
```

- [ ] **Step 4: Tests → PASS.**

- [ ] **Step 5: HTML del modal + botón sidebar**

Antes del modal `modal-gen-op-item` (o junto a cualquier otro modal), insertar:

```html
<!-- MODAL: Command palette (Ctrl+K) -->
<div class="modal-overlay" id="modal-palette">
  <div class="modal" style="width:560px;align-self:flex-start;margin-top:10vh">
    <div class="modal-body" style="padding:12px">
      <input type="text" id="palette-input" placeholder="Buscar clientes, ventas, OPs, páginas… (Esc para cerrar)" autocomplete="off" style="width:100%;font-size:14px;padding:10px 12px">
      <div id="palette-results" style="margin-top:8px;max-height:50vh;overflow-y:auto"></div>
    </div>
  </div>
</div>
```

En el sidebar, junto al botón de tema (buscar `toggleTheme` en el HTML, ~línea 383), agregar:

```html
<button class="btn-logout" onclick="openPalette()" title="Buscar (Ctrl+K)" aria-label="Buscar" style="margin-right:4px">⌕</button>
```

(Usar la misma clase/estilo del botón de tema contiguo; copiar su markup exacto al implementar.)

- [ ] **Step 6: Índice, render y teclado**

Al final del script:

```js
// ─── Command palette ──────────
let _palItems=[],_palSel=0;
function buildPaletteIndex(){
  const ix=[];
  clientes.forEach(c=>ix.push({cat:'Clientes',label:`${c.nombre}${c.cuit?' · '+c.cuit:''}`,page:'clientes',id:c.id}));
  ventas.forEach(v=>ix.push({cat:'Ventas',label:`${v.nro_remito||v.nro_pedido||''} · ${v.cliente||''} · ${fmtUSD(parseFloat(v.total||0))}`,page:'ventas',id:v.id}));
  presupuestos.forEach(p=>ix.push({cat:'Presupuestos',label:`${p.nro||''} · ${p.cliente||''} (${p.estado||''})`,page:'presupuestos',id:p.id}));
  ops.forEach(o=>ix.push({cat:'Órdenes de producción',label:`${o.nro||''} · ${o.pieza||''}`,page:'op',id:o.id}));
  barras.forEach(b=>ix.push({cat:'Materia prima',label:`${b.lote||''} · ${b.material||''}`,page:'mp',id:b.id}));
  pts.forEach(p=>ix.push({cat:'Prod. terminados',label:`${p.lote||''} · ${p.pieza||''}`,page:'pt',id:p.id}));
  certs.forEach(c=>ix.push({cat:'Certificados',label:`${c.nro||''} · ${c.material||''}${c.colada?' · colada '+c.colada:''}`,page:'cert',id:c.id}));
  proveedores.forEach(p=>ix.push({cat:'Proveedores',label:p.nombre||'',page:'compras',id:p.id}));
  cheques.forEach(c=>ix.push({cat:'Cheques',label:`${c.numero||''} · ${c.banco||''} (${c.estado||''})`,page:'cheques',id:c.id}));
  noConformidades.forEach(n=>ix.push({cat:'NCR',label:`${n.numero||''} · ${(n.descripcion||'').slice(0,50)}`,page:'ncr',id:n.id}));
  // Páginas
  const vistos=new Set();
  Object.values(GROUP_TABS).flat().forEach(t=>{
    (t.sub||[t]).forEach(s=>{if(!vistos.has(s.k)){vistos.add(s.k);ix.push({cat:'Páginas',label:'Ir a '+s.l,run:()=>showPage(s.k)});}});
  });
  ix.push({cat:'Páginas',label:'Ir a Métricas',run:()=>showPage('dash')});
  // Acciones
  ix.push({cat:'Acciones',label:'⚡ Nueva venta',run:()=>openModal('modal-venta')});
  ix.push({cat:'Acciones',label:'⚡ Nuevo presupuesto',run:()=>openPresupuestoModal()});
  ix.push({cat:'Acciones',label:'⚡ Nueva orden de producción',run:()=>openModal('modal-op')});
  ix.push({cat:'Acciones',label:'⚡ Nueva orden de compra',run:()=>openOCModal()});
  return ix;
}
let _palIndex=null;
function openPalette(){
  _palIndex=buildPaletteIndex();
  openModal('modal-palette');
  const inp=document.getElementById('palette-input');
  inp.value='';renderPaletteResults('');
  setTimeout(()=>inp.focus(),50);
}
function renderPaletteResults(q){
  const cont=document.getElementById('palette-results');
  _palItems=q.trim()?paletteMatch(q,_palIndex):_palIndex.filter(i=>i.cat==='Acciones'||i.cat==='Páginas').slice(0,10);
  _palSel=0;
  if(!_palItems.length){cont.innerHTML='<div style="padding:14px;text-align:center;color:var(--text3);font-size:12px">Sin resultados</div>';return;}
  let lastCat=null;
  cont.innerHTML=_palItems.map((it,i)=>{
    const header=it.cat!==lastCat?`<div style="font-size:9px;text-transform:uppercase;letter-spacing:1.2px;color:var(--text3);padding:8px 10px 3px">${esc(it.cat)}</div>`:'';
    lastCat=it.cat;
    return header+`<div class="palette-item${i===_palSel?' sel':''}" data-i="${i}" onclick="execPaletteItem(${i})" style="padding:8px 10px;border-radius:4px;cursor:pointer;font-size:13px">${esc(it.label)}</div>`;
  }).join('');
  updatePaletteSel();
}
function updatePaletteSel(){
  document.querySelectorAll('.palette-item').forEach(el=>{
    const sel=parseInt(el.dataset.i)===_palSel;
    el.style.background=sel?'var(--surface2)':'transparent';
    el.style.outline=sel?'1px solid var(--accent)':'none';
    if(sel)el.scrollIntoView({block:'nearest'});
  });
}
function execPaletteItem(i){
  const it=_palItems[i];if(!it)return;
  closeModal('modal-palette');
  if(it.run)it.run();
  else showPage(it.page,it.id);
}
document.addEventListener('keydown',e=>{
  if((e.ctrlKey||e.metaKey)&&(e.key==='k'||e.key==='K')){e.preventDefault();openPalette();return;}
  const overlay=document.getElementById('modal-palette');
  if(!overlay||!overlay.classList.contains('open'))return;
  if(e.key==='Escape'){e.preventDefault();closeModal('modal-palette');}
  else if(e.key==='ArrowDown'){e.preventDefault();_palSel=Math.min(_palSel+1,_palItems.length-1);updatePaletteSel();}
  else if(e.key==='ArrowUp'){e.preventDefault();_palSel=Math.max(_palSel-1,0);updatePaletteSel();}
  else if(e.key==='Enter'&&_palItems.length){e.preventDefault();execPaletteItem(_palSel);}
});
document.getElementById('palette-input').addEventListener('input',e=>renderPaletteResults(e.target.value));
```

Nota: el `addEventListener` sobre `palette-input` corre al cargar el script — el input ya existe en el DOM (el script está al final del body). Si el harness de tests fallara por esto, mover esa línea dentro de un guard `if(document.getElementById('palette-input'))` (el stub del harness devuelve elementos con addEventListener no-op, así que no debería fallar).

- [ ] **Step 7: Validar (comando global), commit, deploy, verificar**

```bash
git add index.html tests/palette.test.js
git commit -m "feat(ux): command palette Ctrl+K — búsqueda global de registros, páginas y acciones"
git push origin main
```

Verificar en prod: Ctrl+K abre; tipear un cliente → Enter → aterriza en Clientes con la fila flasheada; "nueva venta" → abre el modal; Esc cierra; ↑/↓ navegan; el botón ⌕ del sidebar funciona (mobile).

---

### Task 5: Filtros de fecha (2D)

**Files:**
- Modify: `index.html` — toolbars de ventas/presupuestos/compras(OC)/op/cheques, sus renders, helper puro.
- Test: agregar caso a `tests/sort.test.js`.

**Interfaces:**
- Consumes: renders existentes (`renderVentas`, `renderPresupuestos`, render de OCs, `renderOP`, `renderCheques`).
- Produces: `enRango(fecha, desde, hasta) → bool` (pura).

- [ ] **Step 1: Test que falla** (agregar a `tests/sort.test.js`)

```js
test('enRango filtra por fecha inclusive, vacío = sin límite', () => {
  const r = erp.run(`[enRango('2026-07-07','2026-07-01','2026-07-31'),enRango('2026-07-07','','2026-07-06'),enRango('2026-07-07','',''),enRango('','2026-07-01',''),enRango(null,'','')]`);
  assert.deepStrictEqual(Array.from(r), [true, false, true, false, true]);
});
```

- [ ] **Step 2: Ver fallar** → `enRango is not defined`.

- [ ] **Step 3: Implementar** (junto a los parsers de sort):

```js
function enRango(fecha,desde,hasta){
  if(!fecha)return!(desde||hasta)?true:false;
  const f=String(fecha).slice(0,10);
  return(!desde||f>=desde)&&(!hasta||f<=hasta);
}
```

Ojo: `enRango(null,'','')` debe dar `true` (sin filtro no excluye) y `enRango('',desde,'')` da `false` (hay filtro y el registro no tiene fecha). La implementación de arriba cumple ambos.

- [ ] **Step 4: Tests → PASS.**

- [ ] **Step 5: Inputs en las toolbars + wiring de renders**

Para cada módulo, en su `.toolbar` junto al `.search-box`, insertar (ejemplo ventas — repetir cambiando el prefijo y el render):

```html
<input type="date" id="ventas-fdesde" onchange="renderVentas(document.querySelector('#page-ventas .search-box input').value)" title="Desde" style="width:auto">
<input type="date" id="ventas-fhasta" onchange="renderVentas(document.querySelector('#page-ventas .search-box input').value)" title="Hasta" style="width:auto">
```

Módulos y campo de fecha a filtrar:
| Módulo | Prefijo ids | Render | Campo |
|---|---|---|---|
| Ventas | `ventas-` | `renderVentas` | `v.fecha` |
| Presupuestos | `presup-f` | `renderPresupuestos` | `p.fecha` |
| Compras (OCs) | `oc-f` | render de OCs (buscar `oc-tbody`) | `oc.fecha` |
| OPs | `opf-` | `renderOP` | `o.fecha` |
| Cheques | `chq-f` | `renderCheques` | `c.fecha_pago||c.fecha_recepcion` |

En cada render, donde se filtra la lista por texto, agregar el filtro de rango. Ejemplo ventas:

```js
const fd=document.getElementById('ventas-fdesde')?.value||'',fh=document.getElementById('ventas-fhasta')?.value||'';
const list=ventas.filter(v=>(!f||v.nro_remito.toLowerCase().includes(f)||v.cliente.toLowerCase().includes(f))&&enRango(v.fecha,fd,fh));
```

(Los ids con prefijo distinto por módulo evitan colisiones; usar el patrón exacto de filtro de cada render y sumarle `&&enRango(...)`.)

- [ ] **Step 6: Validar (comando global), commit, deploy, verificar (cierra P2)**

```bash
git add index.html tests/sort.test.js
git commit -m "feat(ux): filtros de rango de fechas en ventas, presupuestos, compras, OPs y cheques"
git push origin main
```

Verificar en prod: acotar ventas a un mes muestra solo esas; combinado con texto funciona; limpiar los inputs restaura todo; el sort sigue aplicándose tras filtrar.

---

## Self-review (hecho al escribir el plan)

- **Cobertura de spec:** 2E→Task 1, 2C→Task 2, 2B→Task 3, 2A→Task 4, 2D→Task 5. ✓
- **Sin placeholders:** los únicos lookups en sitio son nombres de renders/vars de map de módulos secundarios (tabla en Task 3) y el markup exacto del botón de tema (Task 4) — instrucciones explícitas de 1 minuto, no diseño pendiente. ✓
- **Consistencia:** `parseCellValue/detectColType/compareCells/applyTableSort/_tableSorts` (T2) usados en el hook de T2 y verificación de T5; `showPage(p,recordId)/resolveHighlight` (T3) consumidos por `execPaletteItem` (T4); `paletteMatch/buildPaletteIndex/openPalette` coherentes. ✓
