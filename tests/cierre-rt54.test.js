// Tests del Sprint A "Cierre RT 54 mínimo" (2026-09-02): las cinco
// funciones puras que arman los asientos de ajuste previos a la
// refundición de resultados (IIGG, previsión incobrables, provisiones
// laborales, diferencia de cambio, variación de existencias).
// Informe: docs/analisis/2026-09-02-auditoria-rt54.md
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const CFG = {
  cta_iigg: 'iigg', cta_iigg_a_pagar: 'iigg_pagar',
  cta_prev_incobrables: 'prev', cta_gasto_incobrables: 'incob',
  cta_sueldos_fab: 'sfab', cta_sueldos_adm: 'sadm', cta_cargas_fab: 'cfab', cta_cargas_adm: 'cadm',
  cta_prov_vacaciones: 'vac', cta_provision_sac: 'sac',
  cta_dif_cambio: 'difc',
  cta_cmv: 'cmv', cta_stock_mp: 'mp', cta_stock_pt: 'pt', cta_stock_insumos: 'ins',
};
const j = JSON.stringify;
const sumDebe = ls => ls.reduce((s, l) => s + l.debe, 0);
const sumHaber = ls => ls.reduce((s, l) => s + l.haber, 0);
// Los arrays vienen del contexto vm (otro realm): deepStrictEqual falla por prototipo → comparar por JSON.
const dhl = ls => JSON.stringify(ls.map(l => [l.cuenta_id, l.debe, l.haber]));
const same = (a, b) => assert.strictEqual(dhl(a), JSON.stringify(b));

// ── computeAsientoIIGG ────────────────────────────────────────────

test('computeAsientoIIGG: gasto al debe, pasivo al haber', () => {
  const r = erp.run(`computeAsientoIIGG(1500000, ${j(CFG)})`);
  assert.strictEqual(r.error, undefined);
  assert.strictEqual(r.lineas.length, 2);
  same(r.lineas, [['iigg', 1500000, 0], ['iigg_pagar', 0, 1500000]]);
});

test('computeAsientoIIGG: importe cero o config incompleta no genera líneas', () => {
  assert.strictEqual(erp.run(`computeAsientoIIGG(0, ${j(CFG)})`).lineas.length, 0);
  const r = erp.run(`computeAsientoIIGG(100, ${j({ cta_iigg: 'iigg' })})`);
  assert.strictEqual(r.lineas.length, 0);
  assert.match(r.error, /imputaci/i);
});

// ── computePrevisionIncobrables ───────────────────────────────────

const CTACTE = [
  { nombre: 'YPF', buckets: { alDia: 1000, d30: 0, d60: 200, d90: 0, mas90: 100 } },
  { nombre: 'Pan American', buckets: { alDia: 0, d30: 500, d60: 0, d90: 300, mas90: 0 } },
];
const PCTS = { d30: 10, d60: 25, d90: 50, mas90: 100 };

test('computePrevisionIncobrables: objetivo por tramos × TC, ajuste = objetivo − saldo actual', () => {
  // base ARS (TC 1000): d30 500k → 50k; d60 200k → 50k; d90 300k → 150k; mas90 100k → 100k = 350k
  const r = erp.run(`computePrevisionIncobrables(${j(CTACTE)}, ${j(PCTS)}, 1000, 100000, ${j(CFG)})`);
  assert.strictEqual(r.base.alDia, 1000000);
  assert.strictEqual(r.base.mas90, 100000);
  assert.strictEqual(r.objetivo, 350000);
  assert.strictEqual(r.ajuste, 250000);
  same(r.lineas, [['incob', 250000, 0], ['prev', 0, 250000]]);
});

test('computePrevisionIncobrables: si el saldo actual supera el objetivo, revierte (previsión al debe)', () => {
  const r = erp.run(`computePrevisionIncobrables(${j(CTACTE)}, ${j(PCTS)}, 1000, 400000, ${j(CFG)})`);
  assert.strictEqual(r.ajuste, -50000);
  same(r.lineas, [['prev', 50000, 0], ['incob', 0, 50000]]);
});

test('computePrevisionIncobrables: sin diferencia → sin líneas', () => {
  const r = erp.run(`computePrevisionIncobrables(${j(CTACTE)}, ${j(PCTS)}, 1000, 350000, ${j(CFG)})`);
  assert.strictEqual(r.lineas.length, 0);
});

// ── computeProvisionLaboral ───────────────────────────────────────

test('computeProvisionLaboral: vacaciones por centro + cargas s/SAC prorrateadas por gasto', () => {
  const r = erp.run(`computeProvisionLaboral(${j({ vacFab: 300000, vacAdm: 100000, saldoSac: 1000000, pctCargas: 27.35, gastoFab: 3000000, gastoAdm: 1000000 })}, ${j(CFG)})`);
  assert.strictEqual(r.cargasSac, 273500);
  assert.strictEqual(r.cargasFab, 205125);   // 75 %
  assert.strictEqual(r.cargasAdm, 68375);    // 25 %
  assert.strictEqual(r.total, 673500);
  assert.strictEqual(Math.round(sumDebe(r.lineas) * 100) / 100, Math.round(sumHaber(r.lineas) * 100) / 100);
  const haber = r.lineas.filter(l => l.haber > 0);
  assert.strictEqual(haber.length, 1);
  assert.strictEqual(haber[0].cuenta_id, 'vac');
  assert.strictEqual(haber[0].haber, 673500);
});

test('computeProvisionLaboral: sin gasto de sueldos reparte cargas 50/50; todo cero → sin líneas', () => {
  const r = erp.run(`computeProvisionLaboral(${j({ vacFab: 0, vacAdm: 0, saldoSac: 200000, pctCargas: 20, gastoFab: 0, gastoAdm: 0 })}, ${j(CFG)})`);
  assert.strictEqual(r.cargasFab, 20000);
  assert.strictEqual(r.cargasAdm, 20000);
  const z = erp.run(`computeProvisionLaboral(${j({ vacFab: 0, vacAdm: 0, saldoSac: 0, pctCargas: 20, gastoFab: 0, gastoAdm: 0 })}, ${j(CFG)})`);
  assert.strictEqual(z.lineas.length, 0);
});

// ── computeDiferenciaCambio ───────────────────────────────────────

const CUENTAS = [
  { id: 'prov', codigo: '211002', nombre: 'Proveedores', tipo: 'pasivo', es_ajustable: false, imputable: true, activa: true },
  { id: 'caja_usd', codigo: '111002', nombre: 'Caja USD', tipo: 'activo', es_ajustable: false, imputable: true, activa: true },
  { id: 'maq', codigo: '122007', nombre: 'Maquinarias', tipo: 'activo', es_ajustable: true, imputable: true, activa: true },
  { id: 'difc', codigo: '424006', nombre: 'Dif. de cambio', tipo: 'egreso', es_ajustable: true, imputable: true, activa: true },
];
const ASIENTOS = [
  { id: 'a1', estado: 'confirmado', fecha: '2026-03-10', moneda: 'USD', tipo_cambio: 1000 },
  { id: 'a2', estado: 'confirmado', fecha: '2026-06-10', moneda: 'USD', tipo_cambio: 1200 },
  { id: 'a3', estado: 'confirmado', fecha: '2026-06-15', moneda: 'ARS', tipo_cambio: null },
  { id: 'a4', estado: 'borrador',   fecha: '2026-06-20', moneda: 'USD', tipo_cambio: 1300 },
];
const LINEAS = [
  { asiento_id: 'a1', cuenta_id: 'prov', debe: 0, haber: 100 },      // deuda 100 USD a 1000 → 100.000
  { asiento_id: 'a1', cuenta_id: 'maq', debe: 100, haber: 0 },       // bien de uso: no monetario, se ignora
  { asiento_id: 'a2', cuenta_id: 'prov', debe: 40, haber: 0 },       // pago 40 USD a 1200 → 48.000
  { asiento_id: 'a2', cuenta_id: 'caja_usd', debe: 0, haber: 40 },
  { asiento_id: 'a2', cuenta_id: 'caja_usd', debe: 60, haber: 0 },   // caja USD queda +20 USD contabilizados a 1200 → 24.000
  { asiento_id: 'a3', cuenta_id: 'prov', debe: 0, haber: 500000 },   // ARS: no entra en la exposición
  { asiento_id: 'a4', cuenta_id: 'prov', debe: 0, haber: 999 },      // borrador: se ignora
];

test('computeDiferenciaCambio: solo monetarias con líneas en USD, al TC de cierre', () => {
  const r = erp.run(`computeDiferenciaCambio(${j(LINEAS)}, ${j(ASIENTOS)}, ${j(CUENTAS)}, 1500, ${j(CFG)})`);
  const prov = r.filas.find(f => f.cuenta.id === 'prov');
  // Proveedores: −100 + 40 = −60 USD; contable = −100.000 + 48.000 = −52.000; cierre = −90.000; dif = −38.000 (más pasivo → pérdida)
  assert.strictEqual(prov.saldoUsd, -60);
  assert.strictEqual(prov.arsContable, -52000);
  assert.strictEqual(prov.arsCierre, -90000);
  assert.strictEqual(prov.dif, -38000);
  const caja = r.filas.find(f => f.cuenta.id === 'caja_usd');
  // Caja USD: +20 USD; contable 24.000; cierre 30.000; dif +6.000 (ganancia)
  assert.strictEqual(caja.dif, 6000);
  assert.strictEqual(r.filas.find(f => f.cuenta.id === 'maq'), undefined);
  assert.strictEqual(r.total, -32000);
  // Líneas: proveedores al haber 38.000, caja al debe 6.000, dif. de cambio al debe 32.000 neto
  assert.strictEqual(Math.round(sumDebe(r.lineas)), Math.round(sumHaber(r.lineas)));
  const dc = r.lineas.find(l => l.cuenta_id === 'difc');
  assert.strictEqual(dc.debe, 32000);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'prov').haber, 38000);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'caja_usd').debe, 6000);
});

test('computeDiferenciaCambio: sin TC o sin cuenta de diferencia → error', () => {
  assert.match(erp.run(`computeDiferenciaCambio([], [], [], 0, ${j(CFG)})`).error, /tipo de cambio/i);
  assert.match(erp.run(`computeDiferenciaCambio([], [], [], 1500, {})`).error, /imputaci/i);
});

// ── computeVariacionExistencias ───────────────────────────────────

test('computeVariacionExistencias: saldo contable − existencia final → CMV', () => {
  const saldos = { mp: { debe: 5000000, haber: 1000000 }, pt: { debe: 800000, haber: 0 }, ins: { debe: 300000, haber: 0 } };
  const r = erp.run(`computeVariacionExistencias(${j(saldos)}, ${j({ mp: 2500000, pt: 1000000, insumos: 300000 })}, ${j(CFG)})`);
  const mp = r.filas.find(f => f.cuenta_id === 'mp');
  assert.strictEqual(mp.saldoContable, 4000000);
  assert.strictEqual(mp.variacion, 1500000);        // consumido → CMV
  const pt = r.filas.find(f => f.cuenta_id === 'pt');
  assert.strictEqual(pt.variacion, -200000);        // creció el stock de PT → menos CMV
  assert.strictEqual(r.cmv, 1300000);
  assert.strictEqual(Math.round(sumDebe(r.lineas)), Math.round(sumHaber(r.lineas)));
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'cmv').debe, 1300000);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'mp').haber, 1500000);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'pt').debe, 200000);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'ins'), undefined); // sin variación: sin línea
});

test('computeVariacionExistencias: sin cuenta CMV → error', () => {
  assert.match(erp.run(`computeVariacionExistencias({}, {mp:0,pt:0,insumos:0}, {})`).error, /imputaci/i);
});
