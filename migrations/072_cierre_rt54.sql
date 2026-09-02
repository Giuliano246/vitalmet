-- ═══════════════════════════════════════════════════════════════════
-- 072 — CIERRE RT 54 MÍNIMO (Sprint A de la auditoría RT 54, 2026-09-02)
-- ═══════════════════════════════════════════════════════════════════
-- Informe: docs/analisis/2026-09-02-auditoria-rt54.md
-- Plan:    docs/superpowers/plans/2026-09-02-sprint-a-cierre-rt54.md
--
-- Qué hace:
--   1. cuentas_contables.rubro_rt54 (CHECK sobre la lista de rubros del
--      modelo de EECC para Entidades Pequeñas) y .naturaleza (texto
--      libre para el anexo "Costo de producción y gastos por
--      naturaleza"; se completa a mano, sprint D).
--   2. Patrimonio neto con nombre (E-01): 310000 Capital suscripto,
--      312000 Ajuste de capital, 313001 Reserva legal, 314000 Resultados
--      no asignados (ejercicios anteriores). Solo renombra si el nombre
--      sigue siendo el código (no pisa renombres manuales). NO mueve
--      saldos entre 314000 y 314002: eso es un asiento que decide la
--      contadora (ver verificación al pie).
--   3. Amortizaciones acumuladas 122010–122014 pasan a saldo_habitual
--      'acreedor' (son regularizadoras de activo, M-03).
--   4. Agrupadoras nuevas: 123000 Activos intangibles (y 122004 "Sist. y
--      programas" cuelga ahí), 215000 Deudas en especie, 216000
--      Previsiones, 220000 Pasivo no corriente (vacía, para reclasificar
--      leasing a mano), 510000 Costo de ventas.
--   5. Cuentas nuevas: 511000 Costo de los bienes vendidos, 424006
--      Diferencias de cambio, 112090 Previsión para incobrables
--      (regularizadora, saldo acreedor), 423007 Deudores incobrables,
--      214009 Provisión vacaciones y cargas sociales, 215001 Anticipos
--      de clientes, 216001 Previsión para juicios.
--   6. rubro_rt54 asignado a todo el plan por prefijo/lista (sección 5
--      del informe).
--   7. 666666 "Cuenta de ajustes" se desactiva si no tiene líneas.
--   8. config_contable: cta_cmv, cta_dif_cambio, cta_prev_incobrables,
--      cta_gasto_incobrables, cta_iigg, cta_iigg_a_pagar,
--      cta_prov_vacaciones, cta_anticipos_clientes, con defaults.
--
-- Convenciones del proyecto: idempotente, BEGIN/COMMIT, empresa
-- hardcodeada, verificación comentada al final. Correr en el SQL Editor
-- ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

-- ─── 1. Columnas nuevas en el plan de cuentas ────────────────────────
ALTER TABLE public.cuentas_contables
  ADD COLUMN IF NOT EXISTS rubro_rt54 text,
  ADD COLUMN IF NOT EXISTS naturaleza text;

ALTER TABLE public.cuentas_contables DROP CONSTRAINT IF EXISTS cuentas_contables_rubro_rt54_chk;
ALTER TABLE public.cuentas_contables ADD CONSTRAINT cuentas_contables_rubro_rt54_chk
  CHECK (rubro_rt54 IS NULL OR rubro_rt54 IN (
    'caja_bancos','inversiones','cuentas_cobrar_clientes','creditos_impositivos',
    'creditos_partes_rel','otras_cuentas_cobrar','bienes_cambio','bienes_uso','intangibles',
    'proveedores','prestamos','deudas_fiscales','deudas_laborales','deudas_especie',
    'deudas_partes_rel','previsiones',
    'capital','ajuste_capital','aportes_irrevocables','reserva_legal','otras_reservas','rna','resultado_ejercicio',
    'ventas','cmv','gastos_comercializacion','gastos_administracion','desvalorizacion','rfyt',
    'otros_ingresos_egresos','iigg'
  ));

COMMENT ON COLUMN public.cuentas_contables.rubro_rt54 IS
  'Rubro del modelo de EECC RT 54 para Entidades Pequeñas al que se expone la cuenta (mig 072). NULL = sin clasificar.';
COMMENT ON COLUMN public.cuentas_contables.naturaleza IS
  'Naturaleza del gasto para el anexo "Costo de producción y gastos por naturaleza" (sueldos, cargas, honorarios, energía...). Texto libre.';

DO $$
DECLARE
  emp uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  v_renombradas int := 0; v_agrup int := 0; v_ctas int := 0; v_rubros int := 0;
  v_padre uuid;
BEGIN
  -- ─── 2. Patrimonio neto con nombre (solo si nombre = código) ──────
  UPDATE public.cuentas_contables SET nombre = CASE codigo
      WHEN '310000' THEN 'Capital suscripto'
      WHEN '312000' THEN 'Ajuste de capital'
      WHEN '313001' THEN 'Reserva legal'
      WHEN '314000' THEN 'Resultados no asignados (ejercicios anteriores)'
    END
  WHERE empresa_id = emp AND codigo IN ('310000','312000','313001','314000') AND nombre = codigo;
  GET DIAGNOSTICS v_renombradas = ROW_COUNT;

  -- El Capital se mantiene a valor nominal (RT 54, Nota 2.16): deja de
  -- ser ajustable; el ajuste va a 312000 (sprint B usa esta marca).
  UPDATE public.cuentas_contables SET es_ajustable = false
   WHERE empresa_id = emp AND codigo = '310000' AND es_ajustable = true;
  UPDATE public.cuentas_contables SET es_ajustable = true
   WHERE empresa_id = emp AND codigo = '312000' AND es_ajustable = false;

  -- ─── 3. Amortizaciones acumuladas: regularizadoras (saldo acreedor) ─
  UPDATE public.cuentas_contables SET saldo_habitual = 'acreedor'
   WHERE empresa_id = emp AND codigo IN ('122010','122011','122012','122013','122014')
     AND saldo_habitual IS DISTINCT FROM 'acreedor';

  -- ─── 4. Agrupadoras nuevas ────────────────────────────────────────
  CREATE TEMP TABLE _agr (codigo text PRIMARY KEY, nombre text, tipo text, padre text) ON COMMIT DROP;
  INSERT INTO _agr VALUES
    ('123000', 'Activos intangibles',        'activo', '120000'),
    ('215000', 'Deudas en especie',          'pasivo', '210000'),
    ('216000', 'Previsiones',                'pasivo', '210000'),
    ('220000', 'Pasivo no corriente',        'pasivo', '200000'),
    ('510000', 'Costo de ventas',            'egreso', NULL);
  INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
  SELECT emp, a.codigo, a.nombre, a.tipo, false, true, false
  FROM _agr a
  WHERE NOT EXISTS (SELECT 1 FROM public.cuentas_contables c WHERE c.empresa_id = emp AND c.codigo = a.codigo);
  GET DIAGNOSTICS v_agrup = ROW_COUNT;
  UPDATE public.cuentas_contables c SET cuenta_padre_id = p.id
    FROM _agr a JOIN public.cuentas_contables p ON p.empresa_id = emp AND p.codigo = a.padre
   WHERE c.empresa_id = emp AND c.codigo = a.codigo AND c.cuenta_padre_id IS NULL;

  -- 122004 Sist. y programas → Activos intangibles
  SELECT id INTO v_padre FROM public.cuentas_contables WHERE empresa_id = emp AND codigo = '123000';
  UPDATE public.cuentas_contables SET cuenta_padre_id = v_padre
   WHERE empresa_id = emp AND codigo = '122004' AND cuenta_padre_id IS DISTINCT FROM v_padre;

  -- ─── 5. Cuentas imputables nuevas ─────────────────────────────────
  CREATE TEMP TABLE _ctas (codigo text PRIMARY KEY, nombre text, tipo text, saldo text, padre text, ajustable boolean) ON COMMIT DROP;
  INSERT INTO _ctas VALUES
    ('511000', 'Costo de los bienes vendidos',              'egreso', 'deudor',   '510000', true),
    ('424006', 'Diferencias de cambio',                     'egreso', 'deudor',   '424000', true),
    ('112090', 'Previsión para incobrables',                'activo', 'acreedor', '112000', false),
    ('423007', 'Deudores incobrables',                      'egreso', 'deudor',   '423000', true),
    ('214009', 'Provisión vacaciones y cargas sociales',    'pasivo', 'acreedor', '214000', false),
    ('215001', 'Anticipos de clientes',                     'pasivo', 'acreedor', '215000', false),
    ('216001', 'Previsión para juicios',                    'pasivo', 'acreedor', '216000', false);
  INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable, saldo_habitual, cuenta_padre_id)
  SELECT emp, x.codigo, x.nombre, x.tipo, true, true, x.ajustable, x.saldo,
         (SELECT id FROM public.cuentas_contables p WHERE p.empresa_id = emp AND p.codigo = x.padre)
  FROM _ctas x
  WHERE NOT EXISTS (SELECT 1 FROM public.cuentas_contables c WHERE c.empresa_id = emp AND c.codigo = x.codigo);
  GET DIAGNOSTICS v_ctas = ROW_COUNT;

  -- ─── 6. rubro_rt54 para todo el plan (solo sobre imputables) ──────
  UPDATE public.cuentas_contables SET rubro_rt54 = CASE
      -- Activo
      WHEN codigo IN ('111007','111009')                       THEN 'inversiones'
      WHEN codigo = '111006'                                   THEN 'cuentas_cobrar_clientes'  -- cheques de cobro diferido
      WHEN codigo LIKE '111%'                                  THEN 'caja_bancos'
      WHEN codigo = '112001'                                   THEN 'bienes_uso'               -- RODADOS mal colgado (E-07)
      WHEN codigo LIKE '112%'                                  THEN 'cuentas_cobrar_clientes'
      WHEN codigo IN ('113013','113014','113015','113016')     THEN 'creditos_partes_rel'
      WHEN codigo = '113023' OR codigo LIKE '121%'             THEN 'otras_cuentas_cobrar'
      WHEN codigo LIKE '113%'                                  THEN 'creditos_impositivos'
      WHEN codigo LIKE '114%'                                  THEN 'bienes_cambio'
      WHEN codigo = '122004' OR codigo LIKE '123%'             THEN 'intangibles'
      WHEN codigo LIKE '122%'                                  THEN 'bienes_uso'
      -- Pasivo
      WHEN codigo LIKE '211%' OR codigo = '212003'             THEN 'proveedores'              -- + cheques de pago diferido
      WHEN codigo LIKE '212%'                                  THEN 'prestamos'
      WHEN codigo = '213012'                                   THEN 'deudas_partes_rel'        -- BP-Acciones (E-07)
      WHEN codigo LIKE '213%'                                  THEN 'deudas_fiscales'
      WHEN codigo LIKE '214%'                                  THEN 'deudas_laborales'
      WHEN codigo LIKE '215%'                                  THEN 'deudas_especie'
      WHEN codigo LIKE '216%'                                  THEN 'previsiones'
      WHEN codigo LIKE '22%'                                   THEN 'prestamos'
      -- Patrimonio neto
      WHEN codigo = '310000'                                   THEN 'capital'
      WHEN codigo = '312000'                                   THEN 'ajuste_capital'
      WHEN codigo = '313001'                                   THEN 'reserva_legal'
      WHEN codigo IN ('314000','314002')                       THEN 'rna'
      WHEN codigo IN ('314001','314003')                       THEN 'resultado_ejercicio'
      WHEN codigo LIKE '31%'                                   THEN 'otras_reservas'
      -- Resultados
      WHEN codigo LIKE '411%'                                  THEN 'ventas'
      WHEN codigo IN ('412003','412004','424006')              THEN 'rfyt'
      WHEN codigo LIKE '412%'                                  THEN 'otros_ingresos_egresos'
      WHEN codigo LIKE '421%'                                  THEN 'cmv'                      -- costo de producción → anexo CMV
      WHEN codigo LIKE '422%'                                  THEN 'gastos_administracion'
      WHEN codigo LIKE '423%'                                  THEN 'gastos_comercializacion'
      WHEN codigo LIKE '424%'                                  THEN 'rfyt'
      WHEN codigo = '425001'                                   THEN 'iigg'
      WHEN codigo LIKE '425%'                                  THEN 'otros_ingresos_egresos'
      WHEN codigo LIKE '51%'                                   THEN 'cmv'
      ELSE NULL END
  WHERE empresa_id = emp AND imputable = true AND rubro_rt54 IS NULL;
  GET DIAGNOSTICS v_rubros = ROW_COUNT;

  -- ─── 7. 666666 "Cuenta de ajustes": huérfana y sin uso → inactiva ──
  UPDATE public.cuentas_contables c SET activa = false
   WHERE c.empresa_id = emp AND c.codigo = '666666' AND c.activa = true
     AND NOT EXISTS (SELECT 1 FROM public.asiento_lineas l WHERE l.cuenta_id = c.id);

  RAISE NOTICE '072: % cuentas de PN renombradas, % agrupadoras nuevas, % cuentas nuevas, % rubros asignados',
    v_renombradas, v_agrup, v_ctas, v_rubros;
END $$;

-- ─── 8. Imputación contable del cierre RT 54 ────────────────────────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_cmv               uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_dif_cambio        uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_prev_incobrables  uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_gasto_incobrables uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_iigg              uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_iigg_a_pagar      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_prov_vacaciones   uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_anticipos_clientes uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

UPDATE public.config_contable c SET
  cta_cmv                = COALESCE(c.cta_cmv,                (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '511000')),
  cta_dif_cambio         = COALESCE(c.cta_dif_cambio,         (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '424006')),
  cta_prev_incobrables   = COALESCE(c.cta_prev_incobrables,   (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '112090')),
  cta_gasto_incobrables  = COALESCE(c.cta_gasto_incobrables,  (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '423007')),
  cta_iigg               = COALESCE(c.cta_iigg,               (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '425001')),
  cta_iigg_a_pagar       = COALESCE(c.cta_iigg_a_pagar,       (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '213005')),
  cta_prov_vacaciones    = COALESCE(c.cta_prov_vacaciones,    (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '214009')),
  cta_anticipos_clientes = COALESCE(c.cta_anticipos_clientes, (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '215001'));

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, en el SQL Editor)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Cuentas nuevas y PN con nombre:
-- SELECT codigo, nombre, tipo, saldo_habitual, rubro_rt54, activa
--   FROM cuentas_contables
--  WHERE codigo IN ('310000','312000','313001','314000','314002','511000','424006','112090','423007','214009','215001','216001','123000','510000','666666')
--  ORDER BY codigo;
--
-- 2. Imputables sin rubro (esperado: solo cuentas raras; completar desde Plan de cuentas → Editar):
-- SELECT codigo, nombre, tipo FROM cuentas_contables WHERE imputable AND activa AND rubro_rt54 IS NULL ORDER BY codigo;
--
-- 3. Cuentas sin nombre (E-07): ponerles nombre o desactivarlas.
-- SELECT codigo, nombre FROM cuentas_contables WHERE nombre = codigo ORDER BY codigo;
--
-- 4. Resultados no asignados duplicados (E-01): si ambas tienen saldo,
--    la contadora define un asiento manual que pase 314000 → 314002
--    (o al revés) y se desactiva la que quede en cero.
-- SELECT c.codigo, c.nombre,
--        round(sum(CASE WHEN a.moneda='USD' THEN l.haber*a.tipo_cambio ELSE l.haber END)
--            - sum(CASE WHEN a.moneda='USD' THEN l.debe*a.tipo_cambio ELSE l.debe END), 2) AS saldo_acreedor_ars
--   FROM cuentas_contables c
--   LEFT JOIN asiento_lineas l ON l.cuenta_id = c.id
--   LEFT JOIN asientos a ON a.id = l.asiento_id AND a.estado = 'confirmado'
--  WHERE c.codigo IN ('314000','314002') GROUP BY c.codigo, c.nombre ORDER BY c.codigo;
--
-- 5. Config del cierre:
-- SELECT cta_cmv IS NOT NULL, cta_dif_cambio IS NOT NULL, cta_prev_incobrables IS NOT NULL,
--        cta_gasto_incobrables IS NOT NULL, cta_iigg IS NOT NULL, cta_iigg_a_pagar IS NOT NULL,
--        cta_prov_vacaciones IS NOT NULL, cta_anticipos_clientes IS NOT NULL
--   FROM config_contable;
