# PG-09 — Control de producto no conforme

| Campo | Valor |
|---|---|
| **Código** | PG-09 |
| **Revisión** | 0 |
| **Fecha de emisión** | 2026-07-01 |
| **Elaboró** | Responsable de Calidad |
| **Revisó** | Dirección |
| **Aprobó** | Dirección |
| **Cláusulas que satisface** | ISO 9001:2015 §8.7 · API Q1 §5.10 (Control de producto no conforme), incl. §5.10.3 (notificación al cliente) |

## 1. Propósito

Establecer la metodología para identificar, documentar, segregar, evaluar y disponer las salidas no conformes con los requisitos, en cualquier etapa del proceso — desde la recepción de materia prima hasta el producto ya entregado al cliente —, asegurando que ningún producto no conforme se use, se procese o se entregue de manera no intencionada, y que toda no conformidad quede registrada con su disposición y evidencia de cierre.

## 2. Alcance

Aplica a toda no conformidad detectada sobre producto o proceso en Vitalmet S.A., cualquiera sea su origen:

- Materia prima o insumos no conformes detectados en la inspección de entrada (recepciones rechazadas, PG-05).
- Producto en proceso no conforme detectado durante la producción o en una inspección/ensayo del routing (PG-06).
- Producto terminado no conforme detectado antes del despacho.
- Producto no conforme detectado después de la entrega (reclamo de cliente), incluyendo la obligación de notificación al cliente (API Q1 §5.10.3).
- No conformidades de proveedor y hallazgos de auditoría que afecten producto.

El tratamiento de la causa raíz y las acciones correctivas/preventivas derivadas de una no conformidad no forman parte de este procedimiento: se rigen por PG-10 (CAPA). Las no conformidades de sistema (hallazgos de auditoría interna sin producto afectado) se documentan con este mismo registro (`origen_tipo` = 'auditoria') pero su tratamiento es directamente una CAPA según PG-10.

## 3. Referencias

- ISO 9001:2015, §8.7 — Control de las salidas no conformes.
- API Specification Q1, 9ª edición — §5.10 Control of Nonconforming Product (incl. §5.10.3 Customer Notification).
- MC-01 — Manual de Calidad (objetivo de calidad Nº 2: cierre de NC en ≤ 30 días).
- PG-01 — Control de documentos y registros (retención y protección de la evidencia).
- PG-05 — Inspección de entrada (recepciones rechazadas).
- PG-06 — Control de producción y PQP (resultados de ensayo no conformes).
- PG-10 — Acciones correctivas y preventivas (CAPA).

## 4. Definiciones

- **NC / NCR**: no conformidad / registro de no conformidad; incumplimiento de un requisito, documentado en la tabla `no_conformidades` del ERP. En pantalla se identifica como NC-nnnn.
- **Disposición**: decisión documentada sobre el destino del producto no conforme. Valores admitidos por el sistema (`no_conformidades.disposicion`): 'retrabajo', 'reproceso', 'rechazo', 'concesion', 'devolucion_proveedor'.
- **Retrabajo**: acción sobre el producto para que cumpla el requisito original (queda sujeto a re-inspección).
- **Reproceso**: acción sobre el producto para volverlo apto por una vía distinta de la original (queda sujeto a re-inspección).
- **Concesión (uso como está)**: autorización para usar o liberar producto que no cumple el requisito, con justificación documentada y, cuando el requisito es de cliente, con su aceptación.
- **Rechazo / scrap**: el producto se descarta; se identifica y segrega para impedir su uso.
- **Devolución a proveedor**: el producto no conforme de origen externo retorna al proveedor.
- **Origen** (`no_conformidades.origen_tipo`): fuente de detección — 'recepcion', 'produccion', 'cliente', 'proveedor', 'auditoria', 'otro'.

## 5. Responsabilidades

- **Dirección**: aprueba la disposición de las no conformidades mayores (ver 6.3.2); provee los recursos para segregar y tratar el producto no conforme.
- **Responsable de Calidad**: administra el módulo Calidad → NCR del ERP; evalúa cada NC y decide (o eleva) la disposición; tiene autoridad para detener producción y despacho ante producto no conforme (MC-01 §6.4), con independencia de Producción; verifica la re-inspección tras retrabajo/reproceso; gestiona la notificación al cliente cuando el producto ya fue entregado; cierra las NC.
- **Responsable de Producción**: detecta y reporta las NC de proceso; segrega e identifica el producto no conforme en planta; ejecuta los retrabajos/reprocesos dispuestos; no continúa operaciones sobre producto no conforme sin disposición.
- **Responsable de Compras/Administración**: gestiona las devoluciones a proveedor y las notas de débito/crédito asociadas; comunica al proveedor la NC cuando el origen es 'recepcion' o 'proveedor' (insumo para su evaluación en la AVL, PG-04).
- **Todo el personal**: tiene la obligación de reportar producto sospechoso de no conformidad al Responsable de Calidad.

## 6. Desarrollo

### 6.1 Detección y apertura de la NC

1. Toda no conformidad se registra en el ERP, en el módulo **Calidad → NCR** (tabla `no_conformidades`), mediante el botón **+ Nueva NC**. El registro exige como mínimo: `fecha`, `origen_tipo` y `descripcion` (qué se detectó, contra qué requisito, cantidad afectada — la descripción es obligatoria: el sistema no guarda sin ella).
2. El número de NC lo asigna la base de datos: si se carga sin número, el trigger `fn_nc_numero` toma el siguiente correlativo de la empresa bajo advisory lock (misma técnica que la numeración de asientos), y la combinación (empresa, número) es única (restricción UNIQUE sobre `empresa_id, numero`). El mismo trigger asienta automáticamente quién detectó la NC (`detectado_por` = usuario autenticado, si no se indica otro). En pantalla la NC se muestra como NC-nnnn.
3. La NC se **vincula a la transacción real de origen** desde el propio formulario: OP vinculada (`orden_id`), recepción vinculada (`recepcion_id`) o venta vinculada (`venta_id`). A nivel de base existe además el vínculo `registro_calidad_id` al registro de inspección/ensayo que la originó. Estos vínculos sostienen la trazabilidad de la NC hasta la colada (PG-07).
4. Disparadores típicos de apertura, según el origen:
   - **Recepción** ('recepcion'): una recepción rechazada en la inspección de entrada. Al rechazar una recepción, el sistema bloquea la barra vinculada y recuerda en pantalla registrar la NC en Calidad → NCR (PG-05).
   - **Producción** ('produccion'): un registro de inspección/ensayo con `registros_calidad.resultado` = 'no_conforme'. El sistema lo advierte al guardar («Registro NO CONFORME guardado — registrá la NC en Calidad → NCR») y el resultado no conforme impide firmar el punto de control del routing (PG-06 §6.3).
   - **Cliente** ('cliente'): reclamo sobre producto entregado; se vincula la venta (`venta_id`) y aplica 6.4.
   - **Proveedor** ('proveedor') y **Auditoría** ('auditoria'): NC detectadas fuera de una recepción puntual o en auditorías internas/externas.
5. La NC nace en `estado` = 'abierta'. Las NC abiertas aparecen automáticamente en el panel «Para hoy» del dashboard (digest de alertas, `computeAlertas()`), lo que impide que queden olvidadas.

### 6.2 Identificación y segregación del producto no conforme

6. El producto físico afectado se identifica de inmediato (tarjeta, marcado o precinto según IT-03) y se segrega a la zona de material no conforme, para prevenir su uso no intencionado.
7. El sistema refuerza la segregación en los casos que administra:
   - La materia prima rechazada en recepción queda con `estado_calidad` distinto de 'aceptado', y el sistema **impide consumir barras no liberadas** en una OP (RPC `consumir_barra`, PG-06 §6.2).
   - En producción, un resultado no conforme impide firmar el hold/witness point asociado, y el gate `fn_op_quality_gate` bloquea el avance del routing sobre un hold sin firmar (PG-06 §6.3): el producto en proceso no conforme no avanza.
8. Ninguna operación posterior se ejecuta sobre producto no conforme hasta que exista una disposición registrada.

### 6.3 Evaluación y disposición

9. El Responsable de Calidad evalúa la NC y registra la **disposición** en el ERP (`no_conformidades.disposicion`): 'retrabajo', 'reproceso', 'rechazo', 'concesion' o 'devolucion_proveedor', junto con su **justificación** (`justificacion`).
10. La justificación es **obligatoria cuando la disposición es 'concesion'**: el formulario del ERP no guarda una concesión sin justificación. Además, si la concesión afecta un requisito acordado con el cliente, requiere la aceptación previa del cliente, cuya evidencia (correo u otro documento) se conserva en la carpeta de calidad referenciando el número de NC.
11. **NC mayores**: se consideran mayores las NC con disposición 'concesion' o 'rechazo' sobre producto terminado de alta presión, y toda NC sobre producto ya entregado. Su disposición la aprueba la **Dirección** (MC-01 §5); la aprobación se documenta en la `justificacion` de la NC («Disposición aprobada por Dirección, fecha») o en registro adjunto en la carpeta de calidad. La clasificación mayor/menor es una definición de este procedimiento; el sistema no la impone.
12. Ejecución según disposición:
    - **Retrabajo / reproceso**: Producción ejecuta la acción dispuesta; el producto se somete a **re-inspección** contra el requisito original, con nuevo registro en `registros_calidad` (PG-06 §6.3). No se libera producto retrabajado sin re-inspección conforme.
    - **Rechazo**: el producto se marca y se dispone como scrap; se descuenta del stock por el circuito normal del módulo correspondiente.
    - **Concesión**: el producto se libera «como está», con la justificación y las aceptaciones de 6.3.10 documentadas.
    - **Devolución a proveedor**: Compras gestiona el retorno; la NC alimenta la evaluación del proveedor en la AVL (PG-04).
13. Mientras se ejecuta el tratamiento, el `estado` de la NC se pasa a 'en_tratamiento' desde el selector de estado de la grilla NCR.

### 6.4 Producto no conforme detectado después de la entrega (API Q1 §5.10.3)

14. Si la no conformidad afecta producto **ya entregado** (o se detecta que producto entregado pudo salir no conforme), el Responsable de Calidad **notifica al cliente** de manera inmediata y documentada, indicando producto, lote/colada afectada y riesgo asociado. La trazabilidad por colada del ERP (PG-07) permite determinar el alcance exacto de los lotes comprometidos.
15. La notificación se asienta en el campo `no_conformidades.cliente_notificado` ('Sí' / 'No (pendiente)'; 'N/A' cuando el producto no fue entregado). **Una NC de origen 'cliente' o con `venta_id` vinculado no se cierra con la notificación pendiente**: este control es procedimental (el sistema registra el campo pero no bloquea el cierre por él), por lo que el Responsable de Calidad lo verifica expresamente antes de cerrar.
16. La evidencia de la notificación (correo, minuta) se conserva en la carpeta de calidad referenciando el número de NC.

### 6.5 Cierre de la NC

17. La NC se cierra pasando su `estado` a 'cerrada' desde el selector de la grilla, una vez ejecutada y verificada la disposición. El sistema **impide cerrar una NC sin disposición registrada**: el guard de base de datos `fn_nc_cierre_guard` (trigger `trg_nc_cierre_guard`) rechaza el cierre con el error «La NC n no se puede cerrar sin disposición» y, cuando el cierre procede, estampa automáticamente la fecha y hora de cierre en `cerrada_at`.
18. Antes de cerrar, el Responsable de Calidad verifica: disposición ejecutada, re-inspección conforme (si aplicó retrabajo/reproceso), cliente notificado (si aplicó 6.4) y evaluación de necesidad de CAPA (6.6).
19. Conforme al objetivo de calidad Nº 2 de MC-01, las NC se cierran en **≤ 30 días**; el indicador se calcula sobre la diferencia entre `fecha` y `cerrada_at` de las NC con `estado` = 'cerrada'.

### 6.6 Vinculación con acciones correctivas (PG-10)

20. Toda NC se evalúa respecto de la necesidad de una acción correctiva. Es **obligatorio abrir una CAPA** (PG-10) cuando la NC: (a) tiene origen 'cliente'; (b) su disposición es 'concesion' o 'rechazo' de producto terminado; (c) es repetitiva (misma causa o mismo modo de falla que otra NC de los últimos 12 meses); o (d) surge de auditoría. Para el resto, el Responsable de Calidad decide y deja constancia del criterio en la descripción o justificación de la NC.
21. La CAPA se abre directamente desde la fila de la NC con el botón **+ CAPA**, que precarga el vínculo `acciones_capa.nc_id` con la NC de origen. El cierre de la NC (disposición ejecutada sobre el producto) es independiente del cierre de la CAPA (eliminación de la causa raíz, que exige verificación de eficacia según PG-10).

### 6.7 Protección del registro

22. Los registros de `no_conformidades` están protegidos como evidencia de calidad (PG-01): toda operación INSERT/UPDATE/DELETE queda asentada en `audit_log` con el diff de valores (trigger `trg_audit`), el DELETE está restringido a administradores (trigger `trg_proteger_evidencia`, función `fn_proteger_evidencia`) y el acceso está aislado por empresa (política RLS `tenant_isolation`).

## 7. Registros asociados

| Registro | Dónde vive en el ERP | Retención |
|---|---|---|
| No conformidades (con origen, disposición, justificación, notificación al cliente y cierre) | `no_conformidades` (Calidad → NCR) | 10 años (protegidas por `fn_proteger_evidencia`) |
| Registros de re-inspección tras retrabajo/reproceso | `registros_calidad` (OP → botón Ensayo) | 10 años |
| Historia de cambios de cada NC | `audit_log` (solo lectura de administradores) | 10 años |
| Aceptación del cliente ante concesión / evidencia de notificación al cliente | Carpeta de calidad (fuera del ERP), referenciando el Nº de NC | 10 años |
| Acciones CAPA derivadas | `acciones_capa` (Calidad → NCR/CAPA; ver PG-10) | 10 años |

## 8. Control de cambios

| Rev | Fecha | Descripción |
|---|---|---|
| 0 | 2026-07-01 | Emisión inicial |

---
*La numeración API Q1 referencia la estructura de la 9ª edición; verificar contra la edición
vigente adquirida antes de la auditoría de certificación.*
