-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (4/6) : caisse, comptoir, ticket Z
-- (à lancer après 03_commercial.sql)
-- ============================================================================
do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  v_caisse uuid; v_pdv uuid; v_depot uuid;
  v_sess uuid; v_fond numeric;
  v_vente public.ventes_comptoir; v_n int := 0; d int; k int; v_cmp public.composants; v_q numeric; v_tot numeric; v_sous numeric;
  v_modes text[] := array['espece','espece','mobile_money','espece','banque','espece','mobile_money','cheque'];
  v_clients text[] := array['Client de passage','Atelier Konan Métal','Menuiserie Diaby','Ets Traoré & Fils','Client de passage','Quincaillerie Koffi','Client de passage','Soro Soudure'];
  v_codes text[][] := array[
    array['QUI-GAL-001','QUI-ROU-001','FIX-CHV-001'], array['JNT-001','CON-001','FIX-RIV-001'], array['TUB-ALU-25','QUI-CYL-001','JNT-FRP-001'],
    array['VIT-001','JNT-EQ-001','CON-SIL-STR'], array['P-STD-001','QUI-CRM-001','QUI-GAL-001'], array['PIN-GI-001','TEN-GI-001','PLA-GI-001'],
    array['MOT-TUB-001','QUI-SER-3P','FIX-RIV-001'], array['TUL-MO-001','TOI-MOU-ENR','JNT-ONG-001']];
begin
  select id into v_caisse from public.caisses order by created_at limit 1;
  select id, depot_id into v_pdv, v_depot from public.points_vente order by created_at limit 1;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('app.caisse_validation', '1', true);

  -- Prix de vente comptoir (marge ~ 25 %) pour les articles stockés au dépôt principal
  update public.composants c set prix_vente = round(coalesce(nullif(c.prix_unitaire, 0), 1) * 1.25, -1)
    where prix_vente is null and exists (select 1 from public.stocks_depot s where s.composant_id = c.id and s.depot_id = v_depot and s.quantite > 0);
  update public.composants set prix_vente = 5.5 where code = 'CAB-GI-001';

  -- Règles de ventilation automatique des sorties de caisse
  insert into public.caisse_regles_ventilation (mot_cle, compte_code) values
    ('transport', '611'), ('carburant', '6054'), ('gasoil', '6054'), ('électricité', '6052'), ('eau', '6051'),
    ('bureau', '6047'), ('petit matériel', '6056'), ('internet', '628'), ('téléphone', '628'), ('entretien', '6054')
  on conflict do nothing;

  -- Sessions de caisse clôturées (7 derniers jours ouvrés) + session du jour ouverte
  for d in reverse 8..1 loop
    v_fond := 50000;
    insert into public.caisse_sessions (caisse_id, date_session, fond_ouverture, statut, ouverte_par, ouverte_le, ouverte_par_id)
      values (v_caisse, current_date - d, v_fond, 'ouverte', 'caisse@aluexpert.ci', (current_date - d)::timestamptz + interval '8 hours', '00000000-0000-4000-8000-000000000003')
      returning id into v_sess;

    -- 2 à 4 ventes comptoir par jour
    for k in 1..(2 + d % 3) loop
      v_n := v_n + 1;
      v_sous := 0;
      declare
        v_lignes jsonb := '[]'::jsonb; c text; v_pu numeric; v_lt numeric; v_idx int := 1 + (v_n % 8);
      begin
        foreach c in array v_codes[v_idx:v_idx][1:3] loop
          select * into v_cmp from public.composants where code = c;
          v_q := case v_cmp.unite when 'ml' then 3 when 'm2' then 1 when 'cartouche' then 2 else case when c in ('MOT-TUB-001','QUI-SER-3P') then 1 else 4 end end;
          v_pu := v_cmp.prix_vente; v_lt := v_pu * v_q; v_sous := v_sous + v_lt;
          v_lignes := v_lignes || jsonb_build_object('composant_id', v_cmp.id, 'designation', v_cmp.nom, 'unite', v_cmp.unite, 'quantite', v_q,
                       'prix_unitaire', v_pu, 'prix_achat', coalesce(v_cmp.cmup, 0), 'remise_pct', 0, 'total', v_lt);
        end loop;
        v_tot := round(v_sous, -1);
        v_vente := public.vente_comptoir_valider(jsonb_build_object(
          'date_vente', current_date - d, 'client_nom', v_clients[v_idx], 'sous_total', v_sous, 'remise', 0, 'total', v_tot,
          'mode_paiement', v_modes[v_idx], 'montant_recu', ceil(v_tot / 1000) * 1000, 'monnaie_rendue', ceil(v_tot / 1000) * 1000 - v_tot,
          'caisse_id', v_caisse, 'point_vente_id', v_pdv, 'depot_id', v_depot, 'vendeur', 'Caissier Démo'), v_lignes);
        if v_modes[v_idx] = 'espece' then
          insert into public.caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, piece_ref, statut, created_by)
            values (v_sess, v_caisse, v_vente.code, current_date - d, 'entree', v_tot, 'Vente au comptoir ' || v_vente.code, v_clients[v_idx], v_vente.code, 'ventile', '00000000-0000-4000-8000-000000000003');
        end if;
      end;
    end loop;

    -- Dépenses courantes de caisse
    insert into public.caisse_mouvements (session_id, caisse_id, numero, date_mouvement, type, montant, motif, beneficiaire, statut, compte_ventile, created_by) values
      (v_sess, v_caisse, 'CM-' || to_char(current_date - d, 'YYMMDD') || '-1', current_date - d, 'sortie', 5000 + d * 500, 'Transport livraison chantier', 'Taxi Kouassi', 'ventile', '611', '00000000-0000-4000-8000-000000000003'),
      (v_sess, v_caisse, 'CM-' || to_char(current_date - d, 'YYMMDD') || '-2', current_date - d, 'sortie', 3000, 'Carburant groupe électrogène atelier', 'Station Total', 'ventile', '6054', '00000000-0000-4000-8000-000000000003');

    update public.caisse_sessions s set
      fond_cloture_theorique = v_fond + coalesce((select sum(case type when 'entree' then montant else -montant end) from public.caisse_mouvements where session_id = s.id), 0),
      statut = 'cloturee', cloturee_par = 'caisse@aluexpert.ci', cloturee_le = (current_date - d)::timestamptz + interval '18 hours', cloturee_par_id = '00000000-0000-4000-8000-000000000003'
      where s.id = v_sess;
    update public.caisse_sessions set
      fond_cloture_reel = fond_cloture_theorique - case when d = 3 then 500 else 0 end,
      ecart = case when d = 3 then -500 else 0 end where id = v_sess;
  end loop;

  -- Session du jour (ouverte)
  insert into public.caisse_sessions (caisse_id, date_session, fond_ouverture, statut, ouverte_par, ouverte_le, ouverte_par_id)
    values (v_caisse, current_date, 50000, 'ouverte', 'caisse@aluexpert.ci', now() - interval '3 hours', '00000000-0000-4000-8000-000000000003') returning id into v_sess;

  -- Demandes de décaissement : en attente, validée, rejetée
  insert into public.caisse_demandes (numero, caisse_id, session_id, type, montant, date_mouvement, motif, beneficiaire, statut, demande_par, demande_nom, demande_le, decide_par, decide_nom, decide_le, motif_rejet) values
    ('DC-DEMO-001', v_caisse, v_sess, 'sortie', 180000, current_date, 'Achat petit matériel (visseuse + forets)', 'Quincaillerie Centrale', 'en_attente', '00000000-0000-4000-8000-000000000003', 'Caissier Démo', now() - interval '2 hours', null, null, null, null),
    ('DC-DEMO-002', v_caisse, v_sess, 'sortie', 45000, current_date - 2, 'Avance sur salaire — poseur', 'Poseur Yao', 'validee', '00000000-0000-4000-8000-000000000003', 'Caissier Démo', now() - interval '2 days', v_admin, 'Directeur Démo', now() - interval '2 days' + interval '1 hour', null),
    ('DC-DEMO-003', v_caisse, v_sess, 'sortie', 600000, current_date - 4, 'Achat de panneaux hors budget', 'Fournisseur divers', 'rejetee', '00000000-0000-4000-8000-000000000003', 'Caissier Démo', now() - interval '4 days', v_admin, 'Directeur Démo', now() - interval '4 days' + interval '2 hours', 'Passer par un bon de commande fournisseur');

  -- Ticket Z journalier pour la veille + une vente annulée ne figure pas (cohérence)
  perform public.ticket_z_emettre(v_pdv, 'journalier', current_date - 1, current_date - 1, '{}'::jsonb);
  perform public.ticket_z_emettre(v_pdv, 'periodique', current_date - 8, current_date - 1, '{}'::jsonb);
end $$;
