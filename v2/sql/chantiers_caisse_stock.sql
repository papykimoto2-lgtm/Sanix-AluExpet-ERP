-- ============================================================================
-- Sanix AluExpert ERP — Rattacher les mouvements de caisse et de stock au chantier d'un client
-- ============================================================================
-- Un bon d'entrée / de sortie de caisse et un mouvement de stock peuvent désormais être
-- rattachés à un chantier (projet) : suivi des dépenses et des matériaux par chantier,
-- écriture comptable de ventilation rattachée au même chantier.
-- ============================================================================
alter table public.caisse_mouvements add column if not exists projet_id uuid references public.projets(id) on delete set null;
alter table public.mouvements_stock add column if not exists projet_id uuid references public.projets(id) on delete set null;
create index if not exists idx_caisse_mvt_projet on public.caisse_mouvements (projet_id);
create index if not exists idx_mouvements_stock_projet on public.mouvements_stock (projet_id);

-- Reprise de l'existant : mouvements d'une caisse de chantier → ce chantier ;
-- sorties de stock d'une fiche d'exécution → le chantier de la fiche
update public.caisse_mouvements m set projet_id = c.projet_id
  from public.caisses c where c.id = m.caisse_id and c.projet_id is not null and m.projet_id is null;
update public.mouvements_stock ms set projet_id = f.projet_id
  from public.fiches_execution f
  where ms.reference = f.code and ms.motif = 'Fiche d''exécution' and f.projet_id is not null and ms.projet_id is null;

-- Mouvement de stock : paramètre facultatif p_projet_id (les appels existants restent valables)
drop function if exists public.stock_mouvement(uuid, text, numeric, text, text, numeric, uuid, uuid);
create or replace function public.stock_mouvement(p_composant_id uuid, p_type text, p_quantite numeric,
  p_motif text default null, p_reference text default null, p_prix_unitaire numeric default null,
  p_depot_id uuid default null, p_transfert_id uuid default null, p_projet_id uuid default null)
returns composants
language plpgsql set search_path = public as $$
declare
  v_comp composants%rowtype;
  v_depot uuid;
  v_qte_depot numeric;
  v_delta numeric;
  v_new_cmup numeric;
begin
  if p_type not in ('entree','sortie','ajustement','inventaire','transfert') then
    raise exception 'Type de mouvement invalide: %', p_type;
  end if;
  v_depot := coalesce(p_depot_id, (select id from depots where est_principal limit 1));
  if v_depot is null then raise exception 'Aucun dépôt principal défini'; end if;

  select * into v_comp from composants where id = p_composant_id for update;
  if v_comp.id is null then raise exception 'Composant introuvable'; end if;

  insert into stocks_depot(depot_id, composant_id, quantite) values (v_depot, p_composant_id, 0)
    on conflict (depot_id, composant_id) do nothing;
  select quantite into v_qte_depot from stocks_depot where depot_id = v_depot and composant_id = p_composant_id for update;

  v_new_cmup := coalesce(v_comp.cmup, 0);
  if p_type = 'entree' then
    if p_quantite <= 0 then raise exception 'Quantité entrée doit être positive'; end if;
    v_delta := p_quantite;
    if p_prix_unitaire is not null and (v_comp.stock_actuel + p_quantite) > 0 then
      v_new_cmup := ((v_comp.stock_actuel * coalesce(v_comp.cmup,0)) + (p_quantite * p_prix_unitaire))
                    / (v_comp.stock_actuel + p_quantite);
    else
      v_new_cmup := coalesce(v_comp.cmup, p_prix_unitaire, 0);
    end if;
  elsif p_type = 'sortie' then
    if p_quantite <= 0 then raise exception 'Quantité sortie doit être positive'; end if;
    v_delta := -p_quantite;
  elsif p_type in ('ajustement','transfert') then
    v_delta := p_quantite;
  elsif p_type = 'inventaire' then
    v_delta := p_quantite - v_qte_depot;
  end if;

  update stocks_depot set quantite = quantite + v_delta where depot_id = v_depot and composant_id = p_composant_id;
  update composants set stock_actuel = stock_actuel + v_delta, cmup = v_new_cmup where id = p_composant_id
    returning * into v_comp;

  insert into mouvements_stock (composant_id, type, quantite, prix_unitaire, stock_apres, cmup_apres, motif, reference,
                                created_by, depot_id, transfert_id, stock_depot_apres, projet_id)
    values (p_composant_id, p_type, v_delta, p_prix_unitaire, v_comp.stock_actuel, v_new_cmup, p_motif, p_reference,
            auth.uid(), v_depot, p_transfert_id, v_qte_depot + v_delta, p_projet_id);
  return v_comp;
end $$;
