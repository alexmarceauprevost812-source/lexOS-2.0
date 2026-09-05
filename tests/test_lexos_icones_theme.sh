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

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
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

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
