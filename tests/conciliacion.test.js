'use strict';
const test = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();
const run = (code) => erp.run(code);

test('parsearExtractoPegado: tab-separated con fecha dd/mm/yyyy y monto AR', () => {
  const txt = '01/06/2026\tTransferencia recibida\t1.234,56\n02/06/2026\tComisión mantenimiento\t-500,00';
  const r = run(`parsearExtractoPegado(${JSON.stringify(txt)})`);
  assert.strictEqual(r.length, 2);
  assert.strictEqual(r[0].fecha, '2026-06-01');
  assert.strictEqual(r[0].importe, 1234.56);
  assert.strictEqual(r[1].importe, -500);
  assert.strictEqual(r[1].descripcion, 'Comisión mantenimiento');
});
test('parsearExtractoPegado: ignora líneas vacías y sin importe', () => {
  const txt = '\n01/06/2026\tAlgo\t100,00\n   \n';
  const r = run(`parsearExtractoPegado(${JSON.stringify(txt)})`);
  assert.strictEqual(r.length, 1);
});
test('parsearExtractoPegado: importe cero se parsea (el guard vive en crearAsientoDesdeExtracto)', () => {
  const r = run(`parsearExtractoPegado("01/06/2026\\tReverso\\t0,00")`);
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].importe, 0);
});
test('sugerirMatchExtracto: matchea por importe (debe-haber) y fecha dentro de ventana', () => {
  const linea = { fecha:'2026-06-03', importe:1000 };
  const movs = [
    { id:'a', fecha:'2026-06-01', debe:1000, haber:0 },
    { id:'b', fecha:'2026-06-03', debe:0, haber:1000 },
  ];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r?.id, 'a');
});
test('sugerirMatchExtracto: importe negativo matchea un haber', () => {
  const linea = { fecha:'2026-06-05', importe:-500 };
  const movs = [{ id:'x', fecha:'2026-06-05', debe:0, haber:500 }];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r?.id, 'x');
});
test('sugerirMatchExtracto: fuera de ventana no matchea', () => {
  const linea = { fecha:'2026-06-20', importe:1000 };
  const movs = [{ id:'a', fecha:'2026-06-01', debe:1000, haber:0 }];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r, null);
});
