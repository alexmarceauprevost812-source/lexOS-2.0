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
import gestes  # noqa: E402
import reglages  # noqa: E402

WEB = ICI / "web"
#  Les polices et le logo viennent du Moteur installé : une seule copie des
#  20 polices dans le système, celle de ti-lex IA.
MOTEUR_UI = Path(os.environ.get("LEXOS_BUREAU_MOTEUR_UI", "/usr/lib/lexos/ti-lex-ia/interface"))
HOTES_LOCAUX = {"127.0.0.1", "localhost"}
ACTIONS = ("parametres", "terminal", "dossier-bureau", "classique", "fond-suivant", "ranger", "audit", "reseau",
           "nouveau-dossier", "nouveau-document", "terminal-bureau", "affichage")


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

    def _tout(self) -> tuple[dict, dict]:
        """Réglages + TOUTES les sections, et la table qui sait les lancer.

        La table contient TOUT, même ce que le bureau cache (une section
        décochée, les applis du labo) : le bureau et le labo partagent ce
        serveur, et chacun reconstruit la table — si celle du bureau oubliait
        les applis du labo, un clic dans le labo ne lancerait plus rien."""
        r = reglages.lire()
        table = applis.Table()
        tout = {"tilex": table.section_tilex(), "lexos": table.section_lexos(),
                "bureau": table.section_bureau(), "applis": table.section_applis(),
                "demon": table.section_demon()}
        with self.verrou:
            self.table = table
        return r, tout

    def construire(self) -> dict:
        r, tout = self._tout()
        sections = []
        #  « cote » : comme le Bureau du Moteur (nouvelle version), l'IA à
        #  gauche et les outils à droite. Les fichiers d'Alex vont sous l'IA,
        #  à gauche — là où on cherche ses fichiers sur un bureau.
        if r["tilex"] and tout["tilex"]:
            sections.append({"titre": "ti-lex IA", "cote": "gauche", "elements": tout["tilex"]})
        if r["lexos"] and tout["lexos"]:
            sections.append({"titre": "LexOS", "cote": "droite", "elements": tout["lexos"]})
        if r["bureau"]:
            sections.append({"titre": "Mon bureau", "cote": "gauche", "elements": tout["bureau"]})
        return {"prenom": prenom(), "reglages": r, "sections": sections,
                "tilex": bool(shutil.which("ti-lex-ia")), "dock": dock(), "zone": ZONE.lire(),
                "labo": [e["id"] for e in labo_choisis(r, tout)],
                "couleurs": reglages.COULEURS, "polices": reglages.POLICES,
                #  Le dock et les icônes du bureau démon (demon.html), et de
                #  quoi signer sa devise : « LEXOS 2.0 · NOMADE ».
                "demon": demon_avec_ajouts(r, tout), "systeme": systeme()}

    def construire_outils(self) -> dict:
        """🎛️ Mes outils : le son, les notifications, et les outils placés."""
        r, tout = self._tout()
        sections = [{"titre": t, "elements": tout[c]} for c, t in
                    (("tilex", "ti-lex IA"), ("lexos", "LexOS"), ("bureau", "Mon bureau"),
                     ("applis", "Toutes les applications")) if tout[c]]
        return {"apps": outils_choisis(r, tout), "sections": sections, "prenom": prenom(),
                "son": gestes.son_etat(), "notifs": gestes.notifications(), "dnd": gestes.ne_pas_deranger(),
                "bureaux": gestes.bureaux(),
                "audit": bool(applis.trouver_desktop("lexos-audit")),
                "reglages": {k: r[k] for k in ("accent", "police", "outils_apps")}}

    def construire_labo(self) -> dict:
        """🧪 Mon labo : ce qu'Alex y a mis, et de quoi en ajouter."""
        r, tout = self._tout()
        sections = [{"titre": t, "elements": tout[c]} for c, t in
                    (("tilex", "ti-lex IA"), ("lexos", "LexOS"), ("bureau", "Mon bureau"),
                     ("applis", "Toutes les applications")) if tout[c]]
        return {"apps": labo_choisis(r, tout), "sections": sections, "prenom": prenom(),
                "reglages": {k: r[k] for k in ("accent", "police", "labo_apps")}}

    def version(self) -> str:
        #  La base dconf du compte change quand on déplace le dock (« lexos
        #  dock droite ») : la page refait alors sa place autour de lui.
        try:
            d = int(DCONF.stat().st_mtime_ns)
        except OSError:
            d = 0
        z = ".".join(map(str, ZONE.lire()))
        return reglages.empreinte() + "-" + applis.empreinte_bureau() + "-" + str(d) + "-" + z


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
            #  La vidéo d'ouverture du bureau démon (demon.html). Écrit ici,
            #  pas laissé à mimetypes : sa table dépend de /etc/mime.types, et
            #  une vidéo servie en « octet-stream » ne joue pas — l'ouverture
            #  retomberait sur les yeux en CSS sans dire pourquoi.
            if p.suffix == ".webm":
                t = "video/webm"
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
            #  « / », c'est LA page du bureau : la grille du Moteur ou le
            #  démon, selon le réglage « interface » (saveur nomade : le
            #  démon d'office). Jamais gardée en cache : quand la page change
            #  ce réglage, elle se recharge et doit recevoir l'AUTRE page.
            #  « /index.html » et « /demon.html » restent servies telles quelles,
            #  SAUF dans la nomade : là, le démon est LE bureau, pour de bon
            #  (décision d'Alex, 2026-10-29) — « / » comme « /index.html »
            #  rendent demon.html, quoi que dise un bureau.json d'avant.
            if chemin in ("", "/") or (reglages.NOMADE and chemin == "/index.html"):
                demon = reglages.NOMADE or reglages.lire()["interface"] == "demon"
                return self._fichier(WEB / ("demon.html" if demon else "index.html"), cache=False)
            racine, rel = WEB, chemin.lstrip("/") or "index.html"
            if rel == "polices.css" or rel.startswith("polices/") or rel in ("logo.png", "lexos-nomad.png"):
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
            if chemin == "/api/labo":
                return self._json(etat.construire_labo())
            if chemin == "/api/outils":
                return self._json(etat.construire_outils())
            if chemin == "/api/etat":
                return self._json(etat.construire())
            if chemin == "/api/reseau":
                return self._json(gestes.reseau_etat())
            if chemin == "/api/son":
                return self._json(gestes.son_etat())
            if chemin == "/api/bureaux":
                #  Le bureau virtuel affiché (les boutons 1 2 3 4 du bureau démon).
                return self._json(gestes.bureaux())
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
                #  « abo » : 🌐 Mon abonnement (ChatGPT, Claude, Gemini… sur
                #  leur site officiel), la question déjà écrite. Rien d'autre
                #  que ces deux onglets-là.
                vers = "abo" if d.get("vers") == "abo" else "chat"
                if not q or not shutil.which("ti-lex-ia"):
                    return self._json({"ok": False})
                return self._json({"ok": applis._detache(["ti-lex-ia", vers, q])})
            if chemin == "/api/son":
                return self._json(gestes.son(d))
            if chemin == "/api/bureau":
                return self._json(gestes.bureau(d))
            if chemin == "/api/capture":
                return self._json({"ok": gestes.capture(str(d.get("mode", "")))})
            if chemin == "/api/notifs":
                return self._json(gestes.notifs(d))
            if chemin == "/api/session":
                return self._json({"ok": gestes.session(str(d.get("geste", "")))})
            if chemin == "/api/reglages":
                r = reglages.ecrire(d)
                if r["mode"] == "classique":
                    etat.fin.set()
                return self._json({"ok": True, "reglages": r})
            if chemin == "/api/action":
                return self._json({"ok": action(str(d.get("nom", "")), etat)})
            self.send_error(404)
    return G


class ZoneTravail:
    """_NET_WORKAREA : l'écran MOINS ce que la barre du haut réserve.

    POURQUOI LA PAGE NE SE FIE PLUS À QT POUR ÇA. Sur le PC d'Alex, la
    colonne d'icônes passait SOUS la barre du haut : le bureau démarre avant
    xfce4-panel, Qt lit l'aire disponible à ce moment-là (l'écran entier),
    et ne la relit plus — mesuré sous Xvfb + xfwm4 : tuer et relancer
    xfce4-panel change _NET_WORKAREA, mais availableGeometryChanged ne vient
    jamais. On lit donc la propriété ici, à chaque « /api/version » (une
    lecture X, quelques microsecondes), et la page refait ses marges.
    python3-xlib est dans la liste stricte des paquets (lexos-core)."""

    def __init__(self) -> None:
        self.verrou = threading.Lock()
        self.ecran = None

    def lire(self) -> list[int]:
        with self.verrou:
            for _ in range(2):
                try:
                    if self.ecran is None:
                        from Xlib import display  # noqa: PLC0415
                        self.ecran = display.Display()
                    racine = self.ecran.screen().root
                    p = racine.get_full_property(self.ecran.intern_atom("_NET_WORKAREA"), 0)
                    v = list(p.value[:4]) if p is not None and len(p.value) >= 4 else []
                    return [int(n) for n in v]
                except Exception:       # pas de Xlib, X fermé, connexion perdue
                    try:
                        if self.ecran is not None:
                            self.ecran.close()
                    except Exception:
                        pass
                    self.ecran = None
            return []


ZONE = ZoneTravail()


def _choisis(ids: list, tout: dict, defaut: list) -> list[dict]:
    connus: dict[str, dict] = {}
    for cle in ("tilex", "lexos", "bureau", "applis"):
        for e in tout[cle]:
            connus.setdefault(e["id"], e)
    return [connus[i] for i in (defaut if ids == ["*"] else ids) if i in connus]


def labo_choisis(r: dict, tout: dict) -> list[dict]:
    """Les éléments du labo, dans l'ordre d'Alex. Une appli désinstallée
    (identifiant introuvable) disparaît sans bruit ; ["*"] = pas encore
    choisi : les onglets de ti-lex IA, puis le terminal, Fichiers et le
    navigateur."""
    defaut = [e["id"] for e in tout["tilex"]]
    defaut += [e["id"] for e in tout["lexos"] if e["nom"] in ("Terminal TI-LEX", "Fichiers", "Navigateur Web")]
    return _choisis(r["labo_apps"], tout, defaut)


def outils_choisis(r: dict, tout: dict) -> list[dict]:
    """Les outils qu'Alex a placés dans 🎛️ Mes outils ; au départ, trois
    outils LexOS — à lui de les changer (« ＋ »)."""
    defaut = [e["id"] for e in tout["lexos"] if e["nom"] in ("Paramètres", "Moniteur système", "Pilotes")]
    return _choisis(r["outils_apps"], tout, defaut)


DCONF = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "dconf" / "user"
SCHEMA_DOCK = "net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"


def dock() -> dict:
    """Où est le dock Plank, et sa taille : {"cote": "right", "taille": 64}.

    Il se cache seulement quand une fenêtre le touche (« intelligent ») :
    sur le bureau vide, il est là, PAR-DESSUS la page — et il ne réserve
    pas sa place à l'écran (pas de « strut »). Sans ça, la colonne d'icônes
    de droite passait sous le dock posé à droite (« lexos dock droite »)."""
    vide = {"cote": "", "taille": 0}
    if not shutil.which("gsettings") or not shutil.which("plank"):
        return vide
    #  Plank installé mais ÉTEINT (le cas normal depuis le 2026-11-01) : il
    #  ne prend aucune place, et le nouveau dock se colle au vrai bord.
    try:
        if subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "plank"],
                          capture_output=True, timeout=2).returncode != 0:
            return vide
    except (OSError, subprocess.SubprocessError):
        return vide
    try:
        def lire(cle: str) -> str:
            return subprocess.run(["gsettings", "get", SCHEMA_DOCK, cle], capture_output=True,
                                  text=True, timeout=2).stdout.strip().strip("'")
        cote, taille = lire("position"), lire("icon-size")
    except (OSError, subprocess.SubprocessError):
        return vide
    if cote not in ("left", "right", "top", "bottom"):
        return vide
    return {"cote": cote, "taille": int(taille) if taille.isdigit() else 48}


def demon_avec_ajouts(r: dict, tout: dict) -> list[dict]:
    """Les tuiles du bureau démon, PLUS les applis qu'Alex y a ajoutées (« on
    peut ajouter les applications dans toute la fenêtre du bureau »). Une
    appli ajoutée est cherchée dans TOUTES les sections : celle qui a été
    désinstallée depuis disparaît d'elle-même, sans laisser de tuile morte."""
    out = list(tout["demon"])
    vus = {e["id"] for e in out}
    index = {}
    for cle in ("applis", "lexos", "tilex", "bureau"):
        for e in tout.get(cle) or []:
            index.setdefault(e.get("id"), e)
    for ident in r.get("demon_ajouts") or []:
        e = index.get(ident)
        if e and ident not in vus:
            vus.add(ident)
            out.append({"id": ident, "cle": "appli", "nom": e.get("nom", ""), "icone": bool(e.get("icone")),
                        "ajout": True})
    return out


def systeme() -> dict:
    """Nom, version et saveur de l'ISO, lus dans build.conf (jamais exécuté)."""
    vals = {"LEXOS_NAME": "LexOS", "LEXOS_VERSION": "", "LEXOS_FLAVOUR": reglages.saveur()}
    try:
        for ligne in reglages.BUILD_CONF.read_text(encoding="utf-8").splitlines():
            cle, _, v = ligne.partition("=")
            if cle in ("LEXOS_NAME", "LEXOS_VERSION"):
                vals[cle] = v.strip().strip('"').strip("'")[:40]
    except (OSError, UnicodeDecodeError):
        pass
    try:
        compte = pwd.getpwuid(os.getuid()).pw_name[:32]
    except KeyError:
        compte = ""
    #  « À propos » du bureau démon (la tuile Tux) : ce que lexfetch dirait,
    #  lu dans /proc — quelques lectures de fichiers, rien n'est lancé.
    def lire(chemin: str, cle: str) -> str:
        try:
            for ligne in Path(chemin).read_text(encoding="utf-8", errors="replace").splitlines():
                if ligne.startswith(cle):
                    return ligne.split(":", 1)[1].strip()
        except OSError:
            pass
        return ""
    memoire = lire("/proc/meminfo", "MemTotal")
    try:
        memoire = f"{round(int(memoire.split()[0]) / 1048576, 1)} Gio" if memoire else ""
    except (ValueError, IndexError):
        memoire = ""
    try:
        secondes = int(float(Path("/proc/uptime").read_text().split()[0]))
        allume = f"{secondes // 3600} h {secondes % 3600 // 60:02d}"
    except (OSError, ValueError, IndexError):
        allume = ""
    #  « compte » : pour l'invite du petit terminal du bureau démon
    #  (« alex@lexos-nomade:~$ »), comme dans un vrai terminal.
    return {"nom": vals["LEXOS_NAME"] or "LexOS", "version": vals["LEXOS_VERSION"],
            "saveur": vals["LEXOS_FLAVOUR"][:20], "compte": compte,
            "noyau": os.uname().release[:60], "processeur": lire("/proc/cpuinfo", "model name")[:80],
            "memoire": memoire, "allume": allume}


def nouveau_sur_le_bureau(dossier: bool) -> bool:
    """« Nouveau dossier » / « Nouveau document » dans ~/Bureau, sans jamais
    écraser : « Nouveau dossier 2 », « 3 »… Le nom vient d'ici, pas de la page."""
    d = applis.dossier_bureau()
    base, ext = ("Nouveau dossier", "") if dossier else ("Nouveau document", ".txt")
    try:
        d.mkdir(parents=True, exist_ok=True)
        for n in range(1, 200):
            p = d / (f"{base}{ext}" if n == 1 else f"{base} {n}{ext}")
            try:
                if dossier:
                    p.mkdir()
                else:
                    with open(p, "x", encoding="utf-8"):
                        pass
                return True
            except FileExistsError:
                continue
    except OSError:
        pass
    return False


def action(nom: str, etat: Etat) -> bool:
    if nom not in ACTIONS:
        return False
    if nom == "parametres":
        for cmd in (["lexos-settings", "bureau"], ["lexos", "settings"]):
            if shutil.which(cmd[0]):
                return applis._detache(cmd)
        return False
    if nom == "reseau":
        #  Le réseau, sans la barre du haut (bureau démon) : la section Wi-Fi
        #  des Paramètres de LexOS, sinon l'éditeur de NetworkManager.
        for cmd in (["lexos-settings", "wifi"], ["nm-connection-editor"]):
            if shutil.which(cmd[0]):
                return applis._detache(cmd)
        return False
    if nom == "terminal":
        return applis._detache(["exo-open", "--launch", "TerminalEmulator"]) if shutil.which("exo-open") \
            else applis._detache(["x-terminal-emulator"])
    if nom == "audit":
        #  La mascotte d'Alex, dans 🎛️ Mes outils : l'appli « Outils
        #  d'audit » de LexOS, telle qu'elle est installée.
        p = applis.trouver_desktop("lexos-audit")
        return bool(p) and applis.lancer("desktop", str(p))
    if nom == "dossier-bureau":
        return applis.lancer("ouvrir", str(applis.dossier_bureau()))
    if nom == "ranger":
        reglages.ecrire({"positions": {}})
        return True
    #  Le clic droit du bureau démon, comme celui d'Ubuntu (2026-10-31).
    if nom in ("nouveau-dossier", "nouveau-document"):
        return nouveau_sur_le_bureau(nom == "nouveau-dossier")
    if nom == "terminal-bureau":
        d = str(applis.dossier_bureau())
        if shutil.which("exo-open"):
            return applis._detache(["exo-open", "--working-directory", d, "--launch", "TerminalEmulator"])
        return applis._detache(["x-terminal-emulator", "--working-directory", d])
    if nom == "affichage":
        for cmd in (["lexos-settings", "ecrans"], ["xfce4-display-settings"]):
            if shutil.which(cmd[0]):
                return applis._detache(cmd)
        return False
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


#  ═══ UN SEUL DOCK : L'ANCIEN (Plank) S'EN VA ═══
#  ALEX (2026-11-01), capture à l'appui : « on est rendu avec 2 docks,
#  supprimer l'ancien et garder le new ». Le nouveau dock est celui du bureau
#  démon (demon.css, .dock), collé au bord droit. Plank était lancé par
#  ~/.config/autostart/plank.desktop, copié de /etc/skel à la création du
#  compte — /etc/skel ne le pose plus, mais un compte déjà créé le garde.
#  On l'éteint donc ici, une fois le bureau affiché : « Hidden=true » dans
#  la copie de l'utilisateur (la façon XDG de désactiver un autostart, que
#  le Gestionnaire de session respecte), puis on ferme celui qui roule.
#  Plank reste installé : « plank & » le ramène à la main si on y tient.
def arreter_plank() -> None:
    def arreter():
        auto = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "autostart" / "plank.desktop"
        try:
            if auto.is_file():
                texte = auto.read_text("utf-8")
                if "Hidden=true" not in texte:
                    auto.write_text(texte.rstrip("\n") + "\nHidden=true\n", "utf-8")
        except OSError:
            pass
        try:
            subprocess.run(["pkill", "-u", str(os.getuid()), "-x", "plank"],
                           capture_output=True, timeout=5, check=False)
        except (OSError, subprocess.SubprocessError):
            pass
    threading.Thread(target=arreter, daemon=True).start()


def main() -> int:
    a = argparse.ArgumentParser(description="LexOS Bureau")
    a.add_argument("--sans-fenetre", action="store_true")
    a.add_argument("--port", type=int, default=0)
    args = a.parse_args()
    #  SIGUSR1 (« lexos-bureau labo ») TUE un processus par défaut : on
    #  l'ignore d'abord, et la fenêtre du labo le prend dès qu'elle existe.
    import signal
    signal.signal(signal.SIGUSR1, signal.SIG_IGN)
    signal.signal(signal.SIGUSR2, signal.SIG_IGN)

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
        QTimer.singleShot(2000, arreter_plank)

    code = fenetre.ouvrir(url, etat.jeton, signal_pret=pret, fin=etat.fin)
    serveur.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
