#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-dualboot — un Windows chiffré n'est pas un disque vide
# =============================================================================
#  BitLocker ne présente pas « ntfs » à lsblk mais « BitLocker » : la
#  recherche d'origine (trouver_windows) ne trouvait donc rien sur un disque
#  chiffré, et l'outil concluait « aucune partition Windows — l'installateur
#  proposera d'utiliser tout le disque ». Sur une machine où Windows est
#  simplement verrouillé, c'était une invitation à l'effacer en croyant
#  installer à côté.
#
#  Pas le cas de l'Alienware d'Alex aujourd'hui (BitLocker inactif, vérifié
#  dans le registre) — c'est un piège DORMANT : Windows 11 active le
#  chiffrement tout seul après certaines mises à jour ou une connexion à un
#  compte Microsoft.
#
#  Ce banc rejoue l'outil réel (lsblk est le seul rouage qu'on remplace) et
#  vérifie trois choses : le cas chiffré parle clairement et NE PRÉTEND PAS
#  qu'il n'y a pas de Windows ; le cas normal (NTFS en clair) n'est pas
#  troublé par la nouvelle recherche ; et l'outil, fidèle à sa nature de
#  bilan qui ne s'arrête jamais en cours de route, va bien jusqu'au bout —
#  BitLocker n'est pas un motif pour couper le reste du diagnostic (menu de
#  démarrage, UEFI), qui reste vrai et utile quel que soit l'état de Windows.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-dualboot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
#  « %b » ET PAS « %s » : plusieurs messages de ce banc joignent la sortie de
#  l'outil derrière un « \n ». Avec %s, cette séquence s'affichait telle
#  quelle — « :\n » — et la sortie qui devait expliquer l'échec restait
#  invisible. Un rouge qui ne montre pas ce qu'il a vu fait perdre le temps
#  qu'il était censé faire gagner.
non()  { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-dualboot introuvable ou non exécutable"; exit 1; }

FAUXBIN="$BANC/bin"
TABLE="$BANC/table"   # les lignes NAME FSTYPE SIZE que le faux lsblk sert

pose_table() { # pose_table "nom1 fstype1 taille1" "nom2 fstype2 taille2" ...
	mkdir -p "$FAUXBIN"
	printf '%s\n' "$@" > "$TABLE"
	cat > "$FAUXBIN/lsblk" <<EOF
#!/bin/sh
#  Trois formes suffisent, et ce sont les trois que l'outil emploie :
#    · "-brno NAME,FSTYPE,SIZE" sans périphérique : toute la table ;
#    · "-brno SIZE /dev/xxx"    : la taille de CETTE partition ;
#    · "-rno PKNAME /dev/xxx"   : le disque qui la porte.
#  Les deux dernières ont été ajoutées avec le voisin Linux : sans elles, sa
#  taille revenait vide et le banc mesurait un disque de 0 Go — vert, et
#  ne prouvant rien.
case "\$*" in
	*"NAME,FSTYPE,SIZE"*) cat "$TABLE" ;;
	*SIZE*)
		for a in \$*; do case "\$a" in /dev/*) d="\${a#/dev/}" ;; esac; done
		awk -v n="\$d" '\$1 == n { print \$3 }' "$TABLE"
		;;
	*PKNAME*)
		for a in \$*; do case "\$a" in /dev/*) d="\${a#/dev/}" ;; esac; done
		printf '%s\\n' "\${d%%[0-9]*}"
		;;
	*) exit 0 ;;
esac
EOF
	chmod +x "$FAUXBIN/lsblk"
	#  Par défaut, notre racine n'est AUCUNE partition du disque : on est sur
	#  la clé USB, comme Alex le sera. Les essais qui veulent le contraire
	#  reposent findmnt eux-mêmes.
	pose_racine "/dev/loop0"
}

#  Ce que « findmnt -no SOURCE / » répondra — c'est-à-dire NOTRE racine.
pose_racine() { # pose_racine <source>
	mkdir -p "$FAUXBIN"
	cat > "$FAUXBIN/findmnt" <<EOF
#!/bin/sh
printf '%s\\n' "$1"
EOF
	chmod +x "$FAUXBIN/findmnt"
}

#  Ce que dumpe2fs racontera du voisin ext4 : place et propreté.
pose_ext4() { # pose_ext4 <blocs totaux> <blocs libres> <état>
	mkdir -p "$FAUXBIN"
	cat > "$FAUXBIN/dumpe2fs" <<EOF
#!/bin/sh
echo "Filesystem state:         $3"
echo "Block count:              $1"
echo "Free blocks:              $2"
echo "Block size:               4096"
EOF
	chmod +x "$FAUXBIN/dumpe2fs"
}

#  Sans dumpe2fs du tout — le cas d'un voisin btrfs ou xfs.
retire_ext4() { rm -f "$FAUXBIN/dumpe2fs"; }

lance_avec() { # lance_avec <arguments…> -> la sortie ; le code dans $BANC/code
	PATH="$FAUXBIN:$PATH" NO_COLOR=1 sh "$OUTIL" "$@" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

lance() { # lance -> la sortie complète (sans couleur) + $? dans $BANC/code
	PATH="$FAUXBIN:$PATH" NO_COLOR=1 sh "$OUTIL" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

# =============================================================================
titre "1. Disque chiffré (BitLocker) -> ça le dit clairement, pas « pas de Windows »"
# =============================================================================
pose_table "nvme0n1p3 BitLocker 500000000000"
S="$(lance)"
CODE="$(cat "$BANC/code")"
if echo "$S" | grep -q "CHIFFRÉ (BitLocker)"; then
	ok "le disque chiffré est signalé comme CHIFFRÉ, pas comme absent"
else
	non "aucune mention de BitLocker dans la sortie :\n$S"
fi
if echo "$S" | grep -q "nvme0n1p3"; then
	ok "le nom du périphérique chiffré est cité"
else
	non "le périphérique n'est pas nommé"
fi
if echo "$S" | grep -q "aucune partition Windows"; then
	non "le message « aucune partition Windows » est ENCORE affiché — c'est faux ici, Windows existe"
else
	ok "le message « aucune partition Windows » (faux dans ce cas) n'apparaît plus"
fi
echo "$S" | grep -q "clé de récupération" \
	&& ok "le conseil de noter la clé de récupération est présent" \
	|| non "aucun rappel de la clé de récupération"
[ "$CODE" = "0" ] \
	&& ok "l'outil ne s'arrête pas en cours de route (code 0, un bilan reste un bilan)" \
	|| non "code de sortie inattendu : $CODE (l'outil ne doit jamais interrompre son bilan)"

# =============================================================================
titre "2. Disque chiffré -> le reste du bilan (menu de démarrage) s'affiche quand même"
# =============================================================================
#  C'est la différence de comportement volontaire avec le document d'audit,
#  qui proposait un « exit 1 » : cet outil, vérifié dans le reste du
#  fichier, ne s'arrête JAMAIS en cours de route — même sans aucun Windows
#  trouvé, il va jusqu'au bilan de démarrage (UEFI, GRUB, os-prober), qui
#  reste vrai quel que soit l'état de Windows. Un « exit 1 » aurait coupé
#  cette partie utile pour rien.
pose_table "nvme0n1p3 BitLocker 500000000000"
S="$(lance)"
echo "$S" | grep -q "LE MENU DE DÉMARRAGE" \
	&& ok "le bilan continue jusqu'à la section du menu de démarrage" \
	|| non "le bilan s'est arrêté avant la section du menu de démarrage :\n$S"
echo "$S" | grep -q "CE QU'IL FAUT RETENIR" \
	&& ok "…et jusqu'au résumé final" \
	|| non "le résumé final n'a pas été atteint"

# =============================================================================
titre "3. Windows en clair (NTFS) -> comportement d'origine intact, pas de régression"
# =============================================================================
pose_table "nvme0n1p3 ntfs 500000000000"
S="$(lance)"
if echo "$S" | grep -q "Windows trouvé sur /dev/nvme0n1p3"; then
	ok "un Windows NTFS normal est toujours trouvé exactement comme avant"
else
	non "régression : Windows NTFS non détecté :\n$S"
fi
if echo "$S" | grep -qi "BitLocker\|CHIFFRÉ"; then
	non "une mention de chiffrement est apparue alors que le disque est en clair"
else
	ok "aucune fausse alerte de chiffrement sur un disque en clair"
fi

# =============================================================================
titre "4. Aucun Windows du tout (ni NTFS ni BitLocker) -> le message d'origine, inchangé"
# =============================================================================
pose_table "sda1 vfat 200000000"
S="$(lance)"
echo "$S" | grep -q "aucune partition Windows (NTFS) de plus de 20 Go trouvée" \
	&& ok "le message d'origine (aucun Windows) est toujours affiché tel quel" \
	|| non "le message d'absence de Windows a changé ou disparu :\n$S"
if echo "$S" | grep -qi "BitLocker\|CHIFFRÉ"; then
	non "une mention de chiffrement est apparue sans disque chiffré"
else
	ok "aucune fausse alerte de chiffrement sans disque chiffré"
fi

# =============================================================================
titre "5. Une petite partition BitLocker (< 20 Go, ex. Recovery) -> ignorée, comme le NTFS"
# =============================================================================
#  Même seuil que trouver_windows() : une partition de récupération chiffrée
#  minuscule ne doit pas être prise pour LE Windows chiffré à déverrouiller.
pose_table "nvme0n1p1 BitLocker 800000000"
S="$(lance)"
if echo "$S" | grep -q "CHIFFRÉ (BitLocker)"; then
	non "une partition BitLocker de moins de 20 Go a été prise pour le Windows chiffré"
else
	ok "une petite partition BitLocker (< 20 Go) est bien ignorée, comme pour le NTFS"
fi

# =============================================================================
titre "6. Un voisin LINUX (Ubuntu) — trouvé, mesuré, et le curseur est chiffré"
# =============================================================================
#  ALEX : « l'ISO, peux-tu l'installer à côté d'un autre logiciel comme
#  Ubuntu ? » L'outil ne cherchait que du NTFS : devant un disque Ubuntu il
#  annonçait « aucune partition Windows trouvée » et laissait Alex sans le
#  chiffre à régler. Calamares, lui, savait déjà le faire.
#  300 Go, dont 120 utilisés : 73242187 blocs de 4 kio, 43945312 libres.
pose_table "nvme0n1p2 ext4 300000000000"
pose_ext4 73242187 43945312 "clean"
S="$(lance)"
echo "$S" | grep -q "un autre Linux occupe /dev/nvme0n1p2" \
	&& ok "le voisin Linux est trouvé et nommé" \
	|| non "le voisin Linux (ext4, 300 Go) n'a pas été vu :\n$S"
echo "$S" | grep -q "utilise 120 Go sur 300 Go" \
	&& ok "sa place occupée est MESURÉE (dumpe2fs), pas devinée" \
	|| non "la place occupée du voisin Linux n'est pas mesurée :\n$S"
echo "$S" | grep -q "40 Go pour LexOS" \
	&& ok "le chiffre exact à régler sur le curseur est donné" \
	|| non "aucun chiffre de découpe pour un voisin Linux"
#  ET IL NE DIT PLUS QUE LE DISQUE EST LIBRE. Sans Windows, l'outil
#  concluait « l'installateur proposera d'utiliser tout le disque » — vrai
#  sur un disque vide, FAUX ici, et c'est la phrase qui déciderait Alex à
#  laisser tout effacer. Écrit d'abord comme un contrôle qui appelait ok()
#  dans ses DEUX branches : il ne pouvait pas échouer, donc ne prouvait
#  rien. C'est en le rendant capable d'échouer qu'il a montré le défaut.
if echo "$S" | grep -q "proposera d'utiliser tout le disque"; then
	non "il annonce que l'installateur prendra TOUT le disque — il y a un Linux dessus"
else
	ok "il ne prétend plus que le disque est libre à prendre en entier"
fi

#  Et sur un disque VRAIMENT vide, la phrase rassurante doit rester.
pose_table "sda1 vfat 200000000"
S_VIDE="$(lance)"
echo "$S_VIDE" | grep -q "proposera d'utiliser tout le disque" \
	&& ok "…mais sur un disque sans voisin, elle est toujours là" \
	|| non "la phrase du disque vide a disparu — elle était juste, elle"
pose_table "nvme0n1p2 ext4 300000000000"

# =============================================================================
titre "7. ON NE SE PROPOSE JAMAIS DE SE RÉDUIRE SOI-MÊME"
# =============================================================================
#  Le piège n'est pas théorique : lancé depuis un LexOS DÉJÀ INSTALLÉ, l'ext4
#  le plus gros du disque est le NÔTRE. Sans le filtre sur la racine, l'outil
#  conseillerait posément de découper la partition sur laquelle il tourne.
#  Depuis la clé USB le cas ne se voit pas (la racine est un squashfs) — il
#  n'apparaîtrait donc que sur la machine d'Alex, après installation.
pose_table "nvme0n1p2 ext4 300000000000"
pose_ext4 73242187 43945312 "clean"
pose_racine "/dev/nvme0n1p2"
S="$(lance)"
if echo "$S" | grep -q "un autre Linux occupe"; then
	non "notre PROPRE racine est proposée comme voisin à réduire :\n$S"
else
	ok "notre propre racine n'est jamais prise pour un voisin"
fi
pose_racine "/dev/loop0"

# =============================================================================
titre "8. « not clean » se lit en DEUX mots — le défaut que ce banc a attrapé"
# =============================================================================
#  L'état revenait de mesurer_ext4() collé à la place occupée : « 120 not
#  clean ». On le découpait avec « ${x##* } », qui retire le PLUS LONG
#  préfixe finissant par une espace — donc rendait « clean » sur un système
#  de fichiers qui ne l'était pas. L'avertissement ne se serait jamais
#  déclenché, et on aurait redimensionné un disque en cours d'utilisation sur
#  la foi d'un outil affirmant que tout allait bien.
pose_table "nvme0n1p2 ext4 300000000000"
pose_ext4 73242187 43945312 "not clean"
S="$(lance)"
echo "$S" | grep -q "n'est pas « clean » (état : not clean)" \
	&& ok "un ext4 « not clean » est signalé, avec son état complet" \
	|| non "un ext4 sale passe pour propre — le découpage serait conseillé quand même :\n$S"
pose_ext4 73242187 43945312 "clean"
S="$(lance)"
echo "$S" | grep -q "n'est pas « clean »" \
	&& non "fausse alerte : un ext4 propre est signalé comme sale" \
	|| ok "…et un ext4 propre ne déclenche aucune fausse alerte"

# =============================================================================
titre "9. La taille se CHOISIT — la demande d'Alex"
# =============================================================================
#  « Je voudrais qu'on choisisse le nombre de mémoire qu'il peut prendre. »
#  C'était une variable d'environnement, donc en pratique inatteignable :
#  personne n'écrit « LEXOS_DUALBOOT_CIBLE_GO=60 lexos dualboot » devant un
#  disque qu'il a peur d'abîmer.
pose_table "nvme0n1p2 ext4 300000000000"
pose_ext4 73242187 43945312 "clean"
S="$(lance_avec 120)"
echo "$S" | grep -q "120 Go pour LexOS" \
	&& ok "« lexos dualboot 120 » vise bien 120 Go" \
	|| non "la taille demandée en ligne de commande est ignorée :\n$S"
S="$(lance_avec --taille 90)"
echo "$S" | grep -q "90 Go pour LexOS" \
	&& ok "« --taille 90 » marche aussi" \
	|| non "la forme --taille est ignorée"

#  ET CE QUI N'EST PAS UN NOMBRE EST REFUSÉ, PAS DEVINÉ. « 60Go » ressemble à
#  un chiffre et n'en est pas un ; le prendre pour 0 ou pour 60 au petit
#  bonheur donnerait un conseil de découpe faux sur un disque qui contient
#  les jeux d'Alex.
for MAUVAIS in 60Go soixante -40; do
	S="$(lance_avec "$MAUVAIS")"
	CODE="$(cat "$BANC/code")"
	if [ "$CODE" = "2" ] && ! echo "$S" | grep -q "LA PLACE POUR LEXOS"; then
		ok "« $MAUVAIS » est refusé net (code 2), sans afficher de conseil"
	else
		non "« $MAUVAIS » n'est pas refusé proprement (code $CODE) :\n$S"
	fi
done

#  Sous le plancher, on refuse aussi : conseiller une découpe où LexOS ne
#  rentre pas ne rend service à personne.
S="$(lance_avec 10)"
[ "$(cat "$BANC/code")" = "2" ] \
	&& ok "10 Go — sous le minimum — est refusé avec son motif" \
	|| non "une taille sous le plancher est acceptée"

# =============================================================================
titre "10. Un voisin Linux CHIFFRÉ ou en LVM — le cas de l'Alienware"
# =============================================================================
#  LE MÊME PIÈGE QUE BITLOCKER, À L'AUTRE BOUT. Dans un LUKS, lsblk montre
#  « crypto_LUKS » sur la partition ; l'ext4 n'apparaît qu'APRÈS
#  déverrouillage, sur un /dev/mapper qui n'existe pas encore. Dans un LVM,
#  c'est « LVM2_member ». trouver_linux() ne cherchait ni l'un ni l'autre :
#  devant l'Ubuntu chiffré de l'Alienware, l'outil disait « aucune autre
#  partition Linux » puis « aucun voisin : l'installateur proposera d'utiliser
#  le disque en entier » — sur le disque qui porte ce système-là.
pose_table "nvme0n1p3 crypto_LUKS 400000000000"
S="$(lance)"

echo "$S" | grep -qi "chiffré (LUKS)" \
	&& ok "le voisin chiffré est nommé pour ce qu'il est (LUKS)" \
	|| non "le système chiffré n'est pas signalé :\n$S"

echo "$S" | grep -q "nvme0n1p3" \
	&& ok "…et son périphérique est cité" \
	|| non "le périphérique chiffré n'est pas nommé"

if echo "$S" | grep -q "proposera d'utiliser tout le disque\|proposera de l'utiliser en entier"; then
	non "l'outil propose ENCORE d'utiliser tout le disque — sur un disque qui porte un système"
else
	ok "la phrase « l'installateur prendra tout le disque » n'apparaît plus"
fi

echo "$S" | grep -q "partitionnement manuel\|partitionnement MANUEL" \
	&& ok "le chemin de sortie (partitionnement manuel) est donné" \
	|| non "aucune consigne de partitionnement manuel :\n$S"

#  ON EXIGE LA LISTE NUMÉROTÉE, pas une mention quelque part. Les cinq noms
#  apparaissent AUSSI en une ligne dans le résumé final : un simple grep sur
#  « resize2fs » restait donc vert même en supprimant toute la marche à
#  suivre détaillée. Attrapé en cassant le bloc exprès.
N=1
for ETAPE in resize2fs lvreduce pvresize "cryptsetup resize" GParted; do
	echo "$S" | grep -qE "^ +$N\. +$ETAPE" \
		&& ok "…la marche à suivre donne l'étape $N dans l'ordre : $ETAPE" \
		|| non "l'étape $N ($ETAPE) manque de la marche à suivre numérotée"
	N=$((N+1))
done

if echo "$S" | grep -q "curseur à"; then
	non "le résumé conseille encore le curseur « Installer à côté de » — inutilisable ici"
else
	ok "le résumé ne renvoie plus vers « Installer à côté de », qui ne sait pas faire"
fi

#  UN LVM NON CHIFFRÉ EST LE MÊME PROBLÈME : Calamares ne le redimensionne
#  pas davantage.
pose_table "sda2 LVM2_member 300000000000"
S="$(lance)"
echo "$S" | grep -qi "volume LVM" \
	&& ok "un LVM non chiffré est signalé aussi" \
	|| non "le LVM2_member n'est pas reconnu :\n$S"

#  MÊME SEUIL QUE LES AUTRES : une petite partition chiffrée (un /boot
#  chiffré, une partition de récupération) n'est pas LE système voisin.
pose_table "sda3 crypto_LUKS 900000000"
S="$(lance)"
if echo "$S" | grep -qi "chiffré (LUKS)"; then
	non "une partition LUKS de moins de 20 Go a été prise pour le système voisin"
else
	ok "une petite partition LUKS (< 20 Go) est ignorée, comme pour le NTFS"
fi

#  ET ON NE SE SIGNALE PAS SOI-MÊME. Lancé depuis un LexOS déjà installé sur
#  un disque chiffré, le LUKS le plus gros est le NÔTRE — le même piège que
#  la section 7, à l'autre bout.
pose_table "nvme0n1p3 crypto_LUKS 400000000000"
pose_racine "/dev/nvme0n1p3"
S="$(lance)"
if echo "$S" | grep -qi "chiffré (LUKS)"; then
	non "l'outil signale NOTRE PROPRE racine chiffrée comme un système voisin"
else
	ok "notre propre racine chiffrée n'est pas prise pour un voisin"
fi
pose_racine "/dev/loop0"

#  UN VOISIN EN CLAIR PREND LE PAS : un disque qui porte un /boot ext4 et un
#  LVM chiffré à côté, c'est UN système, pas deux. Deux annonces
#  embrouilleraient plus qu'elles n'aideraient.
pose_table "sda2 ext4 300000000000" "sda3 crypto_LUKS 400000000000"
pose_ext4 50000000 40000000 clean
S="$(lance)"
if echo "$S" | grep -qi "chiffré (LUKS)"; then
	non "le voisin chiffré est annoncé EN PLUS du voisin en clair — deux annonces pour un système"
else
	ok "quand un voisin en clair existe, lui seul est annoncé"
fi
retire_ext4

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
