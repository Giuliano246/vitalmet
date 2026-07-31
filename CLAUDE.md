# CLAUDE.md — VitalStock ERP

## Proyecto
VitalStock es un ERP single-file (HTML + Supabase) para Vitalmet SA, empresa metalúrgica argentina que fabrica productos para la industria petrolera (uniones, válvulas, anillos BX, codos, campanas, etc.).

**Owner:** Giuliano
**Empresa:** Vitalmet SA — Perú 246, Villa Martelli, Buenos Aires
**Web:** vitalmetsa.com
**ERP URL:** https://erp.vitalmetsa.com (CNAME → Netlify, site `vitalmetstock`)

## Stack
- **Frontend:** HTML único (`index.html`, ~8.000 líneas), vanilla JS, CSS embebido. Libs por CDN (cdnjs): jsPDF + autotable, SheetJS (xlsx), Chart.js.
- **Backend/DB:** Supabase (auth + PostgreSQL 17, REST vía PostgREST)
- **Hosting:** Netlify (deploy automático al pushear a `main` de github.com/Giuliano246/vitalmet)
- **Headers:** `netlify.toml` define CSP + security headers. **Si se agrega un CDN, API externa o fuente nueva, agregar el origen al CSP o se bloquea en producción.**
- **Facturación AFIP:** microservicio aparte `~/vitalmet-billing` en Railway (https://billing.vitalmetsa.com). Falta solo el cert X.509.

## Supabase
- **URL:** `https://dqvlqhaxgvtilhiuatpv.supabase.co` (anon key en el HTML, ~línea 1843)
- **RLS:** activado en TODAS las tablas. Patrón: policy `tenant_isolation FOR ALL TO authenticated USING (empresa_id = public.current_empresa_id())` + `WITH CHECK` igual. `current_empresa_id()` lee el JWT.
- **empresa_id del usuario:** `a0a19507-2a50-4e80-a716-e9459f51d653` — hardcodear directo en migrations y scripts (single-tenant en la práctica).
- **Migraciones:** `migrations/001` a `056`. Convención: BEGIN/COMMIT, idempotentes (IF NOT EXISTS / DROP IF EXISTS), retrocompatibles, query de verificación comentada al pie. **El SQL se corre en el SQL Editor ANTES de deployar el frontend.** Para dry-run contra prod: Management API con COMMIT→ROLLBACK.
- **Integridad (migración 023):** RPCs atómicas `guardar_venta` / `anular_venta` / `convertir_presupuesto` / `crear_asiento` / `consumir_barra` / `upsert_cliente` (SECURITY INVOKER), trigger de partida doble diferido, numeración de asientos por DB, guard anti-edición de ventas con CAE, `audit_log` + trigger `trg_audit` (fn_audit) en tablas con plata.
- **Integridad (migración 055):** trigger + UNIQUE anti-duplicado de `facturas_recibidas` (empresa, proveedor, tipo, letra, nro); `recepciones_oc.oc_item_id` es ON DELETE **RESTRICT** (editar OC con recepciones ya no reescribe ítems — el frontend solo actualiza cabecera); RPC `eliminar_op` (repone kg a la barra, bloquea si hay PT/registros de calidad/NC/tratamientos/signoffs); numeración de presupuestos server-side (`trg_presupuesto_nro`, P-nnnn con advisory lock); RPCs `guardar_permisos` y `ajustar_precios_pct` atómicas; `clientes.condicion_fiscal` + `config_contable.punto_venta`. La facturación (`emitirFactura`) deriva letra A/B de la condición fiscal del cliente (RG 5003: RI y monotributo→A, exento y CF→B), convierte USD→ARS al TC vendedor BNA del día y usa el punto de venta configurado — funciones puras `tipoComprobanteVentaAFIP` / `buildItemsFactura` con tests en `tests/facturacion.test.js`. Tarifa operario unificada en `tarifaOperarioUSD()` (lee `empresas.tarifa_operario_usd_h`).
- **Ciclo del dinero (migración 056):** tabla `retenciones_sufridas` (certificados Gcias/IIBB/SUSS/IVA que aplican los clientes al cobrar; NO está en loadAll — se consulta on-demand para el exportable) + config `cta_ret_*` (defaults del plan real: 113018/113006/113019/113005) y `cta_cheques_cartera`/`cta_cheques_emitidos` (111006/212003). Cobros con retenciones: `armarLineasCobro` (pura, tests en `tests/ciclo-dinero.test.js`) arma banco + retenciones al debe / Deudores por el total; la cta cte suma todos los debe. Cheques: `contabilizarCheque` genera asientos por estado (depositado/rechazado/debitado; origen_tipo `cheque-*` idempotente); el alta contable la hace Cobros y Pagos método "cheque"; rechazo recibido = asiento tipo `auto-cheque-rechazo` que computeCtaCte suma como cargo (deuda revive). Costo real de OP: al completar (cambiarEstado o saveEditOP) `persistirCostoRealOP` congela `ordenes_produccion.costo_real_usd` (por unidad, vía `computeCostoRealOP` pura) y valúa el PT del lote a ese costo. Exportables nuevos: IVA ventas con letra/signo (`cbteAfipInfo`/`alicuotaImplicita` puras), Posición IVA del mes, Retenciones sufridas.
- **Compras fiscal (migración 054):** `registrar_factura_recibida(p_factura, p_impuestos, p_override, p_motivo)` hace 3-way match + asiento + tax lines en `factura_recibida_impuestos` (una fila por alícuota de IVA / percepción, patrón SAP). Regla: montos SIEMPRE positivos en DB, el signo lo da `facturas_recibidas.tipo` (`nota_credito` resta). El RPC valida la aritmética (total = bases + no gravado + exento + IVA + percepciones ±$0.01) y que letra B/C/X no discrimine IVA. Facturas sin OC y NC/ND requieren `cta_imputacion_id`. Espejo cliente: `computeTotalesFactura` / `validarDesgloseFactura` (tests en `tests/compras-fiscal.test.js`).
- **Gotchas aprendidos:**
  - Las RPCs SIEMPRE devuelven `jsonb` (nunca `void`: el `db()` del frontend explota parseando la respuesta vacía).
  - Supabase otorga EXECUTE a `anon` por default privileges → toda función nueva lleva `REVOKE ... FROM anon` explícito.
  - Funciones con `SET search_path = public`.

## Arquitectura del frontend
- **Navegación:** sidebar de grupos + tabs por grupo. Página nueva = tocar TRES estructuras: `PAGE_TO_GROUP` (página→grupo), `GROUP_TABS` (tabs del grupo, soporta `sub:[]` para dropdowns), y `groupMods` dentro de `aplicarPermisos()`. El HTML de la página necesita `<div class="tabs"></div>` en su `.page-header` (showPage inyecta las tabs ahí). Sub-páginas además van en `PAGE_TO_PARENT`.
- **Datos:** `loadAll()` baja todo en un `Promise.all` con asignación por destructuring. Tabla nueva = agregar variable global, entrada AL FINAL del destructure y del array de GETs con `.catch(e=>_loadFail('Nombre',e))`, y fallback `||[]` en el catch de seguridad. Los errores de carga se muestran en el banner `#load-error-banner` (con botón Reintentar) — NO usar `.catch(()=>[])` silencioso.
- **Render:** `PAGE_RENDERS` mapea página → funciones de render. `renderAll()` marca todas las páginas sucias y renderiza SOLO la activa; `showPage()` renderiza una página sucia al entrar. Cada módulo: `renderModulo(filter='')` → stats en `#modulo-stats`, filtro por texto, tabla en `#modulo-tbody`. Página nueva → registrar sus renders en `PAGE_RENDERS`.
- **Estados:** `estadoSelect(tabla,id,actual,valores,badgeMap)` genera el select que PATCHea vía `cambiarEstado` genérico.
- **Save pattern:** validar → `setBusy(btnId,true)` → try { POST/PATCH o RPC + loadAll + closeModal + renderAll + notify } catch { notify err } finally setBusy false.
- **Escapado:** TODO dato de usuario interpolado en HTML pasa por `esc()`.
- **PDFs:** certificados se guardan base64 en la DB; `loadAll` NO baja `file_data` (se descarga on-demand en `openPDF`). Adjuntos ≤5MB. PDFs generados (presupuesto/remito/cert conformidad/NDP) usan jsPDF + doc.save().
- **Mobile (≤768px):** sidebar off-canvas con hamburguesa (`toggleMobileNav`), grids colapsan. Los overrides de estilos inline necesitan `!important` en la media query.
- **Digest:** `computeAlertas()` + panel "Para hoy" en el dashboard + badge en nav Métricas. Si un módulo nuevo tiene vencimientos/urgencias, sumarlos ahí.

## Módulos
Dashboard (KPIs + digest de alertas) · Materia prima (barras + reposición) · Productos terminados · Certificados MTC · Insumos · Herramientas · Órdenes de producción (tiempos por operación) · Compras (OCs, proveedores, recepciones, NDP) · Presupuestos (cotizador con costeo y margen, seguimiento, conversión) · Ventas (estilo Tango, remito PDF, cert de conformidad, OTD, botón Facturar→billing) · Clientes · Cta. corriente (aging FIFO) · Costos y rentabilidad · Trazabilidad (cert→barra→OP→PT→venta) · Contabilidad completa (plan de cuentas jerárquico, asientos, cobros y pagos, **cheques diferidos**, libro diario/mayor, balance comprobación, estado de resultados, balance general, ratios, bimonetario, ajuste por inflación RT 6, cierre/apertura, comparativos) · Configuración · Modo Planta (`planta.html` standalone: timers de producción desde el móvil vía QR por OP; usuario compartido `planta@vitalmetsa.com` con `usuarios.es_planta=true`, lockdown RLS RESTRICTIVE a ordenes_produccion/op_operaciones/op_time_entries + trigger solo-estado — migración 052. **Regla: toda tabla nueva con RLS necesita su policy `planta_lockdown`, las tres `contador_no_ins/upd/del` y el trigger `contador_guard`** (migración 053: Modo Contador — usuario `es_contador=true` en solo lectura total; los DO-loops de 052/053 son el molde)).

## Moneda
El core opera en **USD** (`fmtUSD()`). Excepciones: contabilidad bimonetaria y cheques (ARS o USD con tipo_cambio).

## Reglas de desarrollo
1. **Un cambio a la vez** — commit, deploy (push a main) y verificar entre cambios.
2. **SQL en Supabase ANTES del código** — pasar la migración para el SQL Editor, esperar el "listo", verificar, recién ahí pushear el frontend.
3. **empresa_id obligatorio** en todo POST (`currentEmpresa.id`).
4. **No usar parseFloat en campos de texto** (ej: `horas_total` es text).
5. **Columnas thead vs tbody deben coincidir.**
6. Página nueva → `PAGE_TO_GROUP` + `GROUP_TABS` + `groupMods` en `aplicarPermisos` + `<div class="tabs">`.
7. Tabla nueva → global + `loadAll` (al final, con `_loadFail`) + `renderAll`.
8. Mutaciones críticas (ventas, asientos, stock) → usar las RPCs atómicas, no POST/PATCH directo.
9. Validar antes de commitear: extraer el `<script>` grande y `node --check`, y correr `node --test tests/calculos.test.js`. Si se toca un cálculo de plata (cta cte, costeo, reposición), agregar/ajustar su test.
10. Texto de UI en español argentino (voseo).

## Estructura del archivo
```
index.html (~8.050 líneas)
├── <head> — fonts + libs CDN (líneas 10-14)
├── <style> (15-249) — CSS completo (mobile al final, ~216+)
├── <body>
│   ├── #loading-screen (~256)
│   ├── #auth-screen (~266) — login/register/join
│   ├── mobile-menu-btn + backdrop + #load-error-banner (~351)
│   ├── #app-screen (~356) — sidebar + pages (page-dash ... page-config)
│   ├── Modales
│   └── <script> (1841-fin) — toda la lógica
```

## Pendientes (deuda técnica de la auditoría 2026-06)
- [x] Errores de carga visibles (banner + Reintentar)
- [x] Headers CSP (netlify.toml)
- [x] Tests de cálculos de plata (`tests/calculos.test.js` — cta cte FIFO/aging, costeo PT, reposición; harness vm en `tests/_harness.js`)
- [x] Pase de `esc()` sobre renders viejos (104 interpolaciones; los contextos sin HTML — notify/confirm/textContent/DB/jsPDF — no se escapan)
- [ ] Partir index.html en módulos (script files clásicos) — solo cuando haya dolor real
- [x] Render solo de la página activa (PAGE_RENDERS + dirty-set en showPage)
- [ ] PDFs a Supabase Storage (hoy base64 en la DB)
- [ ] Decisión: permisos por módulo son solo visuales (REST accesible a todo usuario autenticado)
- [ ] Padrón AFIP (bloqueado por cert X.509; cuando esté: GET /padron/{cuit} en billing + botón "Buscar en AFIP")

### Logo
SVG embebido en base64 dentro del HTML (loading screen, auth, sidebar): 4 paralelogramos azules/grises + texto "VITALSTOCK". Favicon también SVG embebido.
