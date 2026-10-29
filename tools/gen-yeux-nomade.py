#!/usr/bin/env python3
"""Fabrique les images des yeux du démon pour la saveur nomade.

Les deux amandes rouges, en aplat, avec EXACTEMENT le tracé de demon.js
(OEIL, repère 100 × 52, étiré sans garder les proportions comme le fait le
SVG de la page) — pour que les yeux de Plymouth, de l'écran de connexion et
du bureau démon soient les mêmes d'un bout à l'autre du démarrage.

    python3 tools/gen-yeux-nomade.py

Écrit (Pillow seulement, rien n'est appelé à la construction de l'ISO) :
    config/includes.chroot/usr/share/plymouth/themes/lexos-nomade/yeux.png
    config/includes.chroot/usr/share/lexos/nomade/fond-connexion-nomade.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

RACINE = Path(__file__).resolve().parents[1]
INC = RACINE / "config/includes.chroot"
ROUGE = (0xE0, 0x24, 0x24, 255)
SUR = 4  # suréchantillonnage : bords lissés après réduction

# Le tracé de demon.js : M2 3 C26 8 62 20 97 34 C99 42 92 49 78 50
#                        C56 51 34 42 20 30 C10 21 4 12 2 3 Z
DEPART = (2, 3)
COURBES = [((26, 8), (62, 20), (97, 34)), ((99, 42), (92, 49), (78, 50)),
           ((56, 51), (34, 42), (20, 30)), ((10, 21), (4, 12), (2, 3))]


def contour(pas=64):
    pts, p0 = [DEPART], DEPART
    for c1, c2, p3 in COURBES:
        for i in range(1, pas + 1):
            t = i / pas
            u = 1 - t
            pts.append(tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d
                             for a, b, c, d in zip(p0, c1, c2, p3)))
        p0 = p3
    return pts


def oeil(dessin, x, y, l, h, droit):
    """Un œil dans la boîte (x, y, l, h), repère 100 × 52 étiré ; le droit
    est le gauche en miroir (translate(100 0) scale(-1 1) dans la page)."""
    pts = []
    for px, py in contour():
        if droit:
            px = 100 - px
        pts.append(((x + px / 100 * l) * SUR, (y + py / 52 * h) * SUR))
    dessin.polygon(pts, fill=ROUGE)


def paire(largeur, hauteur, fond, cx, cy, l_paire, h_oeil):
    """Les deux yeux, comme .yeux dans demon.css : chacun 40 % de la largeur
    de la paire, l'un à gauche, l'autre à droite."""
    im = Image.new("RGBA", (largeur * SUR, hauteur * SUR), fond)
    d = ImageDraw.Draw(im)
    x0, y0 = cx - l_paire / 2, cy - h_oeil / 2
    l = 0.40 * l_paire
    oeil(d, x0, y0, l, h_oeil, False)
    oeil(d, x0 + l_paire - l, y0, l, h_oeil, True)
    return im.resize((largeur, hauteur), Image.LANCZOS)


def main():
    # Plymouth : la paire seule, sur transparent, centrée par le script.
    ply = INC / "usr/share/plymouth/themes/lexos-nomade/yeux.png"
    ply.parent.mkdir(parents=True, exist_ok=True)
    paire(640, 112, (0, 0, 0, 0), 320, 56, 640, 108).save(ply, optimize=True)

    # LightDM : 1920 × 1080 noir, les yeux au-dessus de la carte (dont le
    # HAUT est à mi-hauteur : « position=50%,center 50%,start », hook 0410).
    fond = INC / "usr/share/lexos/nomade/fond-connexion-nomade.png"
    fond.parent.mkdir(parents=True, exist_ok=True)
    paire(1920, 1080, (0, 0, 0, 255), 960, 330, 820, 140).convert("RGB").save(fond, optimize=True)
    for p in (ply, fond):
        print(p.relative_to(RACINE), p.stat().st_size, "octets")


if __name__ == "__main__":
    main()
