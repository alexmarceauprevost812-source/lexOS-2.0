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
#  Deux appelants aujourd'hui : interactive.sh (sourcé aussi bien par /bin/sh
#  que par bash) et le banc. Le POSIX pur n'est donc pas une contrainte du
#  jour : c'est la même règle que secure-boot.sh juste à côté, pour que
#  lexos-tv — qui est en #!/bin/sh — puisse le sourcer le jour où on le lui
#  demandera, sans que personne ait à s'en souvenir.
#  ⚠ CETTE NOTE A DIT « trois appelants, dont lexos-tv » ALORS QUE C'ÉTAIT
#  FAUX : lexos-tv ne source que secure-boot.sh. Un commentaire faux est un
#  défaut à part entière — la prochaine lecture s'y fie.
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

#  Un module d'affichage est-il chargé ?
#  ═══ TROIS RÉPONSES, PAS DEUX ═══
#    0 = un pilote est chargé
#    1 = AUCUN pilote chargé — c'est une mesure
#    2 = je n'ai pas pu lire (pas de /proc/modules : chroot, conteneur…)
#  La première version rendait 1 dans les deux derniers cas, et l'appelant
#  imprimait alors « Mesuré : AUCUN pilote d'affichage n'est chargé » sur une
#  machine où l'on n'avait simplement rien lu. C'est le bogue du dock, avec le
#  mot « Mesuré » écrit dessus. secure-boot.sh fait déjà la distinction deux
#  fichiers plus loin (mode_raid_dire : « impossible à vérifier » ≠ « rien
#  d'anormal ») ; il n'y avait pas de raison de ne pas la faire ici.
session_graphique_pilote() {
	[ -r "$LEXOS_MODULES" ] || return 2
	#  Les six modules qui pilotent un écran sur les machines visées.
	if awk '{print $1}' "$LEXOS_MODULES" 2>/dev/null \
		| grep -qE '^(nvidia|nouveau|i915|xe|amdgpu|radeon)$'; then
		return 0
	fi
	return 1
}

#  La machine VISE-T-ELLE le graphique ? Sur une installation en mode serveur,
#  pas de bureau attendu, donc pas de panne à annoncer.
session_graphique_attendue() {
	#  La couture, pour que le cas « machine en mode serveur » soit éprouvable
	#  autrement qu'en relisant le code.
	_sg_cible="${LEXOS_CIBLE_DEFAUT:-}"
	if [ -z "$_sg_cible" ]; then
		command -v systemctl >/dev/null 2>&1 || return 1
		_sg_cible="$(systemctl get-default 2>/dev/null)"
	fi
	#  ═══ IL FAUT UNE RÉPONSE POSITIVE, PAS UNE ABSENCE DE REFUS ═══
	#  La première version rendait 0 — « le graphique est attendu », donc feu
	#  vert pour annoncer la panne — dans les deux cas où elle n'avait RIEN pu
	#  mesurer : systemctl absent, et systemctl muet. Son propre commentaire
	#  disait « on ne conclut pas » ; la valeur de retour, elle, concluait, et
	#  du côté de l'alarme. C'est l'inverse exact de la doctrine de
	#  secure-boot.sh : « le doute penche vers inactif — on préfère ne rien
	#  dire à accuser Secure Boot d'un écran noir dont il n'est pas
	#  responsable. »
	#  Sur les machines visées, systemd est là et la cible est graphique : on
	#  ne perd donc rien à exiger la réponse, et on cesse d'annoncer une panne
	#  à une machine dont on ne sait rien.
	case "$_sg_cible" in
		graphical.target) return 0 ;;
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

#  ⚠ LA QUATRIÈME CLÉ, QUI MANQUAIT ICI. Le hook 0260 écrit aussi
#  LEXOS_NVIDIA_MODULE (oui|non) : un pilote peut être installé sans que son
#  module noyau ait été compilé — c'est arrivé, et ce dépôt a déjà livré deux
#  ISO sur la foi d'un « apt a dit oui ». Sans cette lecture, le message
#  annonçait « cette ISO embarque pourtant le pilote X » sur une ISO où RIEN
#  ne pouvait prendre la carte : une consolation fausse, qui envoie chercher
#  du côté du BIOS.
_sg_nvidia_module() {
	[ -r "$LEXOS_BUILD_CONF" ] || return 1
	# shellcheck disable=SC1090
	( . "$LEXOS_BUILD_CONF" 2>/dev/null; printf '%s' "${LEXOS_NVIDIA_MODULE:-}" )
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

	#  ═══ ON SÉPARE « RIEN N'EST CHARGÉ » DE « JE N'AI PAS PU LIRE » ═══
	session_graphique_pilote
	_sg_p=$?

	#  Cause 2a : on n'a pas pu lire la liste des modules. On ne prétend pas.
	if [ "$_sg_p" = "2" ]; then
		echo "  Je n'ai PAS PU lire la liste des modules du noyau"
		echo "  (${LEXOS_MODULES}) : je ne sais donc pas quel pilote est chargé,"
		echo "  et je ne vais pas l'inventer."
		echo
		echo "  Pour tout voir :  sudo lexos tv"
		return 0
	fi

	#  Cause 2b : aucun pilote d'affichage chargé. C'est le cas d'Alex.
	if [ "$_sg_p" = "1" ]; then
		echo "  Mesuré : AUCUN pilote d'affichage n'est chargé (ni nvidia, ni"
		echo "  nouveau, ni un pilote intégré). Le serveur graphique n'a donc"
		echo "  rien pour dessiner."
		#  Un « if », pas un « [ … ] && echo » : ce dernier rend 1 quand la
		#  condition est fausse, et ce fragment est fait pour être sourcé par
		#  n'importe quel appelant, y compris un qui tournerait sous
		#  « set -e ». ⚠ LA PREMIÈRE VERSION DE CETTE NOTE JUSTIFIAIT LA MÊME
		#  LIGNE PAR « lexos-tv tourne sous set -e » : doublement faux —
		#  lexos-tv ne source pas ce fragment, et il est en « set -u ». Le
		#  code était bon, sa raison était fabriquée.
		_sg_v="$(_sg_nvidia_version 2>/dev/null || true)"
		_sg_m="$(_sg_nvidia_module 2>/dev/null || true)"
		if [ -n "$_sg_v" ] && [ "$_sg_m" = "non" ]; then
			echo "  Cette ISO embarque le pilote NVIDIA ${_sg_v}, mais SON MODULE"
			echo "  NOYAU n'a pas été compilé à la construction : il n'y a donc"
			echo "  rien qui puisse prendre la carte. Une autre ISO est"
			echo "  nécessaire — inutile de chercher du côté du BIOS."
			echo
			echo "  Pour tout voir :  sudo lexos tv"
			return 0
		fi
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
