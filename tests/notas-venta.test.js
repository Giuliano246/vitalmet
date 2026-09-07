// Tests del sprint "NC/ND de venta" (2026-09-07, migración 075): tipos
// AFIP de nota por factura/letra, saldo acreditable ignorando ND, líneas
// del asiento para NC y ND, resolución del cliente de una factura sin
// venta y validación de la asociación de una nota libre.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

// ── tipos ──────────────────────────────────────────────────────────

test('tipoNota: NC y ND de la misma letra que la factura', () => {
  assert.strictEqual(erp.run(`tipoNota(1,'nc')`), 3);
  assert.strictEqual(erp.run(`tipoNota(1,'nd')`), 2);
  assert.strictEqual(erp.run(`tipoNota(6,'nc')`), 8);
  assert.strictEqual(erp.run(`tipoNota(6,'nd')`), 7);
  assert.strictEqual(erp.run(`tipoNota(11,'nd')`), 12);
  assert.strictEqual(erp.run(`tipoNota(51,'nc')`), 53);
  assert.strictEqual(erp.run(`tipoNota(3,'nc')`), null); // una NC no admite nota
});

test('tipoNotaPorLetra y claseNota', () => {
  assert.strictEqual(erp.run(`tipoNotaPorLetra('A','nc')`), 3);
  assert.strictEqual(erp.run(`tipoNotaPorLetra('B','nd')`), 7);
  assert.strictEqual(erp.run(`tipoNotaPorLetra('Z','nd')`), null);
  assert.strictEqual(erp.run(`claseNota(8)`), 'nc');
  assert.strictEqual(erp.run(`claseNota(52)`), 'nd');
  assert.strictEqual(erp.run(`claseNota(1)`), null);
});

// ── computeSaldoNC ignora ND ───────────────────────────────────────

test('computeSaldoNC suma sólo NC previas (las ND asociadas no reducen el saldo)', () => {
  const r = erp.run(`computeSaldoNC(1000, ${JSON.stringify([
    { tipo_comprobante: 3, imp_total: 300 },
    { tipo_comprobante: 2, imp_total: 500 },  // ND: no cuenta
    { tipo_comprobante: 8, imp_total: 100 },
  ])})`);
  assert.strictEqual(r.acreditado, 400);
  assert.strictEqual(r.saldo, 600);
});

test('computeSaldoNC sin tipo_comprobante (datos viejos) sigue contando como NC', () => {
  const r = erp.run(`computeSaldoNC(100, [{ imp_total: 40 }])`);
  assert.strictEqual(r.saldo, 60);
});

// ── armarLineasNota ───────────────────────────────────────────────

const CTAS = { ctaVentas: { id: 'v' }, ctaIvaDeb: { id: 'iva' }, ctaDeudores: { id: 'd' } };

test('armarLineasNota NC: debe Ventas + IVA, haber Deudores por el total', () => {
  const l = erp.run(`armarLineasNota(${JSON.stringify({ clase: 'nc', neto: 100, iva: 21, total: 121, ...CTAS, fmt: 'NC-A 00004-00000010', cliente: 'YPF' })})`);
  assert.strictEqual(l.length, 3);
  assert.deepStrictEqual([l[0].cuenta_id, l[0].debe, l[0].haber], ['v', 100, 0]);
  assert.deepStrictEqual([l[1].cuenta_id, l[1].debe, l[1].haber], ['iva', 21, 0]);
  assert.deepStrictEqual([l[2].cuenta_id, l[2].debe, l[2].haber], ['d', 0, 121]);
});

test('armarLineasNota ND: debe Deudores por el total, haber Ventas + IVA', () => {
  const l = erp.run(`armarLineasNota(${JSON.stringify({ clase: 'nd', neto: 100, iva: 21, total: 121, ...CTAS, fmt: 'ND-A 00004-00000011', cliente: 'YPF' })})`);
  assert.strictEqual(l.length, 3);
  assert.deepStrictEqual([l[0].cuenta_id, l[0].debe, l[0].haber], ['d', 121, 0]);
  assert.deepStrictEqual([l[1].cuenta_id, l[1].debe, l[1].haber], ['v', 0, 100]);
  assert.deepStrictEqual([l[2].cuenta_id, l[2].debe, l[2].haber], ['iva', 0, 21]);
  const debe = l.reduce((a, x) => a + x.debe, 0), haber = l.reduce((a, x) => a + x.haber, 0);
  assert.strictEqual(debe, haber);
});

test('armarLineasNota sin IVA (letra C / exento): dos líneas por el neto', () => {
  const l = erp.run(`armarLineasNota(${JSON.stringify({ clase: 'nc', neto: 100, iva: 0, total: 100, ctaVentas: { id: 'v' }, ctaIvaDeb: null, ctaDeudores: { id: 'd' }, fmt: 'NC-C', cliente: 'X' })})`);
  assert.strictEqual(l.length, 2);
  assert.strictEqual(l[1].haber, 100);
});

// ── resolverClienteFactura ────────────────────────────────────────

const CLIENTES = [{ id: 'c1', nombre: 'YPF SA', cuit: '30-54668997-9' }, { id: 'c2', nombre: 'Otro', cuit: '20-11111111-1' }];

test('resolverClienteFactura: por la venta si existe', () => {
  const r = erp.run(`resolverClienteFactura(${JSON.stringify({ venta_id: 'v1', doc_nro: '20111111111' })}, ${JSON.stringify([{ id: 'v1', cliente: 'YPF SA', cliente_id: 'c1' }])}, ${JSON.stringify(CLIENTES)})`);
  assert.deepStrictEqual({ ...r }, { cliente: 'YPF SA', cliente_id: 'c1' });
});

test('resolverClienteFactura: factura directa → por CUIT (ignora guiones)', () => {
  const r = erp.run(`resolverClienteFactura(${JSON.stringify({ venta_id: null, doc_nro: '30546689979' })}, [], ${JSON.stringify(CLIENTES)})`);
  assert.deepStrictEqual({ ...r }, { cliente: 'YPF SA', cliente_id: 'c1' });
});

test('resolverClienteFactura: sin match devuelve "cliente" sin id', () => {
  const r = erp.run(`resolverClienteFactura(${JSON.stringify({ venta_id: null, doc_nro: '0' })}, [], ${JSON.stringify(CLIENTES)})`);
  assert.deepStrictEqual({ ...r }, { cliente: 'cliente', cliente_id: null });
});

// ── validarAsociacionNota ─────────────────────────────────────────

test('validarAsociacionNota: período válido', () => {
  const r = erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'periodo', desde: '2026-08-01', hasta: '2026-08-31' })})`);
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual({ ...r.periodo_asociado }, { desde: '2026-08-01', hasta: '2026-08-31' });
  assert.strictEqual(r.comprobantes_asociados, null);
});

test('validarAsociacionNota: período invertido o incompleto', () => {
  assert.strictEqual(erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'periodo', desde: '2026-08-31', hasta: '2026-08-01' })})`).ok, false);
  assert.strictEqual(erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'periodo', desde: '', hasta: '2026-08-01' })})`).ok, false);
});

test('validarAsociacionNota: comprobante externo → CbteAsoc con la letra de la nota', () => {
  const r = erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'externo', letra: 'A', pv: '3', nro: '1520', fecha: '2026-07-10' })})`);
  assert.strictEqual(r.ok, true, r.error);
  assert.deepStrictEqual({ ...r.comprobantes_asociados[0] }, { tipo: 1, punto_venta: 3, numero: 1520, fecha: '2026-07-10' });
  assert.strictEqual(r.cbte_asoc_externo, 'FA-A 00003-00001520');
  assert.strictEqual(r.periodo_asociado, null);
});

test('validarAsociacionNota: externo sin número o PV inválido', () => {
  assert.strictEqual(erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'externo', letra: 'A', pv: '0', nro: '1' })})`).ok, false);
  assert.strictEqual(erp.run(`validarAsociacionNota(${JSON.stringify({ modo: 'externo', letra: 'A', pv: '3', nro: '' })})`).ok, false);
});

// ── facturasSinAsiento cubre ND ───────────────────────────────────

test('facturasSinAsiento: una ND con asiento origen nota-debito no figura como faltante', () => {
  const r = erp.run(`facturasSinAsiento(${JSON.stringify([{ id: 'nd1', cae: 'X', tipo_comprobante: 2 }, { id: 'nd2', cae: 'Y', tipo_comprobante: 7 }])}, ${JSON.stringify([{ origen_tipo: 'nota-debito', origen_id: 'nd1' }])})`);
  assert.deepStrictEqual([...r.map(x => x.id)], ['nd2']);
});
