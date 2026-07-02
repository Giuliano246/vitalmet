-- ═══════════════════════════════════════════════════════════════════
-- 045_colada_resync.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, complemento del GAP 1.
--
-- Contexto (hallazgo de la Fase 2 frontend): los campos
-- certificados.colada y barras.nro_colada estaban etiquetados "Nro OC"
-- en la UI, así que el dato cargado hasta hoy es el número de orden de
-- compra, NO el heat number del MTR. Decisión (2026-07-01, Giuliano):
-- las etiquetas pasan a "Colada (heat nº)" y el histórico se corrige a
-- mano con el PDF del MTR a la vista.
--
-- Qué agrega:
--   fn_barra_colada_sync / trg_barra_colada_sync — cuando se corrige
--   barras.nro_colada, el cambio se propaga a productos_terminados.
--   nro_colada de los PT de esa barra (el trigger de 037 solo copia al
--   crear el PT o al cambiarle la barra; este cubre la regularización).
--
-- Cláusulas: ISO 9001:2015 §8.5.2, API Q1 §5.7.6.
-- Requiere: 037 (productos_terminados.nro_colada).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_barra_colada_sync() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  UPDATE productos_terminados
  SET nro_colada = NEW.nro_colada
  WHERE barra_id = NEW.id AND nro_colada IS DISTINCT FROM NEW.nro_colada;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_barra_colada_sync() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_barra_colada_sync ON barras;
CREATE TRIGGER trg_barra_colada_sync
  AFTER UPDATE OF nro_colada ON barras
  FOR EACH ROW EXECUTE FUNCTION public.fn_barra_colada_sync();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_barra_colada_sync';
--
-- Para auditar la regularización pendiente (qué "coladas" parecen OC):
-- SELECT lote, nro_colada FROM barras
--  WHERE nro_colada ILIKE 'OC%' OR nro_colada ILIKE '%-%-%' ORDER BY lote;
-- SELECT nro, colada FROM certificados
--  WHERE colada ILIKE 'OC%' OR colada ILIKE '%-%-%' ORDER BY nro;
