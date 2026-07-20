// Harness de tests: carga el <script> inline de index.html en un
// contexto vm de Node con el DOM stubeado, para testear las funciones
// de cálculo puras (computeCtaCte, computeCostoPT, calcReorden*, etc.)
// sin navegador ni red.
//
// Las variables del ERP (clientes, ventas, ops...) son bindings
// léxicos top-level del script, NO propiedades de globalThis: por eso
// no se pueden setear desde afuera con ctx.clientes = [...]. Se setean
// y se leen ejecutando código DENTRO del contexto vía erp.run(codigo).
//
// Uso:
//   const erp = require('./_harness').load();
//   erp.set({clientes:[...], ventas:[...]});
//   const res = erp.run('computeCtaCte()');
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const NOOP_METHODS = new Set([
  'addEventListener', 'removeEventListener', 'setAttribute', 'removeAttribute',
  'appendChild', 'removeChild', 'focus', 'blur', 'click', 'remove', 'select',
  'scrollIntoView', 'showModal', 'close', 'write', 'requestSubmit', 'reset',
]);

function stubElement() {
  const base = {
    style: {},
    dataset: {},
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    value: '', textContent: '', innerHTML: '', checked: false, disabled: false,
  };
  return new Proxy(base, {
    get(t, k) {
      if (typeof k !== 'string') return undefined;
      if (k in t) return t[k];
      if (NOOP_METHODS.has(k)) return () => {};
      if (k === 'querySelectorAll') return () => [];
      if (k === 'querySelector' || k === 'closest' || k === 'cloneNode') return () => stubElement();
      if (k === 'getAttribute') return () => null;
      return undefined;
    },
    set(t, k, v) { t[k] = v; return true; },
  });
}

function stubDocument() {
  return new Proxy({}, {
    get(t, k) {
      if (typeof k !== 'string') return undefined;
      if (k === 'getElementById' || k === 'createElement' || k === 'querySelector') {
        return () => stubElement();
      }
      if (k === 'querySelectorAll') return () => [];
      if (k === 'addEventListener' || k === 'removeEventListener' || k === 'write' || k === 'close') {
        return () => {};
      }
      if (k === 'body' || k === 'head' || k === 'documentElement') return stubElement();
      return undefined;
    },
  });
}

function extractInlineScript() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
  if (!scripts.length) throw new Error('No se encontró <script> inline en index.html');
  return scripts.reduce((a, b) => (b.length > a.length ? b : a));
}

function load() {
  const sandbox = {
    document: stubDocument(),
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    location: { hostname: 'test', hash: '', href: 'http://test/' },
    navigator: { userAgent: 'node-test' },
    fetch: () => Promise.reject(new Error('sin red en tests')),
    confirm: () => false,
    alert() {}, prompt: () => null,
    setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
    console,
    URL: { createObjectURL: () => 'blob:test', revokeObjectURL() {} },
    Blob: function () {},
    TextEncoder,
    TextDecoder,
    Uint8Array,
    DataView,
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  const context = vm.createContext(sandbox);
  vm.runInContext(extractInlineScript(), context, { filename: 'index.html#script' });
  return {
    // Ejecuta código dentro del contexto del ERP y devuelve el resultado
    run(code) { return vm.runInContext(code, context); },
    // Setea variables top-level del ERP (clientes, ventas, ops, ...)
    set(vars) {
      for (const [k, v] of Object.entries(vars)) {
        vm.runInContext(`${k} = ${JSON.stringify(v)};`, context);
      }
    },
  };
}

module.exports = { load };
