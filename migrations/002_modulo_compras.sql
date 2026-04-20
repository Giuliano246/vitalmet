-- ═══════════════════════════════════════════════════════════
-- Migración 002 — Módulo Compras
-- Proveedores + Órdenes de Compra + Items + Recepciones parciales
-- Todo en USD
-- ═══════════════════════════════════════════════════════════

-- Proveedores (espejo de clientes pero de compras)
CREATE TABLE IF NOT EXISTS proveedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  nombre text NOT NULL,
  cuit text,
  contacto text,
  email text,
  telefono text,
  direccion text,
  condicion_pago_default text,          -- "30 dias", "contado", etc.
  saldo_actual numeric DEFAULT 0,       -- deuda con proveedor (+ debemos, - a favor)
  observaciones text,
  activo boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Órdenes de compra
CREATE TABLE IF NOT EXISTS ordenes_compra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  nro text NOT NULL,
  proveedor_id uuid NOT NULL REFERENCES proveedores(id),
  fecha date NOT NULL,
  fecha_entrega_esperada date,
  condicion_pago text,
  subtotal numeric DEFAULT 0,
  total numeric DEFAULT 0,
  estado text DEFAULT 'borrador',       -- borrador | enviada | confirmada | recibida_parcial | recibida | facturada | anulada
  factura_nro text,
  factura_fecha date,
  factura_vto date,
  observaciones text,
  created_at timestamptz DEFAULT now()
);

-- Items de OC (lo que se compra)
CREATE TABLE IF NOT EXISTS oc_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  oc_id uuid NOT NULL REFERENCES ordenes_compra(id) ON DELETE CASCADE,
  tipo text NOT NULL DEFAULT 'otro',    -- materia_prima | insumo | herramienta | servicio | otro
  descripcion text NOT NULL,
  material text,                        -- si tipo=materia_prima → AISI 316, etc.
  perfil text,                          -- si tipo=materia_prima → redondo, chapa, etc.
  diametro text,
  cantidad numeric NOT NULL,
  unidad text DEFAULT 'un',             -- kg | un | mts | ltrs | hs | global
  cantidad_recibida numeric DEFAULT 0,
  precio_unitario numeric NOT NULL,
  subtotal numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Recepciones (parciales o totales)
CREATE TABLE IF NOT EXISTS recepciones_oc (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  oc_item_id uuid NOT NULL REFERENCES oc_items(id) ON DELETE CASCADE,
  fecha date NOT NULL,
  cantidad_recibida numeric NOT NULL,
  certificado_id uuid REFERENCES certificados(id),
  barra_id uuid REFERENCES barras(id),   -- si la recepción generó una barra en MP
  observaciones text,
  created_at timestamptz DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_proveedores_empresa ON proveedores (empresa_id);
CREATE INDEX IF NOT EXISTS idx_oc_empresa_fecha ON ordenes_compra (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_oc_proveedor ON ordenes_compra (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_oc_estado ON ordenes_compra (estado);
CREATE INDEX IF NOT EXISTS idx_oc_items_oc ON oc_items (oc_id);
CREATE INDEX IF NOT EXISTS idx_recepciones_item ON recepciones_oc (oc_item_id);

-- Vista: items con estado de recepción
CREATE OR REPLACE VIEW oc_items_con_recepcion AS
SELECT
  i.*,
  (i.cantidad - i.cantidad_recibida) AS cantidad_pendiente,
  CASE
    WHEN i.cantidad_recibida = 0 THEN 'pendiente'
    WHEN i.cantidad_recibida < i.cantidad THEN 'parcial'
    ELSE 'completo'
  END AS estado_recepcion
FROM oc_items i;

-- Agregar columna proveedor_id a barras (opcional: vincular barra con proveedor real)
ALTER TABLE barras ADD COLUMN IF NOT EXISTS proveedor_id uuid REFERENCES proveedores(id);
ALTER TABLE barras ADD COLUMN IF NOT EXISTS oc_id uuid REFERENCES ordenes_compra(id);

-- NOTA: RLS desactivado igual que el resto del sistema.
