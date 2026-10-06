// Tests de los modelos de libros imprimibles (Diario, Mayor, IVA) y del
// transporte por hoja. El dibujo del PDF (jsPDF) se prueba en el navegador.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;

const CUENTAS = [
  { id: 'c1', codigo: '111003', nombre: 'BANCO', tipo: 'activo' },
  { id: 'c2', codigo: '211002', nombre: 'PROVEEDORES', tipo: 'pasivo' },
  { id: 'c3', codigo: '422001', nombre: 'GASTOS', tipo: 'egreso' },
];
const AS = [
  { id: 'a1', numero: 1, fecha: '2026-09-10', estado: 'confirmado', moneda: 'ARS', descripcion: 'Factura gastos', comprobante_nro: 'A-1' },
  { id: 'a2', numero: 2, fecha: '2026-10-05', estado: 'confirmado', moneda: 'ARS', descripcion: 'Pago' },
  { id: 'a3', numero: 3, fecha: '2026-10-06', estado: 'anulado', moneda: 'ARS', descripcion: 'Anulado' },
  { id: 'a4', numero: 4, fecha: '2026-10-07', estado: 'confirmado', moneda: 'USD', tipo_cambio: 1000, descripcion: 'Gasto en USD' },
];
const LN = [
  { asiento_id: 'a1', cuenta_id: 'c3', debe: 1000, haber: 0, orden: 0 }, { asiento_id: 'a1', cuenta_id: 'c2', debe: 0, haber: 1000, orden: 1 },
  { asiento_id: 'a2', cuenta_id: 'c2', debe: 400, haber: 0, orden: 0 }, { asiento_id: 'a2', cuenta_id: 'c1', debe: 0, haber: 400, orden: 1 },
  { asiento_id: 'a3', cuenta_id: 'c3', debe: 999, haber: 0, orden: 0 }, { asiento_id: 'a3', cuenta_id: 'c2', debe: 0, haber: 999, orden: 1 },
  { asiento_id: 'a4', cuenta_id: 'c3', debe: 2, haber: 0, orden: 0 }, { asiento_id: 'a4', cuenta_id: 'c2', debe: 0, haber: 2, orden: 1 },
];
const args = `${J(AS)}, ${J(LN)}, ${J(CUENTAS)}`;

test('Libro Diario: sólo confirmados, en ARS, debe = haber', () => {
  const m = erp.run(`libroDiarioModelo(${args}, '', '')`);
  assert.strictEqual(m.asientos, 3);
  assert.strictEqual(m.debe, 3400); // 1.000 + 400 + 2 USD × 1.000
  assert.strictEqual(m.haber, 3400);
  assert.deepStrictEqual([...m.sumar], [4, 5]);
  const f0 = [...m.filas[0]];
  assert.deepStrictEqual(f0, ['10/09/2026', '1', '422001', 'GASTOS', 1000, '']);
  assert.match(m.filas[1][3], /a {2}PROVEEDORES$/); // la cuenta del haber va sangrada
  assert.match(m.filas[2].nota, /Factura gastos — A-1/);
});

test('Libro Diario: respeta el rango de fechas', () => {
  const m = erp.run(`libroDiarioModelo(${args}, '2026-10-01', '2026-10-31')`);
  assert.strictEqual(m.asientos, 2);
  assert.strictEqual(m.debe, 2400);
  assert.match(m.subtitulo, /01\/10\/2026 al 31\/10\/2026/);
});

test('Libro Mayor de una cuenta: saldo anterior + movimientos + totales', () => {
  const m = erp.run(`libroMayorModelo(${args}, 'c2', '2026-10-01', '2026-10-31')`);
  assert.match(m.filas[0].grupo, /211002 — PROVEEDORES.*acreedor/);
  assert.strictEqual(m.filas[1].total[5], 1000); // saldo anterior acreedor
  assert.deepStrictEqual([...m.filas[2]].slice(3), [400, '', 600]);
  assert.deepStrictEqual([...m.filas[3]].slice(3), ['', 2000, 2600]);
  assert.deepStrictEqual([...m.filas[4].total].slice(3), [400, 2000, 2600]);
  assert.deepStrictEqual([...m.sumar], [3, 4]);
});

test('Libro Mayor general: todas las cuentas con movimientos, sin transporte', () => {
  const m = erp.run(`libroMayorModelo(${args}, '', '', '')`);
  assert.strictEqual(m.cuentas, 3);
  assert.strictEqual(m.sumar.length, 0);
  assert.strictEqual(m.filas.filter(f => f.grupo).length, 3);
  const banco = m.filas.findIndex(f => f.grupo && /BANCO/.test(f.grupo));
  assert.strictEqual(m.filas[banco + 2].total[5], -400); // activo con saldo acreedor: negativo
});

test('libroTransportes: acumula por hoja sólo filas de datos', () => {
  const filas = [['a', 10, 1], { nota: 'x' }, ['b', 20, 2], ['c', '', 3], { total: ['', 999, 999] }, ['d', 5, 4]];
  const r = erp.run(`libroTransportes(${J(filas)}, [1,2], [1,1,1,2,2,3], 3)`);
  assert.strictEqual(JSON.stringify(r), '[[30,3],[30,6],[35,10]]');
});

test('Libro IVA Compras: reordena alícuotas y agrupa lo que no tiene columna propia', () => {
  //            10,5      21         27     otras   s/desg  NG  EX  pIVA pIIBB jur pGan otros total
  const nums = [100, 10.5, 1000, 210, 0, 0, 50, 2.5, 30, 6.3, 7, 3, 15, 20, 0, 5, 1, 1460.3];
  const m = erp.run(`libroIvaComprasModelo(${J([{ txt: ['05/10/2026', 'FA-A', '0001-00000001', 'ACEROS SA', '30-1'], nums }])}, '2026-10-01', '2026-10-31')`);
  assert.strictEqual(m.columnas.length, 18);
  assert.deepStrictEqual([...m.filas[0]].slice(5), [1000, 210, 100, 10.5, '', '', 80, 8.8, 10, 15, 20, 6, 1460.3]);
  assert.strictEqual(m.orient, 'l');
  assert.strictEqual(m.sumar.length, 13);
});

test('Libro IVA Ventas: columnas de importe para el transporte', () => {
  const m = erp.run(`libroIvaVentasModelo(${J([['05/10/2026', 'FA A', '00004-00000012', 'YPF', '30-5', 1000, 210, '21', 1210, '7612']])}, '2026-10-01', '2026-10-31')`);
  assert.deepStrictEqual([...m.sumar], [5, 6, 8]);
  assert.strictEqual(m.filas[0][8], 1210);
});

test('parseEscalaRetencion: valida tramos contiguos', () => {
  const ok = erp.run(`parseEscalaRetencion("0;8000;0;5\\n8000;;400;9")`);
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(JSON.stringify(ok.escala), '[{"desde":0,"hasta":8000,"fijo":0,"pct":5},{"desde":8000,"hasta":null,"fijo":400,"pct":9}]');
  assert.strictEqual(erp.run(`parseEscalaRetencion("0;8000;0;5\\n9000;;400;9")`).ok, false);
  assert.strictEqual(erp.run(`parseEscalaRetencion("0;abc;0;5")`).ok, false);
  assert.strictEqual(erp.run(`parseEscalaRetencion("")`).escala, null);
});

test('retencionesPracticadasFilas: totales por impuesto sin las anuladas', () => {
  const list = [
    { proveedor_id: 'p1', orden_pago_id: 'o1', fecha: '2026-10-05', impuesto: 'ganancias', regimen_codigo: '78', regimen_nombre: 'Bienes', certificado_nro: '00000001', base_calculo: 1000000, alicuota: 2, monto: 15520, estado: 'vigente' },
    { proveedor_id: 'p1', orden_pago_id: 'o2', fecha: '2026-10-06', impuesto: 'ganancias', regimen_codigo: '78', regimen_nombre: 'Bienes', certificado_nro: '00000002', base_calculo: 500000, alicuota: 2, monto: 10000, estado: 'anulada' },
  ];
  const r = erp.run(`retencionesPracticadasFilas(${J(list)}, ${J([{ id: 'p1', nombre: 'ACEROS SA', cuit: '30-1' }])}, ${J([{ id: 'o1', nro: 'OP-0007', orden_pago_imputaciones: [{ factura_id: 'f1' }] }])}, ${J([{ id: 'f1', nro: 'A-0001-00000010' }])})`);
  assert.strictEqual(r.tot.ganancias, 15520);
  assert.strictEqual(r.filas.length, 4); // encabezado + 2 + total
  assert.strictEqual(r.filas[1][9], 'A-0001-00000010');
  assert.strictEqual(r.filas[2][13], 'ANULADA');
  assert.strictEqual(r.filas[3][12], '15520,00');
});
