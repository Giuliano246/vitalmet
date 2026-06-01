-- ═══════════════════════════════════════════════════════════
-- Migración 018 — Columnas faltantes en certificados
-- El front guarda metros / fecha / file_data / file_name en
-- certificados, pero la tabla fue creada a mano sin esas
-- columnas. Las agregamos como nullable (IF NOT EXISTS para
-- ser idempotente).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE certificados
  ADD COLUMN IF NOT EXISTS metros     float8,
  ADD COLUMN IF NOT EXISTS fecha      date,
  ADD COLUMN IF NOT EXISTS file_data  text,
  ADD COLUMN IF NOT EXISTS file_name  text;

-- Forzar reload del schema cache de PostgREST (Supabase).
NOTIFY pgrst, 'reload schema';
