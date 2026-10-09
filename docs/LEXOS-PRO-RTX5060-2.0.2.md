# LexOS Pro RTX5060 V2.0.2 — préparation et reconstruction sûre

## État et portée

Préparé sur `feature/lexos-pro-2.0.2-rtx5060-icons`, PR brouillon #6,
base `fix/lexos-2.0.1-live-desktop-nvidia`. La branche par défaut est
`claude/code`; ses constructions automatiques publient des releases.
La CI du commit initial `0ac45cb` était réussie (run 37919589179).
Les changements suivants doivent recevoir leur propre CI. La PR #5 reste
en brouillon vers claude/code; la PR #4 (Pro par défaut) reste distincte et
non fusionnée. La reconstruction ci-dessous force donc explicitement Pro.
Aucune ISO 2.0.2 construite, aucun système installé mis à jour, aucune
partition, NVRAM ou configuration de démarrage du PC modifiée ici.
La release et le workflow de publication 2.0.1 restent intacts.

## Changements intégrés

- Corbeille : réutilisation des SVG vide/pleine de la PR #6 et du hook 0605
  de conversion PNG; thème LexOS conservé. `show-trash=true` ajouté dans
  le squelette XFCE. Les utilisateurs existants peuvent activer Corbeille
  dans Réglages du bureau → Icônes; leur configuration n'est pas écrasée.
- Tableau de bord : `lexos-pro.desktop` propose Retirer du dock et Épingler.
  Thunar offre aussi Retirer du dock sur les fichiers `.desktop`.
  `lexos-epingler --enlever` reconnaît les URI file:/, file:///, encodées,
  application: et les copies bureau du même identifiant `.desktop`.
  Il retire uniquement les `.dockitem` correspondants; il conserve les
  autres applications et le terminal Pro. Les liens symboliques sont ignorés.
  Le tableau de bord n'était déjà pas dans les lanceurs ni les defaults
  dconf du dépôt; il le reste. `lock-items=false` est conservé.
  Aucun service trouvé ne le réépingle automatiquement. La cause exacte
  sur l'ancienne machine nécessite encore la lecture de ses lanceurs.
- GRUB : fond approuvé copié sans retouche dans les thèmes ISO et installé.
  Source récupérée : `livrables/lexos-grub-fond/background.png`, dont le
  document précédent atteste la copie de « Bannière cyberpunk LexOS Pro(1).png ».
  `/mnt/data` n'est pas présent ici. Empreinte : `docs/grub-background.sha256`.
  Aucune entrée n'est dessinée dans le fond. Le vrai `boot_menu` est centré,
  sur un panneau noir opaque séparé pour rendre le texte blanc lisible.
  Six lignes au minimum sur les résolutions testées, défilement activé pour
  les entrées supplémentaires. Le thème et le distributeur GRUB annoncent
  `LexOS-Pro RTX5060 V2.0.2`; délai menu conservé à huit secondes dans
  l'ISO et le système installé. Les entrées générées Linux/Windows restent
  gérées par les hooks existants, sans inventer d'entrée Windows sur la clé.
- Mosaïque : Ctrl + Windows + gauche/droite, sur le même bureau, avec
  `tile_left_key`/`tile_right_key`. Windows + gauche/droite reste disponible.
  Migration unique XFCE par `lexos-raccourcis-mosaique` : sauvegarde de la
  configuration, retrait des commandes concurrentes pour ces combinaisons,
  correction des variantes Primary/Control, marqueur seulement après succès.
  Les autres raccourcis sont conservés; les personnalisations ultérieures
  ne sont pas réécrites à chaque connexion. Réapplication volontaire :
  `lexos-raccourcis-mosaique --force`. Le squelette seul ne migre pas un
  compte existant : y lancer cette commande manuellement après mise à jour.

Pour retirer le tableau de bord d'un compte existant, sans sudo :

```bash
lexos-epingler --enlever /usr/share/applications/lexos-pro.desktop
lexos-epingler --liste
```

Plank peut continuer à montrer une application en cours d'exécution après
son désépinglage : fermer sa fenêtre permet de vérifier qu'elle n'est plus
conservée. Si le retrait est interdit, vérifier `lock-items` et les droits de
`~/.config/plank/dock1/launchers/`; ne pas supprimer tout le dossier.
Aucun lanceur du tableau de bord n'est remis dans `/etc/skel`.

## Secure Boot activé — exigence ajoutée

`auto/config` conserve `--uefi-secure-boot enable`; shim-signed,
grub-efi-amd64-signed et mokutil sont déjà prévus. Le diagnostic partagé
conseille maintenant de conserver Secure Boot et d'examiner la confiance
MOK, plutôt que de le désactiver. `lexos-signer-pilote --etat` est en lecture
seule. L'outil d'inscription existant reste réservé au système installé et
ne s'exécute pas automatiquement.

La signature d'un module NVIDIA DKMS ne garantit pas sa confiance par le
noyau. Le bureau live RTX 5060 avec Secure Boot actif reste un **point de
validation bloquant avant publication** : le certificat utilisé pour les
modules de l'ISO peut ne pas être reconnu. Le mode secours doit rester
accessible; ce n'est pas une validation du bureau accéléré. Ne pas partager
une clé privée de signature avec une ISO pour résoudre ce problème.
L'inscription MOK, si nécessaire, est une modification explicite de la
confiance UEFI à faire et valider séparément sur une machine de test.
Aucune clé, configuration Secure Boot ou entrée Windows n'a été changée ici.

Références : [Debian Secure Boot et DKMS](https://wiki.debian.org/SecureBoot),
[format officiel des thèmes GRUB](https://www.gnu.org/software/grub/manual/grub/html_node/Theme-file-format.html).

## Tests avant construction

```bash
bash tests/test_lexos_202_icons.sh
python3 tests/test_lexos_202_desktop.py
bash tests/test_lexos_epingler.sh
bash tests/test_lexos_grub_theme.sh
bash tests/test_lexos_signer_pilote.sh
python3 tools/verifier-images.py
```

Le test desktop exécute le vrai outil de retrait sur un dock isolé et la
migration sur un faux xfconf persistant. Le test GRUB vérifie l'empreinte,
les deux copies, le panneau opaque et la géométrie à six résolutions.
Ces tests ne simulent pas un démarrage réel ou un pilote chargé.
Validation locale : les tests ciblés passent, ainsi que les 12 contrôles
Compiz et 87 tests unitaires des services Pro. Le banc graphique Pro
a échoué faute de serveur GTK accessible (`cannot open display`); son
rendu et ses dix mesures graphiques ne sont pas validés ici.

## Reconstruction Pro isolée, sans publication

Utiliser une VM Linux de construction avec disque virtuel dédié, sans
passage des disques Windows, sans monter l'ESP de l'hôte. Prendre un clone
neuf de la branche, conserver les ISO 2.0.1 ailleurs. Ne pas lancer
`make distclean` dans un dossier contenant les anciennes ISO.

```bash
git clone --branch feature/lexos-pro-2.0.2-rtx5060-icons \
  https://github.com/alexmarceauprevost812-source/lexOS-2.0.git lexos-202-build
cd lexos-202-build
git rev-parse HEAD  # consigner le SHA exact validé
sudo ./build.sh --check
sudo ./build.sh --flavour pro --suite trixie
sha256sum ./*.iso > SHA256SUMS
sudo bash tools/verifier-secure-boot-build.sh .
```

Installer les prérequis indiqués par `--check` dans la VM; l'audit de
signatures exige `sbsigntool`. Conserver build.log, SHA256SUMS, le SHA source
et les rapports NVIDIA/Secure Boot. Les ISO sont nommées
`lexos-2.0.2-rtx5060-pro-amd64.hybrid.iso` suivant live-build.

Autre voie : workflow **ISO de test 2.0.2 (sans publication)**,
`build-iso-test.yml`, sur le SHA/branche validé, saveur Pro. Son déclenchement
est manuel seulement; il conserve des artefacts 2.0.2 liés au SHA, sans
release ni suppression des anciens artefacts. Si GitHub ne propose pas ce
workflow sur une branche non par défaut, utiliser la VM : ne pas fusionner
uniquement pour rendre le bouton disponible. Aucun lancement fait ici.
Éviter `build-iso.yml`, la vigie et les branches `claude/**` pour cette
validation : le workflow historique peut publier automatiquement.

## Validation réelle obligatoire avant merge ou release

1. BIOS et UEFI en VM sans disque hôte : démarrage live normal et secours,
   titre, huit secondes, sélection au clavier, défilement et lisibilité en
   1920×1080, 1280×720 et 1024×768. Les entrées doivent être dynamiques.
2. UEFI Secure Boot avec variables OVMF de test et certificats de confiance
   adaptés à Debian : présence des signatures PE ne prouve ni confiance,
   ni compatibilité SBAT/DBX. Vérifier `mokutil --sb-state` en live.
3. RTX 5060 avec Secure Boot actif : bureau, TV HDMI, pilote effectivement
   chargé (`nvidia-smi`, `lsmod`, journaux des refus de signature). Si ce test
   échoue, garder la PR en brouillon et ne pas publier une compatibilité.
4. XFCE compte neuf : corbeille vide puis pleine, thème LexOS et taille des
   icônes. Deux fenêtres sur le même bureau : Ctrl+Windows+gauche/droite,
   vérifier que le numéro de bureau ne change pas. Déconnexion/reconnexion.
5. Plank : épingler/désépingler le tableau de bord, fermer sa fenêtre,
   reconnecter; terminal et autres épingles restent. Tester un compte ayant
   un ancien lanceur bureau/URI encodée et un ancien raccourci workspace.
6. Installation dans un disque virtuel de test uniquement : Linux + Windows
   de test, menu de huit secondes, démarrer chacun. La présence de Windows
   sur le PC réel ne peut pas être garantie par les fichiers du dépôt.

Aucun grub-install, update-grub, os-prober, formatage, changement EFI ou
commande d'inscription MOK à lancer sur le PC Windows pour préparer l'ISO.
La future installation dual boot sera une opération séparée à valider.
