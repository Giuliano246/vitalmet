// Tests del Sprint C "Bienes de uso" (2026-09-02): depreciación lineal
// por meses y anexo Bienes de uso del modelo RT 54 (valores de origen,
// altas, bajas, depreciación del ejercicio y acumulada).
// Informe: docs/analisis/2026-09-02-auditoria-rt54.md (M-03)
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const j = JSON.stringify;

const TORNO = { id: 't1', nro: 'BU-0001', nombre: 'Torno CNC', rubro: 'maquinarias', fecha_alta: '2025-03-15', valor_origen: 12000000, valor_residual: 0, vida_util_meses: 120, estado: 'activo', fecha_baja: null };

test('computeDepreciacion: lineal por meses, mes de alta completo, primer ejercicio', () => {
  // Ejercicio 2025: de marzo a diciembre = 10 meses × (12.000.000 / 120 = 100.000)
  const r = erp.run(`computeDepreciacion(${j(TORNO)}, '2025-01-01', '2025-12-31', [])`);
  assert.strictEqual(r.cuota, 100000);
  assert.strictEqual(r.meses, 10);
  assert.strictEqual(r.importe, 1000000);
  assert.strictEqual(r.acumPrevio, 0);
  assert.strictEqual(r.acumPosterior, 1000000);
  assert.strictEqual(r.valorNeto, 11000000);
});

test('computeDepreciacion: segundo ejercicio completo descuenta lo ya depreciado y no pasa la vida útil', () => {
  const previas = [{ bien_id: 't1', hasta: '2025-12-31', meses: 10, importe: 1000000 }];
  const r = erp.run(`computeDepreciacion(${j(TORNO)}, '2026-01-01', '2026-12-31', ${j(previas)})`);
  assert.strictEqual(r.meses, 12);
  assert.strictEqual(r.importe, 1200000);
  assert.strictEqual(r.acumPrevio, 1000000);
  // Bien casi agotado: quedan 3 meses de vida
  const casi = [{ bien_id: 't1', hasta: '2034-12-31', meses: 117, importe: 11700000 }];
  const r2 = erp.run(`computeDepreciacion(${j(TORNO)}, '2035-01-01', '2035-12-31', ${j(casi)})`);
  assert.strictEqual(r2.meses, 3);
  assert.strictEqual(r2.importe, 300000);
  assert.strictEqual(r2.valorNeto, 0);
});

test('computeDepreciacion: valor residual, baja a mitad de ejercicio, alta posterior al cierre, terreno', () => {
  const auto = { ...TORNO, id: 'a1', rubro: 'rodados', fecha_alta: '2024-01-10', valor_origen: 6000000, valor_residual: 600000, vida_util_meses: 60, fecha_baja: '2026-05-20', estado: 'baja' };
  const previas = [{ bien_id: 'a1', hasta: '2025-12-31', meses: 24, importe: 2160000 }];
  const r = erp.run(`computeDepreciacion(${j(auto)}, '2026-01-01', '2026-12-31', ${j(previas)})`);
  assert.strictEqual(r.cuota, 90000);          // (6.000.000 − 600.000) / 60
  assert.strictEqual(r.meses, 5);              // enero a mayo (mes de baja incluido)
  assert.strictEqual(r.importe, 450000);
  const futuro = erp.run(`computeDepreciacion(${j({ ...TORNO, fecha_alta: '2027-02-01' })}, '2026-01-01', '2026-12-31', [])`);
  assert.strictEqual(futuro.meses, 0);
  assert.strictEqual(futuro.importe, 0);
  const terreno = erp.run(`computeDepreciacion(${j({ ...TORNO, rubro: 'terrenos', vida_util_meses: 0 })}, '2026-01-01', '2026-12-31', [])`);
  assert.strictEqual(terreno.importe, 0);
});

test('computeDepreciacion: redondeo — el último tramo cierra exacto contra el valor amortizable', () => {
  const b = { ...TORNO, valor_origen: 1000, vida_util_meses: 36 };   // cuota 27,78
  const previas = [{ bien_id: 't1', hasta: '2027-12-31', meses: 34, importe: 944.44 }];
  const r = erp.run(`computeDepreciacion(${j(b)}, '2028-01-01', '2028-12-31', ${j(previas)})`);
  assert.strictEqual(r.meses, 2);
  assert.strictEqual(r.importe, 55.56);        // 1000 − 944,44, no 2 × 27,78 = 55,56 (coincide) → neto 0
  assert.strictEqual(r.valorNeto, 0);
});

test('computeAnexoBienesUso: inicio, altas, bajas, depreciación del ejercicio y acumulada por rubro', () => {
  const bienes = [
    TORNO,                                                                                                       // alta 2025, sigue
    { ...TORNO, id: 'f1', nro: 'BU-0002', nombre: 'Fresadora', fecha_alta: '2026-04-01', valor_origen: 5000000 }, // alta del ejercicio
    { ...TORNO, id: 'a1', nro: 'BU-0003', nombre: 'Camioneta', rubro: 'rodados', fecha_alta: '2024-01-10', valor_origen: 6000000, valor_residual: 600000, vida_util_meses: 60, fecha_baja: '2026-05-20', estado: 'baja' },
  ];
  const deprecs = [
    { bien_id: 't1', hasta: '2025-12-31', meses: 10, importe: 1000000 },
    { bien_id: 'a1', hasta: '2025-12-31', meses: 24, importe: 2160000 },
    { bien_id: 't1', hasta: '2026-12-31', meses: 12, importe: 1200000 },
    { bien_id: 'f1', hasta: '2026-12-31', meses: 9, importe: 375000 },
    { bien_id: 'a1', hasta: '2026-12-31', meses: 5, importe: 450000 },
  ];
  const r = erp.run(`computeAnexoBienesUso(${j(bienes)}, ${j(deprecs)}, '2026-01-01', '2026-12-31')`);
  const maq = r.filas.find(f => f.rubro === 'maquinarias');
  assert.strictEqual(maq.valorInicio, 12000000);
  assert.strictEqual(maq.altas, 5000000);
  assert.strictEqual(maq.bajas, 0);
  assert.strictEqual(maq.valorCierre, 17000000);
  assert.strictEqual(maq.amortInicio, 1000000);
  assert.strictEqual(maq.amortEjercicio, 1575000);
  assert.strictEqual(maq.amortCierre, 2575000);
  assert.strictEqual(maq.netoCierre, 14425000);
  assert.strictEqual(maq.netoInicio, 11000000);
  const rod = r.filas.find(f => f.rubro === 'rodados');
  assert.strictEqual(rod.valorInicio, 6000000);
  assert.strictEqual(rod.bajas, 6000000);
  assert.strictEqual(rod.valorCierre, 0);
  assert.strictEqual(rod.amortInicio, 2160000);
  assert.strictEqual(rod.amortEjercicio, 450000);
  assert.strictEqual(rod.amortBajas, 2610000);
  assert.strictEqual(rod.amortCierre, 0);
  assert.strictEqual(rod.netoCierre, 0);
  assert.strictEqual(r.total.valorCierre, 17000000);
  assert.strictEqual(r.total.amortEjercicio, 2025000);
  assert.strictEqual(r.total.netoCierre, 14425000);
});
