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
