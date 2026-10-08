# Outils de sécurité disponibles dans Kali

LexOS reste une distribution basée sur Debian. La commande `lexos outils-kali`
installe à la demande une sélection d'outils également disponibles dans Kali,
depuis les dépôts APT déjà configurés. Elle n'ajoute aucun dépôt et ne transforme
pas LexOS en Kali. Les versions proposées sont celles de ces dépôts.

```bash
lexos outils-kali liste
lexos outils-kali installer reseau --essai
sudo lexos outils-kali installer reseau
lexos outils-kali etat
```

| Groupe | Paquets |
| --- | --- |
| reseau | nmap, wireshark, tshark |
| web | sqlmap |
| wifi | aircrack-ng |
| mots-de-passe | john, hydra |
| tous (défaut) | Tous les paquets ci-dessus |

`lexos kali` est un alias. `--essai` utilise les index locaux sans les rafraîchir
et sans droits administrateur. L'installation réelle rafraîchit les index,
simule la résolution, puis laisse APT présenter les changements et demander
confirmation. Si des paquets sont indisponibles ou si la résolution exige une
suppression, elle échoue. Une interruption pendant l'installation peut laisser
certains paquets installés : consulter `etat` et les messages APT.

Les outils sont optionnels et ne sont pas installés pendant la construction ISO.
Une installation dans une session live sans persistance disparaît au redémarrage.
L'installation ne lance aucun audit. La capture Wireshark dépend des permissions
de capture; les fonctions Wi-Fi dépendent de l'adaptateur et de son pilote.
Pour retirer un paquet choisi : `sudo lexos remove sqlmap`, par exemple.

Le catalogue n'inclut pas tous les outils ni les méta-paquets Kali. Pour un outil
exclusif à Kali, utiliser une machine virtuelle Kali distincte. Ne pas ajouter
`kali-rolling` aux sources APT de LexOS : Kali déconseille explicitement d'ajouter
ses dépôts à une autre distribution.

Références : [dépôts Kali](https://www.kali.org/docs/general-use/kali-linux-sources-list-repositories/),
[paquets Debian](https://packages.debian.org/trixie/).
