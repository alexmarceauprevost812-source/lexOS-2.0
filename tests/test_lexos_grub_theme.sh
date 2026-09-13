#!/usr/bin/env bash
# =============================================================================
#  Thème GRUB de LexOS — il doit tenir à TOUTE définition, pas qu'en 1920x1080
# =============================================================================
#  ALEX, ESSAI SUR L'ALIENWARE : « tout est déformé et les places pour le boot
#  ne sont pas bien placées ».
#
#  LA CAUSE, MESURÉE. La géométrie du thème était en PIXELS ABSOLUS, calée sur
#  1920x1080. Le hook 0910 demande « gfxmode=1920x1080,1280x720,1024x768,auto »
#  et GRUB NE REDIMENSIONNE PAS UN THÈME — mais il étire le fond. Dès que le
#  firmware ne rend pas le 1920x1080, le cadre dessiné se déplace, les entrées
#  restent à 534/449, et elles tombent à côté. En 1024x768 (4:3), un fond 16:9
#  étiré est en plus déformé.
#
#  ═══ CE QUE CE BANC MESURE, ET CE QU'IL NE PEUT PAS MESURER ═══
#  Il ne démarre pas GRUB : aucun coureur ne peut le faire. Il refait son
#  ARITHMÉTIQUE — « pourcentage x total / 100 », en entier, comme GRUB — et il
#  relève le cadre DANS background.png par ses ruptures de luminance, au lieu
#  de croire le commentaire qui l'annonce. Si un jour le dessin change sans
#  que le thème suive, c'est l'image qui aura raison ici.
#
#  Ce qui n'est donc PAS prouvé par ce banc : que l'écran d'Alex affiche bien
#  le résultat. Seule une photo de son menu le dira.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$RACINE/config/includes.binary/boot/grub/themes/lexos"
CHR="$RACINE/config/includes.chroot/usr/share/grub/themes/lexos"

REUSSIS=0; ECHOUES=0; NONMESURE=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
gris() { printf '  \033[90m—\033[0m %s\n' "$1"; NONMESURE=$((NONMESURE+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$BIN/theme.txt" ] || { echo "theme.txt introuvable"; exit 1; }

# =============================================================================
titre "1. Les deux copies du thème ne divergent pas"
# =============================================================================
#  IL Y EN A DEUX, ET C'EST VOULU : includes.binary habille le menu de la CLÉ,
#  includes.chroot celui du système INSTALLÉ. Corriger l'un sans l'autre, c'est
#  réparer le menu qu'on regarde en oubliant celui qu'on aura tous les jours.
for F in theme.txt background.png; do
	if cmp -s "$BIN/$F" "$CHR/$F"; then
		ok "$F est identique dans les deux copies"
	else
		non "$F diffère entre l'ISO et le système installé"
	fi
done

# =============================================================================
titre "2. La géométrie est en pourcentages, pas en pixels"
# =============================================================================
SORTIE="$(python3 - "$BIN/theme.txt" <<'PY'
import re, sys
txt = open(sys.argv[1], encoding="utf-8").read()

#  ON LIT LE THÈME, PAS SA PROSE. Les commentaires de ce fichier citent les
#  anciennes valeurs en pixels (« les entrées restaient à 534/449 ») pour
#  expliquer le correctif : un contrôle qui grepperait « 534 » se déclencherait
#  sur sa propre justification. On retire donc les commentaires d'abord.
code = "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))

def bloc(nom):
    m = re.search(r'\+\s*' + nom + r'\s*\{(.*?)\n\}', code, re.S)
    return m.group(1) if m else ""

def val(corps, cle):
    m = re.search(rf'^\s*{cle}\s*=\s*("?)([^"\n]+)\1', corps, re.M)
    return m.group(2).strip() if m else None

menu = bloc("boot_menu")
prob = []
for cle in ("left", "top", "width", "height"):
    v = val(menu, cle)
    if v is None:
        prob.append(f"boot_menu.{cle} absent")
    elif not v.endswith("%"):
        prob.append(f"boot_menu.{cle} = {v} (pixels)")

for nom in ("label", "progress_bar"):
    corps = bloc(nom)
    for cle in ("top", "width"):
        v = val(corps, cle)
        if v is not None and not v.endswith("%"):
            prob.append(f"{nom}.{cle} = {v} (pixels)")

print("PIXELS=%d" % len(prob))
for p in prob:
    print("  - " + p)
print("LEFT=%s"   % val(menu, "left").rstrip("%"))
print("TOP=%s"    % val(menu, "top").rstrip("%"))
print("LARG=%s"   % val(menu, "width").rstrip("%"))
print("HAUT=%s"   % val(menu, "height").rstrip("%"))
print("ITEM=%s"   % val(menu, "item_height"))
print("GOUT=%s"   % val(menu, "item_spacing"))
PY
)"

NB_PX="$(sed -n 's/^PIXELS=//p' <<< "$SORTIE")"
if [ "${NB_PX:-1}" = "0" ]; then
	ok "toute la géométrie qui doit suivre l'écran est en pourcentage"
else
	non "$NB_PX valeur(s) encore en pixels absolus :"
	sed -n '/^  - /p' <<< "$SORTIE" | while read -r l; do printf '        %s\n' "$l"; done
fi

LEFT="$(sed -n 's/^LEFT=//p'  <<< "$SORTIE")"
TOP="$(sed  -n 's/^TOP=//p'   <<< "$SORTIE")"
LARG="$(sed -n 's/^LARG=//p'  <<< "$SORTIE")"
HAUT="$(sed -n 's/^HAUT=//p'  <<< "$SORTIE")"
ITEM="$(sed -n 's/^ITEM=//p'  <<< "$SORTIE")"
GOUT="$(sed -n 's/^GOUT=//p'  <<< "$SORTIE")"

# =============================================================================
titre "3. Le cadre relevé DANS l'image, et la boîte qui doit y tenir"
# =============================================================================
if ! python3 -c "import PIL" 2>/dev/null; then
	gris "Pillow absent : le cadre n'a PAS été relevé dans background.png"
else
	CADRE="$(python3 - "$BIN/background.png" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
W, H = im.size
px = im.load()

#  ═══ TROIS MESURES RATÉES AVANT CELLE-CI, ET C'EST INSTRUCTIF ═══
#  1. « la dernière rupture de la colonne médiane » donnait un bas de cadre à
#     1078 — le bas de l'IMAGE. Le contrôle passait alors qu'il n'exigeait
#     presque rien : n'importe quelle boîte tenait dans 400→1078.
#  2. « la première ligne très claire » tombait sur le LOGO (y 120), pas sur
#     le cadre.
#  3. « la colonne du bord gauche seule » butait sur les décorations du bas.
#
#  Ce qui marche, et pourquoi : un cadre, c'est DEUX bords verticaux à la
#  même hauteur. On garde les lignes où une rupture nette existe À LA FOIS
#  près de x=520 et près de x=1400. Le logo n'en a qu'un, les décorations du
#  bas aucun des deux. Mesuré : la plage sort d'un seul tenant, sans trou.
def rupture_pres_de(y, xc, fen=6, seuil=30):
    for x in range(xc - fen, xc + fen):
        if abs(sum(px[x + 1, y]) - sum(px[x - 1, y])) > seuil:
            return True
    return False

#  Les deux bords sont cherchés autour de leur position attendue ; si le
#  dessin bouge d'un cheveu la fenêtre les retrouve, s'il change vraiment la
#  plage sort vide et le contrôle le dit au lieu de passer.
lignes = [y for y in range(1, H - 1)
          if rupture_pres_de(y, 520) and rupture_pres_de(y, 1400)]

x1 = x2 = y1 = y2 = -1
if lignes:
    y1, y2 = lignes[0], lignes[-1]
    milieu = (y1 + y2) // 2
    prof = [sum(px[x, milieu]) for x in range(W)]
    rx = [x for x in range(1, W) if abs(prof[x] - prof[x - 1]) > 30]
    if rx:
        x1, x2 = rx[0], rx[-1]

print("W=%d" % W); print("H=%d" % H)
print("X1=%d" % x1); print("X2=%d" % x2)
print("Y1=%d" % y1); print("Y2=%d" % y2)
PY
)"
	IW="$(sed -n 's/^W=//p'  <<< "$CADRE")"; IH="$(sed -n 's/^H=//p'  <<< "$CADRE")"
	X1="$(sed -n 's/^X1=//p' <<< "$CADRE")"; X2="$(sed -n 's/^X2=//p' <<< "$CADRE")"
	Y1="$(sed -n 's/^Y1=//p' <<< "$CADRE")"; Y2="$(sed -n 's/^Y2=//p' <<< "$CADRE")"

	if [ "$X1" -gt 0 ] && [ "$X2" -gt "$X1" ] && [ "$Y1" -gt 0 ] && [ "$Y2" -gt "$Y1" ]; then
		ok "cadre relevé dans l'image : x $X1→$X2, y $Y1→$Y2 (fond ${IW}x${IH})"
	else
		non "aucun cadre net trouvé dans background.png — le reste ne prouverait rien"
	fi

	#  LE CONTRÔLE QUI COMPTE. Pour chaque définition, on refait le calcul de
	#  GRUB — entier, comme lui — et on exige que la boîte des entrées tienne
	#  dans le cadre, qui suit l'étirement du fond.
	DEHORS="$(python3 - "$IW" "$IH" "$X1" "$X2" "$Y1" "$Y2" \
	                    "$LEFT" "$TOP" "$LARG" "$HAUT" "$ITEM" "$GOUT" <<'PY'
import sys
iw, ih, x1, x2, y1, y2, left, top, larg, haut, item, gout = map(int, sys.argv[1:13])

DEFS = [(1920,1080), (1280,720), (1024,768), (1920,1200), (2560,1440), (3840,2160)]
MINI = 4           # entrées visibles exigées partout (le menu BIOS en a cinq)
MINI_REF = 6       # …et à la définition de référence

mauvais = []
for W, H in DEFS:
    #  Le fond est étiré à l'écran : le cadre suit la même fraction.
    cx1, cx2 = x1 * W // iw, x2 * W // iw
    cy1, cy2 = y1 * H // ih, y2 * H // ih
    #  GRUB : pourcentage x total / 100, en entier.
    bx, by = left * W // 100, top * H // 100
    bw, bh = larg * W // 100, haut * H // 100
    if bx < cx1 or bx + bw > cx2 or by < cy1 or by + bh > cy2:
        mauvais.append(f"{W}x{H} : boîte {bx},{by} {bw}x{bh} sort du cadre "
                       f"{cx1},{cy1} → {cx2},{cy2}")
    n = bh // (item + gout)
    seuil = MINI_REF if (W, H) == (1920, 1080) else MINI
    if n < seuil:
        mauvais.append(f"{W}x{H} : {n} entrée(s) visibles, il en faut {seuil}")

print("DEHORS=%d" % len(mauvais))
for m in mauvais:
    print("  - " + m)
PY
)"
	NB_D="$(sed -n 's/^DEHORS=//p' <<< "$DEHORS")"
	if [ "${NB_PX:-1}" != "0" ]; then
		#  UN DÉFAUT DE CE BANC, TROUVÉ PAR SA PROPRE MUTATION 1. Quand la
		#  géométrie est repassée en pixels, ce calcul multiplie quand même
		#  par la définition : « left 534 » devient 10252 et les six
		#  définitions sortent fautives. Le banc rougissait — pour la bonne
		#  cause, avec un diagnostic faux. Un rouge qui raconte n'importe
		#  quoi s'apprend à ignorer aussi vite qu'un vert imméri­té.
		gris "balayage des définitions non mesuré : la géométrie n'est pas en %"
	elif [ "${NB_D:-1}" = "0" ]; then
		ok "à 1920x1080, 1280x720, 1024x768, 1920x1200, 2560x1440 et 3840x2160 :"
		ok "…la boîte reste dans le cadre et assez d'entrées restent visibles"
	else
		non "$NB_D définition(s) fautives :"
		sed -n '/^  - /p' <<< "$DEHORS" | while read -r l; do printf '        %s\n' "$l"; done
	fi
fi

# =============================================================================
titre "4. Le hook pose bien le thème et une définition de repli"
# =============================================================================
HOOK="$RACINE/config/hooks/normal/0910-lexos-grub-theme.hook.binary"
if grep -q 'set gfxmode=' "$HOOK"; then
	ok "le hook fixe gfxmode (sinon le firmware choisit, et le thème suit mal)"
else
	non "aucun « set gfxmode » dans le hook 0910"
fi
grep -q 'set theme=' "$HOOK" \
	&& ok "…et il pose la ligne « set theme »" \
	|| non "le hook ne pose pas « set theme »"

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' \
	"$REUSSIS" "$ECHOUES" "$NONMESURE"
[ "$ECHOUES" -eq 0 ]
