'use strict';
const test = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('periodoRango arma desde/hasta del mes', () => {
  assert.deepEqual(erp.run(`periodoRango('2026-07')`), {desde:'2026-07-01', hasta:'2026-07-31'});
  assert.deepEqual(erp.run(`periodoRango('2026-02')`), {desde:'2026-02-01', hasta:'2026-02-28'});
  assert.deepEqual(erp.run(`periodoRango('2028-02')`), {desde:'2028-02-01', hasta:'2028-02-29'}); // bisiesto
  assert.equal(erp.run(`periodoRango('2026-13')`), null);
  assert.equal(erp.run(`periodoRango('')`), null);
});

test('csvCampo escapa ; comillas y saltos', () => {
  assert.equal(erp.run(`csvCampo('hola')`), 'hola');
  assert.equal(erp.run(`csvCampo('a;b')`), '"a;b"');
  assert.equal(erp.run(`csvCampo('di"jo')`), '"di""jo"');
  assert.equal(erp.run(`csvCampo(null)`), '');
});

test('csvArmar: BOM, separador ; y CRLF', () => {
  const s = erp.run(`csvArmar([['A','B'],['1','2;3']])`);
  assert.ok(s.startsWith('﻿'));
  assert.equal(s, '﻿A;B\r\n1;"2;3"\r\n');
});

test('csvNum y csvFecha en formato argentino', () => {
  assert.equal(erp.run(`csvNum(1234.5)`), '1234,50');
  assert.equal(erp.run(`csvNum(null)`), '0,00');
  assert.equal(erp.run(`csvFecha('2026-07-19')`), '19/07/2026');
  assert.equal(erp.run(`csvFecha(null)`), '');
});

test('crc32 valores conocidos', () => {
  // CRC32 de 'abc' = 0x352441C2 (vector estándar)
  assert.equal(erp.run(`crc32(new TextEncoder().encode('abc'))`), 0x352441C2);
  assert.equal(erp.run(`crc32(new Uint8Array(0))`), 0);
});

test('zipStore genera un ZIP store válido estructuralmente', () => {
  const bytes = erp.run(`Array.from(zipStore([{nombre:'a.csv', contenido:'hola'}]))`);
  const u = Uint8Array.from(bytes);
  const dv = new DataView(u.buffer);
  assert.equal(dv.getUint32(0, true), 0x04034b50);            // local file header
  assert.equal(dv.getUint32(u.length - 22, true), 0x06054b50); // EOCD al final
  assert.equal(dv.getUint16(u.length - 22 + 10, true), 1);     // 1 entrada
  const crcEsperado = erp.run(`crc32(new TextEncoder().encode('hola'))`);
  assert.equal(dv.getUint32(14, true), crcEsperado);
});

test('zipStore multiarchivo: offsets consistentes', () => {
  const bytes = erp.run(`Array.from(zipStore([{nombre:'a.txt',contenido:'AA'},{nombre:'b.txt',contenido:'BBBB'}]))`);
  const u = Uint8Array.from(bytes);
  const dv = new DataView(u.buffer);
  assert.equal(dv.getUint16(u.length - 22 + 10, true), 2);     // 2 entradas
  // Segundo local header arranca en 30+5+2 = 37 ('a.txt' = 5 chars, 'AA' = 2)
  assert.equal(dv.getUint32(37, true), 0x04034b50);
});
