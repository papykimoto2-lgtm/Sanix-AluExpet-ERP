-- ============================================================================
-- Sanix AluExpert ERP — Moteur d'impression : registre des documents imprimés
-- et QR code de SÉCURITÉ LOGICIEL (distinct du QR code FNE de la DGI)
-- ============================================================================
-- Chaque document imprimé (devis, facture, reçu, bon, fiche, état périodique, brouillard,
-- ticket Z, page imprimée…) reçoit un CODE D'AUTHENTICITÉ unique et une SIGNATURE HMAC
-- calculée ici avec une clé secrète propre à la base (jamais exposée au navigateur).
-- Le QR code de sécurité pointe vers la page de vérification de l'application
-- (…/index.html?verif=CODE-SIGNATURE) : n'importe qui, sans compte, peut contrôler qu'un papier
-- a bien été émis par le logiciel et que son type, numéro, montant et tiers n'ont pas été modifiés.
-- Le QR code FNE (certification DGI) reste un QR séparé, uniquement sur les factures certifiées.
-- Réimprimer le même document (mêmes données) conserve son code et incrémente le compteur
-- (impression n° 2, 3… = duplicata) ; un document aux données modifiées reçoit un nouveau code.
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;

alter table public.parametres add column if not exists impression jsonb not null default '{}'::jsonb;

-- Clé secrète de signature (une ligne) : RLS sans politique → illisible depuis l'API
create table if not exists public.securite_documents_cle (
  id int primary key default 1 check (id = 1),
  cle bytea not null,
  created_at timestamptz not null default now()
);
alter table public.securite_documents_cle enable row level security;
revoke all on public.securite_documents_cle from public, anon, authenticated;
insert into public.securite_documents_cle (id, cle) values (1, extensions.gen_random_bytes(32)) on conflict (id) do nothing;

create table if not exists public.documents_imprimes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  signature text not null,
  type text not null,
  titre text,
  numero text,
  montant numeric(16,2) not null default 0,
  tiers text,
  periode text,
  niveau text,
  empreinte text not null,
  format text,
  nb_impressions integer not null default 1,
  premiere_impression timestamptz not null default now(),
  derniere_impression timestamptz not null default now(),
  imprime_par uuid default auth.uid(),
  imprime_par_nom text,
  statut text not null default 'valide' check (statut in ('valide','revoque')),
  motif_revocation text,
  revoque_le timestamptz,
  revoque_par text
);
create index if not exists idx_documents_imprimes_date on public.documents_imprimes (derniere_impression desc);
create index if not exists idx_documents_imprimes_doc on public.documents_imprimes (type, numero, empreinte);

alter table public.documents_imprimes enable row level security;
drop policy if exists "documents_imprimes_lecture" on public.documents_imprimes;
create policy "documents_imprimes_lecture" on public.documents_imprimes for select to authenticated
  using (public.est_utilisateur_autorise());
-- Pas d'écriture directe : tout passe par les fonctions ci-dessous

create or replace function public.document_signature(p_code text, p_type text, p_numero text, p_montant numeric, p_empreinte text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select upper(substr(encode(extensions.hmac(
    convert_to(concat_ws('|', p_code, p_type, coalesce(p_numero, ''), to_char(coalesce(p_montant, 0), 'FM999999999999990.00'), p_empreinte), 'UTF8'),
    (select cle from securite_documents_cle where id = 1), 'sha256'), 'hex'), 1, 12));
$$;
revoke all on function public.document_signature(text, text, text, numeric, text) from public, anon, authenticated;

-- Enregistre une impression ; renvoie le code, la signature et le n° d'impression
create or replace function public.document_imprime_enregistrer(
  p_type text, p_numero text, p_titre text, p_montant numeric, p_tiers text, p_periode text,
  p_empreinte text, p_format text default 'a4', p_niveau text default null)
returns table (code text, signature text, nb_impressions integer, premiere_impression timestamptz, statut text)
language plpgsql security definer set search_path = public, extensions as $$
declare v public.documents_imprimes; v_code text; v_nom text;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if coalesce(p_type, '') = '' or coalesce(p_empreinte, '') = '' then raise exception 'Document incomplet'; end if;
  perform pg_advisory_xact_lock(hashtext('doc_imprime:' || p_type || ':' || coalesce(p_numero, '') || ':' || p_empreinte));
  select * into v from documents_imprimes d where d.type = p_type and d.numero is not distinct from nullif(p_numero, '') and d.empreinte = p_empreinte
    order by d.premiere_impression limit 1;
  if found then
    update documents_imprimes d set nb_impressions = d.nb_impressions + 1, derniere_impression = now() where d.id = v.id returning * into v;
  else
    select coalesce(nullif(p.nom_complet, ''), u.email, auth.uid()::text) into v_nom
      from auth.users u left join profiles p on p.id = u.id where u.id = auth.uid();
    loop
      v_code := 'SX-' || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4)) || '-'
                      || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4)) || '-'
                      || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 4));
      exit when not exists (select 1 from documents_imprimes d where d.code = v_code);
    end loop;
    insert into documents_imprimes (code, signature, type, titre, numero, montant, tiers, periode, niveau, empreinte, format, imprime_par, imprime_par_nom)
      values (v_code, public.document_signature(v_code, p_type, nullif(p_numero, ''), coalesce(p_montant, 0), p_empreinte),
              p_type, p_titre, nullif(p_numero, ''), coalesce(p_montant, 0), nullif(p_tiers, ''), nullif(p_periode, ''), nullif(p_niveau, ''),
              p_empreinte, p_format, auth.uid(), v_nom)
      returning * into v;
  end if;
  return query select v.code, v.signature, v.nb_impressions, v.premiere_impression, v.statut;
end $$;
revoke all on function public.document_imprime_enregistrer(text, text, text, numeric, text, text, text, text, text) from public, anon;
grant execute on function public.document_imprime_enregistrer(text, text, text, numeric, text, text, text, text, text) to authenticated;

-- Vérification publique (scan du QR, sans compte). Les détails ne sont révélés que si la signature
-- correspond au code (le code seul ne suffit pas : impossible de parcourir le registre).
create or replace function public.document_verifier(p_code text, p_signature text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v public.documents_imprimes; v_sig text; p public.parametres;
begin
  select * into v from documents_imprimes d where d.code = upper(trim(p_code));
  if not found then return jsonb_build_object('trouve', false); end if;
  v_sig := public.document_signature(v.code, v.type, v.numero, v.montant, v.empreinte);
  if v_sig <> v.signature or upper(trim(coalesce(p_signature, ''))) <> v.signature then
    return jsonb_build_object('trouve', true, 'signature_valide', false);
  end if;
  select * into p from parametres limit 1;
  return jsonb_build_object(
    'trouve', true, 'signature_valide', true, 'code', v.code, 'type', v.type, 'titre', v.titre, 'numero', v.numero,
    'montant', v.montant, 'tiers', v.tiers, 'periode', v.periode, 'niveau', v.niveau,
    'premiere_impression', v.premiere_impression, 'derniere_impression', v.derniere_impression,
    'nb_impressions', v.nb_impressions, 'imprime_par', v.imprime_par_nom,
    'statut', v.statut, 'motif_revocation', v.motif_revocation, 'revoque_le', v.revoque_le,
    'entreprise', p.raison_sociale, 'ncc', p.ncc, 'rccm', p.rccm, 'telephone', p.telephone);
end $$;
revoke all on function public.document_verifier(text, text) from public;
grant execute on function public.document_verifier(text, text) to anon, authenticated;

-- Révocation (document annulé, falsifié, remplacé…) : administrateur / manager
create or replace function public.document_revoquer(p_code text, p_motif text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'Motif obligatoire'; end if;
  update documents_imprimes set statut = 'revoque', motif_revocation = trim(p_motif), revoque_le = now(),
    revoque_par = (select coalesce(nullif(email, ''), id::text) from auth.users where id = auth.uid())
    where code = upper(trim(p_code)) and statut = 'valide';
  if not found then raise exception 'Document introuvable ou déjà révoqué'; end if;
end $$;
revoke all on function public.document_revoquer(text, text) from public, anon;
grant execute on function public.document_revoquer(text, text) to authenticated;
