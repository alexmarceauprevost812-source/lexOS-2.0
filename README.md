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

Le socle est **Debian 13 « trixie »** : noyau 6.12 LTS, systemd 257, Mesa 25 —
la même génération de composants qu'Ubuntu 26.04, le même moteur. Par-dessus,
LexOS pose son identité : nom, logo, écran de démarrage, thème noir, dock,
profils de performance, outils réseau et de partage.

| | |
|---|---|
| **Nom** | LexOS 1.0 « Nomad » |
| **Socle** | Debian trixie — noyau 6.12 LTS, systemd 257, Mesa 25 |
| **Bureau** | XFCE — barre en haut, dock à droite, façon Ubuntu |
| **Thème** | LexOS Noir : fond noir pur, écriture blanche, boutons accentués |
| **Terminal** | Fond noir, écriture vert néon, curseur orange |
| **Effets** | Ouverture/fermeture de fenêtres façon téléviseur 1980 |
| **Performance** | 4 profils : petit · médium · performant · max |
| **Réseau** | Mode avion, Wi-Fi, Bluetooth, partage par QR code |
| **Sécurité** | Chiffrement du disque proposé à l'installation (LUKS2) |
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

> **Pas de machine Linux sous la main ?** GitHub la construit pour toi.
> Édite [`.iso-build-request`](.iso-build-request) et pousse :
>
> ```
> flavour: standard      # minimal | standard | dev | full | gaming
> suite: trixie          # trixie | bookworm
> build: 2               # incrémenter pour relancer
> ```
>
> Une heure plus tard, l'ISO est téléchargeable dans
> **Actions → la construction → Artifacts**.
> Voir [`build-iso.yml`](.github/workflows/build-iso.yml).

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

### Les cinq saveurs

| Saveur | Contenu | Taille approx. |
|---|---|---|
| `minimal` | Console seule, aucun bureau | ~700 Mio |
| `standard` | Bureau XFCE, Firefox, dock, effets — **défaut** | ~2,5 Gio |
| `dev` | standard + compilateurs, langages, conteneurs, Neovim | ~4 Gio |
| `full` | dev + LibreOffice, GIMP, Inkscape, VLC, Krita | ~6 Gio |
| `gaming` | dev + Steam, Lutris, Wine, gamemode, MangoHud, Vulkan | ~5 Gio |

```bash
make minimal        # ou : make standard / make dev / make full / make gaming
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

### Sans clé USB, ou depuis Windows

Trois autres chemins mènent au bureau LexOS, détaillés dans
[`docs/INSTALLATION.md`](docs/INSTALLATION.md) :

| Moyen | Pour qui | Touche au disque ? |
|---|---|---|
| **VirtualBox** — LexOS dans une fenêtre, comme un logiciel | Windows, macOS | Non, jamais |
| **Ventoy** — copier-coller l'ISO sur la clé, sans graver | Tout le monde | Non |
| **Boucle GRUB** — démarrer l'ISO posée sur le disque dur | Linux déjà installé | Non (lecture seule) |

Pour garder LexOS **à côté** de Windows pour de bon, c'est l'installation
normale : session démo → `lexos install-disk` → **« Installer à côté »**, qui
rétrécit la partition Windows sans l'effacer.

---

## À quoi ça ressemble

### LexOS Noir

Fond **noir pur** (`#000000`), écriture **blanche**, et une couleur d'accent
qui habille les boutons, les sélections, le curseur et les barres de
progression.

| Accent | Code | Commande |
|---|---|---|
| Orange *(défaut)* | `#E8590C` | `lexos accent orange` |
| Bleu | `#3D8BFD` | `lexos accent bleu` |
| Rouge | `#E5484D` | `lexos accent rouge` |
| Vert foncé | `#1F8F4E` | `lexos accent vert` |
| Gris | `#8A8A8A` | `lexos accent gris` |
| Violet | `#8B5CF6` | `lexos accent violet` |
| Vert néon | `#39FF14` | `lexos accent neon` |

Le changement est instantané et se retient d'une session à l'autre.

### Le terminal

Fond noir, écriture **vert néon** (`#39FF14`), curseur à la couleur d'accent,
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
* **Dock à droite** — Plank, icônes zoomantes, masquage intelligent.
  Déplaçable : `lexos dock gauche` · `bas` · `haut` · `droite`.
* **Bureau** — raccourcis « Essayer LexOS (démo) » et « Installer LexOS ».

---

## Performance de la machine

Quatre profils, du plus économe au plus agressif. Chacun agit sur le
gouverneur du processeur, les réglages du noyau, l'ordonnanceur disque, les
services et les effets du bureau.

| Profil | Pour qui | Ce qui change |
|---|---|---|
| `petit` | Vieille machine, batterie à ménager | Gouverneur `powersave`, turbo coupé, zram, journal en mémoire, Bluetooth et impression arrêtés, aucun effet de fenêtre |
| `medium` | La plupart des machines — **défaut** | Gouverneur adaptatif, compositing simple, réglages noyau équilibrés |
| `performant` | Machine récente, branchée | Gouverneur `performance`, swappiness basse, TCP BBR, effets CRT actifs |
| `max` | Tout donner | `performance` sans compromis, cache disque agressif, ordonnanceur E/S à faible latence |

```bash
lexos perf              # liste les profils
lexos perf auto         # choisit d'après la RAM et le nombre de cœurs
lexos perf max          # applique
lexos perf status       # ce que fait VRAIMENT la machine
```

`lexos perf status` compare ce qui est demandé et ce qui tourne. Sur une
machine virtuelle sans pilote `cpufreq`, il le dit plutôt que de prétendre
avoir réglé quelque chose.

Le profil est rejoué à chaque démarrage par `lexos-perf.service`. Sans profil
enregistré, LexOS choisit tout seul au premier allumage.

Un sélecteur graphique est aussi dans le menu : **Performance de la machine**
(ou `Super+P`).

---

## Réseau : mode avion, Wi-Fi, Bluetooth

```bash
lexos avion on          # coupe Wi-Fi, Bluetooth et données mobiles
lexos avion toggle      # bascule — aussi sur Super+A et la touche Fn Wi-Fi
lexos wifi              # cherche les réseaux à portée
lexos net connect "Café du coin"
lexos bt scan           # appareils Bluetooth à portée
lexos bt pair "Casque"  # appaire, approuve et connecte
lexos net status        # vue d'ensemble
```

Le scan Wi-Fi montre le signal en barres, la bande, et signale en clair les
réseaux **OUVERT** — ceux sans mot de passe.

### Connexion automatique aux réseaux ouverts

LexOS sait se raccrocher tout seul à un réseau sans mot de passe quand tu n'as
plus de connexion. **Cette option est désactivée par défaut**, et l'activer
demande de taper `OUI` après un avertissement :

> Un réseau ouvert n'est pas chiffré. Toute personne à portée peut lire ce qui
> y circule en clair, et n'importe qui peut créer un faux point d'accès portant
> le nom d'un réseau connu.

```bash
lexos net auto on       # avertit, puis demande confirmation
lexos net auto status
lexos net auto off
```

Quand c'est actif, LexOS ne se connecte que si tu es réellement hors ligne,
jamais par-dessus une connexion filaire, et affiche une notification à chaque
fois. Rien ne se fait en douce.

---

## Plusieurs écrans

Portable + écran externe, projecteur, triple écran : tout se règle depuis
**Écrans** dans le menu (ou `Super+D`), et en ligne de commande.

```bash
lexos ecran                      # ce qui est branché, résolution, position
lexos ecran etendre droite       # bureau étendu — aussi gauche, haut, bas
lexos ecran miroir               # la même image partout (projecteur)
lexos ecran principal HDMI-1     # le grand écran porte la barre et le dock
lexos ecran seul eDP-1           # n'allumer que celui-là
lexos ecran resolution HDMI-1 2560x1440
lexos ecran gui                  # réglage à la souris
```

`lexos ecran` affiche l'état réel :

```
  SORTIE       RÉSOLUTION     POSITION     PRINCIPAL ÉTAT
  ──────────────────────────────────────────────────────────
  eDP-1        1920x1080      +0+0         ●         actif
  HDMI-1       2560x1440      +1920+0                actif

  2 écran(s) branché(s), 2 allumé(s).
```

Le fond d'écran est réappliqué automatiquement sur tout écran qui vient de
s'allumer — pas de bureau gris sur le second moniteur.

### Retrouver sa disposition tout seul

```bash
lexos ecran profil save bureau   # mémorise la configuration actuelle
lexos ecran profil list
```

Avec `autorandr`, LexOS reconnaît la combinaison d'écrans au branchement et
réapplique la bonne disposition sans rien demander.

---

## Partager des fichiers et des images

Trois moyens, du plus universel au plus spécialisé.

### QR code — rien à installer sur le téléphone

```bash
lexos share photo.jpg
```

Un QR code s'affiche dans le terminal. Tu le scannes avec l'appareil photo du
téléphone, le fichier se télécharge. La même page permet de **t'envoyer** des
fichiers depuis le téléphone — ils arrivent dans `~/Téléchargements/LexOS-reçus`.

Le partage s'arrête tout seul au bout de 15 minutes.

Dans le gestionnaire de fichiers : clic droit → **Partager avec LexOS**.

### KDE Connect — façon AirDrop

Avec l'application KDE Connect sur le téléphone, les deux appareils appairés
sur le même Wi-Fi : `lexos share` envoie directement, sans QR code.

### Bluetooth — quand il n'y a pas de réseau

```bash
lexos share bt document.pdf
```

```bash
lexos share devices     # ce qui est joignable, par quel moyen
lexos receive           # ouvrir une boîte de réception
```

### Autocollants — découper le sujet d'une photo

Comme la fonction « Autocollants » d'un téléphone Samsung, mais 100% locale :

```bash
lexos sticker photo.jpg
```

Le sujet est découpé du fond et enregistré comme un vrai fichier PNG à fond
transparent, dans `~/Images/Autocollants/`. Deux méthodes, choisies toutes
seules :

- **Mode IA** (`rembg`, si installé) — découpe même sur un fond compliqué.
- **Mode rapide** (ImageMagick, toujours disponible) — retire un fond à peu
  près uni, comme sur une photo prise devant un mur clair.

Dans le gestionnaire de fichiers : clic droit sur une image → **Créer un
autocollant**.

---

## IA locale — agent autonome dans le terminal

```bash
lexos ia setup                      # installe Ollama + un petit modèle, une fois
lexos ia                            # conversation libre
lexos ia "libère 2 Gio d'espace disque"   # agent autonome
```

Le moteur (Ollama) tourne **sur la machine** : une fois le modèle téléchargé,
plus rien ne sort sur internet, même en mode agent.

En mode agent, LexOS propose une commande, te la montre, l'exécute, regarde
le résultat, et recommence jusqu'à avoir fini la tâche. Les mêmes règles que
`lexos format` s'appliquent :

- Seules les commandes de **lecture** connues (`ls`, `df`, `cat`, `journalctl`…)
  tournent sans rien demander. **Tout le reste attend ton accord**, même avec
  `--auto`.
- Quelques formes notoires (`rm -rf /`, `mkfs`, `dd of=/dev/…`) sont refusées
  sèchement, sans même proposer.
- Jamais `sudo` par défaut (`lexos ia --sudo "…"` pour l'autoriser).
- Sans terminal (script, tâche planifiée), rien qui demanderait une
  confirmation ne s'exécute.

---

## Mot de passe sur le disque dur

À l'installation, Calamares propose de **chiffrer le disque entier** (LUKS2).
Une phrase secrète est alors demandée à chaque démarrage, avant même que le
système ne se charge.

Sans elle, le contenu du disque est illisible — y compris pour quelqu'un qui
sortirait le disque de la machine pour le brancher ailleurs. C'est la seule
protection réelle contre le vol de l'ordinateur ; une simple session
verrouillée ne protège rien.

> **Le revers :** phrase secrète oubliée = données perdues, définitivement.
> Il n'existe aucune porte dérobée. Note-la ailleurs qu'à l'intérieur de
> la machine.

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
  accent <couleur>    orange · bleu · rouge · vert · gris · violet · neon
  dock <position>     droite (défaut) · gauche · bas · haut
  ecran               Plusieurs écrans : étendre, dupliquer, principal
  wallpaper [chemin]  Changer le fond d'écran
  crt <on|off|status> Effets d'ouverture/fermeture façon TV 1980

PERFORMANCE
  perf <profil>       petit · medium · performant · max
  perf status         Ce que fait vraiment la machine
  perf auto           Choisir d'après le matériel

RÉSEAU
  avion <on|off>      Mode avion : coupe toutes les radios
  wifi                Chercher et rejoindre un réseau
  bt                  Bluetooth : appairer, connecter
  net                 Toutes les commandes réseau

PARTAGE
  share <fichiers…>   Envoyer vers un téléphone
  receive             Recevoir depuis un téléphone

IMAGES
  sticker <image…>    Découpe le sujet en autocollant (PNG transparent)

IA
  ia setup            Installe l'IA locale (Ollama) + un petit modèle
  ia "<tâche>"         Agent autonome — rien n'est envoyé sur internet

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
LEXOS_DEBIAN_SUITE="trixie"     # ou bookworm (plus ancien, plus éprouvé)
LEXOS_KERNEL_CHANNEL="stock"    # ou backports (noyau plus récent)
LEXOS_PERF_PROFILE="auto"       # petit | medium | performant | max
LEXOS_DOCK_POSITION="right"     # right | left | bottom | top
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
  package-lists/            Paquets ESSENTIELS — un nom manquant casse le build
  hooks/normal/             Personnalisation exécutée dans le chroot
    0100 identité           os-release, issue, motd, GRUB
    0110 localisation       langue, clavier, fuseau
    0200 performance        initramfs zstd, oomd, service de profil
    0250 optionnels         paquets de confort, tolérants aux absences
    0300 visuels            WebP/SVG→PNG, icônes, avatar, Plymouth
    0400 bureau             LightDM, menus, raccourcis clavier, clic droit
    0500 installateur       Calamares + chiffrement du disque
    0600 thème              LexOS Noir + dock + base dconf
    9900 nettoyage          Allègement de l'image
  includes.chroot/          Fichiers copiés tels quels dans le système
    usr/bin/                lexos, lexfetch, lexos-perf, lexos-net,
                            lexos-share, lexos-display, lexos-install…
    usr/lib/lexos/          share-server.py (partage par QR code)
    usr/lib/systemd/system/ lexos-perf.service, lexos-autoconnect.timer
    usr/share/lexos/        Listes de paquets optionnels
    etc/skel/               Configuration héritée par chaque compte
    etc/dconf/db/local.d/   Dock Plank + effets Compiz
  bootloaders/isolinux/     Écran du menu de démarrage

flavours/                   Paquets essentiels par saveur
tests/                      Tests exécutables (serveur de partage)
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

**Un paquet a disparu de Debian, ma construction va casser ?**
Non. Seuls les paquets vitaux (noyau, serveur X, XFCE, Firefox) sont
obligatoires. Tout le confort est installé en « best effort » par le hook
0250 : ce qui manque est noté dans `/etc/lexos/optional-report` et la
construction continue.

**Le partage par QR code, ça passe par internet ?**
Non. Le fichier ne quitte jamais ton réseau local : ton ordinateur sert une
page web, le téléphone la lit. Rien n'est téléversé nulle part, et le serveur
s'éteint tout seul au bout de 15 minutes.

**J'ai oublié le mot de passe du disque chiffré.**
Les données sont perdues. Il n'y a pas de récupération, pas de porte dérobée —
c'est précisément ce qui rend le chiffrement utile. Note la phrase secrète
ailleurs qu'à l'intérieur de la machine.

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
