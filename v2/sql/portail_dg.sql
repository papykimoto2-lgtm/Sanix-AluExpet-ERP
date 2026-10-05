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

notify pgrst, 'reload schema';
