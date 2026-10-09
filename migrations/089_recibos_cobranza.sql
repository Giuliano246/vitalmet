-- ═══════════════════════════════════════════════════════════════════
-- 089 — RECIBOS DE COBRANZA (multi-medio + imputación a facturas emitidas)
-- ═══════════════════════════════════════════════════════════════════
-- Espejo de la 074 (órdenes de pago) del lado ventas.
--
-- Qué hace:
--   1. facturas_emitidas.cliente_id (backfill por venta y por CUIT) y
--      tc_usd (TC vendedor BNA con el que se pasó la venta a pesos; lo
--      manda el frontend al emitir — sirve para el equivalente en USD de
--      la cuenta corriente). Las viejas quedan con tc_usd NULL: el
--      frontend lo deduce de la venta.
--   2. Tabla recibos: cabecera del cobro (cliente, moneda/TC, total,
--      estado confirmado/anulado, asiento). El número es el REC-nnnn que
--      la 068 le pone al asiento auto-cobranza: una sola numeración para
--      los cobros viejos y los recibos nuevos.
--   3. Tabla recibo_medios: N medios (caja / banco = cuenta bancaria real
--      / cheque recibido, que entra a cartera en la misma transacción /
--      retención sufrida, que genera su fila en retenciones_sufridas).
--   4. Tabla recibo_imputaciones: M facturas canceladas total o
--      parcialmente. monto en moneda del recibo, monto_factura en la de
--      la factura (pesos). El remanente queda "a cuenta" del cliente.
--   5. saldo_factura_emitida(id): total − NC asociadas −
--      imputaciones de recibos confirmados (la ND se cobra como un
--      comprobante más).
--   6. RPC registrar_recibo(p_cabecera, p_medios, p_imputaciones): valida
--      Σ medios = total, Σ imputaciones ≤ total y cada imputación contra
--      el saldo (FOR UPDATE); arma el asiento (debe cada medio agrupado
--      por cuenta / haber Deudores) vía crear_asiento. Todo en UNA
--      transacción.
--   7. RPC anular_recibo(p_id, p_motivo): asiento → anulado, cheques del
--      recibo → anulado (bloquea si alguno ya se depositó, endosó o
--      rechazó), retenciones sufridas del recibo → borradas, recibo →
--      anulado con motivo. Las facturas vuelven a quedar con saldo.
--
-- No cambia registrar_cobro: los cobros sin imputación siguen andando y
-- la cuenta corriente los aplica a la factura más vieja.
--
-- Batería RLS completa, molde de la 074. Requiere: 016, 027 (cheques),
-- 035 (cuentas_bancarias), 056 (retenciones_sufridas), 067
-- (crear_asiento), 068 (REC-nnnn), 073/074.
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

-- ─── 1. facturas_emitidas: cliente y TC de la conversión ────────────
ALTER TABLE public.facturas_emitidas
  ADD COLUMN IF NOT EXISTS cliente_id uuid REFERENCES public.clientes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS tc_usd     numeric;
COMMENT ON COLUMN public.facturas_emitidas.cliente_id IS 'Cliente del comprobante (mig 089). Lo manda el frontend al emitir; backfill por venta y por CUIT.';
COMMENT ON COLUMN public.facturas_emitidas.tc_usd IS 'TC vendedor BNA usado para pasar la venta en USD a pesos (mig 089). NULL = facturado directo en pesos o anterior a la 089.';
CREATE INDEX IF NOT EXISTS facturas_emitidas_cliente_idx ON public.facturas_emitidas(cliente_id);

UPDATE public.facturas_emitidas f SET cliente_id = v.cliente_id
  FROM public.ventas v
 WHERE f.cliente_id IS NULL AND f.venta_id = v.id AND v.cliente_id IS NOT NULL;
-- NC/ND: el cliente de la factura asociada
UPDATE public.facturas_emitidas f SET cliente_id = a.cliente_id
  FROM public.facturas_emitidas a
 WHERE f.cliente_id IS NULL AND f.factura_asociada_id = a.id AND a.cliente_id IS NOT NULL;
-- Facturas directas: por CUIT (sólo si un único cliente tiene ese CUIT)
UPDATE public.facturas_emitidas f SET cliente_id = c.id
  FROM (SELECT empresa_id, regexp_replace(COALESCE(cuit,''), '\D', '', 'g') AS cuit_n, MIN(id::text)::uuid AS id
          FROM public.clientes GROUP BY 1, 2 HAVING COUNT(*) = 1) c
 WHERE f.cliente_id IS NULL AND f.empresa_id = c.empresa_id
   AND length(c.cuit_n) = 11 AND regexp_replace(COALESCE(f.doc_nro,''), '\D', '', 'g') = c.cuit_n;

-- ─── 2. recibos ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.recibos (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid          NOT NULL,
  nro              text,                                   -- REC-nnnn (el del asiento, trigger 068)
  fecha            date          NOT NULL,
  cliente_id       uuid          NOT NULL REFERENCES public.clientes(id) ON DELETE RESTRICT,
  moneda           text          NOT NULL DEFAULT 'ARS' CHECK (moneda IN ('ARS','USD')),
  tipo_cambio      numeric,
  total            numeric(18,2) NOT NULL CHECK (total > 0),
  estado           text          NOT NULL DEFAULT 'confirmado' CHECK (estado IN ('confirmado','anulado')),
  asiento_id       uuid          REFERENCES public.asientos(id) ON DELETE SET NULL,
  observaciones    text,
  motivo_anulacion text,
  created_by       uuid,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  updated_at       timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS recibos_empresa_idx ON public.recibos(empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS recibos_cliente_idx ON public.recibos(cliente_id);
CREATE INDEX IF NOT EXISTS recibos_asiento_idx ON public.recibos(asiento_id);
COMMENT ON TABLE public.recibos IS 'Recibo de cobranza a cliente (mig 089): N medios + M imputaciones a facturas emitidas; el remanente queda a cuenta. El asiento lo arma registrar_recibo.';
SELECT pg_temp.aplicar_bateria('recibos');

-- ─── 3. recibo_medios ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.recibo_medios (
  id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid          NOT NULL,
  recibo_id          uuid          NOT NULL REFERENCES public.recibos(id) ON DELETE CASCADE,
  tipo               text          NOT NULL CHECK (tipo IN ('caja','banco','cheque','retencion')),
  monto              numeric(18,2) NOT NULL CHECK (monto > 0),
  cuenta_contable_id uuid          NOT NULL REFERENCES public.cuentas_contables(id) ON DELETE RESTRICT,
  cuenta_bancaria_id uuid          REFERENCES public.cuentas_bancarias(id) ON DELETE SET NULL,
  cheque_id          uuid          REFERENCES public.cheques(id) ON DELETE SET NULL,
  retencion          jsonb,                                -- {tipo, certificado_nro, jurisdiccion}
  detalle            text,
  orden              int           NOT NULL DEFAULT 0,
  created_at         timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS recibo_medios_recibo_idx ON public.recibo_medios(recibo_id);
COMMENT ON TABLE public.recibo_medios IS 'Valores recibidos en un recibo (mig 089): caja, banco, cheque de terceros (cheque_id creado en la misma transacción) o retención sufrida.';
SELECT pg_temp.aplicar_bateria('recibo_medios');

-- ─── 4. recibo_imputaciones ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.recibo_imputaciones (
  id             uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid          NOT NULL,
  recibo_id      uuid          NOT NULL REFERENCES public.recibos(id) ON DELETE CASCADE,
  factura_id     uuid          NOT NULL REFERENCES public.facturas_emitidas(id) ON DELETE RESTRICT,
  monto          numeric(18,2) NOT NULL CHECK (monto > 0),          -- moneda del recibo
  monto_factura  numeric(18,2) NOT NULL CHECK (monto_factura > 0),  -- moneda de la factura (pesos)
  created_at     timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT recibo_imputaciones_uq UNIQUE (recibo_id, factura_id)
);
CREATE INDEX IF NOT EXISTS recibo_imput_factura_idx ON public.recibo_imputaciones(factura_id);
COMMENT ON TABLE public.recibo_imputaciones IS 'Facturas emitidas canceladas (total o parcialmente) por un recibo (mig 089). Sólo cuentan las de recibos en estado confirmado.';
SELECT pg_temp.aplicar_bateria('recibo_imputaciones');

-- ─── 5. Saldo pendiente de una factura emitida ──────────────────────
-- Facturas y notas de débito (tipos 1,2,6,7,11,12,51,52). En pesos.
CREATE OR REPLACE FUNCTION public.saldo_factura_emitida(p_factura_id uuid)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT ROUND(
    f.imp_total
    - COALESCE((SELECT SUM(n.imp_total) FROM facturas_emitidas n
                 WHERE n.factura_asociada_id = f.id AND n.tipo_comprobante IN (3,8,13,53)), 0)
    - COALESCE((SELECT SUM(i.monto_factura) FROM recibo_imputaciones i
                 JOIN recibos r ON r.id = i.recibo_id
                 WHERE i.factura_id = f.id AND r.estado = 'confirmado'), 0)
  , 2)
  FROM facturas_emitidas f WHERE f.id = p_factura_id;
$$;
REVOKE ALL ON FUNCTION public.saldo_factura_emitida(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.saldo_factura_emitida(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.saldo_factura_emitida(uuid) TO authenticated;

-- ─── 6. RPC registrar_recibo ────────────────────────────────────────
-- p_cabecera: {fecha, cliente_id, moneda, tipo_cambio, total, observaciones}
-- p_medios:   [{tipo, monto, cuenta_contable_id, cuenta_bancaria_id, detalle,
--               cheque:{numero, banco, fecha_pago, echeq, librador},
--               retencion:{tipo, certificado_nro, jurisdiccion}}]
-- p_imputaciones: [{factura_id, monto, monto_factura}]
CREATE OR REPLACE FUNCTION public.registrar_recibo(p_cabecera jsonb, p_medios jsonb, p_imputaciones jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_cli record; v_cfg record; v_rec_id uuid; v_nro text;
  v_moneda text := COALESCE(p_cabecera->>'moneda', 'ARS');
  v_tc numeric := NULLIF(p_cabecera->>'tipo_cambio', '')::numeric;
  v_total numeric := ROUND(COALESCE((p_cabecera->>'total')::numeric, 0), 2);
  v_fecha date := (p_cabecera->>'fecha')::date;
  v_sum_medios numeric := 0; v_sum_imput numeric := 0;
  m jsonb; i jsonb; r jsonb; v_monto numeric; v_cta uuid; v_cheque_id uuid; v_ord int := 0;
  f record; v_saldo numeric; v_mf numeric;
  v_lineas jsonb; v_asiento jsonb; v_asiento_id uuid; v_ret_n int := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF v_fecha IS NULL THEN RAISE EXCEPTION 'Falta la fecha del recibo'; END IF;
  IF v_total <= 0 THEN RAISE EXCEPTION 'El total del recibo debe ser mayor a cero'; END IF;
  IF v_moneda NOT IN ('ARS','USD') THEN RAISE EXCEPTION 'Moneda inválida: %', v_moneda; END IF;
  IF v_moneda = 'USD' AND COALESCE(v_tc, 0) <= 0 THEN RAISE EXCEPTION 'Un recibo en USD necesita tipo de cambio'; END IF;
  IF COALESCE(jsonb_array_length(COALESCE(p_medios, '[]'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'El recibo necesita al menos un valor recibido';
  END IF;

  SELECT id, nombre INTO v_cli FROM clientes
   WHERE id = NULLIF(p_cabecera->>'cliente_id','')::uuid AND empresa_id = emp;
  IF v_cli.id IS NULL THEN RAISE EXCEPTION 'Cliente no encontrado'; END IF;

  SELECT cta_deudores INTO v_cfg FROM config_contable WHERE empresa_id = emp;
  IF v_cfg.cta_deudores IS NULL THEN
    RAISE EXCEPTION 'Falta la cuenta de Deudores en Imputación contable';
  END IF;

  INSERT INTO recibos (empresa_id, fecha, cliente_id, moneda, tipo_cambio, total, observaciones, created_by)
  VALUES (emp, v_fecha, v_cli.id, v_moneda, v_tc, v_total, NULLIF(p_cabecera->>'observaciones',''), auth.uid())
  RETURNING id INTO v_rec_id;

  -- Medios
  FOR m IN SELECT * FROM jsonb_array_elements(p_medios) LOOP
    v_monto := ROUND(COALESCE((m->>'monto')::numeric, 0), 2);
    IF v_monto <= 0 THEN RAISE EXCEPTION 'Valor recibido con monto inválido'; END IF;
    IF COALESCE(m->>'tipo','') NOT IN ('caja','banco','cheque','retencion') THEN
      RAISE EXCEPTION 'Tipo de valor inválido: %', m->>'tipo';
    END IF;
    v_cta := NULLIF(m->>'cuenta_contable_id','')::uuid;
    IF v_cta IS NULL OR NOT EXISTS (SELECT 1 FROM cuentas_contables WHERE id = v_cta AND empresa_id = emp) THEN
      RAISE EXCEPTION 'El valor % no tiene cuenta contable (revisá Imputación contable / Bancos)', m->>'tipo';
    END IF;
    v_cheque_id := NULL;
    IF m->>'tipo' = 'cheque' THEN
      IF COALESCE(m->'cheque'->>'numero','') = '' OR COALESCE(m->'cheque'->>'fecha_pago','') = '' THEN
        RAISE EXCEPTION 'El cheque necesita número y fecha de pago';
      END IF;
      INSERT INTO cheques (empresa_id, tipo, numero, banco, echeq, cliente_id, librador,
                           fecha_recepcion, fecha_pago, monto, moneda, tipo_cambio, estado, observaciones)
      VALUES (emp, 'recibido', m->'cheque'->>'numero', NULLIF(m->'cheque'->>'banco',''),
              COALESCE((m->'cheque'->>'echeq')::boolean, false), v_cli.id,
              COALESCE(NULLIF(m->'cheque'->>'librador',''), v_cli.nombre),
              v_fecha, (m->'cheque'->>'fecha_pago')::date, v_monto, v_moneda,
              CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END, 'en_cartera', 'Recibo de cobranza')
      RETURNING id INTO v_cheque_id;
    END IF;
    IF m->>'tipo' = 'retencion' THEN
      r := m->'retencion';
      IF r IS NULL OR jsonb_typeof(r) <> 'object' OR COALESCE(r->>'tipo','') NOT IN ('ganancias','iibb','suss','iva') THEN
        RAISE EXCEPTION 'La retención necesita el impuesto';
      END IF;
      IF r->>'tipo' = 'iibb' AND COALESCE(r->>'jurisdiccion','') = '' THEN
        RAISE EXCEPTION 'La retención de IIBB requiere jurisdicción';
      END IF;
      v_ret_n := v_ret_n + 1;
    END IF;
    INSERT INTO recibo_medios (empresa_id, recibo_id, tipo, monto, cuenta_contable_id, cuenta_bancaria_id, cheque_id, retencion, detalle, orden)
    VALUES (emp, v_rec_id, m->>'tipo', v_monto, v_cta, NULLIF(m->>'cuenta_bancaria_id','')::uuid, v_cheque_id,
            CASE WHEN m->>'tipo' = 'retencion' THEN m->'retencion' ELSE NULL END, NULLIF(m->>'detalle',''), v_ord);
    v_ord := v_ord + 1;
    v_sum_medios := v_sum_medios + v_monto;
  END LOOP;
  IF abs(v_sum_medios - v_total) >= 0.01 THEN
    RAISE EXCEPTION 'Los valores recibidos suman % y el total del recibo es %', v_sum_medios, v_total;
  END IF;

  -- Imputaciones (lock por factura: serializa recibos concurrentes sobre la misma)
  FOR i IN SELECT * FROM jsonb_array_elements(COALESCE(p_imputaciones, '[]'::jsonb)) LOOP
    v_monto := ROUND(COALESCE((i->>'monto')::numeric, 0), 2);
    v_mf := ROUND(COALESCE((i->>'monto_factura')::numeric, v_monto), 2);
    IF v_monto <= 0 OR v_mf <= 0 THEN RAISE EXCEPTION 'Imputación con monto inválido'; END IF;
    SELECT id, tipo_comprobante, punto_venta, numero, cliente_id INTO f FROM facturas_emitidas
     WHERE id = NULLIF(i->>'factura_id','')::uuid AND empresa_id = emp FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'Factura a imputar no encontrada'; END IF;
    IF f.tipo_comprobante IN (3,8,13,53) THEN RAISE EXCEPTION 'Una nota de crédito no se cobra: %-%', f.punto_venta, f.numero; END IF;
    IF f.cliente_id IS NOT NULL AND f.cliente_id <> v_cli.id THEN
      RAISE EXCEPTION 'El comprobante %-% no es de este cliente', f.punto_venta, f.numero;
    END IF;
    v_saldo := public.saldo_factura_emitida(f.id);
    IF v_mf > v_saldo + 0.01 THEN
      RAISE EXCEPTION 'El comprobante %-% tiene saldo $ % y se intenta imputar $ %', f.punto_venta, f.numero, v_saldo, v_mf;
    END IF;
    IF f.cliente_id IS NULL THEN UPDATE facturas_emitidas SET cliente_id = v_cli.id WHERE id = f.id; END IF;
    INSERT INTO recibo_imputaciones (empresa_id, recibo_id, factura_id, monto, monto_factura)
    VALUES (emp, v_rec_id, f.id, v_monto, v_mf);
    v_sum_imput := v_sum_imput + v_monto;
  END LOOP;
  IF v_sum_imput > v_total + 0.01 THEN
    RAISE EXCEPTION 'Las imputaciones (%) superan el total del recibo (%)', v_sum_imput, v_total;
  END IF;

  -- Asiento: debe cada medio agrupado por cuenta / haber Deudores por el total.
  -- comprobante_nro vacío → el trigger de la 068 asigna el REC-nnnn.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
              'cuenta_id', g.cuenta_contable_id, 'debe', g.monto, 'haber', 0,
              'descripcion', g.detalle, 'orden', g.rn - 1) ORDER BY g.rn), '[]'::jsonb)
         || jsonb_build_array(jsonb_build_object(
              'cuenta_id', v_cfg.cta_deudores, 'debe', 0, 'haber', v_total,
              'descripcion', 'Cancelación deuda ' || v_cli.nombre, 'orden', 99))
    INTO v_lineas
  FROM (
    SELECT cuenta_contable_id, SUM(monto) AS monto,
           string_agg(DISTINCT CASE tipo WHEN 'caja' THEN 'Caja' WHEN 'banco' THEN 'Transferencia'
                                          WHEN 'cheque' THEN 'Cheque' ELSE 'Retención' END, ' + ') || ' ' || v_cli.nombre AS detalle,
           row_number() OVER (ORDER BY MIN(orden)) AS rn
    FROM recibo_medios WHERE recibo_id = v_rec_id GROUP BY cuenta_contable_id
  ) g;

  v_asiento := public.crear_asiento(jsonb_build_object(
    'fecha', v_fecha,
    'descripcion', 'Cobro de ' || v_cli.nombre || COALESCE(' — ' || NULLIF(p_cabecera->>'observaciones',''), ''),
    'tipo', 'auto-cobranza', 'origen_tipo', 'recibo', 'origen_id', v_rec_id,
    'estado', 'confirmado', 'moneda', v_moneda,
    'tipo_cambio', CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END,
    'tc_tipo', CASE WHEN v_moneda = 'USD' THEN 'venta' ELSE NULL END,
    'cliente_id', v_cli.id), v_lineas);
  v_asiento_id := (v_asiento->>'id')::uuid;
  SELECT comprobante_nro INTO v_nro FROM asientos WHERE id = v_asiento_id;

  UPDATE recibos SET asiento_id = v_asiento_id, nro = v_nro WHERE id = v_rec_id;
  UPDATE cheques SET asiento_id = v_asiento_id,
         observaciones = 'Recibo ' || COALESCE(v_nro, '')
   WHERE id IN (SELECT cheque_id FROM recibo_medios WHERE recibo_id = v_rec_id AND cheque_id IS NOT NULL);

  -- Retenciones sufridas: una fila por medio 'retencion' (certificado del cliente)
  INSERT INTO retenciones_sufridas (empresa_id, cliente_id, fecha, tipo, certificado_nro, jurisdiccion,
                                    monto, moneda, tipo_cambio, asiento_id, created_by)
  SELECT emp, v_cli.id, v_fecha, rm.retencion->>'tipo', NULLIF(rm.retencion->>'certificado_nro',''),
         NULLIF(rm.retencion->>'jurisdiccion',''), rm.monto, v_moneda,
         CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END, v_asiento_id, auth.uid()
    FROM recibo_medios rm WHERE rm.recibo_id = v_rec_id AND rm.tipo = 'retencion';

  RETURN jsonb_build_object('id', v_rec_id, 'nro', v_nro,
                            'asiento_id', v_asiento_id, 'asiento_numero', v_asiento->>'numero',
                            'a_cuenta', ROUND(v_total - v_sum_imput, 2), 'retenciones', v_ret_n);
END $$;
REVOKE ALL ON FUNCTION public.registrar_recibo(jsonb, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_recibo(jsonb, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_recibo(jsonb, jsonb, jsonb) TO authenticated;

-- ─── 7. RPC anular_recibo ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anular_recibo(p_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  o record; v_movidos int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(TRIM(p_motivo),'') = '' THEN RAISE EXCEPTION 'El motivo es obligatorio'; END IF;
  SELECT * INTO o FROM recibos WHERE id = p_id AND empresa_id = emp FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'Recibo no encontrado'; END IF;
  IF o.estado = 'anulado' THEN RAISE EXCEPTION 'El recibo % ya está anulado', o.nro; END IF;

  SELECT count(*) INTO v_movidos FROM cheques c
   WHERE c.id IN (SELECT cheque_id FROM recibo_medios WHERE recibo_id = o.id AND cheque_id IS NOT NULL)
     AND c.estado NOT IN ('en_cartera','anulado');
  IF v_movidos > 0 THEN
    RAISE EXCEPTION 'El recibo % tiene % cheque(s) ya depositado(s), endosado(s) o rechazado(s): no se puede anular', o.nro, v_movidos;
  END IF;

  UPDATE cheques SET estado = 'anulado', updated_at = now(),
         observaciones = COALESCE(observaciones,'') || ' · ANULADO con ' || COALESCE(o.nro,'el recibo')
   WHERE id IN (SELECT cheque_id FROM recibo_medios WHERE recibo_id = o.id AND cheque_id IS NOT NULL)
     AND estado = 'en_cartera';
  IF o.asiento_id IS NOT NULL THEN
    DELETE FROM retenciones_sufridas WHERE asiento_id = o.asiento_id AND empresa_id = emp;
    UPDATE asientos SET estado = 'anulado' WHERE id = o.asiento_id AND empresa_id = emp;
  END IF;
  UPDATE recibos SET estado = 'anulado', motivo_anulacion = TRIM(p_motivo), updated_at = now() WHERE id = o.id;
  RETURN jsonb_build_object('ok', true, 'nro', o.nro);
END $$;
REVOKE ALL ON FUNCTION public.anular_recibo(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_recibo(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_recibo(uuid, text) TO authenticated;

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT tablename FROM pg_tables WHERE tablename IN ('recibos','recibo_medios','recibo_imputaciones'); -- 3 filas
-- SELECT count(*) FILTER (WHERE cliente_id IS NULL) AS sin_cliente, count(*) AS total FROM facturas_emitidas; -- sin_cliente bajo
-- SELECT id, imp_total, public.saldo_factura_emitida(id) FROM facturas_emitidas ORDER BY fecha DESC LIMIT 5; -- saldo = total (o menos su NC)
-- SELECT proname FROM pg_proc WHERE proname IN ('registrar_recibo','anular_recibo','saldo_factura_emitida'); -- 3 filas
