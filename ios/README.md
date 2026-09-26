# NeonWave pour iPhone

Application **native SwiftUI**, destinée à iOS 17 et versions ultérieures. Aucun écran HTML, aucune WebView de lecture, aucune dépendance Electron ou Capacitor. Le projet Xcode est livré directement : pas de CocoaPods ni de XcodeGen.

## État exact de cette livraison

Le code du client iOS, le projet Xcode, l’icône, les services d’authentification et les tests sont présents. La syntaxe des sources et la structure du projet ont été vérifiées sous Windows ; les tests du serveur sont exécutables ici. **Le client n’a pas été compilé ni testé sur simulateur ou iPhone : cette validation nécessite macOS et Xcode. Aucune IPA signée, aucun envoi TestFlight/App Store n’a été effectué.**

Les connexions Apple et Google nécessitent les comptes développeur et les secrets du propriétaire du service. Elles sont désactivées tant que le serveur ne les annonce pas disponibles. L’acceptation App Store n’est pas garantie par la présence du projet.

## Fonctions du client

- Accueil avec salutation, mix aléatoire de la bibliothèque, écoutes récentes et derniers ajouts.
- Connexion e-mail, création de compte, Sign in with Apple et Google via le navigateur système.
- Accès local sans compte pour les fichiers personnels.
- Import multiple depuis Fichiers, récupération des titres, artistes, durées et pochettes intégrées via AVFoundation.
- Bibliothèques séparées par compte, playlists locales, ajout/retrait/renommage/suppression, favoris.
- Recherche locale par titre ou artiste, filtres favoris et fichiers disponibles sur l’iPhone.
- Lecteur plein écran, mini-lecteur, file d’attente, aléatoire, répétition et minuterie.
- AVPlayer, session audio en arrière-plan, commandes de l’écran verrouillé, AirPlay et volume système.
- Gestion des interruptions et pause lors du retrait des écouteurs.
- Téléchargement des fichiers personnels du serveur avec URLSession en arrière-plan, progression, annulation et nouvelle tentative.
- Préférence Wi-Fi pour les prochains téléchargements et indicateur d’espace audio utilisé.
- Sauvegarde volontaire d’un fichier personnel sur son compte depuis le menu du titre ; MP3, M4A, WAV et FLAC, maximum 50 Mo par fichier.
- Actualisation des fichiers du compte depuis Bibliothèque. Les playlists, favoris et statistiques restent locaux dans cette version.
- Suppression du compte depuis les réglages, révocation Apple et effacement de sa bibliothèque locale.
- Animations SwiftUI, retours haptiques, labels d’accessibilité et prise en compte de Réduire les animations pour les effets décoratifs.

Les fichiers importés sont copiés dans Application Support. L’écoute locale ne dépend donc pas d’un serveur ou d’une URL de fichier temporaire. L’app ne diffuse pas les flux YouTube/Spotify de la version historique et ne propose pas leur téléchargement. Un catalogue commercial demanderait une source autorisée, ses licences et éventuellement un mécanisme DRM distinct.

## Ouvrir sur Mac

1. Copier ce dépôt sur le Mac et ouvrir **`ios/NeonWave.xcodeproj`**.
2. Choisir le schéma **NeonWave**, un simulateur iPhone installé, puis Run.
3. Sur l’écran d’accueil, choisir **Commencer sur cet iPhone**. Importer des fichiers audio personnels via Bibliothèque → Importer. Le mode local ne nécessite pas de serveur.
4. Pour un iPhone réel, sélectionner l’équipe Apple dans Signing & Capabilities et utiliser un identifiant de bundle dont vous êtes propriétaire. Activer Sign in with Apple pour cet identifiant.
5. Exécuter Product → Test pour les tests de bibliothèque ; tester ensuite les parcours manuels de `RELEASE-CHECKLIST.md`.

Le projet cible iOS 17 minimum. Pour distribuer, utiliser une version de Xcode et du SDK iOS acceptée par App Store Connect à la date de soumission.

## Connecter le service de comptes

Le serveur Express du dépôt expose les comptes existants et les nouvelles routes `/api/ios/*`. Le serveur peut être déployé indépendamment de l’application PC. Le worker Cloudflare dans `functions/` **n’a pas été adapté à ces nouvelles routes** : pointer l’app vers le service Express, pas vers ce worker.

Créer `ios/Local.xcconfig` (ignoré par Git) :

```xcconfig
DEVELOPMENT_TEAM = VOTRE_EQUIPE_APPLE
PRODUCT_BUNDLE_IDENTIFIER = votre.identifiant.neonwave
NEONWAVE_API_URL = https:/$()/votre-api.fr
NEONWAVE_PRIVACY_URL = https:/$()/votre-site.fr/confidentialite
NEONWAVE_SUPPORT_URL = https:/$()/votre-site.fr/assistance
```

L’app impose HTTPS. Ne pas ajouter d’exception globale ATS. Ne jamais mettre une clé privée, un secret Google ou le secret JWT dans le projet iOS.

Côté serveur : configurer les variables de `.env.example`, installer les dépendances et lancer `npm run server` derrière un proxy HTTPS. Initialiser le compte propriétaire avant d’ouvrir les inscriptions. Les comptes créés dans l’app sont des comptes USER. Le compte OWNER du service doit transférer la propriété via l’administration avant suppression ; ne pas utiliser ce compte d’exploitation comme compte utilisateur ou compte de démonstration App Review.

### Google

Créer un client OAuth de type **Application Web** dans Google Cloud (le code est échangé côté serveur), renseigner son écran de consentement et enregistrer exactement :

```text
https://votre-api.fr/api/ios/auth/google/callback
```

Définir `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` et `GOOGLE_IOS_REDIRECT_URI` sur le serveur. Le client utilise ASWebAuthenticationSession, un état aléatoire, une preuve PKCE et un ticket à usage unique de 60 secondes. Aucun jeton de session n’est placé dans le lien `neonwave://auth`.

Les adresses e-mail identiques ne fusionnent pas automatiquement un compte Google et un compte à mot de passe. L’utilisateur doit utiliser sa méthode de connexion existante.

### Apple

Activer Sign in with Apple sur l’App ID et créer une clé Apple correspondante. Définir sur le serveur :

- `APPLE_CLIENT_ID` : identifiant exact du bundle de l’app.
- `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` : informations de l’équipe et clé privée PEM.
- `APPLE_TOKEN_ENCRYPTION_KEY` : 32 octets aléatoires, encodés en 64 caractères hexadécimaux. Garder cette clé stable et sauvegardée pour pouvoir révoquer les connexions lors d’une suppression.

Le serveur vérifie la signature Apple, l’émetteur, l’audience, l’expiration et le nonce. Il échange aussi le code d’autorisation, chiffre le refresh token avec AES-256-GCM et le révoque lors de la suppression du compte. L’identifiant Apple `sub` est l’identité de référence, y compris avec Masquer mon adresse e-mail.

Les demandes de connexion en cours sont conservées en mémoire côté serveur. Un redémarrage exige de recommencer la connexion. Pour plusieurs instances, remplacer ces tables par un stockage partagé avec TTL avant déploiement.

## Vérification

À la racine :

```sh
npm test
```

Les tests serveur couvrent le premier lancement, les mots de passe, les fichiers personnels, les playlists et sept scénarios iOS : fournisseurs non configurés, Google avec PKCE et anti-rejeu, refus des associations par simple e-mail, expiration et inscriptions fermées, isolation de bibliothèque, suppression de compte, validation/révocation Apple. Les fournisseurs sont simulés : les vrais parcours Google/Apple doivent encore être testés avec les identifiants de production.

Dans Xcode : Product → Test. Les tests Swift couvrent les playlists, l’isolation des comptes, la persistance et l’existence effective des fichiers hors connexion. Ils sont fournis mais n’ont pas été exécutés sous Windows.

Les scripts `tools/generate-project.js` et `tools/render-icon.py` permettent de régénérer le projet et l’icône. Ils ne sont pas nécessaires pour ouvrir le projet livré. `tools/validate-project.py` effectue une validation structurelle, sans remplacer `xcodebuild` ; il attend `tree-sitter`, `tree-sitter-swift` et `openstep-parser` dans `scratch/ios-validation` à la racine du dépôt.

## Distribution

Le build Release bloque volontairement les URLs `.example` et l’absence d’équipe Apple. Après configuration et validation sur iPhone : Product → Archive → Distribute App → App Store Connect → TestFlight. Préparer les captures réelles, les coordonnées d’assistance, la politique de confidentialité, les réponses App Privacy et un compte de test pour Apple. Réviser le manifeste `PrivacyInfo.xcprivacy` selon l’hébergement et les services effectivement déployés.
