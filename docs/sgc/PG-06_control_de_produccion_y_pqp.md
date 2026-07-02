# PG-06 — Control de Producción y Plan de Calidad de Producto (PQP)

| Campo | Valor |
|---|---|
| **Código** | PG-06 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.5.1 · API Q1 §5.7 (Product Quality Plan) / §5.8 (Control de producción) |

## 1. Propósito

Establecer la metodología para planificar y ejecutar la producción bajo condiciones controladas, mediante Planes de Calidad de Producto (PQP) que definen el routing de operaciones, los puntos de retención (hold points) y de presencia (witness points), los documentos técnicos aplicables a cada operación y los registros de calidad asociados, para todos los productos fabricados por Vitalmet S.A. (uniones figura 1502, pup joints, couplings y uniones dobles).

## 2. Alcance

Aplica a todas las órdenes de producción (OP) emitidas en el ERP VitalStock, desde su creación hasta su cierre, incluyendo:

- La creación y mantenimiento de plantillas PQP por producto crítico.
- La instanciación del PQP en cada OP y la ejecución de su routing de operaciones.
- La gestión de puntos hold y witness, y su firma (signoff).
- La captura de tiempos por operación.
- Los procesos tercerizados de tratamiento térmico (temple y revenido Q&T, PWHT).
- La generación del producto terminado (PT) con su trazabilidad heredada.

No aplica al control de la soldadura en sí (calificación WPS/PQR/WPQ, cubierta por el documento correspondiente del SGC) ni al control de equipos de medición (PG-08).

## 3. Referencias

- ISO 9001:2015, §8.5.1 — Control de la producción y de la provisión del servicio.
- API Specification Q1, cláusulas de Product Quality Plan y control de producción.
- ASME Sección IX — Calificación de soldadura (WPS aplicables citados en el routing).
- NACE MR-0175 — Requisitos de materiales para servicio sour, cuando el pedido lo especifique.
- PG-07 — Identificación y trazabilidad.
- PG-08 — Control de equipos de medición.
- PG-09 — Producto no conforme.
- Procedimiento de control de documentos del SGC (documentos controlados tipo 'pqp', 'wps', 'instructivo').

## 4. Definiciones

- **PQP (Product Quality Plan)**: plan de calidad de producto; secuencia modelo de operaciones con sus puntos de control, documentos aplicables y tiempos estimados, para un producto determinado.
- **Hold point (punto de retención)**: operación que detiene el avance de la producción hasta que un responsable autorizado la firma tras verificar el cumplimiento del requisito.
- **Witness point (punto de presencia)**: operación que requiere firma de verificación, pero que no detiene el avance de las operaciones posteriores.
- **Routing**: secuencia ordenada de operaciones de una OP.
- **Signoff**: firma electrónica de un punto de control, con identidad del firmante y fecha/hora.
- **OP**: orden de producción.
- **PT**: producto terminado.

## 5. Responsabilidades

- **Dirección**: aprueba las plantillas PQP y sus revisiones (aprobación del documento controlado tipo 'pqp'). Provee los recursos para cumplir los puntos de control.
- **Responsable de Calidad**: elabora y mantiene las plantillas PQP; define qué operaciones son hold o witness; firma los signoff de los puntos de control de calidad; verifica los certificados de tratamiento térmico tercerizado antes de liberar la operación asociada.
- **Responsable de Producción**: crea las OP, instancia el PQP, asigna operarios y máquinas, ejecuta el routing, registra los tiempos por operación y no avanza sobre puntos de retención sin firma.
- **Responsable de Compras**: gestiona la contratación del tratamiento térmico tercerizado exclusivamente con proveedores aprobados de la lista de proveedores (AVL), conforme al procedimiento de compras del SGC.

## 6. Desarrollo

### 6.1 Elaboración de la plantilla PQP

1. Para cada producto crítico (uniones figura 1502, pup joints, couplings, uniones dobles), el Responsable de Calidad elabora una plantilla PQP en el ERP (módulo Calidad → Plantillas PQP), registrada en `pqp_plantillas` con `codigo` (ej. PQP-1502), `producto` y `documento_id`.
2. El PQP tiene además su documento controlado asociado: un registro en `documentos_controlados` con `tipo` = 'pqp', con su `codigo`, `revision`, `estado` y `file_data` (PDF firmado). Solo puede referenciarse un documento en estado 'vigente'; al poner una nueva revisión en 'vigente', el sistema obsoleta automáticamente las revisiones anteriores del mismo código (trigger `fn_doc_vigencia`).
3. El routing modelo se carga en `pqp_plantilla_operaciones`, definiendo para cada operación: `secuencia`, `nombre`, `tipo_punto` ('normal' | 'hold' | 'witness'), `documento_id` (el WPS o instructivo vigente aplicable a la operación) y `tiempo_estimado_min`.
4. Criterios mínimos para definir puntos de control en productos de alta presión:
   - Inspección dimensional de roscas y sellos: **hold**.
   - Soldadura conforme WPS calificado (ASME Sección IX): la operación referencia el WPS por `documento_id`; la verificación posterior a soldadura es **hold**.
   - Recepción y verificación del certificado de tratamiento térmico tercerizado (Q&T / PWHT): **hold**.
   - Prueba hidrostática en banco (hasta 22.000 psi): **hold**.
   - Ensayos no destructivos (líquidos penetrantes, partículas magnéticas) cuando el plano o el pedido lo requieran: **hold** o **witness** según criticidad definida por el Responsable de Calidad.
   - Verificaciones intermedias de proceso (control visual, marcado): **witness** o 'normal' según corresponda.
5. Cuando el cliente exija presenciar un punto (inspección de tercera parte o del cliente), el Responsable de Calidad lo configura como 'witness' o 'hold' según lo acordado contractualmente, y coordina la notificación al cliente por los medios habituales (correo; registro en carpeta de calidad si el cliente lo requiere documentado).

### 6.2 Creación de la OP e instanciación del PQP

6. El Responsable de Producción crea la OP en el ERP (módulo Producción), registrada en `ordenes_produccion` con `nro`, `pieza`, `codigo_plano`, `cantidad`, `barra_id`, `lote_pt`, `fecha` y `operario`.
7. La materia prima asignada debe estar liberada: el sistema impide consumir barras cuyo `estado_calidad` sea distinto de 'aceptado' (RPC `consumir_barra`). La liberación de materia prima se rige por el procedimiento de compras e inspección de entrada del SGC.
8. Al crear la OP de un producto con PQP, se instancia el plan mediante el RPC `instanciar_pqp(orden_id, plantilla_id)`, que copia el routing modelo de `pqp_plantilla_operaciones` a `op_operaciones`, incluyendo `secuencia`, `nombre`, `tipo_punto`, `documento_id` y `tiempo_estimado_min`.
9. Queda prohibido fabricar productos críticos sin PQP instanciado. Si un producto aún no tiene plantilla, el Responsable de Calidad debe crearla antes de emitir la OP.

### 6.3 Ejecución del routing y puntos de control

10. Cada operación de `op_operaciones` se ejecuta según su `secuencia`, con `maquina` y `operario_id` asignados, y transita los estados 'pendiente' → 'en_curso' → 'completada'.
11. Cada operación se ejecuta conforme al documento técnico vigente que referencia su `documento_id` (WPS para soldadura, instructivo de trabajo para el resto). El sistema exige que `documento_id` apunte únicamente a documentos en estado 'vigente' (gate `fn_op_quality_gate`); no es posible asociar documentos en 'borrador' u 'obsoleto'.
12. **Hold points**: el sistema impide iniciar o completar cualquier operación posterior a un hold point sin firmar, y además impide completar el propio hold sin su signoff (gate `fn_op_quality_gate`). La firma se materializa en `op_operaciones.signoff_usuario_id` y `signoff_at`, y constituye el registro de liberación del punto.
13. **Witness points**: requieren su propio signoff (`signoff_usuario_id` / `signoff_at`) para completarse, pero no bloquean el avance de las operaciones siguientes (gate `fn_op_quality_gate`). Si el punto era presenciado por el cliente y éste renuncia por escrito a presenciarlo, el Responsable de Calidad firma dejando la evidencia de la renuncia adjunta al registro de calidad correspondiente.
14. La firma de un hold o witness solo procede tras verificar el requisito con evidencia objetiva. Cuando la verificación es una inspección o ensayo (dimensional, visual, hidrostática, dureza, LP, PM), la evidencia se carga desde la OP (botón Ensayo) en `registros_calidad`, con `orden_id`, `operacion_id`, `tipo`, `herramienta_id`, `datos` (para hidrostática: `presion_psi`, `sostenimiento_min`, `temperatura_c`), `resultado` y `firmado_por`. El instrumento utilizado debe tener calibración vigente: el sistema bloquea el uso de instrumentos vencidos en una inspección (gate `fn_registro_calibracion_gate`; ver PG-08).
15. Un resultado `registros_calidad.resultado` = 'no_conforme' impide firmar el punto y dispara el tratamiento de producto no conforme según PG-09 (apertura de registro en `no_conformidades` vinculado por `registro_calidad_id` u `orden_id`).

### 6.4 Captura de tiempos

16. Los tiempos reales de cada operación se capturan en `op_time_entries` desde el modal Captura de tiempos de la OP, asociados a la operación y al operario. Estos registros alimentan el análisis de desvíos contra `tiempo_estimado_min` y la mejora de las plantillas PQP.

### 6.5 Tratamiento térmico tercerizado (Q&T / PWHT)

17. El tratamiento térmico es un proceso tercerizado y se gestiona colgado de la OP, en la tabla `tratamientos`, con `orden_id`, `tipo`, `proveedor_id`, `fecha`, `certificado_nro`, `certificado_id` y el certificado en PDF adjunto.
18. El `proveedor_id` del tratamiento es FK a `proveedores` y queda por lo tanto sujeto a la AVL: solo se contratan tratamientos con proveedores con `aprobado` = true, `criticidad` y `alcance_aprobacion` acordes, y evaluación no vencida (`fecha_proxima_evaluacion`), conforme al procedimiento de compras del SGC.
19. La operación del routing asociada a la recepción del material tratado es un **hold point**: el Responsable de Calidad verifica el certificado del tratamiento (identificación del material, colada, ciclo térmico, durezas cuando aplique, cumplimiento NACE MR-0175 si el servicio es sour) antes de firmar. Sin certificado cargado en `tratamientos` no se firma el hold, y el sistema no permite avanzar sobre él (gate `fn_op_quality_gate`).

### 6.6 Cierre de la OP y generación del producto terminado

20. El sistema impide pasar la OP a 'completada' si existen hold o witness points sin firmar (gate `fn_op_cierre_gate`). El cierre de la OP equivale, por lo tanto, a la liberación final del producto: todos los puntos de control fueron verificados y firmados.
21. Al cierre se genera el producto terminado en `productos_terminados`, con `lote`, `pieza`, `cantidad`, `barra_id` y `orden_id`. El PT hereda automáticamente el heat number de la barra de origen: `productos_terminados.nro_colada` se propaga por trigger (`fn_pt_colada`) desde `barras.nro_colada` (ver PG-07).
22. Si la OP se suspende (`estado` = 'suspendida'), el material en proceso conserva su identificación de lote y OP; la reanudación retoma el routing en la operación pendiente, sin saltear puntos de control.

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Plantilla PQP (routing modelo) | `pqp_plantillas` / `pqp_plantilla_operaciones` (Calidad → Plantillas PQP) | Permanente (documento vivo) |
| Documento PQP controlado (PDF firmado) | `documentos_controlados` tipo 'pqp' (Calidad → Documentos) | 10 años tras obsolescencia |
| Orden de producción y su routing ejecutado | `ordenes_produccion` / `op_operaciones` (Producción) | 10 años |
| Firmas de hold/witness | `op_operaciones.signoff_usuario_id` / `signoff_at` | 10 años (con la OP) |
| Registros de inspección y ensayo | `registros_calidad` (OP → botón Ensayo) | 10 años (protegidos por `fn_proteger_evidencia`) |
| Certificados de tratamiento térmico | `tratamientos` + PDF adjunto | 10 años (protegidos por `fn_proteger_evidencia`) |
| Tiempos por operación | `op_time_entries` (modal Captura de tiempos) | 5 años |
| Pista de auditoría de cambios | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición vigente adquirida antes de la auditoría de certificación.*
