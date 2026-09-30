// Tests del armado de factura electrónica (sprint integridad 2026-07-30).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function cbte(cond, tieneCuit) {
  return erp.run(`tipoComprobanteVentaAFIP(${JSON.stringify(cond)},${tieneCuit})`);
}
function items(list, opts) {
  return erp.run(`buildItemsFactura(${JSON.stringify(list)},${JSON.stringify(opts)})`);
}

test('tipoComprobanteVentaAFIP: RI y monotributo reciben Factura A (RG 5003)', () => {
  // Objetos cruzan el contexto vm: comparar propiedad por propiedad
  const ri = cbte('RI', true);
  assert.strictEqual(ri.tipo, 1);
  assert.strictEqual(ri.letra, 'A');
  const mono = cbte('monotributo', true);
  assert.strictEqual(mono.tipo, 1);
  assert.strictEqual(mono.letra, 'A');
});

test('tipoComprobanteVentaAFIP: exento y consumidor final reciben B', () => {
  assert.strictEqual(cbte('exento', true).tipo, 6);
  assert.strictEqual(cbte('consumidor_final', false).tipo, 6);
});

test('tipoComprobanteVentaAFIP: con CUIT sin condición definida → null (falta el dato)', () => {
  assert.strictEqual(cbte(null, true), null);
});

test('tipoComprobanteVentaAFIP: sin CUIT sin condición → B consumidor final', () => {
  const r = cbte(null, false);
  assert.strictEqual(r.tipo, 6);
  assert.strictEqual(r.letra, 'B');
});

test('buildItemsFactura convierte USD→ARS al TC y manda neto', () => {
  const r = items(
    [{ pieza: 'Unión doble 2"', cantidad: 2, precio_unitario: 100 }],
    { tc: 1300, ivaPct: 21, incluyenIva: false }
  );
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].descripcion, 'Unión doble 2"');
  assert.strictEqual(r[0].cantidad, 2);
  assert.strictEqual(r[0].precio_unit, 130000); // 100 USD × 1300, ya es neto
  assert.strictEqual(r[0].iva_pct, 21);
});

test('buildItemsFactura desagrega IVA si los precios lo incluyen', () => {
  const r = items(
    [{ pieza: 'Anillo BX', cantidad: 1, precio_unitario: 121 }],
    { tc: 1000, ivaPct: 21, incluyenIva: true }
  );
  assert.strictEqual(r[0].precio_unit, 100000); // 121.000 ARS / 1.21
});

test('buildItemsFactura tolera lista vacía y campos faltantes', () => {
  assert.strictEqual(items([], { tc: 1000, ivaPct: 21, incluyenIva: false }).length, 0);
  const r = items([{ cantidad: 1 }], { tc: 1000, ivaPct: 21, incluyenIva: false });
  assert.strictEqual(r[0].descripcion, 'Producto');
  assert.strictEqual(r[0].precio_unit, 0);
});

// ── Motivo del rechazo de ARCA visible (2026-09-30) ──────────────────
// La Edge Function devuelve {detail:{mensaje, errores:[{code,msg}],
// observaciones:[...]}} y el ERP mostraba solo `mensaje`.
function motivo(detail, statusText) {
  return erp.run(`mensajeErrorFacturacion(${JSON.stringify(detail)},${JSON.stringify(statusText || '')})`);
}

test('mensajeErrorFacturacion: string → tal cual', () => {
  assert.strictEqual(motivo('Sesión inválida o vencida'), 'Sesión inválida o vencida');
});

test('mensajeErrorFacturacion: rechazo de ARCA muestra código y motivo de cada error', () => {
  const m = motivo({
    mensaje: 'AFIP rechazó la solicitud de CAE',
    resultado: 'R',
    errores: [{ code: 10247, msg: 'La CUIT receptora informada está inactiva o es inválida.' }],
    observaciones: [],
  });
  assert.match(m, /rechaz/i);
  assert.match(m, /10247/);
  assert.match(m, /CUIT receptora informada está inactiva/);
});

test('mensajeErrorFacturacion: observaciones de ARCA también se muestran', () => {
  const m = motivo({
    mensaje: 'AFIP rechazó la solicitud de CAE',
    resultado: 'R',
    errores: [],
    observaciones: ['10015: Para comprobantes tipo B ... DocTipo deberá ser distinto de 99'],
  });
  assert.match(m, /10015/);
  assert.match(m, /DocTipo/);
});

test('mensajeErrorFacturacion: sin detalle usa el statusText; objeto sin errores usa mensaje', () => {
  assert.strictEqual(motivo(undefined, 'Bad Gateway'), 'Bad Gateway');
  assert.strictEqual(motivo({ mensaje: 'WSAA: token inválido' }), 'WSAA: token inválido');
});

// ── Ver CAE: ir directo a Constatación de Comprobantes (2026-09-30) ──
// https://www.afip.gob.ar/fe/qr/?p=… (destino oficial del QR, RG 4892)
// hoy responde una página en blanco con un código de bloqueo. La página
// real es servicioscf.afip.gob.ar/publico/comprobantes/cae.aspx?p=<mismo p>.
test('urlConstatacionArca: reusa el payload p del qr_url oficial', () => {
  const p = 'eyJ2ZXIiOjF9';
  const u = erp.run(`urlConstatacionArca(${JSON.stringify('https://www.afip.gob.ar/fe/qr/?p=' + p)})`);
  assert.strictEqual(u, 'https://servicioscf.afip.gob.ar/publico/comprobantes/cae.aspx?p=' + p);
});

test('urlConstatacionArca: sin p reconocible devuelve la URL original; vacío → null', () => {
  assert.strictEqual(erp.run(`urlConstatacionArca('https://otra.cosa/x')`), 'https://otra.cosa/x');
  assert.strictEqual(erp.run(`urlConstatacionArca('')`), null);
  assert.strictEqual(erp.run(`urlConstatacionArca(null)`), null);
});
