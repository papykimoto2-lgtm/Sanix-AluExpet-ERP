-- ============================================================================
-- Sanix AluExpert ERP — Révocation réelle des sessions (revue de sécurité)
-- ============================================================================
-- À exécuter UNE FOIS dans l'éditeur SQL Supabase (après sql/utilisateurs_auth_menko.sql).
-- Jusqu'ici, « Déconnecter tous les postes » et la désactivation d'un compte n'agissaient que
-- dans l'application : un jeton de session déjà émis restait utilisable directement auprès du
-- serveur. Désormais les sessions sont supprimées côté serveur (auth.sessions ; les jetons de
-- renouvellement liés disparaissent avec elles) : un appareil perdu ou un compte désactivé
-- ne peut plus rien lire ni écrire, même avec un jeton copié.
-- ============================================================================

-- Déconnexion générale : tous les postes sauf celui de l'administrateur qui la déclenche
create or replace function public.forcer_deconnexion_generale() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v timestamptz := now();
begin
  if not public.is_admin() then raise exception 'Réservé à un administrateur'; end if;
  update parametres set deconnexion_forcee_le = v where true;
  delete from auth.sessions where user_id <> auth.uid();
  return v;
end $$;
revoke execute on function public.forcer_deconnexion_generale() from public, anon;
grant execute on function public.forcer_deconnexion_generale() to authenticated;

-- Compte désactivé : ses sessions sont supprimées immédiatement
create or replace function public.profiles_revoquer_sessions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.actif, true) = false and coalesce(old.actif, true) = true then
    delete from auth.sessions where user_id = new.id;
  end if;
  return new;
end $$;
revoke execute on function public.profiles_revoquer_sessions() from public, anon, authenticated;
drop trigger if exists trg_profiles_revoquer_sessions on public.profiles;
create trigger trg_profiles_revoquer_sessions after update of actif on public.profiles
  for each row execute function public.profiles_revoquer_sessions();
