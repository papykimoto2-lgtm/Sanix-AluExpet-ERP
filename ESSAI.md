# Essai gratuit de 30 jours — Sanix AluExpert ERP

Pour proposer un essai à un prospect, lui envoyer le lien `…/essai.html` (à côté de `index.html`, même déploiement).

- Le prospect crée son espace : société, nom, e-mail (identifiant) et mot de passe (8 caractères minimum). Aucune donnée d'exemple client.
- L'espace est **local à l'appareil** : le cloud SANIX (projet Supabase) est neutralisé pendant l'essai, rien n'est envoyé. Il faut garder le même appareil et le même navigateur.
- Un bandeau indique les jours restants (en rouge à 5 jours ou moins).
- À l'expiration, un écran de verrouillage propose de télécharger une sauvegarde (JSON : tables de l'application et réglages) et de contacter SANIX.
- Reculer l'horloge de l'appareil ne prolonge pas l'essai (la dernière date vue est mémorisée).
- Un appareil qui contient déjà de vraies données AluExpert (compte autre que `admin@sanix.local` ou base locale remplie) est refusé, pour ne rien écraser.

Limite : l'essai est stocké dans le navigateur ; vider les données du site permet d'en démarrer un nouveau. Ce n'est pas une protection de licence.

Fichiers : `essai.html` (activation), `essai.js` (bandeau, verrouillage, sauvegarde, mode local), une ligne dans `index.html` (`<script src="essai.js">` juste après `SANIX_CFG`).
