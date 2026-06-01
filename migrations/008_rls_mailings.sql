-- ============================================================
-- 008_rls_mailings.sql
-- Activa RLS + tenant_isolation en las tablas creadas por
-- 004_mailings.sql que quedaron fuera del setup original (006).
-- ============================================================

DO $$
DECLARE
  t text;
  mailings_tables text[] := ARRAY[
    'email_templates',
    'email_queue',
    'email_log',
    'integracion_microsoft',
    'mailings_config'
  ];
BEGIN
  FOREACH t IN ARRAY mailings_tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', t);
      EXECUTE format(
        'CREATE POLICY tenant_isolation ON %I FOR ALL TO authenticated USING (empresa_id = public.current_empresa_id()) WITH CHECK (empresa_id = public.current_empresa_id())',
        t
      );
      RAISE NOTICE 'RLS activado en %', t;
    ELSE
      RAISE NOTICE 'Tabla % no existe — saltada', t;
    END IF;
  END LOOP;
END $$;

-- ─── Verificación ────────────────────────────────────────────
-- Para ver el estado real:
--   SELECT tablename, rowsecurity
--   FROM pg_tables
--   WHERE schemaname='public'
--   ORDER BY rowsecurity DESC, tablename;
