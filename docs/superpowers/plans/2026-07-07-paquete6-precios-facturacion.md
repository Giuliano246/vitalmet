# Paquete 6 — Precios/Facturación: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tabla de precios base editable con reprecio masivo, autocompletado de precio en venta/presupuesto (último precio al cliente → base → PT), y facturación en lote de entregadas.

**Architecture:** Migración 049 (`precios_base`, ya commiteada) + página "precios" en el grupo Ventas + función pura `resolverPrecio` testeada + wiring en los dos puntos de alta de ítems + botón de lote que reusa `emitirFactura`. `precios_base` entra al registro `TBL` (P5).

**Tech Stack:** vanilla JS + PostgREST, tests harness vm, deploy Netlify.

**Spec:** `docs/superpowers/specs/2026-07-07-paquete6-precios-facturacion-design.md`

## Global Constraints

- Migración 049 corrida en SQL Editor ANTES del push del frontend.
- Reglas CLAUDE.md (validación por task: snippet + `node --check` + `node --test tests/*.test.js`; voseo; `esc()`; `empresa_id` en POSTs).
- El precio autocompletado SIEMPRE queda editable; el resolver nunca pisa un precio ya tipeado por el usuario (solo se aplica al seleccionar pieza).

---

### Task 1: Registro TBL + página Precios (6A)

**Files:**
- Modify: `index.html` — entrada en `TBL`, registro de página (`PAGE_TO_GROUP` `precios:'ventas'`, `GROUP_TABS.ventas` `+{k:'precios',l:'Precios'}`, `groupMods.ventas` `+'precios'`, `PAGE_RENDERS` `precios:[renderPrecios]`), HTML `#page-precios`, JS render + acciones.

**Interfaces:**
- Produces: global `preciosBase=[]`; entrada `TBL.precios_base`; `renderPrecios()`, `savePrecioBase(id)`, `nuevoPrecioBase()`, `ajustarPreciosPct()`, `importarPreciosDesdeStock()`.

- [ ] **Step 1:** Global `let preciosBase=[];` + entrada en `TBL`: `precios_base:{label:'Precios base',q:'?order=pieza.asc',set:r=>{preciosBase=r||[];}},`
- [ ] **Step 2:** HTML de la página (después de `#page-mailings`), siguiendo el patrón de páginas existentes:

```html
<!-- PRECIOS BASE -->
<div class="page" id="page-precios">
  <div class="page-header"><div class="page-title">Precios de venta</div><div class="page-sub">// precio de lista USD por pieza — el último precio al cliente manda</div><div class="tabs"></div></div>
  <div class="page-content">
    <div class="stats-bar" id="precios-stats"></div>
    <div class="toolbar">
      <div class="search-box"><input type="text" placeholder="Buscar pieza..." oninput="renderPrecios(this.value)"></div>
      <div style="display:flex;gap:6px">
        <button class="btn btn-ghost" onclick="importarPreciosDesdeStock()" title="Crea entradas para las piezas del stock PT que aún no tienen precio base">Importar desde stock</button>
        <button class="btn btn-ghost" onclick="ajustarPreciosPct()" style="border-color:var(--accent);color:var(--accent)">Ajustar todo %</button>
        <button class="btn" onclick="nuevoPrecioBase()" style="background:var(--accent);color:white">+ Pieza</button>
      </div>
    </div>
    <div class="table-wrap"><table><thead><tr><th>Pieza</th><th>Precio USD</th><th>Actualizado</th><th></th></tr></thead><tbody id="precios-tbody"></tbody></table></div>
  </div>
</div>
```

- [ ] **Step 3:** JS (render con edición inline + acciones):

```js
// ═══ PRECIOS BASE ═══
function renderPrecios(filter=''){
  const f=(filter||'').toLowerCase();
  const el=document.getElementById('precios-stats');if(!el)return;
  el.innerHTML=`<div class="stat-card"><div class="stat-label">Piezas con precio</div><div class="stat-value" style="color:var(--accent)">${preciosBase.length}</div></div>
    <div class="stat-card"><div class="stat-label">Piezas en stock sin precio</div><div class="stat-value" style="color:var(--coral)">${[...new Set(pts.map(p=>(p.pieza||'').trim().toLowerCase()))].filter(x=>x&&!preciosBase.some(pb=>pb.pieza.trim().toLowerCase()===x)).length}</div></div>`;
  const list=preciosBase.filter(p=>!f||p.pieza.toLowerCase().includes(f));
  document.getElementById('precios-tbody').innerHTML=list.length?list.map(p=>`<tr data-id="${p.id}">
    <td style="font-weight:500">${esc(p.pieza)}</td>
    <td><input type="number" step="0.01" min="0" value="${parseFloat(p.precio_usd)||0}" style="width:120px" onchange="savePrecioBase('${p.id}',this.value)"></td>
    <td class="mono" style="font-size:11px;color:var(--text3)">${(p.updated_at||'').slice(0,10)}</td>
    <td><button class="btn btn-danger btn-sm" onclick="deletePrecioBase('${p.id}')" aria-label="Eliminar">×</button></td></tr>`).join('')
    :'<tr><td colspan="4" style="text-align:center;color:var(--text3);padding:24px">Sin precios cargados — arrancá con <b>Importar desde stock</b></td></tr>';
}
async function savePrecioBase(id,valor){
  try{await PATCH('precios_base',{precio_usd:parseFloat(valor)||0},`?id=eq.${id}`);await reload('precios_base');renderPrecios();notify('Precio actualizado');}
  catch(e){notify('Error: '+e.message,'err');}
}
async function deletePrecioBase(id){
  const p=preciosBase.find(x=>x.id===id);
  if(!confirm(`¿Eliminar el precio base de "${p?.pieza||''}"?`))return;
  try{await DEL('precios_base',`?id=eq.${id}`);await reload('precios_base');renderPrecios();notify('Eliminado');}
  catch(e){notify('Error: '+e.message,'err');}
}
async function nuevoPrecioBase(){
  const pieza=prompt('Pieza:');if(!pieza||!pieza.trim())return;
  const precio=parseFloat(prompt('Precio USD:'))||0;
  try{await POST('precios_base',{empresa_id:currentEmpresa.id,pieza:pieza.trim(),precio_usd:precio});await reload('precios_base');renderPrecios();notify('Precio agregado');}
  catch(e){notify('Error: '+e.message,'err');}
}
async function ajustarPreciosPct(){
  if(!preciosBase.length){notify('No hay precios para ajustar');return;}
  const pct=parseFloat(prompt(`Ajuste porcentual sobre ${preciosBase.length} piezas (ej: 8 para +8%, -5 para bajar 5%):`));
  if(isNaN(pct)||pct===0)return;
  if(!confirm(`¿Ajustar los ${preciosBase.length} precios en ${pct>0?'+':''}${pct}%?`))return;
  try{
    for(const p of preciosBase){await PATCH('precios_base',{precio_usd:Math.round((parseFloat(p.precio_usd)||0)*(1+pct/100)*100)/100},`?id=eq.${p.id}`);}
    await reload('precios_base');renderPrecios();notify(`✓ ${preciosBase.length} precios ajustados ${pct>0?'+':''}${pct}%`);
  }catch(e){notify('Error: '+e.message,'err');}
}
async function importarPreciosDesdeStock(){
  const existentes=new Set(preciosBase.map(p=>p.pieza.trim().toLowerCase()));
  const nuevos={};
  [...pts].sort((a,b)=>(a.created_at||'').localeCompare(b.created_at||'')).forEach(p=>{
    const k=(p.pieza||'').trim();if(!k||existentes.has(k.toLowerCase()))return;
    nuevos[k.toLowerCase()]={empresa_id:currentEmpresa.id,pieza:k,precio_usd:parseFloat(p.precio_unitario)||0}; // el más reciente pisa
  });
  const rows=Object.values(nuevos);
  if(!rows.length){notify('Todas las piezas del stock ya tienen precio');return;}
  if(!confirm(`Se van a crear ${rows.length} precios desde el stock PT. ¿Continuar?`))return;
  try{await POST('precios_base',rows);await reload('precios_base');renderPrecios();notify(`✓ ${rows.length} precios importados`);}
  catch(e){notify('Error: '+e.message,'err');}
}
```

- [ ] **Step 4:** Registro de página (4 estructuras) + validar + commit: `feat(precios): página Precios base — edición inline, ajuste % masivo e importación desde stock`

---

### Task 2: resolverPrecio + wiring (6B)

**Files:**
- Modify: `index.html`; Create: `tests/precios.test.js`.

**Interfaces:**
- Consumes: `preciosBase`, `ventas` (con `venta_items(*, productos_terminados(lote,pieza))`), `pts`.
- Produces: `resolverPrecio(pieza, cliente, ventasArr, preciosArr, ptsArr) → {precio, origen}` (pura).

- [ ] **Step 1: Test que falla** (`tests/precios.test.js`, boilerplate del harness):

```js
test('resolverPrecio: último al cliente > base > PT > 0', () => {
  const r = erp.run(`(()=>{
    const ventasArr=[
      {cliente:'ACME SA',estado:'facturado',created_at:'2026-06-01',venta_items:[{precio_unitario:120,productos_terminados:{pieza:'Anillo BX'}}]},
      {cliente:'ACME SA',estado:'entregado',created_at:'2026-07-01',venta_items:[{precio_unitario:150,productos_terminados:{pieza:'Anillo BX'}}]},
      {cliente:'Otro SRL',estado:'facturado',created_at:'2026-07-02',venta_items:[{precio_unitario:99,productos_terminados:{pieza:'Anillo BX'}}]},
    ];
    const precios=[{pieza:'Anillo BX',precio_usd:130},{pieza:'Unión 2',precio_usd:80}];
    const ptsArr=[{pieza:'Codo 90',precio_unitario:55,created_at:'2026-01-01'}];
    return {
      cli: resolverPrecio('anillo bx','ACME SA',ventasArr,precios,ptsArr),
      base: resolverPrecio('Unión 2','Nuevo SA',ventasArr,precios,ptsArr),
      pt: resolverPrecio('Codo 90','Nuevo SA',ventasArr,precios,ptsArr),
      nada: resolverPrecio('Inexistente','X',ventasArr,precios,ptsArr),
    };
  })()`);
  assert.deepStrictEqual({...r.cli},{precio:150,origen:'cliente'});   // la más reciente de ACME
  assert.deepStrictEqual({...r.base},{precio:80,origen:'base'});
  assert.deepStrictEqual({...r.pt},{precio:55,origen:'pt'});
  assert.deepStrictEqual({...r.nada},{precio:0,origen:null});
});
```

- [ ] **Step 2: Implementar** (junto a las funciones puras existentes):

```js
function resolverPrecio(pieza,cliente,ventasArr,preciosArr,ptsArr){
  const pk=(pieza||'').trim().toLowerCase();
  const ck=(cliente||'').trim().toLowerCase();
  if(ck){
    const vs=[...ventasArr].filter(v=>(v.cliente||'').trim().toLowerCase()===ck&&v.estado!=='anulada')
      .sort((a,b)=>(b.created_at||b.fecha||'').localeCompare(a.created_at||a.fecha||''));
    for(const v of vs){
      const it=(v.venta_items||[]).find(i=>((i.productos_terminados?.pieza)||'').trim().toLowerCase()===pk);
      if(it&&parseFloat(it.precio_unitario)>0)return{precio:parseFloat(it.precio_unitario),origen:'cliente'};
    }
  }
  const pb=preciosArr.find(p=>(p.pieza||'').trim().toLowerCase()===pk);
  if(pb&&parseFloat(pb.precio_usd)>0)return{precio:parseFloat(pb.precio_usd),origen:'base'};
  const pt=[...ptsArr].sort((a,b)=>(b.created_at||'').localeCompare(a.created_at||'')).find(p=>((p.pieza||'').trim().toLowerCase())===pk);
  if(pt&&parseFloat(pt.precio_unitario)>0)return{precio:parseFloat(pt.precio_unitario),origen:'pt'};
  return{precio:0,origen:null};
}
```

- [ ] **Step 3: Wiring** — dos puntos (leer el código real de cada uno antes de editar):
  1. **Ítems de venta**: donde el select de PT de un ítem cambia (buscar el `onchange` del select de producto en `renderVentaItems`/`addVentaItem`), al elegir PT: si el precio del ítem está en 0, setearlo con `resolverPrecio(pt.pieza, g('v-cliente'), ventas, preciosBase, pts)` y mostrar hint según `origen` (`cliente`→"últ. a este cliente", `base`→"precio de lista", `pt`→"precio del stock").
  2. **Cotizador de presupuesto**: donde hoy se autocompleta `precio_unitario` desde el producto (~`índice 8740` según auditoría P1), anteponer el resolver con el cliente del header del presupuesto.

- [ ] **Step 4:** Validar (suite + nuevos PASS), commit: `feat(precios): autocompletado de precio en venta y presupuesto — último al cliente > lista > PT`

---

### Task 3: Facturación en lote (6C) + deploy del paquete

**Files:**
- Modify: `index.html` — toolbar de Ventas + función `facturarEntregadas()`.

**Interfaces:**
- Consumes: `emitirFactura(ventaId)` existente (leerla: si tiene `confirm` interno, extraer el núcleo a `_emitirFacturaCore(id)` sin confirm y que ambas lo usen).

- [ ] **Step 1:** Botón en la toolbar de Ventas: `<button class="btn btn-ghost" id="btn-fact-lote" onclick="facturarEntregadas()" style="border-color:var(--green);color:var(--green)">Facturar entregadas</button>` — `renderVentas` actualiza su texto con el count y lo oculta si es 0.
- [ ] **Step 2:**

```js
async function facturarEntregadas(){
  const pendientes=ventas.filter(v=>v.estado==='entregado'&&!v.factura_emitida_id);
  if(!pendientes.length){notify('No hay entregadas sin facturar');return;}
  if(!confirm(`¿Solicitar CAE para ${pendientes.length} venta${pendientes.length>1?'s':''} entregada${pendientes.length>1?'s':''}?`))return;
  setBusy('btn-fact-lote',true);
  let ok=0,err=0;
  for(const v of pendientes){
    try{await _emitirFacturaCore(v.id);ok++;}
    catch(e){err++;console.error('lote factura',v.nro_remito,e);}
    const b=document.getElementById('btn-fact-lote');if(b)b.textContent=`Facturando ${ok+err}/${pendientes.length}…`;
  }
  await reload('ventas','asientos','asiento_lineas');renderAll();
  setBusy('btn-fact-lote',false);
  notify(err?`${ok} facturadas · ${err} con error (ver consola)`:`✓ ${ok} facturadas`,err?'err':undefined);
}
```
(El refactor `_emitirFacturaCore`: mover el cuerpo de `emitirFactura` sin el confirm ni el reload a una función interna; `emitirFactura` la llama con confirm+reload como hoy. Leer la función real primero.)

- [ ] **Step 3:** Validar, commit, **esperar el "listo" de la migración 049**, push, verificación en prod (cierra P6): página Precios funciona, importar desde stock crea filas, elegir PT en una venta autocompleta con hint, facturar entregadas en lote muestra progreso.

## Self-review
- Cobertura: 6A→T1 (migración ya commiteada aparte), 6B→T2, 6C→T3. ✓
- Placeholders: los dos "leer el código real" de T2.3/T3.2 son lookups guiados en funciones nombradas. ✓
- Consistencia: `preciosBase/resolverPrecio/reload('precios_base')` coherentes. ✓
