-- ═══════════════════════════════════════════════════════════════════
-- 086 — RETENCIONES PRACTICADAS A PROVEEDORES (Ganancias RG 830 + otras)
-- ═══════════════════════════════════════════════════════════════════
-- Pedido de la contadora (2026-10-05): el proveedor tiene que poder
-- marcarse como sujeto de retención y la orden de pago calcularla.
--
-- Qué hace:
--   1. Tabla retencion_regimenes: conceptos por impuesto (ganancias /
--      iibb / suss / iva) con mínimo no sujeto, alícuotas inscripto y
--      no inscripto, escala opcional y mínimo de retención. modo
--      'acumulado_mensual' (RG 830 art. 26) o 'por_pago'. Seed de los
--      regímenes usuales de Ganancias — LOS IMPORTES SON EDITABLES y
--      hay que validarlos con la contadora contra el Anexo VIII vigente.
--   2. proveedores.retenciones (jsonb): [{regimen_id, condicion,
--      exclusion_cert, exclusion_hasta}] — qué se le retiene.
--   3. Tabla retenciones_practicadas: una fila por retención de cada OP
--      (monto 0 = pago alcanzado que no superó el mínimo: sirve para
--      acumular la base del mes). Nº de certificado por impuesto
--      (trigger con advisory lock) sólo cuando monto > 0.
--   4. orden_pago_medios.tipo admite 'retencion'.
--   5. config_contable.cta_retp_* (pasivo "retenciones a depositar";
--      defaults del plan real: Ganancias 213010, IIBB 213007).
--   6. registrar_orden_pago RE-EMITIDA (base 074 — ediciones futuras
--      parten de acá): medio 'retencion' → fila en retenciones_practicadas
--      + haber a la cuenta de retenciones; p_cabecera.retenciones_cero.
--      Misma firma: el frontend viejo sigue funcionando.
--   7. anular_orden_pago RE-EMITIDA (base 074): anula las retenciones.
--
-- Batería RLS completa, molde de la 074. Requiere 074.
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


-- ─── 1. retencion_regimenes ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.retencion_regimenes (
  id                    uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            uuid          NOT NULL,
  impuesto              text          NOT NULL CHECK (impuesto IN ('ganancias','iibb','suss','iva')),
  codigo                text          NOT NULL,              -- código de régimen (SICORE / jurisdicción)
  nombre                text          NOT NULL,
  modo                  text          NOT NULL DEFAULT 'acumulado_mensual' CHECK (modo IN ('acumulado_mensual','por_pago')),
  minimo_no_sujeto      numeric(18,2) NOT NULL DEFAULT 0 CHECK (minimo_no_sujeto >= 0),
  alicuota_inscripto    numeric(7,4)  CHECK (alicuota_inscripto >= 0 AND alicuota_inscripto <= 100),   -- %; NULL si usa escala
  alicuota_no_inscripto numeric(7,4)  CHECK (alicuota_no_inscripto >= 0 AND alicuota_no_inscripto <= 100),
  escala                jsonb,                                -- [{desde, hasta, fijo, pct}] sólo inscriptos
  minimo_retencion      numeric(18,2) NOT NULL DEFAULT 0 CHECK (minimo_retencion >= 0),
  jurisdiccion          text,
  activo                boolean       NOT NULL DEFAULT true,
  created_at            timestamptz   NOT NULL DEFAULT now(),
  updated_at            timestamptz   NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS retencion_regimenes_uq ON public.retencion_regimenes(empresa_id, impuesto, codigo);
COMMENT ON TABLE public.retencion_regimenes IS 'Regímenes de retención a proveedores (mig 086). Importes editables desde Configuración → Imputación contable: mantenerlos al día con la norma vigente.';
SELECT pg_temp.aplicar_bateria('retencion_regimenes');

-- Seed Ganancias RG 830 (sólo si la empresa todavía no tiene regímenes).
-- Valores de referencia del Anexo VIII: VALIDAR con la contadora.
INSERT INTO public.retencion_regimenes (empresa_id, impuesto, codigo, nombre, modo, minimo_no_sujeto, alicuota_inscripto, alicuota_no_inscripto, escala, minimo_retencion)
SELECT 'a0a19507-2a50-4e80-a716-e9459f51d653'::uuid, 'ganancias', s.codigo, s.nombre, 'acumulado_mensual', s.mns, s.ai, s.ani, s.escala, 240
FROM (VALUES
  ('78',  'Enajenación de bienes muebles y bienes de cambio',                     224000::numeric, 2::numeric,    10::numeric, NULL::jsonb),
  ('94',  'Locaciones de obra y/o servicios no ejecutados en relación de dependencia', 67170,      2,             28,          NULL),
  ('116', 'Honorarios — profesiones liberales, oficios, síndicos, etc.',           67170,          NULL,          28,
     '[{"desde":0,"hasta":8000,"fijo":0,"pct":5},{"desde":8000,"hasta":16000,"fijo":400,"pct":9},{"desde":16000,"hasta":24000,"fijo":1120,"pct":12},{"desde":24000,"hasta":32000,"fijo":2080,"pct":15},{"desde":32000,"hasta":48000,"fijo":3280,"pct":19},{"desde":48000,"hasta":64000,"fijo":6320,"pct":23},{"desde":64000,"hasta":96000,"fijo":10000,"pct":27},{"desde":96000,"hasta":null,"fijo":18640,"pct":31}]'::jsonb),
  ('31',  'Alquileres o arrendamientos de bienes inmuebles urbanos',               11200,          6,             28,          NULL),
  ('32',  'Alquileres o arrendamientos de bienes muebles',                         11200,          6,             28,          NULL),
  ('95',  'Transporte de carga nacional e internacional',                          67170,          0.25,          28,          NULL)
) AS s(codigo, nombre, mns, ai, ani, escala)
WHERE NOT EXISTS (SELECT 1 FROM public.retencion_regimenes r
                   WHERE r.empresa_id = 'a0a19507-2a50-4e80-a716-e9459f51d653'::uuid);

-- ─── 2. proveedores.retenciones ─────────────────────────────────────
ALTER TABLE public.proveedores
  ADD COLUMN IF NOT EXISTS retenciones jsonb NOT NULL DEFAULT '[]'::jsonb;
COMMENT ON COLUMN public.proveedores.retenciones IS 'Regímenes de retención que se le aplican al pagar (mig 086): [{regimen_id, condicion: inscripto|no_inscripto, exclusion_cert, exclusion_hasta}]';

-- ─── 3. retenciones_practicadas ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.retenciones_practicadas (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid          NOT NULL,
  orden_pago_id    uuid          NOT NULL REFERENCES public.ordenes_pago(id) ON DELETE RESTRICT,
  medio_id         uuid          REFERENCES public.orden_pago_medios(id) ON DELETE SET NULL,
  proveedor_id     uuid          NOT NULL REFERENCES public.proveedores(id) ON DELETE RESTRICT,
  fecha            date          NOT NULL,
  impuesto         text          NOT NULL CHECK (impuesto IN ('ganancias','iibb','suss','iva')),
  regimen_id       uuid          REFERENCES public.retencion_regimenes(id) ON DELETE SET NULL,
  regimen_codigo   text,                                   -- congelado al momento del pago
  regimen_nombre   text,
  condicion        text,
  moneda_op        text          NOT NULL DEFAULT 'ARS',
  tipo_cambio      numeric,
  base_calculo     numeric(18,2) NOT NULL DEFAULT 0,       -- ARS: base de ESTE pago
  base_acumulada   numeric(18,2) NOT NULL DEFAULT 0,       -- ARS: pagos anteriores del mes (mismo régimen)
  retenido_previo  numeric(18,2) NOT NULL DEFAULT 0,       -- ARS: ya retenido en el mes
  minimo_no_sujeto numeric(18,2) NOT NULL DEFAULT 0,
  alicuota         numeric,                                -- % aplicado (NULL = escala)
  monto            numeric(18,2) NOT NULL DEFAULT 0 CHECK (monto >= 0),     -- ARS retenido
  monto_op         numeric(18,2) NOT NULL DEFAULT 0 CHECK (monto_op >= 0),  -- en la moneda de la OP
  certificado_nro  text,                                   -- trigger, sólo si monto > 0
  estado           text          NOT NULL DEFAULT 'vigente' CHECK (estado IN ('vigente','anulada')),
  manual           boolean       NOT NULL DEFAULT false,   -- el usuario pisó el importe calculado
  detalle          jsonb,
  created_by       uuid,
  created_at       timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS retenciones_practicadas_mes_idx ON public.retenciones_practicadas(empresa_id, proveedor_id, regimen_id, fecha);
CREATE INDEX IF NOT EXISTS retenciones_practicadas_op_idx ON public.retenciones_practicadas(orden_pago_id);
CREATE UNIQUE INDEX IF NOT EXISTS retenciones_practicadas_cert_uq ON public.retenciones_practicadas(empresa_id, impuesto, certificado_nro) WHERE certificado_nro IS NOT NULL;
COMMENT ON TABLE public.retenciones_practicadas IS 'Retenciones practicadas a proveedores en órdenes de pago (mig 086). monto 0 = pago alcanzado sin retención (acumula base del mes). Importes en ARS.';

CREATE OR REPLACE FUNCTION public.fn_retencion_cert_nro() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.monto > 0 AND COALESCE(NEW.certificado_nro, '') = '' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('ret_cert:' || NEW.empresa_id::text || ':' || NEW.impuesto, 0));
    SELECT lpad((COALESCE(MAX(r.certificado_nro::bigint), 0) + 1)::text, 8, '0')
      INTO NEW.certificado_nro
      FROM retenciones_practicadas r
      WHERE r.empresa_id = NEW.empresa_id AND r.impuesto = NEW.impuesto AND r.certificado_nro ~ '^[0-9]+$';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_retencion_cert_nro() FROM PUBLIC, anon;
DROP TRIGGER IF EXISTS trg_retencion_cert_nro ON public.retenciones_practicadas;
CREATE TRIGGER trg_retencion_cert_nro BEFORE INSERT ON public.retenciones_practicadas
  FOR EACH ROW EXECUTE FUNCTION public.fn_retencion_cert_nro();
SELECT pg_temp.aplicar_bateria('retenciones_practicadas');

-- ─── 4. orden_pago_medios.tipo admite 'retencion' ───────────────────
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.orden_pago_medios'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%tipo%' LOOP
    EXECUTE format('ALTER TABLE public.orden_pago_medios DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.orden_pago_medios ADD CONSTRAINT orden_pago_medios_tipo_check
  CHECK (tipo IN ('caja','banco','cheque','tarjeta','retencion'));

-- ─── 5. config_contable.cta_retp_* ──────────────────────────────────
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_retp_ganancias uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_retp_iibb      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_retp_suss      uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cta_retp_iva       uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL;
UPDATE public.config_contable c SET
  cta_retp_ganancias = COALESCE(c.cta_retp_ganancias,
    (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '213010')),
  cta_retp_iibb = COALESCE(c.cta_retp_iibb,
    (SELECT id FROM public.cuentas_contables WHERE empresa_id = c.empresa_id AND codigo = '213007'));

-- ─── 6. RPC registrar_orden_pago RE-EMITIDA (base 074) ──────────────
-- p_medios admite {tipo:'retencion', monto, cuenta_contable_id,
--   retencion:{impuesto, regimen_id, regimen_codigo, regimen_nombre, condicion,
--              base_calculo, base_acumulada, retenido_previo, minimo_no_sujeto,
--              alicuota, manual, detalle}}   (importes del cálculo en ARS)
-- p_cabecera.retenciones_cero: mismas claves, para pagos alcanzados sin retención.
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
  v_medio_id uuid; r jsonb; v_ret_n int := 0; v_tc_ars numeric;
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

  v_tc_ars := CASE WHEN v_moneda = 'USD' THEN v_tc ELSE 1 END;

  -- Medios
  FOR m IN SELECT * FROM jsonb_array_elements(p_medios) LOOP
    v_monto := ROUND(COALESCE((m->>'monto')::numeric, 0), 2);
    IF v_monto <= 0 THEN RAISE EXCEPTION 'Medio de pago con monto inválido'; END IF;
    IF COALESCE(m->>'tipo','') NOT IN ('caja','banco','cheque','tarjeta','retencion') THEN
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
            NULLIF(m->>'detalle',''), v_ord)
    RETURNING id INTO v_medio_id;
    -- Retención practicada (mig 086): el medio 'retencion' lleva el cálculo
    -- en m.retencion; el monto retenido es el del medio (moneda de la OP).
    IF m->>'tipo' = 'retencion' THEN
      r := m->'retencion';
      IF r IS NULL OR jsonb_typeof(r) <> 'object' OR COALESCE(r->>'impuesto','') NOT IN ('ganancias','iibb','suss','iva') THEN
        RAISE EXCEPTION 'La retención necesita impuesto y régimen';
      END IF;
      INSERT INTO retenciones_practicadas (empresa_id, orden_pago_id, medio_id, proveedor_id, fecha, impuesto,
        regimen_id, regimen_codigo, regimen_nombre, condicion, moneda_op, tipo_cambio, base_calculo, base_acumulada,
        retenido_previo, minimo_no_sujeto, alicuota, monto, monto_op, manual, detalle, created_by)
      VALUES (emp, v_op_id, v_medio_id, v_prov.id, v_fecha, r->>'impuesto',
        NULLIF(r->>'regimen_id','')::uuid, NULLIF(r->>'regimen_codigo',''), NULLIF(r->>'regimen_nombre',''),
        NULLIF(r->>'condicion',''), v_moneda, CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END,
        ROUND(COALESCE((r->>'base_calculo')::numeric, 0), 2), ROUND(COALESCE((r->>'base_acumulada')::numeric, 0), 2),
        ROUND(COALESCE((r->>'retenido_previo')::numeric, 0), 2), ROUND(COALESCE((r->>'minimo_no_sujeto')::numeric, 0), 2),
        NULLIF(r->>'alicuota','')::numeric, ROUND(v_monto * v_tc_ars, 2), v_monto,
        COALESCE((r->>'manual')::boolean, false), r->'detalle', auth.uid());
      v_ret_n := v_ret_n + 1;
    END IF;
    v_ord := v_ord + 1;
    v_sum_medios := v_sum_medios + v_monto;
  END LOOP;
  IF abs(v_sum_medios - v_total) >= 0.01 THEN
    RAISE EXCEPTION 'Los medios de pago suman % y el total de la orden es %', v_sum_medios, v_total;
  END IF;

  -- Pagos alcanzados por un régimen que NO generaron retención (bajo el
  -- mínimo, exclusión…): se guardan con monto 0 para que la base del
  -- mes acumule en el próximo pago (RG 830 art. 26). Sin certificado.
  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_cabecera->'retenciones_cero', '[]'::jsonb)) LOOP
    IF COALESCE(r->>'impuesto','') NOT IN ('ganancias','iibb','suss','iva') THEN CONTINUE; END IF;
    INSERT INTO retenciones_practicadas (empresa_id, orden_pago_id, proveedor_id, fecha, impuesto,
      regimen_id, regimen_codigo, regimen_nombre, condicion, moneda_op, tipo_cambio, base_calculo, base_acumulada,
      retenido_previo, minimo_no_sujeto, alicuota, monto, monto_op, manual, detalle, created_by)
    VALUES (emp, v_op_id, v_prov.id, v_fecha, r->>'impuesto',
      NULLIF(r->>'regimen_id','')::uuid, NULLIF(r->>'regimen_codigo',''), NULLIF(r->>'regimen_nombre',''),
      NULLIF(r->>'condicion',''), v_moneda, CASE WHEN v_moneda = 'USD' THEN v_tc ELSE NULL END,
      ROUND(COALESCE((r->>'base_calculo')::numeric, 0), 2), ROUND(COALESCE((r->>'base_acumulada')::numeric, 0), 2),
      ROUND(COALESCE((r->>'retenido_previo')::numeric, 0), 2), ROUND(COALESCE((r->>'minimo_no_sujeto')::numeric, 0), 2),
      NULLIF(r->>'alicuota','')::numeric, 0, 0, COALESCE((r->>'manual')::boolean, false), r->'detalle', auth.uid());
  END LOOP;

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
                                          WHEN 'cheque' THEN 'Cheque' WHEN 'retencion' THEN 'Retención' ELSE 'Tarjeta' END, ' + ') || ' ' || v_prov.nombre AS detalle,
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
                            'a_cuenta', ROUND(v_total - v_sum_imput, 2), 'retenciones', v_ret_n);
END $$;
REVOKE ALL ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_orden_pago(jsonb, jsonb, jsonb) TO authenticated;


-- ─── 7. RPC anular_orden_pago RE-EMITIDA (base 074) ─────────────────
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
  UPDATE retenciones_practicadas SET estado = 'anulada' WHERE orden_pago_id = o.id AND empresa_id = emp;
  UPDATE ordenes_pago SET estado = 'anulada', motivo_anulacion = TRIM(p_motivo) WHERE id = o.id;
  RETURN jsonb_build_object('ok', true, 'nro', o.nro);
END $$;
REVOKE ALL ON FUNCTION public.anular_orden_pago(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_orden_pago(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_orden_pago(uuid, text) TO authenticated;


COMMIT;

-- ── Verificación (correr después del COMMIT) ────────────────────────
-- SELECT tablename FROM pg_tables WHERE tablename IN
--   ('retencion_regimenes','retenciones_practicadas');                  -- 2 filas
-- SELECT codigo, nombre, minimo_no_sujeto, alicuota_inscripto FROM retencion_regimenes ORDER BY codigo::int; -- 6 filas
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='orden_pago_medios_tipo_check'; -- incluye retencion
-- SELECT cta_retp_ganancias, cta_retp_iibb FROM config_contable;        -- no nulos
-- SELECT column_name FROM information_schema.columns WHERE table_name='proveedores' AND column_name='retenciones'; -- 1 fila
