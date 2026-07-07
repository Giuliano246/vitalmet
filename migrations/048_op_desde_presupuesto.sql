-- 048_op_desde_presupuesto.sql — Vínculo presupuesto → OP (Paquete 1B)
-- Permite generar una orden de producción desde un presupuesto aprobado
-- y mantener la trazabilidad presupuesto → OP → PT → venta.
BEGIN;

ALTER TABLE ordenes_produccion ADD COLUMN IF NOT EXISTS presupuesto_id uuid REFERENCES presupuestos(id);
CREATE INDEX IF NOT EXISTS ix_ordenes_produccion_presupuesto ON ordenes_produccion(presupuesto_id);

COMMIT;

-- Verificación:
-- SELECT column_name FROM information_schema.columns WHERE table_name='ordenes_produccion' AND column_name='presupuesto_id';
