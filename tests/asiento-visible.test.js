// El asiento de factura/NC fallaba en SILENCIO (console.warn + return):
// quedaban facturas con CAE sin asiento. Ahora los generadores LANZAN el
// motivo, el emisor lo muestra y el backfill lo reporta.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const reject = (code) => erp.run(`${code}.then(()=>null,e=>e.message)`);

test('generarAsientoFactura LANZA si falta la configuración contable', async () => {
  erp.run('configContable=null');
  const msg = await reject('generarAsientoFactura("x",{imp_neto:100,imp_iva:21,imp_total:121},{cliente:"c"})');
  assert.match(msg, /configuraci[oó]n contable/i);
});

test('generarAsientoFactura LANZA si las cuentas no resuelven', async () => {
  erp.run('configContable={cta_deudores:"a",cta_ventas_default:"b",cta_iva_debito:"c"}; cuentasContables=[];');
  const msg = await reject('generarAsientoFactura("x",{imp_neto:100,imp_iva:21,imp_total:121},{cliente:"c"})');
  assert.match(msg, /Deudores o Ventas/i);
});

test('generarAsientoFactura LANZA si hay IVA pero no hay cuenta de IVA Débito (evita asiento descuadrado)', async () => {
  erp.run('configContable={cta_deudores:"a",cta_ventas_default:"b",cta_iva_debito:null}; cuentasContables=[{id:"a",codigo:"1",nombre:"Deudores"},{id:"b",codigo:"4",nombre:"Ventas"}];');
  const msg = await reject('generarAsientoFactura("x",{imp_neto:100,imp_iva:21,imp_total:121},{cliente:"c"})');
  assert.match(msg, /IVA D[eé]bito/i);
});

test('generarAsientoNC LANZA si falta la configuración contable', async () => {
  erp.run('configContable=null');
  const msg = await reject('generarAsientoNC("x",{imp_neto:100,imp_iva:21,imp_total:121},{cliente:"c"},"")');
  assert.match(msg, /configuraci[oó]n contable/i);
});
