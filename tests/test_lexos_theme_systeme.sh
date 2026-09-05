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
#  Le gtk.css du socle n'est PAS une feuille de style : c'est une seule
#  ligne qui pointe vers une ressource COMPILÉE, que GTK n'enregistre que
#  lorsqu'il charge le socle PAR SON NOM. Un thème qui importerait ce fichier
#  par son chemin obtient « Failed to import: The resource does not exist » —
#  et un bureau NU, sans en-tête ni sélection, l'avertissement perdu dans le
#  journal. La ressource doit être posée À CÔTÉ de notre feuille.
#
#  LE SOCLE A CHANGÉ À L'ISO 109 : « Yaru-dark » remplace « Arc-Dark ».
#  L'adresse de la ressource change avec lui — mesurée :
#  « resource:///com/ubuntu/themes/Yaru-dark/3.0/gtk.css » là où Arc écrivait
#  « resource:///org/gnome/arc-theme/gtk-main-dark.css ». Ce contrôle-ci ne
#  connaît AUCUNE de ces deux adresses : il compare ce que le générateur a
#  écrit à ce que le socle écrit CHEZ LUI. C'est ce qui a permis au socle de
#  changer sans qu'une ligne de gen_theme() ne bouge.
SOCLE_ATTENDU="Yaru-dark"
BASE="${LEXOS_THEMES_SYS:-/usr/share/themes}/$SOCLE_ATTENDU"
if [ ! -d "$BASE" ]; then
	saut "$SOCLE_ATTENDU absent de cette machine : le lien n'a PAS été vérifié"
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
	saut "$SOCLE_ATTENDU absent : les couleurs n'ont PAS été mesurées"
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
#  Le socle peut manquer — il était OPTIONNEL du temps d'arc-theme, et même
#  en liste stricte un repli reste prévu. Le hook 0600 choisit donc le
#  premier thème sombre réellement présent — mais il l'exportait sous
#  « LEXOS_GTK_BASE_THEME » tandis que le générateur lisait
#  « LEXOS_GTK_BASE ». Deux noms voisins, jamais le même : le repli
#  n'arrivait pas. Sur une machine sans le socle on aurait posé un lien vers
#  une ressource ABSENTE — bureau NU, pour un avertissement dans le journal.
CODE_H="$(sed 's/#.*$//' "$HOOK")"
if grep -q 'LEXOS_GTK_BASE_THEME="\$GTK_BASE"' <<< "$CODE_H"; then
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
#  générateur retombait sur son défaut. Mais ce défaut nommait un socle
#  précis — « Arc-Dark » à l'époque, qui voyageait dans les paquets
#  OPTIONNELS : sur une machine où il manquait, le hook avait choisi un autre
#  socle, et la première session rebâtissait le thème sur un socle absent.
#  ISO juste, premier démarrage faux, silence complet.
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
if grep -q 'LEXOS_GTK_SOCLE=\${GTK_SOCLE}' <<< "$CODE_S"; then
	ok "build.conf reçoit LEXOS_GTK_SOCLE — la première session saura sur quoi bâtir"
else
	non "le hook n'écrit pas le socle dans build.conf : firstrun retomberait sur son défaut"
fi

#  3. firstrun le repasse au générateur — et ne lui donne PAS l'autre clé.
if [ -r "$FIRSTRUN" ]; then
	CODE_F="$(sed 's/#.*$//' "$FIRSTRUN")"
	if grep -q 'LEXOS_GTK_SOCLE="\$SOCLE" lexos-theme-gen' <<< "$CODE_F"; then
		ok "lexos-firstrun refabrique le thème sur le socle de la construction"
	else
		non "lexos-firstrun n'informe pas le générateur du socle : premier démarrage différent de l'ISO"
	fi
	if grep -q 'LEXOS_GTK_BASE_THEME=.*lexos-theme-gen' <<< "$CODE_F" ; then
		non "lexos-firstrun passe LEXOS_GTK_BASE_THEME au générateur — il vaut « LexOS-Noir » dans build.conf"
	else
		ok "lexos-firstrun ne donne pas au générateur la clé qui porte « LexOS-Noir »"
	fi
else
	non "lexos-firstrun introuvable — la première session n'a pas pu être éprouvée"
fi

#  4. LA MESURE, pas la lecture : le socle donné est bien celui employé.
rm -rf "$BANC/socle"; mkdir -p "$BANC/socle"
#  La valeur donnée doit être DIFFÉRENTE du défaut, sinon le contrôle serait
#  vert même si le générateur ignorait la clé. « Yaru-blue-dark » existe pour
#  de vrai (yaru-theme-gtk livre neuf variantes d'accent : bark, blue,
#  magenta, olive, prussiangreen, purple, red, sage, viridian, chacune avec
#  son « -dark ») — mais ici seul son NOM compte.
LEXOS_PANNEAU_CSS="$IC/usr/share/lexos/gtk-panneau.css" LEXOS_GTK_SOCLE="Yaru-blue-dark" \
	bash "$GEN" --target "$BANC/socle" orange >/dev/null 2>&1
if grep -q "^MetacityTheme=Yaru-blue-dark$" "$BANC/socle/.themes/LexOS-Noir/index.theme" 2>/dev/null; then
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
titre "3 sexies. Le socle par défaut est LE MÊME des deux côtés"
# =============================================================================
#  ═══ POURQUOI CE CONTRÔLE EXISTE ═══
#  Le nom du socle est écrit par DÉFAUT à quatre endroits, et deux programmes
#  différents peuvent le lire :
#
#    · le hook 0600 le fixe en tête (« GTK_BASE=… »), c'est le chemin de
#      l'ISO ;
#    · le hook 0600 le redonne comme repli quand build.conf est là
#      (« ${LEXOS_GTK_BASE_THEME:-…} ») ;
#    · lexos-theme-gen a le sien (« BASE_NOM=${LEXOS_GTK_SOCLE:-…} »), c'est
#      le chemin d'un appel à la main — « lexos accent bleu », par exemple ;
#    · lexos-theme-gen en a un second, celui qui refuse qu'un thème se bâtisse
#      sur lui-même.
#
#  Deux valeurs par défaut qui divergent, c'est un thème qui se construit
#  DIFFÉREMMENT selon le chemin emprunté : l'ISO sur un socle, la première
#  commande de l'utilisateur sur un autre. Personne ne le verrait — les deux
#  thèmes s'appellent LexOS-Noir, les deux ont un @import, les deux ont l'air
#  corrects. Seules les couleurs que notre feuille n'attrape pas changeraient,
#  et c'est exactement le genre de dérive qu'on met sur le dos d'autre chose.
#
#  Le changement Arc-Dark -> Yaru-dark de l'ISO 109 a touché ces quatre lignes.
#  Ce contrôle est là pour qu'un prochain changement ne puisse pas n'en toucher
#  que trois.
SOC_HOOK="$(grep -m1 '^GTK_BASE="' "$HOOK" | sed 's/^GTK_BASE="//; s/".*$//')"
SOC_HOOK_CONF="$(grep -m1 'GTK_BASE="${LEXOS_GTK_BASE_THEME:-' "$HOOK" \
	| sed 's/.*LEXOS_GTK_BASE_THEME:-//; s/}.*$//')"
SOC_GEN="$(grep -m1 '^BASE_NOM="${LEXOS_GTK_SOCLE:-' "$GEN" \
	| sed 's/.*LEXOS_GTK_BASE_THEME:-//; s/}.*$//')"
SOC_GEN_REPLI="$(grep -m1 '^[[:space:]]*BASE_NOM="[A-Za-z]' "$GEN" \
	| sed 's/.*BASE_NOM="//; s/".*$//')"

if [ -z "$SOC_HOOK" ] || [ -z "$SOC_HOOK_CONF" ] || [ -z "$SOC_GEN" ] || [ -z "$SOC_GEN_REPLI" ]; then
	non "socle par défaut illisible (hook=$SOC_HOOK/$SOC_HOOK_CONF gen=$SOC_GEN/$SOC_GEN_REPLI)"
elif [ "$SOC_HOOK" = "$SOC_GEN" ] && [ "$SOC_HOOK_CONF" = "$SOC_GEN" ] \
     && [ "$SOC_GEN_REPLI" = "$SOC_GEN" ]; then
	ok "les quatre défauts nomment le même socle (« $SOC_GEN »)"
else
	non "défauts divergents — hook « $SOC_HOOK » / « $SOC_HOOK_CONF », générateur « $SOC_GEN » / « $SOC_GEN_REPLI »"
fi

#  ET LE REPLI DU HOOK COMMENCE PAR LUI. « premier_present » prend le premier
#  thème RÉELLEMENT présent de sa liste. Si cette liste ne commençait pas par
#  le socle demandé, une machine qui a les deux prendrait le second : le repli
#  déciderait à la place du défaut, sans qu'aucun message ne soit imprimé
#  (l'avertissement n'est écrit que si le thème demandé manque).
PREMIER_REPLI="$(grep -m1 -A1 'premier_present /usr/share/themes' "$HOOK" \
	| sed -n '2p' | awk '{print $1}')"
if [ "$PREMIER_REPLI" = "$SOC_GEN" ]; then
	ok "la liste de repli commence par le socle demandé (« $PREMIER_REPLI »)"
else
	non "la liste de repli commence par « $PREMIER_REPLI », pas par « $SOC_GEN »"
fi

#  ═══ ET SON PAQUET EST EN LISTE STRICTE ═══
#  C'est la leçon des dossiers blancs de l'ISO 72, appliquée au socle. Tant
#  qu'arc-theme voyageait dans les paquets OPTIONNELS, le socle dépendait du
#  temps qu'il faisait sur les miroirs Debian : présent au build 71, absent au
#  72, et rien dans le journal pour le dire. Un socle absent, ce n'est pas
#  « un peu moins joli », c'est XFCE qui retombe sur son thème CLAIR.
#
#  LA LIMITE DE CE CONTRÔLE, ÉCRITE PLUTÔT QUE CACHÉE : le nom du THÈME
#  (« Yaru-dark ») n'est pas le nom du PAQUET (« yaru-theme-gtk »), et aucune
#  règle ne les relie. On rapproche donc la racine du nom — ce qui précède le
#  premier tiret, en minuscules — et on exige une ligne de paquet qui commence
#  par elle. « Yaru-dark » -> « yaru » -> « yaru-theme-gtk » ; « Arc-Dark » ->
#  « arc » -> « arc-theme ». C'est une heuristique, elle peut donner un vert
#  de trop sur un socle dont un paquet homonyme traînerait dans la liste ;
#  elle ne peut pas donner de vert quand le paquet est ABSENT de la liste
#  stricte, et c'est la panne qu'on veut empêcher.
STRICTE="$RACINE/config/package-lists/lexos-core.list.chroot"
OPTIONNELS="$IC/usr/share/lexos/optional-packages"
RACINE_PAQ="$(printf '%s' "$SOC_GEN" | tr 'A-Z' 'a-z' | cut -d- -f1)"
if [ -z "$RACINE_PAQ" ]; then
	non "racine de paquet illisible pour le socle « $SOC_GEN »"
elif grep -qE "^${RACINE_PAQ}[a-z0-9.+-]*$" "$STRICTE" 2>/dev/null; then
	ok "le paquet du socle est en liste STRICTE (« $RACINE_PAQ… » dans lexos-core)"
else
	non "aucun paquet « ${RACINE_PAQ}… » en liste stricte : le socle pourrait manquer sans arrêter la construction"
fi

#  ═══ ET LES VIEILLES APPLICATIONS GTK 2 SUIVENT LE SOCLE ═══
#  lexos-theme-gen écrit un ~/.gtkrc-2.0 qui nomme un thème GTK 2 en dur, un
#  pour le mode sombre et un pour le clair. Ces deux noms sont restés
#  « Arc-Dark » / « Arc » APRÈS le changement de socle, le temps d'un
#  balayage : arc-theme étant redevenu optionnel, ils désignaient un thème qui
#  peut ne pas être là — et GTK 2 sans thème, c'est le gris clair d'origine au
#  milieu d'un bureau noir. On exige donc qu'ils viennent du même paquet que
#  le socle. MESURÉ : yaru-theme-gtk livre bien un gtk-2.0 pour Yaru-dark et
#  pour Yaru.
G2S="$(grep -m1 '^GTK2_THEME="' "$GEN" | sed 's/^GTK2_THEME="//; s/".*$//')"
G2C="$(grep -m1 'GTK2_THEME="[A-Za-z][^"]*"; GTK2_ICONS="Papirus"' "$GEN" 	| sed 's/.*GTK2_THEME="//; s/".*$//')"
G2SR="$(printf '%s' "$G2S" | tr 'A-Z' 'a-z' | cut -d- -f1)"
G2CR="$(printf '%s' "$G2C" | tr 'A-Z' 'a-z' | cut -d- -f1)"
if [ -z "$G2S" ] || [ -z "$G2C" ]; then
	non "thèmes GTK 2 illisibles dans le générateur (sombre=$G2S clair=$G2C)"
elif [ "$G2SR" = "$RACINE_PAQ" ] && [ "$G2CR" = "$RACINE_PAQ" ]; then
	ok "les thèmes GTK 2 viennent du paquet du socle (« $G2S » / « $G2C »)"
else
	non "GTK 2 nomme « $G2S » / « $G2C » — hors du paquet du socle « $RACINE_PAQ »"
fi

#  ═══ ET LA CI L'INSTALLE, SOUS SON NOM DU JOUR ═══
#  CE CONTRÔLE EXISTE PARCE QUE LA PANNE A EU LIEU. Première construction de
#  l'ISO 110 : la CI installait « arc-theme », l'ancien socle. Yaru-dark
#  n'était donc pas là, et le banc NE S'EST PAS MIS EN ROUGE — il s'est SAUTÉ.
#  La section 2 (« la ressource est atteignable ») et surtout la section 3 —
#  les treize couleurs MESURÉES sur un vrai GTK 3.24, le cœur du banc — sont
#  passées derrière un « — », et il ne restait plus que des lectures de
#  fichiers. Deux contrôles ont fini par rougir, presque par accident : ceux
#  qui exigent qu'un thème refusant de se bâtir sur lui-même retombe sur un
#  socle RÉEL. Sans eux, la CI serait restée verte en n'éprouvant plus rien.
#
#  C'est exactement le faux vert que ce dépôt traque depuis le banc Boost
#  décroché pendant cinq constructions. On le ferme ici : la ligne
#  d'installation de la CI doit nommer le paquet du socle. Changer le socle
#  sans changer cette ligne rougit maintenant, au lieu de vider le banc.
CI_YML="$RACINE/.github/workflows/ci.yml"
L_INV="$(grep -n 'bash tests/test_lexos_theme_systeme.sh' "$CI_YML" 2>/dev/null \
	| head -1 | cut -d: -f1)"
LISTE_CI=""
[ -n "$L_INV" ] && LISTE_CI="$(awk -v n="$L_INV" \
	'NR < n && /for p in /{ l = $0 } END { print l }' "$CI_YML")"
if [ -z "$LISTE_CI" ]; then
	non "impossible de relire la liste de paquets de la CI pour ce banc"
elif grep -qE "(^|[[:space:]])${RACINE_PAQ:-@}[a-z0-9.+-]*([[:space:]]|;)" <<< "$LISTE_CI"; then
	ok "la CI installe bien le paquet du socle avant de lancer ce banc"
else
	non "la CI n'installe aucun « ${RACINE_PAQ}… » : le banc se SAUTERAIT au lieu de mesurer"
fi

#  Et il ne voyage PAS AUSSI dans les optionnels : deux listes pour un même
#  paquet, c'est l'apt-get de trop et surtout la fausse impression qu'on peut
#  le retirer de la stricte sans conséquence.
DOUBLON="$(grep -rhE "^${RACINE_PAQ:-@}[a-z0-9.+-]*$" "$OPTIONNELS" 2>/dev/null | tr '\n' ' ')"
if [ -z "$DOUBLON" ]; then
	ok "le paquet du socle n'est pas en double dans les paquets optionnels"
else
	non "le paquet du socle est AUSSI optionnel : $DOUBLON"
fi

# =============================================================================
titre "4. Le hook ne déclare le thème que s'il EXISTE"
# =============================================================================
#  Écrire un nom de thème introuvable donne un bureau CLAIR par défaut, sans
#  qu'une ligne du journal ne le signale. C'est la faute que le garde-fou
#  du socle évite déjà vingt lignes plus haut ; celui-ci fait pareil.
CODE="$(sed 's/#.*$//' "$HOOK")"
if grep -q '\-r "/etc/skel/.themes/${THEME_LEXOS}/gtk-3.0/gtk.css"' <<< "$CODE"; then
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

#  ═══ ET CETTE VALEUR EST PUBLIÉE, PAS SEULEMENT CALCULÉE ═══
#  Elle ne partait dans build.conf que par le hook 0610, qui DÉRIVE un thème
#  de fenêtre à gros boutons. Or 0610 s'arrête avant d'écrire quoi que ce soit
#  quand il n'a rien pu dériver — pas d'arc-theme, pas d'ImageMagick. La clé
#  restait alors absente, lexos-firstrun retombait sur LEXOS_GTK_BASE_THEME,
#  c'est-à-dire « LexOS-Noir »… qui n'a PAS de dossier xfwm4, étant une
#  feuille de style dans le foyer. Résultat mesurable : xfwm4 sur « Default »,
#  des bordures GRISES au milieu d'un bureau noir, et pas une ligne de
#  journal. 0600 publie donc sa valeur ; 0610 la remplace par la sienne quand
#  il réussit, puisqu'il passe après.
if grep -q 'LEXOS_XFWM_THEME=\${XFWM_THEME}' <<< "$CODE"; then
	ok "le hook 0600 publie LEXOS_XFWM_THEME — 0610 muet ne laisse plus la clé vide"
else
	non "LEXOS_XFWM_THEME n'est pas publié par 0600 : bordures grises si 0610 ne dérive rien"
fi

#  ET LA CEINTURE DU CÔTÉ DE LA PREMIÈRE SESSION. « lexos theme » vérifiait
#  depuis toujours que le thème de fenêtre nommé EXISTE ; lexos-firstrun, non.
if [ -r "$FIRSTRUN" ]; then
	if grep -q 'd "/usr/share/themes/${XFWM_THEME}/xfwm4"' "$FIRSTRUN"; then
		ok "lexos-firstrun refuse un thème de fenêtre absent (même garde que « lexos theme »)"
	else
		non "lexos-firstrun poserait un thème de fenêtre inexistant : bordures grises"
	fi
else
	non "lexos-firstrun introuvable — la garde du thème de fenêtre n'a pas pu être éprouvée"
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mLexOS-Noir est un vrai thème, et il rend ce que rendait la pile.\033[0m\n'
