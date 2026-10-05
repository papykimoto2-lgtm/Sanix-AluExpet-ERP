-- ============================================================================
-- CENTRE DE VALIDATION — Direction générale & hiérarchie autorisée (modèle Menko Immo)
-- ----------------------------------------------------------------------------
-- 1. Paliers hiérarchiques par montant (N+1 / Direction N+2 / DG-PDG) stockés dans
--    parametres.validation_hierarchie : au-delà d'un seuil, seul un rôle de niveau
--    suffisant (en plus du droit « valider » du module et du plafond du rôle) peut décider.
-- 2. Fonction générique peut_valider(module, montant) — utilisée par la caisse
--    (peut_valider_caisse), les bons de commande fournisseur et les commandes internes.
-- 3. Circuit de validation des bons de commande fournisseur au-delà d'un seuil :
--    soumettre → valider / rejeter ; l'envoi et la réception exigent la validation.
-- 4. Vue v_validations : toutes les demandes (caisse, BC, commandes internes) sous un
--    format unique (en attente, historique, état périodique par type).
-- Idempotent : peut être rejoué.
-- ============================================================================

alter table public.parametres add column if not exists validation_hierarchie jsonb not null default
  '{"paliers_actifs":false,
    "paliers":[{"code":"N1","libelle":"Responsable hiérarchique (N+1)","seuil":1000000,"niveau":2},
               {"code":"N2","libelle":"Direction (N+2)","seuil":5000000,"niveau":3},
               {"code":"DG","libelle":"Directeur général / PDG","seuil":20000000,"niveau":4}],
    "bon_commande":{"actif":true,"seuil":500000},
    "commande_interne":{"actif":true}}'::jsonb;

-- ---------- Paliers ----------
create or replace function public.validation_niveau_requis(p_montant numeric) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select max((p->>'niveau')::int)
      from parametres pa, jsonb_array_elements(coalesce(pa.validation_hierarchie->'paliers', '[]'::jsonb)) p
     where coalesce((pa.validation_hierarchie->>'paliers_actifs')::boolean, false)
       and coalesce(p_montant, 0) > coalesce((p->>'seuil')::numeric, 0)
  ), 0);
$$;
grant execute on function public.validation_niveau_requis(numeric) to authenticated;

-- Droit de décider : droit « valider » du module (ou administrateur), plafond du rôle couvrant
-- le montant, niveau du rôle ≥ niveau exigé par le palier (l'administrateur = DG passe tous les paliers).
create or replace function public.peut_valider(p_module text, p_montant numeric) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    left join role_permissions rp on rp.role_id = r.id and rp.module_code = p_module
    where p.id = auth.uid() and p.actif and not p.must_change
      and (r.code = 'admin' or coalesce(rp.peut_valider, false))
      and (r.plafond_validation is null or r.plafond_validation >= coalesce(p_montant, 0))
      and (r.code = 'admin' or r.niveau >= public.validation_niveau_requis(p_montant))
  );
$$;
grant execute on function public.peut_valider(text, numeric) to authenticated;

-- La caisse applique désormais aussi les paliers hiérarchiques
create or replace function public.peut_valider_caisse(p_montant numeric) returns boolean
language sql stable security definer set search_path = public as $$ select public.peut_valider('Caisse', p_montant); $$;

-- ---------- Bons de commande fournisseur : circuit de validation ----------
alter table public.commandes_fournisseur add column if not exists validation_statut text;
alter table public.commandes_fournisseur drop constraint if exists commandes_fournisseur_validation_statut_check;
alter table public.commandes_fournisseur add constraint commandes_fournisseur_validation_statut_check
  check (validation_statut is null or validation_statut in ('en_attente','validee','rejetee'));
alter table public.commandes_fournisseur add column if not exists validation_montant numeric(16,2);
alter table public.commandes_fournisseur add column if not exists validation_demande_le timestamptz;
alter table public.commandes_fournisseur add column if not exists validation_demande_nom text;
alter table public.commandes_fournisseur add column if not exists valide_par_nom text;
alter table public.commandes_fournisseur add column if not exists valide_le timestamptz;
alter table public.commandes_fournisseur add column if not exists motif_rejet text;
create index if not exists idx_cf_validation on public.commandes_fournisseur (validation_statut) where validation_statut is not null;

create or replace function public.bc_validation_requise(p_montant numeric) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce((validation_hierarchie->'bon_commande'->>'actif')::boolean, false)
                          and coalesce(p_montant, 0) > coalesce((validation_hierarchie->'bon_commande'->>'seuil')::numeric, 0)
                     from parametres limit 1), false);
$$;
grant execute on function public.bc_validation_requise(numeric) to authenticated;

-- Commande validée pour son montant actuel (une hausse du montant après validation annule la validation)
create or replace function public.bc_est_validee(v public.commandes_fournisseur) returns boolean
language sql stable security definer set search_path = public as $$
  select not public.bc_validation_requise(v.total_ttc)
      or (v.validation_statut = 'validee' and v.total_ttc <= coalesce(v.validation_montant, 0) + 0.005);
$$;

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
  -- Une demande en attente dont le montant change est retirée ; une validation ne couvre pas une hausse du montant
  if (v.validation_statut = 'en_attente' and v.total_ttc <> coalesce(v.validation_montant, 0))
     or (v.validation_statut = 'validee' and v.total_ttc > coalesce(v.validation_montant, 0) + 0.005) then
    update commandes_fournisseur set validation_statut = null, valide_par_nom = null, valide_le = null where id = v.id returning * into v;
  end if;
  return v;
end $$;
revoke all on function public.commande_fournisseur_enregistrer(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.commande_fournisseur_enregistrer(uuid, jsonb, jsonb) to authenticated;

create or replace function public.commande_fournisseur_action(p_id uuid, p_action text, p_motif text default null)
returns public.commandes_fournisseur language plpgsql security definer set search_path = public as $$
declare v public.commandes_fournisseur; n int; v_nom text := public.achat_utilisateur();
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  select * into v from commandes_fournisseur where id = p_id for update;
  if v.id is null then raise exception 'Commande introuvable'; end if;
  if p_action = 'envoyer' then
    if v.statut <> 'brouillon' then raise exception 'Commande déjà envoyée (%)', v.code; end if;
    if not public.bc_est_validee(v) then
      -- Un décideur habilité valide en envoyant ; les autres doivent soumettre la commande
      if public.peut_valider('Stock', v.total_ttc) then
        update commandes_fournisseur set validation_statut = 'validee', validation_montant = total_ttc,
          validation_demande_le = coalesce(validation_demande_le, now()), validation_demande_nom = coalesce(validation_demande_nom, v_nom),
          valide_par_nom = v_nom, valide_le = now(), motif_rejet = null where id = v.id;
      else
        raise exception 'Validation hiérarchique requise : la commande % (% FCFA TTC) dépasse le seuil de validation — soumettez-la à la validation', v.code, to_char(v.total_ttc, 'FM999G999G999G990');
      end if;
    end if;
    update commandes_fournisseur set statut = 'envoyee', envoyee_le = now() where id = v.id returning * into v;
  elsif p_action = 'soumettre_validation' then
    if v.statut <> 'brouillon' then raise exception 'Seule une commande en brouillon peut être soumise à validation'; end if;
    if v.validation_statut = 'en_attente' then raise exception 'Commande déjà en attente de validation'; end if;
    update commandes_fournisseur set validation_statut = 'en_attente', validation_montant = total_ttc, validation_demande_le = now(),
      validation_demande_nom = v_nom, valide_par_nom = null, valide_le = null, motif_rejet = null where id = v.id returning * into v;
  elsif p_action in ('valider','rejeter') then
    if v.validation_statut is distinct from 'en_attente' then raise exception 'La commande % n''est pas en attente de validation', v.code; end if;
    if not public.peut_valider('Stock', v.total_ttc) then
      raise exception 'Hiérarchie insuffisante : votre rôle (droit « valider » Stock, plafond, niveau) ne couvre pas % FCFA', to_char(v.total_ttc, 'FM999G999G999G990');
    end if;
    if p_action = 'rejeter' and coalesce(trim(p_motif), '') = '' then raise exception 'Motif du rejet obligatoire'; end if;
    update commandes_fournisseur set validation_statut = case when p_action = 'valider' then 'validee' else 'rejetee' end,
      validation_montant = total_ttc, valide_par_nom = v_nom, valide_le = now(),
      motif_rejet = case when p_action = 'rejeter' then trim(p_motif) end where id = v.id returning * into v;
  elsif p_action = 'retirer_validation' then
    if v.validation_statut is distinct from 'en_attente' then raise exception 'Aucune demande de validation en cours'; end if;
    update commandes_fournisseur set validation_statut = null where id = v.id returning * into v;
  elsif p_action = 'annuler' then
    select count(*) into n from receptions_fournisseur where commande_id = v.id;
    if n > 0 then raise exception 'Commande déjà (partiellement) reçue : utilisez « Solder » pour abandonner le reste'; end if;
    if v.statut in ('annulee','recue','soldee') then raise exception 'Cette commande ne peut plus être annulée'; end if;
    if coalesce(trim(p_motif), '') = '' then raise exception 'Motif d''annulation obligatoire'; end if;
    update commandes_fournisseur set statut = 'annulee', motif_annulation = trim(p_motif),
      validation_statut = case when validation_statut = 'en_attente' then null else validation_statut end where id = v.id returning * into v;
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

-- Réception : une commande encore en brouillon doit être validée si elle dépasse le seuil
create or replace function public.bc_reception_controle() returns trigger
language plpgsql security definer set search_path = public as $$
declare cf public.commandes_fournisseur;
begin
  if new.commande_id is null then return new; end if;
  select * into cf from commandes_fournisseur where id = new.commande_id;
  if cf.statut = 'brouillon' and not public.bc_est_validee(cf) then
    raise exception 'La commande % doit être validée par la hiérarchie avant réception (montant % FCFA TTC)', cf.code, to_char(cf.total_ttc, 'FM999G999G999G990');
  end if;
  return new;
end $$;
drop trigger if exists trg_bc_reception_controle on public.receptions_fournisseur;
create trigger trg_bc_reception_controle before insert on public.receptions_fournisseur for each row execute function public.bc_reception_controle();

-- ---------- Commandes internes : décision par la hiérarchie autorisée ----------
create or replace function public.commande_interne_valeur(p_id uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(l.quantite_demandee * coalesce(nullif(c.cmup, 0), c.prix_unitaire, 0)), 2), 0)
    from commandes_internes_lignes l join composants c on c.id = l.composant_id where l.commande_id = p_id;
$$;
grant execute on function public.commande_interne_valeur(uuid) to authenticated;

create or replace function public.commande_interne_action(p_id uuid, p_action text, p_motif text default null)
returns public.commandes_internes language plpgsql security definer set search_path = public as $$
declare v public.commandes_internes;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  select * into v from commandes_internes where id = p_id for update;
  if v.id is null then raise exception 'Commande interne introuvable'; end if;
  if p_action in ('valider','refuser') and not (public.est_gestionnaire_caisse() or public.peut_valider('Stock', public.commande_interne_valeur(v.id))) then
    raise exception 'Validation réservée à la hiérarchie autorisée (administrateur, manager ou rôle habilité « valider » Stock couvrant la valeur)';
  end if;
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

-- ---------- Vue unifiée des validations ----------
drop view if exists public.v_validations;
create view public.v_validations with (security_invoker = true) as
  select 'caisse'::text as categorie,
         'caisse_' || d.type as type,
         d.id as ref_id, d.numero as reference,
         d.motif || coalesce(' — ' || d.beneficiaire, '') as libelle,
         d.montant::numeric as montant,
         d.demande_nom as demandeur, d.demande_le as date_demande,
         case d.statut when 'en_attente' then 'en_attente' when 'validee' then 'valide' when 'rejetee' then 'rejete' else 'annule' end as statut,
         d.decide_nom as valideur, d.decide_le as date_decision, d.motif_rejet as motif,
         c.nom as lieu, d.projet_id
    from public.caisse_demandes d left join public.caisses c on c.id = d.caisse_id
  union all
  select 'bon_commande', 'bon_commande', b.id, b.code,
         'Commande fournisseur — ' || coalesce(f.nom, '?'),
         coalesce(b.validation_montant, b.total_ttc)::numeric,
         coalesce(b.validation_demande_nom, b.cree_par_nom), coalesce(b.validation_demande_le, b.created_at),
         case b.validation_statut when 'en_attente' then 'en_attente' when 'validee' then 'valide' else 'rejete' end,
         b.valide_par_nom, b.valide_le, b.motif_rejet,
         dp.nom, b.projet_id
    from public.commandes_fournisseur b
    left join public.fournisseurs f on f.id = b.fournisseur_id
    left join public.depots dp on dp.id = b.depot_id
   where b.validation_statut is not null
  union all
  select 'commande_interne', 'commande_interne', ci.id, ci.code,
         'Commande interne — ' || coalesce(ds.nom, '?') || ' → ' || coalesce(dd.nom, '?') || coalesce(' · ' || ci.motif, ''),
         public.commande_interne_valeur(ci.id),
         ci.demande_par_nom, ci.created_at,
         case when ci.statut = 'soumise' then 'en_attente' when ci.statut = 'refusee' then 'rejete' else 'valide' end,
         ci.decide_par_nom, ci.decide_le, ci.motif_refus,
         dd.nom, ci.projet_id
    from public.commandes_internes ci
    left join public.depots ds on ds.id = ci.depot_fournisseur_id
    left join public.depots dd on dd.id = ci.depot_demandeur_id
   where ci.statut = 'soumise' or ci.decide_le is not null;
grant select on public.v_validations to authenticated;
revoke all on public.v_validations from anon;

notify pgrst, 'reload schema';
