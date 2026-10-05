-- ============================================================================
-- Sanix AluExpert ERP — Droits par module contrôlés EN BASE (revue de sécurité)
-- ============================================================================
-- À exécuter UNE FOIS dans l'éditeur SQL Supabase, après tous les autres scripts.
-- Ré-exécutable (à relancer aussi après tout script qui redéfinit stock_mouvement,
-- les transferts ou la vente au comptoir).
--
-- Jusqu'ici, les droits des rôles (voir / créer / modifier / supprimer / valider, par
-- module) n'étaient appliqués que par l'interface : un utilisateur pouvait écrire dans
-- n'importe quelle table en appelant directement l'API. Désormais chaque écriture
-- (création, modification, suppression) faite par un utilisateur est contrôlée en base,
-- avec un message clair en cas de refus.
--
--   • Un déclencheur par table vérifie le droit du rôle sur le(s) module(s) concerné(s).
--     Les opérations qui touchent plusieurs modules (une facture passe une écriture
--     comptable, une vente au comptoir crée un client ou sort du stock…) sont autorisées
--     par le droit du module d'origine.
--   • Les fonctions serveur (security definer) font leurs propres contrôles : elles ne
--     sont pas concernées. Les fonctions qui écrivaient avec les droits de l'utilisateur
--     (mouvement de stock, transferts, vente au comptoir) sont désormais enveloppées par
--     un contrôle de droit.
--   • Administrateur : tous les droits. Supprimer : réservé aux rôles admin et manager
--     autorisés (même règle que l'interface).
--   • Les LECTURES ne changent pas (les écrans d'un module lisent les données des autres).
--   • Interrupteur de secours (administrateur, Paramètres → Utilisateurs & Rôles) :
--     parametres.droits_en_base = false revient au contrôle par l'interface seule.
-- ============================================================================

alter table public.parametres add column if not exists droits_en_base boolean not null default true;

-- 1. Droit d'un utilisateur sur un module
create or replace function public.droit(p_module text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    left join role_permissions rp on rp.role_id = r.id and rp.module_code = p_module
    where p.id = auth.uid() and coalesce(p.actif, true) and not coalesce(p.must_change, false) and r.code <> 'sans_role'
      and (r.code = 'admin' or coalesce(case p_action
            when 'voir' then rp.peut_voir
            when 'creer' then rp.peut_creer
            when 'modifier' then rp.peut_modifier
            when 'supprimer' then rp.peut_supprimer and r.code in ('admin', 'manager') and coalesce(r.peut_supprimer, true)
            when 'valider' then rp.peut_valider end, false))
  );
$$;
-- Au moins un des droits « Module:action » de la liste
create or replace function public.droit_un(p_droits text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from unnest(p_droits) d where public.droit(split_part(d, ':', 1), split_part(d, ':', 2)));
$$;
create or replace function public.droits_en_base_actifs() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select droits_en_base from parametres limit 1), true);
$$;
-- Libellés lisibles pour les messages de refus
create or replace function public.droits_libelle(p_droits text[]) returns text
language sql immutable as $$
  select string_agg(distinct case split_part(d, ':', 1)
      when 'Projets' then 'Chantiers' when 'FichesExecution' then 'Fiches d''exécution' when 'Comptabilite' then 'Comptabilité'
      when 'Composants' then 'Composants & consommables' when 'Comptoir' then 'Vente au comptoir' when 'Realisations' then 'Réalisations'
      when 'Parametres' then 'Paramètres' when 'Utilisateurs' then 'Utilisateurs & Rôles' else split_part(d, ':', 1) end, ', ')
  from unnest(p_droits) d;
$$;

-- Vrai quand l'opération vient directement d'un utilisateur de l'API (et non d'une fonction serveur, qui s'exécute
-- sous son propriétaire). Les fonctions de contrôle ci-dessous sont donc SECURITY INVOKER.
create or replace function public.session_user_is_api() returns boolean
language sql stable as $$ select current_user in ('authenticated', 'anon') $$;

-- 2. Contrôle générique : TG_ARGV = droits création | modification | suppression (listes « Module:action » séparées par des virgules)
--    Appliqué seulement aux appels directs des utilisateurs (rôles authenticated / anon) : les fonctions serveur
--    (security definer) s'exécutent sous leur propriétaire et font leurs propres contrôles.
create or replace function public.droits_controle() returns trigger
language plpgsql set search_path = public as $$
declare v_droits text[]; v_verbe text;
begin
  if session_user_is_api() is not true or not public.droits_en_base_actifs() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'INSERT' then v_droits := string_to_array(tg_argv[0], ','); v_verbe := 'créer';
  elsif tg_op = 'UPDATE' then v_droits := string_to_array(tg_argv[1], ','); v_verbe := 'modifier';
  else v_droits := string_to_array(tg_argv[2], ','); v_verbe := 'supprimer'; end if;
  if not public.droit_un(v_droits) then
    raise exception '🔒 Votre rôle ne permet pas de % dans « % » (%).', v_verbe, public.droits_libelle(v_droits), tg_table_name
      using errcode = '42501', hint = 'Demandez le droit à un administrateur (Paramètres → Utilisateurs & Rôles).';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- Écritures comptables : la comptabilité, ou une écriture AUTOMATIQUE passée par un module de gestion
create or replace function public.droits_controle_compta() returns trigger
language plpgsql set search_path = public as $$
declare v_auto boolean; v_ecr compta_ecritures%rowtype;
  v_gestion text[] := array['Factures:creer','Factures:modifier','Caisse:creer','Caisse:modifier','Stock:creer','Stock:modifier',
                            'Comptoir:creer','Comptoir:modifier','FichesExecution:creer','FichesExecution:modifier','Parametres:creer'];
  v_compta text[];
begin
  if session_user_is_api() is not true or not public.droits_en_base_actifs() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_table_name = 'compta_ecritures' then
    v_auto := coalesce(case when tg_op = 'DELETE' then old.source else new.source end, '') = 'auto'
              and (tg_op <> 'UPDATE' or coalesce(old.source, '') = 'auto');
  else
    select * into v_ecr from compta_ecritures where id = case when tg_op = 'DELETE' then old.ecriture_id else new.ecriture_id end;
    if tg_op = 'DELETE' and v_ecr.id is null then return old; end if;   -- suppression en cascade de l'écriture (déjà contrôlée)
    v_auto := coalesce(v_ecr.source, '') = 'auto';
  end if;
  v_compta := case tg_op when 'INSERT' then array['Comptabilite:creer','Comptabilite:modifier']
                         when 'UPDATE' then array['Comptabilite:modifier','Comptabilite:valider']
                         else array['Comptabilite:supprimer','Comptabilite:modifier'] end;
  if public.droit_un(v_compta) or (v_auto and public.droit_un(v_gestion)) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception '🔒 Votre rôle ne permet pas de % des écritures comptables.', case tg_op when 'INSERT' then 'créer' when 'UPDATE' then 'modifier' else 'supprimer' end
    using errcode = '42501', hint = 'Demandez le droit « Comptabilité » à un administrateur (Paramètres → Utilisateurs & Rôles).';
end $$;

-- Interrupteur de secours : seul un administrateur peut le changer
create or replace function public.parametres_garde_droits() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.droits_en_base is distinct from old.droits_en_base and session_user_is_api() and not public.is_admin() then
    raise exception '🔒 Seul un administrateur peut activer ou désactiver le contrôle des droits en base.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_parametres_garde_droits on public.parametres;
create trigger trg_parametres_garde_droits before update of droits_en_base on public.parametres
  for each row execute function public.parametres_garde_droits();

-- 3. Matrice : table → droits création | modification | suppression
do $$
declare r record;
begin
  for r in select * from (values
    -- Tiers
    ('clients',               'Clients:creer,Prospects:modifier,Projets:creer,Devis:creer,Comptoir:creer,Caisse:creer,Stock:creer,Parametres:creer', 'Clients:modifier', 'Clients:supprimer'),
    ('client_categories',     'Clients:creer,Clients:modifier', 'Clients:creer,Clients:modifier', 'Clients:modifier,Clients:supprimer'),
    ('prospects',             'Prospects:creer,Parametres:creer', 'Prospects:modifier', 'Prospects:supprimer'),
    ('fournisseurs',          'Fournisseurs:creer,Stock:creer,Parametres:creer', 'Fournisseurs:modifier', 'Fournisseurs:supprimer'),
    -- Chantiers, devis, factures, fiches
    ('projets',               'Projets:creer,Caisse:creer,Stock:creer,Devis:creer,Parametres:creer', 'Projets:modifier', 'Projets:supprimer'),
    ('devis',                 'Devis:creer', 'Devis:modifier,Devis:creer,Factures:creer,FichesExecution:creer', 'Devis:supprimer'),
    ('devis_lignes',          'Devis:creer,Devis:modifier', 'Devis:modifier', 'Devis:modifier,Devis:supprimer'),
    ('devis_categories',      'Devis:creer,Devis:modifier', 'Devis:creer,Devis:modifier', 'Devis:modifier,Devis:supprimer'),
    ('factures',              'Factures:creer', 'Factures:modifier,Factures:creer', 'Factures:supprimer'),
    ('paiements',             'Factures:creer,Factures:modifier', 'Factures:modifier', 'Factures:supprimer'),
    ('fiches_execution',      'FichesExecution:creer,Devis:creer,Devis:modifier', 'FichesExecution:modifier,FichesExecution:creer,Devis:creer,Devis:modifier', 'FichesExecution:supprimer'),
    ('fiche_execution_lignes','FichesExecution:creer,FichesExecution:modifier,Devis:creer,Devis:modifier', 'FichesExecution:modifier', 'FichesExecution:modifier,FichesExecution:supprimer'),
    -- Catalogue et stock
    ('produits',              'Produits:creer,Parametres:creer', 'Produits:modifier', 'Produits:supprimer'),
    ('composants',            'Composants:creer,Stock:creer,Parametres:creer', 'Composants:modifier', 'Composants:supprimer'),
    ('photos_articles',       'Produits:creer,Produits:modifier,Composants:creer,Composants:modifier', 'Produits:modifier,Composants:modifier', 'Produits:modifier,Composants:modifier'),
    ('familles_articles',     'Produits:creer,Produits:modifier,Composants:creer,Composants:modifier,Stock:modifier,Parametres:modifier', 'Produits:modifier,Composants:modifier,Parametres:modifier', 'Produits:supprimer,Composants:supprimer,Parametres:modifier'),
    ('unites_mesure',         'Produits:creer,Produits:modifier,Composants:creer,Composants:modifier,Stock:modifier,Parametres:modifier', 'Produits:modifier,Composants:modifier,Parametres:modifier', 'Produits:supprimer,Composants:supprimer,Parametres:modifier'),
    ('depots',                'Stock:creer,Stock:modifier,Parametres:modifier', 'Stock:modifier,Parametres:modifier', 'Stock:supprimer'),
    ('stocks_depot',          'Stock:creer,Stock:modifier', 'Stock:modifier', 'Stock:supprimer'),
    ('mouvements_stock',      'Stock:creer,Stock:modifier', 'Stock:modifier', 'Stock:supprimer'),
    ('transferts_stock',      'Stock:creer,Stock:modifier', 'Stock:creer,Stock:modifier', 'Stock:modifier,Stock:supprimer'),
    ('transferts_stock_lignes','Stock:creer,Stock:modifier', 'Stock:creer,Stock:modifier', 'Stock:creer,Stock:modifier'),
    -- Comptabilité (hors écritures, traitées à part)
    ('compta_comptes',        'Comptabilite:creer,Comptabilite:modifier,Parametres:creer,Parametres:modifier', 'Comptabilite:modifier,Parametres:modifier', 'Comptabilite:supprimer'),
    ('compta_journaux',       'Comptabilite:creer,Comptabilite:modifier', 'Comptabilite:modifier', 'Comptabilite:supprimer'),
    ('compta_exercices',      'Comptabilite:creer,Comptabilite:modifier,Comptabilite:valider', 'Comptabilite:modifier,Comptabilite:valider', 'Comptabilite:supprimer'),
    -- Caisse et comptoir
    ('caisses',               'Caisse:creer,Caisse:modifier,Parametres:modifier', 'Caisse:modifier,Parametres:modifier', 'Caisse:supprimer'),
    ('caisse_mouvements',     'Caisse:creer,Factures:creer,Factures:modifier,Comptoir:creer,Comptoir:modifier', 'Caisse:creer,Caisse:modifier,Comptabilite:creer,Comptabilite:modifier', 'Caisse:supprimer'),
    ('caisse_regles_ventilation','Caisse:creer,Caisse:modifier,Comptabilite:creer,Comptabilite:modifier', 'Caisse:modifier,Comptabilite:modifier', 'Caisse:modifier,Comptabilite:modifier'),
    ('ventes_comptoir',       'Comptoir:creer', 'Comptoir:creer,Comptoir:modifier,Comptabilite:modifier', 'Comptoir:supprimer'),
    ('ventes_comptoir_lignes','Comptoir:creer', 'Comptoir:creer,Comptoir:modifier', 'Comptoir:supprimer'),
    ('points_vente',          'Comptoir:creer,Comptoir:modifier,Caisse:modifier,Parametres:modifier', 'Comptoir:modifier,Caisse:modifier,Parametres:modifier', 'Comptoir:supprimer'),
    -- Site web et réglages
    ('realisations',          'Realisations:creer', 'Realisations:modifier', 'Realisations:supprimer'),
    ('parametres',            'Parametres:creer,Parametres:modifier,Utilisateurs:modifier,Comptabilite:modifier,Caisse:valider,Clients:voir,Devis:voir,Factures:voir,Stock:voir,Caisse:voir,Comptoir:voir,Comptabilite:voir,Projets:voir',
                              'Parametres:modifier,Utilisateurs:modifier,Comptabilite:modifier,Caisse:valider', 'Parametres:supprimer')
  ) as m(t, ins, upd, del) loop
    if to_regclass('public.' || r.t) is null then continue; end if;
    execute format('drop trigger if exists trg_droits_module on public.%I', r.t);
    execute format('create trigger trg_droits_module before insert or update or delete on public.%I for each row execute function public.droits_controle(%L, %L, %L)',
                   r.t, r.ins, r.upd, r.del);
  end loop;
end $$;
drop trigger if exists trg_droits_module on public.compta_ecritures;
create trigger trg_droits_module before insert or update or delete on public.compta_ecritures for each row execute function public.droits_controle_compta();
drop trigger if exists trg_droits_module on public.compta_lignes;
create trigger trg_droits_module before insert or update or delete on public.compta_lignes for each row execute function public.droits_controle_compta();

-- 4. Fonctions serveur sans contrôle du MODULE : enveloppe security definer avec contrôle de droit.
--    • celles qui écrivaient avec les droits de l'utilisateur (mouvement de stock, transferts, vente au comptoir) ;
--    • celles qui ne vérifiaient que « utilisateur autorisé » (réception, commandes, inventaires, ticket Z).
--    L'implémentation est renommée « <nom>__interne » (non appelable par les utilisateurs) ; l'enveloppe garde le même
--    nom et la même signature : rien ne change dans l'application ni dans les fonctions qui l'appellent. Les contrôles
--    propres de l'implémentation (validation par palier, affectation au point de vente…) restent appliqués en plus.
do $$
declare
  r record; f record; v_appel text; v_retour text; v_corps text;
  v_marque constant text := 'enveloppe droits_modules';
begin
  for r in select * from (values
    ('stock_mouvement',                   'Stock:creer,Stock:modifier,FichesExecution:creer,FichesExecution:modifier,Comptoir:creer,Composants:creer,Parametres:creer'),
    ('transfert_expedier',                'Stock:creer,Stock:modifier,Stock:valider'),
    ('transfert_receptionner',            'Stock:creer,Stock:modifier,Stock:valider'),
    ('transfert_annuler',                 'Stock:modifier,Stock:supprimer,Stock:valider'),
    ('vente_comptoir_valider',            'Comptoir:creer'),
    ('vente_comptoir_annuler',            'Comptoir:modifier,Comptoir:supprimer,Comptoir:valider'),
    ('reception_fournisseur_enregistrer', 'Stock:creer,Stock:modifier'),
    ('reception_marquer_comptabilisee',   'Stock:creer,Stock:modifier,Comptabilite:modifier'),
    ('commande_fournisseur_enregistrer',  'Stock:creer,Stock:modifier'),
    ('commande_fournisseur_action',       'Stock:creer,Stock:modifier,Stock:valider'),
    ('commande_interne_enregistrer',      'Stock:creer,Stock:modifier'),
    ('commande_interne_action',           'Stock:creer,Stock:modifier,Stock:valider'),
    ('commande_interne_servir',           'Stock:creer,Stock:modifier,Stock:valider'),
    ('inventaire_enregistrer',            'Stock:creer,Stock:modifier'),
    ('inventaire_valider',                'Stock:modifier,Stock:valider'),
    ('inventaire_justifier',              'Stock:modifier,Stock:valider'),
    ('inventaire_regulariser',            'Stock:modifier,Stock:valider'),
    ('inventaire_supprimer_brouillon',    'Stock:creer,Stock:modifier'),
    ('ticket_z_emettre',                  'Comptoir:creer,Comptoir:modifier,Caisse:creer,Caisse:modifier')
  ) as m(nom, droits) loop
    for f in select p.oid, pg_get_function_arguments(p.oid) as args_def, pg_get_function_identity_arguments(p.oid) as args_id,
                    pg_get_function_result(p.oid) as resultat, p.proretset, p.proargnames, coalesce(obj_description(p.oid, 'pg_proc'), '') as note
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = r.nom loop
      if f.note <> v_marque then
        -- implémentation (première exécution, ou redéfinie depuis par un autre script) : la mettre de côté
        execute format('drop function if exists public.%I(%s)', r.nom || '__interne', f.args_id);
        execute format('alter function public.%I(%s) rename to %I', r.nom, f.args_id, r.nom || '__interne');
      end if;
      execute format('revoke execute on function public.%I(%s) from public, anon, authenticated', r.nom || '__interne', f.args_id);
      select coalesce(string_agg(format('%1$I => %1$I', a), ', '), '') into v_appel from unnest(f.proargnames) a;
      v_retour := case when f.proretset then format('return query select * from public.%I(%s); return;', r.nom || '__interne', v_appel)
                       when f.resultat = 'void' then format('perform public.%I(%s); return;', r.nom || '__interne', v_appel)
                       else format('return public.%I(%s);', r.nom || '__interne', v_appel) end;
      v_corps := format($f$
begin
  if not public.droits_en_base_actifs() then
    if not public.est_utilisateur_autorise() then raise exception 'Accès refusé.' using errcode = '42501'; end if;
  elsif not public.droit_un(%L::text[]) then
    raise exception '🔒 Votre rôle ne permet pas cette opération (« %% »).', public.droits_libelle(%L::text[])
      using errcode = '42501', hint = 'Demandez le droit à un administrateur (Paramètres → Utilisateurs & Rôles).';
  end if;
  %s
end $f$, '{' || r.droits || '}', '{' || r.droits || '}', v_retour);
      execute format('create or replace function public.%I(%s) returns %s language plpgsql security definer set search_path = public as %L',
                     r.nom, f.args_def, f.resultat, v_corps);
      execute format('comment on function public.%I(%s) is %L', r.nom, f.args_id, v_marque);
      execute format('revoke execute on function public.%I(%s) from public, anon', r.nom, f.args_id);
      execute format('grant execute on function public.%I(%s) to authenticated', r.nom, f.args_id);
    end loop;
  end loop;
end $$;

revoke execute on function public.droits_controle(), public.droits_controle_compta(), public.parametres_garde_droits() from public, anon, authenticated;
grant execute on function public.droit(text, text), public.droit_un(text[]), public.droits_en_base_actifs() to authenticated;
