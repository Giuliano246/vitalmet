# Controles Contables Fase A — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar a VitalStock cuatro controles contables estilo SAP — audit trail en compras/tesorería, períodos contables cerrados (bloqueo mensual), 3-way match GR/IR (OC↔Remito↔Factura) y control de correlatividad.

**Architecture:** Postgres/Supabase + RLS por `empresa_id` (single-tenant en la práctica, `empresa_id = a0a19507-2a50-4e80-a716-e9459f51d653`). La lógica autoritativa (bloqueos, match, asientos) vive en triggers y RPCs `jsonb` server-side; el frontend (`index.html`, vanilla JS) construye asientos vía la RPC existente `crear_asiento` y muestra previews con funciones puras testeables.

**Tech Stack:** PostgreSQL 17 (Supabase), PostgREST, HTML/vanilla JS único, tests con `node --test` sobre harness `vm` (`tests/_harness.js`).

---

## Convenciones del proyecto (LEER ANTES DE EMPEZAR)

- **SQL se aplica a mano en el SQL Editor de Supabase ANTES de pushear el frontend.** El ejecutor NO tiene `psql` ni `supabase` CLI local. Para cada migración: escribir el archivo → pedirle a Giuliano que la corra en el SQL Editor → esperar "listo" → correr la query de verificación → recién ahí commitear y seguir.
- Migraciones: `BEGIN; ... COMMIT;`, idempotentes (`IF NOT EXISTS` / `CREATE OR REPLACE` / `DROP ... IF EXISTS`), retrocompatibles, con query de verificación comentada al pie.
- RPCs: SIEMPRE devuelven `jsonb` (nunca `void`). `SET search_path = public`. `REVOKE EXECUTE ON FUNCTION ... FROM anon;` explícito tras crearlas. SECURITY INVOKER salvo que se necesite bypassear RLS (helpers de auth → DEFINER).
- Frontend, tabla nueva: agregar variable global + entrada AL FINAL del destructure de `loadAll()` y del array de GETs con `.catch(e=>_loadFail('Nombre',e))` + fallback `||[]`. Render en `PAGE_RENDERS`. Página nueva: `PAGE_TO_GROUP` + `GROUP_TABS` + `groupMods` en `aplicarPermisos()` + `<div class="tabs"></div>` en el `.page-header`.
- Toda interpolación de dato de usuario en HTML pasa por `esc()`.
- Mutaciones de plata (asientos) → vía RPC atómica, nunca POST/PATCH directo.
- Antes de cada commit que toca `index.html`: extraer el `<script>` y `node --check`, y `node --test tests/*.test.js`.
- Texto de UI en español argentino (voseo).

## File Structure

- **Create** `migrations/031_audit_compras.sql` — engancha `fn_audit()` a tablas de compras/tesorería.
- **Create** `migrations/032_periodos_contables.sql` — helper `current_usuario_es_admin()`, tabla `periodos_contables`, trigger `fn_periodo_cerrado()` en `asientos`, guard de reapertura.
- **Create** `migrations/033_gr_ir_3way_match.sql` — cuenta GR/IR + seed, columnas en `config_contable`, tabla `facturas_recibidas`, RPC `registrar_factura_recibida()`.
- **Create** `migrations/034_correlatividad.sql` — `UNIQUE(empresa_id,nro)` en `ordenes_compra`, vista `v_correlatividad` (huecos + duplicados).
- **Modify** `index.html`:
  - `generarAsientoCompra()` → asiento de recepción GR/IR (sin IVA, sin Proveedores).
  - nueva función pura `evaluarMatchFactura()` (preview del match).
  - `registrarFacturaRecibida()` (save flow que llama la RPC) + UI "Factura recibida" en Compras.
  - página "Cierre de períodos" en Contabilidad.
  - página "Control de correlatividad" en Contabilidad.
  - globals + `loadAll` + `PAGE_RENDERS` + nav para las tablas/páginas nuevas.
- **Modify** `tests/match.test.js` (Create) — tests de `evaluarMatchFactura()`.

## Orden de dependencias

031 (audit) → 032 (helper es_admin + períodos) → 033 (GR/IR, usa el helper) → frontend GR/IR + match + factura recibida → frontend cierre de períodos → 034 (correlatividad) → frontend correlatividad.

---

## Task 1: Migración 031 — audit trail en compras/tesorería

**Files:**
- Create: `migrations/031_audit_compras.sql`

- [ ] **Step 1: Confirmar la firma del trigger de audit existente**

Pedir a Giuliano que corra en el SQL Editor (o el ejecutor lo confirma con Giuliano):
```sql
-- Verificación previa: ¿cómo se llama el trigger y la función de audit?
SELECT tgname, tgrelid::regclass AS tabla
FROM pg_trigger
WHERE tgname LIKE '%audit%' AND NOT tgisinternal
ORDER BY tabla;
```
Expected: filas con `trg_audit` (o similar) sobre `ventas`, `asientos`, etc., todas apuntando a `fn_audit()`. Anotar el nombre EXACTO del trigger y de la función (el plan asume `fn_audit()` y triggers `trg_audit`; ajustar si difieren).

- [ ] **Step 2: Escribir la migración**

`migrations/031_audit_compras.sql`:
```sql
-- 031_audit_compras.sql
-- Extiende el audit trail (fn_audit, migración 023) a las tablas de
-- compras y tesorería que hoy quedan sin registrar.
BEGIN;

-- Idempotente: recrea el trigger en cada tabla objetivo.
DO $$
DECLARE
  t text;
  tablas text[] := ARRAY[
    'ordenes_compra', 'oc_items', 'recepciones_oc',
    'proveedores', 'cheques'
  ];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON public.%I;', t);
      EXECUTE format(
        'CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.fn_audit();', t);
    END IF;
  END LOOP;
END$$;

COMMIT;

-- Verificación:
-- SELECT tgrelid::regclass AS tabla FROM pg_trigger
--  WHERE tgname='trg_audit' AND NOT tgisinternal
--    AND tgrelid::regclass::text IN
--        ('ordenes_compra','oc_items','recepciones_oc','proveedores','cheques')
--  ORDER BY tabla;
-- Esperado: 5 filas.
```

> Nota: las tablas `facturas_recibidas`, `periodos_contables` y `cuentas_bancarias` reciben su trigger DENTRO de su propia migración (033, 032, 035) al crearse — no acá.

- [ ] **Step 3: Aplicar la migración**

Pasarle el archivo a Giuliano para el SQL Editor. Esperar confirmación "listo".

- [ ] **Step 4: Verificar**

Correr la query de verificación del pie del archivo.
Expected: 5 filas (`ordenes_compra`, `oc_items`, `recepciones_oc`, `proveedores`, `cheques`).

Prueba funcional rápida: editar una OC cualquiera (PATCH `observaciones`) y verificar:
```sql
SELECT tabla, accion, created_at FROM audit_log
WHERE tabla='ordenes_compra' ORDER BY created_at DESC LIMIT 1;
```
Expected: 1 fila reciente con `accion='UPDATE'`.

- [ ] **Step 5: Commit**

```bash
git add migrations/031_audit_compras.sql
git commit -m "feat(contab): audit trail en compras y tesorería (mig 031)"
```

---

## Task 2: Migración 032 — períodos contables cerrados (bloqueo mensual)

**Files:**
- Create: `migrations/032_periodos_contables.sql`

- [ ] **Step 1: Escribir la migración**

`migrations/032_periodos_contables.sql`:
```sql
-- 032_periodos_contables.sql
-- Cierre de períodos contables a nivel MENSUAL con bloqueo duro de asientos
-- y reapertura sólo por admin. Motivado por la declaración mensual de IVA (AFIP).
BEGIN;

-- 1) Helper: ¿el usuario del JWT es admin? (mismo patrón que current_empresa_id)
CREATE OR REPLACE FUNCTION public.current_usuario_es_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT es_admin FROM public.usuarios WHERE id = auth.uid()),
    false);
$$;
REVOKE EXECUTE ON FUNCTION public.current_usuario_es_admin() FROM anon;

-- 2) Tabla de períodos mensuales
CREATE TABLE IF NOT EXISTS public.periodos_contables (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid NOT NULL,
  anio        int  NOT NULL CHECK (anio BETWEEN 2000 AND 2100),
  mes         int  NOT NULL CHECK (mes BETWEEN 1 AND 12),
  estado      text NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto','cerrado')),
  cerrado_por uuid,
  cerrado_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, anio, mes)
);

ALTER TABLE public.periodos_contables ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.periodos_contables;
CREATE POLICY tenant_isolation ON public.periodos_contables
  FOR ALL TO authenticated
  USING (empresa_id = public.current_empresa_id())
  WITH CHECK (empresa_id = public.current_empresa_id());

-- audit trail sobre la tabla nueva
DROP TRIGGER IF EXISTS trg_audit ON public.periodos_contables;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.periodos_contables
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- 3) Guard de reapertura: sólo admin puede pasar de 'cerrado' a 'abierto'
CREATE OR REPLACE FUNCTION public.fn_periodo_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.estado = 'cerrado' AND NEW.estado = 'abierto'
     AND NOT public.current_usuario_es_admin() THEN
    RAISE EXCEPTION 'Sólo un administrador puede reabrir un período cerrado';
  END IF;
  IF NEW.estado = 'cerrado' AND (OLD.estado IS DISTINCT FROM 'cerrado') THEN
    NEW.cerrado_por := auth.uid();
    NEW.cerrado_at  := now();
  END IF;
  RETURN NEW;
END$$;
DROP TRIGGER IF EXISTS trg_periodo_guard ON public.periodos_contables;
CREATE TRIGGER trg_periodo_guard BEFORE UPDATE ON public.periodos_contables
  FOR EACH ROW EXECUTE FUNCTION public.fn_periodo_guard();

-- 4) Bloqueo de asientos con fecha en período cerrado
CREATE OR REPLACE FUNCTION public.fn_periodo_cerrado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_estado text;
BEGIN
  SELECT estado INTO v_estado
  FROM public.periodos_contables
  WHERE empresa_id = NEW.empresa_id
    AND anio = EXTRACT(YEAR  FROM NEW.fecha)::int
    AND mes  = EXTRACT(MONTH FROM NEW.fecha)::int;
  IF v_estado = 'cerrado' THEN
    RAISE EXCEPTION 'Período %-% cerrado: no se pueden imputar/editar asientos en esa fecha',
      EXTRACT(YEAR FROM NEW.fecha)::int, EXTRACT(MONTH FROM NEW.fecha)::int;
  END IF;
  RETURN NEW;
END$$;
DROP TRIGGER IF EXISTS trg_periodo_cerrado ON public.asientos;
CREATE TRIGGER trg_periodo_cerrado BEFORE INSERT OR UPDATE ON public.asientos
  FOR EACH ROW EXECUTE FUNCTION public.fn_periodo_cerrado();

COMMIT;

-- Verificación:
-- 1) SELECT public.current_usuario_es_admin();  -- bool del usuario actual
-- 2) Insertar un período cerrado de prueba y un asiento en esa fecha:
--   INSERT INTO periodos_contables(empresa_id,anio,mes,estado)
--     VALUES ('a0a19507-2a50-4e80-a716-e9459f51d653',2020,1,'cerrado');
--   -- el siguiente INSERT debe FALLAR con "Período 2020-1 cerrado":
--   -- (usar crear_asiento o un INSERT directo con fecha '2020-01-15')
--   DELETE FROM periodos_contables WHERE anio=2020 AND mes=1; -- limpiar
```

- [ ] **Step 2: Aplicar la migración**

Pasarle el archivo a Giuliano para el SQL Editor. Esperar "listo".

- [ ] **Step 3: Verificar el bloqueo**

Correr (con cuidado, limpiando al final) el bloque de verificación 2 del pie.
Expected: el INSERT del asiento en 2020-01 FALLA con `Período 2020-1 cerrado`; el `DELETE` de limpieza deja la tabla sin el período de prueba.

Verificar el guard de reapertura: como usuario no-admin, intentar `UPDATE periodos_contables SET estado='abierto'` sobre un período cerrado debe fallar. (Si el usuario de prueba es admin, validar al menos que un cierre setea `cerrado_por`/`cerrado_at`.)

- [ ] **Step 4: Commit**

```bash
git add migrations/032_periodos_contables.sql
git commit -m "feat(contab): períodos contables cerrados con bloqueo mensual + reapertura admin (mig 032)"
```

---

## Task 3: Migración 033 — cuenta GR/IR, config y RPC de factura recibida

**Files:**
- Create: `migrations/033_gr_ir_3way_match.sql`

- [ ] **Step 1: Confirmar nombres reales del esquema contable**

Verificar (SQL Editor) las columnas/tablas que la RPC va a tocar:
```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name='config_contable' ORDER BY ordinal_position;
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name IN ('oc_items','recepciones_oc','ordenes_compra')
ORDER BY table_name, ordinal_position;
-- Confirmar la firma de crear_asiento:
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='crear_asiento';
```
Expected: confirmar que `config_contable` tiene `cta_iva_credito`, `cta_proveedores`; `oc_items` tiene `precio_unitario`, `cantidad_recibida`; `crear_asiento(p_cabecera jsonb, p_lineas jsonb, p_asiento_id uuid)` devuelve jsonb. Ajustar la RPC si los nombres difieren.

- [ ] **Step 2: Escribir la migración**

`migrations/033_gr_ir_3way_match.sql`:
```sql
-- 033_gr_ir_3way_match.sql
-- 3-way match GR/IR (OC <-> Remito <-> Factura).
-- El asiento de recepción acredita una cuenta puente "Facturas a recibir";
-- la factura del proveedor cancela la puente y registra IVA + Proveedores.
BEGIN;

-- 1) Cuenta puente GR/IR (pasivo). Código 211009 libre en el plan de Vitalmet.
INSERT INTO public.cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa)
VALUES ('a0a19507-2a50-4e80-a716-e9459f51d653','211009','FACTURAS A RECIBIR (GR/IR)','pasivo',true,true)
ON CONFLICT (empresa_id, codigo) DO NOTHING;

-- 2) Config: cuenta GR/IR + tolerancias de match
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS cta_gr_ir uuid,
  ADD COLUMN IF NOT EXISTS match_tolerancia_pct   numeric NOT NULL DEFAULT 0.02,
  ADD COLUMN IF NOT EXISTS match_tolerancia_monto numeric NOT NULL DEFAULT 5000;

UPDATE public.config_contable c
SET cta_gr_ir = (SELECT id FROM public.cuentas_contables
                 WHERE empresa_id = c.empresa_id AND codigo='211009')
WHERE cta_gr_ir IS NULL;

-- 3) Tabla de facturas recibidas
CREATE TABLE IF NOT EXISTS public.facturas_recibidas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid NOT NULL,
  proveedor_id   uuid,
  oc_id          uuid REFERENCES public.ordenes_compra(id),
  nro            text NOT NULL,
  fecha          date NOT NULL,
  fecha_vto      date,
  neto           numeric NOT NULL,
  iva            numeric NOT NULL DEFAULT 0,
  total          numeric NOT NULL,
  moneda         text NOT NULL DEFAULT 'USD',
  tipo_cambio    numeric NOT NULL DEFAULT 1,
  estado_match   text NOT NULL DEFAULT 'pendiente'
                 CHECK (estado_match IN ('pendiente','ok','override')),
  asiento_id     uuid,
  override_por   uuid,
  override_motivo text,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.facturas_recibidas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.facturas_recibidas;
CREATE POLICY tenant_isolation ON public.facturas_recibidas
  FOR ALL TO authenticated
  USING (empresa_id = public.current_empresa_id())
  WITH CHECK (empresa_id = public.current_empresa_id());
DROP TRIGGER IF EXISTS trg_audit ON public.facturas_recibidas;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.facturas_recibidas
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- 4) RPC: registra la factura, hace el 3-way match y crea el asiento IR.
--    Devuelve jsonb. SECURITY INVOKER (RLS + triggers aplican como el usuario).
CREATE OR REPLACE FUNCTION public.registrar_factura_recibida(
  p_factura jsonb,        -- {proveedor_id, oc_id, nro, fecha, fecha_vto, neto, iva, total, moneda, tipo_cambio}
  p_override boolean DEFAULT false,
  p_motivo   text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
DECLARE
  v_empresa uuid := public.current_empresa_id();
  v_cfg     public.config_contable%ROWTYPE;
  v_oc_id   uuid := (p_factura->>'oc_id')::uuid;
  v_neto    numeric := (p_factura->>'neto')::numeric;
  v_iva     numeric := COALESCE((p_factura->>'iva')::numeric, 0);
  v_total   numeric := (p_factura->>'total')::numeric;
  v_valor_recibido numeric;
  v_dif     numeric;
  v_umbral  numeric;
  v_es_admin boolean := public.current_usuario_es_admin();
  v_estado  text;
  v_fact_id uuid;
  v_asiento jsonb;
  v_oc_nro  text;
  v_prov    text;
BEGIN
  SELECT * INTO v_cfg FROM public.config_contable WHERE empresa_id = v_empresa;
  IF v_cfg.cta_gr_ir IS NULL OR v_cfg.cta_iva_credito IS NULL OR v_cfg.cta_proveedores IS NULL THEN
    RAISE EXCEPTION 'Config contable incompleta: faltan cta_gr_ir / cta_iva_credito / cta_proveedores';
  END IF;

  -- Valor de lo recibido valuado a precio de OC
  SELECT COALESCE(SUM(precio_unitario * cantidad_recibida), 0)
    INTO v_valor_recibido
    FROM public.oc_items WHERE oc_id = v_oc_id;

  v_dif    := abs(v_neto - v_valor_recibido);
  v_umbral := LEAST(v_valor_recibido * v_cfg.match_tolerancia_pct, v_cfg.match_tolerancia_monto);

  IF v_dif <= v_umbral THEN
    v_estado := 'ok';
  ELSIF p_override AND v_es_admin THEN
    v_estado := 'override';
  ELSE
    RAISE EXCEPTION 'Match fallido: neto factura % vs recibido % (dif %, tolerancia %). Requiere override de admin.',
      v_neto, v_valor_recibido, v_dif, v_umbral;
  END IF;

  SELECT nro INTO v_oc_nro FROM public.ordenes_compra WHERE id = v_oc_id;
  SELECT nombre INTO v_prov FROM public.proveedores WHERE id = (p_factura->>'proveedor_id')::uuid;

  -- Asiento IR: Debe GR/IR (neto) + Debe IVA CF | Haber Proveedores (total)
  v_asiento := public.crear_asiento(
    jsonb_build_object(
      'fecha', p_factura->>'fecha',
      'descripcion', format('Factura proveedor %s s/OC %s — %s', p_factura->>'nro', v_oc_nro, v_prov),
      'comprobante_nro', p_factura->>'nro',
      'tipo', 'auto-factura-compra',
      'origen_tipo', 'factura_recibida',
      'estado', 'confirmado',
      'moneda', COALESCE(p_factura->>'moneda','USD'),
      'tipo_cambio', COALESCE((p_factura->>'tipo_cambio')::numeric, 1),
      'proveedor_id', p_factura->>'proveedor_id'
    ),
    (
      SELECT jsonb_agg(l) FROM (
        SELECT jsonb_build_object('cuenta_id', v_cfg.cta_gr_ir, 'debe', v_neto, 'haber', 0,
                                  'descripcion','Cancela Facturas a recibir','orden',0) AS l
        UNION ALL
        SELECT jsonb_build_object('cuenta_id', v_cfg.cta_iva_credito,'debe', v_iva,'haber',0,
                                  'descripcion','IVA Crédito Fiscal','orden',1)
        WHERE v_iva > 0
        UNION ALL
        SELECT jsonb_build_object('cuenta_id', v_cfg.cta_proveedores,'debe',0,'haber', v_total,
                                  'descripcion','Proveedor','orden',2)
      ) s
    ),
    NULL
  );

  INSERT INTO public.facturas_recibidas
    (empresa_id, proveedor_id, oc_id, nro, fecha, fecha_vto, neto, iva, total,
     moneda, tipo_cambio, estado_match, asiento_id, override_por, override_motivo, created_by)
  VALUES
    (v_empresa, (p_factura->>'proveedor_id')::uuid, v_oc_id, p_factura->>'nro',
     (p_factura->>'fecha')::date, NULLIF(p_factura->>'fecha_vto','')::date,
     v_neto, v_iva, v_total, COALESCE(p_factura->>'moneda','USD'),
     COALESCE((p_factura->>'tipo_cambio')::numeric,1), v_estado,
     (v_asiento->>'id')::uuid,
     CASE WHEN v_estado='override' THEN auth.uid() END,
     CASE WHEN v_estado='override' THEN p_motivo END,
     auth.uid())
  RETURNING id INTO v_fact_id;

  RETURN jsonb_build_object('id', v_fact_id, 'estado_match', v_estado,
                            'asiento_id', v_asiento->>'id',
                            'dif', v_dif, 'umbral', v_umbral,
                            'valor_recibido', v_valor_recibido);
END$$;
REVOKE EXECUTE ON FUNCTION public.registrar_factura_recibida(jsonb, boolean, text) FROM anon;

COMMIT;

-- Verificación:
-- 1) SELECT codigo,nombre FROM cuentas_contables WHERE codigo='211009';
-- 2) SELECT cta_gr_ir, match_tolerancia_pct, match_tolerancia_monto FROM config_contable;
-- 3) Probar la RPC con una OC real recibida (neto = valor recibido) → estado_match 'ok'.
--    Probar con neto muy distinto sin override → debe FALLAR.
```

- [ ] **Step 3: Aplicar la migración**

Pasarle el archivo a Giuliano. Esperar "listo".

- [ ] **Step 4: Verificar**

Correr las 3 verificaciones del pie.
Expected: (1) la cuenta 211009 existe; (2) `cta_gr_ir` no es null y tolerancias 0.02/5000; (3) con una OC recibida y `neto = valor recibido` la RPC devuelve `estado_match='ok'` y un `asiento_id`; con `neto` fuera de tolerancia y sin override, la RPC lanza excepción.

- [ ] **Step 5: Commit**

```bash
git add migrations/033_gr_ir_3way_match.sql
git commit -m "feat(compras): 3-way match GR/IR + facturas_recibidas + RPC registrar_factura_recibida (mig 033)"
```

---

## Task 4: Frontend — asiento de recepción GR/IR

**Files:**
- Modify: `index.html` (función `generarAsientoCompra()`)

- [ ] **Step 1: Localizar la función**

Abrir `index.html` y localizar `generarAsientoCompra(` (aprox. línea 5546). Leer cómo arma `lineas` hoy (debita stock/gasto por tipo + IVA, acredita `cta_proveedores`).

- [ ] **Step 2: Cambiar las líneas a GR/IR**

Reemplazar la construcción de `lineas` para que el asiento de recepción quede SIN IVA y SIN Proveedores, acreditando la cuenta puente. La cabecera mantiene `tipo:'auto-compra'`, `origen_tipo:'recepcion'`. El patrón resultante:

```js
// Asiento de recepción (GR): Debe Stock/Gasto (neto por tipo) | Haber GR/IR (neto total)
const lineas = [];
let orden = 0, netoTotal = 0;
for (const [tipo, neto] of Object.entries(netoPorTipo)) {  // netoPorTipo: igual que hoy, SIN IVA
  if (!neto) continue;
  lineas.push({ cuenta_id: ctaCompraPorTipo[tipo], debe: neto, haber: 0,
                descripcion: `Recepción OC ${oc.nro}`, orden: orden++ });
  netoTotal += neto;
}
if (!configContable.cta_gr_ir) { notify('Falta configurar la cuenta GR/IR (Facturas a recibir)','err'); return; }
lineas.push({ cuenta_id: configContable.cta_gr_ir, debe: 0, haber: netoTotal,
              descripcion: `Facturas a recibir OC ${oc.nro}`, orden: orden++ });
```

> Importante: quitar del cálculo cualquier línea de IVA (`cta_iva_credito`) y la línea de `cta_proveedores` que hoy existe en este asiento. El IVA y Proveedores pasan al asiento de la factura (Task 6 / RPC 033). Mantener el resto del flujo (`crear_asiento`, idempotencia por `origen_id` si existe) igual.

- [ ] **Step 3: Validar el script**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp.js',s)" && node --check /tmp/erp.js
```
Expected: sin output (sintaxis OK).

```bash
node --test tests/*.test.js
```
Expected: todos los tests existentes en verde (no se tocó cálculo testeado).

- [ ] **Step 4: Verificación funcional (manual, con Giuliano)**

En staging/prod (tras aplicar mig 033): registrar una recepción de OC y abrir el asiento generado.
Expected: el asiento tiene SOLO líneas de stock/gasto al debe y una línea GR/IR (211009) al haber, balanceado, SIN IVA ni Proveedores.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat(compras): asiento de recepción usa cuenta puente GR/IR (sin IVA ni Proveedores)"
```

---

## Task 5: Frontend — función pura de match (TDD)

**Files:**
- Create: `tests/match.test.js`
- Modify: `index.html` (nueva función `evaluarMatchFactura`)

- [ ] **Step 1: Escribir el test que falla**

`tests/match.test.js`:
```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

function evalMatch(args) {
  return erp.run(`evaluarMatchFactura(${JSON.stringify(args)})`);
}

test('match OK cuando el neto coincide con lo recibido', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1000, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.estado, 'ok');
});

test('match OK dentro de tolerancia porcentual', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1015, tolPct: 0.02, tolMonto: 5000 });
  // umbral = min(1000*0.02=20, 5000) = 20; dif 15 <= 20 -> ok
  assert.strictEqual(r.ok, true);
});

test('tope absoluto recorta la tolerancia en montos grandes', () => {
  const r = evalMatch({ valorRecibido: 1000000, neto: 1010000, tolPct: 0.02, tolMonto: 5000 });
  // umbral = min(20000, 5000) = 5000; dif 10000 > 5000 -> falla
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.estado, 'discrepancia');
});

test('match falla fuera de tolerancia', () => {
  const r = evalMatch({ valorRecibido: 1000, neto: 1200, tolPct: 0.02, tolMonto: 5000 });
  assert.strictEqual(r.ok, false);
});
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
node --test tests/match.test.js
```
Expected: FALLA (`evaluarMatchFactura is not defined`).

- [ ] **Step 3: Implementar la función pura en index.html**

Agregar cerca de las otras funciones de cálculo (ej. junto a `computeCtaCte`). Debe ser pura (sin DOM/red):
```js
// 3-way match (preview client-side; la RPC registrar_factura_recibida re-valida server-side)
function evaluarMatchFactura({ valorRecibido, neto, tolPct, tolMonto }) {
  const dif = Math.abs(neto - valorRecibido);
  const umbral = Math.min(valorRecibido * tolPct, tolMonto);
  const ok = dif <= umbral;
  return { ok, dif, umbral, estado: ok ? 'ok' : 'discrepancia' };
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
node --test tests/match.test.js
```
Expected: PASS (4 tests).

- [ ] **Step 5: node --check del script completo**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp.js',s)" && node --check /tmp/erp.js
```
Expected: sin output.

- [ ] **Step 6: Commit**

```bash
git add index.html tests/match.test.js
git commit -m "feat(compras): función pura evaluarMatchFactura + tests del 3-way match"
```

---

## Task 6: Frontend — UI y save flow de factura recibida

**Files:**
- Modify: `index.html` (global `facturasRecibidas`, `loadAll`, UI en Compras, `registrarFacturaRecibida`, render del match)

- [ ] **Step 1: Registrar la tabla en loadAll**

Agregar la global y la carga (AL FINAL del destructure y del array de GETs de `loadAll`, con `_loadFail` y `||[]`), siguiendo el patrón existente:
```js
let facturasRecibidas = [];
// ...en loadAll, al final del Promise.all destructure y del array de GETs:
//   db('facturas_recibidas?select=*&order=created_at.desc').catch(e=>_loadFail('Facturas recibidas',e))
// y en el catch de seguridad: facturasRecibidas = fr || [];
```

- [ ] **Step 2: Agregar el formulario de factura recibida en la página de Compras**

En la sección Compras, agregar un modal/form "Registrar factura de proveedor" con: selector de OC (de OCs en estado `recibida`/`recibida_parcial`/`recibida`), proveedor (autocompletado de la OC), nro, fecha, fecha_vto, neto, iva, total, moneda, tipo_cambio. Al cambiar la OC o el neto, calcular el valor recibido de esa OC (`Σ precio_unitario*cantidad_recibida` de sus `oc_items`) y mostrar el preview del match con `evaluarMatchFactura(...)`, resaltando la diferencia. Si `!ok`, mostrar el botón de override SOLO si el usuario es admin (`currentUsuario?.es_admin`), con campo motivo obligatorio. Todo dato de usuario interpolado con `esc()`.

- [ ] **Step 3: Implementar el save flow**

```js
async function registrarFacturaRecibida(btnId) {
  const f = leerFormFacturaRecibida();        // arma el objeto desde el form
  if (!f.oc_id || !f.nro || !f.neto) { notify('Completá OC, nº y neto','err'); return; }
  const preview = evaluarMatchFactura({ valorRecibido: f._valorRecibido, neto: f.neto,
                    tolPct: configContable.match_tolerancia_pct, tolMonto: configContable.match_tolerancia_monto });
  let override = false, motivo = null;
  if (!preview.ok) {
    if (!currentUsuario?.es_admin) { notify('La factura no matchea la OC/remito y no sos admin para forzar','err'); return; }
    motivo = (document.getElementById('fr-motivo')?.value || '').trim();
    if (!motivo) { notify('Indicá el motivo del override','err'); return; }
    override = true;
  }
  setBusy(btnId, true);
  try {
    await db('rpc/registrar_factura_recibida', 'POST',
      { p_factura: f, p_override: override, p_motivo: motivo });
    await loadAll(); closeModal(); renderAll();
    notify('Factura registrada','ok');
  } catch (e) { notify(e.message || 'Error registrando factura','err'); }
  finally { setBusy(btnId, false); }
}
```
> Ajustar `db(...)` a la firma real del helper del proyecto (revisar cómo se llaman otras RPCs, ej. `crear_asiento`). La RPC re-valida el match server-side: si falla y no hay override válido, lanza excepción y `notify` la muestra.

- [ ] **Step 4: Render de la lista de facturas recibidas**

Agregar `renderFacturasRecibidas(filter='')` (stats + tabla: OC, proveedor, nº, fecha, neto, iva, total, estado_match con badge, asiento) y registrarla en `PAGE_RENDERS` bajo la página/tab de Compras correspondiente. Estados con badge: `ok` (verde), `override` (amarillo), `pendiente` (gris).

- [ ] **Step 5: Validar**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp.js',s)" && node --check /tmp/erp.js && node --test tests/*.test.js
```
Expected: sin errores de sintaxis; todos los tests en verde.

- [ ] **Step 6: Verificación funcional (con Giuliano)**

Registrar una factura que matchea (estado `ok`, crea asiento IR que cancela GR/IR) y una que no matchea (bloqueada; con override admin queda `override` + motivo en audit_log). Verificar que la cuenta 211009 queda en cero cuando recepción y factura coinciden.

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat(compras): UI y registro de facturas recibidas con 3-way match y override admin"
```

---

## Task 7: Frontend — página "Cierre de períodos"

**Files:**
- Modify: `index.html` (global `periodosContables`, `loadAll`, nav, página, render, acciones cerrar/reabrir)

- [ ] **Step 1: Registrar la tabla en loadAll**

```js
let periodosContables = [];
// en loadAll: db('periodos_contables?select=*&order=anio.desc,mes.desc').catch(e=>_loadFail('Períodos',e))
// catch de seguridad: periodosContables = pc || [];
```

- [ ] **Step 2: Registrar la página en la navegación**

En Contabilidad: agregar `page-cierre-periodos` a `PAGE_TO_GROUP` (grupo contabilidad), una entrada en `GROUP_TABS` del grupo, su `groupMods` en `aplicarPermisos()`, y el `<div class="tabs"></div>` en el `.page-header` de la página nueva. Sub-página → `PAGE_TO_PARENT` si corresponde.

- [ ] **Step 3: Render + acciones**

`renderCierrePeriodos()`: grilla de meses (año actual y anterior) con su estado; botón "Cerrar" en períodos abiertos y "Reabrir" (solo `currentUsuario?.es_admin`) en cerrados, mostrando quién/cuándo cerró.
```js
async function cerrarPeriodo(anio, mes) {
  if (!confirm(`¿Cerrar el período ${mes}/${anio}? No se podrán imputar asientos en ese mes.`)) return;
  try {
    // upsert del período en estado 'cerrado'
    await db('periodos_contables', 'POST',
      { empresa_id: currentEmpresa.id, anio, mes, estado: 'cerrado' },
      { 'Prefer': 'resolution=merge-duplicates' });
    await loadAll(); renderAll(); notify('Período cerrado','ok');
  } catch (e) { notify(e.message || 'Error cerrando período','err'); }
}
async function reabrirPeriodo(id) {
  if (!currentUsuario?.es_admin) { notify('Solo un admin puede reabrir','err'); return; }
  if (!confirm('¿Reabrir el período?')) return;
  try {
    await db(`periodos_contables?id=eq.${id}`, 'PATCH', { estado: 'abierto' });
    await loadAll(); renderAll(); notify('Período reabierto','ok');
  } catch (e) { notify(e.message || 'No se pudo reabrir','err'); }
}
```
> Ajustar la firma de `db(...)` (método, headers `Prefer` para upsert/merge) a la convención real del proyecto. El guard server-side (trigger `trg_periodo_guard`) bloquea la reapertura si el usuario no es admin aunque la UI lo deje pasar.

- [ ] **Step 4: Validar**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp.js',s)" && node --check /tmp/erp.js && node --test tests/*.test.js
```
Expected: sin errores; tests en verde.

- [ ] **Step 5: Verificación funcional (con Giuliano)**

Cerrar un mes y verificar que intentar imputar un asiento con fecha en ese mes da error (`Período X cerrado`). Reabrir como admin y verificar que vuelve a permitir.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(contab): página de cierre/reapertura de períodos contables"
```

---

## Task 8: Migración 034 — control de correlatividad

**Files:**
- Create: `migrations/034_correlatividad.sql`

- [ ] **Step 1: Escribir la migración**

`migrations/034_correlatividad.sql`:
```sql
-- 034_correlatividad.sql
-- Unicidad de nº de OC + vista que detecta huecos y duplicados en
-- numeraciones correlativas (asientos, OCs, facturas emitidas).
BEGIN;

-- 1) Unicidad de nº de OC por empresa
CREATE UNIQUE INDEX IF NOT EXISTS uq_oc_nro_empresa
  ON public.ordenes_compra (empresa_id, nro);

-- 2) Vista de control de correlatividad
CREATE OR REPLACE VIEW public.v_correlatividad AS
WITH asientos_num AS (
  SELECT empresa_id, numero::bigint AS n FROM public.asientos
   WHERE numero IS NOT NULL
)
-- Duplicados de asientos
SELECT 'asiento'::text AS doc, 'duplicado'::text AS tipo,
       empresa_id, n::text AS valor
FROM asientos_num
GROUP BY empresa_id, n HAVING count(*) > 1
UNION ALL
-- Huecos de asientos (números faltantes entre min y max por empresa)
SELECT 'asiento', 'hueco', a.empresa_id, g.n::text
FROM (SELECT empresa_id, min(n) lo, max(n) hi FROM asientos_num GROUP BY empresa_id) a
CROSS JOIN LATERAL generate_series(a.lo, a.hi) AS g(n)
WHERE NOT EXISTS (SELECT 1 FROM asientos_num x
                  WHERE x.empresa_id=a.empresa_id AND x.n=g.n);

COMMIT;

-- Verificación:
-- SELECT * FROM v_correlatividad ORDER BY doc, tipo, valor;
-- (vacío o con los huecos/duplicados reales de asientos)
```
> Alcance v1 de la vista: asientos (la numeración con garantía DB). OCs y facturas emitidas: la unicidad ya queda cubierta por índices únicos (OC nuevo arriba; facturas emitidas ya tienen UNIQUE pv+tipo+numero en mig 016). Si más adelante se quiere detección de huecos en OC/facturas, se extiende la vista — fuera de alcance ahora (YAGNI).

- [ ] **Step 2: Aplicar la migración**

Pasarle el archivo a Giuliano. Esperar "listo".
> Nota: si el índice único de OC falla por duplicados preexistentes, listar y resolver con Giuliano antes de reintentar (`SELECT empresa_id,nro,count(*) FROM ordenes_compra GROUP BY 1,2 HAVING count(*)>1;`).

- [ ] **Step 3: Verificar**

```sql
SELECT * FROM v_correlatividad ORDER BY doc, tipo, valor;
```
Expected: vacío, o filas que reflejan huecos/duplicados reales en asientos.

- [ ] **Step 4: Commit**

```bash
git add migrations/034_correlatividad.sql
git commit -m "feat(contab): control de correlatividad — unique OC + vista de huecos/duplicados (mig 034)"
```

---

## Task 9: Frontend — reporte "Control de correlatividad" + sugerencia de nº OC

**Files:**
- Modify: `index.html` (global `correlatividad`, `loadAll`, página/reporte, sugerencia de nº OC)

- [ ] **Step 1: Registrar la vista en loadAll**

```js
let correlatividad = [];
// en loadAll: db('v_correlatividad?select=*').catch(e=>_loadFail('Correlatividad',e))
// catch de seguridad: correlatividad = corr || [];
```

- [ ] **Step 2: Página/reporte**

Agregar `page-correlatividad` a la navegación de Contabilidad (`PAGE_TO_GROUP` + `GROUP_TABS` + `groupMods` + `<div class="tabs">`). `renderCorrelatividad()`: tabla agrupada por documento (asiento/OC/factura) listando huecos y duplicados; si está vacío, mostrar estado "Sin anomalías de correlatividad ✓".

- [ ] **Step 3: Sugerencia de próximo nº de OC**

En el form de alta de OC, prellenar el campo `nro` con el siguiente correlativo sugerido a partir del máximo numérico existente (manteniendo el prefijo usado, ej. `OC-2026-007`). Es solo sugerencia (campo editable); la unicidad la garantiza el índice de la mig 034.
```js
function sugerirNroOC() {
  const nums = ordenesCompra
    .map(o => (o.nro || '').match(/(\d+)\s*$/)?.[1])
    .filter(Boolean).map(Number);
  const next = (nums.length ? Math.max(...nums) : 0) + 1;
  const anio = new Date().getFullYear();
  return `OC-${anio}-${String(next).padStart(3, '0')}`;
}
```

- [ ] **Step 4: Validar**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp.js',s)" && node --check /tmp/erp.js && node --test tests/*.test.js
```
Expected: sin errores; tests en verde.

- [ ] **Step 5: Verificación funcional (con Giuliano)**

Abrir el reporte y confirmar que refleja el resultado de `v_correlatividad`. Alta de OC nueva muestra el nº sugerido y un nº duplicado es rechazado por la DB.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(contab): reporte de correlatividad + sugerencia de nº de OC"
```

---

## Cierre de la Fase A

- [ ] Verificar que las migraciones 031-034 están aplicadas en Supabase y los archivos commiteados.
- [ ] `node --test tests/*.test.js` en verde.
- [ ] Push a `main` (deploy Netlify) y smoke test en `https://erp.vitalmetsa.com`: recepción GR/IR, factura recibida con match, cierre de período, reporte de correlatividad.
- [ ] Invocar `superpowers:finishing-a-development-branch` para decidir la integración.

> Fase B (conciliación bancaria, mig 035) queda para un plan aparte cuando se termine la Fase A.

## Notas de cobertura del spec

- Spec §1 (audit) → Task 1. §2 (períodos) → Task 2 + Task 7. §3 (GR/IR) → Tasks 3-6. §4 (correlatividad) → Task 8 + Task 9.
- Decisiones del spec respetadas: GR/IR con IVA en la factura (Task 3 RPC), tolerancia min(pct, monto) (Tasks 3 y 5), bloqueo + override admin (Tasks 3 y 6), cierre mensual + reapertura admin (Tasks 2 y 7).
- Fuera de alcance confirmado: conciliación bancaria (Fase B), match a nivel línea, multi-tenancy, costeo PPP.
