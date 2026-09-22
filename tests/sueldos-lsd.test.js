// Tests de Sueldos 082: conceptos → renglón, bases F.931, CBU y el TXT del
// Libro de Sueldos Digital (ARCA). Los strings "vacíos" de referencia salen
// de las fórmulas de LSD-ARMADO-TXT-Liquidaciones.xlsx (filas sin datos).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

const run = (code) => erp.run(code);
const J = JSON.stringify;

const CATALOGO = [
  { codigo: '100', nombre: 'Básico', tipo: 'remunerativo' },
  { codigo: '190', nombre: 'No rem', tipo: 'no_remunerativo' },
  { codigo: '300', nombre: 'Jubilación', tipo: 'descuento' },
  { codigo: '900', nombre: 'AAFF', tipo: 'informativo' },
];

test('computeItemDesdeConceptos: remunerativo → bruto, no rem → no_rem, descuento → aportes, informativo no suma', () => {
  const r = run(`computeItemDesdeConceptos(${J([
    { codigo: '100', importe: 1000000 }, { codigo: '190', importe: 200000 },
    { codigo: '300', importe: 110000 }, { codigo: '900', importe: 99999 }, { codigo: 'XXX', importe: 5 },
  ])},${J(CATALOGO)})`);
  assert.deepEqual(JSON.parse(JSON.stringify(r)), { bruto: 1000000, no_remunerativo: 200000, aportes: 110000, neto: 1090000 });
});

test('computeF931Default: bases = bruto, tope en 1/4/5, base 10 = bruto − detracción (0 sin detracción)', () => {
  const f = run(`computeF931Default(${J({ bruto: 1500000, noRem: 100000, detraer: 7003.68, tope: 1200000 })})`);
  assert.equal(f.rem_bruta, 1600000);
  assert.equal(f.base1, 1200000); assert.equal(f.base4, 1200000); assert.equal(f.base5, 1200000);
  assert.equal(f.base2, 1500000); assert.equal(f.base3, 1500000); assert.equal(f.base8, 1500000); assert.equal(f.base9, 1500000);
  assert.equal(f.base6, 0); assert.equal(f.base7, 0);
  assert.equal(f.base10, 1492996.32);
  const sin = run(`computeF931Default(${J({ bruto: 1500000 })})`);
  assert.equal(sin.base10, 0); assert.equal(sin.base1, 1500000); assert.equal(sin.dias, 30);
});

test('sugerirNroLSD: mayor a los ya informados en el período, 1 si no hay', () => {
  const liqs = [{ periodo: '2026-08-01', lsd_nro: 2 }, { periodo: '2026-08-01', lsd_nro: 5 }, { periodo: '2026-07-01', lsd_nro: 9 }];
  assert.equal(run(`sugerirNroLSD(${J(liqs)},'2026-08-01')`), 6);
  assert.equal(run(`sugerirNroLSD(${J(liqs)},'2026-09-01')`), 1);
});

// DV de un bloque calculado con la formulación clásica (pesos de izquierda a derecha)
function dvBloque(digitos, pesosLR) {
  let s = 0; for (let i = 0; i < digitos.length; i++) s += Number(digitos[i]) * pesosLR[i];
  return (10 - (s % 10)) % 10;
}
function cbuValido(banco7, cuenta13) {
  return banco7 + dvBloque(banco7, [7, 1, 3, 9, 7, 1, 3]) + cuenta13 + dvBloque(cuenta13, [3, 9, 7, 1, 3, 9, 7, 1, 3, 9, 7, 1, 3]);
}
const CBU_OK = cbuValido('0170099', '2000006779737');
const CUIL = '20123456786';      // 2012345678 → DV 6
const CUIL2 = '27000000006';     // 2700000000 → DV 6
const CUIT_EMP = '30712345671';  // 3071234567 → DV 1

test('validarCbu: 22 dígitos con los dos verificadores correctos', () => {
  assert.equal(run(`validarCbu('${CBU_OK}')`), true);
  const malo = CBU_OK.slice(0, 21) + String((Number(CBU_OK[21]) + 1) % 10);
  assert.equal(run(`validarCbu('${malo}')`), false);
  assert.equal(run(`validarCbu('123')`), false);
  assert.equal(run(`validarCbu('${CBU_OK.slice(0, 4)}-${CBU_OK.slice(4)}')`), true);  // tolera guiones
});

test('lsd helpers: padding de número, importe ×100, alfanumérico izq/der y ASCII', () => {
  assert.equal(run(`lsdNum('1',2)`), '01');
  assert.equal(run(`lsdNum(30,2)`), '30');
  assert.equal(run(`lsdNum('20-12345678-3',11)`), '20123456783');
  assert.equal(run(`lsdImp(1234.5,15)`), '000000000123450');
  assert.equal(run(`lsdImp(6.5,5)`), '00650');
  assert.equal(run(`lsdStr('Pérez',10)`), 'Perez     ');
  assert.equal(run(`lsdStrR('SJ',2)`), 'SJ');
  assert.equal(run(`lsdStrR('',6)`), '      ');
});

test('registros vacíos coinciden con las fórmulas del Excel de ARCA', () => {
  assert.equal(run(`lsdReg1({cuit:'',envio:'',periodo:'',tipoLiq:'',nro:0,cantReg4:0})`), '0100000000000  000000 0000030000000');
  assert.equal(run(`lsdReg2({})`), '0200000000000' + ' '.repeat(82) + '00000000000' + ' '.repeat(8) + '0');
  assert.equal(run(`lsdReg2({})`).length, 115);
  assert.equal(run(`lsdReg3('',{})`), '0300000000000          00000 000000000000000       ');
  const r4 = run(`lsdReg4('',{})`);
  assert.equal(r4.length, 370);
  assert.equal(r4.slice(0, 23), '04000000000000000000000');
  assert.equal(r4.slice(23, 33), '  000     ');   // condición (2 esp) + actividad 000 + modalidad (3 esp) + siniestrado (2 esp)
  assert.match(r4.slice(33), /^0+$/);
});

function inputBase(over = {}) {
  return {
    cuit: CUIT_EMP, envio: 'SJ', periodo: '202608', tipoLiq: 'M', nro: 1,
    empleados: [{
      nombre: 'Juan Pérez', cuil: CUIL, legajo: '001', dependencia: 'Planta', cbu: CBU_OK, formaPago: 3,
      diasTope: 0, fechaPago: '20260904',
      conceptos: [
        { codigo: '100', cantidad: 0, unidades: '', importe: 1000000, dc: 'C', periodo_ajuste: '' },
        { codigo: '300', cantidad: 11, unidades: '%', importe: 110000, dc: 'D', periodo_ajuste: '' },
      ],
      reg4: { conyuge: 0, hijos: 2, cct: 1, scvo: 1, reduccion: 0, tipoEmpresa: 1, situacion: '1', condicion: '1', actividad: '049',
        modalidad: '008', siniestrado: '00', localidad: '00', revista1: '1', dia1: 1, revista2: '', dia2: 0, revista3: '', dia3: 0,
        dias: 30, horas: 0, pctAdicSS: 0, contribDif: 0, obraSocial: '107202', adherentes: 0,
        aporteAdicOS: 0, contribAdicOS: 0, baseDifApOS: 0, baseDifContrOS: 0, baseDifLRT: 0, remMaternidad: 0, remBruta: 1000000,
        base1: 1000000, base2: 1000000, base3: 1000000, base4: 1000000, base5: 1000000, base6: 0, base7: 0, base8: 1000000, base9: 1000000,
        baseDifApSS: 0, baseDifContrSS: 0, base10: 0, detraer: 0 },
    }],
    ...over,
  };
}

test('buildLSD: archivo completo válido — 1 reg 01, N reg 02, conceptos reg 03, N reg 04, largos exactos, CRLF', () => {
  const inp = inputBase();
  const r = run(`buildLSD(${J(inp)})`);
  assert.equal(r.errores.length, 0, r.errores.join(" / "));
  assert.equal(r.lineas.length, 1 + 1 + 2 + 1);
  assert.equal(r.lineas[0], `01${inp.cuit}SJ202608M00001300000001`);
  assert.equal(r.lineas[0].length, 35);
  assert.equal(r.lineas[1], `02${CUIL}001       Planta` + ' '.repeat(44) + CBU_OK + '000' + '20260904' + ' '.repeat(8) + '3');
  assert.equal(r.lineas[2], `03${CUIL}100       00000 000000100000000C      `);
  assert.equal(r.lineas[3], `03${CUIL}300       01100%000000011000000D      `);
  assert.equal(r.lineas[4].length, 370);
  assert.equal(r.lineas[4].slice(0, 13), `04${CUIL}`);
  assert.equal(r.lineas[4].slice(13, 23), '0021101' + '0' + '01');          // cónyuge 0, hijos 02, cct 1, scvo 1, red 0, tipo 1, op 0, situación 01
  assert.equal(r.lineas[4].slice(23, 33), '1 049008' + '00');              // condición "1 ", actividad 049, modalidad 008, siniestrado 00
  assert.equal(r.lineas[4].slice(33, 47), '00' + '01' + '01' + '00' + '00' + '00' + '00'); // localidad, revista1/día, revista2/día, revista3/día
  assert.equal(r.lineas[4].slice(47, 52), '30' + '000');                   // días 30, horas 000
  assert.equal(r.lineas[4].slice(52, 70), '00000' + '00000' + '107202' + '00');
  assert.equal(r.lineas[4].slice(70 + 6 * 15, 70 + 7 * 15), '000000100000000'); // rem bruta
  assert.ok(r.txt.endsWith('\r\n'));
  assert.equal(r.txt.split('\r\n').length - 1, 5);
  assert.equal(r.resumen.empleados, 1); assert.equal(r.resumen.conceptos, 2);
  assert.equal(r.resumen.haberes, 1000000); assert.equal(r.resumen.descuentos, 110000);
});

test('buildLSD: detecta lo que ARCA rechaza (CUIL, CBU con acreditación, sin conceptos, obra social, actividad, días+horas)', () => {
  const inp = inputBase();
  const e = inp.empleados[0];
  e.cuil = '20123456784'; e.cbu = '123'; e.conceptos = []; e.reg4.obraSocial = ''; e.reg4.actividad = ''; e.reg4.dias = 30; e.reg4.horas = 8;
  const r = run(`buildLSD(${J(inp)})`);
  const txt = r.errores.join(' | ');
  for (const s of ['CUIL inválido', 'CBU', 'sin conceptos', 'obra social', 'actividad', 'días trabajados O horas']) assert.match(txt, new RegExp(s));
  // El archivo se arma igual (preview) y los largos siguen siendo los del formato
  assert.equal(r.lineas[0].length, 35); assert.equal(r.lineas[1].length, 115); assert.equal(r.lineas[2].length, 370);
});

test('buildLSD: RE deja días base en blanco; cantidad de registros 04 = empleados', () => {
  const inp = inputBase({ envio: 'RE' });
  inp.empleados.push({ ...inp.empleados[0], cuil: CUIL2, nombre: 'Otra' });
  const r = run(`buildLSD(${J(inp)})`);
  assert.equal(r.lineas[0].slice(27, 29), '  ');
  assert.equal(r.lineas[0].slice(29), '000002');
  assert.equal(r.lineas.filter(l => l.startsWith('04')).length, 2);
});
