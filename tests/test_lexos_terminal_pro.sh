#!/usr/bin/env bash
# =============================================================================
#  Éprouver LexOS Pro Terminal — le terminal officiel qui remplace l'ancien
# =============================================================================
#  ALEX : « c'est le new terminal officiel de LexOS Pro, pour le terminal
#  normal je veux que ce soit lui qui le remplace. »
#
#  ══ CE QUE CE BANC SURVEILLE, ET POURQUOI CHAQUE POINT A COÛTÉ QUELQUE CHOSE ══
#
#  1. LES COMMANDES S'EXÉCUTENT POUR DE VRAI. La page d'origine simulait un
#     système de fichiers ENTIER en mémoire (un projet fictif, un « lex
#     status » qui prétendait construire du code qui n'existe pas). Un
#     terminal qui remplace le vrai doit toucher le vrai disque — sinon
#     « ls » ment sur ce qui est vraiment là.
#
#  2. LE PONT EXÉCUTE N'IMPORTE QUOI, EXPRÈS — donc SEUL qui peut l'atteindre
#     compte. Trois verrous : 127.0.0.1 seulement, un jeton tiré au hasard
#     exigé dans un en-tête (jamais dans l'URL toute seule — une page
#     malveillante pourrait sinon poster en aveugle avant toute vérification
#     CORS), et l'Origine quand le navigateur en pose une.
#
#  3. CE QUI NE PEUT PAS MARCHER EST DIT, PAS CACHÉ. Cette fenêtre n'a pas de
#     grille de caractères ni de curseur qu'on déplace : les programmes
#     plein écran (vim, nano, htop, less, man…) sont reconnus AVANT d'être
#     lancés, et renvoient vers le Terminal classique au lieu d'un carnage
#     de codes d'échappement.
#
#  4. AUCUNE COMMANDE FICTIVE NE MASQUE PLUS UNE VRAIE COMMANDE. La page
#     d'origine réimplémentait ls/cd/cat/mkdir/rm/grep/find/wc/tree/whoami/
#     uname/env/ps/neofetch en JavaScript, contre l'arbre en mémoire. Si un
#     seul de ces noms redevenait un « built-in » local, taper « ls » ne
#     montrerait plus JAMAIS le vrai dossier — un bogue qui ne se verrait
#     qu'en cherchant un fichier qu'on sait pourtant présent.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web/index.html"
LANCEUR="$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal"
BUREAU="$RACINE/config/includes.chroot/usr/share/applications/lexos-pro-terminal.desktop"
HOOK="$RACINE/config/hooks/normal/0455-lexos-terminal-pro.hook.chroot"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
COMPLETION="$RACINE/config/includes.chroot/usr/share/bash-completion/completions/lexos"
DOCKITEM="$RACINE/config/includes.chroot/etc/skel/.config/plank/dock1/launchers/01-terminal.dockitem"
PANNEAU="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
RACCOURCIS="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$BACKEND" "$PAGE" "$LANCEUR" "$BUREAU" "$HOOK" "$DISPATCH" "$COMPLETION" \
         "$DOCKITEM" "$PANNEAU" "$RACCOURCIS"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE BACKEND : renvoyé au banc du pseudo-terminal"
# =============================================================================
#  CETTE SECTION A ÉTÉ VIDÉE, ET C'EST LE SIGNE QUE LE TRAVAIL EST FAIT.
#  Elle éprouvait executer() : un bash JETABLE par commande, l'entrée fermée
#  (stdin=DEVNULL), la sortie ramassée d'un bloc, un délai de 25 s, et
#  ansi_vers_html() qui RETIRAIT en silence tout ce qui n'était pas une
#  couleur — déplacements du curseur, effacements d'écran.
#
#  ALEX : « j'ai beau essayer le terminal LexOS Pro, je suis même pas capable
#  de lancer claude ». Ces quatre choses étaient la raison. Il n'y a plus de
#  bash jetable ni de journal de lignes : un vrai pseudo-terminal, un shell
#  par volet, et xterm.js qui tient la grille de caractères.
#
#  Ce que cette section éprouvait est donc devenu SANS OBJET — et ce qui l'a
#  remplacé est éprouvé ailleurs, plus sévèrement :
#    · tests/test_lexos_terminal_pty.sh          le pty et les quatre routes
#    · tests/test_lexos_terminal_navigateur.sh   l'affichage, dans Chromium
#
#  On garde ici UN contrôle : que l'ancien chemin ne revienne pas par la
#  petite porte. Un « executer() » qui reparaîtrait à côté du pty rendrait
#  le comportement du terminal dépendant de la commande tapée.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent"
else
	#  ═══ ON LIT DU CODE, PAS DE LA PROSE ═══
	#  « sed 's/#.*//' » ne suffit pas ici : l'en-tête du fichier est une
	#  DOCSTRING, pas un commentaire « # », et elle raconte exprès ce qui a
	#  disparu — « LISTE_TUI », « capture_output », le délai de 25 s. Un
	#  grep sur le texte brut serait donc rouge à jamais, et la tentation
	#  serait d'effacer l'explication pour faire taire le banc : on perdrait
	#  la seule trace écrite de pourquoi claude ne démarrait pas.
	#
	#  On passe donc par le TOKENIZER de Python : il ne rend que les noms,
	#  les opérateurs et les nombres — jamais le contenu d'une chaîne ni
	#  d'un commentaire. Ce qui reste est du code, et rien d'autre.
	python3 - "$BACKEND" > "$BANC/pont-code.txt" <<'PY'
import io, sys, token, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
mots = []
for t in tokenize.generate_tokens(io.StringIO(src).readline):
    if t.type in (token.NAME, token.OP, token.NUMBER):
        mots.append(t.string)
sys.stdout.write(" ".join(mots))
PY
	CODE_PONT="$(cat "$BANC/pont-code.txt")"
	MORTS=""
	for MOTIF in "def executer" "def ansi_vers_html" "LISTE_TUI" "DELAI_MAX" "capture_output" "DEVNULL"; do
		grep -qF "$MOTIF" <<< "$CODE_PONT" && MORTS="$MORTS $MOTIF"
	done
	if [ -z "$MORTS" ]; then
		ok "l'ancien chemin (bash jetable, entrée fermée, délai, journal de lignes) a bien disparu"
	else
		non "l'ancien chemin est de retour dans le pont :$MORTS"
	fi
	#  ET LE NOUVEAU EST BIEN LÀ : sans ce contrôle, un fichier VIDE
	#  passerait le contrôle ci-dessus avec les honneurs.
	#  Le tokenizer retire aussi les CHAÎNES : « /api/flux » n'y est plus.
	#  On le cherche donc dans le fichier, mais sur la ligne de code qui
	#  l'utilise — pas dans l'en-tête qui le décrit.
	if grep -qF "pty . fork" <<< "$CODE_PONT" && grep -qE '^\s*if chemin == "/api/flux"' "$BACKEND"; then
		ok "le pont repose bien sur un pseudo-terminal et sert le flux (/api/flux)"
	else
		non "le pont n'a ni pty.fork ni /api/flux — le terminal ne peut rien afficher"
	fi
fi

# =============================================================================
titre "2. SÉCURITÉ — ce qui reste vrai après le pty"
# =============================================================================
#  Le modèle n'a pas bougé (127.0.0.1, jeton, Origine) mais les routes, si :
#  /api/exec a disparu ; /api/flux, /api/saisie, /api/taille et /api/fermer
#  l'ont remplacée. LA MATRICE COMPLÈTE — quatre routes contre trois refus —
#  est dans tests/test_lexos_terminal_pty.sh, et c'est elle qui a trouvé que
#  /api/flux ne vérifiait NI le jeton NI l'origine : la route la plus
#  sensible des quatre, celle qui ouvre le shell. Ici on garde le contrôle
#  qui ne dépend d'aucune route : sur quoi le serveur écoute.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : l'écoute du pont n'a PAS été éprouvée"
else
	SORTIE_S="$(LEXOS_TERMINAL_PRO_WEB="$BANC" python3 - "$BACKEND" <<'PY' 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true
import sys, importlib.util
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

try:
    serveur, port, jeton = tp.demarrer_serveur()
    #  Un terminal exécute n'importe quoi, exprès : SEUL compte qui peut
    #  l'atteindre. Écouter 0.0.0.0 offrirait un shell au réseau entier.
    dit(serveur.socket.getsockname()[0] == "127.0.0.1", "le serveur n'écoute QUE 127.0.0.1")
    #  Le jeton est tiré à CHAQUE lancement : deux fenêtres ouvertes en même
    #  temps ne doivent jamais partager le même.
    serveur2, _, jeton2 = tp.demarrer_serveur()
    dit(jeton != jeton2 and len(jeton) >= 32, "le jeton est neuf à chaque lancement, et assez long")
    serveur.shutdown(); serveur2.shutdown()
except Exception as e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(e).__name__, e))
print("FIN|")
PY
)"
	if [ -z "$SORTIE_S" ]; then
		non "le pont n'a rien rendu sur son écoute"
	elif ! grep -q '^FIN|' <<< "$SORTIE_S"; then
		non "le banc de sécurité s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_S
EOF
	fi
fi

# =============================================================================
titre "3. LE FRONT-END — la page ne réimplémente toujours RIEN"
# =============================================================================
#  ══ CE QUE CETTE SECTION SURVEILLE DEPUIS LE DÉBUT ══
#  La page d'origine simulait un système de fichiers ENTIER en mémoire, et
#  réimplémentait ls, cd, cat, mkdir, rm, grep, find, wc, tree, whoami,
#  uname, env, ps, neofetch en JavaScript contre cet arbre fictif. Si un seul
#  de ces noms redevenait un « built-in » de la page, taper « ls » ne
#  montrerait plus JAMAIS le vrai dossier — un bogue invisible tant qu'on ne
#  cherche pas un fichier qu'on sait pourtant présent.
#
#  ══ CE QUI A CHANGÉ, ET POURQUOI LE CONTRÔLE DEVIENT PLUS SIMPLE ══
#  La page n'a plus de ligne de commande du tout : elle ne LIT plus ce qu'on
#  tape, elle le transmet au pty octet par octet (xterm.onData → /api/saisie).
#  Il n'y a donc plus rien à intercepter, ni aucun tableau de commandes où
#  une commande fictive pourrait se cacher. On vérifie exactement ça.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : la page n'a PAS été relue"
else
	#  ON LIT LE CODE, PAS LES COMMENTAIRES. Ce fichier PARLE de « ls », de
	#  « COMMANDES » et de l'ancien journal pour expliquer ce qui a disparu ;
	#  un grep naïf serait rouge à jamais — ou pire, on l'émousserait pour le
	#  faire taire. Piège déjà payé deux fois dans ce dépôt.
	python3 - "$PAGE" > "$BANC/page-code.js" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<script>(.*)</script>", s, re.S)
js = m.group(1) if m else ""
js = re.sub(r"/\*.*?\*/", "", js, flags=re.S)
js = "\n".join(l for l in js.splitlines() if not l.lstrip().startswith("//"))
sys.stdout.write(js)
PY
	CODE="$(cat "$BANC/page-code.js")"
	if [ -z "$CODE" ]; then
		non "impossible d'extraire le code de la page"
	else
		if grep -qE "\bCOMMANDES\b" <<< "$CODE"; then
			non "un tableau de commandes de la page est revenu : il masquerait de vrais programmes"
		else
			ok "aucun tableau de commandes dans la page — rien ne peut masquer un vrai programme"
		fi

		#  Le chemin de la frappe, en entier. Si « onData » disparaissait,
		#  plus rien ne partirait au shell : une fenêtre belle et morte.
		if grep -q "onData" <<< "$CODE" && grep -q "/api/saisie" <<< "$CODE"; then
			ok "ce qu'on tape va de xterm.js au pty sans être relu par la page (onData → /api/saisie)"
		else
			non "le chemin de la frappe est cassé : ni onData ni /api/saisie"
		fi

		#  EventSource ne sait pas poser d'en-tête personnalisé : s'en servir
		#  pour le flux ferait tomber le jeton, donc 403, donc un terminal
		#  muet — et la panne serait à un endroit (la sécurité) très loin du
		#  symptôme (rien ne s'affiche). La consigne l'interdit nommément.
		if grep -q "EventSource" <<< "$CODE"; then
			non "le flux passe par EventSource : il ne peut pas porter le jeton (403 garanti)"
		else
			ok "le flux est lu par fetch + getReader, pas par EventSource"
		fi

		if grep -q "X-Lexos-Jeton" <<< "$CODE"; then
			ok "la page envoie le jeton dans un en-tête sur ses appels au pont"
		else
			non "la page n'envoie plus le jeton : le pont refusera tout"
		fi
	fi

	#  ═══ RIEN NE VIENT D'INTERNET ═══
	#  Mesuré dans un vrai navigateur : les polices allaient chez Google à
	#  CHAQUE ouverture et échouaient (ERR_CONNECTION_RESET). Le terminal
	#  principal du système doit s'ouvrir sur un portable sans réseau.
	if grep -qE "https?://(cdn|unpkg|jsdelivr|fonts\.google|fonts\.gstatic)" "$PAGE"; then
		non "la page va chercher un fichier sur Internet : elle ne marchera pas hors ligne"
	else
		ok "aucune ressource distante : tout vient de l'ISO (vendor/ et les polices Debian)"
	fi
fi

# =============================================================================
titre "4. TOUT EST BRANCHÉ — dispatcheur, aide, complétion, dock, panneau"
# =============================================================================
#  ═══ IL N'Y A PLUS DE COMMANDE DE DÉMARRAGE, ET C'EST LE CORRECTIF ═══
#  La page demandait « printf "%s\\n" "$HOME"; whoami » au pont avant d'ouvrir
#  la première fenêtre, pour dessiner une invite crédible. Sans le « \\n », les
#  deux sorties se collaient (« /rootroot ») : nom d'utilisateur ET dossier
#  personnel faux, en silence — trouvé en chargeant la vraie page dans un vrai
#  navigateur contre un vrai pont.
#
#  La vraie correction n'est pas le « \\n » : c'est qu'il n'y a plus DEUX
#  sources de vérité. Le shell écrit sa propre invite, avec son vrai nom
#  d'utilisateur et son vrai dossier. Ce contrôle veille donc à ce que la
#  page ne se remette pas à deviner ce que bash sait déjà.
if grep -qF 'whoami' "$PAGE"; then
	non "la page redemande le nom d'utilisateur au pont : c'est au shell de l'écrire"
else
	ok "la page ne devine plus ni le dossier personnel ni l'utilisateur — bash les écrit"
fi
bash -n "$LANCEUR" 2>/dev/null && ok "lexos-pro-terminal : syntaxe bash valide" \
	|| non "lexos-pro-terminal : erreur de syntaxe"
#  La CHAÎNE « --classique » apparaît aussi dans l'aide : on vérifie la
#  vraie BRANCHE du case, pas seulement sa mention en commentaire ou en aide.
grep -qE -- '--classique\|classique\)[[:space:]]*classique[[:space:]]*;;' "$LANCEUR" \
	&& ok "le Terminal classique reste atteignable (branche --classique du case)" \
	|| non "aucun repli vers un vrai terminal"

# =============================================================================
#  ═══ ET ON LE LANCE POUR DE VRAI — LE grep CI-DESSUS NE PROUVAIT RIEN ═══
# =============================================================================
#  CE QUE ÇA FAISAIT AVANT : le contrôle du dessus certifiait « le Terminal
#  classique reste atteignable » en trouvant une branche de « case ». La
#  branche était bien là. Elle appelait classique(), qui commençait par
#  « exec x-terminal-emulator » — l'alternative Debian que le hook 0455 a
#  rebranchée sur lexos-pro-terminal.wrapper, lequel fait « exec
#  /usr/bin/lexos-pro-terminal ». Le filet de secours se rappelait lui-même.
#
#  MESURÉ AVANT LE CORRECTIF, dans le bac à sable ci-dessous :
#      « --classique », PySide6 absent : tué à 8 s (code 124),
#      1222 passages dans le lanceur, xfce4-terminal lancé 0 fois.
#  Sur une machine sans PySide6 — exactement celle où ce filet est la
#  dernière chance d'avoir un terminal — Super+T ne donnait plus rien et
#  occupait un cœur.
#
#  Un contrôle qui lit du texte ne pouvait pas voir ça. Celui-ci EXÉCUTE le
#  lanceur, dans une machine reconstituée : x-terminal-emulator branché sur
#  le pont, PySide6 absent, et un faux xfce4-terminal qui dit son nom.
BAC="$BANC/classique"; mkdir -p "$BAC/bin" "$BAC/web"
cp "$LANCEUR" "$BAC/bin/lexos-pro-terminal"
sed "s|/usr/bin/lexos-pro-terminal|$BAC/bin/lexos-pro-terminal|" \
	"$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal.wrapper" \
	> "$BAC/bin/lexos-pro-terminal.wrapper"
ln -sf "$BAC/bin/lexos-pro-terminal.wrapper" "$BAC/bin/x-terminal-emulator"
printf '#!/bin/sh\necho VRAI-TERMINAL-CLASSIQUE\n' > "$BAC/bin/xfce4-terminal"
#  PySide6 absent : c'est le cas qui compte, celui du filet de secours.
printf '#!/bin/sh\nexit 1\n' > "$BAC/bin/python3"
chmod +x "$BAC/bin"/*
#  Un compteur de passages : une boucle se voit au nombre, pas au silence.
sed -i "3i printf x >> $BAC/tours" "$BAC/bin/lexos-pro-terminal"
: > "$BAC/tours"
#  CODE est en dur dans le lanceur ; sans ce fichier il sort avant d'arriver
#  au filet, et le contrôle ne mesurerait rien.
if [ -r /usr/lib/lexos/terminal-pro.py ]; then
	SORTIE_CL="$(PATH="$BAC/bin:$PATH" LEXOS_TERMINAL_PRO_WEB="$BAC/web" \
		timeout 8 "$BAC/bin/lexos-pro-terminal" --classique 2>&1)"
	CODE_CL=$?
	TOURS_CL="$(wc -c < "$BAC/tours" | tr -d ' ')"
	if [ "$CODE_CL" = "124" ]; then
		non "« --classique » ne s-arrête jamais : ${TOURS_CL} passages en 8 s — le filet de secours se rappelle lui-même"
	elif grep -q 'VRAI-TERMINAL-CLASSIQUE' <<< "$SORTIE_CL" && [ "${TOURS_CL:-0}" -le 2 ]; then
		ok "« --classique » lance VRAIMENT le terminal classique, en un seul passage (mesuré, pas lu)"
	else
		non "« --classique » n-a pas lancé le terminal classique (${TOURS_CL} passages, code ${CODE_CL})"
	fi
	#  Et le filet lui-même : lancement NORMAL sans PySide6.
	: > "$BAC/tours"
	SORTIE_FI="$(PATH="$BAC/bin:$PATH" LEXOS_TERMINAL_PRO_WEB="$BAC/web" \
		timeout 8 "$BAC/bin/lexos-pro-terminal" 2>&1)"
	CODE_FI=$?
	TOURS_FI="$(wc -c < "$BAC/tours" | tr -d ' ')"
	if [ "$CODE_FI" = "124" ]; then
		non "sans PySide6, le lanceur boucle : ${TOURS_FI} passages en 8 s — plus aucun terminal sur la machine"
	elif grep -q 'VRAI-TERMINAL-CLASSIQUE' <<< "$SORTIE_FI"; then
		ok "sans PySide6, le filet ouvre le terminal classique — Super+T donne toujours quelque chose"
	else
		non "sans PySide6, aucun terminal ne s-ouvre (${TOURS_FI} passages, code ${CODE_FI})"
	fi
else
	printf '  \033[2mrepli du terminal non EXÉCUTÉ : /usr/lib/lexos/terminal-pro.py absent de cette machine\033[0m\n'
fi
grep -q 'QtWebEngineWidgets' "$LANCEUR" \
	&& ok "PySide6 WebEngine est vérifié avant de lancer la fenêtre" \
	|| non "aucune vérification de PySide6 avant le lancement"

grep -qE '(^|[^a-z-])terminal-pro[^a-z-].*exec lexos-pro-terminal' "$DISPATCH" \
	&& ok "« lexos terminal-pro » mène à l'outil" \
	|| non "aucune branche « terminal-pro » dans le dispatcheur"
sed 's/${[A-Z]*}//g' "$DISPATCH" | awk '/^cmd_help\(\)/,0' > "$BANC/aide-nue"
grep -qE '(^|[[:space:]])terminal-pro([[:space:]]|$)' "$BANC/aide-nue" \
	&& ok "…et l'aide en parle" \
	|| non "« terminal-pro » n'apparaît pas dans l'aide"
grep -q 'terminal-pro' "$COMPLETION" \
	&& ok "…et la touche Tab la propose" \
	|| non "« terminal-pro » manque à la complétion"

EXEC_PROG="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$BUREAU" | head -1)"
[ "$EXEC_PROG" = "lexos-pro-terminal" ] \
	&& ok "le .desktop appelle bien lexos-pro-terminal" \
	|| non "le .desktop appelle « $EXEC_PROG », pas lexos-pro-terminal"
grep -q '^Icon=lexos-pro-terminal' "$BUREAU" \
	&& ok "…avec sa propre icône" \
	|| non "aucune icône déclarée pour le .desktop"
grep -q 'Terminal classique' "$BUREAU" \
	&& ok "…et une action secondaire mène au Terminal classique" \
	|| non "aucune action « Terminal classique » sur le .desktop"

grep -q 'lexos-pro-terminal.desktop' "$DOCKITEM" \
	&& ok "le dock ouvre maintenant LexOS Pro Terminal" \
	|| non "le dock pointe encore ailleurs"
grep -q 'lexos-pro-terminal.desktop' "$PANNEAU" \
	&& ok "…et les favoris du panneau aussi" \
	|| non "les favoris du panneau n'ont pas changé"
grep -q 'value="lexos-pro-terminal"' "$RACCOURCIS" \
	&& ok "Super+Retour et Super+T ouvrent LexOS Pro Terminal" \
	|| non "les raccourcis clavier n'ont pas changé"

#  ═══ LE TERMINAL CLASSIQUE N'A PAS DISPARU ═══
#  Rien de ce qui vient d'être câblé ne doit avoir RETIRÉ xfce4-terminal :
#  Claude Code, OpenCode, les scripts qui demandent une confirmation tapée,
#  l'enregistrement vidéo (--hold) en ont toujours besoin.
#  On vise la ligne « exec » elle-même, pas n'importe quelle mention du nom
#  (un commentaire suffirait sinon à garder ce contrôle vert par accident).
for USAGE in 'lexos-claude-terminal' 'lexos-opencode'; do
	F2="$RACINE/config/includes.chroot/usr/bin/$USAGE"
	if [ -r "$F2" ] && grep -qE 'exec (x-terminal-emulator|xfce4-terminal)' "$F2"; then
		ok "$USAGE garde son vrai terminal (pty complet)"
	else
		non "$USAGE ne référence plus aucun terminal réel"
	fi
done

grep -q 'ICONES_HICOLOR' "$HOOK" \
	&& ok "le hook 0455 rend l'icône aux huit tailles, comme les autres" \
	|| non "le hook 0455 ne suit pas le patron des autres icônes LexOS"
grep -q 'VDIR=.*scalable' "$HOOK" && grep -q 'rm -f "\$VDIR' "$HOOK" \
	&& ok "…et retire toute version scalable (le dock ne changerait pas de dessin au survol)" \
	|| non "une version scalable pourrait rester et changer de dessin au survol du dock"

# =============================================================================
titre "LE TERMINAL PRINCIPAL DU SYSTÈME"
# =============================================================================
#  ALEX : « je voudrais juste que le terminal principal du système soit le
#  terminal LexOS Pro ».
#
#  Trois branchements, et le troisième est un piège documenté : terminal-pro.py
#  NE TRAITE AUCUN ARGUMENT. Brancher le lanceur directement sur l'alternative
#  « x-terminal-emulator » ferait ouvrir une fenêtre VIDE, sans rien lancer, à
#  chaque fois qu'un programme du système fait « x-terminal-emulator -e
#  commande » — une panne muette, la pire espèce.
PONT="$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal.wrapper"
AIDE="$RACINE/config/includes.chroot/usr/share/xfce4/helpers/lexos-pro-terminal.desktop"

if [ -r "$AIDE" ]; then
	ok "l'assistant XFCE existe (sans lui, « Applications par défaut » ne le propose pas)"
	grep -q '^X-XFCE-Category=TerminalEmulator' "$AIDE" \
		&& ok "…et il se déclare bien comme émulateur de terminal" \
		|| non "l'assistant ne porte pas X-XFCE-Category=TerminalEmulator"
	grep -q '^X-XFCE-Binaries=lexos-pro-terminal;' "$AIDE" \
		&& ok "…et il nomme le bon programme" \
		|| non "l'assistant ne nomme pas lexos-pro-terminal"
else
	non "aucun assistant XFCE : la page « Applications par défaut » ne verra pas LexOS Pro Terminal"
fi

if [ -x "$PONT" ]; then
	ok "le pont x-terminal-emulator existe et est exécutable"
	#  ═══ ET IL TRANSMET POUR DE VRAI ═══
	#  On le fait tourner avec un faux LexOS Pro Terminal qui répète ses
	#  arguments, et on regarde ce qui arrive. Lire le fichier ne suffirait
	#  pas : c'est le comportement qui compte.
	#
	#  CE CONTRÔLE A CHANGÉ DE SENS, ET VOICI POURQUOI. Le pont renvoyait
	#  vers le Terminal classique TOUT ce qui demandait d'exécuter une
	#  commande (« -e », « -x », « --working-directory »…), parce que
	#  terminal-pro.py ne lisait aucun argument : brancher l'alternative
	#  Debian dessus aurait ouvert une fenêtre VIDE, en silence, chaque fois
	#  qu'un programme du système demande un terminal pour lancer quelque
	#  chose. LexOS Pro Terminal lit maintenant ses arguments ET a un vrai
	#  pty : le détournement n'a plus lieu d'être, et le laisser en place
	#  voudrait dire que la moitié du système continue d'ouvrir l'ancien
	#  terminal sans que personne ne s'en aperçoive.
	PB="$(mktemp -d)"
	printf '#!/bin/sh\necho CLASSIQUE\n' > "$PB/xfce4-terminal.wrapper"
	printf '#!/bin/sh\necho "PRO:$*"\n'  > "$PB/lexos-pro-terminal"
	chmod +x "$PB"/*
	sed -e "s|/usr/bin/xfce4-terminal.wrapper|$PB/xfce4-terminal.wrapper|" \
	    -e "s|/usr/bin/lexos-pro-terminal|$PB/lexos-pro-terminal|" \
	    "$PONT" > "$PB/pont"
	chmod +x "$PB/pont"
	MAUVAIS=0
	for A in "" "--title=Truc" "-e ls" "-x htop" "--command=top" \
	         "--hold -e ls" "--working-directory=/tmp"; do
		# shellcheck disable=SC2086
		R="$(bash "$PB/pont" $A 2>/dev/null)"
		case "$R" in
			PRO:*) : ;;
			*) non "« $A » n'arrive pas à LexOS Pro Terminal (reçu : $R)"; MAUVAIS=1 ;;
		esac
	done
	[ "$MAUVAIS" = 0 ] && ok "toutes les formes d'appel arrivent à LexOS Pro Terminal, sans détour"
	#  ET LES ARGUMENTS ARRIVENT ENTIERS. Un pont qui les avalerait ouvrirait
	#  un terminal sans rien lancer : la fenêtre vide, autrement.
	R="$(bash "$PB/pont" --working-directory=/tmp -e "ls -la" 2>/dev/null)"
	if [ "$R" = "PRO:--working-directory=/tmp -e ls -la" ]; then
		ok "les arguments traversent le pont intacts (dossier de départ et commande)"
	else
		non "le pont abîme les arguments (reçu : $R)"
	fi

	#  ═══ ET LE PONT SAIT VRAIMENT LES LIRE, DE L'AUTRE CÔTÉ ═══
	#  Le pont peut bien tout transmettre : si terminal-pro.py ne comprend
	#  pas ces options, on retombe sur la fenêtre vide et muette qu'on
	#  voulait justement éviter. On interroge donc lire_arguments() sur les
	#  DEUX conventions — celle de xfce4-terminal (« -e "ls -la" », un seul
	#  argument) et celle de Debian (« -e ls -la », déjà découpé).
	if command -v python3 >/dev/null 2>&1; then
		SORTIE_A="$(python3 - "$BACKEND" <<'PY' 2>/dev/null | grep -E '^(OK|NON)\|' || true
import sys, importlib.util
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
def dit(b, m): print(("OK|" if b else "NON|") + m)
dit(tp.lire_arguments(["--working-directory=/tmp"]) == ("/tmp", None, False),
    "--working-directory= : « Ouvrir un terminal ici » de Thunar arrive au bon dossier")
dit(tp.lire_arguments(["--working-directory", "/etc"]) == ("/etc", None, False),
    "--working-directory séparé du dossier : compris aussi")
dit(tp.lire_arguments(["-e", "ls -la"]) == (None, "ls -la", False),
    "-e « ls -la » (xfce4-terminal : UN argument) : la ligne entière")
dit(tp.lire_arguments(["-e", "ls", "-la", "/tmp"]) == (None, "ls -la /tmp", False),
    "-e ls -la /tmp (Debian : déjà découpé) : recollé sans perdre d'argument")
dit(tp.lire_arguments(["-e", "echo", "deux mots"]) == (None, "echo 'deux mots'", False),
    "un argument qui contient une espace est protégé au recollage")
dit(tp.lire_arguments(["--hold", "-x", "lexos", "capture", "video"]) == (None, "lexos capture video", True),
    "--hold : le volet reste ouvert après la commande (lanceur 11 du panneau)")
dit(tp.lire_arguments([]) == (None, None, False),
    "sans argument : un shell ordinaire, rien de plus")
PY
)"
		if [ -z "$SORTIE_A" ]; then
			non "lire_arguments() n'existe pas : les options seraient ignorées en silence"
		else
			while IFS='|' read -r V M; do
				case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
			done <<EOF
$SORTIE_A
EOF
		fi
	fi
	rm -rf "$PB"
else
	non "aucun pont x-terminal-emulator : brancher le lanceur nu ouvrirait des fenêtres vides"
fi

#  Le hook doit poser les deux, et ne PAS toucher au lanceur 11 du panneau,
#  qui a besoin d'un vrai pty et de « --hold ».
grep -q 'update-alternatives --install /usr/bin/x-terminal-emulator' "$HOOK" \
	&& ok "le hook 0455 branche l'alternative Debian" \
	|| non "le hook 0455 ne branche pas x-terminal-emulator"
grep -q 'TerminalEmulator=lexos-pro-terminal' "$HOOK" \
	&& ok "…et le helpers.rc du squelette dit le même choix" \
	|| non "le squelette ne nomme pas LexOS Pro Terminal comme émulateur"

# =============================================================================
titre "5. LA PALETTE VIENT DU THÈME, PLUS DE LA PAGE"
# =============================================================================
#  ALEX : « les couleurs, on les retrouve dans les autres terminaux aussi ».
#  La page portait les siennes : un TROISIÈME orange pour le curseur, un vert
#  ANSI qui n'était pas celui de LexOS, et un fond noir même en thème JOUR.
#  Trois choses à mesurer, et elles ne se remplacent pas :
#   · le pont EXTRAIT bien ce que le générateur écrit ;
#   · il REFUSE ce qui n'est pas une couleur — « setProperty » n'est pas un
#     filtre, et « #000;}body{background:url(…) » est du CSS valide ;
#   · la page DEMANDE et APPLIQUE.
PONT_PY="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
GEN_TH="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
if [ ! -r "$PONT_PY" ] || [ ! -x "$GEN_TH" ]; then
	non "le pont ou le générateur est introuvable : la palette n'est pas vérifiable"
else
	rm -rf "${BANC:?}/th"; mkdir -p "$BANC/th"
	for MODE in nuit jour; do
		bash "$GEN_TH" --target "$BANC/th/$MODE" --terminal "$MODE" orange >/dev/null 2>&1
	done
	RES="$(PONT_PY="$PONT_PY" BANC="$BANC" python3 - <<'PY' 2>/dev/null
import importlib.util, os, tempfile
sp = importlib.util.spec_from_file_location("tp", os.environ["PONT_PY"])
tp = importlib.util.module_from_spec(sp); sp.loader.exec_module(tp)
banc = os.environ["BANC"]
for mode in ("nuit", "jour"):
    t = tp.lire_theme(os.path.join(banc, "th", mode, ".config", "lexos", "terminal.env"))
    for cle in ("LEXOS_TERM_BG", "LEXOS_TERM_FG", "LEXOS_TERM_TEXTE",
                "LEXOS_TERM_CURSEUR", "LEXOS_TERM_EFFECTIF"):
        print("%s.%s=%s" % (mode, cle, t.get(cle, "")))
#  Les valeurs hostiles, une par une.
p = os.path.join(tempfile.mkdtemp(), "t.env")
open(p, "w").write("# commentaire\n"
                   "LEXOS_TERM_BG=#000;}body{background:url(http://x)\n"
                   "LEXOS_TERM_EFFECTIF=rm -rf /\n"
                   "PATH=/usr/mechant\n"
                   "LEXOS_TERM_FG=#00D700\n")
h = tp.lire_theme(p)
print("hostile.cles=%s" % ",".join(sorted(h)))
print("absent.vide=%s" % ("oui" if tp.lire_theme("/n/existe/pas") == {} else "non"))
PY
)"
	lit() { printf '%s\n' "$RES" | sed -n "s/^$1=//p"; }
	for MODE in nuit jour; do
		ENVF="$BANC/th/$MODE/.config/lexos/terminal.env"
		BON=1
		for CLE in LEXOS_TERM_BG LEXOS_TERM_FG LEXOS_TERM_TEXTE LEXOS_TERM_CURSEUR; do
			ATT="$(sed -n "s/^$CLE=//p" "$ENVF")"
			[ -n "$ATT" ] && [ "$(lit "$MODE.$CLE")" = "$ATT" ] || BON=0
		done
		if [ "$BON" = 1 ]; then
			ok "$MODE : le pont extrait les quatre couleurs que le générateur écrit"
		else
			non "$MODE : le pont n'extrait pas ce que le générateur écrit"
		fi
	done
	#  Le fond de JOUR est le point qui comptait : la fenêtre restait noire.
	if [ "$(lit 'jour.LEXOS_TERM_BG')" = "$(sed -n 's/^LEXOS_TERM_BG=//p' "$BANC/th/jour/.config/lexos/terminal.env")" ] \
	   && [ "$(lit 'jour.LEXOS_TERM_BG')" != "$(lit 'nuit.LEXOS_TERM_BG')" ]; then
		ok "le fond de JOUR diffère de celui de nuit — la fenêtre ne peut plus rester noire"
	else
		non "le fond de jour et celui de nuit sont identiques : le thème ne traverse pas"
	fi
	case "$(lit 'hostile.cles')" in
		LEXOS_TERM_FG) ok "une valeur qui n'est pas une couleur est JETÉE (seul #00D700 survit)" ;;
		*) non "le pont a laissé passer autre chose qu'une couleur : « $(lit 'hostile.cles') »" ;;
	esac
	[ "$(lit 'absent.vide')" = oui ] \
		&& ok "sans fichier de thème, le pont rend vide — la page garde sa palette livrée" \
		|| non "sans fichier de thème, le pont ne rend pas vide"
fi

#  ET LA PAGE : elle demande, et elle applique. ON LIT LE CODE APRÈS AVOIR
#  RETIRÉ LES COMMENTAIRES — la page RACONTE qu'elle portait « #ff6a1a » et
#  « --braise » avant, et un contrôle naïf lirait son propre récit.
#  ⚠ ON CAPTURE, ON NE TUBE PAS DANS « grep -q ». Ce banc tourne sous
#  « set -o pipefail » (l.35) : « grep -q » rend la main au premier résultat,
#  le SIGPIPE tue le « sed » en amont, et le TUBE rend non-zéro alors que la
#  chaîne cherchée est bien là. Le dépôt a déjà payé ça une fois — c'est
#  écrit dans le message du commit qui l'a corrigé pour « lexos aide ».
#  Mesuré ici aussi : les quatre contrôles rougissaient sur une page juste.
PAGE_NUE="$(sed 's|//.*$||' "$PAGE")"
case "$PAGE_NUE" in
	*"/api/theme"*) ok "la page demande la palette au pont" ;;
	*) non "la page ne demande jamais /api/theme : elle garde sa palette à elle" ;;
esac
MANQUE=""
for V in '--noir' '--texte' '--orange' '--vert'; do
	case "$PAGE_NUE" in
		*"pose(\"$V\""*) ;;
		*) MANQUE="$MANQUE $V" ;;
	esac
done
if [ -z "$MANQUE" ]; then
	ok "les quatre variables de la page sont posées depuis le thème"
else
	non "la page n'applique pas le thème à :$MANQUE"
fi
case "$PAGE_NUE" in
	*braise*) non "« --braise » traîne encore — une couleur définie que personne n'emploie" ;;
	*) ok "« --braise » a disparu : plus de couleur définie et jamais employée" ;;
esac
case "$PAGE_NUE" in
	*'selectionBackground: "rgba('*) non "la sélection garde un orange écrit une seconde fois" ;;
	*) ok "la sélection suit --orange au lieu d'un orange réécrit" ;;
esac

titre "6. LES SEIZE COULEURS ANSI viennent du thème, et elles se lisent"
# =============================================================================
#  LE DÉFAUT QUE CE BLOC MESURE, ET IL ÉTAIT À MOI. Poser le fond de JOUR
#  sans poser la palette, c'était rendre la fenêtre illisible : le rouge, le
#  jaune, le bleu, le magenta, le cyan et le blanc restaient ceux de la NUIT
#  sur un fond crème. Onze des seize entrées tombaient sous le seuil AA —
#  jaune 1,51:1, blanc 1,70:1, cyan 1,66:1. Le blanc est le pire : c'est la
#  couleur des fichiers ordinaires de « ls ».
#
#  Les seize existaient déjà, par thème, dans le générateur — mais elles
#  n'allaient QUE dans xfce4-terminal. Deux écritures de la même palette, qui
#  avaient DÉJÀ divergé : la page appelait « jaune » une couleur à ΔE 55 de
#  celle que le système appelle jaune.
if [ ! -r "$PONT_PY" ] || [ ! -x "$GEN_TH" ] || [ ! -r "$PAGE" ]; then
	non "le pont, le générateur ou la page est introuvable : la palette n'est pas vérifiable"
else
	#  ═══ 1) LE FICHIER : SEIZE COULEURS, ET APOSTROPHÉES ═══
	#  L'absence d'apostrophes échoue EN SILENCE : bash lit « ; » comme un
	#  séparateur de commandes et « #B3261E… » comme un commentaire. La
	#  variable ne vaudrait qu'UNE couleur, sans un mot d'erreur. On ne lit
	#  donc pas la ligne : on la fait RELIRE PAR BASH, comme les vrais
	#  consommateurs le font.
	for MODE in nuit jour; do
		ENVP="$BANC/th/$MODE/.config/lexos/terminal.env"
		if [ ! -r "$ENVP" ]; then
			non "$MODE : terminal.env manque — la palette n'est pas vérifiable"
			continue
		fi
		N_PAL="$(env -i bash -c ". '$ENVP' 2>/dev/null; printf '%s\\n' \"\${LEXOS_TERM_PALETTE:-}\"" | awk -F';' '{print NF}')"
		case "$N_PAL" in
			16) ok "$MODE : bash relit SEIZE couleurs depuis terminal.env" ;;
			1)  non "$MODE : bash n'en relit qu'UNE — la ligne n'est pas apostrophée, le « ; » a tout coupé" ;;
			*)  non "$MODE : bash relit $N_PAL couleur(s) au lieu de seize" ;;
		esac
	done

	#  ═══ 2) LE PONT LA REND, ET LA MESURE TIENT SUR LES DEUX FONDS ═══
	RESP="$(PONT_PY="$PONT_PY" BANC="$BANC" python3 - <<'PY' 2>/dev/null
import importlib.util, os, tempfile
sp = importlib.util.spec_from_file_location("tp", os.environ["PONT_PY"])
tp = importlib.util.module_from_spec(sp); sp.loader.exec_module(tp)
banc = os.environ["BANC"]

def lum(h):
    v = [int(h[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]

def contraste(a, b):
    x, y = lum(a), lum(b)
    if x < y:
        x, y = y, x
    return (x+0.05)/(y+0.05)

for mode in ("nuit", "jour"):
    t = tp.lire_theme(os.path.join(banc, "th", mode, ".config", "lexos", "terminal.env"))
    pal = (t.get("LEXOS_TERM_PALETTE") or "").split(";") if t.get("LEXOS_TERM_PALETTE") else []
    print("%s.n=%d" % (mode, len(pal)))
    if len(pal) != 16:
        continue
    bg = t.get("LEXOS_TERM_BG", "#000000")
    #  Les index 0 et 8 sont les emplacements « fond » et « atténué » de la
    #  convention ANSI : on ne leur demande pas de contraste de texte.
    mesures = [(contraste(c, bg), i) for i, c in enumerate(pal) if i not in (0, 8)]
    pire, idx = min(mesures)
    print("%s.pire=%.2f" % (mode, pire))
    print("%s.pirecouleur=%s" % (mode, pal[idx]))
    print("%s.sous=%d" % (mode, sum(1 for k, _ in mesures if k < 4.5)))

#  Ce que le pont doit REFUSER. Une palette tronquée ou surdimensionnée est
#  jetée EN ENTIER plutôt qu'appliquée à moitié : sinon la page poserait
#  --ansi-0..2 et garderait les treize autres couleurs de l'autre thème.
d = tempfile.mkdtemp()
for nom, val in (("trois", ";".join(["#112233"]*3)),
                 ("quarante", ";".join(["#112233"]*40)),
                 ("injection", "#000;}body{background:url(http://x)"),
                 ("mixte", ";".join(["#112233"]*15) + ";rouge")):
    p = os.path.join(d, nom + ".env")
    open(p, "w").write("LEXOS_TERM_PALETTE='%s'\n" % val)
    print("refus.%s=%s" % (nom, "jetee" if "LEXOS_TERM_PALETTE" not in tp.lire_theme(p) else "ACCEPTEE"))
PY
)"
	litp() { printf '%s\n' "$RESP" | sed -n "s/^$1=//p"; }
	for MODE in nuit jour; do
		case "$(litp "$MODE.n")" in
			16) ok "$MODE : le pont rend les seize couleurs à la page" ;;
			*)  non "$MODE : le pont rend « $(litp "$MODE.n") » couleur(s) — la page garderait la sienne" ;;
		esac
		SOUS="$(litp "$MODE.sous")"; PIRE="$(litp "$MODE.pire")"; PC="$(litp "$MODE.pirecouleur")"
		if [ -z "$SOUS" ]; then
			non "$MODE : le contraste de la palette n'a pas pu être mesuré"
		elif [ "$SOUS" = 0 ]; then
			ok "$MODE : les quatorze couleurs de texte se lisent sur le fond — la plus basse est $PC à $PIRE:1"
		else
			non "$MODE : $SOUS couleur(s) sous le seuil AA, la pire étant $PC à $PIRE:1"
		fi
	done
	for CAS in trois quarante injection mixte; do
		case "$(litp "refus.$CAS")" in
			jetee) ok "une palette « $CAS » est JETÉE en entier" ;;
			*)     non "le pont a accepté une palette « $CAS » — la page serait à moitié thémée" ;;
		esac
	done

	#  ═══ 3) LA PAGE LES POSE ET LES LIT — LES SEIZE, PAS QUINZE ═══
	PAGE_P="$(sed 's|//.*$||' "$PAGE")"
	case "$PAGE_P" in
		*'pose("--ansi-"'*) ok "la page pose les couleurs ANSI du thème" ;;
		*) non "la page ne pose aucune couleur ANSI : poser le fond de jour la rendrait illisible" ;;
	esac
	ABSENT=""
	for I in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
		case "$PAGE_P" in
			*"--ansi-$I\""*) ;;
			*) ABSENT="$ABSENT $I" ;;
		esac
	done
	if [ -z "$ABSENT" ]; then
		ok "les seize emplacements ANSI lisent la palette du thème"
	else
		non "des emplacements ANSI ne lisent pas le thème :$ABSENT"
	fi

	#  ═══ 4) L'ENCRE DU CHROME EST FIGÉE, ET C'EST VOULU ═══
	#  Le même « pose » qui répare le fond avait cassé le chrome : --texte est
	#  devenu l'encre du THÈME, et trois règles de survol la posaient sur des
	#  fonds restés SOMBRES — 1,08:1 pour « #plus:hover », 1,19:1 pour la
	#  croix d'onglet. Mesuré. Le chrome garde ses fonds sombres par choix,
	#  donc son encre doit être figée aussi.
	MAL=""
	for R in '.onglet .x:hover' '#plus:hover' '.fen-outils button:hover'; do
		LIGNE="$(printf '%s\n' "$PAGE_P" | sed -n "s|^$R{\(.*\)}$|\1|p" | head -1)"
		case "$LIGNE" in
			*'var(--texte)'*) MAL="$MAL « $R »" ;;
		esac
	done
	if [ -z "$MAL" ]; then
		ok "les survols du chrome prennent une encre figée, pas celle du thème"
	else
		non "des survols du chrome gardent l'encre du thème sur un fond sombre :$MAL"
	fi
	case "$PAGE_P" in
		*'pose("--encre-chrome"'*) non "« --encre-chrome » est posé depuis le thème — elle doit rester figée" ;;
		*'--encre-chrome'*) ok "« --encre-chrome » existe et n'est jamais posée depuis le thème" ;;
		*) non "« --encre-chrome » n'existe pas : l'encre du chrome suit encore le thème" ;;
	esac
	#  ET L'ACCENT ET LE VERT NON PLUS NE TRAVERSENT PAS LE CHROME. Posés
	#  depuis le thème, ils valent #A84007 et #0B6B3A en mode clair — faits
	#  pour un fond crème, donc 3,24:1 et 3,03:1 sur le chrome resté sombre.
	#  « var(--orange) » et « var(--vert) » n'ont donc plus rien à faire dans
	#  la feuille de style : la palette xterm.js, elle, les lit par
	#  « v("--orange") », une autre écriture — le contrôle les distingue.
	FUITE=""
	case "$PAGE_P" in *'var(--orange)'*) FUITE="$FUITE --orange" ;; esac
	case "$PAGE_P" in *'var(--vert)'*)   FUITE="$FUITE --vert" ;; esac
	if [ -z "$FUITE" ]; then
		ok "l'accent et le vert du thème ne peignent plus le chrome figé"
	else
		non "le chrome peint encore avec une couleur du thème :$FUITE — sous AA en mode clair"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
