-- ═══════════════════════════════════════════════════════════
-- Migración 003 — Costos + Presupuestos + Reserva de stock
-- ═══════════════════════════════════════════════════════════

-- Config de costos a nivel empresa
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS tarifa_operario_usd_h numeric DEFAULT 18;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS overhead_pct numeric DEFAULT 15;

-- Costo de compra por unidad (USD/kg o USD/pieza) en cada barra
ALTER TABLE barras ADD COLUMN IF NOT EXISTS costo_usd_unidad numeric;

-- Costo unitario calculado cacheado en PT (se recalcula al pedir)
ALTER TABLE productos_terminados ADD COLUMN IF NOT EXISTS costo_mp_unit numeric;
ALTER TABLE productos_terminados ADD COLUMN IF NOT EXISTS costo_tiempo_unit numeric;
ALTER TABLE productos_terminados ADD COLUMN IF NOT EXISTS costo_total_unit numeric;

-- ────────────── PRESUPUESTOS ──────────────
CREATE TABLE IF NOT EXISTS presupuestos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  nro text NOT NULL,
  cliente text NOT NULL,
  cuit text,
  fecha date NOT NULL,
  fecha_vencimiento date,
  condicion_pago text,
  subtotal numeric DEFAULT 0,
  descuento_pct numeric DEFAULT 0,
  total numeric DEFAULT 0,
  estado text DEFAULT 'borrador',       -- borrador | enviado | aprobado | rechazado | convertido | vencido
  venta_id uuid REFERENCES ventas(id),   -- si se convirtió
  observaciones text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS presupuesto_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  presupuesto_id uuid NOT NULL REFERENCES presupuestos(id) ON DELETE CASCADE,
  producto_id uuid REFERENCES productos_terminados(id),
  pieza text NOT NULL,
  descripcion text,
  cantidad numeric NOT NULL,
  precio_unitario numeric NOT NULL,
  subtotal numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_presupuestos_empresa_fecha ON presupuestos (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_presupuestos_estado ON presupuestos (estado);
CREATE INDEX IF NOT EXISTS idx_presupuesto_items_presup ON presupuesto_items (presupuesto_id);

-- ────────────── RESERVA DE STOCK ──────────────
-- Vista que calcula stock disponible por PT
-- Reservado = unidades en ventas con estado distinto de 'entregado','facturado','anulada'
CREATE OR REPLACE VIEW pt_stock_disponible AS
SELECT
  pt.id AS producto_id,
  pt.empresa_id,
  pt.pieza,
  pt.cantidad AS stock_total,
  COALESCE((
    SELECT SUM(vi.cantidad)
    FROM venta_items vi
    JOIN ventas v ON v.id = vi.venta_id
    WHERE vi.producto_id = pt.id
      AND v.estado NOT IN ('entregado','facturado','anulada')
  ), 0) AS reservado,
  pt.cantidad - COALESCE((
    SELECT SUM(vi.cantidad)
    FROM venta_items vi
    JOIN ventas v ON v.id = vi.venta_id
    WHERE vi.producto_id = pt.id
      AND v.estado NOT IN ('entregado','facturado','anulada')
  ), 0) AS disponible
FROM productos_terminados pt;

-- NOTA: RLS desactivado igual que el resto del sistema.
