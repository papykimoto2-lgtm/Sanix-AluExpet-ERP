-- ============================================================================
-- Sanix AluExpert ERP — Mode hors ligne (offline-first)
-- ============================================================================
-- Une vente au comptoir faite sans connexion reçoit sur l'appareil son identifiant et un code
-- provisoire « VCH-AAAA-XXXXXXX » ; à la synchronisation, la vente est créée avec CES valeurs
-- (les documents déjà imprimés restent valables et un envoi rejoué ne crée pas de doublon).
-- Les ventes en ligne gardent la numérotation VC-AAAA-00001 (le code n'est alors pas fourni).
-- ============================================================================
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
