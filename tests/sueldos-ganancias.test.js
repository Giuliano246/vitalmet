'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const TABLA = { vigencia_desde:'2026-07-01', gni_anual:6019671.36, deduccion_especial_anual:28894422.56, conyuge_anual:5669323.06, hijo_anual:2859060.30, hijo_incap_anual:5718120.61,
  tramos:[{desde:0,hasta:2336953.69,fijo:0,pct:5},{desde:2336953.69,hasta:4673907.37,fijo:116847.68,pct:9},{desde:4673907.37,hasta:7010861.06,fijo:327173.51,pct:12},{desde:7010861.06,hasta:10516291.59,fijo:607607.96,pct:15},{desde:10516291.59,hasta:21032583.19,fijo:1133422.53,pct:19},{desde:21032583.19,hasta:31548874.78,fijo:3131517.94,pct:23},{desde:31548874.78,hasta:47323312.17,fijo:5550265.01,pct:27},{desde:47323312.17,hasta:70984968.27,fijo:9809363.11,pct:31},{desde:70984968.27,hasta:null,fijo:17144476.49,pct:35}] };
const CAT = [{codigo:'1',tipo:'remunerativo'},{codigo:'16',tipo:'remunerativo'},{codigo:'200',tipo:'descuento'},{codigo:'201',tipo:'descuento'},{codigo:'202',tipo:'descuento'},{codigo:'203',tipo:'descuento'},{codigo:'223',tipo:'descuento'}];
const PREV = { aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, ganancias_tope_retencion_pct:35 };
const conc = (bruto, extras100=0) => [{codigo:'1',importe:bruto},{codigo:'16',importe:extras100},{codigo:'200',importe:(bruto+extras100)*0.11},{codigo:'201',importe:(bruto+extras100)*0.03},{codigo:'202',importe:(bruto+extras100)*0.03}];
const gan = (o) => JSON.parse(JSON.stringify(run(`computeGanancias(${J(Object.assign({ empleado:{ganancias_aplica:true,conyuge:false,hijos:0,hijos_incap:0,ganancias_deducciones:[]}, periodo:'2026-01-01', tipo:'mensual', conceptos:conc(5000000), catalogo:CAT, tabla:TABLA, acumulados:null, previsional:PREV, remBruto:5000000, noRem:0 }, o))})`)));

test('computeGanancias: enero, soltero sin deducciones, 5.000.000 brutos → 229.345,78 (cálculo a mano RG 4003)', () => {
  const g = gan();
  // rem gravada = (5.000.000 + 416.666,67 SAC 1/12) × (1 − 17 %) = 4.495.833,33
  assert.equal(g.rem_gravada_acum, 4495833.33);
  assert.equal(g.deducciones_personales_acum, 2909507.83);              // (GNI + especial) / 12
  assert.equal(g.gnsi_acum, 1586325.50);
  assert.equal(g.impuesto_acum, 229345.78);                              // tramo 5: 94.451,88 + 19 % × (1.586.325,50 − 876.357,63)
  assert.equal(g.retencion_mes, 229345.78); assert.equal(g.tabla_vigencia, '2026-07-01');
});
test('computeGanancias: febrero acumula y descuenta lo retenido; cónyuge + 1 hijo + alquiler con tope 40 % GNI', () => {
  const emp = { ganancias_aplica:true, conyuge:true, hijos:1, hijos_incap:0, ganancias_deducciones:[{tipo:'alquiler',importe_mensual:900000,periodo_desde:'2026-01',periodo_hasta:'2026-12'}] };
  const g = gan({ empleado:emp, periodo:'2026-02-01', acumulados:{ rem_gravada_acum:4495833.33, retenido_previo:229345.78, sac_prorrateado_acum:416666.67, sac_real_acum:0 } });
  assert.equal(g.rem_gravada_acum, 8991666.66);
  // personales: (6.019.671,36 + 28.894.422,56 + 5.669.323,06 + 2.859.060,30) × 2/12 = 7.240.412,88
  assert.equal(g.deducciones_personales_acum, 7240412.88);
  // alquiler: 1.800.000 pagados, tope 40 % de GNI acum (1.003.278,56 × 0,4 = 401.311,42)
  assert.equal(g.deducciones_f572_acum, 401311.42);
  assert.equal(g.gnsi_acum, 1349942.36);
  // tramos × 2/12: hasta 389.492,28 (5 %), 778.984,56 (9 %), 1.168.476,84 (12 %), 1.752.715,27 (15 %) → tramo 4: 101.267,99 + 15 % × (1.349.942,36 − 1.168.476,84)
  assert.equal(g.impuesto_acum, 128487.82);
  assert.equal(g.retencion_mes, -100857.96);                             // devolución
});
test('computeGanancias: horas extras 100 % exentas — aportes prorrateados a la porción gravada (R9)', () => {
  const g = gan({ conceptos:conc(3000000, 2000000), remBruto:5000000, previsional:{ ...PREV, ganancias_tope_retencion_pct:1 } });
  // aportes 17 % s/5.000.000 = 850.000, prorrateado a la porción gravada 3.000.000/5.000.000 = 60 % → 510.000
  // neto = 3.000.000 − 510.000 = 2.490.000; SAC doceavo = 3.000.000/12 × 0,83 = 207.500
  assert.equal(g.rem_gravada_mes, 2697500);
  // rem gravada acum (2.697.500) queda por debajo de las deducciones personales de enero (2.909.507,83):
  // gnsi = 0 → impuesto = 0 → no hay nada que topear.
  assert.equal(g.tope_aplicado, false); assert.equal(g.retencion_mes, 0);
});
test('computeGanancias: junio SAC — reemplaza doceavos por el SAC real', () => {
  const g = gan({ tipo:'sac', periodo:'2026-06-01', conceptos:[{codigo:'1',importe:2500000},{codigo:'200',importe:275000},{codigo:'201',importe:75000},{codigo:'202',importe:75000}], remBruto:2500000,
    acumulados:{ rem_gravada_acum:22479166.65, retenido_previo:1500000, sac_prorrateado_acum:2083333.35, sac_real_acum:0 } });
  // se descuentan los 5 doceavos prorrateados (2.083.333,35 × 0,83) y se suma el SAC real neto (2.500.000 × 0,83)
  assert.equal(g.rem_gravada_mes, 345833.32);
  assert.equal(g.sac_prorrateado_acum, 0);        // el semestre se cierra: no quedan doceavos pendientes
  assert.equal(g.sac_real_acum, 2500000);
});
test('computeGanancias: rama del tope — retención topeada al 1 % del bruto cuando el impuesto acumulado excede el tope', () => {
  const g = gan({ periodo:'2026-02-01', conceptos:conc(5000000), remBruto:5000000, previsional:{ ...PREV, ganancias_tope_retencion_pct:1 },
    acumulados:{ rem_gravada_acum:30000000, retenido_previo:0, sac_prorrateado_acum:0, sac_real_acum:0 } });
  assert.ok(g.impuesto_acum > 50000);              // muy por encima del tope forzado al 1 %
  assert.equal(g.tope_aplicado, true);
  assert.equal(g.retencion_mes, 50000);            // 1 % de 5.000.000
});
test('computeGanancias: deducciones F.572 acotadas al año fiscal del período (no arrastran meses de años anteriores)', () => {
  // mayo 2026: una deducción que arrancó en 2025 sólo cuenta desde enero de este año (5 meses: ene-mayo)
  const emp1 = { ganancias_aplica:true, conyuge:false, hijos:0, hijos_incap:0, ganancias_deducciones:[{tipo:'servicio_domestico',importe_mensual:100000,periodo_desde:'2025-06'}] };
  const g1 = gan({ empleado:emp1, periodo:'2026-05-01' });
  assert.equal(g1.deducciones_f572_acum, 500000);
  // una deducción que terminó en 2025 no aporta nada en 2026
  const emp2 = { ganancias_aplica:true, conyuge:false, hijos:0, hijos_incap:0, ganancias_deducciones:[{tipo:'servicio_domestico',importe_mensual:100000,periodo_desde:'2025-01',periodo_hasta:'2025-12'}] };
  const g2 = gan({ empleado:emp2, periodo:'2026-05-01' });
  assert.equal(g2.deducciones_f572_acum, 0);
});
test('computeGanancias: liquidación final — el SAC real (código 28) no duplica lo ya contado en el neto (R24)', () => {
  const CAT_SAC = [...CAT, { codigo: '28', tipo: 'remunerativo' }];
  const g = gan({ tipo:'final', periodo:'2026-09-01', catalogo:CAT_SAC,
    conceptos:[{codigo:'1',importe:2500000},{codigo:'28',importe:1250000},{codigo:'200',importe:412500},{codigo:'201',importe:112500},{codigo:'202',importe:112500}],
    remBruto:3750000, acumulados:{ rem_gravada_acum:20000000, retenido_previo:2000000, sac_prorrateado_acum:1250000, sac_real_acum:0 } });
  // neto ordinario = 2.500.000 × 0,83 = 2.075.000; SAC real (1.250.000 × 0,83) − doceavos ya prorrateados (1.250.000 × 0,83) = 0
  assert.equal(g.rem_gravada_mes, 2075000);
  assert.equal(g.sac_prorrateado_acum, 0);
  assert.equal(g.sac_real_acum, 1250000);
});
test('computeGanancias: 208/211 (aportes s/no remunerativo) no se deducen — noRem queda fuera de la base gravada (R23)', () => {
  const base = gan();
  const conConNoRem = conc(5000000).concat([{ codigo:'208', importe:300000 }]);
  const g = gan({ conceptos:conConNoRem, noRem:9999999 });
  assert.equal(g.rem_gravada_mes, base.rem_gravada_mes);
});
