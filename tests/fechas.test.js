// Tests de fmtFecha (display dd/mm/yyyy en tablas y textos de UI).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const f = (v) => erp.run(`fmtFecha(${JSON.stringify(v)})`);

test('fmtFecha: ISO simple → dd/mm/yyyy', () => {
  assert.strictEqual(f('2026-08-26'), '26/08/2026');
  assert.strictEqual(f('2025-01-03'), '03/01/2025');
});

test('fmtFecha: timestamp ISO con hora también convierte', () => {
  assert.strictEqual(f('2026-08-26T14:30:00'), '26/08/2026');
  assert.strictEqual(f('2026-08-26 14:30:00+00'), '26/08/2026');
});

test('fmtFecha: falsy → vacío (los fallback ||"—" de la UI siguen funcionando)', () => {
  assert.strictEqual(f(null), '');
  assert.strictEqual(f(''), '');
  assert.strictEqual(f(undefined), '');
});

test('fmtFecha: formatos no-ISO pasan intactos', () => {
  assert.strictEqual(f('26/08/2026'), '26/08/2026');
  assert.strictEqual(f('sin fecha'), 'sin fecha');
});
