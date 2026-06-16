-- ═══════════════════════════════════════════════════════════════════
-- 031_audit_compras.sql
-- Extiende el audit trail (fn_audit, migración 023) a las tablas de
-- compras y tesorería que hoy quedan sin registrar.
--
-- Tablas cubiertas:
--   ordenes_compra, oc_items, recepciones_oc  → migración 002
--   proveedores                               → migración 002
--   cheques                                   → migración 027
--
-- No redefine fn_audit() ni altera audit_log: solo agrega triggers.
-- Idempotente: DROP TRIGGER IF EXISTS antes de cada CREATE TRIGGER.
-- Guard: solo actúa si la tabla existe en information_schema.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  t text;
  tablas text[] := ARRAY['ordenes_compra','oc_items','recepciones_oc','proveedores','cheques'];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I;', t);
      EXECUTE format(
        'CREATE TRIGGER trg_audit
           AFTER INSERT OR UPDATE OR DELETE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.fn_audit();',
        t
      );
    END IF;
  END LOOP;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT tgrelid::regclass AS tabla
--   FROM pg_trigger
--  WHERE tgname = 'trg_audit'
--    AND NOT tgisinternal
--    AND tgrelid::regclass::text IN
--        ('ordenes_compra','oc_items','recepciones_oc','proveedores','cheques')
--  ORDER BY tabla;
-- Esperado: 5 filas.
