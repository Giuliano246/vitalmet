// Tests de las funciones puras del rollup de eficiencia (Paquete 1C).
// computeEficienciaPorOperacion / computePausasPorMotivo / computeEficienciaPorPieza
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

// Fixtures generadas DENTRO del contexto vm (los objetos no cruzan bien el límite).
// OPR(id, orden, nombre, estMin) — operación completada.
// ENT(op, tipo, startMin, endMin, motivo) — entry con offsets en minutos sobre una época fija.
const FIX = `
  const OPR=(id,orden,nombre,est)=>({id,orden_id:orden,nombre,tiempo_estimado_min:est,estado:'completada'});
  const ENT=(op,tipo,startMin,endMin,motivo)=>({operacion_id:op,tipo,motivo:motivo||null,
    started_at:new Date(1700000000000+startMin*60000).toISOString(),
    ended_at:endMin==null?null:new Date(1700000000000+endMin*60000).toISOString()});
`;

test('computeEficienciaPorOperacion agrupa por nombre normalizado y calcula eff', () => {
  const r = erp.run(`(()=>{${FIX}
    const opers=[OPR('a','o1','Torneado',60),OPR('b','o2','torneado ',30),OPR('c','o1','Fresado',45)];
    const entries=[ENT('a','productivo',0,80),ENT('b','productivo',0,40),ENT('c','productivo',0,45),ENT('a','pausa',80,90,'Setup')];
    return computeEficienciaPorOperacion(opers,entries);
  })()`);
  const torneado = r.find(x => x.nombre === 'torneado');
  assert.strictEqual(torneado.estMin, 90);
  assert.strictEqual(torneado.realMin, 120); // las pausas NO cuentan
  assert.strictEqual(torneado.eff, 75);      // 90/120
  assert.strictEqual(torneado.n, 2);
  const fresado = r.find(x => x.nombre === 'fresado');
  assert.strictEqual(fresado.eff, 100);
  // orden descendente por tiempo real
  assert.ok(r[0].realMin >= r[r.length - 1].realMin);
});

test('computeEficienciaPorOperacion devuelve eff null sin datos suficientes', () => {
  const r = erp.run(`(()=>{${FIX}
    const opers=[OPR('a','o1','Rectificado',0)];       // sin estimado
    const entries=[ENT('a','productivo',0,30)];
    return computeEficienciaPorOperacion(opers,entries);
  })()`);
  assert.strictEqual(r[0].eff, null);
});

test('computePausasPorMotivo suma minutos y cuenta por motivo, orden desc', () => {
  const r = erp.run(`(()=>{${FIX}
    const entries=[ENT('a','pausa',0,30,'Setup / cambio herramienta'),ENT('b','pausa',0,15,'Setup / cambio herramienta'),
      ENT('c','pausa',0,10,'Rotura de máquina'),ENT('a','productivo',30,60)];
    return computePausasPorMotivo(entries);
  })()`);
  assert.deepStrictEqual({ ...r[0] }, { motivo: 'Setup / cambio herramienta', min: 45, count: 2 });
  assert.strictEqual(r.length, 2);
  assert.strictEqual(r[1].motivo, 'Rotura de máquina');
});

test('computeEficienciaPorPieza agrega por pieza de la orden', () => {
  const r = erp.run(`(()=>{${FIX}
    const ordenes=[{id:'o1',pieza:'Anillo BX-156'},{id:'o2',pieza:'Anillo BX-156'},{id:'o3',pieza:'Unión 2"'}];
    const opers=[OPR('a','o1','Torneado',60),OPR('b','o2','Torneado',60),OPR('c','o3','Fresado',30)];
    const entries=[ENT('a','productivo',0,50),ENT('b','productivo',0,70),ENT('c','productivo',0,60)];
    return computeEficienciaPorPieza(ordenes,opers,entries);
  })()`);
  const bx = r.find(x => x.pieza === 'Anillo BX-156');
  assert.strictEqual(bx.estMin, 120);
  assert.strictEqual(bx.realMin, 120);
  assert.strictEqual(bx.eff, 100);
  assert.strictEqual(bx.nOps, 2);
  const union = r.find(x => x.pieza === 'Unión 2"');
  assert.strictEqual(union.eff, 50); // 30 est / 60 real
});
