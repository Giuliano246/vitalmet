-- ═══════════════════════════════════════════════════════════════════
-- 087_comprobantes_imprimibles.sql
-- Impresión de facturas, notas de crédito y notas de débito emitidas.
--
--   1. facturas_emitidas.items (jsonb): el detalle que se informó a ARCA
--      ([{descripcion, cantidad, precio_unit, iva_pct}], precio NETO en
--      pesos). Hasta ahora el comprobante guardaba sólo los totales.
--   2. Trigger trg_factura_items (BEFORE INSERT): si el alta llega sin
--      ítems, los copia de la bitácora afip_eventos (el pedido de CAE
--      aprobado con el mismo punto de venta, tipo, número y ambiente).
--      Así el detalle impreso es EXACTAMENTE el que recibió ARCA y el
--      frontend no cambia su alta.
--   3. Backfill de los comprobantes ya emitidos, desde la misma bitácora.
--   4. config_contable.iibb_nro / inicio_actividades: datos del emisor
--      que la RG 1415 exige en el comprobante impreso.
--
-- Idempotente y retrocompatible: el frontend imprime igual sin ítems
-- guardados (reconstruye el detalle desde la venta o usa una línea única).
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.facturas_emitidas ADD COLUMN IF NOT EXISTS items jsonb;
COMMENT ON COLUMN public.facturas_emitidas.items IS
  'Detalle informado a ARCA: [{descripcion, cantidad, precio_unit (neto, pesos), iva_pct}]. Lo completa trg_factura_items desde afip_eventos (mig 087).';

ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS iibb_nro text,
  ADD COLUMN IF NOT EXISTS inicio_actividades date;
COMMENT ON COLUMN public.config_contable.iibb_nro IS 'Nº de Ingresos Brutos del emisor (se imprime en facturas, NC y ND), mig 087.';
COMMENT ON COLUMN public.config_contable.inicio_actividades IS 'Fecha de inicio de actividades del emisor (se imprime en facturas, NC y ND), mig 087.';

-- SECURITY DEFINER: afip_eventos sólo la leen los admins; el trigger
-- tiene que poder copiar los ítems cuando factura un usuario de Ventas.
CREATE OR REPLACE FUNCTION public.fn_factura_items() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_items jsonb;
BEGIN
  IF NEW.items IS NULL THEN
    SELECT e.request->'items' INTO v_items
      FROM afip_eventos e
     WHERE e.evento = 'cae_aprobado'
       AND e.punto_venta = NEW.punto_venta
       AND e.tipo_comprobante = NEW.tipo_comprobante
       AND e.numero = NEW.numero
       AND e.environment = NEW.afip_environment
       AND (e.empresa_id IS NULL OR e.empresa_id = NEW.empresa_id)
     ORDER BY e.created_at DESC
     LIMIT 1;
    IF jsonb_typeof(v_items) = 'array' THEN NEW.items := v_items; END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.fn_factura_items() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_factura_items() FROM anon;

DROP TRIGGER IF EXISTS trg_factura_items ON public.facturas_emitidas;
CREATE TRIGGER trg_factura_items BEFORE INSERT ON public.facturas_emitidas
  FOR EACH ROW EXECUTE FUNCTION public.fn_factura_items();

-- Backfill: comprobantes ya emitidos que tienen su pedido en la bitácora.
UPDATE public.facturas_emitidas f
   SET items = x.items
  FROM (
    SELECT DISTINCT ON (e.punto_venta, e.tipo_comprobante, e.numero, e.environment)
           e.punto_venta, e.tipo_comprobante, e.numero, e.environment, e.empresa_id,
           e.request->'items' AS items
      FROM public.afip_eventos e
     WHERE e.evento = 'cae_aprobado' AND jsonb_typeof(e.request->'items') = 'array'
     ORDER BY e.punto_venta, e.tipo_comprobante, e.numero, e.environment, e.created_at DESC
  ) x
 WHERE f.items IS NULL
   AND f.punto_venta = x.punto_venta
   AND f.tipo_comprobante = x.tipo_comprobante
   AND f.numero = x.numero
   AND f.afip_environment = x.environment
   AND (x.empresa_id IS NULL OR x.empresa_id = f.empresa_id);

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT count(*) FILTER (WHERE items IS NOT NULL) AS con_detalle,
--        count(*) FILTER (WHERE items IS NULL)     AS sin_detalle
--   FROM facturas_emitidas;
-- SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.facturas_emitidas'::regclass AND tgname = 'trg_factura_items'; -- 1 fila
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'config_contable' AND column_name IN ('iibb_nro','inicio_actividades');  -- 2 filas
