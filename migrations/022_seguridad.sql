-- ═══════════════════════════════════════════════════════════════════
-- 022_seguridad.sql
-- Hardening de seguridad (auditoría 2026-06-09)
--
-- Qué arregla:
--   1. Escalada de privilegios: usuarios_update sin WITH CHECK permitía
--      a cualquier usuario hacerse es_admin=true o cambiarse de empresa
--      con un PATCH directo a /rest/v1/usuarios. → trigger guardián.
--   2. El join por código de invitación se validaba SOLO en el cliente
--      y la tabla empresas era legible sin login (policies anon/public
--      con USING true, exponiendo codigo_invitacion). → RPCs SECURITY
--      DEFINER + drop de las policies abiertas y legacy.
--   3. Las vistas (ventas_pendientes_mail, pt_stock_disponible,
--      oc_items_con_recepcion) corrían con permisos del owner y
--      bypaseaban RLS. → security_invoker = true.
--   4. Las policies de asientos/asiento_lineas/cuentas_contables se
--      crearon a mano (no versionadas), sin el wrap (SELECT ...) de 020,
--      y asiento_lineas tenía una policy duplicada. → se versionan acá,
--      optimizadas, y se elimina el duplicado.
--   5. asientos/asiento_lineas no tenían índices. → se agregan.
--
-- Requiere deploy del frontend en el mismo momento: doJoin pasa a usar
-- las RPCs empresa_por_codigo / join_empresa (el flujo viejo de alta de
-- usuarios deja de funcionar al dropear empresas_anon_lookup; los
-- usuarios ya logueados no se ven afectados).
--
-- Idempotente. Seguro de re-correr.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Trigger guardián de usuarios ────────────────────────────────
-- Reglas:
--   INSERT: es_admin nace siempre false (los admin se otorgan por UPDATE
--           de otro admin, o manualmente con service_role/SQL editor).
--   UPDATE: cambiar es_admin → solo un admin de la empresa.
--           cambiar empresa_id → solo en el primer join (OLD IS NULL)
--           o por un admin.
--   auth.uid() IS NULL = acceso directo postgres/service_role → bypass
--   (el SQL editor y el microservicio de billing no pasan por acá).
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
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND OLD.empresa_id IS NOT NULL
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_usuarios_guard ON usuarios;
CREATE TRIGGER trg_usuarios_guard
  BEFORE INSERT OR UPDATE ON usuarios
  FOR EACH ROW EXECUTE FUNCTION public.usuarios_guard();

-- ─── 2. RPCs para el flujo de invitación ────────────────────────────
-- Lookup por código exacto: devuelve solo id+nombre y solo si matchea.
-- Reemplaza la lectura abierta de empresas por anon.
CREATE OR REPLACE FUNCTION public.empresa_por_codigo(p_codigo text)
RETURNS TABLE(id uuid, nombre text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT e.id, e.nombre FROM empresas e
  WHERE upper(e.codigo_invitacion) = upper(trim(p_codigo))
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.empresa_por_codigo(text) FROM public;
GRANT EXECUTE ON FUNCTION public.empresa_por_codigo(text) TO anon, authenticated;

-- Join validado en el servidor. Si el usuario ya tiene empresa, no se
-- muda (devuelve la actual). es_admin queda en false vía trigger.
CREATE OR REPLACE FUNCTION public.join_empresa(p_codigo text, p_nombre text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE emp uuid; existing uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  SELECT e.id INTO emp FROM empresas e
  WHERE upper(e.codigo_invitacion) = upper(trim(p_codigo));
  IF emp IS NULL THEN
    RAISE EXCEPTION 'Código inválido. Verificá con tu administrador.';
  END IF;
  SELECT empresa_id INTO existing FROM usuarios WHERE id = auth.uid();
  IF existing IS NOT NULL THEN
    RETURN existing;
  END IF;
  INSERT INTO usuarios (id, empresa_id, nombre, email, rol, es_admin)
  VALUES (auth.uid(), emp, p_nombre, (auth.jwt()->>'email'), 'usuario', false)
  ON CONFLICT (id) DO UPDATE SET empresa_id = excluded.empresa_id, nombre = excluded.nombre;
  RETURN emp;
END $$;
REVOKE ALL ON FUNCTION public.join_empresa(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.join_empresa(text, text) TO authenticated;

-- ─── 3. Limpieza de policies de empresas ────────────────────────────
-- Quedan: empresas_self (SELECT propio), empresas_insert (alta en
-- doRegister), empresas_update (ahora solo admin).
-- Se van: las dos policies abiertas (anon/public USING true) y las
-- legacy de generaciones anteriores que usaban funciones viejas.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='empresas') THEN
    EXECUTE 'DROP POLICY IF EXISTS empresas_anon_lookup ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS buscar_por_codigo ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresa_propia ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_select ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_delete ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_update ON empresas';
    EXECUTE 'CREATE POLICY empresas_update ON empresas FOR UPDATE TO authenticated '
            'USING (id = (SELECT public.current_empresa_id()) '
            'AND COALESCE((SELECT u.es_admin FROM usuarios u WHERE u.id = (SELECT auth.uid())), false)) '
            'WITH CHECK (id = (SELECT public.current_empresa_id()))';
  END IF;
END $$;

-- ─── 4. Vistas: respetar la RLS de las tablas base ──────────────────
DO $$
DECLARE v text;
BEGIN
  FOREACH v IN ARRAY ARRAY['ventas_pendientes_mail','pt_stock_disponible','oc_items_con_recepcion'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema='public' AND table_name=v) THEN
      EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v);
      RAISE NOTICE 'security_invoker activado en %', v;
    END IF;
  END LOOP;
END $$;

-- ─── 5. Policies contables: versionar, optimizar, deduplicar ────────
-- (asientos, asiento_lineas y cuentas_contables se crearon a mano;
-- esta migración las trae al repo con el patrón (SELECT ...) de 020)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['asientos','cuentas_contables'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', t);
      EXECUTE format(
        'CREATE POLICY tenant_isolation ON %I FOR ALL TO authenticated '
        'USING (empresa_id = (SELECT public.current_empresa_id())) '
        'WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))', t);
    END IF;
  END LOOP;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='asiento_lineas') THEN
    EXECUTE 'ALTER TABLE asiento_lineas ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS lineas_isolation ON asiento_lineas';        -- duplicada
    EXECUTE 'DROP POLICY IF EXISTS asiento_lineas_isolation ON asiento_lineas';
    EXECUTE 'CREATE POLICY asiento_lineas_isolation ON asiento_lineas FOR ALL TO authenticated '
            'USING (EXISTS (SELECT 1 FROM asientos a WHERE a.id = asiento_lineas.asiento_id AND a.empresa_id = (SELECT public.current_empresa_id()))) '
            'WITH CHECK (EXISTS (SELECT 1 FROM asientos a WHERE a.id = asiento_lineas.asiento_id AND a.empresa_id = (SELECT public.current_empresa_id())))';
  END IF;
END $$;

-- ─── 6. Índices contables faltantes ─────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_asientos_empresa_fecha ON asientos (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_asientos_origen        ON asientos (origen_tipo, origen_id);
CREATE INDEX IF NOT EXISTS idx_asiento_lineas_asiento ON asiento_lineas (asiento_id);
CREATE INDEX IF NOT EXISTS idx_asiento_lineas_cuenta  ON asiento_lineas (cuenta_id);
CREATE INDEX IF NOT EXISTS idx_recepciones_empresa    ON recepciones_oc (empresa_id);

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
-- SELECT tablename, policyname, cmd, roles::text FROM pg_policies
-- WHERE schemaname='public' AND tablename IN ('empresas','usuarios','asientos','asiento_lineas','cuentas_contables')
-- ORDER BY tablename, policyname;
-- SELECT relname, reloptions FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
-- WHERE n.nspname='public' AND c.relkind='v';
