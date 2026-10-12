# LexOS Pro RTX5060 — correction OpenGL et effets (12 octobre 2026)

> **Préparation pour la prochaine ISO Pro. Pas une release.**
> Garder la PR brouillon #6, la release 2.0.1 et GRUB Windows/Linux.
> Les effets expérimentaux ci-dessous ne sont PAS encore implémentés.

## Correction NVIDIA confirmée sur le PC LexOS

- RTX 5060, NVIDIA 615.71.09, XFCE/X11 : `nvidia-smi` fonctionnait,
  mais Xorg utilisait `modesetting`, GLX le fournisseur `DRISWRAST`
  et Mesa `llvmpipe`. Picom plantait sur `GLX_EXT_texture_from_pixmap`.
- Il manquait `nvidia-driver-libs` et `xserver-xorg-video-nvidia`.
- Installation des bibliothèques NVIDIA : 39 nouveaux paquets, zéro suppression.
  Installation du pilote Xorg et ses dépendances : trois nouveaux paquets,
  zéro suppression. Tous en 615.71.09-2.
- Nouvelle session X11 : `glxinfo -B` montre
  `NVIDIA Corporation` / `GeForce RTX 5060`;
  `xrandr --listproviders` montre `NVIDIA-0`.
- `lexos crt status` confirme picom v12 et l'accélération 3D réelle,
  avec effets demandés et moteur en marche.

**Correctif ISO :** `0260-lexos-nvidia.hook.chroot` installe désormais
`nvidia-driver-libs`, `xserver-xorg-video-nvidia` et `nvidia-driver`
à la **version réelle** du pilote retenu, avec `--no-remove`.
Le hook vérifie `libglx-nvidia0`, les versions et `nvidia_drv.so`.
Il arrête le build Pro si la pile Xorg/GLX est incohérente.
Aucun numéro 615 figé : les branches NVIDIA peuvent évoluer.
Ce test du chroot ne remplace pas un test sur RTX 5060 réelle.

## Sept effets demandés : faisabilité réelle

| Effet | Picom 12.5 + XFCE 4.20 | État de la prochaine ISO |
|---|---|---|
| 📺 CRT vieille TV | Oui : scale-y → scale-x → opacity à la fermeture | **Existant, picom actif sur RTX 5060** |
| 👾 Hologramme | Approximation par opacité, zoom, translation, couleur; pas de projection 3D | À prototyper, non livré |
| ⚡ Glitch | Bandes RGB/distorsion de pixels : non disponible via les animations déclaratives picom; rendu supplémentaire nécessaire | Recherche séparée, désactivé |
| 🟠 Néon | Ombres colorées et fenêtre active différenciée; vrai halo/contour nécessite développement supplémentaire | À prototyper |
| 🌀 Portail | Zoom et réduction au centre possibles; cibler l'icône Plank exige sa position dynamique | À prototyper sans promettre le dock |
| 💻 Démarrage rétro | Possible par animation courte après ouverture de session XFCE, distincte du moteur picom | À développer, sans modifier EFI/GRUB |
| 🪟 Fenêtres fluides | Oui : transitions opacity/scale/offset courtes | À prototyper |

### Architecture sûre et désactivable

- **Un seul compositeur.** Garder xfwm4 comme gestionnaire de fenêtres.
  Picom remplace son compositeur seulement avec OpenGL réellement accéléré.
  Ne jamais lancer Compiz et picom ensemble.
- **Conserver le profil CRT fonctionnel** comme référence. Les profils
  `Hologramme`, `Fluide` et `Portail` concernent parfois les mêmes événements
  `open` et `close` : éviter leur superposition automatique.
- Prévoir dans une étape ultérieure des interrupteurs indépendants
  par compte, sauvegarde de configuration, réglages de durée et profil
  « mouvement réduit ». Ne pas ajouter de boutons fictifs.
- Un seul geste d'urgence pour désactiver le compositeur :
  `lexos crt off`, et restauration automatique du compositeur xfwm4
  quand picom quitte. Garder la possibilité d'ouvrir une session XFCE.
- Exclure les mots de passe, menus fréquents, jeux et vidéos plein écran
  des effets intrusifs. Privilégier animations brèves et légères.
- Le démarrage rétro doit rester **dans la session utilisateur**;
  ne pas changer le chargeur GRUB, les partitions, LightDM, ou le Secure Boot.
- Le glitch nécessitant des shaders ou un autre moteur est **optionnel**.
  Pas de remplacement de gestionnaire de fenêtres pour cet effet seul.

### Ordre recommandé

1. Correctif de la pile OpenGL/Xorg (commité) + tests.
2. Préserver CRT existant et corriger plus tard les avertissements
   `shadow-exclude`/`rules`, sans changer le comportement fonctionnel.
3. Tester les prototypes **Fenêtres fluides**, **Hologramme** et **Néon**,
   chacun activable/désactivable.
4. Tester **Portail** sans ancrage au dock, puis évaluer Plank.
5. Développer **Démarrage rétro** non bloquant après session XFCE.
6. Garder **Glitch** en recherche jusqu'à démonstration graphique fiable.

### Tests et critères d'acceptation

- CI : `sh -n`, simulations du hook NVIDIA avec fausses commandes apt et
  dpkg, vérification qu'une pile incomplète arrête la construction;
  `tests/test_lexos_202_nvidia_glx.sh`.
- Tests XFCE : `lexos crt on/off/status`, sauvegarde/retour xfwm4
  si picom meurt, aucune collision de raccourcis mosaïque ou de dock.
- Machine RTX 5060 : `glxinfo -B`, `xrandr --listproviders`,
  `nvidia-smi`, fermeture/réouverture de Thunar et Chrome répétées,
  `~/.config/lexos/crt.log`, fluidité en plein écran et HDMI.
- Construction ISO Pro : vérifier BIOS/UEFI, Secure Boot actif,
  module NVIDIA chargeable (MOK), menu Linux/Windows **de test**,
  mode de secours et branche de pilote réellement embarquée.
- CI sans GPU et Xvfb peuvent vérifier structure/interface;
  **ils ne prouvent pas une accélération GPU réelle**.

### Commandes qui existent actuellement

```bash
lexos crt status
lexos crt on
lexos crt off
```

Les commandes `lexos effets hologramme`, `lexos effets glitch`, etc.
**n'existent pas encore**; ne pas les documenter comme opérationnelles
avant implémentation et tests.

Voir [la procédure ISO 2.0.2](LEXOS-PRO-RTX5060-2.0.2.md)
et [la PR #6](https://github.com/alexmarceauprevost812-source/lexOS-2.0/pull/6).
