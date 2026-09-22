# =============================================================================
#  LexOS — le bureau n'a pas démarré : le dire, et dire pourquoi
# =============================================================================
#  CE QU'ALEX A VU, ET POURQUOI C'ÉTAIT PIRE QU'UN ÉCRAN NOIR.
#
#  Alienware Aurora ACT1250, RTX 5060, entrée normale du menu : le bureau ne
#  démarre pas, la machine retombe en console texte — et cette console
#  affiche la bannière lexfetch. Un masque en blocs, des couleurs, des
#  chiffres qui ont l'air d'aller. Rien ne dit que quelque chose a échoué.
#  Quelqu'un qui arrive là ne sait même pas s'il est au bon endroit.
#
#  C'est pourtant un PROGRÈS : jusqu'au build 54, l'écran perdait le signal
#  tout court. La liste noire de « nouveau » fait son travail et le tampon
#  d'image du micrologiciel tient l'écran. Ce qui manque est donc précis :
#  nvidia.ko ne prend pas la carte, et le serveur graphique ne trouve aucun
#  pilote.
#
#  ═══ POURQUOI UN FICHIER À PART, ET EN POSIX PUR ═══
#  Trois appelants, trois shells : interactive.sh (sourcé par /bin/sh comme
#  par bash), lexos-tv (#!/bin/sh) et les bancs. Même raison que
#  secure-boot.sh juste à côté, et même interdit : ne pas « moderniser » avec
#  [[ ]], un tableau ou une substitution bash — ça cesserait de marcher dans
#  lexos-tv, et ça cesserait EN SILENCE.
#
#  ═══ LA RÈGLE QUI COMPTE : NE JAMAIS CRIER AU LOUP ═══
#  Une console sans DISPLAY, c'est aussi Ctrl+Alt+F2 pendant que le bureau
#  tourne très bien, et c'est aussi une session SSH. Annoncer une panne à
#  quelqu'un dont la machine va bien, c'est le même défaut à l'envers que la
#  tuile qui affirme « Désactivé » faute d'avoir pu lire : une affirmation
#  qu'on n'a pas mesurée. On exige donc QUATRE conditions, pas une.
# =============================================================================
#
#  Sourcé, pas exécuté : pas de shebang, donc on dit le shell à shellcheck.
# shellcheck shell=sh

#  Les coutures. Sans elles, rien de tout ceci n'est éprouvable : /proc et
#  /tmp/.X11-unix ne se fabriquent pas dans un banc, et un contrôle qu'on ne
#  peut que relire finit par mentir.
LEXOS_MODULES="${LEXOS_MODULES:-/proc/modules}"
LEXOS_X11_SOCKETS="${LEXOS_X11_SOCKETS:-/tmp/.X11-unix}"
LEXOS_BUILD_CONF="${LEXOS_BUILD_CONF:-/etc/lexos/build.conf}"
LEXOS_SHELL_DIR="${LEXOS_SHELL_DIR:-/usr/share/lexos/shell}"

#  Un serveur d'affichage tourne-t-il, quelque part sur cette machine ?
#  On ne regarde pas DISPLAY : l'appelant est justement dans un shell qui n'en
#  a pas. On cherche la SOCKET, qui existe pour toute la machine.
session_graphique_en_cours() {
	for _sg_s in "$LEXOS_X11_SOCKETS"/X*; do
		[ -e "$_sg_s" ] && return 0
	done
	#  Wayland : une socket dans le répertoire d'exécution de l'utilisateur.
	if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
		for _sg_w in "$XDG_RUNTIME_DIR"/wayland-*; do
			case "$_sg_w" in *'*') continue ;; esac
			[ -e "$_sg_w" ] && return 0
		done
	fi
	return 1
}

#  Un module d'affichage est-il chargé ? On nomme les quatre qui pilotent un
#  écran sur cette machine, et « nvidia » d'abord : c'est celui qui manque.
session_graphique_pilote() {
	[ -r "$LEXOS_MODULES" ] || return 1
	awk '{print $1}' "$LEXOS_MODULES" 2>/dev/null \
		| grep -qE '^(nvidia|nouveau|i915|xe|amdgpu|radeon)$'
}

#  La machine VISE-T-ELLE le graphique ? Sur une installation en mode serveur,
#  pas de bureau attendu, donc pas de panne à annoncer.
session_graphique_attendue() {
	#  La couture, pour que le cas « machine en mode serveur » soit éprouvable
	#  autrement qu'en relisant le code.
	_sg_cible="${LEXOS_CIBLE_DEFAUT:-}"
	if [ -z "$_sg_cible" ]; then
		command -v systemctl >/dev/null 2>&1 || return 0
		_sg_cible="$(systemctl get-default 2>/dev/null)"
	fi
	case "$_sg_cible" in
		graphical.target) return 0 ;;
		"")               return 0 ;;   # systemd muet : on ne conclut pas
		*)                return 1 ;;
	esac
}

#  ═══ LES QUATRE CONDITIONS ═══
#  Rend 0 (vrai) seulement quand le bureau AURAIT DÛ être là et n'y est pas.
session_graphique_absente() {
	#  1. Pas de DISPLAY pour l'appelant — sinon il est DANS le bureau.
	[ -z "${DISPLAY:-}" ] || return 1
	#  2. Pas une session distante : un SSH n'a jamais de bureau, ce n'est pas
	#     une panne.
	[ -z "${SSH_CONNECTION:-}" ] || return 1
	[ -z "${SSH_TTY:-}" ] || return 1
	[ -z "${SSH_CLIENT:-}" ] || return 1
	#  3. Aucun serveur d'affichage nulle part — sinon c'est un Ctrl+Alt+F2,
	#     et le bureau attend sagement derrière.
	session_graphique_en_cours && return 1
	#  4. La machine vise bien le graphique.
	session_graphique_attendue || return 1
	return 0
}

#  Ce que dit build.conf du pilote embarqué. Vide si le hook ne l'a pas
#  écrit — une ISO d'avant cette consigne, par exemple.
_sg_nvidia_etat() {
	[ -r "$LEXOS_BUILD_CONF" ] || return 1
	# shellcheck disable=SC1090
	( . "$LEXOS_BUILD_CONF" 2>/dev/null; printf '%s' "${LEXOS_NVIDIA_ETAT:-}" )
}

_sg_nvidia_version() {
	[ -r "$LEXOS_BUILD_CONF" ] || return 1
	# shellcheck disable=SC1090
	( . "$LEXOS_BUILD_CONF" 2>/dev/null; printf '%s' "${LEXOS_NVIDIA_VERSION:-}" )
}

#  ═══ LE MESSAGE ═══
#  Quatre lignes au plus, en français, et dans cet ordre : ce qui n'a pas
#  démarré, la cause MESURÉE, la commande pour en savoir plus, et la marche à
#  suivre quand on la connaît.
#
#  L'ORDRE DES CAUSES N'EST PAS ARBITRAIRE : on commence par ce qu'on peut
#  LIRE (le pilote est-il seulement dans cette ISO ?), puis par ce qu'on peut
#  MESURER (Secure Boot, modules chargés). On ne suppose jamais.
session_graphique_dire() {
	_sg_etat="$(_sg_nvidia_etat 2>/dev/null || true)"

	echo "LE BUREAU N'A PAS DÉMARRÉ — tu es en console texte."
	echo

	#  Cause 1 : le pilote n'est pas dans l'ISO. C'est écrit, pas déduit.
	case "$_sg_etat" in
		absent|absent-accepte)
			echo "  Cause : cette ISO N'EMBARQUE AUCUN PILOTE NVIDIA. La cascade"
			echo "  d'installation a échoué à la construction ; c'est inscrit dans"
			echo "  /etc/lexos/build.conf et détaillé dans /etc/lexos/nvidia-report."
			echo "  Une autre ISO est nécessaire — il n'y a rien à régler ici."
			echo
			echo "  Pour tout voir :  sudo lexos tv"
			return 0
			;;
	esac

	#  Cause 2 : aucun pilote d'affichage chargé. C'est le cas d'Alex.
	if ! session_graphique_pilote; then
		echo "  Mesuré : AUCUN pilote d'affichage n'est chargé (ni nvidia, ni"
		echo "  nouveau, ni un pilote intégré). Le serveur graphique n'a donc"
		echo "  rien pour dessiner."
		#  Un « [ … ] && echo » ici rendrait 1 quand la condition est fausse.
		#  Ce fragment est sourcé par lexos-tv, qui tourne sous « set -e » : la
		#  ligne suivante ne serait jamais atteinte. On écrit donc un « if ».
		_sg_v="$(_sg_nvidia_version 2>/dev/null || true)"
		if [ -n "$_sg_v" ]; then
			echo "  (Cette ISO embarque pourtant le pilote NVIDIA ${_sg_v}.)"
		fi
		echo

		#  Et la cause la plus probable de ce refus, si on peut la lire.
		if [ -r "$LEXOS_SHELL_DIR/secure-boot.sh" ]; then
			# shellcheck disable=SC1091
			. "$LEXOS_SHELL_DIR/secure-boot.sh"
			if secure_boot_actif; then
				secure_boot_dire | sed 's/^/  /'
				echo
			fi
		fi
		echo "  Pour tout voir :  sudo lexos tv"
		return 0
	fi

	#  Cause 3 : un pilote est chargé, mais la session ne s'ouvre pas. On ne
	#  devine pas laquelle des vingt raisons possibles : on dit où regarder.
	echo "  Mesuré : un pilote d'affichage EST chargé — la panne est donc"
	echo "  ailleurs (gestionnaire de connexion, Xorg, session)."
	echo
	echo "  Pour tout voir :       sudo lexos tv"
	echo "  Le journal de la session :  journalctl -b -u lightdm"
	return 0
}
