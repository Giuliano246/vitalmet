// facturacion — factura electrónica AFIP/ARCA (reemplaza al
// microservicio vitalmet-billing de Railway, dado de baja 2026-08-04).
//
// Rutas (base /facturacion, deploy con --no-verify-jwt):
//   GET  /health              — liveness, sin auth
//   GET  /ultimo-comprobante  — ?punto_venta=&tipo_comprobante=
//   POST /facturar            — solicita CAE, mismo contrato que el
//                               microservicio viejo + afip_environment
//                               y condicion_iva_receptor_id (RG 5616)
//
// Auth (cualquiera de las dos):
//   a) Authorization: Bearer <access_token de Supabase> — el camino
//      normal del ERP: cualquier usuario logueado de la empresa con
//      permiso al módulo 'ventas' (o es_admin) puede facturar; los
//      usuarios es_planta / es_contador quedan afuera.
//   b) header X-API-Key == BILLING_API_KEY — fallback para testing
//      y scripts (el shared secret que usaba Railway).
//
// WSAA: el TRA se firma CMS/PKCS#7 con node-forge y se postea a
// LoginCms. El TA resultante se persiste en public.afip_ta (migración
// 063) porque ARCA rechaza pedir un TA nuevo mientras el anterior siga
// vigente (~12h) y las Edge Functions no comparten memoria.
//
// Secrets (supabase secrets set): AFIP_CUIT, AFIP_ENVIRONMENT
// (homologacion|produccion), AFIP_CERT_B64, AFIP_KEY_B64,
// BILLING_API_KEY. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los
// inyecta la plataforma.
import { createClient } from "npm:@supabase/supabase-js@2";
import forge from "npm:node-forge@1.3.1";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const AFIP_CUIT = Deno.env.get("AFIP_CUIT") ?? "";
const AFIP_ENV = (Deno.env.get("AFIP_ENVIRONMENT") ?? "homologacion") as
  | "homologacion"
  | "produccion";
const BILLING_API_KEY = Deno.env.get("BILLING_API_KEY") ?? "";

const WSAA_URLS = {
  homologacion: "https://wsaahomo.afip.gov.ar/ws/services/LoginCms",
  produccion: "https://wsaa.afip.gov.ar/ws/services/LoginCms",
};
const WSFE_URLS = {
  homologacion: "https://wswhomo.afip.gov.ar/wsfev1/service.asmx",
  produccion: "https://servicios1.afip.gov.ar/wsfev1/service.asmx",
};

// IDs de alícuotas IVA según AFIP (RG 4290)
const IVA_ID_BY_PCT: Record<string, number> = {
  "0": 3, "10.5": 4, "21": 5, "27": 6, "5": 8, "2.5": 9,
};

// Condición IVA del receptor (RG 5616, obligatorio desde 2026-09-01).
// Si el ERP no la manda, se infiere de la letra: A solo se emite a RI;
// B sin dato asume Consumidor Final.
const COND_IVA_DEFAULT_BY_TIPO: Record<number, number> = {
  1: 1, 2: 1, 3: 1,      // A → Responsable Inscripto
  6: 5, 7: 5, 8: 5,      // B → Consumidor Final
  11: 5, 12: 5, 13: 5,   // C → Consumidor Final
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, x-api-key, authorization, apikey",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

class AfipError extends Error {
  constructor(public detail: unknown, public status = 422) {
    super(typeof detail === "string" ? detail : JSON.stringify(detail));
  }
}

// ── Helpers XML ─────────────────────────────────────────────────────
const xmlEsc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function tag(xml: string, name: string): string | null {
  const m = xml.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? m[1] : null;
}

function tags(xml: string, name: string): string[] {
  return [...xml.matchAll(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`, "g"))]
    .map((m) => m[1]);
}

// Errores/Observaciones de WSFE: pares <Code>/<Msg> dentro de <Err>/<Obs>
function codeMsgs(xml: string, wrapper: string): { code: number; msg: string }[] {
  return tags(xml, wrapper).map((e) => ({
    code: Number(tag(e, "Code") ?? 0),
    msg: (tag(e, "Msg") ?? "").trim(),
  }));
}

// El código 39 es un aviso masivo de ARCA (RG 5616), no un error real.
const soloAvisos = (errs: { code: number }[]) =>
  errs.every((e) => e.code === 39);

// ── WSAA: firma CMS del TRA + LoginCms + cache en afip_ta ───────────
function firmarTRA(traXml: string, certPem: string, keyPem: string): string {
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(traXml, "utf8");
  const cert = forge.pki.certificateFromPem(certPem);
  p7.addCertificate(cert);
  p7.addSigner({
    key: forge.pki.privateKeyFromPem(keyPem),
    certificate: cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign();
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  return forge.util.encode64(der);
}

async function loginWSAA(): Promise<{ token: string; sign: string; expiresAt: string }> {
  const certPem = atob(Deno.env.get("AFIP_CERT_B64") ?? "");
  const keyPem = atob(Deno.env.get("AFIP_KEY_B64") ?? "");
  if (!certPem || !keyPem) {
    throw new AfipError("AFIP_CERT_B64 / AFIP_KEY_B64 no configurados", 503);
  }
  const now = Date.now();
  const iso = (t: number) => new Date(t).toISOString().replace(/\.\d{3}Z$/, "Z");
  const tra = `<?xml version="1.0" encoding="UTF-8"?>
<loginTicketRequest version="1.0">
  <header>
    <uniqueId>${Math.floor(now / 1000)}</uniqueId>
    <generationTime>${iso(now - 5 * 60_000)}</generationTime>
    <expirationTime>${iso(now + 10 * 60_000)}</expirationTime>
  </header>
  <service>wsfe</service>
</loginTicketRequest>`;

  const cms = firmarTRA(tra, certPem, keyPem);
  const soap = `<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:wsaa="http://wsaa.view.sua.dvadac.desein.afip.gov">
  <soapenv:Body><wsaa:loginCms><wsaa:in0>${cms}</wsaa:in0></wsaa:loginCms></soapenv:Body>
</soapenv:Envelope>`;

  const res = await fetch(WSAA_URLS[AFIP_ENV], {
    method: "POST",
    headers: { "Content-Type": "text/xml; charset=utf-8", SOAPAction: '""' },
    body: soap,
  });
  const raw = await res.text();
  const fault = tag(raw, "faultstring");
  if (fault) {
    // "El CEE ya posee un TA valido": hay un TA emitido que no tenemos
    // en la tabla (p.ej. lo pidió otro proceso). No hay forma de
    // recuperarlo — esperar a que venza.
    throw new AfipError(`WSAA: ${fault}`, 502);
  }
  // El loginTicketResponse viene XML-escapado dentro de loginCmsReturn
  const inner = (tag(raw, "loginCmsReturn") ?? "")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  const token = tag(inner, "token");
  const sign = tag(inner, "sign");
  const exp = tag(inner, "expirationTime");
  if (!token || !sign || !exp) {
    throw new AfipError(`WSAA: respuesta inesperada: ${raw.slice(0, 300)}`, 502);
  }
  return { token, sign, expiresAt: new Date(exp).toISOString() };
}

async function getTA(): Promise<{ token: string; sign: string }> {
  const { data } = await supabase
    .from("afip_ta")
    .select("token, sign, expires_at")
    .eq("service", "wsfe")
    .eq("environment", AFIP_ENV)
    .maybeSingle();

  // Margen de 10' para no usar un TA a punto de vencer
  if (data && new Date(data.expires_at).getTime() > Date.now() + 10 * 60_000) {
    return { token: data.token, sign: data.sign };
  }

  const ta = await loginWSAA();
  const { error } = await supabase.from("afip_ta").upsert({
    service: "wsfe",
    environment: AFIP_ENV,
    token: ta.token,
    sign: ta.sign,
    expires_at: ta.expiresAt,
    updated_at: new Date().toISOString(),
  });
  if (error) console.error("afip_ta upsert:", error.message);
  return { token: ta.token, sign: ta.sign };
}

// ── WSFEv1 ──────────────────────────────────────────────────────────
async function wsfeCall(action: string, innerXml: string): Promise<string> {
  const { token, sign } = await getTA();
  const soap = `<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ar="http://ar.gov.afip.dif.FEV1/">
  <soap:Body>
    <ar:${action}>
      <ar:Auth><ar:Token>${token}</ar:Token><ar:Sign>${sign}</ar:Sign><ar:Cuit>${AFIP_CUIT}</ar:Cuit></ar:Auth>
      ${innerXml}
    </ar:${action}>
  </soap:Body>
</soap:Envelope>`;
  const res = await fetch(WSFE_URLS[AFIP_ENV], {
    method: "POST",
    headers: {
      "Content-Type": "text/xml; charset=utf-8",
      SOAPAction: `"http://ar.gov.afip.dif.FEV1/${action}"`,
    },
    body: soap,
  });
  if (!res.ok) {
    throw new AfipError(`WSFE ${action}: HTTP ${res.status}`, 502);
  }
  return await res.text();
}

async function ultimoComprobante(pv: number, tipo: number): Promise<number> {
  const xml = await wsfeCall(
    "FECompUltimoAutorizado",
    `<ar:PtoVta>${pv}</ar:PtoVta><ar:CbteTipo>${tipo}</ar:CbteTipo>`,
  );
  const errs = codeMsgs(xml, "Err");
  if (errs.length && !soloAvisos(errs)) {
    throw new AfipError({ mensaje: "AFIP rechazó la consulta", errores: errs });
  }
  return Number(tag(xml, "CbteNro") ?? 0);
}

// ── Totales e IVA (port de calcular_totales de main.py) ─────────────
interface Item { descripcion: string; cantidad: number; precio_unit: number; iva_pct: number }

function calcularTotales(items: Item[]) {
  const r2 = (n: number) => Math.round(n * 100) / 100;
  const grupos = new Map<number, { base: number; importe: number }>();
  for (const it of items) {
    const pct = it.iva_pct ?? 21;
    const base = r2(it.precio_unit * it.cantidad);
    const importe = r2(base * pct / 100);
    const g = grupos.get(pct) ?? { base: 0, importe: 0 };
    g.base += base;
    g.importe += importe;
    grupos.set(pct, g);
  }
  let impNeto = 0, impIva = 0;
  const ivas: { id: number; baseImp: number; importe: number }[] = [];
  for (const [pct, g] of grupos) {
    const id = IVA_ID_BY_PCT[String(pct)];
    if (id === undefined) {
      throw new AfipError(
        `Alícuota IVA ${pct}% no soportada por AFIP. Permitidas: 0, 2.5, 5, 10.5, 21, 27`,
        400,
      );
    }
    impNeto += g.base;
    impIva += g.importe;
    ivas.push({ id, baseImp: r2(g.base), importe: r2(g.importe) });
  }
  impNeto = r2(impNeto);
  impIva = r2(impIva);
  return { impNeto, impIva, impTotal: r2(impNeto + impIva), ivas };
}

// ── QR oficial AFIP (RG 4892/2020) ──────────────────────────────────
function qrUrl(p: {
  cuit: string; pv: number; tipo: number; nro: number; fecha: string;
  total: number; cae: string; docTipo: number; docNro: string;
}): string {
  const payload = {
    ver: 1, fecha: p.fecha, cuit: Number(p.cuit), ptoVta: p.pv,
    tipoCmp: p.tipo, nroCmp: p.nro, importe: p.total, moneda: "PES",
    ctz: 1, tipoDocRec: p.docTipo,
    nroDocRec: /^\d+$/.test(p.docNro) ? Number(p.docNro) : 0,
    tipoCodAut: "E", codAut: Number(p.cae),
  };
  const b64 = btoa(JSON.stringify(payload))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `https://www.afip.gob.ar/fe/qr/?p=${b64}`;
}

// ── Solicitud de CAE ────────────────────────────────────────────────
interface FacturaReq {
  punto_venta: number;
  tipo_comprobante: number;
  concepto?: number;
  doc_tipo?: number;
  doc_nro: string;
  fecha: string; // yyyy-mm-dd
  moneda?: string;
  cotizacion_moneda?: number;
  condicion_iva_receptor_id?: number;
  items: Item[];
}

async function solicitarCAE(req: FacturaReq) {
  if (!req.punto_venta || !req.tipo_comprobante || !req.fecha || !req.items?.length) {
    throw new AfipError("Faltan campos: punto_venta, tipo_comprobante, fecha, items", 400);
  }
  const concepto = req.concepto ?? 1;
  const docTipo = req.doc_tipo ?? 80;
  const totales = calcularTotales(req.items);
  const nro = (await ultimoComprobante(req.punto_venta, req.tipo_comprobante)) + 1;
  const fechaAfip = req.fecha.replace(/-/g, "");
  const condIva = req.condicion_iva_receptor_id ??
    COND_IVA_DEFAULT_BY_TIPO[req.tipo_comprobante] ?? 5;

  // Factura C (11/12/13): el IVA va implícito, sin array <Iva>
  const esC = [11, 12, 13].includes(req.tipo_comprobante);
  const impNeto = esC ? totales.impTotal : totales.impNeto;
  const impIva = esC ? 0 : totales.impIva;
  const ivaXml = esC ? "" : `<ar:Iva>${
    totales.ivas.map((i) =>
      `<ar:AlicIva><ar:Id>${i.id}</ar:Id><ar:BaseImp>${i.baseImp.toFixed(2)}</ar:BaseImp><ar:Importe>${i.importe.toFixed(2)}</ar:Importe></ar:AlicIva>`
    ).join("")
  }</ar:Iva>`;

  // El orden de los elementos respeta la secuencia del WSDL de FECAEDetRequest
  const xml = await wsfeCall(
    "FECAESolicitar",
    `<ar:FeCAEReq>
      <ar:FeCabReq><ar:CantReg>1</ar:CantReg><ar:PtoVta>${req.punto_venta}</ar:PtoVta><ar:CbteTipo>${req.tipo_comprobante}</ar:CbteTipo></ar:FeCabReq>
      <ar:FeDetReq><ar:FECAEDetRequest>
        <ar:Concepto>${concepto}</ar:Concepto>
        <ar:DocTipo>${docTipo}</ar:DocTipo>
        <ar:DocNro>${xmlEsc(req.doc_nro || "0")}</ar:DocNro>
        <ar:CbteDesde>${nro}</ar:CbteDesde>
        <ar:CbteHasta>${nro}</ar:CbteHasta>
        <ar:CbteFch>${fechaAfip}</ar:CbteFch>
        <ar:ImpTotal>${totales.impTotal.toFixed(2)}</ar:ImpTotal>
        <ar:ImpTotConc>0</ar:ImpTotConc>
        <ar:ImpNeto>${impNeto.toFixed(2)}</ar:ImpNeto>
        <ar:ImpOpEx>0</ar:ImpOpEx>
        <ar:ImpTrib>0</ar:ImpTrib>
        <ar:ImpIVA>${impIva.toFixed(2)}</ar:ImpIVA>
        <ar:MonId>${xmlEsc(req.moneda ?? "PES")}</ar:MonId>
        <ar:MonCotiz>${req.cotizacion_moneda ?? 1}</ar:MonCotiz>
        <ar:CondicionIVAReceptorId>${condIva}</ar:CondicionIVAReceptorId>
        ${ivaXml}
      </ar:FECAEDetRequest></ar:FeDetReq>
    </ar:FeCAEReq>`,
  );

  const cae = (tag(xml, "CAE") ?? "").trim();
  const resultado = tag(xml, "Resultado") ?? "";
  const obs = codeMsgs(xml, "Obs").map((o) => `${o.code}: ${o.msg}`);
  if (!cae || resultado === "R") {
    throw new AfipError({
      mensaje: "AFIP rechazó la solicitud de CAE",
      resultado,
      errores: codeMsgs(xml, "Err").filter((e) => e.code !== 39),
      observaciones: obs,
    });
  }
  const vto = tag(xml, "CAEFchVto") ?? ""; // yyyymmdd
  const caeVto = vto.length === 8 ? `${vto.slice(0, 4)}-${vto.slice(4, 6)}-${vto.slice(6, 8)}` : vto;

  return {
    cae,
    cae_vto: caeVto,
    numero: nro,
    punto_venta: req.punto_venta,
    tipo_comprobante: req.tipo_comprobante,
    cuit: AFIP_CUIT,
    fecha: req.fecha,
    imp_neto: totales.impNeto,
    imp_iva: totales.impIva,
    imp_total: totales.impTotal,
    resultado,
    observaciones: obs,
    condicion_iva_receptor_id: condIva,
    afip_environment: AFIP_ENV,
    qr_url: qrUrl({
      cuit: AFIP_CUIT, pv: req.punto_venta, tipo: req.tipo_comprobante,
      nro, fecha: req.fecha, total: totales.impTotal, cae,
      docTipo, docNro: req.doc_nro || "0",
    }),
  };
}

// ── Autorización ────────────────────────────────────────────────────
// Devuelve null si el request está autorizado, o la Response de error.
async function autorizar(req: Request): Promise<Response | null> {
  // b) shared secret (testing / scripts)
  const apiKey = req.headers.get("x-api-key");
  if (apiKey) {
    if (BILLING_API_KEY && apiKey === BILLING_API_KEY) return null;
    return json({ detail: "API key inválida (header X-API-Key)" }, 401);
  }

  // a) sesión de Supabase del usuario del ERP
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!bearer) {
    return json({ detail: "Falta autenticación (Authorization: Bearer o X-API-Key)" }, 401);
  }
  const { data: userData, error } = await supabase.auth.getUser(bearer);
  if (error || !userData?.user) {
    return json({ detail: "Sesión inválida o vencida — volvé a loguearte en el ERP" }, 401);
  }

  const { data: u } = await supabase
    .from("usuarios")
    .select("empresa_id, es_admin, es_planta, es_contador")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!u) return json({ detail: "Usuario sin alta en el ERP" }, 403);
  if (u.es_planta || u.es_contador) {
    return json({ detail: "Este usuario no está habilitado para facturar" }, 403);
  }
  if (!u.es_admin) {
    const { data: perm } = await supabase
      .from("permisos_usuario")
      .select("id")
      .eq("usuario_id", userData.user.id)
      .eq("modulo", "ventas")
      .maybeSingle();
    if (!perm) {
      return json({ detail: "Necesitás permiso al módulo Ventas para facturar" }, 403);
    }
  }
  return null;
}

// ── Router ──────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/facturacion/, "") || "/";

  if (path === "/health") {
    return json({
      status: "ok",
      service: "facturacion",
      afip_environment: AFIP_ENV,
      cuit: AFIP_CUIT,
      afip_ready: !!(Deno.env.get("AFIP_CERT_B64") && Deno.env.get("AFIP_KEY_B64")),
    });
  }

  const authError = await autorizar(req);
  if (authError) return authError;

  try {
    if (path === "/ultimo-comprobante" && req.method === "GET") {
      const pv = Number(url.searchParams.get("punto_venta"));
      const tipo = Number(url.searchParams.get("tipo_comprobante"));
      if (!pv || !tipo) {
        return json({ detail: "Faltan query params punto_venta / tipo_comprobante" }, 400);
      }
      const ultimo = await ultimoComprobante(pv, tipo);
      return json({ punto_venta: pv, tipo_comprobante: tipo, ultimo, siguiente: ultimo + 1 });
    }

    if (path === "/facturar" && req.method === "POST") {
      const body = (await req.json()) as FacturaReq;
      return json(await solicitarCAE(body));
    }

    return json({ detail: `Ruta no encontrada: ${req.method} ${path}` }, 404);
  } catch (err) {
    if (err instanceof AfipError) return json({ detail: err.detail }, err.status);
    console.error("facturacion:", err);
    return json({ detail: `Error interno: ${(err as Error).message}` }, 500);
  }
});
