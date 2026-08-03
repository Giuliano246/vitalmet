# Facturas de compra: anulación, recepción integrada, doble fecha y alta de proveedor

**Fecha:** 2026-08-03 · **Origen:** feedback de Giuliano cargando las primeras facturas reales.

Diagnóstico previo (datos de prod): todas las facturas cargadas quedaron en
`estado_match='override'` con motivo "NS" y todas las OC tienen recibido $0 —
nadie usa el botón Recibir antes de facturar porque, según el proveedor, el
material y la factura llegan juntos. Además no existe forma de corregir o
anular una factura registrada, hay una sola fecha, y el alta rápida de
proveedor por CUIT (que ya existe en el modal sin OC) no está en el modal de
nueva OC.

## 1. Anular y corregir facturas

**RPC nueva `anular_factura_recibida(p_factura_id uuid, p_motivo text)`**
(migración 062, patrón `anular_venta`):

- Valida: factura existe y es de la empresa; motivo no vacío; si es tipo
  `factura`, que no tenga NC/ND con `factura_asociada_id` apuntándole
  (error: "Anulá primero la NC/ND asociada").
- Borra el asiento contable de la factura (`asientos` con
  `origen_tipo='factura_recibida'` y `origen_id=p_factura_id`) y sus líneas.
- Borra las filas de `factura_recibida_impuestos`.
- La OC no se toca: el estado del match vive en la factura (que desaparece)
  y las recepciones NO se revierten (el material entró igual).
- Borra la fila de `facturas_recibidas`. El `audit_log` (trigger existente)
  registra el DELETE con usuario; el motivo va en un UPDATE previo de
  `override_motivo = 'ANULADA: '||p_motivo` para que quede en el audit trail.
- jsonb de retorno `{ok:true, nro:...}`. SECURITY INVOKER, search_path
  public, REVOKE anon/PUBLIC, GRANT authenticated. Las policies RLS
  existentes (planta/contador) ya bloquean a quienes no deben.
- Cualquier usuario del módulo compras puede anular (quien se equivocó,
  corrige); el motivo es obligatorio y queda auditado.

**Frontend** — en la tabla de Facturas recibidas, por fila:

- Botón **Anular**: `prompt` de motivo → RPC → reload + notify.
- Botón **Corregir**: guarda en memoria los datos de la factura (cabecera +
  tax lines leídas de `factura_recibida_impuestos`), llama a la misma
  anulación (motivo automático "Corrección: se recarga") y reabre el modal
  correspondiente (con OC / sin OC / NC-ND según la factura) precargado con
  todos los campos e impuestos. El usuario ajusta y registra de nuevo.

## 2. Recepción integrada al facturar

En el modal de factura **con OC** (solo tipo `factura`), tilde nuevo:

> ☐ Recibí todo el material con esta factura (registra la recepción completa
> de la OC en este paso)

- Visible solo si la OC tiene pendientes de recepción (algún item con
  `cantidad_recibida < cantidad`).
- Al registrarse con el tilde activo, ANTES de llamar a
  `registrar_factura_recibida` se ejecuta la recepción completa reutilizando
  el flujo existente de `saveRecepcion` refactorizado: se extrae una función
  `registrarRecepcionOC(ocId, items, {fecha, certId, colada, remitoNro, obs})`
  que hoy vive inline en `saveRecepcion`, y ambos caminos la llaman. Para el
  tilde: items = todos los pendientes por la cantidad pendiente, fecha = la
  fecha contable de la factura, remito = nro de factura, obs = "Recepción
  registrada desde factura <nro>". Crea barras valuadas / suma insumos /
  alta herramientas + filas `recepciones_oc` + PATCH `cantidad_recibida` +
  estado OC + asiento GR-IR (`generarAsientoCompra`) + kardex (triggers).
- Después sigue el flujo normal: el match ahora encuentra recibido > 0 y
  cierra OK (mismos números de la OC).
- El preview del match (`frRecalc`) simula el escenario: con el tilde
  activo calcula el match como si la OC estuviera recibida completa, y el
  badge SIN RECEPCIONES desaparece.
- No es atómico entre recepción y factura (dos pasos, como el flujo manual);
  si la factura falla después de recibir, el material quedó recibido — igual
  que si el usuario hubiera usado Recibir y luego errado la factura. Se
  documenta en el manual.

## 3. Doble fecha: emisión y contable

- Migración 062: `facturas_recibidas.fecha_contable date` — backfill
  `fecha_contable = fecha` para las existentes, luego NOT NULL DEFAULT.
- El RPC `registrar_factura_recibida` (re-emisión, base 061) acepta
  `fecha_contable` en `p_factura`; el **asiento** se genera con
  `fecha_contable` (antes usaba `fecha`).
- Modal: "Fecha de emisión *" (la del comprobante) + "Fecha contable *"
  (default hoy) + "Vencimiento". Validación: contable >= emisión (warning,
  no bloquea — puede haber ajustes).
- Libro IVA Compras, Posición IVA y el detalle contable filtran/ordenan por
  `fecha_contable` (queries de las líneas 2746/2798/2812 + exportables). La
  fecha de emisión se sigue mostrando como dato del comprobante.
- La vista de vencimientos/cashflow sigue usando `fecha_vto`.

## 4. Alta rápida de proveedor en nueva OC

El modal de nueva OC suma el botón **+ CUIT** junto al selector de proveedor
(reutiliza `openProvRapidoModal` / `saveProvRapido` tal cual; al guardar,
además de seleccionarlo en el modal de factura sin OC, si el modal de OC está
abierto selecciona el proveedor ahí). Cambio mínimo: `saveProvRapido` debe
refrescar/seleccionar en el select correcto según qué modal lo invocó
(parámetro de contexto).

## Orden de implementación

1. Migración 062 (fecha_contable + RPC anular + re-emisión registrar con
   fecha_contable) → SQL en Supabase, verificar resultado de la corrida.
2. Frontend: fechas (3) → recepción integrada (2) → anular/corregir (1) →
   +CUIT en OC (4). Tests puros para lo testeable (validación de fechas,
   armado de items de recepción completa, precarga de corrección).
3. Manual de usuario (sección compras) + .docx.

## Fuera de alcance

- Editar in-place una factura registrada (la corrección es anular+recargar).
- Anular facturas con pagos aplicados: los pagos no referencian facturas
  (van por proveedor), así que no hay FK que bloquee; la cta cte se
  recalcula sola al desaparecer el asiento.
- Recepciones parciales desde el modal de factura (para eso está Recibir).
