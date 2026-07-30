// Tests del armado de factura electrónica (sprint integridad 2026-07-30).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function cbte(cond, tieneCuit) {
  return erp.run(`tipoComprobanteVentaAFIP(${JSON.stringify(cond)},${tieneCuit})`);
}
function items(list, opts) {
  return erp.run(`buildItemsFactura(${JSON.stringify(list)},${JSON.stringify(opts)})`);
}

test('tipoComprobanteVentaAFIP: RI y monotributo reciben Factura A (RG 5003)', () => {
  // Objetos cruzan el contexto vm: comparar propiedad por propiedad
  const ri = cbte('RI', true);
  assert.strictEqual(ri.tipo, 1);
  assert.strictEqual(ri.letra, 'A');
  const mono = cbte('monotributo', true);
  assert.strictEqual(mono.tipo, 1);
  assert.strictEqual(mono.letra, 'A');
});

test('tipoComprobanteVentaAFIP: exento y consumidor final reciben B', () => {
  assert.strictEqual(cbte('exento', true).tipo, 6);
  assert.strictEqual(cbte('consumidor_final', false).tipo, 6);
});

test('tipoComprobanteVentaAFIP: con CUIT sin condición definida → null (falta el dato)', () => {
  assert.strictEqual(cbte(null, true), null);
});

test('tipoComprobanteVentaAFIP: sin CUIT sin condición → B consumidor final', () => {
  const r = cbte(null, false);
  assert.strictEqual(r.tipo, 6);
  assert.strictEqual(r.letra, 'B');
});

test('buildItemsFactura convierte USD→ARS al TC y manda neto', () => {
  const r = items(
    [{ pieza: 'Unión doble 2"', cantidad: 2, precio_unitario: 100 }],
    { tc: 1300, ivaPct: 21, incluyenIva: false }
  );
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].descripcion, 'Unión doble 2"');
  assert.strictEqual(r[0].cantidad, 2);
  assert.strictEqual(r[0].precio_unit, 130000); // 100 USD × 1300, ya es neto
  assert.strictEqual(r[0].iva_pct, 21);
});

test('buildItemsFactura desagrega IVA si los precios lo incluyen', () => {
  const r = items(
    [{ pieza: 'Anillo BX', cantidad: 1, precio_unitario: 121 }],
    { tc: 1000, ivaPct: 21, incluyenIva: true }
  );
  assert.strictEqual(r[0].precio_unit, 100000); // 121.000 ARS / 1.21
});

test('buildItemsFactura tolera lista vacía y campos faltantes', () => {
  assert.strictEqual(items([], { tc: 1000, ivaPct: 21, incluyenIva: false }).length, 0);
  const r = items([{ cantidad: 1 }], { tc: 1000, ivaPct: 21, incluyenIva: false });
  assert.strictEqual(r[0].descripcion, 'Producto');
  assert.strictEqual(r[0].precio_unit, 0);
});
