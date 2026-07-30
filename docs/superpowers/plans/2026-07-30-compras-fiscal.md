# Compras Fiscal Completo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Llevar facturas de proveedor a nivel ERP argentino completo: alícuotas múltiples de IVA, percepciones, tipo/letra de comprobante, NC/ND de proveedor, facturas sin OC y condición fiscal del proveedor.

**Architecture:** Single-file HTML (`index.html`, ~11k líneas, vanilla JS compacto) + Supabase (PostgREST + RPCs plpgsql). Nueva tabla `factura_recibida_impuestos` (tax lines, patrón SAP/Tango), RPC `registrar_factura_recibida` v2 con validación aritmética server-side, modal de factura rediseñado con grillas dinámicas.

**Tech Stack:** Vanilla JS (sin frameworks), Supabase/PostgREST, plpgsql, `node --test` con `tests/_harness.js` (carga index.html en vm de Node).

**Spec:** `docs/superpowers/specs/2026-07-30-compras-fiscal-design.md` — leerlo antes de empezar.

## Global Constraints

- Repo: `~/vitalmet-erp`. TODO el frontend vive en `index.html` (estilo compacto, líneas largas, español rioplatense en UI y comentarios).
- Migración nueva = `migrations/054_compras_fiscal.sql` (053 ya existe). Idempotente, patrón NOT EXISTS de mig 033. Se corre a mano en el SQL Editor de Supabase — NO hay pipeline.
- Tests: `node --test tests/` desde la raíz. Funciones puras se testean vía `tests/_harness.js` (`erp.run('fn(...)')`).
- Montos SIEMPRE positivos en DB; el signo lo aplica `tipo` (`nota_credito` resta).
- `neto` (cabecera facturas_recibidas) = Σ bases gravadas. Match compara `neto + no_gravado + exento` vs valor recibido OC.
- Empresa seed Vitalmet SA: `a0a19507-2a50-4e80-a716-e9459f51d653`. Cuentas: 113007 PERCEPCION IVA (existe), 113010/113011 (crear).
- Helpers existentes: `GET/POST/PATCH/DEL/RPC`, `reload(...)`, `esc()`, `notify(msg,'err')`, `setBusy(id,bool)`, `hoyLocal(offsetDias)`, `fmtARS/fmtUSD`, `openModal/closeModal`.
- Commits frecuentes, mensajes en español estilo repo (`feat:`, `fix:`, `docs:`), con `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Funciones puras de desglose fiscal + tests

**Files:**
- Modify: `index.html` — insertar junto a `evaluarMatchFactura` (~línea 10770, sección de funciones puras)
- Create: `tests/compras-fiscal.test.js`

**Interfaces:**
- Produces:
  - `computeTotalesFactura({ivas, noGravado, exento, percepciones})` → `{neto, iva, percep, total}` — `ivas` = `[{alicuota, base, monto}]`, `percepciones` = `[{tipo, monto, jurisdiccion}]`
  - `validarDesgloseFactura({letra, ivas, totalTipeado, totales})` → `{ok, errores:[string]}` — `totales` es el output de `computeTotalesFactura`
  - `sugerirLetra(condicionFiscal)` → `'A'|'B'|'C'` — RI→A, monotributo→C, exento→C, consumidor_final→B, default A
  - `letraDiscriminaIva(letra)` → `boolean` — true solo para A y M

- [ ] **Step 1: Write the failing tests**

Crear `tests/compras-fiscal.test.js`:

```js
// Tests del desglose fiscal de facturas de proveedor (spec 2026-07-30).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();

function totales(args) { return erp.run(`computeTotalesFactura(${JSON.stringify(args)})`); }
function validar(args) { return erp.run(`validarDesgloseFactura(${JSON.stringify(args)})`); }

test('computeTotalesFactura suma bases, IVA y percepciones', () => {
  const r = totales({
    ivas: [{ alicuota: 21, base: 1000, monto: 210 }, { alicuota: 10.5, base: 500, monto: 52.5 }],
    noGravado: 100, exento: 50,
    percepciones: [{ tipo: 'percepcion_iibb', monto: 30, jurisdiccion: 'PBA' }, { tipo: 'percepcion_iva', monto: 20 }],
  });
  assert.strictEqual(r.neto, 1500);
  assert.strictEqual(r.iva, 262.5);
  assert.strictEqual(r.percep, 50);
  assert.strictEqual(r.total, 1962.5);
});

test('computeTotalesFactura tolera arrays vacíos y campos ausentes', () => {
  const r = totales({ ivas: [], percepciones: [] });
  assert.deepStrictEqual(r, { neto: 0, iva: 0, percep: 0, total: 0 });
});

test('validarDesgloseFactura OK cuando el total tipeado coincide', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1210, totales: t });
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(r.errores, []);
});

test('validarDesgloseFactura rechaza total que no cierra (>0.01)', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1200, totales: t });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.errores.length, 1);
});

test('validarDesgloseFactura rechaza IVA en letra C', () => {
  const t = totales({ ivas: [{ alicuota: 21, base: 1000, monto: 210 }], noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'C', ivas: [{ alicuota: 21, base: 1000, monto: 210 }], totalTipeado: 1210, totales: t });
  assert.strictEqual(r.ok, false);
});

test('validarDesgloseFactura acepta redondeo del proveedor en el monto de IVA', () => {
  // base*alicuota = 209.99 vs monto cargado 210: diferencia chica, aceptable
  const ivas = [{ alicuota: 21, base: 999.95, monto: 210 }];
  const t = totales({ ivas, noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas, totalTipeado: t.total, totales: t });
  assert.strictEqual(r.ok, true);
});

test('validarDesgloseFactura rechaza monto de IVA incoherente con la base', () => {
  const ivas = [{ alicuota: 21, base: 1000, monto: 500 }]; // 21% de 1000 es 210, no 500
  const t = totales({ ivas, noGravado: 0, exento: 0, percepciones: [] });
  const r = validar({ letra: 'A', ivas, totalTipeado: t.total, totales: t });
  assert.strictEqual(r.ok, false);
});

test('sugerirLetra mapea condición fiscal', () => {
  assert.strictEqual(erp.run(`sugerirLetra('RI')`), 'A');
  assert.strictEqual(erp.run(`sugerirLetra('monotributo')`), 'C');
  assert.strictEqual(erp.run(`sugerirLetra('exento')`), 'C');
  assert.strictEqual(erp.run(`sugerirLetra('consumidor_final')`), 'B');
  assert.strictEqual(erp.run(`sugerirLetra(null)`), 'A');
});

test('letraDiscriminaIva solo A y M', () => {
  assert.strictEqual(erp.run(`letraDiscriminaIva('A')`), true);
  assert.strictEqual(erp.run(`letraDiscriminaIva('M')`), true);
  assert.strictEqual(erp.run(`letraDiscriminaIva('B')`), false);
  assert.strictEqual(erp.run(`letraDiscriminaIva('C')`), false);
  assert.strictEqual(erp.run(`letraDiscriminaIva('X')`), false);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/vitalmet-erp && node --test tests/compras-fiscal.test.js`
Expected: FAIL — `computeTotalesFactura is not defined` (ReferenceError dentro de erp.run).

- [ ] **Step 3: Implement the pure functions**

En `index.html`, inmediatamente DESPUÉS de `evaluarMatchFactura` (~línea 10776, tras el `}` de la función), insertar:

```js
// ─── DESGLOSE FISCAL DE FACTURAS DE PROVEEDOR (spec 2026-07-30) ──────
// Funciones PURAS (sin DOM ni red) espejo de la validación del RPC
// registrar_factura_recibida v2 (migración 054).
const ALICUOTAS_IVA=[0,2.5,5,10.5,21,27];
function computeTotalesFactura({ivas=[],noGravado=0,exento=0,percepciones=[]}={}){
  const r2=n=>Math.round(n*100)/100;
  const neto=r2(ivas.reduce((a,i)=>a+(parseFloat(i.base)||0),0));
  const iva=r2(ivas.reduce((a,i)=>a+(parseFloat(i.monto)||0),0));
  const percep=r2(percepciones.reduce((a,p)=>a+(parseFloat(p.monto)||0),0));
  const total=r2(neto+(parseFloat(noGravado)||0)+(parseFloat(exento)||0)+iva+percep);
  return {neto,iva,percep,total};
}
function letraDiscriminaIva(letra){return letra==='A'||letra==='M';}
function sugerirLetra(condicionFiscal){
  return {RI:'A',monotributo:'C',exento:'C',consumidor_final:'B'}[condicionFiscal]||'A';
}
function validarDesgloseFactura({letra,ivas=[],totalTipeado,totales}){
  const errores=[];
  if(!letraDiscriminaIva(letra)&&totales.iva>0)
    errores.push(`Una factura ${letra} no discrimina IVA — el importe va todo al neto/gasto`);
  for(const i of ivas){
    const base=parseFloat(i.base)||0,monto=parseFloat(i.monto)||0,ali=parseFloat(i.alicuota)||0;
    const esperado=base*ali/100;
    // Tolerancia: redondeos del proveedor (1% del esperado, mínimo $0.05)
    if(Math.abs(monto-esperado)>Math.max(esperado*0.01,0.05))
      errores.push(`IVA ${ali}%: el monto ${monto.toFixed(2)} no coincide con base ${base.toFixed(2)} (esperado ${esperado.toFixed(2)})`);
  }
  if(Math.abs((parseFloat(totalTipeado)||0)-totales.total)>0.01)
    errores.push(`El total tipeado ${(parseFloat(totalTipeado)||0).toFixed(2)} no coincide con la suma de componentes ${totales.total.toFixed(2)}`);
  return {ok:errores.length===0,errores};
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test tests/compras-fiscal.test.js`
Expected: PASS (9 tests). Después correr la suite completa: `node --test tests/` — todo verde (ningún test existente roto).

- [ ] **Step 5: Commit**

```bash
git add tests/compras-fiscal.test.js index.html
git commit -m "feat: funciones puras de desglose fiscal de facturas (alícuotas, letra, validación)"
```

---

### Task 2: Migración 054 — schema + cuentas + backfill + RPC v2

**Files:**
- Create: `migrations/054_compras_fiscal.sql`

**Interfaces:**
- Consumes: patrón de mig 033 (`crear_asiento(jsonb,jsonb,uuid)`, `current_empresa_id()`, `current_usuario_es_admin()`, `fn_audit()`).
- Produces:
  - Tabla `factura_recibida_impuestos(id, empresa_id, factura_id, tipo, alicuota, base, monto, jurisdiccion, created_at)`
  - Columnas nuevas en `facturas_recibidas`: `tipo, letra, no_gravado, exento, factura_asociada_id, cta_imputacion_id`
  - Columna `proveedores.condicion_fiscal`
  - Config: `cta_percep_iva, cta_percep_iibb, cta_percep_ganancias`
  - RPC `registrar_factura_recibida(p_factura jsonb, p_impuestos jsonb, p_override boolean, p_motivo text)` → jsonb `{id, estado_match, asiento_id, dif, umbral, valor_recibido}`

**Nota de diseño (desvío consciente del spec):** si hay percepciones cargadas pero falta la cuenta configurada, el RPC hace RAISE (no "omite la pata") — un asiento sin esa línea no balancearía. Percepciones tipo `otros` solo se admiten cuando hay `cta_imputacion_id` (van al débito de esa cuenta); con OC pura se rechazan.

- [ ] **Step 1: Escribir la migración completa**

Crear `migrations/054_compras_fiscal.sql`:

```sql
-- ═══════════════════════════════════════════════════════════════════
-- MIGRACIÓN 054 — Compras fiscal completo
-- Spec: docs/superpowers/specs/2026-07-30-compras-fiscal-design.md
--   1. proveedores.condicion_fiscal
--   2. facturas_recibidas: tipo/letra/no_gravado/exento/asociada/cta_imputacion
--   3. Tabla factura_recibida_impuestos (tax lines) + RLS + audit
--   4. Cuentas 113010/113011 + config cta_percep_*
--   5. Backfill: desglose 21% para facturas históricas coherentes
--   6. RPC registrar_factura_recibida v2 (p_impuestos)
-- Requiere: 033 (facturas_recibidas, GR/IR), 023 (crear_asiento, fn_audit),
--           006 (current_empresa_id), 032 (current_usuario_es_admin).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Condición fiscal del proveedor ──────────────────────────────
ALTER TABLE public.proveedores
  ADD COLUMN IF NOT EXISTS condicion_fiscal text NOT NULL DEFAULT 'RI';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='proveedores_condicion_fiscal_check') THEN
    ALTER TABLE public.proveedores ADD CONSTRAINT proveedores_condicion_fiscal_check
      CHECK (condicion_fiscal IN ('RI','monotributo','exento','consumidor_final'));
  END IF;
END $$;

-- ─── 2. Cabecera facturas_recibidas ─────────────────────────────────
ALTER TABLE public.facturas_recibidas
  ADD COLUMN IF NOT EXISTS tipo                text NOT NULL DEFAULT 'factura',
  ADD COLUMN IF NOT EXISTS letra               text NOT NULL DEFAULT 'A',
  ADD COLUMN IF NOT EXISTS no_gravado          numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS exento              numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS factura_asociada_id uuid REFERENCES public.facturas_recibidas(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_imputacion_id   uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='facturas_recibidas_tipo_check') THEN
    ALTER TABLE public.facturas_recibidas ADD CONSTRAINT facturas_recibidas_tipo_check
      CHECK (tipo IN ('factura','nota_credito','nota_debito'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='facturas_recibidas_letra_check') THEN
    ALTER TABLE public.facturas_recibidas ADD CONSTRAINT facturas_recibidas_letra_check
      CHECK (letra IN ('A','B','C','M','X'));
  END IF;
END $$;

-- ─── 3. Tax lines: factura_recibida_impuestos ───────────────────────
CREATE TABLE IF NOT EXISTS public.factura_recibida_impuestos (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid        NOT NULL,
  factura_id   uuid        NOT NULL REFERENCES public.facturas_recibidas(id) ON DELETE CASCADE,
  tipo         text        NOT NULL CHECK (tipo IN ('iva','percepcion_iva','percepcion_iibb','percepcion_ganancias','otros')),
  alicuota     numeric,          -- solo tipo 'iva': 0, 2.5, 5, 10.5, 21, 27
  base         numeric     NOT NULL DEFAULT 0,
  monto        numeric     NOT NULL,
  jurisdiccion text,             -- solo 'percepcion_iibb'
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.factura_recibida_impuestos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.factura_recibida_impuestos;
CREATE POLICY tenant_isolation ON public.factura_recibida_impuestos
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

DROP TRIGGER IF EXISTS trg_audit ON public.factura_recibida_impuestos;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.factura_recibida_impuestos
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

CREATE INDEX IF NOT EXISTS idx_fri_empresa_factura
  ON public.factura_recibida_impuestos (empresa_id, factura_id);

-- ─── 4. Cuentas de percepciones + config ────────────────────────────
DO $$
DECLARE emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_contables WHERE empresa_id=emp_id AND codigo='113010') THEN
    INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa)
    VALUES (emp_id,'113010','PERCEPCIONES IIBB SUFRIDAS','activo',true,true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_contables WHERE empresa_id=emp_id AND codigo='113011') THEN
    INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa)
    VALUES (emp_id,'113011','PERCEPCIONES GANANCIAS SUFRIDAS','activo',true,true);
  END IF;
END $$;

ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_percep_iva       uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_percep_iibb      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_percep_ganancias uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

-- Defaults: 113007 ya existe en el seed 007; 113010/113011 recién creadas.
UPDATE public.config_contable c SET cta_percep_iva = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113007')
  WHERE cta_percep_iva IS NULL;
UPDATE public.config_contable c SET cta_percep_iibb = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113010')
  WHERE cta_percep_iibb IS NULL;
UPDATE public.config_contable c SET cta_percep_ganancias = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113011')
  WHERE cta_percep_ganancias IS NULL;

-- ─── 5. Backfill: facturas históricas con IVA ≈ 21% del neto ────────
-- No se inventa desglose: solo si iva está a ±1% del 21% teórico.
INSERT INTO public.factura_recibida_impuestos (empresa_id, factura_id, tipo, alicuota, base, monto)
SELECT f.empresa_id, f.id, 'iva', 21, f.neto, f.iva
  FROM public.facturas_recibidas f
 WHERE f.iva > 0
   AND abs(f.iva - f.neto*0.21) <= f.neto*0.01
   AND NOT EXISTS (SELECT 1 FROM public.factura_recibida_impuestos i WHERE i.factura_id=f.id);

-- ─── 6. RPC registrar_factura_recibida v2 ───────────────────────────
-- La firma cambia: se elimina la versión de 3 args para evitar overload
-- ambiguo desde PostgREST.
DROP FUNCTION IF EXISTS public.registrar_factura_recibida(jsonb, boolean, text);

CREATE OR REPLACE FUNCTION public.registrar_factura_recibida(
  p_factura   jsonb,
  p_impuestos jsonb   DEFAULT '[]'::jsonb,
  p_override  boolean DEFAULT false,
  p_motivo    text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_empresa        uuid := public.current_empresa_id();
  v_cfg            public.config_contable%ROWTYPE;
  v_oc_id          uuid := NULLIF(p_factura->>'oc_id','')::uuid;
  v_prov_id        uuid := NULLIF(p_factura->>'proveedor_id','')::uuid;
  v_tipo           text := COALESCE(NULLIF(p_factura->>'tipo',''),'factura');
  v_letra          text := COALESCE(NULLIF(p_factura->>'letra',''),'A');
  v_neto           numeric := COALESCE((p_factura->>'neto')::numeric,0);
  v_no_gravado     numeric := COALESCE((p_factura->>'no_gravado')::numeric,0);
  v_exento         numeric := COALESCE((p_factura->>'exento')::numeric,0);
  v_iva            numeric := COALESCE((p_factura->>'iva')::numeric,0);
  v_total          numeric := (p_factura->>'total')::numeric;
  v_cta_imput      uuid := NULLIF(p_factura->>'cta_imputacion_id','')::uuid;
  v_asociada       uuid := NULLIF(p_factura->>'factura_asociada_id','')::uuid;
  v_sum_bases      numeric; v_sum_iva numeric;
  v_p_iva          numeric; v_p_iibb numeric; v_p_gcias numeric; v_p_otros numeric;
  v_sum_percep     numeric;
  v_neto_total     numeric;
  v_valor_recibido numeric := 0; v_dif numeric := 0; v_umbral numeric := 0;
  v_es_admin       boolean := public.current_usuario_es_admin();
  v_estado         text := 'ok';
  v_fact_id        uuid; v_asiento jsonb; v_oc_nro text; v_prov text;
  v_lineas         jsonb := '[]'::jsonb;
  v_orden          int := 0;
  v_desc_tipo      text;
  imp              jsonb;
BEGIN
  -- ── Validaciones básicas ──────────────────────────────────────────
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_factura->>'nro','')='' THEN RAISE EXCEPTION 'Falta el número de comprobante'; END IF;
  IF COALESCE(p_factura->>'fecha','')='' THEN RAISE EXCEPTION 'Falta la fecha'; END IF;
  IF v_total IS NULL OR v_total <= 0 THEN RAISE EXCEPTION 'El total debe ser mayor a cero'; END IF;
  IF v_neto < 0 OR v_no_gravado < 0 OR v_exento < 0 THEN
    RAISE EXCEPTION 'Los importes se cargan en positivo; el signo lo da el tipo de comprobante';
  END IF;
  IF v_tipo NOT IN ('factura','nota_credito','nota_debito') THEN RAISE EXCEPTION 'Tipo inválido: %', v_tipo; END IF;
  IF v_letra NOT IN ('A','B','C','M','X') THEN RAISE EXCEPTION 'Letra inválida: %', v_letra; END IF;

  -- ── Sumas del array de impuestos ──────────────────────────────────
  SELECT COALESCE(SUM((i->>'base')::numeric),0), COALESCE(SUM((i->>'monto')::numeric),0)
    INTO v_sum_bases, v_sum_iva
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='iva';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_iva
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_iva';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_iibb
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_iibb';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_gcias
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_ganancias';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_otros
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='otros';
  v_sum_percep := v_p_iva + v_p_iibb + v_p_gcias + v_p_otros;
  v_neto_total := v_neto + v_no_gravado + v_exento;

  -- ── Validación aritmética (autoritativa, tolerancia $0.01) ────────
  IF abs(v_neto - v_sum_bases) > 0.01 THEN
    RAISE EXCEPTION 'El neto % no coincide con la suma de bases de IVA %', v_neto, v_sum_bases;
  END IF;
  IF abs(v_iva - v_sum_iva) > 0.01 THEN
    RAISE EXCEPTION 'El IVA % no coincide con la suma del desglose %', v_iva, v_sum_iva;
  END IF;
  IF abs(v_total - (v_neto_total + v_sum_iva + v_sum_percep)) > 0.01 THEN
    RAISE EXCEPTION 'El total % no cierra: neto+no gravado+exento+IVA+percepciones = %',
      v_total, v_neto_total + v_sum_iva + v_sum_percep;
  END IF;
  IF v_letra NOT IN ('A','M') AND v_sum_iva > 0 THEN
    RAISE EXCEPTION 'Una factura letra % no discrimina IVA (el crédito no es computable)', v_letra;
  END IF;

  -- ── Validaciones por tipo de comprobante ──────────────────────────
  IF v_tipo IN ('nota_credito','nota_debito') THEN
    IF v_asociada IS NULL THEN RAISE EXCEPTION 'NC/ND requiere factura asociada'; END IF;
    PERFORM 1 FROM public.facturas_recibidas
      WHERE id = v_asociada AND empresa_id = v_empresa AND proveedor_id = v_prov_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Factura asociada inexistente o de otro proveedor'; END IF;
  END IF;
  IF (v_tipo <> 'factura' OR v_oc_id IS NULL) AND v_cta_imput IS NULL THEN
    RAISE EXCEPTION 'Comprobante sin OC (o NC/ND) requiere cuenta de imputación';
  END IF;
  IF v_p_otros > 0 AND v_cta_imput IS NULL THEN
    RAISE EXCEPTION 'Impuestos tipo "otros" requieren cuenta de imputación (van al costo)';
  END IF;

  -- ── Config contable ───────────────────────────────────────────────
  SELECT * INTO v_cfg FROM public.config_contable WHERE empresa_id = v_empresa;
  IF v_cfg.cta_proveedores IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_proveedores'; END IF;
  IF v_sum_iva > 0 AND v_cfg.cta_iva_credito IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_iva_credito'; END IF;
  IF v_tipo = 'factura' AND v_oc_id IS NOT NULL AND v_cfg.cta_gr_ir IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: falta cta_gr_ir (211009)';
  END IF;
  IF v_p_iva   > 0 AND v_cfg.cta_percep_iva       IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_iva'; END IF;
  IF v_p_iibb  > 0 AND v_cfg.cta_percep_iibb      IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_iibb'; END IF;
  IF v_p_gcias > 0 AND v_cfg.cta_percep_ganancias IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_ganancias'; END IF;

  -- ── 3-way match (solo factura con OC) ─────────────────────────────
  IF v_tipo = 'factura' AND v_oc_id IS NOT NULL THEN
    SELECT COALESCE(SUM(precio_unitario * cantidad_recibida), 0)
      INTO v_valor_recibido FROM public.oc_items WHERE oc_id = v_oc_id;
    IF COALESCE(v_cfg.precios_incluyen_iva, false) THEN
      v_valor_recibido := v_valor_recibido / (1 + COALESCE(v_cfg.iva_alicuota, 0));
    END IF;
    v_dif    := abs(v_neto_total - v_valor_recibido);
    v_umbral := LEAST(v_valor_recibido * v_cfg.match_tolerancia_pct, v_cfg.match_tolerancia_monto);
    IF v_dif <= v_umbral THEN v_estado := 'ok';
    ELSIF p_override AND v_es_admin THEN v_estado := 'override';
    ELSE
      RAISE EXCEPTION 'Match fallido: neto factura % vs recibido % (dif %, umbral %). Requiere override de un administrador.',
        v_neto_total, v_valor_recibido, v_dif, v_umbral;
    END IF;
  END IF;

  SELECT nro    INTO v_oc_nro FROM public.ordenes_compra WHERE id = v_oc_id;
  SELECT nombre INTO v_prov   FROM public.proveedores     WHERE id = v_prov_id;
  v_desc_tipo := CASE v_tipo WHEN 'nota_credito' THEN 'NC' WHEN 'nota_debito' THEN 'ND' ELSE 'Factura' END;

  -- ── Armar líneas del asiento ──────────────────────────────────────
  -- Débito de imputación: GR/IR (factura con OC) o cta elegida (resto).
  -- 'otros' impuestos van al costo (misma cuenta de imputación).
  IF v_tipo = 'nota_credito' THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_proveedores,
      'debe', v_total, 'haber', 0, 'descripcion', COALESCE(v_prov,'Proveedor')||' (NC)', 'orden', v_orden);
    v_orden := v_orden + 1;
    IF v_neto_total + v_p_otros > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cta_imput,
        'debe', 0, 'haber', v_neto_total + v_p_otros, 'descripcion', 'NC '||(p_factura->>'nro'), 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_sum_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_iva_credito,
        'debe', 0, 'haber', v_sum_iva, 'descripcion', 'IVA CF s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iva,
        'debe', 0, 'haber', v_p_iva, 'descripcion', 'Percep. IVA s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iibb > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iibb,
        'debe', 0, 'haber', v_p_iibb, 'descripcion', 'Percep. IIBB s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_gcias > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_ganancias,
        'debe', 0, 'haber', v_p_gcias, 'descripcion', 'Percep. Gcias s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
  ELSE
    -- factura (con o sin OC) y nota de débito
    v_lineas := v_lineas || jsonb_build_object(
      'cuenta_id', CASE WHEN v_tipo='factura' AND v_oc_id IS NOT NULL THEN v_cfg.cta_gr_ir ELSE v_cta_imput END,
      'debe', v_neto_total + v_p_otros, 'haber', 0,
      'descripcion', CASE WHEN v_tipo='factura' AND v_oc_id IS NOT NULL
        THEN 'Cancela Facturas a recibir (GR/IR)' ELSE v_desc_tipo||' '||(p_factura->>'nro') END,
      'orden', v_orden);
    v_orden := v_orden + 1;
    IF v_sum_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_iva_credito,
        'debe', v_sum_iva, 'haber', 0, 'descripcion', 'IVA Crédito Fiscal', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iva,
        'debe', v_p_iva, 'haber', 0, 'descripcion', 'Percepción IVA sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iibb > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iibb,
        'debe', v_p_iibb, 'haber', 0, 'descripcion', 'Percepción IIBB sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_gcias > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_ganancias,
        'debe', v_p_gcias, 'haber', 0, 'descripcion', 'Percepción Ganancias sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_proveedores,
      'debe', 0, 'haber', v_total, 'descripcion', COALESCE(v_prov,'Proveedor'), 'orden', v_orden);
  END IF;

  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha',          p_factura->>'fecha',
      'descripcion',    format('%s proveedor %s%s — %s', v_desc_tipo, p_factura->>'nro',
                          CASE WHEN v_oc_nro IS NOT NULL THEN ' s/OC '||v_oc_nro ELSE '' END,
                          COALESCE(v_prov,'?')),
      'comprobante_nro', p_factura->>'nro',
      'tipo',           'auto-compra',
      'origen_tipo',    'factura_recibida',
      'origen_id',      NULL,
      'estado',         'confirmado',
      'moneda',         COALESCE(NULLIF(p_factura->>'moneda',''),'ARS'),
      'tipo_cambio',    NULLIF(p_factura->>'tipo_cambio','')::numeric,
      'proveedor_id',   p_factura->>'proveedor_id'
    ),
    v_lineas,
    NULL
  );

  -- ── Insertar factura + tax lines ──────────────────────────────────
  INSERT INTO public.facturas_recibidas (
    empresa_id, proveedor_id, oc_id, nro, fecha, fecha_vto,
    neto, iva, total, moneda, tipo_cambio,
    tipo, letra, no_gravado, exento, factura_asociada_id, cta_imputacion_id,
    estado_match, asiento_id, override_por, override_motivo, created_by
  ) VALUES (
    v_empresa, v_prov_id, v_oc_id,
    p_factura->>'nro', (p_factura->>'fecha')::date, NULLIF(p_factura->>'fecha_vto','')::date,
    v_neto, v_iva, v_total,
    COALESCE(NULLIF(p_factura->>'moneda',''),'ARS'),
    COALESCE((p_factura->>'tipo_cambio')::numeric, 1),
    v_tipo, v_letra, v_no_gravado, v_exento, v_asociada, v_cta_imput,
    v_estado, (v_asiento->>'id')::uuid,
    CASE WHEN v_estado='override' THEN auth.uid() ELSE NULL END,
    CASE WHEN v_estado='override' THEN p_motivo  ELSE NULL END,
    auth.uid()
  ) RETURNING id INTO v_fact_id;

  FOR imp IN SELECT * FROM jsonb_array_elements(p_impuestos) LOOP
    INSERT INTO public.factura_recibida_impuestos
      (empresa_id, factura_id, tipo, alicuota, base, monto, jurisdiccion)
    VALUES (
      v_empresa, v_fact_id, imp->>'tipo',
      NULLIF(imp->>'alicuota','')::numeric,
      COALESCE((imp->>'base')::numeric, 0),
      (imp->>'monto')::numeric,
      NULLIF(imp->>'jurisdiccion','')
    );
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_fact_id, 'estado_match', v_estado, 'asiento_id', v_asiento->>'id',
    'dif', v_dif, 'umbral', v_umbral, 'valor_recibido', v_valor_recibido
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, jsonb, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, jsonb, boolean, text) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, línea a línea)
-- ═══════════════════════════════════════════════════════════════════
-- 1) SELECT codigo,nombre FROM cuentas_contables WHERE codigo IN ('113007','113010','113011');
--    → 3 filas.
-- 2) SELECT cta_percep_iva,cta_percep_iibb,cta_percep_ganancias FROM config_contable;
--    → los 3 NOT NULL.
-- 3) SELECT count(*) FROM factura_recibida_impuestos;  → ≥ cantidad de facturas
--    históricas con IVA≈21%.
-- 4) SELECT proname, pronargs FROM pg_proc WHERE proname='registrar_factura_recibida';
--    → 1 sola fila con pronargs=4.
```

- [ ] **Step 2: Sanity check del SQL**

Run: `psql --version >/dev/null 2>&1 && psql -f /dev/null 2>/dev/null; node -e "const s=require('fs').readFileSync('migrations/054_compras_fiscal.sql','utf8'); console.log('BEGIN/COMMIT:', (s.match(/^BEGIN;/m)?1:0), (s.match(/^COMMIT;/m)?1:0)); console.log('longitud OK:', s.length>5000)"`
Expected: `BEGIN/COMMIT: 1 1` y `longitud OK: true`. (No hay Postgres local — la validación real es correrla en el SQL Editor de Supabase; eso lo hace Giuliano en el paso de deploy.)

- [ ] **Step 3: Commit**

```bash
git add migrations/054_compras_fiscal.sql
git commit -m "feat: migración 054 — desglose fiscal de compras (tax lines, percepciones, NC/ND, RPC v2)"
```

---

### Task 3: Modal de factura rediseñado (HTML + JS)

**Files:**
- Modify: `index.html` — reemplazar el modal `modal-factura-recibida` (~línea 1849-1893) y el bloque JS de facturas recibidas (~línea 9763-9884: `openFacturaRecibidaModal`, `_calcValorRecibidoOC`, `actualizarMatchPreview`, `registrarFacturaRecibida`)

**Interfaces:**
- Consumes: `computeTotalesFactura`, `validarDesgloseFactura`, `sugerirLetra`, `letraDiscriminaIva`, `ALICUOTAS_IVA` (Task 1); RPC v2 (Task 2); `evaluarMatchFactura` (existente).
- Produces:
  - `openFacturaRecibidaModal(ocId)` — factura con OC (firma sin cambios, la llama el botón Factura de la OC)
  - `openFacturaSinOCModal()` — factura/ND de gastos
  - `openNCNDModal(facturaId)` — NC/ND sobre factura existente
  - Estado interno `_frCtx = {mode:'oc'|'sinoc'|'ncnd', ocId, provId, facturaAsociadaId}`, drafts `frIvas[]`, `frPerceps[]`

- [ ] **Step 1: Reemplazar el HTML del modal**

Reemplazar TODO el contenido de `<div class="modal-overlay" id="modal-factura-recibida">...</div>` por:

```html
<!-- MODAL: Registrar comprobante de proveedor (fiscal completo + 3-way match) -->
<div class="modal-overlay" id="modal-factura-recibida">
  <div class="modal" style="width:760px;max-width:95vw">
    <div class="modal-header"><div class="modal-title" id="fr-modal-title">Registrar factura de proveedor</div><button class="modal-close" onclick="closeModal('modal-factura-recibida')">×</button></div>
    <div class="modal-body">
      <div class="form-row" style="grid-template-columns:150px 90px 1fr 1fr">
        <div class="form-group"><label>Tipo *</label><select id="fr-tipo" onchange="frOnTipoChange()"><option value="factura">Factura</option><option value="nota_debito">Nota de débito</option><option value="nota_credito">Nota de crédito</option></select></div>
        <div class="form-group"><label>Letra *</label><select id="fr-letra" onchange="frOnLetraChange()"><option>A</option><option>B</option><option>C</option><option>M</option><option>X</option></select></div>
        <div class="form-group" id="fr-prov-ro-wrap"><label>Proveedor</label><input type="text" id="fr-proveedor-nombre" readonly style="background:var(--bg);color:var(--text3)"></div>
        <div class="form-group" id="fr-prov-sel-wrap" style="display:none"><label>Proveedor *</label><select id="fr-proveedor-select" onchange="frOnProveedorChange()"></select></div>
        <div class="form-group" id="fr-oc-wrap"><label>OC</label><input type="text" id="fr-oc-nro" readonly style="background:var(--bg);color:var(--text3)"></div>
      </div>
      <div id="fr-letra-warn" style="display:none;font-size:11px;color:var(--coral);margin:-4px 0 8px"></div>
      <div class="form-row" id="fr-asociada-wrap" style="display:none;grid-template-columns:1fr 1fr">
        <div class="form-group"><label>Factura asociada *</label><select id="fr-asociada"></select></div>
        <div class="form-group"><label>Cuenta de contrapartida *</label><select id="fr-cta-imputacion-nc"></select></div>
      </div>
      <div class="form-row" id="fr-cta-wrap" style="display:none;grid-template-columns:1fr">
        <div class="form-group"><label>Cuenta de imputación (gasto) *</label><select id="fr-cta-imputacion"></select></div>
      </div>
      <div class="form-row" style="grid-template-columns:1fr 140px 140px 100px 120px">
        <div class="form-group"><label>Nro comprobante *</label><input type="text" id="fr-nro" placeholder="A-0001-00012345"></div>
        <div class="form-group"><label>Fecha *</label><input type="date" id="fr-fecha"></div>
        <div class="form-group"><label>Vencimiento</label><input type="date" id="fr-fecha-vto"></div>
        <div class="form-group"><label>Moneda</label><select id="fr-moneda"><option value="ARS">ARS</option><option value="USD">USD</option></select></div>
        <div class="form-group"><label>Tipo de cambio</label><input type="number" id="fr-tc" step="0.01" min="0" placeholder="1.00"></div>
      </div>
      <hr class="form-divider">
      <div id="fr-iva-section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px"><div class="section-label" style="margin:0">IVA por alícuota</div><button class="btn btn-ghost btn-sm" onclick="frAddIvaRow()">+ Alícuota</button></div>
        <div id="fr-iva-rows" style="display:flex;flex-direction:column;gap:6px"></div>
      </div>
      <div class="form-row" style="grid-template-columns:1fr 1fr;margin-top:8px">
        <div class="form-group"><label>No gravado</label><input type="number" id="fr-no-gravado" step="0.01" min="0" placeholder="0.00" oninput="frRecalc()"></div>
        <div class="form-group"><label>Exento</label><input type="number" id="fr-exento" step="0.01" min="0" placeholder="0.00" oninput="frRecalc()"></div>
      </div>
      <div style="display:flex;justify-content:space-between;align-items:center;margin:8px 0 6px"><div class="section-label" style="margin:0">Percepciones</div><button class="btn btn-ghost btn-sm" onclick="frAddPercepRow()">+ Percepción</button></div>
      <div id="fr-percep-rows" style="display:flex;flex-direction:column;gap:6px"></div>
      <hr class="form-divider">
      <div class="form-row" style="grid-template-columns:1fr 220px;align-items:end">
        <div id="fr-totales" style="font-size:12px;color:var(--text2);font-family:var(--mono)"></div>
        <div class="form-group"><label>Total según el comprobante *</label><input type="number" id="fr-total" step="0.01" min="0" placeholder="0.00" oninput="frRecalc()"></div>
      </div>
      <div id="fr-arit-badge" style="margin-bottom:8px"></div>
      <div id="fr-match-preview" style="display:none;padding:10px 12px;border-radius:6px;border:1px solid var(--border);background:var(--surface);margin-bottom:8px">
        <div style="font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--text3);font-weight:600;margin-bottom:8px">Verificación 3-way match</div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:8px;font-size:12px">
          <div><div style="color:var(--text3);margin-bottom:2px">Valor recibido (OC)</div><div class="mono" id="fr-match-recibido">—</div></div>
          <div><div style="color:var(--text3);margin-bottom:2px">Neto factura</div><div class="mono" id="fr-match-neto">—</div></div>
          <div><div style="color:var(--text3);margin-bottom:2px">Diferencia</div><div class="mono" id="fr-match-dif">—</div></div>
          <div><div style="color:var(--text3);margin-bottom:2px">Umbral</div><div class="mono" id="fr-match-umbral">—</div></div>
        </div>
        <div style="margin-top:10px" id="fr-match-badge"></div>
      </div>
      <div id="fr-override-section" style="display:none">
        <div class="form-group"><label style="color:var(--coral)">Motivo de override (admin requerido)</label><textarea id="fr-motivo" rows="2" placeholder="Justificá la discrepancia para registrar de todas formas..." style="width:100%;box-sizing:border-box;background:var(--bg);border:1px solid var(--coral);color:var(--text);border-radius:5px;padding:8px;font-size:12px;font-family:var(--mono);resize:vertical"></textarea></div>
      </div>
    </div>
    <div class="modal-footer">
      <button class="btn btn-ghost" onclick="closeModal('modal-factura-recibida')">Cancelar</button>
      <button class="btn btn-primary" id="btn-save-fr" onclick="registrarFacturaRecibida('btn-save-fr')">Registrar</button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Reemplazar el bloque JS de facturas recibidas**

Reemplazar desde `let _currentFacturaOcId=null;` hasta el final de `registrarFacturaRecibida` (NO tocar `renderFacturasRecibidas` en esta task) por:

```js
let _frCtx={mode:'oc',ocId:null,provId:null,facturaAsociadaId:null};
let frIvas=[],frPerceps=[];
const PERCEP_TIPOS=[['percepcion_iva','Percep. IVA'],['percepcion_iibb','Percep. IIBB'],['percepcion_ganancias','Percep. Ganancias'],['otros','Otros impuestos']];
const JURISDICCIONES=['CABA','Buenos Aires','Catamarca','Chaco','Chubut','Córdoba','Corrientes','Entre Ríos','Formosa','Jujuy','La Pampa','La Rioja','Mendoza','Misiones','Neuquén','Río Negro','Salta','San Juan','San Luis','Santa Cruz','Santa Fe','Sgo. del Estero','Tierra del Fuego','Tucumán'];

function _frCuentasImputablesOpts(sel){
  return '<option value="">— elegir cuenta —</option>'+cuentasContables
    .filter(c=>c.imputable!==false&&c.activa!==false)
    .map(c=>`<option value="${esc(c.id)}" ${sel===c.id?'selected':''}>${esc(c.codigo)} · ${esc(c.nombre)}</option>`).join('');
}

function _frReset(){
  frIvas=[];frPerceps=[];
  ['fr-nro','fr-fecha-vto','fr-no-gravado','fr-exento','fr-total','fr-tc','fr-motivo'].forEach(id=>{const el=document.getElementById(id);if(el)el.value='';});
  document.getElementById('fr-fecha').value=hoyLocal();
  document.getElementById('fr-tipo').value='factura';
  document.getElementById('fr-moneda').value='ARS';
  document.getElementById('fr-match-preview').style.display='none';
  document.getElementById('fr-override-section').style.display='none';
  document.getElementById('fr-arit-badge').innerHTML='';
  document.getElementById('fr-letra-warn').style.display='none';
}

function openFacturaRecibidaModal(ocId){
  const oc=ordenesCompra.find(o=>o.id===ocId);
  if(!oc){notify('OC no encontrada','err');return;}
  const prov=proveedores.find(p=>p.id===oc.proveedor_id)||oc.proveedores||null;
  _frCtx={mode:'oc',ocId,provId:oc.proveedor_id,facturaAsociadaId:null};
  _frReset();
  document.getElementById('fr-modal-title').textContent='Registrar factura de proveedor';
  document.getElementById('fr-prov-ro-wrap').style.display='';
  document.getElementById('fr-prov-sel-wrap').style.display='none';
  document.getElementById('fr-oc-wrap').style.display='';
  document.getElementById('fr-asociada-wrap').style.display='none';
  document.getElementById('fr-cta-wrap').style.display='none';
  document.getElementById('fr-proveedor-nombre').value=prov?.nombre||'—';
  document.getElementById('fr-oc-nro').value=oc.nro||'';
  document.getElementById('fr-moneda').value=oc.moneda||'ARS';
  document.getElementById('fr-tc').value=oc.tipo_cambio||'';
  document.getElementById('fr-letra').value=sugerirLetra(prov?.condicion_fiscal);
  if(letraDiscriminaIva(document.getElementById('fr-letra').value))frAddIvaRow(21);
  frOnLetraChange();frRender();openModal('modal-factura-recibida');
}

function openFacturaSinOCModal(){
  _frCtx={mode:'sinoc',ocId:null,provId:null,facturaAsociadaId:null};
  _frReset();
  document.getElementById('fr-modal-title').textContent='Registrar comprobante sin OC (gastos)';
  document.getElementById('fr-prov-ro-wrap').style.display='none';
  document.getElementById('fr-prov-sel-wrap').style.display='';
  document.getElementById('fr-oc-wrap').style.display='none';
  document.getElementById('fr-asociada-wrap').style.display='none';
  document.getElementById('fr-cta-wrap').style.display='';
  document.getElementById('fr-proveedor-select').innerHTML='<option value="">— elegir proveedor —</option>'+proveedores.filter(p=>p.activo!==false).map(p=>`<option value="${esc(p.id)}">${esc(p.nombre)}</option>`).join('');
  document.getElementById('fr-cta-imputacion').innerHTML=_frCuentasImputablesOpts(configContable?.cta_compra_servicios||'');
  document.getElementById('fr-letra').value='A';
  frAddIvaRow(21);frOnLetraChange();frRender();openModal('modal-factura-recibida');
}

function openNCNDModal(facturaId){
  const fa=facturasRecibidas.find(x=>x.id===facturaId);
  if(!fa){notify('Factura no encontrada','err');return;}
  const prov=proveedores.find(p=>p.id===fa.proveedor_id);
  _frCtx={mode:'ncnd',ocId:null,provId:fa.proveedor_id,facturaAsociadaId:facturaId};
  _frReset();
  document.getElementById('fr-modal-title').textContent='NC / ND de proveedor';
  document.getElementById('fr-tipo').value='nota_credito';
  document.getElementById('fr-prov-ro-wrap').style.display='';
  document.getElementById('fr-prov-sel-wrap').style.display='none';
  document.getElementById('fr-oc-wrap').style.display='none';
  document.getElementById('fr-asociada-wrap').style.display='';
  document.getElementById('fr-cta-wrap').style.display='none';
  document.getElementById('fr-proveedor-nombre').value=prov?.nombre||'—';
  document.getElementById('fr-asociada').innerHTML=facturasRecibidas
    .filter(x=>x.proveedor_id===fa.proveedor_id&&(x.tipo||'factura')==='factura')
    .map(x=>`<option value="${esc(x.id)}" ${x.id===facturaId?'selected':''}>${esc(x.nro)} · ${x.fecha}</option>`).join('');
  document.getElementById('fr-cta-imputacion-nc').innerHTML=_frCuentasImputablesOpts(fa.cta_imputacion_id||'');
  document.getElementById('fr-letra').value=fa.letra||'A';
  document.getElementById('fr-moneda').value=fa.moneda||'ARS';
  if(letraDiscriminaIva(fa.letra||'A'))frAddIvaRow(21);
  frOnLetraChange();frRender();openModal('modal-factura-recibida');
}

function frOnTipoChange(){
  const t=document.getElementById('fr-tipo').value;
  if(_frCtx.mode==='ncnd'&&t==='factura'){document.getElementById('fr-tipo').value='nota_credito';return;}
  frRecalc();
}
function frOnProveedorChange(){
  const p=proveedores.find(x=>x.id===document.getElementById('fr-proveedor-select').value);
  _frCtx.provId=p?.id||null;
  if(p){document.getElementById('fr-letra').value=sugerirLetra(p.condicion_fiscal);frOnLetraChange();}
}
function frOnLetraChange(){
  const letra=document.getElementById('fr-letra').value;
  const discrimina=letraDiscriminaIva(letra);
  document.getElementById('fr-iva-section').style.display=discrimina?'':'none';
  if(!discrimina)frIvas=[];
  const prov=proveedores.find(p=>p.id===_frCtx.provId);
  const warn=document.getElementById('fr-letra-warn');
  if(prov&&sugerirLetra(prov.condicion_fiscal)!==letra){
    warn.textContent=`⚠ El proveedor es ${prov.condicion_fiscal||'RI'} — lo esperable es letra ${sugerirLetra(prov.condicion_fiscal)}.`;
    warn.style.display='';
  }else warn.style.display='none';
  frRender();
}

function frAddIvaRow(alicuota){frIvas.push({alicuota:alicuota??21,base:'',monto:''});frRender();}
function frDelIvaRow(i){frIvas.splice(i,1);frRender();}
function frOnIvaInput(i,campo,val){
  frIvas[i][campo]=val;
  if(campo==='base'||campo==='alicuota'){
    const b=parseFloat(frIvas[i].base)||0,a=parseFloat(frIvas[i].alicuota)||0;
    frIvas[i].monto=(Math.round(b*a)/100).toFixed(2);
    const el=document.getElementById(`fr-iva-monto-${i}`);if(el)el.value=frIvas[i].monto;
  }
  frRecalc();
}
function frAddPercepRow(){frPerceps.push({tipo:'percepcion_iibb',jurisdiccion:'Buenos Aires',monto:''});frRender();}
function frDelPercepRow(i){frPerceps.splice(i,1);frRender();}
function frOnPercepInput(i,campo,val){
  frPerceps[i][campo]=val;
  if(campo==='tipo')frRender();else frRecalc();
}

function frRender(){
  document.getElementById('fr-iva-rows').innerHTML=frIvas.map((r,i)=>`
    <div style="display:grid;grid-template-columns:110px 1fr 1fr 32px;gap:6px;align-items:center">
      <select onchange="frOnIvaInput(${i},'alicuota',this.value)" style="width:100%">${ALICUOTAS_IVA.map(a=>`<option value="${a}" ${String(a)===String(r.alicuota)?'selected':''}>${a}%</option>`).join('')}</select>
      <input type="number" step="0.01" min="0" placeholder="Base imponible" value="${esc(String(r.base??''))}" oninput="frOnIvaInput(${i},'base',this.value)">
      <input type="number" step="0.01" min="0" placeholder="IVA" id="fr-iva-monto-${i}" value="${esc(String(r.monto??''))}" oninput="frOnIvaInput(${i},'monto',this.value)">
      <button class="btn btn-danger btn-sm" onclick="frDelIvaRow(${i})" title="Quitar">×</button>
    </div>`).join('')||'<div style="font-size:11px;color:var(--text3)">Sin IVA discriminado</div>';
  document.getElementById('fr-percep-rows').innerHTML=frPerceps.map((r,i)=>`
    <div style="display:grid;grid-template-columns:170px 1fr 1fr 32px;gap:6px;align-items:center">
      <select onchange="frOnPercepInput(${i},'tipo',this.value)" style="width:100%">${PERCEP_TIPOS.map(([v,l])=>`<option value="${v}" ${v===r.tipo?'selected':''}>${l}</option>`).join('')}</select>
      ${r.tipo==='percepcion_iibb'?`<select onchange="frOnPercepInput(${i},'jurisdiccion',this.value)">${JURISDICCIONES.map(j=>`<option ${j===r.jurisdiccion?'selected':''}>${j}</option>`).join('')}</select>`:'<div></div>'}
      <input type="number" step="0.01" min="0" placeholder="Monto" value="${esc(String(r.monto??''))}" oninput="frOnPercepInput(${i},'monto',this.value)">
      <button class="btn btn-danger btn-sm" onclick="frDelPercepRow(${i})" title="Quitar">×</button>
    </div>`).join('')||'<div style="font-size:11px;color:var(--text3)">Sin percepciones</div>';
  frRecalc();
}

function frTotalesDraft(){
  return computeTotalesFactura({
    ivas:frIvas.map(r=>({alicuota:parseFloat(r.alicuota)||0,base:parseFloat(r.base)||0,monto:parseFloat(r.monto)||0})),
    noGravado:parseFloat(document.getElementById('fr-no-gravado').value)||0,
    exento:parseFloat(document.getElementById('fr-exento').value)||0,
    percepciones:frPerceps.map(r=>({tipo:r.tipo,monto:parseFloat(r.monto)||0,jurisdiccion:r.jurisdiccion||null})),
  });
}

function frRecalc(){
  const t=frTotalesDraft();
  const fmt=n=>n.toLocaleString('es-AR',{minimumFractionDigits:2,maximumFractionDigits:2});
  document.getElementById('fr-totales').innerHTML=
    `Neto ${fmt(t.neto)} · IVA ${fmt(t.iva)} · Percep ${fmt(t.percep)} · <b>Total calc. ${fmt(t.total)}</b>`;
  const totalTipeado=parseFloat(document.getElementById('fr-total').value)||0;
  const badge=document.getElementById('fr-arit-badge');
  if(totalTipeado>0){
    const v=validarDesgloseFactura({letra:document.getElementById('fr-letra').value,ivas:frIvas,totalTipeado,totales:t});
    badge.innerHTML=v.ok?'<span class="badge badge-ok">✓ La suma cierra</span>'
      :v.errores.map(e=>`<div style="font-size:11px;color:var(--coral)">✗ ${esc(e)}</div>`).join('');
  }else badge.innerHTML='';
  // Preview 3-way match — solo factura con OC
  const preview=document.getElementById('fr-match-preview');
  const overrideSection=document.getElementById('fr-override-section');
  const esFacturaConOC=_frCtx.mode==='oc'&&document.getElementById('fr-tipo').value==='factura';
  const netoTotal=t.neto+(parseFloat(document.getElementById('fr-no-gravado').value)||0)+(parseFloat(document.getElementById('fr-exento').value)||0);
  if(!esFacturaConOC||netoTotal<=0){preview.style.display='none';overrideSection.style.display='none';return;}
  const valorRecibido=_calcValorRecibidoOC(_frCtx.ocId);
  const tolPct=parseFloat(configContable?.match_tolerancia_pct)||0;
  const tolMonto=parseFloat(configContable?.match_tolerancia_monto)||0;
  const match=evaluarMatchFactura({valorRecibido,neto:netoTotal,tolPct,tolMonto});
  document.getElementById('fr-match-recibido').textContent=fmt(valorRecibido);
  document.getElementById('fr-match-neto').textContent=fmt(netoTotal);
  document.getElementById('fr-match-dif').textContent=fmt(match.dif);
  document.getElementById('fr-match-umbral').textContent=fmt(match.umbral);
  const mbadge=document.getElementById('fr-match-badge');
  if(match.ok){
    mbadge.innerHTML='<span class="badge badge-ok" style="font-size:12px">✓ MATCH OK</span>';
    preview.style.borderColor='var(--green)';overrideSection.style.display='none';
  }else{
    mbadge.innerHTML='<span class="badge badge-coral" style="font-size:12px">✗ DISCREPANCIA</span>';
    preview.style.borderColor='var(--coral)';
    const esAdmin=currentUserData?.es_admin===true;
    overrideSection.style.display=esAdmin?'':'none';
    if(!esAdmin)mbadge.innerHTML+=' <span style="font-size:11px;color:var(--text3);margin-left:8px">Se requiere un administrador para registrar con discrepancia.</span>';
  }
  preview.style.display='';
}

async function registrarFacturaRecibida(btnId){
  const tipo=document.getElementById('fr-tipo').value;
  const letra=document.getElementById('fr-letra').value;
  const nro=document.getElementById('fr-nro').value.trim();
  const fecha=document.getElementById('fr-fecha').value;
  const t=frTotalesDraft();
  const totalTipeado=parseFloat(document.getElementById('fr-total').value)||0;
  const noGravado=parseFloat(document.getElementById('fr-no-gravado').value)||0;
  const exento=parseFloat(document.getElementById('fr-exento').value)||0;
  if(!nro){notify('El número de comprobante es obligatorio','err');return;}
  if(!fecha){notify('La fecha es obligatoria','err');return;}
  if(totalTipeado<=0){notify('El total debe ser mayor a cero','err');return;}
  if(_frCtx.mode==='sinoc'&&!_frCtx.provId){notify('Elegí el proveedor','err');return;}
  const v=validarDesgloseFactura({letra,ivas:frIvas,totalTipeado,totales:t});
  if(!v.ok){notify(v.errores[0],'err');return;}
  let ctaImputacion=null,facturaAsociada=null;
  if(_frCtx.mode==='ncnd'){
    facturaAsociada=document.getElementById('fr-asociada').value||null;
    ctaImputacion=document.getElementById('fr-cta-imputacion-nc').value||null;
    if(!facturaAsociada){notify('Elegí la factura asociada','err');return;}
    if(!ctaImputacion){notify('Elegí la cuenta de contrapartida','err');return;}
  }else if(_frCtx.mode==='sinoc'){
    ctaImputacion=document.getElementById('fr-cta-imputacion').value||null;
    if(!ctaImputacion){notify('Elegí la cuenta de imputación','err');return;}
  }
  // Override de match (solo factura con OC)
  let override=false,motivo=null;
  if(_frCtx.mode==='oc'&&tipo==='factura'){
    const netoTotal=t.neto+noGravado+exento;
    const valorRecibido=_calcValorRecibidoOC(_frCtx.ocId);
    const tolPct=parseFloat(configContable?.match_tolerancia_pct)||0;
    const tolMonto=parseFloat(configContable?.match_tolerancia_monto)||0;
    const match=evaluarMatchFactura({valorRecibido,neto:netoTotal,tolPct,tolMonto});
    if(!match.ok){
      if(currentUserData?.es_admin!==true){notify('Hay una discrepancia en el match. Solo un administrador puede registrar con override.','err');return;}
      motivo=(document.getElementById('fr-motivo').value||'').trim();
      if(!motivo){notify('Ingresá el motivo del override para continuar','err');return;}
      override=true;
    }
  }
  const impuestos=[
    ...frIvas.filter(r=>(parseFloat(r.base)||0)>0||(parseFloat(r.monto)||0)>0)
      .map(r=>({tipo:'iva',alicuota:parseFloat(r.alicuota)||0,base:parseFloat(r.base)||0,monto:parseFloat(r.monto)||0})),
    ...frPerceps.filter(r=>(parseFloat(r.monto)||0)>0)
      .map(r=>({tipo:r.tipo,monto:parseFloat(r.monto)||0,jurisdiccion:r.tipo==='percepcion_iibb'?r.jurisdiccion:null})),
  ];
  const f={
    oc_id:_frCtx.ocId,proveedor_id:_frCtx.provId,nro,fecha,
    fecha_vto:document.getElementById('fr-fecha-vto').value||null,
    tipo,letra,neto:t.neto,iva:t.iva,total:totalTipeado,
    no_gravado:noGravado,exento,
    moneda:document.getElementById('fr-moneda').value,
    tipo_cambio:parseFloat(document.getElementById('fr-tc').value)||null,
    factura_asociada_id:facturaAsociada,cta_imputacion_id:ctaImputacion,
  };
  try{
    setBusy(btnId,true);
    await RPC('registrar_factura_recibida',{p_factura:f,p_impuestos:impuestos,p_override:override,p_motivo:motivo});
    await reload('facturas_recibidas','ordenes_compra','asientos','asiento_lineas');
    closeModal('modal-factura-recibida');renderAll();
    notify({factura:'Factura registrada',nota_credito:'Nota de crédito registrada',nota_debito:'Nota de débito registrada'}[tipo]);
  }catch(e){notify(e.message||'Error registrando el comprobante','err');}
  finally{setBusy(btnId,false);}
}
```

Nota: `_calcValorRecibidoOC` (existente) se conserva tal cual. El viejo `actualizarMatchPreview` y `_currentFacturaOcId` se eliminan (reemplazados por `frRecalc`/`_frCtx`).

- [ ] **Step 3: Run tests**

Run: `node --test tests/`
Expected: PASS completo — el harness carga index.html entero; si hay error de sintaxis JS la suite explota acá.

- [ ] **Step 4: Verificación visual**

Abrir la app local (`open index.html` o el flujo habitual de Netlify dev) y verificar: el modal abre desde el botón Factura de una OC, se agregan/quitan filas de IVA y percepciones, el total calculado se actualiza, el badge de aritmética aparece, el preview de match sigue funcionando.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: modal de comprobante de proveedor con desglose de IVA, percepciones y NC/ND"
```

---

### Task 4: Tab Facturas recibidas — botón sin OC, acciones NC/ND, columna tipo, stats

**Files:**
- Modify: `index.html` — tab `compras-tab-facturas` (~línea 542-548) y `renderFacturasRecibidas` (~línea 9885)

**Interfaces:**
- Consumes: `openFacturaSinOCModal()`, `openNCNDModal(id)` (Task 3); campos `tipo/letra` en `facturasRecibidas` (Task 2).

- [ ] **Step 1: HTML del tab**

Reemplazar el toolbar y la tabla del tab por:

```html
        <div id="compras-tab-facturas" style="display:none">
          <div class="stats-bar" id="fr-stats"></div>
          <div class="toolbar">
            <div class="search-box"><input type="text" placeholder="Buscar por nro, proveedor..." oninput="renderFacturasRecibidas(this.value)"></div>
            <button class="btn btn-primary btn-sm" onclick="openFacturaSinOCModal()">+ Factura sin OC</button>
          </div>
          <div class="table-wrap"><table><thead><tr><th>Tipo</th><th>OC</th><th>Proveedor</th><th>Nro</th><th>Fecha</th><th>Vto.</th><th>Mon.</th><th>Neto</th><th>IVA</th><th>Total</th><th>Match</th><th>Asiento</th><th></th></tr></thead><tbody id="fr-tbody"></tbody></table></div>
        </div>
```

- [ ] **Step 2: Reescribir renderFacturasRecibidas**

```js
function renderFacturasRecibidas(filter=''){
  const f=(filter||'').toLowerCase();
  const signo=r=>(r.tipo==='nota_credito'?-1:1);
  const total=facturasRecibidas.length;
  const matchOk=facturasRecibidas.filter(r=>r.estado_match==='ok').length;
  const ncnd=facturasRecibidas.filter(r=>(r.tipo||'factura')!=='factura').length;
  const totalARS=facturasRecibidas.filter(r=>(r.moneda||'ARS')==='ARS').reduce((a,r)=>a+signo(r)*(parseFloat(r.total)||0),0);
  const totalUSD=facturasRecibidas.filter(r=>r.moneda==='USD').reduce((a,r)=>a+signo(r)*(parseFloat(r.total)||0),0);
  document.getElementById('fr-stats').innerHTML=`
    <div class="stat-card"><div class="stat-label">Comprobantes</div><div class="stat-value" style="color:var(--accent)">${total}</div></div>
    <div class="stat-card"><div class="stat-label">Match OK</div><div class="stat-value" style="color:var(--green)">${matchOk}</div></div>
    <div class="stat-card"><div class="stat-label">NC / ND</div><div class="stat-value" style="color:var(--coral)">${ncnd}</div></div>
    <div class="stat-card solo-costos"><div class="stat-label">Total ARS (neto NC)</div><div class="stat-value" style="color:var(--green)">${fmtARS(totalARS)}</div></div>
    <div class="stat-card solo-costos"><div class="stat-label">Total USD (neto NC)</div><div class="stat-value" style="color:var(--blue)">${fmtUSD(totalUSD)}</div></div>`;
  const matchBadges={ok:'badge-ok',override:'badge-warn',pendiente:'',discrepancia:'badge-coral'};
  const tipoBadge=r=>{
    const tp=r.tipo||'factura',l=r.letra||'A';
    if(tp==='nota_credito')return `<span class="badge badge-coral">NC-${esc(l)}</span>`;
    if(tp==='nota_debito')return `<span class="badge badge-warn">ND-${esc(l)}</span>`;
    return `<span class="badge badge-blue">FA-${esc(l)}</span>`;
  };
  const list=facturasRecibidas.filter(r=>{
    if(!f)return true;
    const oc=ordenesCompra.find(o=>o.id===r.oc_id);
    const prov=proveedores.find(p=>p.id===r.proveedor_id);
    return (oc?.nro||'').toLowerCase().includes(f)||(prov?.nombre||'').toLowerCase().includes(f)||(r.nro||'').toLowerCase().includes(f);
  });
  document.getElementById('fr-tbody').innerHTML=list.length?list.map(r=>{
    const oc=ordenesCompra.find(o=>o.id===r.oc_id);
    const prov=proveedores.find(p=>p.id===r.proveedor_id);
    const mon=r.moneda||'ARS';
    const fmt=mon==='USD'?fmtUSD:fmtARS;
    const s=signo(r);
    const estado=r.estado_match||'pendiente';
    const matchCell=r.oc_id&&(r.tipo||'factura')==='factura'
      ?`<span class="badge ${matchBadges[estado]||''}">${{ok:'MATCH OK',override:'OVERRIDE',pendiente:'PENDIENTE'}[estado]||esc(estado)}</span>`
      :`<span class="mono" style="font-size:11px;color:var(--text3)">${(r.tipo||'factura')==='factura'?'s/OC':'—'}</span>`;
    const rojo=s<0?'color:var(--coral)':'';
    return `<tr>
      <td>${tipoBadge(r)}</td>
      <td class="mono">${esc(oc?.nro||'—')}</td>
      <td style="font-weight:500">${esc(prov?.nombre||'—')}</td>
      <td class="mono">${esc(r.nro||'—')}</td>
      <td>${r.fecha||'—'}</td>
      <td style="color:var(--text3)">${r.fecha_vto||'—'}</td>
      <td><span class="badge ${mon==='USD'?'badge-blue':'badge-teal'}">${esc(mon)}</span></td>
      <td class="mono" style="text-align:right;${rojo}">${fmt(s*parseFloat(r.neto||0))}</td>
      <td class="mono" style="text-align:right;${rojo}">${fmt(s*parseFloat(r.iva||0))}</td>
      <td class="mono" style="text-align:right;font-weight:600;${rojo}">${fmt(s*parseFloat(r.total||0))}</td>
      <td>${matchCell}</td>
      <td class="mono" style="font-size:11px;color:var(--text3)">${r.asiento_id?esc(r.asiento_id):'—'}</td>
      <td>${(r.tipo||'factura')==='factura'?`<button class="btn btn-ghost btn-sm" onclick="openNCNDModal('${r.id}')">NC/ND</button>`:''}</td>
    </tr>`;
  }).join(''):'<tr><td colspan="13" class="empty-cell"><div class="empty-state"><div class="empty-icon"><svg viewBox="0 0 24 24"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg></div><div class="empty-title">Sin comprobantes</div><div class="empty-msg">Registrá facturas con el botón <b>Factura</b> de una OC recibida, o <b>+ Factura sin OC</b> para gastos.</div></div></td></tr>';
}
```

- [ ] **Step 3: Run tests + verificación visual**

Run: `node --test tests/` → PASS.
Visual: tab muestra columna Tipo, botón "+ Factura sin OC" abre el modal en modo gastos, botón NC/ND por fila abre el modal pre-vinculado.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: tab de comprobantes — factura sin OC, NC/ND por fila, columna tipo y totales netos"
```

---

### Task 5: Condición fiscal del proveedor

**Files:**
- Modify: `index.html` — modal proveedor (~línea 1771), `openProveedorModal` (~línea 9487) y `saveProveedor` (~línea 9507)

**Interfaces:**
- Produces: campo `condicion_fiscal` en cada objeto de `proveedores` (consumido por `sugerirLetra` en el modal de factura, ya cableado en Task 3).

- [ ] **Step 1: Agregar el select al modal**

En el modal proveedor, reemplazar la fila Nombre/CUIT por:

```html
      <div class="form-row" style="grid-template-columns:2fr 1fr 1fr"><div class="form-group"><label>Nombre / Razón social *</label><input type="text" id="prov-nombre" placeholder="Aceros XYZ SA"></div><div class="form-group"><label>CUIT</label><input type="text" id="prov-cuit" placeholder="30-12345678-9"></div><div class="form-group"><label>Condición fiscal</label><select id="prov-cond-fiscal"><option value="RI">Resp. Inscripto</option><option value="monotributo">Monotributo</option><option value="exento">Exento</option><option value="consumidor_final">Cons. final</option></select></div></div>
```

- [ ] **Step 2: Cablear open/save**

En `openProveedorModal`, después de la línea de `prov-cuit`, agregar:

```js
  document.getElementById('prov-cond-fiscal').value=p?.condicion_fiscal||'RI';
```

En `saveProveedor`, dentro del objeto `data`, agregar:

```js
    condicion_fiscal:document.getElementById('prov-cond-fiscal').value,
```

- [ ] **Step 3: Run tests + verificación**

Run: `node --test tests/` → PASS. Visual: crear/editar proveedor persiste la condición; al abrir factura de un monotributista la letra sugerida es C y la sección IVA se oculta.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: condición fiscal del proveedor + letra sugerida en el modal de factura"
```

---

### Task 6: Alertas — vencimientos de facturas sin OC

**Files:**
- Modify: `index.html` — bloque de alertas de facturas (~línea 4073-4082)

**Interfaces:**
- Consumes: `facturasRecibidas` con `oc_id`, `fecha_vto`, `tipo` (Task 2).

- [ ] **Step 1: Extender las alertas**

Reemplazar el bloque "Facturas de proveedor vencidas / por vencer" por (une OC.factura_vto + facturas sin OC):

```js
  // Facturas de proveedor vencidas / por vencer (7 días).
  // Dos fuentes: OC.factura_vto (facturas con OC, legacy) y
  // facturas_recibidas sin OC (gastos) — las NC no vencen.
  const en7dF=hoyLocal(7);
  const vencibles=[
    ...ordenesCompra.filter(o=>o.factura_vto&&o.estado!=='anulada').map(o=>({ref:o.nro||'',vto:o.factura_vto})),
    ...facturasRecibidas.filter(r=>!r.oc_id&&r.fecha_vto&&(r.tipo||'factura')!=='nota_credito').map(r=>({ref:(r.nro||'')+' (s/OC)',vto:r.fecha_vto})),
  ];
  const factVencidas=vencibles.filter(x=>x.vto<hoy);
  if(factVencidas.length)out.push({sev:'crit',page:'compras',count:factVencidas.length,
    titulo:uno(factVencidas.length,'Factura de proveedor vencida','Facturas de proveedor vencidas'),
    detalle:factVencidas.slice(0,3).map(x=>esc(x.ref+' (vto '+x.vto+')')).join('  —  ')+masDe(factVencidas)});
  const factPorVencer=vencibles.filter(x=>x.vto>=hoy&&x.vto<=en7dF);
  if(factPorVencer.length)out.push({sev:'warn',page:'compras',count:factPorVencer.length,
    titulo:uno(factPorVencer.length,'Factura de proveedor vence en 7 días','Facturas de proveedor vencen en 7 días'),
    detalle:factPorVencer.slice(0,3).map(x=>esc(x.ref+' (vto '+x.vto+')')).join('  —  ')+masDe(factPorVencer)});
```

- [ ] **Step 2: Run tests + commit**

Run: `node --test tests/` → PASS.

```bash
git add index.html
git commit -m "feat: alertas de vencimiento incluyen facturas sin OC"
```

---

### Task 7: Exportables — Libro IVA Compras real + subdiario con signo

**Files:**
- Modify: `index.html` — `expIvaCompras` (~línea 2469) y `expSubdiarioCompras` (~línea 2459)

**Interfaces:**
- Consumes: tabla `factura_recibida_impuestos` (Task 2), campos `tipo/letra/no_gravado/exento`.

- [ ] **Step 1: Reescribir expIvaCompras**

```js
async function expIvaCompras(desde,hasta){
  const [fr,provs]=await Promise.all([
    GET('facturas_recibidas',`?fecha=gte.${desde}&fecha=lte.${hasta}&order=fecha,nro&select=id,fecha,nro,tipo,letra,proveedor_id,neto,iva,total,no_gravado,exento`),
    GET('proveedores','?select=id,nombre,cuit'),
  ]);
  const ids=fr.map(f=>f.id);
  let imps=[];
  for(let i=0;i<ids.length;i+=80)
    imps=imps.concat(await GET('factura_recibida_impuestos',`?factura_id=in.(${ids.slice(i,i+80).join(',')})&select=factura_id,tipo,alicuota,base,monto,jurisdiccion`));
  const impsPorFactura={};imps.forEach(i=>{(impsPorFactura[i.factura_id]=impsPorFactura[i.factura_id]||[]).push(i);});
  const filas=[['Fecha','Tipo','Nro','Proveedor','CUIT',
    'Neto 10,5','IVA 10,5','Neto 21','IVA 21','Neto 27','IVA 27','Neto otras','IVA otras',
    'Neto s/desglose','IVA s/desglose','No gravado','Exento',
    'Percep IVA','Percep IIBB','Jurisd. IIBB','Percep Gcias','Otros imp','Total']];
  const tot=new Array(18).fill(0); // acumuladores de las 18 columnas numéricas
  const tipoLbl={factura:'FA',nota_credito:'NC',nota_debito:'ND'};
  for(const f of fr){
    const p=provs.find(x=>x.id===f.proveedor_id)||{};
    const s=f.tipo==='nota_credito'?-1:1;
    const rows=impsPorFactura[f.id]||[];
    const ivaRows=rows.filter(r=>r.tipo==='iva');
    const bucket=(ali)=>ivaRows.filter(r=>Math.abs((parseFloat(r.alicuota)||0)-ali)<0.01);
    const sum=(arr,k)=>arr.reduce((a,r)=>a+(parseFloat(r[k])||0),0);
    const b105=bucket(10.5),b21=bucket(21),b27=bucket(27);
    const otras=ivaRows.filter(r=>![10.5,21,27].some(a=>Math.abs((parseFloat(r.alicuota)||0)-a)<0.01));
    const sinDesglose=ivaRows.length===0&&(parseFloat(f.iva)||0)>0;
    const percep=t=>sum(rows.filter(r=>r.tipo===t),'monto');
    const jur=[...new Set(rows.filter(r=>r.tipo==='percepcion_iibb'&&r.jurisdiccion).map(r=>r.jurisdiccion))].join(' / ');
    const nums=[
      s*sum(b105,'base'),s*sum(b105,'monto'),s*sum(b21,'base'),s*sum(b21,'monto'),
      s*sum(b27,'base'),s*sum(b27,'monto'),s*sum(otras,'base'),s*sum(otras,'monto'),
      s*(sinDesglose?parseFloat(f.neto)||0:0),s*(sinDesglose?parseFloat(f.iva)||0:0),
      s*(parseFloat(f.no_gravado)||0),s*(parseFloat(f.exento)||0),
      s*percep('percepcion_iva'),s*percep('percepcion_iibb'),0,
      s*percep('percepcion_ganancias'),s*percep('otros'),s*(parseFloat(f.total)||0),
    ];
    nums.forEach((n,i)=>tot[i]+=n);
    filas.push([csvFecha(f.fecha),`${tipoLbl[f.tipo||'factura']}-${f.letra||'A'}`,f.nro,p.nombre||'',p.cuit||'',
      ...nums.map((n,i)=>i===14?jur:csvNum(n))]);
  }
  filas.push(['','','','TOTALES','',...tot.map((n,i)=>i===14?'':csvNum(n))]);
  return {nombre:`iva_compras_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`IVA compras: ${fr.length} comprobantes · total ${csvNum(tot[17])}`};
}
```

Nota: la posición 14 de `nums` es la columna de texto "Jurisd. IIBB" (queda en 0 en los acumuladores y se imprime como texto). Verificar contra `csvArmar/csvNum/csvFecha` existentes (mismos helpers que la versión anterior).

- [ ] **Step 2: Actualizar expSubdiarioCompras**

Agregar columna Tipo y signo NC. Localizar la función y ajustar: en el array de cabecera agregar `'Tipo'` después de `'Fecha'`; en cada fila insertar `` `${tipoLbl[f.tipo||'factura']}-${f.letra||'A'}` `` (definir `const tipoLbl={factura:'FA',nota_credito:'NC',nota_debito:'ND'};` dentro de la función), y multiplicar neto/iva/total por `s=f.tipo==='nota_credito'?-1:1`. El `select` del GET debe sumar `tipo,letra,no_gravado,exento`.

- [ ] **Step 3: Run tests**

Run: `node --test tests/` → PASS (en particular `contador-export.test.js` — si valida columnas del CSV de compras, actualizar sus expectativas al formato nuevo en el MISMO commit).

- [ ] **Step 4: Commit**

```bash
git add index.html tests/
git commit -m "feat: libro IVA compras con desglose por alícuota, percepciones y signo NC"
```

---

### Task 8: Documentación (manual + CLAUDE.md) y cierre

**Files:**
- Modify: `docs/MANUAL_USUARIO.md` (sección Compras), regenerar `docs/MANUAL_USUARIO.docx`
- Modify: `CLAUDE.md` (si documenta el circuito de compras/facturas)

- [ ] **Step 1: Actualizar el manual**

En la sección de Compras del manual, agregar (adaptar el estilo del documento):

```markdown
### Comprobantes de proveedor: IVA, percepciones y notas de crédito

Al registrar una factura elegís **tipo** (Factura / Nota de débito / Nota de
crédito) y **letra** (A/B/C/M/X). La letra se sugiere sola según la condición
fiscal del proveedor (Resp. Inscripto → A, Monotributo → C).

- **IVA por alícuota**: cargá una fila por alícuota (10,5% / 21% / 27%...).
  El IVA se calcula solo desde la base; podés corregirlo por redondeos.
  Las facturas B y C no discriminan IVA (no es crédito computable).
- **No gravado / Exento**: campos aparte, salen en el Libro IVA.
- **Percepciones**: IVA, IIBB (con jurisdicción) y Ganancias. Se contabilizan
  como crédito en sus cuentas (113007 / 113010 / 113011).
- **El total tiene que cerrar**: el sistema no deja guardar si la suma de
  componentes no coincide con el total del comprobante.
- **Factura sin OC** (botón en el tab Facturas): para gastos sin orden de
  compra — elegís la cuenta contable de imputación.
- **NC/ND**: desde la fila de cualquier factura. La NC reduce la deuda y el
  crédito de IVA, y sale en negativo en el libro. No mueve stock.
```

Regenerar el docx: `pandoc docs/MANUAL_USUARIO.md -o docs/MANUAL_USUARIO.docx`

- [ ] **Step 2: CLAUDE.md**

Si `CLAUDE.md` describe el circuito de compras/3-way match, agregar dos líneas: RPC v2 con `p_impuestos`, tabla `factura_recibida_impuestos`, y la regla "montos positivos, el signo lo da `tipo`".

- [ ] **Step 3: Suite completa + commit final**

Run: `node --test tests/`
Expected: PASS completo.

```bash
git add docs/ CLAUDE.md
git commit -m "docs: manual y CLAUDE.md — comprobantes de proveedor con desglose fiscal"
```

- [ ] **Step 4: Deploy checklist (manual, lo hace Giuliano)**

1. Correr `migrations/054_compras_fiscal.sql` en el SQL Editor de Supabase (prod).
2. Correr las queries de VERIFICACIÓN del final del archivo.
3. Push a main → Netlify despliega el frontend.
4. Smoke test en prod: criterios de aceptación 1-6 del spec.
```

## Self-Review

- **Spec coverage:** alícuotas múltiples (T1-T3), percepciones + cuentas (T2-T3), tipo/letra (T2-T4), NC/ND (T2-T4), sin OC (T2-T4), condición fiscal (T2, T5), exportables (T7), alertas (T6), backfill (T2), criterios de aceptación (T8 deploy checklist). ✓
- **Placeholders:** ninguno — todo el código está inline. ✓
- **Type consistency:** `computeTotalesFactura/validarDesgloseFactura/sugerirLetra/letraDiscriminaIva` (T1) usados con las mismas firmas en T3; RPC v2 firma `(p_factura, p_impuestos, p_override, p_motivo)` idéntica en T2 y T3; `openFacturaSinOCModal/openNCNDModal` (T3) referenciados en T4. ✓
