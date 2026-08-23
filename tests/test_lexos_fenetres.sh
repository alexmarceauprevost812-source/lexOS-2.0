#!/usr/bin/env bash
# =============================================================================
#  Éprouver le hook 0610 — les boutons de fenêtre
# =============================================================================
#  POURQUOI CE BANC EXISTE.
#
#  Le hook 0905 a coûté TROIS ISO — 66, 68, 69 — parce qu'on ne pouvait le
#  lancer que dans une vraie construction : une heure et quart pour savoir si
#  une ligne de sed marchait. Chaque essai brûlait une soirée.
#
#  Celui-ci se lance en deux secondes, sur un faux thème et un faux
#  ImageMagick. Il vérifie ce qu'aucune relecture ne prouve : que les 32
#  images de la rangée du titre grandissent, que les 13 bordures ne bougent
#  PAS, et surtout que le nom du thème dérivé arrive bien jusqu'à
#  lexos-firstrun et « lexos theme » — les deux programmes qui, au build 70,
#  ont effacé le travail du hook des icônes à la première session.
#
#  LE PATH EST FERMÉ. Sans ça, « ImageMagick absent » ne prouverait rien : le
#  conteneur pourrait en avoir un vrai, et le cas ne serait jamais éprouvé.
#  C'est l'erreur commise sur test_lexos_materiel, corrigée là-bas puis
#  reprise ici d'emblée.
# =============================================================================
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0610-lexos-fenetres.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

python3 -c 'import PIL' 2>/dev/null || {
	echo "Pillow absent — ce banc en a besoin pour fabriquer de vrais PNG."
	exit 1
}

# --- Un faux thème, aux trois hauteurs du vrai -------------------------------
#  32 images de 28 px (la rangée du titre), 7 de 16 (bords latéraux),
#  6 de 4 (bord du bas) : la répartition mesurée sur l'Arc-Dark réel.
fabrique_theme() {
	local dst="$1"
	mkdir -p "$dst/xfwm4"
	python3 - "$dst/xfwm4" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
plan = [("titre", 32, 28, 28), ("bord", 7, 4, 16), ("bas", 6, 6, 4)]
for nom, combien, larg, haut in plan:
    for i in range(combien):
        Image.new("RGBA", (larg, haut), (30, 30, 30, 255)).save(f"{d}/{nom}-{i}.png")
PY
	printf 'button_offset=2\nbutton_spacing=2\ntitle_horizontal_offset=4\n' > "$dst/xfwm4/themerc"
}

# --- Un faux ImageMagick, qui redimensionne pour de vrai ---------------------
fabrique_magick() {
	cat > "$BANC/bin/magick" <<'SH'
#!/usr/bin/env bash
#  magick <fichier> -resize xN <sortie>
python3 - "$@" <<'PY'
import sys
from PIL import Image
src, sortie = sys.argv[1], sys.argv[-1]
spec = sys.argv[sys.argv.index("-resize") + 1]
h = int(spec.lstrip("x"))
im = Image.open(src)
im.resize((max(1, round(im.width * h / im.height)), h)).save(sortie)
PY
SH
	chmod +x "$BANC/bin/magick"
}

# --- Un PATH fermé : rien d'autre que ce qu'on y met -------------------------
NECESSAIRES="bash sh od awk sed grep cp rm mkdir touch cat dirname basename printf env python3"
ferme_path() {
	rm -rf "${BANC:?}/min"; mkdir -p "$BANC/min"
	for c in $NECESSAIRES; do
		reel="$(command -v "$c" 2>/dev/null)" && ln -sf "$reel" "$BANC/min/$c"
	done
}

prepare() {
	rm -rf "${BANC:?}/racine" "${BANC:?}/bin"
	mkdir -p "$BANC/bin" "$BANC/racine/themes" "$BANC/racine/etc/lexos" "$BANC/racine/skel"
	cat > "$BANC/racine/skel/xfwm4.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme"                     type="string" value="Arc-Dark"/>
    <property name="title_font"                type="string" value="Sans Bold 13"/>
  </property>
</channel>
XML
}

lance() {
	PATH="$BANC/bin:$BANC/min" \
	LEXOS_THEMES="$BANC/racine/themes" \
	LEXOS_BUILD_CONF="$BANC/racine/etc/lexos/build.conf" \
	LEXOS_XFWM_XML="$BANC/racine/skel/xfwm4.xml" \
	sh "$HOOK" 2>&1
}

hauteur() { python3 -c 'import sys;from PIL import Image;print(Image.open(sys.argv[1]).height)' "$1"; }

ferme_path

# ═════════════════════════════════════════════════════════════════════════════
titre "1. Le cas nominal : les deux thèmes sont là"
prepare; fabrique_magick
fabrique_theme "$BANC/racine/themes/Arc-Dark"
fabrique_theme "$BANC/racine/themes/Arc"
SORTIE="$(lance)"

D="$BANC/racine/themes/LexOS-Arc-Dark/xfwm4"
if [ -d "$D" ]; then ok "le thème sombre dérivé existe"; else non "pas de LexOS-Arc-Dark"; fi
[ -d "$BANC/racine/themes/LexOS-Arc/xfwm4" ] \
	&& ok "le thème clair dérivé existe aussi (mode clair pas oublié)" \
	|| non "LexOS-Arc manquant — les boutons redeviendraient petits en mode clair"

GRANDS=0; PETITS=0; AUTRES=0
for f in "$D"/*.png; do
	case "$(hauteur "$f")" in
		40) GRANDS=$((GRANDS+1)) ;;
		16|4) PETITS=$((PETITS+1)) ;;
		*) AUTRES=$((AUTRES+1)) ;;
	esac
done
[ "$GRANDS" = "32" ] && ok "les 32 images du titre sont passées à 40 px" \
	|| non "32 attendues à 40 px, $GRANDS trouvées"
[ "$PETITS" = "13" ] && ok "les 13 bordures sont restées intactes (pas de cadre gras)" \
	|| non "13 bordures attendues intactes, $PETITS trouvées"
[ "$AUTRES" = "0" ] && ok "aucune image à une hauteur inattendue" \
	|| non "$AUTRES images à une hauteur inattendue"

#  La largeur doit suivre la hauteur, sinon les boutons seraient écrasés.
L="$(python3 -c 'import sys;from PIL import Image;print(Image.open(sys.argv[1]).width)' "$D/titre-0.png")"
[ "$L" = "40" ] && ok "les proportions sont gardées (28x28 -> 40x40)" \
	|| non "largeur $L au lieu de 40 — bouton déformé"

grep -q '^button_offset=3' "$D/themerc" && grep -q '^button_spacing=3' "$D/themerc" \
	&& ok "l'écart des boutons a suivi leur taille" \
	|| non "button_offset/spacing pas repris — les boutons se toucheraient"

# ═════════════════════════════════════════════════════════════════════════════
titre "2. La source unique — la leçon des icônes du build 70"
CONF="$BANC/racine/etc/lexos/build.conf"
grep -q '^LEXOS_XFWM_THEME="LexOS-Arc-Dark"' "$CONF" \
	&& ok "build.conf publie le thème sombre retenu" \
	|| non "LEXOS_XFWM_THEME absent — firstrun écraserait le thème dérivé"
grep -q '^LEXOS_XFWM_THEME_CLAIR="LexOS-Arc"' "$CONF" \
	&& ok "build.conf publie aussi le thème clair" \
	|| non "LEXOS_XFWM_THEME_CLAIR absent"

grep -q 'value="LexOS-Arc-Dark"' "$BANC/racine/skel/xfwm4.xml" \
	&& ok "le XML du squelette nomme le thème dérivé" \
	|| non "le squelette nomme encore l'ancien thème"
grep -q 'name="title_font"' "$BANC/racine/skel/xfwm4.xml" \
	&& ok "les autres propriétés du XML n'ont pas été touchées" \
	|| non "le sed a mangé autre chose que la valeur du thème"

#  Relancer ne doit pas doubler les clés : un hook rejoué (ou une construction
#  reprise) ne doit pas laisser deux LEXOS_XFWM_THEME dans build.conf.
lance >/dev/null
N="$(grep -c '^LEXOS_XFWM_THEME=' "$CONF")"
[ "$N" = "1" ] && ok "rejouer le hook ne double pas la clé" \
	|| non "$N occurrences de LEXOS_XFWM_THEME après deux passages"

# ═════════════════════════════════════════════════════════════════════════════
titre "3. Ce qui doit échouer proprement"
prepare; fabrique_magick
SORTIE="$(lance)"
echo "$SORTIE" | grep -q 'absent' \
	&& ok "sans aucun thème Arc, il le DIT" \
	|| non "aucun thème, et pourtant rien dans le journal"
[ ! -d "$BANC/racine/themes/LexOS-Arc-Dark" ] \
	&& ok "et ne laisse pas de thème vide derrière lui" \
	|| non "un LexOS-Arc-Dark a été créé sans source"

prepare   # pas de faux magick cette fois
fabrique_theme "$BANC/racine/themes/Arc-Dark"
SORTIE="$(lance)"
echo "$SORTIE" | grep -qi 'ni magick ni convert' \
	&& ok "sans ImageMagick, il le dit au lieu de planter" \
	|| non "ImageMagick absent : message attendu introuvable"
[ ! -d "$BANC/racine/themes/LexOS-Arc-Dark" ] \
	&& ok "et le thème d'origine reste seul en place" \
	|| non "un thème dérivé a été créé sans ImageMagick"
[ -d "$BANC/racine/themes/Arc-Dark/xfwm4" ] \
	&& ok "Arc-Dark n'a pas été abîmé" \
	|| non "Arc-Dark a disparu"

# ═════════════════════════════════════════════════════════════════════════════
titre "4. Le mensonge poli : un thème qui ne change rien"
prepare; fabrique_magick
#  Un thème dont AUCUNE image ne fait 28 px : rien à agrandir. Le hook doit
#  effacer le dérivé plutôt que livrer une copie sous notre nom.
mkdir -p "$BANC/racine/themes/Arc-Dark/xfwm4"
python3 - "$BANC/racine/themes/Arc-Dark/xfwm4" <<'PY'
from PIL import Image
import sys
d = sys.argv[1]
for i in range(5):
    Image.new("RGBA", (4, 16), (0, 0, 0, 255)).save(f"{d}/bord-{i}.png")
PY
SORTIE="$(lance)"
[ ! -d "$BANC/racine/themes/LexOS-Arc-Dark" ] \
	&& ok "aucune image agrandie -> le thème dérivé est effacé" \
	|| non "un thème identique à Arc-Dark a été livré sous notre nom"
echo "$SORTIE" | grep -q 'aucune image agrandie' \
	&& ok "et il le dit franchement" \
	|| non "effacé en silence"
! grep -q '^LEXOS_XFWM_THEME="LexOS' "$BANC/racine/etc/lexos/build.conf" 2>/dev/null \
	&& ok "build.conf ne nomme pas un thème qui n'existe pas" \
	|| non "build.conf nomme un thème effacé — XFCE retomberait en clair"

# ═════════════════════════════════════════════════════════════════════════════
titre "5. Les deux programmes qui effaçaient tout au build 70"
FR="$RACINE/config/includes.chroot/usr/bin/lexos-firstrun"
LX="$RACINE/config/includes.chroot/usr/bin/lexos"
grep -q 'LEXOS_XFWM_THEME' "$FR" \
	&& ok "lexos-firstrun lit le thème de fenêtre dans build.conf" \
	|| non "lexos-firstrun écrirait encore le thème GTK par-dessus"
grep -q 'LEXOS_XFWM_THEME_CLAIR' "$LX" \
	&& ok "« lexos theme » lit les deux modes dans build.conf" \
	|| non "« lexos theme » écraserait le thème dérivé à chaque changement"
grep -q 'p /general/theme *-s "\$XFWM_THEME"' "$FR" \
	&& ok "et firstrun pose bien CE nom-là, pas le thème GTK" \
	|| non "firstrun pose encore autre chose que XFWM_THEME"
grep -q 'p /general/theme *-s "\$xfwm"' "$LX" \
	&& ok "et « lexos theme » aussi" \
	|| non "« lexos theme » pose encore le thème GTK sur les fenêtres"

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
