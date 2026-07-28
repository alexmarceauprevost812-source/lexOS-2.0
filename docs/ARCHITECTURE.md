# Comment LexOS est fabriqué

Ce document explique la mécanique interne — utile si tu veux modifier le
processus de construction plutôt que le contenu.

---

## Vue d'ensemble

LexOS n'est pas compilé à partir de rien. Il est **assemblé** : on part d'un
système Debian minimal, on y installe des paquets, on le personnalise, puis on
le compresse en image amorçable.

```
lexos.conf
    │
    ├─→ build.sh ─────→ vérifie l'environnement
    │                   génère /etc/lexos/build.conf
    │                   copie branding/ dans l'image
    │                   choisit les listes de paquets selon la saveur
    │
    ├─→ auto/config ──→ traduit lexos.conf en options live-build
    │
    └─→ lb build
          │
          ├─ 1. bootstrap    debootstrap installe un Debian minimal
          ├─ 2. chroot       installe les paquets des listes
          │                  copie config/includes.chroot/
          │                  exécute config/hooks/normal/ dans l'ordre
          ├─ 3. binary       construit le squashfs
          │                  ajoute isolinux + GRUB EFI
          │                  intègre l'installateur Debian
          └─ 4. iso          produit lexos-1.0-<saveur>-amd64.iso
```

---

## Les quatre étages de live-build

### 1. `bootstrap`

`debootstrap` télécharge les paquets essentiels de Debian et construit un
système minimal dans `chroot/`. Environ 250 Mo, sans noyau ni bureau.

Ce qui est piloté depuis `lexos.conf` : `LEXOS_DEBIAN_SUITE`, `LEXOS_ARCH`,
`LEXOS_MIRROR`.

### 2. `chroot`

L'étage qui fait tout le travail. Dans l'ordre :

1. Configuration d'APT (dépôts, sécurité, mises à jour).
2. Copie de `config/includes.chroot/` à la racine du chroot.
3. Installation de tous les paquets listés dans `config/package-lists/`.
4. Exécution des hooks `config/hooks/normal/*.hook.chroot`, par ordre
   alphabétique — d'où la numérotation.

> Les hooks tournent **à l'intérieur** du futur système, en root. Une commande
> qui échoue interrompt la construction : d'où les `|| true` sur tout ce qui
> n'est pas vital.

### 3. `binary`

Le chroot est compressé en `filesystem.squashfs` (xz). On y ajoute le
chargeur de démarrage (isolinux pour le BIOS, GRUB pour l'UEFI), l'écran du
menu, et l'installateur Debian.

### 4. `iso`

`xorriso` assemble le tout en une image hybride : le même fichier fonctionne
gravé sur DVD **et** copié brut sur clé USB.

---

## Circulation de la configuration

Le problème classique d'une distribution maison : la version est écrite à
douze endroits et trois d'entre eux sont oubliés. Ici il n'y en a qu'un.

```
lexos.conf                          ← tu édites ici, et seulement ici
    │
    ├─→ auto/config                 options live-build (nom de l'ISO, boot…)
    │
    └─→ build.sh
          └─→ config/includes.chroot/etc/lexos/build.conf   (fichier généré)
                    │
                    └─→ lu par les hooks, à l'intérieur du chroot :
                          0100 → /usr/lib/os-release, /etc/issue, /etc/motd
                          0110 → locales, clavier, fuseau horaire
                          0400 → LightDM, sudo
                          0500 → branding Calamares
                          0600 → thème LexOS Noir
                    │
                    └─→ lu à l'exécution par lexos, lexos-wm, lexos-firstrun
```

`build.conf` est **généré** : il est dans `.gitignore` et recréé à chaque
construction. Les hooks embarquent des valeurs de repli, si bien qu'un
`lb build` lancé directement (sans passer par `build.sh`) produit quand même
une image cohérente.

---

## Les hooks, un par un

| Hook | Rôle | Peut échouer sans casser ? |
|---|---|---|
| `0100-lexos-identity` | `os-release`, `lsb-release`, `issue`, `motd`, GRUB | Non — c'est l'identité |
| `0110-lexos-locale` | Locales, clavier, fuseau, police console | Partiellement |
| `0200-lexos-performance` | initramfs zstd, oomd, irqbalance, service de profil | Oui |
| `0250-lexos-optional` | Paquets de confort, un par un, tolérant | Oui — c'est son rôle |
| `0300-lexos-assets` | WebP→PNG, SVG→PNG, icônes, avatar, Plymouth | Oui — dégradation propre |
| `0400-lexos-desktop` | LightDM, menus, clic droit, raccourcis clavier | Sauté si pas de bureau |
| `0500-lexos-installer` | Calamares + chiffrement du disque (LUKS2) | Sauté si pas de Calamares |
| `0600-lexos-theme` | LexOS Noir dans `/etc/skel`, dock, base dconf | Oui |
| `9900-lexos-cleanup` | Caches, journaux, machine-id, clés SSH | Non |

### Pourquoi cet ordre

* L'identité (`0100`) doit précéder tout ce qui lit `/etc/os-release`.
* Les visuels (`0300`) doivent précéder le bureau (`0400`), qui pointe
  LightDM vers le fond d'écran produit.
* Le thème (`0600`) vient après le bureau, parce qu'il détecte si un bureau
  est installé.
* Le nettoyage (`9900`) doit être dernier — il vide les caches APT dont tout
  le reste se sert.

### Ce que fait `9900` et pourquoi c'est important

```sh
: > /etc/machine-id                    # sinon toutes les machines partagent le même
rm -f /etc/ssh/ssh_host_*_key          # sinon toutes partagent les mêmes clés SSH
```

Ces deux fichiers sont régénérés au premier démarrage réel. Les oublier
produirait des installations impossibles à distinguer sur un réseau — et un
risque de sécurité pour SSH.

---

## Le mécanisme des saveurs

`config/package-lists/` est lu intégralement par live-build : impossible d'y
mettre des listes conditionnelles.

La solution : les listes optionnelles vivent dans `flavours/<nom>/`, et
`build.sh` copie celles qui s'appliquent vers
`config/package-lists/zz-flavour-<saveur>-<fichier>` juste avant de lancer la
construction. Ces copies sont ignorées par Git et effacées par `make clean`.

```
minimal   →  (rien)
standard  →  flavours/standard/
dev       →  flavours/standard/ + flavours/dev/
full      →  flavours/standard/ + flavours/dev/ + flavours/full/
gaming    →  flavours/standard/ + flavours/dev/ + flavours/gaming/
```

Le préfixe `zz-` garantit qu'elles sont traitées après les listes de base.

---

## Le repli des effets CRT

Compiz donne l'effet « téléviseur », mais exige une accélération 3D réelle.
Sur une machine sans pilote graphique — courant en machine virtuelle — le
lancer produirait un écran noir sans bureau.

`lexos-wm` est déclaré comme gestionnaire de fenêtres dans
`xfce4-session.xml`, à la place de `xfwm4`. Sa logique :

```
LEXOS_CRT_EFFECTS == "off"        →  xfwm4
compiz absent                     →  xfwm4
glxinfo absent ou en échec        →  xfwm4
pas de « direct rendering: Yes »  →  xfwm4
renderer = llvmpipe/softpipe/swrast (rendu logiciel)
                                  →  xfwm4
sinon                             →  compiz, avec filet de sécurité 5 s
```

Le filet : si Compiz meurt dans les cinq premières secondes, `lexos-wm` prend
le relais avec xfwm4. Tout est journalisé dans `~/.config/lexos/wm.log`, que
`lexos crt status` affiche.

**Le principe** : jamais d'écran noir. Un bureau moins joli vaut mille fois
mieux qu'un bureau absent.

---

## Le thème : pourquoi générer plutôt que livrer

Un thème GTK complet, c'est des milliers de lignes de CSS et des images de
décoration. En écrire un de zéro pour six couleurs d'accent serait
ingérable.

`lexos-theme-gen` prend le chemin inverse : il s'appuie sur **Arc-Dark**
(thème existant, complet, testé) et écrit par-dessus une feuille CSS
utilisateur — appliquée en dernier par GTK, donc gagnante. Environ 200 lignes
suffisent pour le noir pur, l'écriture blanche et l'accent.

Le script écrit dans `$HOME`, ce qui donne deux usages :

```bash
# à la construction, pour tout futur compte
HOME=/etc/skel lexos-theme-gen orange --target /etc/skel

# à l'exécution, pour l'utilisateur courant
lexos accent violet
```

Fichiers produits :

| Fichier | Pour |
|---|---|
| `.config/gtk-3.0/gtk.css` | Applications GTK 3 (la majorité) |
| `.config/gtk-4.0/gtk.css` | Applications GTK 4 |
| `.gtkrc-2.0` | Applications GTK 2 (anciennes) |
| `.config/xfce4/terminal/terminalrc` | Terminal |
| `.config/lexos/theme.conf` | Variables pour les autres scripts |

---

## Le garde-fou d'installation

`lexos-install` s'interpose entre l'utilisateur et Calamares. Il ne formate
rien lui-même : il vérifie, avertit, et passe la main.

```
lexos-install
    │
    ├─ pas en session live ?        → refus (« démarre depuis la clé USB »)
    ├─ liste les disques (lsblk)
    ├─ avertit que l'effacement est irréversible
    ├─ demande confirmation
    │     graphique : bouton « J'ai compris, installer »
    │     console   : taper EFFACER en toutes lettres
    ├─ refus ou autre saisie        → sortie 0, rien n'est modifié
    └─ confirmation                 → exec calamares
```

Le raccourci du bureau et l'entrée du dock pointent sur `lexos-install`, pas
sur `calamares` : le garde-fou ne peut pas être contourné par accident.

---

## Deux niveaux de paquets

live-build interrompt la construction dès qu'un nom de paquet n'existe pas.
C'est le bon réflexe pour le noyau — beaucoup moins pour un thème d'icônes
renommé entre deux versions de Debian.

D'où la séparation :

| | Où | Comportement si absent |
|---|---|---|
| **Essentiels** | `config/package-lists/`, `flavours/*/` | La construction s'arrête |
| **Confort** | `config/includes.chroot/usr/share/lexos/optional-packages/` | Noté et ignoré |

Le hook `0250` tente d'abord d'installer tous les paquets de confort d'un
bloc — c'est bien plus rapide. Si ça échoue, il reprend un par un pour
identifier précisément le fautif, et écrit le bilan dans
`/etc/lexos/optional-report` :

```
# Paquets optionnels — saveur standard
# Installés : 84    Indisponibles : 2

# Non installés (nom absent de l'archive, ou conflit) :
plank
compiz-plugins-extra
```

Le code qui dépend de ces paquets s'y attend : `lexos-wm` retombe sur xfwm4
sans Compiz, le dock ne démarre simplement pas sans Plank, `lexos share`
affiche l'URL sans QR code sans `qrencode`. Aucun de ces cas ne casse la
session.

---

## Le moteur de performance

`lexos-perf` agit sur deux plans, parce que la moitié des réglages exige root
et l'autre moitié une session ouverte :

| Plan | Exécuté par | Ce qu'il touche |
|---|---|---|
| Système | `lexos-perf.service` au démarrage, ou `sudo` | Gouverneur CPU, EPP, turbo, sysctl, ordonnanceur E/S, zram, services |
| Session | `lexos-firstrun`, ou la commande directe | Compositing, effets CRT, zoom du dock, miniatures |

Un seul `case` définit les quatre profils, avec les mêmes variables partout :
pour comprendre ce que fait `max`, il n'y a qu'un bloc de quinze lignes à
lire.

Les réglages CPU dégradent proprement. `schedutil` n'existe pas sur tous les
noyaux : le script lit `scaling_available_governors` et retombe sur
`ondemand`, puis `conservative`. Dans une machine virtuelle sans `cpufreq`,
il l'annonce au lieu de prétendre avoir agi.

---

## Le partage par QR code

Le besoin : envoyer une photo au téléphone sans installer d'application des
deux côtés. La réponse tient en trois pièces :

1. `lexos-share qr` crée un dossier temporaire et y fait des liens durs vers
   les fichiers — pas de copie, même pour une vidéo de 2 Go.
2. `share-server.py` sert ce dossier en HTTP sur le réseau local, avec une
   page dans les couleurs de LexOS et un formulaire d'envoi.
3. `qrencode` affiche l'adresse en QR code dans le terminal.

Le serveur s'arrête tout seul après quinze minutes. Rien ne sort du réseau
local, rien n'est téléversé nulle part.

Le parseur multipart est écrit à la main plutôt que d'utiliser le module
`cgi` de Python : celui-ci disparaît en Python 3.13, donc dans Debian trixie.
Il lit en flux, borné par `Content-Length`, et ne garde jamais plus de
64 Kio en mémoire — un envoi de 4 Go passe sans problème. Le nom de fichier
reçu est réduit à son nom de base : impossible d'écrire ailleurs que dans le
dossier de réception. `tests/test_share_server.py` vérifie les seize cas,
remontées de chemin comprises.

---

## Pourquoi ces choix

**Debian plutôt qu'Ubuntu comme socle.** `live-build` est l'outil officiel
Debian pour ce travail, stable et documenté. Ubuntu a divergé vers ses propres
outils. L'apparence s'inspire d'Ubuntu ; la plomberie est Debian.

**XFCE plutôt que GNOME ou KDE.** XFCE se configure par fichiers XML lisibles
et versionnables, il tourne sur du matériel modeste, et il accepte Compiz comme
gestionnaire de fenêtres — ce que GNOME refuse.

**Plank plutôt qu'un second panneau XFCE.** Plank est un vrai dock, avec zoom
et masquage intelligent, configurable par simples fichiers `.dockitem`. Un
panneau XFCE vertical demanderait bien plus de XML pour un résultat moins
proche d'Ubuntu.

**Calamares plutôt que l'installateur Debian seul.** Calamares s'habille aux
couleurs de la distribution et se pilote à la souris. L'installateur Debian
reste disponible depuis le menu de démarrage, comme filet de sécurité.

**Debian trixie plutôt que bookworm.** Noyau 6.12 LTS, systemd 257, Mesa 25 :
la même génération de composants qu'Ubuntu 26.04. Le matériel récent est
reconnu, et les performances graphiques suivent. `LEXOS_KERNEL_CHANNEL=backports`
va chercher un noyau encore plus neuf quand la machine l'exige.

**Connexion automatique aux réseaux ouverts : désactivée.** La fonctionnalité
est là parce qu'elle a été demandée, mais l'activer par défaut reviendrait à
faire circuler le trafic de l'utilisateur en clair sans qu'il l'ait choisi.
Elle demande donc `OUI` en toutes lettres après un avertissement, ne se
déclenche que hors ligne, et notifie à chaque connexion. La CI vérifie que le
défaut reste `off`.

**MIT plutôt que GPL.** Le travail original ici, ce sont des scripts de
construction. MIT laisse le maximum de liberté à qui veut partir de ce dépôt.
Les paquets embarqués gardent évidemment leurs licences respectives.

---

## Cycle de développement

```bash
# 1. modifier
$EDITOR lexos.conf
$EDITOR flavours/standard/desktop.list.chroot

# 2. vérifier sans construire (quelques secondes)
make lint
make preview

# 3. construire la saveur la plus légère (plus rapide)
sudo ./build.sh --flavour minimal

# 4. essayer dans QEMU
make test

# 5. construire pour de vrai
make build FLAVOUR=standard
```

Astuce : `lb build` reprend là où il s'est arrêté. Après un échec dans l'étage
`chroot`, corrige puis relance sans `make clean` — le bootstrap n'est pas
refait.

Pour repartir de zéro (changement de suite Debian, corruption) :

```bash
make distclean
```
