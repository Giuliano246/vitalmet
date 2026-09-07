// Tests del sprint "listados de facturas" (2026-09-07, hoja de arreglos,
// sprint 3): filtros combinables de facturas emitidas (cliente × tipo ×
// fecha × texto), resumen FA/NC/ND/neto, texto de origen, y filtros de
// facturas recibidas (proveedor × tipo × fecha × texto).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const CLIENTES = `[{id:'c1',nombre:'YPF',cuit:'30-12345678-9'},{id:'c2',nombre:'Pan American',cuit:'30-99999999-1'}]`;
const VENTAS = `[{id:'v1',cliente_id:'c1',cliente:'YPF',nro_remito:'R-0012'}]`;
const FACTURAS = `[
  {id:'f1',venta_id:'v1',tipo_comprobante:1,punto_venta:4,numero:10,fecha:'2026-08-01',doc_nro:'30123456789',imp_neto:1000,imp_iva:210,imp_total:1210,cae:'111'},
  {id:'f2',venta_id:null,tipo_comprobante:1,punto_venta:4,numero:11,fecha:'2026-08-15',doc_nro:'30999999991',imp_neto:2000,imp_iva:420,imp_total:2420,cae:'222'},
  {id:'f3',venta_id:null,factura_asociada_id:'f2',tipo_comprobante:3,punto_venta:4,numero:1,fecha:'2026-09-01',doc_nro:'30999999991',imp_neto:500,imp_iva:105,imp_total:605,cae:'333'},
  {id:'f4',venta_id:null,tipo_comprobante:2,punto_venta:4,numero:1,fecha:'2026-09-03',doc_nro:'30123456789',imp_neto:100,imp_iva:21,imp_total:121,cae:'444',periodo_asoc_desde:'2026-08-01',periodo_asoc_hasta:'2026-08-31'}
]`;
const ctx = `{ventas:${VENTAS},clientes:${CLIENTES}}`;
const ids = (expr) => [...erp.run(`${expr}.map(x=>x.f.id)`)];

// ── facturas emitidas ──────────────────────────────────────────────

test('filtrarFacturasEmitidas: sin filtros devuelve todo, enriquecido con cliente y clase', () => {
  const rows = erp.run(`filtrarFacturasEmitidas(${FACTURAS},{},${ctx}).map(x=>({id:x.f.id,cliente:x.cliente,cliente_id:x.cliente_id,clase:x.clase,signo:x.signo,venta:x.venta?x.venta.id:null,asociada:x.asociada?x.asociada.id:null}))`);
  assert.deepStrictEqual([...rows].map(r => ({ ...r })), [
    { id: 'f1', cliente: 'YPF', cliente_id: 'c1', clase: 'fa', signo: 1, venta: 'v1', asociada: null },
    { id: 'f2', cliente: 'Pan American', cliente_id: 'c2', clase: 'fa', signo: 1, venta: null, asociada: null },
    { id: 'f3', cliente: 'Pan American', cliente_id: 'c2', clase: 'nc', signo: -1, venta: null, asociada: 'f2' },
    { id: 'f4', cliente: 'YPF', cliente_id: 'c1', clase: 'nd', signo: 1, venta: null, asociada: null },
  ]);
});

test('filtrarFacturasEmitidas: por cliente (resuelto por venta o por CUIT)', () => {
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{clienteId:'c1'},${ctx})`), ['f1', 'f4']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{clienteId:'c2'},${ctx})`), ['f2', 'f3']);
});

test('filtrarFacturasEmitidas: por tipo fa / nc / nd', () => {
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{tipo:'fa'},${ctx})`), ['f1', 'f2']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{tipo:'nc'},${ctx})`), ['f3']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{tipo:'nd'},${ctx})`), ['f4']);
});

test('filtrarFacturasEmitidas: rango de fechas inclusivo y combinado con cliente', () => {
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{desde:'2026-08-15',hasta:'2026-09-01'},${ctx})`), ['f2', 'f3']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{desde:'2026-09-01'},${ctx})`), ['f3', 'f4']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{hasta:'2026-08-31',clienteId:'c1'},${ctx})`), ['f1']);
});

test('filtrarFacturasEmitidas: texto busca en cliente, CUIT, número, CAE y remito', () => {
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{texto:'pan am'},${ctx})`), ['f2', 'f3']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{texto:'30999999991'},${ctx})`), ['f2', 'f3']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{texto:'444'},${ctx})`), ['f4']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{texto:'r-0012'},${ctx})`), ['f1']);
  assert.deepStrictEqual(ids(`filtrarFacturasEmitidas(${FACTURAS},{texto:'00004-00000011'},${ctx})`), ['f2']);
});

test('resumenFacturasEmitidas: FA, NC, ND y neto = FA − NC + ND', () => {
  const r = erp.run(`resumenFacturasEmitidas(filtrarFacturasEmitidas(${FACTURAS},{},${ctx}))`);
  assert.deepStrictEqual({ ...r }, { n: 4, fa: 3630, nc: 605, nd: 121, neto: 3146 });
  const vacio = erp.run(`resumenFacturasEmitidas([])`);
  assert.deepStrictEqual({ ...vacio }, { n: 0, fa: 0, nc: 0, nd: 0, neto: 0 });
});

test('cbteLabel y origenFacturaEmitida', () => {
  assert.strictEqual(erp.run(`cbteLabel({tipo_comprobante:1,punto_venta:4,numero:10})`), 'FA-A 00004-00000010');
  assert.strictEqual(erp.run(`cbteLabel({tipo_comprobante:8,punto_venta:4,numero:3})`), 'NC-B 00004-00000003');
  assert.strictEqual(erp.run(`cbteLabel({tipo_comprobante:52,punto_venta:1,numero:7})`), 'ND-M 00001-00000007');
  const rows = erp.run(`filtrarFacturasEmitidas(${FACTURAS},{},${ctx}).map(x=>origenFacturaEmitida(x.f,x))`);
  assert.deepStrictEqual([...rows], ['Remito R-0012', 'Directa', 's/ FA-A 00004-00000011', 'Período 01/08/2026–31/08/2026']);
  assert.strictEqual(erp.run(`origenFacturaEmitida({cbte_asoc_externo:'FA A 00002-00000099'},{})`), 's/ FA A 00002-00000099');
});

// ── facturas recibidas ─────────────────────────────────────────────

const PROVS = `[{id:'p1',nombre:'Aceros Sur'},{id:'p2',nombre:'Fletes Norte'}]`;
const OCS = `[{id:'o1',nro:'OC-0007'}]`;
const RECIBIDAS = `[
  {id:'r1',proveedor_id:'p1',oc_id:'o1',tipo:'factura',nro:'0001-00000500',fecha:'2026-07-20',total:1000},
  {id:'r2',proveedor_id:'p1',oc_id:null,tipo:'nota_credito',nro:'0001-00000012',fecha:'2026-08-02',total:200},
  {id:'r3',proveedor_id:'p2',oc_id:null,tipo:'factura',nro:'0003-00000090',fecha:'2026-08-10',total:300},
  {id:'r4',proveedor_id:'p2',oc_id:null,tipo:'nota_debito',nro:'0003-00000002',fecha:'2026-09-05',total:50}
]`;
const rctx = `{proveedores:${PROVS},ordenesCompra:${OCS}}`;
const rids = (expr) => [...erp.run(`${expr}.map(x=>x.r.id)`)];

test('filtrarFacturasRecibidas: enriquece con proveedor, OC y signo', () => {
  const rows = erp.run(`filtrarFacturasRecibidas(${RECIBIDAS},{},${rctx}).map(x=>({id:x.r.id,prov:x.prov?x.prov.nombre:null,oc:x.oc?x.oc.nro:null,signo:x.signo,tipo:x.tipo}))`);
  assert.deepStrictEqual([...rows].map(r => ({ ...r })), [
    { id: 'r1', prov: 'Aceros Sur', oc: 'OC-0007', signo: 1, tipo: 'factura' },
    { id: 'r2', prov: 'Aceros Sur', oc: null, signo: -1, tipo: 'nota_credito' },
    { id: 'r3', prov: 'Fletes Norte', oc: null, signo: 1, tipo: 'factura' },
    { id: 'r4', prov: 'Fletes Norte', oc: null, signo: 1, tipo: 'nota_debito' },
  ]);
});

test('filtrarFacturasRecibidas: proveedor × tipo × fecha combinados', () => {
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{proveedorId:'p1'},${rctx})`), ['r1', 'r2']);
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{tipo:'factura'},${rctx})`), ['r1', 'r3']);
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{desde:'2026-08-01',hasta:'2026-08-31'},${rctx})`), ['r2', 'r3']);
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{proveedorId:'p2',tipo:'factura',desde:'2026-08-01'},${rctx})`), ['r3']);
});

test('filtrarFacturasRecibidas: texto busca en OC, proveedor y número (comportamiento previo)', () => {
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{texto:'oc-0007'},${rctx})`), ['r1']);
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{texto:'fletes'},${rctx})`), ['r3', 'r4']);
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas(${RECIBIDAS},{texto:'00000012'},${rctx})`), ['r2']);
  // sin tipo → default 'factura' para filas viejas sin la columna
  assert.deepStrictEqual(rids(`filtrarFacturasRecibidas([{id:'x',proveedor_id:'p1',fecha:'2026-01-01'}],{tipo:'factura'},${rctx})`), ['x']);
});
