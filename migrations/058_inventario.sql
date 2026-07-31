-- ═══════════════════════════════════════════════════════════════════
-- 058_inventario.sql — Sprint 4 de la auditoría 2026-07-30
--
--   1. KARDEX (movimientos_stock): cada cambio de cantidad en barras /
--      productos_terminados / insumos queda registrado por TRIGGER con
--      delta, saldo posterior, usuario y contexto. Ningún camino se
--      escapa (RPC, PATCH del frontend, lo que sea): el trigger vive
--      en la tabla. La tabla es de SOLO LECTURA vía API (sin políticas
--      de INSERT/UPDATE/DELETE); escriben únicamente los triggers
--      (SECURITY DEFINER). Por eso NO lleva la batería estándar de
--      contador_guard/trg_audit: es en sí misma un log inmutable.
--   2. Etiquetado de movimientos: las RPCs que mueven stock se
--      re-emiten (copias textuales de 030/039/055) con una línea
--      set_config('app.stock_ctx', ...) para que el kardex diga
--      "consumo-op", "venta", "entrega-venta", etc. en vez de un
--      genérico "edicion".
--   3. Ajustes documentados: RPC ajustar_stock(tipo, item, cantidad
--      nueva, motivo) — motivo obligatorio, kardex etiquetado y
--      asiento automático (stock contra AJUSTES DE INVENTARIO) si el
--      ítem tiene costo y las cuentas están configuradas.
--   4. Cuentas de stock en config: cta_stock_mp (114002 MATERIA
--      PRIMA), cta_stock_pt (114001 Mercaderias), cta_stock_insumos
--      (114003 ACCES. FABRICACION) + cuenta nueva 421099 AJUSTES DE
--      INVENTARIO (egreso).
--   5. Conteo físico: conteos_stock + conteo_items (snapshot del
--      sistema, se cargan cantidades físicas, cerrar_conteo aplica
--      las diferencias vía ajustar_stock → kardex + asientos).
--
-- Requiere: 023 (crear_asiento, current_empresa_id), 030 (ventas),
-- 039 (consumir_barra), 052/053 (es_planta/es_contador), 055
-- (eliminar_op). Idempotente. Correr ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Kardex ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.movimientos_stock (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid        NOT NULL,
  tipo_item          text        NOT NULL CHECK (tipo_item IN ('barra','pt','insumo')),
  item_id            uuid        NOT NULL,
  detalle            text,             -- lote / nombre (snapshot: sobrevive al delete)
  material           text,             -- material / pieza / categoría
  tipo_mov           text        NOT NULL,  -- alta·baja·edicion·consumo-op·devolucion-op·venta·devolucion-venta·entrega-venta·anulacion-venta·ajuste·conteo
  referencia         text,             -- nro de OP/venta/motivo según el caso
  delta              numeric     NOT NULL,
  saldo_posterior    numeric     NOT NULL,
  costo_unitario_usd numeric,
  usuario_id         uuid,
  created_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.movimientos_stock ENABLE ROW LEVEL SECURITY;
-- Solo lectura vía API: única política es SELECT (los triggers escriben
-- como SECURITY DEFINER y no pasan por RLS).
DROP POLICY IF EXISTS tenant_read ON public.movimientos_stock;
CREATE POLICY tenant_read ON public.movimientos_stock
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT public.current_empresa_id()));
DROP POLICY IF EXISTS planta_lockdown ON public.movimientos_stock;
CREATE POLICY planta_lockdown ON public.movimientos_stock
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (NOT public.es_planta());

CREATE INDEX IF NOT EXISTS idx_mov_stock_item
  ON public.movimientos_stock (empresa_id, tipo_item, item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mov_stock_fecha
  ON public.movimientos_stock (empresa_id, created_at DESC);

-- Trigger genérico: compara la columna de cantidad de cada tabla y
-- registra el delta. El contexto llega por set_config transaccional
-- ('app.stock_ctx' = 'tipo-mov:referencia') desde las RPCs de abajo.
CREATE OR REPLACE FUNCTION public.fn_kardex() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  jold jsonb := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  jnew jsonb := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END;
  j    jsonb;
  qty_col text; det_col text; mat_col text; costo_col text; v_tipo_item text;
  v_old numeric; v_new numeric;
  v_ctx text := NULLIF(current_setting('app.stock_ctx', true), '');
  v_mov text; v_ref text;
BEGIN
  IF TG_TABLE_NAME = 'barras' THEN
    qty_col := 'kg_disponibles'; det_col := 'lote'; mat_col := 'material';
    costo_col := 'costo_usd_unidad'; v_tipo_item := 'barra';
  ELSIF TG_TABLE_NAME = 'productos_terminados' THEN
    qty_col := 'cantidad'; det_col := 'lote'; mat_col := 'pieza';
    costo_col := 'costo_unitario'; v_tipo_item := 'pt';
  ELSE
    qty_col := 'cantidad'; det_col := 'nombre'; mat_col := 'categoria';
    costo_col := 'ultimo_precio'; v_tipo_item := 'insumo';
  END IF;
  v_old := COALESCE((jold->>qty_col)::numeric, 0);
  v_new := COALESCE((jnew->>qty_col)::numeric, 0);
  IF TG_OP = 'UPDATE' AND v_new = v_old THEN RETURN NULL; END IF; -- cambió otra cosa, no la cantidad
  j := COALESCE(jnew, jold);
  v_mov := CASE TG_OP
    WHEN 'INSERT' THEN COALESCE(NULLIF(split_part(v_ctx, ':', 1), ''), 'alta')
    WHEN 'DELETE' THEN 'baja'
    ELSE COALESCE(NULLIF(split_part(v_ctx, ':', 1), ''), 'edicion')
  END;
  v_ref := NULLIF(split_part(COALESCE(v_ctx, ''), ':', 2), '');
  INSERT INTO movimientos_stock
    (empresa_id, tipo_item, item_id, detalle, material, tipo_mov, referencia,
     delta, saldo_posterior, costo_unitario_usd, usuario_id)
  VALUES
    ((j->>'empresa_id')::uuid, v_tipo_item, (j->>'id')::uuid,
     j->>det_col, j->>mat_col, v_mov, v_ref,
     v_new - v_old, v_new, (j->>costo_col)::numeric, auth.uid());
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.fn_kardex() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['barras','productos_terminados','insumos'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_kardex ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_kardex AFTER INSERT OR UPDATE OR DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.fn_kardex()', t);
  END LOOP;
END $$;

-- ─── 2. Cuentas de stock y ajustes en config ────────────────────────

ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_stock_mp          uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_stock_pt          uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_stock_insumos     uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_ajuste_inventario uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;

-- Cuenta de resultado para diferencias de inventario (no existía)
INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, activo)
SELECT c.empresa_id, '421099', 'AJUSTES DE INVENTARIO', 'egreso', true
FROM public.config_contable c
WHERE NOT EXISTS (SELECT 1 FROM public.cuentas_contables x
                  WHERE x.empresa_id = c.empresa_id AND x.codigo = '421099');

UPDATE public.config_contable c SET cta_stock_mp = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='114002')
  WHERE cta_stock_mp IS NULL;
UPDATE public.config_contable c SET cta_stock_pt = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='114001')
  WHERE cta_stock_pt IS NULL;
UPDATE public.config_contable c SET cta_stock_insumos = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='114003')
  WHERE cta_stock_insumos IS NULL;
UPDATE public.config_contable c SET cta_ajuste_inventario = (
  SELECT id FROM public.cuentas_contables WHERE empresa_id=c.empresa_id AND codigo='421099')
  WHERE cta_ajuste_inventario IS NULL;

-- ─── 3. RPC ajustar_stock ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ajustar_stock(
  p_tipo text, p_item_id uuid, p_cantidad_nueva numeric, p_motivo text,
  p_origen text DEFAULT 'ajuste')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_actual numeric; v_costo numeric; v_det text;
  v_delta numeric; v_monto numeric; v_asiento jsonb := NULL;
  cfg record; v_cta_stock uuid;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(trim(p_motivo), '') = '' THEN RAISE EXCEPTION 'El motivo del ajuste es obligatorio'; END IF;
  IF p_cantidad_nueva IS NULL OR p_cantidad_nueva < 0 THEN RAISE EXCEPTION 'Cantidad inválida'; END IF;
  IF p_tipo NOT IN ('barra','pt','insumo') THEN RAISE EXCEPTION 'Tipo inválido'; END IF;
  IF p_origen NOT IN ('ajuste','conteo') THEN RAISE EXCEPTION 'Origen inválido'; END IF;

  PERFORM set_config('app.stock_ctx', p_origen || ':' || left(trim(p_motivo), 120), true);

  IF p_tipo = 'barra' THEN
    SELECT kg_disponibles, costo_usd_unidad, lote INTO v_actual, v_costo, v_det
      FROM barras WHERE id = p_item_id AND empresa_id = emp FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Barra no encontrada'; END IF;
    v_delta := p_cantidad_nueva - v_actual;
    IF v_delta = 0 THEN RAISE EXCEPTION 'La cantidad no cambió'; END IF;
    UPDATE barras SET kg_disponibles = p_cantidad_nueva WHERE id = p_item_id;
  ELSIF p_tipo = 'pt' THEN
    SELECT cantidad, costo_unitario, lote INTO v_actual, v_costo, v_det
      FROM productos_terminados WHERE id = p_item_id AND empresa_id = emp FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto terminado no encontrado'; END IF;
    v_delta := p_cantidad_nueva - v_actual;
    IF v_delta = 0 THEN RAISE EXCEPTION 'La cantidad no cambió'; END IF;
    UPDATE productos_terminados SET cantidad = p_cantidad_nueva WHERE id = p_item_id;
  ELSE
    SELECT cantidad, ultimo_precio, nombre INTO v_actual, v_costo, v_det
      FROM insumos WHERE id = p_item_id AND empresa_id = emp FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Insumo no encontrado'; END IF;
    v_delta := p_cantidad_nueva - v_actual;
    IF v_delta = 0 THEN RAISE EXCEPTION 'La cantidad no cambió'; END IF;
    UPDATE insumos SET cantidad = p_cantidad_nueva WHERE id = p_item_id;
  END IF;

  -- Asiento: stock contra AJUSTES DE INVENTARIO, valuado al costo del ítem
  SELECT * INTO cfg FROM config_contable WHERE empresa_id = emp;
  v_cta_stock := CASE p_tipo WHEN 'barra' THEN cfg.cta_stock_mp
                             WHEN 'pt'    THEN cfg.cta_stock_pt
                             ELSE              cfg.cta_stock_insumos END;
  v_monto := round(abs(v_delta) * COALESCE(v_costo, 0), 2);
  IF v_monto >= 0.01 AND v_cta_stock IS NOT NULL AND cfg.cta_ajuste_inventario IS NOT NULL THEN
    v_asiento := public.crear_asiento(
      jsonb_build_object(
        'fecha', CURRENT_DATE, 'estado', 'confirmado', 'tipo', 'auto-ajuste-stock',
        'origen_tipo', 'ajuste-stock', 'origen_id', p_item_id,
        'descripcion', 'Ajuste de stock ' || COALESCE(v_det,'') || ' — ' || trim(p_motivo)),
      CASE WHEN v_delta > 0 THEN
        jsonb_build_array(
          jsonb_build_object('cuenta_id', v_cta_stock, 'debe', v_monto, 'haber', 0,
                            'descripcion', 'Sobrante ' || COALESCE(v_det,''), 'orden', 0),
          jsonb_build_object('cuenta_id', cfg.cta_ajuste_inventario, 'debe', 0, 'haber', v_monto,
                            'descripcion', trim(p_motivo), 'orden', 1))
      ELSE
        jsonb_build_array(
          jsonb_build_object('cuenta_id', cfg.cta_ajuste_inventario, 'debe', v_monto, 'haber', 0,
                            'descripcion', trim(p_motivo), 'orden', 0),
          jsonb_build_object('cuenta_id', v_cta_stock, 'debe', 0, 'haber', v_monto,
                            'descripcion', 'Faltante ' || COALESCE(v_det,''), 'orden', 1))
      END);
  END IF;

  RETURN jsonb_build_object('ok', true, 'delta', v_delta,
                            'asiento_id', v_asiento->>'id');
END $$;
REVOKE ALL ON FUNCTION public.ajustar_stock(text, uuid, numeric, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ajustar_stock(text, uuid, numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ajustar_stock(text, uuid, numeric, text, text) TO authenticated;

-- ─── 4. Conteo físico ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conteos_stock (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid        NOT NULL,
  nro           text,
  fecha         date        NOT NULL DEFAULT CURRENT_DATE,
  estado        text        NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto','cerrado')),
  observaciones text,
  created_by    uuid,
  cerrado_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conteo_items (
  id               uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid    NOT NULL,
  conteo_id        uuid    NOT NULL REFERENCES public.conteos_stock(id) ON DELETE CASCADE,
  tipo_item        text    NOT NULL CHECK (tipo_item IN ('barra','pt','insumo')),
  item_id          uuid    NOT NULL,
  detalle          text,
  material         text,
  cantidad_sistema numeric NOT NULL DEFAULT 0,
  cantidad_fisica  numeric           -- NULL = todavía no contado
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['conteos_stock','conteo_items'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON public.%I FOR ALL TO authenticated
      USING (empresa_id = (SELECT public.current_empresa_id()))
      WITH CHECK (empresa_id = (SELECT public.current_empresa_id()))', t);
    EXECUTE format('DROP POLICY IF EXISTS planta_lockdown ON public.%I', t);
    EXECUTE format('CREATE POLICY planta_lockdown ON public.%I AS RESTRICTIVE FOR ALL TO authenticated
      USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta())', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_ins ON public.%I', t);
    EXECUTE format('CREATE POLICY contador_no_ins ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated
      WITH CHECK ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_upd ON public.%I', t);
    EXECUTE format('CREATE POLICY contador_no_upd ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated
      USING ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_del ON public.%I', t);
    EXECUTE format('CREATE POLICY contador_no_del ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated
      USING ((SELECT NOT public.es_contador()))', t);
    EXECUTE format('DROP TRIGGER IF EXISTS contador_guard ON public.%I', t);
    EXECUTE format('CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I
      FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.fn_audit()', t);
  END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS idx_conteo_items_conteo ON public.conteo_items (conteo_id);

-- Numeración CT-nnnn server-side (patrón presupuestos, mig 055)
CREATE OR REPLACE FUNCTION public.fn_conteo_nro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('conteos_nro:' || NEW.empresa_id::text, 0));
    SELECT 'CT-' || lpad((COALESCE(MAX(substring(c.nro from 4)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM conteos_stock c
      WHERE c.empresa_id = NEW.empresa_id AND c.nro ~ '^CT-[0-9]+$';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_conteo_nro ON public.conteos_stock;
CREATE TRIGGER trg_conteo_nro BEFORE INSERT ON public.conteos_stock
  FOR EACH ROW EXECUTE FUNCTION public.fn_conteo_nro();

-- Cierra el conteo aplicando las diferencias contra el stock ACTUAL
-- (si el stock se movió después del snapshot, la diferencia se calcula
-- contra lo que hay ahora, no contra la foto vieja).
CREATE OR REPLACE FUNCTION public.cerrar_conteo(p_conteo_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  c record; it record; v_actual numeric; v_ajustes int := 0; v_salteados int := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  SELECT * INTO c FROM conteos_stock WHERE id = p_conteo_id AND empresa_id = emp FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Conteo no encontrado'; END IF;
  IF c.estado = 'cerrado' THEN RAISE EXCEPTION 'El conteo % ya está cerrado', c.nro; END IF;

  FOR it IN SELECT * FROM conteo_items
            WHERE conteo_id = p_conteo_id AND cantidad_fisica IS NOT NULL LOOP
    v_actual := CASE it.tipo_item
      WHEN 'barra'  THEN (SELECT kg_disponibles FROM barras WHERE id = it.item_id AND empresa_id = emp)
      WHEN 'pt'     THEN (SELECT cantidad FROM productos_terminados WHERE id = it.item_id AND empresa_id = emp)
      ELSE               (SELECT cantidad FROM insumos WHERE id = it.item_id AND empresa_id = emp)
    END;
    IF v_actual IS NULL THEN v_salteados := v_salteados + 1; CONTINUE; END IF; -- ítem borrado entre medio
    IF it.cantidad_fisica <> v_actual THEN
      PERFORM public.ajustar_stock(it.tipo_item, it.item_id, it.cantidad_fisica,
                                   'Conteo físico ' || c.nro, 'conteo');
      v_ajustes := v_ajustes + 1;
    END IF;
  END LOOP;

  UPDATE conteos_stock SET estado = 'cerrado', cerrado_at = now() WHERE id = p_conteo_id;
  RETURN jsonb_build_object('ok', true, 'nro', c.nro, 'ajustes', v_ajustes, 'saltados', v_salteados);
END $$;
REVOKE ALL ON FUNCTION public.cerrar_conteo(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cerrar_conteo(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.cerrar_conteo(uuid) TO authenticated;

-- ─── 5. Re-emisión de RPCs con etiqueta de kardex ───────────────────
-- Copias textuales de las versiones vigentes (030/039/055) + UNA línea
-- de set_config al inicio de cada bloque que toca stock.

-- 5a. consumir_barra (de 039) — etiqueta 'consumo-op' / 'devolucion-op'
CREATE OR REPLACE FUNCTION public.consumir_barra(p_barra_id uuid, p_kg numeric)
RETURNS numeric LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_kg numeric; v_lote text; v_calidad text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_kg, 0) = 0 THEN
    SELECT kg_disponibles INTO v_kg FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    RETURN v_kg;
  END IF;
  IF p_kg > 0 THEN
    SELECT lote, estado_calidad INTO v_lote, v_calidad
    FROM barras WHERE id = p_barra_id AND empresa_id = emp;
    IF v_lote IS NULL THEN RAISE EXCEPTION 'Barra no encontrada'; END IF;
    IF v_calidad IS DISTINCT FROM 'aceptado' THEN
      RAISE EXCEPTION 'La barra % está en % — requiere inspección de entrada aceptada antes de usarse en producción', v_lote, COALESCE(v_calidad, 'cuarentena');
    END IF;
  END IF;
  PERFORM set_config('app.stock_ctx',
                     CASE WHEN p_kg > 0 THEN 'consumo-op' ELSE 'devolucion-op' END, true);
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

-- 5b. fn_venta_entrega_stock (de 030) — etiqueta 'entrega-venta'
CREATE OR REPLACE FUNCTION public.fn_venta_entrega_stock() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE r record; v_pieza text;
BEGIN
  IF NEW.estado = 'entregado' AND OLD.estado IS DISTINCT FROM 'entregado'
     AND NOT NEW.stock_descontado THEN
    PERFORM set_config('app.stock_ctx', 'entrega-venta:' || COALESCE(NEW.nro_remito,''), true);
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

-- 5c. guardar_venta (de 030) — etiquetas 'devolucion-venta' / 'venta'
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
      PERFORM set_config('app.stock_ctx', 'devolucion-venta:' || COALESCE(p_venta->>'nro_remito',''), true);
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

  PERFORM set_config('app.stock_ctx', 'venta:' || COALESCE(p_venta->>'nro_remito',''), true);
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

-- 5d. anular_venta (de 030) — etiqueta 'anulacion-venta'
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
    PERFORM set_config('app.stock_ctx', 'anulacion-venta:' || COALESCE(v.nro_remito,''), true);
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

-- 5e. eliminar_op (de 055) — etiqueta 'devolucion-op'
CREATE OR REPLACE FUNCTION public.eliminar_op(p_op_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  op  record;
  v_kg_devueltos numeric := 0;
  v_lote text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;

  SELECT * INTO op FROM ordenes_produccion
  WHERE id = p_op_id AND empresa_id = emp
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orden de producción no encontrada'; END IF;

  -- Evidencia y derivados: la OP no se borra, se corrige o se anula
  IF EXISTS (SELECT 1 FROM productos_terminados WHERE orden_id = p_op_id) THEN
    RAISE EXCEPTION 'La OP % ya generó producto terminado. Eliminá o corregí primero el lote de PT.', op.nro;
  END IF;
  IF EXISTS (SELECT 1 FROM registros_calidad WHERE orden_id = p_op_id) THEN
    RAISE EXCEPTION 'La OP % tiene registros de calidad asociados: no se puede eliminar (retención de evidencia).', op.nro;
  END IF;
  IF EXISTS (SELECT 1 FROM no_conformidades WHERE orden_id = p_op_id) THEN
    RAISE EXCEPTION 'La OP % tiene no conformidades asociadas: no se puede eliminar.', op.nro;
  END IF;
  IF EXISTS (SELECT 1 FROM tratamientos WHERE orden_id = p_op_id) THEN
    RAISE EXCEPTION 'La OP % tiene tratamientos con certificado: no se puede eliminar.', op.nro;
  END IF;
  IF EXISTS (SELECT 1 FROM op_operaciones
             WHERE orden_id = p_op_id AND signoff_usuario_id IS NOT NULL) THEN
    RAISE EXCEPTION 'La OP % tiene puntos de control firmados: no se puede eliminar (retención de evidencia).', op.nro;
  END IF;

  -- Reponer el material consumido al crear la OP
  IF op.barra_id IS NOT NULL AND COALESCE(op.kg_usados, 0) > 0 THEN
    PERFORM set_config('app.stock_ctx', 'devolucion-op:' || COALESCE(op.nro,''), true);
    UPDATE barras
    SET kg_disponibles = kg_disponibles + op.kg_usados
    WHERE id = op.barra_id AND empresa_id = emp
    RETURNING lote INTO v_lote;
    IF v_lote IS NOT NULL THEN v_kg_devueltos := op.kg_usados; END IF;
  END IF;

  -- Borra la OP (cascadea op_operaciones → op_time_entries)
  DELETE FROM ordenes_produccion WHERE id = p_op_id AND empresa_id = emp;

  RETURN jsonb_build_object('ok', true, 'kg_devueltos', v_kg_devueltos, 'lote', v_lote);
END $$;

REVOKE EXECUTE ON FUNCTION public.eliminar_op(uuid) FROM PUBLIC, anon;

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT tgrelid::regclass, tgname FROM pg_trigger WHERE tgname='trg_kardex';  -- 3 tablas
-- SELECT count(*) FROM pg_policies WHERE tablename='movimientos_stock';        -- 2 (solo SELECT)
-- SELECT count(*) FROM pg_policies WHERE tablename IN ('conteos_stock','conteo_items'); -- 10
-- SELECT codigo, nombre FROM cuentas_contables WHERE codigo='421099';
-- SELECT cta_stock_mp IS NOT NULL, cta_ajuste_inventario IS NOT NULL FROM config_contable;
-- -- Smoke: UPDATE barras SET kg_disponibles = kg_disponibles WHERE false; (no genera filas)
