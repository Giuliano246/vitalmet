-- ═══════════════════════════════════════════════════════════════════
-- 023_integridad.sql
-- Integridad transaccional (fase 2 de la auditoría 2026-06-09)
--
-- Qué arregla:
--   1. Stock negativo imposible: CHECK en barras.kg_disponibles y
--      productos_terminados.cantidad. Hoy el cliente calcula el nuevo
--      valor con datos viejos (lost update) y hace PATCH absoluto.
--   2. Partida doble garantizada por la DB: trigger diferido que valida
--      Debe = Haber de todo asiento confirmado al commit. Un bug del
--      frontend ya no puede dejar la contabilidad desbalanceada.
--   3. Numeración de asientos en la DB (asignada bajo lock cuando el
--      INSERT no trae numero). Elimina la carrera del maxN+1 del cliente.
--   4. Ventas con CAE intocables: no se pueden borrar ni cambiar de
--      monto/cliente mientras tengan factura emitida (AFIP ya la tiene).
--   5. ventas.cliente_id: FK real a clientes (backfill por nombre).
--   6. RPCs atómicas: guardar_venta, anular_venta, convertir_presupuesto,
--      crear_asiento, consumir_barra. Una operación = una transacción.
--      Se acabó el "guardó la venta pero falló el descuento de stock".
--   7. audit_log: quién tocó qué y cuándo en las tablas críticas.
--
-- Verificado contra producción (2026-06-09): 0 filas violan los CHECKs,
-- 0 asientos confirmados desbalanceados, 0 ventas con factura emitida,
-- ya existen UNIQUE(empresa_id, numero/nro_remito/nro/lote).
--
-- RETROCOMPATIBLE: el frontend viejo sigue funcionando después de correr
-- esto (los flujos actuales insertan lotes balanceados y nunca calculan
-- stock negativo). Las RPCs quedan disponibles para el deploy siguiente.
--
-- Idempotente. Seguro de re-correr.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Stock nunca negativo ─────────────────────────────────────────
ALTER TABLE barras DROP CONSTRAINT IF EXISTS barras_kg_no_negativo;
ALTER TABLE barras ADD CONSTRAINT barras_kg_no_negativo
  CHECK (kg_disponibles >= 0);

ALTER TABLE productos_terminados DROP CONSTRAINT IF EXISTS pt_cantidad_no_negativa;
ALTER TABLE productos_terminados ADD CONSTRAINT pt_cantidad_no_negativa
  CHECK (cantidad >= 0);

-- Líneas contables: montos no negativos, nunca Debe y Haber a la vez,
-- y siempre colgadas de un asiento.
ALTER TABLE asiento_lineas DROP CONSTRAINT IF EXISTS lineas_montos_validos;
ALTER TABLE asiento_lineas ADD CONSTRAINT lineas_montos_validos
  CHECK (COALESCE(debe,0) >= 0 AND COALESCE(haber,0) >= 0
         AND NOT (COALESCE(debe,0) > 0 AND COALESCE(haber,0) > 0));
ALTER TABLE asiento_lineas ALTER COLUMN asiento_id SET NOT NULL;

-- ─── 2. Numeración de asientos en la DB ──────────────────────────────
-- Si el INSERT no trae numero (NULL), se asigna max+1 de la empresa bajo
-- advisory lock. El frontend viejo sigue mandando su numero (la UNIQUE
-- existente ataja la carrera); el nuevo manda NULL y deja que la DB numere.
CREATE OR REPLACE FUNCTION public.fn_asiento_numero() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.numero IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('asientos_numero:' || NEW.empresa_id::text, 0));
    SELECT COALESCE(MAX(numero), 0) + 1 INTO NEW.numero
    FROM asientos WHERE empresa_id = NEW.empresa_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_asiento_numero ON asientos;
CREATE TRIGGER trg_asiento_numero
  BEFORE INSERT ON asientos
  FOR EACH ROW EXECUTE FUNCTION public.fn_asiento_numero();

-- ─── 3. Partida doble garantizada (trigger diferido) ─────────────────
-- Valida al COMMIT que todo asiento confirmado tocado en la transacción
-- quede balanceado. Diferido para que "insertar cabecera + insertar
-- líneas" dentro de una misma transacción (las RPCs) valide al final.
-- El flujo viejo (cabecera y líneas en requests separados) también pasa:
-- cada batch de líneas es balanceado por sí mismo.
CREATE OR REPLACE FUNCTION public.fn_validar_asiento_balanceado() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  aid uuid;
  v_estado text;
  td numeric; th numeric;
BEGIN
  IF TG_TABLE_NAME = 'asiento_lineas' THEN
    aid := COALESCE(NEW.asiento_id, OLD.asiento_id);
  ELSE
    aid := NEW.id;
  END IF;
  SELECT estado INTO v_estado FROM asientos WHERE id = aid;
  IF v_estado = 'confirmado' THEN
    SELECT COALESCE(SUM(debe),0), COALESCE(SUM(haber),0) INTO td, th
    FROM asiento_lineas WHERE asiento_id = aid;
    IF abs(td - th) >= 0.01 THEN
      RAISE EXCEPTION 'Asiento desbalanceado: Debe % ≠ Haber %', td, th;
    END IF;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lineas_balance ON asiento_lineas;
CREATE CONSTRAINT TRIGGER trg_lineas_balance
  AFTER INSERT OR UPDATE OR DELETE ON asiento_lineas
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.fn_validar_asiento_balanceado();

-- Confirmar un asiento (borrador → confirmado) también valida sus líneas.
DROP TRIGGER IF EXISTS trg_asientos_balance ON asientos;
CREATE CONSTRAINT TRIGGER trg_asientos_balance
  AFTER UPDATE OF estado ON asientos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW WHEN (NEW.estado = 'confirmado')
  EXECUTE FUNCTION public.fn_validar_asiento_balanceado();

-- ─── 4. Ventas con factura emitida: intocables ───────────────────────
-- Un CAE emitido vive en la base de AFIP. Borrar o cambiar el monto de
-- la venta deja los libros en contradicción con AFIP. Lo correcto es
-- emitir Nota de Crédito (flujo futuro).
CREATE OR REPLACE FUNCTION public.fn_proteger_venta_facturada() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.factura_emitida_id IS NOT NULL THEN
      RAISE EXCEPTION 'No se puede anular: la venta tiene factura emitida (CAE en AFIP). Corresponde Nota de Crédito.';
    END IF;
    RETURN OLD;
  END IF;
  -- UPDATE: mientras siga vinculada a una factura, monto/cliente/nro fijos
  IF OLD.factura_emitida_id IS NOT NULL AND NEW.factura_emitida_id IS NOT NULL THEN
    IF NEW.total IS DISTINCT FROM OLD.total
       OR NEW.cliente IS DISTINCT FROM OLD.cliente
       OR NEW.nro_remito IS DISTINCT FROM OLD.nro_remito THEN
      RAISE EXCEPTION 'La venta tiene factura emitida (CAE): no se puede cambiar monto, cliente ni número.';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_proteger_venta_facturada ON ventas;
CREATE TRIGGER trg_proteger_venta_facturada
  BEFORE UPDATE OR DELETE ON ventas
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_venta_facturada();

-- ─── 5. FK ventas.cliente_id + backfill ──────────────────────────────
ALTER TABLE ventas ADD COLUMN IF NOT EXISTS cliente_id uuid REFERENCES clientes(id) ON DELETE SET NULL;

-- Backfill por nombre (case-insensitive); ante duplicados gana el más antiguo.
UPDATE ventas v SET cliente_id = c.id
FROM (
  SELECT DISTINCT ON (empresa_id, lower(nombre)) id, empresa_id, lower(nombre) AS ln
  FROM clientes ORDER BY empresa_id, lower(nombre), created_at
) c
WHERE v.cliente_id IS NULL AND c.empresa_id = v.empresa_id AND c.ln = lower(v.cliente);

CREATE INDEX IF NOT EXISTS idx_ventas_cliente ON ventas (cliente_id);

-- ─── 6. Helper: upsert de cliente por nombre ─────────────────────────
-- SECURITY INVOKER: corre con el rol del usuario, la RLS scopea empresa.
CREATE OR REPLACE FUNCTION public.upsert_cliente(p_nombre text, p_cuit text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public AS $$
DECLARE emp uuid := public.current_empresa_id(); cid uuid;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(trim(p_nombre),'') = '' THEN RAISE EXCEPTION 'Falta el nombre del cliente'; END IF;
  SELECT id INTO cid FROM clientes
  WHERE empresa_id = emp AND lower(nombre) = lower(trim(p_nombre))
  ORDER BY created_at LIMIT 1;
  IF cid IS NULL THEN
    INSERT INTO clientes (empresa_id, nombre, cuit)
    VALUES (emp, trim(p_nombre), NULLIF(trim(COALESCE(p_cuit,'')),''))
    RETURNING id INTO cid;
  ELSIF NULLIF(trim(COALESCE(p_cuit,'')),'') IS NOT NULL THEN
    UPDATE clientes SET cuit = trim(p_cuit) WHERE id = cid AND COALESCE(cuit,'') = '';
  END IF;
  RETURN cid;
END $$;
REVOKE ALL ON FUNCTION public.upsert_cliente(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.upsert_cliente(text, text) TO authenticated;

-- ─── 7. RPC crear_asiento: cabecera + líneas en UNA transacción ───────
-- p_asiento_id != NULL → reemplaza (cabecera update + líneas regeneradas),
-- usado por la edición manual y los asientos automáticos idempotentes.
-- Si la cabecera no trae numero, numera la DB (trigger del punto 2).
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
      updated_at      = now()
    WHERE id = p_asiento_id AND empresa_id = emp
    RETURNING id, numero INTO v_id, v_num;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Asiento no encontrado'; END IF;
    DELETE FROM asiento_lineas WHERE asiento_id = v_id;
  ELSE
    INSERT INTO asientos (empresa_id, numero, fecha, descripcion, comprobante_nro,
                          estado, tipo, origen_tipo, origen_id, moneda, tipo_cambio, tc_tipo)
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
            p_cabecera->>'tc_tipo')
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
GRANT EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) TO authenticated;

-- ─── 8. RPC guardar_venta: venta + items + stock, atómico ─────────────
-- Reemplaza el saveVenta de N requests. Si cualquier paso falla
-- (incluido stock insuficiente), no queda NADA a medias.
CREATE OR REPLACE FUNCTION public.guardar_venta(p_venta jsonb, p_items jsonb, p_venta_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; v_cliente_id uuid;
  it jsonb; r record; v_pieza text; v_cant int;
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
    -- Edición: devolver el stock de los items viejos y regenerarlos
    FOR r IN SELECT producto_id, cantidad FROM venta_items
             WHERE venta_id = p_venta_id AND producto_id IS NOT NULL LOOP
      UPDATE productos_terminados SET cantidad = cantidad + r.cantidad WHERE id = r.producto_id;
    END LOOP;
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
      updated_at = now()
    WHERE id = p_venta_id AND empresa_id = emp
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
  ELSE
    INSERT INTO ventas (empresa_id, nro_remito, nro_pedido, cliente, cliente_id, fecha,
                        condicion_pago, estado, estado_pedido,
                        coef_registracion_moneda, coef_emision_moneda, coef_deuda_moneda,
                        fecha_entrega_desde, fecha_entrega_hasta, total, bonif_pct_1,
                        lista_precios_id, grupo_bonificacion, vendedor_id, observaciones)
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
            p_venta->>'observaciones')
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
REVOKE ALL ON FUNCTION public.guardar_venta(jsonb, jsonb, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.guardar_venta(jsonb, jsonb, uuid) TO authenticated;

-- ─── 9. RPC anular_venta: repone stock + anula asientos + borra ───────
-- También desengancha el presupuesto convertido (hoy la FK
-- presupuestos.venta_id hacía fallar el DELETE y dejaba el stock repuesto
-- dos veces al reintentar).
-- Devuelve jsonb (no void) para que PostgREST responda 200 con body
-- (el db() del frontend hace r.json() siempre).
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
  FOR r IN SELECT producto_id, cantidad FROM venta_items
           WHERE venta_id = p_venta_id AND producto_id IS NOT NULL LOOP
    UPDATE productos_terminados SET cantidad = cantidad + r.cantidad WHERE id = r.producto_id;
  END LOOP;
  UPDATE asientos SET estado = 'anulado'
  WHERE empresa_id = emp AND origen_tipo = 'venta' AND origen_id = p_venta_id;
  UPDATE presupuestos SET venta_id = NULL, estado = 'aprobado'
  WHERE empresa_id = emp AND venta_id = p_venta_id;
  DELETE FROM venta_items WHERE venta_id = p_venta_id;
  DELETE FROM ventas WHERE id = p_venta_id;
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public.anular_venta(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.anular_venta(uuid) TO authenticated;

-- ─── 10. RPC convertir_presupuesto: numeración V-xxxxx en la DB ───────
-- Elimina el 'V-'+(ventas.length+1) del cliente (duplicaba números si
-- dos usuarios convertían a la vez o si se borró una venta intermedia).
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
                      observaciones, total)
  VALUES (emp, v_nro, v_nro, p.cliente, v_cliente_id, current_date,
          'pendiente', 'pendiente', p.condicion_pago, p.fecha_vencimiento,
          'USD', 'USD', 'USD',
          'Generada desde presupuesto ' || p.nro ||
            COALESCE(' — ' || NULLIF(p.observaciones,''), ''),
          COALESCE(p.total, 0))
  RETURNING id INTO v_id;

  -- Igual que el flujo actual: la conversión NO descuenta stock PT
  -- (la venta nace 'pendiente'; el stock se mueve al editarla/entregarla).
  INSERT INTO venta_items (venta_id, producto_id, pieza, cantidad, precio_unitario, total)
  SELECT v_id, pi.producto_id, pi.pieza, round(COALESCE(pi.cantidad,0))::int,
         COALESCE(pi.precio_unitario,0), COALESCE(pi.subtotal,0)
  FROM presupuesto_items pi WHERE pi.presupuesto_id = p_presupuesto_id;

  UPDATE presupuestos SET estado = 'convertido', venta_id = v_id WHERE id = p_presupuesto_id;

  RETURN jsonb_build_object('id', v_id, 'nro', v_nro);
END $$;
REVOKE ALL ON FUNCTION public.convertir_presupuesto(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.convertir_presupuesto(uuid) TO authenticated;

-- ─── 11. RPC consumir_barra: descuento atómico de materia prima ───────
-- p_kg > 0 consume, p_kg < 0 devuelve (edición de OP). Falla si el
-- stock no alcanza EN ESTE MOMENTO (no según lo que el cliente leyó).
CREATE OR REPLACE FUNCTION public.consumir_barra(p_barra_id uuid, p_kg numeric)
RETURNS numeric LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_kg numeric; v_lote text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_kg, 0) = 0 THEN
    SELECT kg_disponibles INTO v_kg FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    RETURN v_kg;
  END IF;
  UPDATE barras SET kg_disponibles = kg_disponibles - p_kg
  WHERE id = p_barra_id AND empresa_id = emp AND kg_disponibles - p_kg >= 0
  RETURNING kg_disponibles INTO v_kg;
  IF v_kg IS NULL THEN
    SELECT lote, kg_disponibles INTO v_lote, v_kg FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    IF v_lote IS NULL THEN RAISE EXCEPTION 'Barra no encontrada'; END IF;
    RAISE EXCEPTION 'Stock insuficiente en %: disponible % mts', v_lote, v_kg;
  END IF;
  RETURN v_kg;
END $$;
REVOKE ALL ON FUNCTION public.consumir_barra(uuid, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.consumir_barra(uuid, numeric) TO authenticated;

-- ─── 12. Audit log ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id uuid,
  tabla text NOT NULL,
  registro_id uuid,
  accion text NOT NULL,
  usuario uuid,
  datos_old jsonb,
  datos_new jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_tabla_registro ON audit_log (tabla, registro_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_select_admin ON audit_log;
CREATE POLICY audit_select_admin ON audit_log FOR SELECT TO authenticated
  USING (
    COALESCE((SELECT u.es_admin FROM usuarios u WHERE u.id = (SELECT auth.uid())), false)
    AND (empresa_id = (SELECT public.current_empresa_id()) OR empresa_id IS NULL)
  );
-- Sin policies de INSERT/UPDATE/DELETE: solo escribe el trigger (DEFINER).

-- SECURITY DEFINER: el usuario no tiene permiso de INSERT sobre audit_log,
-- escribe el trigger. En UPDATE guarda solo los campos que cambiaron.
CREATE OR REPLACE FUNCTION public.fn_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  j_old jsonb; j_new jsonb; v_emp uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN j_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN j_new := to_jsonb(NEW); END IF;
  IF TG_OP = 'UPDATE' THEN
    -- diff: solo claves modificadas (sin el ruido de updated_at)
    SELECT COALESCE(jsonb_object_agg(o.key, o.value), '{}'::jsonb) INTO j_old
    FROM jsonb_each(j_old) o WHERE j_new->o.key IS DISTINCT FROM o.value AND o.key <> 'updated_at';
    SELECT COALESCE(jsonb_object_agg(n.key, n.value), '{}'::jsonb) INTO j_new
    FROM jsonb_each(j_new) n WHERE to_jsonb(OLD)->n.key IS DISTINCT FROM n.value AND n.key <> 'updated_at';
    IF j_old = '{}'::jsonb AND j_new = '{}'::jsonb THEN RETURN NULL; END IF; -- no cambió nada
  END IF;
  -- empresa: directa, o vía padre en las tablas hijas
  v_emp := COALESCE((COALESCE(j_new, to_jsonb(NEW))->>'empresa_id')::uuid,
                    (COALESCE(j_old, to_jsonb(OLD))->>'empresa_id')::uuid);
  IF v_emp IS NULL AND TG_TABLE_NAME = 'venta_items' THEN
    SELECT empresa_id INTO v_emp FROM ventas
    WHERE id = COALESCE((to_jsonb(NEW)->>'venta_id')::uuid, (to_jsonb(OLD)->>'venta_id')::uuid);
  ELSIF v_emp IS NULL AND TG_TABLE_NAME = 'asiento_lineas' THEN
    SELECT empresa_id INTO v_emp FROM asientos
    WHERE id = COALESCE((to_jsonb(NEW)->>'asiento_id')::uuid, (to_jsonb(OLD)->>'asiento_id')::uuid);
  END IF;
  INSERT INTO audit_log (empresa_id, tabla, registro_id, accion, usuario, datos_old, datos_new)
  VALUES (v_emp, TG_TABLE_NAME,
          COALESCE((to_jsonb(NEW)->>'id')::uuid, (to_jsonb(OLD)->>'id')::uuid),
          TG_OP, auth.uid(), j_old, j_new);
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ventas','venta_items','asientos','asiento_lineas',
                           'barras','productos_terminados','clientes',
                           'ordenes_produccion','presupuestos','facturas_emitidas'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %I', t);
      EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I
                      FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
    END IF;
  END LOOP;
END $$;

-- ─── 13. Cerrar EXECUTE a anon ───────────────────────────────────────
-- Supabase otorga EXECUTE a anon/authenticated/service_role por DEFAULT
-- PRIVILEGES al crear cada función; el REVOKE ... FROM public de arriba
-- no alcanza esos grants explícitos. Sin esto anon puede ejecutar las
-- RPCs (cortan en 'Sin empresa asignada' y la RLS es TO authenticated,
-- así que no expone datos — pero defensa en profundidad).
REVOKE EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.guardar_venta(jsonb, jsonb, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.anular_venta(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.convertir_presupuesto(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.consumir_barra(uuid, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.upsert_cliente(text, text) FROM anon;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND proname IN
--   ('crear_asiento','guardar_venta','anular_venta','convertir_presupuesto',
--    'consumir_barra','upsert_cliente','fn_audit','fn_asiento_numero',
--    'fn_validar_asiento_balanceado','fn_proteger_venta_facturada');
-- SELECT count(*) AS ventas_con_cliente_id FROM ventas WHERE cliente_id IS NOT NULL;
-- SELECT tgname, relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
-- WHERE tgname IN ('trg_audit','trg_lineas_balance','trg_asientos_balance',
--                  'trg_asiento_numero','trg_proteger_venta_facturada');
