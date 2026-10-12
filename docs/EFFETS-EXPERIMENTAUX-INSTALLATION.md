# Pack d'effets animés (essai sur LexOS Pro RTX5060)

**Statut : expérimental, par compte utilisateur.** Les animations simples sont
fournies par picom 12.5 : fluide, hologramme *simulé* (fondu/zoom), néon *simulé*
(ombre orange), portail *vers le centre*. Ce ne sont ni des shaders holographiques
ou RGB glitch ni une réduction précisément vers l'icône Plank. Les effets CRT
existants restent la référence.

Les sources sont sous
`config/includes.chroot/usr/share/lexos/picom/lexos-effets`.
Le panneau **Paramètres rapides**, dans le coin droit de l'écran, comporte
maintenant une tuile **Animations fenêtres** (auparavant « Effets TV 1980 »).
Cliquer ouvre un menu avec six choix : CRT vieille télévision, Fluide,
Hologramme simulé, Néon orange, Portail vers le centre et Sans animation.
Le bouton retour « ‹ » ou Échap referme le menu. Un seul effet peut être
activé; l'interface explique les erreurs au lieu de masquer les refus.

**Toujours expérimental** : le menu existe dans le code de la branche, mais
son fonctionnement graphique doit être validé sur une session XFCE réelle.
Aucun sudo ne sert à choisir un profil.

## Mise à jour sur un LexOS déjà installé

Dans le clone de la branche
`feature/lexos-pro-2.0.2-rtx5060-icons` :

```bash
git -C "$HOME/Projets LexOS/lexOS-2.0" branch --show-current
sudo miss a jour --essai
sudo miss a jour
```

La mise à jour copie le **panneau Web**, son action Python autorisée, le
superviseur CRT corrigé et le script
`/usr/share/lexos/picom/lexos-effets`. Fermer puis rouvrir le
panneau **Paramètres rapides** pour charger sa nouvelle interface;
cliquer « Animations fenêtres » pour ouvrir la liste.

Le premier clic sur un profil personnalisé prépare les quatre configurations
et réécrit l'autostart utilisateur vers **la version globale mise à jour**.
Ainsi une ancienne copie `~/.local/bin/lexos-effets` ne sera pas
appelée par erreur depuis le panneau. En ligne de commande, utiliser
`bash /usr/share/lexos/picom/lexos-effets neon` (et pas l'ancienne copie).

Le superviseur attend maintenant que le picom CRT se ferme réellement
avant d'en lancer un autre et refuse de démarrer si un compositeur externe
est toujours actif. Le profil CRT d'origine reste inchangé.

Pour ces fichiers de la session graphique, aucune nouvelle ISO n'est
nécessaire. Les composants GRUB, noyau et installateur restent exclus de
`sudo miss a jour`. L'option `--skel` n'est pas nécessaire pour ce
panneau global.

## Choisir un profil

```bash
bash /usr/share/lexos/picom/lexos-effets fluide
bash /usr/share/lexos/picom/lexos-effets hologramme
bash /usr/share/lexos/picom/lexos-effets neon
bash /usr/share/lexos/picom/lexos-effets portail

bash /usr/share/lexos/picom/lexos-effets status
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
bash /usr/share/lexos/picom/lexos-effets crt
lexos crt status
```

Pour éteindre complètement les animations :
```bash
bash /usr/share/lexos/picom/lexos-effets off
```

Pour supprimer uniquement le pack expérimental après l'avoir éteint :
```bash
bash /usr/share/lexos/picom/lexos-effets crt
rm -f "$HOME/.config/autostart/lexos-effets.desktop"
rm -f bash /usr/share/lexos/picom/lexos-effets
```

Les réglages expérimentaux restent dans
`~/.config/lexos/effets/` pour inspection; ils ne touchent pas aux paquets
NVIDIA. Ne pas supprimer ce dossier pendant qu'un profil tourne.

### Tests avant toute ISO publique

- `bash tests/test_lexos_202_effets.sh` : génération sans GPU, conservation
  du CRT original, compatibilité source/règles, 4 profils et ombre néon.
- `shellcheck -S warning` sur l'outil et `bash -n`.
- `python3 tests/test_lexos_202_effets_volet.py` : actions autorisées,
  messages d'erreur, lecture du profil et choix sans sudo.
- `node tests/test_lexos_202_effets_volet.js` : menu des six effets
  et retour vers la grille, sans lancer de vraie session XFCE.
- Sur la RTX 5060 réelle : ouvrir/fermer Thunar/Firefox; vérifier logs,
  mise en veille, sortie plein écran, performance et retour à CRT/xfwm4.
- Les effets Glitch RGB, véritable halo et démarrage rétro restent
  en recherche. Aucun changement de noyau, GRUB ou Windows.
