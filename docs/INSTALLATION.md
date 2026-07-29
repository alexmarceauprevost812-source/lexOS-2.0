# Installer LexOS — du fichier ISO à la machine

Ce guide suit l'ordre prudent : **on essaie d'abord, on efface après.**

---

## Étape 0 — Ce que tu vas faire

```
ISO  →  clé USB  →  session DÉMO (sans risque)  →  installation (optionnelle)
```

Les trois premières étapes ne touchent **jamais** ton disque dur. Seule la
quatrième peut effacer des données, et elle te le demandera clairement.

### Quel chemin prendre ?

La clé USB n'est pas le seul moyen d'arriver au bureau LexOS. Choisis selon
ce que tu veux faire :

| Tu veux… | Prends | Touche à ton disque ? |
|---|---|---|
| Juste voir à quoi ça ressemble, tout de suite | **[Machine virtuelle](#autre-moyen-1--machine-virtuelle-lexos-comme-un-simple-logiciel)** | Non, jamais |
| Essayer sur ta vraie machine (vrai matériel, vraie vitesse) | Étapes 2 et 3 (clé USB) | Non |
| Garder plusieurs ISO sur une seule clé | **[Ventoy](#autre-moyen-2--ventoy-la-clé-sans-rien-graver)** | Non |
| Démarrer l'ISO sans aucune clé USB | **[Boucle GRUB](#autre-moyen-3--démarrer-liso-depuis-le-disque-sans-clé-usb)** | Non (lecture seule) |
| LexOS **à côté** de Windows, pour de bon | Étape 4 → « Installer à côté » | Oui — repartitionne |
| LexOS **seul** sur la machine | Étape 4 → « Effacer le disque » | Oui — efface tout |

> **Aucune ISO encore ?** Tous ces chemins partent du même fichier `.iso`.
> Commence par l'**Étape 1**.

---

## Étape 1 — Obtenir l'ISO

### Option A — la construire toi-même

```bash
git clone https://github.com/alexmarceauprevost812-source/logiciel-ti-lex-.git
cd logiciel-ti-lex-
make check
make build
```

### Option B — la faire construire par GitHub

Onglet **Actions** du dépôt → workflow **« Construire l'ISO »** →
**Run workflow** → choisis la saveur. Au bout d'une heure environ, l'ISO est
téléchargeable en artefact au bas de la page du job.

### Vérifier l'intégrité

```bash
sha256sum -c lexos-1.0-standard-amd64.iso.sha256
```

Si la réponse n'est pas `OK`, l'ISO est corrompue : recommence le
téléchargement plutôt que de graver un fichier abîmé.

---

## Étape 2 — Écrire l'ISO sur une clé USB

Il te faut une clé d'au moins **4 Go** (8 Go pour la saveur `full`). **Tout ce
qu'elle contient sera effacé.**

### Depuis Linux

```bash
lsblk               # identifie la clé — regarde bien la taille !
```

```
NAME   SIZE TYPE MOUNTPOINTS
sda    477G disk               ← disque dur interne : NE PAS TOUCHER
├─sda1   1G part /boot/efi
└─sda2  476G part /
sdb     15G disk               ← la clé USB, c'est celle-là
└─sdb1   15G part /media/lex/USB
```

```bash
make usb DEVICE=/dev/sdb
```

La commande affiche le périphérique visé et attend que tu tapes `OUI`.

Sans le Makefile :

```bash
sudo umount /dev/sdb* 2>/dev/null
sudo dd if=lexos-1.0-standard-amd64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sync
```

> `of=` prend le **disque entier** (`/dev/sdb`), jamais une partition
> (`/dev/sdb1`). Relis la ligne avant d'appuyer sur Entrée : `dd` ne demande
> aucune confirmation.

### Depuis Windows ou macOS

Utilise [balenaEtcher](https://etcher.balena.io/) : sélectionne l'ISO,
sélectionne la clé, clique sur *Flash*. Il refuse par sécurité d'écrire sur un
disque système.

---

## Autre moyen 1 — Machine virtuelle (LexOS comme un simple logiciel)

C'est le moyen **le plus sûr** et le plus rapide : LexOS s'ouvre dans une
fenêtre, comme n'importe quel programme. Ton disque dur n'est jamais touché,
aucune partition n'est modifiée, et tu peux tout casser sans conséquence.

### Depuis Windows ou macOS — VirtualBox

1. Installe [VirtualBox](https://www.virtualbox.org/) (gratuit, libre).
2. **Nouvelle** → nom `LexOS`, type *Linux*, version *Debian (64-bit)*.
3. Mémoire : **4096 Mio** (2048 minimum pour la saveur `minimal`).
4. Disque virtuel : **25 Go** dynamiquement alloué — c'est un fichier sur ton
   disque, pas une partition.
5. Une fois créée : **Configuration** → *Système* → *Carte mère* → coche
   **Activer l'EFI**. LexOS démarre en UEFI comme les machines modernes.
6. **Configuration** → *Stockage* → clique le lecteur optique vide → choisis
   ton fichier `.iso`.
7. **Démarrer**. Le menu LexOS apparaît : prends **Live**.

Pour installer LexOS *dans* la machine virtuelle (et le garder d'une fois à
l'autre), lance `lexos install-disk` **à l'intérieur** de la fenêtre : il
n'écrit alors que dans le disque virtuel de 25 Go, jamais sur ton vrai disque.

> **Écran trop petit ?** *Écran* → *Affichage* → mets la mémoire vidéo à
> 128 Mio et le contrôleur graphique à `VMSVGA`.

### Depuis Linux — QEMU, sans rien installer de plus

Si tu es déjà dans le dépôt :

```bash
make test           # démarrage BIOS
make test-uefi      # démarrage UEFI (exige le paquet ovmf)
```

---

## Autre moyen 2 — Ventoy (la clé sans rien graver)

Avec [Ventoy](https://www.ventoy.net/), tu prépares la clé **une seule fois**,
puis tu **copies-colles** les fichiers `.iso` dessus comme des fichiers
ordinaires. Tu peux en garder plusieurs et choisir au démarrage.

1. Installe Ventoy sur la clé (⚠ cette étape-là efface la clé, une fois).
2. Glisse-dépose `lexos-1.0-standard-amd64.iso` sur la clé, comme un fichier.
3. Redémarre, choisis la clé dans le menu de démarrage, puis LexOS dans la
   liste que Ventoy affiche.

Avantage : pour tester une nouvelle version, tu remplaces juste le fichier.
Pas besoin de regraver.

---

## Autre moyen 3 — Démarrer l'ISO depuis le disque, sans clé USB

Si tu as **déjà un Linux avec GRUB** sur la machine, tu peux démarrer l'ISO
posée sur ton disque dur, sans aucune clé. GRUB la lit **en lecture seule** —
rien n'est écrit, rien n'est effacé.

1. Pose l'ISO quelque part de stable, par exemple `/boot/iso/lexos.iso`.
2. Ajoute ceci à `/etc/grub.d/40_custom` :

```sh
menuentry "LexOS 1.0 (démo depuis le disque)" {
    set isofile="/boot/iso/lexos.iso"
    loopback loop $isofile
    linux (loop)/live/vmlinuz boot=live findiso=$isofile components quiet splash
    initrd (loop)/live/initrd.img
}
```

3. `sudo update-grub`, puis redémarre et choisis l'entrée.

⚠ Ça ne marche **pas** depuis Windows seul (Windows n'a pas GRUB), et le
chemin `/boot/iso/` doit être sur une partition que GRUB sait lire (ext4 ou
FAT32 conviennent ; un `/boot` chiffré, non).

---

## Étape 3 — Démarrer en session démo

1. Laisse la clé branchée et redémarre l'ordinateur.
2. Au tout début du démarrage, appuie répétitivement sur la touche du menu de
   démarrage : souvent `F12`, parfois `F11`, `F9`, `Échap` ou `Suppr`. Le
   fabricant l'affiche brièvement au premier écran.
3. Choisis la ligne qui correspond à ta clé (`USB`, `UEFI: SanDisk…`).
4. Dans le menu LexOS, prends **Live**.

Après quelques secondes, tu es sur le bureau LexOS, connecté en tant que
`lex`. L'écran de bienvenue s'ouvre.

### Ce que tu peux faire sans aucun risque

* Ouvrir un terminal et taper `lexfetch`, `lexos doctor`, `lexos help`.
* Changer la couleur des boutons : `lexos accent violet`.
* Vérifier que le Wi-Fi, le son, l'écran et le pavé tactile fonctionnent.
* Installer des logiciels, ouvrir tes fichiers, naviguer sur le web.

Tout disparaît au redémarrage. **Ton disque dur n'a pas été ouvert.**

Pour t'en assurer :

```bash
lexos demo
```

### Si le démarrage échoue

| Symptôme | Piste |
|---|---|
| La clé n'apparaît pas dans le menu | Désactive *Secure Boot* dans le BIOS/UEFI, ou active le mode *Legacy/CSM* |
| Écran noir après le menu | Rechoisis l'entrée Live et ajoute `nomodeset` aux options de démarrage (touche `e` sur l'entrée) |
| Bureau très lent | Normal en démo : tout tourne depuis l'USB. Ce sera bien plus rapide une fois installé |
| Pas de Wi-Fi | Certaines cartes ont besoin d'un firmware absent. Branche un câble réseau puis `lexos update` |

---

## TI-LEX-OS Pro — l'édition pour jouer

Une **ISO à part**, pas une option à cocher. Même socle que LexOS, mais
assemblée pour une machine de jeu :

| | LexOS standard | TI-LEX-OS Pro |
|---|---|---|
| Pilotes Vulkan et Mesa | à installer | **déjà là** |
| Wine (jeux Windows) | à installer | **déjà là** |
| Steam + Proton | à installer | **déjà là** |
| Lutris, GameMode, MangoHud | à installer | **déjà là** |
| Manettes (Steam, Xbox, PS) | règles à ajouter | **reconnues au branchement** |
| Émulateurs | à installer | RetroArch, Dolphin, PPSSPP, mGBA, ScummVM |
| Jeux libres pour démarrer | aucun | SuperTuxKart, 0 A.D., Minetest, OpenTTD, Xonotic |

Le système s'annonce sous son propre nom — écran de démarrage, « À propos »,
`lexfetch` — parce que ce n'est pas le même produit.

### Faire construire l'ISO Pro

Dans `.iso-build-request`, mets `flavour: pro` et incrémente `build:` :

```yaml
flavour: pro
build: 8
```

Pousse : GitHub Actions produit `lexos-1.0-pro-amd64.iso`, à côté de
l'édition standard. En local : `sudo ./build.sh --flavour pro`.

### Les jeux Windows

Deux chemins, et ils ne se valent pas :

* **Steam → Proton.** Le plus simple. Steam installe Proton tout seul ; dans
  les propriétés d'un jeu, coche *Forcer l'utilisation d'un outil de
  compatibilité*. La plupart des jeux démarrent sans autre réglage.
* **Lutris.** Pour ce qui n'est pas sur Steam — GOG, Epic, un installeur
  `.exe` trouvé ailleurs. Lutris applique des scripts écrits par d'autres
  joueurs pour chaque jeu.

Ce qui ne marchera pas, et il vaut mieux le savoir avant d'essayer : les
jeux en ligne dont l'anti-triche refuse Linux — c'est un refus délibéré de
leur éditeur, pas une limite technique de LexOS. `lexos game info` affiche
ce que la machine sait faire (Vulkan, GameMode, MangoHud) avant de lancer.

---

## Sur un Mac

« Est-ce que ça tourne sur du Apple ? » n'a pas une seule réponse. Il y a
trois familles de Mac, et elles n'ont presque rien en commun.

| Machine | LexOS démarre ? | Ce qu'il faut savoir |
|---|---|---|
| **Mac Intel 2008-2017** | Oui | Comme sur un PC UEFI. Wi-Fi Broadcom à régler |
| **Mac Intel 2018-2020** (puce T2) | Oui, avec réserves | Clavier et souris **USB** obligatoires |
| **Mac Intel 2006-2008** (EFI 32 bits) | Oui, en mode BIOS | Choisir l'entrée « Windows » dans le menu ⌥ |
| **Mac 2006** (Core Duo) | Non | Processeur 32 bits |
| **Mac M1 · M2 · M3 · M4** | **Non** | Ce n'est pas un processeur x86 |

Pour savoir dans quelle case tombe une machine précise, sans rien installer :
le panneau **Paramètres → Matériel → Mac (Apple)** de la
[démo en ligne](https://alexmarceauprevost812-source.github.io/logiciel-ti-lex-/)
donne le verdict modèle par modèle. Une fois LexOS démarré, `lexos mac` fait le
même travail sur la machine réelle.

### Mac Intel (2008-2017) — le cas simple

1. Écris l'ISO sur une clé USB avec `dd` — pas un copier-coller :

   ```bash
   diskutil list                     # trouver le numéro N de la clé
   diskutil unmountDisk /dev/diskN
   sudo dd if=lexos-1.0-standard-amd64.iso of=/dev/rdiskN bs=4m status=progress
   ```

2. Redémarre en tenant **Option (⌥)**.
3. Choisis **EFI Boot**.

Une fois sur le bureau :

```bash
lexos mac              # bilan de la machine
lexos mac wifi         # quel pilote Broadcom il faut, d'après l'identifiant PCI
lexos mac clavier fonction   # F1..F12 redeviennent de vraies touches F
lexos mac ventilateur        # qu'ils accélèrent quand ça chauffe
```

Les deux derniers comptent plus qu'ils n'en ont l'air. Sous Linux, **rien ne
pilote les ventilateurs d'un Mac** tant que `mbpfan` n'est pas lancé : la
machine chauffe en silence. Et la rangée F d'Apple pilote la luminosité, pas
les touches F — ce que la plupart des raccourcis Linux attendent.

Pour installer à côté de macOS, réduis d'abord la partition depuis
l'Utilitaire de disque **de macOS**. Redimensionner de l'APFS depuis Linux
n'est pas fiable.

### Mac à puce T2 (2018-2020) — ça marche, mais lis d'abord

Avant même de brancher la clé :

1. Redémarre en tenant **Commande + R** → Utilitaires →
   **Utilitaire de sécurité au démarrage**.
2. Sécurité au démarrage : **Aucune sécurité**.
3. Démarrage externe : **Autoriser**.

Sans ces deux réglages, le Mac refuse la clé sans rien expliquer.

Ensuite, **avec le noyau Debian d'origine que livre LexOS**, ceci ne
fonctionnera pas :

* le clavier et le pavé tactile internes → il faut un clavier et une souris USB ;
* le son interne ;
* le Wi-Fi interne (son micrologiciel est propre à la machine et vit dans macOS) ;
* le SSD interne peut rester invisible — donc pas d'installation dessus.

Ces quatre points demandent le noyau modifié du projet
[t2linux](https://t2linux.org). LexOS ne le livre pas : c'est un noyau à part,
qui suit son propre calendrier de correctifs. Nous préférons un noyau Debian
qui reçoit les mises à jour de sécurité, et le dire franchement, plutôt qu'une
promesse tenue par un noyau figé.

### Mac Apple Silicon (M1, M2, M3, M4) — non

Ce n'est pas un manque de réglage, c'est un autre processeur. Les puces M sont
en ARM ; l'ISO de LexOS est compilée pour amd64. Le firmware ne saura même pas
la lire.

La seule façon de faire tourner Linux sur ces machines aujourd'hui est
[Asahi Linux](https://asahilinux.org), qui a dû écrire son propre amorceur
(m1n1) et une bonne part des pilotes par rétro-ingénierie. LexOS ne se pose pas
dessus : ce serait une distribution entièrement différente, à recompiler pour
arm64 et à rebâtir sur leur noyau.

Ce qui reste possible :

* **LexOS dans une machine virtuelle x86** (UTM en mode émulation) — ça marche,
  c'est lent, tout est traduit instruction par instruction ;
* **Debian arm64 dans UTM ou Parallels** — rapide et complet, mais ce n'est
  pas LexOS.

---

## Étape 4 — Installer sur le disque (seulement si tu es convaincu)

### Avant de cliquer

- [ ] Tu as **essayé** la session démo et tout fonctionne.
- [ ] Tu as **sauvegardé** tes fichiers importants sur un disque externe.
- [ ] L'ordinateur est **branché sur le secteur**.
- [ ] Tu sais si tu veux **effacer le disque** ou **installer à côté** de ton
      système actuel.

### Lancer

Double-clique sur **« Installer LexOS sur le disque »**, ou en terminal :

```bash
lexos install-disk
```

Un avertissement s'affiche avec la liste des disques détectés. En mode
graphique il faut cliquer sur **« J'ai compris, installer »** ; en console il
faut taper `EFFACER` en toutes lettres. N'importe quoi d'autre annule.

### Les choix de l'installateur

| Choix | Ce que ça fait |
|---|---|
| **Effacer le disque** | Supprime **tout** et installe LexOS seul. Irréversible. |
| **Installer à côté** | Réduit la partition existante et installe LexOS à côté. Un menu au démarrage te laisse choisir. |
| **Partitionnement manuel** | Tu décides de chaque partition. Réservé à ceux qui savent. |

En cas de doute : **installer à côté**. Tu gardes ton système actuel et tu peux
revenir en arrière.

### Après l'installation

1. Éteins, **retire la clé USB**, rallume.
2. Connecte-toi avec le compte créé pendant l'installation.
3. Mets le système à jour :

```bash
lexos update
lexos upgrade
```

4. Vérifie que tout va bien :

```bash
lexos doctor
```

---

## Désinstaller LexOS

Il n'y a pas de « désinstalleur ». Selon ton cas :

* **LexOS seul sur le disque** — démarre l'installateur d'un autre système et
  laisse-le reformater le disque.
* **LexOS à côté d'un autre système** — supprime ses partitions avec GParted
  depuis une clé live, puis restaure le chargeur de démarrage de l'autre
  système (`bootrec /fixmbr` depuis un support de réparation Windows, par
  exemple).

Sauvegarde avant, dans les deux cas.

---

## Aide

* `lexos doctor` — diagnostic automatique
* `lexos logs` — dernières erreurs du système
* [Ouvrir un ticket](https://github.com/alexmarceauprevost812-source/logiciel-ti-lex-/issues)
  en joignant la sortie de `lexos doctor` et `lexos version`
