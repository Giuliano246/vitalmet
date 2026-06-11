// Tests de los cálculos de plata del ERP (decisión del consejo 2026-06-05:
// red de seguridad mínima sobre lo crítico).
//
// Correr con:  node --test tests/
//
// Cubre: cta. corriente (imputación FIFO + aging), costeo de PT
// (MP + tiempo + overhead + margen) y punto de reorden (safety stock).
// Los fixtures usan fechas relativas a hoy en el MEDIO de cada bucket
// (15/45/75/120 días) para que un corrimiento de ±1 día por huso
// horario nunca cambie el resultado.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./_harness');

const erp = load();

// Fecha local AAAA-MM-DD corrida `off` días desde hoy (igual idioma que el ERP)
function D(off) {
  const t = new Date(Date.now() + off * 86400000);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
}

function resetCtaCte() {
  erp.set({ clientes: [], ventas: [], asientos: [], asientoLineas: [] });
}

// ─── Helpers de parsing ──────────────────────────────────────────────

test('_diasCondicionPago: extrae días y trata contado como 0', () => {
  assert.equal(erp.run(`_diasCondicionPago('30 días')`), 30);
  assert.equal(erp.run(`_diasCondicionPago('60 dias fecha factura')`), 60);
  assert.equal(erp.run(`_diasCondicionPago('contado')`), 0);
  assert.equal(erp.run(`_diasCondicionPago(null)`), 0);
});

test('zNivelServicio: tabla normal estándar y default 0.95', () => {
  assert.equal(erp.run('zNivelServicio(0.95)'), 1.65);
  assert.equal(erp.run('zNivelServicio(0.99)'), 2.33);
  assert.equal(erp.run('zNivelServicio(undefined)'), 1.65);
});

// ─── Cuenta corriente: imputación FIFO + aging ───────────────────────

test('cta cte: venta entregada sin cobros queda como saldo en su bucket', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    // contado → venc = fecha = hace 45 días → bucket 31-60
    ventas: [{ cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '1000', fecha: D(-45), condicion_pago: 'contado', nro_remito: 'R-1' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r.length, 1);
  assert.equal(r[0].saldo, 1000);
  assert.equal(r[0].buckets.d60, 1000);
  assert.equal(r[0].buckets.d30 + r[0].buckets.d90 + r[0].buckets.mas90 + r[0].buckets.alDia, 0);
});

test('cta cte: condicion_pago corre el vencimiento (fecha -75d + 30 días = bucket 31-60)', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [{ cliente_id: 'c1', cliente: 'ACME SA', estado: 'facturado', total: '500', fecha: D(-75), condicion_pago: '30 días' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r[0].buckets.d60, 500);
});

test('cta cte: el cobro se imputa FIFO al cargo más viejo primero', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [
      { cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '1000', fecha: D(-45), condicion_pago: 'contado' },
      { cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '500', fecha: D(10), condicion_pago: 'contado' },
    ],
    asientos: [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: D(-5), moneda: 'USD' }],
    asientoLineas: [{ asiento_id: 'a1', debe: '1000' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r[0].saldo, 500);
  // El cargo vencido (más viejo) quedó cubierto; sobrevive solo el al día
  assert.equal(r[0].buckets.d60, 0);
  assert.equal(r[0].buckets.alDia, 500);
});

test('cta cte: cobro en ARS se convierte a USD por tipo_cambio', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [{ cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '1000', fecha: D(-15), condicion_pago: 'contado' }],
    asientos: [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: D(-5), moneda: 'ARS', tipo_cambio: '1000' }],
    asientoLineas: [{ asiento_id: 'a1', debe: '400000' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r[0].totPagos, 400);
  assert.equal(r[0].saldo, 600);
});

test('cta cte: cobro sin cliente_id se vincula por "Cobro de <nombre>" en la descripción', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [{ cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '1000', fecha: D(-15), condicion_pago: 'contado' }],
    asientos: [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', fecha: D(-2), moneda: 'USD', descripcion: 'Cobro de ACME SA — transferencia' }],
    asientoLineas: [{ asiento_id: 'a1', debe: '1000' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r[0].saldo, 0);
});

test('cta cte: ventas pendientes/anuladas y asientos borrador no generan movimientos', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [
      { cliente_id: 'c1', cliente: 'ACME SA', estado: 'pendiente', total: '1000', fecha: D(-15), condicion_pago: 'contado' },
      { cliente_id: 'c1', cliente: 'ACME SA', estado: 'anulado', total: '500', fecha: D(-15), condicion_pago: 'contado' },
    ],
    asientos: [{ id: 'a1', tipo: 'auto-cobranza', estado: 'borrador', cliente_id: 'c1', fecha: D(-2), moneda: 'USD' }],
    asientoLineas: [{ asiento_id: 'a1', debe: '100' }],
  });
  assert.equal(erp.run('computeCtaCte()').length, 0);
});

test('cta cte: pagos por encima de los cargos quedan como saldo a favor', () => {
  resetCtaCte();
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: [{ cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado', total: '100', fecha: D(-15), condicion_pago: 'contado' }],
    asientos: [{ id: 'a1', tipo: 'auto-cobranza', estado: 'confirmado', cliente_id: 'c1', fecha: D(-2), moneda: 'USD' }],
    asientoLineas: [{ asiento_id: 'a1', debe: '300' }],
  });
  const r = erp.run('computeCtaCte()');
  assert.equal(r[0].aFavor, 200);
  assert.equal(r[0].saldo, -200);
});

test('cta cte: aging completo — un cargo en cada bucket', () => {
  resetCtaCte();
  const offsets = { alDia: 10, d30: -15, d60: -45, d90: -75, mas90: -120 };
  erp.set({
    clientes: [{ id: 'c1', nombre: 'ACME SA' }],
    ventas: Object.values(offsets).map((off, i) => ({
      cliente_id: 'c1', cliente: 'ACME SA', estado: 'entregado',
      total: String(100 * (i + 1)), fecha: D(off), condicion_pago: 'contado',
    })),
  });
  // Spread: el objeto nace en el realm del vm y deepEqual estricto compara prototipos
  const b = { ...erp.run('computeCtaCte()')[0].buckets };
  assert.deepEqual(b, { alDia: 100, d30: 200, d60: 300, d90: 400, mas90: 500 });
});

// ─── Costeo de PT: MP + tiempo + overhead + margen ───────────────────

function setCosteoBase() {
  erp.set({
    currentEmpresa: { id: 'e1', tarifa_operario_usd_h: 20, overhead_pct: 10 },
    barras: [{ id: 'b1', costo_usd_unidad: '5' }],
    ops: [{ id: 'o1', barra_id: 'b1', kg_usados: '10' }],
    opOperaciones: [{ id: 's1', orden_id: 'o1', tarifa_maquina_usd: '10' }],
    opTimeEntries: [
      { operacion_id: 's1', tipo: 'productivo', started_at: '2026-01-01T10:00:00', ended_at: '2026-01-01T11:00:00' },
      { operacion_id: 's1', tipo: 'pausa', started_at: '2026-01-01T11:00:00', ended_at: '2026-01-01T12:00:00' },
      { operacion_id: 's1', tipo: 'productivo', started_at: '2026-01-01T12:00:00', ended_at: null },
    ],
    ventas: [], pts: [],
  });
}

test('costeo PT: MP = kg_usados × costo_unitario ÷ cantidad; solo cuenta tiempo productivo cerrado', () => {
  setCosteoBase();
  const c = erp.run(`computeCostoPT({ id: 'p1', orden_id: 'o1', cantidad: 2 })`);
  assert.equal(c.costoMP, 25);            // 10kg × US$5 ÷ 2
  assert.equal(c.costoTiempo, 15);        // 1h × (20+10) ÷ 2 — pausa y entry abierto NO suman
  assert.equal(c.overhead, 4);            // (25+15) × 10%
  assert.equal(c.total, 44);
});

test('costeo PT: margen usa precio de venta promedio ponderado', () => {
  setCosteoBase();
  erp.set({
    ventas: [{
      venta_items: [
        { producto_id: 'p1', precio_unitario: '100', cantidad: '1' },
        { producto_id: 'p1', precio_unitario: '50', cantidad: '3' },
      ],
    }],
  });
  const c = erp.run(`computeCostoPT({ id: 'p1', orden_id: 'o1', cantidad: 2 })`);
  assert.equal(c.precioVtaProm, 62.5);    // (100×1 + 50×3) ÷ 4
  assert.equal(c.margenUSD, 62.5 - 44);
  assert.ok(Math.abs(c.margenPct - ((62.5 - 44) / 62.5) * 100) < 1e-9);
});

test('costeo PT: sin ventas usa el precio_unitario del PT; sin OP el costo es solo overhead 0', () => {
  setCosteoBase();
  const c = erp.run(`computeCostoPT({ id: 'p9', orden_id: null, cantidad: 1, precio_unitario: '80' })`);
  assert.equal(c.costoMP, 0);
  assert.equal(c.costoTiempo, 0);
  assert.equal(c.total, 0);
  assert.equal(c.precioVtaProm, 80);
  assert.equal(c.margenPct, 100);
});

// ─── Reposición: punto de reorden + safety stock ─────────────────────

function setReposicionBase(kgDisponibles) {
  erp.set({
    materiales: [{ nombre: 'SAE 4140', lead_time_dias: '30', nivel_servicio: 0.95 }],
    barras: [{ id: 'b1', material: 'SAE 4140', kg_disponibles: String(kgDisponibles) }],
    // Consumo constante 60/mes en 3 meses → desvío 0 → safety stock 0
    ops: [
      { id: 'o1', barra_id: 'b1', kg_usados: '60', fecha: '2026-01-15' },
      { id: 'o2', barra_id: 'b1', kg_usados: '60', fecha: '2026-02-15' },
      { id: 'o3', barra_id: 'b1', kg_usados: '60', fecha: '2026-03-15' },
    ],
    ocItems: [], ordenesCompra: [], recepciones: [],
  });
}

test('reposición: consumo constante + lead time manual 30d → ROP = consumo mensual', () => {
  setReposicionBase(100);
  const r = erp.run(`calcReordenMaterial('SAE 4140')`);
  assert.equal(r.dProm, 60);
  assert.equal(r.ss, 0);
  assert.equal(r.rop, 60);
  assert.equal(r.fuenteLT, 'manual');
  assert.equal(r.bajo, false);
  assert.equal(r.aPedir, 0);
});

test('reposición: disponible ≤ ROP dispara el reorden con la cantidad a pedir', () => {
  setReposicionBase(50);
  const r = erp.run(`calcReordenMaterial('SAE 4140')`);
  assert.equal(r.bajo, true);
  assert.equal(r.aPedir, 10);             // 60 - 50
});

test('reposición: con 4+ compras el lead time se deriva de OC→recepción', () => {
  setReposicionBase(100);
  erp.set({
    ordenesCompra: [1, 2, 3, 4].map(i => ({ id: 'oc' + i, fecha: `2026-0${i}-01` })),
    ocItems: [1, 2, 3, 4].map(i => ({ id: 'it' + i, oc_id: 'oc' + i, material: 'SAE 4140' })),
    recepciones: [1, 2, 3, 4].map(i => ({ oc_item_id: 'it' + i, fecha: `2026-0${i}-21` })),
  });
  const r = erp.run(`calcReordenMaterial('SAE 4140')`);
  assert.equal(r.fuenteLT, 'compras');
  assert.equal(r.ltDias, 20);
  assert.equal(r.rop, 40);                // 60 × (20/30), sin desvío
});

test('reposición: material sin OPs queda marcado sinDatos y va al final', () => {
  erp.set({
    materiales: [],
    barras: [{ id: 'b1', material: 'INOX 316', kg_disponibles: '10' }],
    ops: [], ocItems: [], ordenesCompra: [], recepciones: [],
  });
  const todos = erp.run('calcReordenTodos()');
  assert.equal(todos.length, 1);
  assert.equal(todos[0].sinDatos, true);
  assert.equal(todos[0].bajo, false);
});
