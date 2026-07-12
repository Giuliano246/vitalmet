// Tests de los helpers puros de planta.html (Modo Planta).
// Mismo patrón vm que _harness.js pero extrayendo el script de planta.html.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function loadPlanta() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'planta.html'), 'utf8');
  const m = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!m) throw new Error('No se encontró <script> inline en planta.html');
  const mockEl = { style: {} };
  const sandbox = {
    document: { getElementById: () => mockEl, addEventListener() {}, querySelectorAll: () => [] },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    location: { search: '', href: 'http://test/' },
    fetch: () => Promise.reject(new Error('sin red en tests')),
    confirm: () => false,
    setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
    URLSearchParams, console, Date,
  };
  sandbox.window = sandbox;
  const ctx = vm.createContext(sandbox);
  vm.runInContext(m[1], ctx, { filename: 'planta.html#script' });
  return { run: (code) => vm.runInContext(code, ctx) };
}

const p = loadPlanta();

test('fmtTimerSec formatea HH:MM:SS', () => {
  assert.strictEqual(p.run('fmtTimerSec(0)'), '00:00:00');
  assert.strictEqual(p.run('fmtTimerSec(59)'), '00:00:59');
  assert.strictEqual(p.run('fmtTimerSec(3661)'), '01:01:01');
});

test('openOf encuentra solo la entry abierta del tipo pedido', () => {
  const r = p.run(`(()=>{
    entries=[
      {id:'e1',operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T11:00:00Z'},
      {id:'e2',operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T12:00:00Z',ended_at:null},
      {id:'e3',operacion_id:'b',tipo:'pausa',started_at:'2026-07-12T12:00:00Z',ended_at:null},
    ];
    return {
      prodA:(openOf('a','productivo')||{}).id||null,
      pausaA:openOf('a','pausa'),
      pausaB:(openOf('b','pausa')||{}).id||null,
    };
  })()`);
  assert.strictEqual(r.prodA, 'e2');
  assert.strictEqual(r.pausaA, null);
  assert.strictEqual(r.pausaB, 'e3');
});

test('holdPrevioSinFirmar bloquea solo pasos posteriores a un hold sin firma', () => {
  const r = p.run(`(()=>{
    pasos=[
      {id:'p1',secuencia:1,tipo_punto:'hold',signoff_at:null},
      {id:'p2',secuencia:2,tipo_punto:'normal',signoff_at:null},
      {id:'p3',secuencia:3,tipo_punto:'witness',signoff_at:null},
    ];
    return {
      p1:holdPrevioSinFirmar(pasos[0]),
      p2:holdPrevioSinFirmar(pasos[1]),
      p3Firmado:(()=>{pasos[0].signoff_at='2026-07-12T10:00:00Z';return holdPrevioSinFirmar(pasos[2]);})(),
    };
  })()`);
  assert.strictEqual(r.p1, false);   // el propio hold no se auto-bloquea
  assert.strictEqual(r.p2, true);    // posterior a hold sin firmar
  assert.strictEqual(r.p3Firmado, false); // hold ya firmado → libre
});

test('minutosCerrados suma solo entries productivas cerradas del paso', () => {
  const r = p.run(`(()=>{
    entries=[
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T10:30:00Z'},
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T11:00:00Z',ended_at:'2026-07-12T11:15:00Z'},
      {operacion_id:'a',tipo:'pausa',started_at:'2026-07-12T10:30:00Z',ended_at:'2026-07-12T11:00:00Z'},
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T12:00:00Z',ended_at:null},
      {operacion_id:'b',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T10:10:00Z'},
    ];
    return minutosCerrados('a');
  })()`);
  assert.strictEqual(r, 45);
});
