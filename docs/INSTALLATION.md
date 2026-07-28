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
