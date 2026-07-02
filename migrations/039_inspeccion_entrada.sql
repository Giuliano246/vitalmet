-- ═══════════════════════════════════════════════════════════════════
-- 039_inspeccion_entrada.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 3.
-- Inspección de entrada con cuarentena: el material recibido queda
-- retenido hasta que la inspección lo acepta, y una barra no aceptada
-- no se puede consumir en producción.
--
-- Qué agrega:
--   1. recepciones_oc.estado_inspeccion ('cuarentena'|'aceptado'|
--      'rechazado', default 'cuarentena') + inspeccionado_por +
--      fecha_inspeccion. Las recepciones EXISTENTES se backfillean
--      como 'aceptado' (ya están en uso — no destructivo).
--   2. barras.estado_calidad (mismos valores; las barras existentes y
--      las creadas a mano nacen 'aceptado' para no romper el flujo
--      actual; las creadas vía recepción quedan sincronizadas con la
--      inspección por trigger — ver punto 4).
--   3. fn_recepcion_inspeccion: al aceptar una recepción de materia
--      prima exige MTR adjunto (certificado_id en la recepción o en su
--      OC) y estampa quién/cuándo inspeccionó.
--   4. fn_recepcion_sync_barra: la barra vinculada a la recepción
--      hereda el estado de inspección (cuarentena al recibir, aceptado/
--      rechazado al inspeccionar).
--   5. consumir_barra() REEMPLAZADA: no consume barras cuyo
--      estado_calidad no sea 'aceptado' (devolver kg sigue permitido).
--
-- Cláusulas: API Q1 §5.7.4 (verificación de producto comprado),
--            ISO 9001:2015 §8.4.2 / §8.6.
-- Requiere: 002 (recepciones_oc), 023 (consumir_barra, fn_audit).
-- ATENCIÓN — ventana de deploy: después de correr esto y HASTA deployar
-- el frontend de esta fase, una recepción nueva de MP deja la barra en
-- 'cuarentena' sin UI para liberarla (se libera con
-- UPDATE recepciones_oc SET estado_inspeccion='aceptado' WHERE id=...).
-- Correr esta migración junto con el deploy del frontend.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Estado de inspección en la recepción ─────────────────────────
ALTER TABLE recepciones_oc ADD COLUMN IF NOT EXISTS estado_inspeccion text;
ALTER TABLE recepciones_oc ADD COLUMN IF NOT EXISTS inspeccionado_por uuid;
ALTER TABLE recepciones_oc ADD COLUMN IF NOT EXISTS fecha_inspeccion timestamptz;

-- Backfill: lo ya recibido se considera aceptado (está consumido/en uso)
UPDATE recepciones_oc SET estado_inspeccion = 'aceptado' WHERE estado_inspeccion IS NULL;

ALTER TABLE recepciones_oc ALTER COLUMN estado_inspeccion SET DEFAULT 'cuarentena';
ALTER TABLE recepciones_oc ALTER COLUMN estado_inspeccion SET NOT NULL;
ALTER TABLE recepciones_oc DROP CONSTRAINT IF EXISTS recepciones_inspeccion_valida;
ALTER TABLE recepciones_oc ADD CONSTRAINT recepciones_inspeccion_valida
  CHECK (estado_inspeccion IN ('cuarentena','aceptado','rechazado'));

-- ─── 2. Estado de calidad en barras ──────────────────────────────────
-- Default 'aceptado': el alta manual de barras (stock histórico) sigue
-- funcionando. El camino recepción→barra queda en cuarentena por el
-- trigger del punto 4. El procedimiento de Fase 3 fija que la MP
-- crítica entra SOLO por recepción de OC.
ALTER TABLE barras ADD COLUMN IF NOT EXISTS estado_calidad text;
UPDATE barras SET estado_calidad = 'aceptado' WHERE estado_calidad IS NULL;
ALTER TABLE barras ALTER COLUMN estado_calidad SET DEFAULT 'aceptado';
ALTER TABLE barras ALTER COLUMN estado_calidad SET NOT NULL;
ALTER TABLE barras DROP CONSTRAINT IF EXISTS barras_estado_calidad_valido;
ALTER TABLE barras ADD CONSTRAINT barras_estado_calidad_valido
  CHECK (estado_calidad IN ('cuarentena','aceptado','rechazado'));

-- ─── 3. Guard de inspección: MTR obligatorio para aceptar MP ─────────
CREATE OR REPLACE FUNCTION public.fn_recepcion_inspeccion() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  v_tipo text;
  v_cert_oc uuid;
BEGIN
  -- Estampar quién/cuándo cada vez que cambia el estado de inspección
  IF TG_OP = 'INSERT' OR NEW.estado_inspeccion IS DISTINCT FROM OLD.estado_inspeccion THEN
    IF NEW.estado_inspeccion IN ('aceptado','rechazado') THEN
      NEW.inspeccionado_por := COALESCE(NEW.inspeccionado_por, auth.uid());
      NEW.fecha_inspeccion  := COALESCE(NEW.fecha_inspeccion, now());
    END IF;
  END IF;

  -- Aceptar materia prima exige el MTR (en la recepción o en la OC)
  IF NEW.estado_inspeccion = 'aceptado'
     AND (TG_OP = 'INSERT' OR OLD.estado_inspeccion IS DISTINCT FROM 'aceptado') THEN
    SELECT oi.tipo, oc.certificado_id INTO v_tipo, v_cert_oc
    FROM oc_items oi JOIN ordenes_compra oc ON oc.id = oi.oc_id
    WHERE oi.id = NEW.oc_item_id;
    IF v_tipo = 'materia_prima' AND NEW.certificado_id IS NULL AND v_cert_oc IS NULL THEN
      RAISE EXCEPTION 'Inspección de entrada: no se puede aceptar materia prima sin el certificado de material (MTR) adjunto. Cargalo en Certificados MTC y vinculalo a la recepción o a la OC.';
    END IF;
  END IF;

  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_recepcion_inspeccion() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_recepcion_inspeccion ON recepciones_oc;
CREATE TRIGGER trg_recepcion_inspeccion
  BEFORE INSERT OR UPDATE ON recepciones_oc
  FOR EACH ROW EXECUTE FUNCTION public.fn_recepcion_inspeccion();

-- ─── 4. La barra hereda el estado de inspección de su recepción ──────
CREATE OR REPLACE FUNCTION public.fn_recepcion_sync_barra() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.barra_id IS NOT NULL THEN
    UPDATE barras SET estado_calidad = NEW.estado_inspeccion
    WHERE id = NEW.barra_id AND estado_calidad IS DISTINCT FROM NEW.estado_inspeccion;
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_recepcion_sync_barra() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_recepcion_sync_barra ON recepciones_oc;
CREATE TRIGGER trg_recepcion_sync_barra
  AFTER INSERT OR UPDATE OF estado_inspeccion, barra_id ON recepciones_oc
  FOR EACH ROW EXECUTE FUNCTION public.fn_recepcion_sync_barra();

-- ─── 5. consumir_barra: gate de calidad ──────────────────────────────
-- Mismo cuerpo que 023, con un solo agregado: consumir (p_kg > 0)
-- exige estado_calidad = 'aceptado'. Devolver kg (p_kg < 0) y consultar
-- (p_kg = 0) siguen permitidos para no romper la edición de OPs.
CREATE OR REPLACE FUNCTION public.consumir_barra(p_barra_id uuid, p_kg numeric)
RETURNS numeric LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_kg numeric; v_lote text; v_calidad text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_kg, 0) = 0 THEN
    SELECT kg_disponibles INTO v_kg FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    RETURN v_kg;
  END IF;
  IF p_kg > 0 THEN
    SELECT lote, estado_calidad INTO v_lote, v_calidad
    FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    IF v_lote IS NULL THEN RAISE EXCEPTION 'Barra no encontrada'; END IF;
    IF v_calidad IS DISTINCT FROM 'aceptado' THEN
      RAISE EXCEPTION 'La barra % está en % — requiere inspección de entrada aceptada antes de usarse en producción', v_lote, COALESCE(v_calidad, 'cuarentena');
    END IF;
  END IF;
  UPDATE barras SET kg_disponibles = kg_disponibles - p_kg
  WHERE id = p_barra_id AND empresa_id = emp AND kg_disponibles - p_kg >= 0
  RETURNING kg_disponibles INTO v_kg;
  IF v_kg IS NULL THEN
    SELECT lote, kg_disponibles INTO v_lote, v_kg FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    IF v_lote IS NULL THEN RAISE EXCEPTION 'Barra no encontrada'; END IF;
    RAISE EXCEPTION 'Stock insuficiente en %: disponible % mts', v_lote, v_kg;
  END IF;
  RETURN v_kg;
END $$;
REVOKE ALL ON FUNCTION public.consumir_barra(uuid, numeric) FROM public;
REVOKE EXECUTE ON FUNCTION public.consumir_barra(uuid, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.consumir_barra(uuid, numeric) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Nada quedó en cuarentena tras el backfill:
-- SELECT estado_inspeccion, count(*) FROM recepciones_oc GROUP BY 1;
-- SELECT estado_calidad, count(*) FROM barras GROUP BY 1;
--
-- 2. Triggers y RPC:
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname IN ('trg_recepcion_inspeccion','trg_recepcion_sync_barra')
--    AND NOT tgisinternal;
--
-- 3. Smoke test del gate de consumo (barra de prueba en cuarentena →
--    consumir_barra debe fallar; limpia al final):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   b uuid;
-- BEGIN
--   INSERT INTO barras (empresa_id, lote, material, kg_disponibles, estado_calidad)
--   VALUES (emp, '__TEST-QC-1__', 'AISI 4130', 100, 'cuarentena') RETURNING id INTO b;
--   BEGIN
--     PERFORM public.consumir_barra(b, 10);
--     RAISE EXCEPTION 'ERROR: el gate de cuarentena NO funcionó';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: consumo bloqueado (%)', SQLERRM;
--   END;
--   DELETE FROM barras WHERE id = b;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
