-- ═══════════════════════════════════════════════════════════════════
-- 069 — FIX tc_tipo 'oficial' en el asiento de sueldos (2026-08-14)
-- ═══════════════════════════════════════════════════════════════════
-- Mismo bug que rompía el asiento de factura/NC (ya corregido en el
-- frontend): `confirmar_liquidacion` (definida en 066) arma el asiento de
-- devengamiento y el de provisión SAC con tc_tipo='oficial', valor que el
-- CHECK constraint asientos_tc_tipo_check NO acepta. Al confirmar una
-- liquidación real, crear_asiento lanzaría:
--   new row for relation "asientos" violates check constraint "asientos_tc_tipo_check"
-- Como son asientos en ARS, tc_tipo debe ser NULL (el resto del ERP usa
-- NULL para ARS y 'compra'/'venta' para USD).
--
-- Esta migración re-define confirmar_liquidacion IDÉNTICA a la de 066,
-- cambiando sólo los dos tc_tipo 'oficial' → NULL. No toca ninguna otra
-- lógica (misma firma, mismos cálculos, misma provisión SAC).
BEGIN;

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

  -- SAC: consumir la provisión acumulada (debe 214008 por lo aplicado,
  -- el excedente sigue yendo a gasto por centro — complemento exacto)
  IF l.tipo = 'sac' AND cfg.cta_provision_sac IS NOT NULL THEN
    SELECT COALESCE(sum(al.haber - al.debe), 0) INTO saldo_prov
    FROM asiento_lineas al JOIN asientos a ON a.id = al.asiento_id
    WHERE a.empresa_id = emp AND a.estado = 'confirmado'
      AND al.cuenta_id = cfg.cta_provision_sac;
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

  -- Devengamiento al PERÍODO (fin de mes), no a la fecha de pago (062)
  -- FIX 069: tc_tipo NULL (era 'oficial', rechazado por asientos_tc_tipo_check)
  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha', (l.periodo + interval '1 month' - interval '1 day')::date,
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
          'fecha', (l.periodo + interval '1 month' - interval '1 day')::date,
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

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- La definición viva ya no debe contener 'oficial':
-- SELECT pg_get_functiondef('public.confirmar_liquidacion(uuid,numeric,boolean)'::regprocedure) LIKE '%oficial%' AS tiene_oficial;
--   → debe devolver false
