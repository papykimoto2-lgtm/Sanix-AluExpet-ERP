-- ============================================================================
-- Sanix AluExpert ERP — Vider la base de données depuis Paramétrage > Sauvegarde
-- ============================================================================
-- À exécuter UNE FOIS dans l'éditeur SQL Supabase. Crée la fonction
-- public.vider_donnees(p_mode), appelable uniquement par un utilisateur ayant le
-- rôle « admin ». Elle ne supprime aucun compte utilisateur, rôle, droit,
-- paramètre de société, plan comptable, journal ni dépôt.
--
--   p_mode = 'operations' (défaut) : efface l'activité — clients, prospects,
--            chantiers, devis, factures, paiements, fiches, stock (mouvements,
--            transferts, inventaires, commandes, réceptions), caisse,
--            comptabilité (écritures), ventes comptoir, réalisations.
--            Conserve les catalogues (produits, composants, fournisseurs,
--            catégories), les caisses et points de vente. Les stocks sont
--            remis à zéro.
--   p_mode = 'tout' : efface aussi les catalogues, fournisseurs, catégories,
--            caisses, points de vente et leurs affectations, journaux de
--            connexion.
--
-- Les compteurs de codes (CLI-, CH-, DEV-, FAC-…) repartent au début.
-- L'opération est atomique : en cas d'erreur, rien n'est supprimé.
-- ============================================================================
create or replace function public.vider_donnees(p_mode text default 'operations')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ops text[] := array['paiements','factures','devis_lignes','devis','fiche_execution_lignes','fiches_execution',
    'projets','clients','prospects','realisations','mouvements_stock','transferts_stock_lignes','transferts_stock',
    'inventaire_lignes','inventaires','commandes_fournisseur_lignes','commandes_fournisseur','commandes_internes_lignes',
    'commandes_internes','receptions_fournisseur_lignes','receptions_fournisseur','caisse_mouvements_audit',
    'caisse_mouvements','caisse_demandes','caisse_sessions','compta_lignes','compta_ecritures','ventes_comptoir_lignes',
    'ventes_comptoir','tickets_z','documents_imprimes'];
  v_cat text[] := array['photos_articles','produits','composants','fournisseurs','devis_categories','client_categories',
    'stocks_depot','caisse_regles_ventilation','caisse_affectations','caisse_pins','caisses','point_vente_affectations',
    'points_vente','logs_connexion','portail_tentatives'];
  v_liste text[];
  v_sql text;
  s record;
begin
  if not exists (select 1 from profiles p join roles r on r.id = p.role_id where p.id = auth.uid() and r.code = 'admin')
     or not public.est_utilisateur_autorise() then
    raise exception 'Réservé aux administrateurs.';
  end if;
  if p_mode not in ('operations','tout') then raise exception 'Mode invalide : %', p_mode; end if;

  v_liste := v_ops || (case when p_mode = 'tout' then v_cat else array[]::text[] end);
  select string_agg(format('public.%I', t), ', ') into v_sql
    from unnest(v_liste) t where to_regclass('public.' || t) is not null;

  -- Références des tables conservées vers des tables vidées
  if p_mode = 'operations' then
    begin update caisses set projet_id = null; exception when undefined_column or undefined_table then null; end;
  end if;

  execute 'truncate table ' || v_sql || ' restart identity';

  if p_mode = 'operations' then
    update composants set stock_actuel = 0;
    update stocks_depot set quantite = 0;
  end if;

  for s in select sequencename from pg_sequences where schemaname = 'public' and sequencename like '%\_code\_seq' loop
    execute format('alter sequence public.%I restart', s.sequencename);
  end loop;

  return jsonb_build_object('ok', true, 'mode', p_mode);
end $$;

revoke execute on function public.vider_donnees(text) from public, anon;
grant execute on function public.vider_donnees(text) to authenticated;
