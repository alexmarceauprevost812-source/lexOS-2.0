#!/usr/bin/env python3
"""
LexOS — le volet qui descend de la barre du haut.

CE QUE C'EST, ET POURQUOI CE N'EST PAS UNE FENÊTRE.
Alex a demandé qu'un clic sur l'heure ouvre « comme un menu qui ouvre
tranquillement et fluide en descendant », montrant les notifications et
l'agenda ; pareil pour la météo. Une FENÊTRE et un VOLET ne sont pas la même
chose : une fenêtre se déplace, se redimensionne, se range dans Alt+Tab. Un
volet appartient à la barre — il en descend, un clic ailleurs le referme, et
il ne laisse aucune trace dans la liste des fenêtres.

POURQUOI LA MÊME PAGE WEB QUE LA DÉMO.
La règle qu'Alex a posée : « tout ce qu'on fait sur Vercel on le met aussi
dans l'ISO ». Le seul moyen SÛR que les deux se ressemblent vraiment est
qu'ils partagent le dessin, pas qu'on le recopie à la main d'un côté puis de
l'autre. Le volet est donc une fenêtre Qt sans cadre qui affiche une page
locale — même patron que les Paramètres (settings.py) et Cartes (cartes.py),
et même CSS que la démo. Ce qui change d'un côté se voit de l'autre.

CE QUI REND L'ANIMATION IDENTIQUE À LA DÉMO.
Elle n'est pas jouée par Qt mais par la PAGE, en CSS, avec exactement la même
courbe et la même durée que sur Vercel. Qt se contente d'ouvrir une fenêtre
transparente déjà à sa taille finale ; le volet s'y déplie tout seul. Une
animation jouée par Qt sur la géométrie de la fenêtre aurait redemandé un
redimensionnement au serveur X à chaque image — saccadé sur un portable de
2016 — et surtout elle n'aurait pas eu la même tête que la démo.

LA SÉCURITÉ, comme partout ailleurs dans LexOS : la page ne peut demander que
les actions de la liste blanche ACTIONS, les arguments sont validés contre des
ensembles fermés, et subprocess reçoit toujours une LISTE, jamais un shell.
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
from datetime import datetime, date
from pathlib import Path

BASE_DIR = Path(os.environ.get("LEXOS_VOLET_DIR", "/usr/share/lexos/volet"))
WEB_DIR = BASE_DIR / "web"

#  Les deux volets existants. La liste est fermée : « lexos-volet <quoi> »
#  n'ouvre rien d'autre, et le nom ne sert jamais à construire un chemin.
VOLETS = {"agenda", "meteo"}

CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
DONNEES = Path(os.environ.get("XDG_DATA_HOME",
                              Path.home() / ".local" / "share")) / "lexos"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
AGENDA = DONNEES / "agenda.json"


# =============================================================================
#  Les notifications
# =============================================================================
def _notifications():
    """Les notifications récentes, lues dans le journal de xfce4-notifyd.

    POURQUOI CE JOURNAL ET PAS UN À NOUS. xfce4-notifyd est le service qui
    reçoit RÉELLEMENT les notifications du système — batterie faible, clé USB
    branchée, mise à jour disponible. En tenir un deuxième en parallèle
    donnerait deux listes qui ne diraient pas la même chose. On lit donc la
    sienne. C'est aussi pour ça que xfce4-notifyd.xml active
    « notification-log » : sans ça, ce fichier n'existe pas et le volet
    n'aurait rien à montrer.

    Le format est un fichier de clés à la GLib : une section par notification,
    dont le nom est un horodatage. On le lit défensivement — un journal
    corrompu doit donner un volet vide, jamais une fenêtre qui ne s'ouvre pas.
    """
    chemin = CACHE / "xfce4" / "notifyd" / "log"
    if not chemin.is_file():
        return []
    import configparser
    lecteur = configparser.RawConfigParser(strict=False)
    #  Les résumés contiennent des majuscules qu'il ne faut pas écraser.
    lecteur.optionxform = str
    try:
        lecteur.read(chemin, encoding="utf-8")
    except (OSError, configparser.Error):
        return []

    sortie = []
    for nom in lecteur.sections():
        s = lecteur[nom]
        quand = ""
        #  Le nom de section EST l'horodatage, en secondes depuis 1970.
        try:
            quand = datetime.fromtimestamp(int(nom)).strftime("%H:%M")
        except (ValueError, OSError, OverflowError):
            quand = s.get("timestamp", "")
        sortie.append({
            "app": s.get("app_name", "").strip(),
            "titre": s.get("summary", "").strip(),
            "corps": s.get("body", "").strip(),
            "quand": quand,
            "cle": nom,
        })
    #  Les plus récentes en tête, et pas plus de cinquante : un journal de
    #  plusieurs milliers d'entrées ferait ramer l'ouverture du volet.
    sortie.sort(key=lambda n: n["cle"], reverse=True)
    return sortie[:50]


def act_notif_vide(_arg=None):
    """Vider le journal des notifications. On ÉCRASE le fichier au lieu de le
    supprimer : xfce4-notifyd garde son descripteur ouvert et recréerait un
    fichier qu'il serait seul à voir."""
    chemin = CACHE / "xfce4" / "notifyd" / "log"
    try:
        if chemin.is_file():
            chemin.write_text("", encoding="utf-8")
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "erreur": str(e)}


# =============================================================================
#  L'agenda
# =============================================================================
def _agenda_lit():
    """Les rendez-vous, dans un fichier à nous.

    POURQUOI PAS CELUI DE GNOME AGENDA. gnome-calendar range ses événements
    dans Evolution Data Server, qu'on ne peut interroger qu'en passant par
    ses bibliothèques — une dépendance lourde, et un service qui doit tourner.
    Le volet doit s'ouvrir instantanément au clic sur l'heure, y compris juste
    après le démarrage. Il garde donc sa propre liste, simple et lisible.
    gnome-calendar reste là pour qui veut des comptes en ligne : les deux ne
    se gênent pas, ils ne prétendent simplement pas être la même chose.
    """
    try:
        donnees = json.loads(AGENDA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(donnees, dict):
        return {}
    #  On filtre à la lecture : un fichier édité à la main ne doit pas pouvoir
    #  injecter n'importe quoi dans la page.
    propre = {}
    for jour, liste in donnees.items():
        if not isinstance(jour, str) or not isinstance(liste, list):
            continue
        evenements = []
        for e in liste[:50]:
            if not isinstance(e, dict):
                continue
            titre = str(e.get("titre", ""))[:120]
            heure = str(e.get("heure", ""))[:5]
            if titre:
                evenements.append({"titre": titre, "heure": heure})
        if evenements:
            propre[jour] = evenements
    return propre


def _agenda_ecrit(donnees):
    try:
        DONNEES.mkdir(parents=True, exist_ok=True)
        #  Écriture par fichier temporaire puis remplacement : une coupure de
        #  courant au mauvais moment ne peut pas laisser un agenda à moitié
        #  écrit, donc illisible.
        temporaire = AGENDA.with_suffix(".json.tmp")
        temporaire.write_text(json.dumps(donnees, ensure_ascii=False, indent=1),
                              encoding="utf-8")
        temporaire.replace(AGENDA)
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "erreur": str(e)}


def _jour_valide(texte):
    """AAAA-MM-JJ, et une VRAIE date. « 2026-02-31 » a la bonne forme mais
    n'existe pas ; le laisser passer donnerait un rendez-vous invisible."""
    try:
        date.fromisoformat(str(texte))
        return True
    except (ValueError, TypeError):
        return False


def act_agenda_ajoute(arg):
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    jour = str(arg.get("jour", ""))
    titre = str(arg.get("titre", "")).strip()[:120]
    heure = str(arg.get("heure", "")).strip()[:5]
    if not _jour_valide(jour):
        return {"ok": False, "erreur": "date invalide"}
    if not titre:
        return {"ok": False, "erreur": "il faut un titre"}
    if heure and not (len(heure) == 5 and heure[2] == ":"
                      and heure[:2].isdigit() and heure[3:].isdigit()
                      and int(heure[:2]) < 24 and int(heure[3:]) < 60):
        return {"ok": False, "erreur": "heure invalide (HH:MM)"}
    donnees = _agenda_lit()
    donnees.setdefault(jour, []).append({"titre": titre, "heure": heure})
    #  Triés par heure : un jour chargé se lit dans l'ordre où il se vivra.
    donnees[jour].sort(key=lambda e: e.get("heure") or "99:99")
    return _agenda_ecrit(donnees)


def act_agenda_enleve(arg):
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    jour = str(arg.get("jour", ""))
    try:
        rang = int(arg.get("rang", -1))
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "rang invalide"}
    donnees = _agenda_lit()
    if jour not in donnees or not (0 <= rang < len(donnees[jour])):
        return {"ok": False, "erreur": "introuvable"}
    donnees[jour].pop(rang)
    if not donnees[jour]:
        del donnees[jour]
    return _agenda_ecrit(donnees)


# =============================================================================
#  La météo — on demande à lexos-meteo, qui sait déjà tout faire
# =============================================================================
def _meteo():
    if shutil.which("lexos-meteo") is None:
        return {"ville": None, "erreur": "lexos-meteo absent"}
    try:
        r = subprocess.run(["lexos-meteo", "--json"],
                           capture_output=True, text=True, timeout=20)
        return json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError) as e:
        return {"ville": None, "erreur": str(e)}


def act_meteo_ville(_arg=None):
    """Ouvre le choix de ville. detach : c'est une fenêtre à part, et le volet
    doit pouvoir se refermer sans l'emporter."""
    if shutil.which("lexos-meteo") is None:
        return {"ok": False, "erreur": "lexos-meteo absent"}
    subprocess.Popen(["lexos-meteo", "--choisir"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


ACTIONS = {
    "notif-vide": act_notif_vide,
    "agenda-ajoute": act_agenda_ajoute,
    "agenda-enleve": act_agenda_enleve,
    "meteo-ville": act_meteo_ville,
}


def etat(quoi):
    commun = {"quoi": quoi, "aujourdhui": date.today().isoformat()}
    if quoi == "meteo":
        commun["meteo"] = _meteo()
    else:
        commun["notifications"] = _notifications()
        commun["agenda"] = _agenda_lit()
    return commun


# =============================================================================
#  Le petit serveur local — même forme que settings.py
# =============================================================================
class Handler(http.server.SimpleHTTPRequestHandler):
    quoi = "agenda"

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path == "/api/etat":
            return self._json(200, etat(self.quoi))
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
        except Exception as e:      # le volet doit survivre à un outil qui casse
            return self._json(200, {"ok": False, "erreur": str(e)})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _hauteur_barre():
    """La hauteur de la barre du haut, pour poser le volet JUSTE en dessous.

    Lue dans xfconf plutôt que codée en dur : quelqu'un qui grossit sa barre
    verrait sinon le volet la chevaucher ou flotter loin d'elle. La marge de
    la feuille GTK (4 px de chaque côté) s'y ajoute."""
    defaut = 32 + 8
    if shutil.which("xfconf-query") is None:
        return defaut
    try:
        r = subprocess.run(["xfconf-query", "-c", "xfce4-panel",
                            "-p", "/panels/panel-1/size"],
                           capture_output=True, text=True, timeout=5)
        v = r.stdout.strip()
        return int(v) + 8 if v.isdigit() else defaut
    except (subprocess.SubprocessError, OSError, ValueError):
        return defaut


def main():
    quoi = sys.argv[1] if len(sys.argv) > 1 else "agenda"
    if quoi not in VOLETS:
        print(f"Volet inconnu : {quoi}   (agenda · meteo)", file=sys.stderr)
        return 1
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        return 1

    mimetypes.add_type("text/javascript", ".js")

    Handler.quoi = quoi
    port = _port_libre()
    handler = functools.partial(Handler, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-volet-http").start()

    from PySide6.QtCore import QUrl, Qt, QTimer
    from PySide6.QtGui import QColor
    from PySide6.QtWidgets import QApplication
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName("Volet LexOS")

    vue = QWebEngineView()
    #  SANS CE FOND TRANSPARENT, RIEN NE MARCHE. La page dessine un volet aux
    #  coins ronds sur du vide ; si la vue web peint un fond blanc derrière,
    #  on obtient un rectangle blanc avec un volet arrondi dedans — le
    #  contraire de ce qu'on veut. Les trois lignes vont ensemble.
    vue.setAttribute(Qt.WA_TranslucentBackground, True)
    vue.page().setBackgroundColor(QColor(Qt.transparent))
    vue.setWindowFlags(Qt.FramelessWindowHint | Qt.Tool
                       | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint)
    vue.setAttribute(Qt.WA_DeleteOnClose, True)
    #  Qt.Tool : pas d'entrée dans Alt+Tab ni dans la liste des fenêtres.
    #  C'est ce qui fait la différence entre un volet et une fenêtre.

    ecran = app.primaryScreen().availableGeometry()
    largeur = min(560, ecran.width() - 24)
    hauteur = min(680, int(ecran.height() * 0.78))
    haut = ecran.y() + _hauteur_barre()

    #  L'agenda descend de l'HEURE, qui est au centre de la barre ; la météo
    #  descend de sa tuile, à gauche. Chacun tombe donc sous la sienne.
    if quoi == "meteo":
        gauche = ecran.x() + 14
    else:
        gauche = ecran.x() + (ecran.width() - largeur) // 2
    vue.setGeometry(gauche, haut, largeur, hauteur)

    vue.load(QUrl(f"http://127.0.0.1:{port}/index.html#{quoi}"))
    vue.show()
    vue.raise_()
    vue.activateWindow()

    #  UN CLIC AILLEURS REFERME — c'est ce qui fait d'un volet un volet.
    #  Le délai : au moment où la fenêtre apparaît, elle n'a pas encore le
    #  focus, et fermer sur « pas de focus » la tuerait avant qu'elle
    #  s'affiche. On n'arme la surveillance qu'une fois posée.
    def surveille():
        def verifie():
            if not vue.isActiveWindow():
                app.quit()
        minuteur = QTimer(vue)
        minuteur.timeout.connect(verifie)
        minuteur.start(250)

    QTimer.singleShot(700, surveille)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
