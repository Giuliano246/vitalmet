-- ═══════════════════════════════════════════════════════════════════
-- 029_timezone_argentina.sql
-- Bug de fechas: la DB corre en UTC, así que current_date de 21:00 a
-- 0:00 hora argentina devuelve el día SIGUIENTE. Afectaba:
--   · ventas.fecha al convertir presupuesto (023, current_date)
--   · ventas.fecha_entregado del trigger OTD (026, current_date) —
--     una entrega marcada a la noche del día prometido quedaba
--     "tarde" por un día
--
-- Fix en dos capas:
--   1. timezone de la base → America/Argentina/Buenos_Aires
--      (current_date/now()::date pasan a ser la fecha argentina en
--      toda función presente y futura; timestamptz sigue guardando
--      UTC, solo cambia la representación)
--   2. fn_venta_fecha_entregado explícito con AT TIME ZONE, por si
--      algún día se resetea el timezone de la base
--
-- El frontend tiene el espejo de este fix: hoyLocal() en vez de
-- new Date().toISOString().
--
-- Idempotente, retrocompatible. No backfillea fechas históricas.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- 1) La base entera piensa en hora argentina (sesiones nuevas;
--    las conexiones vivas del pooler lo toman al reciclarse)
ALTER DATABASE postgres SET timezone TO 'America/Argentina/Buenos_Aires';

-- 2) Trigger OTD: fecha argentina explícita, independiente del TZ de sesión
CREATE OR REPLACE FUNCTION public.fn_venta_fecha_entregado() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'entregado' AND NEW.fecha_entregado IS NULL
     AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM 'entregado') THEN
    NEW.fecha_entregado := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
  END IF;
  RETURN NEW;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, en una sesión NUEVA del SQL Editor)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT current_setting('timezone') AS tz_sesion,
--        (SELECT setting FROM pg_db_role_setting s JOIN pg_database d ON d.oid=s.setdatabase,
--                LATERAL unnest(s.setconfig) AS setting
--          WHERE d.datname='postgres' AND setting LIKE 'TimeZone%') AS tz_base,
--        current_date AS fecha_ar;
