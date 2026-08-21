-- 069_auditoria_fase1.sql — Remediación auditoría externa 2026-08 (Fase 1)
-- Cierra los hallazgos H-02 y H-05 del informe (los flujos quedan
-- server-side y atómicos; el frontend acompaña en el mismo deploy):
--
--   H-02 (CRÍTICA) — Nota de crédito de venta sin tope server-side.
--     El control "Σ NC ≤ total de la factura" vivía en una variable
--     cacheada del navegador (_ncAcreditado): dos pestañas podían
--     emitir cada una una NC por el total, con CAE real. Ahora:
--       a) nc_reservas + RPC nc_reservar: ANTES de pedir el CAE, el
--          frontend reserva el monto contra el saldo REAL (facturas +
--          reservas vivas, con SELECT ... FOR UPDATE sobre la factura
--          → dos emisiones concurrentes se serializan y la segunda es
--          rechazada ANTES de tocar ARCA). Las reservas vencen a los
--          15 minutos (pestaña cerrada a mitad de camino).
--       b) RPC nc_liberar: libera la reserva al terminar (éxito o
--          falla pre-CAE). Si el CAE salió pero el INSERT falló, la
--          reserva NO se libera (sostiene el saldo mientras exista
--          una NC en ARCA sin registrar; afip_eventos la tiene).
--       c) Trigger trg_nc_tope (backstop): ningún INSERT en
--          facturas_emitidas con factura_asociada_id puede dejar
--          Σ NC > imp_total de la factura madre, venga de donde venga.
--
--   H-05 (ALTA) — Cobro con retenciones no atómico. El asiento iba por
--     crear_asiento (RPC) y los certificados por un POST aparte: una
--     falla de red dejaba retención imputada sin certificado para el
--     SICORE. RPC registrar_cobro: asiento + retenciones_sufridas en
--     una sola transacción (envuelve crear_asiento de 067 — hereda la
--     numeración por DB, el balanceo y app.asiento_rpc).
--
-- Convenciones: idempotente, jsonb, REVOKE anon, search_path=public.
-- Correr en el SQL Editor ANTES de deployar el frontend.

BEGIN;

-- ─── 1. nc_reservas — reservas de saldo para NC en curso ─────────────
-- Tabla operativa efímera (una fila por emisión de NC en vuelo, se
-- borra al terminar o vence a los 15'). Batería RLS estándar SIN
-- trg_audit: el registro definitivo es la NC en facturas_emitidas;
-- auditar altas/bajas de reservas solo mete ruido en audit_log.

CREATE TABLE IF NOT EXISTS public.nc_reservas (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid        NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
  factura_id uuid        NOT NULL REFERENCES public.facturas_emitidas(id) ON DELETE CASCADE,
  monto      numeric     NOT NULL CHECK (monto > 0),
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nc_reservas_factura ON public.nc_reservas (factura_id);

ALTER TABLE public.nc_reservas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.nc_reservas;
CREATE POLICY tenant_isolation ON public.nc_reservas FOR ALL TO authenticated
  USING (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));
DROP POLICY IF EXISTS planta_lockdown ON public.nc_reservas;
CREATE POLICY planta_lockdown ON public.nc_reservas AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS contador_no_ins ON public.nc_reservas;
CREATE POLICY contador_no_ins ON public.nc_reservas AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_upd ON public.nc_reservas;
CREATE POLICY contador_no_upd ON public.nc_reservas AS RESTRICTIVE FOR UPDATE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP POLICY IF EXISTS contador_no_del ON public.nc_reservas;
CREATE POLICY contador_no_del ON public.nc_reservas AS RESTRICTIVE FOR DELETE TO authenticated
  USING ((SELECT NOT public.es_contador()));
DROP TRIGGER IF EXISTS contador_guard ON public.nc_reservas;
CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.nc_reservas
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard();

-- ─── 2. RPC nc_reservar — validar y reservar saldo ANTES del CAE ─────

CREATE OR REPLACE FUNCTION public.nc_reservar(p_factura_id uuid, p_monto numeric)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  f record; v_nc numeric; v_res numeric; v_saldo numeric; v_id uuid;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_monto, 0) <= 0 THEN RAISE EXCEPTION 'Monto de NC inválido'; END IF;

  -- Lock de la factura madre: serializa reservas concurrentes entre sí
  -- y con el trigger trg_nc_tope (que también la lockea al insertar).
  SELECT id, imp_total, afip_environment, factura_asociada_id INTO f
  FROM facturas_emitidas WHERE id = p_factura_id AND empresa_id = emp
  FOR UPDATE;
  IF f.id IS NULL THEN RAISE EXCEPTION 'Factura no encontrada'; END IF;
  IF f.factura_asociada_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede emitir una NC sobre otra nota de crédito';
  END IF;

  -- Housekeeping: reservas vencidas de esta factura (pestaña muerta)
  DELETE FROM nc_reservas
  WHERE factura_id = f.id AND created_at < now() - interval '15 minutes';

  -- Saldo real: total − NC ya emitidas (mismo ambiente) − reservas vivas
  SELECT COALESCE(SUM(imp_total), 0) INTO v_nc FROM facturas_emitidas
  WHERE factura_asociada_id = f.id AND afip_environment = f.afip_environment;
  SELECT COALESCE(SUM(monto), 0) INTO v_res FROM nc_reservas
  WHERE factura_id = f.id;
  v_saldo := round((f.imp_total - v_nc - v_res)::numeric, 2);

  IF p_monto > v_saldo + 0.01 THEN
    RAISE EXCEPTION 'El monto $% supera el saldo disponible para acreditar ($%)%',
      p_monto, GREATEST(v_saldo, 0),
      CASE WHEN v_res > 0
        THEN ' — hay otra NC en curso sobre esta factura; esperá unos minutos y recargá'
        ELSE ' — recargá la pantalla para ver las NC ya emitidas' END;
  END IF;

  INSERT INTO nc_reservas (empresa_id, factura_id, monto, created_by)
  VALUES (emp, f.id, p_monto, auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('reserva_id', v_id, 'saldo', v_saldo);
END $$;
REVOKE EXECUTE ON FUNCTION public.nc_reservar(uuid, numeric) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.nc_reservar(uuid, numeric) TO authenticated;

-- ─── 3. RPC nc_liberar — soltar la reserva al terminar ───────────────

CREATE OR REPLACE FUNCTION public.nc_liberar(p_reserva_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  DELETE FROM nc_reservas WHERE id = p_reserva_id AND empresa_id = emp;
  RETURN jsonb_build_object('liberada', FOUND);
END $$;
REVOKE EXECUTE ON FUNCTION public.nc_liberar(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.nc_liberar(uuid) TO authenticated;

-- ─── 4. Trigger trg_nc_tope — backstop: Σ NC ≤ total de la factura ───
-- Garantiza el invariante en la DB aunque alguien escriba por REST
-- directo sin pasar por nc_reservar. No cuenta reservas (la propia
-- emisión en curso tiene la suya viva y se contaría doble).

CREATE OR REPLACE FUNCTION public.fn_nc_tope() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  p record; v_nc numeric;
BEGIN
  SELECT id, empresa_id, imp_total, factura_asociada_id INTO p
  FROM facturas_emitidas WHERE id = NEW.factura_asociada_id
  FOR UPDATE;
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'La factura asociada a la NC no existe';
  END IF;
  IF p.empresa_id IS DISTINCT FROM NEW.empresa_id THEN
    RAISE EXCEPTION 'La factura asociada pertenece a otra empresa';
  END IF;
  IF p.factura_asociada_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede asociar una NC a otra nota de crédito';
  END IF;
  SELECT COALESCE(SUM(imp_total), 0) INTO v_nc FROM facturas_emitidas
  WHERE factura_asociada_id = p.id AND afip_environment = NEW.afip_environment;
  IF v_nc + NEW.imp_total > p.imp_total + 0.01 THEN
    RAISE EXCEPTION 'La NC de $% deja la factura sobre-acreditada: total $%, ya acreditado $%, saldo $%',
      NEW.imp_total, p.imp_total, v_nc, round((p.imp_total - v_nc)::numeric, 2);
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_tope() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_nc_tope ON public.facturas_emitidas;
CREATE TRIGGER trg_nc_tope BEFORE INSERT ON public.facturas_emitidas
  FOR EACH ROW WHEN (NEW.factura_asociada_id IS NOT NULL)
  EXECUTE FUNCTION public.fn_nc_tope();

-- ─── 5. RPC registrar_cobro — asiento + retenciones en una transacción ─
-- Envuelve crear_asiento (versión 067): si el INSERT de un certificado
-- falla, el asiento también hace rollback. La fecha de las retenciones
-- es la del asiento (p_cabecera->>'fecha'), como hacía el frontend.

CREATE OR REPLACE FUNCTION public.registrar_cobro(p_cabecera jsonb, p_lineas jsonb, p_retenciones jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  r jsonb; ret jsonb; v_monto numeric; v_cnt int := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;

  r := public.crear_asiento(p_cabecera, p_lineas);

  FOR ret IN SELECT * FROM jsonb_array_elements(COALESCE(p_retenciones, '[]'::jsonb)) LOOP
    v_monto := COALESCE((ret->>'monto')::numeric, 0);
    IF v_monto <= 0 THEN RAISE EXCEPTION 'Retención con monto inválido'; END IF;
    IF ret->>'tipo' = 'iibb' AND COALESCE(ret->>'jurisdiccion', '') = '' THEN
      RAISE EXCEPTION 'La retención de IIBB requiere jurisdicción';
    END IF;
    INSERT INTO retenciones_sufridas
      (empresa_id, cliente_id, fecha, tipo, certificado_nro, jurisdiccion,
       monto, moneda, tipo_cambio, asiento_id, created_by)
    VALUES
      (emp,
       NULLIF(ret->>'cliente_id', '')::uuid,
       (p_cabecera->>'fecha')::date,
       ret->>'tipo',
       NULLIF(ret->>'certificado_nro', ''),
       NULLIF(ret->>'jurisdiccion', ''),
       v_monto,
       COALESCE(NULLIF(ret->>'moneda', ''), 'ARS'),
       NULLIF(ret->>'tipo_cambio', '')::numeric,
       (r->>'id')::uuid,
       auth.uid());
    v_cnt := v_cnt + 1;
  END LOOP;

  RETURN r || jsonb_build_object('retenciones', v_cnt);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_cobro(jsonb, jsonb, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_cobro(jsonb, jsonb, jsonb) TO authenticated;

COMMIT;

-- ─── Verificación ────────────────────────────────────────────────────
-- 1) Tabla y batería:
-- SELECT policyname FROM pg_policies WHERE tablename = 'nc_reservas' ORDER BY 1;
--    (esperado: contador_no_del, contador_no_ins, contador_no_upd,
--     planta_lockdown, tenant_isolation)
-- 2) Trigger backstop:
-- SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.facturas_emitidas'::regclass
--   AND tgname = 'trg_nc_tope';
-- 3) RPCs sin anon:
-- SELECT proname, pg_get_functiondef(oid) IS NOT NULL AS ok FROM pg_proc
--  WHERE proname IN ('nc_reservar','nc_liberar','registrar_cobro');
-- SELECT has_function_privilege('anon', 'public.nc_reservar(uuid,numeric)', 'EXECUTE');
--    (esperado: false; ídem nc_liberar y registrar_cobro)
-- 4) Backstop funcional (con una factura de prueba en homologación):
--    intentar INSERT de una NC con imp_total > saldo → debe fallar con
--    "deja la factura sobre-acreditada".
