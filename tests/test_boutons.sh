#!/usr/bin/env bash
# =============================================================================
#  « Regarde que tous les boutons soient corrects » — Alex, après la photo
# =============================================================================
#  CE QUI EST ARRIVÉ, ET POURQUOI UN ŒIL NE SUFFIT PAS.
#
#  Sur la fenêtre de bienvenue, le libellé des boutons était posé sur un
#  rectangle NOIR à l'intérieur du bouton orange, et écrit en BLANC. Deux
#  défauts distincts, invisibles dans le code pris règle par règle :
#
#    · la règle « écriture blanche partout » repeignait les libellés qui sont
#      DANS un bouton — un enfant qui porte sa propre couleur n'hérite pas de
#      celle du parent, si bien que le noir demandé par le bouton n'arrivait
#      jamais au texte ;
#    · GTK bâtit un bouton en « button > box > label » : peindre le bouton ne
#      repeint pas ses enfants, et le fond sombre du thème de base restait
#      dessous. C'est lui, le rectangle noir.
#
#  Chercher ça à l'œil, c'est relire une feuille de 500 lignes en tenant la
#  cascade CSS dans sa tête. Ce banc le fait à la place : il GÉNÈRE la feuille
#  pour de vrai — huit accents, deux modes — puis MESURE le contraste de
#  chaque famille de boutons. 4,5:1 est le seuil de lisibilité courant ;
#  blanc sur l'orange de LexOS n'en donne que 3,4.
# =============================================================================
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

ACCENTS="orange orange-rouge bleu rouge vert gris violet neon"

# --- Mesurer, plutôt que regarder -------------------------------------------
mesure() {   # <fichier css> ; imprime une ligne par famille de boutons
	python3 - "$1" <<'PY'
import re, sys

css = open(sys.argv[1], encoding="utf-8").read()
#  Les commentaires portent des exemples de couleurs ; les lire fausserait
#  tout. On les retire avant d'analyser quoi que ce soit.
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

def lum(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def contraste(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

#  Chaque règle : (sélecteurs, corps).
regles = re.findall(r"([^{}]+)\{([^{}]*)\}", css)

def valeur(corps, prop):
    m = re.search(rf"(?<![-\w]){prop}\s*:\s*([^;]+)", corps)
    return m.group(1).strip() if m else None

#  Les familles qu'Alex voit à l'écran. Le libellé sert au message d'erreur.
FAMILLES = [
    ("window button",          "boutons de fenêtre et de dialogue"),
    ("headerbar button",       "boutons de barre de titre"),
    ("toolbar button",         "boutons de barre d'outils"),
    ("popover button",         "boutons de menu surgissant"),
    ("combobox button",        "listes déroulantes"),
    ("treeview header button", "en-têtes de colonnes"),
    ("button.suggested-action", "bouton d'action conseillée"),
    ("button.destructive-action", "bouton de suppression"),
]

for cle, libelle in FAMILLES:
    fond = txt = None
    for sels, corps in regles:
        sl = " ".join(sels.split())
        #  On ne retient que la déclaration de base : pas :hover, pas :disabled.
        if ":" in sl.replace("::", ""):
            continue
        if not re.search(rf"(^|,\s*){re.escape(cle)}(\s*,|\s*$)", sl):
            continue
        f = valeur(corps, "background-color")
        t = valeur(corps, "color")
        if f and f.startswith("#"):
            fond = f
        if t and t.startswith("#"):
            txt = t
    if fond and txt:
        print(f"{cle}|{libelle}|{fond}|{txt}|{contraste(fond, txt):.2f}")
    else:
        print(f"{cle}|{libelle}|{fond or '-'}|{txt or '-'}|MANQUE")
PY
}

# ═════════════════════════════════════════════════════════════════════════════
titre "1. Chaque bouton, chaque accent, chaque mode — le texte est-il lisible ?"
PIRE="999"; PIRE_QUOI=""
TOTAL=0
for MODE in sombre clair; do
	for A in $ACCENTS; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
			bash "$GEN" --target "$BANC/t" --mode "$MODE" "$A" >/dev/null 2>&1
		CSS="$BANC/t/.config/gtk-3.0/gtk.css"
		[ -r "$CSS" ] || { non "$A/$MODE : aucune feuille produite"; continue; }
		while IFS='|' read -r cle libelle fond txt ratio; do
			TOTAL=$((TOTAL + 1))
			if [ "$ratio" = "MANQUE" ]; then
				non "$A/$MODE · $libelle : fond ou couleur absent (fond=$fond texte=$txt)"
				continue
			fi
			if awk -v r="$ratio" 'BEGIN{exit !(r < 4.5)}'; then
				non "$A/$MODE · $libelle : $txt sur $fond = ${ratio}:1 — sous 4,5:1, illisible"
			fi
			if awk -v r="$ratio" -v p="$PIRE" 'BEGIN{exit !(r < p)}'; then
				PIRE="$ratio"; PIRE_QUOI="$A/$MODE · $libelle ($txt sur $fond)"
			fi
		done < <(mesure "$CSS")
	done
done
[ "$ECHOUES" -eq 0 ] && ok "$TOTAL familles de boutons mesurées, toutes au-dessus de 4,5:1"
printf '     \033[2mle plus juste : %s = %s:1\033[0m\n' "$PIRE_QUOI" "$PIRE"

# ═════════════════════════════════════════════════════════════════════════════
titre "2. Le libellé prend la couleur de SON bouton"
rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
	bash "$GEN" --target "$BANC/t" orange >/dev/null 2>&1
CSS="$BANC/t/.config/gtk-3.0/gtk.css"

#  On lit le BLOC en entier, pas deux lignes après le sélecteur : la première
#  version faisait « grep -A2 » et ratait « color: inherit » dès qu'on ajoutait
#  une propriété avant lui. Un banc qui rate sa cible est pire qu'un banc absent.
BLOC_BTN="$(sed -n '/^button label, button box/,/^}/p' "$CSS")"
[ -n "$BLOC_BTN" ] \
	&& ok "la règle des enfants de bouton existe" \
	|| non "plus de règle « button label, button box » — le blanc général reprendrait le dessus"
printf '%s' "$BLOC_BTN" | grep -q 'color: inherit' \
	&& ok "elle propage la couleur du bouton (color: inherit)" \
	|| non "sans « color: inherit », le libellé garde le blanc général"

#  LE COMBINATEUR, ET C'EST LA LEÇON DE LA 72. Un « > » ne franchit qu'un
#  étage : « button > box » rate « button > box > box », et le fond noir y
#  reste. La règle doit employer la DESCENDANCE, qui ne présume d'aucune
#  profondeur.
printf '%s' "$BLOC_BTN" | head -2 | grep -q '>' \
	&& non "la règle emploie « > » : elle ratera les boutons plus profonds d'un étage" \
	|| ok "et elle emploie la descendance, pas un enfant direct à profondeur devinée"

#  La règle générale « écriture blanche partout » doit venir AVANT celle des
#  libellés de boutons, sinon elle la reprend : à spécificité égale, c'est la
#  dernière qui gagne.
LIGNE_GEN="$(grep -n '^label, .label,' "$CSS" | head -1 | cut -d: -f1)"
LIGNE_BTN="$(grep -n 'button label' "$CSS" | head -1 | cut -d: -f1)"
if [ -n "$LIGNE_GEN" ] && [ -n "$LIGNE_BTN" ] && [ "$LIGNE_BTN" -gt "$LIGNE_GEN" ]; then
	ok "et elle est posée APRÈS la règle générale (sinon celle-ci la reprend)"
else
	non "l'ordre des deux règles est faux : générale=$LIGNE_GEN, boutons=$LIGNE_BTN"
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "3. La cascade résolue sur un vrai arbre, pas une recherche de texte"
#  POURQUOI CETTE SECTION A ÉTÉ RÉÉCRITE.
#
#  Sa première version cherchait la CHAÎNE « button > label, button > box »
#  dans la feuille, et se déclarait satisfaite de la trouver. Elle a donc dit
#  vert sur un correctif INERTE : la règle existait bien, mais « color:
#  inherit » sur le libellé héritait du BLANC de la box intermédiaire — la
#  règle des fonds donne explicitement color:#FFFFFF à « box, grid » — au lieu
#  du noir du bouton. Blanc sur orange, 3,58:1 : exactement le défaut que le
#  correctif prétendait réparer.
#
#  Un banc qui vérifie la PRÉSENCE d'une règle ne vérifie rien. Celui-ci
#  RÉSOUT la cascade sur des arbres de nœuds réels — sélecteurs, spécificité,
#  héritage — et mesure la couleur qui arrive vraiment sur le texte.
cascade() {   # <css> ; sort une ligne par forme de bouton
	python3 - "$1" <<'PY'
import re, sys

css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
#  RETIRER LES DECLARATIONS « @…; » AVANT DE DECOUPER LES REGLES.
#  Sans ca, le bloc @define-color qui precede la regle des fonds se retrouve
#  COLLE a sa liste de selecteurs (le decoupage capture tout ce qui separe deux
#  accolades), et un filtre « @ dans les selecteurs » ecarte alors la regle la
#  plus importante de la feuille — celle qui peint « box, grid » en noir sur
#  blanc. C'est exactement ce qui est arrive : le moteur a declare tous les
#  boutons lisibles en ayant perdu de vue la seule regle qui les rendait
#  illisibles.
css = re.sub(r"@[a-zA-Z-]+[^;{}]*;", "", css)

#  --- Un mini-moteur CSS : juste ce qu'il faut pour les sélecteurs employés ici
def analyse_simple(bout):
    m = re.match(r"^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$", bout)
    if not m:
        return None
    nom = m.group(1)
    classes = set(m.group(2).split(".")) - {""}
    return (nom, classes)

def analyse_selecteur(sel):
    """→ liste de (combinateur, nom, classes) ; combinateur ' ' ou '>'."""
    sel = sel.strip()
    if not sel or "*" in sel or "[" in sel:
        return None
    morceaux = re.split(r"\s*(>)\s*|\s+", sel)
    morceaux = [m for m in morceaux if m]
    suite, comb = [], " "
    for m in morceaux:
        if m == ">":
            comb = ">"
            continue
        simple = analyse_simple(m)
        if simple is None:
            return None
        suite.append((comb, simple[0], simple[1]))
        comb = " "
    return suite

def correspond(suite, chemin):
    """chemin = [(nom, classes), …] de la racine à la feuille."""
    def teste(i, k):        # i : index dans suite (depuis la fin), k : index chemin
        if i < 0:
            return True
        comb, nom, classes = suite[i]
        if k < 0:
            return False
        n, c = chemin[k]
        if (nom and nom != n) or not classes <= c:
            if i == len(suite) - 1:
                return False
            if comb == ">":
                return False
            return teste(i, k - 1)
        if comb == ">" or i == 0:
            return teste(i - 1, k - 1)
        for j in range(k - 1, -2, -1):
            if teste(i - 1, j):
                return True
        return False
    #  Le dernier simple doit matcher la feuille elle-même.
    comb, nom, classes = suite[-1]
    n, c = chemin[-1]
    if (nom and nom != n) or not classes <= c:
        return False
    return teste(len(suite) - 2, len(chemin) - 2) if len(suite) > 1 else True

def specificite(suite):
    b = sum(len(cl) for _, _, cl in suite)
    c = sum(1 for _, nom, _ in suite if nom)
    return (b, c)

REGLES = []
for sels, corps in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    if "@" in sels:
        continue
    decl = {}
    for d in corps.split(";"):
        if ":" in d:
            k, v = d.split(":", 1)
            decl[k.strip()] = v.strip()
    for sel in sels.split(","):
        suite = analyse_selecteur(sel)
        if suite and (":" not in sel):
            REGLES.append((suite, specificite(suite), len(REGLES), decl))

def resoudre(chemin, prop, herite):
    """Valeur calculée de prop sur la feuille de `chemin`."""
    gagnante, meilleure = None, None
    for suite, spec, ordre, decl in REGLES:
        if prop not in decl:
            continue
        if not correspond(suite, chemin):
            continue
        cle = (spec, ordre)
        if meilleure is None or cle > meilleure:
            meilleure, gagnante = cle, decl[prop]
    if gagnante == "inherit":
        return resoudre(chemin[:-1], prop, herite) if len(chemin) > 1 else None
    if gagnante is None and herite and len(chemin) > 1:
        return resoudre(chemin[:-1], prop, herite)
    return gagnante

#  --- Les formes que GTK bâtit réellement pour un bouton ---------------------
FORMES = [
    ("texte seul",            [("window", set()), ("button", set()), ("label", set())]),
    ("icone + texte",         [("window", set()), ("button", set()), ("box", set()), ("label", set())]),
    ("boite imbriquee",       [("window", set()), ("button", set()), ("box", set()), ("box", set()), ("label", set())]),
    ("grille interne",        [("window", set()), ("button", set()), ("grid", set()), ("label", set())]),
    ("action conseillee",     [("window", set()), ("button", {"suggested-action"}), ("box", set()), ("label", set())]),
    ("suppression",           [("window", set()), ("button", {"destructive-action"}), ("box", set()), ("label", set())]),
    ("dialogue, icone+texte", [("dialog", set()), ("button", set()), ("box", set()), ("label", set())]),
]

def lum(h):
    h = h.lstrip("#")
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def contraste(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

for nom, chemin in FORMES:
    txt = resoudre(chemin, "color", True)
    #  Le fond visible : le premier ancêtre (en remontant) qui n'est pas
    #  transparent. C'est ce que l'œil voit derrière le texte.
    fond = None
    for k in range(len(chemin), 0, -1):
        f = resoudre(chemin[:k], "background-color", False)
        if f and f.startswith("#"):
            fond = f
            break
        if f == "transparent":
            continue
    if not (txt and txt.startswith("#") and fond):
        print(f"{nom}|{txt}|{fond}|ILLISIBLE")
        continue
    print(f"{nom}|{txt}|{fond}|{contraste(txt, fond):.2f}")
PY
}

#  COMPTEUR LOCAL, et pas le global : la première version lisait $ECHOUES,
#  si bien qu'un échec d'une section PRÉCÉDENTE faisait disparaître le verdict
#  de celle-ci. On ne saurait plus si la cascade est saine ou seulement muette.
MAUVAIS3=0; VU3=0
for MODE in sombre clair; do
	for A in orange bleu neon; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
			bash "$GEN" --target "$BANC/t" --mode "$MODE" "$A" >/dev/null 2>&1
		while IFS='|' read -r forme txt fond ratio; do
			VU3=$((VU3 + 1))
			if [ "$ratio" = "ILLISIBLE" ]; then
				non "$A/$MODE · $forme : couleur ou fond irrésolus (texte=$txt fond=$fond)"
				MAUVAIS3=$((MAUVAIS3 + 1))
			elif awk -v r="$ratio" 'BEGIN{exit !(r < 4.5)}'; then
				non "$A/$MODE · $forme : $txt sur $fond = ${ratio}:1 — le texte du bouton est illisible"
				MAUVAIS3=$((MAUVAIS3 + 1))
			fi
		done < <(cascade "$BANC/t/.config/gtk-3.0/gtk.css")
	done
done
if [ "$VU3" = "0" ]; then
	non "le moteur de cascade n'a résolu AUCUNE forme — il ne prouve rien"
elif [ "$MAUVAIS3" = "0" ]; then
	ok "$VU3 formes de bouton résolues à la cascade, toutes lisibles (3 accents x 2 modes)"
fi

#  Et la forme qui a piégé la première version, nommée à part pour que le
#  message dise quelque chose le jour où elle revient.
rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
	bash "$GEN" --target "$BANC/t" orange >/dev/null 2>&1
LIGNE="$(cascade "$BANC/t/.config/gtk-3.0/gtk.css" | grep '^icone + texte|')"
COUL="$(printf '%s' "$LIGNE" | cut -d'|' -f2)"
[ "$COUL" = "#000000" ] \
	&& ok "bouton à icône : le libellé est NOIR — il n'hérite plus du blanc de la box" \
	|| non "bouton à icône : libellé $COUL au lieu de #000000 — c'est le défaut de la 72"

# ═════════════════════════════════════════════════════════════════════════════
titre "4. Les faux boutons ne sont pas devenus orange"
#  Le revers du correctif : à force de peindre, on repeint les listes
#  déroulantes et les en-têtes de colonnes. Alex l'avait signalé une fois
#  (« les listes en gros orange ») — ça ne doit pas revenir.
ACC="$(sed -n '/^window button, dialog button/,/}/p' "$CSS" | grep -oE 'background-color: #[0-9A-Fa-f]{6}' | grep -oE '#[0-9A-Fa-f]{6}' | head -1)"
STRUCT="$(sed -n '/^combobox button, combobox button.combo/,/}/p' "$CSS" | grep -oE 'background-color: #[0-9A-Fa-f]{6}' | grep -oE '#[0-9A-Fa-f]{6}')"
[ -n "$ACC" ] && [ -n "$STRUCT" ] && [ "$ACC" != "$STRUCT" ] \
	&& ok "listes déroulantes ($STRUCT) ≠ boutons ($ACC)" \
	|| non "les faux boutons ont repris la couleur d'accent (acc=$ACC struct=$STRUCT)"

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
