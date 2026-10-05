-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (1/6) : base, utilisateurs, tiers, catalogue
-- ============================================================================
-- À exécuter UNIQUEMENT sur un projet de démonstration, juste après sql/00_installation_complete.sql.
-- Données 100 % fictives (entreprise « Atelier Alu Démo », clients, prix indicatifs). Les parties 02 à 06 se lancent
-- ensuite dans l'ordre. Pour tout effacer ensuite : select public.vider_donnees('tout');
-- ============================================================================
do $$ begin
  if exists (select 1 from public.clients) or exists (select 1 from public.projets) then
    raise exception 'La base contient déjà des données : la démonstration ne s''installe que sur une base vide.';
  end if;
end $$;

-- ---------- Comptes de démonstration (mot de passe commun : Demo@2026) ----------
do $$
declare
  v_pwd text := extensions.crypt('Demo@2026', extensions.gen_salt('bf'));
  u record;
begin
  for u in select * from (values
    ('00000000-0000-4000-8000-000000000001'::uuid, 'demo@aluexpert.ci',       'demo',       'Directeur Démo',        'admin',       '+225 07 00 00 00 01'),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'commercial@aluexpert.ci', 'commercial', 'Moussa Koné',          'commercial',  '+225 07 00 00 00 02'),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'caisse@aluexpert.ci',     'caisse',     'Aïcha Sylla',          'caissiere',   '+225 07 00 00 00 03'),
    ('00000000-0000-4000-8000-000000000004'::uuid, 'compta@aluexpert.ci',     'compta',     'Ibrahim Touré',        'comptable',   '+225 07 00 00 00 04'),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'manager@aluexpert.ci',    'manager',    'Fatou Diabaté',        'manager',     '+225 07 00 00 00 05')
  ) t(id, email, login, nom, role_code, tel)
  loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email, v_pwd, now(),
        '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nom_complet', u.nom), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (u.id::text, u.id, jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true), 'email', now(), now(), now());
    -- le déclencheur handle_new_user a créé le profil : on le complète
    insert into public.profiles (id) values (u.id) on conflict (id) do nothing;
    update public.profiles set nom_complet = u.nom, role_id = (select id from public.roles where code = u.role_code), role = u.role_code,
        actif = true, must_change = false, login = u.login, email = u.email, telephone = u.tel where id = u.id;
  end loop;
end $$;

-- ---------- Paramètres de l'entreprise de démonstration ----------
update public.parametres set
  raison_sociale = 'ATELIER ALU DÉMO SARL',
  rccm = 'CI-ABJ-2024-B-00000', ncc = '0000000 A', regime_fiscal = 'Réel simplifié d''imposition', tva_pct = 18,
  adresse = 'Zone industrielle de Yopougon, Abidjan — Côte d''Ivoire', email = 'contact@aluexpert-demo.ci',
  telephone = '+225 07 00 00 00 00', whatsapp = '+225 07 00 00 00 00', site_web = 'www.aluexpert-demo.ci',
  portail_actif = true, portail_nom = 'Atelier Alu Démo', portail_slogan = 'Menuiserie aluminium, vitrerie & inox sur mesure',
  portail_couleur = '#6d28d9', site_a_propos = 'Atelier de fabrication et de pose de menuiseries aluminium, verrières, garde-corps inox et vitrerie à Abidjan. Devis gratuit, suivi de chantier et garantie sur la pose.',
  site_facebook = 'https://facebook.com/', site_instagram = 'https://instagram.com/',
  portail_dg_nom = 'Directeur Démo', portail_dg_titre = 'Directeur Général', portail_dg_message = 'Notre priorité : des ouvrages durables, livrés dans les délais convenus.',
  conditions_documents = E'Conditions de règlement :\nAcompte de 50 % à la commande, solde à la livraison avant la pose.\nValidité du devis : 30 jours.\nGarantie :\nQuincaillerie et étanchéité garanties 1 an, profilés et laquage 5 ans.\nLes dimensions définitives sont confirmées après la prise de mesures sur chantier.',
  fne_actif = false, fne_environnement = 'test', validation_caisse_mode = 'plafond';

-- ---------- Référentiels ----------
insert into public.client_categories (nom) values ('Particulier'), ('Entreprise'), ('Promoteur immobilier'), ('Administration');
insert into public.devis_categories (nom) values ('Villa / résidentiel'), ('Commercial & bureaux'), ('Santé & éducation'), ('Hôtellerie');

-- ---------- Dépôts et affectations ----------
insert into public.depots (code, nom, type, adresse, commune, responsable, telephone, est_principal) values
  ('DEP-02', 'Atelier de fabrication', 'atelier', 'Zone industrielle de Yopougon', 'Yopougon', 'Karim Ouattara', '+225 07 00 00 10 02', false),
  ('DEP-03', 'Chantier Riviera Palmeraie', 'chantier', 'Riviera Palmeraie, lot 214', 'Cocody', 'Moussa Koné', '+225 07 00 00 10 03', false);
update public.depots set responsable = 'Aïcha Sylla', adresse = 'Zone industrielle de Yopougon', commune = 'Yopougon' where code = 'DEP-01';
update public.points_vente set nom = 'Comptoir principal', responsable = 'Aïcha Sylla', adresse = 'Zone industrielle de Yopougon' where code = 'PDV-01';
update public.caisses set responsable = 'Aïcha Sylla';
insert into public.point_vente_affectations (point_vente_id, user_id, par_defaut)
  select (select id from public.points_vente where code = 'PDV-01'), u, true
  from unnest(array['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000005']::uuid[]) u;
insert into public.caisse_affectations (caisse_id, user_id)
  select (select id from public.caisses limit 1), u
  from unnest(array['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000005']::uuid[]) u;

-- ---------- Clients ----------
insert into public.clients (code, civilite, nom, prenoms, entreprise, telephone, email, commune, quartier, categorie, adresse, source, commercial, created_at, latitude, longitude, ncc, rccm) values
 ('C-DEMO-01','Monsieur','KOUASSI','Jean-Marc',null,'+225 07 08 11 22 33','jm.kouassi@exemple.ci','Cocody','Riviera Palmeraie','Particulier','Villa lot 214, Riviera Palmeraie','Recommandation','Moussa Koné', now()-interval '120 days',5.3589,-3.9631,null,null),
 ('C-DEMO-02','Madame','TRAORÉ','Awa',null,'+225 05 44 55 66 77','awa.traore@exemple.ci','Marcory','Zone 4','Particulier','Résidence Les Cocotiers, Zone 4','Facebook','Moussa Koné', now()-interval '95 days',5.3008,-3.9838,null,null),
 ('C-DEMO-03','Monsieur','SCI LES PALMIERS',null,'SCI Les Palmiers','+225 27 22 40 10 20','contact@scipalmiers.ci','Cocody','Angré 8e tranche','Promoteur immobilier','Programme de 24 appartements, Angré 8e tranche','Appel d''offres','Fatou Diabaté', now()-interval '80 days',5.3925,-3.9876,'1234567 B','CI-ABJ-2019-B-12345'),
 ('C-DEMO-04','Monsieur','HÔTEL LE BAOBAB SARL',null,'Hôtel Le Baobab','+225 27 20 21 22 23','direction@lebaobab.ci','Plateau','Boulevard de la République','Hôtellerie'::text,'Boulevard de la République, Plateau','Salon professionnel','Fatou Diabaté', now()-interval '70 days',5.3197,-4.0166,'2345678 C','CI-ABJ-2015-B-23456'),
 ('C-DEMO-05','Madame','PHARMACIE SAINTE MARIE',null,'Pharmacie Sainte Marie','+225 07 77 88 99 00','pharmaciestemarie@exemple.ci','Yopougon','Selmer','Entreprise','Carrefour Selmer, Yopougon','Passage devant l''atelier','Moussa Koné', now()-interval '60 days',5.3412,-4.0810,null,null),
 ('C-DEMO-06','Monsieur','ETS KONATÉ & FILS',null,'Ets Konaté & Fils','+225 21 24 35 46 57','konate.fils@exemple.ci','Treichville','Zone 3','Entreprise','Rue des Brasseurs, Zone 3','Recommandation','Moussa Koné', now()-interval '55 days',5.2927,-4.0035,null,null),
 ('C-DEMO-07','Monsieur','RÉSIDENCE LES ORCHIDÉES',null,'Résidence Les Orchidées','+225 27 22 49 00 11','gestion@orchidees.ci','Bingerville','Cité des cadres','Promoteur immobilier','Lotissement Les Orchidées, Bingerville','Site web','Fatou Diabaté', now()-interval '48 days',5.3562,-3.8869,null,null),
 ('C-DEMO-08','Docteur','CLINIQUE LA PROVIDENCE',null,'Clinique La Providence','+225 27 22 44 55 66','admin@cliniqueprovidence.ci','Cocody','Danga','Entreprise','Danga, près du carrefour Saint-Jean','Appel d''offres','Fatou Diabaté', now()-interval '40 days',5.3501,-3.9980,'3456789 D','CI-ABJ-2012-B-34567'),
 ('C-DEMO-09','Monsieur','YAO','Koffi',null,'+225 01 02 03 04 05','yao.koffi@exemple.ci','Koumassi','Remblais','Particulier','Koumassi Remblais, rue 12','Facebook','Moussa Koné', now()-interval '34 days',5.2931,-3.9512,null,null),
 ('C-DEMO-10','Madame','GROUPE SCOLAIRE EXCELLENCE',null,'Groupe Scolaire Excellence','+225 27 21 10 20 30','direction@excellence-school.ci','Abobo','Avocatier','Santé & éducation'::text,'Abobo Avocatier, route d''Anyama','Recommandation','Fatou Diabaté', now()-interval '28 days',5.4181,-4.0212,null,null),
 ('C-DEMO-11','Madame','DIALLO','Fatou',null,'+225 07 55 44 33 22','fatou.diallo@exemple.ci','Cocody','Deux-Plateaux','Particulier','Deux-Plateaux Vallons, villa 18','Recommandation','Moussa Koné', now()-interval '21 days',5.3702,-4.0007,null,null),
 ('C-DEMO-12','Monsieur','DIRECTION RÉGIONALE DE L''HABITAT',null,'DR Habitat Abidjan','+225 27 20 30 40 50','dr.habitat@exemple.gouv.ci','Plateau','Cité administrative','Administration','Cité administrative, tour D','Appel d''offres','Fatou Diabaté', now()-interval '16 days',5.3235,-4.0186,null,null),
 ('C-DEMO-13','Monsieur','BOULANGERIE LA MIE DORÉE',null,'Boulangerie La Mie Dorée','+225 05 11 22 33 44','miedoree@exemple.ci','Port-Bouët','Gonzagueville','Entreprise','Gonzagueville, route de Bassam','Passage devant l''atelier','Moussa Koné', now()-interval '9 days',5.2513,-3.9309,null,null),
 ('C-DEMO-14','Monsieur','BAMBA','Seydou',null,'+225 07 66 77 88 99','seydou.bamba@exemple.ci','Yopougon','Niangon','Particulier','Niangon Nord, rue des écoles','Facebook','Moussa Koné', now()-interval '4 days',5.3300,-4.1000,null,null);
update public.clients set categorie = case categorie when 'Hôtellerie' then 'Entreprise' when 'Santé & éducation' then 'Entreprise' else categorie end;

-- ---------- Prospects (entonnoir commercial) ----------
insert into public.prospects (code, civilite, nom, prenoms, entreprise, telephone, email, commune, statut, source, commercial, notes, created_at, latitude, longitude) values
 ('P-DEMO-01','Monsieur','OUATTARA','Drissa',null,'+225 07 12 34 56 78',null,'Cocody','nouveau','Facebook','Moussa Koné','Souhaite 6 fenêtres coulissantes pour une villa en construction.', now()-interval '2 days',5.3470,-3.9800),
 ('P-DEMO-02','Madame','N''GUESSAN','Marie-Claire',null,'+225 05 98 76 54 32','mc.nguessan@exemple.ci','Marcory','nouveau','Recommandation','Moussa Koné','Demande de prix pour une porte d''entrée vitrée.', now()-interval '3 days',5.3000,-3.9800),
 ('P-DEMO-03','Monsieur','SOCIÉTÉ IMMO SOLEIL',null,'Immo Soleil','+225 27 22 33 44 55','contact@immosoleil.ci','Cocody','contacte','Appel d''offres','Fatou Diabaté','Programme de 12 villas — rendez-vous prévu pour visiter un chantier de référence.', now()-interval '10 days',5.3880,-3.9700),
 ('P-DEMO-04','Madame','CABINET MÉDICAL SANTÉ PLUS',null,'Santé Plus','+225 27 21 55 66 77','sante.plus@exemple.ci','Plateau','contacte','Salon professionnel','Fatou Diabaté','Cloisons vitrées et portes de cabinets.', now()-interval '12 days',5.3200,-4.0100),
 ('P-DEMO-05','Monsieur','TANOH','Eugène',null,'+225 01 44 33 22 11',null,'Bingerville','qualifie','Recommandation','Moussa Koné','Garde-corps inox pour terrasse + escalier — budget validé.', now()-interval '15 days',5.3570,-3.8900),
 ('P-DEMO-06','Monsieur','RESTAURANT LE MAQUIS DU PORT',null,'Maquis du Port','+225 05 22 33 44 55',null,'Treichville','qualifie','Passage devant l''atelier','Moussa Koné','Façade vitrée et porte pliante pour la terrasse.', now()-interval '18 days',5.2890,-4.0050),
 ('P-DEMO-07','Madame','KONÉ','Mariam',null,'+225 07 99 88 77 66',null,'Yopougon','gagne','Facebook','Moussa Koné','Devis accepté — convertie en client.', now()-interval '30 days',5.3400,-4.0700),
 ('P-DEMO-08','Monsieur','LAGOUDJÉ','Armand',null,'+225 05 33 22 11 00',null,'Abobo','perdu','Site web','Fatou Diabaté','Prix jugé trop élevé — a choisi un concurrent.', now()-interval '45 days',5.4100,-4.0200);

-- ---------- Fournisseurs ----------
insert into public.fournisseurs (code, nom, contact_principal, telephone, email, commune, quartier, categorie, adresse, ncc, rccm) values
 ('F-DEMO-01','ALU DISTRIBUTION CI','M. Bakayoko','+225 27 21 35 10 10','ventes@aludistribution.ci','Marcory','Zone 4C','Profilés aluminium','Rue Pierre et Marie Curie, Zone 4C','4567890 E','CI-ABJ-2010-B-45678'),
 ('F-DEMO-02','VITRAL IVOIRE','Mme Coulibaly','+225 27 21 36 20 20','commercial@vitral.ci','Koumassi','Zone industrielle','Vitrage & miroiterie','Zone industrielle de Koumassi','5678901 F','CI-ABJ-2008-B-56789'),
 ('F-DEMO-03','QUINCA PRO AFRIQUE','M. Sangaré','+225 27 21 24 30 30','info@quincapro.ci','Treichville','Zone 3','Quincaillerie','Boulevard de Marseille, Zone 3','6789012 G','CI-ABJ-2013-B-67890'),
 ('F-DEMO-04','INOX SERVICE','M. Doumbia','+225 27 21 28 40 40','inox@inoxservice.ci','Yopougon','Zone industrielle','Inox & tubes','Zone industrielle de Yopougon','7890123 H','CI-ABJ-2016-B-78901'),
 ('F-DEMO-05','COLLES & JOINTS CI','Mme Ahoua','+225 27 21 35 50 50','contact@collesjoints.ci','Marcory','Biétry','Consommables & joints','Rue du Canal, Biétry','8901234 J','CI-ABJ-2011-B-89012'),
 ('F-DEMO-06','MOTORIS AFRICA','M. Kamara','+225 27 22 49 60 60','sav@motoris.ci','Cocody','Riviera 3','Motorisation & automatismes','Riviera 3, boulevard Mitterrand','9012345 K','CI-ABJ-2018-B-90123');

-- ---------- Catalogue de produits finis (prix de vente indicatifs en FCFA) ----------
insert into public.produits (nom, unite, prix_vente, cout_materiel, cout_materiel_pct, famille, alu_ml, glass_m2, vente_comptoir) values
 ('Fenêtre coulissante 2 vantaux — alu blanc, vitrage 6 mm', 'm2', 95000, 52000, 55, 'Fenêtres & châssis', 5.2, 0.9, false),
 ('Fenêtre à la française 1 vantail', 'm2', 105000, 58000, 55, 'Fenêtres & châssis', 5.8, 0.85, false),
 ('Baie coulissante 3 vantaux — vitrage sécurit', 'm2', 125000, 70000, 56, 'Coulissants, baies & pliants', 6.2, 0.9, false),
 ('Porte coulissante 2 vantaux', 'm2', 120000, 66000, 55, 'Coulissants, baies & pliants', 6.0, 0.9, false),
 ('Porte d''entrée aluminium vitrée', 'unite', 250000, 138000, 55, 'Portes', 9.0, 1.4, false),
 ('Porte intérieure alu pleine', 'unite', 140000, 77000, 55, 'Portes', 7.5, 0, false),
 ('Façade vitrée / vitrine commerciale', 'm2', 135000, 76000, 56, 'Façades, vitrines, cloisons & verrières', 4.8, 0.95, false),
 ('Cloison vitrée de bureau', 'm2', 98000, 54000, 55, 'Façades, vitrines, cloisons & verrières', 4.2, 0.92, false),
 ('Verrière d''atelier — profil fin', 'm2', 160000, 92000, 57, 'Façades, vitrines, cloisons & verrières', 6.5, 0.9, false),
 ('Volet roulant aluminium motorisé', 'm2', 88000, 50000, 57, 'Fermetures, volets & protections solaires', 3.5, 0, false),
 ('Garde-corps inox 304 — câbles', 'ml', 68000, 38000, 56, 'Garde-corps, rampes & mains courantes', 0, 0, false),
 ('Garde-corps verre et inox', 'ml', 92000, 52000, 56, 'Garde-corps, rampes & mains courantes', 0, 0.9, false),
 ('Cabine de douche verre trempé 8 mm', 'unite', 285000, 160000, 56, 'Douche & aménagements inox', 3.0, 1.8, false),
 ('Pergola aluminium — lames orientables', 'm2', 175000, 98000, 56, 'Pergolas, auvents & abris', 7.0, 0, false),
 ('Portail coulissant aluminium', 'm2', 145000, 82000, 57, 'Portails, clôtures & grilles', 8.0, 0, false),
 ('Moustiquaire coulissante sur mesure', 'm2', 32000, 17000, 53, 'Fenêtres & châssis', 3.2, 0, true);
