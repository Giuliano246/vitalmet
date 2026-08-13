// Tests del arreglo de CUIT al facturar: la venta guardaba el CUIT como
// foto (match de nombre); si quedaba vacía, facturar cortaba aunque el
// cliente tuviera el CUIT en su ficha. Ahora hay plan B al cliente vivo.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const CLIENTES = [
  { id: 1, nombre: 'ACME SA', cuit: '30-11222333-4', condicion_fiscal: 'RI' },
  { id: 2, nombre: '  Distribuidora Sur  ', cuit: '30999888771', condicion_fiscal: 'RI' }, // espacios en el nombre
  { id: 3, nombre: 'Consumidor Final', cuit: '', condicion_fiscal: 'consumidor_final' },
];
const call = (fn, ...args) => erp.run(`${fn}(${args.map((a) => JSON.stringify(a)).join(',')})`);

test('resolverClienteVenta: por cliente_id cuando la venta lo trae', () => {
  assert.strictEqual(call('resolverClienteVenta', { cliente_id: 2, cliente: 'texto viejo' }, CLIENTES).id, 2);
});

test('resolverClienteVenta: por nombre normalizado (trim + case-insensitive)', () => {
  assert.strictEqual(call('resolverClienteVenta', { cliente: 'acme sa' }, CLIENTES).id, 1);
  assert.strictEqual(call('resolverClienteVenta', { cliente: 'Distribuidora Sur' }, CLIENTES).id, 2);
});

test('resolverClienteVenta: sin match → undefined', () => {
  assert.strictEqual(call('resolverClienteVenta', { cliente: 'no existe' }, CLIENTES), undefined);
});

test('cuitParaFacturar: usa el CUIT de la venta si está', () => {
  assert.strictEqual(call('cuitParaFacturar', { cuit: '30-11222333-4' }, null), '30112223334');
});

test('cuitParaFacturar: PLAN B — cae al CUIT del cliente si la venta no lo tiene', () => {
  assert.strictEqual(call('cuitParaFacturar', { cuit: null }, CLIENTES[0]), '30112223334');
  assert.strictEqual(call('cuitParaFacturar', {}, CLIENTES[0]), '30112223334');
});

test('cuitParaFacturar: ambos vacíos → cadena vacía (consumidor final)', () => {
  assert.strictEqual(call('cuitParaFacturar', { cuit: '' }, CLIENTES[2]), '');
  assert.strictEqual(call('cuitParaFacturar', {}, null), '');
});

test('cuitParaFacturar: limpia guiones/espacios y deja 11 dígitos', () => {
  assert.strictEqual(call('cuitParaFacturar', { cuit: ' 30 999 888 77 1 ' }, null).length, 11);
});

test('escenario del bug: venta SIN CUIT + cliente CON CUIT → Factura A viable (doc 80, 11 díg.)', () => {
  const venta = { cliente: 'acme sa', cuit: null };        // la foto quedó vacía
  const cli = call('resolverClienteVenta', venta, CLIENTES);
  const cuit = call('cuitParaFacturar', venta, cli);
  assert.strictEqual(cuit.length, 11);                     // antes daba 0 → cortaba con error
  const cbte = call('tipoComprobanteVentaAFIP', cli.condicion_fiscal, cuit.length === 11);
  assert.strictEqual(cbte.tipo, 1);                        // Factura A, ya no se bloquea
});
