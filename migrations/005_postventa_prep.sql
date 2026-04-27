-- ═══════════════════════════════════════════════════════════
-- Migración 005 — Preparación de esquema para postventa automático (n8n)
--
-- Lo que hace:
--   1. Agrega updated_at a ventas + trigger (para polling incremental)
--   2. Agrega trigger_estado + trigger_delay_days a email_templates
--      (para que cada template sepa qué estado lo dispara)
--   3. Agrega trigger_estado a email_log y email_queue (anti-duplicación)
--   4. Agrega catalogo_url a mailings_config
--   5. Crea la vista ventas_pendientes_mail — n8n pollea solo esta vista
--
-- Ejecutar una vez en Supabase SQL Editor. Idempotente.
-- ═══════════════════════════════════════════════════════════


-- ─── 0. Función touch_updated_at (si no existe de 004) ────────
-- CREATE OR REPLACE = idempotente, no rompe si ya está.
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ─── 1. updated_at en ventas (polling incremental) ────────────
ALTER TABLE ventas
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Backfill para filas existentes: usar fecha del pedido
UPDATE ventas
SET updated_at = COALESCE(fecha, now())
WHERE updated_at IS NULL;

-- Trigger que refresca updated_at en cada UPDATE (touch_updated_at ya existe en 004)
DROP TRIGGER IF EXISTS trg_ventas_updated ON ventas;
CREATE TRIGGER trg_ventas_updated
  BEFORE UPDATE ON ventas
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Índice para que n8n filtre rápido por estado + orden temporal
CREATE INDEX IF NOT EXISTS idx_ventas_estado_updated
  ON ventas (empresa_id, estado, updated_at DESC);


-- ─── 2. email_templates: disparadores automáticos por estado ───
ALTER TABLE email_templates
  ADD COLUMN IF NOT EXISTS trigger_estado     text,
  ADD COLUMN IF NOT EXISTS trigger_delay_days int DEFAULT 0;

COMMENT ON COLUMN email_templates.trigger_estado IS
  'Estado de ventas que dispara este template automáticamente (aprobado_cliente, entregado, facturado, etc). NULL = template manual.';
COMMENT ON COLUMN email_templates.trigger_delay_days IS
  'Días de espera después del cambio de estado antes de enviar. 0 = inmediato, 14 = seguimiento post-entrega.';

-- Índice parcial: solo los templates automáticos
CREATE INDEX IF NOT EXISTS idx_email_templates_trigger
  ON email_templates (empresa_id, trigger_estado, activo)
  WHERE trigger_estado IS NOT NULL;


-- ─── 3. email_log y email_queue: trazar qué estado disparó el mail ──
-- Necesario para la anti-duplicación: "¿ya mandé un mail para este estado en esta venta?"
ALTER TABLE email_log   ADD COLUMN IF NOT EXISTS trigger_estado text;
ALTER TABLE email_queue ADD COLUMN IF NOT EXISTS trigger_estado text;

CREATE INDEX IF NOT EXISTS idx_email_log_venta_trigger
  ON email_log (venta_id, trigger_estado)
  WHERE venta_id IS NOT NULL;


-- ─── 4. mailings_config: URL del catálogo ─────────────────────
ALTER TABLE mailings_config
  ADD COLUMN IF NOT EXISTS catalogo_url text;

COMMENT ON COLUMN mailings_config.catalogo_url IS
  'URL pública del catálogo PDF. Disponible como placeholder {catalogo_url} en los templates.';


-- ─── 5. Vista helper: "ventas que necesitan mail postventa" ───
-- Esta es LA vista que n8n consulta cada 10 minutos. Cada fila es una
-- combinación venta+template lista para renderizarse y enviarse.
--
-- La vista ya resuelve:
--   - join con clientes por nombre (fuzzy: lower+trim)
--   - match del template por trigger_estado
--   - respeta trigger_delay_days (no aparece antes del delay)
--   - excluye las ventas que ya recibieron mail para este estado
--
-- n8n hace: GET /rest/v1/ventas_pendientes_mail → por cada fila, renderiza
-- body reemplazando placeholders → envía → POST a email_log.
CREATE OR REPLACE VIEW ventas_pendientes_mail AS
SELECT
  v.id                                                AS venta_id,
  v.empresa_id,
  v.cliente                                           AS cliente_nombre,
  v.nro_pedido,
  v.nro_remito,
  v.estado,
  to_char(v.fecha_entrega_desde, 'DD/MM/YYYY')        AS fecha_entrega_desde,
  to_char(v.fecha_entrega_hasta, 'DD/MM/YYYY')        AS fecha_entrega_hasta,
  v.total,
  v.condicion_pago,
  v.updated_at,
  c.id                                                AS cliente_id,
  c.email                                             AS cliente_email,
  COALESCE(NULLIF(trim(c.contacto), ''), c.nombre)    AS cliente_contacto,
  t.id                                                AS template_id,
  t.subject                                           AS template_subject,
  t.body_html                                         AS template_body,
  t.trigger_delay_days,
  mc.catalogo_url
FROM ventas v
LEFT JOIN clientes c
  ON c.empresa_id = v.empresa_id
 AND lower(trim(c.nombre)) = lower(trim(v.cliente))
INNER JOIN email_templates t
  ON t.empresa_id    = v.empresa_id
 AND t.trigger_estado = v.estado
 AND t.activo         = true
LEFT JOIN mailings_config mc
  ON mc.empresa_id = v.empresa_id
WHERE
  -- Solo estados relevantes para postventa
  v.estado IN ('aprobado_cliente', 'entregado', 'facturado')
  -- El cliente tiene email cargado
  AND c.email IS NOT NULL
  AND c.email <> ''
  -- Respetar el delay configurado en el template
  AND (v.updated_at + (t.trigger_delay_days || ' days')::interval) <= now()
  -- No mandar dos veces el mismo mail para el mismo estado
  AND NOT EXISTS (
    SELECT 1 FROM email_log l
    WHERE l.venta_id       = v.id
      AND l.trigger_estado = v.estado
      AND l.status         = 'enviado'
  );

COMMENT ON VIEW ventas_pendientes_mail IS
  'n8n postventa: ventas que necesitan mail automático. Join resuelto con cliente + template + config.';


-- ─── Verificación (opcional, descomentá para correr) ──────────
-- SELECT COUNT(*) AS ventas_con_mail_pendiente FROM ventas_pendientes_mail;
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'ventas' AND column_name = 'updated_at';


-- ═══════════════════════════════════════════════════════════
-- ROLLBACK (correr solo si hay que revertir)
-- ═══════════════════════════════════════════════════════════
-- DROP VIEW IF EXISTS ventas_pendientes_mail;
-- DROP INDEX IF EXISTS idx_email_log_venta_trigger;
-- DROP INDEX IF EXISTS idx_email_templates_trigger;
-- DROP INDEX IF EXISTS idx_ventas_estado_updated;
-- DROP TRIGGER IF EXISTS trg_ventas_updated ON ventas;
-- ALTER TABLE ventas           DROP COLUMN IF EXISTS updated_at;
-- ALTER TABLE email_templates  DROP COLUMN IF EXISTS trigger_estado, DROP COLUMN IF EXISTS trigger_delay_days;
-- ALTER TABLE email_log        DROP COLUMN IF EXISTS trigger_estado;
-- ALTER TABLE email_queue      DROP COLUMN IF EXISTS trigger_estado;
-- ALTER TABLE mailings_config  DROP COLUMN IF EXISTS catalogo_url;
