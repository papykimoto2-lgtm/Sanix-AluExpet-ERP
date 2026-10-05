-- ============================================================================
-- Sanix AluExpert ERP — Comptes comptables par défaut (Paramétrage → Comptabilité)
-- ============================================================================
-- À exécuter dans l'éditeur SQL Supabase, APRÈS sql/comptabilite_syscohada.sql.
-- Additif : ajoute une seule colonne à la table `parametres` existante.
-- ============================================================================

alter table parametres add column if not exists comptes_defaut jsonb not null default '{}'::jsonb;
