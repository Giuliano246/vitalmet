'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'); const path = require('path');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CSV = fs.readFileSync(path.join(__dirname, '..', 'docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv'), 'utf8');

test('MARCAS_DEFAULT: remunerativo todo 1 salvo DIF/ESP; descuento todo 0; 540000 OS/FSR; 550000 + LRT', () => {
  assert.equal(run(`MARCAS_DEFAULT('remunerativo','110000')`), '111111111111100');
  assert.equal(run(`MARCAS_DEFAULT('descuento','810000')`), '000000000000000');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','540000')`), '000011110000000');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','550000')`), '000011110000100');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','520014')`), '000000000000000');
});
test('parseArcaPadron: 121 filas, BOM, marcas de 15, repetición', () => {
  const r = run(`parseArcaPadron(${J(CSV)})`);
  assert.equal(r.errores.length, 0); assert.equal(r.filas.length, 121);
  const jornal = r.filas.find(f => f.codigo === '4');
  assert.deepEqual(JSON.parse(JSON.stringify(jornal)), { codigo_arca: '110000', codigo: '4', nombre: 'JORNAL', repeticion: true, marcas: '111111111111100' });
  assert.equal(r.filas.find(f => f.codigo === '104').marcas, '000011110000000');
});
test('diffConceptosArca: sólo en ARCA, sólo en ERP, marcas distintas', () => {
  const padron = [{ codigo: '4', codigo_arca: '110000', marcas: '111111111111100' }, { codigo: '52', codigo_arca: '110000', marcas: '111111111111100' }];
  const cat = [{ codigo: '4', codigo_arca: '110000', marcas: '111111111111100', activo: true }, { codigo: '10', codigo_arca: '130001', marcas: '111111111111100', activo: true }, { codigo: '52', codigo_arca: '110000', marcas: '000000000000000', legacy: true }];
  const d = run(`diffConceptosArca(${J(padron)},${J(cat)})`);
  assert.deepEqual(JSON.parse(JSON.stringify(d.soloArca)), []); assert.deepEqual(JSON.parse(JSON.stringify(d.soloErp.map(c => c.codigo))), ['10']);
  assert.deepEqual(JSON.parse(JSON.stringify(d.marcasDistintas)), [{ codigo: '52', erp: '000000000000000', arca: '111111111111100' }]);
});
test('buildConceptosTxt: 195 posiciones, ASCII, marcas intercaladas con libres, sólo faltantes', () => {
  const cat = [{ codigo: '10', nombre: 'Horas extras 50 %', tipo: 'remunerativo', codigo_arca: '130001', repeticion: true, marcas: '111111111111100', activo: true },
               { codigo: '4', nombre: 'Jornal', tipo: 'remunerativo', codigo_arca: '110000', repeticion: true, marcas: '111111111111100', activo: true },
               { codigo: '52', nombre: 'x', tipo: 'remunerativo', codigo_arca: '110000', marcas: '111111111111100', activo: false, legacy: true }];
  const r = run(`buildConceptosTxt(${J(cat)},{soloFaltantes:true,padron:[{codigo:'4'}]})`);
  assert.equal(r.errores.length, 0); assert.equal(r.lineas.length, 1);
  const l = r.lineas[0]; assert.equal(l.length, 195);
  assert.equal(l.slice(0, 6), '130001'); assert.equal(l.slice(6, 16), '10        ');
  assert.equal(l.slice(16, 166).trim(), 'Horas extras 50 %'); assert.equal(l[166], '1');
  assert.equal(l.slice(166, 186), '11111111111 1 1 10 0');   // rep + 19 (igual al ejemplo de la planilla, pos. 167-186)
  assert.equal(r.txt.endsWith('\r\n'), true);
  const sin = run(`buildConceptosTxt([{codigo:'9',nombre:'A',tipo:'remunerativo',codigo_arca:null,marcas:'111111111111100',activo:true}],{})`);
  assert.match(sin.errores[0], /sin código ARCA/);
});
