#!/usr/bin/env bash
# =============================================================================
#  Les trois premières lettres, sur n'importe quel dossier
# =============================================================================
#  ALEX, captures de Fichiers : « ajouter toujours sur les dossiers, quand on
#  renomme les dossiers, l'écriture des 3 premières lettres sur le dossier. »
#  Sur ses captures, Documents/Images/Musique/Vidéos/Téléchargements portent
#  bien leur pastille — mais Bureau, Modèles, Public et « Projets LexOS » sont
#  des dossiers nus.
#
#  ═══ DEUX CAUSES DIFFÉRENTES, DEUX CORRECTIFS ═══
#  1) Bureau, Modèles et Public étaient des LIENS vers folder.svg, le dossier
#     nu. Le thème avait bien un nom pour eux, il pointait juste sur le mauvais
#     dessin. Trois fichiers à écrire.
#  2) « Projets LexOS » est un dossier créé par Alex : GIO demande « folder »
#     pour lui, et aucun thème ne peut deviner « PRO » à partir d'un nom de
#     dossier — un thème ne voit pas les noms. C'est une limite de forme.
#     D'où lexos-etiquette, qui fabrique l'icône et la colle SUR le dossier.
#
#  ═══ CE QUE CE BANC NE PEUT PAS FAIRE ═══
#  Vérifier que Thunar AFFICHE l'icône. Il n'y a ni session graphique ni
#  démon de métadonnées gvfs ici : « gio set » échoue dans ce conteneur. Le
#  banc éprouve donc tout ce qui précède — les lettres, le dessin, son
#  emplacement, le refus propre quand ça rate — et dit franchement où il
#  s'arrête. Seul Alex peut confirmer le dernier pas.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-etiquette"
THEME="$RACINE/config/includes.chroot/usr/share/icons/LexOS/places/scalable"
UCA="$RACINE/config/includes.chroot/etc/skel/.config/Thunar/uca.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

pastille_de() { # pastille_de <fichier svg> → le texte de la pastille, ou vide
	python3 - "$1" <<'PY'
import re, sys
t = re.findall(r'<text[^>]*>([^<]*)</text>', open(sys.argv[1], encoding="utf-8").read(), re.S)
print((t[0].strip() if t else ""))
PY
}

# =============================================================================
titre "1. Les dossiers du thème portent tous leur pastille"
# =============================================================================
#  Ceux d'Alex, nommément. Trois d'entre eux étaient des liens vers le dossier
#  nu : les nommer ici fait que le message dit tout de suite de quoi il s'agit
#  si quelqu'un les remet en lien un jour.
for PAIRE in "user-desktop:BUR" "folder-templates:MOD" "folder-publicshare:PUB" \
             "folder-documents:DOC" "folder-pictures:IMG" "folder-music:MUS" \
             "folder-videos:VID" "folder-download:DL"; do
	NOM="${PAIRE%%:*}"; ATT="${PAIRE#*:}"
	F="$THEME/$NOM.svg"
	if [[ ! -r "$F" ]]; then
		non "« $NOM.svg » manque"
		continue
	fi
	VU="$(pastille_de "$F")"
	if [[ "$VU" == "$ATT" ]]; then
		ok "« $NOM » porte « $ATT »"
	else
		non "« $NOM » porte « ${VU:-rien} » au lieu de « $ATT »"
	fi
done

#  ET LE DOSSIER GÉNÉRIQUE RESTE NU : c'est lui qui sert de modèle à l'outil,
#  et une pastille en dur dedans se retrouverait sous toutes les autres.
if [[ -z "$(pastille_de "$THEME/folder.svg")" ]]; then
	ok "le dossier générique reste sans pastille — c'est le modèle de l'outil"
else
	non "folder.svg porte une pastille en dur : elle apparaîtrait sous toutes les autres"
fi

# =============================================================================
titre "2. Les trois lettres, sur de vrais noms"
# =============================================================================
#  DEUX JETS ONT ÉCHOUÉ AVANT LE BON, et ce contrôle existe pour ça :
#    · « iconv //TRANSLIT » supprimait les accents au lieu de les traduire —
#      « Téléchargements » donnait TLC, et le résultat changeait selon la
#      locale de la session ;
#    · « s/[àâä]/a/g » comparait des OCTETS : en UTF-8, « é » et « à »
#      partagent leur premier octet, d'où TAE et AEC.
#  Les deux passaient inaperçus sans un banc qui regarde le résultat.
lettres() { bash -c 'source <(sed -n "/^etiquette_de()/,/^}/p" "$0"); etiquette_de "$1"' "$OUTIL" "$1"; }

for PAIRE in "Projets LexOS:PRO" "Téléchargements:TEL" "école:ECO" "Ça marche:CAM" \
             "Œuvres:OEU" "Sauvegardes vidéo:SAU" "3d models:3DM" "Notes:NOT"; do
	NOM="${PAIRE%%:*}"; ATT="${PAIRE#*:}"
	VU="$(lettres "$NOM")"
	if [[ "$VU" == "$ATT" ]]; then
		ok "« $NOM » → $ATT"
	else
		non "« $NOM » → « ${VU:-vide} » au lieu de « $ATT »"
	fi
done
#  Un nom sans aucune lettre latine ne doit pas produire une pastille vide :
#  l'outil refuse et le dit, plutôt que de coller un dossier nu par-dessus le
#  dossier nu.
if [[ -z "$(lettres "音楽")" ]]; then
	ok "un nom sans lettre latine ne donne rien — l'outil refusera"
else
	non "un nom sans lettre latine produit une étiquette : elle serait illisible"
fi

# =============================================================================
titre "3. L'image est VRAIMENT dessinée, et au bon endroit"
# =============================================================================
#  Une étiquette maison qui ne s'aligne pas avec DOC et IMG se verrait tout de
#  suite. On compare donc les pixels des deux, pas les intentions.
if ! command -v rsvg-convert >/dev/null 2>&1 || ! python3 -c "import PIL" 2>/dev/null; then
	non "rsvg-convert ou Pillow absent : l'image n'a PAS été dessinée ni mesurée"
else
	mkdir -p "$BANC/maison/Projets LexOS" "$BANC/data"
	HOME="$BANC/maison" XDG_DATA_HOME="$BANC/data" \
		LEXOS_ICONES="$RACINE/config/includes.chroot/usr/share/icons/LexOS" \
		bash "$OUTIL" "$BANC/maison/Projets LexOS" > "$BANC/sortie.txt" 2>&1
	PNG="$(find "$BANC/data" -name '*.png' | head -1)"
	if [[ -n "$PNG" && -s "$PNG" ]]; then
		ok "l'image est fabriquée même si la pose échoue ($(basename "$PNG"))"
	else
		non "aucune image produite"
	fi
	if [[ -n "$PNG" ]]; then
		rsvg-convert -w 256 -h 256 -o "$BANC/doc.png" "$THEME/folder-documents.svg" 2>/dev/null
		VERDICT="$(python3 - "$PNG" "$BANC/doc.png" <<'PY'
from PIL import Image
import sys
#  Le cadre du TEXTE BLANC : c'est lui qui doit tomber au même endroit dans
#  les deux images. On isole les pixels quasi blancs et opaques.
def cadre(chemin):
    im = Image.open(chemin).convert("RGBA")
    L, H = im.size
    px = im.load()
    xs, ys = [], []
    for y in range(H):
        for x in range(L):
            r, g, b, a = px[x, y]
            if a > 150 and r > 220 and g > 220 and b > 220:
                xs.append(x); ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))

a, b = cadre(sys.argv[1]), cadre(sys.argv[2])
if a is None or b is None:
    print("PB:pastille introuvable dans %s" % ("l'outil" if a is None else "le thème"))
else:
    #  Même hauteur de ligne, même centre vertical : la largeur peut différer
    #  (PRO et DOC n'ont pas la même chasse, mais trois lettres chacun).
    dh = abs((a[3] - a[1]) - (b[3] - b[1]))
    dy = abs((a[1] + a[3]) - (b[1] + b[3])) // 2
    print("PB:" + ("" if dh <= 2 and dy <= 3 else
          "hauteur %+d px, centre %+d px" % (dh, dy)))
    print("OUTIL:%s" % (a,))
    print("THEME:%s" % (b,))
PY
)"
		PB="$(printf '%s' "$VERDICT" | sed -n 's/^PB://p')"
		if [[ -z "$PB" ]]; then
			ok "la pastille tombe au même endroit que celle du thème"
		else
			non "la pastille est décalée : $PB"
		fi
	fi
	#  ═══ ET L'ÉCHEC EST HONNÊTE ═══ Sans démon de métadonnées, « gio set »
	#  ne peut pas poser l'icône. L'outil doit le DIRE : une commande qui rend
	#  0 en silence ferait croire que c'est fait.
	if grep -q 'refusé de poser' "$BANC/sortie.txt" || grep -q '→' "$BANC/sortie.txt"; then
		ok "il annonce ce qu'il a fait, ou pourquoi il n'a pas pu"
	else
		non "il ne dit rien : on croirait l'étiquette posée"
	fi
fi

# =============================================================================
titre "4. Les dossiers déjà servis par le thème sont laissés tranquilles"
# =============================================================================
#  Leur pastille suit la langue et l'accent du système. Leur coller une image
#  FIXE par-dessus, c'est figer ce que le thème fait mieux.
for N in Documents Images Musique "Téléchargements" Bureau "Modèles" Public; do
	grep -q "$N" "$OUTIL" \
		&& ok "« $N » est reconnu comme déjà servi" \
		|| non "« $N » n'est pas dans la liste : --maison lui collerait une icône fixe"
done

# =============================================================================
titre "5. Trois chemins y mènent"
# =============================================================================
#  Un outil qu'on ne peut lancer que d'une seule façon est un outil qu'on
#  oublie. Le contrôle 16 réclame déjà le dispatcheur et les Paramètres ; le
#  clic droit est celui qu'Alex emploiera vraiment.
grep -qE '^\s*etiquette\|' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos etiquette » existe" \
	|| non "le dispatcheur ne connaît pas « etiquette »"
grep -q '"etiquettes":' "$RACINE/config/includes.chroot/usr/lib/lexos/settings.py" \
	&& ok "Paramètres sait l'ouvrir" \
	|| non "aucun chemin depuis les Paramètres"
grep -q "ouvrir('etiquettes')" "$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js" \
	&& ok "…et la page porte le bouton" \
	|| non "le moteur a l'action mais la page n'a pas de bouton : action morte"
if grep -q 'lexos-etiquette %F' "$UCA"; then
	ok "le clic droit dans Fichiers propose « Étiqueter ce dossier »"
else
	non "aucune action de clic droit — le chemin le plus naturel manque"
fi
#  Les identifiants d'action de Thunar doivent rester uniques, sinon Thunar
#  en écarte une SANS RIEN DIRE.
if python3 -c "
import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
ids = [a.findtext('unique-id') for a in r.findall('action')]
sys.exit(0 if len(ids) == len(set(ids)) else 1)
" "$UCA" 2>/dev/null; then
	ok "les identifiants des actions du clic droit sont uniques"
else
	non "deux actions partagent un identifiant : Thunar en écartera une en silence"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
