// Sueldos 085 — segunda tanda de la Ley 27.802 (texto literal de infoleg 423680):
//   art. 133 Ley 27.802 (art. 9 Ley 14.250): aportes a sindicatos válidos para afiliados y no
//     afiliados ≤ 2 %; la cuota de afiliación queda EXCLUIDA del tope.
//   art. 37 (LCT 133): el tope del 20 % no alcanza a los adelantos (LCT 130: hasta el 50 %).
//   arts. 156-163: RIFL — altas nuevas: 2 % total SIPA + FNE + AAFF y 3 % INSSJP por 48 meses;
//     el FAL se ingresa sin la reducción del art. 76.
//   art. 42 (LCT 197 bis): banco de horas por acuerdo escrito.
//   art. 41 (LCT 154): vacaciones 1/10–30/4, aviso de 30 días, tramos de 7 días o más,
//     verano al menos una vez cada tres años.
//   art. 28 (LCT 95) y LCT 250: contrato a plazo fijo.
//   art. 53 (LCT 255): reingreso — piso = indemnización del último período.
//   art. 52 (LCT 248): fallecimiento — 30 días para pagar.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify; const N = x => JSON.parse(JSON.stringify(x));

// ─── computeRecibo ──────────────────────────────────────────────────────
const CATR = [
  { codigo:'1', nombre:'Sueldo básico', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{orden:1} },
  { codigo:'4', nombre:'Jornal', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{auto:true,aplica_modalidad:'jornal',base:'valor_hora',cantidad:'horas_normales',orden:10} },
  { codigo:'10', nombre:'Horas extras 50 %', tipo:'remunerativo', codigo_arca:'130001', marcas:'111111111111100', regla:{auto:true,base:'valor_hora_extra',factor:1.5,cantidad:'novedad.hs_extra_50',indemniz:'variable',orden:40} },
  { codigo:'200', nombre:'Jubilación', tipo:'descuento', codigo_arca:'810000', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_jubilacion_pct',cantidad:'1',orden:200} },
  { codigo:'203', nombre:'Sindicato UOM', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'rem_bruto',pct_param:'cuota_sindical_pct',cantidad:'1',condicion:'afiliado',orden:203} },
  { codigo:'205', nombre:'Aporte solidario UOM', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'rem_bruto',pct_param:'aporte_solidario_pct',cantidad:'1',condicion:'no_afiliado',orden:205} },
  { codigo:'204', nombre:'Seguro de vida', tipo:'descuento', codigo_arca:'810005', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',art133:true,orden:204} },
  { codigo:'223', nombre:'Adelanto de sueldo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'fijo',cantidad:'novedad.adelanto',orden:223} },
  { codigo:'227', nombre:'Cuota de préstamo', tipo:'descuento', codigo_arca:'810007', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',art133:true,orden:227} },
];
const CONV = { horas_mes:200, horas_dia:8, antiguedad_pct:0, redondeo_a:0, tope_por_quincena:true, scvo_importe:0, cuota_sindical_pct:2.5, aporte_solidario_pct:2, presentismo_pct:0 };
const PREV = { tope_min:0, tope_max:0, detraccion:0, aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, aporte_os_adherente_pct:1.5, tipo_empresa:2,
  contrib_sipa_pct:10.77, contrib_inssjp_pct:1.59, contrib_fne_pct:0.94, contrib_aaff_pct:4.70, contrib_os_pct:5.10, contrib_fsr_pct:0.90, art_pct:0, art_fijo:0, fal_pct:0 };
const EMPM = { id:'e2', nombre:'PEREZ, ANA', convenio:'fuera', modalidad:'mensual', sueldo_pactado:1000000, fecha_ingreso:'2026-01-01', horas_semanales:48, afiliado_sindicato:false, presentismo:false, adherentes:0, adicionales_fijos:[], conceptos_recurrentes:[], ganancias_aplica:false };
const EMPJ = { id:'e1', nombre:'AYALA, RODRIGO', convenio:'uom', modalidad:'jornal', categoria_escala:'Operario', fecha_ingreso:'2026-01-01', horas_semanales:48, afiliado_sindicato:true, presentismo:false, adherentes:0, adicionales_fijos:[], conceptos_recurrentes:[], ganancias_aplica:false };
const ESC = { vigencia_desde:'2026-08-01', categoria:'Operario', modalidad:'jornal', valor_hora:5000, basico_mensual:0 };
function recibo(over) {
  return run(`computeRecibo(${J(Object.assign({ empleado:EMPM, periodo:'2026-11-01', tipo:'mensual', novedad:{}, escala:null, convenio:CONV, previsional:PREV, ganTabla:null, catalogo:CATR, acumulados:{}, hoy:'2026-11-30' }, over || {}))})`);
}
const imp = (r, cod) => (r.conceptos.find(c => c.codigo === cod) || {}).importe;
const contribDe = r => Object.fromEntries(r.contribuciones.map(c => [c.codigo, c]));

test('aporte solidario por encima del 2 % → alerta (art. 9 Ley 14.250); la cuota de afiliación del 2,5 % no alerta', () => {
  const noAfil = recibo({ empleado:{...EMPJ, afiliado_sindicato:false}, escala:ESC, novedad:{horas_normales:160}, convenio:{...CONV, aporte_solidario_pct:3} });
  assert.equal(imp(noAfil,'205'), 24000);                                  // se descuenta lo configurado: 800.000 × 3 %
  assert.ok(noAfil.alertas.some(a => a.includes('2 %') && a.includes('solidario')), noAfil.alertas.join(' | '));
  const ok = recibo({ empleado:{...EMPJ, afiliado_sindicato:false}, escala:ESC, novedad:{horas_normales:160} });
  assert.ok(!ok.alertas.some(a => a.includes('solidario')));
  const afil = recibo({ empleado:EMPJ, escala:ESC, novedad:{horas_normales:160} });
  assert.equal(imp(afil,'203'), 20000);                                    // cuota de afiliación 2,5 %: excluida del tope
  assert.ok(!afil.alertas.some(a => a.includes('solidario')));
});

test('art. 133: el adelanto NO entra en el tope del 20 %; seguro + préstamo sí', () => {
  const soloAdelanto = recibo({ novedad:{adelanto:400000} });
  assert.ok(!soloAdelanto.alertas.some(a => a.includes('art. 133')));
  const vol = recibo({ novedad:{otros:[{codigo:'204',importe:120000}]}, empleado:{...EMPM, conceptos_recurrentes:[{codigo:'227',importe:100000,cuotas_total:10,cuotas_pagadas:0,desde:'2026-01-01'}]} });
  assert.ok(vol.alertas.some(a => a.includes('20 %') && a.includes('art. 133')), vol.alertas.join(' | '));
});
test('art. 130: adelanto por encima del 50 % de la remuneración del período → alerta', () => {
  const r = recibo({ novedad:{adelanto:600000} });
  assert.ok(r.alertas.some(a => a.includes('50 %') && a.includes('art. 130')), r.alertas.join(' | '));
  assert.ok(!recibo({ novedad:{adelanto:500000} }).alertas.some(a => a.includes('art. 130')));
});

test('RIFL: 2 % total SIPA+FNE+AAFF y 3 % INSSJP durante 48 meses; FAL sin reducción; obra social igual', () => {
  const r = recibo({ empleado:{...EMPM, fecha_ingreso:'2026-06-01', rifl_desde:'2026-06-01'}, previsional:{...PREV, fal_pct:2.5} });
  const c = contribDe(r);
  assert.equal(c['644'].importe, 20000); assert.equal(c['644'].pct, 2);
  assert.equal(c['642'].importe, 30000); assert.equal(c['642'].pct, 3);
  assert.equal(c['646'], undefined); assert.equal(c['647'], undefined);
  assert.equal(c['649'].importe, 25000);                                    // FAL completo, sin bajar la SIPA (art. 76)
  assert.equal(c['645'].importe, 51000); assert.equal(c['643'].importe, 9000);
  assert.equal(r.contribuciones_total, 135000);
  assert.ok(r.alertas.some(a => a.includes('RIFL')));
});
test('RIFL: a partir del mes 49 vuelve el régimen general', () => {
  const dentro = recibo({ periodo:'2030-05-01', hoy:'2030-05-31', empleado:{...EMPM, fecha_ingreso:'2026-06-01', rifl_desde:'2026-06-01'} });   // mes 48
  assert.equal(contribDe(dentro)['644'].pct, 2);
  const fuera = recibo({ periodo:'2030-06-01', hoy:'2030-06-30', empleado:{...EMPM, fecha_ingreso:'2026-06-01', rifl_desde:'2026-06-01'} });   // mes 49
  assert.equal(contribDe(fuera)['644'].pct, 10.77);
  assert.ok(contribDe(fuera)['647']);
});

test('banco de horas: las horas compensadas se pagan como horas normales del jornal; las acreditadas no se pagan', () => {
  const r = recibo({ empleado:{...EMPJ, banco_horas:true, banco_horas_acuerdo:'2026-10-01'}, escala:ESC, novedad:{horas_normales:152, hs_banco_compensadas:8, hs_banco_acreditadas:4, hs_extra_50:0} });
  assert.equal(imp(r,'4'), 800000);                                        // (152 + 8) h × 5.000
  assert.equal(imp(r,'10'), undefined);                                    // las 4 h acreditadas no generan extras
  assert.equal(r.bases.horas_normales, 160);
  assert.ok(r.alertas.some(a => a.includes('Banco de horas')));
});
test('banco de horas sin acuerdo escrito en el legajo → alerta y no se compensa', () => {
  const r = recibo({ empleado:EMPJ, escala:ESC, novedad:{horas_normales:152, hs_banco_compensadas:8} });
  assert.equal(imp(r,'4'), 760000);
  assert.ok(r.alertas.some(a => a.includes('197 bis')), r.alertas.join(' | '));
});
test('computeBancoHoras: saldo acumulado por empleado hasta el período', () => {
  const novs = [
    { empleado_id:'e1', periodo:'2026-10-01', tipo:'mensual', hs_banco_acreditadas:10, hs_banco_compensadas:0 },
    { empleado_id:'e1', periodo:'2026-11-01', tipo:'quincena1', hs_banco_acreditadas:4, hs_banco_compensadas:8 },
    { empleado_id:'e1', periodo:'2026-12-01', tipo:'mensual', hs_banco_acreditadas:20, hs_banco_compensadas:0 },
    { empleado_id:'e9', periodo:'2026-10-01', tipo:'mensual', hs_banco_acreditadas:99, hs_banco_compensadas:0 },
  ];
  assert.deepEqual(N(run(`computeBancoHoras(${J(novs)},'e1','2026-11-01')`)), { acreditadas:14, compensadas:8, saldo:6 });
  assert.equal(run(`computeBancoHoras(${J(novs)},'e1')`).saldo, 26);
});

// ─── computeLiquidacionFinal ────────────────────────────────────────────
const CAT = [
  {codigo:'20',tipo:'remunerativo',regla:{orden:15}},{codigo:'28',tipo:'remunerativo',regla:{orden:16}},
  {codigo:'517',tipo:'no_remunerativo',regla:{orden:517}},{codigo:'521',tipo:'no_remunerativo',regla:{orden:521}},
  {codigo:'530',tipo:'no_remunerativo',regla:{orden:530}},{codigo:'531',tipo:'no_remunerativo',regla:{orden:531}},
  {codigo:'532',tipo:'no_remunerativo',regla:{orden:532}},{codigo:'533',tipo:'no_remunerativo',regla:{orden:533}},
  {codigo:'535',tipo:'no_remunerativo',regla:{orden:535}},
];
const EMP = {fecha_ingreso:'2020-03-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1000000};
function final(over) {
  return run(`computeLiquidacionFinal(${J(Object.assign({ empleado:EMP, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, topeIndemnizatorio:0, acumulados:[], catalogo:CAT, vacacionesGozadasAnio:14, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:40000,dias_trabajados:20}} }, over || {}))})`);
}
const codigos = r => r.conceptos.map(c => c.codigo);

test('fin de contrato a plazo fijo (LCT 250): con un año o más, 50 % de la indemnización; con menos, nada', () => {
  const r = final({ causa:'fin_contrato', empleado:{...EMP, fecha_ingreso:'2025-03-01'} });            // 1a 6m 20d → 2 años
  assert.equal(imp(r,'530'), 1000000);                                     // 1.000.000 × 2 × 50 %
  ['531','532','533'].forEach(c => assert.ok(!codigos(r).includes(c)));
  assert.ok(r.alertas.some(a => a.includes('art. 250')));
  const corto = final({ causa:'fin_contrato', empleado:{...EMP, fecha_ingreso:'2026-01-10'} });
  assert.ok(!codigos(corto).includes('530'));
});
test('despido antes del vencimiento del plazo (LCT 95): la antigüedad se cuenta hasta el fin del plazo pactado', () => {
  const r = final({ empleado:{...EMP, fecha_ingreso:'2025-03-01'}, fechaFinPlazo:'2028-02-29' });       // 3 años al vencimiento
  assert.equal(r.detalle.anios_indemnizacion, 3);
  assert.equal(imp(r,'530'), 3000000);
  assert.ok(r.alertas.some(a => a.includes('art. 95')));
  // si el plazo ya venció a la fecha de egreso no cambia nada
  assert.equal(final({ empleado:{...EMP, fecha_ingreso:'2025-03-01'}, fechaFinPlazo:'2026-08-31' }).detalle.anios_indemnizacion, 2);
});
test('reingreso (LCT 255): el piso es la indemnización del último período, no un mes', () => {
  // antigüedad total 7 años (7.000.000), último período desde 01/2024 → 2a 8m 20d = 3 años (3.000.000)
  const r = final({ indemnizacionAnterior: 6000000, fechaReingreso:'2024-01-01' });
  assert.equal(imp(r,'530'), 3000000);
  const sinFecha = final({ indemnizacionAnterior: 6000000 });
  assert.equal(imp(sinFecha,'530'), 1000000);                               // sin fecha de reingreso: piso de un mes (084)
  const holgado = final({ indemnizacionAnterior: 1000000, fechaReingreso:'2024-01-01' });
  assert.equal(imp(holgado,'530'), 6000000);
});
test('base indemnizatoria manual: reemplaza a la calculada cuando no hay historia en el sistema', () => {
  const r = final({ baseManual: 1350000 });
  assert.equal(r.detalle.mejor_rem_normal, 1350000);
  assert.equal(imp(r,'530'), 9450000);                                     // 1.350.000 × 7
  assert.ok(r.alertas.some(a => a.includes('cargada a mano')));
});
test('fallecimiento: recuerda el plazo de 30 días para pagar (art. 248)', () => {
  assert.ok(final({ causa:'fallecimiento' }).alertas.some(a => a.includes('30 días')));
});
test('baja con saldo de banco de horas: avisa las horas pendientes', () => {
  assert.ok(final({ causa:'renuncia', bancoHorasSaldo: 12 }).alertas.some(a => a.includes('12') && a.toLowerCase().includes('banco de horas')));
});

// ─── vacaciones (LCT 154) ───────────────────────────────────────────────
const vac = o => N(run(`validarVacaciones(${J(Object.assign({ desde:'2027-01-04', hasta:'2027-01-17', notificado_el:'2026-11-20', diasCorresponden:14, programadas:[] }, o || {}))})`));
test('validarVacaciones: tramo de 14 días en enero notificado con más de 30 días → sin errores', () => {
  const v = vac();
  assert.equal(v.dias, 14); assert.deepEqual(v.errores, []); assert.equal(v.temporada_verano, true);
});
test('validarVacaciones: tramo menor a 7 días → error; salvo que sea todo el saldo que queda', () => {
  assert.ok(vac({ hasta:'2027-01-08' }).errores.some(e => e.includes('7')));                       // 5 días
  const saldo = vac({ desde:'2027-03-01', hasta:'2027-03-05', notificado_el:'2027-01-10', programadas:[{desde:'2027-01-04',hasta:'2027-01-12'}] });   // ya gozó 9, quedan 5
  assert.deepEqual(saldo.errores, []);
});
test('validarVacaciones: fuera del 1/10–30/4 exige acuerdo; con acuerdo pasa', () => {
  assert.ok(vac({ desde:'2027-07-05', hasta:'2027-07-18', notificado_el:'2027-05-01' }).errores.some(e => e.includes('1/10')));
  assert.deepEqual(vac({ desde:'2027-07-05', hasta:'2027-07-18', notificado_el:'2027-05-01', acuerdoFueraPeriodo:true }).errores, []);
});
test('validarVacaciones: aviso con menos de 30 días de anticipación o sin notificar', () => {
  assert.ok(vac({ notificado_el:'2026-12-20' }).errores.some(e => e.includes('30 días')));
  assert.ok(vac({ notificado_el:null }).avisos.some(e => e.toLowerCase().includes('notific')));
});
test('validarVacaciones: no puede superar los días que corresponden sumando lo ya programado', () => {
  const v = vac({ programadas:[{desde:'2026-12-01',hasta:'2026-12-07'}] });                        // 7 + 14 > 14
  assert.ok(v.errores.some(e => e.includes('corresponden')));
  assert.equal(v.ya_programados, 7);
});
test('validarVacaciones: sin verano en los dos años anteriores → aviso de temporada de verano', () => {
  const v = vac({ desde:'2027-04-05', hasta:'2027-04-18', notificado_el:'2027-02-01', historial:[{anio:2025,desde:'2025-10-06',hasta:'2025-10-19'},{anio:2026,desde:'2026-04-06',hasta:'2026-04-19'}] });
  assert.ok(v.avisos.some(a => a.includes('verano')));
});
test('diasVacacionesEnPeriodo: días programados que caen dentro del período de la novedad', () => {
  const prog = [{ empleado_id:'e1', desde:'2027-01-25', hasta:'2027-02-07' }, { empleado_id:'e2', desde:'2027-01-04', hasta:'2027-01-17' }];
  assert.equal(run(`diasVacacionesEnPeriodo(${J(prog)},'e1','2027-01-01','2027-01-31')`), 7);
  assert.equal(run(`diasVacacionesEnPeriodo(${J(prog)},'e1','2027-02-01','2027-02-15')`), 7);
  assert.equal(run(`diasVacacionesEnPeriodo(${J(prog)},'e1','2027-03-01','2027-03-31')`), 0);
});
test('renderNotificacionVacaciones: comunicación escrita con fechas, días y cita legal', () => {
  const html = run(`renderNotificacionVacaciones(${J({ empresa:{razon_social:'VITALMET SA',cuit:'30123456789'}, empleado:{nombre:'PEREZ, ANA',cuil:'27123456789',legajo:'7'}, vacacion:{anio:2026,desde:'2027-01-04',hasta:'2027-01-17',dias:14}, fechaEmision:'2026-11-20' })})`);
  ['VITALMET SA','PEREZ, ANA','04/01/2027','17/01/2027','14','art. 154','18/01/2027'].forEach(s => assert.ok(html.includes(s), `falta "${s}"`));
});
