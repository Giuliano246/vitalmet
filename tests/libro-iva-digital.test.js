// Tests del Libro IVA Digital RG 4597 (migración 068): registros TXT
// de ancho fijo para el importador de ARCA (formato espejo CITI 3685).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const VENTA = {
  fecha: '2026-08-05', tipo: 1, pv: 4, nro: 123, docTipo: 80,
  docNro: '30112223334', denom: 'ACME SA', total: 121000, noGravado: 0,
  exento: 0, moneda: 'PES', tc: 1,
  alicuotas: [{ pct: 21, neto: 100000, iva: 21000 }],
};

function lidVentas(cbtes) {
  return erp.run(`buildLidVentas(${JSON.stringify(cbtes)})`);
}
function lidCompras(cbtes) {
  return erp.run(`buildLidCompras(${JSON.stringify(cbtes)})`);
}

test('buildLidVentas: largos fijos (266 cbte / 62 alícuota) y campos clave', () => {
  const r = lidVentas([VENTA]);
  assert.strictEqual(r.cbte.length, 266);
  assert.strictEqual(r.alic.length, 62);
  assert.ok(r.cbte.startsWith('20260805' + '001' + '00004'));           // fecha+tipo+pv
  assert.ok(r.cbte.includes('000000012100000'));                        // total en centavos
  assert.ok(r.cbte.includes('PES' + '0001000000'));                     // moneda + TC 1.000000
  assert.ok(r.alic.includes('0005'));                                   // alícuota 21% = id 5
  assert.ok(r.alic.endsWith('000000002100000'));                        // IVA liquidado
});

test('buildLidVentas: NC va con su tipo (8) e importes positivos', () => {
  const r = lidVentas([{ ...VENTA, tipo: 8, total: 1000, alicuotas: [{ pct: 21, neto: 826.45, iva: 173.55 }] }]);
  assert.ok(r.cbte.slice(8, 11) === '008');
  assert.ok(!r.cbte.includes('-'));
});

test('buildLidVentas: varias líneas separadas por CRLF, misma longitud', () => {
  const r = lidVentas([VENTA, { ...VENTA, nro: 124 }]);
  const lineas = r.cbte.split('\r\n');
  assert.strictEqual(lineas.length, 2);
  assert.ok(lineas.every((l) => l.length === 266));
});

test('buildLidCompras: largos fijos (325 cbte / 84 alícuota) y crédito fiscal', () => {
  const r = lidCompras([{
    fecha: '2026-08-10', tipo: 1, pv: 3, nro: 4567, docTipo: 80,
    docNro: '30556667778', denom: 'PROVEEDOR SRL', total: 60500,
    noGravado: 0, exento: 0, moneda: 'PES', tc: 1,
    percepIva: 0, percepNac: 0, percepIibb: 500, credFiscal: 10500,
    alicuotas: [{ pct: 21, neto: 50000, iva: 10500 }],
  }]);
  assert.strictEqual(r.cbte.length, 325);
  assert.strictEqual(r.alic.length, 84);
  assert.ok(r.cbte.includes('000000001050000'));  // crédito fiscal computable
  assert.ok(r.alic.includes('30556667778'));      // CUIT del vendedor en la alícuota
});

test('parseNroComprobante: PV-número, texto libre y basura', () => {
  // JSON.stringify: los objetos del contexto vm tienen otro prototipo
  const p = (s) => erp.run(`JSON.stringify(parseNroComprobante(${JSON.stringify(s)}))`);
  assert.strictEqual(p('00004-00001234'), '{"pv":4,"nro":1234}');
  assert.strictEqual(p('4-1234'), '{"pv":4,"nro":1234}');
  assert.strictEqual(p('FC 998877'), '{"pv":0,"nro":998877}');
  assert.strictEqual(p(''), '{"pv":0,"nro":0}');
});

test('helpers: lidNum centavos, lidFecha, lidAlicId', () => {
  assert.strictEqual(erp.run(`lidNum(1234.56)`), '000000000123456');
  assert.strictEqual(erp.run(`lidNum(-50)`), '000000000005000'); // siempre positivo
  assert.strictEqual(erp.run(`lidFecha('2026-01-09')`), '20260109');
  assert.strictEqual(erp.run(`lidAlicId(10.5)`), 4);
  assert.strictEqual(erp.run(`lidAlicId(27)`), 6);
});
