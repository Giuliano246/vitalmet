// Tests del sprint "inventario auditable" (2026-07-31): valuación de
// stock MP a costo por lote + PPP informativo, y valuación de PT.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

// ── computeValuacionMP ────────────────────────────────────────────

const BARRAS = [
  { material: 'AISI 316', kg_disponibles: 100, costo_usd_unidad: 10 },  // 1000
  { material: 'AISI 316', kg_disponibles: 50, costo_usd_unidad: 14 },   // 700
  { material: 'AISI 316', kg_disponibles: 30, costo_usd_unidad: null }, // sin costo
  { material: 'SAE 1045', kg_disponibles: 200, costo_usd_unidad: 4 },   // 800
  { material: 'SAE 1045', kg_disponibles: 0, costo_usd_unidad: 99 },    // agotada: no cuenta
];

test('computeValuacionMP agrupa por material con valor a costo por lote y PPP', () => {
  const r = erp.run(`computeValuacionMP(${JSON.stringify(BARRAS)})`);
  assert.strictEqual(r.length, 2);
  const a316 = r.find(x => x.material === 'AISI 316');
  assert.strictEqual(a316.kg, 180);
  assert.strictEqual(a316.valor, 1700);          // 100×10 + 50×14; los 30 sin costo no suman valor
  assert.strictEqual(a316.kgSinCosto, 30);
  assert.strictEqual(Math.round(a316.ppp * 100) / 100, 11.33); // 1700 / 150 kg con costo
  const sae = r.find(x => x.material === 'SAE 1045');
  assert.strictEqual(sae.kg, 200);               // la barra agotada no aparece
  assert.strictEqual(sae.valor, 800);
  assert.strictEqual(r[0].material, 'AISI 316'); // ordenado por valor desc
});

test('computeValuacionMP con stock vacío devuelve lista vacía', () => {
  assert.strictEqual(erp.run(`computeValuacionMP([])`).length, 0);
  assert.strictEqual(erp.run(`computeValuacionMP(null)`).length, 0);
});

// ── computeValuacionPT ────────────────────────────────────────────

test('computeValuacionPT usa costo_unitario y cae a precio_unitario', () => {
  const r = erp.run(`computeValuacionPT(${JSON.stringify([
    { cantidad: 10, costo_unitario: 14.3 },                        // 143 (costo real de OP)
    { cantidad: 5, costo_unitario: null, precio_unitario: 20 },    // 100 (fallback precio)
    { cantidad: 3, costo_unitario: null, precio_unitario: null },  // sin costo
    { cantidad: 0, costo_unitario: 99 },                           // sin stock: no cuenta
  ])})`);
  assert.strictEqual(r.unidades, 18);
  assert.strictEqual(r.valor, 243);
  assert.strictEqual(r.sinCosto, 3);
});
