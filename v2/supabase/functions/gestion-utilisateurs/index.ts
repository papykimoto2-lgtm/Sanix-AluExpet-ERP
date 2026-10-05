// Sanix AluExpert ERP — Gestion des comptes par un administrateur (à la manière de Menko Immo).
// Actions : creer, modifier, reinitialiser_mdp, definir_actif. Réservé aux rôles ayant le droit
// « Utilisateurs » (créer / modifier) — l'administrateur par défaut. Utilise la clé serveur
// (service role) : ces opérations sont impossibles depuis le navigateur.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const LOGIN_RE = /^[a-z0-9][a-z0-9._-]{2,29}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const DOMAINE_INTERNE = "comptes.aluexpert.local";   // e-mail technique des comptes sans e-mail
function politiqueMdp(p: string): string | null {
  if (p.length < 8) return "Le mot de passe doit contenir au moins 8 caractères.";
  if (!/[A-Z]/.test(p)) return "Le mot de passe doit contenir au moins une majuscule.";
  if (!/[0-9]/.test(p)) return "Le mot de passe doit contenir au moins un chiffre.";
  if (!/[^A-Za-z0-9]/.test(p)) return "Le mot de passe doit contenir au moins un caractère spécial.";
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, message: "Méthode non autorisée" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false },
  });
  const { data: { user: appelant } } = await userClient.auth.getUser();
  if (!appelant) return json({ ok: false, message: "Non authentifié" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ ok: false, message: "Requête invalide" }, 400); }
  const action = String(b.action || "");

  // Droits de l'appelant (module « Utilisateurs »)
  const { data: moi } = await admin.from("profiles").select("role_id, actif, must_change, roles(code)").eq("id", appelant.id).maybeSingle();
  const codeRole = (moi as any)?.roles?.code;
  const { data: perm } = await admin.from("role_permissions").select("peut_creer, peut_modifier")
    .eq("role_id", moi?.role_id || "00000000-0000-0000-0000-000000000000").eq("module_code", "Utilisateurs").maybeSingle();
  const estAdmin = codeRole === "admin";
  const droit = action === "creer" ? (estAdmin || perm?.peut_creer) : (estAdmin || perm?.peut_modifier);
  if (!moi?.actif || moi?.must_change || !droit) return json({ ok: false, message: "🔒 Action réservée aux administrateurs des utilisateurs." }, 403);

  const roleValide = async (roleId: string) => {
    const { data: r } = await admin.from("roles").select("id, code").eq("id", roleId).maybeSingle();
    if (!r) return "Rôle inconnu.";
    if (r.code === "admin" && !estAdmin) return "Seul un administrateur peut attribuer le rôle Administrateur.";
    return null;
  };
  const loginLibre = async (login: string, saufId?: string) => {
    let q = admin.from("profiles").select("id").ilike("login", login);
    if (saufId) q = q.neq("id", saufId);
    const { data } = await q; return !(data || []).length;
  };

  try {
    if (action === "creer") {
      const login = String(b.login || "").trim().toLowerCase();
      const nom = String(b.nom_complet || "").trim();
      const email = String(b.email || "").trim().toLowerCase();
      const mdp = String(b.mot_de_passe || "");
      if (!LOGIN_RE.test(login)) return json({ ok: false, message: "Identifiant invalide : 3 à 30 caractères, lettres minuscules, chiffres, point, tiret." }, 400);
      if (!nom) return json({ ok: false, message: "Le nom est obligatoire." }, 400);
      if (email && !EMAIL_RE.test(email)) return json({ ok: false, message: "E-mail invalide." }, 400);
      const e1 = politiqueMdp(mdp); if (e1) return json({ ok: false, message: e1 }, 400);
      const e2 = await roleValide(String(b.role_id || "")); if (e2) return json({ ok: false, message: e2 }, 400);
      if (!(await loginLibre(login))) return json({ ok: false, message: "Cet identifiant est déjà utilisé." }, 409);
      const { data: cree, error } = await admin.auth.admin.createUser({
        email: email || `${login}@${DOMAINE_INTERNE}`, password: mdp, email_confirm: true, user_metadata: { nom_complet: nom },
      });
      if (error) return json({ ok: false, message: /already|registered|exists/i.test(error.message) ? "Cet e-mail est déjà utilisé par un autre compte." : error.message }, 400);
      const { error: eP } = await admin.from("profiles").update({
        login, nom_complet: nom, email: email || null, telephone: String(b.telephone || "").trim() || null,
        role_id: b.role_id, must_change: true, actif: true, cree_par: appelant.id,
      }).eq("id", cree.user.id);
      if (eP) { await admin.auth.admin.deleteUser(cree.user.id); return json({ ok: false, message: eP.message }, 400); }
      return json({ ok: true, id: cree.user.id });
    }

    const cible = String(b.user_id || "");
    const { data: prof } = await admin.from("profiles").select("id, login").eq("id", cible).maybeSingle();
    if (!prof) return json({ ok: false, message: "Utilisateur introuvable." }, 404);

    if (action === "modifier") {
      const maj: Record<string, unknown> = {};
      if (b.nom_complet !== undefined) { const n = String(b.nom_complet).trim(); if (!n) return json({ ok: false, message: "Le nom est obligatoire." }, 400); maj.nom_complet = n; }
      if (b.telephone !== undefined) maj.telephone = String(b.telephone || "").trim() || null;
      if (b.login !== undefined) {
        const l = String(b.login).trim().toLowerCase();
        if (!LOGIN_RE.test(l)) return json({ ok: false, message: "Identifiant invalide." }, 400);
        if (!(await loginLibre(l, cible))) return json({ ok: false, message: "Cet identifiant est déjà utilisé." }, 409);
        maj.login = l;
      }
      if (b.role_id !== undefined) { const e = await roleValide(String(b.role_id)); if (e) return json({ ok: false, message: e }, 400); maj.role_id = b.role_id; }
      if (b.email !== undefined) {
        const e = String(b.email || "").trim().toLowerCase();
        if (e && !EMAIL_RE.test(e)) return json({ ok: false, message: "E-mail invalide." }, 400);
        const loginFinal = String(maj.login || prof.login || cible);
        const { error } = await admin.auth.admin.updateUserById(cible, { email: e || `${loginFinal}@${DOMAINE_INTERNE}`, email_confirm: true });
        if (error) return json({ ok: false, message: /already|registered|exists/i.test(error.message) ? "Cet e-mail est déjà utilisé par un autre compte." : error.message }, 400);
        maj.email = e || null;
      }
      const { error } = await admin.from("profiles").update(maj).eq("id", cible);
      if (error) return json({ ok: false, message: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "reinitialiser_mdp") {
      const mdp = String(b.mot_de_passe || "");
      const e1 = politiqueMdp(mdp); if (e1) return json({ ok: false, message: e1 }, 400);
      const { error } = await admin.auth.admin.updateUserById(cible, { password: mdp });
      if (error) return json({ ok: false, message: error.message }, 400);
      await admin.from("profiles").update({ must_change: true }).eq("id", cible);
      // Débloque la connexion : une réussite fictive remet le compteur d'échecs à zéro
      await admin.from("logs_connexion").insert({ login_saisi: String(prof.login || "").toLowerCase(), user_id: cible, succes: true, detail: "Mot de passe réinitialisé par un administrateur" });
      return json({ ok: true });
    }

    if (action === "definir_actif") {
      if (cible === appelant.id) return json({ ok: false, message: "Vous ne pouvez pas désactiver votre propre compte." }, 400);
      const actif = !!b.actif;
      const { error: eP } = await admin.from("profiles").update({ actif }).eq("id", cible);   // refusé si dernier administrateur
      if (eP) return json({ ok: false, message: eP.message }, 400);
      const { error } = await admin.auth.admin.updateUserById(cible, { ban_duration: actif ? "none" : "876000h" });
      if (error) { await admin.from("profiles").update({ actif: !actif }).eq("id", cible); return json({ ok: false, message: error.message }, 400); }
      return json({ ok: true });
    }
    return json({ ok: false, message: "Action inconnue." }, 400);
  } catch (e) {
    return json({ ok: false, message: e instanceof Error ? e.message : String(e) }, 500);
  }
});
