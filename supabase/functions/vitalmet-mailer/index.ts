// vitalmet-mailer — despacha la cola de emails del ERP (email_queue).
//
// Invocada por pg_cron cada 15' (migración 057) con header
// x-mailer-secret == MAILER_SECRET. Flujo:
//   1. Valida secret y ventana horaria (mailings_config de la empresa).
//   2. Toma email_queue estado='aprobado' con scheduled_at vencido y la
//      agrupa POR EMPRESA (auditoría 2026-09-21, C06): cada mail sale con
//      la integración de SU empresa; sin integración activa, el mail
//      queda en 'aprobado' esperando (no se manda con otra identidad).
//   3. Pide access_token a Azure AD con el refresh_token de
//      integracion_microsoft_secretos (migración 081, C03: tabla sin
//      acceso para usuarios, sólo service_role) y envía por Microsoft
//      Graph sendMail.
//   4. Marca enviado/fallido y copia el resultado a email_log.
//
// Secrets (supabase secrets set): MAILER_SECRET (mismo valor que
// push_config.mailer_secret). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
// los inyecta la plataforma.
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const LOTE_MAX = 20; // mails por corrida (el cron pasa cada 15')

function ahoraART(): { hhmm: string; diaSemana: number } {
  const d = new Date();
  const art = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Argentina/Buenos_Aires",
    hour: "2-digit", minute: "2-digit", hour12: false, weekday: "short",
  }).formatToParts(d);
  const get = (t: string) => art.find((p) => p.type === t)?.value ?? "";
  const dias = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return { hhmm: `${get("hour")}:${get("minute")}`, diaSemana: dias.indexOf(get("weekday")) };
}

interface Integracion {
  id: string; empresa_id: string; tenant_id: string; client_id: string; sender_email: string;
}

async function accessTokenGraph(integ: Integracion): Promise<string | null> {
  const { data: sec } = await supabase.from("integracion_microsoft_secretos")
    .select("client_secret, refresh_token").eq("integracion_id", integ.id).maybeSingle();
  if (!sec?.client_secret || !sec.refresh_token) return null;
  const res = await fetch(`https://login.microsoftonline.com/${integ.tenant_id}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: integ.client_id,
      client_secret: sec.client_secret,
      refresh_token: sec.refresh_token,
      grant_type: "refresh_token",
      scope: "https://graph.microsoft.com/.default offline_access",
    }),
  });
  if (!res.ok) {
    console.error("Azure AD token error:", res.status, await res.text());
    return null;
  }
  const tok = await res.json();
  // Azure rota el refresh_token: persistir el nuevo para la próxima corrida
  if (tok.refresh_token && tok.refresh_token !== sec.refresh_token) {
    await supabase.from("integracion_microsoft_secretos")
      .update({ refresh_token: tok.refresh_token, ultimo_refresh_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("integracion_id", integ.id);
  }
  return tok.access_token ?? null;
}

async function enviarGraph(token: string, sender: string, mail: {
  to_email: string; to_nombre: string | null; subject: string; body_html: string;
}): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(sender)}/sendMail`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        subject: mail.subject,
        body: { contentType: "HTML", content: mail.body_html },
        toRecipients: [{ emailAddress: { address: mail.to_email, name: mail.to_nombre ?? undefined } }],
      },
      saveToSentItems: true,
    }),
  });
  if (res.status === 202) return { ok: true };
  return { ok: false, error: `Graph ${res.status}: ${(await res.text()).slice(0, 300)}` };
}

Deno.serve(async (req) => {
  if (req.headers.get("x-mailer-secret") !== Deno.env.get("MAILER_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { "Content-Type": "application/json" } });
  const { hhmm, diaSemana } = ahoraART();
  const ahora = new Date().toISOString();

  // Cola: aprobados cuyo momento ya llegó (todas las empresas)
  const { data: cola, error: eCola } = await supabase.from("email_queue")
    .select("id, empresa_id, venta_id, cliente_id, template_id, to_email, to_nombre, subject, body_html")
    .eq("estado", "aprobado").lte("scheduled_at", ahora)
    .order("scheduled_at").limit(LOTE_MAX);
  if (eCola) return json({ error: eCola.message });
  if (!cola?.length) return json({ enviados: 0, cola_vacia: true });

  const porEmpresa = new Map<string, typeof cola>();
  for (const m of cola) {
    if (!m.empresa_id) continue;
    if (!porEmpresa.has(m.empresa_id)) porEmpresa.set(m.empresa_id, []);
    porEmpresa.get(m.empresa_id)!.push(m);
  }

  let enviados = 0, fallidos = 0, sinIntegracion = 0, fueraHorario = 0;
  const detalle: Record<string, string> = {};

  for (const [empresaId, mails] of porEmpresa) {
    // Ventana horaria y días hábiles según config de ESTA empresa
    const { data: cfg } = await supabase.from("mailings_config")
      .select("*").eq("empresa_id", empresaId).maybeSingle();
    const desde = (cfg?.horario_envio_desde ?? "09:00").slice(0, 5);
    const hasta = (cfg?.horario_envio_hasta ?? "18:00").slice(0, 5);
    if (hhmm < desde || hhmm > hasta) { fueraHorario += mails.length; detalle[empresaId] = "fuera_de_horario"; continue; }
    if ((cfg?.dias_habiles_solamente ?? true) && (diaSemana === 0 || diaSemana === 6)) {
      fueraHorario += mails.length; detalle[empresaId] = "fin_de_semana"; continue;
    }

    // Integración de ESTA empresa (sin fallback a otra)
    const { data: integ } = await supabase.from("integracion_microsoft")
      .select("id, empresa_id, tenant_id, client_id, sender_email")
      .eq("empresa_id", empresaId).eq("activo", true).maybeSingle();
    if (!integ) { sinIntegracion += mails.length; detalle[empresaId] = "sin_integracion_microsoft"; continue; }
    const token = await accessTokenGraph(integ as Integracion);
    if (!token) { sinIntegracion += mails.length; detalle[empresaId] = "azure_token_failed"; continue; }

    for (const m of mails) {
      const r = await enviarGraph(token, integ.sender_email, m);
      if (r.ok) {
        enviados++;
        await supabase.from("email_queue")
          .update({ estado: "enviado", enviado_at: new Date().toISOString(), error_texto: null })
          .eq("id", m.id);
      } else {
        fallidos++;
        await supabase.from("email_queue")
          .update({ estado: "fallido", error_texto: r.error })
          .eq("id", m.id);
      }
      await supabase.from("email_log").insert({
        empresa_id: m.empresa_id, queue_id: m.id, venta_id: m.venta_id,
        cliente_id: m.cliente_id, template_id: m.template_id,
        to_email: m.to_email, subject: m.subject,
        status: r.ok ? "enviado" : "fallido", error_texto: r.error ?? null,
      });
    }
  }
  return json({ enviados, fallidos, sin_integracion: sinIntegracion, fuera_de_horario: fueraHorario, hora_art: hhmm, detalle });
});
