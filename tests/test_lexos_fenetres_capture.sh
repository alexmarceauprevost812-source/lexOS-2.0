#!/usr/bin/env bash
# =============================================================================
#  Les trois pastilles, la capture qu'on peut fermer, l'agenda qui a une fin
# =============================================================================
#  QUATRE DEMANDES D'ALEX, LE MÊME JOUR.
#
#  1. « On pourrait garder en haut à droite : bouton rouge pour fermer,
#     bouton jaune pour réduire, bouton gris pour mettre la page de côté. »
#     Il n'y avait AUCUN bouton réduire : button_layout valait « |OMC ».
#
#  2. « Pouvoir fermer la fenêtre de la capture d'écran. » La bulle attendait
#     un clic sur l'une de ses deux actions, qui FAISAIENT toutes deux
#     quelque chose : on ne pouvait pas s'en débarrasser.
#
#  3. « Quand on prend une capture d'écran, faire en sorte que ce soit
#     écriture noire. » Le rappel des raccourcis s'affichait en blanc sur
#     l'orange : 3,58:1, sous le seuil lisible.
#
#  4. « Ajouter une heure de fin d'événement — dans le calendrier. »
#
#  ── CE QUE CE BANC ÉPROUVE, ET COMMENT ─────────────────────────────────────
#  Il FAIT TOURNER ce qui peut l'être : le crochet des fenêtres sur un vrai
#  thème Arc, l'agenda sur un vrai dossier. Il ne relit une intention que là
#  où il n'y a rien à exécuter.
#
#  LA LEÇON DU JOUR, INSCRITE ICI : l'heure de fin a d'abord été ajoutée à
#  l'écriture et à la page — et PERDUE à la relecture, parce que le filtre de
#  _agenda_lit() ne recopie que les champs qu'il connaît. Le rendez-vous
#  s'enregistrait, sa fin disparaissait sans un mot. Trouvé en faisant tourner
#  l'aller-retour complet, jamais en relisant le code.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saute() { printf '  \033[33m•\033[0m %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

XFWM="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
HOOK="$RACINE/config/hooks/normal/0610-lexos-fenetres.hook.chroot"
CAPTURE="$RACINE/config/includes.chroot/usr/bin/lexos-capture"
THEME_GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
VOLET_PY="$RACINE/config/includes.chroot/usr/lib/lexos/volet.py"
VOLET_JS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/app.js"

# =============================================================================
titre "1. Les trois boutons existent, dans le bon ordre"
# =============================================================================
LAYOUT="$(grep -o 'button_layout"[^>]*value="[^"]*"' "$XFWM" | sed 's/.*value="//;s/"//')"
if [[ -z "$LAYOUT" ]]; then
	non "button_layout introuvable — le reste de cette section serait creux"
else
	ok "button_layout lu dans le squelette : « $LAYOUT »"
fi
#  « H » (hide) EST LE CŒUR DE LA DEMANDE : sans lui, aucune fenêtre ne peut
#  être réduite à la souris. C'est ce qui manquait.
case "$LAYOUT" in
	*H*) ok "« H » présent — les fenêtres peuvent enfin être réduites" ;;
	*)   non "« H » absent : aucun bouton pour réduire, le bogue d'Alex" ;;
esac
case "$LAYOUT" in
	*M*) ok "« M » présent — mettre la page de côté" ;;
	*)   non "« M » absent : plus de bouton pour agrandir" ;;
esac
case "$LAYOUT" in
	*C*) ok "« C » présent — fermer" ;;
	*)   non "« C » absent : plus de bouton pour fermer, ce serait pire que tout" ;;
esac
#  L'ORDRE COMPTE : fermer doit être le DERNIER, donc le plus loin du doigt
#  qui vise « réduire ». Un « C » au milieu ferait fermer par mégarde.
DROITE="${LAYOUT#*|}"
if [[ "${DROITE: -1}" == "C" ]]; then
	ok "« fermer » est le dernier — le plus loin du doigt qui vise « réduire »"
else
	non "« fermer » n'est pas au bout ($DROITE) : on fermerait par mégarde"
fi
#  ET TOUT EST À DROITE, ce qu'Alex demande : ce qui précède la barre
#  verticale serait aligné à GAUCHE.
GAUCHE="${LAYOUT%%|*}"
if [[ -z "$GAUCHE" ]]; then
	ok "aucun bouton à gauche — les trois sont en haut à droite"
else
	non "« $GAUCHE » serait aligné à gauche, pas à droite"
fi

# =============================================================================
titre "2. Le crochet peint vraiment les pastilles (on le FAIT TOURNER)"
# =============================================================================
#  On ne grep pas le crochet : on l'exécute sur un vrai thème Arc et on relit
#  les pixels qu'il a produits. C'est la seule façon de savoir qu'un dessin
#  ressemble à ce qu'on croyait dessiner — une première version du tiret
#  traversait tout le disque, et seule l'image l'a montré.
ARC="$(ls -d /usr/share/themes/Arc-Dark 2>/dev/null | head -1)"
if [[ -z "$ARC" ]]; then
	saute "Arc-Dark absent de cette machine : le rendu réel n'a pas pu être éprouvé"
elif ! command -v convert >/dev/null 2>&1 && ! command -v magick >/dev/null 2>&1; then
	saute "ni convert ni magick : le rendu réel n'a pas pu être éprouvé"
else
	mkdir -p "$BANC/themes"
	cp -a "$ARC" "$BANC/themes/" 2>/dev/null
	SORTIE="$(LEXOS_THEMES="$BANC/themes" LEXOS_BUILD_CONF="$BANC/b.conf" \
	          LEXOS_XFWM_XML="$BANC/f.xml" sh "$HOOK" 2>&1 || true)"
	for B in hide maximize; do
		if printf '%s' "$SORTIE" | grep -q "pastille « $B » peinte : 4/4"; then
			ok "« $B » : les quatre états peints (actif, survol, pressé, inactif)"
		else
			non "« $B » : les quatre états n'ont pas été peints"
		fi
	done
	#  ET LA COULEUR EST BIEN CELLE QU'ON CROIT. On relit le pixel du disque.
	D="$BANC/themes/LexOS-Arc-Dark/xfwm4"
	if [[ -f "$D/hide-active.png" ]] && command -v python3 >/dev/null 2>&1; then
		python3 - "$D" <<'PY'
from PIL import Image
import sys, os
D = sys.argv[1]
def teinte(f):
    im = Image.open(os.path.join(D, f)).convert("RGBA"); px = im.load()
    w, h = im.size
    #  OÙ MESURER, ET POURQUOI PAS AILLEURS. Une première version relevait
    #  le pixel (w/2, h/2 - h/5) — juste sous le haut du disque. Pour le
    #  tiret de « réduire » ça tombait juste ; pour le CARRÉ de « mettre de
    #  côté », ça tombait pile sur son trait du haut, c'est-à-dire sur le
    #  creux, et le banc annonçait « pas gris » alors que le disque l'était.
    #  Le banc avait tort, pas le dessin.
    #
    #  On relève donc à mi-hauteur, à un quart de la largeur : dans le
    #  disque à coup sûr, et à gauche du glyphe quel qu'il soit.
    return px[w // 2 - w // 4, h // 2]
j = teinte("hide-active.png")
g = teinte("maximize-active.png")
#  Jaune : rouge et vert forts, bleu faible. Gris : les trois proches.
if j[0] > 150 and j[1] > 120 and j[2] < 110:
    print("OK|le disque « réduire » est bien JAUNE %s" % (j[:3],))
else:
    print("NON|le disque « réduire » n'est pas jaune %s" % (j[:3],))
if abs(g[0]-g[1]) < 40 and abs(g[1]-g[2]) < 40 and g[0] > 100:
    print("OK|le disque « de côté » est bien GRIS %s" % (g[:3],))
else:
    print("NON|le disque « de côté » n'est pas gris %s" % (g[:3],))
PY
	fi | while IFS='|' read -r verdict message; do
		[[ "$verdict" == "OK" ]] && ok "$message" || non "$message"
	done
	#  LE CREUX SUIT LE THÈME, il n'est pas écrit en dur : sombre pour
	#  Arc-Dark, clair pour Arc. Un ton figé aurait donné des boutons justes
	#  en sombre et faux en clair.
	if printf '%s' "$SORTIE" | grep -q 'creux srgba\?(4[0-9],'; then
		ok "le creux a été LU dans le thème sombre, pas écrit en dur"
	else
		non "le creux ne vient pas du thème : $(printf '%s' "$SORTIE" | grep -o 'creux [^)]*)' | head -1)"
	fi
fi

# =============================================================================
titre "3. La bulle de capture peut être fermée"
# =============================================================================
if grep -q 'fermer=Fermer' "$CAPTURE"; then
	ok "un bouton « Fermer » est proposé"
else
	non "aucun bouton pour fermer : la bulle resterait à l'écran, comme sur la photo"
fi
#  ET IL NE DOIT RIEN FAIRE D'AUTRE : pas de branche dans le « case ». Une
#  action « fermer » qui ouvrirait un dossier serait un piège.
if grep -qE '^\s*fermer\)' "$CAPTURE"; then
	non "« fermer » a une branche dans le case — il ferait autre chose que fermer"
else
	ok "« fermer » ne fait que fermer — aucune branche dans le case"
fi
#  UNE EXPIRATION pour qui ne clique rien du tout.
if grep -q 'notify-send -w -t [0-9]' "$CAPTURE"; then
	ok "la bulle expire d'elle-même si personne ne clique"
else
	non "sans expiration, une bulle ignorée resterait jusqu'à la fin de la session"
fi
#  LA BULLE EN DOUBLE DE FLAMESHOT EST COUPÉE.
if grep -q 'showDesktopNotification=false' "$THEME_GEN"; then
	ok "la bulle « Flameshot Info » en double est coupée"
else
	non "deux bulles pour une capture — celle de flameshot n'est pas coupée"
fi

# =============================================================================
titre "4. Le texte du rappel des raccourcis est lisible"
# =============================================================================
#  flameshot choisit LUI-MÊME la couleur de ce texte d'après la clarté de
#  « uiColor » — éprouvé sous un serveur X virtuel, pas deviné : avec
#  contrastUiColor déjà à #000000, l'écriture restait blanche. Mesuré :
#  #E8590C donne du blanc, #FF7A33 donne du noir. On exige donc l'accent HAUT.
if grep -q 'uiColor=\${ACCENT_HI}' "$THEME_GEN"; then
	ok "flameshot reçoit l'accent HAUT — c'est lui qui fait basculer le texte en noir"
else
	non "flameshot reçoit l'accent principal : son rappel resterait en blanc (3,58:1)"
fi
#  ET LA COULEUR D'ICÔNE EST CALCULÉE SUR LA MÊME COULEUR. La mesurer sur
#  l'accent principal alors que le fond est l'accent haut serait mesurer le
#  contraste sur la mauvaise couleur.
if grep -q 'contrastUiColor=\$(texte_lisible "\$ACCENT_HI")' "$THEME_GEN"; then
	ok "l'icône est calculée sur la couleur qui est VRAIMENT derrière elle"
else
	non "l'icône est calculée sur une autre couleur que son fond"
fi

# =============================================================================
titre "5. L'agenda garde l'heure de fin — l'aller ET le retour"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : l'agenda n'a pas pu être éprouvé"
else
	HOME="$BANC/foyer" python3 - "$VOLET_PY" <<'PY' | while IFS='|' read -r v m; do
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("volet", sys.argv[1])
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)

def dit(ok, msg): print(("OK|" if ok else "NON|") + msg)

r = v.act_agenda_ajoute({"jour":"2026-08-30","titre":"Dentiste",
                         "heure":"09:00","fin":"10:30"})
dit(r.get("ok"), "un rendez-vous avec une heure de fin est accepté")

#  LE CŒUR : la fin doit SURVIVRE à l'écriture puis à la relecture. C'est
#  ici que le premier correctif échouait — le filtre de _agenda_lit() ne
#  recopiait que titre et heure, et jetait la fin en silence.
relu = v._agenda_lit().get("2026-08-30", [])
garde = any(e.get("fin") == "10:30" for e in relu)
dit(garde, "et sa fin survit à l'aller-retour par le disque")

r = v.act_agenda_ajoute({"jour":"2026-08-30","titre":"Courses","heure":"14:00"})
dit(r.get("ok"), "un rendez-vous SANS fin marche toujours (elle est facultative)")

r = v.act_agenda_ajoute({"jour":"2026-08-30","titre":"Faute",
                         "heure":"14:00","fin":"09:00"})
dit(not r.get("ok"), "une fin AVANT le début est refusée, avec son motif")

r = v.act_agenda_ajoute({"jour":"2026-08-30","titre":"Orphelin","fin":"10:00"})
dit(not r.get("ok"), "une fin SANS début est refusée — elle ne voudrait rien dire")

r = v.act_agenda_ajoute({"jour":"2026-08-30","titre":"Bof",
                         "heure":"09:00","fin":"25:99"})
dit(not r.get("ok"), "une fin mal écrite est refusée")
PY
		[[ "$v" == "OK" ]] && ok "$m" || non "$m"
	done
fi
#  LA PAGE DOIT L'ENVOYER, sinon le moteur ne la recevrait jamais.
if grep -q '"agF"' "$VOLET_JS" && grep -q 'fin:' "$VOLET_JS"; then
	ok "la page porte un champ de fin et l'envoie au moteur"
else
	non "la page n'envoie pas de fin : le moteur ne la verrait jamais"
fi
#  ET L'AFFICHER, sinon on l'enregistrerait sans jamais la revoir.
if grep -q 'e.fin ?' "$VOLET_JS"; then
	ok "et elle l'affiche dans la liste du jour"
else
	non "la fin est enregistrée mais jamais montrée"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
