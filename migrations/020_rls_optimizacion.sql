-- ═══════════════════════════════════════════════════════════════════
-- 020_rls_optimizacion.sql
-- Optimización de performance de las policies RLS (postgres-patterns)
--
-- Qué cambia respecto de 006_rls_setup.sql:
--   Envuelve current_empresa_id() y auth.uid() en (SELECT ...).
--   Postgres entonces los evalúa UNA vez por query (initPlan) en lugar
--   de UNA vez por fila. Mismo comportamiento de seguridad, mucho más
--   rápido a medida que crecen las tablas.
--
-- No cambia QUÉ ve cada usuario, solo CÓMO se evalúa. Seguro de re-correr.
-- Mismo conjunto de tablas y misma lógica que 006; solo difiere el (SELECT ...).
-- Correr DESPUÉS de 019. Rollback disponible en 006_rls_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Tablas con empresa_id directo: policy genérica optimizada ────
DO $$
DECLARE
  t text;
  tables_with_empresa_id text[] := ARRAY[
    'certificados', 'barras', 'ordenes_produccion', 'productos_terminados',
    'ventas', 'materiales', 'tratamientos', 'permisos_usuario',
    'clientes', 'vendedores', 'listas_precios', 'asientos_contables',
    'proveedores', 'ordenes_compra', 'recepciones_oc', 'presupuestos',
    'insumos', 'herramientas', 'op_time_entries', 'op_operaciones'
  ];
BEGIN
  FOREACH t IN ARRAY tables_with_empresa_id LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', t);
      EXECUTE format(
        'CREATE POLICY tenant_isolation ON %I FOR ALL TO authenticated '
        'USING (empresa_id = (SELECT public.current_empresa_id())) '
        'WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))',
        t
      );
      RAISE NOTICE 'RLS optimizado en %', t;
    ELSE
      RAISE NOTICE 'Tabla % no existe — salteada', t;
    END IF;
  END LOOP;
END $$;

-- ─── 2. empresas (tabla raíz) ───────────────────────────────────────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='empresas') THEN
    EXECUTE 'ALTER TABLE empresas ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS empresas_self ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_insert ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_update ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_anon_lookup ON empresas';
    EXECUTE 'CREATE POLICY empresas_self ON empresas FOR SELECT TO authenticated USING (id = (SELECT public.current_empresa_id()))';
    -- Anon lookup por código de invitación (igual que en 006; ver nota de seguridad allí)
    EXECUTE 'CREATE POLICY empresas_anon_lookup ON empresas FOR SELECT TO anon USING (true)';
    EXECUTE 'CREATE POLICY empresas_insert ON empresas FOR INSERT TO authenticated WITH CHECK (true)';
    EXECUTE 'CREATE POLICY empresas_update ON empresas FOR UPDATE TO authenticated USING (id = (SELECT public.current_empresa_id()))';
  END IF;
END $$;

-- ─── 3. usuarios (caso circular, sin recursión) ─────────────────────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='usuarios') THEN
    EXECUTE 'ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_select ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_insert ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_update ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_delete ON usuarios';
    EXECUTE 'CREATE POLICY usuarios_select ON usuarios FOR SELECT TO authenticated USING (id = (SELECT auth.uid()) OR empresa_id = (SELECT public.current_empresa_id()))';
    EXECUTE 'CREATE POLICY usuarios_insert ON usuarios FOR INSERT TO authenticated WITH CHECK (id = (SELECT auth.uid()))';
    EXECUTE 'CREATE POLICY usuarios_update ON usuarios FOR UPDATE TO authenticated USING (id = (SELECT auth.uid()) OR empresa_id = (SELECT public.current_empresa_id()))';
    EXECUTE 'CREATE POLICY usuarios_delete ON usuarios FOR DELETE TO authenticated USING (empresa_id = (SELECT public.current_empresa_id()))';
  END IF;
END $$;

-- ─── 4. Tablas hijas (empresa_id vía el padre) ──────────────────────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='venta_items') THEN
    EXECUTE 'ALTER TABLE venta_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS venta_items_isolation ON venta_items';
    EXECUTE 'CREATE POLICY venta_items_isolation ON venta_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM ventas v WHERE v.id = venta_items.venta_id AND v.empresa_id = (SELECT public.current_empresa_id()))) WITH CHECK (EXISTS (SELECT 1 FROM ventas v WHERE v.id = venta_items.venta_id AND v.empresa_id = (SELECT public.current_empresa_id())))';
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='oc_items') THEN
    EXECUTE 'ALTER TABLE oc_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS oc_items_isolation ON oc_items';
    EXECUTE 'CREATE POLICY oc_items_isolation ON oc_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM ordenes_compra o WHERE o.id = oc_items.oc_id AND o.empresa_id = (SELECT public.current_empresa_id()))) WITH CHECK (EXISTS (SELECT 1 FROM ordenes_compra o WHERE o.id = oc_items.oc_id AND o.empresa_id = (SELECT public.current_empresa_id())))';
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='presupuesto_items') THEN
    EXECUTE 'ALTER TABLE presupuesto_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS presupuesto_items_isolation ON presupuesto_items';
    EXECUTE 'CREATE POLICY presupuesto_items_isolation ON presupuesto_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM presupuestos p WHERE p.id = presupuesto_items.presupuesto_id AND p.empresa_id = (SELECT public.current_empresa_id()))) WITH CHECK (EXISTS (SELECT 1 FROM presupuestos p WHERE p.id = presupuesto_items.presupuesto_id AND p.empresa_id = (SELECT public.current_empresa_id())))';
  END IF;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: ver las policies activas
-- ═══════════════════════════════════════════════════════════════════
-- SELECT tablename, policyname, qual FROM pg_policies
-- WHERE schemaname='public' ORDER BY tablename, policyname;
