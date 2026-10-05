-- ============================================================================
-- Sanix AluExpert ERP — Multi-dépôts, points de vente affiliés, transferts dépôt → dépôt
-- ============================================================================
-- À exécuter APRÈS sql/vente_comptoir.sql. Additif et idempotent.
--
-- Modèle :
--   depots          : lieux de stockage (dépôt, magasin, atelier…) ; un seul « principal ».
--   points_vente    : points de vente, chacun affilié à UN dépôt (d'où sort le stock vendu)
--                     et éventuellement à une caisse.
--   stocks_depot    : quantité de chaque composant dans chaque dépôt.
--                     Invariant : composants.stock_actuel = somme des stocks_depot (+ rien en transit).
--   transferts_stock: bon de transfert en 2 temps — expédition (sortie du dépôt source, marchandise
--                     « en transit ») puis réception (entrée au dépôt destination, écarts tracés).
-- Le CMUP reste global (par composant, tous dépôts confondus).
-- ============================================================================

create table if not exists depots (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  nom text not null,
  type text not null default 'depot' check (type in ('depot','magasin','atelier','chantier')),
  adresse text,
  commune text,
  responsable text,
  telephone text,
  est_principal boolean not null default false,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists depots_un_seul_principal on depots(est_principal) where est_principal;

create table if not exists points_vente (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  nom text not null,
  depot_id uuid not null references depots(id) on delete restrict,
  caisse_id uuid references caisses(id) on delete set null,
  adresse text,
  responsable text,
  telephone text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists stocks_depot (
  depot_id uuid not null references depots(id) on delete restrict,
  composant_id uuid not null references composants(id) on delete cascade,
  quantite numeric not null default 0,
  primary key (depot_id, composant_id)
);
create index if not exists idx_stocks_depot_composant on stocks_depot(composant_id);

create table if not exists transferts_stock (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  depot_source_id uuid not null references depots(id) on delete restrict,
  depot_destination_id uuid not null references depots(id) on delete restrict,
  statut text not null default 'brouillon' check (statut in ('brouillon','en_transit','recu','annule')),
  motif text,
  notes_reception text,
  date_expedition timestamptz,
  date_reception timestamptz,
  expedie_par text,
  recu_par text,
  annule_par text,
  created_by uuid,
  created_at timestamptz not null default now(),
  check (depot_source_id <> depot_destination_id)
);
create table if not exists transferts_stock_lignes (
  id uuid primary key default gen_random_uuid(),
  transfert_id uuid not null references transferts_stock(id) on delete cascade,
  composant_id uuid not null references composants(id) on delete restrict,
  quantite_envoyee numeric not null check (quantite_envoyee > 0),
  quantite_recue numeric,
  cmup numeric,
  ordre int not null default 0
);
create index if not exists idx_transferts_lignes_transfert on transferts_stock_lignes(transfert_id);

alter table mouvements_stock add column if not exists depot_id uuid references depots(id) on delete restrict;
alter table mouvements_stock add column if not exists transfert_id uuid references transferts_stock(id) on delete set null;
alter table mouvements_stock add column if not exists stock_depot_apres numeric;
alter table mouvements_stock drop constraint if exists mouvements_stock_type_check;
alter table mouvements_stock add constraint mouvements_stock_type_check check (type in ('entree','sortie','ajustement','inventaire','transfert'));

alter table ventes_comptoir add column if not exists point_vente_id uuid references points_vente(id) on delete set null;
alter table ventes_comptoir add column if not exists depot_id uuid references depots(id) on delete set null;

-- RLS : même politique que le reste de l'application
do $$
declare t text;
begin
  foreach t in array array['depots','points_vente','stocks_depot','transferts_stock','transferts_stock_lignes'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "authenticated_all_%1$s" on %1$I', t);
    execute format('create policy "authenticated_all_%1$s" on %1$I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t);
  end loop;
end $$;

-- Reprise de l'existant : dépôt principal + stock actuel + point de vente par défaut
insert into depots(code,nom,type,est_principal)
  select 'DEP-01','Dépôt principal','depot',true
  where not exists (select 1 from depots where est_principal);
insert into stocks_depot(depot_id,composant_id,quantite)
  select d.id, c.id, c.stock_actuel from composants c cross join depots d
  where d.est_principal and coalesce(c.stock_actuel,0) <> 0
    and not exists (select 1 from stocks_depot s where s.composant_id = c.id);
update mouvements_stock set depot_id = (select id from depots where est_principal) where depot_id is null;
insert into points_vente(code,nom,depot_id,caisse_id)
  select 'PDV-01','Comptoir principal',(select id from depots where est_principal),
         (select id from caisses where actif order by created_at limit 1)
  where not exists (select 1 from points_vente);
update ventes_comptoir set point_vente_id = (select id from points_vente order by created_at limit 1),
                           depot_id = (select id from depots where est_principal)
  where depot_id is null;

-- Numérotation TR-AAAA-00001
create or replace function public.transferts_stock_set_code() returns trigger
language plpgsql set search_path = public as $$
declare n int; an text := to_char(now(), 'YYYY');
begin
  if new.code is null then
    perform pg_advisory_xact_lock(hashtext('transferts_stock_code_' || an));
    select coalesce(max(nullif(split_part(code, '-', 3), '')::int), 0) + 1 into n
      from transferts_stock where code like 'TR-' || an || '-%';
    new.code := 'TR-' || an || '-' || lpad(n::text, 5, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_transferts_stock_code on transferts_stock;
create trigger trg_transferts_stock_code before insert on transferts_stock
  for each row execute function public.transferts_stock_set_code();

-- Mouvement de stock multi-dépôts. p_depot_id NULL = dépôt principal (compatibilité des anciens appels).
--   entree / sortie : quantité positive ; ajustement : écart signé ;
--   inventaire      : quantité comptée DANS CE DÉPÔT ;
--   transfert       : écart signé (négatif au départ, positif à l'arrivée), CMUP inchangé.
drop function if exists public.stock_mouvement(uuid,text,numeric,text,text,numeric);
create or replace function public.stock_mouvement(p_composant_id uuid, p_type text, p_quantite numeric,
  p_motif text default null, p_reference text default null, p_prix_unitaire numeric default null,
  p_depot_id uuid default null, p_transfert_id uuid default null)
returns composants
language plpgsql set search_path = public as $$
declare
  v_comp composants%rowtype;
  v_depot uuid;
  v_qte_depot numeric;
  v_delta numeric;
  v_new_cmup numeric;
begin
  if p_type not in ('entree','sortie','ajustement','inventaire','transfert') then
    raise exception 'Type de mouvement invalide: %', p_type;
  end if;
  v_depot := coalesce(p_depot_id, (select id from depots where est_principal limit 1));
  if v_depot is null then raise exception 'Aucun dépôt principal défini'; end if;

  select * into v_comp from composants where id = p_composant_id for update;
  if v_comp.id is null then raise exception 'Composant introuvable'; end if;

  insert into stocks_depot(depot_id, composant_id, quantite) values (v_depot, p_composant_id, 0)
    on conflict (depot_id, composant_id) do nothing;
  select quantite into v_qte_depot from stocks_depot where depot_id = v_depot and composant_id = p_composant_id for update;

  v_new_cmup := coalesce(v_comp.cmup, 0);
  if p_type = 'entree' then
    if p_quantite <= 0 then raise exception 'Quantité entrée doit être positive'; end if;
    v_delta := p_quantite;
    if p_prix_unitaire is not null and (v_comp.stock_actuel + p_quantite) > 0 then
      v_new_cmup := ((v_comp.stock_actuel * coalesce(v_comp.cmup,0)) + (p_quantite * p_prix_unitaire))
                    / (v_comp.stock_actuel + p_quantite);
    else
      v_new_cmup := coalesce(v_comp.cmup, p_prix_unitaire, 0);
    end if;
  elsif p_type = 'sortie' then
    if p_quantite <= 0 then raise exception 'Quantité sortie doit être positive'; end if;
    v_delta := -p_quantite;
  elsif p_type in ('ajustement','transfert') then
    v_delta := p_quantite;
  elsif p_type = 'inventaire' then
    v_delta := p_quantite - v_qte_depot;
  end if;

  update stocks_depot set quantite = quantite + v_delta where depot_id = v_depot and composant_id = p_composant_id;
  update composants set stock_actuel = stock_actuel + v_delta, cmup = v_new_cmup where id = p_composant_id
    returning * into v_comp;

  insert into mouvements_stock (composant_id, type, quantite, prix_unitaire, stock_apres, cmup_apres, motif, reference,
                                created_by, depot_id, transfert_id, stock_depot_apres)
    values (p_composant_id, p_type, v_delta, p_prix_unitaire, v_comp.stock_actuel, v_new_cmup, p_motif, p_reference,
            auth.uid(), v_depot, p_transfert_id, v_qte_depot + v_delta);
  return v_comp;
end $$;

-- Expédition : contrôle du disponible au dépôt source, sortie « transfert », passage en transit
create or replace function public.transfert_expedier(p_transfert_id uuid, p_par text)
returns transferts_stock
language plpgsql set search_path = public as $$
declare t transferts_stock; l record; v_dispo numeric; n int := 0;
begin
  select * into t from transferts_stock where id = p_transfert_id for update;
  if t.id is null then raise exception 'Transfert introuvable'; end if;
  if t.statut <> 'brouillon' then raise exception 'Seul un transfert en brouillon peut être expédié'; end if;
  for l in select tl.*, c.nom, c.cmup as c_cmup from transferts_stock_lignes tl join composants c on c.id = tl.composant_id
           where tl.transfert_id = t.id order by tl.ordre loop
    select coalesce(quantite,0) into v_dispo from stocks_depot where depot_id = t.depot_source_id and composant_id = l.composant_id;
    if coalesce(v_dispo,0) < l.quantite_envoyee then
      raise exception 'Stock insuffisant au dépôt source pour « % » : disponible %, demandé %', l.nom, coalesce(v_dispo,0), l.quantite_envoyee;
    end if;
    perform stock_mouvement(l.composant_id, 'transfert', -l.quantite_envoyee, 'Transfert expédié', t.code, null, t.depot_source_id, t.id);
    update transferts_stock_lignes set cmup = l.c_cmup where id = l.id;
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Le transfert ne contient aucune ligne'; end if;
  update transferts_stock set statut = 'en_transit', date_expedition = now(), expedie_par = p_par
    where id = t.id returning * into t;
  return t;
end $$;

-- Réception : p_lignes = [{"id": ligne_id, "quantite_recue": n}] (absent = quantité envoyée)
create or replace function public.transfert_receptionner(p_transfert_id uuid, p_lignes jsonb, p_notes text, p_par text)
returns transferts_stock
language plpgsql set search_path = public as $$
declare t transferts_stock; l transferts_stock_lignes; v_recu numeric;
begin
  select * into t from transferts_stock where id = p_transfert_id for update;
  if t.id is null then raise exception 'Transfert introuvable'; end if;
  if t.statut <> 'en_transit' then raise exception 'Seul un transfert en transit peut être réceptionné'; end if;
  for l in select * from transferts_stock_lignes where transfert_id = t.id order by ordre loop
    select (e->>'quantite_recue')::numeric into v_recu from jsonb_array_elements(coalesce(p_lignes,'[]'::jsonb)) e
      where e->>'id' = l.id::text limit 1;
    v_recu := coalesce(v_recu, l.quantite_envoyee);
    if v_recu < 0 then raise exception 'Quantité reçue négative'; end if;
    if v_recu > 0 then
      perform stock_mouvement(l.composant_id, 'transfert', v_recu,
        case when v_recu < l.quantite_envoyee then 'Transfert reçu (écart ' || (l.quantite_envoyee - v_recu) || ')' else 'Transfert reçu' end,
        t.code, null, t.depot_destination_id, t.id);
    end if;
    update transferts_stock_lignes set quantite_recue = v_recu where id = l.id;
  end loop;
  update transferts_stock set statut = 'recu', date_reception = now(), recu_par = p_par, notes_reception = p_notes
    where id = t.id returning * into t;
  return t;
end $$;

-- Annulation : brouillon → annulé ; en transit → marchandise remise au dépôt source
create or replace function public.transfert_annuler(p_transfert_id uuid, p_par text)
returns transferts_stock
language plpgsql set search_path = public as $$
declare t transferts_stock; l transferts_stock_lignes;
begin
  select * into t from transferts_stock where id = p_transfert_id for update;
  if t.id is null then raise exception 'Transfert introuvable'; end if;
  if t.statut not in ('brouillon','en_transit') then raise exception 'Ce transfert ne peut plus être annulé'; end if;
  if t.statut = 'en_transit' then
    for l in select * from transferts_stock_lignes where transfert_id = t.id loop
      perform stock_mouvement(l.composant_id, 'transfert', l.quantite_envoyee, 'Transfert annulé — retour', t.code, null, t.depot_source_id, t.id);
    end loop;
  end if;
  update transferts_stock set statut = 'annule', annule_par = p_par where id = t.id returning * into t;
  return t;
end $$;

-- Vente au comptoir : le stock sort du dépôt affilié au point de vente
create or replace function public.vente_comptoir_valider(p_vente jsonb, p_lignes jsonb)
returns ventes_comptoir
language plpgsql set search_path = public as $$
declare v ventes_comptoir; l jsonb; i int := 0; v_depot uuid;
begin
  if jsonb_array_length(coalesce(p_lignes, '[]'::jsonb)) = 0 then
    raise exception 'Le panier est vide';
  end if;
  v_depot := coalesce(nullif(p_vente->>'depot_id','')::uuid,
                      (select depot_id from points_vente where id = nullif(p_vente->>'point_vente_id','')::uuid),
                      (select id from depots where est_principal limit 1));
  insert into ventes_comptoir (date_vente, client_id, client_nom, client_telephone, sous_total, remise, total, cout_total,
      mode_paiement, montant_recu, monnaie_rendue, reference_paiement, caisse_id, vendeur, created_by, point_vente_id, depot_id)
    values (coalesce((p_vente->>'date_vente')::date, current_date), nullif(p_vente->>'client_id','')::uuid,
      p_vente->>'client_nom', p_vente->>'client_telephone',
      coalesce((p_vente->>'sous_total')::numeric,0), coalesce((p_vente->>'remise')::numeric,0),
      coalesce((p_vente->>'total')::numeric,0), coalesce((p_vente->>'cout_total')::numeric,0),
      coalesce(p_vente->>'mode_paiement','espece'), (p_vente->>'montant_recu')::numeric, (p_vente->>'monnaie_rendue')::numeric,
      p_vente->>'reference_paiement', nullif(p_vente->>'caisse_id','')::uuid, p_vente->>'vendeur', auth.uid(),
      nullif(p_vente->>'point_vente_id','')::uuid, v_depot)
    returning * into v;
  for l in select * from jsonb_array_elements(p_lignes) loop
    insert into ventes_comptoir_lignes (vente_id, composant_id, designation, unite, quantite, prix_unitaire, prix_achat, remise_pct, total, ordre)
      values (v.id, nullif(l->>'composant_id','')::uuid, l->>'designation', l->>'unite', (l->>'quantite')::numeric,
        coalesce((l->>'prix_unitaire')::numeric,0), coalesce((l->>'prix_achat')::numeric,0),
        coalesce((l->>'remise_pct')::numeric,0), coalesce((l->>'total')::numeric,0), i);
    if nullif(l->>'composant_id','') is not null then
      perform stock_mouvement((l->>'composant_id')::uuid, 'sortie', (l->>'quantite')::numeric, 'Vente au comptoir', v.code, null, v_depot, null);
    end if;
    i := i + 1;
  end loop;
  return v;
end $$;

create or replace function public.vente_comptoir_annuler(p_vente_id uuid, p_motif text, p_par text)
returns ventes_comptoir
language plpgsql set search_path = public as $$
declare v ventes_comptoir; l ventes_comptoir_lignes;
begin
  select * into v from ventes_comptoir where id = p_vente_id for update;
  if v.id is null then raise exception 'Vente introuvable'; end if;
  if v.statut = 'annulee' then raise exception 'Vente déjà annulée'; end if;
  for l in select * from ventes_comptoir_lignes where vente_id = p_vente_id loop
    if l.composant_id is not null then
      perform stock_mouvement(l.composant_id, 'ajustement', l.quantite, 'Annulation vente au comptoir', v.code, null, v.depot_id, null);
    end if;
  end loop;
  update ventes_comptoir set statut = 'annulee', motif_annulation = p_motif, annulee_le = now(), annulee_par = p_par
    where id = p_vente_id returning * into v;
  return v;
end $$;
