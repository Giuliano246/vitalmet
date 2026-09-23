'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;

test('antiguedadEntre: años/meses/días con el último día inclusive (recibo: 27/04/2026 → 15/09/2026 = 0a 4m 20d)', () => {
  assert.deepEqual(JSON.parse(JSON.stringify(run(`antiguedadEntre('2026-04-27','2026-09-15')`))), { anios: 0, meses: 4, dias: 20, texto: '0a 4m 20d' });
  assert.deepEqual(JSON.parse(JSON.stringify(run(`antiguedadEntre('2023-03-10','2026-09-30')`))), { anios: 3, meses: 6, dias: 21, texto: '3a 6m 21d' });
  assert.equal(run(`antiguedadEntre(null,'2026-09-30')`).anios, 0);
});
test('diasVacacionesLCT: <6 meses 1 cada 20 trabajados; 14/21/28/35', () => {
  assert.equal(run(`diasVacacionesLCT(0, 100)`), 5);
  assert.equal(run(`diasVacacionesLCT(0, 365)`), 14);   // ≥ 6 meses en el año → 14
  assert.equal(run(`diasVacacionesLCT(5, 365)`), 14);
  assert.equal(run(`diasVacacionesLCT(6, 365)`), 21);
  assert.equal(run(`diasVacacionesLCT(11, 365)`), 28);
  assert.equal(run(`diasVacacionesLCT(21, 365)`), 35);
});
test('vigenteA: mayor vigencia ≤ fecha, null si ninguna', () => {
  const l = [{ vigencia_desde: '2026-08-01', v: 'a' }, { vigencia_desde: '2026-10-01', v: 'b' }, { vigencia_desde: '2026-12-01', v: 'c' }];
  assert.equal(run(`vigenteA(${J(l)},'2026-09-30').v`), 'a');
  assert.equal(run(`vigenteA(${J(l)},'2026-10-01').v`), 'b');
  assert.equal(run(`vigenteA(${J(l)},'2026-07-31')`), null);
});
test('numeroALetras: recibo real y casos borde', () => {
  assert.equal(run(`numeroALetras(395310)`), 'TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ');
  assert.equal(run(`numeroALetras(0)`), 'CERO');
  assert.equal(run(`numeroALetras(21)`), 'VEINTIUNO');
  assert.equal(run(`numeroALetras(100)`), 'CIEN');
  assert.equal(run(`numeroALetras(1000000)`), 'UN MILLON');
  assert.equal(run(`numeroALetras(2500116)`), 'DOS MILLONES QUINIENTOS MIL CIENTO DIECISEIS');
});
test('diasPeriodo / finPeriodo', () => {
  assert.equal(run(`diasPeriodo('quincena1')`), 15); assert.equal(run(`diasPeriodo('mensual')`), 30);
  assert.equal(run(`finPeriodo('2026-09-01','quincena1')`), '2026-09-15');
  assert.equal(run(`finPeriodo('2026-09-01','quincena2')`), '2026-09-30');
  assert.equal(run(`finPeriodo('2026-02-01','mensual')`), '2026-02-28');
});
