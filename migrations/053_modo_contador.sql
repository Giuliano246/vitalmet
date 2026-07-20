-- 053_modo_contador.sql — Contador externo en solo lectura (Modo Contador)
-- El contador del estudio entra con su propio login (se registra con el
-- código de invitación, como cualquier usuario) y el admin lo marca
-- usuarios.es_contador=true desde Configuración → Usuarios. A partir de ahí:
--   · SELECT: intacto (qué módulos ve lo deciden los permisos_usuario)
--   · INSERT/UPDATE/DELETE: bloqueados en TODAS las tablas con RLS por
--     tres policies RESTRICTIVE por comando (contador_no_ins/upd/del)
--   · Funciones SECURITY DEFINER que escriben (bypass de RLS): las frena
--     el trigger de statement contador_guard, que se dispara también
--     dentro de funciones DEFINER. Doble cerrojo deliberado.
-- Usuarios normales (es_contador=false): cero cambio de comportamiento.
BEGIN;

-- ─── 1. Flag ─────────────────────────────────────────────────────────
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS es_contador boolean NOT NULL DEFAULT false;

-- ─── 2. Helper (SECURITY DEFINER: lee usuarios sin chocar con RLS) ───
CREATE OR REPLACE FUNCTION public.es_contador()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE((SELECT u.es_contador FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_contador() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_contador() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_contador() TO authenticated;

-- ─── 3. Trigger guard: frena escrituras (INSERT/UPDATE/DELETE/TRUNCATE) incluso vía SECURITY DEFINER ─
-- Nota: RLS nunca gobierna TRUNCATE en PostgreSQL, así que el trigger como statement-level
-- es la única barrera que tiene el contador para ese comando.
CREATE OR REPLACE FUNCTION public.fn_contador_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF public.es_contador() THEN
    RAISE EXCEPTION 'Modo contador: solo lectura';
  END IF;
  RETURN NULL; -- statement-level BEFORE: el valor de retorno se ignora
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_contador_guard() FROM PUBLIC, anon;

-- ─── 4. Lockdown: 3 policies + trigger en TODA tabla con RLS ─────────
-- Sin whitelist: el contador no escribe en ninguna tabla, tampoco en
-- usuarios (su fila se crea al registrarse, cuando es_contador aún es
-- false; después la administra el admin, que no es contador).
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND rowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS contador_no_ins ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_ins ON %I AS RESTRICTIVE FOR INSERT '
      'TO authenticated WITH CHECK ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_upd ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_upd ON %I AS RESTRICTIVE FOR UPDATE '
      'TO authenticated USING ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_del ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_del ON %I AS RESTRICTIVE FOR DELETE '
      'TO authenticated USING ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP TRIGGER IF EXISTS contador_guard ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %I '
      'FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard()', t);
  END LOOP;
END $$;

-- ─── 5. usuarios_guard: es_contador solo lo cambia un admin ──────────
-- Recrea la función de 052 agregando la misma regla que es_admin /
-- ver_costos / es_planta. El SQL Editor (auth.uid() IS NULL) sigue confiado.
CREATE OR REPLACE FUNCTION public.usuarios_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_admin boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- postgres / service_role: confiado
  END IF;
  SELECT es_admin INTO caller_admin FROM usuarios WHERE id = auth.uid();
  IF TG_OP = 'INSERT' THEN
    NEW.es_admin := false;
    NEW.ver_costos := false;
    NEW.es_planta := false;
    NEW.es_contador := false;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.ver_costos IS DISTINCT FROM OLD.ver_costos
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar ver_costos';
    END IF;
    IF NEW.es_planta IS DISTINCT FROM OLD.es_planta
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_planta';
    END IF;
    IF NEW.es_contador IS DISTINCT FROM OLD.es_contador
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_contador';
    END IF;
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND OLD.empresa_id IS NOT NULL
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

COMMIT;

-- Verificación:
-- 1) Columna y función:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name='usuarios' AND column_name='es_contador';      -- 1 fila
--    SELECT public.es_contador();                                      -- false (SQL editor)
-- 2) Las 3 policies en tablas sensibles (mismo conteo por policy):
--    SELECT policyname, count(*) FROM pg_policies
--     WHERE policyname LIKE 'contador_no_%' GROUP BY policyname;      -- 3 filas, mismo count
--    SELECT tablename FROM pg_policies WHERE policyname='contador_no_ins'
--     AND tablename IN ('ventas','asientos','usuarios','ordenes_produccion'); -- 4 filas
-- 3) Restrictivas de verdad:
--    SELECT permissive FROM pg_policies
--     WHERE policyname='contador_no_ins' LIMIT 1;                     -- RESTRICTIVE
-- 4) Trigger en todas las tablas con RLS:
--    SELECT count(*) FROM pg_trigger WHERE tgname='contador_guard';
--    -- = SELECT count(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity
-- 5) Guard extendido:
--    SELECT prosrc LIKE '%es_contador%' FROM pg_proc WHERE proname='usuarios_guard'; -- true
