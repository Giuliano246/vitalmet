-- Validación local de migrations/083_sueldos_motor.sql (2026-09-28).
-- Uso: docker run -d --name pg083 -e POSTGRES_PASSWORD=x postgres:17-alpine
--      docker exec -i pg083 psql -U postgres -v ON_ERROR_STOP=1 < tests/db/083-stub.sql
--      docker exec -i pg083 psql -U postgres -v ON_ERROR_STOP=1 < migrations/083_sueldos_motor.sql
--      docker exec -i pg083 psql -U postgres -v ON_ERROR_STOP=1 < tests/db/083-smoke.sql
-- Para una migración futura: partir de este stub y sumarle las columnas de la 083.

-- Esquema stub mínimo para validar migrations/083_sueldos_motor.sql en Postgres 17 local.
-- Reproduce lo que la 083 asume que ya existe (006/023/052/053/065/066/071/081/082).
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;

CREATE TABLE public.usuarios (id uuid PRIMARY KEY, empresa_id uuid NOT NULL,
  es_admin boolean DEFAULT false, es_contador boolean DEFAULT false, es_planta boolean DEFAULT false, es_auditor boolean DEFAULT false);
GRANT ALL ON public.usuarios TO authenticated;

CREATE OR REPLACE FUNCTION public.current_empresa_id() RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT empresa_id FROM public.usuarios WHERE id = auth.uid() LIMIT 1 $$;
CREATE OR REPLACE FUNCTION public.es_planta() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE((SELECT es_planta FROM public.usuarios WHERE id = auth.uid()), false) $$;
CREATE OR REPLACE FUNCTION public.es_contador() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE((SELECT es_contador OR es_auditor FROM public.usuarios WHERE id = auth.uid()), false) $$;
CREATE OR REPLACE FUNCTION public.es_admin() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE((SELECT es_admin FROM public.usuarios WHERE id = auth.uid()), false) $$;
CREATE OR REPLACE FUNCTION public.tiene_modulo(m text) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE((SELECT es_admin OR es_contador OR es_auditor FROM public.usuarios WHERE id = auth.uid()), false) $$;
CREATE OR REPLACE FUNCTION public.fn_contador_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF public.es_contador() THEN RAISE EXCEPTION 'Modo contador: solo lectura'; END IF; RETURN NULL; END $$;
CREATE TABLE public.audit_log (id bigserial PRIMARY KEY, tabla text, op text, at timestamptz DEFAULT now());
CREATE OR REPLACE FUNCTION public.fn_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO public.audit_log(tabla, op) VALUES (TG_TABLE_NAME, TG_OP); RETURN NULL; END $$;

CREATE TABLE public.cuentas_contables (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, codigo text, nombre text);
CREATE TABLE public.asientos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, numero serial,
  fecha date, estado text, tipo text, origen_tipo text, origen_id uuid, descripcion text, moneda text, tipo_cambio numeric, tc_tipo text);
CREATE TABLE public.asiento_lineas (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), asiento_id uuid REFERENCES public.asientos(id) ON DELETE CASCADE,
  cuenta_id uuid, debe numeric DEFAULT 0, haber numeric DEFAULT 0, descripcion text, orden int);
-- Stub de crear_asiento (023/067): inserta cabecera + líneas, valida partida doble, devuelve {id, numero}
CREATE OR REPLACE FUNCTION public.crear_asiento(p_cab jsonb, p_lineas jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE emp uuid := public.current_empresa_id(); v_id uuid; v_num int; l jsonb; sd numeric := 0; sh numeric := 0;
BEGIN
  INSERT INTO asientos (empresa_id, fecha, estado, tipo, origen_tipo, origen_id, descripcion, moneda, tipo_cambio, tc_tipo)
  VALUES (emp, (p_cab->>'fecha')::date, p_cab->>'estado', p_cab->>'tipo', p_cab->>'origen_tipo', (p_cab->>'origen_id')::uuid,
          p_cab->>'descripcion', p_cab->>'moneda', (p_cab->>'tipo_cambio')::numeric, p_cab->>'tc_tipo')
  RETURNING id, numero INTO v_id, v_num;
  FOR l IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
    INSERT INTO asiento_lineas (asiento_id, cuenta_id, debe, haber, descripcion, orden)
    VALUES (v_id, (l->>'cuenta_id')::uuid, (l->>'debe')::numeric, (l->>'haber')::numeric, l->>'descripcion', (l->>'orden')::int);
    sd := sd + (l->>'debe')::numeric; sh := sh + (l->>'haber')::numeric;
  END LOOP;
  IF round(sd,2) <> round(sh,2) THEN RAISE EXCEPTION 'Asiento no balancea: debe % haber %', sd, sh; END IF;
  RETURN jsonb_build_object('id', v_id, 'numero', v_num);
END $$;

CREATE TABLE public.config_contable (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL UNIQUE,
  cta_sueldos_fab uuid, cta_cargas_fab uuid, cta_sueldos_adm uuid, cta_cargas_adm uuid, cta_sueldos_a_pagar uuid, cta_cargas_a_pagar uuid,
  cta_provision_sac uuid, cuit_empleador text, lsd_tipo_empresa smallint NOT NULL DEFAULT 1,
  lsd_importe_detraer numeric(14,2) NOT NULL DEFAULT 0, lsd_tope_aportes numeric(14,2) NOT NULL DEFAULT 0);

-- 065 + 066 + 082
CREATE TABLE public.empleados (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, legajo text, nombre text NOT NULL, cuil text,
  categoria text, rama text, centro text NOT NULL DEFAULT 'fabricacion' CHECK (centro IN ('fabricacion','administracion')),
  modalidad text NOT NULL DEFAULT 'jornal' CHECK (modalidad IN ('jornal','mensual')),
  fecha_ingreso date, fecha_egreso date, obra_social text, operario_nombre text, observaciones text,
  activo boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
  valor_hora numeric(14,2), cbu text, forma_pago smallint NOT NULL DEFAULT 3, dependencia text, conyuge boolean NOT NULL DEFAULT false,
  hijos smallint NOT NULL DEFAULT 0, adherentes smallint NOT NULL DEFAULT 0, cod_obra_social text);
CREATE TABLE public.liquidaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, periodo date NOT NULL,
  tipo text NOT NULL DEFAULT 'mensual' CHECK (tipo IN ('mensual','quincena1','quincena2','sac','vacaciones','final','otro')),
  estado text NOT NULL DEFAULT 'borrador' CHECK (estado IN ('borrador','confirmada')), fecha_pago date,
  bruto numeric(14,2) NOT NULL DEFAULT 0, no_remunerativo numeric(14,2) NOT NULL DEFAULT 0, aportes numeric(14,2) NOT NULL DEFAULT 0,
  neto numeric(14,2) NOT NULL DEFAULT 0, contribuciones numeric(14,2) NOT NULL DEFAULT 0, art numeric(14,2) NOT NULL DEFAULT 0,
  tipo_cambio numeric(14,4), asiento_id uuid REFERENCES public.asientos(id) ON DELETE SET NULL, observaciones text, created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(), lsd_nro integer, lsd_exportado_at timestamptz);
CREATE UNIQUE INDEX uq_liquidaciones_periodo_tipo ON public.liquidaciones (empresa_id, periodo, tipo) WHERE tipo IN ('mensual','quincena1','quincena2','sac');
CREATE TABLE public.liquidacion_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  liquidacion_id uuid NOT NULL REFERENCES public.liquidaciones(id) ON DELETE CASCADE,
  empleado_id uuid NOT NULL REFERENCES public.empleados(id) ON DELETE RESTRICT,
  bruto numeric(14,2) NOT NULL DEFAULT 0, no_remunerativo numeric(14,2) NOT NULL DEFAULT 0, aportes numeric(14,2) NOT NULL DEFAULT 0,
  neto numeric(14,2) NOT NULL DEFAULT 0, contribuciones numeric(14,2) NOT NULL DEFAULT 0, art numeric(14,2) NOT NULL DEFAULT 0,
  detalle jsonb, observaciones text, created_at timestamptz NOT NULL DEFAULT now(), f931 jsonb);
CREATE UNIQUE INDEX uq_liq_items_empleado ON public.liquidacion_items (liquidacion_id, empleado_id);
CREATE TABLE public.conceptos_sueldo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  codigo text NOT NULL CHECK (codigo ~ '^[A-Za-z0-9]{1,10}$'), nombre text NOT NULL,
  tipo text NOT NULL DEFAULT 'remunerativo' CHECK (tipo IN ('remunerativo','no_remunerativo','descuento','informativo')),
  unidades text CHECK (unidades IS NULL OR unidades IN ('$','%','A','Q','M','D','H')),
  orden integer NOT NULL DEFAULT 0, activo boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX uq_conceptos_sueldo_codigo ON public.conceptos_sueldo (empresa_id, codigo);
CREATE TABLE public.liquidacion_conceptos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  liquidacion_id uuid NOT NULL REFERENCES public.liquidaciones(id) ON DELETE CASCADE,
  item_id uuid NOT NULL REFERENCES public.liquidacion_items(id) ON DELETE CASCADE,
  empleado_id uuid NOT NULL REFERENCES public.empleados(id) ON DELETE RESTRICT,
  codigo text NOT NULL, cantidad numeric(7,2) NOT NULL DEFAULT 0 CHECK (cantidad >= 0 AND cantidad < 1000),
  unidades text CHECK (unidades IS NULL OR unidades IN ('$','%','A','Q','M','D','H')),
  importe numeric(15,2) NOT NULL CHECK (importe >= 0), dc char(1) NOT NULL CHECK (dc IN ('D','C')),
  periodo_ajuste text CHECK (periodo_ajuste IS NULL OR periodo_ajuste ~ '^\d{6}$'),
  orden integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now());

-- RLS tenant_isolation en las tablas existentes (como prod) para que el smoke como authenticated sea realista
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['config_contable','empleados','liquidaciones','liquidacion_items','liquidacion_conceptos','conceptos_sueldo','asientos','cuentas_contables'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON public.%I FOR ALL TO authenticated USING (empresa_id = public.current_empresa_id()) WITH CHECK (empresa_id = public.current_empresa_id())', t);
  END LOOP; END $$;
ALTER TABLE public.asiento_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY al_all ON public.asiento_lineas FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Datos base: empresa, usuario admin, cuentas, config, seed 082 de conceptos (16 códigos incl. 900)
INSERT INTO public.usuarios VALUES ('11111111-1111-1111-1111-111111111111','a0a19507-2a50-4e80-a716-e9459f51d653',true,false,false,false);
INSERT INTO public.usuarios VALUES ('22222222-2222-2222-2222-222222222222','bbbbbbbb-0000-0000-0000-000000000002',true,false,false,false);
INSERT INTO public.cuentas_contables (id, empresa_id, codigo, nombre) VALUES
 ('c0000000-0000-0000-0000-000000421001','a0a19507-2a50-4e80-a716-e9459f51d653','421001','Sueldos fab'),
 ('c0000000-0000-0000-0000-000000421002','a0a19507-2a50-4e80-a716-e9459f51d653','421002','Cargas fab'),
 ('c0000000-0000-0000-0000-000000422003','a0a19507-2a50-4e80-a716-e9459f51d653','422003','Sueldos adm'),
 ('c0000000-0000-0000-0000-000000422004','a0a19507-2a50-4e80-a716-e9459f51d653','422004','Cargas adm'),
 ('c0000000-0000-0000-0000-000000214006','a0a19507-2a50-4e80-a716-e9459f51d653','214006','Sueldos a pagar'),
 ('c0000000-0000-0000-0000-000000214007','a0a19507-2a50-4e80-a716-e9459f51d653','214007','Cargas a pagar'),
 ('c0000000-0000-0000-0000-000000214008','a0a19507-2a50-4e80-a716-e9459f51d653','214008','Provisión SAC');
INSERT INTO public.config_contable (empresa_id, cta_sueldos_fab, cta_cargas_fab, cta_sueldos_adm, cta_cargas_adm, cta_sueldos_a_pagar, cta_cargas_a_pagar, cta_provision_sac, lsd_importe_detraer, lsd_tope_aportes)
VALUES ('a0a19507-2a50-4e80-a716-e9459f51d653','c0000000-0000-0000-0000-000000421001','c0000000-0000-0000-0000-000000421002','c0000000-0000-0000-0000-000000422003','c0000000-0000-0000-0000-000000422004','c0000000-0000-0000-0000-000000214006','c0000000-0000-0000-0000-000000214007','c0000000-0000-0000-0000-000000214008', 7003.68, 4691748.47);
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden)
SELECT 'a0a19507-2a50-4e80-a716-e9459f51d653', c, n, t, NULL, o FROM (VALUES
 ('100','Sueldo básico','remunerativo',1),('110','Horas extras 50','remunerativo',2),('120','Horas extras 100','remunerativo',3),
 ('130','Antigüedad','remunerativo',4),('131','Presentismo','remunerativo',5),('140','Vacaciones','remunerativo',6),('150','SAC','remunerativo',7),
 ('160','Feriado','remunerativo',8),('190','Otros rem','remunerativo',9),('300','No rem','no_remunerativo',10),
 ('310','Jubilación','descuento',11),('320','Ley 19032','descuento',12),('330','Obra social','descuento',13),('340','Sindicato','descuento',14),
 ('350','Otros desc','descuento',15),('900','Informativo','informativo',16)) s(c,n,t,o);
