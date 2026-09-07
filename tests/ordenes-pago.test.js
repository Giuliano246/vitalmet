// Tests del sprint "órdenes de pago" (2026-09-07, migración 074):
// saldo pendiente de facturas de proveedor, conversión de imputaciones,
// validación de la OP y cuenta corriente de proveedores.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const FA = { id: 'f1', nro: 'A-0001-00000010', tipo: 'factura', proveedor_id: 'p1', moneda: 'ARS', tipo_cambio: 1000, total: 121000, fecha: '2026-08-01', fecha_vto: '2026-08-31' };
const NC = { id: 'n1', nro: 'NC-1', tipo: 'nota_credito', factura_asociada_id: 'f1', proveedor_id: 'p1', moneda: 'ARS', total: 21000 };
const ND = { id: 'd1', nro: 'ND-1', tipo: 'nota_debito', factura_asociada_id: 'f1', proveedor_id: 'p1', moneda: 'ARS', total: 1000 };

// ── imputacionesVivas ─────────────────────────────────────────────

test('imputacionesVivas: sólo las de OPs confirmadas', () => {
  const r = erp.run(`imputacionesVivas(${JSON.stringify([
    { id: 'op1', estado: 'confirmada', orden_pago_imputaciones: [{ factura_id: 'f1', monto: 10, monto_factura: 10 }] },
    { id: 'op2', estado: 'anulada', orden_pago_imputaciones: [{ factura_id: 'f1', monto: 99, monto_factura: 99 }] },
  ])})`);
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].orden_pago_id, 'op1');
  assert.strictEqual(r[0].monto_factura, 10);
});

// ── saldoFacturaProveedor ─────────────────────────────────────────

test('saldoFacturaProveedor sin NC ni pagos = total', () => {
  const r = erp.run(`saldoFacturaProveedor(${JSON.stringify(FA)}, ${JSON.stringify([FA])}, [])`);
  assert.deepStrictEqual({ ...r }, { total: 121000, nc: 0, nd: 0, pagado: 0, saldo: 121000 });
});

test('saldoFacturaProveedor descuenta NC asociadas, suma ND y resta imputaciones vivas', () => {
  const r = erp.run(`saldoFacturaProveedor(${JSON.stringify(FA)}, ${JSON.stringify([FA, NC, ND])}, ${JSON.stringify([
    { factura_id: 'f1', monto_factura: 50000 }, { factura_id: 'otra', monto_factura: 999 },
  ])})`);
  assert.strictEqual(r.nc, 21000);
  assert.strictEqual(r.nd, 1000);
  assert.strictEqual(r.pagado, 50000);
  assert.strictEqual(r.saldo, 51000);
});

test('saldoFacturaProveedor nunca devuelve saldo negativo (redondeo)', () => {
  const r = erp.run(`saldoFacturaProveedor(${JSON.stringify({ ...FA, total: 100 })}, [], [{ factura_id: 'f1', monto_factura: 100.004 }])`);
  assert.strictEqual(r.saldo, 0);
});

// ── convertirMontoImputacion ──────────────────────────────────────

test('convertirMontoImputacion: misma moneda no convierte', () => {
  assert.strictEqual(erp.run(`convertirMontoImputacion(123.45, 'ARS', 0, 'ARS')`), 123.45);
  assert.strictEqual(erp.run(`convertirMontoImputacion(10, 'USD', 1000, 'USD')`), 10);
});

test('convertirMontoImputacion: OP en USD sobre factura en ARS multiplica por TC', () => {
  assert.strictEqual(erp.run(`convertirMontoImputacion(10, 'USD', 1234.5, 'ARS')`), 12345);
});

test('convertirMontoImputacion: OP en ARS sobre factura en USD divide por TC, redondea a 2', () => {
  assert.strictEqual(erp.run(`convertirMontoImputacion(10000, 'ARS', 1300, 'USD')`), 7.69);
});

test('convertirMontoImputacion: sin TC entre monedas distintas devuelve null', () => {
  assert.strictEqual(erp.run(`convertirMontoImputacion(10, 'USD', 0, 'ARS')`), null);
});

// ── validarOrdenPago ──────────────────────────────────────────────

const MEDIOS_OK = [
  { tipo: 'banco', monto: 60000, cuenta_contable_id: 'c-bco' },
  { tipo: 'cheque', monto: 61000, cuenta_contable_id: 'c-chq', cheque: { numero: '123', fecha_pago: '2026-10-01' } },
];

test('validarOrdenPago: TF + cheque que suman el total, imputado a una factura, sin remanente', () => {
  const r = erp.run(`validarOrdenPago(${JSON.stringify({
    total: 121000, medios: MEDIOS_OK,
    imputaciones: [{ factura_id: 'f1', monto: 121000, monto_factura: 121000 }],
    saldos: { f1: 121000 },
  })})`);
  assert.strictEqual(r.ok, true, r.errores.join(' | '));
  assert.strictEqual(r.sumMedios, 121000);
  assert.strictEqual(r.sumImputado, 121000);
  assert.strictEqual(r.aCuenta, 0);
});

test('validarOrdenPago: varios cheques y pago parcial → remanente a cuenta', () => {
  const r = erp.run(`validarOrdenPago(${JSON.stringify({
    total: 100000,
    medios: [
      { tipo: 'cheque', monto: 50000, cuenta_contable_id: 'c', cheque: { numero: '1', fecha_pago: '2026-10-01' } },
      { tipo: 'cheque', monto: 50000, cuenta_contable_id: 'c', cheque: { numero: '2', fecha_pago: '2026-11-01' } },
    ],
    imputaciones: [{ factura_id: 'f1', monto: 70000, monto_factura: 70000 }],
    saldos: { f1: 121000 },
  })})`);
  assert.strictEqual(r.ok, true, r.errores.join(' | '));
  assert.strictEqual(r.aCuenta, 30000);
});

test('validarOrdenPago: medios que no suman el total', () => {
  const r = erp.run(`validarOrdenPago(${JSON.stringify({ total: 100, medios: [{ tipo: 'caja', monto: 90, cuenta_contable_id: 'c' }], imputaciones: [], saldos: {} })})`);
  assert.strictEqual(r.ok, false);
  assert.match(r.errores[0], /suman/);
});

test('validarOrdenPago: imputación mayor al saldo de la factura', () => {
  const r = erp.run(`validarOrdenPago(${JSON.stringify({
    total: 100, medios: [{ tipo: 'caja', monto: 100, cuenta_contable_id: 'c' }],
    imputaciones: [{ factura_id: 'f1', monto: 100, monto_factura: 100 }], saldos: { f1: 80 },
  })})`);
  assert.strictEqual(r.ok, false);
  assert.match(r.errores[0], /saldo/);
});

test('validarOrdenPago: imputaciones superan el total', () => {
  const r = erp.run(`validarOrdenPago(${JSON.stringify({
    total: 100, medios: [{ tipo: 'caja', monto: 100, cuenta_contable_id: 'c' }],
    imputaciones: [{ factura_id: 'f1', monto: 60, monto_factura: 60 }, { factura_id: 'f2', monto: 60, monto_factura: 60 }],
    saldos: { f1: 100, f2: 100 },
  })})`);
  assert.strictEqual(r.ok, false);
  assert.match(r.errores[0], /superan/);
});

test('validarOrdenPago: cheque sin número o fecha, medio sin cuenta, sin medios', () => {
  const sinDatos = erp.run(`validarOrdenPago(${JSON.stringify({ total: 10, medios: [{ tipo: 'cheque', monto: 10, cuenta_contable_id: 'c', cheque: { numero: '', fecha_pago: '' } }], imputaciones: [], saldos: {} })})`);
  assert.strictEqual(sinDatos.ok, false);
  assert.match(sinDatos.errores[0], /cheque/i);
  const sinCta = erp.run(`validarOrdenPago(${JSON.stringify({ total: 10, medios: [{ tipo: 'caja', monto: 10, cuenta_contable_id: '' }], imputaciones: [], saldos: {} })})`);
  assert.strictEqual(sinCta.ok, false);
  assert.match(sinCta.errores[0], /cuenta/i);
  const vacio = erp.run(`validarOrdenPago(${JSON.stringify({ total: 10, medios: [], imputaciones: [], saldos: {} })})`);
  assert.strictEqual(vacio.ok, false);
});

// ── resumenMediosOP ───────────────────────────────────────────────

test('resumenMediosOP arma el texto corto', () => {
  assert.strictEqual(erp.run(`resumenMediosOP(${JSON.stringify([{ tipo: 'banco' }, { tipo: 'cheque' }, { tipo: 'cheque' }])})`), 'Transf. + 2 cheques');
  assert.strictEqual(erp.run(`resumenMediosOP(${JSON.stringify([{ tipo: 'caja' }])})`), 'Caja');
  assert.strictEqual(erp.run(`resumenMediosOP(${JSON.stringify([{ tipo: 'tarjeta' }, { tipo: 'cheque' }])})`), 'Tarjeta + Cheque');
  assert.strictEqual(erp.run(`resumenMediosOP([])`), '—');
});

// ── computeCtaCteProveedores ──────────────────────────────────────

test('computeCtaCteProveedores: facturas pendientes en USD menos pagos a cuenta (OP + asientos legacy)', () => {
  const r = erp.run(`computeCtaCteProveedores(${JSON.stringify({
    proveedores: [{ id: 'p1', nombre: 'Aceros SA' }, { id: 'p2', nombre: 'Sin deuda' }],
    facturas: [
      FA,                                                                    // 121000 ARS / TC 1000 = 121 USD
      { id: 'f2', nro: 'B-2', tipo: 'factura', proveedor_id: 'p1', moneda: 'USD', tipo_cambio: 1000, total: 50, fecha: '2026-08-10', fecha_vto: '2026-09-10' },
      NC,                                                                    // −21000 ARS sobre f1
    ],
    ordenesPago: [
      { id: 'op1', estado: 'confirmada', proveedor_id: 'p1', moneda: 'ARS', tipo_cambio: null, total: 30000,
        orden_pago_imputaciones: [{ factura_id: 'f1', monto: 20000, monto_factura: 20000 }] },   // 10000 ARS a cuenta
      { id: 'op2', estado: 'anulada', proveedor_id: 'p1', moneda: 'USD', tipo_cambio: 1000, total: 999, orden_pago_imputaciones: [] },
    ],
    asientos: [
      { id: 'a1', tipo: 'auto-pago', estado: 'confirmado', origen_tipo: 'pago', proveedor_id: 'p1', moneda: 'USD', tipo_cambio: 1000 }, // legacy: 5 USD
      { id: 'a2', tipo: 'auto-pago', estado: 'confirmado', origen_tipo: 'orden_pago', proveedor_id: 'p1', moneda: 'ARS' },             // ya contado vía OP
      { id: 'a3', tipo: 'auto-pago', estado: 'anulado', origen_tipo: 'pago', proveedor_id: 'p1', moneda: 'USD', tipo_cambio: 1000 },
    ],
    asientoLineas: [
      { asiento_id: 'a1', debe: 5, haber: 0 }, { asiento_id: 'a1', debe: 0, haber: 5 },
      { asiento_id: 'a2', debe: 30000, haber: 0 }, { asiento_id: 'a2', debe: 0, haber: 30000 },
      { asiento_id: 'a3', debe: 100, haber: 0 }, { asiento_id: 'a3', debe: 0, haber: 100 },
    ],
    tcHoy: 1000,
  })})`);
  const p1 = r.find(x => x.proveedor.id === 'p1');
  assert.ok(p1);
  // f1: 121000 − 21000 NC − 20000 imputado = 80000 ARS = 80 USD ; f2: 50 USD
  assert.strictEqual(p1.facturas.length, 2);
  assert.strictEqual(p1.facturas.find(f => f.id === 'f1').saldo, 80000);
  assert.strictEqual(p1.deudaFacturasUSD, 130);
  // a cuenta: OP1 remanente 10000 ARS (TC hoy 1000 → 10 USD) + legacy 5 USD
  assert.strictEqual(p1.aCuentaUSD, 15);
  assert.strictEqual(p1.saldoUSD, 115);
  const p2 = r.find(x => x.proveedor.id === 'p2');
  assert.strictEqual(p2.saldoUSD, 0);
  assert.strictEqual(p2.facturas.length, 0);
});

test('computeCtaCteProveedores: factura totalmente pagada no aparece como pendiente', () => {
  const r = erp.run(`computeCtaCteProveedores(${JSON.stringify({
    proveedores: [{ id: 'p1', nombre: 'X' }],
    facturas: [FA],
    ordenesPago: [{ id: 'op1', estado: 'confirmada', proveedor_id: 'p1', moneda: 'ARS', total: 121000,
      orden_pago_imputaciones: [{ factura_id: 'f1', monto: 121000, monto_factura: 121000 }] }],
    asientos: [], asientoLineas: [], tcHoy: 1000,
  })})`);
  assert.strictEqual(r[0].facturas.length, 0);
  assert.strictEqual(r[0].saldoUSD, 0);
});
