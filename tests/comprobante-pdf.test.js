// Tests del comprobante impreso (factura / NC / ND con CAE, mig 087):
// el modelo que alimenta el PDF. El dibujo (jsPDF + QR) se prueba en el
// navegador.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;

const EMP = { razon: 'VITALMET S.A.', cuit: '34-59751980-1', domicilio: 'Perú 246', iibb: '901-123', inicio: '2010-03-01' };
const CLI = { id: 'c1', nombre: 'YPF S.A.', cuit: '30-54668997-9', condicion_fiscal: 'RI', direccion: 'Macacha Güemes 515' };
const FA = { id: 'f1', venta_id: 'v1', tipo_comprobante: 1, punto_venta: 4, numero: 10, fecha: '2026-08-01', doc_tipo: 80, doc_nro: '30546689979',
  imp_neto: 1500, imp_iva: 262.5, imp_total: 1762.5, cae: '76123456789012', cae_vto: '2026-08-11', afip_environment: 'produccion',
  qr_url: 'https://www.afip.gob.ar/fe/qr/?p=abc',
  items: [{ descripcion: 'Unión 2" FIG 1502', cantidad: 2, precio_unit: 500, iva_pct: 21 }, { descripcion: 'Flete', cantidad: 1, precio_unit: 500, iva_pct: 10.5 }] };
const VENTA = { id: 'v1', cliente: 'YPF S.A.', cliente_id: 'c1', nro_remito: 'R-0012', nro_pedido: 'OC-77', condicion_pago: '30 días',
  venta_items: [{ pieza: 'Unión', cantidad: 3, precio_unitario: 100 }, { pieza: 'Codo', cantidad: 1, precio_unitario: 100 }] };
const modelo = (f, ctx) => JSON.parse(erp.run(`JSON.stringify(comprobanteModelo(${J(f)}, ${J(ctx)}))`));

test('fmtCuitDoc: formatea CUIT de 11 dígitos y deja el resto como viene', () => {
  assert.strictEqual(erp.run(`fmtCuitDoc('30546689979')`), '30-54668997-9');
  assert.strictEqual(erp.run(`fmtCuitDoc('30-54668997-9')`), '30-54668997-9');
  assert.strictEqual(erp.run(`fmtCuitDoc('12345678')`), '12345678');
});

test('Factura A: discrimina IVA por alícuota con el detalle informado a ARCA', () => {
  const m = modelo(FA, { cliente: CLI, venta: VENTA, empresa: EMP });
  assert.strictEqual(m.titulo, 'FACTURA');
  assert.strictEqual(m.letra, 'A');
  assert.strictEqual(m.codigo, '01');
  assert.strictEqual(m.numero, '00004-00000010');
  assert.strictEqual(m.discrimina, true);
  assert.strictEqual(m.estimados, false);
  assert.deepStrictEqual(m.items.map(i => [i.cantidad, i.precio, i.iva_pct, i.subtotal]), [[2, 500, 21, 1000], [1, 500, 10.5, 500]]);
  assert.deepStrictEqual(m.ivas, [{ pct: 10.5, base: 500, importe: 52.5 }, { pct: 21, base: 1000, importe: 210 }]);
  assert.strictEqual(m.total, 1762.5);
  assert.strictEqual(m.iva_contenido, null);
  assert.deepStrictEqual(m.receptor, { nombre: 'YPF S.A.', doc_label: 'CUIT', doc: '30-54668997-9', cond_iva: 'IVA Responsable Inscripto', domicilio: 'Macacha Güemes 515' });
  assert.strictEqual(m.condicion_venta, '30 días');
  assert.strictEqual(m.referencia, 'Remito R-0012 · Pedido OC-77');
  assert.strictEqual(m.emisor.iibb, '901-123');
  assert.strictEqual(m.homologacion, false);
  assert.strictEqual(m.archivo, 'FA-A_00004-00000010_YPF_S_A_.pdf');
});

test('Factura B: precios finales con IVA incluido e IVA contenido (Ley 27.743)', () => {
  const f = { ...FA, tipo_comprobante: 6, doc_tipo: 99, doc_nro: '0', imp_neto: 1000, imp_iva: 210, imp_total: 1210,
    items: [{ descripcion: 'Anillo BX', cantidad: 2, precio_unit: 500, iva_pct: 21 }] };
  const m = modelo(f, { cliente: null, venta: null, empresa: EMP });
  assert.strictEqual(m.letra, 'B');
  assert.strictEqual(m.discrimina, false);
  assert.deepStrictEqual(m.items.map(i => [i.precio, i.subtotal]), [[605, 1210]]);
  assert.strictEqual(m.iva_contenido, 210);
  assert.strictEqual(m.receptor.nombre, 'Consumidor Final');
  assert.strictEqual(m.receptor.doc, '');
  assert.strictEqual(m.receptor.cond_iva, 'Consumidor Final');
  assert.strictEqual(m.condicion_venta, 'Cuenta corriente');
});

test('Sin detalle guardado: se reconstruye desde la venta y cierra contra el neto de ARCA', () => {
  const f = { ...FA, items: null, imp_neto: 1000.01, imp_iva: 210, imp_total: 1210.01 };
  const m = modelo(f, { cliente: CLI, venta: VENTA, empresa: EMP });
  assert.strictEqual(m.estimados, true);
  assert.deepStrictEqual(m.items.map(i => i.descripcion), ['Unión', 'Codo']);
  assert.deepStrictEqual(m.items.map(i => i.subtotal), [750.01, 250]);
  assert.strictEqual(Math.round(m.items.reduce((s, i) => s + i.subtotal, 0) * 100) / 100, 1000.01);
  assert.deepStrictEqual(m.ivas, [{ pct: 21, base: 1000.01, importe: 210 }]);
});

test('Nota de crédito sin detalle: una línea con la factura que corrige', () => {
  const nc = { id: 'n1', venta_id: 'v1', factura_asociada_id: 'f1', tipo_comprobante: 3, punto_venta: 4, numero: 2, fecha: '2026-09-01',
    doc_tipo: 80, doc_nro: '30546689979', imp_neto: 100, imp_iva: 21, imp_total: 121, cae: '1', cae_vto: '2026-09-11', afip_environment: 'homologacion' };
  const m = modelo(nc, { cliente: CLI, venta: VENTA, asociada: FA, empresa: EMP });
  assert.strictEqual(m.titulo, 'NOTA DE CRÉDITO');
  assert.strictEqual(m.codigo, '03');
  assert.deepStrictEqual(m.items.map(i => [i.descripcion, i.cantidad, i.subtotal]), [['Nota de crédito s/ FA-A 00004-00000010', 1, 100]]);
  assert.strictEqual(m.asociado, 'Comprobante asociado: FA-A 00004-00000010 del 01/08/2026');
  assert.strictEqual(m.referencia, '');
  assert.strictEqual(m.condicion_venta, 'Cuenta corriente');
  assert.strictEqual(m.homologacion, true);
});

test('Nota de débito libre: período asociado y observaciones sin los avisos de ARCA', () => {
  const nd = { id: 'd1', tipo_comprobante: 2, punto_venta: 4, numero: 1, fecha: '2026-09-03', doc_tipo: 80, doc_nro: '30546689979',
    imp_neto: 100, imp_iva: 21, imp_total: 121, cae: '2', cae_vto: '2026-09-13', afip_environment: 'produccion',
    periodo_asoc_desde: '2026-08-01', periodo_asoc_hasta: '2026-08-31',
    observaciones: 'Intereses de agosto · Emitida en USD a TC $1450 · 10217: aviso de ARCA',
    items: [{ descripcion: 'Intereses', cantidad: 1, precio_unit: 100, iva_pct: 21 }] };
  const m = modelo(nd, { cliente: CLI, empresa: EMP });
  assert.strictEqual(m.titulo, 'NOTA DE DÉBITO');
  assert.strictEqual(m.asociado, 'Período asociado: 01/08/2026 al 31/08/2026');
  assert.strictEqual(m.obs, 'Intereses de agosto · Emitida en USD a TC $1450');
});

test('comprobanteObs: las observaciones de ARCA (array) no se imprimen', () => {
  assert.strictEqual(erp.run(`comprobanteObs(['10217: algo'])`), '');
  assert.strictEqual(erp.run(`comprobanteObs(null)`), '');
});

test('Si el detalle no cierra contra el IVA autorizado, el IVA va en un renglón con el importe real', () => {
  const f = { ...FA, imp_neto: 1500, imp_iva: 300, imp_total: 1800 };
  const m = modelo(f, { cliente: CLI, empresa: EMP });
  assert.strictEqual(m.ivas.length, 1);
  assert.strictEqual(m.ivas[0].importe, 300);
});
