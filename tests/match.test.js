'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function evalMatch(args) {
  return erp.run(`evaluarMatchFactura(${JSON.stringify(args)})`);
}

test('match OK cuando el neto coincide con lo recibido', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1000, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.estado, 'ok');
});

test('match OK dentro de tolerancia porcentual', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1015, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, true); // umbral=min(20,5000)=20; dif 15<=20
});

test('tope absoluto recorta la tolerancia en montos grandes', () => {
  const r = evalMatch({ valorRecibido: 1000000, neto: 1010000, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, false); // umbral=min(20000,5000)=5000; dif 10000>5000
  assert.strictEqual(r.estado, 'discrepancia');
});

test('match falla fuera de tolerancia', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1200, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, false);
});
