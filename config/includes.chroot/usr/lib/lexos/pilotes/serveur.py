#!/usr/bin/env python3
"""LexOS Pilotes — serveur local (API JSON + interface web).

Même patron que LexOS Diagnostic : http.server de la bibliothèque standard,
écoute sur 127.0.0.1 seulement, et le navigateur ouvre la page.

Ce serveur tourne EN UTILISATEUR. Pour installer, il lance
« pkexec lexos-pilotes-maj installer » : la fenêtre de mot de passe est
celle du système (polkit), et c'est l'aide root qui recalcule elle-même
la liste des paquets. Le serveur ne lui transmet AUCUN nom de paquet.

Usage :
    python3 serveur.py [--port 7862] [--sans-navigateur]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import moteur  # noqa: E402

DOSSIER_WEB = Path(__file__).resolve().parent / "web"
PORT_DEFAUT = 7862
AIDE_ROOT = "/usr/bin/lexos-pilotes-maj"
HOTES_LOCAUX = {"127.0.0.1", "localhost", "::1", "[::1]"}

#  Une seule tâche à la fois : deux apt en parallèle, c'est un verrou dpkg
#  et un message d'erreur incompréhensible.
_verrou = threading.Lock()
_tache = {"action": None, "en_cours": False, "journal": [], "resultat": None, "debut": None}


def _lancer(action: str) -> bool:
    if not _verrou.acquire(blocking=False):
        return False
    _tache.update(action=action, en_cours=True, journal=[], resultat=None, debut=time.time())

    def travail() -> None:
        try:
            proc = subprocess.Popen(["pkexec", AIDE_ROOT, action], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, bufsize=1)
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
                #  126/127 : mot de passe refusé ou fenêtre fermée (pkexec).
                message = ("Mot de passe annulé — rien n'a été changé." if code in (126, 127)
                           else f"L'aide s'est arrêtée sans résultat (code {code}).")
                _tache["resultat"] = {"ok": False, "message": message}
        except OSError as exc:
            _tache["resultat"] = {"ok": False, "message": f"pkexec introuvable : {exc}"}
        finally:
            _tache["en_cours"] = False
            _verrou.release()

    threading.Thread(target=travail, daemon=True).start()
    return True


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "LexOSPilotes/1.0"

    def _appelant_local(self) -> bool:
        hote = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        if hote not in HOTES_LOCAUX:
            return False
        origine = self.headers.get("Origin")
        if origine and urlparse(origine).hostname not in HOTES_LOCAUX:
            return False
        return True

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
        chemin = urlparse(self.path).path
        try:
            if chemin == "/api/etat":
                self._json(moteur.instantane())
            elif chemin == "/api/tache":
                self._json(_tache)
            else:
                self._statique(chemin)
        except Exception as exc:  # pragma: no cover - filet de sécurité
            self._json({"erreur": str(exc)}, 500)

    def do_POST(self) -> None:  # noqa: N802
        #  En plus de l'origine : un en-tête maison. Un formulaire d'un autre
        #  site ne peut pas l'ajouter sans une requête préalable (CORS) que
        #  ce serveur ne valide jamais.
        if not self._appelant_local() or self.headers.get("X-LexOS") != "1":
            self.send_error(403, "Interdit")
            return
        chemin = urlparse(self.path).path
        actions = {"/api/verifier": "verifier", "/api/installer": "installer"}
        if chemin not in actions:
            self.send_error(404, "Introuvable")
            return
        if _lancer(actions[chemin]):
            self._json({"lance": True})
        else:
            self._json({"lance": False, "message": "Une tâche est déjà en cours."}, 409)


def main() -> None:
    a = argparse.ArgumentParser(description="LexOS Pilotes — serveur local")
    a.add_argument("--port", type=int, default=PORT_DEFAUT)
    a.add_argument("--sans-navigateur", action="store_true")
    args = a.parse_args()
    serveur = ThreadingHTTPServer(("127.0.0.1", args.port), Gestionnaire)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"[lexos-pilotes] serveur local sur {url}  (Ctrl+C pour arrêter)")
    if not args.sans_navigateur:
        webbrowser.open(url)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        serveur.server_close()


if __name__ == "__main__":
    main()
