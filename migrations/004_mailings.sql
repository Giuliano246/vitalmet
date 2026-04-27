-- ═══════════════════════════════════════════════════════════
-- Migración 004 — Módulo Mailings (seguimientos + envío individual)
-- Crea 4 tablas: templates, queue, log, integración Microsoft Graph
-- Ejecutar una vez en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── Templates de email ────────────────────────────────────
-- Almacena las plantillas reutilizables. El body soporta {placeholders}
-- que se reemplazan al enviar ({cliente}, {pieza}, {fecha_entrega}, etc.)
CREATE TABLE IF NOT EXISTS email_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  nombre text NOT NULL,                       -- ej "Seguimiento post-entrega"
  tipo text NOT NULL,                          -- 'seguimiento' | 'individual' | 'comunicado'
  subject text NOT NULL,                       -- asunto con placeholders
  body_html text NOT NULL,                     -- cuerpo HTML con placeholders
  variables_disponibles text[] DEFAULT ARRAY[]::text[], -- ej ['{cliente}', '{pieza}']
  activo bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_templates_empresa ON email_templates (empresa_id);
CREATE INDEX IF NOT EXISTS idx_email_templates_tipo ON email_templates (empresa_id, tipo, activo);


-- ─── Cola de emails (seguimientos programados + envíos manuales) ────────
-- Cada fila es un mail a enviar en un momento específico.
-- Estado: pendiente_aprobacion → aprobado → enviado (o cancelado / fallido)
-- Con cola de aprobación: Giuliano revisa antes de que salga.
CREATE TABLE IF NOT EXISTS email_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- origen
  venta_id uuid REFERENCES ventas(id) ON DELETE SET NULL,         -- si viene de una venta
  cliente_id uuid REFERENCES clientes(id) ON DELETE SET NULL,     -- destinatario principal
  template_id uuid REFERENCES email_templates(id) ON DELETE SET NULL,

  -- contenido resuelto (los placeholders ya reemplazados, listo para enviar)
  to_email text NOT NULL,
  to_nombre text,
  subject text NOT NULL,
  body_html text NOT NULL,

  -- scheduling
  scheduled_at timestamptz NOT NULL,          -- cuándo debe salir
  estado text NOT NULL DEFAULT 'pendiente_aprobacion',
  -- estados: pendiente_aprobacion | aprobado | enviado | cancelado | fallido

  -- auditoría
  aprobado_por uuid REFERENCES usuarios(id),
  aprobado_at timestamptz,
  enviado_at timestamptz,
  graph_msg_id text,                          -- id que devuelve Microsoft Graph
  error_texto text,                           -- si falla

  created_by uuid REFERENCES usuarios(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_queue_empresa ON email_queue (empresa_id);
CREATE INDEX IF NOT EXISTS idx_email_queue_estado ON email_queue (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_email_queue_scheduled ON email_queue (estado, scheduled_at)
  WHERE estado = 'aprobado';                  -- índice parcial: solo los que hay que mandar


-- ─── Log de envíos (histórico completo, nunca se borra) ─────────────────
-- Cuando un email_queue pasa a 'enviado' se copia acá.
-- Esta tabla es el source of truth para reportes y métricas.
CREATE TABLE IF NOT EXISTS email_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  queue_id uuid REFERENCES email_queue(id),
  venta_id uuid REFERENCES ventas(id) ON DELETE SET NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE SET NULL,
  template_id uuid REFERENCES email_templates(id) ON DELETE SET NULL,
  to_email text NOT NULL,
  subject text NOT NULL,
  graph_msg_id text,
  status text NOT NULL,                       -- 'enviado' | 'fallido'
  error_texto text,
  sent_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_log_empresa ON email_log (empresa_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_email_log_cliente ON email_log (cliente_id, sent_at DESC);


-- ─── Integración Microsoft Graph (OAuth tokens por empresa) ─────────────
-- Guarda el refresh_token para que la Edge Function pueda pedir access_tokens
-- cuando necesite enviar. Una fila por empresa.
CREATE TABLE IF NOT EXISTS integracion_microsoft (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL UNIQUE REFERENCES empresas(id) ON DELETE CASCADE,
  tenant_id text NOT NULL,                    -- del tenant de Azure AD
  client_id text NOT NULL,                    -- app registrada en Azure AD
  client_secret_cifrado text NOT NULL,        -- Supabase vault recomendado en prod
  refresh_token_cifrado text,                 -- se setea después del OAuth one-time
  sender_email text NOT NULL,                 -- ventas@vitalmetsa.com
  sender_display_name text,                   -- "Vitalmet SA — Ventas"
  ultimo_refresh_at timestamptz,
  activo bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_integracion_ms_empresa ON integracion_microsoft (empresa_id);


-- ─── Config global de mailings por empresa ─────────────────────────────
-- Parámetros: delay default para seguimientos, horario permitido, etc.
CREATE TABLE IF NOT EXISTS mailings_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL UNIQUE REFERENCES empresas(id) ON DELETE CASCADE,
  seguimiento_dias_default int DEFAULT 14,    -- cuántos días después del despacho
  horario_envio_desde time DEFAULT '09:00',   -- no enviar antes de
  horario_envio_hasta time DEFAULT '18:00',   -- no enviar después de
  dias_habiles_solamente bool DEFAULT true,   -- skip sábado/domingo
  requiere_aprobacion bool DEFAULT true,      -- cola de aprobación activa
  max_envios_por_hora int DEFAULT 20,         -- throttle
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);


-- ─── Helpers ───────────────────────────────────────────────────────────

-- Renueva updated_at en cambios
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_templates_updated ON email_templates;
CREATE TRIGGER trg_templates_updated
  BEFORE UPDATE ON email_templates
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_integracion_ms_updated ON integracion_microsoft;
CREATE TRIGGER trg_integracion_ms_updated
  BEFORE UPDATE ON integracion_microsoft
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_mailings_config_updated ON mailings_config;
CREATE TRIGGER trg_mailings_config_updated
  BEFORE UPDATE ON mailings_config
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- ─── Seed: templates default para empezar ─────────────────────────────
-- (podés editarlos después desde el módulo Mailings)
-- Nota: el WHERE NOT EXISTS evita duplicar si la migración se corre de nuevo

INSERT INTO email_templates (empresa_id, nombre, tipo, subject, body_html, variables_disponibles)
SELECT
  e.id,
  'Seguimiento post-entrega',
  'seguimiento',
  'Cómo les funcionaron los {pieza}, {cliente}?',
  '<p>Hola {contacto},</p>
<p>Hace unos días les enviamos <strong>{pieza}</strong> con el remito {nro_remito}. Quería pasar para ver cómo les funcionaron en la operación.</p>
<p>¿Pudieron instalarlas sin inconvenientes? ¿Hubo algún tema dimensional o de comportamiento en servicio que valga la pena revisar de nuestro lado?</p>
<p>Cualquier comentario me sirve para mejorar el próximo lote. Si todo estuvo ok, también me avisás y quedo tranquilo.</p>
<p>Saludos,<br>Giuliano Vitale<br>Vitalmet SA</p>',
  ARRAY['{contacto}', '{cliente}', '{pieza}', '{nro_remito}', '{fecha_entrega}']
FROM empresas e
WHERE NOT EXISTS (
  SELECT 1 FROM email_templates t
  WHERE t.empresa_id = e.id AND t.tipo = 'seguimiento'
);


-- ─── Verificación (opcional, lo podés comentar después) ───────────────
-- SELECT 'email_templates'::text, COUNT(*) FROM email_templates
-- UNION ALL SELECT 'email_queue', COUNT(*) FROM email_queue
-- UNION ALL SELECT 'email_log', COUNT(*) FROM email_log
-- UNION ALL SELECT 'integracion_microsoft', COUNT(*) FROM integracion_microsoft
-- UNION ALL SELECT 'mailings_config', COUNT(*) FROM mailings_config;
