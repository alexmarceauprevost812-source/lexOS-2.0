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

grep -q 'button label' "$CSS" && grep -A2 'button label' "$CSS" | grep -q 'color: inherit' \
	&& ok "« button label » hérite au lieu de garder le blanc général" \
	|| non "le libellé du bouton ne suit pas la couleur du bouton — texte blanc sur orange, 3,4:1"

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
titre "3. Plus de rectangle noir derrière le texte"
grep -q 'button > label, button > box' "$CSS" \
	&& ok "les enfants du bouton sont explicitement dépeints" \
	|| non "les enfants du bouton gardent leur fond — c'est le rectangle noir de la photo"
BLOC="$(sed -n '/button > label, button > box/,/}/p' "$CSS")"
printf '%s' "$BLOC" | grep -q 'background-color: transparent' \
	&& ok "fond transparent" || non "le fond des enfants n'est pas remis à transparent"
printf '%s' "$BLOC" | grep -q 'background-image: none' \
	&& ok "et pas de dégradé hérité du thème de base" || non "background-image pas neutralisé"

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
