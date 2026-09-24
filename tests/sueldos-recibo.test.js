'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CAT = [{codigo:'4',nombre:'JORNAL',tipo:'remunerativo'},{codigo:'5',nombre:'FERIADO',tipo:'remunerativo'},{codigo:'200',nombre:'JUBILACION',tipo:'descuento'},{codigo:'201',nombre:'LEY 19032',tipo:'descuento'},{codigo:'202',nombre:'OBRA SOCIAL',tipo:'descuento'},{codigo:'203',nombre:'SINDICATO UOM',tipo:'descuento'},{codigo:'211',nombre:'Sindicato S/No Rem',tipo:'descuento'},{codigo:'208',nombre:'Obra Social S/ No Rem',tipo:'descuento'},{codigo:'102',nombre:'Gratif extraord No Rem',tipo:'no_remunerativo'},{codigo:'998',nombre:'Redondeo',tipo:'no_remunerativo'}];
const ITEM = { recibo_nro:1603, bruto:444111.03, no_remunerativo:40000.62, aportes:88801.65, neto:395310, contribuciones:108780.94, art:0,
  liquidacion_conceptos:[{codigo:'4',cantidad:90,unidades:'H',importe:403737.30,dc:'C',orden:0},{codigo:'5',cantidad:9,unidades:'H',importe:40373.73,dc:'C',orden:1},{codigo:'200',cantidad:11,unidades:'%',importe:48852.21,dc:'D',orden:2},{codigo:'201',cantidad:3,unidades:'%',importe:13323.33,dc:'D',orden:3},{codigo:'202',cantidad:3,unidades:'%',importe:13323.33,dc:'D',orden:4},{codigo:'203',cantidad:2.5,unidades:'%',importe:11102.78,dc:'D',orden:5},{codigo:'211',cantidad:0,unidades:'',importe:1000,dc:'D',orden:6},{codigo:'208',cantidad:0,unidades:'',importe:1200,dc:'D',orden:7},{codigo:'102',cantidad:0,unidades:'',importe:40000,dc:'C',orden:8},{codigo:'998',cantidad:0,unidades:'',importe:0.62,dc:'C',orden:9}],
  contribuciones_detalle:[{codigo:'640',nombre:'SVC',pct:null,base:424.62,importe:424.62},{codigo:'642',nombre:'CONTRIBUCION INSSJP',pct:1.59,base:440609.19,importe:7005.69},{codigo:'643',nombre:'CONTRIBUCION ANSSAL',pct:0.9,base:484111.03,importe:4357},{codigo:'644',nombre:'CONTRIBUCION JUBILACION',pct:10.77,base:440609.19,importe:47453.61},{codigo:'645',nombre:'CONTRIBUCION OBRA SOCIAL',pct:5.1,base:484111.03,importe:24689.66},{codigo:'646',nombre:'CONTRIBUCION FONDO DESEMPLEO',pct:0.94,base:440609.19,importe:4141.73},{codigo:'647',nombre:'CONTRIBUCION SUBSIDIO FAMILIAR',pct:4.7,base:440609.19,importe:20708.63}] };
const ARGS = { empresa:{razon_social:'VITALMET SOCIEDAD ANONIMA',domicilio:'PERU 246',localidad:'VILLA MARTELLI',actividad:'Forjado, prensado, estampado y laminado de metales; pulvimetalurgia',cuit:'34-59751980-1'},
  empleado:{legajo:'69',nombre:'AYALA , RODRIGO EZEQUIEL',cuil:'20334592775',fecha_ingreso:'2026-04-27',fecha_ingreso_reconocida:'2026-09-01',categoria_escala:'INGRESANTE',contratacion:'Nuevo período de prueba',obra_social:'UNION OBRERA METALURGICA',tarea:'INGRESANTE',lugar_pago:'CASA CENTRAL',banco_deposito:'FRANCES'},
  item:ITEM, liquidacion:{periodo:'2026-09-01',tipo:'quincena1',fecha_pago:'2026-09-18'}, conceptosCat:CAT, config:{f931_ultimo_periodo:'08/2026',f931_ultimo_fecha:'2026-09-09'}, escala:{valor_hora:4485.97}, copias:['ORIGINAL','DUPLICADO'] };

test('_reciboComposicion: totales de la página 2 del recibo real', () => {
  const c = run(`_reciboComposicion(${J(ITEM)},${J(CAT)})`);
  assert.equal(c.ss.emp, 76660.97);          // SIPA 47.453,61 + FNE 4.141,73 + AAFF 20.708,63 + ANSSAL 4.357,00 (como la página 2 del recibo real)
  assert.equal(c.os.emp, 24689.66); assert.equal(c.inssjp.emp, 7005.69); assert.equal(c.scvo.emp, 424.62);
  assert.equal(c.otrosDesc.trab, 88801.65); assert.equal(c.costoTotal, 592892.59);
  assert.equal(Math.round(Object.values(c.pct).reduce((a, b) => a + b, 0)), 100);
});
test('renderRecibo: 2 páginas × 2 copias, bloques y neto en letras', () => {
  const html = run(`renderRecibo(${J(ARGS)})`);
  assert.equal((html.match(/class="recibo-pagina"/g) || []).length, 4);
  for (const s of ['Recibo de haberes','VITALMET SOCIEDAD ANONIMA','34-59751980-1','1RA QUINC SEPTIEMBRE 2026','18/09/2026','20-33459277-5','0a 4m 20d','COSTO TOTAL EMPLEADOR','592.892,59','SUELDO BRUTO','484.111,65','SUELDO NETO','395.310,00','TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ','Detalle de la composici','Página 1 de 2','Página 2 de 2','ORIGINAL','DUPLICADO','1603'])
    assert.ok(html.includes(s), 'falta: ' + s);
  assert.ok(html.includes('-48.852,21'));
  assert.ok(html.includes('<svg'));
});
