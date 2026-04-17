# CLAUDE.md — VitalStock ERP

## Proyecto
VitalStock es un ERP single-file (HTML + Supabase) para Vitalmet SA, empresa metalúrgica argentina que fabrica productos para la industria petrolera (uniones, válvulas, anillos BX, codos, campanas, etc.).

**Owner:** Giuliano
**Empresa:** Vitalmet SA — Perú 246, Villa Martelli, Buenos Aires
**Web:** vitalmetsa.com
**ERP URL:** vitalmetstock.netlify.app (futuro: stock.vitalmetsa.com)

## Stack
- **Frontend:** HTML único (index.html), vanilla JS, CSS embebido
- **Backend/DB:** Supabase (auth + PostgreSQL)
- **Hosting:** Netlify (deploy vía GitHub)
- **Dominio:** Donweb (vitalmetsa.com / vitalmetsa.online)

## Supabase
- **URL:** `https://dqvlqhaxgvtilhiuatpv.supabase.co`
- **Anon Key:** está en el HTML (línea ~845)
- **RLS:** DESACTIVADO en todas las tablas (hubo problemas de recursión, pendiente de resolver)

## Tablas en Supabase
| Tabla | Descripción |
|-------|-------------|
| empresas | Multi-tenancy, código invitación |
| usuarios | Auth, empresa_id, es_admin, permisos |
| certificados | MTC con PDF adjunto, metros |
| barras | Materia prima (acero), stock en metros |
| ordenes_produccion | OPs, consumo de barras, horas (campo text) |
| productos_terminados | PT generado desde OPs |
| ventas | Pedidos/remitos expandido estilo Tango |
| venta_items | Ítems de venta con bonificación y moneda |
| materiales | Config de tipos de acero |
| tratamientos | Tratamientos térmicos vinculados a OPs |
| permisos_usuario | Permisos por módulo por usuario |
| clientes | Base de clientes auto-generada desde ventas |
| vendedores | Vendedores (tabla nueva, puede estar vacía) |
| listas_precios | Listas de precios (tabla nueva, puede estar vacía) |
| asientos_contables | Asientos contables vinculados a ventas (tabla nueva) |

## Módulos implementados
1. **Dashboard** — KPIs, gráficos de producción/ventas/clientes, rentabilidad por pieza
2. **Materia Prima** — CRUD barras de acero, stock en metros, alertas mínimo
3. **Productos Terminados** — CRUD PT, vinculado a barras y OPs
4. **Certificados MTC** — CRUD con PDF adjunto, campo metros
5. **Órdenes de Producción** — CRUD con consumo de barras, tratamientos, horas (texto libre), stats
6. **Ventas** — Modal expandido estilo Tango (razón social + CUIT autocomplete, coeficientes USD, fechas entrega, condiciones comerciales, vendedor, lista precios, bonificación, items con bonif)
7. **Clientes** — Auto-creados desde ventas, ficha con historial de compras, CRUD
8. **Trazabilidad** — Cadena certificado → barra → OP → PT → venta
9. **Configuración** — Materiales, usuarios, permisos por módulo, código invitación

## Moneda
Todo el sistema opera en **USD**. No hay pesos. La función de formato es `fmtUSD()`.

## Patrones de código

### CRUD helpers
```javascript
const GET   = (t,p) => db('GET',t,null,p);
const POST  = (t,b) => db('POST',t,b);
const PATCH = (t,b,p) => db('PATCH',t,b,p);
const DEL   = (t,p) => db('DELETE',t,null,p);
```

### Render pattern
Cada módulo tiene `renderModulo(filter='')` que:
1. Calcula stats y llena `#modulo-stats`
2. Filtra datos por texto
3. Genera HTML de la tabla en `#modulo-tbody`

### Save pattern
```javascript
async function saveModulo() {
  // Validar campos obligatorios
  // setBusy(btnId, true)
  // try { POST/PATCH + loadAll + closeModal + renderAll + notify }
  // catch { notify error }
  // setBusy(btnId, false)
}
```

### Autocomplete cliente en ventas
`onVentaClienteChange()` — al escribir razón social, autocompleta CUIT y lista de precios del cliente existente. Si es nuevo, se crea automáticamente al guardar la venta.

### Navegación
`showPage(p)` con map: `{dash:0, mp:1, pt:2, cert:3, op:4, ventas:5, clientes:6, trace:7, config:8}`
Si se agrega una página, actualizar TAMBIÉN `aplicarPermisos()` que tiene el mismo map.

### Session management
- Token refresh automático en `checkExistingSession()` y en `db()` (retry on 401)
- Loading screen mientras verifica sesión
- Sesión persistida en localStorage como `sb_session`

## Reglas de desarrollo

1. **Siempre preguntar antes de cambios grandes** — confirmar con Giuliano antes de modificar
2. **Un cambio a la vez** — deploy y testear entre cambios
3. **empresa_id obligatorio** en todo POST
4. **Columnas nuevas en Supabase ANTES del código** — proveer SQL para SQL Editor
5. **No usar parseFloat en campos de texto** (ej: horas_total es text)
6. **Verificar columnas thead vs tbody** — deben coincidir
7. **Actualizar renderAll()** al agregar nuevos renders
8. **Actualizar loadAll()** al agregar nuevas tablas
9. **Actualizar showPage map Y aplicarPermisos map** al agregar páginas

## Pendientes / Roadmap

### Corto plazo (mejoras al ERP actual)
- [ ] RLS en Supabase (falló por recursión infinita en policy de usuarios, está desactivado)
- [ ] Responsive/mobile (sidebar hamburguesa, tablas scroll horizontal)
- [ ] Protección doble clic en todos los saves (solo saveMP la tiene)
- [ ] Filtros por estado en OPs (tabs: Todos | En proceso | Completadas)
- [ ] Duplicar OP (botón que copie datos a nueva OP)
- [ ] Remito PDF para imprimir
- [ ] Paginación en tablas
- [ ] Módulo de compras (OC a proveedores)

### Mediano plazo (comercialización)
- [ ] Migración a React + Node.js (necesario para módulo contable y AFIP)
- [ ] Módulo de costos y rentabilidad
- [ ] Módulo contable (plan de cuentas, asientos, libro diario/mayor)
- [ ] Facturación electrónica AFIP (requiere backend con WSFE)
- [ ] Landing page para vender VitalStock como producto

### Logo
El logo es SVG embebido en base64 dentro del HTML (loading screen, auth, sidebar). Son los 4 paralelogramos azules/grises + texto "VITALSTOCK". Favicon también embebido como SVG.

## Estructura del archivo
```
index.html (~2500 líneas)
├── <style> (líneas 8-157) — CSS completo
├── <body>
│   ├── #loading-screen (línea ~164)
│   ├── #auth-screen (línea ~175) — login/register/join
│   ├── #app-screen (línea ~264)
│   │   ├── sidebar (nav + user)
│   │   └── main (pages)
│   │       ├── page-dash
│   │       ├── page-mp
│   │       ├── page-pt
│   │       ├── page-cert
│   │       ├── page-op
│   │       ├── page-ventas
│   │       ├── page-clientes
│   │       ├── page-trace
│   │       └── page-config
│   ├── Modales (líneas ~440-850)
│   └── <script> (líneas ~845-fin) — toda la lógica JS
```
