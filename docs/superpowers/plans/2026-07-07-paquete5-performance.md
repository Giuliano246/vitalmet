# Paquete 5 — Performance: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el `loadAll()` post-mutación (38 GETs × 70 call sites) por recargas dirigidas, sumar refetch al volver a la pestaña, y lazy-load del extracto bancario.

**Architecture:** `loadAll()` se refactoriza sobre un registro de tablas `TBL` (query + setter por tabla, contrato externo idéntico: mismos globals, `_loadFail`, banner). `reload(...nombres)` baja solo lo afectado. Los 70 call sites se re-mapean según la tabla de este plan (regla superset). Sin migraciones.

**Tech Stack:** vanilla JS + PostgREST. Validación: `node --check` + suite (48 tests) en cada task.

**Spec:** `docs/superpowers/specs/2026-07-07-paquete5-performance-design.md`

## Global Constraints

- El contrato externo de `loadAll()` NO cambia: mismos globals asignados, mismas queries (copiadas VERBATIM del Promise.all actual), mismo `_loadFail(nombre, e)` por tabla, mismos fallbacks.
- Regla superset en el mapeo: ante la duda, recargar tablas de más.
- Mantienen `loadAll()` completo: `loadEmpresaAndStart`, `retryLoad`, `convertirPresupuesto`, `generarAsientosCierre`, `generarAsientoAjusteInflacion`.
- Validación por task: snippet python + `node --check` + `node --test tests/*.test.js`. Deploy (push) al final de T1 (smoke de arranque), T3 y T4.

---

### Task 1: Registro de tablas + loadAll refactorizado + reload()

**Files:**
- Modify: `index.html` — bloque `loadAll()` (~2540-2600: el `Promise.all` con destructuring + las líneas de fallback `||[]`).

**Interfaces:**
- Produces: `const TBL = {...}` (clave = nombre de tabla DB); `_loadTables(nombres[]) → Promise`; `reload(...nombres) → Promise`; global `_lastLoadAllAt` (ms). `loadAll()` mantiene su firma.

- [ ] **Step 1: Construir el registro**

Estructura (una entrada por cada GET del Promise.all actual — copiar cada querystring EXACTO; los nombres de label son los que hoy recibe `_loadFail`):

```js
const TBL={
  certificados:{q:'<query actual de certs>',set:r=>{certs=r;}},
  barras:{q:'<query actual>',set:r=>{barras=r;}},
  ordenes_produccion:{q:'<query actual con embed barras(lote)>',set:r=>{ops=r;}},
  productos_terminados:{q:'<query actual>',set:r=>{pts=r;}},
  ventas:{q:'<query actual con venta_items embed>',set:r=>{ventas=r;}},
  // … TODAS las tablas del Promise.all, en el mismo orden, hasta acciones_capa …
  usuarios:{rpc:'get_usuarios_empresa',set:r=>{usuariosEmpresa=r;}},
  config_contable:{q:'<query actual limit=1>',set:r=>{configContable=(r&&r[0])||null;}},
};
async function _loadTables(nombres){
  await Promise.all(nombres.map(n=>{
    const t=TBL[n];if(!t)return Promise.resolve();
    const p=t.rpc?RPC(t.rpc,{}):GET(n,t.q);
    return p.catch(e=>{_loadFail(t.label||n,e);return null;}).then(r=>t.set(r||[]));
  }));
}
async function reload(...nombres){await _loadTables(nombres);}
let _lastLoadAllAt=0;
```

`loadAll()` queda: `async function loadAll(){await _loadTables(Object.keys(TBL));_lastLoadAllAt=Date.now();}` — y se BORRAN el destructuring gigante y las líneas de fallback `||[]` (el `set` con `r||[]` ya cubre eso). OJO: si el loadAll actual hace algo más después del Promise.all (revisar el bloque completo antes de borrar), conservarlo.

Detalles a respetar al copiar: `configContable` singleton (`[0]||null`), la RPC de usuarios (verificar cómo se llama hoy en el array y con qué args), y los `.catch(e=>_loadFail('Nombre',e))` — el label humano de cada tabla se copia al campo `label`.

- [ ] **Step 2: Validar y smoke local** — suite 48 PASS + `node --check`. Verificación crítica: `grep -c "GET('" ` dentro del registro debe dar la MISMA cantidad de tablas que el Promise.all viejo (38 entradas). Confirmar que ninguna variable global quedó sin setter (`grep` de cada global del viejo destructure contra los `set:` del registro).

- [ ] **Step 3: Commit + push + verificar arranque en prod**

```bash
git add index.html && git commit -m "refactor(datos): loadAll sobre registro de tablas + reload() dirigido (contrato idéntico)"
git push origin main
```
En prod: login → dashboard con KPIs y digest poblados, todas las páginas renderizan, banner de errores ausente.

---

### Task 2: Re-mapear call sites simples (una tabla o dos)

**Files:**
- Modify: `index.html` — las funciones listadas.

**Interfaces:**
- Consumes: `reload(...nombres)` (Task 1).

- [ ] **Step 1: Reemplazar `await loadAll()` por `await reload(...)` según esta tabla**

| Funciones | reload(...) |
|---|---|
| `saveInsumo`, `deleteInsumo` | `'insumos'` |
| `saveHerramienta`, `deleteHerramienta` | `'herramientas'` |
| `saveCliente`, `deleteCliente`, `importClientes` | `'clientes'` |
| `saveProveedor`, `deleteProveedor` | `'proveedores'` |
| `saveCert`, `saveEditCert`, `deleteCert` | `'certificados','barras'` |
| `saveMaterial`, `deleteMaterial` | `'materiales'` |
| `saveMP`, `saveEditBarra`, `deleteBarra` | `'barras'` |
| `savePT`, `deletePT`, `importPT` | `'productos_terminados'` |
| `saveCheque`, `deleteCheque` | `'cheques'` |
| `saveCuenta`, `deleteCuenta` | `'cuentas_contables'` |
| `saveIndiceIPC`, `deleteIndiceIPC` | `'indices_ipc'` |
| `saveCuentaBancaria` | `'cuentas_bancarias'` |
| `saveDoc`, `aprobarDoc` | `'documentos_controlados'` |
| `saveCalibracion` | `'calibraciones'` |
| `saveNC` | `'no_conformidades'` |
| `saveCapa` | `'acciones_capa'` |
| `savePQPPlantilla` | `'pqp_plantillas','pqp_plantilla_ops'` |
| `saveTratamiento`, `deleteTratamiento` | `'tratamientos'` |
| `savePermisos` | `'permisos_usuario','usuarios'` |
| `saveConfigContable` | `'config_contable'` |
| `savePresupuesto`, `deletePresupuesto` | `'presupuestos'` |
| `cerrarPeriodo`, `reabrirPeriodo` | `'periodos_contables','asientos','asiento_lineas'` |

(Los nombres de clave son las tablas DB del registro — verificar contra las claves reales de `TBL` de Task 1; si un nombre difiere, usar el del registro.)

- [ ] **Step 2: Validar (suite 48 PASS + node --check), commit**

```bash
git add index.html && git commit -m "perf(datos): recargas dirigidas en los guardados/borrados simples (~45 call sites)"
```

---

### Task 3: Re-mapear call sites compuestos + cambiarEstado genérico

**Files:**
- Modify: `index.html`.

**Interfaces:**
- Consumes: `reload(...)`.

- [ ] **Step 1: Mapeo de los flujos compuestos**

| Funciones | reload(...) |
|---|---|
| `saveVenta`, `anularVenta` | `'ventas','productos_terminados','clientes','asientos','asiento_lineas'` |
| `emitirFactura` | `'ventas','asientos','asiento_lineas'` |
| `saveOP`, `saveEditOP`, `deleteOP` | `'ordenes_produccion','barras','productos_terminados'` |
| `saveOC`, `deleteOC` | `'ordenes_compra','oc_items','asientos','asiento_lineas'` |
| `saveRecepcion`, `aceptarRecepcion`, `rechazarRecepcion` | `'recepciones','ordenes_compra','oc_items','barras','insumos','herramientas','certificados'` |
| `registrarFacturaRecibida` | `'facturas_recibidas','ordenes_compra','asientos','asiento_lineas'` |
| `saveAsiento`, `deleteAsiento`, `anularAsiento` | `'asientos','asiento_lineas'` |
| `registrarCobroOPago`, `anularCobPag` | `'asientos','asiento_lineas','cheques'` |
| `importarExtracto`, `conciliarLinea`, `desconciliarLinea` | `'extracto_bancario'` (+ `'asientos','asiento_lineas'` en conciliar/desconciliar si tocan asientos — verificar cada una) |
| `crearAsientoDesdeExtracto` (3 sitios) | `'asientos','asiento_lineas','extracto_bancario'` |

- [ ] **Step 2: `cambiarEstado(tabla, …)` genérico** — reemplazar su `await loadAll()` por `await reload(tabla)` (el primer parámetro YA es el nombre de tabla DB). Verificar leyendo la función que `tabla` llega tal cual.

- [ ] **Step 3: Auditoría final** — `grep -n "await loadAll()" index.html` debe dejar SOLO los 5 sitios de Global Constraints (init, retry, convertir, cierre, ajuste). Si aparece alguno no clasificado, mapearlo con la regla superset o dejarlo en `loadAll()` y anotar por qué.

- [ ] **Step 4: Validar, commit, push, verificación en prod**

```bash
git add index.html && git commit -m "perf(datos): recargas dirigidas en flujos compuestos y cambiarEstado genérico"
git push origin main
```
En prod (DevTools → Network): guardar un insumo dispara 1 GET (no 38); una venta ~5; el estado de una OP 1; la cta cte refleja un cobro recién cargado.

---

### Task 4: Refetch on focus + lazy extracto_bancario (cierra P5)

**Files:**
- Modify: `index.html` — listener global, registro `TBL`, render de Conciliación.

**Interfaces:**
- Consumes: `TBL`, `reload`, `_lastLoadAllAt`, `loadAll`, `renderAll`.

- [ ] **Step 1: Refetch al volver a la pestaña**

```js
let _refetching=false;
document.addEventListener('visibilitychange',async()=>{
  if(document.visibilityState!=='visible')return;
  if(_refetching||!_lastLoadAllAt||Date.now()-_lastLoadAllAt<5*60*1000)return;
  if(!currentEmpresa)return; // sin sesión no hay nada que refrescar
  _refetching=true;
  try{await loadAll();renderAll();}catch(e){console.warn('refetch on focus:',e);}
  finally{_refetching=false;}
});
```

- [ ] **Step 2: Lazy extracto** — sacar `extracto_bancario` de `Object.keys(TBL)` en el arranque: agregar flag `lazy:true` a su entrada y en `loadAll()` filtrar `Object.keys(TBL).filter(n=>!TBL[n].lazy)`. En el render de Conciliación (buscar el render que usa `extractoBancario`), al principio: `if(!_extractoLoaded){await reload('extracto_bancario');_extractoLoaded=true;}` (global `let _extractoLoaded=false;`; `reload('extracto_bancario')` sigue funcionando para las mutaciones de Task 3 — el flag solo controla la carga inicial). Verificar que `renderConciliacion` (o su nombre real) esté en `PAGE_RENDERS` y pueda ser async.

- [ ] **Step 3: Validar, commit, push, verificación final del paquete**

```bash
git add index.html && git commit -m "perf(datos): refetch al volver a la pestaña (staleness >5min) + lazy-load del extracto bancario"
git push origin main
```
En prod: arranque sin GET de extracto_bancario (Network); entrar a Conciliación lo carga; dejar la pestaña oculta >5 min y volver dispara el refresh.

## Self-review

- Cobertura: 5A→T1-T3, 5B→T4.1, 5C→T4.2. Fuera de alcance (bounding) documentado en la spec. ✓
- Placeholders: las queries del registro se copian "VERBATIM del Promise.all actual" con verificación de conteo (38) y de setters — es transcripción guiada, no diseño pendiente. ✓
- Consistencia: `TBL/_loadTables/reload/_lastLoadAllAt` idénticos entre tasks; claves = nombres de tabla DB usados en el mapeo de T2/T3. ✓
