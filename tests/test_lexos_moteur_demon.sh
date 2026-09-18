#!/usr/bin/env bash
# =============================================================================
#  LE DÉMON RÉSIDENT — et surtout : ce qui se passe quand il n'est PAS là
# =============================================================================
#  ALEX : « un moteur pour tous les paramètres, que ça soit encore plus
#  fluide et rapide ».
#
#  CE QUE LE DÉMON RETIENT, MESURÉ :
#      import de volet.py .................  438 ms
#      import de settings.py ..............   86 ms
#      lecture d'état à froid ............. 1812 ms
#      monter le serveur, trouver le port .. 0 à 5 ms
#
#  ⚠ UNE DES DEUX RAISONS ATTENDUES N'EN ÉTAIT PAS UNE. On croyait que
#  trouver un port libre coûtait ; mesuré, c'est zéro. Ce qui coûte, c'est
#  l'import et la lecture. Dire le contraire aurait fait construire la
#  mauvaise moitié.
#
#  ═══ MAIS LA MOITIÉ DE CE BANC PORTE SUR SON ABSENCE ═══
#  Un accélérateur qui tombe ne doit RIEN empêcher — c'est la règle de
#  lexos-intro. Démon arrêté, fichier de ports périmé, démon muet : les
#  fenêtres doivent s'ouvrir comme avant, sans message et sans attendre.
#  C'est le point 3, et c'est celui qui compte le plus.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$RACINE/config/includes.chroot/usr/lib/lexos"
BIN="$RACINE/config/includes.chroot/usr/bin"
PART="$RACINE/config/includes.chroot/usr/share/lexos"
BANC="$(mktemp -d)"
trap 'pkill -f "$BANC" 2>/dev/null; rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$LIB/moteur/demon.py" ] || { echo "introuvable : $LIB/moteur/demon.py"; exit 1; }
command -v python3 >/dev/null 2>&1 || { muet "python3 absent : rien n'a été mesuré"; exit 0; }

EXEC="$BANC/exec"; mkdir -p "$EXEC"
demarre_demon() {
	LEXOS_VOLET_DIR="$PART/volet" LEXOS_SETTINGS_DIR="$PART/settings" \
	XDG_RUNTIME_DIR="$EXEC" LEXOS_VOLET_DELAI="${1:-4}" LEXOS_VOLET_LIRE="${2:-3}" \
	python3 "$LIB/moteur/demon.py" >"$BANC/demon.log" 2>&1 &
	echo $!
}
attends_ports() {
	for _ in $(seq 1 200); do
		[ -r "$EXEC/lexos/moteur.json" ] && return 0
		sleep 0.05
	done
	return 1
}
port_de() { python3 -c '
import json,sys
print(json.load(open(sys.argv[1]))["ports"].get(sys.argv[2], ""))' "$EXEC/lexos/moteur.json" "$1" 2>/dev/null; }

# ===========================================================================
titre "1. IL DÉMARRE, IL DIT OÙ IL EST, ET IL RANGE EN PARTANT"
# ===========================================================================
PID="$(demarre_demon)"
if ! attends_ports; then
	non "le démon n'a pas publié ses ports : $(head -3 "$BANC/demon.log" | tr '\n' ' ')"
	kill "$PID" 2>/dev/null
else
	PV="$(port_de volet)"; PS="$(port_de settings)"
	{ [ -n "$PV" ] && [ -n "$PS" ]; } \
		&& ok "les deux applications sont servies (volet:$PV settings:$PS)" \
		|| non "une application manque (volet:« $PV » settings:« $PS »)"
	#  Le fichier est à l'utilisateur SEUL : il dit où joindre un service qui
	#  exécute des actions système.
	DROITS="$(stat -c %a "$EXEC/lexos/moteur.json" 2>/dev/null || echo '?')"
	[ "$DROITS" = "600" ] \
		&& ok "le fichier de ports n'est lisible que par son propriétaire (0$DROITS)" \
		|| non "le fichier de ports est en 0$DROITS — il désigne un service qui agit sur la machine"
	DOSSIER="$(stat -c %a "$EXEC/lexos" 2>/dev/null || echo '?')"
	[ "$DOSSIER" = "700" ] \
		&& ok "…et son dossier aussi (0$DOSSIER)" \
		|| non "le dossier d'exécution est en 0$DOSSIER"

	# =========================================================================
	titre "2. LE PRÉCHAUFFAGE REND LA MAIN TOUT DE SUITE, ET RECOUVRE L'ATTENTE"
	# =========================================================================
	#  Un cache qui ne vit que 1,5 s ne sert à rien si la fenêtre met deux
	#  secondes à s'afficher. Le lanceur PRÉVIENT donc le démon avant de
	#  lancer la fenêtre : la lecture se fait PENDANT le démarrage de
	#  Chromium. Sans ça, le démon ne ferait gagner que l'import.
	LENT="$BANC/lent"; mkdir -p "$LENT"
	for O in nmcli bluetoothctl pactl xfconf-query wmctrl lpstat upower; do
		printf '#!/bin/sh\nsleep 1.2\nexit 0\n' > "$LENT/$O"; chmod +x "$LENT/$O"
	done
	kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
	PATH="$LENT:$PATH" PID="$(PATH="$LENT:$PATH" demarre_demon)"
	if ! attends_ports; then
		non "le démon n'a pas redémarré avec les outils lents — rien n'a été mesuré"
	else
		PV="$(port_de volet)"
		MESURE="$(python3 - "$PV" <<'PY' 2>/dev/null
import json, sys, time, urllib.request
p = sys.argv[1]
def get(u, d=30):
    with urllib.request.urlopen(u, timeout=d) as r: return r.read()
def ms(f):
    t = time.monotonic(); f(); return int((time.monotonic()-t)*1000)
#  Dire QUEL volet : sans ça le démon sert « agenda », qui ne lit aucun outil
#  externe — et la mesure ne mesurerait rien. Vu en la faisant.
get(f"http://127.0.0.1:{p}/api/prechauffe?quoi=rapides"); time.sleep(4)
sans = ms(lambda: get(f"http://127.0.0.1:{p}/api/etat")); time.sleep(3)
pre  = ms(lambda: get(f"http://127.0.0.1:{p}/api/prechauffe?quoi=rapides"))
time.sleep(1.5)                       # le temps que met la fenêtre à s'afficher
avec = ms(lambda: get(f"http://127.0.0.1:{p}/api/etat"))
print(json.dumps({"sans": sans, "pre": pre, "avec": avec}))
PY
)"
		if [ -z "$MESURE" ]; then
			muet "le préchauffage n'a pas pu être chronométré — non mesuré"
		else
			v(){ python3 -c 'import json,sys;print(json.loads(sys.argv[1])[sys.argv[2]])' "$MESURE" "$1"; }
			SANS="$(v sans)"; PRE="$(v pre)"; AVEC="$(v avec)"
			printf '     sans préchauffage : %s ms | il rend la main en %s ms | avec : %s ms\n' \
			       "$SANS" "$PRE" "$AVEC"
			[ "$SANS" -gt 500 ] \
				&& ok "le témoin mesure quelque chose : sans préchauffage, la page attend $SANS ms" \
				|| non "sans préchauffage la page n'attend que $SANS ms — les outils lents ne sont pas pris, le reste est sans valeur"
			[ "$PRE" -lt 300 ] \
				&& ok "préchauffer rend la main en $PRE ms : le lanceur n'est pas retenu" \
				|| non "préchauffer a retenu le lanceur $PRE ms — il attendrait la lecture, ce qui annule l'intérêt"
			[ "$AVEC" -lt 300 ] \
				&& ok "…et la page trouve son état déjà lu ($AVEC ms contre $SANS ms)" \
				|| non "la page a quand même attendu $AVEC ms : la lecture ne recouvre pas le démarrage"
		fi

		# =======================================================================
		titre "2 ter. LA PAGE REJOINT LA LECTURE EN COURS, ELLE N'EN LANCE PAS UNE DEUXIÈME"
		# =======================================================================
		#  ═══ LE CAS QUE LE POINT 2 NE COUVRAIT PAS, ET QUI A FAILLI PASSER ═══
		#  Au point 2, la fenêtre met 1,5 s à s'afficher : la lecture
		#  préchauffée a le temps de FINIR, et la page trouve un cache chaud.
		#  Une mutation qui retirait la déduplication des lectures restait donc
		#  VERTE. Mais sur une machine où Chromium démarre plus vite que les
		#  outils ne répondent — le vrai cas du ThinkPad — la page demande
		#  PENDANT que la lecture tourne encore. Sans déduplication, elle en
		#  lance une DEUXIÈME : deux fois les sous-processus, et le
		#  préchauffage ne sert plus à rien.
		#  On compte les lancements réels, on ne raisonne pas dessus.
		TEMOIN2="$BANC/temoin2"; : > "$TEMOIN2"
		for O in nmcli bluetoothctl pactl; do
			printf '#!/bin/sh\necho x >> "%s"\nsleep 1.2\n' "$TEMOIN2" > "$LENT/$O"
			chmod +x "$LENT/$O"
		done
		#  ⚠ ON MESURE D'ABORD CE QUE COÛTE **UNE** LECTURE, on ne le devine
		#  pas. Première version de ce point : « pas plus de 3 lancements ».
		#  Faux — une lecture des rapides en fait SIX (deux nmcli pour les
		#  radios, un bluetoothctl, trois pactl pour volume/muet/micro). Le
		#  contrôle accusait donc un code juste. Un seuil inventé ne vaut pas
		#  mieux qu'une valeur inventée : on relève la référence, puis on
		#  compare.
		sleep 3                       # laisser expirer le cache précédent
		: > "$TEMOIN2"
		python3 -c '
import sys, urllib.request
with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/api/etat", timeout=30): pass' "$PV" >/dev/null 2>&1
		UNE="$(wc -l < "$TEMOIN2" | tr -d ' ')"
		sleep 3                       # laisser expirer le cache de la référence
		: > "$TEMOIN2"
		DEDUP="$(python3 - "$PV" <<'PY2' 2>/dev/null
import json, sys, time, urllib.request
p = sys.argv[1]
def get(u, d=30):
    with urllib.request.urlopen(u, timeout=d) as r: return r.read()
get(f"http://127.0.0.1:{p}/api/prechauffe?quoi=rapides")
time.sleep(0.3)                   # la fenêtre s'affiche AVANT la fin de la lecture
t = time.monotonic()
get(f"http://127.0.0.1:{p}/api/etat")
print(json.dumps({"attente": int((time.monotonic()-t)*1000)}))
PY2
)"
		N2="$(wc -l < "$TEMOIN2" | tr -d ' ')"
		ATT="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["attente"])' "$DEDUP" 2>/dev/null || echo -1)"
		printf '     page servie pendant la lecture : %s ms, %s lancements d'"'"'outils\n' "$ATT" "$N2"
		printf '     référence : UNE lecture = %s lancements\n' "$UNE"
		if [ "$UNE" = "0" ] || [ "$N2" = "0" ]; then
			non "aucun outil lancé (référence $UNE, mesure $N2) — le témoin ne mesure rien, ce point est sans valeur"
		elif [ "$N2" -le "$UNE" ]; then
			ok "la page a REJOINT la lecture en cours : $N2 lancements pour une lecture qui en coûte $UNE"
		else
			non "$N2 lancements alors qu'une lecture en coûte $UNE — la page en a relancé une deuxième en parallèle"
		fi
		[ "$ATT" -ge 0 ] 2>/dev/null && [ "$ATT" -lt 1500 ] \
			&& ok "…et elle a attendu $ATT ms, pas une lecture entière" \
			|| non "la page a attendu $ATT ms : elle n'a pas rejoint la lecture"

		# =======================================================================
		titre "2 bis. AU REPOS, IL NE LIT RIEN — pas de relecture périodique"
		# =======================================================================
		#  Sur un portable, un nmcli toutes les deux secondes toute la journée
		#  se paie en autonomie. Le démon ne doit rien lire tant que personne
		#  n'ouvre rien. On compte les lancements réels pendant qu'il dort.
		TEMOIN="$BANC/temoin"; : > "$TEMOIN"
		for O in nmcli bluetoothctl pactl; do
			printf '#!/bin/sh\necho x >> "%s"\nsleep 1.2\n' "$TEMOIN" > "$LENT/$O"
			chmod +x "$LENT/$O"
		done
		sleep 4
		N="$(wc -l < "$TEMOIN" | tr -d ' ')"
		[ "$N" = "0" ] \
			&& ok "quatre secondes de repos, ZÉRO lancement d'outil" \
			|| non "$N lancements pendant que personne n'ouvrait rien — le démon lit en boucle"
	fi
	kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
	sleep 0.3
	[ ! -e "$EXEC/lexos/moteur.json" ] \
		&& ok "en partant, il efface son fichier de ports : personne ne suivra une adresse morte" \
		|| non "le fichier de ports survit au démon : les lanceurs iraient frapper à une porte fermée"
fi

# ===========================================================================
titre "3. SANS LUI, RIEN NE CHANGE — c'est le point qui compte le plus"
# ===========================================================================
#  Un accélérateur qui tombe ne doit rien empêcher. On ne lit pas le lanceur :
#  on le FAIT TOURNER, avec un faux python3 qui note ce qu'on lui demande
#  d'exécuter, et on regarde quel chemin il a pris.
FAUX="$BANC/faux"; mkdir -p "$FAUX"
JOURNAL="$BANC/appels"
cat > "$FAUX/python3" <<FAUXPY
#!/bin/sh
#  Les appels « python3 - » (les petits sondages du lanceur) doivent marcher
#  pour de vrai : c'est eux qui lisent le fichier de ports et frappent chez
#  le démon. Seuls les LANCEMENTS DE FENÊTRE sont notés et court-circuités.
case "\$1" in
  */vitrine.py|*/volet.py|*/settings.py)
      echo "\$*" >> "$JOURNAL"; exit 0 ;;
esac
exec /usr/bin/python3 "\$@"
FAUXPY
chmod +x "$FAUX/python3"
for O in pgrep pkill xfconf-query; do
	printf '#!/bin/sh\nexit 1\n' > "$FAUX/$O"; chmod +x "$FAUX/$O"
done

essai_lanceur() {   # $1 = description du décor ; rend le chemin pris
	: > "$JOURNAL"
	PATH="$FAUX:$PATH" XDG_RUNTIME_DIR="$1" HOME="$BANC/home" \
		sh "$BIN/lexos-volet" rapides >/dev/null 2>&1
	cat "$JOURNAL" 2>/dev/null
}

VIDE="$BANC/vide"; mkdir -p "$VIDE"
A="$(essai_lanceur "$VIDE")"
case "$A" in
	*volet.py*rapides*) ok "démon absent : le lanceur prend le chemin entier (volet.py)" ;;
	"")                 non "démon absent : le lanceur n'a RIEN lancé — le volet ne s'ouvrirait pas" ;;
	*)                  non "démon absent : le lanceur a lancé « $A »" ;;
esac

#  Un fichier de ports qui désigne un démon MORT. C'est le cas vicieux : le
#  fichier existe, le port n'écoute plus. Sans vérification, le lanceur
#  ouvrirait une fenêtre sur une adresse qui ne répond pas — un volet BLANC.
MORT="$BANC/mort"; mkdir -p "$MORT/lexos"
python3 -c '
import json, socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close()
json.dump({"pid": 999999, "ports": {"volet": p, "settings": p}},
          open(sys.argv[1], "w"))' "$MORT/lexos/moteur.json"
B="$(essai_lanceur "$MORT")"
case "$B" in
	*volet.py*rapides*) ok "fichier de ports périmé : il vérifie, n'obtient rien, et retombe sur le chemin entier" ;;
	*vitrine.py*)       non "fichier de ports périmé : il a quand même lancé la fenêtre légère — volet BLANC sur un port mort" ;;
	"")                 non "fichier de ports périmé : rien n'a été lancé" ;;
	*)                  non "fichier de ports périmé : « $B »" ;;
esac

#  Et avec un VRAI démon : le chemin rapide.
PID="$(XDG_RUNTIME_DIR="$EXEC" demarre_demon)"
if attends_ports; then
	C="$(essai_lanceur "$EXEC")"
	case "$C" in
		*vitrine.py\ volet*rapides*) ok "démon vivant : le lanceur prend la fenêtre légère, sans réimporter volet.py" ;;
		*volet.py*)                  non "démon vivant : le lanceur a quand même pris le chemin entier — le gain est perdu" ;;
		*)                           non "démon vivant : « $C »" ;;
	esac
else
	muet "le démon n'a pas redémarré : le chemin rapide n'a pas été éprouvé"
fi
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null

# ===========================================================================
titre "4. UN SEUL VOLET À LA FOIS, SOUS LES DEUX FORMES"
# ===========================================================================
#  Le volet existe maintenant sous DEUX formes de processus : « volet.py »
#  sans démon, « moteur/vitrine.py volet » avec. Le basculement du lanceur
#  (un clic ouvre, un deuxième referme) repose sur pgrep. S'il ne connaissait
#  qu'une des deux formes, un deuxième clic sur la flèche OUVRIRAIT UN
#  DEUXIÈME VOLET au lieu de fermer le premier.
LANCEUR="$(grep -v '^[[:space:]]*#' "$BIN/lexos-volet")"
CONNU=0
grep -q 'vitrine.py volet' <<< "$LANCEUR" && CONNU=$((CONNU+1))
grep -q 'lexos/volet.py' <<< "$LANCEUR" && CONNU=$((CONNU+1))
[ "$CONNU" = 2 ] \
	&& ok "le lanceur connaît les deux formes de volet pour les fermer" \
	|| non "le lanceur ne connaît que $CONNU forme(s) de volet : un deuxième clic en ouvrirait un deuxième"

# ===========================================================================
titre "5. « VOLET INSTANTANÉ » COUPÉ : LE LANCEUR N'UTILISE PAS LE DÉMON"
# ===========================================================================
#  Couper l'interrupteur arrête normalement le service, donc plus de fichier
#  de ports, donc le lanceur retombe tout seul. Mais sans systemctl (session
#  sans logind), le réglage s'écrit et le service ne bouge pas — et un
#  interrupteur qui ne change rien est pire qu'absent. Le lanceur lit donc
#  le réglage lui-même. On l'éprouve avec un démon BIEN VIVANT : c'est le
#  seul décor où la distinction se voit.
PID="$(XDG_RUNTIME_DIR="$EXEC" demarre_demon)"
if ! attends_ports; then
	muet "le démon n'a pas démarré : l'interrupteur n'a pas été éprouvé"
else
	mkdir -p "$BANC/home/.config/lexos"
	printf 'off\n' > "$BANC/home/.config/lexos/volet-instantane"
	D="$(essai_lanceur "$EXEC")"
	case "$D" in
		*volet.py*rapides*) ok "interrupteur coupé, démon vivant : le lanceur prend quand même le chemin entier" ;;
		*vitrine.py*)       non "interrupteur coupé : le lanceur utilise quand même le démon — le réglage ne change rien" ;;
		*)                  non "interrupteur coupé : « $D »" ;;
	esac
	printf 'on\n' > "$BANC/home/.config/lexos/volet-instantane"
	E="$(essai_lanceur "$EXEC")"
	case "$E" in
		*vitrine.py*) ok "…et rallumé, il reprend la fenêtre légère" ;;
		*)            non "interrupteur rallumé : « $E » — le réglage ne se relit pas" ;;
	esac
	rm -f "$BANC/home/.config/lexos/volet-instantane"
fi
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null

# ===========================================================================
titre "6. IL EST LIVRÉ ACTIVÉ — l'unité, et le lien qui l'allume"
# ===========================================================================
#  ALEX l'a demandé activé par défaut. Une unité livrée mais jamais activée
#  ne servirait à personne, et l'interrupteur des Paramètres montrerait
#  « demandé, mais arrêté » à tout le monde dès la première session.
UNITE="$RACINE/config/includes.chroot/usr/lib/systemd/user/lexos-moteurd.service"
LIEN="$RACINE/config/includes.chroot/etc/systemd/user/graphical-session.target.wants/lexos-moteurd.service"
[ -r "$UNITE" ] \
	&& ok "l'unité utilisateur est livrée" \
	|| non "lexos-moteurd.service n'est pas livré"
if [ -L "$LIEN" ]; then
	CIBLE="$(readlink "$LIEN")"
	[ "$CIBLE" = "/usr/lib/systemd/user/lexos-moteurd.service" ] \
		&& ok "…et le lien qui l'active pointe sur elle ($CIBLE)" \
		|| non "le lien d'activation pointe ailleurs : « $CIBLE »"
else
	non "rien n'active l'unité : elle serait livrée et jamais démarrée"
fi
#  ═══ L'UNITÉ SE RELIT-ELLE ? ET NON, systemd-analyze NE SAIT PAS LE DIRE ICI ═══
#  Première version de ce contrôle : « systemd-analyze --user verify ».
#  Éprouvée en cassant l'unité ([Service] → [Servize]) : elle reste VERTE.
#  Sur ce bâti, l'outil n'arrive même pas à démarrer son gestionnaire
#  (« Failed to initialize manager ») et sort avec le code 0 dans les DEUX
#  cas. Il ne mesurait rien du tout.
#  On relit donc le fichier nous-mêmes : les sections qu'une unité de service
#  doit avoir, et pas d'autres. C'est moins complet qu'un vrai verify, mais
#  ça attrape ce qui se casse vraiment — une faute de frappe dans un
#  [Section], qui ne se verrait sinon qu'au démarrage de la session chez Alex.
VERDICT="$(python3 - "$UNITE" <<'PYEOF' 2>&1
import re, sys
CONNUES = {"Unit", "Service", "Install"}
texte = open(sys.argv[1], encoding="utf-8").read()
sections, courante, cles = [], None, {}
for ligne in texte.splitlines():
    l = ligne.strip()
    if not l or l.startswith("#") or l.startswith(";"):
        continue
    m = re.fullmatch(r"\[([^\]]+)\]", l)
    if m:
        courante = m.group(1); sections.append(courante); continue
    if courante and "=" in l:
        cles.setdefault(courante, set()).add(l.split("=", 1)[0].strip())
inconnues = [s for s in sections if s not in CONNUES]
manque = [s for s in ("Unit", "Service", "Install") if s not in sections]
if inconnues:
    print("SECTION_INCONNUE " + " ".join(inconnues))
elif manque:
    print("SECTION_MANQUANTE " + " ".join(manque))
elif "ExecStart" not in cles.get("Service", set()):
    print("PAS_D_EXECSTART")
elif "WantedBy" not in cles.get("Install", set()):
    print("PAS_DE_WANTEDBY")
else:
    print("OK")
PYEOF
)"
case "$VERDICT" in
	OK) ok "l'unité a les trois sections attendues, un ExecStart et un WantedBy" ;;
	SECTION_INCONNUE*) non "l'unité a une section que systemd ne connaît pas : ${VERDICT#SECTION_INCONNUE }" ;;
	SECTION_MANQUANTE*) non "il manque une section à l'unité : ${VERDICT#SECTION_MANQUANTE }" ;;
	PAS_D_EXECSTART) non "l'unité n'a pas d'ExecStart : elle ne lancerait rien" ;;
	PAS_DE_WANTEDBY) non "l'unité n'a pas de WantedBy : « enable » ne saurait pas où l'accrocher" ;;
	*) muet "l'unité n'a pas pu être relue ici : $VERDICT" ;;
esac

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
