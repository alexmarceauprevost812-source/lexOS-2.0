#!/usr/bin/env bash
# =============================================================================
#  Éprouver le VRAI pseudo-terminal de LexOS Pro Terminal
# =============================================================================
#  ALEX : « j'ai beau essayer le terminal LexOS Pro, je suis même pas capable
#  de lancer claude ».
#
#  ══ CE QUE CE BANC PROTÈGE, ET CE QUE CHAQUE POINT A COÛTÉ ══
#
#  1. UN VRAI TERMINAL, PAS UN SUBPROCESS. L'ancien chemin lançait un bash
#     jetable avec stdin fermé, la sortie ramassée à la fin, et un délai de
#     25 secondes. Trois verrous, dont chacun suffisait — et surtout AUCUN
#     pty : « isatty() » était faux, donc « claude », « sudo », « nano » et
#     « htop » refusaient tous de démarrer. Les contrôles ci-dessous
#     REPRODUISENT chacun de ces quatre besoins avec de vrais programmes,
#     jamais en relisant le code.
#
#  2. LE MOT DE PASSE DE SUDO. C'est l'une des deux lignes que la consigne
#     déclare bloquantes. On ne peut pas éprouver sudo lui-même dans un banc
#     (il n'y a pas toujours de mot de passe, et jamais celui d'ALEX) : on
#     éprouve LE MÉCANISME EXACT dont sudo se sert — getpass, qui ouvre
#     /dev/tty et coupe l'écho par la discipline de ligne. Invite affichée,
#     mot de passe reçu, écho coupé : les trois, ou rien.
#
#  3. LE TROU DU FLUX. Première écriture des routes : /api/flux ne vérifiait
#     NI le jeton NI l'origine. Elle CRÉE un shell et déverse tout ce qu'il
#     écrit — c'est la plus sensible des quatre. Ça n'a pas été vu en
#     relisant le code, mais en éprouvant les QUATRE routes contre les TROIS
#     refus attendus. D'où la matrice complète plus bas, jamais un
#     échantillon.
#
#  4. LES ORPHELINS. Fermer un onglet pendant qu'un programme tourne ne doit
#     rien laisser derrière. MESURÉ : un travail lancé depuis le shell
#     interactif — au premier plan comme en fond — reçoit SON PROPRE groupe
#     de processus. Signaler le seul groupe du shell ne l'atteint donc pas
#     directement ; le contrôle vérifie le RÉSULTAT (plus de processus),
#     pas la méthode.
#
#  5. L'ÉCHO DU PTY PIÈGE LES ASSERTIONS. Un pty renvoie en écho la ligne
#     qu'on tape. Une première version de ce banc affirmait « le mot ABC
#     n'apparaît pas » après un Ctrl+C — il apparaissait toujours, comme
#     écho de la frappe, et le contrôle était rouge à tort. On compte donc
#     les occurrences : une = seulement l'écho, deux = la commande a tourné.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
LANCEUR="$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$BACKEND" "$LANCEUR"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 absent : ce banc ne peut rien éprouver"; exit 1
fi
#  Sans /dev/pts, rien de ce banc n'a de sens — et un vert obtenu sans pty
#  serait un mensonge. On le dit et on s'arrête, on ne « saute » pas.
if ! python3 -c "import os,pty; m,e=pty.openpty(); os.close(m); os.close(e)" 2>/dev/null; then
	echo "aucun pseudo-terminal disponible ici : ce banc ne peut rien éprouver"; exit 1
fi

#  ═══ « | rendu » PERD LE COMPTE, « < <(…) » NON ═══
#  Deuxième faux vert de ce banc, trouvé en le regardant tourner : avec
#  « lance x.py | rendu », le compteur vit dans un SOUS-SHELL — bash met le
#  membre droit d'un tuyau dans son propre processus, et ses variables
#  meurent avec lui. Vingt réussites et un échec s'affichaient bien à
#  l'écran, et le total annonçait « 2 réussis, 0 échoués » : le banc entier
#  pouvait devenir rouge sans jamais sortir en erreur. La substitution de
#  processus garde « rendu » dans le shell courant, donc le compte aussi.
lance() { python3 "$BANC/$1" "$BACKEND" 2>&1; }

#  ═══ UN CONTRÔLE QUI PLANTE EST UN ÉCHEC, PAS UN SILENCE ═══
#  Première version de ce banc : le fichier d'essai s'appelait « pty.py » et
#  masquait le module « pty » de Python. Les trois sections en question se
#  sont écrasées AVANT d'écrire le moindre verdict — et le total a annoncé
#  « 0 échoués », parce qu'on ne comptait que les lignes OK|/NON| et qu'il
#  n'y en avait aucune. Un banc vert sur un banc mort : exactement le faux
#  vert que ce dépôt traque. « rendu » exige donc désormais qu'il y ait des
#  verdicts, et transforme toute trace d'erreur en échec.
rendu() {
	local vus=0 titre_section="$1" ligne verdict message
	while IFS='|' read -r verdict message; do
		case "$verdict" in
			OK)  ok  "$message"; vus=$((vus+1)) ;;
			NON) non "$message"; vus=$((vus+1)) ;;
			*)
				ligne="$verdict$message"
				[ -n "$ligne" ] && printf '     %s\n' "$ligne"
				case "$ligne" in
					Traceback*|*Error:*|*Exception:*) vus=-1000 ;;
				esac
				;;
		esac
	done
	if [ "$vus" -le 0 ]; then
		non "« $titre_section » : aucun verdict rendu (le script d'essai s'est arrêté)"
	fi
}

# =============================================================================
titre "1. LE PTY : ce que « claude », « sudo », « nano » et « htop » exigent"
# =============================================================================
cat > "$BANC/session_pty.py" <<'PY'
import importlib.util, os, re, subprocess, sys, threading, time
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

class Volet:
    """Une session + un fil qui vide sa sortie en continu, comme le fait le
    flux SSE côté page."""
    def __init__(self, **kw):
        self.s = tp.Session(**kw)
        self.buf = bytearray()
        threading.Thread(target=self._lire, daemon=True).start()
        self.attend(b"$", 8) or self.attend(b"#", 2)
    def _lire(self):
        pos = 0
        while True:
            b, pos, fini = self.s.depuis(pos, 0.3)
            self.buf.extend(b)
            if fini: return
    def tape(self, t): self.s.ecrire(t if isinstance(t, bytes) else t.encode())
    def attend(self, motif, delai=8, fois=1):
        """« fois » n'est pas un raffinement : le pty RENVOIE EN ÉCHO la ligne
        tapée, donc tout mot de la commande apparaît une première fois sans
        que rien n'ait tourné. Attendre la première occurrence, c'est
        attendre l'écho. Deux = la commande a vraiment produit sa sortie."""
        t0 = time.time()
        while time.time() - t0 < delai:
            if bytes(self.buf).count(motif) >= fois: return True
            time.sleep(0.03)
        return False
    def vide(self): self.buf.clear()

v = Volet(cwd="/tmp", colonnes=80, lignes=24)

#  ═══ 1. UN VRAI TERMINAL ═══
#  « test -t 0 » est EXACTEMENT le isatty() que claude, sudo et tous les
#  programmes interactifs interrogent avant de décider s'ils démarrent.
v.tape("tty -s && echo A_UN_TTY; test -t 0 && echo ENTREE_TTY\n")
dit(v.attend(b"A_UN_TTY"), "le programme lancé a un vrai terminal de contrôle (tty)")
dit(v.attend(b"ENTREE_TTY"), "isatty() est VRAI sur son entrée — le verrou qui empêchait claude")

#  ═══ 2. TERM ET LA TAILLE ═══
v.vide(); v.tape("echo T=$TERM C=$(tput cols) L=$(tput lines)\n")
dit(v.attend(b"T=xterm-256color"), "TERM annonce xterm-256color (couleurs et dessins complets)")
dit(v.attend(b"C=80 L=24"), "le shell voit la taille demandée à l'ouverture (TIOCSWINSZ)")

#  ═══ 3. REDIMENSIONNEMENT — validation n° 7 ═══
v.vide(); v.s.redimensionner(132, 40)
v.tape("echo APRES=$(tput cols)x$(tput lines)\n")
dit(v.attend(b"APRES=132x40"), "redimensionner change la taille vue par le shell")

#  SIGWINCH pendant qu'un programme tourne : c'est ce qui fait que htop se
#  réajuste au lieu de dessiner à l'ancienne largeur.
v.vide(); v.tape('trap "echo VU_WINCH" WINCH; sleep 4\n')
time.sleep(0.7); v.s.redimensionner(100, 30)
dit(v.attend(b"VU_WINCH"), "SIGWINCH arrive au programme EN COURS (validation n° 7)")

#  ═══ 4. PLUS AUCUN DÉLAI — validation n° 9 ═══
#  L'ancien chemin tuait tout à 25 s. On dépasse volontairement cette borne :
#  une valeur plus courte ne prouverait rien.
#  On laisse d'abord retomber le « sleep 4 » du contrôle précédent : sinon
#  la commande suivante attend son tour dans le tampon du terminal et le
#  chronomètre mesure autre chose que ce qu'on croit.
v.attend(b"VU_WINCH", 8); time.sleep(3.5)
v.vide(); t0 = time.time()
v.tape("sleep 27 && echo VINGT_SEPT_SECONDES\n")
#  Deux occurrences : l'écho de la frappe, PUIS la sortie réelle. La
#  première version de ce contrôle n'en demandait qu'une — elle était donc
#  satisfaite par l'écho, en moins d'une seconde, et déclarait rouge un
#  code parfaitement correct.
vu = v.attend(b"VINGT_SEPT_SECONDES", 60, fois=2)
ecoule = time.time() - t0
dit(vu and ecoule > 25,
    "une commande de plus de 25 s n'est plus tuée (%.0f s, validation n° 9)" % ecoule)

#  ═══ 5. CTRL+C — validation n° 8 ═══
#  ATTENTION À L'ÉCHO : le pty renvoie la ligne tapée, donc le mot apparaît
#  une première fois SANS que la commande ait tourné. Une occurrence = écho
#  seul (interrompu) ; deux = la commande a bien affiché.
v.vide(); v.tape("sleep 40 && echo PAS_INTERROMPU\n")
time.sleep(0.9); v.tape("\x03"); time.sleep(0.6)
v.tape("echo VIVANT_APRES\n")
vivant = v.attend(b"VIVANT_APRES", 8, fois=2)
brut = bytes(v.buf)
dit(vivant and brut.count(b"PAS_INTERROMPU") == 1 and b"^C" in brut,
    "Ctrl+C interrompt la commande et la session survit (validation n° 8)")

#  ═══ 6. LE MOT DE PASSE — validation n° 5, déclarée bloquante ═══
#  getpass ouvre /dev/tty et coupe l'écho par la discipline de ligne : c'est
#  mot pour mot ce que fait sudo. Éprouver sudo lui-même est impossible ici
#  (pas de mot de passe connu) ; éprouver son mécanisme, non.
v.vide()
v.tape("""python3 -c 'import getpass; m=getpass.getpass("mot de passe : "); print("RECU=["+m+"]")'\n""")
dit(v.attend(b"mot de passe :"), "une invite de mot de passe s'affiche (validation n° 5)")
avant = bytes(v.buf)
v.tape("secret42\n")
recu = v.attend(b"RECU=[secret42]")
apres = bytes(v.buf)[len(avant):]
dit(recu, "le mot de passe tapé est reçu par le programme (validation n° 5)")
#  L'écho coupé n'est pas un détail : sans lui le mot de passe s'afficherait
#  en clair à l'écran, et resterait dans le journal du terminal.
dit(recu and b"secret42\r\n" not in apres.split(b"RECU=")[0],
    "l'écho est coupé pendant la saisie : le mot de passe ne s'affiche pas")

#  ═══ 7. DEUX VOLETS = DEUX SHELLS — validation n° 10 ═══
w = Volet(cwd="/etc")
v.vide(); w.vide()
v.tape("cd /usr; echo ICI_V=$PWD\n")
w.tape("echo ICI_W=$PWD\n")
dit(v.attend(b"ICI_V=/usr") and w.attend(b"ICI_W=/etc"),
    "deux volets ont chacun leur shell, « cd » indépendants (validation n° 10)")

#  ═══ 8. AUCUN ORPHELIN — validation n° 11 ═══
#  MESURÉ : un travail lancé depuis un shell interactif reçoit son PROPRE
#  groupe de processus, au premier plan comme en fond. On vérifie donc le
#  résultat (plus rien ne tourne), pas le signal envoyé.
x = Volet(cwd="/tmp")
x.tape("sleep 300 & echo FOND=$!\n"); x.attend(b"FOND=")
fond = int(re.search(rb"FOND=(\d+)", bytes(x.buf)).group(1))
x.tape("sleep 200\n"); time.sleep(0.9)
plan = [p for p in subprocess.run(["pgrep", "-P", str(x.s.pid), "-x", "sleep"],
                                  capture_output=True, text=True).stdout.split()
        if p != str(fond)]
dit(os.path.exists("/proc/%d" % fond) and bool(plan),
    "avant la fermeture, les deux programmes tournent bien (le contrôle a de quoi mordre)")
x.s.fermer()
t0 = time.time()
while time.time() - t0 < 8:
    if not os.path.exists("/proc/%d" % fond) and not any(os.path.exists("/proc/" + p) for p in plan):
        break
    time.sleep(0.05)
dit(not os.path.exists("/proc/%d" % fond) and not any(os.path.exists("/proc/" + p) for p in plan),
    "fermer le volet ne laisse AUCUN orphelin, ni au premier plan ni en fond (validation n° 11)")

#  ═══ 9. LE TAMPON EST BORNÉ ═══
#  Un htop laissé ouvert une nuit ne doit pas remplir la mémoire.
y = Volet(cwd="/tmp")
tp.TAMPON_MAX = 4096
y.tape("head -c 200000 /dev/zero | tr '\\0' 'z'\n")
time.sleep(3)
dit(len(y.s.tampon) <= 4096 + 65536 and y.s.perdus > 0,
    "le tampon d'une session est borné, l'élagage compte les octets jetés (%d gardés, %d jetés)"
    % (len(y.s.tampon), y.s.perdus))
#  Une position devenue trop ancienne ne doit pas planter : on remonte au
#  plus vieil octet encore là plutôt que de lever une erreur.
bloc, pos, _ = y.s.depuis(0, 0.1)
dit(pos == y.s.total, "une position périmée est remontée au plus ancien octet encore présent")

for volet in (v, w, x, y):
    volet.s.fermer()
PY
rendu "le pty" < <(lance session_pty.py)

# =============================================================================
titre "2. LES CINQ ROUTES ET LES TROIS SERRURES (matrice complète)"
# =============================================================================
cat > "$BANC/routes.py" <<'PY'
import importlib.util, json, os, re, sys, tempfile, time, urllib.error, urllib.request
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

#  ═══ AVANT TOUTE CHOSE : UN FOYER À NOUS, POUR TOUTE LA SONDE ═══
#  MESURÉ, et c'est la ONZIÈME fois que ce chantier se fait prendre à hériter
#  de son environnement. Cette sonde poste /api/reglages EN ÉCRITURE trois
#  fois (18 px, 13,3 px, 16 px) bien avant les sections qui, elles, épinglent
#  leur dossier. Le pont résolvait donc « terminal-pro.json » sous le foyer
#  HÉRITÉ. Semé {"taille": 11.0} dans le vrai ~/.config/lexos, banc lancé →
#  le fichier disait {"taille": 16.0}. Lancer ce banc changeait pour de bon la
#  taille du texte de celui qui le lance, et la LISAIT de lui.
#
#  ON ÉPINGLE EN HAUT, PAS SECTION PAR SECTION : c'est précisément le
#  pointillé qui a laissé passer celle-ci. Les sections qui épinglent déjà
#  leur propre dossier continuent de le faire et restaurent CELUI-CI, pas
#  celui de l'appelant — elles n'en deviennent que plus sûres.
#  HOME *ET* XDG_CONFIG_HOME, parce que le pont retombe sur « $HOME/.config »
#  quand la variable ne porte rien (c'est « dossier_theme() »).
__FOYER = tempfile.mkdtemp(prefix="pty-foyer-")
os.makedirs(os.path.join(__FOYER, ".config", "lexos"), exist_ok=True)
os.environ["HOME"] = __FOYER
os.environ["XDG_CONFIG_HOME"] = os.path.join(__FOYER, ".config")

srv, port, jeton = tp.demarrer_serveur()
base = "http://127.0.0.1:%d" % port
BON = {"X-Lexos-Jeton": jeton, "Origin": base, "Content-Type": "application/json"}

def appel(route, entetes, methode="POST", corps=b'{"fen":"z"}', delai=5):
    req = urllib.request.Request(base + route,
                                 data=(corps if methode == "POST" else None),
                                 headers=entetes, method=methode)
    try:
        r = urllib.request.urlopen(req, timeout=delai)
        return r.getcode(), r
    except urllib.error.HTTPError as e:
        return e.code, e
    except Exception as e:
        #  ═══ UN HOQUET DE TRANSPORT NE DOIT PAS EMPORTER LES AUTRES ═══
        #  CE QUI EST ARRIVÉ EN CI : un POST sur « /api/inventee » est mort en
        #  « BadStatusLine: {"ok": false, "erreur": "inconnu"} » — et comme
        #  l'exception remontait, le script s'arrêtait là et VINGT-TROIS
        #  verdicts déjà acquis étaient perdus d'un coup. « rendu » a bien dit
        #  « aucun verdict rendu », ce qui est honnête, mais ne disait pas QUOI.
        #  On rend donc la panne comme un code : le point qui l'attrape échoue
        #  seul, avec sa raison, et les vingt-deux autres se prononcent.
        return ("transport", type(e).__name__, str(e)[:70]), None

#  ═══ LA MATRICE : 4 routes × 3 refus. Un échantillon ne suffit pas — c'est
#  précisément la route qu'on n'avait pas essayée (/api/flux) qui était
#  ouverte à tout le monde.
#  /api/theme est ENTRÉE DANS LA MATRICE, elle n'est pas posée à côté : c'est
#  exactement la faute qu'avait faite /api/flux, écrite sans serrure et vue
#  seulement le jour où la matrice a été complétée.
ROUTES = (("/api/flux?fen=z", "GET"), ("/api/saisie", "POST"),
          ("/api/taille", "POST"), ("/api/fermer", "POST"),
          ("/api/theme", "GET"))
REFUS = (("sans jeton", {"Origin": base}),
         ("jeton faux", {"X-Lexos-Jeton": "pas-le-bon", "Origin": base}),
         ("origine étrangère", {"X-Lexos-Jeton": jeton, "Origin": "http://mechant.example"}))
for nom, entetes in REFUS:
    for route, methode in ROUTES:
        code, _ = appel(route, dict(entetes, **{"Content-Type": "application/json"}), methode)
        dit(code == 403, "%s → %s : refusé (%s)" % (route, nom, code))

#  Le jeton doit être comparé en temps constant, pas avec « == » : sinon la
#  durée de la réponse laisse deviner le préfixe correct, caractère par
#  caractère.
import inspect
source = inspect.getsource(tp.Handler._autorise)
dit("compare_digest" in source, "le jeton est comparé en temps constant (compare_digest)")

#  ═══ ET LE CHEMIN NORMAL PASSE ═══
code, _ = appel("/api/saisie", BON)
dit(code == 404, "avec le bon jeton, une session absente répond 404 (pas 403)")

#  Le flux crée la session, la saisie l'atteint, la sortie revient.
import base64, threading
recu = bytearray()
def ecoute():
    code, r = appel("/api/flux?fen=vrai&cwd=/tmp&colonnes=80&lignes=24", BON, "GET", delai=20)
    if code != 200: return
    for ligne in r:
        if ligne.startswith(b"data: "):
            recu.extend(base64.b64decode(ligne[6:].strip()))
threading.Thread(target=ecoute, daemon=True).start()
time.sleep(1.5)
code, r = appel("/api/saisie", BON, corps=json.dumps({"fen": "vrai", "texte": "echo BOUT_EN_BOUT\n"}).encode())
t0 = time.time()
while time.time() - t0 < 8 and b"BOUT_EN_BOUT" not in bytes(recu): time.sleep(0.05)
#  Deux occurrences : l'écho de la frappe, puis la sortie réelle. Une seule
#  voudrait dire que le shell n'a rien exécuté.
dit(bytes(recu).count(b"BOUT_EN_BOUT") >= 2,
    "flux + saisie : la frappe atteint le shell et sa sortie revient par le flux")

#  Un accent doit traverser intact : c'est tout l'intérêt du base64 dans le
#  sens descendant (les blocs de 64 ko coupent au hasard, y compris au
#  milieu d'un caractère UTF-8).
recu.clear()
appel("/api/saisie", BON, corps=json.dumps({"fen": "vrai", "texte": "printf 'ACCENT:éàü🙂\\n'\n"}).encode())
t0 = time.time()
while time.time() - t0 < 8 and "ACCENT:éàü🙂".encode() not in bytes(recu): time.sleep(0.05)
dit("ACCENT:éàü🙂".encode() in bytes(recu),
    "accents et emoji traversent le flux intacts (base64, pas de décodage par bloc)")

code, _ = appel("/api/taille", BON, corps=json.dumps({"fen": "vrai", "colonnes": 111, "lignes": 33}).encode())
s = tp.session_de("vrai")
dit(code == 200 and s is not None and s.colonnes == 111 and s.lignes == 33,
    "/api/taille redimensionne bien la session")

code, r = appel("/api/fermer", BON, corps=json.dumps({"fen": "vrai"}).encode())
dit(code == 200 and tp.session_de("vrai") is None, "/api/fermer retire la session du registre")

#  Une route inventée ne doit pas retomber sur le service de fichiers.
code, _ = appel("/api/inventee", BON)
dit(code == 404, "une route POST inconnue répond 404 (reçu %r)" % (code,))
code, _ = appel("/api/inventee", BON, "GET")
dit(code == 404, "une route GET inconnue sous /api/ répond 404, sans servir de fichier")

#  ═══ LES RÉGLAGES : CE QU'ALEX CHOISIT DOIT SURVIVRE À UNE RELANCE ═══
#  LE DÉFAUT, MESURÉ. La page rangeait la taille du texte dans le
#  localStorage, cloisonné PAR ORIGINE ; or le pont se lie au port 0, donc le
#  système lui donne un port éphémère DIFFÉRENT à chaque lancement (deux
#  tirages mesurés : 42839 puis 57411). Taille posée à 18,5, pont relancé →
#  retour à 12,5. Relancé sur le MÊME port, elle revenait : c'est bien le
#  cloisonnement, pas une écriture ratée.
#  Le réglage vit donc dans la configuration de LexOS. Ce que ces points
#  éprouvent, c'est le MAGASIN : les bornes, l'arrondi, les deux serrures, et
#  surtout qu'un échec d'écriture se DISE au lieu de s'inventer un succès.
code, j = appel("/api/reglages", BON, "GET")
dit(code == 200 and j is not None, "/api/reglages se lit (reçu %r)" % (code,))
LU = json.loads(j.read()) if (code == 200 and j is not None) else {}
dit(LU.get("taille_min") == 7 and LU.get("taille_max") == 32
    and LU.get("taille_defaut") == 12.5,
    "…et il PORTE ses bornes et son défaut (%r à %r, défaut %r) — la page les "
    "reçoit au lieu de les réécrire de son côté"
    % (LU.get("taille_min"), LU.get("taille_max"), LU.get("taille_defaut")))

def regler(valeur, entetes=BON):
    c, r = appel("/api/reglages", entetes, corps=json.dumps({"taille": valeur}).encode())
    try:
        return c, json.loads(r.read()) if r is not None else {}
    except Exception:
        return c, {}

code, rep = regler(18)
dit(code == 200 and rep.get("reglages", {}).get("taille") == 18.0,
    "une taille valide s'enregistre et se relit (reçu %r, %r)"
    % (code, rep.get("reglages")))
code, rep = regler(13.3)
dit(rep.get("reglages", {}).get("taille") == 13.5,
    "…arrondie au demi-point par le PONT, pas par la page (13,3 → %r)"
    % (rep.get("reglages", {}).get("taille"),))

#  LE PONT NE FAIT PAS CONFIANCE À LA PAGE. Chacune de ces valeurs est un
#  refus, et le refus DIT les bornes : une page qui reçoit « non » sans savoir
#  pourquoi retentera la même chose indéfiniment.
REFUSES = []
for MAUVAIS in (99, 2, "grand", None, [14], {"a": 1}, True, 1e308):
    c, rep = regler(MAUVAIS)
    if not (c == 400 and "bornes" in str(rep.get("erreur", ""))):
        REFUSES.append((MAUVAIS, c, rep.get("erreur")))
dit(not REFUSES,
    "huit tailles aberrantes sont refusées en 400 AVEC leurs bornes "
    "(passées à travers : %r)" % (REFUSES[:2],))
#  Et aucune ne doit avoir ABÎMÉ ce qui était rangé.
code, rep = regler(16)
dit(rep.get("reglages", {}).get("taille") == 16.0,
    "…et le magasin est intact après les refus (%r)"
    % (rep.get("reglages", {}).get("taille"),))

#  LES DEUX SERRURES, ICI AUSSI. /api/flux avait été écrite sans, et ça ne
#  s'est vu qu'en éprouvant la matrice complète : ces deux routes-ci entrent
#  dans la même exigence, elles ne sont pas posées à côté.
code, _ = appel("/api/reglages", {"Content-Type": "application/json"},
                corps=b'{"taille": 20}')
dit(code == 403, "POST /api/reglages sans jeton : refusé (reçu %r)" % (code,))
code, _ = appel("/api/reglages", dict(BON, **{"Origin": "http://mechant.example"}),
                corps=b'{"taille": 20}')
dit(code == 403, "POST /api/reglages sur une origine étrangère : refusé (reçu %r)" % (code,))
code, _ = appel("/api/reglages", {}, "GET")
dit(code == 403, "GET /api/reglages sans jeton : refusé (reçu %r)" % (code,))

#  ═══ UN ÉCHEC D'ÉCRITURE SE DIT ═══
#  La consigne du projet est explicite : jamais une valeur inventée, jamais un
#  échec muet. On met donc un FICHIER là où le dossier devrait être — makedirs
#  échoue alors même pour root, ce qu'un simple chmod ne garantit pas.
__d = tempfile.mkdtemp()
open(os.path.join(__d, "lexos"), "w").write("je ne suis pas un dossier")
__avant = os.environ.get("XDG_CONFIG_HOME")
os.environ["XDG_CONFIG_HOME"] = __d
code, rep = regler(15)
dit(code == 500 and "non enregistr" in str(rep.get("erreur", "")),
    "un dossier de configuration inutilisable rend 500 ET sa raison "
    "(reçu %r : %r)" % (code, rep.get("erreur")))
dit(tp.lire_reglages() == {},
    "…et la LECTURE se dégrade sans lever, pour que le terminal s'ouvre quand même")
if __avant is None:
    os.environ.pop("XDG_CONFIG_HOME", None)
else:
    os.environ["XDG_CONFIG_HOME"] = __avant

#  ═══ LE MENU LANCE LA COMMANDE DU SYSTÈME, ET RIEN D'AUTRE ═══
#  ALEX : « aimerai on metre en haut de la fenetre capable de changer les
#  couleur du terminal ». Le menu ne peint rien lui-même : il lance
#  « lexos-terminal jour|nuit|auto ». terminal.env reste la seule source de
#  couleur de tout LexOS, et une page qui se peindrait elle-même dirait dès le
#  premier clic le contraire de tous les autres terminaux.
#
#  CE QUE CES POINTS GARDENT. La table est FERMÉE et les arguments sont des
#  LITTÉRAUX : la page n'envoie qu'une CLEF, et rien de ce qu'elle dit
#  n'atteint jamais argv. Pas de shell=True, pas de concaténation — il n'y a
#  rien à échapper puisqu'il n'y a rien de variable. On le MESURE en poussant
#  des clefs hostiles, « jour; rm -rf / » comprise.
dit(sorted(tp._MODES_COMMANDE) == ["auto", "jour", "nuit"],
    "la table des commandes est fermée à trois modes (%r)"
    % (sorted(tp._MODES_COMMANDE),))
dit(all(isinstance(v, tuple) and v[0] == "lexos-terminal" and len(v) == 2
        for v in tp._MODES_COMMANDE.values()),
    "…et chaque entrée est un argv LITTÉRAL de deux éléments, jamais une chaîne "
    "de shell (%r)" % (sorted(tp._MODES_COMMANDE.values()),))

HOSTILES = []
for __CLEF in ("accent", "jour; rm -rf /", "jour && reboot", "../../bin/sh",
               "$(id)", "`id`", "jour nuit", "JOUR", "", None, 42, ["jour"],
               {"mode": "jour"}, "jour\n", " jour"):
    __ok, __dit = tp.lancer_mode(__CLEF)
    if __ok or "inconnu" not in __dit:
        HOSTILES.append((__CLEF, __ok, __dit))
dit(not HOSTILES,
    "quinze clefs hostiles sont toutes refusées « mode inconnu » — y compris "
    "« jour; rm -rf / » (passées à travers : %r)" % (HOSTILES[:2],))

#  ═══ ET LA COMMANDE MARCHE VRAIMENT ═══
#  La MÉCANIQUE est éprouvée ici, séparément de la POLITIQUE : le refus de
#  tourner en root appartient à la route, et ce banc tourne EN root sur le
#  coureur. Sans cette séparation, le chemin du succès ne serait mesuré nulle
#  part en CI.
#  ⚠ ON ÉPINGLE XDG_CONFIG_HOME : sinon cette sonde réécrirait le thème de la
#  machine qui fait tourner le banc. Sixième fois que ce chantier doit s'en
#  souvenir.
#  ⚠ HOME *ET* XDG_CONFIG_HOME, ÉPINGLÉS AU MÊME DOSSIER. Les deux, parce que
#  les deux outils en jeu ne lisent pas le même : lexos-terminal écrit son mode
#  dans « ${XDG_CONFIG_HOME:-$HOME/.config}/lexos » tandis que lexos-theme-gen
#  régénère terminal.env sous « $TARGET/.config » et ne suit pas la variable
#  (c'est écrit en tête du générateur, avec la mesure qui dit pourquoi le lui
#  faire suivre à moitié était pire que de ne pas le faire).
#  N'épingler que la variable faisait donc atterrir terminal-mode dans le
#  dossier du banc et terminal.env dans le HOME de l'appelant : lire_theme()
#  rendait {} et deux points rougissaient sur du code juste. Mesuré.
#  Les pointer sur le MÊME dossier met les deux outils d'accord, qui est
#  exactement la configuration livrée.
__MAISON = tempfile.mkdtemp()
__CONF = os.path.join(__MAISON, ".config")
os.makedirs(__CONF, exist_ok=True)
__GARDE = os.environ.get("XDG_CONFIG_HOME")
__GARDE_HOME = os.environ.get("HOME")
os.environ["XDG_CONFIG_HOME"] = __CONF
os.environ["HOME"] = __MAISON
#  ⚠ ET LE PATH : « lexos-terminal » n'est pas installé sur le coureur, il est
#  DANS LE DÉPÔT. Sans cette ligne les trois points ci-dessous rougissaient en
#  « Indisponible : « lexos-terminal » est introuvable dans le PATH » — ce qui
#  est le bon message, mais pour la mauvaise raison. On le pointe donc sur
#  l'arbre, comme les autres bancs de ce dépôt le font déjà.
__BIN = os.path.dirname(sys.argv[1]).replace("/lib/lexos", "/bin")
__PATH_GARDE = os.environ.get("PATH", "")
os.environ["PATH"] = __BIN + os.pathsep + __PATH_GARDE
__VUS = []
for __M, __ATTENDU in (("nuit", "nuit"), ("jour", "jour"), ("auto", "auto")):
    __ok, __dit = tp.lancer_mode(__M)
    #  Le mode CHOISI, pas le mode résolu : après « auto », terminal.env porte
    #  LEXOS_TERM_MODE=nuit ET _EFFECTIF=nuit — lexos-theme-gen RÉSOUT « auto »
    #  avant d'écrire. Le choix est dans « terminal-mode », et c'est lui que le
    #  menu doit cocher. Mesuré : cocher sur LEXOS_TERM_MODE faisait cocher
    #  « Nuit » juste après un clic sur « Auto ».
    __VUS.append((__M, __ok, tp.lire_mode_choisi(), __dit[:40]))
dit(all(v[1] and v[2] == v[0] for v in __VUS),
    "« lexos-terminal jour|nuit|auto » tourne et le mode CHOISI est relu tel "
    "quel (%r)" % (__VUS,))
dit(bool(tp.lire_theme().get("LEXOS_TERM_PALETTE")),
    "…et le thème est régénéré derrière, palette comprise")
#  « auto » est RÉSOLU dans terminal.env : c'est exactement pourquoi le menu ne
#  peut pas s'y fier.
tp.lancer_mode("auto")
dit(tp.lire_mode_choisi() == "auto"
    and tp.lire_theme().get("LEXOS_TERM_EFFECTIF") in ("jour", "nuit"),
    "après « auto », le choix reste « auto » mais l'effectif est résolu (%r / %r)"
    % (tp.lire_mode_choisi(), tp.lire_theme().get("LEXOS_TERM_EFFECTIF")))

#  ═══ terminal.env SE TROUVE DANS LES DEUX RACINES ═══
#  SIGNALÉ PAR UNE RELECTURE (Codex, P2), puis reproduit ici. lexos-terminal
#  écrit son mode dans « ${XDG_CONFIG_HOME:-$HOME/.config}/lexos » et honore
#  donc la variable ; lexos-theme-gen régénère terminal.env sous
#  « $TARGET/.config » et ne l'honore PAS. Pour qui pose la variable ailleurs
#  que $HOME/.config, « lexos terminal nuit » réussissait, écrivait
#  terminal-mode dans le dossier de la variable, et /api/mode rendait un thème
#  VIDE — alors que cette route PROMET le thème frais.
#  C'est donc le LECTEUR qui cède, et c'est le bon sens de la concession : lire
#  un fichier là où il est ne casse rien, tandis que déplacer ce que le
#  générateur écrit a déjà cassé deux choses (voir l'en-tête du générateur).
#  CE POINT ÉPROUVE LA RÈGLE, PAS UN CAS : les deux racines séparément, ET la
#  préséance quand les deux ont un fichier.
__RT = tempfile.mkdtemp()
__RG = (os.environ.get("HOME"), os.environ.get("XDG_CONFIG_HOME"))
__ECARTS = []

#  a) le fichier SOUS HOME, la variable ailleurs et vide → on le trouve.
os.environ["HOME"] = os.path.join(__RT, "a")
os.environ["XDG_CONFIG_HOME"] = os.path.join(__RT, "a-var")
os.makedirs(os.path.join(__RT, "a", ".config", "lexos"), exist_ok=True)
os.makedirs(os.environ["XDG_CONFIG_HOME"], exist_ok=True)
with open(os.path.join(__RT, "a", ".config", "lexos", "terminal.env"), "w") as __f:
    __f.write("LEXOS_TERM_EFFECTIF=nuit\nLEXOS_TERM_BG=#000000\n")
if tp.lire_theme().get("LEXOS_TERM_BG") != "#000000":
    __ECARTS.append("sous HOME : non trouvé")

#  b) le fichier DANS LA VARIABLE → on le trouve aussi.
os.environ["HOME"] = os.path.join(__RT, "b")
os.environ["XDG_CONFIG_HOME"] = os.path.join(__RT, "b-var")
os.makedirs(os.path.join(__RT, "b-var", "lexos"), exist_ok=True)
with open(os.path.join(__RT, "b-var", "lexos", "terminal.env"), "w") as __f:
    __f.write("LEXOS_TERM_EFFECTIF=jour\nLEXOS_TERM_BG=#F7F5F0\n")
if tp.lire_theme().get("LEXOS_TERM_BG") != "#F7F5F0":
    __ECARTS.append("dans la variable : non trouvé")

#  c) LES DEUX EN ONT UN → la VARIABLE gagne, parce que c'est là que tous les
#     lecteurs de LexOS regardent.
os.environ["HOME"] = os.path.join(__RT, "c")
os.environ["XDG_CONFIG_HOME"] = os.path.join(__RT, "c-var")
os.makedirs(os.path.join(__RT, "c", ".config", "lexos"), exist_ok=True)
os.makedirs(os.path.join(__RT, "c-var", "lexos"), exist_ok=True)
with open(os.path.join(__RT, "c", ".config", "lexos", "terminal.env"), "w") as __f:
    __f.write("LEXOS_TERM_BG=#111111\n")
with open(os.path.join(__RT, "c-var", "lexos", "terminal.env"), "w") as __f:
    __f.write("LEXOS_TERM_BG=#222222\n")
if tp.lire_theme().get("LEXOS_TERM_BG") != "#222222":
    __ECARTS.append("les deux : la variable ne gagne pas (%r)"
                    % (tp.lire_theme().get("LEXOS_TERM_BG"),))

#  d) AUCUN des deux → {} , et surtout pas une levée.
os.environ["HOME"] = os.path.join(__RT, "d")
os.environ["XDG_CONFIG_HOME"] = os.path.join(__RT, "d-var")
try:
    if tp.lire_theme() != {}:
        __ECARTS.append("aucun des deux : devrait rendre {}")
except Exception as __e:
    __ECARTS.append("aucun des deux : LÈVE " + type(__e).__name__)

dit(not __ECARTS,
    "terminal.env est trouvé sous HOME comme dans XDG_CONFIG_HOME, la variable "
    "gagne quand les deux en ont un, et l'absence rend {} sans lever "
    "(écarts : %r)" % (__ECARTS,))
if __RG[0] is not None:
    os.environ["HOME"] = __RG[0]
if __RG[1] is None:
    os.environ.pop("XDG_CONFIG_HOME", None)
else:
    os.environ["XDG_CONFIG_HOME"] = __RG[1]

#  ═══ DES OCTETS ILLISIBLES NE DOIVENT PAS FAIRE MENTIR LA ROUTE ═══
#  RETENU PAR LA RELECTURE (0 réfutation sur 3), et c'est l'ORDRE qui rend le
#  défaut grave : lexos-terminal écrit son mode, appelle le générateur — qui
#  réécrit terminal.env — ET SEULEMENT ENSUITE imprime sa confirmation. Un
#  octet non-UTF-8 dans cette ligne (le script SOURCE des fichiers de $HOME et
#  en recrache les valeurs) faisait lever « text=True », qui décode en strict.
#  Mon premier correctif attrapait l'exception pour rendre un ÉCHEC : la page
#  annonçait alors « la couleur n'a pas changé » alors qu'elle venait de
#  changer, et ne repeignait pas — la fenêtre restait en nuit pendant que
#  l'invite, lexfetch, tmux et xfce4-terminal étaient passés en jour.
#  « errors="replace" » est la bonne réponse : la commande a RÉUSSI.
__SB = tempfile.mkdtemp()
with open(os.path.join(__SB, "lexos-terminal"), "w", encoding="utf-8") as __f:
    __f.write(
        '#!/usr/bin/env bash\n'
        '#  Fidèle à l\'ORDRE du vrai : il change le thème, PUIS imprime — et\n'
        '#  sa confirmation porte un octet non-UTF-8 (0xFF).\n'
        'CONF="${XDG_CONFIG_HOME:-$HOME/.config}/lexos"; mkdir -p "$CONF"\n'
        'printf jour > "$CONF/terminal-mode"\n'
        'cat > "$CONF/terminal.env" <<EOF\n'
        'LEXOS_TERM_EFFECTIF=jour\n'
        'LEXOS_TERM_BG=#F7F5F0\n'
        'LEXOS_TERM_FG=#0B6B3A\n'
        'LEXOS_TERM_TEXTE=#1B1A17\n'
        'LEXOS_TERM_CURSEUR=#A84007\n'
        'EOF\n'
        "printf '\\xe2\\x9c\\x93 Terminal de jour \\xff illisible\\n'\n")
os.chmod(os.path.join(__SB, "lexos-terminal"), 0o755)
__PG2 = os.environ["PATH"]
os.environ["PATH"] = __SB + os.pathsep + __PG2
tp._outils.oublier()
__OK, __DIT = tp.lancer_mode("jour")
__T = tp.lire_theme()
dit(__OK is True and "Terminal de jour" in __DIT
    and __T.get("LEXOS_TERM_EFFECTIF") == "jour",
    "une commande qui réussit en crachant un octet illisible reste un SUCCÈS, "
    "son message est décodé en perte, et le thème est relu (ok=%r, dit=%r)"
    % (__OK, __DIT[:46]))
os.environ["PATH"] = __PG2
tp._outils.oublier()

#  ═══ « INDISPONIBLE » ET SA RAISON, PLUTÔT QU'UN SUCCÈS INVENTÉ ═══
#  La consigne du projet l'exige : si une action est impossible, on le dit et
#  on dit pourquoi — jamais une valeur inventée, jamais un échec muet. On
#  retire donc « lexos-terminal » du PATH et on regarde ce qui sort.
os.environ["PATH"] = "/nulle/part"
#  ⚠ ET IL FAUT LE FAIRE OUBLIER, sinon ce point est INSTABLE. Le pont passe
#  par moteur/outils.chemin(), qui garde sa réponse trente secondes : les
#  appels ci-dessus viennent de mettre « lexos-terminal » en mémoire, donc
#  sans cet oubli le pont le trouverait encore malgré le PATH vide, et ce
#  point passerait ou échouerait selon l'HEURE. Mesuré en l'oubliant et en ne
#  l'oubliant pas.
tp._outils.oublier()
__ok, __dit = tp.lancer_mode("nuit")
dit(not __ok and "Indisponible" in __dit and "lexos-terminal" in __dit
    and "PATH" in __dit,
    "sans « lexos-terminal » dans le PATH : « Indisponible » AVEC sa raison, "
    "pas un succès inventé (« %s »)" % (__dit,))
os.environ["PATH"] = __BIN + os.pathsep + __PATH_GARDE
tp._outils.oublier()

#  ═══ LA ROUTE : LES DEUX SERRURES, ET LA POLITIQUE ═══
def mode_route(corps, entetes=BON):
    c, r = appel("/api/mode", entetes, corps=json.dumps(corps).encode(), delai=40)
    try:
        return c, (json.loads(r.read()) if r is not None else {})
    except Exception:
        return c, {}

code, _ = mode_route({"mode": "nuit"}, {"Content-Type": "application/json"})
dit(code == 403, "POST /api/mode sans jeton : refusé (reçu %r)" % (code,))
code, _ = mode_route({"mode": "nuit"},
                     dict(BON, **{"Origin": "http://mechant.example"}))
dit(code == 403, "POST /api/mode sur une origine étrangère : refusé (reçu %r)" % (code,))
code, rep = mode_route({"mode": "accent"})
dit(code == 400 and "inconnu" in str(rep.get("erreur", "")),
    "un mode inconnu est refusé par la ROUTE aussi (reçu %r : %r)"
    % (code, rep.get("erreur")))

#  ═══ UN « mode » NON HACHABLE NE DOIT PAS TUER LA RÉPONSE ═══
#  TROUVÉ PAR UNE RELECTURE INDÉPENDANTE, puis reproduit ici. La route validait
#  par « mode not in _MODES_COMMANDE » — une appartenance à un DICT, qui exige
#  une clef hachable. Avec {"mode": []} ou {"mode": {"jour": 1}}, Python lève
#  « TypeError: unhashable type », l'exception traverse do_POST, socketserver
#  ferme la prise, et le client reçoit ZÉRO octet au lieu du 400. Mesuré contre
#  le pont réel : « RemoteDisconnected: Remote end closed connection without
#  response » pour les trois formes non hachables.
#  ⚠ lancer_mode() avait BIEN son isinstance(mode, str) : c'est la ROUTE qui
#  validait autrement. Deux écritures d'une même règle, et c'est la seconde qui
#  a cédé — exactement la faute que ce dépôt traque partout ailleurs. Ce point
#  interroge donc la ROUTE, pas la mécanique.
MUETS = []
for FORME in ([], {"jour": 1}, ["jour"], None, 3, True, "JOUR", {}, [[]]):
    c, rep = mode_route({"mode": FORME})
    if not (c == 400 and "inconnu" in str(rep.get("erreur", ""))):
        MUETS.append((FORME, c, rep.get("erreur")))
dit(not MUETS,
    "neuf formes de « mode » hostiles — listes et dictionnaires compris — "
    "reçoivent toutes un 400 AVEC sa raison, aucune ne ferme la prise en "
    "silence (passées à travers : %r)" % (MUETS[:2],))

#  ═══ JAMAIS EN ROOT, ET LE REFUS DIT POURQUOI ═══
#  Ce point mesure DEUX choses selon qui lance le banc, et le dit. En root —
#  le cas du coureur — on exige le refus AVEC sa raison : en root le thème
#  changé serait celui de root, donc l'action aurait l'air d'avoir marché sans
#  rien changer pour Alex. Autrement, on exige qu'elle marche.
code, rep = mode_route({"mode": "nuit"})
if os.geteuid() == 0:
    dit(code == 403 and "root" in str(rep.get("erreur", "")),
        "lancé EN ROOT : la route refuse de changer le thème ET dit pourquoi "
        "(reçu %r : %r)" % (code, rep.get("erreur")))
else:
    dit(code == 200 and rep.get("mode_choisi") == "nuit"
        and bool(rep.get("theme")),
        "lancé en utilisateur : la route pose le mode et REND le thème frais "
        "pour que la page repeigne sans second aller-retour (reçu %r)" % (code,))
if __GARDE is None:
    os.environ.pop("XDG_CONFIG_HOME", None)
else:
    os.environ["XDG_CONFIG_HOME"] = __GARDE
if __GARDE_HOME is not None:
    os.environ["HOME"] = __GARDE_HOME
os.environ["PATH"] = __PATH_GARDE

#  ═══ UN FICHIER DE RÉGLAGES HOSTILE NE DOIT PAS ÊTRE SANS RETOUR ═══
#  TROUVÉ PAR UNE RELECTURE INDÉPENDANTE, puis reproduit ici. Un entier JSON
#  trop grand pour un double — 400 chiffres, ou 2**1024 — fait lever
#  « OverflowError: int too large to convert to float » à float(), et
#  OverflowError n'hérite ni de TypeError ni de ValueError. L'exception
#  traversait lire_reglages() et la route : « GET /api/reglages » fermait la
#  prise sans un octet.
#  ET C'ÉTAIT SANS RETOUR, ce qui est le pire : la page ne pouvait plus ni
#  lire ni écrire le réglage, donc plus réparer le fichier par où elle l'avait
#  écrit. Ce point exige les deux : que la lecture se dégrade, ET qu'une
#  écriture REMETTE le fichier d'aplomb.
import json as _json
__CONF2 = tempfile.mkdtemp()
__G2 = os.environ.get("XDG_CONFIG_HOME")
os.environ["XDG_CONFIG_HOME"] = __CONF2
os.makedirs(os.path.join(__CONF2, "lexos"), exist_ok=True)
__JSON = os.path.join(__CONF2, "lexos", "terminal-pro.json")
__SURVIVANTS = []
#  ⚠ LES DEUX DERNIERS VIENNENT D'UNE RELECTURE (Codex, P2), et ils manquaient
#  à cette liste. Un terminal-pro.json PROFONDÉMENT IMBRIQUÉ et un fichier
#  ÉNORME passaient la lecture (qui rendait {}) mais tuaient l'ÉCRITURE —
#  RecursionError pour l'un, et pour l'autre les 200 Kio étaient rechargés puis
#  réécrits, donc conservés à jamais. Le fichier que la lecture tolérait,
#  l'écriture ne pouvait donc pas le réparer : or c'est par l'écriture que la
#  page répare. Les deux chemins passent désormais par la MÊME lecture.
for __POISON in ('{"taille": %s}' % ("9" * 400), '{"taille": %d}' % (2 ** 1024),
                 '{"taille": [1]}', '{"taille": {"a": 1}}', '[]', 'null',
                 'pas du json', '', '{"taille": 1e400}',
                 '{"taille": ' + '[' * 2000 + ']' * 2000 + '}',
                 '{"bourre": "' + "x" * 200000 + '", "taille": 14}'):
    with open(__JSON, "w", encoding="utf-8") as __f:
        __f.write(__POISON)
    try:
        __lu = tp.lire_reglages()
    except Exception as __e:
        __SURVIVANTS.append((__POISON[:18], "lecture lève " + type(__e).__name__))
        continue
    __c, __r = appel("/api/reglages", BON, "GET")
    if __c != 200:
        __SURVIVANTS.append((__POISON[:18], "GET rend %r" % (__c,)))
        continue
    __c, __r = appel("/api/reglages", BON,
                     corps=_json.dumps({"taille": 15}).encode())
    if __c != 200:
        __SURVIVANTS.append((__POISON[:18], "réparation rend %r" % (__c,)))
dit(not __SURVIVANTS,
    "onze fichiers de réglages hostiles — imbrication profonde et 200 Kio "
    "compris : la lecture se dégrade, la route répond, et une écriture REMET "
    "le fichier d'aplomb. Aucun n'est sans retour (restés coincés : %r)"
    % (__SURVIVANTS[:2],))
if __G2 is None:
    os.environ.pop("XDG_CONFIG_HOME", None)
else:
    os.environ["XDG_CONFIG_HOME"] = __G2

#  ═══ LES DEUX ÉCRITURES DES BORNES DOIVENT S'ACCORDER ═══
#  La page porte un REPLI (let TAILLE_DEFAUT = 12,5, MIN = 7, MAX = 32) qui ne
#  sert qu'en mode démonstration, là où il n'y a pas de pont à interroger. Si
#  ce repli dérivait, la démonstration laisserait choisir une taille que le
#  pont refuserait d'enregistrer — et personne ne le verrait, puisque les deux
#  chemins ne se croisent jamais.
#  C'est la faute que ce dépôt a déjà payée plusieurs fois sur les couleurs :
#  deux écritures d'une même valeur finissent toujours par diverger.
#  argv[1] = …/usr/lib/lexos/terminal-pro.py : trois dirname pour atteindre
#  « usr », d'où « share/lexos/terminal-pro/web ».
__PAGE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(sys.argv[1]))),
                      "share", "lexos", "terminal-pro", "web", "index.html")
try:
    __SRC = open(__PAGE, encoding="utf-8").read()
except OSError as __e:
    __SRC = ""
    dit(False, "la page est introuvable (%s) — l'accord des bornes n'a PAS été "
               "vérifié" % (__e,))
if __SRC:
    __M = re.search(r"let TAILLE_DEFAUT = ([\d.]+), TAILLE_MIN = ([\d.]+), "
                    r"TAILLE_MAX = ([\d.]+);", __SRC)
    if __M is None:
        #  ON NE CONCLUT PAS QUAND ON N'A PAS PU LIRE.
        dit(False, "les bornes de repli de la page ne se lisent plus sous cette "
                   "forme — l'accord n'a PAS été vérifié, corrigez ce contrôle")
    else:
        __d, __mn, __mx = (float(__M.group(1)), float(__M.group(2)),
                           float(__M.group(3)))
        dit((__mn, __mx, __d) == (tp.TAILLE_MIN, tp.TAILLE_MAX, tp.TAILLE_DEFAUT),
            "le repli de la page s'accorde au pont (page %g/%g/%g, pont %g/%g/%g)"
            % (__mn, __mx, __d, tp.TAILLE_MIN, tp.TAILLE_MAX, tp.TAILLE_DEFAUT))

#  ═══ LE PONT FINIT DE LIRE LA REQUÊTE AVANT D'Y RÉPONDRE ═══
#  LE DÉFAUT, MESURÉ : les chemins d'erreur — route inconnue, origine
#  refusée, jeton invalide — répondaient SANS avoir lu le corps. Les octets
#  non lus restent dans la file de réception ; à la fermeture le noyau envoie
#  un RST au lieu d'un FIN, et le client PERD la réponse déjà reçue.
#  Mesuré sur ce pont, 12 POST par cas : corps de 11 octets → 12 sains ;
#  corps d'1 Mio → 10 sains et 2 « Broken pipe » sur la route inconnue, 11 et
#  10 sur les chemins 403. Après le correctif : 12 sains partout.
#  POURQUOI UN GROS CORPS. Avec onze octets le défaut ne se voit presque
#  jamais — vingt passes de cette sonde et trois cents appels ciblés n'ont
#  rien montré ici, alors que la CI est tombée dessus. La panne grandit avec
#  le corps : on mesure donc là où elle est VISIBLE, pas là où elle se cache.
GROS = b'{"fen":"' + b'z' * (1000 * 1000 - 10) + b'"}'
for ROUTE, ENTETES, ATTENDU, QUOI in (
        ("/api/inventee", BON, 404, "une route inconnue"),
        ("/api/saisie", {"Content-Type": "application/json"}, 403, "sans jeton"),
        ("/api/saisie", dict(BON, **{"Origin": "http://mechant.example"}), 403,
         "sur une origine étrangère")):
    sains = 0
    casses = []
    for _ in range(12):
        c, _r = appel(ROUTE, ENTETES, corps=GROS, delai=10)
        if c == ATTENDU:
            sains += 1
        else:
            casses.append(c)
    dit(sains == 12,
        "%s avec un corps d'1 Mio répond %d douze fois sur douze — le pont "
        "finit de lire avant de répondre (sains : %d, autres : %r)"
        % (QUOI, ATTENDU, sains, casses[:2]))

tp.fermer_toutes()
srv.shutdown()
PY
rendu "les routes" < <(lance routes.py)

# =============================================================================
titre "3. LE FILET : si le pty ne s'ouvre pas, le Terminal classique"
# =============================================================================
#  Le texte de doctrine, pas le code : on lit ce que le lanceur EXÉCUTE.
SANS_COMM="$(sed 's/#.*//' "$LANCEUR")"
if grep -q "pty.openpty" <<< "$SANS_COMM"; then
	ok "le lanceur essaie d'ouvrir un pseudo-terminal avant de montrer une fenêtre"
else
	non "le lanceur n'éprouve pas le pseudo-terminal : une fenêtre morte peut s'ouvrir"
fi
#  La bascule doit être « classique », pas « die » : mourir derrière Super+T
#  laisse un système où l'on ne peut plus rien lancer.
BLOC_PTY="$(awk '/pty.openpty/,/^fi$/' <<< "$SANS_COMM")"
if grep -q "classique" <<< "$BLOC_PTY" && ! grep -q "die " <<< "$BLOC_PTY"; then
	ok "sans pseudo-terminal, il bascule sur le Terminal classique au lieu de mourir"
else
	non "sans pseudo-terminal, le lanceur ne bascule pas sur le Terminal classique"
fi

# =============================================================================
titre "4. CE QUI DOIT AVOIR DISPARU DU CHEMIN INTERACTIF"
# =============================================================================
cat > "$BANC/absences.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
def dit(bon, m): print(("OK|" if bon else "NON|") + m)

#  inspect.getsource ne sait pas retrouver la source d'un module chargé par
#  chemin (il le prend pour une classe native). On lit donc le fichier, et on
#  découpe la classe à la main — c'est aussi ce qui garantit qu'on relit bien
#  CE fichier-là, pas une copie installée ailleurs.
entier = open(sys.argv[1], encoding="utf-8").read()
debut = entier.index("class Session:")
fin = entier.index("\nSESSIONS = {}")
src = entier[debut:fin]
#  ET SANS LES COMMENTAIRES : ils PARLENT de DEVNULL, de capture_output et du
#  délai de 25 s pour expliquer ce qui a disparu. Les garder rendrait les
#  trois contrôles suivants rouges à jamais — et surtout, ce banc lirait de
#  la prose au lieu de lire du code.
src = "\n".join(l.split("#")[0] if l.lstrip().startswith("#") else l
                 for l in src.splitlines())
#  Les trois verrous de l'ancien chemin, nommément : aucun n'a le droit de
#  reparaître dans la session interactive.
dit("DEVNULL" not in src, "la session n'a plus stdin fermé (DEVNULL)")
dit("capture_output" not in src, "la session ne ramasse plus la sortie d'un bloc")
dit("timeout" not in src and "DELAI_MAX" not in src,
    "la session n'a plus de délai maximal : un shell interactif ne meurt pas à 25 s")
dit("pty.fork" in src, "la session repose sur pty.fork (chef de session + terminal de contrôle)")
#  argv[0] commençant par « - » : c'est ce qui fait lire /etc/profile puis
#  ~/.profile, donc le PATH complet — sans quoi « claude » serait introuvable.
dit('"-" + os.path.basename' in src, "le shell est lancé comme shell de CONNEXION (argv[0] en « - »)")
#  SIGPIPE ignoré se transmet à travers exec : sans remise à zéro,
#  « yes | head » ne s'arrête jamais dans tout le shell.
dit("SIGPIPE" in src, "les signaux ignorés sont remis à zéro avant exec (SIGPIPE)")
#  Le jeton ne doit jamais fuiter dans l'environnement des programmes lancés.
dit("LEXOS_TERMINAL_PRO_JETON" in src, "le jeton du pont est retiré de l'environnement du shell")
PY
rendu "les absences" < <(lance absences.py)

# =============================================================================
printf '\n\033[1m═══ TOTAL ═══\033[0m\n'
printf '  réussis : \033[32m%d\033[0m\n  échoués : \033[31m%d\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
