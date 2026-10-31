#!/usr/bin/env python3
"""Fabrique demon.png, le démon TI-LEX-AL de l'écran de démarrage nomade.

ALEX : « ajouter l'animation du démon quand on ouvre LexOS, au tout début ».
Le thème Plymouth lexos-nomade vit dans l'initramfs d'une clé USB-C : tout le
thème doit rester sous 64 Kio (tests/test_lexos_nomade_demarrage.sh). On part
donc du logo du bureau (bureau/web/ti-demon.png), réduit à 200 px de haut et
ramené à 64 couleurs, puis réécrit en RVB+alpha 8 bits non entrelacé — le
format que Plymouth lit à coup sûr. Le script l'agrandit une seule fois au
chargement, à la taille de l'écran.

Usage : python3 tools/gen-demon-nomade.py
"""
from pathlib import Path

from PIL import Image

RACINE = Path(__file__).resolve().parent.parent
SOURCE = RACINE / "config/includes.chroot/usr/lib/lexos/bureau/web/ti-demon.png"
CIBLE = RACINE / "config/includes.chroot/usr/share/plymouth/themes/lexos-nomade/demon.png"
HAUTEUR = 200
COULEURS = 64

im = Image.open(SOURCE).convert("RGBA")
largeur = round(im.width * HAUTEUR / im.height)
im = im.resize((largeur, HAUTEUR), Image.LANCZOS)
im = im.quantize(COULEURS, method=Image.Quantize.FASTOCTREE).convert("RGBA")
im.save(CIBLE, "PNG", optimize=True)
print(f"{CIBLE.name} : {largeur}x{HAUTEUR}, {CIBLE.stat().st_size} octets")
