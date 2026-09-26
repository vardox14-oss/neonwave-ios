# Ouvrir la vraie app iOS dans un navigateur Windows

Le workflow `.github/workflows/ios-simulator.yml` compile **les sources SwiftUI de ce dossier** sur un Mac GitHub Actions. Il ne lance pas l’interface web du dépôt et ne génère pas une imitation HTML.

Il produit :

- `NeonWave-iOS-Simulator.zip` : le paquet `.app` pour Appetize ;
- `NeonWave-iPhone.png` : une capture de l’application exécutée dans le simulateur Apple ;
- les journaux de compilation et les résultats des tests XCTest.

## Parcours

1. Envoyer le dossier `ios/` et le workflow dans le dépôt GitHub choisi. Les secrets serveur et les données des comptes ne sont pas nécessaires.
2. Dans **Actions → iPhone simulator for Appetize**, lancer **Run workflow**. Le workflow se lance aussi lors d’un push sur la branche `codex/ios-browser-preview`.
3. Attendre la compilation. Si elle échoue, corriger les erreurs Xcode avant de poursuivre : la validation de syntaxe faite sur Windows ne remplace pas cette étape.
4. Télécharger l’artefact **NeonWave-iOS-Simulator**. Décompresser cet artefact GitHub pour récupérer le fichier **NeonWave-iOS-Simulator.zip** qu’il contient.
5. Se connecter sur [Appetize](https://appetize.io), créer une application iOS et envoyer **ce ZIP intérieur**, pas le ZIP global contenant les journaux.
6. Ouvrir la session Appetize : l’iPhone simulé exécute alors la vraie application native.

Cette compilation pour simulateur n’exige pas de certificat Apple ni d’abonnement Apple Developer. Un compte Appetize et du temps de session disponible sont nécessaires. Aucun abonnement payant n’est souscrit par le workflow.

## Ce qui est testable avec la configuration actuelle

Le mode **Commencer sur cet iPhone** permet de parcourir l’app sans serveur. Pour l’audio, il faut importer des fichiers dans le simulateur selon les fonctions de transfert proposées par Appetize. La session cloud peut être réinitialisée : ce n’est pas un stockage permanent de musique.

Les connexions Apple/Google et les fonctions du compte nécessitent un backend HTTPS accessible depuis le cloud et configuré. `localhost:5005` sur le PC Windows n’est pas accessible au simulateur cloud. Le workflow n’expose pas ce serveur et n’envoie aucune donnée personnelle.

La validation écran verrouillé, Bluetooth/AirPlay, mode avion et téléchargements en arrière-plan doit ensuite se faire sur un vrai iPhone.

Références : [format iOS Appetize](https://docs.appetize.io/platform/app-management/uploading-apps/ios), [Macs GitHub Actions](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
