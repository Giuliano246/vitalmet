-- 052_modo_planta.sql — Usuario planta + lockdown RLS (Modo Planta)
-- planta.html (pantalla móvil de taller, spec 2026-07-12) opera con una
-- cuenta compartida marcada usuarios.es_planta=true. Ese usuario solo
-- puede tocar producción:
--   ordenes_produccion  → solo SELECT (lockdown de escritura aparte)
--   op_operaciones      → SELECT + UPDATE (la UI solo cambia estado;
--                         los quality gates de 041 aplican igual)
--   op_time_entries     → SELECT + INSERT + UPDATE
-- Todo lo demás queda bloqueado con policies RESTRICTIVE, que se
-- AND-ean con las tenant_isolation existentes (que NO se tocan).
-- Usuarios normales (es_planta=false): cero cambio de comportamiento.
-- fn_audit es SECURITY DEFINER → la auditoría sigue funcionando aunque
-- audit_log quede bloqueada para planta.
BEGIN;

-- ─── 1. Flag ─────────────────────────────────────────────────────────
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS es_planta boolean NOT NULL DEFAULT false;

-- ─── 2. Helper (SECURITY DEFINER: lee usuarios sin chocar con RLS) ───
CREATE OR REPLACE FUNCTION public.es_planta()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE((SELECT u.es_planta FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_planta() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_planta() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_planta() TO authenticated;

-- ─── 3. Lockdown: toda tabla con RLS fuera de la whitelist ───────────
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
      AND rowsecurity
      AND tablename NOT IN ('ordenes_produccion','op_operaciones','op_time_entries')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS planta_lockdown ON %I', t);
    EXECUTE format(
      'CREATE POLICY planta_lockdown ON %I AS RESTRICTIVE FOR ALL TO authenticated '
      'USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta())', t);
  END LOOP;
END $$;

-- ─── 4. ordenes_produccion: planta solo lectura ──────────────────────
DROP POLICY IF EXISTS planta_ro_ins ON ordenes_produccion;
CREATE POLICY planta_ro_ins ON ordenes_produccion AS RESTRICTIVE FOR INSERT
  TO authenticated WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS planta_ro_upd ON ordenes_produccion;
CREATE POLICY planta_ro_upd ON ordenes_produccion AS RESTRICTIVE FOR UPDATE
  TO authenticated USING (NOT public.es_planta());
DROP POLICY IF EXISTS planta_ro_del ON ordenes_produccion;
CREATE POLICY planta_ro_del ON ordenes_produccion AS RESTRICTIVE FOR DELETE
  TO authenticated USING (NOT public.es_planta());

-- ─── 5. op_operaciones / op_time_entries: recorte fino para planta ──
-- Whitelist del spec: op_operaciones SELECT+UPDATE,
-- op_time_entries SELECT+INSERT+UPDATE. Bloquear el resto.
DROP POLICY IF EXISTS planta_no_ins ON op_operaciones;
CREATE POLICY planta_no_ins ON op_operaciones AS RESTRICTIVE FOR INSERT
  TO authenticated WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS planta_no_del ON op_operaciones;
CREATE POLICY planta_no_del ON op_operaciones AS RESTRICTIVE FOR DELETE
  TO authenticated USING (NOT public.es_planta());
DROP POLICY IF EXISTS planta_no_del ON op_time_entries;
CREATE POLICY planta_no_del ON op_time_entries AS RESTRICTIVE FOR DELETE
  TO authenticated USING (NOT public.es_planta());

COMMIT;

-- Verificación:
-- 1) Columna y función:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name='usuarios' AND column_name='es_planta';       -- 1 fila
--    SELECT public.es_planta();                                       -- false (SQL editor)
-- 2) Lockdown presente en tablas sensibles y AUSENTE en la whitelist:
--    SELECT tablename FROM pg_policies WHERE policyname='planta_lockdown'
--     AND tablename IN ('ventas','asientos','clientes','usuarios');   -- 4 filas
--    SELECT tablename FROM pg_policies WHERE policyname='planta_lockdown'
--     AND tablename IN ('ordenes_produccion','op_operaciones','op_time_entries'); -- 0 filas
-- 3) Solo lectura en ordenes_produccion:
--    SELECT policyname FROM pg_policies WHERE tablename='ordenes_produccion'
--     AND policyname LIKE 'planta_ro_%';                              -- 3 filas
-- 4) Las policies restrictivas quedaron como tales:
--    SELECT tablename, permissive FROM pg_policies
--     WHERE policyname='planta_lockdown' LIMIT 3;                     -- 'RESTRICTIVE'
-- 5) Recorte fino en tablas op_*:
--    SELECT tablename, policyname FROM pg_policies
--     WHERE policyname IN ('planta_no_ins','planta_no_del');           -- 3 filas
