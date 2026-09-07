-- ═══════════════════════════════════════════════════════════════════
-- 074 — ÓRDENES DE PAGO A PROVEEDORES (multi-medio + imputación)
-- ═══════════════════════════════════════════════════════════════════
-- Spec: docs/superpowers/specs/2026-09-07-ordenes-pago-design.md
--
-- Qué hace:
--   1. Tabla ordenes_pago: comprobante OP-nnnn (trigger con advisory
--      lock) por proveedor, moneda/TC, total, estado confirmada/anulada,
--      asiento vinculado.
--   2. Tabla orden_pago_medios: N medios por OP (caja / banco =
--      transferencia desde una cuenta bancaria real / cheque diferido
--      emitido en la misma transacción / tarjeta de crédito).
--   3. Tabla orden_pago_imputaciones: M facturas canceladas total o
--      parcialmente por la OP. monto en moneda de la OP, monto_factura
--      en la moneda de la factura. El remanente queda "a cuenta".
--   4. config_contable.cta_tarjeta_credito (default 213014).
--   5. RPC registrar_orden_pago(p_cabecera, p_medios, p_imputaciones):
--      valida Σ medios = total, Σ imputaciones ≤ total y cada imputación
--      contra el saldo pendiente de la factura (FOR UPDATE), crea los
--      cheques emitidos, arma el asiento (debe Proveedores / haber cada
--      medio agrupado por cuenta) vía crear_asiento y graba todo en UNA
--      transacción.
--   6. RPC anular_orden_pago(p_id, p_motivo): asiento → anulado (nunca
--      se borra), cheques creados por la OP → anulado (bloquea si alguno
--      ya fue debitado/rechazado), OP → anulada con motivo.
--   7. anular_factura_recibida RE-EMITIDA (base 062 — ediciones futuras
--      parten de acá): bloquea si la factura tiene imputaciones vivas.
--   8. Plan de cuentas: 111003 "BANCO HSBC" → "BANCO BBVA" (sólo si
--      todavía tiene el nombre semilla).
--
-- Batería RLS completa (tenant_isolation + planta_lockdown +
-- contador_no_* + contador_guard + trg_audit), molde de la 073.
-- Requiere: 027 (cheques), 033/054/062 (facturas_recibidas), 035
-- (cuentas_bancarias), 067 (crear_asiento + inmutabilidad), 073.
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.aplicar_bateria(t text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
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
END $$;

-- ─── 1. ordenes_pago ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ordenes_pago (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid          NOT NULL,
  nro              text,                                   -- OP-nnnn (trigger)
  fecha            date          NOT NULL,
  proveedor_id     uuid          NOT NULL REFERENCES public.proveedores(id) ON DELETE RESTRICT,
  moneda           text          NOT NULL DEFAULT 'ARS' CHECK (moneda IN ('ARS','USD')),
  tipo_cambio      numeric,
  total            numeric(18,2) NOT NULL CHECK (total > 0),
  estado           text          NOT NULL DEFAULT 'confirmada' CHECK (estado IN ('confirmada','anulada')),
  asiento_id       uuid          REFERENCES public.asientos(id) ON DELETE SET NULL,
  observaciones    text,
  motivo_anulacion text,
  created_by       uuid,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  updated_at       timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ordenes_pago_empresa_idx ON public.ordenes_pago(empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ordenes_pago_prov_idx ON public.ordenes_pago(proveedor_id);
CREATE UNIQUE INDEX IF NOT EXISTS ordenes_pago_nro_uq ON public.ordenes_pago(empresa_id, nro);
COMMENT ON TABLE public.ordenes_pago IS 'Orden de pago a proveedor (mig 074): N medios + M imputaciones a facturas recibidas; el remanente queda a cuenta. El asiento lo arma registrar_orden_pago.';

CREATE OR REPLACE FUNCTION public.fn_orden_pago_nro() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' OR EXISTS (
    SELECT 1 FROM ordenes_pago o WHERE o.empresa_id = NEW.empresa_id AND o.nro = NEW.nro AND o.id <> NEW.id
  ) THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('ordenes_pago_nro:' || NEW.empresa_id::text, 0));
    SELECT 'OP-' || lpad((COALESCE(MAX(substring(o.nro from 4)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM ordenes_pago o
      WHERE o.empresa_id = NEW.empresa_id AND o.nro ~ '^OP-[0-9]+$';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_orden_pago_nro() FROM PUBLIC, anon;
DROP TRIGGER IF EXISTS trg_orden_pago_nro ON public.ordenes_pago;
CREATE TRIGGER trg_orden_pago_nro BEFORE INSERT OR UPDATE ON public.ordenes_pago
  FOR EACH ROW EXECUTE FUNCTION public.fn_orden_pago_nro();

SELECT pg_temp.aplicar_bateria('ordenes_pago');

-- ─── 2. orden_pago_medios ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orden_pago_medios (
  id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid          NOT NULL,
  orden_pago_id      uuid          NOT NULL REFERENCES public.ordenes_pago(id) ON DELETE CASCADE,
  tipo               text          NOT NULL CHECK (tipo IN ('caja','banco','cheque','tarjeta')),
  monto              numeric(18,2) NOT NULL CHECK (monto > 0),
  cuenta_contable_id uuid          NOT NULL REFERENCES public.cuentas_contables(id) ON DELETE RESTRICT,
  cuenta_bancaria_id uuid          REFERENCES public.cuentas_bancarias(id) ON DELETE SET NULL,
  cheque_id          uuid          REFERENCES public.cheques(id) ON DELETE SET NULL,
  detalle            text,
  orden              int           NOT NULL DEFAULT 0,
  created_at         timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS orden_pago_medios_op_idx ON public.orden_pago_medios(orden_pago_id);
COMMENT ON TABLE public.orden_pago_medios IS 'Medios de una orden de pago (mig 074): caja, banco (cuenta bancaria real), cheque diferido (cheque_id creado en la misma transacción) o tarjeta de crédito.';
SELECT pg_temp.aplicar_bateria('orden_pago_medios');

-- ─── 3. orden_pago_imputaciones ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orden_pago_imputaciones (
  id             uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid          NOT NULL,
  orden_pago_id  uuid          NOT NULL REFERENCES public.ordenes_pago(id) ON DELETE CASCADE,
  factura_id     uuid          NOT NULL REFERENCES public.facturas_recibidas(id) ON DELETE RESTRICT,
  monto          numeric(18,2) NOT NULL CHECK (monto > 0),          -- moneda de la OP
  monto_factura  numeric(18,2) NOT NULL CHECK (monto_factura > 0),  -- moneda de la factura
  created_at     timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT orden_pago_imputaciones_uq UNIQUE (orden_pago_id, factura_id)
);
CREATE INDEX IF NOT EXISTS orden_pago_imput_factura_idx ON public.orden_pago_imputaciones(factura_id);
COMMENT ON TABLE public.orden_pago_imputaciones IS 'Facturas recibidas canceladas (total o parcialmente) por una orden de pago (mig 074). Sólo cuentan las de OPs en estado confirmada.';
SELECT pg_temp.aplicar_bateria('orden_pago_imputaciones');

-- ─── 4. config_contable.cta_tarjeta_credito ─────────────────────────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_tarjeta_credito uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;
UPDATE public.config_contable c SET
  cta_tarjeta_credito = COALESCE(c.cta_tarjeta_credito,
    (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '213014'));

-- ─── 5. Saldo pendiente de una factura (helper) ─────────────────────
-- total − Σ NC asociadas + Σ ND asociadas − Σ imputaciones de OPs
-- confirmadas. En la moneda de la factura. Sólo facturas (no NC/ND).
CREATE OR REPLACE FUNCTION public.saldo_factura_recibida(p_factura_id uuid)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT ROUND(
    f.total
    - COALESCE((SELECT SUM(n.total) FROM facturas_recibidas n
                 WHERE n.factura_asociada_id = f.id AND n.tipo = 'nota_credito'), 0)
    + COALESCE((SELECT SUM(n.total) FROM facturas_recibidas n
                 WHERE n.factura_asociada_id = f.id AND n.tipo = 'nota_debito'), 0)
    - COALESCE((SELECT SUM(i.monto_factura) FROM orden_pago_imputaciones i
                 JOIN ordenes_pago o ON o.id = i.orden_pago_id
                 WHERE i.factura_id = f.id AND o.estado = 'confirmada'), 0)
  , 2)
  FROM facturas_recibidas f WHERE f.id = p_factura_id;
$$;
REVOKE ALL ON FUNCTION public.saldo_factura_recibida(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.saldo_factura_recibida(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.saldo_factura_recibida(uuid) TO authenticated;

-- ─── 6. RPC registrar_orden_pago ────────────────────────────────────
-- p_cabecera: {fecha, proveedor_id, moneda, tipo_cambio, total, observaciones}
-- p_medios:   [{tipo, monto, cuenta_contable_id, cuenta_bancaria_id, detalle,
--               cheque:{numero, banco, fecha_pago, echeq}}]
-- p_imputaciones: [{factura_id, monto, monto_factura}]
CREATE OR REPLACE FUNCTION public.registrar_orden_pago(p_cabecera jsonb, p_medios jsonb, p_imputaciones jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_prov record; v_cfg record; v_op_id uuid; v_nro text;
  v_moneda text := COALESCE(p_cabecera->>'moneda', 'ARS');
  v_tc numeric := NULLIF(p_cabecera->>'tipo_cambio', '')::numeric;
  v_total numeric := ROUND(COALESCE((p_cabecera->>'total')::numeric, 0), 2);
  v_fecha date := (p_cabecera->>'fecha')::date;
  v_sum_medios numeric := 0; v_sum_imput numeric := 0;
  m jsonb; i jsonb; v_monto numeric; v_cta uuid; v_cheque_id uuid; v_ord int := 0;
  f record; v_saldo numeric; v_mf numeric;
  v_lineas jsonb; v_asiento jsonb; v_desc text;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF v_fecha IS NULL THEN RAISE EXCEPTION 'Falta la fecha de la orden de pago'; END IF;
  IF v_total <= 0 THEN RAISE EXCEPTION 'El total de la orden de pago debe ser mayor a cero'; END IF;
  IF v_moneda NOT IN ('ARS','USD') THEN RAISE EXCEPTION 'Moneda inválida: %', v_moneda; END IF;
  IF v_moneda = 'USD' AND COALESCE(v_tc, 0) <= 0 THEN RAISE EXCEPTION 'Una orden de pago en USD necesita tipo de cambio'; END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_medios, '[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'La orden de pago necesita al menos un medio de pago';
  END IF;

  SELECT id, nombre INTO v_prov FROM proveedores
   WHERE id = NULLIF(p_cabecera->>'proveedor_id','')::uuid AND empresa_id = emp;
  IF v_prov.id IS NULL THEN RAISE EXCEPTION 'Proveedor no encontrado'; END IF;

  SELECT cta_proveedores INTO v_cfg FROM config_contable WHERE empresa_id = emp;
  IF v_cfg.cta_proveedores IS NULL THEN
    RAISE EXCEPTION 'Falta la cuenta de Proveedores en Imputación contable';
  END IF;

  -- Cabecera (el trigger asigna OP-nnnn)
  INSERT INTO ordenes_pago (empresa_id, fecha, proveedor_id, moneda, tipo_cambio, total, observaciones, created_by)
  VALUES (emp, v_fecha, v_prov.id, v_moneda, v_tc, v_total, NULLIF(p_cabecera->>'observaciones',''), auth.uid())
  RETURNING id, nro INTO v_op_id, v_nro;

  -- Medios
  FOR m IN SELECT * FROM jsonb_array_elements(p_medios) LOOP
    v_monto := ROUND(COALESCE((m->>'monto')::numeric, 0), 2);
    IF v_monto <= 0 THEN RAISE EXCEPTION 'Medio de pago con monto inválido'; END IF;
    IF COALESCE(m->>'tipo','') NOT IN ('caja','banco','cheque','tarjeta') THEN
      RAISE EXCEPTION 'Tipo de medio inválido: %', m->>'tipo';
    END IF;
    v_cta := NULLIF(m->>'cuenta_contable_id','')::uuid;
    IF v_cta IS NULL OR NOT EXISTS (SELECT 1 FROM cuentas_contables WHERE id = v_cta AND empresa_id = emp) THEN
      RAISE EXCEPTION 'El medio % no tiene cuenta contable (revisá Imputación contable / Bancos)', m->>'tipo';
    END IF;
    v_cheque_id := NULL;
    IF m->>'tipo' = 'cheque' THEN
      IF COALESCE(m->'cheque'->>'numero','') = '' OR COALESCE(m->'cheque'->>'fecha_pago','') = '' THEN
        RAISE EXCEPTION 'El cheque necesita número y fecha de pago';
      END IF;
      INSERT INTO cheques (empresa_id, tipo, numero, banco, echeq, proveedor_id, librador,
                           fecha_recepcion, fecha_pago, monto, moneda, tipo_cambio, estado, observaciones)
      VALUES (emp, 'emitido', m->'cheque'->>'numero', NULLIF(m->'cheque'->>'banco',''),
              COALESCE((m->'cheque'->>'echeq')::boolean, false), v_prov.id, v_prov.nombre,
              v_fecha, (m->'cheque'->>'fecha_pago')::date, v_monto, v_moneda,
              CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END, 'entregado',
              'Orden de pago ' || v_nro)
      RETURNING id INTO v_cheque_id;
    END IF;
    INSERT INTO orden_pago_medios (empresa_id, orden_pago_id, tipo, monto, cuenta_contable_id, cuenta_bancaria_id, cheque_id, detalle, orden)
    VALUES (emp, v_op_id, m->>'tipo', v_monto, v_cta, NULLIF(m->>'cuenta_bancaria_id','')::uuid, v_cheque_id,
            NULLIF(m->>'detalle',''), v_ord);
    v_ord := v_ord + 1;
    v_sum_medios := v_sum_medios + v_monto;
  END LOOP;
  IF abs(v_sum_medios - v_total) >= 0.01 THEN
    RAISE EXCEPTION 'Los medios de pago suman % y el total de la orden es %', v_sum_medios, v_total;
  END IF;

  -- Imputaciones (lock por factura: serializa OPs concurrentes sobre la misma)
  FOR i IN SELECT * FROM jsonb_array_elements(COALESCE(p_imputaciones, '[]'::jsonb)) LOOP
    v_monto := ROUND(COALESCE((i->>'monto')::numeric, 0), 2);
    v_mf := ROUND(COALESCE((i->>'monto_factura')::numeric, v_monto), 2);
    IF v_monto <= 0 OR v_mf <= 0 THEN RAISE EXCEPTION 'Imputación con monto inválido'; END IF;
    SELECT id, nro, tipo, proveedor_id, moneda INTO f FROM facturas_recibidas
     WHERE id = NULLIF(i->>'factura_id','')::uuid AND empresa_id = emp FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'Factura a imputar no encontrada'; END IF;
    IF COALESCE(f.tipo,'factura') <> 'factura' THEN RAISE EXCEPTION 'Sólo se imputan facturas (no NC/ND): %', f.nro; END IF;
    IF f.proveedor_id IS DISTINCT FROM v_prov.id THEN RAISE EXCEPTION 'La factura % no es de este proveedor', f.nro; END IF;
    v_saldo := public.saldo_factura_recibida(f.id);
    IF v_mf > v_saldo + 0.01 THEN
      RAISE EXCEPTION 'La factura % tiene saldo % % y se intenta imputar %', f.nro, f.moneda, v_saldo, v_mf;
    END IF;
    INSERT INTO orden_pago_imputaciones (empresa_id, orden_pago_id, factura_id, monto, monto_factura)
    VALUES (emp, v_op_id, f.id, v_monto, v_mf);
    v_sum_imput := v_sum_imput + v_monto;
  END LOOP;
  IF v_sum_imput > v_total + 0.01 THEN
    RAISE EXCEPTION 'Las imputaciones (%) superan el total de la orden (%)', v_sum_imput, v_total;
  END IF;

  -- Asiento: debe Proveedores por el total / haber cada medio agrupado por cuenta
  v_desc := 'Orden de pago ' || v_nro || ' — ' || v_prov.nombre;
  SELECT jsonb_build_array(jsonb_build_object(
           'cuenta_id', v_cfg.cta_proveedores, 'debe', v_total, 'haber', 0,
           'descripcion', 'Cancelación deuda ' || v_prov.nombre, 'orden', 0))
         || COALESCE(jsonb_agg(jsonb_build_object(
              'cuenta_id', g.cuenta_contable_id, 'debe', 0, 'haber', g.monto,
              'descripcion', g.detalle, 'orden', g.rn) ORDER BY g.rn), '[]'::jsonb)
    INTO v_lineas
  FROM (
    SELECT cuenta_contable_id, SUM(monto) AS monto,
           string_agg(DISTINCT CASE tipo WHEN 'caja' THEN 'Caja' WHEN 'banco' THEN 'Transferencia'
                                          WHEN 'cheque' THEN 'Cheque' ELSE 'Tarjeta' END, ' + ') || ' ' || v_prov.nombre AS detalle,
           row_number() OVER (ORDER BY MIN(orden)) AS rn
    FROM orden_pago_medios WHERE orden_pago_id = v_op_id GROUP BY cuenta_contable_id
  ) g;

  v_asiento := public.crear_asiento(jsonb_build_object(
    'fecha', v_fecha, 'descripcion', v_desc, 'comprobante_nro', v_nro,
    'tipo', 'auto-pago', 'origen_tipo', 'orden_pago', 'origen_id', v_op_id,
    'estado', 'confirmado', 'moneda', v_moneda,
    'tipo_cambio', CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END,
    'tc_tipo', CASE WHEN v_moneda = 'USD' THEN 'venta' ELSE NULL END,
    'proveedor_id', v_prov.id), v_lineas);

  UPDATE ordenes_pago SET asiento_id = (v_asiento->>'id')::uuid WHERE id = v_op_id;
  UPDATE cheques SET asiento_id = (v_asiento->>'id')::uuid
   WHERE id IN (SELECT cheque_id FROM orden_pago_medios WHERE orden_pago_id = v_op_id AND cheque_id IS NOT NULL);

  RETURN jsonb_build_object('id', v_op_id, 'nro', v_nro,
                            'asiento_id', v_asiento->>'id', 'asiento_numero', v_asiento->>'numero',
                            'a_cuenta', ROUND(v_total - v_sum_imput, 2));
END $$;
REVOKE ALL ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) TO authenticated;

-- ─── 7. RPC anular_orden_pago ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anular_orden_pago(p_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  o record; v_movidos int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(TRIM(p_motivo),'') = '' THEN RAISE EXCEPTION 'El motivo es obligatorio'; END IF;
  SELECT * INTO o FROM ordenes_pago WHERE id = p_id AND empresa_id = emp FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'Orden de pago no encontrada'; END IF;
  IF o.estado = 'anulada' THEN RAISE EXCEPTION 'La orden % ya está anulada', o.nro; END IF;

  SELECT count(*) INTO v_movidos FROM cheques c
   WHERE c.id IN (SELECT cheque_id FROM orden_pago_medios WHERE orden_pago_id = o.id AND cheque_id IS NOT NULL)
     AND c.estado NOT IN ('entregado','anulado');
  IF v_movidos > 0 THEN
    RAISE EXCEPTION 'La orden % tiene % cheque(s) ya debitado(s)/rechazado(s): no se puede anular', o.nro, v_movidos;
  END IF;

  UPDATE cheques SET estado = 'anulado', updated_at = now(),
         observaciones = COALESCE(observaciones,'') || ' · ANULADO con ' || o.nro
   WHERE id IN (SELECT cheque_id FROM orden_pago_medios WHERE orden_pago_id = o.id AND cheque_id IS NOT NULL)
     AND estado = 'entregado';
  IF o.asiento_id IS NOT NULL THEN
    UPDATE asientos SET estado = 'anulado' WHERE id = o.asiento_id AND empresa_id = emp;
  END IF;
  UPDATE ordenes_pago SET estado = 'anulada', motivo_anulacion = TRIM(p_motivo) WHERE id = o.id;
  RETURN jsonb_build_object('ok', true, 'nro', o.nro);
END $$;
REVOKE ALL ON FUNCTION public.anular_orden_pago(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_orden_pago(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_orden_pago(uuid, text) TO authenticated;

-- ─── 8. anular_factura_recibida RE-EMITIDA (base 062) ───────────────
-- Suma el guard de imputaciones vivas. El resto es idéntico a la 062.
CREATE OR REPLACE FUNCTION public.anular_factura_recibida(p_factura_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  f record; v_ncnd int; v_imput int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(TRIM(p_motivo),'') = '' THEN RAISE EXCEPTION 'El motivo es obligatorio'; END IF;
  SELECT * INTO f FROM facturas_recibidas WHERE id = p_factura_id AND empresa_id = emp FOR UPDATE;
  IF f.id IS NULL THEN RAISE EXCEPTION 'Factura no encontrada'; END IF;
  IF COALESCE(f.tipo,'factura') = 'factura' THEN
    SELECT count(*) INTO v_ncnd FROM facturas_recibidas
     WHERE empresa_id = emp AND factura_asociada_id = p_factura_id;
    IF v_ncnd > 0 THEN
      RAISE EXCEPTION 'La factura tiene % NC/ND asociada(s): anulalas primero', v_ncnd;
    END IF;
    SELECT count(*) INTO v_imput FROM orden_pago_imputaciones i
      JOIN ordenes_pago o ON o.id = i.orden_pago_id
     WHERE i.factura_id = p_factura_id AND o.estado = 'confirmada';
    IF v_imput > 0 THEN
      RAISE EXCEPTION 'La factura está imputada en % orden(es) de pago: anulá la OP primero', v_imput;
    END IF;
  END IF;
  UPDATE facturas_recibidas SET override_motivo = 'ANULADA: ' || TRIM(p_motivo)
   WHERE id = p_factura_id;
  IF f.asiento_id IS NOT NULL THEN
    UPDATE asientos SET estado = 'anulado' WHERE id = f.asiento_id AND empresa_id = emp;
  END IF;
  DELETE FROM orden_pago_imputaciones WHERE factura_id = p_factura_id;  -- sólo quedan las de OPs anuladas
  DELETE FROM facturas_recibidas WHERE id = p_factura_id;  -- cascade: tax lines (054)
  RETURN jsonb_build_object('ok', true, 'nro', f.nro, 'tipo', COALESCE(f.tipo,'factura'));
END $$;

-- ─── 9. Plan de cuentas: HSBC → BBVA ────────────────────────────────
UPDATE public.cuentas_contables SET nombre = 'BANCO BBVA'
 WHERE codigo = '111003' AND upper(nombre) = 'BANCO HSBC';

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT tablename FROM pg_tables WHERE tablename IN
--   ('ordenes_pago','orden_pago_medios','orden_pago_imputaciones');     -- 3 filas
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('registrar_orden_pago','anular_orden_pago','saldo_factura_recibida'); -- 3 filas
-- SELECT codigo, nombre FROM cuentas_contables WHERE codigo='111003';    -- BANCO BBVA
-- SELECT cta_tarjeta_credito FROM config_contable;                       -- no nulo
