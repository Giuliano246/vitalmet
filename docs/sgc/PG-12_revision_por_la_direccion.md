# PG-12 — Revisión por la dirección

| Campo | Valor |
|---|---|
| **Código** | PG-12 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §9.3 · API Q1 §6.5 (Revisión por la dirección) |

## 1. Propósito

Establecer la metodología para que la Dirección de Vitalmet S.A. revise el Sistema de Gestión
de la Calidad (SGC) a intervalos planificados, asegurando su conveniencia, adecuación, eficacia
y alineación continuas con la dirección estratégica de la empresa, y que de cada revisión
resulten decisiones y acciones documentadas.

## 2. Alcance

Aplica a la revisión integral del SGC descripto en MC-01: la política y los objetivos de
calidad, el desempeño de todos los procesos del mapa de MC-01 §6.3, los recursos y los riesgos
y oportunidades. Comprende las revisiones ordinarias programadas y las extraordinarias.

## 3. Referencias

- ISO 9001:2015, §9.3 — Revisión por la dirección (§9.3.2 entradas; §9.3.3 salidas).
- API Specification Q1, 9ª edición — §6.5 Revisión por la dirección.
- MC-01 — Manual de Calidad (política §6.1; objetivos e indicadores §6.2).
- PG-02 — Gestión de riesgos (matriz AR-01).
- PG-04 — Compras y evaluación de proveedores (AVL).
- PG-09 / PG-10 — Producto no conforme y CAPA.
- PG-11 — Auditorías internas.
- PG-13 — Competencia y capacitación.
- PG-14 — Gestión del cambio (MoC).

## 4. Definiciones

- **Revisión por la dirección**: evaluación formal, conducida por la Dirección, del estado y
  la eficacia del SGC, con entradas y salidas definidas por la norma.
- **Revisión ordinaria**: la programada con la frecuencia mínima de §6.1.
- **Revisión extraordinaria**: la convocada fuera de programa ante un evento significativo.
- **Minuta**: registro de la revisión (asistentes, entradas tratadas, decisiones, acciones,
  responsables y plazos).
- **Dashboard del ERP**: módulo **Métricas** de VitalStock, que presenta los indicadores
  operativos y el panel de alertas «Para hoy».

## 5. Responsabilidades

- **Dirección**: convoca y conduce la revisión; evalúa las entradas; toma las decisiones de
  salida; asigna los recursos resultantes; aprueba la minuta.
- **Responsable de Calidad**: prepara el paquete de entradas (indicadores del ERP, estado de
  NC/CAPA, resultados de auditorías, estado de la matriz de riesgos); redacta la minuta;
  archiva el registro en la carpeta de calidad; hace el seguimiento de las acciones hasta su
  cierre.
- **Responsable de Producción**: aporta el estado de los procesos de producción (desempeño del
  routing, desvíos de tiempos, mantenimiento de equipos) y participa de la revisión.
- **Responsable de Compras/Administración**: aporta el desempeño de proveedores externos y la
  información comercial y administrativa pertinente, y participa de la revisión.

## 6. Desarrollo

### 6.1 Frecuencia y convocatoria

1. La revisión ordinaria se realiza **como mínimo una vez por año calendario**, con no más de
   12 meses entre revisiones consecutivas.
2. La Dirección convoca una revisión extraordinaria ante cualquiera de los siguientes eventos:
   una no conformidad mayor (interna, de auditoría o reclamo grave de cliente), un cambio
   significativo gestionado por PG-14 que afecte al SGC en su conjunto, un resultado adverso
   de auditoría de certificación, o un incumplimiento sostenido de un objetivo de calidad.
3. Participan la Dirección, el Responsable de Calidad, el Responsable de Producción y el
   Responsable de Compras/Administración. La Dirección puede invitar a otro personal según
   los temas.

### 6.2 Entradas de la revisión

4. El Responsable de Calidad prepara y distribuye antes de la reunión el paquete de entradas,
   que cubre como mínimo (ISO 9001 §9.3.2 y API Q1 §6.5):

   1. **Estado de las acciones de revisiones previas** (minutas anteriores).
   2. **Cambios en las cuestiones externas e internas** pertinentes al SGC, incluyendo los
      MoC tramitados o en curso (PG-14).
   3. **Desempeño y eficacia del SGC**, con la siguiente información:
      - Satisfacción del cliente y retroalimentación de partes interesadas, incluyendo
        reclamos (NC con `origen_tipo` = 'cliente' en el módulo Calidad → NCR/CAPA).
      - **Grado de cumplimiento de los objetivos de calidad** según los indicadores definidos
        en MC-01 §6.2 (OTD, cierre de NC en plazo, proveedores críticos vigentes,
        inspecciones con instrumentos calibrados, trazabilidad de PT).
      - Desempeño de los procesos y conformidad del producto: no conformidades por origen y
        disposición (`no_conformidades`), resultados de inspecciones y ensayos
        (`registros_calidad`).
      - Resultados de las auditorías internas (informes de PG-11) y externas.
      - Desempeño de los proveedores externos: estado de la AVL, reevaluaciones vencidas y
        NC con `origen_tipo` = 'proveedor' (PG-04).
      - Estado de las acciones correctivas y preventivas (`acciones_capa`): abiertas,
        vencidas y verificación de eficacia.
   4. **Adecuación de los recursos**: infraestructura y equipos (estado de herramientas e
      instrumentos, calibraciones), y competencia del personal (estado de la matriz y del plan
      de capacitación, PG-13).
   5. **Eficacia de las acciones tomadas para abordar riesgos y oportunidades**: estado de la
      matriz AR-01 y de sus acciones de mitigación (PG-02 §6.5).
   6. **Oportunidades de mejora** identificadas por cualquier fuente.

### 6.3 Fuente de indicadores: dashboard del ERP

5. La fuente primaria de los indicadores de desempeño es el **dashboard del ERP (módulo
   Métricas)**, que presenta en tiempo real los KPI operativos (stock, producción, ventas,
   márgenes) y el **panel de alertas «Para hoy»**, cuyo digest incluye las alertas de calidad:
   instrumentos con calibración vencida (bloqueados para inspecciones), calibraciones por
   vencer a 30 días, recepciones en cuarentena, no conformidades abiertas, acciones CAPA
   vencidas y proveedores con reevaluación AVL vencida.
6. Los indicadores de los objetivos de calidad se calculan con datos del ERP conforme a la
   tabla de MC-01 §6.2. Dado que el dashboard se consulta en vivo, el Responsable de Calidad
   toma una **captura o exportación con fecha de corte** de los indicadores presentados, que
   se adjunta a la minuta como evidencia del estado evaluado.

### 6.4 Desarrollo de la reunión y salidas

7. La Dirección evalúa cada entrada y deja constancia de las conclusiones. Las salidas de la
   revisión incluyen decisiones y acciones sobre (ISO 9001 §9.3.3 y API Q1 §6.5):
   - **Oportunidades de mejora** del SGC, los procesos y el producto.
   - **Necesidades de cambio en el SGC**, incluyendo la política y los objetivos de calidad;
     cuando el cambio constituye un MoC, se tramita por PG-14.
   - **Necesidades de recursos** (equipamiento, calibraciones, personal, capacitación,
     contratación de auditores externos).
   - La evaluación de la **eficacia general del SGC** y de su alineación con la estrategia.
8. Cada acción de salida se documenta con responsable y plazo. Las que constituyen acciones
   correctivas o preventivas se cargan en el módulo Calidad → NCR/CAPA (`acciones_capa`, con
   `responsable_id` y `fecha_compromiso`), quedando sujetas a la verificación de eficacia de
   PG-10.

### 6.5 Registro y seguimiento

9. La minuta de la revisión se registra en **planilla física archivada en la carpeta de
   calidad** (registro fuera del ERP, conforme a PG-01 §6.5.6 y MC-01 §7), con el contenido
   mínimo: fecha, asistentes, entradas tratadas (con la captura de indicadores adjunta),
   conclusiones, decisiones y acciones con responsable y plazo, y firma de la Dirección.
10. El Responsable de Calidad efectúa el seguimiento de las acciones de la minuta; su estado
    es la primera entrada de la revisión siguiente (§6.2, punto 1).

## 7. Registros asociados

| Registro | Dónde vive | Retención |
|---|---|---|
| Minutas de revisión por la dirección (con captura de indicadores adjunta) | Planilla física, carpeta de calidad (fuera del ERP) | 10 años |
| Indicadores de objetivos de calidad (datos fuente) | Dashboard del ERP, calculados sobre `ventas`, `no_conformidades`, `proveedores`, `registros_calidad`, `productos_terminados` | 10 años (datos protegidos por `fn_proteger_evidencia`) |
| Acciones de salida gestionadas como CAPA | `acciones_capa` (Calidad → NCR/CAPA) | 10 años |
| Informes de auditoría interna (entrada) | Carpeta de calidad (fuera del ERP) | 10 años |
| Matriz de riesgos AR-01 (entrada) | `documentos_controlados` (Calidad → Documentos) | Permanente |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
