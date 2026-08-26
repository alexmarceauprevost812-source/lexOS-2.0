#!/usr/bin/env bash
# =============================================================================
#  Éprouver le partage d'écran (greffon « grid ») sous Compiz
# =============================================================================
#  ALEX : « quand on met une fenêtre dans le coin, qu'elle se divise à 50 %
#  de l'écran, pour pouvoir en mettre une autre à côté — comme Ubuntu ». Puis,
#  message suivant : un aperçu doit se voir dès que la souris touche le bord.
#
#  CE QUI MANQUAIT. xfwm4 sait déjà faire ça (xfwm4.xml : tile_on_move=true,
#  plus les raccourcis Super+Gauche/Droite/Origine/Page…/Fin dans
#  xfce4-keyboard-shortcuts.xml) — mais lexos-wm REMPLACE xfwm4 par Compiz dès
#  qu'une accélération 3D réelle est détectée, et Compiz gère alors les
#  fenêtres avec ses PROPRES greffons. Le greffon qui fait ce geste-là,
#  « grid », n'était pas dans la liste active : sur une machine où Compiz
#  démarre, glisser une fenêtre vers un bord ne faisait STRICTEMENT RIEN.
#
#  CE BANC PROUVE DEUX CHOSES, PAS UNE SEULE :
#    1. Le fichier dconf compile pour de vrai (le même « dconf compile » que
#       lance le hook 0600) — une virgule oubliée dans une liste GVariant ne
#       casserait pas la construction, juste TOUT l'effet visuel, en silence.
#    2. Les valeurs sont les BONNES — lues dans le vrai grid.xml du paquet
#       Debian (0=Aucune … 4=Moitié gauche … 6=Moitié droite … 10=Maximiser),
#       pas devinées : un 4 et un 6 inversés donnerait la moitié à l'envers,
#       sans qu'aucune erreur ne le signale jamais.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPIZ_DB="$RACINE/config/includes.chroot/etc/dconf/db/local.d/01-lexos-compiz"
XFWM4_XML="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
RACCOURCIS_XML="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$COMPIZ_DB" ] || { echo "01-lexos-compiz introuvable"; exit 1; }

# =============================================================================
titre "1. Le greffon « grid » est réellement chargé"
# =============================================================================
LIGNE_ACTIVE="$(grep '^active-plugins=' "$COMPIZ_DB")"
case "$LIGNE_ACTIVE" in
	*"'grid'"*) ok "« grid » figure dans active-plugins — sans lui, tout le reste de ce fichier ne sert à rien" ;;
	*) non "« grid » est ABSENT de active-plugins : glisser une fenêtre vers un bord ne ferait rien sous Compiz" ;;
esac

#  Dépendance réelle du greffon (lue dans grid.xml : requiert « opengl »,
#  doit charger après composite/opengl/decor). On ne réclame pas l'ordre
#  exact, seulement que les trois soient présents AVANT « grid » dans la
#  liste — Compiz charge dans l'ordre donné.
POSITION_GRID="$(echo "$LIGNE_ACTIVE" | tr ',' '\n' | grep -n "'grid'" | cut -d: -f1)"
MANQUE=0
for DEP in composite opengl decor; do
	POS_DEP="$(echo "$LIGNE_ACTIVE" | tr ',' '\n' | grep -n "'$DEP'" | cut -d: -f1)"
	if [ -z "$POS_DEP" ] || [ -z "$POSITION_GRID" ] || [ "$POS_DEP" -ge "$POSITION_GRID" ]; then
		non "« $DEP » doit charger AVANT « grid » (dépendance réelle de grid.xml) — ordre actuel invalide"
		MANQUE=1
	fi
done
[ "$MANQUE" -eq 0 ] && ok "composite, opengl et decor chargent tous avant « grid », comme grid.xml l'exige"

# =============================================================================
titre "2. Les bords : gauche/droite donnent bien une MOITIÉ (pas autre chose)"
# =============================================================================
#  Valeurs de grid.xml, lues dans le vrai paquet compiz-plugins-default :
#  4 = Moitié gauche, 6 = Moitié droite. Le cœur de la demande d'Alex.
grep -qE '^left-edge-action=4$'  "$COMPIZ_DB" \
	&& ok "glisser à GAUCHE -> 4 (Moitié gauche)" \
	|| non "left-edge-action n'est pas 4 (Moitié gauche) — la demande d'Alex, ratée"
grep -qE '^right-edge-action=6$' "$COMPIZ_DB" \
	&& ok "glisser à DROITE -> 6 (Moitié droite)" \
	|| non "right-edge-action n'est pas 6 (Moitié droite) — « à droite, pareil comme Ubuntu »"

# =============================================================================
titre "3. Les quatre coins : un quart chacun, pour quatre fenêtres à la fois"
# =============================================================================
declare -A COINS=(
	[top-left-corner-action]=7
	[top-right-corner-action]=9
	[bottom-left-corner-action]=1
	[bottom-right-corner-action]=3
)
for CLE in "${!COINS[@]}"; do
	grep -qE "^${CLE}=${COINS[$CLE]}\$" "$COMPIZ_DB" \
		&& ok "$CLE = ${COINS[$CLE]}" \
		|| non "$CLE devrait valoir ${COINS[$CLE]} (un quart d'écran) — valeur absente ou fausse"
done

# =============================================================================
titre "4. L'aperçu pendant le glisser, demandé dans le message suivant"
# =============================================================================
grep -qE '^draw-indicator=true$' "$COMPIZ_DB" \
	&& ok "draw-indicator=true — le rectangle d'aperçu s'affiche dès que la souris touche le bord" \
	|| non "draw-indicator absent ou faux : aucun aperçu ne s'afficherait pendant le glisser"
grep -qE '^draw-stretched-window=true$' "$COMPIZ_DB" \
	&& ok "draw-stretched-window=true — le contenu de la fenêtre s'étire déjà vers sa place" \
	|| non "draw-stretched-window absent ou faux"

# =============================================================================
titre "5. Les mêmes touches que xfwm4 — peu importe lequel démarre pour de vrai"
# =============================================================================
#  lexos-wm choisit xfwm4 OU Compiz selon le matériel, à l'exécution. Si les
#  deux n'utilisent pas les mêmes raccourcis, le clavier d'Alex changerait de
#  comportement d'une machine à l'autre sans qu'il ait rien changé lui-même.
[ -r "$XFWM4_XML" ] && [ -r "$RACCOURCIS_XML" ] || { echo "fichiers xfwm4 introuvables"; exit 1; }

declare -A PAIRES=(
	["put-left-key='<Super>Left'"]="tile_left_key"
	["put-right-key='<Super>Right'"]="tile_right_key"
	["put-topleft-key='<Super>Home'"]="tile_up_left_key"
	["put-topright-key='<Super>Page_Up'"]="tile_up_right_key"
	["put-bottomleft-key='<Super>End'"]="tile_down_left_key"
	["put-bottomright-key='<Super>Page_Down'"]="tile_down_right_key"
	["put-maximize-key='<Super>Up'"]="maximize_window_key"
	["put-restore-key='<Super>Down'"]="unmaximize_window_key"
)
DESACCORD=0
for CLE_COMPIZ in "${!PAIRES[@]}"; do
	ACTION_XFWM4="${PAIRES[$CLE_COMPIZ]}"
	#  Retrouve la touche xfwm4 assignée à cette action (ex. « &lt;Super&gt;Left »),
	#  puis vérifie que Compiz porte la MÊME touche pour le geste équivalent.
	TOUCHE_XFWM4="$(grep -F "value=\"$ACTION_XFWM4\"" "$RACCOURCIS_XML" \
		| sed -n 's/.*<property name="\([^"]*\)".*/\1/p' | head -1)"
	if [ -z "$TOUCHE_XFWM4" ]; then
		non "« $ACTION_XFWM4 » n'existe pas côté xfwm4 (xfce4-keyboard-shortcuts.xml) — rien à comparer"
		DESACCORD=1
		continue
	fi
	TOUCHE_XFWM4_DEDECODE="$(printf '%s' "$TOUCHE_XFWM4" | sed 's/&lt;/</g; s/&gt;/>/g')"
	ATTENDU="'${TOUCHE_XFWM4_DEDECODE}'"
	if grep -qF "${CLE_COMPIZ%%=*}=$ATTENDU" "$COMPIZ_DB"; then
		:  # ok, vérifié en bloc plus bas pour ne pas noyer la sortie
	else
		non "« $ACTION_XFWM4 » = ${TOUCHE_XFWM4_DEDECODE} côté xfwm4, mais Compiz n'a pas la même touche"
		DESACCORD=1
	fi
done
[ "$DESACCORD" -eq 0 ] \
	&& ok "les huit gestes de partage ont EXACTEMENT la même touche sous Compiz et sous xfwm4" \
	|| : # les échecs, s'il y en a, ont déjà été comptés un par un ci-dessus

# =============================================================================
titre "6. Le fichier compile pour de vrai (dconf compile, comme le hook 0600)"
# =============================================================================
if command -v dconf >/dev/null 2>&1 || apt-get install -y dconf-cli >/dev/null 2>&1; then
	DEST="$BANC/db.d"; mkdir -p "$DEST"
	cp "$COMPIZ_DB" "$DEST/"
	if dconf compile "$BANC/compile-verif" "$DEST" 2>"$BANC/erreur.txt"; then
		ok "dconf compile réussit sur 01-lexos-compiz — la syntaxe GVariant est valide"
	else
		non "dconf compile ÉCHOUE : $(cat "$BANC/erreur.txt")"
	fi
else
	echo "  (dconf indisponible sur ce banc — section sautée, pas déclarée réussie)"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
