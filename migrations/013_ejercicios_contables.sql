-- ═══════════════════════════════════════════════════════════════════
-- 013_ejercicios_contables.sql
-- Soporte para "Cierre y apertura" estilo Tango:
--   1) Tabla ejercicios con estado (abierto/cerrado) y refs a los 4
--      asientos que se generan al cerrar.
--   2) Cuenta puente 314003 "Cierre de Ejercicio" (tipo patrimonio).
--   3) RLS por empresa_id usando public.current_empresa_id().
--
-- Habilita:
--   - Cierre completo en 4 pasos (refundición + pasaje + cierre patr.
--     + apertura siguiente ejercicio)
--   - Bloqueo automático de asientos con fecha en ejercicio cerrado
--   - Reversión / Eliminación de un cierre
--
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Tabla ejercicios
CREATE TABLE IF NOT EXISTS ejercicios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  numero int NOT NULL,                                       -- 1, 2, 3...
  fecha_inicio date NOT NULL,
  fecha_fin date NOT NULL,
  estado text NOT NULL DEFAULT 'abierto'
    CHECK (estado IN ('abierto','cerrado')),
  fecha_cierre_efectivo timestamptz,                         -- cuándo se ejecutó el cierre
  -- referencias a los 4 asientos generados (todos opcionales, según qué se ejecutó)
  asiento_refundicion_id uuid REFERENCES asientos(id) ON DELETE SET NULL,
  asiento_pasaje_id uuid REFERENCES asientos(id) ON DELETE SET NULL,
  asiento_cierre_patrimonial_id uuid REFERENCES asientos(id) ON DELETE SET NULL,
  asiento_apertura_id uuid REFERENCES asientos(id) ON DELETE SET NULL,
  observaciones text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ejercicios_fechas_chk CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT ejercicios_empresa_numero_uq UNIQUE (empresa_id, numero),
  CONSTRAINT ejercicios_empresa_rango_uq UNIQUE (empresa_id, fecha_inicio, fecha_fin)
);

CREATE INDEX IF NOT EXISTS ejercicios_empresa_idx ON ejercicios(empresa_id);
CREATE INDEX IF NOT EXISTS ejercicios_empresa_estado_idx ON ejercicios(empresa_id, estado);
CREATE INDEX IF NOT EXISTS ejercicios_fechas_idx ON ejercicios(empresa_id, fecha_inicio, fecha_fin);

-- 2. RLS
ALTER TABLE ejercicios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ejercicios_select ON ejercicios;
DROP POLICY IF EXISTS ejercicios_insert ON ejercicios;
DROP POLICY IF EXISTS ejercicios_update ON ejercicios;
DROP POLICY IF EXISTS ejercicios_delete ON ejercicios;

CREATE POLICY ejercicios_select ON ejercicios
  FOR SELECT USING (empresa_id = public.current_empresa_id());
CREATE POLICY ejercicios_insert ON ejercicios
  FOR INSERT WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY ejercicios_update ON ejercicios
  FOR UPDATE USING (empresa_id = public.current_empresa_id())
              WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY ejercicios_delete ON ejercicios
  FOR DELETE USING (empresa_id = public.current_empresa_id());

-- 3. Cuenta puente para cierre patrimonial
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  creadas int := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cuentas_contables
     WHERE empresa_id = emp_id AND codigo = '314003'
  ) THEN
    INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
    VALUES (emp_id, '314003', 'Cierre de Ejercicio', 'patrimonio', true, true, false);
    creadas := creadas + 1;
  END IF;

  RAISE NOTICE 'Migration 013: % cuenta(s) creada(s), tabla ejercicios lista', creadas;
END $$;
