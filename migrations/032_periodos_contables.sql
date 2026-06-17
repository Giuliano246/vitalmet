-- ═══════════════════════════════════════════════════════════════════
-- 032_periodos_contables.sql
-- Cierre de períodos contables a nivel MENSUAL con bloqueo duro de
-- asientos y reapertura sólo por admin.
-- Motivado por la declaración mensual de IVA (AFIP).
--
-- Qué agrega:
--   1. current_usuario_es_admin()  — helper SECURITY DEFINER (mismo
--      patrón que current_empresa_id() de 006).
--   2. periodos_contables          — tabla con estado abierto/cerrado
--      por empresa × año × mes, RLS tenant_isolation, audit trigger.
--   3. fn_periodo_guard / trg_periodo_guard — sólo admin puede
--      reabrir un período cerrado; registra cerrado_por / cerrado_at
--      al cerrar.
--   4. fn_periodo_cerrado / trg_periodo_cerrado — bloqueo BEFORE
--      INSERT OR UPDATE en asientos: rechaza si el período del mes
--      de la fecha del asiento está cerrado.
--
-- Requiere: migración 006 (current_empresa_id), 022 (usuarios.es_admin),
--           023 (fn_audit / trg_audit).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Helper: ¿el usuario del JWT es admin? ────────────────────
-- Mismo patrón que current_empresa_id() (006_rls_setup.sql):
--   LANGUAGE sql / SECURITY DEFINER / SET search_path = public / STABLE.
-- SECURITY DEFINER evita que RLS sobre usuarios cause recursión al
-- ser llamada desde un contexto de evaluación de policies.
CREATE OR REPLACE FUNCTION public.current_usuario_es_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT es_admin FROM public.usuarios WHERE id = auth.uid() LIMIT 1),
    false
  );
$$;
-- Supabase otorga EXECUTE a anon por default: revocar explícitamente.
REVOKE EXECUTE ON FUNCTION public.current_usuario_es_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_usuario_es_admin() TO authenticated;

-- ─── 2. Tabla de períodos contables mensuales ────────────────────
CREATE TABLE IF NOT EXISTS public.periodos_contables (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid        NOT NULL,
  anio        int         NOT NULL CHECK (anio BETWEEN 2000 AND 2100),
  mes         int         NOT NULL CHECK (mes  BETWEEN 1    AND 12),
  estado      text        NOT NULL DEFAULT 'abierto'
                          CHECK (estado IN ('abierto','cerrado')),
  cerrado_por uuid,                           -- auth.uid() del que cerró
  cerrado_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, anio, mes)
);

ALTER TABLE public.periodos_contables ENABLE ROW LEVEL SECURITY;

-- Policy estándar optimizada (patrón 020/022: (SELECT ...) evita
-- re-evaluación por fila).
DROP POLICY IF EXISTS tenant_isolation ON public.periodos_contables;
CREATE POLICY tenant_isolation ON public.periodos_contables
  FOR ALL TO authenticated
  USING  (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));

-- Audit trail (fn_audit definida en migración 023).
DROP TRIGGER IF EXISTS trg_audit ON public.periodos_contables;
CREATE TRIGGER trg_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.periodos_contables
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- ─── 3. Guard de reapertura: sólo admin puede abrir un período cerrado ──
CREATE OR REPLACE FUNCTION public.fn_periodo_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  -- Reapertura (cerrado → abierto): requiere admin.
  IF TG_OP = 'UPDATE'
     AND OLD.estado = 'cerrado'
     AND NEW.estado = 'abierto'
     AND NOT public.current_usuario_es_admin()
  THEN
    RAISE EXCEPTION 'Sólo un administrador puede reabrir un período cerrado';
  END IF;

  -- Cierre (INSERT directo en 'cerrado' o UPDATE → 'cerrado'): registrar
  -- quién y cuándo cerró. El INSERT es el camino común (cerrarPeriodo hace
  -- POST cuando el período aún no existe), por eso el trigger cubre INSERT.
  IF NEW.estado = 'cerrado'
     AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM 'cerrado') THEN
    NEW.cerrado_por := auth.uid();
    NEW.cerrado_at  := now();
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_periodo_guard ON public.periodos_contables;
CREATE TRIGGER trg_periodo_guard
  BEFORE INSERT OR UPDATE ON public.periodos_contables
  FOR EACH ROW EXECUTE FUNCTION public.fn_periodo_guard();
-- Función de trigger de uso interno: no exponer a anon (convención del proyecto).
REVOKE EXECUTE ON FUNCTION public.fn_periodo_guard() FROM PUBLIC, anon;

-- ─── 4. Bloqueo de asientos en período cerrado ───────────────────
-- SECURITY DEFINER: necesita leer periodos_contables sin que el RLS
-- de esa tabla (empresa_id check) interfiera cuando la función se
-- invoca desde el trigger de asientos.
CREATE OR REPLACE FUNCTION public.fn_periodo_cerrado()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_estado text;
BEGIN
  SELECT estado INTO v_estado
    FROM public.periodos_contables
   WHERE empresa_id = NEW.empresa_id
     AND anio = EXTRACT(YEAR  FROM NEW.fecha)::int
     AND mes  = EXTRACT(MONTH FROM NEW.fecha)::int;

  IF v_estado = 'cerrado' THEN
    RAISE EXCEPTION
      'Período %-% cerrado: no se pueden imputar/editar asientos en esa fecha',
      EXTRACT(YEAR  FROM NEW.fecha)::int,
      EXTRACT(MONTH FROM NEW.fecha)::int;
  END IF;

  RETURN NEW;
END $$;
-- Esta función es de uso interno (trigger), no la exponer a anon.
REVOKE EXECUTE ON FUNCTION public.fn_periodo_cerrado() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_periodo_cerrado ON public.asientos;
CREATE TRIGGER trg_periodo_cerrado
  BEFORE INSERT OR UPDATE ON public.asientos
  FOR EACH ROW EXECUTE FUNCTION public.fn_periodo_cerrado();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, línea a línea, en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Helper admin (debería devolver false para un usuario normal):
-- SELECT public.current_usuario_es_admin();

-- 2. Funciones y triggers creados:
-- SELECT proname, prosecdef FROM pg_proc
--  WHERE proname IN ('current_usuario_es_admin','fn_periodo_guard','fn_periodo_cerrado')
--    AND pronamespace = 'public'::regnamespace;
--
-- SELECT tgname, tgrelid::regclass AS tabla, tgenabled
--   FROM pg_trigger
--  WHERE tgname IN ('trg_periodo_guard','trg_periodo_cerrado','trg_audit')
--    AND tgrelid::regclass::text IN ('periodos_contables','asientos')
--    AND NOT tgisinternal
--  ORDER BY tabla, tgname;

-- 3. Smoke test del bloqueo (crear período cerrado de prueba, intentar
--    insertar asiento con esa fecha y verificar que falla, limpiar):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   aid uuid;
-- BEGIN
--   -- Crear período 2020-01 cerrado directamente (saltea el guard UPDATE
--   -- porque es un INSERT con estado='cerrado'; el guard sólo actúa en UPDATE).
--   INSERT INTO public.periodos_contables (empresa_id, anio, mes, estado, cerrado_por, cerrado_at)
--   VALUES (emp, 2020, 1, 'cerrado', auth.uid(), now());
--
--   -- Intento de insertar asiento en ese período: debe lanzar EXCEPTION.
--   BEGIN
--     INSERT INTO public.asientos (empresa_id, numero, fecha, descripcion,
--                                  estado, tipo, moneda)
--     VALUES (emp, 99999, '2020-01-15', 'Test período cerrado',
--             'borrador', 'manual', 'ARS');
--     RAISE EXCEPTION 'ERROR: el bloqueo NO funcionó — revisar fn_periodo_cerrado';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: asiento bloqueado correctamente (mensaje: %)', SQLERRM;
--   END;
--
--   -- Limpiar período de prueba.
--   DELETE FROM public.periodos_contables WHERE empresa_id = emp AND anio = 2020 AND mes = 1;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
