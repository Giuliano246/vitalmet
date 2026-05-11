-- ═══════════════════════════════════════════════════════════════════
-- 012_config_contable.sql
-- Crea la tabla de imputación contable: define qué cuentas usar
-- automáticamente cuando el sistema genera asientos desde ventas,
-- compras, cobranzas y pagos.
--
-- 1 registro por empresa. Si una cuenta queda en NULL, la auto-
-- generación correspondiente queda deshabilitada (no rompe nada).
--
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS config_contable (
  empresa_id uuid PRIMARY KEY REFERENCES empresas(id) ON DELETE CASCADE,
  -- Ventas
  cta_ventas_default     uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_deudores           uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_iva_debito         uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  precios_incluyen_iva   boolean NOT NULL DEFAULT false,
  iva_alicuota           numeric(5,4) NOT NULL DEFAULT 0.21 CHECK (iva_alicuota >= 0 AND iva_alicuota <= 1),
  -- Compras
  cta_iva_credito        uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_proveedores        uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_compra_insumos     uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_compra_mp          uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_compra_herramientas uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_compra_servicios   uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  -- Cobros / Pagos / Cierre
  cta_caja_default       uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  cta_banco_default      uuid REFERENCES cuentas_contables(id) ON DELETE SET NULL,
  -- metadata
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS por empresa
ALTER TABLE config_contable ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS config_contable_select ON config_contable;
DROP POLICY IF EXISTS config_contable_insert ON config_contable;
DROP POLICY IF EXISTS config_contable_update ON config_contable;
DROP POLICY IF EXISTS config_contable_delete ON config_contable;

CREATE POLICY config_contable_select ON config_contable
  FOR SELECT USING (empresa_id = public.current_empresa_id());
CREATE POLICY config_contable_insert ON config_contable
  FOR INSERT WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY config_contable_update ON config_contable
  FOR UPDATE USING (empresa_id = public.current_empresa_id())
              WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY config_contable_delete ON config_contable
  FOR DELETE USING (empresa_id = public.current_empresa_id());

-- Insert defaults para Vitalmet SA usando los códigos del plan sembrado en 007
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  cuenta_id_record uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM config_contable WHERE empresa_id = emp_id) THEN
    INSERT INTO config_contable (
      empresa_id,
      cta_ventas_default,
      cta_deudores,
      cta_iva_debito,
      precios_incluyen_iva,
      iva_alicuota,
      cta_iva_credito,
      cta_proveedores,
      cta_compra_insumos,
      cta_compra_mp,
      cta_compra_herramientas,
      cta_compra_servicios,
      cta_caja_default,
      cta_banco_default
    ) VALUES (
      emp_id,
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='411001'),  -- VENTAS BUENOS AIRES
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='112016'),  -- DEUDORES POR VENTAS
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='213003'),  -- IVA DEBITO
      false,
      0.21,
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='113003'),  -- IVA CREDITO FISCAL
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='211002'),  -- PROVEEDORES
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='114001'),  -- Mercaderias
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='114002'),  -- MATERIA PRIMA
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='122008'),  -- Herramientas
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='421014'),  -- TRABAJOS DE TERCEROS
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='111001'),  -- CAJA
      (SELECT id FROM cuentas_contables WHERE empresa_id=emp_id AND codigo='111003')   -- BANCO HSBC
    );
    RAISE NOTICE 'Migration 012: config_contable inicializada para empresa %', emp_id;
  ELSE
    RAISE NOTICE 'Migration 012: config_contable ya existía, no se modifica';
  END IF;
END $$;
