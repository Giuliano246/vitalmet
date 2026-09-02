// Tests del Sprint B "Ajuste por inflación con anticuación" (2026-09-02):
// computeAnticuacion reexpresa cada partida por su mes de origen (RT 54,
// Nota 1.3 del modelo EP), lleva el ajuste del Capital a Ajuste de capital
// y cierra contra RECPAM. Informe: docs/analisis/2026-09-02-auditoria-rt54.md
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const j = JSON.stringify;
const r2 = n => Math.round(n * 100) / 100;

const INDICES = [
  { anio: 2025, mes: 12, indice: 100 },
  { anio: 2026, mes: 1, indice: 110 },
  { anio: 2026, mes: 6, indice: 150 },
  { anio: 2026, mes: 12, indice: 200 },
];
const CUENTAS = [
  { id: 'maq', codigo: '122007', nombre: 'Maquinarias', tipo: 'activo', es_ajustable: true, imputable: true, activa: true, rubro_rt54: 'bienes_uso' },
  { id: 'cap', codigo: '310000', nombre: 'Capital suscripto', tipo: 'patrimonio', es_ajustable: false, imputable: true, activa: true, rubro_rt54: 'capital' },
  { id: 'ajcap', codigo: '312000', nombre: 'Ajuste de capital', tipo: 'patrimonio', es_ajustable: true, imputable: true, activa: true, rubro_rt54: 'ajuste_capital' },
  { id: 'ventas', codigo: '411001', nombre: 'Ventas', tipo: 'ingreso', es_ajustable: true, imputable: true, activa: true, rubro_rt54: 'ventas' },
  { id: 'caja', codigo: '111001', nombre: 'Caja', tipo: 'activo', es_ajustable: false, imputable: true, activa: true, rubro_rt54: 'caja_bancos' },
  { id: 'recpam', codigo: '412004', nombre: 'RECPAM', tipo: 'ingreso', es_ajustable: false, imputable: true, activa: true, rubro_rt54: 'rfyt' },
  { id: 'agr', codigo: '122000', nombre: 'Bienes de uso', tipo: 'activo', es_ajustable: true, imputable: false, activa: true },
];
const ASIENTOS = [
  { id: 'a0', estado: 'confirmado', fecha: '2025-12-31', moneda: 'ARS', origen_tipo: 'manual' },
  { id: 'a1', estado: 'confirmado', fecha: '2026-06-15', moneda: 'ARS', origen_tipo: 'manual' },
  { id: 'a2', estado: 'confirmado', fecha: '2026-12-10', moneda: 'USD', tipo_cambio: 10, origen_tipo: 'factura' },
  { id: 'a3', estado: 'borrador',   fecha: '2026-12-11', moneda: 'ARS', origen_tipo: 'manual' },
];
const LINEAS = [
  { asiento_id: 'a0', cuenta_id: 'maq', debe: 1000, haber: 0 },   // apertura dic-25 → coef 2,0
  { asiento_id: 'a0', cuenta_id: 'cap', debe: 0, haber: 1000 },
  { asiento_id: 'a1', cuenta_id: 'maq', debe: 500, haber: 0 },    // alta jun-26 → coef 200/150
  { asiento_id: 'a1', cuenta_id: 'caja', debe: 0, haber: 500 },
  { asiento_id: 'a2', cuenta_id: 'caja', debe: 30, haber: 0 },    // USD × 10 → 300 ARS en dic-26 → coef 1
  { asiento_id: 'a2', cuenta_id: 'ventas', debe: 0, haber: 30 },
  { asiento_id: 'a3', cuenta_id: 'maq', debe: 9999, haber: 0 },   // borrador: se ignora
];
const BASE = { lineas: LINEAS, asientos: ASIENTOS, cuentas: CUENTAS, indices: INDICES, hasta: '2026-12-31', recpamId: 'recpam', ajusteCapitalId: 'ajcap' };
const run = extra => erp.run(`computeAnticuacion(${j({ ...BASE, ...extra })})`);

test('computeAnticuacion: cada partida con el coeficiente de su mes; Capital → Ajuste de capital; RECPAM como contrapartida', () => {
  const r = run({});
  assert.strictEqual(r.error, undefined);
  assert.strictEqual(r.ipcCierre, 200);
  assert.strictEqual(r.fechaAsiento, '2026-12-31');
  const maq = r.filas.find(f => f.cuenta.id === 'maq');
  assert.strictEqual(maq.saldoHist, 1500);
  assert.strictEqual(maq.ajuste, r2(1000 * 1 + 500 * (200 / 150 - 1)));   // 1166,67
  assert.strictEqual(maq.saldoAjustado, r2(1500 + 1166.67));
  assert.strictEqual(maq.detalle.length, 2);
  const cap = r.filas.find(f => f.cuenta.id === 'cap');
  assert.strictEqual(cap.ajuste, -1000);                                 // saldo acreedor × (2 − 1)
  assert.strictEqual(cap.destino.id, 'ajcap');
  assert.strictEqual(r.filas.find(f => f.cuenta.id === 'ventas'), undefined); // coef 1 en el mes de cierre → sin ajuste
  assert.strictEqual(r.filas.find(f => f.cuenta.id === 'caja'), undefined);   // monetaria
  // Líneas: maq debe 1166,67 · ajcap haber 1000 · RECPAM haber 166,67 (ganancia por pasivo... no: por PN vs activo)
  const ls = r.lineas;
  assert.strictEqual(ls.find(l => l.cuenta_id === 'maq').debe, 1166.67);
  assert.strictEqual(ls.find(l => l.cuenta_id === 'ajcap').haber, 1000);
  assert.strictEqual(ls.find(l => l.cuenta_id === 'cap'), undefined);
  assert.strictEqual(r.recpamHaber, 166.67);
  assert.strictEqual(r.recpamDebe, 0);
  const td = ls.reduce((s, l) => s + l.debe, 0), th = ls.reduce((s, l) => s + l.haber, 0);
  assert.strictEqual(r2(td), r2(th));
});

test('computeAnticuacion: con un ajuste previo, lo anterior se reexpresa con un solo coeficiente desde esa fecha', () => {
  const asientos = ASIENTOS.concat([{ id: 'aj', estado: 'confirmado', fecha: '2026-06-30', moneda: 'ARS', origen_tipo: 'ajuste_inflacion' }]);
  const lineas = LINEAS.concat([
    { asiento_id: 'aj', cuenta_id: 'maq', debe: 700, haber: 0 },
    { asiento_id: 'aj', cuenta_id: 'ajcap', debe: 0, haber: 500 },
    { asiento_id: 'aj', cuenta_id: 'recpam', debe: 0, haber: 200 },
  ]);
  const r = run({ asientos, lineas });
  assert.strictEqual(r.ultimoAjuste.fecha, '2026-06-30');
  const maq = r.filas.find(f => f.cuenta.id === 'maq');
  assert.strictEqual(maq.saldoHist, 2200);
  assert.strictEqual(maq.detalle.length, 1);                              // un solo bucket: base jun-26
  assert.strictEqual(maq.ajuste, r2(2200 * (200 / 150 - 1)));             // 733,33
  const cap = r.filas.find(f => f.cuenta.id === 'cap');
  assert.strictEqual(cap.ajuste, r2(-1000 * (200 / 150 - 1)));
  const ajcap = r.filas.find(f => f.cuenta.id === 'ajcap');
  assert.strictEqual(ajcap.ajuste, r2(-500 * (200 / 150 - 1)));
  // Capital y Ajuste de capital se acumulan en una sola línea sobre 312000
  assert.strictEqual(r.lineas.filter(l => l.cuenta_id === 'ajcap').length, 1);
  assert.strictEqual(r.lineas.find(l => l.cuenta_id === 'ajcap').haber, r2(1500 * (200 / 150 - 1)));
});

test('computeAnticuacion: ignorarAjustes trata las líneas del ajuste previo como movimientos de su mes', () => {
  const asientos = ASIENTOS.concat([{ id: 'aj', estado: 'confirmado', fecha: '2026-06-30', moneda: 'ARS', origen_tipo: 'ajuste_inflacion' }]);
  const lineas = LINEAS.concat([{ asiento_id: 'aj', cuenta_id: 'maq', debe: 700, haber: 0 }]);
  const r = run({ asientos, lineas, ignorarAjustes: true });
  assert.strictEqual(r.ultimoAjuste, null);
  const maq = r.filas.find(f => f.cuenta.id === 'maq');
  assert.strictEqual(maq.ajuste, r2(1000 * 1 + 1200 * (200 / 150 - 1)));
});

test('computeAnticuacion: un mes sin índice usa el anterior más cercano y avisa', () => {
  const asientos = ASIENTOS.concat([{ id: 'a5', estado: 'confirmado', fecha: '2026-03-20', moneda: 'ARS', origen_tipo: 'manual' }]);
  const lineas = LINEAS.concat([{ asiento_id: 'a5', cuenta_id: 'maq', debe: 110, haber: 0 }, { asiento_id: 'a5', cuenta_id: 'caja', debe: 0, haber: 110 }]);
  const r = run({ asientos, lineas });
  const maq = r.filas.find(f => f.cuenta.id === 'maq');
  const mar = maq.detalle.find(d => d.mes === '2026-03');
  assert.strictEqual(mar.coef, Math.round(200 / 110 * 1e6) / 1e6);            // usa ene-26
  assert.ok(r.mesesSinIndice.includes('2026-03'));
  assert.ok(r.advertencias.some(a => /2026-03/.test(a)));
});

test('computeAnticuacion: errores y advertencias', () => {
  assert.match(run({ hasta: '2027-03-31' }).error, /IPC/);
  assert.match(run({ indices: [] }).error, /IPC/);
  assert.match(run({ recpamId: null }).error, /RECPAM/);
  const asientos = ASIENTOS.concat([{ id: 'ref', estado: 'confirmado', fecha: '2026-12-31', moneda: 'ARS', tipo: 'auto-cierre-resultados', origen_tipo: 'cierre_ejercicio' }]);
  const r = run({ asientos });
  assert.ok(r.advertencias.some(a => /refundici/i.test(a)));
  const sinAjCap = run({ ajusteCapitalId: null });
  assert.strictEqual(sinAjCap.filas.find(f => f.cuenta.id === 'cap').destino.id, 'cap');
  assert.ok(sinAjCap.advertencias.some(a => /Ajuste de capital/.test(a)));
});

test('ipcMasCercano: exacto, anterior más cercano, o el primero si no hay anterior', () => {
  const m = { '2026-01': 110, '2026-06': 150 };
  assert.strictEqual(erp.run(`ipcMasCercano(${j(m)}, '2026-06').indice`), 150);
  const r = erp.run(`ipcMasCercano(${j(m)}, '2026-04')`);
  assert.strictEqual(r.indice, 110); assert.strictEqual(r.mesUsado, '2026-01');
  assert.strictEqual(erp.run(`ipcMasCercano(${j(m)}, '2025-03').mesUsado`), '2026-01');
  assert.strictEqual(erp.run(`ipcMasCercano({}, '2025-03')`), null);
});
