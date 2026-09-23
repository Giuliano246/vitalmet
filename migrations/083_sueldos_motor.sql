-- ═══════════════════════════════════════════════════════════════════
-- 083_sueldos_motor.sql
-- Motor de liquidación de sueldos: catálogo ARCA (padrón 121 conceptos),
-- conceptos del empleador con marcas y regla declarativa, escala UOM y
-- parámetros previsionales/Ganancias con vigencias, novedades mensuales,
-- legajo ampliado y acumulados por empleado. Ver
-- docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv y
-- .superpowers/sdd/2026-09-23-sueldos-motor-liquidacion/task-1-brief.md
--
-- RPCs RE-EMITIDAS (ediciones futuras parten de acá):
--   guardar_liquidacion (base 082), confirmar_liquidacion (base 082).
--   Mismas firmas. anular_liquidacion queda sin cambios (082).
-- Nueva RPC: guardar_novedades(periodo, tipo, items) → upsert de
--   sueldos_novedades por (empresa, empleado, período, tipo).
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Batería RLS (molde 052/053/065/071, incluye modulo_sueldos) ──

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

-- ─── 1. Catálogo ARCA de conceptos (lectura para todos; alta de códigos de
--        rango libre sólo admin, para el importador del padrón) ──────────
CREATE TABLE IF NOT EXISTS public.conceptos_arca (
  codigo      text PRIMARY KEY CHECK (codigo ~ '^\d{6}$'),
  familia     text NOT NULL CHECK (familia IN ('remunerativo','no_remunerativo','descuento')),
  descripcion text NOT NULL,
  uso_libre   boolean NOT NULL DEFAULT false,
  rango_hasta text
);
ALTER TABLE public.conceptos_arca ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lectura_todos ON public.conceptos_arca;
CREATE POLICY lectura_todos ON public.conceptos_arca FOR SELECT TO authenticated USING (true);
-- R29: el importador del padrón (Task 7) crea filas para códigos de rango
-- libre que ARCA no publica como fila propia (p.ej. 551001 dentro de
-- 551000-559999) — sólo admin puede darlas de alta, el resto queda en
-- solo lectura.
DROP POLICY IF EXISTS alta_admin ON public.conceptos_arca;
CREATE POLICY alta_admin ON public.conceptos_arca FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.es_admin()));
INSERT INTO public.conceptos_arca (codigo, familia, descripcion, uso_libre, rango_hasta) VALUES
  ('110000','remunerativo','Sueldo',false,NULL),
  ('110001','remunerativo','Preaviso',false,NULL),
  ('110002','remunerativo','Remuneraciones en especie',false,NULL),
  ('110003','remunerativo','Comida',false,NULL),
  ('110004','remunerativo','Habitación',false,NULL),
  ('110005','remunerativo','Licencias por estudio',false,NULL),
  ('110006','remunerativo','Donación de sangre',false,NULL),
  ('110007','remunerativo','Feriado',false,NULL),
  ('110008','remunerativo','Prest. Dineraria Ley 24557 (primeros 10d)',false,NULL),
  ('110009','remunerativo','Prest. Dineraria Ley 24557 (a cargo de ART)',false,NULL),
  ('110010','remunerativo','Sueldo - RG 2252 actividades simultáneas',false,NULL),
  ('110011','remunerativo','Incremento solidario - Dec. 14/2020',false,NULL),
  ('111000','remunerativo','Sueldo - De uso libre',true,'119999'),
  ('120000','remunerativo','Sueldo anual complementario',false,NULL),
  ('120001','remunerativo','SAC 1er semestre',false,NULL),
  ('120002','remunerativo','SAC 2do semestre',false,NULL),
  ('120003','remunerativo','SAC proporcional',false,NULL),
  ('120004','remunerativo','SAC - RG 2252 actividades simultáneas',false,NULL),
  ('121000','remunerativo','SAC - De uso libre',true,'129999'),
  ('130000','remunerativo','Horas extras',false,NULL),
  ('130001','remunerativo','Horas extras al 50 %',false,NULL),
  ('130002','remunerativo','Horas extras al 100 %',false,NULL),
  ('130003','remunerativo','Horas extras al 200 %',false,NULL),
  ('130004','remunerativo','Horas extras - RG 2252 actividades simultáneas',false,NULL),
  ('131000','remunerativo','Horas extras - De uso libre',true,'139999'),
  ('140000','remunerativo','Zona desfavorable',false,NULL),
  ('140001','remunerativo','Zona desfavorable - RG 2252',false,NULL),
  ('141000','remunerativo','Zona desfavorable - De uso libre',true,'149999'),
  ('150000','remunerativo','Adelanto vacacional',false,NULL),
  ('150001','remunerativo','Adelanto vacacional - RG 2252',false,NULL),
  ('151000','remunerativo','Adelanto vacacional - De uso libre',true,'159999'),
  ('160000','remunerativo','Adicionales',false,NULL),
  ('160001','remunerativo','Adicional por antigüedad',false,NULL),
  ('160002','remunerativo','Adicional por título',false,NULL),
  ('160003','remunerativo','Adicional por tarea',false,NULL),
  ('160004','remunerativo','Adicional por desarraigo',false,NULL),
  ('160005','remunerativo','Adicionales - RG 2252',false,NULL),
  ('161000','remunerativo','Adicionales - De uso libre',true,'169999'),
  ('170000','remunerativo','Gratificaciones y/o Premios',false,NULL),
  ('170001','remunerativo','Premio por presentismo',false,NULL),
  ('170002','remunerativo','Premio por producción',false,NULL),
  ('170003','remunerativo','Comisiones',false,NULL),
  ('170004','remunerativo','Accesorios',false,NULL),
  ('170005','remunerativo','Viáticos sin comprobante',false,NULL),
  ('170006','remunerativo','Propinas habituales no prohibidas',false,NULL),
  ('170007','remunerativo','Gratificaciones - RG 2252',false,NULL),
  ('171000','remunerativo','Gratificaciones y/o Premios - De uso libre',true,'179999'),
  ('180000','remunerativo','Rectificativa por remuneración Ley 27.742',false,NULL),
  ('499999','remunerativo','Redondeo (Remunerativo)',false,NULL),
  ('510000','no_remunerativo','Asignaciones Familiares',false,NULL),
  ('510001','no_remunerativo','Ayuda escolar',false,NULL),
  ('510002','no_remunerativo','Asignación por hijo/hijo con discapacidad',false,NULL),
  ('510003','no_remunerativo','Asignación por maternidad',false,NULL),
  ('510004','no_remunerativo','Asignación por maternidad down',false,NULL),
  ('510005','no_remunerativo','Asignación por matrimonio',false,NULL),
  ('510006','no_remunerativo','Asignación por nacimiento / adopción',false,NULL),
  ('510007','no_remunerativo','Asignación por prenatal',false,NULL),
  ('511000','no_remunerativo','Asignaciones Familiares - De uso libre',true,'519999'),
  ('520000','no_remunerativo','Beneficios sociales',false,NULL),
  ('520001','no_remunerativo','Servicio de comedor',false,NULL),
  ('520002','no_remunerativo','Gastos médicos',false,NULL),
  ('520003','no_remunerativo','Provisión de ropa de trabajo',false,NULL),
  ('520004','no_remunerativo','Guardería',false,NULL),
  ('520005','no_remunerativo','Provisión de útiles escolares',false,NULL),
  ('520006','no_remunerativo','Gastos de sepelio',false,NULL),
  ('520007','no_remunerativo','Cursos de capacitación',false,NULL),
  ('520008','no_remunerativo','Becas (art. 7 Ley 24.241)',false,NULL),
  ('520009','no_remunerativo','Desempleo (art. 7 Ley 24.241)',false,NULL),
  ('520010','no_remunerativo','Gratificación por cese laboral (art. 7 Ley 24.241)',false,NULL),
  ('520011','no_remunerativo','Indemnización por extinción del contrato (art. 7 Ley 24.241)',false,NULL),
  ('520012','no_remunerativo','Vacaciones no gozadas (art. 7 Ley 24.241)',false,NULL),
  ('520013','no_remunerativo','Incapacidad permanente (art. 7 Ley 24.241)',false,NULL),
  ('520014','no_remunerativo','Indemnización por despido',false,NULL),
  ('520015','no_remunerativo','Indemnización sustitutiva del preaviso',false,NULL),
  ('520016','no_remunerativo','Integración mes de despido',false,NULL),
  ('520017','no_remunerativo','SAC sobre integración o preaviso',false,NULL),
  ('520018','no_remunerativo','SAC sobre vacaciones no gozadas',false,NULL),
  ('521000','no_remunerativo','Beneficios sociales - De uso libre',true,'529999'),
  ('530000','no_remunerativo','Incrementos no remunerativos (con aportes OS)',false,NULL),
  ('531000','no_remunerativo','Incrementos no rem. (con aportes OS) - De uso libre',true,'539999'),
  ('540000','no_remunerativo','Incrementos no remunerativos (con aportes y contribuciones OS)',false,NULL),
  ('541000','no_remunerativo','Incrementos no rem. (con aportes y contrib. OS) - De uso libre',true,'549999'),
  ('550000','no_remunerativo','Importes no remunerativos especiales',false,NULL),
  ('551000','no_remunerativo','Importes no remunerativos especiales - De uso libre',true,'559999'),
  ('551001','no_remunerativo','Importes no rem. especiales - uso libre 551001',false,NULL),
  ('560000','no_remunerativo','Mensual - PPC y CCT Especiales',false,NULL),
  ('560001','no_remunerativo','SAC - PPC y CCT Especiales',false,NULL),
  ('560002','no_remunerativo','SAC Proporcional - PPC y CCT Especiales',false,NULL),
  ('560003','no_remunerativo','Vacaciones - PPC y CCT Especiales',false,NULL),
  ('560004','no_remunerativo','Asign. dineraria progr. sociales - Dec. 551/2022',false,NULL),
  ('560005','no_remunerativo','Asign. No remunerativa Dec 841/2022',false,NULL),
  ('560006','no_remunerativo','Asignación no Remunerativa Dcto 438/2023',false,NULL),
  ('570000','no_remunerativo','Mensual - Remuneración No Contributiva',false,NULL),
  ('570001','no_remunerativo','SAC - Remuneración No Contributiva',false,NULL),
  ('570002','no_remunerativo','SAC Proporcional - Remuneración No Contributiva',false,NULL),
  ('570003','no_remunerativo','Vacaciones - Remuneración No Contributiva',false,NULL),
  ('799999','no_remunerativo','Redondeo (No Remunerativo)',false,NULL),
  ('810000','descuento','Sistema previsional',false,NULL),
  ('810001','descuento','INSSJyP',false,NULL),
  ('810002','descuento','Obra Social',false,NULL),
  ('810003','descuento','Fondo Solidario de Redistribución (ex ANSSAL)',false,NULL),
  ('810004','descuento','Cuota Sindical',false,NULL),
  ('810005','descuento','Seguro de Vida',false,NULL),
  ('810006','descuento','RENATEA (ex RENATRE)',false,NULL),
  ('810007','descuento','Préstamos',false,NULL),
  ('810008','descuento','Impuesto a las Ganancias',false,NULL),
  ('810009','descuento','Obra Social - Adherentes',false,NULL),
  ('810010','descuento','Fondo Solidario de Redistribución - Adherentes',false,NULL),
  ('810011','descuento','Ajuste Aporte Dec. 561/2019',false,NULL),
  ('810012','descuento','Salario complementario Dec 332/2020',false,NULL),
  ('810013','descuento','SAC - Ajuste Bases imponibles',false,NULL),
  ('810014','descuento','Pago a cuenta Asign. dineraria Dec. 551/2022',false,NULL),
  ('810015','descuento','Sistema previsional no nacional',false,NULL),
  ('810016','descuento','Obra Social provincial',false,NULL),
  ('820000','descuento','Otros descuentos',false,NULL),
  ('821000','descuento','Otros descuentos - De uso libre',true,'829999')
ON CONFLICT (codigo) DO NOTHING;

-- ─── 2. Conceptos del empleador: código ARCA, marcas, regla ─────────
ALTER TABLE public.conceptos_sueldo
  ADD COLUMN IF NOT EXISTS codigo_arca text REFERENCES public.conceptos_arca(codigo),
  ADD COLUMN IF NOT EXISTS repeticion  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS marcas      char(15) NOT NULL DEFAULT '000000000000000' CHECK (marcas ~ '^[01]{15}$'),
  ADD COLUMN IF NOT EXISTS regla       jsonb,
  ADD COLUMN IF NOT EXISTS legacy      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS origen      text NOT NULL DEFAULT 'manual' CHECK (origen IN ('padron','seed','manual'));
COMMENT ON COLUMN public.conceptos_sueldo.marcas IS
  '15 marcas ARCA en orden del CSV: SIPA-A SIPA-C INSSJP-A INSSJP-C OS-A OS-C FSR-A FSR-C REN-A REN-C AAFF FNE LRT DIF ESP';

-- 2a. Padrón ARCA 2026-09-23 (121 filas, docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv).
--     Formato: (codigo_arca, codigo, nombre, repeticion, marcas, activo). Activos = canónicos; el resto legacy.
--     El JOIN de abajo contra conceptos_arca descarta en silencio cualquier fila cuyo
--     codigo_arca no esté en el catálogo (p.ej. '551001', un código de rango libre dentro
--     de 551000-559999 que ARCA no publica como fila propia — R13: se le da su propia fila
--     en conceptos_arca §1). Si se agrega un código nuevo de rango libre al padrón, primero
--     hay que sumarlo a conceptos_arca o la fila se pierde sin error.
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, legacy, origen)
SELECT c.empresa_id, p.codigo, p.nombre,
       CASE a.familia WHEN 'remunerativo' THEN 'remunerativo' WHEN 'no_remunerativo' THEN 'no_remunerativo' ELSE 'descuento' END,
       NULL, 500 + row_number() OVER (), p.activo, p.codigo_arca, p.repeticion, p.marcas, NOT p.activo, 'padron'
FROM public.config_contable c
CROSS JOIN (VALUES
  ('110000','97','SUELDO RETROACTIVO',true,'111111111111100',false),
  ('110000','101','AUMENTO VOLUNTARIO',false,'111111111111100',false),
  ('110000','53','AUMENTO VOLUNTARIO',false,'111111111111100',false),
  ('110000','51','VACACIONES 2021',false,'111111111111100',false),
  ('110000','52','ANTIGUEDAD',false,'111111111111100',false),
  ('110000','44','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('110000','59','ANTIGUEDAD',true,'111111111111100',false),
  ('110000','58','DIAS TRABAJADOS',true,'111111111111100',false),
  ('110000','50','RETROACT VACACIONES',false,'111111111111100',false),
  ('110000','49','RETROACT SAC',false,'111111111111100',false),
  ('110000','42','retroactivo',true,'111111111111100',false),
  ('110000','63','Antiguedad',true,'111111111111100',false),
  ('110000','29','Reteoactivo UOm',false,'111111111111100',false),
  ('110000','54','SAC DICIEMBRE',false,'111111111111100',false),
  ('110000','48','DIF AUMENTO SUELDO',true,'111111111111100',false),
  ('110000','45','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('110000','94','DIAS TRABAJADOS DICIEMBRE 2023',false,'111111111111100',false),
  ('110000','19','DIF AUMENTO JULIO 2023',false,'111111111111100',false),
  ('110000','39','DIF AUMENTO JULIO 2023',false,'111111111111100',false),
  ('110000','30','DIF AUMENTO JULIO 2023',false,'111111111111100',false),
  ('110000','46','DIF AUMENTO JULIO 2023',false,'111111111111100',false),
  ('110000','36','DIF AUMENTO JULIO 2023',false,'111111111111100',false),
  ('110000','84','DIFERENCIA AUMENTO',true,'111111111111100',false),
  ('110000','82','DIFERENCIA AUMENTO',true,'111111111111100',false),
  ('110000','70','DIFRENCIA AUMENTO',true,'111111111111100',false),
  ('110000','83','DIFERENCIA AUMENTO',true,'111111111111100',false),
  ('110000','73','DIFERENCIA AUMENTO',true,'111111111111100',false),
  ('110000','72','DIFERENCIA AUMENTO',true,'111111111111100',false),
  ('110000','11','DIF AUMENTO ABRIL 2024 4%',false,'111111111111100',false),
  ('110000','15','ANTIGUEDAD',false,'111111111111100',false),
  ('110000','38','SAC DIC 23 RETROACT AUM 12.8/',false,'111111111111100',false),
  ('110000','32','NOVIEMBRE 23 RETROACTIVO AUM 8.3',false,'111111111111100',false),
  ('110000','35','DCIEMBRE 23 RETROAC AUM 12.8',false,'111111111111100',false),
  ('110000','65','DIFERENCIA S.A.C. 2023',false,'111111111111100',false),
  ('110000','96','VACACIONES 2022',false,'111111111111100',false),
  ('110000','47','DIFERENCIA VACACIONES 2023',false,'111111111111100',false),
  ('110000','99','DIAS TRABAJADOS DICIEMBRE 2023',false,'111111111111100',false),
  ('110000','60','VACACIONES2022',false,'111111111111100',false),
  ('110000','1','SUELDO BASISO',true,'111111111111100',true),
  ('110000','69','1ER AGUINALDO',true,'111111111111100',false),
  ('110000','61','1ER AGUINALDO',true,'111111111111100',false),
  ('110000','40','1ER AGUINALDO',true,'111111111111100',false),
  ('110000','43','1ER AGUINALDO',false,'111111111111100',false),
  ('110000','81','1ER AGUINALDO',true,'111111111111100',false),
  ('110000','78','1ER AGUINALDO',true,'111111111111100',false),
  ('110000','67','1ER AGUINALDO',false,'111111111111100',false),
  ('110000','41','1ER AGUINALDO',false,'111111111111100',false),
  ('110000','57','VACACIONES 2022',true,'111111111111100',false),
  ('110000','21','ENERO 2023 - 23 DIAS TRABAJADOS',false,'111111111111100',false),
  ('110000','2','SUELDO BASICO',true,'111111111111100',true),
  ('110000','4','JORNAL',true,'111111111111100',true),
  ('110007','5','FERIADO',true,'111111111111100',true),
  ('110008','8','ACCIDENTE',true,'111111111111100',true),
  ('111000','7','ENFERMEDAD',true,'111111111111100',true),
  ('120000','28','SAC PROPORCIONAL',true,'111111111111100',true),
  ('120000','20','AGUINALDO',false,'111111111111100',true),
  ('160000','95','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('160000','62','AUMENTO VOLUNTARIOS',true,'111111111111100',false),
  ('160000','14','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('160000','13','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('160000','56','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('160000','23','AUMENTO VOLUNTARIO',false,'111111111111100',false),
  ('160000','12','AUMENTO VOLUNTARIO',true,'111111111111100',false),
  ('160000','6','AUMENTO VOLUNTARIO',true,'111111111111100',true),
  ('160001','22','ANTIGUEDAD',false,'111111111111100',false),
  ('160001','71','ANTIGUEDAD',true,'111111111111100',false),
  ('160001','79','ANTIGUEDAD',true,'111111111111100',false),
  ('160001','9','ANTIGUEDAD',true,'111111111111100',true),
  ('160001','74','ANTIGUEDAD',true,'111111111111100',false),
  ('160001','68','ANTIGUEDAD',true,'111111111111100',false),
  ('160001','66','ANTIGUEDAD',true,'111111111111100',false),
  ('520012','559','VACACIONES NO GOZADAS',true,'000000000000000',false),
  ('520012','517','VACACIONES NO GOZADAS',false,'000000000000000',true),
  ('520018','561','SA SOBRE VACACIONES NO GOZADAS',true,'000000000000000',false),
  ('520018','521','SAC SOBRE VACACIONES NO GOZ',false,'000000000000000',true),
  ('540000','104','Gratif extraord no rem',false,'000011110000000',false),
  ('540000','103','compensac extraord no rem',false,'000011110000000',false),
  ('540000','102','Gratif extraord no rem',false,'000011110000000',true),
  ('540000','105','compensac extraord no rem',false,'000011110000000',false),
  ('550000','34','ASIG NO REMUN',false,'000011110000100',false),
  ('550000','500','GRAT EXT ORD UOM 2023 CUOTA 1',false,'000000000000000',false),
  ('550000','505','GRAT EXT NO REM UOM 2023 CUOTA 1',false,'000000000000000',false),
  ('550000','33','ASIG NO REMURATIVA',false,'000011110000100',false),
  ('550000','31','ASIG NO REM',false,'000011110000100',true),
  ('550000','580','MARZO NO REM ACU 04-2024',false,'000011110000100',false),
  ('550000','579','FEBRERO NO REM AC ABRIL 24',false,'000011110000100',false),
  ('550000','509','BONO DECRETO 438/2023 CUOTA 2',false,'000000000000000',false),
  ('550000','504','BONO DECRETO 438/2023 CUOTA 2',false,'000000000000000',false),
  ('550000','507','BONO DTO.  438/2023 CUOTA 1',false,'000000000000000',false),
  ('550000','502','BONO DECRETO 438/2023 CUOTA 1',false,'000000000000000',false),
  ('550000','506','GRAT EXT NO REM UOM 2023 CUOTA 2',false,'000000000000000',false),
  ('550000','501','GRAT EXT NO REM UOM 2023 CUOTA 2',false,'000000000000000',false),
  ('551000','400','PRESTAMOS',false,'000000000000000',true),
  ('551000','85','EXTRAORDINARIA NO REMUNERATIVA',false,'000000000000000',true),
  ('551001','91','EXTRAORDINARIA NO REMUNERATIVA',true,'000000000000000',false),
  ('560006','514','BONO DECRETO 438/2023 CUOTA 1',false,'000000000000000',false),
  ('560006','512','BONO DECRETO 438/2023 CUOTA 1',false,'000000000000000',false),
  ('810000','200','JUBILACION',true,'000000000000000',true),
  ('810001','201','LEY 19032',true,'000000000000000',true),
  ('810002','214','Obra Social No rem',true,'000000000000000',false),
  ('810002','208','Obra Social No rem',true,'000000000000000',true),
  ('810002','210','Obra Social no rem',true,'000000000000000',false),
  ('810002','590','OBRA SOC S/ NO REM',false,'000000000000000',false),
  ('810002','202','OBRA SOCIAL',true,'000000000000000',true),
  ('810002','221','O SON S/NOREM',false,'000000000000000',false),
  ('810002','219','Obra Social No rem',false,'000000000000000',false),
  ('810002','212','Obra Social No rem',true,'000000000000000',false),
  ('810002','217','Obra Social No rem',false,'000000000000000',false),
  ('810002','220','O SON S/NOREM',false,'000000000000000',false),
  ('810004','211','Sindicato No Rem',true,'000000000000000',true),
  ('810004','213','Sindicato No Rem',true,'000000000000000',false),
  ('810004','591','SIND SOBRE NO REM',false,'000000000000000',false),
  ('810004','203','SINDICATO',true,'000000000000000',true),
  ('810004','216','Sindicato No Rem',false,'000000000000000',false),
  ('810004','218','Sindicato No Rem',false,'000000000000000',false),
  ('810004','209','Sindicato No Rem',false,'000000000000000',false),
  ('810004','222','SIND SOBRE NO REM',false,'000000000000000',false),
  ('810004','215','Sindicato No Rem',false,'000000000000000',false),
  ('810005','204','SEGURO DE VIDA',true,'000000000000000',true),
  ('810008','900','RET IMP A LAS GANANCIAS',true,'000000000000000',true),
  ('820000','999','REDONDEO',false,'000000000000000',true)
) AS p(codigo_arca, codigo, nombre, repeticion, marcas, activo)
JOIN public.conceptos_arca a ON a.codigo = p.codigo_arca
ON CONFLICT (empresa_id, codigo) DO UPDATE
  SET codigo_arca = EXCLUDED.codigo_arca, repeticion = EXCLUDED.repeticion,
      marcas = EXCLUDED.marcas, origen = 'padron', tipo = EXCLUDED.tipo, nombre = EXCLUDED.nombre,
      legacy = EXCLUDED.legacy, activo = EXCLUDED.activo;

-- 2b. Seed 082 (100..900): pasa a legacy inactivo (no está en ARCA)
UPDATE public.conceptos_sueldo SET legacy = true, activo = false
 WHERE origen = 'manual' AND codigo IN ('100','110','120','130','131','140','150','160','190','300','310','320','330','340','350','900')
   AND codigo_arca IS NULL;

-- 2c. Conceptos nuevos del motor (regla declarativa). regla: ver spec §Reglas.
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, regla, origen)
SELECT c.empresa_id, s.codigo, s.nombre, s.tipo, s.unidades, s.orden, true, s.arca, true, s.marcas, s.regla::jsonb, 'seed'
FROM public.config_contable c CROSS JOIN (VALUES
  ('3','Presentismo','remunerativo',NULL,30,'170001','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"basico_mas_antiguedad","pct_param":"presentismo_pct","cantidad":"1","condicion":"presentismo_ok","orden":30}'),
  ('10','Horas extras 50 %','remunerativo','H',40,'130001','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":1.5,"cantidad":"novedad.hs_extra_50","orden":40}'),
  ('16','Horas extras 100 %','remunerativo','H',41,'130002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":2,"cantidad":"novedad.hs_extra_100","orden":41}'),
  ('17','Feriado trabajado','remunerativo','H',42,'130002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":2,"cantidad":"novedad.feriados_trabajados_hs","orden":42}'),
  ('18','Vacaciones','remunerativo','D',50,'150000','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia_vacaciones","cantidad":"novedad.vacaciones_dias","orden":50}'),
  ('24','Complemento IMGR','remunerativo',NULL,60,'110000','111111111111100','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"complemento_imgr","cantidad":"1","orden":60}'),
  ('25','Tarea peligrosa 20 % (art. 65)','remunerativo','%',22,'160003','111111111111100','{"auto":false,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"basico","pct":20,"cantidad":"1","orden":22}'),
  ('26','Altas calorías 20 % (art. 66)','remunerativo','%',23,'160003','111111111111100','{"auto":false,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"basico","pct":20,"cantidad":"1","orden":23}'),
  ('27','Adicional por título','remunerativo','$',24,'160002','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":24}'),
  ('37','Licencia paga','remunerativo','D',45,'111000','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia","cantidad":"novedad.licencia_paga_dias","orden":45}'),
  ('64','Premio por producción','remunerativo','$',70,'170002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"novedad.premio_produccion","orden":70}'),
  ('75','Bono / gratificación','remunerativo','$',71,'170000','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":71}'),
  ('86','Preaviso trabajado','remunerativo','D',80,'110001','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia","cantidad":"1","orden":80}'),
  ('106','Viáticos con comprobante','no_remunerativo','$',110,'520000','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":110}'),
  ('205','Aporte solidario UOM','descuento','%',205,'810004','000000000000000','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"rem_bruto","pct_param":"aporte_solidario_pct","cantidad":"1","condicion":"no_afiliado","orden":205}'),
  ('206','Seguro de sepelio UOM','descuento','$',206,'810005','000000000000000','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"fijo_param","importe_param":"sepelio_importe","cantidad":"1","orden":206}'),
  ('207','Obra social adherentes 1,5 %','descuento','%',207,'810009','000000000000000','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"rem_topeado","pct_param":"aporte_os_adherente_pct","cantidad":"legajo.adherentes","orden":207}'),
  ('223','Adelanto de sueldo','descuento','$',223,'820000','000000000000000','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"novedad.adelanto","orden":223}'),
  ('226','Embargo judicial','descuento','$',226,'820000','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","tope_pct_neto":20,"orden":226}'),
  ('227','Cuota de préstamo','descuento','$',227,'810007','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":227}'),
  ('530','Indemnización por antigüedad art. 245','no_remunerativo',NULL,530,'520014','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":530}'),
  ('531','Indemnización sustitutiva de preaviso','no_remunerativo',NULL,531,'520015','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":531}'),
  ('532','Integración mes de despido','no_remunerativo',NULL,532,'520016','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":532}'),
  ('533','SAC s/ preaviso e integración','no_remunerativo',NULL,533,'520017','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":533}'),
  ('901','Devolución Impuesto a las Ganancias','no_remunerativo',NULL,901,'550000','000000000000000','{"auto":true,"base":"ganancias","cantidad":"1","condicion":"ganancias_aplica","orden":901}'),
  ('998','Redondeo (crédito)','no_remunerativo',NULL,998,'799999','000000000000000','{"auto":true,"base":"redondeo","cantidad":"1","orden":998}')
) AS s(codigo, nombre, tipo, unidades, orden, arca, marcas, regla)
ON CONFLICT (empresa_id, codigo) DO UPDATE SET regla = EXCLUDED.regla, codigo_arca = EXCLUDED.codigo_arca, marcas = EXCLUDED.marcas, origen = 'seed';

-- 2d. Reglas de los canónicos del padrón (los importados no traen regla)
UPDATE public.conceptos_sueldo c SET regla = r.regla::jsonb, unidades = r.unidades, orden = r.orden
FROM (VALUES
  ('1','{"auto":true,"aplica_modalidad":"mensual","base":"basico","cantidad":"1","orden":10}',NULL,10),
  ('4','{"auto":true,"aplica_modalidad":"jornal","base":"valor_hora","cantidad":"horas_normales","orden":10}','H',10),
  ('5','{"auto":true,"aplica_modalidad":"jornal","base":"valor_hora","factor_horas_dia":true,"cantidad":"novedad.feriados_no_trabajados","orden":43}','D',43),
  ('7','{"auto":true,"base":"valor_dia","cantidad":"novedad.enfermedad_dias","orden":46}','D',46),
  ('8','{"auto":true,"base":"valor_dia","cantidad":"novedad.accidente_dias","orden":47}','D',47),
  ('9','{"auto":true,"base":"basico","pct_param":"antiguedad_pct","cantidad":"legajo.antiguedad_anios","orden":20}','%',20),
  ('6','{"auto":false,"base":"fijo","cantidad":"1","orden":25}','$',25),
  ('102','{"auto":true,"aplica_convenio":"uom","base":"no_rem_paritaria","cantidad":"1","orden":59}',NULL,59),
  ('200','{"auto":true,"base":"rem_topeado","pct_param":"aporte_jubilacion_pct","cantidad":"1","orden":200}','%',200),
  ('201','{"auto":true,"base":"rem_topeado","pct_param":"aporte_inssjp_pct","cantidad":"1","orden":201}','%',201),
  ('202','{"auto":true,"base":"rem_topeado","pct_param":"aporte_os_pct","cantidad":"1","orden":202}','%',202),
  ('203','{"auto":true,"aplica_convenio":"uom","base":"rem_bruto","pct_param":"cuota_sindical_pct","cantidad":"1","condicion":"afiliado","orden":203}','%',203),
  ('204','{"auto":false,"base":"fijo","cantidad":"1","orden":204}','$',204),
  ('208','{"auto":true,"base":"no_rem_os","pct_param":"aporte_os_pct","cantidad":"1","orden":208}','%',208),
  ('211','{"auto":true,"aplica_convenio":"uom","base":"no_rem","pct_param":"cuota_sindical_pct","cantidad":"1","condicion":"afiliado","orden":211}','%',211),
  ('900','{"auto":true,"base":"ganancias","cantidad":"1","condicion":"ganancias_aplica","orden":900}',NULL,900),
  ('999','{"auto":true,"base":"redondeo","cantidad":"1","orden":999}',NULL,999),
  ('20','{"auto":false,"base":"sac","cantidad":"1","orden":15}',NULL,15),
  ('28','{"auto":false,"base":"sac","cantidad":"1","orden":16}','D',16)
) AS r(codigo, regla, unidades, orden)
WHERE c.codigo = r.codigo;

-- ─── 3. Escala UOM y parámetros con vigencias ────────────────────────
CREATE TABLE IF NOT EXISTS public.sueldos_convenio_parametros (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  vigencia_desde date NOT NULL,
  imgr numeric(14,2) NOT NULL DEFAULT 0, no_rem_paritaria numeric(14,2) NOT NULL DEFAULT 0, no_rem_codigo text NOT NULL DEFAULT '102',
  antiguedad_pct numeric(6,3) NOT NULL DEFAULT 1, horas_mes integer NOT NULL DEFAULT 200, horas_dia numeric(4,2) NOT NULL DEFAULT 8,
  presentismo_pct numeric(6,3) NOT NULL DEFAULT 0, presentismo_tolerancia_dias smallint NOT NULL DEFAULT 0,
  sepelio_importe numeric(14,2) NOT NULL DEFAULT 0, scvo_importe numeric(14,2) NOT NULL DEFAULT 0,
  cuota_sindical_pct numeric(6,3) NOT NULL DEFAULT 2.5, aporte_solidario_pct numeric(6,3) NOT NULL DEFAULT 2,
  redondeo_a numeric(6,2) NOT NULL DEFAULT 10, tope_por_quincena boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_convenio_parametros');

CREATE TABLE IF NOT EXISTS public.sueldos_escala (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  vigencia_desde date NOT NULL, categoria text NOT NULL,
  modalidad text NOT NULL DEFAULT 'jornal' CHECK (modalidad IN ('jornal','mensual')),
  valor_hora numeric(14,2) NOT NULL DEFAULT 0, basico_mensual numeric(14,2) NOT NULL DEFAULT 0,
  orden integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, vigencia_desde, categoria));
SELECT pg_temp.aplicar_bateria('sueldos_escala');
CREATE INDEX IF NOT EXISTS idx_sueldos_escala_cat ON public.sueldos_escala (empresa_id, categoria, vigencia_desde DESC);

CREATE TABLE IF NOT EXISTS public.sueldos_parametros_previsionales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, vigencia_desde date NOT NULL,
  tope_min numeric(14,2) NOT NULL DEFAULT 0, tope_max numeric(14,2) NOT NULL DEFAULT 0, detraccion numeric(14,2) NOT NULL DEFAULT 0,
  aporte_jubilacion_pct numeric(6,3) NOT NULL DEFAULT 11, aporte_inssjp_pct numeric(6,3) NOT NULL DEFAULT 3,
  aporte_os_pct numeric(6,3) NOT NULL DEFAULT 3, aporte_os_adherente_pct numeric(6,3) NOT NULL DEFAULT 1.5,
  tipo_empresa smallint NOT NULL DEFAULT 1,
  contrib_sipa_pct numeric(6,3) NOT NULL DEFAULT 10.77, contrib_inssjp_pct numeric(6,3) NOT NULL DEFAULT 1.59,
  contrib_fne_pct numeric(6,3) NOT NULL DEFAULT 0.94, contrib_aaff_pct numeric(6,3) NOT NULL DEFAULT 4.70,
  contrib_os_pct numeric(6,3) NOT NULL DEFAULT 5.10, contrib_fsr_pct numeric(6,3) NOT NULL DEFAULT 0.90,
  art_pct numeric(6,3) NOT NULL DEFAULT 0, art_fijo numeric(14,2) NOT NULL DEFAULT 0,
  ganancias_tope_retencion_pct numeric(6,2) NOT NULL DEFAULT 35,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_parametros_previsionales');

CREATE TABLE IF NOT EXISTS public.sueldos_ganancias_tablas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, vigencia_desde date NOT NULL,
  gni_anual numeric(16,2) NOT NULL, deduccion_especial_anual numeric(16,2) NOT NULL,
  conyuge_anual numeric(16,2) NOT NULL, hijo_anual numeric(16,2) NOT NULL, hijo_incap_anual numeric(16,2) NOT NULL,
  tramos jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_ganancias_tablas');

CREATE TABLE IF NOT EXISTS public.sueldos_novedades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  empleado_id uuid NOT NULL REFERENCES public.empleados(id) ON DELETE CASCADE,
  periodo date NOT NULL, tipo text NOT NULL DEFAULT 'mensual' CHECK (tipo IN ('mensual','quincena1','quincena2')),
  dias_trabajados numeric(5,2), horas_normales numeric(6,2), hs_extra_50 numeric(6,2) NOT NULL DEFAULT 0, hs_extra_100 numeric(6,2) NOT NULL DEFAULT 0,
  feriados_no_trabajados smallint NOT NULL DEFAULT 0, feriados_trabajados_hs numeric(6,2) NOT NULL DEFAULT 0,
  ausencias_injustificadas numeric(5,2) NOT NULL DEFAULT 0, enfermedad_dias numeric(5,2) NOT NULL DEFAULT 0, accidente_dias numeric(5,2) NOT NULL DEFAULT 0,
  licencia_paga_dias numeric(5,2) NOT NULL DEFAULT 0, licencia_paga_tipo text, licencia_sin_goce_dias numeric(5,2) NOT NULL DEFAULT 0,
  vacaciones_dias numeric(5,2) NOT NULL DEFAULT 0, adelanto numeric(14,2) NOT NULL DEFAULT 0, premio_produccion numeric(14,2) NOT NULL DEFAULT 0,
  otros jsonb NOT NULL DEFAULT '[]'::jsonb, observaciones text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, empleado_id, periodo, tipo));
SELECT pg_temp.aplicar_bateria('sueldos_novedades');
CREATE INDEX IF NOT EXISTS idx_sueldos_novedades_per ON public.sueldos_novedades (empresa_id, periodo, tipo);

-- Seeds 2026 (por empresa, sólo si no existen)
INSERT INTO public.sueldos_convenio_parametros (empresa_id, vigencia_desde, no_rem_paritaria, horas_dia, scvo_importe)
SELECT empresa_id, '2026-08-01', 80000, 9, 849.24 FROM public.config_contable ON CONFLICT DO NOTHING;   -- 40.000 por quincena (recibo 09/2026)
INSERT INTO public.sueldos_escala (empresa_id, vigencia_desde, categoria, modalidad, valor_hora, orden)
SELECT c.empresa_id, v.vig::date, s.cat, 'jornal', CASE WHEN s.cat='Ingresante' THEN v.vh ELSE 0 END, s.ord
FROM public.config_contable c
CROSS JOIN (VALUES ('2026-08-01',4485.97),('2026-10-01',4665.41),('2026-12-01',4852.02),('2027-01-01',4949.06),('2027-03-01',5122.28)) v(vig,vh)
CROSS JOIN (VALUES ('Ingresante',1),('Operario',2),('Operario Calificado',3),('Medio Oficial',4),('Operario Especializado',5),('Oficial',6),('Operario Especializado Múltiple',7),('Oficial Múltiple',8)) s(cat,ord)
ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_escala (empresa_id, vigencia_desde, categoria, modalidad, basico_mensual, orden)
SELECT c.empresa_id, '2026-08-01', s.cat, 'mensual', 0, s.ord FROM public.config_contable c
CROSS JOIN (VALUES ('Administrativo A1',11),('Administrativo A2',12),('Administrativo A3',13),('Administrativo A4',14),('Técnico B1',21),('Técnico B2',22),('Técnico B3',23),('Técnico B4',24),('Técnico B5',25),('Técnico B6',26)) s(cat,ord)
ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_parametros_previsionales (empresa_id, vigencia_desde, tope_min, tope_max, detraccion)
SELECT empresa_id, '2026-09-01', 144363.55, 4691748.47, 7003.68 FROM public.config_contable ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_ganancias_tablas (empresa_id, vigencia_desde, gni_anual, deduccion_especial_anual, conyuge_anual, hijo_anual, hijo_incap_anual, tramos)
SELECT empresa_id, '2026-07-01', 6019671.36, 28894422.56, 5669323.06, 2859060.30, 5718120.61,
 '[{"desde":0,"hasta":2336953.69,"fijo":0,"pct":5},{"desde":2336953.69,"hasta":4673907.37,"fijo":116847.68,"pct":9},{"desde":4673907.37,"hasta":7010861.06,"fijo":327173.51,"pct":12},{"desde":7010861.06,"hasta":10516291.59,"fijo":607607.96,"pct":15},{"desde":10516291.59,"hasta":21032583.19,"fijo":1133422.53,"pct":19},{"desde":21032583.19,"hasta":31548874.78,"fijo":3131517.94,"pct":23},{"desde":31548874.78,"hasta":47323312.17,"fijo":5550265.01,"pct":27},{"desde":47323312.17,"hasta":70984968.27,"fijo":9809363.11,"pct":31},{"desde":70984968.27,"hasta":null,"fijo":17144476.49,"pct":35}]'::jsonb
FROM public.config_contable ON CONFLICT DO NOTHING;
-- Migrar los dos campos sueltos de config_contable (082) a la tabla con vigencia
UPDATE public.sueldos_parametros_previsionales p SET tope_max = c.lsd_tope_aportes, detraccion = c.lsd_importe_detraer
FROM public.config_contable c WHERE c.empresa_id = p.empresa_id AND p.vigencia_desde = '2026-09-01'
  AND c.lsd_tope_aportes > 0 AND c.lsd_importe_detraer > 0;

-- ─── 4. Legajo ampliado ──────────────────────────────────────────────
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS convenio text NOT NULL DEFAULT 'uom' CHECK (convenio IN ('uom','fuera')),
  ADD COLUMN IF NOT EXISTS categoria_escala text,
  ADD COLUMN IF NOT EXISTS sueldo_pactado numeric(14,2),
  ADD COLUMN IF NOT EXISTS horas_semanales numeric(5,2) NOT NULL DEFAULT 48,
  ADD COLUMN IF NOT EXISTS afiliado_sindicato boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS presentismo boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS antiguedad_pct numeric(6,3),
  ADD COLUMN IF NOT EXISTS adicionales_fijos jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS conceptos_recurrentes jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS ganancias_aplica boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ganancias_deducciones jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS hijos_incap smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fecha_ingreso_reconocida date,
  ADD COLUMN IF NOT EXISTS contratacion text, ADD COLUMN IF NOT EXISTS tarea text,
  ADD COLUMN IF NOT EXISTS lugar_pago text NOT NULL DEFAULT 'Casa Central',
  ADD COLUMN IF NOT EXISTS banco_deposito text, ADD COLUMN IF NOT EXISTS causa_egreso text;
UPDATE public.empleados SET convenio = 'fuera' WHERE centro = 'administracion' AND convenio = 'uom';

ALTER TABLE public.liquidacion_conceptos
  ADD COLUMN IF NOT EXISTS origen text NOT NULL DEFAULT 'manual' CHECK (origen IN ('auto','manual')),
  ADD COLUMN IF NOT EXISTS traza jsonb, ADD COLUMN IF NOT EXISTS base numeric(15,2);
ALTER TABLE public.liquidacion_items
  ADD COLUMN IF NOT EXISTS ganancias jsonb, ADD COLUMN IF NOT EXISTS contribuciones_detalle jsonb,
  ADD COLUMN IF NOT EXISTS recibo_nro integer;
ALTER TABLE public.liquidaciones ADD COLUMN IF NOT EXISTS causa_egreso text;
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS recibo_prox_nro integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS razon_social_recibo text, ADD COLUMN IF NOT EXISTS domicilio_recibo text,
  ADD COLUMN IF NOT EXISTS actividad_recibo text, ADD COLUMN IF NOT EXISTS f931_ultimo_periodo text,
  ADD COLUMN IF NOT EXISTS f931_ultimo_fecha date, ADD COLUMN IF NOT EXISTS f931_banco text,
  ADD COLUMN IF NOT EXISTS tope_indemnizatorio numeric(14,2);

-- ─── 5. Acumulados por empleado/año/mes (liquidaciones confirmadas) ──
CREATE OR REPLACE VIEW public.v_sueldos_acumulados
  WITH (security_invoker = true)
AS
SELECT i.empresa_id, i.empleado_id, extract(year from l.periodo)::int AS anio, extract(month from l.periodo)::int AS mes, l.tipo,
       i.bruto, i.no_remunerativo, i.aportes, i.neto,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo = '900'), 0) AS ganancias_retenida,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('20','28')), 0) AS sac_pagado,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('16','17')), 0) AS extras_exentas,
       COALESCE((i.f931->>'dias')::numeric, 30) AS dias_trabajados
FROM liquidacion_items i JOIN liquidaciones l ON l.id = i.liquidacion_id
WHERE l.estado = 'confirmada';
GRANT SELECT ON public.v_sueldos_acumulados TO authenticated;

-- ─── 6. guardar_novedades ────────────────────────────────────────────
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
      licencia_paga_tipo, licencia_sin_goce_dias, vacaciones_dias, adelanto, premio_produccion, otros, observaciones)
    VALUES (emp, (it->>'empleado_id')::uuid, p_periodo, p_tipo,
      NULLIF(it->>'dias_trabajados','')::numeric, NULLIF(it->>'horas_normales','')::numeric,
      COALESCE((it->>'hs_extra_50')::numeric,0), COALESCE((it->>'hs_extra_100')::numeric,0),
      COALESCE((it->>'feriados_no_trabajados')::int,0), COALESCE((it->>'feriados_trabajados_hs')::numeric,0),
      COALESCE((it->>'ausencias_injustificadas')::numeric,0), COALESCE((it->>'enfermedad_dias')::numeric,0), COALESCE((it->>'accidente_dias')::numeric,0),
      COALESCE((it->>'licencia_paga_dias')::numeric,0), NULLIF(it->>'licencia_paga_tipo',''), COALESCE((it->>'licencia_sin_goce_dias')::numeric,0),
      COALESCE((it->>'vacaciones_dias')::numeric,0), COALESCE((it->>'adelanto')::numeric,0), COALESCE((it->>'premio_produccion')::numeric,0),
      CASE WHEN jsonb_typeof(it->'otros')='array' THEN it->'otros' ELSE '[]'::jsonb END, it->>'observaciones')
    ON CONFLICT (empresa_id, empleado_id, periodo, tipo) DO UPDATE SET
      dias_trabajados = EXCLUDED.dias_trabajados, horas_normales = EXCLUDED.horas_normales, hs_extra_50 = EXCLUDED.hs_extra_50,
      hs_extra_100 = EXCLUDED.hs_extra_100, feriados_no_trabajados = EXCLUDED.feriados_no_trabajados, feriados_trabajados_hs = EXCLUDED.feriados_trabajados_hs,
      ausencias_injustificadas = EXCLUDED.ausencias_injustificadas, enfermedad_dias = EXCLUDED.enfermedad_dias, accidente_dias = EXCLUDED.accidente_dias,
      licencia_paga_dias = EXCLUDED.licencia_paga_dias, licencia_paga_tipo = EXCLUDED.licencia_paga_tipo, licencia_sin_goce_dias = EXCLUDED.licencia_sin_goce_dias,
      vacaciones_dias = EXCLUDED.vacaciones_dias, adelanto = EXCLUDED.adelanto, premio_produccion = EXCLUDED.premio_produccion,
      otros = EXCLUDED.otros, observaciones = EXCLUDED.observaciones;
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('guardadas', n);
END $$;
REVOKE ALL ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) TO authenticated;

-- ─── 7. guardar_liquidacion (RE-EMISIÓN, base 082) ───────────────────
-- p_liq: {periodo, tipo, fecha_pago, observaciones, causa_egreso}
-- p_items: [{empleado_id, bruto, no_remunerativo, aportes, neto,
--            contribuciones, art, detalle, observaciones,
--            conceptos: [{codigo, cantidad, unidades, importe, dc, periodo_ajuste, origen, traza, base}],
--            f931: {...}, ganancias: {...}, contribuciones_detalle: [...]}]
-- Con conceptos: bruto/no_rem/aportes/neto se RECALCULAN desde ellos.
-- Rechaza conceptos legacy (083): usá el código vigente del padrón/seed.
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
        IF EXISTS (SELECT 1 FROM conceptos_sueldo c WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo' AND c.legacy) THEN
          RAISE EXCEPTION 'El concepto % es histórico (legacy) — usá el código vigente', cc->>'codigo';
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
        observaciones = p_liq->>'observaciones',
        causa_egreso = p_liq->>'causa_egreso'
      WHERE id = p_liq_id RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Ya existe una liquidación % del período % — editá esa en vez de cargar otra',
        v_tipo, to_char((p_liq->>'periodo')::date, 'MM/YYYY');
    END;
  ELSE
    BEGIN
      INSERT INTO liquidaciones (empresa_id, periodo, tipo, fecha_pago, observaciones, causa_egreso, created_by)
      VALUES (emp, (p_liq->>'periodo')::date, v_tipo,
              NULLIF(p_liq->>'fecha_pago','')::date,
              p_liq->>'observaciones', p_liq->>'causa_egreso', auth.uid())
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
      no_remunerativo, aportes, neto, contribuciones, art, detalle, observaciones, f931, ganancias, contribuciones_detalle)
    VALUES (emp, v_id, (it->>'empleado_id')::uuid, v_bruto, v_norem, v_aportes, v_neto,
            COALESCE((it->>'contribuciones')::numeric,0), COALESCE((it->>'art')::numeric,0),
            it->'detalle', it->>'observaciones',
            CASE WHEN jsonb_typeof(it->'f931') = 'object' THEN it->'f931' ELSE NULL END,
            CASE WHEN jsonb_typeof(it->'ganancias') = 'object' THEN it->'ganancias' ELSE NULL END,
            CASE WHEN jsonb_typeof(it->'contribuciones_detalle') = 'array' THEN it->'contribuciones_detalle' ELSE NULL END)
    RETURNING id INTO v_item_id;

    IF jsonb_typeof(it->'conceptos') = 'array' THEN
      v_orden := 0;
      FOR cc IN SELECT * FROM jsonb_array_elements(it->'conceptos') LOOP
        SELECT c.tipo INTO v_tipo_c FROM conceptos_sueldo c
         WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo';
        v_dc := CASE WHEN v_tipo_c = 'descuento' THEN 'D' ELSE 'C' END;
        INSERT INTO liquidacion_conceptos (empresa_id, liquidacion_id, item_id, empleado_id,
          codigo, cantidad, unidades, importe, dc, periodo_ajuste, orden, origen, traza, base)
        VALUES (emp, v_id, v_item_id, (it->>'empleado_id')::uuid,
          cc->>'codigo', COALESCE((cc->>'cantidad')::numeric, 0),
          NULLIF(cc->>'unidades',''), round(COALESCE((cc->>'importe')::numeric, 0), 2),
          v_dc, NULLIF(cc->>'periodo_ajuste',''), v_orden,
          CASE WHEN cc->>'origen' = 'auto' THEN 'auto' ELSE 'manual' END,
          CASE WHEN jsonb_typeof(cc->'traza') = 'object' THEN cc->'traza' ELSE NULL END,
          NULLIF(cc->>'base','')::numeric);
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

-- ─── 8. confirmar_liquidacion (RE-EMISIÓN, base 082) ─────────────────
-- 083: agrega numerador de recibos (recibo_nro por ítem), avance de cuotas
-- de préstamo (concepto 227) en conceptos_recurrentes y cierre de legajo
-- (activo=false, fecha_egreso, causa_egreso) cuando el tipo es 'final'.
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
  r record; v_nro int;
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

  -- 083: numerador de recibos, cuotas de préstamos, cierre de legajo en final
  FOR r IN SELECT i.id, i.empleado_id FROM liquidacion_items i WHERE i.liquidacion_id = p_liq_id ORDER BY i.created_at LOOP
    UPDATE config_contable SET recibo_prox_nro = recibo_prox_nro + 1 WHERE empresa_id = emp RETURNING recibo_prox_nro - 1 INTO v_nro;
    UPDATE liquidacion_items SET recibo_nro = v_nro WHERE id = r.id;
    -- préstamo 227 incluido → cuotas_pagadas + 1 en el legajo
    IF EXISTS (SELECT 1 FROM liquidacion_conceptos c WHERE c.item_id = r.id AND c.codigo = '227') THEN
      UPDATE empleados e SET conceptos_recurrentes = (
        SELECT COALESCE(jsonb_agg(CASE WHEN x->>'codigo' = '227' THEN x || jsonb_build_object('cuotas_pagadas', COALESCE((x->>'cuotas_pagadas')::int,0) + 1) ELSE x END), '[]'::jsonb)
        FROM jsonb_array_elements(e.conceptos_recurrentes) x)
      WHERE e.id = r.empleado_id;
    END IF;
    IF l.tipo = 'final' THEN
      UPDATE empleados SET activo = false, fecha_egreso = COALESCE(fecha_egreso, v_fin_mes), causa_egreso = COALESCE(causa_egreso, l.causa_egreso)
       WHERE id = r.empleado_id;
    END IF;
  END LOOP;

  UPDATE liquidaciones SET estado = 'confirmada',
    asiento_id = (v_asiento->>'id')::uuid,
    tipo_cambio = COALESCE(p_tipo_cambio, tipo_cambio)
  WHERE id = p_liq_id;

  RETURN jsonb_build_object('id', p_liq_id, 'asiento_id', v_asiento->>'id',
    'provision_asiento_id', v_prov_asiento->>'id', 'provision_aplicada', aplicado);
END $$;

-- ─── 9. Grants (mismas firmas de guardar_liquidacion/confirmar_liquidacion; re-afirmar cierre a anon) ─
REVOKE ALL ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_liquidacion(jsonb, jsonb, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirmar_liquidacion(uuid, numeric, boolean) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT (SELECT count(*) FROM conceptos_arca) AS arca,                         -- 116
--        (SELECT count(*) FROM conceptos_sueldo WHERE origen='padron') AS padron, -- 121
--        (SELECT count(*) FROM conceptos_sueldo WHERE origen='seed' AND regla IS NOT NULL) AS seed, -- 26
--        (SELECT count(*) FROM sueldos_escala) AS escala,                        -- 50 (8 cat × 5 vig + 10 mensuales)
--        (SELECT count(*) FROM pg_policies WHERE tablename='sueldos_novedades') AS pol; -- 6

