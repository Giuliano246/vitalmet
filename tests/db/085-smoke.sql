-- Smoke de migrations/085_sueldos_ley_27802_fase2.sql (después de 083-stub.sql + 083 + 084 + 085).
-- Uso: docker exec -i pg085 psql -U postgres -v ON_ERROR_STOP=1 < tests/db/085-smoke.sql
\set ON_ERROR_STOP on
\pset format aligned
\echo '=== VERIFICACIÓN (esperado emp=4 nov=2 art133=2 nuevos=11 vac_tabla=1 vac_pol=6)'
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='empleados' AND column_name IN ('rifl_desde','contrato_plazo_hasta','banco_horas','banco_horas_acuerdo')) AS emp,
       (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='sueldos_novedades' AND column_name IN ('hs_banco_acreditadas','hs_banco_compensadas')) AS nov,
       (SELECT count(*) FROM conceptos_sueldo WHERE (regla->>'art133')::boolean) AS art133,
       (SELECT count(*) FROM conceptos_sueldo WHERE codigo IN ('111','112','113','114','115','116','117','118','119','121','122') AND origen='seed') AS nuevos,
       (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='sueldos_vacaciones') AS vac_tabla,
       (SELECT count(*) FROM pg_policies WHERE tablename='sueldos_vacaciones') AS vac_pol;
SELECT codigo, regla ? 'art133' AS art133 FROM conceptos_sueldo WHERE codigo IN ('204','223','226','227') ORDER BY codigo;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

\echo '=== legajo con RIFL, plazo fijo y banco de horas'
INSERT INTO empleados (id, empresa_id, legajo, nombre, cuil, centro, modalidad, fecha_ingreso, rifl_desde, contrato_plazo_hasta, banco_horas, banco_horas_acuerdo)
VALUES ('e0000000-0000-0000-0000-000000000085', public.current_empresa_id(), '85', 'GOMEZ, LUIS', '20123456786', 'fabricacion', 'jornal', '2026-06-01', '2026-06-01', '2027-05-31', true, '2026-10-01');

\echo '=== guardar_novedades con banco de horas: 2 llamadas → 1 fila, quedan 4 y 8'
SELECT public.guardar_novedades('2026-11-01','mensual','[{"empleado_id":"e0000000-0000-0000-0000-000000000085","horas_normales":152,"hs_banco_acreditadas":2,"hs_banco_compensadas":0}]'::jsonb);
SELECT public.guardar_novedades('2026-11-01','mensual','[{"empleado_id":"e0000000-0000-0000-0000-000000000085","horas_normales":152,"hs_banco_acreditadas":4,"hs_banco_compensadas":8}]'::jsonb);
SELECT count(*) AS filas, max(hs_banco_acreditadas) AS acreditadas, max(hs_banco_compensadas) AS compensadas FROM sueldos_novedades WHERE empleado_id='e0000000-0000-0000-0000-000000000085';
\echo '=== frontend anterior (sin los campos nuevos) → los deja en 0, no falla'
SELECT public.guardar_novedades('2026-12-01','mensual','[{"empleado_id":"e0000000-0000-0000-0000-000000000085","horas_normales":160}]'::jsonb);
SELECT periodo, hs_banco_acreditadas, hs_banco_compensadas FROM sueldos_novedades WHERE empleado_id='e0000000-0000-0000-0000-000000000085' ORDER BY periodo;

\echo '=== vacaciones: alta, edición y CHECK de fechas'
INSERT INTO sueldos_vacaciones (empresa_id, empleado_id, anio, desde, hasta, dias, notificado_el)
VALUES (public.current_empresa_id(), 'e0000000-0000-0000-0000-000000000085', 2026, '2027-01-04', '2027-01-17', 14, NULL);
UPDATE sueldos_vacaciones SET notificado_el = '2026-11-20' WHERE empleado_id='e0000000-0000-0000-0000-000000000085';
SELECT anio, desde, hasta, dias, notificado_el, acuerdo_fuera_periodo FROM sueldos_vacaciones;
DO $$ BEGIN
  INSERT INTO sueldos_vacaciones (empresa_id, empleado_id, anio, desde, hasta, dias)
  VALUES (public.current_empresa_id(), 'e0000000-0000-0000-0000-000000000085', 2026, '2027-02-10', '2027-02-01', 1);
  RAISE EXCEPTION 'NO rechazó hasta < desde';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK rechazo de fechas invertidas';
END $$;

\echo '=== liquidación con un beneficio social (113) y reintegro art. 105 (119): van a no remunerativo'
SELECT public.guardar_liquidacion(
  '{"periodo":"2026-11-01","tipo":"mensual","fecha_pago":"2026-12-04"}'::jsonb,
  '[{"empleado_id":"e0000000-0000-0000-0000-000000000085","contribuciones":1000,"art":100,
     "conceptos":[{"codigo":"4","cantidad":160,"unidades":"H","importe":800000,"origen":"auto"},
                  {"codigo":"113","cantidad":1,"importe":30000,"origen":"manual"},
                  {"codigo":"119","cantidad":1,"importe":20000,"origen":"manual"}]}]'::jsonb);
SELECT bruto, no_remunerativo, aportes, neto FROM liquidacion_items WHERE empleado_id='e0000000-0000-0000-0000-000000000085';

\echo '=== RLS: otra empresa no ve vacaciones ni novedades'
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
SELECT (SELECT count(*) FROM sueldos_vacaciones) AS vac, (SELECT count(*) FROM sueldos_novedades) AS nov;
RESET ROLE;
\echo '=== anon no puede ejecutar guardar_novedades'
SELECT has_function_privilege('anon','public.guardar_novedades(date,text,jsonb)','EXECUTE') AS anon_nov,
       has_function_privilege('authenticated','public.guardar_novedades(date,text,jsonb)','EXECUTE') AS auth_nov;
