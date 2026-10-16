# Validation — 16 octobre 2026

Version 0.1.0, Python 3.13, Tk 8.6, Linux ; écran virtuel TigerVNC 1280×900
sans port réseau, socket Unix local protégé. Un serveur HTTP simulant Ollama
écoutait seulement sur 127.0.0.1. Aucun modèle réel n’a été exécuté.

Résultat : **19 tests réussis, 0 ignoré, 0 échec**.

- Projets : création/import sans doublon, renommage, retrait conservant les
  fichiers, refus des chemins invalides et des dossiers existants.
- Stockage : registre corrompu conservé, écritures atomiques, échec de remplacement
  conservant l’original, refus des liens de notes sortant du projet.
- Outils : arguments passés littéralement, dossier de travail correct, absence
  d’exécutable et de terminal signalée ; aucun shell ajouté par l’application.
- Ollama : véritable échange HTTP avec le faux serveur, payload officiel,
  modèles, erreurs 404, JSON et schéma invalides, refus d’hôtes distants et de
  redirections, serveur indisponible.
- Fenêtre : création et sélection de projets, notes enregistrées/rechargées,
  annulation d’un changement avec notes non enregistrées, ouverture de la
  configuration ; réponse IA asynchrone et conservation du nouveau brouillon ;
  erreur IA sans perte du message et réactivation des commandes.
- Installation : préfixe avec espaces et dollar, seconde installation,
  conservation d’un lanceur existant non géré, lancement installé `--version`.
- `shellcheck rea-studio`, validation `.desktop` et compilation de tous les
  modules Python : succès.
- PNG : RGBA 1254×1254, canal alpha de 0 à 255 ; icône issue du visage validé
  par l’utilisateur. Aperçu de fenêtre réalisé sur un projet exemple temporaire.

Limites : aucune construction ISO, aucun démarrage d’une ISO LexOS, aucun test
sur le matériel utilisateur et aucune génération avec un vrai modèle Ollama.
Les outils tiers peuvent avoir leur propre interface, configuration ou erreurs.
Le support d’un outil REA spécifique attend son identification.
