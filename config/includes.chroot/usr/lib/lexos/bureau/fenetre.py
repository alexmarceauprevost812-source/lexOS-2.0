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
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName("LexOS Bureau")
    app.setQuitOnLastWindowClosed(False)
    vues = []

    def poser(ecran, principal: bool):
        g, d = ecran.geometry(), ecran.availableGeometry()
        vue = QWebEngineView()
        vue.setWindowTitle("LexOS Bureau")
        vue.page().setBackgroundColor(QColor("#070707"))
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
        }
        vue.load(QUrl(f"{url_base}?{urlencode(marges)}"))
        vue.show()

        def type_bureau():
            fen = vue.windowHandle()
            if fen is None:
                return
            fen.setProperty("_q_xcb_wm_window_type", XCB_TYPE_BUREAU)
            #  Qt ne fait RIEN si les drapeaux ne changent pas — et c'est
            #  setFlags() qui fait relire la propriété. Vu en vraie session
            #  XFCE : la fenêtre restait NORMALE, avec une barre de titre.
            #  On retire donc un drapeau puis on le remet : deux vrais
            #  changements, la propriété est relue au second.
            base = fen.flags()
            fen.setFlags(base & ~Qt.WindowStaysOnBottomHint)
            fen.setFlags(base | Qt.WindowStaysOnBottomHint)
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
        #  Le bureau classique est encore derrière pendant ce temps — il ne
        #  part que deux secondes après (serveur.py, pret()).
        QTimer.singleShot(800, type_bureau)
        vues.append(vue)

    principal = app.primaryScreen()
    for ecran in app.screens():
        poser(ecran, ecran is principal)

    def ecran_ajoute(ecran):
        poser(ecran, False)
    app.screenAdded.connect(ecran_ajoute)

    if signal_pret:
        signal_pret()
    if fin is not None:
        guet = QTimer()
        guet.timeout.connect(lambda: fin.is_set() and app.quit())
        guet.start(400)
    return app.exec()
