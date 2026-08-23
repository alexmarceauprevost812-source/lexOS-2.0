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
#  LES VRAIS NOMS, ET POURQUOI ÇA A CHANGÉ.
#  Ce banc fabriquait « titre-0.png », « bord-3.png »… : des noms inventés.
#  Ça suffisait tant qu'on ne faisait qu'AGRANDIR — le hook lisait la hauteur
#  de chaque PNG sans se soucier de son nom. Ça ne suffit plus depuis qu'il
#  redessine les COINS : arrondir_coins() cherche « top-left-active.png » et
#  « title-3-active.png » NOMMÉMENT. Avec les anciens noms il n'aurait rien
#  trouvé, aurait annoncé « 0/4 », et le banc aurait été content.
#  Les 45 noms viennent de common/xfwm4/assets.txt d'arc-theme. Les hauteurs
#  sont attribuées PAR RÔLE (rangée du titre / bords / bas) : c'est une
#  reconstruction fidèle du rôle, pas une copie du fichier réel — d'où un
#  décompte un peu différent de celui mesuré en tête du hook. Ce qu'on éprouve
#  ici c'est le COMPORTEMENT (28 grandit, le reste non), pas un nombre magique.
fabrique_theme() {
	local dst="$1"
	mkdir -p "$dst/xfwm4"
	python3 - "$dst/xfwm4" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
boutons = [f"{n}-{e}" for n, etats in (
    ("close",    ("active", "inactive", "prelight", "pressed")),
    ("hide",     ("active", "inactive", "prelight", "pressed")),
    ("maximize", ("active", "inactive", "prelight", "pressed")),
    ("menu",     ("active", "inactive", "pressed")),
    ("shade",    ("active", "inactive", "pressed")),
    ("stick",    ("active", "inactive", "pressed")),
) for e in etats]
titres = [f"title-{i}-{e}" for i in range(1, 6) for e in ("active", "inactive")]
coins  = [f"top-{c}-{e}" for c in ("left", "right") for e in ("active", "inactive")]
bords  = [f"{c}-{e}" for c in ("left", "right") for e in ("active", "inactive")]
bas    = [f"{c}-{e}" for c in ("bottom", "bottom-left", "bottom-right")
                     for e in ("active", "inactive")]
#  La barre de titre porte un DÉGRADÉ, pas un aplat : c'est lui qui doit se
#  retrouver dans le coin redessiné. Avec un aplat, un coin rempli de
#  n'importe quelle couleur unie serait passé pour juste.
plan = [(boutons, 28, 28, None), (titres, 7, 28, "degrade"),
        (coins, 4, 28, None), (bords, 4, 16, None), (bas, 4, 4, None)]
for noms, larg, haut, style in plan:
    for n in noms:
        im = Image.new("RGBA", (larg, haut), (30, 30, 30, 255))
        if style == "degrade":
            px = im.load()
            for y in range(haut):
                v = 30 + (y * 40) // haut
                for x in range(larg):
                    px[x, y] = (v, v, v + 8, 255)
        im.save(f"{d}/{n}.png")
PY
	printf 'button_offset=2\nbutton_spacing=2\ntitle_horizontal_offset=4\n' > "$dst/xfwm4/themerc"
}

# --- Un faux ImageMagick, qui redimensionne pour de vrai ---------------------
#  CE FAUX MAGICK SERT AUX SECTIONS 1 À 4, ET IL A SES LIMITES.
#  Il connaît deux appels : l'agrandissement (« -resize xN ») et le
#  redessin d'un coin (« -compose CopyOpacity »). Le second est une
#  RÉIMPLÉMENTATION de l'intention, pas une preuve de la commande réelle :
#  ici, il ne prouve que le pilotage — que le hook demande bien quatre coins,
#  aux bonnes dimensions, avec le bon rayon. Que la commande ImageMagick
#  produise vraiment un quart de disque, c'est la SECTION 5 qui l'éprouve,
#  avec le vrai binaire. Sans elle, ce banc ne vérifierait que ce Python.
fabrique_magick() {
	cat > "$BANC/bin/magick" <<'SH'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import re
import sys
from PIL import Image
a = sys.argv
src, sortie = a[1], a[-1]
spec = a[a.index("-resize") + 1]
larg, haut = (spec.rstrip("!").split("x") + [None])[:2]
haut = int(haut) if haut else None
im = Image.open(src).convert("RGBA")

if "CopyOpacity" in a:
    r = int(larg)
    h = haut
    dessin = a[a.index("-draw") + 1]
    rayon = int(re.search(r"roundrectangle .*?,.*? .*?,.*? (\d+),", dessin).group(1))
    im = im.resize((r, h))
    px = im.load()
    for y in range(h):
        for x in range(r):
            #  Le centre du quart de disque est au coin INTÉRIEUR du rayon.
            cx = rayon - 0.5 if "-flop" not in a else r - rayon - 0.5
            cy = rayon - 0.5
            dx, dy = x - cx, y - cy
            dedans = (dx > 0 if "-flop" not in a else dx < 0) or dy > 0
            if not dedans and (dx * dx + dy * dy) > rayon * rayon:
                px[x, y] = px[x, y][:3] + (0,)
    im.save(sortie)
else:
    h = haut
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
#  35 = 21 boutons + 10 pièces de titre + 4 coins. 10 = 4 bords + 6 du bas.
[ "$GRANDS" = "35" ] && ok "les 35 images du titre sont passées à 40 px" \
	|| non "35 attendues à 40 px, $GRANDS trouvées"
[ "$PETITS" = "10" ] && ok "les 10 bordures sont restées intactes (pas de cadre gras)" \
	|| non "10 bordures attendues intactes, $PETITS trouvées"
[ "$AUTRES" = "0" ] && ok "aucune image à une hauteur inattendue" \
	|| non "$AUTRES images à une hauteur inattendue"

#  La largeur doit suivre la hauteur, sinon les boutons seraient écrasés.
L="$(python3 -c 'import sys;from PIL import Image;print(Image.open(sys.argv[1]).width)' "$D/close-active.png")"
[ "$L" = "40" ] && ok "les proportions sont gardées (28x28 -> 40x40)" \
	|| non "largeur $L au lieu de 40 — bouton déformé"

grep -q '^button_offset=3' "$D/themerc" && grep -q '^button_spacing=3' "$D/themerc" \
	&& ok "l'écart des boutons a suivi leur taille" \
	|| non "button_offset/spacing pas repris — les boutons se toucheraient"

#  Les coins : ici on n'éprouve que le PILOTAGE (quatre appels, aux bonnes
#  dimensions). La forme réelle est éprouvée en section 6, au vrai binaire.
echo "$SORTIE" | grep -q 'coins arrondis : 4/4' \
	&& ok "les quatre coins du haut ont été redessinés" \
	|| non "le hook n'annonce pas 4/4 pour les coins"
DIMS="$(python3 -c 'import sys;from PIL import Image
print(",".join("%dx%d" % Image.open(f).size for f in sys.argv[1:]))' \
	"$D/top-left-active.png" "$D/top-left-inactive.png" \
	"$D/top-right-active.png" "$D/top-right-inactive.png")"
[ "$DIMS" = "12x40,12x40,12x40,12x40" ] \
	&& ok "les quatre coins font 12x40 (rayon 12 sur un titre de 40)" \
	|| non "dimensions des coins : $DIMS au lieu de 12x40 partout"

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
for n in ("left-active", "left-inactive", "right-active", "right-inactive",
          "bottom-active"):
    Image.new("RGBA", (4, 16), (0, 0, 0, 255)).save(f"{d}/{n}.png")
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
titre "6. Les coins, avec le VRAI ImageMagick"
#  POURQUOI CETTE SECTION EXISTE À PART.
#  Les sections 1 à 4 tournent sur un faux magick : elles prouvent que le hook
#  demande quatre coins aux bonnes dimensions, rien de plus. Si la commande
#  ImageMagick réelle était fausse — une option dans le mauvais ordre, un
#  masque lu à l'envers — elles seraient vertes quand même. C'est exactement
#  la panne des boutons de la 72 : un banc qui vérifiait la présence du
#  correctif et pas son effet.
#  Ici, on lance le MÊME hook avec le vrai binaire, et on regarde l'alpha.
VRAI_IM=""
for c in magick convert; do
	reel="$(command -v "$c" 2>/dev/null)" && { VRAI_IM="$reel"; VRAI_NOM="$c"; break; }
done
if [ -z "$VRAI_IM" ]; then
	#  On ne passe PAS en silence : un contrôle sauté doit se voir.
	non "ni magick ni convert dans ce conteneur — la forme des coins n'a PAS été éprouvée"
else
	prepare
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	ln -sf "$VRAI_IM" "$BANC/bin/$VRAI_NOM"
	fabrique_theme "$BANC/racine/themes/Arc-Dark"
	SORTIE="$(lance)"
	D="$BANC/racine/themes/LexOS-Arc-Dark/xfwm4"

	echo "$SORTIE" | grep -q 'coins arrondis : 4/4' \
		&& ok "le vrai ImageMagick a redessiné les quatre coins" \
		|| non "avec le vrai binaire, les coins ne sont pas annoncés 4/4"

	VERDICT="$(python3 - "$D" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
pb = []


def a(im, x, y):
    return im.getpixel((x, y))[3]


try:
    g = Image.open(d + "/top-left-active.png").convert("RGBA")
    dr = Image.open(d + "/top-right-active.png").convert("RGBA")
except Exception as e:
    print("ILLISIBLE %s" % e)
    raise SystemExit

if g.size != (12, 40):
    pb.append("gauche %dx%d" % g.size)

#  Le coin extérieur doit être TRANSPARENT, le coin opposé OPAQUE.
if a(g, 0, 0) > 20:
    pb.append("haut-gauche pas creuse (alpha %d)" % a(g, 0, 0))
if a(g, 11, 39) < 235:
    pb.append("bas-droit du coin gauche pas plein (alpha %d)" % a(g, 11, 39))
if a(dr, 11, 0) > 20:
    pb.append("haut-droit pas creuse (alpha %d)" % a(dr, 11, 0))
if a(dr, 0, 39) < 235:
    pb.append("bas-gauche du coin droit pas plein (alpha %d)" % a(dr, 0, 39))

#  Sous le rayon, la colonne du bord doit être pleine : sinon ce n'est pas un
#  quart de disque, c'est une diagonale qui ronge toute la hauteur.
for y in (12, 20, 39):
    if a(g, 0, y) < 235:
        pb.append("colonne 0 rongee a y=%d (alpha %d)" % (y, a(g, 0, y)))

#  La courbe doit MONTER : plus on descend, plus la ligne est pleine.
pleins = [sum(1 for x in range(12) if a(g, x, y) > 128) for y in (0, 3, 6, 11)]
if pleins != sorted(pleins):
    pb.append("la courbe ne progresse pas : %s" % pleins)
if pleins[0] >= 12:
    pb.append("premiere ligne deja pleine — aucun arrondi")

#  Et la couleur doit venir du DÉGRADÉ de la barre, pas d'un aplat inventé.
if g.getpixel((11, 15))[:3] == g.getpixel((11, 35))[:3]:
    pb.append("couleur uniforme — le coin ne reprend pas le degrade du titre")

#  Le bas reste carré : c'est un choix, il doit tenir.
b = Image.open(d + "/bottom-left-active.png").convert("RGBA")
if b.getpixel((0, b.height - 1))[3] < 235:
    pb.append("le bas a ete arrondi alors qu'il doit rester carre")

print("OK" if not pb else "PB " + " | ".join(pb))
PY
)"
	case "$VERDICT" in
		OK) ok "l'alpha est un vrai quart de disque, du dégradé du titre, bas carré" ;;
		*)  non "coins : $VERDICT" ;;
	esac

	#  ─── MUTATION : sans title-3 NI title-1, on ne doit rien inventer ───────
	prepare
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	ln -sf "$VRAI_IM" "$BANC/bin/$VRAI_NOM"
	fabrique_theme "$BANC/racine/themes/Arc-Dark"
	rm -f "$BANC/racine/themes/Arc-Dark/xfwm4"/title-*.png
	SORTIE="$(lance)"
	echo "$SORTIE" | grep -q 'coins arrondis : 0/4' \
		&& ok "sans pièce de titre, il annonce 0/4 au lieu de faire semblant" \
		|| non "sans title-*, le hook prétend avoir arrondi des coins"
	[ -d "$BANC/racine/themes/LexOS-Arc-Dark/xfwm4" ] \
		&& ok "et le reste du thème dérivé est quand même livré" \
		|| non "l'absence de coins a fait tomber tout le thème"
fi

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
