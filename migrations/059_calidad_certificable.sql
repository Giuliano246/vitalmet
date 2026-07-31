-- ═══════════════════════════════════════════════════════════════════
-- 059_calidad_certificable.sql — Sprint 5 de la auditoría 2026-07-30
--
--   1. Certificados de conformidad EMITIDOS (G7): registro correlativo
--      CC-nnnn por venta. Hoy generateCertConformidadPDF hace doc.save()
--      y no queda rastro; ahora cada emisión se numera y persiste.
--   2. Revisión por la dirección (ISO 9001 §9.3 / API Q1 §5.1.3, G2):
--      snapshot de KPIs congelado + decisiones/acciones. Cerrada =
--      inmutable (trigger).
--   3. Auditorías internas (§9.2 / Q1 §5.9, G1): programa + ejecución
--      + hallazgos tipificados, con link a NC (origen 'auditoria').
--   4. Matriz de competencias (§7.2 / Q1 §5.3, G3): persona ×
--      habilidad con nivel, vencimiento y evidencia.
--   5. Modo auditor solo lectura: usuarios.es_auditor. Reutiliza el
--      cerrojo del Modo Contador (053): es_contador() pasa a devolver
--      true también para auditores → las ~40 tablas con policies
--      contador_no_* y el trigger contador_guard lo cubren sin crear
--      una sola policy nueva.
--
-- Requiere: 043 (no_conformidades), 052/053 (es_planta/es_contador,
-- fn_contador_guard), 055 (guardar_permisos — acá se RE-EMITE con
-- p_es_auditor). Idempotente. Correr ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Batería RLS estándar (helper local del script) ─────────────────
CREATE OR REPLACE FUNCTION pg_temp.aplicar_bateria(t text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
  EXECUTE format('CREATE POLICY tenant_isolation ON public.%I FOR ALL TO authenticated
    USING (empresa_id = (SELECT public.current_empresa_id()))
    WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))', t);
  EXECUTE format('DROP POLICY IF EXISTS planta_lockdown ON public.%I', t);
  EXECUTE format('CREATE POLICY planta_lockdown ON public.%I AS RESTRICTIVE FOR ALL TO authenticated
    USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta())', t);
  EXECUTE format('DROP POLICY IF EXISTS contador_no_ins ON public.%I', t);
  EXECUTE format('CREATE POLICY contador_no_ins ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK ((SELECT NOT public.es_contador()))', t);
  EXECUTE format('DROP POLICY IF EXISTS contador_no_upd ON public.%I', t);
  EXECUTE format('CREATE POLICY contador_no_upd ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated
    USING ((SELECT NOT public.es_contador()))', t);
  EXECUTE format('DROP POLICY IF EXISTS contador_no_del ON public.%I', t);
  EXECUTE format('CREATE POLICY contador_no_del ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated
    USING ((SELECT NOT public.es_contador()))', t);
  EXECUTE format('DROP TRIGGER IF EXISTS contador_guard ON public.%I', t);
  EXECUTE format('CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I
    FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard()', t);
  EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I', t);
  EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
END $$;

-- ─── 1. Certificados de conformidad emitidos ────────────────────────

CREATE TABLE IF NOT EXISTS public.certificados_emitidos (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid        NOT NULL,
  numero        int,
  venta_id      uuid        NOT NULL UNIQUE REFERENCES public.ventas(id) ON DELETE RESTRICT,
  cliente       text,
  remito        text,
  fecha         date        NOT NULL DEFAULT CURRENT_DATE,
  items_resumen jsonb,      -- snapshot: piezas, lotes, coladas, MTCs al momento de emitir
  emitido_por   uuid,
  created_at    timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('certificados_emitidos');
CREATE INDEX IF NOT EXISTS idx_cert_emitidos_empresa
  ON public.certificados_emitidos (empresa_id, numero DESC);

CREATE OR REPLACE FUNCTION public.fn_cert_emitido_nro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.numero IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('cert_emitido_nro:' || NEW.empresa_id::text, 0));
    SELECT COALESCE(MAX(numero), 0) + 1 INTO NEW.numero
      FROM certificados_emitidos WHERE empresa_id = NEW.empresa_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_cert_emitido_nro ON public.certificados_emitidos;
CREATE TRIGGER trg_cert_emitido_nro BEFORE INSERT ON public.certificados_emitidos
  FOR EACH ROW EXECUTE FUNCTION public.fn_cert_emitido_nro();

-- ─── 2. Revisión por la dirección ───────────────────────────────────

CREATE TABLE IF NOT EXISTS public.revisiones_direccion (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid        NOT NULL,
  nro           text,
  fecha         date        NOT NULL DEFAULT CURRENT_DATE,
  periodo_desde date        NOT NULL,
  periodo_hasta date        NOT NULL,
  kpis          jsonb,      -- snapshot congelado al crear (OTD, NCs, CAPA, calibraciones…)
  asistentes    text,
  temas         text,       -- entradas revisadas (además de los KPIs)
  decisiones    text,
  acciones      text,       -- salidas: acciones con responsable y plazo
  estado        text        NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','cerrada')),
  cerrada_at    timestamptz,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('revisiones_direccion');

CREATE OR REPLACE FUNCTION public.fn_revdir_nro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('revdir_nro:' || NEW.empresa_id::text, 0));
    SELECT 'RD-' || lpad((COALESCE(MAX(substring(r.nro from 4)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM revisiones_direccion r
      WHERE r.empresa_id = NEW.empresa_id AND r.nro ~ '^RD-[0-9]+$';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_revdir_nro ON public.revisiones_direccion;
CREATE TRIGGER trg_revdir_nro BEFORE INSERT ON public.revisiones_direccion
  FOR EACH ROW EXECUTE FUNCTION public.fn_revdir_nro();

-- Una revisión cerrada es un registro de calidad: inmutable
CREATE OR REPLACE FUNCTION public.fn_revdir_inmutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.estado = 'cerrada' THEN
      RAISE EXCEPTION 'La revisión % está cerrada: es un registro del SGC y no se puede eliminar', OLD.nro;
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.estado = 'cerrada' THEN
    RAISE EXCEPTION 'La revisión % está cerrada y no se puede modificar', OLD.nro;
  END IF;
  IF NEW.estado = 'cerrada' AND NEW.cerrada_at IS NULL THEN NEW.cerrada_at := now(); END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_revdir_inmutable ON public.revisiones_direccion;
CREATE TRIGGER trg_revdir_inmutable BEFORE UPDATE OR DELETE ON public.revisiones_direccion
  FOR EACH ROW EXECUTE FUNCTION public.fn_revdir_inmutable();

-- ─── 3. Auditorías internas ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.auditorias_internas (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid        NOT NULL,
  nro              text,
  alcance          text        NOT NULL,   -- proceso / área auditada
  criterios        text,                   -- ISO 9001 §x, API Q1 §y, PG-zz
  auditor          text,
  fecha_planificada date,
  fecha_realizada  date,
  estado           text        NOT NULL DEFAULT 'planificada'
                               CHECK (estado IN ('planificada','en_curso','cerrada')),
  conclusiones     text,
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('auditorias_internas');

CREATE TABLE IF NOT EXISTS public.auditoria_hallazgos (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid        NOT NULL,
  auditoria_id uuid        NOT NULL REFERENCES public.auditorias_internas(id) ON DELETE CASCADE,
  tipo         text        NOT NULL CHECK (tipo IN ('conforme','observacion','nc_menor','nc_mayor','oportunidad')),
  clausula     text,       -- requisito auditado (ej. "ISO 9001 §7.1.5")
  descripcion  text        NOT NULL,
  nc_id        uuid        REFERENCES public.no_conformidades(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('auditoria_hallazgos');
CREATE INDEX IF NOT EXISTS idx_hallazgos_auditoria ON public.auditoria_hallazgos (auditoria_id);

CREATE OR REPLACE FUNCTION public.fn_auditoria_nro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('auditoria_nro:' || NEW.empresa_id::text, 0));
    SELECT 'AI-' || lpad((COALESCE(MAX(substring(a.nro from 4)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM auditorias_internas a
      WHERE a.empresa_id = NEW.empresa_id AND a.nro ~ '^AI-[0-9]+$';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_auditoria_nro ON public.auditorias_internas;
CREATE TRIGGER trg_auditoria_nro BEFORE INSERT ON public.auditorias_internas
  FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_nro();

-- ─── 4. Matriz de competencias ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.competencias (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid        NOT NULL,
  persona            text        NOT NULL,   -- texto libre: la planta comparte cuenta
  puesto             text,
  habilidad          text        NOT NULL,   -- ej. "Torno CNC", "Inspección dimensional"
  nivel              text        NOT NULL DEFAULT 'calificado'
                                 CHECK (nivel IN ('en_formacion','calificado','experto')),
  fecha_calificacion date,
  vence              date,                   -- NULL = no vence
  evidencia          text,                   -- curso, certificado, evaluación interna
  observaciones      text,
  created_by         uuid,
  created_at         timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('competencias');
CREATE INDEX IF NOT EXISTS idx_competencias_persona ON public.competencias (empresa_id, persona);

-- ─── 5. Modo auditor (solo lectura total) ───────────────────────────

ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS es_auditor boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.es_auditor()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT COALESCE((SELECT u.es_auditor FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_auditor() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_auditor() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_auditor() TO authenticated;

-- es_contador() pasa a significar "usuario de solo lectura" (contador
-- O auditor): todas las policies contador_no_* y el contador_guard
-- existentes cubren al auditor sin tocar una sola tabla.
CREATE OR REPLACE FUNCTION public.es_contador()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT COALESCE((SELECT u.es_contador OR u.es_auditor FROM usuarios u WHERE u.id = auth.uid()), false)
$$;

CREATE OR REPLACE FUNCTION public.fn_contador_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF public.es_contador() THEN
    RAISE EXCEPTION 'Modo solo lectura (contador/auditor): no se puede escribir';
  END IF;
  RETURN NULL;
END $$;

-- guardar_permisos re-emitida (de 055) con p_es_auditor
DROP FUNCTION IF EXISTS public.guardar_permisos(uuid, boolean, boolean, boolean, text[]);
CREATE OR REPLACE FUNCTION public.guardar_permisos(
  p_usuario_id uuid,
  p_es_admin   boolean,
  p_ver_costos boolean,
  p_es_contador boolean,
  p_modulos    text[],
  p_es_auditor boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  m   text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND es_admin = true) THEN
    RAISE EXCEPTION 'Solo un administrador puede cambiar permisos';
  END IF;
  IF p_es_admin AND (p_es_contador OR p_es_auditor) THEN
    RAISE EXCEPTION 'Un usuario de solo lectura (contador/auditor) no puede ser administrador';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_usuario_id AND empresa_id = emp) THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;

  -- El trigger usuarios_guard (022/050) sigue vigilando la escalada
  UPDATE usuarios
  SET es_admin = p_es_admin, ver_costos = p_ver_costos,
      es_contador = p_es_contador, es_auditor = p_es_auditor
  WHERE id = p_usuario_id AND empresa_id = emp;

  DELETE FROM permisos_usuario WHERE usuario_id = p_usuario_id AND empresa_id = emp;
  IF NOT p_es_admin THEN
    FOREACH m IN ARRAY COALESCE(p_modulos, '{}') LOOP
      INSERT INTO permisos_usuario (empresa_id, usuario_id, modulo)
      VALUES (emp, p_usuario_id, m);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('ok', true, 'modulos', COALESCE(array_length(p_modulos, 1), 0));
END $$;
REVOKE EXECUTE ON FUNCTION public.guardar_permisos(uuid, boolean, boolean, boolean, text[], boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_permisos(uuid, boolean, boolean, boolean, text[], boolean) TO authenticated;

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT tablename, count(*) FROM pg_policies
--   WHERE tablename IN ('certificados_emitidos','revisiones_direccion',
--                       'auditorias_internas','auditoria_hallazgos','competencias')
--   GROUP BY 1;                                             -- 5 policies c/u
-- SELECT proname FROM pg_proc WHERE proname IN ('es_auditor','fn_cert_emitido_nro','fn_revdir_nro','fn_auditoria_nro');
-- SELECT column_name FROM information_schema.columns WHERE table_name='usuarios' AND column_name='es_auditor';
