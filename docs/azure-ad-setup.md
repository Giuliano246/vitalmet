# Azure AD — Registrar app para envío de emails vía Microsoft Graph

Objetivo: que Vitalstock pueda mandar emails desde `ventas@vitalmetsa.com` usando
la API oficial de Microsoft, sin usar SMTP básico.

Tiempo estimado: **10 minutos**.

Al final tenés que pegarme 3 valores:
- `TENANT_ID`
- `CLIENT_ID`
- `CLIENT_SECRET`

---

## Paso 1 — Entrar al portal

1. Abrí https://entra.microsoft.com con tu cuenta admin de `vitalmetsa.com`.
2. En el menú izquierdo: **Identity** → **Applications** → **App registrations**.
3. Arriba, botón **+ New registration**.

## Paso 2 — Registrar la app

Completá:
- **Name**: `Vitalstock Mailer`
- **Supported account types**: seleccioná **"Accounts in this organizational directory only (Single tenant)"**
- **Redirect URI**:
  - Platform: **Web**
  - URL: `https://vitalmetstock.netlify.app/oauth-callback`
  *(si después cambiás a `stock.vitalmetsa.com` lo agregás como redirect adicional)*

Clickeá **Register**.

Te lleva a la página de la app. **Copiá** estos dos valores de la parte superior:

- `Application (client) ID` → este es tu **CLIENT_ID**
- `Directory (tenant) ID`  → este es tu **TENANT_ID**

## Paso 3 — Permisos de API

En el menú lateral de la app: **API permissions**.

1. Clickeá **+ Add a permission**
2. Elegí **Microsoft Graph**
3. Elegí **Delegated permissions** (NO Application)
4. Buscá y marcá estos permisos:
   - `Mail.Send`
   - `Mail.ReadWrite`   *(lo necesitamos para que el mail enviado aparezca en tu "Enviados" de Outlook)*
   - `offline_access`    *(para el refresh_token que no vence cada hora)*
   - `User.Read`         *(default, ya debería estar)*

5. Clickeá **Add permissions**.
6. De vuelta en la lista, clickeá el botón **"Grant admin consent for Vitalmet SA"** (o el nombre de tu tenant).

   Debe quedar una marca verde ✓ al lado de cada permiso.

## Paso 4 — Crear el client secret

En el menú lateral: **Certificates & secrets** → tab **Client secrets** → **+ New client secret**.

- **Description**: `Vitalstock mailer — prod`
- **Expires**: **24 months**

Clickeá **Add**.

**IMPORTANTE**: la columna **Value** se muestra una sola vez. Copiála ahora — ese es tu **CLIENT_SECRET**.

Si cerrás la página sin copiar, hay que generar uno nuevo.

## Paso 5 — Autorizar el envío desde ventas@vitalmetsa.com

En una sesión privada del navegador, andá a esta URL reemplazando `{TENANT_ID}` y `{CLIENT_ID}` por los valores que copiaste:

```
https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/authorize?client_id={CLIENT_ID}&response_type=code&redirect_uri=https%3A%2F%2Fvitalmetstock.netlify.app%2Foauth-callback&scope=Mail.Send%20Mail.ReadWrite%20offline_access%20User.Read&prompt=consent
```

Te va a pedir login con **ventas@vitalmetsa.com** (la casilla desde la que querés que salgan los mails).

Después del login te va a mostrar la pantalla de consentimiento con los 4 permisos. Clickeás **Accept**.

Te va a redirigir a `https://vitalmetstock.netlify.app/oauth-callback?code=0.AXcA...` — la página va a dar 404 pero **NO importa**, lo que necesitamos es el parámetro `code=` de la URL. Copiá toda la URL entera o al menos el valor después de `code=` hasta el `&` o el final.

---

## Pegame estos 4 valores

1. `TENANT_ID` = ...
2. `CLIENT_ID` = ...
3. `CLIENT_SECRET` = ...
4. `AUTH_CODE` = ... *(el `code=` del paso 5)*

Con esos 4 valores yo hago el último intercambio y obtenemos el `refresh_token` permanente
que queda guardado en la tabla `integracion_microsoft` de Supabase.

---

## Seguridad

- El `CLIENT_SECRET` es como una contraseña. Me lo pasás una vez, yo lo guardo cifrado en Supabase, y después lo podés rotar cuando quieras (de hecho te recomiendo rotarlo cada 6 meses).
- El `refresh_token` tampoco vence mientras lo uses. Si la app queda sin usar 90 días, hay que repetir el paso 5.
- Si algún día despedís o dás de baja `ventas@vitalmetsa.com`, la integración deja de funcionar hasta que hagas el flujo con otra cuenta.
