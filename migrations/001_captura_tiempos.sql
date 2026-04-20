-- ═══════════════════════════════════════════════════════════
-- Migración 001 — Captura de tiempos de producción
-- Agrega el desglose de OPs en pasos + time entries (start/stop)
-- Ejecutar una vez en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- Pasos/operaciones dentro de una OP (torno → fresadora → control, etc.)
CREATE TABLE IF NOT EXISTS op_operaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  orden_id uuid NOT NULL REFERENCES ordenes_produccion(id) ON DELETE CASCADE,
  secuencia int NOT NULL,
  nombre text NOT NULL,
  maquina text,
  operario_id uuid REFERENCES usuarios(id),
  tiempo_estimado_min int DEFAULT 0,
  tarifa_maquina_usd numeric DEFAULT 0,
  estado text DEFAULT 'pendiente',           -- pendiente | en_curso | completada
  created_at timestamptz DEFAULT now()
);

-- Registros de tiempo (cada arranque/parada genera uno)
CREATE TABLE IF NOT EXISTS op_time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  operacion_id uuid NOT NULL REFERENCES op_operaciones(id) ON DELETE CASCADE,
  operario_id uuid REFERENCES usuarios(id),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,                      -- null = timer activo
  tipo text NOT NULL DEFAULT 'productivo',   -- productivo | pausa
  motivo text,                               -- solo si tipo='pausa'
  created_at timestamptz DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_op_operaciones_orden ON op_operaciones (orden_id);
CREATE INDEX IF NOT EXISTS idx_op_time_entries_operacion ON op_time_entries (operacion_id);
CREATE INDEX IF NOT EXISTS idx_op_time_entries_activo ON op_time_entries (operario_id) WHERE ended_at IS NULL;

-- Vista de métricas agregadas por operación
CREATE OR REPLACE VIEW op_metricas AS
SELECT
  o.id AS operacion_id,
  o.orden_id,
  o.nombre,
  o.tiempo_estimado_min,
  o.estado,
  COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(e.ended_at, now()) - e.started_at))/60)
    FILTER (WHERE e.tipo = 'productivo'), 0)::int AS minutos_productivos,
  COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(e.ended_at, now()) - e.started_at))/60)
    FILTER (WHERE e.tipo = 'pausa'), 0)::int AS minutos_pausa
FROM op_operaciones o
LEFT JOIN op_time_entries e ON e.operacion_id = o.id
GROUP BY o.id;

-- NOTA: RLS queda desactivado igual que el resto del sistema (pendiente de resolver).
-- Cuando se active, usar policies similares a las de ordenes_produccion.
