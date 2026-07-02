# PG-16 — Control de soldadura y servicio sour (ASME IX / NACE MR-0175)

| Campo | Valor |
|---|---|
| **Código** | PG-16 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.5.1.f (validación de procesos especiales) · API Q1 §5.7 (control de producción) · ASME Sección IX · NACE MR-0175 |

## 1. Propósito

Establecer la metodología para controlar la soldadura como **proceso especial** en Vitalmet S.A.: la calificación de los procedimientos de soldadura (WPS/PQR) y de los soldadores (WPQ) conforme a ASME Sección IX, la ejecución de la soldadura exclusivamente contra WPS vigentes, la verificación posterior mediante ensayos, y los requisitos adicionales para producto destinado a servicio sour (NACE MR-0175), dado que el resultado de la soldadura no puede verificarse en su totalidad por inspección posterior sobre el producto.

## 2. Alcance

Aplica a toda soldadura de producción ejecutada en planta sobre producto de Vitalmet S.A. (uniones figura 1502, pup joints, couplings y uniones dobles), incluyendo:

- La calificación y el control documental de WPS, PQR y WPQ.
- La asignación del WPS a cada operación de soldadura del routing (plantillas PQP y OP).
- La ejecución de la soldadura y su verificación posterior (hold point).
- El tratamiento térmico post-soldadura (PWHT) tercerizado, en lo relativo a su vínculo con la soldadura.
- Los requisitos complementarios de servicio sour (NACE MR-0175): materiales, durezas y su evidencia.

La mecánica general del routing, los hold/witness points y su firma se rigen por PG-06; el ciclo de vida documental (borrador → vigente → obsoleto) se rige por PG-01. Este procedimiento define los requisitos específicos del proceso de soldadura.

## 3. Referencias

- ISO 9001:2015, §8.5.1.f — Validación y revalidación periódica de procesos cuyos resultados no pueden verificarse mediante seguimiento o medición posteriores.
- API Specification Q1, 9ª edición — §5.7 (control de producción; validación de procesos).
- ASME Boiler and Pressure Vessel Code, Sección IX — Welding and Brazing Qualifications.
- NACE MR-0175 / ISO 15156 — materiales para servicio sour (H₂S).
- PG-01 — Control de documentos y registros.
- PG-06 — Control de producción y PQP.
- PG-08 — Control de equipos de medición.
- PG-09 — Control de producto no conforme.
- PG-13 — Competencia y capacitación.
- PG-15 — Control de diseño y validación.

## 4. Definiciones

- **Proceso especial**: proceso cuyo resultado no puede verificarse completamente por inspección posterior del producto; sus deficiencias pueden manifestarse solo en servicio. La soldadura es el proceso especial de Vitalmet S.A.
- **WPS (Welding Procedure Specification)**: especificación de procedimiento de soldadura; documento que define las variables del proceso con las que se debe soldar.
- **PQR (Procedure Qualification Record)**: registro de calificación del procedimiento; evidencia de los ensayos que califican al WPS conforme a ASME IX.
- **WPQ (Welder Performance Qualification)**: calificación de habilidad del soldador para un proceso y rango determinados.
- **Variables esenciales**: variables del WPS cuyo cambio fuera del rango calificado exige recalificar (ASME IX).
- **PWHT**: tratamiento térmico post-soldadura.
- **Servicio sour**: servicio con presencia de H₂S en condiciones alcanzadas por NACE MR-0175 / ISO 15156.
- **WPS vigente**: revisión del WPS habilitada para uso operativo (`documentos_controlados.estado` = 'vigente'; ver PG-01).

## 5. Responsabilidades

- **Dirección**: aprueba los WPS y sus revisiones (puesta en vigencia del documento controlado); provee los recursos para calificar procedimientos y soldadores.
- **Responsable de Calidad**: administra WPS, PQR y WPQ como documentos controlados en el módulo Calidad → Documentos del ERP; verifica que cada WPS esté soportado por su PQR; firma el hold point de verificación posterior a soldadura; define los ensayos posteriores aplicables; mantiene el registro de continuidad de los soldadores.
- **Responsable de Producción**: gestiona la soldadura conforme a WPS vigentes (MC-01 §5); asigna a cada operación de soldadura el WPS aplicable y un soldador calificado; asegura que en planta no se suelde sin WPS vigente asociado a la operación; detiene la soldadura ante cualquier desvío de las variables esenciales.
- **Responsable de Compras/Administración**: compra los materiales de aporte según la especificación indicada en el WPS, con proveedores de la AVL (PG-04); contrata el PWHT tercerizado conforme a PG-06 §6.5.

## 6. Desarrollo

### 6.1 Calificación del procedimiento de soldadura (WPS / PQR)

1. Todo WPS se califica conforme a ASME Sección IX mediante su PQR: la probeta se suelda registrando las variables reales y se ensaya según la Sección IX; el PQR documenta los resultados y el rango calificado.
2. WPS y PQR se administran como **documentos controlados individuales** en `documentos_controlados` (PG-01 §6.1), con `tipo` = 'wps' y 'pqr' respectivamente, su `codigo` (WPS-xxx / PQR-xxx), `titulo`, `revision`, `estado` y el PDF firmado en `file_data`. La combinación código + revisión es única en el sistema y solo existe una revisión vigente por código (trigger `fn_doc_vigencia`).
3. Un WPS solo se pone en 'vigente' (botón «Poner vigente», que estampa `aprobado_por` y `fecha_vigencia`) cuando su PQR de soporte está cargado y referenciado en las `observaciones` del WPS. El listado de WPS vigentes se consulta en el módulo Calidad → Documentos filtrando por tipo 'wps' y `estado` = 'vigente' (MC-01 §6.7).
4. Cualquier cambio de una variable esencial fuera del rango calificado exige recalificar: nueva probeta, nuevo PQR y nueva revisión del WPS, tramitada como nueva revisión del documento controlado (PG-01 §6.2). Al ponerla en vigencia, la revisión anterior queda obsoleta automáticamente.

### 6.2 Calificación de soldadores (WPQ)

5. Cada soldador que ejecute soldadura de producción debe estar calificado conforme a ASME Sección IX para el proceso, material y rango aplicables. El certificado WPQ se administra como documento controlado con `tipo` = 'wpq' en `documentos_controlados` (MC-01 §6.7), de modo que el listado de soldadores calificados vigentes se consulta filtrando por tipo 'wpq' y `estado` = 'vigente'.
6. La continuidad de la calificación (mantenimiento por uso del proceso dentro del período que fija ASME IX) se registra en planilla física en la carpeta de calidad, bajo custodia del Responsable de Calidad. Vencida la continuidad, el Responsable de Calidad pasa el WPQ a 'obsoleto' y el soldador debe recalificar antes de volver a soldar producción.
7. La asignación de soldadores a operaciones de soldadura la realiza el Responsable de Producción únicamente entre soldadores con WPQ vigente para el rango requerido; la identidad del operario queda asentada en la operación (`op_operaciones.operario_id`) y en la captura de tiempos (`op_time_entries`, PG-06 §6.4). La competencia general del personal se rige por PG-13.

### 6.3 Asignación del WPS a la operación de soldadura

8. Toda operación de soldadura del routing debe referenciar su WPS por `documento_id`, tanto en el routing modelo (`pqp_plantilla_operaciones.documento_id`, al elaborar la plantilla PQP — PG-06 §6.1) como en el routing real de la OP (`op_operaciones.documento_id`).
9. El sistema garantiza por dos vías que solo se asocien WPS **vigentes**:
   - En la interfaz, los selectores de documento de la operación (modal de paso de la OP y editor de plantillas PQP) solo ofrecen documentos con `estado` = 'vigente'.
   - En la base de datos, el gate `fn_op_quality_gate` (BEFORE INSERT/UPDATE sobre `op_operaciones`) rechaza con excepción cualquier `documento_id` que no apunte a un documento en estado 'vigente' («nadie suelda con un WPS obsoleto»); no es posible asociar documentos en 'borrador' u 'obsoleto'.
10. Al instanciar una plantilla PQP en una OP (RPC `instanciar_pqp`), la referencia al WPS se copia de `pqp_plantilla_operaciones` a `op_operaciones`; como esa copia es un INSERT sobre `op_operaciones`, el gate `fn_op_quality_gate` revalida la vigencia del documento en ese momento. Si el WPS quedó obsoleto desde la creación de la plantilla, la instanciación falla y el Responsable de Calidad debe actualizar la plantilla a la revisión vigente.
11. Cuando una nueva revisión de un WPS pasa a 'vigente' (y la anterior a 'obsoleto'), el Responsable de Calidad verifica las OP abiertas y las plantillas PQP que referencien la revisión anterior y actualiza la referencia a la revisión vigente antes de ejecutar la operación de soldadura pendiente. Esta verificación es un control operativo: el gate valida la vigencia al asignar el documento, no re-bloquea referencias ya asignadas.

### 6.4 Ejecución de la soldadura y verificación posterior

12. La soldadura se ejecuta bajo condiciones controladas: WPS vigente disponible en el punto de uso (consultado desde el ERP, PG-01 §6.3), soldador con WPQ vigente, material de aporte según especificación del WPS y equipos en estado operativo (`herramientas.estado`, MC-01 §6.3).
13. El soldador ejecuta respetando las variables esenciales del WPS. Ante cualquier desvío (parámetros fuera de rango, material de aporte incorrecto, precalentamiento insuficiente), la operación se detiene y se trata como producto potencialmente no conforme (PG-09).
14. La **verificación posterior a soldadura es un hold point** del routing (PG-06 §6.1.4): el sistema impide iniciar o completar operaciones posteriores sin su firma (gate `fn_op_quality_gate`), y la OP no puede cerrarse con el punto sin firmar (gate `fn_op_cierre_gate`). La firma se materializa en `op_operaciones.signoff_usuario_id` / `signoff_at` y solo procede tras verificar con evidencia objetiva (§6.5).

### 6.5 Ensayos posteriores a la soldadura

15. Los ensayos que soportan la firma del hold de soldadura se cargan desde la OP (botón Ensayo) en `registros_calidad`, con `orden_id`, `operacion_id`, `tipo`, `herramienta_id`, `datos`, `resultado` y `firmado_por` (PG-06 §6.3.14). Según el plano y el pedido, aplican: inspección visual (`tipo` = 'visual'), líquidos penetrantes ('liquidos_penetrantes'), partículas magnéticas ('particulas_magneticas'), dureza ('dureza') y el ensayo hidrostático final ('hidrostatico', con `presion_psi`, `sostenimiento_min` y `temperatura_c`).
16. Los instrumentos utilizados deben tener calibración vigente: el sistema bloquea el registro de un ensayo con instrumento vencido (gate `fn_registro_calibracion_gate`; ver PG-08).
17. Un `resultado` = 'no_conforme' impide firmar el hold y dispara el tratamiento de producto no conforme según PG-09 (registro en `no_conformidades` vinculado por `registro_calidad_id` u `orden_id`). La reparación por soldadura de un defecto se ejecuta también bajo WPS calificado y repite la verificación completa.

### 6.6 Tratamiento térmico post-soldadura (PWHT)

18. Cuando el WPS, el plano o el requisito NACE lo exijan, el PWHT se ejecuta como proceso tercerizado conforme a PG-06 §6.5: se registra en `tratamientos` (con `orden_id`, `tipo`, `proveedor_id` sujeto a la AVL, `certificado_nro` y el certificado en PDF adjunto) y la recepción del material tratado es un **hold point** que el Responsable de Calidad firma solo tras verificar el certificado (ciclo térmico, identificación y colada, durezas cuando aplique).

### 6.7 Servicio sour (NACE MR-0175)

19. Cuando el pedido especifica servicio sour, el diseño (PG-15) y el PQP del producto incorporan los requisitos de NACE MR-0175 / ISO 15156: material y condición de tratamiento térmico conformes, y dureza máxima admisible en metal base, zona afectada por el calor y soldadura según la norma.
20. La evidencia de cumplimiento se materializa en: el MTR del material (`certificados`, PG-05), el certificado del tratamiento térmico (`tratamientos`) y el ensayo de dureza posterior a soldadura/PWHT registrado en `registros_calidad` con `tipo` = 'dureza', cuyos valores se asientan en `datos`. Un valor fuera del límite NACE es un `resultado` = 'no_conforme' y se trata según PG-09; el producto no se libera para servicio sour.
21. El certificado de conformidad emitido al despacho (PG-07) declara el cumplimiento NACE MR-0175 únicamente cuando la evidencia anterior está completa y conforme.

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| WPS y PQR (todas las revisiones y su PDF) | `documentos_controlados` tipos 'wps' / 'pqr' (Calidad → Documentos) | Permanente (obsoletos conservados) |
| WPQ (calificación de soldadores) | `documentos_controlados` tipo 'wpq' (Calidad → Documentos) | Permanente (obsoletos conservados) |
| Registro de continuidad de soldadores | Planilla física, carpeta de calidad (fuera del ERP) | 10 años |
| WPS asignado a cada operación de soldadura | `pqp_plantilla_operaciones.documento_id` / `op_operaciones.documento_id` | 10 años (con la OP) |
| Firma del hold de verificación posterior a soldadura | `op_operaciones.signoff_usuario_id` / `signoff_at` | 10 años (con la OP) |
| Ensayos posteriores (visual, LP, PM, dureza, hidrostático) | `registros_calidad` (OP → botón Ensayo) | 10 años (protegidos por `fn_proteger_evidencia`) |
| Certificados de PWHT | `tratamientos` + PDF adjunto | 10 años (protegidos por `fn_proteger_evidencia`) |
| Pista de auditoría de cambios | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
