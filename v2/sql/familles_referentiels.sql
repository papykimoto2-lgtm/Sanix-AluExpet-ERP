-- ============================================================================
-- Sanix AluExpert ERP — Référentiels paramétrables : familles d'articles et unités de mesure
-- ============================================================================
-- Remplace les listes codées en dur dans l'application :
--   • familles de COMPOSANTS / consommables (icône, couleur, ordre, compte de stock SYSCOHADA) ;
--   • familles de PRODUITS / ouvrages (icône, couleur, ordre) — aussi utilisées par les réalisations ;
--   • unités de mesure des composants (auparavant bloquées par une contrainte CHECK figée).
-- Le compte de stock d'une famille (321 profilés, 322 vitrages, 323 fournitures, 331 consommables…)
-- remplace la déduction « au nom » de la famille : la comptabilisation automatique et la variation
-- des stocks utilisent désormais ce réglage.
-- Renommer une famille renomme aussi les articles qui la portent ; une famille utilisée ne peut pas
-- être supprimée : on la fusionne dans une autre (famille_fusionner) ou on la désactive.
-- Les unités des PRODUITS (unité / m² / ml) restent figées : elles pilotent le calcul du prix.
-- ============================================================================
create table if not exists public.familles_articles (
  id uuid primary key default gen_random_uuid(),
  domaine text not null check (domaine in ('composant','produit')),
  nom text not null check (length(trim(nom)) > 0),
  icone text,
  couleur text,
  compte_stock text check (compte_stock in ('stock_profiles','stock_vitrage','stock_fournitures','stock_consommables')),
  ordre integer not null default 100,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  constraint familles_articles_nom_key unique (domaine, nom)
);

alter table public.familles_articles enable row level security;
drop policy if exists "familles_lecture" on public.familles_articles;
create policy "familles_lecture" on public.familles_articles for select to authenticated using (public.est_utilisateur_autorise());
drop policy if exists "familles_creation" on public.familles_articles;
create policy "familles_creation" on public.familles_articles for insert to authenticated with check (public.est_utilisateur_autorise());
drop policy if exists "familles_modification" on public.familles_articles;
create policy "familles_modification" on public.familles_articles for update to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse()) with check (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());
drop policy if exists "familles_suppression" on public.familles_articles;
create policy "familles_suppression" on public.familles_articles for delete to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());

-- Renommage propagé aux articles ; suppression refusée si la famille est utilisée
create or replace function public.familles_articles_propager() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_op = 'UPDATE' then
    if new.domaine <> old.domaine then raise exception 'Le domaine d''une famille ne se modifie pas'; end if;
    new.nom := trim(new.nom);
    if new.nom <> old.nom then
      if old.domaine = 'composant' then
        update composants set famille = new.nom where famille = old.nom;
      else
        update produits set famille = new.nom where famille = old.nom;
        update realisations set famille = new.nom where famille = old.nom;
      end if;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.domaine = 'composant' then select count(*) into n from composants where famille = old.nom;
    else select (select count(*) from produits where famille = old.nom) + (select count(*) from realisations where famille = old.nom) into n; end if;
    if n > 0 then raise exception 'La famille « % » est utilisée par % article(s) : fusionnez-la dans une autre famille ou désactivez-la.', old.nom, n; end if;
    return old;
  end if;
  new.nom := trim(new.nom);
  return new;
end $$;
drop trigger if exists trg_familles_articles_propager on public.familles_articles;
create trigger trg_familles_articles_propager before insert or update or delete on public.familles_articles
  for each row execute function public.familles_articles_propager();

-- Fusion : déplace les articles de la famille source vers la cible, puis supprime la source
create or replace function public.famille_fusionner(p_source uuid, p_cible uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare s familles_articles; c familles_articles; n int := 0; k int;
begin
  if not public.est_utilisateur_autorise() or not public.est_gestionnaire_caisse() then raise exception 'Réservé aux administrateurs et managers'; end if;
  select * into s from familles_articles where id = p_source;
  select * into c from familles_articles where id = p_cible;
  if s.id is null or c.id is null then raise exception 'Famille introuvable'; end if;
  if s.id = c.id then raise exception 'Choisissez une autre famille'; end if;
  if s.domaine <> c.domaine then raise exception 'Les deux familles doivent être du même domaine'; end if;
  if s.domaine = 'composant' then
    update composants set famille = c.nom where famille = s.nom; get diagnostics n = row_count;
  else
    update produits set famille = c.nom where famille = s.nom; get diagnostics n = row_count;
    update realisations set famille = c.nom where famille = s.nom; get diagnostics k = row_count; n := n + k;
  end if;
  delete from familles_articles where id = s.id;
  return n;
end $$;
revoke all on function public.famille_fusionner(uuid, uuid) from public, anon;
grant execute on function public.famille_fusionner(uuid, uuid) to authenticated;

-- Familles de départ (anciennes listes de l'application) + familles déjà présentes dans les données
insert into public.familles_articles (domaine, nom, icone, couleur, compte_stock, ordre) values
  ('composant','Profilé aluminium','🪜','#2563eb','stock_profiles',10),
  ('composant','Vitrage','🪟','#7c3aed','stock_vitrage',20),
  ('composant','Panneau','🧱','#0f766e','stock_profiles',30),
  ('composant','Quincaillerie','🔩','#475569','stock_fournitures',40),
  ('composant','Visserie & fixations','🔧','#0891b2','stock_fournitures',50),
  ('composant','Joint & étanchéité','➰','#d97706','stock_fournitures',60),
  ('composant','Motorisation','⚙️','#be123c','stock_fournitures',70),
  ('composant','Consommable atelier','🧴','#059669','stock_consommables',80),
  ('composant','Autre','📦','#6b7280',null,999),
  ('produit','Fenêtres & châssis','🪟','#1d4ed8',null,10),
  ('produit','Coulissants, baies & pliants','↔️','#0369a1',null,20),
  ('produit','Portes','🚪','#b45309',null,30),
  ('produit','Façades, vitrines, cloisons & verrières','🏢','#be185d',null,40),
  ('produit','Fermetures, volets & protections solaires','🌗','#4d7c0f',null,50),
  ('produit','Pergolas, auvents & abris','⛱️','#15803d',null,60),
  ('produit','Garde-corps, rampes & mains courantes','🛡️','#334155',null,70),
  ('produit','Portails, clôtures & grilles','🚧','#7c2d12',null,80),
  ('produit','Douche & aménagements inox','🚿','#0e7490',null,90),
  ('produit','Habillage & bardage composite','🧱','#6d28d9',null,100),
  ('produit','Fenêtre coulissante','🪟','#2563eb',null,110),
  ('produit','Porte à la française','🚪','#d97706',null,120),
  ('produit','Porte coulissante','🚪','#ea580c',null,130),
  ('produit','Coulissant galandage','🚪','#0891b2',null,140),
  ('produit','Fenêtre jalousie','🪟','#7c3aed',null,150),
  ('produit','Moustiquaire fixe','🦟','#059669',null,160),
  ('produit','Moustiquaire coulissante','🦟','#10b981',null,170),
  ('produit','Garde-corps inox','🛡️','#475569',null,180),
  ('produit','Verrière / mur rideau','🏢','#be185d',null,190),
  ('produit','Autre','📦','#6b7280',null,999)
on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'composant', trim(famille), '📦', '#6b7280', 500 from public.composants where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'produit', trim(famille), '📦', '#6b7280', 500 from public.produits where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;
insert into public.familles_articles (domaine, nom, icone, couleur, ordre)
  select distinct 'produit', trim(famille), '📦', '#6b7280', 500 from public.realisations where coalesce(trim(famille),'') <> ''
  on conflict (domaine, nom) do nothing;

-- ---------- Unités de mesure des composants ----------
create table if not exists public.unites_mesure (
  code text primary key check (code ~ '^[a-z0-9_]{1,20}$'),
  libelle text not null,
  ordre integer not null default 100,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.unites_mesure enable row level security;
drop policy if exists "unites_lecture" on public.unites_mesure;
create policy "unites_lecture" on public.unites_mesure for select to authenticated using (public.est_utilisateur_autorise());
drop policy if exists "unites_creation" on public.unites_mesure;
create policy "unites_creation" on public.unites_mesure for insert to authenticated with check (public.est_utilisateur_autorise());
drop policy if exists "unites_modification" on public.unites_mesure;
create policy "unites_modification" on public.unites_mesure for update to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse()) with check (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());
drop policy if exists "unites_suppression" on public.unites_mesure;
create policy "unites_suppression" on public.unites_mesure for delete to authenticated
  using (public.est_utilisateur_autorise() and public.est_gestionnaire_caisse());

insert into public.unites_mesure (code, libelle, ordre) values
  ('unite','Unité',10),('ml','Mètre linéaire (ml)',20),('m2','Mètre carré (m²)',30),('kg','Kilogramme (kg)',40),
  ('litre','Litre',50),('boite','Boîte',60),('cartouche','Cartouche',70)
on conflict (code) do nothing;
insert into public.unites_mesure (code, libelle, ordre)
  select distinct unite, unite, 500 from public.composants where unite is not null and unite ~ '^[a-z0-9_]{1,20}$'
  on conflict (code) do nothing;

-- La contrainte figée est remplacée par une clé étrangère vers le référentiel (unité supprimable seulement si inutilisée)
alter table public.composants drop constraint if exists composants_unite_check;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'composants_unite_fk') then
    alter table public.composants add constraint composants_unite_fk foreign key (unite) references public.unites_mesure(code) on update cascade on delete restrict;
  end if;
end $$;
