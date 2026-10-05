# Sanix AluExpert ERP — v2 (démo)

Version évoluée d'AluExpert, basée sur le socle ERP de 100 % INOX : Supabase (Postgres + RLS + Auth + Edge Functions),
ventes comptoir + ticket Z, caisse avec circuit de validation, achats / réceptions, dépôts & transferts, inventaires,
comptabilité SYSCOHADA révisée, portail client, site vitrine. L'application historique à la racine du dépôt reste intacte.

## Installation (projet Supabase dédié à la démo)
1. Créer un projet Supabase « AluExpert Démo » (ne jamais utiliser le projet de production).
2. SQL Editor : exécuter `sql/00_installation_complete.sql`, puis dans l'ordre `sql/demo/01_base.sql` … `06_portail_divers.sql`
   (le script 01 refuse de s'exécuter si la base contient déjà des clients/projets).
3. Déployer les Edge Functions de `supabase/functions` (`connexion` avec verify_jwt = false, `gestion-utilisateurs`, `fne-proxy`).
4. Copier `config.example.js` en `config.js` avec l'URL et la clé publishable du projet.
5. Déployer le dossier `v2/` (Vercel, dossier racine = `v2`).

## Comptes de démonstration (mot de passe : `Demo@2026`)
| Identifiant | E-mail | Rôle |
|---|---|---|
| demo | demo@aluexpert.ci | Direction |
| commercial | commercial@aluexpert.ci | Commercial |
| caisse | caisse@aluexpert.ci | Caissier |
| compta | compta@aluexpert.ci | Comptable |
| manager | manager@aluexpert.ci | Manager |

## Jeu de données (`sql/demo/`)
01 base (utilisateurs, clients, fournisseurs, catalogue, paramètres) · 02 stock & achats · 03 chantiers, devis, factures, paiements ·
04 caisse, comptoir, ticket Z · 05 comptabilité (69 écritures équilibrées) · 06 vitrine, invitations, journal de connexion.
Le jeu est généré via les fonctions métier de l'application (stock, ventes, réceptions…), donc cohérent de bout en bout.
