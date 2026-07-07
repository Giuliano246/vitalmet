-- 049_precios_base.sql — Precios base por producto (Paquete 6A)
-- Un precio de lista en USD por pieza. El precio de venta se resuelve:
-- último precio al cliente → precio base → precio del PT.
BEGIN;

CREATE TABLE IF NOT EXISTS precios_base (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  pieza text NOT NULL,
  precio_usd numeric NOT NULL DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  UNIQUE(empresa_id, pieza)
);

ALTER TABLE precios_base ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON precios_base;
CREATE POLICY tenant_isolation ON precios_base FOR ALL TO authenticated
  USING (empresa_id = public.current_empresa_id())
  WITH CHECK (empresa_id = public.current_empresa_id());

DROP TRIGGER IF EXISTS trg_precios_base_updated ON precios_base;
CREATE TRIGGER trg_precios_base_updated
  BEFORE UPDATE ON precios_base
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

COMMIT;

-- Verificación:
-- SELECT tablename, rowsecurity FROM pg_tables WHERE tablename='precios_base';
-- SELECT policyname FROM pg_policies WHERE tablename='precios_base';
