-- Main-d'œuvre facturée sur les devis (en plus de « autre_frais » = autres charges facturées)
alter table public.devis add column if not exists main_oeuvre numeric default 0 not null;
