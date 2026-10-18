#!/usr/bin/env python3
"""LexOS Pro Terminal — le pont local qui rend le terminal RÉEL.

ALEX : « c'est le new terminal officiel de LexOS Pro, pour le terminal
normal je veux que ce soit lui qui le remplace. » Puis, une fois branché
partout : « j'ai beau essayer le terminal LexOS Pro, je suis même pas
capable de lancer claude ».

  ═══ CE QUE CE FICHIER FAISAIT, ET POURQUOI CE N'ÉTAIT PAS SUFFISANT ═══

La première version lançait chaque commande dans un bash JETABLE :
subprocess.run(["bash", "-c", …], stdin=DEVNULL, capture_output=True,
timeout=25). Quatre verrous, dont chacun suffisait à empêcher un programme
interactif de tourner — et surtout AUCUN pseudo-terminal. « isatty() » était
donc faux, et claude, comme tout programme bien élevé, refusait de démarrer.
Une liste (LISTE_TUI) reconnaissait vim, nano, htop, less et man pour
renvoyer un message clair au lieu d'un carnage de codes d'échappement ;
claude n'y était pas, il partait dans le subprocess et se faisait tuer au
bout de 25 secondes. C'est exactement ce qu'ALEX a vu.

  ═══ CE QUE FAIT CE FICHIER MAINTENANT ═══

Un VRAI pseudo-terminal par volet (pty.fork), un shell de connexion qui vit
entre deux commandes, aucun délai, l'entrée branchée, la taille suivie. La
page, elle, tient une vraie grille de caractères avec xterm.js (paquet
Debian node-xterm). vim, nano, htop, less, man, sudo et claude y tournent
comme dans n'importe quel terminal — parce que c'en est un.

Quatre routes, une par sens du tuyau :

  GET  /api/flux?fen=…   la sortie du pty, en flux continu (SSE, base64)
  POST /api/saisie       les frappes, écrites sur le maître du pty
  POST /api/taille       colonnes × lignes (TIOCSWINSZ)
  POST /api/fermer       raccroche le shell et tout ce qu'il a lancé

  ═══ SÉCURITÉ : CE PONT EXÉCUTE N'IMPORTE QUELLE COMMANDE, EXPRÈS ═══

C'est un terminal : accepter d'exécuter ce qu'on tape est tout le produit.
Le risque n'est donc pas « la commande », c'est « qui peut atteindre ce
pont ». Trois verrous, tous nécessaires, sur LES QUATRE ROUTES :

  1. Écoute UNIQUEMENT 127.0.0.1 (comme lexos-settings et lexos-cartes) —
     rien n'est visible depuis le réseau.
  2. Un JETON tiré au hasard à chaque lancement (secrets.token_urlsafe),
     jamais écrit sur le disque, exigé dans l'en-tête « X-Lexos-Jeton » de
     CHAQUE requête. Sans lui : 403, rien n'est exécuté.
  3. L'en-tête « Origin » de la requête, quand le navigateur en pose un,
     doit être exactement http://127.0.0.1:<notre port>.

Pourquoi le jeton ET l'Origine, et pas l'un ou l'autre ? Parce qu'une simple
requête POST (Content-Type: text/plain, sans en-tête personnalisé) part
AVANT que le navigateur ne demande la permission CORS — une page malveillante
ouverte dans un vrai navigateur pourrait donc l'envoyer en aveugle même si
elle ne lira jamais la réponse. Exiger un en-tête personnalisé (le jeton)
change la nature de la requête : le navigateur DOIT alors demander la
permission au serveur avant de l'envoyer pour de vrai (une requête
« préparée », preflight), et notre serveur refuse cette permission à toute
origine autre que la sienne. C'est le jeton qui ferme la porte ; l'Origine
n'est qu'une deuxième serrure.

CE POINT A ÉTÉ MANQUÉ UNE FOIS : à la première écriture des trois routes du
pty, /api/flux ne vérifiait NI l'un NI l'autre — la route qui OUVRE le shell
et déverse tout ce qu'il écrit. Ça n'a pas été vu en relisant le code, mais
en éprouvant les quatre routes contre les trois refus attendus. D'où la
matrice complète dans tests/test_lexos_terminal_pty.sh, jamais un échantillon.
"""
import base64
import fcntl
import functools
import http.server
import json
import os
import pty
import re
import secrets
import shlex
import signal
import socket
import struct
import sys
import termios
import threading
import time
import urllib.parse
from pathlib import Path

APP_NAME = "LexOS Pro Terminal"
WEB_DIR = Path(os.environ.get("LEXOS_TERMINAL_PRO_WEB",
                               "/usr/share/lexos/terminal-pro/web"))
ICON_PATH = Path("/usr/share/icons/hicolor/128x128/apps/lexos-pro-terminal.png")

#  ═══ LA PALETTE VIENT DU THÈME, PLUS DE LA PAGE ═══
#  ALEX : « les couleurs, on les retrouve dans les autres terminaux aussi ».
#  La page portait sa propre palette en dur : un TROISIÈME orange pour le
#  curseur (#ff6a1a, à côté de l'accent #E8590C du générateur), un vert ANSI
#  qui n'était pas celui de LexOS, et un fond noir même en thème JOUR.
#  Elle demande maintenant les valeurs au pont, qui les lit dans le fichier
#  que lexos-theme-gen écrit — une seule source, comme l'invite.
#
#  ⚠ ON NE SOURCE PAS CE FICHIER. terminal.env est fait pour être lu par
#  bash, et il vit dans $HOME : tout ce qui tourne sous ce compte peut y
#  écrire. L'exécuter depuis le pont, ce serait offrir au contenu d'un
#  fichier de configuration le droit de lancer des commandes dans le
#  processus qui tient les pseudo-terminaux. On l'EXTRAIT, et on VALIDE.
#
#  La validation n'est pas décorative : « setProperty » n'est pas un filtre,
#  et « #000;}body{background:url(http://…) » est du CSS parfaitement valide.
#  C'est ici que la porte se ferme, pas dans la page.
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
_MODES = ("jour", "nuit", "auto", "suivre")
#  LA PALETTE A SON PROPRE VALIDATEUR, et sa LONGUEUR EST ANCRÉE À SEIZE.
#  Ce n'est pas de la coquetterie : sans le « {15} », un terminal.env pourrait
#  annoncer trois couleurs ou quarante, la page poserait « --ansi-0..2 » et
#  les treize autres resteraient sur la palette livrée — un thème à moitié
#  appliqué, sans un mot. Et ce fichier vit dans $HOME, donc tout ce qui
#  tourne sous ce compte peut y écrire : c'est la seule borne sur ce que la
#  page reçoit.
_PALETTE = re.compile(r"^#[0-9A-Fa-f]{6}(;#[0-9A-Fa-f]{6}){15}$")
#  Ce que la page a le droit de demander, et rien d'autre.
_CLES_THEME = ("LEXOS_TERM_BG", "LEXOS_TERM_FG", "LEXOS_TERM_TEXTE",
               "LEXOS_TERM_CURSEUR", "LEXOS_TERM_EFFECTIF",
               "LEXOS_TERM_PALETTE")


def lire_theme(chemin=None):
    """Les couleurs du thème, extraites de terminal.env sans l'exécuter.

    Rend {} quand le fichier manque, ne se lit pas, ou ne contient rien de
    valide : la page garde alors la palette livrée. Un thème illisible ne
    doit jamais empêcher le terminal de s'ouvrir."""
    if chemin is None:
        base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
            os.path.expanduser("~"), ".config")
        chemin = os.path.join(base, "lexos", "terminal.env")
    valeurs = {}
    try:
        with open(chemin, encoding="utf-8") as f:
            lignes = f.readlines()
    except (OSError, UnicodeDecodeError):
        return {}
    for ligne in lignes:
        ligne = ligne.strip()
        #  Les commentaires d'abord — et ici le format est « sh », donc un
        #  « # » en début de ligne. Le dépouilleur dépend du format : dans
        #  tmux, « #[fg=…] » est du balisage, pas un commentaire.
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, _, val = ligne.partition("=")
        cle = cle.strip()
        if cle not in _CLES_THEME:
            continue
        val = val.strip()
        #  Le générateur met des apostrophes sur les LEXOS_PS_*, pas sur les
        #  LEXOS_TERM_* : on en retire UNE paire, pas davantage.
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
            val = val[1:-1]
        if cle == "LEXOS_TERM_EFFECTIF":
            if val in _MODES:
                valeurs[cle] = val
        elif cle == "LEXOS_TERM_PALETTE":
            #  Seize couleurs séparées par « ; », ou rien : une palette
            #  tronquée est refusée EN ENTIER plutôt qu'appliquée à moitié.
            if _PALETTE.match(val):
                valeurs[cle] = val
        elif _HEX.match(val):
            valeurs[cle] = val
    return valeurs

#  ═══ PIÈCE 1 — UN VRAI PTY, UNE SESSION PAR VOLET ═══
#
#  ALEX : « j'ai beau essayer le terminal LexOS Pro, je suis même pas capable
#  de lancer claude ». Ce n'était pas un bogue : `executer()` ci-dessus lance
#  un bash JETABLE avec stdin=DEVNULL, capture_output=True et un délai de
#  25 s. Trois verrous, dont chacun suffit à empêcher `claude` de tourner —
#  et surtout AUCUN pty, donc `isatty()` est faux et tout programme bien
#  élevé refuse de démarrer en mode interactif.
#
#  Ici, à l'inverse : un pseudo-terminal réel (pty.fork), un shell de
#  connexion qui VIT entre deux commandes, aucun délai, l'entrée branchée.
#  C'est ce que `claude`, `sudo`, `nano`, `htop` et `less` exigent tous.
#
#  ── POURQUOI pty.fork() ET PAS openpty() + subprocess ──────────────────────
#  pty.fork() ne se contente pas d'ouvrir une paire maître/esclave : l'enfant
#  devient CHEF DE SESSION (setsid) et l'esclave devient son TERMINAL DE
#  CONTRÔLE. Sans ce terminal de contrôle il n'y a pas de contrôle de tâches :
#  pas de groupe de processus au premier plan, donc Ctrl+C n'interromprait
#  rien (validation n° 8) et sudo ne trouverait pas de terminal où lire le mot
#  de passe (validation n° 5). openpty() + subprocess.Popen ne donne ça
#  qu'avec start_new_session=True PLUS un TIOCSCTTY à la main ; pty.fork()
#  fait les deux d'un coup et c'est de la bibliothèque standard.
SHELL_DEFAUT = "/bin/bash"

#  Ce que la session garde en mémoire de ce que le pty a déjà écrit. Sert au
#  rattrapage : le flux SSE peut s'attacher quelques millisecondes après le
#  démarrage du shell, et la bannière + la première invite ne doivent pas se
#  perdre. Borné, sinon un `htop` laissé ouvert une nuit remplirait la RAM.
#  ═══ LE RÉVEIL PARTAGÉ — POURQUOI IL EXISTE ═══
#  Chaque session a SA condition, et « depuis() » l'attend. Cela suffit tant
#  qu'un flux ne suit qu'UNE session. Le flux multiplexé, lui, en suit
#  plusieurs : sans signal commun, il devrait interroger chacune à tour de
#  rôle avec un petit délai — six volets à 50 ms, c'est jusqu'à 300 ms de
#  retard sur la frappe, et un terminal qui traîne se remarque tout de suite.
#  Ce réveil-ci est notifié EN MÊME TEMPS que la condition d'une session : le
#  flux multiplexé dort dessus et se lève dès que N'IMPORTE LAQUELLE parle.
REVEIL = threading.Condition()


def _reveiller():
    with REVEIL:
        REVEIL.notify_all()


TAMPON_MAX = int(os.environ.get("LEXOS_TERMINAL_PRO_TAMPON", str(256 * 1024)))

#  Un volet = une session. Bornée pour qu'une page en boucle ne puisse pas
#  ouvrir mille shells.
SESSIONS_MAX = int(os.environ.get("LEXOS_TERMINAL_PRO_SESSIONS_MAX", "64"))


class Session:
    """Un shell vivant derrière son pseudo-terminal.

    Un fil de lecture vide le maître en continu dans « tampon » ; les lecteurs
    (le flux SSE) se réveillent sur « cond » et repartent de leur position
    absolue. Le tampon est borné : « perdus » compte les octets déjà jetés,
    pour qu'une position absolue reste juste même après un élagage."""

    def __init__(self, cwd=None, colonnes=80, lignes=24, shell=None,
                 cmd=None):
        self.colonnes = max(2, int(colonnes))
        self.lignes = max(1, int(lignes))
        self.tampon = bytearray()
        self.perdus = 0
        self.fini = False
        self.code = None
        self.cond = threading.Condition()

        depart = cwd if (cwd and os.path.isdir(cwd)) else str(Path.home())
        shell = shell or os.environ.get("SHELL") or SHELL_DEFAUT
        if not os.path.isabs(shell) or not os.access(shell, os.X_OK):
            shell = SHELL_DEFAUT

        #  L'ENVIRONNEMENT EST CONSTRUIT AVANT LE FORK, EXPRÈS. Entre fork()
        #  et exec() dans un programme à plusieurs fils, seul le strict
        #  minimum est sûr : un autre fil peut détenir le verrou du malloc au
        #  moment du fork, et l'enfant qui allouerait se bloquerait pour
        #  toujours. On prépare donc tout ici, et l'enfant ne fait plus que
        #  chdir + signal + execve.
        env = dict(os.environ)
        #  xterm.js annonce xterm-256color : dire autre chose ferait dessiner
        #  les programmes en couleurs pauvres (ou pas du tout).
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LEXOS_TERMINAL"] = "pro"
        #  Ces deux-là appartiennent au pont, pas au shell de l'utilisateur :
        #  les laisser fuiterait le jeton dans l'environnement de CHAQUE
        #  programme lancé (un `env` suffirait à le lire).
        env.pop("LEXOS_TERMINAL_PRO_JETON", None)
        env.pop("LEXOS_TERMINAL_PRO_PORT", None)

        #  argv[0] commençant par « - » : c'est ainsi que login démarre un
        #  SHELL DE CONNEXION. Il lit alors /etc/profile puis ~/.profile —
        #  et c'est ~/.profile qui, sur Debian, source ~/.bashrc. Sans ça,
        #  le PATH de l'utilisateur (~/.local/bin, /usr/local/bin, les
        #  installations de node ou de claude) manquerait, et « claude »
        #  serait « command not found » au lieu de démarrer.
        argv = ["-" + os.path.basename(shell)]
        if cmd:
            argv = [os.path.basename(shell), "-l", "-c", cmd]

        pid, maitre = pty.fork()
        if pid == 0:  # ── l'enfant : le moins de code possible, puis exec ──
            try:
                os.chdir(depart)
            except OSError:
                pass
            #  PYTHON IGNORE SIGPIPE, ET « ignoré » SE TRANSMET À TRAVERS
            #  exec (contrairement à « traité par une fonction », qui est
            #  remis à zéro). Sans cette ligne, tout le shell hérite d'un
            #  SIGPIPE ignoré : « yes | head » ne s'arrête plus jamais, et
            #  la moitié des pipelines se comportent bizarrement. Le même
            #  raisonnement vaut pour SIGINT/SIGQUIT si quelqu'un les avait
            #  ignorés plus haut.
            for sig in (signal.SIGPIPE, signal.SIGINT, signal.SIGQUIT,
                        signal.SIGTERM, signal.SIGHUP, signal.SIGCHLD):
                try:
                    signal.signal(sig, signal.SIG_DFL)
                except (OSError, ValueError):
                    pass
            try:
                os.execve(shell, argv, env)
            except OSError:
                os._exit(127)
        #  ── le parent ──
        self.pid = pid
        self.maitre = maitre
        self.redimensionner(self.colonnes, self.lignes)
        self._fil = threading.Thread(target=self._lire, daemon=True,
                                     name="lexos-pty-%d" % pid)
        self._fil.start()

    # -- lecture -----------------------------------------------------------
    def _lire(self):
        while True:
            try:
                morceau = os.read(self.maitre, 65536)
            except OSError:
                #  Quand le shell meurt, Linux rend EIO sur le maître — ce
                #  n'est pas une panne, c'est la fin normale de la session.
                morceau = b""
            if not morceau:
                break
            with self.cond:
                self.tampon += morceau
                trop = len(self.tampon) - TAMPON_MAX
                if trop > 0:
                    del self.tampon[:trop]
                    self.perdus += trop
                self.cond.notify_all()
            _reveiller()
        with self.cond:
            self.fini = True
            self.cond.notify_all()
        _reveiller()
        try:
            self.code = os.waitpid(self.pid, 0)[1]
        except OSError:
            self.code = -1

    @property
    def total(self):
        """Position absolue de la fin du flux, élagage compris."""
        return self.perdus + len(self.tampon)

    def depuis(self, pos, delai):
        """Rend (octets, nouvelle_position, fini). Attend au plus « delai »
        secondes qu'il y ait quelque chose. Une position antérieure à ce qui
        a été élagué est remontée au plus ancien octet encore là — mieux vaut
        un trou qu'un plantage."""
        with self.cond:
            if pos < self.perdus:
                pos = self.perdus
            if pos >= self.total and not self.fini:
                self.cond.wait(delai)
                if pos < self.perdus:
                    pos = self.perdus
            bloc = bytes(self.tampon[pos - self.perdus:])
            return bloc, pos + len(bloc), self.fini

    # -- écriture ----------------------------------------------------------
    def ecrire(self, donnees):
        """Les frappes, telles quelles, sur le maître. Une écriture partielle
        est possible sur un pty (le tampon du noyau est petit) : on boucle."""
        vus = 0
        while vus < len(donnees):
            try:
                vus += os.write(self.maitre, donnees[vus:])
            except BlockingIOError:
                time.sleep(0.005)
            except OSError:
                return False
        return True

    def redimensionner(self, colonnes, lignes):
        """TIOCSWINSZ sur le MAÎTRE.

        MESURÉ, PAS SUPPOSÉ : cet ioctl suffit — le noyau envoie lui-même
        SIGWINCH au groupe de processus AU PREMIER PLAN du terminal. Ajouter
        un kill(-pgid, SIGWINCH) à la main serait pire que redondant : le
        groupe du shell n'est pas forcément celui du premier plan, on
        réveillerait donc le mauvais programme."""
        self.colonnes = max(2, int(colonnes))
        self.lignes = max(1, int(lignes))
        try:
            fcntl.ioctl(self.maitre, termios.TIOCSWINSZ,
                        struct.pack("HHHH", self.lignes, self.colonnes, 0, 0))
            return True
        except OSError:
            return False

    def _pgid(self):
        try:
            return os.getpgid(self.pid)
        except OSError:
            return -1

    def vivante(self):
        if self.fini:
            return False
        try:
            os.kill(self.pid, 0)
            return True
        except OSError:
            return False

    # -- fermeture ---------------------------------------------------------
    def fermer(self):
        """SIGHUP au GROUPE, pas au seul shell.

        Fermer un onglet pendant qu'un `htop` tourne ne doit pas laisser de
        processus orphelin (validation n° 11) : `htop` est un enfant du shell,
        tuer le shell seul le laisserait vivant, rattaché à init. Le signal
        part donc au groupe entier — c'est exactement ce que fait un vrai
        terminal quand sa fenêtre se ferme, d'où le nom du signal
        (« hang up », raccrocher)."""
        #  MESURÉ : un travail lancé depuis le shell interactif — au premier
        #  plan (`htop`) comme en fond (`sleep 300 &`) — reçoit SON PROPRE
        #  groupe de processus, différent de celui du shell. Signaler le seul
        #  groupe du shell ne l'atteint donc PAS directement ; on compte sur
        #  bash pour propager. Alors on frappe les deux : d'abord le groupe
        #  au premier plan du terminal (là où se trouve `htop`), ensuite
        #  celui du shell. Ce que fait un vrai terminal quand sa fenêtre se
        #  ferme, et la raison du nom du signal (« hang up », raccrocher).
        try:
            avant = os.tcgetpgrp(self.maitre)
        except OSError:
            avant = -1
        for cible in (avant, self._pgid()):
            if cible and cible > 0:
                try:
                    os.killpg(cible, signal.SIGHUP)
                except OSError:
                    pass
        try:
            os.kill(self.pid, signal.SIGHUP)
        except OSError:
            pass
        #  Fermer le maître fait aussi arriver EOF/EIO côté esclave : le fil
        #  de lecture sort de sa boucle et la session se marque finie.
        try:
            os.close(self.maitre)
        except OSError:
            pass
        with self.cond:
            self.fini = True
            self.cond.notify_all()
        _reveiller()


#  Le registre des sessions vivantes, une par volet. La clé est l'identifiant
#  que la page fabrique pour chaque volet (onglet ou division).
SESSIONS = {}
_VERROU_SESSIONS = threading.Lock()


def session_de(fen, creer=False, cwd=None, colonnes=80, lignes=24, cmd=None):
    """Rend la session du volet « fen », en la créant si demandé. Une session
    morte est remplacée, jamais rendue telle quelle."""
    with _VERROU_SESSIONS:
        s = SESSIONS.get(fen)
        if s is not None and not s.vivante():
            SESSIONS.pop(fen, None)
            s = None
        if s is None and creer:
            if len(SESSIONS) >= SESSIONS_MAX:
                raise RuntimeError("trop de sessions ouvertes")
            s = Session(cwd=cwd, colonnes=colonnes, lignes=lignes, cmd=cmd)
            SESSIONS[fen] = s
        return s


def fermer_session(fen):
    with _VERROU_SESSIONS:
        s = SESSIONS.pop(fen, None)
    if s is not None:
        s.fermer()
        return True
    return False


def fermer_toutes():
    with _VERROU_SESSIONS:
        vivantes = list(SESSIONS.values())
        SESSIONS.clear()
    for s in vivantes:
        s.fermer()


#  ═══ LE SERVEUR ═══
class Handler(http.server.SimpleHTTPRequestHandler):
    jeton = ""
    port = 0
    #  Posé par _corps() comme par _vider_corps() : le corps d'une requête ne
    #  se lit qu'UNE fois, sinon le second read() attend des octets qui ne
    #  viendront jamais.
    _corps_lu = False

    def log_message(self, fmt, *args):
        pass

    #  ═══ ON LIT TOUJOURS LA REQUÊTE AVANT D'Y RÉPONDRE ═══
    #  CE QUE ÇA A CASSÉ, ET C'EST MESURÉ. Les chemins d'erreur — route
    #  inconnue, origine refusée, jeton invalide — répondaient SANS avoir lu
    #  le corps de la requête. Les octets non lus restent dans la file de
    #  réception de la prise ; à la fermeture, le noyau envoie un RST au lieu
    #  d'un FIN, et le client PERD la réponse qu'il avait déjà reçue.
    #
    #  MESURÉ sur ce pont, 12 POST sur une route inconnue : corps de
    #  11 octets → 12 sains ; corps de 64 Kio → 12 sains ; corps d'1 Mio →
    #  10 sains et 2 « Broken pipe ». La panne grandit avec le corps, ce qui
    #  est la signature exacte du corps non lu.
    #
    #  CE QUE ÇA A DONNÉ EN CI, sur l'étape du pseudo-terminal :
    #  « BadStatusLine: {"ok": false, "erreur": "inconnu"} » — le client a lu
    #  le CORPS de la réponse là où il attendait la ligne de statut, puis la
    #  sonde entière est morte et vingt-trois verdicts ont été perdus d'un
    #  coup. Je n'ai PAS reproduit cette forme-là ici (20 passes de la sonde
    #  complète et 300 appels ciblés, tous sains) : ce que j'ai prouvé, c'est
    #  que le défaut existe et qu'il casse ce même appel. Que ce soit lui qui
    #  ait produit cette ligne précise reste une déduction, pas une mesure.
    #
    #  LE PLAFOND N'EST PAS UNE COQUETTERIE : ce vidage a lieu AVANT le
    #  contrôle du jeton — il faut bien lire pour pouvoir répondre « refusé »
    #  proprement. Sans borne, un appelant local non authentifié annoncerait
    #  « Content-Length: 10 Gio » et nous le ferions lire. Au-delà du plafond
    #  on arrête de lire et on marque la connexion à fermer : le client peut
    #  perdre la réponse, mais c'est SON abus, et nous restons bornés.
    PLAFOND_VIDAGE = 1 << 20

    def _vider_corps(self):
        if self._corps_lu:
            return
        self._corps_lu = True
        try:
            reste = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            return
        if reste > self.PLAFOND_VIDAGE:
            self.close_connection = True
            return
        while reste > 0:
            bloc = self.rfile.read(min(reste, 65536))
            if not bloc:
                break
            reste -= len(bloc)

    def _json(self, code, donnees):
        #  AVANT d'écrire quoi que ce soit : finir de lire ce qu'on nous a
        #  envoyé. Un seul endroit à tenir, parce que c'est le seul endroit
        #  par lequel le pont répond.
        self._vider_corps()
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def _origine_valide(self):
        """Absente : un fetch same-origin depuis notre propre page ne pose
        PAS toujours cet en-tête selon le navigateur — on ne bloque donc que
        l'en-tête présent ET faux, jamais son absence pure."""
        o = self.headers.get("Origin", "")
        return o == "" or o == "http://127.0.0.1:%d" % self.port

    def _autorise(self):
        """═══ LES DEUX SERRURES, SUR TOUTES LES ROUTES ═══

        Le modèle de sécurité ne bouge pas d'un pouce avec l'arrivée du pty :
        les trois routes nouvelles (/api/flux, /api/saisie, /api/taille) sont
        exactement aussi exigeantes que /api/exec l'était. Le raisonnement
        derrière — pourquoi le jeton ET l'origine — est écrit en tête de
        fichier ; c'est le jeton qui ferme la porte."""
        if not self._origine_valide():
            self._json(403, {"ok": False, "erreur": "origine refusée"})
            return False
        recu = self.headers.get("X-Lexos-Jeton", "")
        if not (recu and secrets.compare_digest(recu, self.jeton)):
            self._json(403, {"ok": False, "erreur": "jeton absent ou invalide"})
            return False
        return True

    def _corps(self):
        """Le JSON de la requête, ou None (400 déjà envoyé)."""
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            brut = self.rfile.read(taille)
        except ValueError:
            #  Content-Length illisible : rien n'a été lu, et _json videra ce
            #  qu'il peut. On ne touche donc PAS au drapeau ici.
            self._json(400, {"ok": False, "erreur": "requête invalide"})
            return None
        #  Lu pour de bon : plus personne ne doit relire cette prise.
        self._corps_lu = True
        try:
            return json.loads(brut or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._json(400, {"ok": False, "erreur": "requête invalide"})
            return None

    def do_GET(self):
        self._corps_lu = False
        chemin, _, requete = self.path.partition("?")
        if chemin == "/api/flux":
            return self._flux(urllib.parse.parse_qs(requete))
        if chemin == "/api/theme":
            return self._theme()
        if chemin.startswith("/api/"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        return super().do_GET()

    def _theme(self):
        """Les couleurs du thème, pour que la page cesse d'avoir les siennes.

        LES DEUX SERRURES COMME PARTOUT. /api/flux avait été écrite sans, et
        ça ne s'est vu qu'en éprouvant la matrice complète : cette route-ci
        entre dans la même matrice, elle n'est pas posée à côté."""
        if not self._autorise():
            return
        return self._json(200, {"ok": True, "theme": lire_theme()})

    #  ═══ PIÈCE 3 — LE TUYAU, SENS PONT → PAGE ═══
    def _flux(self, params):
        """Sortie du pty en flux continu (text/event-stream).

        POURQUOI DU BASE64 ET PAS LE TEXTE TEL QUEL : ce qui sort d'un pty
        est un flot d'OCTETS, et on le lit par blocs de 64 ko. Un caractère
        accentué (deux octets en UTF-8), un emoji (quatre), ou n'importe
        quel dessin de cadre peut se faire couper EN PLEIN MILIEU par une
        frontière de bloc. Décoder chaque bloc en texte ici produirait des
        « ￼ » à la place — et les recoller correctement demanderait de
        garder un décodeur à état par session. Le base64 transporte les
        octets intacts ; c'est xterm.js, de l'autre côté, qui tient le
        décodeur UTF-8 à état et recolle les morceaux. En prime, le base64
        ne contient jamais de « \n », donc rien ne peut casser le découpage
        en événements SSE."""
        #  LE FLUX EST UNE ROUTE COMME LES AUTRES. Première écriture : cette
        #  vérification manquait — /api/flux créait un shell et déversait sa
        #  sortie à qui la demandait, sans jeton ni origine. Trouvé en
        #  éprouvant les quatre routes contre les trois refus attendus, pas
        #  en relisant le code : les trois routes POST passaient, celle-ci
        #  répondait 200. C'est la route la PLUS sensible des quatre — elle
        #  ouvre le shell et montre tout ce qu'il écrit.
        if not self._autorise():
            return

        def prem(nom, defaut=""):
            v = params.get(nom, [defaut])
            return v[0] if v else defaut

        #  ═══ UN SEUL FLUX POUR TOUS LES VOLETS ═══
        #  « fens=a,b,c » : le flux suit plusieurs volets et ÉTIQUETTE chaque
        #  bloc. « fen=a » reste accepté, sans étiquette — c'est la forme
        #  qu'emploient les bancs du pont, et un pont qui casse ses propres
        #  bancs en corrigeant autre chose n'a rien corrigé.
        #  « fens=* » : SUIVRE TOUTES LES SESSIONS, ET CELLES QUI NAÎTRONT.
        #  C'est la forme qu'emploie la page. Une liste figée obligerait à
        #  ROUVRIR le flux à chaque volet ouvert ou fermé — donc à abandonner
        #  une requête en cours, ce que le banc du navigateur signale à juste
        #  titre comme une requête échouée. Avec l'étoile, le flux est ouvert
        #  UNE fois pour la vie de la fenêtre.
        brut = prem("fens").strip()
        toutes = (brut == "*")
        liste = [] if toutes else [f.strip() for f in brut.split(",") if f.strip()]
        fen = prem("fen").strip()
        if not liste and not toutes and fen:
            liste = [fen]
        etiquete = bool(brut)
        if not liste and not toutes:
            return self._json(400, {"ok": False, "erreur": "fen manquant"})
        try:
            colonnes = int(prem("colonnes", "80") or 80)
            lignes = int(prem("lignes", "24") or 24)
        except ValueError:
            colonnes, lignes = 80, 24
        #  ON NE CONSOMME LE DÉMARRAGE QUE SI UN SHELL VA VRAIMENT NAÎTRE.
        #  Le consommer sans rien créer — flux rouvert sur une session déjà
        #  là, après un hoquet du tuyau — perdrait pour de bon le
        #  « -e "lexos capture video" » du lanceur : la fenêtre s'ouvrirait
        #  sur une invite nue, sans que rien n'explique pourquoi.
        suivies = {}
        try:
            for f in list(liste):
                #  ON NE CONSOMME LE DÉMARRAGE QUE POUR UNE SESSION QUI NAÎT.
                depart = None if session_de(f) is not None else _prendre_demarrage()
                suivies[f] = session_de(
                    f, creer=True,
                    cwd=(depart and depart["cwd"]) or prem("cwd") or None,
                    colonnes=colonnes, lignes=lignes,
                    cmd=(depart and depart["cmd"]) or None)
        except Exception as e:  # noqa: BLE001 — la fenêtre doit survivre
            return self._json(500, {"ok": False, "erreur": str(e)})

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        pos = {f: 0 for f in liste}
        finies = set()
        try:
            while True:
                #  En mode « toutes », la liste se relit à chaque tour : un
                #  volet ouvert entre-temps est suivi sans rouvrir le flux.
                if toutes:
                    with _VERROU_SESSIONS:
                        liste = list(SESSIONS.keys())
                        for f in liste:
                            if f not in suivies:
                                suivies[f] = SESSIONS[f]
                                pos[f] = 0
                #  On VIDE d'abord tout ce qui attend, sans dormir (délai 0) :
                #  la sortie d'un volet ne doit pas attendre le tour d'un
                #  autre. C'est seulement quand tout est vide qu'on dort — sur
                #  le RÉVEIL PARTAGÉ, qui se lève dès que n'importe laquelle
                #  des sessions parle.
                quelque_chose = False
                for f in liste:
                    if f in finies:
                        continue
                    bloc, pos[f], fini = suivies[f].depuis(pos[f], 0)
                    if bloc:
                        quelque_chose = True
                        if etiquete:
                            self.wfile.write(b"data: " + f.encode("utf-8") +
                                             b" " + base64.b64encode(bloc) +
                                             b"\n\n")
                        else:
                            self.wfile.write(b"data: " +
                                             base64.b64encode(bloc) + b"\n\n")
                    elif fini:
                        finies.add(f)
                        quelque_chose = True
                        if etiquete:
                            self.wfile.write(b"event: fin\ndata: " +
                                             f.encode("utf-8") + b"\n\n")
                        else:
                            self.wfile.write(b"event: fin\ndata: {}\n\n")
                            self.wfile.flush()
                            return
                if quelque_chose:
                    self.wfile.flush()
                    continue
                #  En mode « toutes », on ne raccroche jamais : la fenêtre
                #  peut rouvrir un volet après avoir fermé le dernier.
                if etiquete and not toutes and len(finies) == len(liste):
                    self.wfile.flush()
                    return
                #  Le réveil au bout d'une seconde n'est pas de l'attente
                #  active : sans lui, un volet fermé par la page ne serait
                #  JAMAIS remarqué — on ne s'en aperçoit qu'en écrivant sur
                #  la prise. Le « : » est un commentaire SSE, ignoré par le
                #  lecteur, et c'est lui qui déclenche l'erreur d'écriture.
                with REVEIL:
                    REVEIL.wait(1.0)
                self.wfile.write(b": .\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            #  La page a fermé le volet ou s'est rechargée. Le shell, lui,
            #  reste vivant : c'est /api/fermer qui le raccroche, pas la
            #  perte du tuyau — sinon un simple hoquet réseau local tuerait
            #  la session en cours.
            return

    def do_POST(self):
        #  ═══ REMIS À ZÉRO À CHAQUE REQUÊTE, PAS À CHAQUE CONNEXION ═══
        #  Aujourd'hui ce pont parle HTTP/1.0 : « close_connection » est vrai
        #  après chaque réponse, donc une instance de Handler ne sert qu'une
        #  requête et le drapeau de classe suffirait. MAIS le jour où
        #  quelqu'un pose « protocol_version = "HTTP/1.1" » pour garder la
        #  connexion ouverte, une même instance en servirait plusieurs, le
        #  drapeau resterait vrai, et la deuxième requête ne serait plus vidée.
        #  CE N'EST PAS UNE CRAINTE EN L'AIR, C'EST MESURÉ : en forçant
        #  HTTP/1.1 et en envoyant trois POST de 200 Kio sur UNE connexion,
        #  sans cette ligne la troisième rend « 414 Request-URI Too Long » —
        #  le serveur a lu le corps resté en file comme une nouvelle ligne de
        #  requête. Avec la ligne : 404, 404, 404.
        self._corps_lu = False
        if self.path in ("/api/saisie", "/api/taille", "/api/fermer",
                         "/api/ouvrir"):
            return self._route_pty(self.path)
        return self._json(404, {"ok": False, "erreur": "inconnu"})

    #  ═══ PIÈCE 3 — LE TUYAU, SENS PAGE → PONT ═══
    def _route_pty(self, chemin):
        if not self._autorise():
            return
        requete = self._corps()
        if requete is None:
            return
        fen = str(requete.get("fen", "")).strip()
        if not fen:
            return self._json(400, {"ok": False, "erreur": "fen manquant"})

        if chemin == "/api/fermer":
            return self._json(200, {"ok": True, "ferme": fermer_session(fen)})

        #  ═══ /api/ouvrir — CRÉER LA SESSION SANS TENIR DE CONNEXION ═══
        #  C'était /api/flux qui créait le shell, en même temps qu'il ouvrait
        #  le tuyau de sortie. Pratique, et c'est ce qui a coûté cher : un
        #  navigateur n'accorde que SIX connexions simultanées par origine en
        #  HTTP/1.1, et chaque volet en gardait une, à vie. MESURÉ dans un
        #  vrai Chromium contre ce pont :
        #      1 à 5 flux ouverts → /api/saisie répond en 3 à 6 ms
        #      6 flux et au-delà  → /api/saisie ne répond plus (> 5 s)
        #  Au sixième volet, taper ne faisait plus rien. On sépare donc les
        #  deux gestes : ouvrir est une requête courte, écouter est UN seul
        #  flux pour tous les volets (voir « fens » dans _flux).
        if chemin == "/api/ouvrir":
            try:
                colonnes = int(requete.get("colonnes", 80) or 80)
                lignes = int(requete.get("lignes", 24) or 24)
            except (TypeError, ValueError):
                colonnes, lignes = 80, 24
            depart = None if session_de(fen) is not None else _prendre_demarrage()
            try:
                session_de(fen, creer=True,
                           cwd=((depart and depart["cwd"])
                                or str(requete.get("cwd") or "") or None),
                           colonnes=colonnes, lignes=lignes,
                           cmd=(depart and depart["cmd"]) or None)
            except Exception as e:  # noqa: BLE001 — la fenêtre doit survivre
                return self._json(500, {"ok": False, "erreur": str(e)})
            return self._json(200, {"ok": True})

        s = session_de(fen)
        if s is None:
            return self._json(404, {"ok": False, "erreur": "session absente"})

        if chemin == "/api/taille":
            try:
                colonnes = int(requete.get("colonnes", 80))
                lignes = int(requete.get("lignes", 24))
            except (TypeError, ValueError):
                return self._json(400, {"ok": False, "erreur": "taille invalide"})
            return self._json(200, {"ok": s.redimensionner(colonnes, lignes)})

        #  /api/saisie — les frappes. Du TEXTE JSON, pas du base64 : ce que
        #  xterm.js remonte est déjà une chaîne (« a », « \x1b[A » pour la
        #  flèche du haut, une ligne entière collée…), et JSON transporte
        #  n'importe quelle chaîne sans dommage. C'est l'inverse du sens
        #  descendant, où l'on manipule des octets bruts découpés au hasard.
        texte = requete.get("texte", "")
        if not isinstance(texte, str):
            return self._json(400, {"ok": False, "erreur": "saisie invalide"})
        return self._json(200, {"ok": s.ecrire(texte.encode("utf-8"))})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def demarrer_serveur():
    """Démarre le pont sur un port libre, avec un jeton neuf. Rend
    (serveur, port, jeton) — l'appelant décide de la fenêtre."""
    port = _port_libre()
    jeton = secrets.token_urlsafe(32)
    classe = type("HandlerJeton", (Handler,), {"jeton": jeton, "port": port})
    handler = functools.partial(classe, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-terminal-pro-http").start()
    return serveur, port, jeton


#  ═══ CE QUE LA LIGNE DE COMMANDE A DEMANDÉ POUR LE PREMIER VOLET ═══
#  « Ouvrir un terminal ici » de Thunar passe --working-directory ; le pont
#  x-terminal-emulator et les lanceurs du panneau passent -e ou -x. Avant, ces
#  options étaient IGNORÉES (le seul argv du fichier était celui de Qt) : le
#  clic droit de Thunar ouvrait le dossier personnel au lieu du dossier visé,
#  et tout ce qui demandait d'exécuter une commande devait partir vers le
#  Terminal classique.
#
#  UNE SEULE FOIS, POUR LE PREMIER VOLET. Un nouvel onglet ouvert ensuite doit
#  recevoir un shell ordinaire, pas rejouer la commande de départ — d'où le
#  drapeau « consomme », et un verrou parce que deux volets peuvent demander
#  leur flux en même temps.
DEMARRAGE = {"cwd": None, "cmd": None, "consomme": False}
_VERROU_DEMARRAGE = threading.Lock()


def _prendre_demarrage():
    with _VERROU_DEMARRAGE:
        if DEMARRAGE["consomme"]:
            return None
        DEMARRAGE["consomme"] = True
        return {"cwd": DEMARRAGE["cwd"], "cmd": DEMARRAGE["cmd"]}


def lire_arguments(args):
    """Rend (cwd, commande, tenir). Reconnaît les formes de xfce4-terminal ET
    la convention Debian de x-terminal-emulator.

    LA DIFFÉRENCE ENTRE LES DEUX N'EST PAS UN DÉTAIL : xfce4-terminal prend
    « -e "ls -la" » — UN seul argument, une ligne de shell entière ;
    x-terminal-emulator prend « -e ls -la » — la commande PUIS ses arguments,
    déjà découpés. Confondre les deux donne soit un « ls -la » introuvable
    (on cherche un programme dont le nom contient une espace), soit un « -la »
    perdu. On distingue au nombre d'arguments restants, et on RECOLLE avec
    shlex.quote quand il y en a plusieurs : le shell recevra exactement les
    mots qu'on lui a donnés, espaces et guillemets compris."""
    cwd = None
    commande = None
    tenir = False
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("--working-directory="):
            cwd = a.split("=", 1)[1]
        elif a == "--working-directory" and i + 1 < len(args):
            i += 1
            cwd = args[i]
        elif a in ("--hold", "-hold", "-H"):
            tenir = True
        elif a in ("-e", "--command", "-x"):
            reste = args[i + 1:]
            if len(reste) == 1:
                commande = reste[0]
            elif reste:
                commande = " ".join(shlex.quote(m) for m in reste)
            i = len(args)
        elif a.startswith("--command="):
            commande = a.split("=", 1)[1]
        i += 1
    return cwd, commande, tenir


def main():
    cwd, commande, tenir = lire_arguments(sys.argv[1:])
    DEMARRAGE["cwd"] = cwd
    if commande:
        #  --hold : la fenêtre reste après la fin de la commande. C'est ce que
        #  le lanceur 11 du panneau attend (« lexos capture video »), sans
        #  quoi le volet se ferme avant qu'on ait pu lire le message.
        DEMARRAGE["cmd"] = (
            commande + "\nprintf '\\n\\033[90m— terminé. Entrée pour fermer.\\033[0m'\nread -r _\n"
            if tenir else commande)

    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    serveur, port, jeton = demarrer_serveur()
    url = f"http://127.0.0.1:{port}/index.html?port={port}&jeton={jeton}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(760, min(1280, int(dispo.width() * 0.72)))
        hauteur = max(480, min(860, int(dispo.height() * 0.78)))
        fenetre.resize(largeur, hauteur)
        fenetre.move(dispo.x() + (dispo.width() - largeur) // 2,
                     dispo.y() + (dispo.height() - hauteur) // 2)
    else:
        fenetre.resize(1000, 640)
    if ICON_PATH.exists():
        fenetre.setWindowIcon(QIcon(str(ICON_PATH)))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)

    #  ═══ LE PRESSE-PAPIER, ET POURQUOI IL FAUT DEUX RÉGLAGES ═══
    #  ALEX : le copier-coller ne fonctionnait pas. Deux causes distinctes ;
    #  celle-ci est côté Qt. QtWebEngine DÉSACTIVE PAR DÉFAUT l'accès de
    #  JavaScript au presse-papier — tant que ces attributs ne sont pas
    #  posés, la page ne peut ni écrire ni lire dedans, quoi qu'elle tente.
    #
    #  LES DEUX SONT NÉCESSAIRES ET NE FONT PAS LA MÊME CHOSE :
    #    · JavascriptCanAccessClipboard autorise l'ÉCRITURE (copier) ;
    #    · JavascriptCanPaste          autorise la LECTURE  (coller).
    #  N'en poser qu'un donne un copier-coller à moitié réparé — le collage
    #  marche mais pas la copie, ou l'inverse — et c'est plus long à
    #  diagnostiquer qu'une panne franche.
    #
    #  AVANT le load : après le chargement, les réglages peuvent ne pas
    #  s'appliquer à la page déjà en cours.
    #
    #  ET SOUS try/except, PARCE QU'UN TERMINAL QUI NE S'OUVRE PAS EST PIRE.
    #  Si une version de PySide6 renomme ou déplace ces attributs, la fenêtre
    #  doit s'ouvrir QUAND MÊME, sans presse-papier. Un presse-papier absent
    #  est un désagrément ; une fenêtre qui refuse de s'ouvrir laisse un
    #  système où l'on ne peut plus rien lancer du tout — c'est la règle
    #  écrite en tête de ce fichier. On journalise l'échec, on ne l'avale pas.
    try:
        from PySide6.QtWebEngineCore import QWebEngineSettings
        reglages = vue.settings()
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard, True)
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanPaste, True)
    except Exception as e:  # noqa: BLE001 — voir le commentaire ci-dessus
        print(f"[lexos-terminal-pro] presse-papier non activé : {e}",
              file=sys.stderr)

    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    #  Raccrocher AVANT de rendre la main : sans ça, fermer la fenêtre
    #  laisserait un shell (et tout ce qu'il a lancé) vivant en fond, sans
    #  plus aucun terminal pour l'atteindre.
    fermer_toutes()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
