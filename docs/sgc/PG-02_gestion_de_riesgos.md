# PG-02 — Gestión de riesgos

| Campo | Valor |
|---|---|
| **Código** | PG-02 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §6.1 · API Q1 §5.3 (Evaluación de riesgos) y §5.11 (Planes de contingencia) |

## 1. Propósito

Definir una metodología simple y repetible para identificar, evaluar y tratar los riesgos que
puedan afectar la conformidad del producto y la capacidad de entrega de Vitalmet S.A., y para
mantener actualizada la matriz de riesgos y los planes de contingencia asociados.

## 2. Alcance

Aplica a los riesgos asociados a la realización del producto en los cuatro dominios que exige
API Q1: **revisión de contrato**, **diseño** (cuando aplique al alcance del pedido),
**compras** y **producción** (incluyendo procesos tercerizados: tratamiento térmico y
calibración externa). Incluye la evaluación de riesgos de disponibilidad (falla de equipo
crítico, falta de material, indisponibilidad de personal clave) que alimenta los planes de
contingencia.

## 3. Referencias

- ISO 9001:2015, §6.1 — Acciones para abordar riesgos y oportunidades.
- API Specification Q1, 9ª edición — §5.3 Evaluación de riesgos; §5.11 Planes de contingencia.
- AR-01 — Matriz de riesgos (documento controlado, tipo 'otro' en `documentos_controlados`).
- PC-01 / PC-02 / PC-03 — Planes de contingencia (documentos controlados, tipo
  'plan_contingencia').
- PG-03 — Revisión de requisitos del cliente.
- PG-04 — Compras y AVL.

## 4. Definiciones

- **Riesgo**: efecto de la incertidumbre sobre la conformidad del producto o el cumplimiento
  de la entrega.
- **Probabilidad (P)**: verosimilitud de ocurrencia del evento (1 = baja, 2 = media, 3 = alta).
- **Severidad (S)**: impacto del evento sobre el producto, el cliente o la entrega
  (1 = menor, 2 = moderada, 3 = crítica).
- **Nivel de riesgo**: producto P × S, resultante de la matriz 3×3.
- **MoC (Management of Change)**: cambio planificado que puede afectar la conformidad del
  producto (cambio de proveedor crítico, de proceso, de material o de equipamiento).

## 5. Responsabilidades

- **Dirección**: aprueba la matriz de riesgos AR-01 y los planes de contingencia; asigna
  recursos para el tratamiento de riesgos no aceptables.
- **Responsable de Calidad**: administra la metodología; convoca y documenta las revisiones de
  la matriz; verifica que los disparadores de actualización se atiendan; mantiene AR-01 y los
  PC como documentos controlados según PG-01.
- **Responsable de Producción**: identifica riesgos de proceso y de equipamiento; participa en
  la evaluación; ejecuta las acciones de mitigación de su dominio.
- **Responsable de Compras**: identifica riesgos de la cadena de suministro; participa en la
  evaluación de riesgos de compras y de proveedores críticos.

## 6. Desarrollo

### 6.1 Metodología de evaluación: matriz 3×3

1. Cada riesgo identificado se enuncia como evento + causa + consecuencia.
2. Se le asigna Probabilidad (1–3) y Severidad (1–3). El nivel de riesgo es P × S:

| P \ S | 1 (menor) | 2 (moderada) | 3 (crítica) |
|---|---|---|---|
| **3 (alta)** | 3 — Tolerable | 6 — No aceptable | 9 — No aceptable |
| **2 (media)** | 2 — Aceptable | 4 — Tolerable | 6 — No aceptable |
| **1 (baja)** | 1 — Aceptable | 2 — Aceptable | 3 — Tolerable |

3. Criterios de tratamiento:
   - **Aceptable (1–2)**: se documenta; no requiere acción adicional.
   - **Tolerable (3–4)**: requiere control operativo documentado (gate del ERP, inspección,
     verificación) y seguimiento en la revisión anual.
   - **No aceptable (6–9)**: requiere acción de mitigación con responsable y plazo, y —cuando
     el riesgo es de disponibilidad— plan de contingencia asociado (PC-01/02/03).
4. La evaluación completa se registra en la matriz **AR-01**, que es un documento controlado
   del SGC: su revisión, aprobación y vigencia se administran conforme a PG-01 en
   `documentos_controlados` (código AR-01, PDF en `file_data`, vigencia única por código
   garantizada por el trigger `fn_doc_vigencia`).

### 6.2 Dominios de aplicación obligatoria (API Q1)

La matriz AR-01 debe cubrir, como mínimo, los cuatro dominios siguientes:

1. **Revisión de contrato**: riesgo de aceptar requisitos que exceden la capacidad de planta
   (presión de prueba superior al banco de 22.000 psi, materiales fuera de alcance, plazos
   inviables). Control operativo: la revisión de capacidad previa al envío del presupuesto,
   antes de pasar `presupuestos.estado` a 'enviado' (ver PG-03).
2. **Diseño**: riesgo de aplicar una revisión de plano o especificación incorrecta. Control
   operativo: el plano se identifica en `ordenes_produccion.codigo_plano` y los documentos
   técnicos vinculados a la operación deben estar vigentes (el sistema exige que
   `op_operaciones.documento_id` apunte a un documento en estado 'vigente', gate
   `fn_op_quality_gate`).
3. **Compras**: riesgo de material no conforme o proveedor no calificado. Controles
   operativos: el sistema bloquea la emisión de OC de materia prima o a proveedor crítico sin
   proveedor aprobado y con evaluación vigente (gate `fn_oc_avl_gate`), y exige MTR para
   aceptar materia prima en recepción (gate `fn_recepcion_inspeccion`); ver PG-04 y PG-05.
4. **Producción**: riesgo de procesar material no liberado, de saltear puntos de inspección o
   de usar instrumentos vencidos. Controles operativos: el sistema impide consumir material no
   aceptado (RPC `consumir_barra`), impide avanzar sobre hold points sin firma y cerrar la OP
   con puntos sin signoff (gates `fn_op_quality_gate` y `fn_op_cierre_gate`), y bloquea el uso
   de instrumentos con calibración vencida en inspecciones (gate
   `fn_registro_calibracion_gate`).

### 6.3 Riesgos de disponibilidad y planes de contingencia

Para los riesgos que comprometen la continuidad de la entrega (falla del banco de prueba
hidrostática, indisponibilidad del proveedor de tratamiento térmico, caída del ERP), la matriz
AR-01 remite a los planes de contingencia:

- **PC-01** — Falla de equipo crítico (banco hidrostático / manómetro patrón).
- **PC-02** — Indisponibilidad de proveedor crítico tercerizado (tratamiento térmico).
- **PC-03** — Indisponibilidad del sistema informático (ERP).

Los tres son documentos controlados (tipo 'plan_contingencia' en `documentos_controlados`) y
siguen el ciclo de vida de PG-01.

### 6.4 Disparadores de actualización de la matriz

La matriz AR-01 se revisa y, de corresponder, se reemite como nueva revisión ante cualquiera
de los siguientes disparadores:

1. **Revisión anual programada**, como entrada de la revisión por la dirección.
2. **No conformidad repetida**: dos o más NC con el mismo origen y causa raíz en 12 meses
   (consulta sobre `no_conformidades.origen_tipo` y las causas registradas en
   `acciones_capa.causa_raiz`).
3. **Cambio de proveedor crítico** o incorporación de un proveedor nuevo con
   `proveedores.criticidad` = 'critico' (incluye proveedores de tratamiento térmico
   referenciados en `tratamientos.proveedor_id` y laboratorios de calibración referenciados en
   `calibraciones.laboratorio_id`).
4. **MoC**: cambio de proceso, material, equipamiento o instalaciones que pueda afectar la
   conformidad del producto.
5. **Resultado de auditoría** (interna o externa) que evidencie un riesgo no contemplado
   (las NC de auditoría se registran con `no_conformidades.origen_tipo` = 'auditoria').

Cada actualización genera una nueva revisión de AR-01 en `documentos_controlados`; la revisión
anterior queda obsoleta automáticamente (trigger `fn_doc_vigencia`), preservando el histórico.

### 6.5 Seguimiento y verificación de eficacia

1. Las acciones de mitigación derivadas de riesgos no aceptables se gestionan como acciones
   preventivas en el módulo Calidad → NCR/CAPA (`acciones_capa.tipo` = 'preventiva'), con
   responsable (`responsable_id`) y plazo (`fecha_compromiso`).
2. El cierre de estas acciones exige verificación de eficacia: el sistema no permite cerrar
   una acción CAPA sin completar `verificacion_eficacia` y `eficaz` (guard
   `fn_capa_cierre_guard`).
3. El estado de la matriz de riesgos y de sus acciones asociadas es entrada obligatoria de la
   revisión por la dirección (minuta en carpeta de calidad, fuera del ERP).

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| Matriz de riesgos AR-01 (todas las revisiones) | `documentos_controlados` (Calidad → Documentos) | Permanente |
| Planes de contingencia PC-01/02/03 | `documentos_controlados` (Calidad → Documentos) | Permanente |
| Acciones preventivas derivadas de riesgos | `acciones_capa` (Calidad → NCR/CAPA) | 10 años |
| NC que disparan revisión de la matriz | `no_conformidades` (Calidad → NCR/CAPA) | 10 años |
| Minuta de revisión por la dirección | Archivo en carpeta de calidad (fuera del ERP) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
