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
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
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
titre "3. LE CŒUR — le thème seul rend ce que rend la pile actuelle"
# =============================================================================
PY=""
for C in python3.12 python3.13 python3.11 python3; do
	command -v "$C" >/dev/null 2>&1 || continue
	"$C" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null \
		&& { PY="$C"; break; }
done
if [ -z "$PY" ]; then
	saut "aucun python avec GTK 3 : l'égalité n'a PAS été mesurée"
	saut "c'est la partie qui compte : installer « python3-gi gir1.2-gtk-3.0 »"
elif [ ! -d "$BASE" ]; then
	saut "Arc-Dark absent : l'égalité n'a PAS été mesurée"
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
st.set_property("gtk-theme-name", sys.argv[1])
st.set_property("gtk-application-prefer-dark-theme", True)
if len(sys.argv) > 2 and sys.argv[2]:
    p = Gtk.CssProvider(); p.connect("parsing-error", lambda *a: None)
    try: p.load_from_path(sys.argv[2])
    except Exception as e: print("FEUILLE-REJETEE", e)
    Gtk.StyleContext.add_provider_for_screen(ecran, p, Gtk.STYLE_PROVIDER_PRIORITY_USER)
F = Gtk.StateFlags
def hexa(c): return "#%02X%02X%02X:%.2f" % (round(c.red*255), round(c.green*255),
                                            round(c.blue*255), c.alpha)
def couleur(nom, classes, etat, quoi):
    w = Gtk.WidgetPath(); w.append_type(GObject.TYPE_NONE); w.iter_set_object_name(-1, nom)
    for c in classes: w.iter_add_class(-1, c)
    ctx = Gtk.StyleContext(); ctx.set_screen(ecran); ctx.set_path(w); ctx.set_state(etat)
    return hexa(ctx.get_background_color(etat) if quoi == "bg" else ctx.get_color(etat))
#  Les pièces que quelqu'un REGARDE. Pas un échantillon au hasard : le fond,
#  l'en-tête, les trois sortes de sélection (liste, grille, Thunar), le bureau,
#  les menus, la saisie, les boutons, l'infobulle et la sélection de texte.
CAS = [
 ("fenetre",           "window",  ["background"], F.NORMAL,  "bg"),
 ("fenetre-texte",     "window",  ["background"], F.NORMAL,  "fg"),
 ("en-tete",           "headerbar", ["titlebar"], F.NORMAL,  "bg"),
 ("vue-repos",         "treeview", ["view"],      F.NORMAL,  "bg"),
 ("liste-choisie",     "treeview", ["view"],      F.SELECTED, "bg"),
 ("grille-choisie",    "iconview", ["view"],      F.SELECTED, "bg"),
 ("thunar-choisi",     "ExoIconView", ["view"],   F.SELECTED, "bg"),
 ("bureau-choisi",     "XfdesktopIconView", ["view"], F.ACTIVE, "bg"),
 ("bureau-repos",      "XfdesktopIconView", ["view"], F.NORMAL, "bg"),
 ("ligne-choisie",     "row",     [],             F.SELECTED, "bg"),
 ("menu",              "menu",    [],             F.NORMAL,  "bg"),
 ("saisie",            "entry",   [],             F.NORMAL,  "bg"),
 ("saisie-texte",      "entry",   [],             F.NORMAL,  "fg"),
 ("popover",           "popover", ["background"], F.NORMAL,  "bg"),
 ("infobulle",         "tooltip", ["background"], F.NORMAL,  "bg"),
 ("infobulle-texte",   "tooltip", ["background"], F.NORMAL,  "fg"),
 ("ascenseur",         "scrollbar", [],           F.NORMAL,  "bg"),
 ("selection-texte",   "selection", [],           F.NORMAL,  "bg"),
]
for nom, n, cl, fl, q in CAS:
    print("%s\t%s" % (nom, couleur(n, cl, fl, q)))
PY
	#  Le thème doit être trouvable par GTK : il le cherche dans ~/.themes.
	mkdir -p "$BANC/home/.themes"
	cp -r "$TH" "$BANC/home/.themes/"
	mesure() { HOME="$BANC/home" "$PY" "$BANC/mes.py" "$@" 2>/dev/null; }
	mesure Arc-Dark "$BANC/t/.config/gtk-3.0/gtk.css" > "$BANC/avant.txt"
	mesure LexOS-Noir ""                              > "$BANC/apres.txt"

	if grep -q "PAS-D-ECRAN" "$BANC/avant.txt" 2>/dev/null; then
		saut "aucun écran X (relancer sous « xvfb-run ») : l'égalité n'a PAS été mesurée"
	elif [ ! -s "$BANC/avant.txt" ] || [ ! -s "$BANC/apres.txt" ]; then
		non "la mesure n'a rien rendu"
	else
		DIFFS=0
		while IFS=$'\t' read -r NOM VAL; do
			VAL2="$(awk -F'\t' -v k="$NOM" '$1==k{print $2}' "$BANC/apres.txt")"
			if [ "$VAL" != "$VAL2" ]; then
				non "$NOM : la pile actuelle rend $VAL, le thème seul rend $VAL2"
				DIFFS=$((DIFFS + 1))
			fi
		done < "$BANC/avant.txt"
		N="$(wc -l < "$BANC/avant.txt")"
		[ "$DIFFS" = 0 ] \
			&& ok "les $N couleurs sont IDENTIQUES — le thème seul suffirait déjà" \
			|| non "$DIFFS règle(s) cesseraient de gagner : à écrire à la bonne spécificité"
	fi
fi

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
