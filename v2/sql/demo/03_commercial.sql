-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (3/6) : chantiers, devis, fiches d'exécution, factures, paiements
-- (à lancer après 02_stock_achats.sql)
-- ============================================================================
create or replace function pg_temp.cli(p_nom text) returns uuid language sql as $$ select id from public.clients where nom = p_nom $$;

-- Prix d'une ligne de devis d'après le catalogue (m² = L×H, ml = longueur, unité = pièce)
create or replace function pg_temp.prix(p_produit text, p_l numeric, p_h numeric) returns numeric language sql as $$
  select round(case unite when 'm2' then prix_vente * greatest(p_l * p_h / 1000000.0, 1.0) when 'ml' then prix_vente * greatest(p_l / 1000.0, 1) else prix_vente end, -2)
    from public.produits where nom like p_produit || '%' limit 1
$$;

create or replace function pg_temp.mk_devis(p_client text, p_libelle text, p_statut text, p_cat text, p_jours int, p_projet uuid, p_commercial text,
    p_lieu text, p_lignes jsonb, p_reduction numeric default 0, p_pose numeric default 0, p_frais numeric default 0, p_echeance_jours int default 30,
    p_version int default 1, p_racine uuid default null, p_current boolean default true) returns uuid language plpgsql as $$
declare
  v_id uuid; l jsonb; i int := 0; v_total numeric := 0; v_pu numeric; v_ligne numeric; v_prod public.produits;
  v_commune text; v_quartier text;
begin
  select commune, quartier into v_commune, v_quartier from public.clients where nom = p_client;
  insert into public.devis (libelle, client_id, projet_id, date_creation, date_echeance, statut, categorie, commercial, lieu_affaire, commune, quartier,
                            reduction, autre_frais, main_oeuvre, created_by, created_at, version_number, is_current, racine_id)
    values (p_libelle, pg_temp.cli(p_client), p_projet, current_date + p_jours, current_date + p_jours + p_echeance_jours, p_statut, p_cat, p_commercial, p_lieu,
            v_commune, v_quartier, p_reduction, p_frais, p_pose, '00000000-0000-4000-8000-000000000001', (current_date + p_jours)::timestamptz + interval '9 hours',
            p_version, p_current, p_racine)
    returning id into v_id;
  for l in select * from jsonb_array_elements(p_lignes) loop
    i := i + 1;
    select * into v_prod from public.produits where nom like (l->>'produit') || '%' limit 1;
    v_pu := pg_temp.prix(l->>'produit', (l->>'l')::numeric, (l->>'h')::numeric);
    v_ligne := coalesce((l->>'q')::numeric, 1) * v_pu * (1 - coalesce((l->>'remise')::numeric, 0) / 100);
    insert into public.devis_lignes (devis_id, piece, produit_id, titre, largeur, hauteur, quantite, remise_pct, prix_unitaire, total, ordre, cout_materiel_pct)
      values (v_id, l->>'piece', v_prod.id, coalesce(l->>'titre', v_prod.nom), coalesce((l->>'l')::numeric, 0), coalesce((l->>'h')::numeric, 0),
              coalesce((l->>'q')::numeric, 1), coalesce((l->>'remise')::numeric, 0), v_pu, v_ligne, i, coalesce(v_prod.cout_materiel_pct, 60));
    v_total := v_total + v_ligne;
  end loop;
  update public.devis set total = v_total - p_reduction + p_frais + p_pose where id = v_id;
  return v_id;
end $$;

do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid; p7 uuid; p8 uuid; p9 uuid; p10 uuid; p11 uuid; p12 uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; d6 uuid; d7 uuid; d8 uuid; d9 uuid; d10a uuid; d10 uuid;
  f record; v_fiche uuid; l record; v_f uuid;
  v_tot numeric;
begin
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  -- ---------- Chantiers ----------
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Villa Kouassi — menuiseries complètes', pg_temp.cli('KOUASSI'), current_date-80, current_date-20, 'Cocody', 'Riviera Palmeraie', 'Villa / résidentiel', 'Recommandation', 'Moussa Koné', 'Fenêtres, baies, porte d''entrée et garde-corps d''une villa R+1.', 'termine', 5.3589, -3.9631, v_admin, now()-interval '90 days') returning id into p1;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('SCI Les Palmiers — appartements témoins', pg_temp.cli('SCI LES PALMIERS'), current_date-55, current_date+20, 'Cocody', 'Angré 8e tranche', 'Villa / résidentiel', 'Appel d''offres', 'Fatou Diabaté', '3 appartements témoins du programme de 24 logements.', 'fabrication_en_cours', 5.3925, -3.9876, v_admin, now()-interval '72 days') returning id into p2;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Hôtel Le Baobab — façade et baies', pg_temp.cli('HÔTEL LE BAOBAB SARL'), current_date-45, current_date+10, 'Plateau', 'Boulevard de la République', 'Hôtellerie', 'Salon professionnel', 'Fatou Diabaté', 'Façade vitrée du hall, baies des chambres témoins, cloison d''accueil.', 'installation_en_cours', 5.3197, -4.0166, v_admin, now()-interval '64 days') returning id into p3;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Pharmacie Sainte Marie — vitrine', pg_temp.cli('PHARMACIE SAINTE MARIE'), current_date-48, current_date-30, 'Yopougon', 'Selmer', 'Commercial & bureaux', 'Passage devant l''atelier', 'Moussa Koné', 'Vitrine et porte d''entrée vitrée de l''officine.', 'termine', 5.3412, -4.0810, v_admin, now()-interval '57 days') returning id into p4;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Résidence Les Orchidées — garde-corps lot A', pg_temp.cli('RÉSIDENCE LES ORCHIDÉES'), current_date-10, current_date+35, 'Bingerville', 'Cité des cadres', 'Villa / résidentiel', 'Site web', 'Fatou Diabaté', 'Garde-corps inox et verre des balcons et escaliers du lot A.', 'pret_fabrication', 5.3562, -3.8869, v_admin, now()-interval '42 days') returning id into p5;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Clinique La Providence — cloisons et portes', pg_temp.cli('CLINIQUE LA PROVIDENCE'), current_date-6, current_date+40, 'Cocody', 'Danga', 'Santé & éducation', 'Appel d''offres', 'Fatou Diabaté', 'Cloisons vitrées des consultations et portes des salles de soins.', 'mesure_disponible', 5.3501, -3.9980, v_admin, now()-interval '35 days') returning id into p6;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Groupe scolaire Excellence — fenêtres des 12 classes', pg_temp.cli('GROUPE SCOLAIRE EXCELLENCE'), null, null, 'Abobo', 'Avocatier', 'Santé & éducation', 'Recommandation', 'Fatou Diabaté', 'Remplacement de 48 fenêtres — négociation en cours.', 'en_attente', 5.4181, -4.0212, v_admin, now()-interval '28 days') returning id into p7;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Villa Diallo — baies, moustiquaires et douches', pg_temp.cli('DIALLO'), current_date-18, current_date+12, 'Cocody', 'Deux-Plateaux', 'Villa / résidentiel', 'Recommandation', 'Moussa Koné', 'Deux baies coulissantes, six fenêtres, moustiquaires et deux cabines de douche.', 'fabrication_en_cours', 5.3702, -4.0007, v_admin, now()-interval '28 days') returning id into p8;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('DR Habitat — cloisons des bureaux', pg_temp.cli('DIRECTION RÉGIONALE DE L''HABITAT'), null, null, 'Plateau', 'Cité administrative', 'Commercial & bureaux', 'Appel d''offres', 'Fatou Diabaté', 'Cloisons vitrées de 8 bureaux — en attente de validation budgétaire.', 'en_attente', 5.3235, -4.0186, v_admin, now()-interval '15 days') returning id into p9;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Boulangerie La Mie Dorée — devanture', pg_temp.cli('BOULANGERIE LA MIE DORÉE'), current_date-9, current_date+3, 'Port-Bouët', 'Gonzagueville', 'Commercial & bureaux', 'Passage devant l''atelier', 'Moussa Koné', 'Devanture vitrée, porte d''entrée et volet roulant motorisé.', 'installation_en_cours', 5.2513, -3.9309, v_admin, now()-interval '24 days') returning id into p10;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Maison Yao — portes et fenêtres', pg_temp.cli('YAO'), current_date-60, current_date-38, 'Koumassi', 'Remblais', 'Villa / résidentiel', 'Facebook', 'Moussa Koné', 'Renouvellement des menuiseries d''une maison familiale.', 'termine', 5.2931, -3.9512, v_admin, now()-interval '66 days') returning id into p11;
  insert into public.projets (libelle, client_id, date_debut, date_fin, commune, quartier, categorie, source, responsable, description, etape, latitude, longitude, created_by, created_at) values
   ('Villa Bamba — fenêtres et pergola', pg_temp.cli('BAMBA'), null, null, 'Yopougon', 'Niangon', 'Villa / résidentiel', 'Facebook', 'Moussa Koné', 'Annulé : budget non confirmé par le client.', 'annule', 5.3300, -4.1000, v_admin, now()-interval '32 days') returning id into p12;

  -- ---------- Devis ----------
  d1 := pg_temp.mk_devis('KOUASSI', 'Menuiseries villa R+1 — Riviera Palmeraie', 'accepte', 'Villa / résidentiel', -88, p1, 'Moussa Koné', 'Riviera Palmeraie, lot 214',
    '[{"piece":"Salon","produit":"Baie coulissante","l":3000,"h":2200,"q":1},{"piece":"Chambres","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":3},{"piece":"Cuisine","produit":"Fenêtre à la française","l":800,"h":1000,"q":1},{"piece":"Entrée","produit":"Porte d''entrée","q":1},{"piece":"Terrasse","produit":"Garde-corps verre","l":6000,"h":1000,"q":1},{"piece":"Chambres","produit":"Moustiquaire","l":1500,"h":1200,"q":3}]', 150000, 450000);
  d2 := pg_temp.mk_devis('SCI LES PALMIERS', 'Appartements témoins — 3 unités', 'accepte', 'Villa / résidentiel', -70, p2, 'Fatou Diabaté', 'Angré 8e tranche',
    '[{"piece":"Séjours","produit":"Baie coulissante","l":2400,"h":2200,"q":6,"remise":8},{"piece":"Chambres","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":18,"remise":8},{"piece":"Balcons","produit":"Porte coulissante","l":2000,"h":2100,"q":3,"remise":8},{"piece":"Intérieur","produit":"Porte intérieure","q":9,"remise":8}]', 0, 900000);
  d3 := pg_temp.mk_devis('HÔTEL LE BAOBAB SARL', 'Façade vitrée du hall et baies des chambres', 'accepte', 'Hôtellerie', -62, p3, 'Fatou Diabaté', 'Boulevard de la République, Plateau',
    '[{"piece":"Hall","produit":"Façade vitrée","l":5000,"h":3200,"q":1},{"piece":"Hall","produit":"Porte d''entrée","q":2},{"piece":"Chambres témoins","produit":"Baie coulissante","l":3000,"h":2200,"q":4},{"piece":"Accueil","produit":"Cloison vitrée","l":3000,"h":2500,"q":1}]', 250000, 1200000);
  d4 := pg_temp.mk_devis('PHARMACIE SAINTE MARIE', 'Vitrine et porte d''entrée de la pharmacie', 'accepte', 'Commercial & bureaux', -55, p4, 'Moussa Koné', 'Carrefour Selmer, Yopougon',
    '[{"piece":"Façade","produit":"Façade vitrée","l":3500,"h":2400,"q":1},{"piece":"Entrée","produit":"Porte d''entrée","q":1}]', 0, 180000);
  d5 := pg_temp.mk_devis('RÉSIDENCE LES ORCHIDÉES', 'Garde-corps inox et verre — lot A', 'accepte', 'Villa / résidentiel', -40, p5, 'Fatou Diabaté', 'Lotissement Les Orchidées, Bingerville',
    '[{"piece":"Balcons","produit":"Garde-corps inox","l":48000,"h":1000,"q":1},{"piece":"Escaliers","produit":"Garde-corps verre","l":22000,"h":1000,"q":1}]', 0, 600000);
  d6 := pg_temp.mk_devis('CLINIQUE LA PROVIDENCE', 'Cloisons vitrées et portes — consultations', 'accepte', 'Santé & éducation', -33, p6, 'Fatou Diabaté', 'Danga, Cocody',
    '[{"piece":"Consultations","produit":"Cloison vitrée","l":6000,"h":2600,"q":1},{"piece":"Salles de soins","produit":"Porte intérieure","q":10},{"piece":"Couloir","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":8}]', 100000, 520000);
  d7 := pg_temp.mk_devis('DIALLO', 'Baies, fenêtres, moustiquaires et douches', 'accepte', 'Villa / résidentiel', -26, p8, 'Moussa Koné', 'Deux-Plateaux Vallons, villa 18',
    '[{"piece":"Salon","produit":"Baie coulissante","l":3200,"h":2200,"q":2},{"piece":"Chambres","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":6},{"piece":"Chambres","produit":"Moustiquaire","l":1500,"h":1200,"q":6},{"piece":"Salles de bain","produit":"Cabine de douche","q":2}]', 0, 380000);
  d8 := pg_temp.mk_devis('BOULANGERIE LA MIE DORÉE', 'Devanture vitrée et volet roulant', 'accepte', 'Commercial & bureaux', -22, p10, 'Moussa Koné', 'Gonzagueville, route de Bassam',
    '[{"piece":"Devanture","produit":"Façade vitrée","l":3000,"h":2400,"q":1},{"piece":"Entrée","produit":"Porte d''entrée","q":1},{"piece":"Laboratoire","produit":"Volet roulant","l":3000,"h":2400,"q":1}]', 0, 260000);
  d9 := pg_temp.mk_devis('YAO', 'Portes et fenêtres — maison familiale', 'accepte', 'Villa / résidentiel', -50, p11, 'Moussa Koné', 'Koumassi Remblais',
    '[{"piece":"Intérieur","produit":"Porte intérieure","q":3},{"piece":"Entrée","produit":"Porte d''entrée","q":1},{"piece":"Façades","produit":"Fenêtre coulissante","l":1200,"h":1200,"q":4}]', 0, 220000);
  -- Groupe scolaire : V1 refusée (trop chère), V2 en négociation
  d10a := pg_temp.mk_devis('GROUPE SCOLAIRE EXCELLENCE', 'Fenêtres des 12 classes — V1', 'refuse', 'Santé & éducation', -24, p7, 'Fatou Diabaté', 'Abobo Avocatier',
    '[{"piece":"Classes","produit":"Fenêtre coulissante","l":1500,"h":1500,"q":48},{"piece":"Salles","produit":"Porte intérieure","q":12}]', 0, 1800000, 0, 30, 1, null, false);
  d10 := pg_temp.mk_devis('GROUPE SCOLAIRE EXCELLENCE', 'Fenêtres des 12 classes — V2 (remise 10 %)', 'en_cours', 'Santé & éducation', -12, p7, 'Fatou Diabaté', 'Abobo Avocatier',
    '[{"piece":"Classes","produit":"Fenêtre coulissante","l":1500,"h":1500,"q":48,"remise":10},{"piece":"Salles","produit":"Porte intérieure","q":12,"remise":10}]', 0, 1500000, 0, 30, 2, (select racine_id from public.devis where id = d10a), true);
  perform pg_temp.mk_devis('DIRECTION RÉGIONALE DE L''HABITAT', 'Cloisons vitrées — 8 bureaux', 'en_attente', 'Commercial & bureaux', -5, p9, 'Fatou Diabaté', 'Cité administrative, Plateau',
    '[{"piece":"Bureaux","produit":"Cloison vitrée","l":12000,"h":2600,"q":1},{"piece":"Bureaux","produit":"Porte intérieure","q":8}]', 0, 650000);
  perform pg_temp.mk_devis('TRAORÉ', 'Fenêtres, moustiquaires et porte coulissante', 'en_attente', 'Villa / résidentiel', -3, null, 'Moussa Koné', 'Résidence Les Cocotiers, Marcory',
    '[{"piece":"Chambres","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":4},{"piece":"Chambres","produit":"Moustiquaire","l":1500,"h":1200,"q":4},{"piece":"Terrasse","produit":"Porte coulissante","l":2000,"h":2100,"q":1}]', 0, 150000);
  perform pg_temp.mk_devis('ETS KONATÉ & FILS', 'Portail coulissant et volet roulant', 'en_attente', 'Commercial & bureaux', -2, null, 'Moussa Koné', 'Zone 3, Treichville',
    '[{"piece":"Entrée cour","produit":"Portail coulissant","l":4000,"h":2000,"q":1},{"piece":"Magasin","produit":"Volet roulant","l":2500,"h":2200,"q":1}]', 0, 200000);
  perform pg_temp.mk_devis('BAMBA', 'Fenêtres et pergola — villa Niangon', 'refuse', 'Villa / résidentiel', -30, p12, 'Moussa Koné', 'Niangon Nord',
    '[{"piece":"Villa","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":6},{"piece":"Terrasse","produit":"Pergola","l":5000,"h":3500,"q":1}]', 0, 300000);
  perform pg_temp.mk_devis('KOUASSI', 'Pergola aluminium — terrasse', 'en_cours', 'Villa / résidentiel', -4, null, 'Moussa Koné', 'Riviera Palmeraie, lot 214',
    '[{"piece":"Terrasse","produit":"Pergola","l":5000,"h":3500,"q":1}]', 0, 250000);
  perform pg_temp.mk_devis('CLINIQUE LA PROVIDENCE', 'Ancien devis — portes automatiques', 'annule', 'Santé & éducation', -45, null, 'Fatou Diabaté', 'Danga, Cocody',
    '[{"piece":"Accueil","produit":"Porte coulissante","l":2400,"h":2200,"q":2}]', 0, 150000);
  perform pg_temp.mk_devis('SCI LES PALMIERS', 'Phase 2 — 24 appartements (fenêtres et baies)', 'en_attente', 'Villa / résidentiel', -1, null, 'Fatou Diabaté', 'Angré 8e tranche',
    '[{"piece":"Séjours","produit":"Baie coulissante","l":2400,"h":2200,"q":24,"remise":12},{"piece":"Chambres","produit":"Fenêtre coulissante","l":1500,"h":1200,"q":72,"remise":12},{"piece":"Cuisines","produit":"Fenêtre à la française","l":800,"h":1000,"q":24,"remise":12}]', 0, 3200000);

  -- ---------- Fiches d'exécution (mesures, fabrication, pose) ----------
  for f in select d.id as devis_id, d.projet_id, p.etape, d.commercial, d.lieu_affaire from public.devis d join public.projets p on p.id = d.projet_id where d.statut = 'accepte' loop
    insert into public.fiches_execution (devis_id, projet_id, commercial, lieu_affaire, date_visite, responsable_chantier, statut, created_by, created_at,
        mesure_prise_par, mesure_prise_le, fabrication_lancee_par, fabrication_lancee_le)
      values (f.devis_id, f.projet_id, f.commercial, f.lieu_affaire, current_date - 30, 'Karim Ouattara',
        case f.etape when 'termine' then 'termine' when 'en_attente' then 'en_attente' when 'mesure_disponible' then 'en_attente' else 'en_cours' end, v_admin, now() - interval '30 days',
        case when f.etape in ('mesure_disponible','pret_fabrication','fabrication_en_cours','installation_en_cours','termine') then v_admin end, case when f.etape in ('mesure_disponible','pret_fabrication','fabrication_en_cours','installation_en_cours','termine') then now() - interval '25 days' end,
        case when f.etape in ('fabrication_en_cours','installation_en_cours','termine') then v_admin end, case when f.etape in ('fabrication_en_cours','installation_en_cours','termine') then now() - interval '18 days' end)
      returning id into v_fiche;
    for l in select * from public.devis_lignes where devis_id = f.devis_id order by ordre limit 8 loop
      insert into public.fiche_execution_lignes (fiche_id, devis_ligne_id, piece, produit, largeur_commande, hauteur_commande, largeur_mesuree, hauteur_mesuree,
          fabrication_alu, fabrication_vitrage, pose_alu, pose_vitrage, controle_re, controle_termine, commentaires, ordre)
        values (v_fiche, l.id, l.piece, l.titre, l.largeur, l.hauteur,
          case when f.etape <> 'en_attente' and l.largeur > 0 then l.largeur - 5 end, case when f.etape <> 'en_attente' and l.hauteur > 0 then l.hauteur - 3 end,
          case when f.etape in ('fabrication_en_cours','installation_en_cours','termine') then 'oui' when f.etape = 'pret_fabrication' then 'non' end,
          case when f.etape in ('installation_en_cours','termine') then 'oui' when f.etape = 'fabrication_en_cours' then 'non' end,
          case when f.etape = 'termine' then 'oui' when f.etape = 'installation_en_cours' then 'non' end,
          case when f.etape = 'termine' then 'oui' when f.etape = 'installation_en_cours' then 'non' end,
          case when f.etape = 'termine' then 'oui' end, case when f.etape = 'termine' then 'oui' end,
          case when l.ordre = 1 and f.etape <> 'en_attente' then 'Mesures relevées sur site, tolérance de pose 5 mm.' end, l.ordre);
    end loop;
  end loop;
  update public.fiches_execution f set updated_at = now() - interval '2 days';
end $$;

-- ---------- Factures et paiements ----------
do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  r record; v_fac uuid; v_tot numeric; n int := 0;
begin
  for r in
    select d.id, d.client_id, d.total, d.libelle, p.etape, d.date_creation,
           row_number() over (order by d.date_creation) as rn
      from public.devis d join public.projets p on p.id = d.projet_id
     where d.statut = 'accepte' order by d.date_creation
  loop
    n := r.rn;
    insert into public.factures (devis_id, client_id, date_facture, total, statut, created_by, created_at, type_facture, fne_reference, fne_statut)
      values (r.id, r.client_id, r.date_creation + 4, r.total, 'en_attente', v_admin, (r.date_creation + 4)::timestamptz + interval '10 hours',
              case when n in (1,2,3,6) then 'fne' else 'simple' end,
              case when n in (1,2,3,6) then 'FNE-DEMO-' || lpad(n::text, 5, '0') end,
              case when n in (1,2,3) then 'certifiee' when n = 6 then 'provisoire' end)
      returning id into v_fac;
    -- règlements : chantiers terminés soldés ; chantiers en cours : acompte ; derniers dossiers : non réglés
    if r.etape = 'termine' then
      insert into public.paiements (facture_id, date_paiement, montant, mode, reference, created_by, created_at) values
        (v_fac, r.date_creation + 6, round(r.total * 0.5), case when n % 2 = 0 then 'mobile_money' else 'banque' end, 'ACOMPTE-' || n, v_admin, (r.date_creation + 6)::timestamptz),
        (v_fac, r.date_creation + 35, r.total - round(r.total * 0.5), case when n % 3 = 0 then 'mobile_money' else 'banque' end, 'SOLDE-' || n, v_admin, (r.date_creation + 35)::timestamptz);
      update public.factures set statut = 'payee' where id = v_fac;
    elsif r.etape in ('fabrication_en_cours','installation_en_cours') then
      insert into public.paiements (facture_id, date_paiement, montant, mode, reference, created_by, created_at)
        values (v_fac, r.date_creation + 7, round(r.total * 0.5), case when n % 2 = 0 then 'mobile_money' else 'banque' end, 'ACOMPTE-' || n, v_admin, (r.date_creation + 7)::timestamptz);
      update public.factures set statut = 'payee_partielle' where id = v_fac;
    elsif r.etape = 'mesure_disponible' then
      insert into public.paiements (facture_id, date_paiement, montant, mode, reference, created_by, created_at)
        values (v_fac, r.date_creation + 8, round(r.total * 0.3), 'mobile_money', 'ACOMPTE-' || n, v_admin, (r.date_creation + 8)::timestamptz);
      update public.factures set statut = 'payee_partielle' where id = v_fac;
    end if;  -- 'pret_fabrication' : facture émise, non réglée (impayé à relancer)
  end loop;
  -- un règlement en espèces (encaissé à la caisse principale) sur la facture de la maison Yao
  update public.paiements set mode = 'espece', caisse_id = (select id from public.caisses limit 1)
   where reference like 'SOLDE-%'
     and facture_id = (select f.id from public.factures f join public.devis d on d.id = f.devis_id where d.libelle like 'Portes et fenêtres%');
end $$;
