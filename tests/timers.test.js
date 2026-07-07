// Tests de los helpers puros del multi-timer (Paquete 1A).
// openEntryOf / activeProductivos operan sobre arrays de op_time_entries.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

// Los objetos cruzan el límite del contexto vm, así que las aserciones
// devuelven primitivos calculados DENTRO del contexto (patrón del harness).

test('openEntryOf encuentra la entrada abierta del tipo pedido', () => {
  const r = erp.run(`(()=>{
    const entries=[
      {id:'e1',operacion_id:'a',tipo:'productivo',started_at:'2026-07-06T10:00:00Z',ended_at:'2026-07-06T11:00:00Z'},
      {id:'e2',operacion_id:'a',tipo:'productivo',started_at:'2026-07-06T12:00:00Z',ended_at:null},
      {id:'e3',operacion_id:'b',tipo:'pausa',started_at:'2026-07-06T12:00:00Z',ended_at:null},
    ];
    return {
      prodA: (openEntryOf(entries,'a','productivo')||{}).id||null,
      pausaA: openEntryOf(entries,'a','pausa'),
      pausaB: (openEntryOf(entries,'b','pausa')||{}).id||null,
      prodC: openEntryOf(entries,'c','productivo'),
    };
  })()`);
  assert.strictEqual(r.prodA, 'e2');
  assert.strictEqual(r.pausaA, null);
  assert.strictEqual(r.pausaB, 'e3');
  assert.strictEqual(r.prodC, null);
});

test('activeProductivos devuelve solo productivos abiertos', () => {
  const r = erp.run(`(()=>{
    const entries=[
      {id:'e1',operacion_id:'a',tipo:'productivo',started_at:'2026-07-06T10:00:00Z',ended_at:null},
      {id:'e2',operacion_id:'b',tipo:'productivo',started_at:'2026-07-06T10:00:00Z',ended_at:'2026-07-06T11:00:00Z'},
      {id:'e3',operacion_id:'c',tipo:'pausa',started_at:'2026-07-06T10:00:00Z',ended_at:null},
      {id:'e4',operacion_id:'d',tipo:'productivo',started_at:'2026-07-06T10:30:00Z',ended_at:null},
    ];
    return activeProductivos(entries).map(e=>e.id);
  })()`);
  assert.deepStrictEqual(Array.from(r), ['e1', 'e4']);
});
