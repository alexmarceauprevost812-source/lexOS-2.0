# -*- coding: utf-8 -*-
"""Fabrique branding/wallpaper-nomad.svg — le bureau de la démo, en image."""
import sys

LIGNES = [
    "   __         _____ _____",
    "  / /  _____ / __  |  ___|",
    " / /  / _ \\ \\/ / | | |___",
    "/ /__|  __/>  <  | |___  |",
    "\\____/\\___/_/\\_\\ |_____/",
]

L, H = 1920, 1080          # la taille de référence ; le SVG reste vectoriel
CW, CH = 27.0, 47.0        # la cellule monospace : largeur, hauteur
TRAIT = 5.4                # l'épaisseur du trait, ~20 % de la cellule
ACCENT = "#E8590C"

NCOL = max(len(x) for x in LIGNES)
NLIG = len(LIGNES)
BLOC_L, BLOC_H = NCOL * CW, NLIG * CH
X0 = (L - BLOC_L) / 2.0
Y0 = 356.0                 # le bloc est posé un peu au-dessus du milieu

def seg(x1, y1, x2, y2):
    return f'M{x1:.1f} {y1:.1f}L{x2:.1f} {y2:.1f}'

#  ═══ CHAQUE CARACTÈRE EST UN TRAIT, PAS UNE LETTRE ═══
#  Six formes suffisent : _ / \ | < >. Les dessiner nous-mêmes rend le logo
#  indépendant de toute police — voir l'en-tête du SVG.
def glyphe(c, cx, cy):
    x, y = cx, cy
    if c == "_":
        #  Sur le bas de la cellule et sur TOUTE sa largeur : une suite de
        #  soulignés forme alors un seul trait continu, sans dent.
        return seg(x, y + CH - TRAIT / 2, x + CW, y + CH - TRAIT / 2)
    if c == "/":
        return seg(x + 1.5, y + CH - 2, x + CW - 1.5, y + 2)
    if c == "\\":
        return seg(x + 1.5, y + 2, x + CW - 1.5, y + CH - 2)
    if c == "|":
        return seg(x + CW / 2, y + 2, x + CW / 2, y + CH - 2)
    if c == "<":
        return (f'M{x+CW*0.82:.1f} {y+CH*0.16:.1f}'
                f'L{x+CW*0.20:.1f} {y+CH*0.50:.1f}'
                f'L{x+CW*0.82:.1f} {y+CH*0.84:.1f}')
    if c == ">":
        return (f'M{x+CW*0.18:.1f} {y+CH*0.16:.1f}'
                f'L{x+CW*0.80:.1f} {y+CH*0.50:.1f}'
                f'L{x+CW*0.18:.1f} {y+CH*0.84:.1f}')
    return ""

traits = []
for r, ligne in enumerate(LIGNES):
    for c, ch in enumerate(ligne):
        if ch == " ":
            continue
        d = glyphe(ch, X0 + c * CW, Y0 + r * CH)
        if d:
            traits.append(d)
CHEMIN = " ".join(traits)

#  LE CURSEUR SE CALCULE, IL NE SE PLACE PAS À L'ŒIL. Premier jet : un x
#  écrit en dur, qui laissait le bloc flotter 260 px après la fin du texte.
#  DejaVu Sans Mono a une chasse de 0.6023 em — la seule chose à savoir pour
#  poser un curseur au bout d'une ligne monospace.
CODE_TAILLE = 20
CODE_X = 46
CHASSE = 0.6023
LIGNE_CODE = "#  lexos-settings — Paramètres LexOS"
CURSEUR_X = CODE_X + len(LIGNE_CODE) * CODE_TAILLE * CHASSE + 2

BAS = Y0 + BLOC_H                     # sous le bloc du logo
Y_REGLE = BAS + 30
Y_MARQUE = Y_REGLE + 44
Y_VERSION = Y_MARQUE + 38
REGLE_L = 690

#  UN COMMENTAIRE XML NE PEUT PAS CONTENIR « -- ». Le premier jet citait
#  « var(--ac) », le nom CSS de l'accent : librsvg a refusé le fichier tout
#  entier (« Comment must not contain double-hyphen »). Le garde-fou ci-dessous
#  attrape le cas au lieu d'écrire un SVG que personne ne peut lire.
svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!--
  LexOS — fond d'écran « Nomad » : le bureau de la démo web, en image.
  ══════════════════════════════════════════════════════════════════════════
  ALEX, capture de la démo à l'appui : « ajouter ce fond d'écran officiel
  comme fond d'écran », puis « mettre ces images dans l'ISO 96, dans le
  fichier images, si je veux les avoir comme fond d'écran ».

  C'est le bureau de web-demo/index.html, repris valeur par valeur — pas
  redessiné à l'œil :

      fond .......... #000
      grille ........ 64 px, rgba(232,135,58,.05)   (#desktop)
      braise ........ ellipse 60 % x 45 % au point (50 %, 55 %),
                      rgba(232,135,58,.14), éteinte à 70 %
      logo .......... l'ASCII de build.sh, en {ACCENT} (la variable d'accent)
      halo .......... 0 0 24px rgba(232,89,12,.35)  (text-shadow)
      filet ......... dégradé transparent -> accent -> transparent
      marque ........ #b8b8bc, chasse 0.7em
      version ....... #86868c, chasse 0.35em
      code .......... #b8b8bc à 40 %, en haut à gauche

  ═══ POURQUOI LE LOGO N'EST PAS DU TEXTE ═══
  Un dessin ASCII n'a de sens que si CHAQUE caractère occupe exactement la
  même chasse. Le confier à une police, c'est parier qu'elle sera installée
  au moment où le crochet 0300 rend l'image — or fonts-firacode et
  fonts-dejavu voyagent dans une liste OPTIONNELLE. Un repli non
  monospace ne casserait pas la construction : il produirait une bouillie,
  en silence, et on la découvrirait sur une photo.

  Les six formes employées ({" ".join(sorted(set("".join(LIGNES)) - {" "}))}) sont donc tracées ici comme des
  segments, sur une grille de {CW} x {CH}. Aucune police n'intervient, le
  rendu est identique partout, et les traits ont des bouts ronds que même
  Fira Code ne donnait pas.

  Fabriqué par tools/gen-fond-nomad.py — modifier le script, pas ce fichier.
-->
<svg xmlns="http://www.w3.org/2000/svg" width="{L}" height="{H}"
     viewBox="0 0 {L} {H}" role="img"
     aria-label="LexOS — TI·LEX·AL 2.0.0 Nomad">
  <defs>
    <!--  La braise : « radial-gradient(60% 45% at 50% 55%, …, transparent 70%) ».
          En SVG, le rayon se donne en fraction de la boîte : 0.60 et 0.45. -->
    <radialGradient id="braise" cx="0.5" cy="0.55" r="0.5">
      <stop offset="0%"  stop-color="#E8873A" stop-opacity="0.14"/>
      <stop offset="70%" stop-color="#E8873A" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="filet" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%"   stop-color="{ACCENT}" stop-opacity="0"/>
      <stop offset="50%"  stop-color="{ACCENT}" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="{ACCENT}" stop-opacity="0"/>
    </linearGradient>
    <!--  Le halo du logo : « text-shadow: 0 0 24px rgba(232,89,12,.35) ». -->
    <filter id="halo" x="-30%" y="-60%" width="160%" height="220%">
      <feGaussianBlur stdDeviation="12"/>
    </filter>
    <pattern id="grille" width="64" height="64" patternUnits="userSpaceOnUse">
      <path d="M64 0 H0 V64" fill="none" stroke="#E8873A"
            stroke-opacity="0.05" stroke-width="1"/>
    </pattern>
  </defs>

  <rect width="{L}" height="{H}" fill="#000000"/>
  <rect width="{L}" height="{H}" fill="url(#grille)"/>
  <!--  L'ellipse porte la braise : 60 % de la largeur, 45 % de la hauteur,
        centrée au point (50 %, 55 %) comme dans la feuille de style. -->
  <ellipse cx="{L/2:.0f}" cy="{H*0.55:.0f}" rx="{L*0.60:.0f}" ry="{H*0.45:.0f}"
           fill="url(#braise)"/>

  <!--  Le code du fond : les trois premières lignes de lexos-settings, comme
        sur la capture d'Alex. Décoratif, discret, et volontairement court :
        une page entière passerait derrière les icônes du bureau. -->
  <g font-family="DejaVu Sans Mono, Liberation Mono, monospace" font-size="{CODE_TAILLE}"
     fill="#B8B8BC" opacity="0.40" xml:space="preserve">
    <text x="{CODE_X}" y="60">#!/usr/bin/env bash</text>
    <text x="{CODE_X}" y="94"># =============================================================================</text>
    <text x="{CODE_X}" y="128">{LIGNE_CODE}</text>
  </g>
  <rect x="{CURSEUR_X:.0f}" y="112" width="11" height="22" fill="#B8B8BC" opacity="0.40"/>

  <!--  LE LOGO. Deux fois le même tracé : une passe floue pour le halo, une
        passe nette par-dessus. -->
  <g fill="none" stroke="{ACCENT}" stroke-width="{TRAIT}"
     stroke-linecap="round" stroke-linejoin="round">
    <path d="{CHEMIN}" opacity="0.55" filter="url(#halo)"/>
    <path d="{CHEMIN}"/>
  </g>

  <rect x="{(L-REGLE_L)/2:.0f}" y="{Y_REGLE:.0f}" width="{REGLE_L}" height="2"
        fill="url(#filet)"/>

  <text x="{L/2:.0f}" y="{Y_MARQUE:.0f}" text-anchor="middle"
        font-family="DejaVu Sans Mono, Liberation Mono, monospace"
        font-size="25" letter-spacing="17.5" fill="#B8B8BC"
        >T I · L E X · A L</text>
  <text x="{L/2:.0f}" y="{Y_VERSION:.0f}" text-anchor="middle"
        font-family="DejaVu Sans Mono, Liberation Mono, monospace"
        font-size="19" letter-spacing="6.7" fill="#86868C"
        >2.0.0 — NOMAD</text>
</svg>
'''
entete = svg.split("-->", 1)[0]
if "--" in entete.replace("<!--", "", 1):
    raise SystemExit("l'en-tête contient « -- » : librsvg refuserait le fichier")

open(sys.argv[1] if len(sys.argv) > 1 else "branding/wallpaper-nomad.svg",
     "w", encoding="utf-8").write(svg)
print("écrit")
