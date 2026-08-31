#!/usr/bin/env bash
# =============================================================================
#  Les applications Qt suivent le sombre — sans un kit par application
# =============================================================================
#  ALEX : « pour pas avoir à changer les couleurs et tout le kit sur chaque
#  appli ». LexOS embarque SEPT applications Qt — audacity, flameshot,
#  kdenlive, keepassxc, krita, scribus, vlc — et RIEN ne leur disait de suivre
#  le thème. Elles s'ouvraient BLANCHES au milieu d'un bureau noir.
#
#  ═══ DEUX VARIABLES, DEUX RÔLES, ET LA PREMIÈRE NE SUFFIT PAS ═══
#  On aurait pu s'arrêter à « QT_QPA_PLATFORMTHEME=gtk3 », le réglage qu'on
#  cite partout. Mesure sur le VRAI flameshot sous Xvfb, fond de sa fenêtre
#  relevé au pixel :
#
#     rien ............................ #FBFBFB  (blanc)
#     QT_QPA_PLATFORMTHEME=gtk3 ....... #FBFBFB  (blanc)
#     QT_STYLE_OVERRIDE=Adwaita-Dark .. #303030  (sombre)
#
#  Le greffon gtk3 EST bien chargé — vérifié avec QT_DEBUG_PLUGINS, il
#  apparaît dans le journal — mais celui de Qt5 fournit les dialogues, les
#  polices et les icônes, PAS la palette. C'est le STYLE qui peint. Un banc
#  qui se serait contenté de vérifier la présence de la variable aurait été
#  vert sur un bureau resté blanc.
#
#  ON GARDE LES DEUX : la couleur d'un côté, les fenêtres « ouvrir un
#  fichier » du système de l'autre.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot"
LISTE="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages/20-desktop.list"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

STYLE="Adwaita-Dark"

# =============================================================================
titre "1. Ce qu'il faut est dans l'ISO"
# =============================================================================
#  Sans le paquet, la variable ne désigne rien : Qt cherche un style qui
#  n'existe pas, n'en dit rien, et retombe sur le blanc.
MANQUE=""
for P in adwaita-qt adwaita-qt6 qt5-gtk-platformtheme qt6-gtk-platformtheme; do
	grep -qx "$P" "$LISTE" || MANQUE="$MANQUE $P"
done
[ -z "$MANQUE" ] \
	&& ok "les quatre paquets Qt sont dans 20-desktop.list" \
	|| non "paquets ABSENTS de la liste :$MANQUE"

# =============================================================================
titre "2. Les variables sont posées là où une session graphique les lit"
# =============================================================================
#  /etc/environment ET PAS profile.d : profile.d n'est lu que par un shell de
#  CONNEXION. Une application lancée depuis le dock n'en voit rien.
#  /etc/environment est lu par PAM, donc par toute session graphique.
printf 'PATH="/usr/bin"\n' > "$BANC/env"
BLOC="$(awk '/^ENVF=/,/^fi$/' "$HOOK")"
if [ -z "$BLOC" ]; then
	non "le bloc qui écrit les variables est introuvable dans le hook"
else
	printf '%s' "$BLOC" | LEXOS_ENVIRONMENT="$BANC/env" sh >/dev/null 2>&1
	for V in "QT_QPA_PLATFORMTHEME=gtk3" "QT_STYLE_OVERRIDE=$STYLE"; do
		grep -qx "$V" "$BANC/env" \
			&& ok "« $V » posé" \
			|| non "« $V » ABSENT du fichier d'environnement"
	done
	#  ON AJOUTE, ON N'ÉCRASE PAS : Debian y met PATH.
	grep -q '^PATH=' "$BANC/env" \
		&& ok "le PATH de Debian survit — on ajoute, on ne réécrit pas" \
		|| non "le fichier a été écrasé : le PATH de Debian a disparu"
	#  ET DEUX FOIS NE FAIT PAS DEUX LIGNES.
	printf '%s' "$BLOC" | LEXOS_ENVIRONMENT="$BANC/env" sh >/dev/null 2>&1
	N="$(grep -c "^QT_STYLE_OVERRIDE=" "$BANC/env")"
	[ "$N" = 1 ] \
		&& ok "rejouer le hook n'empile pas les lignes" \
		|| non "$N lignes QT_STYLE_OVERRIDE : le hook s'empile sur lui-même"
fi

# =============================================================================
titre "3. LA PREUVE PAR L'IMAGE — une vraie application Qt"
# =============================================================================
#  C'est la partie qui compte. Vérifier la présence d'une variable ne prouve
#  RIEN : « QT_QPA_PLATFORMTHEME=gtk3 » est posé, chargé, et laisse la
#  fenêtre blanche. Seul le pixel tranche.
MANQUE=""
command -v flameshot >/dev/null 2>&1 || MANQUE="$MANQUE flameshot"
command -v Xvfb      >/dev/null 2>&1 || MANQUE="$MANQUE xvfb"
command -v import    >/dev/null 2>&1 || MANQUE="$MANQUE imagemagick"
python3 -c "import PIL" 2>/dev/null   || MANQUE="$MANQUE python3-pil"
ls /usr/lib/*/qt5/plugins/styles/adwaita.so >/dev/null 2>&1 || MANQUE="$MANQUE adwaita-qt"

if [ -n "$MANQUE" ]; then
	saut "absent :$MANQUE — la couleur des applications Qt n'a PAS été mesurée"
	saut "c'est la partie qui compte : l'installer avant de conclure"
else
	essai() { # essai <nom> <style|"">
		local H="$BANC/$1"
		mkdir -p "$H/.config/gtk-3.0"
		printf '[Settings]\ngtk-theme-name=Adwaita\ngtk-application-prefer-dark-theme=true\n' \
			> "$H/.config/gtk-3.0/settings.ini"
		Xvfb :89 -screen 0 900x700x24 >/dev/null 2>&1 &
		local XP=$!
		local i=0
		while [ ! -e /tmp/.X11-unix/X89 ] && [ "$i" -lt 60 ]; do i=$((i+1)); read -r -t 0.2 < /dev/zero; done
		env DISPLAY=:89 HOME="$H" QT_QPA_PLATFORMTHEME=gtk3 \
			${2:+QT_STYLE_OVERRIDE="$2"} flameshot config >/dev/null 2>&1 &
		local FP=$!
		for i in $(seq 1 8); do read -r -t 1 < /dev/zero; done
		DISPLAY=:89 import -window root "$BANC/$1.png" 2>/dev/null
		kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; wait 2>/dev/null
	}
	fond() { python3 - "$1" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
W, H = im.size
#  La fenêtre est posée sur un fond noir : on la borne, puis on relève un
#  point franchement DANS son corps — pas sur un bord, pas sur un onglet.
xs = [x for x in range(0, W, 4) for y in range(0, H, 4) if im.getpixel((x, y)) != (0, 0, 0)]
ys = [y for y in range(0, H, 4) for x in range(0, W, 4) if im.getpixel((x, y)) != (0, 0, 0)]
if not xs:
    print("AUCUNE-FENETRE"); sys.exit()
print("#%02X%02X%02X" % im.getpixel((min(xs) + 20, min(ys) + 120)))
PY
}
	essai qt-sans ""
	essai qt-avec "$STYLE"
	SANS="$(fond "$BANC/qt-sans.png")"; AVEC="$(fond "$BANC/qt-avec.png")"
	printf '       sans le style %s · avec %s\n' "$SANS" "$AVEC"

	if [ "$SANS" = "AUCUNE-FENETRE" ] || [ "$AVEC" = "AUCUNE-FENETRE" ]; then
		non "l'application Qt ne s'est pas affichée : rien n'a été mesuré"
	else
		#  CLAIR = illisible sur le bureau noir de LexOS. On mesure la
		#  clarté plutôt qu'une teinte précise : le jour où le style change
		#  de nom, c'est « sombre ou pas » qui doit rester vrai.
		CLAIR="$(python3 -c "
import sys
h='$AVEC'.lstrip('#')
print(sum(int(h[i:i+2],16) for i in (0,2,4)) // 3)")"
		if [ "$CLAIR" -lt 90 ]; then
			ok "avec le style, la fenêtre Qt est SOMBRE ($AVEC)"
		else
			non "avec le style, la fenêtre Qt reste claire ($AVEC) — le réglage ne peint pas"
		fi
		if [ "$SANS" = "$AVEC" ]; then
			non "le style ne change RIEN : la variable ne sert à rien"
		else
			ok "le style change vraiment la fenêtre ($SANS → $AVEC)"
		fi
	fi
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mLes applications Qt suivent le sombre, sans un kit chacune.\033[0m\n'
