-- ═══════════════════════════════════════════════════════════════════
-- 041_pqp_hold_points.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAPs 4 y 5.
-- PQP (Product Quality Plan) ejecutable sobre el routing existente
-- (op_operaciones, migración 001): hold/witness points que FRENAN el
-- avance de la OP sin signoff, y referencia al documento controlado
-- (WPS de soldadura, instructivo de mecanizado/hidro) por operación.
--
-- Qué agrega:
--   1. op_operaciones.tipo_punto ('normal'|'hold'|'witness'),
--      signoff_usuario_id, signoff_at, signoff_obs, documento_id
--      (FK a documentos_controlados — el WPS/instructivo vigente).
--   2. pqp_plantillas + pqp_plantilla_operaciones: el routing modelo
--      por producto (fig. 1502, pup joint, coupling, unión doble) que
--      se instancia al crear la OP.
--   3. RPC instanciar_pqp(orden_id, plantilla_id): copia las
--      operaciones de la plantilla a la OP en una transacción.
--   4. fn_op_quality_gate: BEFORE en op_operaciones —
--      · una operación no arranca ni se completa si una anterior con
--        tipo_punto='hold' no tiene signoff;
--      · una operación hold/witness no se completa sin su PROPIO signoff;
--      · firmar estampa usuario/fecha;
--      · documento_id debe apuntar a un documento 'vigente' (nadie
--        suelda con un WPS obsoleto).
--   5. fn_op_cierre_gate: la OP no pasa a 'completada' con hold/witness
--      points sin firmar.
--
-- Cláusulas: API Q1 §5.7.1.2 (Product Quality Plan) / §5.7.7
--            (inspección y ensayo), ISO 9001:2015 §8.5.1.
-- Requiere: 001 (op_operaciones), 040 (documentos_controlados).
-- RETROCOMPATIBLE: las OPs existentes tienen tipo_punto='normal' en
-- todas sus operaciones → ningún gate las frena.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Hold/witness points en el routing ────────────────────────────
ALTER TABLE op_operaciones ADD COLUMN IF NOT EXISTS tipo_punto text NOT NULL DEFAULT 'normal';
ALTER TABLE op_operaciones ADD COLUMN IF NOT EXISTS signoff_usuario_id uuid;
ALTER TABLE op_operaciones ADD COLUMN IF NOT EXISTS signoff_at timestamptz;
ALTER TABLE op_operaciones ADD COLUMN IF NOT EXISTS signoff_obs text;
ALTER TABLE op_operaciones ADD COLUMN IF NOT EXISTS documento_id uuid
  REFERENCES documentos_controlados(id) ON DELETE SET NULL;

ALTER TABLE op_operaciones DROP CONSTRAINT IF EXISTS op_operaciones_tipo_punto_valido;
ALTER TABLE op_operaciones ADD CONSTRAINT op_operaciones_tipo_punto_valido
  CHECK (tipo_punto IN ('normal','hold','witness'));

-- ─── 2. Plantillas PQP ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pqp_plantillas (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid        NOT NULL,
  codigo       text        NOT NULL,               -- ej: PQP-1502
  producto     text        NOT NULL,               -- pieza/familia: unión fig. 1502, pup joint...
  descripcion  text,
  documento_id uuid        REFERENCES documentos_controlados(id) ON DELETE SET NULL, -- el PQP como doc controlado
  activo       bool        NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, codigo)
);

CREATE TABLE IF NOT EXISTS public.pqp_plantilla_operaciones (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          uuid        NOT NULL,
  plantilla_id        uuid        NOT NULL REFERENCES pqp_plantillas(id) ON DELETE CASCADE,
  secuencia           int         NOT NULL,
  nombre              text        NOT NULL,
  maquina             text,
  tipo_punto          text        NOT NULL DEFAULT 'normal'
                                  CHECK (tipo_punto IN ('normal','hold','witness')),
  documento_id        uuid        REFERENCES documentos_controlados(id) ON DELETE SET NULL,
  tiempo_estimado_min int         NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pqp_ops_plantilla ON pqp_plantilla_operaciones (plantilla_id, secuencia);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pqp_plantillas','pqp_plantilla_operaciones'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON public.%I
                    FOR ALL TO authenticated
                    USING  (empresa_id = (SELECT public.current_empresa_id()))
                    WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
  END LOOP;
END $$;

-- ─── 3. RPC instanciar_pqp ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.instanciar_pqp(p_orden_id uuid, p_plantilla_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  pl record; n int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO pl FROM pqp_plantillas WHERE id = p_plantilla_id AND empresa_id = emp;
  IF pl.id IS NULL THEN RAISE EXCEPTION 'Plantilla PQP no encontrada'; END IF;
  IF NOT pl.activo THEN RAISE EXCEPTION 'La plantilla % está inactiva', pl.codigo; END IF;
  IF NOT EXISTS (SELECT 1 FROM ordenes_produccion WHERE id = p_orden_id AND empresa_id = emp) THEN
    RAISE EXCEPTION 'Orden de producción no encontrada';
  END IF;
  IF EXISTS (SELECT 1 FROM op_operaciones WHERE orden_id = p_orden_id) THEN
    RAISE EXCEPTION 'La OP ya tiene operaciones cargadas: borralas antes de aplicar el PQP %', pl.codigo;
  END IF;

  INSERT INTO op_operaciones (empresa_id, orden_id, secuencia, nombre, maquina,
                              tiempo_estimado_min, estado, tipo_punto, documento_id)
  SELECT emp, p_orden_id, po.secuencia, po.nombre, po.maquina,
         po.tiempo_estimado_min, 'pendiente', po.tipo_punto, po.documento_id
  FROM pqp_plantilla_operaciones po
  WHERE po.plantilla_id = p_plantilla_id
  ORDER BY po.secuencia;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE EXCEPTION 'La plantilla % no tiene operaciones', pl.codigo; END IF;

  RETURN jsonb_build_object('operaciones', n, 'plantilla', pl.codigo);
END $$;
REVOKE ALL ON FUNCTION public.instanciar_pqp(uuid, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.instanciar_pqp(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.instanciar_pqp(uuid, uuid) TO authenticated;

-- ─── 4. Gate de calidad en las operaciones ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_op_quality_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  v_hold record;
  v_doc_estado text;
BEGIN
  -- Firmar estampa usuario y fecha
  IF NEW.signoff_at IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.signoff_at IS NULL) THEN
    NEW.signoff_usuario_id := COALESCE(NEW.signoff_usuario_id, auth.uid());
  END IF;

  -- El documento referenciado (WPS/instructivo) debe estar vigente
  IF NEW.documento_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.documento_id IS DISTINCT FROM OLD.documento_id) THEN
    SELECT estado INTO v_doc_estado FROM documentos_controlados WHERE id = NEW.documento_id;
    IF v_doc_estado IS DISTINCT FROM 'vigente' THEN
      RAISE EXCEPTION 'El documento referenciado no está vigente (estado: %). Usá la revisión vigente.', COALESCE(v_doc_estado, 'inexistente');
    END IF;
  END IF;

  -- Avanzar de estado con un hold point anterior sin firmar: bloqueado
  IF NEW.estado IN ('en_curso','completada')
     AND (TG_OP = 'INSERT' OR NEW.estado IS DISTINCT FROM OLD.estado) THEN
    SELECT o.secuencia, o.nombre INTO v_hold
    FROM op_operaciones o
    WHERE o.orden_id = NEW.orden_id AND o.id <> NEW.id
      AND o.secuencia < NEW.secuencia
      AND o.tipo_punto = 'hold' AND o.signoff_at IS NULL
    ORDER BY o.secuencia LIMIT 1;
    IF v_hold.secuencia IS NOT NULL THEN
      RAISE EXCEPTION 'Hold point sin liberar: la operación % (%) requiere signoff de calidad antes de avanzar', v_hold.secuencia, v_hold.nombre;
    END IF;
  END IF;

  -- Un hold/witness no se completa sin su propio signoff
  IF NEW.estado = 'completada' AND NEW.tipo_punto IN ('hold','witness')
     AND NEW.signoff_at IS NULL THEN
    RAISE EXCEPTION 'La operación % es un punto de % y no se puede completar sin signoff', NEW.nombre, NEW.tipo_punto;
  END IF;

  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_op_quality_gate() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_op_quality_gate ON op_operaciones;
CREATE TRIGGER trg_op_quality_gate
  BEFORE INSERT OR UPDATE ON op_operaciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_op_quality_gate();

-- ─── 5. Gate de cierre de la OP ──────────────────────────────────────
-- ordenes_produccion.estado es texto libre ('en-proceso'|'completada'|
-- 'suspendida' desde el front): el gate solo actúa al pasar a 'completada'.
CREATE OR REPLACE FUNCTION public.fn_op_cierre_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_pend record;
BEGIN
  IF NEW.estado = 'completada' AND OLD.estado IS DISTINCT FROM 'completada' THEN
    SELECT o.secuencia, o.nombre, o.tipo_punto INTO v_pend
    FROM op_operaciones o
    WHERE o.orden_id = NEW.id AND o.tipo_punto IN ('hold','witness') AND o.signoff_at IS NULL
    ORDER BY o.secuencia LIMIT 1;
    IF v_pend.secuencia IS NOT NULL THEN
      RAISE EXCEPTION 'No se puede completar la OP: la operación % (%) es un punto de % sin signoff', v_pend.secuencia, v_pend.nombre, v_pend.tipo_punto;
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_op_cierre_gate() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_op_cierre_gate ON ordenes_produccion;
CREATE TRIGGER trg_op_cierre_gate
  BEFORE UPDATE OF estado ON ordenes_produccion
  FOR EACH ROW EXECUTE FUNCTION public.fn_op_cierre_gate();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Columnas y tablas:
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'op_operaciones'
--    AND column_name IN ('tipo_punto','signoff_usuario_id','signoff_at','documento_id');
-- SELECT relname FROM pg_class WHERE relname LIKE 'pqp_%';
--
-- 2. Smoke test del hold point (OP de prueba con hold sin firmar →
--    completar la operación siguiente debe fallar; limpia al final):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   op uuid; o2 uuid;
-- BEGIN
--   INSERT INTO ordenes_produccion (empresa_id, nro, pieza, cantidad, estado, fecha)
--   VALUES (emp, '__TEST-PQP__', 'test', 1, 'en-proceso', current_date) RETURNING id INTO op;
--   INSERT INTO op_operaciones (empresa_id, orden_id, secuencia, nombre, tipo_punto, estado)
--   VALUES (emp, op, 1, 'Inspección dimensional', 'hold', 'pendiente');
--   INSERT INTO op_operaciones (empresa_id, orden_id, secuencia, nombre, estado)
--   VALUES (emp, op, 2, 'Roscado', 'pendiente') RETURNING id INTO o2;
--   BEGIN
--     UPDATE op_operaciones SET estado = 'en_curso' WHERE id = o2;
--     RAISE EXCEPTION 'ERROR: el hold point NO frenó el avance';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: avance bloqueado (%)', SQLERRM;
--   END;
--   DELETE FROM op_operaciones WHERE orden_id = op;
--   DELETE FROM ordenes_produccion WHERE id = op;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
