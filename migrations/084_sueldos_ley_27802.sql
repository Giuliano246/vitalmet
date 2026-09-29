-- ═══════════════════════════════════════════════════════════════════
-- 084_sueldos_ley_27802.sql
-- Adecuación del motor de sueldos (083) a la Ley 27.802 de Modernización
-- Laboral (2026) — ver docs/analisis/2026-09-29-sueldos-ley-27802.md:
--   · Título II — Fondo de Asistencia Laboral: `fal_pct` en los parámetros
--     previsionales (2,5 % PyME / 1 % grandes sobre la base SIPA, vigente
--     desde el 1/11/2026 por Dec. 408/2026; reduce la contribución SIPA en
--     la misma proporción, art. 76). Se siembra la vigencia 2026-11-01
--     copiando la última vigente con fal_pct = 2,5 (editable en la UI).
--   · art. 48 (LCT 231/92 bis): `periodo_prueba_meses` en el convenio
--     (6 por defecto — Ley 27.742; el CCT puede extenderlo).
--   · art. 51 (LCT 245): base indemnizatoria normal y habitual → la vista
--     v_sueldos_acumulados expone `variables` (regla.indemniz='variable':
--     extras, feriado trabajado, premio, bono) y `excluidos`
--     (regla.indemniz='excluir': vacaciones, SAC).
--   · art. 241: concepto 535 "Gratificación por cese" (ARCA 520010) para la
--     suma pactada en el mutuo acuerdo.
--   · art. 37 (LCT 133): `regla.art133 = true` marca los descuentos
--     voluntarios sujetos al tope del 20 % (seguro de vida, adelanto,
--     embargo, préstamo).
--   · art. 27 (LCT 92 ter): el aporte de obra social (202) lleva la marca
--     `regla.tiempo_completo` (se calcula sobre el equivalente a tiempo completo).
--   · art. 25 (LCT 80): `empleados.certificado_trabajo_at` (fecha de
--     emisión del certificado de trabajo; alerta de 45 días hábiles).
-- No re-emite RPCs. Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Parámetros con vigencia ──────────────────────────────────────
ALTER TABLE public.sueldos_parametros_previsionales
  ADD COLUMN IF NOT EXISTS fal_pct numeric(6,3) NOT NULL DEFAULT 0;
ALTER TABLE public.sueldos_convenio_parametros
  ADD COLUMN IF NOT EXISTS periodo_prueba_meses smallint NOT NULL DEFAULT 6;
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS certificado_trabajo_at timestamptz;

-- ─── 2. Catálogo: marcas de regla para la base indemnizatoria y el art. 133 ──
UPDATE public.conceptos_sueldo SET regla = COALESCE(regla, '{}'::jsonb) || '{"indemniz":"variable"}'::jsonb
 WHERE codigo IN ('10','16','17','64','75') AND (regla->>'indemniz') IS DISTINCT FROM 'variable';
UPDATE public.conceptos_sueldo SET regla = COALESCE(regla, '{}'::jsonb) || '{"indemniz":"excluir"}'::jsonb
 WHERE codigo IN ('18','20','28') AND (regla->>'indemniz') IS DISTINCT FROM 'excluir';
UPDATE public.conceptos_sueldo SET regla = COALESCE(regla, '{}'::jsonb) || '{"art133":true}'::jsonb
 WHERE codigo IN ('204','223','226','227') AND COALESCE((regla->>'art133')::boolean, false) IS DISTINCT FROM true;
-- Obra social a tiempo parcial como tiempo completo (LCT 92 ter). Es una MARCA sobre la regla del
-- seed 083 (la base sigue siendo rem_topeado): el frontend anterior la ignora y sigue calculando
-- igual hasta el deploy; el nuevo usa el equivalente a tiempo completo.
UPDATE public.conceptos_sueldo SET regla = regla || '{"tiempo_completo":true}'::jsonb
 WHERE codigo = '202' AND regla->>'base' = 'rem_topeado'
   AND COALESCE((regla->>'tiempo_completo')::boolean, false) IS DISTINCT FROM true;

-- ─── 3. Concepto 535: gratificación por cese (mutuo acuerdo art. 241) ──
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, regla, origen)
SELECT c.empresa_id, '535', 'Gratificación por cese (art. 241 LCT)', 'no_remunerativo', NULL, 535, true, '520010', true, '000000000000000',
       '{"auto":false,"base":"fijo","cantidad":"1","orden":535}'::jsonb, 'seed'
FROM public.config_contable c
ON CONFLICT (empresa_id, codigo) DO NOTHING;

-- ─── 4. Vista de acumulados: + variables / excluidos (art. 51) ────────
-- CREATE OR REPLACE sólo agrega columnas al final; las existentes quedan iguales (083).
CREATE OR REPLACE VIEW public.v_sueldos_acumulados
  WITH (security_invoker = true)
AS
SELECT i.empresa_id, i.empleado_id, extract(year from l.periodo)::int AS anio, extract(month from l.periodo)::int AS mes, l.tipo,
       i.bruto, i.no_remunerativo, i.aportes, i.neto,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo = '900'), 0) AS ganancias_retenida,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('20','28')), 0) AS sac_pagado,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('16','17')), 0) AS extras_exentas,
       COALESCE((i.f931->>'dias')::numeric, 30) AS dias_trabajados,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c
                 JOIN conceptos_sueldo cs ON cs.empresa_id = i.empresa_id AND cs.codigo = c.codigo
                 WHERE c.item_id = i.id AND cs.regla->>'indemniz' = 'variable'), 0) AS variables,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c
                 JOIN conceptos_sueldo cs ON cs.empresa_id = i.empresa_id AND cs.codigo = c.codigo
                 WHERE c.item_id = i.id AND cs.regla->>'indemniz' = 'excluir'), 0) AS excluidos
FROM liquidacion_items i JOIN liquidaciones l ON l.id = i.liquidacion_id
WHERE l.estado = 'confirmada';
GRANT SELECT ON public.v_sueldos_acumulados TO authenticated;

-- ─── 5. FAL: vigencia 2026-11-01 con 2,5 % (PyME), copiando la última vigente ──
INSERT INTO public.sueldos_parametros_previsionales
  (empresa_id, vigencia_desde, tope_min, tope_max, detraccion, aporte_jubilacion_pct, aporte_inssjp_pct, aporte_os_pct, aporte_os_adherente_pct,
   tipo_empresa, contrib_sipa_pct, contrib_inssjp_pct, contrib_fne_pct, contrib_aaff_pct, contrib_os_pct, contrib_fsr_pct, art_pct, art_fijo,
   ganancias_tope_retencion_pct, fal_pct)
SELECT DISTINCT ON (p.empresa_id) p.empresa_id, '2026-11-01', p.tope_min, p.tope_max, p.detraccion, p.aporte_jubilacion_pct, p.aporte_inssjp_pct, p.aporte_os_pct, p.aporte_os_adherente_pct,
   p.tipo_empresa, p.contrib_sipa_pct, p.contrib_inssjp_pct, p.contrib_fne_pct, p.contrib_aaff_pct, p.contrib_os_pct, p.contrib_fsr_pct, p.art_pct, p.art_fijo,
   p.ganancias_tope_retencion_pct, 2.5
FROM public.sueldos_parametros_previsionales p
WHERE p.vigencia_desde < '2026-11-01'
ORDER BY p.empresa_id, p.vigencia_desde DESC
ON CONFLICT (empresa_id, vigencia_desde) DO NOTHING;

COMMIT;

-- ─── VERIFICACIÓN (esperado: fal=1, prueba=1, cert=1, variable=5, excluir=3, art133=4, os_tc=1, c535=1, vista=2, vig_fal=1 por empresa) ──
-- SELECT (SELECT count(*) FROM information_schema.columns WHERE table_name='sueldos_parametros_previsionales' AND column_name='fal_pct') AS fal,
--        (SELECT count(*) FROM information_schema.columns WHERE table_name='sueldos_convenio_parametros' AND column_name='periodo_prueba_meses') AS prueba,
--        (SELECT count(*) FROM information_schema.columns WHERE table_name='empleados' AND column_name='certificado_trabajo_at') AS cert,
--        (SELECT count(*) FROM conceptos_sueldo WHERE regla->>'indemniz'='variable') AS variable,
--        (SELECT count(*) FROM conceptos_sueldo WHERE regla->>'indemniz'='excluir') AS excluir,
--        (SELECT count(*) FROM conceptos_sueldo WHERE (regla->>'art133')::boolean) AS art133,
--        (SELECT count(*) FROM conceptos_sueldo WHERE codigo='202' AND (regla->>'tiempo_completo')::boolean) AS os_tc,
--        (SELECT count(*) FROM conceptos_sueldo WHERE codigo='535') AS c535,
--        (SELECT count(*) FROM information_schema.columns WHERE table_name='v_sueldos_acumulados' AND column_name IN ('variables','excluidos')) AS vista,
--        (SELECT count(*) FROM sueldos_parametros_previsionales WHERE vigencia_desde='2026-11-01' AND fal_pct=2.5) AS vig_fal;
