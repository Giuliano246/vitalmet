'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CAT = [
  {codigo:'20',tipo:'remunerativo',nombre:'Aguinaldo',regla:{orden:15}},
  {codigo:'28',tipo:'remunerativo',nombre:'SAC proporcional',regla:{orden:16}},
  {codigo:'517',tipo:'no_remunerativo',regla:{orden:517}},
  {codigo:'521',tipo:'no_remunerativo',regla:{orden:521}},
  {codigo:'530',tipo:'no_remunerativo',regla:{orden:530}},
  {codigo:'531',tipo:'no_remunerativo',regla:{orden:531}},
  {codigo:'532',tipo:'no_remunerativo',regla:{orden:532}},
  {codigo:'533',tipo:'no_remunerativo',regla:{orden:533}},
];
const ACUM = [1,2,3,4,5,6].map(m => ({ anio:2026, mes:m, tipo:'mensual', bruto: 1000000 + m*10000, dias_trabajados:30 }));

test('computeSAC: semestre completo = 50 % de la mejor remuneración', () => {
  const s = run(`computeSAC(${J({ empleado:{fecha_ingreso:'2020-01-01'}, periodo:'2026-06-01', acumulados:ACUM, catalogo:CAT })})`);
  assert.equal(s.codigo, '20'); assert.equal(s.mejor_rem, 1060000); assert.equal(s.importe, 530000);
});
test('computeSAC: ingreso 15/03 → proporcional a los días del semestre (108 de 181)', () => {
  const s = run(`computeSAC(${J({ empleado:{fecha_ingreso:'2026-03-15'}, periodo:'2026-06-01', acumulados:ACUM.slice(2), catalogo:CAT })})`);
  assert.equal(s.codigo, '28'); assert.equal(s.dias_trabajados, 108); assert.equal(s.dias_semestre, 181);
  assert.equal(s.importe, 316243.09);                                    // 1.060.000 × 0,5 × 108/181
});
test('computeSAC: las quincenas se suman por mes', () => {
  const ac = [{anio:2026,mes:1,tipo:'quincena1',bruto:400000,dias_trabajados:15},{anio:2026,mes:1,tipo:'quincena2',bruto:450000,dias_trabajados:15},{anio:2026,mes:2,tipo:'mensual',bruto:800000,dias_trabajados:30}];
  assert.equal(run(`computeSAC(${J({ empleado:{fecha_ingreso:'2020-01-01'}, periodo:'2026-06-01', acumulados:ac, catalogo:CAT })})`).mejor_rem, 850000);
});
test('computeSAC: semestre jul-dic, egreso 15/11 → 138 de 184 días', () => {
  const s = run(`computeSAC(${J({ empleado:{fecha_ingreso:'2020-01-01',fecha_egreso:'2026-11-15'}, periodo:'2026-12-01', acumulados:[], catalogo:CAT })})`);
  assert.equal(s.dias_semestre, 184); assert.equal(s.dias_trabajados, 138); assert.equal(s.codigo, '28');
});

test('computeLiquidacionFinal: despido sin causa a los 2a 4m, mensual 1.200.000, sin preaviso', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:false, topeIndemnizatorio:0,
    acumulados:[7,8].map(m=>({anio:2026,mes:m,tipo:'mensual',bruto:1200000,dias_trabajados:30})), catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[{codigo:'1',importe:800000,dc:'C'}],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const imp = c => (r.conceptos.find(x => x.codigo === c) || {}).importe;
  assert.equal(r.detalle.anios_indemnizacion, 3);                        // 2a 4m: la fracción de 4 meses (> 3) cuenta como año
  assert.equal(imp('530'), 3600000);                                      // 1.200.000 × 3
  assert.equal(imp('531'), 1200000);                                      // preaviso 1 mes (antigüedad ≤ 5 años)
  assert.equal(imp('532'), 400000);                                       // integración: 10 días que faltan del mes
  assert.equal(imp('533'), 133333.33);                                    // (531 + 532) / 12
  assert.equal(imp('28'), 267391.30);                                     // SAC prop: 1.200.000 × 0,5 × 82/184 (01/07 → 20/09 = 82 días; H2 2026 = 184 días)
  // vacaciones no gozadas: 14 × 263/365 = 10,09 → 10 días × 48.000
  assert.equal(imp('517'), 480000); assert.equal(imp('521'), 40000);
  assert.equal(r.conceptos.some(c => c.codigo === '1'), true);
  // M4: orden por regla.orden del catálogo; el '1' del recibo parcial (sin regla) queda al final
  assert.deepEqual(JSON.parse(JSON.stringify(r.conceptos.map(c => c.codigo))), ['28','517','521','530','531','532','533','1']);
  assert.ok(r.alertas.includes('Sin tope indemnizatorio cargado: se usa la mejor remuneración sin tope'));
});
test('computeLiquidacionFinal: renuncia → sólo proporcionales, SAC recalculado con mejorNormal sin acumulados', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'renuncia', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const imp = c => (r.conceptos.find(x => x.codigo === c) || {}).importe;
  assert.deepEqual(JSON.parse(JSON.stringify(r.conceptos.map(c => c.codigo).sort())), ['28','517','521']);
  assert.equal(imp('28'), 267391.30);                                     // R24: sin acumulados, se usa mejorNormal = 1.200.000 × 0,5 × 82/184
});
test('computeLiquidacionFinal: vacaciones ya gozadas por completo → sin 517/521', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'renuncia', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:10, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const codigos = r.conceptos.map(c => c.codigo);
  assert.ok(!codigos.includes('517')); assert.ok(!codigos.includes('521'));
});
test('computeLiquidacionFinal R26: vacaciones no gozadas usan días trabajados del año (no corridos desde el 1/1)', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2026-08-01',modalidad:'mensual',convenio:'fuera',sueldo_pactado:900000}, fechaEgreso:'2026-09-20', causa:'renuncia', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:30000,dias_trabajados:20}} })})`);
  const imp = c => (r.conceptos.find(x => x.codigo === c) || {}).importe;
  assert.equal(r.detalle.dias_vac_prop, 2);                              // diasVacacionesLCT(0, 51) = 2 (51 días trabajados: 01/08 → 20/09)
  assert.equal(imp('517'), 60000);                                       // 2 × 30.000
  assert.equal(imp('521'), 5000);                                        // 517 / 12
});
test('computeLiquidacionFinal: tope indemnizatorio y mínimo de un mes', () => {
  const base = { empleado:{fecha_ingreso:'2026-03-01',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1000000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:40000,dias_trabajados:20}} };
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:0 })})`).conceptos.find(c=>c.codigo==='530').importe, 1000000);   // mínimo 1 mes
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:700000 })})`).conceptos.find(c=>c.codigo==='530').importe, 700000);
});
test('computeLiquidacionFinal R28 / Ley 27.802: período de prueba (6 meses) — sólo proporcionales, sin 530/531/532/533', () => {
  // Hasta la 083 el período de prueba era de 3 meses y pagaba 15 días de preaviso; desde la
  // Ley 27.742 son 6 meses y el art. 48 de la Ley 27.802 elimina el preaviso en período de prueba.
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2026-08-01',modalidad:'mensual',convenio:'fuera',sueldo_pactado:900000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:false, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:30000,dias_trabajados:20}} })})`);
  const codigos = r.conceptos.map(c => c.codigo);
  ['28','517','521'].forEach(c => assert.ok(codigos.includes(c), `falta ${c}`));
  ['530','531','532','533'].forEach(c => assert.ok(!codigos.includes(c), `no debería estar ${c}`));
  assert.equal(r.detalle.periodo_prueba, true);
  assert.ok(r.alertas.some(a => a.startsWith('Período de prueba (6 meses)')));
});
test('computeLiquidacionFinal: con preaviso otorgado no hay 531/532/533', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[7,8].map(m=>({anio:2026,mes:m,tipo:'mensual',bruto:1200000,dias_trabajados:30})), catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const codigos = r.conceptos.map(c => c.codigo);
  ['531','532','533'].forEach(c => assert.ok(!codigos.includes(c)));
  assert.ok(codigos.includes('530'));
});
test('computeLiquidacionFinal: egreso el último día del mes → sin integración (532)', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-30', causa:'despido_sin_causa', preavisoOtorgado:false, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const codigos = r.conceptos.map(c => c.codigo);
  assert.ok(codigos.includes('531'));
  assert.ok(!codigos.includes('532'));
});
