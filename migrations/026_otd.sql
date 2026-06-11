-- ═══════════════════════════════════════════════════════════════════
-- 026_otd.sql
-- OTD — On-Time Delivery (fase 3, mes 2 — roadmap auditoría)
--
-- ventas.fecha_entregado: la fecha REAL de entrega, estampada por la
-- DB automáticamente la primera vez que la venta pasa a 'entregado'
-- (desde el select de estado, la RPC guardar_venta o un INSERT que ya
-- nace entregado). El OTD se calcula en el frontend comparando contra
-- fecha_entrega_hasta (la prometida).
--
-- No se backfillea: las ventas históricas sin fecha real no cuentan
-- en el indicador (mejor sin dato que con dato inventado).
--
-- Aditiva, retrocompatible, idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE ventas ADD COLUMN IF NOT EXISTS fecha_entregado date;

CREATE OR REPLACE FUNCTION public.fn_venta_fecha_entregado() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'entregado' AND NEW.fecha_entregado IS NULL
     AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM 'entregado') THEN
    NEW.fecha_entregado := current_date;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_venta_fecha_entregado ON ventas;
CREATE TRIGGER trg_venta_fecha_entregado
  BEFORE INSERT OR UPDATE ON ventas
  FOR EACH ROW EXECUTE FUNCTION public.fn_venta_fecha_entregado();

COMMIT;
