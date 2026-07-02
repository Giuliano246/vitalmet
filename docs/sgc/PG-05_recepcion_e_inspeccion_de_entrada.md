# PG-05 — Recepción e inspección de entrada

| Campo | Valor |
|---|---|
| **Código** | PG-05 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.4.3 y §8.6 (aplicada a la entrada) · API Q1 §5.7.4 (Verificación de producto comprado) |

## 1. Propósito

Establecer la metodología para recibir e inspeccionar los productos comprados antes de su uso, mediante un régimen de **cuarentena**: todo material recibido queda retenido hasta que la inspección de entrada lo acepta, y la materia prima crítica no se libera sin su certificado de material (MTR). El objetivo es que ningún material no verificado ingrese a producción.

## 2. Alcance

Aplica a todas las recepciones contra órdenes de compra registradas en el ERP (tabla `recepciones_oc`): materia prima (barras — acero AISI 4130 Q&T, API 5L), insumos y herramientas. El control es pleno para la materia prima, cuyo estado de calidad se administra pieza a pieza en `barras.estado_calidad`.

La verificación de los certificados de tratamiento térmico tercerizado dentro de la OP se rige por PG-06 §6.5. La disposición del material rechazado se rige por PG-09 (producto no conforme).

## 3. Referencias

- ISO 9001:2015, §8.4.3 — Información para los proveedores externos; §8.6 — Liberación de los productos y servicios.
- API Specification Q1, 9ª edición — §5.7.4 Verificación de producto comprado.
- MC-01 — Manual de Calidad (proceso Operativo 4 del mapa de procesos).
- PG-04 — Compras y evaluación de proveedores (AVL).
- PG-06 — Control de producción y PQP (consumo de barras en OP).
- PG-07 — Identificación y trazabilidad (colada).
- PG-09 — Control de producto no conforme.
- Migración `039_inspeccion_entrada.sql` del ERP (implementación de la cuarentena y sus gates).

## 4. Definiciones

- **Recepción**: registro en `recepciones_oc` del ingreso físico de un ítem de OC, con fecha, cantidad, remito del proveedor y certificado vinculado.
- **Cuarentena**: estado inicial de toda recepción (`recepciones_oc.estado_inspeccion` = 'cuarentena') y de la barra creada desde ella (`barras.estado_calidad` = 'cuarentena'); el material en cuarentena no es utilizable en producción.
- **MTR** (Material Test Report): certificado de calidad del material con número de colada, registrado en la tabla `certificados` (módulo Certificados MTC).
- **Barra**: unidad de stock de materia prima (tabla `barras`), identificada por `lote` y `nro_colada`, vinculada a su `certificado_id`, `proveedor_id` y `oc_id`.
- **Liberación**: aceptación de la recepción ('aceptado'), que habilita el uso del material en producción.

## 5. Responsabilidades

- **Responsable de Compras/Administración**: registra las recepciones en el ERP contra la OC (fecha, remito, cantidades, certificado); custodia los remitos; no libera material.
- **Responsable de Calidad**: ejecuta la inspección de entrada y decide la aceptación o el rechazo de cada recepción (pestaña Inspección de entrada); verifica el MTR contra el requisito de compra; abre la no conformidad ante rechazo. Conforme a MC-01 §5, mantiene independencia de Producción para esta decisión.
- **Responsable de Producción**: no utiliza material en cuarentena o rechazado; segrega físicamente el material retenido; informa cualquier defecto detectado en el uso posterior.
- **Dirección**: resuelve las disposiciones de material rechazado de valor significativo (devolución, concesión con el cliente cuando aplique, descarte).

## 6. Desarrollo

### 6.1 Registro de la recepción (cuarentena automática)

1. Todo ingreso de material comprado se registra desde la OC (módulo Compras, botón «Recibir»), que abre el modal de recepción precargado con el remito y el certificado ya asociados a la OC, si los hubiera. Se registran: `fecha`, `remito_nro` del proveedor, el **certificado MTR** seleccionado del módulo Certificados MTC (`certificado_id`) — cuya `colada` se autocompleta y puede corregirse — y la cantidad recibida de cada ítem.
2. Por cada ítem recibido, el ERP crea el registro en `recepciones_oc` (`oc_item_id`, `fecha`, `cantidad_recibida`, `certificado_id`, `barra_id`, `remito_nro`, `observaciones`) y actualiza `oc_items.cantidad_recibida` y el estado de la OC ('recibida_parcial' o 'recibida').
3. Si el ítem es **materia prima**, el sistema crea automáticamente la barra en stock (`barras`) con `lote` autogenerado a partir del número de OC, material, perfil, diámetro, kg o unidades, `nro_colada`, `certificado_id`, `proveedor_id` y `oc_id` — la cadena de trazabilidad de PG-07 nace en este acto. Si es insumo, suma al stock de `insumos`; si es herramienta, se da de alta individualmente en `herramientas`.
4. Toda recepción nace en estado **'cuarentena'** (default de `recepciones_oc.estado_inspeccion`), y la barra vinculada hereda ese estado: el trigger `fn_recepcion_sync_barra` sincroniza `barras.estado_calidad` con el estado de inspección de su recepción. El material físico se identifica y segrega en la zona de cuarentena hasta la decisión de la inspección.
5. La **materia prima crítica ingresa exclusivamente por recepción de OC**. El alta manual de barras (reservada a stock histórico o regularizaciones) nace 'aceptado' por diseño del sistema y elude la cuarentena, por lo que queda prohibida para material nuevo comprado; toda alta manual de barras debe estar justificada y autorizada por el Responsable de Calidad.

### 6.2 Inspección de entrada

6. La inspección se gestiona en la pestaña **Compras → Inspección de entrada** del ERP, que lista las recepciones con las de cuarentena primero, muestra los contadores «En cuarentena» y «Rechazadas», y señala con badge «SIN MTR» la materia prima recibida sin certificado vinculado. El panel «Para hoy» del dashboard alerta las recepciones en cuarentena pendientes de inspección.
7. El Responsable de Calidad inspecciona cada recepción verificando, según el tipo de material:
   - **Correspondencia documental**: remito contra OC (ítem, cantidad, material, perfil, diámetro).
   - **MTR** (materia prima): que el certificado corresponda al material recibido; número de colada legible y coincidente con el marcado del material; composición química y propiedades mecánicas dentro de la especificación de compra (AISI 4130 Q&T / API 5L); condición de tratamiento térmico declarada; cumplimiento NACE MR-0175 cuando el uso previsto es servicio sour.
   - **Condición física**: estado superficial, ausencia de daños de transporte, dimensiones principales.
   - **Identificación**: marcado de colada/lote sobre el material, consistente con el MTR.
8. Los instrumentos utilizados en verificaciones dimensionales de entrada deben tener calibración vigente (PG-08).

### 6.3 Decisión: aceptación o rechazo

9. **Aceptación**: el botón «Aceptar» de la pestaña Inspección pasa la recepción a 'aceptado'. El sistema aplica dos controles automáticos (trigger `fn_recepcion_inspeccion`):
   - **MTR obligatorio**: no permite aceptar materia prima sin certificado de material vinculado a la recepción o a su OC («no se puede aceptar materia prima sin el certificado de material (MTR) adjunto»).
   - **Firma de la inspección**: estampa automáticamente quién inspeccionó (`inspeccionado_por`, del usuario autenticado) y cuándo (`fecha_inspeccion`).
   La barra vinculada pasa a `estado_calidad` = 'aceptado' (trigger `fn_recepcion_sync_barra`) y queda liberada para producción.
10. **Rechazo**: el botón «Rechazar» pasa la recepción a 'rechazado', con la misma estampa de firma; la barra vinculada queda bloqueada ('rechazado'). El Responsable de Calidad abre la no conformidad en Calidad → NCR (`no_conformidades`, PG-09) identificando proveedor, OC, material y motivo; el material se segrega e identifica como rechazado hasta su disposición (devolución al proveedor, descarte). El rechazo alimenta la reevaluación del proveedor (PG-04 §6.2).
11. La decisión de aceptación/rechazo es exclusiva del Responsable de Calidad (o de quien la Dirección designe con la misma independencia). El registro de quién inspeccionó queda asentado por el sistema y es auditable en `audit_log`.

### 6.4 Gate de consumo: el material no aceptado no entra a producción

12. El control de fondo es de sistema: la función `consumir_barra()` — única vía de descuento de materia prima al asignarla a una orden de producción — **rechaza el consumo de toda barra cuyo `estado_calidad` no sea 'aceptado'**, con el mensaje «la barra está en cuarentena/rechazado — requiere inspección de entrada aceptada antes de usarse en producción». La devolución de kg (edición de OP) y la consulta de stock siguen permitidas para no bloquear correcciones.
13. Complementariamente, el listado de Materia prima muestra el estado de cada barra con los badges «CUARENTENA» y «RECHAZADO», de modo que la retención es visible en el punto de uso.
14. No existe liberación por urgencia ni uso condicional de material en cuarentena: la única vía de liberación es la aceptación de la inspección de entrada. Si un material aceptado resulta luego no conforme, se trata según PG-09 (incluida la evaluación del producto ya fabricado con esa colada, vía trazabilidad de PG-07).

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Recepciones con su estado de inspección, inspector y fecha | `recepciones_oc` (`estado_inspeccion`, `inspeccionado_por`, `fecha_inspeccion`) — Compras → Inspección de entrada | 10 años (protegidas por `fn_proteger_evidencia`) |
| Certificados de material (MTR) | `certificados` (Inventario → Certificados MTC), PDF adjunto en `file_data` | 10 años (protegidos por `fn_proteger_evidencia`) |
| Estado de calidad de la materia prima | `barras.estado_calidad` (+ `lote`, `nro_colada`, `certificado_id`, `proveedor_id`, `oc_id`) | 10 años |
| Remitos del proveedor | `recepciones_oc.remito_nro` + remito físico en el legajo de compras | 10 años |
| No conformidades de entrada | `no_conformidades` (Calidad → NCR; PG-09) | 10 años |
| Historia de cambios (recepciones, barras, decisiones de inspección) | `audit_log` | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
