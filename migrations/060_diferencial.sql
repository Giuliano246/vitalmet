-- ═══════════════════════════════════════════════════════════════════
-- 060_diferencial.sql — Sprint 6 (último) de la auditoría 2026-07-30
--
--   Planos vinculados a la pieza: tabla `planos` con el archivo
--   (PDF/imagen en base64, patrón certificados). El vínculo con las
--   OPs es por `codigo_plano` (texto que ya existe en la OP). El
--   usuario de PLANTA los puede VER (visor en planta.html — es el
--   core del negocio "repuestos a plano") pero no modificar.
--
--   El resto del sprint (dashboard temporal + cash-flow proyectado)
--   es frontend puro: no toca la base.
--
-- Requiere: 052/053 (es_planta/es_contador, fn_contador_guard).
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.planos (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid        NOT NULL,
  codigo      text        NOT NULL,       -- el mismo codigo_plano de las OPs
  revision    text,                       -- rev vigente (el historial queda en audit_log)
  descripcion text,
  cliente     text,
  file_name   text,
  file_data   text,                       -- data-URL base64 (PDF o imagen), descarga on-demand
  updated_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_planos_codigo
  ON public.planos (empresa_id, codigo);

ALTER TABLE public.planos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.planos;
CREATE POLICY tenant_isolation ON public.planos
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Planta VE los planos (sin lockdown de SELECT) pero no los toca:
DROP POLICY IF EXISTS planta_no_ins ON public.planos;
CREATE POLICY planta_no_ins ON public.planos
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS planta_no_upd ON public.planos;
CREATE POLICY planta_no_upd ON public.planos
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (NOT public.es_planta());
DROP POLICY IF EXISTS planta_no_del ON public.planos;
CREATE POLICY planta_no_del ON public.planos
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING (NOT public.es_planta());

-- Contador/auditor: solo lectura (batería estándar)
DROP POLICY IF EXISTS contador_no_ins ON public.planos;
CREATE POLICY contador_no_ins ON public.planos
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_upd ON public.planos;
CREATE POLICY contador_no_upd ON public.planos
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_del ON public.planos;
CREATE POLICY contador_no_del ON public.planos
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP TRIGGER IF EXISTS contador_guard ON public.planos;
CREATE TRIGGER contador_guard
  BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.planos
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard();

-- Un plano es un documento controlado: cada cambio queda auditado
DROP TRIGGER IF EXISTS trg_audit ON public.planos;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.planos
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT count(*) FROM pg_policies WHERE tablename='planos';  -- 7
-- SELECT indexname FROM pg_indexes WHERE tablename='planos';
