#!/usr/bin/env bash
# =============================================================================
#  Les images de thème — et SURTOUT : celles qui n'arrivent jamais dans l'ISO
# =============================================================================
#  Alex a déposé verifier-images.py sans consigne. Il a été éprouvé comme les
#  autres — en le faisant tourner. Il a trouvé DEUX vrais défauts et SIX faux,
#  et c'est en tirant sur un de ses fils qu'on a découvert le plus gros trou
#  du dépôt à ce jour.
#
#  ═══ CE QU'IL A TROUVÉ DE VRAI ═══
#    · branding/icon-github.png portait un bloc eXIf au CRC faux. Conséquence
#      mesurée, et elle est nette : Pillow REFUSE le fichier entier
#      (UnidentifiedImageError), pas seulement le bloc.
#    · branding/logo-ti-lex-al.png était un JPEG. « file » : « JPEG image
#      data, 1024x1024 ». Il servait de repli au logo dans le hook 0300.
#
#  ═══ CE QU'IL A DIT DE FAUX ═══
#    · quatre fichiers du thème GRUB déclarés « cassés » pour cause de 4 bits
#      par canal. Vérifié dans grub-core/video/readers/png.c : GRUB accepte
#      le 4 bits EN PALETTE, et c'est exactement ce que sont ces fichiers ;
#    · quinze lignes « sed réécrit un lot de fichiers » : le « * » relevé
#      était celui du « .* » de la substitution, pas un motif de fichiers ;
#    · et il se signalait LUI-MÊME, citant « mogrify » dans son propre code.
#
#  ═══ LE TROU QU'AUCUN OUTIL NE VOYAIT ═══
#  build.sh recopiait branding/*.svg *.png *.webp *.gif *.mp4 dans l'image.
#  PAS les .jpg. Or fond-mascotte.jpg et fond-tilexal-banniere.jpg — les deux
#  fonds d'écran d'Alex — sont des .jpg. Ils n'arrivaient donc JAMAIS dans le
#  chroot ; le hook 0300 imprimait « absent » et passait. Aucune ISO publiée
#  n'a jamais contenu ces deux fonds.
#
#  ET UN BANC ÉTAIT VERT DESSUS DEPUIS LE DÉBUT. tests/test_lexos_fonds_alex.sh
#  recopie lui-même les deux fichiers depuis branding/ dans sa fausse
#  arborescence, puis vérifie que le hook les découpe bien. Il éprouve la
#  RECETTE ; personne n'éprouvait la LIVRAISON. C'est le contrôle 2 ci-dessous,
#  et c'est le seul qui aurait attrapé ça.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/tools/verifier-images.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; NONMESURE=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
gris() { printf '  \033[90m—\033[0m %s\n' "$1"; NONMESURE=$((NONMESURE+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$OUTIL" ] || { echo "tools/verifier-images.py introuvable"; exit 1; }

# =============================================================================
titre "1. Aucune image du dépôt n'est cassée"
# =============================================================================
SORTIE="$(cd "$RACINE" && NO_COLOR=1 python3 "$OUTIL" 2>&1)"
NB="$(sed -n 's/^\([0-9]*\) cassée(s).*/\1/p' <<< "$SORTIE")"
if grep -q "Rien à signaler" <<< "$SORTIE" || [ "${NB:-1}" = "0" ]; then
	ok "verifier-images ne trouve aucune image cassée"
else
	non "$NB image(s) cassée(s) :"
	sed -n '/^  ✗/,+1p' <<< "$SORTIE" | while read -r l; do printf '        %s\n' "$l"; done
fi

# =============================================================================
titre "2. Tout ce qu'un hook LIT sous \$BRAND est LIVRÉ par build.sh"
# =============================================================================
#  LE CONTRÔLE QUI MANQUAIT, ET QUI A COÛTÉ DEUX FONDS D'ÉCRAN.
LIVRAISON="$(cd "$RACINE" && python3 - <<'PY'
import glob, os, re

#  Ce que build.sh recopie réellement vers l'arbre de l'image.
src = open("build.sh", encoding="utf-8").read()
bloc = re.search(r'BRAND_DST=.*?(?=\n#\s*---|\nok ")', src, re.S)
bloc = bloc.group(0) if bloc else src
livres = set()
for m in re.finditer(r'cp[^\n]*branding/([^\s"\']+)[^\n]*"\$BRAND_DST"', bloc):
    for motif in re.findall(r'branding/(\*\.[A-Za-z0-9]+)', m.group(0)):
        livres.add(motif[1:].lower())          # « *.jpg » -> « .jpg »

#  Ce que les hooks vont chercher sous $BRAND.
demandes = {}
for f in glob.glob("config/hooks/**/*", recursive=True):
    if not os.path.isfile(f):
        continue
    try:
        txt = open(f, errors="ignore", encoding="utf-8").read()
    except OSError:
        continue
    for nom in re.findall(r'\$\{?BRAND\}?/([A-Za-z0-9][A-Za-z0-9._-]*)', txt):
        demandes.setdefault(nom, set()).add(os.path.basename(f))

#  ON NE JUGE QUE CE QUI EXISTE DANS branding/ : un hook peut écrire sous
#  $BRAND des fichiers qu'il fabrique lui-même, et exiger leur présence en
#  amont serait faux. Un fichier qui EXISTE dans branding/ et qu'un hook LIT,
#  lui, doit arriver — sinon il est là pour rien.
perdus = []
for nom, ou in sorted(demandes.items()):
    if not os.path.isfile(os.path.join("branding", nom)):
        continue
    ext = os.path.splitext(nom)[1].lower()
    if ext not in livres:
        perdus.append("%s (lu par %s) — build.sh ne copie pas les %s"
                      % (nom, ", ".join(sorted(ou)[:2]), ext))

print("LIVRES=%s" % ",".join(sorted(livres)))
print("PERDUS=%d" % len(perdus))
for p in perdus:
    print("  - " + p)
PY
)"
EXT="$(sed -n 's/^LIVRES=//p' <<< "$LIVRAISON")"
NBP="$(sed -n 's/^PERDUS=//p' <<< "$LIVRAISON")"
[ -n "$EXT" ] \
	&& ok "build.sh livre : $EXT" \
	|| non "aucune extension relevée dans build.sh — le contrôle ne prouverait rien"
if [ "${NBP:-1}" = "0" ]; then
	ok "chaque fichier de branding/ qu'un hook lit arrive bien dans l'image"
else
	non "$NBP fichier(s) réclamés par un hook et jamais livrés :"
	sed -n '/^  - /p' <<< "$LIVRAISON" | while read -r l; do printf '        %s\n' "$l"; done
fi

#  ET LES DEUX FONDS D'ALEX NOMMÉMENT : c'est eux qui manquaient, et un
#  contrôle général peut être affaibli sans qu'on s'en aperçoive.
for F in fond-mascotte.jpg fond-tilexal-banniere.jpg; do
	grep -q "jpg" <<< "$EXT" && [ -r "$RACINE/branding/$F" ] \
		&& ok "$F est dans branding/ et les .jpg sont livrés" \
		|| non "$F ne serait pas livré — le fond d'écran d'Alex manquerait encore"
done

# =============================================================================
titre "3. L'outil sait dire NON — et ne dit pas non à tort"
# =============================================================================
#  UN VÉRIFICATEUR QUI NE TROUVE JAMAIS RIEN EST UN VÉRIFICATEUR MORT. On lui
#  fabrique de vrais cas, et on mesure ce qu'il en dit.
FAUX="$BANC/faux"; mkdir -p "$FAUX/branding" "$FAUX/config/includes.binary/boot/grub/themes/lexos"
python3 - "$FAUX" <<'PY'
import os, struct, sys, zlib
base = sys.argv[1]

def png(chemin, largeur, hauteur, prof, coul, donnees, palette=None):
    def bloc(typ, charge):
        return (struct.pack(">I", len(charge)) + typ + charge
                + struct.pack(">I", zlib.crc32(typ + charge) & 0xFFFFFFFF))
    d = b"\x89PNG\r\n\x1a\n"
    d += bloc(b"IHDR", struct.pack(">IIBBBBB", largeur, hauteur, prof, coul, 0, 0, 0))
    if palette:
        d += bloc(b"PLTE", palette)
    d += bloc(b"IDAT", zlib.compress(donnees))
    d += bloc(b"IEND", b"")
    open(chemin, "wb").write(d)

#  Un PNG 4 bits EN PALETTE : GRUB l'accepte, l'outil ne doit PAS le refuser.
png(os.path.join(base, "config/includes.binary/boot/grub/themes/lexos/select_c.png"),
    2, 1, 4, 3, b"\x00\x10", palette=b"\xff\x7a\x18\x09\x0a\x0c")

#  Un PNG tronqué : l'outil DOIT le refuser.
chemin = os.path.join(base, "branding", "casse.png")
png(chemin, 2, 1, 8, 2, b"\x00\xff\x00\x00\x00\x00\xff")
d = open(chemin, "rb").read()
open(chemin, "wb").write(d[:-6])
PY
#  Une ligne de sed parfaitement saine, avec un « .* » dans la substitution.
cat > "$FAUX/faux-hook.sh" <<'HOOK'
#!/bin/sh
sed -i -e "s|^icon-theme-name=.*|icon-theme-name=LexOS|" "$CONF"
HOOK
S="$(cd "$FAUX" && NO_COLOR=1 python3 "$OUTIL" 2>&1)"
grep -q "casse.png" <<< "$S" \
	&& ok "un PNG tronqué est bien signalé (l'outil peut rougir)" \
	|| non "un PNG tronqué passe inaperçu — l'outil ne prouverait plus rien :\n$S"
grep -q "select_c.png" <<< "$S" \
	&& non "un PNG 4 bits EN PALETTE est refusé à tort — GRUB l'accepte" \
	|| ok "un PNG 4 bits en palette n'est PAS refusé (GRUB l'accepte)"
grep -q "faux-hook.sh" <<< "$S" \
	&& non "une substitution sed entre guillemets est signalée à tort" \
	|| ok "le « .* » d'une substitution sed n'est plus pris pour un lot de fichiers"
grep -q "verifier-images.py" <<< "$S" \
	&& non "l'outil se signale lui-même (il cite les commandes qu'il traque)" \
	|| ok "l'outil ne se signale plus lui-même"

# =============================================================================
titre "4. Ce que git doit garder intact"
# =============================================================================
GA="$RACINE/.gitattributes"
if [ -r "$GA" ]; then
	ok ".gitattributes existe"
	MANQUE=""
	for E in png jpg svg mp4; do
		grep -qE "^\*\.${E}[[:space:]]" "$GA" || MANQUE="$MANQUE .$E"
	done
	[ -z "$MANQUE" ] && ok "…et il déclare png, jpg, svg et mp4" \
		|| non "extensions non déclarées :$MANQUE"
	grep -qE '^\*\.png[[:space:]]+binary' "$GA" \
		&& ok "…les PNG sont déclarés binaires (pas de réécriture de fins de ligne)" \
		|| non "les PNG ne sont pas déclarés binaires"
else
	non ".gitattributes absent : un clone peut abîmer les images sans qu'on y touche"
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' \
	"$REUSSIS" "$ECHOUES" "$NONMESURE"
[ "$ECHOUES" -eq 0 ]
