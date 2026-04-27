-- ═══════════════════════════════════════════════════════════════════
-- 006_rls_rollback.sql — REVERTIR RLS si algo se rompió
-- Corré este archivo si la app deja de funcionar después de activar RLS
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  t text;
  all_tables text[] := ARRAY[
    'empresas', 'usuarios',
    'certificados', 'barras', 'ordenes_produccion', 'productos_terminados',
    'ventas', 'venta_items', 'materiales', 'tratamientos', 'permisos_usuario',
    'clientes', 'vendedores', 'listas_precios', 'asientos_contables',
    'proveedores', 'ordenes_compra', 'oc_items', 'recepciones_oc',
    'presupuestos', 'presupuesto_items', 'insumos', 'herramientas',
    'op_time_entries', 'op_operaciones'
  ];
BEGIN
  FOREACH t IN ARRAY all_tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE %I DISABLE ROW LEVEL SECURITY', t);
      RAISE NOTICE 'RLS desactivado en %', t;
    END IF;
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS public.current_empresa_id();

COMMIT;
