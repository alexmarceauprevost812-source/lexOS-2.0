#!/usr/bin/env bash
# =============================================================================
#  Éprouver heure-dualboot — l'heure juste dans les DEUX systèmes
# =============================================================================
#  Linux garde l'horloge matérielle en UTC, Windows la lit en heure locale.
#  Sur une machine à double démarrage, chaque bascule décale donc l'heure de
#  l'autre — 4 h l'hiver, 5 h l'été au Québec. Le service aligne LexOS sur
#  Windows QUAND Windows est là, et ne touche à rien sinon.
#
#  Ce banc rejoue le vrai script. Deux rouages sont remplacés : timedatectl
#  (on ne va pas changer l'horloge de la machine qui fait tourner le banc) et
#  la racine, via les seams LEXOS_RACINE et LEXOS_CMDLINE, déjà employés par
#  gpu-garde et demo-guard.
#
#  CE QU'ON VÉRIFIE, ET POURQUOI CHAQUE CAS COMPTE :
#    · Windows dans le menu           -> l'horloge PASSE en heure locale ;
#    · pas de Windows                 -> RIEN n'est touché (UTC reste le
#      défaut de Debian, et une machine sans Windows n'a aucune raison d'en
#      changer) ;
#    · déjà en heure locale           -> on ne rappelle PAS la commande :
#      --adjust-system-clock décale l'heure système pour compenser, et le
#      faire deux fois décalerait deux fois ;
#    · session démo                   -> on sort tout de suite, le grub.cfg
#      lisible est celui de la clé USB, pas celui du disque ;
#    · pas de grub.cfg, pas de timedatectl -> on sort proprement, sans rien
#      écrire et sans échouer.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/lib/lexos/heure-dualboot"
SERVICE="$RACINE/config/includes.chroot/usr/lib/systemd/system/lexos-heure-dualboot.service"
HOOK="$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "heure-dualboot introuvable ou non exécutable"; exit 1; }

FAUXBIN="$BANC/bin"
FAUXRACINE="$BANC/racine"
APPELS="$BANC/appels"        # ce que timedatectl a reçu

#  Un faux timedatectl : il NOTE ce qu'on lui demande au lieu de le faire, et
#  répond ce que le cas d'essai veut pour « show -p LocalRTC ».
pose_timedatectl() { # pose_timedatectl <valeur LocalRTC : yes|no> [echec]
	mkdir -p "$FAUXBIN"
	cat > "$FAUXBIN/timedatectl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$APPELS"
case "\$*" in
	*"show -p LocalRTC"*) printf '%s\n' "$1"; exit 0 ;;
	*set-local-rtc*)      exit ${2:-0} ;;
esac
exit 0
EOF
	chmod +x "$FAUXBIN/timedatectl"
}

#  La fausse racine : un grub.cfg qui parle (ou non) de Windows.
pose_racine() { # pose_racine <contenu du grub.cfg, ou VIDE pour aucun fichier>
	rm -rf "$FAUXRACINE"
	mkdir -p "$FAUXRACINE/boot/grub" "$FAUXRACINE/var/log"
	if [ "$1" != "VIDE" ]; then
		printf '%s\n' "$1" > "$FAUXRACINE/boot/grub/grub.cfg"
	fi
}

pose_cmdline() { printf '%s\n' "$1" > "$BANC/cmdline"; }

lance() {
	: > "$APPELS"
	PATH="$FAUXBIN:$PATH" LEXOS_RACINE="$FAUXRACINE" LEXOS_CMDLINE="$BANC/cmdline" \
		sh "$OUTIL" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

a_regle_lhorloge() { grep -q 'set-local-rtc 1' "$APPELS"; }

MENU_WINDOWS="menuentry 'Windows Boot Manager (sur /dev/nvme0n1p1)' --class windows {"
MENU_SANS="menuentry 'LexOS GNU/Linux' --class lexos {"

# =============================================================================
titre "1. Windows est là -> l'horloge passe en heure locale"
# =============================================================================
pose_cmdline "BOOT_IMAGE=/vmlinuz root=/dev/nvme0n1p5 ro quiet"
pose_racine "$MENU_WINDOWS"
pose_timedatectl "no"
S="$(lance)"

a_regle_lhorloge \
	&& ok "timedatectl set-local-rtc 1 a bien été appelé" \
	|| non "l'horloge n'a PAS été réglée alors que Windows est dans le menu :\n$S"

grep -q 'adjust-system-clock' "$APPELS" \
	&& ok "…avec --adjust-system-clock (sinon l'heure affichée saute d'un coup)" \
	|| non "--adjust-system-clock manque : l'heure système sauterait de 4 h"

echo "$S" | grep -qi "heure locale" \
	&& ok "le journal dit ce qui a changé" \
	|| non "rien dans le journal :\n$S"

[ "$(cat "$BANC/code")" = "0" ] \
	&& ok "le script sort proprement (code 0)" \
	|| non "code de sortie inattendu : $(cat "$BANC/code")"

#  UNE ENTRÉE DE RÉCUPÉRATION WINDOWS COMPTE AUSSI. Contrairement à
#  grub-defaut-windows (qui les écarte : démarrer sur la récupération ne
#  lance pas Windows), ici la question est « Windows existe-t-il sur cette
#  machine ? » — et une partition de récupération Windows prouve que oui.
pose_racine "menuentry 'Windows Recovery Environment (sur /dev/sda3)' --class windows {"
pose_timedatectl "no"
lance >/dev/null
a_regle_lhorloge \
	&& ok "une entrée « Windows Recovery » suffit : Windows est bien sur la machine" \
	|| non "l'entrée de récupération Windows n'a pas été reconnue"

# =============================================================================
titre "2. Pas de Windows -> on ne touche À RIEN"
# =============================================================================
pose_racine "$MENU_SANS"
pose_timedatectl "no"
S="$(lance)"

a_regle_lhorloge \
	&& non "l'horloge a été changée sur une machine SANS Windows — UTC devait rester" \
	|| ok "aucune modification de l'horloge : UTC reste le défaut"

echo "$S" | grep -qi "pas de Windows" \
	&& ok "le journal dit pourquoi il n'a rien fait" \
	|| non "le journal n'explique pas l'abstention :\n$S"

# =============================================================================
titre "3. Déjà en heure locale -> on ne refait pas le réglage"
# =============================================================================
#  --adjust-system-clock DÉCALE l'heure système pour compenser le changement
#  de convention. L'appeler une deuxième fois la décalerait une deuxième
#  fois : l'horloge serait fausse de 8 h au lieu de 4.
pose_racine "$MENU_WINDOWS"
pose_timedatectl "yes"
S="$(lance)"

a_regle_lhorloge \
	&& non "set-local-rtc rappelé alors que LocalRTC était déjà « yes » — double décalage" \
	|| ok "rien n'est rappelé quand l'horloge est déjà en heure locale"

echo "$S" | grep -qi "déjà" \
	&& ok "le journal le dit" \
	|| non "le journal ne mentionne pas l'état déjà bon :\n$S"

# =============================================================================
titre "4. Les sorties propres — démo, pas de grub.cfg, pas de timedatectl"
# =============================================================================
#  SESSION DÉMO : le grub.cfg lisible est celui de la clé USB. Il ne parle pas
#  du Windows du disque, et l'horloge de la machine ne nous regarde pas tant
#  que rien n'est installé.
pose_cmdline "BOOT_IMAGE=/live/vmlinuz boot=live components quiet"
pose_racine "$MENU_WINDOWS"
pose_timedatectl "no"
S="$(lance)"
if a_regle_lhorloge; then
	non "l'horloge a été changée EN SESSION DÉMO"
else
	ok "session démo : le script sort sans rien toucher"
fi
[ "$(cat "$BANC/code")" = "0" ] \
	&& ok "…et sort avec le code 0, pas en erreur" \
	|| non "la sortie en démo n'est pas propre : code $(cat "$BANC/code")"

#  PAS DE GRUB.CFG : rien à lire, donc rien à conclure. Le cas arrive pour de
#  vrai — /boot séparé pas encore monté, installation en cours.
pose_cmdline "BOOT_IMAGE=/vmlinuz root=/dev/sda2 ro quiet"
pose_racine "VIDE"
pose_timedatectl "no"
S="$(lance)"
if a_regle_lhorloge; then
	non "l'horloge a été changée sans aucun grub.cfg à lire"
else
	ok "sans grub.cfg : aucune décision prise, aucune écriture"
fi
[ "$(cat "$BANC/code")" = "0" ] \
	&& ok "…et le script n'échoue pas pour autant" \
	|| non "absence de grub.cfg traitée comme une erreur : code $(cat "$BANC/code")"

#  ET IL DIT LA VRAIE RAISON. Sans grub.cfg, « pas de Windows dans le menu »
#  serait une phrase FAUSSE : on n'a pas lu de menu du tout, on ne sait donc
#  rien de Windows. Sans ce contrôle, retirer la garde du grub.cfg absent ne
#  changeait rien de visible — le script tombait dans la branche suivante et
#  affirmait qu'il n'y avait pas de Windows. Même comportement, mauvaise
#  explication : exactement le genre de phrase qui envoie chercher la panne
#  ailleurs six mois plus tard.
if echo "$S" | grep -qi "aucun grub.cfg"; then
	ok "…et le journal dit la VRAIE raison (grub.cfg illisible), pas « pas de Windows »"
else
	non "le journal n'explique pas que le grub.cfg est illisible :\n$S"
fi

#  PAS DE TIMEDATECTL : sur un système sans systemd, il n'y a rien à régler.
rm -f "$FAUXBIN/timedatectl"
pose_racine "$MENU_WINDOWS"
S="$(PATH="$FAUXBIN:/usr/bin:/bin" LEXOS_RACINE="$FAUXRACINE" LEXOS_CMDLINE="$BANC/cmdline" \
	sh "$OUTIL" 2>&1; echo "code=$?")"
if echo "$S" | grep -q "code=0"; then
	ok "sans timedatectl : sortie propre, code 0"
else
	non "sans timedatectl, le script échoue :\n$S"
fi

# =============================================================================
titre "5. Le service et son activation"
# =============================================================================
[ -r "$SERVICE" ] \
	&& ok "l'unité systemd existe" \
	|| non "config/includes.chroot/usr/lib/systemd/system/lexos-heure-dualboot.service absent"

grep -q '^ExecStart=/usr/lib/lexos/heure-dualboot' "$SERVICE" \
	&& ok "…et elle lance bien le script" \
	|| non "l'unité ne pointe pas sur /usr/lib/lexos/heure-dualboot"

grep -q '^Type=oneshot' "$SERVICE" \
	&& ok "…en oneshot, comme ses deux services frères" \
	|| non "l'unité n'est pas en Type=oneshot"

#  APRÈS local-fs.target : le script lit /boot/grub/grub.cfg, qui n'existe pas
#  avant sur une installation avec /boot séparé.
grep -q 'After=.*local-fs.target' "$SERVICE" \
	&& ok "…et après local-fs.target (sinon /boot n'est pas monté)" \
	|| non "l'unité ne dépend pas de local-fs.target"

grep -q '^WantedBy=multi-user.target' "$SERVICE" \
	&& ok "…et elle est installable (WantedBy)" \
	|| non "l'unité n'a pas de section [Install] utilisable"

grep -q 'systemctl enable lexos-heure-dualboot.service' "$HOOK" \
	&& ok "le hook 0500 l'active à la construction" \
	|| non "le hook 0500 n'active pas le service — il ne démarrerait jamais"

grep -q 'chmod 0755 /usr/lib/lexos/heure-dualboot' "$HOOK" \
	&& ok "…et lui donne son bit d'exécution" \
	|| non "le hook ne rend pas le script exécutable"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
