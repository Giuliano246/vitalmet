-- ═══════════════════════════════════════════════════════════════════
-- 015_agrupadoras_plan_cuentas.sql
-- Crea las 18 cuentas agrupadoras (no imputables) del plan de cuentas
-- de Vitalmet SA y reparenta las 129 hojas existentes al padre que
-- corresponde por prefijo de código.
--
-- Estructura final (1 nivel de agrupación):
--   ACTIVO
--     111  Disponibilidades           ← 111001..111009
--     112  Créditos por ventas        ← 112001, 112016
--     113  Otros créditos a CP        ← 113001..113023
--     114  Bienes de cambio  [AJ]     ← 114001..114003
--     121  Otros créditos a LP        ← 121001, 121002
--     122  Bienes de uso     [AJ]     ← 122001..122014
--   PASIVO
--     211  Proveedores                ← 211002
--     212  Deudas financieras         ← 212002, 212003
--     213  Deudas fiscales            ← 213002..213015
--     214  Remuneraciones y CS        ← 214001..214007
--   PATRIMONIO NETO
--     300  Patrimonio Neto  [AJ]      ← 310000, 312000, 313001,
--                                       314000..314003
--   RESULTADOS POSITIVOS
--     411  Ventas           [AJ]      ← 411001..411009
--     412  Otros ingresos   [AJ]      ← 412003, 412004
--   RESULTADOS NEGATIVOS
--     421  Costos de fabricación [AJ] ← 421001..421018
--     422  Gastos de administración [AJ] ← 422001..422015
--     423  Gastos de comercialización [AJ] ← 423001..423006
--     424  Resultados financieros [AJ] ← 424001..424005
--     425  Otros egresos    [AJ]      ← 425001..425008
--   ESPECIAL (sin padre)
--     666666  CUENTA DE AJUSTES (contrapartida RECPAM)
--
-- Idempotente:
--   * agrupadoras: INSERT con NOT EXISTS por (empresa_id, codigo)
--   * reparenting: UPDATE solo sobre hojas con cuenta_padre_id IS NULL
-- ═══════════════════════════════════════════════════════════════════

-- 0) Defensivo: garantizar que la columna cuenta_padre_id exista
ALTER TABLE cuentas_contables
  ADD COLUMN IF NOT EXISTS cuenta_padre_id uuid
  REFERENCES cuentas_contables(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_cuentas_contables_padre
  ON cuentas_contables(cuenta_padre_id);

-- 1) Crear las 18 agrupadoras
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  inserted_count int;
  reparented_count int;
BEGIN
  CREATE TEMP TABLE _agrupadoras (
    codigo          text PRIMARY KEY,
    nombre          text NOT NULL,
    tipo            text NOT NULL,
    saldo_habitual  text NOT NULL,
    es_ajustable    boolean NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _agrupadoras (codigo, nombre, tipo, saldo_habitual, es_ajustable) VALUES
    -- Activo
    ('111', 'Disponibilidades',           'activo',     'deudor',   false),
    ('112', 'Créditos por ventas',        'activo',     'deudor',   false),
    ('113', 'Otros créditos a corto plazo','activo',    'deudor',   false),
    ('114', 'Bienes de cambio',           'activo',     'deudor',   true),
    ('121', 'Otros créditos a largo plazo','activo',    'deudor',   false),
    ('122', 'Bienes de uso',              'activo',     'deudor',   true),
    -- Pasivo
    ('211', 'Proveedores',                'pasivo',     'acreedor', false),
    ('212', 'Deudas financieras',         'pasivo',     'acreedor', false),
    ('213', 'Deudas fiscales',            'pasivo',     'acreedor', false),
    ('214', 'Remuneraciones y cargas sociales','pasivo','acreedor', false),
    -- Patrimonio Neto (todos los 310-314 cuelgan acá)
    ('300', 'Patrimonio Neto',            'patrimonio', 'acreedor', true),
    -- Resultados positivos
    ('411', 'Ventas',                     'ingreso',    'acreedor', true),
    ('412', 'Otros ingresos',             'ingreso',    'acreedor', true),
    -- Resultados negativos
    ('421', 'Costos de fabricación',      'egreso',     'deudor',   true),
    ('422', 'Gastos de administración',   'egreso',     'deudor',   true),
    ('423', 'Gastos de comercialización', 'egreso',     'deudor',   true),
    ('424', 'Resultados financieros',     'egreso',     'deudor',   true),
    ('425', 'Otros egresos',              'egreso',     'deudor',   true);

  -- Insert solo las que aún no existen para esta empresa
  INSERT INTO cuentas_contables
    (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable, saldo_habitual)
  SELECT emp_id, a.codigo, a.nombre, a.tipo, false, true, a.es_ajustable, a.saldo_habitual
  FROM _agrupadoras a
  WHERE NOT EXISTS (
    SELECT 1 FROM cuentas_contables c
    WHERE c.empresa_id = emp_id AND c.codigo = a.codigo
  );
  GET DIAGNOSTICS inserted_count = ROW_COUNT;

  -- 2) Reparenta las hojas existentes a su agrupadora por prefijo
  -- Regla:
  --   * código 666666 → queda huérfano (cuenta especial)
  --   * código empieza con '3' (PN) → padre = '300'
  --   * cualquier otro → padre = LEFT(codigo, 3)
  WITH map AS (
    SELECT c.id AS hijo_id,
           p.id AS padre_id
    FROM cuentas_contables c
    JOIN cuentas_contables p
      ON p.empresa_id = c.empresa_id
     AND p.imputable = false
     AND p.codigo = CASE
                      WHEN LEFT(c.codigo, 1) = '3' THEN '300'
                      ELSE LEFT(c.codigo, 3)
                    END
    WHERE c.empresa_id = emp_id
      AND c.imputable = true
      AND c.cuenta_padre_id IS NULL
      AND c.codigo <> '666666'
  )
  UPDATE cuentas_contables c
     SET cuenta_padre_id = m.padre_id
    FROM map m
   WHERE c.id = m.hijo_id;
  GET DIAGNOSTICS reparented_count = ROW_COUNT;

  RAISE NOTICE '015: % agrupadoras insertadas, % hojas reparentadas',
               inserted_count, reparented_count;
END $$;
