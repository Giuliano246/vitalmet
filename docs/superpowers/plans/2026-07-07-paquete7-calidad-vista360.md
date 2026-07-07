# Paquete 7 — Calidad + Vista 360: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NC automática al rechazar recepción, alerta de revisión anual de documentos, y ficha de cliente enriquecida (cta cte, presupuestos, rentabilidad, último precio).

**Architecture:** Todo en `index.html`, sin migraciones. La NC auto usa el mismo POST del alta manual (`numero` lo asigna la DB). La ficha (`openFichaCliente`) suma secciones al HTML que ya construye. Rentabilidad en función pura con `costoFn` inyectable (testeable sin DOM).

**Tech Stack:** vanilla JS, tests harness vm, deploy Netlify. **Spec:** `docs/superpowers/specs/2026-07-07-paquete7-calidad-vista360-design.md`

## Global Constraints
- Reglas CLAUDE.md (validación: snippet + `node --check` + `node --test tests/*.test.js`; `esc()`; voseo). Un deploy al cierre del paquete.
- Confirmado: `saveNC` POSTea SIN `numero` (lo asigna la DB) con campos `fecha, origen_tipo, orden_id, recepcion_id, venta_id, registro_calidad_id, descripcion, disposicion, justificacion, cliente_notificado, empresa_id`.

---

### Task 1: Auto-draft de NCR al rechazar recepción (7A)

**Files:** Modify `index.html` — `rechazarRecepcion(id)`.

- [ ] **Step 1:** Reescribir el cuerpo:

```js
async function rechazarRecepcion(id){
  const r=recepciones.find(x=>x.id===id);if(!r)return;
  if(!confirm('¿Rechazar esta recepción? La barra vinculada queda bloqueada y se crea la No Conformidad automáticamente.'))return;
  try{
    await PATCH('recepciones_oc',{estado_inspeccion:'rechazado'},`?id=eq.${id}`);
    // NC automática pre-cargada (numero lo asigna la DB, como en el alta manual)
    let ncMsg='';
    try{
      const oc=ordenesCompra.find(o=>o.id===r.oc_id);
      const desc=`Rechazo de recepción ${r.fecha||hoyLocal()}${oc?` — OC ${oc.nro||''} · ${oc.proveedores?.nombre||''}`:''}${r.remito_nro?` · remito ${r.remito_nro}`:''}. Detectado en inspección de entrada.`;
      await POST('no_conformidades',{empresa_id:currentEmpresa.id,fecha:hoyLocal(),origen_tipo:'recepcion',recepcion_id:id,descripcion:desc});
      ncMsg=' — NC creada automáticamente en Calidad → NCR (completá la disposición)';
    }catch(eNC){console.error('NC automática:',eNC);ncMsg=' — ⚠ la NC automática falló, registrala a mano en Calidad';}
    await reload('recepciones_oc','ordenes_compra','oc_items','barras','no_conformidades');renderAll();
    notify('Recepción rechazada'+ncMsg,ncMsg.includes('⚠')?'err':undefined);
  }catch(e){notify('Error: '+e.message,'err');}
}
```
(Verificar contra la recepción real los nombres `r.oc_id`/`r.remito_nro` — grep en `saveRecepcion`/`renderInspeccion`; usar los reales.)

- [ ] **Step 2:** Validar + commit: `feat(calidad): NC automática pre-cargada al rechazar una recepción`

---

### Task 2: Docs controlados en digest (7B)

**Files:** Modify `index.html` — `computeAlertas()` (antes del `return out;`, después del bloque de emails).

- [ ] **Step 1:**

```js
  // Documentos controlados: revisión anual pendiente (ISO 9001)
  const hace365=hoyLocal(-365);
  const docsRev=documentosControlados.filter(d=>d.estado==='vigente'&&d.fecha_vigencia&&d.fecha_vigencia<hace365);
  if(docsRev.length)out.push({sev:'warn',page:'doccontrol',count:docsRev.length,
    titulo:uno(docsRev.length,'Documento con revisión anual pendiente','Documentos con revisión anual pendiente'),
    detalle:docsRev.slice(0,3).map(d=>esc((d.codigo||'')+' rev.'+(d.revision||'')+' (vigente desde '+d.fecha_vigencia+')')).join('  —  ')+masDe(docsRev)});
```

- [ ] **Step 2:** Validar + commit: `feat(digest): alerta de revisión anual pendiente en documentos controlados`

---

### Task 3: Vista 360 del cliente (7C) + deploy final

**Files:** Modify `index.html` — función pura + `openFichaCliente`; Create `tests/cliente360.test.js`.

**Interfaces:** Produces `computeRentabilidadCliente(ventasCliente, costoPorPieza) → {facturado, costoEstimado, margenPct}` — `costoPorPieza` es un mapa `{pieza(lower): costoUnit}` (inyectable en tests; en producción se arma con `computeCostoPT` sobre `pts`).

- [ ] **Step 1: Test que falla** (`tests/cliente360.test.js`, boilerplate harness):

```js
test('computeRentabilidadCliente calcula margen con costo por pieza', () => {
  const r = erp.run(`(()=>{
    const ventasC=[
      {estado:'facturado',venta_items:[{cantidad:2,precio_unitario:100,pieza:'Anillo BX'},{cantidad:1,precio_unitario:50,pieza:'Codo'}]},
      {estado:'anulada',venta_items:[{cantidad:9,precio_unitario:999,pieza:'Anillo BX'}]},
    ];
    return computeRentabilidadCliente(ventasC,{'anillo bx':60,'codo':30});
  })()`);
  assert.strictEqual(r.facturado, 250);
  assert.strictEqual(r.costoEstimado, 150); // 2×60 + 1×30
  assert.strictEqual(r.margenPct, 40);      // (250-150)/250
});
test('computeRentabilidadCliente sin costos devuelve margen null', () => {
  const r = erp.run(`computeRentabilidadCliente([{estado:'facturado',venta_items:[{cantidad:1,precio_unitario:10,pieza:'X'}]}],{})`);
  assert.strictEqual(r.margenPct, null);
});
```

- [ ] **Step 2: Implementar** (junto a `resolverPrecio`):

```js
function computeRentabilidadCliente(ventasC,costoPorPieza){
  let facturado=0,costoEstimado=0,conCosto=0,total=0;
  ventasC.filter(v=>v.estado!=='anulada').forEach(v=>(v.venta_items||[]).forEach(i=>{
    const sub=(parseFloat(i.cantidad)||0)*(parseFloat(i.precio_unitario)||0);
    facturado+=sub;total++;
    const c=costoPorPieza[((i.pieza||i.productos_terminados?.pieza||'')+'').trim().toLowerCase()];
    if(c!=null){costoEstimado+=(parseFloat(i.cantidad)||0)*c;conCosto++;}
  }));
  const margenPct=(conCosto&&conCosto===total&&facturado>0)?Math.round((facturado-costoEstimado)/facturado*100):null;
  return{facturado,costoEstimado,margenPct};
}
```

- [ ] **Step 3: Enriquecer openFichaCliente** — después del cálculo de `topPiezas` existente, agregar y concatenar al `html`:

```js
  // 360: cta cte, presupuestos abiertos, rentabilidad, último precio
  const cta=computeCtaCte().find(x=>x.cliente&&x.cliente.id===c.id);
  const vencido=cta?cta.buckets.d30+cta.buckets.d60+cta.buckets.d90+cta.buckets.mas90:0;
  const presupAbiertos=presupuestos.filter(p=>['enviado','aprobado'].includes(p.estado)&&(p.cliente||'').toLowerCase()===(c.nombre||'').toLowerCase());
  const costoPorPieza={};
  pts.forEach(p=>{const k=(p.pieza||'').trim().toLowerCase();if(k&&costoPorPieza[k]==null){const cc=computeCostoPT(p);costoPorPieza[k]=cc.total||null;if(costoPorPieza[k]==null)delete costoPorPieza[k];}});
  const rent=computeRentabilidadCliente(ventasC,costoPorPieza);
  html+=`<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:16px">
    <div class="dash-card"><div class="section-label">Cta. corriente</div>
      <div style="font-size:18px;font-weight:700;font-family:var(--mono);color:${cta&&cta.saldo>0.005?(vencido>0.005?'var(--coral)':'var(--accent)'):'var(--green)'};margin-top:6px">${cta?fmtUSD(Math.max(0,cta.saldo)):'US$ 0'}</div>
      <div style="font-size:11px;color:${vencido>0.005?'var(--coral)':'var(--text3)'}">${vencido>0.005?fmtUSD(vencido)+' vencido':'sin deuda vencida'}</div>
      <button class="btn btn-ghost btn-sm" style="margin-top:8px" onclick="closeModal('modal-ficha-cliente');showPage('ctacte')">Ver cta. corriente</button></div>
    <div class="dash-card"><div class="section-label">Rentabilidad histórica</div>
      <div style="font-size:18px;font-weight:700;font-family:var(--mono);color:${rent.margenPct==null?'var(--text3)':rent.margenPct>=30?'var(--green)':rent.margenPct>=15?'var(--accent)':'var(--coral)'};margin-top:6px">${rent.margenPct!=null?rent.margenPct+'%':'—'}</div>
      <div style="font-size:11px;color:var(--text3)">margen sobre ${fmtUSD(rent.facturado)} facturado <span title="Costo estimado con el costeo actual de cada pieza">*al costo de hoy</span></div></div>
  </div>
  ${presupAbiertos.length?`<div class="section-label">Presupuestos abiertos (${presupAbiertos.length})</div>
  <div style="display:flex;flex-direction:column;gap:4px;margin:8px 0 16px">${presupAbiertos.map(p=>{
    const dias=p.fecha?Math.floor((Date.now()-new Date(p.fecha+'T00:00:00'))/86400000):0;
    return `<div onclick="closeModal('modal-ficha-cliente');showPage('presupuestos','${p.id}')" style="display:flex;justify-content:space-between;padding:6px 10px;background:var(--surface2);border-radius:4px;cursor:pointer;font-size:12px"><span>${esc(p.nro||'')} · ${fmtUSD(parseFloat(p.total||0))} <span class="badge badge-${p.estado==='aprobado'?'ok':'blue'}" style="font-size:9px">${p.estado}</span></span><span class="mono" style="color:${dias>=7?'var(--coral)':'var(--text3)'}">${dias}d</span></div>`;}).join('')}</div>`:''}`;
```
Y en el ranking `topPiezas` existente, agregar por pieza el último precio: donde se renderiza cada entrada del ranking, sumar `· últ. ${fmtUSD(resolverPrecio(pieza,c.nombre,ventas,preciosBase,pts).precio)}` (leer el bloque real del ranking y adaptarlo).

- [ ] **Step 4:** Validar (suite completa PASS), commit, **push (deploy final del roadmap)**, verificación en prod: rechazar recepción de prueba → NC creada; digest con docs vencidos si existen; ficha de cliente real muestra saldo/margen/presupuestos con deep-links.

```bash
git add index.html tests/cliente360.test.js
git commit -m "feat(clientes): vista 360 — cta cte, rentabilidad, presupuestos abiertos y último precio en la ficha"
git push origin main
```

## Self-review
- Cobertura: 7A→T1, 7B→T2, 7C→T3. ✓ Placeholders: lookups guiados (campos de recepción en T1, bloque de ranking en T3). ✓ Consistencia: `computeRentabilidadCliente` firma idéntica test/impl; deep-links usan `showPage(page,id)` de P2. ✓
