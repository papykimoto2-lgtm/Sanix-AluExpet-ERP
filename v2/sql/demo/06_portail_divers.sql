-- ============================================================================
-- Sanix AluExpert ERP — JEU DE DONNÉES DE DÉMONSTRATION (6/6) : vitrine / portail, invitations, journal de connexion
-- (à lancer après 05_comptabilite.sql)
-- ============================================================================
-- Réalisations affichées sur le site vitrine (visuels vectoriels générés, aucune photo réelle)
create or replace function pg_temp.visuel(p_c1 text, p_c2 text, p_legende text) returns text language sql as $$
  select 'data:image/svg+xml;base64,' || encode(convert_to(
    '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420" viewBox="0 0 640 420"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="' || p_c1 || '"/><stop offset="1" stop-color="' || p_c2 || '"/></linearGradient></defs><rect width="640" height="420" fill="url(#g)"/><g fill="none" stroke="#ffffff" stroke-opacity=".55" stroke-width="6"><rect x="120" y="70" width="400" height="280" rx="6"/><line x1="320" y1="70" x2="320" y2="350"/><line x1="120" y1="210" x2="520" y2="210"/></g><text x="320" y="395" font-family="Arial" font-size="22" fill="#ffffff" text-anchor="middle">' || p_legende || '</text></svg>', 'UTF8'), 'base64')
$$;

insert into public.realisations (titre, description, famille, photo_base64, ordre, publie, created_by) values
  ('Mur-rideau — Siège Riviera', 'Façade vitrée en mur-rideau aluminium laqué, vitrage réfléchissant 8 mm, 120 m².', 'Façades', pg_temp.visuel('#0f172a', '#2563eb', 'Mur-rideau'), 1, true, '00000000-0000-4000-8000-000000000001'),
  ('Fenêtres coulissantes — Résidence Palmeraie', '48 fenêtres coulissantes 2 vantaux, double vitrage, moustiquaires intégrées.', 'Fenêtres', pg_temp.visuel('#134e4a', '#14b8a6', 'Fenêtres coulissantes'), 2, true, '00000000-0000-4000-8000-000000000001'),
  ('Garde-corps inox — Villa Cocody', 'Garde-corps inox 304 et verre feuilleté, escalier et terrasse.', 'Garde-corps', pg_temp.visuel('#334155', '#94a3b8', 'Garde-corps inox'), 3, true, '00000000-0000-4000-8000-000000000001'),
  ('Portail coulissant motorisé — Zone 4', 'Portail aluminium 5 m motorisé avec contrôle d''accès.', 'Portails', pg_temp.visuel('#7c2d12', '#f97316', 'Portail motorisé'), 4, true, '00000000-0000-4000-8000-000000000001'),
  ('Pergola bioclimatique — Restaurant Marcory', 'Pergola à lames orientables motorisées, 36 m².', 'Pergolas', pg_temp.visuel('#365314', '#84cc16', 'Pergola bioclimatique'), 5, true, '00000000-0000-4000-8000-000000000001'),
  ('Portes en aluminium — Clinique Angré', 'Portes battantes aluminium anodisé avec ferme-porte, 22 ouvrants.', 'Portes', pg_temp.visuel('#581c87', '#a855f7', 'Portes aluminium'), 6, true, '00000000-0000-4000-8000-000000000001');

-- Invitation en attente et journal de connexion
insert into public.invitations (email, role_id, statut, invited_by, created_at)
  select 'nouveau.technicien@aluexpert.ci', id, 'en_attente', '00000000-0000-4000-8000-000000000001', now() - interval '1 day' from public.roles order by created_at limit 1;
insert into public.logs_connexion (login_saisi, user_id, succes, detail, ip, user_agent, created_at) values
  ('demo', '00000000-0000-4000-8000-000000000001', true, 'Connexion réussie', '196.200.0.10', 'Mozilla/5.0 (Windows NT 10.0)', now() - interval '2 hours'),
  ('caisse', '00000000-0000-4000-8000-000000000003', true, 'Connexion réussie', '196.200.0.11', 'Mozilla/5.0 (Android 13)', now() - interval '3 hours'),
  ('compta', '00000000-0000-4000-8000-000000000004', true, 'Connexion réussie', '196.200.0.12', 'Mozilla/5.0 (Macintosh)', now() - interval '1 day'),
  ('inconnu', null, false, 'Identifiant inconnu', '41.66.0.5', 'curl/8.0', now() - interval '2 days');
