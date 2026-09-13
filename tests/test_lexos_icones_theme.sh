#!/usr/bin/env bash
# =============================================================================
#  Le thème d'icônes livré : ce que GTK REGARDE, pas ce qui est sur le disque
# =============================================================================
#  ALEX, DEUX PHOTOS DU DOCK : « toujours le gestionnaire de fichiers, il
#  garde jamais l'image du fichier. » Au repos une poche orange, au survol un
#  engrenage bleu-vert — jamais l'icône dessinée pour lui.
#
#  ═══ LE CORRECTIF EXISTAIT DÉJÀ, ET IL NE S'EXÉCUTAIT JAMAIS ═══
#  apps/scalable contenait cinq liens (Thunar.svg, thunar.svg,
#  org.xfce.thunar.svg, file-manager.svg, system-file-manager.svg) vers
#  folder-open.svg. Les fichiers étaient là, installés, livrés dans l'ISO.
#
#  Mais « Directories= » de index.theme ne listait que « places/scalable ».
#  La spécification freedesktop est formelle : un dossier ABSENT de cette
#  liste n'est PAS parcouru. GTK ne cherchait donc même pas dans apps/scalable
#  et continuait la chaîne d'héritage jusqu'à un engrenage générique. Aucune
#  erreur, aucun fichier manquant — cinq icônes invisibles.
#
#  ═══ POURQUOI AUCUN BANC NE L'A VU ═══
#  test_boutons.sh compare déjà dossiers déclarés et dossiers présents — mais
#  sur la COPIE que lexos-theme-gen fabrique pour un accent non-orange, jamais
#  sur le THÈME SOURCE qui part dans l'ISO. Le fichier fautif n'était éprouvé
#  par personne.
#
#  ═══ CE QUE CE BANC ÉPROUVE ═══
#  La question utile n'est pas « le fichier existe-t-il » — il existait — mais
#  « GTK ira-t-il le chercher ». On lit donc index.theme comme GTK le lit, et
#  on exige que chaque dossier du disque y soit déclaré, et réciproquement.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$RACINE/config/includes.chroot/usr/share/icons/LexOS"
INDEX="$THEME/index.theme"

reussis=0; echoues=0; nonmesure=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
gris()  { printf '  \033[90m—\033[0m %s\n' "$1"; nonmesure=$((nonmesure+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. index.theme est lisible, et par un vrai lecteur de configuration"
# =============================================================================
if [[ -r "$INDEX" ]]; then
	ok "le thème livré porte bien son index.theme"
else
	non "index.theme introuvable — sans lui GTK ignore le thème ENTIER"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi

#  On le lit avec configparser, PAS avec grep : un fichier qu'un lecteur de
#  configuration refuse est un fichier que GTK refuse aussi, et un grep
#  content de trouver sa ligne ne le dirait jamais.
if python3 -c "
import configparser,sys
c=configparser.ConfigParser(); c.read(sys.argv[1], encoding='utf-8')
assert 'Icon Theme' in c.sections()
" "$INDEX" 2>/dev/null; then
	ok "il se parse, et porte bien sa section « [Icon Theme] »"
else
	non "index.theme ne se parse pas, ou n'a pas de section « [Icon Theme] »"
fi

# =============================================================================
titre "2. CHAQUE dossier du disque est déclaré — le bogue d'Alex"
# =============================================================================
#  LE CŒUR. Un dossier non déclaré n'est pas parcouru : ses icônes existent
#  et ne servent à rien. C'est précisément ce qui est arrivé à apps/scalable.
RESULTAT="$(python3 - "$INDEX" "$THEME" <<'PY'
import configparser, os, sys
index, racine = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser(); c.read(index, encoding="utf-8")
declares = [d.strip() for d in c["Icon Theme"].get("Directories", "").split(",") if d.strip()]

#  Les dossiers RÉELLEMENT présents, à la profondeur « contexte/taille ».
sur_disque = []
for ctx in sorted(os.listdir(racine)):
    p = os.path.join(racine, ctx)
    if not os.path.isdir(p):
        continue
    for taille in sorted(os.listdir(p)):
        q = os.path.join(p, taille)
        #  Un dossier VIDE ne mérite pas d'être déclaré : ce qu'on traque,
        #  c'est une icône livrée que personne ne regarde.
        if os.path.isdir(q) and os.listdir(q):
            sur_disque.append(f"{ctx}/{taille}")

manquants = [d for d in sur_disque if d not in declares]
fantomes  = [d for d in declares if not os.path.isdir(os.path.join(racine, d))]
sans_sect = [d for d in declares if d not in c.sections()]

print("MANQUANTS:" + ",".join(manquants))
print("FANTOMES:" + ",".join(fantomes))
print("SANS_SECTION:" + ",".join(sans_sect))
print("DISQUE:" + ",".join(sur_disque))
PY
)"
lire() { printf '%s' "$RESULTAT" | grep "^$1:" | cut -d: -f2-; }

MANQUANTS="$(lire MANQUANTS)"
if [[ -z "$MANQUANTS" ]]; then
	ok "aucun dossier livré n'est ignoré par GTK (sur le disque : $(lire DISQUE))"
else
	non "dossier(s) présents mais NON déclarés — leurs icônes sont invisibles : $MANQUANTS"
fi

#  L'INVERSE COMPTE AUSSI : un dossier déclaré mais absent fait chercher GTK
#  dans le vide. Ce n'est pas une panne visible, c'est une déclaration qui ment.
FANTOMES="$(lire FANTOMES)"
if [[ -z "$FANTOMES" ]]; then
	ok "aucun dossier déclaré n'est absent du disque"
else
	non "dossier(s) déclarés mais introuvables : $FANTOMES"
fi

#  Et chaque dossier déclaré doit avoir SA SECTION, sinon GTK ne connaît ni sa
#  taille ni son type et l'écarte.
SANS="$(lire SANS_SECTION)"
if [[ -z "$SANS" ]]; then
	ok "chaque dossier déclaré porte sa section [dossier] (taille, type)"
else
	non "dossier(s) déclarés sans section — GTK ne saurait pas les lire : $SANS"
fi

# =============================================================================
titre "3. Le nom que Thunar demande VRAIMENT est couvert"
# =============================================================================
#  « Icon=org.xfce.thunar » — relevé dans le thunar.desktop du VRAI paquet
#  Debian, pas deviné de mémoire. Les autres écritures sont là parce que
#  d'autres applications (et plank, selon la façon dont il résout le lanceur)
#  demandent l'un ou l'autre nom.
for NOM in org.xfce.thunar thunar Thunar file-manager system-file-manager; do
	F="$THEME/apps/scalable/$NOM.svg"
	if [[ ! -e "$F" ]]; then
		non "« $NOM » : aucune icône — le dock retomberait sur un engrenage générique"
	elif [[ ! -r "$F" ]]; then
		non "« $NOM » : lien cassé (la cible n'existe pas)"
	elif python3 -c "import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1])" "$F" 2>/dev/null; then
		ok "« $NOM » : icône présente et lisible"
	else
		non "« $NOM » : le fichier n'est pas un SVG valide"
	fi
done

#  ET CE DOSSIER-LÀ EN PARTICULIER doit être déclaré. Le contrôle général
#  ci-dessus le couvre déjà, mais nommer le cas vécu fait que le message dit
#  tout de suite de quoi il s'agit si quelqu'un le retire un jour.
if grep -q '^Directories=.*apps/scalable' "$INDEX"; then
	ok "apps/scalable est déclaré — l'icône d'Alex sera enfin cherchée"
else
	non "apps/scalable n'est plus déclaré : le gestionnaire de fichiers reperd son icône"
fi

# =============================================================================
titre "4. La chaîne d'héritage reste un filet, pas un trou"
# =============================================================================
#  Le thème ne porte qu'une poignée d'icônes ; TOUT le reste vient de
#  l'héritage. Une chaîne vide ou tronquée ferait disparaître des milliers
#  d'icônes d'un coup — bien pire que le bogue qu'on répare.
HERITE="$(grep -m1 '^Inherits=' "$INDEX" | sed 's/^Inherits=//')"
if [[ -z "$HERITE" ]]; then
	non "aucun héritage : tout ce que le thème ne porte pas disparaîtrait"
else
	ok "héritage déclaré : $HERITE"
fi
#  « hicolor » DOIT terminer la chaîne : c'est le thème de dernier recours de
#  la spécification, celui où toute application dépose ses propres icônes. Si
#  Papirus n'est pas installé (sa liste est optionnelle), c'est lui qui reste.
if grep -q 'hicolor' <<< "$HERITE" ; then
	ok "« hicolor » ferme la chaîne — le dernier recours de la spécification"
else
	non "« hicolor » absent : les icônes propres aux applications seraient perdues"
fi

# =============================================================================
titre "5. Le disque dur porte le dessin de LexOS, pas celui de Papirus"
# =============================================================================
#  ALEX, PHOTO DU DOCK : le disque dur est une icône générique grise et bleue
#  au milieu des poches orange de LexOS. Le thème ne redéfinissait que les
#  dossiers ; le disque était hérité — exactement comme le Bureau l'était
#  avant qu'on ne trouve « user-desktop ».
DEV="$THEME/devices/scalable"

#  LES NOMS SONT CEUX DE GIO, RELEVÉS DANS SON BINAIRE — c'est GIO qui nomme
#  l'icône d'un volume monté, et c'est lui que Plank, Thunar et le bureau
#  interrogent. Les autres écritures viennent des thèmes installés.
MANQUE=""
for N in drive-harddisk drive-harddisk-system drive-harddisk-scsi \
         drive-harddisk-ieee1394 drive-multidisk harddisk \
         drive-removable-media drive-removable-media-usb \
         drive-removable-media-ieee1394 drive-harddisk-usb media-removable; do
	#  « -r » SUIT LE LIEN : un alias cassé répond non, et c'est voulu — un
	#  lien qui pointe dans le vide a l'air présent et ne l'est pas. C'est la
	#  faute que ce banc a déjà attrapée une fois, dans places/.
	[ -r "$DEV/$N.svg" ] || MANQUE="$MANQUE $N"
done
[ -z "$MANQUE" ] \
	&& ok "les onze écritures du disque et des supports amovibles sont là" \
	|| non "écritures ABSENTES ou liens cassés :$MANQUE"

#  DEUX DESSINS ET NON UN. Les confondre ferait passer une clé USB pour un
#  disque dur — et personne ne s'en apercevrait avant une photo.
if [ -r "$DEV/drive-harddisk.svg" ] && [ -r "$DEV/drive-removable-media.svg" ]; then
	if cmp -s "$DEV/drive-harddisk.svg" "$DEV/drive-removable-media.svg"; then
		non "le disque et la clé USB sont le MÊME dessin"
	else
		ok "le disque interne et les supports amovibles ont chacun leur dessin"
	fi
fi

#  ET CE SONT BIEN LES DESSINS DE LexOS, pas des copies qui ont divergé.
for PAIRE in "drive-harddisk:icon-disque" "drive-removable-media:icon-usb"; do
	CIBLE="$DEV/${PAIRE%%:*}.svg"; SRC="$RACINE/branding/${PAIRE#*:}.svg"
	if [ -r "$CIBLE" ] && [ -r "$SRC" ]; then
		cmp -s "$CIBLE" "$SRC" \
			&& ok "${PAIRE%%:*} est bien ${PAIRE#*:}.svg, au fichier près" \
			|| non "${PAIRE%%:*} a divergé de branding/${PAIRE#*:}.svg"
	else
		non "${PAIRE%%:*} ou branding/${PAIRE#*:}.svg est introuvable"
	fi
done

#  ON NE DÉTOURNE PAS LES « -symbolic ». Ce sont des traits monochromes pour
#  les barres d'outils : y poser un dessin en couleur ferait une tache dans
#  une rangée d'icônes au trait. Et « drive-optical » est un disque OPTIQUE,
#  pas un disque dur — l'héritage fait mieux que nous.
INTRUS=""
for N in "$DEV"/*-symbolic.svg "$DEV"/drive-optical*.svg; do
	[ -e "$N" ] && INTRUS="$INTRUS $(basename "$N")"
done
[ -z "$INTRUS" ] \
	&& ok "aucun « -symbolic » ni « drive-optical » détourné — l'héritage les garde" \
	|| non "dessins en couleur posés là où il faut du trait :$INTRUS"

#  ET LE HOOK LES REND EN PNG. Un SVG seul a besoin de librsvg branché dans
#  gdk-pixbuf ; c'est précisément ce qui a manqué pendant trois ISO.
HOOK="$RACINE/config/hooks/normal/0605-lexos-icones.hook.chroot"
if grep -q "for CAT in apps devices" < <(sed 's/#.*$//' "$HOOK"); then
	ok "le hook 0605 rend aussi les PNG de « devices »"
else
	non "le hook ne rend pas les PNG des périphériques — le SVG seul peut ne pas s'afficher"
fi

# =============================================================================
titre "6. GTK reconnaît nos SVG comme des images"
# =============================================================================
#  ALEX, 13 SEPTEMBRE : « le répertoire personnel et le système de fichiers,
#  on voit plus l'image sur le bureau ». lexos-dev-sync avait recopié
#  l'index.theme du dépôt (SVG seulement) par-dessus celui du hook (PNG
#  déclarés) : GTK n'avait plus que les SVG — et les refusait TOUS, « format
#  d'image non reconnu ». rsvg-convert, lui, les rendait sans broncher.
#
#  LA CAUSE : gdk-pixbuf devine le format d'après les premiers octets, et
#  l'en-tête de commentaire posé AVANT « <svg » l'empêchait de reconnaître un
#  SVG. Le commentaire vit donc JUSTE APRÈS la balise ouvrante. On éprouve la
#  forme (sans dépendre de GTK en CI) et, si gdk-pixbuf est là, le chargement.
MAUVAIS=""
for F in "$THEME"/*/scalable/*.svg; do
	[ -L "$F" ] && continue
	python3 - "$F" <<'PY' || MAUVAIS="$MAUVAIS ${F#"$THEME"/}"
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r"^\s*<\?xml[^>]*\?>\s*", "", s)
sys.exit(0 if s.startswith("<svg") else 1)
PY
done
[ -z "$MAUVAIS" ] \
	&& ok "aucun SVG n'a de commentaire avant « <svg » — gdk-pixbuf les reconnaît" \
	|| non "« <svg » n'ouvre pas le fichier, GTK dira « format non reconnu » :$MAUVAIS"

#  ═══ CE CONTRÔLE SE SAUTAIT EN SILENCE, ET C'EST LUI QUI COMPTE ═══
#  C'est le seul qui éprouve le VRAI symptôme : gdk-pixbuf refusant le
#  fichier. Il était gardé par « python3 -c import gi » et, quand ça ratait,
#  il ne s'affichait pas du tout — pas une ligne, pas un gris. Mesuré :
#  29 contrôles sur la machine d'Alex, 28 ici, et rien pour dire lequel
#  manquait ni pourquoi.
#
#  Ici, « python3 » est un 3.11 local alors que le paquet Debian livre son
#  module compilé pour 3.12 : l'import échoue sur un décalage de version, pas
#  sur une absence. On cherche donc un interpréteur QUI SAIT, au lieu de
#  supposer que c'est celui du PATH — et s'il n'y en a aucun, on le DIT.
PY_GI=""
for CANDIDAT in python3 /usr/bin/python3 python3.13 python3.12 python3.11; do
	command -v "$CANDIDAT" >/dev/null 2>&1 || continue
	if "$CANDIDAT" -c "import gi; gi.require_version('GdkPixbuf','2.0'); from gi.repository import GdkPixbuf" 2>/dev/null; then
		PY_GI="$CANDIDAT"; break
	fi
done
if [ -z "$PY_GI" ]; then
	gris "gdk-pixbuf injoignable (paquets python3-gi / gir1.2-gdkpixbuf-2.0) : le chargement des SVG n'est PAS mesuré"
else
	REFUS="$("$PY_GI" - "$THEME" <<'PY'
import glob, os, sys, gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*/scalable/*.svg"))):
    try:
        GdkPixbuf.Pixbuf.new_from_file_at_size(f, 64, 64)
    except Exception:
        print(os.path.relpath(f, sys.argv[1]), end=" ")
PY
)"
	[ -z "$REFUS" ] \
		&& ok "gdk-pixbuf ($PY_GI) charge chaque SVG du thème, comme le bureau et Thunar" \
		|| non "gdk-pixbuf refuse : $REFUS"
fi

# =============================================================================
titre "7. Une mise à jour à chaud ne rend plus le bureau aveugle"
# =============================================================================
#  LA SECTION 6 SOIGNE LE SYMPTÔME, CELLE-CI LA CAUSE. Les SVG reconnus, il
#  reste que lexos-dev-sync et lexos-mise-a-jour recopiaient l'index.theme du
#  dépôt (scalable seulement) sur celui que le hook 0605 avait réécrit avec
#  ses PNG. Les deux outils sautent désormais ce fichier et rejouent le hook.
#
#  On monte donc la machine telle que la construction la laisse — thème du
#  dépôt, un dossier de PNG, index.theme qui le déclare — on change un dessin
#  dans le clone, et on exige qu'après le passage les PNG soient ENCORE
#  déclarés. Le vrai hook tourne : c'est lui qui répare, c'est lui qu'on
#  éprouve. Sans rsvg-convert il ne rend rien, mais énumère toujours le disque.
BANC7="$(mktemp -d)"
trap 'rm -rf "$BANC7"' EXIT
HOOK="$RACINE/config/hooks/normal/0605-lexos-icones.hook.chroot"

monte7() { # monte7 <dossier> — un clone et un système neufs
	local C="$1/clone" S="$1/systeme"
	mkdir -p "$C/config/includes.chroot/usr/share/icons" "$C/config/hooks/normal" \
	         "$S/usr/share/icons" "$S/etc/lexos"
	: > "$C/lexos.conf"
	cp -a "$THEME" "$C/config/includes.chroot/usr/share/icons/"
	cp "$HOOK" "$C/config/hooks/normal/"
	cp -a "$THEME" "$S/usr/share/icons/"
	#  Ce que la construction laisse : des PNG, et un index.theme qui les nomme.
	mkdir -p "$S/usr/share/icons/LexOS/places/48x48"
	cp "$S/usr/share/icons/LexOS/places/scalable/folder.svg" "$S/usr/share/icons/LexOS/places/48x48/folder.png"
	LEXOS_ICONES="$S/usr/share/icons/LexOS" LEXOS_RAPPORT_ICONES="$S/etc/lexos/icones-report" \
		LEXOS_APPS_LOCAL="$S/usr/local/share/applications" sh "$HOOK" >/dev/null 2>&1
	#  Un dessin qui change dans le clone : le déclencheur d'une vraie mise à jour.
	printf '<!-- retouche -->\n' >> "$C/config/includes.chroot/usr/share/icons/LexOS/places/scalable/folder.svg"
}

declare_png() { grep -q '^Directories=.*places/48x48' "$1/systeme/usr/share/icons/LexOS/index.theme" 2>/dev/null; }

for OUTIL7 in lexos-mise-a-jour lexos-dev-sync; do
	D7="$BANC7/$OUTIL7"
	monte7 "$D7"
	if ! declare_png "$D7"; then
		non "$OUTIL7 : le banc n'a pas su monter une machine avec ses PNG déclarés"
		continue
	fi
	lance7() {
		NO_COLOR=1 LEXOS_MAJ_DEST="$D7/systeme" LEXOS_MAJ_ETC="$D7/systeme/etc/lexos" \
			LEXOS_MAJ_SRC_DEFAUT="$D7/nulle-part" LEXOS_DEV_SYNC_DEST="$D7/systeme" \
			bash "$RACINE/config/includes.chroot/usr/bin/$OUTIL7" --depuis "$D7/clone" "$@" 2>&1
	}

	AVANT7="$(md5sum "$D7/systeme/usr/share/icons/LexOS/index.theme")"
	lance7 --essai >/dev/null
	[ "$AVANT7" = "$(md5sum "$D7/systeme/usr/share/icons/LexOS/index.theme")" ] \
		&& ok "$OUTIL7 --essai laisse index.theme intact" \
		|| non "$OUTIL7 --essai a touché index.theme"

	SORTIE7="$(lance7)"
	if declare_png "$D7"; then
		ok "$OUTIL7 : après le passage, les PNG sont TOUJOURS déclarés"
	else
		non "$OUTIL7 a rendu les PNG invisibles — les icônes du bureau redeviennent blanches"
	fi
	if ls "$D7/systeme/usr/share/icons/LexOS/"index.theme.lexos-bak-* >/dev/null 2>&1; then
		non "$OUTIL7 a encore recopié l'index.theme du dépôt (une sauvegarde en témoigne)"
	else
		ok "$OUTIL7 ne recopie pas l'index.theme du dépôt"
	fi
	grep -q 'hook 0605 rejoué' <<< "$SORTIE7" \
		&& ok "$OUTIL7 rejoue le hook 0605 quand un dessin change" \
		|| non "$OUTIL7 n'a pas rejoué le hook 0605 — les PNG gardent l'ancien dessin"
done

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' \
	"$reussis" "$echoues" "$nonmesure"

#  EN CI, RIEN NE RESTE « NON MESURÉ ». Une ligne grise dans un journal de
#  deux cents étapes ne se voit pas ; la variable en fait un échec franc.
[[ "$echoues" -eq 0 ]] || exit 1
if [[ "${LEXOS_ICONES_EXIGER_MESURE:-0}" == "1" && "$nonmesure" -gt 0 ]]; then
	printf '\033[31m  LEXOS_ICONES_EXIGER_MESURE=1 : %d contrôle(s) non mesuré(s).\033[0m\n' "$nonmesure"
	exit 1
fi
exit 0
