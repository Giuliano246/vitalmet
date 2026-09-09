BEGIN;

CREATE OR REPLACE FUNCTION public.conciliar_extracto(p_extracto_id uuid, p_asiento_linea_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE
 e extracto_bancario%rowtype; l asiento_lineas%rowtype; a asientos%rowtype;
 b cuentas_bancarias%rowtype; monto numeric;
BEGIN
 IF current_empresa_id() IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
 SELECT * INTO e FROM extracto_bancario WHERE id=p_extracto_id AND empresa_id=current_empresa_id() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Extracto inexistente o sin permiso'; END IF;
 IF e.conciliado AND e.asiento_linea_id IS DISTINCT FROM p_asiento_linea_id THEN RAISE EXCEPTION 'Desconciliá el movimiento antes de cambiar su vínculo'; END IF;
 SELECT * INTO l FROM asiento_lineas WHERE id=p_asiento_linea_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Línea inexistente o sin permiso'; END IF;
 SELECT * INTO a FROM asientos WHERE id=l.asiento_id FOR UPDATE;
 IF NOT FOUND OR a.estado IS DISTINCT FROM 'confirmado' OR a.empresa_id IS DISTINCT FROM e.empresa_id THEN RAISE EXCEPTION 'Se requiere un asiento confirmado de la misma empresa'; END IF;
 SELECT * INTO b FROM cuentas_bancarias WHERE id=e.cuenta_bancaria_id FOR SHARE;
 IF NOT FOUND OR b.empresa_id IS DISTINCT FROM e.empresa_id OR b.cuenta_contable_id IS NULL OR b.cuenta_contable_id IS DISTINCT FROM l.cuenta_id THEN RAISE EXCEPTION 'Cuenta bancaria incompatible'; END IF;
 IF a.moneda IS NULL OR b.moneda IS NULL OR a.moneda NOT IN ('ARS','USD') OR b.moneda NOT IN ('ARS','USD') THEN RAISE EXCEPTION 'Moneda inválida'; END IF;
 IF a.moneda='USD' OR a.moneda<>b.moneda THEN
   IF a.tipo_cambio IS NULL OR a.tipo_cambio<=0 OR a.tipo_cambio::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Tipo de cambio inválido'; END IF;
 END IF;
 IF l.debe IS NULL OR l.haber IS NULL OR e.importe IS NULL THEN RAISE EXCEPTION 'Importe requerido'; END IF;
 monto:=l.debe-l.haber;
 IF a.moneda<>b.moneda THEN monto:=CASE WHEN b.moneda='ARS' THEN monto*a.tipo_cambio ELSE monto/a.tipo_cambio END; END IF;
 IF monto::text IN ('NaN','Infinity','-Infinity') OR e.importe::text IN ('NaN','Infinity','-Infinity') OR e.importe=0 OR round(monto,2)<>round(e.importe,2) THEN RAISE EXCEPTION 'El importe y el signo no coinciden con el extracto'; END IF;
 IF EXISTS(SELECT 1 FROM extracto_bancario WHERE asiento_linea_id=l.id AND id<>e.id) THEN RAISE EXCEPTION 'Línea ya conciliada'; END IF;
 UPDATE extracto_bancario SET conciliado=true,asiento_linea_id=l.id WHERE id=e.id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sin permiso para conciliar'; END IF;
 RETURN jsonb_build_object('extracto_id',e.id,'asiento_linea_id',l.id,'conciliado',true);
END $$;

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
   r:=public.crear_asiento(jsonb_build_object('fecha',e.fecha,'descripcion','Banco: '||coalesce(e.descripcion,'Movimiento bancario'),'comprobante_nro',e.referencia,'tipo','auto-banco','origen_tipo','extracto_bancario','origen_id',e.id,'estado','confirmado','moneda',b.moneda,'tipo_cambio',CASE WHEN b.moneda='USD' THEN p_tipo_cambio ELSE 1 END,'tc_tipo','oficial'),
     jsonb_build_array(jsonb_build_object('cuenta_id',b.cuenta_contable_id,'debe',CASE WHEN e.importe>0 THEN monto ELSE 0 END,'haber',CASE WHEN e.importe<0 THEN monto ELSE 0 END),jsonb_build_object('cuenta_id',p_contracuenta_id,'debe',CASE WHEN e.importe<0 THEN monto ELSE 0 END,'haber',CASE WHEN e.importe>0 THEN monto ELSE 0 END)));
   aid:=(r->>'id')::uuid;
 END IF;
 SELECT id INTO lid FROM asiento_lineas WHERE asiento_id=aid AND cuenta_id=b.cuenta_contable_id;
 RETURN public.conciliar_extracto(e.id,lid);
END $$;

-- Revisión contra datos actuales, también para llamadas directas a la API.
CREATE OR REPLACE FUNCTION public.revisar_periodo_al_cerrar()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE d date; h date;
BEGIN
 IF NEW.estado IS DISTINCT FROM 'cerrado' THEN RETURN NEW; END IF;
 d:=make_date(NEW.anio,NEW.mes,1); h:=(d+interval '1 month')::date;
 IF EXISTS(SELECT 1 FROM asientos WHERE empresa_id=NEW.empresa_id AND fecha>=d AND fecha<h AND coalesce(estado,'borrador')='borrador') THEN RAISE EXCEPTION 'Hay asientos en borrador'; END IF;
 IF EXISTS(SELECT 1 FROM facturas_emitidas f WHERE f.empresa_id=NEW.empresa_id AND f.fecha>=d AND f.fecha<h AND nullif(f.cae,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM asientos a WHERE a.empresa_id=f.empresa_id AND a.origen_id=f.id AND a.origen_tipo IN ('factura','nota-credito','nota-debito') AND a.estado='confirmado')) THEN RAISE EXCEPTION 'Hay comprobantes sin asiento confirmado'; END IF;
 IF EXISTS(SELECT 1 FROM extracto_bancario WHERE empresa_id=NEW.empresa_id AND fecha>=d AND fecha<h AND (conciliado IS DISTINCT FROM true OR asiento_linea_id IS NULL)) THEN RAISE EXCEPTION 'Hay movimientos bancarios pendientes'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_revision_cierre ON public.periodos_contables;
CREATE TRIGGER trg_revision_cierre BEFORE INSERT OR UPDATE OF estado ON public.periodos_contables FOR EACH ROW EXECUTE FUNCTION public.revisar_periodo_al_cerrar();

CREATE TABLE IF NOT EXISTS public.efe_clasificaciones (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 linea_id uuid NOT NULL REFERENCES public.asiento_lineas(id) ON DELETE CASCADE,
 categoria text NOT NULL CHECK(categoria IN ('op.cobros_clientes','op.pagos_proveedores','op.sueldos_cargas','op.impuestos','op.otros','inv.altas','inv.bajas','inv.inversiones','fin.prestamos','fin.aportes_dividendos')),
 PRIMARY KEY(empresa_id,linea_id)
);
ALTER TABLE public.efe_clasificaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.efe_clasificaciones;
CREATE POLICY tenant_isolation ON public.efe_clasificaciones TO authenticated USING(empresa_id=current_empresa_id()) WITH CHECK(empresa_id=current_empresa_id() AND EXISTS(SELECT 1 FROM asiento_lineas l JOIN asientos a ON a.id=l.asiento_id WHERE l.id=linea_id AND a.empresa_id=current_empresa_id()));
DROP POLICY IF EXISTS planta_lockdown ON public.efe_clasificaciones;
CREATE POLICY planta_lockdown ON public.efe_clasificaciones AS RESTRICTIVE TO authenticated USING(NOT es_planta()) WITH CHECK(NOT es_planta());
DROP POLICY IF EXISTS contador_no_ins ON public.efe_clasificaciones;
CREATE POLICY contador_no_ins ON public.efe_clasificaciones AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(NOT es_contador());
DROP POLICY IF EXISTS contador_no_upd ON public.efe_clasificaciones;
CREATE POLICY contador_no_upd ON public.efe_clasificaciones AS RESTRICTIVE FOR UPDATE TO authenticated USING(NOT es_contador()) WITH CHECK(NOT es_contador());
DROP POLICY IF EXISTS contador_no_del ON public.efe_clasificaciones;
CREATE POLICY contador_no_del ON public.efe_clasificaciones AS RESTRICTIVE FOR DELETE TO authenticated USING(NOT es_contador());
DROP TRIGGER IF EXISTS contador_guard ON public.efe_clasificaciones;
CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE ON public.efe_clasificaciones FOR EACH ROW EXECUTE FUNCTION public.fn_contador_guard();
REVOKE ALL ON public.efe_clasificaciones FROM anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.efe_clasificaciones TO authenticated;
REVOKE ALL ON FUNCTION public.conciliar_extracto(uuid,uuid), public.crear_asiento_extracto(uuid,uuid,numeric), public.revisar_periodo_al_cerrar() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.conciliar_extracto(uuid,uuid), public.crear_asiento_extracto(uuid,uuid,numeric) TO authenticated;
COMMIT;
-- Verificación: SELECT to_regprocedure('public.crear_asiento_extracto(uuid,uuid,numeric)');
