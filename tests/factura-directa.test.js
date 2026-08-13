// Tests de la factura directa (sin venta): armado puro de ítems y totales
// desde las filas del formulario. concepto=1 (productos), moneda ARS/USD.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const call = (fn, ...args) => erp.run(`${fn}(${args.map((a) => JSON.stringify(a)).join(',')})`);

const FILAS = [
  { descripcion: 'Repuesto X', cantidad: 2, precio: 100, ivaPct: 21 },
  { descripcion: 'Repuesto Y', cantidad: 1, precio: 50, ivaPct: 10.5 },
  { descripcion: '', cantidad: 0, precio: 0 }, // fila vacía → se filtra
];

test('facturaDirectaItems: ARS (tc=1) no convierte y filtra filas vacías', () => {
  const items = call('facturaDirectaItems', FILAS, 1);
  assert.strictEqual(items.length, 2);
  assert.strictEqual(items[0].precio_unit, 100);
  assert.strictEqual(items[0].iva_pct, 21);
  assert.strictEqual(items[1].iva_pct, 10.5);
});

test('facturaDirectaItems: USD convierte precio al TC', () => {
  const items = call('facturaDirectaItems', [{ descripcion: 'P', cantidad: 1, precio: 10, ivaPct: 21 }], 1200);
  assert.strictEqual(items[0].precio_unit, 12000); // 10 USD * 1200
});

test('facturaDirectaItems: descripción vacía → "Producto"; se corta a 200', () => {
  const items = call('facturaDirectaItems', [{ cantidad: 1, precio: 1 }, { descripcion: 'x'.repeat(250), cantidad: 1, precio: 1 }], 1);
  assert.strictEqual(items[0].descripcion, 'Producto');
  assert.strictEqual(items[1].descripcion.length, 200);
  assert.strictEqual(items[0].iva_pct, 21); // default cuando no viene ivaPct
});

test('facturaDirectaTotales: neto/iva/total con dos alícuotas', () => {
  const items = call('facturaDirectaItems', FILAS, 1);
  const t = call('facturaDirectaTotales', items);
  assert.strictEqual(t.neto, 250);                 // 200 + 50
  assert.strictEqual(t.iva, 47.25);                // 42 + 5.25
  assert.strictEqual(t.total, 297.25);
});

test('facturaDirectaTotales: sin ítems → todo cero', () => {
  const t = call('facturaDirectaTotales', []);
  assert.deepEqual([t.neto, t.iva, t.total], [0, 0, 0]);
});

test('escenario: cliente RI con CUIT → letra A y doc 80', () => {
  const clientes = [{ id: 1, nombre: 'ACME SA', cuit: '30-11222333-4', condicion_fiscal: 'RI' }];
  const venta = { cliente: 'ACME SA' };
  const cli = call('resolverClienteVenta', venta, clientes);
  const cuit = call('cuitParaFacturar', venta, cli);
  const cbte = call('tipoComprobanteVentaAFIP', cli.condicion_fiscal, cuit.length === 11);
  assert.strictEqual(cbte.tipo, 1);
  assert.strictEqual(cbte.letra, 'A');
  assert.strictEqual(cuit.length === 11 ? 80 : 99, 80);
});
