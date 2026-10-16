# REA Studio — atelier de projets Linux

REA Studio est disponible dans le menu Développement et via `rea-studio`.
La version 0.2.0 crée des applications Python/Tkinter ou HTML avec Ollama local ou Codex en ligne. Elle fournit un aperçu, des versions sans écrasement, le lancement explicite et un terminal utilisateur, ainsi que projets, notes et outils configurables.
Le lanceur porte le visage orange choisi par l’utilisateur.

La documentation, les sources et les tests sont dans
[config/includes.chroot/usr/share/lexos/rea-studio](../config/includes.chroot/usr/share/lexos/rea-studio/README.md).
L’application est aussi installable séparément par `python3 install.py` depuis
une copie extraite de ce dossier. `python3-tk` est requis dans les saveurs de bureau.

REA n’a pas été identifié dans les sources examinées : aucune API REA n’est
supposée. `lexos-studio` conserve son fonctionnement. MARCEAU Android est distinct.
L’intégration ISO doit encore être construite et essayée sur le système cible.
