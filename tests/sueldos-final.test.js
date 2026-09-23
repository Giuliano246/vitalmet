'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CAT = [{codigo:'20',tipo:'remunerativo',nombre:'Aguinaldo'},{codigo:'28',tipo:'remunerativo',nombre:'SAC proporcional'},{codigo:'517',tipo:'no_remunerativo'},{codigo:'521',tipo:'no_remunerativo'},{codigo:'530',tipo:'no_remunerativo'},{codigo:'531',tipo:'no_remunerativo'},{codigo:'532',tipo:'no_remunerativo'},{codigo:'533',tipo:'no_remunerativo'}];
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
});
test('computeLiquidacionFinal: renuncia → sólo proporcionales', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'renuncia', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  assert.deepEqual(JSON.parse(JSON.stringify(r.conceptos.map(c => c.codigo).sort())), ['28','517','521']);
});
test('computeLiquidacionFinal: tope indemnizatorio y mínimo de un mes', () => {
  const base = { empleado:{fecha_ingreso:'2026-07-01',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1000000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:40000,dias_trabajados:20}} };
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:0 })})`).conceptos.find(c=>c.codigo==='530').importe, 1000000);   // mínimo 1 mes
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:700000 })})`).conceptos.find(c=>c.codigo==='530').importe, 700000);
});
