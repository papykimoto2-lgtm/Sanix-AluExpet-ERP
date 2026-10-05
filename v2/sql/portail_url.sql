-- ============================================================================
-- Portail client — URL du site public (pour l'envoi du code d'accès aux clients)
-- ============================================================================
alter table public.parametres add column if not exists portail_url text;
notify pgrst, 'reload schema';
