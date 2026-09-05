#!/usr/bin/env bash
# =============================================================================
#  L'écran de démarrage — la mascotte se tient, le logo s'écrit, la pluie tombe
# =============================================================================
#  ALEX : mascotte fixe en haut, « LEXOS » qui s'écrit lettre par lettre en
#  dessous, pluie Matrix verte en fond, barre de progression passée au vert.
#
#  ═══ CE QUE CET ÉCRAN AVAIT DE CASSÉ ═══
#  La mascotte s'agitait en 16 images de 240×240 sur un écran de 1920×1080 :
#  un timbre-poste, flou dès qu'on l'agrandit, où l'on ne distinguait ni le
#  masque ni le geste de la main. Et deux animations en même temps — la
#  mascotte ET la barre — laissaient l'œil sans point d'accroche.
#
#  ═══ POURQUOI CE BANC EXISTE ═══
#  UN ÉCRAN DE DÉMARRAGE NE SE REGARDE QU'AU DÉMARRAGE SUIVANT. Une lettre de
#  la mauvaise taille décale tout l'alignement ; une lettre au fond opaque
#  découpe ses voisines pendant le glissement ; une courbe linéaire donne un
#  mouvement de robot — et RIEN de tout ça ne se voit avant d'avoir gravé une
#  clé, redémarré une machine et regardé une seconde et demie d'animation.
#  C'est le pire cycle de retour du dépôt.
#
#  ═══ CE BANC N'INSPECTE PAS LE HOOK : IL LE FAIT TOURNER ═══
#  Le fragment entre les marqueurs « banc: plymouth » est DÉCOUPÉ du hook 0300
#  et EXÉCUTÉ sur un faux thème, un faux dossier de marque et un vrai
#  ImageMagick. On regarde ensuite le thème PRODUIT, pas le code qui prétend
#  le produire. Trois passages, parce que ce sont les trois états qui
#  comptent :
#
#    · tout est là          -> thème complet, avec la pluie ;
#    · la pluie manque      -> thème complet SANS elle. Une décoration ne doit
#                              jamais pouvoir casser l'écran de démarrage ;
#    · une lettre manque    -> repli « two-step », et le journal le DIT.
#
#  S'y ajoutent les deux mesures que seule une lecture d'image donne : les
#  dimensions (en-tête PNG) et le détourage (canal alpha décodé pixel par
#  pixel).
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
BRANDING="$RACINE/branding"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
IM=""
for c in magick convert; do command -v "$c" >/dev/null 2>&1 && { IM="$c"; break; }; done

# =============================================================================
titre "1. Les images sont là, aux dimensions EXACTES"
# =============================================================================
#  Les décalages du logo (0/102/202/304/418) ont été mesurés sur ces images-là.
#  Une lettre plus large ou plus étroite, et le mot se disloque — visible
#  seulement au démarrage suivant.
#
#  ON LIT L'EN-TÊTE PNG, on n'appelle pas ImageMagick : largeur et hauteur
#  sont aux octets 16 à 23, en gros boutiste, juste après la signature et
#  l'amorce du bloc IHDR. Aucune dépendance, et la même mesure qu'un outil
#  d'image.
dim_png() { # dim_png <fichier> -> « LxH »
	od -An -tu1 -j16 -N8 "$1" 2>/dev/null | awk '
		{ printf "%dx%d",
			$1*16777216 + $2*65536 + $3*256 + $4,
			$5*16777216 + $6*65536 + $7*256 + $8 }'
}

verifie_image() { # verifie_image <fichier> <LxH attendu>
	if [ ! -r "$BRANDING/$1" ]; then
		non "$1 absent de branding/"
		return 1
	fi
	VU="$(dim_png "$BRANDING/$1")"
	if [ "$VU" = "$2" ]; then
		ok "$1 : $VU"
		return 0
	fi
	non "$1 fait $VU au lieu de $2"
	return 1
}

MANQUE=0
verifie_image lexos-lettre-0.png  "98x138"   || MANQUE=1
verifie_image lexos-lettre-1.png  "98x138"   || MANQUE=1
verifie_image lexos-lettre-2.png  "100x138"  || MANQUE=1
verifie_image lexos-lettre-3.png  "112x138"  || MANQUE=1
verifie_image lexos-lettre-4.png  "100x138"  || MANQUE=1
verifie_image mascotte-splash.png "449x540"  || MANQUE=1
verifie_image pluie-demarrage.png "1920x1080" || true   # décoration : non bloquante

# =============================================================================
titre "2. Les lettres sont VRAIMENT détourées"
# =============================================================================
#  L'ASSERTION QUI COMPTE LE PLUS, ET LA MOINS VISIBLE. Une lettre au fond
#  NOIR OPAQUE se confond avec le fond noir de l'écran : elle a l'air
#  parfaite… jusqu'à ce qu'elle passe DEVANT sa voisine pendant le glissement
#  et lui découpe un rectangle. On ne verrait ça que sur une vidéo du
#  démarrage, image par image.
#
#  On ne se contente donc pas de « le PNG a un canal alpha » — un canal alpha
#  entièrement opaque en est un aussi. On décode les pixels et on COMPTE les
#  transparents.
if [ -z "$PY" ]; then
	saut "python3 absent : le détourage n'a PAS été mesuré"
elif [ "$MANQUE" = 1 ]; then
	saut "images manquantes : le détourage n'a PAS été mesuré"
else
	"$PY" - "$BRANDING" <<'PYEOF' > "$BANC/alpha.txt" 2>/dev/null || true
import sys, zlib, struct, os

def pixels(chemin):
    d = open(chemin, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    pos, idat, ihdr = 8, b'', None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]
        if typ == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', data[:13])
        elif typ == b'IDAT':
            idat += data
        pos += 12 + ln
    if ihdr is None:
        return None
    w, h, depth, ctype, comp, filt, entrelace = ihdr
    #  On ne traite que le cas qui nous intéresse : 8 bits, RVB+alpha, non
    #  entrelacé. Tout le reste rend None et le banc le DIT au lieu de deviner.
    if depth != 8 or ctype != 6 or entrelace != 0:
        return None
    brut = zlib.decompress(idat)
    bpp, stride = 4, w * 4
    sortie, prec = bytearray(), bytearray(stride)
    i = 0
    for _ in range(h):
        f = brut[i]; i += 1
        ligne = bytearray(brut[i:i+stride]); i += stride
        for x in range(stride):
            a = ligne[x-bpp] if x >= bpp else 0
            b = prec[x]
            c = prec[x-bpp] if x >= bpp else 0
            if f == 1:   ligne[x] = (ligne[x] + a) & 255
            elif f == 2: ligne[x] = (ligne[x] + b) & 255
            elif f == 3: ligne[x] = (ligne[x] + (a + b) // 2) & 255
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                ligne[x] = (ligne[x] + pr) & 255
        sortie += ligne
        prec = ligne
    return w, h, bytes(sortie)

racine = sys.argv[1]
for n in range(5):
    f = os.path.join(racine, 'lexos-lettre-%d.png' % n)
    r = pixels(f)
    if r is None:
        print('%d ERREUR 0' % n)
        continue
    w, h, px = r
    transp = sum(1 for i in range(3, len(px), 4) if px[i] == 0)
    print('%d %d %d' % (n, transp, w * h))
PYEOF
	if [ ! -s "$BANC/alpha.txt" ]; then
		non "le décodage des lettres n'a rien rendu — détourage NON vérifié"
	else
		while read -r NUM TRANSP TOTAL; do
			if [ "$TRANSP" = "ERREUR" ]; then
				non "lexos-lettre-$NUM.png : pas du 8 bits RVB+alpha non entrelacé — illisible ici"
			elif [ "$TRANSP" -gt 0 ] 2>/dev/null; then
				ok "lexos-lettre-$NUM.png : $(( 100 * TRANSP / TOTAL )) % de pixels transparents — vraiment détourée"
			else
				non "lexos-lettre-$NUM.png n'a AUCUN pixel transparent : elle découperait ses voisines"
			fi
		done < "$BANC/alpha.txt"
	fi
fi

# =============================================================================
titre "3. Le hook 0300 est DÉCOUPÉ et EXÉCUTÉ"
# =============================================================================
FRAGMENT="$BANC/fragment.sh"
sed -n '/^# >>> banc: plymouth$/,/^# <<< banc: plymouth$/p' "$HOOK" > "$FRAGMENT"
if [ "$(grep -c . "$FRAGMENT")" -lt 60 ]; then
	non "fragment « banc: plymouth » introuvable dans le hook 0300 — rien à éprouver"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
	exit 1
fi
ok "fragment découpé du hook 0300 ($(grep -c . "$FRAGMENT") lignes) — c'est le vrai code qui tourne"

#  Le fragment attend trois choses que le hook lui donne plus haut : le
#  dossier de marque, le logo du watermark, et « have ». On les fournit,
#  et RIEN D'AUTRE — si le fragment se met un jour à dépendre d'autre chose,
#  il échouera ici au lieu de le faire en pleine construction d'ISO.
prelude() { # prelude <dossier-de-marque>
	printf '#!/bin/sh\nset -e\nBRAND="%s"\nLOGO_SRC=""\nhave() { command -v "$1" >/dev/null 2>&1; }\n' "$1"
}

lance() { # lance <dossier-de-marque> <destination> -> journal sur stdout
	rm -rf "$2"
	{ prelude "$1"; cat "$FRAGMENT"; } > "$BANC/run.sh"
	LEXOS_PLYMOUTH_SRC="$BANC/spinner" LEXOS_PLYMOUTH_DST="$2" \
		sh "$BANC/run.sh" 2>&1
}

#  Un faux thème « spinner » : le hook en part par copie. Deux fichiers
#  suffisent — on éprouve ce que LexOS écrit, pas ce que Debian livre.
mkdir -p "$BANC/spinner"
: > "$BANC/spinner/spinner.plymouth"
: > "$BANC/spinner/throbber.png"

if [ -z "$IM" ]; then
	saut "ni magick ni convert : le thème n'a PAS été généré, les contrôles 3 à 5 sont sautés"
elif [ "$MANQUE" = 1 ]; then
	saut "images manquantes : le thème n'a PAS été généré"
else
	# --- Passage 1 : tout est là --------------------------------------------
	mkdir -p "$BANC/brand"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand/"
	[ -r "$BRANDING/pluie-demarrage.png" ] && cp "$BRANDING/pluie-demarrage.png" "$BANC/brand/"
	JOURNAL="$(lance "$BANC/brand" "$BANC/theme1")"
	SCRIPT="$BANC/theme1/lexos.script"

	if [ -r "$SCRIPT" ]; then
		ok "le thème « script » est produit ($(grep -c . "$SCRIPT") lignes)"
	else
		non "aucun lexos.script produit : l'écran de démarrage serait celui de Debian"
	fi

	if [ -r "$BANC/theme1/lexos.plymouth" ] && grep -q 'ModuleName=script' "$BANC/theme1/lexos.plymouth"; then
		ok "lexos.plymouth déclare bien le module « script »"
	else
		non "lexos.plymouth ne déclare pas le module « script »"
	fi

	#  Les six images sont VRAIMENT posées à côté du script — Plymouth les
	#  cherche dans son ImageDir, pas dans branding/.
	POSEES=0
	for F in lexos-lettre-0.png lexos-lettre-1.png lexos-lettre-2.png \
	         lexos-lettre-3.png lexos-lettre-4.png mascotte-splash.png; do
		[ -r "$BANC/theme1/$F" ] && POSEES=$((POSEES+1))
	done
	if [ "$POSEES" = 6 ]; then
		ok "les six images sont posées dans le thème, à côté du script"
	else
		non "$POSEES image(s) sur 6 posées dans le thème — Plymouth n'en trouverait pas"
	fi

	#  ET ELLES NE SONT PAS RETOUCHÉES. Le logo est du pixel carré : un
	#  passage dans convert le lisserait et lui ferait perdre son air d'écran
	#  cathodique. On compare octet pour octet.
	INTACTES=1
	for I in 0 1 2 3 4; do
		cmp -s "$BRANDING/lexos-lettre-$I.png" "$BANC/theme1/lexos-lettre-$I.png" || INTACTES=0
	done
	if [ "$INTACTES" = 1 ]; then
		ok "les lettres sont copiées OCTET POUR OCTET — jamais rééchantillonnées"
	else
		non "une lettre a été modifiée en chemin : le logo serait flou"
	fi

	# --- Ce que le script produit contient ----------------------------------
	if [ -r "$SCRIPT" ]; then
		ATTENDUS="0 102 202 304 418"
		VUS=""
		for I in 0 1 2 3 4; do
			VUS="$VUS $(sed -n "s/^lettre_dx\[$I\][[:space:]]*=[[:space:]]*\([0-9]\+\);.*/\1/p" "$SCRIPT" | head -1)"
		done
		VUS="${VUS# }"
		if [ "$VUS" = "$ATTENDUS" ]; then
			ok "les cinq décalages sont ceux mesurés sur le logo ($VUS)"
		else
			non "décalages « $VUS » au lieu de « $ATTENDUS » — le mot ne serait plus aligné"
		fi

		#  Le total 518 n'est pas un nombre écrit à côté : c'est le décalage
		#  de la DERNIÈRE lettre plus SA largeur réelle. Si Alex remplace un
		#  jour le S par un dessin plus large sans toucher au reste, ce
		#  contrôle le dit.
		DECL="$(sed -n 's/^logo_largeur[[:space:]]*=[[:space:]]*\([0-9]\+\);.*/\1/p' "$SCRIPT" | head -1)"
		L4="$(dim_png "$BRANDING/lexos-lettre-4.png")"; L4="${L4%x*}"
		SOMME=$(( 418 + L4 ))
		if [ "$SOMME" = "${DECL:-0}" ] && [ "$SOMME" = "518" ]; then
			ok "418 + la largeur réelle du S ($L4) = $SOMME, et c'est bien logo_largeur"
		else
			non "418 + $L4 = $SOMME, mais le script déclare logo_largeur=${DECL:-vide} (attendu 518)"
		fi

		#  LA COURBE EST CUBIQUE, ET C'EST TOUT L'EFFET : p = 1 − (1−t)³. La
		#  lettre part vite et se pose en douceur. Une interpolation linéaire
		#  donnerait un mouvement de robot avec un arrêt net — indiscernable
		#  dans un diff, évident à l'écran.
		if grep -qE '1[[:space:]]*-[[:space:]]*reste[[:space:]]*\*[[:space:]]*reste[[:space:]]*\*[[:space:]]*reste' "$SCRIPT"; then
			ok "le glissement suit une courbe CUBIQUE (1 − (1−t)³)"
		else
			non "pas de courbe cubique : le mouvement serait celui d'un robot"
		fi

		if grep -q 'SetOpacity(opacite)' "$SCRIPT" && grep -qE 'opacite[[:space:]]*=[[:space:]]*p[[:space:]]*\*' "$SCRIPT"; then
			ok "la lettre monte en opacité pendant son trajet"
		else
			non "l'opacité ne suit pas le trajet : la lettre surgirait au bord de l'écran"
		fi

		NB="$(grep -c 'lettre_sprite\[[0-4]\][[:space:]]*=[[:space:]]*Sprite()' "$SCRIPT")"
		if [ "$NB" = "5" ]; then
			ok "les cinq lettres ont chacune leur Sprite — elles n'arrivent pas ensemble"
		else
			non "$NB Sprite(s) de lettre au lieu de 5"
		fi

		NB="$(grep -c 'Image("lexos-lettre-[0-4].png")' "$SCRIPT")"
		if [ "$NB" = "5" ]; then
			ok "les cinq images de lettres sont chargées"
		else
			non "$NB image(s) de lettre chargée(s) au lieu de 5"
		fi

		if grep -q 'Plymouth.SetRefreshFunction' "$SCRIPT" && grep -q 'Plymouth.GetTime()' "$SCRIPT"; then
			ok "l'animation est pilotée par l'horloge de Plymouth"
		else
			non "aucune fonction de rafraîchissement : les lettres ne bougeraient pas"
		fi

		#  Une barre minutée qui avance toute seule est un mensonge poli, et
		#  elle ment surtout le jour où le démarrage bloque.
		if grep -q 'Plymouth.SetBootProgressFunction(progress_callback)' "$SCRIPT"; then
			ok "la barre est branchée sur la progression RÉELLE du démarrage"
		else
			non "la barre n'est plus branchée sur Plymouth : elle ferait semblant"
		fi

		if grep -q 'mascot-anim' "$SCRIPT"; then
			non "le thème produit référence encore mascot-anim-*.png"
		else
			ok "aucune référence aux 16 images : la mascotte est fixe"
		fi

		if grep -q 'Image("mascotte-splash.png")' "$SCRIPT"; then
			ok "la mascotte affichée est bien mascotte-splash.png"
		else
			non "le script n'affiche pas mascotte-splash.png"
		fi

		#  L'ordre de superposition. Une barre sous la mascotte disparaîtrait
		#  derrière elle ; une pluie au-dessus des lettres les voilerait.
		Z=1
		grep -q 'pluie_sprite.SetZ(1);'        "$SCRIPT" || Z=0
		grep -q 'mascotte_sprite.SetZ(10);'    "$SCRIPT" || Z=0
		grep -q 'SetZ(15);'                    "$SCRIPT" || Z=0
		grep -q 'progress_bg_sprite.SetZ(20);' "$SCRIPT" || Z=0
		grep -q 'progress_fg_sprite.SetZ(21);' "$SCRIPT" || Z=0
		if [ "$Z" = 1 ]; then
			ok "superposition : pluie 1, mascotte 10, lettres 15, barre 20/21"
		else
			non "l'ordre de superposition n'est pas 1 / 10 / 15 / 20 / 21"
		fi

		# --- La pluie -------------------------------------------------------
		if [ -r "$BANC/theme1/pluie-demarrage.png" ]; then
			ok "la pluie est copiée dans le thème, à côté du script"
		else
			non "la pluie n'est pas copiée dans le thème : Plymouth ne la trouverait pas"
		fi
		if grep -q 'pluie_image.Scale(Window.GetWidth(), Window.GetHeight())' "$SCRIPT"; then
			ok "la pluie est étirée à la fenêtre — elle tient à toute résolution"
		else
			non "la pluie n'est pas mise à l'échelle de la fenêtre"
		fi
	fi

	# --- Passage 2 : SANS la pluie ------------------------------------------
	titre "4. La pluie est une DÉCORATION — on la retire pour de vrai"
	#  Une décoration ne doit jamais pouvoir casser l'écran de démarrage.
	#  On ne lit pas le code pour s'en convaincre : on enlève l'image et on
	#  regénère.
	rm -rf "$BANC/brand2"; mkdir -p "$BANC/brand2"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand2/"
	J2="$(lance "$BANC/brand2" "$BANC/theme2")"
	S2="$BANC/theme2/lexos.script"
	if [ -r "$S2" ] && [ "$(grep -c . "$S2")" -gt 80 ]; then
		ok "sans la pluie, le thème se génère quand même ($(grep -c . "$S2") lignes)"
	else
		non "sans la pluie, le thème ne se génère plus — une décoration casse l'écran"
	fi
	if [ -r "$S2" ] && grep -q 'Image("pluie-demarrage.png")' "$S2"; then
		non "le script charge une pluie qui n'existe pas : image nulle au démarrage"
	else
		ok "le script ne charge pas d'image de pluie absente"
	fi
	if printf '%s' "$J2" | grep -q 'pluie-demarrage.png absente'; then
		ok "l'absence de la pluie se DIT dans le journal de construction"
	else
		non "la pluie manque en silence — on ne saurait pas pourquoi l'écran est nu"
	fi
	if [ -r "$BANC/theme2/lexos.plymouth" ] && grep -q 'ModuleName=script' "$BANC/theme2/lexos.plymouth"; then
		ok "sans la pluie, on reste sur le thème animé (pas de repli inutile)"
	else
		non "l'absence de la pluie a fait retomber sur le repli statique"
	fi

	# --- Passage 3 : une lettre manque --------------------------------------
	titre "5. Une lettre manquante ne donne PAS un thème vide"
	rm -rf "$BANC/brand3"; mkdir -p "$BANC/brand3"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand3/"
	[ -r "$BRANDING/pluie-demarrage.png" ] && cp "$BRANDING/pluie-demarrage.png" "$BANC/brand3/"
	rm -f "$BANC/brand3/lexos-lettre-3.png"
	J3="$(lance "$BANC/brand3" "$BANC/theme3")"
	if [ -r "$BANC/theme3/lexos.plymouth" ] && grep -q 'ModuleName=two-step' "$BANC/theme3/lexos.plymouth"; then
		ok "le repli statique « two-step » est écrit — l'écran n'est pas vide"
	else
		non "pas de repli : une lettre absente donnerait un écran de démarrage nu"
	fi
	if [ ! -f "$BANC/theme3/lexos.script" ]; then
		ok "aucun lexos.script orphelin n'est laissé derrière"
	else
		non "un lexos.script traîne alors qu'on est en repli"
	fi
	if printf '%s' "$J3" | grep -q 'lettres ou mascotte absentes'; then
		ok "le repli se DIT dans le journal de construction"
	else
		non "le repli est silencieux — on livrerait un écran nu sans le savoir"
	fi
fi

# =============================================================================
titre "6. La barre est VERTE — et elle le reste quel que soit l'accent"
# =============================================================================
if [ -n "$IM" ] && [ -r "$BANC/theme1/progress-fg.png" ] && [ -n "$PY" ]; then
	#  ON MESURE LE PIXEL PRODUIT, pas la ligne de commande qui prétend
	#  l'écrire. C'est un PNG d'un seul pixel : on lit sa couleur.
	COUL="$("$PY" - "$BANC/theme1" <<'PYEOF' 2>/dev/null
import sys, zlib, struct, os

#  ImageMagick n'ecrit PAS ces images d'un pixel en RVB. MESURE sur la vraie
#  sortie de « convert -size 1x1 xc:'#1F9E3D' » : c'est un PNG a PALETTE, un
#  seul bit de profondeur, dont la couleur vit dans le bloc PLTE. Une premiere
#  version ne lisait que le cas RVB et rendait « ? » — un controle qui ne
#  mesurait rien. On traite donc les deux formes, et on refuse de deviner pour
#  tout le reste.
def couleur(chemin):
    d = open(chemin, 'rb').read()
    pos, idat, plte, ihdr = 8, b'', None, None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]
        if typ == b'IHDR':   ihdr = struct.unpack('>IIBB', data[:10])
        elif typ == b'PLTE': plte = data
        elif typ == b'IDAT': idat += data
        pos += 12 + ln
    if ihdr is None:
        return '?'
    w, h, depth, ctype = ihdr
    brut = zlib.decompress(idat)
    if len(brut) < 2:
        return '?'
    octet = brut[1]                      # brut[0] = octet de filtre
    if ctype == 3 and plte:
        #  L'index du premier pixel occupe les bits de poids fort.
        idx = (octet >> (8 - depth)) & ((1 << depth) - 1)
        if len(plte) < 3 * (idx + 1):
            return '?'
        return '#%02X%02X%02X' % tuple(plte[3*idx:3*idx+3])
    if ctype in (2, 6) and depth == 8:
        return '#%02X%02X%02X' % tuple(brut[1:4])
    return '?'

r = sys.argv[1]
print(couleur(os.path.join(r, 'progress-fg.png')),
      couleur(os.path.join(r, 'progress-bg.png')))
PYEOF
)"
	VERT="${COUL%% *}"; GRIS="${COUL##* }"
	if [ "$VERT" = "#1F9E3D" ]; then
		ok "le pixel de remplissage MESURÉ est vert : $VERT"
	else
		non "le remplissage de la barre vaut « $VERT » au lieu de #1F9E3D"
	fi
	if [ "$GRIS" = "#1A1A1C" ]; then
		ok "le pixel de fond MESURÉ est le gris voulu : $GRIS"
	else
		non "le fond de la barre vaut « $GRIS » au lieu de #1A1A1C"
	fi
else
	saut "thème non généré ou python3 absent : les couleurs de la barre n'ont PAS été mesurées"
fi

#  ═══ LE PIÈGE, ET POURQUOI CE CONTRÔLE VAUT PLUS QU'IL N'EN A L'AIR ═══
#  #E8590C n'est pas une couleur, c'est un JETON : lexos-theme-gen le remplace
#  par l'accent courant (« lexos accent bleu »), et le hook 0600 fait pareil
#  pour l'écran de connexion. Si la barre de démarrage était écrite avec ce
#  jeton, elle changerait de couleur avec l'accent — un défaut qu'on ne
#  verrait qu'au démarrage suivant, longtemps après le changement qui l'a
#  causé.
#
#  ON DÉCOUPE SUR DES ANCRES ASCII, ET C'EST UNE LEÇON PAYÉE ICI MÊME. La
#  première version bornait le bloc sur « # --- Thème Plymouth ». Hors d'une
#  locale UTF-8, le « . » d'un sed ne couvre qu'UN OCTET et le « è » en fait
#  deux : la plage ne s'ouvrait jamais, le bloc sortait VIDE, et les grep qui
#  y cherchent une absence passaient au vert sans rien avoir lu. Un faux vert,
#  exactement ce que ce dépôt traque.
BLOC_PLY="$(awk '/^# >>> banc: plymouth$/{d=1} d{print} /^# <<< banc: plymouth$/{exit}' "$HOOK")"
if [ "$(printf '%s' "$BLOC_PLY" | grep -c .)" -lt 60 ]; then
	non "bloc Plymouth du hook 0300 introuvable — les contrôles suivants seraient vides"
	BLOC_PLY="__VIDE__"
else
	ok "bloc Plymouth découpé du hook ($(printf '%s' "$BLOC_PLY" | grep -c .) lignes)"
fi

if printf '%s' "$BLOC_PLY" | grep -q "xc:'#E8590C'"; then
	non "la barre de démarrage est peinte avec le JETON d'accent : elle suivrait « lexos accent »"
else
	ok "la barre n'emploie pas le jeton d'accent — elle est hors du chemin de substitution"
fi

#  ET ON LE VÉRIFIE DE L'AUTRE CÔTÉ : aucun des deux programmes qui font la
#  substitution ne connaît Plymouth. Le jour où quelqu'un y ajoute le thème de
#  démarrage, ce contrôle rougit avant l'ISO.
SUBST=1
grep -qi 'plymouth' "$GEN" && SUBST=0
grep -qi 'plymouth' "$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot" && SUBST=0
if [ "$SUBST" = 1 ]; then
	ok "ni lexos-theme-gen ni le hook 0600 ne touchent au thème Plymouth"
else
	non "un programme de substitution d'accent nomme Plymouth — la barre pourrait changer de couleur"
fi

#  LA MESURE DEMANDÉE PAR ALEX : on lance vraiment le générateur avec un
#  accent NON-ORANGE et on regarde si le vert a bougé.
if [ -r "$GEN" ]; then
	AVANT="$(grep -c "xc:'#1F9E3D'" "$HOOK")"
	rm -rf "$BANC/accent"; mkdir -p "$BANC/accent"
	LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/accent" bleu >/dev/null 2>&1 || true
	APRES="$(grep -c "xc:'#1F9E3D'" "$HOOK")"
	FUITE=0
	grep -rq '#1F9E3D' "$BANC/accent" 2>/dev/null && FUITE=1
	if [ "$AVANT" = "$APRES" ] && [ "$AVANT" -gt 0 ] && [ "$FUITE" = 0 ]; then
		ok "« lexos accent bleu » lancé pour de vrai : le vert de la barre est intact"
	else
		non "le vert de la barre a bougé après un changement d'accent (avant=$AVANT après=$APRES)"
	fi
else
	saut "lexos-theme-gen illisible : le changement d'accent n'a PAS été mesuré"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLa mascotte se tient, le logo s'\''écrit, la pluie tombe, la barre est verte.\033[0m\n'
