# PG-01 — Control de documentos y registros

| Campo | Valor |
|---|---|
| **Código** | PG-01 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §7.5 · API Q1 §4.4 (Control de documentos) y §4.5 (Control de registros) |

## 1. Propósito

Establecer la metodología para crear, revisar, aprobar, distribuir, actualizar y retirar los
documentos del Sistema de Gestión de Calidad (SGC) de Vitalmet S.A., y para identificar,
proteger, conservar y disponer de los registros de calidad, asegurando que en los puestos de
trabajo solo se utilice información documentada vigente y que la evidencia del SGC permanezca
íntegra, legible y recuperable durante todo el período de retención.

## 2. Alcance

Aplica a la totalidad de la información documentada del SGC: manual de calidad, procedimientos,
instructivos, formularios, planes de calidad de producto (PQP), análisis de riesgo, planes de
contingencia, especificaciones de soldadura (WPS/PQR/WPQ) y todo otro documento cuyo uso afecte
la conformidad del producto. Aplica asimismo a todos los registros de calidad generados por la
operación (certificados de material, registros de inspección y ensayo, calibraciones, no
conformidades, acciones CAPA, tratamientos térmicos, recepciones).

## 3. Referencias

- ISO 9001:2015, §7.5 — Información documentada.
- API Specification Q1, 9ª edición — §4.4 Control de documentos; §4.5 Control de registros.
- MC-01 — Manual de Calidad.
- PG-02 — Gestión de riesgos (registro AR-01).

## 4. Definiciones

- **Documento controlado**: información documentada cuya emisión, revisión y vigencia se
  administran conforme a este procedimiento, registrada en la tabla `documentos_controlados` del ERP.
- **Registro de calidad**: evidencia objetiva de una actividad realizada o de un resultado
  obtenido; a diferencia del documento, el registro no se revisa: se conserva.
- **ERP (VitalStock)**: sistema de gestión propio de Vitalmet S.A.; es el repositorio maestro y
  punto único de consulta de los documentos vigentes del SGC.
- **Revisión vigente**: única revisión de un código de documento habilitada para uso operativo
  (`documentos_controlados.estado` = 'vigente').

## 5. Responsabilidades

- **Dirección**: aprueba los documentos del SGC; autoriza la baja de documentos obsoletos;
  es responsable del respaldo anual de la base de datos y su custodia externa.
- **Responsable de Calidad**: elabora y/o revisa los documentos del SGC; administra el módulo
  Calidad → Documentos del ERP; controla la codificación, la vigencia y el retiro de obsoletos;
  verifica la integridad de los registros de calidad.
- **Responsable de Producción**: verifica que en planta solo se utilicen instructivos, planos y
  WPS en estado vigente; propone actualizaciones cuando la práctica difiere del documento.
- **Responsable de Compras**: asegura que los documentos enviados a proveedores (requisitos de
  compra, especificaciones) correspondan a la revisión vigente.

## 6. Desarrollo

### 6.1 Codificación de documentos

Todo documento controlado se identifica con un código único según su tipo, registrado en
`documentos_controlados.codigo`:

| Prefijo | Tipo de documento | `documentos_controlados.tipo` |
|---|---|---|
| MC | Manual de Calidad | 'manual' |
| PG | Procedimiento general | 'procedimiento' |
| IT | Instructivo de trabajo | 'instructivo' |
| FR | Formulario / plantilla de registro | 'formulario' |
| PC | Plan de contingencia | 'plan_contingencia' |
| AR | Análisis / matriz de riesgos | 'otro' |
| PQP | Plan de calidad de producto | 'pqp' |
| WPS | Especificación de procedimiento de soldadura | 'wps' |
| PQR | Registro de calificación de procedimiento | 'pqr' |
| WPQ | Calificación de soldador | 'wpq' |

La combinación código + revisión es única en el sistema (restricción UNIQUE sobre
`documentos_controlados.codigo, revision`); el sistema impide cargar dos veces la misma
revisión de un mismo código.

### 6.2 Ciclo de vida del documento

1. **Elaboración (borrador)**. El Responsable de Calidad crea el documento en el módulo
   Calidad → Documentos, con `documentos_controlados.estado` = 'borrador'. En este estado el
   documento no es apto para uso operativo: el sistema impide vincular documentos en borrador a
   operaciones de producción (el campo `op_operaciones.documento_id` solo acepta documentos en
   estado 'vigente', gate `fn_op_quality_gate`).
2. **Revisión**. La Dirección revisa el contenido. Las observaciones se incorporan sobre el
   borrador; no se emiten revisiones intermedias.
3. **Aprobación**. La aprobación queda estampada en `documentos_controlados.aprobado_por` junto
   con `fecha_vigencia`. El PDF firmado se adjunta en `documentos_controlados.file_data`.
4. **Puesta en vigencia**. Al pasar `documentos_controlados.estado` a 'vigente', el sistema
   obsoleta automáticamente toda otra revisión del mismo código (trigger `fn_doc_vigencia`).
   De este modo existe una y solo una revisión vigente por código en todo momento, sin
   intervención manual.
5. **Modificación**. Todo cambio se tramita como nueva revisión: se crea un nuevo registro con
   el mismo `codigo` y `revision` incrementada, se repiten los pasos 1 a 4, y la revisión
   anterior pasa a 'obsoleto' automáticamente al activar la nueva.
6. **Obsolescencia**. Los documentos en estado 'obsoleto' permanecen en el sistema con fines de
   consulta histórica y trazabilidad, pero no son utilizables en producción (ver 6.2.1). No se
   eliminan: el sistema restringe el DELETE sobre `documentos_controlados` exclusivamente a
   administradores y lo asienta en el registro de auditoría (trigger `fn_proteger_evidencia`).

### 6.3 Distribución y punto de uso

1. El ERP es el **punto único de consulta** de la documentación vigente. No se distribuyen
   copias controladas en papel; toda impresión es copia no controlada y pierde validez al día
   siguiente de su impresión.
2. El documento aprobado se consulta desde el módulo Calidad → Documentos, descargando el PDF
   almacenado en `documentos_controlados.file_data` / `file_name`.
3. En producción, el documento aplicable a cada operación (WPS, instructivo) queda vinculado a
   la operación de la orden mediante `op_operaciones.documento_id`; el sistema exige que ese
   vínculo apunte a un documento en estado 'vigente' (gate `fn_op_quality_gate`), lo que
   garantiza que el operario nunca trabaje contra una revisión obsoleta.
4. Las plantillas PQP referencian sus documentos por `pqp_plantillas.documento_id` y
   `pqp_plantilla_operaciones.documento_id`; al instanciar la plantilla en una orden de
   producción (RPC `instanciar_pqp`) la referencia documental se copia al routing real.

### 6.4 Documentos de origen externo

Las normas de referencia (ISO 9001, API Q1, API 6A, API 5L, ASME Sección IX, NACE MR-0175) y
los planos de cliente se identifican y controlan por su edición/revisión declarada en el
documento del SGC que los invoca. Su archivo físico o digital se mantiene en la carpeta de
calidad, bajo custodia del Responsable de Calidad.

### 6.5 Control de registros de calidad

1. **Identificación y almacenamiento**. Los registros de calidad nacen y viven en el ERP, en
   las tablas correspondientes a cada proceso: `certificados` (MTRs), `recepciones_oc`
   (inspección de entrada), `registros_calidad` (inspecciones y ensayos), `calibraciones`,
   `tratamientos`, `no_conformidades` y `acciones_capa`. Cada registro queda vinculado por
   clave foránea a su objeto de origen (OC, orden de producción, recepción o venta), lo que
   asegura su recuperabilidad.
2. **Retención**. La retención mínima de los registros de calidad es de **10 años**, conforme
   a API Q1. Ningún registro se elimina antes de ese plazo.
3. **Protección contra borrado**. El sistema restringe el DELETE sobre `certificados`,
   `recepciones_oc`, `tratamientos`, `calibraciones`, `registros_calidad`, `no_conformidades`,
   `acciones_capa` y `documentos_controlados` exclusivamente a usuarios administradores, y
   asienta cada borrado en el registro de auditoría (trigger `fn_proteger_evidencia`).
4. **Inmutabilidad y trazabilidad de cambios**. Toda operación INSERT/UPDATE/DELETE sobre las
   tablas críticas queda asentada en `audit_log` con el diff de valores anteriores y nuevos,
   el usuario y la fecha. El `audit_log` es de solo lectura para administradores y no admite
   modificación: constituye la evidencia inmutable de la historia de cada registro.
5. **Legibilidad**. Los registros con documento adjunto (certificados, calibraciones, ensayos)
   conservan el PDF original en el campo `file_data` de la tabla correspondiente.
6. **Registros fuera del ERP**. Los siguientes registros no están materializados en el ERP y
   se conservan como planilla física o archivo en la carpeta de calidad, con la misma retención
   de 10 años: asistencia a capacitación, informes de auditoría interna, minutas de revisión
   por la dirección y calificaciones de soldadores (WPQ).

### 6.6 Respaldo (control operativo)

1. Una vez por año, la Dirección ejecuta (o delega bajo su supervisión) una **exportación
   completa de la base de datos** del ERP, incluyendo los PDFs adjuntos (`file_data` de
   `documentos_controlados`, `certificados`, `calibraciones`, `registros_calidad` y
   `tratamientos`).
2. El export se graba en soporte externo (disco o medio equivalente), se identifica con la
   fecha de corte y se conserva **10 años** fuera de las instalaciones del servidor primario.
3. La ejecución del respaldo se registra como archivo en la carpeta de calidad (fecha, soporte,
   ubicación de custodia, responsable). **Responsable: Dirección.**

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Documentos controlados (todas las revisiones y su PDF) | `documentos_controlados` (Calidad → Documentos) | Permanente (obsoletos conservados) |
| Historia de cambios de documentos y registros | `audit_log` | 10 años |
| Certificados de material (MTR) | `certificados` (Inventario → Certificados MTC) | 10 años |
| Registros de inspección y ensayo | `registros_calidad` | 10 años |
| Calibraciones | `calibraciones` | 10 años |
| Tratamientos térmicos | `tratamientos` | 10 años |
| No conformidades y CAPA | `no_conformidades` / `acciones_capa` (Calidad → NCR/CAPA) | 10 años |
| Constancia de respaldo anual | Archivo en carpeta de calidad (fuera del ERP) | 10 años |
| Asistencia a capacitación, informes de auditoría interna, minutas de revisión por la dirección, WPQ | Planilla física / carpeta de calidad (fuera del ERP) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
