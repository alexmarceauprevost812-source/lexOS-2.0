#!/usr/bin/env bash
# =============================================================================
#  Les outils système trouvent leurs commandes — même lancés depuis le bureau
# =============================================================================
#  ALEX : « pas capable de faire formater ma clé USB, il affiche outil
#  manquant ». Le message venait de lexos-format, et il était TROMPEUR :
#  l'outil n'était pas absent de la machine, il était absent du PATH.
#
#  ═══ LE MÉCANISME, ET IL VAUT POUR TOUT LE DÉPÔT ═══
#  Debian ne met les répertoires sbin dans le PATH que pour root :
#  /etc/profile teste l'UID, et un compte ordinaire reçoit
#  /usr/local/bin:/usr/bin:/bin, rien de plus. Or parted, mkfs.vfat,
#  mkfs.ext4, wipefs, dmidecode, smartctl, usermod, rfkill, modprobe et
#  swapon vivent tous dans /usr/sbin.
#
#  Un outil LexOS lancé depuis le BUREAU — action du clic droit, fichier
#  .desktop, page des Paramètres — tourne sous le compte ordinaire. Il ne
#  trouvait donc pas des commandes pourtant installées, et disait « outil
#  manquant » à tort. Le clic droit « Formater ce support… » lance
#  « lexos-format --gui » : c'est exactement ce chemin-là.
#
#  ═══ CE QUE CE BANC GARDE ═══
#  Que tout outil du dépôt qui appelle une commande de sbin normalise son
#  PATH. C'est un garde-fou de CLASSE, pas un correctif d'un cas : il attrape
#  aussi le prochain outil qu'on écrira.
#
#  Et il garde deux détails qui ont failli coûter cher, tous deux trouvés en
#  cassant le correctif exprès :
#    · les sbin vont EN QUEUE du PATH, jamais en tête. Mis devant, ils
#      passent avant ce que l'utilisateur — ou un banc — a déjà mis dans le
#      sien : deux bancs de ce dépôt injectent de faux outils par un
#      répertoire en tête de PATH, et les doubler par les vrais les a rendus
#      aveugles sur-le-champ ;
#    · le seam LEXOS_SANS_SBIN=1 doit rester, pour qu'un banc puisse encore
#      simuler un outil VRAIMENT absent.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$RACINE/config/includes.chroot/usr/bin"

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[[ -d "$BIN" ]] || { echo "dossier des outils introuvable : $BIN"; exit 1; }

#  Les commandes qui vivent dans sbin sur Debian. On ne devine pas : ce sont
#  celles que les outils du dépôt appellent réellement, relevées à la main.
SBIN='parted|mkfs\.[a-z0-9]+|wipefs|fdisk|sfdisk|sgdisk|partprobe|cryptsetup|resize2fs|dumpe2fs|e2fsck|hdparm|smartctl|dmidecode|lshw|hwinfo|rfkill|modprobe|swapon|useradd|usermod|chpasswd|update-grub|grub-install|efibootmgr|ntfsresize|hwclock'

# =============================================================================
titre "1. Tout outil qui appelle une commande de sbin normalise son PATH"
# =============================================================================
CONCERNES=0
for F in "$BIN"/lexos-*; do
	[[ -f "$F" ]] || continue
	NOM="$(basename "$F")"
	#  On regarde le CODE, commentaires retirés : plusieurs de ces outils
	#  citent « parted » ou « dmidecode » dans leurs explications sans les
	#  appeler, et les compter donnerait des rouges pour rien.
	CODE="$(sed 's/#.*$//' "$F")"
	APPELS="$(printf '%s' "$CODE" | grep -oE "\b($SBIN)\b" | sort -u | tr '\n' ' ')"
	[[ -z "${APPELS// }" ]] && continue
	CONCERNES=$((CONCERNES+1))

	if printf '%s' "$CODE" | grep -e 'PATH=.*sbin' >/dev/null; then
		ok "$NOM appelle ${APPELS%% *}… et normalise son PATH"
	else
		non "$NOM appelle des commandes de sbin ($APPELS) sans normaliser son PATH\n     → lancé depuis le bureau, il dirait « outil manquant » à tort"
	fi
done

if (( CONCERNES > 0 )); then
	ok "$CONCERNES outils concernés ont été examinés"
else
	non "aucun outil concerné trouvé — le motif de recherche ne mord plus"
fi

# =============================================================================
titre "2. Les sbin vont EN QUEUE du PATH, jamais en tête"
# =============================================================================
#  ═══ LE DÉTAIL QUI A ÉTÉ PRIS EN FAUTE ═══
#  La première version de ce correctif écrivait « PATH=/usr/sbin:$PATH ».
#  Deux bancs ont rougi immédiatement : ils injectent de faux outils par un
#  répertoire placé en tête de PATH, et les vrais outils du système passaient
#  désormais devant. Au-delà des bancs, c'est le principe : ce qu'on ajoute
#  d'office ne doit pas écraser ce que l'appelant a choisi.
for F in "$BIN"/lexos-*; do
	[[ -f "$F" ]] || continue
	NOM="$(basename "$F")"
	LIGNE="$(sed 's/#.*$//' "$F" | grep -E '^\s*(\[.*\]\s*\|\|\s*)?PATH=.*sbin' | head -1)"
	[[ -z "$LIGNE" ]] && continue

	if printf '%s' "$LIGNE" | grep -E 'PATH="\$PATH:' >/dev/null; then
		ok "$NOM ajoute les sbin en queue"
	else
		non "$NOM met les sbin EN TÊTE du PATH : il écraserait le choix de l'appelant\n     ligne : $LIGNE"
	fi
done

# =============================================================================
titre "3. Le seam de banc survit"
# =============================================================================
#  Sans lui, un banc ne peut plus simuler un outil vraiment absent : l'outil
#  irait le chercher dans /usr/sbin et le trouverait sur la machine du
#  coureur. C'est ce qui est arrivé au banc du matériel, qui a rougi.
for F in "$BIN"/lexos-*; do
	[[ -f "$F" ]] || continue
	NOM="$(basename "$F")"
	#  PAS DE « grep -q » DANS UN TUBE ICI. Avec « set -o pipefail », grep -q
	#  ferme le tube dès la première correspondance, sed prend un SIGPIPE, et
	#  le pipeline entier rend non-zéro ALORS QUE LA LIGNE EXISTE. Ce banc
	#  sautait ainsi lexos-net au hasard — un faux vert par intermittence,
	#  exactement ce qu'un banc ne doit jamais faire. On capture, puis on
	#  teste la variable.
	CODE3="$(sed 's/#.*$//' "$F")"
	printf '%s' "$CODE3" | grep -E 'PATH=.*sbin' >/dev/null || continue
	if grep -q 'LEXOS_SANS_SBIN' "$F"; then
		ok "$NOM garde le seam LEXOS_SANS_SBIN"
	else
		non "$NOM n'a plus de seam : aucun banc ne pourra simuler un outil absent"
	fi
done

#  ET LE SEAM DOIT MARCHER POUR DE VRAI, pas seulement être écrit.
#  ON MESURE LA VRAIE LIGNE DU FICHIER, pas une copie : on l'extrait et on
#  l'exécute dans un sous-shell, avec et sans le seam, puis on regarde le
#  PATH obtenu. Une première version de ce contrôle lançait l'outil entier
#  sur /dev/null et concluait de son message d'erreur — mais l'outil échoue
#  bien avant d'avoir besoin de parted, sur la résolution de la cible. Elle
#  mesurait donc autre chose que ce qu'elle croyait.
FORMAT="$BIN/lexos-format"
LIGNE_SEAM="$(grep -E '^\[ "\$\{LEXOS_SANS_SBIN' "$FORMAT" | head -1)"
if [[ -z "$LIGNE_SEAM" ]]; then
	non "la ligne du seam est introuvable dans lexos-format"
else
	AVEC="$(PATH="/usr/bin:/bin" bash -c "$LIGNE_SEAM"$'\n''printf %s "$PATH"')"
	SANS="$(PATH="/usr/bin:/bin" LEXOS_SANS_SBIN=1 bash -c "$LIGNE_SEAM"$'\n''printf %s "$PATH"')"

	if [[ "$AVEC" == *"/usr/sbin"* ]]; then
		ok "sans le seam, la ligne ajoute bien /usr/sbin au PATH ($AVEC)"
	else
		non "la ligne n'ajoute PAS /usr/sbin : le correctif ne fait rien ($AVEC)"
	fi

	if [[ "$SANS" != *"/usr/sbin"* ]]; then
		ok "avec LEXOS_SANS_SBIN=1, elle ne touche à rien ($SANS)"
	else
		non "le seam ne désactive plus l'ajout : aucun banc ne pourra simuler une absence ($SANS)"
	fi

	#  Et l'ajout doit rester EN QUEUE, ce que la sortie montre directement.
	if [[ "$AVEC" == "/usr/bin:/bin:"* ]]; then
		ok "…et ce qui était déjà dans le PATH reste devant"
	else
		non "l'ajout est passé devant le PATH d'origine ($AVEC)"
	fi
fi

# =============================================================================
titre "4. Un outil vraiment absent dit QUOI installer"
# =============================================================================
#  « Outil manquant : parted » n'apprend rien à qui ne sait pas que parted
#  vient du paquet parted. Même règle que partout ailleurs dans LexOS : on
#  nomme la condition qui manque, et le geste qui la répare.
if grep -q 'paquet_de()' "$FORMAT"; then
	ok "lexos-format sait nommer le paquet d'une commande absente"
	for C in parted:parted mkfs.vfat:dosfstools mkfs.ext4:e2fsprogs mkfs.exfat:exfatprogs; do
		CMD="${C%%:*}"; PKG="${C##*:}"
		if grep -qE "^\s*${CMD//./\\.})\s*printf '${PKG}'" "$FORMAT"; then
			ok "…$CMD → $PKG"
		else
			non "$CMD n'est pas rattaché au paquet $PKG"
		fi
	done
	#  SUR LA LIGNE DU MESSAGE, pas n'importe où dans le fichier. Le fichier
	#  cite « lexos install exfatprogs » une seconde fois, dans le cas exFAT :
	#  un grep large restait donc vert même en retirant la consigne du
	#  message générique. Attrapé en le retirant exprès.
	if grep -E 'die "Outil manquant.*lexos install' "$FORMAT" >/dev/null; then
		ok "…et le message lui-même donne la commande qui l'installe"
	else
		non "le message « Outil manquant » ne dit plus comment installer le paquet"
	fi
else
	non "lexos-format ne nomme pas le paquet d'une commande absente"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
