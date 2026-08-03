# Facturas de compra UX (anular/corregir + recepción integrada + doble fecha + CUIT en OC) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Giuliano pueda corregir/anular facturas de compra, registrar la recepción de la OC en el mismo paso que la factura, separar fecha de emisión de fecha contable, y dar de alta proveedores por CUIT desde el modal de OC.

**Architecture:** Migración 062 (RPC `anular_factura_recibida` + columna `fecha_contable` + re-emisión de `registrar_factura_recibida` base 061) primero en Supabase; después frontend en `index.html` (single-file, vanilla JS) reutilizando el flujo de recepción existente extraído a `registrarRecepcionOC`. Asientos NUNCA se borran: se marcan `estado='anulado'` (patrón `anular_venta`).

**Tech Stack:** PostgreSQL/plpgsql (Supabase), vanilla JS, node:test con harness vm (`tests/_harness.js`), pandoc para el manual.

## Global Constraints (spec + CLAUDE.md)

- RPCs devuelven SIEMPRE `jsonb`; `SECURITY INVOKER`; `SET search_path = public`; `REVOKE FROM PUBLIC, anon` + `GRANT authenticated`.
- Migración idempotente, `BEGIN/COMMIT`, query de verificación comentada al pie. **SQL corre en Supabase ANTES de pushear frontend — VERIFICAR el resultado de la corrida (lección 058)**.
- Ediciones futuras de `registrar_factura_recibida` parten de 062 (no de 061).
- `factura_recibida_impuestos.factura_id` ya es `ON DELETE CASCADE` (054) — el DELETE de la factura arrastra las tax lines.
- `trg_audit` ya existe en `facturas_recibidas` (033): un UPDATE previo al DELETE deja el motivo en el audit trail.
- Texto UI en español argentino (voseo). Todo dato interpolado en HTML pasa por `esc()`.
- Validar antes de commitear: extraer `<script>` con awk + `node --check`, y `node --test tests/*.test.js` (hoy 113/113).
- Trabajo en rama `feat/facturas-ux`; merge FF a main recién después del "listo" del SQL.

---

### Task 1: Migración 062 — SQL

**Files:**
- Create: `migrations/062_facturas_ux.sql`

**Interfaces:**
- Produces: RPC `anular_factura_recibida(p_factura_id uuid, p_motivo text) → jsonb {ok, nro, tipo}`; columna `facturas_recibidas.fecha_contable date NOT NULL`; `registrar_factura_recibida` v062 que acepta `p_factura->>'fecha_contable'` (fallback: `fecha`) y fecha el asiento con ella.

- [ ] **Step 1: Escribir la migración.** Estructura:

```sql
-- 062_facturas_ux.sql — Anulación de facturas de compra + fecha contable
-- 1. fecha_contable; 2. re-emisión registrar_factura_recibida (base 061);
-- 3. RPC anular_factura_recibida.
BEGIN;

-- ── 1. Doble fecha ──────────────────────────────────────────────────
ALTER TABLE public.facturas_recibidas
  ADD COLUMN IF NOT EXISTS fecha_contable date;
UPDATE public.facturas_recibidas SET fecha_contable = fecha WHERE fecha_contable IS NULL;
ALTER TABLE public.facturas_recibidas ALTER COLUMN fecha_contable SET NOT NULL;

-- ── 2. registrar_factura_recibida v062 ──────────────────────────────
-- Copiar ÍNTEGRO el cuerpo de 061_match_moneda.sql y aplicar SOLO estos cambios:
--   (a) tras el bloque "IF COALESCE(p_factura->>'fecha','')='' ..." agregar:
--         v_fecha_contable := COALESCE(NULLIF(p_factura->>'fecha_contable',''),
--                                      p_factura->>'fecha')::date;
--       (declarar v_fecha_contable date; en el DECLARE)
--   (b) en crear_asiento: 'fecha', v_fecha_contable  (antes: p_factura->>'fecha')
--   (c) en el INSERT INTO facturas_recibidas: agregar fecha_contable a la lista
--       de columnas y v_fecha_contable a los VALUES (junto a fecha).

-- ── 3. anular_factura_recibida ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anular_factura_recibida(p_factura_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  emp uuid := public.current_empresa_id();
  f record; v_ncnd int;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF COALESCE(TRIM(p_motivo),'') = '' THEN RAISE EXCEPTION 'El motivo es obligatorio'; END IF;
  SELECT * INTO f FROM facturas_recibidas WHERE id = p_factura_id AND empresa_id = emp FOR UPDATE;
  IF f.id IS NULL THEN RAISE EXCEPTION 'Factura no encontrada'; END IF;
  IF (f.tipo IS NULL OR f.tipo = 'factura') THEN
    SELECT count(*) INTO v_ncnd FROM facturas_recibidas
     WHERE empresa_id = emp AND factura_asociada_id = p_factura_id;
    IF v_ncnd > 0 THEN
      RAISE EXCEPTION 'La factura tiene % NC/ND asociada(s): anulalas primero', v_ncnd;
    END IF;
  END IF;
  -- Motivo al audit trail (trg_audit registra el UPDATE con usuario) y después DELETE
  UPDATE facturas_recibidas SET override_motivo = 'ANULADA: ' || TRIM(p_motivo)
   WHERE id = p_factura_id;
  IF f.asiento_id IS NOT NULL THEN
    UPDATE asientos SET estado = 'anulado' WHERE id = f.asiento_id AND empresa_id = emp;
  END IF;
  DELETE FROM facturas_recibidas WHERE id = p_factura_id;  -- cascade: tax lines
  RETURN jsonb_build_object('ok', true, 'nro', f.nro, 'tipo', COALESCE(f.tipo,'factura'));
END $$;
REVOKE ALL ON FUNCTION public.anular_factura_recibida(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anular_factura_recibida(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_factura_recibida(uuid, text) TO authenticated;

COMMIT;
-- Verificación:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='facturas_recibidas' AND column_name='fecha_contable';  -- 1 fila
-- SELECT proname FROM pg_proc WHERE proname='anular_factura_recibida';       -- 1 fila
```

- [ ] **Step 2:** `pbcopy < migrations/062_facturas_ux.sql` → pedir a Giuliano que la corra y **confirme que Run terminó sin error** (mostrar la salida si duda).
- [ ] **Step 3:** Con el "listo": verificar desde el navegador (sesión ERP) que `GET facturas_recibidas ?select=fecha_contable&limit=1` responde OK y que un RPC `anular_factura_recibida` con UUID dummy devuelve "Factura no encontrada".
- [ ] **Step 4:** `git add migrations/062_facturas_ux.sql && git commit -m "feat(compras): migración 062 — anular factura + fecha contable"`.

### Task 2: Doble fecha en el frontend

**Files:**
- Modify: `index.html` — modal factura (~línea 2114), `_frReset` (~11146), `registrarFacturaRecibida` (~11398), queries IVA compras (líneas 2746, 2798, 2812), `renderFacturasRecibidas` (~11482)
- Test: `tests/compras-fiscal.test.js`

**Interfaces:**
- Produces: función pura `validarFechasFactura({emision, contable}) → {ok:boolean, warning:string|null}` (exportada al harness); input `#fr-fecha-contable`.

- [ ] **Step 1: Test (falla).**

```js
test('validarFechasFactura', () => {
  assert.deepEqual(ctx.validarFechasFactura({emision:'2026-06-09',contable:'2026-08-03'}), {ok:true, warning:null});
  const w = ctx.validarFechasFactura({emision:'2026-08-03',contable:'2026-06-09'});
  assert.equal(w.ok, true); assert.match(w.warning, /anterior a la emisión/);
  assert.equal(ctx.validarFechasFactura({emision:'',contable:'2026-08-03'}).ok, false);
  assert.equal(ctx.validarFechasFactura({emision:'2026-08-03',contable:''}).ok, false);
});
```

- [ ] **Step 2: Implementar.**

```js
function validarFechasFactura({emision, contable}){
  if(!emision || !contable) return {ok:false, warning:null};
  return {ok:true, warning: contable < emision
    ? `La fecha contable (${contable}) es anterior a la emisión (${emision}) — verificá que sea intencional`
    : null};
}
```

- HTML: label del campo existente pasa a "Fecha de emisión *"; al lado, nuevo `<div class="form-group"><label>Fecha contable *</label><input type="date" id="fr-fecha-contable"></div>` (la form-row pasa a 3 columnas con Vencimiento).
- `_frReset()`: `document.getElementById('fr-fecha-contable').value=hoyLocal();`.
- `registrarFacturaRecibida`: leer `fechaContable`, validar con `validarFechasFactura` (si `!ok` → notify error; si `warning` → `confirm(warning)` y abortar si cancela), agregar `fecha_contable:fechaContable` al objeto `f`.
- Queries de libros (2746/2798/2812): `?fecha=gte.` → `?fecha_contable=gte.` (y `lte`, y `order=fecha_contable`); en los selects agregar `fecha_contable`. La columna "Fecha" de la tabla muestra emisión y, si difiere, una segunda línea `cont. <fecha_contable>` en `--text3`.
- [ ] **Step 3:** `node --test tests/compras-fiscal.test.js` → PASS. Commit `feat(compras): fecha de emisión + fecha contable en facturas`.

### Task 3: Recepción integrada al facturar (tilde)

**Files:**
- Modify: `index.html` — `saveRecepcion` (~11065), modal factura (HTML, junto al preview del match), `_frMatchInfo`/`frRecalc` (~zona 061), `registrarFacturaRecibida`
- Test: `tests/compras-fiscal.test.js`

**Interfaces:**
- Consumes: `generarAsientoCompra(recepcionItems, oc, fecha)` existente.
- Produces: `registrarRecepcionOC(oc, items, opts)` async (items=`[{itemId,qty,it}]`, opts=`{fecha,certId,colada,remitoNro,obs}`) — crea barras/insumos/herramientas + recepciones_oc + PATCH cantidad_recibida + estado OC + asiento GR-IR; función pura `itemsPendientesOC(ocItems) → [{itemId, qty, it}]`; checkbox `#fr-recibir-todo`.

- [ ] **Step 1: Test de la pura (falla).**

```js
test('itemsPendientesOC', () => {
  const items=[
    {id:'a', cantidad:10, cantidad_recibida:4},
    {id:'b', cantidad:5,  cantidad_recibida:5},
    {id:'c', cantidad:3,  cantidad_recibida:null},
  ];
  const r=ctx.itemsPendientesOC(items);
  assert.deepEqual(r.map(x=>({id:x.itemId,qty:x.qty})), [{id:'a',qty:6},{id:'c',qty:3}]);
  assert.equal(r[0].it.id,'a');
});
```

- [ ] **Step 2: Implementar.**

```js
function itemsPendientesOC(items){
  return (items||[]).map(i=>{
    const qty=(parseFloat(i.cantidad)||0)-(parseFloat(i.cantidad_recibida)||0);
    return qty>0?{itemId:i.id,qty,it:i}:null;
  }).filter(Boolean);
}
```

- Refactor `saveRecepcion`: mover el cuerpo del `for(const r of recepcionesNuevas)` + actualización de estado OC + `generarAsientoCompra` a `async function registrarRecepcionOC(oc, items, {fecha,certId=null,colada='',remitoNro=null,obs=null})` (idéntico, sin tocar lógica). `saveRecepcion` la llama con sus valores del modal.
- HTML modal factura: `<label id="fr-recibir-todo-wrap" style="display:none"><input type="checkbox" id="fr-recibir-todo" onchange="frRecalc()"> Recibí todo el material con esta factura (registra la recepción completa de la OC)</label>` dentro de la sección de match.
- `openFacturaRecibidaModal`: mostrar el wrap solo si `itemsPendientesOC(ocItems.filter(i=>i.oc_id===ocId)).length>0`; desmarcar el checkbox en `_frReset`.
- `_frMatchInfo(ocId, netoTotal)`: si `#fr-recibir-todo` está tildado, calcular el valor recibido como Σ `precio_unitario × cantidad` (total pedido) y `sinRecepciones=false` — el preview muestra el match como quedará tras la recepción.
- `registrarFacturaRecibida`: si el tilde está activo (modo `oc`, tipo `factura`), ANTES del RPC: `const oc=ordenesCompra.find(o=>o.id===_frCtx.ocId); const pend=itemsPendientesOC(ocItems.filter(i=>i.oc_id===_frCtx.ocId)); if(pend.length) await registrarRecepcionOC(oc, pend, {fecha:fechaContable, remitoNro:nro, obs:'Recepción registrada desde factura '+nro});` y recién después `RPC('registrar_factura_recibida',...)`. En el reload agregar `recepciones_oc`,`oc_items`,`barras`,`insumos`,`herramientas`,`certificados`.
- [ ] **Step 3:** tests PASS. Commit `feat(compras): tilde "recibí todo" — recepción completa desde la factura`.

### Task 4: Anular y Corregir

**Files:**
- Modify: `index.html` — `renderFacturasRecibidas` (~11482, columna acciones), zona de funciones fr (~11135)
- Test: `tests/compras-fiscal.test.js`

**Interfaces:**
- Consumes: RPC `anular_factura_recibida` (Task 1), modales `openFacturaRecibidaModal`/`openFacturaSinOCModal`/`openNCNDModal`.
- Produces: `anularFacturaRecibida(id)`, `corregirFacturaRecibida(id)`, pura `armarDraftCorreccion(factura, impuestos) → {ivas:[{alicuota,base,monto}], perceps:[{tipo,monto,jurisdiccion}], campos:{nro,fecha,fechaContable,fechaVto,tipo,letra,moneda,tc,noGravado,exento,total}}`.

- [ ] **Step 1: Test de la pura (falla).**

```js
test('armarDraftCorreccion', () => {
  const f={nro:'A-1',fecha:'2026-07-01',fecha_contable:'2026-08-01',fecha_vto:'2026-08-15',
    tipo:'factura',letra:'A',moneda:'ARS',tipo_cambio:1480,no_gravado:10,exento:0,total:1210};
  const imp=[{tipo:'iva',alicuota:21,base:1000,monto:210},
             {tipo:'percepcion_iibb',monto:15,jurisdiccion:'CABA'}];
  const d=ctx.armarDraftCorreccion(f,imp);
  assert.deepEqual(d.ivas,[{alicuota:21,base:1000,monto:210}]);
  assert.deepEqual(d.perceps,[{tipo:'percepcion_iibb',monto:15,jurisdiccion:'CABA'}]);
  assert.equal(d.campos.fechaContable,'2026-08-01');
  assert.equal(d.campos.tc,1480);
});
```

- [ ] **Step 2: Implementar.**

```js
function armarDraftCorreccion(f, impuestos){
  return {
    ivas:(impuestos||[]).filter(i=>i.tipo==='iva')
      .map(i=>({alicuota:parseFloat(i.alicuota)||0,base:parseFloat(i.base)||0,monto:parseFloat(i.monto)||0})),
    perceps:(impuestos||[]).filter(i=>i.tipo!=='iva')
      .map(i=>({tipo:i.tipo,monto:parseFloat(i.monto)||0,jurisdiccion:i.jurisdiccion||null})),
    campos:{nro:f.nro||'',fecha:f.fecha||'',fechaContable:f.fecha_contable||f.fecha||'',
      fechaVto:f.fecha_vto||'',tipo:f.tipo||'factura',letra:f.letra||'A',
      moneda:f.moneda||'ARS',tc:parseFloat(f.tipo_cambio)||null,
      noGravado:parseFloat(f.no_gravado)||0,exento:parseFloat(f.exento)||0,
      total:parseFloat(f.total)||0},
  };
}
```

- `anularFacturaRecibida(id)`: busca la factura, `prompt('Motivo de la anulación de '+nro+' (obligatorio):')`, si vacío return; `RPC('anular_factura_recibida',{p_factura_id:id,p_motivo:motivo})` → `reload('facturas_recibidas','asientos','asiento_lineas')` + renderAll + notify `✓ ${r.nro} anulada — el asiento quedó en estado anulado`.
- `corregirFacturaRecibida(id)`: `const f=facturasRecibidas.find(...)`; `const imp=await GET('factura_recibida_impuestos','?factura_id=eq.'+id)`; `const draft=armarDraftCorreccion(f,imp)`; confirm explicando que se anula y recarga; RPC anular con motivo `'Corrección: se recarga'`; reload; abrir el modal según origen (`f.oc_id` → `openFacturaRecibidaModal(f.oc_id)`; NC/ND → `openNCNDModal(f.factura_asociada_id||undefined)` con proveedor de f; resto → `openFacturaSinOCModal()` + seleccionar `f.proveedor_id` y `cta_imputacion_id`); después pisar campos con `draft` (inputs + `frIvas=draft.ivas; frPerceps=draft.perceps; frRender(); frRecalc();`).
- Botones por fila en `renderFacturasRecibidas` (después del botón NC/ND existente): `Corregir` (ghost) y `Anular` (danger), ambos con `esc()` en ids.
- [ ] **Step 3:** tests PASS. Commit `feat(compras): anular y corregir facturas de proveedor`.

### Task 5: + CUIT en el modal de OC

**Files:**
- Modify: `index.html` — HTML modal OC (línea 2021), `openProvRapidoModal` (~11219), `saveProvRapido` (~11238)

**Interfaces:**
- Produces: `openProvRapidoModal(destino)` con `destino ∈ {'fr','oc'}` (default `'fr'`, se guarda en variable módulo `_prDestino`).

- [ ] **Step 1:** HTML OC: `<div class="form-group"><label>Proveedor *</label><div style="display:flex;gap:6px"><select id="oc-proveedor" style="flex:1"></select><button type="button" class="btn btn-ghost btn-sm" onclick="openProvRapidoModal('oc')" title="Alta rápida por CUIT">+ CUIT</button></div></div>`. El botón existente del modal factura pasa a `openProvRapidoModal('fr')`.
- [ ] **Step 2:** `saveProvRapido` al final: si `_prDestino==='oc'` → re-armar options de `#oc-proveedor` (mismo map que `openOCModal` línea 10916) y `document.getElementById('oc-proveedor').value=provId`; si `'fr'` → comportamiento actual.
- [ ] **Step 3:** Validación JS global (`node --check`) + commit `feat(compras): alta rápida de proveedor por CUIT desde la OC`.

### Task 6: Validación final, manual y deploy

**Files:**
- Modify: `docs/MANUAL_USUARIO.md` (+ regenerar `.docx` con pandoc), `CLAUDE.md` (bullet migración 062 + rango 001-062)

- [ ] **Step 1:** `awk` extrae el `<script>` grande → `node --check` OK; `node --test tests/*.test.js` → todo verde (esperado: 113 + 3 nuevos = 116+).
- [ ] **Step 2:** Manual sección compras: corregir factura (anular+recargar), tilde recibí-todo, qué es cada fecha, +CUIT. `pandoc docs/MANUAL_USUARIO.md -o docs/MANUAL_USUARIO.docx`.
- [ ] **Step 3:** CLAUDE.md: bullet "**Facturas UX (migración 062)**: fecha_contable (asiento/IVA por contable), anular_factura_recibida (asiento→anulado, factura DELETE con motivo auditado), recepción completa desde el modal de factura (registrarRecepcionOC + itemsPendientesOC), +CUIT en OC".
- [ ] **Step 4:** Merge FF a main + push (Netlify deploy). Smoke en prod con el navegador: abrir modal factura de una OC pendiente y ver el tilde + las dos fechas; corregir una factura override "NS" real como prueba end-to-end (con OK de Giuliano).

## Self-review

- Spec §1 → Task 1+4; §2 → Task 3; §3 → Task 1+2; §4 → Task 5; manual → Task 6. Sin gaps.
- Desvío deliberado de la spec: el asiento NO se borra — se marca `anulado` (convención `anular_venta`/`anularAsiento` del proyecto; los libros ya filtran anulados). Avisar a Giuliano en el cierre.
- Nombres consistentes: `registrarRecepcionOC`, `itemsPendientesOC`, `armarDraftCorreccion`, `validarFechasFactura`, `anular_factura_recibida`, `fecha_contable`, `#fr-fecha-contable`, `#fr-recibir-todo`, `_prDestino`.
