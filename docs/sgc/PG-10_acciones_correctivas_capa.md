# PG-10 — Acciones correctivas y preventivas (CAPA)

| Campo | Valor |
|---|---|
| **Código** | PG-10 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §10.2 · API Q1 §5.11 (Corrective/Preventive Action, incl. verificación de eficacia) |

## 1. Propósito

Establecer la metodología para eliminar las causas de las no conformidades reales (acciones correctivas) y potenciales (acciones preventivas), de modo de evitar su recurrencia u ocurrencia, asegurando que cada acción tenga responsable, plazo, implementación verificada y — como condición excluyente de cierre — **verificación de eficacia**, tal como lo exige API Q1 §5.11.

## 2. Alcance

Aplica a todas las acciones correctivas y preventivas de Vitalmet S.A., registradas en el ERP VitalStock (tabla `acciones_capa`, módulo Calidad → NCR/CAPA), cualquiera sea su fuente:

- **Correctivas**: derivadas de no conformidades de producto o proceso (PG-09), reclamos de clientes, no conformidades de proveedor y hallazgos de auditoría interna o externa (PG-11).
- **Preventivas**: derivadas del análisis de riesgos y oportunidades (PG-02 / AR-01), del análisis de tendencias de indicadores (PG-12), de observaciones de auditoría y de oportunidades de mejora detectadas por el personal.

No aplica a la corrección inmediata del producto no conforme (disposición: retrabajo, reproceso, rechazo, concesión o devolución), que se rige por PG-09. La corrección resuelve el producto; la CAPA elimina la causa.

## 3. Referencias

- ISO 9001:2015, §10.2 — No conformidad y acción correctiva.
- API Specification Q1, 9ª edición — §5.11 (acción correctiva y preventiva, incl. verificación de eficacia).
- MC-01 — Manual de Calidad.
- PG-01 — Control de documentos y registros (retención y protección de la evidencia).
- PG-02 — Gestión de riesgos y oportunidades (fuente de acciones preventivas; registro AR-01).
- PG-09 — Control de producto no conforme (fuente de acciones correctivas; vinculación NCR→CAPA).
- PG-11 — Auditorías internas.
- PG-12 — Revisión por la dirección (revisión del estado de las CAPA).

## 4. Definiciones

- **CAPA**: acción correctiva o preventiva, registrada en la tabla `acciones_capa` del ERP. En pantalla se identifica como AC-nnnn (correctiva) o AP-nnnn (preventiva), según `acciones_capa.tipo`.
- **Acción correctiva** ('correctiva'): acción para eliminar la causa raíz de una no conformidad ya ocurrida y evitar su recurrencia.
- **Acción preventiva** ('preventiva'): acción para eliminar la causa de una no conformidad potencial y evitar su ocurrencia.
- **Causa raíz** (`causa_raiz`): causa de fondo cuya eliminación previene la recurrencia; se determina con una técnica sistemática (5 porqués, Ishikawa).
- **Verificación de eficacia** (`verificacion_eficacia` / `eficaz`): comprobación objetiva, posterior a la implementación, de que la acción eliminó efectivamente la causa (la no conformidad no volvió a ocurrir en condiciones equivalentes).

## 5. Responsabilidades

- **Dirección**: provee los recursos para implementar las acciones; revisa el estado y la eficacia de las CAPA en la revisión por la dirección (PG-12); aprueba las acciones que impliquen cambios de proceso, equipo o documentación mayores (canalizadas por PG-14 cuando corresponda gestión del cambio).
- **Responsable de Calidad**: administra el módulo Calidad → CAPA del ERP; decide la apertura de CAPA según los criterios de PG-09 §6.6 y de este procedimiento; conduce o valida el análisis de causa raíz; **realiza la verificación de eficacia y cierra las CAPA** (la verificación no la realiza quien implementó la acción, para preservar objetividad); monitorea los vencimientos.
- **Responsable designado de la acción** (`responsable_id`): implementa la acción comprometida en el plazo acordado y registra la fecha de implementación.
- **Responsable de Producción / Compras**: implementan las acciones de su área y aportan la evidencia de implementación.

## 6. Desarrollo

### 6.1 Apertura de la acción

1. Toda CAPA se registra en el ERP, en el módulo **Calidad → NCR/CAPA** (tabla `acciones_capa`), con el botón **Nueva CAPA**, o — cuando deriva de una no conformidad — con el botón **+ CAPA** de la fila de la NC, que precarga el vínculo a la NC de origen (`acciones_capa.nc_id`). El campo `accion` (qué se va a hacer para eliminar la causa) es obligatorio: el sistema no guarda sin él.
2. El número de CAPA lo asigna la base de datos (trigger `trg_capa_numero`, función `fn_nc_numero`): correlativo por empresa bajo advisory lock, con unicidad garantizada (UNIQUE sobre `empresa_id, numero`). En pantalla se muestra como AC-nnnn o AP-nnnn según el `tipo`.
3. El **vínculo NCR→CAPA** es obligatorio para las correctivas derivadas de una NC: `nc_id` referencia la NC de origen, y la grilla CAPA muestra en cada fila la NC asociada. El campo es nullable a propósito: una **acción preventiva** puede nacer de un análisis de riesgo (AR-01, PG-02) o de una auditoría, sin NC asociada.
4. Al abrir la acción se asigna el **responsable** (`responsable_id`, seleccionado entre los usuarios de la empresa) y la **fecha de compromiso** (`fecha_compromiso`). La CAPA nace en `estado` = 'abierta'.

### 6.2 Análisis de causa raíz

5. Para las acciones correctivas, se analiza y documenta la **causa raíz** en `acciones_capa.causa_raiz`, aplicando una técnica sistemática (5 porqués, Ishikawa) proporcional a la severidad del problema. No se acepta como causa raíz un síntoma («error del operario») sin preguntar por qué el sistema permitió el error.
6. El análisis considera si existen no conformidades similares o potenciales en otros productos, procesos o proveedores (extensión de la acción), y si el riesgo asociado está contemplado en AR-01 (retroalimentación a PG-02).
7. Para las preventivas, en `causa_raiz` se documenta la causa potencial identificada (del análisis de riesgo, tendencia o hallazgo que la origina).

### 6.3 Implementación

8. El responsable implementa la acción comprometida dentro del plazo de `fecha_compromiso`. Implementada la acción, registra la `fecha_implementacion` en el ERP y pasa el `estado` a 'implementada' desde el selector de la grilla.
9. Las CAPA **vencidas** (no cerradas con `fecha_compromiso` anterior a hoy) se destacan en rojo en la grilla y disparan una alerta **crítica** en el panel «Para hoy» del dashboard (digest `computeAlertas()`), identificadas por su número AC-/AP-nnnn. El Responsable de Calidad gestiona los vencimientos: replanifica con nueva fecha de compromiso justificada o escala a la Dirección.
10. Si la acción implica modificar documentos del SGC, la modificación sigue PG-01 (nueva revisión del documento controlado); si implica un cambio de proceso, producto o proveedor con impacto en la conformidad, se canaliza además por la gestión del cambio (PG-14).

### 6.4 Verificación de eficacia

11. Transcurrido un período razonable desde la implementación — definido caso a caso por el Responsable de Calidad según la frecuencia del proceso afectado —, se **verifica la eficacia**: con evidencia objetiva (indicadores, registros de calidad posteriores, ausencia de recurrencia) se determina si la acción eliminó la causa.
12. El resultado se registra en el ERP: `verificacion_eficacia` (cómo se verificó que funcionó) y `eficaz` (Sí / No). Con la verificación registrada, el `estado` pasa a 'verificada'.
13. Si la acción resulta **no eficaz** (`eficaz` = 'No'), la CAPA no se cierra: se reanaliza la causa raíz y se abre una nueva acción (vinculada a la misma NC por `nc_id`, cuando corresponda), dejando la acción no eficaz documentada como antecedente.

### 6.5 Cierre

14. La CAPA se cierra pasando su `estado` a 'cerrada'. El sistema **impide el cierre sin verificación de eficacia**: el guard de base de datos `fn_capa_cierre_guard` (trigger `trg_capa_cierre_guard`) rechaza el cierre si `eficaz` está sin definir o si `verificacion_eficacia` está vacía, con el error «La CAPA n no se puede cerrar sin verificación de eficacia (API Q1 §5.11)». Este control es un gate de la base de datos: aplica a cualquier vía de actualización, no solo a la pantalla.
15. La secuencia de estados 'abierta' → 'implementada' → 'verificada' → 'cerrada' es la definida por este procedimiento; el selector de la grilla permite el cambio de estado y el único bloqueo del sistema es el del punto 14, por lo que el Responsable de Calidad es responsable de respetar la secuencia y de no cerrar acciones sin implementación real verificada.
16. El cierre de la CAPA es independiente del cierre de la NC de origen (PG-09 §6.6): la NC se cierra al ejecutar la disposición sobre el producto; la CAPA, al verificar que la causa fue eliminada.

### 6.6 Seguimiento y revisión por la dirección

17. La grilla CAPA y sus indicadores de cabecera (CAPA abiertas, CAPA vencidas) constituyen el tablero de seguimiento permanente del módulo Calidad → NCR/CAPA.
18. El estado de las acciones correctivas y preventivas — cantidad, vencimientos, eficacia — es entrada obligatoria de la revisión por la dirección (PG-12), junto con el análisis de recurrencia de NC.

### 6.7 Protección del registro

19. Los registros de `acciones_capa` están protegidos como evidencia de calidad (PG-01): toda operación INSERT/UPDATE/DELETE queda asentada en `audit_log` con el diff de valores (trigger `trg_audit`), el DELETE está restringido a administradores (trigger `trg_proteger_evidencia`, función `fn_proteger_evidencia`) y el acceso está aislado por empresa (política RLS `tenant_isolation`).

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Acciones CAPA (causa raíz, acción, responsable, fechas, verificación de eficacia) | `acciones_capa` (Calidad → NCR/CAPA) | 10 años (protegidas por `fn_proteger_evidencia`) |
| Vínculo con la NC de origen | `acciones_capa.nc_id` → `no_conformidades` | 10 años (con la CAPA) |
| Historia de cambios de cada CAPA | `audit_log` (solo lectura de administradores) | 10 años |
| Evidencia de implementación y de verificación de eficacia (cuando excede el campo de texto) | Carpeta de calidad (fuera del ERP), referenciando el Nº de CAPA | 10 años |
| Revisión del estado de CAPA | Minuta de revisión por la dirección (PG-12, carpeta de calidad) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
