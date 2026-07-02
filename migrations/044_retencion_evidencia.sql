-- ═══════════════════════════════════════════════════════════════════
-- 044_retencion_evidencia.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 9.
-- Retención de registros (10 años): los registros de calidad no se
-- borran. Hoy el REST de Supabase permite DELETE a cualquier usuario
-- autenticado de la empresa; este guard lo restringe a administradores
-- (y el borrado queda registrado en audit_log por trg_audit, que corre
-- después del BEFORE guard).
--
-- Tablas protegidas: certificados (MTRs), recepciones_oc,
-- tratamientos, calibraciones, registros_calidad, no_conformidades,
-- acciones_capa, documentos_controlados.
--
-- NO cubre (a propósito): op_operaciones (se regeneran al aplicar un
-- PQP), barras/productos_terminados (operativas, ya con CHECKs), y las
-- tablas contables (ya protegidas por período cerrado / CAE).
--
-- La otra mitad de la retención es OPERATIVA y va en el procedimiento
-- de control de registros de Fase 3: backup exportable conservado 10
-- años (el PITR de Supabase es de días, no años) — no es SQL.
--
-- Cláusulas: API Q1 §4.5 (control de registros, retención mínima),
--            ISO 9001:2015 §7.5.3.
-- Requiere: 032 (current_usuario_es_admin), 037-043 (tablas de calidad).
-- RETROCOMPATIBLE: los admins (Giuliano) siguen pudiendo borrar; a los
-- demás usuarios el botón Eliminar les va a devolver el error del guard.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_proteger_evidencia() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NOT public.current_usuario_es_admin() THEN
    RAISE EXCEPTION 'Registro de calidad protegido (retención 10 años): '
      'solo un administrador puede eliminarlo';
  END IF;
  RETURN OLD;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_proteger_evidencia() FROM PUBLIC, anon;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['certificados','recepciones_oc','tratamientos',
                           'calibraciones','registros_calidad',
                           'no_conformidades','acciones_capa',
                           'documentos_controlados'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_proteger_evidencia ON %I', t);
      EXECUTE format('CREATE TRIGGER trg_proteger_evidencia BEFORE DELETE ON %I
                      FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_evidencia()', t);
    END IF;
  END LOOP;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. El guard está en las 8 tablas:
-- SELECT tgrelid::regclass AS tabla FROM pg_trigger
--  WHERE tgname = 'trg_proteger_evidencia' AND NOT tgisinternal
--  ORDER BY 1;
--
-- 2. Probar con un usuario NO admin: cualquier DELETE sobre esas tablas
--    debe devolver "Registro de calidad protegido...". Como admin, el
--    DELETE pasa y queda asentado en audit_log (accion='DELETE').
