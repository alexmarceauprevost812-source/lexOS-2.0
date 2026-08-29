#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-fond-video — les icônes du bureau derrière la vidéo
# =============================================================================
#  ALEX, photo à l'appui (un fond vidéo animé — texte de code qui défile,
#  logo « TI·LEX·AL » — sur un portable Lenovo) : « on voit les applications
#  du bureau juste au moment où on change le fond d'écran ». Exactement le
#  bogue déjà connu et déjà corrigé dans fond-anime.py (voir
#  test_lexos_fond_anime.sh) : notre fenêtre de fond ET xfdesktop (qui
#  dessine les icônes) sont TOUTES LES DEUX _NET_WM_WINDOW_TYPE_DESKTOP —
#  xfwm4 garantit que ce calque reste sous les fenêtres normales, mais PAS
#  l'ordre RELATIF entre deux fenêtres du même calque. fond-video.py
#  n'avait JAMAIS reçu ce correctif : il abaisse sa fenêtre UNE SEULE FOIS
#  à sa création. Le bref instant où les icônes redeviennent visibles est
#  justement celui où xfdesktop se redessine tout seul au changement de
#  fond — puis elles repassent sous la vidéo, pour de bon cette fois.
#
#  lexos-fond-video (ce script, en bash — fond-video.py, lui, ne fait que la
#  fenêtre et mpv) porte maintenant un PORT SHELL de remonte_xfdesktop() :
#  deux champs WM_CLASS essayés, code de retour vérifié, repli wmctrl — et
#  une boucle de fond (surveille_icones) qui la rappelle toutes les 15
#  secondes tant que mpv tourne, exactement comme la minuterie GLib de
#  fond-anime.py.
#
#  POURQUOI CE BANC EXTRAIT LES FONCTIONS PLUTÔT QUE DE SOURCER LE FICHIER.
#  lexos-fond-video se termine par un aiguillage (« case "${1:-}" in ... »)
#  qui s'exécute sans condition — le sourcer tel quel lancerait cmd_etat()
#  ou pire, cmd_demarrer() sur un mot de passe inventé. On extrait donc
#  seulement le bloc utile (couleurs, chemins d'état, remonte_xfdesktop(),
#  surveille_icones(), sur_batterie(), surveille_batterie(), cmd_arreter())
#  entre deux repères stables du fichier.
#
#  CE QUI N'EST PAS ÉPROUVÉ ICI, ET POURQUOI. cmd_demarrer() a besoin de
#  mpv, d'un vrai serveur X et de python3-xlib — rien de tout ça n'existe
#  sur la machine de construction. Son câblage (l'appel immédiat à
#  remonte_xfdesktop, le lancement de surveille_icones) est donc vérifié
#  PAR LECTURE DU FICHIER (grep), même limite déjà assumée dans
#  test_lexos_fond_anime.sh pour son propre minuteur GLib.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/usr/bin/lexos-fond-video"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

DEBUT="$(grep -n '^set -uo pipefail' "$SCRIPT" | head -1 | cut -d: -f1)"
FIN="$(grep -n '^cmd_arreter() {' "$SCRIPT" | head -1 | cut -d: -f1)"
FIN="$(awk -v d="$FIN" 'NR>=d && /^}/{print NR; exit}' "$SCRIPT")"
sed -n "${DEBUT},${FIN}p" "$SCRIPT" > "$BAC/fonctions.sh"
for f in vivant remonte_xfdesktop surveille_icones cmd_arreter; do
	grep -q "^${f}()" "$BAC/fonctions.sh" \
		|| { echo "extraction ratée : ${f}() absente du bloc"; exit 1; }
done

mkdir -p "$BAC/bin-full" "$BAC/bin-wmctrl"
cat > "$BAC/bin-full/xdotool" <<'EOF'
#!/bin/sh
echo "xdotool $*" >> "$JOURNAL"
if [ "$1" = "search" ]; then
	case "$2" in
		--classname) [ "${XDOTOOL_MATCH:-}" = "classname" ] && exit 0 ;;
		--class)     [ "${XDOTOOL_MATCH:-}" = "class" ] && exit 0 ;;
	esac
fi
exit 1
EOF
cat > "$BAC/bin-full/wmctrl" <<'EOF'
#!/bin/sh
echo "wmctrl $*" >> "$JOURNAL"
exit 0
EOF
cp "$BAC/bin-full/wmctrl" "$BAC/bin-wmctrl/wmctrl"
chmod +x "$BAC"/bin-full/* "$BAC"/bin-wmctrl/*

# essai_remonte <dossier-outils|""> <XDOTOOL_MATCH>
essai_remonte() {
	local bindir="$1" match="$2" p="$PATH"
	[ -n "$bindir" ] && p="$bindir:$PATH"
	: > "$BAC/journal"
	PATH="$p" XDOTOOL_MATCH="$match" JOURNAL="$BAC/journal" \
		bash -c "source '$BAC/fonctions.sh'; remonte_xfdesktop"
	printf 'RC=%d\n' "$?"
	printf 'JOURNAL:%s\n' "$(cat "$BAC/journal" 2>/dev/null)"
}

# =============================================================================
titre "1. remonte_xfdesktop() — xdotool préféré, wmctrl en repli, rien en repli"
# =============================================================================
#  DEUX CHAMPS, DEUX ESSAIS : le premier correctif de fond-anime.py n'en
#  essayait qu'un (voir son propre banc) — même exigence portée ici.
SORTIE="$(essai_remonte "$BAC/bin-full" classname)"
case "$SORTIE" in
	*"RC=0"*"xdotool search --classname"*)
		if [[ "$SORTIE" == *"wmctrl"* ]]; then
			non "l'INSTANCE matche du premier coup, mais wmctrl a quand même été appelé : $SORTIE"
		else
			ok "l'INSTANCE matche du premier coup -> un seul essai, wmctrl jamais appelé"
		fi ;;
	*) non "le premier essai (--classname) aurait dû suffire : $SORTIE" ;;
esac

SORTIE="$(essai_remonte "$BAC/bin-full" class)"
if [[ "$SORTIE" == *"RC=0"* && "$SORTIE" == *"--classname"* && "$SORTIE" == *"--class "*"[Xx]fdesktop"* && "$SORTIE" != *"wmctrl"* ]]; then
	ok "l'instance ne matche pas mais la CLASSE oui -> deuxième essai xdotool, sans passer par wmctrl"
else
	non "le repli --class (deuxième essai xdotool) n'a pas eu lieu comme attendu : $SORTIE"
fi

SORTIE="$(essai_remonte "$BAC/bin-full" "")"
if [[ "$SORTIE" == *"RC=0"* && "$SORTIE" == *"--classname"* && "$SORTIE" == *"--class "* && "$SORTIE" == *"wmctrl -x -a xfdesktop.Xfdesktop"* ]]; then
	ok "xdotool ne trouve rien dans AUCUN des deux champs -> repli sur wmctrl, pas un succès inventé"
else
	non "les deux essais xdotool en échec auraient dû retomber sur wmctrl : $SORTIE"
fi

SORTIE="$(essai_remonte "$BAC/bin-wmctrl" "")"
if [[ "$SORTIE" == *"RC=0"* && "$SORTIE" != *"xdotool"* && "$SORTIE" == *"wmctrl -x -a xfdesktop.Xfdesktop"* ]]; then
	ok "xdotool absent, seul wmctrl dispo -> repli direct, xdotool jamais invoqué"
else
	non "sans xdotool, le repli direct sur wmctrl n'a pas eu lieu comme attendu : $SORTIE"
fi

SORTIE="$(essai_remonte "" "")"
if [[ "$SORTIE" == *"RC=1"* && "$SORTIE" == "RC=1"$'\n'"JOURNAL:" ]]; then
	ok "ni xdotool ni wmctrl -> rien n'est exécuté, et ça le DIT (échec), pas un succès inventé"
else
	non "sans outil, la fonction aurait dû échouer sans rien exécuter : $SORTIE"
fi

# =============================================================================
titre "2. surveille_icones() — la boucle suit mpv, pas une minuterie aveugle"
# =============================================================================
XDGRT="$BAC/xdgrt"
mkdir -p "$XDGRT/lexos-fond-video"

#  mpv déjà mort AVANT même le premier tour : la boucle ne doit ni appeler
#  remonte_xfdesktop(), ni bloquer (elle doit rendre la main tout de suite).
( : ) & pid_mort=$!
wait "$pid_mort" 2>/dev/null
echo "$pid_mort" > "$XDGRT/lexos-fond-video/mpv.pid"
: > "$BAC/journal"
if timeout 3 env PATH="$BAC/bin-full:$PATH" XDG_RUNTIME_DIR="$XDGRT" \
	XDOTOOL_MATCH=classname JOURNAL="$BAC/journal" \
	bash -c "source '$BAC/fonctions.sh'; surveille_icones"
then
	if [ -s "$BAC/journal" ]; then
		non "mpv déjà mort, mais remonte_xfdesktop() a quand même été appelée"
	else
		ok "mpv déjà mort -> la boucle rend la main tout de suite, sans appeler remonte_xfdesktop()"
	fi
else
	non "mpv déjà mort -> surveille_icones() aurait dû rendre la main, pas rester bloquée (timeout ou échec)"
fi

#  mpv vivant : au moins UN appel à remonte_xfdesktop() avant qu'on
#  interrompe (elle boucle toutes les 15 s — 3 s suffisent pour voir le
#  premier tour sans faire durer le banc pour rien).
sleep 30 & pid_vivant=$!
echo "$pid_vivant" > "$XDGRT/lexos-fond-video/mpv.pid"
: > "$BAC/journal"
timeout 3 env PATH="$BAC/bin-full:$PATH" XDG_RUNTIME_DIR="$XDGRT" \
	XDOTOOL_MATCH=classname JOURNAL="$BAC/journal" \
	bash -c "source '$BAC/fonctions.sh'; surveille_icones" 2>/dev/null
if grep -q 'xdotool search --classname' "$BAC/journal" 2>/dev/null; then
	ok "mpv vivant -> remonte_xfdesktop() est bien appelée pendant que la vidéo tourne"
else
	non "mpv vivant, mais aucun appel à remonte_xfdesktop() n'a été vu dans la fenêtre du banc"
fi
kill "$pid_vivant" 2>/dev/null; wait "$pid_vivant" 2>/dev/null

# =============================================================================
titre "3. cmd_arreter() — PID_ICONES fait bien partie du nettoyage"
# =============================================================================
#  Le vrai test : QUATRE processus témoins (pas de vrai mpv/fenêtre — juste
#  des « sleep » qui tiennent lieu de PID), et on vérifie qu'après
#  cmd_arreter() les QUATRE sont bien morts, pas seulement les anciens
#  trois d'avant l'ajout des icônes.
XDGRT2="$BAC/xdgrt2"; XDGCF2="$BAC/xdgcf2"
mkdir -p "$XDGRT2/lexos-fond-video" "$XDGCF2/autostart"
declare -A PIDS
for nom in bat icones mpv fen; do
	sleep 60 & PIDS[$nom]=$!
done
echo "${PIDS[bat]}"    > "$XDGRT2/lexos-fond-video/batterie.pid"
echo "${PIDS[icones]}" > "$XDGRT2/lexos-fond-video/icones.pid"
echo "${PIDS[mpv]}"    > "$XDGRT2/lexos-fond-video/mpv.pid"
echo "${PIDS[fen]}"    > "$XDGRT2/lexos-fond-video/fenetre.pid"
: > "$XDGCF2/autostart/lexos-fond-video.desktop"

SORTIE="$(XDG_RUNTIME_DIR="$XDGRT2" XDG_CONFIG_HOME="$XDGCF2" \
	bash -c "source '$BAC/fonctions.sh'; cmd_arreter")"

tous_morts=1
for nom in bat icones mpv fen; do
	kill -0 "${PIDS[$nom]}" 2>/dev/null && tous_morts=0
done
if [ "$tous_morts" = 1 ]; then
	ok "les QUATRE processus témoins (dont les icônes) sont bien arrêtés"
else
	non "au moins un processus témoin a survécu à cmd_arreter() — les icônes n'étaient pas dans la boucle avant ce correctif"
fi

if [ ! -e "$XDGRT2/lexos-fond-video/icones.pid" ]; then
	ok "le fichier icones.pid est bien supprimé"
else
	non "icones.pid traîne encore après cmd_arreter()"
fi

if [ ! -e "$XDGCF2/autostart/lexos-fond-video.desktop" ]; then
	ok "l'entrée autostart est bien retirée"
else
	non "l'entrée autostart survit à cmd_arreter()"
fi

if [[ "$SORTIE" == *"arrêté"* ]]; then
	ok "cmd_arreter() confirme l'arrêt (message affiché)"
else
	non "aucun message de confirmation — sortie : $SORTIE"
fi

# =============================================================================
titre "4. Câblage — cmd_demarrer() et cmd_etat() savent parler des icônes"
# =============================================================================
#  Ce qui suit ne peut pas s'exécuter ici (mpv, un vrai serveur X et
#  python3-xlib manquent tous sur la machine de construction) : on vérifie
#  donc par lecture, comme le fait déjà test_lexos_fond_anime.sh pour le
#  minuteur GLib de l'autre fond.
grep -q 'remonte_xfdesktop$' "$SCRIPT" \
	&& ok "cmd_demarrer() appelle remonte_xfdesktop() une première fois, tout de suite" \
	|| non "aucun appel immédiat à remonte_xfdesktop() dans le fichier — les icônes resteraient cachées jusqu'au premier tour de boucle"

grep -q 'surveille_icones >/dev/null 2>&1 &' "$SCRIPT" \
	&& ok "cmd_demarrer() lance bien surveille_icones() en tâche de fond" \
	|| non "surveille_icones() n'est lancée nulle part — un seul appel au démarrage ne suffit pas (voir section 2)"

grep -q 'PID_ICONES' "$SCRIPT" \
	&& ok "PID_ICONES existe et est suivi comme les autres tâches de fond" \
	|| non "PID_ICONES n'existe pas dans le fichier"

#  cmd_etat() doit le dire quand ni xdotool ni wmctrl ne sont là — sinon les
#  icônes resteraient cachées SANS AUCUN diagnostic nulle part.
grep -q 'ni xdotool ni wmctrl' "$SCRIPT" \
	&& ok "cmd_etat() prévient quand ni xdotool ni wmctrl ne sont installés" \
	|| non "cmd_etat() ne dit rien si xdotool ET wmctrl manquent tous les deux — l'échec resterait silencieux"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
