-- ═══════════════════════════════════════════════════════════════════
-- 055_integridad.sql
--
-- Fixes de integridad detectados en la auditoría integral 2026-07-30
-- (docs/analisis/2026-07-30-analisis-integral.md, bugs B2-B7):
--
--   1. Facturas de proveedor duplicadas: trigger con mensaje claro +
--      índice UNIQUE (empresa, proveedor, tipo, letra, nro) como red
--      anti-carrera. Hoy la misma factura se puede contabilizar 2 veces.
--   2. recepciones_oc.oc_item_id pasa de ON DELETE CASCADE a RESTRICT:
--      editar una OC (que hace DELETE+re-INSERT de items) o borrarla
--      ya no destruye silenciosamente recepciones e inspecciones.
--   3. RPC eliminar_op: borrar una OP repone los kg consumidos a la
--      barra y se bloquea si la OP tiene PT, registros de calidad,
--      NC, tratamientos o signoffs (evidencia API Q1).
--   4. Numeración de presupuestos server-side: trigger que asigna
--      P-nnnn bajo advisory lock si el nro viene vacío o repetido
--      (hoy el cliente calcula length+1 y colisiona).
--   5. RPC guardar_permisos: reemplaza el PATCH+DELETE+POSTs sueltos
--      del frontend (si fallaba a mitad, el usuario quedaba sin permisos).
--   6. RPC ajustar_precios_pct: ajuste masivo de precios en UNA
--      transacción (hoy: un PATCH por fila, sin atomicidad).
--   7. clientes.condicion_fiscal + config_contable.punto_venta:
--      base para que emitirFactura deje de hardcodear Factura B / PV 1.
--
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Facturas de proveedor duplicadas ────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_factura_recibida_duplicada()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM facturas_recibidas f
    WHERE f.empresa_id = NEW.empresa_id
      AND f.proveedor_id = NEW.proveedor_id
      AND f.tipo = NEW.tipo
      AND f.letra = NEW.letra
      AND f.nro = NEW.nro
      AND f.id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'Ya está registrado el comprobante % % nro % de este proveedor',
      CASE NEW.tipo WHEN 'nota_credito' THEN 'NC' WHEN 'nota_debito' THEN 'ND' ELSE 'FA' END,
      NEW.letra, NEW.nro;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_factura_recibida_duplicada ON facturas_recibidas;
CREATE TRIGGER trg_factura_recibida_duplicada
  BEFORE INSERT OR UPDATE OF nro, letra, tipo, proveedor_id ON facturas_recibidas
  FOR EACH ROW EXECUTE FUNCTION public.fn_factura_recibida_duplicada();

-- Red anti-carrera (dos sesiones registrando a la vez). Si ya hubiera
-- duplicados históricos el índice no se puede crear: se avisa y se
-- sigue (el trigger igual frena los nuevos).
DO $$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS ux_facturas_recibidas_comprobante
    ON facturas_recibidas (empresa_id, proveedor_id, tipo, letra, nro);
EXCEPTION WHEN unique_violation OR others THEN
  RAISE NOTICE 'ux_facturas_recibidas_comprobante no creado (¿duplicados existentes?): %', SQLERRM;
END $$;

-- ─── 2. Recepciones: de CASCADE a RESTRICT ──────────────────────────
-- La edición de OC en el frontend hace DELETE de oc_items + re-INSERT.
-- Con CASCADE eso arrastraba recepciones_oc (y por herencia el estado
-- de inspección de las barras quedaba huérfano). RESTRICT hace que la
-- DB rechace el borrado si hay recepciones — el frontend ahora bloquea
-- la edición de ítems de OCs con mercadería recibida.

ALTER TABLE recepciones_oc
  DROP CONSTRAINT IF EXISTS recepciones_oc_oc_item_id_fkey;
ALTER TABLE recepciones_oc
  ADD CONSTRAINT recepciones_oc_oc_item_id_fkey
  FOREIGN KEY (oc_item_id) REFERENCES oc_items(id) ON DELETE RESTRICT;

-- ─── 3. eliminar_op: borrar OP repone stock y protege evidencia ─────

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

-- ─── 4. Numeración de presupuestos server-side ──────────────────────
-- Si el INSERT trae nro vacío o ya usado, se asigna P-nnnn (max+1 de
-- la empresa) bajo advisory lock. El frontend sigue sugiriendo su nro;
-- la DB garantiza que no colisione.

CREATE OR REPLACE FUNCTION public.fn_presupuesto_nro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' OR EXISTS (
    SELECT 1 FROM presupuestos p
    WHERE p.empresa_id = NEW.empresa_id AND p.nro = NEW.nro AND p.id <> NEW.id
  ) THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('presupuestos_nro:' || NEW.empresa_id::text, 0));
    SELECT 'P-' || lpad((COALESCE(MAX(substring(p.nro from 3)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM presupuestos p
      WHERE p.empresa_id = NEW.empresa_id AND p.nro ~ '^P-[0-9]+$';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_presupuesto_nro ON presupuestos;
CREATE TRIGGER trg_presupuesto_nro
  BEFORE INSERT ON presupuestos
  FOR EACH ROW EXECUTE FUNCTION public.fn_presupuesto_nro();

DO $$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS ux_presupuestos_nro
    ON presupuestos (empresa_id, nro);
EXCEPTION WHEN unique_violation OR others THEN
  RAISE NOTICE 'ux_presupuestos_nro no creado (¿duplicados existentes?): %', SQLERRM;
END $$;

-- ─── 5. guardar_permisos: roles + módulos en una transacción ────────

CREATE OR REPLACE FUNCTION public.guardar_permisos(
  p_usuario_id uuid,
  p_es_admin   boolean,
  p_ver_costos boolean,
  p_es_contador boolean,
  p_modulos    text[]
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  m   text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND es_admin = true) THEN
    RAISE EXCEPTION 'Solo un administrador puede cambiar permisos';
  END IF;
  IF p_es_admin AND p_es_contador THEN
    RAISE EXCEPTION 'Un contador no puede ser administrador';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_usuario_id AND empresa_id = emp) THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;

  -- El trigger usuarios_guard (022/050) sigue vigilando la escalada
  UPDATE usuarios
  SET es_admin = p_es_admin, ver_costos = p_ver_costos, es_contador = p_es_contador
  WHERE id = p_usuario_id AND empresa_id = emp;

  DELETE FROM permisos_usuario WHERE usuario_id = p_usuario_id AND empresa_id = emp;
  IF NOT p_es_admin THEN
    FOREACH m IN ARRAY COALESCE(p_modulos, '{}') LOOP
      INSERT INTO permisos_usuario (empresa_id, usuario_id, modulo)
      VALUES (emp, p_usuario_id, m);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('ok', true, 'modulos', COALESCE(array_length(p_modulos, 1), 0));
END $$;

REVOKE EXECUTE ON FUNCTION public.guardar_permisos(uuid, boolean, boolean, boolean, text[]) FROM PUBLIC, anon;

-- ─── 6. ajustar_precios_pct: ajuste masivo atómico ──────────────────

CREATE OR REPLACE FUNCTION public.ajustar_precios_pct(p_pct numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_count int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF p_pct IS NULL OR p_pct = 0 OR p_pct <= -100 THEN
    RAISE EXCEPTION 'Porcentaje inválido: %', p_pct;
  END IF;
  UPDATE precios_base
  SET precio_usd = round(COALESCE(precio_usd, 0) * (1 + p_pct / 100), 2)
  WHERE empresa_id = emp;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'ajustados', v_count);
END $$;

REVOKE EXECUTE ON FUNCTION public.ajustar_precios_pct(numeric) FROM PUBLIC, anon;

-- ─── 7. Condición fiscal del cliente + punto de venta ───────────────
-- Base para que emitirFactura derive letra A/B según el receptor
-- (RG 5003: RI y monotributistas reciben A; exentos y CF reciben B)
-- y use el punto de venta configurado en vez de hardcodear 1.

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS condicion_fiscal text;
DO $$
BEGIN
  ALTER TABLE clientes ADD CONSTRAINT clientes_condicion_fiscal_chk
    CHECK (condicion_fiscal IS NULL OR condicion_fiscal IN ('RI','monotributo','exento','consumidor_final'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE config_contable ADD COLUMN IF NOT EXISTS punto_venta int NOT NULL DEFAULT 1;

COMMIT;

-- ─── Verificación ───────────────────────────────────────────────────
-- SELECT tgname FROM pg_trigger WHERE tgname IN
--   ('trg_factura_recibida_duplicada','trg_presupuesto_nro');
-- SELECT confdeltype FROM pg_constraint WHERE conname='recepciones_oc_oc_item_id_fkey'; -- 'r'
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('eliminar_op','guardar_permisos','ajustar_precios_pct');
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clientes' AND column_name='condicion_fiscal';
