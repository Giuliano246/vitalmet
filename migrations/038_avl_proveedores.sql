-- ═══════════════════════════════════════════════════════════════════
-- 038_avl_proveedores.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 2.
-- AVL (Approved Vendor List): aprobación de proveedores con alcance,
-- criticidad y reevaluación, y GATE que impide enviar una OC de
-- material crítico a un proveedor no aprobado.
--
-- Qué agrega:
--   1. proveedores.aprobado / alcance_aprobacion / criticidad /
--      fecha_evaluacion / fecha_proxima_evaluacion.
--   2. Backfill: los proveedores activos existentes quedan aprobados
--      como "homologación inicial por historial de suministro" (la
--      evaluación formal con registro la exige el procedimiento PG de
--      compras de Fase 3). Sin esto, correr la migración frenaría las
--      compras en curso — el gate aplica pleno a proveedores NUEVOS.
--   3. fn_oc_avl_gate / trg_oc_avl_gate — al pasar una OC a 'enviada'
--      (o crearla directamente en un estado distinto de borrador/
--      anulada), si la OC tiene ítems de materia prima o el proveedor
--      es de criticidad 'critico', el proveedor debe estar aprobado.
--
-- Cláusulas: API Q1 §5.6.1.2 (evaluación y selección de proveedores),
--            ISO 9001:2015 §8.4 (control de procesos externos).
-- Requiere: 002 (proveedores, ordenes_compra, oc_items).
-- RETROCOMPATIBLE: por el backfill del punto 2, los flujos actuales
-- siguen funcionando; el gate solo frena OCs a proveedores nuevos no
-- evaluados.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Columnas AVL en proveedores ──────────────────────────────────
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS aprobado bool NOT NULL DEFAULT false;
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS alcance_aprobacion text;
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS criticidad text NOT NULL DEFAULT 'no_critico';
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS fecha_evaluacion date;
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS fecha_proxima_evaluacion date;

ALTER TABLE proveedores DROP CONSTRAINT IF EXISTS proveedores_criticidad_valida;
ALTER TABLE proveedores ADD CONSTRAINT proveedores_criticidad_valida
  CHECK (criticidad IN ('critico','no_critico'));

-- ─── 2. Backfill: homologación inicial de la base actual ─────────────
-- Solo la primera vez (aprobado=false y sin fecha de evaluación).
UPDATE proveedores SET
  aprobado = true,
  fecha_evaluacion = current_date,
  fecha_proxima_evaluacion = current_date + interval '1 year',
  alcance_aprobacion = COALESCE(alcance_aprobacion,
    'Homologación inicial por historial de suministro (regularizar según procedimiento de compras)')
WHERE activo = true AND aprobado = false AND fecha_evaluacion IS NULL;

-- ─── 3. Gate AVL en órdenes de compra ────────────────────────────────
-- Dispara cuando la OC deja de ser borrador (transición a 'enviada' o
-- INSERT directo en estado operativo). Bloquea si:
--   · la OC tiene ítems tipo 'materia_prima', o
--   · el proveedor es criticidad 'critico',
-- y el proveedor no está aprobado o su reevaluación está vencida.
CREATE OR REPLACE FUNCTION public.fn_oc_avl_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  p record;
  tiene_mp bool;
BEGIN
  -- Solo al salir de borrador (los estados posteriores ya pasaron el gate)
  IF NEW.estado IN ('borrador','anulada') THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.estado NOT IN ('borrador') THEN RETURN NEW; END IF;

  SELECT nombre, aprobado, criticidad, fecha_proxima_evaluacion INTO p
  FROM proveedores WHERE id = NEW.proveedor_id;

  SELECT EXISTS (
    SELECT 1 FROM oc_items WHERE oc_id = NEW.id AND tipo = 'materia_prima'
  ) INTO tiene_mp;

  IF tiene_mp OR p.criticidad = 'critico' THEN
    IF NOT COALESCE(p.aprobado, false) THEN
      RAISE EXCEPTION 'AVL: el proveedor % no está aprobado para material/servicio crítico. Evaluálo y aprobalo en Proveedores antes de enviar la OC.', p.nombre;
    END IF;
    IF p.fecha_proxima_evaluacion IS NOT NULL AND p.fecha_proxima_evaluacion < current_date THEN
      RAISE EXCEPTION 'AVL: la reevaluación del proveedor % venció el %. Reevaluálo antes de enviar la OC.', p.nombre, p.fecha_proxima_evaluacion;
    END IF;
  END IF;

  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_oc_avl_gate() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_oc_avl_gate ON ordenes_compra;
CREATE TRIGGER trg_oc_avl_gate
  BEFORE INSERT OR UPDATE OF estado ON ordenes_compra
  FOR EACH ROW EXECUTE FUNCTION public.fn_oc_avl_gate();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Columnas y backfill:
-- SELECT nombre, aprobado, criticidad, fecha_evaluacion, fecha_proxima_evaluacion
--   FROM proveedores ORDER BY nombre;
--
-- 2. Trigger:
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname = 'trg_oc_avl_gate' AND NOT tgisinternal;
--
-- 3. Smoke test del gate (proveedor de prueba NO aprobado + OC de MP
--    que intenta pasar a 'enviada' → debe fallar; limpia todo al final):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   prov uuid; oc uuid;
-- BEGIN
--   INSERT INTO proveedores (empresa_id, nombre, aprobado, criticidad)
--   VALUES (emp, '__TEST_AVL__', false, 'no_critico') RETURNING id INTO prov;
--   INSERT INTO ordenes_compra (empresa_id, nro, proveedor_id, fecha, estado)
--   VALUES (emp, '__TEST-AVL-1__', prov, current_date, 'borrador') RETURNING id INTO oc;
--   INSERT INTO oc_items (oc_id, tipo, descripcion, cantidad, precio_unitario, subtotal)
--   VALUES (oc, 'materia_prima', 'test 4130', 1, 1, 1);
--   BEGIN
--     UPDATE ordenes_compra SET estado = 'enviada' WHERE id = oc;
--     RAISE EXCEPTION 'ERROR: el gate AVL NO funcionó';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: OC bloqueada (%)', SQLERRM;
--   END;
--   DELETE FROM oc_items WHERE oc_id = oc;
--   DELETE FROM ordenes_compra WHERE id = oc;
--   DELETE FROM proveedores WHERE id = prov;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
