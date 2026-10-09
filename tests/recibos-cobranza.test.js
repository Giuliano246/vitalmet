// Tests de recibos de cobranza y cuenta corriente por comprobante (mig 089):
// saldo por factura emitida, TC de la factura, validación del recibo y la
// cuenta corriente en pesos y en dólares.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;
const run = code => JSON.parse(erp.run(`JSON.stringify(${code})`));
const HOY = '2026-10-09';
const cc = input => run(`computeCtaCteClientes(${J({ hoy: HOY, tcHoy: 1500, ...input })})`);

const CLI = [{ id: 'c1', nombre: 'ACME SA', cuit: '30-50001091-2' }];
const VENTA = { id: 'v1', cliente_id: 'c1', cliente: 'ACME SA', estado: 'facturado', total: '1000', fecha: '2026-09-01', condicion_pago: '30 días', nro_remito: 'R-1',
  venta_items: [{ cantidad: 10, precio_unitario: 100 }] };
// 1000 USD × TC 1400 = 1.400.000 neto + 21 % = 1.694.000
const FA = { id: 'f1', venta_id: 'v1', tipo_comprobante: 1, punto_venta: 4, numero: 10, fecha: '2026-09-01', doc_nro: '30500010912', imp_neto: 1400000, imp_iva: 294000, imp_total: 1694000, afip_environment: 'produccion' };

test('saldoFacturaEmitida: total − NC asociadas − imputaciones vivas; el exceso queda a favor', () => {
  const nc = { id: 'n1', tipo_comprobante: 3, factura_asociada_id: 'f1', imp_total: 94000 };
  const imp = run(`imputacionesRecibosVivas(${J([
    { estado: 'confirmado', recibo_imputaciones: [{ factura_id: 'f1', monto_factura: 600000 }] },
    { estado: 'anulado', recibo_imputaciones: [{ factura_id: 'f1', monto_factura: 999 }] }])})`);
  assert.deepStrictEqual(imp, { f1: 600000 });
  assert.deepStrictEqual(run(`saldoFacturaEmitida(${J(FA)},${J([FA, nc])},${J(imp)})`), { total: 1694000, nc: 94000, imputado: 600000, saldo: 1000000, exceso: 0 });
  assert.deepStrictEqual(run(`saldoFacturaEmitida(${J(FA)},${J([FA, nc])},${J({ f1: 1694000 })})`).exceso, 94000);
});

test('tcFacturaEmitida: el guardado, o el implícito de la venta (neto o total según la config)', () => {
  assert.strictEqual(run(`tcFacturaEmitida(${J({ ...FA, tc_usd: 1410 })},${J(VENTA)},false)`), 1410);
  assert.strictEqual(run(`tcFacturaEmitida(${J(FA)},${J(VENTA)},false)`), 1400);
  assert.strictEqual(run(`tcFacturaEmitida(${J(FA)},${J(VENTA)},true)`), 1694);
  assert.strictEqual(run(`tcFacturaEmitida(${J(FA)},null,false)`), null);
});

test('cta cte: la factura es el cargo, en pesos y con su equivalente en USD', () => {
  const [c] = cc({ clientes: CLI, ventas: [VENTA], facturasEmitidas: [FA] });
  assert.strictEqual(c.cargos.length, 1); // la venta facturada no se duplica
  assert.deepStrictEqual([c.saldoARS, c.saldo, c.cargos[0].tipo, c.cargos[0].venc], [1694000, 1210, 'Factura', '2026-10-01']);
  assert.deepStrictEqual([c.bucketsARS.d30, c.buckets.d30], [1694000, 1210]);
});

test('cta cte: recibo imputado baja esa factura; lo a cuenta va a la más vieja', () => {
  const FB = { ...FA, id: 'f2', venta_id: null, numero: 11, fecha: '2026-10-05', imp_neto: 100000, imp_iva: 21000, imp_total: 121000, cliente_id: 'c1' };
  const recibos = [{ id: 'r1', nro: 'REC-0001', estado: 'confirmado', cliente_id: 'c1', fecha: '2026-10-08', moneda: 'ARS', total: 221000,
    recibo_imputaciones: [{ factura_id: 'f2', monto: 121000, monto_factura: 121000 }] }];
  const [c] = cc({ clientes: CLI, ventas: [VENTA], facturasEmitidas: [FA, FB], recibos });
  const por = Object.fromEntries(c.cargos.map(x => [x.id, x.saldoARS]));
  assert.deepStrictEqual(por, { f1: 1594000, f2: 0 });
  assert.strictEqual(c.saldoARS, 1594000);
  assert.strictEqual(c.pagos.length, 1);
});

test('cta cte: cobro viejo (asiento sin recibo) en pesos baja la factura aunque no tenga TC', () => {
  const asientos = [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: '2026-10-02', moneda: 'ARS', origen_tipo: 'cobro' },
    { id: 'a2', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: '2026-10-03', moneda: 'ARS', origen_tipo: 'recibo' }];
  const asientoLineas = [{ asiento_id: 'a1', debe: 694000 }, { asiento_id: 'a2', debe: 50000 }];
  const [c] = cc({ clientes: CLI, ventas: [VENTA], facturasEmitidas: [FA], asientos, asientoLineas });
  assert.strictEqual(c.saldoARS, 1000000); // el asiento de un recibo no se cuenta dos veces
});

test('cta cte: venta entregada sin factura queda aparte en USD; cobro USD la cancela en USD', () => {
  const v2 = { id: 'v2', cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '500', fecha: '2026-10-01', condicion_pago: 'contado', nro_remito: 'R-2' };
  const asientos = [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: '2026-10-02', moneda: 'USD', tipo_cambio: 1200 }];
  const sin = cc({ clientes: CLI, ventas: [v2] })[0];
  assert.deepStrictEqual([sin.saldo, sin.sinFacturarUSD, sin.saldoARS], [500, 500, 750000]);
  const con = cc({ clientes: CLI, ventas: [v2], asientos, asientoLineas: [{ asiento_id: 'a1', debe: 500 }] })[0];
  assert.deepStrictEqual([con.saldo, con.saldoARS, con.aFavor], [0, 0, 0]);
});

test('cta cte: NC libre y pago de más quedan a favor; homologación no cuenta', () => {
  const ncLibre = { id: 'n9', tipo_comprobante: 3, punto_venta: 4, numero: 2, fecha: '2026-10-06', doc_nro: '30500010912', imp_total: 2000000, afip_environment: 'produccion' };
  const homo = { ...FA, id: 'fh', numero: 99, afip_environment: 'homologacion', venta_id: null };
  const [c] = cc({ clientes: CLI, ventas: [VENTA], facturasEmitidas: [FA, ncLibre, homo] });
  assert.deepStrictEqual([c.cargos.length, c.aFavorARS, c.saldoARS], [1, 306000, -306000]);
});

test('facturasPendientesCliente y validarRecibo', () => {
  const pend = run(`facturasPendientesCliente('c1',${J({ clientes: CLI, ventas: [VENTA], facturasEmitidas: [FA, { ...FA, id: 'fx', numero: 12, doc_nro: '20123456786', venta_id: null }], recibos: [] })})`);
  assert.deepStrictEqual(pend.map(p => [p.f.id, p.saldo, p.venc]), [['f1', 1694000, '2026-10-01']]);
  const base = { total: 1000, saldos: { f1: 800 } };
  const v = a => run(`validarRecibo(${J({ ...base, ...a })})`);
  assert.strictEqual(v({ medios: [{ tipo: 'banco', monto: 1000, cuenta_contable_id: 'x' }], imputaciones: [{ factura_id: 'f1', monto: 800, monto_factura: 800 }] }).ok, true);
  assert.match(v({ medios: [{ tipo: 'banco', monto: 900, cuenta_contable_id: 'x' }], imputaciones: [] }).errores[0], /suman/);
  assert.match(v({ medios: [{ tipo: 'banco', monto: 1000, cuenta_contable_id: 'x' }], imputaciones: [{ factura_id: 'f1', monto: 900, monto_factura: 900 }] }).errores[0], /saldo/);
  assert.match(v({ medios: [{ tipo: 'cheque', monto: 1000, cuenta_contable_id: 'x', cheque: { numero: '' } }], imputaciones: [] }).errores[0], /cheque/);
  assert.match(v({ medios: [{ tipo: 'retencion', monto: 1000, cuenta_contable_id: 'x', retencion: { tipo: 'iibb' } }], imputaciones: [] }).errores[0], /jurisdicci/);
});
