-- ═══════════════════════════════════════════════════════════════════
-- 016_facturas_emitidas.sql
-- Tabla de comprobantes electrónicos emitidos vía AFIP/ARCA (WSFEv1).
-- Una fila por cada CAE recibido del microservicio vitalmet-billing.
--
-- Relación con `ventas`:
--   * `facturas_emitidas.venta_id` → FK opcional a la venta origen
--   * `ventas.factura_emitida_id` → FK al comprobante emitido (one-to-one,
--     pero permitimos NULL para ventas no facturadas o reemitidas)
--
-- RLS aislado por empresa_id (mismo patrón que migrations/006).
-- ═══════════════════════════════════════════════════════════════════

-- ─── Tabla principal ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS facturas_emitidas (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  venta_id            uuid REFERENCES ventas(id) ON DELETE SET NULL,

  -- Datos AFIP del CAE
  cae                 text NOT NULL,
  cae_vto             date NOT NULL,
  numero              int  NOT NULL,
  punto_venta         int  NOT NULL,
  tipo_comprobante    int  NOT NULL,
    -- Códigos AFIP: 1=FacA, 6=FacB, 11=FacC, 51=FacM, 201=FCE-A, etc.
  fecha               date NOT NULL,

  -- Totales (todos los importes en moneda del comprobante)
  imp_neto            numeric(14,2) NOT NULL DEFAULT 0,
  imp_iva             numeric(14,2) NOT NULL DEFAULT 0,
  imp_total           numeric(14,2) NOT NULL DEFAULT 0,
  moneda              text          NOT NULL DEFAULT 'PES',
  cotizacion_moneda   numeric(14,4) NOT NULL DEFAULT 1.0,

  -- Datos del receptor
  doc_tipo            int  NOT NULL,
    -- 80=CUIT, 86=CUIL, 96=DNI, 99=Consumidor final
  doc_nro             text NOT NULL,

  -- Resultado y metadata
  resultado           text,
    -- AFIP: 'A'=Aprobado, 'P'=Parcial, 'R'=Rechazado
  observaciones       jsonb,
    -- Array de observaciones que AFIP devuelve (ej. percepciones aplicadas)
  qr_url              text,
    -- URL oficial AFIP del QR (RG 4892/2020) para impresión
  pdf_url             text,
    -- URL opcional al PDF generado (puede vivir en Supabase Storage)
  afip_environment    text NOT NULL
    CHECK (afip_environment IN ('homologacion','produccion')),

  -- Auditoría
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES usuarios(id) ON DELETE SET NULL,
  raw_response        jsonb
    -- Snapshot completo de la respuesta AFIP por si se necesita debugging
);

COMMENT ON TABLE facturas_emitidas IS
  'Comprobantes electrónicos emitidos a AFIP. Una fila por CAE.';
COMMENT ON COLUMN facturas_emitidas.afip_environment IS
  'En homologacion las facturas NO son legales — son testing contra wswhomo.afip.gov.ar';

-- ─── Constraint de unicidad: (empresa, PV, tipo, número, ambiente) ───
-- En homologación y producción los números son independientes, por eso
-- incluimos afip_environment en la clave.
CREATE UNIQUE INDEX IF NOT EXISTS uq_facturas_emitidas_numero
  ON facturas_emitidas (empresa_id, punto_venta, tipo_comprobante, numero, afip_environment);

-- ─── Índices de consulta ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_facturas_emitidas_venta
  ON facturas_emitidas (venta_id) WHERE venta_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_facturas_emitidas_empresa_fecha
  ON facturas_emitidas (empresa_id, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_facturas_emitidas_doc
  ON facturas_emitidas (empresa_id, doc_nro);

-- ─── FK desde ventas → facturas_emitidas ─────────────────────────────
ALTER TABLE ventas
  ADD COLUMN IF NOT EXISTS factura_emitida_id uuid
  REFERENCES facturas_emitidas(id) ON DELETE SET NULL;

COMMENT ON COLUMN ventas.factura_emitida_id IS
  'CAE emitido por AFIP para esta venta. NULL = no facturada todavía.';

CREATE INDEX IF NOT EXISTS idx_ventas_factura_emitida
  ON ventas (factura_emitida_id) WHERE factura_emitida_id IS NOT NULL;

-- ─── RLS — aislamiento por empresa_id ────────────────────────────────
ALTER TABLE facturas_emitidas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS facturas_emitidas_select ON facturas_emitidas;
CREATE POLICY facturas_emitidas_select ON facturas_emitidas
  FOR SELECT
  USING (empresa_id = public.current_empresa_id());

DROP POLICY IF EXISTS facturas_emitidas_insert ON facturas_emitidas;
CREATE POLICY facturas_emitidas_insert ON facturas_emitidas
  FOR INSERT
  WITH CHECK (empresa_id = public.current_empresa_id());

DROP POLICY IF EXISTS facturas_emitidas_update ON facturas_emitidas;
CREATE POLICY facturas_emitidas_update ON facturas_emitidas
  FOR UPDATE
  USING (empresa_id = public.current_empresa_id())
  WITH CHECK (empresa_id = public.current_empresa_id());

DROP POLICY IF EXISTS facturas_emitidas_delete ON facturas_emitidas;
CREATE POLICY facturas_emitidas_delete ON facturas_emitidas
  FOR DELETE
  USING (empresa_id = public.current_empresa_id());
