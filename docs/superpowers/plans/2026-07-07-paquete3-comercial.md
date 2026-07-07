# Paquete 3 — Comercial: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cobros/pagos con tercero por selección, 5 alertas nuevas en el digest, módulo Mailings con cola de aprobación, generación automática diaria de recordatorios, worker de envío vía Microsoft Graph en el billing service, y métricas de pipeline.

**Architecture:** UI y generador en `~/vitalmet-erp/index.html` (single-file, vanilla JS; datos de mailings on-demand fuera de `loadAll`). Worker de envío en `~/vitalmet-billing/main.py` (FastAPI en Railway, task asyncio cada 5 min, Graph client-credentials, acceso a Supabase con service key). La cola `email_queue` (migración 004, ya en prod) es el contrato entre ambos.

**Tech Stack:** vanilla JS + Supabase PostgREST · FastAPI + httpx · tests `node --test` + harness vm · deploys: Netlify (push a main del ERP) y Railway (push al repo billing).

**Spec:** `docs/superpowers/specs/2026-07-07-paquete3-comercial-design.md`

## Global Constraints

- Reglas CLAUDE.md del ERP: un cambio a la vez, `esc()` en toda interpolación, `empresa_id:currentEmpresa.id` en todo POST, validar con el snippet python + `node --check` + `node --test tests/*.test.js` antes de commitear, voseo.
- Anclas confirmadas: input tercero `#cp-tercero` (HTML línea ~975, label `#cp-tercero-label`, datalist `#cp-tercero-list`; lectura en `saveCobroPago` vía `document.getElementById('cp-tercero').value.trim()` ~5330; el modo cobro/pago setea el label en ~5272). `computeAlertas()` empuja objetos `{sev,page,count,titulo,detalle}` a `out` y devuelve `out`. Estados de OC: `borrador,enviada,confirmada,recibida_parcial,recibida,facturada,anulada`. Billing: `lifespan` en `main.py:381`, `app=FastAPI(...,lifespan=lifespan)` en ~395.
- Verificación previa (Task 3, paso 0): confirmar en prod que `email_templates`/`email_queue`/`email_log` existen y tienen seeds (`GET email_templates?select=id,nombre,tipo`). Si la 004 no corrió, frenar y pedírsela a Giuliano.
- El worker de billing queda detrás de `MAILER_ENABLED` (default false) hasta que Giuliano cargue las credenciales de Azure en Railway.

Comando de validación del ERP (idéntico al CI):

```bash
cd ~/vitalmet-erp && python3 -c "
import re
html = open('index.html').read()
scripts = re.findall(r'<script>(.*?)</script>', html, re.S)
open('/tmp/erp_script.js','w').write(max(scripts, key=len))
" && node --check /tmp/erp_script.js && node --test tests/*.test.js
```

---

### Task 1: Cobros/pagos — tercero por selección (3D)

**Files:**
- Modify: `~/vitalmet-erp/index.html` — HTML del form de cobro/pago (~975), función que setea el modo (~5272), `saveCobroPago` (~5330).

**Interfaces:**
- Consumes: globals `clientes` (campo `nombre`), `proveedores` (campo `nombre`); función de modo cobro/pago existente.
- Produces: `populateCpTerceroSelect(modo)`; el valor del tercero se sigue leyendo como string (nombre exacto) — nada aguas abajo cambia.

- [ ] **Step 1: Reemplazar el input por select + input "Otro"**

En el HTML (~975), reemplazar el `<input type="text" id="cp-tercero" ...>` y su `<datalist>` por:

```html
<select id="cp-tercero-sel" onchange="document.getElementById('cp-tercero-otro').style.display=this.value==='__otro__'?'':'none'"></select>
<input type="text" id="cp-tercero-otro" placeholder="Razón social..." style="display:none;margin-top:6px">
```

- [ ] **Step 2: Poblar el select según el modo**

Donde se setea `cp-tercero-label` según el modo (~5272), reemplazar la lógica del datalist (~5277) por:

```js
function populateCpTerceroSelect(modo){
  const sel=document.getElementById('cp-tercero-sel');
  const src=modo==='cobro'?clientes:proveedores;
  sel.innerHTML='<option value="">— Seleccioná —</option>'
    +[...src].sort((a,b)=>(a.nombre||'').localeCompare(b.nombre||'','es')).map(x=>`<option value="${esc(x.nombre)}">${esc(x.nombre)}</option>`).join('')
    +'<option value="__otro__">Otro…</option>';
  document.getElementById('cp-tercero-otro').style.display='none';
}
```
y llamarla desde el switch de modo. Verificar con grep si el datalist se poblaba en otra función y borrar esa lógica.

- [ ] **Step 3: Lectura en saveCobroPago**

Reemplazar `const tercero=document.getElementById('cp-tercero').value.trim();` por:

```js
const selT=document.getElementById('cp-tercero-sel').value;
const tercero=(selT==='__otro__'?document.getElementById('cp-tercero-otro').value:selT).trim();
```

Verificar con `grep -n "cp-tercero" index.html` que no queden referencias al input viejo.

- [ ] **Step 4: Validar (comando global), commit**

```bash
git add index.html && git commit -m "fix(contab): tercero de cobros/pagos por selección — elimina pagos huérfanos por typo"
```

---

### Task 2: Alertas nuevas en computeAlertas (3C)

**Files:**
- Modify: `~/vitalmet-erp/index.html` — `computeAlertas()` (agregar detectores antes del `return`).

**Interfaces:**
- Consumes: globals `ordenesCompra` (`fecha_entrega_esperada`, `factura_vto`, `estado`), `ventas` (`estado`, `factura_emitida_id`, `fecha`), `presupuestos` (`estado`, `fecha`), `ops` (`presupuesto_id`), y `mailingsQueueCount` (global numérico, definido en Task 3 con default `null`).
- Produces: 5 alertas nuevas con el shape existente `{sev,page,count,titulo,detalle}`.

- [ ] **Step 1: Agregar los detectores** (antes del `return` de `computeAlertas`, siguiendo el patrón de los existentes — mirar 2-3 de los que ya están para copiar el formato exacto de `titulo`/`detalle` con `uno()` y `masDe()`):

```js
  // OCs demoradas (entrega esperada vencida sin recibir)
  const ocDemoradas=ordenesCompra.filter(o=>['enviada','confirmada','recibida_parcial'].includes(o.estado)&&o.fecha_entrega_esperada&&o.fecha_entrega_esperada<hoy);
  if(ocDemoradas.length)out.push({sev:'crit',page:'compras',count:ocDemoradas.length,
    titulo:`${ocDemoradas.length} OC${uno(ocDemoradas.length,'','s')} con entrega vencida`,
    detalle:ocDemoradas.slice(0,3).map(o=>`${o.nro} (esperada ${o.fecha_entrega_esperada})`).join(' · ')+masDe(ocDemoradas)});

  // Facturas de proveedor por vencer / vencidas
  const en7d_f=hoyLocal(7);
  const factVencidas=ordenesCompra.filter(o=>o.factura_vto&&o.estado!=='anulada'&&o.factura_vto<hoy);
  const factPorVencer=ordenesCompra.filter(o=>o.factura_vto&&o.estado!=='anulada'&&o.factura_vto>=hoy&&o.factura_vto<=en7d_f);
  if(factVencidas.length)out.push({sev:'crit',page:'compras',count:factVencidas.length,
    titulo:`${factVencidas.length} factura${uno(factVencidas.length,'','s')} de proveedor vencida${uno(factVencidas.length,'','s')}`,
    detalle:factVencidas.slice(0,3).map(o=>`${o.nro} (vto ${o.factura_vto})`).join(' · ')+masDe(factVencidas)});
  if(factPorVencer.length)out.push({sev:'warn',page:'compras',count:factPorVencer.length,
    titulo:`${factPorVencer.length} factura${uno(factPorVencer.length,'','s')} de proveedor vence${uno(factPorVencer.length,'','n')} en 7 días`,
    detalle:factPorVencer.slice(0,3).map(o=>`${o.nro} (vto ${o.factura_vto})`).join(' · ')+masDe(factPorVencer)});

  // Ventas entregadas sin facturar (3+ días)
  const hace3d=hoyLocal(-3);
  const sinFacturar=ventas.filter(v=>v.estado==='entregado'&&!v.factura_emitida_id&&v.fecha&&v.fecha<=hace3d);
  if(sinFacturar.length)out.push({sev:'warn',page:'ventas',count:sinFacturar.length,
    titulo:`${sinFacturar.length} venta${uno(sinFacturar.length,'','s')} entregada${uno(sinFacturar.length,'','s')} sin facturar`,
    detalle:sinFacturar.slice(0,3).map(v=>`${v.nro_remito} · ${v.cliente}`).join(' · ')+masDe(sinFacturar)});

  // Presupuestos aprobados sin convertir ni OP (5+ días)
  const hace5d=hoyLocal(-5);
  const aprobFrios=presupuestos.filter(p=>p.estado==='aprobado'&&p.fecha&&p.fecha<=hace5d&&!ops.some(o=>o.presupuesto_id===p.id));
  if(aprobFrios.length)out.push({sev:'warn',page:'presupuestos',count:aprobFrios.length,
    titulo:`${aprobFrios.length} presupuesto${uno(aprobFrios.length,'','s')} aprobado${uno(aprobFrios.length,'','s')} sin arrancar`,
    detalle:aprobFrios.slice(0,3).map(p=>`${p.nro} · ${p.cliente}`).join(' · ')+masDe(aprobFrios)});

  // Emails esperando aprobación (si el módulo mailings cargó el dato)
  if(typeof mailingsQueueCount==='number'&&mailingsQueueCount>0)out.push({sev:'warn',page:'mailings',count:mailingsQueueCount,
    titulo:`${mailingsQueueCount} email${uno(mailingsQueueCount,'','s')} esperando tu aprobación`,
    detalle:'Revisalos en Ventas → Mailings'});
```

Nota: verificar que `hoyLocal()` acepte offset negativo (`hoyLocal(-3)`); si no, calcular con `new Date(Date.now()-3*86400000).toISOString().slice(0,10)`.

- [ ] **Step 2: Definir el stub del global** (se completa en Task 3): junto a los globals de datos, agregar `let mailingsQueueCount=null;`

- [ ] **Step 3: Validar, commit, push (deploy bloque 3D+3C), verificar digest en prod**

```bash
git add index.html && git commit -m "feat(digest): alertas de OCs demoradas, facturas proveedor, entregadas sin facturar y aprobados sin arrancar"
git push origin main
```

---

### Task 3: Módulo Mailings — UI (3A)

**Files:**
- Modify: `~/vitalmet-erp/index.html` — registro de página (`PAGE_TO_GROUP` + `GROUP_TABS.ventas` + `groupMods.ventas` + `PAGE_RENDERS`), HTML `#page-mailings` (después de `#page-ctacte`), modal preview/edición, JS de datos + renders + acciones.

**Interfaces:**
- Consumes: `GET/POST/PATCH`, `esc()`, `openModal/closeModal`, patrón on-demand de `ensureEficienciaData`.
- Produces: globals `emailQueue=[]`, `emailTemplates=[]`, `emailLog=[]`, `mailingsQueueCount` (número tras cargar); `ensureMailingsData(force)`; `renderMailings()`; `aprobarEmail(id)`, `cancelarEmail(id)`, `aprobarTodos()`, `openEmailPreview(id)`, `openEmailEdit(id)`, `saveEmailEdit()`, `openTemplateEdit(id)`, `saveTemplate()`. Usados por Task 4.

- [ ] **Step 0: Verificar la migración 004 en prod**

Desde la consola del navegador logueado en el ERP (o pedirle a Giuliano que corra en SQL Editor): `SELECT count(*) FROM email_templates;`. Alternativa por código: `GET('email_templates','?select=id,nombre,tipo')` en consola. Si la tabla no existe → STOP, pasarle la migración 004 y esperar.

- [ ] **Step 1: Registro de página**

`PAGE_TO_GROUP`: `mailings:'ventas'`. `GROUP_TABS.ventas`: agregar `{k:'mailings',l:'Mailings'}` al final. `groupMods.ventas`: agregar `'mailings'`. `PAGE_RENDERS`: `mailings:[renderMailings]`.

- [ ] **Step 2: HTML de la página** (después del cierre de `#page-ctacte`)

```html
<!-- MAILINGS -->
<div class="page" id="page-mailings">
  <div class="page-header"><div class="page-title">Mailings</div><div class="page-sub">// recordatorios con tu aprobación — nada sale solo</div><div class="tabs"></div></div>
  <div class="page-content">
    <div class="stats-bar" id="mail-stats"></div>
    <div class="toolbar">
      <div style="display:flex;gap:6px">
        <button class="btn btn-ghost" id="mail-tab-cola" onclick="switchMailTab('cola')" style="border-color:var(--accent);color:var(--accent)">Cola de aprobación</button>
        <button class="btn btn-ghost" id="mail-tab-templates" onclick="switchMailTab('templates')">Templates</button>
        <button class="btn btn-ghost" id="mail-tab-log" onclick="switchMailTab('log')">Historial</button>
      </div>
      <button class="btn" id="mail-aprobar-todos" onclick="aprobarTodos()" style="background:var(--green);color:white">✓ Aprobar todos</button>
    </div>
    <div id="mail-vista-cola" class="table-wrap"><table><thead><tr><th>Para</th><th>Asunto</th><th>Origen</th><th>Creado</th><th>Estado</th><th></th></tr></thead><tbody id="mail-cola-tbody"></tbody></table></div>
    <div id="mail-vista-templates" class="table-wrap" style="display:none"><table><thead><tr><th>Nombre</th><th>Tipo</th><th>Asunto</th><th>Activo</th><th></th></tr></thead><tbody id="mail-templates-tbody"></tbody></table></div>
    <div id="mail-vista-log" class="table-wrap" style="display:none"><table><thead><tr><th>Fecha</th><th>Para</th><th>Asunto</th></tr></thead><tbody id="mail-log-tbody"></tbody></table></div>
  </div>
</div>
```

Modal (junto a los otros modales):

```html
<!-- MODAL: preview/editar email -->
<div class="modal-overlay" id="modal-email">
  <div class="modal modal-lg">
    <div class="modal-header"><div class="modal-title" id="email-modal-title">Email</div><button class="modal-close" onclick="closeModal('modal-email')">×</button></div>
    <div class="modal-body">
      <div class="form-row"><div class="form-group"><label>Para</label><input type="email" id="em-to"></div><div class="form-group"><label>Asunto</label><input type="text" id="em-subject"></div></div>
      <div class="form-row single"><div class="form-group"><label>Cuerpo (HTML)</label><textarea id="em-body" rows="10" style="width:100%;font-family:var(--mono);font-size:11px"></textarea></div></div>
      <div class="section-label">Vista previa</div>
      <div id="em-preview" style="border:1px solid var(--border);border-radius:6px;padding:14px;background:white;color:#222;max-height:240px;overflow-y:auto"></div>
    </div>
    <div class="modal-footer">
      <button class="btn btn-ghost" onclick="closeModal('modal-email')">Cerrar</button>
      <button class="btn" id="btn-email-save" onclick="saveEmailEdit()" style="background:var(--accent);color:white">Guardar cambios</button>
      <button class="btn" id="btn-email-approve" style="background:var(--green);color:white">✓ Aprobar y programar</button>
    </div>
  </div>
</div>
<!-- MODAL: template -->
<div class="modal-overlay" id="modal-template">
  <div class="modal modal-lg">
    <div class="modal-header"><div class="modal-title">Template</div><button class="modal-close" onclick="closeModal('modal-template')">×</button></div>
    <div class="modal-body">
      <div class="form-row"><div class="form-group"><label>Nombre *</label><input type="text" id="tpl-nombre"></div><div class="form-group"><label>Tipo</label><select id="tpl-tipo"><option value="cobranza">Cobranza</option><option value="seguimiento_presupuesto">Seguimiento presupuesto</option><option value="individual">Individual</option></select></div></div>
      <div class="form-row single"><div class="form-group"><label>Asunto *</label><input type="text" id="tpl-subject"></div></div>
      <div class="form-row single"><div class="form-group"><label>Cuerpo HTML * <span style="color:var(--text3);font-size:10px">placeholders: {cliente} {monto} {dias} {nro} {detalle}</span></label><textarea id="tpl-body" rows="10" style="width:100%;font-family:var(--mono);font-size:11px"></textarea></div></div>
      <div class="form-row single"><div class="form-group"><label><input type="checkbox" id="tpl-activo" checked> Activo</label></div></div>
    </div>
    <div class="modal-footer"><button class="btn btn-ghost" onclick="closeModal('modal-template')">Cancelar</button><button class="btn" id="btn-save-tpl" onclick="saveTemplate()" style="background:var(--accent);color:white">Guardar</button></div>
  </div>
</div>
```

(Ajustar clases del footer al patrón real de otros modales — grep `modal-footer` y copiar.)

- [ ] **Step 3: JS de datos y renders**

```js
// ═══ MAILINGS — cola de aprobación, templates, historial ═══
let emailQueue=[],emailTemplates=[],emailLog=[],mailingsLoaded=false,_mailTab='cola',_emailEditId=null,_tplEditId=null;
async function ensureMailingsData(force){
  if(mailingsLoaded&&!force)return;
  [emailQueue,emailTemplates,emailLog]=await Promise.all([
    GET('email_queue','?order=created_at.desc&estado=in.(pendiente_aprobacion,aprobado,fallido)').catch(()=>[]),
    GET('email_templates','?order=nombre.asc').catch(()=>[]),
    GET('email_log','?order=created_at.desc&limit=200').catch(()=>[])
  ]);
  mailingsLoaded=true;
  mailingsQueueCount=emailQueue.filter(e=>e.estado==='pendiente_aprobacion').length;
}
function switchMailTab(t){
  _mailTab=t;
  ['cola','templates','log'].forEach(k=>{
    document.getElementById('mail-vista-'+k).style.display=k===t?'':'none';
    const b=document.getElementById('mail-tab-'+k);
    b.style.borderColor=k===t?'var(--accent)':'';b.style.color=k===t?'var(--accent)':'';
  });
  document.getElementById('mail-aprobar-todos').style.display=t==='cola'?'':'none';
}
async function renderMailings(){
  await ensureMailingsData();
  const pend=emailQueue.filter(e=>e.estado==='pendiente_aprobacion');
  const aprob=emailQueue.filter(e=>e.estado==='aprobado');
  const fall=emailQueue.filter(e=>e.estado==='fallido');
  document.getElementById('mail-stats').innerHTML=[
    ['Esperando aprobación',pend.length,pend.length?'var(--accent)':'var(--text)'],
    ['Aprobados (por salir)',aprob.length,'var(--blue)'],
    ['Fallidos',fall.length,fall.length?'var(--red)':'var(--text)'],
    ['Enviados (histórico)',emailLog.length,'var(--green)']
  ].map(([l,v,c])=>`<div class="stat-card"><div class="stat-label">${l}</div><div class="stat-value" style="color:${c}">${v}</div></div>`).join('');
  const badge=e=>e.estado==='pendiente_aprobacion'?'<span class="badge badge-warn">PENDIENTE</span>':e.estado==='aprobado'?'<span class="badge badge-blue">APROBADO</span>':`<span class="badge badge-coral" title="${esc(e.error_texto||'')}">FALLIDO</span>`;
  document.getElementById('mail-cola-tbody').innerHTML=emailQueue.length?emailQueue.map(e=>`<tr data-id="${e.id}"><td>${esc(e.to_nombre||'')} <span class="mono" style="color:var(--text3);font-size:10px">${esc(e.to_email)}</span></td><td style="max-width:280px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(e.subject)}</td><td class="mono" style="font-size:10px;color:var(--text3)">${e.venta_id?'venta':e.cliente_id?'cliente':'—'}</td><td class="mono" style="font-size:11px">${(e.created_at||'').slice(0,10)}</td><td>${badge(e)}</td><td style="display:flex;gap:4px">${e.estado!=='aprobado'?`<button class="btn btn-ghost btn-sm" onclick="openEmailPreview('${e.id}')">Ver / Editar</button><button class="btn btn-sm" style="background:var(--green);color:white" onclick="aprobarEmail('${e.id}')">✓</button>`:''}<button class="btn btn-danger btn-sm" onclick="cancelarEmail('${e.id}')">✗</button></td></tr>`).join(''):'<tr><td colspan="6" style="text-align:center;color:var(--text3);padding:24px">Sin emails en cola. Los recordatorios se generan solos cada mañana al abrir el ERP.</td></tr>';
  document.getElementById('mail-templates-tbody').innerHTML=emailTemplates.length?emailTemplates.map(t=>`<tr><td style="font-weight:500">${esc(t.nombre)}</td><td><span class="badge badge-blue">${esc(t.tipo)}</span></td><td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(t.subject)}</td><td>${t.activo?'<span class="badge badge-ok">Sí</span>':'<span class="badge">No</span>'}</td><td><button class="btn btn-ghost btn-sm" onclick="openTemplateEdit('${t.id}')">Editar</button></td></tr>`).join(''):'<tr><td colspan="5" style="text-align:center;color:var(--text3);padding:24px">Sin templates</td></tr>';
  document.getElementById('mail-log-tbody').innerHTML=emailLog.length?emailLog.map(l=>`<tr><td class="mono" style="font-size:11px">${(l.created_at||'').slice(0,16).replace('T',' ')}</td><td>${esc(l.to_email)}</td><td>${esc(l.subject)}</td></tr>`).join(''):'<tr><td colspan="3" style="text-align:center;color:var(--text3);padding:24px">Sin envíos todavía</td></tr>';
}
```

- [ ] **Step 4: Acciones (aprobar/cancelar/editar/templates)**

```js
async function aprobarEmail(id){
  try{
    await PATCH('email_queue',{estado:'aprobado',aprobado_por:currentUser.id,aprobado_at:new Date().toISOString()},`?id=eq.${id}`);
    await ensureMailingsData(true);renderMailings();notify('✓ Aprobado — sale en el próximo ciclo de envío');
  }catch(e){notify('Error: '+e.message,'err');}
}
async function aprobarTodos(){
  const pend=emailQueue.filter(e=>e.estado==='pendiente_aprobacion');
  if(!pend.length){notify('No hay pendientes');return;}
  if(!confirm(`¿Aprobar los ${pend.length} emails pendientes?`))return;
  try{
    await PATCH('email_queue',{estado:'aprobado',aprobado_por:currentUser.id,aprobado_at:new Date().toISOString()},'?estado=eq.pendiente_aprobacion');
    await ensureMailingsData(true);renderMailings();notify(`✓ ${pend.length} aprobados`);
  }catch(e){notify('Error: '+e.message,'err');}
}
async function cancelarEmail(id){
  if(!confirm('¿Cancelar este email? No se va a enviar.'))return;
  try{await PATCH('email_queue',{estado:'cancelado'},`?id=eq.${id}`);await ensureMailingsData(true);renderMailings();notify('Cancelado');}
  catch(e){notify('Error: '+e.message,'err');}
}
function openEmailPreview(id){
  const e=emailQueue.find(x=>x.id===id);if(!e)return;
  _emailEditId=id;
  document.getElementById('email-modal-title').textContent='Email — '+(e.to_nombre||e.to_email);
  document.getElementById('em-to').value=e.to_email;
  document.getElementById('em-subject').value=e.subject;
  document.getElementById('em-body').value=e.body_html;
  document.getElementById('em-preview').innerHTML=e.body_html; // contenido generado por el sistema desde templates propios
  document.getElementById('em-body').oninput=ev=>{document.getElementById('em-preview').innerHTML=ev.target.value;};
  document.getElementById('btn-email-approve').onclick=async()=>{await saveEmailEdit(true);};
  openModal('modal-email');
}
async function saveEmailEdit(aprobar){
  const id=_emailEditId;if(!id)return;
  try{
    const patch={to_email:document.getElementById('em-to').value.trim(),subject:document.getElementById('em-subject').value.trim(),body_html:document.getElementById('em-body').value};
    if(aprobar===true){patch.estado='aprobado';patch.aprobado_por=currentUser.id;patch.aprobado_at=new Date().toISOString();}
    await PATCH('email_queue',patch,`?id=eq.${id}`);
    closeModal('modal-email');await ensureMailingsData(true);renderMailings();
    notify(aprobar===true?'✓ Aprobado y programado':'Cambios guardados');
  }catch(e){notify('Error: '+e.message,'err');}
}
function openTemplateEdit(id){
  const t=id?emailTemplates.find(x=>x.id===id):null;
  _tplEditId=id||null;
  document.getElementById('tpl-nombre').value=t?.nombre||'';
  document.getElementById('tpl-tipo').value=t?.tipo||'cobranza';
  document.getElementById('tpl-subject').value=t?.subject||'';
  document.getElementById('tpl-body').value=t?.body_html||'';
  document.getElementById('tpl-activo').checked=t?t.activo!==false:true;
  openModal('modal-template');
}
async function saveTemplate(){
  const nombre=document.getElementById('tpl-nombre').value.trim();
  const subject=document.getElementById('tpl-subject').value.trim();
  const body=document.getElementById('tpl-body').value;
  if(!nombre||!subject||!body)return notify('Completá nombre, asunto y cuerpo','err');
  try{setBusy('btn-save-tpl',true);
    const data={nombre,tipo:document.getElementById('tpl-tipo').value,subject,body_html:body,activo:document.getElementById('tpl-activo').checked};
    if(_tplEditId)await PATCH('email_templates',data,`?id=eq.${_tplEditId}`);
    else await POST('email_templates',{empresa_id:currentEmpresa.id,...data});
    closeModal('modal-template');await ensureMailingsData(true);renderMailings();notify('Template guardado');
  }catch(e){notify('Error: '+e.message,'err');}
  finally{setBusy('btn-save-tpl',false);}
}
```

Nota `em-preview`: el body proviene de templates propios del sistema (no input de terceros); el textarea permite editarlo a mano igual que un cliente de correo.

- [ ] **Step 5: Validar (comando global), commit**

```bash
git add index.html && git commit -m "feat(comercial): módulo Mailings — cola de aprobación, templates e historial"
```

---

### Task 4: Generación automática diaria de recordatorios (3B frontend)

**Files:**
- Modify: `~/vitalmet-erp/index.html` — `generarRecordatoriosAuto()` + hook post-login, seeds de templates, resolución de placeholders.

**Interfaces:**
- Consumes: `computeCtaCte()` (saldos vencidos por cliente — leer su firma real antes: grep `function computeCtaCte`), `presupuestos`, `clientes` (`nombre`,`email`), `ensureMailingsData`, `emailTemplates`, `POST`.
- Produces: `generarRecordatoriosAuto()`; `resolverTemplate(tpl, vars) → {subject, body}` (pura, testeable); templates seed tipo `cobranza` y `seguimiento_presupuesto` si no existen.

- [ ] **Step 1: Test de resolverTemplate** (agregar a `tests/palette.test.js` o archivo nuevo `tests/mailings.test.js`)

```js
test('resolverTemplate reemplaza todos los placeholders', () => {
  const r = erp.run(`(()=>{
    const tpl={subject:'Recordatorio: saldo de {cliente}',body_html:'<p>Hola {cliente}, saldo {monto} hace {dias} días.</p>'};
    return resolverTemplate(tpl,{cliente:'ACME SA',monto:'US$ 1.200',dias:'12'});
  })()`);
  assert.strictEqual(r.subject, 'Recordatorio: saldo de ACME SA');
  assert.strictEqual(r.body, '<p>Hola ACME SA, saldo US$ 1.200 hace 12 días.</p>');
});
```

- [ ] **Step 2: Implementar resolverTemplate (pura) + generador**

```js
function resolverTemplate(tpl,vars){
  const rep=s=>Object.entries(vars).reduce((a,[k,v])=>a.split('{'+k+'}').join(v),s||'');
  return {subject:rep(tpl.subject),body:rep(tpl.body_html)};
}

const SEED_TEMPLATES=[
 {tipo:'cobranza',nombre:'Recordatorio de cobranza',subject:'Vitalmet SA — Recordatorio de saldo pendiente',
  body_html:'<p>Estimado/a {cliente}:</p><p>Le recordamos que registra un saldo pendiente de <b>{monto}</b> con {dias} días de atraso.</p><p>{detalle}</p><p>Ante cualquier consulta o si el pago ya fue realizado, por favor responda este correo.</p><p>Saludos cordiales,<br>Vitalmet SA — Administración</p>'},
 {tipo:'seguimiento_presupuesto',nombre:'Seguimiento de presupuesto',subject:'Vitalmet SA — Seguimiento presupuesto {nro}',
  body_html:'<p>Estimado/a {cliente}:</p><p>Le escribimos para hacer seguimiento del presupuesto <b>{nro}</b> enviado hace {dias} días.</p><p>Quedamos a disposición por cualquier consulta técnica o comercial.</p><p>Saludos cordiales,<br>Vitalmet SA — Ventas</p>'}
];

async function generarRecordatoriosAuto(){
  const hoy=hoyLocal();
  if(localStorage.getItem('lastMailGen')===hoy)return;
  try{
    await ensureMailingsData();
    // seeds si faltan
    for(const s of SEED_TEMPLATES){
      if(!emailTemplates.some(t=>t.tipo===s.tipo)){
        await POST('email_templates',{empresa_id:currentEmpresa.id,...s,activo:true}).catch(()=>{});
      }
    }
    if(SEED_TEMPLATES.some(s=>!emailTemplates.some(t=>t.tipo===s.tipo)))await ensureMailingsData(true);
    const tplCob=emailTemplates.find(t=>t.tipo==='cobranza'&&t.activo!==false);
    const tplSeg=emailTemplates.find(t=>t.tipo==='seguimiento_presupuesto'&&t.activo!==false);
    const nuevos=[];const sinEmail=[];
    const yaEncolado=(clienteId,marca)=>emailQueue.some(e=>
      (clienteId&&e.cliente_id===clienteId||marca&&(e.subject||'').includes(marca))&&
      (['pendiente_aprobacion','aprobado'].includes(e.estado)||(e.estado==='enviado'&&e.enviado_at&&e.enviado_at>new Date(Date.now()-7*86400000).toISOString())));
    // 1) Cobranzas vencidas — adaptar a la estructura real de computeCtaCte (leerla antes)
    if(tplCob){
      const cta=computeCtaCte();
      // esperado: por cliente, saldo vencido y días de atraso; ajustar nombres de campos a los reales
      (cta.clientesVencidos||[]).forEach(cv=>{
        const cli=clientes.find(c=>(c.nombre||'').toLowerCase()===(cv.cliente||'').toLowerCase());
        if(!cli)return;
        if(!cli.email){sinEmail.push(cv.cliente);return;}
        if(yaEncolado(cli.id,null))return;
        const {subject,body}=resolverTemplate(tplCob,{cliente:cli.nombre,monto:fmtUSD(cv.saldoVencido),dias:String(cv.diasAtraso),detalle:cv.detalle||''});
        nuevos.push({empresa_id:currentEmpresa.id,cliente_id:cli.id,template_id:tplCob.id,to_email:cli.email,to_nombre:cli.nombre,subject,body_html:body,scheduled_at:new Date().toISOString(),created_by:currentUser.id});
      });
    }
    // 2) Presupuestos enviados 7+ días sin respuesta
    if(tplSeg){
      const hace7=new Date(Date.now()-7*86400000).toISOString().slice(0,10);
      presupuestos.filter(p=>p.estado==='enviado'&&p.fecha&&p.fecha<=hace7).forEach(p=>{
        const cli=clientes.find(c=>(c.nombre||'').toLowerCase()===(p.cliente||'').toLowerCase());
        if(!cli||!cli.email){if(!cli||!cli.email)sinEmail.push(p.cliente);return;}
        if(yaEncolado(null,p.nro))return;
        const dias=Math.floor((Date.now()-new Date(p.fecha+'T00:00:00'))/86400000);
        const {subject,body}=resolverTemplate(tplSeg,{cliente:cli.nombre,nro:p.nro,dias:String(dias)});
        nuevos.push({empresa_id:currentEmpresa.id,cliente_id:cli.id,template_id:tplSeg.id,to_email:cli.email,to_nombre:cli.nombre,subject,body_html:body,scheduled_at:new Date().toISOString(),created_by:currentUser.id});
      });
    }
    if(nuevos.length){
      await POST('email_queue',nuevos);
      await ensureMailingsData(true);
      notify(`✉ ${nuevos.length} recordatorio${nuevos.length>1?'s':''} generado${nuevos.length>1?'s':''} — revisalos en Ventas → Mailings`);
    }
    if(sinEmail.length)console.warn('Clientes sin email para recordatorios:',[...new Set(sinEmail)]);
    localStorage.setItem('lastMailGen',hoy);
  }catch(e){console.error('generarRecordatoriosAuto:',e);}
}
```

**IMPORTANTE**: leer `computeCtaCte()` real antes de implementar el bloque de cobranzas y adaptar los nombres de campos (`clientesVencidos/saldoVencido/diasAtraso` son ilustrativos — usar la estructura verdadera; si la función devuelve por-cliente aging FIFO, derivar saldo vencido y días máximos de ahí).

- [ ] **Step 3: Hook post-login**

Encontrar dónde termina el flujo de carga inicial (después del primer `loadAll()` + `renderAll()` del login — grep `loadAll()` en la zona de auth/init) y agregar `generarRecordatoriosAuto();` (sin await, fire-and-forget).

- [ ] **Step 4: Validar (comando global + tests nuevos), commit, push (deploy bloque 3A+3B-frontend), verificar en prod**

```bash
git add index.html tests/
git commit -m "feat(comercial): generación automática diaria de recordatorios con anti-duplicados"
git push origin main
```

Verificación en prod: abrir el ERP → notify de N generados → Ventas → Mailings muestra la cola → aprobar uno → queda `aprobado` (el envío real llega con Task 5).

---

### Task 5: Worker de envío en vitalmet-billing (3B server)

**Files:**
- Modify: `~/vitalmet-billing/main.py` — settings nuevas, mailer loop en lifespan, endpoint `/mailer/status`.
- Modify: `~/vitalmet-billing/README.md` — documentar env vars.

**Interfaces:**
- Consumes: `email_queue`/`email_log` vía Supabase REST (service key), Microsoft Graph `sendMail`.
- Produces: envío real; estados `enviado`/`fallido` en la cola; `GET /mailer/status`.

- [ ] **Step 1: Settings + cliente Graph + loop** (agregar a `main.py`; `httpx` ya es dependencia de FastAPI ecosystem — verificar en requirements.txt, si falta agregarlo)

```python
# ── Mailer (email_queue → Microsoft Graph) ─────────────────────────
class MailerSettings(BaseSettings):
    mailer_enabled: bool = False
    ms_tenant_id: str = ""
    ms_client_id: str = ""
    ms_client_secret: str = ""
    mail_sender: str = "ventas@vitalmetsa.com"
    supabase_url: str = ""
    supabase_service_key: str = ""
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

_mailer_state = {"last_run": None, "sent": 0, "failed": 0, "last_error": None}

async def _graph_token(s: MailerSettings, client: "httpx.AsyncClient") -> str:
    r = await client.post(
        f"https://login.microsoftonline.com/{s.ms_tenant_id}/oauth2/v2.0/token",
        data={"client_id": s.ms_client_id, "client_secret": s.ms_client_secret,
              "scope": "https://graph.microsoft.com/.default", "grant_type": "client_credentials"})
    r.raise_for_status()
    return r.json()["access_token"]

def _supa_headers(s: MailerSettings) -> dict:
    return {"apikey": s.supabase_service_key, "Authorization": f"Bearer {s.supabase_service_key}",
            "Content-Type": "application/json", "Prefer": "return=representation"}

async def _mailer_cycle(s: MailerSettings, client: "httpx.AsyncClient") -> None:
    base = f"{s.supabase_url}/rest/v1"
    q = await client.get(f"{base}/email_queue", headers=_supa_headers(s),
                         params={"estado": "eq.aprobado", "scheduled_at": f"lte.{datetime.utcnow().isoformat()}Z",
                                 "select": "*", "limit": "20"})
    q.raise_for_status()
    rows = q.json()
    if not rows:
        return
    token = await _graph_token(s, client)
    for row in rows:
        try:
            r = await client.post(
                f"https://graph.microsoft.com/v1.0/users/{s.mail_sender}/sendMail",
                headers={"Authorization": f"Bearer {token}"},
                json={"message": {"subject": row["subject"],
                                  "body": {"contentType": "HTML", "content": row["body_html"]},
                                  "toRecipients": [{"emailAddress": {"address": row["to_email"], "name": row.get("to_nombre") or row["to_email"]}}]},
                      "saveToSentItems": True})
            r.raise_for_status()
            now = datetime.utcnow().isoformat() + "Z"
            await client.patch(f"{base}/email_queue", headers=_supa_headers(s),
                               params={"id": f"eq.{row['id']}"},
                               json={"estado": "enviado", "enviado_at": now})
            await client.post(f"{base}/email_log", headers=_supa_headers(s),
                              json={"empresa_id": row["empresa_id"], "queue_id": row["id"],
                                    "venta_id": row.get("venta_id"), "cliente_id": row.get("cliente_id"),
                                    "template_id": row.get("template_id"), "to_email": row["to_email"],
                                    "subject": row["subject"]})
            _mailer_state["sent"] += 1
        except Exception as exc:  # noqa: BLE001 — un mail fallido no frena el ciclo
            _mailer_state["failed"] += 1
            _mailer_state["last_error"] = str(exc)[:500]
            await client.patch(f"{base}/email_queue", headers=_supa_headers(s),
                               params={"id": f"eq.{row['id']}"},
                               json={"estado": "fallido", "error_texto": str(exc)[:500]})

async def mailer_loop() -> None:
    import asyncio
    s = MailerSettings()
    if not (s.mailer_enabled and s.ms_tenant_id and s.supabase_service_key):
        logging.getLogger("mailer").info("Mailer deshabilitado (faltan env vars o MAILER_ENABLED=false)")
        return
    async with httpx.AsyncClient(timeout=30) as client:
        while True:
            try:
                await _mailer_cycle(s, client)
                _mailer_state["last_run"] = datetime.utcnow().isoformat() + "Z"
            except Exception as exc:  # noqa: BLE001
                _mailer_state["last_error"] = str(exc)[:500]
                logging.getLogger("mailer").error("ciclo mailer: %s", exc)
            await asyncio.sleep(300)
```

Agregar `import httpx` arriba (y a `requirements.txt` si no está). En el `lifespan` existente (línea ~381), lanzar la task: `task = asyncio.create_task(mailer_loop())` al entrar y `task.cancel()` al salir (respetar la estructura actual del lifespan — leerla antes de editar).

Endpoint de estado (junto a los endpoints existentes, con el mismo `Depends` de api key que usan los demás):

```python
@app.get("/mailer/status")
async def mailer_status(_: None = Depends(require_api_key)):  # usar el guard real del archivo
    return _mailer_state
```

- [ ] **Step 2: Probar localmente** (sin credenciales reales el loop se auto-deshabilita y loguea el aviso)

```bash
cd ~/vitalmet-billing && python3 -c "import main" && echo IMPORT_OK
```

- [ ] **Step 3: Commit + push (Railway auto-deploya) + pedir credenciales a Giuliano**

```bash
cd ~/vitalmet-billing && git add main.py requirements.txt README.md && git commit -m "feat(mailer): worker de envío email_queue → Microsoft Graph (detrás de MAILER_ENABLED)" && git push
```

Mensaje a Giuliano: hacer `docs/azure-ad-setup.md` (app con permiso de APLICACIÓN `Mail.Send` + admin consent — no delegado) y cargar en Railway: `MAILER_ENABLED=true`, `MS_TENANT_ID`, `MS_CLIENT_ID`, `MS_CLIENT_SECRET`, `MAIL_SENDER=ventas@vitalmetsa.com`, `SUPABASE_URL=https://dqvlqhaxgvtilhiuatpv.supabase.co`, `SUPABASE_SERVICE_KEY=<service_role del panel>`.

- [ ] **Step 4: Verificación end-to-end** (cuando las env estén): aprobar un email de prueba a una casilla propia → en ≤5 min llega, la fila pasa a `enviado`, aparece en Historial, y `GET /mailer/status` muestra `sent≥1`.

---

### Task 6: Métricas de pipeline (3E)

**Files:**
- Modify: `~/vitalmet-erp/index.html` — función pura + ampliación de `renderPresupuestos` stats (`#presup-stats`, render en ~9069).
- Test: `tests/mailings.test.js` (o `tests/pipeline.test.js`).

**Interfaces:**
- Consumes: `presupuestos` (`fecha`, `estado`, `total`, `updated_at` si existe — verificar; si no hay fecha de decisión, usar `updated_at` o omitir ciclo para registros viejos).
- Produces: `computePipelineMetrics(presupuestos, hoyISO) → {cicloPromedioDias, ganado6m:[{mes,ganado,perdido}], agingAbiertos:[{nro,cliente,dias}]}`.

- [ ] **Step 1: Test que falla**

```js
test('computePipelineMetrics calcula ciclo, ganado/perdido y aging', () => {
  const r = erp.run(`(()=>{
    const ps=[
      {nro:'P-1',cliente:'A',estado:'convertido',total:'1000',fecha:'2026-06-01',updated_at:'2026-06-11T00:00:00Z'},
      {nro:'P-2',cliente:'B',estado:'rechazado',total:'500',fecha:'2026-06-05',updated_at:'2026-06-25T00:00:00Z'},
      {nro:'P-3',cliente:'C',estado:'enviado',total:'800',fecha:'2026-06-27'},
    ];
    return computePipelineMetrics(ps,'2026-07-07');
  })()`);
  assert.strictEqual(r.cicloPromedioDias, 15); // (10+20)/2
  assert.strictEqual(Array.from(r.agingAbiertos)[0].dias, 10);
  const jun = Array.from(r.ganado6m).find(m=>m.mes==='2026-06');
  assert.strictEqual(jun.ganado, 1000);
  assert.strictEqual(jun.perdido, 500);
});
```

- [ ] **Step 2: Implementar** (pura, junto a las otras; decisión con `updated_at` como proxy de fecha de decisión, registros sin `updated_at` se omiten del ciclo):

```js
function computePipelineMetrics(ps,hoyISO){
  const hoyMs=new Date(hoyISO+'T00:00:00').getTime();
  const dias=(a,b)=>Math.round((new Date(b).getTime()-new Date(a+'T00:00:00').getTime())/86400000);
  const decididos=ps.filter(p=>['convertido','rechazado','vencido'].includes(p.estado)&&p.fecha&&p.updated_at);
  const ciclos=decididos.map(p=>dias(p.fecha,p.updated_at)).filter(d=>d>=0&&d<365);
  const cicloPromedioDias=ciclos.length?Math.round(ciclos.reduce((a,b)=>a+b,0)/ciclos.length):null;
  const meses={};
  ps.forEach(p=>{
    if(!p.fecha)return;
    const mes=p.fecha.slice(0,7);
    if(!meses[mes])meses[mes]={mes,ganado:0,perdido:0};
    if(p.estado==='convertido')meses[mes].ganado+=parseFloat(p.total||0);
    else if(['rechazado','vencido'].includes(p.estado))meses[mes].perdido+=parseFloat(p.total||0);
  });
  const ganado6m=Object.values(meses).sort((a,b)=>b.mes.localeCompare(a.mes)).slice(0,6).reverse();
  const agingAbiertos=ps.filter(p=>p.estado==='enviado'&&p.fecha)
    .map(p=>({nro:p.nro,cliente:p.cliente,dias:Math.round((hoyMs-new Date(p.fecha+'T00:00:00').getTime())/86400000)}))
    .sort((a,b)=>b.dias-a.dias);
  return {cicloPromedioDias,ganado6m,agingAbiertos};
}
```

(Verificar que `presupuestos` traiga `updated_at` en el `select=*` de loadAll — sí, es `select=*`. Si la columna no existe en la tabla, el ciclo devuelve null y no se muestra.)

- [ ] **Step 3: UI** — en `renderPresupuestos`, después de las stat-cards existentes agregar una fila `#presup-pipeline` (div debajo de `#presup-stats` en el HTML) con: card "Ciclo promedio: N días", mini-tabla ganado/perdido por mes (6 filas), y "Pipeline abierto" con los 5 más viejos (nro · cliente · días, con color coral si 7+). Todo con `esc()` y estilos de stat-card/dash-card existentes.

- [ ] **Step 4: Validar, commit, push (deploy final), verificar (cierra P3)**

```bash
git add index.html tests/ && git commit -m "feat(comercial): métricas de pipeline — ciclo promedio, ganado vs perdido y aging"
git push origin main
```

---

## Self-review

- **Cobertura:** 3D→T1, 3C→T2, 3A→T3, 3B→T4+T5, 3E→T6. ✓
- **Placeholders:** los puntos "leer estructura real antes de editar" (computeCtaCte en T4, lifespan/require_api_key en T5, footer de modales en T3) son lookups explícitos e inevitables en un plan cross-repo, con instrucción concreta de qué mirar. ✓
- **Consistencia:** `mailingsQueueCount` definido en T3, consumido en T2 (con guard `typeof`); `ensureMailingsData/emailQueue/emailTemplates` (T3) consumidos por T4; contrato `email_queue.estado` idéntico entre T4 (escribe) y T5 (procesa). ✓
