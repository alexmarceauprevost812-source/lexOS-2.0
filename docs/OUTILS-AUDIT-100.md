# Sélection LexOS Pro : 100 entrées d'outils

99 paquets Debian 13 amd64 et Johnny 2.2 compilé depuis Openwall.
Cette sélection n'est pas un classement officiel « top 100 Kali » : elle
couvre les usages réseau, web, Wi-Fi, mots de passe, fichiers et diagnostic.
Les paquets peuvent contenir plusieurs exécutables. Aucun dépôt Kali ajouté.
Installation dans le hook 0262, Pro seulement, sans Recommends. Un paquet
indisponible fait échouer la construction, au lieu de disparaître en silence.

## Reseau et DNS (25)

`nmap`, `ncat`, `ndiff`, `zenmap`, `masscan`, `netcat-openbsd`, `socat`, `tcpdump`, `tshark`, `wireshark`, `ngrep`, `tcpflow`, `tcpreplay`, `netsniff-ng`, `iperf3`, `mtr-tiny`, `traceroute`, `whois`, `bind9-dnsutils`, `dnsrecon`, `dnsenum`, `fierce`, `arp-scan`, `arping`, `hping3`

## Web et protocoles (17)

`curl`, `wget`, `openssl`, `gnutls-bin`, `sslscan`, `ssldump`, `testssl.sh`, `sqlmap`, `patator`, `gobuster`, `ffuf`, `dirb`, `wfuzz`, `whatweb`, `python3-impacket`, `python3-scapy`, `ssh-audit`

## Wi-Fi et interfaces (11)

`aircrack-ng`, `reaver`, `bully`, `wireless-tools`, `iw`, `rfkill`, `bluez`, `bluez-hcidump`, `macchanger`, `ethtool`, `iproute2`

## Mots de passe (11)

`john`, `hashcat`, `hashid`, `crunch`, `cewl`, `ophcrack`, `fcrackzip`, `pdfcrack`, `chntpw`, `medusa`, `hydra`

## Analyse de fichiers et recuperation (18)

`libimage-exiftool-perl`, `pngcheck`, `jpeginfo`, `exiv2`, `binwalk`, `foremost`, `scalpel`, `testdisk`, `extundelete`, `gddrescue`, `dc3dd`, `dcfldd`, `sleuthkit`, `autopsy`, `steghide`, `outguess`, `yara`, `7zip`

## Debogage et inspection (8)

`gdb`, `strace`, `ltrace`, `binutils`, `nasm`, `valgrind`, `hexedit`, `xxd`

## Audit systeme et donnees (9)

`lynis`, `chkrootkit`, `rkhunter`, `debsums`, `gitleaks`, `mat2`, `file`, `jq`, `sqlite3`

## Johnny (1)

Interface graphique de John Debian. La variante Debian n'est pas forcément
John Jumbo : certains formats et fonctions de Kali peuvent manquer.

## Limites et validation

Les 99 noms ont été vérifiés dans les index Debian trixie main/contrib/non-free
amd64 disponibles sur la machine de travail le 9 octobre 2026. Disponibilité
ne signifie pas fonctionnement testé pour chacun. La simulation APT locale a réussi sans installation réelle; la
construction devra encore vérifier les dépendances et le volume. Aucun outil ne
lance de scan, capture, récupération ou attaque automatiquement. L'installation
de certains paquets peut ajouter des services : vérifier leur état dans la VM
et la session live avant validation finale. Les opérations sur disques proposées
par les outils de récupération ne font pas partie de la préparation de l'ISO.
Les outils Wi-Fi dépendent de l'adaptateur et de son pilote, pas de la RTX 5060.
Seul le benchmark Hashcat MD5 CUDA est confirmé sur le PC de l'utilisateur.
Aucun changement de partitions ni de démarrage Windows effectué ici.

La taille compressée de l'ISO et l'espace installé restent à mesurer. Les
paquets sont présents dès le live et sur une installation issue de cette ISO;
une ISO déjà construite n'est pas modifiée rétroactivement.

## Un seul terminal : bouton Audit dans LexOS Pro Terminal

La demande est de garder l'icône **Terminal LexOS Pro** en haut du bureau
et d'accéder à l'audit **à l'intérieur** de ce terminal, plutôt que d'avoir
un terminal distinct réservé aux outils d'audit.

La barre du haut du terminal officiel comporte maintenant un bouton
**🛡 Audit**, près du bouton « + ». Le bouton crée un **nouvel onglet**
dans le **même LexOS Pro Terminal** et y saisit la commande fixe
`lexos audit`, à travers le vrai pseudo-terminal. Cela évite de
modifier la commande en cours dans un autre onglet.

`lexos audit` affiche un catalogue texte de **sept catégories** et
**100 entrées**. L'utilisateur choisit les catégories et peut afficher
les exécutables des paquets installés. **Aucune commande d'audit,
analyse ou action privilégiée ne démarre automatiquement**. La sortie
« non installé » ne déclenche aucune installation. On quitte avec
`q` pour revenir au terminal normal.

Les applications graphiques éventuellement ouvertes depuis l'ancien
catalogue GTK restent indépendantes, mais les fiches en console de ce
catalogue passent désormais par `lexos-pro-terminal`, plus par
`xfce4-terminal`. Le raccourci « Outils d'audit » du menu Applications
ouvre lui aussi le catalogue **dans le terminal officiel**.

### Barre XFCE et comptes existants

Le hook `0270-lexos-audit-menu.hook.chroot` n'ajoute **plus** de
deuxième icône Audit à la barre du haut des nouvelles ISO Pro.
L'icône **Terminal LexOS Pro** demeure celle qui ouvre le programme.
Le hook ne change pas le menu Applications ni les autres boutons.

Sur un **compte XFCE déjà existant**, `sudo miss a jour` met à jour
les scripts et le HTML du terminal, **sans écraser les raccourcis
personnels de la barre**. Si l'ancien bouton d'audit reste visible,
le retirer manuellement dans les Préférences du panneau XFCE
(Éléments → sélectionner le lanceur Audit → « - »). Ne pas restaurer
tout `/etc/skel` et ne pas supprimer le terminal principal.

### Essai sur LexOS installé

```bash
sudo miss a jour --essai
sudo miss a jour
lexos audit
```

Fermer puis relancer **LexOS Pro Terminal** depuis l'icône du haut pour
charger son nouveau HTML. Cliquer sur **🛡 Audit** et vérifier qu'un
nouvel onglet s'ouvre, puis sélectionner une catégorie. Les catégories
ne doivent pas déclencher d'analyse.

Les fichiers concernés sont le catalogue
`/usr/lib/lexos/audit/menu.py`, le terminal
`/usr/share/lexos/terminal-pro/web/index.html`, le lanceur
`/usr/share/applications/lexos-audit.desktop`, le répartiteur
`/usr/bin/lexos` et le hook 0270. Aucune ISO nouvelle n'est
publiée par ce changement.

### Tests et limites

`python3 tests/test_lexos_audit_menu.py` vérifie le catalogue, les
100 entrées, le choix par numéros, le refus d'entrées non valides,
l'absence de lancement automatique, l'appel du bon terminal et
l'absence de doublon dans le panneau d'une nouvelle ISO.
La CI exerce aussi l'ancien menu GTK facultatif sous Xvfb.

La validation sur une session XFCE réelle demeure nécessaire :
bouton visible, nouvel onglet avec vrai PTY, retour à l'invite shell
et conservation des raccourcis de l'utilisateur. Le catalogue ne
promet pas que tous les outils Debian installés ont été testés.


## LexOS 2.0.2 — toutes les commandes visibles dans le catalogue

L'entrée de menu du haut reste **Terminal LexOS Pro → 🛡 Audit**. Ce
catalogue contient toujours 100 entrées regroupées par sept catégories.
Pour **chaque paquet installé**, LexOS lit les fichiers que
**dpkg-query -L** déclare dans les répertoires exécutables usuels
(/usr/bin, /usr/sbin, /usr/local/bin, /usr/local/sbin, /bin, /sbin).
Il teste leur présence et le droit d'exécution, déduplique puis affiche
la liste *réellement constatée*. Le nom du paquet n'est jamais pris
automatiquement pour le nom d'un programme : exiftool par exemple
peut appartenir à un paquet nommé autrement.

Ce sont les **noms et chemins des exécutables**, pas la liste de toutes
leurs options et sous-commandes internes. Une option ou une sous-commande
n'apparaît que dans la documentation propre au programme; il serait
trompeur d'affirmer que dpkg les fournit. Le catalogue n'invente donc
ni syntaxes ni commandes, et **ne lance aucun outil automatiquement**.

Dans le terminal :

    lexos audit
    lexos audit commandes

Le premier ouvre le menu interactif ; le second recense d'un seul coup
les commandes de **tous les paquets effectivement installés** parmi les
100 entrées. Il montre « non installé » quand le paquet est absent,
sans procéder à une installation. Le nombre de commandes varie donc
selon les paquets présents sur la machine, pas selon un tableau figé.

L'ancien catalogue GTK facultatif (lancé directement par menu.py sans
option) affiche un bouton **Commandes** en face de chaque outil installé.
Un clic ouvre une fenêtre de texte sélectionnable, avec la liste
complète des exécutables du paquet, **sans les lancer**. L'ancienne
fonction d'activation du catalogue ne change pas.

### Première vague de vraies icônes Kali (facultative)

L'icône propre à un outil n'est pas inventée, ni tirée d'une recherche
d'images. La commande :

    lexos audit-icones etat
    lexos audit-icones installer

tente de récupérer les SVG de 12 outils prioritaires réellement
présents dans le manifeste LexOS :
nmap, zenmap, wireshark, hashcat, john, aircrack-ng, sqlmap, gobuster,
ffuf, hydra, binwalk et testdisk. **Ce sont douze candidats, pas une
promesse de douze logos trouvés**. Le script dira exactement quels SVG
existent dans cette version de Kali; pour chaque absent, le thème Debian
ou LexOS reste utilisé.

**Source authentique :** archive de sources du paquet officiel
**kali-menu 2026.3.4**, publiée le 11 septembre 2026 et migrée le
14 septembre 2026. Téléchargement chiffré en HTTPS, archive figée par
la somme SHA-256 **publiée par l'équipe Kali** :

    0f977fb202b94e0850e45cc4c5a97fa648936f325e6d5857f9839915ae032aa6

Références officielles :
- https://pkg.kali.org/news/712541/kali-menu-202634-migrated-to-kali-rolling/
- https://archive.kali.org/kali/pool/main/k/kali-menu/
- https://gitlab.com/kalilinux/packages/kali-menu/-/tree/kali/master/menu-icons

Le script ne télécharge **rien au démarrage**, n'extrait pas l'archive
dans /, n'exécute pas de programme du paquet, n'ajoute pas de
dépôt Kali et **refuse sudo**. Il copie uniquement des images SVG
statistiques vérifiées dans le dossier du compte utilisateur
~/.local/share/lexos/audit/icones/ (ou XDG_DATA_HOME). Un SVG avec
script, ressource externe ou contenu invalide est refusé.

**Attribution et marques :** les logos graphiques appartiennent
à leurs auteurs/titulaires. Kali signale que les licences des
composants peuvent varier et conseille de consulter leurs fichiers
de droits d'auteur. Le programme récupère les images uniquement
sur action explicite et n'embarque pas la collection dans l'ISO,
ni dans le dépôt GitHub. Les icônes qui ne sont pas couvertes par
un droit de redistribution clair ne doivent pas être ajoutées
automatiquement à une ISO publique.
Voir : https://www.kali.org/docs/policy/kali-linux-open-source-policy/

Aucune ISO n'est publiée, ni aucun thème Thunar ou bureau remplacé.
L'interface demande encore une vérification graphique sur le vrai PC.

### Mise à jour sur un compte LexOS Pro existant

    sudo miss a jour --essai
    sudo miss a jour
    lexos audit commandes
    lexos audit-icones etat

Pour rechercher volontairement les logos officiels, sans sudo :

    lexos audit-icones installer

Fermer puis relancer **LexOS Pro Terminal** avant d'ouvrir le bouton
🛡 Audit afin de charger les changements du HTML.
