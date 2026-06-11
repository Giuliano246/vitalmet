-- ═══════════════════════════════════════════════════════════════════
-- 025_cotizador.sql
-- Cotizador con costeo estimado (fase 3, mes 2 — roadmap auditoría)
--
-- Una sola columna: el costo unitario estimado de cada ítem cotizado.
-- Se autocompleta en el modal con el costo real histórico del producto
-- (computeCostoPT: MP + tiempos + overhead) y se puede pisar a mano
-- para piezas nuevas. Queda persistido para poder comparar después
-- margen cotizado vs. margen real.
--
-- Aditiva, retrocompatible, idempotente.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE presupuesto_items ADD COLUMN IF NOT EXISTS costo_estimado numeric;
