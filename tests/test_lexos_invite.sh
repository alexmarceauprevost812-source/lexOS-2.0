#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'INVITE du terminal — sa forme et ses couleurs
# =============================================================================
#  ALEX, PHOTO DU TERMINAL, DEUX REMARQUES DANS LA MÊME MINUTE :
#
#    1. « l'écriture, la ligne est pas complète et a déjà une espace — faire
#       en sorte que ça suive ---> ». L'invite tenait sur DEUX lignes :
#
#           lex@lexos ~
#           ❯
#
#       parce que PS1 portait un saut de ligne juste avant le chevron.
#
#    2. « écriture blanc pour écriture de utilisateur, vert pour lexos ».
#       Le chemin et le chevron étaient ORANGE, et la frappe héritait de cet
#       orange (PS1 se termine par une couleur qu'on ne referme pas).
#
#  POURQUOI CE BANC EXISTE, ALORS QUE LE TERMINAL EN AVAIT DÉJÀ UN.
#  test_lexos_terminal.sh éprouve le terminalrc et le canal Xfconf — le
#  fond, la police, les seize couleurs. Il ne touche PAS à PS1 : on a
#  cherché, aucun banc de ce dépôt ne lisait interactive.sh. L'invite était
#  la seule pièce visible à chaque seconde d'utilisation à n'avoir aucun
#  filet. Les deux défauts ci-dessus ont donc pu tenir sans que rien ne
#  proteste.
#
#  COMMENT ON L'ÉPROUVE — PAR L'EXÉCUTION, PAS PAR LA LECTURE.
#  On ne cherche pas « \n » dans le fichier : on lance un VRAI bash
#  interactif, on lui fait lire interactive.sh, et on lui demande de
#  DÉVELOPPER PS1 (« ${PS1@P} », l'opérateur de bash qui applique les
#  échappements d'invite). Ce qui revient est exactement ce que le terminal
#  affichera, séquences ANSI comprises. Un banc qui aurait lu le fichier
#  aurait manqué que « \n » n'est pas le seul chemin vers une deuxième
#  ligne — et surtout, il n'aurait rien dit des COULEURS, qui ne sont pas
#  dans ce fichier : elles viennent de terminal.env, écrit par
#  lexos-theme-gen. Ici on génère les deux modes pour de vrai et on vérifie
#  que la couleur du fichier est bien celle qui ressort dans l'invite.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$RACINE/config/includes.chroot/usr/share/lexos/shell/interactive.sh"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
#  Depuis le 2026-10-31, l'invite par défaut est « pro » (le petit bateau,
#  section en fin de banc). Ce banc éprouve l'invite CLASSIQUE : son dossier
#  de réglages « vide » la choisit explicitement.
mkdir -p "$BANC/vide-config/lexos" && printf 'classique\n' > "$BANC/vide-config/lexos/invite"
trap 'rm -rf "$BANC"' EXIT
mkdir -p "$BANC/home"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$SH" ] || { non "interactive.sh introuvable"; exit 1; }

#  Le VRAI développement de PS1, par bash lui-même.
#    invite <code-retour> <COLORTERM> [XDG_CONFIG_HOME]
#  --norc --noprofile : le banc ne doit pas hériter du .bashrc de la machine
#  qui le fait tourner ; -i pour que « $- » contienne « i », sans quoi
#  interactive.sh se retire avant même de poser l'invite.
invite() {
	local code="$1" ct="$2" xdg="${3:-$BANC/vide-config}"
	#  Ce banc éprouve l'invite CLASSIQUE (l'invite « pro » a sa section).
	[ -e "$xdg/lexos/invite" ] || { mkdir -p "$xdg/lexos" && printf 'classique\n' > "$xdg/lexos/invite"; }
	HOME="$BANC/home" XDG_CONFIG_HOME="$xdg" COLORTERM="$ct" TERM=xterm-256color \
		bash --norc --noprofile -i -c \
		". \"$SH\"; __lexos_code=$code; printf '%s' \"\${PS1@P}\"" 2>/dev/null
}

#  Découpe l'invite développée en segments : ('e', séquence) pour une
#  séquence ANSI, ('t', texte) pour ce qui s'affiche. Les marqueurs \001 et
#  \002 (« ce qui suit ne prend pas de place à l'écran ») sont retirés : ils
#  servent à bash pour compter les colonnes, pas au terminal.
#  Le découpeur est écrit dans un FICHIER, et pas donné à python sur son
#  entrée standard : « python3 - <<PY » consomme justement cette entrée pour
#  y lire son propre script, et sys.stdin ne rend alors plus rien. Le banc
#  a commencé sa vie ainsi et ne mesurait donc RIEN — vingt lignes de
#  verdicts calculés sur une chaîne vide.
DECOUPE="$BANC/segments.py"
cat > "$DECOUPE" <<'PY'
import re, sys
brut = sys.stdin.buffer.read().decode("utf-8", "replace")
brut = brut.replace("\001", "").replace("\002", "")
for m in re.finditer(r"\033\[([0-9;]*)m|([^\033]+)", brut):
    if m.group(1) is not None:
        print("e\t" + m.group(1))
    else:
        print("t\t" + m.group(2).replace("\n", "<SAUT-DE-LIGNE>"))
PY
segments() { python3 "$DECOUPE"; }

#  Le contraste d'une séquence (38;2;r;g;b ou 38;5;n, avec ou sans « 1; »)
#  sur un fond #hex — dans un FICHIER, pour la même raison que le découpeur.
#  L'échappement, posé UNE fois : deux sections s'en servent, et la
#  définir au plus tard la rendait introuvable à la première sous « set -u ».
ESCB=$'\033'
CONTRASTE="$BANC/contraste.py"
cat > "$CONTRASTE" <<'PYC'
import sys, re
def lum(c):
    v = [int(c[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
s = sys.argv[1]
m = re.match(r"(?:1;)?38;2;(\d+);(\d+);(\d+)$", s)
if m:
    fg = "#%02X%02X%02X" % tuple(int(g) for g in m.groups())
else:
    m = re.match(r"(?:1;)?38;5;(\d+)$", s)
    if not m:
        print("0"); sys.exit()
    n = int(m.group(1)); niv = [0, 95, 135, 175, 215, 255]
    if n >= 232:
        v = 8 + (n-232)*10; fg = "#%02X%02X%02X" % (v, v, v)
    elif n >= 16:
        k = n-16; fg = "#%02X%02X%02X" % (niv[k//36], niv[(k//6) % 6], niv[k % 6])
    else:
        print("0"); sys.exit()
a, b = lum(fg), lum(sys.argv[2])
if a < b:
    a, b = b, a
print("%.2f" % ((a+0.05)/(b+0.05)))
PYC

#  Le CONTRASTE dit si ça se lit sur le fond. Il ne dit RIEN de la distance
#  entre deux couleurs : le nom orange et le curseur orange peuvent très
#  bien avoir le même contraste et être indiscernables. D'où ce second
#  outil — écart perçu (ΔE, CIELAB) et TEINTE, en degrés.
ECART="$BANC/ecart.py"
cat > "$ECART" <<'PYE'
import sys, re
def hexa(s):
    if s.startswith("#"):
        return s
    m = re.match(r"(?:1;)?38;2;(\d+);(\d+);(\d+)$", s)
    if m:
        return "#%02X%02X%02X" % tuple(int(g) for g in m.groups())
    m = re.match(r"(?:1;)?38;5;(\d+)$", s)
    if not m:
        return None
    n = int(m.group(1)); niv = [0, 95, 135, 175, 215, 255]
    if n >= 232:
        v = 8 + (n-232)*10; return "#%02X%02X%02X" % (v, v, v)
    if n >= 16:
        k = n-16; return "#%02X%02X%02X" % (niv[k//36], niv[(k//6) % 6], niv[k % 6])
    return None
def lin(c):
    c /= 255.0
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def rgb(h):
    return tuple(int(h[i:i+2], 16) for i in (1, 3, 5))
def lab(h):
    r, g, b = (lin(v) for v in rgb(h))
    X = 0.4124*r+0.3576*g+0.1805*b; Y = 0.2126*r+0.7152*g+0.0722*b
    Z = 0.0193*r+0.1192*g+0.9505*b
    def f(t):
        return t**(1/3) if t > 0.008856 else 7.787*t+16/116
    fx, fy, fz = f(X/0.95047), f(Y/1.0), f(Z/1.08883)
    return (116*fy-16, 500*(fx-fy), 200*(fy-fz))
def teinte(h):
    r, g, b = rgb(h)
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        return -1.0
    if mx == r:
        t = 60*(((g-b)/d) % 6)
    elif mx == g:
        t = 60*(((b-r)/d) + 2)
    else:
        t = 60*(((r-g)/d) + 4)
    return t
mode = sys.argv[1]
a = hexa(sys.argv[2])
if a is None:
    print("-1"); sys.exit()
if mode == "teinte":
    print("%.1f" % teinte(a)); sys.exit()
b = hexa(sys.argv[3])
if b is None:
    print("-1"); sys.exit()
print("%.1f" % (sum((x-y)**2 for x, y in zip(lab(a), lab(b)))**0.5))
PYE

# =============================================================================
titre "1. UNE SEULE LIGNE — « faire en sorte que ça suive --> »"
# =============================================================================
P_OK="$(invite 0 truecolor)"
if [ -z "$P_OK" ]; then
	non "bash n'a rien développé : PS1 est vide (interactive.sh s'est-il retiré ?)"
else
	#  PAS « grep -q $'\n' » : grep coupe son motif AUX sauts de ligne, on
	#  lui donnerait donc un motif VIDE, qui répond oui sur n'importe quoi.
	#  Le filtrage de motif de bash, lui, compare la chaîne entière.
	case "$P_OK" in
		*$'\n'*)
			non "l'invite contient encore un saut de ligne — elle tient sur deux lignes"
			printf '%s' "$P_OK" | segments | sed 's/^/       /' ;;
		*)  ok "l'invite développée ne contient AUCUN saut de ligne" ;;
	esac

	#  Le texte visible, séquences ANSI ôtées. C'est ce qu'Alex voit.
	VISIBLE="$(printf '%s' "$P_OK" | segments | grep -P '^t\t' | cut -f2- | tr -d '\n')"
	printf '       vu à l'"'"'écran : «%s»\n' "$VISIBLE"

	case "$VISIBLE" in
		*'❯ ') ok "l'invite se termine par « ❯ » suivi d'une espace" ;;
		*'❯')  non "le chevron est bien là, mais l'espace qui le suit a disparu" ;;
		*)     non "l'invite ne se termine pas par le chevron : «$VISIBLE»" ;;
	esac

	#  « a déjà une espace » : Alex avait relevé que l'espace existait déjà.
	#  Le saut de ligne devait donc devenir UNE espace, pas deux.
	if grep -q '  ❯' <<< "$VISIBLE" ; then
		non "deux espaces avant le chevron — le saut de ligne a été doublé"
	elif grep -q ' ❯ ' <<< "$VISIBLE" ; then
		ok "une seule espace de chaque côté du chevron"
	else
		non "l'espace avant le chevron manque : «$VISIBLE»"
	fi

	if grep -q '❯  ' <<< "$VISIBLE" ; then
		non "deux espaces APRÈS le chevron"
	else
		ok "une seule espace après le chevron"
	fi
fi

# =============================================================================
titre "2. Trois rôles : le nom en ORANGE, LEXOS en vert foncé, la machine en vert"
# =============================================================================
#  ALEX, consigne « terminal XFCE » : « le nom de l'utilisateur en rouge
#  clair, à côté LEXOS en vert foncé » — puis, captures à l'appui : « la
#  couleur de marceau pour l'orange et le vert pour LEXOS ». Le nom a donc
#  quitté le rouge clair ; LEXOS n'a pas bougé. Le mot LEXOS REMPLACE « @\h ». Le
#  chemin et le chevron restent écrits par la MACHINE et portent la MÊME
#  couleur. Ce banc ne connaît aucune valeur : il vérifie que le nom, LEXOS
#  et le chevron portent TROIS couleurs distinctes, que chemin et chevron
#  n'en font qu'une, et (section 5) que chacune vient du fichier généré.
mapfile -t SEG < <(printf '%s' "$P_OK" | segments)

#  La couleur en vigueur au moment où un texte donné est écrit.
couleur_de() { # couleur_de <texte cherché>
	local courante="" type texte
	for L in "${SEG[@]}"; do
		type="${L%%$'\t'*}"; texte="${L#*$'\t'}"
		if [ "$type" = "e" ]; then
			#  « 0 » referme : on repart de rien. Sinon la dernière
			#  séquence posée est celle qui peint.
			if [ "$texte" = "0" ]; then courante=""; else courante="$texte"; fi
		elif [ "$type" = "t" ] && [[ "$texte" == *"$1"* ]]; then
			printf '%s' "$courante"; return 0
		fi
	done
	return 1
}

C_CHEVRON="$(couleur_de '❯' || true)"
C_CHEMIN="$(couleur_de "$(basename "$BANC/home")" || true)"
#  Le chemin développé par « \w » est le répertoire courant du banc, pas le
#  faux HOME : on le cherche par son dernier segment, qui y figure toujours.
C_CHEMIN="$(couleur_de "$(basename "$PWD")" || true)"
C_NOM="$(couleur_de "$(id -un)" || true)"
C_LOGO="$(couleur_de "LEXOS" || true)"

if [ -z "$C_CHEVRON" ]; then
	non "impossible de relever la couleur du chevron"
else
	ok "le chevron est peint (séquence $C_CHEVRON)"
	if [ -n "$C_CHEMIN" ] && [ "$C_CHEMIN" = "$C_CHEVRON" ]; then
		ok "le chemin porte la MÊME couleur que le chevron (vert machine)"
	else
		non "le chemin ($C_CHEMIN) et le chevron ($C_CHEVRON) ne sont pas de la même couleur"
	fi
	if [ -n "$C_NOM" ] && [ "$C_NOM" != "$C_CHEVRON" ]; then
		ok "le nom d'utilisateur a SA couleur ($C_NOM), distincte du vert machine"
	else
		non "le nom ($C_NOM) porte encore la couleur de la machine ($C_CHEVRON) — il doit être orange"
	fi
	if [ -n "$C_LOGO" ] && [ "$C_LOGO" != "$C_CHEVRON" ] && [ "$C_LOGO" != "$C_NOM" ]; then
		ok "« LEXOS » est écrit, avec une troisième couleur ($C_LOGO) — ni celle du nom, ni celle de la machine"
	else
		non "« LEXOS » manque de l'invite, ou porte la couleur du nom ($C_NOM) ou de la machine ($C_CHEVRON) : vu « $C_LOGO »"
	fi
	#  « @\h » a disparu : LEXOS le remplace. On cherche le nom de machine
	#  précédé de « @ » dans le TEXTE développé, pas dans le fichier.
	TEXTE_INVITE="$(for L in "${SEG[@]}"; do [ "${L%%$'\t'*}" = "t" ] && printf '%s' "${L#*$'\t'}"; done)"
	if [[ "$TEXTE_INVITE" == *"@$(hostname)"* ]] || [[ "$TEXTE_INVITE" == *"$(id -un)@"* ]]; then
		non "l'invite écrit encore « @machine » : LEXOS devait le remplacer"
	else
		ok "plus de « @machine » : le mot LEXOS a pris la place"
	fi
	if [[ "$TEXTE_INVITE" == *"$(id -un) LEXOS "* ]]; then
		ok "l'ordre est « nom LEXOS chemin » — LEXOS juste à côté du nom"
	else
		non "LEXOS n'est pas juste à côté du nom : « $TEXTE_INVITE »"
	fi
fi

# =============================================================================
titre "3. « écriture blanc pour l'utilisateur » — PS1 finit sur la couleur de frappe"
# =============================================================================
#  Le mécanisme : PS1 se termine par une couleur qu'on ne referme PAS, elle
#  déborde donc sur la frappe. Si la dernière séquence de l'invite est un
#  « 0 » (remise à zéro), la frappe reprend la couleur par défaut du
#  terminal et la demande d'Alex tombe à l'eau sans que rien ne le dise.
DERNIER=""
for L in "${SEG[@]}"; do
	[ "${L%%$'\t'*}" = "e" ] && DERNIER="${L#*$'\t'}"
done
if [ -z "$DERNIER" ]; then
	non "l'invite ne finit sur aucune séquence de couleur"
elif [ "$DERNIER" = "0" ]; then
	non "l'invite finit sur une remise à zéro : la frappe n'aura pas de couleur"
elif [ "$DERNIER" = "$C_CHEVRON" ]; then
	non "la frappe porte la couleur de la MACHINE — elle doit s'en distinguer"
else
	ok "l'invite finit sur une couleur ouverte ($DERNIER) : c'est elle qui peint la frappe"
fi

#  PS0 remet à zéro à l'appui sur Entrée, sinon toute la SORTIE de la
#  commande hériterait du blanc de la frappe.
#  On DÉVELOPPE PS0 comme PS1 : « \e[0m » dans le fichier n'est du texte
#  que jusqu'à ce que bash l'interprète. Comparer la chaîne brute ferait
#  passer un PS0 écrit autrement (« \033[0m », « \[\e[0m\] ») pour un
#  PS0 cassé, et l'inverse.
#  TERM EST POSÉ ICI COMME DANS invite(), ET CE N'EST PAS UN DÉTAIL.
#  interactive.sh ne pose l'invite que si le terminal sait l'afficher :
#  « case "${TERM:-dumb}" in dumb|linux-m|unknown) ;; ». Ces deux
#  sous-shells-ci l'avaient oublié. Sur cette machine ça ne se voyait pas —
#  TERM y est hérité —, mais sur le coureur de la CI il ne l'est PAS : le
#  fichier se retirait, PS0 n'existait pas, et le banc annonçait un défaut
#  qui n'en était pas un. Vingt et un verts et un rouge, tous les jours,
#  pour une variable d'environnement. Le contrôle suivant fige le
#  comportement au lieu de le subir.
PS0_VU="$(HOME="$BANC/home" TERM=xterm-256color bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0-ABSENT}\"" 2>/dev/null)"
PS0_DEV="$(HOME="$BANC/home" TERM=xterm-256color bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0@P}\"" 2>/dev/null | tr -d '\001\002')"
if [ "$PS0_VU" = "ABSENT" ]; then
	non "PS0 n'est pas posé : tout l'écran prendrait la couleur de la frappe"
elif [ "$PS0_DEV" = $'\033[0m' ]; then
	ok "PS0 remet la couleur à zéro : la sortie des commandes n'est pas blanche"
else
	non "PS0 ne remet pas à zéro (développé : $(printf '%q' "$PS0_DEV"))"
fi

#  ET SUR UN TERMINAL QUI NE SAIT PAS AFFICHER DE COULEUR, ON NE POSE RIEN.
#  C'est ce que dit le « case TERM » d'interactive.sh, et c'est ce qui rend
#  la ligne ci-dessus obligatoire. Un banc qui hérite de TERM sans le dire
#  éprouve la machine qui le fait tourner, pas le fichier.
PS0_DUMB="$(HOME="$BANC/home" TERM=dumb bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0-ABSENT}\"" 2>/dev/null)"
if [ "$PS0_DUMB" = "ABSENT" ]; then
	ok "terminal « dumb » : aucune invite en couleur n'est posée — le repli marche"
else
	non "terminal « dumb » : une invite en couleur est quand même posée ($(printf '%q' "$PS0_DUMB"))"
fi

# =============================================================================
titre "4. Le chevron vire au ROUGE quand la commande précédente a échoué"
# =============================================================================
P_KO="$(invite 127 truecolor)"
mapfile -t SEG < <(printf '%s' "$P_KO" | segments)
C_CHEVRON_KO="$(couleur_de '❯' || true)"
if [ -z "$C_CHEVRON_KO" ]; then
	non "impossible de relever la couleur du chevron après un échec"
elif [ "$C_CHEVRON_KO" = "$C_CHEVRON" ]; then
	non "le chevron garde sa couleur après un échec : le seul signal de l'invite est perdu"
else
	ok "après un code 127, le chevron change de couleur ($C_CHEVRON → $C_CHEVRON_KO)"
fi
#  Et le reste de l'invite, lui, ne bouge PAS : seul le chevron alerte.
if [ "$(couleur_de "$(basename "$PWD")" || true)" = "$C_CHEMIN" ]; then
	ok "le chemin, lui, garde son vert : seul le chevron alerte"
else
	non "l'échec a repeint autre chose que le chevron"
fi

# =============================================================================
titre "5. Les couleurs viennent du fichier GÉNÉRÉ, pas d'une valeur en dur"
# =============================================================================
#  On génère les deux modes pour de vrai, puis on redemande l'invite en lui
#  donnant ce fichier-là. Si la valeur du fichier ne ressort pas dans
#  l'invite, c'est que le lien est cassé — le défaut exact que ce dépôt a
#  déjà connu : la bonne couleur écrite au bon endroit, et quelque chose de
#  plus tôt dans la chaîne qui ne la lit plus.
for MODE in nuit jour; do
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/t" --terminal "$MODE" orange \
		>"$BANC/gen-$MODE.log" 2>&1
	ENV="$BANC/t/.config/lexos/terminal.env"
	if [ ! -r "$ENV" ]; then
		non "$MODE : aucun terminal.env produit"
		continue
	fi
	# shellcheck disable=SC1090
	( set -a; . "$ENV"; set +a
	  [ -n "${LEXOS_PS_TEXTE:-}" ] ) \
		|| { non "$MODE : LEXOS_PS_TEXTE absent du fichier généré"; continue; }

	ATTENDU_M="$(sed -n "s/^LEXOS_PS_MACHINE='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_T="$(sed -n "s/^LEXOS_PS_TEXTE='\(.*\)'$/\1/p"   "$ENV")"

	mapfile -t SEG < <(invite 0 truecolor "$BANC/t/.config" | segments)
	VU_M="$(couleur_de '❯' || true)"
	VU_T=""
	for L in "${SEG[@]}"; do
		[ "${L%%$'\t'*}" = "e" ] && VU_T="${L#*$'\t'}"
	done

	[ "$VU_M" = "$ATTENDU_M" ] \
		&& ok "$MODE : le vert de l'invite est celui du fichier ($ATTENDU_M)" \
		|| non "$MODE : le fichier dit $ATTENDU_M, l'invite affiche $VU_M"
	#  Les deux rôles de la consigne « terminal XFCE » : le nom, LEXOS.
	ATTENDU_U="$(sed -n "s/^LEXOS_PS_UTILISATEUR='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_L="$(sed -n "s/^LEXOS_PS_LOGO='\(.*\)'$/\1/p" "$ENV")"
	VU_U="$(couleur_de "$(id -un)" || true)"
	VU_L="$(couleur_de "LEXOS" || true)"
	[ -n "$ATTENDU_U" ] && [ "$VU_U" = "$ATTENDU_U" ] \
		&& ok "$MODE : l'orange du nom est celui du fichier ($ATTENDU_U)" \
		|| non "$MODE : le fichier dit « $ATTENDU_U » pour le nom, l'invite affiche « $VU_U »"
	[ -n "$ATTENDU_L" ] && [ "$VU_L" = "$ATTENDU_L" ] \
		&& ok "$MODE : le vert foncé de LEXOS est celui du fichier ($ATTENDU_L)" \
		|| non "$MODE : le fichier dit « $ATTENDU_L » pour LEXOS, l'invite affiche « $VU_L »"
	ATTENDU_E="$(sed -n "s/^LEXOS_PS_ERREUR='\(.*\)'$/\1/p" "$ENV")"
	[ -n "$ATTENDU_U" ] && [ "1;$ATTENDU_U" != "$ATTENDU_E" ] && [ "$ATTENDU_U" != "${ATTENDU_E#1;}" ] \
		&& ok "$MODE : le nom n'est PAS le rouge d'erreur du chevron (signature ≠ signal)" \
		|| non "$MODE : le nom et l'erreur portent la même couleur — on ne distinguerait plus une commande en échec"
	[ "$VU_T" = "$ATTENDU_T" ] \
		&& ok "$MODE : la couleur de frappe est celle du fichier ($ATTENDU_T)" \
		|| non "$MODE : le fichier dit $ATTENDU_T, l'invite affiche $VU_T"

	#  Et le repli palette 256, pour la console texte et les vieux ssh qui
	#  afficheraient « 38;2;255;255;255 » en clair au milieu de l'invite.
	ATTENDU_256="$(sed -n "s/^LEXOS_PS_TEXTE_256='\(.*\)'$/\1/p" "$ENV")"
	VU_256=""
	mapfile -t SEG < <(invite 0 "" "$BANC/t/.config" | segments)
	for L in "${SEG[@]}"; do
		[ "${L%%$'\t'*}" = "e" ] && VU_256="${L#*$'\t'}"
	done
	[ -n "$ATTENDU_256" ] && [ "$VU_256" = "$ATTENDU_256" ] \
		&& ok "$MODE : sans COLORTERM, l'invite retombe sur la palette 256 ($ATTENDU_256)" \
		|| non "$MODE : repli 256 attendu $ATTENDU_256, vu $VU_256"
	ATTENDU_U256="$(sed -n "s/^LEXOS_PS_UTILISATEUR_256='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_L256="$(sed -n "s/^LEXOS_PS_LOGO_256='\(.*\)'$/\1/p" "$ENV")"
	VU_U256="$(couleur_de "$(id -un)" || true)"
	VU_L256="$(couleur_de "LEXOS" || true)"
	[ -n "$ATTENDU_U256" ] && [ "$VU_U256" = "$ATTENDU_U256" ] && [ -n "$ATTENDU_L256" ] && [ "$VU_L256" = "$ATTENDU_L256" ] \
		&& ok "$MODE : en 256 couleurs, le nom ($ATTENDU_U256) et LEXOS ($ATTENDU_L256) retombent sur leurs replis" \
		|| non "$MODE : replis 256 du nom/LEXOS attendus $ATTENDU_U256 / $ATTENDU_L256, vus $VU_U256 / $VU_L256"
	#  …et ces replis restent TROIS couleurs : un repli 256 de LEXOS égal au
	#  vert machine fondrait le mot dans le chemin en console texte.
	ATTENDU_M256="$(sed -n "s/^LEXOS_PS_MACHINE_256='\(.*\)'$/\1/p" "$ENV")"
	[ -n "$ATTENDU_M256" ] && [ "$ATTENDU_L256" != "$ATTENDU_M256" ] && [ "$ATTENDU_U256" != "$ATTENDU_M256" ] && [ "$ATTENDU_U256" != "$ATTENDU_L256" ] \
		&& ok "$MODE : en 256 couleurs aussi, nom / LEXOS / machine sont trois couleurs distinctes" \
		|| non "$MODE : en 256 couleurs, deux des trois rôles se confondent (nom $ATTENDU_U256, LEXOS $ATTENDU_L256, machine $ATTENDU_M256)"

	#  Le contraste, mesuré sur le VRAI fond du mode. Une frappe blanche sur
	#  le crème du thème de jour serait invisible : c'est pour ça que jour et
	#  nuit n'ont pas la même encre.
	BG="$(sed -n 's/^LEXOS_TERM_BG=//p' "$ENV")"
	RAPPORT="$(python3 - "$ATTENDU_T" "$BG" <<'PY'
import sys, re
def lum(c):
    v = [int(c[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
m = re.match(r"38;2;(\d+);(\d+);(\d+)$", sys.argv[1])
if not m:
    print("0"); sys.exit()
fg = "#%02X%02X%02X" % tuple(int(g) for g in m.groups())
a, b = lum(fg), lum(sys.argv[2])
if a < b: a, b = b, a
print("%.2f" % ((a+0.05)/(b+0.05)))
PY
)"
	if awk -v r="$RAPPORT" 'BEGIN{exit !(r >= 4.5)}'; then
		ok "$MODE : la frappe donne $RAPPORT:1 sur le fond $BG (seuil AA 4,5)"
	else
		non "$MODE : la frappe ne donne que $RAPPORT:1 sur $BG — illisible"
	fi
	#  Le nom et LEXOS aussi — en couleur vraie ET en 256 : « le vert foncé
	#  sur fond noir se lit mal », le seuil est mesuré sur le vrai fond.
	for ROLE in "nom:$ATTENDU_U" "LEXOS:$ATTENDU_L" "nom-256:$ATTENDU_U256" "LEXOS-256:$ATTENDU_L256"; do
		R="$(python3 "$CONTRASTE" "${ROLE#*:}" "$BG")"
		if awk -v r="$R" 'BEGIN{exit !(r >= 4.5)}'; then
			ok "$MODE : ${ROLE%%:*} donne $R:1 sur $BG"
		else
			non "$MODE : ${ROLE%%:*} ne donne que $R:1 sur $BG — « le vert foncé sur fond noir se lit mal »"
		fi
	done

	#  ═══ LE NOM EST-IL VRAIMENT DE L'OR ? ═══
	#  Jusqu'ici ce banc ne vérifiait que des DIFFÉRENCES : le nom n'est ni
	#  le vert machine, ni le vert de LEXOS, ni le rouge d'erreur. Un nom
	#  rose vif passait tous ces points. Or Alex n'a pas demandé « une autre
	#  couleur » — et une demande de couleur qu'aucun contrôle ne nomme finit
	#  par dériver au correctif suivant.
	#
	#  LA DEMANDE A CHANGÉ, ET LA PLAGE AVEC ELLE. C'était l'ORANGE (15°-50°)
	#  jusqu'à « sur l'image où c'est écrit marceau, j'aimerais qu'il soit de
	#  couleur jaune or ». L'or tient entre 38° et 62° sur la roue : au-delà
	#  c'est le jaune-vert, en deçà l'orange.
	#
	#  ET LA PLAGE S'EST DÉPLACÉE, PAS ÉLARGIE — c'est le point. L'orange
	#  n'est plus accepté pour le nom, parce que l'orange est désormais
	#  l'ACCENT (curseur, sélection, onglet actif). Si le nom y revenait, la
	#  signature et l'objet vivant se repeindraient pareil : exactement la
	#  confusion que ce lot a passé une journée à défaire.
	#  Livré : #FFD700 → 50,6° · #7A5C00 → 45,2° · 38;5;220 → 50,6°
	#  · 38;5;94 → 42,2°.
	for ROLE in "nom:$ATTENDU_U" "nom-256:$ATTENDU_U256"; do
		H="$(python3 "$ECART" teinte "${ROLE#*:}")"
		if awk -v h="$H" 'BEGIN{exit !(h >= 38 && h <= 62)}'; then
			ok "$MODE : ${ROLE%%:*} est bien dans l'or ($H° sur la roue)"
		else
			non "$MODE : ${ROLE%%:*} est à $H° — hors de la plage or 38°-62°, ce n'est pas ce qui a été demandé"
		fi
	done

	#  ═══ ET CET ORANGE N'EST PAS CELUI DU CURSEUR ═══
	#  L'accent — curseur, sélection, onglet actif — est orange lui aussi.
	#  Constater qu'ils « diffèrent » ne suffirait pas : deux oranges à ΔE 3
	#  diffèrent et sont indiscernables à l'œil. On exige un écart PERÇU
	#  d'au moins 10, seuil au-dessus duquel deux couleurs se lisent comme
	#  deux. C'est tout l'écart entre une signature et un objet vivant.
	#  Livré : ΔE 21 de nuit (#FF8700 contre #E8590C), ΔE 15 de jour
	#  (#8A4400 contre #A84007).
	CURSEUR="$(sed -n 's/^LEXOS_TERM_CURSEUR=//p' "$ENV")"
	if [ -z "$CURSEUR" ]; then
		non "$MODE : terminal.env ne dit pas la couleur du curseur — l'écart n'est pas mesurable, on ne conclut pas qu'il est bon"
	else
		for ROLE in "nom:$ATTENDU_U" "nom-256:$ATTENDU_U256"; do
			D="$(python3 "$ECART" de "${ROLE#*:}" "$CURSEUR")"
			if awk -v d="$D" 'BEGIN{exit !(d >= 10)}'; then
				ok "$MODE : ${ROLE%%:*} se distingue du curseur $CURSEUR (ΔE $D)"
			else
				non "$MODE : ${ROLE%%:*} est à ΔE $D du curseur $CURSEUR — le nom se lirait comme un curseur posé dessus"
			fi
		done
	fi
done

# =============================================================================
titre "6. L'orange est revenu dans l'invite, au NOM seulement"
# =============================================================================
#  Cette section s'appelait « L'orange a quitté l'INVITE ». Elle date de la
#  consigne où le nom était rouge clair ; Alex est revenu dessus et le nom
#  est orange depuis. Ce qu'elle garde reste vrai et reste utile : l'ancien
#  nom de variable ne doit pas revenir, et le curseur, la sélection et
#  l'onglet actif gardent l'accent — les leur retirer aurait été un
#  correctif trop large, et personne ne l'aurait vu venir.
#  Que le nom soit orange SANS être l'orange du curseur, c'est la section 5
#  qui le mesure, en teinte et en écart perçu.
#  ON LIT LE CODE, PAS LES COMMENTAIRES. Les deux fichiers EXPLIQUENT que
#  C_SAISIE s'appelait ainsi avant — un banc naïf lirait sa propre
#  explication et se déclarerait en échec. Ce dépôt s'est déjà fait prendre
#  trois fois à cette faute ; on coupe les commentaires d'abord.
code_seul() { sed 's/#.*$//' "$1"; }
if grep -q 'C_SAISIE\|PS_SAISIE' < <(code_seul "$SH"); then
	non "interactive.sh emploie encore « saisie » dans son code : l'ancien nom traîne"
else
	ok "interactive.sh ne connaît plus que C_MACHINE, C_TEXTE, C_ERREUR et C_DIM"
fi
if grep -q "LEXOS_PS_SAISIE" < <(code_seul "$GEN"); then
	non "lexos-theme-gen écrit encore LEXOS_PS_SAISIE — une clé que personne ne lit"
else
	ok "lexos-theme-gen n'écrit plus de clé d'invite orpheline"
fi
if grep -q 'CursorColor=\${TERM_CURSEUR}\|TabActivityColor=\${TERM_SAISIE}' "$GEN"; then
	ok "le terminal garde bien l'accent pour son curseur et son onglet actif"
else
	non "l'accent a disparu du terminalrc : le correctif a débordé sur le curseur"
fi

# =============================================================================
titre "6 bis. Les REPLIS d'interactive.sh disent ce que le générateur écrit"
# =============================================================================
#  LE SEUL MAILLON QUE PERSONNE NE MESURAIT. Les six valeurs de repli
#  d'interactive.sh et les six PS_*_256 de lexos-theme-gen sont la MÊME
#  couleur écrite deux fois. Le dépôt répète partout que deux écritures de la
#  même couleur finissent par diverger — et celles-ci avaient divergé : le
#  générateur écrivait 38;5;40 pour le chemin pendant qu'interactive.sh
#  gardait 38;5;35, l'ancien vert d'avant « un vert plus visible ».
#  Ce n'est pas un détail cosmétique : ces replis-là servent dès que
#  terminal.env manque, et ils sont LA valeur lue par la console texte, ssh
#  et tmux, puisque aucun des trois n'exporte COLORTERM.
#
#  ON LIT LE CODE, PAS LES COMMENTAIRES : interactive.sh explique ses propres
#  valeurs en toutes lettres juste au-dessus d'elles. On coupe d'abord.
rm -rf "${BANC:?}/replis"; mkdir -p "$BANC/replis"
bash "$GEN" --target "$BANC/replis" --terminal nuit orange >/dev/null 2>&1
ENV_REPLIS="$BANC/replis/.config/lexos/terminal.env"
code_nu() { sed 's/#.*$//' "$1"; }
for PAIRE in "UTILISATEUR:le nom" "LOGO:« LEXOS »" "MACHINE:le chemin"; do
	CLE="${PAIRE%%:*}"; QUOI="${PAIRE#*:}"
	GENERE="$(sed -n "s/^LEXOS_PS_${CLE}_256='\(.*\)'$/\1/p" "$ENV_REPLIS")"
	REPLI="$(code_nu "$SH" | sed -n "s/.*__LEXOS_C_${CLE}='\([^']*\)'.*/\1/p" | head -1)"
	if [ -z "$GENERE" ] || [ -z "$REPLI" ]; then
		non "$QUOI : repli ou valeur générée introuvable (généré « $GENERE », repli « $REPLI ») — on ne conclut pas qu'ils s'accordent"
	elif [ "$GENERE" = "$REPLI" ]; then
		ok "$QUOI : le repli d'interactive.sh est celui du générateur ($REPLI)"
	else
		non "$QUOI : le générateur écrit $GENERE, interactive.sh retombe sur $REPLI — sans thème généré, la console texte affiche une autre couleur"
	fi
done

#  ET TMUX LIT LA MÊME PALETTE. C'est un des « autres terminaux » qu'Alex
#  vise, il n'exporte pas COLORTERM, donc il voit la 256 — et il réécrit ces
#  index À LA MAIN dans sa configuration. Troisième écriture de la même
#  couleur ; elle avait déjà divergé une fois (le vert de la machine y était
#  resté au 35 d'avant pendant que l'invite passait au 40), et elle a
#  divergé une seconde fois pendant la correction elle-même. On la compare
#  donc, au lieu d'y faire attention.
TMUXC="$RACINE/config/includes.chroot/usr/share/lexos/tmux/lexos.conf"
if [ ! -r "$TMUXC" ]; then
	printf '  \033[2mtmux sauté — sa configuration est absente du dépôt\033[0m\n'
else
	#  ⚠ PAS « code_nu » ICI, ET C'EST UNE LEÇON. Dans tmux, « #[...] » est du
	#  BALISAGE DE STYLE, pas un commentaire : « #[fg=colour35,bold]LEXOS »
	#  est précisément la ligne qu'on veut lire, et couper à partir du
	#  premier « # » la fait disparaître — mesuré, le contrôle a d'abord
	#  rendu « index illisible ». La règle du dépôt (retirer les
	#  commentaires avant de chercher un jeton) reste bonne ; ce qu'il faut
	#  retirer dépend du format. Dans tmux, un commentaire est une LIGNE qui
	#  commence par « # ».
	tmux_nu() { sed '/^[[:space:]]*#/d' "$1"; }
	T_LOGO="$(tmux_nu "$TMUXC" | sed -n 's/.*status-left .*fg=colour\([0-9]*\),bold\]LEXOS.*/\1/p' | head -1)"
	T_MACH="$(tmux_nu "$TMUXC" | sed -n 's/.*status-style .*fg=colour\([0-9]*\)".*/\1/p' | head -1)"
	G_LOGO="$(sed -n "s/^LEXOS_PS_LOGO_256='38;5;\(.*\)'$/\1/p" "$ENV_REPLIS")"
	G_MACH="$(sed -n "s/^LEXOS_PS_MACHINE_256='38;5;\(.*\)'$/\1/p" "$ENV_REPLIS")"
	if [ -z "$T_LOGO" ] || [ -z "$G_LOGO" ]; then
		non "tmux : index de LEXOS illisible (tmux « $T_LOGO », généré « $G_LOGO ») — on ne conclut pas qu'ils s'accordent"
	elif [ "$T_LOGO" = "$G_LOGO" ]; then
		ok "tmux écrit « LEXOS » dans le vert de l'invite (colour$T_LOGO)"
	else
		non "tmux écrit « LEXOS » en colour$T_LOGO, l'invite en 38;5;$G_LOGO — deux verts pour le même mot"
	fi
	if [ -z "$T_MACH" ] || [ -z "$G_MACH" ]; then
		non "tmux : index de la machine illisible — on ne conclut pas"
	elif [ "$T_MACH" = "$G_MACH" ]; then
		ok "tmux écrit ce que la machine dit dans le vert de l'invite (colour$T_MACH)"
	else
		non "tmux écrit la machine en colour$T_MACH, l'invite en 38;5;$G_MACH"
	fi
fi

#  ═══ ET LES DEUX AUTRES SURFACES QUI ÉCRIVENT « LexOS » ═══
#  L'onglet Audit et la bascule jour/nuit l'écrivaient en 1;38;5;208 — l'orange
#  que l'invite donne au NOM de l'utilisateur. Les deux rôles y étaient
#  inversés. Ils lisent terminal.env maintenant ; on le mesure.
MENU="$RACINE/config/includes.chroot/usr/lib/lexos/audit/menu.py"
MENU_DIR="$RACINE/config/includes.chroot/usr/lib/lexos/audit"
BASCULE="$RACINE/config/includes.chroot/usr/bin/lexos-terminal"
#  Les deux séquences COMPLÈTES, relues dans le fichier généré — aucune
#  valeur n'est écrite ici. Les deux surfaces ci-dessous ne voient pas
#  COLORTERM, elles lisent donc la branche 256, comme la console et ssh.
GENERE_LOGO_256="$(sed -n "s/^LEXOS_PS_LOGO_256='\(.*\)'$/\1/p" "$ENV_REPLIS")"
GENERE_U256="$(sed -n "s/^LEXOS_PS_UTILISATEUR_256='\(.*\)'$/\1/p" "$ENV_REPLIS")"

#  1) Le menu d'audit : son lecteur rend-il ce que le fichier dit ?
if [ ! -r "$MENU" ]; then
	non "le menu d'audit est introuvable : sa couleur n'est pas vérifiable"
else
	#  ⚠ COLORTERM EST RETIRÉ EXPRÈS : ce point attend la valeur de la palette
	#  256, et menu._role bascule sur la couleur VRAIE quand le terminal
	#  l'annonce. Hériter d'un COLORTERM de l'appelant faisait donc rougir un
	#  code juste — mesuré. Le banc fixe la profondeur qu'il interroge.
	VU_MENU="$(env -u COLORTERM XDG_CONFIG_HOME="$BANC/replis/.config" MENU_DIR="$MENU_DIR" python3 -c "
import os, sys
sys.path.insert(0, os.environ['MENU_DIR'])
import menu
print(menu._role('LOGO', 'REPLI'))
" 2>/dev/null)"
	if [ -z "$VU_MENU" ]; then
		non "le menu d'audit n'a pas pu être interrogé — on ne conclut pas qu'il suit le thème"
	elif [ "$VU_MENU" = "$GENERE_LOGO_256" ]; then
		ok "le menu d'audit prend « LexOS » dans le vert du générateur ($VU_MENU)"
	else
		non "le menu d'audit rend « $VU_MENU » là où le générateur dit « $GENERE_LOGO_256 »"
	fi
	#  ON LIT LE CODE, PAS LES COMMENTAIRES : ce fichier EXPLIQUE en toutes
	#  lettres qu'il écrivait « 1;38;5;208 » avant. Un contrôle naïf lirait
	#  son propre récit et se déclarerait en échec.
	#  ⚠ « grep -q » EN BOUT DE TUBE EST INTERDIT ICI, et la CI le vérifie
	#  (« Aucun banc ne renvoie un texte dans grep -q »). Il s'arrête au
	#  premier résultat, le producteur reçoit une erreur d'écriture, et sous
	#  « pipefail » c'est TOUT le tube qui échoue — motif trouvé, condition
	#  fausse. La substitution de processus sort le producteur du tube.
	if grep -q '38;5;208m⚜\|38;5;208m. + .━.' < <(code_nu "$MENU"); then
		non "le menu d'audit garde un orange écrit en dur sur un titre « LexOS »"
	else
		ok "le menu d'audit n'écrit plus aucune couleur de « LexOS » en dur"
	fi
fi

#  2) La bascule jour/nuit : elle IMPRIME « Terminal LexOS », on lit sa sortie.
if [ ! -x "$BASCULE" ] || ! command -v script >/dev/null 2>&1; then
	printf '  \033[2mbascule sautée — « lexos-terminal » ou « script » absent\033[0m\n'
else
	SORTIE_B="$(HOME="$BANC/replis" XDG_CONFIG_HOME="$BANC/replis/.config" \
		NO_COLOR="" TERM=xterm-256color \
		env -u COLORTERM script -qec "bash '$BASCULE'" /dev/null 2>/dev/null || true)"
	if [ -z "$SORTIE_B" ]; then
		non "« lexos-terminal » n'a rien affiché — son titre n'est pas vérifiable"
	else
		case "$SORTIE_B" in
			*"${ESCB}[${GENERE_LOGO_256}mTerminal LexOS"*)
				ok "« Terminal LexOS » porte le vert du générateur ($GENERE_LOGO_256)" ;;
			*"${ESCB}[${GENERE_U256}mTerminal LexOS"*)
				non "« Terminal LexOS » porte l'orange du NOM ($GENERE_U256) — les deux rôles sont inversés" ;;
			*)
				non "« Terminal LexOS » ne porte pas le vert du générateur ($GENERE_LOGO_256)" ;;
		esac
	fi
fi

#  ═══ ET LA BASCULE IMPRIME DANS LA NOUVELLE PALETTE, PAS L'ANCIENNE ═══
#  « lexos terminal nuit » régénère le thème, repeint la fenêtre, PUIS
#  confirme. Si ses couleurs datent du démarrage du programme, la
#  confirmation sort dans l'ancienne palette : en basculant jour → nuit, le
#  fond devient noir et le « ✓ » s'imprime avec l'index de JOUR (22, un vert
#  sombre) — illisible. Le sens inverse met le vert vif de nuit sur le crème.
#  Défaut réel, signalé par une relecture et reproduit avant d'être corrigé.
if [ ! -x "$BASCULE" ] || ! command -v script >/dev/null 2>&1; then
	printf '  \033[2mbascule à chaud sautée — « lexos-terminal » ou « script » absent\033[0m\n'
else
	rm -rf "${BANC:?}/bascule"; mkdir -p "$BANC/bascule"
	BPATH="$RACINE/config/includes.chroot/usr/bin:$PATH"
	#  On POSE un thème de jour, puis on demande la nuit.
	#  ⚠ XDG_CONFIG_HOME EST OBLIGATOIRE SUR LES TROIS COMMANDES, et son
	#  absence ici est passée entre les mailles. lexos-terminal lit
	#  « ${XDG_CONFIG_HOME:-$HOME/.config} » : la VARIABLE gagne sur HOME.
	#  Épingler HOME seul laissait donc cette sonde écrire et relire le
	#  terminal.env de la machine qui fait tourner le banc. Vert sur un
	#  compte sans thème, ROUGE dès qu'il y en a un — mesuré, avec un thème
	#  de jour actif : « la confirmation sort dans l'ANCIENNE palette ».
	#  Cinquième fois que ce banc se fait prendre à hériter de son
	#  environnement ; la section 9 avait été corrigée, celle-ci pas.
	HOME="$BANC/bascule" XDG_CONFIG_HOME="$BANC/bascule/.config" \
		PATH="$BPATH" "$BASCULE" jour >/dev/null 2>&1 || true
	AVANT="$(sed -n "s/^LEXOS_PS_MACHINE_256='\(.*\)'$/\1/p" \
		"$BANC/bascule/.config/lexos/terminal.env" 2>/dev/null)"
	SORTIE_SW="$(HOME="$BANC/bascule" XDG_CONFIG_HOME="$BANC/bascule/.config" \
		PATH="$BPATH" TERM=xterm-256color NO_COLOR="" \
		env -u COLORTERM script -qec "'$BASCULE' nuit" /dev/null 2>/dev/null || true)"
	APRES="$(sed -n "s/^LEXOS_PS_MACHINE_256='\(.*\)'$/\1/p" \
		"$BANC/bascule/.config/lexos/terminal.env" 2>/dev/null)"
	if [ -z "$AVANT" ] || [ -z "$APRES" ] || [ "$AVANT" = "$APRES" ]; then
		non "la bascule n'a pas changé de thème ($AVANT → $APRES) — on ne conclut pas sur sa couleur"
	else
		case "$SORTIE_SW" in
			*"${ESCB}[${APRES}m"*)
				ok "après la bascule, la confirmation sort dans la NOUVELLE palette ($APRES)" ;;
			*"${ESCB}[${AVANT}m"*)
				non "après la bascule, la confirmation sort dans l'ANCIENNE palette ($AVANT) — illisible sur le nouveau fond" ;;
			*)
				non "après la bascule, la confirmation ne porte ni l'ancienne ($AVANT) ni la nouvelle ($APRES) couleur" ;;
		esac
	fi
fi

# =============================================================================
titre "7. La BANNIÈRE dit la même chose que l'invite"
# =============================================================================
#  ALEX : « les couleurs, on les retrouve dans les autres terminaux aussi ».
#  Sur la console texte, lexfetch s'affiche JUSTE AU-DESSUS de l'invite —
#  interactive.sh le lance quand DISPLAY est vide. On lit donc
#  « marceau@lexos », puis, deux lignes plus bas, « marceau LEXOS ~ ❯ ».
#  Deux fois le même nom sur le même écran.
#  Les deux ont longtemps valu 38;5;208, mais par COÏNCIDENCE : lexfetch
#  l'écrivait en dur. Le jour où l'invite a changé d'avis, rien n'aurait
#  tiré la bannière avec elle, et c'est précisément ce qu'Alex reproche.
#  Ce contrôle ne connaît aucune valeur : il relit ce que le générateur a
#  écrit, et vérifie que la bannière l'emploie.
#
#  IL FAUT UN VRAI TERMINAL. lexfetch ne colore que si « [[ -t 1 ]] » : dans
#  un tube, il sort en noir et blanc et le contrôle passerait au vert sans
#  rien avoir mesuré. D'où « script », qui lui donne un pseudo-terminal.
FETCH="$RACINE/config/includes.chroot/usr/bin/lexfetch"
if ! command -v script >/dev/null 2>&1; then
	printf '  \033[2mbannière sautée — « script » (util-linux) est absent : sans pseudo-terminal, lexfetch ne colore rien et le contrôle ne mesurerait rien\033[0m\n'
elif [ ! -r "$FETCH" ]; then
	non "lexfetch est introuvable : la bannière n'est pas vérifiable"
else
	rm -rf "${BANC:?}/fetch"; mkdir -p "$BANC/fetch"
	bash "$GEN" --target "$BANC/fetch" --terminal nuit orange >/dev/null 2>&1
	EF="$BANC/fetch/.config/lexos/terminal.env"
	#  USER épinglé et HÔTE lu dans le même ordre que lexfetch (hostnamectl,
	#  puis /etc/hostname, puis uname -n) : sa ligne d'identité écrit
	#  « ${USER:-$(id -un)} », donc la variable gagne sur la commande.
	QUI="$(id -un)"
	for PROF in truecolor 256; do
		#  ═══ ON FIGE L'ENVIRONNEMENT, ON NE L'HÉRITE PAS ═══
		#  Deux variables de l'appelant suffisaient à faire rougir ce
		#  contrôle sans qu'aucun code soit en cause — mesuré, pas supposé :
		#   · NO_COLOR : lexfetch le teste en tête et sort alors SANS la
		#     moindre séquence. Les quatre points rougissaient.
		#   · XDG_CONFIG_HOME : lexfetch lit « $XDG_CONFIG_HOME/lexos/
		#     terminal.env » quand il est posé, donc pas la copie fabriquée
		#     ici — et le point du nom en 256 restait VERT quand même,
		#     puisque le repli en dur de lexfetch vaut justement 208. Un
		#     faux rouge À MOITIÉ, le pire à diagnostiquer.
		#  Ce banc a déjà payé exactement ça pour TERM (voir la note de PS0
		#  plus haut : « vingt et un verts et un rouge, tous les jours, pour
		#  une variable d'environnement »). On fige donc au lieu de subir.
		if [ "$PROF" = truecolor ]; then
			SUF=""
			SORTIE="$(HOME="$BANC/fetch" XDG_CONFIG_HOME="$BANC/fetch/.config" \
				USER="$QUI" NO_COLOR="" COLORTERM=truecolor TERM=xterm-256color \
				script -qec "bash '$FETCH'" /dev/null 2>/dev/null || true)"
		else
			SUF="_256"
			SORTIE="$(HOME="$BANC/fetch" XDG_CONFIG_HOME="$BANC/fetch/.config" \
				USER="$QUI" NO_COLOR="" TERM=xterm-256color \
				env -u COLORTERM script -qec "bash '$FETCH'" /dev/null 2>/dev/null || true)"
		fi
		ATT_U="$(sed -n "s/^LEXOS_PS_UTILISATEUR${SUF}='\(.*\)'$/\1/p" "$EF")"
		ATT_L="$(sed -n "s/^LEXOS_PS_LOGO${SUF}='\(.*\)'$/\1/p" "$EF")"
		if [ -z "$ATT_U" ] || [ -z "$ATT_L" ]; then
			non "$PROF : terminal.env ne dit pas les couleurs du nom et de LEXOS — on ne conclut pas que la bannière est bonne"
		elif [ -z "$SORTIE" ]; then
			non "$PROF : lexfetch n'a rien affiché — la bannière n'est pas vérifiable"
		else
			case "$SORTIE" in
				*"${ESCB}[${ATT_U}m${QUI}"*) ok "$PROF : la bannière écrit « $QUI » dans la couleur de l'invite ($ATT_U)" ;;
				*) non "$PROF : la bannière n'écrit pas « $QUI » en $ATT_U — elle a gardé une couleur à elle" ;;
			esac
			case "$SORTIE" in
				*"${ESCB}[${ATT_L}m"*) ok "$PROF : la machine y porte le vert de « LEXOS » ($ATT_L)" ;;
				*) non "$PROF : la machine de la bannière ne porte pas le vert de LEXOS ($ATT_L)" ;;
			esac
		fi
	done
fi

# =============================================================================
titre "8. SANS thème généré, la bannière et l'invite disent la même chose"
# =============================================================================
#  LE TROU QUE CETTE SECTION BOUCHE. Les sections 6 bis et 7 génèrent
#  toujours un terminal.env : elles mesurent donc ce que les fichiers
#  LISENT, jamais ce qu'ils inventent quand il n'y a rien à lire. Or c'est
#  là que lexfetch se trompait — « H="$O" » initialisait la MACHINE, qui
#  porte le rôle LOGO, sur l'orange du NOM. Sans thème, la bannière sortait
#  « marceau@lexos » TOUT EN ORANGE pendant que l'invite, deux lignes plus
#  bas, écrivait le nom en orange et LEXOS en vert. ΔE 105 entre les deux.
#
#  ON N'ÉCRIT AUCUNE COULEUR ICI : l'attendu est relu chez l'autre, dans
#  les replis d'interactive.sh. Les deux sont donc COMPARÉS — c'est ce qui
#  les empêche de diverger plus tard, et c'est tout l'intérêt du point.
if [ ! -r "$FETCH" ] || ! command -v script >/dev/null 2>&1; then
	printf '  \033[2mrepli de la bannière sauté — « lexfetch » ou « script » absent\033[0m\n'
else
	mkdir -p "$BANC/nu/.config"
	#  Les replis de l'invite, lus dans le CODE décommenté : interactive.sh
	#  raconte ses anciennes valeurs juste au-dessus d'elles.
	R_NOM="$(code_nu "$SH" | sed -n "s/.*__LEXOS_C_UTILISATEUR='\([^']*\)'.*/\1/p" | head -1)"
	R_LOGO="$(code_nu "$SH" | sed -n "s/.*__LEXOS_C_LOGO='\([^']*\)'.*/\1/p" | head -1)"
	#  L'orange propre au dessin de lexfetch : on exige qu'il DIFFÈRE du
	#  vert-logo avant de s'en servir, sinon la comparaison serait circulaire.
	R_ART="$(code_nu "$FETCH" | sed -n "s/^[[:space:]]*O=\\\$'\\\\033\[\([0-9;]*\)m'.*/\1/p" | head -1)"
	if [ -z "$R_NOM" ] || [ -z "$R_LOGO" ] || [ -z "$R_ART" ]; then
		non "les replis d'interactive.sh ou l'orange de lexfetch sont illisibles — on ne conclut rien"
	elif [ -e "$BANC/nu/.config/lexos/terminal.env" ]; then
		non "le HOME de ce point n'est pas vierge — il mesurerait un thème, pas le repli"
	elif [ "$R_LOGO" = "$R_ART" ]; then
		non "le vert-logo et l'orange du dessin sont la même valeur — le point serait circulaire"
	else
		#  ⚠ ON ÉPINGLE USER, et ce n'est pas de la coquetterie : lexfetch
		#  écrit « ${USER:-$(id -un)} », donc la VARIABLE gagne. Un banc qui
		#  attendait « id -un » rougissait dès que l'appelant exportait un
		#  USER différent — mesuré : quatre points. On fixe les deux côtés.
		QUI_N="$(id -un 2>/dev/null || echo inconnu)"
		#  L'HÔTE SE LIT COMME lexfetch LE LIT, dans le même ordre : il essaie
		#  hostnamectl, puis /etc/hostname, puis uname -n. « hostname » n'est
		#  PAS dans sa liste, et les trois peuvent différer.
		HOTE_N="$(hostnamectl --static 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n)"
		for PROF in 256 vraie; do
			if [ "$PROF" = vraie ]; then
				NUE="$(HOME="$BANC/nu" XDG_CONFIG_HOME="$BANC/nu/.config" \
					USER="$QUI_N" NO_COLOR="" COLORTERM=truecolor TERM=xterm-256color \
					script -qec "bash '$FETCH'" /dev/null 2>/dev/null || true)"
			else
				NUE="$(HOME="$BANC/nu" XDG_CONFIG_HOME="$BANC/nu/.config" \
					USER="$QUI_N" NO_COLOR="" TERM=xterm-256color \
					env -u COLORTERM script -qec "bash '$FETCH'" /dev/null 2>/dev/null || true)"
			fi
			if [ -z "$NUE" ]; then
				non "$PROF : sans thème, lexfetch n'a rien affiché — rien à mesurer"
				continue
			fi
			#  On s'ancre sur le NOM DE LA MACHINE, pas sur la seule séquence :
			#  chercher le vert n'importe où passerait au vert pour un vert posé
			#  ailleurs dans la bannière.
			case "$NUE" in
				*"${ESCB}[${R_LOGO}m${HOTE_N}"*)
					ok "$PROF : sans thème, « $HOTE_N » porte le vert-logo de l'invite ($R_LOGO)" ;;
				*"${ESCB}[${R_NOM}m${HOTE_N}"*)
					non "$PROF : sans thème, la bannière peint le nom ET la machine en $R_NOM — l'invite, non" ;;
				*)
					non "$PROF : sans thème, « $HOTE_N » ne porte ni le vert-logo ($R_LOGO) ni l'or du nom ($R_NOM)" ;;
			esac
			case "$NUE" in
				*"${ESCB}[${R_NOM}m${QUI_N}"*)
					ok "$PROF : sans thème, « $QUI_N » garde l'or du nom ($R_NOM)" ;;
				*)  non "$PROF : sans thème, « $QUI_N » ne porte pas l'or du nom ($R_NOM)" ;;
			esac
			#  Le dessin ne doit PAS avoir été détourné : c'est le piège du
			#  correctif facile, qui repeindrait $O et donc le logo ASCII.
			case "$NUE" in
				*"${ESCB}[${R_ART}m"*)
					ok "$PROF : le dessin garde l'orange propre à la bannière ($R_ART)" ;;
				*)  non "$PROF : le dessin a perdu son orange ($R_ART) — le correctif a détourné \$O" ;;
			esac
		done
		#  ET SANS COULEUR DU TOUT, RIEN NE DOIT S'ÉCHAPPER. C'est le défaut
		#  qu'un repli posé une ligne trop haut introduirait : mesuré, une
		#  séquence sortait alors même que NO_COLOR est posé.
		MUET="$(HOME="$BANC/nu" XDG_CONFIG_HOME="$BANC/nu/.config" \
			NO_COLOR=1 TERM=xterm-256color bash "$FETCH" 2>/dev/null || true)"
		case "$MUET" in
			*"$ESCB["*) non "avec NO_COLOR=1, la bannière émet encore une séquence — un repli est posé hors de la garde" ;;
			*)          ok "avec NO_COLOR=1, la bannière n'émet aucune séquence" ;;
		esac
	fi
fi

# =============================================================================
titre "9. L'ACCENT est un rôle comme les autres — y compris en 256 couleurs"
# =============================================================================
#  CE QUE CE POINT RÉPARE, ET C'ÉTAIT DANS L'ANGLE MORT DE TOUS LES AUTRES.
#  Six rôles (MACHINE, TEXTE, ERREUR, DIM, UTILISATEUR, LOGO) ont depuis
#  toujours DEUX écritures dans terminal.env : la couleur vraie et la
#  palette 256. L'accent, lui, n'était rangé qu'en #RRGGBB — et trois
#  fichiers le convertissaient chacun de leur côté, ce qui ne marche QUE
#  sous COLORTERM. Hors du Terminal Pro — console texte, ssh, tmux — ils
#  restaient donc figés sur le 208 de NUIT : « lexos terminal jour »
#  imprimait sa ligne « Mode » en orange vif sur le crème qu'il venait
#  lui-même d'installer, à 2,21:1, sous le seuil AA.
#
#  Le point MESURE le contraste et IMPRIME le chiffre, pour qu'une dérive se
#  voie avant de franchir le seuil, plutôt que d'affirmer « c'est lisible ».
if [ ! -x "$GEN" ]; then
	printf '  \033[2maccent sauté — le générateur n'"'"'est pas exécutable\033[0m\n'
else
	#  CE QUI SUIT EXISTE PARCE QUE LA NUIT PASSAIT AU VERT SANS RIEN MESURER.
	#  Le repli en dur de lexos-terminal vaut justement 38;5;208, c'est-à-dire
	#  l'accent de NUIT : une sonde qui lisait le MAUVAIS fichier verdissait
	#  quand même pour ce mode-là, et seul le jour disait la vérité. On relève
	#  donc les deux valeurs observées, et on exige qu'elles DIFFÈRENT — si la
	#  sonde lit ailleurs, elle rend deux fois la même et la garde mord.
	VU_ACC=""
	for MODE in jour nuit; do
		D="$BANC/acc-$MODE"; mkdir -p "$D/.config"
		HOME="$D" XDG_CONFIG_HOME="$D/.config" bash "$GEN" --mode "$MODE" >/dev/null 2>&1 || true
		E="$D/.config/lexos/terminal.env"
		if [ ! -r "$E" ]; then
			non "$MODE : le générateur n'a pas écrit terminal.env — on ne conclut rien sur l'accent"
			continue
		fi
		A_VRAI="$(sed -n "s/^LEXOS_PS_ACCENT='\(.*\)'$/\1/p" "$E")"
		A_256="$(sed -n "s/^LEXOS_PS_ACCENT_256='\(.*\)'$/\1/p" "$E")"
		BG="$(sed -n 's/^LEXOS_TERM_BG=//p' "$E")"
		if [ -z "$A_VRAI" ] || [ -z "$A_256" ]; then
			non "$MODE : terminal.env ne porte pas les deux écritures de l'accent (vraie : « $A_VRAI », 256 : « $A_256 »)"
			continue
		fi
		ok "$MODE : l'accent a ses deux écritures ($A_VRAI et $A_256)"
		#  Le contraste sur le fond DE CE MODE. C'est le défaut même : la
		#  valeur de nuit sur le fond de jour donnait 2,21:1.
		K="$(python3 "$CONTRASTE" "$A_256" "$BG")"
		if [ -z "$K" ]; then
			non "$MODE : le contraste de l'accent 256 n'a pas pu être mesuré"
		else
			case "$(awk -v k="$K" 'BEGIN{print (k>=4.5)?"oui":"non"}')" in
				oui) ok "$MODE : l'accent 256 se lit sur son fond — $K:1 sur $BG" ;;
				*)   non "$MODE : l'accent 256 ne donne que $K:1 sur $BG (seuil AA 4,5)" ;;
			esac
		fi
		#  LA BASCULE LE LIT-ELLE ? Sans COLORTERM, c'est-à-dire sur la
		#  surface où le défaut vivait.
		if [ -x "$BASCULE" ] && command -v script >/dev/null 2>&1; then
			#  ⚠ XDG_CONFIG_HOME EST OBLIGATOIRE ICI, ET SON ABSENCE A FAIT
			#  ROUGIR LA CI. lexos-terminal lit
			#  « ${XDG_CONFIG_HOME:-$HOME/.config}/lexos » : la variable GAGNE
			#  sur HOME. Épingler HOME seul laissait donc la sonde lire le
			#  terminal.env de la machine qui fait tourner le banc — vert ici,
			#  rouge sur le coureur, qui la définit. Troisième fois que ce
			#  banc se fait prendre à hériter de l'environnement.
			VU="$(HOME="$D" XDG_CONFIG_HOME="$D/.config" \
				PATH="$RACINE/config/includes.chroot/usr/bin:$PATH" \
				TERM=xterm-256color NO_COLOR="" \
				env -u COLORTERM script -qec "bash '$BASCULE' etat" /dev/null 2>/dev/null || true)"
			case "$VU" in
				*"${ESCB}[${A_256}m"*)
					ok "$MODE : « lexos terminal » met sa ligne « Mode » dans l'accent du thème ($A_256)"
					VU_ACC="$VU_ACC $MODE=$A_256" ;;
				*)  non "$MODE : « lexos terminal » n'a pas pris l'accent $A_256 — il garde celui d'un autre thème" ;;
			esac
		fi
		#  ET LE MENU D'AUDIT, dans les deux profondeurs.
		if [ -r "$MENU" ]; then
			for CT in "" truecolor; do
				ATT="$A_256"; [ -n "$CT" ] && ATT="$A_VRAI"
				VU_A="$(XDG_CONFIG_HOME="$D/.config" COLORTERM="$CT" MENU_DIR="$MENU_DIR" python3 -c "
import os, sys
sys.path.insert(0, os.environ['MENU_DIR'])
import menu
print(menu._accent())
" 2>/dev/null)"
				PROF=256; [ -n "$CT" ] && PROF=vraie
				if [ -z "$VU_A" ]; then
					non "$MODE/$PROF : le menu d'audit n'a pas pu être interrogé sur son accent"
				elif [ "$VU_A" = "$ATT" ]; then
					ok "$MODE/$PROF : le menu d'audit prend l'accent du générateur ($VU_A)"
				else
					non "$MODE/$PROF : le menu d'audit rend « $VU_A » là où le générateur dit « $ATT »"
				fi
			done
		fi
	done

	#  LA GARDE : deux modes, deux accents OBSERVÉS, et ils doivent différer.
	case "$VU_ACC" in
		*jour=*nuit=*|*nuit=*jour=*)
			J_OBS="${VU_ACC#* jour=}"; J_OBS="${J_OBS%% *}"
			N_OBS="${VU_ACC#* nuit=}"; N_OBS="${N_OBS%% *}"
			if [ "$J_OBS" = "$N_OBS" ]; then
				non "« lexos terminal » rend le MÊME accent de jour et de nuit ($J_OBS) — la sonde ne lit pas le thème qu'on lui donne"
			else
				ok "« lexos terminal » rend deux accents distincts selon le mode ($J_OBS / $N_OBS) — la sonde lit bien le bon fichier"
			fi ;;
		*)  non "l'accent de « lexos terminal » n'a pas été observé dans les deux modes — on ne conclut pas qu'il suit le thème" ;;
	esac

	#  ═══ ET LES DEUX DERNIERS PORTEURS DU VERT MACHINE ═══
	#  Le repli de ia-agent.py valait 38;5;35 — le vert de LEXOS, pas celui
	#  des réponses de la machine. Le contrôle du banc du terminal cherche
	#  « \033[ » et ne peut pas voir une couleur rangée nue : la divergence
	#  a donc survécu à trois corrections. Ici on la COMPARE au générateur.
	AGENT="$RACINE/config/includes.chroot/usr/lib/lexos/ia-agent.py"
	REF_M256="$(sed -n "s/^LEXOS_PS_MACHINE_256='\(.*\)'$/\1/p" "$BANC/acc-nuit/.config/lexos/terminal.env")"
	if [ ! -r "$AGENT" ] || [ -z "$REF_M256" ]; then
		non "ia-agent.py ou la référence du vert machine est illisible — on ne conclut rien"
	else
		R_AG="$(code_nu "$AGENT" | sed -n 's/.*LEXOS_PS_MACHINE_256") or "\([^"]*\)".*/\1/p' | head -1)"
		if [ -z "$R_AG" ]; then
			non "le repli du vert machine de ia-agent.py est introuvable"
		elif [ "$R_AG" = "$REF_M256" ]; then
			ok "ia-agent.py replie le vert machine sur la valeur du générateur ($R_AG)"
		else
			non "ia-agent.py replie le vert machine sur $R_AG là où le générateur dit $REF_M256"
		fi
	fi
	#  tmux : message-style se dit « le vert des réponses de la machine ». Le
	#  banc ne lisait que status-left et status-style ; message-style était
	#  resté en colour35 quand status-style est passé en colour40.
	if [ -r "$TMUXC" ]; then
		tmux_nu2() { sed '/^[[:space:]]*#/d' "$1"; }
		M_MSG="$(tmux_nu2 "$TMUXC" | sed -n 's/.*message-style .*fg=colour\([0-9]*\)".*/\1/p' | head -1)"
		M_ST="$(tmux_nu2 "$TMUXC" | sed -n 's/.*status-style .*fg=colour\([0-9]*\)".*/\1/p' | head -1)"
		if [ -z "$M_MSG" ] || [ -z "$M_ST" ]; then
			non "tmux : message-style ou status-style est illisible — on ne conclut rien"
		elif [ "$M_MSG" = "$M_ST" ]; then
			ok "tmux : les messages portent le même vert machine que la barre (colour$M_MSG)"
		else
			non "tmux : les messages sont en colour$M_MSG, la barre en colour$M_ST — deux verts pour un rôle"
		fi
	fi
fi

# =============================================================================
titre "L'invite « pro » : le petit bateau (défaut depuis le 2026-10-31)"
#  ALEX : « une invite spéciale un peu comme Kali, mais version LexOS […]
#  comme un ti bateau (__________-> ». Sans choix écrit, c'est elle.
PRO_XDG="$BANC/pro-config"; mkdir -p "$PRO_XDG"
pro() { HOME="$BANC/home" XDG_CONFIG_HOME="$PRO_XDG" COLORTERM="$2" TERM=xterm-256color bash --norc --noprofile -i -c \
	". \"$SH\"; __lexos_code=$1; printf '%s' \"\${PS1@P}\"" 2>/dev/null | tr -d '\001\002'; }
VU="$(pro 0 truecolor)"; TXT="$(printf '%s' "$VU" | sed 's/\x1b\[[0-9;]*m//g')"
case "$TXT" in *"╭──("*")─["*"]"*) ok "ligne 1 : ╭──(nom)─[chemin]" ;; *) non "ligne 1 inattendue : $TXT" ;; esac
case "$TXT" in *"@lexos)"*) non "ligne 1 : « @lexos » ne doit plus y être : $TXT" ;; *) ok "ligne 1 : le nom seul, sans @lexos" ;; esac
case "$TXT" in *"╰─(lexos)──➜ "*) ok "ligne 2 : « lexos » sous le nom ╰─(lexos)──➜" ;; *) non "pas de « lexos » en 2e ligne : $TXT" ;; esac
case "$VU" in *"38;2;255;106;26m"*) ok "cadre en orange LexOS (#FF6A1A)" ;; *) non "cadre pas orange" ;; esac
ERR="$(pro 1 truecolor)"
case "$ERR" in *"lexos"*")──"*"38;5;196m"*"➜"*) ok "la flèche du bateau devient rouge après une erreur" ;;
	*")──"*"196"*) ok "la flèche du bateau devient rouge après une erreur" ;; *) non "flèche pas rouge après une erreur" ;; esac
case "$(pro 0 "")" in *"38;5;202m"*) ok "repli 256 couleurs : orange 202" ;; *) non "repli 256 couleurs absent" ;; esac

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mL'"'"'invite tient sur une ligne, en vert, et ce qu'"'"'on tape est blanc.\033[0m\n'
