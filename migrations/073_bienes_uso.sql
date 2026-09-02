-- ═══════════════════════════════════════════════════════════════════
-- 073 — BIENES DE USO Y DEPRECIACIONES (Sprint C de la auditoría RT 54)
-- ═══════════════════════════════════════════════════════════════════
-- Informe: docs/analisis/2026-09-02-auditoria-rt54.md (hallazgo M-03)
--
-- Qué hace:
--   1. Tabla bienes_uso: subledger de bienes de uso e intangibles
--      (rubro, fecha de alta, valor de origen ARS, vida útil en meses,
--      valor residual, cuentas de activo / amortización acumulada /
--      depreciación, baja). Nro BU-nnnn server-side con advisory lock.
--   2. Tabla depreciaciones: una fila por bien y período depreciado,
--      vinculada al asiento. Es la base del anexo "Bienes de uso" del
--      modelo RT 54 (valores de origen, altas, bajas, depreciación del
--      ejercicio y acumulada).
--   3. Cuentas nuevas: 122015 Amort. Acum. Herramientas, 122016 Amort.
--      Acum. Construcciones y mejoras, 123010 Amort. Acum. Sist. y
--      programas (intangible), 421019 Depreciación bienes de uso fábrica
--      (rubro cmv) y 422016 Depreciación bienes de uso administración
--      (rubro gastos_administracion).
--   4. RPC registrar_depreciacion(p_desde, p_hasta, p_fecha, p_items):
--      arma el asiento (gasto al debe / amort. acumulada al haber,
--      agrupado por cuenta) vía crear_asiento en BORRADOR y graba las
--      filas de depreciaciones en la misma transacción. Si el asiento
--      anterior del mismo período fue anulado, sus filas se reemplazan.
--
-- Batería RLS completa (tenant_isolation + planta_lockdown +
-- contador_no_* + contador_guard + trg_audit), molde de la 059.
-- Requiere: 023 (crear_asiento, fn_audit), 052/053 (es_planta/es_contador),
-- 067 (crear_asiento re-emitida), 072 (rubro_rt54). Idempotente.
-- Correr en el SQL Editor ANTES de deployar el frontend.
-- ═══════════════════════════════════════════════════════════════════
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

-- ─── 1. bienes_uso ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bienes_uso (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            uuid        NOT NULL,
  nro                   text,                          -- BU-nnnn (trigger)
  nombre                text        NOT NULL,
  rubro                 text        NOT NULL CHECK (rubro IN (
                          'terrenos','edificios','maquinarias','rodados','instalaciones',
                          'muebles_utiles','herramientas','sistemas','obras_en_curso','otros')),
  fecha_alta            date        NOT NULL,
  valor_origen          numeric(18,2) NOT NULL CHECK (valor_origen >= 0),   -- ARS nominal a la fecha de alta
  valor_residual        numeric(18,2) NOT NULL DEFAULT 0 CHECK (valor_residual >= 0),
  vida_util_meses       int         NOT NULL DEFAULT 0 CHECK (vida_util_meses >= 0),   -- 0 = no se deprecia (terrenos, obras en curso)
  cuenta_activo_id      uuid        REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  cuenta_amort_acum_id  uuid        REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  cuenta_depreciacion_id uuid       REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  proveedor             text,
  comprobante           text,                          -- factura / OC de origen
  valor_usd             numeric(18,2),                 -- informativo
  tipo_cambio           numeric(12,4),                 -- informativo
  fecha_baja            date,
  motivo_baja           text,
  estado                text        NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','baja')),
  observaciones         text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bienes_uso_baja_chk CHECK ((estado = 'baja') = (fecha_baja IS NOT NULL)),
  CONSTRAINT bienes_uso_residual_chk CHECK (valor_residual <= valor_origen)
);
CREATE INDEX IF NOT EXISTS bienes_uso_empresa_idx ON public.bienes_uso(empresa_id, estado);
CREATE UNIQUE INDEX IF NOT EXISTS bienes_uso_nro_uq ON public.bienes_uso(empresa_id, nro);
COMMENT ON TABLE public.bienes_uso IS 'Subledger de bienes de uso e intangibles (mig 073, Sprint C RT 54). Valores en ARS nominales a la fecha de alta; la reexpresión la hace el ajuste por inflación sobre las cuentas.';

CREATE OR REPLACE FUNCTION public.fn_bien_uso_nro() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.nro, '') = '' OR EXISTS (
    SELECT 1 FROM bienes_uso b WHERE b.empresa_id = NEW.empresa_id AND b.nro = NEW.nro AND b.id <> NEW.id
  ) THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('bienes_uso_nro:' || NEW.empresa_id::text, 0));
    SELECT 'BU-' || lpad((COALESCE(MAX(substring(b.nro from 4)::int), 0) + 1)::text, 4, '0')
      INTO NEW.nro
      FROM bienes_uso b
      WHERE b.empresa_id = NEW.empresa_id AND b.nro ~ '^BU-[0-9]+$';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_bien_uso_nro() FROM PUBLIC, anon;
DROP TRIGGER IF EXISTS trg_bien_uso_nro ON public.bienes_uso;
CREATE TRIGGER trg_bien_uso_nro BEFORE INSERT OR UPDATE ON public.bienes_uso
  FOR EACH ROW EXECUTE FUNCTION public.fn_bien_uso_nro();

SELECT pg_temp.aplicar_bateria('bienes_uso');

-- ─── 2. depreciaciones ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.depreciaciones (
  id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid          NOT NULL,
  bien_id     uuid          NOT NULL REFERENCES public.bienes_uso(id) ON DELETE CASCADE,
  desde       date          NOT NULL,
  hasta       date          NOT NULL,
  meses       int           NOT NULL CHECK (meses > 0),
  importe     numeric(18,2) NOT NULL CHECK (importe > 0),
  asiento_id  uuid          REFERENCES public.asientos(id) ON DELETE SET NULL,
  created_at  timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT depreciaciones_rango_chk CHECK (hasta >= desde),
  CONSTRAINT depreciaciones_bien_hasta_uq UNIQUE (bien_id, hasta)
);
CREATE INDEX IF NOT EXISTS depreciaciones_empresa_idx ON public.depreciaciones(empresa_id, hasta DESC);
COMMENT ON TABLE public.depreciaciones IS 'Depreciación registrada por bien y período (mig 073). Si el asiento se anula, la RPC reemplaza la fila al volver a correr el período.';
SELECT pg_temp.aplicar_bateria('depreciaciones');

-- ─── 3. Cuentas nuevas ──────────────────────────────────────────────
DO $$
DECLARE
  emp uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  n int := 0;
BEGIN
  CREATE TEMP TABLE _ctas73 (codigo text PRIMARY KEY, nombre text, tipo text, saldo text, padre text, ajustable boolean, rubro text) ON COMMIT DROP;
  INSERT INTO _ctas73 VALUES
    ('122015', 'Amort Acum Herramientas',                 'activo', 'acreedor', '122000', true, 'bienes_uso'),
    ('122016', 'Amort Acum Construcciones y mejoras',     'activo', 'acreedor', '122000', true, 'bienes_uso'),
    ('123010', 'Amort Acum Sist y programas',             'activo', 'acreedor', '123000', true, 'intangibles'),
    ('421019', 'Depreciación bienes de uso fabricación',  'egreso', 'deudor',   '421000', true, 'cmv'),
    ('422016', 'Depreciación bienes de uso administración','egreso','deudor',   '422000', true, 'gastos_administracion');
  INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable, saldo_habitual, rubro_rt54, cuenta_padre_id)
  SELECT emp, x.codigo, x.nombre, x.tipo, true, true, x.ajustable, x.saldo, x.rubro,
         (SELECT id FROM public.cuentas_contables p WHERE p.empresa_id = emp AND p.codigo = x.padre)
  FROM _ctas73 x
  WHERE NOT EXISTS (SELECT 1 FROM public.cuentas_contables c WHERE c.empresa_id = emp AND c.codigo = x.codigo);
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '073: % cuentas creadas', n;
END $$;

-- ─── 4. RPC registrar_depreciacion ─────────────────────────────────
-- p_items: [{bien_id, meses, importe}]. Devuelve {id, numero, filas}.
CREATE OR REPLACE FUNCTION public.registrar_depreciacion(p_desde date, p_hasta date, p_fecha date, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  it jsonb; b record;
  v_meses int; v_imp numeric;
  deb jsonb := '{}'::jsonb; hab jsonb := '{}'::jsonb;   -- cuenta_id → importe
  k text; v_lineas jsonb := '[]'::jsonb; o int := 0;
  v_asiento jsonb; v_filas int := 0; v_total numeric := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta < p_desde THEN RAISE EXCEPTION 'Período inválido'; END IF;
  IF COALESCE(jsonb_array_length(p_items), 0) = 0 THEN RAISE EXCEPTION 'Sin bienes para depreciar'; END IF;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO b FROM bienes_uso WHERE id = (it->>'bien_id')::uuid AND empresa_id = emp;
    IF NOT FOUND THEN RAISE EXCEPTION 'Bien % inexistente', it->>'bien_id'; END IF;
    v_meses := COALESCE((it->>'meses')::int, 0);
    v_imp := round(COALESCE((it->>'importe')::numeric, 0), 2);
    IF v_meses <= 0 OR v_imp < 0.01 THEN CONTINUE; END IF;
    IF b.cuenta_amort_acum_id IS NULL OR b.cuenta_depreciacion_id IS NULL THEN
      RAISE EXCEPTION 'El bien % (%) no tiene cuentas de amortización acumulada y depreciación', b.nro, b.nombre;
    END IF;
    -- Si el período ya fue depreciado con un asiento ANULADO, se reemplaza; si está vivo, error.
    IF EXISTS (SELECT 1 FROM depreciaciones d JOIN asientos a ON a.id = d.asiento_id
                WHERE d.bien_id = b.id AND d.hasta = p_hasta AND a.estado <> 'anulado') THEN
      RAISE EXCEPTION 'El bien % ya tiene la depreciación al % registrada (asiento vivo). Anulá ese asiento para rehacerla.', b.nro, p_hasta;
    END IF;
    DELETE FROM depreciaciones WHERE bien_id = b.id AND hasta = p_hasta;
    deb := deb || jsonb_build_object(b.cuenta_depreciacion_id::text, COALESCE((deb->>(b.cuenta_depreciacion_id::text))::numeric, 0) + v_imp);
    hab := hab || jsonb_build_object(b.cuenta_amort_acum_id::text,  COALESCE((hab->>(b.cuenta_amort_acum_id::text))::numeric, 0) + v_imp);
    v_total := v_total + v_imp;
  END LOOP;
  IF v_total < 0.01 THEN RAISE EXCEPTION 'Sin importes a depreciar'; END IF;

  FOR k IN SELECT key FROM jsonb_each(deb) ORDER BY key LOOP
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', k, 'debe', round((deb->>k)::numeric, 2), 'haber', 0,
                  'descripcion', 'Depreciación del ejercicio ' || to_char(p_desde, 'DD/MM/YYYY') || ' – ' || to_char(p_hasta, 'DD/MM/YYYY'), 'orden', o);
    o := o + 1;
  END LOOP;
  FOR k IN SELECT key FROM jsonb_each(hab) ORDER BY key LOOP
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', k, 'debe', 0, 'haber', round((hab->>k)::numeric, 2),
                  'descripcion', 'Amortización acumulada al ' || to_char(p_hasta, 'DD/MM/YYYY'), 'orden', o);
    o := o + 1;
  END LOOP;

  v_asiento := public.crear_asiento(
    jsonb_build_object('fecha', p_fecha, 'descripcion', 'Depreciación de bienes de uso — ejercicio ' || to_char(p_desde, 'DD/MM/YYYY') || ' a ' || to_char(p_hasta, 'DD/MM/YYYY'),
                       'tipo', 'auto-depreciacion', 'origen_tipo', 'depreciacion', 'estado', 'borrador', 'moneda', 'ARS'),
    v_lineas);

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_meses := COALESCE((it->>'meses')::int, 0);
    v_imp := round(COALESCE((it->>'importe')::numeric, 0), 2);
    IF v_meses <= 0 OR v_imp < 0.01 THEN CONTINUE; END IF;
    INSERT INTO depreciaciones (empresa_id, bien_id, desde, hasta, meses, importe, asiento_id)
    VALUES (emp, (it->>'bien_id')::uuid, p_desde, p_hasta, v_meses, v_imp, (v_asiento->>'id')::uuid);
    v_filas := v_filas + 1;
  END LOOP;

  RETURN jsonb_build_object('id', v_asiento->>'id', 'numero', v_asiento->>'numero', 'filas', v_filas, 'total', v_total);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_depreciacion(date, date, date, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_depreciacion(date, date, date, jsonb) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
-- SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN ('bienes_uso','depreciaciones');
-- SELECT policyname, tablename FROM pg_policies WHERE tablename IN ('bienes_uso','depreciaciones') ORDER BY 2,1;  -- 5 por tabla
-- SELECT codigo, nombre, rubro_rt54, saldo_habitual FROM cuentas_contables WHERE codigo IN ('122015','122016','123010','421019','422016') ORDER BY codigo;
-- SELECT proname FROM pg_proc WHERE proname IN ('registrar_depreciacion','fn_bien_uso_nro');
