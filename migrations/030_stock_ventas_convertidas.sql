-- ═══════════════════════════════════════════════════════════════════
-- 030_stock_ventas_convertidas.sql
-- Bug de inventario: las ventas nacidas de convertir_presupuesto NUNCA
-- descontaban stock de PT:
--   · la conversión no descuenta (correcto: la venta nace pendiente,
--     las piezas pueden no estar fabricadas aún)
--   · el select de estado (cambiarEstado) hace un PATCH pelado → no
--     descuenta al pasar a 'entregado'
--   · editar la venta tampoco lo arregla: guardar_venta devuelve el
--     stock "viejo" (que nunca se sacó → fantasma +N) y descuenta el
--     nuevo (−N) → neto 0
--   · y anular_venta reponía stock que nunca se descontó → stock
--     fantasma permanente
--
-- Fix: flag ventas.stock_descontado ("el stock de los venta_items
-- actuales ya está aplicado"):
--   · DEFAULT true  → semántica de guardar_venta (descuenta al guardar)
--   · convertir_presupuesto lo deja en false
--   · trigger al pasar a 'entregado' con flag false: descuenta atómico
--     (falla con mensaje claro si no alcanza) y prende el flag
--   · guardar_venta solo devuelve stock viejo si estaba descontado, y
--     deja el flag en true
--   · anular_venta solo repone si estaba descontado
--
-- Prod tiene 0 ventas hoy → sin backfill. Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Flag ─────────────────────────────────────────────────────────
ALTER TABLE ventas ADD COLUMN IF NOT EXISTS stock_descontado boolean NOT NULL DEFAULT true;

-- ─── 2. Trigger: descuento al entregar (solo si está pendiente de descontar)
CREATE OR REPLACE FUNCTION public.fn_venta_entrega_stock() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE r record; v_pieza text;
BEGIN
  IF NEW.estado = 'entregado' AND OLD.estado IS DISTINCT FROM 'entregado'
     AND NOT NEW.stock_descontado THEN
    FOR r IN SELECT producto_id, cantidad FROM venta_items
             WHERE venta_id = NEW.id AND producto_id IS NOT NULL LOOP
      UPDATE productos_terminados SET cantidad = cantidad - r.cantidad
       WHERE id = r.producto_id AND cantidad >= r.cantidad;
      IF NOT FOUND THEN
        SELECT pieza INTO v_pieza FROM productos_terminados WHERE id = r.producto_id;
        RAISE EXCEPTION 'Stock insuficiente para entregar: %', COALESCE(v_pieza, 'producto');
      END IF;
    END LOOP;
    NEW.stock_descontado := true;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_venta_entrega_stock ON ventas;
CREATE TRIGGER trg_venta_entrega_stock BEFORE UPDATE ON ventas
  FOR EACH ROW EXECUTE FUNCTION public.fn_venta_entrega_stock();

-- ─── 3. guardar_venta: retorno de stock viejo SOLO si estaba descontado;
--        el flag queda en true (la función siempre descuenta los items nuevos)
CREATE OR REPLACE FUNCTION public.guardar_venta(p_venta jsonb, p_items jsonb, p_venta_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; v_cliente_id uuid;
  it jsonb; r record; v_pieza text; v_cant int;
  v_descontado boolean;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_venta->>'nro_remito','') = '' OR COALESCE(p_venta->>'cliente','') = '' THEN
    RAISE EXCEPTION 'Completá nro de pedido y razón social';
  END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_items,'[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'Agregá al menos un ítem';
  END IF;

  v_cliente_id := public.upsert_cliente(p_venta->>'cliente', p_venta->>'cuit');

  IF p_venta_id IS NOT NULL THEN
    SELECT stock_descontado INTO v_descontado
    FROM ventas WHERE id = p_venta_id AND empresa_id = emp;
    IF v_descontado IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
    -- Edición: devolver el stock de los items viejos (solo si se había
    -- descontado — una venta convertida pendiente nunca lo descontó)
    IF v_descontado THEN
      FOR r IN SELECT producto_id, cantidad FROM venta_items
               WHERE venta_id = p_venta_id AND producto_id IS NOT NULL LOOP
        UPDATE productos_terminados SET cantidad = cantidad + r.cantidad WHERE id = r.producto_id;
      END LOOP;
    END IF;
    DELETE FROM venta_items WHERE venta_id = p_venta_id;
    UPDATE ventas SET
      nro_remito = p_venta->>'nro_remito',
      nro_pedido = p_venta->>'nro_remito',
      cliente = p_venta->>'cliente',
      cliente_id = v_cliente_id,
      fecha = NULLIF(p_venta->>'fecha','')::date,
      condicion_pago = p_venta->>'condicion_pago',
      estado = COALESCE(NULLIF(p_venta->>'estado',''), 'pendiente'),
      estado_pedido = COALESCE(NULLIF(p_venta->>'estado',''), 'pendiente'),
      fecha_entrega_desde = NULLIF(p_venta->>'fecha_entrega_desde','')::date,
      fecha_entrega_hasta = NULLIF(p_venta->>'fecha_entrega_hasta','')::date,
      total = COALESCE((p_venta->>'total')::numeric, 0),
      bonif_pct_1 = COALESCE((p_venta->>'bonif_pct_1')::numeric, 0),
      lista_precios_id = NULLIF(p_venta->>'lista_precios_id','')::uuid,
      grupo_bonificacion = p_venta->>'grupo_bonificacion',
      vendedor_id = NULLIF(p_venta->>'vendedor_id','')::uuid,
      observaciones = p_venta->>'observaciones',
      stock_descontado = true,
      updated_at = now()
    WHERE id = p_venta_id AND empresa_id = emp
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
  ELSE
    INSERT INTO ventas (empresa_id, nro_remito, nro_pedido, cliente, cliente_id, fecha,
                        condicion_pago, estado, estado_pedido,
                        coef_registracion_moneda, coef_emision_moneda, coef_deuda_moneda,
                        fecha_entrega_desde, fecha_entrega_hasta, total, bonif_pct_1,
                        lista_precios_id, grupo_bonificacion, vendedor_id, observaciones,
                        stock_descontado)
    VALUES (emp, p_venta->>'nro_remito', p_venta->>'nro_remito', p_venta->>'cliente',
            v_cliente_id, NULLIF(p_venta->>'fecha','')::date,
            p_venta->>'condicion_pago',
            COALESCE(NULLIF(p_venta->>'estado',''), 'pendiente'),
            COALESCE(NULLIF(p_venta->>'estado',''), 'pendiente'),
            'USD', 'USD', 'USD',
            NULLIF(p_venta->>'fecha_entrega_desde','')::date,
            NULLIF(p_venta->>'fecha_entrega_hasta','')::date,
            COALESCE((p_venta->>'total')::numeric, 0),
            COALESCE((p_venta->>'bonif_pct_1')::numeric, 0),
            NULLIF(p_venta->>'lista_precios_id','')::uuid,
            p_venta->>'grupo_bonificacion',
            NULLIF(p_venta->>'vendedor_id','')::uuid,
            p_venta->>'observaciones',
            true)
    RETURNING id INTO v_id;
  END IF;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF COALESCE(it->>'producto_id','') = '' THEN RAISE EXCEPTION 'Ítem sin producto'; END IF;
    v_cant := COALESCE((it->>'cantidad')::int, 0);
    IF v_cant <= 0 THEN RAISE EXCEPTION 'Cantidad inválida en un ítem'; END IF;
    -- Descuento atómico: solo descuenta si alcanza el stock AHORA
    v_pieza := NULL;
    UPDATE productos_terminados
    SET cantidad = cantidad - v_cant
    WHERE id = (it->>'producto_id')::uuid AND empresa_id = emp AND cantidad >= v_cant
    RETURNING pieza INTO v_pieza;
    IF NOT FOUND THEN
      SELECT pieza INTO v_pieza FROM productos_terminados WHERE id = (it->>'producto_id')::uuid;
      RAISE EXCEPTION 'Stock insuficiente: %', COALESCE(v_pieza, 'producto');
    END IF;
    INSERT INTO venta_items (venta_id, producto_id, pieza, cantidad, precio_unitario,
                             tipo_cambio, total, bonif_1)
    VALUES (v_id, (it->>'producto_id')::uuid, v_pieza, v_cant,
            COALESCE((it->>'precio_unitario')::numeric, 0), 1,
            COALESCE((it->>'total')::numeric, 0),
            COALESCE((it->>'bonif_1')::numeric, 0));
  END LOOP;

  RETURN jsonb_build_object('id', v_id);
END $$;

-- ─── 4. anular_venta: repone stock SOLO si estaba descontado ─────────
CREATE OR REPLACE FUNCTION public.anular_venta(p_venta_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v record; r record;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO v FROM ventas WHERE id = p_venta_id AND empresa_id = emp;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
  IF v.factura_emitida_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede anular: la venta tiene factura emitida (CAE en AFIP). Corresponde Nota de Crédito.';
  END IF;
  IF v.stock_descontado THEN
    FOR r IN SELECT producto_id, cantidad FROM venta_items
             WHERE venta_id = p_venta_id AND producto_id IS NOT NULL LOOP
      UPDATE productos_terminados SET cantidad = cantidad + r.cantidad WHERE id = r.producto_id;
    END LOOP;
  END IF;
  UPDATE asientos SET estado = 'anulado'
  WHERE empresa_id = emp AND origen_tipo = 'venta' AND origen_id = p_venta_id;
  UPDATE presupuestos SET venta_id = NULL, estado = 'aprobado'
  WHERE empresa_id = emp AND venta_id = p_venta_id;
  DELETE FROM venta_items WHERE venta_id = p_venta_id;
  DELETE FROM ventas WHERE id = p_venta_id;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ─── 5. convertir_presupuesto: la venta nace con el flag apagado ─────
CREATE OR REPLACE FUNCTION public.convertir_presupuesto(p_presupuesto_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  p record; v_id uuid; v_cliente_id uuid; n int; v_nro text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO p FROM presupuestos WHERE id = p_presupuesto_id AND empresa_id = emp;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Presupuesto no encontrado'; END IF;
  IF p.estado = 'convertido' THEN RAISE EXCEPTION 'Este presupuesto ya fue convertido'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ventas_nro:' || emp::text, 0));
  SELECT COALESCE(MAX((substring(nro_remito FROM '^V-(\d+)$'))::int), 0) + 1 INTO n
  FROM ventas WHERE empresa_id = emp AND nro_remito ~ '^V-\d+$';
  v_nro := 'V-' || lpad(n::text, 5, '0');

  v_cliente_id := public.upsert_cliente(p.cliente, p.cuit);

  INSERT INTO ventas (empresa_id, nro_remito, nro_pedido, cliente, cliente_id, fecha,
                      estado, estado_pedido, condicion_pago, fecha_entrega_hasta,
                      coef_registracion_moneda, coef_emision_moneda, coef_deuda_moneda,
                      observaciones, total, stock_descontado)
  VALUES (emp, v_nro, v_nro, p.cliente, v_cliente_id, current_date,
          'pendiente', 'pendiente', p.condicion_pago, p.fecha_vencimiento,
          'USD', 'USD', 'USD',
          'Generada desde presupuesto ' || p.nro ||
            COALESCE(' — ' || NULLIF(p.observaciones,''), ''),
          COALESCE(p.total, 0),
          false)  -- el stock se descuenta recién al pasar a 'entregado' (trigger)
  RETURNING id INTO v_id;

  INSERT INTO venta_items (venta_id, producto_id, pieza, cantidad, precio_unitario, total)
  SELECT v_id, pi.producto_id, pi.pieza, round(COALESCE(pi.cantidad,0))::int,
         COALESCE(pi.precio_unitario,0), COALESCE(pi.subtotal,0)
  FROM presupuesto_items pi WHERE pi.presupuesto_id = p_presupuesto_id;

  UPDATE presupuestos SET estado = 'convertido', venta_id = v_id WHERE id = p_presupuesto_id;

  RETURN jsonb_build_object('id', v_id, 'nro', v_nro);
END $$;

COMMIT;

-- CREATE OR REPLACE conserva los GRANT/REVOKE de la 023 (authenticated
-- sí, anon no) — no hace falta repetirlos.

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT (SELECT count(*) FROM information_schema.columns
--          WHERE table_name='ventas' AND column_name='stock_descontado') AS col,
--        (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
--          WHERE c.relname='ventas' AND t.tgname='trg_venta_entrega_stock') AS trigger;
