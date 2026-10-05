-- ============================================================================
-- Sanix AluExpert ERP — Conditions et mentions imprimées sous les devis / factures
-- ============================================================================
-- Texte libre propre à chaque structure (Paramètres → Entreprise). Une ligne terminée par « : »
-- est imprimée comme intitulé. Vide = aucune mention.
alter table parametres add column if not exists conditions_documents text;

-- Reprise des conditions auparavant écrites dans le code, UNIQUEMENT pour l'installation d'origine
-- (Beda Alu) : on ne les applique qu'à une ligne de paramètres existante dont la raison sociale
-- mentionne Beda. Une nouvelle structure démarre sans conditions.
update parametres set conditions_documents = $txt$Ne sont pas inclus :
- Tout type de correction (maçonnerie, carrelage, électricité et peinture)
- Plans de réalisation ou plans d'exécution
- La protection des aluminiums ou des inox par film pelable
- Le gardiennage du site de pose
Délais :
- Notre délai dépend de la disponibilité des matériaux en stock et de l'état du chantier
Modalité de paiement :
- 60% à la commande (fabrication, pose des cadres sauf soufflets)
- 40% avant la livraison (vitrage et quincaillerie)$txt$
where conditions_documents is null and raison_sociale ilike '%beda%';
