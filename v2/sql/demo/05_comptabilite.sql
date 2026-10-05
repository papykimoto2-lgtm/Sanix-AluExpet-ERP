-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (5/6) : comptabilité (écritures automatiques + manuelles)
-- (à lancer après 04_caisse_comptoir.sql) — reproduit ce que fait l'application côté client.
-- ============================================================================
do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  v_tva numeric; r record; v_id uuid; v_ht numeric; v_t numeric; v_cpt text; v_jr text; v_caisse_cpt text;
begin
  select coalesce(tva_pct, 18) into v_tva from public.parametres limit 1;
  select coalesce(compte_code, '571') into v_caisse_cpt from public.caisses limit 1;

  create temp table tmp_ecr (id uuid default gen_random_uuid(), ref text, d date, jr text, piece text, lib text, st text, sid uuid, src text, valide boolean, projet uuid, n serial) on commit drop;
  create temp table tmp_lig (ecr uuid, cpt text, sens text, m numeric, lib text, tt text, tid uuid) on commit drop;

  -- 1) Factures clients : D 4111 / C 702 + 4431
  for r in select f.*, c.nom cnom, d.projet_id from public.factures f join public.clients c on c.id = f.client_id left join public.devis d on d.id = f.devis_id where f.statut <> 'annulee' and f.total > 0 loop
    v_id := gen_random_uuid(); v_ht := round(r.total / (1 + v_tva / 100)); v_t := r.total - v_ht;
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide, projet) values (v_id, r.date_facture, 'VE', r.code, 'Vente — ' || r.code || ' — ' || r.cnom, 'facture', r.id, 'auto', true, r.projet_id);
    insert into tmp_lig values (v_id, '4111', 'D', r.total, 'Facture ' || r.code, 'client', r.client_id), (v_id, '702', 'C', v_ht, 'Facture ' || r.code, null, null);
    if v_t > 0 then insert into tmp_lig values (v_id, '4431', 'C', v_t, 'TVA sur facture ' || r.code, null, null); end if;
  end loop;

  -- 2) Encaissements : D trésorerie / C 4111
  for r in select p.*, f.code fcode, f.client_id from public.paiements p join public.factures f on f.id = p.facture_id loop
    v_id := gen_random_uuid();
    v_cpt := case r.mode when 'espece' then v_caisse_cpt when 'mobile_money' then '552' else '521' end;
    v_jr := case r.mode when 'espece' then 'CA' when 'mobile_money' then 'MM' else 'BQ' end;
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide) values (v_id, r.date_paiement, v_jr, coalesce(r.reference, r.fcode), 'Encaissement facture ' || r.fcode, 'paiement', r.id, 'auto', true);
    insert into tmp_lig values (v_id, v_cpt, 'D', r.montant, 'Encaissement ' || r.fcode, null, null), (v_id, '4111', 'C', r.montant, 'Encaissement ' || r.fcode, 'client', r.client_id);
  end loop;

  -- 3) Ventes au comptoir : D trésorerie / C 701 + 4431
  for r in select * from public.ventes_comptoir where statut = 'validee' and total > 0 loop
    v_id := gen_random_uuid(); v_ht := round(r.total / (1 + v_tva / 100)); v_t := r.total - v_ht;
    v_cpt := case r.mode_paiement when 'espece' then v_caisse_cpt when 'mobile_money' then '552' else '521' end;
    v_jr := case r.mode_paiement when 'espece' then 'CA' when 'mobile_money' then 'MM' else 'BQ' end;
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide) values (v_id, r.date_vente, v_jr, r.code, 'Vente au comptoir ' || r.code || ' — ' || coalesce(r.client_nom, ''), 'vente_comptoir', r.id, 'auto', true);
    insert into tmp_lig values (v_id, v_cpt, 'D', r.total, 'Vente au comptoir ' || r.code, null, null), (v_id, '701', 'C', v_ht, 'Vente au comptoir ' || r.code, null, null);
    if v_t > 0 then insert into tmp_lig values (v_id, '4431', 'C', v_t, 'TVA — ' || r.code, null, null); end if;
  end loop;

  -- 4) Réceptions fournisseurs : D 601 / C 4011
  for r in select b.*, f.nom fnom from public.receptions_fournisseur b join public.fournisseurs f on f.id = b.fournisseur_id where b.montant_ht > 0 loop
    v_id := gen_random_uuid();
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide, projet) values (v_id, r.date_reception, 'AC', coalesce(r.facture_fournisseur, r.code), 'Achat — ' || r.fnom || ' — ' || r.code, 'reception_fournisseur', r.id, 'auto', true, r.projet_id);
    insert into tmp_lig values (v_id, '601', 'D', r.montant_ht, 'Achat — ' || r.code, null, null), (v_id, '4011', 'C', r.montant_ht, 'Achat — ' || r.code, 'fournisseur', r.fournisseur_id);
  end loop;

  -- 5) Dépenses de caisse ventilées : D compte / C 571
  for r in select * from public.caisse_mouvements where type = 'sortie' and statut = 'ventile' and compte_ventile is not null loop
    v_id := gen_random_uuid();
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide) values (v_id, r.date_mouvement, 'CA', r.numero, r.motif, 'caisse_mouvement', r.id, 'auto', true);
    insert into tmp_lig values (v_id, r.compte_ventile, 'D', r.montant, r.motif, null, null), (v_id, v_caisse_cpt, 'C', r.montant, r.motif, null, null);
  end loop;

  -- 6) Écarts de caisse à la clôture : D 658 / C 571 (manquant)
  for r in select * from public.caisse_sessions where statut = 'cloturee' and coalesce(ecart, 0) < 0 loop
    v_id := gen_random_uuid();
    insert into tmp_ecr (id, d, jr, piece, lib, st, sid, src, valide) values (v_id, r.date_session, 'CA', null, 'Écart de clôture — Caisse principale', 'caisse_session', r.id, 'auto', true);
    insert into tmp_lig values (v_id, '658', 'D', -r.ecart, 'Manquant de caisse', null, null), (v_id, v_caisse_cpt, 'C', -r.ecart, 'Manquant de caisse', null, null);
  end loop;

  -- 7) Écritures manuelles (validées) et brouillards en attente de visa
  v_id := gen_random_uuid(); insert into tmp_ecr (id, d, jr, piece, lib, src, valide) values (v_id, date '2026-07-31', 'OD', 'LOY-0726', 'Loyer atelier — juillet 2026', 'manuel', true);
    insert into tmp_lig values (v_id, '622', 'D', 450000, 'Loyer atelier juillet', null, null), (v_id, '521', 'C', 450000, 'Loyer atelier juillet', null, null);
  v_id := gen_random_uuid(); insert into tmp_ecr (id, d, jr, piece, lib, src, valide) values (v_id, date '2026-08-31', 'OD', 'LOY-0826', 'Loyer atelier — août 2026', 'manuel', true);
    insert into tmp_lig values (v_id, '622', 'D', 450000, 'Loyer atelier août', null, null), (v_id, '521', 'C', 450000, 'Loyer atelier août', null, null);
  v_id := gen_random_uuid(); insert into tmp_ecr (id, d, jr, piece, lib, src, valide) values (v_id, date '2026-08-31', 'OD', 'SAL-0826', 'Salaires du personnel — août 2026', 'manuel', true);
    insert into tmp_lig values (v_id, '661', 'D', 1850000, 'Salaires août', null, null), (v_id, '521', 'C', 1850000, 'Salaires août', null, null);
  v_id := gen_random_uuid(); insert into tmp_ecr (id, d, jr, piece, lib, src, valide) values (v_id, date '2026-09-30', 'BQ', 'REL-0926', 'Frais bancaires — septembre 2026', 'manuel', false);
    insert into tmp_lig values (v_id, '631', 'D', 18500, 'Frais de tenue de compte', null, null), (v_id, '521', 'C', 18500, 'Frais de tenue de compte', null, null);
  v_id := gen_random_uuid(); insert into tmp_ecr (id, d, jr, piece, lib, src, valide) values (v_id, date '2026-09-30', 'OD', 'SAL-0926', 'Salaires du personnel — septembre 2026 (à viser)', 'manuel', false);
    insert into tmp_lig values (v_id, '661', 'D', 1850000, 'Salaires septembre', null, null), (v_id, '521', 'C', 1850000, 'Salaires septembre', null, null);

  -- Numérotation JL-AAAA-NNNNN dans l'ordre chronologique, puis insertion
  update tmp_ecr t set ref = 'JL-2026-' || lpad(x.rn::text, 5, '0') from (select id, row_number() over (order by d, n) rn from tmp_ecr) x where x.id = t.id;
  insert into public.compta_ecritures (id, ref, exercice_annee, date_ecriture, journal_code, piece, libelle, projet_id, source, source_type, source_id, valide_le, valide_par, created_by, created_at)
    select id, ref, 2026, d, jr, piece, lib, projet, src, st, sid, case when valide then d::timestamptz + interval '20 hours' end, case when valide then case when src = 'auto' then 'Automatique' else 'Comptable Démo' end end, v_admin, d::timestamptz + interval '10 hours' from tmp_ecr;
  insert into public.compta_lignes (ecriture_id, compte_code, libelle, sens, montant, tiers_type, tiers_id)
    select ecr, cpt, lib, sens, m, tt, tid from tmp_lig where m > 0;

  -- Liaisons source → écriture
  update public.paiements p set ecriture_id = e.id from public.compta_ecritures e where e.source_type = 'paiement' and e.source_id = p.id;
  update public.ventes_comptoir v set ecriture_id = e.id from public.compta_ecritures e where e.source_type = 'vente_comptoir' and e.source_id = v.id;
  update public.caisse_mouvements m set ecriture_id = e.id from public.compta_ecritures e where e.source_type = 'caisse_mouvement' and e.source_id = m.id;
  update public.caisse_sessions s set ecart_ecriture_id = e.id from public.compta_ecritures e where e.source_type = 'caisse_session' and e.source_id = s.id;
  update public.receptions_fournisseur b set comptabilise = true where exists (select 1 from public.compta_ecritures e where e.source_type = 'reception_fournisseur' and e.source_id = b.id);
end $$;
