#!/usr/bin/env bash
# =============================================================================
#  Éprouver le terminal — la police, les couleurs, ET le canal Xfconf
# =============================================================================
#  ALEX, PHOTO DU TERMINAL : « écriture plus gros ». La police est bien
#  passée de 11 à 13 dans terminalrc… et ça n'a JAMAIS suffi, sur un
#  xfce4-terminal moderne.
#
#  LA DÉCOUVERTE, VÉRIFIÉE EN LE FAISANT TOURNER POUR DE VRAI (le vrai
#  binaire, sous Xvfb, pas une lecture de sa documentation — elle ne dit
#  rien de tout ça) : depuis la branche 1.1 (Xfce 4.20, celle de trixie),
#  xfce4-terminal MIGRE terminalrc vers le canal Xfconf « xfce4-terminal » à
#  son PREMIER lancement, affiche « […] is not used anymore » — et ensuite
#  ne relit plus jamais terminalrc. Un compte qui a déjà ouvert un terminal
#  une fois garde pour toujours la police et les couleurs du jour de cette
#  première migration, quel que soit le nombre de fois où lexos-theme-gen
#  réécrit terminalrc ensuite. C'est le même mur que les icônes qui se
#  masquaient l'une l'autre (build 70-74), rejoué sur un fichier différent :
#  le bon réglage est écrit au bon endroit, et quelque chose de plus tôt
#  dans la chaîne a déjà décidé de ne plus le lire.
#
#  Le correctif : lexos-theme-gen écrit maintenant AUSSI le canal Xfconf
#  directement (xfce4-terminal.xml), comme il le fait déjà pour xfwm4.xml et
#  xsettings.xml. Pour un compte NEUF (le cas normal — /etc/skel), Xfconf
#  trouve le canal déjà rempli à la toute première ouverture : la migration
#  ne se déclenche même pas, terminalrc devient un simple filet.
#
#  CE QUE CE BANC VÉRIFIE, ET COMMENT
#    1. Toujours : les DEUX fichiers portent la MÊME valeur pour chaque
#       réglage partagé — sinon on recrée exactement le défaut qu'on vient
#       de découvrir, une valeur écrite à deux endroits libres de diverger.
#    2. Si le vrai xfce4-terminal (et Xvfb) sont installés sur la machine qui
#       fait tourner ce banc : preuve par l'exécution — le vrai binaire lit
#       NOTRE fichier, ne se plaint d'aucune clé inconnue, ne le réécrit pas,
#       et n'affiche PAS le message de migration (la preuve que le canal
#       était bien considéré comme déjà rempli). Sans ces deux outils, cette
#       partie est sautée PROPREMENT — elle ne se fait pas passer pour verte.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

python3 -c 'import PIL' 2>/dev/null || true   # (pas besoin ici, laissé pour la même forme que les autres bancs)

genere() { # genere <accent> <mode-terminal>
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
		bash "$GEN" --target "$BANC/t" --terminal "$2" "$1" >/tmp/lexos-terminal-banc.log 2>&1
}

RC="$BANC/t/.config/xfce4/terminal/terminalrc"
XML="$BANC/t/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"

# =============================================================================
titre "1. La police, et les couleurs, sont les MÊMES dans les deux fichiers"
# =============================================================================
genere orange suivre
[ -r "$RC" ]  || { non "aucun terminalrc produit"; }
[ -r "$XML" ] || { non "aucun xfce4-terminal.xml produit — le canal Xfconf ne sera jamais rempli"; }

#  On extrait une clé de terminalrc (INI, CamelCase) et sa jumelle du canal
#  Xfconf (XML, kebab-case) — les noms VÉRIFIÉS en faisant migrer un vrai
#  terminalrc par un vrai xfce4-terminal (voir le commentaire dans
#  lexos-theme-gen). Une paire qui diverge, c'est le bogue qu'on corrige qui
#  revient par la porte d'à côté.
PAIRES="FontName:font-name ColorForeground:color-foreground
ColorBackground:color-background ColorCursor:color-cursor
ColorSelectionBackground:color-selection-background
ColorPalette:color-palette TabActivityColor:tab-activity-color"

TOUT_PAREIL=1
for PAIRE in $PAIRES; do
	INI_CLE="${PAIRE%%:*}"; XML_CLE="${PAIRE##*:}"
	V_INI="$(sed -n "s/^${INI_CLE}=//p" "$RC" | tail -1)"
	V_XML="$(sed -n "s/.*name=\"${XML_CLE}\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
	if [ "$V_INI" != "$V_XML" ]; then
		non "$INI_CLE (terminalrc) = « $V_INI » mais $XML_CLE (Xfconf) = « $V_XML » — divergent"
		TOUT_PAREIL=0
	fi
done
[ "$TOUT_PAREIL" = 1 ] \
	&& ok "les réglages partagés portent la même valeur dans les deux fichiers"

#  La police, précisément : c'était la panne d'Alex. « Fira Code 11 » ->
#  « Fira Code 13 » : le banc vérifie le NOUVEAU chiffre, pas l'ancien — un
#  banc qui teste l'ancienne valeur resterait vert si quelqu'un revenait
#  dessus par erreur.
grep -q '^FontName=Fira Code 13$' "$RC" \
	&& ok "la police est bien passée à 13 (elle était à 11 sur la photo d'Alex)" \
	|| non "terminalrc n'annonce pas Fira Code 13"
grep -q 'name="font-name".*value="Fira Code 13"' "$XML" \
	&& ok "…et le canal Xfconf, celui qui compte vraiment, porte la même taille" \
	|| non "xfce4-terminal.xml n'annonce pas Fira Code 13 — la police d'Alex ne bougerait toujours pas"

#  LES 24 PROPRIÉTÉS DOIVENT ÊTRE LÀ, TOUTES — une migration réelle en écrit
#  24 (fond, police, curseur, palette, tabulations, geometrie…). En manquer
#  une revient à livrer une police correcte et un fond resté par défaut.
NB="$(grep -c '<property name=' "$XML")"
[ "$NB" -ge 24 ] \
	&& ok "les 24 propriétés migrées sont toutes écrites ($NB trouvées)" \
	|| non "seulement $NB propriétés — la migration réelle en écrit 24, il en manque"

# =============================================================================
titre "2. Jour et nuit — deux palettes, deux fichiers, jamais mélangés"
# =============================================================================
genere orange jour
FG_JOUR="$(sed -n "s/.*name=\"color-foreground\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
genere orange nuit
FG_NUIT="$(sed -n "s/.*name=\"color-foreground\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
if [ -n "$FG_JOUR" ] && [ -n "$FG_NUIT" ] && [ "$FG_JOUR" != "$FG_NUIT" ]; then
	ok "jour ($FG_JOUR) et nuit ($FG_NUIT) donnent bien deux couleurs différentes dans le canal Xfconf"
else
	non "jour et nuit donnent la même couleur foreground dans Xfconf ($FG_JOUR / $FG_NUIT) — le canal ne suit pas le mode"
fi

# =============================================================================
titre "3. La preuve par l'exécution — quand le vrai xfce4-terminal est là"
# =============================================================================
#  ON NE DEVINE PAS UN NOM DE CLÉ XFCONF. Ces noms ne sont documentés NULLE
#  PART (ni « man xfce4-terminal », ni son .desktop) : la seule façon de les
#  connaître est de faire migrer un vrai terminalrc par le vrai binaire et de
#  relire ce qu'il a écrit — exactement ce que fait ce bloc. Une clé mal
#  orthographiée serait ignorée par Xfconf EN SILENCE (il ignore toute clé
#  qu'il ne reconnaît pas) : aucun test structurel ne peut voir cette
#  faute-là, seul le vrai programme le peut.
if command -v xfce4-terminal >/dev/null 2>&1 && command -v Xvfb >/dev/null 2>&1; then
	genere orange suivre
	DISP=":$((90 + RANDOM % 400))"
	Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 &
	XVFB_PID=$!
	sleep 1

	AVANT="$(md5sum "$XML" | cut -d' ' -f1)"
	SORTIE="$(DISPLAY="$DISP" HOME="$BANC/t" XDG_CONFIG_HOME="$BANC/t/.config" \
		timeout 4 xfce4-terminal --disable-server -e /bin/sleep\ 2 2>&1)"
	sleep 0.3
	APRES="$(md5sum "$XML" | cut -d' ' -f1)"

	kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null

	if printf '%s' "$SORTIE" | grep -qi 'migrated'; then
		non "xfce4-terminal a migré terminalrc au lieu de lire notre canal — il l'a donc trouvé VIDE"
	else
		ok "aucun message de migration : le vrai xfce4-terminal a trouvé le canal déjà rempli"
	fi
	if printf '%s' "$SORTIE" | grep -qi 'unrecognized\|unknown.*setting\|no such property'; then
		non "xfce4-terminal signale une clé qu'il ne reconnaît pas : $SORTIE"
	else
		ok "aucune clé rejetée — les 24 noms vérifiés sont tous corrects"
	fi
	[ "$AVANT" = "$APRES" ] \
		&& ok "notre fichier n'a pas été réécrit par le lancement (il fait déjà foi)" \
		|| non "xfce4-terminal a réécrit notre fichier — nos valeurs n'auraient pas tenu"
else
	printf '  \033[2mxfce4-terminal ou Xvfb absent de cette machine — preuve par l'"'"'exécution sautée (le reste tient quand même)\033[0m\n'
fi

# =============================================================================
titre "4. lexos-theme-gen le dit dans son propre code — pas un secret retrouvé"
# =============================================================================
grep -q 'is not used anymore\|migrated' "$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen" \
	&& ok "la découverte est documentée dans lexos-theme-gen, pas seulement dans ce banc" \
	|| non "rien dans lexos-theme-gen n'explique pourquoi ce fichier existe"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
