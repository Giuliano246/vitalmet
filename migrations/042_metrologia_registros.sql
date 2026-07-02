-- ═══════════════════════════════════════════════════════════════════
-- 042_metrologia_registros.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 7.
-- Control metrológico (calibración de instrumentos) y registros de
-- calidad (el ensayo hidrostático, dimensionales, END) con GATE:
-- un instrumento con calibración vencida no puede usarse en una
-- inspección.
--
-- Qué agrega:
--   1. herramientas.requiere_calibracion / frecuencia_calibracion_meses /
--      fecha_ultima_calibracion / vencimiento_calibracion /
--      patron_referencia. (El banco de hidro 22.000 psi y el WIKA
--      CPG1500 se marcan requiere_calibracion=true desde la UI.)
--   2. Tabla calibraciones: historial por instrumento con certificado
--      adjunto y laboratorio (FK a proveedores → entra a la AVL).
--      Una calibración 'conforme' actualiza fecha/vencimiento del
--      instrumento por trigger; una 'no_conforme' lo bloquea
--      (vencimiento a NULL → el gate lo rechaza).
--   3. Tabla registros_calidad: la evidencia colgada de la OP/operación/
--      recepción — tipo (hidrostatico, dimensional, visual, dureza,
--      END), instrumento usado, datos jsonb (presión, tiempo de
--      sostenimiento, mediciones), resultado, firmante, PDF.
--   4. fn_registro_calibracion_gate: BEFORE INSERT en registros_calidad
--      — si el instrumento requiere calibración y está vencido (o nunca
--      calibrado), EXCEPTION.
--   5. trg_audit en herramientas, calibraciones y registros_calidad.
--
-- Cláusulas: ISO 9001:2015 §7.1.5 (recursos de seguimiento y medición),
--            API Q1 §4.4.4 / §5.7.7. El hidro registra lo que exige
--            API 6A: presión, tiempo de sostenimiento y manómetro usado.
-- Requiere: herramientas (creada a mano), 001 (op_operaciones),
--           002 (proveedores, recepciones_oc), 023 (fn_audit).
-- RETROCOMPATIBLE: requiere_calibracion default false → nada se frena
-- hasta que marques los instrumentos.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Calibración en herramientas ──────────────────────────────────
ALTER TABLE herramientas ADD COLUMN IF NOT EXISTS requiere_calibracion bool NOT NULL DEFAULT false;
ALTER TABLE herramientas ADD COLUMN IF NOT EXISTS frecuencia_calibracion_meses int;
ALTER TABLE herramientas ADD COLUMN IF NOT EXISTS fecha_ultima_calibracion date;
ALTER TABLE herramientas ADD COLUMN IF NOT EXISTS vencimiento_calibracion date;
ALTER TABLE herramientas ADD COLUMN IF NOT EXISTS patron_referencia text;

-- ─── 2. Historial de calibraciones ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.calibraciones (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  herramienta_id  uuid        NOT NULL REFERENCES herramientas(id) ON DELETE CASCADE,
  fecha           date        NOT NULL DEFAULT current_date,
  resultado       text        NOT NULL DEFAULT 'conforme'
                              CHECK (resultado IN ('conforme','no_conforme')),
  certificado_nro text,
  laboratorio_id  uuid        REFERENCES proveedores(id) ON DELETE SET NULL,
  file_data       text,       -- PDF del certificado de calibración (base64)
  file_name       text,
  observaciones   text,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_calibraciones_herramienta ON calibraciones (herramienta_id, fecha DESC);

-- ─── 3. Registros de calidad (evidencia de inspección/ensayo) ────────
CREATE TABLE IF NOT EXISTS public.registros_calidad (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid        NOT NULL,
  orden_id       uuid        REFERENCES ordenes_produccion(id) ON DELETE SET NULL,
  operacion_id   uuid        REFERENCES op_operaciones(id)     ON DELETE SET NULL,
  recepcion_id   uuid        REFERENCES recepciones_oc(id)     ON DELETE SET NULL,
  tipo           text        NOT NULL
                             CHECK (tipo IN ('hidrostatico','dimensional','visual','dureza',
                                             'liquidos_penetrantes','particulas_magneticas','otro')),
  herramienta_id uuid        REFERENCES herramientas(id) ON DELETE SET NULL,
  datos          jsonb,      -- ej hidro: {"presion_psi":22000,"sostenimiento_min":3,"temperatura_c":21}
  resultado      text        NOT NULL DEFAULT 'conforme'
                             CHECK (resultado IN ('conforme','no_conforme')),
  observaciones  text,
  firmado_por    uuid,
  file_data      text,
  file_name      text,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_registros_calidad_orden ON registros_calidad (orden_id);
CREATE INDEX IF NOT EXISTS idx_registros_calidad_recepcion ON registros_calidad (recepcion_id);

-- ─── 4. RLS ──────────────────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['calibraciones','registros_calidad'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON public.%I
                    FOR ALL TO authenticated
                    USING  (empresa_id = (SELECT public.current_empresa_id()))
                    WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))', t);
  END LOOP;
END $$;

-- ─── 5. Una calibración actualiza (o bloquea) el instrumento ─────────
CREATE OR REPLACE FUNCTION public.fn_calibracion_aplicar() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.resultado = 'conforme' THEN
    UPDATE herramientas SET
      fecha_ultima_calibracion = NEW.fecha,
      vencimiento_calibracion = CASE
        WHEN frecuencia_calibracion_meses IS NOT NULL
        THEN (NEW.fecha + (frecuencia_calibracion_meses || ' months')::interval)::date
        ELSE vencimiento_calibracion END
    WHERE id = NEW.herramienta_id;
  ELSE
    -- No conforme: el instrumento queda bloqueado (sin vencimiento
    -- válido, el gate del punto 6 lo rechaza) y va a mantenimiento.
    UPDATE herramientas SET
      vencimiento_calibracion = NULL,
      estado = 'mantenimiento'
    WHERE id = NEW.herramienta_id;
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_calibracion_aplicar() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_calibracion_aplicar ON calibraciones;
CREATE TRIGGER trg_calibracion_aplicar
  AFTER INSERT ON calibraciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_calibracion_aplicar();

-- Estampar quién registró la calibración
CREATE OR REPLACE FUNCTION public.fn_calibracion_created_by() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_calibracion_created_by() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_calibracion_created_by ON calibraciones;
CREATE TRIGGER trg_calibracion_created_by
  BEFORE INSERT ON calibraciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_calibracion_created_by();

-- ─── 6. Gate: calibración vencida = instrumento inutilizable ─────────
CREATE OR REPLACE FUNCTION public.fn_registro_calibracion_gate() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE h record;
BEGIN
  NEW.firmado_por := COALESCE(NEW.firmado_por, auth.uid());
  IF NEW.herramienta_id IS NOT NULL THEN
    SELECT nombre, requiere_calibracion, vencimiento_calibracion INTO h
    FROM herramientas WHERE id = NEW.herramienta_id;
    IF COALESCE(h.requiere_calibracion, false)
       AND (h.vencimiento_calibracion IS NULL OR h.vencimiento_calibracion < current_date) THEN
      RAISE EXCEPTION 'El instrumento % tiene la calibración vencida (o nunca calibrado): no puede usarse en una inspección. Registrá la calibración primero.', h.nombre;
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_registro_calibracion_gate() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_registro_calibracion_gate ON registros_calidad;
CREATE TRIGGER trg_registro_calibracion_gate
  BEFORE INSERT ON registros_calidad
  FOR EACH ROW EXECUTE FUNCTION public.fn_registro_calibracion_gate();

-- ─── 7. Auditoría ────────────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['herramientas','calibraciones','registros_calidad'] LOOP
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
-- 1. Columnas y tablas:
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'herramientas' AND column_name LIKE '%calibracion%';
-- SELECT relname FROM pg_class WHERE relname IN ('calibraciones','registros_calidad');
--
-- 2. Smoke test del gate (instrumento que requiere calibración y nunca
--    se calibró → registrar una inspección con él debe fallar):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   h uuid;
-- BEGIN
--   INSERT INTO herramientas (empresa_id, codigo, nombre, cantidad, estado, requiere_calibracion, frecuencia_calibracion_meses)
--   VALUES (emp, '__TEST-CAL__', 'Manómetro test', 1, 'en-uso', true, 12) RETURNING id INTO h;
--   BEGIN
--     INSERT INTO registros_calidad (empresa_id, tipo, herramienta_id, resultado)
--     VALUES (emp, 'hidrostatico', h, 'conforme');
--     RAISE EXCEPTION 'ERROR: el gate de calibración NO funcionó';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: inspección bloqueada (%)', SQLERRM;
--   END;
--   -- Calibrarlo la habilita:
--   INSERT INTO calibraciones (empresa_id, herramienta_id, fecha, resultado, certificado_nro)
--   VALUES (emp, h, current_date, 'conforme', 'TEST-001');
--   INSERT INTO registros_calidad (empresa_id, tipo, herramienta_id, resultado, datos)
--   VALUES (emp, 'hidrostatico', h, 'conforme', '{"presion_psi":22000,"sostenimiento_min":3}');
--   RAISE NOTICE 'OK: con calibración vigente la inspección pasa';
--   DELETE FROM registros_calidad WHERE herramienta_id = h;
--   DELETE FROM calibraciones WHERE herramienta_id = h;
--   DELETE FROM herramientas WHERE id = h;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
