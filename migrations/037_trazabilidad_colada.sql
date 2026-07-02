-- ═══════════════════════════════════════════════════════════════════
-- 037_trazabilidad_colada.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 1.
-- Trazabilidad por colada (heat number): cerrar los eslabones débiles.
--
-- Qué arregla:
--   1. productos_terminados.nro_colada — la colada se propaga al PT al
--      crearlo (trigger copia desde barras.nro_colada). Hoy la colada
--      solo es alcanzable remontando FKs; si se pierde barra_id se
--      pierde el heat number. Backfill de los PT existentes.
--   2. tratamientos.proveedor_id — FK real a proveedores (hoy texto
--      libre). El tratamiento térmico (Q&T del 4130, PWHT) entra a la
--      cadena de trazabilidad y a la evaluación de proveedores (AVL).
--      Backfill por nombre. La columna vieja `proveedor` queda.
--   3. tratamientos.certificado_id — FK opcional a certificados, para
--      que el cert del tratamiento pueda vivir en la tabla de
--      certificados en vez de solo base64 embebido.
--   4. trg_audit sobre certificados y tratamientos (evidencia de
--      calidad: quién tocó qué y cuándo — Q1 4.5).
--
-- Cláusulas: ISO 9001:2015 §8.5.2 (identificación y trazabilidad),
--            API Q1 §5.7.6 / §4.5 (registros).
-- Requiere: 002 (proveedores), 023 (fn_audit).
-- RETROCOMPATIBLE: solo agrega columnas y triggers de copia/auditoría.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. La colada viaja con el producto terminado ────────────────────
ALTER TABLE productos_terminados ADD COLUMN IF NOT EXISTS nro_colada text;

CREATE OR REPLACE FUNCTION public.fn_pt_colada() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- INSERT: completar si falta. UPDATE de barra_id: refrescar desde la
  -- barra nueva (la colada vieja no puede quedar pegada al PT).
  IF NEW.barra_id IS NOT NULL
     AND (NEW.nro_colada IS NULL
          OR (TG_OP = 'UPDATE' AND NEW.barra_id IS DISTINCT FROM OLD.barra_id)) THEN
    SELECT nro_colada INTO NEW.nro_colada FROM barras WHERE id = NEW.barra_id;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_pt_colada() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_pt_colada ON productos_terminados;
CREATE TRIGGER trg_pt_colada
  BEFORE INSERT OR UPDATE OF barra_id ON productos_terminados
  FOR EACH ROW EXECUTE FUNCTION public.fn_pt_colada();

-- Backfill de los PT existentes que tienen barra
UPDATE productos_terminados pt SET nro_colada = b.nro_colada
FROM barras b
WHERE pt.barra_id = b.id AND pt.nro_colada IS NULL AND b.nro_colada IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pt_colada ON productos_terminados (nro_colada);

-- ─── 2. Tratamientos: proveedor por FK ───────────────────────────────
ALTER TABLE tratamientos ADD COLUMN IF NOT EXISTS proveedor_id uuid
  REFERENCES proveedores(id) ON DELETE SET NULL;

-- Backfill por nombre (case-insensitive); ante duplicados gana el más
-- antiguo (mismo criterio que el backfill de ventas.cliente_id en 023).
UPDATE tratamientos t SET proveedor_id = p.id
FROM (
  SELECT DISTINCT ON (empresa_id, lower(nombre)) id, empresa_id, lower(nombre) AS ln
  FROM proveedores ORDER BY empresa_id, lower(nombre), created_at
) p
WHERE t.proveedor_id IS NULL
  AND p.empresa_id = t.empresa_id
  AND p.ln = lower(COALESCE(t.proveedor, ''));

CREATE INDEX IF NOT EXISTS idx_tratamientos_proveedor ON tratamientos (proveedor_id);

-- ─── 3. Tratamientos: certificado por FK (opcional) ──────────────────
ALTER TABLE tratamientos ADD COLUMN IF NOT EXISTS certificado_id uuid
  REFERENCES certificados(id) ON DELETE SET NULL;

-- ─── 4. Auditoría sobre las tablas de evidencia de trazabilidad ──────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['certificados','tratamientos'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %I', t);
      EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I
                      FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
    END IF;
  END LOOP;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Columnas nuevas:
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name IN ('productos_terminados','tratamientos')
--    AND column_name IN ('nro_colada','proveedor_id','certificado_id');
--
-- 2. Cobertura del backfill (PT con barra que quedaron sin colada = la
--    barra no tiene nro_colada cargado — revisar a mano):
-- SELECT count(*) FILTER (WHERE nro_colada IS NOT NULL) AS con_colada,
--        count(*) FILTER (WHERE barra_id IS NOT NULL AND nro_colada IS NULL) AS barra_sin_colada
--   FROM productos_terminados;
--
-- 3. Tratamientos matcheados a proveedor:
-- SELECT count(*) FILTER (WHERE proveedor_id IS NOT NULL) AS con_fk,
--        count(*) FILTER (WHERE proveedor_id IS NULL) AS sin_fk
--   FROM tratamientos;
--
-- 4. Triggers:
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname IN ('trg_pt_colada','trg_audit')
--    AND tgrelid::regclass::text IN ('productos_terminados','certificados','tratamientos')
--    AND NOT tgisinternal;
