#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'écran de connexion — le hook 0410, le fragment du 0600, le CSS
# =============================================================================
#  CE QU'ON ÉPROUVE, ET CE QU'ON NE PEUT PAS ÉPROUVER
#  On n'a pas de serveur X dans le conteneur : personne ici ne verra jamais
#  l'écran de connexion. Ce banc ne dit donc PAS « c'est joli ». Il dit trois
#  choses vérifiables :
#
#    1. Le CSS, passé dans un moteur de cascade écrit ici, donne bien du NOIR
#       à la boîte et de l'ORANGE aux écritures — y compris quand une règle du
#       thème de base essaie de dire autre chose. C'est la seule façon de
#       prouver un CSS sans rien afficher : résoudre la cascade à la main.
#    2. Le hook 0410 écrit ce qu'il faut dans le cas normal, ET se replie
#       proprement dans les trois cas où quelque chose manque. Chaque repli
#       est joué pour de vrai, pas relu.
#    3. Le fragment du hook 0600 n'écrase PAS le thème de connexion. C'était
#       le piège : le 0600 réécrivait « theme-name » sans condition, et aurait
#       défait le travail du 0410 en silence.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0410-lexos-connexion.hook.chroot"
HOOK0600="$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot"
HOOK0300="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
CSS="$RACINE/config/includes.chroot/usr/share/lexos/connexion.css"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
#  Un moteur de cascade GTK, réduit à ce dont on a besoin
# =============================================================================
#  GTK trie par PRIORITÉ de fournisseur d'abord (thème 200, utilisateur 800),
#  puis par spécificité, puis par ordre d'écriture. On reproduit les trois.
#  Le « thème de base » du banc joue le rôle d'Arc-Dark : il peint la boîte en
#  gris. Si notre feuille ne le bat pas, la réponse sera grise et le banc
#  rouge — ce qui est exactement ce qu'Alex a photographié.
cat > "$BANC/cascade.py" <<'PY'
import re, sys, json

def couleurs(texte):
    #  GTK résout les « @define-color » AVANT d'appliquer les déclarations :
    #  un banc qui rendrait « @lexos_noir » ne dirait pas si c'est noir.
    return dict(re.findall(r"@define-color\s+([\w-]+)\s+([^;]+);", texte))

def regles(texte):
    #  On enlève les commentaires, puis on découpe « sélecteurs { corps } ».
    texte = re.sub(r"/\*.*?\*/", "", texte, flags=re.S)
    noms = couleurs(texte)
    out = []
    for m in re.finditer(r"([^{}@]+)\{([^{}]*)\}", texte):
        sels = [s.strip() for s in m.group(1).split(",") if s.strip()]
        decls = {}
        for d in m.group(2).split(";"):
            if ":" in d:
                k, v = d.split(":", 1)
                v = v.strip()
                for nom, val in noms.items():
                    v = v.replace("@" + nom, val.strip())
                decls[k.strip()] = v
        for s in sels:
            out.append((s, decls))
    return out

def specificite(sel):
    return (sel.count("#"), sel.count(".") + sel.count(":"), len(re.findall(r"(?<![#.\w-])[a-z][a-z0-9-]*", sel)))

def correspond(sel, chemin):
    #  chemin : liste d'ancêtres, du plus lointain au nœud lui-même.
    #  Chaque nœud : {"nom":..., "id":..., "classes":[...]}
    parts = sel.split()
    i = len(chemin) - 1
    for p in reversed(parts):
        trouve = False
        while i >= 0:
            n = chemin[i]
            i -= 1
            nom = re.match(r"^[a-z][a-z0-9-]*", p)
            idm = re.search(r"#([\w-]+)", p)
            cls = re.findall(r"\.([\w-]+)", p)
            pse = re.findall(r":([\w-]+)", p)
            if nom and nom.group(0) != n["nom"] and p[0] != "*":
                continue
            if p.startswith("*") and not nom:
                pass
            if idm and idm.group(1) != n.get("id"):
                continue
            if any(c not in n.get("classes", []) for c in cls):
                continue
            if any(s not in n.get("etats", []) for s in pse):
                continue
            trouve = True
            break
        if not trouve:
            return False
    return True

def resoudre(feuilles, chemin, prop):
    #  feuilles : [(priorite, texte)] dans l'ordre de chargement
    gagnant = None
    for ordre_f, (prio, texte) in enumerate(feuilles):
        for ordre_r, (sel, decls) in enumerate(regles(texte)):
            if prop not in decls:
                continue
            if not correspond(sel, chemin):
                continue
            cle = (prio,) + specificite(sel) + (ordre_f, ordre_r)
            if gagnant is None or cle > gagnant[0]:
                gagnant = (cle, decls[prop])
    return gagnant[1] if gagnant else None

if __name__ == "__main__":
    feuilles = json.load(open(sys.argv[1]))
    chemin   = json.load(open(sys.argv[2]))
    print(resoudre([(p, open(f).read()) for p, f in feuilles], chemin, sys.argv[3]) or "")
PY

#  Le faux « Arc-Dark » : il peint en gris, comme le vrai, et il le fait avec
#  des sélecteurs COMPOSÉS — sinon on prouverait qu'on bat un adversaire plus
#  faible que le vrai.
cat > "$BANC/base.css" <<'CSS'
#login_window { background-color: #383C4A; color: #D3DAE3; }
#login_window #content_frame { background-color: #404552; }
#login_window #buttonbox_frame { background-color: #353945; }
#login_window button { background-color: #4B5162; color: #D3DAE3; }
#login_window entry { background-color: #2B2E39; color: #D3DAE3; }
#login_window label.error { color: #E01B24; }
#panel_window { background-color: #2F343F; color: #D3DAE3; }
menuitem:hover { background-color: #4B5162; color: #D3DAE3; }
row:selected { background-color: #4B5162; color: #D3DAE3; }
CSS

resout() { # resout <chemin.json> <propriete> [<priorite-de-notre-feuille>]
	local prio="${3:-800}"
	printf '[[200,"%s"],[%s,"%s"]]' "$BANC/base.css" "$prio" "$CSS" > "$BANC/f.json"
	python3 "$BANC/cascade.py" "$BANC/f.json" "$1" "$2"
}

# =============================================================================
titre "1. Le CSS : la boîte devient noire et l'écriture orange"
# =============================================================================
[ -r "$CSS" ] || { non "connexion.css introuvable"; echo; exit 1; }

cat > "$BANC/boite.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]}]
J
cat > "$BANC/contenu.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"box","id":"content_frame","classes":[]}]
J
cat > "$BANC/boutons.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"box","id":"buttonbox_frame","classes":[]}]
J
cat > "$BANC/erreur.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"label","classes":["error"]}]
J
cat > "$BANC/bouton.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"button","classes":[]}]
J
cat > "$BANC/champ.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"entry","classes":[]}]
J
cat > "$BANC/photo.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"image","id":"user_image","classes":[]}]
J
#  LE CAS QUI COMPTE : un menu ou une rangée survolée dans un POPUP QUI N'A
#  AUCUN ANCÊTRE NOMMÉ — ni #login_window, ni #panel_window. C'est
#  précisément le cas d'un GtkMenu (le menu « Mettre en veille / Éteindre »
#  de l'indicateur « ~power », la liste des comptes) : sa fenêtre de haut
#  niveau n'est pas un descendant GTK du panneau, même si elle paraît collée
#  dessus à l'écran. Si nos règles dépendaient d'un ancêtre nommé, ce cas
#  resterait orange sur orange — exactement la photo d'Alex.
cat > "$BANC/menu_sans_ancre.json" <<'J'
[{"nom":"window","id":"","classes":[]},
 {"nom":"menuitem","classes":[],"etats":["hover"]}]
J
cat > "$BANC/rangee_sans_ancre.json" <<'J'
[{"nom":"window","id":"","classes":[]},
 {"nom":"row","classes":[],"etats":["selected"]}]
J

#  LES DEUX RÉGIMES. En 800 (le CSS de l'utilisateur du compte lightdm) la
#  priorité suffit. En 200 (notre thème LexOS-Connexion, à égalité avec la
#  base) c'est la spécificité et l'ordre qui doivent gagner — c'est LÀ que les
#  sélecteurs composés servent, et c'est le régime qu'on oublierait de tester.
for PRIO in 800 200; do
	F="$(resout "$BANC/boite.json" background-color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : la boîte est NOIRE (#000000), plus le gris d'Arc" \
		|| non "priorité $PRIO : la boîte vaut « $F » au lieu de #000000"

	F="$(resout "$BANC/contenu.json" background-color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : le contenu (#content_frame) est noir lui aussi" \
		|| non "priorité $PRIO : #content_frame vaut « $F » — bande grise dans la boîte"

	F="$(resout "$BANC/boutons.json" background-color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : la rangée des boutons est noire (pas de bande grise en bas)" \
		|| non "priorité $PRIO : #buttonbox_frame vaut « $F »"
done

F="$(resout "$BANC/erreur.json" color)"
[ "$F" = "#E8590C" ] \
	&& ok "« Votre mot de passe est incorrect » passe en orange (le rouge du thème perd)" \
	|| non "le message d'erreur vaut « $F » — il resterait rouge"

F="$(resout "$BANC/bouton.json" color)"
[ "$F" = "#E8590C" ] \
	&& ok "les boutons écrivent en orange" \
	|| non "les boutons écrivent « $F »"
F="$(resout "$BANC/bouton.json" background-color)"
[ "$F" = "#141416" ] \
	&& ok "et leur fond reste très sombre sans être noir sur noir" \
	|| non "fond de bouton : « $F »"

F="$(resout "$BANC/champ.json" color)"
[ "$F" = "#E8590C" ] \
	&& ok "ce qu'on tape dans le champ du mot de passe est orange" \
	|| non "le champ écrit « $F »"

F="$(resout "$BANC/photo.json" border-radius)"
[ "$F" = "50%" ] \
	&& ok "la photo du profil est cerclée en rond" \
	|| non "la photo du profil : border-radius « $F »"

#  ALEX, TROIS PHOTOS : le menu « ~power » (Mettre en veille / Éteindre…) et
#  la liste des comptes (« invite » en surbrillance) passaient orange sur
#  orange au survol. Ces popups n'ont, dans l'arbre GTK, AUCUN ancêtre nommé
#  #login_window ou #panel_window — d'où des fixtures SANS ancêtre nommé
#  (fenêtre à id vide) : si le test passe seulement avec un #login_window en
#  tête de chemin, il ne prouve rien du vrai cas.
for PRIO in 800 200; do
	F="$(resout "$BANC/menu_sans_ancre.json" background-color "$PRIO")"
	[ "$F" = "#E8590C" ] \
		&& ok "priorité $PRIO : un menuitem survolé, SANS ancêtre nommé, passe orange" \
		|| non "priorité $PRIO : menuitem survolé sans ancêtre = « $F » (le popup du panneau resterait gris)"
	F="$(resout "$BANC/menu_sans_ancre.json" color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : … et son écriture passe NOIRE (plus d'orange sur orange)" \
		|| non "priorité $PRIO : écriture du menuitem survolé = « $F »"

	F="$(resout "$BANC/rangee_sans_ancre.json" background-color "$PRIO")"
	[ "$F" = "#E8590C" ] \
		&& ok "priorité $PRIO : une rangée sélectionnée, SANS ancêtre nommé, passe orange" \
		|| non "priorité $PRIO : rangée sélectionnée sans ancêtre = « $F »"
	F="$(resout "$BANC/rangee_sans_ancre.json" color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : … et son écriture passe NOIRE aussi" \
		|| non "priorité $PRIO : écriture de la rangée sélectionnée = « $F »"
done

#  L'ORDRE. « #login_window * » et « #login_window button » ont la MÊME
#  spécificité : si le large passait APRÈS, il repeindrait les boutons et on
#  perdrait le contraste. Le banc regarde les positions, pas les intentions.
LARGE="$(grep -n '^#login_window \*' "$CSS" | head -1 | cut -d: -f1)"
BOUT="$(grep -n '^#login_window button {' "$CSS" | head -1 | cut -d: -f1)"
if [ -n "$LARGE" ] && [ -n "$BOUT" ] && [ "$LARGE" -lt "$BOUT" ]; then
	ok "le sélecteur large est écrit AVANT les boutons (à égalité, le dernier gagne)"
else
	non "ordre des règles : large=$LARGE bouton=$BOUT — les boutons seraient repeints"
fi

#  LA LEÇON DE « selection, ::selection » : un sélecteur douteux ne voyage
#  jamais en liste. S'il tombe, il ne doit emporter que lui-même.
if grep -q '^#login_window entry selection {$' "$CSS"; then
	ok "« entry selection » est seul dans sa règle (un invalide n'emporte pas le champ)"
else
	non "« entry selection » n'est pas isolé — une liste le rendrait fatal au champ"
fi

# =============================================================================
titre "2. Le hook 0410 : le cas normal"
# =============================================================================
prepare() {
	rm -rf "${BANC:?}/racine"
	mkdir -p "$BANC/racine/etc/lightdm" "$BANC/racine/var/lightdm" \
	         "$BANC/racine/themes/Arc-Dark/gtk-3.0" "$BANC/racine/fonds" \
	         "$BANC/racine/etc/lexos" "$BANC/racine/skel/.config/lexos"
	echo '/* le vrai Arc-Dark */' > "$BANC/racine/themes/Arc-Dark/gtk-3.0/gtk.css"
	cat > "$BANC/racine/etc/lexos/build.conf" <<'CONF'
LEXOS_GTK_BASE_THEME="Arc-Dark"
LEXOS_ICON_THEME="LexOS"
CONF
}

lance() {
	LEXOS_LIGHTDM_DIR="$BANC/racine/etc/lightdm" \
	LEXOS_LIGHTDM_HOME="$BANC/racine/var/lightdm" \
	LEXOS_THEMES="$BANC/racine/themes" \
	LEXOS_BG_DIR="$BANC/racine/fonds" \
	LEXOS_CONNEXION_CSS="${CSS_UTILISE:-$CSS}" \
	LEXOS_BUILD_CONF="$BANC/racine/etc/lexos/build.conf" \
	LEXOS_LIGHTDM_BIN="/bin/sh" \
	sh "$HOOK" 2>&1
}

prepare
: > "$BANC/racine/fonds/lexos-connexion.png"
SORTIE="$(lance)"
CONF="$BANC/racine/etc/lightdm/lightdm-gtk-greeter.conf"

grep -q "^background=$BANC/racine/fonds/lexos-connexion.png$" "$CONF" \
	&& ok "le fond est l'image du démon composée par le hook 0300" \
	|| non "background : $(grep '^background=' "$CONF")"
grep -q '^theme-name=LexOS-Connexion$' "$CONF" \
	&& ok "le greeter porte le thème LexOS-Connexion" \
	|| non "theme-name : $(grep '^theme-name=' "$CONF")"
grep -q '^hide-user-image=false$' "$CONF" \
	&& ok "la photo du profil choisi est affichée" \
	|| non "hide-user-image absent — pas de photo de profil"
grep -q '^position=50%,center 88%,end$' "$CONF" \
	&& ok "la boîte est ancrée par le BAS (le logo reste dégagé en haut)" \
	|| non "position : $(grep '^position=' "$CONF")"
grep -q '^icon-theme-name=LexOS$' "$CONF" \
	&& ok "les icônes suivent le thème LexOS lu dans build.conf" \
	|| non "icon-theme-name : $(grep '^icon-theme-name=' "$CONF")"

TH="$BANC/racine/themes/LexOS-Connexion/gtk-3.0/gtk.css"
head -1 "$TH" | grep -q "^@import url(\"file://$BANC/racine/themes/Arc-Dark/gtk-3.0/gtk.css\");$" \
	&& ok "le thème importe le thème de base EN PREMIÈRE LIGNE (règle du langage)" \
	|| non "première ligne du thème : $(head -1 "$TH")"
grep -q '#login_window' "$TH" \
	&& ok "et nos règles suivent l'import" \
	|| non "les règles LexOS ne sont pas dans le thème"
[ -r "$BANC/racine/var/lightdm/.config/gtk-3.0/gtk.css" ] \
	&& ok "la même feuille est posée dans le foyer du compte lightdm (priorité 800)" \
	|| non "pas de gtk.css dans le foyer de lightdm — un seul chemin au lieu de deux"

# =============================================================================
titre "3. Les trois replis — joués, pas relus"
# =============================================================================
prepare                       # aucune image de fond
SORTIE="$(lance)"
grep -q '^background=#000000$' "$CONF" \
	&& ok "sans image, le fond est du NOIR et pas un fichier fantôme" \
	|| non "sans image : $(grep '^background=' "$CONF")"

prepare
: > "$BANC/racine/fonds/wallpaper.png"
SORTIE="$(lance)"
grep -q "^background=$BANC/racine/fonds/wallpaper.png$" "$CONF" \
	&& ok "sans l'image du démon, il retombe sur le fond d'écran ordinaire" \
	|| non "repli du fond : $(grep '^background=' "$CONF")"

prepare
CSS_UTILISE="$BANC/rien.css"
SORTIE="$(lance)"
unset CSS_UTILISE
grep -q '^theme-name=Arc-Dark$' "$CONF" \
	&& ok "sans CSS, il n'écrit PAS le nom d'un thème qu'il n'a pas fabriqué" \
	|| non "sans CSS : $(grep '^theme-name=' "$CONF") — GTK retomberait sur Adwaita, en CLAIR"
[ ! -d "$BANC/racine/themes/LexOS-Connexion" ] \
	&& ok "et ne laisse pas un thème vide derrière lui" \
	|| non "un LexOS-Connexion a été créé sans feuille de style"
echo "$SORTIE" | grep -q 'absent' \
	&& ok "il le DIT dans le journal" \
	|| non "aucun CSS, et rien dans le journal"

prepare
rm -rf "$BANC/racine/themes/Arc-Dark"
SORTIE="$(lance)"
head -1 "$TH" | grep -q '^/\* thème de base introuvable' \
	&& ok "sans thème de base, pas d'import vers un dossier qui n'existe pas" \
	|| non "première ligne : $(head -1 "$TH")"
grep -q '#login_window' "$TH" \
	&& ok "et le noir et l'orange tiennent quand même" \
	|| non "les règles LexOS ont disparu avec le thème de base"

# =============================================================================
titre "4. Le hook 0600 n'écrase pas ce que le 0410 a posé"
# =============================================================================
#  On découpe le fragment entre ses balises et on l'exécute pour de vrai. Si
#  les balises disparaissent, le découpage rend un fichier vide et le banc
#  devient rouge — c'est voulu.
FRAG="$BANC/frag0600.sh"
{ echo '#!/bin/sh'; echo 'set -e'
  sed -n '/^# >>> banc: connexion$/,/^# <<< banc: connexion$/p' "$HOOK0600"
} > "$FRAG"
LIGNES="$(wc -l < "$FRAG")"
[ "$LIGNES" -gt 20 ] \
	&& ok "le fragment « banc: connexion » a bien été retrouvé dans le hook 0600" \
	|| non "fragment introuvable ou vide ($LIGNES lignes) — balises déplacées ?"

frag0600() { # frag0600 <GTK_BASE> <ICONS>
	GTK_BASE="$1" ICONS="$2" \
	LEXOS_LIGHTDM_DIR="$BANC/racine/etc/lightdm" \
	LEXOS_LIGHTDM_HOME="$BANC/racine/var/lightdm" \
	LEXOS_THEMES="$BANC/racine/themes" \
	LEXOS_SKEL="$BANC/racine/skel" \
	sh "$FRAG" 2>&1
}

prepare
: > "$BANC/racine/fonds/lexos-connexion.png"
lance >/dev/null
frag0600 Arc-Dark LexOS >/dev/null
grep -q '^theme-name=LexOS-Connexion$' "$CONF" \
	&& ok "le 0600 LAISSE le thème de connexion en place (le piège du build 76)" \
	|| non "le 0600 a remis « $(grep '^theme-name=' "$CONF") » — tout le travail annulé"

#  Le thème de base a changé sous nos pieds : l'import doit suivre.
mkdir -p "$BANC/racine/themes/Adwaita-dark/gtk-3.0"
echo '/* Adwaita */' > "$BANC/racine/themes/Adwaita-dark/gtk-3.0/gtk.css"
frag0600 Adwaita-dark LexOS >/dev/null
head -1 "$TH" | grep -q "Adwaita-dark/gtk-3.0/gtk.css" \
	&& ok "l'import suit le thème RÉELLEMENT retenu quand Arc-Dark manque" \
	|| non "import : $(head -1 "$TH")"

#  Un greeter sans notre thème (CSS absent au 0410) doit, lui, être corrigé.
prepare
CSS_UTILISE="$BANC/rien.css"; lance >/dev/null; unset CSS_UTILISE
frag0600 Adwaita-dark Papirus-Dark >/dev/null
grep -q '^theme-name=Adwaita-dark$' "$CONF" \
	&& ok "quand ce n'est PAS notre thème, le 0600 corrige le nom comme avant" \
	|| non "theme-name : $(grep '^theme-name=' "$CONF")"
grep -q '^icon-theme-name=Papirus-Dark$' "$CONF" \
	&& ok "et il corrige toujours le thème d'icônes" \
	|| non "icon-theme-name : $(grep '^icon-theme-name=' "$CONF")"

# --- L'accent -----------------------------------------------------------
prepare
: > "$BANC/racine/fonds/lexos-connexion.png"
lance >/dev/null
cat > "$BANC/racine/skel/.config/lexos/theme.conf" <<'CONF'
LEXOS_ACCENT_NAME=bleu
LEXOS_ACCENT=#1A5FB4
LEXOS_ACCENT_HI=#3584E4
LEXOS_ACCENT_LO=#10375F
CONF
frag0600 Arc-Dark LexOS >/dev/null
grep -q '#1A5FB4' "$TH" && ! grep -qi '#E8590C' "$TH" \
	&& ok "une ISO montée en bleu a un écran de connexion bleu (plus deux vérités)" \
	|| non "l'accent n'a pas été substitué dans le thème"
grep -q '#1A5FB4' "$BANC/racine/var/lightdm/.config/gtk-3.0/gtk.css" \
	&& ok "la copie du foyer lightdm suit le même accent" \
	|| non "la copie du foyer lightdm est restée orange"

prepare
: > "$BANC/racine/fonds/lexos-connexion.png"
lance >/dev/null
cat > "$BANC/racine/skel/.config/lexos/theme.conf" <<'CONF'
LEXOS_ACCENT=#E8590C
CONF
frag0600 Arc-Dark LexOS >/dev/null
grep -qi '#E8590C' "$TH" \
	&& ok "et l'orange par défaut n'est pas touché inutilement" \
	|| non "l'orange a été remplacé alors qu'il était déjà le bon"

# =============================================================================
titre "5. Le fond du hook 0300 — l'image que le 0410 attend"
# =============================================================================
grep -q 'lexos-connexion.png' "$HOOK0300" \
	&& ok "le hook 0300 compose bien lexos-connexion.png" \
	|| non "le hook 0300 ne fabrique pas l'image que le 0410 va chercher"
grep -q -- '-resize x680' "$HOOK0300" \
	&& ok "le logo fait 680 px de haut (composition regardée, pas devinée)" \
	|| non "la taille du logo a changé sans que la composition soit revue"

# =============================================================================
titre "6. Les mutations — un banc qui ne peut pas échouer ne prouve rien"
# =============================================================================
mutation() { # mutation <libelle> <fichier> <sed>
	cp "$2" "$BANC/sauve"
	sed -i "$3" "$2"
	if bash "$0" --enfant >/dev/null 2>&1; then
		non "MUTATION NON DÉTECTÉE : $1"
	else
		ok "mutation détectée : $1"
	fi
	cp "$BANC/sauve" "$2"
}

if [ "${1:-}" != "--enfant" ]; then
	mutation "la boîte repasse en gris" "$CSS" \
		's|^#login_window {$|#login_window { background-color: #383C4A; }\n#login_window-mort {|'
	mutation "le 0600 réécrase theme-name sans condition" "$HOOK0600" \
		"s|^\tif ! grep -q '\^theme-name=LexOS-Connexion\$' \"\$CONNEXION_CONF\"; then\$|\tif true; then|"
	mutation "le 0410 nomme un thème qu'il n'a pas fabriqué" "$HOOK" \
		's|^GREETER_THEME="${LEXOS_GTK_BASE_THEME}"$|GREETER_THEME="LexOS-Connexion"|'
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
