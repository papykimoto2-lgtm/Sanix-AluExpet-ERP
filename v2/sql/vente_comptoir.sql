-- ============================================================================
-- Sanix AluExpert ERP — Module Vente au comptoir
-- ============================================================================
-- À exécuter APRÈS sql/composants_prix_achat_vente.sql.
-- Additif : crée deux tables, une fonction de numérotation et deux RPC.
-- ============================================================================

create table if not exists ventes_comptoir (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  date_vente date not null default current_date,
  client_id uuid references clients(id) on delete set null,
  client_nom text,
  client_telephone text,
  sous_total numeric not null default 0,
  remise numeric not null default 0,
  total numeric not null default 0,
  cout_total numeric not null default 0,           -- somme des prix d'achat (marge = total - cout_total)
  mode_paiement text not null default 'espece' check (mode_paiement in ('espece','mobile_money','banque','cheque')),
  montant_recu numeric,
  monnaie_rendue numeric,
  reference_paiement text,
  caisse_id uuid references caisses(id) on delete set null,
  statut text not null default 'validee' check (statut in ('validee','annulee')),
  ecriture_id uuid references compta_ecritures(id) on delete set null,
  motif_annulation text,
  annulee_le timestamptz,
  annulee_par text,
  vendeur text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists idx_ventes_comptoir_date on ventes_comptoir(date_vente);

create table if not exists ventes_comptoir_lignes (
  id uuid primary key default gen_random_uuid(),
  vente_id uuid not null references ventes_comptoir(id) on delete cascade,
  composant_id uuid references composants(id) on delete set null,
  designation text not null,
  unite text,
  quantite numeric not null check (quantite > 0),
  prix_unitaire numeric not null default 0,        -- prix de vente appliqué
  prix_achat numeric not null default 0,           -- prix d'achat au moment de la vente
  remise_pct numeric not null default 0,
  total numeric not null default 0,
  ordre int not null default 0
);
create index if not exists idx_ventes_comptoir_lignes_vente on ventes_comptoir_lignes(vente_id);

alter table ventes_comptoir enable row level security;
alter table ventes_comptoir_lignes enable row level security;
drop policy if exists "authenticated_all_ventes_comptoir" on ventes_comptoir;
create policy "authenticated_all_ventes_comptoir" on ventes_comptoir for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_all_ventes_comptoir_lignes" on ventes_comptoir_lignes;
create policy "authenticated_all_ventes_comptoir_lignes" on ventes_comptoir_lignes for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Numérotation VC-AAAA-00001 (sans trou tant qu'on ne supprime pas ; verrou pour les ventes simultanées)
create or replace function public.ventes_comptoir_set_code() returns trigger
language plpgsql set search_path = public as $$
declare n int; an text := to_char(coalesce(new.date_vente, current_date), 'YYYY');
begin
  if new.code is null then
    perform pg_advisory_xact_lock(hashtext('ventes_comptoir_code_' || an));
    select coalesce(max(nullif(split_part(code, '-', 3), '')::int), 0) + 1 into n
      from ventes_comptoir where code like 'VC-' || an || '-%';
    new.code := 'VC-' || an || '-' || lpad(n::text, 5, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_ventes_comptoir_code on ventes_comptoir;
create trigger trg_ventes_comptoir_code before insert on ventes_comptoir
  for each row execute function public.ventes_comptoir_set_code();

-- Validation atomique : en-tête + lignes + sorties de stock dans une seule transaction.
-- p_vente : objet JSON des colonnes de ventes_comptoir ; p_lignes : tableau JSON des lignes.
create or replace function public.vente_comptoir_valider(p_vente jsonb, p_lignes jsonb)
returns ventes_comptoir
language plpgsql set search_path = public as $$
declare v ventes_comptoir; l jsonb; i int := 0;
begin
  if jsonb_array_length(coalesce(p_lignes, '[]'::jsonb)) = 0 then
    raise exception 'Le panier est vide';
  end if;
  insert into ventes_comptoir (date_vente, client_id, client_nom, client_telephone, sous_total, remise, total, cout_total,
      mode_paiement, montant_recu, monnaie_rendue, reference_paiement, caisse_id, vendeur, created_by)
    values (coalesce((p_vente->>'date_vente')::date, current_date), nullif(p_vente->>'client_id','')::uuid,
      p_vente->>'client_nom', p_vente->>'client_telephone',
      coalesce((p_vente->>'sous_total')::numeric,0), coalesce((p_vente->>'remise')::numeric,0),
      coalesce((p_vente->>'total')::numeric,0), coalesce((p_vente->>'cout_total')::numeric,0),
      coalesce(p_vente->>'mode_paiement','espece'), (p_vente->>'montant_recu')::numeric, (p_vente->>'monnaie_rendue')::numeric,
      p_vente->>'reference_paiement', nullif(p_vente->>'caisse_id','')::uuid, p_vente->>'vendeur', auth.uid())
    returning * into v;
  for l in select * from jsonb_array_elements(p_lignes) loop
    insert into ventes_comptoir_lignes (vente_id, composant_id, designation, unite, quantite, prix_unitaire, prix_achat, remise_pct, total, ordre)
      values (v.id, nullif(l->>'composant_id','')::uuid, l->>'designation', l->>'unite', (l->>'quantite')::numeric,
        coalesce((l->>'prix_unitaire')::numeric,0), coalesce((l->>'prix_achat')::numeric,0),
        coalesce((l->>'remise_pct')::numeric,0), coalesce((l->>'total')::numeric,0), i);
    if nullif(l->>'composant_id','') is not null then
      perform stock_mouvement((l->>'composant_id')::uuid, 'sortie', (l->>'quantite')::numeric, 'Vente au comptoir', v.code, null);
    end if;
    i := i + 1;
  end loop;
  return v;
end $$;

-- Annulation : remet les articles en stock (ajustement, sans toucher au CMUP) et marque la vente annulée.
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
      perform stock_mouvement(l.composant_id, 'ajustement', l.quantite, 'Annulation vente au comptoir', v.code, null);
    end if;
  end loop;
  update ventes_comptoir set statut = 'annulee', motif_annulation = p_motif, annulee_le = now(), annulee_par = p_par
    where id = p_vente_id returning * into v;
  return v;
end $$;

-- Droits : ajoute le module « Comptoir » aux rôles existants (si le module Utilisateurs & Rôles est installé)
do $$
begin
  if to_regclass('public.role_permissions') is not null then
    insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
      select r.id, 'Comptoir',
        r.code in ('admin','manager','comptable','caissiere','commercial','commissaire'),
        r.code in ('admin','manager','caissiere','commercial'),
        r.code in ('admin','manager','caissiere','commercial'),
        r.code in ('admin','manager'),
        r.code in ('admin','manager')
      from roles r
      on conflict (role_id,module_code) do nothing;
  end if;
end $$;
