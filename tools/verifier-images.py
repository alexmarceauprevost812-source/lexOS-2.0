#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verifier-images.py — pourquoi les images de thème cassent.
"""

import argparse
import hashlib
import os
import re
import struct
import subprocess
import sys
import zlib
import xml.etree.ElementTree as ET

VERSION = "1.0"

if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
    VERT, ORANGE, ROUGE, GRIS, GRAS, ZERO = (
        "\033[32m", "\033[38;5;208m", "\033[31m", "\033[90m", "\033[1m", "\033[0m")
else:
    VERT = ORANGE = ROUGE = GRIS = GRAS = ZERO = ""

RACINES = [
    "config/bootloaders",
    "config/includes.binary/boot/grub",
    "config/includes.chroot/usr/share/grub",
    "config/includes.chroot/usr/share/plymouth",
    "config/includes.chroot/usr/share/icons",
    "config/includes.chroot/usr/share/pixmaps",
    "config/includes.chroot/usr/share/backgrounds",
    "config/includes.chroot/usr/share/images",
    "config/includes.chroot/usr/share/wallpapers",
    "config/includes.chroot/etc/skel",
    "config/includes.chroot/usr/share/lexos",
    "config/includes.chroot/usr/share/desktop-base",
    "branding",
]
SAUTER = {".git", "chroot", "binary", "cache", ".build", "local",
          "node_modules", ".venv", "__pycache__"}
EXTENSIONS = (".png", ".jpg", ".jpeg", ".svg", ".svg.in", ".gif",
              ".bmp", ".tga", ".webp", ".ico", ".xpm")

JUMEAUX = ("config/includes.binary/boot/grub/themes",
           "config/includes.chroot/usr/share/grub/themes")

DEBUT_LFS = b"version https://git-lfs.github.com/spec/v1"

DOSSIERS_DEBIAN = (
    "usr/share/images/desktop-base",
    "usr/share/desktop-base",
    "usr/share/backgrounds/xfce",
    "usr/share/xfce4/backdrops",
    "usr/share/plymouth/themes/spinner",
    "usr/share/plymouth/themes/bgrt",
    "usr/share/plymouth/themes/details",
    "usr/share/lightdm",
    "etc/lightdm",
    "usr/share/icons/Adwaita",
    "usr/share/icons/Papirus",
)

EXT_REGLAGES = (".xml", ".conf", ".ini", ".desktop", ".css", ".rc",
                ".theme", ".plymouth", ".cfg")
MOTIF_CHEMIN_IMAGE = re.compile(
    r"(/(?:usr|etc|opt)/[^\s\"'<>]+\.(?:png|jpg|jpeg|svg|gif|webp))")

PROBLEMES = []


def signaler(gravite, chemin, message):
    PROBLEMES.append((gravite, chemin, message))


SIGNATURE_PNG = b"\x89PNG\r\n\x1a\n"


def inspecter_png(chemin, octets):
    if not octets:
        raise ValueError("fichier vide (0 octet)")
    if not octets.startswith(SIGNATURE_PNG):
        raise ValueError("ce n'est pas un PNG (signature absente) "
                         "— extension .png mais autre contenu")
    i = 8
    ihdr = None
    idat = bytearray()
    vu_iend = False
    while i < len(octets):
        if i + 8 > len(octets):
            raise ValueError("tronqué : il manque l'en-tête du dernier bloc")
        (taille,) = struct.unpack(">I", octets[i:i + 4])
        typ = octets[i + 4:i + 8]
        fin = i + 12 + taille
        if fin > len(octets):
            manque = fin - len(octets)
            raise ValueError(
                "tronqué : le bloc %s annonce %d octets, il en manque %d "
                "— écriture interrompue" % (typ.decode("latin-1"), taille, manque))
        charge = octets[i + 8:i + 8 + taille]
        (crc,) = struct.unpack(">I", octets[i + 8 + taille:fin])
        if crc != (zlib.crc32(typ + charge) & 0xFFFFFFFF):
            raise ValueError("bloc %s corrompu (somme de contrôle fausse) "
                             "— fichier abîmé après coup"
                             % typ.decode("latin-1"))
        if typ == b"IHDR":
            ihdr = charge
        elif typ == b"IDAT":
            idat += charge
        elif typ == b"IEND":
            vu_iend = True
            i = fin
            break
        i = fin

    if ihdr is None or len(ihdr) < 13:
        raise ValueError("en-tête IHDR absent ou incomplet")
    if not vu_iend:
        raise ValueError("bloc de fin IEND absent — fichier coupé avant la fin")
    try:
        zlib.decompress(bytes(idat))
    except zlib.error as e:
        raise ValueError("données d'image illisibles (%s)" % e)

    largeur, hauteur, profondeur, couleur, _comp, _filtre, entrelace = \
        struct.unpack(">IIBBBBB", ihdr[:13])
    reste = len(octets) - i
    return {
        "largeur": largeur, "hauteur": hauteur, "profondeur": profondeur,
        "couleur": couleur, "entrelace": entrelace, "apres_iend": reste,
    }


def regles_grub(chemin, info):
    """Contraintes du lecteur PNG de GRUB — relevées DANS son code source.

    ═══ CE CONTRÔLE DISAIT FAUX, ET IL ACCUSAIT LE MENU DE DÉMARRAGE ═══
    La première écriture refusait toute profondeur hors 8 et 16 bits. Elle
    déclarait donc « CASSÉ » quatre fichiers du thème GRUB de LexOS —
    select_ne.png et select_se.png, dans les deux exemplaires du thème.

    Vérifié dans grub-core/video/readers/png.c, la condition de REJET est :

        if ((color_bits != 8) && (color_bits != 16)
            && (color_bits != 4 || !data->is_palette))

    Autrement dit : 4 bits EST accepté quand l'image est en palette. Or ces
    quatre fichiers sont exactement ça — 4 bits, palette. Quatre fichiers de
    démarrage auraient été « réparés » pour rien, sur la foi d'un contrôle.

    Un contrôle qui accuse à tort coûte plus cher qu'un contrôle absent :
    celui-là envoyait retoucher le menu qu'on venait justement de corriger.
    """
    if info["entrelace"]:
        signaler(2, chemin, "PNG entrelacé (Adam7) : GRUB refuse de le lire, "
                            "l'image sera tout simplement absente du menu "
                            "— réexporter sans entrelacement")
    prof, coul = info["profondeur"], info["couleur"]
    palette = (coul == 3)
    if prof not in (8, 16) and not (prof == 4 and palette):
        signaler(2, chemin, "%d bits par canal%s : GRUB n'accepte que 8, 16, "
                            "ou 4 en palette — réexporter en RVBA 8 bits"
                 % (prof, " (palette)" if palette else ""))
    elif prof == 16 and coul == 3:
        signaler(2, chemin, "palette en 16 bits : GRUB refuse cette combinaison "
                            "— réexporter en RVBA 8 bits")
    elif prof == 16:
        signaler(1, chemin, "PNG 16 bits par canal : deux fois plus lourd à "
                            "charger au démarrage, 8 bits suffit")


TRANCHES = ("c", "n", "s", "e", "w", "nw", "ne", "sw", "se")


def theme_grub_complet(racine):
    for base in JUMEAUX:
        base = os.path.join(racine, base)
        if not os.path.isdir(base):
            continue
        for dossier, _s, fichiers in os.walk(base):
            if "theme.txt" not in fichiers:
                continue
            chemin = os.path.join(dossier, "theme.txt")
            try:
                texte = open(chemin, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for nom in set(re.findall(r'"([^"\n]+\.(?:png|jpg|jpeg|tga))"', texte)):
                cibles = ([nom.replace("*", t) for t in TRANCHES]
                          if "*" in nom else [nom])
                manquants = [c for c in cibles
                             if not os.path.exists(os.path.join(dossier, c))]
                if manquants:
                    signaler(2, relatif(racine, chemin),
                             "nomme %s mais le(s) fichier(s) %s manque(nt) : "
                             "GRUB abandonne le thème et retombe sur celui de Debian"
                             % (nom, ", ".join(sorted(manquants)[:4])))


def plymouth_complet(racine):
    base = os.path.join(racine, "config/includes.chroot/usr/share/plymouth/themes")
    if not os.path.isdir(base):
        return
    for dossier, _s, fichiers in os.walk(base):
        for f in fichiers:
            if not f.endswith(".script"):
                continue
            chemin = os.path.join(dossier, f)
            try:
                texte = open(chemin, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for nom in sorted(set(re.findall(r'Image\s*\(\s*"([^"]+)"', texte))):
                if not os.path.exists(os.path.join(dossier, nom)):
                    signaler(2, relatif(racine, chemin),
                             'appelle Image("%s") et le fichier est absent : '
                             "le thème plante et le démarrage se fait sur un "
                             "écran noir" % nom)


def inspecter_svg(chemin, rel, octets):
    texte = octets.decode("utf-8", errors="replace")
    if not octets.strip():
        raise ValueError("fichier vide (0 octet)")
    try:
        racine = ET.fromstring(texte)
    except ET.ParseError as e:
        raise ValueError("XML mal formé, ligne %d : %s"
                         % (e.position[0], e.msg.split(":")[0]))
    if not racine.tag.endswith("svg"):
        raise ValueError("la balise racine n'est pas <svg> mais <%s>" % racine.tag)

    if not racine.get("viewBox") and not (racine.get("width") and racine.get("height")):
        signaler(1, rel, "ni viewBox ni width/height : le rendu en PNG "
                            "sortira à une taille imprévisible")

    dossier = os.path.dirname(chemin)
    for el in racine.iter():
        if not el.tag.endswith("image"):
            continue
        lien = (el.get("href")
                or el.get("{http://www.w3.org/1999/xlink}href") or "")
        if not lien or lien.startswith("data:"):
            continue
        vise = lien if os.path.isabs(lien) else os.path.join(dossier, lien)
        if not os.path.exists(vise):
            signaler(2, rel, "renvoie à une image absente : %s "
                                "(Inkscape a lié le fichier au lieu de l'incorporer)"
                     % lien)
        else:
            signaler(1, rel, "renvoie à un fichier extérieur : %s "
                                "(à incorporer, sinon le rendu dépend du dossier)"
                     % lien)
    return {"racine": racine.tag}


def est_image(nom):
    bas = nom.lower()
    return any(bas.endswith(e) for e in EXTENSIONS)


def recolter(racine):
    depart = [os.path.join(racine, d) for d in RACINES
              if os.path.isdir(os.path.join(racine, d))]
    if not depart:
        depart = [racine]
    trouves = []
    for base in depart:
        for dossier, sous, fichiers in os.walk(base):
            sous[:] = [s for s in sous if s not in SAUTER]
            for f in fichiers:
                if est_image(f):
                    trouves.append(os.path.join(dossier, f))
    return sorted(set(trouves))


def relatif(racine, chemin):
    try:
        return os.path.relpath(chemin, racine)
    except ValueError:
        return chemin


def piege_splash(racine):
    for dossier, _sous, fichiers in os.walk(os.path.join(racine, "config/bootloaders")):
        if "splash.svg" in fichiers:
            signaler(2, relatif(racine, os.path.join(dossier, "splash.svg")),
                     "live-build écrase ce nom par le modèle Debian puis l'efface "
                     "— le fichier doit s'appeler splash.svg.in")
        if "splash.svg.in" not in fichiers and "splash.png" in fichiers:
            signaler(1, relatif(racine, os.path.join(dossier, "splash.png")),
                     "PNG seul, sans splash.svg.in : live-build le remplacera "
                     "par le sien à la prochaine construction")


def jumeaux_divergents(racine):
    a, b = [os.path.join(racine, j) for j in JUMEAUX]
    if not (os.path.isdir(a) and os.path.isdir(b)):
        return
    def carte(base):
        d = {}
        for dossier, _s, fichiers in os.walk(base):
            for f in fichiers:
                p = os.path.join(dossier, f)
                d[os.path.relpath(p, base)] = p
        return d
    ca, cb = carte(a), carte(b)
    for nom in sorted(set(ca) | set(cb)):
        if nom not in ca:
            signaler(1, relatif(racine, cb[nom]),
                     "présent côté disque dur, absent côté ISO — les deux menus "
                     "ne se ressembleront pas")
        elif nom not in cb:
            signaler(1, relatif(racine, ca[nom]),
                     "présent côté ISO, absent côté disque dur — les deux menus "
                     "ne se ressembleront pas")
        else:
            ha = hashlib.sha256(open(ca[nom], "rb").read()).hexdigest()
            hb = hashlib.sha256(open(cb[nom], "rb").read()).hexdigest()
            if ha != hb:
                signaler(1, relatif(racine, ca[nom]),
                         "diffère de son jumeau %s — une seule des deux copies "
                         "a été corrigée" % relatif(racine, cb[nom]))


def hors_de_git(racine, images):
    try:
        suivis = subprocess.run(
            ["git", "-C", racine, "ls-files", "-z"],
            capture_output=True, timeout=30).stdout.split(b"\0")
    except (OSError, subprocess.SubprocessError):
        return
    if not suivis or suivis == [b""]:
        return
    connus = {s.decode("utf-8", "replace") for s in suivis if s}
    absentes = [relatif(racine, i) for i in images if relatif(racine, i) not in connus]
    if not absentes:
        return
    ignorees = set()
    try:
        rep = subprocess.run(["git", "-C", racine, "check-ignore", "--stdin"],
                             input="\n".join(absentes).encode(),
                             capture_output=True, timeout=30)
        ignorees = {l for l in rep.stdout.decode("utf-8", "replace").splitlines() if l}
    except (OSError, subprocess.SubprocessError):
        pass
    for rel in sorted(ignorees):
        signaler(2, rel, "exclue par .gitignore : git ne la gardera jamais, "
                         "elle disparaît à chaque clone et la construction "
                         "repart sans elle")
    autres = [a for a in absentes if a not in ignorees]
    if autres:
        apercu = ", ".join(sorted(autres)[:3]) + (" …" if len(autres) > 3 else "")
        signaler(1, "git",
                 "%d image(s) pas encore ajoutée(s) à git (%s) : un clone frais "
                 "ne les aura pas" % (len(autres), apercu))


MOTIF_CONVERT = re.compile(
    r"\b(?:convert|magick|mogrify|rsvg-convert|inkscape|optipng|pngcrush)\b[^\n;|&]*")


def commandes_dangereuses(racine):
    for dossier, sous, fichiers in os.walk(racine):
        sous[:] = [s for s in sous if s not in SAUTER]
        for f in fichiers:
            if not (f.endswith((".sh", ".py", ".bash")) or ".hook." in f
                    or f in ("build.sh", "Makefile")):
                continue
            chemin = os.path.join(dossier, f)
            #  ═══ UN VÉRIFICATEUR CITE CE QU'IL TRAQUE ═══
            #  Ce fichier-ci contient les mots « mogrify », « convert »… dans
            #  son propre motif de recherche et dans ses messages. Il se
            #  signalait donc lui-même, deux fois. Un contrôle qui se
            #  déclenche sur sa propre justification apprend à ignorer les
            #  rouges — c'est le piège que ce dépôt s'est déjà pris sept fois.
            #  On compare les chemins réels : aucune exemption par nom, rien
            #  d'autre ne peut passer au travers.
            if os.path.abspath(chemin) == os.path.abspath(__file__):
                continue
            try:
                lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
            except OSError:
                continue
            for n, ligne in enumerate(lignes, 1):
                nue = ligne.strip()
                if nue.startswith("#"):
                    continue
                for cmd in MOTIF_CONVERT.findall(ligne):
                    mots = [m.strip("\"'") for m in cmd.split()]
                    mots = [m for m in mots
                            if any(m.lower().endswith(e) for e in
                                   (".png", ".jpg", ".jpeg", ".svg", ".gif", ".webp"))]
                    if len(mots) >= 2 and mots[0] == mots[-1]:
                        signaler(2, "%s:%d" % (relatif(racine, chemin), n),
                                 "écrit dans le fichier qu'elle lit (%s) : si la "
                                 "commande échoue ou est interrompue, l'image est "
                                 "perdue — passer par un fichier temporaire"
                                 % mots[0])
                    elif "mogrify" in cmd and "-path" not in cmd:
                        signaler(1, "%s:%d" % (relatif(racine, chemin), n),
                                 "mogrify modifie sur place, sans copie de secours")
                if re.search(r"\bsed\s+-i\b", ligne) or re.search(r"\biconv\b", ligne):
                    #  ═══ ON REGARDE LES FICHIERS, PAS L'EXPRESSION ═══
                    #  La première écriture cherchait un « * » n'importe où sur
                    #  la ligne. Elle signalait donc QUINZE lignes parfaitement
                    #  saines, dont celle-ci :
                    #      sed -i -e "s|^icon-theme-name=.*|…|" "$CONNEXION_CONF"
                    #  Le « * » trouvé était celui du « .* » de la SUBSTITUTION,
                    #  pas un motif de fichiers — et le fichier visé est unique
                    #  et entre guillemets. Quinze faux signalements sur seize,
                    #  c'est un outil qu'on apprend à ne plus lire.
                    #  On retire donc d'abord tout ce qui est entre guillemets :
                    #  ce qui reste, ce sont les arguments nus, là où un vrai
                    #  glob se trouve.
                    #  ET LE RETRAIT DOIT TENIR COMPTE DES « \" » ÉCHAPPÉS :
                    #  la première version s'arrêtait au premier guillemet
                    #  échappé et laissait la fin de l'expression sed à nu.
                    #  Deux lignes du hook 0600 restaient signalées à tort
                    #  pour cette seule raison.
                    hors_guillemets = re.sub(
                        r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", " ", ligne)
                    if re.search(r"\*(?!\.[A-Za-z])|\bfind\b[^\n]*-type\s+f(?![^\n]*-name)",
                                 hors_guillemets):
                        signaler(1, "%s:%d" % (relatif(racine, chemin), n),
                                 "réécrit un lot de fichiers sans filtrer les "
                                 "extensions : un PNG pris dans le lot est détruit")


def gitattributes(racine):
    chemin = os.path.join(racine, ".gitattributes")
    if not os.path.exists(os.path.join(racine, ".git")):
        return
    if not os.path.exists(chemin):
        signaler(1, ".gitattributes",
                 "absent : rien ne dit à git que les PNG sont binaires "
                 "(un outil de fusion ou une fin de ligne CRLF peut les abîmer)")


def pointeur_lfs(octets):
    return octets.startswith(DEBUT_LFS)


def lien_devenu_texte(chemin, octets):
    if len(octets) > 300 or b"\0" in octets or not octets.strip():
        return None
    try:
        texte = octets.decode("utf-8").strip()
    except UnicodeDecodeError:
        return None
    if "\n" in texte or " " in texte.strip():
        return None
    if "/" in texte and texte.lower().endswith(
            (".png", ".jpg", ".jpeg", ".svg", ".gif", ".webp")):
        return texte
    return None


def attributs_texte(racine):
    chemin = os.path.join(racine, ".gitattributes")
    if not os.path.exists(chemin):
        return
    for n, ligne in enumerate(
            open(chemin, encoding="utf-8", errors="replace").read().splitlines(), 1):
        nue = ligne.strip()
        if not nue or nue.startswith("#"):
            continue
        morceaux = nue.split()
        motif, attrs = morceaux[0], morceaux[1:]
        vise_image = motif == "*" or any(
            motif.lower().endswith(e) for e in
            (".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico"))
        if not vise_image:
            continue
        if any(a == "text" or a.startswith("text=") or a.startswith("eol=")
               for a in attrs) and not any(
                   a in ("-text", "binary") for a in attrs):
            signaler(2, ".gitattributes:%d" % n,
                     "« %s » est déclaré comme du texte : git réécrit ses fins "
                     "de ligne à chaque clone et le fichier arrive corrompu "
                     "— mettre « %s binary » à la place" % (motif, motif))


def reglages_dans_le_vide(racine):
    for arbre in ("config/includes.chroot", "config/includes.binary"):
        base = os.path.join(racine, arbre)
        if not os.path.isdir(base):
            continue
        for dossier, sous, fichiers in os.walk(base):
            sous[:] = [x for x in sous if x not in SAUTER]
            for f in fichiers:
                if not f.lower().endswith(EXT_REGLAGES):
                    continue
                chemin = os.path.join(dossier, f)
                try:
                    if os.path.getsize(chemin) > 512 * 1024:
                        continue
                    texte = open(chemin, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for vise in sorted(set(MOTIF_CHEMIN_IMAGE.findall(texte))):
                    livre = os.path.join(base, vise.lstrip("/"))
                    if os.path.exists(livre):
                        continue
                    rel = relatif(racine, chemin)
                    if "lexos" in vise.lower():
                        signaler(2, rel,
                                 "nomme %s : ce chemin est à LexOS et aucun "
                                 "fichier n'est livré là — fond d'écran vide "
                                 "au premier démarrage" % vise)
                    else:
                        signaler(1, rel,
                                 "nomme %s : rien n'est livré là, ça dépend "
                                 "d'un paquet Debian qui peut changer de "
                                 "contenu à une mise à jour" % vise)


def territoire_debian(racine, images):
    base = os.path.join(racine, "config/includes.chroot")
    if not os.path.isdir(base):
        return
    vus = set()
    for img in images:
        rel = os.path.relpath(img, base) if img.startswith(base + os.sep) else None
        if not rel:
            continue
        for d in DOSSIERS_DEBIAN:
            if rel.replace("\\", "/").startswith(d + "/") and d not in vus:
                vus.add(d)
                signaler(1, relatif(racine, os.path.join(base, d)),
                         "dossier d'un paquet Debian : apt y remet ses propres "
                         "fichiers à la prochaine mise à jour. Livrer dans "
                         "/usr/share/backgrounds/lexos/ et pointer dessus "
                         "(update-alternatives pour desktop-base)")


def main():
    ap = argparse.ArgumentParser(
        description="Vérifie les images de thème du dépôt LexOS.")
    ap.add_argument("--racine", default=".", help="racine du dépôt (défaut : .)")
    ap.add_argument("--tout", action="store_true",
                    help="montre aussi les fichiers sains")
    ap.add_argument("--version", action="version", version="verifier-images " + VERSION)
    args = ap.parse_args()

    racine = os.path.abspath(args.racine)
    images = recolter(racine)
    if not images:
        print("%sAucune image trouvée sous %s%s" % (ROUGE, racine, ZERO))
        return 1

    sains = []
    for chemin in images:
        rel = relatif(racine, chemin)
        if os.path.islink(chemin) and not os.path.exists(chemin):
            signaler(2, rel, "lien symbolique cassé : sa cible (%s) n'existe pas"
                     % os.readlink(chemin))
            continue
        try:
            octets = open(chemin, "rb").read()
        except OSError as e:
            signaler(2, rel, "illisible : %s" % e)
            continue
        bas = chemin.lower()
        if pointeur_lfs(octets):
            signaler(2, rel, "ce n'est pas une image mais un pointeur Git LFS : "
                             "le clone n'a jamais récupéré le vrai fichier "
                             "(git lfs install puis git lfs pull)")
            continue
        cible = lien_devenu_texte(chemin, octets) if not os.path.islink(chemin) else None
        if cible:
            signaler(2, rel, "contient un chemin (%s) au lieu d'une image : le "
                             "lien symbolique a été transformé en fichier texte "
                             "à la copie ou au clone" % cible)
            continue
        try:
            if bas.endswith(".png"):
                info = inspecter_png(chemin, octets)
                if info["apres_iend"] > 0:
                    signaler(1, rel, "%d octets traînent après la fin du PNG "
                                     "(concaténation accidentelle)" % info["apres_iend"])
                if "grub/themes/" in chemin.replace("\\", "/"):
                    regles_grub(rel, info)
                sains.append((rel, "PNG %dx%d, %d bits, type %d"
                              % (info["largeur"], info["hauteur"],
                                 info["profondeur"], info["couleur"])))
            elif bas.endswith(".svg") or bas.endswith(".svg.in"):
                inspecter_svg(chemin, rel, octets)
                sains.append((rel, "SVG bien formé"))
            else:
                if not octets:
                    raise ValueError("fichier vide (0 octet)")
                sains.append((rel, "%d octets" % len(octets)))
        except ValueError as e:
            signaler(2, rel, str(e))

    piege_splash(racine)
    theme_grub_complet(racine)
    plymouth_complet(racine)
    jumeaux_divergents(racine)
    hors_de_git(racine, images)
    commandes_dangereuses(racine)
    gitattributes(racine)
    attributs_texte(racine)
    reglages_dans_le_vide(racine)
    territoire_debian(racine, images)

    casses = [p for p in PROBLEMES if p[0] == 2]
    surveiller = [p for p in PROBLEMES if p[0] == 1]

    print("%s%d images examinées sous %s%s\n"
          % (GRAS, len(images), relatif(os.getcwd(), racine) or ".", ZERO))

    if casses:
        print("%s%sCASSÉ — à réparer avant la prochaine construction%s"
              % (GRAS, ROUGE, ZERO))
        for _g, chemin, msg in casses:
            print("  %s✗%s %s\n      %s%s%s" % (ROUGE, ZERO, chemin, GRIS, msg, ZERO))
        print()

    if surveiller:
        print("%s%sÀ SURVEILLER%s" % (GRAS, ORANGE, ZERO))
        for _g, chemin, msg in surveiller:
            print("  %s⚠%s %s\n      %s%s%s" % (ORANGE, ZERO, chemin, GRIS, msg, ZERO))
        print()

    if args.tout:
        print("%sSAINS%s" % (GRAS, ZERO))
        mauvais = {p[1] for p in PROBLEMES}
        for rel, quoi in sains:
            if rel not in mauvais:
                print("  %s✓%s %s  %s%s%s" % (VERT, ZERO, rel, GRIS, quoi, ZERO))
        print()

    if not PROBLEMES:
        print("%s✓ Rien à signaler : les %d images sont saines.%s"
              % (VERT, len(images), ZERO))
    else:
        print("%d cassée(s), %d à surveiller." % (len(casses), len(surveiller)))
    return 1 if casses else 0


if __name__ == "__main__":
    sys.exit(main())
