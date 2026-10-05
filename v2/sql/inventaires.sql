-- ============================================================================
-- Sanix AluExpert ERP — Inventaires physiques : état d'inventaire et justification des écarts
-- ============================================================================
-- Un inventaire est une SESSION numérotée (INV-AAAA-NNNN) portant sur un dépôt à une date :
--   • chaque article compté est figé dans inventaire_lignes (stock système au moment de la
--     validation, quantité comptée, écart, CMUP, valeur de l'écart) ;
--   • tout écart doit être JUSTIFIÉ (motif normalisé + commentaire, commentaire obligatoire pour
--     « autre ») — la validation est refusée sinon ;
--   • la validation est atomique : lignes + mouvements de stock « inventaire » (référence = code
--     de l'inventaire) dans la même transaction ;
--   • l'état d'inventaire (synthèse par famille et par motif, valeurs théorique / réelle / écarts)
--     s'imprime depuis Stock → États d'inventaire ; un administrateur / manager peut compléter
--     ou corriger une justification après coup (traçée : qui, quand).
-- Comptabilité : inventaire intermittent SYSCOHADA — la valeur réelle des stocks est reprise à la
-- clôture (variation des stocks, journal INV) ; aucun écart n'est comptabilisé ligne à ligne ici.
-- ============================================================================
create table if not exists public.inventaires (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  depot_id uuid references public.depots(id) on delete restrict,
  depot_nom text,
  date_inventaire date not null default current_date,
  responsable text,
  controleur text,
  observations text,
  nb_articles integer not null default 0,
  nb_ecarts integer not null default 0,
  valeur_theorique numeric(16,2) not null default 0,
  valeur_reelle numeric(16,2) not null default 0,
  ecart_positif numeric(16,2) not null default 0,
  ecart_negatif numeric(16,2) not null default 0,
  valide_par uuid default auth.uid(),
  valide_par_nom text,
  created_at timestamptz not null default now()
);
create index if not exists idx_inventaires_date on public.inventaires (date_inventaire desc, created_at desc);

create table if not exists public.inventaire_lignes (
  id uuid primary key default gen_random_uuid(),
  inventaire_id uuid not null references public.inventaires(id) on delete cascade,
  composant_id uuid references public.composants(id) on delete set null,
  code_article text,
  designation text not null,
  famille text,
  unite text,
  emplacement text,
  stock_systeme numeric not null default 0,
  quantite_comptee numeric not null default 0,
  ecart numeric not null default 0,
  cmup numeric not null default 0,
  valeur_ecart numeric(16,2) not null default 0,
  motif text,
  justification text,
  justifie_par text,
  justifie_le timestamptz
);
create index if not exists idx_inventaire_lignes_inv on public.inventaire_lignes (inventaire_id);

alter table public.inventaires enable row level security;
alter table public.inventaire_lignes enable row level security;
drop policy if exists "inventaires_lecture" on public.inventaires;
create policy "inventaires_lecture" on public.inventaires for select to authenticated using (public.est_utilisateur_autorise());
drop policy if exists "inventaire_lignes_lecture" on public.inventaire_lignes;
create policy "inventaire_lignes_lecture" on public.inventaire_lignes for select to authenticated using (public.est_utilisateur_autorise());
-- Pas d'écriture directe : validation et justification passent par les fonctions ci-dessous

-- Motifs normalisés de justification des écarts (mêmes codes que l'application)
create or replace function public.inventaire_motif_libelle(p_motif text) returns text
language sql immutable as $$
  select case p_motif
    when 'casse' then 'Casse / détérioration' when 'vol' then 'Vol' when 'perte' then 'Perte / disparition'
    when 'peremption' then 'Péremption' when 'chute_decoupe' then 'Chutes de découpe non déclarées'
    when 'consommation_non_saisie' then 'Consommation chantier / atelier non saisie'
    when 'reception_non_saisie' then 'Réception fournisseur non saisie' when 'sortie_non_saisie' then 'Sortie / livraison non saisie'
    when 'transfert_non_saisi' then 'Transfert entre dépôts non saisi' when 'erreur_saisie' then 'Erreur de saisie antérieure'
    when 'erreur_comptage' then 'Erreur de comptage (inventaire précédent)' when 'erreur_unite' then 'Erreur d''unité / de conditionnement'
    when 'autre' then 'Autre' else p_motif end;
$$;

-- Valide un inventaire. p_lignes = [{composant_id, quantite_comptee, motif, justification}, …]
create or replace function public.inventaire_valider(p_depot uuid, p_date date, p_responsable text, p_controleur text,
  p_observations text, p_lignes jsonb)
returns public.inventaires
language plpgsql security definer set search_path = public as $$
declare
  v public.inventaires; l jsonb; c public.composants; v_sys numeric; v_cpt numeric; v_ecart numeric; v_cmup numeric;
  v_motif text; v_just text; v_num int; v_an text; v_nom text; v_depot uuid;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  v_depot := coalesce(p_depot, (select id from depots where est_principal limit 1));
  if v_depot is null then raise exception 'Dépôt introuvable'; end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'Aucun article compté'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'Date d''inventaire dans le futur'; end if;
  v_an := to_char(coalesce(p_date, current_date), 'YYYY');
  perform pg_advisory_xact_lock(hashtext('inventaire:' || v_an));
  select coalesce(max(nullif(split_part(code, '-', 3), '')::int), 0) + 1 into v_num from inventaires where code like 'INV-' || v_an || '-%';
  select coalesce(nullif(p.nom_complet, ''), u.email) into v_nom from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid();

  insert into inventaires (code, depot_id, depot_nom, date_inventaire, responsable, controleur, observations, valide_par, valide_par_nom)
    values ('INV-' || v_an || '-' || lpad(v_num::text, 4, '0'), v_depot, (select nom from depots where id = v_depot),
            coalesce(p_date, current_date), nullif(trim(p_responsable), ''), nullif(trim(p_controleur), ''), nullif(trim(p_observations), ''), auth.uid(), v_nom)
    returning * into v;

  for l in select * from jsonb_array_elements(p_lignes) loop
    select * into c from composants where id = (l->>'composant_id')::uuid;
    if c.id is null then raise exception 'Article introuvable dans l''inventaire'; end if;
    v_cpt := (l->>'quantite_comptee')::numeric;
    if v_cpt is null or v_cpt < 0 then raise exception 'Quantité comptée invalide pour « % »', c.nom; end if;
    select coalesce((select quantite from stocks_depot where depot_id = v_depot and composant_id = c.id), 0) into v_sys;
    v_ecart := v_cpt - v_sys;
    v_motif := nullif(trim(l->>'motif'), ''); v_just := nullif(trim(l->>'justification'), '');
    if abs(v_ecart) > 0.0001 then
      if v_motif is not null and public.inventaire_motif_libelle(v_motif) = v_motif then raise exception 'Motif d''écart inconnu : %', v_motif; end if;
      if v_motif is null then raise exception 'Écart non justifié : « % » (% → %). Choisissez un motif.', c.nom, v_sys, v_cpt; end if;
      if v_motif = 'autre' and v_just is null then raise exception 'Motif « Autre » : précisez la justification de l''écart sur « % »', c.nom; end if;
    else
      v_ecart := 0; v_motif := null; v_just := null;
    end if;
    v_cmup := coalesce(nullif(c.cmup, 0), c.prix_unitaire, 0);
    insert into inventaire_lignes (inventaire_id, composant_id, code_article, designation, famille, unite, emplacement,
      stock_systeme, quantite_comptee, ecart, cmup, valeur_ecart, motif, justification, justifie_par, justifie_le)
      values (v.id, c.id, coalesce(c.code, c.reference), c.nom, c.famille, c.unite, c.emplacement,
        v_sys, v_cpt, v_ecart, v_cmup, round(v_ecart * v_cmup, 2), v_motif, v_just,
        case when v_motif is not null then v_nom end, case when v_motif is not null then now() end);
    if v_ecart <> 0 then
      perform public.stock_mouvement(c.id, 'inventaire', v_cpt,
        left('Inventaire ' || v.code || ' — ' || public.inventaire_motif_libelle(v_motif) || coalesce(' : ' || v_just, ''), 500), v.code, null, v_depot);
    end if;
  end loop;

  update inventaires i set
    nb_articles = s.n, nb_ecarts = s.ne,
    valeur_theorique = s.vt, valeur_reelle = s.vr, ecart_positif = s.ep, ecart_negatif = s.en
  from (select count(*) n, count(*) filter (where ecart <> 0) ne,
          coalesce(sum(round(stock_systeme * cmup, 2)), 0) vt, coalesce(sum(round(quantite_comptee * cmup, 2)), 0) vr,
          coalesce(sum(valeur_ecart) filter (where valeur_ecart > 0), 0) ep, coalesce(sum(valeur_ecart) filter (where valeur_ecart < 0), 0) en
        from inventaire_lignes where inventaire_id = v.id) s
  where i.id = v.id returning i.* into v;
  return v;
end $$;
revoke all on function public.inventaire_valider(uuid, date, text, text, text, jsonb) from public, anon;
grant execute on function public.inventaire_valider(uuid, date, text, text, text, jsonb) to authenticated;

-- Complète / corrige la justification d'un écart après validation (administrateur / manager)
create or replace function public.inventaire_justifier(p_ligne uuid, p_motif text, p_justification text)
returns public.inventaire_lignes
language plpgsql security definer set search_path = public as $$
declare v public.inventaire_lignes;
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'Motif obligatoire'; end if;
  if p_motif = 'autre' and coalesce(trim(p_justification), '') = '' then raise exception 'Précisez la justification'; end if;
  update inventaire_lignes set motif = trim(p_motif), justification = nullif(trim(p_justification), ''),
    justifie_par = (select coalesce(nullif(p.nom_complet, ''), u.email) from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid()),
    justifie_le = now()
    where id = p_ligne and ecart <> 0 returning * into v;
  if v.id is null then raise exception 'Ligne introuvable ou sans écart'; end if;
  return v;
end $$;
revoke all on function public.inventaire_justifier(uuid, text, text) from public, anon;
grant execute on function public.inventaire_justifier(uuid, text, text) to authenticated;
