-- ═══════════════════════════════════════════════════════════════════
-- MIGRACIÓN 062 — Facturas de compra: anulación + fecha contable
--
-- Feedback de Giuliano cargando las primeras facturas reales:
--   1. fecha_contable: la factura guarda fecha de EMISIÓN (la del
--      papel) y fecha CONTABLE (cuándo impacta en libros). El asiento
--      y la posición IVA van por la contable (factura de junio que
--      llega en agosto ⇒ libros de agosto).
--   2. registrar_factura_recibida RE-EMITIDA (base 061 — ediciones
--      futuras parten de acá): acepta p_factura->>'fecha_contable'
--      (fallback: fecha) y fecha el asiento con ella.
--   3. anular_factura_recibida: motivo obligatorio (queda en el
--      audit_log vía UPDATE previo), asiento → estado 'anulado'
--      (patrón anular_venta: NUNCA se borra), factura DELETE (las
--      tax lines caen por ON DELETE CASCADE de 054). Bloqueada si
--      hay NC/ND asociada. La OC y sus recepciones no se tocan.
--
-- Requiere: 061. Idempotente. Correr ANTES de deployar el frontend
-- y VERIFICAR que Run termine sin error (lección de la 058).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Doble fecha ──────────────────────────────────────────────────
ALTER TABLE public.facturas_recibidas
  ADD COLUMN IF NOT EXISTS fecha_contable date;
UPDATE public.facturas_recibidas SET fecha_contable = fecha WHERE fecha_contable IS NULL;
ALTER TABLE public.facturas_recibidas ALTER COLUMN fecha_contable SET NOT NULL;

-- ── 2. registrar_factura_recibida v062 (base 061 + fecha_contable) ──
CREATE OR REPLACE FUNCTION public.registrar_factura_recibida(
  p_factura   jsonb,
  p_impuestos jsonb   DEFAULT '[]'::jsonb,
  p_override  boolean DEFAULT false,
  p_motivo    text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
DECLARE
  v_empresa        uuid := public.current_empresa_id();
  v_cfg            public.config_contable%ROWTYPE;
  v_oc_id          uuid := NULLIF(p_factura->>'oc_id','')::uuid;
  v_prov_id        uuid := NULLIF(p_factura->>'proveedor_id','')::uuid;
  v_tipo           text := COALESCE(NULLIF(p_factura->>'tipo',''),'factura');
  v_letra          text := COALESCE(NULLIF(p_factura->>'letra',''),'A');
  v_neto           numeric := COALESCE((p_factura->>'neto')::numeric,0);
  v_no_gravado     numeric := COALESCE((p_factura->>'no_gravado')::numeric,0);
  v_exento         numeric := COALESCE((p_factura->>'exento')::numeric,0);
  v_iva            numeric := COALESCE((p_factura->>'iva')::numeric,0);
  v_total          numeric := (p_factura->>'total')::numeric;
  v_cta_imput      uuid := NULLIF(p_factura->>'cta_imputacion_id','')::uuid;
  v_asociada       uuid := NULLIF(p_factura->>'factura_asociada_id','')::uuid;
  v_sum_bases      numeric; v_sum_iva numeric;
  v_p_iva          numeric; v_p_iibb numeric; v_p_gcias numeric; v_p_otros numeric;
  v_sum_percep     numeric;
  v_neto_total     numeric;
  v_valor_recibido numeric := 0; v_dif numeric := 0; v_umbral numeric := 0;
  v_qty_recibida   numeric := 0;
  v_fact_mon       text := COALESCE(NULLIF(p_factura->>'moneda',''),'ARS');
  v_fact_tc        numeric := NULLIF(p_factura->>'tipo_cambio','')::numeric;
  v_oc_mon         text; v_oc_tc numeric; v_match_tc numeric;
  v_es_admin       boolean := public.current_usuario_es_admin();
  v_estado         text := 'ok';
  v_fact_id        uuid; v_asiento jsonb; v_oc_nro text; v_prov text;
  v_lineas         jsonb := '[]'::jsonb;
  v_orden          int := 0;
  v_desc_tipo      text;
  imp              jsonb;
  v_fecha_contable date;
BEGIN
  -- ── Validaciones básicas ──────────────────────────────────────────
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_factura->>'nro','')='' THEN RAISE EXCEPTION 'Falta el número de comprobante'; END IF;
  IF COALESCE(p_factura->>'fecha','')='' THEN RAISE EXCEPTION 'Falta la fecha'; END IF;
  v_fecha_contable := COALESCE(NULLIF(p_factura->>'fecha_contable',''), p_factura->>'fecha')::date;
  IF v_total IS NULL OR v_total <= 0 THEN RAISE EXCEPTION 'El total debe ser mayor a cero'; END IF;
  IF v_neto < 0 OR v_no_gravado < 0 OR v_exento < 0 THEN
    RAISE EXCEPTION 'Los importes se cargan en positivo; el signo lo da el tipo de comprobante';
  END IF;
  IF v_tipo NOT IN ('factura','nota_credito','nota_debito') THEN RAISE EXCEPTION 'Tipo inválido: %', v_tipo; END IF;
  IF v_letra NOT IN ('A','B','C','M','X') THEN RAISE EXCEPTION 'Letra inválida: %', v_letra; END IF;

  -- ── Sumas del array de impuestos ──────────────────────────────────
  SELECT COALESCE(SUM((i->>'base')::numeric),0), COALESCE(SUM((i->>'monto')::numeric),0)
    INTO v_sum_bases, v_sum_iva
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='iva';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_iva
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_iva';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_iibb
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_iibb';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_gcias
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='percepcion_ganancias';
  SELECT COALESCE(SUM((i->>'monto')::numeric),0) INTO v_p_otros
    FROM jsonb_array_elements(p_impuestos) i WHERE i->>'tipo'='otros';
  v_sum_percep := v_p_iva + v_p_iibb + v_p_gcias + v_p_otros;
  v_neto_total := v_neto + v_no_gravado + v_exento;

  -- ── Validación aritmética (autoritativa, tolerancia $0.01) ────────
  IF abs(v_neto - v_sum_bases) > 0.01 THEN
    RAISE EXCEPTION 'El neto % no coincide con la suma de bases de IVA %', v_neto, v_sum_bases;
  END IF;
  IF abs(v_iva - v_sum_iva) > 0.01 THEN
    RAISE EXCEPTION 'El IVA % no coincide con la suma del desglose %', v_iva, v_sum_iva;
  END IF;
  IF abs(v_total - (v_neto_total + v_sum_iva + v_sum_percep)) > 0.01 THEN
    RAISE EXCEPTION 'El total % no cierra: neto+no gravado+exento+IVA+percepciones = %',
      v_total, v_neto_total + v_sum_iva + v_sum_percep;
  END IF;
  IF v_letra NOT IN ('A','M') AND v_sum_iva > 0 THEN
    RAISE EXCEPTION 'Una factura letra % no discrimina IVA (el crédito no es computable)', v_letra;
  END IF;

  -- ── Validaciones por tipo de comprobante ──────────────────────────
  IF v_tipo IN ('nota_credito','nota_debito') THEN
    IF v_asociada IS NULL THEN RAISE EXCEPTION 'NC/ND requiere factura asociada'; END IF;
    PERFORM 1 FROM public.facturas_recibidas
      WHERE id = v_asociada AND empresa_id = v_empresa AND proveedor_id = v_prov_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Factura asociada inexistente o de otro proveedor'; END IF;
  END IF;
  IF (v_tipo <> 'factura' OR v_oc_id IS NULL) AND v_cta_imput IS NULL THEN
    RAISE EXCEPTION 'Comprobante sin OC (o NC/ND) requiere cuenta de imputación';
  END IF;
  IF v_p_otros > 0 AND v_cta_imput IS NULL THEN
    RAISE EXCEPTION 'Impuestos tipo "otros" requieren cuenta de imputación (van al costo)';
  END IF;

  -- ── Config contable ───────────────────────────────────────────────
  SELECT * INTO v_cfg FROM public.config_contable WHERE empresa_id = v_empresa;
  IF v_cfg.cta_proveedores IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_proveedores'; END IF;
  IF v_sum_iva > 0 AND v_cfg.cta_iva_credito IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_iva_credito'; END IF;
  IF v_tipo = 'factura' AND v_oc_id IS NOT NULL AND v_cfg.cta_gr_ir IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: falta cta_gr_ir (211009)';
  END IF;
  IF v_p_iva   > 0 AND v_cfg.cta_percep_iva       IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_iva'; END IF;
  IF v_p_iibb  > 0 AND v_cfg.cta_percep_iibb      IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_iibb'; END IF;
  IF v_p_gcias > 0 AND v_cfg.cta_percep_ganancias IS NULL THEN RAISE EXCEPTION 'Config contable incompleta: falta cta_percep_ganancias'; END IF;

  -- ── 3-way match (solo factura con OC) ─────────────────────────────
  -- 061: el valor recibido está en la moneda de la OC; se convierte a
  -- la moneda de la factura antes de comparar (TC factura > TC OC).
  IF v_tipo = 'factura' AND v_oc_id IS NOT NULL THEN
    SELECT COALESCE(SUM(precio_unitario * cantidad_recibida), 0),
           COALESCE(SUM(cantidad_recibida), 0)
      INTO v_valor_recibido, v_qty_recibida
      FROM public.oc_items WHERE oc_id = v_oc_id;

    IF v_qty_recibida <= 0 AND NOT (p_override AND v_es_admin) THEN
      RAISE EXCEPTION 'La OC no tiene recepciones registradas: registrá la recepción (botón Recibir) antes de cargar la factura, o registrá con override de un administrador.';
    END IF;

    IF COALESCE(v_cfg.precios_incluyen_iva, false) THEN
      v_valor_recibido := v_valor_recibido / (1 + COALESCE(v_cfg.iva_alicuota, 0));
    END IF;

    SELECT moneda, tipo_cambio INTO v_oc_mon, v_oc_tc
      FROM public.ordenes_compra WHERE id = v_oc_id;
    v_oc_mon := COALESCE(NULLIF(v_oc_mon,''),'ARS');
    IF v_oc_mon <> v_fact_mon THEN
      v_match_tc := COALESCE(NULLIF(v_fact_tc,0), NULLIF(v_oc_tc,0));
      IF v_match_tc IS NULL OR v_match_tc <= 0 THEN
        RAISE EXCEPTION 'La OC está en % y la factura en %: cargá el tipo de cambio para poder comparar el match.', v_oc_mon, v_fact_mon;
      END IF;
      v_valor_recibido := CASE WHEN v_oc_mon = 'USD'
        THEN v_valor_recibido * v_match_tc   -- USD (OC) → ARS (factura)
        ELSE v_valor_recibido / v_match_tc   -- ARS (OC) → USD (factura)
      END;
    END IF;

    v_dif    := abs(v_neto_total - v_valor_recibido);
    v_umbral := LEAST(v_valor_recibido * v_cfg.match_tolerancia_pct, v_cfg.match_tolerancia_monto);
    IF v_dif <= v_umbral THEN v_estado := 'ok';
    ELSIF p_override AND v_es_admin THEN v_estado := 'override';
    ELSE
      RAISE EXCEPTION 'Match fallido: neto factura % vs recibido % (dif %, umbral %). Requiere override de un administrador.',
        v_neto_total, round(v_valor_recibido,2), round(v_dif,2), round(v_umbral,2);
    END IF;
  END IF;

  SELECT nro    INTO v_oc_nro FROM public.ordenes_compra WHERE id = v_oc_id;
  SELECT nombre INTO v_prov   FROM public.proveedores     WHERE id = v_prov_id;
  v_desc_tipo := CASE v_tipo WHEN 'nota_credito' THEN 'NC' WHEN 'nota_debito' THEN 'ND' ELSE 'Factura' END;

  -- ── Armar líneas del asiento ──────────────────────────────────────
  -- Débito de imputación: GR/IR (factura con OC) o cta elegida (resto).
  -- 'otros' impuestos van al costo (misma cuenta de imputación).
  IF v_tipo = 'nota_credito' THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_proveedores,
      'debe', v_total, 'haber', 0, 'descripcion', COALESCE(v_prov,'Proveedor')||' (NC)', 'orden', v_orden);
    v_orden := v_orden + 1;
    IF v_neto_total + v_p_otros > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cta_imput,
        'debe', 0, 'haber', v_neto_total + v_p_otros, 'descripcion', 'NC '||(p_factura->>'nro'), 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_sum_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_iva_credito,
        'debe', 0, 'haber', v_sum_iva, 'descripcion', 'IVA CF s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iva,
        'debe', 0, 'haber', v_p_iva, 'descripcion', 'Percep. IVA s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iibb > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iibb,
        'debe', 0, 'haber', v_p_iibb, 'descripcion', 'Percep. IIBB s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_gcias > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_ganancias,
        'debe', 0, 'haber', v_p_gcias, 'descripcion', 'Percep. Gcias s/NC', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
  ELSE
    -- factura (con o sin OC) y nota de débito
    v_lineas := v_lineas || jsonb_build_object(
      'cuenta_id', CASE WHEN v_tipo='factura' AND v_oc_id IS NOT NULL THEN v_cfg.cta_gr_ir ELSE v_cta_imput END,
      'debe', v_neto_total + v_p_otros, 'haber', 0,
      'descripcion', CASE WHEN v_tipo='factura' AND v_oc_id IS NOT NULL
        THEN 'Cancela Facturas a recibir (GR/IR)' ELSE v_desc_tipo||' '||(p_factura->>'nro') END,
      'orden', v_orden);
    v_orden := v_orden + 1;
    IF v_sum_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_iva_credito,
        'debe', v_sum_iva, 'haber', 0, 'descripcion', 'IVA Crédito Fiscal', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iva > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iva,
        'debe', v_p_iva, 'haber', 0, 'descripcion', 'Percepción IVA sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_iibb > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_iibb,
        'debe', v_p_iibb, 'haber', 0, 'descripcion', 'Percepción IIBB sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    IF v_p_gcias > 0 THEN
      v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_percep_ganancias,
        'debe', v_p_gcias, 'haber', 0, 'descripcion', 'Percepción Ganancias sufrida', 'orden', v_orden);
      v_orden := v_orden + 1;
    END IF;
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cfg.cta_proveedores,
      'debe', 0, 'haber', v_total, 'descripcion', COALESCE(v_prov,'Proveedor'), 'orden', v_orden);
  END IF;

  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha',          v_fecha_contable,   -- 062: asiento por fecha CONTABLE
      'descripcion',    format('%s proveedor %s%s — %s', v_desc_tipo, p_factura->>'nro',
                          CASE WHEN v_oc_nro IS NOT NULL THEN ' s/OC '||v_oc_nro ELSE '' END,
                          COALESCE(v_prov,'?')),
      'comprobante_nro', p_factura->>'nro',
      'tipo',           'auto-compra',
      'origen_tipo',    'factura_recibida',
      'origen_id',      NULL,
      'estado',         'confirmado',
      'moneda',         v_fact_mon,
      'tipo_cambio',    v_fact_tc,
      'proveedor_id',   p_factura->>'proveedor_id'
    ),
    v_lineas,
    NULL
  );

  -- ── Insertar factura + tax lines ──────────────────────────────────
  INSERT INTO public.facturas_recibidas (
    empresa_id, proveedor_id, oc_id, nro, fecha, fecha_contable, fecha_vto,
    neto, iva, total, moneda, tipo_cambio,
    tipo, letra, no_gravado, exento, factura_asociada_id, cta_imputacion_id,
    estado_match, asiento_id, override_por, override_motivo, created_by
  ) VALUES (
    v_empresa, v_prov_id, v_oc_id,
    p_factura->>'nro', (p_factura->>'fecha')::date, v_fecha_contable, NULLIF(p_factura->>'fecha_vto','')::date,
    v_neto, v_iva, v_total,
    v_fact_mon,
    COALESCE(v_fact_tc, 1),
    v_tipo, v_letra, v_no_gravado, v_exento, v_asociada, v_cta_imput,
    v_estado, (v_asiento->>'id')::uuid,
    CASE WHEN v_estado='override' THEN auth.uid() ELSE NULL END,
    CASE WHEN v_estado='override' THEN p_motivo  ELSE NULL END,
    auth.uid()
  ) RETURNING id INTO v_fact_id;

  FOR imp IN SELECT * FROM jsonb_array_elements(p_impuestos) LOOP
    INSERT INTO public.factura_recibida_impuestos
      (empresa_id, factura_id, tipo, alicuota, base, monto, jurisdiccion)
    VALUES (
      v_empresa, v_fact_id, imp->>'tipo',
      NULLIF(imp->>'alicuota','')::numeric,
      COALESCE((imp->>'base')::numeric, 0),
      (imp->>'monto')::numeric,
      NULLIF(imp->>'jurisdiccion','')
    );
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_fact_id, 'estado_match', v_estado, 'asiento_id', v_asiento->>'id',
    'dif', v_dif, 'umbral', v_umbral, 'valor_recibido', v_valor_recibido
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, jsonb, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, jsonb, boolean, text) TO authenticated;

-- ── 3. anular_factura_recibida ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anular_factura_recibida(p_factura_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  f record; v_ncnd int;
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
  END IF;
  -- Motivo al audit trail (trg_audit registra el UPDATE con usuario) y después DELETE
  UPDATE facturas_recibidas SET override_motivo = 'ANULADA: ' || TRIM(p_motivo)
   WHERE id = p_factura_id;
  IF f.asiento_id IS NOT NULL THEN
    UPDATE asientos SET estado = 'anulado' WHERE id = f.asiento_id AND empresa_id = emp;
  END IF;
  DELETE FROM facturas_recibidas WHERE id = p_factura_id;  -- cascade: tax lines (054)
  RETURN jsonb_build_object('ok', true, 'nro', f.nro, 'tipo', COALESCE(f.tipo,'factura'));
END $$;

REVOKE ALL ON FUNCTION public.anular_factura_recibida(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_factura_recibida(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_factura_recibida(uuid, text) TO authenticated;

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='facturas_recibidas' AND column_name='fecha_contable';   -- 1 fila
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('anular_factura_recibida','registrar_factura_recibida');                 -- 2 filas
-- SELECT nro, fecha, fecha_contable FROM facturas_recibidas LIMIT 5;          -- contable = fecha (backfill)
