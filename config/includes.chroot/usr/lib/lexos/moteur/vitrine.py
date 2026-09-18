"""La fenêtre, et rien d'autre — le client léger du démon.

═══ POURQUOI CE FICHIER EXISTE ═══
Quand le démon tient déjà le serveur et l'état, la fenêtre n'a plus besoin
d'importer volet.py : elle a juste besoin d'une adresse. Or importer
volet.py coûte 438 ms MESURÉES — son.py, boost/systeme, moteur/outils, tout
l'arbre. Ce module-ci n'importe que PySide6 (le coût de Qt, incompressible)
et moteur/fenetre.py (quelques lignes).

C'est la moitié du gain du démon. L'autre moitié est la lecture d'état, que
le préchauffage fait pendant que Chromium démarre.

⚠ IL NE SAIT RIEN FAIRE SANS LE DÉMON, et c'est voulu : il ne monte aucun
serveur, ne lit aucun état. Si le démon n'est pas là, le lanceur n'appelle
pas ce fichier — il prend le chemin d'avant, entier.
"""

from __future__ import annotations

import sys
from pathlib import Path

_ICI = Path(__file__).resolve().parent.parent
if str(_ICI) not in sys.path:
    sys.path.insert(0, str(_ICI))

from moteur import fenetre as _fenetre       # noqa: E402


def volet(port: int, quoi: str, mode: str, haut: int) -> int:
    """Le volet : sans cadre, transparent, hors d'Alt+Tab, et il se referme
    quand on clique ailleurs. Géométrie identique à celle de volet.py — elle
    est recopiée ici plutôt que partagée parce qu'elle dépend de VOLETS et de
    la barre, que ce fichier ne veut pas importer."""
    from PySide6.QtCore import QUrl

    app = _fenetre.application("Volet LexOS")
    vue = _fenetre.vue_transparente("Volet LexOS")

    ecran = app.primaryScreen().availableGeometry()
    largeur = min(560, ecran.width() - 24)
    hauteur = min(680, int(ecran.height() * 0.78))
    if quoi == "meteo":
        gauche = ecran.x() + 14
    elif quoi == "rapides":
        largeur = min(340, ecran.width() - 24)
        hauteur = min(560, hauteur)
        gauche = ecran.x() + ecran.width() - largeur - 14
    else:
        gauche = ecran.x() + (ecran.width() - largeur) // 2
    vue.setGeometry(gauche, ecran.y() + haut, largeur, hauteur)

    vue.load(QUrl(f"http://127.0.0.1:{port}/index.html?mode={mode}#{quoi}"))
    vue.show()
    vue.raise_()
    vue.activateWindow()
    _fenetre.ferme_au_flou(app, vue)
    return app.exec()


def reglages(port: int, section: str, mode: str) -> int:
    """Les Paramètres : une fenêtre ordinaire, à la taille de l'écran.

    Même géométrie que settings.py — elle vient de moteur/fenetre.py, donc
    elle n'est pas recopiée : c'est le même code qui la calcule des deux
    côtés, avec le commentaire qui dit pourquoi (une fenêtre à 980 x 700
    coupait la barre latérale du ThinkPad au milieu)."""
    from PySide6.QtCore import QUrl

    app = _fenetre.application("Paramètres LexOS")
    fen, vue = _fenetre.fenetre_cadree(
        app, "Paramètres LexOS",
        "/usr/share/icons/hicolor/128x128/apps/lexos-reglages.png")
    mesures = _fenetre.taille_ecran(app)
    if mesures is not None:
        largeur, hauteur, x, y = mesures
        fen.resize(largeur, hauteur)
        fen.move(x, y)
    else:
        fen.resize(980, 700)
    url = f"http://127.0.0.1:{port}/index.html?mode={mode}"
    if section:
        url += f"#{section}"
    vue.load(QUrl(url))
    fen.show()
    return app.exec()


if __name__ == "__main__":
    #  volet <port> <quoi> <mode> <haut>
    args = sys.argv[1:]
    if len(args) == 5 and args[0] == "volet":
        sys.exit(volet(int(args[1]), args[2], args[3], int(args[4])))
    if len(args) == 4 and args[0] == "reglages":
        sys.exit(reglages(int(args[1]), args[2], args[3]))
    print("Usage : vitrine.py volet <port> <quoi> <mode> <haut>\n"
          "        vitrine.py reglages <port> <section> <mode>", file=sys.stderr)
    sys.exit(2)
