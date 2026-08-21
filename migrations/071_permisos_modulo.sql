-- 071_permisos_modulo.sql — Remediación auditoría externa 2026-08 (Fase 3)
-- Cierra H-04 (ALTA) en su alcance acordado: los permisos por módulo
-- dejan de ser solo de UI para las tablas SENSIBLES. Antes, cualquier
-- usuario autenticado podía leer sueldos o alterar precios por REST
-- directo con la anon key + su token, sin importar qué módulos le
-- habilitó el admin (la RLS aislaba por empresa, no por módulo).
--
-- Alcance deliberado (no es "RLS por módulo en todo"):
--   · SUELDOS (empleados, liquidaciones, liquidacion_items): lectura Y
--     escritura requieren el módulo 'sueldos'. Es el dato más sensible
--     (salarios). Sin el módulo, los SELECT devuelven 0 filas (la UI
--     degrada sola: cashflow/alertas F.931 simplemente no los suman) y
--     las escrituras — directas o vía guardar/confirmar/anular_
--     liquidacion, que son SECURITY INVOKER — fallan.
--   · PRECIOS (precios_base): solo ESCRITURA requiere el módulo
--     'precios'. La lectura queda abierta dentro de la empresa porque
--     presupuestos/ventas la necesitan para cotizar; el riesgo del
--     informe era la alteración de precios por API. Cubre también
--     ajustar_precios_pct (SECURITY INVOKER).
--   · ASIENTOS quedan FUERA a propósito: gatearlos por módulo rompería
--     los flujos cross-módulo (facturar, cheques, sueldos generan
--     asientos vía crear_asiento con el usuario que opera). Su control
--     es la RPC + triggers de inmutabilidad (067) + audit_log.
--
-- Roles: admin bypasea (es_admin), contador/auditor LEEN todo (su
-- trabajo) pero siguen sin poder escribir (contador_no_* RESTRICTIVE,
-- las policies se AND-ean), planta ya estaba bloqueado (planta_lockdown)
-- y además no tiene módulos. SQL Editor (auth.uid() IS NULL) confiado.
--
-- Convenciones: idempotente, REVOKE anon, search_path=public.
-- Correr en el SQL Editor ANTES de deployar (no hay cambio de frontend:
-- la UI ya oculta las pestañas; esto agrega el cerrojo real).

BEGIN;

-- ─── 1. Helper tiene_modulo(text) ────────────────────────────────────
-- Mismo molde que es_planta()/es_contador(): SECURITY DEFINER + STABLE
-- (lee permisos_usuario sin depender de la RLS del caller).

CREATE OR REPLACE FUNCTION public.tiene_modulo(p_modulo text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT auth.uid() IS NULL  -- postgres / service_role: confiado
      OR COALESCE((SELECT u.es_admin OR u.es_contador OR u.es_auditor
                   FROM usuarios u WHERE u.id = auth.uid()), false)
      OR EXISTS (SELECT 1 FROM permisos_usuario p
                 WHERE p.usuario_id = auth.uid() AND p.modulo = p_modulo)
$$;
REVOKE ALL ON FUNCTION public.tiene_modulo(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tiene_modulo(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.tiene_modulo(text) TO authenticated;

-- ─── 2. Sueldos: módulo 'sueldos' para leer y escribir ───────────────

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['empleados', 'liquidaciones', 'liquidacion_items'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS modulo_sueldos ON %I', t);
    EXECUTE format(
      'CREATE POLICY modulo_sueldos ON %I AS RESTRICTIVE FOR ALL '
      'TO authenticated USING ((SELECT public.tiene_modulo(''sueldos''))) '
      'WITH CHECK ((SELECT public.tiene_modulo(''sueldos'')))', t);
  END LOOP;
END $$;

-- ─── 3. Precios: módulo 'precios' solo para escribir ─────────────────
-- (lectura abierta: el cotizador de presupuestos/ventas la necesita)

DROP POLICY IF EXISTS modulo_precios_ins ON precios_base;
CREATE POLICY modulo_precios_ins ON precios_base AS RESTRICTIVE FOR INSERT
  TO authenticated WITH CHECK ((SELECT public.tiene_modulo('precios')));
DROP POLICY IF EXISTS modulo_precios_upd ON precios_base;
CREATE POLICY modulo_precios_upd ON precios_base AS RESTRICTIVE FOR UPDATE
  TO authenticated USING ((SELECT public.tiene_modulo('precios')))
  WITH CHECK ((SELECT public.tiene_modulo('precios')));
DROP POLICY IF EXISTS modulo_precios_del ON precios_base;
CREATE POLICY modulo_precios_del ON precios_base AS RESTRICTIVE FOR DELETE
  TO authenticated USING ((SELECT public.tiene_modulo('precios')));

COMMIT;

-- ─── Verificación ────────────────────────────────────────────────────
-- 1) Helper sin anon:
-- SELECT has_function_privilege('anon', 'public.tiene_modulo(text)', 'EXECUTE');  -- false
-- SELECT public.tiene_modulo('sueldos');                                          -- true (SQL editor)
-- 2) Policies nuevas, RESTRICTIVE:
-- SELECT tablename, policyname, permissive FROM pg_policies
--  WHERE policyname LIKE 'modulo_%' ORDER BY 1, 2;
--    (esperado: empleados/liquidaciones/liquidacion_items → modulo_sueldos,
--     precios_base → modulo_precios_ins/upd/del; todas RESTRICTIVE)
-- 3) Funcional (con un usuario NO admin y SIN el módulo sueldos):
--    GET /rest/v1/liquidaciones → 200 con []   (filas ocultas, no error)
--    POST /rest/v1/empleados    → 42501 (RLS)
--    PATCH /rest/v1/precios_base?... → 0 filas afectadas sin módulo 'precios'
--    y con el módulo asignado (Configuración → Usuarios) todo vuelve a andar.
