# PG-04 — Compras y evaluación de proveedores (AVL)

| Campo | Valor |
|---|---|
| **Código** | PG-04 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.4 (Control de los procesos, productos y servicios suministrados externamente) · API Q1 §5.6 (Compras; §5.6.1.2 evaluación y selección de proveedores) |

## 1. Propósito

Establecer la metodología para evaluar, aprobar y reevaluar a los proveedores de Vitalmet S.A. (lista de proveedores aprobados — AVL), y para emitir y controlar las órdenes de compra, asegurando que los materiales, productos y servicios provistos externamente — en particular la materia prima crítica (AISI 4130 Q&T, API 5L) y los procesos tercerizados críticos (tratamiento térmico, calibración) — se adquieran exclusivamente de proveedores aprobados y vigentes.

## 2. Alcance

Aplica a todas las compras de la empresa registradas en el módulo **Compras** del ERP (tablas `ordenes_compra`, `oc_items`, `proveedores`): materia prima, insumos, herramientas y servicios tercerizados. El grado de control es proporcional al efecto del suministro sobre la conformidad del producto, según la `criticidad` asignada a cada proveedor.

La verificación del producto comprado (recepción e inspección de entrada) se rige por PG-05. La ejecución del tratamiento térmico tercerizado dentro de la orden de producción se rige por PG-06 §6.5.

## 3. Referencias

- ISO 9001:2015, §8.4 — Control de los procesos, productos y servicios suministrados externamente.
- API Specification Q1, 9ª edición — §5.6 Compras (§5.6.1.2 evaluación inicial y selección de proveedores).
- MC-01 — Manual de Calidad (proceso Operativo 3 del mapa de procesos; objetivo de calidad n.º 3).
- PG-05 — Recepción e inspección de entrada.
- PG-06 — Control de producción y PQP (tratamiento térmico tercerizado).
- PG-08 — Control de equipos de medición (calibración externa).
- PG-09 / PG-10 — Producto no conforme y CAPA (no conformidades atribuibles a proveedores).
- Migración `038_avl_proveedores.sql` del ERP (implementación de la AVL y su gate).

## 4. Definiciones

- **AVL** (Approved Vendor List): lista de proveedores aprobados; en el ERP se materializa en los campos de aprobación de la tabla `proveedores` (`aprobado`, `alcance_aprobacion`, `criticidad`, `fecha_evaluacion`, `fecha_proxima_evaluacion`).
- **Proveedor crítico**: proveedor cuyo suministro afecta directamente la conformidad del producto de alta presión (`proveedores.criticidad` = 'critico'): materia prima para producto crítico, tratamiento térmico (Q&T / PWHT), calibración de instrumentos.
- **Alcance de la aprobación**: qué está aprobado a comprarle al proveedor (`alcance_aprobacion`; por ejemplo «materia prima AISI 4130 / tratamiento térmico»). No se compra fuera del alcance aprobado.
- **Gate AVL**: control automático del sistema (trigger `fn_oc_avl_gate`) que bloquea la emisión de órdenes de compra en infracción a la AVL.
- **OC**: orden de compra (`ordenes_compra` + `oc_items`).
- **NDP**: nota de pedido; documento PDF de la OC que se envía al proveedor.

## 5. Responsabilidades

- **Dirección**: aprueba la incorporación de proveedores críticos a la AVL y la baja de proveedores; resuelve las compras de excepción.
- **Responsable de Calidad**: define los criterios de evaluación según la criticidad; participa en la evaluación y reevaluación de proveedores críticos; analiza las no conformidades atribuibles a proveedores y su efecto sobre la aprobación.
- **Responsable de Compras/Administración**: mantiene el maestro de proveedores y sus datos AVL en el ERP; emite las OC exclusivamente a proveedores aprobados y con alcance acorde; ejecuta las reevaluaciones en fecha; registra las facturas recibidas contra la OC.
- **Responsable de Producción**: informa el desempeño operativo de los proveedores (calidad recibida, cumplimiento de plazos) como insumo de la reevaluación.

## 6. Desarrollo

### 6.1 Alta, evaluación inicial y aprobación de proveedores

1. Todo proveedor se registra en el módulo Compras → Proveedores del ERP (tabla `proveedores`), con sus datos de identificación (razón social, CUIT, contacto) y sus **datos AVL**: `criticidad` ('critico' | 'no_critico' — el sistema restringe los valores), estado de aprobación (`aprobado`), `alcance_aprobacion`, `fecha_evaluacion` y `fecha_proxima_evaluacion`. Estos campos se cargan desde el modal de proveedor (Criticidad, Estado AVL, Alcance de la aprobación, Fecha de evaluación, Próxima reevaluación).
2. La criticidad se asigna según el efecto del suministro sobre la conformidad del producto: son **críticos**, como mínimo, los proveedores de materia prima para producto de alta presión, de tratamiento térmico (Q&T / PWHT) y de calibración de instrumentos. El resto se clasifica 'no_critico'.
3. La **evaluación inicial** de un proveedor crítico comprende, según aplique: certificaciones del proveedor (ISO 9001, acreditación del laboratorio de calibración), capacidad de emitir los certificados requeridos (MTR con colada, certificado de tratamiento térmico con ciclo y durezas, certificado de calibración con trazabilidad), muestras o primer suministro verificado en inspección de entrada (PG-05), antecedentes y referencias. Para proveedores no críticos basta la verificación comercial y el historial de suministro.
4. El resultado de la evaluación se asienta en el ERP: `aprobado` = verdadero, `alcance_aprobacion` describiendo qué se le aprueba comprar, `fecha_evaluacion` del día y `fecha_proxima_evaluacion` a un año como máximo. La evidencia de respaldo (certificados del proveedor, informe de evaluación) se archiva en la carpeta de calidad.
5. **Homologación inicial por historial**: al implantar la AVL, los proveedores activos existentes quedaron aprobados en bloque con alcance «Homologación inicial por historial de suministro» y reevaluación a un año (backfill de la migración 038). Esta homologación es transitoria: en la **primera reevaluación** de cada uno de estos proveedores se completa la evaluación formal del punto 3 y se regulariza su alcance.

### 6.2 Reevaluación y pérdida de la aprobación

6. Los proveedores aprobados se reevalúan como máximo **anualmente** (`fecha_proxima_evaluacion`), considerando: no conformidades de entrada atribuidas al proveedor (PG-05/PG-09), cumplimiento de plazos de entrega, completitud y validez de los certificados entregados, y desempeño comercial. El resultado actualiza `fecha_evaluacion` y `fecha_proxima_evaluacion`.
7. El ERP asiste el cumplimiento: el listado de Proveedores señala la reevaluación vencida y la criticidad (badge «Crítico»), y el panel «Para hoy» del dashboard alerta los proveedores aprobados con `fecha_proxima_evaluacion` vencida. El objetivo de calidad n.º 3 de MC-01 (100 % de proveedores críticos evaluados y vigentes) se mide sobre estos campos.
8. Un proveedor pierde la aprobación (`aprobado` = falso) por decisión de la Dirección ante no conformidades graves o reiteradas, o por no superar la reevaluación. La reevaluación vencida produce el mismo efecto práctico: el gate AVL bloquea sus OC críticas (ver 6.4).

### 6.3 Emisión de la orden de compra

9. Toda compra se instrumenta con una OC del ERP (`ordenes_compra`), con numeración propia, proveedor, `fecha`, `fecha_entrega_esperada`, moneda y tipo de cambio cuando corresponde. Los ítems se cargan en `oc_items` con `tipo` ('materia_prima' | 'insumo' | 'herramienta'), descripción, material, perfil, diámetro, cantidad, unidad y precio.
10. La información de compra debe describir sin ambigüedad el requisito: para materia prima crítica, la OC especifica el material y su condición (por ejemplo «AISI 4130 forjado Q&T»), la norma aplicable y la exigencia de **certificado de material (MTR) con número de colada**; para tratamiento térmico, el ciclo requerido y el certificado a entregar; para calibración, la trazabilidad patrón requerida (PG-08). Los documentos técnicos que se adjunten a la OC deben ser revisiones vigentes (PG-01).
11. La OC transita los estados `ordenes_compra.estado`: 'borrador' → 'enviada' → 'confirmada' → 'recibida_parcial' / 'recibida' → 'facturada' (o 'anulada'). La OC se envía al proveedor como **NDP en PDF** generada por el ERP.

### 6.4 Gate AVL: bloqueo de OC a proveedores no aprobados

12. Al sacar una OC del estado 'borrador' (pasarla a 'enviada' o crearla directamente en un estado operativo), el sistema ejecuta el **gate AVL** (trigger `trg_oc_avl_gate`, función `fn_oc_avl_gate`): si la OC contiene ítems de tipo 'materia_prima' **o** el proveedor es de criticidad 'critico', el sistema verifica que el proveedor esté aprobado y que su reevaluación no esté vencida.
13. Si el proveedor no está aprobado, la OC se rechaza con el mensaje «AVL: el proveedor no está aprobado para material/servicio crítico»; si la reevaluación está vencida (`fecha_proxima_evaluacion` anterior a la fecha del día), se rechaza indicando la fecha de vencimiento. En ambos casos la emisión queda **bloqueada por el sistema** hasta evaluar/reevaluar y aprobar al proveedor en el módulo Proveedores. No existe mecanismo de override: la excepción solo procede regularizando la evaluación.
14. Las compras no críticas (ítems 'insumo'/'herramienta' a proveedores 'no_critico') no son bloqueadas por el gate, sin perjuicio del alta del proveedor en el maestro y de su verificación comercial.

### 6.5 Recepción, factura y cierre de la OC

15. La recepción física y la inspección de entrada de lo comprado se ejecutan conforme a **PG-05** (modal «Recibir» de la OC, tabla `recepciones_oc`, cuarentena y liberación). El propio flujo de recepción actualiza `oc_items.cantidad_recibida` y el estado de la OC ('recibida_parcial' / 'recibida').
16. La factura del proveedor se registra contra la OC (`facturas_recibidas`, botón «Factura» de la OC); el ERP aplica los controles de correspondencia entre lo pedido, lo recibido y lo facturado (conciliación GR-IR) según los controles contables vigentes. La OC facturada pasa a 'facturada'.
17. Las no conformidades detectadas en la recepción o en el uso del suministro se registran en `no_conformidades` (PG-09) identificando al proveedor, y alimentan su reevaluación (punto 6).

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Maestro de proveedores con datos AVL (aprobación, alcance, criticidad, evaluaciones) | `proveedores` (Compras → Proveedores) | 10 años |
| Evidencia de evaluación/reevaluación de proveedores críticos | Carpeta de calidad (fuera del ERP) | 10 años |
| Órdenes de compra y sus ítems | `ordenes_compra` / `oc_items` (Compras) | 10 años |
| NDP (PDF de la OC enviada al proveedor) | Generada por el ERP (jsPDF); copia en el legajo de compras | 10 años |
| Recepciones contra OC | `recepciones_oc` (ver PG-05) | 10 años |
| Facturas recibidas vinculadas a OC | `facturas_recibidas` (Compras → Facturas) | 10 años |
| Historia de cambios de proveedores y OC (incl. bloqueos del gate) | `audit_log` | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
