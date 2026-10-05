-- ============================================================================
-- Sanix AluExpert ERP — Module Comptabilité SYSCOHADA + Caisse (multi-caisses)
-- ============================================================================
-- À exécuter une seule fois dans l'éditeur SQL de votre projet Supabase
-- (https://supabase.com/dashboard/project/snphfuygvllbioaoyfkm/sql/new).
-- Ce script est additif : il ne touche à aucune table existante de l'application
-- (clients, devis, factures, projets...). Il crée uniquement les nouvelles
-- tables nécessaires à la Comptabilité SYSCOHADA et à la Caisse, plus les
-- données de départ (plan comptable, journaux, exercice en cours).
--
-- Convention : tous les montants sont en FCFA, entiers ou décimaux à 2
-- chiffres — aucune conversion de devise n'est gérée.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Plan comptable SYSCOHADA révisé
-- ---------------------------------------------------------------------------
create table if not exists compta_comptes (
  code text primary key,
  libelle text not null,
  classe smallint not null check (classe between 1 and 9),
  nature text not null check (nature in ('actif','passif','charge','produit','autre')),
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. Journaux comptables
-- ---------------------------------------------------------------------------
create table if not exists compta_journaux (
  code text primary key,
  libelle text not null
);

-- ---------------------------------------------------------------------------
-- 3. Exercices comptables
-- ---------------------------------------------------------------------------
create table if not exists compta_exercices (
  id uuid primary key default gen_random_uuid(),
  annee int not null unique,
  date_debut date not null,
  date_fin date not null,
  statut text not null default 'ouvert' check (statut in ('ouvert','cloture')),
  cloture_le timestamptz,
  cloture_par text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. Écritures comptables (en-tête)
-- ---------------------------------------------------------------------------
create table if not exists compta_ecritures (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  exercice_annee int not null,
  date_ecriture date not null,
  journal_code text not null references compta_journaux(code),
  piece text,
  libelle text not null,
  projet_id uuid references projets(id) on delete set null,
  source text not null default 'manuel' check (source in ('manuel','auto')),
  source_type text,
  source_id uuid,
  valide_le timestamptz,
  valide_par text,
  contre_passation_de uuid references compta_ecritures(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists idx_compta_ecritures_date on compta_ecritures(date_ecriture);
create index if not exists idx_compta_ecritures_journal on compta_ecritures(journal_code);
create index if not exists idx_compta_ecritures_exercice on compta_ecritures(exercice_annee);
create index if not exists idx_compta_ecritures_source on compta_ecritures(source_type, source_id);

-- ---------------------------------------------------------------------------
-- 5. Lignes d'écriture (partie double)
-- ---------------------------------------------------------------------------
create table if not exists compta_lignes (
  id uuid primary key default gen_random_uuid(),
  ecriture_id uuid not null references compta_ecritures(id) on delete cascade,
  compte_code text not null references compta_comptes(code),
  libelle text,
  sens text not null check (sens in ('D','C')),
  montant numeric(14,2) not null check (montant > 0),
  tiers_type text check (tiers_type in ('client','fournisseur')),
  tiers_id uuid
);
create index if not exists idx_compta_lignes_ecriture on compta_lignes(ecriture_id);
create index if not exists idx_compta_lignes_compte on compta_lignes(compte_code);

-- ---------------------------------------------------------------------------
-- 6. Caisses (multi-caisses)
-- ---------------------------------------------------------------------------
create table if not exists caisses (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  projet_id uuid references projets(id) on delete set null,
  compte_code text not null default '571000' references compta_comptes(code),
  responsable text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 7. Séances de caisse (ouverture/clôture = "brouillard journalier")
-- ---------------------------------------------------------------------------
create table if not exists caisse_sessions (
  id uuid primary key default gen_random_uuid(),
  caisse_id uuid not null references caisses(id) on delete cascade,
  date_session date not null,
  fond_ouverture numeric(14,2) not null default 0,
  fond_cloture_theorique numeric(14,2),
  fond_cloture_reel numeric(14,2),
  ecart numeric(14,2),
  statut text not null default 'ouverte' check (statut in ('ouverte','cloturee')),
  ouverte_par text,
  ouverte_le timestamptz not null default now(),
  cloturee_par text,
  cloturee_le timestamptz,
  ecart_ecriture_id uuid references compta_ecritures(id) on delete set null
);
create index if not exists idx_caisse_sessions_caisse on caisse_sessions(caisse_id);

-- ---------------------------------------------------------------------------
-- 8. Mouvements de caisse (bons d'entrée / sortie)
-- ---------------------------------------------------------------------------
create table if not exists caisse_mouvements (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references caisse_sessions(id) on delete cascade,
  caisse_id uuid not null references caisses(id) on delete cascade,
  numero text,
  date_mouvement date not null,
  type text not null check (type in ('entree','sortie')),
  montant numeric(14,2) not null check (montant > 0),
  motif text not null,
  beneficiaire text,
  piece_ref text,
  statut text not null default 'a_ventiler' check (statut in ('a_ventiler','ventile')),
  compte_ventile text references compta_comptes(code),
  ecriture_id uuid references compta_ecritures(id) on delete set null,
  transfert_id uuid,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists idx_caisse_mvt_session on caisse_mouvements(session_id);
create index if not exists idx_caisse_mvt_caisse on caisse_mouvements(caisse_id);
create index if not exists idx_caisse_mvt_statut on caisse_mouvements(statut);

-- ---------------------------------------------------------------------------
-- 9. Règles de ventilation automatique (apprentissage mot-clé → compte)
-- ---------------------------------------------------------------------------
create table if not exists caisse_regles_ventilation (
  id uuid primary key default gen_random_uuid(),
  mot_cle text not null,
  compte_code text not null references compta_comptes(code),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 10. Paiements / encaissements sur factures (n'existait pas dans l'application :
--     le statut de facture était une simple étiquette manuelle jusqu'ici)
-- ---------------------------------------------------------------------------
create table if not exists paiements (
  id uuid primary key default gen_random_uuid(),
  facture_id uuid not null references factures(id) on delete cascade,
  date_paiement date not null default current_date,
  montant numeric(14,2) not null check (montant > 0),
  mode text not null check (mode in ('espece','banque','mobile_money','cheque')),
  caisse_id uuid references caisses(id) on delete set null,
  reference text,
  ecriture_id uuid references compta_ecritures(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists idx_paiements_facture on paiements(facture_id);

-- ============================================================================
-- SÉCURITÉ (RLS) — même politique simple que le reste de l'app : tout
-- utilisateur authentifié peut lire/écrire. Adaptez si votre projet a des
-- politiques plus fines sur les autres tables.
-- ============================================================================
alter table compta_comptes enable row level security;
alter table compta_journaux enable row level security;
alter table compta_exercices enable row level security;
alter table compta_ecritures enable row level security;
alter table compta_lignes enable row level security;
alter table caisses enable row level security;
alter table caisse_sessions enable row level security;
alter table caisse_mouvements enable row level security;
alter table caisse_regles_ventilation enable row level security;
alter table paiements enable row level security;

do $$
declare t text;
begin
  foreach t in array array['compta_comptes','compta_journaux','compta_exercices','compta_ecritures',
                            'compta_lignes','caisses','caisse_sessions','caisse_mouvements',
                            'caisse_regles_ventilation','paiements']
  loop
    execute format('drop policy if exists "authenticated_all_%1$s" on %1$s', t);
    execute format('create policy "authenticated_all_%1$s" on %1$s for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t);
  end loop;
end $$;

-- ============================================================================
-- DONNÉES DE DÉPART
-- ============================================================================

insert into compta_journaux (code, libelle) values
  ('VE','Journal des Ventes'),
  ('AC','Journal des Achats'),
  ('BQ','Journal de Banque'),
  ('CA','Journal de Caisse'),
  ('MM','Journal Mobile Money'),
  ('OD','Journal des Opérations Diverses'),
  ('AN','Journal des À-Nouveaux'),
  ('CLO','Journal de Clôture')
on conflict (code) do nothing;

insert into compta_exercices (annee, date_debut, date_fin, statut) values
  (extract(year from current_date)::int, make_date(extract(year from current_date)::int,1,1), make_date(extract(year from current_date)::int,12,31), 'ouvert')
on conflict (annee) do nothing;

-- Plan comptable SYSCOHADA révisé (sélection de comptes utiles à une PME de
-- menuiserie aluminium — classes 1, 2, 3, 4, 5, 6, 7, et quelques comptes de
-- la classe 8/9). Vous pouvez en ajouter d'autres depuis l'écran Plan
-- comptable de l'application.
insert into compta_comptes (code, libelle, classe, nature) values
  -- Classe 1 — Ressources durables
  ('101000','Capital social',1,'passif'),
  ('106000','Réserves',1,'passif'),
  ('110000','Report à nouveau créditeur',1,'passif'),
  ('120000','Résultat net de l''exercice (bénéfice)',1,'passif'),
  ('129000','Résultat net de l''exercice (perte)',1,'passif'),
  ('162000','Emprunts auprès des établissements de crédit',1,'passif'),
  ('168000','Autres emprunts et dettes assimilées',1,'passif'),
  -- Classe 2 — Actif immobilisé
  ('213000','Logiciels et sites internet',2,'actif'),
  ('222000','Terrains',2,'actif'),
  ('231000','Bâtiments industriels et administratifs',2,'actif'),
  ('241000','Matériel et outillage industriel (atelier)',2,'actif'),
  ('244000','Matériel et mobilier de bureau',2,'actif'),
  ('245000','Matériel de transport',2,'actif'),
  ('281300','Amortissements des logiciels',2,'actif'),
  ('283100','Amortissements des bâtiments',2,'actif'),
  ('284100','Amortissements du matériel et outillage industriel',2,'actif'),
  ('284500','Amortissements du matériel de transport',2,'actif'),
  -- Classe 3 — Stocks
  ('321000','Matières premières — Profilés aluminium',3,'actif'),
  ('322000','Matières premières — Vitrage',3,'actif'),
  ('323000','Fournitures liées — Quincaillerie & accessoires',3,'actif'),
  ('331000','Autres approvisionnements — Consommables',3,'actif'),
  -- Classe 4 — Tiers
  ('401000','Fournisseurs',4,'passif'),
  ('408000','Fournisseurs — Factures non parvenues',4,'passif'),
  ('409000','Fournisseurs débiteurs — Avances et acomptes versés',4,'actif'),
  ('411000','Clients',4,'actif'),
  ('416000','Clients douteux ou litigieux',4,'actif'),
  ('418000','Clients — Factures à établir',4,'actif'),
  ('419000','Clients créditeurs — Avances et acomptes reçus',4,'passif'),
  ('421000','Personnel — Rémunérations dues',4,'passif'),
  ('422000','Personnel — Avances et acomptes',4,'actif'),
  ('431000','Sécurité sociale (CNPS)',4,'passif'),
  ('441000','État — Impôt sur les bénéfices',4,'passif'),
  ('443000','État — TVA facturée (collectée)',4,'passif'),
  ('445000','État — TVA récupérable',4,'actif'),
  ('444100','État — TVA à décaisser',4,'passif'),
  ('444900','État — Crédit de TVA à reporter',4,'actif'),
  ('447000','État — Autres impôts et taxes',4,'passif'),
  -- Classe 5 — Trésorerie
  ('512000','Banques',5,'actif'),
  ('571000','Caisse principale',5,'actif'),
  ('572000','Caisses secondaires (chantiers)',5,'actif'),
  ('585000','Virements internes (entre caisses / banque)',5,'autre'),
  -- Classe 6 — Charges
  ('601000','Achats de matières premières — Aluminium',6,'charge'),
  ('602000','Achats de fournitures liées — Vitrage, quincaillerie',6,'charge'),
  ('605000','Autres achats (emballages, divers)',6,'charge'),
  ('614000','Transports sur achats et livraisons',6,'charge'),
  ('621000','Sous-traitance générale',6,'charge'),
  ('622000','Locations',6,'charge'),
  ('624000','Entretien, réparations et maintenance',6,'charge'),
  ('625000','Primes d''assurance',6,'charge'),
  ('627000','Publicité, publications, relations publiques',6,'charge'),
  ('628000','Autres charges externes',6,'charge'),
  ('631000','Frais bancaires',6,'charge'),
  ('633000','Frais de formation du personnel',6,'charge'),
  ('638000','Autres charges externes diverses',6,'charge'),
  ('641000','Impôts et taxes directs',6,'charge'),
  ('658000','Charges diverses',6,'charge'),
  ('661000','Rémunérations directes du personnel',6,'charge'),
  ('664000','Charges sociales (CNPS)',6,'charge'),
  ('668000','Autres charges de personnel',6,'charge'),
  ('671000','Intérêts des emprunts',6,'charge'),
  ('678000','Autres charges financières',6,'charge'),
  ('681000','Dotations aux amortissements des immobilisations',6,'charge'),
  -- Classe 7 — Produits
  ('701000','Ventes d''ouvrages menuiserie aluminium',7,'produit'),
  ('706000','Prestations de services (pose, installation)',7,'produit'),
  ('758000','Produits divers',7,'produit'),
  ('771000','Intérêts et produits financiers',7,'produit'),
  -- Classe 8 — HAO / Impôt sur le résultat
  ('891000','Impôts sur le résultat',8,'charge')
on conflict (code) do nothing;

-- Règle de ventilation par défaut : les mouvements de transfert inter-caisses
-- se ventilent automatiquement sur le compte de virement interne.
insert into caisse_regles_ventilation (mot_cle, compte_code)
select 'Transfert', '585000'
where not exists (select 1 from caisse_regles_ventilation where mot_cle = 'Transfert');
