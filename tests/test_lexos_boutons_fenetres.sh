#!/usr/bin/env bash
# =============================================================================
#  Chaque bouton fait quelque chose, chaque fenêtre mène quelque part
# =============================================================================
#  ALEX : « regarde bien pour que tous les boutons et les fenêtres ouvrent
#  fluidement. »
#
#  ═══ CE QUE L'AUDIT A TROUVÉ ═══
#  Deux fenêtres sur trente-cinq étaient MORTES : « Applications » et
#  « Applications par défaut » lançaient toutes deux
#  « exo-preferred-applications ». Vérifié sur les vrais paquets : exo-utils
#  ne livre que exo-open, exo-desktop-item-edit et exo-helper — ce programme
#  n'existe plus. XFCE a déplacé la fenêtre dans xfce4-settings, où le
#  fichier .desktop s'intitule « Default Applications » et lance
#  « xfce4-mime-settings ».
#
#  ET LE SILENCE ÉTAIT DE NOTRE FAIT. Le moteur renvoyait pourtant le motif
#  exact (« Outil absent : … ») ; la page jetait la réponse. On cliquait,
#  rien ne s'ouvrait, aucun message — un bouton mort ne se distinguait pas
#  d'un bouton lent.
#
#  Le commentaire de _xfce() raconte que ce défaut a DÉJÀ tué neuf fenêtres
#  auparavant (son, apparence, bureau, multi-tâches, souris, amovibles,
#  tablette, accessibilité, clavier). C'est le défaut le plus répété de ce
#  dépôt, et rien ne le surveillait.
#
#  ═══ LA QUESTION QUE CE BANC POSE ═══
#  Pas « ce programme est-il installé quelque part » — la réponse serait
#  bruyante et fausse : beaucoup d'appels sont des sondes volontaires. Il
#  pose la question précise et dangereuse : UN BOUTON PEUT-IL NE MENER NULLE
#  PART ? Une fenêtre est acceptée si elle passe par _xfce() (qui garantit un
#  repli), par un terminal (qui s'ouvre toujours), par un outil LexOS présent
#  dans l'ISO, ou par un programme tiers EXPLICITEMENT VÉRIFIÉ ci-dessous.
#  Tout nouveau nom force quelqu'un à vérifier avant de l'ajouter.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
VOL_JS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/app.js"
VOL_PY="$RACINE/config/includes.chroot/usr/lib/lexos/volet.py"

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

#  ═══ LES PROGRAMMES TIERS VÉRIFIÉS, UN PAR UN ═══
#  Chaque ligne dit le paquet qui le fournit ET la liste qui l'installe —
#  vérifiés en téléchargeant le paquet et en listant son contenu, jamais de
#  mémoire. Ajouter un nom ici est un engagement ; le banc rougit sinon.
TIERS="
xfce4-appfinder|xfce4-appfinder|lexos-core.list.chroot
system-config-printer|system-config-printer|20-desktop.list
xfce4-notifyd-config|xfce4-notifyd|20-desktop.list
gcm-viewer|gnome-color-manager|56-reglages.list
timedatectl|systemd|toujours présent (init du système)
"

# =============================================================================
titre "1. Aucun bouton n'appelle une fonction qui n'existe pas"
# =============================================================================
RES="$(python3 - "$APP" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
declarees  = set(re.findall(r'^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)', src, re.M))
declarees |= set(re.findall(r'^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=', src, re.M))
appelees = set()
for m in re.finditer(r'onclick="([^"]+)"', src):
    for f in re.findall(r'\b([A-Za-z_$][\w$]*)\s*\(', m.group(1)):
        appelees.add(f)
#  Ce ne sont pas des fonctions de la page : des méthodes et des natifs.
NATIF = {"event","Number","String","confirm","alert","parseInt","replace",
         "stopPropagation","then","preventDefault","encodeURIComponent"}
print("APPELS:%d" % len(appelees))
print("MANQUE:" + ",".join(sorted(appelees - declarees - NATIF)))
PY
)"
NB="$(printf '%s' "$RES" | sed -n 's/^APPELS://p')"
MQ="$(printf '%s' "$RES" | sed -n 's/^MANQUE://p')"
if [[ "$NB" -ge 30 ]]; then
	ok "$NB fonctions appelées depuis un bouton — la page a bien été lue"
else
	non "seulement $NB appels relevés : la lecture a échoué, le reste serait creux"
fi
if [[ -z "$MQ" ]]; then
	ok "toutes existent — aucun bouton ne pointe dans le vide"
else
	non "fonction(s) appelées mais jamais déclarées : $MQ"
fi

# =============================================================================
titre "2. Chaque appel trouve son action dans SON moteur"
# =============================================================================
#  DEUX PAGES, DEUX MOTEURS. Le volet a son propre volet.py ; comparer ses
#  appels à la table des Paramètres crierait au loup pour rien — c'est
#  l'erreur que cet audit a d'abord commise.
verifie_paire() { # verifie_paire <nom> <page.js> <moteur.py>
	local nom="$1" js="$2" py="$3"
	[[ -r "$js" && -r "$py" ]] || { non "$nom : page ou moteur introuvable"; return; }
	local sortie
	sortie="$(python3 - "$js" "$py" <<'PY'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
py = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r'^ACTIONS\s*=\s*\{(.*?)^\}', py, re.S | re.M) or \
    re.search(r'ACTIONS\s*=\s*\{(.*?)\n\}', py, re.S)
actions = set(re.findall(r'"([^"]+)"\s*:', m.group(1))) if m else set()
#  LES DEUX SORTES DE GUILLEMETS. Ce motif ne voyait que api("nom") : un
#  appel écrit api('nom') lui échappait complètement. Ce n'est pas
#  théorique — app.js portait « api('ouvrir','prive') » dans un attribut
#  onclick, et ce contrôle ne l'a jamais vu. Un futur api('nom-inexistant')
#  serait passé au vert de la même façon.
appels  = set(re.findall(r'\bapi\(\s*"([^"]+)"', js)) \
        | set(re.findall(r"\bapi\(\s*'([^']+)'", js))
print("N:%d" % len(appels))
print("ORPH:" + ",".join(sorted(appels - actions)))
PY
)"
	local n orph
	n="$(printf '%s' "$sortie" | sed -n 's/^N://p')"
	orph="$(printf '%s' "$sortie" | sed -n 's/^ORPH://p')"
	if [[ "$n" -lt 1 ]]; then
		non "$nom : aucun appel relevé — le contrôle serait creux"
	elif [[ -z "$orph" ]]; then
		ok "$nom : les $n actions appelées existent toutes dans son moteur"
	else
		non "$nom : action(s) appelées sans exister — le bouton appelle dans le vide : $orph"
	fi
}
verifie_paire "Paramètres" "$APP" "$SET"
verifie_paire "Volet"      "$VOL_JS" "$VOL_PY"

# =============================================================================
titre "3. Aucune fenêtre ne mène nulle part"
# =============================================================================
FEN="$(python3 - "$SET" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
deb = s.index("def act_ouvrir(arg):")
fin = s.index("\ndef ", deb + 10)
bloc = re.sub(r'^\s*#.*$', '', s[deb:fin], flags=re.M)
for m in re.finditer(r'"([a-z-]+)":\s*lambda:\s*(.+?)(?=,\s*\n\s*(?:"|\}))', bloc, re.S):
    print(m.group(1) + "\t" + " ".join(m.group(2).split()))
PY
)"
N_FEN="$(printf '%s\n' "$FEN" | grep -c . )"
if [[ "$N_FEN" -ge 30 ]]; then
	ok "$N_FEN fenêtres déclarées — la table a bien été lue"
else
	non "seulement $N_FEN fenêtres lues : le contrôle serait creux"
fi

MORTES=""
while IFS=$'\t' read -r cle corps; do
	[[ -n "$cle" ]] || continue
	#  a) _xfce() : il essaie chaque nom PUIS le gestionnaire général. Il ne
	#     peut pas ne mener nulle part — c'est sa raison d'être.
	case "$corps" in *_xfce*) continue ;; esac
	#  b) _terminal() : la fenêtre est le terminal lui-même, toujours là.
	case "$corps" in *_terminal*) continue ;; esac
	#  c) _run() : le programme DOIT exister. C'est ici qu'étaient les morts.
	PROG="$(printf '%s' "$corps" | sed -n 's/.*_run(\["\([a-z0-9._-]*\)".*/\1/p')"
	[[ -n "$PROG" ]] || { MORTES="$MORTES $cle(illisible)"; continue; }
	#  Un outil LexOS : le fichier doit partir dans l'ISO.
	if [[ "$PROG" == lexos* ]]; then
		[[ -e "$RACINE/config/includes.chroot/usr/bin/$PROG" ]] \
			|| MORTES="$MORTES $cle($PROG absent de l'ISO)"
		continue
	fi
	#  Un programme tiers : il doit être dans la liste vérifiée en tête.
	printf '%s' "$TIERS" | grep -q "^$PROG|" \
		|| MORTES="$MORTES $cle($PROG non vérifié)"
done <<< "$FEN"

if [[ -z "$MORTES" ]]; then
	ok "les $N_FEN fenêtres mènent toutes quelque part"
else
	non "fenêtre(s) qui n'ouvriraient rien :$MORTES"
fi

#  ═══ LE MORT NOMMÉMENT ═══ Si quelqu'un le remet, le message dit tout de
#  suite de quoi il s'agit au lieu de laisser chercher.
if printf '%s' "$FEN" | grep -q '_run(\["exo-preferred-applications"'; then
	non "« exo-preferred-applications » est de retour en appel direct — ce programme n'existe plus"
else
	ok "« exo-preferred-applications » n'est plus appelé sans repli"
fi

#  ET LE REMPLAÇANT EST LE BON, celui du fichier .desktop « Default
#  Applications » de xfce4-settings.
if grep -q 'xfce4-mime-settings' "$SET"; then
	ok "« xfce4-mime-settings » a pris le relais (le vrai nom, lu dans le paquet)"
else
	non "aucun remplaçant : les deux fenêtres « applications » resteraient mortes"
fi

# =============================================================================
titre "4. Une fenêtre qui refuse de s'ouvrir le DIT"
# =============================================================================
#  Le silence était la moitié du bogue : le moteur donnait déjà le motif.
#  On dépouille les commentaires — celui juste au-dessus de l'appel contient
#  les mêmes mots, et un contrôle qui lit de la prose reste vert pour rien.
CORPS_OUVRIR="$(python3 - "$APP" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^async function ouvrir\(section\)\{[\s\S]*?\n\}', s, re.M)
t = m.group(0) if m else ""
t = re.sub(r'/\*[\s\S]*?\*/', '', t)
t = re.sub(r'^\s*//.*$', '', t, flags=re.M)
print(t)
PY
)"
if printf '%s' "$CORPS_OUVRIR" | grep -q 'api('; then
	ok "ouvrir() a bien été trouvée"
else
	non "ouvrir() introuvable — les contrôles suivants seraient creux"
fi
if printf '%s' "$CORPS_OUVRIR" | grep -q 'erreur'; then
	ok "elle lit le motif du refus au lieu de jeter la réponse"
else
	non "elle jette la réponse : un outil absent resterait totalement muet"
fi


# =============================================================================
titre "5. LE CHOIX COURANT SE VOIT — et aucun bouton n'annonce un faux succès"
# =============================================================================
CSS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/style.css"
BANC5="$(mktemp -d)"
trap 'rm -rf "$BANC5"' EXIT

#  ═══ ALEX : « POUR CHANGER DE COULEUR SUR LE BOUTON SÉLECTIONNÉ, POUR QU'IL
#      CHANGE DE COULEUR » ═══
#  Les cinq fonds d'écran intégrés et les vignettes de « Mes images » étaient
#  les SEULS choix de toute la page à ne jamais montrer lequel était posé :
#  leurs boutons portaient « class="btn ghost" » écrit en dur, sans condition.
#  Et ce n'était pas un oubli d'une ligne — etat() ne DISAIT pas quel fond est
#  posé, il n'y avait rien à comparer.
grep -q '"fond": _fond_etat(' "$SET" \
	&& ok "le moteur publie QUEL fond est posé (sans ça, rien à mettre en couleur)" \
	|| non "etat() ne dit pas quel fond est posé : aucun bouton ne peut se colorer"
#  Le nom EXACT, et son emploi : « def _fond_actuel » tout court laissait
#  passer un « _fond_actuel_retire » — mesuré par mutation.
grep -q '^def _fond_actuel():' "$SET" && grep -q 'chemin = _fond_actuel()' "$SET" \
	&& ok "…et il le lit dans XFCE, il ne le devine pas" \
	|| non "aucun lecteur du fond courant, ou il n'est pas appelé"

#  La page doit s'en servir POUR LES DEUX listes.
python3 - "$APP" > "$BANC5/fonds" <<'PY2'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'case "bureau":([\s\S]*?)case "multitaches":', s)
b = m.group(1) if m else ""
#  Les cinq fonds intégrés : au moins un « sel » conditionnel, et plus aucun
#  « btn ghost » écrit en dur sur un setFond(...).
#  Les cinq boutons sortent d'un .map() : « setFond( » n'apparaît qu'une fois
#  dans la source. On compte donc les CLÉS, qui, elles, y sont toutes.
print("INTEGRES:%d" % sum(1 for k in ("defaut","secu","demon","keyart","nomad") if '"%s"' % k in b))
print("DUR:%d" % len(re.findall(r'class="btn ghost"[^>]*onclick="setFond\(', b)))
print("SELFOND:%d" % len(re.findall(r'etat\.fond[^\n]*sel', b)))
#  « (etat.fond||{}) » contient une accolade fermante : « [^}]* » s'y arrêtait.
print("SELWALL:%d" % len(re.findall(r'wall-swatch\$\{.*?sel', b)))
PY2
LU_INT="$(sed -n 's/^INTEGRES://p' "$BANC5/fonds")"
LU_DUR="$(sed -n 's/^DUR://p' "$BANC5/fonds")"
LU_SF="$(sed -n 's/^SELFOND://p' "$BANC5/fonds")"
LU_SW="$(sed -n 's/^SELWALL://p' "$BANC5/fonds")"
[[ "${LU_INT:-0}" -ge 5 ]] \
	&& ok "les cinq fonds intégrés sont bien tous là ($LU_INT)" \
	|| non "moins de cinq fonds intégrés relevés — le contrôle suivant serait creux"
[[ "${LU_DUR:-1}" -eq 0 ]] \
	&& ok "aucun fond intégré n'est écrit « ghost » en dur" \
	|| non "$LU_DUR fond(s) intégré(s) gardent « btn ghost » en dur : le fond posé ressemble aux autres"
[[ "${LU_SF:-0}" -ge 1 ]] \
	&& ok "le fond posé prend la classe « sel »" \
	|| non "aucun fond ne prend « sel » : impossible de voir lequel est choisi"
[[ "${LU_SW:-0}" -ge 1 ]] \
	&& ok "…et la vignette de « Mes images » aussi" \
	|| non "la galerie ne met jamais la vignette posée en évidence"
grep -q '^\.wall-swatch\.sel{' "$CSS" \
	&& ok "…et la feuille de style sait la dessiner" \
	|| non "la classe « sel » est posée sur la vignette mais aucune règle CSS ne la dessine — rien ne changerait à l'écran"

#  ═══ UNE FONCTION QUI N'EST ATTEINTE PAR AUCUN BOUTON N'EXISTE PAS ═══
#  capture() était écrite, l'action « capture » était dans ACTIONS,
#  act_capture était implémentée et acceptait photo|zone|fenetre — et AUCUN
#  onclick ne l'appelait. Du code complet, relié des deux côtés, injoignable.
for M in photo zone fenetre; do
	grep -q "capture('$M')" "$APP" \
		&& ok "un bouton appelle capture('$M')" \
		|| non "capture('$M') n'est atteinte par aucun bouton — l'action est injoignable"
done

#  ═══ AUCUN BOUTON N'ANNONCE UN SUCCÈS QU'IL N'A PAS OBTENU ═══
#  « api('ouvrir','prive').then(()=>toast('… s'ouvre')) » : api() affiche déjà
#  « ✗ » et le motif quand ça rate, puis le .then() s'exécute QUOI QU'IL
#  ARRIVE et REMPLACE ce message par un succès. On lisait « Fichiers privés
#  s'ouvre » alors qu'il ne se passait rien.
python3 - "$APP" > "$BANC5/menteurs" <<'PY2'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r'/\*[\s\S]*?\*/', '', s)
#  un api(...) suivi d'un .then( qui ne regarde jamais la réponse
mauvais = re.findall(r'api\([^)]*\)\s*\.then\(\s*\(\s*\)\s*=>', s)
print("MENTEURS:%d" % len(mauvais))
PY2
LU_M="$(sed -n 's/^MENTEURS://p' "$BANC5/menteurs")"
[[ "${LU_M:-1}" -eq 0 ]] \
	&& ok "aucun bouton n'annonce le succès sans regarder la réponse" \
	|| non "$LU_M bouton(s) annoncent le succès quoi qu'il arrive — un échec passerait pour une réussite"

#  ═══ CHAQUE FENÊTRE DÉCLARÉE EST OFFERTE QUELQUE PART ═══
#  L'inverse du contrôle 3 : act_ouvrir servait 38 cibles, la page n'en
#  proposait que 35. « usb », « confidentialite » et « maj » étaient testées
#  ici alors qu'aucun écran ne pouvait les déclencher.
python3 - "$SET" "$APP" > "$BANC5/orphelines" <<'PY2'
import re, sys
py = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
deb = py.index("def act_ouvrir(arg):")
bloc = py[deb:py.index("\n\n\ndef ", deb)]
cibles = set(re.findall(r'^\s{8}"([a-z0-9-]+)":\s*lambda', bloc, re.M))
offertes = set(re.findall(r'btnOuvrir\(\s*"([a-z0-9-]+)"', js))
offertes |= set(re.findall(r"ouvrir\(\s*'([a-z0-9-]+)'", js))
offertes |= set(re.findall(r'ouvrir\(\s*"([a-z0-9-]+)"', js))
#  …et l'appel direct api("ouvrir", "x"), que « boost » emploie (app.js:396).
offertes |= set(re.findall(r'api\(\s*"ouvrir"\s*,\s*"([a-z0-9-]+)"', js))
offertes |= set(re.findall(r"api\(\s*'ouvrir'\s*,\s*'([a-z0-9-]+)'", js))
print("CIBLES:%d" % len(cibles))
print("ORPH:" + ",".join(sorted(cibles - offertes)))
PY2
LU_C="$(sed -n 's/^CIBLES://p' "$BANC5/orphelines")"
LU_O="$(sed -n 's/^ORPH://p' "$BANC5/orphelines")"
[[ "${LU_C:-0}" -ge 30 ]] \
	&& ok "les $LU_C fenêtres du moteur ont bien été relues" \
	|| non "la table act_ouvrir n'a pas été relue — le contrôle serait creux"
[[ -z "$LU_O" ]] \
	&& ok "chacune est offerte par au moins un bouton de la page" \
	|| non "fenêtre(s) servies par le moteur mais offertes nulle part : $LU_O"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
