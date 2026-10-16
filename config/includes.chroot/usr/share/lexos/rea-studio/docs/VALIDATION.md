# Validation — 16 octobre 2026

Version 0.2.0, Python 3.13, Tk 8.6, Linux XFCE.

**32 tests réussis, 0 ignoré, 0 échec**, sur écran virtuel TigerVNC sans port TCP.
Les tests couvrent les projets et notes, les écritures atomiques, les chemins et
liens symboliques, les limites de génération, la syntaxe Python, la réparation
bornée d’une réponse invalide, les versions sans écrasement, le chargement des
fichiers modifiés, le contrat HTTP Ollama, la commande Codex en lecture seule,
les échanges en arrière-plan, les erreurs, le terminal et l’installation utilisateur.
La réouverture du dernier projet et de sa dernière version est vérifiée.

Deux générations réelles ont été réalisées sur ce poste :
- Ollama local, qwen2.5-coder:7b : environ 17 secondes.
- Codex CLI 0.162.1, connexion ChatGPT existante : environ 26 secondes.

Chacune a produit une application Tkinter de tâches et son README. Le code a été
lu avant exécution. Les deux fenêtres ont été ouvertes, puis leurs actions
ajouter, terminer et supprimer ont été testées avec succès. Aucun accès système
ni réseau n’existe dans ces deux programmes exemples.
L’interface REA Studio a été contrôlée à 1120×820 et 900×700 ; les boutons de
création et lancement restent visibles. Les modèles locaux sont détectés sur
le serveur réellement installé. Shellcheck et validation desktop passent.

Limites : aucune construction ni démarrage d’ISO LexOS ; les applications générées
par d’autres demandes ne sont pas garanties par ces tests. Aucune API REA inventée.
La suite automatisée utilise des moteurs simulés et ne nécessite aucun compte IA.
