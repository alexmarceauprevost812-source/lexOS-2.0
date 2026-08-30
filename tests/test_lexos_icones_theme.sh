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
if printf '%s' "$HERITE" | grep -q 'hicolor'; then
	ok "« hicolor » ferme la chaîne — le dernier recours de la spécification"
else
	non "« hicolor » absent : les icônes propres aux applications seraient perdues"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
