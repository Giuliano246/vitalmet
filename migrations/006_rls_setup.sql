-- ═══════════════════════════════════════════════════════════════════
-- 006_rls_setup.sql
-- Activación de Row Level Security (RLS) en VitalStock ERP
-- Multi-tenancy seguro por empresa_id
-- ═══════════════════════════════════════════════════════════════════
--
-- Estrategia:
-- 1. Función SECURITY DEFINER `current_empresa_id()` que bypassea RLS para
--    obtener el empresa_id del usuario logueado sin causar recursión.
-- 2. Policy genérica `tenant_isolation` en tablas con empresa_id directo.
-- 3. Policies especiales en `empresas` (tabla raíz) y `usuarios` (caso circular).
-- 4. Policies en tablas hijas (venta_items, oc_items, presupuesto_items) que
--    chequean el empresa_id del padre.
-- 5. Skip seguro de tablas que aún no existan en este entorno.
--
-- Para revertir: correr 006_rls_rollback.sql
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Función helper (NO causa recursión) ──────────────────────
CREATE OR REPLACE FUNCTION public.current_empresa_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT empresa_id FROM public.usuarios WHERE id = auth.uid() LIMIT 1
$$;

GRANT EXECUTE ON FUNCTION public.current_empresa_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_empresa_id() TO anon;

-- ─── 2. RLS + policies genéricas en tablas con empresa_id ────────
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
        'CREATE POLICY tenant_isolation ON %I FOR ALL TO authenticated USING (empresa_id = public.current_empresa_id()) WITH CHECK (empresa_id = public.current_empresa_id())',
        t
      );
      RAISE NOTICE 'RLS activado en %', t;
    ELSE
      RAISE NOTICE 'Tabla % no existe — saltada', t;
    END IF;
  END LOOP;
END $$;

-- ─── 3. Policies especiales para `empresas` (tabla raíz) ─────────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='empresas') THEN
    EXECUTE 'ALTER TABLE empresas ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS empresas_self ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_insert ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_update ON empresas';
    EXECUTE 'DROP POLICY IF EXISTS empresas_anon_lookup ON empresas';
    -- Authenticated: ve solo su propia empresa
    EXECUTE 'CREATE POLICY empresas_self ON empresas FOR SELECT TO authenticated USING (id = public.current_empresa_id())';
    -- Anon: lookup por codigo_invitacion (necesario para flujo "Unirse con código")
    -- ⚠️ Expone nombre+slug+codigo de todas las empresas a anon. Si tenés multi-tenant
    -- con datos sensibles en `empresas`, considerá reemplazar por una RPC.
    EXECUTE 'CREATE POLICY empresas_anon_lookup ON empresas FOR SELECT TO anon USING (true)';
    -- Permitir INSERT al registrar nueva empresa (no hay empresa_id aún en JWT)
    EXECUTE 'CREATE POLICY empresas_insert ON empresas FOR INSERT TO authenticated WITH CHECK (true)';
    EXECUTE 'CREATE POLICY empresas_update ON empresas FOR UPDATE TO authenticated USING (id = public.current_empresa_id())';
  END IF;
END $$;

-- ─── 4. Policies especiales para `usuarios` (sin recursión) ──────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='usuarios') THEN
    EXECUTE 'ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_select ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_insert ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_update ON usuarios';
    EXECUTE 'DROP POLICY IF EXISTS usuarios_delete ON usuarios';
    -- SELECT: ver propio + usuarios de mi empresa (sin recursión: id = auth.uid() es directo)
    EXECUTE 'CREATE POLICY usuarios_select ON usuarios FOR SELECT TO authenticated USING (id = auth.uid() OR empresa_id = public.current_empresa_id())';
    -- INSERT: solo puedo crear mi propia fila al registrarme
    EXECUTE 'CREATE POLICY usuarios_insert ON usuarios FOR INSERT TO authenticated WITH CHECK (id = auth.uid())';
    -- UPDATE: propio o de mi empresa (admins editan a operarios)
    EXECUTE 'CREATE POLICY usuarios_update ON usuarios FOR UPDATE TO authenticated USING (id = auth.uid() OR empresa_id = public.current_empresa_id())';
    -- DELETE: solo de mi empresa
    EXECUTE 'CREATE POLICY usuarios_delete ON usuarios FOR DELETE TO authenticated USING (empresa_id = public.current_empresa_id())';
  END IF;
END $$;

-- ─── 5. Policies para tablas hijas (sin empresa_id directo) ──────

-- venta_items → ventas
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='venta_items') THEN
    EXECUTE 'ALTER TABLE venta_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS venta_items_isolation ON venta_items';
    EXECUTE 'CREATE POLICY venta_items_isolation ON venta_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM ventas v WHERE v.id = venta_items.venta_id AND v.empresa_id = public.current_empresa_id())) WITH CHECK (EXISTS (SELECT 1 FROM ventas v WHERE v.id = venta_items.venta_id AND v.empresa_id = public.current_empresa_id()))';
  END IF;
END $$;

-- oc_items → ordenes_compra
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='oc_items') THEN
    EXECUTE 'ALTER TABLE oc_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS oc_items_isolation ON oc_items';
    EXECUTE 'CREATE POLICY oc_items_isolation ON oc_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM ordenes_compra o WHERE o.id = oc_items.oc_id AND o.empresa_id = public.current_empresa_id())) WITH CHECK (EXISTS (SELECT 1 FROM ordenes_compra o WHERE o.id = oc_items.oc_id AND o.empresa_id = public.current_empresa_id()))';
  END IF;
END $$;

-- presupuesto_items → presupuestos
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='presupuesto_items') THEN
    EXECUTE 'ALTER TABLE presupuesto_items ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS presupuesto_items_isolation ON presupuesto_items';
    EXECUTE 'CREATE POLICY presupuesto_items_isolation ON presupuesto_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM presupuestos p WHERE p.id = presupuesto_items.presupuesto_id AND p.empresa_id = public.current_empresa_id())) WITH CHECK (EXISTS (SELECT 1 FROM presupuestos p WHERE p.id = presupuesto_items.presupuesto_id AND p.empresa_id = public.current_empresa_id()))';
  END IF;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: correr esto al final para ver qué tablas quedaron con RLS
-- ═══════════════════════════════════════════════════════════════════
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = true
ORDER BY tablename;
