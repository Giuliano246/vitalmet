// Tests de computeDivisionVenta — división de venta por entrega parcial
// (espejo JS de la RPC dividir_venta, migración 064).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function div(items, envios, total) {
  return erp.run(`computeDivisionVenta(${JSON.stringify(items)},${JSON.stringify(envios)},${JSON.stringify(total)})`);
}

const ITEMS = [
  { id: 'a', pieza: 'VTB 2"', cantidad: 10, total: 1000 },
  { id: 'b', pieza: 'Anillo BX', cantidad: 4, total: 200 },
];

test('división 5 de 10: mitades exactas y saldo complementario', () => {
  const d = div(ITEMS, { a: 5, b: 4 }, 1200);
  assert.strictEqual(d.ok, true);
  assert.strictEqual(d.unidadesEnviadas, 9);
  assert.strictEqual(d.unidadesSaldo, 5);
  const a = d.detalle.find(x => x.id === 'a');
  assert.strictEqual(a.enviar, 5);
  assert.strictEqual(a.saldo, 5);
  assert.strictEqual(a.totalEnviado, 500);
  assert.strictEqual(a.totalSaldo, 500);
  // El ítem b se envía entero → total entero, saldo 0
  const b = d.detalle.find(x => x.id === 'b');
  assert.strictEqual(b.totalEnviado, 200);
  assert.strictEqual(b.totalSaldo, 0);
  assert.strictEqual(d.totalEnviado, 700);
  assert.strictEqual(d.totalPendiente, 500);
});

test('las partes SIEMPRE suman el total original (redondeo: saldo = complemento)', () => {
  // 100 / 3 no cierra en 2 decimales: enviado redondea, el saldo absorbe
  const d = div([{ id: 'a', cantidad: 3, total: 100 }], { a: 1 }, 100);
  assert.strictEqual(d.ok, true);
  const a = d.detalle[0];
  assert.strictEqual(a.totalEnviado, 33.33);
  assert.strictEqual(a.totalSaldo, 66.67);
  assert.strictEqual(a.totalEnviado + a.totalSaldo, 100);
  assert.strictEqual(d.totalEnviado + d.totalPendiente, 100);
});

test('cabecera con bonif de cabecera: prorrateo por totales de ítems', () => {
  // Ítems suman 1200 pero la cabecera es 1080 (10% bonif) → 700/1200 de 1080
  const d = div(ITEMS, { a: 5, b: 4 }, 1080);
  assert.strictEqual(d.totalEnviado, 630);
  assert.strictEqual(d.totalPendiente, 450);
});

test('venta en $0: prorratea la cabecera por cantidades', () => {
  const d = div([{ id: 'a', cantidad: 10, total: 0 }], { a: 4 }, 500);
  assert.strictEqual(d.ok, true);
  assert.strictEqual(d.totalEnviado, 200);
  assert.strictEqual(d.totalPendiente, 300);
});

test('ítem no listado en envios va entero al saldo', () => {
  const d = div(ITEMS, { a: 10 }, 1200);
  assert.strictEqual(d.ok, true);
  const b = d.detalle.find(x => x.id === 'b');
  assert.strictEqual(b.enviar, 0);
  assert.strictEqual(b.saldo, 4);
  assert.strictEqual(b.totalEnviado, 0);
  assert.strictEqual(b.totalSaldo, 200);
});

test('error: cantidad a enviar mayor a la pedida', () => {
  const d = div(ITEMS, { a: 11, b: 0 }, 1200);
  assert.strictEqual(d.ok, false);
  assert.match(d.errores[0], /máximo 10/);
});

test('error: no se envía nada', () => {
  const d = div(ITEMS, { a: 0, b: 0 }, 1200);
  assert.strictEqual(d.ok, false);
  assert.match(d.errores[0], /al menos un ítem/);
});

test('error: se envía todo (no hay saldo — no corresponde dividir)', () => {
  const d = div(ITEMS, { a: 10, b: 4 }, 1200);
  assert.strictEqual(d.ok, false);
  assert.match(d.errores[0], /no queda saldo/);
});

test('error: venta sin ítems', () => {
  const d = div([], {}, 0);
  assert.strictEqual(d.ok, false);
  assert.match(d.errores[0], /no tiene ítems/);
});

test('cantidades decimales se truncan a enteros (unidades físicas)', () => {
  const d = div([{ id: 'a', cantidad: 10, total: 100 }], { a: 5.9 }, 100);
  assert.strictEqual(d.ok, true);
  assert.strictEqual(d.detalle[0].enviar, 5);
});
