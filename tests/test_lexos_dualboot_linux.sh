#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-dualboot — LexOS à côté d'UBUNTU sur le ThinkPad
# =============================================================================
#  ALEX : « j'aimerais aussi que LexOS Pro soit capable de se mettre à côté
#  d'Ubuntu 26.04.1 dans mon ThinkPad, ma vieille ordinateur, pour avoir 2
#  logiciels pour être capable de travailler avec les 2 ».
#
#  Le voisin Windows était déjà éprouvé (test_lexos_dualboot_bitlocker.sh,
#  dont ce banc reprend les faux outils). Ce banc-ci couvre ce qui manquait
#  pour un voisin LINUX, et surtout les deux pièges qui se voient TARD :
#    · UEFI d'un bord, BIOS de l'autre -> l'outil le dit FORT, avant tout
#      chiffre de place ;
#    · le GRUB d'Ubuntu ne cherche pas les voisins -> les trois commandes
#      côté Ubuntu sont affichées, prêtes à recopier ;
#    · l'EFI presque pleine -> l'avertissement sort avec le chiffre exact ;
#    · et le cas Ubuntu chiffré est NOMMÉ comme tel.
#
#  Tout tourne sur de faux outils injectés par un PATH en tête (lsblk,
#  parted, findmnt, mount/umount, df, efibootmgr). Le seam LEXOS_SANS_SBIN=1
#  documenté en tête de l'outil empêche les vrais sbin de doubler les faux.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-dualboot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-dualboot introuvable ou non exécutable"; exit 1; }

FAUXBIN="$BANC/bin"; mkdir -p "$FAUXBIN"
TABLE="$BANC/table"          # NAME FSTYPE SIZE PARTTYPE
FAUX_EFI="$BANC/efi"         # ce que la partition EFI contient, une fois « montée »
FAUX_SYS="$BANC/sys"         # /sys/firmware/efi présent ou non — via le faux test ci-dessous

#  ═══ LE FAUX lsblk SERT AUSSI PARTTYPE ═══
#  L'outil trouve la partition EFI par son TYPE (GUID c12a7328-… sur GPT,
#  0xef sur MS-DOS), pas par son nom. La table du banc porte donc une
#  quatrième colonne.
pose_table() { # pose_table "nom fstype taille parttype" ...
	printf '%s\n' "$@" > "$TABLE"
	cat > "$FAUXBIN/lsblk" <<EOF
#!/bin/sh
case "\$*" in
	*"NAME,FSTYPE,SIZE"*) awk '{print \$1, \$2, \$3}' "$TABLE" ;;
	*"NAME,PARTTYPE"*)    awk '{print \$1, (\$4 == "" ? "-" : \$4)}' "$TABLE" ;;
	*SIZE*)
		for a in \$*; do case "\$a" in /dev/*) d="\${a#/dev/}" ;; esac; done
		awk -v n="\$d" '\$1 == n { print \$3 }' "$TABLE"
		;;
	*PKNAME*)
		for a in \$*; do case "\$a" in /dev/*) d="\${a#/dev/}" ;; esac; done
		printf '%s\n' "\$(printf '%s' "\$d" | sed 's/p\{0,1\}[0-9]*\$//')"
		;;
	*) exit 0 ;;
esac
EOF
	chmod +x "$FAUXBIN/lsblk"
}

#  Le faux parted : la table (gpt / msdos) et l'espace libre.
pose_parted() { # pose_parted <gpt|msdos>
	cat > "$FAUXBIN/parted" <<EOF
#!/bin/sh
case "\$*" in
	*free*) printf 'BYT;\n/dev/nvme0n1:256GB:nvme:512:512:$1:disque;\n1:1.05MB:538MB:537MB:fat32::boot, esp;\n2:538MB:256GB:255GB:ext4::;\n' ;;
	*)      printf 'BYT;\n/dev/nvme0n1:256GB:nvme:512:512:$1:disque;\n' ;;
esac
EOF
	chmod +x "$FAUXBIN/parted"
}

#  findmnt : notre racine est la clé (loop0) ; l'EFI n'est montée nulle part
#  SAUF si le cas d'essai la déclare montée (alors on la sert depuis FAUX_EFI).
pose_findmnt() { # pose_findmnt [montee]
	cat > "$FAUXBIN/findmnt" <<EOF
#!/bin/sh
case "\$*" in
	*"SOURCE /"*) printf '/dev/loop0\n' ;;
	*TARGET*)     [ "${1:-}" = "montee" ] && printf '%s\n' "$FAUX_EFI" ;;
esac
exit 0
EOF
	chmod +x "$FAUXBIN/findmnt"
}

#  mount/umount : on ne monte rien, on SIMULE. Le faux mount copie le
#  contenu voulu dans le dossier temporaire que l'outil lui donne ; le faux
#  umount note qu'il a été appelé. Et le faux « id » dit qu'on est root,
#  sinon l'outil refuse (à raison) de monter.
pose_mount() {
	cat > "$FAUXBIN/mount" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$BANC/appels-mount"
dst="\$4"
cp -r "$FAUX_EFI/." "\$dst/" 2>/dev/null
exit 0
EOF
	cat > "$FAUXBIN/umount" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$BANC/appels-umount"
rm -rf "\$1"/* 2>/dev/null
exit 0
EOF
	printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$FAUXBIN/id"
	chmod +x "$FAUXBIN/mount" "$FAUXBIN/umount" "$FAUXBIN/id"
}

#  df : la place libre sur l'EFI, en kilo-octets.
pose_df() { # pose_df <total ko> <libre ko>
	cat > "$FAUXBIN/df" <<EOF
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/nvme0n1p1 %s %s %s 50%% /x\n' "$1" "\$(( $1 - $2 ))" "$2"
EOF
	chmod +x "$FAUXBIN/df"
}

#  efibootmgr : l'ordre de démarrage du micrologiciel.
pose_efibootmgr() { # pose_efibootmgr <premier: ubuntu|lexos>
	if [ "$1" = "ubuntu" ]; then ORDRE="0001,0002"; else ORDRE="0002,0001"; fi
	cat > "$FAUXBIN/efibootmgr" <<EOF
#!/bin/sh
printf 'BootCurrent: 0003\nTimeout: 0 seconds\nBootOrder: $ORDRE,0003\n'
printf 'Boot0001* ubuntu\nBoot0002* LexOS\nBoot0003* UEFI: USB Flash\n'
EOF
	chmod +x "$FAUXBIN/efibootmgr"
}

pose_ext4() { # pose_ext4 <blocs totaux> <blocs libres> <état>
	cat > "$FAUXBIN/dumpe2fs" <<EOF
#!/bin/sh
echo "Filesystem state:         $3"
echo "Block count:              $1"
echo "Free blocks:              $2"
echo "Block size:               4096"
EOF
	chmod +x "$FAUXBIN/dumpe2fs"
}

#  Le mode d'amorçage de la SESSION : l'outil lit /sys/firmware/efi, qu'on
#  ne peut pas créer. On laisse donc l'outil lire la vraie machine — et le
#  banc DIT dans quel mode il tourne, plutôt que de prétendre l'avoir
#  choisi. Les cas qui exigent un mode précis sont sautés si la machine
#  n'est pas dans ce mode, et le disent.
if [ -d /sys/firmware/efi ]; then MODE_BANC="UEFI"; else MODE_BANC="BIOS"; fi
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }

lance() { # lance [args] -> sortie ; code dans $BANC/code
	: > "$BANC/appels-mount"; : > "$BANC/appels-umount"
	PATH="$FAUXBIN:$PATH" LEXOS_SANS_SBIN=1 NO_COLOR=1 sh "$OUTIL" "$@" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

#  Le décor de base : un Ubuntu en ext4 nu de 255 Go (120 utilisés), une
#  EFI de 537 Mo avec EFI/ubuntu et EFI/BOOT dedans, table GPT.
decor_ubuntu() {
	pose_table "nvme0n1p1 vfat 537000000 c12a7328-f81f-11d2-ba4b-00a0c93ec93b" \
	           "nvme0n1p2 ext4 255000000000 0fc63daf-8483-4772-8e79-3d69d8477de4"
	pose_parted gpt
	pose_findmnt
	pose_mount
	rm -rf "$FAUX_EFI"; mkdir -p "$FAUX_EFI/EFI/ubuntu" "$FAUX_EFI/EFI/BOOT"
	pose_df 524288 300000        # 512 Mo, 293 Mo libres
	pose_efibootmgr lexos
	pose_ext4 62255859 32958984 clean   # 255 Go, 120 utilisés
}

# =============================================================================
titre "1. Voisin Ubuntu en ext4 nu -> trouvé, mesuré, et le message parle d'Ubuntu"
# =============================================================================
decor_ubuntu
S="$(lance)"
grep -q "un autre Linux occupe /dev/nvme0n1p2" <<< "$S" \
	&& ok "le voisin Linux est trouvé et nommé" \
	|| non "le voisin Linux n'a pas été vu :\n$S"
grep -q "40 Go pour LexOS" <<< "$S" \
	&& ok "la place conseillée est juste : 40 Go pour LexOS (120 utilisés sur 255, 10 laissés)" \
	|| non "le chiffre de découpe est absent ou faux :\n$S"
grep -qi "Ubuntu" <<< "$S" \
	&& ok "le message parle bien d'Ubuntu" \
	|| non "Ubuntu n'est nommé nulle part"
[ "$(cat "$BANC/code")" = "0" ] \
	&& ok "code de sortie 0 : un bilan, pas une erreur" \
	|| non "code $(cat "$BANC/code")"

# =============================================================================
titre "2. B2 — Les commandes côté Ubuntu sont affichées, prêtes à recopier"
# =============================================================================
#  Depuis GRUB 2.06 os-prober est désactivé par défaut ; le GRUB d'Ubuntu
#  effacerait LexOS de SON menu à sa prochaine mise à jour de noyau. Les
#  trois commandes doivent sortir, EXACTES, dans tous les cas où le voisin
#  est un Linux — pas seulement quand Ubuntu commande aujourd'hui.
for CMD in "sudo sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub" \
           "grep -q GRUB_DISABLE_OS_PROBER /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub" \
           "sudo update-grub"; do
	grep -qF -- "$CMD" <<< "$S" \
		&& ok "commande côté Ubuntu affichée : ${CMD:0:60}…" \
		|| non "commande manquante : $CMD"
done
grep -qi "pourquoi" <<< "$S" && grep -qi "efface LexOS de SON menu\|efface LexOS" <<< "$S" \
	&& ok "…et la raison est écrite en une phrase (sans elle, personne ne le refera dans six mois)" \
	|| non "la raison des trois commandes n'est pas donnée :\n$S"

#  Lequel des deux GRUB commande ? Lu dans BootOrder — pas deviné.
if [ "$MODE_BANC" = "UEFI" ]; then
	grep -q "c'est le GRUB de LexOS qui tient l'amorçage" <<< "$S" \
		&& ok "BootOrder 0002 (LexOS) en premier -> « c'est le GRUB de LexOS qui tient l'amorçage »" \
		|| non "l'outil ne dit pas que LexOS commande alors que BootOrder le met en premier :\n$S"
	pose_efibootmgr ubuntu
	S2="$(lance)"
	grep -q "c'est le GRUB du VOISIN qui tient l'amorçage" <<< "$S2" \
		&& ok "BootOrder 0001 (ubuntu) en premier -> « c'est le GRUB du VOISIN qui tient l'amorçage »" \
		|| non "l'outil ne dit pas que le voisin commande alors que BootOrder le met en premier :\n$S2"
	pose_efibootmgr lexos
else
	saut "banc en mode BIOS : la lecture de BootOrder (efibootmgr) n'est pas mesurée ici"
	grep -q "on ne sait pas lequel des deux GRUB commande" <<< "$S" \
		&& ok "en BIOS, l'outil DIT qu'il ne sait pas lequel commande — il n'invente pas" \
		|| non "en BIOS, l'outil prétend savoir qui commande :\n$S"
fi

# =============================================================================
titre "3. B3 — UEFI ↔ BIOS discordant -> dit FORT, et le chiffre de place est déclassé"
# =============================================================================
#  L'installation de juillet sur le ThinkPad avait une table MS-DOS
#  (signature BIOS). Si Ubuntu 26.04.1 se pose en UEFI sur le même disque,
#  aucun des deux ne verra l'autre. Ça doit être dit AVANT de toucher au
#  disque, pas après.
decor_ubuntu
pose_parted msdos
S="$(lance)"
if [ "$MODE_BANC" = "UEFI" ]; then
	grep -q "NE SERAIENT PAS DANS LE MÊME MODE D'AMORÇAGE" <<< "$S" \
		&& ok "session UEFI + table MS-DOS -> l'alerte de discordance sort, en majuscules" \
		|| non "session UEFI + table MS-DOS : aucune alerte de discordance :\n$S"
	grep -q "le chiffre de place ci-dessous ne sert à rien" <<< "$S" \
		&& ok "…et le chiffre de place est explicitement déclassé tant que ça ne concorde pas" \
		|| non "le chiffre de place est donné comme si de rien n'était"
	grep -q "les deux en UEFI" <<< "$S" \
		&& ok "…et la sortie recommandée est nommée : les deux en UEFI" \
		|| non "aucune marche à suivre pour la discordance :\n$S"
	#  L'ORDRE COMPTE : l'alerte doit sortir AVANT la section « LA PLACE ».
	L_ALERTE="$(grep -n "NE SERAIENT PAS DANS LE MÊME MODE" <<< "$S" | cut -d: -f1 | head -1)"
	L_PLACE="$(grep -n "LA PLACE POUR LEXOS" <<< "$S" | cut -d: -f1 | head -1)"
	if [ -n "$L_ALERTE" ] && [ -n "$L_PLACE" ] && [ "$L_ALERTE" -lt "$L_PLACE" ]; then
		ok "l'alerte (ligne $L_ALERTE) précède la section de place (ligne $L_PLACE)"
	else
		non "l'alerte ne précède pas la section de place (alerte=$L_ALERTE, place=$L_PLACE)"
	fi
else
	#  En BIOS, une table MS-DOS CONCORDE ; c'est un voisin en UEFI (EFI/ubuntu
	#  présent) qui discorde. Le décor a EFI/ubuntu : l'alerte doit sortir.
	grep -q "NE SERAIENT PAS DANS LE MÊME MODE D'AMORÇAGE" <<< "$S" \
		&& ok "session BIOS + voisin avec EFI/ubuntu -> l'alerte de discordance sort" \
		|| non "session BIOS + voisin UEFI : aucune alerte :\n$S"
	grep -q "UEFI Only" <<< "$S" \
		&& ok "…et la marche à suivre nomme le réglage du BIOS (UEFI Only)" \
		|| non "pas de marche à suivre BIOS -> UEFI :\n$S"
fi
#  ET QUAND ÇA CONCORDE, PAS D'ALERTE. Un contrôle qui ne sait pas se taire
#  apprend à ignorer le rouge.
decor_ubuntu
if [ "$MODE_BANC" = "BIOS" ]; then
	pose_parted msdos; rm -rf "$FAUX_EFI/EFI/ubuntu"
	pose_table "nvme0n1p2 ext4 255000000000 -"
fi
S="$(lance)"
if grep -q "NE SERAIENT PAS DANS LE MÊME MODE" <<< "$S"; then
	non "l'alerte sort alors que tout concorde (mode $MODE_BANC) :\n$S"
else
	ok "quand tout concorde (mode $MODE_BANC), aucune alerte — et « cohérent » est dit"
fi

# =============================================================================
titre "4. B4 — EFI presque pleine -> l'avertissement sort avec le bon chiffre"
# =============================================================================
decor_ubuntu
pose_df 102400 30720          # 100 Mo, 30 Mo libres
S="$(lance)"
grep -q "partition EFI presque pleine : 30 Mo libres sur 100 Mo" <<< "$S" \
	&& ok "30 Mo libres sur 100 -> « presque pleine », avec les DEUX chiffres exacts" \
	|| non "l'avertissement EFI est absent ou sans chiffre :\n$S"
grep -q "grub-install" <<< "$S" \
	&& ok "…et il nomme l'étape qui échouerait (grub-install, la dernière)" \
	|| non "l'avertissement ne dit pas ce qui échouerait"
#  Et avec de la place : pas d'avertissement, le chiffre quand même.
pose_df 524288 300000
S="$(lance)"
grep -q "partition EFI : 292 Mo libres sur 512 Mo" <<< "$S" \
	&& ok "292 Mo libres sur 512 -> pas d'alerte, et la mesure est affichée" \
	|| non "avec de la place, la mesure n'est pas affichée ou l'alerte sort quand même :\n$S"
#  ═══ ON N'A RIEN ÉCRIT : mount en LECTURE SEULE, et umount derrière ═══
if grep -q -- '-o ro' "$BANC/appels-mount" && [ -s "$BANC/appels-umount" ]; then
	ok "l'EFI a été montée en LECTURE SEULE (-o ro) et démontée après — le contrat « il lit » tient"
else
	non "montage non lecture-seule, ou pas de démontage : mount=« $(cat "$BANC/appels-mount") » umount=« $(cat "$BANC/appels-umount") »"
fi
#  Sans les droits : PAS de montage, et la mesure est dite NON MESURÉE.
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 1000; exit 0; }\nexec /usr/bin/id "$@"\n' > "$FAUXBIN/id"
S="$(lance)"
if [ ! -s "$BANC/appels-mount" ] && grep -q "NON MESURÉE" <<< "$S" && grep -q "sudo" <<< "$S"; then
	ok "sans les droits : aucun mount tenté, la place EFI est dite NON MESURÉE, et « sudo » est proposé"
else
	non "sans les droits : mount=« $(cat "$BANC/appels-mount") », sortie :\n$S"
fi
pose_mount

# =============================================================================
titre "5. B5 — Ubuntu chiffré : le cas est NOMMÉ, et la sortie simple vient d'abord"
# =============================================================================
pose_table "nvme0n1p1 vfat 537000000 c12a7328-f81f-11d2-ba4b-00a0c93ec93b" \
           "nvme0n1p3 crypto_LUKS 255000000000 0fc63daf-8483-4772-8e79-3d69d8477de4"
S="$(lance)"
grep -q "Ubuntu installé avec le chiffrement" <<< "$S" \
	&& ok "le cas est nommé comme Alex le reconnaîtra : « Ubuntu installé avec le chiffrement complet du disque »" \
	|| non "le cas chiffré n'est pas nommé en clair :\n$S"
L_SIMPLE="$(grep -n "La sortie simple" <<< "$S" | cut -d: -f1 | head -1)"
L_RESIZE="$(grep -n "1. resize2fs" <<< "$S" | cut -d: -f1 | head -1)"
if [ -n "$L_SIMPLE" ] && [ -n "$L_RESIZE" ] && [ "$L_SIMPLE" -lt "$L_RESIZE" ]; then
	ok "« laisser de l'espace libre AU MOMENT d'installer Ubuntu » vient AVANT les quatre commandes de réduction"
else
	non "la sortie simple ne précède pas resize2fs (simple=$L_SIMPLE, resize=$L_RESIZE)"
fi
grep -q "AU MOMENT d'installer" <<< "$S" \
	&& ok "…et elle dit bien : au moment d'installer, pas après coup" \
	|| non "le conseil « au moment d'installer » manque"

# =============================================================================
titre "6. « defaut » — lecture seule sans argument, refus propre sans droits"
# =============================================================================
decor_ubuntu
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 1000; exit 0; }\nexec /usr/bin/id "$@"\n' > "$FAUXBIN/id"
CHOIX="$BANC/dualboot-defaut"
rm -f "$CHOIX"
S="$(LEXOS_DUALBOOT_DEFAUT_FICHIER="$CHOIX" lance defaut)"
grep -q "aucun choix écrit" <<< "$S" && [ ! -e "$CHOIX" ] \
	&& ok "« defaut » sans argument : lit, dit qu'aucun choix n'est écrit, n'écrit rien" \
	|| non "« defaut » sans argument a écrit ou n'a rien dit :\n$S"
S="$(LEXOS_DUALBOOT_DEFAUT_FICHIER="$CHOIX" lance defaut voisin)"
if [ ! -e "$CHOIX" ] && grep -q "sudo lexos-dualboot defaut voisin" <<< "$S" && [ "$(cat "$BANC/code")" != "0" ]; then
	ok "« defaut voisin » sans droits : rien n'est écrit, la commande sudo exacte est donnée, code non nul"
else
	non "sans droits : fichier=$( [ -e "$CHOIX" ] && echo écrit || echo absent ), code $(cat "$BANC/code") :\n$S"
fi
S="$(LEXOS_DUALBOOT_DEFAUT_FICHIER="$CHOIX" lance defaut nimporte)"
[ "$(cat "$BANC/code")" = "2" ] && grep -q "lexos" <<< "$S" && grep -q "voisin" <<< "$S" \
	&& ok "« defaut nimporte » : refusé (code 2) en nommant les deux valeurs possibles" \
	|| non "une valeur inconnue n'est pas refusée proprement : code $(cat "$BANC/code")"

# =============================================================================
titre "7. Le résumé : Secure Boot peut RESTER activé, et la touche du ThinkPad"
# =============================================================================
#  Le résumé disait « Secure Boot → Disabled ». grub-efi-amd64-signed et
#  shim-signed sont OBLIGATOIRES dans lexos-core.list.chroot : le système
#  installé démarre Secure Boot actif. Ce conseil envoyait Alex désactiver
#  une protection pour rien.
decor_ubuntu
S="$(lance)"
if grep -q "Secure Boot → Disabled\|Secure Boot -> Disabled" <<< "$S"; then
	non "le résumé dit encore de DÉSACTIVER Secure Boot — LexOS embarque grub-efi-amd64-signed"
else
	ok "le résumé ne demande plus de désactiver Secure Boot"
fi
grep -q "rester activé" <<< "$S" \
	&& ok "…et il dit qu'il peut rester activé" \
	|| non "il ne dit pas que Secure Boot peut rester activé"
grep -q "F1 sur le ThinkPad" <<< "$S" \
	&& ok "…et la touche du BIOS du ThinkPad (F1) est nommée — pas seulement F2" \
	|| non "la touche du ThinkPad n'est pas nommée"
#  Et la preuve dans la liste de paquets, pas seulement dans le texte.
LISTE="$RACINE/config/package-lists/lexos-core.list.chroot"
grep -qxF "grub-efi-amd64-signed" < <(grep -Ev '^[[:space:]]*(#|$)' "$LISTE") \
	&& grep -qxF "shim-signed" < <(grep -Ev '^[[:space:]]*(#|$)' "$LISTE") \
	&& ok "grub-efi-amd64-signed et shim-signed sont bien au socle obligatoire : le conseil est fondé" \
	|| non "les paquets Secure Boot ne sont pas au socle : le conseil « rester activé » serait faux"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
