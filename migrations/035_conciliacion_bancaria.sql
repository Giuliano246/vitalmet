-- ═══════════════════════════════════════════════════════════════════
-- 035_conciliacion_bancaria.sql
-- Módulo de conciliación bancaria: cuentas bancarias + líneas de extracto.
--
-- Qué agrega:
--   1. Tabla cuentas_bancarias: maestro de cuentas bancarias de la empresa
--      (nombre, banco, CBU, moneda, cuenta contable vinculada).
--   2. Tabla extracto_bancario: líneas importadas del extracto/resumen
--      bancario, con estado de conciliación y vínculo opcional al asiento.
--
-- Requiere: 006 (current_empresa_id), 007 (cuentas_contables),
--           023 (fn_audit).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Tabla cuentas_bancarias ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cuentas_bancarias (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid        NOT NULL,
  nombre             text        NOT NULL,
  banco              text,
  nro_cuenta         text,
  cbu                text,
  moneda             text        NOT NULL DEFAULT 'ARS' CHECK (moneda IN ('ARS','USD')),
  cuenta_contable_id uuid        REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  activa             boolean     NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS: tenant isolation (patrón estándar optimizado de mig 020/022/033).
ALTER TABLE public.cuentas_bancarias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.cuentas_bancarias;
CREATE POLICY tenant_isolation ON public.cuentas_bancarias
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Audit trail (fn_audit definida en migración 023).
DROP TRIGGER IF EXISTS trg_audit ON public.cuentas_bancarias;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.cuentas_bancarias
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- ─── 2. Tabla extracto_bancario ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.extracto_bancario (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid        NOT NULL,
  cuenta_bancaria_id uuid        NOT NULL REFERENCES public.cuentas_bancarias(id) ON DELETE CASCADE,
  fecha              date        NOT NULL,
  descripcion        text,
  importe            numeric     NOT NULL,
  saldo              numeric,
  referencia         text,
  conciliado         boolean     NOT NULL DEFAULT false,
  asiento_linea_id   uuid,
  import_batch       text,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS: tenant isolation.
ALTER TABLE public.extracto_bancario ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.extracto_bancario;
CREATE POLICY tenant_isolation ON public.extracto_bancario
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Audit trail.
DROP TRIGGER IF EXISTS trg_audit ON public.extracto_bancario;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.extracto_bancario
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- ─── 3. Índices de performance ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_extracto_cuenta_fecha
  ON public.extracto_bancario (cuenta_bancaria_id, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_extracto_no_conciliado
  ON public.extracto_bancario (cuenta_bancaria_id) WHERE conciliado = false;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, línea a línea, en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════

-- SELECT tablename, rowsecurity FROM pg_tables
--  WHERE schemaname='public' AND tablename IN ('cuentas_bancarias','extracto_bancario');
-- Esperado: 2 tablas rowsecurity=true.

-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname='trg_audit' AND NOT tgisinternal
--    AND tgrelid::regclass::text IN ('cuentas_bancarias','extracto_bancario');
-- Esperado: 2 triggers trg_audit.
