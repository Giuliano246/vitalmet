-- ═══════════════════════════════════════════════════════════════════
-- 081 — CIERRE AUDITORÍA DE SEGURIDAD 2026-09-21 (C01, C02, C03)
-- ═══════════════════════════════════════════════════════════════════
-- Informe: ~/Downloads/VitalStock-auditoria-seguridad-2026-09-21.zip
-- (revisión estática, 7 candidatos; verificados contra el código).
-- Spec: docs/superpowers/specs/2026-09-21-auditoria-seguridad-design.md
--
-- Qué hace:
--   1. Helper es_admin() (molde es_planta/es_contador/es_auditor).
--   2. C02 — permisos_usuario: INSERT/UPDATE/DELETE sólo admin (policies
--      RESTRICTIVE). Hasta ahora sólo tenía tenant_isolation FOR ALL: un
--      usuario común podía darse los módulos sueldos/precios/ventas con
--      un POST directo. guardar_permisos (SECURITY INVOKER, exige admin)
--      sigue funcionando.
--   3. C03 — secretos de Microsoft Graph fuera del alcance de los
--      usuarios: tabla integracion_microsoft_secretos SIN grants a
--      anon/authenticated y SIN policies (sólo service_role, que es quien
--      corre el mailer). Se copian los valores, se anulan las columnas
--      de texto plano de integracion_microsoft y un trigger impide volver
--      a escribirlas. integracion_microsoft queda sólo para admin.
--      La Edge Function vitalmet-mailer lee/escribe la tabla nueva.
--   4. C01 — alta de usuarios sólo por RPC: usuarios_insert y
--      empresas_insert exigen la marca de sesión 'vitalstock.rpc' que
--      sólo setean join_empresa (re-emitida, base 022) y la nueva
--      crear_empresa (reemplaza los dos POST directos de doRegister).
--      usuarios_guard RE-EMITIDO (base 070 — ediciones futuras parten de
--      acá): INSERT directo rechazado, cambio de empresa_id (incluido
--      NULL → X) sólo admin o RPC, el fundador de una empresa nueva
--      nace admin (marca 'vitalstock.bootstrap', sólo crear_empresa).
--      usuarios_delete: sólo admin y nunca la fila propia (evita borrar
--      y reinsertarse en otra empresa).
--
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend y
-- las Edge Functions vitalmet-mailer y facturacion. Con la 081 aplicada
-- y el mailer viejo todavía deployado, el cron devuelve
-- {skipped:"sin_integracion_microsoft"} (los mails esperan; no se pierde
-- nada). DESPUÉS de aplicar: rotar el client secret en Entra y repetir
-- el consentimiento OAuth (docs/azure-ad-setup.md § Rotación).

BEGIN;

-- ─── 1. es_admin() ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.es_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT COALESCE((SELECT u.es_admin FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_admin() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_admin() TO authenticated;

-- ─── 2. C02: permisos_usuario, escritura sólo admin ──────────────────
DROP POLICY IF EXISTS permisos_solo_admin_ins ON public.permisos_usuario;
CREATE POLICY permisos_solo_admin_ins ON public.permisos_usuario AS RESTRICTIVE FOR INSERT
  TO authenticated WITH CHECK ((SELECT public.es_admin()));
DROP POLICY IF EXISTS permisos_solo_admin_upd ON public.permisos_usuario;
CREATE POLICY permisos_solo_admin_upd ON public.permisos_usuario AS RESTRICTIVE FOR UPDATE
  TO authenticated USING ((SELECT public.es_admin())) WITH CHECK ((SELECT public.es_admin()));
DROP POLICY IF EXISTS permisos_solo_admin_del ON public.permisos_usuario;
CREATE POLICY permisos_solo_admin_del ON public.permisos_usuario AS RESTRICTIVE FOR DELETE
  TO authenticated USING ((SELECT public.es_admin()));

-- ─── 3. C03: secretos de Microsoft sólo para el servicio ─────────────
CREATE TABLE IF NOT EXISTS public.integracion_microsoft_secretos (
  integracion_id    uuid PRIMARY KEY REFERENCES public.integracion_microsoft(id) ON DELETE CASCADE,
  client_secret     text NOT NULL,
  refresh_token     text,
  ultimo_refresh_at timestamptz,
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.integracion_microsoft_secretos IS
  'Secretos de Graph (client secret + refresh token). Sin grants ni policies para usuarios: sólo service_role (mailer). Mig 081.';
ALTER TABLE public.integracion_microsoft_secretos ENABLE ROW LEVEL SECURITY;
-- Supabase otorga ALL a anon/authenticated por default privileges: se revoca.
REVOKE ALL ON TABLE public.integracion_microsoft_secretos FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.integracion_microsoft_secretos TO service_role;

-- Copiar lo que haya (idempotente) y anular el texto plano.
INSERT INTO public.integracion_microsoft_secretos (integracion_id, client_secret, refresh_token, ultimo_refresh_at)
SELECT id, client_secret_cifrado, refresh_token_cifrado, ultimo_refresh_at
FROM public.integracion_microsoft
WHERE COALESCE(client_secret_cifrado, '') <> ''
ON CONFLICT (integracion_id) DO NOTHING;

ALTER TABLE public.integracion_microsoft ALTER COLUMN client_secret_cifrado DROP NOT NULL;
UPDATE public.integracion_microsoft
   SET client_secret_cifrado = NULL, refresh_token_cifrado = NULL
 WHERE client_secret_cifrado IS NOT NULL OR refresh_token_cifrado IS NOT NULL;
COMMENT ON COLUMN public.integracion_microsoft.client_secret_cifrado IS 'OBSOLETA (mig 081): siempre NULL, el secreto vive en integracion_microsoft_secretos.';
COMMENT ON COLUMN public.integracion_microsoft.refresh_token_cifrado IS 'OBSOLETA (mig 081): siempre NULL, el token vive en integracion_microsoft_secretos.';

CREATE OR REPLACE FUNCTION public.fn_ms_sin_secretos() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.client_secret_cifrado IS NOT NULL OR NEW.refresh_token_cifrado IS NOT NULL THEN
    RAISE EXCEPTION 'Los secretos de Microsoft van en integracion_microsoft_secretos (mig 081), no en esta tabla';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_ms_sin_secretos() FROM PUBLIC, anon;
DROP TRIGGER IF EXISTS trg_ms_sin_secretos ON public.integracion_microsoft;
CREATE TRIGGER trg_ms_sin_secretos BEFORE INSERT OR UPDATE ON public.integracion_microsoft
  FOR EACH ROW EXECUTE FUNCTION public.fn_ms_sin_secretos();

-- Metadatos de la integración (tenant, client_id, remitente): sólo admin.
DROP POLICY IF EXISTS ms_solo_admin ON public.integracion_microsoft;
CREATE POLICY ms_solo_admin ON public.integracion_microsoft AS RESTRICTIVE FOR ALL
  TO authenticated USING ((SELECT public.es_admin())) WITH CHECK ((SELECT public.es_admin()));

-- ─── 4. C01: alta de usuarios y empresas sólo por RPC ────────────────
-- 4a. usuarios_guard re-emitido (base 070).
CREATE OR REPLACE FUNCTION public.usuarios_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller_admin boolean;
  via_rpc   boolean := COALESCE(current_setting('vitalstock.rpc', true), '') = '1';
  bootstrap boolean := COALESCE(current_setting('vitalstock.bootstrap', true), '') = '1';
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- postgres / service_role: confiado
  END IF;
  SELECT es_admin INTO caller_admin FROM usuarios WHERE id = auth.uid();
  IF TG_OP = 'INSERT' THEN
    IF NOT via_rpc THEN
      RAISE EXCEPTION 'El alta de usuarios se hace por invitación (join_empresa) o al crear la empresa (crear_empresa)';
    END IF;
    NEW.es_admin := bootstrap;      -- fundador de una empresa nueva
    NEW.ver_costos := bootstrap;
    NEW.es_planta := false;
    NEW.es_contador := false;
    NEW.es_auditor := false;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) AND NOT bootstrap THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.ver_costos IS DISTINCT FROM OLD.ver_costos
       AND NOT COALESCE(caller_admin, false) AND NOT bootstrap THEN
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
    IF NEW.es_auditor IS DISTINCT FROM OLD.es_auditor
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_auditor';
    END IF;
    -- Cambio de empresa (incluido NULL → X): sólo admin o RPC de alta.
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND NOT via_rpc AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- 4b. Policies: INSERT sólo con la marca de RPC; DELETE sólo admin, nunca la propia.
DROP POLICY IF EXISTS usuarios_insert ON public.usuarios;
CREATE POLICY usuarios_insert ON public.usuarios FOR INSERT TO authenticated
  WITH CHECK (id = (SELECT auth.uid()) AND COALESCE(current_setting('vitalstock.rpc', true), '') = '1');
DROP POLICY IF EXISTS usuarios_delete ON public.usuarios;
CREATE POLICY usuarios_delete ON public.usuarios FOR DELETE TO authenticated
  USING (empresa_id = (SELECT public.current_empresa_id())
         AND (SELECT public.es_admin())
         AND id <> (SELECT auth.uid()));
DROP POLICY IF EXISTS empresas_insert ON public.empresas;
CREATE POLICY empresas_insert ON public.empresas FOR INSERT TO authenticated
  WITH CHECK (COALESCE(current_setting('vitalstock.rpc', true), '') = '1');

-- 4c. join_empresa re-emitida (base 022): idéntica + marca de RPC.
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
  PERFORM set_config('vitalstock.rpc', '1', true);   -- local a la transacción
  INSERT INTO usuarios (id, empresa_id, nombre, email, rol, es_admin)
  VALUES (auth.uid(), emp, p_nombre, (auth.jwt()->>'email'), 'usuario', false)
  ON CONFLICT (id) DO UPDATE SET empresa_id = excluded.empresa_id, nombre = excluded.nombre;
  RETURN emp;
END $$;
REVOKE ALL ON FUNCTION public.join_empresa(text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.join_empresa(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_empresa(text, text) TO authenticated;

-- 4d. crear_empresa: reemplaza los POST directos a empresas + usuarios de doRegister.
CREATE OR REPLACE FUNCTION public.crear_empresa(p_nombre text, p_slug text, p_usuario_nombre text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE emp uuid; existing uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF COALESCE(trim(p_nombre), '') = '' THEN
    RAISE EXCEPTION 'Completá el nombre de la empresa';
  END IF;
  SELECT empresa_id INTO existing FROM usuarios WHERE id = auth.uid();
  IF existing IS NOT NULL THEN
    RAISE EXCEPTION 'Este usuario ya pertenece a una empresa';
  END IF;
  PERFORM set_config('vitalstock.rpc', '1', true);
  PERFORM set_config('vitalstock.bootstrap', '1', true);
  INSERT INTO empresas (nombre, slug) VALUES (trim(p_nombre), NULLIF(trim(p_slug), ''))
  RETURNING id INTO emp;
  INSERT INTO usuarios (id, empresa_id, nombre, email, rol, es_admin, ver_costos)
  VALUES (auth.uid(), emp, COALESCE(NULLIF(trim(p_usuario_nombre), ''), auth.jwt()->>'email'),
          (auth.jwt()->>'email'), 'usuario', true, true)
  ON CONFLICT (id) DO UPDATE
    SET empresa_id = excluded.empresa_id, nombre = excluded.nombre,
        es_admin = true, ver_costos = true;
  RETURN jsonb_build_object('id', emp);
END $$;
REVOKE ALL ON FUNCTION public.crear_empresa(text, text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.crear_empresa(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.crear_empresa(text, text, text) TO authenticated;

COMMIT;

-- ─── Verificación ────────────────────────────────────────────────────
-- 1) Helpers y RPCs sin anon:
-- SELECT proname, has_function_privilege('anon', oid, 'EXECUTE') AS anon_ok
--   FROM pg_proc WHERE proname IN ('es_admin','crear_empresa','join_empresa');   -- todo false
-- 2) Policies nuevas (todas RESTRICTIVE salvo usuarios_insert/usuarios_delete/empresas_insert):
-- SELECT tablename, policyname, permissive, cmd FROM pg_policies
--  WHERE policyname IN ('permisos_solo_admin_ins','permisos_solo_admin_upd','permisos_solo_admin_del',
--                       'ms_solo_admin','usuarios_insert','usuarios_delete','empresas_insert') ORDER BY 1,2;
-- 3) Secretos movidos y texto plano anulado:
-- SELECT count(*) FROM integracion_microsoft_secretos;                                   -- 1
-- SELECT count(*) FROM integracion_microsoft
--  WHERE client_secret_cifrado IS NOT NULL OR refresh_token_cifrado IS NOT NULL;         -- 0
-- SELECT grantee, privilege_type FROM information_schema.role_table_grants
--  WHERE table_name = 'integracion_microsoft_secretos';                                  -- sólo service_role (y postgres)
-- 4) Funcional (usuario NO admin, con su JWT):
--    POST /rest/v1/permisos_usuario {empresa_id, usuario_id: propio, modulo:'sueldos'} → 42501
--    GET  /rest/v1/integracion_microsoft_secretos → 42501 (permission denied)
--    GET  /rest/v1/integracion_microsoft → 200 con []
--    POST /rest/v1/usuarios {id: propio, empresa_id: X} → error del guard
--    DELETE /rest/v1/usuarios?id=eq.<propio> → 0 filas
--    Admin: Configuración → Usuarios → Guardar permisos sigue funcionando (guardar_permisos).
--    Registro nuevo: doRegister → RPC crear_empresa → usuario admin de su empresa.
