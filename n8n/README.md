# n8n Postventa Vitalmet — Setup

## 1. Levantar n8n con Docker

```bash
docker volume create n8n_data

docker run -d --restart unless-stopped \
  --name n8n \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e GENERIC_TIMEZONE=America/Argentina/Buenos_Aires \
  -e TZ=America/Argentina/Buenos_Aires \
  -e N8N_SECURE_COOKIE=false \
  docker.n8n.io/n8nio/n8n:1.70.0
```

> **Nota Apple Silicon:** la tag `:latest` tiene un bug que crashea silenciosamente
> (exit 139) en Macs con chip M. Usar `:1.70.0` o probar tags recientes estables
> desde https://hub.docker.com/r/n8nio/n8n/tags

Abrí `http://localhost:5678` y creá tu usuario admin (email + password).

## 2. Crear credenciales

En n8n → **Credentials → New**:

### A) Supabase API
- **Type:** Supabase API
- **Name:** `Supabase Vitalmet`
- **Host:** `https://dqvlqhaxgvtilhiuatpv.supabase.co`
- **Service Role Secret:** la anon key (está en `index.html` ~línea 845) o una service_role key del panel Supabase

### B) SMTP (para enviar mails)
- **Type:** SMTP
- **Name:** `Outlook SMTP`
- **User:** `giuliano@vitalmetsa.com`
- **Password:** tu password (si tenés MFA, crear un app password desde Microsoft account)
- **Host:** `smtp.office365.com`
- **Port:** `587`
- **SSL/TLS:** desactivado
- **STARTTLS:** activado

## 3. Importar el workflow

En n8n → **Workflows → Import from File** → seleccioná `postventa-workflow.json`.

Después del import:
1. Abrí cada nodo marcado con un triángulo naranja (credenciales faltantes)
2. Seleccioná las credenciales que creaste en el paso 2
3. Guardá

## 4. Probar con una venta de prueba

El workflow está en **TEST_MODE = true** por default — mails van a `giuliano@vitalmetsa.com` con prefijo `[TEST -> cliente@real.com]`.

### Para generar un caso de prueba:

En Supabase SQL Editor, insertá un template de ejemplo:

```sql
INSERT INTO email_templates (empresa_id, nombre, tipo, subject, body_html, trigger_estado, trigger_delay_days, activo)
SELECT
  id,
  'Test postventa entregado',
  'seguimiento',
  'TEST - Entrega {nro_remito} para {cliente}',
  '<p>Hola {contacto}, este es un mail de prueba para {cliente}. Remito: {nro_remito}. Pedido: {nro_pedido}. Saludos,<br>Giuliano</p>',
  'entregado',
  0,
  true
FROM empresas LIMIT 1;
```

Después andá a una venta en estado `entregado` cuyo cliente tenga email cargado, y verificá:

```sql
SELECT * FROM ventas_pendientes_mail;
```

Tiene que aparecer al menos 1 fila. Ejecutá el workflow **manualmente** desde n8n (botón "Execute workflow") y chequeá tu inbox.

## 5. Pasar a producción

Cuando los mails de prueba se vean bien:
1. Editá el nodo **Config** → `TEST_MODE = false`
2. Cargá los 4 templates definitivos (paso siguiente)
3. Activá el workflow (toggle arriba a la derecha)
4. Ya queda corriendo cada 10 min en segundo plano

## Troubleshooting

- **No se disparan mails:** corré `SELECT * FROM ventas_pendientes_mail;` — si está vacía, no hay ventas que cumplan las condiciones (estado relevante + cliente con email + template con `trigger_estado` matching + delay vencido + sin mail previo).
- **Error SMTP 535:** MFA activado — generá app password en `account.microsoft.com/security`.
- **Error Supabase 401:** la key está mal, verificá que sea la anon o service_role de tu proyecto.
- **Mail duplicado:** chequear que `email_log` tenga la fila correcta con `trigger_estado` seteado.
