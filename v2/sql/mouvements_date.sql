-- Date de mouvement saisissable sur les mouvements de stock (created_at reste la date d'enregistrement)
alter table public.mouvements_stock add column if not exists date_mouvement date;
update public.mouvements_stock set date_mouvement = (created_at at time zone 'UTC')::date where date_mouvement is null;
alter table public.mouvements_stock alter column date_mouvement set default current_date;
create index if not exists mouvements_stock_date_mouvement_idx on public.mouvements_stock (date_mouvement);

drop function if exists public.stock_mouvement(uuid,text,numeric,text,text,numeric,uuid,uuid,uuid);
create or replace function public.stock_mouvement(p_composant_id uuid, p_type text, p_quantite numeric, p_motif text default null, p_reference text default null, p_prix_unitaire numeric default null, p_depot_id uuid default null, p_transfert_id uuid default null, p_projet_id uuid default null, p_date_mouvement date default null)
returns composants language plpgsql set search_path to 'public' as $function$
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
                                created_by, depot_id, transfert_id, stock_depot_apres, projet_id, date_mouvement)
    values (p_composant_id, p_type, v_delta, p_prix_unitaire, v_comp.stock_actuel, v_new_cmup, p_motif, p_reference,
            auth.uid(), v_depot, p_transfert_id, v_qte_depot + v_delta, p_projet_id, coalesce(p_date_mouvement, current_date));
  return v_comp;
end $function$;
