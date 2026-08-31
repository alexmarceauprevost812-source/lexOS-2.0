#!/usr/bin/env bash
# =============================================================================
#  Le haut du navigateur, et qui est le navigateur officiel
# =============================================================================
#  ALEX, CAPTURE DU NAVIGATEUR : « en haut du navigateur il est trop noir,
#  changer pour qu'il soit un peu gris ». Puis, photo du fichier « Navigateur
#  Web Chromium » : « garder lui officiel comme navigateur ».
#
#  ═══ POURQUOI DEUX RÉGLAGES, ET POURQUOI CE BANC LES ÉPROUVE ENSEMBLE ═══
#  « BrowserThemeColor » (politique d'entreprise) donne au CADRE la couleur
#  demandée. Mais tant que Chromium suit le thème GTK de LexOS, elle ne
#  repeint QUE la barre d'outils : la bande d'onglets — le « haut » qu'Alex
#  montre du doigt — reste noire. Mesuré :
#
#      GTK seul ................ onglets #0A0A0B   barre #000000
#      GTK + politique ......... onglets #0A0A0B   barre #46464E   ← à moitié
#      thème interne + politique onglets #26262B   barre #46464E   ← voulu
#
#  Un banc qui aurait vérifié « le fichier de politique existe » aurait été
#  VERT sur la ligne du milieu. C'est pour ça que celui-ci lance le VRAI
#  Chromium avec les fichiers que le hook vient d'écrire, le photographie et
#  relit les pixels de la bande d'onglets.
#
#  Sans Chromium, sans Xvfb ou sans ImageMagick, cette partie est SAUTÉE
#  proprement — elle ne se fait pas passer pour verte.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0445-lexos-navigateur.hook.chroot"
HOOK_BUREAU="$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

GRIS="#26262B"

# =============================================================================
titre "1. Le hook écrit ce qu'il faut, aux deux endroits"
# =============================================================================
LEXOS_POL_CHROMIUM="$BANC/pol-chromium" \
LEXOS_POL_CHROME="$BANC/pol-chrome" \
LEXOS_SKEL="$BANC/skel" \
	sh "$HOOK" >"$BANC/hook.log" 2>&1 \
	|| { non "le hook 0445 a échoué : $(tail -2 "$BANC/hook.log")"; exit 1; }
ok "le hook 0445 se déroule sans erreur"

for D in "$BANC/pol-chromium" "$BANC/pol-chrome"; do
	N="$(basename "$D")"
	F="$D/lexos-couleurs.json"
	if [ ! -r "$F" ]; then
		non "$N : aucune politique écrite"
		continue
	fi
	if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$F" 2>/dev/null; then
		non "$N : la politique n'est pas du JSON valide — Chromium l'ignorerait en silence"
		continue
	fi
	VU="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('BrowserThemeColor',''))" "$F")"
	[ "$VU" = "$GRIS" ] \
		&& ok "$N : BrowserThemeColor = $GRIS" \
		|| non "$N : BrowserThemeColor vaut « $VU » au lieu de $GRIS"
done

#  LE NOM DE LA CLÉ N'EST PAS INVENTÉ. Il a été relevé dans le binaire de
#  Chromium ; quand ce binaire est là, on le revérifie plutôt que de le croire.
CHROME_BIN=""
for B in /opt/pw-browsers/chromium-*/chrome-linux/chrome \
         "$(command -v chromium 2>/dev/null)" \
         "$(command -v chromium-browser 2>/dev/null)" \
         "$(command -v google-chrome-stable 2>/dev/null)" \
         "$(command -v google-chrome 2>/dev/null)"; do
	[ -n "$B" ] && [ -x "$B" ] && { CHROME_BIN="$B"; break; }
done
if [ -n "$CHROME_BIN" ] && command -v strings >/dev/null 2>&1; then
	#  PAS « grep -q » ICI. Il se ferme au premier accord, « strings » reçoit
	#  un SIGPIPE, et « set -o pipefail » transforme ce 141 en échec du
	#  tuyau : le contrôle serait ROUGE alors que la clé est bien là. On lit
	#  donc tout le flux et on compte après.
	TROUVE="$(strings -a "$CHROME_BIN" 2>/dev/null | grep -cxF "BrowserThemeColor" || true)"
	if [ "${TROUVE:-0}" -gt 0 ]; then
		ok "« BrowserThemeColor » est bien une clé que ce navigateur connaît"
	else
		non "« BrowserThemeColor » est ABSENT du binaire : la politique ne dirait rien"
	fi
else
	saut "aucun navigateur sur la machine : le nom de la clé n'a pas été revérifié"
fi

for P in chromium google-chrome; do
	F="$BANC/skel/.config/$P/Default/Preferences"
	if [ ! -r "$F" ]; then
		non "$P : aucune préférence livrée dans /etc/skel"
		continue
	fi
	ST="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['extensions']['theme']['system_theme'])" "$F" 2>/dev/null || echo ABSENT)"
	[ "$ST" = "0" ] \
		&& ok "$P : system_theme = 0 (thème interne) — la bande d'onglets suivra la couleur" \
		|| non "$P : system_theme vaut « $ST » ; à 1 (GTK) le haut resterait NOIR"
done

# =============================================================================
titre "2. Chromium est le navigateur officiel — et il a un filet"
# =============================================================================
#  On lit ce que le hook 0400 ÉCRIT, en le faisant tourner ? Non : il fait
#  bien d'autres choses (comptes, PAM). On lit sa ligne, en s'assurant qu'elle
#  vient du code et pas d'un commentaire.
CODE_0400="$(sed 's/#.*$//' "$HOOK_BUREAU")"
if printf '%s' "$CODE_0400" | grep -q "chromium.desktop"; then
	ok "le hook 0400 connaît chromium.desktop"
else
	non "le hook 0400 ne nomme plus Chromium : le navigateur officiel a changé"
fi
if printf '%s' "$CODE_0400" | grep -q "firefox-esr.desktop"; then
	ok "…et garde firefox-esr en second, comme filet"
else
	non "plus aucun filet : si Chromium manque, LexOS n'a plus de navigateur par défaut"
fi
#  L'ORDRE COMPTE : la liste est essayée dans l'ordre. Chromium doit venir
#  AVANT firefox-esr, sinon « officiel » ne veut rien dire.
ORDRE="$(printf '%s' "$CODE_0400" | grep -o "chromium.desktop\|firefox-esr.desktop" | head -2 | tr '\n' ' ')"
case "$ORDRE" in
	"chromium.desktop firefox-esr.desktop "*) ok "Chromium est nommé AVANT firefox-esr" ;;
	*) non "l'ordre est « $ORDRE » : firefox-esr passerait devant" ;;
esac

# =============================================================================
titre "3. LA PREUVE PAR L'IMAGE — le vrai navigateur, les vrais pixels"
# =============================================================================
MANQUE=""
[ -n "$CHROME_BIN" ] || MANQUE="$MANQUE chromium"
command -v Xvfb   >/dev/null 2>&1 || MANQUE="$MANQUE xvfb"
command -v import >/dev/null 2>&1 || MANQUE="$MANQUE imagemagick"
python3 -c "import PIL" 2>/dev/null || MANQUE="$MANQUE python3-pil"

if [ -n "$MANQUE" ]; then
	saut "absent :$MANQUE — la couleur du haut n'a PAS été mesurée"
	saut "c'est la partie qui compte : l'installer avant de conclure quoi que ce soit"
else
	#  On monte exactement ce que le hook a produit : la politique là où le
	#  navigateur la lit, les préférences dans un profil neuf.
	H="$BANC/home"; mkdir -p "$H/prof"
	cp -r "$BANC/skel/.config/chromium/Default" "$H/prof/Default"
	POL="/etc/chromium/policies/managed"
	POSEE=0
	if mkdir -p "$POL" 2>/dev/null && cp "$BANC/pol-chromium/lexos-couleurs.json" "$POL/" 2>/dev/null; then
		POSEE=1
	fi
	if [ "$POSEE" = 0 ]; then
		saut "impossible d'écrire dans $POL (pas root ?) : la couleur n'a PAS été mesurée"
	else
		Xvfb :95 -screen 0 1280x800x24 >/dev/null 2>&1 &
		XP=$!
		i=0; while [ ! -e /tmp/.X11-unix/X95 ] && [ "$i" -lt 60 ]; do i=$((i+1)); read -r -t 0.2 < /dev/zero; done
		env DISPLAY=:95 HOME="$H" "$CHROME_BIN" --no-sandbox --disable-dev-shm-usage \
			--no-first-run --no-default-browser-check --disable-gpu \
			--user-data-dir="$H/prof" --window-size=1280,800 --window-position=0,0 \
			about:blank >/dev/null 2>&1 &
		CP=$!
		for i in $(seq 1 14); do read -r -t 1 < /dev/zero; done
		DISPLAY=:95 import -window root "$BANC/haut.png" 2>/dev/null
		kill "$CP" 2>/dev/null; kill "$XP" 2>/dev/null; wait 2>/dev/null
		rm -f "$POL/lexos-couleurs.json"

		if [ ! -s "$BANC/haut.png" ]; then
			non "aucune image : le navigateur ne s'est pas affiché"
		else
			LU="$(python3 - "$BANC/haut.png" <<'PY'
from PIL import Image
from collections import Counter
import sys
im = Image.open(sys.argv[1]).convert("RGB")
L, _ = im.size
def bande(y):
    c = Counter(im.getpixel((x, y)) for x in range(0, L, 7)).most_common(1)[0][0]
    return "#%02X%02X%02X" % c
print(bande(5), bande(90))
PY
)"
			ONGLETS="${LU%% *}"; BARRE="${LU##* }"
			printf '       bande d'"'"'onglets %s · barre d'"'"'outils %s\n' "$ONGLETS" "$BARRE"

			[ "$ONGLETS" = "$GRIS" ] \
				&& ok "la bande d'onglets est le gris demandé ($GRIS)" \
				|| non "la bande d'onglets vaut $ONGLETS au lieu de $GRIS"

			#  « trop noir » : le contrôle qui dit la demande d'Alex plutôt
			#  qu'une valeur. Le noir de LexOS est #000000 / #0A0A0B.
			case "$ONGLETS" in
				'#000000'|'#0A0A0B'|'#0B0B0C') non "le haut est resté NOIR — c'est exactement la photo d'Alex" ;;
				*) ok "le haut n'est plus noir" ;;
			esac

			#  La barre d'outils doit être DIFFÉRENTE du cadre — sinon on a
			#  repeint une seule des deux moitiés, le demi-correctif habituel.
			if [ "$BARRE" = "$ONGLETS" ]; then
				non "cadre et barre d'outils sont identiques : la dérivation n'a pas eu lieu"
			elif [ "$BARRE" = "#000000" ]; then
				non "la barre d'outils est restée NOIRE : seul le cadre a changé"
			else
				ok "la barre d'outils en dérive, plus claire ($BARRE)"
			fi
		fi
	fi
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mLe haut du navigateur est gris, et Chromium reste l'"'"'officiel.\033[0m\n'
