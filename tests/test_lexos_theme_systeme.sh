#!/usr/bin/env bash
# =============================================================================
#  LexOS-Noir — le style de LexOS devient un VRAI THÈME
# =============================================================================
#  ALEX : « les thèmes des applications, on peut-tu faire que ça soit pas trop
#  compliqué et que ça reste tout officiel normal, pour pas avoir à changer les
#  couleurs et tout le kit sur chaque appli. »
#
#  ═══ POURQUOI IL A RAISON ═══
#  Le style de LexOS partait dans ~/.config/gtk-3.0/gtk.css, que GTK charge en
#  priorité UTILISATEUR — la plus forte qui existe. Il écrasait le thème de
#  base ET chaque application par-dessus. D'où, dans le seul mois écoulé :
#  l'icône du bureau peinte en noir alors que xfdesktop la veut transparente,
#  le dossier de Thunar réduit à une silhouette noire, la Logithèque qu'il a
#  fallu convaincre à part. Chaque fois : une règle sur mesure pour CETTE
#  application.
#
#  ═══ CE QUE CE BANC TIENT ═══
#  ÉTAPE 1 : le thème existe, se charge, et rend EXACTEMENT ce que rend la
#  pile actuelle. Tant que cette égalité n'est pas tenue, on ne retire pas la
#  feuille utilisateur. Le banc la mesure sur un vrai GTK 3.24 — il ne compare
#  pas des fichiers, il compare des COULEURS RÉSOLUES, la seule chose qui
#  décide de ce qu'on voit.
#
#  Une règle qui gagnait par PRIORITÉ ne gagne plus que par SPÉCIFICITÉ : ce
#  banc est là pour nommer celles qui tombent. Il en a déjà trouvé une —
#  l'infobulle, noire par accident via « .background », que le « tooltip.
#  background » d'Arc reprenait dès qu'on descendait d'un rang.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
HOOK="$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
	bash "$GEN" --target "$BANC/t" --terminal nuit orange >"$BANC/gen.log" 2>&1
TH="$BANC/t/.themes/LexOS-Noir"

# =============================================================================
titre "1. Le thème est là, et complet"
# =============================================================================
for F in index.theme gtk-3.0/gtk.css gtk-4.0/gtk.css; do
	[ -r "$TH/$F" ] && ok "$F produit" || non "$F MANQUE"
done
grep -q "^GtkTheme=LexOS-Noir" "$TH/index.theme" 2>/dev/null \
	&& ok "index.theme se nomme lui-même LexOS-Noir" \
	|| non "index.theme ne déclare pas GtkTheme=LexOS-Noir"

# =============================================================================
titre "2. La ressource du thème de base est ATTEIGNABLE"
# =============================================================================
#  ═══ LE PIÈGE, MESURÉ AVANT D'ÉCRIRE UNE LIGNE ═══
#  Le gtk.css d'Arc-Dark n'est PAS une feuille de style : c'est une seule
#  ligne qui pointe vers une ressource COMPILÉE, que GTK n'enregistre que
#  lorsqu'il charge Arc PAR SON NOM. Un thème qui importerait ce fichier par
#  son chemin obtient « Failed to import: The resource does not exist » — et
#  un bureau NU, sans en-tête ni sélection, l'avertissement perdu dans le
#  journal. La ressource doit être posée À CÔTÉ de notre feuille.
BASE="${LEXOS_THEMES_SYS:-/usr/share/themes}/Arc-Dark"
if [ ! -d "$BASE" ]; then
	saut "Arc-Dark absent de cette machine : le lien n'a PAS été vérifié"
else
	for V in gtk-3.0 gtk-4.0; do
		L="$TH/$V/gtk.gresource"
		if [ ! -L "$L" ]; then
			non "$V : aucun lien vers la ressource du thème de base"
		elif [ ! -r "$L" ]; then
			non "$V : le lien vers la ressource est CASSÉ ($(readlink "$L"))"
		else
			ok "$V : la ressource du thème de base est atteignable"
		fi
	done
	#  ET L'ADRESSE N'EST PAS DEVINÉE : elle est recopiée du thème de base.
	ATTENDU="$(grep -E '^[[:space:]]*@import' "$BASE/gtk-3.0/gtk.css" 2>/dev/null | head -1)"
	VU="$(grep -E '^[[:space:]]*@import' "$TH/gtk-3.0/gtk.css" 2>/dev/null | head -1)"
	if [ -n "$ATTENDU" ] && [ "$VU" = "$ATTENDU" ]; then
		ok "l'adresse de la ressource est RECOPIÉE du thème de base, pas inventée"
	else
		non "import attendu « $ATTENDU », vu « $VU »"
	fi
fi

# =============================================================================
titre "3. LE CŒUR — le thème seul rend les couleurs de la palette"
# =============================================================================
#  ═══ CE QUE CE CONTRÔLE MESURAIT AVANT, ET POURQUOI IL A CHANGÉ ═══
#  À l'étape 1, il comparait DEUX montages : la feuille utilisateur (priorité
#  UTILISATEUR) contre le thème seul. Il exigeait zéro différence, et c'est
#  ainsi qu'on a su qu'on pouvait retirer la feuille sans rien casser — il a
#  d'ailleurs trouvé la seule règle qui tombait, l'infobulle.
#
#  La feuille utilisateur n'existe plus. Comparer le thème à elle n'aurait
#  plus aucun sens : il ne resterait qu'un banc vert parce qu'il ne mesure
#  rien. On compare donc le thème à la SOURCE DE VÉRITÉ — les variables de
#  palette de lexos-theme-gen. Non circulaire : d'un côté ce que le
#  générateur DIT vouloir, de l'autre ce que GTK rend VRAIMENT.
#
#  ON N'ÉPLUCHE PAS LES COMMENTAIRES pour lire ces variables : « sed
#  s/#.*$// » mangerait le « # » des couleurs elles-mêmes, et tous les motifs
#  deviendraient vides. On ancre l'affectation en début de ligne — une ligne
#  de commentaire commence par « # », donc ce qui est ancré ainsi est du code.
palette() { # palette <nom> -> la valeur de nuit
	awk -v k="$1" '
		/^else$/          { nuit = 1 }
		/^fi$/            { nuit = 0 }
		nuit && $0 ~ "^[ \t]*" k "=\"#" {
			sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit
		}' "$GEN"
}
BG="$(palette BG)"; HEADER="$(palette HEADER)"; FG="$(palette FG)"
BG_ALT="$(palette BG_ALT)"
ACCENT="#E8590C"          # l'accent orange, celui que le banc demande
GRILLE="$(grep -m1 '^SEL_GRILLE="#' "$GEN" | sed 's/^[^"]*"//; s/".*$//')"

if [ -z "$BG" ] || [ -z "$HEADER" ] || [ -z "$GRILLE" ]; then
	non "impossible de relire la palette dans lexos-theme-gen (BG=$BG HEADER=$HEADER GRILLE=$GRILLE)"
else
	ok "palette relue : fond $BG · en-tête $HEADER · grille $GRILLE"
fi

PY=""
for C in python3.12 python3.13 python3.11 python3; do
	command -v "$C" >/dev/null 2>&1 || continue
	"$C" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null \
		&& { PY="$C"; break; }
done
if [ -z "$PY" ]; then
	saut "aucun python avec GTK 3 : les couleurs n'ont PAS été mesurées"
elif [ ! -d "$BASE" ]; then
	saut "Arc-Dark absent : les couleurs n'ont PAS été mesurées"
else
	cat > "$BANC/mes.py" <<'PY'
import sys, warnings, gi
warnings.filterwarnings("ignore")
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GObject
ecran = Gdk.Screen.get_default()
if ecran is None:
    print("PAS-D-ECRAN"); sys.exit(0)
st = Gtk.Settings.get_default()
st.set_property("gtk-theme-name", "LexOS-Noir")
st.set_property("gtk-application-prefer-dark-theme", True)
F = Gtk.StateFlags
def hexa(c): return "#%02X%02X%02X" % (round(c.red*255), round(c.green*255), round(c.blue*255))
def couleur(nom, classes, etat, quoi):
    w = Gtk.WidgetPath(); w.append_type(GObject.TYPE_NONE); w.iter_set_object_name(-1, nom)
    for c in classes: w.iter_add_class(-1, c)
    ctx = Gtk.StyleContext(); ctx.set_screen(ecran); ctx.set_path(w); ctx.set_state(etat)
    return hexa(ctx.get_background_color(etat) if quoi == "bg" else ctx.get_color(etat))
CAS = [
 ("fenetre",         "window",    ["background"], F.NORMAL,   "bg"),
 ("fenetre-texte",   "window",    ["background"], F.NORMAL,   "fg"),
 ("en-tete",         "headerbar", ["titlebar"],   F.NORMAL,   "bg"),
 ("vue-repos",       "treeview",  ["view"],       F.NORMAL,   "bg"),
 ("liste-choisie",   "treeview",  ["view"],       F.SELECTED, "bg"),
 ("grille-choisie",  "iconview",  ["view"],       F.SELECTED, "bg"),
 ("thunar-choisi",   "ExoIconView", ["view"],     F.SELECTED, "bg"),
 ("bureau-choisi",   "XfdesktopIconView", ["view"], F.ACTIVE, "bg"),
 ("menu",            "menu",      [],             F.NORMAL,   "bg"),
 ("infobulle",       "tooltip",   ["background"], F.NORMAL,   "bg"),
 ("selection-texte", "selection", [],             F.NORMAL,   "bg"),
]
for nom, n, cl, fl, q in CAS:
    print("%s\t%s" % (nom, couleur(n, cl, fl, q)))
PY
	mkdir -p "$BANC/home/.themes"
	cp -r "$TH" "$BANC/home/.themes/"
	HOME="$BANC/home" "$PY" "$BANC/mes.py" > "$BANC/vu.txt" 2>/dev/null
	if grep -q "PAS-D-ECRAN" "$BANC/vu.txt" 2>/dev/null; then
		saut "aucun écran X (relancer sous « xvfb-run ») : rien n'a été MESURÉ"
	elif [ ! -s "$BANC/vu.txt" ]; then
		non "la mesure n'a rien rendu"
	else
		val() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$BANC/vu.txt"; }
		verifie() { # verifie <clé> <attendu> <ce que ça veut dire>
			local v; v="$(val "$1")"
			[ "$v" = "$2" ] && ok "$3 : $2" || non "$3 : attendu $2, rendu $v"
		}
		verifie fenetre        "$BG"      "le fond des fenêtres est le noir de LexOS"
		verifie fenetre-texte  "$FG"      "l'écriture des fenêtres"
		verifie en-tete        "$HEADER"  "le haut des fenêtres est le gris choisi par Alex"
		verifie vue-repos      "$BG"      "une vue au repos"
		verifie liste-choisie  "$ACCENT"  "une ligne de liste choisie garde l'accent"
		verifie grille-choisie "$GRILLE"  "la grille d'applications prend le gris pâle"
		verifie thunar-choisi  "$GRILLE"  "le dossier choisi dans Thunar aussi"
		verifie bureau-choisi  "$ACCENT"  "l'icône choisie du bureau garde l'accent plein"
		verifie menu           "$BG_ALT"  "les menus"
		verifie infobulle      "$BG"      "l'infobulle, dite exprès depuis l'étape 1"
		verifie selection-texte "$ACCENT" "la sélection de texte"
	fi
fi

# =============================================================================
titre "3 bis. La feuille utilisateur n'est PLUS écrite"
# =============================================================================
#  C'EST TOUT L'OBJET DE L'ÉTAPE 4. Tant qu'un ~/.config/gtk-3.0/gtk.css
#  existe, il est chargé en priorité UTILISATEUR et écrase de nouveau les
#  applications — on aurait fait le tour complet pour revenir au point de
#  départ. Le banc l'interdit.
DEBORDE=""
for V in 3 4; do
	[ -e "$BANC/t/.config/gtk-${V}.0/gtk.css" ] && DEBORDE="$DEBORDE gtk-${V}.0"
done
[ -z "$DEBORDE" ] \
	&& ok "aucune feuille en priorité utilisateur — les applications gardent leur dessin" \
	|| non "une feuille est encore écrite ($DEBORDE) : elle réécraserait les applications"

# =============================================================================
titre "3 ter. RIEN sous etc/skel/.config ne peut redevenir prioritaire"
# =============================================================================
#  ═══ LE PIÈGE QUI A FAILLI PARTIR DANS UNE ISO ═══
#  Le squelette du panneau vivait dans includes.chroot/etc/skel/.config/
#  gtk-3.0/gtk.css. Tant que la feuille de LexOS était elle-même un fichier
#  d'utilisateur, ça se tenait. Depuis l'étape 4, NON : tout ce qui est sous
#  /etc/skel/.config arrive dans le ~/.config de chaque compte, où GTK le
#  charge en priorité UTILISATEUR. Ce fichier de 14 kio aurait rendu aux
#  applications, sur la VRAIE machine, le poids qu'on venait de leur retirer.
#
#  ET AUCUN BANC NE L'AURAIT VU : ils travaillent tous dans un foyer neuf,
#  où /etc/skel n'est jamais recopié. Vert partout, cassé chez Alex — le
#  défaut exact que ce dépôt se répète. Trouvé par un balayage avant de
#  pousser, pas par un banc ; celui-ci existe pour que ce soit un banc la
#  prochaine fois.
IC="$RACINE/config/includes.chroot"
DEBORDE=""
for F in "$IC/etc/skel/.config/gtk-3.0/gtk.css" "$IC/etc/skel/.config/gtk-4.0/gtk.css"; do
	[ -e "$F" ] && DEBORDE="$DEBORDE ${F#"$IC/"}"
done
[ -z "$DEBORDE" ] \
	&& ok "l'ISO ne livre aucun gtk.css sous etc/skel/.config" \
	|| non "livré dans /etc/skel :$DEBORDE — chaque compte le recevrait en priorité utilisateur"

#  Et le squelette du panneau est bien là où il doit être : une ENTRÉE.
[ -r "$IC/usr/share/lexos/gtk-panneau.css" ] \
	&& ok "le squelette du panneau est une entrée (/usr/share/lexos), pas un fichier d'utilisateur" \
	|| non "gtk-panneau.css introuvable — le style du panneau serait perdu"

# =============================================================================
titre "3 quater. Le thème de base RETENU arrive jusqu'au générateur"
# =============================================================================
#  arc-theme voyage dans les paquets OPTIONNELS. Le hook 0600 choisit donc le
#  premier thème sombre réellement présent — mais il l'exportait sous
#  « LEXOS_GTK_BASE_THEME » tandis que le générateur lisait
#  « LEXOS_GTK_BASE ». Deux noms voisins, jamais le même : le repli
#  n'arrivait pas. Sur une machine sans Arc-Dark on aurait pose un lien vers
#  une ressource ABSENTE — bureau NU, pour un avertissement dans le journal.
CODE_H="$(sed 's/#.*$//' "$HOOK")"
if printf '%s' "$CODE_H" | grep -q 'LEXOS_GTK_BASE_THEME="\$GTK_BASE"'; then
	ok "le hook passe le thème de base retenu À L'APPEL du générateur"
else
	non "le hook n'informe pas le générateur du thème de base : le repli n'arriverait pas"
fi

#  ET IL EN TIENT COMPTE : avec un autre thème de base, aucun lien mort.
rm -rf "$BANC/autre"; mkdir -p "$BANC/autre"
LEXOS_PANNEAU_CSS="$IC/usr/share/lexos/gtk-panneau.css" \
	LEXOS_GTK_BASE_THEME="ThemeQuiNexistePas" \
	bash "$GEN" --target "$BANC/autre" orange >/dev/null 2>&1
LIEN="$BANC/autre/.themes/LexOS-Noir/gtk-3.0/gtk.gresource"
if [ -L "$LIEN" ] && [ ! -r "$LIEN" ]; then
	non "un lien MORT est posé quand le thème de base manque"
else
	ok "thème de base absent : aucun lien mort posé"
fi
grep -q "^MetacityTheme=ThemeQuiNexistePas$" "$BANC/autre/.themes/LexOS-Noir/index.theme" 2>/dev/null \
	&& ok "le nom du thème de base retenu est bien repris dans index.theme" \
	|| non "index.theme ne reprend pas le thème de base qu'on lui a donné"

# =============================================================================
titre "3 quinquies. Le SOCLE a une clé à lui — et un thème ne se bâtit pas sur lui-même"
# =============================================================================
#  TROUVÉ AU BALAYAGE D'AVANT-ISO 103, PAS PAR UN BANC.
#  « LEXOS_GTK_BASE_THEME » servait à DEUX choses. À l'appel du hook 0600, il
#  nomme le socle — le thème sur lequel LexOS-Noir est construit. Dans
#  /etc/lexos/build.conf, la MÊME clé porte le thème que la session doit
#  afficher, « LexOS-Noir », parce que c'est ce que lexos-firstrun y lit pour
#  xfconf. Relire build.conf pour appeler le générateur revenait donc à lui
#  demander de bâtir LexOS-Noir SUR LexOS-Noir : mesuré, une feuille sans
#  @import et sans ressource — un thème sans socle, et pas une ligne de
#  journal.
#
#  Ça ne cassait rien AUJOURD'HUI, par chance et non par construction :
#  firstrun lisait build.conf dans un sous-shell et n'exportait rien, donc le
#  générateur retombait sur son défaut. Mais ce défaut est « Arc-Dark », et
#  arc-theme voyage dans les paquets OPTIONNELS : sur une machine où il
#  manque, le hook avait choisi un autre socle, et la première session
#  rebâtissait le thème sur un Arc-Dark absent. ISO juste, premier démarrage
#  faux, silence complet.
#
#  C'est la faute « LEXOS_GTK_BASE / LEXOS_GTK_BASE_THEME » de l'ISO 102, une
#  ligne plus loin. Deux sens sous un nom.
FIRSTRUN="$IC/usr/bin/lexos-firstrun"
CODE_S="$(sed 's/#.*$//' "$HOOK")"

#  1. Le socle est retenu AVANT la bascule, comme les bordures de fenêtre.
L_SOC="$(grep -n 'GTK_SOCLE="\$GTK_BASE"' "$HOOK" | head -1 | cut -d: -f1)"
L_SW="$(grep -n 'GTK_BASE="\$THEME_LEXOS"' "$HOOK" | head -1 | cut -d: -f1)"
if [ -n "$L_SOC" ] && [ -n "$L_SW" ] && [ "$L_SOC" -lt "$L_SW" ]; then
	ok "le socle est retenu avant la bascule (ligne $L_SOC < $L_SW)"
else
	non "le socle n'est pas retenu avant la bascule : build.conf y mettrait « LexOS-Noir »"
fi

#  2. Et il part dans build.conf sous SA clé.
if printf '%s' "$CODE_S" | grep -q 'LEXOS_GTK_SOCLE=\${GTK_SOCLE}'; then
	ok "build.conf reçoit LEXOS_GTK_SOCLE — la première session saura sur quoi bâtir"
else
	non "le hook n'écrit pas le socle dans build.conf : firstrun retomberait sur Arc-Dark"
fi

#  3. firstrun le repasse au générateur — et ne lui donne PAS l'autre clé.
if [ -r "$FIRSTRUN" ]; then
	CODE_F="$(sed 's/#.*$//' "$FIRSTRUN")"
	if printf '%s' "$CODE_F" | grep -q 'LEXOS_GTK_SOCLE="\$SOCLE" lexos-theme-gen'; then
		ok "lexos-firstrun refabrique le thème sur le socle de la construction"
	else
		non "lexos-firstrun n'informe pas le générateur du socle : premier démarrage différent de l'ISO"
	fi
	if printf '%s' "$CODE_F" | grep -q 'LEXOS_GTK_BASE_THEME=.*lexos-theme-gen'; then
		non "lexos-firstrun passe LEXOS_GTK_BASE_THEME au générateur — il vaut « LexOS-Noir » dans build.conf"
	else
		ok "lexos-firstrun ne donne pas au générateur la clé qui porte « LexOS-Noir »"
	fi
else
	non "lexos-firstrun introuvable — la première session n'a pas pu être éprouvée"
fi

#  4. LA MESURE, pas la lecture : le socle donné est bien celui employé.
rm -rf "$BANC/socle"; mkdir -p "$BANC/socle"
LEXOS_PANNEAU_CSS="$IC/usr/share/lexos/gtk-panneau.css" LEXOS_GTK_SOCLE="Arc-Darker" \
	bash "$GEN" --target "$BANC/socle" orange >/dev/null 2>&1
if grep -q "^MetacityTheme=Arc-Darker$" "$BANC/socle/.themes/LexOS-Noir/index.theme" 2>/dev/null; then
	ok "LEXOS_GTK_SOCLE est bien la clé lue par le générateur"
else
	non "le générateur ignore LEXOS_GTK_SOCLE : la clé de firstrun n'arriverait nulle part"
fi

#  5. ET LE PIÈGE EST FERMÉ, quelle que soit la clé qui porte la valeur.
for CLE in LEXOS_GTK_SOCLE LEXOS_GTK_BASE_THEME; do
	rm -rf "$BANC/lui-meme"; mkdir -p "$BANC/lui-meme"
	env "$CLE=LexOS-Noir" LEXOS_PANNEAU_CSS="$IC/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/lui-meme" orange >/dev/null 2>&1
	F="$BANC/lui-meme/.themes/LexOS-Noir/gtk-3.0/gtk.css"
	if grep -q '@import' "$F" 2>/dev/null; then
		ok "« $CLE=LexOS-Noir » : le thème garde un socle au lieu de se bâtir sur lui-même"
	else
		non "« $CLE=LexOS-Noir » : thème SANS socle — ni @import ni ressource, en silence"
	fi
done

# =============================================================================
titre "4. Le hook ne déclare le thème que s'il EXISTE"
# =============================================================================
#  Écrire un nom de thème introuvable donne un bureau CLAIR par défaut, sans
#  qu'une ligne du journal ne le signale. C'est la faute que le garde-fou
#  d'Arc-Dark évite déjà vingt lignes plus haut ; celui-ci fait pareil.
CODE="$(sed 's/#.*$//' "$HOOK")"
if printf '%s' "$CODE" | grep -q '\-r "/etc/skel/.themes/${THEME_LEXOS}/gtk-3.0/gtk.css"'; then
	ok "le hook vérifie le FICHIER avant de déclarer le thème"
else
	non "le hook déclare LexOS-Noir sans vérifier qu'il est là"
fi

#  ET LES BORDURES DE FENÊTRE RESTENT CELLES DU THÈME DE BASE. LexOS-Noir est
#  une feuille de style : il ne fournit pas de xfwm4. Si XFWM_THEME était
#  calculé APRÈS la bascule, on chercherait « LexOS-Noir/xfwm4 », absent, et
#  toutes les fenêtres retomberaient sur les bordures grises de « Default ».
L_XFWM="$(grep -n 'XFWM_THEME="\$GTK_BASE"' "$HOOK" | head -1 | cut -d: -f1)"
L_BASC="$(grep -n 'GTK_BASE="\$THEME_LEXOS"' "$HOOK" | head -1 | cut -d: -f1)"
if [ -n "$L_XFWM" ] && [ -n "$L_BASC" ] && [ "$L_XFWM" -lt "$L_BASC" ]; then
	ok "les bordures de fenêtre sont choisies AVANT la bascule (ligne $L_XFWM < $L_BASC)"
else
	non "l'ordre est faux : les bordures chercheraient « LexOS-Noir/xfwm4 », qui n'existe pas"
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mLexOS-Noir est un vrai thème, et il rend ce que rendait la pile.\033[0m\n'
