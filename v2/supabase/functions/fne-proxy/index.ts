// Sanix AluExpert ERP — Relais vers l'API FNE de la DGI (Côte d'Ivoire).
// Le navigateur ne peut pas appeler l'API FNE directement (CORS, URL http) : l'application
// appelle cette fonction, qui lit l'URL et la clé API dans `parametres` et relaie l'appel.
// Actions : "sign" (certification d'une facture de vente), "refund" (facture d'avoir), "ping".
// Seuls ces deux endpoints FNE sont joignables : aucune URL n'est fournie par l'appelant.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, message: "Méthode non autorisée" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ ok: false, message: "Non authentifié" }, 401);

  let body: { action?: string; payload?: unknown; invoice_id?: string };
  try { body = await req.json(); } catch { return json({ ok: false, message: "Corps JSON invalide" }, 400); }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: p, error } = await admin.from("parametres")
    .select("fne_actif,fne_environnement,fne_url_test,fne_url_prod,fne_api_key").limit(1).maybeSingle();
  if (error || !p) return json({ ok: false, message: "Paramètres FNE introuvables" }, 500);
  if (!p.fne_actif) return json({ ok: false, inactif: true, message: "Certification FNE désactivée dans les Paramètres" });
  const base = String((p.fne_environnement === "production" ? p.fne_url_prod : p.fne_url_test) || "")
    .trim().replace(/\/+$/, "").replace(/\/external\/invoices\/sign$/, "");
  if (!base || !p.fne_api_key) return json({ ok: false, inactif: true, message: "URL ou clé API FNE manquante" });

  let endpoint: string;
  if (body.action === "sign") endpoint = `${base}/external/invoices/sign`;
  else if (body.action === "refund") {
    if (!body.invoice_id || !/^[0-9a-zA-Z-]{8,64}$/.test(body.invoice_id)) return json({ ok: false, message: "Identifiant de facture FNE invalide" }, 400);
    endpoint = `${base}/external/invoices/${body.invoice_id}/refund`;
  } else if (body.action === "ping") endpoint = `${base}/external/invoices/sign`;
  else return json({ ok: false, message: "Action inconnue" }, 400);

  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "Authorization": `Bearer ${p.fne_api_key}` },
      body: JSON.stringify(body.action === "ping" ? {} : body.payload ?? {}),
      signal: AbortSignal.timeout(25000),
    });
    const text = await res.text();
    let data: unknown = text;
    try { data = JSON.parse(text); } catch { /* réponse non JSON */ }
    return json({ ok: res.ok, status: res.status, environnement: p.fne_environnement, data });
  } catch (e) {
    return json({ ok: false, message: "API FNE injoignable : " + (e instanceof Error ? e.message : String(e)) }, 502);
  }
});
