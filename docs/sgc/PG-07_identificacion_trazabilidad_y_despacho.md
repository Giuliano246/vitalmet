# PG-07 — Identificación, trazabilidad y despacho

| Campo | Valor |
|---|---|
| **Código** | PG-07 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.5.2 (identificación y trazabilidad) y §8.6 (liberación de productos) · API Q1 §5.7.6 (identificación y trazabilidad) y §4.5 (registros) |

## 1. Propósito

Establecer la metodología para identificar el producto en todas sus etapas y mantener la trazabilidad completa por número de colada (heat number) — desde el certificado de material (MTR) hasta el cliente final, y a la inversa —, y para ejecutar el despacho del producto terminado con su remito y su certificado de conformidad, asegurando que solo se entregue producto liberado y que cada entrega sea reconstruible ante un reclamo, un recall o un requerimiento del cliente o de un organismo.

## 2. Alcance

Aplica a todos los productos fabricados por Vitalmet S.A. (uniones figura 1502, pup joints, couplings y uniones dobles), desde el ingreso de la materia prima con su MTR hasta la entrega al cliente, incluyendo:

- La identificación del material y del producto en cada etapa (certificado, barra, orden de producción, lote de producto terminado).
- La propagación y el mantenimiento del número de colada a lo largo de la cadena.
- La inclusión de los tratamientos térmicos tercerizados en la cadena de trazabilidad.
- La consulta de trazabilidad directa (colada → cliente) e inversa (venta → colada).
- El despacho: remito, certificado de conformidad y registro de la fecha real de entrega.

No aplica a la liberación de materia prima en recepción (procedimiento de inspección de entrada del SGC) ni a la ejecución de los puntos de control de producción, que se rigen por PG-06. El marcado físico de las piezas se ejecuta según IT-03 (Instructivo de identificación y marcado de producto).

## 3. Referencias

- ISO 9001:2015, §8.5.2 — Identificación y trazabilidad; §8.6 — Liberación de los productos y servicios.
- API Specification Q1, cláusulas de identificación/trazabilidad y de control de registros.
- MC-01 — Manual de Calidad (política de trazabilidad total por colada, objetivo de calidad Nº 5).
- PG-01 — Control de documentos y registros.
- PG-05 — Inspección de entrada (liberación de materia prima).
- PG-06 — Control de producción y PQP (cierre de OP y generación del PT).
- IT-03 — Instructivo de identificación y marcado de producto (lote / colada).

## 4. Definiciones

- **Colada (heat number)**: identificación de fusión del material declarada en el MTR; es el eje de la trazabilidad. En el ERP vive en `certificados.colada`, `barras.nro_colada` y `productos_terminados.nro_colada`, rotulada en pantalla como «Colada (heat nº)».
- **MTR / MTC**: Material Test Report; certificado de calidad de la materia prima, registrado en la tabla `certificados` con su PDF adjunto.
- **Lote de PT**: identificación del lote de producto terminado (`productos_terminados.lote`), asignada al cierre de la OP.
- **Trazabilidad directa**: partir de una colada o un certificado y llegar a los clientes que recibieron producto de ese material.
- **Trazabilidad inversa**: partir de una venta o remito y llegar a la colada, el MTR y los tratamientos térmicos del producto entregado.
- **Certificado de conformidad**: documento emitido por Vitalmet S.A. en cada despacho, que declara la conformidad del producto y detalla su trazabilidad (lote, OP, material, colada, MTR, tratamientos térmicos).

## 5. Responsabilidades

- **Responsable de Calidad**: verifica que la colada cargada en el sistema coincida con la del MTR; custodia la integridad de la cadena de trazabilidad; emite y firma el certificado de conformidad; puede detener un despacho ante producto sin trazabilidad completa o sin liberar.
- **Responsable de Producción**: asegura que cada OP consuma la barra correcta (`ordenes_produccion.barra_id`) y que el producto en planta conserve su identificación de lote y OP en todo momento, conforme a IT-03.
- **Responsable de Compras/Administración**: carga los MTR en `certificados` con su colada al recibir materia prima; emite el remito; registra el estado 'entregado' de la venta al concretarse la entrega; gestiona la facturación.
- **Dirección**: provee los recursos y respalda la autoridad del Responsable de Calidad para detener despachos.

## 6. Desarrollo

### 6.1 Identificación en cada etapa

1. **Materia prima**: cada MTR se registra en `certificados` con `nro`, `colada`, `proveedor` y el PDF original adjunto (`file_data`). Cada barra ingresada se registra en `barras` con `lote`, `nro_colada`, `material`, `diametro` y su vínculo al MTR (`barras.certificado_id`). El campo de colada se carga **desde el MTR a la vista**, no desde el remito ni la OC.
2. **Producción**: la OP referencia la barra consumida por `ordenes_produccion.barra_id`. El sistema solo permite consumir barras liberadas (`estado_calidad` = 'aceptado', RPC `consumir_barra`; ver PG-06).
3. **Producto terminado**: al cierre de la OP se genera el registro en `productos_terminados` con `lote`, `pieza`, `cantidad`, `barra_id` y `orden_id`. El marcado físico de la pieza (lote y/o colada según plano y requisito del cliente) se ejecuta conforme a IT-03.
4. **Venta**: cada ítem entregado queda vinculado al PT por `venta_items.producto_id`, y la venta (`ventas`) registra cliente, `nro_remito` y fechas.

### 6.2 Propagación automática de la colada

5. La colada **viaja con el producto**: al crear un PT (o al cambiarle la barra asignada), el sistema copia `barras.nro_colada` a `productos_terminados.nro_colada` mediante el trigger `fn_pt_colada`. De este modo el heat number queda estampado en el propio PT y no depende de remontar claves foráneas.
6. Si se corrige la colada de una barra (por ejemplo, al regularizar un dato mal cargado contra el MTR), el sistema propaga la corrección a todos los PT de esa barra mediante el trigger `fn_barra_colada_sync`. La colada del PT nunca queda desincronizada de la de su barra de origen.
7. El objetivo de calidad Nº 5 de MC-01 (100% de lotes de PT con colada asignada) se mide sobre `productos_terminados.nro_colada` no nulo.
8. **Nota de transición (Rev 0)**: los registros históricos cargados antes de 2026-07-01 tenían el campo de colada rotulado «Nro OC» en pantalla, por lo que parte del dato histórico corresponde al número de orden de compra y no al heat number. La regularización se hace manualmente, registro por registro, con el PDF del MTR a la vista; la propagación del punto 6 replica cada corrección a los PT afectados. Hasta completar esa depuración, toda consulta de trazabilidad sobre datos históricos debe contrastarse contra el PDF del MTR adjunto.

### 6.3 Tratamientos térmicos en la cadena

9. Los tratamientos térmicos tercerizados (Q&T / PWHT) integran la cadena de trazabilidad: cada registro de `tratamientos` cuelga de la OP (`orden_id`), identifica al proveedor por clave foránea (`tratamientos.proveedor_id` → `proveedores`, sujeto a la AVL según PG-04) y conserva su certificado (`certificado_nro`, PDF adjunto y, opcionalmente, `certificado_id` → `certificados`).
10. Los certificados de tratamiento aparecen en el certificado de conformidad del despacho (columna «Trat. térmicos», ver 6.5) y se verifican como hold point antes de continuar la producción (PG-06 §6.5).

### 6.4 Consulta de trazabilidad

11. La consulta se realiza en el módulo **Análisis → Trazabilidad** del ERP, que materializa la cadena de claves foráneas `certificados` ← `barras` ← `ordenes_produccion` / `productos_terminados` ← `venta_items` → `ventas` → cliente (MC-01 §6.3).
12. **Trazabilidad directa**: buscando por número de certificado o colada, el sistema recorre `certificados` → `barras` → `productos_terminados` y muestra la cadena completa hasta las ventas vinculadas, incluyendo proveedor del material, material y diámetro de la barra, colada, lote del PT, remito y acceso al PDF del MTR.
13. **Trazabilidad inversa**: buscando por lote o pieza de PT (o desde la propia venta), el sistema reconstruye PT → OP → barra → certificado MTR, incluyendo los tratamientos térmicos de la OP.
14. Ante un reclamo de cliente o una no conformidad detectada en campo, el Responsable de Calidad ejecuta la trazabilidad directa de la colada afectada para delimitar el alcance (qué otros lotes y clientes recibieron material de esa colada) y trata el caso según PG-09.

### 6.5 Despacho y certificado de conformidad

15. **Condición de liberación (§8.6)**: el producto terminado nace exclusivamente al cierre de la OP, y el sistema impide cerrar una OP con hold o witness points sin firmar (gate `fn_op_cierre_gate`; PG-06 §6.6). En consecuencia, todo PT disponible para despacho está liberado: la evidencia de la liberación son las firmas de los puntos de control (`op_operaciones.signoff_usuario_id` / `signoff_at`) y los registros de ensayo asociados (`registros_calidad`).
16. **Remito**: desde el módulo Ventas se genera el remito en PDF, que detalla por ítem el código de plano, la pieza, el **lote de PT** y la cantidad, con los recuadros de firma de entrega y recepción. El número de remito (`ventas.nro_remito`) es la referencia de la entrega en toda la cadena.
17. **Certificado de conformidad**: desde la misma venta se emite el certificado de conformidad en PDF (numerado CC-{nro de remito}), que contiene:
    - La declaración de conformidad: los productos fueron fabricados e inspeccionados conforme a los planos y especificaciones aplicables, con materiales respaldados por los certificados de calidad (MTC) indicados.
    - Por cada ítem: pieza, código de plano, cantidad, lote de PT, número de OP, material, **colada**, certificado MTR con su proveedor, y tratamientos térmicos con su número de certificado.
    - La firma de Control de Calidad de Vitalmet S.A.
    El certificado se construye automáticamente desde los datos vivos del ERP (cadena PT → OP → barra → MTR → tratamientos), por lo que su contenido es siempre reproducible desde los registros protegidos del sistema.
18. El Responsable de Calidad verifica el certificado antes de su envío: si algún ítem muestra colada, MTR o tratamiento faltante («—»), el despacho se detiene hasta completar la cadena o tratar el caso como no conformidad (PG-09).
19. **Registro de la entrega**: al concretarse la entrega, la venta pasa a estado 'entregado' y el sistema estampa automáticamente la fecha real en `ventas.fecha_entregado` (trigger `fn_venta_fecha_entregado`). Contra `ventas.fecha_entrega_hasta` (fecha comprometida) se calcula el indicador OTD del objetivo de calidad Nº 1 (MC-01 §6.2); el módulo Ventas señala las entregas tardías y el dashboard alerta las ventas atrasadas o próximas a vencer.
20. **Facturación**: se dispara desde la venta (botón Facturar → solicitud de CAE a AFIP vía el microservicio de facturación; la factura emitida queda vinculada por `ventas.factura_emitida_id`). La facturación es un paso administrativo posterior a la entrega y no condiciona la trazabilidad ni la liberación.

### 6.6 Protección de la evidencia de trazabilidad

21. Las tablas que sostienen la cadena (`certificados`, `tratamientos`, `calibraciones`, `registros_calidad`, entre otras) tienen auditoría de cambios (trigger `trg_audit` → `audit_log`) y protección contra borrado dentro del período de retención (trigger `fn_proteger_evidencia`), conforme a PG-01 §6.5.

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Certificados de material (MTR) con colada y PDF | `certificados` (Inventario → Certificados MTC) | 10 años (protegidos por `fn_proteger_evidencia`) |
| Barras con lote, colada y vínculo al MTR | `barras` (Inventario → Materia prima) | 10 años |
| Producto terminado con lote y colada propagada | `productos_terminados` | 10 años |
| Tratamientos térmicos (proveedor AVL + certificado) | `tratamientos` + PDF adjunto | 10 años (protegidos por `fn_proteger_evidencia`) |
| Venta, ítems y remito | `ventas` / `venta_items` (Ventas) | 10 años |
| Fecha real de entrega (OTD) | `ventas.fecha_entregado` (estampada por trigger) | 10 años (con la venta) |
| Certificado de conformidad emitido | PDF generado on-demand desde los datos vivos del ERP; copia enviada al cliente. Reproducible en todo momento desde los registros anteriores | Reproducible durante toda la retención de sus datos fuente |
| Pista de auditoría de cambios sobre la evidencia | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición vigente adquirida antes de la auditoría de certificación.*
