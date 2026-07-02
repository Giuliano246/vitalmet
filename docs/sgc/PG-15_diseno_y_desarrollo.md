# PG-15 — Control de diseño y validación (diseño y desarrollo de producto)

| Campo | Valor |
|---|---|
| **Código** | PG-15 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.3 · API Q1 §5.4 (Diseño y desarrollo) |

## 1. Propósito

Establecer la metodología para planificar, ejecutar y controlar el diseño y desarrollo de los productos de Vitalmet S.A. (uniones figura 1502, pup joints, couplings y uniones dobles para servicio de alta presión), desde la definición de las entradas hasta la validación del producto y el control de los cambios de diseño, asegurando que el producto resultante cumpla las especificaciones API, los requisitos del cliente y los requisitos legales y reglamentarios aplicables.

## 2. Alcance

Aplica a todo diseño y desarrollo de producto propio de Vitalmet S.A., realizado bajo especificaciones API (6A Annex M / 7K como especificaciones objetivo del monograma) y/o especificaciones particulares de cliente, incluyendo:

- El diseño de productos nuevos y sus variantes dimensionales o de material.
- La emisión y revisión de las salidas del diseño: planos de fabricación, especificaciones de producto y memorias de cálculo.
- La verificación y la validación del diseño, incluyendo el ensayo hidrostático de la primera pieza o prototipo.
- El control de los cambios de diseño y su transferencia a producción.

No aplica al diseño de procesos de fabricación (routing y puntos de control, cubiertos por PG-06) ni a la calificación de procedimientos de soldadura (PG-16). Los planos provistos por el cliente no constituyen diseño propio: se controlan como documentos de origen externo según PG-01 §6.4, y este procedimiento aplica solo a la verificación de su fabricabilidad.

## 3. Referencias

- ISO 9001:2015, §8.3 — Diseño y desarrollo de los productos y servicios.
- API Specification Q1, 9ª edición — §5.4 Design and Development.
- API 6A Annex M / API 7K — especificaciones de producto objetivo del monograma.
- ASME Sección IX — calificación de soldadura (cuando el diseño incluye juntas soldadas).
- NACE MR-0175 / ISO 15156 — materiales para servicio sour, cuando el uso previsto lo requiera.
- PG-01 — Control de documentos y registros.
- PG-03 — Revisión de requisitos del cliente.
- PG-06 — Control de producción y PQP.
- PG-14 — Gestión del cambio (MoC).
- PG-16 — Control de soldadura y servicio sour.

## 4. Definiciones

- **Entradas del diseño**: requisitos funcionales, dimensionales, de material y de desempeño que el producto debe satisfacer (especificación API, requisito de cliente, norma de material, presión de trabajo y de prueba).
- **Salidas del diseño**: planos de fabricación, especificaciones de producto y memorias de cálculo que materializan el diseño y contra los cuales se fabrica e inspecciona.
- **Revisión de diseño**: examen sistemático del diseño para evaluar su capacidad de cumplir los requisitos e identificar problemas.
- **Verificación de diseño**: comprobación de que las salidas del diseño cumplen las entradas (cálculo, comparación con diseño probado, revisión de plano).
- **Validación de diseño**: comprobación de que el producto resultante es capaz de cumplir los requisitos para su uso previsto; en Vitalmet S.A. su forma principal es el **ensayo hidrostático** del producto a la presión de prueba especificada.
- **Plano vigente**: revisión del plano habilitada para fabricación (`documentos_controlados.estado` = 'vigente'; ver PG-01).
- **Carpeta de diseño**: legajo (físico o digital, en la carpeta de calidad) que reúne para cada producto las entradas, cálculos, revisiones, verificaciones y la evidencia de validación.

## 5. Responsabilidades

- **Dirección**: aprueba el inicio de cada desarrollo y sus recursos; aprueba las salidas del diseño (puesta en vigencia del plano/especificación como documento controlado); aprueba los cambios de diseño significativos por la vía de la gestión del cambio (PG-14).
- **Responsable de Calidad**: administra los planos y especificaciones como documentos controlados en el módulo Calidad → Documentos del ERP (PG-01); participa en las revisiones de diseño; verifica que la validación (ensayo hidrostático y ensayos complementarios) esté completa y conforme antes de dar por validado el diseño; custodia la carpeta de diseño.
- **Responsable de Producción**: participa en las revisiones de diseño aportando la fabricabilidad (mecanizado, soldadura, tratamiento térmico); asegura que en planta solo se fabrique contra planos en estado vigente; elabora junto con Calidad la plantilla PQP del producto nuevo (PG-06).
- **Responsable de Compras/Administración**: verifica la disponibilidad y el costo de la materia prima especificada (AISI 4130 Q&T, API 5L) con proveedores de la AVL antes de congelar el diseño.

## 6. Desarrollo

### 6.1 Planificación del diseño

1. Todo desarrollo se inicia por decisión de la Dirección, a partir de un requerimiento comercial (presupuesto en curso, PG-03), de una especificación API objetivo o de una mejora interna.
2. Al inicio, el Responsable de Calidad abre la **carpeta de diseño** del producto, donde se planifican las etapas, los responsables y los puntos de revisión, verificación y validación. Como mínimo, todo diseño transita las etapas: entradas → diseño (plano/especificación en borrador) → revisión → verificación → validación → liberación.
3. Las interfaces entre roles (Calidad, Producción, Compras) se resuelven en las revisiones de diseño (§6.4); no se libera un diseño con observaciones de fabricabilidad o de abastecimiento abiertas.

### 6.2 Entradas del diseño

4. Las entradas del diseño se documentan en la carpeta de diseño e incluyen, según aplique:
   - La especificación API aplicable (API 6A Annex M, API 7K) en su edición declarada, controlada como documento de origen externo (PG-01 §6.4).
   - Los requisitos particulares del cliente, tomados de la revisión de requisitos (PG-03) sobre el presupuesto correspondiente (`presupuestos`).
   - Los requisitos de material: AISI 4130 forjado con temple y revenido (Q&T) o API 5L, con MTR obligatorio; requisitos NACE MR-0175 cuando el servicio es sour.
   - Presión de trabajo y presión de prueba hidrostática (hasta 22.000 psi en banco propio).
   - Requisitos legales y reglamentarios aplicables.
   - Información de diseños similares previos y lecciones de no conformidades (PG-09/PG-10).
5. Las entradas se revisan para verificar que son completas, no ambiguas y no contradictorias entre sí antes de comenzar el diseño. Los conflictos se resuelven con el cliente (PG-03) o contra la especificación API, que prevalece en los requisitos de seguridad del producto.

### 6.3 Salidas del diseño

6. Las salidas del diseño son los **planos de fabricación y las especificaciones de producto**, y se emiten como **documentos controlados** en el módulo Calidad → Documentos del ERP (tabla `documentos_controlados`), conforme a PG-01: cada plano/especificación se registra con su `codigo` (el código de plano), `titulo`, `revision`, `estado` y el PDF firmado en `file_data`. La combinación código + revisión es única en el sistema (restricción UNIQUE sobre `documentos_controlados.codigo, revision`) y solo puede existir una revisión vigente por código (trigger `fn_doc_vigencia`).
7. Dado que el catálogo de tipos de `documentos_controlados.tipo` no incluye un tipo específico para planos, los planos y especificaciones de producto se cargan con `tipo` = 'otro', identificándolos por su prefijo de código de plano. Las memorias de cálculo permanecen en la carpeta de diseño.
8. Las salidas del diseño deben: cumplir las entradas (§6.2), proveer la información necesaria para comprar (material, dimensiones de barra), fabricar (cotas, tolerancias, roscas, sellos, requisitos de soldadura con referencia al WPS aplicable — PG-16) e inspeccionar (características a verificar, presión y tiempo de sostenimiento del hidro), y especificar las características esenciales para el uso seguro del producto (presión nominal, marcado, límites de servicio).

### 6.4 Revisión y verificación del diseño

9. **Revisión de diseño**: en las etapas planificadas (como mínimo, antes de liberar el plano para la primera fabricación), la Dirección, el Responsable de Calidad y el Responsable de Producción revisan el diseño contra las entradas. La minuta de revisión, con los participantes, las observaciones y su resolución, se archiva en la carpeta de diseño.
10. **Verificación de diseño**: antes de la validación se verifica que las salidas cumplen las entradas mediante uno o más de los siguientes métodos, documentados en la carpeta de diseño: memoria de cálculo (espesores, áreas resistentes, presión de prueba), comparación con un diseño similar probado, o revisión independiente del plano por alguien distinto de quien lo elaboró.
11. Mientras el diseño está en revisión/verificación, el plano permanece en `documentos_controlados.estado` = 'borrador'. En ese estado el documento no es apto para uso operativo: el sistema impide vincular documentos en borrador a operaciones de producción (gate `fn_op_quality_gate` sobre `op_operaciones.documento_id`; ver PG-01 §6.2).

### 6.5 Validación del diseño

12. La validación demuestra que el producto fabricado según el diseño cumple los requisitos del uso previsto. Su forma principal es el **ensayo hidrostático de la primera pieza o prototipo** en el banco propio (hasta 22.000 psi, manómetro patrón WIKA CPG1500), a la presión de prueba y con el tiempo de sostenimiento especificados en el plano, conforme al instructivo IT-01.
13. El ensayo de validación se registra en el ERP como registro de calidad: desde la OP de la primera fabricación (botón Ensayo) se asienta en `registros_calidad` con `tipo` = 'hidrostatico', `orden_id`, `operacion_id`, `herramienta_id` (el manómetro patrón), `datos` (`presion_psi`, `sostenimiento_min`, `temperatura_c`), `resultado` y `firmado_por`. El instrumento debe tener calibración vigente: el sistema bloquea el registro con instrumento vencido (gate `fn_registro_calibracion_gate`; ver PG-08).
14. Cuando las entradas lo requieran, la validación se completa con ensayos complementarios registrados igualmente en `registros_calidad`: dureza (`tipo` = 'dureza', obligatoria para verificar límites NACE MR-0175 en servicio sour), líquidos penetrantes o partículas magnéticas sobre juntas soldadas (ver PG-16).
15. Un `resultado` = 'no_conforme' en el ensayo de validación impide liberar el diseño: se trata según PG-09 y el diseño vuelve a la etapa que corresponda (§6.4). Solo con la validación conforme el plano pasa a `estado` = 'vigente' (botón «Poner vigente» del módulo Calidad → Documentos), quedando estampados `aprobado_por` y `fecha_vigencia` (trigger `fn_doc_vigencia`).

### 6.6 Transferencia del diseño a producción

16. La fabricación seriada solo procede contra planos vigentes. En cada OP, el plano se identifica en `ordenes_produccion.codigo_plano`; dado que ese campo es texto libre, el Responsable de Producción verifica al emitir la OP que el código asentado corresponda a la revisión vigente en `documentos_controlados`.
17. Para productos críticos, el diseño liberado se traduce en su plantilla PQP (`pqp_plantillas` / `pqp_plantilla_operaciones`, PG-06), cuyas operaciones referencian por `documento_id` los documentos técnicos vigentes aplicables (WPS, instructivos). El sistema exige que esas referencias apunten a documentos en estado 'vigente' (gate `fn_op_quality_gate`).

### 6.7 Control de cambios de diseño

18. Todo cambio a un plano o especificación liberados se tramita como **nueva revisión del documento controlado** (PG-01 §6.2): en el módulo Calidad → Documentos, el botón «Nueva revisión» crea un nuevo registro con el mismo `codigo` y la `revision` incrementada, en estado 'borrador'. El cambio se revisa y verifica según §6.4 y, cuando altera la función, el material, la presión nominal o la geometría resistente, se valida nuevamente según §6.5 antes de ponerlo en vigencia.
19. Al poner la nueva revisión en 'vigente', el sistema obsoleta automáticamente la revisión anterior del mismo código (trigger `fn_doc_vigencia`), garantizando que en planta no coexistan dos revisiones utilizables del mismo plano. Las revisiones obsoletas se conservan para consulta histórica y no son asociables a operaciones de producción (gate `fn_op_quality_gate`).
20. Los cambios de diseño que impacten en el producto ya vendido, en los procesos de fabricación, en los proveedores o en los riesgos del SGC se gestionan además por la **gestión del cambio** (PG-14), incluyendo la evaluación de OP abiertas que referencien la revisión anterior y la notificación al cliente cuando el contrato lo requiera.
21. El motivo del cambio, la evaluación de impacto y su aprobación quedan documentados en `documentos_controlados.observaciones` de la nueva revisión y, en los cambios significativos, en el registro de MoC (PG-14). La historia completa de estados de cada documento queda asentada en `audit_log` (PG-01 §6.5).

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Planos y especificaciones de producto (todas las revisiones y su PDF) | `documentos_controlados` (Calidad → Documentos) | Permanente (obsoletos conservados) |
| Carpeta de diseño: entradas, memorias de cálculo, minutas de revisión y verificaciones | Carpeta de calidad (fuera del ERP) | 10 años |
| Validación del diseño: ensayo hidrostático y ensayos complementarios | `registros_calidad` (OP → botón Ensayo) | 10 años (protegidos por `fn_proteger_evidencia`) |
| Vinculación diseño–producción | `ordenes_produccion.codigo_plano` / `op_operaciones.documento_id` | 10 años (con la OP) |
| Registro de gestión del cambio (cuando aplique) | Según PG-14 | 10 años |
| Pista de auditoría de cambios de documentos | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
