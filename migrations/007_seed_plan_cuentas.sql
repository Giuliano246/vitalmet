-- ═══════════════════════════════════════════════════════════════════
-- 007_seed_plan_cuentas.sql
-- Carga del plan de cuentas Vitalmet (124 cuentas) desde Excel.
-- Idempotente: no duplica cuentas con mismo codigo en la empresa.
-- ═══════════════════════════════════════════════════════════════════
--
-- INSTRUCCIONES:
-- 1. Obtené el UUID de tu empresa:
--      SELECT id, nombre FROM empresas;
-- 2. Pegá ese UUID en la línea `emp_id := ...` abajo.
-- 3. Ejecutá todo el bloque en Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  emp_id uuid := 'PEGAR_AQUI_EL_UUID_DE_EMPRESA';
  inserted_count int;
BEGIN
  IF emp_id IS NULL OR emp_id::text = 'PEGAR_AQUI_EL_UUID_DE_EMPRESA' THEN
    RAISE EXCEPTION 'Reemplazá emp_id por el UUID de tu empresa antes de ejecutar';
  END IF;

  WITH src(codigo, nombre, tipo, activa) AS (VALUES
  ('111001', 'CAJA', 'activo', true),
  ('111002', '111002', 'activo', true),
  ('111003', 'BANCO HSBC', 'activo', true),
  ('111004', 'BANCO FRANCES', 'activo', true),
  ('111005', 'VALORES A DEPOSITAR', 'activo', true),
  ('111006', 'CHEQUES DIFERIDOS', 'activo', true),
  ('111007', 'PLAZO FIJO', 'activo', true),
  ('111008', 'BANCO CREDICOOP', 'activo', true),
  ('111009', 'FONDO DE INVERSION', 'activo', true),
  ('112001', 'RODADOS', 'activo', true),
  ('112016', 'DEUDORES POR VENTAS', 'activo', true),
  ('113001', 'IVA SALDO A FAVOR', 'activo', true),
  ('113002', 'GCIAS. SOC SALDO A FAVOR', 'activo', true),
  ('113003', 'IVA CREDITO FISCAL', 'activo', true),
  ('113004', 'INGRESOS BRUTOS SALDO A FAVOR', 'activo', true),
  ('113005', 'RETENCIONES IVA', 'activo', true),
  ('113006', 'RETENCIONES I. BRUTOS', 'activo', true),
  ('113007', 'PERCEPCION IVA', 'activo', true),
  ('113008', '113008', 'activo', true),
  ('113009', 'ANTICIPO GANANCIAS', 'activo', true),
  ('113013', 'MIRTA SALOCHA CTA. PART.', 'activo', true),
  ('113014', 'FABIAN VITALE CTA. PART.', 'activo', true),
  ('113015', 'PABLO VITALE CTA. PART.', 'activo', true),
  ('113016', 'NORA PEYRANO CTA. PART.', 'activo', true),
  ('113018', 'RETENCIONES GANACIAS', 'activo', true),
  ('113019', 'RETENCIONES SUSS', 'activo', true),
  ('113020', 'OTRAS RETENCIONES', 'activo', true),
  ('113021', 'Sircreb retencion', 'activo', true),
  ('113022', 'Retencion ley 25413 Ganancias', 'activo', true),
  ('113023', 'Prestamos de Personal', 'activo', true),
  ('114001', 'Mercaderias', 'activo', true),
  ('114002', 'MATERIA PRIMA', 'activo', true),
  ('114003', 'ACCES. FABRICACION', 'activo', true),
  ('121001', 'PRESTAMOS AL PERSONAL', 'activo', true),
  ('121002', 'OTROS CREDITOS O PRESTAMOS', 'activo', true),
  ('122001', 'Rodados', 'activo', true),
  ('122002', 'INSTALACIONES', 'activo', true),
  ('122003', 'MUEBLES Y UTILES', 'activo', true),
  ('122004', 'Sist y programas de computacio', 'activo', true),
  ('122005', 'Inmuebles', 'activo', true),
  ('122006', 'Construcciones y mejoras', 'activo', true),
  ('122007', 'MAQUINARIAS', 'activo', true),
  ('122008', 'Herramientas', 'activo', true),
  ('122010', 'Amort Acum Rodados', 'activo', true),
  ('122011', 'Amort Acum Instaleciones', 'activo', true),
  ('122012', 'Amort Acum Muebles y utiles', 'activo', true),
  ('122013', 'Amort Acum Maquinarias', 'activo', true),
  ('122014', 'Amort Acum Inmuebles', 'activo', true),
  ('211002', 'PROVEEDORES', 'pasivo', true),
  ('212002', 'Leasing a Pagar', 'pasivo', true),
  ('212003', 'CHEQUES DIFERIDOS', 'pasivo', true),
  ('213002', 'IVA a Pagar', 'pasivo', true),
  ('213003', 'IVA DEBITO', 'pasivo', true),
  ('213004', 'INGRESOS BRUTOS A PAGAR', 'pasivo', true),
  ('213005', 'GANANCIAS A PAGAR', 'pasivo', true),
  ('213006', 'Moratorias Fiscales', 'pasivo', true),
  ('213007', 'RETENCIONES IIBB S/PAGOS A PAG', 'pasivo', true),
  ('213008', 'PERCEPCIONES IIBB', 'pasivo', true),
  ('213009', 'Mis Facilidades a Pagar-Gananc', 'pasivo', true),
  ('213010', 'Ganancias Ret s/ Pagos', 'pasivo', true),
  ('213011', 'MORATORIA ING BRUTOS A PAGAR', 'pasivo', true),
  ('213012', 'BP-ACCIONES O PARTICIP A PAGAR', 'pasivo', true),
  ('213013', 'SEG E HIG-ARBA-M.V.L.  A PAGAR', 'pasivo', true),
  ('213014', 'TARJETA DE CREDITO A PAGAR', 'pasivo', true),
  ('213015', 'LUZ-GAS-AGUA-TELEFONO A PAGAR', 'pasivo', true),
  ('214001', 'R.N.SEG. SOCIAL A PAGAR', 'pasivo', true),
  ('214002', 'R.N. OBRA SOCIAL A PAGAR', 'pasivo', true),
  ('214003', 'ART A PAGAR', 'pasivo', true),
  ('214004', 'UOM A PAGAR', 'pasivo', true),
  ('214005', 'SG.VIDA OBLIG A PAGAR', 'pasivo', true),
  ('214006', 'SUELDOS A PAGAR', 'pasivo', true),
  ('214007', 'Cargas Sociales a Pagar', 'pasivo', true),
  ('310000', '310000', 'patrimonio', true),
  ('312000', '312000', 'patrimonio', true),
  ('313001', '313001', 'patrimonio', true),
  ('314000', '314000', 'patrimonio', true),
  ('411001', 'VENTAS BUENOS AIRES', 'ingreso', true),
  ('411002', 'VENTAS CHUBUT', 'ingreso', true),
  ('411003', 'VENTAS NEUQUEN', 'ingreso', true),
  ('411004', 'VENTAS CAPITAL FEDERAL', 'ingreso', true),
  ('411005', 'VENTAS MENDOZA', 'ingreso', true),
  ('411006', 'VENTAS SALTA', 'ingreso', true),
  ('411007', 'VENTAS RIO GDE. "E"', 'ingreso', true),
  ('411008', 'VENTAS SANTA CRUZ', 'ingreso', true),
  ('411009', 'VENTAS TIERRA DEL FUEGO', 'ingreso', true),
  ('412003', 'Intereses Ganados', 'ingreso', true),
  ('421001', 'SUELDO BRUTO FABRICACION', 'egreso', true),
  ('421002', 'CARGAS SOCIALES FABRICACION', 'egreso', true),
  ('421006', 'GASTOS MANTEN.FABRICA', 'egreso', true),
  ('421007', 'Gastos varios fabricacion', 'egreso', true),
  ('421012', 'GASTOS DE SEGUROS', 'egreso', true),
  ('421013', 'GASTOS SERVICIO TECNICO', 'egreso', true),
  ('421014', 'TRABAJOS DE TERCEROS', 'egreso', true),
  ('421015', 'GASTOS MEDICOS PERSONAL', 'egreso', true),
  ('421016', 'SERVICIOS TICKET', 'egreso', true),
  ('421017', 'GASTOS GENERALES', 'egreso', true),
  ('421018', 'ABL - RENTAS INMOB-SEG.E HIGIE', 'egreso', true),
  ('422001', 'GASTOS GENERALES', 'egreso', true),
  ('422002', 'GASTOS DE LIBRERIA', 'egreso', true),
  ('422003', 'SUELDO BRUTO ADMINISTRACION', 'egreso', true),
  ('422004', 'CARGAS SOCIALES ADMINISTRACION', 'egreso', true),
  ('422005', 'HONORARIOS PROFESIONALES', 'egreso', true),
  ('422006', 'Honorar.Tecnicos/Gest.Calidad', 'egreso', true),
  ('422007', 'LUZ-GAS-AGUA-TELEFONO', 'egreso', true),
  ('422008', 'Gastos e Insumos de Computacio', 'egreso', true),
  ('422009', 'GASTOS DE CORREO', 'egreso', true),
  ('422014', 'VIATICOS Y MOVILIDAD', 'egreso', true),
  ('422015', 'GASTOS LIMPIEZA Y ALMACEN', 'egreso', true),
  ('423001', 'Gastos de Administracion', 'egreso', true),
  ('423002', 'INGRESOS BRUTOS', 'egreso', true),
  ('423003', 'FLETES Y ACARREOS', 'egreso', true),
  ('423004', 'GASTOS DE PUBLICIDAD', 'egreso', true),
  ('423006', 'Gastos de Comercializacion', 'egreso', true),
  ('424001', 'Gastos e Intereses Bancarios', 'egreso', true),
  ('424002', 'Intereses Fiscales y Previsio', 'egreso', true),
  ('424003', 'Intereses y Recargos Impositiv', 'egreso', true),
  ('424005', 'IMPUESTO CH', 'egreso', true),
  ('425002', 'ATENCIONES Y CUMPLIDOS', 'egreso', true),
  ('425003', 'EVENTOS Y AGASAJOS', 'egreso', true),
  ('425004', 'GASTOS DE RODADOS', 'egreso', true),
  ('425006', 'Gastos de Bienes de Uso', 'egreso', true),
  ('425007', 'GASTOS DE IMPORTACION', 'egreso', true),
  ('425008', 'REDONDEOS', 'egreso', true),
  ('666666', 'CUENTA DE AJUSTES', 'egreso', true)
  )
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa)
  SELECT emp_id, s.codigo, s.nombre, s.tipo, true, s.activa
  FROM src s
  WHERE NOT EXISTS (
    SELECT 1 FROM cuentas_contables c
    WHERE c.empresa_id = emp_id AND c.codigo = s.codigo
  );

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RAISE NOTICE 'Insertadas % cuentas nuevas (skipped duplicates)', inserted_count;
END $$;
