// Tests de la remediación H-01 (auditoría externa 2026-08, mig 070):
// armarAsientoRecepcion — el armado puro del asiento GR/IR que la RPC
// registrar_recepcion_oc crea dentro de su transacción.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const CFG = {
  cta_gr_ir: 'grir', cta_compra_mp: 'mp', cta_compra_insumos: 'ins',
  cta_compra_herramientas: 'herr', cta_compra_servicios: 'srv',
  iva_alicuota: 0.21, precios_incluyen_iva: false,
};
const CUENTAS = [{ id: 'grir', codigo: '211002', nombre: 'GR/IR' }];
const OC = { id: 'oc1', nro: 'OC-0042', moneda: 'USD', tipo_cambio: null, tc_tipo: null, proveedores: { nombre: 'ACINDAR' } };

function armar(items, oc = OC, cfg = CFG) {
  return erp.run(`armarAsientoRecepcion(${JSON.stringify(items)},${JSON.stringify(oc)},'2026-08-21',${JSON.stringify(cfg)},${JSON.stringify(CUENTAS)})`);
}

test('recepción de MP: debe cuenta de compra, haber GR/IR, balanceado', () => {
  const r = armar([{ qty: 10, it: { tipo: 'materia_prima', precio_unitario: '25.5' } }]);
  assert.ok(r);
  assert.strictEqual(r.lineas.length, 2);
  assert.strictEqual(r.lineas[0].cuenta_id, 'mp');
  assert.strictEqual(r.lineas[0].debe, 255);
  assert.strictEqual(r.lineas[1].cuenta_id, 'grir');
  assert.strictEqual(r.lineas[1].haber, 255);
  assert.strictEqual(r.cabecera.tipo, 'auto-compra');
  assert.strictEqual(r.cabecera.origen_tipo, 'recepcion');
  assert.strictEqual(r.cabecera.estado, 'confirmado');
  assert.ok(r.cabecera.descripcion.includes('OC-0042'));
  assert.ok(r.cabecera.descripcion.includes('ACINDAR'));
});

test('tipos mezclados agrupan por cuenta y el haber GR/IR es la suma', () => {
  const r = armar([
    { qty: 2, it: { tipo: 'materia_prima', precio_unitario: '100' } },
    { qty: 3, it: { tipo: 'materia_prima', precio_unitario: '50' } },
    { qty: 1, it: { tipo: 'insumo', precio_unitario: '80' } },
  ]);
  assert.strictEqual(r.lineas.length, 3); // mp (agrupada) + insumos + GR/IR
  const mp = r.lineas.find(l => l.cuenta_id === 'mp');
  const ins = r.lineas.find(l => l.cuenta_id === 'ins');
  const grir = r.lineas.find(l => l.cuenta_id === 'grir');
  assert.strictEqual(mp.debe, 350);
  assert.strictEqual(ins.debe, 80);
  assert.strictEqual(grir.haber, 430);
  const debe = r.lineas.reduce((a, l) => a + l.debe, 0);
  const haber = r.lineas.reduce((a, l) => a + l.haber, 0);
  assert.ok(Math.abs(debe - haber) < 0.01);
});

test('precios_incluyen_iva descuenta el IVA del neto', () => {
  const r = armar([{ qty: 1, it: { tipo: 'materia_prima', precio_unitario: '121' } }],
    OC, { ...CFG, precios_incluyen_iva: true });
  assert.ok(Math.abs(r.lineas[0].debe - 100) < 0.01);
  assert.ok(Math.abs(r.lineas[1].haber - 100) < 0.01);
});

test('sin cta_gr_ir o sin config → null (recepción sin asiento, como siempre)', () => {
  assert.strictEqual(armar([{ qty: 1, it: { tipo: 'materia_prima', precio_unitario: '10' } }], OC, { ...CFG, cta_gr_ir: null }), null);
  assert.strictEqual(armar([{ qty: 1, it: { tipo: 'materia_prima', precio_unitario: '10' } }], OC, null), null);
});

test('monto total 0 (ítems sin precio) → null', () => {
  assert.strictEqual(armar([{ qty: 5, it: { tipo: 'materia_prima', precio_unitario: '0' } }]), null);
});

test('tipo sin cuenta mapeada se saltea sin romper el balanceo', () => {
  const r = armar([
    { qty: 1, it: { tipo: 'materia_prima', precio_unitario: '100' } },
    { qty: 1, it: { tipo: 'otro_tipo', precio_unitario: '999' } },
  ]);
  assert.strictEqual(r.lineas.length, 2);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'grir').haber, 100);
});

test('la cabecera hereda moneda y TC de la OC (origen_id queda para la RPC)', () => {
  const r = armar([{ qty: 1, it: { tipo: 'materia_prima', precio_unitario: '10' } }],
    { ...OC, moneda: 'ARS', tipo_cambio: 1300, tc_tipo: 'oficial' });
  assert.strictEqual(r.cabecera.moneda, 'ARS');
  assert.strictEqual(r.cabecera.tipo_cambio, 1300);
  assert.strictEqual(r.cabecera.tc_tipo, 'oficial');
  assert.strictEqual(r.cabecera.origen_id, null);
});
