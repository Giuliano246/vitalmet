# Modo Contador — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contador externo con login propio en solo lectura garantizada por la base + página "Exportables" (6 CSVs + carpeta ZIP del período) en el grupo Contabilidad.

**Architecture:** Flag `usuarios.es_contador` (calco del patrón Modo Planta, migración 052): helper `es_contador()`, tres policies RESTRICTIVE por comando + trigger de statement `contador_guard` en toda tabla con RLS (cubre también funciones SECURITY DEFINER), guard client-side en `db()`. La visibilidad de módulos usa los `permisos_usuario` existentes; el admin marca el flag desde el modal de permisos.

**Tech Stack:** Supabase (PostgreSQL 17 + PostgREST + RLS), single-file `index.html` vanilla JS, tests node con harness vm (`tests/_harness.js`).

**Spec:** `docs/superpowers/specs/2026-07-20-modo-contador-design.md`

## Global Constraints

- **SQL en Supabase ANTES del deploy**: la migración 053 se corre en el SQL Editor y se verifica ANTES de pushear el frontend (el push a main deploya solo).
- Migración: `BEGIN;`/`COMMIT;`, idempotente (`IF NOT EXISTS` / `DROP ... IF EXISTS` / `CREATE OR REPLACE`), verificación comentada al pie. Toda función nueva: `SET search_path = public` + `REVOKE ... FROM PUBLIC, anon` explícito (Supabase da EXECUTE a anon por default).
- RPCs devuelven `jsonb`, nunca `void`.
- Formato CSV exacto: BOM `U+FEFF`, separador `;`, números `toFixed(2)` con coma decimal, fechas `DD/MM/AAAA`, líneas `CRLF`.
- ZIP formato *store*: fecha DOS fija `0x2100`, hora `0`, flag UTF-8 `0x0800`, CRC32 tabla `0xEDB88320`.
- Página nueva = tocar `PAGE_TO_GROUP` + `GROUP_TABS` + `groupMods` (en `aplicarPermisos`) + `<div class="tabs"></div>` en el `.page-header` + registrar en `PAGE_RENDERS`.
- Todo dato de usuario interpolado en HTML pasa por `esc()`. Texto UI en español argentino (voseo).
- Validación pre-commit: extraer el `<script>` grande y `node --check`, y `node --test tests/`.
- Cero referencias a otros productos o repos en código, comentarios y commits.
- No usar `git push` en ninguna task: el push a main es deploy a producción y lo autoriza el usuario en la Task 6.

## Estado del repo relevante (verificado)

- Última migración: `migrations/052_modo_planta.sql`. La 053 es la próxima.
- `usuarios`: `id (auth.uid) / empresa_id / nombre / email / rol / es_admin / ver_costos / es_planta / created_at`. Guard `usuarios_guard()` definido en 052:79-111.
- Las RPCs atómicas de la 023 son `SECURITY INVOKER` (las policies las cubren); el trigger es cinturón para cualquier DEFINER presente o futura.
- `db()` en index.html:2321; `doLogout()` en 2514; `loadEmpresaAndStart()` en 2522 (setea `currentUserData` en 2539); `PAGE_TO_GROUP`/`GROUP_TABS` en 2650-2669; `PAGE_RENDERS` en 4113; `MODULOS_LABELS` en 7206; `renderUsuarios` 7208; `openPermisos` 7240; `savePermisos` 7255; `aplicarPermisos` 7852; modal-permisos HTML en 2203-2231; `#app-screen` en 364; media query mobile en 231.
- Tablas para exports (nombres confirmados): `ventas(fecha,nro_remito,nro_pedido,cliente,condicion_pago,estado,total)`, `facturas_emitidas(fecha,tipo_comprobante,punto_venta,numero,doc_tipo,doc_nro,imp_neto,imp_iva,imp_total,cae)`, `facturas_recibidas(fecha,fecha_vto,nro,proveedor_id,neto,iva,total,moneda,tipo_cambio,estado_match)`, `proveedores(id,nombre,cuit)`, `asientos(id,numero,fecha,descripcion,estado)` con `estado='confirmado'` como filtro vigente, `asiento_lineas(asiento_id,cuenta_id,debe,haber,descripcion)`, `cuentas_contables(id,codigo,nombre,tipo,imputable,activa)`.

---

### Task 1: Migración `053_modo_contador.sql` + reglas del CLAUDE.md

**Files:**
- Create: `migrations/053_modo_contador.sql`
- Modify: `CLAUDE.md` (regla de lockdowns en la sección Módulos, rango de migraciones en la sección Supabase)

**Interfaces:**
- Produces: columna `usuarios.es_contador`, función `public.es_contador() → boolean`, policies `contador_no_ins/upd/del`, trigger `contador_guard` (función `public.fn_contador_guard()`), `usuarios_guard()` extendido. La corrida en el SQL Editor ocurre en la Task 6 (gate), NO acá.

- [ ] **Step 1: Escribir la migración**

Crear `migrations/053_modo_contador.sql` con exactamente:

```sql
-- 053_modo_contador.sql — Contador externo en solo lectura (Modo Contador)
-- El contador del estudio entra con su propio login (se registra con el
-- código de invitación, como cualquier usuario) y el admin lo marca
-- usuarios.es_contador=true desde Configuración → Usuarios. A partir de ahí:
--   · SELECT: intacto (qué módulos ve lo deciden los permisos_usuario)
--   · INSERT/UPDATE/DELETE: bloqueados en TODAS las tablas con RLS por
--     tres policies RESTRICTIVE por comando (contador_no_ins/upd/del)
--   · Funciones SECURITY DEFINER que escriben (bypass de RLS): las frena
--     el trigger de statement contador_guard, que se dispara también
--     dentro de funciones DEFINER. Doble cerrojo deliberado.
-- Usuarios normales (es_contador=false): cero cambio de comportamiento.
BEGIN;

-- ─── 1. Flag ─────────────────────────────────────────────────────────
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS es_contador boolean NOT NULL DEFAULT false;

-- ─── 2. Helper (SECURITY DEFINER: lee usuarios sin chocar con RLS) ───
CREATE OR REPLACE FUNCTION public.es_contador()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE((SELECT u.es_contador FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_contador() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_contador() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_contador() TO authenticated;

-- ─── 3. Trigger guard: frena escrituras incluso vía SECURITY DEFINER ─
CREATE OR REPLACE FUNCTION public.fn_contador_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF public.es_contador() THEN
    RAISE EXCEPTION 'Modo contador: solo lectura';
  END IF;
  RETURN NULL; -- statement-level BEFORE: el valor de retorno se ignora
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_contador_guard() FROM PUBLIC, anon;

-- ─── 4. Lockdown: 3 policies + trigger en TODA tabla con RLS ─────────
-- Sin whitelist: el contador no escribe en ninguna tabla, tampoco en
-- usuarios (su fila se crea al registrarse, cuando es_contador aún es
-- false; después la administra el admin, que no es contador).
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND rowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS contador_no_ins ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_ins ON %I AS RESTRICTIVE FOR INSERT '
      'TO authenticated WITH CHECK (NOT public.es_contador())', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_upd ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_upd ON %I AS RESTRICTIVE FOR UPDATE '
      'TO authenticated USING (NOT public.es_contador())', t);
    EXECUTE format('DROP POLICY IF EXISTS contador_no_del ON %I', t);
    EXECUTE format(
      'CREATE POLICY contador_no_del ON %I AS RESTRICTIVE FOR DELETE '
      'TO authenticated USING (NOT public.es_contador())', t);
    EXECUTE format('DROP TRIGGER IF EXISTS contador_guard ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE ON %I '
      'FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard()', t);
  END LOOP;
END $$;

-- ─── 5. usuarios_guard: es_contador solo lo cambia un admin ──────────
-- Recrea la función de 052 agregando la misma regla que es_admin /
-- ver_costos / es_planta. El SQL Editor (auth.uid() IS NULL) sigue confiado.
CREATE OR REPLACE FUNCTION public.usuarios_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_admin boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- postgres / service_role: confiado
  END IF;
  SELECT es_admin INTO caller_admin FROM usuarios WHERE id = auth.uid();
  IF TG_OP = 'INSERT' THEN
    NEW.es_admin := false;
    NEW.ver_costos := false;
    NEW.es_planta := false;
    NEW.es_contador := false;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.es_admin IS DISTINCT FROM OLD.es_admin
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_admin';
    END IF;
    IF NEW.ver_costos IS DISTINCT FROM OLD.ver_costos
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar ver_costos';
    END IF;
    IF NEW.es_planta IS DISTINCT FROM OLD.es_planta
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_planta';
    END IF;
    IF NEW.es_contador IS DISTINCT FROM OLD.es_contador
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar es_contador';
    END IF;
    IF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       AND OLD.empresa_id IS NOT NULL
       AND NOT COALESCE(caller_admin, false) THEN
      RAISE EXCEPTION 'No autorizado a cambiar de empresa';
    END IF;
  END IF;
  RETURN NEW;
END $$;

COMMIT;

-- Verificación:
-- 1) Columna y función:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name='usuarios' AND column_name='es_contador';      -- 1 fila
--    SELECT public.es_contador();                                      -- false (SQL editor)
-- 2) Las 3 policies en tablas sensibles (mismo conteo por policy):
--    SELECT policyname, count(*) FROM pg_policies
--     WHERE policyname LIKE 'contador_no_%' GROUP BY policyname;      -- 3 filas, mismo count
--    SELECT tablename FROM pg_policies WHERE policyname='contador_no_ins'
--     AND tablename IN ('ventas','asientos','usuarios','ordenes_produccion'); -- 4 filas
-- 3) Restrictivas de verdad:
--    SELECT permissive FROM pg_policies
--     WHERE policyname='contador_no_ins' LIMIT 1;                     -- RESTRICTIVE
-- 4) Trigger en todas las tablas con RLS:
--    SELECT count(*) FROM pg_trigger WHERE tgname='contador_guard';
--    -- = SELECT count(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity
-- 5) Guard extendido:
--    SELECT prosrc LIKE '%es_contador%' FROM pg_proc WHERE proname='usuarios_guard'; -- true
```

- [ ] **Step 2: Actualizar CLAUDE.md**

En la sección **Módulos**, reemplazar el texto final del ítem Modo Planta:

```
**Regla: toda tabla nueva con RLS necesita su policy `planta_lockdown`**
```

por:

```
**Regla: toda tabla nueva con RLS necesita su policy `planta_lockdown`, las tres `contador_no_ins/upd/del` y el trigger `contador_guard`** (migración 053: Modo Contador — usuario `es_contador=true` en solo lectura total; los DO-loops de 052/053 son el molde)
```

En la sección **Supabase**, cambiar `**Migraciones:** \`migrations/001\` a \`027\`` por `**Migraciones:** \`migrations/001\` a \`053\``.

- [ ] **Step 3: Chequear sintaxis SQL a ojo y commitear**

Verificar que cada `EXECUTE format` usa `%I` y que el DO-loop no tiene whitelist. Después:

```bash
git add migrations/053_modo_contador.sql CLAUDE.md
git commit -m "feat: migración 053 Modo Contador — es_contador + solo lectura RLS + trigger guard"
```

---

### Task 2: Utilidades puras de export + tests (TDD)

**Files:**
- Modify: `tests/_harness.js:83` (agregar 4 globals al sandbox)
- Create: `tests/contador-export.test.js`
- Modify: `index.html:2339` (insertar bloque de utilidades después de `const RPC  =(fn,args)=>db('POST','rpc/'+fn,args||{});`)

**Interfaces:**
- Produces: `periodoRango(mes) → {desde,hasta}|null`, `csvCampo(v) → string`, `csvArmar(filas) → string`, `csvNum(n) → string`, `csvFecha(iso) → string`, `crc32(bytes) → number`, `zipStore(archivos:[{nombre,contenido}]) → Uint8Array`, `descargarBytes(nombre,bytes,mime)`, `descargarTexto(nombre,texto)`. Las consumen las Tasks 3.

- [ ] **Step 1: Escribir el test que falla**

Crear `tests/contador-export.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('periodoRango arma desde/hasta del mes', () => {
  assert.deepEqual(erp.run(`periodoRango('2026-07')`), {desde:'2026-07-01', hasta:'2026-07-31'});
  assert.deepEqual(erp.run(`periodoRango('2026-02')`), {desde:'2026-02-01', hasta:'2026-02-28'});
  assert.deepEqual(erp.run(`periodoRango('2028-02')`), {desde:'2028-02-01', hasta:'2028-02-29'}); // bisiesto
  assert.equal(erp.run(`periodoRango('2026-13')`), null);
  assert.equal(erp.run(`periodoRango('')`), null);
});

test('csvCampo escapa ; comillas y saltos', () => {
  assert.equal(erp.run(`csvCampo('hola')`), 'hola');
  assert.equal(erp.run(`csvCampo('a;b')`), '"a;b"');
  assert.equal(erp.run(`csvCampo('di"jo')`), '"di""jo"');
  assert.equal(erp.run(`csvCampo(null)`), '');
});

test('csvArmar: BOM, separador ; y CRLF', () => {
  const s = erp.run(`csvArmar([['A','B'],['1','2;3']])`);
  assert.ok(s.startsWith('﻿'));
  assert.equal(s, '﻿A;B\r\n1;"2;3"\r\n');
});

test('csvNum y csvFecha en formato argentino', () => {
  assert.equal(erp.run(`csvNum(1234.5)`), '1234,50');
  assert.equal(erp.run(`csvNum(null)`), '0,00');
  assert.equal(erp.run(`csvFecha('2026-07-19')`), '19/07/2026');
  assert.equal(erp.run(`csvFecha(null)`), '');
});

test('crc32 valores conocidos', () => {
  // CRC32 de 'abc' = 0x352441C2 (vector estándar)
  assert.equal(erp.run(`crc32(new TextEncoder().encode('abc'))`), 0x352441C2);
  assert.equal(erp.run(`crc32(new Uint8Array(0))`), 0);
});

test('zipStore genera un ZIP store válido estructuralmente', () => {
  const bytes = erp.run(`Array.from(zipStore([{nombre:'a.csv', contenido:'hola'}]))`);
  const u = Uint8Array.from(bytes);
  const dv = new DataView(u.buffer);
  assert.equal(dv.getUint32(0, true), 0x04034b50);            // local file header
  assert.equal(dv.getUint32(u.length - 22, true), 0x06054b50); // EOCD al final
  assert.equal(dv.getUint16(u.length - 22 + 10, true), 1);     // 1 entrada
  const crcEsperado = erp.run(`crc32(new TextEncoder().encode('hola'))`);
  assert.equal(dv.getUint32(14, true), crcEsperado);
});

test('zipStore multiarchivo: offsets consistentes', () => {
  const bytes = erp.run(`Array.from(zipStore([{nombre:'a.txt',contenido:'AA'},{nombre:'b.txt',contenido:'BBBB'}]))`);
  const u = Uint8Array.from(bytes);
  const dv = new DataView(u.buffer);
  assert.equal(dv.getUint16(u.length - 22 + 10, true), 2);     // 2 entradas
  // Segundo local header arranca en 30+5+2 = 37 ('a.txt' = 5 chars, 'AA' = 2)
  assert.equal(dv.getUint32(37, true), 0x04034b50);
});
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `node --test tests/contador-export.test.js`
Expected: FAIL con `periodoRango is not defined` (o ReferenceError equivalente).

- [ ] **Step 3: Harness — agregar los globals que usa el generador ZIP**

En `tests/_harness.js`, después de la línea `Blob: function () {},` (línea 83), agregar:

```js
    TextEncoder,
    TextDecoder,
    Uint8Array,
    DataView,
```

- [ ] **Step 4: Insertar las utilidades en index.html**

Inmediatamente después de la línea 2339 (`const RPC  =(fn,args)=>db('POST','rpc/'+fn,args||{});`), insertar:

```js

// ─── EXPORTABLES: utilidades puras (testeadas en tests/contador-export.test.js) ───
function periodoRango(mes){ // 'AAAA-MM' → {desde,hasta} (fechas ISO del mes)
  const m=/^(\d{4})-(\d{2})$/.exec(String(mes||''));
  if(!m)return null;
  const a=+m[1],mm=+m[2];
  if(mm<1||mm>12)return null;
  const ult=new Date(Date.UTC(a,mm,0)).getUTCDate();
  const p=n=>String(n).padStart(2,'0');
  return {desde:`${a}-${p(mm)}-01`,hasta:`${a}-${p(mm)}-${p(ult)}`};
}
function csvCampo(v){
  if(v===null||v===undefined)v='';
  v=String(v);
  return /[;"\n\r]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;
}
function csvArmar(filas){return '﻿'+filas.map(f=>f.map(csvCampo).join(';')).join('\r\n')+'\r\n';}
function csvNum(n){return Number(n||0).toFixed(2).replace('.',',');}
function csvFecha(iso){
  if(!iso)return'';
  const s=String(iso).slice(0,10).split('-');
  return s.length===3?`${s[2]}/${s[1]}/${s[0]}`:String(iso);
}
const _CRC_TABLA=(()=>{const t=new Uint32Array(256);for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1);t[n]=c>>>0;}return t;})();
function crc32(bytes){let c=0xFFFFFFFF;for(let i=0;i<bytes.length;i++)c=_CRC_TABLA[(c^bytes[i])&0xFF]^(c>>>8);return (c^0xFFFFFFFF)>>>0;}
// ZIP formato "store" (sin compresión): suficiente para CSVs chicos, cero dependencias.
function zipStore(archivos){
  const enc=new TextEncoder();
  const partes=[],centrales=[];let offset=0;
  const FECHA_DOS=0x2100,HORA_DOS=0; // fecha DOS fija (determinístico para tests)
  for(const a of archivos){
    const nombre=enc.encode(a.nombre);
    const data=typeof a.contenido==='string'?enc.encode(a.contenido):a.contenido;
    const crc=crc32(data);
    const local=new Uint8Array(30+nombre.length);
    const dv=new DataView(local.buffer);
    dv.setUint32(0,0x04034b50,true);dv.setUint16(4,20,true);dv.setUint16(6,0x0800,true); // flag UTF-8
    dv.setUint16(8,0,true);dv.setUint16(10,HORA_DOS,true);dv.setUint16(12,FECHA_DOS,true);
    dv.setUint32(14,crc,true);dv.setUint32(18,data.length,true);dv.setUint32(22,data.length,true);
    dv.setUint16(26,nombre.length,true);dv.setUint16(28,0,true);
    local.set(nombre,30);
    partes.push(local,data);
    const cen=new Uint8Array(46+nombre.length);
    const dc=new DataView(cen.buffer);
    dc.setUint32(0,0x02014b50,true);dc.setUint16(4,20,true);dc.setUint16(6,20,true);
    dc.setUint16(8,0x0800,true);dc.setUint16(10,0,true);
    dc.setUint16(12,HORA_DOS,true);dc.setUint16(14,FECHA_DOS,true);
    dc.setUint32(16,crc,true);dc.setUint32(20,data.length,true);dc.setUint32(24,data.length,true);
    dc.setUint16(28,nombre.length,true);
    dc.setUint32(42,offset,true);
    cen.set(nombre,46);
    centrales.push(cen);
    offset+=local.length+data.length;
  }
  let cdSize=0;centrales.forEach(c=>cdSize+=c.length);
  const eocd=new Uint8Array(22);const de=new DataView(eocd.buffer);
  de.setUint32(0,0x06054b50,true);
  de.setUint16(8,archivos.length,true);de.setUint16(10,archivos.length,true);
  de.setUint32(12,cdSize,true);de.setUint32(16,offset,true);
  const out=new Uint8Array(offset+cdSize+22);let p=0;
  for(const parte of [...partes,...centrales,eocd]){out.set(parte,p);p+=parte.length;}
  return out;
}
function descargarBytes(nombre,bytes,mime){
  const blob=new Blob([bytes],{type:mime||'application/octet-stream'});
  const a=document.createElement('a');
  a.href=URL.createObjectURL(blob);a.download=nombre;a.click();
  setTimeout(()=>URL.revokeObjectURL(a.href),5000);
}
function descargarTexto(nombre,texto){descargarBytes(nombre,new TextEncoder().encode(texto),'text/csv;charset=utf-8');}
```

- [ ] **Step 5: Correr los tests y verificar que pasan**

Run: `node --test tests/contador-export.test.js`
Expected: PASS 7/7.

Run: `node --test tests/` — la suite completa sigue verde (57+ tests).

- [ ] **Step 6: node --check y commit**

```bash
python3 - <<'EOF'
import re
html = open('index.html').read()
scripts = re.findall(r'<script>([\s\S]*?)</script>', html)
open('/tmp/erp-script.js','w').write(max(scripts, key=len))
EOF
node --check /tmp/erp-script.js
git add tests/_harness.js tests/contador-export.test.js index.html
git commit -m "feat: utilidades puras de export CSV/ZIP con tests"
```

---

### Task 3: Builders, página Exportables y navegación

**Files:**
- Modify: `index.html` — builders después del bloque de utilidades de la Task 2; página HTML antes del comentario `<!-- CONTABILIDAD: Cobros y Pagos -->` (línea 1008); `PAGE_TO_GROUP` (2650); `GROUP_TABS.contabilidad` (2660); `groupMods.contabilidad` (7859); `PAGE_RENDERS` (4113)

**Interfaces:**
- Consumes: `periodoRango`, `csvArmar`, `csvNum`, `csvFecha`, `zipStore`, `descargarBytes`, `descargarTexto` (Task 2); `GET` (existente); `esc`, `notify` (existentes).
- Produces: `EXPORT_BUILDERS` (array de `{titulo, fn(desde,hasta) → Promise<{nombre,contenido,resumen}>}`), `exportarUno(idx)`, `renderExportables()`, `descargarCarpeta()`, página `exportables`.

- [ ] **Step 1: Insertar los builders**

Inmediatamente después de la línea `function descargarTexto(...)` insertada en la Task 2, agregar:

```js

// ─── Exportables del período (contador y admin) ───
async function expSubdiarioVentas(desde,hasta){
  const vs=await GET('ventas',`?fecha=gte.${desde}&fecha=lte.${hasta}&order=fecha,nro_remito&select=fecha,nro_remito,nro_pedido,cliente,condicion_pago,estado,total`);
  const filas=[['Fecha','Remito','Pedido','Cliente','Condición de pago','Estado','Total']];
  let tot=0;
  for(const v of vs){filas.push([csvFecha(v.fecha),v.nro_remito,v.nro_pedido||'',v.cliente,v.condicion_pago||'',v.estado||'',csvNum(v.total)]);tot+=Number(v.total||0);}
  filas.push(['','','','','','TOTAL',csvNum(tot)]);
  return {nombre:`subdiario_ventas_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`Subdiario ventas: ${vs.length} remitos · total ${csvNum(tot)}`};
}
async function expIvaVentas(desde,hasta){
  const fe=await GET('facturas_emitidas',`?fecha=gte.${desde}&fecha=lte.${hasta}&order=fecha,punto_venta,numero&select=fecha,tipo_comprobante,punto_venta,numero,doc_tipo,doc_nro,imp_neto,imp_iva,imp_total,cae`);
  const filas=[['Fecha','Tipo cbte','Pto vta','Número','Doc tipo','Doc nro','Neto','IVA','Total','CAE']];
  let n=0,i=0,t=0;
  for(const f of fe){filas.push([csvFecha(f.fecha),f.tipo_comprobante,f.punto_venta,f.numero,f.doc_tipo,f.doc_nro,csvNum(f.imp_neto),csvNum(f.imp_iva),csvNum(f.imp_total),f.cae]);n+=+f.imp_neto||0;i+=+f.imp_iva||0;t+=+f.imp_total||0;}
  filas.push(['','','','','','TOTALES',csvNum(n),csvNum(i),csvNum(t),'']);
  return {nombre:`iva_ventas_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`IVA ventas: ${fe.length} comprobantes · neto ${csvNum(n)} · IVA ${csvNum(i)}`};
}
async function _proveedoresMap(){
  const ps=await GET('proveedores','?select=id,nombre,cuit');
  const m={};for(const p of ps)m[p.id]={nombre:p.nombre,cuit:p.cuit||''};
  return m;
}
async function expSubdiarioCompras(desde,hasta){
  const [fr,pm]=await Promise.all([
    GET('facturas_recibidas',`?fecha=gte.${desde}&fecha=lte.${hasta}&order=fecha,nro&select=fecha,fecha_vto,nro,proveedor_id,neto,iva,total,moneda,tipo_cambio,estado_match`),
    _proveedoresMap()]);
  const filas=[['Fecha','Comprobante','Proveedor','CUIT','Moneda','T.C.','Total','Vencimiento','Estado']];
  for(const f of fr){const p=pm[f.proveedor_id]||{nombre:'',cuit:''};
    filas.push([csvFecha(f.fecha),f.nro,p.nombre,p.cuit,f.moneda||'',csvNum(f.tipo_cambio),csvNum(f.total),csvFecha(f.fecha_vto),f.estado_match||'']);}
  return {nombre:`subdiario_compras_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`Subdiario compras: ${fr.length} comprobantes`};
}
async function expIvaCompras(desde,hasta){
  const [fr,pm]=await Promise.all([
    GET('facturas_recibidas',`?fecha=gte.${desde}&fecha=lte.${hasta}&order=fecha,nro&select=fecha,nro,proveedor_id,neto,iva,total`),
    _proveedoresMap()]);
  const filas=[['Fecha','Comprobante','Proveedor','CUIT','Neto','IVA','Total']];
  let n=0,i=0,t=0;
  for(const f of fr){const p=pm[f.proveedor_id]||{nombre:'',cuit:''};
    filas.push([csvFecha(f.fecha),f.nro,p.nombre,p.cuit,csvNum(f.neto),csvNum(f.iva),csvNum(f.total)]);n+=+f.neto||0;i+=+f.iva||0;t+=+f.total||0;}
  filas.push(['','','','TOTALES',csvNum(n),csvNum(i),csvNum(t)]);
  return {nombre:`iva_compras_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`IVA compras: ${fr.length} comprobantes · neto ${csvNum(n)} · IVA ${csvNum(i)}`};
}
async function expMayores(desde,hasta){
  const as=await GET('asientos',`?fecha=gte.${desde}&fecha=lte.${hasta}&estado=eq.confirmado&order=fecha,numero&select=id,numero,fecha,descripcion`);
  const cuentas=await GET('cuentas_contables','?select=id,codigo,nombre&order=codigo');
  const cm={};for(const c of cuentas)cm[c.id]=c;
  let lineas=[];
  // PostgREST in.(): en lotes de 80 ids para no exceder el largo de URL
  for(let i=0;i<as.length;i+=80){
    const ids=as.slice(i,i+80).map(a=>a.id).join(',');
    lineas=lineas.concat(await GET('asiento_lineas',`?asiento_id=in.(${ids})&select=asiento_id,cuenta_id,debe,haber,descripcion`));
  }
  const am={};for(const a of as)am[a.id]=a;
  lineas.sort((x,y)=>{
    const cx=cm[x.cuenta_id]?.codigo||'',cy=cm[y.cuenta_id]?.codigo||'';
    if(cx!==cy)return cx<cy?-1:1;
    const fx=am[x.asiento_id]?.fecha||'',fy=am[y.asiento_id]?.fecha||'';
    if(fx!==fy)return fx<fy?-1:1;
    return (am[x.asiento_id]?.numero||0)-(am[y.asiento_id]?.numero||0);
  });
  const filas=[['Cuenta','Nombre','Fecha','Asiento','Descripción','Debe','Haber','Saldo acumulado']];
  let ctaActual=null,saldo=0;
  for(const l of lineas){
    const c=cm[l.cuenta_id]||{codigo:'?',nombre:'(cuenta eliminada)'};
    if(c.codigo!==ctaActual){ctaActual=c.codigo;saldo=0;}
    saldo+=Number(l.debe||0)-Number(l.haber||0);
    const a=am[l.asiento_id]||{};
    filas.push([c.codigo,c.nombre,csvFecha(a.fecha),a.numero||'',l.descripcion||a.descripcion||'',csvNum(l.debe),csvNum(l.haber),csvNum(saldo)]);
  }
  return {nombre:`mayores_${desde}_a_${hasta}.csv`,contenido:csvArmar(filas),
          resumen:`Mayores: ${as.length} asientos · ${lineas.length} líneas`};
}
async function expPlanCuentas(){
  const cs=await GET('cuentas_contables','?select=codigo,nombre,tipo,imputable,activa&order=codigo');
  const filas=[['Código','Nombre','Tipo','Imputable','Activa']];
  for(const c of cs)filas.push([c.codigo,c.nombre,c.tipo,c.imputable?'SI':'NO',c.activa?'SI':'NO']);
  return {nombre:'plan_de_cuentas.csv',contenido:csvArmar(filas),
          resumen:`Plan de cuentas: ${cs.length} cuentas`};
}
const EXPORT_BUILDERS=[
  {titulo:'Subdiario de ventas',fn:expSubdiarioVentas},
  {titulo:'IVA ventas',fn:expIvaVentas},
  {titulo:'Subdiario de compras',fn:expSubdiarioCompras},
  {titulo:'IVA compras',fn:expIvaCompras},
  {titulo:'Mayores',fn:expMayores},
  {titulo:'Plan de cuentas',fn:(d,h)=>expPlanCuentas()},
];
async function exportarUno(idx){
  const btns=document.querySelectorAll('#exportables-lista button');
  const mes=document.getElementById('exp-mes').value;
  const r=periodoRango(mes);
  if(!r)return notify('Elegí un mes válido','err');
  try{
    btns.forEach(b=>b.disabled=true);
    const res=await EXPORT_BUILDERS[idx].fn(r.desde,r.hasta);
    descargarTexto(res.nombre,res.contenido);
    notify(res.resumen,'ok');
  }catch(e){notify('Error al exportar: '+e.message,'err');}
  finally{btns.forEach(b=>b.disabled=false);}
}
function renderExportables(){
  const mesEl=document.getElementById('exp-mes');
  if(mesEl&&!mesEl.value){
    const hoy=new Date();hoy.setMonth(hoy.getMonth()-1); // mes anterior por defecto
    mesEl.value=`${hoy.getFullYear()}-${String(hoy.getMonth()+1).padStart(2,'0')}`;
  }
  document.getElementById('exportables-lista').innerHTML=EXPORT_BUILDERS.map((b,i)=>
    `<div style="display:flex;align-items:center;justify-content:space-between;padding:10px 14px;border:1px solid var(--border);border-radius:6px">
       <span style="font-size:13px;color:var(--text)">${esc(b.titulo)}</span>
       <button class="btn btn-ghost btn-sm" onclick="exportarUno(${i})">Descargar CSV</button>
     </div>`).join('');
}
async function descargarCarpeta(){
  const mes=document.getElementById('exp-mes').value;
  const r=periodoRango(mes);
  if(!r)return notify('Elegí un mes válido','err');
  const btn=document.getElementById('btn-carpeta');
  try{
    btn.disabled=true;btn.textContent='Armando carpeta...';
    const archivos=[];const resumenes=[];
    for(const b of EXPORT_BUILDERS){
      const res=await b.fn(r.desde,r.hasta);
      archivos.push({nombre:res.nombre,contenido:res.contenido});
      resumenes.push(res.resumen);
    }
    const gen=new Date();
    archivos.unshift({nombre:'resumen.txt',contenido:
      `VitalStock — Carpeta del período ${mes}\r\n`+
      `Empresa: ${currentEmpresa?.nombre||''}\r\n`+
      `Generado: ${gen.toLocaleDateString('es-AR')} ${gen.toLocaleTimeString('es-AR')}\r\n\r\n`+
      resumenes.join('\r\n')+'\r\n'});
    const zip=zipStore(archivos);
    descargarBytes(`VitalStock_${mes}.zip`,zip,'application/zip');
    notify('Carpeta del período descargada','ok');
  }catch(e){notify('Error al armar la carpeta: '+e.message,'err');}
  finally{btn.disabled=false;btn.textContent='Descargar carpeta del período (ZIP)';}
}
```

- [ ] **Step 2: Insertar el HTML de la página**

Inmediatamente antes de la línea 1008 (`    <!-- CONTABILIDAD: Cobros y Pagos -->`), insertar:

```html
    <!-- CONTABILIDAD: Exportables -->
    <div class="page" id="page-exportables">
      <div class="page-header"><div class="page-title">Exportables</div><div class="page-sub">// subdiarios, IVA y mayores en CSV — listos para el estudio contable</div><div class="tabs"></div></div>
      <div class="page-content">
        <div class="toolbar">
          <label style="font-size:12px;color:var(--text2)">Período <input type="month" id="exp-mes" style="margin-left:6px;background:var(--surface2);border:1px solid var(--border);border-radius:5px;padding:7px 9px;color:var(--text);font-size:13px;font-family:var(--sans)"></label>
          <button class="btn" id="btn-carpeta" onclick="descargarCarpeta()">Descargar carpeta del período (ZIP)</button>
        </div>
        <div id="exportables-lista" style="display:flex;flex-direction:column;gap:8px;max-width:560px"></div>
        <div style="font-size:11px;color:var(--text3);margin-top:12px">CSV en UTF-8 con separador «;» — se abren directo en Excel. Decimales con coma, fechas DD/MM/AAAA.</div>
      </div>
    </div>

```

- [ ] **Step 3: Registrar la navegación (las TRES estructuras + renders)**

1. `PAGE_TO_GROUP` (línea 2650): agregar `exportables:'contabilidad',` justo antes de `config:'config'`.
2. `GROUP_TABS.contabilidad` (línea 2660): después de `{k:'conciliacion',l:'Conciliación bancaria'},` agregar:
   ```js
    {k:'exportables',l:'Exportables'},
   ```
3. `groupMods` dentro de `aplicarPermisos` (línea 7859): en el array de `contabilidad`, agregar `'exportables'` al final (queda `...,'correlatividad','conciliacion','exportables']`).
4. `PAGE_RENDERS` (línea 4113): agregar la entrada `exportables:[renderExportables],` (por ejemplo después de la entrada de `conciliacion`; si no existe entrada de conciliación, agregarla al final del objeto).

- [ ] **Step 4: Validar y commitear**

```bash
python3 - <<'EOF'
import re
html = open('index.html').read()
scripts = re.findall(r'<script>([\s\S]*?)</script>', html)
open('/tmp/erp-script.js','w').write(max(scripts, key=len))
EOF
node --check /tmp/erp-script.js
node --test tests/
git add index.html
git commit -m "feat: página Exportables — 6 CSVs del período + carpeta ZIP"
```

---

### Task 4: Modo solo-lectura en el boot (banner, guard, logout)

**Files:**
- Modify: `index.html` — CSS (antes de la línea 231 `@media (max-width:768px){`), banner HTML (antes de la línea 364 `<div id="app-screen">`), `db()` (2321), `loadEmpresaAndStart()` (2539), `doLogout()` (2514), `aplicarPermisos()` (7867)

**Interfaces:**
- Consumes: `currentUserData.es_contador` (columna de la Task 1, llega por el `loadAll` de `usuarios`).
- Produces: `window._modoContador` (boolean), clase CSS `modo-contador` en `<body>`, `#contador-banner`. Los consume la Task 5 (badge) y el guard de `db()`.

- [ ] **Step 1: CSS del banner**

Antes de la línea 231 (`@media (max-width:768px){`), agregar:

```css
body.modo-contador #contador-banner{display:block!important}
```

- [ ] **Step 2: HTML del banner**

Inmediatamente antes de la línea 364 (`<div id="app-screen">`), insertar:

```html
<div id="contador-banner" style="display:none;position:sticky;top:0;z-index:1500;background:var(--accent);color:#fff;font-size:12.5px;font-weight:600;padding:7px 14px;text-align:center">
  👁 Modo contador — solo lectura · <span id="contador-banner-empresa"></span>
</div>
```

- [ ] **Step 3: Guard en `db()`**

En `db()` (línea 2321), como PRIMERA línea del cuerpo de la función (antes del primer `fetch`), agregar:

```js
  if(window._modoContador&&method!=='GET'){throw new Error('Modo contador: acceso de solo lectura');}
```

- [ ] **Step 4: Activación en el boot**

En `loadEmpresaAndStart()`, inmediatamente después de la línea 2539 (`currentUserData=usuariosEmpresa.find(u=>u.id===currentUser.id)||null;`) y ANTES de `aplicarPermisos();`, agregar:

```js
    // Modo contador: solo lectura (la garantía real es el RLS; esto es UX)
    window._modoContador=currentUserData?.es_contador===true;
    document.body.classList.toggle('modo-contador',window._modoContador);
    if(window._modoContador)document.getElementById('contador-banner-empresa').textContent=currentEmpresa.nombre;
```

- [ ] **Step 5: Reset en `doLogout()`**

En `doLogout()` (línea 2514), antes de la línea `document.getElementById('auth-screen').style.display='flex';`, agregar:

```js
  window._modoContador=false;
  document.body.classList.remove('modo-contador');
```

Sin esto, el próximo usuario que entre en la misma pestaña heredaría el guard de solo lectura.

- [ ] **Step 6: Primera página permitida para el contador**

En `aplicarPermisos()` (línea 7867-7869), la lista de fallback no incluye ninguna página de contabilidad. Reemplazar:

```js
    const first=['mp','pt','cert','op','compras','presupuestos','ventas','clientes','costos','trace'].find(m=>misPermisos.includes(m));
```

por:

```js
    const first=['mp','pt','cert','op','compras','presupuestos','ventas','clientes','costos','trace','cuentas'].find(m=>misPermisos.includes(m));
```

- [ ] **Step 7: Validar y commitear**

```bash
python3 - <<'EOF'
import re
html = open('index.html').read()
scripts = re.findall(r'<script>([\s\S]*?)</script>', html)
open('/tmp/erp-script.js','w').write(max(scripts, key=len))
EOF
node --check /tmp/erp-script.js
node --test tests/
git add index.html
git commit -m "feat: modo contador en el boot — banner, guard de escritura y reset en logout"
```

---

### Task 5: Admin UI — tilde "Contador" en el modal de permisos

**Files:**
- Modify: `index.html` — modal-permisos HTML (después de la línea 2224, el `</label>` de ver_costos), `MODULOS_LABELS` (7206), `renderUsuarios()` (7220), `openPermisos()` (7245), `savePermisos()` (7255-7261)

**Interfaces:**
- Consumes: `usuarios.es_contador` (Task 1), `usuarios_guard` permite el PATCH porque el caller es admin.
- Produces: checkbox `#permisos-escontador`, función `onContadorToggle(el)`, badge CONTADOR en la lista de usuarios.

- [ ] **Step 1: Checkbox en el modal**

Después de la línea 2224 (el `</label>` que cierra el checkbox de ver costos), agregar:

```html
      <label style="display:flex;align-items:center;gap:10px;padding:8px 10px;background:var(--surface2);border-radius:5px;cursor:pointer;font-size:13px;margin-top:4px">
        <input type="checkbox" id="permisos-escontador" onchange="onContadorToggle(this)" style="width:15px;height:15px;accent-color:var(--accent)">
        <span>Contador (solo lectura)<br><span style="font-size:11px;color:var(--text3)">Puede ver pero no modificar nada — pensado para el contador del estudio. Al tildarlo se sugieren Contabilidad, Ventas, Compras y ver costos.</span></span>
      </label>
```

- [ ] **Step 2: Módulos Contabilidad y Compras asignables desde la UI**

`MODULOS_LABELS` (línea 7206) hoy no ofrece ni contabilidad ni compras, así que un no-admin jamás podría verlas. Reemplazar la línea por:

```js
const MODULOS_LABELS={dash:'Dashboard',mp:'Materia prima',pt:'Prod. terminados',cert:'Certificados MTC',op:'Órdenes producción',compras:'Compras',ventas:'Ventas',trace:'Trazabilidad',cuentas:'Contabilidad'};
```

(`cuentas` está en `groupMods.contabilidad`, con lo cual otorga el grupo Contabilidad completo — tabs de Exportables incluidas. `compras` idem para su grupo.)

- [ ] **Step 3: `onContadorToggle` + `openPermisos` + `savePermisos`**

Después de `openPermisos` (línea 7253, tras su `}`), agregar:

```js
function onContadorToggle(el){
  if(!el.checked)return;
  // Sugerencias al marcar contador (editables antes de guardar)
  document.getElementById('permisos-esadmin').value='false';
  document.getElementById('permisos-vercostos').checked=true;
  for(const mod of ['cuentas','ventas','compras']){
    const c=document.getElementById('perm-'+mod);
    if(c)c.checked=true;
  }
}
```

En `openPermisos` (línea 7245), después de `document.getElementById('permisos-vercostos').checked=u.ver_costos===true;`, agregar:

```js
  document.getElementById('permisos-escontador').checked=u.es_contador===true;
```

En `savePermisos` (línea 7255), después de `const verCostos=document.getElementById('permisos-vercostos').checked;`, agregar:

```js
  const esContador=document.getElementById('permisos-escontador').checked;
  if(esContador&&esAdmin){notify('Un contador no puede ser administrador','err');return;}
```

y en el PATCH (línea 7261) reemplazar:

```js
    await PATCH('usuarios',{es_admin:esAdmin,ver_costos:verCostos},`?id=eq.${userId}`);
```

por:

```js
    await PATCH('usuarios',{es_admin:esAdmin,ver_costos:verCostos,es_contador:esContador},`?id=eq.${userId}`);
```

(El modal solo se abre para otros usuarios — `renderUsuarios` no ofrece el botón sobre uno mismo — así que el admin no puede dejarse a sí mismo en solo lectura.)

- [ ] **Step 4: Badge CONTADOR en la lista**

En `renderUsuarios()` (línea 7220), reemplazar:

```js
      <td>${esAdmin?'<span class="badge badge-purple">ADMIN</span>':'<span class="badge badge-blue">EMPLEADO</span>'}</td>
```

por:

```js
      <td>${esAdmin?'<span class="badge badge-purple">ADMIN</span>':u.es_contador?'<span class="badge badge-amber">CONTADOR</span>':'<span class="badge badge-blue">EMPLEADO</span>'}</td>
```

(`badge-amber` ya existe en el CSS.)

- [ ] **Step 5: Validar y commitear**

```bash
python3 - <<'EOF'
import re
html = open('index.html').read()
scripts = re.findall(r'<script>([\s\S]*?)</script>', html)
open('/tmp/erp-script.js','w').write(max(scripts, key=len))
EOF
node --check /tmp/erp-script.js
node --test tests/
git add index.html
git commit -m "feat: tilde Contador (solo lectura) en el modal de permisos + módulos Contabilidad/Compras asignables"
```

---

### Task 6: Gate de producción — migración, push y E2E (con el usuario)

**Files:** ninguno nuevo (posibles hotfixes sobre `migrations/053_modo_contador.sql` / `index.html`).

Este task lo coordina el controlador CON el usuario — no un subagente. Orden estricto (regla del repo: SQL antes del deploy):

- [ ] **Step 1: Migración en el SQL Editor.** Copiar `migrations/053_modo_contador.sql` al portapapeles (`pbcopy < migrations/053_modo_contador.sql`), pedirle al usuario que la corra en el SQL Editor de Supabase y espere el "listo". Correr las queries de verificación del pie (el usuario pega los resultados o las corre él).
- [ ] **Step 2: Push a main (deploy).** Con la migración verificada, pedir autorización explícita del usuario para `git push` (deploya a erp.vitalmetsa.com vía Netlify).
- [ ] **Step 3: E2E en producción.** El usuario hace los logins (nunca el agente — no maneja credenciales):
  1. Usuario de prueba se registra con el código de invitación (o se reutiliza uno existente no-admin).
  2. Admin lo marca "Contador" en Configuración → Usuarios → Permisos (verificar sugerencias de módulos al tildar).
  3. Re-login del contador: banner visible, solo módulos otorgados, Config oculta.
  4. Intento de escritura: por UI (debe cortar el guard de `db()`) y por REST directo con su JWT (`curl -X POST .../rest/v1/clientes` → 403 con `contador_no_ins`; `curl -X POST .../rest/v1/rpc/crear_asiento` → error "Modo contador: solo lectura" del trigger).
  5. Exportables: los 6 CSVs del mes con datos reales (abrir en Excel, verificar separador/decimales) + carpeta ZIP (`unzip -t` local: 7 archivos OK).
  6. Destildar "Contador" → re-login → vuelve a ser empleado normal.
  7. La operación normal del admin y el Modo Planta siguen funcionando (una escritura cualquiera del admin pasa — el trigger no molesta a no-contadores).
- [ ] **Step 4: Cierre.** Marcar el spec como implementado y verificado, actualizar el ledger `.superpowers/sdd/progress.md`, commitear docs. La primera carpeta ZIP generada queda para mostrarle al contador del estudio (validación de formatos para el Libro IVA).
