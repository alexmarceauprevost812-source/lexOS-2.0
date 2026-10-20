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
import signal
import subprocess
import sys
import time
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
    from PySide6.QtGui import QColor, QSurfaceFormat
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

    #  ═══ PAS D'ATTENTE DE SYNCHRO VERTICALE ═══
    #  Mesuré sous Xvfb + xfwm4 (py-spy) : le fil principal restait BLOQUÉ
    #  pour de bon dans glXSwapBuffers (QRhi::endFrame) après qu'on eut
    #  montré puis caché la fenêtre du labo — bureau figé, et lexos-bureau
    #  ne voyait rien tomber. Avec l'attente de la synchro (« swap interval
    #  1 »), GLX attend une image qu'une fenêtre cachée ne montrera jamais
    #  (le même piège est connu chez NVIDIA). Chromium cadence lui-même ses
    #  images : Qt n'a pas à attendre l'écran.
    fmt = QSurfaceFormat.defaultFormat()
    fmt.setSwapInterval(0)
    QSurfaceFormat.setDefaultFormat(fmt)
    app = QApplication(sys.argv)
    app.setApplicationName("LexOS Bureau")
    app.setQuitOnLastWindowClosed(False)
    vues: list = []
    etat = {"pret": False, "echecs": 0}
    labo = Labo(app, url_base, jeton, base)
    surveiller_le_fil(labo)

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
        #  Le bouton 🧪 de la page change son titre en « labo-… » : c'est le
        #  seul signe qu'elle peut faire à la fenêtre du labo.
        vue.titleChanged.connect(lambda t: t.startswith("labo-") and labo.basculer())
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


#  ═══ LE CHIEN DE GARDE ═══
#  Si le fil de Qt reste figé (pilote graphique bloqué, voir plus haut « PAS
#  D'ATTENTE DE SYNCHRO »), le bureau est mort mais le processus vit :
#  lexos-bureau ne voit rien tomber et l'écran reste figé jusqu'à la fin de
#  la session. Le tic du labo bat huit fois par seconde ; s'il ne bat plus
#  depuis 30 s, on sort en erreur — lexos-bureau remet xfdesktop tout de
#  suite, puis relance le bureau.
GARDE_S = 30


def surveiller_le_fil(labo) -> None:
    import threading

    def garde():
        while True:
            time.sleep(5)
            if time.monotonic() - labo.battement > GARDE_S:
                print(f"[lexos-bureau] le fil de Qt ne répond plus depuis {GARDE_S} s — on rend la main",
                      file=sys.stderr, flush=True)
                os._exit(3)
    threading.Thread(target=garde, daemon=True).start()


#  ═══ 🧪 LE LABO — le panneau qui monte du bas de l'écran ═══
#  ALEX : « on mettra la souris complètement en bas de l'écran, puis ça
#  ouvrira un menu […] fluidement, qui monte vers les airs […] ce sera mon
#  petit laboratoire de mes IA ».
#
#  COMMENT ON SAIT QUE LA SOURIS EST EN BAS : on demande sa position à X
#  (XQueryPointer par python3-xlib, quelques microsecondes) huit fois par
#  seconde. PAS QCursor.pos() : dans ce processus, il rendait TOUJOURS la
#  position du démarrage (mesuré sous Xvfb + xfwm4 : 31 lectures de suite à
#  « 100, 300 » pendant que xdotool promenait la souris partout). PAS de bande invisible posée au bas de l'écran : elle volerait
#  les clics de la dernière rangée de pixels de chaque appli (barre de
#  défilement, barre d'état), et passerait par-dessus une vidéo en plein
#  écran. Ici, rien n'est posé tant que le labo n'est pas ouvert.
#
#  LA FENÊTRE : « Qt.ToolTip » = override-redirect sous X — au-dessus des
#  applis, hors de la barre des tâches et d'Alt+Tab, sans cadre, et xfwm4 ne
#  la déplace pas. Transparente (le compositeur de xfwm4 est actif dans
#  LexOS) : seul le panneau arrondi se voit. Elle ne prend pas le clavier,
#  et n'en a pas besoin : tout se fait à la souris.
#
#  ELLE NE SE ROUVRE PAS EN BOUCLE : fermée, elle attend que la souris ait
#  QUITTÉ le bas de l'écran avant de pouvoir remonter — sinon, lancer une
#  appli avec la souris restée en bas la faisait remonter une seconde après.
class Labo:
    TIC_MS = 120
    SORTIE_MS = 650          # souris hors du panneau aussi longtemps → il redescend

    def __init__(self, app, url_base: str, jeton: str, base) -> None:
        from PySide6.QtCore import QTimer, QUrl
        from PySide6.QtGui import QColor
        from PySide6.QtCore import Qt
        from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineSettings
        from PySide6.QtWebEngineWidgets import QWebEngineView
        import reglages
        self.app, self.rg = app, reglages
        self.ouvert = False
        self.bas_depuis: float | None = None
        self.dehors_depuis: float | None = None
        self.attendre_sortie = True        # au démarrage aussi : la souris peut déjà être en bas
        self.demande = False
        self.regl = {"labo": True, "labo_delai": 1000}
        self.empreinte = None
        self.vu_regl = 0.0
        self.x11 = None
        self.battement = time.monotonic()
        self.hauteur: int | None = None
        self.entre = False
        self.ouvert_a = 0.0

        class PageLabo(QWebEnginePage):
            def acceptNavigationRequest(self, url, genre, principal):  # noqa: N802
                if not principal:
                    return True
                return (url.host() == base.host() and url.port() == base.port()
                        and url.path() == "/labo.html")

        vue = QWebEngineView()
        page = PageLabo(vue)
        vue.setPage(page)
        r = page.settings()
        r.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, False)
        try:
            r.setAttribute(QWebEngineSettings.WebAttribute.NavigateOnDropEnabled, False)
        except AttributeError:
            pass
        vue.setAcceptDrops(False)
        vue.setWindowTitle("LexOS Labo")
        vue.setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        vue.setAttribute(Qt.WA_TranslucentBackground)
        vue.setAttribute(Qt.WA_ShowWithoutActivating)
        page.setBackgroundColor(QColor(0, 0, 0, 0))
        vue.titleChanged.connect(self.titre)
        vue.load(QUrl(f"{url_base}labo.html?t={jeton}"))
        self.vue = vue

        #  « lexos-bureau labo » envoie SIGUSR1 : ouvrir / fermer (pour un
        #  raccourci clavier). Python ne traite le signal qu'entre deux
        #  instructions Python — le tic ci-dessous lui en donne l'occasion.
        try:
            signal.signal(signal.SIGUSR1, lambda *_: setattr(self, "demande", True))
        except ValueError:      # pas dans le fil principal (bancs)
            pass
        self.tic_minuteur = QTimer(self.vue)
        self.tic_minuteur.timeout.connect(self.tic)
        self.tic_minuteur.start(self.TIC_MS)

    # ── où le panneau se pose ──
    def rect(self, hauteur: int | None = None):
        """Centré, collé au bas de l'écran principal. La hauteur est celle
        que la page a demandée (« taille-… »), bornée : jamais plus que
        62 % de l'écran ni 640 px, jamais moins de 240 px."""
        from PySide6.QtCore import QRect
        g = self.app.primaryScreen().geometry()
        l = min(1180, int(g.width() * 0.86))
        maxi = min(640, max(300, int(g.height() * 0.62)))
        h = max(240, min(maxi, hauteur or self.hauteur or maxi))
        return QRect(g.x() + (g.width() - l) // 2, g.y() + g.height() - h, l, h)

    def titre(self, t: str) -> None:
        if t.startswith("fermer-"):
            self.cacher()
        elif t.startswith("taille-"):
            try:
                self.hauteur = int(t.split("-")[1])
            except (IndexError, ValueError):
                return
            if self.ouvert and not t.endswith("-plus-tard"):
                self.vue.setGeometry(self.rect())

    def lire_reglages(self) -> None:
        maintenant = time.monotonic()
        if maintenant - self.vu_regl < 2:
            return
        self.vu_regl = maintenant
        try:
            e = self.rg.empreinte()
            if e != self.empreinte:
                self.empreinte = e
                r = self.rg.lire()
                self.regl = {"labo": r["labo"], "labo_delai": r["labo_delai"]}
        except Exception:       # un réglage illisible ne fait pas tomber le bureau
            pass

    def _x(self):
        if self.x11 is None:
            from Xlib import display
            self.x11 = display.Display()
        return self.x11

    def pointeur(self):
        """La souris, en pixels Qt (logiques). None si X ne répond pas."""
        from PySide6.QtCore import QPoint
        try:
            p = self._x().screen().root.query_pointer()
        except Exception:
            self.x11 = None
            return None
        r = self.app.primaryScreen().devicePixelRatio() or 1
        return QPoint(round(p.root_x / r), round(p.root_y / r))

    def plein_ecran(self) -> bool:
        """Une appli en plein écran (jeu, vidéo) : le bas de l'écran est à
        elle — on n'y fait pas monter le labo."""
        try:
            from Xlib import X
            d = self._x()
            racine = d.screen().root
            a = racine.get_full_property(d.intern_atom("_NET_ACTIVE_WINDOW"), X.AnyPropertyType)
            if a is None or not len(a.value) or not a.value[0]:
                return False
            w = d.create_resource_object("window", int(a.value[0]))
            st = w.get_full_property(d.intern_atom("_NET_WM_STATE"), X.AnyPropertyType)
            return st is not None and d.intern_atom("_NET_WM_STATE_FULLSCREEN") in list(st.value)
        except Exception:
            self.x11 = None
            return False

    # ── ouvrir, fermer ──
    def ouvrir(self) -> None:
        if self.ouvert:
            return
        self.vue.setGeometry(self.rect())
        self.vue.show()
        self.vue.raise_()
        self.ouvert = True
        self.ouvert_a = time.monotonic()
        self.entre = False
        self.dehors_depuis = None
        self.vue.page().runJavaScript("window.labo && labo.ouvrir()")

    def fermer(self) -> None:
        from PySide6.QtCore import QTimer
        if not self.ouvert:
            return
        self.vue.page().runJavaScript("window.labo && labo.fermer()")
        QTimer.singleShot(700, self.cacher)     # filet : si la page ne répond pas

    def cacher(self) -> None:
        if self.ouvert:
            self.vue.hide()
            self.ouvert = False
            self.bas_depuis = None
            self.attendre_sortie = True

    def basculer(self) -> None:
        if self.ouvert:
            self.fermer()
        else:
            self.attendre_sortie = False
            self.ouvrir()

    def tic(self) -> None:
        self.battement = time.monotonic()
        if self.demande:
            self.demande = False
            self.basculer()
        self.lire_reglages()
        pos = self.pointeur()
        if pos is None:
            return
        maintenant = time.monotonic()
        if self.ouvert:
            #  Un peu de marge au-dessus du panneau : on ne le ferme pas
            #  pour une souris qui le frôle en remontant.
            #  Ouvert par « lexos-bureau labo » (un raccourci clavier), la
            #  souris peut être n'importe où : on attend qu'elle soit VENUE
            #  dans le panneau avant de le refermer quand elle part — sinon
            #  il redescendait aussitôt monté. Jamais venue en 8 s : il redescend.
            if self.vue.geometry().adjusted(-8, -40, 8, 8).contains(pos):
                self.entre = True
                self.dehors_depuis = None
            elif not self.entre:
                if maintenant - self.ouvert_a > 8:
                    self.fermer()
            elif self.dehors_depuis is None:
                self.dehors_depuis = maintenant
            elif (maintenant - self.dehors_depuis) * 1000 >= self.SORTIE_MS:
                self.dehors_depuis = None
                self.fermer()
            return
        if not self.regl["labo"]:
            return
        r = self.rect()
        au_bord = pos.y() >= r.bottom() - 1 and r.left() <= pos.x() <= r.right()
        if not au_bord:
            self.bas_depuis = None
            self.attendre_sortie = False
            return
        if self.attendre_sortie:
            return
        if self.bas_depuis is None:
            self.bas_depuis = maintenant
        elif (maintenant - self.bas_depuis) * 1000 >= self.regl["labo_delai"]:
            self.bas_depuis = None
            if self.plein_ecran():
                self.attendre_sortie = True
            else:
                self.ouvrir()
