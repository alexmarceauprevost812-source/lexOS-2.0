#!/usr/bin/env python3
"""
LexOS 1.0.0 — application native de cartes pour Linux.

Fenêtre Qt (PySide6) contenant une carte web (MapLibre GL JS + données
OpenStreetMap réelles via OpenFreeMap) affichée dans un QWebEngineView.

Pourquoi un petit serveur HTTP local plutôt que d'ouvrir web/index.html
directement en file:// ?
  - Les modules ES (import/export utilisés par js/*.js) sont bloqués par
    la politique CORS de Chromium sous file://.
  - navigator.geolocation (position actuelle) exige un « contexte
    sécurisé » (https ou localhost) — file:// n'en est pas un.
On lance donc un serveur HTTP minimal sur 127.0.0.1, sur un port libre
choisi automatiquement, et on charge la page depuis là.
"""
import functools
import os
import http.server
import mimetypes
import socket
import subprocess
import sys
import threading
from pathlib import Path

from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication, QMainWindow
from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile
from PySide6.QtWebEngineWidgets import QWebEngineView

#  Ce même fichier sert à DEUX applications : « Cartes LexOS » (la carte du
#  monde livrée avec le système) et « GPS d'Alex » (la carte de navigation
#  écrite par Alex). Elles ont exactement les mêmes besoins — fenêtre Qt,
#  serveur local pour la géolocalisation — et seuls le nom, l'icône et le
#  dossier des fichiers changent. Plutôt que de recopier ce fichier, les
#  lanceurs le paramètrent par l'environnement.
APP_NAME = os.environ.get("LEXOS_CARTES_NOM", "Cartes LexOS")
APP_SOUS_TITRE = os.environ.get("LEXOS_CARTES_SOUS_TITRE", "Cartes")
APP_VERSION = "1.0.0"

#  Sur l'ISO, le code vit dans /usr/lib/lexos et les fichiers de la carte
#  dans /usr/share/lexos/cartes — la répartition attendue par le FHS. La
#  variable d'environnement sert au développement, hors installation.
BASE_DIR = Path(os.environ.get("LEXOS_CARTES_DIR", "/usr/share/lexos/cartes"))
WEB_DIR = BASE_DIR / "web"
ICON_PATH = BASE_DIR / "icone.png"


def _register_mime_types() -> None:
    """S'assure que .mjs est bien servi en JavaScript (sinon les imports
    de modules ES échouent avec un mauvais Content-Type)."""
    mimetypes.add_type("text/javascript", ".mjs")
    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")


def _find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler qui ne spamme pas la console."""

    def log_message(self, fmt, *args):  # noqa: A002 - signature imposée par la classe parente
        pass


def start_local_server(directory: Path, port: int) -> http.server.ThreadingHTTPServer:
    handler_cls = functools.partial(_QuietHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler_cls)
    thread = threading.Thread(target=server.serve_forever, daemon=True, name="lexos-http")
    thread.start()
    return server


class LexOSPage(QWebEnginePage):
    """Autorise la géolocalisation — mais seulement à notre propre page.

    QtWebEngine bloque navigator.geolocation en silence si personne ne
    répond à la demande de permission : aucune boîte de dialogue
    n'apparaît par défaut, et la carte reste sans position sans dire
    pourquoi. On répond donc oui.

    Mais oui À QUI. La version d'origine accordait la permission quelle
    que soit l'origine demandeuse ; une page tierce chargée dans cette
    vue aurait donc obtenu la position sans que personne soit consulté.
    On restreint au serveur local, seul à servir la carte.
    """

    def __init__(self, profile, parent, origine_permise: str):
        super().__init__(profile, parent)
        self._origine = origine_permise

    def featurePermissionRequested(self, url: QUrl, feature) -> None:
        meme_origine = f"{url.scheme()}://{url.host()}:{url.port()}" == self._origine
        if feature == QWebEnginePage.Feature.Geolocation and meme_origine:
            self.setFeaturePermission(
                url, feature, QWebEnginePage.PermissionPolicy.PermissionGrantedByUser
            )
        else:
            super().featurePermissionRequested(url, feature)


class MainWindow(QMainWindow):
    def __init__(self, start_url: str, origine: str):
        super().__init__()
        self.setWindowTitle(f"{APP_NAME} {APP_VERSION} — {APP_SOUS_TITRE}")
        self.resize(1280, 820)
        if ICON_PATH.exists():
            self.setWindowIcon(QIcon(str(ICON_PATH)))

        self.view = QWebEngineView(self)
        self.page = LexOSPage(QWebEngineProfile.defaultProfile(), self.view, origine)
        self.view.setPage(self.page)
        self.setCentralWidget(self.view)

        self.page.profile().downloadRequested.connect(self._handle_download)

        self.view.load(QUrl(start_url))

    def _handle_download(self, download) -> None:
        """Gère le bouton « Exporter une image » (téléchargement du PNG)."""
        #  xdg-user-dir donne le vrai dossier, « Téléchargements » sur une
        #  session française — « Downloads » en dur n'existerait pas.
        target_dir = Path.home()
        try:
            sortie = subprocess.run(["xdg-user-dir", "DOWNLOAD"],
                                    capture_output=True, text=True, timeout=3)
            candidat = Path(sortie.stdout.strip())
            if sortie.returncode == 0 and candidat.is_dir():
                target_dir = candidat
        except Exception:
            pass
        try:
            suggested_name = Path(download.downloadFileName()).name
        except Exception:
            suggested_name = "lexos-position.png"
        download.setDownloadDirectory(str(target_dir))
        download.setDownloadFileName(suggested_name)
        download.accept()


def main() -> None:
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    _register_mime_types()
    QApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(APP_VERSION)

    port = _find_free_port()
    server = start_local_server(WEB_DIR, port)

    origine = f"http://127.0.0.1:{port}"
    window = MainWindow(f"{origine}/index.html", origine)
    window.show()

    exit_code = app.exec()
    server.shutdown()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
