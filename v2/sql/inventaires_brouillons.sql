-- ============================================================================
-- Sanix AluExpert ERP — Inventaires : brouillons enregistrés, inventaires partiels,
-- motif « stock initial » et régularisation des ajustements hors registre
-- ============================================================================
-- • Un inventaire peut être ENREGISTRÉ en brouillon sur le serveur (inventaire_enregistrer) : il garde son
--   numéro INV-AAAA-NNNN, se reprend sur n'importe quel appareil, s'imprime en état PROVISOIRE, et ne touche
--   pas au stock tant qu'il n'est pas validé.
-- • La validation (inventaire_valider) peut finaliser un brouillon et porter seulement sur les articles
--   réellement comptés (inventaire PARTIEL : une famille, une zone…) ; le stock des autres n'est pas touché.
-- • Motif « Stock initial / reprise de stock » pour la mise en place du stock d'un dépôt.
-- • inventaire_regulariser : rattache à un inventaire enregistré (état imprimable) les ajustements
--   « inventaire » passés hors registre (ancienne version de l'écran ou saisie unitaire), sans retoucher le stock.
-- ============================================================================
alter table public.inventaires add column if not exists statut text not null default 'valide';
alter table public.inventaires add column if not exists partiel boolean not null default false;
alter table public.inventaires add column if not exists nb_articles_depot integer;
alter table public.inventaires add column if not exists regularisation boolean not null default false;
alter table public.inventaires add column if not exists modifie_le timestamptz;
alter table public.inventaires add column if not exists modifie_par_nom text;
alter table public.inventaires drop constraint if exists inventaires_statut_check;
alter table public.inventaires add constraint inventaires_statut_check check (statut in ('brouillon','valide'));

create or replace function public.inventaire_motif_libelle(p_motif text) returns text
language sql immutable as $$
  select case p_motif
    when 'stock_initial' then 'Stock initial / reprise de stock'
    when 'casse' then 'Casse / détérioration' when 'vol' then 'Vol' when 'perte' then 'Perte / disparition'
    when 'peremption' then 'Péremption' when 'chute_decoupe' then 'Chutes de découpe non déclarées'
    when 'consommation_non_saisie' then 'Consommation chantier / atelier non saisie'
    when 'reception_non_saisie' then 'Réception fournisseur non saisie' when 'sortie_non_saisie' then 'Sortie / livraison non saisie'
    when 'transfert_non_saisi' then 'Transfert entre dépôts non saisi' when 'erreur_saisie' then 'Erreur de saisie antérieure'
    when 'erreur_comptage' then 'Erreur de comptage (inventaire précédent)' when 'erreur_unite' then 'Erreur d''unité / de conditionnement'
    when 'autre' then 'Autre' else p_motif end;
$$;

-- Numéro INV-AAAA-NNNN (brouillons et inventaires validés partagent la séquence)
create or replace function public.inventaire_prochain_code(p_date date) returns text
language plpgsql security definer set search_path = public as $$
declare v_an text := to_char(coalesce(p_date, current_date), 'YYYY'); v_num int;
begin
  perform pg_advisory_xact_lock(hashtext('inventaire:' || v_an));
  select coalesce(max(nullif(split_part(code, '-', 3), '')::int), 0) + 1 into v_num from inventaires where code like 'INV-' || v_an || '-%';
  return 'INV-' || v_an || '-' || lpad(v_num::text, 4, '0');
end $$;
revoke all on function public.inventaire_prochain_code(date) from public, anon, authenticated;

create or replace function public.inventaire_nom_utilisateur() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.nom_complet, ''), u.email) from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid();
$$;
revoke all on function public.inventaire_nom_utilisateur() from public, anon;

-- Lignes d'un inventaire (brouillon ou validé) : stock système lu au moment de l'appel
create or replace function public.inventaire_ecrire_lignes(p_inv uuid, p_depot uuid, p_lignes jsonb, p_controle boolean)
returns void language plpgsql security definer set search_path = public as $$
declare l jsonb; c public.composants; v_sys numeric; v_cpt numeric; v_ecart numeric; v_cmup numeric; v_motif text; v_just text; v_nom text := public.inventaire_nom_utilisateur();
begin
  delete from inventaire_lignes where inventaire_id = p_inv;
  for l in select * from jsonb_array_elements(coalesce(p_lignes, '[]'::jsonb)) loop
    select * into c from composants where id = (l->>'composant_id')::uuid;
    if c.id is null then raise exception 'Article introuvable dans l''inventaire'; end if;
    v_cpt := (l->>'quantite_comptee')::numeric;
    if v_cpt is null or v_cpt < 0 then raise exception 'Quantité comptée invalide pour « % »', c.nom; end if;
    select coalesce((select quantite from stocks_depot where depot_id = p_depot and composant_id = c.id), 0) into v_sys;
    v_ecart := v_cpt - v_sys;
    v_motif := nullif(trim(l->>'motif'), ''); v_just := nullif(trim(l->>'justification'), '');
    if v_motif is not null and public.inventaire_motif_libelle(v_motif) = v_motif then raise exception 'Motif d''écart inconnu : %', v_motif; end if;
    if abs(v_ecart) > 0.0001 then
      if p_controle and v_motif is null then raise exception 'Écart non justifié : « % » (% → %). Choisissez un motif.', c.nom, v_sys, v_cpt; end if;
      if p_controle and v_motif = 'autre' and v_just is null then raise exception 'Motif « Autre » : précisez la justification de l''écart sur « % »', c.nom; end if;
    else
      v_ecart := 0; if p_controle then v_motif := null; v_just := null; end if;
    end if;
    v_cmup := coalesce(nullif(c.cmup, 0), c.prix_unitaire, 0);
    insert into inventaire_lignes (inventaire_id, composant_id, code_article, designation, famille, unite, emplacement,
      stock_systeme, quantite_comptee, ecart, cmup, valeur_ecart, motif, justification, justifie_par, justifie_le)
      values (p_inv, c.id, coalesce(c.code, c.reference), c.nom, c.famille, c.unite, c.emplacement,
        v_sys, v_cpt, v_ecart, v_cmup, round(v_ecart * v_cmup, 2), v_motif, v_just,
        case when v_motif is not null then v_nom end, case when v_motif is not null then now() end);
  end loop;
end $$;
revoke all on function public.inventaire_ecrire_lignes(uuid, uuid, jsonb, boolean) from public, anon, authenticated;

create or replace function public.inventaire_totaux(p_inv uuid) returns void
language sql security definer set search_path = public as $$
  update inventaires i set
    nb_articles = s.n, nb_ecarts = s.ne, valeur_theorique = s.vt, valeur_reelle = s.vr, ecart_positif = s.ep, ecart_negatif = s.en
  from (select count(*) n, count(*) filter (where ecart <> 0) ne,
          coalesce(sum(round(stock_systeme * cmup, 2)), 0) vt, coalesce(sum(round(quantite_comptee * cmup, 2)), 0) vr,
          coalesce(sum(valeur_ecart) filter (where valeur_ecart > 0), 0) ep, coalesce(sum(valeur_ecart) filter (where valeur_ecart < 0), 0) en
        from inventaire_lignes where inventaire_id = p_inv) s
  where i.id = p_inv;
$$;
revoke all on function public.inventaire_totaux(uuid) from public, anon, authenticated;

-- Enregistre (crée ou met à jour) un brouillon ; ne modifie pas le stock
create or replace function public.inventaire_enregistrer(p_id uuid, p_depot uuid, p_date date, p_responsable text, p_controleur text,
  p_observations text, p_lignes jsonb, p_partiel boolean default true)
returns public.inventaires language plpgsql security definer set search_path = public as $$
declare v public.inventaires; v_depot uuid;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  v_depot := coalesce(p_depot, (select id from depots where est_principal limit 1));
  if v_depot is null then raise exception 'Dépôt introuvable'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'Date d''inventaire dans le futur'; end if;
  if p_id is not null then
    select * into v from inventaires where id = p_id for update;
    if v.id is null then raise exception 'Brouillon introuvable'; end if;
    if v.statut <> 'brouillon' then raise exception 'Cet inventaire est déjà validé : il ne peut plus être modifié'; end if;
    if v.depot_id <> v_depot then raise exception 'Ce brouillon concerne un autre dépôt'; end if;
    update inventaires set date_inventaire = coalesce(p_date, current_date), responsable = nullif(trim(p_responsable), ''), controleur = nullif(trim(p_controleur), ''),
      observations = nullif(trim(p_observations), ''), partiel = coalesce(p_partiel, true), modifie_le = now(), modifie_par_nom = public.inventaire_nom_utilisateur()
      where id = v.id;
  else
    insert into inventaires (code, statut, depot_id, depot_nom, date_inventaire, responsable, controleur, observations, partiel, valide_par, valide_par_nom, modifie_le, modifie_par_nom)
      values (public.inventaire_prochain_code(p_date), 'brouillon', v_depot, (select nom from depots where id = v_depot), coalesce(p_date, current_date),
        nullif(trim(p_responsable), ''), nullif(trim(p_controleur), ''), nullif(trim(p_observations), ''), coalesce(p_partiel, true), null, null, now(), public.inventaire_nom_utilisateur())
      returning * into v;
  end if;
  perform public.inventaire_ecrire_lignes(v.id, v_depot, p_lignes, false);
  update inventaires set nb_articles_depot = (select count(*) from composants) where id = v.id;
  perform public.inventaire_totaux(v.id);
  select * into v from inventaires where id = v.id;
  return v;
end $$;
revoke all on function public.inventaire_enregistrer(uuid, uuid, date, text, text, text, jsonb, boolean) from public, anon;
grant execute on function public.inventaire_enregistrer(uuid, uuid, date, text, text, text, jsonb, boolean) to authenticated;

-- Validation : ajuste le stock des articles comptés (écarts justifiés), fige l'inventaire ; finalise un brouillon si fourni
drop function if exists public.inventaire_valider(uuid, date, text, text, text, jsonb);
create or replace function public.inventaire_valider(p_depot uuid, p_date date, p_responsable text, p_controleur text,
  p_observations text, p_lignes jsonb, p_brouillon uuid default null, p_partiel boolean default false)
returns public.inventaires language plpgsql security definer set search_path = public as $$
declare v public.inventaires; li public.inventaire_lignes; v_depot uuid; v_nom text := public.inventaire_nom_utilisateur();
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  v_depot := coalesce(p_depot, (select id from depots where est_principal limit 1));
  if v_depot is null then raise exception 'Dépôt introuvable'; end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'Aucun article compté'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'Date d''inventaire dans le futur'; end if;
  if p_brouillon is not null then
    select * into v from inventaires where id = p_brouillon for update;
    if v.id is null then raise exception 'Brouillon introuvable'; end if;
    if v.statut <> 'brouillon' then raise exception 'Cet inventaire est déjà validé (%)', v.code; end if;
    if v.depot_id <> v_depot then raise exception 'Ce brouillon concerne un autre dépôt'; end if;
    update inventaires set statut = 'valide', date_inventaire = coalesce(p_date, current_date), responsable = nullif(trim(p_responsable), ''),
      controleur = nullif(trim(p_controleur), ''), observations = nullif(trim(p_observations), ''), partiel = coalesce(p_partiel, false),
      valide_par = auth.uid(), valide_par_nom = v_nom, created_at = now()
      where id = v.id returning * into v;
  else
    insert into inventaires (code, statut, depot_id, depot_nom, date_inventaire, responsable, controleur, observations, partiel, valide_par, valide_par_nom)
      values (public.inventaire_prochain_code(p_date), 'valide', v_depot, (select nom from depots where id = v_depot), coalesce(p_date, current_date),
        nullif(trim(p_responsable), ''), nullif(trim(p_controleur), ''), nullif(trim(p_observations), ''), coalesce(p_partiel, false), auth.uid(), v_nom)
      returning * into v;
  end if;
  perform public.inventaire_ecrire_lignes(v.id, v_depot, p_lignes, true);
  for li in select * from inventaire_lignes where inventaire_id = v.id and ecart <> 0 loop
    perform public.stock_mouvement(li.composant_id, 'inventaire', li.quantite_comptee,
      left('Inventaire ' || v.code || ' — ' || public.inventaire_motif_libelle(li.motif) || coalesce(' : ' || li.justification, ''), 500), v.code, null, v_depot);
  end loop;
  update inventaires set nb_articles_depot = (select count(*) from composants) where id = v.id;
  perform public.inventaire_totaux(v.id);
  select * into v from inventaires where id = v.id;
  return v;
end $$;
revoke all on function public.inventaire_valider(uuid, date, text, text, text, jsonb, uuid, boolean) from public, anon;
grant execute on function public.inventaire_valider(uuid, date, text, text, text, jsonb, uuid, boolean) to authenticated;

create or replace function public.inventaire_supprimer_brouillon(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  delete from inventaires where id = p_id and statut = 'brouillon';
  if not found then raise exception 'Brouillon introuvable ou déjà validé'; end if;
end $$;
revoke all on function public.inventaire_supprimer_brouillon(uuid) from public, anon;
grant execute on function public.inventaire_supprimer_brouillon(uuid) to authenticated;

-- Ajustements « inventaire » passés hors registre (sans référence) : à régulariser
create or replace function public.inventaire_hors_registre()
returns table (depot_id uuid, depot_nom text, jour date, nb bigint, premiere timestamptz, derniere timestamptz)
language sql stable security definer set search_path = public as $$
  select m.depot_id, d.nom, (m.created_at at time zone 'UTC')::date, count(*), min(m.created_at), max(m.created_at)
    from mouvements_stock m left join depots d on d.id = m.depot_id
   where m.type = 'inventaire' and m.reference is null and public.est_utilisateur_autorise()
   group by 1, 2, 3 order by 3 desc, 2;
$$;
revoke all on function public.inventaire_hors_registre() from public, anon;
grant execute on function public.inventaire_hors_registre() to authenticated;

-- Crée l'inventaire enregistré correspondant (sans retoucher le stock) et y rattache les mouvements
create or replace function public.inventaire_regulariser(p_depot uuid, p_debut date, p_fin date, p_motif text, p_justification text)
returns public.inventaires language plpgsql security definer set search_path = public as $$
declare v public.inventaires; v_nom text := public.inventaire_nom_utilisateur(); n int;
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  if coalesce(trim(p_motif), '') = '' or public.inventaire_motif_libelle(p_motif) = p_motif then raise exception 'Motif invalide'; end if;
  if p_motif = 'autre' and coalesce(trim(p_justification), '') = '' then raise exception 'Précisez la justification'; end if;
  select count(*) into n from mouvements_stock m where m.type = 'inventaire' and m.reference is null and m.depot_id is not distinct from p_depot
    and (m.created_at at time zone 'UTC')::date between p_debut and p_fin;
  if n = 0 then raise exception 'Aucun ajustement hors registre sur cette période'; end if;
  insert into inventaires (code, statut, depot_id, depot_nom, date_inventaire, observations, partiel, regularisation, valide_par, valide_par_nom)
    values (public.inventaire_prochain_code(p_fin), 'valide', p_depot, (select nom from depots where id = p_depot), p_fin,
      'Régularisation de ' || n || ' ajustement(s) d''inventaire saisis hors registre entre le ' || to_char(p_debut, 'DD/MM/YYYY') || ' et le ' || to_char(p_fin, 'DD/MM/YYYY') || '.',
      true, true, auth.uid(), v_nom)
    returning * into v;
  insert into inventaire_lignes (inventaire_id, composant_id, code_article, designation, famille, unite, emplacement,
      stock_systeme, quantite_comptee, ecart, cmup, valeur_ecart, motif, justification, justifie_par, justifie_le)
    select v.id, c.id, coalesce(c.code, c.reference), c.nom, c.famille, c.unite, c.emplacement,
      a.compte - a.ecart, a.compte, a.ecart, coalesce(nullif(c.cmup, 0), c.prix_unitaire, 0),
      round(a.ecart * coalesce(nullif(c.cmup, 0), c.prix_unitaire, 0), 2),
      case when a.ecart <> 0 then p_motif end, case when a.ecart <> 0 then nullif(trim(p_justification), '') end,
      case when a.ecart <> 0 then v_nom end, case when a.ecart <> 0 then now() end
    from (select m.composant_id, sum(m.quantite) ecart,
                 (array_agg(m.stock_depot_apres order by m.created_at desc))[1] compte
            from mouvements_stock m
           where m.type = 'inventaire' and m.reference is null and m.depot_id is not distinct from p_depot
             and (m.created_at at time zone 'UTC')::date between p_debut and p_fin
           group by m.composant_id) a
    join composants c on c.id = a.composant_id;
  update mouvements_stock set reference = v.code
   where type = 'inventaire' and reference is null and depot_id is not distinct from p_depot
     and (created_at at time zone 'UTC')::date between p_debut and p_fin;
  perform public.inventaire_totaux(v.id);
  select * into v from inventaires where id = v.id;
  return v;
end $$;
revoke all on function public.inventaire_regulariser(uuid, date, date, text, text) from public, anon;
grant execute on function public.inventaire_regulariser(uuid, date, date, text, text) to authenticated;
