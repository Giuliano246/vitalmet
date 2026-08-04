-- ═══════════════════════════════════════════════════════════════════
-- MIGRACIÓN 063 — Facturación AFIP migra de Railway a Edge Function
--
-- Contexto: el trial de Railway venció (2026-08-04) y el microservicio
-- vitalmet-billing se reescribió como Edge Function `facturacion`
-- (supabase/functions/facturacion). Esta migración crea su única
-- dependencia de schema:
--
--   1. afip_ta: cache persistente del Ticket de Acceso de WSAA.
--      Las Edge Functions son efímeras y ARCA RECHAZA pedir un TA
--      nuevo mientras el anterior siga vigente (~12h), así que el
--      token/sign deben sobrevivir entre invocaciones. Acceso solo
--      via service_role (RLS sin policies + revoke), el cliente
--      nunca lo ve.
--
--   2. config_contable.punto_venta = 4 para Vitalmet SA: ARCA tiene
--      habilitados para web service los PV 2 y 4; el 2 lo usa el
--      sistema del contador (3.310 FA emitidas), el 4 está sin uso.
--      Solo pisa el valor si sigue en el default 1 (que no es válido
--      para WS).
--
-- Requiere: 055 (config_contable.punto_venta). Idempotente. Correr
-- ANTES de deployar el frontend y la función.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Cache del Ticket de Acceso WSAA ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.afip_ta (
  service     text NOT NULL,
  environment text NOT NULL CHECK (environment IN ('homologacion','produccion')),
  token       text NOT NULL,
  sign        text NOT NULL,
  expires_at  timestamptz NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (service, environment)
);

ALTER TABLE public.afip_ta ENABLE ROW LEVEL SECURITY;
-- Sin policies a propósito: solo service_role (la Edge Function) accede.
REVOKE ALL ON public.afip_ta FROM anon, authenticated;

-- ── 2. Punto de venta habilitado para WS ────────────────────────────
UPDATE public.config_contable
   SET punto_venta = 4
 WHERE empresa_id = 'a0a19507-2a50-4e80-a716-e9459f51d653'
   AND punto_venta = 1;

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT relrowsecurity FROM pg_class WHERE relname='afip_ta';           -- t
-- SELECT punto_venta FROM config_contable
--   WHERE empresa_id='a0a19507-2a50-4e80-a716-e9459f51d653';             -- 4
