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

// ─── computeSaldoNC (mig 069, H-02): preview del saldo acreditable ───
// El control autoritativo es server-side (nc_reservar + trg_nc_tope);
// esto valida el espejo puro que alimenta el modal.

function saldoNC(total, previas) {
  return erp.run(`computeSaldoNC(${JSON.stringify(total)},${JSON.stringify(previas)})`);
}

test('computeSaldoNC: sin NC previas, el saldo es el total', () => {
  const r = saldoNC(121000, []);
  assert.strictEqual(r.acreditado, 0);
  assert.strictEqual(r.saldo, 121000);
});

test('computeSaldoNC: resta las NC previas', () => {
  const r = saldoNC(121000, [{ imp_total: 21000 }, { imp_total: '50000' }]);
  assert.strictEqual(r.acreditado, 71000);
  assert.strictEqual(r.saldo, 50000);
});

test('computeSaldoNC: sobre-acreditada clampea a 0 (nunca saldo negativo)', () => {
  const r = saldoNC(100, [{ imp_total: 80 }, { imp_total: 30 }]);
  assert.strictEqual(r.acreditado, 110);
  assert.strictEqual(r.saldo, 0);
});

test('computeSaldoNC: redondeo a 2 decimales (centavos AFIP)', () => {
  const r = saldoNC(100, [{ imp_total: 33.335 }, { imp_total: 33.335 }]);
  assert.strictEqual(r.acreditado, 66.67);
  assert.strictEqual(r.saldo, 33.33);
});

test('computeSaldoNC: entradas inválidas no rompen', () => {
  const r = saldoNC('abc', [{ imp_total: 'x' }, {}]);
  assert.strictEqual(r.acreditado, 0);
  assert.strictEqual(r.saldo, 0);
});
