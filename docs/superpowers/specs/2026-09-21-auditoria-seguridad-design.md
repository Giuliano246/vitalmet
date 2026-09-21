# Cierre de la auditoría de seguridad 2026-09-21

Origen: `~/Downloads/VitalStock-auditoria-seguridad-2026-09-21.zip` (revisión estática con el skill security-audit de Cloudflare, perfil quick, run incompleto: 7 candidatos sin validación independiente, `findings.json` vacío). Commit auditado `b8e4cb7`.

## Verificación contra el código (2026-09-21)

| # | Candidato | Veredicto | Cierre |
|---|---|---|---|
| C02 | `permisos_usuario` sólo tenía `tenant_isolation FOR ALL`: un usuario común podía darse sueldos/precios/ventas con un POST | **Real, prioridad 1** | mig 081 §2: policies RESTRICTIVE `permisos_solo_admin_ins/upd/del` con `es_admin()` |
| C03 | `integracion_microsoft` legible por toda la empresa, con client secret y refresh token en texto plano | **Real, prioridad 1** (mailer activo desde 2026-08-03 → credenciales reales expuestas) | mig 081 §3: tabla `integracion_microsoft_secretos` sin grants ni policies (sólo service_role), columnas viejas anuladas + trigger; `integracion_microsoft` sólo admin. Mailer lee/escribe la tabla nueva. **Rotar** secret y refresh token |
| C01 | Signup público + INSERT directo en `usuarios` con cualquier `empresa_id`; DELETE de la propia fila permitía reinsertarse | **Real, prioridad 2** (requiere conocer el UUID de la empresa) | mig 081 §4: alta sólo por RPC (`join_empresa` re-emitida, `crear_empresa` nueva) con marca de sesión `vitalstock.rpc`; guard re-emitido; DELETE sólo admin y nunca la propia; `doRegister` usa la RPC |
| C05 | `autorizar()` de facturación no consultaba `es_auditor` | **Real, prioridad 2** | Edge Function facturacion: auditor rechazado como planta/contador |
| C07 | Bitácora fiscal tomaba `empresa_id`/`venta_id` del body | Marginal (integridad de registro) | `autorizar()` devuelve contexto; `vincularEmpresa()` ata el body a la empresa de la sesión y valida que la venta sea de esa empresa (X-API-Key mantiene el body) |
| C04 | Previews de importación XLSX sin `esc()`, `openDocPDF` con `document.write`, preview de email con `innerHTML` | Bajo (self-XSS / contenido propio) | `esc()` en celdas; `openDocPDF` valida el data URL y usa `pdfBlobURL` como `openPDF`; preview de email en `<iframe sandbox="">` con `srcdoc` |
| C06 | Mailer elegía la primera integración activa sin filtrar por empresa | No aplica (single-tenant); sí para Forja | Mailer agrupa la cola por empresa, integración y config de esa empresa, sin fallback |

Controles que ya estaban bien y no se tocaron: `usuarios_guard` (070) para roles, lockdowns planta (052) y contador/auditor (053/059), `tiene_modulo` (071), escape HTML general, headers Netlify.

## Orden de despliegue

1. SQL Editor: `migrations/081_auditoria_seguridad.sql` (idempotente). Verificaciones al pie.
2. `npx supabase functions deploy vitalmet-mailer --no-verify-jwt --project-ref dqvlqhaxgvtilhiuatpv` (hasta acá los mails quedan en `aprobado`, no se pierden).
3. `npx supabase functions deploy facturacion --no-verify-jwt --project-ref dqvlqhaxgvtilhiuatpv` (independiente del SQL; se puede hacer antes).
4. Push a `main` (Netlify): `doRegister` necesita la RPC `crear_empresa` de la 081.
5. Rotar credenciales de Microsoft (`docs/azure-ad-setup.md` § Rotación) y, en Supabase → Authentication → Providers → Email, evaluar apagar "Allow new users to sign up" (single-tenant: sólo se prende para dar de alta a alguien con código de invitación).

## Pruebas

- `node --test tests/*.test.js`: 277 OK (2026-09-21). `deno check` de las dos Edge Functions OK.
- Funcionales pendientes (con un usuario NO admin, ver bloque de verificación de la 081): POST a `permisos_usuario` → 42501; GET a `integracion_microsoft_secretos` → permission denied; POST directo a `usuarios` → excepción del guard; DELETE propio → 0 filas; admin guarda permisos normalmente; alta nueva por "Crear empresa" → usuario admin.
