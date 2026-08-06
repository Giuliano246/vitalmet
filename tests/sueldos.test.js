// Tests del módulo Sueldos (migración 065): pre-cálculo de renglones,
// totales de liquidación y cashflow proyectado con sueldos/F.931.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function item(bruto, noRem, pcts) {
  return erp.run(`computeItemLiquidacion(${bruto},${noRem},${JSON.stringify(pcts || {})})`);
}
function totales(items) {
  return erp.run(`computeTotalesLiquidacion(${JSON.stringify(items)})`);
}
function cashflow(data, hoy) {
  return erp.run(`computeCashflowProyectado(${JSON.stringify(data)},${JSON.stringify(hoy)})`);
}

test('computeItemLiquidacion: defaults 2026 (17% aportes, 27,35% contrib, 3% ART)', () => {
  const r = item(1000000, 0);
  assert.strictEqual(r.aportes, 170000);
  assert.strictEqual(r.neto, 830000);
  assert.strictEqual(r.contribuciones, 273500);
  assert.strictEqual(r.art, 30000);
});

test('computeItemLiquidacion: lo no remunerativo suma al neto pero no lleva cargas', () => {
  const r = item(1000000, 200000);
  assert.strictEqual(r.aportes, 170000);          // solo sobre el bruto
  assert.strictEqual(r.neto, 1030000);            // bruto + no_rem − aportes
  assert.strictEqual(r.contribuciones, 273500);   // solo sobre el bruto
});

test('computeItemLiquidacion: porcentajes custom y redondeo a 2 decimales', () => {
  const r = item(333333.33, 0, { aportesPct: 17, contribPct: 27.35, artPct: 3 });
  assert.strictEqual(r.aportes, 56666.67);
  assert.strictEqual(r.neto, 276666.66);
});

test('computeTotalesLiquidacion: cargas = aportes + contribuciones + ART; costo empresa', () => {
  const t = totales([
    { bruto: 1000000, no_remunerativo: 0, aportes: 170000, neto: 830000, contribuciones: 273500, art: 30000 },
    { bruto: 500000, no_remunerativo: 100000, aportes: 85000, neto: 515000, contribuciones: 136750, art: 15000 },
  ]);
  assert.strictEqual(t.bruto, 1500000);
  assert.strictEqual(t.neto, 1345000);
  assert.strictEqual(t.cargas, 170000 + 85000 + 273500 + 136750 + 30000 + 15000);
  assert.strictEqual(t.costoTotal, 1500000 + 100000 + 273500 + 136750 + 30000 + 15000);
  // Control contable: el asiento balancea ⇔ costo empresa = netos + F.931/ART
  // (debe: bruto+no_rem+contrib+art · haber: neto + aportes+contrib+art)
  assert.strictEqual(t.costoTotal, t.neto + t.cargas);
});

test('cashflow: netos a fecha de pago y F.931 el 9 del mes siguiente, en USD', () => {
  const cf = cashflow({
    liquidaciones: [{
      estado: 'confirmada', periodo: '2026-08-01', fecha_pago: '2026-09-01',
      neto: 1345000, aportes: 255000, contribuciones: 410250, art: 45000, tc: 1000,
    }],
  }, '2026-08-25');
  // Netos 01/09 (7 días → d30): 1.345.000 / 1000 = 1345 USD
  // F.931 09/09 (15 días → d30): 710.250 / 1000 = 710,25 USD
  assert.ok(Math.abs(cf.egr.d30 - (1345 + 710.25)) < 0.01);
  assert.strictEqual(cf.egr.vencido, 0);
});

test('cashflow: liquidaciones con fecha pasada o ya pagadas no suman', () => {
  const base = { estado: 'confirmada', periodo: '2026-05-01', fecha_pago: '2026-06-01',
                 neto: 100000, aportes: 0, contribuciones: 0, art: 0, tc: 1000 };
  // Fecha pasada → se asume pagada, no va ni a "vencido"
  const cf1 = cashflow({ liquidaciones: [base] }, '2026-08-25');
  assert.strictEqual(cf1.egr.vencido + cf1.egr.d30 + cf1.egr.d60 + cf1.egr.d90, 0);
  // Futura pero con pago registrado → tampoco
  const cf2 = cashflow({ liquidaciones: [{ ...base, fecha_pago: '2026-09-01', pagado_netos: true }] }, '2026-08-25');
  assert.strictEqual(cf2.egr.d30, 0);
});

test('cashflow: borradores no proyectan y sin TC no rompe (suma 0)', () => {
  const cf = cashflow({
    liquidaciones: [
      { estado: 'borrador', periodo: '2026-08-01', fecha_pago: '2026-09-01', neto: 999999, tc: 1000 },
      { estado: 'confirmada', periodo: '2026-08-01', fecha_pago: '2026-09-01', neto: 100000, aportes: 0, contribuciones: 0, art: 0, tc: 0 },
    ],
  }, '2026-08-25');
  assert.strictEqual(cf.egr.d30, 0);
});

test('cashflow: sin fecha_pago usa el fin del período', () => {
  const cf = cashflow({
    liquidaciones: [{ estado: 'confirmada', periodo: '2026-09-01',
      neto: 500000, aportes: 0, contribuciones: 0, art: 0, tc: 1000 }],
  }, '2026-08-25');
  // Fin de septiembre = 30/09 (36 días → d60) + F.931 09/10 (45 días → d60)
  assert.ok(Math.abs(cf.egr.d60 - 500) < 0.01);
});
