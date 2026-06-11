# Panorama comercial Vitalmet

> Análisis estratégico del consejo de agentes — 2026-06-05.
> Cualitativo (sin datos históricos confiables aún). Insumo para reunión de decisión comercial.

## 1. Lectura del panorama

La buena noticia primero: el mercado NO se cayó para Vitalmet, al menos no donde importa. Los dos sectores ancla declarados —petróleo/gas no convencional (Vaca Muerta) y minería (litio, cobre, oro vía RIGI)— están en el mayor boom de capex en años: YPF +US$25.000M, Chevron +US$13.800M, más de US$31.100M en minería pendientes, y programas explícitos para sumar ~200 PyMEs proveedoras en 2026. La mala noticia: ese dinero NO entra por el canal donde Vitalmet está parada. La industria metalmecánica genérica —el segmento que una operación pasiva, esperando consultas entrantes, podía sostener— está en su peor momento en 4 años (capacidad ociosa ~58-60%, acero chino barato con dólar apreciado comiéndole el mercado de piezas commodity). O sea: Vitalmet está sentada al lado de una mina de oro pero enchufada al caño equivocado. El dinero de oil&gas y minería no se gana esperando el teléfono: se gana entrando a los registros de proveedores (proveedores.ypf.com y análogos), homologándose con certificaciones y prospectando activamente a compras. Internamente, la empresa ya construyó casi toda la infraestructura comercial necesaria (sitio multisector, CRM con pipeline y captura de leads, digest diario por Telegram, trazabilidad de coladas en el ERP) pero ninguna de esas palancas está enchufada a un hábito comercial. El diagnóstico honesto: "vendemos poco" es mayormente causa INTERNA (no se prospecta, no se está calificado como proveedor, las herramientas no se usan), sobre una base de causa externa parcial real (la industria genérica que sí se secó).

## 2. Hipótesis ordenadas por probabilidad

### #1 — Captación: casi no entra demanda nueva porque nadie prospecta (MUY PROBABLE)
- **Por qué**: la operación es declaradamente pasiva, el canal de entrada (web multisector + CRM + formulario) recién se construyó y casi no se usa. La web reemplazó WordPress en mayo 2026 y el SEO es nuevo. Sin prospección saliente ni canal entrante maduro, el flujo de consultas nuevas es por definición bajo. Y justo el segmento que alimentaba la pasividad (industria genérica) es el que colapsó.
- **Qué la confirmaría**: pocas o cero consultas/RFQ nuevas por mes, pocos leads cargados en el CRM, tráfico web bajo a las landings de sector (medible HOY con los scripts GA4/GSC).
- **Pregunta al dueño**: "¿Cuántos pedidos de cotización nuevos te entran por mes hoy, y cuántos venían hace 2-3 años? ¿De dónde vienen: recompra de clientes viejos, referidos, o consultas frías nuevas?"

### #2 — Concentración / churn: "vender poco" puede ser un cliente grande que compró menos (PROBABLE)
- **Por qué**: patrón típico de metalúrgica chica con raíz petrolera: 2-3 clientes son casi toda la facturación. El sector es cíclico y depende del capex de pocas operadoras. Si una recortó o cambió de proveedor, la caída agregada se siente fuerte aunque el resto esté igual. No es lo mismo "el mercado compra menos" que "se me cayó una cuenta".
- **Qué la confirmaría**: top 2-3 clientes concentrando >50-60% de la facturación histórica; un cliente que compraba todos los meses y dejó de aparecer.
- **Pregunta al dueño**: "¿Qué % de tu facturación del último año bueno venía de tus 3 clientes más grandes? ¿Alguno compró mucho menos o dejó de comprar este año, y por qué (precio, calidad, plazo, o simplemente tienen menos obra)?"

### #3 — Pricing USD vs costos en pesos: erosión de margen, no de volumen (PROBABLE como problema de margen)
- **Por qué**: el ERP opera 100% en USD, pero los costos reales son híbridos: el operario cobra en pesos, la energía, los servicios y los tratamientos térmicos se pagan en pesos con inflación. Si las listas en USD no se actualizan al ritmo de inflación en pesos + movimientos cambiarios, el margen por pieza se erosiona aunque el número en dólares "parezca" firme.
- **Qué la confirmaría**: listas de precios en USD sin actualizar hace meses; contribución marginal por venta cayendo; costo en pesos subiendo más rápido que el precio USD cobrado.
- **Pregunta al dueño**: "¿Cada cuánto actualizás tus precios en dólares y cuándo fue la última vez? ¿Ganás lo mismo por pieza que hace un año, o el margen se achicó aunque el número en USD sea igual?"
- **Ojo**: esto explica "ganar menos", no "vender menos cantidad". Si la queja es de volumen, no es esta.

### #4 — Conversión: presupuesta y no cierra (MENOS PROBABLE hoy, importante mañana)
- **Por qué**: con operación pasiva y CRM sin usar, probablemente hay pocos presupuestos en circulación. No se puede "perder" lo que no se cotiza. La conversión recién se vuelve cuello de botella DESPUÉS de resolver captación.
- **Qué la confirmaría**: muchos presupuestos en estado enviado/vencido y pocos convertidos; clientes que piden cotización y no responden por falta de seguimiento.
- **Pregunta al dueño**: "De cada 10 presupuestos que mandás, ¿cuántos terminan en venta? Cuando no cierran, ¿sabés por qué (precio, plazo, o no volviste a llamar)?"

### #5 — Capacidad / abastecimiento (LA MENOS PROBABLE)
- **Por qué**: un quiebre de materia prima o tope de capacidad produce "no doy abasto / pierdo pedidos por no poder cumplir", que es lo OPUESTO al síntoma reportado. El ERP ya modela stock de barras en metros con alertas de reorden, así que la restricción sería visible si existiera.
- **Pregunta al dueño** (solo para descartar): "¿Alguna vez rechazaste o demoraste un pedido por falta de acero o de horas-máquina?"

## 3. Lo que ya tienen a favor (activos sin explotar)

- **Trazabilidad de coladas / certificados de material en el ERP**: es EL diferenciador del rubro. Lo que el comprador de oil&gas/minería valora primero es trazabilidad y calidad, recién después precio. Vitalmet ya tiene el andamiaje documental que el resto de los talleres informales no puede replicar. Hoy es puro back-office; debería ser argumento de venta y entregable.
- **Sitio multisector que vende bien**: páginas por sector (petróleo/minería/gas-GNL), FAQs técnicas, normas (API 11B, ASME B16.34, NACE MR0175), logos de clientes, CTAs claros y formulario que captura sector/productos/plazo. No es folletería, es una palanca de captación real.
- **Captura web → CRM funcionando end-to-end**: el formulario inserta el lead directo a Supabase (origen='web_form'), manda mail a ventas y notificación con deep-link al lead. La tubería existe y opera.
- **CRM con pipeline + digest diario por Telegram**: ya hay un mecanismo proactivo que avisa leads nuevos, próximos pasos vencidos y deals estancados >30 días, más un asistente IA sobre el pipeline. La semilla del proceso comercial ya está plantada.
- **AFIP + facturación electrónica + contabilidad completa en el ERP**: cubre buena parte de la documentación fiscal/económica que exigen los portales de proveedores (YPF y mineras). Es ventaja para homologarse, aunque por sí solo NO vende.

El mensaje incómodo: el dueño invirtió mucho en back-office contable sofisticado que no mueve la aguja de vender. Las palancas que SÍ venden están casi todas construidas, pero ninguna está enchufada a una rutina. No falta software. Falta hábito.

## 4. Palancas de acción candidatas (opciones, no plan cerrado)

### Corto plazo (semanas, bajo costo)
- **Homologarse en proveedores.ypf.com** y mapear los registros de 3-4 operadoras/mineras objetivo. Es la tarea #1 del rubro: sin estar inscripto y homologado, se está estructuralmente fuera del flujo de demanda grande, por bueno que sea el producto.
- **Verificar el estado real de las certificaciones** (ISO 9001 / API / API 11B). El sitio ya las comunica; hay que confirmar si están EMITIDAS y vigentes o "en proceso". Comunicar sin tener es riesgo ante una auditoría de compras.
- **Rutina comercial diaria de 15 min**: leer el digest de Telegram, tocar cada lead nuevo y cada próximo paso vencido, cargar el siguiente paso con fecha. Sin tecnología nueva, esto transforma la infra existente en máquina comercial.
- **Catálogo PDF detrás de un mini-form** (nombre + empresa + email → mismo flujo de lead, origen='catalogo'). Hoy se descarga 100% anónimo: cada descarga es un prospecto caliente que se pierde. Mejora de mayor ROI por esfuerzo del sitio.
- **Disparar evento `generate_lead` en GA4** al enviar el formulario (hoy solo trackea 'email_click'). Es una hora de trabajo y habilita saber qué canal/landing trae leads.
- **Reactivar clientes dormidos** vía el módulo de mailings/postventa del ERP: outbound a la cartera existente suele ser el camino más rápido a más facturación.
- **Cargar cuentas objetivo en el CRM proactivamente** (cada operadora/mina/EPC como empresa con su oportunidad de homologación). Hoy el pipeline solo se alimenta de leads entrantes; sin input de salida, el CRM solo documenta la pasividad.

### Mediano plazo
- **Certificación API formal** (Q1 + specs 5CT/11B) si todavía no está: ticket de entrada a operadoras y eventual ventana exportadora regional.
- **Certificado de Conformidad de salida en el ERP**: que junto al remito se genere un certificado de trazabilidad por pieza que herede la colada de origen. Es lo que pide oil&gas/minería para saltear la inspección de entrada, y diferencia de talleres que entregan "sin papeles". Funcionalidad acotada sobre el ERP existente.
- **Indicador de entrega a tiempo (OTD) en el ERP**: los compradores piden histórico de 12 meses; documentarlo convierte cada entrega buena en material de venta para la siguiente.
- **Pedir referencias/testimonios a clientes actuales satisfechos**: en B2B metalmecánico el segundo motor de crecimiento son los referidos dentro del ecosistema (operadora→EPC→otro comprador).
- **Dashboard de atribución por canal** (Marketing.tsx hoy es un stub): costo por lead, ROI por canal, pauta paga. PERO en el orden correcto: primero medir conversiones y trabajar el pipeline, después prender pauta, recién ahí el dashboard. No es el cuello de botella de hoy.

## 5. Preguntas clave para la reunión

La pregunta que parte el problema en dos y decide todo lo demás:
> **"¿Te entran consultas y no cierran, o directamente no te entran consultas?"**

Y después:
1. ¿Cuántas cotizaciones nuevas entran por mes hoy vs. hace 2-3 años, y de dónde vienen (recompra / referido / consulta fría)?
2. ¿Qué % de tu facturación viene de tus 3 clientes más grandes? ¿Alguno se cayó o compró mucho menos este año?
3. ¿Estás inscripto/homologado en el portal de YPF y en registros de mineras u operadoras de Vaca Muerta? ¿En cuáles?
4. Las certificaciones que muestra el sitio (ISO 9001, API, API 11B), ¿están EMITIDAS y vigentes o en proceso?
5. ¿Tenés un comercial dedicado o la venta la hacés vos entre otras tareas? (¿el problema es de capacidad o de método?)
6. ¿Cada cuánto actualizás las listas en USD? ¿Ganás lo mismo por pieza que hace un año?
7. ¿Entregás hoy algún documento de calidad/trazabilidad al cliente con el despacho, o solo el remito?
8. ¿Geográficamente, en qué condiciones estás para entregar a Neuquén/Vaca Muerta y a las provincias mineras (Catamarca, San Juan, Salta, Jujuy) con plazos competitivos? El "compre local" neuquino pesa fuerte.

## 6. Qué datos empezar a cargar

El obstáculo central de este análisis es que ningún sistema tiene historia confiable. Para que la próxima vez el diagnóstico sea cuantitativo, empezar a registrar desde ya:

- **Toda consulta/RFQ entrante en el CRM**, sin excepción, con su origen (web, WhatsApp, referido, llamada). Es el único modo de saber si el problema es de captación o de cierre.
- **Cada presupuesto en el ERP/CRM con su estado real** (enviado → aprobado/rechazado/vencido/convertido), para medir tasa de cierre presupuesto→venta.
- **Facturación por cliente y por sector** (oil&gas / minería / gas / industria / construcción), para medir concentración y exposición al sector que cae vs. los que crecen.
- **Fecha de última actualización de listas de precios USD** y **contribución marginal por venta**, para detectar erosión de margen.
- **Entrega a tiempo (OTD) por pedido**: fecha prometida vs. fecha real de despacho.
- **Evento de conversión en GA4** (`generate_lead`) + **columna `utm_source` en crm_leads**, para atribuir leads a canal/landing/keyword.
- **Registro de actividad de prospección saliente** (cuentas objetivo contactadas, estado de homologación por operadora/mina), para que el pipeline refleje el esfuerzo de salida y no solo lo que entra solo.

Con tres meses de estos datos cargados con disciplina, la próxima reunión deja de discutir hipótesis y empieza a discutir números.
