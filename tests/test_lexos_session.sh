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
)
for g in eteindre redemarrer veille deconnexion utilisateur; do
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
titre "5. La barre et la fenêtre disent la même chose"
#  Les deux boutons qu'Alex a demandé de déplacer doivent être DANS la
#  fenêtre et PLUS dans la rangée du panneau. S'ils étaient aux deux
#  endroits, ou à aucun, personne ne s'en apercevrait avant la photo
#  suivante — et ça coûte une ISO à chaque fois.
PANEL="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
ACTIONS="$(python3 - "$PANEL" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-8":
        for q in p:
            if q.get("name") == "items":
                print(" ".join(v.get("value") for v in q))
PY
)"
case "$ACTIONS" in
	*switch-user*) non "« changer d'utilisateur » est encore dans la barre" ;;
	*)             ok "« changer d'utilisateur » a quitté la barre" ;;
esac
case "$ACTIONS" in
	*logout*) non "« déconnexion » est encore dans la barre" ;;
	*)        ok "« déconnexion » a quitté la barre" ;;
esac
case "$ACTIONS" in
	*shutdown*) non "l'arrêt est encore une action du greffon (il doit être le lanceur 17)" ;;
	*)          ok "l'arrêt n'est plus une action du greffon" ;;
esac
case "$ACTIONS" in
	*suspend*restart*) ok "veille puis redémarrage, dans cet ordre, à gauche du bouton rouge" ;;
	*)                 non "ordre inattendu dans la barre : « $ACTIONS »" ;;
esac

#  Et le bouton rouge doit être le DERNIER greffon : c'est ce qui le met
#  tout à droite de l'écran, la demande d'Alex mot pour mot.
DERNIER="$(python3 - "$PANEL" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-ids":
        print([v.get("value") for v in p][-1])
PY
)"
[ "$DERNIER" = "17" ] \
	&& ok "le greffon 17 (bouton rouge) est le dernier — donc le plus à droite" \
	|| non "le dernier greffon est « $DERNIER », pas 17 : le rouge n'est pas au bout"

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
