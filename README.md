<div align="center">

# LexOS 1.0 « Nomad »

**TI·LEX·AL** — une distribution Linux complète, noire, à ma sauce.

`Explore. Build. Own your machine.`

Basée sur Debian · Bureau XFCE façon Ubuntu · Licence MIT

</div>

---

## C'est quoi exactement

LexOS n'est pas un thème ni une simulation : c'est **une vraie distribution
Linux**. Ce dépôt contient tout ce qu'il faut pour fabriquer une **image ISO
amorçable** que tu graves sur une clé USB, que tu essaies sans risque, et que
tu installes si elle te plaît.

Le socle est Debian (stable, éprouvé, plus de 60 000 paquets). Par-dessus,
LexOS pose son identité : nom, logo, écran de démarrage, thème noir, dock,
outils maison et effets de fenêtres.

| | |
|---|---|
| **Nom** | LexOS 1.0 « Nomad » |
| **Socle** | Debian bookworm (modifiable) |
| **Bureau** | XFCE — barre en haut, dock à gauche, comme Ubuntu |
| **Thème** | LexOS Noir : fond noir pur, écriture blanche, boutons accentués |
| **Terminal** | Fond noir, écriture vert foncé, curseur orange |
| **Effets** | Ouverture/fermeture de fenêtres façon téléviseur 1980 |
| **Architecture** | amd64 (64 bits) |
| **Licence** | MIT pour le travail original — voir [LICENSE](LICENSE) |

---

## La règle d'or : essayer avant d'effacer

> **Aucune commande de ce projet n'efface ton disque dur sans que tu l'aies
> confirmé explicitement.**

Le parcours prévu est celui-ci, dans cet ordre :

```
1. Construire l'ISO       →  make build
2. Graver sur clé USB     →  make usb DEVICE=/dev/sdX
3. Démarrer sur la clé    →  session DÉMO, ton disque n'est pas touché
4. Essayer, tester, jouer →  autant de temps que tu veux
5. Seulement si convaincu →  lexos install-disk  (avertissement + confirmation)
```

En session démo, tout tourne depuis la clé USB et la mémoire vive. Tu peux
installer des logiciels, changer les couleurs, casser des choses : au
redémarrage tout est remis à neuf et ton disque dur n'a jamais été ouvert.

La commande `lexos demo` te dit à tout moment où tu en es :

```
  Session DÉMO — tu tournes depuis la clé USB.
  Ton disque dur n'est pas touché : essaie tout ce que tu veux.
  Support     : /dev/sdb1

  Quand tu es convaincu : lexos install-disk
```

`lexos install-disk` (et le raccourci « Installer LexOS » du bureau) affiche
la liste des disques détectés, prévient qu'un effacement est irréversible, et
exige que tu tapes `EFFACER` en console ou que tu cliques sur « J'ai compris »
en mode graphique. Sans ça, rien ne se passe.

---

## Construire ton ISO

### Ce qu'il te faut

Une machine **Linux** (Debian ou Ubuntu de préférence), **12 Go** de disque
libre et une connexion correcte — la construction télécharge plusieurs Go de
paquets.

```bash
sudo apt update
sudo apt install -y live-build debootstrap xorriso squashfs-tools \
                    rsync wget gnupg ca-certificates \
                    syslinux-common isolinux grub-efi-amd64-bin \
                    grub-pc-bin mtools dosfstools librsvg2-bin
```

> Pas de machine Linux sous la main ? Le workflow GitHub Actions
> [`build-iso.yml`](.github/workflows/build-iso.yml) construit l'ISO pour toi
> dans le nuage et la dépose en artefact téléchargeable.

### Vérifier puis construire

```bash
git clone https://github.com/alexmarceauprevost812-source/logiciel-ti-lex-.git
cd logiciel-ti-lex-

make check      # contrôle que tous les outils sont là
make build      # construit l'ISO (saveur standard)
```

Compte **20 à 60 minutes** selon ta connexion. À la fin :

```
  ok  ISO      : lexos-1.0-standard-amd64.iso
  ok  Taille   : 2.4G
  ok  SHA-256  : lexos-1.0-standard-amd64.iso.sha256
```

### Les quatre saveurs

| Saveur | Contenu | Taille approx. |
|---|---|---|
| `minimal` | Console seule, aucun bureau | ~700 Mio |
| `standard` | Bureau XFCE, Firefox, dock, effets — **défaut** | ~2,5 Gio |
| `dev` | standard + compilateurs, langages, conteneurs, Neovim | ~4 Gio |
| `full` | dev + LibreOffice, GIMP, Inkscape, VLC, Krita | ~6 Gio |

```bash
make minimal        # ou : make standard / make dev / make full
make build FLAVOUR=dev
```

---

## Essayer l'ISO

### Dans une machine virtuelle (le plus rapide)

```bash
make test           # démarrage BIOS dans QEMU
make test-uefi      # démarrage UEFI (exige le paquet ovmf)
```

### Sur une vraie clé USB

```bash
lsblk                             # repère ta clé : /dev/sdb, /dev/sdc…
make usb DEVICE=/dev/sdb          # demande de taper OUI avant d'écrire
```

⚠ `DEVICE` doit être **le disque entier** (`/dev/sdb`) et non une partition
(`/dev/sdb1`). Tout ce que contient la clé sera effacé — la clé, pas ton
disque dur.

Redémarre ensuite en choisissant la clé dans le menu de démarrage de ton
ordinateur (souvent `F12`, `F11`, `Échap` ou `Suppr` au démarrage).

---

## À quoi ça ressemble

### LexOS Noir

Fond **noir pur** (`#000000`), écriture **blanche**, et une couleur d'accent
qui habille les boutons, les sélections, le curseur et les barres de
progression.

| Accent | Code | Commande |
|---|---|---|
| Orange *(défaut)* | `#E8873A` | `lexos accent orange` |
| Bleu | `#3D8BFD` | `lexos accent bleu` |
| Rouge | `#E5484D` | `lexos accent rouge` |
| Vert foncé | `#1F8F4E` | `lexos accent vert` |
| Gris | `#8A8A8A` | `lexos accent gris` |
| Violet | `#8B5CF6` | `lexos accent violet` |

Le changement est instantané et se retient d'une session à l'autre.

### Le terminal

Fond noir, écriture **vert foncé** (`#23A55A`), curseur à la couleur d'accent,
police Fira Code, invite sur deux lignes avec la branche Git courante.

### Effets de fenêtres « TV 1980 »

Les fenêtres s'ouvrent et se ferment comme un téléviseur cathodique qu'on
allume et qu'on coupe : l'image s'écrase en une ligne horizontale puis
s'éteint. C'est l'effet *Glide 2* de Compiz, configuré dans
[`01-lexos-compiz`](config/includes.chroot/etc/dconf/db/local.d/01-lexos-compiz).

**Repli automatique** : Compiz exige une vraie accélération 3D. Sur une machine
qui n'en a pas (ou en rendu logiciel), `lexos-wm` le détecte et démarre xfwm4
à la place — fondus plus simples, mais **jamais d'écran noir**.

```bash
lexos crt status    # ce qui tourne réellement, et pourquoi
lexos crt off       # revenir à xfwm4
lexos crt on        # réactiver
```

Un fond d'écran assorti, avec lignes de balayage et masque de phosphore, est
livré : `/usr/share/backgrounds/lexos/wallpaper-crt.png`.

### La disposition, façon Ubuntu

* **Barre en haut** — menu Applications à gauche, horloge au centre, réseau /
  son / batterie / session à droite.
* **Dock à gauche** — Plank, icônes zoomantes, masquage intelligent.
* **Bureau** — raccourcis « Essayer LexOS (démo) » et « Installer LexOS ».

---

## Les outils maison

### `lexfetch`

La fiche technique de la machine, avec le masque LexOS en art ASCII.

```
        ▄▄██████████▄▄         lex@lexos
     ▄██████████████████▄      ────────────────────────────────
  ▄████████████████████████▄   OS       : LexOS 1.0 (Nomad) x86_64
  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀   Base     : Debian bookworm (12.5)
   ███▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄███    Noyau    : 6.1.0-18-amd64
    ██ ▐████▌    ▐████▌ ██     Uptime   : 14 minutes
    ██ ▐████▌    ▐████▌ ██     Paquets  : 1842 (dpkg)
   ███▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀███    Bureau   : XFCE
    ███████▄▄▄▄▄▄▄▄███████     CPU      : Intel Core i5 (4 cœurs)
    █████  ▄  ▄  ▄  █████      Mémoire  : 1204 Mio / 7862 Mio
```

### `lexos`

```
SYSTÈME
  info                Résumé du système
  version             Version de LexOS
  doctor              Diagnostic : disque, réseau, services, mises à jour
  logs [n]            n dernières erreurs du journal

PAQUETS
  update / upgrade    Rafraîchir / mettre à jour
  install <paquets…>  Installer
  remove  <paquets…>  Désinstaller
  search  <terme>     Chercher
  clean               Libérer de l'espace

APPARENCE
  accent <couleur>    orange · bleu · rouge · vert · gris · violet
  wallpaper [chemin]  Changer le fond d'écran
  crt <on|off|status> Effets d'ouverture/fermeture façon TV 1980

DÉMO & INSTALLATION
  demo                Clé USB (démo) ou disque dur ?
  install-disk        Installer sur le disque (confirmation exigée)
```

`lexos doctor` en dit long en cinq lignes :

```
✓ Disque / : 34% utilisé
✓ Mémoire : 22% utilisée
✓ Réseau : dépôts Debian joignables
✓ Aucun service en échec
! 7 mise(s) à jour disponible(s) — lexos upgrade
```

---

## Personnaliser ta version

Tout part de **[`lexos.conf`](lexos.conf)**, unique source de vérité. Change
une valeur, relance `make build`, et l'ISO entière suit — nom, écran de
démarrage, installateur, `/etc/os-release`, thème.

```bash
LEXOS_NAME="LexOS"
LEXOS_VERSION="1.0"
LEXOS_CODENAME="Nomad"
LEXOS_ACCENT_NAME="orange"      # couleur des boutons
LEXOS_CRT_EFFECTS="on"          # effets TV 1980
LEXOS_DEBIAN_SUITE="bookworm"   # ou trixie
LEXOS_TIMEZONE="America/Toronto"
LEXOS_KEYBOARD_LAYOUT="ca"
```

**Ajouter des logiciels** — ouvre la liste correspondante et écris un nom de
paquet par ligne :

```
config/package-lists/lexos-core.list.chroot   ← toutes les saveurs
flavours/standard/desktop.list.chroot         ← bureau
flavours/dev/devtools.list.chroot             ← développement
flavours/full/office-media.list.chroot        ← bureautique & création
```

**Changer les visuels** — remplace les fichiers de [`branding/`](branding/) :

| Fichier | Rôle |
|---|---|
| `logo-ti-lex-al.png` | Logo officiel : icônes, Plymouth, installateur |
| `logo.svg` | Variante vectorielle du masque |
| `wallpaper.svg` | Fond d'écran par défaut |
| `wallpaper-crt.svg` | Variante lignes de balayage |
| `mascot*.webp` | Avatar de session, écran d'accueil |

```bash
make preview    # rend les SVG en PNG dans ./preview pour les regarder
```

Guides détaillés : **[docs/PERSONNALISATION.md](docs/PERSONNALISATION.md)** ·
**[docs/INSTALLATION.md](docs/INSTALLATION.md)** ·
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

---

## Organisation du dépôt

```
lexos.conf                  Identité de la distro — la seule source de vérité
build.sh                    Construction : vérifie, prépare, lance live-build
Makefile                    Raccourcis (build, test, usb, lint, clean)

auto/                       Points d'entrée live-build (config, build, clean)
config/
  package-lists/            Paquets présents dans toutes les saveurs
  hooks/normal/             Personnalisation exécutée dans le chroot
    0100 identité           os-release, issue, motd, GRUB
    0110 localisation       langue, clavier, fuseau
    0300 visuels            SVG→PNG, icônes, avatar, Plymouth
    0400 bureau             LightDM, sudo, applications par défaut
    0500 installateur       Habillage Calamares + raccourcis
    0600 thème              LexOS Noir + base dconf
    9900 nettoyage          Allègement de l'image
  includes.chroot/          Fichiers copiés tels quels dans le système
    usr/bin/                lexos, lexfetch, lexos-install, lexos-wm…
    etc/skel/               Configuration héritée par chaque compte
    etc/dconf/db/local.d/   Dock Plank + effets Compiz
  bootloaders/isolinux/     Écran du menu de démarrage

flavours/                   Paquets optionnels par saveur
branding/                   Logo, mascottes, fonds d'écran (sources)
tools/                      Utilitaires de développement
docs/                       Documentation détaillée
```

---

## Questions fréquentes

**Est-ce que ça peut casser mon ordinateur ?**
Non. Tant que tu restes en session démo depuis la clé USB, rien n'est écrit
sur ton disque. Le seul moment risqué est l'installation, et elle demande une
confirmation explicite.

**Je peux garder Windows à côté ?**
Oui. L'installateur Calamares propose « installer à côté » en plus de
« effacer le disque ». Choisis bien — et sauvegarde avant.

**Pourquoi Debian et pas Ubuntu comme socle ?**
`live-build` est l'outil officiel Debian, il est stable et bien documenté.
L'apparence s'inspire d'Ubuntu (barre en haut, dock à gauche), la base est
Debian. Tu peux changer de suite avec `LEXOS_DEBIAN_SUITE`.

**Les effets CRT ne marchent pas chez moi.**
`lexos crt status` te dira pourquoi. La cause la plus fréquente est l'absence
d'accélération 3D — courant dans une machine virtuelle sans pilote graphique.
LexOS retombe alors sur xfwm4 exprès, pour ne pas te laisser sans bureau.

**Comment je remets tout à zéro ?**
`make distclean` supprime les artefacts et les ISO. Le dépôt redevient propre.

---

## Licence

Le travail original de ce dépôt — scripts, hooks, configuration, outils,
visuels vectoriels — est sous **licence MIT** : réutilise, modifie, distribue.

Les paquets Debian embarqués dans l'ISO conservent chacun leur propre licence.
Le logo **TI-LEX-AL** et les mascottes restent la propriété d'Alex
Marceau-Prevost : si tu publies ta propre distribution dérivée, remplace-les
par tes visuels. Détails dans [LICENSE](LICENSE).

LexOS n'est ni affilié à, ni approuvé par le projet Debian.

---

<div align="center">

**TI·LEX·AL** — LexOS 1.0 « Nomad »

</div>
