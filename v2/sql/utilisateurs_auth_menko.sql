-- ============================================================================
-- Sanix AluExpert ERP — Comptes utilisateurs à la manière de Menko Immo
-- ============================================================================
-- À exécuter APRÈS sql/utilisateurs_roles.sql (rôles & droits par module) et
-- sql/affectations_caisse_pdv.sql. Reprend le fonctionnement de Menko Immo :
--   • comptes créés par un administrateur (identifiant + mot de passe provisoire),
--     plus d'inscription libre (sauf le tout premier compte, qui devient administrateur) ;
--   • connexion par identifiant OU e-mail (Edge Function « connexion ») avec blocage
--     après 5 échecs sur 24 h et journal des connexions (IP, navigateur) ;
--   • changement de mot de passe obligatoire à la première connexion / après réinitialisation ;
--   • activation / désactivation des comptes, déconnexion forcée de tous les postes,
--     déconnexion après inactivité (paramétrable).
-- En plus de Menko, appliqué DANS LA BASE : un compte désactivé, « sans rôle » ou devant
-- changer son mot de passe n'a accès à AUCUNE donnée (politiques RLS restrictives).
-- L'authentification reste celle de Supabase (sessions signées, RLS) : pas de table de
-- mots de passe maison.
-- ============================================================================

-- ---------- Profils : colonnes Menko ----------
alter table profiles add column if not exists login text;
alter table profiles add column if not exists telephone text;
alter table profiles add column if not exists must_change boolean not null default false;
alter table profiles add column if not exists derniere_connexion timestamptz;
alter table profiles add column if not exists cree_par uuid;
create unique index if not exists profiles_login_unique on profiles (lower(login)) where login is not null;

-- Identifiant proposé à partir d'un e-mail (début de l'adresse, rendu unique)
create or replace function public.login_depuis_email(p_email text) returns text
language plpgsql stable security definer set search_path = public as $$
declare base text; cand text; n int := 1;
begin
  base := lower(regexp_replace(split_part(coalesce(p_email,''),'@',1), '[^a-zA-Z0-9._-]', '', 'g'));
  base := left(regexp_replace(base, '^[^a-z0-9]+', ''), 26);
  if length(base) < 3 then base := base || 'utilisateur'; end if;
  cand := base;
  while exists (select 1 from profiles where lower(login) = cand) loop n := n + 1; cand := base || n; end loop;
  return cand;
end $$;

-- E-mail et identifiant des comptes existants
update profiles p set email = u.email from auth.users u where u.id = p.id and p.email is null;
do $$
declare r record;
begin
  for r in select id, email from profiles where login is null and email is not null order by created_at loop
    update profiles set login = public.login_depuis_email(r.email) where id = r.id;
  end loop;
end $$;

-- Nouveaux comptes : le profil reçoit aussi l'e-mail et un identifiant (modifiable ensuite)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nom_complet, email, login)
  values (new.id, coalesce(new.raw_user_meta_data->>'nom_complet', new.email),
          case when new.email like '%@comptes.aluexpert.local' then null else new.email end,
          public.login_depuis_email(new.email));
  return new;
end $$;

-- ---------- Rôle texte = reflet du rôle attribué (roles.code) ----------
-- Les rôles sont désormais dynamiques (rôles personnalisés possibles) : plus de liste figée.
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles alter column role drop default;
alter table profiles alter column role drop not null;

create or replace function public.profiles_garde_et_role() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_admin uuid; v_sans uuid; v_nb_admins int; appelant_admin boolean;
begin
  select id into v_admin from roles where code = 'admin';
  select id into v_sans from roles where code = 'sans_role';
  appelant_admin := public.is_admin();

  if tg_op = 'INSERT' then
    -- Rôle initial : le tout premier compte devient administrateur ; ensuite « sans rôle »,
    -- sauf création par un administrateur ou par le serveur (Edge Function, service role).
    if auth.uid() is not null and not appelant_admin then new.role_id := null; end if;
    if new.role_id is null then
      new.role_id := case when exists (select 1 from profiles where role_id = v_admin) then v_sans else v_admin end;
    end if;
  else
    -- Champs réservés à un administrateur (ou au serveur / aux fonctions autorisées)
    if auth.uid() is not null and not appelant_admin
       and coalesce(current_setting('app.maj_compte_autorisee', true), '') <> '1' then
      new.role_id := old.role_id; new.actif := old.actif; new.login := old.login;
      new.must_change := old.must_change; new.cree_par := old.cree_par;
    end if;
    -- Jamais moins d'un administrateur actif
    if old.role_id = v_admin and old.actif and (new.role_id is distinct from v_admin or not new.actif) then
      select count(*) into v_nb_admins from profiles where role_id = v_admin and actif and id <> old.id;
      if v_nb_admins = 0 then raise exception 'Impossible : ce compte est le dernier administrateur actif'; end if;
    end if;
  end if;
  new.role := (select code from roles where id = new.role_id);
  return new;
end $$;
drop trigger if exists trg_proteger_role_profil on profiles;         -- remplacé par la garde ci-dessous
drop trigger if exists trg_profiles_proteger_role on profiles;       -- idem (ancienne garde sur le rôle texte)
drop trigger if exists trg_zz_profiles_garde_et_role on profiles;
create trigger trg_zz_profiles_garde_et_role before insert or update on profiles
  for each row execute function public.profiles_garde_et_role();
-- Un administrateur peut modifier les profils des autres (rôle, statut…) ; chacun garde la main sur le sien
drop policy if exists "profiles_admin_update" on profiles;
create policy "profiles_admin_update" on profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
-- Réaligne le rôle texte des comptes existants
update profiles p set role = r.code from roles r where r.id = p.role_id and p.role is distinct from r.code;

-- ---------- Accès aux données : comptes actifs, avec rôle, mot de passe à jour ----------
create or replace function public.est_utilisateur_autorise() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    where p.id = auth.uid() and p.actif and not p.must_change and r.code <> 'sans_role'
  );
$$;
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
             and c.relname not in ('profiles','roles','role_permissions','invitations','logs_connexion','caisse_pins')
  loop
    execute format('drop policy if exists "acces_comptes_autorises" on public.%I', t);
    execute format('create policy "acces_comptes_autorises" on public.%I as restrictive for all to authenticated using (public.est_utilisateur_autorise()) with check (public.est_utilisateur_autorise())', t);
  end loop;
end $$;

-- ---------- Journal des connexions (écrit par l'Edge Function « connexion ») ----------
create table if not exists logs_connexion (
  id uuid primary key default gen_random_uuid(),
  login_saisi text not null,
  user_id uuid references profiles(id) on delete set null,
  succes boolean not null,
  detail text,
  ip text,
  user_agent text,
  created_at timestamptz not null default now()
);
create index if not exists idx_logs_connexion_login on logs_connexion (login_saisi, created_at desc);
create index if not exists idx_logs_connexion_date on logs_connexion (created_at desc);
alter table logs_connexion enable row level security;
drop policy if exists "logs_connexion_admin" on logs_connexion;
create policy "logs_connexion_admin" on logs_connexion for select to authenticated using (public.is_admin());

-- ---------- Paramètres de session ----------
alter table parametres add column if not exists session_inactivite_min int not null default 30;   -- 0 = désactivé
alter table parametres add column if not exists deconnexion_forcee_le timestamptz;

-- ---------- Fonctions appelées par l'application ----------
-- Installation vierge ? (affiche « Créer le compte administrateur » sur l'écran de connexion)
create or replace function public.installation_vierge() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles p join roles r on r.id = p.role_id where r.code = 'admin');
$$;
-- Après un changement de mot de passe obligatoire (le mot de passe est changé via Supabase Auth)
create or replace function public.mot_de_passe_change() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Non authentifié'; end if;
  perform set_config('app.maj_compte_autorisee', '1', true);
  update profiles set must_change = false where id = auth.uid();
end $$;
-- Déconnecte tous les postes (chaque application vérifie cette date toutes les minutes)
create or replace function public.forcer_deconnexion_generale() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v timestamptz := now();
begin
  if not public.is_admin() then raise exception 'Réservé à un administrateur'; end if;
  update parametres set deconnexion_forcee_le = v where true;
  return v;
end $$;
revoke execute on function public.mot_de_passe_change(), public.forcer_deconnexion_generale() from public, anon;
grant execute on function public.mot_de_passe_change(), public.forcer_deconnexion_generale() to authenticated;
grant execute on function public.installation_vierge() to anon, authenticated;
