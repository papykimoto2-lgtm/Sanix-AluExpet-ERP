-- ============================================================================
-- Sanix AluExpert ERP — Circuit de validation DG des mouvements de caisse (modèle Menko Immo)
-- ============================================================================
-- Principe repris de Menko Immo :
--   • un bon d'entrée / de sortie ou un transfert entre caisses est d'abord une DEMANDE ;
--     il ne compte dans le solde de caisse qu'une fois APPROUVÉ ;
--   • approuver ou rejeter exige le droit « valider » du module Caisse ET un plafond de
--     validation (roles.plafond_validation, vide = illimité) couvrant le montant — le DG
--     (administrateur, plafond illimité) valide tout, y compris ses propres bons ; un
--     remplaçant désigné (ex. manager) valide dans la limite de son plafond ;
--   • rejet motivé, visible par l'auteur ; l'auteur suit ses demandes puis confirme la
--     remise physique des fonds (« décaisser ») une fois le bon validé.
-- Mode (Paramètres → Caisse) : 'tous' (tout bon est validé — règle DG de Menko, par défaut),
-- 'plafond' (seuls les bons au-delà du plafond de l'auteur), 'aucun' (circuit désactivé).
-- Appliqué DANS LA BASE : un bon manuel ou un transfert ne peut plus être inséré directement
-- dans caisse_mouvements quand le circuit l'exige ; seules les fonctions de validation le créent.
-- Les mouvements automatiques (vente au comptoir, remboursement, encaissement de facture)
-- restent immédiats.
-- ============================================================================

alter table public.parametres add column if not exists validation_caisse_mode text not null default 'tous';
alter table public.parametres drop constraint if exists parametres_validation_caisse_mode_check;
alter table public.parametres add constraint parametres_validation_caisse_mode_check check (validation_caisse_mode in ('tous','plafond','aucun'));

create table if not exists public.caisse_demandes (
  id uuid primary key default gen_random_uuid(),
  numero text unique,
  caisse_id uuid not null references public.caisses(id) on delete cascade,
  session_id uuid references public.caisse_sessions(id) on delete set null,
  type text not null check (type in ('entree','sortie','transfert')),
  caisse_dest_id uuid references public.caisses(id) on delete set null,
  montant numeric(14,2) not null check (montant > 0),
  date_mouvement date not null default current_date,
  motif text not null,
  beneficiaire text,
  projet_id uuid references public.projets(id) on delete set null,
  statut text not null default 'en_attente' check (statut in ('en_attente','validee','rejetee','annulee')),
  demande_par uuid default auth.uid(),
  demande_nom text,
  demande_le timestamptz not null default now(),
  plafond_demandeur numeric,
  decide_par uuid,
  decide_nom text,
  decide_le timestamptz,
  motif_rejet text,
  mouvement_id uuid references public.caisse_mouvements(id) on delete set null,
  mouvement_dest_id uuid references public.caisse_mouvements(id) on delete set null,
  decaisse_le timestamptz,
  decaisse_par uuid,
  decaisse_nom text,
  created_at timestamptz not null default now()
);
create index if not exists idx_caisse_demandes_statut on public.caisse_demandes (statut, demande_le);
create index if not exists idx_caisse_demandes_caisse on public.caisse_demandes (caisse_id);
create index if not exists idx_caisse_demandes_auteur on public.caisse_demandes (demande_par);

-- ---------- Plafond et habilitation du validateur ----------
create or replace function public.mon_plafond_validation() returns numeric
language sql stable security definer set search_path = public as $$
  select r.plafond_validation from profiles p join roles r on r.id = p.role_id where p.id = auth.uid();
$$;
create or replace function public.peut_valider_caisse(p_montant numeric) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    left join role_permissions rp on rp.role_id = r.id and rp.module_code = 'Caisse'
    where p.id = auth.uid() and p.actif and not p.must_change
      and (r.code = 'admin' or coalesce(rp.peut_valider, false))
      and (r.plafond_validation is null or r.plafond_validation >= coalesce(p_montant, 0))
  );
$$;
create or replace function public.est_validateur_caisse() returns boolean
language sql stable security definer set search_path = public as $$ select public.peut_valider_caisse(0); $$;

-- ---------- Demandes : numérotation, auteur, règles d'accès ----------
create or replace function public.caisse_demandes_avant_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int; an text := to_char(now(), 'YYYY');
begin
  perform pg_advisory_xact_lock(hashtext('caisse_demandes_' || an));
  select coalesce(max(nullif(split_part(numero, '-', 3), '')::int), 0) + 1 into n
    from caisse_demandes where numero like 'DV-' || an || '-%';
  new.numero := 'DV-' || an || '-' || lpad(n::text, 5, '0');
  new.statut := 'en_attente';
  new.demande_par := coalesce(auth.uid(), new.demande_par);
  new.demande_le := now();
  new.demande_nom := coalesce((select coalesce(nom_complet, login) from profiles where id = new.demande_par), new.demande_nom);
  new.plafond_demandeur := public.mon_plafond_validation();
  new.decide_par := null; new.decide_nom := null; new.decide_le := null; new.motif_rejet := null;
  new.mouvement_id := null; new.mouvement_dest_id := null; new.decaisse_le := null; new.decaisse_par := null; new.decaisse_nom := null;
  if new.type = 'transfert' and (new.caisse_dest_id is null or new.caisse_dest_id = new.caisse_id) then
    raise exception 'Transfert : choisissez une caisse de destination différente';
  end if;
  return new;
end $$;
drop trigger if exists trg_caisse_demandes_avant_insert on public.caisse_demandes;
create trigger trg_caisse_demandes_avant_insert before insert on public.caisse_demandes
  for each row execute function public.caisse_demandes_avant_insert();

alter table public.caisse_demandes enable row level security;
drop policy if exists "demandes_lecture" on public.caisse_demandes;
create policy "demandes_lecture" on public.caisse_demandes for select to authenticated
  using (demande_par = auth.uid() or public.est_validateur_caisse() or public.peut_utiliser_caisse(caisse_id));
drop policy if exists "demandes_creation" on public.caisse_demandes;
create policy "demandes_creation" on public.caisse_demandes for insert to authenticated
  with check (public.peut_utiliser_caisse(caisse_id));
-- Aucune modification / suppression directe : décisions, annulation et remise des fonds passent par les fonctions ci-dessous
drop policy if exists "acces_comptes_autorises" on public.caisse_demandes;
create policy "acces_comptes_autorises" on public.caisse_demandes as restrictive for all to authenticated
  using (public.est_utilisateur_autorise()) with check (public.est_utilisateur_autorise());

-- ---------- Garde : pas de bon manuel ni de transfert inséré sans passer par le circuit ----------
create or replace function public.caisse_mouvements_garde_validation() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_mode text; v_plafond numeric;
begin
  if coalesce(current_setting('app.caisse_validation', true), '') = '1' then return new; end if;   -- créé par une validation
  select coalesce(validation_caisse_mode, 'tous') into v_mode from parametres limit 1;
  if coalesce(v_mode, 'tous') = 'aucun' or auth.uid() is null then return new; end if;
  -- Mouvements automatiques : vente au comptoir / remboursement, encaissement de facture
  if exists (select 1 from ventes_comptoir v where v.code = new.numero or v.code || '-AN' = new.numero) then return new; end if;
  if new.numero like 'ENC-%' and exists (select 1 from factures f where 'ENC-' || f.code = new.numero) then return new; end if;
  -- Restauration d'un mouvement existant (annulation d'une suppression échouée) par un validateur habilité
  if new.created_at is not null and new.created_at < now() - interval '2 seconds' and public.peut_valider_caisse(new.montant) then return new; end if;
  if v_mode = 'plafond' then
    v_plafond := public.mon_plafond_validation();
    if new.transfert_id is null and (v_plafond is null or new.montant <= v_plafond) then return new; end if;
  end if;
  raise exception 'Circuit de validation : ce mouvement de caisse doit faire l''objet d''une demande validée par un responsable habilité (DG).';
end $$;
drop trigger if exists trg_caisse_mouvements_garde_validation on public.caisse_mouvements;
create trigger trg_caisse_mouvements_garde_validation before insert on public.caisse_mouvements
  for each row execute function public.caisse_mouvements_garde_validation();

-- Montant d'un bon déjà validé : modifiable seulement par un validateur dont le plafond couvre le nouveau montant
create or replace function public.caisse_mouvements_garde_montant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_mode text;
begin
  if new.montant is not distinct from old.montant and new.type is not distinct from old.type then return new; end if;
  if coalesce(current_setting('app.caisse_validation', true), '') = '1' or auth.uid() is null then return new; end if;
  select coalesce(validation_caisse_mode, 'tous') into v_mode from parametres limit 1;
  if coalesce(v_mode, 'tous') = 'aucun' then return new; end if;
  if old.numero ~ '^(BE|BS)-' or old.transfert_id is not null then
    if not public.peut_valider_caisse(new.montant) then
      raise exception 'Circuit de validation : seul un responsable dont le plafond couvre % FCFA peut modifier le montant de ce bon validé.', new.montant;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_caisse_mouvements_garde_montant on public.caisse_mouvements;
create trigger trg_caisse_mouvements_garde_montant before update on public.caisse_mouvements
  for each row execute function public.caisse_mouvements_garde_montant();

-- ---------- Décision du validateur (DG ou délégué dans la limite de son plafond) ----------
create or replace function public.caisse_demande_decider(p_id uuid, p_decision text, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d caisse_demandes; s_src uuid; s_dst uuid; v_num text; n int; v_trf uuid; m1 uuid; m2 uuid;
        v_nom text; c_src text; c_dst text;
begin
  if auth.uid() is null then raise exception 'Non authentifié'; end if;
  select * into d from caisse_demandes where id = p_id for update;
  if d.id is null then return jsonb_build_object('ok',false,'message','Demande introuvable'); end if;
  if d.statut <> 'en_attente' then return jsonb_build_object('ok',false,'message','Cette demande a déjà été traitée ('||d.statut||')'); end if;
  if not public.peut_valider_caisse(d.montant) then
    return jsonb_build_object('ok',false,'message','🔒 Votre plafond de validation ne couvre pas '||replace(to_char(d.montant,'FM999,999,999,990'),',',' ')||' FCFA : un responsable habilité (DG) doit intervenir.');
  end if;
  select coalesce(nom_complet, login) into v_nom from profiles where id = auth.uid();
  if p_decision = 'rejeter' then
    if coalesce(trim(p_motif),'') = '' then return jsonb_build_object('ok',false,'message','Motif du rejet obligatoire'); end if;
    update caisse_demandes set statut='rejetee', motif_rejet=trim(p_motif), decide_par=auth.uid(), decide_nom=v_nom, decide_le=now() where id = d.id;
    return jsonb_build_object('ok',true,'statut','rejetee');
  end if;
  if p_decision <> 'valider' then raise exception 'Décision inconnue'; end if;

  -- Séance ouverte de la caisse (celle de la demande si elle l'est encore)
  select id into s_src from caisse_sessions where caisse_id = d.caisse_id and statut = 'ouverte'
    order by (id = d.session_id) desc, ouverte_le desc limit 1;
  select nom into c_src from caisses where id = d.caisse_id;
  if s_src is null then
    return jsonb_build_object('ok',false,'message','Aucune séance ouverte sur la caisse « '||coalesce(c_src,'')||' » : ouvrez-la pour valider (le bon s''inscrit dans le solde de la séance).');
  end if;
  perform set_config('app.caisse_validation', '1', true);
  if d.type = 'transfert' then
    select id into s_dst from caisse_sessions where caisse_id = d.caisse_dest_id and statut = 'ouverte' order by ouverte_le desc limit 1;
    select nom into c_dst from caisses where id = d.caisse_dest_id;
    if s_dst is null then return jsonb_build_object('ok',false,'message','La caisse destination « '||coalesce(c_dst,'')||' » doit avoir une séance ouverte.'); end if;
    v_trf := gen_random_uuid();
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, statut, transfert_id, created_by, projet_id)
      values (s_src, d.caisse_id, 'TRF-OUT', current_date, 'sortie', d.montant, coalesce(nullif(d.motif,''), 'Transfert vers '||coalesce(c_dst,'caisse')), d.beneficiaire, 'a_ventiler', v_trf, d.demande_par, d.projet_id)
      returning id into m1;
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, statut, transfert_id, created_by)
      values (s_dst, d.caisse_dest_id, 'TRF-IN', current_date, 'entree', d.montant, 'Transfert depuis '||coalesce(c_src,'caisse'), 'a_ventiler', v_trf, d.demande_par)
      returning id into m2;
  else
    perform pg_advisory_xact_lock(hashtext('caisse_bons_' || d.caisse_id::text));
    select greatest(count(*), coalesce(max(nullif(regexp_replace(numero, '^.*-', ''), '')::int) filter (where numero ~ '^(BE|BS)-[0-9]+$'), 0)) + 1
      into n from caisse_mouvements where caisse_id = d.caisse_id;
    v_num := (case when d.type = 'entree' then 'BE' else 'BS' end) || '-' || lpad(n::text, 5, '0');
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, statut, created_by, projet_id)
      values (s_src, d.caisse_id, v_num, d.date_mouvement, d.type, d.montant, d.motif, d.beneficiaire, 'a_ventiler', d.demande_par, d.projet_id)
      returning id into m1;
  end if;
  update caisse_demandes set statut='validee', decide_par=auth.uid(), decide_nom=v_nom, decide_le=now(), mouvement_id=m1, mouvement_dest_id=m2 where id = d.id;
  return jsonb_build_object('ok',true,'statut','validee','mouvement_id',m1,'numero',coalesce(v_num,'TRF'));
end $$;

-- Annulation par l'auteur tant que la demande est en attente
create or replace function public.caisse_demande_annuler(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update caisse_demandes set statut='annulee', decide_le=now(), decide_par=auth.uid()
    where id = p_id and statut = 'en_attente' and (demande_par = auth.uid() or public.est_validateur_caisse());
  if not found then return jsonb_build_object('ok',false,'message','Demande introuvable ou déjà traitée'); end if;
  return jsonb_build_object('ok',true);
end $$;

-- Remise physique des fonds confirmée (après validation) — par l'auteur ou un utilisateur de la caisse
create or replace function public.caisse_demande_decaisser(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d caisse_demandes;
begin
  select * into d from caisse_demandes where id = p_id for update;
  if d.id is null or d.statut <> 'validee' then return jsonb_build_object('ok',false,'message','🔒 La demande doit d''abord être validée.'); end if;
  if d.decaisse_le is not null then return jsonb_build_object('ok',false,'message','Déjà confirmé.'); end if;
  if not (d.demande_par = auth.uid() or public.peut_utiliser_caisse(d.caisse_id)) then return jsonb_build_object('ok',false,'message','Non autorisé'); end if;
  update caisse_demandes set decaisse_le=now(), decaisse_par=auth.uid(),
    decaisse_nom=(select coalesce(nom_complet, login) from profiles where id = auth.uid()) where id = d.id;
  return jsonb_build_object('ok',true);
end $$;

revoke execute on function public.caisse_demande_decider(uuid,text,text), public.caisse_demande_annuler(uuid), public.caisse_demande_decaisser(uuid) from public, anon;
grant execute on function public.caisse_demande_decider(uuid,text,text), public.caisse_demande_annuler(uuid), public.caisse_demande_decaisser(uuid) to authenticated;
grant execute on function public.mon_plafond_validation(), public.peut_valider_caisse(numeric), public.est_validateur_caisse() to authenticated;

-- Le DG valide tout : l'administrateur a le droit « valider » sur la Caisse ; plafonds par défaut de Menko
update public.role_permissions rp set peut_valider = true
  from public.roles r where r.id = rp.role_id and r.code in ('admin','manager') and rp.module_code = 'Caisse';
