# LexOS Pro 2.0.2 — vues de fichiers et aperçu des images

## Demande

Quand on sélectionne une photo, pouvoir la voir EN GRAND sans avoir à
se souvenir du nom du fichier; pouvoir choisir entre une liste et des
icônes, à la manière de Windows.

La capture d'origine montre le dialogue « Sélectionner des fichiers »,
probablement ouvert par un navigateur. **Ce dialogue n'est pas Thunar.**
Les réglages suivants changent le gestionnaire Fichiers (Thunar 4.20)
et les fenêtres Thunar à venir. **Ils ne modifient pas de force le
sélecteur GTK/Chrome/Firefox d'une autre application.** L'interface de
ce sélecteur est décidée par l'application et sa bibliothèque graphique.
Il ne faut surtout pas présenter la fonctionnalité comme « disponible
dans tous les sélecteurs » alors qu'on ne les a pas modifiés.

## Interface LexOS

Dans **Paramètres LexOS → Fichiers et images** :

- Liste détaillée : nom, date, type, taille.
- Icônes normales : grille classique.
- Grandes miniatures : grille plus grande, miniatures des images locales
  et aperçu dans un **panneau séparé à droite**.
- Vue compacte : plusieurs fichiers dans un espace réduit.
- Grand aperçu à droite : activé / désactivé (indépendant de la vue).
- Miniatures : activées / désactivées (fichiers locaux seulement).

Un clic affiche une réponse de réussite ou une erreur réelle. La page
relit le canal XFCONF après modification plutôt que de supposer que
le réglage a marché.

### Source de vérité : XFCONF, pas thunarrc

Thunar 4.20 utilise le **canal XFCONF "thunar"**, après une éventuelle
migration unique de l'ancien fichier \`~/.config/Thunar/thunarrc\`.
Modifier seulement \`thunarrc\` sur le compte actuel aurait l'air
d'avoir marché tout en ne changeant RIEN dans le gestionnaire.

Le moteur \`/usr/lib/lexos/fichiers_vues.py\` écrit avec
\`xfconf-query -c thunar\` les propriétés connues et vérifiées dans
les sources officielles de Thunar 4.20 :

| Propriété | Usage |
| --- | --- |
| \`/last-view\` | \`ThunarDetailsView\`, \`ThunarIconView\`, \`ThunarCompactView\` |
| \`/last-icon-view-zoom-level\` | \`THUNAR_ZOOM_LEVEL_100_PERCENT\` ou \`THUNAR_ZOOM_LEVEL_200_PERCENT\` |
| \`/last-image-preview-visible\` | Booléen : affiche l'aperçu |
| \`/misc-image-preview-mode\` | \`THUNAR_IMAGE_PREVIEW_MODE_STANDALONE\` (à droite) |
| \`/misc-thumbnail-mode\` | \`THUNAR_THUMBNAIL_MODE_ONLY_LOCAL\` ou \`THUNAR_THUMBNAIL_MODE_NEVER\` |

Les modifications restent dans **le compte de l'utilisateur**, sans
sudo, sans altérer les fichiers et sans redémarrer XFCE. Si une fenêtre
de Thunar déjà ouverte ne suit pas le choix, la fermer puis la rouvrir.
Le code restaure les clés déjà modifiées si l'une des étapes échoue.

\`/etc/skel/.config/Thunar/thunarrc\` définit un **défaut pour les
nouveaux comptes**, dont l'aperçu séparé à droite; \`sudo miss a jour\`
n'écrase pas le compte actuel par \`/etc/skel\`, et c'est intentionnel.

## Installation sur LexOS actuel

Vérifier que le clone est bien sur
\`feature/lexos-pro-2.0.2-rtx5060-icons\` :

\`\`\`bash
git -C "$HOME/Projets LexOS/lexOS-2.0" branch --show-current
sudo miss a jour --essai
sudo miss a jour
\`\`\`

Puis ouvrir **Paramètres LexOS → Fichiers et images** et cliquer
« Grandes miniatures ». Il est également possible de le faire directement
depuis le terminal :

\`\`\`bash
lexos vue-fichiers grandes
lexos vue-fichiers etat
thunar "$HOME/Images"
\`\`\`

Revenir au fonctionnement habituel :

\`\`\`bash
lexos vue-fichiers icones
lexos vue-fichiers apercu off
\`\`\`

Autres choix :

\`\`\`bash
lexos vue-fichiers liste
lexos vue-fichiers compact
lexos vue-fichiers apercu on
lexos vue-fichiers miniatures on
lexos vue-fichiers miniatures off
\`\`\`

Les miniatures demandent normalement **Tumbler**. Si elles restent des
icônes génériques, vérifier que le paquet est installé :

\`\`\`bash
dpkg-query -W tumbler
\`\`\`

S'il manque :

\`\`\`bash
sudo apt install tumbler
\`\`\`

**Ne pas faire \`sudo lexos vue-fichiers\`** : cela configurerait le
compte administrateur plutôt que la session graphique de l'utilisateur.

## Contrôles automatisés et vérification réelle

\`\`\`bash
python3 tests/test_lexos_202_fichiers_vues.py
\`\`\`

- Comparaison des propriétés et des valeurs réellement envoyées à XFCONF.
- Quatre modes, panneau de droite et miniatures locales.
- Aucune commande shell générée à partir des données du navigateur.
- Échec partiel : remise des réglages précédents, aucune suppression.
- Refus des modes inconnus, types non texte et absence de dépendances.
- Intégration de l'action et de la page dans les Paramètres LexOS.

**À tester sur le PC :** Fichiers → Images → sélectionner un JPEG/PNG;
aperçu à droite visible, miniatures agrandies, puis repasser en liste.
Fermer/réouvrir Fichiers pour confirmer la persistance. Tester la
fenêtre « Sélectionner des fichiers » du navigateur *séparément* et ne
pas promettre qu'elle ait les mêmes boutons.

La PR reste en brouillon tant que le test graphique n'a pas été réussi.
Aucune nouvelle ISO n'est publiée par cet ajout.

Sources Thunar :
- Debian 13, \`thunar-preferences.c\` : XFCONF / propriétés :
  https://sources.debian.org/src/thunar/4.20.2-1%2Bdeb13u1/thunar/thunar-preferences.c
- Debian 13, \`thunar-window.c\` : panneau image séparé :
  https://sources.debian.org/src/thunar/4.20.2-1%2Bdeb13u1/thunar/thunar-window.c
