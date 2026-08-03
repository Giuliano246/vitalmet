// Tests del desglose fiscal de facturas de proveedor (spec 2026-07-30).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function totales(args) { return erp.run(`computeTotalesFactura(${JSON.stringify(args)})`); }
function validar(args) { return erp.run(`validarDesgloseFactura(${JSON.stringify(args)})`); }

test('computeTotalesFactura suma bases, IVA y percepciones', () => {
  const r = totales({
    ivas: [{ alicuota: 21, base: 1000, monto: 210 }, { alicuota: 10.5, base: 500, monto: 52.5 }],
    noGravado: 100, exento: 50,
    percepciones: [{ tipo: 'percepcion_iibb', monto: 30, jurisdiccion: 'PBA' }, { tipo: 'percepcion_iva', monto: 20 }],
  });
  assert.strictEqual(r.neto, 1500);
  assert.strictEqual(r.iva, 262.5);
  assert.strictEqual(r.percep, 50);
  assert.strictEqual(r.total, 1962.5);
});

test('computeTotalesFactura tolera arrays vacíos y campos ausentes', () => {
  // Nota: los objetos salen del contexto vm — comparar propiedad por
  // propiedad (deepStrictEqual falla por prototipos de otro realm).
  const r = totales({ ivas: [], percepciones: [] });
  assert.strictEqual(r.neto, 0);
  assert.strictEqual(r.iva, 0);
  assert.strictEqual(r.percep, 0);
  assert.strictEqual(r.total, 0);
});

test('validarDesgloseFactura OK cuando el total tipeado coincide', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1210, totales: t });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.errores.length, 0);
});

test('validarDesgloseFactura rechaza total que no cierra (>0.01)', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1200, totales: t });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.errores.length, 1);
});

test('validarDesgloseFactura rechaza IVA en letra C', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'C', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1210, totales: t });
  assert.strictEqual(r.ok, false);
});

test('validarDesgloseFactura acepta redondeo del proveedor en el monto de IVA', () => {
  // base*alicuota = 209.99 vs monto cargado 210: diferencia chica, aceptable
  const ivas = [{ alicuota: 21, base: 999.95, monto: 210 }];
  const t = totales({ ivas, noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas, totalTipeado: t.total, totales: t });
  assert.strictEqual(r.ok, true);
});

test('validarDesgloseFactura rechaza monto de IVA incoherente con la base', () => {
  const ivas = [{ alicuota: 21, base: 1000, monto: 500 }]; // 21% de 1000 es 210, no 500
  const t = totales({ ivas, noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas, totalTipeado: t.total, totales: t });
  assert.strictEqual(r.ok, false);
});

test('sugerirLetra mapea condición fiscal', () => {
  assert.strictEqual(erp.run(`sugerirLetra('RI')`), 'A');
  assert.strictEqual(erp.run(`sugerirLetra('monotributo')`), 'C');
  assert.strictEqual(erp.run(`sugerirLetra('exento')`), 'C');
  assert.strictEqual(erp.run(`sugerirLetra('consumidor_final')`), 'B');
  assert.strictEqual(erp.run(`sugerirLetra(null)`), 'A');
});

test('letraDiscriminaIva solo A y M', () => {
  assert.strictEqual(erp.run(`letraDiscriminaIva('A')`), true);
  assert.strictEqual(erp.run(`letraDiscriminaIva('M')`), true);
  assert.strictEqual(erp.run(`letraDiscriminaIva('B')`), false);
  assert.strictEqual(erp.run(`letraDiscriminaIva('C')`), false);
  assert.strictEqual(erp.run(`letraDiscriminaIva('X')`), false);
});

test('validarCuit: dígito verificador módulo 11', () => {
  assert.strictEqual(erp.run(`validarCuit('30-50001091-2')`), true);  // YPF SA
  assert.strictEqual(erp.run(`validarCuit('30500010912')`), true);    // sin guiones
  assert.strictEqual(erp.run(`validarCuit('20-12345678-9')`), false); // verificador incorrecto
  assert.strictEqual(erp.run(`validarCuit('30-50001091-1')`), false); // último dígito cambiado
  assert.strictEqual(erp.run(`validarCuit('123')`), false);           // largo inválido
  assert.strictEqual(erp.run(`validarCuit('')`), false);
  assert.strictEqual(erp.run(`validarCuit(null)`), false);
});

test('normalizarCuit deja solo dígitos', () => {
  assert.strictEqual(erp.run(`normalizarCuit('30-50001091-2')`), '30500010912');
  assert.strictEqual(erp.run(`normalizarCuit(' 30 50001091 2 ')`), '30500010912');
});

// ── convertirRecibidoAFactura (migración 061) ─────────────────────
// El valor recibido está en la moneda de la OC; el match compara en la
// moneda de la factura.

function conv(args) { return erp.run(`convertirRecibidoAFactura(${JSON.stringify(args)})`); }

test('convertirRecibidoAFactura: misma moneda pasa sin tocar', () => {
  assert.strictEqual(conv({recibido: 1000, monOC: 'ARS', monFact: 'ARS'}).valor, 1000);
  assert.strictEqual(conv({recibido: 500, monOC: 'USD', monFact: 'USD', tcFact: 1479}).valor, 500);
});

test('convertirRecibidoAFactura: OC USD → factura ARS multiplica por TC', () => {
  const r = conv({recibido: 139, monOC: 'USD', monFact: 'ARS', tcFact: 1479});
  assert.strictEqual(r.valor, 139 * 1479);
  assert.strictEqual(r.tc, 1479);
});

test('convertirRecibidoAFactura: OC ARS → factura USD divide por TC', () => {
  const r = conv({recibido: 147900, monOC: 'ARS', monFact: 'USD', tcFact: 1479});
  assert.strictEqual(r.valor, 100);
});

test('convertirRecibidoAFactura: prioriza TC factura y cae al de la OC', () => {
  assert.strictEqual(conv({recibido: 10, monOC: 'USD', monFact: 'ARS', tcFact: 1500, tcOC: 1400}).valor, 15000);
  assert.strictEqual(conv({recibido: 10, monOC: 'USD', monFact: 'ARS', tcFact: '', tcOC: 1400}).valor, 14000);
});

test('convertirRecibidoAFactura: monedas distintas sin TC ⇒ error, no compara', () => {
  const r = conv({recibido: 10, monOC: 'USD', monFact: 'ARS'});
  assert.strictEqual(r.valor, null);
  assert.ok(/tipo de cambio/.test(r.error));
});

test('convertirRecibidoAFactura: moneda ausente defaultea a ARS', () => {
  assert.strictEqual(conv({recibido: 1000, monFact: 'ARS'}).valor, 1000);
});

// ── validarFechasFactura (migración 062: doble fecha) ─────────────

// Los valores nacen en el realm del vm: JSON round-trip para comparar
// estructuras sin chocar con los prototipos (ver calculos.test.js:149).
const J = x => JSON.parse(JSON.stringify(x));

test('validarFechasFactura: contable posterior a emisión es el caso normal', () => {
  const r = erp.run(`validarFechasFactura({emision:'2026-06-09',contable:'2026-08-03'})`);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.warning, null);
});

test('validarFechasFactura: contable anterior a emisión advierte pero no bloquea', () => {
  const r = erp.run(`validarFechasFactura({emision:'2026-08-03',contable:'2026-06-09'})`);
  assert.strictEqual(r.ok, true);
  assert.ok(/anterior a la emisión/.test(r.warning));
});

test('validarFechasFactura: falta cualquiera de las dos ⇒ inválido', () => {
  assert.strictEqual(erp.run(`validarFechasFactura({emision:'',contable:'2026-08-03'})`).ok, false);
  assert.strictEqual(erp.run(`validarFechasFactura({emision:'2026-08-03',contable:''})`).ok, false);
});

// ── itemsPendientesOC (recepción completa desde la factura) ───────

test('itemsPendientesOC: devuelve solo lo pendiente con la cantidad que falta', () => {
  const r = erp.run(`itemsPendientesOC([
    {id:'a', cantidad:10, cantidad_recibida:4},
    {id:'b', cantidad:5,  cantidad_recibida:5},
    {id:'c', cantidad:3,  cantidad_recibida:null},
  ])`);
  assert.deepEqual(J(r).map(x => ({id: x.itemId, qty: x.qty})),
    [{id: 'a', qty: 6}, {id: 'c', qty: 3}]);
  assert.strictEqual(r[0].it.id, 'a');
});

test('itemsPendientesOC: OC completa o vacía ⇒ lista vacía', () => {
  assert.deepEqual(J(erp.run(`itemsPendientesOC([{id:'a',cantidad:2,cantidad_recibida:2}])`)), []);
  assert.deepEqual(J(erp.run(`itemsPendientesOC([])`)), []);
  assert.deepEqual(J(erp.run(`itemsPendientesOC(null)`)), []);
});

// ── armarDraftCorreccion (anular + recargar precargado) ───────────

test('armarDraftCorreccion: separa IVAs de percepciones y arma los campos', () => {
  const r = erp.run(`armarDraftCorreccion(
    {nro:'A-1', fecha:'2026-07-01', fecha_contable:'2026-08-01', fecha_vto:'2026-08-15',
     tipo:'factura', letra:'A', moneda:'ARS', tipo_cambio:1480, no_gravado:10, exento:0, total:1210},
    [{tipo:'iva', alicuota:21, base:1000, monto:210},
     {tipo:'percepcion_iibb', monto:15, jurisdiccion:'CABA'}])`);
  assert.deepEqual(J(r.ivas), [{alicuota: 21, base: 1000, monto: 210}]);
  assert.deepEqual(J(r.perceps), [{tipo: 'percepcion_iibb', monto: 15, jurisdiccion: 'CABA'}]);
  assert.strictEqual(r.campos.fechaContable, '2026-08-01');
  assert.strictEqual(r.campos.tc, 1480);
  assert.strictEqual(r.campos.noGravado, 10);
});

test('armarDraftCorreccion: factura vieja sin fecha_contable cae a la de emisión', () => {
  const r = erp.run(`armarDraftCorreccion({nro:'B-2', fecha:'2026-07-10', total:100}, [])`);
  assert.strictEqual(r.campos.fechaContable, '2026-07-10');
  assert.deepEqual(J(r.ivas), []);
  assert.strictEqual(r.campos.letra, 'A');
});
