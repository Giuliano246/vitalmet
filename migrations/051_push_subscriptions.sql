-- 051_push_subscriptions.sql — VitalPulse Fase 2: push notifications
--
-- Suscripciones Web Push de la app VitalPulse (PWA del dueño).
-- Cada fila = un dispositivo suscripto. prefs controla qué recibe:
--   digest  → resumen matutino (cheques que vencen, entregas, presupuestos fríos)
--   ventas  → aviso instantáneo cuando se carga una venta en el ERP
--
-- push_config guarda el secreto compartido con la Edge Function
-- `vitalpulse-push` (SIN grants: solo postgres/service_role la leen; el
-- valor se setea a mano en el SQL editor, no viaja en el repo).
--
-- El trigger de venta nueva y el cron del digest usan pg_net para
-- invocar la función. Aditiva, idempotente. Correr ANTES de deployar
-- la Edge Function y el frontend de VitalPulse F2.
BEGIN;

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id),
  usuario_id uuid NOT NULL,
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth text NOT NULL,
  prefs jsonb NOT NULL DEFAULT '{"digest": true, "ventas": true}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS push_own ON push_subscriptions;
-- Cada usuario administra SOLO sus suscripciones (y dentro de su empresa).
CREATE POLICY push_own ON push_subscriptions FOR ALL TO authenticated
  USING (usuario_id = (SELECT auth.uid()))
  WITH CHECK (usuario_id = (SELECT auth.uid())
              AND empresa_id = (SELECT public.current_empresa_id()));

CREATE INDEX IF NOT EXISTS idx_push_subs_empresa ON push_subscriptions (empresa_id);

-- ─── Config del canal (secreto compartido con la Edge Function) ──────
CREATE TABLE IF NOT EXISTS push_config (
  k text PRIMARY KEY,
  v text NOT NULL
);
REVOKE ALL ON push_config FROM anon, authenticated;
-- El valor se inserta a mano (ver instrucciones fuera del repo):
-- INSERT INTO push_config (k, v) VALUES ('secret', '<PUSH_SECRET>')
--   ON CONFLICT (k) DO UPDATE SET v = excluded.v;

-- ─── Aviso instantáneo: venta nueva → Edge Function ──────────────────
-- pg_net es asíncrono: no bloquea el INSERT de la venta.
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.notify_venta_push() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sec text;
BEGIN
  SELECT v INTO sec FROM push_config WHERE k = 'secret';
  IF sec IS NULL THEN RETURN NEW; END IF; -- push no configurado: no-op
  PERFORM net.http_post(
    url := 'https://dqvlqhaxgvtilhiuatpv.supabase.co/functions/v1/vitalpulse-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec),
    body := jsonb_build_object(
      'type', 'venta',
      'venta_id', NEW.id,
      'nro', COALESCE(NEW.nro_remito, NEW.nro_pedido, ''),
      'cliente', COALESCE(NEW.cliente, ''),
      'total', COALESCE(NEW.total, 0)
    )
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_push_venta ON ventas;
CREATE TRIGGER trg_push_venta
  AFTER INSERT ON ventas
  FOR EACH ROW EXECUTE FUNCTION public.notify_venta_push();

-- ─── Digest matutino: cron 08:00 ART (11:00 UTC) ─────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'vitalpulse-digest') THEN
    PERFORM cron.unschedule('vitalpulse-digest');
  END IF;
END $$;

SELECT cron.schedule(
  'vitalpulse-digest',
  '0 11 * * *',
  $$
  SELECT net.http_post(
    url := 'https://dqvlqhaxgvtilhiuatpv.supabase.co/functions/v1/vitalpulse-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-push-secret', (SELECT v FROM push_config WHERE k = 'secret')),
    body := '{"type": "digest"}'::jsonb
  )
  $$
);

COMMIT;

-- Verificación:
-- SELECT tablename, policyname FROM pg_policies WHERE tablename='push_subscriptions';
-- SELECT jobname, schedule FROM cron.job WHERE jobname='vitalpulse-digest';
-- SELECT tgname FROM pg_trigger WHERE tgname='trg_push_venta';
