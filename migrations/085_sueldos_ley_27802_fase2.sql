-- ═══════════════════════════════════════════════════════════════════
-- 085_sueldos_ley_27802_fase2.sql
-- Segunda tanda de la Ley 27.802 (texto literal, infoleg 423680) — ver
-- docs/analisis/2026-09-29-sueldos-ley-27802.md, sección "Fase 2":
--   · arts. 156-163 (RIFL): `empleados.rifl_desde` — contribuciones
--     reducidas por 48 meses para las altas encuadradas.
--   · art. 42 (LCT 197 bis): banco de horas — `empleados.banco_horas` +
--     `banco_horas_acuerdo`, y `sueldos_novedades.hs_banco_acreditadas` /
--     `hs_banco_compensadas`.
--   · art. 28 (LCT 95) y LCT 250: `empleados.contrato_plazo_hasta`.
--   · art. 41 (LCT 154): tabla `sueldos_vacaciones` (tramos programados,
--     notificación escrita con 30 días, acuerdo fuera de período).
--   · art. 37 (LCT 133): el adelanto (223) y el embargo (226) salen del
--     tope del 20 % — el adelanto se rige por el art. 130 y el embargo por
--     su propio régimen. Corrige la marca `art133` que puso la 084.
--   · arts. 31 y 34 (LCT 103 bis y 105): conceptos no remunerativos para
--     beneficios sociales y prestaciones complementarias (111-119, 121, 122).
--
-- RPC RE-EMITIDA (ediciones futuras parten de acá):
--   guardar_novedades (base 083, misma firma): acepta los dos campos del
--   banco de horas. Un frontend anterior que no los mande los deja en 0.
-- Idempotente y retrocompatible.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Batería RLS (molde 083, incluye modulo_sueldos) ───────────────
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

-- ─── 1. Legajo y novedades ───────────────────────────────────────────
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS rifl_desde date,
  ADD COLUMN IF NOT EXISTS contrato_plazo_hasta date,
  ADD COLUMN IF NOT EXISTS banco_horas boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS banco_horas_acuerdo date;
ALTER TABLE public.sueldos_novedades
  ADD COLUMN IF NOT EXISTS hs_banco_acreditadas numeric(6,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hs_banco_compensadas numeric(6,2) NOT NULL DEFAULT 0;

-- ─── 2. guardar_novedades re-emitida (base 083) ───────────────────────
CREATE OR REPLACE FUNCTION public.guardar_novedades(p_periodo date, p_tipo text, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE emp uuid := public.current_empresa_id(); it jsonb; n int := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF p_tipo NOT IN ('mensual','quincena1','quincena2') THEN RAISE EXCEPTION 'Tipo de novedad inválido'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
    IF NOT EXISTS (SELECT 1 FROM empleados e WHERE e.id = (it->>'empleado_id')::uuid AND e.empresa_id = emp) THEN
      RAISE EXCEPTION 'Empleado inexistente'; END IF;
    INSERT INTO sueldos_novedades (empresa_id, empleado_id, periodo, tipo, dias_trabajados, horas_normales, hs_extra_50, hs_extra_100,
      feriados_no_trabajados, feriados_trabajados_hs, ausencias_injustificadas, enfermedad_dias, accidente_dias, licencia_paga_dias,
      licencia_paga_tipo, licencia_sin_goce_dias, vacaciones_dias, adelanto, premio_produccion, otros, observaciones,
      hs_banco_acreditadas, hs_banco_compensadas)
    VALUES (emp, (it->>'empleado_id')::uuid, p_periodo, p_tipo,
      NULLIF(it->>'dias_trabajados','')::numeric, NULLIF(it->>'horas_normales','')::numeric,
      COALESCE((it->>'hs_extra_50')::numeric,0), COALESCE((it->>'hs_extra_100')::numeric,0),
      COALESCE((it->>'feriados_no_trabajados')::int,0), COALESCE((it->>'feriados_trabajados_hs')::numeric,0),
      COALESCE((it->>'ausencias_injustificadas')::numeric,0), COALESCE((it->>'enfermedad_dias')::numeric,0), COALESCE((it->>'accidente_dias')::numeric,0),
      COALESCE((it->>'licencia_paga_dias')::numeric,0), NULLIF(it->>'licencia_paga_tipo',''), COALESCE((it->>'licencia_sin_goce_dias')::numeric,0),
      COALESCE((it->>'vacaciones_dias')::numeric,0), COALESCE((it->>'adelanto')::numeric,0), COALESCE((it->>'premio_produccion')::numeric,0),
      CASE WHEN jsonb_typeof(it->'otros')='array' THEN it->'otros' ELSE '[]'::jsonb END, it->>'observaciones',
      COALESCE((it->>'hs_banco_acreditadas')::numeric,0), COALESCE((it->>'hs_banco_compensadas')::numeric,0))
    ON CONFLICT (empresa_id, empleado_id, periodo, tipo) DO UPDATE SET
      dias_trabajados = EXCLUDED.dias_trabajados, horas_normales = EXCLUDED.horas_normales, hs_extra_50 = EXCLUDED.hs_extra_50,
      hs_extra_100 = EXCLUDED.hs_extra_100, feriados_no_trabajados = EXCLUDED.feriados_no_trabajados, feriados_trabajados_hs = EXCLUDED.feriados_trabajados_hs,
      ausencias_injustificadas = EXCLUDED.ausencias_injustificadas, enfermedad_dias = EXCLUDED.enfermedad_dias, accidente_dias = EXCLUDED.accidente_dias,
      licencia_paga_dias = EXCLUDED.licencia_paga_dias, licencia_paga_tipo = EXCLUDED.licencia_paga_tipo, licencia_sin_goce_dias = EXCLUDED.licencia_sin_goce_dias,
      vacaciones_dias = EXCLUDED.vacaciones_dias, adelanto = EXCLUDED.adelanto, premio_produccion = EXCLUDED.premio_produccion,
      otros = EXCLUDED.otros, observaciones = EXCLUDED.observaciones,
      hs_banco_acreditadas = EXCLUDED.hs_banco_acreditadas, hs_banco_compensadas = EXCLUDED.hs_banco_compensadas;
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('guardadas', n);
END $$;
REVOKE ALL ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) TO authenticated;

-- ─── 3. Catálogo ─────────────────────────────────────────────────────
-- 3a. El tope del 20 % (LCT 133) no alcanza al adelanto ni al embargo
UPDATE public.conceptos_sueldo SET regla = regla - 'art133'
 WHERE codigo IN ('223','226') AND regla ? 'art133';

-- 3b. Beneficios sociales (LCT 103 bis) y prestaciones complementarias no remunerativas (LCT 105).
--     Todos de carga manual, sin aportes ni contribuciones (marcas en cero).
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, regla, origen)
SELECT c.empresa_id, s.codigo, s.nombre, 'no_remunerativo', '$', s.orden, true, s.arca, true, '000000000000000',
       jsonb_build_object('auto', false, 'base', 'fijo', 'cantidad', '1', 'orden', s.orden), 'seed'
FROM public.config_contable c CROSS JOIN (VALUES
  ('111','Comedor y alimentación (benef. social)',111,'520001'),
  ('112','Reintegro de gastos médicos (benef. social)',112,'520002'),
  ('113','Ropa de trabajo y equipamiento (benef. social)',113,'520003'),
  ('114','Guardería / sala maternal (benef. social)',114,'520004'),
  ('115','Útiles escolares y guardapolvos (benef. social)',115,'520005'),
  ('116','Gastos de sepelio de familiar a cargo (benef. social)',116,'520006'),
  ('117','Cursos y capacitación (benef. social)',117,'520007'),
  ('118','Reintegro uso de automóvil por km (art. 105)',118,'550000'),
  ('119','Reintegro transporte público (art. 105)',119,'550000'),
  ('121','Telefonía celular e internet laboral (art. 105)',121,'550000'),
  ('122','Vivienda: comodato o locación (art. 105)',122,'550000')
) AS s(codigo, nombre, orden, arca)
ON CONFLICT (empresa_id, codigo) DO NOTHING;

-- ─── 4. Vacaciones programadas (LCT 154) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.sueldos_vacaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  empleado_id uuid NOT NULL REFERENCES public.empleados(id) ON DELETE CASCADE,
  anio integer NOT NULL, desde date NOT NULL, hasta date NOT NULL, dias smallint NOT NULL,
  notificado_el date, acuerdo_fuera_periodo boolean NOT NULL DEFAULT false, observaciones text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sueldos_vacaciones_fechas CHECK (hasta >= desde));
SELECT pg_temp.aplicar_bateria('sueldos_vacaciones');
CREATE INDEX IF NOT EXISTS idx_sueldos_vacaciones_emp ON public.sueldos_vacaciones (empresa_id, empleado_id, anio);

COMMIT;

-- ─── VERIFICACIÓN (esperado por empresa: emp=4, nov=2, art133=2, nuevos=11, vac_tabla=1, vac_pol=6) ──
-- SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='empleados' AND column_name IN ('rifl_desde','contrato_plazo_hasta','banco_horas','banco_horas_acuerdo')) AS emp,
--        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='sueldos_novedades' AND column_name IN ('hs_banco_acreditadas','hs_banco_compensadas')) AS nov,
--        (SELECT count(*) FROM conceptos_sueldo WHERE (regla->>'art133')::boolean) AS art133,
--        (SELECT count(*) FROM conceptos_sueldo WHERE codigo IN ('111','112','113','114','115','116','117','118','119','121','122') AND origen='seed') AS nuevos,
--        (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='sueldos_vacaciones') AS vac_tabla,
--        (SELECT count(*) FROM pg_policies WHERE tablename='sueldos_vacaciones') AS vac_pol;
