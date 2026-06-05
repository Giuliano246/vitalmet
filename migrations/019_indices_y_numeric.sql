-- ═══════════════════════════════════════════════════════════════════
-- 019_indices_y_numeric.sql
-- Performance + correctitud de datos (postgres-patterns)
--   A) Convierte columnas de plata float8 → numeric (evita errores de redondeo)
--   B) Convierte cantidades físicas (kg/metros) float8 → numeric
--   C) Crea índices en empresa_id (filtro forzado por RLS) y en todas las FKs
--
-- Idempotente: se puede correr varias veces sin romper.
-- Saltea de forma segura tablas/columnas que no existan en este entorno.
-- Correr en Supabase SQL Editor (rol service). Testear y luego correr 020.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── A) Plata: float8 → numeric(14,2) ────────────────────────────────
-- Solo convierte si la columna existe Y hoy es double precision.
DO $$
DECLARE
  r record;
  money_cols text[][] := ARRAY[
    ['ordenes_produccion','precio_unitario'],
    ['productos_terminados','precio_unitario'],
    ['productos_terminados','costo_unitario'],
    ['venta_items','precio_unitario']
  ];
  i int;
BEGIN
  FOR i IN 1 .. array_length(money_cols, 1) LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name = money_cols[i][1]
        AND column_name = money_cols[i][2]
        AND data_type = 'double precision'
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ALTER COLUMN %I TYPE numeric(14,2) USING %I::numeric',
        money_cols[i][1], money_cols[i][2], money_cols[i][2]
      );
      RAISE NOTICE 'numeric(14,2): %.%', money_cols[i][1], money_cols[i][2];
    END IF;
  END LOOP;
END $$;

-- ─── B) Cantidades físicas: float8 → numeric(14,3) ──────────────────
DO $$
DECLARE
  qty_cols text[][] := ARRAY[
    ['barras','kg_disponibles'],
    ['barras','kg_minimo'],
    ['ordenes_produccion','kg_usados'],
    ['ordenes_produccion','merma_kg'],
    ['certificados','metros']
  ];
  i int;
BEGIN
  FOR i IN 1 .. array_length(qty_cols, 1) LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name = qty_cols[i][1]
        AND column_name = qty_cols[i][2]
        AND data_type = 'double precision'
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ALTER COLUMN %I TYPE numeric(14,3) USING %I::numeric',
        qty_cols[i][1], qty_cols[i][2], qty_cols[i][2]
      );
      RAISE NOTICE 'numeric(14,3): %.%', qty_cols[i][1], qty_cols[i][2];
    END IF;
  END LOOP;
END $$;

-- ─── C) Índices: empresa_id (RLS) + foreign keys ────────────────────
-- Cada índice se intenta por separado; si la tabla no existe, se saltea.
DO $$
DECLARE
  stmt text;
  stmts text[] := ARRAY[
    -- empresa_id (el filtro que RLS fuerza en CADA query) + listados por fecha
    'CREATE INDEX IF NOT EXISTS idx_certificados_empresa_fecha   ON public.certificados (empresa_id, fecha DESC)',
    'CREATE INDEX IF NOT EXISTS idx_barras_empresa               ON public.barras (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_op_empresa_fecha             ON public.ordenes_produccion (empresa_id, fecha DESC)',
    'CREATE INDEX IF NOT EXISTS idx_pt_empresa                   ON public.productos_terminados (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_ventas_empresa_fecha         ON public.ventas (empresa_id, fecha DESC)',
    'CREATE INDEX IF NOT EXISTS idx_materiales_empresa           ON public.materiales (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_tratamientos_empresa         ON public.tratamientos (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_permisos_usuario_empresa     ON public.permisos_usuario (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_clientes_empresa             ON public.clientes (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_vendedores_empresa           ON public.vendedores (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_listas_precios_empresa       ON public.listas_precios (empresa_id)',
    'CREATE INDEX IF NOT EXISTS idx_asientos_empresa_fecha       ON public.asientos_contables (empresa_id, fecha DESC)',
    -- foreign keys (clave para los EXISTS de las policies hijas y los joins de trazabilidad)
    'CREATE INDEX IF NOT EXISTS idx_barras_certificado           ON public.barras (certificado_id)',
    'CREATE INDEX IF NOT EXISTS idx_op_barra                     ON public.ordenes_produccion (barra_id)',
    'CREATE INDEX IF NOT EXISTS idx_pt_barra                     ON public.productos_terminados (barra_id)',
    'CREATE INDEX IF NOT EXISTS idx_pt_orden                     ON public.productos_terminados (orden_id)',
    'CREATE INDEX IF NOT EXISTS idx_ventas_lista_precios         ON public.ventas (lista_precios_id)',
    'CREATE INDEX IF NOT EXISTS idx_ventas_vendedor              ON public.ventas (vendedor_id)',
    'CREATE INDEX IF NOT EXISTS idx_venta_items_venta            ON public.venta_items (venta_id)',
    'CREATE INDEX IF NOT EXISTS idx_venta_items_producto         ON public.venta_items (producto_id)',
    'CREATE INDEX IF NOT EXISTS idx_tratamientos_orden           ON public.tratamientos (orden_id)',
    'CREATE INDEX IF NOT EXISTS idx_permisos_usuario_usuario     ON public.permisos_usuario (usuario_id)',
    'CREATE INDEX IF NOT EXISTS idx_clientes_lista_precios       ON public.clientes (lista_precios_id)',
    'CREATE INDEX IF NOT EXISTS idx_asientos_venta               ON public.asientos_contables (venta_id)'
  ];
BEGIN
  FOREACH stmt IN ARRAY stmts LOOP
    BEGIN
      EXECUTE stmt;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'tabla inexistente, índice salteado: %', stmt;
      WHEN undefined_column THEN
        RAISE NOTICE 'columna inexistente, índice salteado: %', stmt;
    END;
  END LOOP;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (opcional): FKs que todavía quedaran sin índice
-- ═══════════════════════════════════════════════════════════════════
-- SELECT conrelid::regclass AS tabla, a.attname AS columna_fk
-- FROM pg_constraint c
-- JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
-- WHERE c.contype = 'f'
--   AND NOT EXISTS (SELECT 1 FROM pg_index i
--                   WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey))
-- ORDER BY tabla;
