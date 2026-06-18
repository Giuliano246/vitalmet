-- ═══════════════════════════════════════════════════════════════════
-- 036_extracto_constraints.sql
-- Integridad de la conciliación bancaria (refuerza la mig 035):
--   1. FK extracto_bancario.asiento_linea_id → asiento_lineas(id)
--      ON DELETE SET NULL: si el asiento se regenera/borra, el vínculo
--      se limpia en vez de quedar colgado.
--   2. Índice UNIQUE PARCIAL sobre asiento_linea_id (solo no-NULL): una
--      línea del libro se concilia con a lo sumo UNA línea del extracto.
--      Parcial (WHERE ... IS NOT NULL) para permitir muchas líneas sin
--      conciliar (NULL). NO usar NULLS NOT DISTINCT (bloquearía eso).
--
-- Requiere: 035 (extracto_bancario), asiento_lineas (mig base/023).
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- 1) FK con ON DELETE SET NULL
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fk_extracto_asiento_linea') THEN
    ALTER TABLE public.extracto_bancario
      ADD CONSTRAINT fk_extracto_asiento_linea
      FOREIGN KEY (asiento_linea_id)
      REFERENCES public.asiento_lineas(id) ON DELETE SET NULL;
  END IF;
END$$;

-- 2) Único parcial: cada línea del libro, a lo sumo una vez en el extracto
CREATE UNIQUE INDEX IF NOT EXISTS uq_extracto_asiento_linea
  ON public.extracto_bancario (asiento_linea_id)
  WHERE asiento_linea_id IS NOT NULL;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
-- SELECT conname FROM pg_constraint WHERE conname='fk_extracto_asiento_linea';
-- SELECT indexname FROM pg_indexes WHERE indexname='uq_extracto_asiento_linea';
-- Esperado: 1 fila cada una.
