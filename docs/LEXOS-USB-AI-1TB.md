# LexOS Pro USB AI Edition — SSD externe 1 To

**Statut : phases 1 et 2 — diagnostic et configuration prêts, sans écriture.** Aucune installation USB,
aucune ISO USB AI, aucun partitionnement et aucun pilote supplémentaire ne sont
réalisés à ce stade. L'édition USB AI est une **branche de développement**,
pas une version publiée.

## Objectif

Faire démarrer LexOS Pro sur un SSD USB externe et conserver le système, les
fichiers et les modèles Ollama entre les redémarrages. Après téléchargement des
modèles et des composants nécessaires, les interactions IA doivent fonctionner
sans Internet. L'exécution CPU doit rester possible sur les machines sans NVIDIA.

## Matériel envisagé, non acheté

- SSD externe **1 To**, USB 3.2 Gen 2 (10 Gb/s) si le PC le permet ; connecteur
  USB-C avec câble ou adaptateur compatible avec les prises du PC.
- SSD de marque connue, garantie et endurance documentées ; préférer un vrai
  SSD portable à une petite clé USB ordinaire, moins adaptée aux écritures
  régulières des mises à jour et journaux.
- Un **second support de sauvegarde**, physiquement indépendant du SSD LexOS.
- L'ordinateur hôte fournit le processeur et la RAM ; les modèles Ollama
  dépendent des ressources de **chaque** machine. Une RTX 5060 peut accélérer
  le calcul sur une machine compatible, mais n'est pas un prérequis.

Un SSD vendu comme « 1 To » contient environ **931 Gio** avant formatage.

## Proposition d'aménagement — strictement théorique

| Volume | Taille indicative | Système possible | Fonction |
|---|---:|---|---|
| Démarrage UEFI | 1 Gio | FAT32 | EFI, chargeur de démarrage |
| Système LexOS | 120 Gio | ext4 | Linux et applications |
| Données persistantes | 690 Gio | ext4 | `/data`, Ollama, projets, fichiers |
| Récupération locale | 100 Gio | ext4 | Copies de récupération, pas une sauvegarde anti-panne |
| Réserve | ~20 Gio | non alloué | Marge d'ajustement |

Ces valeurs **ne sont pas des commandes**. Elles seront revues après identification
du vrai matériel, vérification de la capacité, sauvegarde préalable et accord
explicite. Aucun automatisme d'installation/effacement n'est prévu.

Pour protéger les données en cas de perte, vol ou défaillance du SSD, les
sauvegardes chiffrées doivent résider sur **un autre support** ; une partition
« récupération » sur le même SSD ne suffit pas.

## Phase 1 — maintenant, même sans SSD

1. Branche `feature/lexos-usb-ai-1tb` basée sur `main`.
2. Inventaire **sans sudo et sans écriture** :

   ```bash
   python3 tools/lexos-usb-ai-inventaire.py
   ```

   Variante pour les tests automatiques :

   ```bash
   python3 tools/lexos-usb-ai-inventaire.py --json
   ```

   L'outil ne fait qu'appeler `lsblk` ; il n'effectue **jamais** de
   `mkfs`, `dd`, `wipefs`, `parted`, `mount` ou installation. Un statut
   « USB détecté » n'autorise pas le formatage. Même une sortie sans montage
   peut manquer d'informations : confirmation humaine obligatoire.
3. Tests sans périphérique réel, via le workflow `usb-ai.yml` :

   ```bash
   python3 tests/usb_ai_inventaire_checks.py
   ```

4. Gabarit de configuration Ollama **non activé** :
   `usb-ai/ollama/offline.env.example`. Le stockage des modèles sera
   `/data/ollama/models`, le serveur écoutera seulement sur `127.0.0.1`.


## Phase 2 — stockage persistant et prévol Ollama (code prêt, NON activé)

Cette étape ajoute des composants vérifiables sur GitHub **avant l'achat**,
sans créer de système de fichiers, sans téléchargement de modèle et sans
modifier les disques. Elle **ne construit pas encore un système USB amorçable**.

- `usb-ai/ollama/doctor.py` : diagnostic Python en lecture seule. Il vérifie si
  `/data` est réellement un point de montage, si le dossier des modèles existe,
  si Ollama est installé et si le gabarit systemd a été déployé.
- `usb-ai/systemd/ollama.service.d/10-lexos-usb-ai.conf` : gabarit de
  configuration du service Ollama avec stockage des modèles dans
  `/data/ollama/models`, serveur limité à l'ordinateur local et mode sans cloud.
  **Non installé**. Le service ne doit pas démarrer tant que `/data` n'est pas
  monté, afin de ne pas remplir par erreur la partition système.
- `tests/usb_ai_phase2_checks.py` : scénarios isolés (volume absent, volume
  simulé, lien symbolique, diagnostic JSON, mode strict, cohérence systemd).
- `.github/workflows/usb-ai.yml` : validation automatique des deux phases.

Commandes à exécuter plus tard sur un Linux de développement (lecture seule) :

```bash
python3 usb-ai/ollama/doctor.py
python3 usb-ai/ollama/doctor.py --json
python3 tests/usb_ai_phase2_checks.py
```

Si le SSD n'est pas encore présent, l'état « préparation incomplète » est
**normal**. Le diagnostic n'assure **jamais** qu'un modèle répond hors ligne ;
ce contrôle nécessitera un essai réel après installation et préchargement.

### Garde-fous avant phase 3

1. Pas de partitionnement ou d'installation sans identification certaine du
   SSD externe, sauvegarde et validation humaine.
2. Aucun automatisme ne doit installer le gabarit systemd tant que la
   partition persistante n'est pas montée, testée et correctement autorisée.
3. L'ISO pro et ses pilotes NVIDIA doivent réussir leurs vérifications
   indépendamment ; le gabarit Ollama n'en donne aucune garantie.
4. Les sauvegardes vitales doivent être conservées sur un **second disque**.

## Étapes suivantes — NON réalisées

- Phase 3 (à venir) : construction/test **en machine virtuelle ou sur un SSD neuf**, avec
  installation persistante dédiée au SSD externe ; préserver le disque interne.
- Phase 4 (à venir) : Ollama installé, versions de modèles téléchargées et contrôlées
  (exemple envisagé : `qwen2.5-coder:7b`), test réseau coupé puis redémarrage.
- Phase 5 (à venir) : assistant capable de proposer des corrections, les tester dans des
  branches isolées et demander validation avant toute fusion.
- Phase 6 (à venir) : sauvegarde/restauration chiffrée testée sur un second support.
- Phase 7 (à venir) : essais réels BIOS/UEFI, périphériques divers, GPU NVIDIA ou CPU,
  puis Secure Boot avec signatures et inscription de clés adaptées à la machine.

**Important :** une clé MOK inscrite sur un PC ne garantit pas la confiance
Secure Boot sur un autre PC. Les correctifs LexOS 2.0.2 sont développés dans
une autre branche ; ils ne sont pas considérés comme validés par ce document.

Aucune image ISO USB AI n'est publiée à l'issue de la phase 2.
