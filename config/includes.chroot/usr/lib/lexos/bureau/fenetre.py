"""LexOS Bureau — la fenêtre Qt qui EST le bureau.

Une vue web sans cadre, de la taille de chaque écran, posée dans le calque
_NET_WM_WINDOW_TYPE_DESKTOP : sous toutes les fenêtres, hors d'Alt+Tab et de
la barre des tâches, et elle reste là quand on fait « Afficher le bureau ».

═══ POURQUOI ÇA NE REFAIT PAS LA PANNE DES FONDS ANIMÉS ═══
Les fonds animés retirés en 2026 (voir settings.py, « LES FONDS ANIMÉS ONT
ÉTÉ RETIRÉS ») posaient une fenêtre DANS le calque de xfdesktop, À CÔTÉ de
lui : xfwm4 n'ordonne pas deux fenêtres de ce calque entre elles, et le fond
passait devant les icônes de xfdesktop. Ici, il n'y a jamais DEUX fenêtres
de bureau : ce bureau dessine lui-même ses icônes, et lexos-bureau arrête
xfdesktop une fois cette fenêtre affichée (et le relance si elle tombe).
Éprouvé sous Xvfb avec le vrai xfwm4 et le vrai xfdesktop 4.18.

═══ LE TYPE DE FENÊTRE : POSÉ PAR QT, APRÈS L'AFFICHAGE ═══
Trois essais mesurés sous Xvfb + xfwm4 4.18, pour qu'on ne les refasse pas :
  · xprop avant show() : Qt RÉÉCRIT la propriété en affichant → NORMAL ;
  · la propriété Qt « _q_xcb_wm_window_type » avant show() : marche sur un
    QWidget, PAS sur une QWebEngineView — Qt recrée la fenêtre native au
    premier affichage (surface OpenGL) et la propriété ne suit pas ;
  · la même propriété APRÈS show(), suivie d'un setFlags() qui la fait
    relire : _NET_WM_WINDOW_TYPE_DESKTOP en tête de liste, et xfwm4 range
    la fenêtre dans le calque du bureau (états BELOW, STICKY, SKIP_TASKBAR).
    Activée et levée exprès par xdotool, elle reste SOUS Thunar. C'est
    celle-là qu'on garde.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from urllib.parse import urlencode


XCB_TYPE_BUREAU = 0x000002     # QXcbWindow::Desktop, dans le greffon xcb de Qt


def ouvrir(url_base: str, jeton: str, signal_pret=None, fin=None) -> int:
    #  Sans accélération graphique (mode fail-safe, pilote absent, machine
    #  virtuelle), Chromium dessine le fond mais pas le contenu de la page.
    #  lexos-bureau passe LEXOS_BUREAU_SANS_GPU=1 dans ces cas-là.
    if os.environ.get("LEXOS_BUREAU_SANS_GPU") == "1":
        drapeaux = os.environ.get("QTWEBENGINE_CHROMIUM_FLAGS", "")
        os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = (drapeaux + " --disable-gpu").strip()

    from PySide6.QtCore import Qt, QTimer, QUrl
    from PySide6.QtGui import QColor
    from PySide6.QtWidgets import QApplication
    from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineSettings
    from PySide6.QtWebEngineWidgets import QWebEngineView

    base = QUrl(url_base)

    class PageBureau(QWebEnginePage):
        """La page du bureau ne va NULLE PART ailleurs que chez elle.
        Sans ça, glisser un fichier ou un lien sur le bureau (le geste
        « copier sur le Bureau » depuis Fichiers) remplaçait le bureau par ce
        fichier ou ce site jusqu'à la session suivante."""
        def acceptNavigationRequest(self, url, genre, principal):  # noqa: N802
            if not principal:
                return True
            meme = (url.scheme() == base.scheme() and url.host() == base.host()
                    and url.port() == base.port() and url.path() in ("/", "/index.html"))
            return meme

    class VueBureau(QWebEngineView):
        """Le bureau ne se ferme pas. Alt+F4 sur lui, c'est la fenêtre « Fermer
        la session » — exactement ce que fait xfdesktop. Avant, Qt acceptait
        la fermeture, cachait la vue, et le processus restait en vie : plus de
        bureau du tout, et lexos-bureau ne voyait rien tomber."""
        def closeEvent(self, ev):  # noqa: N802
            ev.ignore()
            if shutil.which("xfce4-session-logout"):
                subprocess.Popen(["xfce4-session-logout"], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    app = QApplication(sys.argv)
    app.setApplicationName("LexOS Bureau")
    app.setQuitOnLastWindowClosed(False)
    vues: list = []
    etat = {"pret": False, "echecs": 0}

    def tomber(raison: str):
        #  Une page morte ou blanche n'est PAS un bureau : on sort en erreur
        #  pour que lexos-bureau remette xfdesktop tout de suite.
        print(f"[lexos-bureau] {raison} — on rend la main au bureau classique", file=sys.stderr, flush=True)
        app.exit(1)

    def poser(ecran, principal: bool):
        g, d = ecran.geometry(), ecran.availableGeometry()
        vue = VueBureau()
        page = PageBureau(vue)
        vue.setPage(page)
        reglages = page.settings()
        reglages.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, False)
        try:
            reglages.setAttribute(QWebEngineSettings.WebAttribute.NavigateOnDropEnabled, False)
        except AttributeError:      # Qt < 6.4 : l'acceptNavigationRequest suffit
            pass
        vue.setAcceptDrops(False)
        vue.setWindowTitle("LexOS Bureau")
        page.setBackgroundColor(QColor("#070707"))
        #  PETITE d'abord, et c'est voulu. Une fenêtre NORMALE de la taille de
        #  l'écran est MAXIMISÉE d'office par xfwm4, avec sa barre de titre ;
        #  et elle garde ce décalage de 24 px même une fois devenue fenêtre de
        #  bureau (mesuré). À 64 x 64, xfwm4 n'y touche pas ; elle ne prend
        #  la taille de l'écran qu'une fois typée « bureau » (type_bureau).
        vue.setGeometry(g.x(), g.y(), 64, 64)
        vue.setWindowFlags(Qt.Window | Qt.WindowStaysOnBottomHint)
        #  Ce que la barre du haut et le dock prennent sur CET écran : la
        #  page s'en écarte pour ne rien cacher sous eux.
        marges = {
            "t": jeton,
            "ecran": "principal" if principal else "autre",
            "haut": max(0, d.top() - g.top()),
            "bas": max(0, g.bottom() - d.bottom()),
            "gauche": max(0, d.left() - g.left()),
            "droite": max(0, g.right() - d.right()),
            #  La place de l'écran dans le bureau virtuel : la page s'en sert
            #  avec _NET_WORKAREA (serveur.py, ZoneTravail), que Qt ne relit
            #  pas quand la barre du haut arrive APRÈS le bureau.
            "gx": g.x(), "gy": g.y(), "gl": g.width(), "gh": g.height(),
        }
        url = QUrl(f"{url_base}?{urlencode(marges)}")
        page.renderProcessTerminated.connect(lambda *_: tomber("le moteur de la page s'est arrêté"))

        def charge(ok: bool):
            if ok:
                if principal and not etat["pret"]:
                    etat["pret"] = True
                    #  xfdesktop ne part qu'une fois la VRAIE page affichée
                    #  sur l'écran principal — pas au démarrage à l'aveugle.
                    if signal_pret:
                        signal_pret()
                return
            etat["echecs"] += 1
            if etat["echecs"] >= 3:
                tomber("la page du bureau ne se charge pas")
            else:
                QTimer.singleShot(1500, lambda: vue.load(url))
        vue.loadFinished.connect(charge)
        vue.load(url)
        vue.show()

        def type_bureau():
            try:
                fen = vue.windowHandle()
            except RuntimeError:        # vue déjà remplacée (écrans refaits)
                return
            if fen is None:
                return
            fen.setProperty("_q_xcb_wm_window_type", XCB_TYPE_BUREAU)
            #  Qt ne fait RIEN si les drapeaux ne changent pas — et c'est
            #  setFlags() qui fait relire la propriété. Vu en vraie session
            #  XFCE : la fenêtre restait NORMALE, avec une barre de titre.
            #  On retire donc un drapeau puis on le remet : deux vrais
            #  changements, la propriété est relue au second.
            b = fen.flags()
            fen.setFlags(b & ~Qt.WindowStaysOnBottomHint)
            fen.setFlags(b | Qt.WindowStaysOnBottomHint)
            #  ET ON LA RÉAFFICHE. xfwm4 décide du cadre au moment où la
            #  fenêtre apparaît : changer le type après coup la range bien
            #  dans le calque du bureau, mais lui LAISSE sa barre de titre
            #  (vu en vraie session). Cachée puis remontrée, elle réapparaît
            #  avec le type bureau dès le départ — sans cadre.
            vue.hide()
            vue.setGeometry(g)
            vue.show()
            vue.lower()
        #  Après le premier affichage ET le chargement de la surface de la
        #  page (Qt peut recréer la fenêtre native à ce moment-là) : 800 ms.
        QTimer.singleShot(800, type_bureau)
        vues.append(vue)

    #  ═══ LES ÉCRANS QUI CHANGENT ═══
    #  Brancher, débrancher, changer de résolution ou d'écran principal
    #  (xfsettingsd rejoue le profil d'écrans APRÈS l'ouverture de session) :
    #  on refait TOUTES les vues, d'un coup. Ajouter une vue à côté des
    #  anciennes aurait remis deux fenêtres de bureau sur un même écran —
    #  la panne que tout ce module évite. Une seconde d'attente regroupe la
    #  rafale de signaux qu'un seul branchement provoque.
    reconstruire = QTimer()
    reconstruire.setSingleShot(True)
    reconstruire.setInterval(1000)

    suivis: set = set()

    def tout_poser():
        for v in vues:
            v.hide()
            v.deleteLater()
        vues.clear()
        principal = app.primaryScreen()
        for ecran in app.screens():
            poser(ecran, ecran is principal)
            if id(ecran) not in suivis:         # brancher les signaux UNE fois
                suivis.add(id(ecran))
                ecran.geometryChanged.connect(lambda *_: reconstruire.start())
                ecran.availableGeometryChanged.connect(lambda *_: reconstruire.start())
    reconstruire.timeout.connect(tout_poser)
    app.screenAdded.connect(lambda *_: reconstruire.start())
    app.screenRemoved.connect(lambda *_: reconstruire.start())
    app.primaryScreenChanged.connect(lambda *_: reconstruire.start())
    tout_poser()

    if fin is not None:
        guet = QTimer()
        #  app.exit(0), PAS app.quit() : sous Qt 6, quit() demande d'abord à
        #  chaque fenêtre de se fermer — et le bureau refuse (Alt+F4, plus
        #  haut). Le retour au classique restait alors sans effet (vu en
        #  vraie session), et chaque essai ouvrait « Fermer la session ».
        guet.timeout.connect(lambda: fin.is_set() and app.exit(0))
        guet.start(400)
    return app.exec()
