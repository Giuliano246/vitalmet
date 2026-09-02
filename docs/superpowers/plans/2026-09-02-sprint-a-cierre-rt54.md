# Sprint A — Cierre RT 54 mínimo · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el wizard de cierre de VitalStock genere los cinco asientos de ajuste que la RT 54 exige antes de refundir resultados (IIGG, previsión incobrables, provisiones laborales, diferencia de cambio, variación de existencias), y que el plan de cuentas sepa a qué rubro RT 54 pertenece cada cuenta.

**Architecture:** Una migración (072) agrega `rubro_rt54` + `naturaleza` a `cuentas_contables`, crea las cuentas nuevas, renombra PN y suma 8 columnas `cta_*` a `config_contable`. En el frontend, un panel nuevo "Ajustes de cierre RT 54" en `page-cierre` con cinco pasos: cada uno tiene una función pura `compute*` (testeada con el harness vm) que arma las líneas, un preview en tabla y un botón que crea el asiento en borrador vía RPC `crear_asiento`. El reporte Ratios se reescribe sobre `rubro_rt54`.

**Tech Stack:** index.html vanilla JS, Supabase PostgreSQL (SQL Editor), `node --test` con `tests/_harness.js`.

**Spec:** `docs/analisis/2026-09-02-auditoria-rt54.md` (hallazgos M-02, M-04, M-05, M-06, M-07, E-01, E-04, E-05, E-07; sección 5 mapeo; sección 6 Sprint A).

## Global Constraints

- Migraciones: BEGIN/COMMIT, idempotentes, empresa `a0a19507-2a50-4e80-a716-e9459f51d653` hardcodeada, `REVOKE ... FROM anon` en funciones nuevas, verificación comentada al pie. **SQL se corre en el SQL Editor ANTES de pushear el frontend.**
- Asientos SIEMPRE por RPC `crear_asiento` (mig 067), nunca POST directo. Se generan en estado `borrador`.
- Texto de UI en español argentino (voseo). Todo dato de usuario interpolado en HTML pasa por `esc()`.
- Un cambio por commit. Antes de commitear: extraer el `<script>` y `node --check`; correr `node --test tests/`.
- No abstracciones "por si escala": single-tenant.
- Manual de usuario: `docs/MANUAL_USUARIO.md` y **también** `.docx` vía pandoc, commiteados juntos.

---

### Task 1: Migración 072 — plan de cuentas RT 54 + config

**Files:**
- Create: `migrations/072_cierre_rt54.sql`

**Interfaces:**
- Produces: columnas `cuentas_contables.rubro_rt54 text` (CHECK sobre la lista de abajo) y `cuentas_contables.naturaleza text`; cuentas `511000`, `424006`, `112090`, `423007`, `214009`, `215001`, `216001`; agrupadoras `510000`, `215000`, `216000`, `123000`, `220000`; columnas `config_contable.cta_cmv, cta_dif_cambio, cta_prev_incobrables, cta_gasto_incobrables, cta_iigg, cta_iigg_a_pagar, cta_prov_vacaciones, cta_anticipos_clientes` con defaults.
- Valores de `rubro_rt54`: `caja_bancos, inversiones, cuentas_cobrar_clientes, creditos_impositivos, creditos_partes_rel, otras_cuentas_cobrar, bienes_cambio, bienes_uso, intangibles, proveedores, prestamos, deudas_fiscales, deudas_laborales, deudas_especie, deudas_partes_rel, previsiones, capital, ajuste_capital, aportes_irrevocables, reserva_legal, otras_reservas, rna, resultado_ejercicio, ventas, cmv, gastos_comercializacion, gastos_administracion, desvalorizacion, rfyt, otros_ingresos_egresos, iigg`.

- [ ] **Step 1: Escribir la migración** con: ALTER TABLE (columnas + CHECK), UPDATE de nombres de PN solo cuando `nombre = codigo`, `saldo_habitual='acreedor'` en 122010–122014, agrupadoras y cuentas nuevas con NOT EXISTS, reparent 122004 → 123000, UPDATE masivo de `rubro_rt54` por prefijo/lista (sección 5 del informe), desactivar 666666 solo si no tiene líneas, ALTER config_contable + UPDATE defaults, verificación comentada (saldos 314000 vs 314002, cuentas sin rubro, cuentas sin nombre).
- [ ] **Step 2: Validar sintaxis** — `psql` no disponible: revisar a ojo que cada DO $$ cierre y que la lista del CHECK coincida con la de este plan.
- [ ] **Step 3: Commit** `feat(contabilidad): migración 072 — plan de cuentas RT 54 y cuentas de cierre`

### Task 2: Funciones puras de cierre RT 54 + tests

**Files:**
- Modify: `index.html` (bloque nuevo después de `generarAsientosCierre`, ~línea 7382)
- Test: `tests/cierre-rt54.test.js`

**Interfaces (producidas, usadas por Task 3):**
```js
// Todas devuelven {lineas:[{cuenta_id,debe,haber,descripcion,orden}], ...detalle} o {lineas:[], error:'…'}
computeAsientoIIGG(importe, cfg)                       // → {lineas}
computePrevisionIncobrables(ctacte, pcts, tc, saldoActual, cfg)
   // ctacte = computeCtaCte() (USD); pcts = {d30,d60,d90,mas90} en %; tc = TC cierre; saldoActual = saldo acreedor ARS de la previsión
   // → {base:{alDia,d30,d60,d90,mas90} en ARS, objetivo, ajuste, lineas}
computeProvisionLaboral({vacFab,vacAdm,saldoSac,pctCargas,gastoFab,gastoAdm}, cfg)
   // → {cargasSac, cargasFab, cargasAdm, total, lineas}
computeDiferenciaCambio(lineas, asientos, cuentas, tc, cfg)
   // → {filas:[{cuenta,saldoUsd,arsContable,arsCierre,dif}], total, lineas}
computeVariacionExistencias(saldos, existenciaFinal, cfg)
   // saldos = _agregarSaldos('',hasta); existenciaFinal = {mp,pt,insumos} en ARS
   // → {filas:[{cuenta,saldoContable,existenciaFinal,variacion}], cmv, lineas}
```

- [ ] **Step 1: Escribir los tests** (usar `erp.run` con fixtures inline; un test feliz + un test de borde por función: cfg incompleto → `error`, ajuste cero → `lineas` vacío, signo invertido).
- [ ] **Step 2: Correr** `node --test tests/cierre-rt54.test.js` → FAIL (ReferenceError).
- [ ] **Step 3: Implementar** las cinco funciones en index.html.
- [ ] **Step 4: Correr** los tests → PASS; correr `node --test tests/` → todo verde.
- [ ] **Step 5: Commit** `feat(cierre): funciones puras de ajustes RT 54 con tests`

### Task 3: Panel "Ajustes de cierre RT 54" en page-cierre

**Files:**
- Modify: `index.html` HTML de `page-cierre` (entre los botones de acción, línea ~1045, y `cierre-preview-info`), JS junto a Task 2.

- [ ] **Step 1: HTML** — `<div class="card" id="cierre-rt54">` con cinco filas plegables (`<details>`): cada una con inputs mínimos, botón "Preview", tabla `#rt54-<paso>-tbody`, botón "Generar asiento" deshabilitado hasta el preview. Inputs: TC cierre compartido (`#rt54-tc`, prefill `cotizacion.venta`), IIGG importe, previsión % por tramo (defaults 0/10/25/50/100), vacaciones fab/adm + % cargas (default 27,35), existencia final MP/PT/insumos (prefill `computeValuacionMP/PT` × TC).
- [ ] **Step 2: JS** — `renderCierreRT54()` (registrado en `PAGE_RENDERS.cierre`), `previewRT54(paso)` y `generarAsientoRT54(paso)` que arma cabecera `{fecha: cierre-hasta, tipo:'auto-cierre-rt54', origen_tipo:'cierre_rt54', origen_id:null, estado:'borrador', moneda:'ARS'}` + líneas del preview y llama `RPC('crear_asiento',…)`; idempotencia por aviso: si ya existe un asiento no anulado con `origen_tipo='cierre_rt54'` y misma descripción/fecha, pedir confirm.
- [ ] **Step 3: `node --check` + tests** verdes.
- [ ] **Step 4: Commit** `feat(cierre): panel de ajustes RT 54 (IIGG, previsión, laborales, dif. cambio, existencias)`

### Task 4: Plan de cuentas — rubro RT 54 en modal y listado

**Files:**
- Modify: `index.html` modal `modal-cuenta` (~línea 1428), `openModalCuenta`/`saveCuenta` (~6560–6590), `renderPlanCuentas` fila (~6546).

- [ ] **Step 1:** constante `RUBROS_RT54 = [{v:'caja_bancos', l:'Caja y bancos', t:'activo'}, …]`; select `#cuenta-rubro-rt54` filtrado por tipo de la cuenta; columna "Rubro RT 54" en la tabla del plan (mono, `—` si null).
- [ ] **Step 2:** `saveCuenta` manda `rubro_rt54`.
- [ ] **Step 3:** Commit `feat(plan-cuentas): rubro RT 54 editable`

### Task 5: Configuración → Imputación: cuentas de cierre RT 54

**Files:**
- Modify: `index.html` HTML de imputación (~1275), `renderImputacionContable` (~10013), `saveConfigContable` (~10050).

- [ ] **Step 1:** sub-bloque "Cierre RT 54" con 8 selects (`cfg-cta-cmv` egreso, `cfg-cta-dif-cambio` egreso, `cfg-cta-prev-incobrables` activo, `cfg-cta-gasto-incobrables` egreso, `cfg-cta-iigg` egreso, `cfg-cta-iigg-a-pagar` pasivo, `cfg-cta-prov-vacaciones` pasivo, `cfg-cta-anticipos-clientes` pasivo).
- [ ] **Step 2:** `_llenarSelectCuentas` + `data.cta_*` en save.
- [ ] **Step 3:** Commit `feat(config): cuentas de cierre RT 54 en imputación contable`

### Task 6: Ratios sobre rubro RT 54 (E-04)

**Files:**
- Modify: `index.html` `_esActivoCorriente`…`_sumPor` y `renderRatios` (~8832–8975).

- [ ] **Step 1:** reemplazar los regex con puntos por `_grupoBimon(c)` (AC/ANC/PC/PNC) y `c.rubro_rt54` (inventarios = `bienes_cambio`, C×C = `cuentas_cobrar_clientes`, proveedores = `proveedores`, ventas = `ventas`, CMV = `cmv`, gastos op = `gastos_comercializacion`+`gastos_administracion`, financieros = `rfyt`). Actualizar el texto de "Notas metodológicas".
- [ ] **Step 2:** `node --check`. Commit `fix(ratios): clasificación por rubro RT 54 en vez de códigos con puntos inexistentes`

### Task 7: Docs

**Files:**
- Modify: `CLAUDE.md` (bullet "Cierre RT 54 (migración 072)"), `docs/MANUAL_USUARIO.md` §11.8 (subsección "Ajustes de cierre RT 54") + regenerar `docs/MANUAL_USUARIO.docx` con `pandoc`.

- [ ] **Step 1:** escribir; `pandoc docs/MANUAL_USUARIO.md -o docs/MANUAL_USUARIO.docx`.
- [ ] **Step 2:** Commit `docs: cierre RT 54 en CLAUDE.md y manual`

### Handoff
No pushear hasta que Giuliano corra 072 en el SQL Editor y confirme "listo" (regla 2 del CLAUDE.md). Fuera de alcance de este sprint (van en B/C/D o sprint propio): motor de inflación con anticuación, bienes de uso, estados exportables, cableado de anticipos en `registrar_cobro` (la cuenta 215001 queda creada).
