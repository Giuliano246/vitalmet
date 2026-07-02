-- ============================================================================
-- 046 — Hardening del módulo Calidad (hallazgos QA + OBSERVACIONES_REV0)
--
-- 1. Tipo 'plano' en documentos_controlados (obs. #6): los planos dejan de
--    cargarse como 'otro'. PG-15 opera sobre ellos como documentos controlados.
-- 2. Guard de concesión (obs. #2): la justificación era obligatoria solo en el
--    frontend (saveNC); un PATCH directo por REST podía guardar una concesión
--    sin justificación. Ahora lo exige la DB en cualquier escritura.
-- 3. Notificación al cliente como gate de cierre (obs. #3, API Q1 §5.10.3):
--    una NC de origen 'cliente' con cliente_notificado = false (pendiente)
--    no puede cerrarse. NULL (N/A: producto no entregado) sí puede.
--
-- Orden de deploy (PG-14): esta migración ANTES del push del frontend.
-- ============================================================================

-- ─── 1. Tipo 'plano' ────────────────────────────────────────────────────────
ALTER TABLE public.documentos_controlados
  DROP CONSTRAINT IF EXISTS documentos_controlados_tipo_check;
ALTER TABLE public.documentos_controlados
  ADD CONSTRAINT documentos_controlados_tipo_check
  CHECK (tipo IN ('manual','procedimiento','instructivo','formulario','plano',
                  'wps','pqr','wpq','pqp','plan_contingencia','otro'));

-- ─── 2. Guard de concesión en cualquier escritura ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nc_concesion_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.disposicion = 'concesion'
     AND (NEW.justificacion IS NULL OR btrim(NEW.justificacion) = '') THEN
    RAISE EXCEPTION 'La concesión de la NC % requiere justificación documentada '
      '(API Q1 5.10)', COALESCE(NEW.numero::text, '(nueva)');
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_concesion_guard() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_nc_concesion_guard ON no_conformidades;
CREATE TRIGGER trg_nc_concesion_guard
  BEFORE INSERT OR UPDATE ON no_conformidades
  FOR EACH ROW EXECUTE FUNCTION public.fn_nc_concesion_guard();

-- ─── 3. Cierre exige notificación al cliente resuelta ───────────────────────
-- Reemplaza fn_nc_cierre_guard de la 043 agregando la regla de notificación.
CREATE OR REPLACE FUNCTION public.fn_nc_cierre_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'cerrada' AND OLD.estado IS DISTINCT FROM 'cerrada' THEN
    IF NEW.disposicion IS NULL THEN
      RAISE EXCEPTION 'La NC % no se puede cerrar sin disposición '
        '(retrabajo/reproceso/rechazo/concesión/devolución)', NEW.numero;
    END IF;
    IF NEW.origen_tipo = 'cliente' AND NEW.cliente_notificado IS FALSE THEN
      RAISE EXCEPTION 'La NC % es de origen cliente y la notificación al cliente '
        'está pendiente; notificar antes de cerrar (API Q1 5.10.3)', NEW.numero;
    END IF;
    NEW.cerrada_at := COALESCE(NEW.cerrada_at, now());
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_cierre_guard() FROM PUBLIC, anon;
-- El trigger trg_nc_cierre_guard (BEFORE UPDATE OF estado, mig 043) ya apunta
-- a esta función; no hace falta recrearlo.
