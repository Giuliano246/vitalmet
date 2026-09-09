'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {load}=require('./_harness');

test('cierre consulta fechas actuales y bloquea factura sin asiento aunque el caché esté vacío',async()=>{
 const e=load();
 e.run(`globalThis.writes=[];globalThis.messages=[];notify=(m)=>messages.push(m);confirm=()=>true;db=async(method,table)=>{if(method!=='GET'){writes.push(table);return [];}return table==='facturas_emitidas'?[{id:'f',fecha:'2026-06-02',cae:'123'}]:[];};`);
 await e.run('cerrarPeriodo(2026,6)');
 assert.equal(e.run('writes.length'),0);assert.match(e.run('messages[0]'),/comprobante/);
});
test('cierre no escribe cuando falla la lectura de datos',async()=>{
 const e=load();e.run(`globalThis.writes=[];notify=()=>{};confirm=()=>true;db=async(method)=>{if(method==='GET')throw new Error('offline');writes.push(method);};`);
 await e.run('cerrarPeriodo(2026,6)');assert.equal(e.run('writes.length'),0);
});
test('clasificaciones guardadas se recuperan al cargar y un fallo no reemplaza la anterior',async()=>{
 const e=load();e.run(`currentEmpresa={id:'empresa'};calcularEECC=()=>{};pintarEECC=()=>{};notify=()=>{};globalThis.saved=[];db=async(method,table,body)=>{if(method==='GET')return saved;saved=[{linea_id:body.p_linea_id,categoria:body.p_categoria}];return saved[0];};`);
 await e.run(`cambiarClasificacionEFE('linea','op.otros')`);
 e.run('eeccClasificaciones={}');await e.run(`reload('efe_clasificaciones')`);
 assert.equal(e.run(`eeccClasificaciones.linea`),'op.otros');
 e.run(`db=async()=>{throw new Error('sin permiso')}`);
 await e.run(`cambiarClasificacionEFE('linea','fin.prestamos')`);
 assert.equal(e.run(`eeccClasificaciones.linea`),'op.otros');
});
test('bienes de uso separa ajustes históricos y detecta diferencias por cuenta sin compensarlas',()=>{
 const e=load();const o={desde:'2026-01-01',hasta:'2026-12-31',cuentas:[{id:'a',codigo:'1',tipo:'activo',rubro_rt54:'bienes_uso'},{id:'d',codigo:'2',tipo:'activo',rubro_rt54:'bienes_uso'}],bienes:[{id:'b',fecha_alta:'2025-01-01',valor_origen:100,cuenta_activo_id:'a',cuenta_amort_acum_id:'d'}],depreciaciones:[{bien_id:'b',hasta:'2026-12-31',importe:20}],asientos:[{id:'n',estado:'confirmado',fecha:'2025-01-01',moneda:'ARS'},{id:'i',estado:'confirmado',fecha:'2025-12-31',moneda:'ARS',origen_tipo:'ajuste_inflacion'}],lineas:[{asiento_id:'n',cuenta_id:'a',debe:110,haber:0},{asiento_id:'n',cuenta_id:'d',debe:0,haber:30},{asiento_id:'i',cuenta_id:'a',debe:50,haber:0},{asiento_id:'i',cuenta_id:'d',debe:0,haber:10}]};
 const r=e.run(`computeConciliacionBU(${JSON.stringify(o)})`);
 assert.equal(r[0].ajuste,50);assert.equal(r[0].diferencia,10);assert.equal(r[1].ajuste,-10);assert.equal(r[1].diferencia,-10);
});
