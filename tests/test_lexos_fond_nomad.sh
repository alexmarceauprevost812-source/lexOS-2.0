#!/usr/bin/env bash
# =============================================================================
#  Le fond d'écran « Nomad » — celui de la démo, disponible sur l'ISO
# =============================================================================
#  ALEX, capture de la démo à l'appui : « ajouter ce fond d'écran officiel
#  comme fond d'écran », puis, plus précis : « mettre ces images dans l'ISO 96,
#  dans le fichier images, si je veux les avoir comme fond d'écran ».
#
#  Il ne demande donc pas qu'on lui IMPOSE ce fond : il demande qu'il soit LÀ,
#  choisissable. Ce banc éprouve exactement ça — l'image existe, elle est
#  rendue là où le sélecteur regarde, et les deux chemins qui mènent au choix
#  (Paramètres et « lexos fond-ecran ») la voient.
#
#  ═══ POURQUOI LE LOGO N'EST PAS DU TEXTE, ET POURQUOI ÇA SE VÉRIFIE ═══
#  Un dessin ASCII n'a de sens que si chaque caractère occupe la même chasse.
#  Le confier à une police, c'est parier qu'elle sera installée au moment où
#  le crochet 0300 rend l'image — or fonts-firacode et fonts-dejavu voyagent
#  dans une liste OPTIONNELLE. Un repli non monospace ne casserait pas la
#  construction : il produirait une bouillie, en silence.
#
#  Le logo est donc tracé en segments. Ce banc RE-RENDT le SVG avec le vrai
#  rsvg-convert, celui qu'emploiera la construction, et compte les pixels
#  orange : c'est la seule façon de savoir qu'il y a vraiment un dessin, et
#  pas un fichier valide et noir.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$RACINE/branding/wallpaper-nomad.svg"
GEN="$RACINE/tools/gen-fond-nomad.py"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
SET="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
FOND="$RACINE/config/includes.chroot/usr/bin/lexos-fond-ecran"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. L'image existe, et c'est un SVG que librsvg accepte"
# =============================================================================
if [[ -r "$SVG" ]]; then
	ok "branding/wallpaper-nomad.svg est livré"
else
	non "aucun fond « Nomad » : rien à choisir dans le sélecteur"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi
if python3 -c "import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1])" "$SVG" 2>/dev/null; then
	ok "il se parse comme du XML"
else
	non "le SVG ne se parse pas"
fi
#  LE PIÈGE VÉCU EN L'ÉCRIVANT : un commentaire XML ne peut pas contenir
#  « -- ». L'en-tête citait « var(‑‑ac) », le nom CSS de l'accent, et librsvg
#  a refusé le fichier ENTIER. Un parseur permissif ne l'aurait pas dit.
ENTETE="$(sed -n '/<!--/,/-->/p' "$SVG" | sed 's/<!--//' | sed 's/-->//')"
if grep -q -- '--' <<< "$ENTETE" ; then
	non "l'en-tête contient « -- » : librsvg refusera le fichier entier"
else
	ok "aucun double tiret dans le commentaire — librsvg ne le refusera pas"
fi

# =============================================================================
titre "2. LE VRAI RENDU : il y a un dessin, pas un rectangle noir"
# =============================================================================
if ! command -v rsvg-convert >/dev/null 2>&1 || ! python3 -c "import PIL" 2>/dev/null; then
	non "rsvg-convert ou Pillow absent : l'image n'a PAS été rendue ni mesurée"
else
	if rsvg-convert -w 1920 -h 1080 -o "$BANC/fond.png" "$SVG" 2>"$BANC/err.txt"; then
		ok "rsvg-convert le rend en 1920x1080 sans se plaindre"
	else
		non "rsvg-convert refuse le fichier : $(head -1 "$BANC/err.txt")"
	fi
	MESURE="$(python3 - "$BANC/fond.png" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
L, H = im.size
px = im.load()
#  ORANGE = le logo. On compte large (rouge dominant, bleu faible) pour ne pas
#  dépendre d'une nuance exacte, mais assez serré pour ne pas compter la
#  braise, qui est bien plus sombre.
orange = 0
for y in range(0, H, 2):
    for x in range(0, L, 2):
        r, g, b = px[x, y]
        if r > 150 and 40 < g < 160 and b < 90:
            orange += 1
#  Le coin en haut à droite doit rester du fond : si le logo débordait, ou si
#  le rendu était uni, ce contrôle le dirait.
coin = px[L - 40, 40]
print("ORANGE:%d" % orange)
print("COIN:%d,%d,%d" % coin)
print("TAILLE:%dx%d" % (L, H))
PY
)"
	lire() { printf '%s' "$MESURE" | sed -n "s/^$1://p"; }
	N_ORANGE="$(lire ORANGE)"
	#  Le logo occupe ~700x235 px de traits de 5 px : quelques milliers de
	#  pixels sur l'échantillon (un point sur quatre). Bien au-dessus du bruit,
	#  bien en dessous d'une image entièrement orange.
	if [[ "${N_ORANGE:-0}" -ge 1500 && "${N_ORANGE:-0}" -le 120000 ]]; then
		ok "le logo est bien dessiné ($N_ORANGE points orange relevés)"
	else
		non "$N_ORANGE points orange : image vide, ou envahie — le logo n'est pas là"
	fi
	if [[ "$(lire TAILLE)" == "1920x1080" ]]; then
		ok "et il sort à la taille demandée"
	else
		non "taille inattendue : $(lire TAILLE)"
	fi
	COIN="$(lire COIN)"
	if [[ "$COIN" =~ ^([0-9]+), ]] && [[ "${BASH_REMATCH[1]}" -lt 60 ]]; then
		ok "le coin en haut à droite reste sombre ($COIN) — le fond est un fond"
	else
		non "le coin vaut $COIN : ce n'est plus un fond noir"
	fi
fi

# =============================================================================
titre "3. Le générateur et le fichier ne dérivent pas"
# =============================================================================
#  Le SVG est FABRIQUÉ par un script. Deux sources de vérité, c'est un fichier
#  qu'on retouche à la main et un script qui l'écrase à la construction
#  suivante — sans que personne ne s'en aperçoive.
if [[ -r "$GEN" ]]; then
	ok "tools/gen-fond-nomad.py est là"
	python3 "$GEN" "$BANC/regen.svg" >/dev/null 2>&1
	if cmp -s "$BANC/regen.svg" "$SVG"; then
		ok "le régénérer redonne EXACTEMENT le fichier livré"
	else
		non "le fichier livré ne correspond plus à son script : l'un des deux ment"
	fi
else
	non "aucun générateur : le SVG ne serait plus reproductible"
fi

# =============================================================================
titre "4. La construction le rend, et là où le sélecteur regarde"
# =============================================================================
#  Un SVG dans branding/ n'est pas un fond d'écran : c'est une source. Sans
#  ces lignes-là, l'image n'atteindrait jamais /usr/share/backgrounds/lexos.
for T in "wallpaper-nomad.png" "wallpaper-nomad-4k.png" "wallpaper-nomad-hd.png"; do
	if grep -q "BG/$T\"" "$HOOK"; then
		ok "le crochet 0300 produit $T"
	else
		non "$T n'est jamais rendu"
	fi
done
#  ET LE SÉLECTEUR RATISSE BIEN CE DOSSIER. C'est ce qui rend l'image
#  choisissable sans qu'on ait à l'inscrire nulle part.
if grep -q '"/usr/share/backgrounds"' "$FOND"; then
	ok "lexos-fond-ecran ratisse /usr/share/backgrounds — l'image y apparaîtra seule"
else
	non "le sélecteur ne regarde pas ce dossier : l'image serait invisible"
fi

# =============================================================================
titre "5. Le bouton des Paramètres mène à une image qui existe"
# =============================================================================
#  Le défaut le plus répété de ce dépôt : un bouton ajouté à la page et pas
#  à la table du moteur — il appelle dans le vide, en silence.
if grep -q "setFond('nomad')" "$APP"; then
	ok "la page propose « Nomad »"
else
	non "aucun bouton : le fond serait livré et introuvable depuis Paramètres"
fi
if grep -q '"nomad":' "$SET"; then
	ok "…et le moteur connaît la clé « nomad »"
else
	non "le bouton appelle une clé que le moteur refuse : clic sans effet"
fi
#  Les deux doivent désigner LE MÊME fichier que le crochet produit.
CHEMIN="$(sed -n 's/^ *"nomad": *"\([^"]*\)".*/\1/p' "$SET")"
if [[ "$CHEMIN" == "/usr/share/backgrounds/lexos/wallpaper-nomad.png" ]]; then
	ok "et le chemin est celui que le crochet écrit ($CHEMIN)"
else
	non "le moteur pointe sur « $CHEMIN », que rien ne produit"
fi

#  ═══ ET LES TROIS AUTRES N'ONT PAS ÉTÉ CASSÉS AU PASSAGE ═══
#  PAS « defaut » : cette clé a été retirée (realpath() la rendait
#  indiscernable de « demon », wallpaper.png étant un lien symbolique vers
#  wallpaper-demon.png depuis le crochet 0300 — « demon » ne pouvait alors
#  JAMAIS s'allumer dans la galerie des Paramètres).
for CLE in secu demon keyart; do
	grep -q "\"$CLE\":" "$SET" && grep -q "setFond('$CLE')" "$APP" \
		&& ok "« $CLE » est toujours là, des deux côtés" \
		|| non "« $CLE » a disparu d'un des deux côtés"
done

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
