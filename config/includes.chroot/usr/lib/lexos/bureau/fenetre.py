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
    outils = Outils(app, url_base, jeton, base)
    surveiller_le_fil([labo, outils])

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
        #  La vidéo d'ouverture du bureau démon (muette) doit partir seule :
        #  personne n'a encore cliqué quand la session s'ouvre.
        try:
            reglages.setAttribute(QWebEngineSettings.WebAttribute.PlaybackRequiresUserGesture, False)
        except AttributeError:
            pass
        vue.setAcceptDrops(False)
        vue.setWindowTitle("LexOS Bureau")
        page.setBackgroundColor(QColor("#070707"))
        #  Le bouton 🧪 de la page change son titre en « labo-… » : c'est le
        #  seul signe qu'elle peut faire à la fenêtre du labo.
        vue.titleChanged.connect(lambda t: t.startswith("labo-") and labo.basculer())
        vue.titleChanged.connect(lambda t: t.startswith("outils-") and outils.basculer())
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
            #  Rendu au processeur (LEXOS_BUREAU_SANS_GPU, plus haut) : la page
            #  allège ses effets — le bureau démon coupe ses braises et son
            #  halo qui pulse, ce qu'un VirtualBox sans 3D paie le plus cher.
            "leger": "1" if os.environ.get("LEXOS_BUREAU_SANS_GPU") == "1" else "0",
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


def surveiller_le_fil(tiroirs: list) -> None:
    import threading

    def garde():
        while True:
            time.sleep(5)
            if time.monotonic() - max(t.battement for t in tiroirs) > GARDE_S:
                print(f"[lexos-bureau] le fil de Qt ne répond plus depuis {GARDE_S} s — on rend la main",
                      file=sys.stderr, flush=True)
                os._exit(3)
    threading.Thread(target=garde, daemon=True).start()


#  ═══ LA SOURIS, LUE À X ═══
#  XQueryPointer par python3-xlib, quelques microsecondes. PAS QCursor.pos() :
#  dans ce processus, il rendait TOUJOURS la position du démarrage (mesuré
#  sous Xvfb + xfwm4 : 31 lectures de suite à « 100, 300 » pendant que xdotool
#  promenait la souris partout). Une seule connexion X et une seule lecture
#  par tic pour les deux tiroirs (le labo en bas, les outils en haut).
_X: dict = {"d": None, "pos": None, "quand": 0.0}


def _x():
    if _X["d"] is None:
        from Xlib import display
        _X["d"] = display.Display()
    return _X["d"]


def pointeur(app):
    """La souris, en pixels Qt (logiques). None si X ne répond pas."""
    from PySide6.QtCore import QPoint
    maintenant = time.monotonic()
    if _X["pos"] is not None and maintenant - _X["quand"] < 0.05:
        return _X["pos"]
    try:
        p = _x().screen().root.query_pointer()
    except Exception:
        _X["d"] = None
        return None
    r = app.primaryScreen().devicePixelRatio() or 1
    _X["pos"], _X["quand"] = QPoint(round(p.root_x / r), round(p.root_y / r)), maintenant
    return _X["pos"]


def plein_ecran() -> bool:
    """Une appli en plein écran (jeu, vidéo) : les bords de l'écran sont à
    elle — on n'y fait monter ni descendre aucun tiroir."""
    try:
        from Xlib import X
        d = _x()
        racine = d.screen().root
        a = racine.get_full_property(d.intern_atom("_NET_ACTIVE_WINDOW"), X.AnyPropertyType)
        if a is None or not len(a.value) or not a.value[0]:
            return False
        w = d.create_resource_object("window", int(a.value[0]))
        st = w.get_full_property(d.intern_atom("_NET_WM_STATE"), X.AnyPropertyType)
        return st is not None and d.intern_atom("_NET_WM_STATE_FULLSCREEN") in list(st.value)
    except Exception:
        _X["d"] = None
        return False


def haut_utile(g) -> int:
    """Où commence l'écran SOUS la barre du haut : _NET_WORKAREA, que Qt ne
    relit pas (serveur.py, ZoneTravail). La barre des outils descend de là."""
    try:
        d = _x()
        p = d.screen().root.get_full_property(d.intern_atom("_NET_WORKAREA"), 0)
        y = int(p.value[1]) if p is not None and len(p.value) >= 4 else g.y()
    except Exception:
        _X["d"] = None
        y = g.y()
    return y if g.y() <= y < g.y() + g.height() // 3 else g.y()


#  ═══ LES TIROIRS : 🧪 le labo (en bas) et 🎛️ les outils (en haut) ═══
#  ALEX : « on mettra la souris complètement en bas de l'écran, puis ça
#  ouvrira un menu […] fluidement, qui monte vers les airs » — puis, pour le
#  haut : « un petit menu vraiment petit […] c'est la largeur de l'écran ».
#
#  PAS de bande invisible posée au bord de l'écran : elle volerait les clics
#  de la dernière rangée de pixels de chaque appli, et passerait par-dessus
#  une vidéo en plein écran. Ici, rien n'est posé tant qu'un tiroir n'est pas
#  ouvert : on regarde seulement où est la souris, huit fois par seconde.
#
#  LA FENÊTRE : « Qt.ToolTip » = override-redirect sous X — au-dessus des
#  applis, hors de la barre des tâches et d'Alt+Tab, sans cadre, et xfwm4 ne
#  la déplace pas. Transparente (le compositeur de xfwm4 est actif dans
#  LexOS) : seul le panneau se voit.
#
#  UN TIROIR NE SE ROUVRE PAS EN BOUCLE : fermé, il attend que la souris ait
#  QUITTÉ son bord avant de pouvoir revenir — sinon, lancer une appli avec la
#  souris restée au bord le faisait revenir une seconde après.
class Tiroir:
    TIC_MS = 120
    SORTIE_MS = 650          # souris hors du panneau aussi longtemps → il s'en va
    NOM = "labo"             # le réglage (« labo » : oui/non) et l'objet JS de la page
    PAGE = "labo.html"
    TITRE = "LexOS Labo"
    SIGNAL = signal.SIGUSR1
    DELAI = "labo_delai"     # le réglage qui dit combien de temps rester au bord (ms)

    def __init__(self, app, url_base: str, jeton: str, base) -> None:
        from PySide6.QtCore import QTimer, QUrl
        from PySide6.QtGui import QColor
        from PySide6.QtCore import Qt
        from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineSettings
        from PySide6.QtWebEngineWidgets import QWebEngineView
        import reglages
        self.app, self.rg = app, reglages
        self.ouvert = False
        self.bord_depuis: float | None = None
        self.dehors_depuis: float | None = None
        self.attendre_sortie = True        # au démarrage aussi : la souris peut déjà être au bord
        self.demande = False
        self.regl = {self.NOM: True, "delai": 1000}
        self.empreinte = None
        self.vu_regl = 0.0
        self.battement = time.monotonic()
        self.hauteur: int | None = None
        self.entre = False
        self.ouvert_a = 0.0
        page_ok = "/" + self.PAGE

        class PageTiroir(QWebEnginePage):
            def acceptNavigationRequest(self, url, genre, principal):  # noqa: N802
                if not principal:
                    return True
                return (url.host() == base.host() and url.port() == base.port()
                        and url.path() == page_ok)

        vue = QWebEngineView()
        page = PageTiroir(vue)
        vue.setPage(page)
        r = page.settings()
        r.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, False)
        try:
            r.setAttribute(QWebEngineSettings.WebAttribute.NavigateOnDropEnabled, False)
        except AttributeError:
            pass
        vue.setAcceptDrops(False)
        vue.setWindowTitle(self.TITRE)
        vue.setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        vue.setAttribute(Qt.WA_TranslucentBackground)
        vue.setAttribute(Qt.WA_ShowWithoutActivating)
        page.setBackgroundColor(QColor(0, 0, 0, 0))
        vue.titleChanged.connect(self.titre)
        vue.load(QUrl(f"{url_base}{self.PAGE}?t={jeton}"))
        self.vue = vue

        #  « lexos-bureau labo | outils » envoie SIGUSR1 | SIGUSR2 : ouvrir /
        #  fermer (pour un raccourci clavier). Python ne traite le signal
        #  qu'entre deux instructions Python — le tic lui en donne l'occasion.
        try:
            signal.signal(self.SIGNAL, lambda *_: setattr(self, "demande", True))
        except ValueError:      # pas dans le fil principal (bancs)
            pass
        self.tic_minuteur = QTimer(self.vue)
        self.tic_minuteur.timeout.connect(self.tic)
        self.tic_minuteur.start(self.TIC_MS)

    # ── à redéfinir par chaque tiroir ──
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

    def au_bord(self, pos) -> bool:
        r = self.rect()
        return pos.y() >= r.bottom() - 1 and r.left() <= pos.x() <= r.right()

    def zone_dedans(self):
        """Où la souris compte comme « dans le tiroir ». Un peu de marge
        au-dessus : on ne le ferme pas pour une souris qui le frôle."""
        return self.vue.geometry().adjusted(-8, -40, 8, 8)

    def titre_autre(self, t: str) -> None:
        pass

    # ── commun ──
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
        else:
            self.titre_autre(t)

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
                self.regl = {self.NOM: r[self.NOM], "delai": r[self.DELAI]}
        except Exception:       # un réglage illisible ne fait pas tomber le bureau
            pass

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
        self.vue.page().runJavaScript(f"window.{self.NOM} && {self.NOM}.ouvrir()")

    def fermer(self) -> None:
        from PySide6.QtCore import QTimer
        if not self.ouvert:
            return
        self.vue.page().runJavaScript(f"window.{self.NOM} && {self.NOM}.fermer()")
        QTimer.singleShot(700, self.cacher)     # filet : si la page ne répond pas

    def cacher(self) -> None:
        if self.ouvert:
            self.vue.hide()
            self.ouvert = False
            self.bord_depuis = None
            self.attendre_sortie = True

    def basculer(self) -> None:
        if self.ouvert:
            self.fermer()
        else:
            self.attendre_sortie = False
            self.ouvrir()

    def occupe(self) -> bool:
        """Vrai quand le tiroir ne doit ni se fermer ni s'ouvrir tout seul."""
        return False

    def tic(self) -> None:
        self.battement = time.monotonic()
        if self.demande:
            self.demande = False
            self.basculer()
        self.lire_reglages()
        if self.occupe():
            return
        pos = pointeur(self.app)
        if pos is None:
            return
        maintenant = time.monotonic()
        if self.ouvert:
            #  Ouvert par un raccourci clavier, la souris peut être n'importe
            #  où : on attend qu'elle soit VENUE dans le tiroir avant de le
            #  fermer quand elle part. Jamais venue en 8 s : il s'en va.
            if self.zone_dedans().contains(pos):
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
        if not self.regl[self.NOM]:
            return
        if not self.au_bord(pos):
            self.bord_depuis = None
            self.attendre_sortie = False
            return
        if self.attendre_sortie:
            return
        if self.bord_depuis is None:
            self.bord_depuis = maintenant
        elif (maintenant - self.bord_depuis) * 1000 >= self.regl["delai"]:
            self.bord_depuis = None
            if plein_ecran():
                self.attendre_sortie = True
            else:
                self.ouvrir()


class Labo(Tiroir):
    """🧪 Mon labo — le panneau qui monte du BAS de l'écran."""


#  ═══ 🎛️ MES OUTILS — la barre mince qui descend du HAUT de l'écran ═══
#  Elle descend SOUS la barre du haut (choix d'Alex : « la garder, menu en
#  dessous »), sur toute la largeur. Le bord qui l'ouvre est le haut de
#  l'écran SANS ses coins : le coin haut-gauche ouvre déjà la vue d'ensemble
#  (coin-actif), et viser un coin ne doit pas ouvrir deux choses.
class Outils(Tiroir):
    NOM = "outils"
    PAGE = "outils.html"
    TITRE = "LexOS Outils"
    SIGNAL = signal.SIGUSR2
    COIN = 80
    #  0,3 s au bord du haut, puis la barre descend (réglage « outils_delai »).
    #  Le tic passe à 50 ms ici : à 120 ms, 0,3 s devenait 0,36 à 0,48 s.
    #  Lire la position de la souris ne coûte presque rien.
    DELAI = "outils_delai"
    TIC_MS = 50

    #  ═══ FIXÉE EN HAUT (réglage « outils_fixe », d'office sur la nomade) ═══
    #  ALEX : « l'outil en haut de l'écran visible et fixe en haut ». La barre
    #  est montrée dès que le bureau démarre et n'est plus jamais cachée par
    #  la souris ; « fermer » (Échap, une appli lancée) referme seulement les
    #  menus. Pour que les fenêtres maximisées s'arrêtent SOUS elle, on pose
    #  la marge du haut de xfwm4 (/general/margin_top) : une fenêtre
    #  override-redirect comme celle-ci ne peut pas réserver de place
    #  elle-même (le gestionnaire de fenêtres ignore ses « struts »).
    MARGE = 80          # la barre : 10 px d'air + 62 px de barre + la lueur

    def __init__(self, *a, **k) -> None:
        super().__init__(*a, **k)
        self.en_arret = False
        self.fixe = False
        self.marge_posee = 0
        self.regl["outils_fixe"] = False
        self.vue.loadFinished.connect(self._page_prete)

    def lire_reglages(self) -> None:
        avant = self.regl.get("outils_fixe", False)
        empreinte = self.empreinte
        super().lire_reglages()
        if self.empreinte != empreinte:
            try:
                self.regl["outils_fixe"] = bool(self.rg.lire().get("outils_fixe", False))
            except Exception:
                self.regl["outils_fixe"] = avant

    def _page_prete(self, ok: bool) -> None:
        #  La page a pu finir de charger APRÈS le premier « ouvrir » : sans
        #  ce rappel, la barre fixée resterait repliée hors de l'écran.
        if ok and self.fixe:
            self.vue.page().runJavaScript("window.outils && (outils.fixer(true), outils.ouvrir())")

    def _marge(self, px: int) -> None:
        """La marge du haut de xfwm4, en vrais pixels. On ne remet à zéro que
        la marge qu'on a posée soi-même."""
        if px == self.marge_posee or not shutil.which("xfconf-query"):
            return
        try:
            subprocess.run(["xfconf-query", "-c", "xfwm4", "-p", "/general/margin_top",
                            "--create", "-t", "int", "-s", str(px)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            self.marge_posee = px
        except (OSError, subprocess.SubprocessError):
            pass

    def _fixer(self, oui: bool) -> None:
        self.fixe = oui
        if oui:
            r = self.app.primaryScreen().devicePixelRatio() or 1
            self._marge(round(self.MARGE * r))
            self.vue.page().runJavaScript("window.outils && outils.fixer(true)")
            self.attendre_sortie = False
            self.ouvrir()
        else:
            self._marge(0)
            self.vue.page().runJavaScript("window.outils && outils.fixer(false)")
            self.cacher()

    def fermer(self) -> None:
        if self.fixe and not self.en_arret:
            #  Fixée : on referme les menus, la barre reste.
            self.vue.page().runJavaScript("window.outils && outils.fermer()")
            return
        super().fermer()

    def basculer(self) -> None:
        if self.fixe:
            if not self.ouvert:
                self.ouvrir()
            else:
                self.fermer()
            return
        super().basculer()

    def tic(self) -> None:
        self.lire_reglages()
        voulu = bool(self.regl.get("outils_fixe"))
        if voulu != self.fixe:
            self._fixer(voulu)
        if not self.fixe:
            super().tic()
            return
        self.battement = time.monotonic()
        if self.demande:
            self.demande = False
            self.basculer()
        #  Pendant l'arrêt façon télé, la fenêtre couvre tout l'écran : on
        #  n'y touche pas. Sinon, la barre est toujours là — même après
        #  « rendre l'écran » (un arrêt raté), qui l'avait cachée.
        #  Une vidéo ou un jeu en plein écran : la barre s'efface, et revient
        #  dès que le plein écran se termine.
        if self.en_arret:
            return
        plein = plein_ecran()
        if plein and self.ouvert:
            self.cacher()
        elif not plein and not self.ouvert:
            self.ouvrir()

    def rect(self, hauteur: int | None = None):
        """Toute la largeur, sous la barre du haut. Mince (la barre seule) ;
        plus haute quand un menu est ouvert (« taille-… » de la page)."""
        from PySide6.QtCore import QRect
        g = self.app.primaryScreen().geometry()
        haut = haut_utile(g)
        #  Notre propre marge xfwm4 peut entrer dans _NET_WORKAREA : la barre
        #  se poserait alors SOUS la place qu'elle s'est réservée. On la retire
        #  (sans jamais remonter au-dessus du haut de l'écran).
        if self.fixe and self.marge_posee:
            r = self.app.primaryScreen().devicePixelRatio() or 1
            sans = haut - round(self.marge_posee / r)
            if sans >= g.y():
                haut = sans
        place = g.y() + g.height() - haut
        h = max(80, min(place, hauteur or self.hauteur or 96))
        return QRect(g.x(), haut, g.width(), h)

    def au_bord(self, pos) -> bool:
        g = self.app.primaryScreen().geometry()
        return pos.y() <= g.y() + 1 and g.x() + self.COIN <= pos.x() <= g.right() - self.COIN

    def zone_dedans(self):
        #  La barre du haut, AU-DESSUS du tiroir, compte comme « dedans » :
        #  la souris descend du bord de l'écran jusqu'à lui en la traversant.
        g = self.vue.geometry()
        haut = self.app.primaryScreen().geometry().y()
        return g.adjusted(-8, haut - g.y(), 8, 8)

    def occupe(self) -> bool:
        return self.en_arret

    def titre(self, t: str) -> None:
        #  Pendant l'arrêt, la fenêtre couvre tout l'écran : une « taille »
        #  partie juste avant ne doit pas la rapetisser sous la télé.
        if self.en_arret and t.startswith(("taille-", "fermer-")):
            return
        super().titre(t)

    def titre_autre(self, t: str) -> None:
        if t.startswith("clavier-"):
            #  La recherche du ti démon : une fenêtre override-redirect ne
            #  reçoit pas le clavier toute seule, et activateWindow() de Qt
            #  ne fait rien pour elle (mesuré : xdotool tapait dans le vide).
            #  On donne le focus de X directement à sa fenêtre.
            self.vue.activateWindow()
            self.vue.setFocus()
            try:
                from Xlib import X
                d = _x()
                d.set_input_focus(int(self.vue.winId()), X.RevertToPointerRoot, X.CurrentTime)
                d.sync()
            except Exception:
                _X["d"] = None
        elif t.startswith("arret-pret-"):
            self.executer_arret(t.split("-")[2])
        elif t.startswith("arret-"):
            self.tele(t.split("-")[1])

    # ═══ L'ARRÊT FAÇON TÉLÉ ═══
    #  ALEX : « quand on arrête l'ordinateur, avec une fin d'animation d'une
    #  vieille télé des années 80 ». On photographie l'écran tel qu'il est
    #  (sans la barre des outils : on la cache d'abord), on couvre tout
    #  l'écran avec cette photo, et la page l'écrase en une ligne, puis en un
    #  point lumineux, puis noir. Alors seulement on éteint.
    def tele(self, geste: str) -> None:
        from PySide6.QtCore import QTimer
        if geste not in ("eteindre", "redemarrer") or self.en_arret:
            return
        self.en_arret = True
        self.vue.hide()
        QTimer.singleShot(220, lambda: self._tele_photo(geste))

    def _tele_photo(self, geste: str) -> None:
        import base64
        from PySide6.QtCore import QBuffer, QByteArray, QIODevice
        ecran = self.app.primaryScreen()
        donnees = ""
        try:
            photo = ecran.grabWindow(0)
            tampon = QByteArray()
            b = QBuffer(tampon)
            b.open(QIODevice.WriteOnly)
            photo.save(b, "JPG", 82)
            donnees = "data:image/jpeg;base64," + base64.b64encode(bytes(tampon)).decode("ascii")
        except Exception:       # pas de photo : la page éteint un écran noir, c'est tout
            donnees = ""
        self.vue.setGeometry(ecran.geometry())
        self.vue.show()
        self.vue.raise_()
        self.ouvert = True
        self.vue.page().runJavaScript(f"outils.tele({donnees!r}, {geste!r})")

    def executer_arret(self, geste: str) -> None:
        from PySide6.QtCore import QTimer
        if geste not in ("eteindre", "redemarrer"):
            return
        #  lexos-session, comme le bouton rouge : la session se ferme
        #  proprement (fichiers écrits), puis la machine s'éteint.
        if shutil.which("lexos-session"):
            subprocess.Popen(["lexos-session", geste], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        #  LE FILET. Alex : « pu capable arrêter mon ordinateur ». Si on est
        #  encore là dans 12 s, la fermeture de session n'a pas abouti : on
        #  demande l'arrêt directement à systemd. Et si dans 30 s on est
        #  TOUJOURS là, on rend l'écran — jamais un écran noir pour toujours.
        def plan_b():
            if shutil.which("systemctl"):
                subprocess.Popen(["systemctl", "poweroff" if geste == "eteindre" else "reboot"],
                                 start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def rendre_l_ecran():
            self.en_arret = False
            self.vue.page().runJavaScript("outils.teleRatee()")
            self.cacher()
            if shutil.which("notify-send"):
                subprocess.Popen(["notify-send", "-i", "dialog-warning", "LexOS",
                                  "L'ordinateur ne s'est pas éteint. Essaie « systemctl poweroff » dans un terminal."],
                                 start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        QTimer.singleShot(12000, plan_b)
        QTimer.singleShot(30000, rendre_l_ecran)
