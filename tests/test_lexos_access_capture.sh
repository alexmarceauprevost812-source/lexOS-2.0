#!/usr/bin/env bash
# =============================================================================
#  Éprouver deux gestes du quotidien : le gros texte, et la bulle de capture
# =============================================================================
#  DEUX DEMANDES D'ALEX, LE MÊME SOIR.
#
#  1. « quand on fait agrandissement 100 % de l'écriture, faudrait que celle
#     du bureau grossisse aussi ».
#     Le gros texte réglait le facteur GSettings (les logiciels GNOME) et
#     /Gtk/FontName (les logiciels GTK). Ni l'un ni l'autre n'atteint le
#     BUREAU : les noms sous les icônes sont dessinés par xfdesktop, qui a sa
#     propre taille dans son propre canal. Tout grossissait sauf l'endroit
#     qu'on regarde en premier.
#
#     LE VERROU QUI REND LE RÉGLAGE INERTE. « /desktop-icons/font-size » ne
#     sert à RIEN tant que « /desktop-icons/use-custom-font-size » est faux :
#     xfdesktop suit alors la police du système et ignore la taille. Écrire
#     l'une sans l'autre, c'est le réglage qui a l'air posé et ne change
#     rien — exactement « item-icon-size » du menu au build 74. Le banc
#     vérifie donc que LES DEUX partent, et que « off » les défait.
#
#  2. « quand on prend une capture d'écran […] peux-tu le changer pour qu'on
#     puisse aller la voir directement dans le dossier images ? »
#     La bulle ne proposait qu'un bouton : « En faire mon fond d'écran ».
#
#  CE QUE CE BANC NE PEUT PAS FAIRE : afficher un bureau ni une bulle. Il n'y
#  a pas de serveur X ici. Il donne donc à chaque script un PATH FERMÉ et de
#  faux outils qui NOTENT ce qu'on leur demande au lieu de le faire — la même
#  discipline que les autres bancs de ce dépôt.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCESS="$RACINE/config/includes.chroot/usr/bin/lexos-access"
CAPTURE="$RACINE/config/includes.chroot/usr/bin/lexos-capture"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for f in "$ACCESS" "$CAPTURE"; do
	[ -r "$f" ] || { non "$(basename "$f") introuvable"; echo; exit 1; }
done

# =============================================================================
titre "1. Le gros texte emporte le texte du BUREAU avec lui"
# =============================================================================
#  Faux xfconf-query : il NOTE chaque écriture et répond aux lectures comme
#  une session XFCE ordinaire (police « Noto Sans 10 », aucune taille sur
#  mesure pour le bureau — le cas de départ d'une machine neuve).
mkdir -p "$BANC/bin"
cat > "$BANC/bin/xfconf-query" <<EOF
#!/bin/sh
echo "xfconf \$*" >> "$BANC/journal"
#  Une LECTURE : pas de « -s » dans la ligne de commande.
case "\$*" in
  *-s*) exit 0 ;;
esac
case "\$*" in
  *"/Gtk/FontName"*)                    echo "Noto Sans 10" ;;
  *"/desktop-icons/font-size"*)         exit 1 ;;   # aucune taille sur mesure
  *"/desktop-icons/use-custom-font-size"*) echo "false" ;;
esac
exit 0
EOF
#  gsettings et xrandr : présents, muets. Sans xrandr, facteur_ecran retombe
#  sur son défaut, ce qui suffit — on éprouve la propagation, pas le calcul
#  du facteur (déjà couvert par le pourcentage explicite ci-dessous).
for o in gsettings xrandr notify-send; do
	printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$o" "$BANC/journal" > "$BANC/bin/$o"
done
chmod +x "$BANC"/bin/*

#  LA LISTE DOIT ÊTRE COMPLÈTE, ET C'EST LE BANC QUI S'EN EST ACCUSÉ.
#  Première version, « mkdir » oublié : etat_ecrire ne pouvait plus créer
#  ~/.config/lexos, le fichier d'état restait vide, et « off » n'avait donc
#  RIEN à défaire. Le banc annonçait « off laisse le bureau sur une taille
#  sur mesure » — un échec du harnais présenté comme un échec du script.
#  Un PATH fermé n'est utile que s'il contient tout ce dont le script a
#  besoin ; sinon il ne prouve pas une absence, il en fabrique une.
#  « tail » compte autant que les autres : etat_lire s'en sert pour prendre
#  la DERNIÈRE valeur d'une clé. Sans lui, la lecture d'état échoue en
#  silence et « off » croit n'avoir rien à défaire.
OUTILS="grep sed cat head tail awk tr cut mktemp mv rm sort wc mkdir dirname basename id date touch"
mkdir -p "$BANC/sysbin"
for o in $OUTILS; do
	c="$(command -v "$o" 2>/dev/null)" && ln -sf "$c" "$BANC/sysbin/$o"
done

acces() { # acces <arguments…>
	: > "$BANC/journal"
	rm -f "$BANC/etat/"* 2>/dev/null
	timeout 20 env PATH="$BANC/bin:$BANC/sysbin" HOME="$BANC/foyer" NO_COLOR=1 \
		"$BASH" "$ACCESS" "$@" >"$BANC/sortie" 2>&1
	cat "$BANC/journal" 2>/dev/null
}
mkdir -p "$BANC/foyer"

J="$(acces gros-texte on 150)"

grep -q "/Gtk/FontName" <<< "$J" \
	&& ok "la police GTK est bien agrandie (ce qui marchait déjà)" \
	|| non "la police GTK n'est plus touchée : $J"

#  ═══ LE CŒUR DE LA DEMANDE D'ALEX ═══
grep -q "/desktop-icons/font-size" <<< "$J" \
	&& ok "la taille du texte des icônes du BUREAU est écrite" \
	|| non "le bureau est oublié — « celle du bureau » ne grossit toujours pas : $J"

#  ET LE VERROU, SANS QUOI LA LIGNE PRÉCÉDENTE NE SERT À RIEN.
if grep "/desktop-icons/use-custom-font-size" <<< "$J" | grep -q "true"; then
	ok "le verrou « use-custom-font-size » est levé (sinon xfdesktop ignore la taille)"
else
	non "le verrou n'est pas levé : la taille est écrite et xfdesktop l'ignore — réglage inerte"
fi

#  LA VALEUR EST CALCULÉE, PAS COPIÉE. Base « Noto Sans 10 », facteur 150 %
#  → 15. Un banc qui ne regarde que « la clé est écrite » laisserait passer
#  une taille inchangée.
if grep "/desktop-icons/font-size" <<< "$J" | grep -qE '(^| )15( |$)'; then
	ok "la taille vaut bien 15 (base 10 × 150 %) — elle est calculée, pas recopiée"
else
	non "taille du bureau inattendue : $(grep '/desktop-icons/font-size' <<< "$J")"
fi

# =============================================================================
titre "2. « off » redescend le bureau avec le reste"
# =============================================================================
#  On enchaîne on puis off DANS LA MÊME session d'état : c'est « off » seul,
#  sur un état vierge, qui ne doit rien casser — et « off » après « on » qui
#  doit tout défaire.
: > "$BANC/journal"
timeout 20 env PATH="$BANC/bin:$BANC/sysbin" HOME="$BANC/foyer" NO_COLOR=1 \
	"$BASH" "$ACCESS" gros-texte on 150 >/dev/null 2>&1
: > "$BANC/journal"
timeout 20 env PATH="$BANC/bin:$BANC/sysbin" HOME="$BANC/foyer" NO_COLOR=1 \
	"$BASH" "$ACCESS" gros-texte off >/dev/null 2>&1
J="$(cat "$BANC/journal")"

if grep "/desktop-icons/use-custom-font-size" <<< "$J" | grep -q "false"; then
	ok "« off » relâche le verrou — xfdesktop reprend la police du système"
else
	non "« off » laisse le bureau sur une taille sur mesure : $J"
fi

# =============================================================================
titre "3. La bulle après une capture : aller voir l'image"
# =============================================================================
#  ALEX : « peux-tu le changer pour qu'on puisse aller la voir directement
#  dans le dossier images ? » Le fichier est écrit dans un SOUS-dossier
#  (~/Images/Captures) : même en connaissant « Images », on ne tombe pas
#  dessus du premier coup. On éprouve le TEXTE du script — la bulle ne peut
#  pas s'afficher ici, mais les boutons qu'elle déclare, si.
grep -q -- '-A "voir=' "$CAPTURE" \
	&& ok "la bulle déclare un bouton « voir »" \
	|| non "aucun bouton pour aller voir la capture — la demande d'Alex"

grep -q "Voir dans mes images" "$CAPTURE" \
	&& ok "…et il est écrit « Voir dans mes images »" \
	|| non "le libellé du bouton ne parle pas des images"

#  L'ORDRE COMPTE : les serveurs de notification affichent les boutons dans
#  l'ordre déclaré, et le premier est celui qu'on atteint sans réfléchir.
VOIR="$(grep -n -- '-A "voir=' "$CAPTURE" | head -1 | cut -d: -f1)"
FOND="$(grep -n -- '-A "fond=' "$CAPTURE" | head -1 | cut -d: -f1)"
if [ -n "$VOIR" ] && [ -n "$FOND" ] && [ "$VOIR" -lt "$FOND" ]; then
	ok "« Voir » est déclaré AVANT « fond d'écran » (c'est le geste courant)"
else
	non "ordre des boutons : voir=$VOIR fond=$FOND — le geste rare passerait en premier"
fi

#  ON N'A RIEN RETIRÉ. Le fond d'écran avait été demandé par Alex lui aussi ;
#  ajouter un geste ne doit pas en supprimer un autre.
grep -q "En faire mon fond d'écran" "$CAPTURE" \
	&& ok "le bouton « fond d'écran » est toujours là (on ajoute, on ne retire pas)" \
	|| non "le bouton fond d'écran a disparu — une fonction demandée a été perdue"

#  LE GESTE OUVRE UN DOSSIER, PAS UN FICHIER : « aller la voir dans le
#  dossier images », avec les captures précédentes autour.
grep -q 'ouvrir_dossier "$dossier"' "$CAPTURE" \
	&& ok "le bouton ouvre le DOSSIER de la capture" \
	|| non "le bouton n'ouvre pas le dossier"
grep -q 'dossier="$(dirname "$fichier")"' "$CAPTURE" \
	&& ok "…et ce dossier est celui du fichier, quel qu'il soit" \
	|| non "le dossier ouvert n'est pas déduit du fichier"

#  LE REPLI, comme partout ailleurs dans ce dépôt : thunar d'abord (le
#  gestionnaire de LexOS), xdg-open ensuite, et un mot honnête si ni l'un ni
#  l'autre — jamais un bouton qui ne fait rien en silence.
grep -q "command -v thunar" "$CAPTURE" \
	&& ok "thunar est essayé en premier (le gestionnaire de LexOS)" \
	|| non "thunar n'est pas essayé"
grep -q "command -v xdg-open" "$CAPTURE" \
	&& ok "…xdg-open en repli" || non "aucun repli xdg-open"
grep -q "Aucun gestionnaire de fichiers" "$CAPTURE" \
	&& ok "…et sans aucun des deux, la bulle le DIT" \
	|| non "sans gestionnaire de fichiers, le bouton échouerait en silence"

#  L'AIDE SUIT LE CODE. Une aide qui annonce un seul bouton alors qu'il y en
#  a deux est une aide qui ment — et c'est par elle qu'on découvre l'outil.
grep -q "Voir dans mes images" "$CAPTURE" && \
grep -A3 "bulle de notification" "$CAPTURE" | grep -q "Voir dans mes images" \
	&& ok "l'aide de « lexos capture » annonce les deux boutons" \
	|| non "l'aide n'a pas suivi : elle décrit encore une bulle à un seul bouton"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
