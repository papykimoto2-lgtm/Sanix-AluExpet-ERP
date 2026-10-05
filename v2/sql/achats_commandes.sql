-- ============================================================================
-- Sanix AluExpert ERP — Achats & approvisionnement
--   • Bons de commande FOURNISSEUR (BC-AAAA-NNNN) : brouillon → envoyée → partiellement reçue → reçue / soldée
--   • Réceptions fournisseur (BR-AAAA-NNNN), avec ou sans commande : chaque réception INCRÉMENTE le stock du
--     dépôt de livraison (mouvement « entrée » au prix d'achat → CMUP recalculé), réceptions partielles suivies
--   • Commandes INTERNES (CI-AAAA-NNNN) : un dépôt / magasin / chantier demande des articles à un autre dépôt ;
--     validation par un responsable, puis service par TRANSFERT de stock (sortie du dépôt fournisseur, entrée au
--     dépôt demandeur à la réception — immédiate ou différée via Stock → Transferts)
-- Toutes les écritures passent par des fonctions serveur (transactions atomiques, contrôles, numérotation).
-- ============================================================================
create table if not exists public.commandes_fournisseur (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  fournisseur_id uuid not null references public.fournisseurs(id) on delete restrict,
  depot_id uuid not null references public.depots(id) on delete restrict,
  projet_id uuid references public.projets(id) on delete set null,
  statut text not null default 'brouillon' check (statut in ('brouillon','envoyee','partielle','recue','soldee','annulee')),
  date_commande date not null default current_date,
  date_livraison_prevue date,
  reference_fournisseur text,
  conditions text,
  notes text,
  frais numeric(14,2) not null default 0,
  tva_pct numeric(5,2) not null default 0,
  total_ht numeric(16,2) not null default 0,
  total_ttc numeric(16,2) not null default 0,
  cree_par uuid default auth.uid(),
  cree_par_nom text,
  envoyee_le timestamptz,
  motif_annulation text,
  cloturee_le timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.commandes_fournisseur_lignes (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references public.commandes_fournisseur(id) on delete cascade,
  composant_id uuid not null references public.composants(id) on delete restrict,
  designation text not null,
  unite text,
  quantite numeric not null check (quantite > 0),
  prix_unitaire numeric not null default 0 check (prix_unitaire >= 0),
  remise_pct numeric not null default 0 check (remise_pct >= 0 and remise_pct <= 100),
  montant numeric(16,2) not null default 0,
  quantite_recue numeric not null default 0,
  ordre integer not null default 0
);
create index if not exists idx_cf_lignes on public.commandes_fournisseur_lignes (commande_id);

create table if not exists public.receptions_fournisseur (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  commande_id uuid references public.commandes_fournisseur(id) on delete restrict,
  fournisseur_id uuid not null references public.fournisseurs(id) on delete restrict,
  depot_id uuid not null references public.depots(id) on delete restrict,
  projet_id uuid references public.projets(id) on delete set null,
  date_reception date not null default current_date,
  bl_fournisseur text,
  facture_fournisseur text,
  notes text,
  montant_ht numeric(16,2) not null default 0,
  comptabilise boolean not null default false,
  recu_par uuid default auth.uid(),
  recu_par_nom text,
  created_at timestamptz not null default now()
);
create table if not exists public.receptions_fournisseur_lignes (
  id uuid primary key default gen_random_uuid(),
  reception_id uuid not null references public.receptions_fournisseur(id) on delete cascade,
  commande_ligne_id uuid references public.commandes_fournisseur_lignes(id) on delete set null,
  composant_id uuid not null references public.composants(id) on delete restrict,
  designation text not null,
  unite text,
  quantite numeric not null check (quantite > 0),
  prix_unitaire numeric not null default 0,
  montant numeric(16,2) not null default 0
);
create index if not exists idx_rf_lignes on public.receptions_fournisseur_lignes (reception_id);

create table if not exists public.commandes_internes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  depot_demandeur_id uuid not null references public.depots(id) on delete restrict,
  depot_fournisseur_id uuid not null references public.depots(id) on delete restrict,
  projet_id uuid references public.projets(id) on delete set null,
  statut text not null default 'brouillon' check (statut in ('brouillon','soumise','validee','servie_partielle','servie','refusee','annulee')),
  date_besoin date,
  motif text,
  demande_par uuid default auth.uid(),
  demande_par_nom text,
  decide_par_nom text,
  decide_le timestamptz,
  motif_refus text,
  created_at timestamptz not null default now(),
  constraint commandes_internes_depots check (depot_demandeur_id <> depot_fournisseur_id)
);
create table if not exists public.commandes_internes_lignes (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references public.commandes_internes(id) on delete cascade,
  composant_id uuid not null references public.composants(id) on delete restrict,
  quantite_demandee numeric not null check (quantite_demandee > 0),
  quantite_servie numeric not null default 0,
  ordre integer not null default 0
);
create index if not exists idx_ci_lignes on public.commandes_internes_lignes (commande_id);
alter table public.transferts_stock add column if not exists commande_interne_id uuid references public.commandes_internes(id) on delete set null;

do $$ declare t text; begin
  foreach t in array array['commandes_fournisseur','commandes_fournisseur_lignes','receptions_fournisseur','receptions_fournisseur_lignes','commandes_internes','commandes_internes_lignes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s_lecture" on public.%I', t, t);
    execute format('create policy "%s_lecture" on public.%I for select to authenticated using (public.est_utilisateur_autorise())', t, t);
  end loop;
end $$;
-- Pas d'écriture directe : tout passe par les fonctions ci-dessous

create or replace function public.achat_numero(p_prefixe text, p_table text, p_date date) returns text
language plpgsql security definer set search_path = public as $$
declare v_an text := to_char(coalesce(p_date, current_date), 'YYYY'); n int;
begin
  perform pg_advisory_xact_lock(hashtext('achat_numero:' || p_prefixe || v_an));
  execute format('select coalesce(max(nullif(split_part(code, ''-'', 3), '''')::int), 0) + 1 from public.%I where code like $1', p_table)
    into n using p_prefixe || '-' || v_an || '-%';
  return p_prefixe || '-' || v_an || '-' || lpad(n::text, 4, '0');
end $$;
revoke all on function public.achat_numero(text, text, date) from public, anon, authenticated;

create or replace function public.achat_utilisateur() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.nom_complet, ''), u.email) from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid();
$$;
revoke all on function public.achat_utilisateur() from public, anon;

-- ---------- Commandes fournisseur ----------
create or replace function public.commande_fournisseur_enregistrer(p_id uuid, p_entete jsonb, p_lignes jsonb)
returns public.commandes_fournisseur language plpgsql security definer set search_path = public as $$
declare v public.commandes_fournisseur; l jsonb; c public.composants; i int := 0; v_ht numeric; v_q numeric; v_pu numeric; v_rem numeric;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if (p_entete->>'fournisseur_id') is null then raise exception 'Choisissez le fournisseur'; end if;
  if (p_entete->>'depot_id') is null then raise exception 'Choisissez le dépôt de livraison'; end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'Ajoutez au moins un article'; end if;
  if p_id is not null then
    select * into v from commandes_fournisseur where id = p_id for update;
    if v.id is null then raise exception 'Commande introuvable'; end if;
    if v.statut <> 'brouillon' then raise exception 'Seule une commande en brouillon est modifiable (%)', v.code; end if;
  else
    insert into commandes_fournisseur (code, fournisseur_id, depot_id, cree_par_nom)
      values (public.achat_numero('BC', 'commandes_fournisseur', (p_entete->>'date_commande')::date), (p_entete->>'fournisseur_id')::uuid, (p_entete->>'depot_id')::uuid, public.achat_utilisateur())
      returning * into v;
  end if;
  update commandes_fournisseur set
    fournisseur_id = (p_entete->>'fournisseur_id')::uuid, depot_id = (p_entete->>'depot_id')::uuid,
    projet_id = nullif(p_entete->>'projet_id', '')::uuid,
    date_commande = coalesce((p_entete->>'date_commande')::date, current_date),
    date_livraison_prevue = nullif(p_entete->>'date_livraison_prevue', '')::date,
    reference_fournisseur = nullif(trim(p_entete->>'reference_fournisseur'), ''), conditions = nullif(trim(p_entete->>'conditions'), ''),
    notes = nullif(trim(p_entete->>'notes'), ''), frais = coalesce((p_entete->>'frais')::numeric, 0), tva_pct = coalesce((p_entete->>'tva_pct')::numeric, 0)
    where id = v.id;
  delete from commandes_fournisseur_lignes where commande_id = v.id;
  for l in select * from jsonb_array_elements(p_lignes) loop
    select * into c from composants where id = (l->>'composant_id')::uuid;
    if c.id is null then raise exception 'Article introuvable'; end if;
    v_q := (l->>'quantite')::numeric; v_pu := coalesce((l->>'prix_unitaire')::numeric, 0); v_rem := coalesce((l->>'remise_pct')::numeric, 0);
    if v_q is null or v_q <= 0 then raise exception 'Quantité invalide pour « % »', c.nom; end if;
    i := i + 1;
    insert into commandes_fournisseur_lignes (commande_id, composant_id, designation, unite, quantite, prix_unitaire, remise_pct, montant, ordre)
      values (v.id, c.id, coalesce(nullif(trim(l->>'designation'), ''), c.nom), c.unite, v_q, v_pu, v_rem, round(v_q * v_pu * (1 - v_rem / 100), 2), i);
  end loop;
  select coalesce(sum(montant), 0) into v_ht from commandes_fournisseur_lignes where commande_id = v.id;
  update commandes_fournisseur set total_ht = v_ht + frais, total_ttc = round((v_ht + frais) * (1 + tva_pct / 100), 2) where id = v.id returning * into v;
  return v;
end $$;
revoke all on function public.commande_fournisseur_enregistrer(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.commande_fournisseur_enregistrer(uuid, jsonb, jsonb) to authenticated;

-- Actions : envoyer (brouillon → envoyée), annuler (sans réception), solder (clôture du reste non livré)
create or replace function public.commande_fournisseur_action(p_id uuid, p_action text, p_motif text default null)
returns public.commandes_fournisseur language plpgsql security definer set search_path = public as $$
declare v public.commandes_fournisseur; n int;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  select * into v from commandes_fournisseur where id = p_id for update;
  if v.id is null then raise exception 'Commande introuvable'; end if;
  if p_action = 'envoyer' then
    if v.statut <> 'brouillon' then raise exception 'Commande déjà envoyée (%)', v.code; end if;
    update commandes_fournisseur set statut = 'envoyee', envoyee_le = now() where id = v.id returning * into v;
  elsif p_action = 'annuler' then
    select count(*) into n from receptions_fournisseur where commande_id = v.id;
    if n > 0 then raise exception 'Commande déjà (partiellement) reçue : utilisez « Solder » pour abandonner le reste'; end if;
    if v.statut in ('annulee','recue','soldee') then raise exception 'Cette commande ne peut plus être annulée'; end if;
    if coalesce(trim(p_motif), '') = '' then raise exception 'Motif d''annulation obligatoire'; end if;
    update commandes_fournisseur set statut = 'annulee', motif_annulation = trim(p_motif) where id = v.id returning * into v;
  elsif p_action = 'solder' then
    if v.statut not in ('envoyee','partielle') then raise exception 'Seule une commande envoyée ou partiellement reçue peut être soldée'; end if;
    update commandes_fournisseur set statut = 'soldee', cloturee_le = now(), motif_annulation = nullif(trim(p_motif), '') where id = v.id returning * into v;
  elsif p_action = 'rouvrir' then
    if v.statut <> 'envoyee' then raise exception 'Seule une commande envoyée sans réception peut repasser en brouillon'; end if;
    select count(*) into n from receptions_fournisseur where commande_id = v.id;
    if n > 0 then raise exception 'Commande déjà reçue en partie'; end if;
    update commandes_fournisseur set statut = 'brouillon', envoyee_le = null where id = v.id returning * into v;
  else raise exception 'Action inconnue : %', p_action; end if;
  return v;
end $$;
revoke all on function public.commande_fournisseur_action(uuid, text, text) from public, anon;
grant execute on function public.commande_fournisseur_action(uuid, text, text) to authenticated;

-- Réception : incrémente le stock du dépôt (mouvement « entrée » au prix d'achat → CMUP), suit les quantités reçues
-- p_lignes = [{commande_ligne_id?, composant_id, quantite, prix_unitaire}]
create or replace function public.reception_fournisseur_enregistrer(p_commande uuid, p_fournisseur uuid, p_depot uuid, p_date date,
  p_bl text, p_facture text, p_notes text, p_lignes jsonb, p_projet uuid default null)
returns public.receptions_fournisseur language plpgsql security definer set search_path = public as $$
declare v public.receptions_fournisseur; cf public.commandes_fournisseur; cl public.commandes_fournisseur_lignes; c public.composants; l jsonb;
  v_q numeric; v_pu numeric; v_fourn uuid; v_depot uuid; v_projet uuid; v_nom_f text; n int := 0; v_reste numeric; v_tot numeric;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'Aucun article reçu'; end if;
  if coalesce(p_date, current_date) > current_date then raise exception 'Date de réception dans le futur'; end if;
  if p_commande is not null then
    select * into cf from commandes_fournisseur where id = p_commande for update;
    if cf.id is null then raise exception 'Commande introuvable'; end if;
    if cf.statut not in ('envoyee','partielle','brouillon') then raise exception 'La commande % est %: réception impossible', cf.code, cf.statut; end if;
    v_fourn := cf.fournisseur_id; v_depot := coalesce(p_depot, cf.depot_id); v_projet := coalesce(p_projet, cf.projet_id);
  else
    v_fourn := p_fournisseur; v_depot := p_depot; v_projet := p_projet;
    if v_fourn is null then raise exception 'Choisissez le fournisseur'; end if;
  end if;
  if v_depot is null then raise exception 'Choisissez le dépôt de réception'; end if;
  select nom into v_nom_f from fournisseurs where id = v_fourn;
  insert into receptions_fournisseur (code, commande_id, fournisseur_id, depot_id, projet_id, date_reception, bl_fournisseur, facture_fournisseur, notes, recu_par_nom)
    values (public.achat_numero('BR', 'receptions_fournisseur', p_date), p_commande, v_fourn, v_depot, v_projet, coalesce(p_date, current_date),
      nullif(trim(p_bl), ''), nullif(trim(p_facture), ''), nullif(trim(p_notes), ''), public.achat_utilisateur())
    returning * into v;
  for l in select * from jsonb_array_elements(p_lignes) loop
    v_q := (l->>'quantite')::numeric;
    if v_q is null or v_q = 0 then continue; end if;
    if v_q < 0 then raise exception 'Quantité reçue négative'; end if;
    cl := null;
    if nullif(l->>'commande_ligne_id', '') is not null then
      select * into cl from commandes_fournisseur_lignes where id = (l->>'commande_ligne_id')::uuid and commande_id = p_commande for update;
      if cl.id is null then raise exception 'Ligne de commande introuvable'; end if;
      v_reste := cl.quantite - cl.quantite_recue;
      if v_q > v_reste + 0.0001 then raise exception 'Quantité reçue supérieure au reste à recevoir pour « % » : reste %, reçu %', cl.designation, v_reste, v_q; end if;
    end if;
    select * into c from composants where id = coalesce(cl.composant_id, (l->>'composant_id')::uuid);
    if c.id is null then raise exception 'Article introuvable'; end if;
    v_pu := coalesce((l->>'prix_unitaire')::numeric, case when cl.id is not null then cl.prix_unitaire * (1 - cl.remise_pct / 100) end, c.prix_unitaire, 0);
    insert into receptions_fournisseur_lignes (reception_id, commande_ligne_id, composant_id, designation, unite, quantite, prix_unitaire, montant)
      values (v.id, cl.id, c.id, coalesce(cl.designation, c.nom), c.unite, v_q, v_pu, round(v_q * v_pu, 2));
    perform public.stock_mouvement(c.id, 'entree', v_q,
      left('Réception ' || v.code || coalesce(' / ' || cf.code, '') || ' — ' || coalesce(v_nom_f, 'fournisseur'), 500),
      v.code, v_pu, v_depot, null, v_projet);
    if cl.id is not null then update commandes_fournisseur_lignes set quantite_recue = quantite_recue + v_q where id = cl.id; end if;
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Aucune quantité reçue'; end if;
  select coalesce(sum(montant), 0) into v_tot from receptions_fournisseur_lignes where reception_id = v.id;
  update receptions_fournisseur set montant_ht = v_tot where id = v.id returning * into v;
  if p_commande is not null then
    update commandes_fournisseur set statut = case
        when not exists (select 1 from commandes_fournisseur_lignes where commande_id = p_commande and quantite_recue < quantite - 0.0001) then 'recue'
        else 'partielle' end,
      envoyee_le = coalesce(envoyee_le, now())
      where id = p_commande;
  end if;
  return v;
end $$;
revoke all on function public.reception_fournisseur_enregistrer(uuid, uuid, uuid, date, text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.reception_fournisseur_enregistrer(uuid, uuid, uuid, date, text, text, text, jsonb, uuid) to authenticated;

create or replace function public.reception_marquer_comptabilisee(p_id uuid) returns void
language sql security definer set search_path = public as $$
  update receptions_fournisseur set comptabilise = true where id = p_id and public.est_utilisateur_autorise();
$$;
revoke all on function public.reception_marquer_comptabilisee(uuid) from public, anon;
grant execute on function public.reception_marquer_comptabilisee(uuid) to authenticated;

-- ---------- Commandes internes ----------
create or replace function public.commande_interne_enregistrer(p_id uuid, p_entete jsonb, p_lignes jsonb, p_soumettre boolean default false)
returns public.commandes_internes language plpgsql security definer set search_path = public as $$
declare v public.commandes_internes; l jsonb; i int := 0;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if (p_entete->>'depot_demandeur_id') is null or (p_entete->>'depot_fournisseur_id') is null then raise exception 'Choisissez les deux dépôts'; end if;
  if p_entete->>'depot_demandeur_id' = p_entete->>'depot_fournisseur_id' then raise exception 'Le dépôt demandeur et le dépôt fournisseur doivent être différents'; end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'Ajoutez au moins un article'; end if;
  if p_id is not null then
    select * into v from commandes_internes where id = p_id for update;
    if v.id is null then raise exception 'Commande interne introuvable'; end if;
    if v.statut <> 'brouillon' then raise exception 'Seule une commande interne en brouillon est modifiable (%)', v.code; end if;
  else
    insert into commandes_internes (code, depot_demandeur_id, depot_fournisseur_id, demande_par_nom)
      values (public.achat_numero('CI', 'commandes_internes', current_date), (p_entete->>'depot_demandeur_id')::uuid, (p_entete->>'depot_fournisseur_id')::uuid, public.achat_utilisateur())
      returning * into v;
  end if;
  update commandes_internes set depot_demandeur_id = (p_entete->>'depot_demandeur_id')::uuid, depot_fournisseur_id = (p_entete->>'depot_fournisseur_id')::uuid,
    projet_id = nullif(p_entete->>'projet_id', '')::uuid, date_besoin = nullif(p_entete->>'date_besoin', '')::date, motif = nullif(trim(p_entete->>'motif'), ''),
    statut = case when p_soumettre then 'soumise' else 'brouillon' end
    where id = v.id;
  delete from commandes_internes_lignes where commande_id = v.id;
  for l in select * from jsonb_array_elements(p_lignes) loop
    if (l->>'quantite')::numeric is null or (l->>'quantite')::numeric <= 0 then raise exception 'Quantité demandée invalide'; end if;
    i := i + 1;
    insert into commandes_internes_lignes (commande_id, composant_id, quantite_demandee, ordre) values (v.id, (l->>'composant_id')::uuid, (l->>'quantite')::numeric, i);
  end loop;
  select * into v from commandes_internes where id = v.id;
  return v;
end $$;
revoke all on function public.commande_interne_enregistrer(uuid, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.commande_interne_enregistrer(uuid, jsonb, jsonb, boolean) to authenticated;

-- valider / refuser : administrateur ou manager ; annuler : tant que rien n'est servi ; rouvrir : soumise → brouillon
create or replace function public.commande_interne_action(p_id uuid, p_action text, p_motif text default null)
returns public.commandes_internes language plpgsql security definer set search_path = public as $$
declare v public.commandes_internes;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  select * into v from commandes_internes where id = p_id for update;
  if v.id is null then raise exception 'Commande interne introuvable'; end if;
  if p_action in ('valider','refuser') and not public.est_gestionnaire_caisse() then raise exception 'Validation réservée aux administrateurs et managers'; end if;
  if p_action = 'soumettre' and v.statut = 'brouillon' then
    update commandes_internes set statut = 'soumise' where id = v.id returning * into v;
  elsif p_action = 'valider' and v.statut = 'soumise' then
    update commandes_internes set statut = 'validee', decide_par_nom = public.achat_utilisateur(), decide_le = now() where id = v.id returning * into v;
  elsif p_action = 'refuser' and v.statut = 'soumise' then
    if coalesce(trim(p_motif), '') = '' then raise exception 'Motif du refus obligatoire'; end if;
    update commandes_internes set statut = 'refusee', decide_par_nom = public.achat_utilisateur(), decide_le = now(), motif_refus = trim(p_motif) where id = v.id returning * into v;
  elsif p_action = 'annuler' and v.statut in ('brouillon','soumise','validee') then
    update commandes_internes set statut = 'annulee', motif_refus = nullif(trim(p_motif), '') where id = v.id returning * into v;
  elsif p_action = 'solder' and v.statut = 'servie_partielle' then
    update commandes_internes set statut = 'servie', motif_refus = coalesce(nullif(trim(p_motif), ''), 'Reste non servi abandonné') where id = v.id returning * into v;
  elsif p_action = 'rouvrir' and v.statut = 'soumise' then
    update commandes_internes set statut = 'brouillon' where id = v.id returning * into v;
  else raise exception 'Action « % » impossible sur une commande %', p_action, v.statut; end if;
  return v;
end $$;
revoke all on function public.commande_interne_action(uuid, text, text) from public, anon;
grant execute on function public.commande_interne_action(uuid, text, text) to authenticated;

-- Service : crée le transfert (dépôt fournisseur → dépôt demandeur), l'expédie (sortie du stock fournisseur) et,
-- si demandé, le réceptionne aussitôt (entrée au dépôt demandeur). p_lignes = [{ligne_id, quantite}]
create or replace function public.commande_interne_servir(p_id uuid, p_lignes jsonb, p_reception_immediate boolean default false)
returns public.transferts_stock language plpgsql security definer set search_path = public as $$
declare v public.commandes_internes; cl public.commandes_internes_lignes; l jsonb; t public.transferts_stock; v_q numeric; i int := 0; v_nom text := public.achat_utilisateur();
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  select * into v from commandes_internes where id = p_id for update;
  if v.id is null then raise exception 'Commande interne introuvable'; end if;
  if v.statut not in ('validee','servie_partielle') then raise exception 'La commande % doit être validée avant d''être servie (statut : %)', v.code, v.statut; end if;
  insert into transferts_stock (depot_source_id, depot_destination_id, motif, created_by, commande_interne_id)
    values (v.depot_fournisseur_id, v.depot_demandeur_id, 'Commande interne ' || v.code || coalesce(' — ' || v.motif, ''), auth.uid(), v.id)
    returning * into t;
  for l in select * from jsonb_array_elements(coalesce(p_lignes, '[]'::jsonb)) loop
    v_q := (l->>'quantite')::numeric;
    if v_q is null or v_q = 0 then continue; end if;
    if v_q < 0 then raise exception 'Quantité servie négative'; end if;
    select * into cl from commandes_internes_lignes where id = (l->>'ligne_id')::uuid and commande_id = v.id for update;
    if cl.id is null then raise exception 'Ligne de commande interne introuvable'; end if;
    if v_q > cl.quantite_demandee - cl.quantite_servie + 0.0001 then raise exception 'Quantité servie supérieure au reste demandé'; end if;
    i := i + 1;
    insert into transferts_stock_lignes (transfert_id, composant_id, quantite_envoyee, ordre) values (t.id, cl.composant_id, v_q, i);
    update commandes_internes_lignes set quantite_servie = quantite_servie + v_q where id = cl.id;
  end loop;
  if i = 0 then raise exception 'Aucune quantité à servir'; end if;
  select * into t from public.transfert_expedier(t.id, v_nom);
  if p_reception_immediate then select * into t from public.transfert_receptionner(t.id, '[]'::jsonb, 'Réception immédiate — commande interne ' || v.code, v_nom); end if;
  update commandes_internes set statut = case
      when not exists (select 1 from commandes_internes_lignes where commande_id = v.id and quantite_servie < quantite_demandee - 0.0001) then 'servie'
      else 'servie_partielle' end
    where id = v.id;
  return t;
end $$;
revoke all on function public.commande_interne_servir(uuid, jsonb, boolean) from public, anon;
grant execute on function public.commande_interne_servir(uuid, jsonb, boolean) to authenticated;
