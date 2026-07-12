// Test de plantaURL (botón "QR planta" del modal Tiempos).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('plantaURL arma la URL de producción con el id de la OP', () => {
  assert.strictEqual(
    erp.run(`plantaURL('abc-123')`),
    'https://erp.vitalmetsa.com/planta.html?op=abc-123'
  );
});
