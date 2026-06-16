-- ═══════════════════════════════════════════════════════════════════
-- 033_gr_ir_3way_match.sql
-- 3-way match GR/IR (OC ↔ Remito ↔ Factura).
--
-- El asiento de recepción (GR, generado en el frontend) acredita la
-- cuenta puente "FACTURAS A RECIBIR (GR/IR)".  Cuando llega la
-- factura del proveedor, esta migración registra el asiento de
-- invoice-receipt (IR): Debe GR/IR (neto) + Debe IVA CF | Haber
-- Proveedores (total), y valida la tolerancia del match.
--
-- Qué agrega:
--   1. Cuenta puente pasivo 211009 "FACTURAS A RECIBIR (GR/IR)".
--   2. Columnas en config_contable: cta_gr_ir, match_tolerancia_pct,
--      match_tolerancia_monto.
--   3. Tabla facturas_recibidas con RLS + audit trigger.
--   4. RPC registrar_factura_recibida(): 3-way match + asiento IR.
--
-- Requiere: 006 (current_empresa_id), 012 (config_contable),
--           023 (crear_asiento, fn_audit), 024 (asientos.proveedor_id),
--           032 (current_usuario_es_admin).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Cuenta puente GR/IR (pasivo) ────────────────────────────────
-- Código 211009: libre en el plan de Vitalmet SA (el seed 007 tiene
-- 211002 = PROVEEDORES y salta directo a 212002; 211009 no está usado).
-- No existe UNIQUE constraint en la DB sobre (empresa_id, codigo), por
-- lo que usamos el patrón NOT EXISTS igual que el resto del proyecto.
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.cuentas_contables
    WHERE empresa_id = emp_id AND codigo = '211009'
  ) THEN
    INSERT INTO public.cuentas_contables
      (empresa_id, codigo, nombre, tipo, imputable, activa)
    VALUES
      (emp_id, '211009', 'FACTURAS A RECIBIR (GR/IR)', 'pasivo', true, true);
    RAISE NOTICE 'Migration 033: cuenta 211009 FACTURAS A RECIBIR (GR/IR) creada';
  ELSE
    RAISE NOTICE 'Migration 033: cuenta 211009 ya existía, sin cambios';
  END IF;
END $$;

-- ─── 2. Config: cuenta GR/IR + tolerancias de match ─────────────────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_gr_ir               uuid
    REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS match_tolerancia_pct    numeric NOT NULL DEFAULT 0.02,
  ADD COLUMN IF NOT EXISTS match_tolerancia_monto  numeric NOT NULL DEFAULT 5000;

-- Apuntar cta_gr_ir a la cuenta 211009 recién creada (para todas las
-- empresas que aún no tengan el campo seteado).
UPDATE public.config_contable c
SET cta_gr_ir = (
  SELECT id FROM public.cuentas_contables
  WHERE empresa_id = c.empresa_id AND codigo = '211009'
)
WHERE cta_gr_ir IS NULL;

-- ─── 3. Tabla facturas_recibidas ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.facturas_recibidas (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  proveedor_id    uuid        REFERENCES public.proveedores(id) ON DELETE SET NULL,
  oc_id           uuid        REFERENCES public.ordenes_compra(id) ON DELETE SET NULL,
  nro             text        NOT NULL,
  fecha           date        NOT NULL,
  fecha_vto       date,
  neto            numeric     NOT NULL,
  iva             numeric     NOT NULL DEFAULT 0,
  total           numeric     NOT NULL,
  moneda          text        NOT NULL DEFAULT 'USD',
  tipo_cambio     numeric     NOT NULL DEFAULT 1,
  estado_match    text        NOT NULL DEFAULT 'pendiente'
                              CHECK (estado_match IN ('pendiente','ok','override')),
  asiento_id      uuid,
  override_por    uuid,
  override_motivo text,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- RLS: tenant isolation (patrón estándar optimizado de mig 020/022).
ALTER TABLE public.facturas_recibidas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.facturas_recibidas;
CREATE POLICY tenant_isolation ON public.facturas_recibidas
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Audit trail (fn_audit definida en migración 023).
DROP TRIGGER IF EXISTS trg_audit ON public.facturas_recibidas;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.facturas_recibidas
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- Índices de performance.
CREATE INDEX IF NOT EXISTS idx_facturas_recibidas_empresa
  ON public.facturas_recibidas (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_facturas_recibidas_oc
  ON public.facturas_recibidas (oc_id)
  WHERE oc_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_facturas_recibidas_proveedor
  ON public.facturas_recibidas (proveedor_id)
  WHERE proveedor_id IS NOT NULL;

-- ─── 4. RPC registrar_factura_recibida ───────────────────────────────
-- Hace el 3-way match (OC ↔ remito/recepción ↔ factura), crea el
-- asiento IR y registra la factura en facturas_recibidas, todo atómico.
--
-- Parámetros:
--   p_factura   jsonb    — campos de la factura:
--                          { proveedor_id, oc_id, nro, fecha, fecha_vto,
--                            neto, iva, total, moneda, tipo_cambio }
--   p_override  boolean  — true = forzar aun cuando la dif > umbral
--                          (solo admin puede usarlo)
--   p_motivo    text     — motivo obligatorio cuando p_override = true
--
-- Lógica del match:
--   valor_recibido = Σ (precio_unitario * cantidad_recibida) en oc_items
--   dif    = |neto_factura − valor_recibido|
--   umbral = LEAST(valor_recibido * pct, monto_fijo)
--   si dif ≤ umbral → estado 'ok'
--   si dif > umbral y p_override y es_admin → estado 'override'
--   si dif > umbral y (¬p_override o ¬es_admin) → RAISE EXCEPTION
--
-- Asiento IR generado (cabecera estado='confirmado'):
--   DEBE  211009 GR/IR         neto   (cancela la cuenta puente del GR)
--   DEBE  IVA Crédito Fiscal   iva    (solo si iva > 0)
--   HABER Proveedores          total  (nacimiento de la deuda real)
--
-- Devuelve jsonb con id, estado_match, asiento_id, dif, umbral,
-- valor_recibido.
CREATE OR REPLACE FUNCTION public.registrar_factura_recibida(
  p_factura  jsonb,
  p_override boolean DEFAULT false,
  p_motivo   text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_empresa        uuid    := public.current_empresa_id();
  v_cfg            public.config_contable%ROWTYPE;
  v_oc_id          uuid    := NULLIF(p_factura->>'oc_id', '')::uuid;
  v_neto           numeric := (p_factura->>'neto')::numeric;
  v_iva            numeric := COALESCE((p_factura->>'iva')::numeric, 0);
  v_total          numeric := (p_factura->>'total')::numeric;
  v_valor_recibido numeric;
  v_dif            numeric;
  v_umbral         numeric;
  v_es_admin       boolean := public.current_usuario_es_admin();
  v_estado         text;
  v_fact_id        uuid;
  v_asiento        jsonb;
  v_oc_nro         text;
  v_prov           text;
BEGIN
  -- Validaciones básicas de entrada
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'Sin empresa asignada';
  END IF;
  IF COALESCE(p_factura->>'nro', '') = '' THEN
    RAISE EXCEPTION 'Falta el número de factura';
  END IF;
  IF COALESCE(p_factura->>'fecha', '') = '' THEN
    RAISE EXCEPTION 'Falta la fecha de la factura';
  END IF;
  IF v_neto IS NULL OR v_neto <= 0 THEN
    RAISE EXCEPTION 'El neto debe ser mayor a cero';
  END IF;
  IF v_total IS NULL OR v_total <= 0 THEN
    RAISE EXCEPTION 'El total debe ser mayor a cero';
  END IF;

  -- Cargar config contable de la empresa
  SELECT * INTO v_cfg
  FROM public.config_contable
  WHERE empresa_id = v_empresa;

  IF v_cfg.cta_gr_ir IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: falta cta_gr_ir (211009). Verificar mig 033.';
  END IF;
  IF v_cfg.cta_iva_credito IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: falta cta_iva_credito.';
  END IF;
  IF v_cfg.cta_proveedores IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: falta cta_proveedores.';
  END IF;

  -- ── 3-way match ──────────────────────────────────────────────────
  -- Valor recibido NETO (sin IVA), en la MISMA base que el crédito GR/IR
  -- del asiento de recepción (frontend generarAsientoCompra): si los
  -- precios de la OC incluyen IVA, se descuenta para comparar contra el
  -- neto de la factura. Así GR/IR netea a cero cuando recepción = factura.
  SELECT COALESCE(SUM(precio_unitario * cantidad_recibida), 0)
    INTO v_valor_recibido
    FROM public.oc_items
   WHERE oc_id = v_oc_id;
  IF COALESCE(v_cfg.precios_incluyen_iva, false) THEN
    v_valor_recibido := v_valor_recibido / (1 + COALESCE(v_cfg.iva_alicuota, 0));
  END IF;

  v_dif    := abs(v_neto - v_valor_recibido);
  v_umbral := LEAST(
    v_valor_recibido * v_cfg.match_tolerancia_pct,
    v_cfg.match_tolerancia_monto
  );

  IF v_dif <= v_umbral THEN
    v_estado := 'ok';
  ELSIF p_override AND v_es_admin THEN
    v_estado := 'override';
  ELSE
    RAISE EXCEPTION
      'Match fallido: neto factura % vs recibido % (dif %, umbral %). '
      'Requiere override de un administrador.',
      v_neto, v_valor_recibido, v_dif, v_umbral;
  END IF;

  -- Datos descriptivos para el asiento
  SELECT nro    INTO v_oc_nro FROM public.ordenes_compra WHERE id = v_oc_id;
  SELECT nombre INTO v_prov   FROM public.proveedores     WHERE id = NULLIF(p_factura->>'proveedor_id', '')::uuid;

  -- ── Asiento IR ───────────────────────────────────────────────────
  -- Debe GR/IR (neto) + Debe IVA CF (si iva > 0) | Haber Proveedores (total)
  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha',          p_factura->>'fecha',
      'descripcion',    format(
        'Factura proveedor %s s/OC %s — %s',
        p_factura->>'nro',
        COALESCE(v_oc_nro, '?'),
        COALESCE(v_prov,   '?')
      ),
      'comprobante_nro', p_factura->>'nro',
      'tipo',            'auto-factura-compra',
      'origen_tipo',     'factura_recibida',
      'estado',          'confirmado',
      'moneda',          COALESCE(NULLIF(p_factura->>'moneda', ''), 'USD'),
      'tipo_cambio',     COALESCE((p_factura->>'tipo_cambio')::numeric, 1),
      'proveedor_id',    p_factura->>'proveedor_id'
    ),
    (
      -- Construir el array de líneas dinámicamente para omitir la
      -- línea de IVA cuando iva = 0 (evitar línea con debe=0).
      SELECT jsonb_agg(l ORDER BY ord)
      FROM (
        SELECT
          jsonb_build_object(
            'cuenta_id',   v_cfg.cta_gr_ir,
            'debe',        v_neto,
            'haber',       0,
            'descripcion', 'Cancela Facturas a recibir (GR/IR)',
            'orden',       0
          ) AS l,
          0 AS ord
        UNION ALL
        SELECT
          jsonb_build_object(
            'cuenta_id',   v_cfg.cta_iva_credito,
            'debe',        v_iva,
            'haber',       0,
            'descripcion', 'IVA Crédito Fiscal',
            'orden',       1
          ),
          1
        WHERE v_iva > 0
        UNION ALL
        SELECT
          jsonb_build_object(
            'cuenta_id',   v_cfg.cta_proveedores,
            'debe',        0,
            'haber',       v_total,
            'descripcion', COALESCE(v_prov, 'Proveedor'),
            'orden',       2
          ),
          2
      ) sub(l, ord)
    ),
    NULL  -- p_asiento_id = NULL → crear nuevo asiento
  );

  -- ── Insertar la factura recibida ──────────────────────────────────
  INSERT INTO public.facturas_recibidas (
    empresa_id, proveedor_id, oc_id, nro, fecha, fecha_vto,
    neto, iva, total, moneda, tipo_cambio,
    estado_match, asiento_id,
    override_por, override_motivo,
    created_by
  ) VALUES (
    v_empresa,
    NULLIF(p_factura->>'proveedor_id', '')::uuid,
    v_oc_id,
    p_factura->>'nro',
    (p_factura->>'fecha')::date,
    NULLIF(p_factura->>'fecha_vto', '')::date,
    v_neto, v_iva, v_total,
    COALESCE(NULLIF(p_factura->>'moneda', ''), 'USD'),
    COALESCE((p_factura->>'tipo_cambio')::numeric, 1),
    v_estado,
    (v_asiento->>'id')::uuid,
    CASE WHEN v_estado = 'override' THEN auth.uid() ELSE NULL END,
    CASE WHEN v_estado = 'override' THEN p_motivo  ELSE NULL END,
    auth.uid()
  )
  RETURNING id INTO v_fact_id;

  RETURN jsonb_build_object(
    'id',              v_fact_id,
    'estado_match',    v_estado,
    'asiento_id',      v_asiento->>'id',
    'dif',             v_dif,
    'umbral',          v_umbral,
    'valor_recibido',  v_valor_recibido
  );
END $$;

-- Revocar a anon (Supabase otorga EXECUTE a anon por DEFAULT PRIVILEGES).
REVOKE EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, boolean, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, boolean, text) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, línea a línea, en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════

-- 1) Cuenta GR/IR creada:
-- SELECT codigo, nombre, tipo, imputable, activa
--   FROM public.cuentas_contables
--  WHERE codigo = '211009';
-- Esperado: 1 fila con nombre 'FACTURAS A RECIBIR (GR/IR)', tipo 'pasivo'.

-- 2) Config contable con los nuevos campos:
-- SELECT cta_gr_ir, match_tolerancia_pct, match_tolerancia_monto
--   FROM public.config_contable;
-- Esperado: cta_gr_ir NOT NULL (apunta a 211009), pct=0.02, monto=5000.

-- 3) Tabla creada con RLS y trigger de audit:
-- SELECT tablename, rowsecurity FROM pg_tables
--  WHERE schemaname = 'public' AND tablename = 'facturas_recibidas';
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname = 'trg_audit' AND tgrelid = 'public.facturas_recibidas'::regclass;

-- 4) RPC existe y no accesible a anon:
-- SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--  WHERE n.nspname='public' AND proname='registrar_factura_recibida';
-- SELECT has_function_privilege('anon',
--   'public.registrar_factura_recibida(jsonb,boolean,text)', 'EXECUTE');
-- Esperado: false.

-- 5) Smoke test con una OC real recibida (ajustar el oc_id):
-- SELECT public.registrar_factura_recibida(
--   '{"oc_id":"<UUID_OC_CON_RECEPCIONES>",
--     "proveedor_id":"<UUID_PROVEEDOR>",
--     "nro":"F-0001-00001234",
--     "fecha":"2026-06-16",
--     "neto":1000,
--     "iva":210,
--     "total":1210,
--     "moneda":"USD",
--     "tipo_cambio":1}'::jsonb,
--   false,   -- sin override
--   NULL     -- sin motivo
-- );
-- Esperado con neto=valor_recibido: {"estado_match":"ok","asiento_id":"...","dif":0,...}
-- Esperado con neto muy distinto y sin override: EXCEPTION 'Match fallido...'
