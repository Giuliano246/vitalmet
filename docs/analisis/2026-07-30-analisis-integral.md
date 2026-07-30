# Análisis integral VitalStock ERP — 2026-07-30

Auditoría profunda de los 9 módulos del ERP, realizada con 8 análisis paralelos
sobre el código real (`index.html` 11.281 líneas, migraciones 001–054, manual,
SGC). Cada análisis se hizo desde todos los roles (dueño, administrativo,
operario de planta, vendedor, comprador, contador externo, responsable de
calidad, auditor ISO/API Q1, cliente final) y comparando contra SAP B1, Odoo,
Tango, Bejerman y NetSuite.

---

## Resumen ejecutivo

**Dónde VitalStock ya le gana a los "mejores ERP":**

- **Gates de calidad en la DB** (hold points que bloquean el avance de la OP,
  calibración vencida que rechaza inspecciones, AVL que bloquea OCs, MTR
  obligatorio, cuarentena real): ni SAP QM ni Odoo Quality tienen enforcement
  así de duro a nivel base de datos.
- **GR/IR con 3-way match + compras fiscal multi-alícuota** (054): patrón SAP
  puro, que Tango no tiene.
- **Modo Contador solo-lectura blindado por RLS + carpeta ZIP mensual**: ningún
  competidor PyME lo tiene tan limpio.
- **Costeo por tiempos reales + margen cotizado vs real por presupuesto**:
  diferencial genuino vs Tango.
- **Trazabilidad colada→barra→OP→PT→venta** consultable con un click.
- **Ctrl+K palette, digest "Para hoy" con ~22 reglas, push server-side (051)**.

**Dónde se concentran los déficits** (4 patrones transversales):

1. **El ciclo del dinero no cierra completo**: retenciones sufridas en cobranzas
   inexistentes (las petroleras retienen siempre), cheques sin asiento, stock
   sin valuar ni kardex, costo real de OP calculado pero nunca persistido,
   bienes de uso/amortizaciones ausentes. El balance que el propio ERP genera
   tiene patas ficticias.
2. **Automatizaciones 80% construidas sin el último eslabón**: la cola de mails
   genera recordatorios que nunca se envían (falta worker server-side), la
   reposición sugiere pero no genera OC, las alertas no llegan por push, el
   dashboard no tiene dimensión temporal ni cash-flow proyectado.
3. **Rituales ISO/API Q1 sin soporte** (§5/§6/§9): auditorías internas, revisión
   por la dirección, matriz de competencias, registro de certificados de calidad
   emitidos, gestión de riesgos, MOC. El ERP demuestra §7/§8 mejor que nadie,
   pero los PG-02/11/12/13/14 existen solo en papel.
4. **El gap del core del negocio**: los planos no viven con la pieza. Para una
   empresa de "repuestos a plano", `codigo_plano` es texto libre y el PDF (si
   existe) está suelto en documentos controlados sin FK. El operario fabrica
   con un papel.

**Bugs/riesgos de integridad encontrados** (arreglar antes que cualquier feature):

| # | Bug | Dónde | Gravedad |
|---|---|---|---|
| B1 | `emitirFactura` hardcodea Factura B, moneda PES, cotización 1, IVA 21, PV 1 → una venta de US$ 5.000 saldría facturada como $5.000 ARS y tipo B a clientes RI | index.html L3379-3406 | **Crítica** — bloquear antes de habilitar el cert X.509 |
| B2 | Editar una OC hace `DEL oc_items` + re-POST y `recepciones_oc.oc_item_id` es ON DELETE CASCADE → borra en cascada recepciones e inspecciones ya hechas | `saveOC` L9731 + mig 002 | **Crítica** — destruye trazabilidad API Q1 |
| B3 | Sin UNIQUE `(proveedor, tipo, letra, nro)` en `facturas_recibidas` ni chequeo en el RPC → la misma factura se contabiliza dos veces | mig 054 | Alta |
| B4 | `deleteOP` borra la orden sin reponer la barra consumida ni tocar el PT generado | L7367 | Alta |
| B5 | `MODULOS_LABELS` desactualizado vs `groupMods` → el grupo Calidad es **inasignable** a empleados no-admin | L7531 vs `aplicarPermisos` L8191 | Alta |
| B6 | Numeración de presupuestos client-side (`'P-'+length+1`) colisiona con borrados o dos sesiones | L10310 | Media |
| B7 | Tarifa operario duplicada: `TARIFA_OPERARIO_USD=18` hardcodeada vs `empresas.tarifa_operario_usd_h` configurable → dos pantallas muestran costos distintos | L8219 vs L10968 | Media |
| B8 | `generarAsientoVenta` (L6894) huérfana — código muerto o asiento faltante | L6894 | Baja |
| B9 | `savePermisos` y `ajustarPreciosPct` no atómicos (loop de requests sin transacción) | L7600, L8537 | Media |
| S1 | Clave del usuario planta débil y conocida; sin 2FA para admins; password mínimo 6 chars | config Supabase | Alta — costo de fix: horas |

---

## Top 12 consolidado (cruzando los 8 análisis)

| # | Paquete | Módulos | Impacto | Esfuerzo |
|---|---|---|---|---|
| 1 | **Paquete integridad**: B1–B9 + S1 | todos | Muy alto | S–M |
| 2 | **Facturación real**: cert X.509 + Factura A + facturar en DOL o USD→ARS por TC día + IVA por alícuota + NC/ND de venta | Ventas/ARCA | Muy alto | M |
| 3 | **Retenciones sufridas en cobranzas** (Gcias/IIBB/SUSS con certificado) — espejo del patrón 054 | Contabilidad | Alto | S–M |
| 4 | **Worker de envío de mails server-side** (pg_cron + Edge Function, patrón 051; mata n8n local y "abrir el ERP") | Transversal | Alto | S–M |
| 5 | **Kardex + ajustes de inventario documentados con asiento + valuación PPP de MP** | Inventario | Alto | M |
| 6 | **Costo real persistido al cerrar OP** (PT valuado al costo, margen congelado) | Producción | Alto | S |
| 7 | **Planos adjuntos a la pieza + visor desde OP/presupuesto/Modo Planta** | Transversal | Muy alto | M |
| 8 | **Dashboard temporal + cash-flow proyectado 30/60/90** + resumen semanal push | Dashboard | Alto | M |
| 9 | **OC desde reposición + descontar OC en tránsito** | Inventario/Compras | Alto | S |
| 10 | **Rituales calidad**: revisión por la dirección → certificados emitidos persistidos → auditorías internas → matriz de competencias | Calidad | Alto (certificación) | S–M c/u |
| 11 | **Cheques con asientos automáticos + bienes de uso/amortizaciones** | Contabilidad | Medio-alto | M |
| 12 | **Comercial activo**: alerta clientes inactivos 90/180d + límite de crédito en `saveVenta` + emails de estado de pedido + registro de gestiones | Ventas | Alto | S–M |

**Quick wins sueltos (todos S):** push de vencimientos de calidad/reposición,
libro IVA Ventas con desglose + posición mensual de IVA, calendario fiscal ARCA
en digest, historial de precios de compra por material, backup self-service
(botón "Exportar todo" reusando `zipStore`), asientos modelo/recurrentes,
reporte ventas por vendedor, import Excel de proveedores/insumos, margen por
cliente y punto de equilibrio en dashboard, drill-down en KPIs.

**Hoja de ruta sugerida:**

- **Sprint 1 — Integridad y seguridad** (1 semana): paquete 1 completo + S1.
- **Sprint 2 — El ciclo del dinero** (2-3 semanas): 2, 3, 6, 11 + IVA ventas.
- **Sprint 3 — Automatización que ya está a medio construir** (1-2 semanas): 4, 9, 12 + push + quick wins.
- **Sprint 4 — Inventario auditable** (2 semanas): 5 + conteo físico.
- **Sprint 5 — Calidad certificable** (2 semanas): 10 + tablero KPIs calidad + modo auditor.
- **Sprint 6 — El diferencial** (2 semanas): 7 (planos) + 8 (dashboard/cash-flow).

---

## Anexo A — Inventario

- **Sin kardex**: `kg_disponibles`/`cantidad` son saldos mutables sin historial de movimientos. Crear `movimientos_stock` insertando desde los 4 puntos de mutación existentes (`consumir_barra`, recepción, trigger de venta, ajustes).
- **Ajustes sin documento ni asiento**: `saveEditBarra` (L7136) pisa kg con PATCH pelado; deletes duros de barras/PT/insumos. Único módulo donde se mueve plata sin asiento.
- **MP sin valuar**: barras sin costo (el dato viaja en `oc_items.precio_unitario` y se tira al recibir). Bienes de Cambio del balance es ficción.
- **Sin conteo físico/inventario cíclico**.
- **Maestro de artículos texto libre**: `barras.material`, `pt.pieza`, insumos deduplicados por nombre exacto → duplicados.
- **Unidades inconsistentes**: columna `kg_disponibles` mostrada como "mts"; sin conversión kg↔mts↔barras.
- **Reposición ciega a OC en tránsito** (`calcReordenMaterial` L3680): puede sugerir doble compra.
- **Dos sistemas de mínimos desconectados**: `kg_minimo` por lote vs ROP por material.
- **Reserva de PT soft** (`getPTReservado` L3758): no persiste ni bloquea doble venta (aceptable con 1 vendedor).
- Fortalezas: ROP con safety stock real (Z·√(LT·σ²d+d²·σ²LT)), lote-céntrico nativo, calibraciones de herramientas con bloqueo, trazabilidad colada.
- Prioridad: kardex → ajustes documentados → OC desde reposición + tránsito → valuación PPP → conteo físico.

## Anexo B — Producción

- **Costo real nunca persistido**: `saveOP`/`saveEditOP` escriben `costo_unitario` = precio tipeado (L3312/L7354), no `computeCostoPT`. Sin snapshot al cierre: una OP de marzo recalculada en julio da otro número. Fix S: persistir `costo_real_usd` al cerrar.
- **`deleteOP` no repone stock** (B4).
- **Sin BOM**: consumo = 1 barra + kg; insumos nunca se descuentan contra OP (BOM liviana solo si duele — regla no especular).
- **Sin scheduling**: `maquina` texto libre, sin centros de trabajo ni carga. Primera etapa útil: fecha de entrega sugerida por backlog de minutos por máquina.
- **Estados pobres**: crear la OP ya consume MP aunque nadie haya arrancado (falta `planificada`).
- **Scrap**: `merma_kg` a mano; el PT recibe la cantidad nominal aunque haya rechazos; sin vínculo OP→NCR automático.
- **Cuenta planta compartida** → `op_time_entries.operario_id` no identifica a la persona (observación Q1 §5.4 segura). Fix: selector de operario/PIN al iniciar timer.
- **Timer olvidado**: nada detecta un timer corriendo >12 h — ensucia eficiencia y costos.
- **Tratamientos sin costo ni estado enviado/recibido** — material fuera de planta invisible.
- **Tarifa operario duplicada** (B7). **Doble captura de horas**: `horas_total` legacy convive con timers.
- Fortalezas: multi-timer con índice único parcial, Modo Planta QR con lockdown RLS ejemplar, hold/witness gates en DB, margen cotizado vs real.
- Prioridad: persistir costo (S) → fix deleteOP (S) → alertas OP demorada/timer olvidado (S) → operario individual (M) → fecha sugerida por carga (M).

## Anexo C — Compras

- Fortalezas post-054: fiscal completo, AVL con gate en DB, inspección de entrada con NC automática, 3-way match con override auditado, alta rápida por CUIT.
- **B2 y B3** (arriba) son de este módulo.
- **Sin cta cte de proveedores**: el pago es asiento global sin imputación a facturas; la "deuda" de `renderProveedores` mezcla USD+ARS sin convertir (L9553). Sin aging de pagos.
- **Sin órdenes de pago con retenciones EMITIDAS** (Gcias RG 830/IIBB/SUSS + SICORE/SIRE): verificar con el contador si Vitalmet es agente de retención; si lo es, obligación legal.
- **Sin aprobación de OC**: cualquier usuario crea/edita/borra; estados saltables libremente; sin límites por monto (hallazgo Q1 5.6.1.1 esperable). Reusar molde `fn_oc_avl_gate`.
- **Devolución a proveedor = solo un badge** en NCR; sin documento que revierta stock/GR-IR.
- **Sin historial de precios de compra** por material/proveedor (datos ya en `oc_items`).
- **Sin vencimiento de documentación de proveedores** (cert ISO, seguros) — patrón 040 aplicable.
- **Importaciones/landed cost**: solo si empiezan a importar en serio.
- Prioridad: fixes B2/B3 (S) → OC desde reposición (S) → orden de pago + retenciones + cta cte proveedor (L) → aprobación de OC (M).

## Anexo D — Ventas

- **B1** (facturación hardcodeada) es de este módulo — el hallazgo más crítico de toda la auditoría.
- **La cola de mails no despacha**: `generarRecordatoriosAuto` (L8568) genera cobranzas y follow-ups que quedan en `email_queue` para siempre; el despachador previsto (n8n Docker en la Mac) es frágil. Worker server-side = ROI inmediato sobre código ya escrito.
- **Clientes inactivos**: nadie avisa "cliente sin comprar hace 90/180 días" — el problema comercial declarado es captación/reactivación; es un filter de 10 líneas + template.
- **Límite de crédito**: `clientes.limite_credito` existe en schema y no está ni en el modal ni en `saveVenta`/`convertirPresupuesto`. Check estándar de cualquier ERP.
- **Listas de precios y vendedores son cascarón**: tablas existen (006/019), sin CRUD, `resolverPrecio` ignora `lista_precios_id`.
- **Sin comisiones/reporte por vendedor** (`vendedor_id` se guarda y muere).
- **Sin entregas parciales/backorder**: venta atómica, stock descontado al registrar el pedido; hacerlo cuando duela (pedidos grandes multi-ítem).
- **Cobros sin imputación a facturas puntuales** (FIFO implícito), sin recibo PDF, sin retenciones sufridas (ver Contabilidad).
- **Sin emails de estado al cliente** (confirmado/despachado+remito/factura) — templates y cola ya existen.
- **B6** numeración presupuestos.
- Fortalezas: pipeline con ciclo de venta, costeo real al cotizar, OTD, ficha 360, conversión atómica presupuesto→venta→OP, facturación en lote, digest.
- Prioridad: facturación real (M) → worker mails (S) → clientes inactivos (S) → emails de estado (S-M) → límite de crédito (S) → gestiones por presupuesto (M).

## Anexo E — Calidad

- Fortalezas: gates duros en DB (039/041/042/043/046), retención de evidencia (044), NC numerada server-side con guards Q1 (§5.10.3), trazabilidad de colada, cert de conformidad PDF con cadena completa.
- **G1 Auditorías internas (Q1 §5.9)**: cero soporte — sin programa, checklists ni hallazgos→NC. Sin un ciclo registrado no hay certificación.
- **G2 Revisión por la dirección (§5.1.3)**: el ERP ya calcula casi todas las entradas; falta la tabla que congele snapshot de KPIs + decisiones. Esfuerzo S.
- **G3 Competencias/capacitación (§5.3)**: los signoffs existen pero nada prueba que el firmante era competente.
- **G4 Riesgos (PG-02)**: matriz sev×prob → AP; hoy las preventivas "por análisis de riesgo" no tienen origen registrado.
- **G5 MOC/ECN (§5.11, exclusivo Q1)**: revisión de plano del cliente = ECN obligatoria; hoy nada traza el porqué ni el impacto en OPs abiertas.
- **G7 Certificados de calidad emitidos no quedan registrados**: `generateCertConformidadPDF` (L10711) hace `doc.save()` y listo — sin número correlativo persistido ni copia. Esfuerzo S con patrón NC existente.
- **G8 Calibración**: falta as-found/as-left + evaluación de impacto de instrumento no conforme (ISO §7.1.5.2).
- Push de vencimientos: `computeAlertas` + `push_subscriptions` ya existen, falta el cron.
- Modo auditor solo-lectura: clonar policies del Modo Contador (053) — costo mínimo, efecto enorme.
- Prioridad: G2→G7→push (una semana, tres golpes) → G1 y G3 (condicionan certificación) → tablero KPIs → G4/G5.

## Anexo F — Contabilidad

- Fortalezas: partida doble por constraint de DB, períodos+correlatividad, RT6 con RECPAM, cierre en 4 pasos, bimonetario, ratios con semáforos, conciliación bancaria con sugerencias, GR/IR, Modo Contador, carpeta ZIP.
- **Retenciones SUFRIDAS en cobranzas: no existen** — el agujero más grave; los clientes petroleros retienen Gcias/IIBB/SUSS al pagar y hoy la cta cte queda con deuda fantasma. Espejo del patrón 054. Esfuerzo S-M.
- **Cheques sin asientos**: cartera de valores fuera del balance; depósito/rechazo no mueven contabilidad.
- **Bienes de uso/amortizaciones: ausentes** — metalúrgica con tornos/CNC; además la RT6 queda incompleta en su partida principal.
- **Libro IVA Ventas plano** (una columna, sin alícuotas) — asimétrico vs compras post-054. **Sin posición mensual de IVA** armada.
- **Sin diferencias de cambio automáticas** al cobrar/pagar ni al cierre.
- **Sin asientos modelo/recurrentes**, sin presupuesto vs real, sin previsión incobrables, sin cash-flow proyectado (insumos todos disponibles).
- **Conciliación**: falta conciliar masivo, matching 1-a-N, reglas por descripción (SIRCREB→percepción IIBB automática — plata fiscal que hoy se pierde de registrar), import CSV/OFX.
- **Cierre mensual sin checklist** (GR/IR abiertos, borradores, extracto sin conciliar).
- **Calendario fiscal ARCA**: cero alertas de vencimientos (tabla estática + push, esfuerzo S).
- `generarAsientoVenta` huérfana (B8).
- Prioridad: retenciones sufridas → IVA ventas + posición IVA → cheques con asientos → calendario fiscal → cierre asistido → activos fijos → reglas conciliación.

## Anexo G — Dashboard / BI

- Fortalezas: digest "Para hoy" (~22 reglas), 5 charts, costeo real, margen cotizado-vs-real, 19 ratios, exportables testeados, Ctrl+K, push 08:00.
- **Sin dimensión temporal**: KPIs todos acumulados históricos — no hay "este mes vs anterior", MTD/YTD ni chart de facturación mensual. Gap #1; esfuerzo S.
- **Sin snapshot mensual de KPIs** (`kpi_snapshots` + pg_cron): habilitador de tendencias, comparaciones honestas (costo congelado) y anomalías.
- **Sin cash-flow proyectado 30/60/90** (cheques + vtos proveedor + ctacte): la pregunta que desvela a una PyME argentina.
- **Aging asimétrico**: cobranzas con buckets completos, pagos solo alerta binaria.
- **Sin drill-down** (KPIs y charts muertos; `showPage(page,id)` ya existe).
- **Margen por cliente calculado pero no mostrado** en dashboard; sin punto de equilibrio (calculable hoy).
- **Umbrales de alertas hardcodeados** (7d/3d/30d, semáforos de margen).
- **Sin resumen semanal gerencial push** (infra completa; solo payload nuevo).
- Prioridad: KPIs con período (S) → resumen semanal (S) → drill-down (S) → snapshots (M) → cash-flow (M) → anomalías (M).

## Anexo H — Transversal (plataforma, seguridad, integraciones)

- Fortalezas: RLS por capas con enforcement real (planta/contador), anti-escalada (022), auditoría con datos_old/new en 15 tablas, CSP dura en netlify.toml, esc() sistemático, anulación-no-borrado, import Excel de clientes/PT, mailings con aprobación humana.
- **Permisos por módulo solo visuales** (decisión documentada): cualquier empleado autenticado puede GET cualquier tabla; `ver_costos` viaja igual por API. Reevaluar cuando entre el primer vendedor externo (L).
- **B5** (Calidad inasignable) + `savePermisos` no atómico (B9).
- **Auditoría sin UI**: nadie mira `audit_log`; sin trigger en `usuarios`, `permisos_usuario`, `config_contable`, `precios_base` (cambios de roles y precios sin rastro).
- **Cero backup self-service**: continuidad 100% delegada en Supabase sin verificación; botón "Exportar todo" (ZIP reusando `zipStore`) = S.
- **Sin offline en planta**: corte de wifi frena el fichaje; cola localStorage con retry (M).
- **El gap del negocio: planos no vinculados a la pieza** — FK `plano_doc_id` → `documentos_controlados` en PT/artículo + visor en OP, presupuesto y planta.html. Multiplica el Modo Planta ya construido.
- **Ecosistema desconectado**: CRM/web/ERP sin sync de clientes; PostgREST ya es una API — falta contrato + key dedicada.
- **Automatización dependiente del navegador**: recordatorios corren "al abrir el ERP"; migrar a pg_cron + Edge Function (patrón 051).
- **S1**: clave planta conocida, sin 2FA (Supabase MFA TOTP disponible), password mínimo 6.
- **Config mínima**: tarifa operario, datos fiscales para PDFs y `billing_api_key` (prompt+localStorage) hardcodeados/invisibles.
- Deuda aceptada: adjuntos base64 en DB (migrar a Storage cuando pese), sin paginación en `loadAll` (techo a 2-3 años de datos).
- Prioridad: S1 (horas) → planos (M) → backup (S) → worker mails (M) → B5+B9 (S) → visor auditoría (M) → sync CRM (M).
