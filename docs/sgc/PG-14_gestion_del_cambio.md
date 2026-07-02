# PG-14 — Gestión del cambio (MoC)

| Campo | Valor |
|---|---|
| **Código** | PG-14 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §6.3 (Planificación de los cambios) · API Q1 §5.11 (Management of Change — MoC) |

## 1. Propósito

Establecer la metodología para identificar, evaluar, aprobar, planificar, comunicar y
verificar los cambios que puedan afectar la conformidad del producto o la integridad del
Sistema de Gestión de la Calidad (SGC) de Vitalmet S.A., asegurando que ningún cambio
significativo se implemente sin evaluación de riesgos previa ni aprobación de la Dirección.

## 2. Alcance

Aplica a los cambios planificados de las siguientes categorías:

1. **Diseño de producto**: modificación de planos, especificaciones o criterios de aceptación
   (la ejecución técnica del cambio de diseño se rige por PG-15; este procedimiento gobierna
   su evaluación, aprobación y comunicación).
2. **Proceso de fabricación**: cambio de secuencia u operaciones del routing (plantillas PQP),
   de método, de parámetros, de máquina o equipo crítico, o de WPS aplicable.
3. **Proveedor crítico**: cambio o incorporación de proveedor de materia prima crítica, de
   tratamiento térmico tercerizado o de laboratorio de calibración (PG-04).
4. **Estructura organizacional y personal clave**: cambios que afecten los roles definidos en
   MC-01 §5.
5. **Sistema informático (ERP VitalStock)**: cambios al esquema de datos, a los controles del
   sistema (gates, triggers, RPCs), a la lógica de cálculo de indicadores o a la operatoria de
   los módulos, dado que el SGC opera y se registra en el ERP (MC-01 §4).

No constituye MoC la corrección editorial de un documento ni el cambio que no afecta la
conformidad del producto ni un control del SGC; en caso de duda, el Responsable de Calidad
decide si el cambio se tramita por este procedimiento.

## 3. Referencias

- ISO 9001:2015, §6.3 — Planificación de los cambios.
- API Specification Q1, 9ª edición — §5.11 Management of Change (MoC).
- MC-01 — Manual de Calidad (responsabilidades §5; definición del ERP §4).
- PG-01 — Control de documentos y registros.
- PG-02 — Gestión de riesgos (metodología de evaluación; disparadores de AR-01).
- PG-04 — Compras y evaluación de proveedores (AVL).
- PG-10 — Acciones correctivas y preventivas (CAPA).
- PG-13 — Competencia y capacitación.
- PG-15 — Control de diseño y validación.

## 4. Definiciones

- **MoC (Management of Change)**: cambio planificado que puede afectar la conformidad del
  producto (cambio de proveedor crítico, de proceso, de material o de equipamiento), conforme
  a la definición de PG-02, extendida en este procedimiento al diseño, la organización y el
  sistema informático.
- **Planilla MoC**: registro del cambio (descripción, motivo, evaluación de riesgos,
  aprobación, plan de implementación, comunicación y cierre), archivado en la carpeta de
  calidad.
- **Migración**: script SQL numerado que modifica el esquema o los datos de la base del ERP,
  versionado en la carpeta `migrations/` del repositorio git.
- **Deploy**: publicación de una nueva versión del frontend del ERP mediante el repositorio
  git (la publicación en la rama principal dispara el despliegue automático del hosting).

## 5. Responsabilidades

- **Dirección**: **aprueba todo MoC** antes de su implementación (MC-01 §5); provee los
  recursos; evalúa los MoC significativos en la revisión por la dirección (PG-12).
- **Responsable de Calidad**: administra este procedimiento; mantiene el registro de planillas
  MoC; coordina la evaluación de riesgos (PG-02); verifica que los documentos afectados se
  actualicen (PG-01), que el personal se capacite (PG-13) y que el cambio se cierre con
  verificación; decide en caso de duda si un cambio constituye MoC.
- **Responsable de Producción**: identifica y propone cambios de proceso y equipamiento;
  ejecuta la implementación en planta; no aplica un cambio de proceso sin la aprobación y los
  documentos vigentes correspondientes.
- **Responsable de Compras/Administración**: identifica y propone cambios de proveedor;
  ejecuta la calificación del proveedor entrante conforme a PG-04 antes de la primera compra.

## 6. Desarrollo

### 6.1 Identificación y solicitud del cambio

1. Cualquier integrante de la empresa puede proponer un cambio. La propuesta se documenta en
   la **planilla MoC** (carpeta de calidad) con: descripción del cambio, motivo, categoría
   (§2), procesos, productos y documentos afectados, y fecha objetivo.
2. El Responsable de Calidad asigna un número correlativo de MoC y verifica que la categoría
   y el alcance estén completos.

### 6.2 Evaluación de riesgos

3. Todo MoC se evalúa con la metodología de PG-02 (matriz 3×3: Probabilidad × Severidad),
   considerando el impacto sobre la conformidad del producto, la trazabilidad, los controles
   existentes del ERP y el cumplimiento de entregas. La evaluación se asienta en la planilla
   MoC.
4. Si el nivel de riesgo resulta **no aceptable**, el cambio requiere acciones de mitigación
   previas a la implementación, con responsable y plazo.
5. Si el cambio introduce un riesgo no contemplado en la matriz AR-01 o modifica uno
   existente, se actualiza AR-01 como nueva revisión (disparador 4 de PG-02 §6.4).

### 6.3 Aprobación

6. La **Dirección aprueba o rechaza el MoC** dejando constancia firmada en la planilla. Sin
   aprobación de la Dirección no se implementa ningún cambio alcanzado por este procedimiento.
7. Para cambios de proveedor crítico, la aprobación del MoC no sustituye la calificación del
   proveedor: el proveedor entrante debe quedar aprobado en la AVL con evaluación vigente
   antes de la primera orden de compra (el sistema bloquea las OC a proveedores críticos no
   aprobados, gate `fn_oc_avl_gate`; ver PG-04).

### 6.4 Planificación e implementación

8. El MoC aprobado se planifica en la propia planilla: acciones, responsables, plazos y
   verificaciones previstas. La planificación asegura, según corresponda:
   - **Actualización documental**: los documentos del SGC afectados (procedimientos,
     instructivos, planos, PQP, WPS) se reemiten como nueva revisión conforme a PG-01; al
     ponerse en vigencia, el sistema obsoleta automáticamente la revisión anterior (trigger
     `fn_doc_vigencia`) y las operaciones de producción solo pueden referenciar la vigente
     (gate `fn_op_quality_gate`).
   - **Capacitación previa**: el personal afectado se capacita en el cambio **antes** de su
     puesta en práctica, con registro conforme a PG-13.
   - **Producto en curso**: se define el punto de corte (a partir de qué OP, lote o pedido
     rige el cambio) y se asienta en la planilla MoC.
9. Las acciones de mitigación o de implementación que lo requieran se gestionan además como
   acciones preventivas en el módulo Calidad → NCR/CAPA (`acciones_capa` con
   `tipo` = 'preventiva', `responsable_id` y `fecha_compromiso`), quedando sujetas a la
   verificación de eficacia de PG-10 (guard `fn_capa_cierre_guard`).

### 6.5 Comunicación del cambio

10. El Responsable de Calidad comunica el MoC aprobado al personal afectado antes de su
    implementación, y deja constancia en la planilla (puede materializarse como la
    capacitación de §6.4).
11. Cuando el cambio afecte un producto o pedido en curso y el contrato o la especificación
    del cliente lo requieran, la empresa **notifica al cliente** antes de implementar el
    cambio, conservando la evidencia de la notificación (correo archivado en la carpeta de
    calidad, referenciado en la planilla MoC).

### 6.6 Caso particular: cambios al ERP (migraciones y deploy vía git)

12. El ERP materializa controles del SGC (gates de calidad, trazabilidad, protección de
    evidencia), por lo que sus modificaciones se tratan como MoC cuando afectan un control,
    un registro de calidad o un cálculo de indicador. Reglas de implementación:
    - **Base de datos**: todo cambio de esquema, gate o RPC se implementa como **migración SQL
      numerada** en la carpeta `migrations/` del repositorio git, con scripts idempotentes y
      retrocompatibles y su verificación al pie. La migración se ejecuta y verifica en la base
      de datos **antes** de publicar el frontend que la utiliza.
    - **Frontend**: el código se versiona en git; el **deploy a producción se realiza
      publicando en la rama principal del repositorio**, lo que dispara el despliegue
      automático del hosting. Antes de publicar se ejecutan las verificaciones automatizadas
      del repositorio (chequeo de sintaxis y suite de tests de cálculos en `tests/`).
    - **Un cambio por vez**: cada cambio se publica y verifica en producción antes de iniciar
      el siguiente.
    - **Registro**: el historial de commits del repositorio git y la secuencia numerada de
      migraciones constituyen el registro técnico de implementación; la evaluación de riesgos,
      la aprobación y la verificación de cierre quedan en la planilla MoC. Los cambios sobre
      los datos quedan además asentados en `audit_log` (PG-01 §6.5.4).
13. Ante una falla introducida por un cambio del ERP, la reversión (rollback del frontend
    mediante git y/o migración correctiva) se trata con la prioridad de una contención de
    producto no conforme; si el defecto afectó registros o controles de calidad, se abre la
    no conformidad correspondiente (PG-09) y se evalúa el impacto sobre los registros del
    período afectado.

### 6.7 Verificación y cierre del MoC

14. El Responsable de Calidad verifica que: todas las acciones del plan se completaron, los
    documentos afectados están vigentes, el personal fue capacitado, el cliente fue notificado
    cuando correspondía y el cambio opera según lo previsto. La verificación y la fecha de
    cierre se asientan en la planilla MoC.
15. Los MoC tramitados en el período y su estado son entrada de la revisión por la dirección
    (PG-12 §6.2).

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Planillas MoC (evaluación, aprobación, plan, comunicación y cierre) | Carpeta de calidad (fuera del ERP) | 10 años |
| Matriz de riesgos AR-01 (revisiones disparadas por MoC) | `documentos_controlados` (Calidad → Documentos) | Permanente |
| Documentos del SGC reemitidos por el cambio | `documentos_controlados` (Calidad → Documentos) | Permanente (obsoletos conservados) |
| Acciones preventivas del MoC | `acciones_capa` (Calidad → NCR/CAPA) | 10 años |
| Registro de capacitación en el cambio | Planilla física, carpeta de calidad (PG-13) | 10 años |
| Evidencia de notificación al cliente | Correo archivado en carpeta de calidad, referenciado en la planilla MoC | 10 años |
| Historial de migraciones y deploys del ERP | Carpeta `migrations/` e historial de commits del repositorio git | Permanente (en el repositorio) |
| Pista de auditoría de cambios de datos | `audit_log` (solo lectura de administradores) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
