// Tests de la importación de "Mis Comprobantes Recibidos" de ARCA: lectura
// del archivo (Excel o CSV, formato viejo y con IVA por alícuota) y cruce
// contra las facturas de proveedor ya cargadas.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;
const parse = rows => JSON.parse(erp.run(`JSON.stringify(parseMisComprobantes(${J(rows)}))`));

const HEAD_VIEJO = ['Fecha', 'Tipo', 'Punto de Venta', 'Número Desde', 'Número Hasta', 'Cód. Autorización', 'Tipo Doc. Emisor', 'Nro. Doc. Emisor', 'Denominación Emisor', 'Tipo Cambio', 'Moneda', 'Imp. Neto Gravado', 'Imp. Neto No Gravado', 'Imp. Op. Exentas', 'Otros Tributos', 'IVA', 'Imp. Total'];

test('Excel formato viejo: título arriba, tipo "1 - Factura A", fecha dd/mm/aaaa', () => {
  const r = parse([
    ['Mis Comprobantes Recibidos - CUIT 30712345678'],
    HEAD_VIEJO,
    ['03/10/2026', '1 - Factura A', 3, 1234, 1234, '75401234567890', 'CUIT', 30500010912, 'ACEROS SA', 1, '$', 100000, 0, 0, 3000, 21000, 124000],
  ]);
  assert.strictEqual(r.comprobantes.length, 1);
  const c = r.comprobantes[0];
  assert.deepStrictEqual([c.fecha, c.tipo, c.letra, c.pv, c.numero, c.cuit, c.nombre, c.moneda],
    ['2026-10-03', 'factura', 'A', 3, 1234, '30500010912', 'ACEROS SA', 'ARS']);
  assert.deepStrictEqual(c.ivas, [{ alicuota: 21, base: 100000, monto: 21000 }]);
  assert.deepStrictEqual([c.otrosTributos, c.total, c.nro], [3000, 124000, 'A-0003-00001234']);
});

test('CSV con ; y coma decimal, tipo numérico, NC en negativo y USD', () => {
  const txt = '﻿"Fecha de Emisión";"Tipo de Comprobante";"Punto de Venta";"Número Desde";"Número Hasta";"Cód. Autorización";"Tipo Doc. Emisor";"Nro. Doc. Emisor";"Denominación Emisor";"Tipo Cambio";"Moneda";"Imp. Neto Gravado";"Imp. Neto No Gravado";"Imp. Op. Exentas";"Otros Tributos";"IVA";"Imp. Total"\r\n'
    + '2026-10-05;3;00002;00000045;00000045;75;80;30500010912;"ACEROS; Y CIA SA";1,000000;PES;-1.000,50;0;0;0;-210,11;-1.210,61\r\n'
    + '2026-10-06;6;1;77;77;75;80;20123456786;MONO;1450,5;DOL;0;0;0;0;0;500\r\n';
  const r = JSON.parse(erp.run(`JSON.stringify(parseMisComprobantes(arcaCsvRows(${J(txt)})))`));
  const [nc, fb] = r.comprobantes;
  assert.deepStrictEqual([nc.fecha, nc.tipo, nc.letra, nc.nombre, nc.total], ['2026-10-05', 'nota_credito', 'A', 'ACEROS; Y CIA SA', 1210.61]);
  assert.deepStrictEqual(nc.ivas, [{ alicuota: 21, base: 1000.5, monto: 210.11 }]);
  assert.deepStrictEqual([fb.letra, fb.moneda, fb.tc, fb.total, fb.ivas.length], ['B', 'USD', 1450.5, 500, 0]);
});

test('formato con IVA por alícuota: una fila de IVA por cada alícuota con importe', () => {
  const head = ['Fecha de Emisión', 'Tipo de Comprobante', 'Punto de Venta', 'Número Desde', 'Nro. Doc. Emisor', 'Denominación Emisor', 'Tipo Cambio', 'Moneda',
    'Imp. Neto Gravado IVA 0%', 'IVA 2,5%', 'Imp. Neto Gravado IVA 2,5%', 'IVA 10,5%', 'Imp. Neto Gravado IVA 10,5%', 'IVA 21%', 'Imp. Neto Gravado IVA 21%', 'IVA 27%', 'Imp. Neto Gravado IVA 27%',
    'Total Neto Gravado', 'Imp. Neto No Gravado', 'Imp. Op. Exentas', 'Otros Tributos', 'Total IVA', 'Imp. Total'];
  const r = parse([head, ['01/10/2026', 1, 5, 9, '30500010912', 'EDESUR', 1, '$', 0, 0, 0, 105, 1000, 420, 2000, 270, 1000, 4000, 50, 0, 10, 795, 4855]]);
  const c = r.comprobantes[0];
  assert.deepStrictEqual(c.ivas, [{ alicuota: 10.5, base: 1000, monto: 105 }, { alicuota: 21, base: 2000, monto: 420 }, { alicuota: 27, base: 1000, monto: 270 }]);
  assert.deepStrictEqual([c.noGravado, c.otrosTributos, c.total], [50, 10, 4855]);
});

test('formato viejo con alícuotas mezcladas: una fila a revisar, marcada', () => {
  const r = parse([HEAD_VIEJO, ['03/10/2026', 1, 3, 1, 1, '', 'CUIT', '30500010912', 'X', 1, '$', 3000, 0, 0, 0, 525, 3525]]);
  assert.strictEqual(r.comprobantes[0].ivaMixto, true);
  assert.deepStrictEqual(r.comprobantes[0].ivas, [{ alicuota: 21, base: 3000, monto: 525 }]);
});

test('archivo de emitidos o sin encabezado: error claro', () => {
  const emit = HEAD_VIEJO.map(h => h.replace('Emisor', 'Receptor'));
  assert.match(parse([emit, []]).error, /emitidos/i);
  assert.match(parse([['hola', 'mundo']]).error, /Mis Comprobantes/);
});

test('nroPartes saca punto de venta y número de cualquier formato tipeado', () => {
  const p = s => ({ ...erp.run(`nroPartes(${J(s)})`) });
  assert.deepStrictEqual(p('A-0003-00001234'), { pv: 3, num: 1234 });
  assert.deepStrictEqual(p('0003-1234'), { pv: 3, num: 1234 });
  assert.deepStrictEqual(p('FA A 3 / 1234'), { pv: 3, num: 1234 });
  assert.deepStrictEqual(p('1234'), { pv: null, num: 1234 });
  assert.deepStrictEqual(p('s/n'), { pv: null, num: null });
});

test('conciliarArca: cargada, falta, difiere el total, sin proveedor', () => {
  const proveedores = [{ id: 'p1', nombre: 'Aceros', cuit: '30-50001091-2' }];
  const facturas = [
    { id: 'f1', proveedor_id: 'p1', tipo: 'factura', nro: 'A-0003-00001234', total: 124000, moneda: 'ARS' },
    { id: 'f2', proveedor_id: 'p1', tipo: 'factura', nro: '0003-00001235', total: 999, moneda: 'ARS' },
    { id: 'f4', proveedor_id: 'p1', tipo: 'nota_credito', nro: '3-1237', total: 100 },
  ];
  const c = (numero, total, extra = {}) => ({ tipo: 'factura', letra: 'A', pv: 3, numero, cuit: '30500010912', total, moneda: 'ARS', ...extra });
  const r = JSON.parse(erp.run(`JSON.stringify(conciliarArca(${J([c(1234, 124000), c(1235, 1000), c(1236, 500), c(1237, 100), c(1, 50, { cuit: '20123456786' })])},${J({ facturas, proveedores })}))`));
  assert.deepStrictEqual(r.map(x => x.estado), ['cargada', 'difiere', 'falta', 'falta', 'sin_proveedor']);
  assert.deepStrictEqual([r[0].factura_id, r[0].proveedor_id, r[4].proveedor_id], ['f1', 'p1', null]);
});
