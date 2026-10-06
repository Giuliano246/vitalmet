// Tests de los datos de la entrega del remito (mig 088).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const J = JSON.stringify;
const datos = (v, ctx) => JSON.parse(erp.run(`JSON.stringify(remitoDatosVenta(${J(v)}, ${J(ctx)}))`));

test('sin datos guardados: domicilio del cliente y valor declarado = total de la venta', () => {
  const d = datos({ total: 1210 }, { cliente: { direccion: 'Ruta 7 km 12, Neuquén' } });
  assert.deepStrictEqual(d, { domicilio_entrega: 'Ruta 7 km 12, Neuquén', transporte: '', oc_cliente: '', bultos: null, valor_declarado: 1210, valor_moneda: 'USD' });
});

test('si los precios incluyen IVA, el valor declarado va neto', () => {
  assert.strictEqual(datos({ total: 1210 }, { ivaPct: 21, incluyenIva: true }).valor_declarado, 1000);
});

test('lo guardado en la venta manda sobre los valores por defecto', () => {
  const v = { total: 1210, remito_datos: { domicilio_entrega: 'Yacimiento Loma Campana', transporte: 'Cruz del Sur', oc_cliente: '4500123456', bultos: 3, valor_declarado: 950.5, valor_moneda: 'ARS' } };
  assert.deepStrictEqual(datos(v, { cliente: { direccion: 'Otra' } }),
    { domicilio_entrega: 'Yacimiento Loma Campana', transporte: 'Cruz del Sur', oc_cliente: '4500123456', bultos: 3, valor_declarado: 950.5, valor_moneda: 'ARS' });
});

test('saldo de una entrega parcial: hereda OC, domicilio y transporte de la venta original, no bultos ni valor', () => {
  const padre = { remito_datos: { domicilio_entrega: 'Planta Añelo', transporte: 'Andreani', oc_cliente: 'OC-77', bultos: 5, valor_declarado: 9000 } };
  const d = datos({ total: 400, venta_padre_id: 'p' }, { padre, cliente: { direccion: 'Casa central' } });
  assert.deepStrictEqual(d, { domicilio_entrega: 'Planta Añelo', transporte: 'Andreani', oc_cliente: 'OC-77', bultos: null, valor_declarado: 400, valor_moneda: 'USD' });
});

test('bultos y valor en cero se respetan (no caen al valor por defecto)', () => {
  const d = datos({ total: 500, remito_datos: { bultos: 0, valor_declarado: 0 } }, {});
  assert.strictEqual(d.bultos, 0);
  assert.strictEqual(d.valor_declarado, 0);
});
