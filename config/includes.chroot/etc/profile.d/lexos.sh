# =============================================================================
#  LexOS — environnement de connexion (invite, alias, raccourcis)
# =============================================================================
# shellcheck shell=sh

# --- Invite de commande : noir / vert dark / orange --------------------------
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ]; then
	case "${TERM:-dumb}" in
		dumb|linux-m|unknown) ;;
		*)
			__lexos_git_branch() {
				git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/^/ ⎇ /'
			}
			# vert dark pour l'utilisateur, orange pour le chemin
			PS1='\[\033[38;5;35m\]\u\[\033[2m\]@\[\033[0m\033[38;5;35m\]\h\[\033[0m\] \[\033[38;5;208m\]\w\[\033[0m\]\[\033[2m\]$(__lexos_git_branch)\[\033[0m\]\n\[\033[38;5;208m\]❯\[\033[0m\] '
			;;
	esac
fi

# --- Alias -------------------------------------------------------------------
alias ll='ls -alh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias maj='lexos upgrade'
alias infos='lexfetch'

# --- Confort -----------------------------------------------------------------
export EDITOR="${EDITOR:-nano}"
export LESS="-R"
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth

# --- Bienvenue en console (pas dans les scripts, pas dans le terminal graphique)
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -z "${DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] && command -v lexfetch >/dev/null 2>&1; then
	case "$-" in
		*i*) lexfetch ;;
	esac
fi
