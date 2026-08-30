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
	SORTIE="$(PATH="$BAC/bin:$PATH" script -qec "
		source '$BAC/fonctions.sh'
		banniere
	" /dev/null 2>/dev/null | tr -d '\r')"

	#  #D8352E — pas un rouge inventé : « rouge_hi » dans ACCENTS de
	#  fond-anime.py, le même accent que le reste de LexOS. En 24 bits
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

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
