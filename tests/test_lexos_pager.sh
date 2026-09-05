#!/usr/bin/env bash
# =============================================================================
#  Le sélecteur d'espaces de travail — la rangée de points en haut à gauche
# =============================================================================
#  ALEX, deux captures : la pilule de l'espace courant passe au BLANC, les
#  points au repos deviennent plus fins et un peu plus lisibles, et la rangée
#  n'est plus collée au bord de l'écran.
#
#  ═══ CE QU'ON NE TOUCHE PAS, ET POURQUOI CE BANC LE GARDE ═══
#  Le sélecteur de XFCE n'a pas de mode « points » : il affiche le NOM de
#  chaque espace. LexOS donne donc à chaque espace un nom qui EST un glyphe
#  « ● » (xfwm4.xml) et le met en forme ici. Alex l'a confirmé : « c'est
#  correct pour la fonctionnalité ». Ce banc protège ce montage plutôt que de
#  le vérifier à moitié.
#
#  ═══ L'ASSERTION QUI COMPTE VRAIMENT ═══
#  marge + hauteur + marge doit valoir EXACTEMENT la hauteur de la rangée
#  déclarée dans xfce4-panel.xml — sinon les points se recollent en haut de
#  la barre. CE PIÈGE S'EST REFERMÉ DEUX FOIS : la barre est passée de 32 à
#  44, puis de 44 à 52, et à chaque fois c'est un COMMENTAIRE qui a rattrapé
#  le coup. Un commentaire ne rattrape que ce qu'on lit. Ce banc extrait les
#  deux nombres des DEUX fichiers et refuse toute combinaison qui ne tombe
#  pas juste — quelle que soit la hauteur, aujourd'hui et après.
#
#  Il n'existait aucun banc pour ce sélecteur : rien ne mentionnait « pager »
#  dans tests/.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css"
PANEL_XML="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$CSS" "$PANEL_XML"; do
	if [ ! -r "$F" ]; then
		non "fichier introuvable : $F"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
		exit 1
	fi
done

#  ═══ ON DÉCOUPE LES BLOCS, ON NE GREP PAS LE FICHIER ENTIER ═══
#  « min-width: 26px » existe peut-être ailleurs dans une feuille de 900
#  lignes. Un grep global dirait « c'est là » sans dire OÙ, et un banc qui
#  trouve la bonne valeur dans la mauvaise règle est un faux vert.
#  On isole donc chaque règle par son sélecteur exact, et on lit dedans.
bloc() { # bloc <ligne de sélecteur exacte> -> le corps de la règle
	awk -v cible="$1" '
		$0 == cible { dans = 1; next }
		dans && /^}/ { exit }
		dans { print }
	' "$CSS"
}
valeur() { # valeur <corps> <propriété> -> la valeur, sans « ; »
	printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*\([^;]*\);.*/\1/p" | head -1
}

REPOS="$(bloc '#XfcePanelWindow #pager button {')"
ACTIF="$(bloc '#XfcePanelWindow #pager button:active {')"
RANGEE="$(bloc '#XfcePanelWindow #pager {')"

# =============================================================================
titre "1. La pilule de l'espace courant"
# =============================================================================
if [ -z "$ACTIF" ]; then
	non "règle de l'espace courant introuvable — rien n'a pu être vérifié"
else
	FOND="$(valeur "$ACTIF" background-color)"
	LARG="$(valeur "$ACTIF" min-width)"
	COUL="$(valeur "$ACTIF" color)"

	[ "$FOND" = "#EDEDED" ] \
		&& ok "la pilule est blanche (#EDEDED)" \
		|| non "la pilule vaut « $FOND » au lieu de #EDEDED"

	[ "$LARG" = "26px" ] \
		&& ok "la pilule fait 26 px de large" \
		|| non "la pilule fait « $LARG » au lieu de 26px"

	#  ═══ LE REPLI QUI GARANTIT QU'ON VOIT TOUJOURS QUELQUE CHOSE ═══
	#  Le glyphe n'est PAS caché (« font-size: 0 », « color: transparent ») :
	#  il prend la couleur du fond. Si une version de GTK n'appliquait pas le
	#  fond, un point invisible laisserait un sélecteur d'espaces qu'on ne
	#  voit plus du tout ; avec la couleur du fond, le pire des cas redonne
	#  un point. Les deux valeurs doivent donc rester IDENTIQUES.
	if [ -n "$COUL" ] && [ "$COUL" = "$FOND" ]; then
		ok "le glyphe prend la couleur du fond — le pire cas redonne un point"
	else
		non "glyphe « $COUL » et fond « $FOND » diffèrent : un GTK sans fond donnerait un sélecteur invisible"
	fi
fi

# =============================================================================
titre "2. Les points au repos"
# =============================================================================
if [ -z "$REPOS" ]; then
	non "règle des points au repos introuvable"
else
	MINW="$(valeur "$REPOS" min-width)"
	MINH="$(valeur "$REPOS" min-height)"
	FONTE="$(valeur "$REPOS" font-size)"
	OPAC="$(valeur "$REPOS" color)"
	MARGE="$(valeur "$REPOS" margin)"

	[ "$MINW" = "6px" ] \
		&& ok "les points font 6 px" \
		|| non "les points font « $MINW » au lieu de 6px"

	case "$OPAC" in
		*0.40*) ok "les points au repos sont à 40 % d'opacité" ;;
		*)      non "l'opacité des points au repos vaut « $OPAC », on attendait 0.40" ;;
	esac

	#  ═══ LA POLICE EST LA TAILLE DU POINT ═══
	#  Le glyphe vient du NOM de l'espace : c'est font-size qui décide de sa
	#  taille. Si elle dépasse la hauteur du bouton, le glyphe REGONFLE le
	#  bouton et la rangée redevient une rangée de boutons — exactement ce
	#  qu'on a passé trois ISO à enlever.
	FN="${FONTE%px}"; MH="${MINH%px}"
	if [ -n "$FN" ] && [ -n "$MH" ] && [ "$FN" -le "$MH" ] 2>/dev/null; then
		ok "font-size ($FONTE) ≤ min-height ($MINH) — le glyphe ne regonfle pas le bouton"
	else
		non "font-size « $FONTE » dépasse min-height « $MINH » : la rangée redeviendrait des boutons"
	fi

	#  La pilule GRANDIT, elle n'apparaît pas : c'est la transition sur la
	#  largeur qui fait lire le déplacement d'un espace à l'autre.
	if grep -q 'transition:.*min-width' <<< "$REPOS" ; then
		ok "la transition sur min-width est là — la pilule glisse au lieu de sauter"
	else
		non "plus de transition sur min-width : le changement d'espace serait net"
	fi
fi

# =============================================================================
titre "3. LA SOMME TOMBE JUSTE — marge + hauteur + marge = hauteur de la barre"
# =============================================================================
#  L'assertion qui remplace un commentaire par une garantie. On extrait les
#  DEUX nombres des DEUX fichiers : la marge verticale dans la feuille de
#  style, la hauteur de la rangée dans le XML du panneau. Aucune des deux
#  n'est écrite en dur ici — ce banc reste juste si Alex change la barre.
TAILLE="$(sed -n 's/.*name="size"[^>]*value="\([0-9]\+\)".*/\1/p' "$PANEL_XML" | head -1)"
MARGE_V="$(printf '%s' "${MARGE:-}" | awk '{print $1}')"
MARGE_V="${MARGE_V%px}"
MH="${MINH%px}"

if [ -z "$TAILLE" ]; then
	non "hauteur de la barre illisible dans xfce4-panel.xml — la somme n'a pas pu être vérifiée"
elif [ -z "$MARGE_V" ] || [ -z "$MH" ]; then
	non "marge ou hauteur illisibles dans la feuille de style (marge=$MARGE_V hauteur=$MH)"
else
	SOMME=$(( MARGE_V + MH + MARGE_V ))
	if [ "$SOMME" = "$TAILLE" ]; then
		ok "$MARGE_V + $MH + $MARGE_V = $SOMME, et la barre fait $TAILLE — les points sont centrés"
	else
		non "$MARGE_V + $MH + $MARGE_V = $SOMME alors que la barre fait $TAILLE : les points se recolleraient en haut"
	fi

	#  Et la formule elle-même, écrite dans le commentaire, doit rester
	#  vraie : marge = (hauteur − pastille) / 2. On la recalcule.
	ATTENDUE=$(( (TAILLE - MH) / 2 ))
	if [ "$MARGE_V" = "$ATTENDUE" ]; then
		ok "la marge suit bien la formule ( $TAILLE − $MH ) / 2 = $ATTENDUE"
	else
		non "la formule donne $ATTENDUE, la feuille dit $MARGE_V"
	fi
fi

# =============================================================================
titre "4. La rangée n'est pas collée au bord"
# =============================================================================
#  ALEX : « petit espace pour que ce soit pas collé à l'écran ».
#  L'écart est posé sur la RANGÉE, pas sur les boutons : l'élargir sur chaque
#  bouton aurait aussi élargi l'écart ENTRE les points, et les 7 px mesurés
#  sur les captures seraient tombés.
if [ -z "$RANGEE" ]; then
	non "aucune règle sur la rangée : le premier point toucherait le bord"
else
	ML="$(valeur "$RANGEE" margin-left)"
	MLN="${ML%px}"
	if [ -n "$MLN" ] && [ "$MLN" -gt 0 ] 2>/dev/null; then
		ok "la rangée est décalée du bord de $ML"
	else
		non "la marge gauche de la rangée vaut « $ML » — les points seraient collés au bord"
	fi
fi

#  ET L'ÉCART ENTRE LES POINTS N'A PAS BOUGÉ. C'est la moitié de la marge
#  horizontale de chaque bouton, de part et d'autre : 3.5 + 3.5 = 7 px.
MARGE_H="$(printf '%s' "${MARGE:-}" | awk '{print $2}')"
if [ "$MARGE_H" = "3.5px" ]; then
	ok "l'écart entre deux points reste de 7 px (3.5 de chaque côté)"
else
	non "la marge horizontale vaut « $MARGE_H » au lieu de 3.5px — l'écart mesuré sur les captures serait perdu"
fi

# =============================================================================
titre "5. La pilule NE SUIT PLUS l'accent — et c'est voulu"
# =============================================================================
#  Elle était peinte avec le jeton d'accent, que lexos-theme-gen remplace par
#  sed DANS CE FICHIER MÊME quand Alex change d'accent. Alex a demandé le
#  blanc : #EDEDED n'est pas un jeton, la pilule ne bouge plus.
#
#  CE N'EST PAS UN OUBLI, C'EST LA DEMANDE — et c'est précisément pour ça
#  qu'il faut un contrôle : sans lui, quelqu'un « réparerait » ça dans six
#  mois en croyant à une substitution manquée.
if [ ! -r "$GEN" ]; then
	saut "lexos-theme-gen illisible : la substitution n'a PAS été mesurée"
else
	rm -rf "$BANC/accent"; mkdir -p "$BANC/accent"
	LEXOS_PANNEAU_CSS="$CSS" bash "$GEN" --target "$BANC/accent" bleu >/dev/null 2>&1 || true
	PRODUIT="$(find "$BANC/accent" -name 'gtk.css' | head -1)"
	if [ -z "$PRODUIT" ]; then
		saut "le générateur n'a produit aucune feuille : la substitution n'a PAS été mesurée"
	else
		#  Le blanc de la pilule doit avoir traversé le sed intact.
		if grep -q 'background-color: #EDEDED' "$PRODUIT"; then
			ok "après « lexos accent bleu », la pilule est toujours blanche"
		else
			non "le blanc de la pilule n'a pas survécu au changement d'accent"
		fi
		#  ET LE RESTE DE LA BARRE SUIT BIEN L'ACCENT, LUI. Si plus rien ne
		#  changeait, c'est que la substitution serait cassée pour de bon —
		#  et ce contrôle-ci deviendrait vert pour la mauvaise raison.
		#  ═══ LE CONTRE-CONTRÔLE, ET LES DEUX FOIS OÙ IL S'EST TROMPÉ ═══
		#  Sans lui, « la pilule est restée blanche » serait vert même si la
		#  substitution d'accent ne marchait plus du tout : tout serait resté
		#  blanc, y compris ce qui devrait changer. Il faut donc prouver que le
		#  sed a bien tourné SUR CE FICHIER.
		#
		#  PREMIÈRE VERSION : cherchait « #1C7ED6 », un bleu écrit de mémoire.
		#  Faux — la palette dit #1A5FB4. Le banc accusait le code d'une faute
		#  qu'il n'avait pas.
		#
		#  DEUXIÈME VERSION : cherchait la présence de l'accent bleu dans la
		#  feuille produite. Vert, mais NON DISCRIMINANT, et c'est une mutation
		#  qui l'a montré : en remplaçant le sed du générateur par un simple
		#  « cat », le contrôle restait vert. La raison, mesurée : le bleu
		#  arrive dans la feuille par les @define-color que le générateur écrit
		#  lui-même à partir de $ACCENT — pas par la substitution du squelette.
		#  On mesurait la couleur au mauvais endroit.
		#
		#  TROISIÈME VERSION, CELLE-CI. On regarde DANS le bloc du squelette
		#  (le générateur le borne par deux commentaires) et on y cherche le
		#  JETON, pas l'accent : « 232, 89, 12 », le triplet de l'orange. S'il
		#  survit à un accent bleu, c'est que le sed n'a pas tourné.
		#
		#  ET C'EST LE TRIPLET, PAS #E8590C : depuis que la pilule est blanche,
		#  le squelette ne contient PLUS AUCUN « #E8590C » — la pilule était le
		#  dernier. Un contrôle basé sur ce jeton-là serait vert pour toujours,
		#  faute de matière. Le triplet, lui, est encore là deux fois (les fonds
		#  d'accent en rgba).
		SQUELETTE="$(awk '/Style du panneau, repris du squelette/{d=1} d{print} /Fin du bloc squelette/{exit}' "$PRODUIT")"
		if [ "$(printf '%s' "$SQUELETTE" | grep -c .)" -lt 10 ]; then
			non "bloc du squelette introuvable dans la feuille produite — le contre-contrôle ne prouve rien"
		elif grep -q '232, 89, 12' <<< "$SQUELETTE" ; then
			non "le triplet orange a survécu à un accent bleu : la substitution ne tourne plus, le contrôle ci-dessus ne prouve rien"
		elif grep -q '26, 95, 180' <<< "$SQUELETTE" ; then
			ok "le squelette a bien été substitué (triplet passé à l'accent bleu) — le contrôle du blanc a un sens"
		else
			non "ni l'orange ni le bleu dans le bloc du squelette : on ne mesure plus rien"
		fi
	fi
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLa pilule est blanche, les points sont fins, la rangée respire.\033[0m\n'
