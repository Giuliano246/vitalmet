-- ═══════════════════════════════════════════════════════════════════
-- 075 — NC/ND DE VENTA SOBRE CUALQUIER FACTURA + NC/ND LIBRE
-- ═══════════════════════════════════════════════════════════════════
-- Spec: docs/superpowers/specs/2026-09-07-notas-venta-design.md
--
-- Qué hace:
--   1. facturas_emitidas: periodo_asoc_desde / periodo_asoc_hasta (NC/ND
--      libre con PeriodoAsoc, RG 4540) y cbte_asoc_externo (texto
--      "tipo PV-nro" de una factura propia emitida fuera del ERP).
--   2. fn_nc_tope RE-EMITIDA (base 069 — ediciones futuras parten de acá):
--      el tope Σ NC ≤ total sólo aplica a las NC (tipos 3/8/13/53); las
--      ND (2/7/12/52) asociadas a la factura no cuentan ni se topean.
--   3. nc_reservar RE-EMITIDA (base 069): la suma de acreditado filtra
--      tipos NC, para que una ND previa no reduzca el saldo acreditable.
--
-- Idempotente. Correr en el SQL Editor ANTES de deployar el frontend y
-- la Edge Function facturacion.

BEGIN;

-- ─── 1. Columnas de asociación libre ────────────────────────────────
ALTER TABLE public.facturas_emitidas
  ADD COLUMN IF NOT EXISTS periodo_asoc_desde date,
  ADD COLUMN IF NOT EXISTS periodo_asoc_hasta date,
  ADD COLUMN IF NOT EXISTS cbte_asoc_externo  text;
COMMENT ON COLUMN public.facturas_emitidas.periodo_asoc_desde IS 'NC/ND libre: período asociado informado a ARCA (PeriodoAsoc.FchDesde), mig 075.';
COMMENT ON COLUMN public.facturas_emitidas.cbte_asoc_externo  IS 'NC/ND libre: comprobante propio emitido fuera del ERP al que se asocia ("tipo PV-nro"), mig 075.';

-- ─── 2. fn_nc_tope: sólo NC ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nc_tope() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  p record; v_nc numeric;
BEGIN
  SELECT id, empresa_id, imp_total, factura_asociada_id INTO p
  FROM facturas_emitidas WHERE id = NEW.factura_asociada_id
  FOR UPDATE;
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'La factura asociada a la NC/ND no existe';
  END IF;
  IF p.empresa_id IS DISTINCT FROM NEW.empresa_id THEN
    RAISE EXCEPTION 'La factura asociada pertenece a otra empresa';
  END IF;
  IF p.factura_asociada_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede asociar una NC/ND a otra nota';
  END IF;
  -- Las ND (2/7/12/52) no se topean ni descuentan saldo acreditable.
  IF NEW.tipo_comprobante NOT IN (3, 8, 13, 53) THEN RETURN NEW; END IF;
  SELECT COALESCE(SUM(imp_total), 0) INTO v_nc FROM facturas_emitidas
  WHERE factura_asociada_id = p.id AND afip_environment = NEW.afip_environment
    AND tipo_comprobante IN (3, 8, 13, 53);
  IF v_nc + NEW.imp_total > p.imp_total + 0.01 THEN
    RAISE EXCEPTION 'La NC de $% deja la factura sobre-acreditada: total $%, ya acreditado $%, saldo $%',
      NEW.imp_total, p.imp_total, v_nc, round((p.imp_total - v_nc)::numeric, 2);
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_nc_tope() FROM PUBLIC, anon;
-- El trigger de la 069 (BEFORE INSERT WHEN factura_asociada_id IS NOT NULL) queda igual.

-- ─── 3. nc_reservar: acreditado = sólo NC ───────────────────────────
CREATE OR REPLACE FUNCTION public.nc_reservar(p_factura_id uuid, p_monto numeric)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  f record; v_nc numeric; v_res numeric; v_saldo numeric; v_id uuid;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(p_monto, 0) <= 0 THEN RAISE EXCEPTION 'Monto de NC inválido'; END IF;

  SELECT id, imp_total, afip_environment, factura_asociada_id INTO f
  FROM facturas_emitidas WHERE id = p_factura_id AND empresa_id = emp
  FOR UPDATE;
  IF f.id IS NULL THEN RAISE EXCEPTION 'Factura no encontrada'; END IF;
  IF f.factura_asociada_id IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede emitir una NC sobre otra nota';
  END IF;

  DELETE FROM nc_reservas
  WHERE factura_id = f.id AND created_at < now() - interval '15 minutes';

  SELECT COALESCE(SUM(imp_total), 0) INTO v_nc FROM facturas_emitidas
  WHERE factura_asociada_id = f.id AND afip_environment = f.afip_environment
    AND tipo_comprobante IN (3, 8, 13, 53);
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

COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT column_name FROM information_schema.columns WHERE table_name='facturas_emitidas'
--   AND column_name IN ('periodo_asoc_desde','periodo_asoc_hasta','cbte_asoc_externo');  -- 3 filas
-- SELECT prosrc LIKE '%IN (3, 8, 13, 53)%' FROM pg_proc WHERE proname='fn_nc_tope';       -- true
