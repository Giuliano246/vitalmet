// Tests de resolverPrecio (Paquete 6B): último al cliente > base > PT > 0.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('resolverPrecio: último al cliente > base > PT > 0', () => {
  const r = erp.run(`(()=>{
    const ventasArr=[
      {cliente:'ACME SA',estado:'facturado',created_at:'2026-06-01',venta_items:[{precio_unitario:120,productos_terminados:{pieza:'Anillo BX'}}]},
      {cliente:'ACME SA',estado:'entregado',created_at:'2026-07-01',venta_items:[{precio_unitario:150,productos_terminados:{pieza:'Anillo BX'}}]},
      {cliente:'Otro SRL',estado:'facturado',created_at:'2026-07-02',venta_items:[{precio_unitario:99,productos_terminados:{pieza:'Anillo BX'}}]},
    ];
    const precios=[{pieza:'Anillo BX',precio_usd:130},{pieza:'Unión 2',precio_usd:80}];
    const ptsArr=[{pieza:'Codo 90',precio_unitario:55,created_at:'2026-01-01'}];
    return {
      cli: resolverPrecio('anillo bx','ACME SA',ventasArr,precios,ptsArr),
      base: resolverPrecio('Unión 2','Nuevo SA',ventasArr,precios,ptsArr),
      pt: resolverPrecio('Codo 90','Nuevo SA',ventasArr,precios,ptsArr),
      nada: resolverPrecio('Inexistente','X',ventasArr,precios,ptsArr),
    };
  })()`);
  assert.deepStrictEqual({ ...r.cli }, { precio: 150, origen: 'cliente' }); // la más reciente de ACME
  assert.deepStrictEqual({ ...r.base }, { precio: 80, origen: 'base' });
  assert.deepStrictEqual({ ...r.pt }, { precio: 55, origen: 'pt' });
  assert.deepStrictEqual({ ...r.nada }, { precio: 0, origen: null });
});

test('resolverPrecio ignora ventas anuladas', () => {
  const r = erp.run(`(()=>{
    const ventasArr=[{cliente:'ACME SA',estado:'anulada',created_at:'2026-07-01',venta_items:[{precio_unitario:999,productos_terminados:{pieza:'Anillo BX'}}]}];
    return resolverPrecio('Anillo BX','ACME SA',ventasArr,[{pieza:'Anillo BX',precio_usd:130}],[]);
  })()`);
  assert.deepStrictEqual({ ...r }, { precio: 130, origen: 'base' });
});
