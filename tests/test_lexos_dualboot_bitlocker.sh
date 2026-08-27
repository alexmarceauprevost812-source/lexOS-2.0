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
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-dualboot introuvable ou non exécutable"; exit 1; }

FAUXBIN="$BANC/bin"
TABLE="$BANC/table"   # les lignes NAME FSTYPE SIZE que le faux lsblk sert

pose_table() { # pose_table "nom1 fstype1 taille1" "nom2 fstype2 taille2" ...
	mkdir -p "$FAUXBIN"
	printf '%s\n' "$@" > "$TABLE"
	cat > "$FAUXBIN/lsblk" <<EOF
#!/bin/sh
#  Seule la forme "-brno NAME,FSTYPE,SIZE" (aucun périphérique donné) sert
#  cette table : c'est la seule que l'outil appelle quand WIN_DEV est vide,
#  exactement les scénarios de ce banc.
case "\$*" in
	*"NAME,FSTYPE,SIZE"*) cat "$TABLE" ;;
	*) exit 0 ;;
esac
EOF
	chmod +x "$FAUXBIN/lsblk"
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

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
