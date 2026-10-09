// Tests de la liquidación mensual de IVA: saldo técnico con arrastre,
// ingresos directos (percepciones y retenciones) con saldo de libre
// disponibilidad, y el asiento que cierra las cuentas del mes.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;
const liq = a => JSON.parse(erp.run(`JSON.stringify(computeLiquidacionIva(${J(a)}))`));
const CTAS = { debito: 'D', credito: 'C', saldoFavor: 'SF', percep: 'P', ret: 'R', aPagar: 'AP' };
const asiento = l => JSON.parse(erp.run(`JSON.stringify(armarAsientoLiquidacionIva(${J(l)},${J(CTAS)}))`));
const cuadra = ls => Math.abs(ls.reduce((s, x) => s + x.debe - x.haber, 0)) < 0.005;
const por = ls => Object.fromEntries(ls.map(x => [x.cuenta_id, x.debe - x.haber]));

test('mes a pagar: débito − crédito − saldo técnico anterior, menos percepciones y retenciones', () => {
  const r = liq({ df: 1000000, cf: 600000, stAnterior: 50000, percep: 20000, ret: 30000, sldPercepAnt: 5000, sldRetAnt: 0 });
  assert.deepStrictEqual([r.tecnicoMes, r.tecnico, r.stCierre, r.aPagarBruto], [400000, 350000, 0, 350000]);
  assert.deepStrictEqual([r.usaPercep, r.usaRet, r.aPagar, r.sldPercep, r.sldRet], [25000, 30000, 295000, 0, 0]);
  const ls = asiento(r);
  assert.ok(cuadra(ls));
  assert.deepStrictEqual(por(ls), { D: 1000000, C: -600000, SF: -50000, P: -25000, R: -30000, AP: -295000 });
});

test('mes con saldo técnico a favor: se acumula y los ingresos directos quedan de libre disponibilidad', () => {
  const r = liq({ df: 300000, cf: 500000, stAnterior: 40000, percep: 10000, ret: 0, sldPercepAnt: 0, sldRetAnt: 7000 });
  assert.deepStrictEqual([r.tecnico, r.stCierre, r.aPagar, r.sldPercep, r.sldRet], [-240000, 240000, 0, 10000, 7000]);
  const ls = asiento(r);
  assert.ok(cuadra(ls));
  assert.deepStrictEqual(por(ls), { D: 300000, C: -500000, SF: 200000 }); // percepciones y retenciones no se tocan
});

test('los ingresos directos cubren todo: no hay pago y sobra libre disponibilidad (percepciones primero)', () => {
  const r = liq({ df: 100000, cf: 60000, stAnterior: 0, percep: 30000, ret: 25000, sldPercepAnt: 0, sldRetAnt: 0 });
  assert.deepStrictEqual([r.aPagarBruto, r.usaPercep, r.usaRet, r.aPagar, r.sldPercep, r.sldRet], [40000, 30000, 10000, 0, 0, 15000]);
  assert.ok(cuadra(asiento(r)));
});

test('mes con más notas de crédito que ventas (débito negativo) y sin movimientos', () => {
  const r = liq({ df: -20000, cf: 10000, stAnterior: 0, percep: 0, ret: 0 });
  assert.strictEqual(r.stCierre, 30000);
  const ls = asiento(r);
  assert.ok(cuadra(ls) && ls.every(x => x.debe >= 0 && x.haber >= 0));
  assert.deepStrictEqual(asiento(liq({ df: 0, cf: 0 })), []);
});

test('saldoCuentaHasta: saldo deudor de una cuenta con asientos confirmados hasta una fecha', () => {
  const asientos = [{ id: 'a1', fecha: '2026-08-31', estado: 'confirmado' }, { id: 'a2', fecha: '2026-09-10', estado: 'confirmado' }, { id: 'a3', fecha: '2026-08-15', estado: 'borrador' }];
  const lineas = [{ asiento_id: 'a1', cuenta_id: 'P', debe: 100, haber: 0 }, { asiento_id: 'a1', cuenta_id: 'P', debe: 0, haber: 30 }, { asiento_id: 'a2', cuenta_id: 'P', debe: 50, haber: 0 }, { asiento_id: 'a3', cuenta_id: 'P', debe: 999, haber: 0 }];
  assert.strictEqual(erp.run(`saldoCuentaHasta('P','2026-08-31',${J(lineas)},${J(asientos)})`), 70);
  assert.strictEqual(erp.run(`saldoCuentaHasta('P','2026-09-30',${J(lineas)},${J(asientos)},'2026-09-01')`), 50);
});
