-- ============================================================================
-- Sanix AluExpert ERP — Affectation des utilisateurs aux caisses et points de vente + code PIN de caisse
-- ============================================================================
-- Inspiré de la caisse Menko Immo (ImmoSuite) :
--   • chaque caisse / point de vente a sa liste d'utilisateurs affectés ; une caisse ou un point de vente
--     SANS affectation reste accessible à tous (défensif : on ne bloque jamais un module non configuré) ;
--   • les gestionnaires (admin, manager) voient et utilisent tout ;
--   • chaque utilisateur peut avoir un code PIN personnel de 4 chiffres, exigé à l'ouverture de séance ;
--   • la séance mémorise l'identifiant de qui l'ouvre et la clôture.
-- Renforcements par rapport à Menko : le PIN est haché côté serveur (bcrypt), jamais lisible par
-- l'application, avec blocage après 5 essais ; l'ouverture de séance, les mouvements de caisse et les
-- ventes au comptoir sont contrôlés dans la base, pas seulement à l'écran.
-- À exécuter APRÈS sql/vente_comptoir_fne.sql.
-- ============================================================================

-- ---------- Rôles : plus d'administrateur par défaut, rôle modifiable par un administrateur seulement ----------
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check
  check (role in ('admin','manager','comptable','caissier','commercial','technicien','utilisateur'));
alter table profiles alter column role set default 'utilisateur';

create or replace function public.mon_role_code() returns text
language plpgsql stable security definer set search_path = public as $$
declare r text;
begin
  -- Module Utilisateurs & Rôles (sql/utilisateurs_roles.sql) prioritaire s'il est installé
  if to_regclass('public.roles') is not null then
    begin
      execute 'select r.code from profiles p join roles r on r.id = p.role_id where p.id = auth.uid()' into r;
    exception when undefined_column then r := null;
    end;
  end if;
  if r is null then select role into r from profiles where id = auth.uid(); end if;
  return r;
end $$;

create or replace function public.est_gestionnaire_caisse() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.mon_role_code() in ('admin','manager'), false);
$$;

create or replace function public.profiles_proteger_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    -- Le tout premier compte devient administrateur (« Première connexion ») ; les suivants sont
    -- créés « utilisateur » (sauf création par un administrateur), un administrateur leur attribue ensuite un rôle.
    if not exists (select 1 from profiles where role = 'admin') then new.role := 'admin';
    elsif coalesce(public.mon_role_code(),'') <> 'admin' then new.role := 'utilisateur';
    end if;
  elsif new.role is distinct from old.role and auth.uid() is not null
        and coalesce(public.mon_role_code(),'') <> 'admin' then
    raise exception 'Seul un administrateur peut modifier un rôle';
  elsif new.role is distinct from old.role and old.role = 'admin' and new.role <> 'admin'
        and (select count(*) from profiles where role = 'admin') <= 1 then
    raise exception 'Impossible de retirer le dernier administrateur';
  end if;
  return new;
end $$;
drop trigger if exists trg_profiles_proteger_role on profiles;
create trigger trg_profiles_proteger_role before insert or update of role on profiles
  for each row execute function public.profiles_proteger_role();

-- ---------- Affectations ----------
create table if not exists caisse_affectations (
  caisse_id uuid not null references caisses(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (caisse_id, user_id)
);
create table if not exists point_vente_affectations (
  point_vente_id uuid not null references points_vente(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  par_defaut boolean not null default false,          -- point de vente proposé à l'ouverture de la caisse enregistreuse
  created_at timestamptz not null default now(),
  primary key (point_vente_id, user_id)
);
create unique index if not exists pva_un_defaut_par_user on point_vente_affectations(user_id) where par_defaut;

alter table caisse_affectations enable row level security;
alter table point_vente_affectations enable row level security;
drop policy if exists "affect_caisse_lecture" on caisse_affectations;
create policy "affect_caisse_lecture" on caisse_affectations for select using (auth.role() = 'authenticated');
drop policy if exists "affect_caisse_gestion" on caisse_affectations;
create policy "affect_caisse_gestion" on caisse_affectations for all using (public.est_gestionnaire_caisse()) with check (public.est_gestionnaire_caisse());
drop policy if exists "affect_pdv_lecture" on point_vente_affectations;
create policy "affect_pdv_lecture" on point_vente_affectations for select using (auth.role() = 'authenticated');
drop policy if exists "affect_pdv_gestion" on point_vente_affectations;
create policy "affect_pdv_gestion" on point_vente_affectations for all using (public.est_gestionnaire_caisse()) with check (public.est_gestionnaire_caisse());

create or replace function public.peut_utiliser_caisse(p_caisse_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_gestionnaire_caisse()
      or not exists (select 1 from caisse_affectations where caisse_id = p_caisse_id)
      or exists (select 1 from caisse_affectations where caisse_id = p_caisse_id and user_id = auth.uid());
$$;
create or replace function public.peut_utiliser_point_vente(p_pdv_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_gestionnaire_caisse()
      or not exists (select 1 from point_vente_affectations where point_vente_id = p_pdv_id)
      or exists (select 1 from point_vente_affectations where point_vente_id = p_pdv_id and user_id = auth.uid());
$$;

-- ---------- Code PIN de caisse (jamais lisible : table sans politique de lecture) ----------
create table if not exists caisse_pins (
  user_id uuid primary key references profiles(id) on delete cascade,
  pin_hash text not null,
  echecs int not null default 0,
  bloque_jusqu timestamptz,
  defini_par uuid,
  updated_at timestamptz not null default now()
);
alter table caisse_pins enable row level security;   -- aucune politique : accès uniquement via les fonctions ci-dessous

create or replace function public.definir_pin_caisse(p_user_id uuid, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.est_gestionnaire_caisse() then raise exception 'Réservé aux gestionnaires (admin, manager)'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'Le code PIN doit comporter exactement 4 chiffres'; end if;
  insert into caisse_pins(user_id, pin_hash, echecs, bloque_jusqu, defini_par, updated_at)
    values (p_user_id, crypt(p_pin, gen_salt('bf')), 0, null, auth.uid(), now())
    on conflict (user_id) do update set pin_hash = excluded.pin_hash, echecs = 0, bloque_jusqu = null,
      defini_par = excluded.defini_par, updated_at = now();
end $$;

create or replace function public.supprimer_pin_caisse(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_gestionnaire_caisse() then raise exception 'Réservé aux gestionnaires (admin, manager)'; end if;
  delete from caisse_pins where user_id = p_user_id;
end $$;

-- Vérifie le PIN de l'utilisateur connecté. 5 échecs → blocage 10 minutes.
create or replace function public.verifier_pin_caisse(p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare p caisse_pins;
begin
  select * into p from caisse_pins where user_id = auth.uid() for update;
  if p.user_id is null then return true; end if;                       -- pas de PIN configuré : pas de blocage
  if p.bloque_jusqu is not null and p.bloque_jusqu > now() then
    raise exception 'Code PIN bloqué après trop d''essais — réessayez après %', to_char(p.bloque_jusqu at time zone 'Africa/Abidjan','HH24:MI');
  end if;
  if coalesce(p_pin,'') <> '' and crypt(p_pin, p.pin_hash) = p.pin_hash then
    update caisse_pins set echecs = 0, bloque_jusqu = null where user_id = auth.uid();
    return true;
  end if;
  update caisse_pins set echecs = echecs + 1,
    bloque_jusqu = case when echecs + 1 >= 5 then now() + interval '10 minutes' else null end
    where user_id = auth.uid();
  return false;
end $$;

-- Renvoie {ok, message} au lieu de lever une erreur sur un PIN faux, pour que le compteur d'échecs soit conservé.
create or replace function public.modifier_mon_pin_caisse(p_ancien text, p_nouveau text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_nouveau !~ '^[0-9]{4}$' then return jsonb_build_object('ok',false,'message','Le code PIN doit comporter exactement 4 chiffres'); end if;
  if not exists (select 1 from caisse_pins where user_id = auth.uid()) then
    return jsonb_build_object('ok',false,'message','Aucun code PIN ne vous est attribué — demandez-le à un gestionnaire');
  end if;
  if not public.verifier_pin_caisse(p_ancien) then return jsonb_build_object('ok',false,'message','Ancien code PIN incorrect'); end if;
  update caisse_pins set pin_hash = crypt(p_nouveau, gen_salt('bf')), updated_at = now() where user_id = auth.uid();
  return jsonb_build_object('ok',true);
end $$;

-- État des PIN : tous les utilisateurs pour un gestionnaire, soi-même sinon.
create or replace function public.etat_pins_caisse()
returns table(user_id uuid, a_un_pin boolean, bloque_jusqu timestamptz, echecs int, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, cp.user_id is not null, cp.bloque_jusqu, coalesce(cp.echecs,0), cp.updated_at
  from profiles p left join caisse_pins cp on cp.user_id = p.id
  where public.est_gestionnaire_caisse() or p.id = auth.uid();
$$;

-- ---------- Séances de caisse ----------
alter table caisse_sessions add column if not exists ouverte_par_id uuid references profiles(id) on delete set null;
alter table caisse_sessions add column if not exists cloturee_par_id uuid references profiles(id) on delete set null;

-- Ouverture contrôlée : affectation + PIN + une seule séance ouverte par caisse
-- Renvoie {ok, message, session}. Un PIN faux ne lève pas d'erreur (sinon l'échec ne serait pas compté).
create or replace function public.caisse_ouvrir_session(p_caisse_id uuid, p_fond numeric, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare s caisse_sessions; v_nom text; v_restants int;
begin
  if auth.uid() is null then raise exception 'Non authentifié'; end if;
  if not public.peut_utiliser_caisse(p_caisse_id) then raise exception 'Vous n''êtes pas affecté(e) à cette caisse'; end if;
  if not public.verifier_pin_caisse(p_pin) then
    select greatest(0, 5 - echecs) into v_restants from caisse_pins where user_id = auth.uid();
    return jsonb_build_object('ok',false,'message',
      case when v_restants = 0 then 'Code PIN incorrect — bloqué pendant 10 minutes'
           else 'Code PIN incorrect (' || v_restants || ' essai(s) restant(s))' end);
  end if;
  perform 1 from caisses where id = p_caisse_id for update;
  if exists (select 1 from caisse_sessions where caisse_id = p_caisse_id and statut = 'ouverte') then
    return jsonb_build_object('ok',false,'message','Une séance est déjà ouverte pour cette caisse');
  end if;
  select coalesce(nom_complet, id::text) into v_nom from profiles where id = auth.uid();
  insert into caisse_sessions(caisse_id, date_session, fond_ouverture, statut, ouverte_par, ouverte_par_id)
    values (p_caisse_id, (now() at time zone 'Africa/Abidjan')::date, coalesce(p_fond,0), 'ouverte',
            coalesce((select email from auth.users where id = auth.uid()), v_nom), auth.uid())
    returning * into s;
  return jsonb_build_object('ok',true,'session',to_jsonb(s));
end $$;

-- Contrôles en base (politiques RESTRICTIVES : s'ajoutent aux politiques existantes)
drop policy if exists "sessions_ouverture_via_rpc" on caisse_sessions;
create policy "sessions_ouverture_via_rpc" on caisse_sessions as restrictive for insert
  with check (public.est_gestionnaire_caisse());            -- les autres passent par caisse_ouvrir_session (PIN)
drop policy if exists "sessions_modif_affectes" on caisse_sessions;
create policy "sessions_modif_affectes" on caisse_sessions as restrictive for update
  using (public.peut_utiliser_caisse(caisse_id)) with check (public.peut_utiliser_caisse(caisse_id));
drop policy if exists "mouvements_saisie_affectes" on caisse_mouvements;
create policy "mouvements_saisie_affectes" on caisse_mouvements as restrictive for insert
  with check (public.peut_utiliser_caisse(caisse_id)
              or (transfert_id is not null and type = 'entree'));   -- jambe d'arrivée d'un transfert entre caisses

-- Vente au comptoir : point de vente et caisse (espèces) réservés aux utilisateurs affectés
create or replace function public.vente_comptoir_controle_affectation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if new.point_vente_id is not null and not public.peut_utiliser_point_vente(new.point_vente_id) then
    raise exception 'Vous n''êtes pas affecté(e) à ce point de vente';
  end if;
  if new.caisse_id is not null and not public.peut_utiliser_caisse(new.caisse_id) then
    raise exception 'Vous n''êtes pas affecté(e) à cette caisse';
  end if;
  return new;
end $$;
drop trigger if exists trg_vente_comptoir_affectation on ventes_comptoir;
create trigger trg_vente_comptoir_affectation before insert on ventes_comptoir
  for each row execute function public.vente_comptoir_controle_affectation();

-- Seuls les utilisateurs connectés appellent ces fonctions
revoke execute on function public.definir_pin_caisse(uuid,text), public.supprimer_pin_caisse(uuid),
  public.verifier_pin_caisse(text), public.modifier_mon_pin_caisse(text,text), public.etat_pins_caisse(),
  public.caisse_ouvrir_session(uuid,numeric,text) from public, anon;
grant execute on function public.definir_pin_caisse(uuid,text), public.supprimer_pin_caisse(uuid),
  public.verifier_pin_caisse(text), public.modifier_mon_pin_caisse(text,text), public.etat_pins_caisse(),
  public.caisse_ouvrir_session(uuid,numeric,text) to authenticated;
