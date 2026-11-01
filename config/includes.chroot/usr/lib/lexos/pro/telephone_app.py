"""Mon téléphone — fenêtre autonome (lancée par /usr/bin/lexos-telephone).

La page vit dans ui/pages/telephone.py et reprend le thème de LEXOS PRO ;
cette fenêtre ne fait que l'encadrer, comme « Lien avec le mobile » sous
Windows : une petite appli à part, pas un onglet caché dans une autre.
"""
from __future__ import annotations

import os
import sys

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import QApplication, QVBoxLayout, QWidget

from .services import prefs
from .ui import theme
from .ui.pages.telephone import PageTelephone


class FenetreTelephone(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Mon téléphone")
        self.setMinimumSize(QSize(640, 560))
        self.resize(820, 780)
        d = QVBoxLayout(self)
        d.setContentsMargins(0, 0, 0, 0)
        self.page = PageTelephone(self)
        d.addWidget(self.page)
        QShortcut(QKeySequence("Ctrl+Q"), self, activated=self.close)
        QShortcut(QKeySequence(Qt.Key_F5), self, activated=self.page.rafraichir)
        self.page.entrer()


def principal(argv=None) -> int:
    argv = list(sys.argv if argv is None else argv)
    if os.geteuid() == 0 and not os.environ.get("LEXOS_PRO_AUTORISER_ROOT"):
        sys.stderr.write("Mon téléphone ne se lance pas en root : utilise ton compte habituel.\n")
        return 2
    app = QApplication(argv)
    app.setApplicationName("Mon téléphone")
    app.setApplicationDisplayName("Mon téléphone")
    app.setDesktopFileName("lexos-telephone")
    app.setWindowIcon(theme.icone("reseau", theme.ORANGE, 64))
    reglages = prefs.charger()
    app.setStyleSheet(theme.feuille(int(reglages.get("taille_texte", 100)),
                                    reglages.get("densite", "confortable")))
    fenetre = FenetreTelephone()
    fenetre.show()
    return app.exec()
