# Vérification avant TestFlight et App Store

Cette liste décrit les validations **encore à réaliser sur Mac/iPhone**. Elle ne constitue pas une déclaration de tests déjà réussis.

## Construction et configuration

- Ouvrir le projet, compiler Debug puis Release avec une version de Xcode acceptée par Apple.
- Exécuter NeonWaveTests sur simulateur et corriger tous les avertissements pertinents.
- Renseigner le bundle ID, l’équipe, les trois URLs HTTPS et la capacité Sign in with Apple.
- Vérifier l’icône, l’écran de lancement, le nom et la version dans l’archive.
- Héberger le serveur Express et vérifier les routes iOS ; ne pas pointer vers le worker Cloudflare historique.
- Appliquer les réglages d’exploitation au serveur : origin CORS autorisée, proxy HTTPS, persistance et sauvegardes privées. Vérifier que l’assistant propriétaire n’est pas accessible au public avant initialisation.
- Pour plusieurs processus, externaliser les états OAuth et tickets vers un stockage partagé avec TTL.

## Connexion et confidentialité

- Premier lancement sans compte, inscription et reconnexion par e-mail ; mots de passe incorrects et réseau coupé.
- Google : réussite, annulation, retour depuis le navigateur système, compte existant et session expirée.
- Apple : première connexion, reconnexion, Masquer mon adresse e-mail, annulation, nonce expiré.
- Vérifier que les boutons sociaux sont actifs une fois les fournisseurs configurés.
- Déconnexion puis reconnexion au même compte : bibliothèque préservée. Connexion à un autre compte : aucune fuite de bibliothèque.
- Suppression d’un compte USER : révocation Apple, compte et fichiers du serveur supprimés, bibliothèque locale effacée, ancien token refusé sur les routes iOS.
- Vérifier les journaux, la sauvegarde `.bak`, et la politique de conservation des sauvegardes externes : aucune rétention indéfinie d’un compte supprimé.
- Vérifier les liens de confidentialité/assistance et aligner App Privacy avec la collecte réelle du serveur.

## Audio et stockage

- Importer de vrais MP3, M4A, WAV et FLAC, avec et sans pochettes, et un fichier invalide.
- Lire une playlist en mode avion après fermeture et réouverture de l’app.
- Verrouiller l’écran et écouter au moins 20 minutes ; commandes lecture/pause/suivant/précédent et déplacement dans le titre depuis l’écran verrouillé.
- Interruption par appel ou Siri, retrait des écouteurs, changement Bluetooth et AirPlay.
- File d’attente, fin de playlist, aléatoire, répétition d’un titre/tous et minuterie.
- Sauvegarder volontairement un fichier dans le compte, le retrouver sur un second iPhone, le télécharger, couper le réseau et le lire.
- Télécharger une playlist personnelle complète, suspendre l’app, perdre le réseau, relancer l’app, annuler et réessayer.
- Vérifier Wi-Fi uniquement, erreurs de session et stockage insuffisant.
- Supprimer un téléchargement récupérable puis le récupérer à nouveau ; confirmer avant suppression d’un original local.
- Inspecter la consommation mémoire avec un gros fichier et plusieurs imports simultanés.

## Interface

- Petit iPhone et grand iPhone, clavier ouvert, noms longs, bibliothèque vide et centaines de titres.
- Dynamic Type aux grandes tailles, VoiceOver, Réduire les animations et contrastes.
- Vérifier chaque navigation, feuille modale et mini-lecteur ; ne pas se limiter aux captures de l’accueil.
- Capturer des écrans réels pour la fiche App Store après ces vérifications.

## Soumission

- Fournir un compte USER de démonstration et des fichiers audio de test dont les droits sont maîtrisés.
- Expliquer l’import depuis Fichiers, le stockage local et le téléchargement des fichiers personnels dans les notes App Review.
- Ne pas annoncer un catalogue Spotify/YouTube, une synchronisation de playlists entre appareils ou une lecture DRM qui ne sont pas implémentés ici.
- Faire tester via TestFlight avant la soumission publique. Vérifier les exigences Apple en vigueur au moment de l’envoi.
