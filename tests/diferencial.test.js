// Tests del sprint "diferencial" (2026-07-31): facturación mensual y
// cash-flow proyectado 30/60/90.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

// ── computeVentasPorMes ───────────────────────────────────────────

test('computeVentasPorMes arma 12 meses corridos y suma por mes (anuladas afuera)', () => {
  const ventas = [
    { fecha: '2026-07-05', total: 1000, estado: 'entregado' },
    { fecha: '2026-07-20', total: 500, estado: 'pendiente' },
    { fecha: '2026-06-01', total: 300, estado: 'facturado' },
    { fecha: '2026-07-10', total: 999, estado: 'anulada' },   // no cuenta
    { fecha: '2025-06-10', total: 800, estado: 'entregado' }, // fuera de ventana
  ];
  const r = erp.run(`computeVentasPorMes(${JSON.stringify(ventas)},'2026-07',12)`);
  assert.strictEqual(r.length, 12);
  assert.strictEqual(r[0].ym, '2025-08');       // arranca 11 meses atrás
  assert.strictEqual(r[11].ym, '2026-07');
  assert.strictEqual(r[11].total, 1500);
  assert.strictEqual(r[10].total, 300);
});

test('computeVentasPorMes cruza el cambio de año sin agujeros', () => {
  const r = erp.run(`computeVentasPorMes([],'2026-02',4)`);
  assert.deepStrictEqual(r.map(x => x.ym).join(','), '2025-11,2025-12,2026-01,2026-02');
});

// ── computeCashflowProyectado ─────────────────────────────────────

test('cash-flow: cta cte FIFO + cheques + facturas de proveedor en sus ventanas', () => {
  const datos = {
    cuentas: [{
      // cliente debe 1000+500, pagó 800 → FIFO deja 200 del cargo viejo (vencido) y 500 a 30d
      totPagos: 800,
      cargos: [
        { fecha: '2026-06-01', venc: '2026-07-01', monto: 1000 },  // vencido
        { fecha: '2026-07-20', venc: '2026-08-15', monto: 500 },   // ~15 días
      ],
    }],
    cheques: [
      { tipo: 'recibido', estado: 'en_cartera', fecha_pago: '2026-08-20', monto: 300, moneda: 'USD' },
      { tipo: 'recibido', estado: 'acreditado', fecha_pago: '2026-08-20', monto: 999, moneda: 'USD' }, // ya cobrado: no
      { tipo: 'emitido', estado: 'entregado', fecha_pago: '2026-09-15', monto: 130000, moneda: 'ARS', tipo_cambio: 1300 }, // 100 USD a 31-60d
    ],
    ocs: [
      { factura_vto: '2026-10-20', estado: 'facturada', total: 400, moneda: 'USD' },  // 61-90d
      { factura_vto: '2026-08-01', estado: 'anulada', total: 999, moneda: 'USD' },    // anulada: no
    ],
    facturas: [
      { fecha_vto: '2026-08-05', total: 50, moneda: 'USD', tipo: 'factura' },              // sin OC, 30d
      { fecha_vto: '2026-08-05', total: 999, moneda: 'USD', tipo: 'nota_credito' },        // NC: no
      { fecha_vto: '2026-08-05', total: 999, moneda: 'USD', tipo: 'factura', oc_id: 'x' }, // con OC: va por la OC
    ],
  };
  const r = erp.run(`computeCashflowProyectado(${JSON.stringify(datos)},'2026-07-31')`);
  assert.strictEqual(r.ing.vencido, 200);
  assert.strictEqual(r.ing.d30, 800);            // 500 cta cte + 300 cheque
  assert.strictEqual(r.egr.d30, 50);
  assert.strictEqual(r.egr.d60, 100);            // cheque emitido ARS→USD
  assert.strictEqual(r.egr.d90, 400);
  assert.strictEqual(r.netoAcum, 200 + 800 - 50 - 100 - 400);
});

test('cash-flow vacío da todo en cero', () => {
  const r = erp.run(`computeCashflowProyectado({},'2026-07-31')`);
  assert.strictEqual(r.netoAcum, 0);
  assert.strictEqual(r.ing.d30 + r.egr.d30, 0);
});
