-- 050_ver_costos.sql — Permiso "ver costos" por usuario
-- Por defecto los empleados (es_admin=false) NO ven costos, márgenes ni
-- rentabilidad en la UI. Un admin puede habilitarlo por usuario desde
-- Config → Usuarios y permisos.
--
-- Nota: esto es ocultamiento a nivel UI. El dato sigue viajando por la API
-- (RLS filtra por empresa, no por columna). Para el caso de uso actual
-- (empleados de taller) es suficiente; blindaje a nivel columna requeriría
-- separar costos a tablas propias.
BEGIN;

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS ver_costos boolean NOT NULL DEFAULT false;

-- ─── Guard: solo un admin puede cambiar ver_costos ──────────────────
-- Extiende usuarios_guard (022_seguridad.sql) con la misma regla que es_admin.
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
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.ver_costos IS DISTINCT FROM OLD.ver_costos
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar ver_costos';
    END IF;
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND OLD.empresa_id IS NOT NULL
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- ─── RPC get_usuarios_empresa ────────────────────────────────────────
-- Se recrea como SETOF usuarios para que devuelva TODAS las columnas de
-- la tabla (incluida ver_costos y las que se agreguen a futuro).
-- La versión original se creó a mano en el SQL editor y no está en las
-- migraciones; esta la reemplaza con la misma semántica: usuarios de la
-- empresa del caller, bypasseando RLS vía SECURITY DEFINER.
DROP FUNCTION IF EXISTS public.get_usuarios_empresa();
CREATE FUNCTION public.get_usuarios_empresa()
RETURNS SETOF usuarios
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT * FROM usuarios
  WHERE empresa_id = public.current_empresa_id()
  ORDER BY created_at ASC
$$;
REVOKE ALL ON FUNCTION public.get_usuarios_empresa() FROM public;
GRANT EXECUTE ON FUNCTION public.get_usuarios_empresa() TO authenticated;

COMMIT;

-- Verificación:
-- SELECT column_name FROM information_schema.columns WHERE table_name='usuarios' AND column_name='ver_costos';
-- SELECT proname, prosecdef FROM pg_proc WHERE proname='get_usuarios_empresa';
