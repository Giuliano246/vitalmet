BEGIN;
CREATE OR REPLACE FUNCTION public.crear_asiento_extracto(p_extracto_id uuid,p_contracuenta_id uuid,p_tipo_cambio numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE e extracto_bancario%rowtype; b cuentas_bancarias%rowtype; r jsonb; lid uuid; aid uuid; monto numeric;
BEGIN
 SELECT * INTO e FROM extracto_bancario WHERE id=p_extracto_id AND empresa_id=current_empresa_id() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Extracto inexistente o sin permiso'; END IF;
 IF e.conciliado AND e.asiento_linea_id IS NOT NULL THEN RETURN public.conciliar_extracto(e.id,e.asiento_linea_id); END IF;
 SELECT * INTO b FROM cuentas_bancarias WHERE id=e.cuenta_bancaria_id FOR SHARE;
 IF NOT FOUND OR b.empresa_id IS DISTINCT FROM e.empresa_id OR b.cuenta_contable_id IS NULL THEN RAISE EXCEPTION 'Falta cuenta contable bancaria'; END IF;
 IF p_contracuenta_id IS NULL OR p_contracuenta_id=b.cuenta_contable_id OR NOT EXISTS(SELECT 1 FROM cuentas_contables WHERE id=p_contracuenta_id AND empresa_id=e.empresa_id AND imputable=true) THEN RAISE EXCEPTION 'Contracuenta inválida'; END IF;
 IF b.moneda IS NULL OR b.moneda NOT IN ('ARS','USD') THEN RAISE EXCEPTION 'Moneda inválida'; END IF;
 IF b.moneda='USD' AND (p_tipo_cambio IS NULL OR p_tipo_cambio<=0 OR p_tipo_cambio::text IN ('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Ingresá el tipo de cambio del movimiento'; END IF;
 IF e.importe IS NULL OR e.importe=0 OR e.importe::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Importe inválido'; END IF;
 -- Recupera un asiento previo de este origen si una versión anterior dejó el vínculo incompleto.
 SELECT id INTO aid FROM asientos WHERE empresa_id=e.empresa_id AND origen_tipo='extracto_bancario' AND origen_id=e.id AND estado='confirmado';
 IF aid IS NULL THEN
   monto:=abs(e.importe);
   r:=public.crear_asiento(jsonb_build_object('fecha',e.fecha,'descripcion','Banco: '||coalesce(e.descripcion,'Movimiento bancario'),'comprobante_nro',e.referencia,'tipo','auto-banco','origen_tipo','extracto_bancario','origen_id',e.id,'estado','confirmado','moneda',b.moneda,'tipo_cambio',CASE WHEN b.moneda='USD' THEN p_tipo_cambio ELSE 1 END,'tc_tipo',NULL),
     jsonb_build_array(jsonb_build_object('cuenta_id',b.cuenta_contable_id,'debe',CASE WHEN e.importe>0 THEN monto ELSE 0 END,'haber',CASE WHEN e.importe<0 THEN monto ELSE 0 END),jsonb_build_object('cuenta_id',p_contracuenta_id,'debe',CASE WHEN e.importe<0 THEN monto ELSE 0 END,'haber',CASE WHEN e.importe>0 THEN monto ELSE 0 END)));
   aid:=(r->>'id')::uuid;
 END IF;
 SELECT id INTO lid FROM asiento_lineas WHERE asiento_id=aid AND cuenta_id=b.cuenta_contable_id;
 RETURN public.conciliar_extracto(e.id,lid);
END $$;


COMMIT;

