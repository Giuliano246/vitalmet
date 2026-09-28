-- Smoke funcional de la 083 sobre tests/db/083-stub.sql (ver instrucciones de uso ahí).

-- Smoke funcional de la 083 sobre el stub (se corre después de la migración).
\set ON_ERROR_STOP on
\pset format aligned
\echo '=== VERIFICACIÓN (esperado arca=116 padron=121 seed=26 escala=50 pol=6)'
SELECT (SELECT count(*) FROM conceptos_arca) AS arca,
       (SELECT count(*) FROM conceptos_sueldo WHERE origen='padron') AS padron,
       (SELECT count(*) FROM conceptos_sueldo WHERE origen='seed' AND regla IS NOT NULL) AS seed,
       (SELECT count(*) FROM sueldos_escala) AS escala,
       (SELECT count(*) FROM pg_policies WHERE tablename='sueldos_novedades') AS pol;
\echo '=== 900 debe ser padron/activo (no legacy); 100 del seed 082 debe ser legacy inactivo'
SELECT codigo, tipo, origen, legacy, activo, codigo_arca FROM conceptos_sueldo WHERE codigo IN ('900','100','4','102','998','227') ORDER BY codigo;
\echo '=== marcas char(15) y previsional migrado desde config_contable'
SELECT column_name, data_type, character_maximum_length FROM information_schema.columns WHERE table_name='conceptos_sueldo' AND column_name='marcas';
SELECT vigencia_desde, tope_max, detraccion FROM sueldos_parametros_previsionales;
SELECT vigencia_desde, horas_dia, no_rem_paritaria, scvo_importe FROM sueldos_convenio_parametros;

-- ─── Como usuario authenticated (RLS activa) ───
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
\echo '=== current_empresa_id / es_admin / tiene_modulo'
SELECT public.current_empresa_id(), public.es_admin(), public.tiene_modulo('sueldos');

\echo '=== empleado con préstamo (227) 1/3 pagadas'
INSERT INTO empleados (id, empresa_id, legajo, nombre, cuil, centro, modalidad, fecha_ingreso, conceptos_recurrentes)
VALUES ('e0000000-0000-0000-0000-000000000001', public.current_empresa_id(), '1', 'AYALA, RODRIGO', '20123456786', 'fabricacion', 'jornal', '2026-04-27',
        '[{"codigo":"227","importe":50000,"cuotas_total":3,"cuotas_pagadas":1,"desde":"2026-07-01"}]'::jsonb);

\echo '=== guardar_novedades: upsert (2 llamadas → 1 fila)'
SELECT public.guardar_novedades('2026-09-01','quincena1','[{"empleado_id":"e0000000-0000-0000-0000-000000000001","horas_normales":90,"feriados_no_trabajados":1}]'::jsonb);
SELECT public.guardar_novedades('2026-09-01','quincena1','[{"empleado_id":"e0000000-0000-0000-0000-000000000001","horas_normales":88,"feriados_no_trabajados":1,"otros":[{"codigo":"64","importe":1000}]}]'::jsonb);
SELECT count(*) AS filas, max(horas_normales) AS horas, max(jsonb_array_length(otros)) AS otros FROM sueldos_novedades;

\echo '=== guardar_liquidacion con conceptos 083 (origen/traza/base, ganancias, contribuciones_detalle)'
SELECT public.guardar_liquidacion(
  '{"periodo":"2026-09-01","tipo":"mensual","fecha_pago":"2026-10-04"}'::jsonb,
  '[{"empleado_id":"e0000000-0000-0000-0000-000000000001","contribuciones":1000,"art":100,
     "conceptos":[{"codigo":"4","cantidad":90,"unidades":"H","importe":100000,"origen":"auto","traza":{"formula":"4485.97 × 90 h"},"base":4485.97},
                  {"codigo":"200","cantidad":11,"unidades":"%","importe":11000,"origen":"auto","traza":{"formula":"100000 × 11 %"},"base":100000},
                  {"codigo":"227","cantidad":1,"importe":50000,"origen":"manual"}],
     "f931":{"dias":30},"ganancias":{"retencion_mes":0},"contribuciones_detalle":[{"codigo":"644","importe":1000}]}]'::jsonb) AS r \gset
SELECT l.bruto, l.no_remunerativo, l.aportes, l.neto, l.contribuciones, l.art FROM liquidaciones l;
SELECT codigo, cantidad, importe, dc, origen, traza->>'formula' AS formula, base FROM liquidacion_conceptos ORDER BY orden;
SELECT f931, ganancias, contribuciones_detalle, recibo_nro FROM liquidacion_items;

\echo '=== guardar_liquidacion rechaza concepto legacy (100)'
DO $$ BEGIN
  PERFORM public.guardar_liquidacion('{"periodo":"2026-08-01","tipo":"mensual"}'::jsonb,
    '[{"empleado_id":"e0000000-0000-0000-0000-000000000001","conceptos":[{"codigo":"100","importe":1}]}]'::jsonb);
  RAISE EXCEPTION 'NO rechazó el legacy';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE '%legacy%' THEN RAISE NOTICE 'OK rechazo legacy: %', SQLERRM; ELSE RAISE; END IF;
END $$;

\echo '=== confirmar_liquidacion: recibo_nro=1, prox=2, cuotas_pagadas=2, asiento balanceado'
SELECT public.confirmar_liquidacion((SELECT id FROM liquidaciones WHERE tipo='mensual'), 1, false);
SELECT recibo_nro FROM liquidacion_items;
SELECT recibo_prox_nro FROM config_contable;
SELECT conceptos_recurrentes FROM empleados;
SELECT a.tipo, a.estado, a.fecha, a.descripcion, (SELECT sum(debe) FROM asiento_lineas WHERE asiento_id=a.id) AS debe, (SELECT sum(haber) FROM asiento_lineas WHERE asiento_id=a.id) AS haber FROM asientos a;

\echo '=== liquidación final: cierra el legajo'
SELECT public.guardar_liquidacion(
  '{"periodo":"2026-10-01","tipo":"final","causa_egreso":"renuncia"}'::jsonb,
  '[{"empleado_id":"e0000000-0000-0000-0000-000000000001","conceptos":[{"codigo":"4","cantidad":10,"importe":10000,"origen":"auto"},{"codigo":"517","importe":5000,"origen":"auto"}]}]'::jsonb);
SELECT public.confirmar_liquidacion((SELECT id FROM liquidaciones WHERE tipo='final'), 1, false);
SELECT activo, fecha_egreso, causa_egreso FROM empleados;
SELECT recibo_nro, l.tipo FROM liquidacion_items i JOIN liquidaciones l ON l.id=i.liquidacion_id ORDER BY recibo_nro;

\echo '=== vista de acumulados (security_invoker) como authenticated'
SELECT anio, mes, tipo, bruto, aportes, sac_pagado, dias_trabajados FROM v_sueldos_acumulados ORDER BY mes;

\echo '=== RLS: otra empresa no ve nada (escala, novedades, conceptos)'
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
SELECT (SELECT count(*) FROM sueldos_escala) AS escala, (SELECT count(*) FROM sueldos_novedades) AS nov, (SELECT count(*) FROM conceptos_sueldo) AS conc, (SELECT count(*) FROM conceptos_arca) AS arca_visible, (SELECT count(*) FROM v_sueldos_acumulados) AS acum;
\echo '=== anon no puede ejecutar las RPCs'
RESET ROLE;
SELECT has_function_privilege('anon','public.guardar_novedades(date,text,jsonb)','EXECUTE') AS anon_nov,
       has_function_privilege('anon','public.guardar_liquidacion(jsonb,jsonb,uuid)','EXECUTE') AS anon_liq,
       has_function_privilege('authenticated','public.guardar_novedades(date,text,jsonb)','EXECUTE') AS auth_nov;
\echo '=== idempotencia: segunda corrida de la 083'
