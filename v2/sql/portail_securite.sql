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

notify pgrst, 'reload schema';
