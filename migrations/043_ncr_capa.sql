-- ═══════════════════════════════════════════════════════════════════
-- 043_ncr_capa.sql
-- Capa de calidad ISO 9001 / API Q1 — Fase 2, GAP 6.
-- No conformidades (NCR) y acciones correctivas/preventivas (CAPA).
--
-- Qué agrega:
--   1. Tabla no_conformidades: numerada por la DB (advisory lock, mismo
--      patrón que asientos), con origen enlazado a la transacción real
--      (recepción / OP / venta / registro de calidad), disposición y
--      estado. Guard: no se cierra sin disposición.
--   2. Tabla acciones_capa: correctivas y preventivas, con causa raíz,
--      responsable, fechas de compromiso/implementación y verificación
--      de eficacia. Guard: no se cierra sin verificar eficacia (Q1 la
--      exige explícitamente).
--   3. RLS tenant_isolation + trg_audit en ambas.
--
-- Cláusulas: ISO 9001:2015 §8.7 (salidas no conformes) / §10.2 (no
--            conformidad y acción correctiva), API Q1 §5.10 (control de
--            producto no conforme) / §5.11 (CAPA, incl. verificación
--            de eficacia) / §5.10.3 (notificación al cliente si el
--            producto ya fue entregado — campo cliente_notificado).
-- Requiere: 006 (current_empresa_id), 023 (fn_audit), 042 (registros_calidad).
-- RETROCOMPATIBLE: tablas nuevas, no toca nada existente.
-- Idempotente. Correr en el SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. No conformidades ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.no_conformidades (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          uuid        NOT NULL,
  numero              int,        -- numerada por trigger si viene NULL
  fecha               date        NOT NULL DEFAULT current_date,
  origen_tipo         text        NOT NULL DEFAULT 'produccion'
                                  CHECK (origen_tipo IN ('recepcion','produccion','cliente',
                                                         'proveedor','auditoria','otro')),
  recepcion_id        uuid        REFERENCES recepciones_oc(id)     ON DELETE SET NULL,
  orden_id            uuid        REFERENCES ordenes_produccion(id) ON DELETE SET NULL,
  venta_id            uuid        REFERENCES ventas(id)             ON DELETE SET NULL,
  registro_calidad_id uuid        REFERENCES registros_calidad(id)  ON DELETE SET NULL,
  descripcion         text        NOT NULL,
  disposicion         text        CHECK (disposicion IN ('retrabajo','reproceso','rechazo',
                                                         'concesion','devolucion_proveedor')),
  justificacion       text,       -- obligatoria de facto para 'concesion' (la fija el procedimiento)
  cliente_notificado  bool,       -- Q1 5.10.3: si el producto NC ya fue entregado
  estado              text        NOT NULL DEFAULT 'abierta'
                                  CHECK (estado IN ('abierta','en_tratamiento','cerrada')),
  detectado_por       uuid,
  cerrada_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_nc_estado ON no_conformidades (empresa_id, estado);

-- ─── 2. Acciones CAPA ────────────────────────────────────────────────
-- nc_id nullable: una acción preventiva puede nacer de un análisis de
-- riesgo o auditoría, sin NC asociada.
CREATE TABLE IF NOT EXISTS public.acciones_capa (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            uuid        NOT NULL,
  numero                int,        -- numerada por trigger si viene NULL
  nc_id                 uuid        REFERENCES no_conformidades(id) ON DELETE SET NULL,
  tipo                  text        NOT NULL DEFAULT 'correctiva'
                                    CHECK (tipo IN ('correctiva','preventiva')),
  causa_raiz            text,
  accion                text        NOT NULL,
  responsable_id        uuid        REFERENCES usuarios(id) ON DELETE SET NULL,
  fecha_compromiso      date,
  fecha_implementacion  date,
  verificacion_eficacia text,
  eficaz                bool,
  estado                text        NOT NULL DEFAULT 'abierta'
                                    CHECK (estado IN ('abierta','implementada','verificada','cerrada')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_capa_estado ON acciones_capa (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_capa_nc ON acciones_capa (nc_id);

-- ─── 3. RLS + auditoría ──────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['no_conformidades','acciones_capa'] LOOP
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

-- ─── 4. Numeración por la DB (patrón fn_asiento_numero de 023) ───────
CREATE OR REPLACE FUNCTION public.fn_nc_numero() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.numero IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      TG_TABLE_NAME || '_numero:' || NEW.empresa_id::text, 0));
    EXECUTE format('SELECT COALESCE(MAX(numero), 0) + 1 FROM %I WHERE empresa_id = $1',
                   TG_TABLE_NAME)
    INTO NEW.numero USING NEW.empresa_id;
  END IF;
  IF TG_TABLE_NAME = 'no_conformidades' THEN
    NEW.detectado_por := COALESCE(NEW.detectado_por, auth.uid());
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_numero() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_nc_numero ON no_conformidades;
CREATE TRIGGER trg_nc_numero
  BEFORE INSERT ON no_conformidades
  FOR EACH ROW EXECUTE FUNCTION public.fn_nc_numero();

DROP TRIGGER IF EXISTS trg_capa_numero ON acciones_capa;
CREATE TRIGGER trg_capa_numero
  BEFORE INSERT ON acciones_capa
  FOR EACH ROW EXECUTE FUNCTION public.fn_nc_numero();

-- ─── 5. Guards de cierre ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nc_cierre_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'cerrada' AND OLD.estado IS DISTINCT FROM 'cerrada' THEN
    IF NEW.disposicion IS NULL THEN
      -- Literales adyacentes separados por newline se concatenan (SQL estándar)
      RAISE EXCEPTION 'La NC % no se puede cerrar sin disposición '
        '(retrabajo/reproceso/rechazo/concesión/devolución)', NEW.numero;
    END IF;
    NEW.cerrada_at := COALESCE(NEW.cerrada_at, now());
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_cierre_guard() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_nc_cierre_guard ON no_conformidades;
CREATE TRIGGER trg_nc_cierre_guard
  BEFORE UPDATE OF estado ON no_conformidades
  FOR EACH ROW EXECUTE FUNCTION public.fn_nc_cierre_guard();

CREATE OR REPLACE FUNCTION public.fn_capa_cierre_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF NEW.estado = 'cerrada' AND OLD.estado IS DISTINCT FROM 'cerrada' THEN
    IF NEW.eficaz IS NULL OR COALESCE(trim(NEW.verificacion_eficacia), '') = '' THEN
      RAISE EXCEPTION 'La CAPA % no se puede cerrar sin verificación '
        'de eficacia (API Q1 §5.11)', NEW.numero;
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_capa_cierre_guard() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_capa_cierre_guard ON acciones_capa;
CREATE TRIGGER trg_capa_cierre_guard
  BEFORE UPDATE OF estado ON acciones_capa
  FOR EACH ROW EXECUTE FUNCTION public.fn_capa_cierre_guard();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Tablas, RLS y triggers:
-- SELECT relname, relrowsecurity FROM pg_class
--  WHERE relname IN ('no_conformidades','acciones_capa');
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgrelid::regclass::text IN ('no_conformidades','acciones_capa')
--    AND NOT tgisinternal;
--
-- 2. Smoke test (numeración + guards de cierre; limpia al final):
-- DO $$
-- DECLARE
--   emp uuid := (SELECT public.current_empresa_id());
--   nc uuid; n int;
-- BEGIN
--   INSERT INTO no_conformidades (empresa_id, descripcion)
--   VALUES (emp, '__TEST NC__') RETURNING id, numero INTO nc, n;
--   RAISE NOTICE 'NC numerada automáticamente: %', n;
--   BEGIN
--     UPDATE no_conformidades SET estado = 'cerrada' WHERE id = nc;
--     RAISE EXCEPTION 'ERROR: la NC cerró sin disposición';
--   EXCEPTION WHEN others THEN
--     RAISE NOTICE 'OK: cierre bloqueado (%)', SQLERRM;
--   END;
--   UPDATE no_conformidades SET disposicion = 'retrabajo', estado = 'cerrada' WHERE id = nc;
--   RAISE NOTICE 'OK: con disposición cierra';
--   DELETE FROM acciones_capa WHERE nc_id = nc;
--   DELETE FROM no_conformidades WHERE id = nc;
--   RAISE NOTICE 'Smoke test completado.';
-- END $$;
