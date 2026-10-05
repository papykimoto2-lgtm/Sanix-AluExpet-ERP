-- ============================================================================
-- Sanix AluExpert ERP — Photos des produits et des composants (vente au comptoir)
-- ============================================================================
-- • composants.photo / produits.photo : MINIATURE compressée (≈ 240 px, quelques Ko) chargée avec les listes
--   et le catalogue de la vente au comptoir (fonctionne aussi hors ligne, avec la copie locale) ;
-- • photos_articles : photo en GRAND format (≈ 1 000 px), chargée seulement à l'agrandissement ou en fiche,
--   clé « composant:<id> » ou « produit:<id> » ;
-- • produits.vente_comptoir : le produit (ouvrage) est proposé à la vente au comptoir (sans mouvement de stock).
-- ============================================================================
alter table public.composants add column if not exists photo text;
alter table public.produits add column if not exists photo text;
alter table public.produits add column if not exists vente_comptoir boolean not null default true;

create table if not exists public.photos_articles (
  cle text primary key,
  image text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.photos_articles enable row level security;
drop policy if exists "photos_articles_lecture" on public.photos_articles;
create policy "photos_articles_lecture" on public.photos_articles for select to authenticated
  using (public.est_utilisateur_autorise());
drop policy if exists "photos_articles_ecriture" on public.photos_articles;
create policy "photos_articles_ecriture" on public.photos_articles for all to authenticated
  using (public.est_utilisateur_autorise()) with check (public.est_utilisateur_autorise());
