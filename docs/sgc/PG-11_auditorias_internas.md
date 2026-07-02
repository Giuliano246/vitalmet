# PG-11 — Auditorías internas

| Campo | Valor |
|---|---|
| **Código** | PG-11 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §9.2 · API Q1 §6.2.2 (Auditoría interna) |

## 1. Propósito

Establecer la metodología para planificar, ejecutar e informar las auditorías internas del
Sistema de Gestión de la Calidad (SGC) de Vitalmet S.A., a fin de verificar que el sistema es
conforme con los requisitos de ISO 9001:2015 y API Specification Q1, con los requisitos propios
definidos en la documentación del SGC, y que se encuentra implementado y mantenido eficazmente.

## 2. Alcance

Aplica a todos los procesos del SGC según el mapa de procesos de MC-01 §6.3 (procesos de
dirección, operativos y de apoyo), incluyendo los controles materializados en el ERP
(gates, triggers y registros) y los procesos tercerizados críticos gestionados por la empresa
(tratamiento térmico y calibración externa). Aplica al sitio único de Perú 246, Villa Martelli.

## 3. Referencias

- ISO 9001:2015, §9.2 — Auditoría interna.
- API Specification Q1, 9ª edición — §6.2.2 Auditoría interna.
- ISO 19011 — Directrices para la auditoría de los sistemas de gestión (guía metodológica).
- MC-01 — Manual de Calidad (mapa de procesos §6.3; responsabilidades §5).
- PG-01 — Control de documentos y registros (registros fuera del ERP, §6.5.6).
- PG-02 — Gestión de riesgos (disparadores de actualización de AR-01).
- PG-09 — Control de producto no conforme.
- PG-10 — Acciones correctivas y preventivas (CAPA).
- PG-12 — Revisión por la dirección.

## 4. Definiciones

- **Auditoría interna**: proceso sistemático, independiente y documentado para obtener
  evidencia objetiva y evaluarla contra los criterios de auditoría.
- **Programa anual de auditorías**: planificación del conjunto de auditorías de un año
  calendario, con procesos a auditar, fechas previstas y auditor asignado.
- **Plan de auditoría**: documento de detalle de una auditoría individual (alcance, criterios,
  agenda, auditor).
- **Criterios de auditoría**: ISO 9001:2015, API Q1, la documentación del SGC (MC-01, PG-xx,
  IT-xx, PQP) y los requisitos legales y de cliente aplicables.
- **Hallazgo**: resultado de la evaluación de la evidencia contra los criterios. Se clasifica
  en: **no conformidad mayor** (ausencia o falla total de un requisito, o riesgo directo sobre
  la conformidad del producto), **no conformidad menor** (incumplimiento puntual que no
  compromete el sistema) y **observación / oportunidad de mejora**.
- **Auditor calificado**: persona que cumple los requisitos de calificación de §6.2 de este
  procedimiento. Puede ser personal propio o un auditor externo contratado.

## 5. Responsabilidades

- **Dirección**: aprueba el programa anual de auditorías; provee los recursos, incluyendo la
  contratación de auditores externos cuando corresponda; recibe los informes de auditoría y
  trata sus resultados en la revisión por la dirección (PG-12).
- **Responsable de Calidad**: planifica y coordina las auditorías internas (MC-01 §5); elabora
  el programa anual; verifica la calificación de los auditores y custodia sus registros;
  archiva los informes en la carpeta de calidad; registra los hallazgos como no conformidades
  en el ERP y verifica su tratamiento hasta el cierre (PG-09 / PG-10).
- **Responsable de Producción**: atiende la auditoría de los procesos a su cargo, facilita el
  acceso a planta, personal y registros, y ejecuta las acciones correctivas de su dominio.
- **Responsable de Compras/Administración**: atiende la auditoría de los procesos a su cargo
  (compras, recepción administrativa, ventas, facturación) y ejecuta las acciones correctivas
  de su dominio; gestiona la contratación del auditor externo cuando la Dirección lo disponga.

## 6. Desarrollo

### 6.1 Programa anual de auditorías

1. El Responsable de Calidad elabora, antes del inicio de cada año calendario, el **programa
   anual de auditorías**, que asegura que **todos los procesos del mapa de MC-01 §6.3 sean
   auditados al menos una vez por año**.
2. La frecuencia y profundidad por proceso se ajustan considerando: el nivel de riesgo del
   proceso según la matriz AR-01 (PG-02), los resultados de auditorías anteriores, las no
   conformidades acumuladas del proceso (consulta de `no_conformidades` por `origen_tipo` en
   el módulo Calidad → NCR/CAPA) y los cambios implementados o previstos (MoC, PG-14).
3. El programa se documenta en planilla (archivo en carpeta de calidad, fuera del ERP,
   conforme a PG-01 §6.5.6) y es aprobado por la Dirección.
4. El programa puede modificarse durante el año ante disparadores tales como: una no
   conformidad mayor, un cambio significativo (PG-14), un reclamo de cliente relevante o un
   resultado adverso de auditoría externa. Toda modificación se asienta en la planilla del
   programa y se somete a la misma aprobación.

### 6.2 Calificación e independencia de los auditores

5. Dada la escala de la empresa (una persona por rol, ver MC-01 §6.4), la objetividad e
   imparcialidad de la auditoría se asegura **preferentemente mediante la contratación de
   auditores externos calificados**. Requisitos mínimos del auditor (propio o contratado):
   - Formación como auditor interno de sistemas de gestión ISO 9001 (curso con evaluación
     aprobada) y, deseablemente, formación o experiencia en API Q1.
   - Conocimiento del tipo de producto y proceso (componentes de alta presión para oil & gas,
     mecanizado, soldadura, ensayos) acreditable por experiencia o formación técnica.
6. **Nadie audita su propio trabajo.** El personal propio solo puede actuar como auditor
   interno sobre procesos en los que no tenga responsabilidad directa de ejecución, y siempre
   que cumpla los requisitos del punto 5. Los procesos a cargo del Responsable de Calidad
   (control de documentos, NCR/CAPA, metrología, auditorías) deben ser auditados por un
   auditor externo o por otra función calificada, nunca por él mismo.
7. La evidencia de calificación del auditor (certificados de formación, CV, constancia de
   experiencia) se archiva en la carpeta de calidad y se verifica antes de cada auditoría.

### 6.3 Planificación de cada auditoría

8. Para cada auditoría del programa, el auditor —con el Responsable de Calidad— elabora el
   **plan de auditoría**: alcance (procesos y requisitos a cubrir), criterios, fecha y agenda,
   y personas a entrevistar. El plan se comunica a los auditados con antelación razonable
   (mínimo una semana).

### 6.4 Ejecución de la auditoría

9. La auditoría comprende: reunión de apertura, revisión documental, entrevistas al personal,
   recorrida de planta y verificación de registros, y reunión de cierre con presentación de
   los hallazgos preliminares.
10. La verificación de registros incluye el **muestreo directo en el ERP**, para lo cual el
    auditor recibe acceso de consulta durante la auditoría. Ejemplos de verificaciones típicas:
    - Trazabilidad completa de un pedido tomado al azar (módulo Análisis → Trazabilidad:
      certificado → barra → OP → PT → venta).
    - Órdenes de producción con sus hold/witness points firmados (`op_operaciones.signoff_usuario_id`
      / `signoff_at`) y documentos referenciados en estado 'vigente'.
    - Instrumentos con calibración vigente en las inspecciones registradas (`registros_calidad`).
    - Proveedores críticos con evaluación AVL vigente (`proveedores`).
    - Documentos controlados: unicidad de la revisión vigente por código (Calidad → Documentos).
    - Historia de cambios en `audit_log` para registros seleccionados.
11. La evidencia se registra en las notas del auditor, que forman parte del legajo de la
    auditoría (carpeta de calidad).

### 6.5 Informe de auditoría

12. El auditor emite el **informe de auditoría** dentro de los 10 días hábiles de la reunión
    de cierre, con el contenido mínimo: alcance y criterios, fecha, auditor, personas
    entrevistadas, resumen de evidencia examinada, hallazgos clasificados (NC mayor, NC menor,
    observación / oportunidad de mejora) y conclusión sobre la conformidad y eficacia del SGC.
13. El informe se archiva en la **carpeta de calidad** (registro fuera del ERP, PG-01 §6.5.6)
    con retención de 10 años, y se distribuye a la Dirección y a los responsables de los
    procesos auditados.

### 6.6 Tratamiento de los hallazgos

14. Cada no conformidad de auditoría (mayor o menor) se registra en el ERP, en el módulo
    Calidad → NCR/CAPA, como registro de `no_conformidades` con `origen_tipo` = 'auditoria',
    referenciando en la descripción el informe y el hallazgo de origen. Su tratamiento sigue
    PG-09.
15. Las acciones correctivas derivadas se gestionan en `acciones_capa` conforme a PG-10, con
    análisis de causa raíz (`causa_raiz`), responsable (`responsable_id`) y plazo
    (`fecha_compromiso`). El cierre exige verificación de eficacia: el sistema no permite
    cerrar una acción CAPA sin completar `verificacion_eficacia` y `eficaz` (guard
    `fn_capa_cierre_guard`).
16. Las observaciones y oportunidades de mejora no exigen NC; su tratamiento queda a criterio
    del responsable del proceso y se revisa en la revisión por la dirección.
17. El Responsable de Calidad efectúa el **seguimiento hasta el cierre** de todas las NC de
    auditoría. La verificación de la implementación eficaz se confirma, además, en la
    auditoría siguiente del proceso involucrado.

### 6.7 Salidas hacia otros procesos

18. Los resultados de las auditorías internas son **entrada obligatoria de la revisión por la
    dirección** (PG-12).
19. Un resultado de auditoría que evidencie un riesgo no contemplado dispara la revisión de la
    matriz AR-01 (PG-02 §6.4, disparador 5).

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Programa anual de auditorías (y sus modificaciones) | Planilla en carpeta de calidad (fuera del ERP) | 10 años |
| Planes de auditoría y notas del auditor | Carpeta de calidad (fuera del ERP) | 10 años |
| Informes de auditoría interna | Carpeta de calidad (fuera del ERP) | 10 años |
| Evidencia de calificación de auditores | Carpeta de calidad (fuera del ERP) | Vigencia + 10 años |
| No conformidades de auditoría | `no_conformidades` con `origen_tipo` = 'auditoria' (Calidad → NCR/CAPA) | 10 años |
| Acciones correctivas derivadas | `acciones_capa` (Calidad → NCR/CAPA) | 10 años |
| Minuta de revisión por la dirección (tratamiento de resultados) | Carpeta de calidad (fuera del ERP) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
