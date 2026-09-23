'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;

test('antiguedadEntre: años/meses/días con el último día inclusive (recibo: 27/04/2026 → 15/09/2026 = 0a 4m 20d)', () => {
  assert.deepEqual(JSON.parse(JSON.stringify(run(`antiguedadEntre('2026-04-27','2026-09-15')`))), { anios: 0, meses: 4, dias: 20, texto: '0a 4m 20d' });
  assert.deepEqual(JSON.parse(JSON.stringify(run(`antiguedadEntre('2023-03-10','2026-09-30')`))), { anios: 3, meses: 6, dias: 21, texto: '3a 6m 21d' });
  assert.equal(run(`antiguedadEntre(null,'2026-09-30')`).anios, 0);
});
test('antiguedadEntre R16: meses enteros con día clampeado, nunca días negativos en límites de mes', () => {
  // 31/01/2026 + 1 mes clampea a 28/02/2026 (h = hasta+1d = 01/03/2026) → 0a 1m 1d
  const r1 = JSON.parse(JSON.stringify(run(`antiguedadEntre('2026-01-31','2026-02-28')`)));
  assert.ok(r1.dias >= 0);
  assert.deepEqual(r1, { anios: 0, meses: 1, dias: 1, texto: '0a 1m 1d' });
  // 30/01/2026 + 1 mes también clampea a 28/02/2026 (Feb no tiene día 30) → 0a 1m 1d
  const r2 = JSON.parse(JSON.stringify(run(`antiguedadEntre('2026-01-30','2026-02-28')`)));
  assert.ok(r2.dias >= 0);
  assert.deepEqual(r2, { anios: 0, meses: 1, dias: 1, texto: '0a 1m 1d' });
  // 30/12/2025 + 1 mes = 30/01/2026; + otro mes clampea a 28/02/2026 (h = 01/03/2026) → 0a 2m 1d
  const r3 = JSON.parse(JSON.stringify(run(`antiguedadEntre('2025-12-30','2026-02-28')`)));
  assert.ok(r3.dias >= 0);
  assert.deepEqual(r3, { anios: 0, meses: 2, dias: 1, texto: '0a 2m 1d' });
});
test('diasVacacionesLCT: <6 meses 1 cada 20 trabajados; 14/21/28/35', () => {
  assert.equal(run(`diasVacacionesLCT(0, 100)`), 5);
  assert.equal(run(`diasVacacionesLCT(0, 365)`), 14);   // ≥ 6 meses en el año → 14
  assert.equal(run(`diasVacacionesLCT(5, 365)`), 14);
  assert.equal(run(`diasVacacionesLCT(6, 365)`), 21);
  assert.equal(run(`diasVacacionesLCT(11, 365)`), 28);
  assert.equal(run(`diasVacacionesLCT(21, 365)`), 35);
});
test('vigenteA: mayor vigencia ≤ fecha, null si ninguna', () => {
  const l = [{ vigencia_desde: '2026-08-01', v: 'a' }, { vigencia_desde: '2026-10-01', v: 'b' }, { vigencia_desde: '2026-12-01', v: 'c' }];
  assert.equal(run(`vigenteA(${J(l)},'2026-09-30').v`), 'a');
  assert.equal(run(`vigenteA(${J(l)},'2026-10-01').v`), 'b');
  assert.equal(run(`vigenteA(${J(l)},'2026-07-31')`), null);
});
test('numeroALetras: recibo real y casos borde', () => {
  assert.equal(run(`numeroALetras(395310)`), 'TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ');
  assert.equal(run(`numeroALetras(0)`), 'CERO');
  assert.equal(run(`numeroALetras(21)`), 'VEINTIUNO');
  assert.equal(run(`numeroALetras(100)`), 'CIEN');
  assert.equal(run(`numeroALetras(1000000)`), 'UN MILLON');
  assert.equal(run(`numeroALetras(2500116)`), 'DOS MILLONES QUINIENTOS MIL CIENTO DIECISEIS');
});
test('numeroALetras: apócope global (no solo el primer match) en millones y miles', () => {
  assert.equal(run(`numeroALetras(31031000)`), 'TREINTA Y UN MILLONES TREINTA Y UN MIL');
  assert.equal(run(`numeroALetras(21021000)`), 'VEINTIUN MILLONES VEINTIUN MIL');
});
test('diasPeriodo / finPeriodo', () => {
  assert.equal(run(`diasPeriodo('quincena1')`), 15); assert.equal(run(`diasPeriodo('mensual')`), 30);
  assert.equal(run(`finPeriodo('2026-09-01','quincena1')`), '2026-09-15');
  assert.equal(run(`finPeriodo('2026-09-01','quincena2')`), '2026-09-30');
  assert.equal(run(`finPeriodo('2026-02-01','mensual')`), '2026-02-28');
});

// ─── Task 4: computeRecibo ──────────────────────────────────────────────
const N = x => JSON.parse(JSON.stringify(x));
const CAT = [ // subconjunto del catálogo 083 con reglas (mismos jsonb de la migración)
  { codigo:'4', nombre:'Jornal', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{auto:true,aplica_modalidad:'jornal',base:'valor_hora',cantidad:'horas_normales',orden:10} },
  { codigo:'5', nombre:'Feriado', tipo:'remunerativo', codigo_arca:'110007', marcas:'111111111111100', regla:{auto:true,aplica_modalidad:'jornal',base:'valor_hora',factor_horas_dia:true,cantidad:'novedad.feriados_no_trabajados',orden:43} },
  { codigo:'9', nombre:'Antigüedad', tipo:'remunerativo', codigo_arca:'160001', marcas:'111111111111100', regla:{auto:true,base:'basico',pct_param:'antiguedad_pct',cantidad:'legajo.antiguedad_anios',orden:20} },
  { codigo:'3', nombre:'Presentismo', tipo:'remunerativo', codigo_arca:'170001', marcas:'111111111111100', regla:{auto:true,base:'basico_mas_antiguedad',pct_param:'presentismo_pct',cantidad:'1',condicion:'presentismo_ok',orden:30} },
  { codigo:'10', nombre:'Horas extras 50 %', tipo:'remunerativo', codigo_arca:'130001', marcas:'111111111111100', regla:{auto:true,base:'valor_hora_extra',factor:1.5,cantidad:'novedad.hs_extra_50',orden:40} },
  { codigo:'24', nombre:'Complemento IMGR', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{auto:true,aplica_convenio:'uom',base:'complemento_imgr',cantidad:'1',orden:60} },
  { codigo:'102', nombre:'Gratif extraord no rem', tipo:'no_remunerativo', codigo_arca:'540000', marcas:'000011110000000', regla:{auto:true,aplica_convenio:'uom',base:'no_rem_paritaria',cantidad:'1',orden:59} },
  { codigo:'200', nombre:'Jubilación', tipo:'descuento', codigo_arca:'810000', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_jubilacion_pct',cantidad:'1',orden:200} },
  { codigo:'201', nombre:'Ley 19032', tipo:'descuento', codigo_arca:'810001', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_inssjp_pct',cantidad:'1',orden:201} },
  { codigo:'202', nombre:'Obra social', tipo:'descuento', codigo_arca:'810002', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_os_pct',cantidad:'1',orden:202} },
  { codigo:'203', nombre:'Sindicato UOM', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'rem_bruto',pct_param:'cuota_sindical_pct',cantidad:'1',condicion:'afiliado',orden:203} },
  { codigo:'211', nombre:'Sindicato s/no rem', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'no_rem',pct_param:'cuota_sindical_pct',cantidad:'1',condicion:'afiliado',orden:211} },
  { codigo:'208', nombre:'Obra social s/no rem', tipo:'descuento', codigo_arca:'810002', marcas:'000000000000000', regla:{auto:true,base:'no_rem_os',pct_param:'aporte_os_pct',cantidad:'1',orden:208} },
  { codigo:'998', nombre:'Redondeo', tipo:'no_remunerativo', codigo_arca:'799999', marcas:'000000000000000', regla:{auto:true,base:'redondeo',cantidad:'1',orden:998} },
  { codigo:'999', nombre:'Redondeo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'redondeo',cantidad:'1',orden:999} },
];
const CONV = { vigencia_desde:'2026-08-01', imgr:0, no_rem_paritaria:80000, no_rem_codigo:'102', antiguedad_pct:1, horas_mes:200, horas_dia:9, presentismo_pct:0, presentismo_tolerancia_dias:0, sepelio_importe:0, scvo_importe:849.24, cuota_sindical_pct:2.5, aporte_solidario_pct:2, redondeo_a:10, tope_por_quincena:true };
const PREV = { vigencia_desde:'2026-09-01', tope_min:144363.55, tope_max:4691748.47, detraccion:7003.68, aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, aporte_os_adherente_pct:1.5, tipo_empresa:1, contrib_sipa_pct:10.77, contrib_inssjp_pct:1.59, contrib_fne_pct:0.94, contrib_aaff_pct:4.70, contrib_os_pct:5.10, contrib_fsr_pct:0.90, art_pct:0, art_fijo:0, ganancias_tope_retencion_pct:35 };
const EMP = { id:'e1', nombre:'AYALA, RODRIGO', convenio:'uom', modalidad:'jornal', categoria_escala:'Ingresante', fecha_ingreso:'2026-04-27', fecha_ingreso_reconocida:'2026-09-01', horas_semanales:48, afiliado_sindicato:true, presentismo:true, adherentes:0, adicionales_fijos:[], conceptos_recurrentes:[], ganancias_aplica:false };
const ESC = { vigencia_desde:'2026-08-01', categoria:'Ingresante', modalidad:'jornal', valor_hora:4485.97, basico_mensual:0 };
const NOV = { horas_normales:90, hs_extra_50:0, hs_extra_100:0, feriados_no_trabajados:1, feriados_trabajados_hs:0, ausencias_injustificadas:0, enfermedad_dias:0, accidente_dias:0, licencia_paga_dias:0, licencia_sin_goce_dias:0, vacaciones_dias:0, adelanto:0, premio_produccion:0, otros:[] };
function recibo(over) {
  return run(`computeRecibo(${J(Object.assign({ empleado:EMP, periodo:'2026-09-01', tipo:'quincena1', novedad:NOV, escala:ESC, convenio:CONV, previsional:PREV, ganTabla:null, catalogo:CAT, acumulados:{}, hoy:'2026-09-18' }, over || {}))})`);
}
const imp = (r, cod) => (r.conceptos.find(c => c.codigo === cod) || {}).importe;

test('computeRecibo: reproduce el recibo real de la 1ª quincena 09/2026', () => {
  const r = recibo();
  assert.equal(imp(r,'4'), 403737.30); assert.equal(imp(r,'5'), 40373.73);
  assert.equal(r.conceptos.find(c=>c.codigo==='9'), undefined);          // 0 años → no se genera
  assert.equal(imp(r,'102'), 40000);                                      // 80.000/mes × 0,5 quincena
  assert.equal(imp(r,'200'), 48852.21); assert.equal(imp(r,'201'), 13323.33); assert.equal(imp(r,'202'), 13323.33);
  assert.equal(imp(r,'203'), 11102.78); assert.equal(imp(r,'211'), 1000); assert.equal(imp(r,'208'), 1200);
  assert.equal(imp(r,'998'), 0.62); assert.equal(r.conceptos.find(c=>c.codigo==='999'), undefined);
  assert.deepEqual(N(r.totales), { bruto:444111.03, no_remunerativo:40000.62, aportes:88801.65, neto:395310 });
  assert.equal(r.bases.rem_topeado, 444111.03);
  const contrib = Object.fromEntries(r.contribuciones.map(c => [c.codigo, c.importe]));
  assert.deepEqual(N(contrib), { '640':424.62, '642':7005.69, '643':4357.00, '644':47453.61, '645':24689.66, '646':4141.73, '647':20708.63 });
  assert.equal(r.contribuciones_total, 108780.94);
  assert.equal(r.f931.base1, 444111.03); assert.equal(r.f931.base4, 484111.03); assert.equal(r.f931.base8, 484111.03);
  // base9 = LRT (marca 12): la familia ARCA 540000 de 102 sólo marca OS-A/OS-C/FSR (4,5,6,7), no LRT —
  // spec §Motor punto 17 y design doc línea 298 ("difieren correctamente con no rem 540000" sólo en las
  // bases OS); LRT queda igual que sin no remunerativo, = rem_bruto = base1.
  assert.equal(r.f931.base9, 444111.03); assert.equal(r.f931.detraer, 3501.84); assert.equal(r.f931.base10, 440609.19);
  assert.equal(r.f931.rem_bruta, 484111.65); assert.equal(r.f931.horas, 99); assert.equal(r.f931.dias, 0);
  assert.equal(r.conceptos.every(c => c.origen === 'auto' && c.traza && c.traza.formula), true);
});
test('computeRecibo: mensual UOM con antigüedad, presentismo, extras, ausencia (pierde presentismo) y ART', () => {
  const emp = { ...EMP, modalidad:'mensual', categoria_escala:'Administrativo A2', fecha_ingreso:'2023-03-10', fecha_ingreso_reconocida:null };
  const esc = { vigencia_desde:'2026-08-01', categoria:'Administrativo A2', modalidad:'mensual', valor_hora:0, basico_mensual:1200000 };
  const conv = { ...CONV, presentismo_pct:8.33, imgr:1500000 };
  const nov = { ...NOV, horas_normales:null, hs_extra_50:10, hs_extra_100:4, feriados_no_trabajados:0, ausencias_injustificadas:1 };
  const cat = CAT.concat([{ codigo:'16', nombre:'Horas extras 100 %', tipo:'remunerativo', codigo_arca:'130002', marcas:'111111111111100', regla:{auto:true,base:'valor_hora_extra',factor:2,cantidad:'novedad.hs_extra_100',orden:41} }]);
  const r = recibo({ empleado:emp, escala:esc, convenio:conv, novedad:nov, tipo:'mensual', catalogo:cat, previsional:{ ...PREV, art_pct:3, art_fijo:1000 } });
  // básico 1.200.000 × 29/30 = 1.160.000 (1 ausencia injustificada); antigüedad 3 años × 1 % = 34.800 → 1.194.800
  assert.equal(imp(r,'1'), 1160000); assert.equal(imp(r,'9'), 34800);
  assert.equal(r.conceptos.find(c=>c.codigo==='3'), undefined);            // presentismo perdido
  // valor hora extra = (1.200.000 + 36.000) / 200 = 6.180 → 50 %: 6.180×1,5×10 = 92.700 · 100 %: 6.180×2×4 = 49.440
  assert.equal(imp(r,'10'), 92700); assert.equal(imp(r,'16'), 49440);
  // IMGR: 1.194.800 + 80.000 (no rem) = 1.274.800 < 1.500.000 → complemento 225.200
  assert.equal(imp(r,'24'), 225200);
  assert.equal(r.bases.rem_bruto, 1562140);                                // 1.160.000+34.800+92.700+49.440+225.200
  assert.equal(r.art, 47864.20);                                            // 3 % × 1.562.140 + 1.000
  assert.ok(r.alertas.some(a => /presentismo/i.test(a)));
});
test('computeRecibo: fuera de convenio, mes de ingreso (20 días), tope máximo de aportes, sin sindicato ni no rem', () => {
  const emp = { ...EMP, convenio:'fuera', modalidad:'mensual', categoria_escala:null, sueldo_pactado:7500000, fecha_ingreso:'2026-09-11', fecha_ingreso_reconocida:null, afiliado_sindicato:false };
  const r = recibo({ empleado:emp, escala:null, novedad:null, tipo:'mensual' });
  assert.equal(imp(r,'1'), 5000000);                                       // 7.500.000 × 20/30
  assert.equal(r.conceptos.find(c=>c.codigo==='102'), undefined); assert.equal(r.conceptos.find(c=>c.codigo==='203'), undefined);
  assert.equal(r.bases.tope_max_prorr, 3127832.31);                        // 4.691.748,47 × 20/30
  assert.equal(imp(r,'200'), 344061.55);                                   // 11 % del tope prorrateado
  assert.equal(r.f931.dias, 20); assert.equal(r.f931.detraer, 4669.12);    // 7.003,68 × 20/30
  assert.ok(r.alertas.some(a => /tope/i.test(a)));
});
test('computeRecibo: recurrentes (préstamo con última cuota, embargo tope 20 % del neto), adelanto y premio', () => {
  const emp = { ...EMP, conceptos_recurrentes:[{codigo:'227',importe:50000,cuotas_total:3,cuotas_pagadas:2,desde:'2026-07-01'},{codigo:'226',importe:200000,desde:'2026-01-01'}] };
  const cat = CAT.concat([{ codigo:'227', nombre:'Cuota préstamo', tipo:'descuento', codigo_arca:'810007', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',orden:227} },
                          { codigo:'226', nombre:'Embargo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',tope_pct_neto:20,orden:226} },
                          { codigo:'223', nombre:'Adelanto', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'fijo',cantidad:'novedad.adelanto',orden:223} },
                          { codigo:'64', nombre:'Premio', tipo:'remunerativo', codigo_arca:'170002', marcas:'111111111111100', regla:{auto:true,base:'fijo',cantidad:'novedad.premio_produccion',orden:70} }]);
  const r = recibo({ empleado:emp, catalogo:cat, novedad:{ ...NOV, adelanto:30000, premio_produccion:25000 } });
  assert.equal(imp(r,'64'), 25000); assert.equal(imp(r,'223'), 30000); assert.equal(imp(r,'227'), 50000);
  assert.ok(r.alertas.some(a => /última cuota/i.test(a)));
  // neto antes de embargo: (444.111,03+25.000) rem + 40.000 − aportes(17 % de 469.111,03 + 2,5 % ... ) → embargo = min(200.000, 20 % de ese neto)
  const netoSinEmbargo = r.totales.neto + imp(r,'226') - (imp(r,'998')||0) + (imp(r,'999')||0);
  assert.ok(Math.abs(imp(r,'226') - Math.round(netoSinEmbargo*0.2*100)/100) < 1);
});
