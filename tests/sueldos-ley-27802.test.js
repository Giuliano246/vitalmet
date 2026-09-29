// Sueldos 084 — adecuación a la Ley 27.802 (Modernización Laboral, 2026):
//   art. 51 (LCT 245): base indemnizatoria = mejor remuneración mensual, normal y
//     habitual del último año (sin SAC/vacaciones/premios no mensuales; variables
//     promediadas a 6 meses o al año; habitual = devengado ≥ 6 meses), tope del CCT
//     con piso del 67 %.
//   art. 48 (LCT 231): preaviso 1 mes hasta 5 años / 2 meses si supera 5; sin
//     preaviso en período de prueba (6 meses, Ley 27.742).
//   art. 52 (LCT 248): fallecimiento = 50 % de la indemnización por antigüedad.
//   art. 241: mutuo acuerdo = suma libremente pactada (no se calcula sola).
//   art. 53 (LCT 255): reingreso — se descuenta la indemnización anterior actualizada.
//   art. 37 (LCT 133): descuentos voluntarios ≤ 20 % de la remuneración en dinero.
//   art. 27 (LCT 92 ter): tiempo parcial aporta obra social como tiempo completo.
//   Título II: Fondo de Asistencia Laboral, 2,5 % PyME sobre base SIPA desde el
//     1/11/2026 (Dec. 408/2026) con reducción equivalente de contribuciones (art. 76).
//   art. 25 (LCT 80): certificado de trabajo al egreso.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify; const N = x => JSON.parse(JSON.stringify(x));

const CAT = [
  {codigo:'1',tipo:'remunerativo',nombre:'Sueldo básico',regla:{orden:1}},
  {codigo:'20',tipo:'remunerativo',nombre:'Aguinaldo',regla:{orden:15}},
  {codigo:'28',tipo:'remunerativo',nombre:'SAC proporcional',regla:{orden:16}},
  {codigo:'517',tipo:'no_remunerativo',regla:{orden:517}},
  {codigo:'521',tipo:'no_remunerativo',regla:{orden:521}},
  {codigo:'530',tipo:'no_remunerativo',regla:{orden:530}},
  {codigo:'531',tipo:'no_remunerativo',regla:{orden:531}},
  {codigo:'532',tipo:'no_remunerativo',regla:{orden:532}},
  {codigo:'533',tipo:'no_remunerativo',regla:{orden:533}},
  {codigo:'535',tipo:'no_remunerativo',nombre:'Gratificación por cese (art. 241)',regla:{orden:535}},
];
const EMP = {fecha_ingreso:'2020-03-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1000000};
const mes = (anio, m, bruto, variables = 0, excluidos = 0, tipo = 'mensual') => ({ anio, mes: m, tipo, bruto, variables, excluidos, dias_trabajados: 30 });
const imp = (r, c) => (r.conceptos.find(x => x.codigo === c) || {}).importe;
const codigos = r => r.conceptos.map(c => c.codigo);
function final(over) {
  return run(`computeLiquidacionFinal(${J(Object.assign({ empleado:EMP, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, topeIndemnizatorio:0, acumulados:[], catalogo:CAT, vacacionesGozadasAnio:14, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:40000,dias_trabajados:20}} }, over || {}))})`);
}

// ─── art. 51: base indemnizatoria ──────────────────────────────────────
test('computeBaseIndemnizatoria: ventana de 12 meses anteriores al egreso, SAC y vacaciones excluidos, sin variables', () => {
  const ac = [mes(2025,6,3000000), mes(2025,9,1000000), mes(2026,3,1100000, 0, 100000), mes(2026,6,1700000, 0, 600000), mes(2026,8,1200000)];
  const b = run(`computeBaseIndemnizatoria(${J(ac)},'2026-09-20',0)`);
  assert.equal(b.mejor_fijo, 1200000);           // 06/2025 (3.000.000) queda fuera de la ventana; 06/2026 = 1.700.000 − 600.000 SAC = 1.100.000
  assert.equal(b.prom_variables, 0);
  assert.equal(b.base, 1200000);
  assert.equal(b.meses, 4);
});
test('computeBaseIndemnizatoria: variables habituales (≥ 6 meses) promediadas a 6 meses o al año, lo más favorable', () => {
  // 12 meses de 1.000.000 fijo; horas extras en 8 meses: 6 últimos con 120.000 y dos anteriores con 60.000
  const ac = [];
  for (let m = 9; m <= 12; m++) ac.push(mes(2025, m, 1000000 + (m >= 11 ? 60000 : 0), m >= 11 ? 60000 : 0));
  for (let m = 1; m <= 8; m++) ac.push(mes(2026, m, 1000000 + (m >= 3 ? 120000 : 0), m >= 3 ? 120000 : 0));
  const b = run(`computeBaseIndemnizatoria(${J(ac)},'2026-09-20',0)`);
  assert.equal(b.mejor_fijo, 1000000);
  assert.equal(b.variables_habituales, true);
  assert.equal(b.prom_variables, 120000);        // últimos 6 meses (03..08/2026) = 120.000; el año da (120.000×6 + 60.000×2)/12 = 70.000 → gana 6 meses
  assert.equal(b.base, 1120000);
});
test('computeBaseIndemnizatoria: variables NO habituales (< 6 meses en el año) no entran; el mes con pico no infla la base', () => {
  const ac = [];
  for (let m = 9; m <= 12; m++) ac.push(mes(2025, m, 1000000));
  for (let m = 1; m <= 8; m++) ac.push(mes(2026, m, 1000000 + (m === 5 ? 900000 : 0), m === 5 ? 900000 : 0));
  const b = run(`computeBaseIndemnizatoria(${J(ac)},'2026-09-20',0)`);
  assert.equal(b.variables_habituales, false);
  assert.equal(b.prom_variables, 0);
  assert.equal(b.base, 1000000);                 // con el criterio viejo (bruto máximo) hubiera dado 1.900.000
});
test('computeBaseIndemnizatoria: las quincenas se suman por mes y la remuneración vigente actúa como piso', () => {
  const ac = [mes(2026,7,500000,0,0,'quincena1'), mes(2026,7,550000,0,0,'quincena2'), mes(2026,8,900000)];
  const b = run(`computeBaseIndemnizatoria(${J(ac)},'2026-09-20',1200000)`);
  assert.equal(b.mejor_fijo, 1200000);           // max(1.050.000, 900.000, piso 1.200.000)
  assert.equal(b.meses, 2);
});
test('computeBaseIndemnizatoria: sin acumulados → la remuneración vigente', () => {
  assert.equal(run(`computeBaseIndemnizatoria([],'2026-09-20',1200000)`).base, 1200000);
});
test('computeLiquidacionFinal usa la base normal y habitual, no el bruto máximo histórico', () => {
  const ac = [mes(2024,1,5000000)];               // un pico viejísimo, fuera de la ventana
  for (let m = 1; m <= 8; m++) ac.push(mes(2026, m, 1000000));
  const r = final({ acumulados: ac });
  assert.equal(r.detalle.mejor_rem_normal, 1000000);
  assert.equal(imp(r,'530'), 7000000);           // 6a 6m 11d → 7 años × 1.000.000
});

// ─── art. 51: tope del CCT con piso del 67 % ────────────────────────────
test('tope del CCT nunca deja la base por debajo del 67 % de la remuneración normal y habitual', () => {
  const r = final({ topeIndemnizatorio: 500000 });
  assert.equal(imp(r,'530'), 4690000);           // 67 % × 1.000.000 = 670.000 × 7 años
  assert.ok(r.alertas.some(a => a.includes('67 %')));
});
test('tope del CCT por encima del 67 % se aplica tal cual', () => {
  const r = final({ topeIndemnizatorio: 800000 });
  assert.equal(imp(r,'530'), 5600000);           // 800.000 × 7
});

// ─── art. 48: preaviso ──────────────────────────────────────────────────
test('preaviso: exactamente 5 años de antigüedad = 1 mes; 5 años y 1 día = 2 meses', () => {
  const a = final({ empleado:{...EMP, fecha_ingreso:'2021-09-21'}, preavisoOtorgado:false });   // 21/09/2021 → 20/09/2026 = 5a 0m 0d
  assert.equal(a.detalle.antiguedad, '5a 0m 0d');
  assert.equal(imp(a,'531'), 1000000);
  const b = final({ empleado:{...EMP, fecha_ingreso:'2021-09-20'}, preavisoOtorgado:false });   // 5a 0m 1d
  assert.equal(imp(b,'531'), 2000000);
});
test('período de prueba: 6 meses por defecto (Ley 27.742) — sin indemnización NI preaviso (art. 48 Ley 27.802)', () => {
  const r = final({ empleado:{...EMP, fecha_ingreso:'2026-04-01'}, preavisoOtorgado:false });    // 5a 20d → prueba
  ['530','531','532','533'].forEach(c => assert.ok(!codigos(r).includes(c), `no debería estar ${c}`));
  assert.ok(r.alertas.some(a => a.includes('Período de prueba')));
  // a los 6 meses cumplidos ya no es prueba
  const s = final({ empleado:{...EMP, fecha_ingreso:'2026-03-20'}, preavisoOtorgado:false });    // 6a 0m 1d → 0a 6m 1d
  assert.ok(codigos(s).includes('530')); assert.ok(codigos(s).includes('531'));
});
test('período de prueba configurable por convenio (8 meses)', () => {
  const r = final({ empleado:{...EMP, fecha_ingreso:'2026-02-01'}, convenio:{periodo_prueba_meses:8} });   // 7 meses
  assert.ok(!codigos(r).includes('530'));
});

// ─── causas: mutuo acuerdo, fallecimiento, reingreso ────────────────────
test('mutuo acuerdo (art. 241): no se calcula indemnización; el importe pactado va al 535', () => {
  const r = final({ causa:'mutuo_acuerdo', preavisoOtorgado:false, importePactado: 2500000 });
  ['530','531','532','533'].forEach(c => assert.ok(!codigos(r).includes(c), `no debería estar ${c}`));
  assert.equal(imp(r,'535'), 2500000);
  assert.ok(r.alertas.some(a => a.includes('art. 241')));
  const sin = final({ causa:'mutuo_acuerdo' });
  assert.ok(!codigos(sin).includes('535'));
});
test('fallecimiento (art. 248): 50 % de la indemnización por antigüedad, sin preaviso ni integración', () => {
  const r = final({ causa:'fallecimiento', preavisoOtorgado:false });
  assert.equal(imp(r,'530'), 3500000);           // 7.000.000 × 50 %
  ['531','532','533'].forEach(c => assert.ok(!codigos(r).includes(c), `no debería estar ${c}`));
});
test('reingreso (art. 255): se descuenta la indemnización anterior actualizada, con piso de 1 mes', () => {
  const r = final({ indemnizacionAnterior: 4000000 });
  assert.equal(imp(r,'530'), 3000000);
  assert.ok(r.alertas.some(a => a.toLowerCase().includes('reingreso')));
  const piso = final({ indemnizacionAnterior: 9000000 });
  assert.equal(imp(piso,'530'), 1000000);
});

// ─── computeRecibo: FAL, art. 133, tiempo parcial ───────────────────────
const CATR = [
  { codigo:'1', nombre:'Sueldo básico', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{orden:1} },
  { codigo:'200', nombre:'Jubilación', tipo:'descuento', codigo_arca:'810000', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_jubilacion_pct',cantidad:'1',orden:200} },
  { codigo:'202', nombre:'Obra social', tipo:'descuento', codigo_arca:'810002', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',tiempo_completo:true,pct_param:'aporte_os_pct',cantidad:'1',orden:202} },
  { codigo:'223', nombre:'Adelanto de sueldo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'fijo',cantidad:'novedad.adelanto',art133:true,orden:223} },
  { codigo:'227', nombre:'Cuota de préstamo', tipo:'descuento', codigo_arca:'810007', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',art133:true,orden:227} },
];
const CONV = { horas_mes:200, horas_dia:8, antiguedad_pct:0, redondeo_a:0, tope_por_quincena:true, scvo_importe:0 };
const PREV = { tope_min:0, tope_max:0, detraccion:0, aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, aporte_os_adherente_pct:1.5, tipo_empresa:2,
  contrib_sipa_pct:10.77, contrib_inssjp_pct:1.59, contrib_fne_pct:0.94, contrib_aaff_pct:4.70, contrib_os_pct:5.10, contrib_fsr_pct:0.90, art_pct:0, art_fijo:0, fal_pct:0 };
const EMPR = { id:'e2', nombre:'PEREZ, ANA', convenio:'fuera', modalidad:'mensual', sueldo_pactado:1000000, fecha_ingreso:'2026-01-01', horas_semanales:48, afiliado_sindicato:false, presentismo:false, adherentes:0, adicionales_fijos:[], conceptos_recurrentes:[], ganancias_aplica:false };
function recibo(over) {
  return run(`computeRecibo(${J(Object.assign({ empleado:EMPR, periodo:'2026-11-01', tipo:'mensual', novedad:{}, escala:null, convenio:CONV, previsional:PREV, ganTabla:null, catalogo:CATR, acumulados:{}, hoy:'2026-11-30' }, over || {}))})`);
}
const contribDe = r => Object.fromEntries(r.contribuciones.map(c => [c.codigo, c]));

test('FAL (Título II): línea 649 al fal_pct sobre la base SIPA y contribución SIPA reducida en la misma proporción (art. 76)', () => {
  const r = recibo({ previsional:{...PREV, fal_pct:2.5} });
  const c = contribDe(r);
  assert.equal(c['649'].importe, 25000);         // 1.000.000 × 2,5 %
  assert.equal(c['649'].pct, 2.5);
  assert.equal(c['644'].importe, 82700);         // (10,77 − 2,5) % × 1.000.000
  assert.equal(c['644'].pct, 8.27);
  assert.equal(r.contribuciones_total, 82700 + 25000 + 15900 + 9400 + 47000 + 51000 + 9000);   // el costo total no cambia respecto de sin FAL
  assert.equal(recibo().contribuciones_total, r.contribuciones_total);
  assert.equal(contribDe(recibo())['649'], undefined);                  // fal_pct 0 → sin línea
});
test('art. 133: descuentos voluntarios por encima del 20 % de la remuneración en dinero → alerta (no bloquea)', () => {
  const r = recibo({ novedad:{adelanto:150000}, empleado:{...EMPR, conceptos_recurrentes:[{codigo:'227',importe:100000,cuotas_total:10,cuotas_pagadas:0,desde:'2026-01-01'}]} });
  assert.equal(imp(r,'223'), 150000); assert.equal(imp(r,'227'), 100000);
  assert.ok(r.alertas.some(a => a.includes('20 %') && a.includes('art. 133')), r.alertas.join(' | '));
  const ok = recibo({ novedad:{adelanto:150000} });
  assert.ok(!ok.alertas.some(a => a.includes('art. 133')));
});
test('tiempo parcial (art. 92 ter): la obra social se aporta sobre la remuneración de tiempo completo; jubilación sobre la real', () => {
  // mensualizado a 24 h con sueldo pactado de 500.000 (la mitad de la jornada legal)
  const r = recibo({ empleado:{...EMPR, horas_semanales:24, sueldo_pactado:500000} });
  assert.equal(imp(r,'1'), 500000);
  assert.equal(imp(r,'200'), 55000);             // 11 % × 500.000 (remuneración real)
  assert.equal(imp(r,'202'), 30000);             // 3 % × 1.000.000 (equivalente tiempo completo = 500.000 / (24/48))
  assert.equal(r.bases.rem_topeado_tc, 1000000);
  assert.ok(r.alertas.some(a => a.includes('tiempo parcial')));
  const full = recibo();
  assert.equal(imp(full,'202'), 30000);
  assert.equal(full.bases.rem_topeado_tc, 1000000);
});

// ─── recibo: composición con FAL ────────────────────────────────────────
test('_reciboComposicion: el FAL (649) suma en Seguridad Social del empleador', () => {
  const item = { bruto:1000000, no_remunerativo:0, aportes:170000, neto:830000, contribuciones:240000, art:0, liquidacion_conceptos:[],
    contribuciones_detalle:[{codigo:'644',importe:82700},{codigo:'649',importe:25000},{codigo:'645',importe:51000}] };
  const c = run(`_reciboComposicion(${J(item)},${J(CATR)})`);
  assert.equal(c.ss.emp, 107700);
  assert.equal(c.otros.emp, 0);
});

// ─── art. 25: certificado de trabajo ────────────────────────────────────
test('renderCertificadoTrabajo: datos del art. 80 LCT / art. 25 Ley 27.802', () => {
  const html = run(`renderCertificadoTrabajo(${J({ empresa:{razon_social:'VITALMET SA',domicilio:'Perú 246',cuit:'30123456789'}, empleado:{nombre:'PEREZ, ANA',cuil:'27123456789',legajo:'7',fecha_ingreso:'2020-03-10',fecha_egreso:'2026-09-20',tarea:'Administrativa',categoria_escala:'Administrativo A1',causa_egreso:'renuncia'},
    acumulados:[{anio:2026,mes:8,tipo:'mensual',bruto:1000000,no_remunerativo:50000},{anio:2026,mes:7,tipo:'mensual',bruto:990000,no_remunerativo:50000}], fechaEmision:'2026-09-25' })})`);
  ['CERTIFICADO DE TRABAJO','VITALMET SA','30-12345678-9','PEREZ, ANA','27-12345678-9','10/03/2020','20/09/2026','Administrativa','Art. 80','art. 25','08/2026','1.000.000,00','ARCA'].forEach(s => assert.ok(html.includes(s), `falta "${s}"`));
});
