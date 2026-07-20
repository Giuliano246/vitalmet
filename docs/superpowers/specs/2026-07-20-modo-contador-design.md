# VitalStock — Modo Contador

**Fecha:** 2026-07-20
**Estado:** Diseño aprobado, pendiente de implementación
**Precedente interno:** Modo Planta (migración `052_modo_planta.sql`) — mismo patrón de flag + lockdown RESTRICTIVE.

## Objetivo

Que el contador del estudio entre a VitalStock con su propio login, en solo
lectura garantizada por la base, y se lleve la información contable del
período sin pedirle nada a nadie: subdiarios, IVA, mayores, plan de cuentas
y una carpeta mensual descargable. Se termina el "pasame lo del mes":
el contador entra y se sirve.

## Decisiones tomadas

| Decisión | Elección |
|---|---|
| Modelo | Flag `es_contador` en `usuarios` (calco del patrón `es_planta`) — sin tablas nuevas |
| Visibilidad de módulos | Configurable por el admin con los permisos por módulo existentes; al marcar "Contador" se sugieren activados `ver_costos` + módulos Contabilidad, Ventas y Compras |
| Alta | El contador se auto-registra con el código de invitación (flujo "Unirse" existente); el admin lo marca "Contador" en Configuración → Usuarios, en el modal de permisos de siempre. Cero SQL. |
| Solo lectura | Garantizada por policies RESTRICTIVE en la DB; el ocultamiento de botones en UI es cosmético |
| Exportables | Página nueva "Exportables" en el grupo Contabilidad, visible para contador y admin |
| Formato de exports | CSV/Excel genéricos (UTF-8 con BOM, `;`, coma decimal, DD/MM/AAAA); el formato Libro IVA Digital de ARCA queda para después de validarlo con el contador real |

Enfoques descartados: página standalone tipo `planta.html` (el contador
necesita toda la UI de lectura de contabilidad, no una UI mínima) y
solo-visual sin policies (los permisos por módulo son cosméticos y el REST
queda abierto — inaceptable para un usuario externo).

## Migración `053_modo_contador.sql`

SQL en el Editor ANTES del código (regla del repo). Convenciones:
BEGIN/COMMIT, idempotente, funciones con `SECURITY DEFINER` +
`SET search_path = public` + `REVOKE FROM anon/PUBLIC`, verificación
comentada al pie.

1. **Columna:** `usuarios.es_contador boolean NOT NULL DEFAULT false`
   (`ADD COLUMN IF NOT EXISTS`).
2. **Función `es_contador() → boolean`** — calco exacto de `es_planta()`
   (052:20-31): `COALESCE((SELECT u.es_contador FROM usuarios u WHERE
   u.id = auth.uid()), false)`.
3. **Solo lectura:** DO-loop sobre todas las tablas de `pg_tables` con
   `rowsecurity = true` creando TRES policies RESTRICTIVE por comando:
   - `contador_no_ins` — `AS RESTRICTIVE FOR INSERT WITH CHECK (NOT es_contador())`
   - `contador_no_upd` — `AS RESTRICTIVE FOR UPDATE USING (NOT es_contador())`
   - `contador_no_del` — `AS RESTRICTIVE FOR DELETE USING (NOT es_contador())`

   Por comando y no `FOR ALL`, para no tocar el SELECT. **Sin lista de
   exclusión**: el contador no escribe en ninguna tabla, ni en `usuarios`
   (su fila se crea al registrarse, antes de ser marcado). A diferencia de
   `planta_lockdown`, acá no hay whitelist de tablas de OPs.
4. **Guard:** extender `usuarios_guard()` (052:79-111) para que
   `es_contador` reciba el mismo tratamiento que `es_admin` / `ver_costos` /
   `es_planta`: solo un admin lo cambia; en INSERT se fuerza a `false`;
   si `auth.uid() IS NULL` (SQL Editor / service_role) confía.
5. **RPCs de escritura — el bypass a cerrar con triggers:** las RPCs
   atómicas de la migración 023 (`guardar_venta`, `anular_venta`,
   `crear_asiento`, `consumir_barra`, `upsert_cliente`) y cualquier otra
   función `SECURITY DEFINER` que escriba **bypassean el RLS**: un contador
   podría escribir llamándolas por REST directo aunque las policies lo
   bloqueen. En lugar de auditar y editar cada RPC (frágil: cualquier RPC
   futura reabre el agujero), la 053 crea una función de trigger
   `fn_contador_guard()` que hace `RAISE EXCEPTION 'Modo contador: solo
   lectura'` si `es_contador()`, y el mismo DO-loop de las policies le
   cuelga a cada tabla un trigger
   `contador_guard BEFORE INSERT OR UPDATE OR DELETE … FOR EACH STATEMENT`.
   Los triggers se disparan también dentro de funciones SECURITY DEFINER,
   así que cubren todas las RPCs presentes y futuras sin tocarles el
   cuerpo. Costo: una llamada barata por statement de escritura.
   Las policies RESTRICTIVE del punto 3 se mantienen igual (defensa en
   profundidad y 403 limpio en el REST directo).
6. **Regla nueva para el CLAUDE.md del repo:** toda tabla nueva con RLS
   necesita `planta_lockdown`, las tres `contador_no_ins/upd/del` **y** el
   trigger `contador_guard`.

## Frontend (`index.html`)

### Modo solo-lectura

- Al bootear, si `currentUserData.es_contador` → `window._modoContador = true`,
  clase `modo-contador` en `<body>`, banner persistente
  "Modo contador — solo lectura".
- **Guard en `db()`** (único choke point REST, index:2321-2333): si
  `_modoContador` y el método no es GET → `throw` con mensaje claro antes
  del fetch. Sin excepciones (no hay RPCs que el contador necesite).
  Cosmético a propósito: la garantía es el RLS.
- Configuración ya queda oculta porque el contador no es admin
  (`aplicarPermisos` la oculta para todo no-admin — sin cambios).
- La visibilidad de módulos usa `permisos_usuario` sin cambios: el
  contador es un no-admin más a ojos del sistema de navegación.

### Lado del admin (Configuración → Usuarios)

En el modal de permisos existente (`openPermisos`/`savePermisos`,
index:7240-7255), tilde nuevo **"Contador (solo lectura)"** que PATCHea
`usuarios.es_contador`. Al tildarlo, la UI sugiere (pre-tilda, editable
antes de guardar) `ver_costos` y los módulos Contabilidad, Ventas y
Compras. La lista de usuarios (`renderUsuarios`, index:7208) muestra el
badge CONTADOR junto a ADMIN/EMPLEADO.

## Página "Exportables"

Grupo Contabilidad. Página nueva = tocar las TRES estructuras
(`PAGE_TO_GROUP`, `GROUP_TABS`, `groupMods` en `aplicarPermisos`) +
`<div class="tabs"></div>` en el `.page-header` + registrar renders en
`PAGE_RENDERS` (reglas 6 del CLAUDE.md). Visible para contador y admin;
para empleados según permiso de módulo Contabilidad.

Selector de período (mes por defecto, rango libre) y seis exports,
100% client-side desde PostgREST, sin librerías nuevas:

| Export | Fuente | Contenido |
|---|---|---|
| Subdiario de ventas | `ventas` | Remitos/pedidos del período: nro, cliente, fecha, condición, total, estado |
| IVA ventas | `facturas_emitidas` | Comprobantes fiscales: tipo, punto de venta, número, fecha, doc/CUIT, neto, IVA, total, CAE |
| Subdiario de compras | `facturas_recibidas` + `proveedores` | Facturas de compra: proveedor, CUIT, nro, fecha, vto, neto, IVA, total |
| IVA compras | `facturas_recibidas` + `proveedores` | Mismas fuentes, columnas de libro IVA |
| Mayores | `asientos` + `asiento_lineas` + `cuentas_contables` | Todos los movimientos del período ordenados por cuenta y fecha, con saldo acumulado por cuenta |
| Plan de cuentas | `cuentas_contables` | Código, nombre, tipo, imputable, activa |

- **Formato:** CSV UTF-8 con BOM (U+FEFF), separador `;`, números con coma
  decimal, fechas DD/MM/AAAA, CRLF — Excel en configuración regional
  argentina los abre sin pelear.
- Formateadores y builders como funciones puras testeables con node.
- Los mayores pagan queries por chunks de ids de asiento (PostgREST `in.()`
  con límite práctico) si el período es grande.

## Carpeta del período

Botón "Descargar carpeta" → `VitalStock_<AAAA-MM>.zip` con los 6 CSVs +
`resumen.txt` (totales del período, fecha de generación). ZIP en formato
*store* (sin compresión) generado a mano: local file headers + central
directory + CRC32, cero dependencias — no toca el CSP de `netlify.toml`.

## Errores y casos borde

- Período sin datos → export igual con solo encabezados; el resumen lo
  aclara.
- Contador intenta escribir (por UI residual o REST directo) → el guard de
  `db()` corta con mensaje claro; si lo saltea, la policy RESTRICTIVE
  rechaza (403).
- Admin se marca a sí mismo como contador → la UI lo impide (no tildar
  sobre el propio usuario admin); `usuarios_guard` permite el caso pero la
  UI no lo ofrece, para no dejarse afuera.
- Destildar "Contador" → el usuario vuelve a ser empleado normal en el
  próximo login (el flag se lee al bootear).
- Todo dato renderizado pasa por `esc()`, como siempre.

## Tests

- Port de los tests de utilidades: rango de período (bisiestos), campo y
  armado CSV (BOM + `;` + CRLF), número con coma decimal, fecha DD/MM/AAAA,
  CRC32 (vector conocido `'abc'` = 0x352441C2), firmas y offsets del ZIP.
- El harness (`tests/_harness.js`) necesita sumar `TextEncoder`,
  `TextDecoder`, `Uint8Array`, `DataView` a los globals del sandbox.
- `node --check` del script extraído + suite existente sigue verde.

## Verificación

1. Migración 053 en el SQL Editor + verificación al pie (columna, función,
   conteo de policies `contador_no_*` = 3 × tablas con RLS, guard).
2. Suite node verde + `node --check`.
3. Smoke REST: con el JWT de un usuario contador, INSERT/UPDATE/DELETE
   rechazados en tablas de negocio; llamada directa a una RPC de escritura
   (`/rest/v1/rpc/crear_asiento`) devuelve el error de solo lectura;
   SELECT funciona.
4. E2E en producción: registro con código de invitación → admin marca
   "Contador" → re-login → banner + solo lectura (intento de escritura por
   REST directo rebota) → 6 exports correctos con datos reales → ZIP abre
   en Excel/descompresor → destildar y verificar que vuelve a empleado.
5. Modo Planta y la operación normal siguen intactos (el DO-loop no toca
   policies existentes).

## Fuera de alcance

- Multi-empresa, selector de clientes, códigos de invitación dedicados
  para contadores.
- Formato Libro IVA Digital de ARCA — después de validar los CSV genéricos
  con el contador del estudio (esta feature habilita justamente esa
  validación con la primera carpeta real).
- Bandeja de comprobantes y calendario de vencimientos.
- Notificaciones al contador por cierre de período.
