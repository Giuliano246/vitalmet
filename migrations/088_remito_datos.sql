-- ═══════════════════════════════════════════════════════════════════
-- 088_remito_datos.sql
-- Datos de la entrega que tiene que llevar el remito (pedido de la
-- contadora, 2026-10-06): domicilio de entrega, transporte, valor
-- declarado (neto de la orden de compra), cantidad de bultos y número
-- de la orden de compra del cliente.
--
-- ventas.remito_datos jsonb:
--   {domicilio_entrega, transporte, valor_declarado, valor_moneda ('USD'|'ARS'),
--    bultos, oc_cliente}
-- Lo escribe el frontend con un PATCH desde el botón Remito. No toca
-- monto, cliente ni número, así que el guard de ventas facturadas
-- (fn_proteger_venta_facturada) lo deja pasar también con CAE emitido.
-- Idempotente y retrocompatible.
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.ventas ADD COLUMN IF NOT EXISTS remito_datos jsonb;
COMMENT ON COLUMN public.ventas.remito_datos IS
  'Datos de la entrega impresos en el remito: {domicilio_entrega, transporte, valor_declarado, valor_moneda, bultos, oc_cliente} (mig 088).';

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT column_name, data_type FROM information_schema.columns
--  WHERE table_name = 'ventas' AND column_name = 'remito_datos';   -- 1 fila, jsonb
