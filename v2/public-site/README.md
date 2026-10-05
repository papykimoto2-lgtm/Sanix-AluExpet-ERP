# Portail client BEDA ALU — site public

`index.html` et `portail-unique.html` sont **identiques** et **toujours à jour** :
ils ne contiennent que la connexion Supabase (URL + clé publique) et interrogent en
direct, à chaque visite, la fonction publique `portail_donnees_publiques()` pour
afficher le contenu actuel (réalisations, produits, mot du DG, coordonnées,
activation). **Aucune donnée métier n'est figée dans ces fichiers.**

Modifier le contenu dans l'ERP (Paramètres → 🌐 Portail client, Réalisations,
Produits) suffit — le site public le reflète aussitôt, **sans régénérer ni
redéployer**. Ces deux fichiers ne doivent être régénérés que si le **code** du
portail change (design, fonctionnalités) — depuis Paramètres → Portail client,
bouton « 🔗 Générer « portail-unique.html » ».

Déployé séparément de l'ERP (projet Vercel dédié, racine = `public-site/`) pour
ne pas hériter de la protection SSO de l'outil interne.
