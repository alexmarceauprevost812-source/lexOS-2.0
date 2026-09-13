"""La fenêtre Qt des pages LexOS — écrite UNE fois.

═══ POURQUOI CE MODULE EXISTE ═══
Compté : six fichiers montaient leur propre QApplication, leur propre
QWebEngineView, leur propre géométrie et leur propre fermeture —
settings.py, volet.py, partage.py, ia-locale.py, cartes.py, terminal-pro.py.
Les mêmes gestes, et les mêmes pièges à retomber dedans un par un.

⚠ FUSION, PAS RÉÉCRITURE. Chaque particularité reste celle de son appelant :
le volet garde son fond transparent et son titre contractuel, les
Paramètres gardent leur taille calculée sur l'écran, partage garde ses
620 x 660. Ce module ne DÉCIDE de rien — il tient les gestes communs à un
seul endroit pour qu'un correctif profite aux six au lieu d'un.
"""

from __future__ import annotations

from pathlib import Path


def application(nom: str):
    """La QApplication, nommée. L'import de PySide6 se fait ICI et pas en
    tête de fichier : une fenêtre qui ne s'ouvre pas ne doit pas empêcher la
    ligne de commande du même module de fonctionner."""
    import sys
    from PySide6.QtWidgets import QApplication
    app = QApplication(sys.argv)
    app.setApplicationName(nom)
    return app


def taille_ecran(app, large=(900, 1180, 0.92), haut=(600, 900, 0.94)):
    """Ce que le bureau laisse, borné. Rend (largeur, hauteur, x, y) centré.

    ═══ DÉPLACÉ DE settings.py, COMMENTAIRE COMPRIS ═══
    La fenêtre s'ouvrait à 980 x 700, quel que soit l'écran. Sur le ThinkPad
    (1366 x 768), 700 pixels de haut coupaient la barre latérale au milieu :
    Alex voyait la liste s'arrêter à « Partage » et pensait qu'il manquait
    des sections. Les sections étaient bien là et la barre défilait — mais
    une fenêtre qui n'utilise pas l'écran donne l'impression contraire.

    Ubuntu ouvre ses Paramètres à la taille de l'écran disponible. On fait
    pareil : ce que le bureau laisse (barre du haut et dock déduits, c'est
    ce que rend availableGeometry), sans jamais dépasser une largeur
    confortable en lecture ni descendre sous une taille utilisable.

    Et on CENTRE : sur un petit écran, une fenêtre presque aussi grande que
    le bureau posée en haut à gauche déborde à droite et en bas."""
    ecran = app.primaryScreen()
    if ecran is None:
        return None
    d = ecran.availableGeometry()
    l = max(large[0], min(large[1], int(d.width() * large[2])))
    h = max(haut[0], min(haut[1], int(d.height() * haut[2])))
    return l, h, d.x() + (d.width() - l) // 2, d.y() + (d.height() - h) // 2


def fenetre_cadree(app, titre: str, icone: str | None = None):
    """Une fenêtre ordinaire, avec cadre, barre de titre et icône.

    Rend (fenetre, vue). L'icône n'est posée que si le fichier existe : une
    QIcon sur un chemin absent donne une fenêtre sans icône ET aucun message,
    ce qui se cherche longtemps."""
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView
    fenetre = QMainWindow()
    fenetre.setWindowTitle(titre)
    if icone and Path(icone).exists():
        fenetre.setWindowIcon(QIcon(icone))
    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)
    return fenetre, vue


def vue_transparente(titre: str):
    """Une vue web sans cadre, sur fond transparent, hors de la liste des
    fenêtres. C'est la forme d'un VOLET, et les quatre gestes vont ensemble.

    ═══ DÉPLACÉ DE volet.py, ET LE TITRE EST UN CONTRAT ═══
    SANS LE FOND TRANSPARENT, RIEN NE MARCHE : la page dessine un volet aux
    coins ronds sur du vide ; si la vue peint un fond blanc derrière, on
    obtient un rectangle blanc avec un volet arrondi dedans — le contraire
    de ce qu'on veut.

    Qt.Tool : pas d'entrée dans Alt+Tab ni dans la liste des fenêtres. C'est
    ce qui fait la différence entre un volet et une fenêtre.

    ⚠ LE TITRE EST UN CONTRAT AVEC PICOM — il choisit son animation par la
    PREMIÈRE règle qui correspond (manuel, section RULES), et sans règle à
    lui ce volet tombe dans la règle générique « window_type = 'utility' »
    (car Qt.Tool devient _NET_WM_WINDOW_TYPE_UTILITY) : il recevrait le fondu
    court des menus au lieu de l'extinction « vieille télé ». On POSE donc le
    titre explicitement au lieu de compter sur celui que Qt déduirait du nom
    d'application : une règle picom accrochée à une valeur PAR DÉFAUT est une
    règle qui se décroche en silence à la prochaine version de Qt."""
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QColor
    from PySide6.QtWebEngineWidgets import QWebEngineView
    vue = QWebEngineView()
    vue.setWindowTitle(titre)
    vue.setAttribute(Qt.WA_TranslucentBackground, True)
    vue.page().setBackgroundColor(QColor(Qt.transparent))
    vue.setWindowFlags(Qt.FramelessWindowHint | Qt.Tool
                       | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint)
    vue.setAttribute(Qt.WA_DeleteOnClose, True)
    return vue


def ferme_au_flou(app, vue, retard_ms: int = 700, pas_ms: int = 250):
    """Un clic ailleurs referme — c'est ce qui fait d'un volet un volet.

    ═══ DÉPLACÉ DE volet.py ═══
    Le retard n'est pas un réglage de confort : au moment où la fenêtre
    apparaît, elle n'a pas encore le focus, et fermer sur « pas de focus » la
    tuerait AVANT qu'elle s'affiche. On n'arme la surveillance qu'une fois
    posée."""
    from PySide6.QtCore import QTimer

    def surveille():
        def verifie():
            if not vue.isActiveWindow():
                app.quit()
        minuteur = QTimer(vue)
        minuteur.timeout.connect(verifie)
        minuteur.start(pas_ms)

    QTimer.singleShot(retard_ms, surveille)
