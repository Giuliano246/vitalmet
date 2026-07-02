# PG-13 — Competencia y capacitación

| Campo | Valor |
|---|---|
| **Código** | PG-13 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §7.2 (Competencia) y §7.3 (Toma de conciencia) · API Q1 §4.3.2 (Recursos humanos: competencia, toma de conciencia y capacitación) |

## 1. Propósito

Establecer la metodología para determinar y asegurar la competencia del personal de
Vitalmet S.A. cuyo trabajo afecta la conformidad del producto, para planificar y registrar la
capacitación, evaluar su eficacia y mantener la toma de conciencia sobre la política de
calidad, los objetivos y las consecuencias de un desvío en productos de alta presión.

## 2. Alcance

Aplica a todo el personal de la empresa, incluyendo la Dirección, y al personal eventual o
contratado que realice trabajo bajo control de la empresa que afecte la conformidad del
producto. Comprende con especial énfasis los puestos críticos: **soldadores calificados
(WPQ conforme a ASME Sección IX)**, **operarios de mecanizado** e **inspector** (quien ejecuta
inspecciones y ensayos).

## 3. Referencias

- ISO 9001:2015, §7.2 — Competencia; §7.3 — Toma de conciencia.
- API Specification Q1, 9ª edición — §4.3.2 Recursos humanos.
- ASME Boiler and Pressure Vessel Code, Sección IX — calificación de soldadores (WPQ).
- MC-01 — Manual de Calidad (roles y responsabilidades §5; política §6.1; objetivos §6.2).
- PG-01 — Control de documentos y registros (registros fuera del ERP, §6.5.6; documentos
  controlados tipo 'wpq').
- PG-14 — Gestión del cambio (MoC).
- PG-16 — Control de soldadura y servicio sour.

## 4. Definiciones

- **Competencia**: capacidad demostrada de aplicar educación, formación, habilidades y
  experiencia para lograr los resultados previstos del puesto.
- **Matriz de competencias**: planilla que define, para cada puesto, los requisitos de
  competencia y el estado de cumplimiento de cada persona asignada.
- **WPQ (Welder Performance Qualification)**: calificación de habilidad del soldador conforme
  a ASME Sección IX, con variables esenciales y vigencia.
- **Capacitación**: actividad planificada para cerrar una brecha de competencia (curso,
  entrenamiento en el puesto, instrucción sobre un documento del SGC).
- **Toma de conciencia**: comprensión, por parte del personal, de la política y los objetivos
  de calidad, de su contribución a la eficacia del SGC y de las implicancias de no cumplir
  los requisitos.

## 5. Responsabilidades

- **Dirección**: define los perfiles de puesto y aprueba la matriz de competencias y el plan
  anual de capacitación; provee los recursos (cursos, calificaciones de soldadores,
  entrenamientos externos).
- **Responsable de Calidad**: mantiene la matriz de competencias y los legajos de
  capacitación; planifica la capacitación y evalúa su eficacia; controla la vigencia de las
  WPQ como documentos controlados del SGC; verifica la competencia del personal que firma
  inspecciones y ensayos.
- **Responsable de Producción**: identifica necesidades de capacitación en planta; dicta y
  registra el entrenamiento en el puesto; **no asigna una soldadura a un soldador sin WPQ
  vigente para el proceso** (PG-16) ni una operación a un operario sin la competencia definida
  en la matriz.
- **Responsable de Compras/Administración**: gestiona la contratación de capacitaciones y
  calificaciones externas y archiva sus comprobantes administrativos.

## 6. Desarrollo

### 6.1 Perfiles de puesto y matriz de competencias

1. El Responsable de Calidad elabora y mantiene la **matriz de competencias por puesto**, en
   planilla física archivada en la carpeta de calidad (proceso fuera del ERP, conforme al mapa
   de procesos de MC-01 §6.3 y a PG-01 §6.5.6).
2. La matriz cubre, como mínimo, los siguientes puestos: Dirección, Responsable de Calidad,
   Responsable de Producción, Responsable de Compras/Administración, **soldador calificado**,
   **operario de mecanizado** e **inspector**.
3. Para cada puesto, la matriz define los requisitos de: educación, formación específica,
   habilidades, experiencia y calificaciones formales exigidas. En particular:
   - **Soldador**: WPQ vigente conforme a ASME Sección IX para cada proceso y posición que
     ejecute; conocimiento de los WPS aplicables.
   - **Operario de mecanizado**: lectura e interpretación de planos, operación de las máquinas
     asignadas, uso de instrumentos de medición básicos, conocimiento de los instructivos y
     del routing (hold/witness points) que le aplican.
   - **Inspector**: interpretación de planos y especificaciones, uso de instrumentos de
     medición y del banco de prueba hidrostática conforme a IT-01/IT-02, criterio de
     aceptación/rechazo, y la independencia respecto de Producción exigida por MC-01 §5.
4. La matriz registra además, por persona, el estado de cumplimiento de cada requisito
   (cumple / brecha / capacitación en curso) y su fecha de última revisión.

### 6.2 Evaluación de competencia y detección de brechas

5. La competencia se evalúa: **al ingreso** de una persona, **al cambio de puesto o de
   funciones**, **ante un cambio gestionado por PG-14** que modifique procesos, equipos o
   documentos que la persona utiliza, y **al menos una vez por año** en la revisión general de
   la matriz.
6. Toda brecha detectada genera una acción de capacitación (plan anual o extraordinaria) o una
   restricción de asignación de tareas hasta cerrar la brecha.

### 6.3 Calificaciones especiales: soldadores (WPQ)

7. Las WPQ se administran como **documentos controlados del SGC** en el ERP, en el módulo
   Calidad → Documentos (`documentos_controlados` con `tipo` = 'wpq'), conforme a MC-01 §6.7 y
   PG-01; el listado de calificaciones vigentes se consulta filtrando por tipo y
   `estado` = 'vigente'.
8. El Responsable de Calidad controla la vigencia y continuidad de cada WPQ según ASME
   Sección IX (incluida la continuidad por actividad de soldadura); el vencimiento o la
   interrupción de continuidad se refleja obsoletando el documento y exige recalificación
   antes de una nueva asignación de soldadura (PG-16).

### 6.4 Plan de capacitación

9. El Responsable de Calidad elabora un **plan anual de capacitación** (planilla en carpeta de
   calidad) a partir de las brechas de la matriz, los perfiles de puesto y las necesidades de
   los procesos, y lo somete a aprobación de la Dirección.
10. Se dispone además capacitación **no planificada** ante los siguientes disparadores:
    - Una no conformidad cuya causa raíz (`acciones_capa.causa_raiz`) involucre competencia o
      error humano.
    - Un cambio de proceso, equipo, documento o sistema tramitado por PG-14 (la capacitación
      del personal afectado es condición previa a la puesta en práctica del cambio).
    - La emisión o revisión de un documento del SGC que modifique la operatoria del puesto.
    - Un resultado de auditoría interna (PG-11) que lo requiera.
11. La capacitación puede ser interna (entrenamiento en el puesto, instrucción sobre
    documentos del SGC) o externa (cursos, calificaciones). El entrenamiento en el puesto de
    operarios lo dicta el Responsable de Producción o un operario competente designado.

### 6.5 Registro de la capacitación

12. Toda actividad de capacitación se registra en **planilla física de asistencia** archivada
    en la carpeta de calidad (PG-01 §6.5.6), con: tema y contenido, fecha y duración,
    instructor (interno o externo), asistentes con firma, y material utilizado o referencia al
    documento del SGC tratado.
13. Los certificados de cursos y calificaciones externas se archivan en el legajo de
    capacitación de cada persona, en la carpeta de calidad.

### 6.6 Evaluación de eficacia

14. Para cada capacitación se define y registra el método de evaluación de eficacia, acorde a
    su naturaleza: evaluación teórica o práctica al finalizar, observación posterior del
    desempeño en el puesto, probeta calificada (soldadura), o seguimiento de indicadores del
    proceso (por ejemplo, ausencia de no conformidades repetidas del mismo origen en el módulo
    Calidad → NCR/CAPA).
15. El resultado de la evaluación de eficacia se asienta en la planilla de la capacitación o
    en el legajo. Si la capacitación no resultó eficaz, se repite o se redefine la acción, y
    se mantiene la restricción de tareas si correspondiera.

### 6.7 Toma de conciencia

16. Todo el personal recibe, al ingreso y ante cada actualización, la difusión de: la política
    de calidad (MC-01 §6.1), los objetivos de calidad pertinentes a su función (MC-01 §6.2),
    su contribución a la eficacia del SGC y, en particular, **las consecuencias potenciales de
    un incumplimiento en productos de alta presión** (falla en servicio con riesgo para vidas,
    instalaciones y ambiente).
17. La inducción de ingresantes cubre además: la estructura documental del SGC y el punto
    único de consulta de documentos vigentes (ERP, Calidad → Documentos), el significado de
    los hold/witness points y la obligación de detener el trabajo y reportar ante un desvío
    (PG-09). La inducción se registra como una capacitación más (§6.5).

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Matriz de competencias por puesto (todas las revisiones) | Planilla física, carpeta de calidad (fuera del ERP) | 10 años |
| Perfiles de puesto | Carpeta de calidad (fuera del ERP) | Vigencia + 10 años |
| Plan anual de capacitación | Planilla física, carpeta de calidad (fuera del ERP) | 10 años |
| Planillas de asistencia a capacitación (con evaluación de eficacia) | Planilla física, carpeta de calidad (fuera del ERP) | 10 años |
| Legajos de capacitación (certificados, evidencias) | Carpeta de calidad (fuera del ERP) | 10 años |
| Calificaciones de soldadores (WPQ) | `documentos_controlados` con `tipo` = 'wpq' (Calidad → Documentos) | 10 años tras obsolescencia |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
