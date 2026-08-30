#!/usr/bin/env bash
# =============================================================================
#  Paramètres rapides : le gris autour des boutons, et la tuile jour/nuit en moins
# =============================================================================
#  ALEX, DEUX PHOTOS DU VOLET :
#    · « les paramètres rapides : supprimer pour le thème de jour et de nuit,
#       et garder le thème de nuit officiel » ;
#    · « autour des boutons c'est déjà joli, mais on pourrait mettre du gris
#       où les espaces vides » — précisé ensuite sans ambiguïté : « les
#       boutons sont bien parfaits, juste ajouter du gris autour ».
#
#  ═══ CE QUE « JUSTE AUTOUR » VEUT DIRE, ET POURQUOI ÇA SE MESURE ═══
#  La demande porte une contrainte autant qu'une envie : les tuiles ne doivent
#  PAS changer. Un banc qui vérifierait seulement « il y a du gris quelque
#  part » resterait vert si, pour faire ressortir la plaque, quelqu'un
#  éclaircissait les tuiles au passage — ce qu'Alex a explicitement écarté.
#  On mesure donc les DEUX : le vide devient gris, la tuile reste identique.
#
#  ═══ ON REGARDE LES PIXELS, PAS LE CSS ═══
#  Une couleur composée de trois calques translucides (le voile du volet, la
#  plaque, la tuile) ne se lit pas dans la feuille de style : rgba(255,255,255,
#  .08) ne dit pas s'il en sort un gris visible ou une nuance invisible. Le
#  banc extrait donc le VRAI balisage de app.js, le rend dans un vrai moteur,
#  et relève les valeurs à l'écran.
#
#  Puis il retire la plaque et recommence : si les gouttières ne changent pas
#  de couleur, c'est que la mesure ne prouvait rien.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOL_JS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/app.js"
VOL_CSS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/style.css"
UI_CSS="$RACINE/config/includes.chroot/usr/share/lexos/ui.css"
SET_PY="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
DEMO="$RACINE/web-demo/index.html"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

#  On dépouille les commentaires AVANT de chercher : ce dépôt s'est déjà fait
#  prendre deux fois par un banc qui trouvait ce qu'il cherchait dans la prose
#  écrite juste au-dessus du code, et restait vert après la suppression du
#  code lui-même.
sans_commentaires() { # sans_commentaires <fichier>
	python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r'/\*[\s\S]*?\*/', '', t)
t = re.sub(r'^\s*//.*$', '', t, flags=re.M)
print(t)
PY
}

# =============================================================================
titre "1. La tuile jour/nuit a quitté les Paramètres rapides"
# =============================================================================
VOL_NU="$(sans_commentaires "$VOL_JS")"
#  PAS DE DÉPOUILLAGE SUR LA DÉMO. C'est un fichier HTML de trente mille
#  lignes où du CSS, du JavaScript et des chaînes se croisent : un « /* »
#  vivant dans une chaîne et un « */ » cent lignes plus bas font avaler au
#  dépouilleur des sections entières de code — c'est arrivé en écrivant ce
#  banc, qui a déclaré disparues deux choses parfaitement présentes.
#  On y cherche donc des fragments de CODE que la prose ne peut pas contenir.

if printf '%s' "$VOL_NU" | grep -q 'qsTileHTML("theme"'; then
	non "le volet de l'ISO propose encore la bascule jour/nuit"
else
	ok "volet de l'ISO : plus de tuile « Style sombre / Style clair »"
fi
if grep -q 'qsTileHTML("theme"' "$DEMO"; then
	non "la démo propose encore la bascule — les deux raconteraient deux choses"
else
	ok "démo : la même tuile est partie (parité)"
fi

#  ═══ ET LA POSSIBILITÉ RESTE ═══ Retirer un raccourci n'est pas retirer un
#  réglage. Si ces deux chemins-là disparaissaient, le thème de jour
#  deviendrait inatteignable — ce n'est pas ce qui a été demandé.
if grep -q '"theme": act_theme' "$SET_PY"; then
	ok "Paramètres garde l'action « theme » — le thème de jour reste atteignable"
else
	non "plus aucune action « theme » dans Paramètres : le thème de jour serait perdu"
fi
if grep -q "onclick=\"setMode('clair')\"" "$DEMO"; then
	ok "la démo garde sa bascule dans Apparence"
else
	non "la démo n'a plus aucun moyen de passer en clair"
fi

# =============================================================================
titre "2. La plaque existe — dans le balisage ET dans la feuille de style"
# =============================================================================
if printf '%s' "$VOL_NU" | grep -q 'class="qs-plaque"'; then
	ok "le volet enveloppe bien sa grille dans la plaque"
else
	non "aucune plaque dans le balisage : la règle CSS ne s'appliquerait à rien"
fi
if grep -q '^\.qs-plaque{' "$VOL_CSS"; then
	ok "la règle .qs-plaque existe"
else
	non "aucune règle .qs-plaque : l'élément serait invisible"
fi
if grep -q -- '--qs-plaque:' "$UI_CSS"; then
	N_MODES="$(grep -c -- '--qs-plaque:' "$UI_CSS")"
	if [[ "$N_MODES" -ge 2 ]]; then
		ok "le jeton est défini pour les DEUX modes ($N_MODES fois) — le clair aussi"
	else
		non "le jeton n'est défini qu'une fois : en mode clair la plaque serait blanche sur crème"
	fi
else
	non "aucun jeton --qs-plaque dans ui.css"
fi
if grep -q 'class="qs-plaque"><div class="qs-grid' "$DEMO"; then
	ok "la démo porte la même plaque"
else
	non "la démo n'a pas la plaque — les deux dessins divergeraient"
fi

# =============================================================================
titre "3. LES TUILES N'ONT PAS BOUGÉ — la contrainte d'Alex"
# =============================================================================
#  « Les boutons sont bien parfaits. » Leur surface et leur bord doivent
#  rester les jetons communs, pas devenir des couleurs propres à ce panneau.
LIGNE_TUILE="$(grep -A2 '^\.qs-tile{' "$VOL_CSS" | tr '\n' ' ')"
if printf '%s' "$LIGNE_TUILE" | grep -q 'background:var(--bg-hi)' \
	&& printf '%s' "$LIGNE_TUILE" | grep -q 'border:1px solid var(--bd)'; then
	ok "la tuile garde --bg-hi et --bd : rien n'a été repeint pour l'occasion"
else
	non "la surface ou le bord des tuiles a changé — Alex les voulait intactes"
fi

# =============================================================================
titre "4. LA MESURE : le vide devient gris, la tuile reste la même"
# =============================================================================
NAVIGATEUR=""
for C in /opt/pw-browsers/chromium chromium chromium-browser google-chrome google-chrome-stable; do
	if command -v "$C" >/dev/null 2>&1; then NAVIGATEUR="$C"; break; fi
done

rendre() { # rendre <dossier> ; produit rendu.png
	"$NAVIGATEUR" --headless --disable-gpu --no-sandbox --hide-scrollbars \
		--window-size=440,700 --screenshot="$1/rendu.png" "file://$1/essai.html" \
		>/dev/null 2>&1
	[[ -s "$1/rendu.png" ]]
}

monter() { # monter <dossier> <avec-plaque 0/1>
	local d="$1" avec="$2"
	mkdir -p "$d"
	cp "$UI_CSS" "$VOL_CSS" "$d/"
	python3 - "$VOL_JS" "$d" "$avec" <<'PY'
import re, sys, os
js = open(sys.argv[1], encoding="utf-8").read()
d, avec = sys.argv[2], sys.argv[3] == "1"
def bloc(nom):
    m = re.search(r'^function %s\([^)]*\)\{' % nom, js, re.M)
    if not m: raise SystemExit("bloc %s introuvable" % nom)
    prof = 0
    for k in range(m.end() - 1, len(js)):
        if js[k] == '{': prof += 1
        elif js[k] == '}':
            prof -= 1
            if prof == 0: return js[m.start():k + 1]
    raise SystemExit("bloc %s non refermé" % nom)
src = bloc("qsTileHTML") + "\n" + bloc("rapidesHTML")
open(os.path.join(d, "extrait.js"), "w", encoding="utf-8").write(src)
#  LA MUTATION : on neutralise la plaque en la rendant transparente, sans
#  toucher au balisage — la grille garde sa place, seul le gris s'en va.
mut = "" if avec else "<style>.qs-plaque{background:transparent;border-color:transparent}</style>"
open(os.path.join(d, "essai.html"), "w", encoding="utf-8").write(
"""<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<link rel="stylesheet" href="ui.css"><link rel="stylesheet" href="style.css">
<style>html,body{margin:0;height:100%%;background:#000}</style>%s</head><body>
<div class="shade on" style="position:absolute;inset:0"><div class="shade-in" id="dedans"></div></div>
<script>
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];});}
var etat={rapides:{wifi:true,bt:true,avion:false,perf:"performant",perfLabel:"Performant",crt:true}};
</script>
<script src="extrait.js"></script>
<script>document.getElementById("dedans").innerHTML=rapidesHTML();</script>
</body></html>""" % mut)
PY
}

pixel() { # pixel <png> <x> <y>  -> "r,v,b"
	python3 - "$1" "$2" "$3" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
print("%d,%d,%d" % im.getpixel((int(sys.argv[2]), int(sys.argv[3]))))
PY
}

if [[ -z "$NAVIGATEUR" ]]; then
	non "aucun navigateur sans écran : les couleurs n'ont PAS été mesurées (installer chromium)"
elif ! python3 -c "import PIL" 2>/dev/null; then
	non "Pillow absent : les couleurs n'ont PAS été mesurées (installer python3-pil)"
else
	monter "$BANC/avec" 1
	if rendre "$BANC/avec"; then
		ok "le panneau se rend (navigateur : $(basename "$NAVIGATEUR"))"

		#  Trois points, choisis pour ce qu'ils prouvent chacun :
		#    · (400,12)  la bande du titre — HORS de la plaque : le voile ;
		#    · (220,480) le grand vide sous la dernière rangée ;
		#    · (253,260) la gouttière ENTRE deux tuiles ;
		#    · (150,190) le corps d'une tuile éteinte.
		VOILE="$(pixel "$BANC/avec/rendu.png" 400 12)"
		VIDE="$(pixel  "$BANC/avec/rendu.png" 220 480)"
		GOUT="$(pixel  "$BANC/avec/rendu.png" 253 260)"
		TUILE="$(pixel "$BANC/avec/rendu.png" 150 190)"

		#  « Plus clair que le voile, d'au moins 10 niveaux » : en deçà, l'œil
		#  ne distingue rien sur un écran de portable et la demande n'est pas
		#  honorée. On compare le canal rouge, les trois bougent ensemble.
		R_VOILE="${VOILE%%,*}"; R_VIDE="${VIDE%%,*}"; R_GOUT="${GOUT%%,*}"
		if (( R_VIDE >= R_VOILE + 10 )); then
			ok "le vide sous les tuiles est gris ($VIDE) contre le voile ($VOILE)"
		else
			non "le vide ($VIDE) ne se détache pas du voile ($VOILE) : gris invisible"
		fi
		if (( R_GOUT >= R_VOILE + 10 )); then
			ok "les gouttières entre les tuiles sont grises aussi ($GOUT)"
		else
			non "les gouttières ($GOUT) sont restées noires"
		fi
		#  ET LA TUILE N'A PAS BOUGÉ : --bg-hi vaut #141416 en sombre.
		if [[ "$TUILE" == "20,20,22" ]]; then
			ok "la tuile éteinte vaut toujours $TUILE (#141416) — intacte, comme demandé"
		else
			non "la tuile éteinte vaut $TUILE au lieu de 20,20,22 : les boutons ont changé"
		fi

		#  ═══ LA MUTATION ═══
		monter "$BANC/sans" 0
		if rendre "$BANC/sans"; then
			G2="$(pixel "$BANC/sans/rendu.png" 253 260)"
			if [[ "$G2" != "$GOUT" ]]; then
				ok "sans la plaque la gouttière retombe à $G2 — la mesure voit la différence"
			else
				non "même couleur ($G2) avec et sans la plaque : ce banc ne prouverait rien"
			fi
		else
			non "le rendu de contrôle a échoué : la mutation n'a pas pu être faite"
		fi
	else
		non "le panneau ne se rend pas — page cassée, ou navigateur inutilisable"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
