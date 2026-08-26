#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'horloge du panneau — le badge « <[lexOS⚡pro]> », lisible partout
# =============================================================================
#  ALEX a envoyé une image : un porte-clés bleu de chaque côté, un fond noir,
#  « <[lexOS⚡pro]> » — et a demandé la même chose en haut de l'écran.
#
#  « lexOS » était déjà en tête de l'horloge du panneau (texte brut, aucune
#  couleur). genmon affiche <txt> avec gtk_label_set_markup() — vérifié dans
#  le vrai binaire de xfce4-genmon-plugin, pas supposé — donc du Pango en
#  balises <span> s'y rend pour de vrai.
#
#  DEUX PIÈGES QUE CE BANC FERME :
#    1. Le PANNEAU seul doit voir les balises. Le même code sert aussi le
#       terminal (« lexos-heure », sans argument) — y laisser fuir des
#       balises <span> donnerait un fouillis illisible à qui tape la
#       commande, au lieu d'une heure toute simple.
#    2. « date » avale la sortie de badge_panneau() comme un format
#       strftime : un « %» égaré dans un futur ajustement de couleur s'y
#       ferait lire comme une directive de date et casserait l'affichage
#       en silence — le comportement précis que ce banc surveille.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-heure"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-heure introuvable ou non exécutable"; exit 1; }

# =============================================================================
titre "1. Le panneau porte bien le badge, en Pango bien formé"
# =============================================================================
SORTIE="$(HOME="$BANC" "$OUTIL" --panneau)"
MARKUP="$(printf '%s' "$SORTIE" | sed -n 's/.*<txt> \(.*\) <\/txt>.*/\1/p')"

echo "$MARKUP" | grep -qF '🔵' \
	&& ok "les deux porte-clés bleus (🔵) sont là" \
	|| non "aucun porte-clés bleu dans la sortie du panneau"
echo "$MARKUP" | grep -qF 'lexOS' \
	&& ok "« lexOS » est présent" \
	|| non "« lexOS » a disparu de la sortie"
echo "$MARKUP" | grep -qF '⚡' \
	&& ok "l'éclair (⚡) sépare bien lexOS et pro, comme sur l'image d'Alex" \
	|| non "l'éclair a disparu"
echo "$MARKUP" | grep -qF '>pro<' \
	&& ok "« pro » est présent" \
	|| non "« pro » a disparu"
echo "$MARKUP" | grep -qF '&lt;[' && echo "$MARKUP" | grep -qF ']&gt;' \
	&& ok "les crochets « <[ » et « ]> » sont bien ÉCHAPPÉS (&lt; / &gt;), pas des balises brutes" \
	|| non "les crochets ne sont pas correctement échappés — Pango les lirait comme des balises"

#  Un test Pango réel (gi cassé sur ce banc) remplacerait ceci ; à défaut,
#  on vérifie que les balises <span> sont un XML bien formé — Pango est un
#  sous-ensemble strict de XML, donc un déséquilibre ici serait AUSSI un
#  déséquilibre pour Pango.
BIEN_FORME="$(python3 -c "
import sys, xml.etree.ElementTree as ET
markup = sys.stdin.read()
try:
    ET.fromstring('<r>' + markup + '</r>')
    print('OUI')
except Exception as e:
    print('NON', e)
" <<< "$MARKUP")"
case "$BIEN_FORME" in
	OUI*) ok "le Pango est bien formé (balises équilibrées, entités correctes)" ;;
	*) non "Pango mal formé : $BIEN_FORME" ;;
esac

# =============================================================================
titre "2. Le terminal, lui, ne voit AUCUNE balise — juste une heure lisible"
# =============================================================================
SORTIE_CLI="$(HOME="$BANC" "$OUTIL")"
case "$SORTIE_CLI" in
	*"<span"*|*"</span>"*)
		non "des balises Pango ont fui dans la sortie console : « $SORTIE_CLI »" ;;
	*"lexOS"*)
		ok "la console affiche « lexOS » en clair, sans aucune balise : « $SORTIE_CLI »" ;;
	*) non "« lexOS » a disparu de la sortie console : « $SORTIE_CLI »" ;;
esac

# =============================================================================
titre "3. Les couleurs sont celles de LexOS, pas inventées pour l'occasion"
# =============================================================================
#  #3584E4 = l'accent bleu « haut » et #E8590C = l'orange par défaut, tous
#  deux déjà vérifiés dans ACCENTS (fond-anime.py). Un badge qui piocherait
#  des teintes au hasard sur la photo d'Alex divergerait du reste de LexOS
#  à la première mise à jour du thème.
FOND_ANIME="$RACINE/config/includes.chroot/usr/lib/lexos/fond-anime.py"
grep -q '"bleu":.*"#3584E4"' "$FOND_ANIME" \
	&& echo "$MARKUP" | grep -qF '#3584E4' \
	&& ok "le bleu du badge (#3584E4) est bien l'accent « bleu haut » déjà utilisé ailleurs" \
	|| non "le bleu du badge ne correspond pas à un accent déjà vérifié dans fond-anime.py"
grep -q '"orange":.*"#E8590C"' "$FOND_ANIME" \
	&& echo "$MARKUP" | grep -qF '#E8590C' \
	&& ok "l'éclair (#E8590C) est bien l'orange par défaut de LexOS" \
	|| non "l'orange de l'éclair ne correspond pas à l'accent par défaut"

# =============================================================================
titre "4. « date » avale le badge sans jamais le confondre avec une directive"
# =============================================================================
#  Si un « % » se glissait un jour dans une couleur ou un libellé, « date »
#  le lirait comme « %<lettre> » et le badge disparaîtrait en silence. On le
#  vérifie en cherchant un « % » NU dans la sortie du panneau — en dehors
#  des directives légitimes déjà consommées par « date » (donc absentes du
#  résultat final).
echo "$SORTIE" | grep -qF '%' \
	&& non "un « % » brut traîne dans la sortie du panneau — « date » l'aurait interprété" \
	|| ok "aucun « % » ne traîne dans la sortie finale — rien que « date » ait pu mal lire"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
