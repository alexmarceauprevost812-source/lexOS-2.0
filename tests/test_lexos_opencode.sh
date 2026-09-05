#!/usr/bin/env bash
# =============================================================================
#  Éprouver OpenCode dans LexOS — le paquet, l'icône, le lanceur
# =============================================================================
#  ALEX : « peux-tu faire en sorte qu'OpenCode s'installe sur LexOS pro », et
#  pour lever l'ambiguïté : « open source ». C'est opencode-ai, l'agent de
#  code en terminal, sous licence MIT.
#
#  CE QUE CE BANC PROTÈGE, ET POURQUOI CHACUN DE CES POINTS.
#
#  1. LE NOM DU PAQUET npm. « opencode-ai » et « opencode » existent TOUS LES
#     DEUX sur npm et ce ne sont pas les mêmes. Se tromper de nom n'échoue
#     pas : ça installe silencieusement autre chose, l'ISO sort avec un
#     programme qui n'est pas celui qu'Alex a demandé, et rien ne le dit. Le
#     bon nom est relevé dans le README du projet, pas écrit de mémoire.
#
#  2. TROIS ICÔNES DIFFÉRENTES. C'est une plainte réelle d'Alex, photo du
#     dock à l'appui : « deux étoiles Claude identiques, côte à côte ». Trois
#     lanceurs de terminal se suivent maintenant dans le dock — Terminal,
#     Claude Terminal, OpenCode — et une icône qui ne distingue pas n'est pas
#     une icône.
#
#  3. L'ICÔNE TIENT À 16 px. Le premier dessin était un « </> ». Rendu aux
#     tailles que le dock emploie vraiment et regardé agrandi, le trait
#     oblique colle aux chevrons et l'ensemble devient une tache. Deux
#     chevrons, eux, restent nets. Ce banc fige ce choix : deux formes
#     séparées, chacune assez grasse pour se voir.
#
#  4. LE HOOK TOURNE POUR DE VRAI, sur des dossiers à lui — pas une lecture
#     de son code source.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0425-lexos-opencode.hook.chroot"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-opencode"
LEXOS="$RACINE/config/includes.chroot/usr/bin/lexos"
SVG="$RACINE/branding/opencode-icon.svg"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$HOOK" "$OUTIL" "$SVG"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE NOM DU PAQUET — « opencode-ai », et pas « opencode »"
# =============================================================================
#  On lit le CODE, commentaires retirés : une mention du bon nom dans une
#  explication ne prouve pas que la commande l'emploie.
CODE_H="$(sed 's/#.*$//' "$HOOK")"
CODE_O="$(sed 's/#.*$//' "$OUTIL")"

if grep -q 'npm install -g opencode-ai@latest' <<< "$CODE_H" ; then
	ok "le hook installe bien « opencode-ai@latest »"
else
	non "le hook n'installe pas « opencode-ai@latest » — il poserait autre chose"
fi

#  ET SURTOUT PAS « opencode » TOUT COURT. On cherche la faute exacte :
#  « -g opencode » non suivi de « -ai ».
if grep -qE '\-g +opencode([^-]|$)' < <(printf '%s' "$CODE_H$CODE_O"); then
	non "un « npm install -g opencode » (sans « -ai ») traîne — ce n'est PAS le bon paquet"
else
	ok "aucun « npm install -g opencode » nu : le paquet voisin n'est jamais posé par erreur"
fi

if grep -q 'PAQUET_NPM="opencode-ai"' <<< "$CODE_O" ; then
	ok "le lanceur emploie le même nom de paquet que le hook"
else
	non "le lanceur et le hook ne s'accordent pas sur le nom du paquet"
fi

# =============================================================================
titre "2. LE HOOK TOURNE — icône aux huit tailles, lanceur posé"
# =============================================================================
if ! command -v rsvg-convert >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
	saute "ni rsvg-convert ni convert : le rendu de l'icône n'a PAS été éprouvé"
else
	SORTIE="$(LEXOS_ICONES_HICOLOR="$BANC/icons" LEXOS_APPS_DIR="$BANC/apps" \
		sh "$HOOK" 2>&1 || true)"

	MANQUE=""
	for T in 16 22 24 32 48 64 128 256; do
		[ -s "$BANC/icons/${T}x${T}/apps/lexos-opencode.png" ] || MANQUE="$MANQUE $T"
	done
	if [ -z "$MANQUE" ]; then
		ok "l'icône est rendue aux huit tailles du dock"
	else
		non "tailles manquantes :$MANQUE — l'icône changerait sous la souris"
	fi

	#  PAS de version vectorielle : à 83 px (le dock au survol) elle seule
	#  répondrait, et le dessin changerait au passage de la souris. C'est la
	#  panne du build 70, sur une autre icône.
	if [ -e "$BANC/icons/scalable/apps/lexos-opencode.svg" ]; then
		non "une version scalable est posée — le dessin changerait au survol"
	else
		ok "aucune version scalable : le dock ne peut pas changer de dessin au survol"
	fi

	D="$BANC/apps/lexos-opencode.desktop"
	if [ -s "$D" ]; then
		ok "le lanceur du dock est posé"
		grep -qx 'Exec=lexos-opencode --fenetre' "$D" \
			&& ok "il ouvre la fenêtre d'OpenCode, pas un shell nu" \
			|| non "Exec inattendu : $(grep '^Exec=' "$D")"
		grep -qx 'Icon=lexos-opencode' "$D" \
			&& ok "il pointe sur l'icône que le hook vient de rendre" \
			|| non "Icon ne correspond pas au nom rendu"
		grep -qx 'Terminal=false' "$D" \
			&& ok "Terminal=false : c'est le lanceur qui habille sa fenêtre" \
			|| non "Terminal=true ouvrirait une fenêtre sans habillage"
	else
		non "aucun lanceur .desktop posé"
	fi
fi

# =============================================================================
titre "3. L'ICÔNE SE LIT À 16 px — deux chevrons, pas une tache"
# =============================================================================
if ! command -v rsvg-convert >/dev/null 2>&1 || ! python3 -c "import PIL" 2>/dev/null; then
	saute "rsvg-convert ou Pillow absent : la lisibilité n'a PAS été mesurée"
else
	cat > "$BANC/formes.py" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
px = im.load()
#  Le vert du dessin, distingué du fond noir : canal vert franc ET nettement
#  au-dessus du rouge. Un seuil sur la seule luminosité prendrait aussi le
#  liseré clair du cadre.
vert = {(x, y) for y in range(h) for x in range(w)
        if px[x, y][1] > 90 and px[x, y][1] > px[x, y][0] + 25}
vus, groupes = set(), []
for p in vert:
    if p in vus:
        continue
    pile, taille = [p], 0
    while pile:
        q = pile.pop()
        if q in vus:
            continue
        vus.add(q); taille += 1
        x, y = q
        for v in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
            if v in vert and v not in vus:
                pile.append(v)
    groupes.append(taille)
groupes.sort()
print("%d %d" % (len(groupes), groupes[0] if groupes else 0))
PY
	rsvg-convert -w 16 -h 16 "$SVG" -o "$BANC/o16.png" 2>/dev/null
	LU="$(python3 "$BANC/formes.py" "$BANC/o16.png" 2>/dev/null)"
	NB="${LU%% *}"; PLUS_PETIT="${LU##* }"
	if [ "${NB:-0}" = "2" ]; then
		ok "à 16 px, le dessin fait DEUX formes séparées (les deux chevrons)"
	else
		non "à 16 px, ${NB:-0} forme(s) au lieu de 2 — le dessin ne se lit plus"
	fi
	#  Chacune doit peser : deux points isolés feraient aussi « deux formes »
	#  sans rien vouloir dire.
	if [ "${PLUS_PETIT:-0}" -ge 8 ]; then
		ok "et la plus petite des deux pèse ${PLUS_PETIT} pixels — elle se voit"
	else
		non "la plus petite forme ne fait que ${PLUS_PETIT:-0} pixels : invisible"
	fi
fi

# =============================================================================
titre "4. TROIS TERMINAUX, TROIS ICÔNES — la plainte d'Alex, en photo"
# =============================================================================
#  « Deux étoiles Claude identiques, côte à côte. Rien ne dit lequel ouvre
#  quoi. » Le dock en aligne maintenant trois.
if ! command -v rsvg-convert >/dev/null 2>&1 || ! command -v md5sum >/dev/null 2>&1; then
	saute "rsvg-convert ou md5sum absent : les icônes n'ont PAS été comparées"
else
	EMPREINTES=""; NOMS=""
	for I in opencode-icon claude-terminal-icon icon-terminal; do
		F="$RACINE/branding/${I}.svg"
		[ -r "$F" ] || continue
		rsvg-convert -w 48 -h 48 "$F" -o "$BANC/${I}.png" 2>/dev/null || continue
		EMPREINTES="$EMPREINTES $(md5sum "$BANC/${I}.png" | cut -d' ' -f1)"
		NOMS="$NOMS $I"
	done
	N="$(printf '%s\n' $EMPREINTES | grep -c .)"
	U="$(printf '%s\n' $EMPREINTES | sort -u | grep -c .)"
	if [ "$N" -ge 3 ] && [ "$N" = "$U" ]; then
		ok "les $N icônes de terminal sont toutes différentes ($NOMS)"
	elif [ "$N" -lt 3 ]; then
		non "seulement $N icônes trouvées — il en faut trois à comparer"
	else
		non "deux icônes identiques parmi :$NOMS — on ne saurait pas laquelle ouvre quoi"
	fi
fi

# =============================================================================
titre "5. LE LANCEUR — branché, et honnête quand OpenCode manque"
# =============================================================================
CODE_L="$(sed 's/#.*$//' "$LEXOS")"
if grep -q 'opencode|oc)' <<< "$CODE_L"; then
	ok "« lexos opencode » (et « lexos oc ») mènent à lexos-opencode"
else
	non "la commande « lexos opencode » n'est branchée nulle part"
fi
grep -q 'lexos-opencode' <<< "$CODE_L" \
	&& ok "l'aide de « lexos » nomme OpenCode" \
	|| non "OpenCode n'apparaît pas dans lexos"

#  SANS OpenCode installé, « --version » doit REFUSER avec un motif — pas
#  planter, pas répondre une version vide. On ferme le PATH pour de vrai.
VIDE="$BANC/path-vide"; mkdir -p "$VIDE"
for C in sh sed grep printf command; do
	P="$(command -v "$C" 2>/dev/null)" && ln -sf "$P" "$VIDE/$C"
done
SORTIE_V="$(PATH="$VIDE" HOME="$BANC" NO_COLOR=1 sh "$OUTIL" --version 2>&1)"
CODE_V=$?
if [ "$CODE_V" != "0" ] && grep -q "setup" <<< "$SORTIE_V"; then
	ok "sans OpenCode, « --version » refuse (code $CODE_V) en disant quoi faire"
else
	non "sans OpenCode, « --version » répond « $SORTIE_V » (code $CODE_V)"
fi

# =============================================================================
titre "6. LA LICENCE EST DITE — LexOS ne pose pas d'outil propriétaire"
# =============================================================================
#  Le dépôt s'est donné cette règle et la répète dans lexos-dualboot
#  (« Aucun outil propriétaire »). OpenCode est sous MIT ; que ce soit ÉCRIT
#  évite d'avoir à le redécouvrir.
if grep -qi "MIT" "$OUTIL" && grep -qi "MIT" "$RACINE/branding/opencode-icon.svg"; then
	ok "la licence MIT est nommée dans le lanceur et dans l'icône"
else
	non "la licence d'OpenCode n'est écrite nulle part"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
