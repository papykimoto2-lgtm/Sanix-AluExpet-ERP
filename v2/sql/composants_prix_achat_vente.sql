-- Composants : prix d'achat (prix_unitaire, déjà existant — alimente le BOM / coût du Configurateur)
-- et prix de vente (nouveau) pour la revente directe des composants sur les devis.
alter table public.composants add column if not exists prix_vente numeric;
comment on column public.composants.prix_unitaire is 'Prix d''achat unitaire (FCFA) — coût utilisé par le Configurateur';
comment on column public.composants.prix_vente is 'Prix de vente unitaire (FCFA) — proposé sur les lignes de devis';

-- Lien optionnel d'une ligne de devis vers le composant vendu
alter table public.devis_lignes add column if not exists composant_id uuid references public.composants(id) on delete set null;
create index if not exists devis_lignes_composant_id_idx on public.devis_lignes(composant_id);
