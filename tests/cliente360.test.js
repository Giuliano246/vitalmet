// Tests de computeRentabilidadCliente (Paquete 7C).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('computeRentabilidadCliente calcula margen con costo por pieza', () => {
  const r = erp.run(`(()=>{
    const ventasC=[
      {estado:'facturado',venta_items:[{cantidad:2,precio_unitario:100,pieza:'Anillo BX'},{cantidad:1,precio_unitario:50,pieza:'Codo'}]},
      {estado:'anulada',venta_items:[{cantidad:9,precio_unitario:999,pieza:'Anillo BX'}]},
    ];
    return computeRentabilidadCliente(ventasC,{'anillo bx':60,'codo':30});
  })()`);
  assert.strictEqual(r.facturado, 250);
  assert.strictEqual(r.costoEstimado, 150); // 2×60 + 1×30
  assert.strictEqual(r.margenPct, 40);      // (250-150)/250
});

test('computeRentabilidadCliente sin costos completos devuelve margen null', () => {
  const r = erp.run(`computeRentabilidadCliente([{estado:'facturado',venta_items:[{cantidad:1,precio_unitario:10,pieza:'X'}]}],{})`);
  assert.strictEqual(r.margenPct, null);
  assert.strictEqual(r.facturado, 10);
});
