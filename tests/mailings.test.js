// Tests del generador de recordatorios (Paquete 3B): resolverTemplate.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('resolverTemplate reemplaza todos los placeholders (incluso repetidos)', () => {
  const r = erp.run(`(()=>{
    const tpl={subject:'Recordatorio: saldo de {cliente}',body_html:'<p>Hola {cliente}, saldo {monto} hace {dias} días. {cliente}.</p>'};
    return resolverTemplate(tpl,{cliente:'ACME SA',monto:'US$ 1.200',dias:'12'});
  })()`);
  assert.strictEqual(r.subject, 'Recordatorio: saldo de ACME SA');
  assert.strictEqual(r.body, '<p>Hola ACME SA, saldo US$ 1.200 hace 12 días. ACME SA.</p>');
});

test('resolverTemplate deja intactos los placeholders sin variable', () => {
  const r = erp.run(`resolverTemplate({subject:'{nro} y {otro}',body_html:''},{nro:'P-1'})`);
  assert.strictEqual(r.subject, 'P-1 y {otro}');
});
