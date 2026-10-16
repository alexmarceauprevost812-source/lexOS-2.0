# REA Studio 0.1.0 — LexOS Pro

Application Linux de bureau pour créer et retrouver des projets, enregistrer des
notes, discuter avec Ollama local et lancer des outils installés. Interface noire
et orange, icône encapuchonnée choisie par l’utilisateur, fenêtre redimensionnable.

## Installation sur LexOS / Debian / Ubuntu / XFCE

Prérequis (une fois, si Tkinter manque) :

```bash
sudo apt update
sudo apt install python3 python3-tk
```

Depuis ce dossier extrait :

```bash
python3 install.py
```

Ouvrir ensuite **Applications → Développement → REA Studio**.
Le lanceur utilise le visage orange. Le menu peut nécessiter une réouverture.
Il n’est pas nécessaire d’ajouter un dossier au PATH. L’application peut aussi
être démarrée directement, sans installation :

```bash
./rea-studio
```

L’installation copie le programme dans `~/.local/share/rea-studio`, crée le lien
`~/.local/bin/rea-studio` et le menu `$XDG_DATA_HOME/applications/rea-studio.desktop`
(par défaut `~/.local/share/applications`). Elle ne télécharge rien, n’exige pas
sudo et ne modifie aucun fichier système. Relancer l’installateur met à jour le
code applicatif ; les projets et réglages sont conservés. Les sources doivent
être dans un autre dossier que la destination installée.

Pour placer aussi le lanceur sur le bureau XFCE, utiliser le menu Applications,
puis clic droit sur **REA Studio → Ajouter au bureau**. Selon la configuration
XFCE, autoriser ensuite l’exécution du lanceur au premier clic.

## Utilisation

1. **Nouveau projet** : choisir un dossier parent puis un nom de nouveau dossier.
   Un dossier existant ne sera jamais remplacé.
2. **Importer un dossier** : référencer un dossier existant sans déplacer son contenu.
3. Écrire dans **Notes du projet**, puis **Enregistrer** ou **Ctrl+S**.
4. **Renommer** change uniquement le nom affiché ; **Retirer de la liste** conserve
   le dossier et les notes. Un changement de projet propose de sauvegarder les notes.
5. **IA locale** : détecter les modèles puis envoyer un message, avec le bouton ou
   **Ctrl+Entrée**. Les messages sont conservés en mémoire par projet pendant cette
   session ; **Exporter** les enregistre en Markdown. Fermer l’application perd
   les discussions non exportées. Les brouillons saisis pendant une réponse sont conservés.
6. **Outils REA** : choisir un outil puis **Lancer**. La commande et le dossier
   sont affichés avant le lancement. Les outils restent soumis aux droits de votre
   session Linux. Leur état d’exécution interne n’est pas supervisé par REA Studio.

## Ollama

Ollama et au moins un modèle doivent être installés séparément. Voir la
[documentation officielle](https://docs.ollama.com/quickstart).
Si le serveur n’est pas déjà actif :

```bash
ollama serve
```

Lister les modèles installés avec `ollama list`, puis utiliser **Détecter les modèles**.
Un modèle peut être téléchargé séparément avec `ollama pull NOM_DU_MODELE` ;
son choix dépend de la mémoire et du matériel. REA Studio ne télécharge aucun modèle.

Adresse initiale : `http://127.0.0.1:11434`. Le bouton **Connexion** permet de
changer le port local. Seules les adresses HTTP de boucle locale sont acceptées ;
les proxys système et les redirections sont désactivés. L’application utilise
`GET /api/tags` et `POST /api/chat` avec `stream: false`, conformément à la
[documentation des modèles](https://docs.ollama.com/api/tags) et du
[chat](https://docs.ollama.com/api/chat).

Seuls les messages saisis et l’historique de la discussion courante sont envoyés.
Les notes et fichiers de projet ne sont pas lus par l’IA. Aucune réponse ne déclenche
de commande ou d’écriture automatique. Utiliser des modèles locaux : la politique
d’un éventuel modèle cloud configuré dans Ollama relève du serveur Ollama.

## Extensions REA

**La signification exacte de REA reste à confirmer.** L’examen du dépôt LexOS et
la conversation fournie n’ont révélé aucune API REA documentée. Aucun endpoint,
SDK ni exécutable fictif n’a été ajouté. Le nom de l’application suit la demande.
Voir [l’enquête](docs/CONTEXTE.md).

**Configurer** ouvre une liste JSON d’outils utilisateur. Exemple de schéma :

```json
[
  {
    "name": "Mon outil REA installé",
    "argv": ["/chemin/absolu/vers/mon-outil", "{project}"],
    "terminal": false
  }
]
```

Remplacer ce chemin par un véritable programme avant utilisation. Chaque élément
`argv` est un argument distinct. `{project}` est remplacé par le dossier sélectionné.
Les pipelines, `&&`, `$()` et les redirections ne sont pas interprétés par REA
Studio. Ne pas ajouter de shell (`bash -c`, etc.) sauf si vous comprenez la commande.
Les outils nécessitant une interaction texte peuvent utiliser `terminal: true`
avec `xfce4-terminal` installé. Aucun plugin Python ni configuration du dossier
importé n’est chargé automatiquement. Studio+ existant reste accessible sous
son nom `lexos-studio`, sans être remplacé.

## Données et désinstallation

- Registre : `$XDG_DATA_HOME/rea-studio/projects.json`.
- Notes : `.rea-studio/notes.md` dans chaque dossier de projet.
- Réglages et outils : `$XDG_CONFIG_HOME/rea-studio/`.
- Valeurs XDG par défaut : `~/.local/share` et `~/.config`.
- En cas de JSON corrompu : fichier conservé, erreur explicite. Sauvegarder le
  fichier avant de le réparer. Aucun effacement ni réinitialisation silencieuse.

Pour désinstaller, retirer uniquement le lien `~/.local/bin/rea-studio`, le menu
`~/.local/share/applications/rea-studio.desktop` (ou son équivalent XDG) et les
fichiers applicatifs `rea_studio/`, `assets/`, `rea-studio` sous
`~/.local/share/rea-studio`. **Conserver `projects.json` et les dossiers de projets**
si vous souhaitez garder vos données. Aucun désinstalleur destructif automatique.

## Tests

Depuis ce dossier :

```bash
sudo apt install python3-tk xvfb desktop-file-utils shellcheck
xvfb-run -a python3 -m unittest discover -s tests -v
shellcheck rea-studio
desktop-file-validate assets/rea-studio.desktop
```

Le faux serveur HTTP de test écoute uniquement sur la boucle locale. Aucun modèle,
compte ni serveur Ollama réel n’est nécessaire. Sans écran, les tests GUI sont
ignorés : employer `xvfb-run` pour les exécuter. Voir [VALIDATION.md](docs/VALIDATION.md).

Cette version est un atelier initial utilisable. Elle n’est pas un IDE complet,
ne construit pas d’APK et ne modifie pas MARCEAU Android. Son intégration dans
l’ISO LexOS reste à vérifier par une construction et un démarrage de l’ISO cible.

Code original REA Studio sous MIT, voir [LICENSE](LICENSE).
L’icône dérivée de l’image utilisateur est réservée à ce projet ; elle ne concède
pas de droits sur l’identité TI-LEX-AL ou sur l’image source.
