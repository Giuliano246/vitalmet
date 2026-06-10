-- ═══════════════════════════════════════════════════════════════════
-- 024_ctacte.sql
-- Cuenta corriente de clientes (fase 3, mes 1 — roadmap auditoría)
--
-- Qué agrega:
--   1. asientos.cliente_id / asientos.proveedor_id: los cobros y pagos
--      quedan vinculados al cliente/proveedor real (hasta ahora el
--      tercero era texto libre dentro de la descripción).
--   2. Backfill: los cobros/pagos históricos se vinculan matcheando
--      "Cobro de <nombre>" / "Pago a <nombre>" contra clientes y
--      proveedores (ante duplicados gana el más antiguo).
--   3. crear_asiento acepta cliente_id/proveedor_id en p_cabecera
--      (misma firma, CREATE OR REPLACE — el frontend viejo no se entera).
--
-- La cuenta corriente se calcula en el frontend: cargos = ventas
-- entregadas/facturadas, pagos = asientos auto-cobranza confirmados del
-- cliente, imputación FIFO, aging por vencimiento (condicion_pago).
--
-- RETROCOMPATIBLE e idempotente. Correr ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Vínculo real de cobros/pagos ─────────────────────────────────
ALTER TABLE asientos ADD COLUMN IF NOT EXISTS cliente_id uuid REFERENCES clientes(id) ON DELETE SET NULL;
ALTER TABLE asientos ADD COLUMN IF NOT EXISTS proveedor_id uuid REFERENCES proveedores(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_asientos_cliente   ON asientos (cliente_id)   WHERE cliente_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_asientos_proveedor ON asientos (proveedor_id) WHERE proveedor_id IS NOT NULL;

-- ─── 2. Backfill de movimientos históricos ───────────────────────────
UPDATE asientos a SET cliente_id = c.id
FROM (
  SELECT DISTINCT ON (empresa_id, lower(nombre)) id, empresa_id, lower(nombre) AS ln
  FROM clientes ORDER BY empresa_id, lower(nombre), created_at
) c
WHERE a.tipo = 'auto-cobranza' AND a.cliente_id IS NULL
  AND a.empresa_id = c.empresa_id
  AND lower(a.descripcion) LIKE 'cobro de ' || c.ln || '%';

UPDATE asientos a SET proveedor_id = p.id
FROM (
  SELECT DISTINCT ON (empresa_id, lower(nombre)) id, empresa_id, lower(nombre) AS ln
  FROM proveedores ORDER BY empresa_id, lower(nombre), created_at
) p
WHERE a.tipo = 'auto-pago' AND a.proveedor_id IS NULL
  AND a.empresa_id = p.empresa_id
  AND lower(a.descripcion) LIKE 'pago a ' || p.ln || '%';

-- ─── 3. crear_asiento: persistir cliente_id / proveedor_id ───────────
-- Idéntica a la de 023 salvo las dos columnas nuevas. Misma firma.
CREATE OR REPLACE FUNCTION public.crear_asiento(p_cabecera jsonb, p_lineas jsonb, p_asiento_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; v_num int;
  v_estado text := COALESCE(p_cabecera->>'estado', 'borrador');
  l jsonb; d numeric; h numeric; td numeric := 0; th numeric := 0;
  cnt int := COALESCE(jsonb_array_length(COALESCE(p_lineas, '[]'::jsonb)), 0);
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_cabecera->>'fecha','') = '' OR COALESCE(p_cabecera->>'descripcion','') = '' THEN
    RAISE EXCEPTION 'Fecha y descripción son obligatorias';
  END IF;
  FOR l IN SELECT * FROM jsonb_array_elements(COALESCE(p_lineas, '[]'::jsonb)) LOOP
    IF COALESCE(l->>'cuenta_id','') = '' THEN RAISE EXCEPTION 'Cada línea debe tener una cuenta'; END IF;
    d := COALESCE((l->>'debe')::numeric, 0);
    h := COALESCE((l->>'haber')::numeric, 0);
    IF d < 0 OR h < 0 OR (d > 0 AND h > 0) OR (d = 0 AND h = 0) THEN
      RAISE EXCEPTION 'Línea inválida: Debe o Haber > 0, nunca ambos';
    END IF;
    td := td + d; th := th + h;
  END LOOP;
  IF cnt > 0 AND abs(td - th) >= 0.01 THEN
    RAISE EXCEPTION 'Asiento desbalanceado: Debe % ≠ Haber %', td, th;
  END IF;
  IF v_estado = 'confirmado' AND cnt < 2 THEN
    RAISE EXCEPTION 'Un asiento confirmado requiere al menos 2 líneas';
  END IF;

  IF p_asiento_id IS NOT NULL THEN
    UPDATE asientos SET
      numero          = COALESCE((p_cabecera->>'numero')::int, numero),
      fecha           = (p_cabecera->>'fecha')::date,
      descripcion     = p_cabecera->>'descripcion',
      comprobante_nro = p_cabecera->>'comprobante_nro',
      estado          = v_estado,
      tipo            = COALESCE(p_cabecera->>'tipo', tipo),
      origen_tipo     = COALESCE(p_cabecera->>'origen_tipo', origen_tipo),
      origen_id       = COALESCE((p_cabecera->>'origen_id')::uuid, origen_id),
      moneda          = COALESCE(p_cabecera->>'moneda', moneda),
      tipo_cambio     = (p_cabecera->>'tipo_cambio')::numeric,
      tc_tipo         = p_cabecera->>'tc_tipo',
      cliente_id      = COALESCE(NULLIF(p_cabecera->>'cliente_id','')::uuid, cliente_id),
      proveedor_id    = COALESCE(NULLIF(p_cabecera->>'proveedor_id','')::uuid, proveedor_id),
      updated_at      = now()
    WHERE id = p_asiento_id AND empresa_id = emp
    RETURNING id, numero INTO v_id, v_num;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Asiento no encontrado'; END IF;
    DELETE FROM asiento_lineas WHERE asiento_id = v_id;
  ELSE
    INSERT INTO asientos (empresa_id, numero, fecha, descripcion, comprobante_nro,
                          estado, tipo, origen_tipo, origen_id, moneda, tipo_cambio, tc_tipo,
                          cliente_id, proveedor_id)
    VALUES (emp,
            (p_cabecera->>'numero')::int,
            (p_cabecera->>'fecha')::date,
            p_cabecera->>'descripcion',
            p_cabecera->>'comprobante_nro',
            v_estado,
            p_cabecera->>'tipo',
            p_cabecera->>'origen_tipo',
            (p_cabecera->>'origen_id')::uuid,
            COALESCE(p_cabecera->>'moneda', 'ARS'),
            (p_cabecera->>'tipo_cambio')::numeric,
            p_cabecera->>'tc_tipo',
            NULLIF(p_cabecera->>'cliente_id','')::uuid,
            NULLIF(p_cabecera->>'proveedor_id','')::uuid)
    RETURNING id, numero INTO v_id, v_num;
  END IF;

  INSERT INTO asiento_lineas (asiento_id, cuenta_id, debe, haber, descripcion, orden)
  SELECT v_id,
         (t.l->>'cuenta_id')::uuid,
         COALESCE((t.l->>'debe')::numeric, 0),
         COALESCE((t.l->>'haber')::numeric, 0),
         t.l->>'descripcion',
         COALESCE((t.l->>'orden')::int, t.ord::int - 1)
  FROM jsonb_array_elements(COALESCE(p_lineas, '[]'::jsonb)) WITH ORDINALITY AS t(l, ord);

  RETURN jsonb_build_object('id', v_id, 'numero', v_num);
END $$;
REVOKE ALL ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT count(*) FILTER (WHERE cliente_id IS NOT NULL) AS cobros_vinculados,
--        count(*) FILTER (WHERE tipo='auto-cobranza') AS cobros_total
-- FROM asientos;
