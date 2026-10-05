-- ============================================================================
-- Sanix AluExpert ERP — Plan comptable : structure compte / sous-compte
-- ============================================================================
-- À exécuter UNE FOIS dans l'éditeur SQL Supabase (après sql/syscohada_revise.sql).
-- Additif et ré-exécutable. Apporte :
--   1. Options du plan (parametres.plan_comptable) : longueur normalisée des comptes
--      imputables, comptes auxiliaires clients / fournisseurs.
--   2. Comptes auxiliaires tiers : un sous-compte par client (sous le compte « Clients »
--      des réglages, ex. 4111) et par fournisseur (ex. 4011), créé à la demande ;
--      numérotation au choix (n° d'ordre, code du tiers, catégorie) ; compte créé
--      automatiquement dès la création du tiers ; libellé suivi au renommage du tiers.
--   3. Changement de code d'un compte (et de tous ses sous-comptes) avec report de
--      toutes les références : écritures, caisses, ventilations, demandes de caisse,
--      comptes par défaut, comptes auxiliaires.
--   4. Normalisation : chaque compte imputable plus court que la longueur choisie reçoit
--      un sous-compte normalisé (571 → 57100000) qui reprend ses mouvements de l'exercice
--      ouvert et ses réglages ; 571 devient un compte de regroupement.
-- Les exercices clôturés ne sont jamais modifiés.
-- ============================================================================

-- 1. Options et colonnes
alter table public.parametres add column if not exists plan_comptable jsonb not null default '{}'::jsonb;
alter table public.clients add column if not exists compte_code text references public.compta_comptes(code) on delete set null;
alter table public.fournisseurs add column if not exists compte_code text references public.compta_comptes(code) on delete set null;
-- Codes de compte strictement numériques pour tout nouveau compte (les comptes existants ne sont pas vérifiés : NOT VALID)
do $$ begin
  alter table public.compta_comptes add constraint compta_comptes_code_numerique check (code ~ '^[1-9][0-9]*$') not valid;
exception when duplicate_object then null; end $$;

-- Droit de restructurer le plan : administrateur, ou droit « modifier » sur la Comptabilité
create or replace function public.compta_peut_gerer_plan() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    left join role_permissions rp on rp.role_id = r.id and rp.module_code = 'Comptabilite'
    where p.id = auth.uid() and coalesce(p.actif, true)
      and (r.code = 'admin' or coalesce(rp.peut_modifier, false))
  ) and public.est_utilisateur_autorise();   -- compte actif, mot de passe provisoire changé, rôle attribué
$$;

-- Nature par défaut d'un compte selon sa classe (même règle que l'application)
create or replace function public.compta_nature_classe(p_code text) returns text
language sql immutable as $$
  select case left(p_code, 1) when '1' then 'passif' when '2' then 'actif' when '3' then 'actif'
    when '5' then 'actif' when '6' then 'charge' when '7' then 'produit' else 'autre' end;
$$;

-- Le contrôle « compte de regroupement non imputable » est suspendu pendant une restructuration
-- (les lignes historiques d'un regroupement déplacé restent sur le regroupement déplacé).
create or replace function public.compta_lignes_garde_imputable() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('compta.restructuration', true), '') = 'on'
     and current_user not in ('authenticated', 'anon') then return new; end if;   -- seulement depuis les fonctions du plan
  if public.compta_compte_est_regroupement(new.compte_code) then
    raise exception 'Le compte % est un compte de regroupement (il a des sous-comptes) : imputez l''écriture sur l''un de ses sous-comptes.', new.compte_code
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- Report de toutes les références d'un ensemble de codes (table temporaire _compta_map : ancien → nouveau).
-- p_lignes_closes : reporter aussi les lignes d'écriture des exercices clôturés.
create or replace function public.compta__reporter_references(p_defauts jsonb, p_lignes_closes boolean) returns integer
language plpgsql set search_path = public as $$
declare v_lignes integer;
begin
  perform set_config('compta.restructuration', 'on', true);
  update compta_lignes l set compte_code = m.nouveau
    from _compta_map m, compta_ecritures e
    where l.compte_code = m.ancien and e.id = l.ecriture_id
      and (p_lignes_closes or not exists (select 1 from compta_exercices x where x.annee = e.exercice_annee and x.statut = 'cloture'));
  get diagnostics v_lignes = row_count;
  perform set_config('compta.restructuration', '', true);
  update caisses x set compte_code = m.nouveau from _compta_map m where x.compte_code = m.ancien;
  update caisse_mouvements x set compte_ventile = m.nouveau from _compta_map m where x.compte_ventile = m.ancien;
  update caisse_regles_ventilation x set compte_code = m.nouveau from _compta_map m where x.compte_code = m.ancien;
  begin
    update caisse_demandes x set compte_imputation = m.nouveau from _compta_map m where x.compte_imputation = m.ancien;
  exception when undefined_column or undefined_table then null; end;
  update clients x set compte_code = m.nouveau from _compta_map m where x.compte_code = m.ancien;
  update fournisseurs x set compte_code = m.nouveau from _compta_map m where x.compte_code = m.ancien;
  -- Comptes par défaut : p_defauts = comptes effectifs vus par l'application (réglages + valeurs de repli)
  update parametres p set comptes_defaut = coalesce(p.comptes_defaut, '{}'::jsonb) || coalesce((
      select jsonb_object_agg(e.key, m.nouveau)
      from jsonb_each_text(coalesce(p_defauts, '{}'::jsonb) || coalesce(p.comptes_defaut, '{}'::jsonb)) e
      join _compta_map m on m.ancien = e.value), '{}'::jsonb);
  return v_lignes;
end $$;

-- 2. Compte auxiliaire d'un tiers (créé s'il n'existe pas). p_id null → compte « divers ».
--    Numérotation (parametres.plan_comptable->>'format_aux') :
--      sequentiel (défaut) : collectif + n° d'ordre            4111 → 41110001, 41110002…
--      code_tiers          : collectif + n° du code du tiers   C-1234 → 41111234 (sinon n° d'ordre)
--      categorie           : collectif + chiffre de la catégorie + n° d'ordre
--                            Particulier → 41111 (« Clients — Particulier ») → 41111001…
--    Le compte « divers » est le collectif complété de zéros (41110000).
create or replace function public.compta_compte_tiers(p_type text, p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cle text; v_parent text; v_long integer; v_lg integer; v_code text; v_nom text; v_existant text; v_n bigint;
  v_p compta_comptes%rowtype; v_format text; v_codetiers text; v_cat text; v_base text; v_chiffre text; v_map jsonb; v_chiffres text;
begin
  if auth.uid() is null or not public.est_utilisateur_autorise() then raise exception 'Accès refusé.'; end if;
  if p_type not in ('client','fournisseur') then raise exception 'Type de tiers invalide : %', p_type; end if;
  v_cle := case p_type when 'client' then 'clients' else 'fournisseurs' end;
  select nullif(comptes_defaut->>v_cle, ''), coalesce(nullif(plan_comptable->>'longueur', '')::integer, 0),
         coalesce(nullif(plan_comptable->>'format_aux', ''), 'sequentiel')
    into v_parent, v_long, v_format from parametres limit 1;
  v_parent := coalesce(v_parent, case p_type when 'client' then '4111' else '4011' end);
  v_long := coalesce(v_long, 0); v_format := coalesce(v_format, 'sequentiel');
  select * into v_p from compta_comptes where code = v_parent;
  if v_p.code is null then raise exception 'Le compte collectif % est absent du plan comptable.', v_parent; end if;
  v_lg := case when v_long > length(v_parent) then v_long else length(v_parent) + 4 end;

  if p_id is not null then
    if p_type = 'client' then
      select compte_code, trim(coalesce(nom, '') || ' ' || coalesce(prenoms, '')), code, categorie
        into v_existant, v_nom, v_codetiers, v_cat from clients where id = p_id for update;
    else
      select compte_code, nom, code, categorie into v_existant, v_nom, v_codetiers, v_cat from fournisseurs where id = p_id for update;
    end if;
    if not found then raise exception 'Tiers introuvable.'; end if;
    if v_existant is not null and exists (select 1 from compta_comptes where code = v_existant and actif) then return v_existant; end if;
  end if;

  perform pg_advisory_xact_lock(hashtext('compta_compte_tiers:' || v_parent));
  if p_id is null then
    v_code := rpad(v_parent, v_lg, '0');
    insert into compta_comptes (code, libelle, classe, nature, actif, standard)
      values (v_code, case p_type when 'client' then 'Clients divers' else 'Fournisseurs divers' end, v_p.classe, v_p.nature, true, false)
      on conflict (code) do update set actif = true;
    return v_code;
  end if;

  v_base := v_parent;
  if v_format = 'code_tiers' then
    v_chiffres := regexp_replace(coalesce(v_codetiers, ''), '[^0-9]', '', 'g');
    if v_chiffres <> '' and length(v_parent) + length(v_chiffres) <= v_lg then
      v_code := v_parent || lpad(v_chiffres, v_lg - length(v_parent), '0');
      if v_code <> rpad(v_parent, v_lg, '0') and not exists (select 1 from compta_comptes where code = v_code) then
        insert into compta_comptes (code, libelle, classe, nature, actif, standard)
          values (v_code, left(coalesce(nullif(v_nom, ''), 'Tiers'), 120), v_p.classe, v_p.nature, true, false);
        if p_type = 'client' then update clients set compte_code = v_code where id = p_id;
        else update fournisseurs set compte_code = v_code where id = p_id; end if;
        return v_code;
      end if;
    end if;   -- code absent, trop long ou déjà pris : numéro d'ordre
  elsif v_format = 'categorie' then
    v_cat := coalesce(nullif(trim(v_cat), ''), 'Autres');
    select coalesce(plan_comptable->'aux_categories'->p_type, '{}'::jsonb) into v_map from parametres limit 1;
    v_map := coalesce(v_map, '{}'::jsonb);
    v_chiffre := v_map->>v_cat;
    if v_chiffre is null then
      select min(d)::text into v_chiffre from generate_series(1, 9) d
        where not exists (select 1 from jsonb_each_text(v_map) e where e.value = d::text);
      v_chiffre := coalesce(v_chiffre, '9');
      update parametres set plan_comptable = coalesce(plan_comptable, '{}'::jsonb)
        || jsonb_build_object('aux_categories', coalesce(plan_comptable->'aux_categories', '{}'::jsonb) || jsonb_build_object(p_type, v_map || jsonb_build_object(v_cat, v_chiffre)));
    end if;
    v_base := v_parent || v_chiffre;
    if v_lg <= length(v_base) then v_lg := length(v_base) + 3; end if;
    insert into compta_comptes (code, libelle, classe, nature, actif, standard)
      values (v_base, left(case p_type when 'client' then 'Clients' else 'Fournisseurs' end || ' — ' || v_cat, 120), v_p.classe, v_p.nature, true, false)
      on conflict (code) do update set actif = true;
  end if;

  select coalesce(max(substr(code, length(v_base) + 1)::bigint), 0) + 1 into v_n
    from compta_comptes
    where left(code, length(v_base)) = v_base and length(code) = v_lg and substr(code, length(v_base) + 1) ~ '^[0-9]+$';
  v_code := v_base || lpad(v_n::text, v_lg - length(v_base), '0');
  if length(v_code) > v_lg then raise exception 'Plus aucun numéro libre sous le compte % (longueur %).', v_base, v_lg; end if;
  insert into compta_comptes (code, libelle, classe, nature, actif, standard)
    values (v_code, left(coalesce(nullif(v_nom, ''), 'Tiers'), 120), v_p.classe, v_p.nature, true, false);
  if p_type = 'client' then update clients set compte_code = v_code where id = p_id;
  else update fournisseurs set compte_code = v_code where id = p_id; end if;
  return v_code;
end $$;

-- Création AUTOMATIQUE du compte auxiliaire dès la création du tiers (fiche, import, vente au comptoir, création
-- rapide…), si les comptes auxiliaires sont activés pour ce type de tiers. Un échec (compte collectif absent du plan…)
-- n'empêche jamais l'enregistrement du tiers : son compte sera alors créé à sa première écriture comptable.
create or replace function public.compta_tiers_compte_auto() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text := case tg_table_name when 'clients' then 'client' else 'fournisseur' end; v_actif boolean;
begin
  if new.compte_code is not null then return new; end if;
  select coalesce((plan_comptable->>(case v_type when 'client' then 'aux_clients' else 'aux_fournisseurs' end))::boolean, false)
    into v_actif from parametres limit 1;
  if coalesce(v_actif, false) then
    begin
      perform public.compta_compte_tiers(v_type, new.id);
    exception when others then
      raise warning 'Compte auxiliaire non créé pour le % % : %', v_type, new.id, sqlerrm;
    end;
  end if;
  return new;
end $$;
revoke execute on function public.compta_tiers_compte_auto() from public, anon, authenticated;
drop trigger if exists trg_clients_compte_auto on public.clients;
create trigger trg_clients_compte_auto after insert on public.clients
  for each row execute function public.compta_tiers_compte_auto();
drop trigger if exists trg_fournisseurs_compte_auto on public.fournisseurs;
create trigger trg_fournisseurs_compte_auto after insert on public.fournisseurs
  for each row execute function public.compta_tiers_compte_auto();

-- Libellé du compte auxiliaire mis à jour quand le tiers est renommé (sauf libellé personnalisé)
create or replace function public.compta_client_libelle_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ancien text := left(trim(coalesce(old.nom, '') || ' ' || coalesce(old.prenoms, '')), 120);
        v_nouveau text := left(trim(coalesce(new.nom, '') || ' ' || coalesce(new.prenoms, '')), 120);
begin
  if new.compte_code is not null and v_nouveau <> '' and v_nouveau is distinct from v_ancien then
    update compta_comptes set libelle = v_nouveau where code = new.compte_code and libelle = v_ancien;
  end if;
  return new;
end $$;
create or replace function public.compta_fournisseur_libelle_sync() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.compte_code is not null and coalesce(new.nom, '') <> '' and new.nom is distinct from old.nom then
    update compta_comptes set libelle = left(new.nom, 120) where code = new.compte_code and libelle = left(old.nom, 120);
  end if;
  return new;
end $$;
drop trigger if exists trg_clients_compte_libelle on public.clients;
create trigger trg_clients_compte_libelle after update of nom, prenoms on public.clients
  for each row execute function public.compta_client_libelle_sync();
drop trigger if exists trg_fournisseurs_compte_libelle on public.fournisseurs;
create trigger trg_fournisseurs_compte_libelle after update of nom on public.fournisseurs
  for each row execute function public.compta_fournisseur_libelle_sync();

-- Création en masse des comptes auxiliaires ; p_reclasser : les lignes de l'exercice ouvert passées sur le
-- compte collectif avec un tiers identifié sont reportées sur le compte auxiliaire de ce tiers.
create or replace function public.compta_comptes_tiers_generer(p_type text, p_reclasser boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record; v_crees integer := 0; v_reclasses integer := 0; v_parent text; v_divers text; v_n integer;
begin
  if not public.compta_peut_gerer_plan() then raise exception 'Droit insuffisant : administrateur ou droit « modifier » en Comptabilité requis.'; end if;
  if p_type = 'client' then
    for r in select id from clients where compte_code is null or not exists (select 1 from compta_comptes c where c.code = clients.compte_code and c.actif) loop
      perform public.compta_compte_tiers('client', r.id); v_crees := v_crees + 1;
    end loop;
  elsif p_type = 'fournisseur' then
    for r in select id from fournisseurs where compte_code is null or not exists (select 1 from compta_comptes c where c.code = fournisseurs.compte_code and c.actif) loop
      perform public.compta_compte_tiers('fournisseur', r.id); v_crees := v_crees + 1;
    end loop;
  else raise exception 'Type de tiers invalide : %', p_type; end if;

  if p_reclasser then
    select coalesce(nullif(comptes_defaut->>(case p_type when 'client' then 'clients' else 'fournisseurs' end), ''),
                    case p_type when 'client' then '4111' else '4011' end) into v_parent from parametres limit 1;
    v_parent := coalesce(v_parent, case p_type when 'client' then '4111' else '4011' end);
    perform set_config('compta.restructuration', 'on', true);
    update compta_lignes l set compte_code = t.compte_code
      from compta_ecritures e, (select id, compte_code from clients where p_type = 'client'
                                union all select id, compte_code from fournisseurs where p_type = 'fournisseur') t
      where e.id = l.ecriture_id and l.compte_code = v_parent and l.tiers_type = p_type and l.tiers_id = t.id and t.compte_code is not null
        and not exists (select 1 from compta_exercices x where x.annee = e.exercice_annee and x.statut = 'cloture');
    get diagnostics v_n = row_count; v_reclasses := v_n;
    if exists (select 1 from compta_lignes l join compta_ecritures e on e.id = l.ecriture_id
               where l.compte_code = v_parent and l.tiers_type = p_type
                 and not exists (select 1 from compta_exercices x where x.annee = e.exercice_annee and x.statut = 'cloture')) then
      v_divers := public.compta_compte_tiers(p_type, null);
      update compta_lignes l set compte_code = v_divers from compta_ecritures e
        where e.id = l.ecriture_id and l.compte_code = v_parent and l.tiers_type = p_type
          and not exists (select 1 from compta_exercices x where x.annee = e.exercice_annee and x.statut = 'cloture');
      get diagnostics v_n = row_count; v_reclasses := v_reclasses + v_n;
    end if;
    perform set_config('compta.restructuration', '', true);
  end if;
  return jsonb_build_object('ok', true, 'crees', v_crees, 'reclasses', v_reclasses);
end $$;

-- 3. Changement de code d'un compte et de ses sous-comptes (déplacement dans l'arborescence)
create or replace function public.compta_compte_recoder(p_ancien text, p_nouveau text, p_libelle text, p_defauts jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lp integer; v_n integer; v_lignes integer; v_conflit text;
begin
  if not public.compta_peut_gerer_plan() then raise exception 'Droit insuffisant : administrateur ou droit « modifier » en Comptabilité requis.'; end if;
  p_nouveau := trim(coalesce(p_nouveau, ''));
  if p_nouveau !~ '^[1-9][0-9]*$' then raise exception 'Code invalide : numérique, commençant par le chiffre de la classe (1 à 9).'; end if;
  if not exists (select 1 from compta_comptes where code = p_ancien) then raise exception 'Compte % introuvable.', p_ancien; end if;
  if p_nouveau = p_ancien then
    update compta_comptes set libelle = coalesce(nullif(trim(p_libelle), ''), libelle) where code = p_ancien;
    return jsonb_build_object('ok', true, 'comptes', 0, 'lignes', 0);
  end if;
  v_lp := length(p_ancien);
  drop table if exists _compta_map;
  create temp table _compta_map on commit drop as
    select code as ancien, p_nouveau || substr(code, v_lp + 1) as nouveau from compta_comptes where left(code, v_lp) = p_ancien;
  select m.nouveau into v_conflit from _compta_map m join compta_comptes c on c.code = m.nouveau limit 1;
  if v_conflit is not null then raise exception 'Le code % existe déjà dans le plan comptable.', v_conflit; end if;
  if exists (select 1 from compta_lignes l join compta_ecritures e on e.id = l.ecriture_id
             join compta_exercices x on x.annee = e.exercice_annee and x.statut = 'cloture'
             where l.compte_code in (select ancien from _compta_map)) then
    raise exception 'Ce compte (ou un de ses sous-comptes) est mouvementé dans un exercice clôturé : son code ne peut plus changer. Créez un nouveau compte à la place.';
  end if;
  insert into compta_comptes (code, libelle, classe, nature, actif, standard, created_at)
    select m.nouveau,
           case when c.code = p_ancien then coalesce(nullif(trim(p_libelle), ''), c.libelle) else c.libelle end,
           left(m.nouveau, 1)::smallint,
           case when left(m.nouveau, 1) = left(c.code, 1) then c.nature
                else coalesce((select pp.nature from compta_comptes pp
                               where pp.code not in (select ancien from _compta_map)
                                 and left(m.nouveau, length(pp.code)) = pp.code and pp.code <> m.nouveau
                               order by length(pp.code) desc limit 1), public.compta_nature_classe(m.nouveau)) end,
           c.actif, c.standard, c.created_at
    from _compta_map m join compta_comptes c on c.code = m.ancien;
  get diagnostics v_n = row_count;
  v_lignes := public.compta__reporter_references(p_defauts, true);
  delete from compta_comptes where code in (select ancien from _compta_map);
  return jsonb_build_object('ok', true, 'comptes', v_n, 'lignes', v_lignes);
end $$;

-- 4. Normalisation de la longueur des comptes imputables. p_appliquer = false : aperçu seulement.
create or replace function public.compta_plan_normaliser(p_longueur integer, p_appliquer boolean, p_defauts jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_liste jsonb; v_n integer := 0; v_lignes integer := 0;
begin
  if not public.compta_peut_gerer_plan() then raise exception 'Droit insuffisant : administrateur ou droit « modifier » en Comptabilité requis.'; end if;
  if p_longueur is null or p_longueur < 4 or p_longueur > 12 then raise exception 'Longueur invalide (4 à 12 chiffres).'; end if;
  drop table if exists _compta_norm;
  create temp table _compta_norm on commit drop as
    select c.code as ancien, rpad(c.code, p_longueur, '0') as nouveau,
      case when exists (select 1 from compta_comptes d where d.code = rpad(c.code, p_longueur, '0')) then 'conflit'
           else 'a_creer' end as statut
    from compta_comptes c
    where c.actif and c.code ~ '^[0-9]+$' and length(c.code) < p_longueur
      and not exists (select 1 from compta_comptes d where d.code <> c.code and left(d.code, length(c.code)) = c.code)
      -- un compte collectif avec comptes auxiliaires reste un regroupement : il n'est pas normalisé
      and c.code not in (select e.value from parametres p, jsonb_each_text(coalesce(p_defauts, '{}'::jsonb) || coalesce(p.comptes_defaut, '{}'::jsonb)) e
                         where (e.key = 'clients' and coalesce((p.plan_comptable->>'aux_clients')::boolean, false))
                            or (e.key = 'fournisseurs' and coalesce((p.plan_comptable->>'aux_fournisseurs')::boolean, false)));
  select coalesce(jsonb_agg(jsonb_build_object('ancien', ancien, 'nouveau', nouveau, 'statut', statut) order by ancien), '[]'::jsonb)
    into v_liste from _compta_norm;
  if p_appliquer then
    insert into compta_comptes (code, libelle, classe, nature, actif, standard)
      select n.nouveau, c.libelle, c.classe, c.nature, true, false
      from _compta_norm n join compta_comptes c on c.code = n.ancien where n.statut = 'a_creer';
    get diagnostics v_n = row_count;
    drop table if exists _compta_map;
    create temp table _compta_map on commit drop as select ancien, nouveau from _compta_norm where statut = 'a_creer';
    v_lignes := public.compta__reporter_references(p_defauts, false);
    update parametres set plan_comptable = coalesce(plan_comptable, '{}'::jsonb) || jsonb_build_object('longueur', p_longueur);
  end if;
  return jsonb_build_object('ok', true, 'comptes', v_liste, 'crees', v_n, 'lignes', v_lignes);
end $$;

revoke execute on function public.compta__reporter_references(jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.compta_compte_tiers(text, uuid), public.compta_comptes_tiers_generer(text, boolean),
  public.compta_compte_recoder(text, text, text, jsonb), public.compta_plan_normaliser(integer, boolean, jsonb),
  public.compta_peut_gerer_plan() from public, anon;
grant execute on function public.compta_compte_tiers(text, uuid), public.compta_comptes_tiers_generer(text, boolean),
  public.compta_compte_recoder(text, text, text, jsonb), public.compta_plan_normaliser(integer, boolean, jsonb),
  public.compta_peut_gerer_plan() to authenticated;
