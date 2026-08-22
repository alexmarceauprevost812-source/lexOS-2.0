# =============================================================================
#  LexOS — le terminal tel qu'on le veut (invite, alias, touche Tab)
# =============================================================================
#  POURQUOI CE FICHIER EXISTE, ET PAS SEULEMENT /etc/profile.d/lexos.sh
#
#  Tout ceci vivait dans /etc/profile.d/lexos.sh. Or /etc/profile.d n'est lu
#  QUE par un shell de connexion. Le terminal du bureau (xfce4-terminal)
#  démarre un shell interactif SANS connexion : il lit /etc/bash.bashrc puis
#  ~/.bashrc, et jamais /etc/profile.d. Autrement dit, l'invite verte et
#  orange de LexOS et les alias (ll, maj, infos) n'apparaissaient QUE dans la
#  console texte — c'est-à-dire presque jamais, puisqu'on ouvre le terminal
#  depuis le bureau.
#
#  Le contenu est donc ici, et trois chargeurs le lisent (hook 0120) :
#    · /etc/profile.d/lexos.sh   → shells de connexion (console texte, ssh)
#    · /etc/bash.bashrc          → tous les shells interactifs, root compris
#    · /etc/skel/.bashrc         → à la FIN, pour les comptes utilisateurs
#
#  Cette dernière ligne n'est pas un doublon : le ~/.bashrc de Debian pose SA
#  propre invite PS1, et il est lu APRÈS /etc/bash.bashrc. Sans un rappel à la
#  fin de ~/.bashrc, l'invite de LexOS serait posée puis aussitôt écrasée par
#  celle de Debian. D'où la règle suivie ici : l'invite et les alias se
#  REPOSENT à chaque passage (c'est sans effet de bord), tandis que ce qui ne
#  doit se produire qu'une fois — le logo d'accueil, le chargement de la
#  complétion — est tenu par le garde-fou LEXOS_SHELL_CHARGE.
# =============================================================================
# shellcheck shell=sh

# --- Confort (utile même hors interactif) ------------------------------------
export EDITOR="${EDITOR:-nano}"
export LESS="-R"
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth

# Tout ce qui suit n'a de sens que dans un shell INTERACTIF. Un script qui
# source ce fichier ne doit hériter ni de l'invite, ni des alias, ni du logo.
case "$-" in
	*i*) ;;
	*)   return 0 ;;
esac

# --- Invite de commande : noir / vert dark / orange --------------------------
#  Reposée à chaque passage, exprès : voir l'explication en tête de fichier.
#
#  LA RÈGLE DE COULEUR, la même dans la démo web et sur la vraie machine :
#    · vert dark  — tout ce que la MACHINE écrit (l'invite, les réponses)
#    · orange     — tout ce que VOUS tapez
#    · rouge      — ce qui n'a pas marché (fausse commande, commande en échec)
#
#  L'orange de la frappe tient à un détail : PS1 se termine par une couleur
#  qu'on ne referme PAS. Elle déborde donc sur ce qui est saisi ensuite —
#  c'est voulu. PS0, affiché juste après Entrée et avant l'exécution, remet
#  le tout à zéro pour que la sortie de la commande retrouve le vert.
if [ -n "${BASH_VERSION:-}" ]; then
	case "${TERM:-dumb}" in
		dumb|linux-m|unknown) ;;
		*)
			__lexos_git_branch() {
				git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/^/ ⎇ /'
			}
			#  Le code de sortie doit être saisi AVANT toute autre chose :
			#  $(__lexos_git_branch) s'exécute pendant le calcul de l'invite
			#  et écrase $? au passage. PROMPT_COMMAND, lui, tourne avant.
			__lexos_etat() { __lexos_code=$?; }
			case "${PROMPT_COMMAND:-}" in
				*__lexos_etat*) ;;
				"")  PROMPT_COMMAND="__lexos_etat" ;;
				*)   PROMPT_COMMAND="__lexos_etat; $PROMPT_COMMAND" ;;
			esac
			#  Le chevron : orange quand tout va bien, ROUGE quand la
			#  commande précédente a échoué — une commande qui n'existe pas
			#  rend 127, et la ligne suivante s'ouvre donc en rouge.
			__lexos_fleche() {
				if [ "${__lexos_code:-0}" = "0" ]; then
					printf '\033[38;5;208m'
				else
					printf '\033[1;38;5;196m'
				fi
			}
			# vert dark pour l'utilisateur, orange pour le chemin ET pour la frappe
			PS1='\[\033[38;5;35m\]\u\[\033[2m\]@\[\033[0m\033[38;5;35m\]\h\[\033[0m\] \[\033[38;5;208m\]\w\[\033[0m\]\[\033[2m\]$(__lexos_git_branch)\[\033[0m\]\n\[$(__lexos_fleche)\]❯\[\033[0m\] \[\033[38;5;208m\]'
			PS0='\e[0m'
			;;
	esac
fi

# --- Une commande qui n'existe pas : le dire en rouge, et en français --------
#  bash répond « commande introuvable » dans la couleur courante — donc en
#  vert, comme une réponse normale. On la repeint en rouge et on rappelle le
#  mot qui ouvre l'aide. On ne remplace jamais un gestionnaire déjà posé
#  (Debian en installe un avec le paquet command-not-found).
if [ -n "${BASH_VERSION:-}" ] \
	&& ! command -v command_not_found_handle >/dev/null 2>&1; then
	command_not_found_handle() {
		printf '\033[1;38;5;196m✗ commande inconnue : %s\033[0m\n' "$1" >&2
		printf '\033[2mTape « aide » pour la liste des commandes.\033[0m\n' >&2
		return 127
	}
fi

# --- Alias -------------------------------------------------------------------
alias ll='ls -alh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'

#  Debian nomme la commande de « bat » BATCAT (conflit de nom avec Bacula) :
#  l'outil était installé et personne ne le trouvait. Même chose pour
#  git-delta, dont la commande est « delta » — celle-là porte déjà le bon
#  nom, on ne fait que le rappeler ici. Les gardes : ne jamais masquer un
#  vrai « bat » si l'utilisateur en installe un.
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
	alias bat='batcat'
fi
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias maj='lexos upgrade'
alias infos='lexfetch'
# « aide » tout court : le premier mot qu'un francophone tape quand il est
# perdu. Il ouvre le sommaire des commandes.
alias aide='lexos aide'

# =============================================================================
#  À partir d'ici : une seule fois par shell.
# =============================================================================
[ -n "${LEXOS_SHELL_CHARGE:-}" ] && return 0
LEXOS_SHELL_CHARGE=1

# --- La touche Tab -----------------------------------------------------------
#  bash-completion est installé (lexos-core.list.chroot) et le ~/.bashrc de
#  Debian le charge déjà. Mais root n'a pas ce ~/.bashrc, et un utilisateur qui
#  a réécrit le sien se retrouverait sans rien — or la complétion « lexos » est
#  justement ce qui remplace le manuel pour un débutant. On s'assure donc
#  qu'elle est là, sans la charger deux fois.
if [ -n "${BASH_VERSION:-}" ] \
   && ! command -v _comp_load >/dev/null 2>&1 \
   && ! command -v _completion_loader >/dev/null 2>&1; then
	if [ -r /usr/share/bash-completion/bash_completion ]; then
		# shellcheck disable=SC1091
		. /usr/share/bash-completion/bash_completion
	fi
fi

# --- Bienvenue en console (pas dans les scripts, pas dans le terminal graphique)
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -z "${DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] && command -v lexfetch >/dev/null 2>&1; then
	lexfetch
fi
