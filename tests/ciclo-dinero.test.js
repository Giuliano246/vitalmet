// Tests del sprint "ciclo del dinero" (2026-07-31): retenciones en
// cobranzas, comprobantes AFIP con signo y costo real de OP.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

// ── armarLineasCobro ──────────────────────────────────────────────

test('armarLineasCobro sin retenciones = cobro clásico de 2 líneas', () => {
  const r = erp.run(`armarLineasCobro(${JSON.stringify({
    monto: 1000, retenciones: [],
    ctaMedio: { id: 'caja', nombre: 'CAJA' },
    ctaDeudores: { id: 'deu', nombre: 'DEUDORES' },
    tercero: 'YPF',
  })})`);
  assert.strictEqual(r.lineas.length, 2);
  assert.strictEqual(r.lineas[0].debe, 1000);
  assert.strictEqual(r.lineas[1].haber, 1000);
  assert.strictEqual(r.totalRet, 0);
  assert.strictEqual(r.totalAplicado, 1000);
});

test('armarLineasCobro con retenciones: debe por cada una, Deudores por el total', () => {
  const r = erp.run(`armarLineasCobro(${JSON.stringify({
    monto: 850, // YPF paga 850 y retiene 100+50
    retenciones: [
      { tipo: 'ganancias', certificado_nro: 'C-001', monto: 100, cuenta_id: 'ret-g' },
      { tipo: 'iibb', certificado_nro: 'C-002', jurisdiccion: 'Buenos Aires', monto: 50, cuenta_id: 'ret-ib' },
    ],
    ctaMedio: { id: 'bco', nombre: 'BANCO' },
    ctaDeudores: { id: 'deu', nombre: 'DEUDORES' },
    tercero: 'YPF',
  })})`);
  assert.strictEqual(r.lineas.length, 4);
  assert.strictEqual(r.lineas[0].debe, 850);              // banco
  assert.strictEqual(r.lineas[1].debe, 100);              // ret ganancias
  assert.strictEqual(r.lineas[1].cuenta_id, 'ret-g');
  assert.ok(r.lineas[1].descripcion.includes('C-001'));
  assert.strictEqual(r.lineas[2].debe, 50);               // ret iibb
  assert.ok(r.lineas[2].descripcion.includes('Buenos Aires'));
  assert.strictEqual(r.lineas[3].haber, 1000);            // deudores por el total
  assert.strictEqual(r.totalRet, 150);
  assert.strictEqual(r.totalAplicado, 1000);
});

test('armarLineasCobro ignora retenciones en cero o negativas', () => {
  const r = erp.run(`armarLineasCobro(${JSON.stringify({
    monto: 500,
    retenciones: [{ tipo: 'suss', monto: 0, cuenta_id: 'x' }, { tipo: 'iva', monto: -5, cuenta_id: 'y' }],
    ctaMedio: { id: 'caja', nombre: 'CAJA' },
    ctaDeudores: { id: 'deu', nombre: 'DEUDORES' },
    tercero: 'Cliente',
  })})`);
  assert.strictEqual(r.lineas.length, 2);
  assert.strictEqual(r.totalAplicado, 500);
});

// ── cbteAfipInfo / alicuotaImplicita ──────────────────────────────

test('cbteAfipInfo: letra y signo por código AFIP', () => {
  const fa = erp.run(`cbteAfipInfo(1)`);
  assert.strictEqual(fa.label, 'FA-A');
  assert.strictEqual(fa.signo, 1);
  const ncA = erp.run(`cbteAfipInfo(3)`);
  assert.strictEqual(ncA.label, 'NC-A');
  assert.strictEqual(ncA.signo, -1);
  const ncB = erp.run(`cbteAfipInfo(8)`);
  assert.strictEqual(ncB.signo, -1);
  const desconocido = erp.run(`cbteAfipInfo(999)`);
  assert.strictEqual(desconocido.signo, 1);
});

test('alicuotaImplicita detecta las alícuotas legales con tolerancia', () => {
  assert.strictEqual(erp.run(`alicuotaImplicita(1000,210)`), 21);
  assert.strictEqual(erp.run(`alicuotaImplicita(1000,105)`), 10.5);
  assert.strictEqual(erp.run(`alicuotaImplicita(1000,270)`), 27);
  assert.strictEqual(erp.run(`alicuotaImplicita(999.95,210)`), 21); // redondeo del emisor
  assert.strictEqual(erp.run(`alicuotaImplicita(1000,0)`), 0);
  assert.strictEqual(erp.run(`alicuotaImplicita(0,210)`), 0);
  assert.strictEqual(erp.run(`alicuotaImplicita(1000,150)`), 15);   // no legal → % calculado
});

// ── computeCostoRealOP ────────────────────────────────────────────

test('computeCostoRealOP: MP + tiempo productivo cerrado + overhead, por unidad', () => {
  const r = erp.run(`computeCostoRealOP(${JSON.stringify({
    op: { cantidad: 10, kg_usados: 20 },
    barra: { costo_usd_unidad: 5 },          // MP: 20 × 5 = 100
    pasos: [{ id: 'p1', tarifa_maquina_usd: 12 }],
    entries: [
      { operacion_id: 'p1', tipo: 'productivo', started_at: '2026-07-01T10:00:00Z', ended_at: '2026-07-01T11:00:00Z' }, // 60 min
      { operacion_id: 'p1', tipo: 'pausa', started_at: '2026-07-01T11:00:00Z', ended_at: '2026-07-01T12:00:00Z' },      // no cuenta
      { operacion_id: 'p1', tipo: 'productivo', started_at: '2026-07-01T12:00:00Z', ended_at: null },                    // abierta, no cuenta
    ],
    tarifaOp: 18,                             // tiempo: 1h × (18+12) = 30
    overheadPct: 10,                          // (100+30) × 10% = 13
  })})`);
  assert.strictEqual(r.costoMP, 100);
  assert.strictEqual(r.costoTiempo, 30);
  assert.strictEqual(r.overhead, 13);
  assert.strictEqual(r.totalOP, 143);
  assert.strictEqual(r.totalUnidad, 14.3);   // 143 / 10 unidades
});

test('computeCostoRealOP sin barra ni tiempos da cero (no rompe)', () => {
  const r = erp.run(`computeCostoRealOP(${JSON.stringify({ op: { cantidad: 5 } })})`);
  assert.strictEqual(r.totalOP, 0);
  assert.strictEqual(r.totalUnidad, 0);
});
