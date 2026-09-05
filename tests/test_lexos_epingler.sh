#!/usr/bin/env bash
# =============================================================================
#  Épingler une application au dock, d'un clic droit
# =============================================================================
#  ALEX, photo du clic droit sur une icône du bureau : « on voit pas
#  "épingler" pour le mettre sur le dock ». Le menu proposait Exécuter,
#  Modifier le lanceur, Ouvrir avec, Couper, Copier, Corbeille, Renommer,
#  Créer une archive, Propriétés — et rien pour dire « garde-la sous la main ».
#
#  ═══ CE QU'IL FAUT SAVOIR SUR LE DOCK ═══
#  Plank ne lit pas une liste dans un réglage : chaque icône épinglée est un
#  petit fichier « .dockitem » dans ~/.config/plank/dock1/launchers. Plank
#  surveille ce dossier — c'est exactement ce qu'il fait lui-même quand on
#  glisse une application dessus. On écrit le fichier, le dock suit.
#
#  ═══ LE PIÈGE QUE CE BANC SURVEILLE ═══
#  L'icône du bureau est un .desktop posé dans ~/Bureau. L'épingler TEL QUEL
#  marche… jusqu'au jour où Alex efface l'icône du bureau : le dock garde un
#  lanceur mort, et il faut aller chercher pourquoi. Quand le même nom existe
#  au catalogue des applications, c'est CELUI-LÀ qu'il faut épingler.
#  Ce contrôle-là ne se voit pas à la lecture du code — il se voit en donnant
#  à l'outil une icône de bureau et en regardant ce qu'il écrit.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-epingler"
UCA="$RACINE/config/includes.chroot/etc/skel/.config/Thunar/uca.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

prepare() {
	rm -rf "${BANC:?}/d"
	mkdir -p "$BANC/d/lanceurs" "$BANC/d/apps" "$BANC/d/bureau"
	printf '[Desktop Entry]\nType=Application\nName=Google Chrome\nExec=google-chrome\n' \
		> "$BANC/d/apps/google-chrome.desktop"
	cp "$BANC/d/apps/google-chrome.desktop" "$BANC/d/bureau/google-chrome.desktop"
	printf '[Desktop Entry]\nType=Application\nName=Mon script\nExec=/truc.sh\n' \
		> "$BANC/d/bureau/mon-script.desktop"
	: > "$BANC/d/bureau/photo.jpg"
}
lance() { LEXOS_PLANK="$BANC/d/lanceurs" LEXOS_APPS_DIRS="$BANC/d/apps" bash "$OUTIL" "$@" 2>&1; }
items() { ls "$BANC/d/lanceurs"/*.dockitem 2>/dev/null | wc -l; }
vise()  { sed -n 's|^Launcher=file://||p' "$BANC/d/lanceurs"/*.dockitem 2>/dev/null; }

# =============================================================================
titre "1. Le fichier écrit est celui que Plank sait lire"
# =============================================================================
prepare
SORTIE="$(lance "$BANC/d/bureau/google-chrome.desktop")"
if [[ "$(items)" == "1" ]]; then
	ok "un .dockitem est écrit"
else
	non "$(items) fichier(s) écrit(s) au lieu d'un : $SORTIE"
fi
F="$(ls "$BANC/d/lanceurs"/*.dockitem 2>/dev/null | head -1)"
if [[ -n "$F" ]] && grep -qx '\[PlankDockItemPreferences\]' < <(head -1 "$F"); then
	ok "il porte l'en-tête que Plank attend"
else
	non "en-tête absent ou faux — Plank ignorerait le fichier"
fi
if [[ -n "$F" ]] && grep -q '^Launcher=file:///' "$F"; then
	ok "et un Launcher en URI absolue"
else
	non "le Launcher n'est pas une URI absolue : Plank ne le suivrait pas"
fi
#  LE NOM DU FICHIER SE RELIT. Un dossier de « 50-a3f9.dockitem » ne se
#  débrouille pas à la main le jour où il faut y faire le ménage.
if [[ "$(basename "$F")" == *google-chrome* ]]; then
	ok "le nom du fichier porte celui de l'application ($(basename "$F"))"
else
	non "le fichier s'appelle « $(basename "$F") » : illisible à la main"
fi

# =============================================================================
titre "2. LE PIÈGE : on épingle le lanceur du SYSTÈME, pas la copie du bureau"
# =============================================================================
#  Sans ça, effacer l'icône du bureau laisserait un lanceur mort sur le dock.
CIBLE="$(vise)"
if [[ "$CIBLE" == "$BANC/d/apps/google-chrome.desktop" ]]; then
	ok "l'icône du bureau épingle le lanceur du catalogue — il survit au ménage"
elif [[ "$CIBLE" == "$BANC/d/bureau/google-chrome.desktop" ]]; then
	non "c'est la copie du BUREAU qui est épinglée : effacer l'icône casserait le dock"
else
	non "cible inattendue : $CIBLE"
fi
#  ET L'INVERSE : un lanceur qui n'existe QUE sur le bureau doit être épinglé
#  tel quel, sinon on refuserait d'épingler les scripts d'Alex.
prepare
lance "$BANC/d/bureau/mon-script.desktop" >/dev/null
if [[ "$(vise)" == "$BANC/d/bureau/mon-script.desktop" ]]; then
	ok "un lanceur absent du catalogue est épinglé tel quel"
else
	non "un lanceur personnel n'est pas épinglé : « $(vise) »"
fi

# =============================================================================
titre "3. Deux fois, et ce qui n'est pas une application"
# =============================================================================
prepare
lance "$BANC/d/bureau/google-chrome.desktop" >/dev/null
SORTIE2="$(lance "$BANC/d/bureau/google-chrome.desktop")"
if [[ "$(items)" == "1" ]]; then
	ok "épingler deux fois n'ajoute pas un doublon"
else
	non "$(items) fichiers après deux épinglages : le dock aurait l'icône en double"
fi
if grep -qi 'déjà' <<< "$SORTIE2" ; then
	ok "…et il le DIT au lieu de faire semblant"
else
	non "il ne dit rien : on cliquerait à nouveau sans savoir"
fi
prepare
SORTIE3="$(lance "$BANC/d/bureau/photo.jpg")"; CODE3=$?
if [[ "$CODE3" -ne 0 && "$(items)" == "0" ]]; then
	ok "une image n'est pas épinglée, et le refus se voit dans le code de sortie"
else
	non "une image a été épinglée, ou l'échec est passé pour un succès"
fi
if grep -qi "n'est pas une application" <<< "$SORTIE3" ; then
	ok "…avec un message qui dit pourquoi"
else
	non "refus muet : « $SORTIE3 »"
fi

# =============================================================================
titre "4. Retirer, et lister"
# =============================================================================
prepare
lance "$BANC/d/bureau/google-chrome.desktop" >/dev/null
lance "$BANC/d/bureau/mon-script.desktop" >/dev/null
if [[ "$(vise | grep -c .)" == "2" ]]; then
	ok "deux applications épinglées"
else
	non "attendu 2 épinglées, vu $(vise | grep -c .)"
fi
lance --enlever "$BANC/d/bureau/google-chrome.desktop" >/dev/null
#  ON RETIRE PAR L'ICÔNE DU BUREAU alors que c'est le lanceur du CATALOGUE
#  qui est épinglé : les deux chemins doivent se rejoindre, sinon on ne
#  pourrait plus retirer ce qu'on vient d'ajouter.
if [[ "$(vise | grep -c .)" == "1" && "$(vise)" == *mon-script* ]]; then
	ok "retirer par l'icône du bureau retire bien l'entrée du catalogue"
else
	non "le retrait n'a pas trouvé l'entrée : reste « $(vise) »"
fi
if grep -q 'mon-script' < <(lance --liste); then
	ok "la liste montre ce qui reste"
else
	non "la liste ne montre pas ce qui est épinglé"
fi
#  Sans dock du tout, l'outil ne doit pas planter en silence.
rm -rf "$BANC/d/lanceurs"
if grep -qi 'rien sur le dock' < <(lance --liste); then
	ok "sans dock installé, il le dit au lieu de rendre une liste vide muette"
else
	non "sans dock, la sortie ne dit rien"
fi

# =============================================================================
titre "5. Trois chemins y mènent"
# =============================================================================
#  Le clic droit est celui qu'Alex a demandé, nommément. Les deux autres sont
#  la discipline du dépôt : le contrôle 16 les réclame.
if grep -q 'lexos-epingler %F' "$UCA"; then
	ok "le clic droit propose « Épingler au dock »"
else
	non "aucune action de clic droit — la demande d'Alex n'est pas remplie"
fi
if python3 - "$UCA" <<'PY'
import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
for a in r.findall("action"):
    if "lexos-epingler" in (a.findtext("command") or ""):
        #  Sans motif « *.desktop », l'action s'afficherait sur TOUT fichier —
        #  y compris ceux qu'elle refuse ensuite. Un menu qui propose ce qu'il
        #  ne sait pas faire, c'est pire que pas de menu.
        sys.exit(0 if (a.findtext("patterns") or "") == "*.desktop" else 1)
sys.exit(1)
PY
then
	ok "…et seulement sur les applications (*.desktop)"
else
	non "l'action s'afficherait sur n'importe quel fichier"
fi
#  Les identifiants doivent rester uniques : Thunar en écarte un en SILENCE.
if python3 -c "
import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
ids = [a.findtext('unique-id') for a in r.findall('action')]
sys.exit(0 if len(ids) == len(set(ids)) else 1)" "$UCA" 2>/dev/null; then
	ok "les identifiants des actions restent uniques"
else
	non "deux actions partagent un identifiant : Thunar en écartera une en silence"
fi
grep -qE '^\s*epingler\|' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos epingler » existe" \
	|| non "le dispatcheur ne connaît pas « epingler »"
grep -q '"dock-epingles":' "$RACINE/config/includes.chroot/usr/lib/lexos/settings.py" \
	&& ok "Paramètres sait montrer ce qui est épinglé" \
	|| non "aucun chemin depuis les Paramètres"
grep -q "ouvrir('dock-epingles')" "$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js" \
	&& ok "…et la page porte le bouton" \
	|| non "le moteur a l'action mais la page n'a pas de bouton : action morte"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
