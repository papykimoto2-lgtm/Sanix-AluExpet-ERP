-- ============================================================================
-- Sanix AluExpert ERP — INSTALLATION COMPLÈTE D'UNE NOUVELLE STRUCTURE
-- © Sanix Africa Division Technologies
-- ============================================================================
-- À exécuter UNE FOIS, dans l'éditeur SQL d'un projet Supabase NEUF et VIDE
-- (Supabase → SQL Editor → coller ce fichier → Run).
-- Crée toute la base de l'application : tables, contraintes, fonctions, déclencheurs,
-- règles de sécurité (RLS), et les référentiels de départ (journaux, plan comptable
-- SYSCOHADA de base, catalogue technique du configurateur, dépôt / caisse / point de vente).
-- Aucune donnée d'une autre entreprise n'est incluse.
--
-- Généré à partir de la base de référence ; équivaut à l'ensemble des scripts de sql/
-- (qui restent pour mettre à jour une installation existante).
-- Ensuite : déployer les Edge Functions de supabase/functions/ (connexion, gestion-utilisateurs,
-- fne-proxy), créer config.js, créer le premier compte (administrateur) puis remplir Paramètres → Entreprise.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;
set check_function_bodies = off;   -- les fonctions se référencent entre elles : ordre de création libre

-- ---------------------------------------------------------------------------
-- 1. Compteurs de numérotation et tables
-- ---------------------------------------------------------------------------
create sequence if not exists public.clients_code_seq;
create sequence if not exists public.devis_code_seq;
create sequence if not exists public.factures_code_seq;
create sequence if not exists public.fiches_code_seq;
create sequence if not exists public.fournisseurs_code_seq;
create sequence if not exists public.projets_code_seq;
create sequence if not exists public.prospects_code_seq;

create table if not exists public.caisse_affectations (
  caisse_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.caisse_mouvements (
  id uuid default gen_random_uuid() not null,
  session_id uuid not null,
  caisse_id uuid not null,
  numero text,
  date_mouvement date not null,
  type text not null,
  montant numeric(14,2) not null,
  motif text not null,
  beneficiaire text,
  piece_ref text,
  statut text default 'a_ventiler'::text not null,
  compte_ventile text,
  ecriture_id uuid,
  transfert_id uuid,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.caisse_mouvements_audit (
  id uuid default gen_random_uuid() not null,
  mouvement_id uuid,
  caisse_id uuid,
  numero text,
  action text not null,
  donnees jsonb,
  details jsonb,
  user_email text,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.caisse_pins (
  user_id uuid not null,
  pin_hash text not null,
  echecs integer default 0 not null,
  bloque_jusqu timestamp with time zone,
  defini_par uuid,
  updated_at timestamp with time zone default now() not null
);
create table if not exists public.caisse_regles_ventilation (
  id uuid default gen_random_uuid() not null,
  mot_cle text not null,
  compte_code text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.caisse_sessions (
  id uuid default gen_random_uuid() not null,
  caisse_id uuid not null,
  date_session date not null,
  fond_ouverture numeric(14,2) default 0 not null,
  fond_cloture_theorique numeric(14,2),
  fond_cloture_reel numeric(14,2),
  ecart numeric(14,2),
  statut text default 'ouverte'::text not null,
  ouverte_par text,
  ouverte_le timestamp with time zone default now() not null,
  cloturee_par text,
  cloturee_le timestamp with time zone,
  ecart_ecriture_id uuid,
  ouverte_par_id uuid,
  cloturee_par_id uuid
);
create table if not exists public.caisses (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  projet_id uuid,
  compte_code text default '571000'::text not null,
  responsable text,
  actif boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.client_categories (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.clients (
  id uuid default gen_random_uuid() not null,
  code text default ('C-'::text || (nextval('clients_code_seq'::regclass))::text) not null,
  civilite text default 'Monsieur'::text,
  nom text not null,
  prenoms text,
  entreprise text,
  telephone text,
  email text,
  pays text default 'Côte d''Ivoire'::text,
  commune text,
  quartier text,
  categorie text default 'Particulier'::text,
  adresse text,
  source text,
  commercial text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  ncc text,
  rccm text,
  regime_fiscal text,
  latitude numeric,
  longitude numeric
);
create table if not exists public.composants (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  type text default 'Composant'::text not null,
  famille text default 'Autre'::text not null,
  unite text default 'unite'::text not null,
  prix_unitaire numeric default 0 not null,
  reference text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  code text,
  stock_actuel numeric default 0 not null,
  stock_min numeric default 0 not null,
  stock_max numeric,
  emplacement text,
  cmup numeric default 0 not null,
  standing text default 'standard'::text not null,
  prix_vente numeric
);
create table if not exists public.compta_comptes (
  code text not null,
  libelle text not null,
  classe smallint not null,
  nature text not null,
  actif boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.compta_ecritures (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  exercice_annee integer not null,
  date_ecriture date not null,
  journal_code text not null,
  piece text,
  libelle text not null,
  projet_id uuid,
  source text default 'manuel'::text not null,
  source_type text,
  source_id uuid,
  valide_le timestamp with time zone,
  valide_par text,
  contre_passation_de uuid,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.compta_exercices (
  id uuid default gen_random_uuid() not null,
  annee integer not null,
  date_debut date not null,
  date_fin date not null,
  statut text default 'ouvert'::text not null,
  cloture_le timestamp with time zone,
  cloture_par text,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.compta_journaux (
  code text not null,
  libelle text not null
);
create table if not exists public.compta_lignes (
  id uuid default gen_random_uuid() not null,
  ecriture_id uuid not null,
  compte_code text not null,
  libelle text,
  sens text not null,
  montant numeric(14,2) not null,
  tiers_type text,
  tiers_id uuid
);
create table if not exists public.depots (
  id uuid default gen_random_uuid() not null,
  code text not null,
  nom text not null,
  type text default 'depot'::text not null,
  adresse text,
  commune text,
  responsable text,
  telephone text,
  est_principal boolean default false not null,
  actif boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.devis (
  id uuid default gen_random_uuid() not null,
  code text default ('DVS-'::text || (nextval('devis_code_seq'::regclass))::text) not null,
  libelle text,
  client_id uuid not null,
  projet_id uuid,
  date_creation date default CURRENT_DATE not null,
  date_echeance date,
  statut text default 'en_attente'::text not null,
  categorie text,
  commercial text,
  lieu_affaire text,
  pays text default 'Côte d''Ivoire'::text,
  commune text,
  quartier text,
  reduction numeric default 0 not null,
  autre_frais numeric default 0 not null,
  main_oeuvre numeric default 0 not null,
  total numeric default 0 not null,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  racine_id uuid not null,
  version_number integer default 1 not null,
  is_current boolean default true not null
);
create table if not exists public.devis_categories (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.devis_lignes (
  id uuid default gen_random_uuid() not null,
  devis_id uuid not null,
  piece text default 'Non renseigné'::text not null,
  produit_id uuid,
  titre text not null,
  largeur numeric default 0 not null,
  hauteur numeric default 0 not null,
  quantite numeric default 1 not null,
  remise_pct numeric default 0 not null,
  prix_unitaire numeric default 0 not null,
  total numeric default 0 not null,
  ordre integer default 0 not null,
  created_at timestamp with time zone default now() not null,
  cout_materiel_pct numeric default 60 not null,
  composant_id uuid
);
create table if not exists public.factures (
  id uuid default gen_random_uuid() not null,
  code text default ('FCT-'::text || (nextval('factures_code_seq'::regclass))::text) not null,
  devis_id uuid,
  client_id uuid not null,
  date_facture date default CURRENT_DATE not null,
  total numeric default 0 not null,
  statut text default 'en_attente'::text not null,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  type_facture text default 'simple'::text not null,
  fne_reference text,
  fne_statut text
);
create table if not exists public.fiche_execution_lignes (
  id uuid default gen_random_uuid() not null,
  fiche_id uuid not null,
  devis_ligne_id uuid,
  piece text default 'Non renseigné'::text not null,
  produit text not null,
  largeur_commande numeric,
  hauteur_commande numeric,
  largeur_mesuree numeric,
  hauteur_mesuree numeric,
  fabrication_alu text default ''::text,
  fabrication_vitrage text default ''::text,
  pose_alu text default ''::text,
  pose_vitrage text default ''::text,
  controle_re text default ''::text,
  controle_termine text default ''::text,
  commentaires text default ''::text,
  ordre integer default 0 not null
);
create table if not exists public.fiches_execution (
  id uuid default gen_random_uuid() not null,
  code text default ('FE-'::text || (nextval('fiches_code_seq'::regclass))::text) not null,
  devis_id uuid not null,
  projet_id uuid,
  commercial text,
  lieu_affaire text,
  date_visite date,
  responsable_chantier text,
  statut text default 'en_attente'::text not null,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  updated_at timestamp with time zone default now() not null,
  mesure_prise_par uuid,
  mesure_prise_le timestamp with time zone,
  fabrication_lancee_par uuid,
  fabrication_lancee_le timestamp with time zone
);
create table if not exists public.fournisseurs (
  id uuid default gen_random_uuid() not null,
  code text default ('F-'::text || (nextval('fournisseurs_code_seq'::regclass))::text) not null,
  nom text not null,
  contact_principal text,
  telephone text,
  email text,
  pays text default 'Côte d''Ivoire'::text,
  commune text,
  quartier text,
  categorie text default 'Matériaux'::text,
  adresse text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  ncc text,
  rccm text,
  regime_fiscal text
);
create table if not exists public.mouvements_stock (
  id uuid default gen_random_uuid() not null,
  composant_id uuid not null,
  type text not null,
  quantite numeric not null,
  prix_unitaire numeric,
  stock_apres numeric not null,
  cmup_apres numeric not null,
  motif text,
  reference text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  depot_id uuid,
  transfert_id uuid,
  stock_depot_apres numeric
);
create table if not exists public.paiements (
  id uuid default gen_random_uuid() not null,
  facture_id uuid not null,
  date_paiement date default CURRENT_DATE not null,
  montant numeric(14,2) not null,
  mode text not null,
  caisse_id uuid,
  reference text,
  ecriture_id uuid,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.parametres (
  id uuid default gen_random_uuid() not null,
  raison_sociale text default ''::text not null,
  rccm text,
  ncc text,
  regime_fiscal text default 'reel_simplifie'::text,
  tva_pct numeric default 18 not null,
  adresse text,
  email text,
  telephone text,
  site_web text,
  whatsapp text,
  logo_base64 text,
  derniere_sauvegarde timestamp with time zone,
  updated_at timestamp with time zone default now() not null,
  fne_actif boolean default false not null,
  fne_environnement text default 'test'::text not null,
  fne_api_key text,
  fne_url_test text default 'http://54.247.95.108/ws'::text,
  fne_url_prod text,
  fne_point_vente text default '1'::text,
  fne_etablissement text default 'Principal'::text,
  portail_actif boolean default false not null,
  portail_nom text,
  portail_slogan text,
  portail_couleur text default '#1D3557'::text not null,
  site_a_propos text,
  site_facebook text,
  site_instagram text,
  comptes_defaut jsonb default '{}'::jsonb not null,
  fne_taxe_defaut text default 'TVA'::text not null,
  conditions_documents text
);
create table if not exists public.point_vente_affectations (
  point_vente_id uuid not null,
  user_id uuid not null,
  par_defaut boolean default false not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.points_vente (
  id uuid default gen_random_uuid() not null,
  code text not null,
  nom text not null,
  depot_id uuid not null,
  caisse_id uuid,
  adresse text,
  responsable text,
  telephone text,
  actif boolean default true not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.produits (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  unite text default 'm2'::text not null,
  prix_vente numeric default 0 not null,
  cout_materiel numeric default 0 not null,
  created_at timestamp with time zone default now() not null,
  cout_materiel_pct numeric default 60 not null,
  config_json jsonb,
  alu_ml numeric,
  glass_m2 numeric,
  famille text default 'Autre'::text not null
);
create table if not exists public.profiles (
  id uuid not null,
  nom_complet text,
  role text default 'utilisateur'::text not null,
  created_at timestamp with time zone default now() not null,
  latitude numeric,
  longitude numeric,
  position_updated_at timestamp with time zone
);
create table if not exists public.projets (
  id uuid default gen_random_uuid() not null,
  code text default ('CH-'::text || (nextval('projets_code_seq'::regclass))::text) not null,
  libelle text not null,
  client_id uuid,
  date_debut date,
  date_fin date,
  pays text default 'Côte d''Ivoire'::text,
  commune text,
  quartier text,
  categorie text default 'Habitation'::text,
  source text,
  responsable text,
  description text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  etape text default 'en_attente'::text not null,
  latitude numeric,
  longitude numeric
);
create table if not exists public.prospects (
  id uuid default gen_random_uuid() not null,
  code text default ('P-'::text || (nextval('prospects_code_seq'::regclass))::text) not null,
  civilite text default 'Monsieur'::text,
  nom text not null,
  prenoms text,
  entreprise text,
  telephone text,
  email text,
  pays text default 'Côte d''Ivoire'::text,
  commune text,
  quartier text,
  statut text default 'nouveau'::text not null,
  source text,
  commercial text,
  notes text,
  created_at timestamp with time zone default now() not null,
  created_by uuid,
  latitude numeric,
  longitude numeric
);
create table if not exists public.realisations (
  id uuid default gen_random_uuid() not null,
  titre text not null,
  description text,
  famille text,
  photo_base64 text,
  ordre integer default 0 not null,
  publie boolean default true not null,
  created_at timestamp with time zone default now() not null,
  created_by uuid
);
create table if not exists public.stocks_depot (
  depot_id uuid not null,
  composant_id uuid not null,
  quantite numeric default 0 not null
);
create table if not exists public.transferts_stock (
  id uuid default gen_random_uuid() not null,
  code text,
  depot_source_id uuid not null,
  depot_destination_id uuid not null,
  statut text default 'brouillon'::text not null,
  motif text,
  notes_reception text,
  date_expedition timestamp with time zone,
  date_reception timestamp with time zone,
  expedie_par text,
  recu_par text,
  annule_par text,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.transferts_stock_lignes (
  id uuid default gen_random_uuid() not null,
  transfert_id uuid not null,
  composant_id uuid not null,
  quantite_envoyee numeric not null,
  quantite_recue numeric,
  cmup numeric,
  ordre integer default 0 not null
);
create table if not exists public.ventes_comptoir (
  id uuid default gen_random_uuid() not null,
  code text,
  date_vente date default CURRENT_DATE not null,
  client_id uuid,
  client_nom text,
  client_telephone text,
  sous_total numeric default 0 not null,
  remise numeric default 0 not null,
  total numeric default 0 not null,
  cout_total numeric default 0 not null,
  mode_paiement text default 'espece'::text not null,
  montant_recu numeric,
  monnaie_rendue numeric,
  reference_paiement text,
  caisse_id uuid,
  statut text default 'validee'::text not null,
  ecriture_id uuid,
  motif_annulation text,
  annulee_le timestamp with time zone,
  annulee_par text,
  vendeur text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  point_vente_id uuid,
  depot_id uuid,
  fne_statut text,
  fne_reference text,
  fne_token text,
  fne_invoice_id text,
  fne_template text,
  fne_client_nom text,
  fne_client_ncc text,
  fne_client_telephone text,
  fne_client_email text,
  fne_certifiee_le timestamp with time zone,
  fne_erreur text,
  fne_reponse jsonb,
  fne_avoir_reference text,
  fne_avoir_token text,
  facture_imprimee_le timestamp with time zone,
  client_ncc text,
  client_adresse text
);
create table if not exists public.ventes_comptoir_lignes (
  id uuid default gen_random_uuid() not null,
  vente_id uuid not null,
  composant_id uuid,
  designation text not null,
  unite text,
  quantite numeric not null,
  prix_unitaire numeric default 0 not null,
  prix_achat numeric default 0 not null,
  remise_pct numeric default 0 not null,
  total numeric default 0 not null,
  ordre integer default 0 not null
);

-- ---------------------------------------------------------------------------
-- 2. Clés primaires, unicités, contrôles, clés étrangères, index
-- ---------------------------------------------------------------------------
alter table public.caisse_affectations add constraint caisse_affectations_pkey PRIMARY KEY (caisse_id, user_id);
alter table public.caisse_mouvements add constraint caisse_mouvements_pkey PRIMARY KEY (id);
alter table public.caisse_mouvements_audit add constraint caisse_mouvements_audit_pkey PRIMARY KEY (id);
alter table public.caisse_pins add constraint caisse_pins_pkey PRIMARY KEY (user_id);
alter table public.caisse_regles_ventilation add constraint caisse_regles_ventilation_pkey PRIMARY KEY (id);
alter table public.caisse_sessions add constraint caisse_sessions_pkey PRIMARY KEY (id);
alter table public.caisses add constraint caisses_pkey PRIMARY KEY (id);
alter table public.client_categories add constraint client_categories_pkey PRIMARY KEY (id);
alter table public.clients add constraint clients_pkey PRIMARY KEY (id);
alter table public.composants add constraint composants_pkey PRIMARY KEY (id);
alter table public.compta_comptes add constraint compta_comptes_pkey PRIMARY KEY (code);
alter table public.compta_ecritures add constraint compta_ecritures_pkey PRIMARY KEY (id);
alter table public.compta_exercices add constraint compta_exercices_pkey PRIMARY KEY (id);
alter table public.compta_journaux add constraint compta_journaux_pkey PRIMARY KEY (code);
alter table public.compta_lignes add constraint compta_lignes_pkey PRIMARY KEY (id);
alter table public.depots add constraint depots_pkey PRIMARY KEY (id);
alter table public.devis add constraint devis_pkey PRIMARY KEY (id);
alter table public.devis_categories add constraint devis_categories_pkey PRIMARY KEY (id);
alter table public.devis_lignes add constraint devis_lignes_pkey PRIMARY KEY (id);
alter table public.factures add constraint factures_pkey PRIMARY KEY (id);
alter table public.fiche_execution_lignes add constraint fiche_execution_lignes_pkey PRIMARY KEY (id);
alter table public.fiches_execution add constraint fiches_execution_pkey PRIMARY KEY (id);
alter table public.fournisseurs add constraint fournisseurs_pkey PRIMARY KEY (id);
alter table public.mouvements_stock add constraint mouvements_stock_pkey PRIMARY KEY (id);
alter table public.paiements add constraint paiements_pkey PRIMARY KEY (id);
alter table public.parametres add constraint parametres_pkey PRIMARY KEY (id);
alter table public.point_vente_affectations add constraint point_vente_affectations_pkey PRIMARY KEY (point_vente_id, user_id);
alter table public.points_vente add constraint points_vente_pkey PRIMARY KEY (id);
alter table public.produits add constraint produits_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.projets add constraint projets_pkey PRIMARY KEY (id);
alter table public.prospects add constraint prospects_pkey PRIMARY KEY (id);
alter table public.realisations add constraint realisations_pkey PRIMARY KEY (id);
alter table public.stocks_depot add constraint stocks_depot_pkey PRIMARY KEY (depot_id, composant_id);
alter table public.transferts_stock add constraint transferts_stock_pkey PRIMARY KEY (id);
alter table public.transferts_stock_lignes add constraint transferts_stock_lignes_pkey PRIMARY KEY (id);
alter table public.ventes_comptoir add constraint ventes_comptoir_pkey PRIMARY KEY (id);
alter table public.ventes_comptoir_lignes add constraint ventes_comptoir_lignes_pkey PRIMARY KEY (id);
alter table public.client_categories add constraint client_categories_nom_key UNIQUE (nom);
alter table public.clients add constraint clients_code_key UNIQUE (code);
alter table public.composants add constraint composants_code_standing_key UNIQUE (code, standing);
alter table public.compta_ecritures add constraint compta_ecritures_ref_key UNIQUE (ref);
alter table public.compta_exercices add constraint compta_exercices_annee_key UNIQUE (annee);
alter table public.depots add constraint depots_code_key UNIQUE (code);
alter table public.devis add constraint devis_code_key UNIQUE (code);
alter table public.devis_categories add constraint devis_categories_nom_key UNIQUE (nom);
alter table public.factures add constraint factures_code_key UNIQUE (code);
alter table public.fiches_execution add constraint fiches_execution_code_key UNIQUE (code);
alter table public.fournisseurs add constraint fournisseurs_code_key UNIQUE (code);
alter table public.points_vente add constraint points_vente_code_key UNIQUE (code);
alter table public.projets add constraint projets_code_key UNIQUE (code);
alter table public.prospects add constraint prospects_code_key UNIQUE (code);
alter table public.transferts_stock add constraint transferts_stock_code_key UNIQUE (code);
alter table public.ventes_comptoir add constraint ventes_comptoir_code_key UNIQUE (code);
alter table public.caisse_mouvements add constraint caisse_mouvements_montant_check CHECK ((montant > (0)::numeric));
alter table public.caisse_mouvements add constraint caisse_mouvements_statut_check CHECK ((statut = ANY (ARRAY['a_ventiler'::text, 'ventile'::text])));
alter table public.caisse_mouvements add constraint caisse_mouvements_type_check CHECK ((type = ANY (ARRAY['entree'::text, 'sortie'::text])));
alter table public.caisse_mouvements_audit add constraint caisse_mouvements_audit_action_check CHECK ((action = ANY (ARRAY['modification'::text, 'suppression'::text])));
alter table public.caisse_sessions add constraint caisse_sessions_statut_check CHECK ((statut = ANY (ARRAY['ouverte'::text, 'cloturee'::text])));
alter table public.composants add constraint composants_standing_check CHECK ((standing = ANY (ARRAY['economique'::text, 'standard'::text, 'premium'::text])));
alter table public.composants add constraint composants_type_check CHECK ((type = ANY (ARRAY['Composant'::text, 'Consommable'::text])));
alter table public.composants add constraint composants_unite_check CHECK ((unite = ANY (ARRAY['unite'::text, 'ml'::text, 'm2'::text, 'kg'::text, 'litre'::text, 'boite'::text, 'cartouche'::text])));
alter table public.compta_comptes add constraint compta_comptes_classe_check CHECK (((classe >= 1) AND (classe <= 9)));
alter table public.compta_comptes add constraint compta_comptes_nature_check CHECK ((nature = ANY (ARRAY['actif'::text, 'passif'::text, 'charge'::text, 'produit'::text, 'autre'::text])));
alter table public.compta_ecritures add constraint compta_ecritures_source_check CHECK ((source = ANY (ARRAY['manuel'::text, 'auto'::text])));
alter table public.compta_exercices add constraint compta_exercices_statut_check CHECK ((statut = ANY (ARRAY['ouvert'::text, 'cloture'::text])));
alter table public.compta_lignes add constraint compta_lignes_montant_check CHECK ((montant > (0)::numeric));
alter table public.compta_lignes add constraint compta_lignes_sens_check CHECK ((sens = ANY (ARRAY['D'::text, 'C'::text])));
alter table public.compta_lignes add constraint compta_lignes_tiers_type_check CHECK ((tiers_type = ANY (ARRAY['client'::text, 'fournisseur'::text])));
alter table public.depots add constraint depots_type_check CHECK ((type = ANY (ARRAY['depot'::text, 'magasin'::text, 'atelier'::text, 'chantier'::text])));
alter table public.devis add constraint devis_statut_check CHECK ((statut = ANY (ARRAY['en_attente'::text, 'en_cours'::text, 'accepte'::text, 'refuse'::text, 'annule'::text])));
alter table public.factures add constraint factures_fne_statut_check CHECK ((fne_statut = ANY (ARRAY['certifiee'::text, 'provisoire'::text, 'echec'::text])));
alter table public.factures add constraint factures_statut_check CHECK ((statut = ANY (ARRAY['en_attente'::text, 'payee_partielle'::text, 'payee'::text, 'annulee'::text])));
alter table public.factures add constraint factures_type_facture_check CHECK ((type_facture = ANY (ARRAY['simple'::text, 'fne'::text])));
alter table public.fiches_execution add constraint fiches_execution_statut_check CHECK ((statut = ANY (ARRAY['en_attente'::text, 'en_cours'::text, 'termine'::text])));
alter table public.mouvements_stock add constraint mouvements_stock_type_check CHECK ((type = ANY (ARRAY['entree'::text, 'sortie'::text, 'ajustement'::text, 'inventaire'::text, 'transfert'::text])));
alter table public.paiements add constraint paiements_mode_check CHECK ((mode = ANY (ARRAY['espece'::text, 'banque'::text, 'mobile_money'::text, 'cheque'::text])));
alter table public.paiements add constraint paiements_montant_check CHECK ((montant > (0)::numeric));
alter table public.parametres add constraint parametres_fne_environnement_check CHECK ((fne_environnement = ANY (ARRAY['test'::text, 'production'::text])));
alter table public.parametres add constraint parametres_fne_taxe_defaut_check CHECK ((fne_taxe_defaut = ANY (ARRAY['TVA'::text, 'TVAB'::text, 'TVAC'::text, 'TVAD'::text])));
alter table public.produits add constraint produits_unite_check CHECK ((unite = ANY (ARRAY['m2'::text, 'ml'::text, 'unite'::text])));
alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'manager'::text, 'comptable'::text, 'caissier'::text, 'commercial'::text, 'technicien'::text, 'utilisateur'::text])));
alter table public.projets add constraint projets_etape_check CHECK ((etape = ANY (ARRAY['en_attente'::text, 'mesure_disponible'::text, 'pret_fabrication'::text, 'fabrication_en_cours'::text, 'installation_en_cours'::text, 'termine'::text, 'annule'::text])));
alter table public.prospects add constraint prospects_statut_check CHECK ((statut = ANY (ARRAY['nouveau'::text, 'contacte'::text, 'qualifie'::text, 'gagne'::text, 'perdu'::text])));
alter table public.transferts_stock add constraint transferts_stock_check CHECK ((depot_source_id <> depot_destination_id));
alter table public.transferts_stock add constraint transferts_stock_statut_check CHECK ((statut = ANY (ARRAY['brouillon'::text, 'en_transit'::text, 'recu'::text, 'annule'::text])));
alter table public.transferts_stock_lignes add constraint transferts_stock_lignes_quantite_envoyee_check CHECK ((quantite_envoyee > (0)::numeric));
alter table public.ventes_comptoir add constraint ventes_comptoir_fne_statut_check CHECK ((fne_statut = ANY (ARRAY['certifiee'::text, 'provisoire'::text, 'erreur'::text])));
alter table public.ventes_comptoir add constraint ventes_comptoir_mode_paiement_check CHECK ((mode_paiement = ANY (ARRAY['espece'::text, 'mobile_money'::text, 'banque'::text, 'cheque'::text])));
alter table public.ventes_comptoir add constraint ventes_comptoir_statut_check CHECK ((statut = ANY (ARRAY['validee'::text, 'annulee'::text])));
alter table public.ventes_comptoir_lignes add constraint ventes_comptoir_lignes_quantite_check CHECK ((quantite > (0)::numeric));
alter table public.caisse_affectations add constraint caisse_affectations_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE CASCADE;
alter table public.caisse_affectations add constraint caisse_affectations_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.caisse_mouvements add constraint caisse_mouvements_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE CASCADE;
alter table public.caisse_mouvements add constraint caisse_mouvements_compte_ventile_fkey FOREIGN KEY (compte_ventile) REFERENCES compta_comptes(code);
alter table public.caisse_mouvements add constraint caisse_mouvements_ecriture_id_fkey FOREIGN KEY (ecriture_id) REFERENCES compta_ecritures(id) ON DELETE SET NULL;
alter table public.caisse_mouvements add constraint caisse_mouvements_session_id_fkey FOREIGN KEY (session_id) REFERENCES caisse_sessions(id) ON DELETE CASCADE;
alter table public.caisse_pins add constraint caisse_pins_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.caisse_regles_ventilation add constraint caisse_regles_ventilation_compte_code_fkey FOREIGN KEY (compte_code) REFERENCES compta_comptes(code);
alter table public.caisse_sessions add constraint caisse_sessions_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE CASCADE;
alter table public.caisse_sessions add constraint caisse_sessions_cloturee_par_id_fkey FOREIGN KEY (cloturee_par_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.caisse_sessions add constraint caisse_sessions_ecart_ecriture_id_fkey FOREIGN KEY (ecart_ecriture_id) REFERENCES compta_ecritures(id) ON DELETE SET NULL;
alter table public.caisse_sessions add constraint caisse_sessions_ouverte_par_id_fkey FOREIGN KEY (ouverte_par_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.caisses add constraint caisses_compte_code_fkey FOREIGN KEY (compte_code) REFERENCES compta_comptes(code);
alter table public.caisses add constraint caisses_projet_id_fkey FOREIGN KEY (projet_id) REFERENCES projets(id) ON DELETE SET NULL;
alter table public.clients add constraint clients_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.composants add constraint composants_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.compta_ecritures add constraint compta_ecritures_contre_passation_de_fkey FOREIGN KEY (contre_passation_de) REFERENCES compta_ecritures(id) ON DELETE SET NULL;
alter table public.compta_ecritures add constraint compta_ecritures_journal_code_fkey FOREIGN KEY (journal_code) REFERENCES compta_journaux(code);
alter table public.compta_ecritures add constraint compta_ecritures_projet_id_fkey FOREIGN KEY (projet_id) REFERENCES projets(id) ON DELETE SET NULL;
alter table public.compta_lignes add constraint compta_lignes_compte_code_fkey FOREIGN KEY (compte_code) REFERENCES compta_comptes(code);
alter table public.compta_lignes add constraint compta_lignes_ecriture_id_fkey FOREIGN KEY (ecriture_id) REFERENCES compta_ecritures(id) ON DELETE CASCADE;
alter table public.devis add constraint devis_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE RESTRICT;
alter table public.devis add constraint devis_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.devis add constraint devis_projet_id_fkey FOREIGN KEY (projet_id) REFERENCES projets(id) ON DELETE SET NULL;
alter table public.devis add constraint devis_racine_id_fkey FOREIGN KEY (racine_id) REFERENCES devis(id);
alter table public.devis_lignes add constraint devis_lignes_composant_id_fkey FOREIGN KEY (composant_id) REFERENCES composants(id) ON DELETE SET NULL;
alter table public.devis_lignes add constraint devis_lignes_devis_id_fkey FOREIGN KEY (devis_id) REFERENCES devis(id) ON DELETE CASCADE;
alter table public.devis_lignes add constraint devis_lignes_produit_id_fkey FOREIGN KEY (produit_id) REFERENCES produits(id) ON DELETE SET NULL;
alter table public.factures add constraint factures_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE RESTRICT;
alter table public.factures add constraint factures_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.factures add constraint factures_devis_id_fkey FOREIGN KEY (devis_id) REFERENCES devis(id) ON DELETE SET NULL;
alter table public.fiche_execution_lignes add constraint fiche_execution_lignes_devis_ligne_id_fkey FOREIGN KEY (devis_ligne_id) REFERENCES devis_lignes(id) ON DELETE SET NULL;
alter table public.fiche_execution_lignes add constraint fiche_execution_lignes_fiche_id_fkey FOREIGN KEY (fiche_id) REFERENCES fiches_execution(id) ON DELETE CASCADE;
alter table public.fiches_execution add constraint fiches_execution_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.fiches_execution add constraint fiches_execution_devis_id_fkey FOREIGN KEY (devis_id) REFERENCES devis(id) ON DELETE CASCADE;
alter table public.fiches_execution add constraint fiches_execution_fabrication_lancee_par_fkey FOREIGN KEY (fabrication_lancee_par) REFERENCES auth.users(id);
alter table public.fiches_execution add constraint fiches_execution_mesure_prise_par_fkey FOREIGN KEY (mesure_prise_par) REFERENCES auth.users(id);
alter table public.fiches_execution add constraint fiches_execution_projet_id_fkey FOREIGN KEY (projet_id) REFERENCES projets(id) ON DELETE SET NULL;
alter table public.fournisseurs add constraint fournisseurs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.mouvements_stock add constraint mouvements_stock_composant_id_fkey FOREIGN KEY (composant_id) REFERENCES composants(id) ON DELETE CASCADE;
alter table public.mouvements_stock add constraint mouvements_stock_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.mouvements_stock add constraint mouvements_stock_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE RESTRICT;
alter table public.mouvements_stock add constraint mouvements_stock_transfert_id_fkey FOREIGN KEY (transfert_id) REFERENCES transferts_stock(id) ON DELETE SET NULL;
alter table public.paiements add constraint paiements_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE SET NULL;
alter table public.paiements add constraint paiements_ecriture_id_fkey FOREIGN KEY (ecriture_id) REFERENCES compta_ecritures(id) ON DELETE SET NULL;
alter table public.paiements add constraint paiements_facture_id_fkey FOREIGN KEY (facture_id) REFERENCES factures(id) ON DELETE CASCADE;
alter table public.point_vente_affectations add constraint point_vente_affectations_point_vente_id_fkey FOREIGN KEY (point_vente_id) REFERENCES points_vente(id) ON DELETE CASCADE;
alter table public.point_vente_affectations add constraint point_vente_affectations_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.points_vente add constraint points_vente_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE SET NULL;
alter table public.points_vente add constraint points_vente_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE RESTRICT;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.projets add constraint projets_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL;
alter table public.projets add constraint projets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.prospects add constraint prospects_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.realisations add constraint realisations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.stocks_depot add constraint stocks_depot_composant_id_fkey FOREIGN KEY (composant_id) REFERENCES composants(id) ON DELETE CASCADE;
alter table public.stocks_depot add constraint stocks_depot_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE RESTRICT;
alter table public.transferts_stock add constraint transferts_stock_depot_destination_id_fkey FOREIGN KEY (depot_destination_id) REFERENCES depots(id) ON DELETE RESTRICT;
alter table public.transferts_stock add constraint transferts_stock_depot_source_id_fkey FOREIGN KEY (depot_source_id) REFERENCES depots(id) ON DELETE RESTRICT;
alter table public.transferts_stock_lignes add constraint transferts_stock_lignes_composant_id_fkey FOREIGN KEY (composant_id) REFERENCES composants(id) ON DELETE RESTRICT;
alter table public.transferts_stock_lignes add constraint transferts_stock_lignes_transfert_id_fkey FOREIGN KEY (transfert_id) REFERENCES transferts_stock(id) ON DELETE CASCADE;
alter table public.ventes_comptoir add constraint ventes_comptoir_caisse_id_fkey FOREIGN KEY (caisse_id) REFERENCES caisses(id) ON DELETE SET NULL;
alter table public.ventes_comptoir add constraint ventes_comptoir_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL;
alter table public.ventes_comptoir add constraint ventes_comptoir_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
alter table public.ventes_comptoir add constraint ventes_comptoir_ecriture_id_fkey FOREIGN KEY (ecriture_id) REFERENCES compta_ecritures(id) ON DELETE SET NULL;
alter table public.ventes_comptoir add constraint ventes_comptoir_point_vente_id_fkey FOREIGN KEY (point_vente_id) REFERENCES points_vente(id) ON DELETE SET NULL;
alter table public.ventes_comptoir_lignes add constraint ventes_comptoir_lignes_composant_id_fkey FOREIGN KEY (composant_id) REFERENCES composants(id) ON DELETE SET NULL;
alter table public.ventes_comptoir_lignes add constraint ventes_comptoir_lignes_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES ventes_comptoir(id) ON DELETE CASCADE;

CREATE INDEX idx_caisse_mvt_caisse ON public.caisse_mouvements USING btree (caisse_id);
CREATE INDEX idx_caisse_mvt_session ON public.caisse_mouvements USING btree (session_id);
CREATE INDEX idx_caisse_mvt_statut ON public.caisse_mouvements USING btree (statut);
CREATE INDEX idx_caisse_audit_mvt ON public.caisse_mouvements_audit USING btree (mouvement_id);
CREATE INDEX idx_caisse_sessions_caisse ON public.caisse_sessions USING btree (caisse_id);
CREATE INDEX clients_nom_idx ON public.clients USING btree (nom);
CREATE INDEX idx_compta_ecritures_date ON public.compta_ecritures USING btree (date_ecriture);
CREATE INDEX idx_compta_ecritures_exercice ON public.compta_ecritures USING btree (exercice_annee);
CREATE INDEX idx_compta_ecritures_journal ON public.compta_ecritures USING btree (journal_code);
CREATE INDEX idx_compta_ecritures_source ON public.compta_ecritures USING btree (source_type, source_id);
CREATE INDEX idx_compta_lignes_compte ON public.compta_lignes USING btree (compte_code);
CREATE INDEX idx_compta_lignes_ecriture ON public.compta_lignes USING btree (ecriture_id);
CREATE UNIQUE INDEX depots_un_seul_principal ON public.depots USING btree (est_principal) WHERE est_principal;
CREATE INDEX devis_client_id_idx ON public.devis USING btree (client_id);
CREATE INDEX devis_projet_id_idx ON public.devis USING btree (projet_id);
CREATE INDEX idx_devis_is_current ON public.devis USING btree (is_current);
CREATE INDEX idx_devis_racine ON public.devis USING btree (racine_id);
CREATE INDEX devis_lignes_composant_id_idx ON public.devis_lignes USING btree (composant_id);
CREATE INDEX devis_lignes_devis_id_idx ON public.devis_lignes USING btree (devis_id);
CREATE INDEX factures_client_id_idx ON public.factures USING btree (client_id);
CREATE INDEX factures_devis_id_idx ON public.factures USING btree (devis_id);
CREATE INDEX fiche_execution_lignes_fiche_id_idx ON public.fiche_execution_lignes USING btree (fiche_id);
CREATE INDEX fiches_execution_devis_id_idx ON public.fiches_execution USING btree (devis_id);
CREATE INDEX fournisseurs_nom_idx ON public.fournisseurs USING btree (nom);
CREATE INDEX mouvements_stock_composant_id_idx ON public.mouvements_stock USING btree (composant_id);
CREATE INDEX mouvements_stock_created_at_idx ON public.mouvements_stock USING btree (created_at);
CREATE INDEX idx_paiements_facture ON public.paiements USING btree (facture_id);
CREATE UNIQUE INDEX pva_un_defaut_par_user ON public.point_vente_affectations USING btree (user_id) WHERE par_defaut;
CREATE INDEX projets_client_id_idx ON public.projets USING btree (client_id);
CREATE INDEX projets_etape_idx ON public.projets USING btree (etape);
CREATE INDEX prospects_nom_idx ON public.prospects USING btree (nom);
CREATE INDEX idx_realisations_ordre ON public.realisations USING btree (ordre);
CREATE INDEX idx_stocks_depot_composant ON public.stocks_depot USING btree (composant_id);
CREATE INDEX idx_transferts_lignes_transfert ON public.transferts_stock_lignes USING btree (transfert_id);
CREATE INDEX idx_ventes_comptoir_date ON public.ventes_comptoir USING btree (date_vente);
CREATE INDEX idx_ventes_comptoir_lignes_vente ON public.ventes_comptoir_lignes USING btree (vente_id);

-- ---------------------------------------------------------------------------
-- 3. Fonctions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bump_fiche_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  update fiches_execution set updated_at = now() where id = coalesce(new.fiche_id, old.fiche_id);
  return coalesce(new, old);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.devis_set_racine_id()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.racine_id IS NULL THEN
    NEW.racine_id := NEW.id;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, nom_complet)
  values (new.id, coalesce(new.raw_user_meta_data->>'nom_complet', new.email));
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.portail_lookup(p_code text, p_telephone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_client clients%ROWTYPE;
  v_result jsonb;
  v_digits text := regexp_replace(coalesce(p_telephone,''), '\D', '', 'g');
  v_actif boolean;
BEGIN
  SELECT portail_actif INTO v_actif FROM parametres LIMIT 1;
  IF NOT coalesce(v_actif,false) THEN
    RETURN jsonb_build_object('found', false, 'disabled', true);
  END IF;

  SELECT * INTO v_client
  FROM clients
  WHERE upper(trim(code)) = upper(trim(coalesce(p_code,'')))
    AND regexp_replace(coalesce(telephone,''), '\D', '', 'g') <> ''
    AND right(regexp_replace(coalesce(telephone,''), '\D', '', 'g'), 8) = right(v_digits, 8)
  LIMIT 1;

  IF v_client.id IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  SELECT jsonb_build_object(
    'found', true,
    'client', jsonb_build_object(
      'code', v_client.code, 'nom', v_client.nom, 'prenoms', v_client.prenoms,
      'civilite', v_client.civilite, 'entreprise', v_client.entreprise,
      'commune', v_client.commune
    ),
    'projets', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'code', pr.code, 'libelle', pr.libelle, 'etape', pr.etape,
        'date_debut', pr.date_debut, 'date_fin', pr.date_fin, 'commune', pr.commune
      ) ORDER BY pr.created_at DESC)
      FROM projets pr WHERE pr.client_id = v_client.id
    ), '[]'::jsonb),
    'devis', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'code', d.code, 'libelle', d.libelle, 'statut', d.statut,
        'total', d.total, 'date_creation', d.date_creation
      ) ORDER BY d.created_at DESC)
      FROM devis d WHERE d.client_id = v_client.id
    ), '[]'::jsonb),
    'factures', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'code', f.code, 'statut', f.statut, 'total', f.total,
        'date_facture', f.date_facture, 'type_facture', f.type_facture
      ) ORDER BY f.created_at DESC)
      FROM factures f WHERE f.client_id = v_client.id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

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
  insert into ventes_comptoir (id, code, date_vente, client_id, client_nom, client_telephone, sous_total, remise, total, cout_total,
      mode_paiement, montant_recu, monnaie_rendue, reference_paiement, caisse_id, vendeur, created_by, point_vente_id, depot_id)
    values (coalesce(nullif(p_vente->>'id','')::uuid, gen_random_uuid()), nullif(p_vente->>'code',''),
      coalesce((p_vente->>'date_vente')::date, current_date), nullif(p_vente->>'client_id','')::uuid,
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

create or replace function public.mon_role_code() returns text
language plpgsql stable security definer set search_path = public as $$
declare r text;
begin
  -- Module Utilisateurs & Rôles (sql/utilisateurs_roles.sql) prioritaire s'il est installé
  if to_regclass('public.roles') is not null then
    begin
      execute 'select r.code from profiles p join roles r on r.id = p.role_id where p.id = auth.uid()' into r;
    exception when undefined_column then r := null;
    end;
  end if;
  if r is null then select role into r from profiles where id = auth.uid(); end if;
  return r;
end $$;

create or replace function public.est_gestionnaire_caisse() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.mon_role_code() in ('admin','manager'), false);
$$;

create or replace function public.profiles_proteger_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    -- Le tout premier compte devient administrateur (« Première connexion ») ; les suivants sont
    -- créés « utilisateur » (sauf création par un administrateur), un administrateur leur attribue ensuite un rôle.
    if not exists (select 1 from profiles where role = 'admin') then new.role := 'admin';
    elsif coalesce(public.mon_role_code(),'') <> 'admin' then new.role := 'utilisateur';
    end if;
  elsif new.role is distinct from old.role and auth.uid() is not null
        and coalesce(public.mon_role_code(),'') <> 'admin' then
    raise exception 'Seul un administrateur peut modifier un rôle';
  elsif new.role is distinct from old.role and old.role = 'admin' and new.role <> 'admin'
        and (select count(*) from profiles where role = 'admin') <= 1 then
    raise exception 'Impossible de retirer le dernier administrateur';
  end if;
  return new;
end $$;

create or replace function public.peut_utiliser_caisse(p_caisse_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_gestionnaire_caisse()
      or not exists (select 1 from caisse_affectations where caisse_id = p_caisse_id)
      or exists (select 1 from caisse_affectations where caisse_id = p_caisse_id and user_id = auth.uid());
$$;

create or replace function public.peut_utiliser_point_vente(p_pdv_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_gestionnaire_caisse()
      or not exists (select 1 from point_vente_affectations where point_vente_id = p_pdv_id)
      or exists (select 1 from point_vente_affectations where point_vente_id = p_pdv_id and user_id = auth.uid());
$$;

create or replace function public.definir_pin_caisse(p_user_id uuid, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.est_gestionnaire_caisse() then raise exception 'Réservé aux gestionnaires (admin, manager)'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'Le code PIN doit comporter exactement 4 chiffres'; end if;
  insert into caisse_pins(user_id, pin_hash, echecs, bloque_jusqu, defini_par, updated_at)
    values (p_user_id, crypt(p_pin, gen_salt('bf')), 0, null, auth.uid(), now())
    on conflict (user_id) do update set pin_hash = excluded.pin_hash, echecs = 0, bloque_jusqu = null,
      defini_par = excluded.defini_par, updated_at = now();
end $$;

create or replace function public.supprimer_pin_caisse(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_gestionnaire_caisse() then raise exception 'Réservé aux gestionnaires (admin, manager)'; end if;
  delete from caisse_pins where user_id = p_user_id;
end $$;

create or replace function public.verifier_pin_caisse(p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare p caisse_pins;
begin
  select * into p from caisse_pins where user_id = auth.uid() for update;
  if p.user_id is null then return true; end if;                       -- pas de PIN configuré : pas de blocage
  if p.bloque_jusqu is not null and p.bloque_jusqu > now() then
    raise exception 'Code PIN bloqué après trop d''essais — réessayez après %', to_char(p.bloque_jusqu at time zone 'Africa/Abidjan','HH24:MI');
  end if;
  if coalesce(p_pin,'') <> '' and crypt(p_pin, p.pin_hash) = p.pin_hash then
    update caisse_pins set echecs = 0, bloque_jusqu = null where user_id = auth.uid();
    return true;
  end if;
  update caisse_pins set echecs = echecs + 1,
    bloque_jusqu = case when echecs + 1 >= 5 then now() + interval '10 minutes' else null end
    where user_id = auth.uid();
  return false;
end $$;

create or replace function public.modifier_mon_pin_caisse(p_ancien text, p_nouveau text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_nouveau !~ '^[0-9]{4}$' then return jsonb_build_object('ok',false,'message','Le code PIN doit comporter exactement 4 chiffres'); end if;
  if not exists (select 1 from caisse_pins where user_id = auth.uid()) then
    return jsonb_build_object('ok',false,'message','Aucun code PIN ne vous est attribué — demandez-le à un gestionnaire');
  end if;
  if not public.verifier_pin_caisse(p_ancien) then return jsonb_build_object('ok',false,'message','Ancien code PIN incorrect'); end if;
  update caisse_pins set pin_hash = crypt(p_nouveau, gen_salt('bf')), updated_at = now() where user_id = auth.uid();
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.etat_pins_caisse()
returns table(user_id uuid, a_un_pin boolean, bloque_jusqu timestamptz, echecs int, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, cp.user_id is not null, cp.bloque_jusqu, coalesce(cp.echecs,0), cp.updated_at
  from profiles p left join caisse_pins cp on cp.user_id = p.id
  where public.est_gestionnaire_caisse() or p.id = auth.uid();
$$;

create or replace function public.caisse_ouvrir_session(p_caisse_id uuid, p_fond numeric, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare s caisse_sessions; v_nom text; v_restants int;
begin
  if auth.uid() is null then raise exception 'Non authentifié'; end if;
  if not public.peut_utiliser_caisse(p_caisse_id) then raise exception 'Vous n''êtes pas affecté(e) à cette caisse'; end if;
  if not public.verifier_pin_caisse(p_pin) then
    select greatest(0, 5 - echecs) into v_restants from caisse_pins where user_id = auth.uid();
    return jsonb_build_object('ok',false,'message',
      case when v_restants = 0 then 'Code PIN incorrect — bloqué pendant 10 minutes'
           else 'Code PIN incorrect (' || v_restants || ' essai(s) restant(s))' end);
  end if;
  perform 1 from caisses where id = p_caisse_id for update;
  if exists (select 1 from caisse_sessions where caisse_id = p_caisse_id and statut = 'ouverte') then
    return jsonb_build_object('ok',false,'message','Une séance est déjà ouverte pour cette caisse');
  end if;
  select coalesce(nom_complet, id::text) into v_nom from profiles where id = auth.uid();
  insert into caisse_sessions(caisse_id, date_session, fond_ouverture, statut, ouverte_par, ouverte_par_id)
    values (p_caisse_id, (now() at time zone 'Africa/Abidjan')::date, coalesce(p_fond,0), 'ouverte',
            coalesce((select email from auth.users where id = auth.uid()), v_nom), auth.uid())
    returning * into s;
  return jsonb_build_object('ok',true,'session',to_jsonb(s));
end $$;

create or replace function public.vente_comptoir_controle_affectation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if new.point_vente_id is not null and not public.peut_utiliser_point_vente(new.point_vente_id) then
    raise exception 'Vous n''êtes pas affecté(e) à ce point de vente';
  end if;
  if new.caisse_id is not null and not public.peut_utiliser_caisse(new.caisse_id) then
    raise exception 'Vous n''êtes pas affecté(e) à cette caisse';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Déclencheurs
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_devis_set_racine_id BEFORE INSERT ON public.devis FOR EACH ROW EXECUTE FUNCTION devis_set_racine_id();
CREATE TRIGGER fiche_lignes_bump_updated_at AFTER UPDATE ON public.fiche_execution_lignes FOR EACH ROW EXECUTE FUNCTION bump_fiche_updated_at();
CREATE TRIGGER fiches_execution_set_updated_at BEFORE UPDATE ON public.fiches_execution FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER parametres_set_updated_at BEFORE UPDATE ON public.parametres FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_profiles_proteger_role BEFORE INSERT OR UPDATE OF role ON public.profiles FOR EACH ROW EXECUTE FUNCTION profiles_proteger_role();
CREATE TRIGGER trg_transferts_stock_code BEFORE INSERT ON public.transferts_stock FOR EACH ROW EXECUTE FUNCTION transferts_stock_set_code();
CREATE TRIGGER trg_vente_comptoir_affectation BEFORE INSERT ON public.ventes_comptoir FOR EACH ROW EXECUTE FUNCTION vente_comptoir_controle_affectation();
CREATE TRIGGER trg_ventes_comptoir_code BEFORE INSERT ON public.ventes_comptoir FOR EACH ROW EXECUTE FUNCTION ventes_comptoir_set_code();
-- Création automatique du profil à l'inscription (le premier compte devient administrateur)
drop trigger if exists on_auth_user_created on auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ---------------------------------------------------------------------------
-- 5. Sécurité : RLS et politiques d'accès
-- ---------------------------------------------------------------------------
alter table public.caisse_affectations enable row level security;
alter table public.caisse_mouvements enable row level security;
alter table public.caisse_mouvements_audit enable row level security;
alter table public.caisse_pins enable row level security;
alter table public.caisse_regles_ventilation enable row level security;
alter table public.caisse_sessions enable row level security;
alter table public.caisses enable row level security;
alter table public.client_categories enable row level security;
alter table public.clients enable row level security;
alter table public.composants enable row level security;
alter table public.compta_comptes enable row level security;
alter table public.compta_ecritures enable row level security;
alter table public.compta_exercices enable row level security;
alter table public.compta_journaux enable row level security;
alter table public.compta_lignes enable row level security;
alter table public.depots enable row level security;
alter table public.devis enable row level security;
alter table public.devis_categories enable row level security;
alter table public.devis_lignes enable row level security;
alter table public.factures enable row level security;
alter table public.fiche_execution_lignes enable row level security;
alter table public.fiches_execution enable row level security;
alter table public.fournisseurs enable row level security;
alter table public.mouvements_stock enable row level security;
alter table public.paiements enable row level security;
alter table public.parametres enable row level security;
alter table public.point_vente_affectations enable row level security;
alter table public.points_vente enable row level security;
alter table public.produits enable row level security;
alter table public.profiles enable row level security;
alter table public.projets enable row level security;
alter table public.prospects enable row level security;
alter table public.realisations enable row level security;
alter table public.stocks_depot enable row level security;
alter table public.transferts_stock enable row level security;
alter table public.transferts_stock_lignes enable row level security;
alter table public.ventes_comptoir enable row level security;
alter table public.ventes_comptoir_lignes enable row level security;
-- caisse_pins : RLS sans aucune politique (codes PIN accessibles uniquement via les fonctions)

create policy affect_caisse_gestion on public.caisse_affectations as permissive for all to public using (est_gestionnaire_caisse()) with check (est_gestionnaire_caisse());
create policy affect_caisse_lecture on public.caisse_affectations as permissive for select to public using ((auth.role() = 'authenticated'::text));
create policy authenticated_all_caisse_mouvements on public.caisse_mouvements as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy mouvements_saisie_affectes on public.caisse_mouvements as restrictive for insert to public with check ((peut_utiliser_caisse(caisse_id) OR ((transfert_id IS NOT NULL) AND (type = 'entree'::text))));
create policy audit_caisse_insert on public.caisse_mouvements_audit as permissive for insert to authenticated with check (true);
create policy audit_caisse_select on public.caisse_mouvements_audit as permissive for select to authenticated using (true);
create policy authenticated_all_caisse_regles_ventilation on public.caisse_regles_ventilation as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_caisse_sessions on public.caisse_sessions as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy sessions_modif_affectes on public.caisse_sessions as restrictive for update to public using (peut_utiliser_caisse(caisse_id)) with check (peut_utiliser_caisse(caisse_id));
create policy sessions_ouverture_via_rpc on public.caisse_sessions as restrictive for insert to public with check (est_gestionnaire_caisse());
create policy authenticated_all_caisses on public.caisses as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.client_categories as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.clients as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.composants as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_compta_comptes on public.compta_comptes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_compta_ecritures on public.compta_ecritures as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_compta_exercices on public.compta_exercices as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_compta_journaux on public.compta_journaux as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_compta_lignes on public.compta_lignes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_depots on public.depots as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.devis as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.devis_categories as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.devis_lignes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.factures as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.fiche_execution_lignes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.fiches_execution as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.fournisseurs as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.mouvements_stock as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_paiements on public.paiements as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.parametres as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy affect_pdv_gestion on public.point_vente_affectations as permissive for all to public using (est_gestionnaire_caisse()) with check (est_gestionnaire_caisse());
create policy affect_pdv_lecture on public.point_vente_affectations as permissive for select to public using ((auth.role() = 'authenticated'::text));
create policy authenticated_all_points_vente on public.points_vente as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.produits as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy profiles_authenticated_select on public.profiles as permissive for select to public using ((auth.role() = 'authenticated'::text));
create policy profiles_self_insert on public.profiles as permissive for insert to public with check ((auth.uid() = id));
create policy profiles_self_select on public.profiles as permissive for select to public using ((auth.uid() = id));
create policy profiles_self_update on public.profiles as permissive for update to public using ((auth.uid() = id));
create policy authenticated_full_access on public.projets as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.prospects as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_full_access on public.realisations as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_stocks_depot on public.stocks_depot as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_transferts_stock on public.transferts_stock as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_transferts_stock_lignes on public.transferts_stock_lignes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_ventes_comptoir on public.ventes_comptoir as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));
create policy authenticated_all_ventes_comptoir_lignes on public.ventes_comptoir_lignes as permissive for all to public using ((auth.role() = 'authenticated'::text)) with check ((auth.role() = 'authenticated'::text));

-- Fonctions sensibles : réservées aux utilisateurs connectés ; portail client : accessible au public (anon)
revoke execute on function public.definir_pin_caisse(uuid,text), public.supprimer_pin_caisse(uuid),
  public.verifier_pin_caisse(text), public.modifier_mon_pin_caisse(text,text), public.etat_pins_caisse(),
  public.caisse_ouvrir_session(uuid,numeric,text), public.portail_lookup(text,text) from public;
revoke execute on function public.definir_pin_caisse(uuid,text), public.supprimer_pin_caisse(uuid),
  public.verifier_pin_caisse(text), public.modifier_mon_pin_caisse(text,text), public.etat_pins_caisse(),
  public.caisse_ouvrir_session(uuid,numeric,text) from anon;
grant execute on function public.definir_pin_caisse(uuid,text), public.supprimer_pin_caisse(uuid),
  public.verifier_pin_caisse(text), public.modifier_mon_pin_caisse(text,text), public.etat_pins_caisse(),
  public.caisse_ouvrir_session(uuid,numeric,text) to authenticated;
grant execute on function public.portail_lookup(text,text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Données de départ (référentiels génériques — aucune donnée d'entreprise)
-- ---------------------------------------------------------------------------
insert into public.compta_journaux (code, libelle) values
  ('AC', 'Journal des Achats'),
  ('AN', 'Journal des À-Nouveaux'),
  ('BQ', 'Journal de Banque'),
  ('CA', 'Journal de Caisse'),
  ('CLO', 'Journal de Clôture'),
  ('MM', 'Journal Mobile Money'),
  ('OD', 'Journal des Opérations Diverses'),
  ('VE', 'Journal des Ventes')
on conflict (code) do nothing;

-- Plan comptable SYSCOHADA de base (adaptable dans Comptabilité → Plan comptable)
insert into public.compta_comptes (code, libelle, classe, nature) values
  ('101000', 'Capital social', 1, 'passif'),
  ('106000', 'Réserves', 1, 'passif'),
  ('110000', 'Report à nouveau créditeur', 1, 'passif'),
  ('120000', 'Résultat net de l''exercice (bénéfice)', 1, 'passif'),
  ('129000', 'Résultat net de l''exercice (perte)', 1, 'passif'),
  ('162000', 'Emprunts auprès des établissements de crédit', 1, 'passif'),
  ('168000', 'Autres emprunts et dettes assimilées', 1, 'passif'),
  ('213000', 'Logiciels et sites internet', 2, 'actif'),
  ('222000', 'Terrains', 2, 'actif'),
  ('231000', 'Bâtiments industriels et administratifs', 2, 'actif'),
  ('241000', 'Matériel et outillage industriel (atelier)', 2, 'actif'),
  ('244000', 'Matériel et mobilier de bureau', 2, 'actif'),
  ('245000', 'Matériel de transport', 2, 'actif'),
  ('281300', 'Amortissements des logiciels', 2, 'actif'),
  ('283100', 'Amortissements des bâtiments', 2, 'actif'),
  ('284100', 'Amortissements du matériel et outillage industriel', 2, 'actif'),
  ('284500', 'Amortissements du matériel de transport', 2, 'actif'),
  ('321000', 'Matières premières — Profilés aluminium', 3, 'actif'),
  ('322000', 'Matières premières — Vitrage', 3, 'actif'),
  ('323000', 'Fournitures liées — Quincaillerie & accessoires', 3, 'actif'),
  ('331000', 'Autres approvisionnements — Consommables', 3, 'actif'),
  ('401000', 'Fournisseurs', 4, 'passif'),
  ('408000', 'Fournisseurs — Factures non parvenues', 4, 'passif'),
  ('409000', 'Fournisseurs débiteurs — Avances et acomptes versés', 4, 'actif'),
  ('411000', 'Clients', 4, 'actif'),
  ('416000', 'Clients douteux ou litigieux', 4, 'actif'),
  ('418000', 'Clients — Factures à établir', 4, 'actif'),
  ('419000', 'Clients créditeurs — Avances et acomptes reçus', 4, 'passif'),
  ('421000', 'Personnel — Rémunérations dues', 4, 'passif'),
  ('422000', 'Personnel — Avances et acomptes', 4, 'actif'),
  ('431000', 'Sécurité sociale (CNPS)', 4, 'passif'),
  ('441000', 'État — Impôt sur les bénéfices', 4, 'passif'),
  ('443000', 'État — TVA facturée (collectée)', 4, 'passif'),
  ('444100', 'État — TVA à décaisser', 4, 'passif'),
  ('444900', 'État — Crédit de TVA à reporter', 4, 'actif'),
  ('445000', 'État — TVA récupérable', 4, 'actif'),
  ('447000', 'État — Autres impôts et taxes', 4, 'passif'),
  ('512000', 'Banques', 5, 'actif'),
  ('571000', 'Caisse principale', 5, 'actif'),
  ('572000', 'Caisses secondaires (chantiers)', 5, 'actif'),
  ('585000', 'Virements internes (entre caisses / banque)', 5, 'autre'),
  ('601000', 'Achats de matières premières — Aluminium', 6, 'charge'),
  ('602000', 'Achats de fournitures liées — Vitrage, quincaillerie', 6, 'charge'),
  ('605000', 'Autres achats (emballages, divers)', 6, 'charge'),
  ('614000', 'Transports sur achats et livraisons', 6, 'charge'),
  ('621000', 'Sous-traitance générale', 6, 'charge'),
  ('622000', 'Locations', 6, 'charge'),
  ('624000', 'Entretien, réparations et maintenance', 6, 'charge'),
  ('625000', 'Primes d''assurance', 6, 'charge'),
  ('627000', 'Publicité, publications, relations publiques', 6, 'charge'),
  ('628000', 'Autres charges externes', 6, 'charge'),
  ('631000', 'Frais bancaires', 6, 'charge'),
  ('633000', 'Frais de formation du personnel', 6, 'charge'),
  ('638000', 'Autres charges externes diverses', 6, 'charge'),
  ('641000', 'Impôts et taxes directs', 6, 'charge'),
  ('658000', 'Charges diverses', 6, 'charge'),
  ('661000', 'Rémunérations directes du personnel', 6, 'charge'),
  ('664000', 'Charges sociales (CNPS)', 6, 'charge'),
  ('668000', 'Autres charges de personnel', 6, 'charge'),
  ('671000', 'Intérêts des emprunts', 6, 'charge'),
  ('678000', 'Autres charges financières', 6, 'charge'),
  ('681000', 'Dotations aux amortissements des immobilisations', 6, 'charge'),
  ('701000', 'Ventes d''ouvrages menuiserie aluminium', 7, 'produit'),
  ('706000', 'Prestations de services (pose, installation)', 7, 'produit'),
  ('758000', 'Produits divers', 7, 'produit'),
  ('771000', 'Intérêts et produits financiers', 7, 'produit'),
  ('891000', 'Impôts sur le résultat', 8, 'charge')
on conflict (code) do nothing;

-- Exercice comptable de l'année en cours
insert into public.compta_exercices (annee, date_debut, date_fin, statut)
  select y, make_date(y,1,1), make_date(y,12,31), 'ouvert'
  from (select extract(year from now())::int as y) a
on conflict (annee) do nothing;

-- Structure minimale : dépôt principal, caisse principale, point de vente (renommables dans l'application)
insert into public.depots (code, nom, type, est_principal)
  select 'DEP-01', 'Dépôt principal', 'depot', true where not exists (select 1 from public.depots);
insert into public.caisses (nom, compte_code)
  select 'Caisse principale', '571000' where not exists (select 1 from public.caisses);
insert into public.points_vente (code, nom, depot_id, caisse_id)
  select 'PDV-01', 'Comptoir principal', (select id from public.depots where est_principal),
         (select id from public.caisses order by created_at limit 1)
  where not exists (select 1 from public.points_vente);

-- Paramètres vierges : raison sociale, logo, TVA, FNE, conditions… à renseigner dans Paramètres → Entreprise
insert into public.parametres (raison_sociale) select '' where not exists (select 1 from public.parametres);

-- Catalogue technique du Configurateur d'ouvrage (codes utilisés pour le calcul des débits / BOM).
-- PRIX INDICATIFS en FCFA : à ajuster par la structure (Composants → Catalogue).
insert into public.composants (code, standing, nom, type, famille, unite, prix_unitaire) values
  ('BAR-GI-001', 'standard', 'Barreau vertical inox Ø12mm', 'Composant', 'Profilé aluminium', 'ml', 8200),
  ('BRO-001', 'standard', 'Joint brosse étanchéité', 'Consommable', 'Joint & étanchéité', 'ml', 1100),
  ('CAB-GI-001', 'standard', 'Câble inox Ø6mm tendu', 'Composant', 'Quincaillerie', 'ml', 4.5),
  ('CAD-FJ-001', 'standard', 'Cadre dormant jalousie', 'Composant', 'Profilé aluminium', 'ml', 8500),
  ('CAD-FJ-002', 'standard', 'Montant dormant jalousie', 'Composant', 'Profilé aluminium', 'ml', 8500),
  ('CAD-MO-001', 'standard', 'Cadre aluminium moustiquaire', 'Composant', 'Profilé aluminium', 'ml', 3800),
  ('CAD-MO-002', 'standard', 'Traverse aluminium moustiquaire', 'Composant', 'Profilé aluminium', 'ml', 3800),
  ('CAI-001', 'standard', 'Caisson de galandage', 'Composant', 'Profilé aluminium', 'ml', 14500),
  ('CLI-FJ-001', 'standard', 'Clip de fixation lame', 'Composant', 'Quincaillerie', 'unite', 350),
  ('CON-001', 'standard', 'Silicone', 'Consommable', 'Consommable atelier', 'cartouche', 2800),
  ('JNT-001', 'standard', 'Joint vitrage', 'Consommable', 'Joint & étanchéité', 'ml', 900),
  ('JNT-ABT-001', 'standard', 'Aboutage 90° + vis', 'Composant', 'Visserie & fixations', 'unite', 900),
  ('JNT-EQ-001', 'standard', 'Équerre d''angle mécanique', 'Composant', 'Visserie & fixations', 'unite', 1200),
  ('JNT-ONG-001', 'standard', 'Jonction onglet 45° (colle+sertissage)', 'Composant', 'Visserie & fixations', 'unite', 1500),
  ('LAM-FJ-001', 'standard', 'Lame de verre jalousie 5mm', 'Composant', 'Vitrage', 'm2', 4800),
  ('LOQ-MO-001', 'standard', 'Loquet de fermeture', 'Composant', 'Quincaillerie', 'unite', 1200),
  ('MC-GI-001', 'standard', 'Main courante inox', 'Composant', 'Profilé aluminium', 'ml', 16800),
  ('MEC-FJ-001', 'standard', 'Mécanisme à manivelle', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('P-PAR-001', 'standard', 'Parclose', 'Composant', 'Profilé aluminium', 'ml', 3200),
  ('P-SEU-001', 'standard', 'Seuil bas renforcé', 'Composant', 'Profilé aluminium', 'ml', 11500),
  ('P-STD-001', 'standard', 'Dormant horizontal', 'Composant', 'Profilé aluminium', 'ml', 8500),
  ('P-STD-002', 'standard', 'Dormant vertical', 'Composant', 'Profilé aluminium', 'ml', 8500),
  ('P-STD-003', 'standard', 'Ouvrant horizontal', 'Composant', 'Profilé aluminium', 'ml', 9200),
  ('P-STD-004', 'standard', 'Ouvrant vertical', 'Composant', 'Profilé aluminium', 'ml', 9200),
  ('PIN-GI-001', 'standard', 'Pince de fixation verre inox', 'Composant', 'Quincaillerie', 'unite', 2400),
  ('PLA-GI-001', 'standard', 'Platine fixation inox', 'Composant', 'Quincaillerie', 'unite', 3800),
  ('POT-GI-001', 'standard', 'Poteau inox tube 42.4mm', 'Composant', 'Profilé aluminium', 'ml', 22500),
  ('QUI-001', 'standard', 'Poignée', 'Composant', 'Quincaillerie', 'unite', 4500),
  ('QUI-001-PORTE', 'standard', 'Ensemble serrure + poignée', 'Composant', 'Quincaillerie', 'unite', 12500),
  ('QUI-002', 'standard', 'Paumelle', 'Composant', 'Quincaillerie', 'unite', 850),
  ('QUI-002-GALANDAGE', 'standard', 'Roulette renforcée galandage', 'Composant', 'Quincaillerie', 'unite', 2100),
  ('QUI-002-PORTE', 'standard', 'Paumelle renforcée', 'Composant', 'Quincaillerie', 'unite', 1600),
  ('QUI-003', 'standard', 'Gâche + ferme-porte', 'Composant', 'Quincaillerie', 'unite', 7800),
  ('RAI-MO-001', 'standard', 'Rail coulissant moustiquaire', 'Composant', 'Profilé aluminium', 'ml', 4200),
  ('RAIL-001', 'standard', 'Rail double renforcé galandage', 'Composant', 'Profilé aluminium', 'ml', 12800),
  ('ROU-MO-001', 'standard', 'Roulette coulissante', 'Composant', 'Quincaillerie', 'unite', 950),
  ('SAN-001', 'standard', 'Sangle de finition caisson', 'Composant', 'Visserie & fixations', 'ml', 3500),
  ('TEN-GI-001', 'standard', 'Tendeur + terminaison sertie', 'Composant', 'Quincaillerie', 'unite', 1800),
  ('TUL-MO-001', 'standard', 'Toile moustiquaire (fibre de verre)', 'Consommable', 'Vitrage', 'm2', 3200),
  ('VIT-001', 'standard', 'Double vitrage 6/12/6', 'Composant', 'Vitrage', 'm2', 6500),
  ('VIT-GI-001', 'standard', 'Verre feuilleté sécurit', 'Composant', 'Vitrage', 'm2', 9500)
on conflict (code, standing) do nothing;

reset check_function_bodies;

-- ===========================================================================
-- 7. Utilisateurs, rôles et droits par module (copie de sql/utilisateurs_roles.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Module Utilisateurs, Rôles & Accès (à l'image de ImmoSuite)
-- ============================================================================
-- À exécuter dans l'éditeur SQL Supabase, APRÈS sql/comptabilite_syscohada.sql
-- et sql/parametres_comptes_defaut.sql. Additif : crée 3 nouvelles tables
-- (roles, role_permissions, invitations) et ajoute 2 colonnes à `profiles`
-- (déjà existante). Aucune table existante n'est modifiée en profondeur.
--
-- Modèle : chaque rôle porte, pour chaque module de l'application, 5 droits
-- indépendants (voir/créer/modifier/supprimer/valider). Contrairement à
-- ImmoSuite (où l'absence de restriction sur un module = tout autorisé),
-- ici chaque couple (rôle, module) a une ligne explicite dans
-- role_permissions — pas de valeur implicite, pour éviter les angles morts
-- de sécurité. Règle absolue conservée d'ImmoSuite : seuls les rôles
-- « admin » et « manager » peuvent supprimer, même si un rôle personnalisé
-- coche « supprimer » sur un module (contrôlée côté application).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Rôles
-- ----------------------------------------------------------------------------
create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  label text not null,
  icon text not null default '👤',
  niveau int not null default 1,
  est_systeme boolean not null default false,
  peut_supprimer boolean not null default true,
  plafond_validation numeric(14,2),
  description text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. Permissions par rôle et par module
-- ----------------------------------------------------------------------------
create table if not exists role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  module_code text not null,
  peut_voir boolean not null default false,
  peut_creer boolean not null default false,
  peut_modifier boolean not null default false,
  peut_supprimer boolean not null default false,
  peut_valider boolean not null default false,
  primary key (role_id, module_code)
);

-- ----------------------------------------------------------------------------
-- 3. Invitations (l'application n'a pas d'API admin Supabase côté client : on ne
--    peut pas créer un compte auth pour quelqu'un d'autre. Une invitation
--    pré-attribue un rôle à un email ; quand cette personne s'inscrit via
--    l'écran de connexion existant, le rôle lui est attribué automatiquement)
-- ----------------------------------------------------------------------------
create table if not exists invitations (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  role_id uuid not null references roles(id),
  statut text not null default 'en_attente' check (statut in ('en_attente','acceptee')),
  invited_by uuid,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

-- ----------------------------------------------------------------------------
-- 4. Rattachement d'un rôle et d'un statut actif/inactif à chaque profil
-- ----------------------------------------------------------------------------
alter table profiles add column if not exists role_id uuid references roles(id);
alter table profiles add column if not exists actif boolean not null default true;
-- `profiles` n'avait pas de colonne email (l'email vit dans auth.users, non
-- lisible par le client). On la duplique ici pour l'affichage dans l'écran
-- Utilisateurs et le rapprochement des invitations ; elle se renseigne toute
-- seule à la prochaine connexion de chaque utilisateur (voir index.html).
alter table profiles add column if not exists email text;

-- ----------------------------------------------------------------------------
-- 5. Sécurité — RLS + garde-fou anti élévation de privilège
-- ----------------------------------------------------------------------------
alter table roles enable row level security;
alter table role_permissions enable row level security;
alter table invitations enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable as $$
  select exists(
    select 1 from profiles p join roles r on r.id = p.role_id
    where p.id = auth.uid() and r.code = 'admin'
  );
$$;

drop policy if exists "roles_select" on roles;
create policy "roles_select" on roles for select using (auth.role() = 'authenticated');
drop policy if exists "roles_insert_admin" on roles;
create policy "roles_insert_admin" on roles for insert with check (public.is_admin());
drop policy if exists "roles_update_admin" on roles;
create policy "roles_update_admin" on roles for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "roles_delete_admin" on roles;
create policy "roles_delete_admin" on roles for delete using (public.is_admin());

drop policy if exists "role_permissions_select" on role_permissions;
create policy "role_permissions_select" on role_permissions for select using (auth.role() = 'authenticated');
drop policy if exists "role_permissions_insert_admin" on role_permissions;
create policy "role_permissions_insert_admin" on role_permissions for insert with check (public.is_admin());
drop policy if exists "role_permissions_update_admin" on role_permissions;
create policy "role_permissions_update_admin" on role_permissions for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "role_permissions_delete_admin" on role_permissions;
create policy "role_permissions_delete_admin" on role_permissions for delete using (public.is_admin());

drop policy if exists "invitations_select" on invitations;
create policy "invitations_select" on invitations for select using (public.is_admin() or email = (auth.jwt()->>'email'));
drop policy if exists "invitations_insert_admin" on invitations;
create policy "invitations_insert_admin" on invitations for insert with check (public.is_admin());
drop policy if exists "invitations_update" on invitations;
create policy "invitations_update" on invitations for update
  using (public.is_admin() or email = (auth.jwt()->>'email'))
  with check (public.is_admin() or email = (auth.jwt()->>'email'));
drop policy if exists "invitations_delete_admin" on invitations;
create policy "invitations_delete_admin" on invitations for delete using (public.is_admin());

-- Garde-fou indépendant de la policy RLS existante sur `profiles` (que cette
-- migration ne connaît pas et ne modifie pas) : quel que soit ce que cette
-- policy autorise déjà, ce trigger empêche un utilisateur non-admin de
-- modifier son propre rôle ou son statut actif une fois qu'un rôle lui a
-- déjà été attribué. Exception nécessaire : un profil qui n'a PAS encore de
-- rôle (role_id IS NULL, cas d'une inscription qui vient d'avoir lieu) peut
-- recevoir son rôle initial — c'est ce qui permet à l'inscription et au
-- mécanisme d'invitation de fonctionner sans intervention manuelle.
create or replace function public.proteger_role_profil() returns trigger
language plpgsql as $$
declare
  appelant_admin boolean;
begin
  if new.role_id is distinct from old.role_id or new.actif is distinct from old.actif then
    select public.is_admin() into appelant_admin;
    if not appelant_admin and old.role_id is not null then
      new.role_id := old.role_id;
      new.actif := old.actif;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_proteger_role_profil on profiles;
create trigger trg_proteger_role_profil before update on profiles
for each row execute function public.proteger_role_profil();

-- ----------------------------------------------------------------------------
-- 6. Rôles système + matrice de permissions par défaut
-- ----------------------------------------------------------------------------
do $$
declare
  rid uuid;
  m text;
  tous_modules text[] := array['Clients','Prospects','Fournisseurs','Projets','Devis','Factures',
                                'FichesExecution','Produits','Composants','Stock','Comptabilite',
                                'Caisse','Comptoir','Realisations','Utilisateurs','Parametres'];
begin
  -- ADMINISTRATEUR : accès total, y compris Utilisateurs et Paramètres
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('admin','Administrateur','👑',4,true,true,null,'Accès complet à tous les modules, y compris Utilisateurs et Paramètres.')
    on conflict (code) do nothing;
  select id into rid from roles where code='admin';
  foreach m in array tous_modules loop
    insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
      values (rid,m,true,true,true,true,true) on conflict (role_id,module_code) do nothing;
  end loop;

  -- MANAGER : tout sauf Comptabilité, Utilisateurs, Paramètres
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('manager','Manager','🧭',3,true,true,null,'Gestion opérationnelle complète (commercial, chantiers, stock) — sans accès à la Comptabilité ni aux Paramètres.')
    on conflict (code) do nothing;
  select id into rid from roles where code='manager';
  foreach m in array tous_modules loop
    if m in ('Comptabilite','Utilisateurs','Parametres') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,true,true) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMPTABLE : Comptabilité/Caisse/Factures/Fournisseurs en création-modif (pas suppression),
  -- consultation sur le reste, aucun accès à Utilisateurs/Paramètres/Prospects
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('comptable','Comptable','📗',2,true,false,1000000,'Comptabilité SYSCOHADA, Caisse, Factures et Fournisseurs — sans droit de suppression.')
    on conflict (code) do nothing;
  select id into rid from roles where code='comptable';
  foreach m in array tous_modules loop
    if m in ('Comptabilite','Caisse','Factures','Fournisseurs') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,true) on conflict (role_id,module_code) do nothing;
    elsif m in ('Clients','Devis','Projets','Stock','Produits','Composants','Realisations','FichesExecution','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMMERCIAL : Clients/Prospects/Devis en création-modif, consultation sur le reste du cycle de vente
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('commercial','Commercial','🤝',1,true,false,null,'Clients, prospects et devis — sans droit de suppression, sans accès à la Comptabilité ni à la Caisse.')
    on conflict (code) do nothing;
  select id into rid from roles where code='commercial';
  foreach m in array tous_modules loop
    if m in ('Clients','Prospects','Devis','Realisations','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,true) on conflict (role_id,module_code) do nothing;
    elsif m in ('Projets','FichesExecution','Produits','Composants','Stock','Factures') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- CAISSIÈRE : Caisse en création-modif uniquement (ni suppression, ni validation —
  -- ségrégation des tâches), simple consultation de la Comptabilité
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('caissiere','Caissier(ère)','💰',1,true,false,100000,'Bons d''entrée/sortie de caisse — sans suppression ni validation, pour la ségrégation des tâches.')
    on conflict (code) do nothing;
  select id into rid from roles where code='caissiere';
  foreach m in array tous_modules loop
    if m in ('Caisse','Comptoir') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,true,true,false,false) on conflict (role_id,module_code) do nothing;
    elsif m='Comptabilite' then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- COMMISSAIRE (auditeur externe) : consultation seule sur tous les modules financiers/métier
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('commissaire','Commissaire aux comptes','🔍',1,true,false,0,'Consultation uniquement — aucune création, modification, suppression ou validation.')
    on conflict (code) do nothing;
  select id into rid from roles where code='commissaire';
  foreach m in array tous_modules loop
    if m in ('Utilisateurs','Parametres') then
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
    else
      insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
        values (rid,m,true,false,false,false,false) on conflict (role_id,module_code) do nothing;
    end if;
  end loop;

  -- SANS RÔLE : aucun accès — attribué par défaut à toute inscription sans invitation
  -- lorsqu'un compte administrateur existe déjà (empêche un inconnu de s'auto-attribuer
  -- un accès en s'inscrivant sur l'écran de connexion public)
  insert into roles(code,label,icon,niveau,est_systeme,peut_supprimer,plafond_validation,description)
    values ('sans_role','Sans rôle (en attente)','🚫',0,true,false,0,'Compte créé sans invitation : aucun accès tant qu''un administrateur n''attribue un rôle.')
    on conflict (code) do nothing;
  select id into rid from roles where code='sans_role';
  foreach m in array tous_modules loop
    insert into role_permissions(role_id,module_code,peut_voir,peut_creer,peut_modifier,peut_supprimer,peut_valider)
      values (rid,m,false,false,false,false,false) on conflict (role_id,module_code) do nothing;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 7. Migration des comptes déjà existants : conserve leur accès complet actuel
--    (aujourd'hui, sans notion de rôle, TOUT utilisateur connecté a un accès
--    complet — on ne restreint donc personne rétroactivement, seuls les
--    NOUVEAUX comptes créés après cette migration seront concernés par le
--    rôle « Sans rôle » par défaut).
-- ----------------------------------------------------------------------------
-- Si un rôle texte existe déjà (profiles.role, cf. sql/affectations_caisse_pdv.sql), on le reprend ;
-- « utilisateur » / « technicien » (sans équivalent) → « sans rôle » ; profil sans rôle du tout → administrateur
-- (comportement historique : avant ce module, tout compte connecté avait un accès complet).
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='role') then
    execute $q$
      update profiles p set role_id = r.id from roles r
      where p.role_id is null and p.role is not null
        and r.code = case p.role when 'caissier' then 'caissiere' when 'utilisateur' then 'sans_role'
                                 when 'technicien' then 'sans_role' else p.role end $q$;
  end if;
end $$;
update profiles set role_id = (select id from roles where code = 'admin') where role_id is null;

-- ===========================================================================
-- 8. Comptes, connexion et sécurité à la manière de Menko Immo
--    (copie de sql/utilisateurs_auth_menko.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Comptes utilisateurs à la manière de Menko Immo
-- ============================================================================
-- À exécuter APRÈS sql/utilisateurs_roles.sql (rôles & droits par module) et
-- sql/affectations_caisse_pdv.sql. Reprend le fonctionnement de Menko Immo :
--   • comptes créés par un administrateur (identifiant + mot de passe provisoire),
--     plus d'inscription libre (sauf le tout premier compte, qui devient administrateur) ;
--   • connexion par identifiant OU e-mail (Edge Function « connexion ») avec blocage
--     après 5 échecs sur 24 h et journal des connexions (IP, navigateur) ;
--   • changement de mot de passe obligatoire à la première connexion / après réinitialisation ;
--   • activation / désactivation des comptes, déconnexion forcée de tous les postes,
--     déconnexion après inactivité (paramétrable).
-- En plus de Menko, appliqué DANS LA BASE : un compte désactivé, « sans rôle » ou devant
-- changer son mot de passe n'a accès à AUCUNE donnée (politiques RLS restrictives).
-- L'authentification reste celle de Supabase (sessions signées, RLS) : pas de table de
-- mots de passe maison.
-- ============================================================================

-- ---------- Profils : colonnes Menko ----------
alter table profiles add column if not exists login text;
alter table profiles add column if not exists telephone text;
alter table profiles add column if not exists must_change boolean not null default false;
alter table profiles add column if not exists derniere_connexion timestamptz;
alter table profiles add column if not exists cree_par uuid;
create unique index if not exists profiles_login_unique on profiles (lower(login)) where login is not null;

-- Identifiant proposé à partir d'un e-mail (début de l'adresse, rendu unique)
create or replace function public.login_depuis_email(p_email text) returns text
language plpgsql stable security definer set search_path = public as $$
declare base text; cand text; n int := 1;
begin
  base := lower(regexp_replace(split_part(coalesce(p_email,''),'@',1), '[^a-zA-Z0-9._-]', '', 'g'));
  base := left(regexp_replace(base, '^[^a-z0-9]+', ''), 26);
  if length(base) < 3 then base := base || 'utilisateur'; end if;
  cand := base;
  while exists (select 1 from profiles where lower(login) = cand) loop n := n + 1; cand := base || n; end loop;
  return cand;
end $$;

-- E-mail et identifiant des comptes existants
update profiles p set email = u.email from auth.users u where u.id = p.id and p.email is null;
do $$
declare r record;
begin
  for r in select id, email from profiles where login is null and email is not null order by created_at loop
    update profiles set login = public.login_depuis_email(r.email) where id = r.id;
  end loop;
end $$;

-- Nouveaux comptes : le profil reçoit aussi l'e-mail et un identifiant (modifiable ensuite)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nom_complet, email, login)
  values (new.id, coalesce(new.raw_user_meta_data->>'nom_complet', new.email),
          case when new.email like '%@comptes.aluexpert.local' then null else new.email end,
          public.login_depuis_email(new.email));
  return new;
end $$;

-- ---------- Rôle texte = reflet du rôle attribué (roles.code) ----------
-- Les rôles sont désormais dynamiques (rôles personnalisés possibles) : plus de liste figée.
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles alter column role drop default;
alter table profiles alter column role drop not null;

create or replace function public.profiles_garde_et_role() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_admin uuid; v_sans uuid; v_nb_admins int; appelant_admin boolean;
begin
  select id into v_admin from roles where code = 'admin';
  select id into v_sans from roles where code = 'sans_role';
  appelant_admin := public.is_admin();

  if tg_op = 'INSERT' then
    -- Rôle initial : le tout premier compte devient administrateur ; ensuite « sans rôle »,
    -- sauf création par un administrateur ou par le serveur (Edge Function, service role).
    if auth.uid() is not null and not appelant_admin then new.role_id := null; end if;
    if new.role_id is null then
      new.role_id := case when exists (select 1 from profiles where role_id = v_admin) then v_sans else v_admin end;
    end if;
  else
    -- Champs réservés à un administrateur (ou au serveur / aux fonctions autorisées)
    if auth.uid() is not null and not appelant_admin
       and coalesce(current_setting('app.maj_compte_autorisee', true), '') <> '1' then
      new.role_id := old.role_id; new.actif := old.actif; new.login := old.login;
      new.must_change := old.must_change; new.cree_par := old.cree_par;
    end if;
    -- Jamais moins d'un administrateur actif
    if old.role_id = v_admin and old.actif and (new.role_id is distinct from v_admin or not new.actif) then
      select count(*) into v_nb_admins from profiles where role_id = v_admin and actif and id <> old.id;
      if v_nb_admins = 0 then raise exception 'Impossible : ce compte est le dernier administrateur actif'; end if;
    end if;
  end if;
  new.role := (select code from roles where id = new.role_id);
  return new;
end $$;
drop trigger if exists trg_proteger_role_profil on profiles;         -- remplacé par la garde ci-dessous
drop trigger if exists trg_profiles_proteger_role on profiles;       -- idem (ancienne garde sur le rôle texte)
drop trigger if exists trg_zz_profiles_garde_et_role on profiles;
create trigger trg_zz_profiles_garde_et_role before insert or update on profiles
  for each row execute function public.profiles_garde_et_role();
-- Un administrateur peut modifier les profils des autres (rôle, statut…) ; chacun garde la main sur le sien
drop policy if exists "profiles_admin_update" on profiles;
create policy "profiles_admin_update" on profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
-- Réaligne le rôle texte des comptes existants
update profiles p set role = r.code from roles r where r.id = p.role_id and p.role is distinct from r.code;

-- ---------- Accès aux données : comptes actifs, avec rôle, mot de passe à jour ----------
create or replace function public.est_utilisateur_autorise() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p join roles r on r.id = p.role_id
    where p.id = auth.uid() and p.actif and not p.must_change and r.code <> 'sans_role'
  );
$$;
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
             and c.relname not in ('profiles','roles','role_permissions','invitations','logs_connexion','caisse_pins')
  loop
    execute format('drop policy if exists "acces_comptes_autorises" on public.%I', t);
    execute format('create policy "acces_comptes_autorises" on public.%I as restrictive for all to authenticated using (public.est_utilisateur_autorise()) with check (public.est_utilisateur_autorise())', t);
  end loop;
end $$;

-- ---------- Journal des connexions (écrit par l'Edge Function « connexion ») ----------
create table if not exists logs_connexion (
  id uuid primary key default gen_random_uuid(),
  login_saisi text not null,
  user_id uuid references profiles(id) on delete set null,
  succes boolean not null,
  detail text,
  ip text,
  user_agent text,
  created_at timestamptz not null default now()
);
create index if not exists idx_logs_connexion_login on logs_connexion (login_saisi, created_at desc);
create index if not exists idx_logs_connexion_date on logs_connexion (created_at desc);
alter table logs_connexion enable row level security;
drop policy if exists "logs_connexion_admin" on logs_connexion;
create policy "logs_connexion_admin" on logs_connexion for select to authenticated using (public.is_admin());

-- ---------- Paramètres de session ----------
alter table parametres add column if not exists session_inactivite_min int not null default 30;   -- 0 = désactivé
alter table parametres add column if not exists deconnexion_forcee_le timestamptz;

-- ---------- Fonctions appelées par l'application ----------
-- Installation vierge ? (affiche « Créer le compte administrateur » sur l'écran de connexion)
create or replace function public.installation_vierge() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles p join roles r on r.id = p.role_id where r.code = 'admin');
$$;
-- Après un changement de mot de passe obligatoire (le mot de passe est changé via Supabase Auth)
create or replace function public.mot_de_passe_change() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Non authentifié'; end if;
  perform set_config('app.maj_compte_autorisee', '1', true);
  update profiles set must_change = false where id = auth.uid();
end $$;
-- Déconnecte tous les postes (chaque application vérifie cette date toutes les minutes)
create or replace function public.forcer_deconnexion_generale() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v timestamptz := now();
begin
  if not public.is_admin() then raise exception 'Réservé à un administrateur'; end if;
  update parametres set deconnexion_forcee_le = v where true;
  return v;
end $$;
revoke execute on function public.mot_de_passe_change(), public.forcer_deconnexion_generale() from public, anon;
grant execute on function public.mot_de_passe_change(), public.forcer_deconnexion_generale() to authenticated;
grant execute on function public.installation_vierge() to anon, authenticated;

-- ===========================================================================
-- 9. Chantiers : rattachement des mouvements de caisse et de stock (copie de sql/chantiers_caisse_stock.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Rattacher les mouvements de caisse et de stock au chantier d'un client
-- ============================================================================
-- Un bon d'entrée / de sortie de caisse et un mouvement de stock peuvent désormais être
-- rattachés à un chantier (projet) : suivi des dépenses et des matériaux par chantier,
-- écriture comptable de ventilation rattachée au même chantier.
-- ============================================================================
alter table public.caisse_mouvements add column if not exists projet_id uuid references public.projets(id) on delete set null;
alter table public.mouvements_stock add column if not exists projet_id uuid references public.projets(id) on delete set null;
create index if not exists idx_caisse_mvt_projet on public.caisse_mouvements (projet_id);
create index if not exists idx_mouvements_stock_projet on public.mouvements_stock (projet_id);

-- Reprise de l'existant : mouvements d'une caisse de chantier → ce chantier ;
-- sorties de stock d'une fiche d'exécution → le chantier de la fiche
update public.caisse_mouvements m set projet_id = c.projet_id
  from public.caisses c where c.id = m.caisse_id and c.projet_id is not null and m.projet_id is null;
update public.mouvements_stock ms set projet_id = f.projet_id
  from public.fiches_execution f
  where ms.reference = f.code and ms.motif = 'Fiche d''exécution' and f.projet_id is not null and ms.projet_id is null;

-- Mouvement de stock : paramètre facultatif p_projet_id (les appels existants restent valables)
drop function if exists public.stock_mouvement(uuid, text, numeric, text, text, numeric, uuid, uuid);
create or replace function public.stock_mouvement(p_composant_id uuid, p_type text, p_quantite numeric,
  p_motif text default null, p_reference text default null, p_prix_unitaire numeric default null,
  p_depot_id uuid default null, p_transfert_id uuid default null, p_projet_id uuid default null)
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
                                created_by, depot_id, transfert_id, stock_depot_apres, projet_id)
    values (p_composant_id, p_type, v_delta, p_prix_unitaire, v_comp.stock_actuel, v_new_cmup, p_motif, p_reference,
            auth.uid(), v_depot, p_transfert_id, v_qte_depot + v_delta, p_projet_id);
  return v_comp;
end $$;

-- ===========================================================================
-- 10. Circuit de validation DG des mouvements de caisse (copie de sql/validation_dg.sql)
-- ===========================================================================
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

-- ===========================================================================
-- 11. Catalogue étendu d'ouvrages du Configurateur (copie de sql/catalogue_ouvrages.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Catalogue étendu d'ouvrages (menuiserie aluminium & inox)
-- ============================================================================
-- Composants utilisés par les ~77 nouveaux ouvrages du Configurateur (fenêtres, coulissants, portes,
-- façades, fermetures, pergolas, garde-corps, portails, douche, composite). PRIX INDICATIFS en FCFA,
-- à ajuster dans Composants & consommables. Les composants déjà présents ne sont pas modifiés.
-- ============================================================================
insert into public.composants (code, standing, nom, type, famille, unite, prix_unitaire) values
  ('P-MEN-001', 'standard', 'Meneau / traverse aluminium', 'Composant', 'Profilé aluminium', 'ml', 9800),
  ('P-COU-RH', 'standard', 'Rail haut coulissant', 'Composant', 'Profilé aluminium', 'ml', 9500),
  ('P-COU-RB', 'standard', 'Rail bas coulissant', 'Composant', 'Profilé aluminium', 'ml', 10500),
  ('P-COU-MD', 'standard', 'Montant dormant coulissant', 'Composant', 'Profilé aluminium', 'ml', 8500),
  ('P-COU-OV', 'standard', 'Ouvrant coulissant (montant/traverse)', 'Composant', 'Profilé aluminium', 'ml', 9800),
  ('P-LEV-OV', 'standard', 'Ouvrant levant-coulissant renforcé', 'Composant', 'Profilé aluminium', 'ml', 16500),
  ('P-POR-DOR', 'standard', 'Dormant de porte', 'Composant', 'Profilé aluminium', 'ml', 11500),
  ('P-POR-OUV', 'standard', 'Ouvrant de porte (montant large)', 'Composant', 'Profilé aluminium', 'ml', 13500),
  ('P-MR-MON', 'standard', 'Montant de mur-rideau 50 mm', 'Composant', 'Profilé aluminium', 'ml', 18500),
  ('P-MR-TRA', 'standard', 'Traverse de mur-rideau 50 mm', 'Composant', 'Profilé aluminium', 'ml', 15500),
  ('P-MR-CAP', 'standard', 'Serreur + capot de mur-rideau', 'Composant', 'Profilé aluminium', 'ml', 6500),
  ('P-VER-40', 'standard', 'Profilé verrière 40×20 aspect acier', 'Composant', 'Profilé aluminium', 'ml', 7200),
  ('P-CLO-001', 'standard', 'Profilé de cloison (rail / montant)', 'Composant', 'Profilé aluminium', 'ml', 6800),
  ('P-GUI-OV', 'standard', 'Ouvrant guillotine', 'Composant', 'Profilé aluminium', 'ml', 9800),
  ('P-PLI-OV', 'standard', 'Ouvrant pliant (accordéon)', 'Composant', 'Profilé aluminium', 'ml', 12500),
  ('P-PLI-RAIL', 'standard', 'Rail haut/bas porte pliante', 'Composant', 'Profilé aluminium', 'ml', 14500),
  ('PAN-SAND-24', 'standard', 'Panneau sandwich alu 24 mm (remplissage)', 'Composant', 'Panneau', 'm2', 18500),
  ('TOL-ALU-20', 'standard', 'Tôle aluminium 2 mm laquée', 'Composant', 'Panneau', 'm2', 16500),
  ('TOL-PERF-INX', 'standard', 'Tôle inox perforée 1,5 mm', 'Composant', 'Panneau', 'm2', 42000),
  ('VIT-FEU-442', 'standard', 'Verre feuilleté 44.2 (sécurité)', 'Composant', 'Vitrage', 'm2', 19500),
  ('VIT-TRE-8', 'standard', 'Verre trempé 8 mm (douche)', 'Composant', 'Vitrage', 'm2', 24000),
  ('VIT-TRE-10', 'standard', 'Verre trempé 10 mm (porte tout verre)', 'Composant', 'Vitrage', 'm2', 29000),
  ('VIT-POLY-16', 'standard', 'Polycarbonate alvéolaire 16 mm', 'Composant', 'Vitrage', 'm2', 9500),
  ('VIT-HUB-001', 'standard', 'Hublot vitré de porte sectionnelle', 'Composant', 'Vitrage', 'unite', 18000),
  ('JNT-FRP-001', 'standard', 'Joint de frappe EPDM', 'Consommable', 'Joint & étanchéité', 'ml', 650),
  ('JNT-MR-001', 'standard', 'Joint EPDM de mur-rideau', 'Consommable', 'Joint & étanchéité', 'ml', 1200),
  ('CON-SIL-STR', 'standard', 'Silicone structurel (VEC)', 'Consommable', 'Consommable atelier', 'cartouche', 9500),
  ('FIX-CHV-001', 'standard', 'Cheville + vis de fixation dormant', 'Consommable', 'Visserie & fixations', 'unite', 250),
  ('FIX-MR-ATT', 'standard', 'Attache de mur-rideau (équerre de dalle)', 'Composant', 'Visserie & fixations', 'unite', 6500),
  ('FIX-SCE-001', 'standard', 'Patte de scellement', 'Composant', 'Visserie & fixations', 'unite', 900),
  ('QUI-CRM-001', 'standard', 'Crémone + poignée de fenêtre', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('QUI-VER-001', 'standard', 'Verrou de semi-fixe', 'Composant', 'Quincaillerie', 'unite', 2200),
  ('QUI-OB-KIT', 'standard', 'Kit ferrage oscillo-battant', 'Composant', 'Quincaillerie', 'unite', 38000),
  ('QUI-CMP-SOU', 'standard', 'Compas de soufflet', 'Composant', 'Quincaillerie', 'unite', 4500),
  ('QUI-BRA-PRJ', 'standard', 'Paire de bras de projection (italienne)', 'Composant', 'Quincaillerie', 'unite', 14500),
  ('QUI-PIV-001', 'standard', 'Paire de pivots avec frein', 'Composant', 'Quincaillerie', 'unite', 17500),
  ('QUI-GUI-RES', 'standard', 'Balancier / ressorts de guillotine', 'Composant', 'Quincaillerie', 'unite', 16000),
  ('QUI-ROU-001', 'standard', 'Roulette réglable de coulissant', 'Composant', 'Quincaillerie', 'unite', 1800),
  ('QUI-FER-COU', 'standard', 'Fermeture à crochet + poignée coquille', 'Composant', 'Quincaillerie', 'unite', 5500),
  ('QUI-BUT-001', 'standard', 'Butée de coulissant', 'Composant', 'Quincaillerie', 'unite', 600),
  ('QUI-LEV-KIT', 'standard', 'Kit levant-coulissant (chariots + levier)', 'Composant', 'Quincaillerie', 'unite', 95000),
  ('QUI-CHA-PLI', 'standard', 'Charnière de porte pliante', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('QUI-CHR-PLI', 'standard', 'Chariot de porte pliante', 'Composant', 'Quincaillerie', 'unite', 12500),
  ('QUI-CYL-001', 'standard', 'Cylindre de sécurité 5 clés', 'Composant', 'Quincaillerie', 'unite', 9500),
  ('QUI-SER-3P', 'standard', 'Serrure 3 points de porte', 'Composant', 'Quincaillerie', 'unite', 42000),
  ('QUI-PIV-SOL', 'standard', 'Pivot de sol avec frein (va-et-vient)', 'Composant', 'Quincaillerie', 'unite', 85000),
  ('QUI-PIV-POR', 'standard', 'Pivot de porte désaxée', 'Composant', 'Quincaillerie', 'unite', 120000),
  ('QUI-POI-TIR', 'standard', 'Poignée tirant inox', 'Composant', 'Quincaillerie', 'unite', 18000),
  ('LAM-VR-39', 'standard', 'Lame de volet roulant alu 39 mm isolée', 'Composant', 'Profilé aluminium', 'ml', 2600),
  ('LAM-VR-55', 'standard', 'Lame de volet alu 55 mm', 'Composant', 'Profilé aluminium', 'ml', 3400),
  ('LAM-GA-77', 'standard', 'Lame de porte de garage alu 77 mm', 'Composant', 'Profilé aluminium', 'ml', 5200),
  ('LAM-RM-100', 'standard', 'Lame de rideau métallique 100 mm', 'Composant', 'Profilé aluminium', 'ml', 6800),
  ('LAM-RM-MAI', 'standard', 'Tablier grille maillée (anneaux)', 'Composant', 'Panneau', 'm2', 38000),
  ('TOI-MOU-ENR', 'standard', 'Toile de moustiquaire enroulable', 'Consommable', 'Vitrage', 'm2', 4500),
  ('LAM-FIN', 'standard', 'Lame finale avec joint', 'Composant', 'Profilé aluminium', 'ml', 4500),
  ('P-ENR-COF', 'standard', 'Coffre de volet / rideau', 'Composant', 'Profilé aluminium', 'ml', 12500),
  ('P-ENR-COU', 'standard', 'Coulisse avec joint brosse', 'Composant', 'Profilé aluminium', 'ml', 5500),
  ('AXE-OCT-60', 'standard', 'Axe octogonal Ø60', 'Composant', 'Profilé aluminium', 'ml', 5800),
  ('AXE-RM-102', 'standard', 'Axe de rideau métallique Ø102 + ressorts', 'Composant', 'Quincaillerie', 'ml', 22000),
  ('QUI-ATT-TAB', 'standard', 'Attache tablier / verrou', 'Composant', 'Quincaillerie', 'unite', 650),
  ('QUI-JOU-001', 'standard', 'Paire de joues / flasques de coffre', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('MOT-TUB-001', 'standard', 'Moteur tubulaire filaire + inverseur', 'Composant', 'Motorisation', 'unite', 75000),
  ('MOT-RID-001', 'standard', 'Moteur central de rideau métallique', 'Composant', 'Motorisation', 'unite', 260000),
  ('QUI-MAN-001', 'standard', 'Treuil + manivelle', 'Composant', 'Quincaillerie', 'unite', 18000),
  ('QUI-SER-RID', 'standard', 'Serrure de sol de rideau', 'Composant', 'Quincaillerie', 'unite', 22000),
  ('PAN-SEC-40', 'standard', 'Panneau sectionnel isolé 40 mm', 'Composant', 'Panneau', 'm2', 32000),
  ('P-SEC-RAIL', 'standard', 'Rail de porte sectionnelle', 'Composant', 'Profilé aluminium', 'ml', 7500),
  ('QUI-RES-TOR', 'standard', 'Ressort de torsion + tambour', 'Composant', 'Quincaillerie', 'unite', 48000),
  ('QUI-GAL-001', 'standard', 'Galet + support de panneau', 'Composant', 'Quincaillerie', 'unite', 3500),
  ('QUI-CHA-SEC', 'standard', 'Charnière intermédiaire de panneau', 'Composant', 'Quincaillerie', 'unite', 2500),
  ('MOT-PLA-001', 'standard', 'Motorisation plafond de porte de garage', 'Composant', 'Motorisation', 'unite', 220000),
  ('P-CAD-LAM', 'standard', 'Cadre porte-lames (persienne / volet)', 'Composant', 'Profilé aluminium', 'ml', 7800),
  ('LAM-PER-50', 'standard', 'Lame de persienne 50 mm', 'Composant', 'Profilé aluminium', 'ml', 2400),
  ('LAM-BS-150', 'standard', 'Lame brise-soleil aile d’avion 150 mm', 'Composant', 'Profilé aluminium', 'ml', 9500),
  ('LAM-BSO-80', 'standard', 'Lame orientable BSO 80 mm', 'Composant', 'Profilé aluminium', 'ml', 3800),
  ('LAM-CLA-100', 'standard', 'Lame claustra 100×30', 'Composant', 'Profilé aluminium', 'ml', 5200),
  ('QUI-EMB-LAM', 'standard', 'Embout / clip de lame', 'Composant', 'Quincaillerie', 'unite', 450),
  ('FIX-CONS-BS', 'standard', 'Console de brise-soleil', 'Composant', 'Visserie & fixations', 'unite', 9500),
  ('QUI-PEN-001', 'standard', 'Penture + gond de volet battant', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('QUI-ESP-001', 'standard', 'Espagnolette de volet', 'Composant', 'Quincaillerie', 'unite', 8500),
  ('MOT-BSO-001', 'standard', 'Moteur de BSO', 'Composant', 'Motorisation', 'unite', 95000),
  ('P-PER-POT', 'standard', 'Poteau de pergola 150×150', 'Composant', 'Profilé aluminium', 'ml', 32000),
  ('P-PER-POU', 'standard', 'Poutre-chéneau de pergola', 'Composant', 'Profilé aluminium', 'ml', 36000),
  ('LAM-PER-200', 'standard', 'Lame orientable de pergola 200 mm', 'Composant', 'Profilé aluminium', 'ml', 14500),
  ('LAM-PER-FIX', 'standard', 'Chevron / lame fixe de toiture', 'Composant', 'Profilé aluminium', 'ml', 9800),
  ('MOT-PER-001', 'standard', 'Vérin / moteur de lames de pergola', 'Composant', 'Motorisation', 'unite', 185000),
  ('PLA-PER-001', 'standard', 'Platine d’ancrage de poteau', 'Composant', 'Visserie & fixations', 'unite', 14500),
  ('FIX-MUR-PER', 'standard', 'Fixation murale de pergola adossée', 'Composant', 'Visserie & fixations', 'unite', 4500),
  ('P-AUV-MUR', 'standard', 'Profil mural d’auvent', 'Composant', 'Profilé aluminium', 'ml', 16500),
  ('TIR-INX-001', 'standard', 'Tirant inox + rotules', 'Composant', 'Quincaillerie', 'unite', 38000),
  ('TUB-ALU-80', 'standard', 'Tube aluminium 80×40 (cadre)', 'Composant', 'Profilé aluminium', 'ml', 8800),
  ('TUB-ALU-25', 'standard', 'Tube aluminium 25×25 (barreau)', 'Composant', 'Profilé aluminium', 'ml', 3200),
  ('LAM-POR-150', 'standard', 'Lame de portail / clôture 150 mm', 'Composant', 'Profilé aluminium', 'ml', 6500),
  ('TUB-INX-40', 'standard', 'Tube inox 40×40 (cadre)', 'Composant', 'Profilé aluminium', 'ml', 19500),
  ('TUB-INX-20', 'standard', 'Tube inox Ø20 (barreau)', 'Composant', 'Profilé aluminium', 'ml', 7800),
  ('QUI-GON-001', 'standard', 'Gond réglable de portail', 'Composant', 'Quincaillerie', 'unite', 9500),
  ('QUI-SER-POR', 'standard', 'Serrure de portail + gâche', 'Composant', 'Quincaillerie', 'unite', 28000),
  ('QUI-ROU-POR', 'standard', 'Roue à gorge de portail coulissant', 'Composant', 'Quincaillerie', 'unite', 14000),
  ('QUI-GUI-POR', 'standard', 'Guide haut à galets', 'Composant', 'Quincaillerie', 'unite', 16000),
  ('P-RAI-SOL', 'standard', 'Rail au sol à sceller', 'Composant', 'Profilé aluminium', 'ml', 6500),
  ('MOT-POR-BAT', 'standard', 'Motorisation portail battant (2 vérins)', 'Composant', 'Motorisation', 'unite', 320000),
  ('MOT-POR-COU', 'standard', 'Motorisation portail coulissant', 'Composant', 'Motorisation', 'unite', 260000),
  ('POT-CLO-001', 'standard', 'Poteau de clôture aluminium', 'Composant', 'Profilé aluminium', 'ml', 12500),
  ('BAR-DEF-012', 'standard', 'Barreau de défense acier galva Ø12', 'Composant', 'Profilé aluminium', 'ml', 2200),
  ('POT-ALU-001', 'standard', 'Poteau de garde-corps alu 50×50', 'Composant', 'Profilé aluminium', 'ml', 14500),
  ('MC-ALU-001', 'standard', 'Main courante aluminium', 'Composant', 'Profilé aluminium', 'ml', 9800),
  ('LIS-ALU-001', 'standard', 'Lisse / barreau aluminium', 'Composant', 'Profilé aluminium', 'ml', 4200),
  ('LIS-GI-012', 'standard', 'Lisse inox Ø12', 'Composant', 'Profilé aluminium', 'ml', 6800),
  ('P-SAB-001', 'standard', 'Sabot aluminium pour verre (profil U)', 'Composant', 'Profilé aluminium', 'ml', 45000),
  ('QUI-CAL-SAB', 'standard', 'Cale / kit de serrage de sabot', 'Composant', 'Quincaillerie', 'unite', 2800),
  ('SUP-MC-001', 'standard', 'Support de main courante murale inox', 'Composant', 'Quincaillerie', 'unite', 6500),
  ('QUI-EMB-MC', 'standard', 'Embout / coude de main courante', 'Composant', 'Quincaillerie', 'unite', 4500),
  ('FIX-ANG-001', 'standard', 'Fixation à l’anglaise (nez de dalle)', 'Composant', 'Visserie & fixations', 'unite', 7800),
  ('P-DOU-MUR', 'standard', 'Profil mural de paroi de douche', 'Composant', 'Profilé aluminium', 'ml', 9500),
  ('BAR-STA-INX', 'standard', 'Barre de stabilisation inox', 'Composant', 'Quincaillerie', 'unite', 22000),
  ('QUI-CHA-DOU', 'standard', 'Charnière verre-mur de douche inox', 'Composant', 'Quincaillerie', 'unite', 19000),
  ('QUI-POI-DOU', 'standard', 'Poignée de porte de douche', 'Composant', 'Quincaillerie', 'unite', 9500),
  ('P-DOU-RAIL', 'standard', 'Rail haut de douche coulissante inox', 'Composant', 'Profilé aluminium', 'ml', 28000),
  ('QUI-ROU-DOU', 'standard', 'Roulette de douche coulissante', 'Composant', 'Quincaillerie', 'unite', 8500),
  ('JNT-DOU-001', 'standard', 'Joint d’étanchéité de douche', 'Consommable', 'Joint & étanchéité', 'ml', 1800),
  ('ACM-004', 'standard', 'Panneau composite aluminium 4 mm (ACM)', 'Composant', 'Panneau', 'm2', 21000),
  ('P-OSS-OME', 'standard', 'Ossature oméga aluminium', 'Composant', 'Profilé aluminium', 'ml', 4800),
  ('FIX-EQU-ACM', 'standard', 'Équerre de fixation d’ossature', 'Composant', 'Visserie & fixations', 'unite', 1200),
  ('FIX-RIV-001', 'standard', 'Rivet / vis de cassette', 'Consommable', 'Visserie & fixations', 'unite', 120)
on conflict (code, standing) do nothing;

-- ===========================================================================
-- 12. Tickets Z des points de vente (copie de sql/tickets_z.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Tickets Z des points de vente (clôture journalière et état périodique)
-- ============================================================================
-- Trois états distincts :
--   • Ventilation des mouvements de caisse (Comptabilité) : imputation comptable de chaque mouvement ;
--   • Brouillard de caisse (Caisse) : journal chronologique des entrées / sorties d'une caisse, solde progressif,
--     comptage et écart par séance — calculé à partir de caisse_sessions / caisse_mouvements (aucune table) ;
--   • Ticket Z (Point de vente) : relevé NUMÉROTÉ et définitif des ventes d'un point de vente pour une journée
--     (Z journalier) ou une période (Z périodique, ex. mensuel), avec grand total perpétuel. Enregistré ici.
-- Un Z ne se modifie pas : une nouvelle édition du même Z est une réimpression (DUPLICATA, compteur).
-- ============================================================================
create table if not exists public.tickets_z (
  id uuid primary key default gen_random_uuid(),
  point_vente_id uuid not null references public.points_vente(id) on delete restrict,
  type text not null check (type in ('journalier','periodique')),
  numero integer not null,
  date_debut date not null,
  date_fin date not null,
  nb_ventes integer not null default 0,
  total_ttc numeric(14,2) not null default 0,
  grand_total numeric(16,2) not null default 0,
  totaux jsonb not null default '{}'::jsonb,
  edite_par text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  nb_reimpressions integer not null default 0,
  derniere_reimpression timestamptz,
  constraint tickets_z_numero_key unique (point_vente_id, type, numero),
  constraint tickets_z_periode_key unique (point_vente_id, type, date_debut, date_fin),
  constraint tickets_z_dates_check check (date_debut <= date_fin and (type = 'periodique' or date_debut = date_fin))
);
create index if not exists idx_tickets_z_pdv on public.tickets_z (point_vente_id, date_fin desc);

alter table public.tickets_z enable row level security;
drop policy if exists "tickets_z_lecture" on public.tickets_z;
create policy "tickets_z_lecture" on public.tickets_z for select to authenticated
  using (public.est_utilisateur_autorise());
-- Pas d'écriture directe : émission et réimpression passent par ticket_z_emettre()

-- Émet (ou réimprime) le Z d'un point de vente. Nombre de ventes, total TTC et grand total sont recalculés
-- ici à partir des ventes validées ; p_totaux (modes de paiement, TVA, remises, caisse…) est conservé tel quel.
create or replace function public.ticket_z_emettre(p_pdv uuid, p_type text, p_debut date, p_fin date, p_totaux jsonb default '{}'::jsonb)
returns public.tickets_z
language plpgsql security definer set search_path = public as $$
declare v public.tickets_z; v_nb int; v_total numeric; v_gt numeric; v_num int;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if not public.peut_utiliser_point_vente(p_pdv) then raise exception 'Vous n''êtes pas affecté(e) à ce point de vente'; end if;
  if p_type not in ('journalier','periodique') then raise exception 'Type de ticket Z invalide'; end if;
  if p_type = 'journalier' and p_debut <> p_fin then raise exception 'Un Z journalier porte sur un seul jour'; end if;
  if p_debut > p_fin then raise exception 'Période invalide'; end if;
  if p_fin > current_date then raise exception 'Impossible d''émettre un Z sur une date future'; end if;
  perform pg_advisory_xact_lock(hashtext('ticket_z:' || p_pdv::text || ':' || p_type));

  select * into v from tickets_z where point_vente_id = p_pdv and type = p_type and date_debut = p_debut and date_fin = p_fin;
  if found then
    update tickets_z set nb_reimpressions = nb_reimpressions + 1, derniere_reimpression = now() where id = v.id returning * into v;
    return v;
  end if;

  select count(*), coalesce(sum(total), 0) into v_nb, v_total from ventes_comptoir
    where point_vente_id = p_pdv and statut = 'validee' and date_vente between p_debut and p_fin;
  select coalesce(sum(total), 0) into v_gt from ventes_comptoir
    where point_vente_id = p_pdv and statut = 'validee' and date_vente <= p_fin;
  select coalesce(max(numero), 0) + 1 into v_num from tickets_z where point_vente_id = p_pdv and type = p_type;

  insert into tickets_z (point_vente_id, type, numero, date_debut, date_fin, nb_ventes, total_ttc, grand_total, totaux, edite_par, created_by)
    values (p_pdv, p_type, v_num, p_debut, p_fin, v_nb, v_total, v_gt, coalesce(p_totaux, '{}'::jsonb),
            (select coalesce(nullif(email, ''), id::text) from auth.users where id = auth.uid()), auth.uid())
    returning * into v;
  return v;
end $$;
revoke all on function public.ticket_z_emettre(uuid, text, date, date, jsonb) from public, anon;
grant execute on function public.ticket_z_emettre(uuid, text, date, date, jsonb) to authenticated;

-- ===========================================================================
-- 13. Comptabilité SYSCOHADA révisé : plan arborescent, reprise du plan d'origine, comptes de regroupement
--     (copie de sql/syscohada_revise.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Comptabilité SYSCOHADA révisé (Acte uniforme OHADA, 2017)
-- ============================================================================
-- 1. Plan comptable de référence SYSCOHADA révisé : comptes principaux (2 chiffres), divisionnaires
--    (3 chiffres) et sous-comptes utiles (4 chiffres), classes 1 à 8. L'arborescence se lit par PRÉFIXE :
--    le parent d'un compte est le plus long compte existant dont le code est un préfixe du sien
--    (401 → 4011 → 40110001…). Un compte qui a des sous-comptes est un compte de REGROUPEMENT :
--    il totalise ses sous-comptes et n'est plus imputable (contrôle en base, ci-dessous).
-- 2. Reprise du plan d'origine (codes à 6 chiffres 571000, 512000, 701000…) : chaque ancien compte est
--    fusionné dans son équivalent SYSCOHADA révisé (écritures, caisses, ventilations, règles et comptes par
--    défaut sont reportés), puis supprimé. Les comptes créés par l'entité (ex. 6042, 60420001) sont conservés.
-- 3. Comptes par défaut de la comptabilisation automatique ramenés sur les codes révisés.
-- Idempotent : peut être rejoué sans effet de bord.
-- ============================================================================
alter table public.compta_comptes add column if not exists standard boolean not null default false;
alter table public.caisses alter column compte_code set default '571';
alter table public.caisse_demandes add column if not exists compte_imputation text references public.compta_comptes(code);

-- 1. Plan de référence (le libellé d'un compte déjà présent n'est pas écrasé)
insert into public.compta_comptes (code, libelle, classe, nature, standard, actif) values
  ('10', 'Capital', 1, 'passif', true, true),
  ('101', 'Capital social', 1, 'passif', true, true),
  ('102', 'Capital par dotation', 1, 'passif', true, true),
  ('103', 'Capital personnel', 1, 'passif', true, true),
  ('104', 'Compte de l''exploitant', 1, 'passif', true, true),
  ('105', 'Primes liées au capital social', 1, 'passif', true, true),
  ('106', 'Écarts de réévaluation', 1, 'passif', true, true),
  ('109', 'Apporteurs, capital souscrit non appelé', 1, 'actif', true, true),
  ('11', 'Réserves', 1, 'passif', true, true),
  ('111', 'Réserve légale', 1, 'passif', true, true),
  ('112', 'Réserves statutaires ou contractuelles', 1, 'passif', true, true),
  ('113', 'Réserves réglementées', 1, 'passif', true, true),
  ('118', 'Autres réserves', 1, 'passif', true, true),
  ('12', 'Report à nouveau', 1, 'passif', true, true),
  ('121', 'Report à nouveau créditeur', 1, 'passif', true, true),
  ('129', 'Report à nouveau débiteur', 1, 'actif', true, true),
  ('13', 'Résultat net de l''exercice', 1, 'passif', true, true),
  ('130', 'Résultat en instance d''affectation', 1, 'passif', true, true),
  ('131', 'Résultat net : bénéfice', 1, 'passif', true, true),
  ('139', 'Résultat net : perte', 1, 'actif', true, true),
  ('14', 'Subventions d''investissement', 1, 'passif', true, true),
  ('141', 'Subventions d''équipement', 1, 'passif', true, true),
  ('148', 'Autres subventions d''investissement', 1, 'passif', true, true),
  ('15', 'Provisions réglementées et fonds assimilés', 1, 'passif', true, true),
  ('151', 'Amortissements dérogatoires', 1, 'passif', true, true),
  ('158', 'Autres provisions et fonds réglementés', 1, 'passif', true, true),
  ('16', 'Emprunts et dettes assimilées', 1, 'passif', true, true),
  ('161', 'Emprunts obligataires', 1, 'passif', true, true),
  ('162', 'Emprunts et dettes auprès des établissements de crédit', 1, 'passif', true, true),
  ('163', 'Avances reçues de l''État', 1, 'passif', true, true),
  ('164', 'Avances reçues et comptes courants bloqués', 1, 'passif', true, true),
  ('165', 'Dépôts et cautionnements reçus', 1, 'passif', true, true),
  ('166', 'Intérêts courus', 1, 'passif', true, true),
  ('167', 'Avances assorties de conditions particulières', 1, 'passif', true, true),
  ('168', 'Autres emprunts et dettes', 1, 'passif', true, true),
  ('17', 'Dettes de location-acquisition', 1, 'passif', true, true),
  ('172', 'Dettes de location-acquisition / crédit-bail immobilier', 1, 'passif', true, true),
  ('173', 'Dettes de location-acquisition / crédit-bail mobilier', 1, 'passif', true, true),
  ('176', 'Intérêts courus sur dettes de location-acquisition', 1, 'passif', true, true),
  ('178', 'Autres dettes de location-acquisition', 1, 'passif', true, true),
  ('18', 'Dettes liées à des participations et comptes de liaison', 1, 'passif', true, true),
  ('181', 'Dettes liées à des participations', 1, 'passif', true, true),
  ('184', 'Comptes permanents bloqués des établissements et succursales', 1, 'passif', true, true),
  ('185', 'Comptes permanents non bloqués des établissements et succursales', 1, 'passif', true, true),
  ('19', 'Provisions pour risques et charges', 1, 'passif', true, true),
  ('191', 'Provisions pour litiges', 1, 'passif', true, true),
  ('194', 'Provisions pour pertes de change', 1, 'passif', true, true),
  ('195', 'Provisions pour impôts', 1, 'passif', true, true),
  ('196', 'Provisions pour pensions et obligations similaires', 1, 'passif', true, true),
  ('198', 'Autres provisions pour risques et charges', 1, 'passif', true, true),
  ('21', 'Immobilisations incorporelles', 2, 'actif', true, true),
  ('211', 'Frais de développement', 2, 'actif', true, true),
  ('212', 'Brevets, licences, concessions et droits similaires', 2, 'actif', true, true),
  ('213', 'Logiciels et sites internet', 2, 'actif', true, true),
  ('214', 'Marques', 2, 'actif', true, true),
  ('215', 'Fonds commercial', 2, 'actif', true, true),
  ('216', 'Droit au bail', 2, 'actif', true, true),
  ('217', 'Investissements de création', 2, 'actif', true, true),
  ('218', 'Autres droits et valeurs incorporels', 2, 'actif', true, true),
  ('219', 'Immobilisations incorporelles en cours', 2, 'actif', true, true),
  ('22', 'Terrains', 2, 'actif', true, true),
  ('221', 'Terrains agricoles et forestiers', 2, 'actif', true, true),
  ('222', 'Terrains nus', 2, 'actif', true, true),
  ('223', 'Terrains bâtis', 2, 'actif', true, true),
  ('224', 'Travaux de mise en valeur des terrains', 2, 'actif', true, true),
  ('225', 'Terrains de carrières – tréfonds', 2, 'actif', true, true),
  ('226', 'Terrains aménagés', 2, 'actif', true, true),
  ('227', 'Terrains mis en concession', 2, 'actif', true, true),
  ('228', 'Autres terrains', 2, 'actif', true, true),
  ('229', 'Aménagements de terrains en cours', 2, 'actif', true, true),
  ('23', 'Bâtiments, installations techniques et agencements', 2, 'actif', true, true),
  ('231', 'Bâtiments industriels, agricoles, administratifs et commerciaux sur sol propre', 2, 'actif', true, true),
  ('232', 'Bâtiments industriels, agricoles, administratifs et commerciaux sur sol d''autrui', 2, 'actif', true, true),
  ('233', 'Ouvrages d''infrastructure', 2, 'actif', true, true),
  ('234', 'Aménagements, agencements et installations techniques', 2, 'actif', true, true),
  ('235', 'Aménagements de bureaux', 2, 'actif', true, true),
  ('237', 'Bâtiments industriels, agricoles et commerciaux mis en concession', 2, 'actif', true, true),
  ('238', 'Autres installations et agencements', 2, 'actif', true, true),
  ('239', 'Bâtiments et installations en cours', 2, 'actif', true, true),
  ('24', 'Matériel, mobilier et actifs biologiques', 2, 'actif', true, true),
  ('241', 'Matériel et outillage industriel et commercial', 2, 'actif', true, true),
  ('242', 'Matériel et outillage agricole', 2, 'actif', true, true),
  ('243', 'Matériel d''emballage récupérable et identifiable', 2, 'actif', true, true),
  ('244', 'Matériel et mobilier', 2, 'actif', true, true),
  ('245', 'Matériel de transport', 2, 'actif', true, true),
  ('246', 'Actifs biologiques', 2, 'actif', true, true),
  ('247', 'Agencements, aménagements du matériel et des actifs biologiques', 2, 'actif', true, true),
  ('248', 'Autres matériels et mobiliers', 2, 'actif', true, true),
  ('249', 'Matériels et actifs biologiques en cours', 2, 'actif', true, true),
  ('25', 'Avances et acomptes versés sur immobilisations', 2, 'actif', true, true),
  ('251', 'Avances et acomptes versés sur immobilisations incorporelles', 2, 'actif', true, true),
  ('252', 'Avances et acomptes versés sur immobilisations corporelles', 2, 'actif', true, true),
  ('26', 'Titres de participation', 2, 'actif', true, true),
  ('261', 'Titres de participation dans des sociétés sous contrôle exclusif', 2, 'actif', true, true),
  ('262', 'Titres de participation dans des sociétés sous contrôle conjoint', 2, 'actif', true, true),
  ('263', 'Titres de participation dans des sociétés conférant une influence notable', 2, 'actif', true, true),
  ('265', 'Participations dans des organismes professionnels', 2, 'actif', true, true),
  ('266', 'Parts dans des groupements d''intérêt économique (GIE)', 2, 'actif', true, true),
  ('268', 'Autres titres de participation', 2, 'actif', true, true),
  ('27', 'Autres immobilisations financières', 2, 'actif', true, true),
  ('271', 'Prêts et créances', 2, 'actif', true, true),
  ('272', 'Prêts au personnel', 2, 'actif', true, true),
  ('273', 'Créances sur l''État', 2, 'actif', true, true),
  ('274', 'Titres immobilisés', 2, 'actif', true, true),
  ('275', 'Dépôts et cautionnements versés', 2, 'actif', true, true),
  ('276', 'Intérêts courus', 2, 'actif', true, true),
  ('277', 'Créances rattachées à des participations et avances à des GIE', 2, 'actif', true, true),
  ('278', 'Immobilisations financières diverses', 2, 'actif', true, true),
  ('28', 'Amortissements', 2, 'actif', true, true),
  ('281', 'Amortissements des immobilisations incorporelles', 2, 'actif', true, true),
  ('2813', 'Amortissements des logiciels et sites internet', 2, 'actif', true, true),
  ('282', 'Amortissements des terrains', 2, 'actif', true, true),
  ('283', 'Amortissements des bâtiments, installations techniques et agencements', 2, 'actif', true, true),
  ('2831', 'Amortissements des bâtiments sur sol propre', 2, 'actif', true, true),
  ('284', 'Amortissements du matériel, du mobilier et des actifs biologiques', 2, 'actif', true, true),
  ('2841', 'Amortissements du matériel et outillage industriel et commercial', 2, 'actif', true, true),
  ('2844', 'Amortissements du matériel et mobilier', 2, 'actif', true, true),
  ('2845', 'Amortissements du matériel de transport', 2, 'actif', true, true),
  ('29', 'Dépréciations des immobilisations', 2, 'actif', true, true),
  ('291', 'Dépréciations des immobilisations incorporelles', 2, 'actif', true, true),
  ('292', 'Dépréciations des terrains', 2, 'actif', true, true),
  ('293', 'Dépréciations des bâtiments, installations techniques et agencements', 2, 'actif', true, true),
  ('294', 'Dépréciations du matériel, du mobilier et des actifs biologiques', 2, 'actif', true, true),
  ('295', 'Dépréciations des avances et acomptes versés sur immobilisations', 2, 'actif', true, true),
  ('296', 'Dépréciations des titres de participation', 2, 'actif', true, true),
  ('297', 'Dépréciations des autres immobilisations financières', 2, 'actif', true, true),
  ('31', 'Marchandises', 3, 'actif', true, true),
  ('311', 'Marchandises A', 3, 'actif', true, true),
  ('312', 'Marchandises B', 3, 'actif', true, true),
  ('318', 'Marchandises hors activités ordinaires (HAO)', 3, 'actif', true, true),
  ('32', 'Matières premières et fournitures liées', 3, 'actif', true, true),
  ('321', 'Matières A', 3, 'actif', true, true),
  ('322', 'Matières B', 3, 'actif', true, true),
  ('323', 'Fournitures (A, B)', 3, 'actif', true, true),
  ('33', 'Autres approvisionnements', 3, 'actif', true, true),
  ('331', 'Matières consommables', 3, 'actif', true, true),
  ('332', 'Matières combustibles', 3, 'actif', true, true),
  ('333', 'Produits d''entretien', 3, 'actif', true, true),
  ('334', 'Fournitures d''atelier et d''usine', 3, 'actif', true, true),
  ('335', 'Emballages', 3, 'actif', true, true),
  ('336', 'Fournitures de magasin', 3, 'actif', true, true),
  ('337', 'Fournitures de bureau', 3, 'actif', true, true),
  ('338', 'Autres matières', 3, 'actif', true, true),
  ('34', 'Produits en cours', 3, 'actif', true, true),
  ('341', 'Produits en cours', 3, 'actif', true, true),
  ('342', 'Travaux en cours', 3, 'actif', true, true),
  ('35', 'Services en cours', 3, 'actif', true, true),
  ('351', 'Études en cours', 3, 'actif', true, true),
  ('352', 'Prestations de services en cours', 3, 'actif', true, true),
  ('36', 'Produits finis', 3, 'actif', true, true),
  ('361', 'Produits finis A', 3, 'actif', true, true),
  ('362', 'Produits finis B', 3, 'actif', true, true),
  ('37', 'Produits intermédiaires et résiduels', 3, 'actif', true, true),
  ('371', 'Produits intermédiaires', 3, 'actif', true, true),
  ('372', 'Produits résiduels', 3, 'actif', true, true),
  ('38', 'Stocks en cours de route, en consignation ou en dépôt', 3, 'actif', true, true),
  ('381', 'Marchandises en cours de route', 3, 'actif', true, true),
  ('382', 'Matières premières et fournitures liées en cours de route', 3, 'actif', true, true),
  ('383', 'Autres approvisionnements en cours de route', 3, 'actif', true, true),
  ('386', 'Produits finis en cours de route', 3, 'actif', true, true),
  ('387', 'Stocks en consignation ou en dépôt', 3, 'actif', true, true),
  ('39', 'Dépréciations des stocks et encours de production', 3, 'actif', true, true),
  ('391', 'Dépréciations des stocks de marchandises', 3, 'actif', true, true),
  ('392', 'Dépréciations des stocks de matières premières et fournitures liées', 3, 'actif', true, true),
  ('393', 'Dépréciations des stocks d''autres approvisionnements', 3, 'actif', true, true),
  ('394', 'Dépréciations des productions en cours', 3, 'actif', true, true),
  ('396', 'Dépréciations des stocks de produits finis', 3, 'actif', true, true),
  ('40', 'Fournisseurs et comptes rattachés', 4, 'passif', true, true),
  ('401', 'Fournisseurs, dettes en compte', 4, 'passif', true, true),
  ('4011', 'Fournisseurs', 4, 'passif', true, true),
  ('4012', 'Fournisseurs groupe', 4, 'passif', true, true),
  ('4013', 'Fournisseurs sous-traitants', 4, 'passif', true, true),
  ('4016', 'Fournisseurs, réserve de propriété', 4, 'passif', true, true),
  ('4017', 'Fournisseurs, retenues de garantie', 4, 'passif', true, true),
  ('402', 'Fournisseurs, effets à payer', 4, 'passif', true, true),
  ('404', 'Fournisseurs, acquisitions courantes d''immobilisations', 4, 'passif', true, true),
  ('408', 'Fournisseurs, factures non parvenues', 4, 'passif', true, true),
  ('409', 'Fournisseurs débiteurs', 4, 'actif', true, true),
  ('4091', 'Fournisseurs, avances et acomptes versés', 4, 'actif', true, true),
  ('4094', 'Fournisseurs, créances pour emballages et matériels à rendre', 4, 'actif', true, true),
  ('4098', 'Fournisseurs, rabais, remises, ristournes et autres avoirs à obtenir', 4, 'actif', true, true),
  ('41', 'Clients et comptes rattachés', 4, 'actif', true, true),
  ('411', 'Clients', 4, 'actif', true, true),
  ('4111', 'Clients', 4, 'actif', true, true),
  ('4112', 'Clients groupe', 4, 'actif', true, true),
  ('4114', 'Clients, État et collectivités publiques', 4, 'actif', true, true),
  ('4117', 'Clients, retenues de garantie', 4, 'actif', true, true),
  ('412', 'Clients, effets à recevoir en portefeuille', 4, 'actif', true, true),
  ('414', 'Créances sur cessions courantes d''immobilisations', 4, 'actif', true, true),
  ('415', 'Clients, effets escomptés non échus', 4, 'actif', true, true),
  ('416', 'Créances clients litigieuses ou douteuses', 4, 'actif', true, true),
  ('418', 'Clients, produits à recevoir', 4, 'actif', true, true),
  ('419', 'Clients créditeurs', 4, 'passif', true, true),
  ('4191', 'Clients, avances et acomptes reçus', 4, 'passif', true, true),
  ('4194', 'Clients, dettes pour emballages et matériels consignés', 4, 'passif', true, true),
  ('4198', 'Clients, rabais, remises, ristournes et autres avoirs à accorder', 4, 'passif', true, true),
  ('42', 'Personnel', 4, 'passif', true, true),
  ('421', 'Personnel, avances et acomptes', 4, 'actif', true, true),
  ('422', 'Personnel, rémunérations dues', 4, 'passif', true, true),
  ('423', 'Personnel, oppositions, saisies-arrêts', 4, 'passif', true, true),
  ('424', 'Personnel, œuvres sociales internes', 4, 'passif', true, true),
  ('425', 'Représentants du personnel', 4, 'passif', true, true),
  ('426', 'Personnel, participation aux bénéfices', 4, 'passif', true, true),
  ('427', 'Personnel, dépôts', 4, 'passif', true, true),
  ('428', 'Personnel, charges à payer et produits à recevoir', 4, 'passif', true, true),
  ('43', 'Organismes sociaux', 4, 'passif', true, true),
  ('431', 'Sécurité sociale (CNPS)', 4, 'passif', true, true),
  ('432', 'Caisses de retraite complémentaire', 4, 'passif', true, true),
  ('433', 'Autres organismes sociaux', 4, 'passif', true, true),
  ('438', 'Organismes sociaux, charges à payer et produits à recevoir', 4, 'passif', true, true),
  ('44', 'État et collectivités publiques', 4, 'passif', true, true),
  ('441', 'État, impôt sur les bénéfices', 4, 'passif', true, true),
  ('442', 'État, autres impôts et taxes', 4, 'passif', true, true),
  ('443', 'État, TVA facturée', 4, 'passif', true, true),
  ('4431', 'TVA facturée sur ventes', 4, 'passif', true, true),
  ('4432', 'TVA facturée sur prestations de services', 4, 'passif', true, true),
  ('4433', 'TVA facturée sur travaux', 4, 'passif', true, true),
  ('4434', 'TVA facturée sur production livrée à soi-même', 4, 'passif', true, true),
  ('4435', 'TVA sur factures à établir', 4, 'passif', true, true),
  ('444', 'État, TVA due ou crédit de TVA', 4, 'passif', true, true),
  ('4441', 'État, TVA due', 4, 'passif', true, true),
  ('4449', 'État, crédit de TVA à reporter', 4, 'actif', true, true),
  ('445', 'État, TVA récupérable', 4, 'actif', true, true),
  ('4451', 'TVA récupérable sur immobilisations', 4, 'actif', true, true),
  ('4452', 'TVA récupérable sur achats', 4, 'actif', true, true),
  ('4453', 'TVA récupérable sur transport', 4, 'actif', true, true),
  ('4454', 'TVA récupérable sur services extérieurs et autres charges', 4, 'actif', true, true),
  ('4455', 'TVA récupérable sur factures non parvenues', 4, 'actif', true, true),
  ('4456', 'TVA transférée par d''autres entités', 4, 'actif', true, true),
  ('446', 'État, autres taxes sur le chiffre d''affaires', 4, 'passif', true, true),
  ('447', 'État, impôts retenus à la source', 4, 'passif', true, true),
  ('448', 'État, charges à payer et produits à recevoir', 4, 'autre', true, true),
  ('449', 'État, créances et dettes diverses', 4, 'autre', true, true),
  ('45', 'Organismes internationaux', 4, 'autre', true, true),
  ('451', 'Opérations avec les organismes africains', 4, 'autre', true, true),
  ('452', 'Opérations avec les autres organismes internationaux', 4, 'autre', true, true),
  ('458', 'Organismes internationaux, fonds de dotation et subventions à recevoir', 4, 'actif', true, true),
  ('46', 'Apporteurs, associés et groupe', 4, 'autre', true, true),
  ('461', 'Apporteurs, opérations sur le capital', 4, 'autre', true, true),
  ('462', 'Associés, comptes courants', 4, 'autre', true, true),
  ('463', 'Associés, opérations faites en commun', 4, 'autre', true, true),
  ('465', 'Associés, dividendes à payer', 4, 'autre', true, true),
  ('466', 'Groupe, comptes courants', 4, 'autre', true, true),
  ('467', 'Apporteurs, restant dû sur capital appelé', 4, 'actif', true, true),
  ('47', 'Débiteurs et créditeurs divers', 4, 'autre', true, true),
  ('471', 'Débiteurs et créditeurs divers', 4, 'autre', true, true),
  ('472', 'Créances et dettes sur titres de placement', 4, 'autre', true, true),
  ('474', 'Répartition périodique des charges et des produits', 4, 'autre', true, true),
  ('475', 'Créances sur travaux non encore facturables', 4, 'actif', true, true),
  ('476', 'Charges constatées d''avance', 4, 'actif', true, true),
  ('477', 'Produits constatés d''avance', 4, 'autre', true, true),
  ('478', 'Écarts de conversion – Actif', 4, 'actif', true, true),
  ('479', 'Écarts de conversion – Passif', 4, 'autre', true, true),
  ('48', 'Créances et dettes hors activités ordinaires (HAO)', 4, 'passif', true, true),
  ('481', 'Fournisseurs d''investissements', 4, 'passif', true, true),
  ('482', 'Fournisseurs d''investissements, effets à payer', 4, 'passif', true, true),
  ('484', 'Autres dettes hors activités ordinaires', 4, 'passif', true, true),
  ('485', 'Créances sur cessions d''immobilisations', 4, 'actif', true, true),
  ('488', 'Autres créances hors activités ordinaires', 4, 'actif', true, true),
  ('49', 'Dépréciations et provisions pour risques à court terme (tiers)', 4, 'actif', true, true),
  ('490', 'Dépréciations des comptes fournisseurs', 4, 'actif', true, true),
  ('491', 'Dépréciations des comptes clients', 4, 'actif', true, true),
  ('492', 'Dépréciations des comptes personnel', 4, 'actif', true, true),
  ('493', 'Dépréciations des comptes organismes sociaux', 4, 'actif', true, true),
  ('494', 'Dépréciations des comptes État et collectivités publiques', 4, 'actif', true, true),
  ('495', 'Dépréciations des comptes organismes internationaux', 4, 'actif', true, true),
  ('496', 'Dépréciations des comptes apporteurs, associés et groupe', 4, 'actif', true, true),
  ('497', 'Dépréciations des comptes débiteurs divers', 4, 'actif', true, true),
  ('498', 'Dépréciations des comptes de créances HAO', 4, 'actif', true, true),
  ('499', 'Provisions pour risques à court terme', 4, 'actif', true, true),
  ('50', 'Titres de placement', 5, 'actif', true, true),
  ('501', 'Titres du Trésor et bons de caisse à court terme', 5, 'actif', true, true),
  ('502', 'Actions', 5, 'actif', true, true),
  ('503', 'Obligations', 5, 'actif', true, true),
  ('504', 'Bons de souscription', 5, 'actif', true, true),
  ('505', 'Titres négociables hors région', 5, 'actif', true, true),
  ('506', 'Intérêts courus', 5, 'actif', true, true),
  ('508', 'Autres titres de placement et créances assimilées', 5, 'actif', true, true),
  ('51', 'Valeurs à encaisser', 5, 'actif', true, true),
  ('511', 'Effets à encaisser', 5, 'actif', true, true),
  ('512', 'Effets à l''encaissement', 5, 'actif', true, true),
  ('513', 'Chèques à encaisser', 5, 'actif', true, true),
  ('514', 'Chèques à l''encaissement', 5, 'actif', true, true),
  ('515', 'Cartes de crédit à encaisser', 5, 'actif', true, true),
  ('518', 'Autres valeurs à l''encaissement', 5, 'actif', true, true),
  ('52', 'Banques', 5, 'actif', true, true),
  ('521', 'Banques locales', 5, 'actif', true, true),
  ('522', 'Banques autres États de la région', 5, 'actif', true, true),
  ('523', 'Banques autres États de la zone monétaire', 5, 'actif', true, true),
  ('524', 'Banques hors zone monétaire', 5, 'actif', true, true),
  ('525', 'Banques, dépôts à terme', 5, 'actif', true, true),
  ('526', 'Banques, intérêts courus', 5, 'actif', true, true),
  ('53', 'Établissements financiers et assimilés', 5, 'actif', true, true),
  ('531', 'Chèques postaux', 5, 'actif', true, true),
  ('532', 'Trésor', 5, 'actif', true, true),
  ('533', 'Sociétés de gestion et d''intermédiation (SGI)', 5, 'actif', true, true),
  ('536', 'Établissements financiers', 5, 'actif', true, true),
  ('538', 'Autres organismes financiers', 5, 'actif', true, true),
  ('54', 'Instruments de trésorerie', 5, 'actif', true, true),
  ('541', 'Options de taux d''intérêt', 5, 'actif', true, true),
  ('542', 'Options de taux de change', 5, 'actif', true, true),
  ('543', 'Options de taux boursiers', 5, 'actif', true, true),
  ('544', 'Instruments de marchés à terme', 5, 'actif', true, true),
  ('545', 'Avoirs d''or et autres métaux précieux', 5, 'actif', true, true),
  ('55', 'Instruments de monnaie électronique', 5, 'actif', true, true),
  ('551', 'Monnaie électronique carte carburant', 5, 'actif', true, true),
  ('552', 'Monnaie électronique téléphone portable (Mobile Money)', 5, 'actif', true, true),
  ('553', 'Monnaie électronique carte péage', 5, 'actif', true, true),
  ('554', 'Porte-monnaie électronique', 5, 'actif', true, true),
  ('558', 'Autres instruments de monnaie électronique', 5, 'actif', true, true),
  ('56', 'Banques, crédits de trésorerie et d''escompte', 5, 'passif', true, true),
  ('561', 'Crédits de trésorerie', 5, 'passif', true, true),
  ('564', 'Escompte de crédits de campagne', 5, 'passif', true, true),
  ('565', 'Escompte de crédits ordinaires', 5, 'passif', true, true),
  ('566', 'Banques, crédits de trésorerie, intérêts courus', 5, 'passif', true, true),
  ('57', 'Caisse', 5, 'actif', true, true),
  ('571', 'Caisse siège social', 5, 'actif', true, true),
  ('572', 'Caisse succursale A', 5, 'actif', true, true),
  ('573', 'Caisse succursale B', 5, 'actif', true, true),
  ('58', 'Régies d''avances, accréditifs et virements internes', 5, 'actif', true, true),
  ('581', 'Régies d''avance', 5, 'actif', true, true),
  ('582', 'Accréditifs', 5, 'actif', true, true),
  ('585', 'Virements de fonds', 5, 'autre', true, true),
  ('588', 'Autres virements internes', 5, 'autre', true, true),
  ('59', 'Dépréciations et provisions pour risques à court terme (trésorerie)', 5, 'actif', true, true),
  ('590', 'Dépréciations des titres de placement', 5, 'actif', true, true),
  ('591', 'Dépréciations des titres et valeurs à encaisser', 5, 'actif', true, true),
  ('592', 'Dépréciations des comptes banques', 5, 'actif', true, true),
  ('593', 'Dépréciations des comptes établissements financiers', 5, 'actif', true, true),
  ('594', 'Dépréciations des comptes d''instruments de trésorerie', 5, 'actif', true, true),
  ('599', 'Provisions pour risques à court terme à caractère financier', 5, 'passif', true, true),
  ('60', 'Achats et variations de stocks', 6, 'charge', true, true),
  ('601', 'Achats de marchandises', 6, 'charge', true, true),
  ('602', 'Achats de matières premières et fournitures liées', 6, 'charge', true, true),
  ('603', 'Variations des stocks de biens achetés', 6, 'charge', true, true),
  ('6031', 'Variations des stocks de marchandises', 6, 'charge', true, true),
  ('6032', 'Variations des stocks de matières premières et fournitures liées', 6, 'charge', true, true),
  ('6033', 'Variations des stocks d''autres approvisionnements', 6, 'charge', true, true),
  ('604', 'Achats stockés de matières et fournitures consommables', 6, 'charge', true, true),
  ('6041', 'Matières consommables', 6, 'charge', true, true),
  ('6042', 'Matières combustibles', 6, 'charge', true, true),
  ('6043', 'Produits d''entretien', 6, 'charge', true, true),
  ('6044', 'Fournitures d''atelier et d''usine', 6, 'charge', true, true),
  ('6046', 'Fournitures de magasin', 6, 'charge', true, true),
  ('6047', 'Fournitures de bureau', 6, 'charge', true, true),
  ('605', 'Autres achats', 6, 'charge', true, true),
  ('6051', 'Fournitures non stockables – Eau', 6, 'charge', true, true),
  ('6052', 'Fournitures non stockables – Électricité', 6, 'charge', true, true),
  ('6053', 'Fournitures non stockables – Autres énergies', 6, 'charge', true, true),
  ('6054', 'Fournitures d''entretien non stockables', 6, 'charge', true, true),
  ('6055', 'Fournitures de bureau non stockables', 6, 'charge', true, true),
  ('6056', 'Achats de petit matériel et outillage', 6, 'charge', true, true),
  ('6057', 'Achats d''études et prestations de services', 6, 'charge', true, true),
  ('6058', 'Achats de travaux, matériels et équipements', 6, 'charge', true, true),
  ('608', 'Achats d''emballages', 6, 'charge', true, true),
  ('61', 'Transports', 6, 'charge', true, true),
  ('611', 'Transports sur achats', 6, 'charge', true, true),
  ('612', 'Transports sur ventes', 6, 'charge', true, true),
  ('613', 'Transports pour le compte de tiers', 6, 'charge', true, true),
  ('614', 'Transports du personnel', 6, 'charge', true, true),
  ('616', 'Transports de plis', 6, 'charge', true, true),
  ('618', 'Autres frais de transport', 6, 'charge', true, true),
  ('6181', 'Voyages et déplacements', 6, 'charge', true, true),
  ('6182', 'Transports entre établissements ou chantiers', 6, 'charge', true, true),
  ('6183', 'Transports administratifs', 6, 'charge', true, true),
  ('62', 'Services extérieurs', 6, 'charge', true, true),
  ('621', 'Sous-traitance générale', 6, 'charge', true, true),
  ('622', 'Locations et charges locatives', 6, 'charge', true, true),
  ('623', 'Redevances de location-acquisition', 6, 'charge', true, true),
  ('624', 'Entretien, réparations, remise en état et maintenance', 6, 'charge', true, true),
  ('625', 'Primes d''assurance', 6, 'charge', true, true),
  ('626', 'Études, recherches et documentation', 6, 'charge', true, true),
  ('627', 'Publicité, publications, relations publiques', 6, 'charge', true, true),
  ('628', 'Frais de télécommunications', 6, 'charge', true, true),
  ('63', 'Autres services extérieurs', 6, 'charge', true, true),
  ('631', 'Frais bancaires', 6, 'charge', true, true),
  ('632', 'Rémunérations d''intermédiaires et de conseils', 6, 'charge', true, true),
  ('633', 'Frais de formation du personnel', 6, 'charge', true, true),
  ('634', 'Redevances pour brevets, licences, logiciels, concessions et droits similaires', 6, 'charge', true, true),
  ('635', 'Cotisations', 6, 'charge', true, true),
  ('637', 'Rémunérations de personnel extérieur à l''entité', 6, 'charge', true, true),
  ('638', 'Autres charges externes', 6, 'charge', true, true),
  ('64', 'Impôts et taxes', 6, 'charge', true, true),
  ('641', 'Impôts et taxes directs', 6, 'charge', true, true),
  ('645', 'Impôts et taxes indirects', 6, 'charge', true, true),
  ('646', 'Droits d''enregistrement', 6, 'charge', true, true),
  ('647', 'Pénalités, amendes fiscales', 6, 'charge', true, true),
  ('648', 'Autres impôts et taxes', 6, 'charge', true, true),
  ('65', 'Autres charges', 6, 'charge', true, true),
  ('651', 'Pertes sur créances clients et autres débiteurs', 6, 'charge', true, true),
  ('652', 'Quote-part de résultat sur opérations faites en commun', 6, 'charge', true, true),
  ('654', 'Valeurs comptables des cessions courantes d''immobilisations', 6, 'charge', true, true),
  ('656', 'Pertes de change sur créances et dettes commerciales', 6, 'charge', true, true),
  ('657', 'Pénalités et amendes pénales', 6, 'charge', true, true),
  ('658', 'Charges diverses', 6, 'charge', true, true),
  ('659', 'Charges pour dépréciations et provisions pour risques à court terme d''exploitation', 6, 'charge', true, true),
  ('66', 'Charges de personnel', 6, 'charge', true, true),
  ('661', 'Rémunérations directes versées au personnel national', 6, 'charge', true, true),
  ('662', 'Rémunérations directes versées au personnel non national', 6, 'charge', true, true),
  ('663', 'Indemnités forfaitaires versées au personnel', 6, 'charge', true, true),
  ('664', 'Charges sociales', 6, 'charge', true, true),
  ('666', 'Rémunérations et charges sociales de l''exploitant individuel', 6, 'charge', true, true),
  ('667', 'Rémunération transférée de personnel extérieur', 6, 'charge', true, true),
  ('668', 'Autres charges sociales', 6, 'charge', true, true),
  ('67', 'Frais financiers et charges assimilées', 6, 'charge', true, true),
  ('671', 'Intérêts des emprunts', 6, 'charge', true, true),
  ('672', 'Intérêts dans loyers de location-acquisition', 6, 'charge', true, true),
  ('673', 'Escomptes accordés', 6, 'charge', true, true),
  ('674', 'Autres intérêts', 6, 'charge', true, true),
  ('675', 'Escomptes des effets de commerce', 6, 'charge', true, true),
  ('676', 'Pertes de change financières', 6, 'charge', true, true),
  ('677', 'Pertes sur cessions de titres de placement', 6, 'charge', true, true),
  ('678', 'Pertes sur risques financiers', 6, 'charge', true, true),
  ('679', 'Charges pour dépréciations et provisions pour risques à court terme financières', 6, 'charge', true, true),
  ('68', 'Dotations aux amortissements', 6, 'charge', true, true),
  ('681', 'Dotations aux amortissements d''exploitation', 6, 'charge', true, true),
  ('69', 'Dotations aux provisions et aux dépréciations', 6, 'charge', true, true),
  ('691', 'Dotations aux provisions et aux dépréciations d''exploitation', 6, 'charge', true, true),
  ('697', 'Dotations aux provisions et aux dépréciations financières', 6, 'charge', true, true),
  ('70', 'Ventes', 7, 'produit', true, true),
  ('701', 'Ventes de marchandises', 7, 'produit', true, true),
  ('702', 'Ventes de produits finis', 7, 'produit', true, true),
  ('703', 'Ventes de produits intermédiaires', 7, 'produit', true, true),
  ('704', 'Ventes de produits résiduels', 7, 'produit', true, true),
  ('705', 'Travaux facturés', 7, 'produit', true, true),
  ('706', 'Services vendus', 7, 'produit', true, true),
  ('707', 'Produits accessoires', 7, 'produit', true, true),
  ('71', 'Subventions d''exploitation', 7, 'produit', true, true),
  ('711', 'Subventions sur produits à l''exportation', 7, 'produit', true, true),
  ('712', 'Subventions sur produits à l''importation', 7, 'produit', true, true),
  ('713', 'Subventions sur produits de péréquation', 7, 'produit', true, true),
  ('718', 'Autres subventions d''exploitation', 7, 'produit', true, true),
  ('72', 'Production immobilisée', 7, 'produit', true, true),
  ('721', 'Immobilisations incorporelles', 7, 'produit', true, true),
  ('722', 'Immobilisations corporelles', 7, 'produit', true, true),
  ('726', 'Immobilisations financières', 7, 'produit', true, true),
  ('73', 'Variations des stocks de biens et de services produits', 7, 'produit', true, true),
  ('734', 'Variations des stocks de produits en cours', 7, 'produit', true, true),
  ('735', 'Variations des en-cours de services', 7, 'produit', true, true),
  ('736', 'Variations des stocks de produits finis', 7, 'produit', true, true),
  ('737', 'Variations des stocks de produits intermédiaires et résiduels', 7, 'produit', true, true),
  ('75', 'Autres produits', 7, 'produit', true, true),
  ('751', 'Profits sur créances clients et autres débiteurs', 7, 'produit', true, true),
  ('752', 'Quote-part de résultat sur opérations faites en commun', 7, 'produit', true, true),
  ('754', 'Produits des cessions courantes d''immobilisations', 7, 'produit', true, true),
  ('756', 'Gains de change sur créances et dettes commerciales', 7, 'produit', true, true),
  ('758', 'Produits divers', 7, 'produit', true, true),
  ('759', 'Reprises de charges pour dépréciations et provisions pour risques à court terme d''exploitation', 7, 'produit', true, true),
  ('77', 'Revenus financiers et produits assimilés', 7, 'produit', true, true),
  ('771', 'Intérêts de prêts et créances diverses', 7, 'produit', true, true),
  ('772', 'Revenus de participations et autres titres immobilisés', 7, 'produit', true, true),
  ('773', 'Escomptes obtenus', 7, 'produit', true, true),
  ('774', 'Revenus de placement', 7, 'produit', true, true),
  ('775', 'Intérêts dans loyers de location-acquisition', 7, 'produit', true, true),
  ('776', 'Gains de change financiers', 7, 'produit', true, true),
  ('777', 'Gains sur cessions de titres de placement', 7, 'produit', true, true),
  ('778', 'Gains sur risques financiers', 7, 'produit', true, true),
  ('779', 'Reprises de charges pour dépréciations et provisions pour risques à court terme financières', 7, 'produit', true, true),
  ('78', 'Transferts de charges', 7, 'produit', true, true),
  ('781', 'Transferts de charges d''exploitation', 7, 'produit', true, true),
  ('787', 'Transferts de charges financières', 7, 'produit', true, true),
  ('79', 'Reprises de provisions, de dépréciations et autres', 7, 'produit', true, true),
  ('791', 'Reprises de provisions et dépréciations d''exploitation', 7, 'produit', true, true),
  ('797', 'Reprises de provisions et dépréciations financières', 7, 'produit', true, true),
  ('798', 'Reprises d''amortissements', 7, 'produit', true, true),
  ('799', 'Reprises de subventions d''investissement', 7, 'produit', true, true),
  ('81', 'Valeurs comptables des cessions d''immobilisations', 8, 'charge', true, true),
  ('811', 'Immobilisations incorporelles', 8, 'charge', true, true),
  ('812', 'Immobilisations corporelles', 8, 'charge', true, true),
  ('816', 'Immobilisations financières', 8, 'charge', true, true),
  ('82', 'Produits des cessions d''immobilisations', 8, 'produit', true, true),
  ('821', 'Immobilisations incorporelles', 8, 'produit', true, true),
  ('822', 'Immobilisations corporelles', 8, 'produit', true, true),
  ('826', 'Immobilisations financières', 8, 'produit', true, true),
  ('83', 'Charges hors activités ordinaires', 8, 'charge', true, true),
  ('831', 'Charges HAO constatées', 8, 'charge', true, true),
  ('834', 'Pertes sur créances HAO', 8, 'charge', true, true),
  ('835', 'Dons et libéralités accordés', 8, 'charge', true, true),
  ('836', 'Abandons de créances consentis', 8, 'charge', true, true),
  ('839', 'Charges pour dépréciations et provisions pour risques à court terme HAO', 8, 'charge', true, true),
  ('84', 'Produits hors activités ordinaires', 8, 'produit', true, true),
  ('841', 'Produits HAO constatés', 8, 'produit', true, true),
  ('845', 'Dons et libéralités obtenus', 8, 'produit', true, true),
  ('846', 'Abandons de créances obtenus', 8, 'produit', true, true),
  ('848', 'Transferts de charges HAO', 8, 'produit', true, true),
  ('849', 'Reprises de charges pour dépréciations et provisions pour risques à court terme HAO', 8, 'produit', true, true),
  ('85', 'Dotations hors activités ordinaires', 8, 'charge', true, true),
  ('851', 'Dotations aux provisions réglementées', 8, 'charge', true, true),
  ('852', 'Dotations aux amortissements HAO', 8, 'charge', true, true),
  ('853', 'Dotations aux dépréciations HAO', 8, 'charge', true, true),
  ('854', 'Dotations aux provisions pour risques et charges HAO', 8, 'charge', true, true),
  ('858', 'Autres dotations HAO', 8, 'charge', true, true),
  ('86', 'Reprises de charges, provisions et dépréciations HAO', 8, 'produit', true, true),
  ('861', 'Reprises de provisions réglementées', 8, 'produit', true, true),
  ('862', 'Reprises d''amortissements HAO', 8, 'produit', true, true),
  ('863', 'Reprises de dépréciations HAO', 8, 'produit', true, true),
  ('864', 'Reprises de provisions pour risques et charges HAO', 8, 'produit', true, true),
  ('865', 'Reprises de subventions d''investissement', 8, 'produit', true, true),
  ('868', 'Autres reprises HAO', 8, 'produit', true, true),
  ('87', 'Participation des travailleurs', 8, 'charge', true, true),
  ('871', 'Participation légale aux bénéfices', 8, 'charge', true, true),
  ('874', 'Participation contractuelle aux bénéfices', 8, 'charge', true, true),
  ('878', 'Autres participations', 8, 'charge', true, true),
  ('88', 'Subventions d''équilibre', 8, 'produit', true, true),
  ('881', 'Subventions d''équilibre de l''État', 8, 'produit', true, true),
  ('884', 'Subventions d''équilibre des collectivités publiques', 8, 'produit', true, true),
  ('886', 'Subventions d''équilibre du groupe', 8, 'produit', true, true),
  ('888', 'Autres subventions d''équilibre', 8, 'produit', true, true),
  ('89', 'Impôts sur le résultat', 8, 'charge', true, true),
  ('891', 'Impôts sur les bénéfices de l''exercice', 8, 'charge', true, true),
  ('892', 'Rappels d''impôts sur résultats antérieurs', 8, 'charge', true, true),
  ('895', 'Impôt minimum forfaitaire (IMF)', 8, 'charge', true, true),
  ('899', 'Dégrèvements et annulations d''impôts sur résultats antérieurs', 8, 'charge', true, true)
on conflict (code) do update set standard = true, classe = excluded.classe;

-- 2. Reprise des comptes du plan d'origine
create temp table if not exists _reprise_pc (ancien text primary key, nouveau text not null, garder_libelle boolean not null);
truncate _reprise_pc;
insert into _reprise_pc values
  ('101000', '101', false),
  ('106000', '118', false),
  ('110000', '121', false),
  ('120000', '131', false),
  ('129000', '139', false),
  ('162000', '162', false),
  ('168000', '168', false),
  ('213000', '213', false),
  ('222000', '223', false),
  ('231000', '231', false),
  ('241000', '241', false),
  ('244000', '244', false),
  ('245000', '245', false),
  ('281300', '2813', false),
  ('283100', '2831', false),
  ('284100', '2841', false),
  ('284500', '2845', false),
  ('321000', '321', true),
  ('322000', '322', true),
  ('323000', '323', true),
  ('331000', '331', false),
  ('401000', '4011', false),
  ('408000', '408', false),
  ('409000', '4091', false),
  ('411000', '4111', false),
  ('416000', '416', false),
  ('418000', '418', false),
  ('419000', '4191', false),
  ('421000', '422', false),
  ('422000', '421', false),
  ('431000', '431', false),
  ('441000', '441', false),
  ('443000', '4431', false),
  ('444100', '4441', false),
  ('444900', '4449', false),
  ('445000', '4452', false),
  ('447000', '442', false),
  ('512000', '521', false),
  ('571000', '571', true),
  ('572000', '572', true),
  ('585000', '585', false),
  ('601000', '602', false),
  ('602000', '602', false),
  ('605000', '608', false),
  ('614000', '611', false),
  ('621000', '621', false),
  ('622000', '622', false),
  ('624000', '624', false),
  ('625000', '625', false),
  ('627000', '627', false),
  ('628000', '638', false),
  ('631000', '631', false),
  ('633000', '633', false),
  ('638000', '638', false),
  ('641000', '641', false),
  ('658000', '658', false),
  ('661000', '661', false),
  ('664000', '664', false),
  ('668000', '668', false),
  ('671000', '671', false),
  ('678000', '674', false),
  ('681000', '681', false),
  ('701000', '701', false),
  ('706000', '706', false),
  ('758000', '758', false),
  ('771000', '771', false),
  ('891000', '891', false);
delete from _reprise_pc r where not exists (select 1 from public.compta_comptes c where c.code = r.ancien);
update public.compta_comptes n set libelle = o.libelle
  from _reprise_pc r join public.compta_comptes o on o.code = r.ancien where n.code = r.nouveau and r.garder_libelle;
update public.compta_lignes x set compte_code = r.nouveau from _reprise_pc r where x.compte_code = r.ancien;
update public.caisses x set compte_code = r.nouveau from _reprise_pc r where x.compte_code = r.ancien;
update public.caisse_mouvements x set compte_ventile = r.nouveau from _reprise_pc r where x.compte_ventile = r.ancien;
update public.caisse_regles_ventilation x set compte_code = r.nouveau from _reprise_pc r where x.compte_code = r.ancien;
update public.parametres p set comptes_defaut = (
    select coalesce(jsonb_object_agg(e.key, coalesce((select r.nouveau from _reprise_pc r where r.ancien = e.value), e.value)), '{}'::jsonb)
    from jsonb_each_text(p.comptes_defaut) e)
  where p.comptes_defaut is not null and p.comptes_defaut <> '{}'::jsonb;
delete from public.compta_comptes c using _reprise_pc r where c.code = r.ancien;
drop table _reprise_pc;

-- 3. Compte de regroupement = non imputable (il a des sous-comptes actifs)
create or replace function public.compta_compte_est_regroupement(p_code text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from compta_comptes c where c.actif and c.code <> p_code and left(c.code, length(p_code)) = p_code);
$$;
create or replace function public.compta_lignes_garde_imputable() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.compta_compte_est_regroupement(new.compte_code) then
    raise exception 'Le compte % est un compte de regroupement (il a des sous-comptes) : imputez l''écriture sur l''un de ses sous-comptes.', new.compte_code
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists trg_compta_lignes_imputable on public.compta_lignes;
create trigger trg_compta_lignes_imputable before insert or update of compte_code on public.compta_lignes
  for each row execute function public.compta_lignes_garde_imputable();

-- 4. Journaux
insert into public.compta_journaux (code, libelle) values
  ('AC','Journal des Achats'),('AN','Journal des À-Nouveaux'),('BQ','Journal de Banque'),('CA','Journal de Caisse'),
  ('CLO','Journal de Clôture'),('MM','Journal Mobile Money'),('OD','Journal des Opérations Diverses'),('VE','Journal des Ventes'),
  ('INV','Journal d''inventaire (variations de stocks)')
on conflict (code) do nothing;

-- 5. Comptabilisation automatique des bons validés par le DG : le compte d'imputation choisi sur le bon
--    (caisse_demandes.compte_imputation) est reporté sur le mouvement (compte proposé, statut « à ventiler »),
--    les transferts sur le compte de virements de fonds ; l'application génère ensuite l'écriture.
create or replace function public.caisse_demande_decider(p_id uuid, p_decision text, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d caisse_demandes; s_src uuid; s_dst uuid; v_num text; n int; v_trf uuid; m1 uuid; m2 uuid;
        v_nom text; c_src text; c_dst text; v_cpt_vir text;
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
    -- Comptabilisation automatique : un transfert se ventile sur le compte de virements de fonds (585)
    select coalesce(nullif(comptes_defaut->>'virement_interne',''), '585') into v_cpt_vir from parametres limit 1;
    v_cpt_vir := coalesce(v_cpt_vir, '585');
    if not exists (select 1 from compta_comptes where code = v_cpt_vir) then v_cpt_vir := null; end if;
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, statut, transfert_id, created_by, projet_id, compte_ventile)
      values (s_src, d.caisse_id, 'TRF-OUT', current_date, 'sortie', d.montant, coalesce(nullif(d.motif,''), 'Transfert vers '||coalesce(c_dst,'caisse')), d.beneficiaire, 'a_ventiler', v_trf, d.demande_par, d.projet_id, v_cpt_vir)
      returning id into m1;
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, statut, transfert_id, created_by, compte_ventile)
      values (s_dst, d.caisse_dest_id, 'TRF-IN', current_date, 'entree', d.montant, 'Transfert depuis '||coalesce(c_src,'caisse'), 'a_ventiler', v_trf, d.demande_par, v_cpt_vir)
      returning id into m2;
  else
    perform pg_advisory_xact_lock(hashtext('caisse_bons_' || d.caisse_id::text));
    select greatest(count(*), coalesce(max(nullif(regexp_replace(numero, '^.*-', ''), '')::int) filter (where numero ~ '^(BE|BS)-[0-9]+$'), 0)) + 1
      into n from caisse_mouvements where caisse_id = d.caisse_id;
    v_num := (case when d.type = 'entree' then 'BE' else 'BS' end) || '-' || lpad(n::text, 5, '0');
    insert into caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, statut, created_by, projet_id, compte_ventile)
      values (s_src, d.caisse_id, v_num, d.date_mouvement, d.type, d.montant, d.motif, d.beneficiaire, 'a_ventiler', d.demande_par, d.projet_id, d.compte_imputation)
      returning id into m1;
  end if;
  update caisse_demandes set statut='validee', decide_par=auth.uid(), decide_nom=v_nom, decide_le=now(), mouvement_id=m1, mouvement_dest_id=m2 where id = d.id;
  return jsonb_build_object('ok',true,'statut','validee','mouvement_id',m1,'numero',coalesce(v_num,'TRF'));
end $$;

-- ===========================================================================
-- 14. Photos des produits et composants (copie de sql/photos_articles.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Photos des produits et des composants (vente au comptoir)
-- ============================================================================
-- • composants.photo / produits.photo : MINIATURE compressée (≈ 240 px, quelques Ko) chargée avec les listes
--   et le catalogue de la vente au comptoir (fonctionne aussi hors ligne, avec la copie locale) ;
-- • photos_articles : photo en GRAND format (≈ 1 000 px), chargée seulement à l'agrandissement ou en fiche,
--   clé « composant:<id> » ou « produit:<id> » ;
-- • produits.vente_comptoir : le produit (ouvrage) est proposé à la vente au comptoir (sans mouvement de stock).
-- ============================================================================
alter table public.composants add column if not exists photo text;
alter table public.produits add column if not exists photo text;
alter table public.produits add column if not exists vente_comptoir boolean not null default true;

create table if not exists public.photos_articles (
  cle text primary key,
  image text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.photos_articles enable row level security;
drop policy if exists "photos_articles_lecture" on public.photos_articles;
create policy "photos_articles_lecture" on public.photos_articles for select to authenticated
  using (public.est_utilisateur_autorise());
drop policy if exists "photos_articles_ecriture" on public.photos_articles;
create policy "photos_articles_ecriture" on public.photos_articles for all to authenticated
  using (public.est_utilisateur_autorise()) with check (public.est_utilisateur_autorise());

-- ===========================================================================
-- 15. Moteur d'impression : registre des documents imprimés et QR code de sécurité logiciel (copie de sql/impressions_securite.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Moteur d'impression : registre des documents imprimés
-- et QR code de SÉCURITÉ LOGICIEL (distinct du QR code FNE de la DGI)
-- ============================================================================
-- Chaque document imprimé (devis, facture, reçu, bon, fiche, état périodique, brouillard,
-- ticket Z, page imprimée…) reçoit un CODE D'AUTHENTICITÉ unique et une SIGNATURE HMAC
-- calculée ici avec une clé secrète propre à la base (jamais exposée au navigateur).
-- Le QR code de sécurité pointe vers la page de vérification de l'application
-- (…/index.html?verif=CODE-SIGNATURE) : n'importe qui, sans compte, peut contrôler qu'un papier
-- a bien été émis par le logiciel et que son type, numéro, montant et tiers n'ont pas été modifiés.
-- Le QR code FNE (certification DGI) reste un QR séparé, uniquement sur les factures certifiées.
-- Réimprimer le même document (mêmes données) conserve son code et incrémente le compteur
-- (impression n° 2, 3… = duplicata) ; un document aux données modifiées reçoit un nouveau code.
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;

alter table public.parametres add column if not exists impression jsonb not null default '{}'::jsonb;

-- Clé secrète de signature (une ligne) : RLS sans politique → illisible depuis l'API
create table if not exists public.securite_documents_cle (
  id int primary key default 1 check (id = 1),
  cle bytea not null,
  created_at timestamptz not null default now()
);
alter table public.securite_documents_cle enable row level security;
revoke all on public.securite_documents_cle from public, anon, authenticated;
insert into public.securite_documents_cle (id, cle) values (1, extensions.gen_random_bytes(32)) on conflict (id) do nothing;

create table if not exists public.documents_imprimes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  signature text not null,
  type text not null,
  titre text,
  numero text,
  montant numeric(16,2) not null default 0,
  tiers text,
  periode text,
  niveau text,
  empreinte text not null,
  format text,
  nb_impressions integer not null default 1,
  premiere_impression timestamptz not null default now(),
  derniere_impression timestamptz not null default now(),
  imprime_par uuid default auth.uid(),
  imprime_par_nom text,
  statut text not null default 'valide' check (statut in ('valide','revoque')),
  motif_revocation text,
  revoque_le timestamptz,
  revoque_par text
);
create index if not exists idx_documents_imprimes_date on public.documents_imprimes (derniere_impression desc);
create index if not exists idx_documents_imprimes_doc on public.documents_imprimes (type, numero, empreinte);

alter table public.documents_imprimes enable row level security;
drop policy if exists "documents_imprimes_lecture" on public.documents_imprimes;
create policy "documents_imprimes_lecture" on public.documents_imprimes for select to authenticated
  using (public.est_utilisateur_autorise());
-- Pas d'écriture directe : tout passe par les fonctions ci-dessous

create or replace function public.document_signature(p_code text, p_type text, p_numero text, p_montant numeric, p_empreinte text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select upper(substr(encode(extensions.hmac(
    convert_to(concat_ws('|', p_code, p_type, coalesce(p_numero, ''), to_char(coalesce(p_montant, 0), 'FM999999999999990.00'), p_empreinte), 'UTF8'),
    (select cle from securite_documents_cle where id = 1), 'sha256'), 'hex'), 1, 12));
$$;
revoke all on function public.document_signature(text, text, text, numeric, text) from public, anon, authenticated;

-- Enregistre une impression ; renvoie le code, la signature et le n° d'impression
create or replace function public.document_imprime_enregistrer(
  p_type text, p_numero text, p_titre text, p_montant numeric, p_tiers text, p_periode text,
  p_empreinte text, p_format text default 'a4', p_niveau text default null)
returns table (code text, signature text, nb_impressions integer, premiere_impression timestamptz, statut text)
language plpgsql security definer set search_path = public, extensions as $$
declare v public.documents_imprimes; v_code text; v_nom text;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if coalesce(p_type, '') = '' or coalesce(p_empreinte, '') = '' then raise exception 'Document incomplet'; end if;
  perform pg_advisory_xact_lock(hashtext('doc_imprime:' || p_type || ':' || coalesce(p_numero, '') || ':' || p_empreinte));
  select * into v from documents_imprimes d where d.type = p_type and d.numero is not distinct from nullif(p_numero, '') and d.empreinte = p_empreinte
    order by d.premiere_impression limit 1;
  if found then
    update documents_imprimes d set nb_impressions = d.nb_impressions + 1, derniere_impression = now() where d.id = v.id returning * into v;
  else
    select coalesce(nullif(p.nom_complet, ''), u.email, auth.uid()::text) into v_nom
      from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid();
    loop
      v_code := 'SX-' || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4)) || '-'
                      || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4)) || '-'
                      || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4));
      exit when not exists (select 1 from documents_imprimes d where d.code = v_code);
    end loop;
    insert into documents_imprimes (code, signature, type, titre, numero, montant, tiers, periode, niveau, empreinte, format, imprime_par, imprime_par_nom)
      values (v_code, public.document_signature(v_code, p_type, nullif(p_numero, ''), coalesce(p_montant, 0), p_empreinte),
              p_type, p_titre, nullif(p_numero, ''), coalesce(p_montant, 0), nullif(p_tiers, ''), nullif(p_periode, ''), nullif(p_niveau, ''),
              p_empreinte, p_format, auth.uid(), v_nom)
      returning * into v;
  end if;
  return query select v.code, v.signature, v.nb_impressions, v.premiere_impression, v.statut;
end $$;
revoke all on function public.document_imprime_enregistrer(text, text, text, numeric, text, text, text, text, text) from public, anon;
grant execute on function public.document_imprime_enregistrer(text, text, text, numeric, text, text, text, text, text) to authenticated;

-- Vérification publique (scan du QR, sans compte). Les détails ne sont révélés que si la signature
-- correspond au code (le code seul ne suffit pas : impossible de parcourir le registre).
create or replace function public.document_verifier(p_code text, p_signature text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v public.documents_imprimes; v_sig text; p public.parametres;
begin
  select * into v from documents_imprimes d where d.code = upper(trim(p_code));
  if not found then return jsonb_build_object('trouve', false); end if;
  v_sig := public.document_signature(v.code, v.type, v.numero, v.montant, v.empreinte);
  if v_sig <> v.signature or upper(trim(coalesce(p_signature, ''))) <> v.signature then
    return jsonb_build_object('trouve', true, 'signature_valide', false);
  end if;
  select * into p from parametres limit 1;
  return jsonb_build_object(
    'trouve', true, 'signature_valide', true, 'code', v.code, 'type', v.type, 'titre', v.titre, 'numero', v.numero,
    'montant', v.montant, 'tiers', v.tiers, 'periode', v.periode, 'niveau', v.niveau,
    'premiere_impression', v.premiere_impression, 'derniere_impression', v.derniere_impression,
    'nb_impressions', v.nb_impressions, 'imprime_par', v.imprime_par_nom,
    'statut', v.statut, 'motif_revocation', v.motif_revocation, 'revoque_le', v.revoque_le,
    'entreprise', p.raison_sociale, 'ncc', p.ncc, 'rccm', p.rccm, 'telephone', p.telephone);
end $$;
revoke all on function public.document_verifier(text, text) from public;
grant execute on function public.document_verifier(text, text) to anon, authenticated;

-- Révocation (document annulé, falsifié, remplacé…) : administrateur / manager
create or replace function public.document_revoquer(p_code text, p_motif text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'Motif obligatoire'; end if;
  update documents_imprimes set statut = 'revoque', motif_revocation = trim(p_motif), revoque_le = now(),
    revoque_par = (select coalesce(nullif(email, ''), id::text) from auth.users where id = auth.uid())
    where code = upper(trim(p_code)) and statut = 'valide';
  if not found then raise exception 'Document introuvable ou déjà révoqué'; end if;
end $$;
revoke all on function public.document_revoquer(text, text) from public, anon;
grant execute on function public.document_revoquer(text, text) to authenticated;

-- ===========================================================================
-- 16. Inventaires physiques : état d'inventaire et justification des écarts (copie de sql/inventaires.sql)
-- ===========================================================================
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

-- ===========================================================================
-- 17. Référentiels paramétrables : familles d'articles et unités de mesure (copie de sql/familles_referentiels.sql)
-- ===========================================================================
-- ============================================================================
-- Sanix AluExpert ERP — Référentiels paramétrables : familles d'articles et unités de mesure
-- ============================================================================
-- Remplace les listes codées en dur dans l'application :
--   • familles de COMPOSANTS / consommables (icône, couleur, ordre, compte de stock SYSCOHADA) ;
--   • familles de PRODUITS / ouvrages (icône, couleur, ordre) — aussi utilisées par les réalisations ;
--   • unités de mesure des composants (auparavant bloquées par une contrainte CHECK figée).
-- Le compte de stock d'une famille (321 profilés, 322 vitrages, 323 fournitures, 331 consommables…)
-- remplace la déduction « au nom » de la famille : la comptabilisation automatique et la variation
-- des stocks utilisent désormais ce réglage.
-- Renommer une famille renomme aussi les articles qui la portent ; une famille utilisée ne peut pas
-- être supprimée : on la fusionne dans une autre (famille_fusionner) ou on la désactive.
-- Les unités des PRODUITS (unité / m² / ml) restent figées : elles pilotent le calcul du prix.
-- ============================================================================
create table if not exists public.familles_articles (
  id uuid primary key default gen_random_uuid(),
  domaine text not null check (domaine in ('composant','produit')),
  nom text not null check (length(trim(nom)) > 0),
  icone text,
  couleur text,
  compte_stock text check (compte_stock in ('stock_profiles','stock_vitrage','stock_fournitures','stock_consommables')),
  ordre integer not null default 100,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  constraint familles_articles_nom_key unique (domaine, nom)
);

alter table public.familles_articles enable row level security;
drop policy if exists "familles_lecture" on public.familles_articles;
create policy "familles_lecture" on public.familles_articles for select to authenticated using (public.est_utilisateur_autorise());
drop policy if exists "familles_creation" on public.familles_articles;
create policy "familles_creation" on public.familles_articles for insert to authenticated with check (public.est_utilisateur_autorise());
drop policy if exists "familles_modification" on public.familles_articles;
create policy "familles_modification" on public.familles_articles for update to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse()) with check (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());
drop policy if exists "familles_suppression" on public.familles_articles;
create policy "familles_suppression" on public.familles_articles for delete to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());

-- Renommage propagé aux articles ; suppression refusée si la famille est utilisée
create or replace function public.familles_articles_propager() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_op = 'UPDATE' then
    if new.domaine <> old.domaine then raise exception 'Le domaine d''une famille ne se modifie pas'; end if;
    new.nom := trim(new.nom);
    if new.nom <> old.nom then
      if old.domaine = 'composant' then
        update composants set famille = new.nom where famille = old.nom;
      else
        update produits set famille = new.nom where famille = old.nom;
        update realisations set famille = new.nom where famille = old.nom;
      end if;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.domaine = 'composant' then select count(*) into n from composants where famille = old.nom;
    else select (select count(*) from produits where famille = old.nom) + (select count(*) from realisations where famille = old.nom) into n; end if;
    if n > 0 then raise exception 'La famille « % » est utilisée par % article(s) : fusionnez-la dans une autre famille ou désactivez-la.', old.nom, n; end if;
    return old;
  end if;
  new.nom := trim(new.nom);
  return new;
end $$;
drop trigger if exists trg_familles_articles_propager on public.familles_articles;
create trigger trg_familles_articles_propager before insert or update or delete on public.familles_articles
  for each row execute function public.familles_articles_propager();

-- Fusion : déplace les articles de la famille source vers la cible, puis supprime la source
create or replace function public.famille_fusionner(p_source uuid, p_cible uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare s familles_articles; c familles_articles; n int := 0; k int;
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  select * into s from familles_articles where id = p_source;
  select * into c from familles_articles where id = p_cible;
  if s.id is null or c.id is null then raise exception 'Famille introuvable'; end if;
  if s.id = c.id then raise exception 'Choisissez une autre famille'; end if;
  if s.domaine <> c.domaine then raise exception 'Les deux familles doivent être du même domaine'; end if;
  if s.domaine = 'composant' then
    update composants set famille = c.nom where famille = s.nom; get diagnostics n = row_count;
  else
    update produits set famille = c.nom where famille = s.nom; get diagnostics n = row_count;
    update realisations set famille = c.nom where famille = s.nom; get diagnostics k = row_count; n := n + k;
  end if;
  delete from familles_articles where id = s.id;
  return n;
end $$;
revoke all on function public.famille_fusionner(uuid, uuid) from public, anon;
grant execute on function public.famille_fusionner(uuid, uuid) to authenticated;

-- Familles de départ (anciennes listes de l'application) + familles déjà présentes dans les données
insert into public.familles_articles (domaine, nom, icone, couleur, compte_stock, ordre) values
  ('composant','Profilé aluminium','🪜','#2563eb','stock_profiles',10),
  ('composant','Vitrage','🪟','#7c3aed','stock_vitrage',20),
  ('composant','Panneau','🧱','#0f766e','stock_profiles',30),
  ('composant','Quincaillerie','🔩','#475569','stock_fournitures',40),
  ('composant','Visserie & fixations','🔧','#0891b2','stock_fournitures',50),
  ('composant','Joint & étanchéité','➰','#d97706','stock_fournitures',60),
  ('composant','Motorisation','⚙️','#be123c','stock_fournitures',70),
  ('composant','Consommable atelier','🧴','#059669','stock_consommables',80),
  ('composant','Autre','📦','#6b7280',null,999),
  ('produit','Fenêtres & châssis','🪟','#1d4ed8',null,10),
  ('produit','Coulissants, baies & pliants','↔️','#0369a1',null,20),
  ('produit','Portes','🚪','#b45309',null,30),
  ('produit','Façades, vitrines, cloisons & verrières','🏢','#be185d',null,40),
  ('produit','Fermetures, volets & protections solaires','🌗','#4d7c0f',null,50),
  ('produit','Pergolas, auvents & abris','⛱️','#15803d',null,60),
  ('produit','Garde-corps, rampes & mains courantes','🛡️','#334155',null,70),
  ('produit','Portails, clôtures & grilles','🚧','#7c2d12',null,80),
  ('produit','Douche & aménagements inox','🚿','#0e7490',null,90),
  ('produit','Habillage & bardage composite','🧱','#6d28d9',null,100),
  ('produit','Fenêtre coulissante','🪟','#2563eb',null,110),
  ('produit','Porte à la française','🚪','#d97706',null,120),
  ('produit','Porte coulissante','🚪','#ea580c',null,130),
  ('produit','Coulissant galandage','🚪','#0891b2',null,140),
  ('produit','Fenêtre jalousie','🪟','#7c3aed',null,150),
  ('produit','Moustiquaire fixe','🦟','#059669',null,160),
  ('produit','Moustiquaire coulissante','🦟','#10b981',null,170),
  ('produit','Garde-corps inox','🛡️','#475569',null,180),
  ('produit','Verrière / mur rideau','🏢','#be185d',null,190),
  ('produit','Autre','📦','#6b7280',null,999)
on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'composant', trim(famille), '📦', '#6b7280', 500 from public.composants where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'produit', trim(famille), '📦', '#6b7280', 500 from public.produits where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'produit', trim(famille), '📦', '#6b7280', 500 from public.realisations where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;

-- ---------- Unités de mesure des composants ----------
create table if not exists public.unites_mesure (
  code text primary key check (code ~ '^[a-z0-9_]{1,20}$'),
  libelle text not null,
  ordre integer not null default 100,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.unites_mesure enable row level security;
drop policy if exists "unites_lecture" on public.unites_mesure;
create policy "unites_lecture" on public.unites_mesure for select to authenticated using (public.est_utilisateur_autorise());
drop policy if exists "unites_creation" on public.unites_mesure;
create policy "unites_creation" on public.unites_mesure for insert to authenticated with check (public.est_utilisateur_autorise());
drop policy if exists "unites_modification" on public.unites_mesure;
create policy "unites_modification" on public.unites_mesure for update to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse()) with check (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());
drop policy if exists "unites_suppression" on public.unites_mesure;
create policy "unites_suppression" on public.unites_mesure for delete to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());

insert into public.unites_mesure (code, libelle, ordre) values
  ('unite','Unité',10),('ml','Mètre linéaire (ml)',20),('m2','Mètre carré (m²)',30),('kg','Kilogramme (kg)',40),
  ('litre','Litre',50),('boite','Boîte',60),('cartouche','Cartouche',70)
on conflict (code) do nothing;
insert into public.unites_mesure (code, libelle, ordre)
  select distinct unite, unite, 500 from public.composants where unite is not null and unite ~ '^[a-z0-9_]{1,20}$'
  on conflict (code) do nothing;

-- La contrainte figée est remplacée par une clé étrangère vers le référentiel (unité supprimable seulement si inutilisée)
alter table public.composants drop constraint if exists composants_unite_check;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'composants_unite_fk') then
    alter table public.composants add constraint composants_unite_fk foreign key (unite) references public.unites_mesure(code) on update cascade on delete restrict;
  end if;
end $$;

-- ===========================================================================
-- 18. Inventaires : brouillons, inventaires partiels, stock initial, régularisation (copie de sql/inventaires_brouillons.sql)
-- ===========================================================================
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

-- ===========================================================================
-- 19. Achats & approvisionnement : commandes fournisseur, réceptions, commandes internes (copie de sql/achats_commandes.sql)
-- ===========================================================================
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

-- ===========================================================================
-- 20. Centre de validation — DG & hiérarchie autorisée : paliers, circuit des bons de commande, vue v_validations (copie de sql/validations_hierarchie.sql)
-- ===========================================================================
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


-- ===========================================================================
-- 21. Portail client — vitrine complète : mot du DG, produits présentés (copie de sql/portail_dg.sql)
-- ===========================================================================
-- ============================================================================
-- Portail client — vitrine complète : mot du DG, produits présentés
-- ----------------------------------------------------------------------------
-- Ajoute au paramétrage du portail (Paramètres → Portail client) les champs du
-- « mot du DG » (nom, titre, message, photo). Aucune autre modification de schéma :
-- la présentation des produits fabriqués réutilise la table `produits` existante
-- (colonne `photo` déjà ajoutée par sql/photos.sql), incluse dans le fichier HTML
-- généré au moment de l'export (aucun accès Supabase public supplémentaire requis).
-- Idempotent : peut être rejoué.
-- ============================================================================
alter table public.parametres add column if not exists portail_dg_nom text;
alter table public.parametres add column if not exists portail_dg_titre text;
alter table public.parametres add column if not exists portail_dg_message text;
alter table public.parametres add column if not exists portail_dg_photo text;


-- ===========================================================================
-- 22. Portail client — vitrine PUBLIQUE toujours à jour : fonction portail_donnees_publiques (copie de sql/portail_public.sql)
-- ===========================================================================
-- ============================================================================
-- Portail client — vitrine PUBLIQUE, toujours à jour (modèle Menko Immo)
-- ----------------------------------------------------------------------------
-- Fonction SECURITY DEFINER accessible en lecture par le public (anon) qui renvoie
-- uniquement les données destinées au site vitrine (jamais de données internes :
-- ni chiffres d'affaires, ni clients, ni stocks…). Permet de déployer UNE SEULE
-- page HTML statique (sql/../public-site/portail-unique.html) qui se recharge en
-- direct à chaque visite — aucune régénération/redéploiement nécessaire quand le
-- contenu (réalisations, produits, mot du DG, coordonnées…) change dans l'ERP.
-- Respecte enfin réellement la case « Portail actif » : si décochée, ne renvoie
-- que {"actif":false} (aucune fuite de données), le site affiche alors un message.
-- Idempotent : peut être rejoué.
-- ============================================================================
create or replace function public.portail_donnees_publiques()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_p parametres%rowtype;
  v_result jsonb;
begin
  select * into v_p from parametres limit 1;
  if v_p.id is null or not coalesce(v_p.portail_actif, false) then
    return jsonb_build_object('actif', false);
  end if;

  select jsonb_build_object(
    'actif', true,
    'nom', coalesce(nullif(v_p.portail_nom, ''), v_p.raison_sociale, 'Notre entreprise'),
    'slogan', coalesce(nullif(v_p.portail_slogan, ''), 'Votre menuiserie aluminium sur-mesure'),
    'couleur', coalesce(nullif(v_p.portail_couleur, ''), '#1D3557'),
    'logo', coalesce(v_p.logo_base64, ''),
    'telephone', coalesce(v_p.telephone, ''),
    'whatsapp', coalesce(v_p.whatsapp, ''),
    'email', coalesce(v_p.email, ''),
    'adresse', coalesce(v_p.adresse, ''),
    'aPropos', coalesce(v_p.site_a_propos, ''),
    'facebook', coalesce(v_p.site_facebook, ''),
    'instagram', coalesce(v_p.site_instagram, ''),
    'rccm', coalesce(v_p.rccm, ''),
    'ncc', coalesce(v_p.ncc, ''),
    'dgNom', coalesce(v_p.portail_dg_nom, ''),
    'dgTitre', coalesce(v_p.portail_dg_titre, ''),
    'dgMessage', coalesce(v_p.portail_dg_message, ''),
    'dgPhoto', coalesce(v_p.portail_dg_photo, ''),
    'familleIcones', coalesce((
      select jsonb_object_agg(nom, coalesce(icone, '🛠️'))
      from familles_articles where domaine = 'produit' and actif
    ), '{}'::jsonb),
    'produits', coalesce((
      select jsonb_agg(jsonb_build_object('nom', nom, 'famille', famille) order by famille)
      from produits
    ), '[]'::jsonb),
    'produitsPresentes', coalesce((
      select jsonb_agg(jsonb_build_object('nom', nom, 'famille', famille, 'photo', photo) order by famille)
      from produits where photo is not null
    ), '[]'::jsonb),
    'realisations', coalesce((
      select jsonb_agg(jsonb_build_object('titre', titre, 'description', description, 'famille', famille, 'photo_base64', photo_base64) order by ordre)
      from realisations where publie = true
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;
revoke all on function public.portail_donnees_publiques() from public;
grant execute on function public.portail_donnees_publiques() to anon, authenticated;


-- ===========================================================================
-- 23. Portail client — durcissement anti-énumération de l'accès par code client + téléphone (copie de sql/portail_securite.sql)
-- ===========================================================================
-- ============================================================================
-- Portail client — durcissement de l'accès par code client + téléphone
-- ----------------------------------------------------------------------------
-- Revue de sécurité : portail_lookup(code, téléphone) est appelée par n'importe
-- qui (anon), sans authentification. Or les codes clients sont SÉQUENTIELS
-- (C-1, C-2, C-3…) donc triviaux à énumérer, et le téléphone n'est comparé que
-- sur ses 8 derniers chiffres (tolérance de saisie voulue, conservée ici). Sans
-- limite d'appels, un script pouvait donc parcourir tous les codes et essayer des
-- numéros jusqu'à tomber juste, exposant projets, devis et factures de chaque
-- client. Ce fichier ajoute :
--   1. une limite GLOBALE anti-parcours automatisé (30 appels / minute, tous
--      codes confondus) ;
--   2. un verrou PAR CODE (5 échecs / 15 min → blocage 30 min) qui empêche de
--      forcer le téléphone d'un client précis, même son code connu ;
-- sans changer la tolérance de saisie du téléphone ni le format de réponse pour
-- un utilisateur légitime. Purge automatique des anciennes tentatives (> 1 jour).
-- Idempotent : peut être rejoué.
-- ============================================================================
create table if not exists public.portail_tentatives (
  id uuid primary key default gen_random_uuid(),
  code_normalise text not null,
  succes boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_portail_tentatives_code on public.portail_tentatives (code_normalise, created_at desc);
create index if not exists idx_portail_tentatives_date on public.portail_tentatives (created_at desc);
alter table public.portail_tentatives enable row level security;
-- Aucune politique : ni anon ni authenticated n'ont de droit direct, seule la fonction SECURITY DEFINER y accède.
revoke all on public.portail_tentatives from public, anon, authenticated;

create or replace function public.portail_lookup(p_code text, p_telephone text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_client clients%rowtype;
  v_result jsonb;
  v_digits text := regexp_replace(coalesce(p_telephone,''), '\D', '', 'g');
  v_code_norm text := upper(trim(coalesce(p_code,'')));
  v_actif boolean;
  v_recent_global int;
  v_recent_code_fails int;
  v_trouve boolean;
begin
  select portail_actif into v_actif from parametres limit 1;
  if not coalesce(v_actif,false) then
    return jsonb_build_object('found', false, 'disabled', true);
  end if;

  if v_code_norm = '' or v_digits = '' then
    return jsonb_build_object('found', false);
  end if;

  -- purge opportuniste (évite un job planifié dédié)
  if random() < 0.02 then
    delete from portail_tentatives where created_at < now() - interval '1 day';
  end if;

  select count(*) into v_recent_global from portail_tentatives where created_at > now() - interval '1 minute';
  if v_recent_global >= 30 then
    return jsonb_build_object('found', false, 'limite', true);
  end if;

  select count(*) into v_recent_code_fails from portail_tentatives
    where code_normalise = v_code_norm and not succes and created_at > now() - interval '15 minutes';
  if v_recent_code_fails >= 5 then
    insert into portail_tentatives(code_normalise, succes) values (v_code_norm, false);
    return jsonb_build_object('found', false, 'limite', true);
  end if;

  select * into v_client
  from clients
  where upper(trim(code)) = v_code_norm
    and regexp_replace(coalesce(telephone,''), '\D', '', 'g') <> ''
    and right(regexp_replace(coalesce(telephone,''), '\D', '', 'g'), 8) = right(v_digits, 8)
  limit 1;

  v_trouve := v_client.id is not null;
  insert into portail_tentatives(code_normalise, succes) values (v_code_norm, v_trouve);

  if not v_trouve then
    return jsonb_build_object('found', false);
  end if;

  select jsonb_build_object(
    'found', true,
    'client', jsonb_build_object(
      'code', v_client.code, 'nom', v_client.nom, 'prenoms', v_client.prenoms,
      'civilite', v_client.civilite, 'entreprise', v_client.entreprise,
      'commune', v_client.commune
    ),
    'projets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', pr.code, 'libelle', pr.libelle, 'etape', pr.etape,
        'date_debut', pr.date_debut, 'date_fin', pr.date_fin, 'commune', pr.commune
      ) order by pr.created_at desc)
      from projets pr where pr.client_id = v_client.id
    ), '[]'::jsonb),
    'devis', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', d.code, 'libelle', d.libelle, 'statut', d.statut,
        'total', d.total, 'date_creation', d.date_creation
      ) order by d.created_at desc)
      from devis d where d.client_id = v_client.id
    ), '[]'::jsonb),
    'factures', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', f.code, 'statut', f.statut, 'total', f.total,
        'date_facture', f.date_facture, 'type_facture', f.type_facture
      ) order by f.created_at desc)
      from factures f where f.client_id = v_client.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;
revoke all on function public.portail_lookup(text,text) from public;
grant execute on function public.portail_lookup(text,text) to anon, authenticated;


-- ===========================================================================
-- 24. Portail client — URL du site public, pour l'envoi du code d'accès (copie de sql/portail_url.sql)
-- ===========================================================================
-- ============================================================================
-- Portail client — URL du site public (pour l'envoi du code d'accès aux clients)
-- ============================================================================
alter table public.parametres add column if not exists portail_url text;
