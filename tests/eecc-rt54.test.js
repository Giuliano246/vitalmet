// Tests del Sprint D "Estados contables RT 54" (2026-09-02): saldosEECC
// (reglas de exclusión de asientos de cierre), computeEstadosRT54 (ESP por
// rubro y corriente/no corriente, ER por función, EEPN) y computeEFE
// (clasificación por contrapartida). Informe: docs/analisis/2026-09-02-auditoria-rt54.md
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const j = JSON.stringify;

const C = (id, codigo, nombre, tipo, rubro, extra) => ({ id, codigo, nombre, tipo, rubro_rt54: rubro, imputable: true, activa: true, es_ajustable: false, ...(extra || {}) });
const CUENTAS = [
  C('caja', '111001', 'Caja', 'activo', 'caja_bancos'),
  C('deud', '112016', 'Deudores por ventas', 'activo', 'cuentas_cobrar_clientes'),
  C('prev', '112090', 'Previsión para incobrables', 'activo', 'cuentas_cobrar_clientes', { saldo_habitual: 'acreedor' }),
  C('merc', '114001', 'Mercaderías', 'activo', 'bienes_cambio'),
  C('maq', '122007', 'Maquinarias', 'activo', 'bienes_uso'),
  C('amort', '122013', 'Amort Acum Maquinarias', 'activo', 'bienes_uso', { saldo_habitual: 'acreedor' }),
  C('prov', '211002', 'Proveedores', 'pasivo', 'proveedores'),
  C('leas', '212002', 'Leasing a pagar', 'pasivo', 'prestamos'),
  C('cap', '310000', 'Capital suscripto', 'patrimonio', 'capital'),
  C('ajcap', '312000', 'Ajuste de capital', 'patrimonio', 'ajuste_capital'),
  C('rna', '314002', 'Resultados no asignados', 'patrimonio', 'rna'),
  C('vtas', '411001', 'Ventas', 'ingreso', 'ventas'),
  C('cmv', '511000', 'CMV', 'egreso', 'cmv'),
  C('sfab', '421001', 'Sueldos fabricación', 'egreso', 'cmv', { naturaleza: 'Sueldos y jornales' }),
  C('gadm', '422005', 'Honorarios', 'egreso', 'gastos_administracion', { naturaleza: 'Honorarios profesionales' }),
  C('sadm', '422003', 'Sueldos administración', 'egreso', 'gastos_administracion', { naturaleza: 'Sueldos y jornales' }),
  C('int', '424001', 'Intereses bancarios', 'egreso', 'rfyt'),
  C('recpam', '412004', 'RECPAM', 'ingreso', 'rfyt'),
  C('iigg', '425001', 'Imp. a las ganancias', 'egreso', 'iigg'),
];
// Ejercicio 2026. Apertura (saldos al 31/12/2025) + movimientos + cierre de resultados del ejercicio (que debe ignorarse).
const ASIENTOS = [
  { id: 'ap', estado: 'confirmado', fecha: '2025-12-31', moneda: 'ARS', tipo: 'manual' },
  { id: 'v1', estado: 'confirmado', fecha: '2026-03-10', moneda: 'ARS', tipo: 'auto-factura' },
  { id: 'c1', estado: 'confirmado', fecha: '2026-04-05', moneda: 'ARS', tipo: 'auto-cobranza' },
  { id: 'cp', estado: 'confirmado', fecha: '2026-05-02', moneda: 'ARS', tipo: 'manual', origen_tipo: 'factura_recibida' },
  { id: 'pg', estado: 'confirmado', fecha: '2026-05-20', moneda: 'ARS', tipo: 'auto-pago' },
  { id: 'mq', estado: 'confirmado', fecha: '2026-06-01', moneda: 'USD', tipo_cambio: 1000, tipo: 'manual' },
  { id: 'sl', estado: 'confirmado', fecha: '2026-06-30', moneda: 'ARS', tipo: 'auto-sueldos' },
  { id: 'cx', estado: 'confirmado', fecha: '2026-12-31', moneda: 'ARS', tipo: 'auto-cierre-rt54', origen_tipo: 'cierre_rt54' },
  { id: 'ref', estado: 'confirmado', fecha: '2026-12-31', moneda: 'ARS', tipo: 'auto-cierre-resultados' },
  { id: 'cpat', estado: 'confirmado', fecha: '2026-12-31', moneda: 'ARS', tipo: 'auto-cierre-patrimoniales' },
  { id: 'bor', estado: 'borrador', fecha: '2026-12-31', moneda: 'ARS', tipo: 'manual' },
];
const LINEAS = [
  // apertura: caja 100, deudores 200, merc 300, maq 1000 / prov 150, cap 1000, ajcap 200, rna 250
  { asiento_id: 'ap', cuenta_id: 'caja', debe: 100, haber: 0 }, { asiento_id: 'ap', cuenta_id: 'deud', debe: 200, haber: 0 },
  { asiento_id: 'ap', cuenta_id: 'merc', debe: 300, haber: 0 }, { asiento_id: 'ap', cuenta_id: 'maq', debe: 1000, haber: 0 },
  { asiento_id: 'ap', cuenta_id: 'prov', debe: 0, haber: 150 }, { asiento_id: 'ap', cuenta_id: 'cap', debe: 0, haber: 1000 },
  { asiento_id: 'ap', cuenta_id: 'ajcap', debe: 0, haber: 200 }, { asiento_id: 'ap', cuenta_id: 'rna', debe: 0, haber: 250 },
  // venta 500 a crédito; cobro 400; compra mercadería 250 a crédito; pago proveedor 300
  { asiento_id: 'v1', cuenta_id: 'deud', debe: 500, haber: 0 }, { asiento_id: 'v1', cuenta_id: 'vtas', debe: 0, haber: 500 },
  { asiento_id: 'c1', cuenta_id: 'caja', debe: 400, haber: 0 }, { asiento_id: 'c1', cuenta_id: 'deud', debe: 0, haber: 400 },
  { asiento_id: 'cp', cuenta_id: 'merc', debe: 250, haber: 0 }, { asiento_id: 'cp', cuenta_id: 'prov', debe: 0, haber: 250 },
  { asiento_id: 'pg', cuenta_id: 'prov', debe: 300, haber: 0 }, { asiento_id: 'pg', cuenta_id: 'caja', debe: 0, haber: 300 },
  // máquina 0,1 USD × 1000 = 100 ARS con leasing (financiación) → inversión y financiación en el mismo asiento: no toca efectivo
  { asiento_id: 'mq', cuenta_id: 'maq', debe: 0.1, haber: 0 }, { asiento_id: 'mq', cuenta_id: 'leas', debe: 0, haber: 0.1 },
  // sueldos pagados por caja 120 (fab 80, adm 40)
  { asiento_id: 'sl', cuenta_id: 'sfab', debe: 80, haber: 0 }, { asiento_id: 'sl', cuenta_id: 'sadm', debe: 40, haber: 0 }, { asiento_id: 'sl', cuenta_id: 'caja', debe: 0, haber: 120 },
  // cierre RT 54: variación existencias 250 (merc 550 → EF 300), depreciación 100, previsión 30, IIGG 10 (contra prov por simplicidad)
  { asiento_id: 'cx', cuenta_id: 'cmv', debe: 250, haber: 0 }, { asiento_id: 'cx', cuenta_id: 'merc', debe: 0, haber: 250 },
  { asiento_id: 'cx', cuenta_id: 'gadm', debe: 100, haber: 0 }, { asiento_id: 'cx', cuenta_id: 'amort', debe: 0, haber: 100 },
  { asiento_id: 'cx', cuenta_id: 'int', debe: 30, haber: 0 }, { asiento_id: 'cx', cuenta_id: 'prev', debe: 0, haber: 30 },
  { asiento_id: 'cx', cuenta_id: 'iigg', debe: 10, haber: 0 }, { asiento_id: 'cx', cuenta_id: 'prov', debe: 0, haber: 10 },
  // refundición (debe ignorarse): ventas 500 / gastos... / resultado
  { asiento_id: 'ref', cuenta_id: 'vtas', debe: 500, haber: 0 }, { asiento_id: 'ref', cuenta_id: 'cmv', debe: 0, haber: 250 }, { asiento_id: 'ref', cuenta_id: 'rna', debe: 0, haber: 250 },
  // cierre patrimonial (debe ignorarse): caja al haber
  { asiento_id: 'cpat', cuenta_id: 'caja', debe: 0, haber: 80 },
  { asiento_id: 'bor', cuenta_id: 'caja', debe: 9999, haber: 0 },
];

test('saldosEECC: excluye borradores, cierre patrimonial siempre y refundición del ejercicio en curso', () => {
  const s = erp.run(`saldosEECC(${j(LINEAS)}, ${j(ASIENTOS)}, {hasta:'2026-12-31', ejercicioDesde:'2026-01-01'})`);
  assert.strictEqual(s.caja.debe - s.caja.haber, 80);          // 100 + 400 − 300 − 120; sin 'cpat' ni 'bor'
  assert.strictEqual(s.vtas.haber - s.vtas.debe, 500);         // sin refundición
  assert.strictEqual(s.maq.debe, 1100);                        // USD × TC
  const ini = erp.run(`saldosEECC(${j(LINEAS)}, ${j(ASIENTOS)}, {hasta:'2025-12-31', ejercicioDesde:'2026-01-01'})`);
  assert.strictEqual(ini.merc.debe, 300);
  assert.strictEqual(ini.vtas, undefined);
});

function armar(conAnterior) {
  return erp.run(`(()=>{
    const L=${j(LINEAS)},A=${j(ASIENTOS)},C=${j(CUENTAS)};
    const act={saldos:saldosEECC(L,A,{hasta:'2026-12-31',ejercicioDesde:'2026-01-01'}),inicio:saldosEECC(L,A,{hasta:'2025-12-31',ejercicioDesde:'2026-01-01'}),mov:saldosEECC(L,A,{desde:'2026-01-01',hasta:'2026-12-31',ejercicioDesde:'2026-01-01'}),
      movCompras:saldosEECC(L,A,{desde:'2026-01-01',hasta:'2026-12-31',ejercicioDesde:'2026-01-01',excluirOrigen:['cierre_rt54']})};
    const ant=${conAnterior}?{saldos:saldosEECC(L,A,{hasta:'2025-12-31',ejercicioDesde:'2025-01-01'}),inicio:{},mov:{}}:null;
    return computeEstadosRT54({cuentas:C,act,ant,coefAnt:2,desde:'2026-01-01',hasta:'2026-12-31'});
  })()`);
}

test('computeEstadosRT54: ESP por rubro, corriente / no corriente, regularizadoras netas y cuadre', () => {
  const r = armar(false);
  const e = r.esp;
  const ac = Object.fromEntries(e.activoCorriente.map(b => [b.rubro, b.actual]));
  assert.strictEqual(ac.caja_bancos, 80);
  assert.strictEqual(ac.cuentas_cobrar_clientes, 270);         // 200 + 500 − 400 − previsión 30
  assert.strictEqual(ac.bienes_cambio, 300);
  assert.strictEqual(e.activoNoCorriente[0].rubro, 'bienes_uso');
  assert.strictEqual(e.activoNoCorriente[0].actual, 1000);      // 1100 − amort 100
  assert.strictEqual(e.totActivo, 1650);
  const pc = Object.fromEntries(e.pasivoCorriente.map(b => [b.rubro, b.actual]));
  assert.strictEqual(pc.proveedores, 110);                      // 150 + 250 − 300 + 10
  assert.strictEqual(pc.prestamos, 100);                        // leasing (prefijo 21 → corriente)
  assert.strictEqual(e.totPasivo, 210);
  const pn = Object.fromEntries(e.pn.map(b => [b.rubro, b.actual]));
  assert.strictEqual(pn.capital, 1000);
  assert.strictEqual(pn.ajuste_capital, 200);
  assert.strictEqual(pn.rna, 250);
  assert.strictEqual(pn.resultado_ejercicio, -10);              // 500 − 250 − 80 − 40 − 100 − 30 − 10
  assert.strictEqual(e.totPN, 1440);
  assert.ok(e.cuadra, `dif ${e.dif}`);
  assert.strictEqual(r.sinRubro.length, 0);
});

test('computeEstadosRT54: ER por función, anexos de gastos por naturaleza y CMV', () => {
  const r = armar(false);
  const er = Object.fromEntries(r.er.lineas.map(l => [l.k, l.actual]));
  assert.strictEqual(er.ventas, 500);
  assert.strictEqual(er.cmv, -330);                             // 511000 250 + sueldos fábrica 80
  assert.strictEqual(er.bruto, 170);
  assert.strictEqual(er.gastos_administracion, -140);           // honorarios/depreciación 100 + sueldos adm 40
  assert.strictEqual(er.rfyt, -30);
  assert.strictEqual(er.antesIIGG, 0);
  assert.strictEqual(er.iigg, -10);
  assert.strictEqual(er.resultado, -10);
  const gn = r.gastosNat;
  const sueldos = gn.filas.find(f => f.concepto === 'Sueldos y jornales');
  assert.strictEqual(sueldos.cmv, 80); assert.strictEqual(sueldos.gastos_administracion, 40); assert.strictEqual(sueldos.total, 120);
  assert.strictEqual(gn.total.total, 220);                      // 80 + 40 + 100 (511000 excluido)
  const cv = r.anexoCMV;
  assert.strictEqual(cv.existenciaInicial, 300);
  assert.strictEqual(cv.compras, 250);
  assert.strictEqual(cv.costoProduccion, 80);
  assert.strictEqual(cv.existenciaFinal, 300);
  assert.strictEqual(cv.cmv, 330);
  assert.strictEqual(cv.cmvContabilizado, 250);
  assert.strictEqual(cv.cmvTotalER, 330);
  const prev = r.previsiones.find(p => p.codigo === '112090');
  assert.strictEqual(prev.deducidaDelActivo, true); assert.strictEqual(prev.aumentos, 30); assert.strictEqual(prev.cierre, 30);
});

test('computeEstadosRT54: comparativo reexpresado × coef y EEPN', () => {
  const r = armar(true);
  const ac = r.esp.activoCorriente.find(b => b.rubro === 'caja_bancos');
  assert.strictEqual(ac.anterior, 200);                         // 100 × 2
  assert.strictEqual(r.esp.totActivoAnt, 3200);                 // (100+200+300+1000) × 2
  assert.strictEqual(r.esp.pn.find(b => b.rubro === 'capital').anterior, 2000);
  const ep = r.eepn;
  const ini = ep.filas[0], fin = ep.filas[3];
  assert.strictEqual(ini.vals.capital, 1000); assert.strictEqual(ini.vals.rna, 250); assert.strictEqual(ini.total, 1450);
  assert.strictEqual(ep.filas[2].vals.rna, -10);
  assert.strictEqual(fin.vals.rna, 240); assert.strictEqual(fin.total, 1440);
});

test('computeEFE: clasifica por contrapartida y concilia con el efectivo del ESP', () => {
  const r = erp.run(`(()=>{
    const L=${j(LINEAS)},A=${j(ASIENTOS)},C=${j(CUENTAS)};
    return computeEFE({lineas:L,asientos:A,cuentas:C,desde:'2026-01-01',hasta:'2026-12-31',
      saldosInicio:saldosEECC(L,A,{hasta:'2025-12-31',ejercicioDesde:'2026-01-01'}),saldosCierre:saldosEECC(L,A,{hasta:'2026-12-31',ejercicioDesde:'2026-01-01'})});
  })()`);
  assert.strictEqual(r.inicio, 100);
  assert.strictEqual(r.cierre, 80);
  assert.strictEqual(r.variacion, -20);
  assert.strictEqual(r.op.cobros_clientes, 400);
  assert.strictEqual(r.op.pagos_proveedores, -300);
  assert.strictEqual(r.op.sueldos_cargas, -120);                // sueldos pagados directo contra gasto: por nombre de cuenta
  assert.strictEqual(r.op.otros, 0);
  assert.strictEqual(r.totOp, -20);
  assert.strictEqual(r.totInv, 0);
  assert.strictEqual(r.totFin, 0);
  assert.strictEqual(r.recpamEfectivo, 0);
});
