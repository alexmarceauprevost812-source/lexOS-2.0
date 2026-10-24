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
Terminal Pro : un jeton tiré au hasard au démarrage, connu de la seule
page qu'on ouvre (dans le fragment « #j=… », qui ne part jamais sur le
réseau), exigé sur toute l'API. Et « installer » a désormais sa propre
action polkit en auth_admin : chaque installation redemande le mot de passe.

═══ POURQUOI PLUS DE PORT FIXE ═══
Le lanceur ouvrait la page de QUICONQUE répondait 200 sur 127.0.0.1:7862,
même un autre utilisateur arrivé avant nous — une fausse page qui réclame
le mot de passe, c'est l'invite sudo maison que LexOS interdit. Le serveur
prend maintenant un port libre, et écrit {port, jeton} dans
$XDG_RUNTIME_DIR/lexos/pilotes.json (dossier 0700, fichier 0600). Au
deuxième clic, on ne croit ce fichier qu'après une poignée de main : le
serveur doit prouver qu'il connaît le jeton (HMAC d'un défi tiré au
hasard), sans que le jeton lui-même passe par la socket.

Usage :
    python3 serveur.py [--port 0] [--sans-navigateur] [--nouveau]
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import http.client
import json
import os
import secrets
import stat
import subprocess
import sys
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


def _preuve(defi: str, jeton: str = "") -> str:
    return hmac.new((jeton or JETON).encode(), defi.encode(), hashlib.sha256).hexdigest()


def _sans_resultat(code: int, journal: list) -> str:
    """Ce que pkexec veut dire quand l'aide n'a rendu aucun résultat.

    126 : la fenêtre a été fermée. 127 : autorisation refusée OU impossible
    — pas d'agent polkit, mot de passe faux trois fois, programme absent
    (pkexec.c:905-920). Tout traduire par « Mot de passe annulé » disait à
    Alex qu'il avait annulé une fenêtre qui ne s'était jamais ouverte.
    """
    derniere = next((l.strip() for l in reversed(journal) if l.strip()), "")
    tout = " ".join(journal[-6:])
    if code == 126:
        return "Fenêtre de mot de passe fermée — rien n'a été changé."
    if code == 127:
        if "No authentication agent found" in tout:
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


def _lancer(action: str) -> bool:
    if not _verrou.acquire(blocking=False):
        return False
    _tache.update(action=action, en_cours=True, journal=[], resultat=None, debut=time.time())

    def travail() -> None:
        try:
            #  L'argv est FIXE : l'action vient d'une table du serveur, jamais
            #  de la requête. Pas de shell.
            with subprocess.Popen(["pkexec", AIDE_ROOT, action], stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, bufsize=1) as proc:
                assert proc.stdout is not None
                for ligne in proc.stdout:
                    ligne = ligne.rstrip("\n")
                    if ligne.startswith("LEXOS-RESULTAT "):
                        try:
                            _tache["resultat"] = json.loads(ligne[len("LEXOS-RESULTAT "):])
                        except json.JSONDecodeError:
                            pass
                    else:
                        _tache["journal"].append(ligne)
                        del _tache["journal"][:-400]
                code = proc.wait()
            if _tache["resultat"] is None:
                _tache["resultat"] = {"ok": False, "message": _sans_resultat(code, _tache["journal"])}
        except OSError as exc:
            _tache["resultat"] = {"ok": False, "message": f"pkexec introuvable : {exc} — rien n'a été changé."}
        finally:
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
                if not 16 <= len(defi) <= 128:
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
        #  Trois serrures : l'origine, le jeton de la session, et un en-tête
        #  maison qu'un formulaire d'un autre site ne peut pas ajouter sans
        #  une requête préalable (CORS) que ce serveur ne valide jamais.
        if not self._appelant_local() or self.headers.get("X-LexOS") != "1" or not self._jeton_ok():
            self.send_error(403, "Interdit")
            return
        chemin = urlparse(self.path).path
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


def serveur_existant(delai: float = 1.5) -> Optional[str]:
    """L'URL (jeton compris) de NOTRE serveur déjà lancé, ou None.

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
    return f"http://127.0.0.1:{port}/#j={jeton}"


def main() -> None:
    a = argparse.ArgumentParser(description="LexOS Pilotes — serveur local")
    a.add_argument("--port", type=int, default=0, help="0 : un port libre (par défaut)")
    a.add_argument("--sans-navigateur", action="store_true")
    a.add_argument("--nouveau", action="store_true", help="ne pas rouvrir un serveur déjà lancé")
    args = a.parse_args()
    if not args.nouveau:
        url = serveur_existant()
        if url:
            #  Deuxième clic : un onglet de plus sur NOTRE serveur.
            print("[lexos-pilotes] déjà lancé : nouvel onglet")
            if not args.sans_navigateur:
                webbrowser.open(url)
            return
    try:
        serveur = ThreadingHTTPServer(("127.0.0.1", args.port), Gestionnaire)
    except OSError as exc:
        print(f"[lexos-pilotes] impossible d'écouter sur 127.0.0.1:{args.port} : {exc}", file=sys.stderr)
        sys.exit(1)
    port = serveur.server_address[1]
    if ecrire_etat(port) is None:
        print("[lexos-pilotes] $XDG_RUNTIME_DIR inutilisable : un deuxième clic ouvrira un "
              "deuxième serveur", file=sys.stderr)
    url = f"http://127.0.0.1:{port}/#j={JETON}"
    print(f"[lexos-pilotes] serveur local sur http://127.0.0.1:{port}/  (Ctrl+C pour arrêter)", flush=True)
    if not args.sans_navigateur:
        webbrowser.open(url)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        effacer_etat()
        serveur.server_close()


if __name__ == "__main__":
    main()
