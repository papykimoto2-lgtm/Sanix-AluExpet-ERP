-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (2/6) : stock, achats, transferts, inventaire
-- (à lancer après 01_base.sql). Utilise les vraies fonctions de l'application (stock_mouvement, commandes, réceptions…).
-- ============================================================================
create or replace function pg_temp.cid(p_code text) returns uuid language sql as $$ select id from public.composants where code = p_code $$;
create or replace function pg_temp.dep(p_code text) returns uuid language sql as $$ select id from public.depots where code = p_code $$;
create or replace function pg_temp.frn(p_code text) returns uuid language sql as $$ select id from public.fournisseurs where code = p_code $$;

do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  r record;
  v_bc public.commandes_fournisseur;
  v_br public.receptions_fournisseur;
  v_lignes jsonb;
  v_ci public.commandes_internes;
  v_t public.transferts_stock;
  v_inv public.inventaires;
begin
  -- on agit au nom de l'administrateur de démonstration
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- ---------- Stock initial du dépôt principal (entrées valorisées au CMUP) ----------
  for r in select * from (values
    ('P-COU-OV',180),('P-COU-RH',150),('P-COU-RB',150),('P-COU-MD',160),('P-STD-001',140),('P-STD-002',140),('P-STD-003',130),('P-STD-004',130),
    ('P-POR-DOR',90),('P-POR-OUV',90),('P-MR-TRA',60),('P-MR-MON',60),('P-VER-40',120),('P-SEU-001',50),('P-MEN-001',80),('P-PAR-001',200),
    ('TUB-ALU-80',70),('TUB-ALU-25',90),('POT-GI-001',60),('TUB-INX-20',80),('LIS-GI-012',70),('MC-GI-001',50),('CAB-GI-001',400),
    ('VIT-001',120),('VIT-GI-001',60),('VIT-TRE-8',6),('VIT-TRE-10',24),('TOI-MOU-ENR',30),('TUL-MO-001',40),
    ('QUI-001-PORTE',30),('QUI-003',4),('QUI-CRM-001',60),('QUI-ROU-001',300),('QUI-GAL-001',120),('QUI-SER-3P',14),('QUI-CYL-001',28),
    ('FIX-CHV-001',1500),('FIX-RIV-001',2000),('JNT-ONG-001',600),('JNT-EQ-001',500),
    ('JNT-001',500),('JNT-FRP-001',400),('CON-001',8),('CON-SIL-STR',20),('PIN-GI-001',80),('PLA-GI-001',60),('TEN-GI-001',90),
    ('MOT-TUB-001',8),('PAN-SAND-24',40),('ACM-004',30)
  ) t(code, qte)
  loop
    perform public.stock_mouvement(pg_temp.cid(r.code), 'entree', r.qte, 'Stock initial', 'INIT-DEMO',
      (select round(prix_unitaire * 0.93, 2) from public.composants where code = r.code), pg_temp.dep('DEP-01'));
  end loop;
  -- seuils de réapprovisionnement (3 articles volontairement sous le minimum pour alimenter les alertes)
  update public.composants set stock_min = 20, stock_max = 80 where code in ('VIT-TRE-8','QUI-003','CON-001','QUI-SER-3P');
  update public.composants set stock_min = 60, stock_max = 250 where code in ('P-COU-OV','P-COU-RH','P-COU-RB','P-STD-003','P-STD-004');
  update public.composants set stock_min = 30, stock_max = 120 where code in ('VIT-001','VIT-GI-001','QUI-CRM-001','TUB-INX-20');
  update public.composants set emplacement = case
      when famille = 'Profilé aluminium' then 'Rack A' when famille = 'Vitrage' then 'Chevalets vitrage'
      when famille = 'Quincaillerie' then 'Étagère Q' when famille = 'Visserie & fixations' then 'Étagère V'
      else 'Zone consommables' end
    where stock_actuel > 0;

  -- ---------- Achats : commandes fournisseurs de tous statuts ----------
  -- 1. Profilés — reçue en totalité
  v_bc := public.commande_fournisseur_enregistrer(null, jsonb_build_object('fournisseur_id', pg_temp.frn('F-DEMO-01'), 'depot_id', pg_temp.dep('DEP-01'),
    'date_commande', current_date - 62, 'date_livraison_prevue', current_date - 55, 'reference_fournisseur', 'DEVIS-ADC-2291', 'conditions', 'Paiement à 30 jours', 'tva_pct', 18),
    jsonb_build_array(
      jsonb_build_object('composant_id', pg_temp.cid('P-COU-OV'), 'quantite', 120, 'prix_unitaire', 9300),
      jsonb_build_object('composant_id', pg_temp.cid('P-COU-RB'), 'quantite', 100, 'prix_unitaire', 9900),
      jsonb_build_object('composant_id', pg_temp.cid('P-STD-003'), 'quantite', 80,  'prix_unitaire', 8700, 'remise_pct', 3)));
  perform public.commande_fournisseur_action(v_bc.id, 'envoyer');
  select jsonb_agg(jsonb_build_object('commande_ligne_id', id, 'composant_id', composant_id, 'quantite', quantite, 'prix_unitaire', round(prix_unitaire*(1-remise_pct/100),2)))
    into v_lignes from public.commandes_fournisseur_lignes where commande_id = v_bc.id;
  v_br := public.reception_fournisseur_enregistrer(v_bc.id, null, pg_temp.dep('DEP-01'), current_date - 55, 'BL-ADC-8841', 'FA-ADC-5520', 'Livraison complète, profilés contrôlés.', v_lignes);

  -- 2. Vitrage — partiellement reçue
  v_bc := public.commande_fournisseur_enregistrer(null, jsonb_build_object('fournisseur_id', pg_temp.frn('F-DEMO-02'), 'depot_id', pg_temp.dep('DEP-01'),
    'date_commande', current_date - 26, 'date_livraison_prevue', current_date - 12, 'reference_fournisseur', 'BC-VIT-0412', 'conditions', 'Livraison franco atelier', 'frais', 15000, 'tva_pct', 18),
    jsonb_build_array(
      jsonb_build_object('composant_id', pg_temp.cid('VIT-001'),    'quantite', 60, 'prix_unitaire', 6300),
      jsonb_build_object('composant_id', pg_temp.cid('VIT-TRE-8'),  'quantite', 30, 'prix_unitaire', 23200),
      jsonb_build_object('composant_id', pg_temp.cid('VIT-TRE-10'), 'quantite', 12, 'prix_unitaire', 28100)));
  perform public.commande_fournisseur_action(v_bc.id, 'envoyer');
  select jsonb_agg(jsonb_build_object('commande_ligne_id', id, 'composant_id', composant_id,
         'quantite', case when composant_id = pg_temp.cid('VIT-TRE-8') then 18 else quantite end, 'prix_unitaire', prix_unitaire))
    into v_lignes from public.commandes_fournisseur_lignes where commande_id = v_bc.id;
  v_br := public.reception_fournisseur_enregistrer(v_bc.id, null, pg_temp.dep('DEP-01'), current_date - 14, 'BL-VIT-3310', 'FA-VIT-7781', 'Reliquat de verre trempé 8 mm attendu sous 10 jours.', v_lignes);

  -- 3. Quincaillerie — envoyée, en attente de livraison
  v_bc := public.commande_fournisseur_enregistrer(null, jsonb_build_object('fournisseur_id', pg_temp.frn('F-DEMO-03'), 'depot_id', pg_temp.dep('DEP-01'),
    'date_commande', current_date - 5, 'date_livraison_prevue', current_date + 4, 'reference_fournisseur', 'QPA-1187', 'tva_pct', 18),
    jsonb_build_array(
      jsonb_build_object('composant_id', pg_temp.cid('QUI-003'),    'quantite', 40, 'prix_unitaire', 7300),
      jsonb_build_object('composant_id', pg_temp.cid('QUI-SER-3P'), 'quantite', 20, 'prix_unitaire', 40000),
      jsonb_build_object('composant_id', pg_temp.cid('QUI-CRM-001'),'quantite', 50, 'prix_unitaire', 6100)));
  perform public.commande_fournisseur_action(v_bc.id, 'envoyer');

  -- 4. Inox — brouillon
  perform public.commande_fournisseur_enregistrer(null, jsonb_build_object('fournisseur_id', pg_temp.frn('F-DEMO-04'), 'depot_id', pg_temp.dep('DEP-02'),
    'date_commande', current_date, 'date_livraison_prevue', current_date + 7, 'notes', 'Pour le garde-corps de la clinique — à valider avant envoi.', 'tva_pct', 18),
    jsonb_build_array(
      jsonb_build_object('composant_id', pg_temp.cid('POT-GI-001'), 'quantite', 40, 'prix_unitaire', 21500),
      jsonb_build_object('composant_id', pg_temp.cid('MC-GI-001'),  'quantite', 30, 'prix_unitaire', 16000),
      jsonb_build_object('composant_id', pg_temp.cid('TUB-INX-20'), 'quantite', 60, 'prix_unitaire', 7400)));

  -- 5. Motorisation — annulée
  v_bc := public.commande_fournisseur_enregistrer(null, jsonb_build_object('fournisseur_id', pg_temp.frn('F-DEMO-06'), 'depot_id', pg_temp.dep('DEP-01'),
    'date_commande', current_date - 20, 'tva_pct', 18),
    jsonb_build_array(jsonb_build_object('composant_id', pg_temp.cid('MOT-POR-COU'), 'quantite', 2, 'prix_unitaire', 250000)));
  perform public.commande_fournisseur_action(v_bc.id, 'envoyer');
  perform public.commande_fournisseur_action(v_bc.id, 'annuler', 'Client du portail annulé — commande reportée.');

  -- ---------- Transferts entre dépôts + commandes internes ----------
  -- Transfert reçu : dépôt principal → atelier
  insert into public.transferts_stock (depot_source_id, depot_destination_id, motif, created_by) values (pg_temp.dep('DEP-01'), pg_temp.dep('DEP-02'), 'Approvisionnement de l''atelier', v_admin) returning * into v_t;
  insert into public.transferts_stock_lignes (transfert_id, composant_id, quantite_envoyee, ordre) values
    (v_t.id, pg_temp.cid('P-COU-OV'), 60, 1), (v_t.id, pg_temp.cid('P-COU-RH'), 50, 2), (v_t.id, pg_temp.cid('P-COU-RB'), 50, 3), (v_t.id, pg_temp.cid('VIT-001'), 30, 4), (v_t.id, pg_temp.cid('QUI-ROU-001'), 120, 5);
  perform public.transfert_expedier(v_t.id, 'Aïcha Sylla');
  perform public.transfert_receptionner(v_t.id, '[]'::jsonb, 'Reçu complet', 'Karim Ouattara');
  -- Transfert en transit : vers le chantier Riviera Palmeraie
  insert into public.transferts_stock (depot_source_id, depot_destination_id, motif, created_by) values (pg_temp.dep('DEP-01'), pg_temp.dep('DEP-03'), 'Matériel de pose — chantier Riviera Palmeraie', v_admin) returning * into v_t;
  insert into public.transferts_stock_lignes (transfert_id, composant_id, quantite_envoyee, ordre) values
    (v_t.id, pg_temp.cid('FIX-CHV-001'), 300, 1), (v_t.id, pg_temp.cid('CON-SIL-STR'), 6, 2), (v_t.id, pg_temp.cid('JNT-001'), 80, 3);
  perform public.transfert_expedier(v_t.id, 'Aïcha Sylla');
  -- Commande interne servie (atelier → principal) et une soumise en attente de décision
  v_ci := public.commande_interne_enregistrer(null, jsonb_build_object('depot_demandeur_id', pg_temp.dep('DEP-02'), 'depot_fournisseur_id', pg_temp.dep('DEP-01'),
    'date_besoin', current_date - 8, 'motif', 'Fabrication — fenêtres villa Kouassi'),
    jsonb_build_array(jsonb_build_object('composant_id', pg_temp.cid('P-STD-003'), 'quantite', 40), jsonb_build_object('composant_id', pg_temp.cid('QUI-CRM-001'), 'quantite', 12)), true);
  perform public.commande_interne_action(v_ci.id, 'valider');
  perform public.commande_interne_servir(v_ci.id, (select jsonb_agg(jsonb_build_object('ligne_id', id, 'quantite', quantite_demandee)) from public.commandes_internes_lignes where commande_id = v_ci.id), true);
  perform public.commande_interne_enregistrer(null, jsonb_build_object('depot_demandeur_id', pg_temp.dep('DEP-02'), 'depot_fournisseur_id', pg_temp.dep('DEP-01'),
    'date_besoin', current_date + 3, 'motif', 'Fabrication — baie coulissante hôtel'),
    jsonb_build_array(jsonb_build_object('composant_id', pg_temp.cid('P-MR-TRA'), 'quantite', 18), jsonb_build_object('composant_id', pg_temp.cid('VIT-GI-001'), 'quantite', 10)), true);

  -- ---------- Inventaire physique validé (écarts justifiés) ----------
  v_inv := public.inventaire_valider(pg_temp.dep('DEP-01'), current_date - 10, 'Aïcha Sylla', 'Fatou Diabaté', 'Inventaire tournant des profilés et du vitrage.',
    (select jsonb_agg(case when c.code = 'VIT-001' then jsonb_build_object('composant_id', c.id, 'quantite_comptee', sd.quantite - 2, 'motif', 'casse', 'justification', '2 m² cassés à la manutention')
                           when c.code = 'FIX-CHV-001' then jsonb_build_object('composant_id', c.id, 'quantite_comptee', sd.quantite - 40, 'motif', 'consommation_non_saisie')
                           when c.code = 'P-STD-004' then jsonb_build_object('composant_id', c.id, 'quantite_comptee', sd.quantite + 6, 'motif', 'erreur_comptage')
                           else jsonb_build_object('composant_id', c.id, 'quantite_comptee', sd.quantite) end)
       from public.composants c join public.stocks_depot sd on sd.composant_id = c.id and sd.depot_id = pg_temp.dep('DEP-01')
      where c.code in ('P-COU-OV','P-COU-RH','P-COU-RB','P-STD-003','P-STD-004','VIT-001','VIT-GI-001','FIX-CHV-001','QUI-CRM-001','JNT-001')));
end $$;

-- ---------- Historique daté : les mouvements créés à l'instant sont reportés aux bonnes dates ----------
update public.mouvements_stock set created_at = now() - interval '70 days' where reference = 'INIT-DEMO';
update public.mouvements_stock m set created_at = (r.date_reception::timestamptz + interval '10 hours')
  from public.receptions_fournisseur r where m.reference = r.code;
update public.commandes_fournisseur set created_at = date_commande::timestamptz + interval '9 hours' where date_commande is not null;
update public.receptions_fournisseur set created_at = date_reception::timestamptz + interval '10 hours';
update public.transferts_stock set created_at = now() - interval '12 days', date_expedition = now() - interval '12 days', date_reception = case when statut = 'recu' then now() - interval '11 days' end where statut = 'recu';
update public.transferts_stock set created_at = now() - interval '1 day', date_expedition = now() - interval '1 day' where statut = 'en_transit';
update public.mouvements_stock m set created_at = now() - interval '12 days' from public.transferts_stock t where m.transfert_id = t.id and t.statut = 'recu';
update public.mouvements_stock m set created_at = now() - interval '1 day' from public.transferts_stock t where m.transfert_id = t.id and t.statut = 'en_transit';
update public.mouvements_stock set created_at = now() - interval '10 days' where type = 'inventaire' or motif ilike 'Inventaire%';
