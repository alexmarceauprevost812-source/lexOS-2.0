#!/usr/bin/env python3
"""
LexOS — Paramètres : une seule fenêtre, une barre latérale, tous les réglages.

Même patron que Cartes LexOS (cartes.py) : une fenêtre Qt (PySide6) qui
affiche une page web servie par un petit serveur HTTP local. La page est
l'interface ; les actions réelles passent par une API locale (/api/…) que
le serveur exécute côté Python.

Pourquoi une API HTTP plutôt que QWebChannel : aucune dépendance de plus
(http.server est dans la bibliothèque standard, déjà utilisé par cartes.py),
et le pont est une LISTE BLANCHE — la page ne peut demander que les actions
définies ici, jamais une commande arbitraire.

Le serveur n'écoute que 127.0.0.1, sur un port libre tiré au lancement.
"""
import functools
import http.server
import json
import mimetypes
import os
import shutil
import socket
import subprocess
import sys
import threading
from pathlib import Path

APP_NAME = "Paramètres LexOS"
BASE_DIR = Path(os.environ.get("LEXOS_SETTINGS_DIR", "/usr/share/lexos/settings"))
WEB_DIR = BASE_DIR / "web"


# =============================================================================
#  Actions — la liste blanche.
#  Chaque entrée : nom -> fonction(arg) -> dict sérialisable en JSON.
#  Les arguments venant de la page sont validés contre des ensembles fermés :
#  jamais interpolés dans un shell.
# =============================================================================

def _run(argv, *, detach=False):
    """Lance une commande. detach=True pour les fenêtres graphiques."""
    if shutil.which(argv[0]) is None:
        return {"ok": False, "erreur": f"Outil absent : {argv[0]}"}
    if detach:
        subprocess.Popen(argv, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True}
    r = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    return {"ok": r.returncode == 0,
            "sortie": (r.stdout or r.stderr).strip()[-4000:]}


def _terminal(titre, commande):
    """Ouvre un outil en ligne de commande dans un terminal, comme le faisait
    l'ancien routeur bash — même forme d'appel que les .desktop du hook 0400
    (xfce4-terminal --hold -e "commande; bash"). `commande` est une chaîne
    fixe définie ICI, jamais construite depuis la page ; elle part telle
    quelle comme UN SEUL élément d'argv (pas de ré-interprétation shell côté
    Python : subprocess.Popen reçoit une liste, jamais shell=True)."""
    return _run(["xfce4-terminal", f"--title={titre}", "--hold", "-e",
                 f"{commande}; bash"], detach=True)


def _xfce(module):
    return _run(["xfce4-settings-manager", "-s", module], detach=True)


PERFS = {"petit", "medium", "performant", "max"}
THEMES = {"sombre", "clair"}
ACCENTS = {"orange", "orange-rouge", "bleu", "rouge", "vert", "gris",
           "violet", "neon"}
POLICES = {"defaut", "classique", "mono", "manuscrite"}
DOCKS = {"droite", "gauche", "bas", "haut"}
CADRAGES = {"remplir", "ajuster", "etirer", "centrer", "mosaique"}
FONDS = {
    "defaut":  "/usr/share/backgrounds/lexos/wallpaper.png",
    "secu":    "/usr/share/backgrounds/lexos/wallpaper-secu.png",
    "demon":   "/usr/share/backgrounds/lexos/wallpaper-demon.png",
    "keyart":  "/usr/share/backgrounds/lexos/wallpaper-keyart.png",
}
LANGUES = {
    "fr_CA.UTF-8", "fr_FR.UTF-8", "en_US.UTF-8", "en_CA.UTF-8", "en_GB.UTF-8",
    "es_ES.UTF-8", "es_MX.UTF-8", "de_DE.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8",
    "ru_RU.UTF-8", "zh_CN.UTF-8", "ja_JP.UTF-8", "ko_KR.UTF-8", "ar_SA.UTF-8",
}


def act_ouvrir(arg):
    """Ouvre l'outil complet d'une section — reprise exacte de l'ancien
    routeur bash (hook 0450)."""
    outils = {
        "wifi":       lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "reseau":     lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "bluetooth":  lambda: _terminal("Bluetooth — LexOS", "lexos bt scan"),
        "ecrans":     lambda: _run(["lexos-display", "gui"], detach=True),
        "son":        lambda: _xfce("mixer"),
        "energie":    lambda: _terminal("Énergie — LexOS", "lexos perf status; echo; lexos lumiere"),
        "usb":        lambda: _terminal("USB — LexOS", "lexos usb; echo; echo 'Formater un support : lexos format'"),
        "mac":        lambda: _terminal("Mac (Apple) — LexOS", "lexos mac"),
        "apparence":  lambda: _xfce("appearance"),
        "bureau":     lambda: _xfce("xfdesktop"),
        "multitaches": lambda: _xfce("workspaces"),
        "applications": lambda: _run(["exo-preferred-applications"], detach=True),
        "notifications": lambda: _run(["xfce4-notifyd-config"], detach=True),
        "recherche":  lambda: _run(["xfce4-appfinder", "--collapsed"], detach=True),
        "partage":    lambda: _run(["lexos-share", "devices"], detach=True),
        "souris":     lambda: _xfce("pointers"),
        "couleurs":   lambda: _run(["gcm-viewer"], detach=True),
        "imprimantes": lambda: _run(["system-config-printer"], detach=True),
        "amovibles":  lambda: _xfce("thunar-volman"),
        "tablette":   lambda: _xfce("wacom"),
        "confidentialite": lambda: _terminal("Confidentialité et sécurité — LexOS",
                                             "lexos net status; echo; lexos secure"),
        "maj":        lambda: _terminal("Mises à jour — LexOS", "lexos doctor"),
        "accessibilite": lambda: _xfce("accessibility"),
        "utilisateurs": lambda: _terminal("Utilisateurs — LexOS",
                                          "printf '%s\\n' 'Comptes locaux de LexOS :' '' "
                                          "'  lex     — Principal, administrateur' "
                                          "'  invite  — Invité, session limitée sans mot de passe' ''"),
        "clavier":    lambda: _xfce("keyboard"),
        "datetime":   lambda: _terminal("Date et heure — LexOS", "timedatectl"),
        "defaut":     lambda: _run(["exo-preferred-applications"], detach=True),
        "distant":    lambda: _terminal("Bureau à distance — LexOS",
                                        "echo 'Bureau à distance : lexos install x11vnc, puis x11vnc -display :0'"),
        "apropos":    lambda: _run(["lexos-welcome", "--about"], detach=True),
    }
    fn = outils.get(arg)
    if fn is None:
        return {"ok": False, "erreur": f"Section inconnue : {arg}"}
    return fn()


def act_avion(arg):
    if arg not in {"toggle", "on", "off"}:
        return {"ok": False, "erreur": "avion : toggle|on|off"}
    return _run(["lexos-net", "avion", arg])


def act_perf(arg):
    if arg not in PERFS:
        return {"ok": False, "erreur": "profil inconnu"}
    return _run(["lexos-perf", arg])


def act_lumiere(arg):
    try:
        n = int(arg)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "luminosité : un nombre 5-100"}
    n = max(5, min(100, n))
    return _run(["lexos-brightness", str(n)])


def act_theme(arg):
    if arg not in THEMES:
        return {"ok": False, "erreur": "thème : sombre|clair"}
    return _run(["lexos", "theme", arg])


def act_accent(arg):
    if arg not in ACCENTS:
        return {"ok": False, "erreur": "accent inconnu"}
    return _run(["lexos", "accent", arg])


def act_police(arg):
    if arg not in POLICES:
        return {"ok": False, "erreur": "police inconnue"}
    return _run(["lexos", "police", arg])


def act_dock(arg):
    if arg not in DOCKS:
        return {"ok": False, "erreur": "position : droite|gauche|bas|haut"}
    return _run(["lexos", "dock", arg])


def act_fond(arg):
    chemin = FONDS.get(arg)
    if chemin is None:
        return {"ok": False, "erreur": "fond inconnu"}
    if not Path(chemin).exists():
        return {"ok": False, "erreur": f"Image absente : {chemin}"}
    return _run(["lexos", "wallpaper", chemin, "remplir"])


#  Les scènes animées sont LUES SUR LE DISQUE, jamais recopiées dans une liste.
#  L'aide du terminal annonçait « ciel » alors que le fichier s'appelle
#  « etoiles » : la commande copiée de la documentation échouait mot pour mot.
#  Une liste écrite à la main finit toujours par mentir ; celle-ci ne peut pas.
FONDS_ANIMES_DIRS = ("/usr/share/lexos/fonds", "~/.config/lexos/fonds")


def _animes_disponibles():
    noms = set()
    for d in FONDS_ANIMES_DIRS:
        try:
            for f in Path(d).expanduser().glob("*.json"):
                # « modele » est le gabarit à copier, pas une scène à poser.
                if f.stem != "modele":
                    noms.add(f.stem)
        except OSError:
            continue
    return noms


def act_fond_anime(arg):
    """Pose un fond animé, ou le retire. Le nom vient de la page : il est donc
    validé contre ce qui existe RÉELLEMENT sur le disque avant tout appel."""
    if arg in ("off", "stop", "arret"):
        return _run(["lexos", "wallpaper", "anime", "off"])
    dispo = _animes_disponibles()
    if arg not in dispo:
        connues = " · ".join(sorted(dispo)) or "aucune"
        return {"ok": False, "erreur": f"scène inconnue. Installées : {connues}"}
    return _run(["lexos", "wallpaper", "anime", arg])


def act_fond_capture(arg):
    """Capture l'écran et en fait le fond d'écran — les deux outils existaient
    déjà mais rien ne les reliait, il fallait retenir le chemin du fichier."""
    mode = arg if arg in ("plein", "zone") else "plein"
    if shutil.which("lexos-capture") is None:
        return {"ok": False, "erreur": "lexos-capture absent"}
    return _run(["lexos-capture", "fond", mode], detach=True)


def act_fond_perso(arg):
    """Ouvre un sélecteur de fichier (zenity) puis applique l'image choisie.
    Le chemin vient du sélecteur local, pas de la page."""
    if shutil.which("zenity") is None:
        return {"ok": False, "erreur": "zenity absent"}
    r = subprocess.run(
        ["zenity", "--file-selection", "--title=Choisir un fond d'écran",
         "--file-filter=Images | *.jpg *.jpeg *.png *.webp *.avif *.bmp *.tif *.tiff *.gif"],
        capture_output=True, text=True, timeout=600)
    chemin = r.stdout.strip()
    if r.returncode != 0 or not chemin:
        return {"ok": False, "erreur": "Aucun fichier choisi"}
    cadrage = arg if arg in CADRAGES else "remplir"
    return _run(["lexos", "wallpaper", chemin, cadrage])


def act_langue(arg):
    if arg not in LANGUES:
        return {"ok": False, "erreur": "langue inconnue"}
    return _run(["lexos", "lang", arg])


def act_capture(arg):
    modes = {"photo": ["lexos-capture"], "zone": ["lexos-capture", "zone"],
             "fenetre": ["lexos-capture", "fenetre"]}
    argv = modes.get(arg)
    if argv is None:
        return {"ok": False, "erreur": "capture : photo|zone|fenetre"}
    return _run(argv, detach=True)


ACTIONS = {
    "ouvrir": act_ouvrir,
    "avion": act_avion,
    "perf": act_perf,
    "lumiere": act_lumiere,
    "theme": act_theme,
    "accent": act_accent,
    "police": act_police,
    "dock": act_dock,
    "fond": act_fond,
    "fond-perso": act_fond_perso,
    "fond-anime": act_fond_anime,
    "fond-capture": act_fond_capture,
    "langue": act_langue,
    "capture": act_capture,
}


# =============================================================================
#  État — ce que la page affiche au chargement.
# =============================================================================

def _sortie(argv):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def etat():
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def fichier(nom, defaut):
        try:
            return (conf / nom).read_text().strip() or defaut
        except OSError:
            return defaut

    #  Même règle que avion_state() dans lexos-net : « -t » (terse) donne des
    #  mots-clés fixes, jamais traduits — contrairement à la sortie normale de
    #  nmcli, qui suit la langue du système (fr_CA par défaut sur LexOS).
    avion = "off"
    if shutil.which("nmcli"):
        wifi = _sortie(["nmcli", "-t", "radio", "wifi"]) or "?"
        wwan = _sortie(["nmcli", "-t", "radio", "wwan"]) or "?"
        if wifi == "disabled" and wwan in ("disabled", "missing"):
            avion = "on"

    version = ""
    try:
        for ligne in Path("/etc/os-release").read_text().splitlines():
            if ligne.startswith("PRETTY_NAME="):
                version = ligne.split("=", 1)[1].strip('"')
                break
    except OSError:
        pass

    try:
        perf = Path("/etc/lexos/performance").read_text().strip() or "medium"
    except OSError:
        perf = "medium"

    return {
        "perf": perf,
        "theme": fichier("mode", "sombre"),
        "accent": fichier("accent", "orange"),
        "police": fichier("police", "defaut"),
        "avion": avion,
        "hote": socket.gethostname(),
        "version": version or "LexOS 1.0 « Nomad »",
        "noyau": _sortie(["uname", "-r"]),
    }


# =============================================================================
#  Serveur : fichiers statiques + API.
# =============================================================================

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path == "/api/etat":
            return self._json(200, etat())
        return super().do_GET()

    def do_POST(self):
        if not self.path.startswith("/api/action"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        action = ACTIONS.get(requete.get("action", ""))
        if action is None:
            return self._json(400, {"ok": False, "erreur": "action inconnue"})
        try:
            return self._json(200, action(requete.get("arg")))
        except subprocess.TimeoutExpired:
            return self._json(200, {"ok": False, "erreur": "délai dépassé"})
        except Exception as e:  # la fenêtre doit survivre à un outil qui casse
            return self._json(200, {"ok": False, "erreur": str(e)})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")

    section = ""
    if len(sys.argv) > 1 and sys.argv[1].replace("-", "").isalnum():
        section = sys.argv[1]

    port = _port_libre()
    handler = functools.partial(Handler, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-settings-http").start()

    url = f"http://127.0.0.1:{port}/index.html"
    if section:
        url += f"#{section}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)

    #  La fenêtre s'ouvrait à 980 x 700, quel que soit l'écran. Sur le
    #  ThinkPad (1366 x 768), 700 pixels de haut coupaient la barre latérale
    #  au milieu : Alex voyait la liste s'arrêter à « Partage » et pensait
    #  qu'il manquait des sections. Les 32 sections sont bien là et la barre
    #  défile — mais une fenêtre qui n'utilise pas l'écran donne l'impression
    #  contraire.
    #
    #  Ubuntu ouvre ses Paramètres à la taille de l'écran disponible. On fait
    #  pareil : on prend ce que le bureau laisse (barre du haut et dock
    #  déduits, c'est ce que renvoie availableGeometry), sans jamais dépasser
    #  une largeur confortable en lecture ni descendre sous une taille
    #  utilisable.
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(900, min(1180, int(dispo.width() * 0.92)))
        hauteur = max(600, min(900, int(dispo.height() * 0.94)))
        fenetre.resize(largeur, hauteur)
        #  Centrer : sur un petit écran, une fenêtre presque aussi grande que
        #  le bureau posée en haut à gauche déborde à droite et en bas.
        fenetre.move(
            dispo.x() + (dispo.width() - largeur) // 2,
            dispo.y() + (dispo.height() - hauteur) // 2,
        )
    else:
        fenetre.resize(980, 700)
    icone = "/usr/share/icons/hicolor/128x128/apps/lexos-reglages.png"
    if Path(icone).exists():
        fenetre.setWindowIcon(QIcon(icone))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)
    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
