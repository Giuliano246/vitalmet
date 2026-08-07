// Tests de Notas de Crédito de venta (migración 067): desglose
// neto/IVA desde un monto con IVA incluido, espejo del redondeo por
// paso (r2) de la Edge Function facturacion.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function desglose(total, pct) {
  return erp.run(`computeNetoIvaDesdeTotal(${JSON.stringify(total)},${JSON.stringify(pct)})`);
}

test('computeNetoIvaDesdeTotal: 21% exacto', () => {
  const d = desglose(121000, 21);
  assert.strictEqual(d.neto, 100000);
  assert.strictEqual(d.iva, 21000);
  assert.strictEqual(d.total, 121000);
});

test('computeNetoIvaDesdeTotal: 10,5% exacto', () => {
  const d = desglose(110.5, 10.5);
  assert.strictEqual(d.neto, 100);
  assert.strictEqual(d.iva, 10.5);
  assert.strictEqual(d.total, 110.5);
});

test('computeNetoIvaDesdeTotal: el total devuelto es neto+iva redondeados (ajuste AFIP)', () => {
  // 100 / 1.21 = 82.6446… → 82.64 · IVA 17.3544… → 17.35 · total 99.99
  const d = desglose(100, 21);
  assert.strictEqual(d.neto, 82.64);
  assert.strictEqual(d.iva, 17.35);
  assert.strictEqual(d.total, 99.99);
  // El invariante que importa: lo que se emite balancea consigo mismo
  assert.strictEqual(d.total, Math.round((d.neto + d.iva) * 100) / 100);
});

test('computeNetoIvaDesdeTotal: 0% (exento/no gravado) — todo neto', () => {
  const d = desglose(5000, 0);
  assert.strictEqual(d.neto, 5000);
  assert.strictEqual(d.iva, 0);
  assert.strictEqual(d.total, 5000);
});

test('computeNetoIvaDesdeTotal: entradas inválidas no rompen (devuelve 0)', () => {
  const d = desglose('abc', 21);
  assert.strictEqual(d.neto, 0);
  assert.strictEqual(d.iva, 0);
  assert.strictEqual(d.total, 0);
});
