-- ═══════════════════════════════════════════════════════════════════
-- 034_correlatividad.sql
-- Unicidad de nº de OC + vista que detecta huecos y duplicados en
-- numeraciones correlativas (foco: asientos.numero).
--
-- Qué hace:
--   1. UNIQUE index en ordenes_compra (empresa_id, nro): impide dos OC
--      con el mismo número dentro de la misma empresa.
--   2. Vista v_correlatividad: expone DUPLICADOS y HUECOS en la
--      secuencia de asientos.numero por empresa. Útil para auditoría
--      contable y como señal temprana de problemas de correlatividad.
--
-- AVISO — índice único en OC:
--   Si ya existen filas con (empresa_id, nro) duplicados en la tabla
--   ordenes_compra, el CREATE UNIQUE INDEX fallará. Correr PRIMERO la
--   siguiente consulta para detectar duplicados:
--
--   SELECT empresa_id, nro, count(*)
--   FROM ordenes_compra
--   GROUP BY 1, 2
--   HAVING count(*) > 1;
--
--   Si devuelve filas: resolver manualmente (borrar/renumerar los
--   duplicados) y recién entonces aplicar esta migración.
--
-- Seguridad RLS:
--   La vista declara security_invoker = true para que la RLS de las
--   tablas base (asientos) se aplique con el rol del usuario que
--   consulta (no el del owner de la vista). Supabase PG17 soporta
--   este atributo. Sin esto, PostgREST expondría asientos de todas
--   las empresas a cualquier usuario autenticado.
--
-- Idempotente. Seguro de re-correr.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Unicidad de número de OC por empresa ─────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_oc_nro_empresa
  ON public.ordenes_compra (empresa_id, nro);

-- ─── 2. Vista de correlatividad: duplicados y huecos en asientos ─────
-- asientos.numero es int (asignado por fn_asiento_numero como
-- COALESCE(MAX(numero),0)+1). Se castea a bigint para generate_series.
CREATE OR REPLACE VIEW public.v_correlatividad
  WITH (security_invoker = true)
AS
WITH asientos_num AS (
  SELECT empresa_id, numero::bigint AS n
  FROM public.asientos
  WHERE numero IS NOT NULL
)
-- Duplicados: mismo numero más de una vez dentro de la empresa
SELECT
  'asiento'::text    AS doc,
  'duplicado'::text  AS tipo,
  empresa_id,
  n::text            AS valor
FROM asientos_num
GROUP BY empresa_id, n
HAVING count(*) > 1

UNION ALL

-- Huecos: números enteros entre min y max que no existen
SELECT
  'asiento'::text   AS doc,
  'hueco'::text     AS tipo,
  a.empresa_id,
  g.n::text         AS valor
FROM (
  SELECT empresa_id, min(n) AS lo, max(n) AS hi
  FROM asientos_num
  GROUP BY empresa_id
) a
-- Bound de seguridad: si el rango fuera anómalo (ej. un numero manual
-- gigante), no expandir millones de filas en generate_series.
CROSS JOIN LATERAL generate_series(a.lo, LEAST(a.hi, a.lo + 100000)) AS g(n)
WHERE NOT EXISTS (
  SELECT 1 FROM asientos_num x
  WHERE x.empresa_id = a.empresa_id AND x.n = g.n
);

-- PostgREST expone las vistas públicas a anon por default; revocar.
-- security_invoker=true ya aplica la RLS de asientos al consultante.
REVOKE SELECT ON public.v_correlatividad FROM anon;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- Confirmar índice creado:
-- SELECT indexname FROM pg_indexes
-- WHERE schemaname='public' AND tablename='ordenes_compra'
--   AND indexname='uq_oc_nro_empresa';

-- Confirmar vista con security_invoker:
-- SELECT relname, reloptions FROM pg_class c
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- WHERE n.nspname='public' AND c.relkind='v' AND relname='v_correlatividad';
-- (reloptions debe contener "security_invoker=true")

-- Inspeccionar correlatividad real:
-- SELECT * FROM v_correlatividad ORDER BY doc, tipo, valor;
