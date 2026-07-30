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
--           006 (current_empresa_id), 032 (current_usuario_es_admin),
--           052/053 (planta_lockdown + contador_guard para tablas nuevas).
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

-- Lockdowns estándar para tablas nuevas (regla CLAUDE.md, molde 052/053):
-- usuario planta no ve nada; contador en solo lectura.
DROP POLICY IF EXISTS planta_lockdown ON public.factura_recibida_impuestos;
CREATE POLICY planta_lockdown ON public.factura_recibida_impuestos
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS contador_no_ins ON public.factura_recibida_impuestos;
CREATE POLICY contador_no_ins ON public.factura_recibida_impuestos
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_upd ON public.factura_recibida_impuestos;
CREATE POLICY contador_no_upd ON public.factura_recibida_impuestos
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_del ON public.factura_recibida_impuestos;
CREATE POLICY contador_no_del ON public.factura_recibida_impuestos
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP TRIGGER IF EXISTS contador_guard ON public.factura_recibida_impuestos;
CREATE TRIGGER contador_guard
  BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.factura_recibida_impuestos
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard();

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
    RAISE NOTICE 'Migration 054: cuenta 113010 creada';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_contables WHERE empresa_id=emp_id AND codigo='113011') THEN
    INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa)
    VALUES (emp_id,'113011','PERCEPCIONES GANANCIAS SUFRIDAS','activo',true,true);
    RAISE NOTICE 'Migration 054: cuenta 113011 creada';
  END IF;
END $$;

ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_percep_iva       uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_percep_iibb      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_percep_ganancias uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

-- Defaults: 113007 PERCEPCION IVA ya existe en el seed 007; 113010/113011 recién creadas.
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
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
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
-- VERIFICACIÓN (correr después, línea a línea, en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════
-- 1) Cuentas de percepciones:
-- SELECT codigo, nombre FROM public.cuentas_contables
--  WHERE codigo IN ('113007','113010','113011') ORDER BY codigo;
-- Esperado: 3 filas.
--
-- 2) Config apuntando a las cuentas:
-- SELECT cta_percep_iva, cta_percep_iibb, cta_percep_ganancias
--   FROM public.config_contable;
-- Esperado: los 3 NOT NULL.
--
-- 3) Tabla nueva con RLS + lockdowns + audit:
-- SELECT polname FROM pg_policy
--  WHERE polrelid = 'public.factura_recibida_impuestos'::regclass ORDER BY polname;
-- Esperado: contador_no_del, contador_no_ins, contador_no_upd,
--           planta_lockdown, tenant_isolation.
--
-- 4) Backfill (facturas históricas 21%):
-- SELECT count(*) FROM public.factura_recibida_impuestos;
--
-- 5) Una sola versión del RPC (4 args):
-- SELECT proname, pronargs FROM pg_proc WHERE proname='registrar_factura_recibida';
-- Esperado: 1 fila con pronargs = 4.
