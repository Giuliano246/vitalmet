-- ═══════════════════════════════════════════════════════════════════
-- 064_entrega_parcial.sql
-- Entrega parcial de ventas → facturación parcial por división.
--
-- Caso real: el cliente pide 10 VTB (venta de 10), hoy se envían 5 y
-- se facturan 5; las otras 5 quedan pendientes de entrega/facturación.
--
-- Diseño elegido (ver análisis 2026-08-06): en vez de un modelo de
-- entregas/facturas parciales (N tablas + tocar cta cte, guard 023,
-- cert conformidad, mails, render), se DIVIDE la venta en dos ventas
-- hermanas ANTES de entregar/facturar:
--   · la original queda con lo que se envía hoy (y opcionalmente pasa
--     a 'entregado' en la misma transacción → trigger de stock de 058)
--   · la hermana nace 'pendiente' con el saldo, comparte nro_pedido y
--     apunta a la original vía venta_padre_id
-- Después de eso TODO el ciclo existente funciona sin cambios: remito
-- PDF por envío, CAE por lo enviado (emitirFactura), asiento, cta cte,
-- OTD, cert de conformidad e IVA ventas — cada parte es una venta común.
--
-- Reglas:
--   · Solo ventas SIN CAE y NO entregadas se pueden dividir (guard 023
--     igual lo impediría: la división cambia el total).
--   · stock_descontado se HEREDA: si la venta manual ya descontó las 10,
--     ambas partes nacen con flag true (nada que descontar); si vino de
--     presupuesto (flag false), cada parte descuenta al entregarse.
--   · Totales: ítem prorrateado por cantidad (parte = total×env/cant,
--     redondeo a 2; el saldo es el complemento exacto → la suma de las
--     partes SIEMPRE reproduce el total original, sin pérdida por
--     redondeo). Cabecera prorrateada por los totales de ítems.
--   · nro_remito de la hermana: sufijo '-2', '-3'... (único por la
--     UNIQUE(empresa_id, nro_remito) de 023; advisory lock serializa).
--
-- trg_audit (023) ya cubre ventas/venta_items → la división queda
-- auditada sin código extra. Sin tablas nuevas → sin policies nuevas.
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Trazabilidad: la venta-saldo apunta a la original ───────────
ALTER TABLE ventas
  ADD COLUMN IF NOT EXISTS venta_padre_id uuid
  REFERENCES ventas(id) ON DELETE SET NULL;

COMMENT ON COLUMN ventas.venta_padre_id IS
  'Venta original de la que esta es saldo (entrega parcial, RPC dividir_venta). NULL = venta entera.';

CREATE INDEX IF NOT EXISTS idx_ventas_padre
  ON ventas (venta_padre_id) WHERE venta_padre_id IS NOT NULL;

-- ─── 2. Guard: las columnas que clona la RPC tienen que existir ──────
-- (el cuerpo plpgsql no se valida contra las tablas al crear la función;
-- esto hace fallar la MIGRACIÓN si el schema real difiere del esperado)
DO $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['nro_pedido','sucursal','nro_original',
    'coef_registracion','coef_registracion_moneda','coef_emision','coef_emision_moneda',
    'coef_deuda','coef_deuda_moneda','fecha_entrega_desde','fecha_entrega_hasta',
    'bonif_pct_1','bonif_pct_2','contribucion_marginal','lista_precios_id',
    'grupo_bonificacion','vendedor_id','limite_credito','saldo_actual_cliente',
    'stock_descontado','updated_at'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='ventas' AND column_name=c) THEN
      RAISE EXCEPTION 'Falta ventas.% — revisar dividir_venta antes de correr esta migración', c;
    END IF;
  END LOOP;
  FOREACH c IN ARRAY ARRAY['cantidad_bonificada','bonif_1','bonif_2','bonif_3','tot_pct_bonif'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='venta_items' AND column_name=c) THEN
      RAISE EXCEPTION 'Falta venta_items.% — revisar dividir_venta antes de correr esta migración', c;
    END IF;
  END LOOP;
END $$;

-- ─── 3. RPC dividir_venta ────────────────────────────────────────────
-- p_cantidades: [{venta_item_id, cantidad}] = lo que SE ENVÍA hoy.
-- Ítems no listados (o con 0) van enteros al saldo.
-- p_entregar: true = la parte enviada pasa a 'entregado' acá mismo
-- (dispara fn_venta_entrega_stock de 058 → kardex + fecha_entregado 026).
CREATE OR REPLACE FUNCTION public.dividir_venta(
  p_venta_id uuid,
  p_cantidades jsonb,
  p_entregar boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v record; r record;
  v_saldo_id uuid; v_nro_saldo text; i int;
  v_env int; v_parte numeric; v_pend numeric;
  t_items numeric := 0;      -- Σ total de ítems originales
  t_env_items numeric := 0;  -- Σ total de ítems enviados
  n_cant int := 0; n_env int := 0;  -- Σ cantidades (fallback de prorrateo)
  total_env numeric; total_pend numeric;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;

  SELECT * INTO v FROM ventas
  WHERE id = p_venta_id AND empresa_id = emp
  FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
  IF v.factura_emitida_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede dividir: la venta ya tiene factura emitida (CAE en AFIP).';
  END IF;
  IF v.estado IN ('entregado','facturado') THEN
    RAISE EXCEPTION 'La venta ya está entregada — no hay saldo que dividir.';
  END IF;

  -- Cada elemento de p_cantidades tiene que referir a un ítem de ESTA venta
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(p_cantidades,'[]'::jsonb)) e
    WHERE NOT EXISTS (
      SELECT 1 FROM venta_items vi
      WHERE vi.id = (e->>'venta_item_id')::uuid AND vi.venta_id = p_venta_id)
  ) THEN
    RAISE EXCEPTION 'Ítem inexistente en la venta';
  END IF;

  -- Validar cantidades y acumular totales
  FOR r IN
    SELECT vi.*,
           COALESCE((SELECT (e->>'cantidad')::int
                     FROM jsonb_array_elements(COALESCE(p_cantidades,'[]'::jsonb)) e
                     WHERE (e->>'venta_item_id')::uuid = vi.id), 0) AS env
    FROM venta_items vi WHERE vi.venta_id = p_venta_id
  LOOP
    IF r.env < 0 OR r.env > r.cantidad THEN
      RAISE EXCEPTION 'Cantidad a enviar inválida en %: máximo %', COALESCE(r.pieza,'ítem'), r.cantidad;
    END IF;
    t_items := t_items + COALESCE(r.total, 0);
    n_cant := n_cant + r.cantidad;
    n_env := n_env + r.env;
    IF r.env = r.cantidad THEN
      t_env_items := t_env_items + COALESCE(r.total, 0);
    ELSIF r.env > 0 THEN
      t_env_items := t_env_items + round(COALESCE(r.total,0) * r.env / r.cantidad, 2);
    END IF;
  END LOOP;

  IF n_cant = 0 THEN RAISE EXCEPTION 'La venta no tiene ítems'; END IF;
  IF n_env <= 0 THEN RAISE EXCEPTION 'Indicá cuánto se envía de al menos un ítem'; END IF;
  IF n_env >= n_cant THEN
    RAISE EXCEPTION 'Se envía todo — no queda saldo pendiente. Pasala a "entregado" directamente.';
  END IF;

  -- Cabecera prorrateada (por totales de ítems; por cantidades si son $0)
  IF t_items > 0 THEN
    total_env := round(COALESCE(v.total,0) * t_env_items / t_items, 2);
  ELSE
    total_env := round(COALESCE(v.total,0) * n_env / n_cant, 2);
  END IF;
  total_pend := COALESCE(v.total,0) - total_env;

  -- Numeración de la hermana: sufijo -2, -3... (serializado por lock)
  PERFORM pg_advisory_xact_lock(hashtextextended('ventas_nro:' || emp::text, 0));
  i := 2;
  LOOP
    v_nro_saldo := v.nro_remito || '-' || i;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM ventas WHERE empresa_id = emp AND nro_remito = v_nro_saldo);
    i := i + 1;
  END LOOP;

  -- Venta-saldo: clona la cabecera, nace pendiente con el resto
  INSERT INTO ventas (empresa_id, nro_remito, nro_pedido, cliente, cliente_id, fecha,
                      condicion_pago, estado, estado_pedido, sucursal, nro_original,
                      coef_registracion, coef_registracion_moneda,
                      coef_emision, coef_emision_moneda,
                      coef_deuda, coef_deuda_moneda,
                      fecha_entrega_desde, fecha_entrega_hasta,
                      total, bonif_pct_1, bonif_pct_2, contribucion_marginal,
                      lista_precios_id, grupo_bonificacion, vendedor_id,
                      limite_credito, saldo_actual_cliente, observaciones,
                      stock_descontado, venta_padre_id)
  VALUES (emp, v_nro_saldo, COALESCE(v.nro_pedido, v.nro_remito), v.cliente, v.cliente_id, v.fecha,
          v.condicion_pago, 'pendiente', 'pendiente', v.sucursal, v.nro_original,
          v.coef_registracion, v.coef_registracion_moneda,
          v.coef_emision, v.coef_emision_moneda,
          v.coef_deuda, v.coef_deuda_moneda,
          v.fecha_entrega_desde, v.fecha_entrega_hasta,
          total_pend, v.bonif_pct_1, v.bonif_pct_2, v.contribucion_marginal,
          v.lista_precios_id, v.grupo_bonificacion, v.vendedor_id,
          v.limite_credito, v.saldo_actual_cliente,
          'Saldo pendiente de ' || v.nro_remito ||
            COALESCE(' — ' || NULLIF(v.observaciones,''), ''),
          v.stock_descontado, v.id)
  RETURNING id INTO v_saldo_id;

  -- Repartir los ítems (SIN mover stock: la división no es un movimiento
  -- físico — el stock lo descuenta el trigger de 058 al entregar cada parte,
  -- o ya estaba descontado si la venta era manual)
  FOR r IN
    SELECT vi.*,
           COALESCE((SELECT (e->>'cantidad')::int
                     FROM jsonb_array_elements(COALESCE(p_cantidades,'[]'::jsonb)) e
                     WHERE (e->>'venta_item_id')::uuid = vi.id), 0) AS env
    FROM venta_items vi WHERE vi.venta_id = p_venta_id
  LOOP
    IF r.env = 0 THEN
      -- No se envía nada de este ítem → pasa entero al saldo
      UPDATE venta_items SET venta_id = v_saldo_id WHERE id = r.id;
    ELSIF r.env < r.cantidad THEN
      v_parte := round(COALESCE(r.total,0) * r.env / r.cantidad, 2);
      v_pend  := COALESCE(r.total,0) - v_parte;
      UPDATE venta_items SET cantidad = r.env, total = v_parte WHERE id = r.id;
      INSERT INTO venta_items (venta_id, producto_id, pieza, cantidad, precio_unitario,
                               tipo_cambio, total, cantidad_bonificada,
                               bonif_1, bonif_2, bonif_3, tot_pct_bonif)
      VALUES (v_saldo_id, r.producto_id, r.pieza, r.cantidad - r.env, r.precio_unitario,
              r.tipo_cambio, v_pend, r.cantidad_bonificada,
              r.bonif_1, r.bonif_2, r.bonif_3, r.tot_pct_bonif);
    END IF;
    -- env = cantidad → el ítem queda entero en la original
  END LOOP;

  UPDATE ventas SET total = total_env, updated_at = now() WHERE id = p_venta_id;

  IF p_entregar THEN
    -- Dispara fn_venta_entrega_stock (058: descuenta con etiqueta kardex
    -- si el flag estaba apagado) y fn_venta_fecha_entregado (026)
    UPDATE ventas SET estado = 'entregado', estado_pedido = 'entregado'
    WHERE id = p_venta_id;
  END IF;

  RETURN jsonb_build_object(
    'id', p_venta_id, 'saldo_id', v_saldo_id, 'nro_saldo', v_nro_saldo,
    'total_enviado', total_env, 'total_pendiente', total_pend);
END $$;

-- Supabase da EXECUTE a anon por default privileges → cerrarlo explícito
REVOKE EXECUTE ON FUNCTION public.dividir_venta(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dividir_venta(uuid, jsonb, boolean) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT (SELECT count(*) FROM information_schema.columns
--          WHERE table_name='ventas' AND column_name='venta_padre_id') AS col,
--        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--          WHERE n.nspname='public' AND p.proname='dividir_venta') AS rpc;
-- Esperado: col=1, rpc=1
