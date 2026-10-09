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

## Bouton indépendant dans la barre du haut

Le hook Pro 0270 ajoute un lanceur « Outils d’audit » immédiatement après
le menu principal. Le menu principal conserve Ti-Lex; le nouveau bouton
emploie le dragon bleu Kali. La fenêtre suit le thème GTK LexOS, présente
les sept catégories ci-dessus et une recherche par nom ou catégorie.
Johnny est placé dans « Mots de passe ». Un outil absent est grisé avec
« non installé » : le bouton n’installe aucun paquet à votre place.

Johnny, Wireshark, Zenmap et Ophcrack ouvrent leur interface graphique,
sans sudo. Les autres entrées ouvrent un terminal XFCE, affichent les
exécutables réellement fournis par le paquet et indiquent `man NOM_DE_COMMANDE`.
Aucun scan, capture, test de mot de passe ou opération disque ne démarre au clic.
Les commandes d’Impacket, Scapy, Sleuthkit et autres familles sont ainsi
listées depuis le paquet installé, sans inventer de commande identique au
nom du paquet. L’élévation nécessaire à une opération reste à votre choix.

Le hook modifie uniquement le squelette de la future ISO Pro. Il choisit
un identifiant de greffon libre, conserve les autres éléments du panneau,
et ne duplique pas son bouton lorsqu’il est rejoué.
Pour un compte existant après la mise à jour des fichiers : clic droit
sur la barre → Tableau de bord → Ajouter de nouveaux éléments → Lanceur,
puis Propriétés du lanceur → Ajouter « Outils d’audit »; déplacer le bouton
près du menu principal. Ne pas remplacer tout votre panneau par `/etc/skel`.
Ce lanceur reste retirable depuis les propriétés de la barre XFCE.

Logo copié sans retouche depuis les ressources graphiques officielles Kali :
https://gitlab.com/kalilinux/documentation/graphic-resources,
commit `ace9d74f7a8894e9ed00967c19f6d6ce187c0712`, fichier
`kali-icon/circle-4/kali-dragon-circle-simple-blue.svg`.
Kali et son logo appartiennent à leurs titulaires; LexOS reste une sélection
Debian indépendante, sans dépôt Kali ni prétention d’être une distribution Kali.

Validation : tests du catalogue complet, préservation et idempotence du
panneau, séparation Pro/standard, lancement sans sudo, SVG et lanceur.
La CI exerce également l’affichage GTK et le filtrage sous Xvfb. L’apparence
finale sur la barre de la session live reste à vérifier avant l’ISO finale.

### Titre et logo à l’ouverture du terminal

Chaque terminal ouvert depuis le bouton porte le nom du paquet et affiche
un en-tête orange « NOM · Outils d’audit LexOS ». Si le paquet fournit un
lanceur avec une icône, ou si une icône à son nom existe dans le thème,
son image est rendue en petits blocs couleur dans le terminal XFCE
(24 × 24 pixels au maximum). Aucun logo n’est téléchargé au lancement.
Une image absente ou illisible conserve le titre. Les sorties redirigées,
`NO_COLOR` et les terminaux `dumb` restent en texte simple. Cela concerne
les ouvertures depuis le catalogue, pas toutes les commandes tapées à la main.
Le bouton Kali reste immédiatement à droite du menu Ti-Lex.
