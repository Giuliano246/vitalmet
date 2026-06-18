# Conciliación Bancaria Fase B — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar a VitalStock un módulo de conciliación bancaria — alta de cuentas bancarias, importación del extracto pegando desde Excel/CSV, auto-match contra los movimientos del libro (asiento_lineas de la cuenta del banco) por importe exacto + ventana de fechas, y generación del asiento contable desde una línea no conciliada.

**Architecture:** Postgres/Supabase + RLS por `empresa_id` (single-tenant, `empresa_id = a0a19507-2a50-4e80-a716-e9459f51d653`). Dos tablas nuevas (`cuentas_bancarias`, `extracto_bancario`). El parseo del pegado y la sugerencia de match son funciones puras client-side (testeables con el harness vm). La creación de asientos reusa la RPC atómica `crear_asiento`.

**Tech Stack:** PostgreSQL 17 (Supabase), PostgREST, HTML/vanilla JS único (`index.html`), tests con `node --test` sobre `tests/_harness.js`.

---

## Convenciones del proyecto (idénticas a Fase A — LEER)

- **SQL se aplica a mano en el SQL Editor de Supabase ANTES de pushear el frontend.** El ejecutor NO tiene psql/CLI. Para la migración: escribir el archivo → pasárselo a Giuliano para el SQL Editor → esperar "listo" → correr la query de verificación → commitear.
- Migraciones: `BEGIN; ... COMMIT;`, idempotentes (`IF NOT EXISTS`/`CREATE OR REPLACE`/`DROP ... IF EXISTS`), retrocompatibles, query de verificación comentada al pie.
- RPCs devuelven `jsonb`, `SET search_path = public`, `REVOKE EXECUTE ... FROM PUBLIC, anon;` (anon hereda de PUBLIC — REVOKE FROM anon solo NO alcanza, aprendido en Fase A) + `GRANT ... TO authenticated;`. No se crean RPCs nuevas en esta fase (se reusa `crear_asiento`).
- Tablas nuevas: RLS `tenant_isolation FOR ALL TO authenticated USING (empresa_id = (SELECT public.current_empresa_id())) WITH CHECK (...)`, + trigger `trg_audit AFTER INSERT OR UPDATE OR DELETE ... fn_audit()`.
- Frontend, tabla nueva: global + entrada AL FINAL del destructure de `loadAll()` y del array de GETs con `.catch(e=>_loadFail('Nombre',e))` + fallback `||[]`. Render en `PAGE_RENDERS`. Página nueva: `PAGE_TO_GROUP` + `GROUP_TABS` + `groupMods` en `aplicarPermisos()` + `<div class="tabs"></div>` en el `.page-header`.
- Toda interpolación de dato de usuario en HTML pasa por `esc()`. Mutaciones de asientos → RPC `crear_asiento`. Antes de cada commit que toca `index.html`: `node --check` del `<script>` + `node --test tests/*.test.js`. Texto UI en español argentino (voseo).

## Decisiones tomadas (sesión 2026-06-18)

| Decisión | Elección |
|---|---|
| Importación del extracto | **Pegar desde Excel/CSV** en un textarea (parseo de fecha/descripción/importe). Sin subir archivo. |
| Criterio de auto-match | **Importe exacto + ventana de fecha** (±N días configurable en la UI, default ±3). |
| Línea sin match | **Marcar pendiente + poder generar el asiento desde la pantalla** (ej. comisión → cuenta de gastos bancarios). |
| Convención de signo del extracto | `importe` con signo: **+ = crédito/ingreso** al banco, **− = débito/egreso**. En el libro, el movimiento neto de la cuenta banco = `debe − haber` (banco es activo: debe=ingreso, haber=egreso). Match si `(debe − haber) == importe`. |

## File Structure

- **Create** `migrations/035_conciliacion_bancaria.sql` — tablas `cuentas_bancarias` y `extracto_bancario` (RLS + audit + FKs + índices).
- **Modify** `index.html`:
  - globals `cuentasBancarias`, `extractoBancario` + `loadAll` + fallbacks.
  - nav: página `conciliacion` (PAGE_TO_GROUP + GROUP_TABS + groupMods + page HTML con tabs div) + `PAGE_RENDERS`.
  - CRUD simple de cuentas bancarias (modal alta/edición + render).
  - funciones puras `parsearExtractoPegado(texto)` y `sugerirMatchExtracto(linea, movsBanco, ventanaDias)`.
  - UI de importación (pegar → parsear → preview → guardar líneas) y de conciliación (dos columnas, auto-match, marcar conciliado, crear asiento desde línea pendiente).
- **Create** `tests/conciliacion.test.js` — tests de las 2 funciones puras.

## Orden de dependencias
035 (tablas) → globals/loadAll/nav → CRUD cuentas bancarias → funciones puras + tests → UI importación → UI conciliación + crear asiento.

---

## Task 1: Migración 035 — tablas de conciliación bancaria

**Files:**
- Create: `migrations/035_conciliacion_bancaria.sql`

- [ ] **Step 1: Confirmar nombres reales**

Verificar (leyendo migraciones): `cuentas_contables(id)` existe (para la FK `cuenta_contable_id`), `current_empresa_id()` (006), `fn_audit()` (023). Confirmar el patrón RLS optimizado `(SELECT public.current_empresa_id())` usado en migs 020/022/032/033.

- [ ] **Step 2: Escribir la migración**

`migrations/035_conciliacion_bancaria.sql`:
```sql
-- 035_conciliacion_bancaria.sql
-- Módulo de conciliación bancaria: cuentas bancarias + líneas de extracto.
BEGIN;

-- 1) Cuentas bancarias (enlazan con una cuenta del plan, ej. 111003 BANCO HSBC)
CREATE TABLE IF NOT EXISTS public.cuentas_bancarias (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid NOT NULL,
  nombre             text NOT NULL,
  banco              text,
  nro_cuenta         text,
  cbu                text,
  moneda             text NOT NULL DEFAULT 'ARS' CHECK (moneda IN ('ARS','USD')),
  cuenta_contable_id uuid REFERENCES public.cuentas_contables(id) ON DELETE SET NULL,
  activa             boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cuentas_bancarias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.cuentas_bancarias;
CREATE POLICY tenant_isolation ON public.cuentas_bancarias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));
DROP TRIGGER IF EXISTS trg_audit ON public.cuentas_bancarias;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.cuentas_bancarias
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

-- 2) Líneas del extracto bancario
CREATE TABLE IF NOT EXISTS public.extracto_bancario (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         uuid NOT NULL,
  cuenta_bancaria_id uuid NOT NULL REFERENCES public.cuentas_bancarias(id) ON DELETE CASCADE,
  fecha              date NOT NULL,
  descripcion        text,
  importe            numeric NOT NULL,           -- + crédito/ingreso, − débito/egreso
  saldo              numeric,                     -- saldo informado por el banco (opcional)
  referencia         text,
  conciliado         boolean NOT NULL DEFAULT false,
  asiento_linea_id   uuid,                        -- línea del libro con la que matchea
  import_batch       text,                        -- agrupa una importación (timestamp/etiqueta)
  created_at         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.extracto_bancario ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.extracto_bancario;
CREATE POLICY tenant_isolation ON public.extracto_bancario
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT public.current_empresa_id()))
  WITH CHECK (empresa_id = (SELECT public.current_empresa_id()));
DROP TRIGGER IF EXISTS trg_audit ON public.extracto_bancario;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.extracto_bancario
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

CREATE INDEX IF NOT EXISTS idx_extracto_cuenta_fecha
  ON public.extracto_bancario (cuenta_bancaria_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_extracto_no_conciliado
  ON public.extracto_bancario (cuenta_bancaria_id) WHERE conciliado = false;

COMMIT;

-- Verificación:
-- SELECT tablename, rowsecurity FROM pg_tables
--  WHERE schemaname='public' AND tablename IN ('cuentas_bancarias','extracto_bancario');
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--  WHERE tgname='trg_audit'
--    AND tgrelid::regclass::text IN ('cuentas_bancarias','extracto_bancario');
-- Esperado: 2 tablas con rowsecurity=true y 2 triggers trg_audit.
```

- [ ] **Step 3: Aplicar** — pasar el archivo a Giuliano para el SQL Editor; esperar "listo".

- [ ] **Step 4: Verificar** — correr las queries del pie. Esperado: 2 tablas con RLS + 2 triggers.

- [ ] **Step 5: Commit**
```bash
git add migrations/035_conciliacion_bancaria.sql
git commit -m "feat(contab): tablas de conciliación bancaria — cuentas_bancarias + extracto_bancario (mig 035)"
```

---

## Task 2: Frontend — globals, loadAll y registro de la página

**Files:** Modify `index.html`

- [ ] **Step 1: Globals + loadAll**

Agregar globals `let cuentasBancarias=[],extractoBancario=[];` junto a los otros (línea ~1926). En `loadAll`:
- al array de GETs (al final): `GET('cuentas_bancarias','?order=nombre.asc').catch(e=>_loadFail('Cuentas bancarias',e)),` y `GET('extracto_bancario','?order=fecha.desc').catch(e=>_loadFail('Extracto bancario',e)),`
- al destructure (al final, en el mismo orden).
- a la línea de fallbacks (~2246): `cuentasBancarias=cuentasBancarias||[];extractoBancario=extractoBancario||[];`

- [ ] **Step 2: Registrar la página en la navegación**

- `PAGE_TO_GROUP` (línea ~2252): agregar `conciliacion:'contabilidad'`.
- `GROUP_TABS.contabilidad` (array ~2257-2264): agregar `{k:'conciliacion',l:'Conciliación bancaria'}` como tab top-level (después de `{k:'cheques',l:'Cheques'}` o junto a `correlatividad`).
- `groupMods.contabilidad` (~6887): agregar `'conciliacion'`.
- `PAGE_RENDERS`: agregar `conciliacion:[renderConciliacion]`.
- HTML: agregar `<div class="page" id="page-conciliacion">` cerca de las otras páginas de contabilidad (ej. junto a `page-correlatividad`), con `.page-header` que contenga `<div class="tabs"></div>` y contenedores `#concil-cuentas`, `#concil-import`, `#concil-tablero`.

- [ ] **Step 3: Validar**
```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erpb2.js',s)" && node --check /tmp/erpb2.js && echo "SYNTAX OK"
node --test tests/*.test.js
```
Expected: SYNTAX OK; 25 tests pasan.

- [ ] **Step 4: Commit**
```bash
git add index.html
git commit -m "feat(contab): página Conciliación bancaria + carga de cuentas_bancarias/extracto_bancario"
```

---

## Task 3: Frontend — ABM de cuentas bancarias

**Files:** Modify `index.html`

- [ ] **Step 1: Modal + render**

Agregar un modal "Cuenta bancaria" con campos: nombre, banco, nro_cuenta, cbu, moneda (ARS/USD), cuenta contable (select de cuentas activo via `_llenarSelectCuentas('cb-cuenta',['activo'],...)`, típicamente 111003/111004), activa. `renderConciliacionCuentas()`: tabla de cuentas con botón "Editar"/"Nueva", mostrada dentro de `#concil-cuentas`. Mirar el patrón de un ABM existente (ej. proveedores) para el modal + `openModal`/`closeModal`.

- [ ] **Step 2: Save flow**
```js
async function saveCuentaBancaria(btnId){
  const nombre=document.getElementById('cb-nombre').value.trim();
  if(!nombre){notify('Poné un nombre para la cuenta','err');return;}
  const id=document.getElementById('cb-edit-id').value||null;
  const data={empresa_id:currentEmpresa.id,nombre,
    banco:document.getElementById('cb-banco').value.trim()||null,
    nro_cuenta:document.getElementById('cb-nro').value.trim()||null,
    cbu:document.getElementById('cb-cbu').value.trim()||null,
    moneda:document.getElementById('cb-moneda').value,
    cuenta_contable_id:document.getElementById('cb-cuenta').value||null,
    activa:document.getElementById('cb-activa').checked};
  setBusy(btnId,true);
  try{
    if(id){await PATCH('cuentas_bancarias',data,`?id=eq.${id}`);}
    else{await POST('cuentas_bancarias',data);}
    await loadAll();closeModal('modal-cuenta-bancaria');renderAll();notify('Cuenta bancaria guardada');
  }catch(e){notify(e.message||'Error guardando cuenta','err');}
  finally{setBusy(btnId,false);}
}
```
(Verificar firmas reales de POST/PATCH/setBusy/notify por grep — POST(t,b), PATCH(t,b,p).)

- [ ] **Step 3: Validar** (node --check + node --test, igual que Task 2 Step 3).

- [ ] **Step 4: Commit**
```bash
git add index.html
git commit -m "feat(contab): ABM de cuentas bancarias"
```

---

## Task 4: Frontend — funciones puras de parseo y match (TDD)

**Files:** Create `tests/conciliacion.test.js`; Modify `index.html`

- [ ] **Step 1: Escribir los tests que fallan**

`tests/conciliacion.test.js`:
```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const erp = require('./_harness').load();
const run = (code) => erp.run(code);

test('parsearExtractoPegado: tab-separated con fecha dd/mm/yyyy y monto AR', () => {
  const txt = '01/06/2026\tTransferencia recibida\t1.234,56\n02/06/2026\tComisión mantenimiento\t-500,00';
  const r = run(`parsearExtractoPegado(${JSON.stringify(txt)})`);
  assert.strictEqual(r.length, 2);
  assert.strictEqual(r[0].fecha, '2026-06-01');
  assert.strictEqual(r[0].importe, 1234.56);
  assert.strictEqual(r[1].importe, -500);
  assert.strictEqual(r[1].descripcion, 'Comisión mantenimiento');
});

test('parsearExtractoPegado: ignora líneas vacías y sin importe', () => {
  const txt = '\n01/06/2026\tAlgo\t100,00\n   \n';
  const r = run(`parsearExtractoPegado(${JSON.stringify(txt)})`);
  assert.strictEqual(r.length, 1);
});

test('sugerirMatchExtracto: matchea por importe (debe-haber) y fecha dentro de ventana', () => {
  const linea = { fecha:'2026-06-03', importe:1000 };
  const movs = [
    { id:'a', fecha:'2026-06-01', debe:1000, haber:0 },   // +1000, 2 días → candidato
    { id:'b', fecha:'2026-06-03', debe:0, haber:1000 },    // -1000 → no
  ];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r?.id, 'a');
});

test('sugerirMatchExtracto: importe negativo matchea un haber', () => {
  const linea = { fecha:'2026-06-05', importe:-500 };
  const movs = [{ id:'x', fecha:'2026-06-05', debe:0, haber:500 }];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r?.id, 'x');
});

test('sugerirMatchExtracto: fuera de ventana no matchea', () => {
  const linea = { fecha:'2026-06-20', importe:1000 };
  const movs = [{ id:'a', fecha:'2026-06-01', debe:1000, haber:0 }];
  const r = run(`sugerirMatchExtracto(${JSON.stringify(linea)},${JSON.stringify(movs)},3)`);
  assert.strictEqual(r, null);
});
```

- [ ] **Step 2: Correr y verificar que FALLA**
```bash
node --test tests/conciliacion.test.js
```
Expected: FALLA (`parsearExtractoPegado is not defined`).

- [ ] **Step 3: Implementar las funciones puras en index.html** (cerca de las otras compute*/evaluar*):
```js
// Parseo del extracto pegado (tab o ; o , como separador). Devuelve
// [{fecha:'YYYY-MM-DD', descripcion, importe:Number}]. Puro (sin DOM/red).
function parsearExtractoPegado(texto){
  const norm=n=>{ // "1.234,56" -> 1234.56 ; "-500,00" -> -500 ; "1234.56" -> 1234.56
    let s=String(n).trim().replace(/\s/g,'');
    if(s.includes(',')){ s=s.replace(/\./g,'').replace(',','.'); }
    const v=parseFloat(s);
    return isFinite(v)?v:null;
  };
  const fechaISO=f=>{
    const m=String(f).trim().match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})$/);
    if(m){ let[,d,mo,y]=m; if(y.length===2)y='20'+y; return `${y}-${mo.padStart(2,'0')}-${d.padStart(2,'0')}`; }
    const iso=String(f).trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    return iso?iso[0]:null;
  };
  return String(texto||'').split(/\r?\n/).map(l=>{
    if(!l.trim())return null;
    const cols=l.split(/\t|;|,(?=\s|\d)/).map(c=>c.trim()).filter(c=>c!=='');
    if(cols.length<2)return null;
    const fecha=fechaISO(cols[0]);
    const importe=norm(cols[cols.length-1]);
    if(fecha===null||importe===null)return null;
    const descripcion=cols.slice(1,-1).join(' ').trim();
    return {fecha,descripcion,importe};
  }).filter(Boolean);
}

// Sugerencia de match: movimiento del libro (banco) cuyo neto (debe-haber)
// == importe y cuya fecha está dentro de ±ventanaDias. Devuelve el más
// cercano en fecha o null. Puro.
function sugerirMatchExtracto(linea, movsBanco, ventanaDias){
  const diasEntre=(a,b)=>Math.abs((Date.parse(a)-Date.parse(b))/86400000);
  let mejor=null, mejorDelta=Infinity;
  for(const m of movsBanco||[]){
    const neto=(parseFloat(m.debe)||0)-(parseFloat(m.haber)||0);
    if(Math.abs(neto-linea.importe)>=0.01)continue;
    const d=diasEntre(linea.fecha,m.fecha);
    if(d>ventanaDias)continue;
    if(d<mejorDelta){mejor=m;mejorDelta=d;}
  }
  return mejor;
}
```
> Nota: `Date.parse` sobre 'YYYY-MM-DD' es estable para diferencia de días; no se usa `Date.now()`.

- [ ] **Step 4: Correr y verificar que PASA**
```bash
node --test tests/conciliacion.test.js
```
Expected: PASS (5 tests).

- [ ] **Step 5: node --check + suite completa**
```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const s=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).reduce((a,b)=>b.length>a.length?b:a);fs.writeFileSync('/tmp/erpb4.js',s)" && node --check /tmp/erpb4.js && echo "SYNTAX OK"
node --test tests/*.test.js
```
Expected: SYNTAX OK; 30 tests (25 + 5 nuevos).

- [ ] **Step 6: Commit**
```bash
git add index.html tests/conciliacion.test.js
git commit -m "feat(contab): funciones puras de parseo de extracto y sugerencia de match + tests"
```

---

## Task 5: Frontend — importación del extracto (pegar → parsear → guardar)

**Files:** Modify `index.html`

- [ ] **Step 1: UI de importación**

Dentro de `#concil-import`: un selector de cuenta bancaria (de `cuentasBancarias` activas), un `<textarea id="concil-paste">` con placeholder explicando el formato (fecha TAB descripción TAB importe; importe negativo = débito), un botón "Previsualizar" que llama `previewExtracto()`, una tabla de preview `#concil-preview-tbody`, y un botón "Importar N líneas" que llama `importarExtracto(btnId)`.

- [ ] **Step 2: Preview + importación**
```js
let _extractoPreview=[];
function previewExtracto(){
  const txt=document.getElementById('concil-paste').value;
  _extractoPreview=parsearExtractoPegado(txt);
  const tb=document.getElementById('concil-preview-tbody');
  if(!_extractoPreview.length){tb.innerHTML='<tr><td colspan="3" style="color:var(--text3)">Nada para importar (revisá el formato)</td></tr>';return;}
  tb.innerHTML=_extractoPreview.map(r=>`<tr><td class="mono">${esc(r.fecha)}</td><td>${esc(r.descripcion)}</td><td class="mono" style="text-align:right;color:${r.importe<0?'var(--red)':'var(--green)'}">${fmtARS(r.importe)}</td></tr>`).join('');
}
async function importarExtracto(btnId){
  const ctaId=document.getElementById('concil-cuenta-import').value;
  if(!ctaId){notify('Elegí la cuenta bancaria','err');return;}
  if(!_extractoPreview.length){notify('No hay líneas previsualizadas','err');return;}
  const batch='imp-'+document.getElementById('concil-fecha-import')?.value+'-'+_extractoPreview.length;
  const rows=_extractoPreview.map(r=>({empresa_id:currentEmpresa.id,cuenta_bancaria_id:ctaId,fecha:r.fecha,descripcion:r.descripcion,importe:r.importe,conciliado:false,import_batch:batch}));
  setBusy(btnId,true);
  try{
    await POST('extracto_bancario',rows);
    _extractoPreview=[];document.getElementById('concil-paste').value='';
    await loadAll();renderAll();notify(`${rows.length} líneas importadas`);
  }catch(e){notify(e.message||'Error importando','err');}
  finally{setBusy(btnId,false);}
}
```
> `batch` no debe usar `Date.now()` en el harness, pero en el navegador real está OK; acá se arma con un input de fecha opcional. Si no hay input, usar el conteo + la primera fecha. Ajustar a lo que exista. POST acepta array (ver cómo POST inserta lotes en otras partes del código).

- [ ] **Step 3: Validar** (node --check + node --test).

- [ ] **Step 4: Commit**
```bash
git add index.html
git commit -m "feat(contab): importación del extracto bancario por pegado con preview"
```

---

## Task 6: Frontend — tablero de conciliación + crear asiento desde línea pendiente

**Files:** Modify `index.html`

- [ ] **Step 1: Tablero de conciliación**

Dentro de `#concil-tablero`: selector de cuenta bancaria + input "ventana de días" (default 3). `renderConciliacion()` (registrada en PAGE_RENDERS) arma:
- Para la cuenta elegida, calcula `movsBanco` = líneas del libro de esa cuenta contable que aún NO están conciliadas: filtrar `asientoLineas` donde `cuenta_id === cuentaBancaria.cuenta_contable_id` y cuyo `id` no esté ya en `extractoBancario[*].asiento_linea_id`. Para la fecha del movimiento, usar la fecha del asiento (join: buscar en `asientos` por `asiento_id`).
- Tabla del extracto (líneas de esa cuenta), cada fila con su estado (conciliado/pendiente) y, si está pendiente, la **sugerencia** `sugerirMatchExtracto(linea, movsBanco, ventana)`:
  - si hay sugerencia → botón "Conciliar" que llama `conciliarLinea(extractoId, asientoLineaId)`.
  - si no hay → botón "Crear asiento" que abre el modal de asiento desde extracto.
- Mostrar totales: saldo según extracto vs saldo según libro, y la diferencia.

- [ ] **Step 2: Conciliar (marcar la línea)**
```js
async function conciliarLinea(extractoId, asientoLineaId){
  try{
    await PATCH('extracto_bancario',{conciliado:true,asiento_linea_id:asientoLineaId},`?id=eq.${extractoId}`);
    await loadAll();renderAll();notify('Línea conciliada');
  }catch(e){notify(e.message||'Error al conciliar','err');}
}
async function desconciliarLinea(extractoId){
  try{
    await PATCH('extracto_bancario',{conciliado:false,asiento_linea_id:null},`?id=eq.${extractoId}`);
    await loadAll();renderAll();notify('Conciliación deshecha');
  }catch(e){notify(e.message||'Error','err');}
}
```

- [ ] **Step 3: Crear asiento desde línea pendiente**

Modal que toma la línea del extracto (fecha, descripción, importe) y pide la **contracuenta** (select de cuentas, ej. gastos bancarios para una comisión, o la cuenta que corresponda). Arma el asiento reusando `crear_asiento`, con la lógica de signo del banco (banco es activo): si `importe > 0` (ingreso) → Debe banco / Haber contracuenta; si `importe < 0` (egreso) → Debe contracuenta / Haber banco. Luego marca la línea conciliada contra la **línea del banco** recién creada.
```js
async function crearAsientoDesdeExtracto(btnId){
  const ex=_extractoActual; // seteada al abrir el modal
  const cb=cuentasBancarias.find(c=>c.id===ex.cuenta_bancaria_id);
  const ctaBanco=cb?.cuenta_contable_id;
  const ctaContra=document.getElementById('ce-contracuenta').value;
  if(!ctaBanco){notify('La cuenta bancaria no tiene cuenta contable asociada','err');return;}
  if(!ctaContra){notify('Elegí la contracuenta','err');return;}
  const monto=Math.abs(ex.importe);
  const ingreso=ex.importe>0;
  const lineas=ingreso
    ? [{cuenta_id:ctaBanco,debe:monto,haber:0,descripcion:ex.descripcion||'Mov. banco',orden:0},
       {cuenta_id:ctaContra,debe:0,haber:monto,descripcion:ex.descripcion||'',orden:1}]
    : [{cuenta_id:ctaContra,debe:monto,haber:0,descripcion:ex.descripcion||'',orden:0},
       {cuenta_id:ctaBanco,debe:0,haber:monto,descripcion:ex.descripcion||'Mov. banco',orden:1}];
  const cabecera={fecha:ex.fecha,descripcion:`Banco: ${ex.descripcion||''}`.trim(),comprobante_nro:ex.referencia||null,tipo:'auto-banco',origen_tipo:'extracto_bancario',origen_id:ex.id,estado:'confirmado',moneda:cb?.moneda||'ARS'};
  setBusy(btnId,true);
  try{
    const as=await RPC('crear_asiento',{p_cabecera:cabecera,p_lineas:lineas});
    // buscar la línea del banco del asiento recién creado para enlazarla
    await loadAll();
    const lineaBanco=asientoLineas.find(l=>l.asiento_id===(as.id)&&l.cuenta_id===ctaBanco);
    if(lineaBanco){await PATCH('extracto_bancario',{conciliado:true,asiento_linea_id:lineaBanco.id},`?id=eq.${ex.id}`);}
    await loadAll();closeModal('modal-asiento-extracto');renderAll();notify('Asiento creado y línea conciliada');
  }catch(e){notify(e.message||'Error creando asiento','err');}
  finally{setBusy(btnId,false);}
}
```
> El asiento pasa por el trigger de período cerrado (mig 032): si la fecha cae en un mes cerrado, la RPC tira excepción y `notify` la muestra — correcto. Verificar la forma real del retorno de `crear_asiento` (`as.id`); ajustar si difiere (Fase A confirmó que devuelve `{id,numero}`).

- [ ] **Step 4: Validar** (node --check + node --test; 30 tests verdes).

- [ ] **Step 5: Commit**
```bash
git add index.html
git commit -m "feat(contab): tablero de conciliación bancaria con auto-match y alta de asiento desde extracto"
```

---

## Cierre de la Fase B
- [ ] Migración 035 aplicada en Supabase + archivos commiteados.
- [ ] `node --test tests/*.test.js` en verde (30 tests).
- [ ] Smoke test (local, contra DB real): crear una cuenta bancaria (enlazada a 111003), pegar un extracto de prueba, auto-match de una línea que coincida con un asiento existente, y crear asiento desde una comisión. Verificar que el saldo extracto vs libro cuadra.
- [ ] Revisión final (subagente) + merge a `main` con autorización explícita (deploy).

## Notas de cobertura del spec
- Spec Fase B (`cuentas_bancarias`, `extracto_bancario`, importación, auto-match, UI dos columnas) → Tasks 1-6.
- Decisiones de la sesión respetadas: pegar Excel/CSV (Task 5), match importe exacto + ventana (Task 4 + Task 6), crear asiento desde línea pendiente (Task 6).
- Fuera de alcance: subir archivo .xlsx (se eligió pegar), conciliación multi-moneda con conversión (cada cuenta es ARS o USD; no se convierte), import recurrente/automático.
