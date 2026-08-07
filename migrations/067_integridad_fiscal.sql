-- ═══════════════════════════════════════════════════════════════════
-- 067 — INTEGRIDAD CONTABLE Y FISCAL (auditoría 2026-08-06)
-- ═══════════════════════════════════════════════════════════════════
-- Cierra los 3 hallazgos graves de la auditoría contable:
--
--   1. INMUTABILIDAD DE ASIENTOS (CCyC art. 324): un asiento confirmado
--      no se puede borrar ni editar por REST. Solo se permite el flip
--      confirmado ⇄ anulado (soft delete, contenido intacto). Borradores
--      siguen libres. El DELETE queda además bloqueado en período cerrado
--      (el trigger de la mig. 032 solo cubría INSERT/UPDATE).
--      La RPC crear_asiento — que valida partida doble y línea a línea —
--      conserva su capacidad de actualizar asientos (flujos idempotentes
--      de facturas y cheques) vía un flag de transacción (GUC
--      app.asiento_rpc) que los triggers respetan.
--
--   2. TRAZABILIDAD ARCA: tabla afip_eventos donde la Edge Function
--      `facturacion` persiste TODA solicitud de CAE (aprobada o
--      rechazada) con la respuesta SOAP cruda — prueba ante una
--      fiscalización. Escribe solo service_role; lee solo el admin.
--
--   3. NOTAS DE CRÉDITO/DÉBITO DE VENTA: facturas_emitidas.factura_
--      asociada_id vincula la NC con el comprobante original (el bloque
--      CbtesAsoc que exige ARCA lo arma la Edge Function).
--
-- Convenciones del proyecto: idempotente, BEGIN/COMMIT, REVOKE anon
-- explícito, SET search_path = public, verificación comentada al final.
BEGIN;

-- ─── 1a. crear_asiento: marca la transacción con el GUC ──────────────
-- Idéntica a la de 024 (misma firma, no hace falta DROP) + la primera
-- línea set_config. set_config(..., true) es transaction-local: el flag
-- muere solo al terminar la transacción, no queda colgado en el pool.
CREATE OR REPLACE FUNCTION public.crear_asiento(p_cabecera jsonb, p_lineas jsonb, p_asiento_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  v_id uuid; v_num int;
  v_estado text := COALESCE(p_cabecera->>'estado', 'borrador');
  l jsonb; d numeric; h numeric; td numeric := 0; th numeric := 0;
  cnt int := COALESCE(jsonb_array_length(COALESCE(p_lineas, '[]'::jsonb)), 0);
BEGIN
  PERFORM set_config('app.asiento_rpc', '1', true);
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
      cliente_id      = COALESCE(NULLIF(p_cabecera->>'cliente_id','')::uuid, cliente_id),
      proveedor_id    = COALESCE(NULLIF(p_cabecera->>'proveedor_id','')::uuid, proveedor_id),
      updated_at      = now()
    WHERE id = p_asiento_id AND empresa_id = emp
    RETURNING id, numero INTO v_id, v_num;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Asiento no encontrado'; END IF;
    DELETE FROM asiento_lineas WHERE asiento_id = v_id;
  ELSE
    INSERT INTO asientos (empresa_id, numero, fecha, descripcion, comprobante_nro,
                          estado, tipo, origen_tipo, origen_id, moneda, tipo_cambio, tc_tipo,
                          cliente_id, proveedor_id)
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
            p_cabecera->>'tc_tipo',
            NULLIF(p_cabecera->>'cliente_id','')::uuid,
            NULLIF(p_cabecera->>'proveedor_id','')::uuid)
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
REVOKE EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.crear_asiento(jsonb, jsonb, uuid) TO authenticated;

-- ─── 1b. Inmutabilidad de la cabecera ────────────────────────────────
-- SECURITY DEFINER: lee periodos_contables sin que su RLS interfiera
-- (mismo criterio que fn_periodo_cerrado, mig. 032).
CREATE OR REPLACE FUNCTION public.fn_asiento_inmutable() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_periodo text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.estado <> 'borrador' THEN
      RAISE EXCEPTION 'El asiento N° % está %: los asientos no se eliminan (CCyC art. 324) — corresponde anularlo',
        OLD.numero, OLD.estado;
    END IF;
    SELECT estado INTO v_periodo FROM periodos_contables
     WHERE empresa_id = OLD.empresa_id
       AND anio = EXTRACT(YEAR  FROM OLD.fecha)::int
       AND mes  = EXTRACT(MONTH FROM OLD.fecha)::int;
    IF v_periodo = 'cerrado' THEN
      RAISE EXCEPTION 'Período %-% cerrado: no se pueden eliminar asientos de esa fecha',
        EXTRACT(YEAR FROM OLD.fecha)::int, EXTRACT(MONTH FROM OLD.fecha)::int;
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE: la RPC (que valida todo) pasa; el resto según estado.
  IF current_setting('app.asiento_rpc', true) = '1' THEN RETURN NEW; END IF;
  IF OLD.estado = 'borrador' THEN RETURN NEW; END IF;
  -- Confirmado/anulado por REST: solo el flip de estado, contenido intacto.
  IF NEW.estado NOT IN ('confirmado', 'anulado')
     OR (to_jsonb(NEW) - 'estado' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'estado' - 'updated_at') THEN
    RAISE EXCEPTION 'El asiento N° % está %: solo se puede anular o re-confirmar. Para corregirlo, anulalo y creá uno nuevo.',
      OLD.numero, OLD.estado;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_asiento_inmutable() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_asiento_inmutable ON public.asientos;
CREATE TRIGGER trg_asiento_inmutable
  BEFORE UPDATE OR DELETE ON public.asientos
  FOR EACH ROW EXECUTE FUNCTION public.fn_asiento_inmutable();

-- ─── 1c. Inmutabilidad de las líneas ─────────────────────────────────
-- Sin el flag de la RPC, las líneas de un asiento que no está en
-- borrador no se tocan. Parent NULL = el asiento se está borrando en
-- cascada (ya validado en 1b) o no existe: se deja pasar.
CREATE OR REPLACE FUNCTION public.fn_lineas_inmutables() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado text; v_num int;
BEGIN
  IF current_setting('app.asiento_rpc', true) = '1' THEN RETURN COALESCE(NEW, OLD); END IF;
  SELECT estado, numero INTO v_estado, v_num FROM asientos
   WHERE id = CASE WHEN TG_OP = 'INSERT' THEN NEW.asiento_id ELSE OLD.asiento_id END;
  IF v_estado IS NULL OR v_estado = 'borrador' THEN RETURN COALESCE(NEW, OLD); END IF;
  RAISE EXCEPTION 'Las líneas del asiento N° % (%) no se pueden modificar por REST — usá la RPC crear_asiento o anulá el asiento',
    v_num, v_estado;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_lineas_inmutables() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_lineas_inmutables ON public.asiento_lineas;
CREATE TRIGGER trg_lineas_inmutables
  BEFORE INSERT OR UPDATE OR DELETE ON public.asiento_lineas
  FOR EACH ROW EXECUTE FUNCTION public.fn_lineas_inmutables();

-- ─── 2. afip_eventos: bitácora de solicitudes a ARCA ─────────────────
-- Una fila por FECAESolicitar (aprobado o rechazado) con el SOAP crudo.
-- INSERT: solo la Edge Function (service_role bypasea RLS; authenticated
-- no recibe grant de INSERT). SELECT: solo admins de la empresa.
CREATE TABLE IF NOT EXISTS public.afip_eventos (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       uuid REFERENCES empresas(id) ON DELETE CASCADE,
  venta_id         uuid,          -- sin FK: la venta puede borrarse, el evento queda
  evento           text NOT NULL CHECK (evento IN ('cae_aprobado', 'cae_rechazado', 'error')),
  punto_venta      int,
  tipo_comprobante int,
  numero           int,           -- número intentado/otorgado
  request          jsonb,         -- payload recibido del ERP
  detalle          jsonb,         -- CAE/vto u errores/observaciones parseados
  raw_response     text,          -- SOAP completo de ARCA (prueba de auditoría)
  environment      text,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_afip_eventos_created ON public.afip_eventos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_afip_eventos_venta ON public.afip_eventos (venta_id);
COMMENT ON TABLE public.afip_eventos IS
  'Bitácora de solicitudes de CAE a ARCA (aprobadas y rechazadas) con respuesta SOAP cruda. Escribe la Edge Function facturacion.';

ALTER TABLE public.afip_eventos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS afip_eventos_select_admin ON public.afip_eventos;
CREATE POLICY afip_eventos_select_admin ON public.afip_eventos FOR SELECT TO authenticated
  USING (empresa_id = public.current_empresa_id() AND public.current_usuario_es_admin());
REVOKE ALL ON public.afip_eventos FROM anon;
GRANT SELECT ON public.afip_eventos TO authenticated;

-- ─── 3. NC/ND de ventas: vínculo con el comprobante original ─────────
ALTER TABLE public.facturas_emitidas
  ADD COLUMN IF NOT EXISTS factura_asociada_id uuid REFERENCES facturas_emitidas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_facturas_emitidas_asociada ON public.facturas_emitidas (factura_asociada_id);
COMMENT ON COLUMN public.facturas_emitidas.factura_asociada_id IS
  'En NC/ND (tipos 2,3,7,8,12,13): el comprobante original que corrige. ARCA recibe el bloque CbtesAsoc.';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después, línea a línea)
-- ═══════════════════════════════════════════════════════════════════
-- 1. Triggers instalados:
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname IN ('trg_asiento_inmutable','trg_lineas_inmutables');
--
-- 2. Un DELETE de asiento confirmado debe fallar:
-- DELETE FROM asientos WHERE estado='confirmado' AND id=(SELECT id FROM asientos WHERE estado='confirmado' LIMIT 1);
-- → ERROR: los asientos no se eliminan (CCyC art. 324)
--
-- 3. Editar un confirmado por REST debe fallar (solo el flip de estado pasa):
-- UPDATE asientos SET descripcion='hack' WHERE estado='confirmado' AND id=(SELECT id FROM asientos WHERE estado='confirmado' LIMIT 1);
-- → ERROR: solo se puede anular o re-confirmar
--
-- 4. Tabla de eventos:
-- SELECT count(*) FROM afip_eventos;
