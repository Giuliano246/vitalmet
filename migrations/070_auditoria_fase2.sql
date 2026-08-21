-- 070_auditoria_fase2.sql — Remediación auditoría externa 2026-08 (Fase 2)
-- Cierra los hallazgos H-01 (CRÍTICA), H-06 y H-07 (MEDIAS) del informe.
-- H-03 (ALTA) va en el mismo deploy pero es frontend puro: pre-check
-- anti doble CAE en emitirFactura + repararVinculosVentaFactura() al
-- cargar (re-vincula ventas con CAE que quedaron sin factura_emitida_id).
--
--   H-01 (CRÍTICA) — Recepción de OC no transaccional. El frontend hacía
--     entre 4 y N·3+2 requests REST sueltos (POST barras/insumos/
--     herramientas → POST recepciones_oc → PATCH oc_items → PATCH
--     ordenes_compra → crear_asiento): una falla a mitad de camino
--     dejaba stock creado sin recepción, cantidad_recibida a medias y
--     la compra sin devengar; reintentar DUPLICABA. Ahora RPC
--     registrar_recepcion_oc (mismo molde que guardar_venta /
--     registrar_cobro): TODO en una transacción, idempotente por
--     batch_id (el frontend genera un uuid por intento y lo reusa al
--     reintentar tras un timeout — si el commit anterior entró, la RPC
--     responde ya_registrada en vez de duplicar). El asiento lo arma el
--     frontend (armarAsientoRecepcion, misma lógica de imputación de
--     siempre) y la RPC lo crea vía crear_asiento DENTRO de la misma
--     transacción: si el asiento falla, la recepción también rollbackea
--     (antes quedaba stock sin asiento en silencio). Sin configuración
--     contable el frontend manda p_asiento = null y la recepción sale
--     sin asiento, como siempre.
--
--   H-06 (MEDIA) — guardar_venta forzaba stock_descontado=true en TODA
--     edición: editar una venta convertida de presupuesto que seguía
--     pendiente (que NO descuenta stock hasta la entrega) descontaba el
--     stock ahí mismo y le pisaba la semántica de "descontar al
--     entregar". Re-emisión (base 058 — ediciones futuras parten de
--     070): la edición PRESERVA el comportamiento de la venta
--     (v_descontado); solo descuenta si la venta ya había descontado, o
--     si el propio save la pasa a 'entregado' (en ese caso marca
--     stock_descontado=true ANTES de que el trigger de entrega vea los
--     items borrados, y descuenta los items nuevos en la RPC).
--
--   H-07 (MEDIA) — usuarios_guard sin cláusula es_auditor: un no-admin
--     podía flipear usuarios.es_auditor por REST (defensa en
--     profundidad; el flag además AGREGA restricciones, no privilegios,
--     pero el guard debe cubrir los 5 flags parejo). Re-emisión de la
--     función (base 053 — ediciones futuras parten de 070) con la misma
--     regla que es_admin / ver_costos / es_planta / es_contador.
--
-- Convenciones: idempotente, jsonb, REVOKE anon, search_path=public.
-- Correr en el SQL Editor ANTES de deployar el frontend.

BEGIN;

-- ─── 1. recepciones_oc.batch_id — clave de idempotencia ──────────────
-- Todas las filas de un mismo submit comparten el batch. No es UNIQUE
-- (N ítems por batch); la serialización la da el FOR UPDATE sobre la OC.

ALTER TABLE public.recepciones_oc
  ADD COLUMN IF NOT EXISTS batch_id uuid;
CREATE INDEX IF NOT EXISTS idx_recepciones_oc_batch
  ON public.recepciones_oc (batch_id) WHERE batch_id IS NOT NULL;

-- ─── 2. RPC registrar_recepcion_oc — recepción atómica ───────────────
-- SECURITY INVOKER: la RLS del caller aplica a todos los INSERT/UPDATE
-- (tenant_isolation, planta_lockdown y contador_no_* siguen mandando).
-- p_items:   [{oc_item_id, qty, tipo, descripcion, material, perfil,
--              diametro, unidad, precio_unitario}]
-- p_meta:    {fecha, certificado_id, nro_colada, remito_nro, observaciones}
-- p_asiento: {cabecera, lineas} | null (lo arma el frontend con la
--            lógica de imputación de generarAsientoCompra)

CREATE OR REPLACE FUNCTION public.registrar_recepcion_oc(
  p_oc_id uuid, p_items jsonb, p_meta jsonb,
  p_asiento jsonb DEFAULT NULL, p_batch_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  oc record; item record; it jsonb;
  v_fecha date; v_cert uuid; v_qty numeric; v_precio numeric;
  v_barra_id uuid; v_ins_id uuid; v_lote text; v_costo numeric; v_tc numeric;
  v_all boolean; v_any boolean; v_estado text;
  v_cnt int := 0; v_asiento jsonb := NULL;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_items, '[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'La recepción no tiene ítems';
  END IF;
  v_fecha := NULLIF(p_meta->>'fecha', '')::date;
  IF v_fecha IS NULL THEN RAISE EXCEPTION 'La fecha de recepción es obligatoria'; END IF;
  v_cert := NULLIF(p_meta->>'certificado_id', '')::uuid;

  -- Serializa recepciones concurrentes de la misma OC y ancla el
  -- chequeo de idempotencia: el retry espera este lock y recién
  -- entonces ve (o no) el batch ya commiteado.
  SELECT * INTO oc FROM ordenes_compra
  WHERE id = p_oc_id AND empresa_id = emp FOR UPDATE;
  IF oc.id IS NULL THEN RAISE EXCEPTION 'Orden de compra no encontrada'; END IF;

  IF p_batch_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM recepciones_oc WHERE batch_id = p_batch_id AND empresa_id = emp
  ) THEN
    SELECT bool_and(COALESCE(cantidad_recibida, 0) >= COALESCE(cantidad, 0))
      INTO v_all FROM oc_items WHERE oc_id = oc.id;
    RETURN jsonb_build_object('ok', true, 'ya_registrada', true,
                              'all_complete', COALESCE(v_all, false));
  END IF;

  -- Etiqueta del kardex (fn_kardex, mig 058) para las altas de stock
  PERFORM set_config('app.stock_ctx', 'recepcion-oc:' || COALESCE(oc.nro, ''), true);

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((it->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Cantidad recibida inválida'; END IF;

    SELECT * INTO item FROM oc_items
    WHERE id = (it->>'oc_item_id')::uuid AND oc_id = oc.id FOR UPDATE;
    IF item.id IS NULL THEN
      RAISE EXCEPTION 'El ítem % no pertenece a la OC %', it->>'oc_item_id', oc.nro;
    END IF;

    v_precio := COALESCE((it->>'precio_unitario')::numeric, 0);
    v_barra_id := NULL;

    IF it->>'tipo' = 'materia_prima' THEN
      -- Espejo de la barraData del frontend: nace valuada en USD
      v_tc := COALESCE(oc.tipo_cambio, 0);
      v_costo := CASE WHEN oc.moneda = 'ARS' AND v_tc > 0 THEN v_precio / v_tc ELSE v_precio END;
      v_lote := COALESCE(oc.nro, 'OC') || '-'
             || left(regexp_replace(COALESCE(it->>'descripcion', ''), '\s', '', 'g'), 8)
             || '-' || lpad(floor(random() * 10000)::int::text, 4, '0');
      INSERT INTO barras (empresa_id, lote, material, perfil, diametro,
                          kg_disponibles, unidades, nro_colada, certificado_id,
                          kg_minimo, proveedor_id, oc_id, costo_usd_unidad, observaciones)
      VALUES (emp, v_lote,
              COALESCE(NULLIF(it->>'material', ''), it->>'descripcion'),
              COALESCE(it->>'perfil', ''), COALESCE(it->>'diametro', ''),
              CASE WHEN it->>'unidad' IN ('kg', 'mts') THEN v_qty ELSE 0 END,
              CASE WHEN it->>'unidad' = 'un' THEN v_qty ELSE 0 END,
              COALESCE(p_meta->>'nro_colada', ''), v_cert, 0,
              oc.proveedor_id, oc.id,
              NULLIF(v_costo, 0),
              'Recepción OC ' || COALESCE(oc.nro, ''))
      RETURNING id INTO v_barra_id;

    ELSIF it->>'tipo' = 'insumo' THEN
      -- Match por nombre case-insensitive contra la DB (no contra el
      -- caché del navegador) y con lock: dos recepciones concurrentes
      -- del mismo insumo no pisan la cantidad.
      SELECT id INTO v_ins_id FROM insumos
      WHERE empresa_id = emp
        AND lower(trim(nombre)) = lower(trim(COALESCE(it->>'descripcion', '')))
      LIMIT 1 FOR UPDATE;
      IF v_ins_id IS NOT NULL THEN
        UPDATE insumos SET
          cantidad = COALESCE(cantidad, 0) + v_qty,
          ultimo_precio = COALESCE(NULLIF(v_precio, 0), ultimo_precio),
          proveedor_id = COALESCE(oc.proveedor_id, proveedor_id),
          updated_at = now()
        WHERE id = v_ins_id;
      ELSE
        INSERT INTO insumos (empresa_id, nombre, descripcion, cantidad, unidad,
                             ultimo_precio, proveedor_id, observaciones)
        VALUES (emp, trim(COALESCE(it->>'descripcion', '')),
                NULLIF(it->>'descripcion', ''), v_qty,
                COALESCE(NULLIF(it->>'unidad', ''), 'un'),
                NULLIF(v_precio, 0), oc.proveedor_id,
                'Recibido en OC ' || COALESCE(oc.nro, ''));
      END IF;

    ELSIF it->>'tipo' = 'herramienta' THEN
      INSERT INTO herramientas (empresa_id, nombre, descripcion, cantidad, estado,
                                precio_compra, fecha_compra, proveedor_id, observaciones)
      VALUES (emp, trim(COALESCE(it->>'descripcion', '')),
              NULLIF(it->>'descripcion', ''), v_qty, 'nueva',
              NULLIF(v_precio, 0), v_fecha, oc.proveedor_id,
              'Recibida en OC ' || COALESCE(oc.nro, ''));
    END IF;
    -- 'servicio' u otros tipos: sin alta de stock, solo recepción + asiento

    INSERT INTO recepciones_oc (empresa_id, oc_item_id, fecha, cantidad_recibida,
                                certificado_id, barra_id, remito_nro, observaciones, batch_id)
    VALUES (emp, item.id, v_fecha, v_qty, v_cert, v_barra_id,
            NULLIF(p_meta->>'remito_nro', ''), NULLIF(p_meta->>'observaciones', ''),
            p_batch_id);

    UPDATE oc_items SET cantidad_recibida = COALESCE(cantidad_recibida, 0) + v_qty
    WHERE id = item.id;
    v_cnt := v_cnt + 1;
  END LOOP;

  -- Estado de la OC (misma regla que el frontend viejo)
  SELECT bool_and(COALESCE(cantidad_recibida, 0) >= COALESCE(cantidad, 0)),
         bool_or(COALESCE(cantidad_recibida, 0) > 0)
    INTO v_all, v_any FROM oc_items WHERE oc_id = oc.id;
  v_estado := CASE WHEN COALESCE(v_all, false) THEN 'recibida'
                   WHEN COALESCE(v_any, false) THEN 'recibida_parcial'
                   ELSE oc.estado END;
  UPDATE ordenes_compra SET estado = v_estado WHERE id = oc.id;

  -- Asiento de recepción (GR/IR) en la MISMA transacción: si falla,
  -- la recepción entera rollbackea (antes quedaba stock sin devengar).
  IF p_asiento IS NOT NULL AND p_asiento ? 'cabecera' THEN
    v_asiento := public.crear_asiento(
      (p_asiento->'cabecera') || jsonb_build_object('origen_id', p_batch_id),
      p_asiento->'lineas');
  END IF;

  RETURN jsonb_build_object('ok', true, 'ya_registrada', false,
                            'all_complete', COALESCE(v_all, false),
                            'estado', v_estado, 'recepciones', v_cnt,
                            'asiento', v_asiento);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_recepcion_oc(uuid, jsonb, jsonb, jsonb, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_recepcion_oc(uuid, jsonb, jsonb, jsonb, uuid) TO authenticated;

-- ─── 3. guardar_venta: la edición preserva stock_descontado (H-06) ───
-- Re-emisión completa (base 058: etiquetas de kardex incluidas).
-- Cambios vs 058, SOLO en el branch de edición (p_venta_id no nulo):
--   · stock_descontado = v_debe_descontar (antes: true fijo)
--   · el loop de ítems solo descuenta stock si corresponde; si la venta
--     sigue difiriendo el descuento a la entrega, los ítems se insertan
--     sin tocar productos_terminados (la valida el trigger al entregar).

CREATE OR REPLACE FUNCTION public.guardar_venta(p_venta jsonb, p_items jsonb, p_venta_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; v_cliente_id uuid;
  it jsonb; r record; v_pieza text; v_cant int;
  v_descontado boolean;
  v_estado_nuevo text := COALESCE(NULLIF(p_venta->>'estado',''), 'pendiente');
  v_debe_descontar boolean;
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
    -- H-06: descontar solo si la venta YA venía descontando, o si este
    -- mismo save la entrega (ahí el descuento no se puede diferir más).
    v_debe_descontar := v_descontado OR v_estado_nuevo = 'entregado';
    -- Edición: devolver el stock de los items viejos (solo si se había
    -- descontado — una venta convertida pendiente nunca lo descontó)
    IF v_descontado THEN
      PERFORM set_config('app.stock_ctx', 'devolucion-venta:' || COALESCE(p_venta->>'nro_remito',''), true);
      FOR r IN SELECT producto_id, cantidad FROM venta_items
               WHERE venta_id = p_venta_id AND producto_id IS NOT NULL LOOP
        UPDATE productos_terminados SET cantidad = cantidad + r.cantidad WHERE id = r.producto_id;
      END LOOP;
    END IF;
    DELETE FROM venta_items WHERE venta_id = p_venta_id;
    -- stock_descontado va ANTES de que el trigger de entrega evalúe:
    -- si el save entrega, el descuento lo hace el loop de abajo (los
    -- items viejos ya no existen para el trigger).
    UPDATE ventas SET
      nro_remito = p_venta->>'nro_remito',
      nro_pedido = p_venta->>'nro_remito',
      cliente = p_venta->>'cliente',
      cliente_id = v_cliente_id,
      fecha = NULLIF(p_venta->>'fecha','')::date,
      condicion_pago = p_venta->>'condicion_pago',
      estado = v_estado_nuevo,
      estado_pedido = v_estado_nuevo,
      fecha_entrega_desde = NULLIF(p_venta->>'fecha_entrega_desde','')::date,
      fecha_entrega_hasta = NULLIF(p_venta->>'fecha_entrega_hasta','')::date,
      total = COALESCE((p_venta->>'total')::numeric, 0),
      bonif_pct_1 = COALESCE((p_venta->>'bonif_pct_1')::numeric, 0),
      lista_precios_id = NULLIF(p_venta->>'lista_precios_id','')::uuid,
      grupo_bonificacion = p_venta->>'grupo_bonificacion',
      vendedor_id = NULLIF(p_venta->>'vendedor_id','')::uuid,
      observaciones = p_venta->>'observaciones',
      stock_descontado = v_debe_descontar,
      updated_at = now()
    WHERE id = p_venta_id AND empresa_id = emp
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
  ELSE
    v_debe_descontar := true; -- venta manual nueva: descuenta al guardar, como siempre
    INSERT INTO ventas (empresa_id, nro_remito, nro_pedido, cliente, cliente_id, fecha,
                        condicion_pago, estado, estado_pedido,
                        coef_registracion_moneda, coef_emision_moneda, coef_deuda_moneda,
                        fecha_entrega_desde, fecha_entrega_hasta, total, bonif_pct_1,
                        lista_precios_id, grupo_bonificacion, vendedor_id, observaciones,
                        stock_descontado)
    VALUES (emp, p_venta->>'nro_remito', p_venta->>'nro_remito', p_venta->>'cliente',
            v_cliente_id, NULLIF(p_venta->>'fecha','')::date,
            p_venta->>'condicion_pago',
            v_estado_nuevo,
            v_estado_nuevo,
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

  PERFORM set_config('app.stock_ctx', 'venta:' || COALESCE(p_venta->>'nro_remito',''), true);
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF COALESCE(it->>'producto_id','') = '' THEN RAISE EXCEPTION 'Ítem sin producto'; END IF;
    v_cant := COALESCE((it->>'cantidad')::int, 0);
    IF v_cant <= 0 THEN RAISE EXCEPTION 'Cantidad inválida en un ítem'; END IF;
    v_pieza := NULL;
    IF v_debe_descontar THEN
      -- Descuento atómico: solo descuenta si alcanza el stock AHORA
      UPDATE productos_terminados
      SET cantidad = cantidad - v_cant
      WHERE id = (it->>'producto_id')::uuid AND empresa_id = emp AND cantidad >= v_cant
      RETURNING pieza INTO v_pieza;
      IF NOT FOUND THEN
        SELECT pieza INTO v_pieza FROM productos_terminados WHERE id = (it->>'producto_id')::uuid;
        RAISE EXCEPTION 'Stock insuficiente: %', COALESCE(v_pieza, 'producto');
      END IF;
    ELSE
      -- H-06: la venta difiere el descuento a la entrega (trigger 058);
      -- acá solo se valida que el producto exista.
      SELECT pieza INTO v_pieza FROM productos_terminados
      WHERE id = (it->>'producto_id')::uuid AND empresa_id = emp;
      IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado'; END IF;
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

-- ─── 4. usuarios_guard: cláusula es_auditor (H-07) ───────────────────
-- Re-emisión completa (base 053). El SQL Editor (auth.uid() IS NULL)
-- sigue confiado.

CREATE OR REPLACE FUNCTION public.usuarios_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_admin boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- postgres / service_role: confiado
  END IF;
  SELECT es_admin INTO caller_admin FROM usuarios WHERE id = auth.uid();
  IF TG_OP = 'INSERT' THEN
    NEW.es_admin := false;
    NEW.ver_costos := false;
    NEW.es_planta := false;
    NEW.es_contador := false;
    NEW.es_auditor := false;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.ver_costos IS DISTINCT FROM OLD.ver_costos
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar ver_costos';
    END IF;
    IF NEW.es_planta IS DISTINCT FROM OLD.es_planta
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_planta';
    END IF;
    IF NEW.es_contador IS DISTINCT FROM OLD.es_contador
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_contador';
    END IF;
    IF NEW.es_auditor IS DISTINCT FROM OLD.es_auditor
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_auditor';
    END IF;
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND OLD.empresa_id IS NOT NULL
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

COMMIT;

-- ─── Verificación ────────────────────────────────────────────────────
-- 1) Columna e índice de idempotencia:
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'recepciones_oc' AND column_name = 'batch_id';    -- 1 fila
-- 2) RPC sin anon:
-- SELECT has_function_privilege('anon',
--   'public.registrar_recepcion_oc(uuid,jsonb,jsonb,jsonb,uuid)', 'EXECUTE'); -- false
-- SELECT has_function_privilege('authenticated',
--   'public.registrar_recepcion_oc(uuid,jsonb,jsonb,jsonb,uuid)', 'EXECUTE'); -- true
-- 3) guardar_venta re-emitida con el fix H-06:
-- SELECT prosrc LIKE '%v_debe_descontar%' FROM pg_proc WHERE proname = 'guardar_venta'; -- true
-- 4) Guard con es_auditor:
-- SELECT prosrc LIKE '%es_auditor%' FROM pg_proc WHERE proname = 'usuarios_guard'; -- true
-- 4) Idempotencia funcional (con una OC de prueba): llamar la RPC dos
--    veces con el mismo p_batch_id → la segunda devuelve
--    "ya_registrada": true y NO duplica barras ni cantidad_recibida.
