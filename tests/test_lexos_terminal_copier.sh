#!/usr/bin/env bash
# =============================================================================
#  LexOS Pro Terminal — le copier-coller
# =============================================================================
#  ALEX : « le copier-coller ne fonctionne pas ». DEUX causes distinctes, et
#  c'est ce qui rendait la panne difficile à lire : corriger l'une seule
#  aurait laissé le symptôme presque entier.
#
#  CAUSE 1 — Ctrl+C ÉTAIT AVALÉ. Le gestionnaire de touches ne regardait que
#  la sélection DANS LE CHAMP DE SAISIE (« !this.champ.selectionEnd »). Quand
#  on sélectionne du texte dans la SORTIE — le cas normal, on veut copier le
#  résultat d'une commande — la condition restait vraie, preventDefault()
#  s'exécutait, et on obtenait « ^C » à la place du texte dans le
#  presse-papier. Le test était faux même pour le champ : selectionEnd vaut 0
#  quand le curseur est au DÉBUT sans rien sélectionner.
#
#  CAUSE 2 — QtWebEngine INTERDIT LE PRESSE-PAPIER PAR DÉFAUT. Tant que
#  JavascriptCanAccessClipboard et JavascriptCanPaste ne sont pas posés, la
#  page ne peut ni écrire ni lire, quoi qu'elle tente.
#
#  ═══ CE QUE CE BANC NE PEUT PAS FAIRE, ET CE QU'IL FAIT À LA PLACE ═══
#  Il ne peut pas ouvrir une vraie fenêtre QtWebEngine ni presser Ctrl+C :
#  la machine de construction n'a ni écran ni PySide6. Il éprouve donc les
#  DEUX conditions nécessaires — les réglages posés au bon endroit et sous
#  filet, la condition de touche corrigée — et il exécute pour de vrai la
#  logique de sélection extraite du fichier, sur les cas qui ont produit la
#  panne.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web/index.html"
PY="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$HTML" "$PY"; do
	if [ ! -r "$F" ]; then
		non "fichier introuvable : $F"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
		exit 1
	fi
done

# =============================================================================
titre "1. QtWebEngine a le droit d'écrire ET de lire le presse-papier"
# =============================================================================
#  LES DEUX, SÉPARÉMENT. JavascriptCanAccessClipboard autorise l'ÉCRITURE
#  (copier), JavascriptCanPaste la LECTURE (coller). N'en poser qu'un donne
#  un copier-coller à moitié réparé — plus long à diagnostiquer qu'une panne
#  franche, parce que le symptôme devient « ça marche des fois ».
#  ═══ ON CHERCHE LA FORME COMPLÈTE, ET C'EST UNE LEÇON PAYÉE ICI ═══
#  Une première version cherchait « JavascriptCanPaste » tout court. Le nom
#  apparaît AUSSI dans le commentaire qui explique le réglage, quelques
#  lignes plus haut : le banc trouvait le commentaire et croyait avoir trouvé
#  le code. Pire, le repérage par numéro de ligne s'en servait ensuite pour
#  situer le try/except — et se trompait de bloc. On exige donc la forme
#  qualifiée « QWebEngineSettings.WebAttribute.… », qui n'existe que dans
#  l'appel réel.
CODE_COPIE='QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard'
CODE_COLLE='QWebEngineSettings.WebAttribute.JavascriptCanPaste'
if grep -q "$CODE_COPIE" "$PY"; then
	ok "JavascriptCanAccessClipboard est posé — la page peut COPIER"
else
	non "JavascriptCanAccessClipboard absent : la copie restera impossible"
fi
if grep -q "$CODE_COLLE" "$PY"; then
	ok "JavascriptCanPaste est posé — la page peut COLLER"
else
	non "JavascriptCanPaste absent : le collage restera impossible"
fi

#  ═══ AVANT LE CHARGEMENT, PAS APRÈS ═══
#  Un réglage posé après vue.load() peut ne pas s'appliquer à la page déjà
#  en cours : le terminal s'ouvrirait avec les anciens droits, et le
#  correctif ne se verrait qu'au deuxième lancement — ou jamais.
L_REGL="$(grep -n "$CODE_COPIE" "$PY" | head -1 | cut -d: -f1)"
L_LOAD="$(grep -n 'vue.load(' "$PY" | head -1 | cut -d: -f1)"
if [ -n "$L_REGL" ] && [ -n "$L_LOAD" ] && [ "$L_REGL" -lt "$L_LOAD" ]; then
	ok "les réglages sont posés AVANT vue.load() (ligne $L_REGL < $L_LOAD)"
else
	non "les réglages arrivent après le chargement (réglages=$L_REGL load=$L_LOAD) : la page garderait les anciens droits"
fi

#  ═══ L'ASSERTION LA PLUS IMPORTANTE DU BANC ═══
#  Si une version de PySide6 renomme ou déplace ces attributs, la fenêtre
#  doit s'ouvrir QUAND MÊME, sans presse-papier. Un presse-papier absent est
#  un désagrément ; un TERMINAL qui refuse de s'ouvrir laisse un système où
#  Alex ne peut plus rien lancer du tout. C'est la règle écrite en tête du
#  lanceur, et c'est celle-ci qu'il faut tenir.
#
#  On ne se contente pas de « il y a un try quelque part » : on vérifie que
#  le try OUVRE avant les réglages et que le except ferme après.
L_PASTE="$(grep -n "$CODE_COLLE" "$PY" | head -1 | cut -d: -f1)"
#  Le dernier « try: » AVANT l'appel, et le premier « except » APRÈS : c'est
#  celui-là qui enveloppe les réglages, et pas un autre bloc du fichier.
BLOC="$(awk -v n="${L_REGL:-0}" 'NR<n && /^    try:/{d=NR} END{print d}' "$PY")"
EXC="$(awk -v n="${L_PASTE:-0}" 'NR>n && /^    except /{print NR; exit}' "$PY")"
if [ -n "$BLOC" ] && [ -n "$EXC" ] && [ -n "$L_PASTE" ] \
   && [ "$BLOC" -lt "$L_REGL" ] && [ "$EXC" -gt "$L_PASTE" ]; then
	ok "les réglages sont sous try/except (try l.$BLOC, except l.$EXC) — le terminal s'ouvre même si PySide6 change"
else
	non "les réglages ne sont pas protégés : un PySide6 qui renomme un attribut empêcherait le terminal de s'ouvrir"
fi

#  ET L'ÉCHEC SE DIT. Un except muet, c'est un presse-papier qui disparaît
#  sans que rien ne l'explique.
if awk -v d="${EXC:-0}" 'NR>=d && NR<=d+3' "$PY" | grep -q 'presse-papier non activé'; then
	ok "un échec d'activation est journalisé, pas avalé"
else
	non "l'except est muet : le presse-papier disparaîtrait sans un mot"
fi

if command -v python3 >/dev/null 2>&1; then
	if python3 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read(), sys.argv[1])" "$PY" 2>/dev/null; then
		ok "terminal-pro.py reste un Python valide"
	else
		non "terminal-pro.py ne se compile plus"
	fi
else
	saut "python3 absent : la syntaxe du lanceur n'a PAS été vérifiée"
fi

# =============================================================================
titre "2. Ctrl+C ne mange plus la copie"
# =============================================================================
if grep -q '!this.champ.selectionEnd' "$HTML"; then
	non "« !this.champ.selectionEnd » est encore là : la copie serait toujours avalée"
else
	ok "l'ancienne condition « !this.champ.selectionEnd » a disparu"
fi

if grep -q 'window.getSelection()' "$HTML"; then
	ok "la sélection de la PAGE est consultée, pas seulement celle du champ"
else
	non "window.getSelection() n'est pas consulté : sélectionner dans la sortie ne changerait rien"
fi

#  ═══ LE COMPORTEMENT « ANNULER LA LIGNE » DOIT SURVIVRE ═══
#  C'est un terminal : Ctrl+C sans sélection DOIT interrompre. Un correctif
#  qui aurait simplement supprimé la branche aurait « réparé » la copie en
#  cassant l'interruption — et personne ne s'en serait aperçu avant d'avoir
#  besoin d'arrêter quelque chose.
#  ON CHERCHE LA FORME DU CODE, PAS LE SIGNE. Une première version greppait
#  « ^C » dans tout le fichier : le motif survit dans les COMMENTAIRES qui
#  expliquent le correctif, et une mutation qui effaçait le vrai « ^C »
#  restait verte. C'est la troisième fois dans ce chantier qu'un contrôle
#  lit un commentaire en croyant lire du code — on exige donc la balise
#  complète, qui n'existe que dans la branche qui l'écrit.
if grep -qF '<span class="r">^C</span>' "$HTML"; then
	ok "l'annulation de ligne (« ^C ») existe toujours"
else
	non "le « ^C » a disparu : Ctrl+C n'interromprait plus rien"
fi

#  ═══ ET ON EXÉCUTE LA LOGIQUE, ON NE LA LIT PAS ═══
#  Un grep dit que la fonction est là ; il ne dit pas qu'elle répond juste.
#  On extrait aSelection() du fichier et on la fait tourner sur les quatre
#  cas qui comptent — dont celui qui a produit la panne (sélection dans la
#  sortie) et celui où l'ancienne condition se trompait déjà (curseur au
#  début du champ).
if ! command -v node >/dev/null 2>&1; then
	saut "node absent : la logique de sélection n'a PAS été exécutée"
else
	CORPS="$(awk '/^  aSelection\(\)\{/{d=1} d{print} d&&/^  \}$/{exit}' "$HTML")"
	if [ -z "$CORPS" ]; then
		non "aSelection() introuvable dans le fichier — rien à exécuter"
	else
		{
			printf 'class T {\n'
			printf '  constructor(sel, champ){ this._sel = sel; this.champ = champ; }\n'
			printf '  get _w(){ return this._sel; }\n'
			printf '%s\n' "$CORPS"
			printf '}\n'
			#  On fabrique un window.getSelection() qui rend ce que le cas
			#  décrit, exactement comme le navigateur le ferait.
			cat <<'JS'
let SEL = null;
global.window = { getSelection: () => SEL };
function cas(nom, sel, champ, attendu){
  SEL = sel;
  const t = new T(sel, champ);
  const vu = t.aSelection();
  console.log((vu === attendu ? "OK   " : "RATE ") + nom + " -> " + vu);
}
const vide = { isCollapsed: true, toString: () => "" };
const plein = { isCollapsed: false, toString: () => "resultat de ls" };
cas("selection dans la SORTIE (la panne d'Alex)", plein, {selectionStart:0, selectionEnd:0}, true);
cas("rien de selectionne, curseur au DEBUT",      vide,  {selectionStart:0, selectionEnd:0}, false);
cas("rien de selectionne, curseur au milieu",     vide,  {selectionStart:3, selectionEnd:3}, false);
cas("selection dans le CHAMP",                    vide,  {selectionStart:1, selectionEnd:5}, true);
JS
		} > "$BANC/sel.js"
		SORTIE="$(node "$BANC/sel.js" 2>&1)"
		if printf '%s' "$SORTIE" | grep -q 'RATE'; then
			non "aSelection() se trompe :"
			printf '%s\n' "$SORTIE" | sed 's/^/       /'
		else
			ok "aSelection() répond juste sur les quatre cas (dont la panne d'Alex)"
			printf '%s\n' "$SORTIE" | sed 's/^/       /'
		fi
	fi
fi

# =============================================================================
titre "3. Les autres chemins vers le presse-papier"
# =============================================================================
#  Ctrl+Maj+C et Ctrl+Maj+V, les raccourcis habituels des terminaux sous
#  Linux. Ils ne peuvent pas se contenter de « laisser faire le navigateur » :
#  dans une vue QtWebEngine, Ctrl+Maj+C n'a aucune action par défaut.
if grep -q 'e.shiftKey && e.key.toLowerCase() === "c"' "$HTML"; then
	ok "Ctrl+Maj+C copie la sélection"
else
	non "Ctrl+Maj+C n'est pas branché"
fi
if grep -q 'e.shiftKey && e.key.toLowerCase() === "v"' "$HTML"; then
	ok "Ctrl+Maj+V colle"
else
	non "Ctrl+Maj+V n'est pas branché"
fi

#  Ctrl+C (sans Maj) ne doit pas attraper Ctrl+Maj+C au passage.
if grep -q 'e.ctrlKey && !e.shiftKey && !this.aSelection()' "$HTML"; then
	ok "la branche « annuler la ligne » exclut explicitement Maj"
else
	non "Ctrl+C ne distingue pas Maj : les deux raccourcis se marcheraient dessus"
fi

#  ═══ LE MENU DU CLIC DROIT RESTE ═══
#  C'est le chemin qu'utilisent les gens qui ne connaissent pas les
#  raccourcis — et le seul qui reste si les deux autres tombent.
if grep -qi 'contextmenu\|NoContextMenu\|setContextMenuPolicy' "$HTML" "$PY"; then
	non "quelque chose touche au menu contextuel : le clic droit pourrait ne plus proposer Copier/Coller"
else
	ok "rien ne désactive le menu contextuel — le clic droit garde Copier/Coller"
fi

#  ═══ LA SORTIE DOIT RESTER SÉLECTIONNABLE ═══
#  Trois « user-select:none » existent dans le fichier. Ils visent la barre
#  d'onglets, l'en-tête de fenêtre et la barre d'état — c'est voulu. Aucun ne
#  doit atteindre .sortie : une sortie non sélectionnable rendrait tout le
#  reste inutile. MESURÉ : .sortie vit dans .fen-corps, qui est le FRÈRE de
#  .fen-tete, donc rien n'est hérité.
MAUVAIS=0
for SEL in '.sortie' '.fen-corps'; do
	if awk -v s="$SEL" '
		$0 ~ "^"s"\\{" { dans = 1 }
		dans && /user-select[[:space:]]*:[[:space:]]*none/ { trouve = 1 }
		dans && /^}/ { dans = 0 }
		END { exit !trouve }
	' "$HTML"; then
		non "« user-select: none » s'applique à $SEL — la sortie ne serait pas sélectionnable"
		MAUVAIS=1
	fi
done
[ "$MAUVAIS" = 0 ] && ok "aucun « user-select: none » n'atteint la sortie"

# =============================================================================
titre "4. L'aide ne ment pas"
# =============================================================================
#  Une aide qui ment coûte plus cher qu'une aide absente : elle envoie
#  chercher la panne au mauvais endroit.
#  L'aide doit dire les DEUX comportements de Ctrl+C. Une première version
#  de ce contrôle refusait la chaîne « annuler la ligne » — mais la bonne
#  description la contient (« copier si… sinon annuler la ligne »). On exige
#  donc ce qui manquait : le mot « copier » dans la ligne de Ctrl+C.
LIGNE_CTRLC="$(grep -o '\["Ctrl+C","[^"]*"\]' "$HTML" | head -1)"
if [ -z "$LIGNE_CTRLC" ]; then
	non "aucune entrée « Ctrl+C » dans l'aide"
elif printf '%s' "$LIGNE_CTRLC" | grep -qi 'copier'; then
	ok "l'aide dit les deux comportements de Ctrl+C"
else
	non "l'aide réduit Ctrl+C à $LIGNE_CTRLC — elle ne dit pas qu'il copie"
fi
for R in 'Ctrl+Maj+C' 'Ctrl+Maj+V'; do
	if grep -q "$R" "$HTML"; then
		ok "l'aide annonce $R"
	else
		non "l'aide ne dit rien de $R — un raccourci qui existe et que personne ne connaît"
	fi
done

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mCopier, coller, et Ctrl+C qui interrompt encore.\033[0m\n'
