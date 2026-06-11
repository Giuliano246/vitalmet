-- ═══════════════════════════════════════════════════════════════════
-- 028_completar_agrupadoras.sql
-- Completa el árbol del plan de cuentas siguiendo el criterio que
-- Giuliano empezó a mano con el Activo (códigos de 6 dígitos,
-- agrupadora = prefijo de 3 dígitos + '000'):
--
--   100000 Activo                      (ya existe)
--     110000 Activo corriente          (ya existe)
--       111000 disponibilidades        (ya existe) ← 111001..111009
--       112000 Creditos x ventas       (ya existe) ← 112001, 112016
--       113000 Otros creditos          (ya existe) ← 113001..113023
--       114000 Bienes de cambio        NUEVA       ← 114001..114003
--     120000 Activo no corriente       NUEVA
--       121000 Otros créditos a largo plazo NUEVA  ← 121001, 121002
--       122000 Bienes de uso           NUEVA       ← 122001..122014
--   200000 Pasivo                      NUEVA
--     210000 Pasivo corriente          NUEVA
--       211000 Deudas comerciales      NUEVA       ← 211002
--       212000 Deudas financieras      NUEVA       ← 212002, 212003
--       213000 Deudas fiscales         NUEVA       ← 213002..213015
--       214000 Remuneraciones y cargas sociales NUEVA ← 214001..214007
--   300000 Patrimonio neto             NUEVA       ← 310000..314000
--   410000 Ingresos                    NUEVA
--     411000 Ventas                    NUEVA       ← 411001..411009
--     412000 Otros ingresos            NUEVA       ← 412003
--   420000 Egresos                     NUEVA
--     421000 Costos de fabricación     NUEVA       ← 421001..421018
--     422000 Gastos de administración  NUEVA       ← 422001..422015
--     423000 Gastos de comercialización NUEVA      ← 423001..423006
--     424000 Resultados financieros    NUEVA       ← 424001..424005
--     425000 Otros egresos             NUEVA       ← 425001..425008
--   666666 CUENTA DE AJUSTES           queda suelta (contrapartida RECPAM)
--
-- Mismo patrón que las agrupadoras existentes: imputable=false,
-- activa=true, es_ajustable=false, saldo_habitual=null.
--
-- Idempotente: agrupadoras con NOT EXISTS por (empresa, codigo);
-- reparenting solo sobre hojas imputables con cuenta_padre_id IS NULL
-- (no pisa nada que ya esté colgado a mano).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  agrupadoras_nuevas int;
  hojas_colgadas int;
  agrup_colgadas int;
BEGIN
  CREATE TEMP TABLE _nuevas (
    codigo       text PRIMARY KEY,
    nombre       text NOT NULL,
    tipo         text NOT NULL,
    padre_codigo text          -- NULL = raíz
  ) ON COMMIT DROP;

  INSERT INTO _nuevas (codigo, nombre, tipo, padre_codigo) VALUES
    -- Activo
    ('114000', 'Bienes de cambio',                 'activo',     '110000'),
    ('120000', 'Activo no corriente',              'activo',     '100000'),
    ('121000', 'Otros créditos a largo plazo',     'activo',     '120000'),
    ('122000', 'Bienes de uso',                    'activo',     '120000'),
    -- Pasivo
    ('200000', 'Pasivo',                           'pasivo',     NULL),
    ('210000', 'Pasivo corriente',                 'pasivo',     '200000'),
    ('211000', 'Deudas comerciales',               'pasivo',     '210000'),
    ('212000', 'Deudas financieras',               'pasivo',     '210000'),
    ('213000', 'Deudas fiscales',                  'pasivo',     '210000'),
    ('214000', 'Remuneraciones y cargas sociales', 'pasivo',     '210000'),
    -- Patrimonio neto
    ('300000', 'Patrimonio neto',                  'patrimonio', NULL),
    -- Resultados
    ('410000', 'Ingresos',                         'ingreso',    NULL),
    ('411000', 'Ventas',                           'ingreso',    '410000'),
    ('412000', 'Otros ingresos',                   'ingreso',    '410000'),
    ('420000', 'Egresos',                          'egreso',     NULL),
    ('421000', 'Costos de fabricación',            'egreso',     '420000'),
    ('422000', 'Gastos de administración',         'egreso',     '420000'),
    ('423000', 'Gastos de comercialización',       'egreso',     '420000'),
    ('424000', 'Resultados financieros',           'egreso',     '420000'),
    ('425000', 'Otros egresos',                    'egreso',     '420000');

  -- 1) Crear las agrupadoras que falten (mismo patrón que 100000..113000)
  INSERT INTO cuentas_contables
    (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
  SELECT emp_id, n.codigo, n.nombre, n.tipo, false, true, false
  FROM _nuevas n
  WHERE NOT EXISTS (
    SELECT 1 FROM cuentas_contables c
    WHERE c.empresa_id = emp_id AND c.codigo = n.codigo
  );
  GET DIAGNOSTICS agrupadoras_nuevas = ROW_COUNT;

  -- 2) Colgar las agrupadoras nuevas de su padre (solo si no tienen)
  UPDATE cuentas_contables c
     SET cuenta_padre_id = p.id
    FROM _nuevas n
    JOIN cuentas_contables p
      ON p.empresa_id = emp_id AND p.codigo = n.padre_codigo
   WHERE c.empresa_id = emp_id
     AND c.codigo = n.codigo
     AND c.cuenta_padre_id IS NULL;
  GET DIAGNOSTICS agrup_colgadas = ROW_COUNT;

  -- 3) Colgar las hojas imputables sueltas en su agrupadora por prefijo:
  --    padre = LEFT(codigo,3) || '000'; patrimonio (3xxxxx) → 300000.
  --    666666 queda suelta. No toca nada ya parentado.
  WITH map AS (
    SELECT c.id AS hijo_id, p.id AS padre_id
    FROM cuentas_contables c
    JOIN cuentas_contables p
      ON p.empresa_id = c.empresa_id
     AND p.imputable = false
     AND p.codigo = CASE
                      WHEN LEFT(c.codigo, 1) = '3' THEN '300000'
                      ELSE LEFT(c.codigo, 3) || '000'
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
  GET DIAGNOSTICS hojas_colgadas = ROW_COUNT;

  RAISE NOTICE '028: % agrupadoras creadas, % agrupadoras colgadas, % hojas reparentadas',
               agrupadoras_nuevas, agrup_colgadas, hojas_colgadas;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT (SELECT count(*) FROM cuentas_contables
--          WHERE empresa_id='a0a19507-2a50-4e80-a716-e9459f51d653'
--            AND imputable=false) AS agrupadoras,        -- esperado: 25
--        (SELECT count(*) FROM cuentas_contables
--          WHERE empresa_id='a0a19507-2a50-4e80-a716-e9459f51d653'
--            AND imputable=true AND cuenta_padre_id IS NULL) AS hojas_sueltas;  -- esperado: 1 (666666)
