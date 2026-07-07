-- 047_multi_timer.sql — Multi-timer simultáneo (Paquete 1A)
-- Garantiza a lo sumo UNA entrada abierta de cada tipo (productivo/pausa)
-- por operación. Habilita timers paralelos entre operaciones con integridad.
BEGIN;

-- Higiene previa: si quedó más de una entrada abierta del mismo tipo para
-- la misma operación (bug histórico o carrera), cerrar todas menos la más nueva.
WITH dup AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY operacion_id, tipo ORDER BY started_at DESC
  ) AS rn
  FROM op_time_entries WHERE ended_at IS NULL
)
UPDATE op_time_entries e SET ended_at = now()
FROM dup WHERE e.id = dup.id AND dup.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_op_time_entries_abierta
  ON op_time_entries(operacion_id, tipo) WHERE ended_at IS NULL;

COMMIT;

-- Verificación:
-- SELECT indexname FROM pg_indexes WHERE tablename='op_time_entries' AND indexname='ux_op_time_entries_abierta';
-- SELECT operacion_id, tipo, count(*) FROM op_time_entries WHERE ended_at IS NULL GROUP BY 1,2 HAVING count(*)>1;  -- debe dar 0 filas
