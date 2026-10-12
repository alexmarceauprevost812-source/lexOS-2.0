# Pack d'effets animés (essai sur LexOS Pro RTX5060)

**Statut : expérimental, par compte utilisateur.** Les animations simples sont
fournies par picom 12.5 : fluide, hologramme *simulé* (fondu/zoom), néon *simulé*
(ombre orange), portail *vers le centre*. Ce ne sont ni des shaders holographiques
ou RGB glitch ni une réduction précisément vers l'icône Plank. Les effets CRT
existants restent la référence.

Les sources sont sous
`config/includes.chroot/usr/share/lexos/picom/lexos-effets`.
Ce programme n'est pas encore enregistré dans `lexos` et dans l'interface
Paramètres : **il n'est pas annoncé comme opérationnel par défaut dans l'ISO**.
Il s'installe dans le compte utilisateur pour essais, sans sudo ni changement
de pilote, de session, d'UEFI ou de fichiers originaux.

## Installation sur LexOS installé

Exécuter dans une session XFCE/X11 où `lexos crt status` montre picom en
marche et `glxinfo -B` affiche bien NVIDIA :

```bash
mkdir -p "$HOME/.local/bin"
curl -fL --retry 2 \
  "https://raw.githubusercontent.com/alexmarceauprevost812-source/lexOS-2.0/feature/lexos-pro-2.0.2-rtx5060-icons/config/includes.chroot/usr/share/lexos/picom/lexos-effets" \
  -o "$HOME/.local/bin/lexos-effets"
bash -n "$HOME/.local/bin/lexos-effets" &&
chmod 700 "$HOME/.local/bin/lexos-effets" &&
"$HOME/.local/bin/lexos-effets" installer
```

Un fichier téléchargé de GitHub reste du code exécutable : il est bon de le
relire avant le `chmod` pour un poste sensible. Le SHA du commit GitHub peut
être substitué au nom de la branche pour figer une version testée.

## Choisir un profil

```bash
"$HOME/.local/bin/lexos-effets" fluide
"$HOME/.local/bin/lexos-effets" hologramme
"$HOME/.local/bin/lexos-effets" neon
"$HOME/.local/bin/lexos-effets" portail

"$HOME/.local/bin/lexos-effets" status
```

Un seul profil peut être actif à la fois. La commande arrête uniquement le
compositeur CRT contrôlé par LexOS, jamais une instance picom externe.
L'outil pose un démarrage automatique **dans le compte** pour reprendre le
profil choisi à la prochaine ouverture de session, sans administrateur.
Le fichier `/usr/share/lexos/picom/lexos-tv.conf` n'est jamais réécrit.
Si un nouveau profil ne démarre pas, le script tente de rétablir le CRT;
le superviseur rend le compositeur de xfwm4 quand picom quitte.

### Retour arrière

```bash
"$HOME/.local/bin/lexos-effets" crt
lexos crt status
```

Pour éteindre complètement les animations :
```bash
"$HOME/.local/bin/lexos-effets" off
```

Pour supprimer uniquement le pack expérimental après l'avoir éteint :
```bash
"$HOME/.local/bin/lexos-effets" crt
rm -f "$HOME/.config/autostart/lexos-effets.desktop"
rm -f "$HOME/.local/bin/lexos-effets"
```

Les réglages expérimentaux restent dans
`~/.config/lexos/effets/` pour inspection; ils ne touchent pas aux paquets
NVIDIA. Ne pas supprimer ce dossier pendant qu'un profil tourne.

### Tests avant toute ISO publique

- `bash tests/test_lexos_202_effets.sh` : génération sans GPU, conservation
  du CRT original, compatibilité source/règles, 4 profils et ombre néon.
- `shellcheck -S warning` sur l'outil et `bash -n`.
- Sur la RTX 5060 réelle : ouvrir/fermer Thunar/Firefox; vérifier logs,
  mise en veille, sortie plein écran, performance et retour à CRT/xfwm4.
- Les effets Glitch RGB, véritable halo et démarrage rétro restent
  en recherche. Aucun changement de noyau, GRUB ou Windows.
