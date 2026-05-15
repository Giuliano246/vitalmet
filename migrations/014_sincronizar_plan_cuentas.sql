-- ═══════════════════════════════════════════════════════════════════
-- 014_sincronizar_plan_cuentas.sql
-- Sincroniza el plan de cuentas de Vitalmet SA con el último export
-- contable (Cuentas contables (1).xlsx — 125 cuentas, 15-may-2026).
--
-- Esta migración:
--   1) Agrega la columna `saldo_habitual` (deudor|acreedor) a
--      cuentas_contables, con CHECK constraint.
--   2) Inserta cuentas faltantes que ya estaban en el xlsx contable
--      pero no en el seed inicial (migration 007). Concretamente:
--        - 425001 Imp. a las ganancias
--   3) Updatea, para las 125 cuentas del xlsx, los campos:
--        - es_ajustable: aplica regla CATEGÓRICA del owner (RT 6
--          simplificada, sobreescribe la columna "Tipo" del xlsx que
--          tenía inconsistencias). Es TRUE cuando:
--            · tipo ∈ {ingreso, egreso, patrimonio}, O
--            · codigo empieza con 114 (bienes de cambio), O
--            · codigo empieza con 122 (bienes de uso + amort. acum.)
--          Excepción: 666666 CUENTA DE AJUSTES se queda en FALSE
--          porque es la contrapartida del RECPAM (no se ajusta a sí
--          misma → evita circularidad).
--        - saldo_habitual (Deudor/Acreedor)
--        - activa (Habilitado Si/No)
--      NOTA: no pisa `nombre` cuando ya hay una descripción cargada;
--      sólo completa el campo si actualmente coincide con el código
--      (placeholders) y el xlsx tiene una descripción real.
--
-- Idempotente: re-ejecutable sin duplicar ni romper estado existente.
-- Vitalmet SA UUID hardcodeado (a0a19507-2a50-4e80-a716-e9459f51d653).
-- ═══════════════════════════════════════════════════════════════════

-- 1) Schema change: columna saldo_habitual
ALTER TABLE cuentas_contables
  ADD COLUMN IF NOT EXISTS saldo_habitual text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cuentas_contables_saldo_habitual_check'
  ) THEN
    ALTER TABLE cuentas_contables
      ADD CONSTRAINT cuentas_contables_saldo_habitual_check
      CHECK (saldo_habitual IS NULL OR saldo_habitual IN ('deudor','acreedor'));
  END IF;
END $$;

COMMENT ON COLUMN cuentas_contables.saldo_habitual IS
  'Saldo habitual de la cuenta: deudor (activos/gastos) o acreedor (pasivos/PN/ingresos). Tomado del plan contable del contador.';

-- 2) Sincronización masiva desde el xlsx
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  inserted_count int;
  updated_count int;
BEGIN
  -- Tabla temporaria con el snapshot del xlsx
  CREATE TEMP TABLE _plan_cuentas_snapshot (
    codigo          text PRIMARY KEY,
    nombre          text NOT NULL,
    tipo            text NOT NULL,
    es_ajustable    boolean NOT NULL,
    saldo_habitual  text NOT NULL,
    activa          boolean NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _plan_cuentas_snapshot (codigo, nombre, tipo, es_ajustable, saldo_habitual, activa) VALUES
  ('111001', 'CAJA', 'activo', false, 'deudor', true),
  ('111002', '111002', 'activo', false, 'deudor', true),
  ('111003', 'BANCO HSBC', 'activo', false, 'deudor', true),
  ('111004', 'BANCO FRANCES', 'activo', false, 'deudor', true),
  ('111005', 'VALORES A DEPOSITAR', 'activo', false, 'deudor', true),
  ('111006', 'CHEQUES DIFERIDOS', 'activo', false, 'deudor', true),
  ('111007', 'PLAZO FIJO', 'activo', false, 'deudor', true),
  ('111008', 'BANCO CREDICOOP', 'activo', false, 'deudor', true),
  ('111009', 'FONDO DE INVERSION', 'activo', false, 'deudor', true),
  ('112001', 'RODADOS', 'activo', false, 'deudor', true),
  ('112016', 'DEUDORES POR VENTAS', 'activo', false, 'deudor', true),
  ('113001', 'IVA SALDO A FAVOR', 'activo', false, 'deudor', true),
  ('113002', 'GCIAS. SOC SALDO A FAVOR', 'activo', false, 'deudor', true),
  ('113003', 'IVA CREDITO FISCAL', 'activo', false, 'deudor', true),
  ('113004', 'INGRESOS BRUTOS SALDO A FAVOR', 'activo', false, 'deudor', true),
  ('113005', 'RETENCIONES IVA', 'activo', false, 'deudor', true),
  ('113006', 'RETENCIONES I. BRUTOS', 'activo', false, 'deudor', true),
  ('113007', 'PERCEPCION IVA', 'activo', false, 'deudor', true),
  ('113008', '113008', 'activo', false, 'deudor', true),
  ('113009', 'ANTICIPO GANANCIAS', 'activo', false, 'deudor', true),
  ('113013', 'MIRTA SALOCHA CTA. PART.', 'activo', false, 'deudor', true),
  ('113014', 'FABIAN VITALE CTA. PART.', 'activo', false, 'deudor', true),
  ('113015', 'PABLO VITALE CTA. PART.', 'activo', false, 'deudor', true),
  ('113016', 'NORA PEYRANO CTA. PART.', 'activo', false, 'deudor', true),
  ('113018', 'RETENCIONES GANACIAS', 'activo', false, 'deudor', true),
  ('113019', 'RETENCIONES SUSS', 'activo', false, 'deudor', true),
  ('113020', 'OTRAS RETENCIONES', 'activo', false, 'deudor', true),
  ('113021', 'Sircreb retencion', 'activo', false, 'deudor', true),
  ('113022', 'Retencion ley 25413 Ganancias', 'activo', false, 'deudor', true),
  ('113023', 'Prestamos de Personal', 'activo', false, 'deudor', true),
  ('114001', 'Mercaderias', 'activo', true, 'deudor', true),
  ('114002', 'MATERIA PRIMA', 'activo', true, 'deudor', true),
  ('114003', 'ACCES. FABRICACION', 'activo', true, 'deudor', true),
  ('121001', 'PRESTAMOS AL PERSONAL', 'activo', false, 'deudor', true),
  ('121002', 'OTROS CREDITOS O PRESTAMOS', 'activo', false, 'deudor', true),
  ('122001', 'Rodados', 'activo', true, 'deudor', true),
  ('122002', 'INSTALACIONES', 'activo', true, 'deudor', true),
  ('122003', 'MUEBLES Y UTILES', 'activo', true, 'deudor', true),
  ('122004', 'Sist y programas de computacio', 'activo', true, 'deudor', true),
  ('122005', 'Inmuebles', 'activo', true, 'deudor', true),
  ('122006', 'Construcciones y mejoras', 'activo', true, 'deudor', true),
  ('122007', 'MAQUINARIAS', 'activo', true, 'deudor', true),
  ('122008', 'Herramientas', 'activo', true, 'deudor', true),
  ('122010', 'Amort Acum Rodados', 'activo', true, 'deudor', true),
  ('122011', 'Amort Acum Instaleciones', 'activo', true, 'deudor', true),
  ('122012', 'Amort Acum Muebles y utiles', 'activo', true, 'deudor', true),
  ('122013', 'Amort Acum Maquinarias', 'activo', true, 'deudor', true),
  ('122014', 'Amort Acum Inmuebles', 'activo', true, 'deudor', true),
  ('211002', 'PROVEEDORES', 'pasivo', false, 'acreedor', true),
  ('212002', 'Leasing a Pagar', 'pasivo', false, 'acreedor', true),
  ('212003', 'CHEQUES DIFERIDOS', 'pasivo', false, 'acreedor', true),
  ('213002', 'IVA a Pagar', 'pasivo', false, 'acreedor', true),
  ('213003', 'IVA DEBITO', 'pasivo', false, 'acreedor', true),
  ('213004', 'INGRESOS BRUTOS A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213005', 'GANANCIAS A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213006', 'Moratorias Fiscales', 'pasivo', false, 'acreedor', true),
  ('213007', 'RETENCIONES IIBB S/PAGOS A PAG', 'pasivo', false, 'acreedor', true),
  ('213008', 'PERCEPCIONES IIBB', 'pasivo', false, 'acreedor', true),
  ('213009', 'Mis Facilidades a Pagar-Gananc', 'pasivo', false, 'acreedor', true),
  ('213010', 'Ganancias Ret s/ Pagos', 'pasivo', false, 'acreedor', true),
  ('213011', 'MORATORIA ING BRUTOS A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213012', 'BP-ACCIONES O PARTICIP A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213013', 'SEG E HIG-ARBA-M.V.L.  A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213014', 'TARJETA DE CREDITO A PAGAR', 'pasivo', false, 'acreedor', true),
  ('213015', 'LUZ-GAS-AGUA-TELEFONO A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214001', 'R.N.SEG. SOCIAL A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214002', 'R.N. OBRA SOCIAL A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214003', 'ART A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214004', 'UOM A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214005', 'SG.VIDA OBLIG A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214006', 'SUELDOS A PAGAR', 'pasivo', false, 'acreedor', true),
  ('214007', 'Cargas Sociales a Pagar', 'pasivo', false, 'acreedor', true),
  ('310000', '310000', 'patrimonio', true, 'acreedor', true),
  ('312000', '312000', 'patrimonio', true, 'acreedor', true),
  ('313001', '313001', 'patrimonio', true, 'acreedor', true),
  ('314000', '314000', 'patrimonio', true, 'acreedor', true),
  ('411001', 'VENTAS BUENOS AIRES', 'ingreso', true, 'acreedor', true),
  ('411002', 'VENTAS CHUBUT', 'ingreso', true, 'acreedor', true),
  ('411003', 'VENTAS NEUQUEN', 'ingreso', true, 'acreedor', true),
  ('411004', 'VENTAS CAPITAL FEDERAL', 'ingreso', true, 'acreedor', true),
  ('411005', 'VENTAS MENDOZA', 'ingreso', true, 'acreedor', true),
  ('411006', 'VENTAS SALTA', 'ingreso', true, 'acreedor', true),
  ('411007', 'VENTAS RIO GDE. "E"', 'ingreso', true, 'acreedor', true),
  ('411008', 'VENTAS SANTA CRUZ', 'ingreso', true, 'acreedor', true),
  ('411009', 'VENTAS TIERRA DEL FUEGO', 'ingreso', true, 'acreedor', true),
  ('412003', 'Intereses Ganados', 'ingreso', true, 'acreedor', true),
  ('421001', 'SUELDO BRUTO FABRICACION', 'egreso', true, 'deudor', true),
  ('421002', 'CARGAS SOCIALES FABRICACION', 'egreso', true, 'deudor', true),
  ('421006', 'GASTOS MANTEN.FABRICA', 'egreso', true, 'deudor', true),
  ('421007', 'Gastos varios fabricacion', 'egreso', true, 'deudor', true),
  ('421012', 'GASTOS DE SEGUROS', 'egreso', true, 'deudor', true),
  ('421013', 'GASTOS SERVICIO TECNICO', 'egreso', true, 'deudor', true),
  ('421014', 'TRABAJOS DE TERCEROS', 'egreso', true, 'deudor', true),
  ('421015', 'GASTOS MEDICOS PERSONAL', 'egreso', true, 'deudor', true),
  ('421016', 'SERVICIOS TICKET', 'egreso', true, 'deudor', true),
  ('421017', 'GASTOS GENERALES', 'egreso', true, 'deudor', true),
  ('421018', 'ABL - RENTAS INMOB-SEG.E HIGIE', 'egreso', true, 'deudor', true),
  ('422001', 'GASTOS GENERALES', 'egreso', true, 'deudor', true),
  ('422002', 'GASTOS DE LIBRERIA', 'egreso', true, 'deudor', true),
  ('422003', 'SUELDO BRUTO ADMINISTRACION', 'egreso', true, 'deudor', true),
  ('422004', 'CARGAS SOCIALES ADMINISTRACION', 'egreso', true, 'deudor', true),
  ('422005', 'HONORARIOS PROFESIONALES', 'egreso', true, 'deudor', true),
  ('422006', 'Honorar.Tecnicos/Gest.Calidad', 'egreso', true, 'deudor', true),
  ('422007', 'LUZ-GAS-AGUA-TELEFONO', 'egreso', true, 'deudor', true),
  ('422008', 'Gastos e Insumos de Computacio', 'egreso', true, 'deudor', true),
  ('422009', 'GASTOS DE CORREO', 'egreso', true, 'deudor', true),
  ('422014', 'VIATICOS Y MOVILIDAD', 'egreso', true, 'deudor', true),
  ('422015', 'GASTOS LIMPIEZA Y ALMACEN', 'egreso', true, 'deudor', true),
  ('423001', 'Gastos de Administracion', 'egreso', true, 'deudor', true),
  ('423002', 'INGRESOS BRUTOS', 'egreso', true, 'deudor', true),
  ('423003', 'FLETES Y ACARREOS', 'egreso', true, 'deudor', true),
  ('423004', 'GASTOS DE PUBLICIDAD', 'egreso', true, 'deudor', true),
  ('423006', 'Gastos de Comercializacion', 'egreso', true, 'deudor', true),
  ('424001', 'Gastos e Intereses Bancarios', 'egreso', true, 'deudor', true),
  ('424002', 'Intereses Fiscales y Previsio', 'egreso', true, 'deudor', true),
  ('424003', 'Intereses y Recargos Impositiv', 'egreso', true, 'deudor', true),
  ('424005', 'IMPUESTO CH', 'egreso', true, 'deudor', true),
  ('425001', 'Imp. a las ganancias', 'egreso', true, 'deudor', true),
  ('425002', 'ATENCIONES Y CUMPLIDOS', 'egreso', true, 'deudor', true),
  ('425003', 'EVENTOS Y AGASAJOS', 'egreso', true, 'deudor', true),
  ('425004', 'GASTOS DE RODADOS', 'egreso', true, 'deudor', true),
  ('425006', 'Gastos de Bienes de Uso', 'egreso', true, 'deudor', true),
  ('425007', 'GASTOS DE IMPORTACION', 'egreso', true, 'deudor', true),
  ('425008', 'REDONDEOS', 'egreso', true, 'deudor', true),
  ('666666', 'CUENTA DE AJUSTES', 'egreso', false, 'deudor', true);

  -- 2.a) INSERT de cuentas faltantes
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable, saldo_habitual)
  SELECT emp_id, s.codigo, s.nombre, s.tipo, true, s.activa, s.es_ajustable, s.saldo_habitual
  FROM _plan_cuentas_snapshot s
  WHERE NOT EXISTS (
    SELECT 1 FROM cuentas_contables c
    WHERE c.empresa_id = emp_id AND c.codigo = s.codigo
  );
  GET DIAGNOSTICS inserted_count = ROW_COUNT;

  -- 2.b) UPDATE de campos autoritativos del xlsx
  -- - es_ajustable y saldo_habitual: siempre se sincronizan
  -- - activa: siempre se sincroniza
  -- - nombre: sólo se completa si el actual es placeholder (= codigo)
  --   y el xlsx trae una descripción real (≠ codigo)
  UPDATE cuentas_contables c
     SET es_ajustable   = s.es_ajustable,
         saldo_habitual = s.saldo_habitual,
         activa         = s.activa,
         nombre         = CASE
                            WHEN c.nombre = c.codigo AND s.nombre <> s.codigo
                              THEN s.nombre
                            ELSE c.nombre
                          END
    FROM _plan_cuentas_snapshot s
   WHERE c.empresa_id = emp_id
     AND c.codigo = s.codigo
     AND (
       c.es_ajustable IS DISTINCT FROM s.es_ajustable
       OR c.saldo_habitual IS DISTINCT FROM s.saldo_habitual
       OR c.activa IS DISTINCT FROM s.activa
       OR (c.nombre = c.codigo AND s.nombre <> s.codigo)
     );
  GET DIAGNOSTICS updated_count = ROW_COUNT;

  RAISE NOTICE '014: % cuentas insertadas, % cuentas actualizadas', inserted_count, updated_count;
END $$;

-- 3) Backfill defensivo: cuentas que ya existían pero no estaban en
--    el xlsx (ej. 314001/314002/314003 creadas por migration 010 para
--    cierre de ejercicio, 412004 por migration 009). Se les setea
--    saldo_habitual coherente con su `tipo` si quedó NULL.
UPDATE cuentas_contables
   SET saldo_habitual = CASE
                          WHEN tipo IN ('activo','egreso') THEN 'deudor'
                          WHEN tipo IN ('pasivo','patrimonio','ingreso') THEN 'acreedor'
                        END
 WHERE empresa_id = 'a0a19507-2a50-4e80-a716-e9459f51d653'::uuid
   AND saldo_habitual IS NULL;
