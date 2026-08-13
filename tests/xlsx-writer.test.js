// Tests del generador .xlsx en JS puro (xlsxBuild) y del armado del
// Libro IVA Digital en Excel (libroIvaExcelHojas). El .xlsx es un ZIP
// "store" (sin comprimir), así que el XML aparece en claro en los bytes
// y se puede inspeccionar sin descomprimir.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const hojas = (v, c, e) =>
  erp.run(`libroIvaExcelHojas(${JSON.stringify(v)},${JSON.stringify(c)},${JSON.stringify(e || [])})`);
const build = (h) => erp.run(`xlsxBuild(${JSON.stringify(h)})`);
const decode = (bytes) => new TextDecoder().decode(Uint8Array.from(bytes));

const VENTAS = [
  { fecha: '2026-08-05', tipo: 1, pv: 4, nro: 123, docTipo: 80, docNro: '30112223334',
    denom: 'ACME SA', total: 121000, moneda: 'PES', tc: 1,
    alicuotas: [{ pct: 21, neto: 100000, iva: 21000 }] },
  { fecha: '2026-08-20', tipo: 3, pv: 4, nro: 45, docTipo: 80, docNro: '30112223334',
    denom: 'ACME SA', total: 1210, moneda: 'PES', tc: 1,
    alicuotas: [{ pct: 21, neto: 1000, iva: 210 }] }, // NC-A: resta
];
const COMPRAS = [
  { fecha: '2026-08-10', tipo: 1, pv: 3, nro: 4567, docTipo: 80, docNro: '30556667778',
    denom: 'PROVEEDOR SRL', total: 60500, moneda: 'PES', tc: 1,
    percepIva: 0, percepNac: 0, percepIibb: 500, credFiscal: 10500,
    alicuotas: [{ pct: 21, neto: 50000, iva: 10500 }] },
];

test('libroIvaExcelHojas: 3 hojas con headers y TOTALES que cuadran (NC resta)', () => {
  const h = hojas(VENTAS, COMPRAS, []);
  assert.deepEqual(Array.from(h, (x) => x.nombre), ['Ventas', 'Compras', 'Resumen']);

  // Ventas: TOTALES = neto/iva/total netos de la NC
  const vTot = h[0].filas[h[0].filas.length - 1];
  assert.strictEqual(vTot[5].v, 99000);   // neto 100000 − 1000
  assert.strictEqual(vTot[6].v, 20790);   // iva  21000  − 210
  assert.strictEqual(vTot[8].v, 119790);  // total 121000 − 1210

  // Compras: TOTALES
  const cTot = h[1].filas[h[1].filas.length - 1];
  assert.strictEqual(cTot[5].v, 50000);   // neto
  assert.strictEqual(cTot[6].v, 10500);   // iva
  assert.strictEqual(cTot[9].v, 500);     // percep IIBB
  assert.strictEqual(cTot[11].v, 10500);  // crédito fiscal
  assert.strictEqual(cTot[12].v, 60500);  // total
});

test('libroIvaExcelHojas: Resumen deriva DF/CF de las mismas hojas', () => {
  const r = hojas(VENTAS, COMPRAS, []).find((x) => x.nombre === 'Resumen');
  assert.strictEqual(r.filas[1][1].v, 20790);        // DF = IVA ventas neto
  assert.strictEqual(r.filas[2][1].v, 10500);        // CF = crédito fiscal
  assert.strictEqual(r.filas[3][1].v, 10290);        // saldo técnico
  const saldo = r.filas[r.filas.length - 1];
  assert.strictEqual(saldo[0].v, 'SALDO A PAGAR');
  assert.strictEqual(saldo[1].v, 10290);
});

test('libroIvaExcelHojas: excluidos van como nota al pie de Compras', () => {
  const h = hojas(VENTAS, COMPRAS, ['B 998', 'C 12']);
  const compras = h[1].filas;
  const nota = compras[compras.length - 1][0].v;
  assert.match(nota, /Excluidos.*B 998, C 12/);
});

test('xlsxBuild: ZIP válido con las partes obligatorias del OOXML', () => {
  const bytes = build(hojas(VENTAS, COMPRAS, []));
  assert.strictEqual(bytes[0], 0x50); // 'P'
  assert.strictEqual(bytes[1], 0x4b); // 'K'  → firma ZIP
  const xml = decode(bytes);
  for (const parte of ['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml',
    'xl/_rels/workbook.xml.rels', 'xl/styles.xml',
    'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml', 'xl/worksheets/sheet3.xml']) {
    assert.ok(xml.includes(parte), `falta la parte ${parte}`);
  }
  assert.ok(xml.includes('name="Ventas"'));
  assert.ok(xml.includes('PROVEEDOR SRL'));
  assert.ok(xml.includes('#,##0.00'));            // formato de moneda
  assert.ok(xml.includes('state="frozen"'));      // header congelado
});

test('xlsxBuild: escapa XML en el contenido de las celdas', () => {
  const bytes = build([{ nombre: 'H', filas: [[{ v: 'A & B <x> "q"', s: 'header' }]] }]);
  const xml = decode(bytes);
  assert.ok(xml.includes('A &amp; B &lt;x&gt;'));
  assert.ok(!xml.includes('<x>'));                // el < crudo no debe quedar
});

test('xlsxBuild: celdas numéricas como <v>, textos como inlineStr', () => {
  const bytes = build([{ nombre: 'H', filas: [[{ v: 1234.5, t: 'n', s: 'money' }, 'hola']] }]);
  const xml = decode(bytes);
  assert.ok(xml.includes('<v>1234.5</v>'));
  assert.ok(xml.includes('t="inlineStr"><is><t xml:space="preserve">hola</t></is>'));
});
