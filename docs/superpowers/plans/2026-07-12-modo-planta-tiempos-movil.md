# Modo Planta (tiempos de producción desde el móvil) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que los operarios registren tiempos de producción (iniciar/pausar/finalizar operaciones de una OP) desde el celular, escaneando un QR impreso por OP, con una cuenta compartida `planta` limitada por RLS a las tablas de producción.

**Architecture:** Un `planta.html` standalone (vanilla JS + CSS embebido, cero CDN) en la raíz del repo, servido por el mismo Netlify en `erp.vitalmetsa.com/planta.html`. Habla directo con Supabase REST usando la misma semántica de timers que el ERP (`op_time_entries` productivo/pausa, índice único de 047, quality gates de 041 en la DB). El ERP (`index.html`) solo suma un botón "QR planta" en el modal Tiempos. La migración 052 agrega `usuarios.es_planta` + policies RESTRICTIVE que bloquean al usuario planta fuera de la whitelist de producción.

**Tech Stack:** HTML/vanilla JS, Supabase (PostgREST + Auth REST), qrcodejs 1.0.0 (cdnjs, solo en index.html), jsPDF (ya presente), Node test runner (`node --test`) con el patrón de harness vm existente.

**Spec:** `docs/superpowers/specs/2026-07-12-tiempos-planta-movil-design.md`

## Global Constraints

- **SQL en Supabase ANTES del frontend:** la migración se corre en el SQL Editor y se verifica ANTES de pushear código que dependa de ella. El push a `main` deploya automáticamente a producción.
- **Convención de migraciones:** BEGIN/COMMIT, idempotentes (IF NOT EXISTS / DROP IF EXISTS), retrocompatibles, query de verificación comentada al pie.
- **empresa_id hardcodeado permitido en scripts/migraciones (single-tenant):** `a0a19507-2a50-4e80-a716-e9459f51d653`.
- **Supabase:** URL `https://dqvlqhaxgvtilhiuatpv.supabase.co`; la anon key está en `index.html` línea ~2273 (const `SUPA_KEY`) — copiarla textual a `planta.html`.
- **Todo dato de usuario interpolado en HTML pasa por `esc()`.**
- **Texto de UI en español argentino (voseo).**
- **CSP:** si se agrega un CDN u origen nuevo, agregarlo en `netlify.toml` o se bloquea en producción. `script-src` ya permite `https://cdnjs.cloudflare.com`.
- **Validación antes de commitear:** `node --check` sobre el script inline extraído + `node --test tests/`.
- **Funciones SQL nuevas:** `SECURITY DEFINER` cuando corresponda, `SET search_path = public`, y `REVOKE`/`GRANT EXECUTE` explícitos (Supabase da EXECUTE a `anon` por default).
- **No usar supabase-js:** el proyecto usa `fetch` crudo contra PostgREST/Auth REST (patrón `authH`/`db` de index.html).

---

### Task 1: Migración 052 — `es_planta` + lockdown RESTRICTIVE + alta usuario

**Files:**
- Create: `migrations/052_modo_planta.sql`

**Interfaces:**
- Produces: columna `usuarios.es_planta boolean`, función `public.es_planta() returns boolean`, policies `planta_lockdown` (todas las tablas con RLS salvo whitelist) y `planta_ro_*` (ordenes_produccion solo lectura). El usuario `planta@vitalmetsa.com` queda creado y marcado. Task 2 depende de que esto esté corrido en prod.

**Contexto para el implementador:**
- El patrón de policies existente es `tenant_isolation FOR ALL TO authenticated USING (empresa_id = (SELECT public.current_empresa_id()))` (permisiva). NO se toca. El lockdown usa policies **RESTRICTIVE**, que se AND-ean con las permisivas: para usuarios normales `NOT es_planta()` es true y nada cambia; para planta, todo lo que no esté en la whitelist queda bloqueado.
- `fn_audit()` (trigger de auditoría) es SECURITY DEFINER → el lockdown sobre `audit_log` NO rompe los INSERTs de planta en `op_time_entries` (verificado en `migrations/023_integridad.sql:494`).
- `current_empresa_id()` es SECURITY DEFINER y lee `usuarios` → sigue funcionando aunque planta no pueda leer `usuarios` vía REST.
- El trigger `usuarios_guard` (022) solo protege `es_admin`; `es_planta` no necesita guard propio porque el lockdown bloquea al usuario planta de TODA la tabla `usuarios` (no puede auto-desmarcarse), y los demás usuarios ya podían editar `usuarios` de su empresa (sin cambio de superficie).

- [ ] **Step 1: Escribir la migración**

Crear `migrations/052_modo_planta.sql` con este contenido exacto:

```sql
-- 052_modo_planta.sql — Usuario planta + lockdown RLS (Modo Planta)
-- planta.html (pantalla móvil de taller, spec 2026-07-12) opera con una
-- cuenta compartida marcada usuarios.es_planta=true. Ese usuario solo
-- puede tocar producción:
--   ordenes_produccion  → solo SELECT (lockdown de escritura aparte)
--   op_operaciones      → SELECT + UPDATE (la UI solo cambia estado;
--                         los quality gates de 041 aplican igual)
--   op_time_entries     → SELECT + INSERT + UPDATE
-- Todo lo demás queda bloqueado con policies RESTRICTIVE, que se
-- AND-ean con las tenant_isolation existentes (que NO se tocan).
-- Usuarios normales (es_planta=false): cero cambio de comportamiento.
-- fn_audit es SECURITY DEFINER → la auditoría sigue funcionando aunque
-- audit_log quede bloqueada para planta.
BEGIN;

-- ─── 1. Flag ─────────────────────────────────────────────────────────
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS es_planta boolean NOT NULL DEFAULT false;

-- ─── 2. Helper (SECURITY DEFINER: lee usuarios sin chocar con RLS) ───
CREATE OR REPLACE FUNCTION public.es_planta()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE((SELECT u.es_planta FROM usuarios u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.es_planta() FROM public;
REVOKE EXECUTE ON FUNCTION public.es_planta() FROM anon;
GRANT EXECUTE ON FUNCTION public.es_planta() TO authenticated;

-- ─── 3. Lockdown: toda tabla con RLS fuera de la whitelist ───────────
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
      AND rowsecurity
      AND tablename NOT IN ('ordenes_produccion','op_operaciones','op_time_entries')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS planta_lockdown ON %I', t);
    EXECUTE format(
      'CREATE POLICY planta_lockdown ON %I AS RESTRICTIVE FOR ALL TO authenticated '
      'USING (NOT public.es_planta()) WITH CHECK (NOT public.es_planta())', t);
  END LOOP;
END $$;

-- ─── 4. ordenes_produccion: planta solo lectura ──────────────────────
DROP POLICY IF EXISTS planta_ro_ins ON ordenes_produccion;
CREATE POLICY planta_ro_ins ON ordenes_produccion AS RESTRICTIVE FOR INSERT
  TO authenticated WITH CHECK (NOT public.es_planta());
DROP POLICY IF EXISTS planta_ro_upd ON ordenes_produccion;
CREATE POLICY planta_ro_upd ON ordenes_produccion AS RESTRICTIVE FOR UPDATE
  TO authenticated USING (NOT public.es_planta());
DROP POLICY IF EXISTS planta_ro_del ON ordenes_produccion;
CREATE POLICY planta_ro_del ON ordenes_produccion AS RESTRICTIVE FOR DELETE
  TO authenticated USING (NOT public.es_planta());

COMMIT;

-- Verificación:
-- 1) Columna y función:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name='usuarios' AND column_name='es_planta';       -- 1 fila
--    SELECT public.es_planta();                                       -- false (SQL editor)
-- 2) Lockdown presente en tablas sensibles y AUSENTE en la whitelist:
--    SELECT tablename FROM pg_policies WHERE policyname='planta_lockdown'
--     AND tablename IN ('ventas','asientos','clientes','usuarios');   -- 4 filas
--    SELECT tablename FROM pg_policies WHERE policyname='planta_lockdown'
--     AND tablename IN ('ordenes_produccion','op_operaciones','op_time_entries'); -- 0 filas
-- 3) Solo lectura en ordenes_produccion:
--    SELECT policyname FROM pg_policies WHERE tablename='ordenes_produccion'
--     AND policyname LIKE 'planta_ro_%';                              -- 3 filas
-- 4) Las policies restrictivas quedaron como tales:
--    SELECT tablename, permissive FROM pg_policies
--     WHERE policyname='planta_lockdown' LIMIT 3;                     -- 'RESTRICTIVE'
```

- [ ] **Step 2: Validar sintaxis localmente (opcional pero barato)**

Si hay un `psql` local no hace falta; alternativa mínima: revisar a ojo que cada `BEGIN` cierre con `COMMIT` y que los `$$` estén balanceados (4 bloques `$$` en total: función + DO).

- [ ] **Step 3: Commit del archivo de migración**

```bash
cd ~/vitalmet-erp
git add migrations/052_modo_planta.sql
git commit -m "feat(planta): migración 052 — es_planta + lockdown RLS restrictivo"
```

(Commitear el .sql no deploya nada peligroso: Netlify solo publica archivos, la migración no corre sola.)

- [ ] **Step 4: DETENERSE — pedirle a Giuliano que corra la migración**

Mensaje para el usuario: pegar `migrations/052_modo_planta.sql` completo en el SQL Editor de Supabase, correrlo, y después correr las 4 queries de verificación comentadas al pie. Esperar el "listo" antes de seguir con el Step 5.

- [ ] **Step 5: DETENERSE — alta del usuario planta (manual + SQL)**

Pedirle a Giuliano:
1. En el dashboard de Supabase → Authentication → Users → **Add user**: email `planta@vitalmetsa.com`, contraseña fuerte (guardarla — se carga una sola vez por celular), con **Auto Confirm User** activado.
2. En el SQL Editor, correr:

```sql
INSERT INTO usuarios (id, empresa_id, nombre, email, rol, es_admin, es_planta)
SELECT id, 'a0a19507-2a50-4e80-a716-e9459f51d653', 'Planta (móvil)',
       'planta@vitalmetsa.com', 'usuario', false, true
FROM auth.users WHERE email = 'planta@vitalmetsa.com'
ON CONFLICT (id) DO UPDATE SET es_planta = true;

-- Verificación:
SELECT nombre, es_planta FROM usuarios WHERE email='planta@vitalmetsa.com';
-- → 'Planta (móvil)' | true
```

- [ ] **Step 6: Smoke test del lockdown con el token de planta**

Con el password del paso anterior, desde una terminal:

```bash
SUPA=https://dqvlqhaxgvtilhiuatpv.supabase.co
KEY=<anon key de index.html línea ~2273>
TOKEN=$(curl -s "$SUPA/auth/v1/token?grant_type=password" \
  -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"planta@vitalmetsa.com","password":"<LA_CLAVE>"}' |
  python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# Debe devolver [] (bloqueado):
curl -s "$SUPA/rest/v1/ventas?select=id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN"
curl -s "$SUPA/rest/v1/asientos?select=id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN"
curl -s "$SUPA/rest/v1/usuarios?select=id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN"

# Debe devolver filas (whitelist):
curl -s "$SUPA/rest/v1/ordenes_produccion?select=id,nro&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN"
```

Expected: los tres primeros devuelven `[]`; el último devuelve una OP real.

---

### Task 2: `planta.html` + headers Netlify

**Files:**
- Create: `planta.html`
- Create: `tests/planta.test.js`
- Modify: `netlify.toml` (headers + redirect al final del archivo)

**Interfaces:**
- Consumes: migración 052 corrida (usuario planta funcional). Anon key `SUPA_KEY` copiada de `index.html:2273`.
- Produces: página en `/planta.html` con query param `?op=<orden_id>` (la URL que codifica el QR de Task 3). Helpers puros testeados: `fmtTimerSec(seg)`, `openOf(pasoId, tipo)`, `holdPrevioSinFirmar(paso)`, `minutosCerrados(pasoId)`.

**Contexto para el implementador:**
- Semántica de timers copiada del ERP (`startTiempoOp` / `confirmPauseTiempo` / `completeTiempoOp`, index.html ~8634-8716): iniciar = PATCH cerrar pausa abierta + POST entry `productivo` + estado `en_curso` si estaba `pendiente`; pausar = PATCH cerrar productivo + POST entry `pausa` con motivo; finalizar = PATCH cerrar todas las abiertas + estado `completada`.
- Los quality gates ya viven en la DB (trigger `fn_op_quality_gate`, migración 041): si un PATCH de estado viola un hold point, PostgREST devuelve error → mostrarlo con `toast(...,'err')` y recargar. El bloqueo visual client-side (`holdPrevioSinFirmar`) es solo UX.
- Los 8 motivos de pausa son EXACTAMENTE los del ERP (index.html modal `modal-pausa-motivo`): `Setup / cambio herramienta`, `Almuerzo / descanso`, `Fin de turno`, `Falta de material`, `Rotura de máquina`, `Reproceso / control`, `Esperando operario`, `Otro`. No inventar otros: el análisis de paradas de Eficiencia agrupa por estos strings.
- Estados de OP usan guión: `en-proceso`; estados de operación usan guión bajo: `pendiente`/`en_curso`/`completada`. Ojo con eso.

- [ ] **Step 1: Escribir el test de helpers (falla primero)**

Crear `tests/planta.test.js`:

```js
// Tests de los helpers puros de planta.html (Modo Planta).
// Mismo patrón vm que _harness.js pero extrayendo el script de planta.html.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function loadPlanta() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'planta.html'), 'utf8');
  const m = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!m) throw new Error('No se encontró <script> inline en planta.html');
  const sandbox = {
    document: { getElementById: () => null, addEventListener() {}, querySelectorAll: () => [] },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    location: { search: '', href: 'http://test/' },
    fetch: () => Promise.reject(new Error('sin red en tests')),
    confirm: () => false,
    setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
    URLSearchParams, console, Date,
  };
  sandbox.window = sandbox;
  const ctx = vm.createContext(sandbox);
  vm.runInContext(m[1], ctx, { filename: 'planta.html#script' });
  return { run: (code) => vm.runInContext(code, ctx) };
}

const p = loadPlanta();

test('fmtTimerSec formatea HH:MM:SS', () => {
  assert.strictEqual(p.run('fmtTimerSec(0)'), '00:00:00');
  assert.strictEqual(p.run('fmtTimerSec(59)'), '00:00:59');
  assert.strictEqual(p.run('fmtTimerSec(3661)'), '01:01:01');
});

test('openOf encuentra solo la entry abierta del tipo pedido', () => {
  const r = p.run(`(()=>{
    entries=[
      {id:'e1',operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T11:00:00Z'},
      {id:'e2',operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T12:00:00Z',ended_at:null},
      {id:'e3',operacion_id:'b',tipo:'pausa',started_at:'2026-07-12T12:00:00Z',ended_at:null},
    ];
    return {
      prodA:(openOf('a','productivo')||{}).id||null,
      pausaA:openOf('a','pausa'),
      pausaB:(openOf('b','pausa')||{}).id||null,
    };
  })()`);
  assert.strictEqual(r.prodA, 'e2');
  assert.strictEqual(r.pausaA, null);
  assert.strictEqual(r.pausaB, 'e3');
});

test('holdPrevioSinFirmar bloquea solo pasos posteriores a un hold sin firma', () => {
  const r = p.run(`(()=>{
    pasos=[
      {id:'p1',secuencia:1,tipo_punto:'hold',signoff_at:null},
      {id:'p2',secuencia:2,tipo_punto:'normal',signoff_at:null},
      {id:'p3',secuencia:3,tipo_punto:'witness',signoff_at:null},
    ];
    return {
      p1:holdPrevioSinFirmar(pasos[0]),
      p2:holdPrevioSinFirmar(pasos[1]),
      p3Firmado:(()=>{pasos[0].signoff_at='2026-07-12T10:00:00Z';return holdPrevioSinFirmar(pasos[2]);})(),
    };
  })()`);
  assert.strictEqual(r.p1, false);   // el propio hold no se auto-bloquea
  assert.strictEqual(r.p2, true);    // posterior a hold sin firmar
  assert.strictEqual(r.p3Firmado, false); // hold ya firmado → libre
});

test('minutosCerrados suma solo entries productivas cerradas del paso', () => {
  const r = p.run(`(()=>{
    entries=[
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T10:30:00Z'},
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T11:00:00Z',ended_at:'2026-07-12T11:15:00Z'},
      {operacion_id:'a',tipo:'pausa',started_at:'2026-07-12T10:30:00Z',ended_at:'2026-07-12T11:00:00Z'},
      {operacion_id:'a',tipo:'productivo',started_at:'2026-07-12T12:00:00Z',ended_at:null},
      {operacion_id:'b',tipo:'productivo',started_at:'2026-07-12T10:00:00Z',ended_at:'2026-07-12T10:10:00Z'},
    ];
    return minutosCerrados('a');
  })()`);
  assert.strictEqual(r, 45);
});
```

- [ ] **Step 2: Correr el test — debe fallar**

```bash
cd ~/vitalmet-erp && node --test tests/planta.test.js
```

Expected: FAIL con `ENOENT ... planta.html` (el archivo no existe todavía).

- [ ] **Step 3: Escribir `planta.html` completo**

Crear `planta.html` en la raíz del repo. **Antes de guardar, reemplazar `<SUPA_KEY_DE_INDEX>` por la anon key textual de `index.html` línea ~2273.** Contenido completo:

```html
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0d1117">
<title>VitalStock · Planta</title>
<style>
:root{--bg:#0d1117;--bg2:#161b22;--bg3:#1c2330;--border:#30363d;--text:#e6edf3;--text2:#9da7b3;--text3:#6e7681;--accent:#4a9eff;--green:#3fb950;--amber:#d29922;--coral:#f85149;--mono:ui-monospace,'SF Mono',Menlo,monospace}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{background:var(--bg);color:var(--text);font-family:-apple-system,system-ui,'Segoe UI',Roboto,sans-serif;min-height:100vh}
.wrap{max-width:560px;margin:0 auto;padding:14px 14px 60px}
header{display:flex;align-items:center;justify-content:space-between;padding:4px 2px 14px}
header .brand{font-weight:700;font-size:16px;letter-spacing:.5px}
header .brand span{color:var(--accent)}
header button{background:none;border:1px solid var(--border);color:var(--text3);border-radius:6px;padding:6px 10px;font-size:12px}
.card{background:var(--bg2);border:1px solid var(--border);border-radius:10px;padding:14px;margin-bottom:10px}
.op-head{margin-bottom:14px}
.op-head .nro{font-family:var(--mono);color:var(--accent);font-size:13px}
.op-head .pieza{font-size:19px;font-weight:700;margin:2px 0 4px}
.op-head .meta{color:var(--text2);font-size:13px}
.paso{display:flex;flex-direction:column;gap:10px}
.paso-top{display:flex;align-items:baseline;justify-content:space-between;gap:8px}
.paso-nombre{font-size:16px;font-weight:600}
.paso-maquina{color:var(--text3);font-size:12px}
.paso-timer{font-family:var(--mono);font-size:20px;font-weight:700}
.paso-timer.live{color:var(--green)}
.badge{display:inline-block;font-size:10px;font-weight:700;letter-spacing:.5px;padding:2px 7px;border-radius:10px;vertical-align:2px;margin-left:6px}
.badge.hold{background:rgba(210,153,34,.15);color:var(--amber);border:1px solid var(--amber)}
.badge.witness{background:rgba(74,158,255,.12);color:var(--accent);border:1px solid var(--accent)}
.badge.pausa{background:rgba(248,81,73,.12);color:var(--coral);border:1px solid var(--coral)}
.badge.ok{background:rgba(63,185,80,.12);color:var(--green);border:1px solid var(--green)}
.acciones{display:flex;gap:8px}
.btn{flex:1;min-height:54px;border-radius:9px;border:1px solid var(--border);background:var(--bg3);color:var(--text);font-size:15px;font-weight:700;letter-spacing:.3px}
.btn:active{transform:scale(.98)}
.btn.play{border-color:var(--green);color:var(--green)}
.btn.pause{border-color:var(--amber);color:var(--amber)}
.btn.stop{border-color:var(--coral);color:var(--coral)}
.btn[disabled]{opacity:.35}
.bloqueado{color:var(--amber);font-size:12px}
.done{color:var(--text3)}
.done .paso-nombre{text-decoration:line-through;color:var(--text3);font-weight:400}
input{width:100%;background:var(--bg2);border:1px solid var(--border);color:var(--text);border-radius:8px;padding:14px;font-size:16px;margin-bottom:10px}
.btn-primary{width:100%;min-height:52px;background:var(--accent);border:none;color:#fff;font-size:16px;font-weight:700;border-radius:9px}
.err{color:var(--coral);font-size:13px;margin:6px 0;display:none}
.err.visible{display:block}
.lista-item{display:block;width:100%;text-align:left}
.lista-item .nro{font-family:var(--mono);color:var(--accent);font-size:12px}
.lista-item .pieza{font-size:16px;font-weight:600;margin-top:2px}
.lista-item .meta{color:var(--text3);font-size:12px;margin-top:2px}
.msg{text-align:center;padding:40px 10px;color:var(--text2)}
.msg a{color:var(--accent)}
#sheet-backdrop{display:none;position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:9}
#sheet{display:none;position:fixed;left:0;right:0;bottom:0;background:var(--bg2);border-top:1px solid var(--border);border-radius:16px 16px 0 0;padding:16px 14px 30px;z-index:10}
#sheet h3{font-size:14px;color:var(--text2);margin-bottom:12px;text-align:center}
#sheet .motivos{display:grid;grid-template-columns:1fr 1fr;gap:8px}
#sheet button{min-height:56px;border-radius:9px;border:1px solid var(--border);background:var(--bg3);color:var(--text);font-size:13px;font-weight:600;text-align:left;padding:8px 10px}
#sheet button small{display:block;font-size:9px;letter-spacing:1px;text-transform:uppercase;color:var(--text3);margin-bottom:2px}
#sheet button.plan{border-left:3px solid var(--green)}
#sheet button.noplan{border-left:3px solid var(--coral)}
#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%) translateY(80px);background:var(--bg3);border:1px solid var(--border);color:var(--text);padding:12px 18px;border-radius:9px;font-size:14px;transition:transform .2s;z-index:20;max-width:90vw}
#toast.show{transform:translateX(-50%) translateY(0)}
#toast.err{border-color:var(--coral);color:var(--coral)}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="brand">⏱ VITAL<span>STOCK</span> · Planta</div>
    <button id="btn-salir" onclick="logout()" style="display:none">Salir</button>
  </header>

  <div id="view-login" style="display:none">
    <div class="card">
      <input type="email" id="login-email" placeholder="Email" autocomplete="username" value="planta@vitalmetsa.com">
      <input type="password" id="login-pass" placeholder="Contraseña" autocomplete="current-password">
      <div class="err" id="login-err"></div>
      <button class="btn-primary" id="btn-login" onclick="doLogin()">Entrar</button>
    </div>
  </div>

  <div id="view-msg" style="display:none" class="msg"></div>
  <div id="view-lista" style="display:none"></div>
  <div id="view-op" style="display:none">
    <div class="op-head" id="op-head"></div>
    <div id="op-pasos"></div>
  </div>
</div>

<div id="sheet-backdrop" onclick="closeSheet()"></div>
<div id="sheet">
  <h3>¿Por qué pausás?</h3>
  <div class="motivos">
    <button class="plan" onclick="pausar('Setup / cambio herramienta')"><small>Planificada</small>Setup / cambio</button>
    <button class="plan" onclick="pausar('Almuerzo / descanso')"><small>Planificada</small>Almuerzo / descanso</button>
    <button class="plan" onclick="pausar('Fin de turno')"><small>Planificada</small>Fin de turno</button>
    <button class="noplan" onclick="pausar('Falta de material')"><small>No planif.</small>Falta material</button>
    <button class="noplan" onclick="pausar('Rotura de máquina')"><small>No planif.</small>Rotura máquina</button>
    <button class="noplan" onclick="pausar('Reproceso / control')"><small>No planif.</small>Reproceso / control</button>
    <button class="noplan" onclick="pausar('Esperando operario')"><small>No planif.</small>Esperando operario</button>
    <button onclick="pausar('Otro')"><small>General</small>Otro</button>
  </div>
</div>
<div id="toast"></div>

<script>
'use strict';
// ─── Config (copiada de index.html — misma Supabase) ────────────────
const SUPA_URL='https://dqvlqhaxgvtilhiuatpv.supabase.co';
const SUPA_KEY='<SUPA_KEY_DE_INDEX>';
const EMPRESA_ID='a0a19507-2a50-4e80-a716-e9459f51d653';
const LS_KEY='planta_session';

let session=null;
let op=null,pasos=[],entries=[];
let tickInt=null;

// ─── Helpers puros (testeados en tests/planta.test.js) ──────────────
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function fmtTimerSec(s){const h=Math.floor(s/3600),m=Math.floor((s%3600)/60),x=s%60;return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(x).padStart(2,'0')}`;}
function secSince(iso){return Math.max(0,Math.round((Date.now()-new Date(iso).getTime())/1000));}
function openOf(pasoId,tipo){return entries.find(e=>e.operacion_id===pasoId&&e.tipo===tipo&&!e.ended_at)||null;}
function holdPrevioSinFirmar(paso){return pasos.some(p=>p.secuencia<paso.secuencia&&p.tipo_punto==='hold'&&!p.signoff_at);}
function minutosCerrados(pasoId){return entries.filter(e=>e.operacion_id===pasoId&&e.tipo==='productivo'&&e.ended_at).reduce((a,e)=>a+(new Date(e.ended_at)-new Date(e.started_at))/60000,0);}

// ─── Supabase REST (patrón db() de index.html, reducido) ────────────
function authH(){return{'Content-Type':'application/json','apikey':SUPA_KEY,'Authorization':'Bearer '+(session?.access_token||SUPA_KEY),'Prefer':'return=representation'};}
async function db(method,table,params='',body){
  let r=await fetch(`${SUPA_URL}/rest/v1/${table}${params}`,{method,headers:authH(),body:body?JSON.stringify(body):undefined});
  if(r.status===401&&session?.refresh_token){
    if(await refreshTok())r=await fetch(`${SUPA_URL}/rest/v1/${table}${params}`,{method,headers:authH(),body:body?JSON.stringify(body):undefined});
    else{logout();throw new Error('Sesión vencida — entrá de nuevo');}
  }
  if(!r.ok){let e={};try{e=await r.json();}catch(_){/* sin body */}throw new Error(e.message||r.statusText);}
  return r.status===204?null:r.json();
}
const GET=(t,p)=>db('GET',t,p);
const POST=(t,b)=>db('POST',t,'',b);
const PATCH=(t,p,b)=>db('PATCH',t,p,b);

// ─── Auth ────────────────────────────────────────────────────────────
function saveSession(d){session={access_token:d.access_token,refresh_token:d.refresh_token,user:d.user};localStorage.setItem(LS_KEY,JSON.stringify(session));}
async function refreshTok(){
  try{
    const r=await fetch(`${SUPA_URL}/auth/v1/token?grant_type=refresh_token`,{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPA_KEY},body:JSON.stringify({refresh_token:session.refresh_token})});
    if(!r.ok)return false;
    const d=await r.json();
    if(!d.access_token)return false;
    saveSession(d);return true;
  }catch(_){return false;}
}
async function doLogin(){
  const email=document.getElementById('login-email').value.trim();
  const pass=document.getElementById('login-pass').value;
  const errEl=document.getElementById('login-err');
  errEl.classList.remove('visible');
  if(!email||!pass){errEl.textContent='Completá email y contraseña';errEl.classList.add('visible');return;}
  const btn=document.getElementById('btn-login');btn.disabled=true;
  try{
    const r=await fetch(`${SUPA_URL}/auth/v1/token?grant_type=password`,{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPA_KEY},body:JSON.stringify({email,password:pass})});
    const d=await r.json();
    if(!r.ok||!d.access_token)throw new Error(d.error_description||d.msg||'Email o contraseña incorrectos');
    saveSession(d);
    document.getElementById('btn-salir').style.display='';
    route();
  }catch(e){errEl.textContent=e.message;errEl.classList.add('visible');}
  finally{btn.disabled=false;}
}
function logout(){localStorage.removeItem(LS_KEY);session=null;stopTick();document.getElementById('btn-salir').style.display='none';show('view-login');}

// ─── Vistas ──────────────────────────────────────────────────────────
function show(id){['view-login','view-msg','view-lista','view-op'].forEach(v=>{document.getElementById(v).style.display=v===id?'':'none';});}
function showMsg(html){document.getElementById('view-msg').innerHTML=html;show('view-msg');stopTick();}
function toast(msg,err){const t=document.getElementById('toast');t.textContent=msg;t.className='show'+(err?' err':'');clearTimeout(toast._t);toast._t=setTimeout(()=>{t.className='';},3000);}

async function route(){
  const opId=new URLSearchParams(location.search).get('op');
  if(opId)await loadOP(opId);else await loadLista();
}

async function loadLista(){
  try{
    const list=await GET('ordenes_produccion','?estado=eq.en-proceso&order=created_at.desc&select=id,nro,pieza,cantidad,fecha');
    document.getElementById('view-lista').innerHTML=list.length
      ?list.map(o=>`<button class="card lista-item" onclick="location.search='?op=${o.id}'">
          <div class="nro">${esc(o.nro)}</div>
          <div class="pieza">${esc(o.pieza)}</div>
          <div class="meta">x${esc(o.cantidad)} · ${esc(o.fecha||'')}</div>
        </button>`).join('')
      :'<div class="msg">No hay órdenes en proceso.</div>';
    show('view-lista');stopTick();
  }catch(e){showMsg('Error al cargar: '+esc(e.message)+'<br><br><a href="planta.html">Reintentar</a>');}
}

async function loadOP(opId){
  try{
    const rows=await GET('ordenes_produccion',`?id=eq.${opId}&select=id,nro,pieza,cantidad,estado,fecha`);
    op=rows[0]||null;
    if(!op){showMsg('OP no encontrada.<br><br><a href="planta.html">Ver órdenes en proceso</a>');return;}
    pasos=await GET('op_operaciones',`?orden_id=eq.${opId}&order=secuencia.asc`);
    entries=pasos.length?await GET('op_time_entries',`?operacion_id=in.(${pasos.map(p=>p.id).join(',')})&order=started_at.asc`):[];
    renderOP();show('view-op');startTick();
  }catch(e){showMsg('Error al cargar: '+esc(e.message)+'<br><br><a href="planta.html">Ver órdenes en proceso</a>');}
}

function renderOP(){
  document.getElementById('op-head').innerHTML=`
    <div class="nro">${esc(op.nro)}${op.estado!=='en-proceso'?` <span class="badge ok">${esc(op.estado)}</span>`:''}</div>
    <div class="pieza">${esc(op.pieza)}</div>
    <div class="meta">x${esc(op.cantidad)} unidades${op.fecha?' · '+esc(op.fecha):''}</div>`;
  document.getElementById('op-pasos').innerHTML=pasos.length?pasos.map(p=>{
    const prod=openOf(p.id,'productivo'),pausa=openOf(p.id,'pausa');
    const qc=p.tipo_punto==='hold'?`<span class="badge hold">HOLD${p.signoff_at?' ✓':''}</span>`
            :p.tipo_punto==='witness'?`<span class="badge witness">WITNESS${p.signoff_at?' ✓':''}</span>`:'';
    const bloqueado=holdPrevioSinFirmar(p);
    const done=p.estado==='completada';
    const timer=`<span class="paso-timer${prod?' live':''}" id="t-${p.id}">${fmtTimerSec(Math.round(minutosCerrados(p.id)*60)+(prod?secSince(prod.started_at):0))}</span>`;
    let acciones='';
    if(done)acciones='';
    else if(bloqueado)acciones=`<div class="bloqueado">🔒 Bloqueado: hay un punto HOLD anterior sin liberar (se firma desde el ERP).</div>`;
    else if(prod)acciones=`<div class="acciones"><button class="btn pause" onclick="openSheet('${p.id}')">⏸ PAUSAR</button><button class="btn stop" onclick="finalizar('${p.id}')">■ FINALIZAR</button></div>`;
    else acciones=`<div class="acciones"><button class="btn play" onclick="iniciar('${p.id}')">▶ INICIAR</button>${p.estado==='en_curso'?`<button class="btn stop" onclick="finalizar('${p.id}')">■ FINALIZAR</button>`:''}</div>`;
    return `<div class="card paso${done?' done':''}">
      <div class="paso-top">
        <div><span class="paso-nombre">${done?'✓ ':''}${esc(p.nombre)}</span>${qc}${pausa?`<span class="badge pausa">⏸ ${esc(pausa.motivo||'pausa')}</span>`:''}
          ${p.maquina?`<div class="paso-maquina">${esc(p.maquina)}</div>`:''}</div>
        ${timer}
      </div>
      ${acciones}
    </div>`;
  }).join(''):'<div class="msg">Esta OP no tiene operaciones cargadas.</div>';
}

// ─── Tick de cronómetros (solo texto, sin re-render) ────────────────
function startTick(){stopTick();tickInt=setInterval(()=>{
  pasos.forEach(p=>{
    const prod=openOf(p.id,'productivo');if(!prod)return;
    const el=document.getElementById('t-'+p.id);
    if(el)el.textContent=fmtTimerSec(Math.round(minutosCerrados(p.id)*60)+secSince(prod.started_at));
  });
},1000);}
function stopTick(){if(tickInt){clearInterval(tickInt);tickInt=null;}}

// ─── Acciones (misma semántica que startTiempoOp/confirmPauseTiempo/
//     completeTiempoOp del ERP; los quality gates los aplica la DB) ──
async function iniciar(pasoId){
  const paso=pasos.find(p=>p.id===pasoId);if(!paso)return;
  if(paso.estado==='completada'){toast('Ese paso ya está completado',1);return;}
  if(openOf(pasoId,'productivo')){toast('Ese paso ya tiene un timer corriendo',1);return;}
  try{
    const now=new Date().toISOString();
    await PATCH('op_time_entries',`?operacion_id=eq.${pasoId}&tipo=eq.pausa&ended_at=is.null`,{ended_at:now});
    await POST('op_time_entries',[{empresa_id:EMPRESA_ID,operacion_id:pasoId,operario_id:session.user.id,tipo:'productivo',started_at:now}]);
    if(paso.estado==='pendiente')await PATCH('op_operaciones',`?id=eq.${pasoId}`,{estado:'en_curso'});
    toast('▶ Timer iniciado · '+paso.nombre);
  }catch(e){toast('Error: '+e.message,1);}
  loadOP(op.id);
}

let pausaPasoId=null;
function openSheet(pasoId){
  if(!openOf(pasoId,'productivo')){toast('Ese paso no tiene timer corriendo',1);return;}
  pausaPasoId=pasoId;
  document.getElementById('sheet-backdrop').style.display='block';
  document.getElementById('sheet').style.display='block';
}
function closeSheet(){pausaPasoId=null;document.getElementById('sheet-backdrop').style.display='none';document.getElementById('sheet').style.display='none';}
async function pausar(motivo){
  const pasoId=pausaPasoId;closeSheet();
  if(!pasoId)return;
  try{
    const now=new Date().toISOString();
    await PATCH('op_time_entries',`?operacion_id=eq.${pasoId}&tipo=eq.productivo&ended_at=is.null`,{ended_at:now});
    await POST('op_time_entries',[{empresa_id:EMPRESA_ID,operacion_id:pasoId,operario_id:session.user.id,tipo:'pausa',motivo,started_at:now}]);
    toast('⏸ Pausado · '+motivo);
  }catch(e){toast('Error: '+e.message,1);}
  loadOP(op.id);
}

async function finalizar(pasoId){
  const paso=pasos.find(p=>p.id===pasoId);if(!paso)return;
  if(!confirm(`¿Marcar "${paso.nombre}" como completado?`))return;
  try{
    const now=new Date().toISOString();
    await PATCH('op_time_entries',`?operacion_id=eq.${pasoId}&ended_at=is.null`,{ended_at:now});
    await PATCH('op_operaciones',`?id=eq.${pasoId}`,{estado:'completada'});
    toast('✓ '+paso.nombre+' completado');
  }catch(e){toast('Error: '+e.message,1);}
  loadOP(op.id);
}

// ─── Init ────────────────────────────────────────────────────────────
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&session&&op&&document.getElementById('view-op').style.display!=='none')loadOP(op.id);});
(function init(){
  try{session=JSON.parse(localStorage.getItem(LS_KEY))||null;}catch(_){session=null;}
  if(session&&session.access_token){document.getElementById('btn-salir').style.display='';route();}
  else show('view-login');
})();
</script>
</body>
</html>
```

- [ ] **Step 4: Correr tests + chequeo de sintaxis**

```bash
cd ~/vitalmet-erp
node --test tests/planta.test.js
node -e "const fs=require('fs');const m=fs.readFileSync('planta.html','utf8').match(/<script>([\s\S]*?)<\/script>/);fs.writeFileSync('/tmp/planta-check.js',m[1])" && node --check /tmp/planta-check.js && echo "sintaxis OK"
```

Expected: 4 tests PASS, `sintaxis OK`.

- [ ] **Step 5: Headers y redirect en `netlify.toml`**

Agregar AL FINAL de `netlify.toml`:

```toml
# planta.html (Modo Planta): mismo endurecimiento que la app.
# Sin CDNs: script/style inline + fetch solo a Supabase.
[[headers]]
  for = "/planta.html"
  [headers.values]
    Content-Security-Policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src https://dqvlqhaxgvtilhiuatpv.supabase.co; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"

[[redirects]]
  from = "/planta"
  to = "/planta.html"
  status = 200
```

- [ ] **Step 6: Correr la suite completa y commitear**

```bash
cd ~/vitalmet-erp
node --test tests/
git add planta.html tests/planta.test.js netlify.toml
git commit -m "feat(planta): planta.html — timers de producción desde el móvil (Modo Planta)"
```

Expected: toda la suite PASS (los tests existentes no se tocan). **NO pushear todavía** — el push se hace en Task 4 después de confirmar que la migración corrió.

---

### Task 3: Botón "QR planta" en el ERP (`index.html`)

**Files:**
- Modify: `index.html` — (a) `<head>` zona libs CDN (~líneas 10-14), (b) modal `modal-tiempos` header (línea ~1878), (c) HTML de modales (agregar `modal-qr-planta` junto a los otros modales, p.ej. antes de `modal-pausa-motivo` línea ~1920), (d) script: nuevas funciones cerca de `startTiempoOp` (~línea 8634)
- Create: `tests/planta-qr.test.js`

**Interfaces:**
- Consumes: `currentTiempoOpId` (global del ERP, seteado por `openTiempos`), array global `ops`, helpers `esc()`, `openModal`/`closeModal`, jsPDF (`window.jspdf`), la página `/planta.html?op=` de Task 2.
- Produces: `plantaURL(opId)` (pura, testeada), `openQRPlanta()`, `descargarQRPDF()`.

- [ ] **Step 1: Test del helper puro (falla primero)**

Crear `tests/planta-qr.test.js`:

```js
// Test de plantaURL (botón "QR planta" del modal Tiempos).
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();

test('plantaURL arma la URL de producción con el id de la OP', () => {
  assert.strictEqual(
    erp.run(`plantaURL('abc-123')`),
    'https://erp.vitalmetsa.com/planta.html?op=abc-123'
  );
});
```

- [ ] **Step 2: Correr el test — debe fallar**

```bash
cd ~/vitalmet-erp && node --test tests/planta-qr.test.js
```

Expected: FAIL con `plantaURL is not defined`.

- [ ] **Step 3: Lib QR en el `<head>`**

En `index.html`, junto a los otros `<script src="https://cdnjs.cloudflare.com/...">` del head (~líneas 10-14), agregar:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js" defer></script>
```

(El CSP ya permite `script-src https://cdnjs.cloudflare.com` — no hay que tocar `netlify.toml`.)

- [ ] **Step 4: Modal `modal-qr-planta`**

Agregar junto a los otros modales (p.ej. inmediatamente antes de `<div class="modal-overlay" id="modal-pausa-motivo">`, línea ~1920):

```html
<div class="modal-overlay" id="modal-qr-planta">
  <div class="modal" style="width:340px">
    <div class="modal-header"><div class="modal-title">QR planta <span id="qr-planta-nro" style="color:var(--accent);font-weight:400;margin-left:8px"></span></div><button class="modal-close" onclick="closeModal('modal-qr-planta')">×</button></div>
    <div class="modal-body" style="text-align:center">
      <div id="qr-planta-canvas" style="display:inline-block;background:#fff;padding:14px;border-radius:8px"></div>
      <p style="margin:12px 0 4px;font-size:12px;color:var(--text3)">Escaneá con la cámara del celular para abrir los timers de esta OP.</p>
      <button class="btn btn-primary" id="btn-qr-pdf" onclick="descargarQRPDF()" style="margin-top:10px;width:100%">Descargar PDF para imprimir</button>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Funciones en el script**

Agregar inmediatamente antes de `async function startTiempoOp(pasoId){` (~línea 8634):

```js
// ─── QR planta: link móvil a los timers de la OP (Modo Planta) ─────
const PLANTA_BASE='https://erp.vitalmetsa.com/planta.html';
function plantaURL(opId){return PLANTA_BASE+'?op='+opId;}

function openQRPlanta(){
  if(!currentTiempoOpId)return;
  const o=ops.find(x=>x.id===currentTiempoOpId);
  document.getElementById('qr-planta-nro').textContent=o?o.nro:'';
  const cont=document.getElementById('qr-planta-canvas');
  cont.innerHTML='';
  if(typeof QRCode==='undefined'){notify('La librería de QR no cargó — recargá la página','err');return;}
  new QRCode(cont,{text:plantaURL(currentTiempoOpId),width:220,height:220,correctLevel:QRCode.CorrectLevel.M});
  openModal('modal-qr-planta');
}

function descargarQRPDF(){
  const o=ops.find(x=>x.id===currentTiempoOpId);if(!o)return;
  const img=document.querySelector('#qr-planta-canvas img,#qr-planta-canvas canvas');
  if(!img){notify('Generá el QR primero','err');return;}
  const dataURL=img.tagName==='CANVAS'?img.toDataURL('image/png'):img.src;
  const {jsPDF}=window.jspdf;
  const doc=new jsPDF({unit:'mm',format:'a4'});
  doc.setFontSize(18);doc.setFont(undefined,'bold');
  doc.text('Timers de producción — escaneá con el celular',105,30,{align:'center'});
  doc.setFontSize(14);doc.setFont(undefined,'normal');
  doc.text(`${o.nro} · ${o.pieza}`,105,42,{align:'center'});
  doc.addImage(dataURL,'PNG',65,55,80,80);
  doc.setFontSize(10);doc.setTextColor(120);
  doc.text(plantaURL(currentTiempoOpId),105,145,{align:'center'});
  doc.save(`QR-planta-${o.nro}.pdf`);
}
```

- [ ] **Step 6: Botón en el header del modal Tiempos**

En `index.html` línea ~1878, el header del modal es:

```html
<div class="modal-header">
  <div class="modal-title">...Captura de tiempos <span id="tiempos-op-nro" ...></span></div>
  <button class="modal-close" onclick="closeTiempos()">×</button>
</div>
```

Insertar el botón entre el título y la ✕:

```html
<button class="btn btn-ghost btn-sm" onclick="openQRPlanta()" style="margin-left:auto;margin-right:10px;border-color:var(--accent);color:var(--accent)">📱 QR planta</button>
```

(Queda: `modal-title`, luego el botón nuevo, luego `modal-close`. Si `.modal-header` no es flex con espacio, ajustar con `style` inline — verificar visualmente.)

- [ ] **Step 7: Correr tests + sintaxis**

```bash
cd ~/vitalmet-erp
node --test tests/planta-qr.test.js
node -e "const fs=require('fs');const html=fs.readFileSync('index.html','utf8');const s=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erp-check.js',s)" && node --check /tmp/erp-check.js && echo "sintaxis OK"
node --test tests/
```

Expected: test nuevo PASS, `sintaxis OK`, suite completa PASS.

- [ ] **Step 8: Commit**

```bash
cd ~/vitalmet-erp
git add index.html tests/planta-qr.test.js
git commit -m "feat(planta): botón QR planta en el modal Tiempos — imprime el acceso móvil por OP"
```

---

### Task 4: Verificación final, push y prueba E2E

**Files:** ninguno nuevo.

- [ ] **Step 1: Gate — confirmar que la migración 052 corrió**

NO pushear si Giuliano no confirmó los Steps 4-6 de Task 1 (migración corrida + usuario planta creado + smoke test del lockdown OK). El frontend deployado sin la migración deja a planta sin lockdown.

- [ ] **Step 2: Suite completa + push**

```bash
cd ~/vitalmet-erp
node --test tests/
git push origin main
```

Expected: suite PASS; Netlify deploya automáticamente (1-2 min).

- [ ] **Step 3: Verificación en producción (checklist para Giuliano + browser)**

1. `https://erp.vitalmetsa.com/planta` carga y muestra el login (redirect OK, CSP sin errores en consola).
2. Login con `planta@vitalmetsa.com` → lista de OPs en proceso.
3. En el ERP de escritorio: abrir una OP → Tiempos → **📱 QR planta** → se ve el QR → **Descargar PDF** baja el archivo.
4. Escanear el QR con un celular real → abre la OP correcta → ▶ INICIAR arranca el timer → en el escritorio, el panel "⏱ Timers activos" de Producción lo muestra en segundos.
5. ⏸ PAUSAR con motivo → el badge de pausa aparece en ambos lados. ■ FINALIZAR → el paso queda ✓ completado en el ERP.
6. Con la sesión de planta, intentar entrar al ERP de escritorio (`erp.vitalmetsa.com`): debe fallar la carga de datos (lockdown — comportamiento esperado y deseado).

- [ ] **Step 4: Actualizar CLAUDE.md (módulos + estructura)**

En `CLAUDE.md` sección Módulos, agregar al final de la lista: `Modo Planta (planta.html: timers móviles por QR, usuario es_planta con lockdown RLS)`. Commitear:

```bash
cd ~/vitalmet-erp
git add CLAUDE.md
git commit -m "docs: Modo Planta en CLAUDE.md"
git push origin main
```

---

## Self-review (hecho al escribir el plan)

- **Cobertura del spec:** planta.html (Task 2), QR + PDF (Task 3), migración lockdown + usuario (Task 1), CSP/redirect (Task 2 Step 5), tests (Tasks 2-3), E2E y seguridad manual (Task 4). Fuera de alcance respetado: sin offline, sin PWA, sin identidad por operario, sin firma de hold points en móvil.
- **Consistencia de tipos:** `openOf(pasoId,tipo)`, `holdPrevioSinFirmar(paso)`, `minutosCerrados(pasoId)`, `fmtTimerSec(seg)` usados igual en código y tests. `plantaURL(opId)` igual en Task 3 código y test.
- **Riesgo conocido aceptado (documentado en spec):** RLS no restringe columnas — planta puede técnicamente actualizar otras columnas de `op_operaciones`/`op_time_entries`; los quality gates del trigger 041 acotan lo importante.
- **Orden iniciar (entry antes que estado):** replica el del ERP a propósito (misma semántica, mismo hueco conocido si el gate rechaza el PATCH de estado).
