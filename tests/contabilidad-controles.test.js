'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const erp=require('./_harness').load();
const call=(fn,o)=>erp.run(`${fn}(${JSON.stringify(o)})`);
const base={cuenta:{id:'bank',cuenta_contable_id:'b',moneda:'ARS'},desde:'2026-06-01',hasta:'2026-06-30',saldoInicial:100,
  asientos:[{id:'old',fecha:'2026-05-01',estado:'confirmado',moneda:'ARS'},{id:'ok',fecha:'2026-06-02',estado:'confirmado',moneda:'ARS'},{id:'draft',fecha:'2026-06-02',estado:'borrador',moneda:'ARS'},{id:'void',fecha:'2026-06-02',estado:'anulado',moneda:'ARS'}],
  lineas:[{id:'l0',asiento_id:'old',cuenta_id:'b',debe:100,haber:0},{id:'l1',asiento_id:'ok',cuenta_id:'b',debe:20,haber:0},{id:'l2',asiento_id:'draft',cuenta_id:'b',debe:999,haber:0},{id:'l3',asiento_id:'void',cuenta_id:'b',debe:888,haber:0}],
  extractos:[{id:'e',cuenta_bancaria_id:'bank',fecha:'2026-06-02',importe:20,conciliado:false}]};
test('conciliación: mismo período, saldo inicial y sólo asientos confirmados',()=>{
 const r=call('computeConciliacion',base);assert.equal(r.saldoLibro,120);assert.equal(r.saldoExtracto,120);assert.equal(r.diferencia,0);assert.equal(r.movs.length,1);assert.equal(r.movs[0].id,'l1');
});
test('conciliación: no inventa saldo inicial y detecta TC faltante',()=>{
 const r=call('computeConciliacion',{...base,saldoInicial:null});assert.equal(r.saldoExtracto,null);assert.equal(r.diferencia,null);
 const bad=call('computeConciliacion',{...base,asientos:base.asientos.map(a=>a.id==='ok'?{...a,moneda:'USD'}:a)});assert.ok(bad.errores.length);assert.equal(bad.saldoLibro,null);
});
test('conciliación: convierte USD al TC registrado y preserva cuenta USD',()=>{
 const a=base.asientos.map(a=>({...a,moneda:'USD',tipo_cambio:1000}));
 assert.equal(call('computeConciliacion',{...base,asientos:a}).saldoLibro,120000);
 assert.equal(call('computeConciliacion',{...base,asientos:a,cuenta:{...base.cuenta,moneda:'USD'}}).saldoLibro,120);
});
test('EECC: descuadre, clasificación, IPC y cargas fallidas bloquean validado',()=>{
 const p={sinRubro:['cuenta'],esp:{cuadra:false,dif:1,difAnt:2},ipcExacto:false,tieneAnterior:true,efe:{recpamEfectivo:5,pendientes:[]},bienesUso:{filas:[]}};
 const r=call('validarPaqueteEECC',{p,erroresCarga:['Asientos']});assert.equal(r.valido,false);assert.ok(r.errores.length>=5);
});
test('cierre: borradores bloquean; bancos pendientes requieren revisión',()=>{
 const r=call('computeRevisionCierre',{desde:base.desde,hasta:base.hasta,asientos:base.asientos,extractos:base.extractos,faltantes:[],erroresCarga:[]});assert.equal(r.borradores.length,1);assert.equal(r.pendientesBanco,1);assert.equal(r.puedeCerrar,false);
});
test('EFE: préstamo e intereses conservan sus contrapartidas',()=>{
 const r=call('computeEFE',{desde:base.desde,hasta:base.hasta,cuentas:[{id:'b',tipo:'activo',rubro_rt54:'caja_bancos'},{id:'p',tipo:'pasivo',rubro_rt54:'prestamos'},{id:'i',tipo:'egreso',rubro_rt54:'rfyt'}],asientos:[{id:'a',fecha:'2026-06-01',estado:'confirmado',moneda:'ARS',tipo:'manual'}],lineas:[{id:'b1',asiento_id:'a',cuenta_id:'b',debe:0,haber:1100},{id:'p1',asiento_id:'a',cuenta_id:'p',debe:1000,haber:0},{id:'i1',asiento_id:'a',cuenta_id:'i',debe:100,haber:0}],saldosInicio:{b:{debe:1100,haber:0}},saldosCierre:{b:{debe:1100,haber:1100}}});
 assert.equal(r.fin.prestamos,-1000);assert.equal(r.op.otros,-100);assert.equal(r.recpamEfectivo,0);assert.ok(r.detalle.length===2);
});
