#!/usr/bin/env python3
"""LexOS Pilotes — serveur local (API JSON + interface web).

Même patron que LexOS Diagnostic : http.server de la bibliothèque standard,
écoute sur 127.0.0.1 seulement, et le navigateur ouvre la page.

Ce serveur tourne EN UTILISATEUR. Pour installer, il lance
« pkexec lexos-pilotes-maj installer » : la fenêtre de mot de passe est
celle du système (polkit), et c'est l'aide root qui recalcule elle-même
la liste des paquets. Le serveur ne lui transmet AUCUN nom de paquet.

═══ POURQUOI UN JETON, ALORS QUE POLKIT DEMANDE LE MOT DE PASSE ═══
Polkit prend pour « sujet » le PARENT de pkexec, c'est-à-dire ce serveur
(pkexec.c:754-779, polkit 126). Avec auth_admin_keep, un mot de passe tapé
pour « Vérifier » valait 5 minutes pour TOUT pkexec lancé par lui : un
autre compte local, ou une appli qui partage le réseau de l'hôte, n'avait
qu'à envoyer « POST /api/installer » pour faire tourner l'aide root sans
aucune fenêtre (reproduit : uid 65534, 3 sur 3). Le contrôle Host/Origin
n'arrête que les navigateurs. Donc, comme le bureau du Moteur et le
Terminal Pro : un jeton tiré au hasard au démarrage (256 bits), exigé sur
toute l'API. Et « installer » a sa propre action polkit en auth_admin :
chaque installation redemande le mot de passe.

═══ POURQUOI LE JETON N'EST JAMAIS DANS UNE ADRESSE ═══
On ouvrait « http://127.0.0.1:P/#j=JETON » avec webbrowser.open : l'adresse
part dans l'argv de xdg-open puis du navigateur, et /proc/<pid>/cmdline
est lisible par TOUS les comptes (pas de hidepid sur LexOS). Un script
lancé en uid 65534, qui ne lisait que /proc, a obtenu 200 sur POST
/api/installer, 3 fois sur 3 : la fenêtre polkit « installer » s'ouvrait
chez Alex sans qu'il ait rien demandé, et « Vérifier » repassait en root
sans fenêtre pendant les 5 minutes du mot de passe gardé. Le bureau du
Moteur n'a pas ce trou : il remet le jeton à sa fenêtre Qt en mémoire.

Ici, la technique de Jupyter, en plus strict : le navigateur reçoit
SEULEMENT le chemin file:// d'une petite page d'ouverture, écrite dans
notre dossier privé ($XDG_RUNTIME_DIR/lexos, 0700) en 0600. Elle contient
un TICKET À USAGE UNIQUE (« #o=… », scellé par HMAC avec le jeton), pas
le jeton. La page de l'appli échange ce ticket contre le jeton (POST
/api/entree), le garde dans le sessionStorage de SON onglet, et retire
le ticket de la barre d'adresse. Le serveur efface la page d'ouverture
dès qu'elle a servi, et toutes celles de son port à l'arrêt. Une adresse
copiée, l'historique, un Referer ne portent donc au pire qu'un ticket
déjà dépensé. Le jeton ne passe ni par un argv, ni par une variable
d'environnement, ni par le journal.

═══ POURQUOI PLUS DE PORT FIXE ═══
Le lanceur ouvrait la page de QUICONQUE répondait 200 sur 127.0.0.1:7862,
même un autre utilisateur arrivé avant nous — une fausse page qui réclame
le mot de passe, c'est l'invite sudo maison que LexOS interdit. Le serveur
prend maintenant un port libre, et écrit {port, jeton} dans
$XDG_RUNTIME_DIR/lexos/pilotes.json (dossier 0700, fichier 0600). Au
deuxième clic, on ne croit ce fichier qu'après une poignée de main : le
serveur doit prouver qu'il connaît le jeton (HMAC d'un défi tiré au
hasard), sans que le jeton lui-même passe par la socket. Le deuxième clic
écrit alors sa propre page d'ouverture, avec un ticket neuf.

Les deux HMAC sont SÉPARÉS (« bonjour: » et « ouvrir: » devant le
message) : /api/bonjour signe ce qu'on lui donne, sans jeton exigé. Sans
ce préfixe, il suffisait de lui donner le nonce d'un ticket pour recevoir
son sceau, et d'échanger ce faux ticket contre le jeton.

═══ POURQUOI L'ARRÊT DU SERVEUR NE COUPE JAMAIS L'AIDE ROOT ═══
L'aide écrivait dans un TUYAU vers ce serveur, dans le même groupe de
processus. Serveur arrêté (Ctrl+C, terminal fermé, kill, fin de session) :
Ctrl+C envoyait SIGINT à tout le groupe, apt et dpkg compris, et sinon le
premier journal() qui suivait le retour d'apt levait BrokenPipeError —
l'aide s'arrêtait avant le contrôle du module NVIDIA, sans résultat.
Maintenant l'aide tourne dans SA session (setsid : aucun signal du
terminal ne l'atteint) et écrit dans un FICHIER de notre dossier privé
(pilotes-tache.log, 0600), verrouillé par flock tant qu'elle le tient
ouvert. Le serveur suivant relit ce fichier : l'aide tourne encore, il la
suit ; elle a fini, son résultat s'affiche comme si de rien n'était.

Usage :
    python3 serveur.py [--port 0] [--sans-navigateur] [--nouveau]
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import hmac
import html
import http.client
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import moteur  # noqa: E402

DOSSIER_WEB = Path(__file__).resolve().parent / "web"
AIDE_ROOT = "/usr/bin/lexos-pilotes-maj"
HOTES_LOCAUX = {"127.0.0.1", "localhost", "::1", "[::1]"}
#  Tiré à chaque démarrage : un jeton volé à un serveur mort ne sert à rien.
JETON = secrets.token_urlsafe(32)

#  Une seule tâche à la fois : deux apt en parallèle, c'est un verrou dpkg
#  et un message d'erreur incompréhensible.
_verrou = threading.Lock()
_tache = {"action": None, "en_cours": False, "journal": [], "resultat": None, "debut": None}

#  Les tickets d'ouverture déjà échangés (un ticket ne sert qu'UNE fois), et
#  les pages d'ouverture écrites par CE processus (nonce → chemin), pour les
#  effacer dès qu'elles ont servi.
_verrou_tickets = threading.Lock()
_tickets_servis: set = set()
_ouvertures: dict = {}
_dossiers_temporaires: list = []
TICKET = re.compile(r"([0-9a-f]{32})\.([0-9a-f]{64})")


def _preuve(defi: str, jeton: str = "") -> str:
    return hmac.new((jeton or JETON).encode(), b"bonjour:" + defi.encode(), hashlib.sha256).hexdigest()


def _sceau(nonce: str, jeton: str = "") -> str:
    """Le sceau d'un ticket d'ouverture. Préfixe différent de _preuve() :
    /api/bonjour ne doit jamais pouvoir signer un ticket."""
    return hmac.new((jeton or JETON).encode(), b"ouvrir:" + nonce.encode(), hashlib.sha256).hexdigest()


def _echanger_ticket(ticket: str, port: int) -> bool:
    """Vrai si le ticket est scellé avec NOTRE jeton et n'a jamais servi.
    Il est alors dépensé, et sa page d'ouverture effacée."""
    m = TICKET.fullmatch(ticket or "")
    if not m or not hmac.compare_digest(m.group(2), _sceau(m.group(1))):
        return False
    nonce = m.group(1)
    with _verrou_tickets:
        if nonce in _tickets_servis:
            return False
        _tickets_servis.add(nonce)
        page = _ouvertures.pop(nonce, None)
    #  La page vient de servir : on l'efface tout de suite. Celle d'un
    #  deuxième clic a été écrite par un autre processus, dans le même
    #  dossier privé ; son nom suffit à la retrouver.
    d = dossier_execution()
    for f in (page, d / f"pilotes-ouvrir-{port}-{nonce}.html" if d else None):
        if f is not None:
            try:
                f.unlink()
            except OSError:
                pass
    return True


def _sans_resultat(code: Optional[int], journal: list) -> str:
    """Ce que pkexec veut dire quand l'aide n'a rendu aucun résultat.

    126 : la fenêtre a été fermée. 127 : autorisation refusée OU impossible
    — pas d'agent polkit, mot de passe faux trois fois, programme absent
    (pkexec.c:905-920). Tout traduire par « Mot de passe annulé » disait à
    Alex qu'il avait annulé une fenêtre qui ne s'était jamais ouverte.
    None : le code est perdu (l'aide a fini pendant que le serveur était
    arrêté) — on ne dit donc ni « annulé » ni « rien n'a été changé ».
    """
    derniere = next((l.strip() for l in reversed(journal) if l.strip()), "")
    tout = " ".join(journal[-6:])
    if code is None:
        return ("L'aide s'est arrêtée sans résultat pendant que LexOS Pilotes était fermé"
                + (f" : « {derniere[:200]} »" if derniere else "")
                + ". Ce qui a été fait est dans le journal ci-dessus.")
    if code == 126:
        return "Fenêtre de mot de passe fermée — rien n'a été changé."
    if code == 127:
        #  « textual authentication agent » : pas d'agent graphique, et pas
        #  de terminal pour l'agent texte de pkexec (l'aide tourne dans sa
        #  propre session, sans terminal de contrôle).
        if "No authentication agent found" in tout or "textual authentication agent" in tout:
            return ("Autorisation impossible : aucune fenêtre de mot de passe n'est disponible dans "
                    "cette session (aucun agent polkit ne tourne) — rien n'a été changé. Lance "
                    "« /usr/lib/lexos/polkit-agent » dans un terminal (il démarre l'agent installé), "
                    "puis réessaie.")
        if "Not authorized" in tout:
            return ("Autorisation refusée par polkit (mot de passe incorrect, ou compte sans droits "
                    "d'administration) — rien n'a été changé.")
        return (f"Autorisation impossible (pkexec, code 127){' : ' + derniere if derniere else ''} "
                "— rien n'a été changé.")
    return (f"L'aide s'est arrêtée sans résultat (code {code})"
            + (f" : « {derniere[:200]} »" if derniere else "")
            + ". Ce qui a été fait est dans le journal ci-dessus.")


# ── La tâche root : un fichier verrouillé, pas un tuyau ────────────────

JOURNAL_TACHE = "pilotes-tache.log"
ENTETE_TACHE = "LEXOS-TACHE "


def _chemin_journal_tache() -> Optional[Path]:
    d = dossier_execution()
    return d / JOURNAL_TACHE if d else None


def _aide_tient(fd: int) -> bool:
    """Vrai tant qu'une aide (ou pkexec) garde le journal ouvert. Le verrou
    suit le fichier OUVERT, hérité par l'enfant : il reste pris après la
    mort du serveur, et tombe quand l'aide sort. fd doit être une ouverture
    à part (un flock sur la nôtre réussirait toujours)."""
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    except OSError:
        return False
    fcntl.flock(fd, fcntl.LOCK_UN)
    return False


def _ligne_de_tache(ligne: str) -> None:
    if ligne.startswith(ENTETE_TACHE):
        return
    if ligne.startswith("LEXOS-RESULTAT "):
        try:
            _tache["resultat"] = json.loads(ligne[len("LEXOS-RESULTAT "):])
        except json.JSONDecodeError:
            pass
        return
    _tache["journal"].append(ligne)
    del _tache["journal"][:-400]


def _suivre_journal(fd: int, fini) -> None:
    """Relit le journal de la tâche jusqu'à ce que fini() soit vrai ET que
    tout soit lu. os.pread : on ne déplace pas la position où l'aide écrit
    (elle partage notre ouverture du fichier)."""
    pos, reste = 0, b""
    while True:
        termine = fini()
        while True:
            bloc = os.pread(fd, 65536, pos)
            if not bloc:
                break
            pos += len(bloc)
            *lignes, reste = (reste + bloc).split(b"\n")
            for ligne in lignes:
                _ligne_de_tache(ligne.decode("utf-8", "replace"))
        if termine:
            break
        time.sleep(0.1)
    if reste:
        _ligne_de_tache(reste.decode("utf-8", "replace"))


def _ouvrir_journal_tache(action: str, debut: float) -> Optional[int]:
    """Le fichier où l'aide écrira : 0600, verrouillé, avec son en-tête.
    None si une aide lancée par un AUTRE serveur le tient encore (une seule
    tâche à la fois, même à travers un redémarrage). OSError si on ne peut
    rien écrire du tout."""
    f = _chemin_journal_tache()
    if f is not None:
        try:
            ancien = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            ancien = None
        if ancien is not None:
            try:
                if _aide_tient(ancien):
                    return None
            finally:
                os.close(ancien)
        try:
            f.unlink(missing_ok=True)
            fd = os.open(f, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except OSError:
            f = None
    if f is None:
        #  Pas de dossier privé : un fichier anonyme. La tâche ira au bout
        #  quand même ; seul son résultat ne survivra pas au serveur.
        fd, nom = tempfile.mkstemp(prefix="lexos-pilotes-tache-")
        os.unlink(nom)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    except OSError:
        pass
    os.write(fd, (ENTETE_TACHE + json.dumps({"action": action, "debut": debut}) + "\n").encode("utf-8"))
    return fd


def _noter_resultat(fd: int) -> None:
    """Le résultat que CE serveur a établi lui-même (fenêtre de mot de passe
    fermée, refus de polkit, aide morte, pkexec absent) va aussi dans le
    journal de la tâche. Sans cette ligne, le serveur suivant n'y trouvait
    pas de « LEXOS-RESULTAT » et affichait, à chaque ouverture, « arrêtée
    sans résultat pendant que LexOS Pilotes était fermé » : faux — l'appli
    était ouverte, et le code était connu (relecture du 2026-10-24)."""
    try:
        taille = os.fstat(fd).st_size
        fin = os.pread(fd, 1, taille - 1) if taille else b"\n"
        ligne = "LEXOS-RESULTAT " + json.dumps(_tache["resultat"], ensure_ascii=False) + "\n"
        os.lseek(fd, 0, os.SEEK_END)
        os.write(fd, (("" if fin == b"\n" else "\n") + ligne).encode("utf-8"))
    except OSError:
        pass


def _lancer(action: str) -> bool:
    if not _verrou.acquire(blocking=False):
        return False
    debut = time.time()
    try:
        fd = _ouvrir_journal_tache(action, debut)
    except OSError as exc:
        _tache.update(action=action, en_cours=False, journal=[], debut=debut,
                      resultat={"ok": False, "message": f"Impossible d'écrire le journal de la tâche ({exc}) : "
                                                         "l'aide n'a pas été lancée — rien n'a été changé."})
        _verrou.release()
        return True
    if fd is None:
        _verrou.release()
        return False
    _tache.update(action=action, en_cours=True, journal=[], resultat=None, debut=debut)

    def travail() -> None:
        try:
            try:
                #  L'argv est FIXE : l'action vient d'une table du serveur,
                #  jamais de la requête. Pas de shell. Sa propre session, et
                #  le fichier pour sortie : ni Ctrl+C, ni la fermeture du
                #  terminal, ni la mort du serveur ne coupent apt ou dpkg.
                proc = subprocess.Popen(["pkexec", AIDE_ROOT, action], stdin=subprocess.DEVNULL,
                                        stdout=fd, stderr=fd, start_new_session=True)
            except OSError as exc:
                _tache["resultat"] = {"ok": False, "message": f"pkexec introuvable : {exc} — rien n'a été changé."}
                _noter_resultat(fd)
                return
            _suivre_journal(fd, lambda: proc.poll() is not None)
            code = proc.wait()
            if _tache["resultat"] is None:
                _tache["resultat"] = {"ok": False, "message": _sans_resultat(code, _tache["journal"])}
                _noter_resultat(fd)
        finally:
            os.close(fd)
            _tache["en_cours"] = False
            _verrou.release()

    threading.Thread(target=travail, daemon=True).start()
    return True


def reprendre_tache() -> bool:
    """Au démarrage : la tâche qu'un serveur précédent a lancée a continué
    sans lui, c'est voulu. On relit son journal : l'aide tourne encore, on
    la suit (la page affiche « en cours ») ; elle a fini, son résultat est
    là. Rend True si une tâche a été retrouvée."""
    f = _chemin_journal_tache()
    if f is None:
        return False
    try:
        fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return False
    try:
        st = os.fstat(fd)
        premiere = os.pread(fd, 4096, 0).split(b"\n", 1)[0].decode("utf-8", "replace")
        infos = json.loads(premiere[len(ENTETE_TACHE):]) if premiere.startswith(ENTETE_TACHE) else {}
        action = infos.get("action") if isinstance(infos, dict) else None
        debut = infos.get("debut") if isinstance(infos.get("debut"), (int, float)) else None
        valable = (stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o077
                   and action in ("verifier", "installer"))
    except (OSError, ValueError, AttributeError):
        valable = False
    if not valable or not _verrou.acquire(blocking=False):
        os.close(fd)
        return False
    _tache.update(action=action, en_cours=True, journal=[], resultat=None, debut=debut)

    def travail() -> None:
        try:
            _suivre_journal(fd, lambda: _tache["resultat"] is not None or not _aide_tient(fd))
            if _tache["resultat"] is None:
                _tache["resultat"] = {"ok": False, "message": _sans_resultat(None, _tache["journal"])}
        finally:
            os.close(fd)
            _tache["en_cours"] = False
            _verrou.release()

    threading.Thread(target=travail, daemon=True).start()
    return True


#  L'inscription MOK est INTERACTIVE : mokutil demande un mot de passe deux
#  fois, au clavier, et ce mot de passe sera retapé dans l'écran bleu au
#  redémarrage. On ne le fait donc pas transiter par cette page : on ouvre un
#  terminal sur l'assistant, qui pose ses questions lui-même. La ligne de
#  commande est FIXE — rien de ce que la page envoie n'y entre.
ASSISTANT_SIGNATURE = [
    "x-terminal-emulator", "-e", "bash", "-c",
    "sudo lexos-signer-pilote; echo; read -rp 'Entrée pour fermer cette fenêtre… ' _",
]


def _ouvrir_assistant_signature() -> bool:
    try:
        subprocess.Popen(ASSISTANT_SIGNATURE, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return False
    return True


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "LexOSPilotes/1.0"

    def _appelant_local(self) -> bool:
        hote = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        if hote not in HOTES_LOCAUX:
            return False
        origine = self.headers.get("Origin")
        if origine:
            #  L'origine EXACTE, port compris : une page servie par un autre
            #  programme sur 127.0.0.1:<autre port> a le même nom d'hôte.
            o = urlparse(origine)
            if o.scheme != "http" or o.hostname not in HOTES_LOCAUX or o.port != self.server.server_address[1]:
                return False
        return True

    def _jeton_ok(self) -> bool:
        return hmac.compare_digest((self.headers.get("X-Jeton") or "").encode(), JETON.encode())

    def log_message(self, format, *args):  # noqa: A002
        pass

    def _json(self, donnees, code: int = 200) -> None:
        corps = json.dumps(donnees, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def _statique(self, chemin: str) -> None:
        chemin = (chemin.lstrip("/") or "index.html")
        racine = DOSSIER_WEB.resolve()
        cible = (racine / chemin).resolve()
        if not cible.is_relative_to(racine):
            self.send_error(403, "Interdit")
            return
        if not cible.is_file():
            self.send_error(404, "Introuvable")
            return
        types = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
                 ".js": "application/javascript; charset=utf-8", ".svg": "image/svg+xml"}
        corps = cible.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", types.get(cible.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self) -> None:  # noqa: N802
        if not self._appelant_local():
            self.send_error(403, "Interdit")
            return
        url = urlparse(self.path)
        chemin = url.path
        try:
            if chemin == "/api/bonjour":
                #  La poignée de main du lanceur : prouver qu'on connaît le
                #  jeton sans le donner. Sans jeton exigé, par construction.
                defi = parse_qs(url.query).get("defi", [""])[0]
                if not re.fullmatch(r"[0-9a-f]{16,128}", defi):
                    self.send_error(400, "Défi invalide")
                    return
                self._json({"preuve": _preuve(defi)})
            elif chemin.startswith("/api/"):
                #  La page statique se charge sans jeton (elle ne contient
                #  rien de secret) ; toute l'API l'exige.
                if not self._jeton_ok():
                    self.send_error(403, "Interdit")
                elif chemin == "/api/etat":
                    self._json(moteur.instantane())
                elif chemin == "/api/tache":
                    self._json(_tache)
                else:
                    self.send_error(404, "Introuvable")
            else:
                self._statique(chemin)
        except Exception as exc:  # pragma: no cover - filet de sécurité
            self._json({"erreur": str(exc)}, 500)

    def do_POST(self) -> None:  # noqa: N802
        chemin = urlparse(self.path).path
        if chemin == "/api/entree":
            #  L'échange du ticket d'ouverture contre le jeton : la SEULE
            #  route sans jeton (c'est elle qui le donne). Le ticket est la
            #  serrure : scellé par HMAC, à usage unique, et seulement lisible
            #  dans un fichier 0600 de notre dossier privé.
            if (not self._appelant_local() or self.headers.get("X-LexOS") != "1"
                    or not _echanger_ticket(self.headers.get("X-Ticket") or "", self.server.server_address[1])):
                self.send_error(403, "Interdit")
                return
            self._json({"jeton": JETON})
            return
        #  Trois serrures : l'origine, le jeton de la session, et un en-tête
        #  maison qu'un formulaire d'un autre site ne peut pas ajouter sans
        #  une requête préalable (CORS) que ce serveur ne valide jamais.
        if not self._appelant_local() or self.headers.get("X-LexOS") != "1" or not self._jeton_ok():
            self.send_error(403, "Interdit")
            return
        if chemin == "/api/assistant-signature":
            if _ouvrir_assistant_signature():
                self._json({"lance": True})
            else:
                self._json({"lance": False, "message": "Aucun terminal trouvé (x-terminal-emulator)."}, 500)
            return
        actions = {"/api/verifier": "verifier", "/api/installer": "installer"}
        if chemin not in actions:
            self.send_error(404, "Introuvable")
            return
        if _lancer(actions[chemin]):
            self._json({"lance": True})
        else:
            self._json({"lance": False, "en_cours": True, "message": "Une tâche est déjà en cours."}, 409)


# ── Le fichier d'état et la poignée de main du deuxième clic ───────────────

def dossier_execution() -> Optional[Path]:
    """$XDG_RUNTIME_DIR/lexos (à l'utilisateur, 0700, nettoyé à la fermeture
    de session), comme le démon du Moteur. None si on ne peut pas garantir
    qu'il est à NOUS : un /tmp/lexos-<uid> créé par un autre compte servirait
    à nous faire ouvrir sa page."""
    base = os.environ.get("XDG_RUNTIME_DIR")
    d = Path(base) / "lexos" if base and Path(base).is_dir() else Path(f"/tmp/lexos-{os.getuid()}")
    try:
        d.mkdir(mode=0o700, parents=True, exist_ok=True)
        st = d.lstat()
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        return None
    return d


def fichier_etat() -> Optional[Path]:
    d = dossier_execution()
    return d / "pilotes.json" if d else None


def ecrire_etat(port: int) -> Optional[Path]:
    f = fichier_etat()
    if f is None:
        return None
    tmp = f.with_name(f".pilotes.{os.getpid()}.tmp")
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as sortie:
            json.dump({"port": port, "jeton": JETON, "pid": os.getpid()}, sortie)
        os.replace(tmp, f)
    except OSError:
        return None
    return f


def effacer_etat() -> None:
    f = fichier_etat()
    try:
        if f and json.loads(f.read_text(encoding="utf-8")).get("jeton") == JETON:
            f.unlink()
    except (OSError, ValueError):
        pass


def serveur_existant(delai: float = 1.5) -> Optional[tuple]:
    """(port, jeton) de NOTRE serveur déjà lancé, ou None.

    On ne croit pas le fichier sur parole : le port qu'il désigne peut être
    celui d'un serveur mort, repris depuis par n'importe qui. Le serveur doit
    rendre le HMAC d'un défi neuf avec le jeton du fichier."""
    f = fichier_etat()
    if f is None:
        return None
    try:
        st = f.lstat()
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
            return None
        etat = json.loads(f.read_text(encoding="utf-8"))
        port, jeton = int(etat["port"]), str(etat["jeton"])
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not 0 < port < 65536 or not jeton:
        return None
    defi = secrets.token_hex(16)
    #  http.client et pas urllib : urllib suivrait un $http_proxy jusque
    #  pour 127.0.0.1, et la poignée de main partirait ailleurs.
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=delai)
        try:
            c.request("GET", f"/api/bonjour?defi={defi}")
            r = c.getresponse()
            preuve = json.loads(r.read(4096).decode("utf-8")).get("preuve", "") if r.status == 200 else ""
        finally:
            c.close()
    except (OSError, ValueError, AttributeError, http.client.HTTPException):
        return None
    if not hmac.compare_digest(str(preuve), _preuve(defi, jeton)):
        return None
    return port, jeton


# ── La page d'ouverture : ce que reçoit le navigateur à la place du jeton ──

PAGE_OUVERTURE = """<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="referrer" content="no-referrer">
<title>LexOS Pilotes</title>
<noscript><meta http-equiv="refresh" content="0;url={cible_html}"></noscript>
<script>location.replace({cible_js});</script>
</head>
<body>
<p>Ouverture de LexOS Pilotes… Si rien ne se passe,
<a href="{cible_html}" rel="noreferrer">clique ici</a>.</p>
</body>
</html>
"""


def ecrire_ouverture(port: int, jeton: str) -> Optional[Path]:
    """Écrit la page d'ouverture (0600, dans un dossier 0700 à nous) et rend
    son chemin, ou None. Elle porte un ticket à usage unique, pas le jeton.

    Créée de façon atomique : O_EXCL sur un nom tiré au hasard (personne ne
    peut l'avoir préparée, ni en lien symbolique), mode 0600 DÈS la
    création, et renommée sous son nom final une fois complète — le
    navigateur ne peut pas lire une page à moitié écrite."""
    d = dossier_execution()
    if d is None:
        #  $XDG_RUNTIME_DIR inutilisable ET /tmp/lexos-<uid> pris par un
        #  autre compte : un dossier neuf, 0700 et au nom imprévisible.
        try:
            d = Path(tempfile.mkdtemp(prefix="lexos-pilotes-"))
        except OSError:
            return None
        _dossiers_temporaires.append(d)
    nonce = secrets.token_hex(16)
    cible = f"http://127.0.0.1:{int(port)}/#o={nonce}.{_sceau(nonce, jeton)}"
    page = d / f"pilotes-ouvrir-{int(port)}-{nonce}.html"
    tmp = d / f".pilotes-ouvrir-{nonce}.tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as sortie:
            sortie.write(PAGE_OUVERTURE.format(cible_html=html.escape(cible, quote=True),
                                               cible_js=json.dumps(cible)))
        os.rename(tmp, page)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass
        return None
    with _verrou_tickets:
        _ouvertures[nonce] = page
    return page


def effacer_ouvertures(port: int) -> None:
    """À l'arrêt : les pages d'ouverture de CE port qui n'ont jamais servi
    (navigateur fermé avant d'avoir chargé la page, deuxième clic…)."""
    with _verrou_tickets:
        pages = list(_ouvertures.values())
        _ouvertures.clear()
    d = dossier_execution()
    if d is not None:
        pages += list(d.glob(f"pilotes-ouvrir-{int(port)}-*.html"))
    for f in pages:
        try:
            f.unlink()
        except OSError:
            pass
    for d in list(_dossiers_temporaires):
        try:
            d.rmdir()
            _dossiers_temporaires.remove(d)
        except OSError:
            pass


def ouvrir_page(port: int, jeton: str) -> bool:
    """Ouvre la page dans le navigateur. L'argv de xdg-open (et celui du
    navigateur, lisible dans /proc par tous les comptes) ne porte QUE le
    chemin file:// de la page d'ouverture."""
    page = ecrire_ouverture(port, jeton)
    if page is None:
        print("[lexos-pilotes] impossible d'écrire la page d'ouverture dans un dossier privé : "
              "la page n'est pas ouverte, pour ne pas exposer le jeton de la session", file=sys.stderr)
        return False
    if not webbrowser.open(page.as_uri()):
        #  On laisse la page en place : un xdg-open très rapide peut avoir
        #  déjà rendu la main au navigateur. Le serveur l'efface à l'arrêt.
        print("[lexos-pilotes] aucun navigateur n'a pu être lancé (xdg-open)", file=sys.stderr)
        return False
    return True


def _arreter(_signal, _cadre) -> None:
    #  Fin de session (SIGHUP) ou « kill » (SIGTERM) : sans ceci, Python
    #  sortait sans passer par « finally », et le fichier d'état et les
    #  pages d'ouverture restaient derrière lui. Une tâche root en cours
    #  n'est PAS touchée : elle va au bout dans sa session (voir _lancer).
    raise SystemExit(0)


def main() -> None:
    a = argparse.ArgumentParser(description="LexOS Pilotes — serveur local")
    a.add_argument("--port", type=int, default=0, help="0 : un port libre (par défaut)")
    a.add_argument("--sans-navigateur", action="store_true")
    a.add_argument("--nouveau", action="store_true", help="ne pas rouvrir un serveur déjà lancé")
    args = a.parse_args()
    if not args.nouveau:
        existant = serveur_existant()
        if existant:
            #  Deuxième clic : un onglet de plus sur NOTRE serveur, avec sa
            #  propre page d'ouverture (un ticket neuf).
            print("[lexos-pilotes] déjà lancé : nouvel onglet", flush=True)
            if not args.sans_navigateur:
                ouvrir_page(*existant)
            return
    try:
        serveur = ThreadingHTTPServer(("127.0.0.1", args.port), Gestionnaire)
    except OSError as exc:
        print(f"[lexos-pilotes] impossible d'écouter sur 127.0.0.1:{args.port} : {exc}", file=sys.stderr)
        sys.exit(1)
    port = serveur.server_address[1]
    signal.signal(signal.SIGTERM, _arreter)
    #  Sous nohup, SIGHUP est ignoré EXPRÈS (« nohup lexos-pilotes & », puis
    #  on ferme le terminal) : on ne défait pas ce choix. Avant, ce
    #  gestionnaire remplaçait le SIG_IGN hérité, et fermer le terminal
    #  arrêtait le serveur.
    if signal.getsignal(signal.SIGHUP) is not signal.SIG_IGN:
        signal.signal(signal.SIGHUP, _arreter)
    try:
        reprendre_tache()
        if ecrire_etat(port) is None:
            print("[lexos-pilotes] $XDG_RUNTIME_DIR inutilisable : un deuxième clic ouvrira un "
                  "deuxième serveur", file=sys.stderr)
        #  Le journal ne montre que l'adresse nue : jamais le jeton.
        print(f"[lexos-pilotes] serveur local sur http://127.0.0.1:{port}/  (Ctrl+C pour arrêter)", flush=True)
        if not args.sans_navigateur:
            ouvrir_page(port, JETON)
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        effacer_etat()
        effacer_ouvertures(port)
        serveur.server_close()


if __name__ == "__main__":
    main()
