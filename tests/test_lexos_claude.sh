#!/usr/bin/env bash
# =============================================================================
#  Éprouver la bannière du vrai Claude Terminal — prenom() et banniere()
# =============================================================================
#  ALEX, en comparant le vrai Claude Terminal (ISO) à la démo web : « claude
#  terminal ouvre pas comme je voyait sur vercel — 3e image, c'est ça qu'il
#  veut voir au début d'une session ». La démo (web-demo/index.html,
#  cctAccueilSession) affiche un mot-sigle « CLAUDE CODE » et « Bonjour,
#  Alex » avant la conversation. Sur le vrai ISO, « claude » (exec) prend
#  tout de suite la main sur l'écran et dessine sa PROPRE interface —
#  impossible d'ajouter quoi que ce soit PENDANT cet écran-là. Ce qui reste
#  possible : imprimer le même mot-sigle JUSTE AVANT de lui céder l'écran.
#
#  LE PIÈGE ÉVITÉ ICI : la démo peut se permettre « Bonjour, Alex » en dur
#  (une page taillée pour lui) — mais lexos-claude est embarqué dans l'ISO,
#  donc dans la machine de QUICONQUE installe LexOS. Écrire « Alex » en dur
#  dans ce fichier-là marcherait par coïncidence pour Alex et serait faux
#  pour tout le monde d'autre. Le prénom doit venir du vrai mécanisme
#  d'identité de LexOS (le champ GECOS que pose « lexos utilisateurs
#  nom-complet »), avec un repli sur le nom du compte si personne ne l'a
#  réglé — jamais un nom écrit en dur dans le script.
#
#  POURQUOI CE BANC EXTRAIT LES FONCTIONS PLUTÔT QUE DE SOURCER LE FICHIER.
#  lexos-claude se termine par un aiguillage (« case "$CMD" in ... ») qui
#  s'exécute sans condition — le sourcer tel quel lancerait cmd_run(),
#  install_claude() ou pire, un vrai « exec claude ». On extrait donc
#  seulement le bloc de couleurs + prenom() + banniere() (les deux points
#  d'injection utiles ici) entre deux repères stables du fichier, et on leur
#  fournit un PATH truqué (getent, id, date) — jamais le vrai système.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/usr/bin/lexos-claude"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

mkdir -p "$BAC/bin"
awk '/^if \[\[ -t 1 \]\] && \[\[ "\$\{NO_COLOR/,/^usage\(\) \{/' "$SCRIPT" \
	| sed '$d' > "$BAC/fonctions.sh"
grep -q 'prenom()' "$BAC/fonctions.sh" || { echo "extraction ratée : prenom() absente du bloc"; exit 1; }
grep -q 'banniere()' "$BAC/fonctions.sh" || { echo "extraction ratée : banniere() absente du bloc"; exit 1; }

#  getent/id truqués : un compte « lex » dont le nom complet (GECOS) est
#  réglé sur « Alex Marceau-Prevost » — exactement le champ que pose
#  « lexos utilisateurs nom-complet ».
cat > "$BAC/bin/getent" <<'EOF'
#!/bin/sh
if [ "$1" = "passwd" ] && [ "$2" = "lex" ]; then
	echo "lex:x:1000:1000:${GECOS_TEST:-Alex Marceau-Prevost,,,}:/home/lex:/bin/bash"
fi
EOF
cat > "$BAC/bin/id" <<'EOF'
#!/bin/sh
[ "$1" = "-un" ] && echo "lex"
EOF
cat > "$BAC/bin/date" <<'EOF'
#!/bin/sh
echo "${MOCK_HOUR:-12}"
EOF
chmod +x "$BAC"/bin/*

appelle() { # appelle <fonction-et-arguments...> — avec le PATH truqué en tête
	PATH="$BAC/bin:$PATH" bash -c "source '$BAC/fonctions.sh'; $*"
}

# =============================================================================
titre "1. prenom() — le vrai mécanisme d'identité, jamais un nom en dur"
# =============================================================================
#  GARDE-FOU STRUCTUREL : si quelqu'un « simplifie » un jour en écrivant
#  Alex directement (comme la démo se le permet), ce test doit le voir.
#  Les LIGNES DE COMMENTAIRE sont exclues : ce fichier explique justement,
#  en commentaire, pourquoi il NE fait PAS ce que la démo fait — le mot
#  « Alex » y figure donc légitimement en prose, jamais dans du code exécuté.
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -qE '"Alex"|, Alex'; then
	non "lexos-claude exécute du code contenant « Alex » en dur — faux pour qui n'est pas Alex"
else
	ok "aucun prénom écrit en dur dans le code de lexos-claude (contrairement à la démo, c'est un fichier de tout le monde)"
fi

SORTIE="$(GECOS_TEST='Alex Marceau-Prevost,,,' appelle prenom)"
if [ "$SORTIE" = "Alex" ]; then
	ok "le prénom est extrait du champ GECOS (« Alex Marceau-Prevost » -> « Alex »)"
else
	non "prenom() aurait dû rendre « Alex », a rendu : « $SORTIE »"
fi

SORTIE="$(GECOS_TEST='Marie-Claude Tremblay,,,' appelle prenom)"
if [ "$SORTIE" = "Marie-Claude" ]; then
	ok "un prénom composé (avec trait d'union) reste entier — seul l'ESPACE sépare prénom et nom"
else
	non "prenom() aurait dû rendre « Marie-Claude », a rendu : « $SORTIE »"
fi

# =============================================================================
titre "2. prenom() — repli sur le nom du compte si aucun nom complet n'est réglé"
# =============================================================================
SORTIE="$(GECOS_TEST=',,,' appelle prenom)"
if [ "$SORTIE" = "Lex" ]; then
	ok "sans nom complet (GECOS vide), repli sur le nom du compte, une majuscule (« lex » -> « Lex »)"
else
	non "le repli aurait dû rendre « Lex », a rendu : « $SORTIE »"
fi

# =============================================================================
titre "3. banniere() — l'heure décide comme dans la démo (cctAccueilSession)"
# =============================================================================
#  MÊME RÈGLE QUE LA DÉMO, MOT POUR MOT : (h >= 18 || h < 5) -> Bonsoir,
#  sinon Bonjour. Les deux bornes (5 et 18) sont les cas qui cassent le
#  premier si une des deux inégalités devient « > » ou « <= » par erreur.
for cas in "0:Bonsoir" "4:Bonsoir" "5:Bonjour" "13:Bonjour" "17:Bonjour" "18:Bonsoir" "23:Bonsoir"; do
	h="${cas%%:*}"; attendu="${cas##*:}"
	SORTIE="$(MOCK_HOUR="$h" appelle banniere)"
	if printf '%s' "$SORTIE" | grep -q "$attendu"; then
		ok "${h} h -> ${attendu}"
	else
		non "${h} h aurait dû dire « ${attendu} », sortie : $SORTIE"
	fi
done

# =============================================================================
titre "4. banniere() — le mot-sigle ET l'information essentielle, tous les deux"
# =============================================================================
SORTIE="$(MOCK_HOUR=12 appelle banniere)"
for attendu in "CLAUDE" "CODE" "Connexion au navigateur au premier lancement."; do
	if printf '%s' "$SORTIE" | grep -qF "$attendu"; then
		ok "la bannière contient « $attendu »"
	else
		non "la bannière ne contient pas « $attendu » — sortie : $SORTIE"
	fi
done

# =============================================================================
titre "5. cmd_run — la bannière est un décor, jamais au prix de l'information"
# =============================================================================
#  Sur une sortie qui n'est pas un vrai terminal (script, pipe, NO_COLOR),
#  cmd_run doit garder le message original — pas juste sauter la bannière
#  ET l'information avec elle.
#  « navigateur au premier lancement » : le bout de phrase COMMUN aux deux
#  branches — la casse du C initial diffère (une phrase à elle seule dans
#  banniere(), la suite de « Claude Code — » dans le repli say()), ce n'est
#  pas ce qu'on éprouve ici.
if grep -A6 'if \[\[ -t 1 \]\] && \[\[ "\${NO_COLOR:-}" == "" \]\]; then' "$SCRIPT" \
	| grep -q 'banniere' \
	&& grep -A8 'if \[\[ -t 1 \]\] && \[\[ "\${NO_COLOR:-}" == "" \]\]; then' "$SCRIPT" \
	| grep -q 'navigateur au premier lancement'; then
	ok "cmd_run affiche banniere() sur un vrai terminal, et le message brut sinon"
else
	non "cmd_run ne semble plus garder le message informatif dans les deux cas"
fi

# =============================================================================
titre "6. Le thème rouge sur fond noir, écriture blanche"
# =============================================================================
#  ALEX, sur l'ISO déjà construite : « je veux il est un theme rouge dans
#  ios dans un fond bien noir et une belle ecriture blanc ». Le fond est
#  --color-bg dans lexos-claude-terminal (déjà noir) ; xfce4-terminal
#  n'offre AUCUN troisième réglage de couleur par fenêtre (vérifié dans son
#  manuel — seuls --color-bg et --color-text existent), donc le rouge ne
#  peut vivre que dans ce que ce script imprime lui-même : le mot-sigle.
#
#  UN VRAI TERMINAL, PAS UNE SORTIE EN TUBE. « [[ -t 1 ]] » répond faux dès
#  que la sortie de banniere() est capturée par une simple substitution de
#  commande — un banc naïf « verrait » toujours des couleurs vides et ne
#  prouverait rien. « script » alloue un vrai pseudo-terminal : c'est la
#  seule façon d'éprouver le VRAI chemin (couleurs allumées), pas son repli.
if command -v script >/dev/null 2>&1; then
	#  « bash -c » À L'INTÉRIEUR DE script, ET CE N'EST PAS UNE CEINTURE DE
	#  PLUS. « script -qec » lance ce qu'on lui donne avec $SHELL, et à défaut
	#  avec /bin/sh — qui est dash sur Debian. Or « source » est un bashisme :
	#  sous dash, ça donne « source: not found », la bannière sort VIDE, et
	#  les trois contrôles qui suivent accusent lexos-claude d'avoir perdu ses
	#  couleurs alors que son code est intact.
	#
	#  Le piège est qu'il ne se voit PAS partout : là où $SHELL vaut déjà
	#  /bin/bash (une session interactive, la machine d'Alex), le banc passe
	#  au vert et ne prouve rien de plus. Il rougit dès que $SHELL manque ou
	#  vaut dash — un cron, un service, un coureur d'intégration, un compte
	#  dont le shell de connexion n'est pas bash. Un banc ne doit pas
	#  dépendre du shell ambiant : il exige celui dont il a besoin.
	#
	#  appelle() ligne 69 le faisait déjà correctement ; cette capture-ci
	#  l'avait oublié.
	SORTIE="$(PATH="$BAC/bin:$PATH" script -qec "bash -c \"
		source '$BAC/fonctions.sh'
		banniere
	\"" /dev/null 2>/dev/null | tr -d '\r')"

	#  #D8352E — pas un rouge inventé : c'est ACCENT_HI du cas « rouge » dans
	#  lexos-theme-gen, le même accent que le reste de LexOS. En 24 bits
	#  littéral (216;53;46), pas les 256 couleurs approchées.
	if printf '%s' "$SORTIE" | grep -qF $'\033[38;2;216;53;46m'; then
		ok "le mot-sigle et le salut portent le VRAI rouge de LexOS (#D8352E), pas une couleur inventée"
	else
		non "le rouge #D8352E (38;2;216;53;46) n'apparaît pas dans la bannière"
	fi
	if printf '%s' "$SORTIE" | grep -qF $'\033[38;2;255;255;255m'; then
		ok "le texte d'accompagnement est en BLANC franc (255;255;255), plus atténué"
	else
		non "le blanc franc (38;2;255;255;255) n'apparaît pas dans la bannière"
	fi
	if printf '%s' "$SORTIE" | grep -q 'CLAUDE'; then
		ok "…et le mot-sigle est toujours là, la couleur n'a pas mangé le texte"
	else
		non "le mot-sigle a disparu avec le changement de couleur"
	fi
else
	non "« script » (util-linux) est absent — impossible d'éprouver les vraies couleurs sur un pseudo-terminal"
fi

grep -q "color-bg='#000000'" "$RACINE/config/includes.chroot/usr/bin/lexos-claude-terminal" \
	&& ok "lexos-claude-terminal : le fond reste noir franc" \
	|| non "le fond de lexos-claude-terminal n'est plus #000000"
grep -q "color-text='#FFFFFF'" "$RACINE/config/includes.chroot/usr/bin/lexos-claude-terminal" \
	&& ok "lexos-claude-terminal : l'écriture est BLANCHE (« une belle ecriture blanc »)" \
	|| non "l'écriture de lexos-claude-terminal n'est plus #FFFFFF"

# =============================================================================
titre "L'icône de Claude Terminal — elle ne doit plus être celle de Claude"
# =============================================================================
#  ALEX, PHOTO DU DOCK : deux étoiles identiques, côte à côte. Les DEUX
#  lanceurs portaient « Icon=lexos-claude ». Rien ne disait lequel ouvrait
#  l'application claude.ai et lequel ouvrait le terminal.
#
#  Puis, photo de l'icône du Terminal : « pour le [terminal], même logo que
#  celui-là s'il vous plaît » — et, juste avant : « le logo Claude Terminal
#  le mettre ROUGE ».
HOOK="$RACINE/config/hooks/normal/0420-lexos-claude.hook.chroot"
SVG_CT="$RACINE/branding/claude-terminal-icon.svg"
SVG_T="$RACINE/branding/icon-terminal.svg"
SVG_CL="$RACINE/branding/claude-icon.svg"
BANC_IC="$(mktemp -d)"
trap 'rm -rf "$BANC_IC"' EXIT

#  LE CŒUR : les deux lanceurs ne partagent plus leur icône. On lit les
#  blocs .desktop du hook, pas des commentaires : « Icon= » en début de
#  ligne, dans le heredoc qui suit chaque « Exec= ».
IC_TERM="$(sed -n '/^Exec=lexos-claude-terminal$/,/^EOF$/s/^Icon=//p' "$HOOK")"
IC_APP="$(sed -n '/^Exec=lexos claude app$/,/^EOF$/s/^Icon=//p' "$HOOK")"
if [ -z "$IC_TERM" ] || [ -z "$IC_APP" ]; then
	non "impossible de relire les deux lignes Icon= des lanceurs ($IC_TERM / $IC_APP)"
elif [ "$IC_TERM" = "$IC_APP" ]; then
	non "les deux lanceurs portent encore la MÊME icône ($IC_TERM) — c'est la photo d'Alex"
else
	ok "Claude Terminal ($IC_TERM) et Claude ($IC_APP) ont des icônes différentes"
fi

#  ET LA FENÊTRE SUIT LE LANCEUR. Sans ce contrôle, la barre des tâches
#  garderait l'ancienne icône : le lanceur corrigé, la fenêtre non — le
#  correctif à moitié, le défaut le plus répété de ce dépôt.
IC_FEN="$(sed -n "s/^[[:space:]]*--icon=\([a-z-]*\) .*/\1/p" \
	"$RACINE/config/includes.chroot/usr/bin/lexos-claude-terminal" | head -1)"
[ -n "$IC_FEN" ] && [ "$IC_FEN" = "$IC_TERM" ] \
	&& ok "la fenêtre porte la même icône que le lanceur ($IC_FEN)" \
	|| non "la fenêtre porte « $IC_FEN » et le lanceur « $IC_TERM » — la barre des tâches montrerait l'ancienne"

#  Le hook doit vraiment POSER cette icône, sinon « Icon= » désigne un nom
#  qui n'existe pas et GTK retombe sur une icône générique.
if grep -q "claude-terminal-icon:${IC_TERM}" "$HOOK"; then
	ok "le hook 0420 rend bien claude-terminal-icon.svg sous le nom « $IC_TERM »"
else
	non "le hook ne pose aucune icône nommée « $IC_TERM » — le lanceur pointerait dans le vide"
fi

if [ ! -r "$SVG_CT" ]; then
	non "branding/claude-terminal-icon.svg est absent"
else
	#  « LOGO OFFICIEL DE CLAUDE MAIS EN ROUGE » : le tracé doit être celui
	#  d'Anthropic, à l'identique. On compare les DEUX tracés, pas les
	#  fichiers — ils n'ont pas les mêmes explications en tête, et pas la
	#  même couleur, ce qui est justement le but.
	#
	#  (Première lecture, corrigée par Alex : j'avais compris « le dessin du
	#  Terminal, en rouge ». C'est l'ÉTOILE qu'il voulait. Le contrôle porte
	#  donc sur claude-icon.svg, pas sur icon-terminal.svg.)
	trace_de() { grep -oE '<path d="M52\.4285[^"]*"' "$1"; }
	if [ -n "$(trace_de "$SVG_CT")" ] && [ "$(trace_de "$SVG_CT")" = "$(trace_de "$SVG_CL")" ]; then
		ok "c'est le tracé OFFICIEL de Claude, au caractère près"
	else
		non "le tracé n'est pas celui de claude-icon.svg — « logo officiel de Claude »"
	fi

	#  LE ROUGE EST CELUI DE LexOS, PAS UN ROUGE INVENTÉ. #E5484D est DANGER
	#  dans lexos-theme-gen : celui de la pastille de fermeture et des
	#  icônes « arrêter » / « redémarrer ».
	GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
	ROUGE="$(sed -n 's/^DANGER="\(#[0-9A-Fa-f]*\)"$/\1/p' "$GEN" | head -1)"
	#  PAS D'ANCRE « $ » ICI : la ligne se termine par « #E5484D"/> », donc un
	#  motif ancré en fin de ligne n'accroche rien et le contrôle se plaint
	#  d'une couleur VIDE alors qu'elle est là. On prend la dernière
	#  occurrence de la ligne du tracé, ce qui est la couleur du remplissage.
	ETOILE="$(grep -oE 'M52\.4285.*fill="#[0-9A-Fa-f]{6}"' "$SVG_CT" | grep -oE '#[0-9A-Fa-f]{6}' | tail -1)"
	if [ -n "$ROUGE" ] && [ "$ETOILE" = "$ROUGE" ]; then
		ok "l'étoile est le rouge de LexOS ($ROUGE), celui de lexos-theme-gen"
	else
		non "l'étoile vaut $ETOILE ; le rouge de LexOS est $ROUGE"
	fi

	#  ET LE FOND EST NOIR — « bien noir avec un tit tin de gris autour ».
	#  Le crème de l'application Claude ici rendrait les deux icônes
	#  presque identiques dans le dock, à la teinte du trait près.
	FOND="$(grep -m1 '<rect width="256" height="256"' "$SVG_CT" | grep -oE '#[0-9A-Fa-f]{6}')"
	case "$FOND" in
		'#0B0B0C'|'#000000') ok "le fond est le noir de LexOS ($FOND), pas le crème de Claude" ;;
		*) non "le fond vaut $FOND — Alex demandait « bien noir »" ;;
	esac
	if grep -q 'stroke-opacity="0.18"' "$SVG_CT"; then
		ok "…avec le liseré discret autour (« un tit tin de gris »)"
	else
		non "le liseré autour de l'icône a disparu"
	fi

	#  ET IL NE DOIT PAS SUIVRE L'ACCENT. #E8590C est un JETON que
	#  lexos-theme-gen remplace par l'accent courant. Si le rouge en était
	#  un, « lexos accent rouge » rendrait les deux icônes identiques et on
	#  serait revenu au problème du départ.
	#  ON LIT LE TRACÉ, PAS LES COMMENTAIRES. Le fichier EXPLIQUE en tête
	#  pourquoi il n'emploie pas de jeton d'accent — un banc naïf lirait
	#  cette explication et se déclarerait en échec. Ce dépôt s'est déjà
	#  fait prendre quatre fois à cette faute.
	if perl -0777 -pe 's/<!--.*?-->//gs' "$SVG_CT" | grep -qE '#(E8590C|FF7A33|A84007)'; then
		non "le fichier contient un jeton d'accent : la couleur changerait avec le thème"
	else
		ok "aucun jeton d'accent : le rouge reste rouge quel que soit le thème"
	fi

	#  ═══ ET LE MIROIR : LE TERMINAL, LUI, NE DOIT PAS AVOIR BOUGÉ ═══
	#  ALEX, APRÈS COUP : « garder le terminal pareil à l'image de la démo
	#  Vercel, avec son orange. » Donner son icône à Claude Terminal ne
	#  devait rien changer au Terminal — et c'est exactement le genre de
	#  dégât qu'on ne voit qu'une ISO plus tard.
	#
	#  Les deux contrôles vont par paire, et c'est voulu : le Claude Terminal
	#  ne doit PAS suivre l'accent (sinon « lexos accent rouge » rendrait les
	#  deux icônes identiques), le Terminal DOIT le suivre.
	if perl -0777 -pe 's/<!--.*?-->//gs' "$SVG_T" | grep -q '#E8590C'; then
		ok "le Terminal garde son jeton d'accent — il reste orange, et suit le thème"
	else
		non "le Terminal n'a plus de jeton d'accent : son orange ne suivrait plus le thème"
	fi

	#  ET IL EST TOUJOURS LE MÊME DESSIN QUE LA DÉMO. La comparaison est
	#  NUMÉRIQUE, pas textuelle : la démo écrit « .12 » là où le SVG écrit
	#  « 0.12 ». Le même nombre, deux écritures — un banc qui comparerait les
	#  chaînes crierait au loup sur une différence qui n'existe pas.
	DEMO="$RACINE/web-demo/index.html"
	if [ -r "$DEMO" ] && command -v python3 >/dev/null 2>&1; then
		VERDICT_IC="$(python3 - "$RACINE/branding/icon-terminal.svg" "$DEMO" <<'PY'
import re, sys
svg = re.sub(r"<!--.*?-->", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
demo = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"function terminalGlyph\(size\)\{(.*?)\n\}", demo, re.S)
if not m:
    print("PAS-DE-GLYPHE"); sys.exit()
def formes(t):
    out = []
    for f in re.finditer(r"<(rect|path)([^>]*?)/?>", t):
        at = dict(re.findall(r'([a-z-]+)="([^"]*)"', f.group(2)))
        for k in ("class", "aria-hidden", "width", "height", "viewBox"):
            at.pop(k, None)
        #  L'accent s'écrit « #E8590C » dans le SVG et « var(--ac) » dans la
        #  démo : c'est la MÊME couleur, dite dans deux langues.
        if at.get("fill") in ("#E8590C", "var(--ac)"):
            at["fill"] = "ACCENT"
        #  « .12 » et « 0.12 » sont le même nombre.
        for k, v in list(at.items()):
            try: at[k] = "%g" % float(v)
            except ValueError: pass
        out.append((f.group(1), tuple(sorted(at.items()))))
    return out
print("PAREIL" if formes(svg) == formes(m.group(1)) else "DIFFERENT")
PY
)"
		case "$VERDICT_IC" in
			PAREIL) ok "l'icône du Terminal est le MÊME dessin que celui de la démo" ;;
			PAS-DE-GLYPHE) non "terminalGlyph() est introuvable dans la démo" ;;
			*) non "l'icône du Terminal a divergé de celle de la démo" ;;
		esac
	fi

	#  LES HUIT TAILLES, RENDUES POUR DE VRAI. 16, 22 et 24 ont déjà manqué
	#  deux fois dans ce dépôt : aux tailles absentes le dock agrandit la
	#  version vectorielle, et le dessin change sous la souris.
	if command -v rsvg-convert >/dev/null 2>&1; then
		MANQUE=""
		for T in 16 22 24 32 48 64 128 256; do
			rsvg-convert -w "$T" -h "$T" "$SVG_CT" -o "$BANC_IC/$T.png" 2>/dev/null \
				|| MANQUE="$MANQUE $T"
			[ -s "$BANC_IC/$T.png" ] || MANQUE="$MANQUE $T"
		done
		[ -z "$MANQUE" ] \
			&& ok "les huit tailles se rendent (16 à 256), aucune ne retombe sur le vectoriel" \
			|| non "tailles qui ne se rendent pas :$MANQUE"

		#  ET LE ROUGE EST VRAIMENT À L'ÉCRAN — pas seulement dans le texte
		#  du fichier. On relit les pixels du cadre à 128 px.
		if [ -s "$BANC_IC/128.png" ] && python3 -c "import PIL" 2>/dev/null; then
			VU="$(python3 - "$BANC_IC/128.png" <<'PY'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGBA")
#  Le CENTRE de l'étoile : c'est là que tous les rayons convergent, donc le
#  seul point dont on sait qu'il est peint quelle que soit la taille rendue.
#  Un point pris sur un rayon tomberait à côté au moindre décalage.
print("#%02X%02X%02X" % im.getpixel((64, 64))[:3])
PY
)"
			[ "$VU" = "$ROUGE" ] \
				&& ok "au rendu, l'étoile est bien $VU — mesuré sur les pixels" \
				|| non "au rendu l'étoile vaut $VU et non $ROUGE"
		else
			printf '  \033[33m—\033[0m  Pillow absent : la couleur RENDUE n'"'"'a pas été mesurée\n'
		fi
	else
		printf '  \033[33m—\033[0m  rsvg-convert absent : les huit tailles n'"'"'ont PAS été rendues\n'
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
