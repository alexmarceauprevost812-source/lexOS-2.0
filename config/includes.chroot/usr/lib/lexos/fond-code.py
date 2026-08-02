#!/usr/bin/env python3
"""
fond-code.py — le fond d'écran qui s'écrit tout seul.

Le fond par défaut de LexOS porte, derrière la marque, des colonnes de code.
Elles sont FIXES : c'est une image (branding/wallpaper.svg). Ce programme
dessine la même scène, mais VIVANTE — le code s'écrit caractère par
caractère, curseur compris, exactement comme dans la démo web (#wallCode).
Et ce n'est pas du faux code : c'est la source d'un vrai programme de LexOS,
lue sur le disque.

Ce que ça coûte, avant ce que ça fait
------------------------------------
Une vidéo en fond d'écran fait tourner un décodeur sans arrêt (voir
fond-video.py). Ici il n'y a pas de vidéo : le fond, la grille, les braises
et la vignette sont peints UNE fois dans une surface en mémoire, et chaque
salve de caractères ne redessine que la bande de lignes qu'elle touche.
Dix réveils par seconde pour repeindre quelques centaines de pixels : c'est
l'ordre de grandeur du curseur qui clignote dans un terminal.

Et comme pour la vidéo, sur batterie tout s'arrête : l'écriture se fige sur
son dernier caractère, plus une seule image n'est produite. Le garde-fou
n'est pas une option — il n'y a pas de réglage pour le désactiver.

La fenêtre
----------
Même recette que fond-video.py : une fenêtre à nous, déclarée fond d'écran
(_NET_WM_WINDOW_TYPE_DESKTOP), maintenue sous tout le reste, et surtout
TRANSPARENTE AUX CLICS (forme d'entrée vide) — le clic droit du bureau et
les icônes continuent de répondre à travers elle.

Ce qui n'a PAS pu être vérifié
------------------------------
Le rendu sur un vrai serveur X : la machine de construction n'a pas
d'affichage. La géométrie, le découpage du texte et les garde-fous, eux,
sont testés (LEXOS_FOND_CODE_TEST=1 dessine une image PNG sans serveur X).
Si la fenêtre se comporte mal sur ton matériel, « lexos wallpaper code off »
remet le fond fixe en place en une commande.
"""
import glob
import math
import os
import sys

#  --- Les couleurs d'accent, celles de lexos-theme-gen ------------------------
#  (accent bas, accent, accent haut) — le logo est peint dans ce dégradé
#  vertical, comme le « fire » de branding/wallpaper.svg.
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

#  Le code qui s'écrit : la source d'un vrai programme de LexOS. Le premier
#  lisible gagne — ils ne sont pas tous installés selon la saveur.
SOURCES = [
    "/usr/bin/lexos-settings",
    "/usr/lib/lexos/settings.py",
    "/usr/bin/lexos",
    "/usr/lib/lexos/fond-code.py",
]

CADENCE_MS = 100      # un réveil tous les dixièmes de seconde
PAR_SALVE = 3         # 3 caractères par réveil ≈ 30 par seconde, comme la démo
BATTERIE_MS = 20000   # on regarde l'alimentation toutes les 20 secondes


def hex_rgb(code):
    code = code.lstrip("#")
    return tuple(int(code[i:i + 2], 16) / 255 for i in (0, 2, 4))


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
    """« 1.0.2 — NOMAD », lu dans /etc/os-release plutôt que recopié ici."""
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


def source_code():
    """Le texte qui s'écrira. Les tabulations deviennent deux espaces :
    un fond d'écran n'a pas de taquet de tabulation."""
    choix = SOURCES
    perso = os.environ.get("LEXOS_FOND_CODE_SOURCE")
    if perso:
        choix = [perso] + list(SOURCES)
    for chemin in choix:
        try:
            with open(chemin, encoding="utf-8", errors="replace") as f:
                texte = f.read()
        except OSError:
            continue
        if texte.strip():
            return texte.replace("\t", "  ").replace("\r", "")
    return "#!/usr/bin/env bash\n# LexOS\n"


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
#  Le dessin — tout en cairo, indépendant de la fenêtre
# =============================================================================
class Scene:
    """Sait peindre le décor, une ligne de code, et la marque par-dessus."""

    def __init__(self, cairo_mod, largeur, hauteur):
        self.cairo = cairo_mod
        self.maj_taille(largeur, hauteur)

    def maj_taille(self, largeur, hauteur):
        self.w = max(320, int(largeur))
        self.h = max(240, int(hauteur))
        self.lo, self.ac, self.hi = accent_courant()

        self.pad_x = max(16, round(self.w * 0.016))
        self.pad_y = max(24, round(self.h * 0.043))
        self.police = max(11, round(self.h / 72))
        self.interligne = self.police * 1.7

        #  Quelle police ? « Fira Code » est celle du terminal et de la démo,
        #  mais si elle manque, fontconfig rend SILENCIEUSEMENT une police
        #  proportionnelle : le code cesse d'être aligné et le curseur se
        #  décale. On vérifie donc que le « i » et le « M » ont la même
        #  largeur — la définition même d'une police à chasse fixe — et on
        #  retombe sur « monospace » sinon.
        tampon = self.cairo.ImageSurface(self.cairo.FORMAT_ARGB32, 8, 8)
        ctx = self.cairo.Context(tampon)
        self.famille = "Fira Code"
        for essai in ("Fira Code", "DejaVu Sans Mono", "monospace"):
            ctx.select_font_face(essai, self.cairo.FONT_SLANT_NORMAL,
                                 self.cairo.FONT_WEIGHT_NORMAL)
            ctx.set_font_size(self.police)
            if abs(ctx.text_extents("i").x_advance
                   - ctx.text_extents("M").x_advance) < 0.01:
                self.famille = essai
                break
            self.famille = "monospace"
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(self.police)
        self.car_w = ctx.text_extents("M").x_advance or self.police * 0.6

        self.colonnes = max(20, int((self.w - 2 * self.pad_x) / self.car_w))
        self.lignes = max(4, int((self.h - self.pad_y - self.pad_x) / self.interligne))

        self.decor = self._decor()

    # --- Le décor : noir, grille, braises, vignette --------------------------
    def _decor(self):
        s = self.cairo.ImageSurface(self.cairo.FORMAT_ARGB32, self.w, self.h)
        c = self.cairo.Context(s)

        c.set_source_rgb(0, 0, 0)
        c.paint()

        #  Braises au centre, comme le radialGradient « ember » du SVG.
        g = self.cairo.RadialGradient(self.w * 0.5, self.h * 0.52, 0,
                                      self.w * 0.5, self.h * 0.52,
                                      max(self.w, self.h) * 0.55)
        g.add_color_stop_rgba(0.00, *hex_rgb("#FF8A1F"), 0.30)
        g.add_color_stop_rgba(0.38, *hex_rgb("#C4460D"), 0.13)
        g.add_color_stop_rgba(1.00, 0, 0, 0, 0)
        c.set_source(g)
        c.paint()

        #  Grille de 72 px, très discrète — la même que le fond fixe.
        c.set_source_rgba(*hex_rgb(self.ac), 0.045)
        c.set_line_width(1)
        x = 0
        while x <= self.w:
            c.move_to(x + 0.5, 0)
            c.line_to(x + 0.5, self.h)
            x += 72
        y = 0
        while y <= self.h:
            c.move_to(0, y + 0.5)
            c.line_to(self.w, y + 0.5)
            y += 72
        c.stroke()

        #  Vignette : les bords s'assombrissent, le centre reste net.
        v = self.cairo.RadialGradient(self.w / 2, self.h / 2, 0,
                                      self.w / 2, self.h / 2,
                                      math.hypot(self.w, self.h) * 0.5)
        v.add_color_stop_rgba(0.55, 0, 0, 0, 0)
        v.add_color_stop_rgba(1.00, 0, 0, 0, 0.65)
        c.set_source(v)
        c.paint()
        return s

    # --- Le code qui s'écrit -------------------------------------------------
    def prepare_texte(self, ctx):
        ctx.select_font_face(self.famille, self.cairo.FONT_SLANT_NORMAL,
                             self.cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(self.police)
        ctx.set_source_rgba(*hex_rgb("#B8B8BC"), 0.40)

    def dessine_ligne(self, ctx, numero, texte):
        """Écrit une ligne du code à sa place. Le fond de la ligne est
        d'abord remis au décor : c'est ce qui efface le curseur précédent."""
        y_haut = self.pad_y + numero * self.interligne
        ctx.save()
        ctx.rectangle(0, y_haut - self.interligne * 0.25,
                      self.w, self.interligne * 1.2)
        ctx.clip()
        ctx.set_source_surface(self.decor, 0, 0)
        ctx.paint()
        self.prepare_texte(ctx)
        ctx.move_to(self.pad_x, y_haut + self.police)
        ctx.show_text(texte)
        ctx.restore()

    def zone_ligne(self, numero):
        """Le rectangle à redessiner pour une ligne (x, y, w, h)."""
        y_haut = self.pad_y + numero * self.interligne
        return (0, int(y_haut - self.interligne * 0.25),
                self.w, int(self.interligne * 1.2) + 2)

    # --- La marque, toujours par-dessus le code ------------------------------
    def dessine_marque(self, ctx):
        cx, cy = self.w / 2, self.h * 0.555

        #  Voile sombre : sans lui, le code traverse le logo et plus rien
        #  n'est lisible. C'est l'ellipse floutée du fond fixe.
        voile = self.cairo.RadialGradient(cx, cy, 0, cx, cy, self.w * 0.40)
        voile.add_color_stop_rgba(0.00, 0, 0, 0, 0.92)
        voile.add_color_stop_rgba(0.70, 0, 0, 0, 0.80)
        voile.add_color_stop_rgba(1.00, 0, 0, 0, 0.0)
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(1.0, 0.52)          # une ellipse, pas un disque
        ctx.translate(-cx, -cy)
        ctx.set_source(voile)
        ctx.paint()
        ctx.restore()

        #  Halo d'accent derrière le logo.
        halo = self.cairo.RadialGradient(cx, cy * 0.96, 0, cx, cy * 0.96, self.w * 0.23)
        halo.add_color_stop_rgba(0.0, *hex_rgb(self.ac), 0.13)
        halo.add_color_stop_rgba(1.0, *hex_rgb(self.ac), 0.0)
        ctx.save()
        ctx.translate(cx, cy * 0.96)
        ctx.scale(1.0, 0.36)
        ctx.translate(-cx, -cy * 0.96)
        ctx.set_source(halo)
        ctx.paint()
        ctx.restore()

        #  Le logo ASCII, en gras, dans le dégradé de feu. Les proportions
        #  sont celles de branding/wallpaper.svg, ramenées à la hauteur de
        #  l'écran : corps 64/1080, interligne 74, trait à +344, la ligne
        #  TI · LEX · AL à +400 et la version à +452 sous la première ligne.
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

        #  Le trait, puis TI · LEX · AL, puis la version.
        y_trait = y0 + taille * 5.375
        trait = self.cairo.LinearGradient(cx - self.w * 0.19, 0, cx + self.w * 0.19, 0)
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
        self._texte_espace(ctx, version_systeme(),
                           cx, y0 + taille * 7.06, max(9, self.h / 56.8),
                           self.h / 216)

    def _texte_espace(self, ctx, texte, cx, y, taille, espace):
        """Écrit un texte centré, lettre à lettre, avec de l'air entre les
        lettres — le « letter-spacing » du fond fixe, que cairo n'a pas."""
        ctx.set_font_size(taille)
        large = sum(ctx.text_extents(c).x_advance + espace for c in texte) - espace
        x = cx - large / 2
        for c in texte:
            ctx.move_to(x, y)
            ctx.show_text(c)
            x += ctx.text_extents(c).x_advance + espace


# =============================================================================
#  L'écrivain : découpe la source en lignes d'écran et avance caractère
#  par caractère. Séparé du dessin pour être testable sans serveur X.
# =============================================================================
class Ecrivain:
    def __init__(self, texte, colonnes, lignes):
        self.texte = texte
        self.colonnes = colonnes
        self.lignes = lignes
        self.recommence()

    def recommence(self):
        self.pos = 0
        self.ecran = [""]          # les lignes déjà écrites, à l'écran

    def avance(self, combien):
        """Ajoute « combien » caractères. Renvoie les numéros de lignes
        touchées, et True s'il faut tout redessiner (retour au début)."""
        touchees = set()
        for _ in range(combien):
            if self.pos >= len(self.texte):
                self.recommence()
                return set(), True
            c = self.texte[self.pos]
            self.pos += 1
            if c == "\n":
                self.ecran.append("")
            else:
                #  Le repli à la colonne : une ligne trop longue continue
                #  sur la suivante, comme le fait le navigateur dans la démo.
                if len(self.ecran[-1]) >= self.colonnes:
                    self.ecran.append("")
                self.ecran[-1] += c
            touchees.add(len(self.ecran) - 1)
            if len(self.ecran) > self.lignes:
                #  Écran plein : on repart d'en haut plutôt que d'écrire
                #  hors de vue. Même choix que la démo web.
                self.recommence()
                return set(), True
        return touchees, False

    def lignes_visibles(self):
        """Les lignes à afficher, curseur compris sur la dernière."""
        out = list(self.ecran)
        out[-1] = out[-1] + "▌"
        return out


# =============================================================================
#  Mode test : dessine une image, sans serveur X ni fenêtre.
# =============================================================================
def mode_test(sortie, largeur=1920, hauteur=1080, caracteres=2600):
    import cairo
    scene = Scene(cairo, largeur, hauteur)
    ecrivain = Ecrivain(source_code(), scene.colonnes, scene.lignes)
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, largeur, hauteur)
    ctx = cairo.Context(surface)
    ctx.set_source_surface(scene.decor, 0, 0)
    ctx.paint()
    #  On avance par petites salves, comme la vraie animation, et on
    #  s'arrête juste avant le retour au début : sinon l'image de test
    #  montrerait un écran vide.
    for _ in range(max(1, caracteres // PAR_SALVE)):
        avant = (list(ecrivain.ecran), ecrivain.pos)
        _, recommence = ecrivain.avance(PAR_SALVE)
        if recommence:
            ecrivain.ecran, ecrivain.pos = avant
            break
    for i, ligne in enumerate(ecrivain.lignes_visibles()):
        scene.dessine_ligne(ctx, i, ligne)
    scene.dessine_marque(ctx)
    surface.write_to_png(sortie)
    print(sortie)


# =============================================================================
#  La fenêtre de fond d'écran
# =============================================================================
def main():
    if os.environ.get("LEXOS_FOND_CODE_TEST"):
        mode_test(os.environ.get("LEXOS_FOND_CODE_TEST"))
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

            self.scene = Scene(cairo, self.larg, self.haut)
            self.ecrivain = Ecrivain(source_code(),
                                     self.scene.colonnes, self.scene.lignes)
            self.tampon = None
            self.timer = None

            self.connect("draw", self.on_draw)
            self.connect("destroy", Gtk.main_quit)
            self.show_all()

            fen = self.get_window()
            if fen is not None:
                fen.lower()
                try:
                    #  Forme d'entrée vide : tous les clics traversent la
                    #  fenêtre. Le bureau (icônes, clic droit) répond comme
                    #  si elle n'existait pas.
                    fen.input_shape_combine_region(cairo.Region(), 0, 0)
                except Exception:
                    pass

            self.reconstruit_tampon()
            self.reprend()
            GLib.timeout_add(BATTERIE_MS, self.surveille_batterie)

        # --- Le tampon : décor + code déjà écrit ---------------------------
        def reconstruit_tampon(self):
            self.tampon = cairo.ImageSurface(cairo.FORMAT_ARGB32,
                                             self.larg, self.haut)
            ctx = cairo.Context(self.tampon)
            ctx.set_source_surface(self.scene.decor, 0, 0)
            ctx.paint()
            for i, ligne in enumerate(self.ecrivain.lignes_visibles()):
                self.scene.dessine_ligne(ctx, i, ligne)
            self.queue_draw()

        def on_draw(self, _widget, ctx):
            ctx.set_source_surface(self.tampon, 0, 0)
            ctx.paint()
            self.scene.dessine_marque(ctx)
            return False

        # --- L'écriture ------------------------------------------------------
        def tape(self):
            #  La ligne où était le curseur AVANT la salve : si l'écriture
            #  vient de passer à la ligne, c'est la seule façon d'aller
            #  effacer le curseur qu'elle y a laissé.
            avant = len(self.ecrivain.ecran) - 1
            touchees, recommence = self.ecrivain.avance(PAR_SALVE)
            if recommence:
                self.reconstruit_tampon()
                return True
            ctx = cairo.Context(self.tampon)
            visibles = self.ecrivain.lignes_visibles()
            touchees.add(avant)
            touchees.add(max(0, len(visibles) - 1))
            for i in sorted(touchees):
                if i < len(visibles):
                    self.scene.dessine_ligne(ctx, i, visibles[i])
                    self.queue_draw_area(*self.scene.zone_ligne(i))
            return True

        # --- Batterie --------------------------------------------------------
        def reprend(self):
            if self.timer is None:
                self.timer = GLib.timeout_add(CADENCE_MS, self.tape)

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

    Fond()
    Gtk.main()


if __name__ == "__main__":
    main()
