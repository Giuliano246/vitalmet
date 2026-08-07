-- ═══════════════════════════════════════════════════════════════════
-- 068 — OBSERVACIONES DE AUDITORÍA (amarillas, sprint 2026-08-07)
-- ═══════════════════════════════════════════════════════════════════
-- Cierra a nivel base las observaciones 2 y 5 del dictamen 2026-08-06:
--
--   1. ANTI DOBLE-PAGO DE SUELDOS: el control era solo visual (el
--      frontend ocultaba el botón). UNIQUE parcial sobre asientos por
--      (empresa, origen_tipo, origen_id) para los pagos de liquidación:
--      un segundo pago de netos/cargas de la misma liquidación es
--      rechazado por la DB. Anular el asiento de pago lo saca del
--      índice y habilita re-registrarlo (corrección legítima).
--
--   2. NUMERACIÓN DE RECIBOS DE COBRANZA: el Nº de recibo era texto
--      libre. Si el cobro llega sin comprobante, la DB asigna REC-nnnn
--      correlativo por empresa bajo advisory lock (mismo patrón que
--      asientos 023 / presupuestos 055). Lo tipeado a mano se respeta.
--
-- El resto del sprint es frontend puro (Libro Diario exportable, Libro
-- IVA Digital RG 4597, pago de liquidaciones contra cuenta bancaria
-- real, validación de CUIL) — no requiere SQL.
BEGIN;

-- ─── 1. Anti doble-pago de liquidaciones ─────────────────────────────
-- Pre-chequeo: si ya hubiera pagos duplicados vivos, avisar cuáles en
-- lugar de fallar con un error críptico del CREATE INDEX.
DO $$
DECLARE v_dups text;
BEGIN
  SELECT string_agg(DISTINCT origen_tipo || ' de la liquidación ' || origen_id, ', ')
    INTO v_dups
  FROM (
    SELECT empresa_id, origen_tipo, origen_id
    FROM asientos
    WHERE origen_tipo IN ('liquidacion-pago-netos', 'liquidacion-pago-cargas')
      AND estado <> 'anulado'
    GROUP BY empresa_id, origen_tipo, origen_id
    HAVING count(*) > 1
  ) d;
  IF v_dups IS NOT NULL THEN
    RAISE EXCEPTION 'Hay pagos de sueldos duplicados sin anular: %. Anulá el asiento duplicado en el Libro Diario y volvé a correr la migración.', v_dups;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_asientos_pago_liquidacion
  ON public.asientos (empresa_id, origen_tipo, origen_id)
  WHERE origen_tipo IN ('liquidacion-pago-netos', 'liquidacion-pago-cargas')
    AND estado <> 'anulado';
COMMENT ON INDEX uq_asientos_pago_liquidacion IS
  'Un solo pago vivo de netos y uno de cargas por liquidación (068). Anular el asiento habilita re-registrar.';

-- ─── 2. Numeración server-side de recibos de cobranza ────────────────
CREATE OR REPLACE FUNCTION public.fn_recibo_nro() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE n int;
BEGIN
  IF NEW.tipo = 'auto-cobranza' AND COALESCE(NEW.comprobante_nro, '') = '' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('recibos_nro:' || NEW.empresa_id::text, 0));
    SELECT COALESCE(MAX((substring(comprobante_nro FROM '^REC-(\d+)$'))::int), 0) + 1 INTO n
    FROM asientos
    WHERE empresa_id = NEW.empresa_id AND comprobante_nro ~ '^REC-\d+$';
    NEW.comprobante_nro := 'REC-' || lpad(n::text, 4, '0');
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_recibo_nro() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_recibo_nro ON public.asientos;
CREATE TRIGGER trg_recibo_nro
  BEFORE INSERT ON public.asientos
  FOR EACH ROW EXECUTE FUNCTION public.fn_recibo_nro();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Índice y trigger:
-- SELECT indexname FROM pg_indexes WHERE indexname = 'uq_asientos_pago_liquidacion';
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_recibo_nro';
--
-- 2. Duplicar un pago debe fallar (probar desde la UI: el segundo
--    intento de "Pagar netos" de la misma liquidación da error de
--    clave duplicada).
