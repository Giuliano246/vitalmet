-- ═══════════════════════════════════════════════════════════════════
-- 056_ciclo_dinero.sql — Sprint 2 de la auditoría 2026-07-30
--
--   1. Retenciones sufridas en cobranzas: tabla retenciones_sufridas
--      (certificados de retención que aplican los clientes al pagar:
--      Ganancias / IIBB / SUSS / IVA) + cuentas default en config.
--      Las cuentas YA existen en el plan real de Vitalmet:
--      113018 RETENCIONES GANACIAS · 113006 RETENCIONES I. BRUTOS ·
--      113019 RETENCIONES SUSS · 113005 RETENCIONES IVA.
--   2. Cheques contabilizados: cuentas default para cartera (111006
--      CHEQUES DIFERIDOS activo) y emitidos (212003 CHEQUES DIFERIDOS
--      pasivo). Los asientos los genera el frontend por evento
--      (cobro/pago con cheque, depósito, débito, rechazo) vía
--      crear_asiento con origen_tipo 'cheque-*' + origen_id.
--   3. Costo real de OP: columnas costo_real_usd (por unidad) y
--      costeado_at en ordenes_produccion. Se persisten al completar
--      la OP (el PT queda valuado al costo real, no al precio tipeado).
--
-- Requiere: 023 (crear_asiento, fn_audit), 052/053 (es_planta,
-- es_contador, fn_contador_guard), 027 (cheques).
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Retenciones sufridas ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.retenciones_sufridas (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  cliente_id      uuid        REFERENCES public.clientes(id) ON DELETE SET NULL,
  fecha           date        NOT NULL,
  tipo            text        NOT NULL CHECK (tipo IN ('ganancias','iibb','suss','iva')),
  certificado_nro text,
  jurisdiccion    text,             -- solo 'iibb'
  monto           numeric     NOT NULL CHECK (monto > 0),
  moneda          text        NOT NULL DEFAULT 'ARS',
  tipo_cambio     numeric,
  asiento_id      uuid        REFERENCES public.asientos(id) ON DELETE SET NULL,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.retenciones_sufridas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.retenciones_sufridas;
CREATE POLICY tenant_isolation ON public.retenciones_sufridas
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Lockdowns estándar para tablas nuevas (regla CLAUDE.md, molde 052/053)
DROP POLICY IF EXISTS planta_lockdown ON public.retenciones_sufridas;
CREATE POLICY planta_lockdown ON public.retenciones_sufridas
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS contador_no_ins ON public.retenciones_sufridas;
CREATE POLICY contador_no_ins ON public.retenciones_sufridas
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_upd ON public.retenciones_sufridas;
CREATE POLICY contador_no_upd ON public.retenciones_sufridas
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_del ON public.retenciones_sufridas;
CREATE POLICY contador_no_del ON public.retenciones_sufridas
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP TRIGGER IF EXISTS contador_guard ON public.retenciones_sufridas;
CREATE TRIGGER contador_guard
  BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.retenciones_sufridas
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard();

DROP TRIGGER IF EXISTS trg_audit ON public.retenciones_sufridas;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.retenciones_sufridas
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

CREATE INDEX IF NOT EXISTS idx_retenciones_empresa_fecha
  ON public.retenciones_sufridas (empresa_id, fecha);

-- ─── 2. Config: cuentas de retenciones y cheques ────────────────────

ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_ret_ganancias    uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_ret_iibb         uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_ret_suss         uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_ret_iva          uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_cheques_cartera  uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_cheques_emitidos uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

-- Defaults desde el plan real (si el código no existe, queda NULL y se
-- elige a mano en Configuración → Imputación contable)
UPDATE public.config_contable c SET cta_ret_ganancias = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113018')
  WHERE cta_ret_ganancias IS NULL;
UPDATE public.config_contable c SET cta_ret_iibb = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113006')
  WHERE cta_ret_iibb IS NULL;
UPDATE public.config_contable c SET cta_ret_suss = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113019')
  WHERE cta_ret_suss IS NULL;
UPDATE public.config_contable c SET cta_ret_iva = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='113005')
  WHERE cta_ret_iva IS NULL;
UPDATE public.config_contable c SET cta_cheques_cartera = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='111006')
  WHERE cta_cheques_cartera IS NULL;
UPDATE public.config_contable c SET cta_cheques_emitidos = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='212003')
  WHERE cta_cheques_emitidos IS NULL;

-- ─── 3. Costo real de OP ────────────────────────────────────────────

ALTER TABLE public.ordenes_produccion
  ADD COLUMN IF NOT EXISTS costo_real_usd numeric,   -- por unidad, al cierre
  ADD COLUMN IF NOT EXISTS costeado_at    timestamptz;

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT count(*) FROM pg_policies WHERE tablename='retenciones_sufridas'; -- 5
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='config_contable' AND column_name LIKE 'cta_ret%';
-- SELECT cta_ret_ganancias IS NOT NULL AS ret_ok, cta_cheques_cartera IS NOT NULL AS chq_ok
--   FROM config_contable;
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='ordenes_produccion' AND column_name='costo_real_usd';
