-- Smoke de migrations/084_sueldos_ley_27802.sql sobre el stub (después de 083-stub.sql + 083 + 084).
-- Uso: docker exec -i pg084 psql -U postgres -v ON_ERROR_STOP=1 < tests/db/084-smoke.sql
\set ON_ERROR_STOP on
\pset format aligned
\echo '=== VERIFICACIÓN (esperado fal=1 prueba=1 cert=1 variable=5 excluir=3 art133=4 os_tc=1 c535=1 vista=2 vig_fal=1)'
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_name='sueldos_parametros_previsionales' AND column_name='fal_pct') AS fal,
       (SELECT count(*) FROM information_schema.columns WHERE table_name='sueldos_convenio_parametros' AND column_name='periodo_prueba_meses') AS prueba,
       (SELECT count(*) FROM information_schema.columns WHERE table_name='empleados' AND column_name='certificado_trabajo_at') AS cert,
       (SELECT count(*) FROM conceptos_sueldo WHERE regla->>'indemniz'='variable') AS variable,
       (SELECT count(*) FROM conceptos_sueldo WHERE regla->>'indemniz'='excluir') AS excluir,
       (SELECT count(*) FROM conceptos_sueldo WHERE (regla->>'art133')::boolean) AS art133,
       (SELECT count(*) FROM conceptos_sueldo WHERE codigo='202' AND (regla->>'tiempo_completo')::boolean) AS os_tc,
       (SELECT count(*) FROM conceptos_sueldo WHERE codigo='535') AS c535,
       (SELECT count(*) FROM information_schema.columns WHERE table_name='v_sueldos_acumulados' AND column_name IN ('variables','excluidos')) AS vista,
       (SELECT count(*) FROM sueldos_parametros_previsionales WHERE vigencia_desde='2026-11-01' AND fal_pct=2.5) AS vig_fal;

\echo '=== la vigencia del FAL copia los topes de la última vigente'
SELECT vigencia_desde, tope_min, tope_max, detraccion, contrib_sipa_pct, fal_pct FROM sueldos_parametros_previsionales ORDER BY vigencia_desde;
SELECT vigencia_desde, periodo_prueba_meses FROM sueldos_convenio_parametros ORDER BY vigencia_desde;

-- ─── Como usuario authenticated (RLS activa) ───
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

\echo '=== liquidación con extras (10 = variable), vacaciones (18 = excluir) y gratificación por cese (535)'
INSERT INTO empleados (id, empresa_id, legajo, nombre, cuil, centro, modalidad, fecha_ingreso)
VALUES ('e0000000-0000-0000-0000-000000000084', public.current_empresa_id(), '84', 'PEREZ, ANA', '27123456780', 'administracion', 'mensual', '2020-03-10');
SELECT public.guardar_liquidacion(
  '{"periodo":"2026-08-01","tipo":"mensual","fecha_pago":"2026-09-04"}'::jsonb,
  '[{"empleado_id":"e0000000-0000-0000-0000-000000000084","contribuciones":1000,"art":100,
     "conceptos":[{"codigo":"1","cantidad":1,"importe":1000000,"origen":"auto"},
                  {"codigo":"10","cantidad":10,"unidades":"H","importe":120000,"origen":"auto"},
                  {"codigo":"18","cantidad":7,"unidades":"D","importe":280000,"origen":"auto"},
                  {"codigo":"535","cantidad":1,"importe":50000,"origen":"manual"}],
     "contribuciones_detalle":[{"codigo":"644","importe":82700},{"codigo":"649","nombre":"CONTRIBUCION FAL (Ley 27.802)","pct":2.5,"importe":25000}]}]'::jsonb);
SELECT public.confirmar_liquidacion((SELECT id FROM liquidaciones WHERE periodo='2026-08-01' AND tipo='mensual'), 1, false);
\echo '=== vista: bruto 1.400.000, variables 120.000, excluidos 280.000'
SELECT anio, mes, tipo, bruto, no_remunerativo, variables, excluidos FROM v_sueldos_acumulados WHERE empleado_id='e0000000-0000-0000-0000-000000000084';
SELECT contribuciones_detalle FROM liquidacion_items WHERE empleado_id='e0000000-0000-0000-0000-000000000084';

\echo '=== certificado_trabajo_at editable por el usuario'
UPDATE empleados SET certificado_trabajo_at = now() WHERE id='e0000000-0000-0000-0000-000000000084';
SELECT certificado_trabajo_at IS NOT NULL AS emitido FROM empleados WHERE id='e0000000-0000-0000-0000-000000000084';

\echo '=== RLS: otra empresa no ve los acumulados'
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
SELECT count(*) AS acum_otra_empresa FROM v_sueldos_acumulados;
RESET ROLE;
\echo '=== idempotencia: correr la 084 por segunda vez y repetir la VERIFICACIÓN'
