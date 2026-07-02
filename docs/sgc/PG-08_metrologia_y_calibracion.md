# PG-08 — Control de equipos de medición (metrología y calibración)

| Campo | Valor |
|---|---|
| **Código** | PG-08 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §7.1.5 (recursos de seguimiento y medición) · API Q1 §4.4.4 y §5.7.7 |

## 1. Propósito

Establecer la metodología para identificar, calibrar y controlar los instrumentos de medición y ensayo que afectan la conformidad del producto, asegurando que ninguna inspección ni ensayo se realice con un instrumento de calibración vencida, que cada calibración quede registrada con su certificado, y que la evidencia de medición (en particular la prueba hidrostática) se conserve con los datos que exigen las especificaciones aplicables.

## 2. Alcance

Aplica a todos los instrumentos de medición y ensayo utilizados en inspecciones de entrada, de proceso y finales de Vitalmet S.A., registrados en el módulo **Inventario → Herramientas** del ERP (tabla `herramientas`) y marcados como instrumentos de medición (`requiere_calibracion` = verdadero). Incluye, entre otros, el manómetro patrón WIKA CPG1500 y el banco de prueba hidrostática de hasta 22.000 psi, calibres, micrómetros y durómetros.

Incluye asimismo el registro de la evidencia de inspección y ensayo (`registros_calidad`) en cuanto al instrumento utilizado y a los datos de medición capturados. La ejecución técnica de cada ensayo se rige por su instructivo (IT-01 para la prueba hidrostática, IT-02 para dimensional y visual); la definición de qué operaciones requieren inspección se rige por PG-06.

No aplica a las herramientas de planta que no realizan mediciones con efecto sobre la conformidad (`requiere_calibracion` = falso), cuyo estado se administra como mantenimiento de equipos (MC-01 §6.3).

## 3. Referencias

- ISO 9001:2015, §7.1.5 — Recursos de seguimiento y medición.
- API Specification Q1 — control de equipos de ensayo, medición y monitoreo.
- API 6A — requisitos de registro de la prueba hidrostática (presión, tiempo de sostenimiento, manómetro utilizado).
- MC-01 — Manual de Calidad (objetivo de calidad Nº 4).
- PG-01 — Control de documentos y registros.
- PG-04 — Compras y evaluación de proveedores (laboratorios de calibración en la AVL).
- PG-06 — Control de producción y PQP (inspecciones y ensayos del routing).
- PG-09 — Control de producto no conforme.
- IT-01 — Instructivo de prueba hidrostática; IT-02 — Instructivo de inspección dimensional y visual.
- PC-02 — Plan de contingencia: falla del banco de prueba o del instrumento patrón.

## 4. Definiciones

- **Instrumento de medición**: herramienta registrada en `herramientas` con `requiere_calibracion` = verdadero; solo puede usarse en inspecciones con calibración vigente.
- **Calibración**: comparación del instrumento contra un patrón trazable, realizada por un laboratorio externo, con resultado 'conforme' o 'no_conforme' y certificado emitido.
- **Vencimiento de calibración**: fecha límite de uso del instrumento (`herramientas.vencimiento_calibracion`), calculada por el sistema como fecha de calibración + frecuencia definida.
- **Gate de calibración**: control automático del ERP (`fn_registro_calibracion_gate`) que rechaza el registro de una inspección cuyo instrumento requiere calibración y la tiene vencida o nunca realizada.
- **Registro de calidad**: evidencia de una inspección o ensayo, registrada en `registros_calidad` (ver PG-06 §6.3).

## 5. Responsabilidades

- **Responsable de Calidad**: mantiene el inventario de instrumentos de medición y su plan de calibración (frecuencias); gestiona las calibraciones externas con laboratorios de la AVL; registra los resultados y archiva los certificados; dispone de los instrumentos no conformes; evalúa la validez de las mediciones previas cuando un instrumento resulta no conforme.
- **Responsable de Producción**: verifica antes de cada inspección que el instrumento a utilizar esté identificado y con calibración vigente; aparta físicamente los instrumentos bloqueados; informa de inmediato golpes, caídas o sospechas de descalibración.
- **Responsable de Compras**: contrata las calibraciones exclusivamente con laboratorios incluidos en la lista de proveedores aprobados (AVL), conforme a PG-04.
- **Dirección**: provee los recursos para cumplir el plan de calibración; respalda el bloqueo de instrumentos aun cuando afecte plazos de producción.

## 6. Desarrollo

### 6.1 Identificación y alta de instrumentos

1. Todo instrumento de medición se registra en el módulo Inventario → Herramientas (tabla `herramientas`) con `codigo`, `nombre`, `estado` y `ubicacion`. En la sección «Metrología — calibración» de la ficha se define:
   - `requiere_calibracion` = «Sí — instrumento de medición»;
   - `frecuencia_calibracion_meses` (frecuencia de calibración; la definición de la frecuencia es obligatoria: sin ella el sistema no puede calcular el vencimiento y lo advierte al registrar la calibración);
   - `patron_referencia` (patrón o referencia de trazabilidad, ej.: patrón WIKA CPG1500).
2. Los campos `fecha_ultima_calibracion` y `vencimiento_calibracion` **no se cargan a mano**: los administra el sistema a partir de cada calibración registrada (ver 6.2).
3. Un instrumento recién dado de alta que requiere calibración nace sin vencimiento válido y por lo tanto **bloqueado para inspecciones** hasta registrar su primera calibración conforme.

### 6.2 Registro de calibraciones

4. Las calibraciones se realizan en laboratorios externos incluidos en la AVL. Cada calibración se registra desde el botón **Calibrar** de la herramienta (tabla `calibraciones`), con: `fecha`, `resultado` ('conforme' / 'no_conforme'), `certificado_nro`, laboratorio (`laboratorio_id`, clave foránea a `proveedores` — el laboratorio queda así sujeto a la evaluación de proveedores), el PDF del certificado adjunto (`file_data`) y observaciones. El sistema estampa automáticamente quién registró la calibración (`created_by`).
5. **Calibración conforme**: el sistema actualiza automáticamente `fecha_ultima_calibracion` y calcula `vencimiento_calibracion` = fecha de calibración + `frecuencia_calibracion_meses` (trigger `fn_calibracion_aplicar`). El instrumento queda habilitado hasta ese vencimiento.
6. **Calibración no conforme**: el mismo trigger anula el vencimiento (`vencimiento_calibracion` = NULL) y pasa el instrumento a `estado` = 'mantenimiento'. El instrumento queda automáticamente bloqueado para inspecciones (ver 6.3) hasta su reparación/ajuste y una nueva calibración conforme.
7. Ante una calibración no conforme, el Responsable de Calidad **evalúa la validez de las mediciones realizadas** con ese instrumento desde su última calibración conforme (consultando los `registros_calidad` con ese `herramienta_id`) y, si alguna aceptación de producto queda en duda, abre la no conformidad correspondiente según PG-09.
8. El historial completo de calibraciones de cada instrumento se consulta en el propio modal de calibración (fecha, resultado, certificado y laboratorio de cada una).

### 6.3 Gate de uso: calibración vencida = instrumento inutilizable

9. El sistema **impide registrar una inspección o ensayo con un instrumento vencido**: al insertar un registro en `registros_calidad`, el trigger `fn_registro_calibracion_gate` verifica el instrumento (`herramienta_id`) y, si requiere calibración y su `vencimiento_calibracion` es nulo o anterior a la fecha, rechaza la operación con error explícito. Este control es de base de datos: no puede ser salteado desde la interfaz.
10. El mismo gate estampa automáticamente al firmante de la inspección (`firmado_por`).
11. Este control materializa el objetivo de calidad Nº 4 de MC-01: cero inspecciones con instrumento vencido; el indicador verifica la ausencia de excepciones.
12. Como ayuda operativa, el selector de instrumento del modal de Ensayo señala cada instrumento como «✓ calibrado» o «⛔ CALIBRACIÓN VENCIDA» antes de intentar el registro.

### 6.4 Vigilancia de vencimientos

13. El módulo Inventario → Herramientas muestra por instrumento el estado de calibración con semáforo: **SIN CALIBRAR** (nunca calibrado), **VENCIDA** (fecha superada), **VENCE** (dentro de los próximos 30 días) y **OK hasta** (vigente), junto con el contador «Calibración vencida» en las estadísticas del módulo.
14. El panel «Para hoy» del dashboard alerta: (a) instrumentos con calibración vencida — bloqueados para inspecciones — y (b) calibraciones que vencen en los próximos 30 días, para gestionar el envío al laboratorio antes del vencimiento y no frenar producción.
15. Los instrumentos dados de baja (`estado` = 'dada-de-baja') salen del plan de calibración y de las alertas.
16. Un instrumento que sufra un golpe, caída o condición que haga dudar de su exactitud se trata como no conforme: se aparta, se registra una calibración 'no_conforme' (que lo bloquea y lo envía a mantenimiento) o se envía directamente a calibrar, y se aplica el punto 7.

### 6.5 Registro de la evidencia de medición

17. Cada inspección o ensayo se registra en `registros_calidad` desde la OP (botón Ensayo) o la recepción, con `tipo` ('hidrostatico', 'dimensional', 'visual', 'dureza', 'liquidos_penetrantes', 'particulas_magneticas', 'otro'), el instrumento utilizado (`herramienta_id`), los datos de medición (`datos`, JSON), `resultado`, firmante y PDF adjunto cuando exista informe (ver PG-06 §6.3).
18. **Prueba hidrostática**: el registro captura obligatoriamente la presión (`presion_psi`) y el tiempo de sostenimiento (`sostenimiento_min`) — el sistema no permite guardar un hidro sin ambos datos — más la temperatura (`temperatura_c`) y el manómetro utilizado (`herramienta_id`). Con ello el registro cubre lo que exige API 6A: presión, tiempo de sostenimiento y manómetro usado. La ejecución del ensayo se rige por IT-01.
19. Ante la falla del banco de prueba o del instrumento patrón se aplica el plan de contingencia PC-02.

### 6.6 Protección de la evidencia metrológica

20. Las tablas `herramientas`, `calibraciones` y `registros_calidad` tienen auditoría de cambios (trigger `trg_audit` → `audit_log`). Además, `calibraciones` y `registros_calidad` están protegidas contra borrado dentro del período de retención (trigger `fn_proteger_evidencia`), conforme a PG-01 §6.5.

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Inventario de instrumentos y su estado de calibración | `herramientas` (Inventario → Herramientas) | Permanente (registro vivo) |
| Historial de calibraciones con certificado del laboratorio (PDF) | `calibraciones` (botón Calibrar de la herramienta) | 10 años (protegidas por `fn_proteger_evidencia`) |
| Registros de inspección y ensayo (incl. hidrostática con presión y sostenimiento) | `registros_calidad` (OP → botón Ensayo / recepción) | 10 años (protegidos por `fn_proteger_evidencia`) |
| Vencimientos y bloqueos aplicados al instrumento | `herramientas.fecha_ultima_calibracion` / `vencimiento_calibracion` / `estado` (administrados por trigger) | Con el instrumento |
| Pista de auditoría de cambios | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición vigente adquirida antes de la auditoría de certificación.*
