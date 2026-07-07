// Tests de los parsers puros del sort de tablas (Paquete 2C) y enRango (2D).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('parseCellValue detecta números con formato US$/miles', () => {
  const r = erp.run(`[parseCellValue('US$ 1.234,50').v,parseCellValue('US$ 1.234,50').tipo,parseCellValue('85%').v,parseCellValue('12,5').v]`);
  assert.deepStrictEqual(Array.from(r), [1234.5, 'num', 85, 12.5]);
});

test('parseCellValue detecta fechas ISO y DD/MM/YYYY', () => {
  const r = erp.run(`[parseCellValue('2026-07-07').v,parseCellValue('07/03/2026').v,parseCellValue('—').tipo,parseCellValue('').tipo]`);
  assert.deepStrictEqual(Array.from(r), ['2026-07-07', '2026-03-07', 'vacio', 'vacio']);
});

test('detectColType decide por mayoría (60%)', () => {
  const r = erp.run(`[detectColType(['US$ 10','US$ 20','—','texto']),detectColType(['2026-01-01','2026-02-01','—']),detectColType(['Anillo BX','Unión 2"','10'])]`);
  assert.deepStrictEqual(Array.from(r), ['num', 'fecha', 'texto']);
});

test('compareCells ordena y manda vacíos al final', () => {
  const r = erp.run(`(()=>{
    const vals=['US$ 300','—','US$ 25','US$ 1.000'];
    return vals.slice().sort((a,b)=>compareCells(a,b,'num'));
  })()`);
  assert.deepStrictEqual(Array.from(r), ['US$ 25', 'US$ 300', 'US$ 1.000', '—']);
});

test('enRango filtra por fecha inclusive, vacío = sin límite', () => {
  const r = erp.run(`[enRango('2026-07-07','2026-07-01','2026-07-31'),enRango('2026-07-07','','2026-07-06'),enRango('2026-07-07','',''),enRango('','2026-07-01',''),enRango(null,'','')]`);
  assert.deepStrictEqual(Array.from(r), [true, false, true, false, true]);
});
