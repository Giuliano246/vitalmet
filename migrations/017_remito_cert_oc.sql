-- ═══════════════════════════════════════════════════════════
-- Migración 017 — Remito + Certificado en OC y Recepción
-- Agrega trazabilidad de documentos de proveedor:
--   · ordenes_compra.remito_nro (texto libre)
--   · ordenes_compra.certificado_id (FK a certificados, opcional)
--   · recepciones_oc.remito_nro (texto libre)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE ordenes_compra
  ADD COLUMN IF NOT EXISTS remito_nro text,
  ADD COLUMN IF NOT EXISTS certificado_id uuid REFERENCES certificados(id) ON DELETE SET NULL;

ALTER TABLE recepciones_oc
  ADD COLUMN IF NOT EXISTS remito_nro text;

CREATE INDEX IF NOT EXISTS idx_oc_certificado ON ordenes_compra (certificado_id);
CREATE INDEX IF NOT EXISTS idx_oc_remito ON ordenes_compra (remito_nro) WHERE remito_nro IS NOT NULL;
