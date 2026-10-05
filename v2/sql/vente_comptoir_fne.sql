-- ============================================================================
-- Sanix AluExpert ERP — Vente au comptoir : facture simple et facture normalisée FNE (DGI)
-- ============================================================================
-- À exécuter APRÈS sql/depots_points_vente_transferts.sql. Additif.
-- La certification passe par l'Edge Function `fne-proxy` (supabase/functions/fne-proxy),
-- car l'API FNE n'est pas appelable directement depuis le navigateur (CORS / http).
-- ============================================================================

alter table ventes_comptoir add column if not exists fne_statut text
  check (fne_statut in ('certifiee','provisoire','erreur'));
alter table ventes_comptoir add column if not exists fne_reference text;        -- n° de facture FNE (ex. 9606123E2500000019)
alter table ventes_comptoir add column if not exists fne_token text;            -- URL de vérification → QR code
alter table ventes_comptoir add column if not exists fne_invoice_id text;       -- id FNE (nécessaire pour l'avoir)
alter table ventes_comptoir add column if not exists fne_template text;         -- B2C / B2B / B2G
alter table ventes_comptoir add column if not exists fne_client_nom text;
alter table ventes_comptoir add column if not exists fne_client_ncc text;
alter table ventes_comptoir add column if not exists fne_client_telephone text;
alter table ventes_comptoir add column if not exists fne_client_email text;
alter table ventes_comptoir add column if not exists fne_certifiee_le timestamptz;
alter table ventes_comptoir add column if not exists fne_erreur text;
alter table ventes_comptoir add column if not exists fne_reponse jsonb;         -- réponse brute de la DGI (audit)
alter table ventes_comptoir add column if not exists fne_avoir_reference text;  -- n° de la facture d'avoir FNE après annulation
alter table ventes_comptoir add column if not exists fne_avoir_token text;
alter table ventes_comptoir add column if not exists facture_imprimee_le timestamptz;

-- Code de TVA FNE appliqué par défaut aux articles (TVA 18 %, TVAB 9 %, TVAC exo. conv., TVAD exo. légale TEE/RME)
alter table parametres add column if not exists fne_taxe_defaut text not null default 'TVA'
  check (fne_taxe_defaut in ('TVA','TVAB','TVAC','TVAD'));

-- Destinataire de la facture simple (client de passage)
alter table ventes_comptoir add column if not exists client_ncc text;
alter table ventes_comptoir add column if not exists client_adresse text;
