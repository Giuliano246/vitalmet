-- ═══════════════════════════════════════════════════════════════════
-- 021_reorden_materiales.sql
-- Soporte para reorden con safety stock real por material.
--
-- Solo AGREGA columnas a `materiales` (operación aditiva, no toca datos
-- existentes → riesgo nulo, no necesita snapshot). Todo el cálculo de
-- consumo, lead time y punto de reorden se hace en el frontend a partir
-- de datos que ya existen (ordenes_produccion, ordenes_compra, recepciones_oc).
--
--   lead_time_dias : fallback de lead time (días) cuando no hay suficientes
--                    recepciones de compra del material para derivarlo solo.
--   nivel_servicio : objetivo de nivel de servicio (0.90 / 0.95 / 0.975)
--                    para elegir el Z de la fórmula de safety stock.
--
-- Idempotente. Correr en Supabase SQL Editor (rol service).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.materiales
  ADD COLUMN IF NOT EXISTS lead_time_dias int;

ALTER TABLE public.materiales
  ADD COLUMN IF NOT EXISTS nivel_servicio numeric(4,2) DEFAULT 0.95;

-- Asegura un valor por defecto en filas ya existentes que quedaron en NULL
UPDATE public.materiales
SET nivel_servicio = 0.95
WHERE nivel_servicio IS NULL;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='materiales'
--   AND column_name IN ('lead_time_dias','nivel_servicio');
