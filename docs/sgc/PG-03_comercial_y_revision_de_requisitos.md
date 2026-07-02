# PG-03 — Comercial: presupuesto y revisión de requisitos del cliente

| Campo | Valor |
|---|---|
| **Código** | PG-03 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.2 (Requisitos para los productos y servicios) · API Q1 §5.1 (Revisión de contrato) |

## 1. Propósito

Establecer la metodología del proceso comercial de Vitalmet S.A.: la elaboración y el seguimiento de presupuestos, la revisión de los requisitos del cliente antes de comprometer la entrega, y la conversión del presupuesto aprobado en venta, asegurando que la empresa solo acepte pedidos cuyos requisitos están definidos, comprendidos y dentro de su capacidad de cumplimiento (técnica, de materiales y de plazo).

## 2. Alcance

Aplica a toda consulta, cotización y pedido de productos fabricados por Vitalmet S.A. (uniones figura 1502, pup joints, couplings y uniones dobles) y de los demás productos comercializados, desde la recepción de la consulta del cliente hasta la aceptación del pedido (conversión del presupuesto en venta en el ERP) y el seguimiento del compromiso de entrega (OTD). El proceso opera en el módulo **Ventas → Presupuestos** del ERP (tablas `presupuestos` y `presupuesto_items`) y en **Ventas** (tablas `ventas` y `venta_items`).

No aplica al despacho, la facturación ni el certificado de conformidad (PG-07), ni al diseño de producto nuevo (PG-15).

## 3. Referencias

- ISO 9001:2015, §8.2 — Requisitos para los productos y servicios (comunicación con el cliente, determinación y revisión de requisitos, cambios).
- API Specification Q1, 9ª edición — §5.1 Revisión de contrato.
- MC-01 — Manual de Calidad (proceso Operativo 1 del mapa de procesos).
- PG-06 — Control de producción y PQP (capacidad y routing).
- PG-15 — Control de diseño y validación (producto nuevo o especificación de cliente).
- PG-07 — Despacho, certificado de conformidad y trazabilidad.

## 4. Definiciones

- **Presupuesto**: oferta comercial registrada en la tabla `presupuestos` del ERP, con sus ítems en `presupuesto_items`. Es el registro de la determinación y revisión de requisitos previa a la aceptación.
- **Conversión**: aceptación formal del pedido; se materializa con el RPC atómico `convertir_presupuesto`, que crea la venta y bloquea el presupuesto en estado 'convertido'.
- **Costo estimado**: costo unitario cotizado de cada ítem (`presupuesto_items.costo_estimado`), base del control de margen.
- **OTD** (On-Time Delivery): cumplimiento de la fecha de entrega comprometida (`ventas.fecha_entrega_hasta`) contra la fecha real (`ventas.fecha_entregado`).
- **CAE**: Código de Autorización Electrónico de AFIP; una venta con CAE emitido queda protegida contra edición.

## 5. Responsabilidades

- **Dirección**: define la política de precios y los márgenes objetivo; aprueba las ofertas con requisitos especiales, apartamientos de norma o condiciones comerciales fuera de lo habitual; resuelve las diferencias entre lo cotizado y lo pedido antes de aceptar.
- **Responsable de Compras/Administración**: elabora, emite y da seguimiento a los presupuestos en el ERP; verifica la identidad y condición del cliente (razón social, CUIT, condición de pago); ejecuta la conversión a venta y mantiene actualizados los estados.
- **Responsable de Producción**: valida la factibilidad de plazo (capacidad de planta, carga de trabajo, disponibilidad de materia prima) antes de comprometer `fecha_entrega_hasta`.
- **Responsable de Calidad**: revisa los requisitos técnicos y normativos particulares (especificación API, plano de cliente, servicio sour NACE MR-0175, requisitos de inspección presenciada) antes del envío de la oferta; interviene ante cambios de requisitos que afecten la conformidad del producto.

## 6. Desarrollo

### 6.1 Determinación de requisitos y elaboración del presupuesto

1. Toda consulta de cliente se responde mediante un presupuesto emitido desde el ERP (módulo Ventas → Presupuestos, botón «Nuevo presupuesto»), registrado en `presupuestos` con: `nro` (correlativo P-xxxx), `cliente`, `cuit`, `fecha`, `fecha_vencimiento` (validez de la oferta), `condicion_pago`, `estado`, `total` y `observaciones`.
2. Antes de cotizar, quien elabora la oferta determina los requisitos del producto: especificación o plano aplicable, material y condición (por ejemplo AISI 4130 Q&T), presión de trabajo y ensayos requeridos, cantidad, requisitos legales/reglamentarios y todo requisito no declarado por el cliente pero necesario para el uso previsto (alta presión, servicio sour). Los requisitos técnicos o normativos no habituales se consultan con el Responsable de Calidad; el producto nuevo o con especificación particular del cliente se deriva al proceso de diseño (PG-15).
3. Cada ítem se carga en `presupuesto_items` con `producto_id` (cuando es un producto del catálogo), `pieza`, `descripcion`, `cantidad`, `precio_unitario` y `subtotal`. El total admite descuento porcentual y se expresa en USD, moneda operativa del ERP.

### 6.2 Cotización con costeo y control de margen

4. El cotizador del ERP registra en `presupuesto_items.costo_estimado` el costo unitario estimado de cada ítem. Para productos con historia de fabricación, el sistema lo autocompleta con el costo real histórico (materia prima + tiempos de producción + overhead, función `computeCostoPT`); para piezas nuevas se estima y carga manualmente.
5. El modal de presupuesto muestra el margen por ítem y el panel de costeo total (costo, margen porcentual) antes de emitir la oferta. Los presupuestos con margen por debajo del objetivo definido por la Dirección requieren su autorización expresa antes del envío.
6. El costo estimado queda persistido: el dashboard del ERP compara, para cada presupuesto convertido en venta, el **margen cotizado contra el margen real** de fabricación (panel «Margen cotizado vs. real»), realimentando la calidad del costeo comercial.

### 6.3 Emisión, envío y seguimiento de la oferta

7. El presupuesto transita los estados registrados en `presupuestos.estado`: 'borrador' → 'enviado' → ('aprobado' | 'rechazado' | 'vencido') → 'convertido'. La oferta se emite como PDF generado por el ERP (botón PDF del listado o del modal) y se envía al cliente por los medios habituales.
8. El seguimiento comercial se apoya en las alertas automáticas del panel «Para hoy» del dashboard, calculadas sobre `presupuestos`:
   - Presupuesto 'enviado' **sin respuesta hace 7 o más días** → contactar al cliente.
   - Presupuesto 'enviado' que **vence en menos de 3 días** (`fecha_vencimiento`) → gestionar la decisión.
   - Presupuesto 'enviado' **ya vencido** → renegociar (nueva oferta o extensión de validez) o cerrar como 'vencido'/'rechazado'.
9. Una oferta vencida no se reactiva: si el cliente decide comprar después de `fecha_vencimiento`, se revisan precios, costos y plazo, y se emite una nueva revisión del presupuesto (nuevo registro) o se actualizan sus datos antes de reenviar.

### 6.4 Revisión de requisitos previa a la aceptación

10. Antes de convertir el presupuesto en venta, el Responsable de Compras/Administración verifica que:
    - los requisitos del pedido del cliente (orden de compra recibida, correo de aprobación) **coinciden con lo cotizado**; toda diferencia se resuelve con el cliente y se documenta en el presupuesto antes de aceptar;
    - la empresa tiene capacidad de cumplir: materia prima disponible o comprable en plazo (PG-04/PG-05), capacidad de planta confirmada por el Responsable de Producción, y requisitos técnicos cubiertos (WPS calificados, instrumentos, PQP vigente — PG-06);
    - la condición crediticia del cliente es aceptable (cuenta corriente al día, según el módulo Cta. corriente).
11. La evidencia de la revisión es el propio registro del presupuesto en estado 'aprobado' (o 'enviado' con aprobación documentada del cliente) más las observaciones cargadas; los correos u órdenes de compra del cliente se conservan en el legajo comercial.

### 6.5 Conversión del presupuesto en venta (aceptación del pedido)

12. La aceptación del pedido se ejecuta con el botón «Venta» del listado de presupuestos, que invoca el RPC atómico `convertir_presupuesto(p_presupuesto_id)`. La función, en una única transacción:
    - asigna a la venta la numeración correlativa V-xxxxx generada en la base de datos (con bloqueo advisory, sin duplicados posibles);
    - crea o actualiza el cliente maestro (`upsert_cliente` con razón social y CUIT);
    - crea la venta en `ventas` en estado 'pendiente', heredando `condicion_pago` y las observaciones, con referencia explícita al presupuesto de origen;
    - copia los ítems de `presupuesto_items` a `venta_items` (pieza, cantidad, precio, total);
    - marca el presupuesto como 'convertido' y lo vincula por `presupuestos.venta_id`. El sistema **impide convertir dos veces** el mismo presupuesto.
13. La conversión toma inicialmente `presupuestos.fecha_vencimiento` como `ventas.fecha_entrega_hasta`. Dado que la validez comercial de la oferta no es necesariamente el plazo de entrega pactado, al confirmar el pedido el Responsable de Compras/Administración **ajusta `fecha_entrega_hasta` a la fecha de entrega realmente comprometida** con el cliente (campo editable en la venta), validada con Producción. Esta fecha es la base del indicador OTD.
14. La conversión no descuenta stock de producto terminado: la venta nace 'pendiente' y el stock se mueve al editarla/entregarla, mediante las RPCs atómicas de venta (`guardar_venta` / `anular_venta`).

### 6.6 Cambios de requisitos y control posterior

15. Los cambios de requisitos posteriores a la aceptación (cantidad, especificación, plazo) se registran editando la venta en el ERP, previa verificación de factibilidad equivalente a la del punto 10. Si el cambio afecta un producto ya en fabricación, se evalúa el impacto sobre la OP y su PQP (PG-06) y, si corresponde, por la gestión del cambio (PG-14).
16. Una venta con factura emitida (CAE) queda protegida por el sistema: no admite edición ni anulación directa (guard de integridad del ERP). Los cambios posteriores a la facturación se tramitan por los mecanismos fiscales correspondientes (nota de crédito).
17. El cumplimiento del compromiso de entrega se mide con el indicador **OTD**: al pasar la venta a 'entregado', el sistema estampa automáticamente la fecha real en `ventas.fecha_entregado` (trigger `fn_venta_fecha_entregado`); el dashboard calcula el porcentaje de entregas a tiempo (`fecha_entregado` ≤ `fecha_entrega_hasta`) y señala las ventas atrasadas (badge «ATRASADO») y las entregas tardías (badge «ENTREGA TARDÍA»). El objetivo de calidad asociado (OTD ≥ 95 %) se revisa según MC-01 §6.2 y PG-12.

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Presupuestos y sus ítems (incl. costo estimado y margen cotizado) | `presupuestos` / `presupuesto_items` (Ventas → Presupuestos) | 10 años |
| PDF de oferta enviado al cliente | Generado por el ERP (jsPDF); copia en el legajo comercial junto con la orden de compra / aprobación del cliente | 10 años |
| Ventas y sus ítems (pedido aceptado) | `ventas` / `venta_items` (Ventas) | 10 años |
| Vínculo presupuesto → venta (trazabilidad de la aceptación) | `presupuestos.venta_id`, `presupuestos.estado` = 'convertido' | 10 años |
| Compromiso y cumplimiento de entrega (OTD) | `ventas.fecha_entrega_hasta` / `ventas.fecha_entregado` | 10 años |
| Historia de cambios de presupuestos y ventas | `audit_log` | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
