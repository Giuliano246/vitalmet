# MC-01 — Manual de Calidad

| Campo | Valor |
|---|---|
| **Código** | MC-01 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §4 a §10 · API Q1 §4, §5 y §6 |

## 1. Propósito

Este Manual de Calidad describe el Sistema de Gestión de la Calidad (SGC) de Vitalmet S.A.,
sus procesos, su estructura documental y las responsabilidades asociadas. Constituye el
documento de Nivel 1 del SGC y el punto de entrada a toda la documentación del sistema.

## 2. Alcance

### 2.1 Alcance del SGC

El SGC de Vitalmet S.A. aplica al **diseño y la fabricación de uniones figura 1502,
pup joints, couplings y uniones dobles para la industria del oil & gas**, incluyendo:

- Compra e inspección de entrada de materia prima crítica (AISI 4130 forjado con temple
  y revenido — Q&T — y API 5L), con certificado de material (MTR) obligatorio.
- Mecanizado y soldadura en planta conforme a ASME Sección IX.
- Ensayos e inspecciones, incluyendo prueba hidrostática hasta 22.000 psi en banco propio,
  con manómetro patrón WIKA CPG1500.
- Gestión de procesos tercerizados críticos: tratamiento térmico (Q&T / PWHT) y
  calibración de instrumentos en laboratorios externos.
- Despacho con certificado de conformidad y trazabilidad completa por colada.

El SGC se implementa conforme a ISO 9001:2015 y API Specification Q1, con requisitos
técnicos complementarios de ASME Sección IX (soldadura) y NACE MR-0175 (servicio sour),
en el camino hacia el monograma API (6A Annex M / 7K).

Sitio único: Perú 246, Villa Martelli, Buenos Aires, Argentina.

### 2.2 Exclusiones

No se declaran exclusiones a los requisitos de ISO 9001:2015. En particular:

- El **diseño y desarrollo** (§8.3) está incluido en el alcance, ya que Vitalmet S.A.
  diseña producto propio bajo especificaciones API y de cliente (PG-15).
- El **tratamiento térmico tercerizado** no constituye una exclusión: es un proceso
  provisto externamente, controlado según §8.4 mediante la evaluación de proveedores
  (PG-04) y el registro de cada tratamiento con su certificado en el ERP
  (tabla `tratamientos`, colgada de la orden de producción).

## 3. Referencias

- ISO 9001:2015 — Sistemas de gestión de la calidad. Requisitos.
- API Specification Q1 — Quality Management System Requirements for Manufacturing
  Organizations for the Petroleum and Natural Gas Industry.
- API 6A Annex M / API 7K — especificaciones de producto objetivo del monograma.
- ASME Boiler and Pressure Vessel Code, Sección IX — calificación de soldadura.
- NACE MR-0175 / ISO 15156 — materiales para servicio sour (H₂S).
- Documentos internos: PG-01 a PG-16, IT-01 a IT-03, PC-01 a PC-03, AR-01, PQP-1502
  (ver lista maestra en §6.7).

## 4. Definiciones

- **SGC**: Sistema de Gestión de la Calidad.
- **ERP / VitalStock**: sistema informático propio de Vitalmet S.A. donde el SGC opera
  y se registra (Supabase/PostgreSQL). Los controles del sistema se materializan en
  tablas, campos, triggers («gates») y funciones (RPC) citados en este manual.
- **MTR**: Material Test Report; certificado de calidad del material con número de colada.
- **Colada** (heat number): identificación de fusión del material, eje de la trazabilidad.
- **AVL**: Approved Vendor List; lista de proveedores aprobados.
- **PQP**: Plan de Calidad de Producto (routing con puntos de inspección).
- **Hold point / Witness point**: punto de detención obligatoria / de presencia en el
  routing de producción, que requiere firma (signoff) para avanzar.
- **NC / CAPA**: No Conformidad / Acción Correctiva y Preventiva.
- **WPS / PQR / WPQ**: especificación de procedimiento de soldadura / registro de
  calificación de procedimiento / calificación de habilidad del soldador (ASME IX).
- **Q&T**: temple y revenido. **PWHT**: tratamiento térmico post-soldadura.
- **OTD**: On-Time Delivery; entregas a tiempo respecto del compromiso con el cliente.

## 5. Responsabilidades

Las responsabilidades del SGC se asignan por rol, sin nombres propios. Una misma persona
puede ejercer más de un rol, excepto donde se indique incompatibilidad.

- **Dirección**: define la política y los objetivos de calidad; aprueba este manual y
  los procedimientos; provee los recursos; conduce la revisión por la dirección (PG-12);
  aprueba la disposición de no conformidades mayores y la gestión del cambio (PG-14).
- **Responsable de Calidad**: representa a la Dirección en el SGC (API Q1 §4); mantiene
  la documentación del sistema (PG-01); administra el módulo Calidad del ERP
  (documentos controlados, NC/CAPA, plantillas PQP); gestiona la metrología (PG-08);
  planifica y coordina auditorías internas (PG-11); libera producto. Debe tener
  independencia respecto de Producción para las decisiones de aceptación/rechazo.
- **Responsable de Producción**: planifica y ejecuta las órdenes de producción; asegura
  el cumplimiento del routing y de los hold/witness points; gestiona la soldadura
  conforme a WPS vigentes (PG-16); coordina los tratamientos térmicos tercerizados.
- **Responsable de Compras/Administración**: gestiona compras sobre la AVL (PG-04);
  registra recepciones; administra ventas, remitos y facturación; custodia los
  registros contables y su retención legal.

## 6. Desarrollo

### 6.1 Política de Calidad

Vitalmet S.A. diseña y fabrica componentes de alta presión para la industria del
oil & gas — uniones figura 1502, pup joints, couplings y uniones dobles — cuya falla
en servicio puede comprometer vidas, instalaciones y el ambiente. En consecuencia,
la Dirección establece la siguiente Política de Calidad:

1. **Seguridad del producto ante todo.** Ningún producto de alta presión se libera sin
   la evidencia completa de sus ensayos e inspecciones; la integridad del producto
   prevalece sobre el plazo y el costo.
2. **Cumplimiento de requisitos.** Se cumplen los requisitos de API Q1, ISO 9001:2015,
   ASME Sección IX y NACE MR-0175, las especificaciones de producto aplicables y los
   requisitos particulares de cada cliente, así como los legales y reglamentarios.
3. **Trazabilidad total por colada.** Cada producto entregado es trazable desde el
   certificado de material (MTR) y su número de colada hasta el cliente final, y a la
   inversa, mediante el ERP de la empresa.
4. **Mejora continua.** El desempeño del SGC se mide con indicadores objetivos, las no
   conformidades se tratan hasta la verificación de eficacia de las acciones, y los
   riesgos se gestionan de manera preventiva.

Esta política es comunicada a todo el personal, está disponible para las partes
interesadas y se revisa en cada revisión por la dirección (PG-12).

### 6.2 Objetivos de Calidad

Los objetivos de calidad son medibles y su indicador se calcula con datos del ERP.
Se revisan como mínimo en cada revisión por la dirección (PG-12).

| # | Objetivo | Meta | Indicador en el ERP |
|---|---|---|---|
| 1 | Entregas a tiempo (OTD) | ≥ 95% | `ventas.fecha_entregado` (real, asentada por trigger) contra `ventas.fecha_entrega_hasta` (compromiso); indicador OTD del dashboard |
| 2 | Cierre oportuno de no conformidades | 100% de NC cerradas en ≤ 30 días | `no_conformidades`: diferencia entre `fecha` y `cerrada_at`, con `estado` = 'cerrada' |
| 3 | Proveedores críticos evaluados y vigentes | 100% | `proveedores` con `criticidad` = 'critico' y `activo`: `aprobado` = verdadero y `fecha_proxima_evaluacion` no vencida; el sistema bloquea las OC en infracción (trigger `fn_oc_avl_gate`) |
| 4 | Inspecciones con instrumentos calibrados | Cero inspecciones con instrumento vencido | Gate del ERP: el sistema impide registrar una inspección con un instrumento cuyo `vencimiento_calibracion` está vencido o nulo (trigger `fn_registro_calibracion_gate`); el indicador verifica ausencia de excepciones |
| 5 | Trazabilidad completa del producto terminado | 100% de lotes de PT con colada asignada | `productos_terminados.nro_colada` no nulo (propagado por el trigger `fn_pt_colada` desde la barra de origen) |

### 6.3 Mapa de procesos

El SGC se organiza en procesos de dirección, operativos y de apoyo. Los procesos
operativos siguen la secuencia de realización del producto; los módulos del ERP donde
opera cada proceso se indican entre paréntesis.

| Grupo | Proceso | Procedimiento rector | Módulo del ERP |
|---|---|---|---|
| **Dirección** | Planificación estratégica, gestión de riesgos y oportunidades | PG-02, AR-01 | — |
| **Dirección** | Revisión por la dirección | PG-12 | Dashboard (indicadores) |
| **Dirección** | Gestión del cambio (MoC) | PG-14 | — |
| **Operativo 1** | Comercial: presupuesto y revisión de requisitos del cliente | PG-03 | Ventas → Presupuestos (`presupuestos`) |
| **Operativo 2** | Diseño y validación de producto | PG-15 | Calidad → Documentos (planos, especificaciones) |
| **Operativo 3** | Compras y evaluación de proveedores (AVL) | PG-04 | Compras (`ordenes_compra`, `proveedores`) |
| **Operativo 4** | Recepción e inspección de entrada | PG-05 | Compras → Inspección de entrada (`recepciones_oc`, `certificados`, `barras`) |
| **Operativo 5** | Producción: mecanizado, soldadura, tratamiento térmico tercerizado | PG-06, PG-16 | Producción (`ordenes_produccion`, `op_operaciones`, `tratamientos`) |
| **Operativo 6** | Inspección y ensayo (dimensional, hidrostático, END) | PG-06, IT-01 a IT-03 | Producción → botón Ensayo (`registros_calidad`) |
| **Operativo 7** | Despacho, certificado de conformidad y facturación | PG-07 | Ventas (`ventas`; certificado de conformidad PDF) |
| **Apoyo** | Control de documentos y registros | PG-01 | Calidad → Documentos (`documentos_controlados`, `audit_log`) |
| **Apoyo** | Metrología: calibración de instrumentos | PG-08 | Inventario → Herramientas (`herramientas`, `calibraciones`) |
| **Apoyo** | Producto no conforme y CAPA | PG-09, PG-10 | Calidad → NCR/CAPA (`no_conformidades`, `acciones_capa`) |
| **Apoyo** | Auditorías internas | PG-11 | — (informes en carpeta de calidad) |
| **Apoyo** | Competencia y capacitación | PG-13 | — (planillas físicas) |
| **Apoyo** | Identificación y trazabilidad | PG-07 | Análisis → Trazabilidad (cadena de FK) |
| **Apoyo** | Mantenimiento de equipos e infraestructura | PG-06 (apartado) | Inventario → Herramientas (`herramientas.estado`) |
| **Apoyo** | Administración y contabilidad | — | Ventas / Compras / Facturación |

Flujo operativo principal:

```
Cliente → [Comercial PG-03] → [Diseño PG-15] → [Compras PG-04] → [Recepción/Inspección PG-05]
       → [Producción PG-06 · Soldadura PG-16 · TT tercerizado] → [Ensayo IT-01/02/03]
       → [Despacho + Certificado de conformidad PG-07] → Cliente
Sostenido por: Calidad (PG-01, PG-09, PG-10, PG-11) · Metrología (PG-08) · Capacitación (PG-13)
Gobernado por: Dirección (PG-02, PG-12, PG-14) · Riesgos (AR-01)
```

La interacción entre procesos queda materializada en el ERP por la cadena de claves
foráneas: `certificados` ← `barras` ← `ordenes_produccion` / `productos_terminados`
← `venta_items` → `ventas` → cliente.

### 6.4 Estructura organizacional

La estructura se define por roles (ver responsabilidades detalladas en §5):

```
                          Dirección
                              |
        +---------------------+----------------------+
        |                     |                      |
 Responsable de        Responsable de         Responsable de
    Calidad             Producción         Compras/Administración
 (representante de   (planta, soldadura,   (compras, recepción
 la dirección ante    routing, tiempos)     administrativa, ventas,
 el SGC — API Q1)                           facturación)
```

El Responsable de Calidad reporta directamente a la Dirección y tiene autoridad para
detener producción y despacho ante producto no conforme, con independencia de las
presiones de plazo o costo.

### 6.5 Estructura documental

La documentación del SGC se organiza en cuatro niveles:

| Nivel | Tipo de documento | Códigos | Tipo en el ERP (`documentos_controlados.tipo`) |
|---|---|---|---|
| 1 | Manual de Calidad | MC-01 | 'manual' |
| 2 | Procedimientos generales | PG-01 a PG-16 | 'procedimiento' |
| 3 | Instructivos de trabajo, planes de calidad, planes de contingencia, análisis de riesgos, documentos de soldadura | IT-xx, PQP-xxxx, PC-xx, AR-xx, WPS/PQR/WPQ | 'instructivo', 'pqp', 'plan_contingencia', 'otro', 'wps', 'pqr', 'wpq' |
| 4 | Formularios y registros | FR-xx y los registros del ERP | 'formulario' + tablas del ERP |

### 6.6 Control de la documentación (repositorio)

El repositorio oficial de los documentos del SGC es el **módulo Calidad → Documentos
del ERP** (tabla `documentos_controlados`), que registra `codigo`, `titulo`, `tipo`,
`revision`, `estado`, `fecha_vigencia`, `aprobado_por` y el PDF firmado (`file_data`).
Los controles clave, detallados en PG-01, son:

- El sistema obsoleta automáticamente las revisiones anteriores de un código cuando
  una nueva revisión pasa a estado 'vigente' (trigger `fn_doc_vigencia`); la
  combinación (codigo, revision) es única en la base.
- En producción, las operaciones del routing solo pueden referenciar documentos en
  estado 'vigente': el sistema rechaza asignar a `op_operaciones.documento_id` un
  documento en otro estado (trigger `fn_op_quality_gate`).
- La eliminación de documentos controlados está restringida a administradores y queda
  asentada en `audit_log` (trigger `fn_proteger_evidencia`).

### 6.7 Lista maestra de documentos del SGC

| Código | Título | Nivel | Tipo en ERP |
|---|---|---|---|
| MC-01 | Manual de Calidad | 1 | 'manual' |
| PG-01 | Control de documentos y registros | 2 | 'procedimiento' |
| PG-02 | Gestión de riesgos y oportunidades | 2 | 'procedimiento' |
| PG-03 | Revisión de requisitos del cliente | 2 | 'procedimiento' |
| PG-04 | Compras y evaluación de proveedores (AVL) | 2 | 'procedimiento' |
| PG-05 | Inspección de entrada | 2 | 'procedimiento' |
| PG-06 | Control de producción y PQP | 2 | 'procedimiento' |
| PG-07 | Identificación y trazabilidad | 2 | 'procedimiento' |
| PG-08 | Control de equipos de medición (calibración) | 2 | 'procedimiento' |
| PG-09 | Control de producto no conforme | 2 | 'procedimiento' |
| PG-10 | Acciones correctivas y preventivas (CAPA) | 2 | 'procedimiento' |
| PG-11 | Auditorías internas | 2 | 'procedimiento' |
| PG-12 | Revisión por la dirección | 2 | 'procedimiento' |
| PG-13 | Competencia y capacitación | 2 | 'procedimiento' |
| PG-14 | Gestión del cambio (MoC) | 2 | 'procedimiento' |
| PG-15 | Control de diseño y validación | 2 | 'procedimiento' |
| PG-16 | Control de soldadura y servicio sour (ASME IX / NACE MR-0175) | 2 | 'procedimiento' |
| IT-01 | Instructivo de prueba hidrostática (banco hasta 22.000 psi, patrón WIKA CPG1500) | 3 | 'instructivo' |
| IT-02 | Instructivo de inspección dimensional y visual | 3 | 'instructivo' |
| IT-03 | Instructivo de identificación y marcado de producto (lote / colada) | 3 | 'instructivo' |
| PC-01 | Plan de contingencia: indisponibilidad del ERP | 3 | 'plan_contingencia' |
| PC-02 | Plan de contingencia: falla del banco de prueba o del instrumento patrón | 3 | 'plan_contingencia' |
| PC-03 | Plan de contingencia: interrupción de proveedor crítico (material / tratamiento térmico) | 3 | 'plan_contingencia' |
| AR-01 | Análisis de riesgos y oportunidades del SGC | 3 | 'otro' |
| PQP-1502 | Plan de Calidad de Producto — Unión figura 1502 | 3 | 'pqp' (plantilla en `pqp_plantillas`, `codigo` = PQP-1502) |
| WPS-xxx | Especificaciones de procedimiento de soldadura (según listado vigente en el ERP) | 3 | 'wps' |
| PQR-xxx | Registros de calificación de procedimiento (según listado vigente en el ERP) | 3 | 'pqr' |
| WPQ-xxx | Calificaciones de soldadores (según listado vigente en el ERP) | 3 | 'wpq' |
| FR-00 | Listado maestro de registros del SGC | 4 | 'formulario' |

Los WPS, PQR y WPQ se administran como documentos controlados individuales en
`documentos_controlados` con su `tipo` correspondiente; el listado vigente se consulta
directamente en el módulo Calidad → Documentos filtrando por tipo y `estado` = 'vigente'.

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Documentos controlados del SGC (incl. revisiones obsoletas) | `documentos_controlados` (Calidad → Documentos) | 10 años |
| Listado maestro de registros | FR-00 (este SGC) | Vigencia permanente, revisiones retenidas 10 años |
| Indicadores de objetivos de calidad | Dashboard del ERP (calculados sobre `ventas`, `no_conformidades`, `proveedores`, `registros_calidad`, `productos_terminados`) | 10 años (datos fuente protegidos por `fn_proteger_evidencia`) |
| Minutas de revisión por la dirección | Planilla física, carpeta de calidad | 10 años |

El detalle completo de los registros del SGC se encuentra en FR-00.

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---

*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la
edición vigente adquirida antes de la auditoría de certificación.*
