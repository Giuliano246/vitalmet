// Tests del sprint "automatización" (2026-07-31): OC en tránsito desde
// reposición, última compra por material, semáforo de crédito y
// clientes inactivos.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

// ── enTransitoMaterial ────────────────────────────────────────────

const OCS = [
  { id: 'oc1', proveedor_id: 'prov-a', fecha: '2026-06-01', estado: 'confirmada' },
  { id: 'oc2', proveedor_id: 'prov-b', fecha: '2026-07-10', estado: 'recibida_parcial' },
  { id: 'oc3', proveedor_id: 'prov-a', fecha: '2026-07-20', estado: 'borrador' },
  { id: 'oc4', proveedor_id: 'prov-c', fecha: '2026-05-01', estado: 'anulada' },
];
const ITEMS = [
  { oc_id: 'oc1', material: 'AISI 316', cantidad: 100, cantidad_recibida: 0, precio_unitario: 12, unidad: 'mts', descripcion: 'Barra 316', perfil: 'redondo', diametro: '25mm' },
  { oc_id: 'oc2', material: 'AISI 316', cantidad: 50, cantidad_recibida: 30, precio_unitario: 14, unidad: 'mts', descripcion: 'Barra 316 fina', perfil: 'redondo', diametro: '12mm' },
  { oc_id: 'oc3', material: 'AISI 316', cantidad: 999, cantidad_recibida: 0, precio_unitario: 10 },  // borrador: no cuenta
  { oc_id: 'oc4', material: 'AISI 316', cantidad: 10, cantidad_recibida: 0, precio_unitario: 9 },    // anulada: no cuenta
  { oc_id: 'oc1', material: 'SAE 1045', cantidad: 40, cantidad_recibida: 0, precio_unitario: 5 },
];

test('enTransitoMaterial suma solo OC enviadas/confirmadas/parciales, neto de lo recibido', () => {
  const r = erp.run(`enTransitoMaterial('AISI 316',${JSON.stringify(ITEMS)},${JSON.stringify(OCS)})`);
  assert.strictEqual(r, 120); // 100 (oc1) + 20 pendientes (oc2); borrador y anulada afuera
});

test('enTransitoMaterial da cero sin OC abiertas del material', () => {
  assert.strictEqual(erp.run(`enTransitoMaterial('Inexistente',${JSON.stringify(ITEMS)},${JSON.stringify(OCS)})`), 0);
});

// ── ultimaCompraMaterial ──────────────────────────────────────────

test('ultimaCompraMaterial devuelve el ítem de la OC más reciente no anulada', () => {
  const r = erp.run(`ultimaCompraMaterial('AISI 316',${JSON.stringify(ITEMS)},${JSON.stringify(OCS)})`);
  assert.strictEqual(r.fecha, '2026-07-20');       // oc3 borrador cuenta como compra previa (referencia de precio)
  assert.strictEqual(r.proveedor_id, 'prov-a');
  assert.strictEqual(r.precio_unitario, 10);
});

test('ultimaCompraMaterial ignora anuladas y devuelve null sin historial', () => {
  const soloAnulada = JSON.stringify([{ oc_id: 'oc4', material: 'X', cantidad: 1, precio_unitario: 9 }]);
  assert.strictEqual(erp.run(`ultimaCompraMaterial('X',${soloAnulada},${JSON.stringify(OCS)})`), null);
});

// ── chequearCredito ───────────────────────────────────────────────

test('chequearCredito: dentro del límite y sin mora', () => {
  const r = erp.run(`chequearCredito(${JSON.stringify({ limite: 10000, saldo: 3000, vencido: 0, totalNuevo: 2000 })})`);
  assert.strictEqual(r.excedeLimite, false);
  assert.strictEqual(r.tieneMora, false);
  assert.strictEqual(r.disponible, 7000);
  assert.strictEqual(r.expuesto, 5000);
});

test('chequearCredito: excede límite y tiene mora', () => {
  const r = erp.run(`chequearCredito(${JSON.stringify({ limite: 5000, saldo: 4000, vencido: 1500, totalNuevo: 2000 })})`);
  assert.strictEqual(r.excedeLimite, true);
  assert.strictEqual(r.tieneMora, true);
  assert.strictEqual(r.expuesto, 6000);
});

test('chequearCredito: sin límite definido nunca excede (solo mora)', () => {
  const r = erp.run(`chequearCredito(${JSON.stringify({ limite: null, saldo: 99999, vencido: 200, totalNuevo: 99999 })})`);
  assert.strictEqual(r.excedeLimite, false);
  assert.strictEqual(r.disponible, null);
  assert.strictEqual(r.tieneMora, true);
});

// ── clientesInactivos ─────────────────────────────────────────────

const CLIENTES = [
  { id: 'c1', nombre: 'YPF', email: 'compras@ypf.com' },
  { id: 'c2', nombre: 'Minera Sur', email: null },
  { id: 'c3', nombre: 'Nuevo Prospecto', email: 'hola@nuevo.com' },
];
const VENTAS = [
  { cliente_id: 'c1', cliente: 'YPF', fecha: '2026-07-15', estado: 'entregado' },       // activo
  { cliente_id: 'c2', cliente: 'Minera Sur', fecha: '2026-03-01', estado: 'entregado' }, // 152 días al 2026-07-31
  { cliente_id: 'c2', cliente: 'Minera Sur', fecha: '2026-07-30', estado: 'anulada' },   // anulada no reactiva
];

test('clientesInactivos detecta 90+ días ignorando anuladas y prospectos sin ventas', () => {
  const r = erp.run(`clientesInactivos(${JSON.stringify(CLIENTES)},${JSON.stringify(VENTAS)},'2026-07-31')`);
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].id, 'c2');
  assert.strictEqual(r[0].ultimaVenta, '2026-03-01');
  assert.strictEqual(r[0].dias, 152);
});

test('clientesInactivos vacío cuando todos compraron hace poco', () => {
  const ventasFrescas = JSON.stringify([{ cliente_id: 'c1', fecha: '2026-07-01', estado: 'entregado' }]);
  const r = erp.run(`clientesInactivos(${JSON.stringify([CLIENTES[0]])},${ventasFrescas},'2026-07-31')`);
  assert.strictEqual(r.length, 0);
});
