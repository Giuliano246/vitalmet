// Tests de retenciones practicadas a proveedores (migración 086):
// cálculo RG 830 (acumulado mensual), escala, por pago, base del pago y
// resolución del total de la OP. Más un guard de ids duplicados en el HTML
// (la OP de pago compartía ids con Órdenes de producción y su listado
// se dibujaba en la otra pantalla).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const erp = require('./_harness').load();
const J = JSON.stringify;
const calc = a => ({ ...erp.run(`calcularRetencion(${J(a)})`) });

const BIENES = { id: 'r78', impuesto: 'ganancias', codigo: '78', modo: 'acumulado_mensual', minimo_no_sujeto: 224000, alicuota_inscripto: 2, alicuota_no_inscripto: 10, minimo_retencion: 240 };
const HONOR = { id: 'r116', impuesto: 'ganancias', codigo: '116', modo: 'acumulado_mensual', minimo_no_sujeto: 67170, alicuota_inscripto: null, alicuota_no_inscripto: 28, minimo_retencion: 240,
  escala: [{ desde: 0, hasta: 8000, fijo: 0, pct: 5 }, { desde: 8000, hasta: 16000, fijo: 400, pct: 9 }, { desde: 16000, hasta: null, fijo: 1120, pct: 12 }] };
const IIBB = { id: 'ri', impuesto: 'iibb', codigo: 'ARBA', modo: 'por_pago', minimo_no_sujeto: 50000, alicuota_inscripto: 1.5, alicuota_no_inscripto: 4, minimo_retencion: 0 };

test('primer pago del mes, inscripto: (base − mínimo) × alícuota', () => {
  const r = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 1000000 });
  assert.strictEqual(r.monto, 15520); // (1.000.000 − 224.000) × 2 %
  assert.strictEqual(r.alicuota, 2);
  assert.strictEqual(r.minimo_no_sujeto, 224000);
});

test('no supera el mínimo no sujeto → 0, con motivo', () => {
  const r = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 200000 });
  assert.strictEqual(r.monto, 0);
  assert.match(r.motivo, /mínimo no sujeto/);
});

test('segundo pago del mes: acumula base y descuenta lo ya retenido', () => {
  // 1er pago 200.000 (sin retención) + 2do 100.000 → (300.000 − 224.000) × 2 % = 1.520
  const r = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 100000, baseAcumPrevia: 200000, retenidoPrevio: 0 });
  assert.strictEqual(r.monto, 1520);
  // 3er pago 500.000 con 1.520 ya retenidos → (800.000 − 224.000) × 2 % − 1.520 = 10.000
  const r3 = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 500000, baseAcumPrevia: 300000, retenidoPrevio: 1520 });
  assert.strictEqual(r3.monto, 10000);
});

test('menor al mínimo de retención → no se retiene', () => {
  const r = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 230000 }); // 6.000 × 2 % = 120 < 240
  assert.strictEqual(r.monto, 0);
  assert.match(r.motivo, /mínimo de retención/);
});

test('no inscripto: sin mínimo no sujeto y alícuota mayor', () => {
  const r = calc({ regimen: BIENES, condicion: 'no_inscripto', basePago: 100000 });
  assert.strictEqual(r.monto, 10000);
  assert.strictEqual(r.minimo_no_sujeto, 0);
});

test('certificado de exclusión vigente → 0', () => {
  const r = calc({ regimen: BIENES, condicion: 'inscripto', basePago: 5000000, excluido: true });
  assert.strictEqual(r.monto, 0);
  assert.match(r.motivo, /exclusión/);
});

test('escala de honorarios: fijo + % sobre el excedente del tramo', () => {
  // base 77.170 − 67.170 = 10.000 → tramo 8.000–16.000: 400 + 2.000 × 9 % = 580
  const r = calc({ regimen: HONOR, condicion: 'inscripto', basePago: 77170 });
  assert.strictEqual(r.monto, 580);
  assert.strictEqual(r.alicuota, null);
  assert.strictEqual(erp.run(`retEscala(${J(HONOR.escala)}, 20000)`), 1600); // 1.120 + 4.000 × 12 %
});

test("modo 'por_pago': el mínimo es umbral y no acumula", () => {
  assert.strictEqual(calc({ regimen: IIBB, condicion: 'inscripto', basePago: 40000 }).monto, 0);
  const r = calc({ regimen: IIBB, condicion: 'inscripto', basePago: 100000, baseAcumPrevia: 900000, retenidoPrevio: 5000 });
  assert.strictEqual(r.monto, 1500); // toda la base × 1,5 %, ignora acumulados
  assert.strictEqual(r.base_acumulada, 0);
});

test('retAcumuladosMes: mismo proveedor, régimen y mes; ignora anuladas', () => {
  const p = [
    { proveedor_id: 'p1', regimen_id: 'r78', fecha: '2026-10-02', base_calculo: 200000, monto: 0, estado: 'vigente' },
    { proveedor_id: 'p1', regimen_id: 'r78', fecha: '2026-10-15', base_calculo: 100000, monto: 1520, estado: 'vigente' },
    { proveedor_id: 'p1', regimen_id: 'r78', fecha: '2026-10-20', base_calculo: 900000, monto: 18000, estado: 'anulada' },
    { proveedor_id: 'p1', regimen_id: 'r78', fecha: '2026-09-30', base_calculo: 500000, monto: 5520, estado: 'vigente' },
    { proveedor_id: 'p2', regimen_id: 'r78', fecha: '2026-10-10', base_calculo: 700000, monto: 9520, estado: 'vigente' },
    { proveedor_id: 'p1', regimen_id: 'r116', fecha: '2026-10-10', base_calculo: 80000, monto: 600, estado: 'vigente' },
  ];
  assert.deepStrictEqual({ ...erp.run(`retAcumuladosMes(${J(p)}, 'p1', 'r78', '2026-10-28')`) }, { base: 300000, retenido: 1520 });
});

test('retencionesAplicables: régimen activo + exclusión por fecha', () => {
  const prov = { retenciones: [
    { regimen_id: 'r78', condicion: 'inscripto', exclusion_hasta: '2026-10-31', exclusion_cert: 'X-1' },
    { regimen_id: 'ri', condicion: 'no_inscripto' },
    { regimen_id: 'borrado' },
  ] };
  const r = erp.run(`retencionesAplicables(${J(prov)}, ${J([BIENES, IIBB])}, '2026-10-15')`);
  assert.strictEqual(r.length, 2);
  assert.strictEqual(r[0].excluido, true);
  assert.strictEqual(r[1].condicion, 'no_inscripto');
  const d = erp.run(`retencionesAplicables(${J(prov)}, ${J([BIENES, IIBB])}, '2026-11-01')`);
  assert.strictEqual(d[0].excluido, false); // venció el certificado
  assert.strictEqual(erp.run(`retencionesAplicables({}, ${J([BIENES])}, '2026-10-15')`).length, 0);
});

test('retBasePago: neto de IVA proporcional al pago + a cuenta entero', () => {
  const f = { total: 121000, neto: 100000, iva: 21000 };
  const fp = { total: 124000, neto: 100000, iva: 21000 }; // 3.000 de percepciones: no son base
  const b = erp.run(`retBasePago(${J({ imputaciones: [{ factura: f, monto: 121000 }, { factura: fp, monto: 62000 }], aCuenta: 10000, impuesto: 'ganancias' })})`);
  assert.strictEqual(b, 160000); // 100.000 + 50.000 + 10.000
  assert.strictEqual(erp.run(`retBasePago(${J({ imputaciones: [{ factura: f, monto: 121000 }], aCuenta: 10000, impuesto: 'iva' })})`), 21000);
  // OP en USD: la base se pasa a pesos por el TC de la OP
  assert.strictEqual(erp.run(`retBasePago(${J({ imputaciones: [{ factura: { total: 1210, neto: 1000, iva: 210 }, monto: 1210 }], tcARS: 1400, impuesto: 'ganancias' })})`), 1400000);
  // factura vieja sin neto cargado: total − IVA
  assert.strictEqual(erp.run(`retBasePago(${J({ imputaciones: [{ factura: { total: 121000, iva: 21000 }, monto: 121000 }], impuesto: 'ganancias' })})`), 100000);
});

test("retResolverOP 'bruto': lo cargado es el total, la retención se descuenta", () => {
  const r = erp.run(`retResolverOP({pagado:1210000, modo:'bruto', calcular:T=>[{monto_op:Math.round((T/1.21-224000)*0.02*100)/100}]})`);
  assert.strictEqual(r.total, 1210000);
  assert.strictEqual(r.retenido, 15520);
});

test("retResolverOP 'neto': total − retención(total) = lo que se transfiere", () => {
  const r = erp.run(`retResolverOP({pagado:1194480, modo:'neto', calcular:T=>[{monto_op:Math.max(0,Math.round((T/1.21-224000)*0.02*100)/100)}]})`);
  assert.ok(Math.abs(r.total - 1210000) < 0.02, `total ${r.total}`);
  assert.ok(Math.abs(r.total - r.retenido - 1194480) < 0.011);
  // sin regímenes no cambia nada
  const s = erp.run(`retResolverOP({pagado:500, modo:'neto', calcular:()=>[]})`);
  assert.deepStrictEqual([s.total, s.retenido], [500, 0]);
});

test('validarOrdenPago acepta el medio retención y exige su cuenta', () => {
  const base = { total: 1000, imputaciones: [], saldos: {} };
  const ok = erp.run(`validarOrdenPago(${J({ ...base, medios: [{ tipo: 'banco', monto: 980, cuenta_contable_id: 'c1' }, { tipo: 'retencion', monto: 20, cuenta_contable_id: 'c2' }] })})`);
  assert.strictEqual(ok.ok, true);
  const sin = erp.run(`validarOrdenPago(${J({ ...base, medios: [{ tipo: 'banco', monto: 980, cuenta_contable_id: 'c1' }, { tipo: 'retencion', monto: 20, cuenta_contable_id: null }] })})`);
  assert.strictEqual(sin.ok, false);
  assert.match(sin.errores[0], /retenciones practicadas/);
});

test('el HTML no tiene ids duplicados', () => {
  for (const file of ['index.html', 'planta.html']) {
    const html = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    const ids = [...html.matchAll(/\sid="([^"$]+)"/g)].map(m => m[1]);
    const dup = [...new Set(ids.filter((x, i) => ids.indexOf(x) !== i))];
    assert.deepStrictEqual(dup, [], `${file}: ids duplicados`);
  }
});
