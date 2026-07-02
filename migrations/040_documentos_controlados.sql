-- ═══════════════════════════════════════════════════════════════════
-- 040_documentos_controlados.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 8.
-- Documentos controlados: manual, procedimientos, instructivos,
-- formularios, WPS/PQR/WPQ, PQPs y planes de contingencia, con código,
-- revisión y estado de vigencia. Es el repositorio del paquete
-- documental de Fase 3 y la tabla que referencian las operaciones de
-- producción (WPS por ID + revisión, migración 041).
--
-- Qué agrega:
--   1. Tabla documentos_controlados (UNIQUE empresa+codigo+revision;
--      PDF adjunto base64 igual que certificados).
--   2. fn_doc_vigencia: al poner una revisión en 'vigente' estampa
--      aprobado_por/fecha_vigencia y OBSOLETA automáticamente las demás
--      revisiones del mismo código (nunca hay dos revisiones vigentes —
--      requisito duro de control de documentos).
--   3. RLS tenant_isolation + trg_audit.
--
-- Cláusulas: ISO 9001:2015 §7.5 (información documentada),
--            API Q1 §4.4.3 (control de documentos).
-- Requiere: 006 (current_empresa_id), 023 (fn_audit).
-- RETROCOMPATIBLE: tabla nueva, no toca nada existente.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Tabla ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.documentos_controlados (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid        NOT NULL,
  codigo         text        NOT NULL,              -- ej: MC-01, PG-04, IT-02, WPS-01, PQP-1502
  titulo         text        NOT NULL,
  tipo           text        NOT NULL DEFAULT 'procedimiento'
                             CHECK (tipo IN ('manual','procedimiento','instructivo','formulario',
                                             'wps','pqr','wpq','pqp','plan_contingencia','otro')),
  revision       text        NOT NULL DEFAULT '0',
  estado         text        NOT NULL DEFAULT 'borrador'
                             CHECK (estado IN ('borrador','vigente','obsoleto')),
  fecha_vigencia date,
  aprobado_por   uuid,                              -- auth.uid() del que puso vigente
  file_data      text,                              -- PDF base64 (mismo patrón que certificados)
  file_name      text,
  observaciones  text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, codigo, revision)
);

CREATE INDEX IF NOT EXISTS idx_doc_codigo ON documentos_controlados (empresa_id, codigo);
CREATE INDEX IF NOT EXISTS idx_doc_estado ON documentos_controlados (empresa_id, estado);

-- ─── 2. RLS ──────────────────────────────────────────────────────────
ALTER TABLE public.documentos_controlados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.documentos_controlados;
CREATE POLICY tenant_isolation ON public.documentos_controlados
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- ─── 3. Vigencia única por código ────────────────────────────────────
-- BEFORE: estampa aprobación. AFTER: obsoleta a las demás revisiones.
-- El UPDATE del AFTER re-dispara el trigger, pero la condición
-- (NEW.estado = 'vigente') no se cumple para 'obsoleto' → no recursiona.
CREATE OR REPLACE FUNCTION public.fn_doc_vigencia_before() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'vigente'
     AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM 'vigente') THEN
    NEW.aprobado_por   := COALESCE(NEW.aprobado_por, auth.uid());
    NEW.fecha_vigencia := COALESCE(NEW.fecha_vigencia, current_date);
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_doc_vigencia_before() FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.fn_doc_vigencia_after() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  UPDATE documentos_controlados
  SET estado = 'obsoleto'
  WHERE empresa_id = NEW.empresa_id AND codigo = NEW.codigo
    AND id <> NEW.id AND estado = 'vigente';
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_doc_vigencia_after() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_doc_vigencia_before ON documentos_controlados;
CREATE TRIGGER trg_doc_vigencia_before
  BEFORE INSERT OR UPDATE OF estado ON documentos_controlados
  FOR EACH ROW EXECUTE FUNCTION public.fn_doc_vigencia_before();

DROP TRIGGER IF EXISTS trg_doc_vigencia_after ON documentos_controlados;
CREATE TRIGGER trg_doc_vigencia_after
  AFTER INSERT OR UPDATE OF estado ON documentos_controlados
  FOR EACH ROW WHEN (NEW.estado = 'vigente')
  EXECUTE FUNCTION public.fn_doc_vigencia_after();

-- ─── 4. Auditoría ────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit ON documentos_controlados;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON documentos_controlados
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Tabla + policy:
-- SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'documentos_controlados';
-- SELECT polname FROM pg_policy WHERE polrelid = 'documentos_controlados'::regclass;
--
-- 2. Smoke test de vigencia única (rev 0 vigente → rev 1 vigente debe
--    obsoletar a la 0; limpia al final):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   d0 uuid; v_estado text;
-- BEGIN
--   INSERT INTO documentos_controlados (empresa_id, codigo, titulo, tipo, revision, estado)
--   VALUES (emp, '__TEST-DOC__', 'Test', 'procedimiento', '0', 'vigente') RETURNING id INTO d0;
--   INSERT INTO documentos_controlados (empresa_id, codigo, titulo, tipo, revision, estado)
--   VALUES (emp, '__TEST-DOC__', 'Test', 'procedimiento', '1', 'vigente');
--   SELECT estado INTO v_estado FROM documentos_controlados WHERE id = d0;
--   IF v_estado = 'obsoleto' THEN RAISE NOTICE 'OK: rev 0 quedó obsoleta';
--   ELSE RAISE EXCEPTION 'ERROR: rev 0 quedó % (esperado obsoleto)', v_estado; END IF;
--   DELETE FROM documentos_controlados WHERE empresa_id = emp AND codigo = '__TEST-DOC__';
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
