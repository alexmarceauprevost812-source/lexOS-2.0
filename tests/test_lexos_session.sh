#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-session — le bouton rouge
# =============================================================================
#  POURQUOI CE BANC EXISTE, ET POURQUOI IL EST PARTICULIER.
#
#  Tous les autres outils de LexOS, on peut les lancer pour voir. Celui-ci
#  ÉTEINT LA MACHINE. On ne le relit donc pas en hochant la tête — on lui
#  donne de faux outils sur un PATH fermé, et on regarde ce qu'il appelle.
#
#  DEUX RÉGIMES, ET LES DEUX COMPTENT :
#
#    · LEXOS_SESSION_SIMULE=1 — le programme ÉCRIT la commande au lieu de
#      l'exécuter, et « dispo » répond oui à tout. C'est le seul moyen
#      d'éprouver le CHEMIN NORMAL (celui d'une vraie machine XFCE) depuis
#      un conteneur qui n'a ni xfce4-session-logout ni dm-tool.
#
#    · PATH FERMÉ + faux outils — la simulation est ÉTEINTE, « dispo » et
#      « lancer » travaillent pour de vrai, et les faux outils écrivent
#      dans un journal. C'est ce régime-là qui éprouve les REPLIS : sans
#      xfce4-session-logout, est-ce bien systemctl qui prend le relais ?
#      Sans rien du tout, est-ce qu'il le DIT au lieu de rendre 0 ?
#
#  Le second régime est indispensable : en simulation, « dispo » répond oui
#  à tout, donc le premier outil de chaque liste gagne toujours et aucun
#  repli n'est jamais emprunté. Un banc qui n'aurait que la simulation
#  déclarerait les replis corrects sans en avoir exécuté un seul.
# =============================================================================
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-session"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-session introuvable ou non exécutable"; exit 1; }

# --- Un PATH fermé : rien d'autre que ce qu'on y met -------------------------
#  Sans ça, « systemctl absent » ne prouverait rien : la machine hôte
#  pourrait en avoir un vrai, et le repli ne serait jamais éprouvé. C'est
#  l'erreur commise sur test_lexos_materiel, corrigée là-bas puis reprise
#  ici d'emblée.
NECESSAIRES="bash sh env cat id printf echo command"
ferme_path() {
	rm -rf "${BANC:?}/min"; mkdir -p "$BANC/min"
	for c in $NECESSAIRES; do
		reel="$(command -v "$c" 2>/dev/null)" && ln -sf "$reel" "$BANC/min/$c"
	done
}

JOURNAL="$BANC/appels.txt"

#  Fabrique de faux outils qui NOTENT ce qu'on leur demande.
faux() {
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	for n in "$@"; do
		cat > "$BANC/bin/$n" <<SH
#!/bin/sh
echo "$n \$*" >> "$JOURNAL"
SH
		chmod +x "$BANC/bin/$n"
	done
}

#  Lance l'outil sans simulation, sur le PATH fermé + les faux outils.
reel() {
	: > "$JOURNAL"
	PATH="$BANC/bin:$BANC/min" DISPLAY=":0" "$OUTIL" "$@" 2>"$BANC/err.txt"
	echo "$?" > "$BANC/rc.txt"
}
rc()      { cat "$BANC/rc.txt"; }
appels()  { cat "$JOURNAL" 2>/dev/null; }
erreurs() { cat "$BANC/err.txt" 2>/dev/null; }

#  Lance l'outil en simulation : il écrit la commande qu'il aurait lancée.
simule() { LEXOS_SESSION_SIMULE=1 DISPLAY=":0" "$OUTIL" "$@" 2>&1; }

ferme_path

# ═════════════════════════════════════════════════════════════════════════════
titre "1. Chaque geste appelle la bonne commande (chemin normal)"
#  Ce que fait une VRAIE machine LexOS : xfce4-session-logout est là, dm-tool
#  aussi. On vérifie le premier choix de chaque liste, et les options.
declare -A ATTENDU=(
	[eteindre]="xfce4-session-logout --halt --fast"
	[redemarrer]="xfce4-session-logout --reboot --fast"
	[veille]="xfce4-session-logout --suspend"
	[deconnexion]="xfce4-session-logout --logout --fast"
	[utilisateur]="dm-tool switch-to-greeter"
	[verrouiller]="xflock4"
)
for g in eteindre redemarrer veille deconnexion utilisateur verrouiller; do
	VU="$(simule "$g")"
	if [ "$VU" = "${ATTENDU[$g]}" ]; then
		ok "« $g » -> ${ATTENDU[$g]}"
	else
		non "« $g » a donné « $VU » au lieu de « ${ATTENDU[$g]} »"
	fi
done

#  « --fast » sur l'arrêt, le redémarrage et la déconnexion, PAS sur la
#  veille : xfce4-session-logout demanderait sinon confirmation par-dessus
#  NOTRE fenêtre, qui est déjà la confirmation. Deux questions pour un geste,
#  c'est une de trop — et c'est le genre de détail qui se perd à la
#  relecture suivante si rien ne le tient.
[ "$(simule veille)" = "xfce4-session-logout --suspend" ] \
	&& ok "la veille ne porte pas « --fast » (rien à enregistrer)" \
	|| non "la veille a changé d'options"

# ═════════════════════════════════════════════════════════════════════════════
titre "2. Les replis, éprouvés pour de vrai (pas en simulation)"
#  Sans xfce4-session-logout : systemctl doit prendre le relais.
faux systemctl loginctl dm-tool
reel eteindre
[ "$(appels)" = "systemctl poweroff" ] \
	&& ok "sans xfce4-session-logout, l'arrêt passe par systemctl" \
	|| non "repli 1 de l'arrêt : « $(appels) »"

reel deconnexion
#  Sans XDG_SESSION_ID, loginctl ne saurait pas QUELLE session terminer :
#  l'outil doit s'abstenir plutôt que d'en couper une au hasard.
[ -z "$(appels)" ] && [ "$(rc)" != "0" ] \
	&& ok "déconnexion sans XDG_SESSION_ID : on s'abstient et on le dit" \
	|| non "il a tenté quelque chose sans savoir quelle session : « $(appels) »"

: > "$JOURNAL"
PATH="$BANC/bin:$BANC/min" DISPLAY=":0" XDG_SESSION_ID="c7" "$OUTIL" deconnexion 2>/dev/null
[ "$(appels)" = "loginctl terminate-session c7" ] \
	&& ok "avec XDG_SESSION_ID, il termine LA BONNE session" \
	|| non "repli de déconnexion : « $(appels) »"

#  Sans systemctl non plus : loginctl.
faux loginctl
reel eteindre
[ "$(appels)" = "loginctl poweroff" ] \
	&& ok "sans systemctl non plus, l'arrêt passe par loginctl" \
	|| non "repli 2 de l'arrêt : « $(appels) »"

#  Plus rien du tout : il doit le DIRE et rendre non-zéro. Une machine qui
#  ne s'éteint pas ET ne dit rien, c'est quelqu'un qui reclique dix fois.
faux
reel eteindre
if [ "$(rc)" != "0" ] && erreurs | grep -q "rien pour éteindre"; then
	ok "sans aucun outil, il refuse ET nomme ce qui manque"
else
	non "sans outil : rc=$(rc), message « $(erreurs) »"
fi

faux
reel utilisateur
if [ "$(rc)" != "0" ] && erreurs | grep -qi "gestionnaire de connexion"; then
	ok "sans gestionnaire de connexion, il le dit au lieu de faire semblant"
else
	non "changement d'utilisateur sans dm-tool : rc=$(rc), « $(erreurs) »"
fi

#  VERROUILLER — les mêmes replis en cascade que les autres gestes.
faux light-locker-command xfce4-screensaver-command loginctl
reel verrouiller
[ "$(appels)" = "light-locker-command -l" ] \
	&& ok "sans xflock4, verrouiller passe par light-locker-command -l" \
	|| non "repli 1 de verrouiller : « $(appels) »"

faux xfce4-screensaver-command loginctl
reel verrouiller
[ "$(appels)" = "xfce4-screensaver-command -l" ] \
	&& ok "sans light-locker non plus, xfce4-screensaver-command -l prend le relais" \
	|| non "repli 2 de verrouiller : « $(appels) »"

faux loginctl
reel verrouiller
[ "$(appels)" = "loginctl lock-session" ] \
	&& ok "en tout dernier recours, loginctl lock-session" \
	|| non "repli 3 de verrouiller : « $(appels) »"

faux
reel verrouiller
if [ "$(rc)" != "0" ] && erreurs | grep -q "rien pour verrouiller"; then
	ok "sans aucun outil de verrouillage, il le dit au lieu de rendre 0 en silence"
else
	non "verrouiller sans outil : rc=$(rc), « $(erreurs) »"
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "3. Sans écran, il ne coupe RIEN"
#  Le piège de cette famille d'outils : « pas d'affichage » ne doit surtout
#  pas vouloir dire « fais-le quand même ». Quelqu'un en ssh qui tape
#  « lexos session » par curiosité ne doit pas éteindre la machine de
#  quelqu'un d'autre.
faux xfce4-session-logout systemctl loginctl dm-tool
: > "$JOURNAL"
SORTIE="$(PATH="$BANC/bin:$BANC/min" env -u DISPLAY -u WAYLAND_DISPLAY "$OUTIL" 2>&1)"
RC=$?
[ -z "$(appels)" ] \
	&& ok "sans écran, aucune commande n'est lancée" \
	|| non "sans écran il a lancé : « $(appels) »"
[ "$RC" = "0" ] \
	&& ok "et il sort proprement (code 0)" \
	|| non "code de sortie $RC sans écran"
echo "$SORTIE" | grep -q "lexos session eteindre" \
	&& ok "il dit quoi taper à la place" \
	|| non "aucune indication en console"

# ═════════════════════════════════════════════════════════════════════════════
titre "4. Ce qu'il doit refuser"
faux xfce4-session-logout systemctl loginctl dm-tool
reel nimportequoi
[ "$(rc)" != "0" ] && [ -z "$(appels)" ] \
	&& ok "un geste inconnu est refusé, et rien n'est lancé" \
	|| non "geste inconnu : rc=$(rc), appels « $(appels) »"

reel aide
[ "$(rc)" = "0" ] && [ -z "$(appels)" ] \
	&& ok "« aide » n'exécute rien" \
	|| non "« aide » a lancé quelque chose : « $(appels) »"

# ═════════════════════════════════════════════════════════════════════════════
titre "5. Le greffon d'actions a disparu de la barre — tout vit dans la fenêtre"
# ═════════════════════════════════════════════════════════════════════════════
#  DEUXIÈME PASSE, APRÈS LES PHOTOS DE TROP D'OUTILS ET DU DAMIER GRIS. Le
#  greffon 8 (« actions » : verrouiller, veille, redémarrer) devait d'abord
#  garder verrouiller ; Alex l'a ensuite jugé inutile ET a demandé que tout
#  rejoigne le bouton rouge. Le greffon 8 n'existe donc plus DU TOUT, ni son
#  numéro dans plugin-ids : s'il restait quelque part, aux deux endroits ou
#  à aucun, personne ne s'en apercevrait avant la photo suivante.
PANEL="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
PRESENT_8="$(python3 - "$PANEL" <<'PYXML8'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
print(any(p.get("name") == "plugin-8" for p in r.iter("property")))
PYXML8
)"
[ "$PRESENT_8" = "False" ] \
	&& ok "le greffon 8 (verrouiller/veille/redémarrer) n'existe plus dans le panneau" \
	|| non "le greffon 8 est encore défini — les trois boutons d'origine sont peut-être encore là"

DANS_IDS_8="$(python3 - "$PANEL" <<'PYIDS8'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-ids":
        print("8" in [v.get("value") for v in p])
PYIDS8
)"
[ "$DANS_IDS_8" = "False" ] \
	&& ok "et son numéro n'apparaît plus dans plugin-ids — pas de trou, pas de fantôme" \
	|| non "« 8 » traîne encore dans plugin-ids sans définition : XFCE afficherait un greffon cassé"

#  Et le bouton rouge doit toujours être le DERNIER greffon : c'est ce qui le
#  met tout à droite de l'écran, la demande d'Alex mot pour mot — ça n'a pas
#  changé en retirant le greffon 8.
DERNIER="$(python3 - "$PANEL" <<'PYLAST'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-ids":
        print([v.get("value") for v in p][-1])
PYLAST
)"
[ "$DERNIER" = "17" ] \
	&& ok "le greffon 17 (bouton rouge) est le dernier — donc le plus à droite" \
	|| non "le dernier greffon est « $DERNIER », pas 17 : le rouge n'est pas au bout"

#  VEILLE ET REDÉMARRER DOIVENT DONC VIVRE ICI, DANS LA FENÊTRE — sinon ils
#  ont disparu du système tout entier, pas juste de la barre.
#
#  ═══ LA FENÊTRE A CHANGÉ DE FORME, ET CES CONTRÔLES AVEC ELLE ═══
#  ALEX : « j'aimerais que ce soit une petite fenêtre qui ouvre dans le
#  côté, au lieu de le voir comme sur la 2e image ». Les six gestes étaient
#  six BOUTONS DE DIALOGUE (--button="…:5") ; yad range ces boutons-là sur
#  une seule rangée horizontale et élargit la fenêtre jusqu'à ce qu'ils
#  tiennent tous — d'où la barre qui traversait l'écran. Ils sont devenus
#  les LIGNES d'une liste verticale, et l'aiguillage se fait maintenant sur
#  le libellé rendu, plus sur un code de sortie. On éprouve donc la ligne ET
#  son aiguillage, comme avant, mais dans la nouvelle forme.
verifie_geste() { # verifie_geste <libellé> <fonction>
	#  Les lignes de la liste se terminent par «  \ » (continuation) : le
	#  motif doit l'accepter, sinon aucune ne correspond jamais.
	grep -qE "^[[:space:]]+\"$1\"[[:space:]]*\\\\?$" "$OUTIL" \
		&& ok "la fenêtre propose « $1 »" \
		|| non "« $1 » a disparu à la fois de la barre ET de la fenêtre"
	grep -qE "\"$1\"\)[[:space:]]+$2 ;;" "$OUTIL" \
		&& ok "…et « $1 » appelle bien le geste $2()" \
		|| non "« $1 » est affiché mais n'appelle rien"
}
verifie_geste "Redémarrer" redemarrer
verifie_geste "Mise en veille" veille

#  LA PETITE FENÊTRE SUR LE CÔTÉ, c'est la demande elle-même : une liste
#  verticale (la largeur ne dépend plus du nombre de gestes) et une position
#  calculée sur le bord, pas au centre.
grep -q -- '--list' "$OUTIL" \
	&& ok "les gestes sont une LISTE verticale — la fenêtre peut rester étroite" \
	|| non "la fenêtre emploie encore des boutons en rangée : elle traversera l'écran"
grep -q -- '--posx=' "$OUTIL" \
	&& ok "elle s'ouvre sur le côté (position calculée d'après la largeur de l'écran)" \
	|| non "aucune position : la fenêtre resterait au centre"
grep -q 'POSITION=(--center)' "$OUTIL" \
	&& ok "…et sans xrandr, elle retombe au centre plutôt que sur une position inventée" \
	|| non "sans xrandr, la position serait devinée"

#  VERROUILLER — TROISIÈME PASSE. Alex l'avait jugé inutile devant un damier
#  gris (l'icône CASSÉE du greffon d'actions, pas le verrouillage lui-même),
#  puis il l'a redemandé — cette fois dans la fenêtre du bouton rouge, avec
#  arrêter/redémarrer/veille/changer d'utilisateur. Il doit donc y être, par
#  la vraie commande système (xflock4), pas par l'ancien greffon.
verifie_geste "Verrouiller l'écran" verrouiller
grep -q 'dispo xflock4' "$OUTIL" \
	&& ok "verrouiller() passe par xflock4 — pas par l'ancien greffon cassé" \
	|| non "verrouiller() ne s'appuie pas sur xflock4"

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
