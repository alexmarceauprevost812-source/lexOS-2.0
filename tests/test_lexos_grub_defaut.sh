#!/usr/bin/env bash
# =============================================================================
#  Éprouver grub-defaut-voisin — QUI démarre tout seul quand il y a un voisin
# =============================================================================
#  ALEX : « j'aimerais aussi que LexOS Pro soit capable de se mettre à côté
#  d'Ubuntu 26.04.1 […] pour avoir 2 logiciels pour être capable de
#  travailler avec les 2 ».
#
#  ═══ LE DÉFAUT QUE CE BANC EXISTE POUR TENIR ═══
#  Le script s'appelait grub-defaut-windows et cherchait « menuentry …
#  windows » dans grub.cfg. Devant un Ubuntu il ne trouvait JAMAIS rien et
#  sortait sur « aucune entrée Windows — LexOS reste le démarrage par
#  défaut » : LexOS devenait le défaut sans que personne ne l'ait décidé.
#
#  ═══ LES TROIS ÉTATS, ET CE QU'ON MESURE DANS CHACUN ═══
#    · aucun choix écrit   -> Windows devient le défaut S'IL EST LÀ ; un
#      voisin Linux, NON (et le journal dit pourquoi et comment changer) ;
#    · « voisin »          -> l'entrée du voisin est écrite dans grubenv ;
#    · « lexos »           -> saved_entry est RETIRÉ (et pas « LexOS »
#      écrit à la place : le titre change à chaque noyau).
#
#  On ne lit pas le code, on le FAIT TOURNER : faux grub-set-default et faux
#  grub-editenv qui NOTENT ce qu'on leur demande, faux grub.cfg, et les
#  seams LEXOS_DUALBOOT_DEFAUT_FICHIER / LEXOS_GRUB_DISTRIBUTOR.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/lib/lexos/grub-defaut-voisin"
ALIAS="$RACINE/config/includes.chroot/usr/lib/lexos/grub-defaut-windows"
SERVICE="$RACINE/config/includes.chroot/usr/lib/systemd/system/lexos-grub-defaut.service"
HOOK0500="$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$OUTIL" ] || { echo "grub-defaut-voisin introuvable"; exit 1; }

FAUXBIN="$BANC/bin"; mkdir -p "$FAUXBIN"
POSES="$BANC/poses"          # ce que grub-set-default a reçu
EDITENV="$BANC/editenv"      # ce que grub-editenv a reçu
ENV_ETAT="$BANC/grubenv"     # ce que « grub-editenv - list » répond

#  ═══ ON RÉÉCRIT LE SCRIPT POUR DÉPLACER CE QU'IL LIT, RIEN DE PLUS ═══
#  Le script lit /proc/cmdline, /boot/grub/grub.cfg et /var/log en dur. Il
#  n'a pas de seam pour ceux-là (et lui en ajouter trois pour le banc
#  seulement serait ajouter du code qui ne sert qu'au banc). On substitue
#  donc les CHEMINS, pas le comportement : aucune ligne de logique n'est
#  touchée, et le banc le VÉRIFIE ci-dessous en comptant les substitutions.
COPIE="$BANC/grub-defaut-voisin"
sed -e "s#/proc/cmdline#$BANC/cmdline#g" \
    -e "s#/boot/grub/grub.cfg#$BANC/grub.cfg#g" \
    -e "s#/boot/grub2/grub.cfg#$BANC/grub2.cfg#g" \
    -e "s#/var/log/lexos-grub-defaut.log#$BANC/journal.log#g" \
    "$OUTIL" > "$COPIE"
N_SUBST="$(diff <(sed 's/[[:space:]]//g' "$OUTIL") <(sed 's/[[:space:]]//g' "$COPIE") | grep -c '^<')"
if [ "$N_SUBST" -ge 3 ] && [ "$N_SUBST" -le 8 ]; then
	ok "le script est rejoué tel quel : $N_SUBST lignes de CHEMIN substituées, aucune de logique"
else
	non "$N_SUBST lignes changées par la substitution — trop, ou pas assez : le banc n'éprouve plus le vrai script"
fi

cat > "$FAUXBIN/grub-set-default" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$POSES"
exit 0
EOF
cat > "$FAUXBIN/grub-editenv" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$EDITENV"
case "\$*" in
	*list*)  [ -r "$ENV_ETAT" ] && cat "$ENV_ETAT" ;;
	*unset*) : > "$ENV_ETAT" ;;
esac
exit 0
EOF
chmod +x "$FAUXBIN/grub-set-default" "$FAUXBIN/grub-editenv"

printf 'BOOT_IMAGE=/vmlinuz root=/dev/nvme0n1p3 ro quiet splash\n' > "$BANC/cmdline"

pose_menu() { printf '%s\n' "$@" > "$BANC/grub.cfg"; }
pose_env()  { printf '%s\n' "${1:-}" > "$ENV_ETAT"; }
pose_choix() { # pose_choix <lexos|voisin|RIEN|abîmé>
	if [ "$1" = "RIEN" ]; then rm -f "$BANC/choix"; else printf '%s\n' "$1" > "$BANC/choix"; fi
}
lance() {
	: > "$POSES"; : > "$EDITENV"
	PATH="$FAUXBIN:$PATH" LEXOS_DUALBOOT_DEFAUT_FICHIER="$BANC/choix" \
		sh "$COPIE" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}
a_pose() { grep -qF -- "$1" "$POSES" 2>/dev/null; }

M_LEXOS="menuentry 'LexOS GNU/Linux' --class lexos --class gnu-linux {"
M_LEXOS2="menuentry 'LexOS GNU/Linux, avec Linux 6.12.0-amd64' --class lexos {"
M_UBUNTU="menuentry 'Ubuntu 26.04.1 LTS (26.04) (sur /dev/nvme0n1p2)' --class ubuntu --class gnu-linux {"
M_UBUNTU_REC="menuentry 'Ubuntu 26.04.1 LTS (26.04) (sur /dev/nvme0n1p2) (recovery mode)' --class ubuntu {"
M_WINDOWS="menuentry 'Windows Boot Manager (sur /dev/nvme0n1p1)' --class windows {"
M_WIN_REC="menuentry 'Windows Recovery Environment (sur /dev/nvme0n1p4)' --class windows {"
M_UEFI="menuentry 'UEFI Firmware Settings' \$menuentry_id_option 'uefi-firmware' {"

# =============================================================================
titre "1. Voisin UBUNTU, « defaut voisin » -> la bonne entrée est écrite"
# =============================================================================
pose_menu "$M_LEXOS" "$M_LEXOS2" "$M_UBUNTU" "$M_UBUNTU_REC" "$M_UEFI"
pose_env ""
pose_choix voisin
S="$(lance)"
if a_pose "Ubuntu 26.04.1 LTS (26.04) (sur /dev/nvme0n1p2)"; then
	ok "l'entrée Ubuntu est posée dans grubenv — c'est ce que l'ancien script ne savait pas faire"
else
	non "aucune entrée Ubuntu posée : « $(cat "$POSES")»\n$S"
fi
#  ═══ ET PAS L'ENTRÉE DE RÉCUPÉRATION ═══
#  « (recovery mode) » ouvre un menu de dépannage en mono-utilisateur. En
#  faire le démarrage par défaut serait désastreux — la même faute que
#  « Windows Recovery », avec une autre orthographe.
if grep -qi "recovery" "$POSES" 2>/dev/null; then
	non "c'est l'entrée de RÉCUPÉRATION d'Ubuntu qui a été posée : « $(cat "$POSES")»"
else
	ok "…et pas son entrée de récupération (« recovery mode »)"
fi
#  ═══ ET SURTOUT PAS NOUS ═══
#  os-prober écrit les voisins APRÈS nos propres entrées. Sans le filtre sur
#  GRUB_DISTRIBUTOR, « defaut voisin » aurait pu poser… LexOS.
if grep -qi "lexos" "$POSES" 2>/dev/null; then
	non "« defaut voisin » a posé une entrée LEXOS : « $(cat "$POSES")»"
else
	ok "…et surtout pas une des NÔTRES (les entrées LexOS viennent en premier dans le menu)"
fi
if grep -qi "firmware\|uefi" "$POSES" 2>/dev/null; then
	non "une entrée de micrologiciel a été posée comme système par défaut"
else
	ok "…ni l'entrée « UEFI Firmware Settings », qui n'est pas un système"
fi
[ "$(cat "$BANC/code")" = "0" ] && ok "code de sortie 0" || non "code $(cat "$BANC/code")"

# =============================================================================
titre "2. « defaut lexos » -> saved_entry est RETIRÉ, pas remplacé par « LexOS »"
# =============================================================================
#  Écrire notre propre titre marcherait jusqu'à la première mise à jour de
#  noyau, qui le change : grubenv désignerait alors une entrée disparue.
#  Effacer dit exactement « pas de préférence », et reste vrai après chaque
#  noyau. Ce cas échoue le jour où quelqu'un « simplifie » en posant LexOS.
pose_menu "$M_LEXOS" "$M_LEXOS2" "$M_UBUNTU"
pose_env "saved_entry=Ubuntu 26.04.1 LTS (26.04) (sur /dev/nvme0n1p2)"
pose_choix lexos
S="$(lance)"
grep -q "unset saved_entry" "$EDITENV" 2>/dev/null \
	&& ok "saved_entry est RETIRÉ de grubenv" \
	|| non "saved_entry n'a pas été retiré : « $(cat "$EDITENV")»\n$S"
if [ -s "$POSES" ]; then
	non "grub-set-default a quand même été appelé : « $(cat "$POSES")»"
else
	ok "…et aucun titre n'est écrit à la place (un titre de noyau se périme)"
fi
grep -qi "LexOS (choix d'Alex)" <<< "$S" \
	&& ok "le journal dit que c'est un CHOIX, pas un effet de bord" \
	|| non "le journal n'explique pas :\n$S"
#  Déjà vide -> on ne rappelle rien. Le service tourne à CHAQUE démarrage.
pose_env ""
lance >/dev/null
if [ -s "$EDITENV" ] && grep -q "unset" "$EDITENV" 2>/dev/null; then
	non "grubenv déjà vide et « unset » rappelé quand même — du bruit à chaque démarrage"
else
	ok "grubenv déjà vide : rien n'est rappelé"
fi

# =============================================================================
titre "3. AUCUN choix écrit -> Windows oui, Ubuntu NON (et le journal le dit)"
# =============================================================================
#  C'est le comportement d'avant, préservé mot pour mot pour Windows : la
#  demande d'origine d'Alex (Windows pour jouer) n'est pas annulée par la
#  nouvelle. Mais deux LINUX dans un menu, celui qui part tout seul doit
#  être DÉCIDÉ, pas deviné.
pose_choix RIEN
pose_env ""
pose_menu "$M_LEXOS" "$M_WINDOWS" "$M_WIN_REC"
S="$(lance)"
a_pose "Windows Boot Manager (sur /dev/nvme0n1p1)" \
	&& ok "sans choix écrit, un WINDOWS voisin devient le défaut — le comportement d'avant, intact" \
	|| non "Windows n'est plus posé sans choix écrit : « $(cat "$POSES")»\n$S"

pose_menu "$M_LEXOS" "$M_LEXOS2" "$M_UBUNTU" "$M_UBUNTU_REC"
S="$(lance)"
if [ -s "$POSES" ]; then
	non "sans choix écrit, un voisin UBUNTU est devenu le défaut tout seul : « $(cat "$POSES")»"
else
	ok "sans choix écrit, un voisin UBUNTU ne devient PAS le défaut : LexOS reste, comme sur le ThinkPad"
fi
#  ═══ ET ALEX DOIT LE LIRE, PAS LE DÉDUIRE ═══
grep -q "LexOS reste le démarrage par défaut et le menu reste 8 s" <<< "$S" \
	&& ok "…et le journal l'ÉCRIT : LexOS reste le défaut, menu 8 s" \
	|| non "le journal ne dit pas ce qui se passe :\n$S"
grep -q "lexos dualboot defaut voisin" <<< "$S" \
	&& ok "…et il donne la commande exacte pour changer" \
	|| non "le journal ne dit pas comment changer :\n$S"
grep -qF "Ubuntu 26.04.1" <<< "$S" \
	&& ok "…en nommant le voisin qu'il a trouvé" \
	|| non "le voisin trouvé n'est pas nommé dans le journal"

# =============================================================================
titre "4. Les deux à la fois -> Windows d'abord (la demande d'origine)"
# =============================================================================
pose_choix voisin
pose_menu "$M_LEXOS" "$M_WINDOWS" "$M_UBUNTU"
lance >/dev/null
if a_pose "Windows Boot Manager (sur /dev/nvme0n1p1)"; then
	ok "Windows ET Ubuntu présents, « voisin » demandé -> c'est Windows qui est posé"
else
	non "Windows n'a pas la priorité sur Ubuntu : « $(cat "$POSES")»"
fi

# =============================================================================
titre "5. Les sorties propres — démo, pas de grub.cfg, choix abîmé"
# =============================================================================
pose_choix voisin
pose_menu "$M_LEXOS" "$M_UBUNTU"
printf 'boot=live components username=lex quiet splash\n' > "$BANC/cmdline"
lance >/dev/null
if [ -s "$POSES" ] || [ -s "$EDITENV" ]; then
	non "EN SESSION DÉMO, grubenv a été touché : « $(cat "$POSES") $(cat "$EDITENV")»"
else
	ok "session démo : rien n'est écrit (le grub.cfg lisible est celui de la clé)"
fi
[ "$(cat "$BANC/code")" = "0" ] && ok "…et le script sort proprement (code 0)" || non "code $(cat "$BANC/code") en démo"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/nvme0n1p3 ro quiet splash\n' > "$BANC/cmdline"

rm -f "$BANC/grub.cfg"
S="$(lance)"
if [ -s "$POSES" ]; then
	non "sans grub.cfg, quelque chose a été posé : « $(cat "$POSES")»"
else
	ok "sans grub.cfg : aucune décision, aucune écriture"
fi
[ "$(cat "$BANC/code")" = "0" ] && ok "…et code 0, pas une erreur" || non "code $(cat "$BANC/code") sans grub.cfg"

pose_menu "$M_LEXOS" "$M_UBUNTU"
pose_choix "n_importe_quoi"
S="$(lance)"
grep -qi "inconnu" <<< "$S" \
	&& ok "un fichier de choix abîmé est SIGNALÉ dans le journal" \
	|| non "un choix inconnu passe en silence :\n$S"
if [ -s "$POSES" ]; then
	non "un choix abîmé a décidé à la place d'Alex : « $(cat "$POSES")»"
else
	ok "…et il ne décide rien : on retombe sur le comportement sans choix"
fi

# =============================================================================
titre "6. Le câblage : l'alias, l'unité, le hook"
# =============================================================================
#  Une machine installée AVANT ce changement garde une unité qui pointe sur
#  l'ancien nom. L'alias est ce qui l'empêche de se casser en silence.
if [ -r "$ALIAS" ] && grep -q 'exec /usr/lib/lexos/grub-defaut-voisin' "$ALIAS"; then
	ok "l'ancien nom grub-defaut-windows existe encore et fait suivre — une machine déjà posée ne casse pas"
else
	non "l'alias grub-defaut-windows manque ou ne fait pas suivre"
fi
grep -q 'ExecStart=/usr/lib/lexos/grub-defaut-voisin' "$SERVICE" \
	&& ok "l'unité lance le NOUVEAU nom" \
	|| non "l'unité ne lance pas grub-defaut-voisin :\n$(grep ExecStart "$SERVICE")"
if grep -qi 'Windows comme démarrage par défaut' "$SERVICE"; then
	non "la description de l'unité parle encore de Windows seulement"
else
	ok "…et sa description couvre les deux (Windows ou Linux)"
fi
grep -q 'chmod 0755 /usr/lib/lexos/grub-defaut-voisin' "$HOOK0500" \
	&& ok "le hook 0500 rend le nouveau script exécutable" \
	|| non "le hook 0500 ne donne pas son bit d'exécution à grub-defaut-voisin"
grep -q 'chmod 0755 .*grub-defaut-windows' "$HOOK0500" \
	&& ok "…et l'alias aussi (sinon il serait là sans pouvoir tourner)" \
	|| non "l'alias n'a pas son bit d'exécution"

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
