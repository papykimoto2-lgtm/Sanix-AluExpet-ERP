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

notify pgrst, 'reload schema';
