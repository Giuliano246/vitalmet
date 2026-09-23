// Test de Sueldos 083 — fix round 1 (R32): _ganAcumulados tomaba los
// acumulados de SAC de la liquidación confirmada MÁS VIEJA en vez de la más
// reciente, porque `liquidaciones` llega ordenada periodo.desc (como la
// carga el TBL) y la función usaba el último elemento del array SIN
// reordenar. Este test reproduce ese orden real y verifica que, tras el
// fix, `sac_prorrateado_acum` sale del mes más reciente (febrero), no del
// más viejo (enero).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

test('_ganAcumulados: rem_gravada_acum suma, retenido_previo = Σ900 − Σ901, sac_prorrateado_acum sale del mes MÁS RECIENTE (no del más viejo)', () => {
  // Listadas en el orden real que entrega el TBL: periodo.desc (más nuevo primero).
  const liquidaciones = [
    { // Marzo 2026 — mismo período que se está preguntando (2026-03-01): debe EXCLUIRSE.
      id: 'l-mar', periodo: '2026-03-01', tipo: 'mensual', estado: 'confirmada', created_at: '2026-04-01T00:00:00Z',
      liquidacion_items: [{ empleado_id: 'e1', bruto: 9999, aportes: 0,
        ganancias: { rem_gravada_mes: 9999, sac_prorrateado_acum: 999, sac_real_acum: 999 },
        liquidacion_conceptos: [{ codigo: '900', importe: 9999 }] }],
    },
    { // Borrador de mediados de febrero — debe EXCLUIRSE (no está confirmada), aunque su
      // período sea más reciente que el de la liquidación de febrero confirmada.
      id: 'l-feb-borr', periodo: '2026-02-20', tipo: 'quincena2', estado: 'borrador', created_at: '2026-02-21T00:00:00Z',
      liquidacion_items: [{ empleado_id: 'e1', bruto: 5000, aportes: 0,
        ganancias: { rem_gravada_mes: 5000, sac_prorrateado_acum: 500, sac_real_acum: 500 },
        liquidacion_conceptos: [{ codigo: '900', importe: 500 }] }],
    },
    { // Febrero 2026 confirmada — el mes MÁS RECIENTE que debe contar como "last".
      id: 'l-feb', periodo: '2026-02-01', tipo: 'mensual', estado: 'confirmada', created_at: '2026-03-01T00:00:00Z',
      liquidacion_items: [{ empleado_id: 'e1', bruto: 200, aportes: 0,
        ganancias: { rem_gravada_mes: 200, sac_prorrateado_acum: 20, sac_real_acum: 0 },
        liquidacion_conceptos: [{ codigo: '900', importe: 8 }, { codigo: '901', importe: 2 }] }],
    },
    { // Enero 2026 confirmada — el mes MÁS VIEJO (lo que el bug tomaba como "last").
      id: 'l-ene', periodo: '2026-01-01', tipo: 'mensual', estado: 'confirmada', created_at: '2026-02-01T00:00:00Z',
      liquidacion_items: [{ empleado_id: 'e1', bruto: 100, aportes: 0,
        ganancias: { rem_gravada_mes: 100, sac_prorrateado_acum: 10, sac_real_acum: 0 },
        liquidacion_conceptos: [{ codigo: '900', importe: 5 }] }],
    },
  ];
  erp.set({ liquidaciones });
  const r = erp.run("_ganAcumulados('e1','2026','2026-03-01')");
  // rem_gravada_acum = Σ rem_gravada_mes de enero + febrero (marzo y el borrador quedan afuera)
  assert.equal(r.rem_gravada_acum, 300);
  // retenido_previo = Σ 900 (5 + 8) − Σ 901 (2) = 11
  assert.equal(r.retenido_previo, 11);
  // sac_prorrateado_acum debe salir de FEBRERO (20), no de enero (10) ni del borrador (500) ni de marzo (999)
  assert.equal(r.sac_prorrateado_acum, 20);
  assert.equal(r.sac_real_acum, 0);
});

test('_ganAcumulados: sin liquidaciones confirmadas previas del año devuelve null', () => {
  erp.set({ liquidaciones: [
    { id: 'l-mar', periodo: '2026-03-01', tipo: 'mensual', estado: 'confirmada', created_at: '2026-04-01T00:00:00Z',
      liquidacion_items: [{ empleado_id: 'e1', bruto: 100, aportes: 0, ganancias: null, liquidacion_conceptos: [] }] },
  ] });
  const r = erp.run("_ganAcumulados('e1','2026','2026-03-01')");
  assert.equal(r, null);
});
