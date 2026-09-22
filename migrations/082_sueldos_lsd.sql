-- ═══════════════════════════════════════════════════════════════════
-- 082_sueldos_lsd.sql
-- Sueldos: cierre de la revisión 2026-09-22 + Libro de Sueldos Digital
-- (LSD) de ARCA. Ver docs/superpowers/specs/2026-09-22-sueldos-lsd-design.md
--
-- A. FIXES de la revisión
--   1. Una liquidación con pagos registrados (asientos vivos
--      'liquidacion-pago-netos' / 'liquidacion-pago-cargas') NO se puede
--      editar ni eliminar: primero se anulan esos asientos.
--   2. UNIQUE parcial (empresa, período, tipo) para mensual / quincenas
--      / SAC → no se puede cargar dos veces el mismo mes. 'vacaciones',
--      'final' y 'otro' quedan libres (pueden repetirse en un mes).
--   3. El consumo de la provisión SAC toma sólo asientos con fecha ≤ fin
--      del período del SAC (antes sumaba todo el saldo de 214008, incluso
--      provisiones de meses posteriores confirmadas antes).
--   4. Dos empleados repetidos en p_items → error claro (antes chocaba
--      con uq_liq_items_empleado con mensaje crudo).
--
-- B. LSD / F.931 (formato "LSD-ARMADO-TXT-Liquidaciones.xlsx" de ARCA,
--    registros 01..04 de ancho fijo)
--   · empleados: atributos de la relación laboral (registro 04) + CBU,
--     forma de pago y dependencia (registro 02). Defaults típicos de un
--     operario UOM en relación de dependencia a tiempo completo; la
--     contadora ajusta por legajo.
--   · config_contable: cuit_empleador, lsd_tipo_empresa (Dec. 814/01),
--     lsd_importe_detraer (Ley 27.430) y lsd_tope_aportes (base máxima
--     para bases 1/4/5).
--   · conceptos_sueldo: catálogo de conceptos DEL EMPLEADOR (los mismos
--     códigos que la contadora asocia en ARCA → LSD → "Conceptos"). tipo
--     define el efecto: remunerativo → bruto, no_remunerativo → no rem,
--     descuento → aportes, informativo → nada. Seed inicial editable.
--   · liquidacion_conceptos: detalle por empleado (registro 03). Cuando
--     un ítem trae conceptos, guardar_liquidacion RECALCULA bruto /
--     no_rem / aportes / neto desde ellos (fuente única de verdad);
--     contribuciones y ART siguen viniendo del ítem (no van al LSD, ARCA
--     los calcula desde las bases).
--   · liquidacion_items.f931 jsonb: bases imponibles, días/horas y
--     overrides del registro 04 por empleado (lo que no está, se deriva
--     del bruto al exportar).
--   · liquidaciones.lsd_nro / lsd_exportado_at: número de liquidación
--     informado a ARCA (debe ser mayor a los ya enviados del período).
--
-- RPCs RE-EMITIDAS (ediciones futuras parten de acá):
--   guardar_liquidacion (base 065), confirmar_liquidacion (base 069),
--   anular_liquidacion (base 066). Mismas firmas.
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Batería RLS (molde 052/053/065) + policy modulo_sueldos (071) ──
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
  EXECUTE format('DROP POLICY IF EXISTS modulo_sueldos ON public.%I', t);
  EXECUTE format('CREATE POLICY modulo_sueldos ON public.%I AS RESTRICTIVE FOR ALL TO authenticated
    USING ((SELECT public.tiene_modulo(''sueldos'')))
    WITH CHECK ((SELECT public.tiene_modulo(''sueldos'')))', t);
  EXECUTE format('DROP TRIGGER IF EXISTS contador_guard ON public.%I', t);
  EXECUTE format('CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I
    FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard()', t);
  EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I', t);
  EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
END $$;

-- ─── 1. Empleados: datos de la relación laboral (registros 02 y 04) ──
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS cbu             text,
  ADD COLUMN IF NOT EXISTS forma_pago      smallint NOT NULL DEFAULT 3
                                           CHECK (forma_pago BETWEEN 1 AND 4),  -- 1 efectivo, 2 cheque, 3 acreditación, 4 externo
  ADD COLUMN IF NOT EXISTS dependencia     text,
  ADD COLUMN IF NOT EXISTS conyuge         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hijos           smallint NOT NULL DEFAULT 0 CHECK (hijos BETWEEN 0 AND 99),
  ADD COLUMN IF NOT EXISTS marca_cct       boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS marca_scvo      boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS marca_reduccion boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cod_situacion   text NOT NULL DEFAULT '1',    -- SICOSS: 1 activo
  ADD COLUMN IF NOT EXISTS cod_condicion   text NOT NULL DEFAULT '1',    -- SICOSS: 1 servicios comunes mayor de 18
  ADD COLUMN IF NOT EXISTS cod_actividad   text NOT NULL DEFAULT '',     -- SICOSS: tabla de actividades (3 dígitos)
  ADD COLUMN IF NOT EXISTS cod_modalidad   text NOT NULL DEFAULT '008',  -- SICOSS: 008 tiempo completo indeterminado
  ADD COLUMN IF NOT EXISTS cod_siniestrado text NOT NULL DEFAULT '00',
  ADD COLUMN IF NOT EXISTS cod_localidad   text NOT NULL DEFAULT '00',
  ADD COLUMN IF NOT EXISTS sit_revista     text NOT NULL DEFAULT '1',    -- SICOSS: 1 activo (día inicio 01)
  ADD COLUMN IF NOT EXISTS cod_obra_social text NOT NULL DEFAULT '',     -- código RNOS 6 dígitos
  ADD COLUMN IF NOT EXISTS adherentes      smallint NOT NULL DEFAULT 0 CHECK (adherentes BETWEEN 0 AND 99);

COMMENT ON COLUMN public.empleados.cod_obra_social IS 'Código RNOS (6 dígitos) — registro 04 del LSD';
COMMENT ON COLUMN public.empleados.forma_pago IS '1 efectivo · 2 cheque · 3 acreditación (exige CBU) · 4 pago externo — registro 02 del LSD';

-- ─── 2. Config: datos del empleador para el LSD ──────────────────────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cuit_empleador      text,
  ADD COLUMN IF NOT EXISTS lsd_tipo_empresa    smallint NOT NULL DEFAULT 1,   -- 1 = Dec. 814/01 art. 2 inc. b (PyME)
  ADD COLUMN IF NOT EXISTS lsd_importe_detraer numeric(14,2) NOT NULL DEFAULT 0,  -- Ley 27.430 (por empleado y mes)
  ADD COLUMN IF NOT EXISTS lsd_tope_aportes    numeric(14,2) NOT NULL DEFAULT 0;  -- base imponible máxima aportes (0 = sin tope)

-- ─── 3. Liquidaciones: nro LSD + unicidad por período ────────────────
ALTER TABLE public.liquidaciones
  ADD COLUMN IF NOT EXISTS lsd_nro          integer,
  ADD COLUMN IF NOT EXISTS lsd_exportado_at timestamptz;

DO $$
DECLARE dup text;
BEGIN
  SELECT string_agg(to_char(periodo,'MM/YYYY') || ' ' || tipo || ' ×' || n, ', ')
    INTO dup
  FROM (SELECT periodo, tipo, count(*) n FROM public.liquidaciones
        WHERE tipo IN ('mensual','quincena1','quincena2','sac')
        GROUP BY empresa_id, periodo, tipo HAVING count(*) > 1) d;
  IF dup IS NOT NULL THEN
    RAISE EXCEPTION 'Hay liquidaciones duplicadas (mismo período y tipo): %. Eliminá/anulá las repetidas antes de correr la 082.', dup;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_liquidaciones_periodo_tipo
  ON public.liquidaciones (empresa_id, periodo, tipo)
  WHERE tipo IN ('mensual','quincena1','quincena2','sac');
COMMENT ON INDEX uq_liquidaciones_periodo_tipo IS
  'Una sola liquidación mensual / por quincena / SAC por período (082). vacaciones/final/otro pueden repetirse.';

-- ─── 4. Catálogo de conceptos del empleador ──────────────────────────
CREATE TABLE IF NOT EXISTS public.conceptos_sueldo (
  id          uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid    NOT NULL,
  codigo      text    NOT NULL CHECK (codigo ~ '^[A-Za-z0-9]{1,10}$'),
  nombre      text    NOT NULL,
  tipo        text    NOT NULL DEFAULT 'remunerativo'
                      CHECK (tipo IN ('remunerativo','no_remunerativo','descuento','informativo')),
  unidades    text    CHECK (unidades IS NULL OR unidades IN ('$','%','A','Q','M','D','H')),
  orden       integer NOT NULL DEFAULT 0,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('conceptos_sueldo');
CREATE UNIQUE INDEX IF NOT EXISTS uq_conceptos_sueldo_codigo
  ON public.conceptos_sueldo (empresa_id, codigo);
COMMENT ON TABLE public.conceptos_sueldo IS
  'Conceptos de liquidación del empleador (códigos propios que se asocian a los conceptos ARCA en el LSD). tipo → efecto en bruto/no_rem/aportes.';

-- Seed (solo si la empresa no tiene ninguno): códigos propios sugeridos
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden)
SELECT c.empresa_id, s.codigo, s.nombre, s.tipo, s.unidades, s.orden
FROM public.config_contable c
CROSS JOIN (VALUES
  ('100', 'Sueldo básico / jornales',            'remunerativo',    NULL, 10),
  ('110', 'Antigüedad',                          'remunerativo',    '%',  20),
  ('120', 'Presentismo',                         'remunerativo',    NULL, 30),
  ('130', 'Horas extras 50%',                    'remunerativo',    'H',  40),
  ('131', 'Horas extras 100%',                   'remunerativo',    'H',  50),
  ('140', 'SAC',                                 'remunerativo',    NULL, 60),
  ('150', 'Vacaciones',                          'remunerativo',    'D',  70),
  ('160', 'Adicional convenio / a cuenta futuros aumentos', 'remunerativo', NULL, 80),
  ('190', 'Asignación no remunerativa',          'no_remunerativo', NULL, 90),
  ('300', 'Jubilación 11%',                      'descuento',       '%',  300),
  ('310', 'Ley 19.032 (INSSJP) 3%',              'descuento',       '%',  310),
  ('320', 'Obra social 3%',                      'descuento',       '%',  320),
  ('330', 'Cuota sindical UOM',                  'descuento',       '%',  330),
  ('340', 'Seguro de sepelio UOM',               'descuento',       '%',  340),
  ('350', 'Adelanto de sueldo',                  'descuento',       NULL, 350),
  ('900', 'Asignaciones familiares (informativo)','informativo',    NULL, 900)
) AS s(codigo, nombre, tipo, unidades, orden)
WHERE NOT EXISTS (SELECT 1 FROM public.conceptos_sueldo x WHERE x.empresa_id = c.empresa_id);

-- ─── 5. Detalle de conceptos por empleado (registro 03) ──────────────
CREATE TABLE IF NOT EXISTS public.liquidacion_conceptos (
  id              uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid    NOT NULL,
  liquidacion_id  uuid    NOT NULL REFERENCES public.liquidaciones(id) ON DELETE CASCADE,
  item_id         uuid    NOT NULL REFERENCES public.liquidacion_items(id) ON DELETE CASCADE,
  empleado_id     uuid    NOT NULL REFERENCES public.empleados(id) ON DELETE RESTRICT,
  codigo          text    NOT NULL,
  cantidad        numeric(7,2)  NOT NULL DEFAULT 0 CHECK (cantidad >= 0 AND cantidad < 1000),
  unidades        text    CHECK (unidades IS NULL OR unidades IN ('$','%','A','Q','M','D','H')),
  importe         numeric(15,2) NOT NULL CHECK (importe >= 0),
  dc              char(1) NOT NULL CHECK (dc IN ('D','C')),
  periodo_ajuste  text    CHECK (periodo_ajuste IS NULL OR periodo_ajuste ~ '^\d{6}$'),
  orden           integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);
SELECT pg_temp.aplicar_bateria('liquidacion_conceptos');
CREATE INDEX IF NOT EXISTS idx_liq_conceptos_item ON public.liquidacion_conceptos (item_id);
CREATE INDEX IF NOT EXISTS idx_liq_conceptos_liq  ON public.liquidacion_conceptos (liquidacion_id);

-- ─── 6. F.931 por empleado (registro 04) ─────────────────────────────
ALTER TABLE public.liquidacion_items
  ADD COLUMN IF NOT EXISTS f931 jsonb;
COMMENT ON COLUMN public.liquidacion_items.f931 IS
  'Overrides del registro 04 del LSD: {dias, horas, rem_bruta, base1..base10, detraer, ...}. Lo ausente se deriva del bruto al exportar.';

-- ─── 7. guardar_liquidacion (RE-EMISIÓN, base 065) ───────────────────
-- p_liq: {periodo, tipo, fecha_pago, observaciones}
-- p_items: [{empleado_id, bruto, no_remunerativo, aportes, neto,
--            contribuciones, art, detalle, observaciones,
--            conceptos: [{codigo, cantidad, unidades, importe, dc, periodo_ajuste}],
--            f931: {...}}]
-- Con conceptos: bruto/no_rem/aportes/neto se RECALCULAN desde ellos.
CREATE OR REPLACE FUNCTION public.guardar_liquidacion(
  p_liq jsonb, p_items jsonb, p_liq_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; it jsonb; cc jsonb; v_estado text; v_item_id uuid; v_orden int;
  v_bruto numeric; v_norem numeric; v_aportes numeric; v_neto numeric;
  v_tipo_c text; v_dc text; v_imp numeric;
  v_emp_ids uuid[] := '{}';
  v_tipo text := COALESCE(NULLIF(p_liq->>'tipo',''), 'mensual');
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF NULLIF(p_liq->>'periodo','') IS NULL THEN RAISE EXCEPTION 'Indicá el período'; END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_items,'[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'Agregá al menos un empleado a la liquidación';
  END IF;

  -- Validación por ítem: empleado de la empresa, sin repetidos, aritmética del neto
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF NOT EXISTS (SELECT 1 FROM empleados e
                   WHERE e.id = (it->>'empleado_id')::uuid AND e.empresa_id = emp) THEN
      RAISE EXCEPTION 'Empleado inexistente';
    END IF;
    IF (it->>'empleado_id')::uuid = ANY (v_emp_ids) THEN
      RAISE EXCEPTION 'Hay un empleado repetido en la liquidación';
    END IF;
    v_emp_ids := v_emp_ids || (it->>'empleado_id')::uuid;
    v_bruto   := COALESCE((it->>'bruto')::numeric, 0);
    v_norem   := COALESCE((it->>'no_remunerativo')::numeric, 0);
    v_aportes := COALESCE((it->>'aportes')::numeric, 0);
    v_neto    := COALESCE((it->>'neto')::numeric, 0);
    IF v_bruto < 0 OR v_norem < 0 OR v_aportes < 0 OR v_neto < 0
       OR COALESCE((it->>'contribuciones')::numeric,0) < 0
       OR COALESCE((it->>'art')::numeric,0) < 0 THEN
      RAISE EXCEPTION 'Los importes no pueden ser negativos';
    END IF;
    IF jsonb_typeof(it->'conceptos') = 'array' AND jsonb_array_length(it->'conceptos') > 0 THEN
      -- Con conceptos la aritmética se valida sobre lo recalculado (abajo)
      FOR cc IN SELECT * FROM jsonb_array_elements(it->'conceptos') LOOP
        IF NOT EXISTS (SELECT 1 FROM conceptos_sueldo c
                       WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo') THEN
          RAISE EXCEPTION 'Concepto % inexistente en el catálogo (Sueldos → Conceptos ARCA)', cc->>'codigo';
        END IF;
        IF COALESCE((cc->>'importe')::numeric, 0) < 0 THEN
          RAISE EXCEPTION 'El concepto % tiene importe negativo — usá un concepto de tipo descuento', cc->>'codigo';
        END IF;
      END LOOP;
    ELSIF abs(v_neto - (v_bruto + v_norem - v_aportes)) > 0.01 THEN
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
    -- FIX 082: con pagos vivos no se edita (el pago dejaría de coincidir)
    IF EXISTS (SELECT 1 FROM asientos a WHERE a.empresa_id = emp AND a.origen_id = p_liq_id
               AND a.origen_tipo IN ('liquidacion-pago-netos','liquidacion-pago-cargas')
               AND a.estado <> 'anulado') THEN
      RAISE EXCEPTION 'La liquidación tiene pagos registrados (netos / F.931) — anulá esos asientos antes de editarla';
    END IF;
    DELETE FROM liquidacion_items WHERE liquidacion_id = p_liq_id;  -- cascade a liquidacion_conceptos
    BEGIN
      UPDATE liquidaciones SET
        periodo = (p_liq->>'periodo')::date,
        tipo = v_tipo,
        fecha_pago = NULLIF(p_liq->>'fecha_pago','')::date,
        observaciones = p_liq->>'observaciones'
      WHERE id = p_liq_id RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Ya existe una liquidación % del período % — editá esa en vez de cargar otra',
        v_tipo, to_char((p_liq->>'periodo')::date, 'MM/YYYY');
    END;
  ELSE
    BEGIN
      INSERT INTO liquidaciones (empresa_id, periodo, tipo, fecha_pago, observaciones, created_by)
      VALUES (emp, (p_liq->>'periodo')::date, v_tipo,
              NULLIF(p_liq->>'fecha_pago','')::date,
              p_liq->>'observaciones', auth.uid())
      RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Ya existe una liquidación % del período % — editá esa en vez de cargar otra',
        v_tipo, to_char((p_liq->>'periodo')::date, 'MM/YYYY');
    END;
  END IF;

  -- Ítems (uno a uno para enganchar los conceptos al item_id)
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_bruto   := COALESCE((it->>'bruto')::numeric, 0);
    v_norem   := COALESCE((it->>'no_remunerativo')::numeric, 0);
    v_aportes := COALESCE((it->>'aportes')::numeric, 0);
    v_neto    := COALESCE((it->>'neto')::numeric, 0);
    IF jsonb_typeof(it->'conceptos') = 'array' AND jsonb_array_length(it->'conceptos') > 0 THEN
      v_bruto := 0; v_norem := 0; v_aportes := 0;
      FOR cc IN SELECT * FROM jsonb_array_elements(it->'conceptos') LOOP
        SELECT c.tipo INTO v_tipo_c FROM conceptos_sueldo c
         WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo';
        v_imp := round(COALESCE((cc->>'importe')::numeric, 0), 2);
        IF    v_tipo_c = 'remunerativo'    THEN v_bruto   := v_bruto + v_imp;
        ELSIF v_tipo_c = 'no_remunerativo' THEN v_norem   := v_norem + v_imp;
        ELSIF v_tipo_c = 'descuento'       THEN v_aportes := v_aportes + v_imp;
        END IF;
      END LOOP;
      v_neto := v_bruto + v_norem - v_aportes;
      IF v_neto < 0 THEN RAISE EXCEPTION 'Los descuentos superan los haberes en un empleado'; END IF;
    END IF;

    INSERT INTO liquidacion_items (empresa_id, liquidacion_id, empleado_id, bruto,
      no_remunerativo, aportes, neto, contribuciones, art, detalle, observaciones, f931)
    VALUES (emp, v_id, (it->>'empleado_id')::uuid, v_bruto, v_norem, v_aportes, v_neto,
            COALESCE((it->>'contribuciones')::numeric,0), COALESCE((it->>'art')::numeric,0),
            it->'detalle', it->>'observaciones',
            CASE WHEN jsonb_typeof(it->'f931') = 'object' THEN it->'f931' ELSE NULL END)
    RETURNING id INTO v_item_id;

    IF jsonb_typeof(it->'conceptos') = 'array' THEN
      v_orden := 0;
      FOR cc IN SELECT * FROM jsonb_array_elements(it->'conceptos') LOOP
        SELECT c.tipo INTO v_tipo_c FROM conceptos_sueldo c
         WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo';
        v_dc := CASE WHEN v_tipo_c = 'descuento' THEN 'D' ELSE 'C' END;
        INSERT INTO liquidacion_conceptos (empresa_id, liquidacion_id, item_id, empleado_id,
          codigo, cantidad, unidades, importe, dc, periodo_ajuste, orden)
        VALUES (emp, v_id, v_item_id, (it->>'empleado_id')::uuid,
          cc->>'codigo', COALESCE((cc->>'cantidad')::numeric, 0),
          NULLIF(cc->>'unidades',''), round(COALESCE((cc->>'importe')::numeric, 0), 2),
          v_dc, NULLIF(cc->>'periodo_ajuste',''), v_orden);
        v_orden := v_orden + 1;
      END LOOP;
    END IF;
  END LOOP;

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

-- ─── 8. confirmar_liquidacion (RE-EMISIÓN, base 069: corte de fecha SAC) ─
CREATE OR REPLACE FUNCTION public.confirmar_liquidacion(
  p_liq_id uuid, p_tipo_cambio numeric DEFAULT NULL, p_provisionar_sac boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  l record; cfg record; v_asiento jsonb; v_prov_asiento jsonb := NULL;
  s_fab numeric; s_adm numeric; c_fab numeric; c_adm numeric;
  b_fab numeric; b_adm numeric;           -- bruto puro por centro (base SAC)
  prov_fab numeric; prov_adm numeric;
  saldo_prov numeric; aplicado numeric := 0; gasto_total numeric;
  v_neto numeric; v_cargas numeric; v_lineas jsonb := '[]'::jsonb; v_orden int := 0;
  v_desc text; v_fin_mes date;
  TIPO_LABEL constant jsonb := '{"mensual":"mensual","quincena1":"1ª quincena","quincena2":"2ª quincena","sac":"SAC","vacaciones":"vacaciones","final":"liquidación final","otro":"otros"}'::jsonb;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO l FROM liquidaciones WHERE id = p_liq_id AND empresa_id = emp FOR UPDATE;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Liquidación no encontrada'; END IF;
  IF l.estado <> 'borrador' THEN RAISE EXCEPTION 'La liquidación ya está confirmada'; END IF;
  v_fin_mes := (l.periodo + interval '1 month' - interval '1 day')::date;

  SELECT * INTO cfg FROM config_contable WHERE empresa_id = emp;
  IF cfg.cta_sueldos_fab IS NULL OR cfg.cta_cargas_fab IS NULL
     OR cfg.cta_sueldos_adm IS NULL OR cfg.cta_cargas_adm IS NULL
     OR cfg.cta_sueldos_a_pagar IS NULL OR cfg.cta_cargas_a_pagar IS NULL THEN
    RAISE EXCEPTION 'Faltan cuentas de sueldos en la imputación contable (Configuración)';
  END IF;

  SELECT COALESCE(sum(CASE WHEN e.centro='fabricacion'     THEN i.bruto + i.no_remunerativo END),0),
         COALESCE(sum(CASE WHEN e.centro='administracion'  THEN i.bruto + i.no_remunerativo END),0),
         COALESCE(sum(CASE WHEN e.centro='fabricacion'     THEN i.contribuciones + i.art END),0),
         COALESCE(sum(CASE WHEN e.centro='administracion'  THEN i.contribuciones + i.art END),0),
         COALESCE(sum(CASE WHEN e.centro='fabricacion'     THEN i.bruto END),0),
         COALESCE(sum(CASE WHEN e.centro='administracion'  THEN i.bruto END),0)
    INTO s_fab, s_adm, c_fab, c_adm, b_fab, b_adm
  FROM liquidacion_items i JOIN empleados e ON e.id = i.empleado_id
  WHERE i.liquidacion_id = p_liq_id;

  v_neto   := l.neto;
  v_cargas := l.aportes + l.contribuciones + l.art;
  IF round(s_fab + s_adm + c_fab + c_adm, 2) <> round(v_neto + v_cargas, 2) THEN
    RAISE EXCEPTION 'El asiento no balancea — revisá los importes de la liquidación';
  END IF;
  IF v_neto + v_cargas < 0.01 THEN RAISE EXCEPTION 'La liquidación está en cero'; END IF;

  -- SAC: consumir la provisión acumulada HASTA el fin del período del SAC
  -- (FIX 082: antes tomaba todo el saldo, incluso provisiones posteriores)
  IF l.tipo = 'sac' AND cfg.cta_provision_sac IS NOT NULL THEN
    SELECT COALESCE(sum(al.haber - al.debe), 0) INTO saldo_prov
    FROM asiento_lineas al JOIN asientos a ON a.id = al.asiento_id
    WHERE a.empresa_id = emp AND a.estado = 'confirmado'
      AND al.cuenta_id = cfg.cta_provision_sac
      AND a.fecha <= v_fin_mes;
    gasto_total := s_fab + s_adm;
    aplicado := LEAST(GREATEST(saldo_prov, 0), gasto_total);
    IF aplicado >= 0.01 THEN
      s_fab := round(s_fab * (1 - aplicado / gasto_total), 2);
      s_adm := gasto_total - aplicado - s_fab;  -- complemento: balance exacto
    ELSE
      aplicado := 0;
    END IF;
  END IF;

  v_desc := 'Sueldos ' || COALESCE(TIPO_LABEL->>l.tipo, l.tipo) || ' ' || to_char(l.periodo, 'MM/YYYY')
            || CASE WHEN aplicado >= 0.01 THEN ' (usa provisión SAC)' ELSE '' END;
  IF aplicado >= 0.01 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', cfg.cta_provision_sac, 'debe', aplicado, 'haber', 0,
      'descripcion', 'Consumo provisión SAC', 'orden', v_orden); v_orden := v_orden + 1; END IF;
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

  -- Devengamiento al PERÍODO (fin de mes); tc_tipo NULL para ARS (fix 069)
  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha', v_fin_mes,
      'estado', 'confirmado', 'tipo', 'auto-sueldos',
      'origen_tipo', 'liquidacion', 'origen_id', p_liq_id,
      'descripcion', v_desc,
      'moneda', 'ARS', 'tipo_cambio', 1, 'tc_tipo', NULL),
    v_lineas);

  -- Provisión SAC del mes: 1/12 del BRUTO por centro, asiento aparte
  IF p_provisionar_sac AND l.tipo IN ('mensual','quincena1','quincena2')
     AND cfg.cta_provision_sac IS NOT NULL THEN
    prov_fab := round(b_fab / 12, 2);
    prov_adm := round(b_adm / 12, 2);
    IF prov_fab + prov_adm >= 0.01 THEN
      v_prov_asiento := public.crear_asiento(
        jsonb_build_object(
          'fecha', v_fin_mes,
          'estado', 'confirmado', 'tipo', 'auto-prov-sac',
          'origen_tipo', 'liquidacion-prov-sac', 'origen_id', p_liq_id,
          'descripcion', 'Provisión SAC 1/12 — ' || to_char(l.periodo, 'MM/YYYY'),
          'moneda', 'ARS', 'tipo_cambio', 1, 'tc_tipo', NULL),
        (CASE WHEN prov_fab >= 0.01 THEN
           jsonb_build_array(jsonb_build_object('cuenta_id', cfg.cta_sueldos_fab, 'debe', prov_fab, 'haber', 0,
                             'descripcion', 'Provisión SAC fabricación', 'orden', 0))
         ELSE '[]'::jsonb END)
        || (CASE WHEN prov_adm >= 0.01 THEN
           jsonb_build_array(jsonb_build_object('cuenta_id', cfg.cta_sueldos_adm, 'debe', prov_adm, 'haber', 0,
                             'descripcion', 'Provisión SAC administración', 'orden', 1))
         ELSE '[]'::jsonb END)
        || jsonb_build_array(jsonb_build_object('cuenta_id', cfg.cta_provision_sac, 'debe', 0,
                             'haber', prov_fab + prov_adm, 'descripcion', 'Provisión SAC a pagar', 'orden', 2)));
    END IF;
  END IF;

  UPDATE liquidaciones SET estado = 'confirmada',
    asiento_id = (v_asiento->>'id')::uuid,
    tipo_cambio = COALESCE(p_tipo_cambio, tipo_cambio)
  WHERE id = p_liq_id;

  RETURN jsonb_build_object('id', p_liq_id, 'asiento_id', v_asiento->>'id',
    'provision_asiento_id', v_prov_asiento->>'id', 'provision_aplicada', aplicado);
END $$;

-- ─── 9. anular_liquidacion (RE-EMISIÓN, base 066: guard de pagos) ─────
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
    UPDATE liquidaciones SET observaciones =
      COALESCE(NULLIF(observaciones,'') || ' · ', '') || 'ANULADA: ' || trim(p_motivo)
    WHERE id = p_liq_id;
    UPDATE asientos SET estado = 'anulado'
    WHERE id = l.asiento_id AND empresa_id = emp;
    -- La provisión SAC de esta liquidación también se anula. Los asientos
    -- de PAGO quedan (plata que se movió): bloquean editar/eliminar (082).
    UPDATE asientos SET estado = 'anulado'
    WHERE empresa_id = emp AND origen_tipo = 'liquidacion-prov-sac' AND origen_id = p_liq_id;
    UPDATE liquidaciones SET estado = 'borrador', asiento_id = NULL WHERE id = p_liq_id;
    RETURN jsonb_build_object('ok', true, 'accion', 'reabierta');
  ELSE
    -- FIX 082: un borrador con pagos vivos no se elimina
    IF EXISTS (SELECT 1 FROM asientos a WHERE a.empresa_id = emp AND a.origen_id = p_liq_id
               AND a.origen_tipo IN ('liquidacion-pago-netos','liquidacion-pago-cargas')
               AND a.estado <> 'anulado') THEN
      RAISE EXCEPTION 'La liquidación tiene pagos registrados (netos / F.931) — anulá esos asientos antes de eliminarla';
    END IF;
    DELETE FROM liquidacion_items WHERE liquidacion_id = p_liq_id;
    DELETE FROM liquidaciones WHERE id = p_liq_id;
    RETURN jsonb_build_object('ok', true, 'accion', 'eliminada');
  END IF;
END $$;

-- ─── 10. Grants (mismas firmas; re-afirmar cierre a anon) ────────────
REVOKE ALL ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.anular_liquidacion(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_liquidacion(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_liquidacion(uuid, text) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT
--   (SELECT count(*) FROM information_schema.columns
--     WHERE table_name='empleados' AND column_name IN ('cbu','forma_pago','cod_obra_social','cod_modalidad')) AS cols_emp,   -- 4
--   (SELECT count(*) FROM information_schema.columns
--     WHERE table_name='config_contable' AND column_name IN ('cuit_empleador','lsd_tipo_empresa','lsd_importe_detraer','lsd_tope_aportes')) AS cols_cfg, -- 4
--   (SELECT count(*) FROM information_schema.tables
--     WHERE table_name IN ('conceptos_sueldo','liquidacion_conceptos')) AS tablas,        -- 2
--   (SELECT count(*) FROM pg_policies WHERE tablename='liquidacion_conceptos') AS pol_lc, -- 6
--   (SELECT count(*) FROM conceptos_sueldo) AS conceptos_seed,                            -- 16 por empresa
--   (SELECT indexname FROM pg_indexes WHERE indexname='uq_liquidaciones_periodo_tipo') AS uq;
-- Funcional (UI): (a) cargar dos veces "mensual 08/2026" → error "Ya existe una
-- liquidación mensual del período 08/2026"; (b) con un pago de netos registrado,
-- "Editar"/"Eliminar" → error "tiene pagos registrados"; (c) LSD → Descargar TXT
-- y validar el archivo en ARCA → Libro de Sueldos Digital → Carga de liquidación.
