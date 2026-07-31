// Tests del sprint "calidad certificable" (2026-07-31): KPIs de la
// revisión por la dirección.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const DATOS = {
  ventas: [
    { fecha_entregado: '2026-06-10', fecha_entrega_hasta: '2026-06-15' }, // a tiempo
    { fecha_entregado: '2026-06-20', fecha_entrega_hasta: '2026-06-15' }, // tarde
    { fecha_entregado: '2026-01-05', fecha_entrega_hasta: '2026-01-10' }, // fuera del período
    { fecha_entregado: null, fecha_entrega_hasta: '2026-06-30' },         // sin entregar: no cuenta
  ],
  ncs: [
    { fecha: '2026-06-05', estado: 'abierta' },
    { fecha: '2026-02-01', estado: 'abierta' },   // vieja pero sigue abierta
    { fecha: '2026-06-12', estado: 'cerrada' },
  ],
  capas: [
    { estado: 'abierta', fecha_compromiso: '2026-05-01' },  // vencida
    { estado: 'abierta', fecha_compromiso: '2026-12-01' },
    { estado: 'cerrada', fecha_compromiso: '2026-05-01' },
  ],
  herramientas: [
    { requiere_calibracion: true, estado: 'en-uso', vencimiento_calibracion: '2026-01-01' }, // vencida
    { requiere_calibracion: true, estado: 'en-uso', vencimiento_calibracion: '2027-01-01' },
    { requiere_calibracion: true, estado: 'dada-de-baja', vencimiento_calibracion: '2026-01-01' }, // baja: no cuenta
    { requiere_calibracion: false },
  ],
  auditorias: [
    { estado: 'cerrada', fecha_planificada: '2026-06-01', fecha_realizada: '2026-06-03' },
    { estado: 'planificada', fecha_planificada: '2026-06-20' },
    { estado: 'planificada', fecha_planificada: '2025-11-01' }, // fuera del período
  ],
};

test('computeKpisCalidad arma el snapshot completo del período', () => {
  const k = erp.run(`computeKpisCalidad(${JSON.stringify(DATOS)},'2026-06-01','2026-06-30','2026-07-31')`);
  assert.strictEqual(k.entregas, 2);
  assert.strictEqual(k.entregasATiempo, 1);
  assert.strictEqual(k.otdPct, 50);
  assert.strictEqual(k.ncNuevas, 2);          // las 2 con fecha de junio
  assert.strictEqual(k.ncAbiertas, 2);        // total abiertas, sin importar fecha
  assert.strictEqual(k.capaAbiertas, 2);
  assert.strictEqual(k.capaVencidas, 1);
  assert.strictEqual(k.calibVencidas, 1);     // la dada de baja no cuenta
  assert.strictEqual(k.auditoriasPlanificadas, 2);
  assert.strictEqual(k.auditoriasCerradas, 1);
});

test('computeKpisCalidad sin entregas con compromiso da OTD null (s/d)', () => {
  const k = erp.run(`computeKpisCalidad(${JSON.stringify({ ventas: [], ncs: [], capas: [], herramientas: [], auditorias: [] })},'2026-06-01','2026-06-30','2026-07-31')`);
  assert.strictEqual(k.otdPct, null);
  assert.strictEqual(k.ncAbiertas, 0);
});
