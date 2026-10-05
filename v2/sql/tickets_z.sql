-- ============================================================================
-- Sanix AluExpert ERP — Tickets Z des points de vente (clôture journalière et état périodique)
-- ============================================================================
-- Trois états distincts :
--   • Ventilation des mouvements de caisse (Comptabilité) : imputation comptable de chaque mouvement ;
--   • Brouillard de caisse (Caisse) : journal chronologique des entrées / sorties d'une caisse, solde progressif,
--     comptage et écart par séance — calculé à partir de caisse_sessions / caisse_mouvements (aucune table) ;
--   • Ticket Z (Point de vente) : relevé NUMÉROTÉ et définitif des ventes d'un point de vente pour une journée
--     (Z journalier) ou une période (Z périodique, ex. mensuel), avec grand total perpétuel. Enregistré ici.
-- Un Z ne se modifie pas : une nouvelle édition du même Z est une réimpression (DUPLICATA, compteur).
-- ============================================================================
create table if not exists public.tickets_z (
  id uuid primary key default gen_random_uuid(),
  point_vente_id uuid not null references public.points_vente(id) on delete restrict,
  type text not null check (type in ('journalier','periodique')),
  numero integer not null,
  date_debut date not null,
  date_fin date not null,
  nb_ventes integer not null default 0,
  total_ttc numeric(14,2) not null default 0,
  grand_total numeric(16,2) not null default 0,
  totaux jsonb not null default '{}'::jsonb,
  edite_par text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  nb_reimpressions integer not null default 0,
  derniere_reimpression timestamptz,
  constraint tickets_z_numero_key unique (point_vente_id, type, numero),
  constraint tickets_z_periode_key unique (point_vente_id, type, date_debut, date_fin),
  constraint tickets_z_dates_check check (date_debut <= date_fin and (type = 'periodique' or date_debut = date_fin))
);
create index if not exists idx_tickets_z_pdv on public.tickets_z (point_vente_id, date_fin desc);

alter table public.tickets_z enable row level security;
drop policy if exists "tickets_z_lecture" on public.tickets_z;
create policy "tickets_z_lecture" on public.tickets_z for select to authenticated
  using (public.est_utilisateur_autorise());
-- Pas d'écriture directe : émission et réimpression passent par ticket_z_emettre()

-- Émet (ou réimprime) le Z d'un point de vente. Nombre de ventes, total TTC et grand total sont recalculés
-- ici à partir des ventes validées ; p_totaux (modes de paiement, TVA, remises, caisse…) est conservé tel quel.
create or replace function public.ticket_z_emettre(p_pdv uuid, p_type text, p_debut date, p_fin date, p_totaux jsonb default '{}'::jsonb)
returns public.tickets_z
language plpgsql security definer set search_path = public as $$
declare v public.tickets_z; v_nb int; v_total numeric; v_gt numeric; v_num int;
begin
  if not public.est_utilisateur_autorise() then raise exception 'Accès refusé'; end if;
  if not public.peut_utiliser_point_vente(p_pdv) then raise exception 'Vous n''êtes pas affecté(e) à ce point de vente'; end if;
  if p_type not in ('journalier','periodique') then raise exception 'Type de ticket Z invalide'; end if;
  if p_type = 'journalier' and p_debut <> p_fin then raise exception 'Un Z journalier porte sur un seul jour'; end if;
  if p_debut > p_fin then raise exception 'Période invalide'; end if;
  if p_fin > current_date then raise exception 'Impossible d''émettre un Z sur une date future'; end if;
  perform pg_advisory_xact_lock(hashtext('ticket_z:' || p_pdv::text || ':' || p_type));

  select * into v from tickets_z where point_vente_id = p_pdv and type = p_type and date_debut = p_debut and date_fin = p_fin;
  if found then
    update tickets_z set nb_reimpressions = nb_reimpressions + 1, derniere_reimpression = now() where id = v.id returning * into v;
    return v;
  end if;

  select count(*), coalesce(sum(total), 0) into v_nb, v_total from ventes_comptoir
    where point_vente_id = p_pdv and statut = 'validee' and date_vente between p_debut and p_fin;
  select coalesce(sum(total), 0) into v_gt from ventes_comptoir
    where point_vente_id = p_pdv and statut = 'validee' and date_vente <= p_fin;
  select coalesce(max(numero), 0) + 1 into v_num from tickets_z where point_vente_id = p_pdv and type = p_type;

  insert into tickets_z (point_vente_id, type, numero, date_debut, date_fin, nb_ventes, total_ttc, grand_total, totaux, edite_par, created_by)
    values (p_pdv, p_type, v_num, p_debut, p_fin, v_nb, v_total, v_gt, coalesce(p_totaux, '{}'::jsonb),
            (select coalesce(nullif(email, ''), id::text) from auth.users where id = auth.uid()), auth.uid())
    returning * into v;
  return v;
end $$;
revoke all on function public.ticket_z_emettre(uuid, text, date, date, jsonb) from public, anon;
grant execute on function public.ticket_z_emettre(uuid, text, date, date, jsonb) to authenticated;
