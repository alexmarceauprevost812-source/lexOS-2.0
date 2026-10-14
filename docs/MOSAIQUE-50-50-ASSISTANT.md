# LexOS Pro RTX5060 V2.0.2 — fenêtres 50/50 avec la souris

## Ce que l'utilisateur a demandé

« Placer une fenêtre à gauche de l'écran (50 %), puis choisir dans une
liste la seconde fenêtre qui occupera les 50 % restants, sur le même bureau. »

C'est le **Snap Assist** façon Windows, sans changer d'espace de travail.

### Geste

1. Ouvrir deux applications ou deux fenêtres, par exemple Thunar et Firefox.
2. Saisir la barre de titre de Thunar et **glisser au bord gauche** de l'écran.
3. XFWM4 place Thunar sur la moitié gauche (sa propriété
   `/general/tile_on_move=true` figure déjà dans la configuration LexOS).
4. Au relâchement, après stabilisation de la géométrie, **LexOS affiche
   les autres fenêtres du même bureau** dans un panneau sur la moitié droite.
5. Cliquer sur Firefox → il remplit la moitié droite. Les deux fenêtres
   restent côte à côte, environ 50/50. Échap ou « ✕ » annule le choix.

Le panneau n'apparaît pas quand aucune autre fenêtre admissible n'est
ouverte. Ce geste ne crée pas de nouveau bureau virtuel et ne change pas
le compositeur picom/CRT. Les raccourcis Ctrl+Super+Gauche/Droite de la
PR #6 continuent de fonctionner indépendamment du geste souris.

### Activation et désactivation

Dans LexOS **une fois la prochaine ISO installée** :

```bash
lexos mosaique status    # état de l'assistant
lexos mosaique on        # activer le sélecteur + l'ancrage natif xfwm4
lexos mosaique off       # désactiver le sélecteur uniquement
```

Le réglage de l'assistant est stocké par compte sous
`~/.config/lexos/assistant-mosaique`. « off » ne désactive pas le
placement natif XFWM4 et ne change pas les raccourcis. Le veilleur
tourne sans privilèges administrateur et quitte dès que l'utilisateur
le désactive. Un verrou de processus évite les doublons.

L'entrée XDG `/etc/xdg/autostart/lexos-assistant-mosaique.desktop`
démarre le veilleur pour les **comptes existants et nouveaux**
dans XFCE, sauf désactivation. Pas besoin de migrer `/etc/skel`
à chaque utilisateur. Les anciennes préférences XFCE ne sont pas
réécrites silencieusement à chaque connexion.

### Architecture et limites

- **Placement natif gauche :** xfwm4. LexOS n'intercepte pas les
  événements de souris en exclusivité et ne remplace pas XFWM4.
- **Surveillance :** python3-xlib ; détecte le bouton gauche près
  du bord gauche, attend le relâchement ET une fenêtre de largeur
  moitié/hauteur utilisable. Ignore les fenêtres déjà ancrées au
  démarrage sans nouveau geste.
- **Choix :** GTK3, fenêtre temporaire sur la moitié droite avec
  les titres des fenêtres de type normal du **bureau courant**.
  Une fenêtre fermée pendant l'affichage est simplement ignorée.
- **Déplacement :** messages EWMH `_NET_WM_STATE`,
  `_NET_ACTIVE_WINDOW` et `_NET_MOVERESIZE_WINDOW` vers xfwm4.
  Aucun raccourci clavier synthétique ni reconfiguration de Xorg.
- **Écrans multiples :** calcul du moniteur source et de sa surface
  de travail (`Gdk.Monitor.get_workarea`), non de la résolution totale.
  Les panneaux et le dock qui réservent de l'espace sont respectés.
- **Application qui refuse le redimensionnement :** XFWM4 reste
  arbitre et peut imposer sa taille minimale; on ne promet pas
  50/50 pixel parfait pour les fenêtres non redimensionnables.
- **X11 seulement :** sur Wayland, le veilleur ne s'exécute pas.
- **Sécurité :** aucune modification EFI, GRUB, Windows, pilote NVIDIA,
  picom, paramètres globaux de fenêtres ou privilège root.
  Le programme offre une désactivation et se ferme en session non X11.

### Prérequis de l'ISO

`python3-xlib` figure déjà dans `lexos-core.list.chroot`.
`python3-gi` et `gir1.2-gtk-3.0` sont ajoutés à la liste graphique
obligatoire `flavours/standard/desktop.list.chroot`.
Le script Python est sous `/usr/lib/lexos/assistant-mosaique.py`,
appelé par son interpréteur, sans dépendre d'un bit exécutable.

### Vérifications avant publication

Banc automatisé : `python3 tests/test_lexos_202_snap_assist.py`.
Il vérifie séparation exacte des écrans impairs, moniteur secondaire,
marges/panneaux, exclusion des autres espaces de travail, geste souris,
temporisation, refus d'ouverture au démarrage, désactivation et
intégration CLI/autostart. Aucune fenêtre réelle n'est déplacée en CI.

**Validation graphique réelle encore nécessaire** sur XFCE 4.20 :
- glisser une fenêtre ouverte au bord gauche : choix affiché sur la
  partie droite uniquement, choisir la seconde; vérifier la taille.
- fermer la première ou la seconde avant de choisir : aucune erreur.
- déplacer une fenêtre déjà partiellement redimensionnée : ne pas
  afficher le panneau par erreur.
- deux écrans, panneaux en haut, Plank, fenêtre maximisée ou réduite,
  Firefox et Thunar, applications avec taille minimale.
- quatre espaces de travail : les fenêtres du bureau voisin ne sont
  pas proposées, raccourcis mosaïque conservés.
- `lexos mosaique off` → panneau absent, fermeture propre du veilleur;
  `on` → retour. Tester reconnexion et utilisateur existant.
- picom CRT en marche : animation et composites inchangés.

**Ne pas déclarer cet assistant validé sur matériel avant ces essais.**
Aucune ISO nouvelle ni mise à jour installée sur le poste par ce commit.
