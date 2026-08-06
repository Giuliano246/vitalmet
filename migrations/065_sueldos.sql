-- ═══════════════════════════════════════════════════════════════════
-- 065_sueldos.sql
-- Módulo Sueldos — Fase 1: registro de nómina (la contadora liquida
-- afuera, el ERP contabiliza). Ver análisis 2026-08-06.
--
-- Contexto regulatorio (reforma laboral Ley 27.802 + Dec. 407/2026):
-- el libro de sueldos ya no es obligatorio, el recibo digital se emite
-- vía ARCA y el F.931 lo presenta la contadora → el ERP NO liquida ni
-- emite recibos. Registra la liquidación ya hecha (10 empleados) y
-- genera el asiento de devengamiento + integra cashflow y costos.
--
-- Diseño:
--   · `empleados` — legajo con centro de costo fabricacion/administracion
--     (mapea a las cuentas reales del plan: 421001/421002 y 422003/422004)
--     y `operario_nombre` para linkear con OPs/timers de Modo Planta (Fase 2).
--   · `liquidaciones` + `liquidacion_items` — una por período y tipo
--     (mensual/quincenas/SAC/vacaciones/final). Montos en ARS (los
--     sueldos son ARS; el core USD convierte con el TC guardado al
--     confirmar). Totales de cabecera calculados server-side.
--   · RPC `guardar_liquidacion` (borrador, valida neto = bruto + no_rem
--     − aportes por ítem), `confirmar_liquidacion` (genera el asiento
--     vía crear_asiento: gastos por centro al debe, 214006 SUELDOS A
--     PAGAR por el neto y 214007 Cargas Sociales a Pagar por aportes +
--     contribuciones + ART al haber) y `anular_liquidacion` (confirmada
--     → asiento anulado y vuelve a borrador; borrador → se borra).
--   · Provisión mensual de SAC/vacaciones: FUERA de Fase 1 (decisión:
--     con 10 empleados la contadora registra el SAC al devengarlo
--     jun/dic como liquidación tipo 'sac').
--
-- Sensibilidad: sueldos es dato caliente → batería RLS completa
-- (tenant + planta_lockdown + contador solo-lectura + audit) en las
-- 3 tablas. Módulo de permisos nuevo 'sueldos' (solo frontend).
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Batería RLS estándar (molde 052/053/059) ─────────────────────
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

-- ─── 1. Empleados ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.empleados (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  legajo          text,
  nombre          text        NOT NULL,
  cuil            text,
  categoria       text,       -- categoría CCT 260/75 (Operario, Op. Calificado, Oficial, etc.)
  rama            text,       -- rama UOM (17 metalmecánica, etc.)
  centro          text        NOT NULL DEFAULT 'fabricacion'
                              CHECK (centro IN ('fabricacion','administracion')),
  modalidad       text        NOT NULL DEFAULT 'jornal'
                              CHECK (modalidad IN ('jornal','mensual')),
  fecha_ingreso   date,
  fecha_egreso    date,
  obra_social     text,
  operario_nombre text,       -- match con ordenes_produccion.operario / timers (Fase 2)
  observaciones   text,
  activo          boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('empleados');
CREATE UNIQUE INDEX IF NOT EXISTS uq_empleados_legajo
  ON public.empleados (empresa_id, legajo) WHERE legajo IS NOT NULL AND legajo <> '';
CREATE INDEX IF NOT EXISTS idx_empleados_empresa ON public.empleados (empresa_id, activo);

COMMENT ON TABLE public.empleados IS
  'Legajos de nómina. centro mapea a las cuentas de gasto (fabricacion 421001/421002, administracion 422003/422004).';

-- ─── 2. Liquidaciones (cabecera) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.liquidaciones (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  periodo         date        NOT NULL,  -- primer día del mes liquidado
  tipo            text        NOT NULL DEFAULT 'mensual'
                              CHECK (tipo IN ('mensual','quincena1','quincena2','sac','vacaciones','final','otro')),
  estado          text        NOT NULL DEFAULT 'borrador'
                              CHECK (estado IN ('borrador','confirmada')),
  fecha_pago      date,
  -- Totales ARS (server-side = Σ items; el frontend no los manda)
  bruto           numeric(14,2) NOT NULL DEFAULT 0,
  no_remunerativo numeric(14,2) NOT NULL DEFAULT 0,
  aportes         numeric(14,2) NOT NULL DEFAULT 0,  -- retenciones al empleado (17% + sindicato)
  neto            numeric(14,2) NOT NULL DEFAULT 0,
  contribuciones  numeric(14,2) NOT NULL DEFAULT 0,  -- patronales (F.931)
  art             numeric(14,2) NOT NULL DEFAULT 0,
  tipo_cambio     numeric(14,4),                     -- TC al confirmar (reportes USD)
  asiento_id      uuid        REFERENCES public.asientos(id) ON DELETE SET NULL,
  observaciones   text,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('liquidaciones');
CREATE INDEX IF NOT EXISTS idx_liquidaciones_empresa
  ON public.liquidaciones (empresa_id, periodo DESC);

-- ─── 3. Items por empleado ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.liquidacion_items (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid        NOT NULL,
  liquidacion_id  uuid        NOT NULL REFERENCES public.liquidaciones(id) ON DELETE CASCADE,
  empleado_id     uuid        NOT NULL REFERENCES public.empleados(id) ON DELETE RESTRICT,
  bruto           numeric(14,2) NOT NULL DEFAULT 0,
  no_remunerativo numeric(14,2) NOT NULL DEFAULT 0,
  aportes         numeric(14,2) NOT NULL DEFAULT 0,
  neto            numeric(14,2) NOT NULL DEFAULT 0,
  contribuciones  numeric(14,2) NOT NULL DEFAULT 0,
  art             numeric(14,2) NOT NULL DEFAULT 0,
  detalle         jsonb,      -- conceptos opcionales (horas extra, presentismo...)
  observaciones   text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('liquidacion_items');
CREATE INDEX IF NOT EXISTS idx_liq_items_liq ON public.liquidacion_items (liquidacion_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_liq_items_empleado
  ON public.liquidacion_items (liquidacion_id, empleado_id);

-- ─── 4. Config: cuentas de imputación (defaults del plan real) ───────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_sueldos_fab     uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_cargas_fab      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_sueldos_adm     uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_cargas_adm      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_sueldos_a_pagar uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_cargas_a_pagar  uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

UPDATE public.config_contable c SET cta_sueldos_fab = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='421001')
  WHERE cta_sueldos_fab IS NULL;
UPDATE public.config_contable c SET cta_cargas_fab = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='421002')
  WHERE cta_cargas_fab IS NULL;
UPDATE public.config_contable c SET cta_sueldos_adm = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='422003')
  WHERE cta_sueldos_adm IS NULL;
UPDATE public.config_contable c SET cta_cargas_adm = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='422004')
  WHERE cta_cargas_adm IS NULL;
UPDATE public.config_contable c SET cta_sueldos_a_pagar = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='214006')
  WHERE cta_sueldos_a_pagar IS NULL;
UPDATE public.config_contable c SET cta_cargas_a_pagar = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='214007')
  WHERE cta_cargas_a_pagar IS NULL;

-- ─── 5. RPC guardar_liquidacion ──────────────────────────────────────
-- p_liq: {periodo, tipo, fecha_pago, observaciones}
-- p_items: [{empleado_id, bruto, no_remunerativo, aportes, neto,
--            contribuciones, art, detalle, observaciones}]
CREATE OR REPLACE FUNCTION public.guardar_liquidacion(
  p_liq jsonb, p_items jsonb, p_liq_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; it jsonb; v_estado text;
  v_bruto numeric; v_norem numeric; v_aportes numeric; v_neto numeric;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF NULLIF(p_liq->>'periodo','') IS NULL THEN RAISE EXCEPTION 'Indicá el período'; END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_items,'[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'Agregá al menos un empleado a la liquidación';
  END IF;

  -- Validación por ítem: empleado de la empresa + aritmética del neto
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF NOT EXISTS (SELECT 1 FROM empleados e
                   WHERE e.id = (it->>'empleado_id')::uuid AND e.empresa_id = emp) THEN
      RAISE EXCEPTION 'Empleado inexistente';
    END IF;
    v_bruto   := COALESCE((it->>'bruto')::numeric, 0);
    v_norem   := COALESCE((it->>'no_remunerativo')::numeric, 0);
    v_aportes := COALESCE((it->>'aportes')::numeric, 0);
    v_neto    := COALESCE((it->>'neto')::numeric, 0);
    IF v_bruto < 0 OR v_norem < 0 OR v_aportes < 0 OR v_neto < 0
       OR COALESCE((it->>'contribuciones')::numeric,0) < 0
       OR COALESCE((it->>'art')::numeric,0) < 0 THEN
      RAISE EXCEPTION 'Los importes no pueden ser negativos';
    END IF;
    IF abs(v_neto - (v_bruto + v_norem - v_aportes)) > 0.01 THEN
      RAISE EXCEPTION 'Neto inconsistente en un empleado: neto (%) ≠ bruto + no remunerativo − aportes (%)',
        v_neto, v_bruto + v_norem - v_aportes;
    END IF;
  END LOOP;

  IF p_liq_id IS NOT NULL THEN
    SELECT estado INTO v_estado FROM liquidaciones WHERE id = p_liq_id AND empresa_id = emp;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Liquidación no encontrada'; END IF;
    IF v_estado <> 'borrador' THEN
      RAISE EXCEPTION 'La liquidación está confirmada — anulala antes de editarla';
    END IF;
    DELETE FROM liquidacion_items WHERE liquidacion_id = p_liq_id;
    UPDATE liquidaciones SET
      periodo = (p_liq->>'periodo')::date,
      tipo = COALESCE(NULLIF(p_liq->>'tipo',''), 'mensual'),
      fecha_pago = NULLIF(p_liq->>'fecha_pago','')::date,
      observaciones = p_liq->>'observaciones'
    WHERE id = p_liq_id RETURNING id INTO v_id;
  ELSE
    INSERT INTO liquidaciones (empresa_id, periodo, tipo, fecha_pago, observaciones, created_by)
    VALUES (emp, (p_liq->>'periodo')::date,
            COALESCE(NULLIF(p_liq->>'tipo',''), 'mensual'),
            NULLIF(p_liq->>'fecha_pago','')::date,
            p_liq->>'observaciones', auth.uid())
    RETURNING id INTO v_id;
  END IF;

  INSERT INTO liquidacion_items (empresa_id, liquidacion_id, empleado_id, bruto,
    no_remunerativo, aportes, neto, contribuciones, art, detalle, observaciones)
  SELECT emp, v_id, (it->>'empleado_id')::uuid,
         COALESCE((it->>'bruto')::numeric,0), COALESCE((it->>'no_remunerativo')::numeric,0),
         COALESCE((it->>'aportes')::numeric,0), COALESCE((it->>'neto')::numeric,0),
         COALESCE((it->>'contribuciones')::numeric,0), COALESCE((it->>'art')::numeric,0),
         it->'detalle', it->>'observaciones'
  FROM jsonb_array_elements(p_items) it;

  -- Totales server-side
  UPDATE liquidaciones l SET
    bruto = t.b, no_remunerativo = t.nr, aportes = t.a, neto = t.n,
    contribuciones = t.c, art = t.art
  FROM (SELECT COALESCE(sum(bruto),0) b, COALESCE(sum(no_remunerativo),0) nr,
               COALESCE(sum(aportes),0) a, COALESCE(sum(neto),0) n,
               COALESCE(sum(contribuciones),0) c, COALESCE(sum(art),0) art
        FROM liquidacion_items WHERE liquidacion_id = v_id) t
  WHERE l.id = v_id;

  RETURN jsonb_build_object('id', v_id);
END $$;

-- ─── 6. RPC confirmar_liquidacion → asiento de devengamiento ─────────
-- Debe:  sueldos fab/adm (bruto + no_rem por centro)
--        cargas fab/adm (contribuciones + ART por centro)
-- Haber: 214006 SUELDOS A PAGAR (neto total)
--        214007 Cargas Sociales a Pagar (aportes + contribuciones + ART)
CREATE OR REPLACE FUNCTION public.confirmar_liquidacion(
  p_liq_id uuid, p_tipo_cambio numeric DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  l record; cfg record; v_asiento jsonb;
  s_fab numeric; s_adm numeric; c_fab numeric; c_adm numeric;
  v_neto numeric; v_cargas numeric; v_lineas jsonb := '[]'::jsonb; v_orden int := 0;
  v_desc text;
  TIPO_LABEL constant jsonb := '{"mensual":"mensual","quincena1":"1ª quincena","quincena2":"2ª quincena","sac":"SAC","vacaciones":"vacaciones","final":"liquidación final","otro":"otros"}'::jsonb;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO l FROM liquidaciones WHERE id = p_liq_id AND empresa_id = emp FOR UPDATE;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Liquidación no encontrada'; END IF;
  IF l.estado <> 'borrador' THEN RAISE EXCEPTION 'La liquidación ya está confirmada'; END IF;

  SELECT * INTO cfg FROM config_contable WHERE empresa_id = emp;
  IF cfg.cta_sueldos_fab IS NULL OR cfg.cta_cargas_fab IS NULL
     OR cfg.cta_sueldos_adm IS NULL OR cfg.cta_cargas_adm IS NULL
     OR cfg.cta_sueldos_a_pagar IS NULL OR cfg.cta_cargas_a_pagar IS NULL THEN
    RAISE EXCEPTION 'Faltan cuentas de sueldos en la imputación contable (Configuración)';
  END IF;

  -- Gasto por centro de costo (join items × empleados)
  SELECT COALESCE(sum(CASE WHEN e.centro='fabricacion'     THEN i.bruto + i.no_remunerativo END),0),
         COALESCE(sum(CASE WHEN e.centro='administracion'  THEN i.bruto + i.no_remunerativo END),0),
         COALESCE(sum(CASE WHEN e.centro='fabricacion'     THEN i.contribuciones + i.art END),0),
         COALESCE(sum(CASE WHEN e.centro='administracion'  THEN i.contribuciones + i.art END),0)
    INTO s_fab, s_adm, c_fab, c_adm
  FROM liquidacion_items i JOIN empleados e ON e.id = i.empleado_id
  WHERE i.liquidacion_id = p_liq_id;

  v_neto   := l.neto;
  v_cargas := l.aportes + l.contribuciones + l.art;
  IF round(s_fab + s_adm + c_fab + c_adm, 2) <> round(v_neto + v_cargas, 2) THEN
    RAISE EXCEPTION 'El asiento no balancea — revisá los importes de la liquidación';
  END IF;
  IF v_neto + v_cargas < 0.01 THEN RAISE EXCEPTION 'La liquidación está en cero'; END IF;

  v_desc := 'Sueldos ' || COALESCE(TIPO_LABEL->>l.tipo, l.tipo) || ' ' || to_char(l.periodo, 'MM/YYYY');
  IF s_fab >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_sueldos_fab, 'debe', s_fab, 'haber', 0,
      'descripcion', 'Sueldos fabricación', 'orden', v_orden); v_orden := v_orden + 1; END IF;
  IF c_fab >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_cargas_fab, 'debe', c_fab, 'haber', 0,
      'descripcion', 'Cargas sociales fabricación', 'orden', v_orden); v_orden := v_orden + 1; END IF;
  IF s_adm >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_sueldos_adm, 'debe', s_adm, 'haber', 0,
      'descripcion', 'Sueldos administración', 'orden', v_orden); v_orden := v_orden + 1; END IF;
  IF c_adm >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_cargas_adm, 'debe', c_adm, 'haber', 0,
      'descripcion', 'Cargas sociales administración', 'orden', v_orden); v_orden := v_orden + 1; END IF;
  IF v_neto >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_sueldos_a_pagar, 'debe', 0, 'haber', v_neto,
      'descripcion', 'Netos a pagar', 'orden', v_orden); v_orden := v_orden + 1; END IF;
  IF v_cargas >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_cargas_a_pagar, 'debe', 0, 'haber', v_cargas,
      'descripcion', 'Aportes y contribuciones (F.931) + ART', 'orden', v_orden); END IF;

  -- El devengamiento se imputa al PERÍODO (fin de mes), no a la fecha de
  -- pago — mismo principio que fecha_contable en facturas (migración 062)
  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha', (l.periodo + interval '1 month' - interval '1 day')::date,
      'estado', 'confirmado', 'tipo', 'auto-sueldos',
      'origen_tipo', 'liquidacion', 'origen_id', p_liq_id,
      'descripcion', v_desc,
      'moneda', 'ARS', 'tipo_cambio', 1, 'tc_tipo', 'oficial'),
    v_lineas);

  UPDATE liquidaciones SET estado = 'confirmada',
    asiento_id = (v_asiento->>'id')::uuid,
    tipo_cambio = COALESCE(p_tipo_cambio, tipo_cambio)
  WHERE id = p_liq_id;

  RETURN jsonb_build_object('id', p_liq_id, 'asiento_id', v_asiento->>'id');
END $$;

-- ─── 7. RPC anular_liquidacion ───────────────────────────────────────
-- Confirmada → asiento a 'anulado' (nunca se borra, patrón anular_venta)
-- y la liquidación vuelve a borrador. Borrador → se elimina.
CREATE OR REPLACE FUNCTION public.anular_liquidacion(p_liq_id uuid, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  l record;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO l FROM liquidaciones WHERE id = p_liq_id AND empresa_id = emp FOR UPDATE;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Liquidación no encontrada'; END IF;

  IF l.estado = 'confirmada' THEN
    IF COALESCE(trim(p_motivo),'') = '' THEN
      RAISE EXCEPTION 'Indicá el motivo de la anulación';
    END IF;
    -- Motivo al audit_log vía UPDATE previo (patrón anular_factura_recibida)
    UPDATE liquidaciones SET observaciones =
      COALESCE(NULLIF(observaciones,'') || ' · ', '') || 'ANULADA: ' || trim(p_motivo)
    WHERE id = p_liq_id;
    UPDATE asientos SET estado = 'anulado'
    WHERE id = l.asiento_id AND empresa_id = emp;
    UPDATE liquidaciones SET estado = 'borrador', asiento_id = NULL WHERE id = p_liq_id;
    RETURN jsonb_build_object('ok', true, 'accion', 'reabierta');
  ELSE
    DELETE FROM liquidacion_items WHERE liquidacion_id = p_liq_id;
    DELETE FROM liquidaciones WHERE id = p_liq_id;
    RETURN jsonb_build_object('ok', true, 'accion', 'eliminada');
  END IF;
END $$;

-- ─── 8. Cerrar EXECUTE a anon (default privileges de Supabase) ───────
REVOKE ALL ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.confirmar_liquidacion(uuid, numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.anular_liquidacion(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_liquidacion(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_liquidacion(uuid, text) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT
--   (SELECT count(*) FROM information_schema.tables
--     WHERE table_name IN ('empleados','liquidaciones','liquidacion_items')) AS tablas,
--   (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--     WHERE n.nspname='public' AND p.proname IN
--     ('guardar_liquidacion','confirmar_liquidacion','anular_liquidacion')) AS rpcs,
--   (SELECT count(*) FROM pg_policies WHERE tablename='liquidaciones') AS policies_liq,
--   (SELECT cta_sueldos_fab IS NOT NULL AND cta_sueldos_a_pagar IS NOT NULL
--     FROM config_contable LIMIT 1) AS ctas_ok;
-- Esperado: tablas=3, rpcs=3, policies_liq=5, ctas_ok=true
