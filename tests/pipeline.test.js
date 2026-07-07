// Tests de computePipelineMetrics (Paquete 3E).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('computePipelineMetrics calcula ciclo, ganado/perdido y aging', () => {
  const r = erp.run(`(()=>{
    const ps=[
      {nro:'P-1',cliente:'A',estado:'convertido',total:'1000',fecha:'2026-06-01',updated_at:'2026-06-11T00:00:00Z'},
      {nro:'P-2',cliente:'B',estado:'rechazado',total:'500',fecha:'2026-06-05',updated_at:'2026-06-25T00:00:00Z'},
      {nro:'P-3',cliente:'C',estado:'enviado',total:'800',fecha:'2026-06-27'},
    ];
    return computePipelineMetrics(ps,'2026-07-07');
  })()`);
  assert.strictEqual(r.cicloPromedioDias, 15); // (10+20)/2
  assert.strictEqual(Array.from(r.agingAbiertos)[0].dias, 10);
  assert.strictEqual(Array.from(r.agingAbiertos)[0].nro, 'P-3');
  const jun = Array.from(r.ganado6m).find(m => m.mes === '2026-06');
  assert.strictEqual(jun.ganado, 1000);
  assert.strictEqual(jun.perdido, 500);
});

test('computePipelineMetrics sin decididos devuelve ciclo null', () => {
  const r = erp.run(`computePipelineMetrics([{nro:'P-9',cliente:'X',estado:'borrador',total:'10',fecha:'2026-07-01'}],'2026-07-07')`);
  assert.strictEqual(r.cicloPromedioDias, null);
  assert.strictEqual(r.agingAbiertos.length, 0);
});
