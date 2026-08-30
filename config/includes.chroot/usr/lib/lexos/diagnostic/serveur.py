#!/usr/bin/env python3
"""LexOS Diagnostic — serveur local (API JSON + interface web).

Sert uniquement sur 127.0.0.1 : rien de ce que cet outil mesure ne sort de
la machine — même esprit que lexos-ia-locale.md (« ça marche sans Internet,
rien ne sort de la machine »). Zéro dépendance au-delà de psutil : pas de
Flask ni FastAPI, http.server (stdlib) suffit pour un outil local à un seul
utilisateur — la même sobriété que verifier-parametres.sh (bash + grep +
find).

Usage :
    python3 serveur.py [--port 7861] [--sans-navigateur] [--onglet materiel]

Le lanceur usr/bin/lexos-diagnostic appelle ce script et ouvre le
navigateur par défaut dessus ; ce fichier peut aussi tourner seul pour
déboguer (python3 serveur.py, puis http://127.0.0.1:7861/).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import disques  # noqa: E402
import medecin  # noqa: E402
import moteur  # noqa: E402
from utils import executable_present, executer_json  # noqa: E402

DOSSIER_WEB = Path(__file__).resolve().parent / "web"
PORT_DEFAUT = 7861

# Petit cache pour qu'un rafraîchissement de page ne relance pas fwupdmgr
# (interroge le réseau LVFS) à chaque fois — seul le bouton « Vérifier »
# force une nouvelle interrogation.
_cache_firmware = {"horodatage": 0.0, "donnees": None}
DUREE_CACHE_FIRMWARE_S = 300


def _etat_firmware(forcer: bool = False) -> dict:
    maintenant = time.time()
    if not forcer and _cache_firmware["donnees"] is not None:
        if maintenant - _cache_firmware["horodatage"] < DUREE_CACHE_FIRMWARE_S:
            return _cache_firmware["donnees"]

    if not executable_present("fwupdmgr"):
        resultat = {
            "disponible": False,
            "message": "fwupdmgr non installé (paquet fwupd — voir 59-diagnostic.list)",
            "peripheriques": [],
            "mises_a_jour": [],
        }
        _cache_firmware["horodatage"] = maintenant
        _cache_firmware["donnees"] = resultat
        return resultat

    if forcer:
        # Best-effort : si le réseau est coupé ou LVFS injoignable, on
        # continue quand même avec ce que get-devices sait localement.
        executer_json(["fwupdmgr", "refresh", "--json"], timeout=45.0)

    peripheriques = executer_json(["fwupdmgr", "get-devices", "--json"], timeout=20.0) or {}
    maj = executer_json(["fwupdmgr", "get-updates", "--json"], timeout=20.0) or {}

    resultat = {
        "disponible": True,
        "message": None,
        "peripheriques": peripheriques.get("Devices", []) if isinstance(peripheriques, dict) else [],
        "mises_a_jour": maj.get("Devices", []) if isinstance(maj, dict) else [],
        "verifie_le": maintenant,
    }
    _cache_firmware["horodatage"] = maintenant
    _cache_firmware["donnees"] = resultat
    return resultat


#  ═══ AJOUT LexOS : QUI A LE DROIT DE PARLER À CE SERVEUR ═══
#  Le module arrive d'ailleurs et il est propre — lecture seule, aucun
#  shell=True, aucun sudo, HTML échappé partout. Une chose manquait quand
#  même, et elle compte parce que le port est FIXE (7861), contrairement au
#  serveur des Paramètres qui tire un port libre au lancement
#  (settings.py : bind sur le port 0) :
#
#  un port local prévisible est joignable par N'IMPORTE QUELLE page web que
#  l'utilisateur ouvre. Le navigateur l'empêchera de LIRE la réponse (même
#  origine), mais rien n'empêche l'envoi : un site pourrait déclencher un
#  scan de doublons de trente secondes sur le disque, en boucle. Et le nom
#  « localhost » peut être repointé vers une adresse extérieure (« DNS
#  rebinding »), auquel cas l'en-tête Host cesse d'être la boucle locale.
#
#  Deux vérifications suffisent, et ne coûtent rien à l'usage normal : notre
#  propre page n'envoie pas d'Origin étrangère, et son Host est bien
#  127.0.0.1. Tout le reste est refusé avant d'atteindre la moindre commande.
HOTES_LOCAUX = {"127.0.0.1", "localhost", "::1", "[::1]"}


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "LexOSDiagnostic/1.0"

    def _appelant_local(self) -> bool:
        hote = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        if hote not in HOTES_LOCAUX:
            return False
        origine = self.headers.get("Origin")
        if origine and urlparse(origine).hostname not in HOTES_LOCAUX:
            return False
        return True

    def log_message(self, format, *args):  # noqa: A002 - signature imposée
        pass  # silence : évite de polluer la console à chaque sondage (~1/s)

    # -- réponses -----------------------------------------------------------

    def _envoyer_json(self, donnees, code: int = 200) -> None:
        corps = json.dumps(donnees, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def _envoyer_texte(self, texte: str, code: int = 200) -> None:
        corps = texte.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def _servir_fichier_statique(self, chemin_relatif: str) -> None:
        if chemin_relatif in ("", "/"):
            chemin_relatif = "index.html"
        chemin_relatif = chemin_relatif.lstrip("/")
        racine = DOSSIER_WEB.resolve()
        cible = (racine / chemin_relatif).resolve()

        if not cible.is_relative_to(racine):  # protection contre /../..
            self.send_error(403, "Interdit")
            return
        if not cible.is_file():
            self.send_error(404, "Introuvable")
            return

        types = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "application/javascript; charset=utf-8",
            ".svg": "image/svg+xml",
        }
        corps = cible.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", types.get(cible.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    # -- routage --------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - imposé par BaseHTTPRequestHandler
        if not self._appelant_local():
            self.send_error(403, "Interdit")
            return
        chemin = urlparse(self.path).path
        try:
            if chemin == "/api/etat":
                self._envoyer_json(moteur.instantane())
            elif chemin == "/api/sante":
                self._envoyer_json(medecin.bilan_complet())
            elif chemin == "/api/sante/rapport":
                self._envoyer_texte(medecin.rapport_texte())
            elif chemin == "/api/disques":
                self._envoyer_json(disques.rapport_disques())
            elif chemin == "/api/firmware":
                self._envoyer_json(_etat_firmware(forcer=False))
            else:
                self._servir_fichier_statique(chemin)
        except Exception as exc:  # pragma: no cover - filet de sécurité
            self._envoyer_json({"erreur": str(exc)}, code=500)

    def do_POST(self) -> None:  # noqa: N802
        if not self._appelant_local():
            self.send_error(403, "Interdit")
            return
        chemin = urlparse(self.path).path
        longueur = int(self.headers.get("Content-Length", 0) or 0)
        corps_brut = self.rfile.read(longueur) if longueur else b""
        try:
            requete = json.loads(corps_brut) if corps_brut else {}
        except json.JSONDecodeError:
            requete = {}

        try:
            if chemin == "/api/disques/doublons":
                self._envoyer_json(disques.chercher_doublons(dossier=requete.get("dossier")))
            elif chemin == "/api/firmware/verifier":
                self._envoyer_json(_etat_firmware(forcer=True))
            else:
                self.send_error(404, "Introuvable")
        except Exception as exc:  # pragma: no cover
            self._envoyer_json({"erreur": str(exc)}, code=500)


def demarrer(port: int = PORT_DEFAUT, ouvrir_navigateur: bool = True, onglet: str = "materiel") -> None:
    serveur = ThreadingHTTPServer(("127.0.0.1", port), Gestionnaire)
    url = f"http://127.0.0.1:{port}/#{onglet}"
    print(f"[lexos-diagnostic] serveur local sur {url}  (Ctrl+C pour arrêter)")
    if ouvrir_navigateur:
        webbrowser.open(url)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        serveur.server_close()


def main() -> None:
    analyseur = argparse.ArgumentParser(description="LexOS Diagnostic — serveur local")
    analyseur.add_argument("--port", type=int, default=PORT_DEFAUT)
    analyseur.add_argument("--sans-navigateur", action="store_true")
    analyseur.add_argument("--onglet", default="materiel", choices=["materiel", "medecin", "disques"])
    args = analyseur.parse_args()
    demarrer(port=args.port, ouvrir_navigateur=not args.sans_navigateur, onglet=args.onglet)


if __name__ == "__main__":
    main()
