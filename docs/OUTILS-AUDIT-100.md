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
