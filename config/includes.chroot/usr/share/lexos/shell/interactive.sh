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

# --- Où l'invite prend ses couleurs -----------------------------------------
#  Elles ne sont plus écrites ici. lexos-theme-gen les dépose dans ce fichier,
#  en même temps qu'il peint le terminal, et l'invite les relit à CHAQUE
#  affichage. Deux conséquences voulues :
#
#    · « lexos terminal jour » repeint les shells DÉJÀ ouverts, à la ligne
#      suivante — sans « source ~/.bashrc », sans rouvrir de fenêtre ;
#    · le vert de l'invite et le vert du fond de terminal sont désormais la
#      MÊME valeur écrite une seule fois. Avant, 38;5;35 d'un côté et
#      #00AF5F de l'autre disaient la même couleur dans deux langues, libres
#      de diverger — et sur le fond crème du thème de jour, les deux
#      devenaient illisibles ensemble.
#
#  __LEXOS_C_TEXTE s'appelait __LEXOS_C_SAISIE et valait l'orange de
#  l'accent. Il porte maintenant le BLANC de la frappe (voir la règle de
#  couleur plus bas). L'orange n'a pas quitté le terminal pour autant : il
#  est resté le curseur, la sélection et l'onglet actif, et c'est pour ça
#  que le nom de la variable a changé avec lui.
#
#  ⚠ CETTE NOTE A DIT « il ne touche plus à l'invite », ET CE N'EST PLUS
#  VRAI. Alex est revenu dessus, captures à l'appui : « la couleur de
#  marceau pour l'orange ». L'orange touche donc l'invite À UN SEUL
#  ENDROIT — le NOM de l'utilisateur, __LEXOS_C_UTILISATEUR. Le chemin, la
#  branche, le chevron et la frappe n'y touchent pas. Et ce n'est PAS la
#  valeur de l'accent : lexos-theme-gen explique, à TERM_UTILISATEUR,
#  pourquoi le nom et le curseur portent deux oranges voisins et non le
#  même.
#
#  Les valeurs de repli ci-dessous sont celles que lexos-theme-gen écrit
#  pour la NUIT en palette 256, à l'identique — et c'est une correction.
#  Elles disaient « exactement celles d'avant (LexOS Noir) » : vrai le jour
#  où la phrase a été écrite, faux depuis. L'invite est passée au vert
#  38;5;40 (« un vert plus visible », demandé par Alex) et ce fichier était
#  resté au 38;5;35 : un utilisateur sans thème généré gardait l'ancien
#  vert, plus sourd, sans que rien ne le dise.
#  Ces trois lignes et les trois PS_*_256 de lexos-theme-gen sont la même
#  valeur écrite deux fois ; un banc les compare maintenant — c'est
#  précisément ce maillon-là que lisent la console texte, ssh et tmux,
#  puisque aucun n'exporte COLORTERM.
LEXOS_TERM_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/lexos/terminal.env"

__lexos_couleurs() {
	__LEXOS_C_MACHINE='38;5;40'
	__LEXOS_C_TEXTE='38;5;15'
	__LEXOS_C_ERREUR='1;38;5;196'
	__LEXOS_C_DIM='2'
	#  Les deux rôles de plus de l'invite (voir la règle de couleur, plus
	#  bas) : le nom en ORANGE, le mot LEXOS en vert foncé. Replis en
	#  palette 256, les plus proches des valeurs de nuit.
	#  38;5;208 EST EXACTEMENT #FF8700, la valeur de nuit : ici le repli ne
	#  s'approche pas, il tombe juste. Ça compte plus qu'il n'y paraît —
	#  personne n'exporte COLORTERM sauf le terminal LexOS Pro, donc la
	#  console texte, ssh et tmux lisent CETTE ligne-ci, pas terminal.env.
	__LEXOS_C_UTILISATEUR='38;5;220'
	__LEXOS_C_LOGO='38;5;35'
	[ -r "$LEXOS_TERM_ENV" ] || return 0
	# shellcheck disable=SC1090
	. "$LEXOS_TERM_ENV" 2>/dev/null || return 0
	#  Couleurs vraies quand le terminal les annonce, palette 256 sinon.
	#  La console texte et les vieux ssh ne comprennent pas 38;2;r;g;b et
	#  afficheraient les chiffres en clair au milieu de l'invite.
	case "${COLORTERM:-}" in
		truecolor|24bit)
			__LEXOS_C_MACHINE="${LEXOS_PS_MACHINE:-$__LEXOS_C_MACHINE}"
			__LEXOS_C_TEXTE="${LEXOS_PS_TEXTE:-$__LEXOS_C_TEXTE}"
			__LEXOS_C_ERREUR="${LEXOS_PS_ERREUR:-$__LEXOS_C_ERREUR}"
			__LEXOS_C_DIM="${LEXOS_PS_DIM:-$__LEXOS_C_DIM}"
			__LEXOS_C_UTILISATEUR="${LEXOS_PS_UTILISATEUR:-$__LEXOS_C_UTILISATEUR}"
			__LEXOS_C_LOGO="${LEXOS_PS_LOGO:-$__LEXOS_C_LOGO}"
			;;
		*)
			__LEXOS_C_MACHINE="${LEXOS_PS_MACHINE_256:-$__LEXOS_C_MACHINE}"
			__LEXOS_C_TEXTE="${LEXOS_PS_TEXTE_256:-$__LEXOS_C_TEXTE}"
			__LEXOS_C_ERREUR="${LEXOS_PS_ERREUR_256:-$__LEXOS_C_ERREUR}"
			__LEXOS_C_DIM="${LEXOS_PS_DIM_256:-$__LEXOS_C_DIM}"
			__LEXOS_C_UTILISATEUR="${LEXOS_PS_UTILISATEUR_256:-$__LEXOS_C_UTILISATEUR}"
			__LEXOS_C_LOGO="${LEXOS_PS_LOGO_256:-$__LEXOS_C_LOGO}"
			;;
	esac
}
__lexos_couleurs

# --- Invite de commande ------------------------------------------------------
#  Reposée à chaque passage, exprès : voir l'explication en tête de fichier.
#
#  LA RÈGLE DE COULEUR, de jour comme de nuit — ALEX, PHOTO DU TERMINAL :
#  « écriture blanc pour écriture de utilisateur, vert pour lexos » ; puis
#  « le nom de l'utilisateur en rouge clair, à côté LEXOS en vert foncé » ;
#  puis, captures à l'appui, la correction qui tient aujourd'hui : « la
#  couleur de marceau pour l'orange et le vert pour LEXOS », et « les
#  couleurs, on les retrouve dans les autres terminaux aussi » :
#    · ORANGE       — le NOM de l'utilisateur (\u), et lui seul. C'était le
#                    rouge clair ; Alex l'a changé. L'orange du nom et celui
#                    du curseur sont VOISINS mais pas identiques, exprès :
#                    lexos-theme-gen dit pourquoi, à TERM_UTILISATEUR ;
#    · vert foncé  — le mot « LEXOS », juste à côté. Il REMPLACE « @\h » :
#                    la machine s'appelle déjà lexos-pro, répéter son nom
#                    à côté d'un LEXOS écrit en dur ne dirait rien de plus ;
#    · vert        — ce que la MACHINE écrit : le CHEMIN et le CHEVRON. (La
#                    branche git, elle, est en __LEXOS_C_DIM — le gris des
#                    détails. Cette ligne a longtemps dit « vert » pour
#                    elle aussi, et le code disait autre chose.) ;
#    · blanc       — tout ce que VOUS tapez ;
#    · rouge       — ce qui n'a pas marché (fausse commande, commande en
#                    échec) : le chevron, et lui seul, vire à ce rouge-là.
#
#  L'orange du nom et le rouge d'erreur sont DEUX couleurs : le premier est
#  une signature, le second un signal, et ils ne doivent pas se lire pareil.
#  Du temps où le nom était rouge clair, c'était le piège évident ; depuis
#  qu'il est orange, le piège a changé de côté et c'est le CURSEUR qu'il ne
#  doit pas imiter. Les deux écarts sont mesurés dans lexos-theme-gen.
#  Le chevron garde son rouge quand la commande précédente a échoué — c'est
#  le seul signal que porte l'invite, on n'y touche pas.
#
#  De jour, ce sont les mêmes rôles, en versions assombries : c'est
#  lexos-theme-gen qui fait la conversion, l'invite ne s'en occupe pas. Le
#  blanc y devient l'encre foncée, et l'orange vif un orange sombre — sans
#  quoi ni la frappe ni le nom ne se liraient sur le crème. Mesuré :
#  l'orange de nuit #FF8700 ne donne que 2,21:1 sur ce crème.
#
#  Le blanc de la frappe tient à un détail : PS1 se termine par une couleur
#  qu'on ne referme PAS. Elle déborde donc sur ce qui est saisi ensuite —
#  c'est voulu. PS0, affiché juste après Entrée et avant l'exécution, remet
#  le tout à zéro pour que la sortie de la commande retrouve le vert.
#
#  UNE SEULE LIGNE. ALEX, PHOTO DU TERMINAL : « l'écriture, la ligne est pas
#  complète et a déjà une espace — faire en sorte que ça suive ---> ». PS1
#  portait un saut de ligne juste avant le chevron : le nom, la machine et
#  le chemin sur une ligne, le chevron seul sur la suivante. Il est remplacé
#  par une espace. Celle qui SUIT le chevron était déjà là — c'est ce
#  qu'Alex avait relevé — et elle n'a pas été doublée.
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
			#  On en profite pour relire les couleurs : c'est ce qui rend la
			#  bascule jour/nuit visible sans relancer le shell. La lecture
			#  est une commande interne de bash sur un fichier de dix lignes,
			#  elle ne crée aucun processus.
			__lexos_etat() { __lexos_code=$?; __lexos_couleurs; __lexos_style; }
			case "${PROMPT_COMMAND:-}" in
				*__lexos_etat*) ;;
				"")  PROMPT_COMMAND="__lexos_etat" ;;
				*)   PROMPT_COMMAND="__lexos_etat; $PROMPT_COMMAND" ;;
			esac
			#  Le chevron : VERT quand tout va bien — c'est la machine qui
			#  l'écrit, comme le nom et le chemin —, ROUGE quand la commande
			#  précédente a échoué. Une commande qui n'existe pas rend 127,
			#  et l'invite suivante s'ouvre donc en rouge.
			__lexos_fleche() {
				if [ "${__lexos_code:-0}" = "0" ]; then
					printf '\033[%sm' "$__LEXOS_C_MACHINE"
				else
					printf '\033[%sm' "$__LEXOS_C_ERREUR"
				fi
			}
			#  PS1 est en apostrophes simples : bash le REDÉVELOPPE à chaque
			#  affichage, donc les ${__LEXOS_C_*} suivent le thème courant.
			#  Le nom en ORANGE, « LEXOS » en vert foncé à la place de
			#  « @\h », puis le chemin et le chevron en vert machine, la
			#  branche git dans le gris des détails — et la frappe blanche,
			#  non refermée, en dernier.
			__LEXOS_PS1_CLASSIQUE='\[\033[${__LEXOS_C_UTILISATEUR}m\]\u\[\033[0m\] \[\033[${__LEXOS_C_LOGO}m\]LEXOS\[\033[0m\] \[\033[${__LEXOS_C_MACHINE}m\]\w\[\033[0m\]\[\033[${__LEXOS_C_DIM}m\]$(__lexos_git_branch)\[\033[0m\] \[$(__lexos_fleche)\]❯\[\033[0m\] \[\033[${__LEXOS_C_TEXTE}m\]'
			PS1="$__LEXOS_PS1_CLASSIQUE"
			PS0='\e[0m'

			#  ═══ L'INVITE « TI-LEX » — UN STYLE DE PLUS, À ALLUMER ═══
			#  ALEX (une invite modèle et la bannière « TI-LEX TERMINAL PRO
			#  v4 ») : « ti-lex en or, lexos en orange, pro en vert — les mêmes
			#  couleurs que la 2e image », puis le texte exact : « ti-lex_lexOS-pro ».
			#  Sur deux lignes, comme son modèle :
			#      ti-lex_lexOS-pro  ~/chemin ⎇ branche
			#      ─◇ ❯
			#  Le chemin et la branche restent, en gris discret : sans eux on
			#  ne sait plus où on est. Le chevron garde son rouge d'échec.
			#  C'est un STYLE, pas un remplacement : l'invite classique (une
			#  ligne, LEXOS en vert foncé) reste celle par défaut, et son banc
			#  ne bouge pas. « invite tilex » / « invite classique » change.
			#  Les couleurs sont celles de la bannière : l'or du « v4 », l'orange
			#  de « TERMINAL PRO », le vert de « TI-LEX » ; de jour, les mêmes
			#  en foncé, sinon l'or ne se lit pas sur le crème.
			#  PUIS, photo à l'appui : « ti-lex en vert lime, lexOS du même
			#  orange que la capuche du ti bonhomme ». Relevé au pixel sur sa
			#  bannière : la capuche vaut #F86A00. ti-lex passe au lime #A3FF12.
			__LEXOS_PS1_TILEX='\[\033[1;${__LEXOS_C_LIME}m\]\u\[\033[0;${__LEXOS_C_VERT_TL}m\]_\[\033[1;${__LEXOS_C_ORANGE_TL}m\]lexOS\[\033[0;${__LEXOS_C_VERT_TL}m\]-\[\033[1;${__LEXOS_C_VERT_TL}m\]pro\[\033[0m\]  \[\033[${__LEXOS_C_DIM}m\]\w$(__lexos_git_branch)\[\033[0m\]\n\[\033[${__LEXOS_C_VERT_TL}m\]─◇\[\033[0m\] \[$(__lexos_fleche)\]❯\[\033[0m\] \[\033[${__LEXOS_C_TEXTE}m\]'
			LEXOS_INVITE_FICHIER="${XDG_CONFIG_HOME:-$HOME/.config}/lexos/invite"
			__lexos_style_vu=""
			#  Pas de « local » : ce fichier est déclaré sh (shellcheck le lit
			#  ainsi, dash aussi via /etc/profile.d) et « local » n'est pas
			#  POSIX. Des noms en __lexos_, comme __lexos_code et __lexos_style_vu.
			__lexos_style() {
				__lexos_st="classique"
				if [ -r "$LEXOS_INVITE_FICHIER" ]; then
					read -r __lexos_st < "$LEXOS_INVITE_FICHIER" 2>/dev/null || __lexos_st="classique"
				fi
				if [ "$__lexos_st" = "tilex" ]; then
					__lexos_jour=""
					[ "${LEXOS_TERM_EFFECTIF:-}" = "jour" ] && __lexos_jour=1
					case "${COLORTERM:-}" in
						truecolor|24bit)
							if [ -n "$__lexos_jour" ]; then
								__LEXOS_C_LIME='38;2;77;124;15'; __LEXOS_C_ORANGE_TL='38;2;176;76;0'; __LEXOS_C_VERT_TL='38;2;11;107;58'
							else
								__LEXOS_C_LIME='38;2;163;255;18'; __LEXOS_C_ORANGE_TL='38;2;248;106;0'; __LEXOS_C_VERT_TL='38;2;57;231;95'
							fi ;;
						*)
							if [ -n "$__lexos_jour" ]; then
								__LEXOS_C_LIME='38;5;64'; __LEXOS_C_ORANGE_TL='38;5;130'; __LEXOS_C_VERT_TL='38;5;29'
							else
								__LEXOS_C_LIME='38;5;154'; __LEXOS_C_ORANGE_TL='38;5;202'; __LEXOS_C_VERT_TL='38;5;41'
							fi ;;
					esac
					__LEXOS_C_MACHINE="$__LEXOS_C_VERT_TL"   # le chevron dans le même vert
					PS1="$__LEXOS_PS1_TILEX"
				elif [ "$__lexos_style_vu" = "tilex" ]; then
					PS1="$__LEXOS_PS1_CLASSIQUE"     # on revient au classique une fois
				fi
				__lexos_style_vu="$__lexos_st"
			}
			#  « invite tilex » / « invite classique » : le choix est gardé dans
			#  ~/.config/lexos/invite, et pris dès la prochaine invite.
			invite() {
				case "${1:-}" in
					tilex|ti-lex) mkdir -p "${LEXOS_INVITE_FICHIER%/*}" && printf 'tilex\n' > "$LEXOS_INVITE_FICHIER" \
						&& printf '✓ Invite ti-lex : or, orange et vert.\n' ;;
					classique|lexos) mkdir -p "${LEXOS_INVITE_FICHIER%/*}" && printf 'classique\n' > "$LEXOS_INVITE_FICHIER" \
						&& printf '✓ Invite classique.\n' ;;
					*) printf 'Usage : invite tilex | classique\n' >&2; return 2 ;;
				esac
			}
			__lexos_style
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
		printf '\033[%sm✗ commande inconnue : %s\033[0m\n' \
			"${__LEXOS_C_ERREUR:-1;38;5;196}" "$1" >&2
		printf '\033[%sm Tape « aide » pour la liste des commandes.\033[0m\n' \
			"${__LEXOS_C_DIM:-2}" >&2
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

# --- La coloration du code ------------------------------------------------------
#  ALEX (photo du LexOS Pro Terminal, tout en vert) : « ajouter de la couleur au
#  code, pas juste vert comme couleur d'écriture, de la coloration dans le
#  code ». Le vert reste la voix de la machine (l'invite, les réponses en texte
#  simple) ; ce qui est du CODE prend les couleurs d'un éditeur :
#    · cat sur un fichier  -> bat (mots-clés, chaînes, nombres… en couleurs)
#    · man                 -> titres et options en couleurs
#    · diff, ip            -> leurs couleurs à eux
#    · colore <commande>   -> colore une sortie en texte brut (journaux, logs)
#  Dans un tuyau ou une redirection, bat écrit du texte nu, exactement comme
#  cat : « cat x | grep y » et « cat a > b » ne changent pas.
__lexos_bat=""
command -v bat >/dev/null 2>&1 && __lexos_bat=bat
[ -z "$__lexos_bat" ] && command -v batcat >/dev/null 2>&1 && __lexos_bat=batcat
if [ -n "$__lexos_bat" ]; then
	#  Un thème d'éditeur sombre et vif ; « export BAT_THEME=... » dans
	#  ~/.bashrc le remplace (liste : bat --list-themes).
	export BAT_THEME="${BAT_THEME:-Monokai Extended}"
	# shellcheck disable=SC2139
	alias cat="$__lexos_bat --paging=never --style=plain"
	#  Le texte d'aide des commandes (« ls --help | aide-couleur »), en couleurs.
	# shellcheck disable=SC2139
	alias aide-couleur="$__lexos_bat --paging=never --style=plain --language=help"
fi
unset __lexos_bat
#  Les pages de man en couleurs, sans outil de plus : less sait le faire.
#  L'échappement vient de printf, pas de $'…' : dash (sh) ne connaît pas
#  $'…' et y laissait « $\033[… » écrit en toutes lettres.
__lexos_esc="$(printf '\033')"
export LESS_TERMCAP_md="${__lexos_esc}[1;38;5;208m"   # titres : orange LexOS
export LESS_TERMCAP_me="${__lexos_esc}[0m"
export LESS_TERMCAP_us="${__lexos_esc}[4;38;5;81m"    # options, arguments : bleu
export LESS_TERMCAP_ue="${__lexos_esc}[0m"
export LESS_TERMCAP_so="${__lexos_esc}[1;30;48;5;214m" # barre du bas, recherche
export LESS_TERMCAP_se="${__lexos_esc}[0m"
unset __lexos_esc
export GROFF_NO_SGR=1
alias diff='diff --color=auto'
alias ip='ip -color=auto'
#  « colore journalctl -f », « colore cat app.log » : les dates, niveaux
#  (ERROR, WARN, INFO), nombres, chaînes et clé=valeur en couleurs. Fait en
#  awk, déjà présent partout : rien à installer.
colore() {
	if [ $# -gt 0 ]; then "$@" 2>&1; else cat; fi | LC_ALL=C.UTF-8 awk '
	BEGIN { R="\033[0m"; ERR="\033[1;38;5;203m"; WARN="\033[1;38;5;214m";
	        INFO="\033[38;5;81m"; CLE="\033[38;5;183m"; NB="\033[38;5;215m"; CH="\033[38;5;150m"; CRO="\033[38;5;117m" }
	{
		l = $0
		#  L ORDRE COMPTE : les nombres d abord, sur le texte nu — après, les
		#  codes de couleur posés contiendraient eux-mêmes des chiffres.
		gsub(/[0-9][0-9.:-]*[0-9]/, NB "&" R, l)
		gsub(/[A-Za-z_][A-Za-z0-9_.]*=/, CLE "&" R, l)
		gsub(/\[[A-Za-z][A-Za-z0-9_.:-]*\]/, CRO "&" R, l)
		gsub(/"[^"]*"/, CH "&" R, l)
		#  ALEX : « ajouter au terminal des émojis, avec de la belle
		#  coloration ». Un émoji en tête de ligne dit le niveau d un coup d oeil.
		if (l ~ /(ERROR|ERREUR|FATAL|CRIT|Traceback|[Ee]rror:|échec|failed)/) l = "❌ " ERR l R
		else if (l ~ /(WARN|WARNING|ATTENTION|deprecated)/) l = "⚠️  " WARN l R
		else if (l ~ /(DEBUG|TRACE)/) l = "🔍 " l
		else if (l ~ /(INFO|NOTICE)/) l = "💡 " l
		else if (l ~ /( OK|[Ss]uccess|réussi|terminé|[Dd]one|✓)/) l = "✅ " l
		else l = "   " l
		print l
		fflush()
	}'
}
#  « liste » (ou « le ») : le contenu d un dossier, un émoji par sorte de
#  fichier, dans les couleurs de ls. Les dossiers d abord.
#  EN SH, PAS EN BASH : /etc/profile.d fait lire ce fichier à dash aussi, et
#  un tableau « ( ) » y est une ERREUR DE SYNTAXE — dash s'arrêtait net ici,
#  et tout ce qui suit (alias, « animation », « tilex ») manquait. Le corps
#  entre ( ) tient lieu de « local » ; deux passages, des tableaux ;
#  « .[!.]* ..?* », de dotglob ; le test -e / -L, de nullglob.
liste() (
	d="${1:-.}"
	[ -d "$d" ] || { printf '❓ « %s » n est pas un dossier\n' "$d" >&2; exit 1; }
	#  UN SEUL TRI, celui de la locale — comme le faisait « "$d"/* » sous
	#  dotglob : les fichiers cachés restent à leur place alphabétique
	#  (.config entre Bureau et Documents), au lieu de remonter tous en tête
	#  parce que leur motif passe en premier. Un nom qui contient un retour à
	#  la ligne s'affiche en deux morceaux : le prix d'un tri en sh pur.
	tous="$(for f in "$d"/.[!.]* "$d"/..?* "$d"/*; do
		if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\n' "$f"; fi   # motif sans résultat : écarté
	done | sort)"
	for passe in dossiers fichiers; do
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		if [ -d "$f" ]; then [ "$passe" = dossiers ] || continue
		else [ "$passe" = fichiers ] || continue; fi
		n="${f##*/}"; e="${n##*.}"; [ "$e" = "$n" ] && e=""
		case "$e" in *[[:upper:]]*) e="$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')" ;; esac
		if [ -L "$f" ]; then ico="🔗"
		elif [ -d "$f" ]; then ico="📁"
		elif [ -x "$f" ] && [ -z "$e" ]; then ico="⚙️ "
		else case "$e" in
			py) ico="🐍" ;; sh|bash|zsh) ico="📜" ;; js|ts|mjs) ico="🟨" ;; html|htm) ico="🌐" ;; css) ico="🎨" ;;
			json|yaml|yml|toml|conf|cfg|ini|env) ico="🧾" ;; md|txt|rst) ico="📝" ;; pdf) ico="📕" ;;
			png|jpg|jpeg|gif|webp|svg|bmp) ico="🖼️ " ;; mp3|ogg|flac|wav|m4a) ico="🎵" ;; mp4|mkv|webm|mov|avi) ico="🎬" ;;
			zip|gz|xz|7z|tar|rar|zst) ico="📦" ;; deb) ico="📦" ;; iso|img) ico="💿" ;; gguf|safetensors) ico="🧠" ;;
			c|h|cpp|rs|go|java) ico="💻" ;; csv|ods|xlsx|db|sqlite) ico="📊" ;; log) ico="📋" ;; desktop) ico="🚀" ;;
			*) ico="📄" ;;
		esac; fi
		printf '%s ' "$ico"
		( cd -- "$d" && ls -d --color=always -- "$n" )
	done <<LISTE
$tous
LISTE
	done
)
alias le='liste'
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
# Les deux raccourcis du terminal jour / nuit, pour ne pas avoir à retenir
# la phrase complète.
alias jour='lexos terminal jour'
alias nuit='lexos terminal nuit'
#  « multi » : plusieurs volets dans un seul terminal (tmux).
#  ═══ ON NE LANCE PAS tmux D'OFFICE ICI, ET C'EST UN PIÈGE À TROIS DÉTENTES ═══
#  La tentation est forte — « comme ça tous les terminaux sont en volets » :
#    · un shell ouvert PAR UN PROGRAMME (Claude Code, un éditeur, le
#      gestionnaire de fichiers) se retrouverait dans tmux, où il n'a rien à
#      faire ;
#    · une session SSH ouvrirait un tmux DANS un tmux, où le préfixe de
#      l'extérieur mange celui de l'intérieur ;
#    · et qui n'aime pas tmux serait coincé dedans à chaque fenêtre, sans
#      savoir en sortir.
#  C'est une commande qu'on tape quand on en veut, pas un état imposé.
alias multi='lexos-multi'

#  « animation on / off » et « tilex » : définis AVANT la garde « une seule
#  fois par shell » — sinon un shell où le fichier a déjà été lu (le
#  terminal LexOS Pro, par exemple) ne les connaissait pas (« commande
#  inconnue : animation »). Seule la bannière automatique reste plus bas.
LEXOS_ANIM_FICHIER="${XDG_CONFIG_HOME:-$HOME/.config}/lexos/animation"
animation() {
	case "${1:-}" in
		on|oui)  mkdir -p "${LEXOS_ANIM_FICHIER%/*}" && printf 'on\n' > "$LEXOS_ANIM_FICHIER" \
			&& printf '✓ Bannière animée à chaque nouveau terminal (« animation off » pour l\x27enlever).\n' ;;
		off|non) mkdir -p "${LEXOS_ANIM_FICHIER%/*}" && printf 'off\n' > "$LEXOS_ANIM_FICHIER" \
			&& printf '✓ Plus de bannière à l\x27ouverture (« tilex » la montre quand tu veux).\n' ;;
		*) printf 'Usage : animation on | off\n' >&2; return 2 ;;
	esac
}
alias tilex='lexos-banniere'

# =============================================================================
#  À partir d'ici : une seule fois par shell.
# =============================================================================
[ -n "${LEXOS_SHELL_CHARGE:-}" ] && return 0
LEXOS_SHELL_CHARGE=1

# --- Terminal de jour ou de nuit : appliquer l'heure à l'ouverture ----------
#  En mode « auto », la minuterie systemd repasse tous les quarts d'heure —
#  mais si la session vient de s'ouvrir, ou si la machine a dormi tout
#  l'après-midi, le terminalrc sur le disque peut encore être celui de la
#  nuit. On rattrape ici, une seule fois, et en arrière-plan : la commande
#  réécrit deux petits fichiers, l'ouverture du terminal ne doit pas
#  l'attendre.
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] \
   && [ "$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/lexos/terminal-mode" 2>/dev/null)" = "auto" ] \
   && command -v lexos-terminal >/dev/null 2>&1; then
	( lexos-terminal --appliquer >/dev/null 2>&1 & ) 2>/dev/null
fi

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

# --- LA PANNE AVANT LA BANNIÈRE ---------------------------------------------
#  ═══ CE QU'ALEX A VU, ET CE QUI MANQUAIT ═══
#  Alienware, RTX 5060, entrée normale du menu : le bureau ne démarre pas, la
#  machine retombe en console — et la console affiche un masque en blocs, des
#  couleurs et des chiffres qui ont l'air d'aller. Rien ne disait que quelque
#  chose avait échoué. Il est arrivé sur un écran joyeux sans savoir s'il
#  était au bon endroit.
#
#  La bannière reste : elle est utile, et c'est elle qui prouve qu'on est
#  bien sur LexOS. Mais quand la session graphique a échoué, ça se dit AVANT,
#  et ça se dit en français.
#
#  ⚠ ON NE CRIE PAS AU LOUP. session_graphique_absente() exige QUATRE
#  conditions — pas de DISPLAY, pas de SSH, aucun serveur d'affichage nulle
#  part, et une machine qui vise bien le graphique. Un Ctrl+Alt+F2 pendant
#  que le bureau tourne ne déclenche rien : annoncer une panne à quelqu'un
#  dont la machine va bien, c'est le même défaut à l'envers que la tuile qui
#  affirme « Désactivé » faute d'avoir pu lire.
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -z "${DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] \
   && [ -r /usr/share/lexos/shell/session-graphique.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/lexos/shell/session-graphique.sh
	if session_graphique_absente; then
		echo
		session_graphique_dire
	fi
fi

# --- 🎬 La bannière TI-LEX animée, à l'ouverture d'un terminal graphique ------
#  ALEX : « ajouter de la couleur… et des animations ». lexos-banniere (pluie
#  de chiffres, TI-LEX, TERMINAL PRO v4) — seulement si on l'a allumée avec
#  « animation on » : un terminal qui s'ouvre sans qu'on l'ait demandé doit
#  rester instantané. « tilex » la rejoue quand on veut.
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] && [ -r "$LEXOS_ANIM_FICHIER" ] \
   && command -v lexos-banniere >/dev/null 2>&1; then
	read -r __lexos_anim < "$LEXOS_ANIM_FICHIER" 2>/dev/null
	[ "${__lexos_anim:-}" = "on" ] && lexos-banniere
	unset __lexos_anim
fi

# --- Bienvenue en console (pas dans les scripts, pas dans le terminal graphique)
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -z "${DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] && command -v lexfetch >/dev/null 2>&1; then
	lexfetch
fi
