# Paquete 3 — Comercial: mailings, alertas, cobros por selección, pipeline

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano (diseño conversado en sesión)
**Contexto:** tercer paquete del roadmap (P1 Producción y P2 Navegación LIVE). Toca DOS repos: `~/vitalmet-erp` (UI) y `~/vitalmet-billing` (worker de envío, FastAPI en Railway).

## Decisiones tomadas con Giuliano

1. **Worker de envío**: en el billing service de Railway (24/7), vía Microsoft Graph desde `ventas@vitalmetsa.com`. Credenciales como env vars de Railway (no en la tabla `integracion_microsoft`).
2. **Generación de recordatorios**: automática diaria en el frontend del ERP (al abrir, 1×/día) + cola de aprobación manual. Nada sale sin aprobación explícita.

## Infraestructura existente (migración 004, ya corrida)

- `email_templates` (con seeds), `email_queue` (estados `pendiente_aprobacion → aprobado → enviado | cancelado | fallido`, con `scheduled_at`, `venta_id`, `cliente_id`, `graph_msg_id`, `error_texto`), `email_log` (histórico), `mailings_config`, `integracion_microsoft` (no se usa en esta fase).
- El plan incluye verificación de que las tablas/seeds existen en prod antes de construir encima.

## 3D. Cobros/pagos: tercero por selección (primera task — fix de bug latente)

- En el modal de cobro/pago, el input libre de tercero se reemplaza por un `<select>`: clientes (modo cobro) o proveedores (modo pago), ordenados alfabéticamente, con opción final `Otro…` que muestra un input de texto libre (comportamiento actual) para casos raros.
- El valor guardado sigue siendo el NOMBRE (el sistema matchea cta. cte. por nombre en el memo del asiento) — el select garantiza match exacto. Sin migración.

## 3C. Alertas nuevas en computeAlertas()

Nuevos detectores (mismo patrón `{sev, count, titulo, detalle, page}` que los ~15 existentes):
1. **OCs demoradas**: `fecha_entrega_esperada < hoy` y estado no recibido/cerrado. sev crit. → page compras.
2. **Facturas de proveedor por vencer/vencidas**: `factura_vto` dentro de 7 días (warn) o vencida (crit) en OCs con factura cargada. → compras.
3. **Ventas entregadas sin facturar**: estado `entregado` sin `factura_emitida_id` hace 3+ días. warn. → ventas.
4. **Presupuestos aprobados sin convertir ni OP**: estado `aprobado` sin OP vinculada (`ops.presupuesto_id`) y sin convertir, 5+ días. warn. → presupuestos.
5. **Emails esperando aprobación**: count de `email_queue` con `estado=pendiente_aprobacion` (dato cargado por el módulo mailings; si no está cargado, se omite silenciosamente). warn. → mailings.

## 3A. Módulo Mailings (UI)

- Página `mailings` en el grupo `ventas` (registro estándar: `PAGE_TO_GROUP`, `GROUP_TABS.ventas`, `groupMods`, `PAGE_RENDERS`, HTML con `.tabs`).
- Tres vistas internas (sub-tabs propias tipo `switchComprasTab`): **Cola** · **Templates** · **Historial**.
- **Cola**: tabla de `email_queue` pendientes de aprobación (para, asunto, origen venta/presupuesto, programado para). Acciones por fila: 👁 preview (modal con el HTML renderizado), ✎ editar subject/body, ✓ Aprobar (PATCH `estado=aprobado`, `aprobado_por`, `aprobado_at`), ✗ Cancelar. Botón "Aprobar todos".
- **Templates**: tabla de `email_templates` + modal de edición (nombre, subject, body_html en textarea, activo). Sin builder visual — HTML crudo con placeholders documentados en el modal.
- **Historial**: `email_log` (fecha, para, asunto, estado del queue asociado si `fallido`).
- Datos on-demand: `ensureMailingsData()` carga las 3 tablas al entrar (patrón de Eficiencia), invalidación tras mutaciones. NO entra en `loadAll`.
- Badge en nav ventas con pendientes (vía `_updateNavAlert` o equivalente).

## 3B. Generación automática + worker de envío

### Generador (frontend ERP)
- `generarRecordatoriosAuto()` corre post-login si `localStorage.lastMailGen !== hoy` (marca al terminar).
- Fuentes (los mismos cómputos del digest):
  - **Cobranza vencida**: por cliente con saldo vencido (reutiliza `computeCtaCte`), template tipo `cobranza`; requiere `cliente.email` — sin email se omite y se lista en un aviso.
  - **Presupuesto sin respuesta 7+ días**: estado `enviado`, `fecha` ≤ hoy-7; template tipo `seguimiento_presupuesto`; destinatario = cliente del presupuesto (lookup por nombre en clientes).
- Placeholders resueltos al encolar (`{cliente}`, `{monto}`, `{dias}`, `{nro}`, etc. según template). `scheduled_at = now()`.
- **Anti-duplicados**: antes de encolar, GET a `email_queue` filtrando por `venta_id`/`cliente_id` (cobranza) o referencia al presupuesto en subject, con `estado in (pendiente_aprobacion, aprobado)` o `enviado` hace <7 días → skip.
- Si faltan los templates tipo `cobranza`/`seguimiento_presupuesto`, se crean seeds desde el frontend la primera vez (INSERT con `WHERE NOT EXISTS` vía verificación previa).
- Al terminar: notify "N recordatorios generados — revisalos en Mailings" y refresh del badge.

### Worker (vitalmet-billing, FastAPI en Railway)
- Task asyncio en el lifespan: cada 5 minutos procesa `email_queue` `estado=aprobado AND scheduled_at<=now()`:
  1. Obtiene token Graph por client credentials (`TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET` de env; scope `https://graph.microsoft.com/.default`; cache hasta expiración).
  2. `POST /v1.0/users/{MAIL_SENDER}/sendMail` con subject/body_html/to.
  3. OK → PATCH `estado=enviado`, `enviado_at`, `graph_msg_id` (si disponible) + INSERT en `email_log`.
  4. Error → `estado=fallido` + `error_texto` (no reintenta automáticamente; re-aprobar desde la UI lo re-encola).
- Acceso a Supabase con `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` (env de Railway) vía REST (httpx), bypassa RLS.
- Env vars nuevas: `MS_TENANT_ID`, `MS_CLIENT_ID`, `MS_CLIENT_SECRET`, `MAIL_SENDER=ventas@vitalmetsa.com`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `MAILER_ENABLED=true`.
- **Dependencia de Giuliano**: crear la app en Azure AD (guía `docs/azure-ad-setup.md`, permiso de aplicación `Mail.Send` + admin consent) y cargar las env vars en Railway.
- Endpoint `GET /mailer/status` (con la api key existente) para diagnóstico: pendientes, aprobados, últimos errores.

## 3E. Métricas de pipeline (página Presupuestos)

Se agregan a las stats existentes (que ya calculan conversión):
- **Ciclo promedio**: días entre `fecha` y decisión (convertido/rechazado/vencido), últimos 90 días.
- **Ganado vs. perdido por mes**: suma de `total` de convertidos vs. rechazados+vencidos, últimos 6 meses (tabla chica o barras CSS).
- **Aging del pipeline abierto**: para cada `enviado`, días desde el envío, resaltando 7+ (ya existe el badge por fila; esto agrega el resumen agregado).
- Cálculos en funciones puras con tests (`computePipelineMetrics(presupuestos, hoy)`).

## Orden de implementación

3D (cobros select) → 3C (alertas) → 3A (UI mailings) → 3B (generador frontend + worker billing) → 3E (pipeline). Commit/deploy por bloque. El worker de billing se deploya por push al repo de billing (Railway auto-deploy); queda detrás de `MAILER_ENABLED` hasta que las credenciales estén cargadas.

## Fuera de alcance

WhatsApp/n8n, editor visual de templates, tracking de apertura, reintentos automáticos del worker, `integracion_microsoft` (OAuth delegado).
