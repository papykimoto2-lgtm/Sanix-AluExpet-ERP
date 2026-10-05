-- ============================================================================
-- Sanix AluExpert ERP — Module Utilisateurs, Rôles & Accès (à l'image de ImmoSuite)
-- ============================================================================
-- À exécuter dans l'éditeur SQL Supabase, APRÈS sql/comptabilite_syscohada.sql
-- et sql/parametres_comptes_defaut.sql. Additif : crée 3 nouvelles tables
-- (roles, role_permissions, invitations) et ajoute 2 colonnes à `profiles`
-- (déjà existante). Aucune table existante n'est modifiée en profondeur.
--
-- Modèle : chaque rôle porte, pour chaque module de l'application, 5 droits
-- indépendants (voir/créer/modifier/supprimer/valider). Contrairement à
-- ImmoSuite (où l'absence de restriction sur un module = tout autorisé),
-- ici chaque couple (rôle, module) a une ligne explicite dans
-- role_permissions — pas de valeur implicite, pour éviter les angles morts
-- de sécurité. Règle absolue conservée d'ImmoSuite : seuls les rôles
-- « admin » et « manager » peuvent supprimer, même si un rôle personnalisé
-- coche « supprimer » sur un module (contrôlée côté application).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Rôles
-- ----------------------------------------------------------------------------
create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  label text not null,
  icon text not null default '👤',
  niveau int not null default 1,
  est_systeme boolean not null default false,
  peut_supprimer boolean not null default true,
  plafond_validation numeric(14,2),
  description text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. Permissions par rôle et par module
-- ----------------------------------------------------------------------------
create table if not exists role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  module_code text not null,
  peut_voir boolean not null default false,
  peut_creer boolean not null default false,
  peut_modifier boolean not null default false,
  peut_supprimer boolean not null default false,
  peut_valider boolean not null default false,
  primary key (role_id, module_code)
);

-- ----------------------------------------------------------------------------
-- 3. Invitations (l'application n'a pas d'API admin Supabase côté client : on ne
--    peut pas créer un compte auth pour quelqu'un d'autre. Une invitation
--    pré-attribue un rôle à un email ; quand cette personne s'inscrit via
--    l'écran de connexion existant, le rôle lui est attribué automatiquement)
-- ----------------------------------------------------------------------------
create table if not exists invitations (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  role_id uuid not null references roles(id),
  statut text not null default 'en_attente' check (statut in ('en_attente','acceptee')),
  invited_by uuid,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

-- ----------------------------------------------------------------------------
-- 4. Rattachement d'un rôle et d'un statut actif/inactif à chaque profil
-- ----------------------------------------------------------------------------
alter table profiles add column if not exists role_id uuid references roles(id);
alter table profiles add column if not exists actif boolean not null default true;
-- `profiles` n'avait pas de colonne email (l'email vit dans auth.users, non
-- lisible par le client). On la duplique ici pour l'affichage dans l'écran
-- Utilisateurs et le rapprochement des invitations ; elle se renseigne toute
-- seule à la prochaine connexion de chaque utilisateur (voir index.html).
alter table profiles add column if not exists email text;

-- ----------------------------------------------------------------------------
-- 5. Sécurité — RLS + garde-fou anti élévation de privilège
-- ----------------------------------------------------------------------------
alter table roles enable row level security;
alter table role_permissions enable row level security;
alter table invitations enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable as $$
  select exists(
    select 1 from profiles p join roles r on r.id = p.role_id
    where p.id = auth.uid() and r.code = 'admin'
  );
$$;

drop policy if exists "roles_select" on roles;
create policy "roles_select" on roles for select using (auth.role() = 'authenticated');
drop policy if exists "roles_insert_admin" on roles;
create policy "roles_insert_admin" on roles for insert with check (public.is_admin());
drop policy if exists "roles_update_admin" on roles;
create policy "roles_update_admin" on roles for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "roles_delete_admin" on roles;
create policy "roles_delete_admin" on roles for delete using (public.is_admin());

drop policy if exists "role_permissions_select" on role_permissions;
create policy "role_permissions_select" on role_permissions for select using (auth.role() = 'authenticated');
drop policy if exists "role_permissions_insert_admin" on role_permissions;
create policy "role_permissions_insert_admin" on role_permissions for insert with check (public.is_admin());
drop policy if exists "role_permissions_update_admin" on role_permissions;
create policy "role_permissions_update_admin" on role_permissions for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "role_permissions_delete_admin" on role_permissions;
create policy "role_permissions_delete_admin" on role_permissions for delete using (public.is_admin());

drop policy if exists "invitations_select" on invitations;
create policy "invitations_select" on invitations for select using (public.is_admin() or email = (auth.jwt()->>'email'));
drop policy if exists "invitations_insert_admin" on invitations;
create policy "invitations_insert_admin" on invitations for insert with check (public.is_admin());
drop policy if exists "invitations_update" on invitations;
create policy "invitations_update" on invitations for update
  using (public.is_admin() or email = (auth.jwt()->>'email'))
  with check (public.is_admin() or email = (auth.jwt()->>'email'));
drop policy if exists "invitations_delete_admin" on invitations;
create policy "invitations_delete_admin" on invitations for delete using (public.is_admin());

-- Garde-fou indépendant de la policy RLS existante sur `profiles` (que cette
-- migration ne connaît pas et ne modifie pas) : quel que soit ce que cette
-- policy autorise déjà, ce trigger empêche un utilisateur non-admin de
-- modifier son propre rôle ou son statut actif une fois qu'un rôle lui a
-- déjà été attribué. Exception nécessaire : un profil qui n'a PAS encore de
-- rôle (role_id IS NULL, cas d'une inscription qui vient d'avoir lieu) peut
-- recevoir son rôle initial — c'est ce qui permet à l'inscription et au
-- mécanisme d'invitation de fonctionner sans intervention manuelle.
create or replace function public.proteger_role_profil() returns trigger
language plpgsql as $$
declare
  appelant_admin boolean;
begin
  if new.role_id is distinct from old.role_id or new.actif is distinct from old.actif then
    select public.is_admin() into appelant_admin;
    if not appelant_admin and old.role_id is not null then
      new.role_id := old.role_id;
      new.actif := old.actif;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_proteger_role_profil on profiles;
create trigger trg_proteger_role_profil before update on profiles
for each row execute function public.proteger_role_profil();

-- ----------------------------------------------------------------------------
-- 6. Rôles système + matrice de permissions par défaut
-- ----------------------------------------------------------------------------
do $$
declare
  rid uuid;
  m text;
  tous_modules text[] := array['Clients','Prospects','Fournisseurs','Projets','Devis','Factures',
                                'FichesExecution','Produits','Composants','Stock','Comptabilite',
                                'Caisse','Comptoir','Realisations','Utilisateurs','Parametres'];
begin
  -- ADMINISTRATEUR : accès total, y compris Utilisateurs et Paramètres
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('admin','Administrateur','👑',4,true,true,null,'Accès complet à tous les modules, y compris Utilisateurs et Paramètres.')
    on conflict (code) do nothing;
  select id into rid from roles where code='admin';
  foreach m in array tous_modules loop
    insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
      values (rid,m,true,true,true,true,true) on conflict (role_id,module_code) do nothing;
  end loop;

  -- MANAGER : tout sauf Comptabilité, Utilisateurs, Paramètres
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('manager','Manager','🧭',3,true,true,null,'Gestion opérationnelle complète (commercial, chantiers, stock) — sans accès à la Comptabilité ni aux Paramètres.')
    on conflict (code) do nothing;
  select id into rid from roles where code='manager';
  foreach m in array tous_modules loop
    if m in ('Comptabilite','Utilisateurs','Parametres') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,true,true) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMPTABLE : Comptabilité/Caisse/Factures/Fournisseurs en création-modif (pas suppression),
  -- consultation sur le reste, aucun accès à Utilisateurs/Paramètres/Prospects
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('comptable','Comptable','📗',2,true,false,1000000,'Comptabilité SYSCOHADA, Caisse, Factures et Fournisseurs — sans droit de suppression.')
    on conflict (code) do nothing;
  select id into rid from roles where code='comptable';
  foreach m in array tous_modules loop
    if m in ('Comptabilite','Caisse','Factures','Fournisseurs') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,true) on conflict (role_id,module_code) do nothing;
    elsif m in ('Clients','Devis','Projets','Stock','Produits','Composants','Realisations','FichesExecution','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMMERCIAL : Clients/Prospects/Devis en création-modif, consultation sur le reste du cycle de vente
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('commercial','Commercial','🤝',1,true,false,null,'Clients, prospects et devis — sans droit de suppression, sans accès à la Comptabilité ni à la Caisse.')
    on conflict (code) do nothing;
  select id into rid from roles where code='commercial';
  foreach m in array tous_modules loop
    if m in ('Clients','Prospects','Devis','Realisations','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,true) on conflict (role_id,module_code) do nothing;
    elsif m in ('Projets','FichesExecution','Produits','Composants','Stock','Factures') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- CAISSIÈRE : Caisse en création-modif uniquement (ni suppression, ni validation —
  -- ségrégation des tâches), simple consultation de la Comptabilité
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('caissiere','Caissier(ère)','💰',1,true,false,100000,'Bons d''entrée/sortie de caisse — sans suppression ni validation, pour la ségrégation des tâches.')
    on conflict (code) do nothing;
  select id into rid from roles where code='caissiere';
  foreach m in array tous_modules loop
    if m in ('Caisse','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,false) on conflict (role_id,module_code) do nothing;
    elsif m='Comptabilite' then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMMISSAIRE (auditeur externe) : consultation seule sur tous les modules financiers/métier
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('commissaire','Commissaire aux comptes','🔍',1,true,false,0,'Consultation uniquement — aucune création, modification, suppression ou validation.')
    on conflict (code) do nothing;
  select id into rid from roles where code='commissaire';
  foreach m in array tous_modules loop
    if m in ('Utilisateurs','Parametres') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- SANS RÔLE : aucun accès — attribué par défaut à toute inscription sans invitation
  -- lorsqu'un compte administrateur existe déjà (empêche un inconnu de s'auto-attribuer
  -- un accès en s'inscrivant sur l'écran de connexion public)
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('sans_role','Sans rôle (en attente)','🚫',0,true,false,0,'Compte créé sans invitation : aucun accès tant qu''un administrateur n''attribue un rôle.')
    on conflict (code) do nothing;
  select id into rid from roles where code='sans_role';
  foreach m in array tous_modules loop
    insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
      values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 7. Migration des comptes déjà existants : conserve leur accès complet actuel
--    (aujourd'hui, sans notion de rôle, TOUT utilisateur connecté a un accès
--    complet — on ne restreint donc personne rétroactivement, seuls les
--    NOUVEAUX comptes créés après cette migration seront concernés par le
--    rôle « Sans rôle » par défaut).
-- ----------------------------------------------------------------------------
-- Si un rôle texte existe déjà (profiles.role, cf. sql/affectations_caisse_pdv.sql), on le reprend ;
-- « utilisateur » / « technicien » (sans équivalent) → « sans rôle » ; profil sans rôle du tout → administrateur
-- (comportement historique : avant ce module, tout compte connecté avait un accès complet).
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='role') then
    execute $q$
      update profiles p set role_id = r.id from roles r
      where p.role_id is null and p.role is not null
        and r.code = case p.role when 'caissier' then 'caissiere' when 'utilisateur' then 'sans_role'
                                 when 'technicien' then 'sans_role' else p.role end $q$;
  end if;
end $$;
update profiles set role_id = (select id from roles where code = 'admin') where role_id is null;
