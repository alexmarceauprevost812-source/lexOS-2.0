#!/usr/bin/env python3
"""
fond-anime.py — le moteur de fonds d'écran animés de LexOS.

Un fond animé, ici, n'est pas une vidéo : c'est une SCÈNE, décrite dans un
petit fichier JSON, et dessinée en direct par ce programme. Une scène est
une pile de couches — un fond, une grille, des braises, du code qui
s'écrit, une pluie de caractères, des étoiles, la marque LexOS — et chaque
couche a ses réglages. C'est ce qui permet d'en fabriquer un sans écrire
une ligne de programme :

    lexos wallpaper anime nouveau mon-fond     # crée le fichier, l'ouvre
    lexos wallpaper anime apercu mon-fond      # une image, pour voir
    lexos wallpaper anime mon-fond             # on le pose

Deux modes, choisis tout seuls
------------------------------
  · ÉCONOME — quand la seule couche animée est du code qui s'écrit. Le
    décor est peint UNE fois en mémoire et chaque salve de caractères ne
    repeint que sa bande de lignes. C'est l'ordre de grandeur du curseur
    qui clignote dans un terminal.
  · COMPLET — dès qu'une couche demande tout l'écran (pluie, étoiles,
    braises qui montent). Là, on redessine l'image entière à la cadence de
    la scène (12 images/seconde par défaut). Ça coûte, et c'est dit.

Dans les deux cas : SUR BATTERIE, TOUT SE FIGE. L'image reste, plus rien
n'est calculé, et ça ne se désactive pas.

La fenêtre
----------
Même recette que fond-video.py : une fenêtre à nous, déclarée fond d'écran
(_NET_WM_WINDOW_TYPE_DESKTOP), maintenue sous tout le reste, et
TRANSPARENTE AUX CLICS — les icônes du bureau et le clic droit répondent à
travers elle. C'est lexos-fond-anime qui rend le bureau de XFCE transparent
au-dessus, pour qu'on la voie sans perdre les icônes.

Sans serveur X
--------------
    LEXOS_FOND_APERCU=/tmp/vu.png python3 fond-anime.py <scène>

dessine la scène dans une image. C'est ce que fait « lexos wallpaper anime
apercu », et c'est ce qui a permis de vérifier tout le dessin sur une
machine de construction qui n'a pas d'écran.
"""
import glob
import json
import math
import os
import random
import shutil
import subprocess
import sys
import time

#  --- Les couleurs d'accent, celles de lexos-theme-gen ------------------------
#  (accent bas, accent, accent haut)
ACCENTS = {
    "orange": ("#A84007", "#E8590C", "#FFC53D"),
    "bleu":   ("#10375F", "#1A5FB4", "#3584E4"),
    "rouge":  ("#8A1512", "#C4211E", "#D8352E"),
    "vert":   ("#125C32", "#1F8F4E", "#2DBF6B"),
    "gris":   ("#5A5A5A", "#8A8A8A", "#B4B4B4"),
    "violet": ("#6234D1", "#8B5CF6", "#A78BFA"),
    "neon":   ("#1FA30A", "#39FF14", "#7BFF5C"),
}

#  Le logo ASCII : celui de build.sh, du terminal et de la démo web.
LOGO = [
    r"   __         _____ _____",
    r"  / /  _____ / __  |  ___|",
    r" / /  / _ \ \/ / | | |___",
    r"/ /__|  __/>  <  | |___  |",
    r"\____/\___/_/\_\ |_____/",
]

#  Où vivent les scènes : celles de LexOS, puis celles de l'utilisateur —
#  qui gagnent, pour qu'on puisse refaire « code » à sa façon sans perdre
#  l'original.
#  LEXOS_FONDS_DIR permet d'essayer des scènes sans les installer — c'est
#  ce que fait la vérification pendant la construction, et c'est la même
#  idée que LEXOS_SETTINGS_DIR pour les Paramètres.
DOSSIER_SYSTEME = os.environ.get("LEXOS_FONDS_DIR", "/usr/share/lexos/fonds")
DOSSIER_UTILISATEUR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "lexos", "fonds")

#  Le code qui s'écrit, quand la scène ne dit pas quel fichier lire.
SOURCES = [
    "/usr/bin/lexos-settings",
    "/usr/lib/lexos/settings.py",
    "/usr/bin/lexos",
    "/usr/lib/lexos/fond-anime.py",
]

BATTERIE_MS = 20000    # on regarde l'alimentation toutes les 20 secondes
ICONES_MS = 15000       # on remonte xfdesktop au-dessus de nous à ce rythme
IPS_DEFAUT = 12        # images par seconde en mode complet
STATIQUES = {"fond", "image", "grille", "braises", "vignette", "marque", "texte"}
ANIMEES = {"code", "pluie", "etoiles", "particules", "horloge", "marque3d"}


# =============================================================================
#  Petites fonctions de service
# =============================================================================
def hex_rgb(code):
    """« #E8590C » -> (0.91, 0.35, 0.05). Un nom d'accent est accepté."""
    if not isinstance(code, str):
        return (1.0, 1.0, 1.0)
    code = code.strip()
    if code.lower() in ("accent", "accent-haut", "accent-bas"):
        lo, ac, hi = accent_courant()
        code = {"accent": ac, "accent-haut": hi, "accent-bas": lo}[code.lower()]
    code = code.lstrip("#")
    if len(code) == 3:
        code = "".join(c * 2 for c in code)
    if len(code) != 6:
        return (1.0, 1.0, 1.0)
    try:
        return tuple(int(code[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return (1.0, 1.0, 1.0)


def accent_courant():
    """L'accent choisi par l'utilisateur, ou l'orange de LexOS."""
    chemin = os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
        "lexos", "accent")
    try:
        with open(chemin, encoding="utf-8") as f:
            nom = f.read().strip().lower()
    except OSError:
        nom = "orange"
    return ACCENTS.get(nom, ACCENTS["orange"])


def version_systeme():
    """« 2.0.0 — NOMAD », lu dans /etc/os-release plutôt que recopié ici."""
    version = codename = ""
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            for ligne in f:
                cle, _, val = ligne.partition("=")
                val = val.strip().strip('"')
                if cle == "VERSION_ID":
                    version = val
                elif cle == "VERSION_CODENAME":
                    codename = val
    except OSError:
        pass
    if version and codename:
        return f"{version} — {codename.upper()}"
    return version or "LexOS"


def source_code(chemin=None):
    """Le texte qui s'écrira. Les tabulations deviennent deux espaces :
    un fond d'écran n'a pas de taquet de tabulation."""
    choix = [chemin] if chemin else []
    choix += [os.environ.get("LEXOS_FOND_CODE_SOURCE") or ""] + list(SOURCES)
    for c in choix:
        if not c:
            continue
        try:
            with open(os.path.expanduser(c), encoding="utf-8", errors="replace") as f:
                texte = f.read()
        except OSError:
            continue
        if texte.strip():
            return texte.replace("\t", "  ").replace("\r", "")
    return "#!/usr/bin/env bash\n# LexOS\n"


#  D'OÙ VIENT LA SOURIS. La fenêtre du fond est transparente aux clics et vit
#  SOUS tout le reste : elle ne recevra jamais un événement de pointeur. On ne
#  l'écoute donc pas — on INTERROGE la position globale, comme le fait déjà
#  coin-actif. La partie GTK installe le lecteur ici au démarrage ; en mode
#  aperçu (sans serveur X), il reste None et LEXOS_FOND_POINTEUR="x,y" permet
#  aux vérifications de simuler une souris.
LIRE_POINTEUR = None


def pointeur_global():
    if LIRE_POINTEUR is not None:
        try:
            return LIRE_POINTEUR()
        except Exception:
            return None
    brut = os.environ.get("LEXOS_FOND_POINTEUR", "")
    if "," in brut:
        try:
            x, y = brut.split(",", 1)
            return float(x), float(y)
        except ValueError:
            return None
    return None


def remonte_xfdesktop(executeur=subprocess.run, cherche=shutil.which):
    """Fait remonter xfdesktop AU-DESSUS de notre fenêtre de fond.

    ALEX : « pas capable de mettre des applications sur le bureau » quand le
    fond animé tourne — les icônes du bureau restaient invisibles, alors
    qu'une image fixe les laissait voir.

    xfdesktop (qui dessine ces icônes) et nous sommes TOUS LES DEUX de type
    _NET_WM_WINDOW_TYPE_DESKTOP — xfwm4 garantit bien que ce calque reste
    sous les fenêtres normales, mais PAS l'ordre RELATIF entre deux fenêtres
    de ce même calque. Notre fenêtre peut donc se retrouver au-dessus de
    xfdesktop plutôt qu'en dessous, et les icônes disparaissent derrière le
    fond animé sans qu'aucun code ne soit à proprement parler « cassé ».
    L'abaisser ENCORE, elle, ne changerait rien : elle est déjà tout en bas.
    C'est xfdesktop qu'il faut remonter, dans CE calque précisément.

    Ça peut se reproduire après le lancement — un rechargement de xfdesktop
    (lexos-theme-gen en déclenche un quand l'accent change, pour repeindre
    les dossiers) le refait apparaître, et l'ordre est de nouveau à refaire.
    D'où l'appel au démarrage ET la minuterie qui le répète.

    « --class » ATTENDAIT « xfdesktop » — ET C'ÉTAIT LE BOGUE DE LA PHOTO.
    xdotool a DEUX filtres différents : « --classname » lit le PREMIER champ
    de WM_CLASS (l'instance), « --class » lit le SECOND (la classe). Le repli
    wmctrl juste en dessous s'écrit « xfdesktop.Xfdesktop » — instance en
    minuscule, classe capitalisée — donc le second champ de xfdesktop est
    « Xfdesktop », pas « xfdesktop ». Un « --class xfdesktop » ne pouvait
    trouver AUCUNE fenêtre (recherche sensible à la casse) : la commande
    « réussissait » (code de sortie 0, aucune exception) sans avoir rien
    remonté du tout — silencieux, comme le reste de cette fonction le
    redoutait déjà en commentaire plus haut. On filtre maintenant sur
    l'INSTANCE (« xfdesktop », en minuscule, le même champ que wmctrl relit
    dans sa moitié gauche), qui ne dépend pas de la capitalisation de la
    classe.
    """
    if cherche("xdotool"):
        args = ["xdotool", "search", "--classname", "xfdesktop", "windowraise"]
    elif cherche("wmctrl"):
        args = ["wmctrl", "-x", "-a", "xfdesktop.Xfdesktop"]
    else:
        return False
    try:
        executeur(args, capture_output=True, timeout=2, check=False)
        return True
    except Exception:
        return False


def sur_batterie():
    """Vrai si une batterie se décharge. Même lecture que lexos-fond-video :
    /sys directement, sans upower ni processus supplémentaire."""
    for f in glob.glob("/sys/class/power_supply/*/status"):
        try:
            with open(f, encoding="utf-8") as fh:
                if fh.read().strip() == "Discharging":
                    return True
        except OSError:
            continue
    return False


# =============================================================================
#  Les scènes : catalogue et lecture
# =============================================================================
def scenes_disponibles():
    """{nom: chemin} — celles de l'utilisateur masquent celles du système."""
    trouvees = {}
    for dossier in (DOSSIER_SYSTEME, DOSSIER_UTILISATEUR):
        for chemin in sorted(glob.glob(os.path.join(dossier, "*.json"))):
            trouvees[os.path.splitext(os.path.basename(chemin))[0]] = chemin
    return trouvees


def scene_repli():
    """Ce qu'on affiche quand la scène demandée est illisible : un fond
    sobre, mais un fond. Un bureau noir sans explication est pire."""
    return {
        "nom": "LexOS",
        "description": "Fond de secours",
        "couches": [
            {"type": "fond", "couleur": "#000000"},
            {"type": "braises", "couleur": "#FF8A1F", "opacite": 0.30},
            {"type": "grille", "pas": 72, "couleur": "accent", "opacite": 0.045},
            {"type": "vignette", "opacite": 0.65},
            {"type": "marque"},
        ],
    }


def charge_scene(nom_ou_chemin):
    """Une scène par son nom (« code ») ou par son chemin."""
    chemin = str(nom_ou_chemin)
    if os.path.sep not in chemin:
        chemin = scenes_disponibles().get(chemin, "")
    if not chemin:
        print(f"scène inconnue : {nom_ou_chemin}", file=sys.stderr)
        return scene_repli()
    try:
        with open(os.path.expanduser(chemin), encoding="utf-8") as f:
            scene = json.load(f)
    except (OSError, ValueError) as e:
        print(f"scène illisible ({chemin}) : {e}", file=sys.stderr)
        return scene_repli()
    if not isinstance(scene, dict) or not isinstance(scene.get("couches"), list):
        print(f"scène mal formée : {chemin}", file=sys.stderr)
        return scene_repli()
    scene.setdefault("nom", os.path.basename(chemin))
    return scene


def nombre(valeur, defaut, mini=None, maxi=None):
    """Un nombre venu d'un fichier écrit à la main : jamais de confiance.
    Une valeur absurde donne le défaut, pas une exception au démarrage."""
    try:
        v = float(valeur)
    except (TypeError, ValueError):
        return defaut
    if math.isnan(v) or math.isinf(v):
        return defaut
    if mini is not None:
        v = max(mini, v)
    if maxi is not None:
        v = min(maxi, v)
    return v


# =============================================================================
#  Les couches animées
# =============================================================================
class CoucheCode:
    """Du code qui s'écrit, caractère par caractère, curseur compris.

    C'est la seule couche capable du mode économe : elle sait dire QUELLES
    lignes ont changé, donc on ne repeint que celles-là.
    """
    econome = True

    def __init__(self, opts, scene):
        self.scene = scene
        self.texte = source_code(opts.get("source"))
        self.couleur = opts.get("couleur", "#B8B8BC")
        self.opacite = nombre(opts.get("opacite"), 0.40, 0.0, 1.0)
        self.par_seconde = nombre(opts.get("vitesse"), 30, 1, 400)
        self.taille = nombre(opts.get("taille"), 0, 0, 0.2)
        self.reste = 0.0
        scene.prepare_code(self)
        self.recommence()

    def recommence(self):
        self.pos = 0
        self.ecran = [""]

    def avance(self, dt):
        """Renvoie (lignes touchées, faut-il tout redessiner)."""
        self.reste += dt * self.par_seconde
        combien = int(self.reste)
        if combien <= 0:
            return set(), False
        self.reste -= combien
        #  Après une longue pause (batterie, veille), on ne rattrape pas dix
        #  minutes d'écriture d'un coup : ça figerait le bureau une seconde.
        combien = min(combien, 400)
        touchees = {len(self.ecran) - 1}
        for _ in range(combien):
            if self.pos >= len(self.texte):
                self.recommence()
                return set(), True
            c = self.texte[self.pos]
            self.pos += 1
            if c == "\n":
                self.ecran.append("")
            else:
                #  Repli à la colonne : une ligne trop longue continue sur la
                #  suivante, comme le fait le navigateur dans la démo.
                if len(self.ecran[-1]) >= self.colonnes:
                    self.ecran.append("")
                self.ecran[-1] += c
            touchees.add(len(self.ecran) - 1)
            if len(self.ecran) > self.lignes:
                #  Écran plein : on repart d'en haut plutôt que d'écrire hors
                #  de vue. Même choix que la démo web.
                self.recommence()
                return set(), True
        return touchees, False

    def lignes_visibles(self):
        out = list(self.ecran)
        out[-1] = out[-1] + "▌"
        return out

    def dessine(self, ctx):
        for i, ligne in enumerate(self.lignes_visibles()):
            self.scene.dessine_ligne_code(ctx, self, i, ligne)


class CouchePluie:
    """La pluie de caractères : des colonnes qui tombent, la tête claire et
    la traîne qui s'efface. Chaque colonne a sa vitesse, sinon l'ensemble
    ressemble à une grille qui descend."""
    econome = False

    def __init__(self, opts, scene):
        self.scene = scene
        self.couleur = opts.get("couleur", "accent")
        self.opacite = nombre(opts.get("opacite"), 0.85, 0.0, 1.0)
        self.vitesse = nombre(opts.get("vitesse"), 14, 0.5, 120)   # lignes/seconde
        self.densite = nombre(opts.get("densite"), 0.6, 0.05, 1.0)
        #  Rien que de l'ASCII par défaut : les katakana de la pluie « façon
        #  Matrix » demandent une police japonaise (fonts-noto-cjk, plus de
        #  100 Mio) que LexOS n'installe pas — sans elle, chaque caractère
        #  devient un carré vide. Qui l'installe peut les écrire ici.
        self.jeu = str(opts.get("caracteres") or
                       "01abcdefghijklmnopqrstuvwxyz23456789#$%&*+-<>[]{}/\\|=")
        self.longueur = int(nombre(opts.get("longueur"), 14, 2, 60))
        self.taille = nombre(opts.get("taille"), 0, 0, 0.2)
        scene.prepare_pluie(self)

    def avance(self, dt):
        for c in self.colonnes:
            c["y"] += c["v"] * dt
            if c["y"] - self.longueur > self.lignes:
                c["y"] = -random.uniform(0, self.lignes * 0.6)
                c["v"] = self.vitesse * random.uniform(0.55, 1.6)
        return set(), False

    def dessine(self, ctx):
        self.scene.dessine_pluie(ctx, self)


class CoucheEtoiles:
    """Un ciel : des points qui scintillent lentement et dérivent à peine.
    La dérive est de l'ordre du pixel par seconde — on la voit sans la
    remarquer, ce qui est tout l'intérêt sur un fond d'écran."""
    econome = False

    def __init__(self, opts, scene):
        self.scene = scene
        self.couleur = opts.get("couleur", "#FFFFFF")
        self.nombre = int(nombre(opts.get("nombre"), 260, 10, 1200))
        self.vitesse = nombre(opts.get("vitesse"), 0.01, 0.0, 1.0)
        self.t = 0.0
        scene.prepare_etoiles(self)

    def avance(self, dt):
        self.t += dt
        for e in self.etoiles:
            e["x"] = (e["x"] + e["vx"] * dt * self.vitesse) % 1.0
        return set(), False

    def dessine(self, ctx):
        self.scene.dessine_etoiles(ctx, self)


class CoucheParticules:
    """Des braises qui montent : elles naissent en bas, s'élèvent, pâlissent
    et repartent — le mouvement d'un feu vu de loin."""
    econome = False

    def __init__(self, opts, scene):
        self.scene = scene
        self.couleur = opts.get("couleur", "accent")
        self.nombre = int(nombre(opts.get("nombre"), 90, 5, 600))
        self.vitesse = nombre(opts.get("vitesse"), 0.045, 0.001, 1.0)
        scene.prepare_particules(self)

    def avance(self, dt):
        for p in self.particules:
            p["y"] -= p["v"] * dt
            p["x"] += math.sin((p["y"] + p["phase"]) * 6.0) * 0.0009
            p["vie"] -= dt * 0.12
            if p["y"] < -0.05 or p["vie"] <= 0:
                self.scene.renait_particule(p, self)
        return set(), False

    def dessine(self, ctx):
        self.scene.dessine_particules(ctx, self)


class CoucheHorloge:
    """L'heure sur le fond. Une seule chose bouge — les chiffres, une fois
    par minute — mais la couche est déclarée animée : il faut bien
    redessiner de temps en temps."""
    econome = False

    def __init__(self, opts, scene):
        self.scene = scene
        self.couleur = opts.get("couleur", "#B8B8BC")
        self.taille = nombre(opts.get("taille"), 0.11, 0.01, 0.5)
        self.x = nombre(opts.get("x"), 0.5, 0.0, 1.0)
        self.y = nombre(opts.get("y"), 0.20, 0.0, 1.0)
        self.format = str(opts.get("format", "%H:%M"))[:32]
        self.opacite = nombre(opts.get("opacite"), 0.9, 0.0, 1.0)

    def avance(self, dt):
        return set(), False

    def dessine(self, ctx):
        self.scene.dessine_horloge(ctx, self)


class CoucheMarque3D:
    """La marque LexOS en relief, qui suit la souris — d'un petit mouvement.

    L'effet vient d'une maquette 3D d'Alex (Lexis_3D) : le logo en pile de
    couches, les copies du fond qui glissent à l'opposé de la souris, la
    face avant qui brille. Ici, pas de vrai 3D : cairo dessine la pile en
    décalant chaque copie, et l'œil fait le reste.

    LE MOUVEMENT EST PETIT, ET C'EST UNE CONSIGNE (« un ti mouvement, pas un
    gros ») : l'amplitude est bornée à quelques pixels par couche. Un fond
    d'écran qui gesticule fatigue en une heure ; un qui respire à peine
    donne de la profondeur sans se faire remarquer.

    Et la douceur n'est pas une transition CSS : chaque image, l'offset
    parcourt une fraction du chemin vers la cible — le logo GLISSE derrière
    la souris au lieu de la coller."""
    econome = False

    def __init__(self, opts, scene):
        self.scene = scene
        #  L'amplitude en fraction de la hauteur d'écran : 0.004 ≈ 4 px par
        #  couche à 1080p, ~20 px de bout en bout. Bornée pour que même une
        #  scène modifiée à la main reste un « ti mouvement ».
        self.amplitude = nombre(opts.get("amplitude"), 0.004, 0.001, 0.010)
        self.copies = int(nombre(opts.get("copies"), 6, 2, 10))
        self.voile = bool(opts.get("voile", True))
        self.ox = 0.0   # offset lissé, en fractions [-0.5 … 0.5]
        self.oy = 0.0

    def avance(self, dt):
        p = pointeur_global()
        if p is None:
            cible_x, cible_y = 0.0, 0.0
        else:
            cible_x = max(-0.5, min(0.5, p[0] / max(1, self.scene.w) - 0.5))
            cible_y = max(-0.5, min(0.5, p[1] / max(1, self.scene.h) - 0.5))
        #  Lissage : ~1/6 du chemin restant par image à 24 ips. Jamais plus
        #  que le chemin entier, même après une longue pause (dt énorme).
        part = min(1.0, dt * 4.0)
        self.ox += (cible_x - self.ox) * part
        self.oy += (cible_y - self.oy) * part
        return set(), True

    def dessine(self, ctx):
        self.scene.dessine_marque3d(ctx, self)


FABRIQUES = {
    "code": CoucheCode,
    "pluie": CouchePluie,
    "etoiles": CoucheEtoiles,
    "particules": CoucheParticules,
    "horloge": CoucheHorloge,
    "marque3d": CoucheMarque3D,
}


# =============================================================================
#  La scène : géométrie, décor, dessin de chaque couche
# =============================================================================
class Scene:
    def __init__(self, cairo_mod, description, largeur, hauteur):
        self.cairo = cairo_mod
        self.desc = description
        self.ips = int(nombre(description.get("ips"), IPS_DEFAUT, 1, 30))
        self.maj_taille(largeur, hauteur)

    # --- Géométrie et polices ------------------------------------------------
    def maj_taille(self, largeur, hauteur):
        self.w = max(320, int(largeur))
        self.h = max(240, int(hauteur))
        self.lo, self.ac, self.hi = accent_courant()
        self.pad_x = max(16, round(self.w * 0.016))
        self.pad_y = max(24, round(self.h * 0.043))
        self.famille = self._famille_monospace()

        #  Les couches statiques déclarées AVANT la première couche animée
        #  forment le décor (peint une fois) ; celles d'après sont repeintes
        #  par-dessus l'animation. C'est ce qui permet d'écrire « vignette »
        #  et « marque » à la fin d'une scène et d'obtenir ce qu'on attend :
        #  par-dessus tout le reste.
        self.decor_couches, self.dessus_couches, self.animees_desc = [], [], []
        vu_anime = False
        for couche in self.desc.get("couches", []):
            if not isinstance(couche, dict):
                continue
            t = str(couche.get("type", "")).lower()
            if t in ANIMEES:
                vu_anime = True
                self.animees_desc.append(couche)
            elif t in STATIQUES:
                (self.dessus_couches if vu_anime else self.decor_couches).append(couche)
            else:
                print(f"couche inconnue, ignorée : {t}", file=sys.stderr)

        self.decor = self._peint_decor()

    def _famille_monospace(self):
        """« Fira Code » si elle est là. Sinon fontconfig rend SILENCIEUSEMENT
        une police proportionnelle : le code cesse d'être aligné et le curseur
        se décale. On vérifie que le « i » et le « M » ont la même largeur —
        la définition d'une chasse fixe."""
        tampon = self.cairo.ImageSurface(self.cairo.FORMAT_ARGB32, 8, 8)
        ctx = self.cairo.Context(tampon)
        for essai in ("Fira Code", "DejaVu Sans Mono", "monospace"):
            ctx.select_font_face(essai, self.cairo.FONT_SLANT_NORMAL,
                                 self.cairo.FONT_WEIGHT_NORMAL)
            ctx.set_font_size(20)
            if abs(ctx.text_extents("i").x_advance
                   - ctx.text_extents("M").x_advance) < 0.01:
                return essai
        return "monospace"

    def _mesure(self, taille):
        """Largeur d'un caractère à cette taille (police à chasse fixe)."""
        tampon = self.cairo.ImageSurface(self.cairo.FORMAT_ARGB32, 8, 8)
        ctx = self.cairo.Context(tampon)
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(taille)
        return ctx.text_extents("M").x_advance or taille * 0.6

    # --- Décor : les couches statiques, peintes une fois ---------------------
    def _peint_decor(self):
        s = self.cairo.ImageSurface(self.cairo.FORMAT_ARGB32, self.w, self.h)
        c = self.cairo.Context(s)
        c.set_source_rgb(0, 0, 0)
        c.paint()
        for couche in self.decor_couches:
            self.peint_statique(c, couche)
        return s

    def peint_dessus(self, ctx):
        for couche in self.dessus_couches:
            self.peint_statique(ctx, couche)

    def peint_statique(self, c, couche):
        t = str(couche.get("type", "")).lower()
        if t == "fond":
            self._fond(c, couche)
        elif t == "image":
            self._image(c, couche)
        elif t == "grille":
            self._grille(c, couche)
        elif t == "braises":
            self._braises(c, couche)
        elif t == "vignette":
            self._vignette(c, couche)
        elif t == "marque":
            self._marque(c, couche)
        elif t == "texte":
            self._texte(c, couche)

    def _fond(self, c, o):
        couleur = o.get("couleur", "#000000")
        deux = o.get("couleur2")
        if deux:
            if str(o.get("sens", "vertical")).lower() == "radial":
                g = self.cairo.RadialGradient(self.w / 2, self.h / 2, 0,
                                              self.w / 2, self.h / 2,
                                              math.hypot(self.w, self.h) / 2)
            else:
                g = self.cairo.LinearGradient(0, 0, 0, self.h)
            g.add_color_stop_rgb(0, *hex_rgb(couleur))
            g.add_color_stop_rgb(1, *hex_rgb(deux))
            c.set_source(g)
        else:
            c.set_source_rgb(*hex_rgb(couleur))
        c.paint()

    def _image(self, c, o):
        """Une image de fond. cairo ne lit QUE le PNG : dire pourquoi vaut
        mieux qu'un rectangle noir que personne ne s'explique."""
        chemin = os.path.expanduser(str(o.get("chemin", "")))
        if not chemin.lower().endswith(".png") or not os.path.isfile(chemin):
            print(f"image ignorée (un PNG est attendu) : {chemin}", file=sys.stderr)
            return
        try:
            img = self.cairo.ImageSurface.create_from_png(chemin)
        except Exception as e:
            print(f"image illisible : {chemin} ({e})", file=sys.stderr)
            return
        iw, ih = img.get_width(), img.get_height()
        if iw <= 0 or ih <= 0:
            return
        if str(o.get("cadrage", "remplir")).lower() == "ajuster":
            k = min(self.w / iw, self.h / ih)
        else:
            k = max(self.w / iw, self.h / ih)
        c.save()
        c.translate((self.w - iw * k) / 2, (self.h - ih * k) / 2)
        c.scale(k, k)
        c.set_source_surface(img, 0, 0)
        c.paint_with_alpha(nombre(o.get("opacite"), 1.0, 0.0, 1.0))
        c.restore()

    def _grille(self, c, o):
        pas = int(nombre(o.get("pas"), 72, 8, 400))
        c.set_source_rgba(*hex_rgb(o.get("couleur", "accent")),
                          nombre(o.get("opacite"), 0.045, 0.0, 1.0))
        c.set_line_width(1)
        x = 0
        while x <= self.w:
            c.move_to(x + 0.5, 0); c.line_to(x + 0.5, self.h); x += pas
        y = 0
        while y <= self.h:
            c.move_to(0, y + 0.5); c.line_to(self.w, y + 0.5); y += pas
        c.stroke()

    def _braises(self, c, o):
        cx = nombre(o.get("x"), 0.5, -1, 2) * self.w
        cy = nombre(o.get("y"), 0.52, -1, 2) * self.h
        r = max(self.w, self.h) * nombre(o.get("rayon"), 0.55, 0.05, 3.0)
        op = nombre(o.get("opacite"), 0.30, 0.0, 1.0)
        g = self.cairo.RadialGradient(cx, cy, 0, cx, cy, r)
        g.add_color_stop_rgba(0.00, *hex_rgb(o.get("couleur", "#FF8A1F")), op)
        g.add_color_stop_rgba(0.38, *hex_rgb(o.get("couleur2", "#C4460D")), op * 0.43)
        g.add_color_stop_rgba(1.00, 0, 0, 0, 0)
        c.set_source(g)
        c.paint()

    def _vignette(self, c, o):
        v = self.cairo.RadialGradient(self.w / 2, self.h / 2, 0,
                                      self.w / 2, self.h / 2,
                                      math.hypot(self.w, self.h) * 0.5)
        v.add_color_stop_rgba(0.55, 0, 0, 0, 0)
        v.add_color_stop_rgba(1.00, 0, 0, 0, nombre(o.get("opacite"), 0.65, 0.0, 1.0))
        c.set_source(v)
        c.paint()

    def _texte(self, c, o):
        contenu = str(o.get("contenu", ""))[:200]
        if not contenu:
            return
        taille = max(8, nombre(o.get("taille"), 0.03, 0.005, 0.5) * self.h)
        c.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                           self.cairo.FONT_WEIGHT_NORMAL)
        c.set_font_size(taille)
        c.set_source_rgba(*hex_rgb(o.get("couleur", "#B8B8BC")),
                          nombre(o.get("opacite"), 0.9, 0.0, 1.0))
        large = c.text_extents(contenu).x_advance
        x = nombre(o.get("x"), 0.5, 0.0, 1.0) * self.w
        align = str(o.get("align", "centre")).lower()
        if align == "centre":
            x -= large / 2
        elif align == "droite":
            x -= large
        c.move_to(x, nombre(o.get("y"), 0.9, 0.0, 1.0) * self.h)
        c.show_text(contenu)

    # --- La marque LexOS -----------------------------------------------------
    def _marque(self, ctx, o):
        """Proportions de branding/wallpaper.svg, ramenées à la hauteur de
        l'écran : corps 64/1080, interligne 74, trait à +344, la ligne
        TI · LEX · AL à +400 et la version à +452 sous la première ligne."""
        cx, cy = self.w / 2, self.h * 0.555

        if o.get("voile", True):
            #  Sans ce voile, le code (ou la pluie) traverse le logo et plus
            #  rien n'est lisible. C'est l'ellipse floutée du fond fixe.
            voile = self.cairo.RadialGradient(cx, cy, 0, cx, cy, self.w * 0.40)
            voile.add_color_stop_rgba(0.00, 0, 0, 0, 0.92)
            voile.add_color_stop_rgba(0.70, 0, 0, 0, 0.80)
            voile.add_color_stop_rgba(1.00, 0, 0, 0, 0.0)
            ctx.save()
            ctx.translate(cx, cy); ctx.scale(1.0, 0.52); ctx.translate(-cx, -cy)
            ctx.set_source(voile); ctx.paint()
            ctx.restore()

            halo = self.cairo.RadialGradient(cx, cy * 0.96, 0, cx, cy * 0.96,
                                             self.w * 0.23)
            halo.add_color_stop_rgba(0.0, *hex_rgb(self.ac), 0.13)
            halo.add_color_stop_rgba(1.0, *hex_rgb(self.ac), 0.0)
            ctx.save()
            ctx.translate(cx, cy * 0.96); ctx.scale(1.0, 0.36)
            ctx.translate(-cx, -cy * 0.96)
            ctx.set_source(halo); ctx.paint()
            ctx.restore()

        taille = max(14, self.h / 16.875)
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(taille)
        large = max(ctx.text_extents(l).x_advance for l in LOGO)
        x0 = cx - large / 2
        y0 = self.h * 0.4185

        feu = self.cairo.LinearGradient(0, y0 - taille, 0, y0 + taille * 4.7)
        feu.add_color_stop_rgb(0.0, *hex_rgb(self.hi))
        feu.add_color_stop_rgb(0.55, *hex_rgb(self.ac))
        feu.add_color_stop_rgb(1.0, *hex_rgb(self.lo))
        ctx.set_source(feu)
        for i, ligne in enumerate(LOGO):
            ctx.move_to(x0, y0 + i * taille * 1.156)
            ctx.show_text(ligne)

        y_trait = y0 + taille * 5.375
        trait = self.cairo.LinearGradient(cx - self.w * 0.19, 0,
                                          cx + self.w * 0.19, 0)
        trait.add_color_stop_rgba(0.0, *hex_rgb(self.ac), 0.0)
        trait.add_color_stop_rgba(0.3, *hex_rgb(self.ac), 0.85)
        trait.add_color_stop_rgba(1.0, *hex_rgb(self.ac), 0.0)
        ctx.set_source(trait)
        ctx.rectangle(cx - self.w * 0.19, y_trait, self.w * 0.38, 2)
        ctx.fill()

        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_source_rgb(*hex_rgb("#B8B8BC"))
        self._texte_espace(ctx, str(o.get("sous_titre", "T I · L E X · A L"))[:60],
                           cx, y0 + taille * 6.25, max(11, self.h / 41.5),
                           self.h / 98)
        if o.get("version", True):
            ctx.set_source_rgb(*hex_rgb("#6E6E74"))
            self._texte_espace(ctx, version_systeme(), cx, y0 + taille * 7.06,
                               max(9, self.h / 56.8), self.h / 216)

    def dessine_marque3d(self, ctx, o):
        """La marque en pile de profondeur — le dessin de CoucheMarque3D.

        Même géométrie que _marque (le logo fixe) : ce qui change, c'est que
        le corps du logo est dessiné N+1 fois. Les N copies du fond glissent
        À L'OPPOSÉ de la souris, de plus en plus loin et de plus en plus
        éteintes ; la face avant glisse AVEC elle, à peine. C'est le
        parallaxe le plus simple qui soit, et l'œil y lit du relief."""
        cx, cy = self.w / 2, self.h * 0.555

        if o.voile:
            voile = self.cairo.RadialGradient(cx, cy, 0, cx, cy, self.w * 0.40)
            voile.add_color_stop_rgba(0.00, 0, 0, 0, 0.92)
            voile.add_color_stop_rgba(0.70, 0, 0, 0, 0.80)
            voile.add_color_stop_rgba(1.00, 0, 0, 0, 0.0)
            ctx.save()
            ctx.translate(cx, cy); ctx.scale(1.0, 0.52); ctx.translate(-cx, -cy)
            ctx.set_source(voile); ctx.paint()
            ctx.restore()

            halo = self.cairo.RadialGradient(cx, cy * 0.96, 0, cx, cy * 0.96,
                                             self.w * 0.23)
            halo.add_color_stop_rgba(0.0, *hex_rgb(self.ac), 0.13)
            halo.add_color_stop_rgba(1.0, *hex_rgb(self.ac), 0.0)
            ctx.save()
            ctx.translate(cx, cy * 0.96); ctx.scale(1.0, 0.36)
            ctx.translate(-cx, -cy * 0.96)
            ctx.set_source(halo); ctx.paint()
            ctx.restore()

        taille = max(14, self.h / 16.875)
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(taille)
        large = max(ctx.text_extents(l).x_advance for l in LOGO)
        x0 = cx - large / 2
        y0 = self.h * 0.4185

        pas = self.h * o.amplitude          # le déplacement d'UNE couche
        rl, gl, bl = hex_rgb(self.lo)

        #  Les copies du fond, de la plus lointaine à la plus proche : la
        #  lointaine bouge le plus (c'est elle qui donne la profondeur) et
        #  s'éteint le plus. La verticale bouge moins que l'horizontale —
        #  comme sur la maquette, où l'inclinaison en X était bornée plus bas.
        for i in range(o.copies, 0, -1):
            k = i / o.copies
            dx = -o.ox * pas * i * 2.0
            dy = -o.oy * pas * i * 1.4
            ctx.set_source_rgba(rl, gl, bl, 0.30 * (1.0 - k) + 0.05)
            for j, ligne in enumerate(LOGO):
                ctx.move_to(x0 + dx, y0 + dy + j * taille * 1.156)
                ctx.show_text(ligne)

        #  La face avant : le dégradé de feu de la marque fixe, décalée AVEC
        #  la souris — d'à peine plus d'une couche.
        dxa = o.ox * pas * 1.3
        dya = o.oy * pas * 0.9
        feu = self.cairo.LinearGradient(0, y0 + dya - taille,
                                        0, y0 + dya + taille * 4.7)
        feu.add_color_stop_rgb(0.0, *hex_rgb(self.hi))
        feu.add_color_stop_rgb(0.55, *hex_rgb(self.ac))
        feu.add_color_stop_rgb(1.0, *hex_rgb(self.lo))
        ctx.set_source(feu)
        for j, ligne in enumerate(LOGO):
            ctx.move_to(x0 + dxa, y0 + dya + j * taille * 1.156)
            ctx.show_text(ligne)

        #  Le trait et les lignes du bas ne bougent PAS : ils sont le sol.
        #  Si tout glissait ensemble, l'œil ne verrait plus un relief mais
        #  une image qui tremble.
        y_trait = y0 + taille * 5.375
        trait = self.cairo.LinearGradient(cx - self.w * 0.19, 0,
                                          cx + self.w * 0.19, 0)
        trait.add_color_stop_rgba(0.0, *hex_rgb(self.ac), 0.0)
        trait.add_color_stop_rgba(0.3, *hex_rgb(self.ac), 0.85)
        trait.add_color_stop_rgba(1.0, *hex_rgb(self.ac), 0.0)
        ctx.set_source(trait)
        ctx.rectangle(cx - self.w * 0.19, y_trait, self.w * 0.38, 2)
        ctx.fill()

        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_source_rgb(*hex_rgb("#B8B8BC"))
        self._texte_espace(ctx, "T I · L E X · A L",
                           cx, y0 + taille * 6.25, max(11, self.h / 41.5),
                           self.h / 98)
        ctx.set_source_rgb(*hex_rgb("#6E6E74"))
        self._texte_espace(ctx, version_systeme(), cx, y0 + taille * 7.06,
                           max(9, self.h / 56.8), self.h / 216)

    def _texte_espace(self, ctx, texte, cx, y, taille, espace):
        """Un texte centré, lettre à lettre, avec de l'air entre les lettres —
        le « letter-spacing » du fond fixe, que cairo n'a pas."""
        ctx.set_font_size(taille)
        large = sum(ctx.text_extents(c).x_advance + espace for c in texte) - espace
        x = cx - large / 2
        for c in texte:
            ctx.move_to(x, y)
            ctx.show_text(c)
            x += ctx.text_extents(c).x_advance + espace

    # --- Couche « code » -----------------------------------------------------
    def prepare_code(self, couche):
        couche.police = max(11, round(self.h * (couche.taille or (1 / 72))))
        couche.interligne = couche.police * 1.7
        couche.car_w = self._mesure(couche.police)
        couche.colonnes = max(20, int((self.w - 2 * self.pad_x) / couche.car_w))
        couche.lignes = max(4, int((self.h - self.pad_y - self.pad_x) / couche.interligne))

    def dessine_ligne_code(self, ctx, couche, numero, texte):
        """Écrit une ligne à sa place. Le fond de la ligne est d'abord remis
        au décor : c'est ce qui efface le curseur précédent."""
        y_haut = self.pad_y + numero * couche.interligne
        ctx.save()
        ctx.rectangle(0, y_haut - couche.interligne * 0.25,
                      self.w, couche.interligne * 1.2)
        ctx.clip()
        ctx.set_source_surface(self.decor, 0, 0)
        ctx.paint()
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(couche.police)
        ctx.set_source_rgba(*hex_rgb(couche.couleur), couche.opacite)
        ctx.move_to(self.pad_x, y_haut + couche.police)
        ctx.show_text(texte)
        ctx.restore()

    def zone_ligne_code(self, couche, numero):
        y_haut = self.pad_y + numero * couche.interligne
        return (0, int(y_haut - couche.interligne * 0.25),
                self.w, int(couche.interligne * 1.2) + 2)

    # --- Couche « pluie » ----------------------------------------------------
    def prepare_pluie(self, couche):
        couche.police = max(11, round(self.h * (couche.taille or (1 / 54))))
        couche.car_w = self._mesure(couche.police)
        couche.interligne = couche.police * 1.25
        couche.lignes = max(4, int(self.h / couche.interligne) + 2)
        total = max(1, int(self.w / couche.car_w))
        couche.colonnes = []
        for i in range(total):
            if random.random() > couche.densite:
                continue
            couche.colonnes.append({
                "x": i * couche.car_w,
                "y": -random.uniform(0, couche.lignes * 1.5),
                "v": couche.vitesse * random.uniform(0.55, 1.6),
                "graines": [random.randrange(1 << 30)
                            for _ in range(couche.longueur + 1)],
            })

    def dessine_pluie(self, ctx, couche):
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(couche.police)
        base = hex_rgb(couche.couleur)
        jeu = couche.jeu
        for col in couche.colonnes:
            tete = int(col["y"])
            for k in range(couche.longueur):
                ligne = tete - k
                if ligne < 0 or ligne > couche.lignes:
                    continue
                #  La tête est claire, la traîne s'efface : c'est ce qui donne
                #  l'impression que ça tombe, plus que le mouvement lui-même.
                force = (1.0 - k / couche.longueur) ** 1.6
                if k == 0:
                    ctx.set_source_rgba(1, 1, 1, couche.opacite)
                else:
                    ctx.set_source_rgba(*base, couche.opacite * force)
                #  Le caractère dépend de la colonne ET de la ligne : il ne
                #  change donc pas à chaque image (ce qui scintillerait), mais
                #  change quand la colonne repart d'en haut.
                idx = (col["graines"][k % len(col["graines"])] + ligne) % len(jeu)
                ctx.move_to(col["x"], ligne * couche.interligne)
                ctx.show_text(jeu[idx])

    # --- Couche « etoiles » --------------------------------------------------
    def prepare_etoiles(self, couche):
        couche.etoiles = []
        for _ in range(couche.nombre):
            couche.etoiles.append({
                "x": random.random(), "y": random.random(),
                "r": random.uniform(0.4, 1.6),
                "phase": random.uniform(0, 6.283),
                "vx": random.uniform(-1.0, 1.0),
            })

    def dessine_etoiles(self, ctx, couche):
        base = hex_rgb(couche.couleur)
        echelle = max(1.0, self.h / 1080)
        for e in couche.etoiles:
            a = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(couche.t * 1.7 + e["phase"]))
            ctx.set_source_rgba(*base, a)
            ctx.arc(e["x"] * self.w, e["y"] * self.h, e["r"] * echelle, 0, 6.283)
            ctx.fill()

    # --- Couche « particules » ----------------------------------------------
    def prepare_particules(self, couche):
        couche.particules = []
        for _ in range(couche.nombre):
            p = self.renait_particule({}, couche)
            p["y"] = random.random()
            couche.particules.append(p)

    def renait_particule(self, p, couche):
        p["x"] = random.random()
        p["y"] = 1.05
        p["r"] = random.uniform(0.6, 2.2)
        p["phase"] = random.uniform(0, 6.283)
        p["vie"] = random.uniform(0.5, 1.0)
        p["v"] = couche.vitesse * random.uniform(0.5, 1.7)
        return p

    def dessine_particules(self, ctx, couche):
        base = hex_rgb(couche.couleur)
        haut = hex_rgb("accent-haut") if couche.couleur == "accent" else base
        echelle = max(1.0, self.h / 1080)
        for p in couche.particules:
            a = max(0.0, min(1.0, p["vie"])) * 0.85
            #  Plus la braise monte, plus elle pâlit vers l'accent clair.
            m = 1.0 - max(0.0, min(1.0, p["y"]))
            coul = tuple(base[i] + (haut[i] - base[i]) * m for i in range(3))
            ctx.set_source_rgba(*coul, a)
            ctx.arc(p["x"] * self.w, p["y"] * self.h, p["r"] * echelle, 0, 6.283)
            ctx.fill()

    # --- Couche « horloge » --------------------------------------------------
    def dessine_horloge(self, ctx, couche):
        try:
            texte = time.strftime(couche.format)
        except ValueError:
            texte = time.strftime("%H:%M")
        taille = max(12, couche.taille * self.h)
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(taille)
        ctx.set_source_rgba(*hex_rgb(couche.couleur), couche.opacite)
        large = ctx.text_extents(texte).x_advance
        ctx.move_to(couche.x * self.w - large / 2, couche.y * self.h)
        ctx.show_text(texte)


# =============================================================================
#  Le moteur : construit les couches, choisit le mode, dessine
# =============================================================================
class Moteur:
    def __init__(self, cairo_mod, scene_desc, largeur, hauteur):
        self.cairo = cairo_mod
        self.scene = Scene(cairo_mod, scene_desc, largeur, hauteur)
        self.couches = []
        for desc in self.scene.animees_desc:
            fabrique = FABRIQUES.get(str(desc.get("type", "")).lower())
            if fabrique:
                self.couches.append(fabrique(desc, self.scene))
        #  Mode économe : rien d'animé, ou uniquement du code qui s'écrit.
        self.econome = all(getattr(c, "econome", False) for c in self.couches)
        self.codes = [c for c in self.couches if isinstance(c, CoucheCode)]

    @property
    def ips(self):
        return self.scene.ips

    def image_complete(self, ctx):
        """Une image entière : décor, couches animées, couches du dessus."""
        ctx.set_source_surface(self.scene.decor, 0, 0)
        ctx.paint()
        for c in self.couches:
            c.dessine(ctx)
        self.scene.peint_dessus(ctx)

    def avance(self, dt):
        """Fait avancer toutes les couches. Renvoie (zones, tout_redessiner)
        — les zones ne servent qu'au mode économe."""
        zones, tout = [], False
        for c in self.couches:
            touchees, recommence = c.avance(dt)
            if recommence:
                tout = True
            elif isinstance(c, CoucheCode):
                zones.extend((c, i) for i in touchees)
        return zones, tout


# =============================================================================
#  Aperçu : dessiner la scène dans une image, sans serveur X
# =============================================================================
def apercu(scene_desc, sortie, largeur=1920, hauteur=1080, secondes=6.0):
    import cairo
    moteur = Moteur(cairo, scene_desc, largeur, hauteur)
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, largeur, hauteur)
    ctx = cairo.Context(surface)

    #  On déroule l'animation pour de bon, avec le même pas de temps qu'à
    #  l'écran : une image d'aperçu qui mentirait sur le rendu ne servirait
    #  à rien. On s'arrête juste avant que le code reparte du haut, sinon
    #  l'aperçu montrerait un écran vide.
    pas = 1.0 / max(1, moteur.ips)
    for _ in range(int(max(0.0, secondes) / pas)):
        avant = [(c, list(c.ecran), c.pos) for c in moteur.codes]
        _, tout = moteur.avance(pas)
        if tout:
            for c, ecran, pos in avant:
                c.ecran, c.pos = ecran, pos
            break
    moteur.image_complete(ctx)
    surface.write_to_png(sortie)
    return sortie


# =============================================================================
#  La fenêtre de fond d'écran
# =============================================================================
def main():
    nom = sys.argv[1] if len(sys.argv) > 1 else "code"
    scene_desc = charge_scene(nom)

    sortie = os.environ.get("LEXOS_FOND_APERCU")
    if sortie:
        largeur = int(nombre(os.environ.get("LEXOS_FOND_LARGEUR"), 1920, 320, 7680))
        hauteur = int(nombre(os.environ.get("LEXOS_FOND_HAUTEUR"), 1080, 240, 4320))
        print(apercu(scene_desc, sortie, largeur, hauteur))
        return

    try:
        import cairo
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk, Gdk, GLib
    except Exception as e:
        print(f"GTK/cairo indisponible : {e}", file=sys.stderr)
        sys.exit(2)

    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        print("aucune session graphique (DISPLAY vide)", file=sys.stderr)
        sys.exit(3)

    class Fond(Gtk.Window):
        def __init__(self):
            super().__init__(type=Gtk.WindowType.TOPLEVEL)
            ecran = self.get_screen()
            self.larg = ecran.get_width()
            self.haut = ecran.get_height()

            #  Le lecteur de souris pour marque3d. La fenêtre est transparente
            #  aux clics et vit sous tout : elle ne recevra jamais un
            #  événement de pointeur — on interroge donc la position GLOBALE,
            #  comme coin-actif. Si quoi que ce soit manque (Wayland exotique,
            #  pas de seat), le lecteur reste None et le logo reste centré :
            #  un fond qui ne suit pas la souris vaut mieux qu'un fond mort.
            global LIRE_POINTEUR
            try:
                souris = Gdk.Display.get_default().get_default_seat().get_pointer()

                def _lire():
                    _, px, py = souris.get_position()
                    return float(px), float(py)

                LIRE_POINTEUR = _lire
            except Exception:
                LIRE_POINTEUR = None

            self.set_app_paintable(True)
            self.set_decorated(False)
            self.set_resizable(False)
            self.set_skip_taskbar_hint(True)
            self.set_skip_pager_hint(True)
            self.set_accept_focus(False)
            self.set_focus_on_map(False)
            self.set_keep_below(True)
            self.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
            self.move(0, 0)
            self.set_default_size(self.larg, self.haut)
            self.stick()

            self.moteur = Moteur(cairo, scene_desc, self.larg, self.haut)
            self.tampon = None
            self.timer = None
            self.dernier = time.monotonic()

            self.connect("draw", self.on_draw)
            self.connect("destroy", Gtk.main_quit)
            self.show_all()

            fen = self.get_window()
            if fen is not None:
                fen.lower()
                try:
                    #  Forme d'entrée vide : tous les clics traversent la
                    #  fenêtre. Le bureau — icônes, clic droit — répond comme
                    #  si elle n'existait pas.
                    fen.input_shape_combine_region(cairo.Region(), 0, 0)
                except Exception:
                    pass

            #  Démarrer sur batterie donnerait un écran vide et figé : on
            #  déroule quelques secondes d'avance avant de geler, pour que le
            #  fond soit complet plutôt que blanc.
            if sur_batterie():
                pas = 1.0 / max(1, self.moteur.ips)
                for _ in range(int(8.0 / pas)):
                    _, tout = self.moteur.avance(pas)
                    if tout:
                        break

            self.reconstruit_tampon()
            if not sur_batterie():
                self.reprend()
            GLib.timeout_add(BATTERIE_MS, self.surveille_batterie)

            #  xfdesktop n'est pas forcément déjà là au moment où on se lève —
            #  on le remonte tout de suite, et la minuterie rattrape le cas où
            #  il apparaît (ou réapparaît) juste après.
            remonte_xfdesktop()
            GLib.timeout_add(ICONES_MS, self.remonte_icones)

        # --- Dessin ----------------------------------------------------------
        def reconstruit_tampon(self):
            self.tampon = cairo.ImageSurface(cairo.FORMAT_ARGB32,
                                             self.larg, self.haut)
            ctx = cairo.Context(self.tampon)
            if self.moteur.econome:
                #  Mode économe : le tampon porte le décor et le code déjà
                #  écrit ; la marque et la vignette sont posées à l'affichage.
                ctx.set_source_surface(self.moteur.scene.decor, 0, 0)
                ctx.paint()
                for c in self.moteur.codes:
                    c.dessine(ctx)
            else:
                self.moteur.image_complete(ctx)
            self.queue_draw()

        def on_draw(self, _widget, ctx):
            ctx.set_source_surface(self.tampon, 0, 0)
            ctx.paint()
            if self.moteur.econome:
                self.moteur.scene.peint_dessus(ctx)
            return False

        # --- Le battement ----------------------------------------------------
        def bat(self):
            maintenant = time.monotonic()
            dt = min(1.0, maintenant - self.dernier)
            self.dernier = maintenant

            zones, tout = self.moteur.avance(dt)
            if tout or not self.moteur.econome:
                self.reconstruit_tampon()
                return True

            ctx = cairo.Context(self.tampon)
            for couche, i in zones:
                visibles = couche.lignes_visibles()
                if i < len(visibles):
                    self.moteur.scene.dessine_ligne_code(ctx, couche, i, visibles[i])
                    self.queue_draw_area(
                        *self.moteur.scene.zone_ligne_code(couche, i))
            return True

        # --- Batterie --------------------------------------------------------
        def reprend(self):
            if self.timer is None:
                self.dernier = time.monotonic()
                self.timer = GLib.timeout_add(
                    int(1000 / max(1, self.moteur.ips)), self.bat)

        def fige(self):
            if self.timer is not None:
                GLib.source_remove(self.timer)
                self.timer = None

        def surveille_batterie(self):
            if sur_batterie():
                self.fige()
            else:
                self.reprend()
            return True

        def remonte_icones(self):
            remonte_xfdesktop()
            return True

    Fond()
    Gtk.main()


if __name__ == "__main__":
    main()
