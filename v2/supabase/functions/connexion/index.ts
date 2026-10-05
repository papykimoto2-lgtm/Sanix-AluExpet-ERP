// Sanix AluExpert ERP — Connexion par identifiant OU e-mail (à la manière de Menko Immo).
// Vérifie le mot de passe via Supabase Auth, bloque après 5 échecs consécutifs sur 24 h,
// refuse les comptes désactivés, journalise chaque tentative (IP, navigateur) dans logs_connexion
// et renvoie la session Supabase à l'application. Appelable sans être connecté (verify_jwt = false).
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const MAX_ECHECS = 5;
const MSG_GENERIQUE = "Identifiant ou mot de passe incorrect.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, message: "Méthode non autorisée" }, 405);

  let body: { identifiant?: string; mot_de_passe?: string };
  try { body = await req.json(); } catch { return json({ ok: false, message: "Requête invalide" }, 400); }
  const saisi = String(body.identifiant || "").trim().toLowerCase().slice(0, 120);
  const motDePasse = String(body.mot_de_passe || "");
  if (!saisi || !motDePasse) return json({ ok: false, message: "Identifiant et mot de passe requis." }, 400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || null;
  const ua = (req.headers.get("user-agent") || "").slice(0, 200) || null;
  // Identifiant → compte ; e-mail accepté aussi
  const colonne = saisi.includes("@") ? "email" : "login";
  const { data: profil } = await admin.from("profiles").select("id, login, actif, must_change")
    .ilike(colonne, saisi.replace(/[%_\\]/g, "\\$&")).maybeSingle();
  // Clé de blocage et de journal : l'identifiant du compte s'il existe (identifiant et e-mail comptent ensemble)
  const cle = (profil?.login || saisi).toLowerCase();
  const journal = (succes: boolean, detail: string, userId: string | null = null) =>
    admin.from("logs_connexion").insert({ login_saisi: cle, user_id: userId, succes, detail, ip, user_agent: ua });

  // Blocage : 5 échecs consécutifs (depuis la dernière réussite) sur les dernières 24 h
  const depuis = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { data: recents } = await admin.from("logs_connexion").select("succes")
    .eq("login_saisi", cle).gte("created_at", depuis).order("created_at", { ascending: false }).limit(MAX_ECHECS + 1);
  let echecs = 0;
  for (const l of recents || []) { if (l.succes) break; echecs++; }
  if (echecs >= MAX_ECHECS) {
    await journal(false, "Refusé : compte bloqué (trop de tentatives)", profil?.id || null);
    return json({ ok: false, bloque: true, message: "🔒 Compte bloqué après trop de tentatives. Réessayez dans 24 h ou demandez à un administrateur de réinitialiser votre mot de passe." }, 429);
  }

  let email: string | null = saisi.includes("@") ? saisi : null;
  if (profil) {
    const { data: u } = await admin.auth.admin.getUserById(profil.id);
    email = u?.user?.email || email;
  }
  const restantes = () => Math.max(0, MAX_ECHECS - echecs - 1);
  if (!email) {
    await journal(false, "Identifiant inconnu");
    return json({ ok: false, message: MSG_GENERIQUE, tentatives_restantes: restantes() }, 401);
  }

  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await anon.auth.signInWithPassword({ email, password: motDePasse });
  if (error || !data.session) {
    const banni = /banned/i.test(error?.message || "");
    await journal(false, banni ? "Refusé : compte désactivé" : "Mot de passe incorrect", profil?.id || null);
    if (banni) return json({ ok: false, message: "⛔ Ce compte est désactivé. Contactez un administrateur." }, 403);
    return json({ ok: false, message: MSG_GENERIQUE, tentatives_restantes: restantes() }, 401);
  }
  const userId = data.user.id;
  const { data: p } = await admin.from("profiles").select("actif, must_change").eq("id", userId).maybeSingle();
  if (p && p.actif === false) {
    await admin.auth.admin.signOut(data.session.access_token).catch(() => {});
    await journal(false, "Refusé : compte désactivé", userId);
    return json({ ok: false, message: "⛔ Ce compte est désactivé. Contactez un administrateur." }, 403);
  }
  await admin.from("profiles").update({ derniere_connexion: new Date().toISOString() }).eq("id", userId);
  await journal(true, p?.must_change ? "Connexion — changement de mot de passe requis" : "Connexion réussie", userId);
  return json({
    ok: true,
    must_change: !!p?.must_change,
    session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token },
  });
});
