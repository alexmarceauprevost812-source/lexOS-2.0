#!/usr/bin/env python3
"""Pluie Matrix discrete, verte — couche de fond pour LexOS."""
import random
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080

# Katakana + chiffres, comme dans le film. Noto Sans CJK porte les katakana ;
# DejaVu ne les a pas et dessinerait des carres vides.
CJK = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
KATA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"
CHIFFRES = "0123456789"

VERT_TETE = (120, 255, 150)   # le caractere de tete, plus clair
VERT = (31, 158, 61)          # #1F9E3D, le vert de la barre de demarrage


def pluie(largeur, hauteur, graine=812, pas=26, opacite_max=42,
          zone_calme=None):
    """Une image RGBA transparente couverte de colonnes de caracteres.

    zone_calme : (cx, cy, rayon) ou la pluie s'efface, pour que la mascotte
    et la boite de connexion restent lisibles.
    """
    rnd = random.Random(graine)
    couche = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 0))
    d = ImageDraw.Draw(couche)
    try:
        police = ImageFont.truetype(CJK, pas - 4)
        jeu = KATA + CHIFFRES
    except Exception:
        police = ImageFont.truetype(MONO, pas - 4)
        jeu = CHIFFRES + "ABCDEFGHJKLMNPQRSTUVWXYZ"

    for x in range(0, largeur, pas):
        if rnd.random() < 0.18:        # des colonnes vides : ca respire
            continue
        y = rnd.randint(-hauteur, hauteur // 2)
        longueur = rnd.randint(6, 26)
        for i in range(longueur):
            yy = y + i * pas
            if yy < -pas or yy > hauteur:
                continue
            # fondu le long de la trainee : la tete est en bas, elle s'eteint
            # vers le haut — c'est ce qui donne le sens de la chute.
            f = i / max(longueur - 1, 1)
            tete = i == longueur - 1
            a = int(opacite_max * (f ** 1.6))
            if tete:
                a = int(opacite_max * 2.1)
            if a <= 1:
                continue

            if zone_calme:
                cx, cy, ray = zone_calme
                dist = ((x - cx) ** 2 + (yy - cy) ** 2) ** 0.5
                if dist < ray:
                    a = int(a * (dist / ray) ** 2)
                    if a <= 1:
                        continue

            d.text((x, yy), rnd.choice(jeu), font=police,
                   fill=(*(VERT_TETE if tete else VERT), a))
    return couche


if __name__ == "__main__":
    pluie(W, H).save("/home/claude/pluie-1920x1080.png")
    print("ok")
