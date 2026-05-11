-- ═══════════════════════════════════════════════════════════════════
-- 009_ajuste_inflacion_fase1.sql
-- Fase 1 del módulo de Ajuste por Inflación (RT 6 / Ley 27.430).
--
-- Cambios:
--   1) Agrega columna `es_ajustable` a cuentas_contables (default false).
--   2) Clasifica en bloque las cuentas no monetarias según el prefijo del
--      código del plan Vitalmet (114=Bs.Cambio, 122/123=Bs.Uso+Intangibles,
--      31=Patrimonio Neto, 4=Resultados).
--   3) Crea tabla `indices_ipc` para cargar el IPC INDEC mensual.
--   4) Crea cuenta 412004 RECPAM (Resultado por Exposición al Cambio en el
--      Poder Adquisitivo de la Moneda) si no existe.
--   5) Habilita RLS en `indices_ipc` aislando por empresa_id.
--
-- Idempotente: se puede correr más de una vez sin efectos colaterales.
-- ═══════════════════════════════════════════════════════════════════
--
-- INSTRUCCIONES:
-- Copiar todo el archivo y pegarlo en Supabase SQL Editor → Run.
-- El UUID de empresa (Vitalmet SA) ya viene hardcodeado más abajo.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1) ALTER cuentas_contables ───────────────────────────────────
ALTER TABLE cuentas_contables
  ADD COLUMN IF NOT EXISTS es_ajustable boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN cuentas_contables.es_ajustable IS
  'true = cuenta NO monetaria (se ajusta por inflación con índice IPC). false = cuenta monetaria (no se ajusta).';

-- ─── 2) CREATE indices_ipc ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS indices_ipc (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  anio         int  NOT NULL CHECK (anio BETWEEN 1990 AND 2100),
  mes          int  NOT NULL CHECK (mes BETWEEN 1 AND 12),
  indice       numeric(20, 4) NOT NULL CHECK (indice > 0),
  fuente       text DEFAULT 'INDEC',
  observaciones text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE(empresa_id, anio, mes)
);

CREATE INDEX IF NOT EXISTS idx_indices_ipc_empresa_periodo
  ON indices_ipc(empresa_id, anio DESC, mes DESC);

-- RLS por empresa_id (mismo patrón que el resto del proyecto)
ALTER TABLE indices_ipc ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS indices_ipc_select ON indices_ipc;
DROP POLICY IF EXISTS indices_ipc_insert ON indices_ipc;
DROP POLICY IF EXISTS indices_ipc_update ON indices_ipc;
DROP POLICY IF EXISTS indices_ipc_delete ON indices_ipc;

CREATE POLICY indices_ipc_select ON indices_ipc
  FOR SELECT USING (empresa_id = public.current_empresa_id());
CREATE POLICY indices_ipc_insert ON indices_ipc
  FOR INSERT WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY indices_ipc_update ON indices_ipc
  FOR UPDATE USING (empresa_id = public.current_empresa_id())
              WITH CHECK (empresa_id = public.current_empresa_id());
CREATE POLICY indices_ipc_delete ON indices_ipc
  FOR DELETE USING (empresa_id = public.current_empresa_id());

-- ─── 3) Clasificación + cuenta RECPAM (por empresa) ───────────────
DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  updated_count int;
  recpam_created boolean := false;
BEGIN

  -- 3.a) Marcar como no monetarias (es_ajustable=true) las cuentas que
  --      según RT 6 se reexpresan por inflación. Plan Vitalmet:
  --        114xxx  Bienes de Cambio
  --        122xxx  Bienes de Uso
  --        123xxx  Activos Intangibles  (no hay aún, queda preparado)
  --        31xxxx  Patrimonio Neto
  --        4xxxxx  Resultados (Ingresos y Egresos)
  UPDATE cuentas_contables
     SET es_ajustable = true
   WHERE empresa_id = emp_id
     AND (
       codigo LIKE '114%' OR
       codigo LIKE '122%' OR
       codigo LIKE '123%' OR
       codigo LIKE '31%'  OR
       codigo LIKE '4%'
     )
     AND es_ajustable = false;
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RAISE NOTICE 'Cuentas marcadas como no monetarias: %', updated_count;

  -- 3.b) Crear cuenta RECPAM si no existe.
  --      Código 412004 dentro del grupo de resultados financieros.
  IF NOT EXISTS (
    SELECT 1 FROM cuentas_contables
     WHERE empresa_id = emp_id AND codigo = '412004'
  ) THEN
    INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
    VALUES (emp_id, '412004', 'RECPAM (Result. Exp. Inflación)', 'ingreso', true, true, false);
    recpam_created := true;
  END IF;

  IF recpam_created THEN
    RAISE NOTICE 'Cuenta RECPAM 412004 creada';
  ELSE
    RAISE NOTICE 'Cuenta RECPAM 412004 ya existía, no se modifica';
  END IF;

  RAISE NOTICE 'Migration 009 completada para empresa %', emp_id;
END $$;
