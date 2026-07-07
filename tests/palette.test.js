// Tests del matching puro del command palette (Paquete 2A).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('paletteMatch: multi-término AND, scoring exacto > empieza > contiene', () => {
  const r = erp.run(`(()=>{
    const items=[
      {cat:'Clientes',label:'Yacimientos del Sur SA'},
      {cat:'Ventas',label:'V-00212 · Yacimientos del Sur SA'},
      {cat:'Clientes',label:'Sur Metal SRL'},
      {cat:'Ventas',label:'V-00212'},
    ];
    return {
      yaci: paletteMatch('yacim',items).map(i=>i.label),
      exact: paletteMatch('v-00212',items)[0].label,
      and: paletteMatch('sur metal',items).map(i=>i.label),
      vacio: paletteMatch('zzz',items).length,
    };
  })()`);
  assert.deepStrictEqual(Array.from(r.yaci), ['Yacimientos del Sur SA', 'V-00212 · Yacimientos del Sur SA']);
  assert.strictEqual(r.exact, 'V-00212');
  assert.deepStrictEqual(Array.from(r.and), ['Sur Metal SRL']);
  assert.strictEqual(r.vacio, 0);
});

test('paletteMatch limita a 4 por categoría', () => {
  const r = erp.run(`(()=>{
    const items=Array.from({length:9},(_,i)=>({cat:'Ventas',label:'V-'+i+' pepe'}));
    return paletteMatch('pepe',items).length;
  })()`);
  assert.strictEqual(r, 4);
});
