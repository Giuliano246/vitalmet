-- ═══════════════════════════════════════════════════════════════════
-- 057_automatizacion.sql — Sprint 3 de la auditoría 2026-07-30
--
--   1. Worker de mails server-side: cron cada 15' (pg_cron + pg_net)
--      que invoca la Edge Function `vitalmet-mailer`. La función lee
--      email_queue (estado='aprobado'), envía por Microsoft Graph con
--      las credenciales de integracion_microsoft y marca enviado /
--      fallido + copia a email_log. Mata la dependencia de n8n local:
--      los mails aprobados salen aunque nadie tenga el ERP abierto.
--      Si integracion_microsoft no está configurada (falta Azure AD),
--      la función es no-op y los mails quedan aprobados esperando.
--   2. clientes.limite_credito: tope de crédito en USD para el
--      semáforo al registrar ventas (NULL = sin límite).
--
-- El secreto del mailer vive en push_config (tabla sin grants, mig
-- 051) bajo la clave 'mailer_secret'. Si ya existe 'secret' (push de
-- VitalPulse) se reutiliza el mismo valor; si no, setearlo a mano:
--   INSERT INTO push_config (k,v) VALUES ('mailer_secret','<SECRET>')
--     ON CONFLICT (k) DO UPDATE SET v = excluded.v;
--
-- Requiere: 004 (email_queue/log, integracion_microsoft,
-- mailings_config), 051 (push_config, pg_cron, pg_net).
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Límite de crédito por cliente ───────────────────────────────

ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS limite_credito numeric CHECK (limite_credito IS NULL OR limite_credito >= 0);

-- ─── 2. Secreto del mailer (reusa el de push si ya existe) ──────────

INSERT INTO public.push_config (k, v)
  SELECT 'mailer_secret', v FROM public.push_config WHERE k = 'secret'
  ON CONFLICT (k) DO NOTHING;

COMMIT;

-- ─── 3. Cron del worker de mails ────────────────────────────────────
-- Cada 15 minutos entre 11 y 22 UTC (08–19 ART). La Edge Function
-- vuelve a chequear horario/días hábiles contra mailings_config, así
-- que el cron puede correr de más sin riesgo de enviar fuera de hora.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'vitalmet-mailer') THEN
    PERFORM cron.unschedule('vitalmet-mailer');
  END IF;
END $$;

SELECT cron.schedule(
  'vitalmet-mailer',
  '*/15 11-22 * * *',
  $$
  SELECT net.http_post(
    url := 'https://dqvlqhaxgvtilhiuatpv.supabase.co/functions/v1/vitalmet-mailer',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-mailer-secret', (SELECT v FROM push_config WHERE k = 'mailer_secret')),
    body := '{"trigger": "cron"}'::jsonb
  )
  $$
);

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clientes' AND column_name='limite_credito';
-- SELECT k FROM push_config;                                  -- debe incluir mailer_secret
-- SELECT jobname, schedule FROM cron.job WHERE jobname='vitalmet-mailer';
