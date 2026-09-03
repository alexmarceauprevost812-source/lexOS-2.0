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
#  Ni vert ni rouge : « on n'a pas pu mesurer ». Compter un vert ferait
#  croire à une preuve ; un rouge accuserait la mauvaise pièce.
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }

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
                #  DU PLUS LONG NOM AU PLUS COURT, ET C'EST UN VRAI BOGUE
                #  QU'ON CORRIGE ICI. « @lexos_accent » est un PRÉFIXE de
                #  « @lexos_accent_hi » : substitué en premier, il laissait
                #  « #E8590C_hi » derrière lui — une couleur qui n'existe pas,
                #  et le banc annonçait un écart là où le CSS était juste. Le
                #  piège dormait depuis toujours : @lexos_accent_hi n'était
                #  employé nulle part, donc aucune assertion ne le résolvait.
                #  Le survol des boutons l'emploie maintenant, et l'a réveillé.
                for nom in sorted(noms, key=len, reverse=True):
                    v = v.replace("@" + nom, noms[nom].strip())
                decls[k.strip()] = v
        for s in sels:
            out.append((s, decls))
    return out

def specificite(sel):
    return (sel.count("#"), sel.count(".") + sel.count(":"), len(re.findall(r"(?<![#.\w-])[a-z][a-z0-9-]*", sel)))

def noeud_ok(p, n):
    nom = re.match(r"^[a-z][a-z0-9-]*", p)
    idm = re.search(r"#([\w-]+)", p)
    cls = re.findall(r"\.([\w-]+)", p)
    pse = re.findall(r":([\w-]+)", p)
    if nom and nom.group(0) != n["nom"] and p[0] != "*":
        return False
    if idm and idm.group(1) != n.get("id"):
        return False
    if any(c not in n.get("classes", []) for c in cls):
        return False
    if any(s not in n.get("etats", []) for s in pse):
        return False
    return True

def correspond(sel, chemin):
    #  chemin : liste d'ancêtres, du plus lointain au nœud lui-même.
    #  Chaque nœud : {"nom":..., "id":..., "classes":[...]}
    #
    #  LE DERNIER MORCEAU DU SÉLECTEUR EST ANCRÉ SUR LE NŒUD LUI-MÊME —
    #  c'est TOUTE la différence entre une correspondance directe et un
    #  héritage. L'ancienne version le laissait flotter : « menuitem:hover »
    #  « correspondait » à un chemin finissant par label, et le banc voyait
    #  vert un écran illisible (la couleur restait posée sur le menuitem,
    #  l'étiquette gardait la sienne). Un moteur qui confond les deux ne
    #  peut pas attraper le bogue orange-sur-orange de la photo d'Alex.
    parts = sel.split()
    if not parts or not noeud_ok(parts[-1], chemin[-1]):
        return False
    i = len(chemin) - 2
    for p in reversed(parts[:-1]):
        trouve = False
        while i >= 0:
            n = chemin[i]
            i -= 1
            if noeud_ok(p, n):
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
cat > "$BANC/bouton_survol.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"button","classes":[],"etats":["hover"]}]
J
#  L'ÉTIQUETTE À L'INTÉRIEUR DU BOUTON — le nœud qu'Alex a vu disparaître.
#  « il avait toute écriture orange bouton noir mais quand on mettait la
#  souris dessus il devenait tout orange puis non visible ». Exactement le
#  cas déjà connu des menus, jamais modélisé pour les boutons : « #login_window * »
#  correspond DIRECTEMENT à cette étiquette, et une correspondance directe bat
#  l'héritage du bouton quelle que soit la spécificité. Résoudre la couleur sur
#  le BOUTON serait vert pendant que l'écran reste illisible — c'est le piège
#  que ce banc a déjà attrapé une fois pour les menus.
cat > "$BANC/etiquette_bouton.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"button","classes":[]},
 {"nom":"label","classes":[]}]
J
cat > "$BANC/etiquette_bouton_survol.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"button","classes":[],"etats":["hover"]},
 {"nom":"label","classes":[]}]
J
#  LES BOUTONS DE LA BARRE DU HAUT — « les boutons en haut était aussi ».
#  Même nœud, même bogue, sous #panel_window cette fois.
cat > "$BANC/etiquette_indicateur.json" <<'J'
[{"nom":"window","id":"panel_window","classes":[]},
 {"nom":"button","classes":[],"etats":["hover"]},
 {"nom":"label","classes":[]}]
J
#  LE BOUTON AU REPOS — « le bouton est pas activé » (Alex : le bouton
#  ~power, Éteindre/Redémarrer, sur la page de choix d'utilisateur). Sans
#  état hover, PAS un fixture inventé : c'est exactement l'état d'un bouton
#  qu'on regarde sans y toucher, celui de la photo d'Alex.
cat > "$BANC/bouton_indicateur_repos.json" <<'J'
[{"nom":"window","id":"panel_window","classes":[]},
 {"nom":"button","classes":[]}]
J
cat > "$BANC/champ.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"entry","classes":[]}]
J
#  LE NOEUD « text » A L'INTERIEUR DU CHAMP. Depuis GTK 3.20 le contenu d'un
#  GtkEntry vit dans son propre noeud, et « #login_window * » le matche
#  DIRECTEMENT — une correspondance directe bat l'heritage du champ. Resoudre
#  la couleur sur le champ seul serait vert pendant qu'on ne voit toujours
#  rien a l'ecran : le piege deja paye pour les menus, puis pour les
#  etiquettes de boutons.
cat > "$BANC/champ_texte.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"entry","classes":[]},
 {"nom":"text","classes":[]}]
J
#  Le nom d'utilisateur n'est pas toujours un champ nu : selon la
#  configuration, c'est une LISTE de comptes, donc un combobox a lui.
cat > "$BANC/champ_liste.json" <<'J'
[{"nom":"window","id":"login_window","classes":[]},
 {"nom":"combobox","classes":[]},
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
#  LA PHOTO SUIVANTE D'ALEX — le même menu, ENCORE orange sur orange. Le cas
#  que le banc ne modélisait pas : l'ÉTIQUETTE À L'INTÉRIEUR du menuitem,
#  quand le menu EST un descendant CSS de #panel_window (un GtkMenu attaché à
#  un widget hérite de son contexte de style — c'est le cas des indicateurs
#  du greeter). « #panel_window * » correspond alors DIRECTEMENT à
#  l'étiquette, et une correspondance directe bat l'héritage du
#  menuitem:hover — quelle que soit la spécificité. Le banc précédent
#  résolvait la couleur sur le MENUITEM : vert, pendant que l'écran réel
#  restait illisible.
cat > "$BANC/etiquette_menu_panneau.json" <<'J'
[{"nom":"window","id":"panel_window","classes":[]},
 {"nom":"menubar","classes":[]},
 {"nom":"menuitem","classes":[]},
 {"nom":"menu","classes":[]},
 {"nom":"menuitem","classes":[],"etats":["hover"]},
 {"nom":"label","classes":[]}]
J
cat > "$BANC/etiquette_menu_orphelin.json" <<'J'
[{"nom":"window","id":"","classes":[]},
 {"nom":"menuitem","classes":[],"etats":["hover"]},
 {"nom":"label","classes":[]}]
J
#  ═══ LE MENU AU REPOS — la photo suivante d'Alex ═══
#  « on voit pas bien les couleurs quand on [va] pour changer d'utilisateur » :
#  le menu d'arrêt était une BARRE CLAIRE illisible, et ne redevenait lisible
#  qu'une fois la souris dessus. Tout le bloc sans ancre ne couvrait que des
#  ÉTATS (:hover, :selected) ; le REPOS n'avait aucune règle de nous. Ces
#  fixtures-ci n'ont donc AUCUN état — c'est exactement un menu qu'on regarde
#  sans y toucher, et c'est le cas que le banc ne modélisait pas.
cat > "$BANC/menu_repos.json" <<'J'
[{"nom":"window","id":"","classes":["popup"]},
 {"nom":"menu","classes":[]}]
J
cat > "$BANC/popup_repos.json" <<'J'
[{"nom":"window","id":"","classes":["popup"]}]
J
cat > "$BANC/menuitem_repos.json" <<'J'
[{"nom":"window","id":"","classes":["popup"]},
 {"nom":"menu","classes":[]},
 {"nom":"menuitem","classes":[]}]
J
cat > "$BANC/etiquette_menuitem_repos.json" <<'J'
[{"nom":"window","id":"","classes":["popup"]},
 {"nom":"menu","classes":[]},
 {"nom":"menuitem","classes":[]},
 {"nom":"label","classes":[]}]
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

#  LES BOUTONS : ORANGE PLEIN, ÉCRITURE NOIRE — demande d'Alex, « pour les
#  boutons fait le bouton orange écriture noire ». Le banc disait avant
#  « écriture #E8590C sur fond #141416 » : c'était le bouton creux d'avant, et
#  ces deux lignes-ci sont donc le banc qui suit la demande, pas un
#  assouplissement.
F="$(resout "$BANC/bouton.json" background-color)"
[ "$F" = "#E8590C" ] \
	&& ok "les boutons sont ORANGE PLEIN dès le repos" \
	|| non "fond de bouton : « $F » au lieu de #E8590C"
F="$(resout "$BANC/bouton.json" color)"
[ "$F" = "#000000" ] \
	&& ok "… et ils écrivent en NOIR dessus" \
	|| non "les boutons écrivent « $F » au lieu de #000000"

#  LA MOITIÉ QUI MANQUAIT, ET QUI EST TOUT LE BOGUE D'ALEX. Poser la couleur
#  sur le BOUTON ne suffit pas : « #login_window * » matche directement
#  l'étiquette à l'intérieur. Sans règle qui la vise, elle reste ORANGE — sur
#  un fond devenu orange. Le bouton se vide à l'écran.
F="$(resout "$BANC/etiquette_bouton.json" color)"
[ "$F" = "#000000" ] \
	&& ok "l'ÉTIQUETTE du bouton est noire elle aussi (pas seulement le bouton)" \
	|| non "étiquette de bouton = « $F » — orange sur orange, le bouton serait vide"

F="$(resout "$BANC/bouton_survol.json" background-color)"
[ "$F" = "#FF7A33" ] \
	&& ok "au survol le bouton s'éclaircit (il répond au doigt, il ne disparaît pas)" \
	|| non "fond de bouton survolé = « $F » au lieu de #FF7A33"
F="$(resout "$BANC/etiquette_bouton_survol.json" color)"
[ "$F" = "#000000" ] \
	&& ok "… et son étiquette reste noire au survol — LA PHOTO D'ALEX" \
	|| non "étiquette de bouton survolé = « $F » — « il devenait tout orange puis non visible »"

F="$(resout "$BANC/etiquette_indicateur.json" color)"
[ "$F" = "#000000" ] \
	&& ok "les boutons de la barre du HAUT restent lisibles au survol aussi" \
	|| non "étiquette d'indicateur survolé = « $F » — « les boutons en haut était aussi »"

#  « LE BOUTON EST PAS ACTIVÉ » — Alex, sur le bouton ~power (Éteindre /
#  Redémarrer) de la page de choix d'utilisateur, SANS la souris dessus.
#  Avant ce correctif, « #panel_window button » n'avait aucune règle hors
#  :hover/:active/:checked — le fond restait celui de « #panel_window * »
#  (transparent) et aucune bordure n'existait : un bouton qui ne ressemble
#  à un bouton qu'au survol se lit comme un bouton désactivé.
F="$(resout "$BANC/bouton_indicateur_repos.json" background-color)"
[ "$F" != "" ] && [ "$F" != "transparent" ] \
	&& ok "au repos, le bouton de la barre du haut a déjà un fond (« $F ») — pas juste au survol" \
	|| non "fond du bouton au repos = « $F » — invisible tant qu'on n'y touche pas, la photo d'Alex"

#  ═══ CE QU'ON TAPE DOIT SE LIRE — ET ON MESURE, ON N'AFFIRME PAS UNE TEINTE ═══
#  ALEX, DEUX PHOTOS DE « CHANGER D'UTILISATEUR » : « on voit pas l'écriture ».
#
#  Ce contrôle exigeait « #E8590C » — l'orange. Il était donc VERT sur la
#  version que montrent ses photos : il vérifiait la couleur qu'on avait
#  choisie, pas qu'on puisse lire. Une couleur en dur ne dit rien de la
#  lisibilité ; c'est le contraste qui la dit.
#
#  ET IL FAUT LE MESURER DEUX FOIS. GtkEntry ne dessine pas l'INVITE
#  (« Saisir votre mot de passe ») avec la couleur telle quelle : il lui
#  applique une opacité réduite, ~55 %, posée par le widget — aucune règle
#  CSS ne la relève. L'orange tombait de 4,9:1 à ~2:1, sous le seuil : la
#  photo. On exige donc 4,5:1 pour le texte saisi ET 3:1 pour l'invite une
#  fois estompée, ce qui écarte d'avance toute teinte trop sombre.
#  Le calcul WCAG, écrit une fois dans un fichier : l'imbriquer dans la
#  fonction ferait entrer un « heredoc » dans un autre, et c'est le genre de
#  détail qui casse un banc sans rapport avec ce qu'il éprouve.
cat > "$BANC/contraste.py" <<'CALC'
import sys


def rvb(h):
    h = h.strip().lstrip("#")
    if len(h) != 6:
        raise ValueError(h)
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def lum(c):
    c = [x / 255 for x in c]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


try:
    t, f, a = rvb(sys.argv[1]), rvb(sys.argv[2]), float(sys.argv[3])
except Exception:
    print("0")
    raise SystemExit
#  L'estompage se fait SUR le fond : c'est ce que l'oeil voit, pas une
#  couleur flottant dans le vide.
vu = [t[i] * a + f[i] * (1 - a) for i in range(3)]
x, y = lum(vu) + 0.05, lum(f) + 0.05
print("%.2f" % (max(x, y) / min(x, y)))
CALC

FOND="$(resout "$BANC/champ.json" background-color)"
contraste_champ() { # contraste_champ <couleur> <fond> <alpha>
	python3 "$BANC/contraste.py" "$1" "$2" "$3"
}
for PAIRE in "champ:le champ du mot de passe" "champ_texte:le nœud texte du champ" \
             "champ_liste:le champ de la liste des comptes"; do
	NOEUD="${PAIRE%%:*}"; QUOI="${PAIRE#*:}"
	F="$(resout "$BANC/$NOEUD.json" color)"
	if [ -z "$F" ]; then
		non "$QUOI n'a aucune couleur de texte : elle serait héritée, donc imprévisible"
		continue
	fi
	C="$(contraste_champ "$F" "${FOND:-#0B0B0C}" 1.0)"
	CI="$(contraste_champ "$F" "${FOND:-#0B0B0C}" 0.55)"
	if [ "${C%%.*}" -ge 4 ] && [ "${CI%%.*}" -ge 3 ]; then
		ok "$QUOI se lit : $C:1 pour la saisie, $CI:1 pour l'invite estompée ($F)"
	else
		non "$QUOI illisible : $C:1 pour la saisie, $CI:1 pour l'invite ($F sur $FOND)"
	fi
done

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

	#  L'étiquette DANS le menuitem — le nœud que la photo suivante d'Alex a
	#  montré encore orange. Sous #panel_window, « #panel_window * » la
	#  matche directement : seule une règle plus spécifique visant
	#  l'étiquette elle-même peut la faire passer noire.
	F="$(resout "$BANC/etiquette_menu_panneau.json" color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : l'ÉTIQUETTE d'un menuitem survolé sous #panel_window passe noire" \
		|| non "priorité $PRIO : étiquette sous #panel_window = « $F » — la photo d'Alex, encore"
	F="$(resout "$BANC/etiquette_menu_orphelin.json" color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : … et celle d'un popup SANS ancêtre nommé aussi" \
		|| non "priorité $PRIO : étiquette sans ancêtre = « $F »"

	#  ═══ LE MENU AU REPOS — « on voit pas bien les couleurs » ═══
	#  Un menu qu'on REGARDE, sans souris dessus. Le fond du popup doit être
	#  NOIR et l'écriture ORANGE, comme la boîte de connexion : c'est le cas
	#  qui laissait une barre claire illisible jusqu'au survol.
	F="$(resout "$BANC/menu_repos.json" background-color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : au REPOS, le fond du menu est noir" \
		|| non "priorité $PRIO : fond du menu au repos = « $F » — la barre claire d'Alex"
	F="$(resout "$BANC/popup_repos.json" background-color "$PRIO")"
	[ "$F" = "#000000" ] \
		&& ok "priorité $PRIO : … et la fenêtre du popup elle-même aussi" \
		|| non "priorité $PRIO : fond de window.popup = « $F »"
	F="$(resout "$BANC/menuitem_repos.json" color "$PRIO")"
	[ "$F" = "#E8590C" ] \
		&& ok "priorité $PRIO : au REPOS, une ligne de menu écrit en orange" \
		|| non "priorité $PRIO : écriture d'un menuitem au repos = « $F » — illisible"
	F="$(resout "$BANC/etiquette_menuitem_repos.json" color "$PRIO")"
	[ "$F" = "#E8590C" ] \
		&& ok "priorité $PRIO : … y compris son ÉTIQUETTE (la leçon déjà payée deux fois)" \
		|| non "priorité $PRIO : étiquette d'un menuitem au repos = « $F »"
done

#  ET LE SURVOL DOIT TOUJOURS L'EMPORTER SUR LE REPOS. Les règles de repos
#  qu'on vient d'ajouter sont écrites AVANT « :hover » exprès : si elles
#  passaient après, elles repeindraient la ligne survolée et on aurait
#  échangé un bogue contre un autre.
REPOS="$(grep -n '^menuitem {$' "$CSS" | head -1 | cut -d: -f1)"
SURVOL="$(grep -n '^menuitem:hover {$' "$CSS" | head -1 | cut -d: -f1)"
if [ -n "$REPOS" ] && [ -n "$SURVOL" ] && [ "$REPOS" -lt "$SURVOL" ]; then
	ok "l'état de repos est écrit AVANT le survol (le survol garde le dernier mot)"
else
	non "ordre des états : repos=$REPOS survol=$SURVOL — le repos repeindrait le survol"
fi

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
#  LE FOYER DE LIGHTDM GARDE UN gtk.css UTILISATEUR, ET C'EST VOULU.
#  Ailleurs, le style de LexOS est descendu au rang de THEME pour cesser
#  d'ecraser les applications. Ici NON : le greeter a son propre theme, et
#  la seule facon de passer devant est la priorite utilisateur. Ce n'est pas
#  un oubli de la bascule, c'est le seul endroit ou l'ancien mecanisme est
#  le bon.
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

# =============================================================================
titre "La liste des comptes se LIT — mesuré sur les vrais nœuds de GTK"
# =============================================================================
#  ALEX, PHOTO : « la page pour changer d'utilisateur, on voit pas les
#  écritures ». Le champ n'était pas vide : en éclaircissant sa photo on lit
#  « invité (LexOS) — session limitée », en NOIR sur un fond quasi noir.
#
#  CE BANC MESURE, IL NE GREPPE PAS, et c'est tout l'enjeu. Les règles
#  fautives disaient « color: #FFFFFF » — un contrôle qui aurait cherché
#  cette chaîne aurait été VERT pendant que l'écran était illisible. Elles
#  visaient « combobox entry », « combobox text » et « combobox button
#  label » : aucun de ces trois nœuds n'existe dans l'arbre que GTK 3.24
#  construit réellement. On demande donc à GTK la couleur résolue sur le
#  chemin de widget exact, et on regarde le CONTRASTE.
#  ON CHERCHE L'INTERPRÉTEUR QUI A « gi », pas le premier venu. Sur une
#  machine où deux python cohabitent, « python3 » peut très bien être celui
#  qui ne l'a pas — le banc sauterait alors sur une machine parfaitement
#  équipée, et le défaut repasserait inaperçu.
PY_GI=""
for P in python3 python3.13 python3.12 python3.11; do
	command -v "$P" >/dev/null 2>&1 || continue
	"$P" -c "import gi; gi.require_version('Gtk','3.0')" 2>/dev/null || continue
	PY_GI="$P"; break
done
if [ -z "$PY_GI" ] || ! command -v xvfb-run >/dev/null 2>&1; then
	saute "gi/GTK ou Xvfb absents : les couleurs de la liste n'ont PAS été mesurées"
else
	cat > "$BANC/liste.py" <<'PYCX'
import sys, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk
Gtk.init([])
prov = Gtk.CssProvider()
prov.load_from_path(sys.argv[1])

def ctx(noeuds):
    ch = Gtk.WidgetPath()
    for nom, classes in noeuds:
        i = ch.append_type(Gtk.Widget.__gtype__)
        ch.iter_set_object_name(i, nom)
        for c in classes:
            ch.iter_add_class(i, c)
    ch.iter_set_name(0, "login_window")
    c = Gtk.StyleContext(); c.set_path(ch)
    c.add_provider(prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    return c

#  L'arbre vient de gtk_style_context_to_string() sur un vrai GtkComboBox :
#  combobox > box.linked > button.combo > box > cellview.
BASE = [("window", ["background"]), ("combobox", []),
        ("box", ["linked", "horizontal"]), ("button", ["combo"]),
        ("box", ["horizontal"])]

def lum(c):
    def v(x):
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * v(c.red) + 0.7152 * v(c.green) + 0.0722 * v(c.blue)

fond = ctx(BASE[:4]).get_property("background-color", Gtk.StateFlags.NORMAL)
for nom, chemin in (("cellview", BASE + [("cellview", [])]),
                    ("arrow",    BASE + [("arrow", [])])):
    t = ctx(chemin).get_color(Gtk.StateFlags.NORMAL)
    a, b = sorted((lum(fond), lum(t)))
    ratio = (b + 0.05) / (a + 0.05)
    teinte = "#%02X%02X%02X" % (round(t.red*255), round(t.green*255), round(t.blue*255))
    #  4,5:1 est le seuil AA pour du texte courant — le meme que celui deja
    #  employe pour l'invite du terminal.
    verdict = "OK" if ratio >= 4.5 else "NON"
    mot = "se lit sur le fond de la liste" if ratio >= 4.5 else "ne se lit PAS (seuil 4,5)"
    print("%s|« %s » %s : %.2f:1 (%s sur %s)" % (
        verdict, nom, mot, ratio, teinte,
        "#%02X%02X%02X" % (round(fond.red*255), round(fond.green*255), round(fond.blue*255))))
PYCX
	#  ON NE GARDE QUE LES LIGNES DE VERDICT. xvfb-run et GTK bavardent sur
	#  la sortie standard (« dbind-WARNING », entre autres) ; sans ce filtre,
	#  une de ces lignes se faisait lire comme un verdict et le banc affichait
	#  un rouge SANS MESSAGE — un échec qui n'apprend rien à personne.
	SORTIE_CX="$(xvfb-run -a "$PY_GI" "$BANC/liste.py" "$CSS" 2>/dev/null \
		| grep -E '^(OK|NON)\|' || true)"
	if [ -z "$SORTIE_CX" ]; then
		non "la mesure des couleurs de la liste n'a rien rendu"
	else
		while IFS='|' read -r VERDICT MESSAGE; do
			[ -n "$VERDICT" ] || continue
			[ "$VERDICT" = "OK" ] && ok "$MESSAGE" || non "$MESSAGE"
		done <<EOF
$SORTIE_CX
EOF
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
