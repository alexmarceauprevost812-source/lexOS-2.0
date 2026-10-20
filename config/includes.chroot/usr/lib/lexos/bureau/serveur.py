#!/usr/bin/env python3
"""LexOS Bureau — le moteur du bureau.

Le bureau de LexOS a l'allure du Bureau du Moteur d'Alex (MOTEUR-INTERFACE) :
fond animé, icônes en grille par sections, grande horloge, « Demande à
ti-lex IA… ». C'est une page web, dessinée par une fenêtre Qt posée dans le
calque du bureau (fenetre.py), et servie par ce fichier.

LE SERVEUR N'ÉCOUTE QUE 127.0.0.1, sur un port tiré au hasard, et chaque
requête doit porter un jeton tiré au hasard au démarrage, connu de la seule
fenêtre du bureau. Ce qu'il sait faire est fermé : lancer un élément DE SA
TABLE (applis.Table), ouvrir le Moteur sur un onglet, changer un réglage
validé (reglages.py). Aucun chemin, aucune commande ne vient de la page.

Usage : python3 serveur.py                  (le bureau, normalement par lexos-bureau)
        python3 serveur.py --sans-fenetre   (le serveur seul, pour les bancs)
"""
from __future__ import annotations

import argparse
import hmac
import json
import mimetypes
import os
import pwd
import secrets
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI))

import applis  # noqa: E402
import reglages  # noqa: E402

WEB = ICI / "web"
#  Les polices et le logo viennent du Moteur installé : une seule copie des
#  20 polices dans le système, celle de ti-lex IA.
MOTEUR_UI = Path(os.environ.get("LEXOS_BUREAU_MOTEUR_UI", "/usr/lib/lexos/ti-lex-ia/interface"))
HOTES_LOCAUX = {"127.0.0.1", "localhost"}
ACTIONS = ("parametres", "terminal", "dossier-bureau", "classique", "fond-suivant")


def prenom() -> str:
    try:
        p = pwd.getpwuid(os.getuid())
        nom = (p.pw_gecos or "").split(",")[0].strip()
        return (nom.split()[0] if nom else p.pw_name.capitalize())[:30]
    except (KeyError, IndexError):
        return ""


class Etat:
    def __init__(self) -> None:
        self.jeton = secrets.token_urlsafe(24)
        self.table = applis.Table()
        self.verrou = threading.Lock()
        #  Mis par le serveur (un fil à lui) quand le bureau doit se fermer —
        #  « revenir au bureau classique ». La fenêtre Qt le SURVEILLE depuis
        #  son propre fil : on ne touche jamais Qt depuis le fil du serveur.
        self.fin = threading.Event()
        #  Dernier lancement par icône : un double-clic (le réflexe d'XFCE)
        #  ne doit pas ouvrir l'appli deux fois.
        self.derniers: dict[str, float] = {}

    def construire(self) -> dict:
        r = reglages.lire()
        table = applis.Table()
        sections = []
        if r["tilex"]:
            s = table.section_tilex()
            if s:
                sections.append({"titre": "ti-lex IA", "elements": s})
        if r["lexos"]:
            s = table.section_lexos()
            if s:
                sections.append({"titre": "LexOS", "elements": s})
        if r["bureau"]:
            sections.append({"titre": "Mon bureau", "elements": table.section_bureau()})
        with self.verrou:
            self.table = table
        return {"prenom": prenom(), "reglages": r, "sections": sections,
                "tilex": bool(shutil.which("ti-lex-ia")),
                "couleurs": reglages.COULEURS, "polices": reglages.POLICES}

    def version(self) -> str:
        return reglages.empreinte() + "-" + applis.empreinte_bureau()


def fabriquer(etat: Etat):
    class G(BaseHTTPRequestHandler):
        server_version = "LexOSBureau/1.0"

        def log_message(self, *a):
            pass

        # ── garde ──
        def _local(self) -> bool:
            hote = (self.headers.get("Host") or "").rsplit(":", 1)[0]
            if hote not in HOTES_LOCAUX:
                return False
            o = self.headers.get("Origin")
            return not o or (urlparse(o).hostname in HOTES_LOCAUX)

        def _jeton_ok(self) -> bool:
            q = parse_qs(urlparse(self.path).query).get("t", [""])[0]
            j = self.headers.get("X-Jeton") or q
            return hmac.compare_digest(j.encode(), etat.jeton.encode())

        # ── réponses ──
        def _json(self, d, code=200):
            #  ensure_ascii : un nom de fichier non-UTF-8 qui aurait échappé à
            #  nom_lisible() ne peut plus faire tomber toute la réponse.
            b = json.dumps(d, ensure_ascii=True).encode("ascii")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(b)

        def _fichier(self, p: Path, cache=True, image_seule=False):
            try:
                b = p.read_bytes()
            except OSError:
                return self.send_error(404)
            t = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
            if p.suffix == ".woff2":
                t = "font/woff2"
            self.send_response(200)
            self.send_header("Content-Type", t)
            if image_seule:
                #  Une icône vient du dossier Bureau, donc de n'importe où :
                #  un SVG piégé ouvert COMME PAGE (glissé d'un écran à l'autre)
                #  tournerait sur notre origine. « sandbox » lui retire tout.
                self.send_header("Content-Security-Policy", "sandbox; default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'")
                self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(b)))
            self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
            self.end_headers()
            self.wfile.write(b)

        def _statique(self, chemin: str):
            racine, rel = WEB, chemin.lstrip("/") or "index.html"
            if rel == "polices.css" or rel.startswith("polices/") or rel == "logo.png":
                racine = MOTEUR_UI
            cible = (racine / rel).resolve()
            if not cible.is_relative_to(racine.resolve()) or not applis._est_fichier(cible):
                return self.send_error(404)
            self._fichier(cible)

        # ── routes ──
        #  Une erreur dans une requête ne doit JAMAIS laisser la page sans
        #  réponse : elle reçoit un 500 propre, l'erreur va au journal, et
        #  le bureau garde ce qu'il affichait.
        def do_GET(self):  # noqa: N802
            try:
                self._get()
            except Exception as e:  # noqa: BLE001
                print(f"[lexos-bureau] GET {self.path.split('?')[0]} : {e!r}", file=sys.stderr, flush=True)
                try:
                    self._json({"erreur": "interne"}, 500)
                except OSError:
                    pass

        def do_POST(self):  # noqa: N802
            try:
                self._post()
            except Exception as e:  # noqa: BLE001
                print(f"[lexos-bureau] POST {self.path.split('?')[0]} : {e!r}", file=sys.stderr, flush=True)
                try:
                    self._json({"erreur": "interne"}, 500)
                except OSError:
                    pass

        def _get(self):
            if not self._local():
                return self.send_error(403)
            chemin = urlparse(self.path).path
            #  « /fond » EXACTEMENT : « /fonds.js » commence pareil, et le
            #  prendre pour une route protégée le faisait refuser (403) —
            #  la page perdait alors tous ses fonds animés.
            if not (chemin.startswith(("/api/", "/icone/")) or chemin == "/fond"):
                return self._statique(chemin)
            if not self._jeton_ok():
                return self.send_error(403)
            if chemin == "/api/etat":
                return self._json(etat.construire())
            if chemin == "/api/version":
                return self._json({"v": etat.version()})
            if chemin.startswith("/icone/"):
                with etat.verrou:
                    p = etat.table.icones.get(chemin[len("/icone/"):])
                return self._fichier(p, cache=False, image_seule=True) if p else self.send_error(404)
            if chemin == "/fond":
                img = reglages.lire()["image"]
                p = Path(img) if img else None
                try:
                    bon = bool(p) and p.is_file() and p.stat().st_size < 40 * 1024 * 1024
                except OSError:
                    bon = False
                return self._fichier(p, cache=False, image_seule=True) if bon else self.send_error(404)
            self.send_error(404)

        def _post(self):
            if not self._local() or not self._jeton_ok():
                return self.send_error(403)
            n = min(int(self.headers.get("Content-Length") or 0), 64 * 1024)
            try:
                d = json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                d = {}
            if not isinstance(d, dict):
                d = {}
            chemin = urlparse(self.path).path
            if chemin == "/api/lancer":
                ident = str(d.get("id", ""))
                with etat.verrou:
                    a = etat.table.actions.get(ident)
                    maintenant = time.monotonic()
                    if a and maintenant - etat.derniers.get(ident, -9.0) < 1.2:
                        return self._json({"ok": True, "deja": True})
                    etat.derniers[ident] = maintenant
                if not a:
                    return self._json({"ok": False})
                r = applis.lancer(*a)
                if isinstance(r, str):
                    return self._json({"ok": False, "raison": r})
                return self._json({"ok": bool(r)})
            if chemin == "/api/demander":
                q = str(d.get("q", "")).strip()[:4000]
                if not q or not shutil.which("ti-lex-ia"):
                    return self._json({"ok": False})
                return self._json({"ok": applis._detache(["ti-lex-ia", "chat", q])})
            if chemin == "/api/reglages":
                r = reglages.ecrire(d)
                if r["mode"] == "classique":
                    etat.fin.set()
                return self._json({"ok": True, "reglages": r})
            if chemin == "/api/action":
                return self._json({"ok": action(str(d.get("nom", "")), etat)})
            self.send_error(404)
    return G


def action(nom: str, etat: Etat) -> bool:
    if nom not in ACTIONS:
        return False
    if nom == "parametres":
        for cmd in (["lexos-settings", "bureau"], ["lexos", "settings"]):
            if shutil.which(cmd[0]):
                return applis._detache(cmd)
        return False
    if nom == "terminal":
        return applis._detache(["exo-open", "--launch", "TerminalEmulator"]) if shutil.which("exo-open") \
            else applis._detache(["x-terminal-emulator"])
    if nom == "dossier-bureau":
        return applis.lancer("ouvrir", str(applis.dossier_bureau()))
    if nom == "fond-suivant":
        r = reglages.lire()
        i = (reglages.FONDS.index(r["anim"]) + 1) % len(reglages.FONDS)
        reglages.ecrire({"anim": reglages.FONDS[i]})
        return True
    if nom == "classique":
        reglages.ecrire({"mode": "classique"})
        etat.fin.set()
        return True
    return False


def arreter_xfdesktop() -> None:
    """Une seule fenêtre de bureau à la fois — voir l'en-tête de fenetre.py.
    Dans un fil à part : appelé depuis Qt, un xfdesktop lent à répondre
    gèlerait le bureau jusqu'à dix secondes."""
    def arreter():
        if shutil.which("xfdesktop"):
            try:
                subprocess.run(["xfdesktop", "--quit"], capture_output=True, timeout=10, check=False)
            except (OSError, subprocess.SubprocessError):
                pass
    threading.Thread(target=arreter, daemon=True).start()


def main() -> int:
    a = argparse.ArgumentParser(description="LexOS Bureau")
    a.add_argument("--sans-fenetre", action="store_true")
    a.add_argument("--port", type=int, default=0)
    args = a.parse_args()

    etat = Etat()
    serveur = ThreadingHTTPServer(("127.0.0.1", args.port), fabriquer(etat))
    serveur.daemon_threads = True
    threading.Thread(target=serveur.serve_forever, daemon=True).start()
    port = serveur.server_address[1]
    url = f"http://127.0.0.1:{port}/"

    if args.sans_fenetre:
        print(json.dumps({"url": url, "jeton": etat.jeton}), flush=True)
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            return 0

    #  Le réglage peut changer HORS de la page : « lexos-bureau classique »
    #  dans un terminal, ou les Paramètres de LexOS. On le relit chaque
    #  seconde ; « classique » ferme le bureau, et lexos-bureau relance
    #  xfdesktop derrière.
    def guetter_mode():
        vu = None
        while not etat.fin.is_set():
            e = reglages.empreinte()
            if e != vu:
                vu = e
                if reglages.lire()["mode"] == "classique":
                    etat.fin.set()
            etat.fin.wait(1.0)
    threading.Thread(target=guetter_mode, daemon=True).start()

    import fenetre
    from PySide6.QtCore import QTimer

    def pret():
        #  La fenêtre est affichée : xfdesktop peut partir. Deux secondes de
        #  marge — que la page ait peint quelque chose avant que l'ancien
        #  bureau disparaisse, sinon on verrait un écran vide entre les deux.
        QTimer.singleShot(2000, arreter_xfdesktop)

    code = fenetre.ouvrir(url, etat.jeton, signal_pret=pret, fin=etat.fin)
    serveur.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
