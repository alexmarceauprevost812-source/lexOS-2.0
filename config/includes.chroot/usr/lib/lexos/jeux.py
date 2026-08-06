#!/usr/bin/env python3
"""
LexOS — Bibliothèque de jeux : tous les jeux de la machine, au même endroit.

POURQUOI CETTE APPLICATION EXISTE

Steam a sa liste. Lutris a la sienne. RetroArch garde ses ROMs dans ses
propres fichiers. Les jeux installés par Debian ne sont que des lanceurs
perdus au milieu du menu. Résultat : sur un système « pour jouer », il n'y
avait AUCUN endroit où voir ses jeux ensemble. C'est ce trou que cette
application bouche.

CE QU'ELLE FAIT

Elle va lire, sans rien installer ni modifier :
  · Steam    — les fichiers appmanifest_*.acf de chaque bibliothèque
  · Lutris   — sa base pga.db (lecture seule, en mode immutable)
  · RetroArch— ses listes de lecture .lpl (JSON)
  · Le menu  — les lanceurs .desktop rangés dans la catégorie « Game »
               (c'est là qu'arrivent les jeux Debian ET les jeux Flatpak)

Puis elle réunit tout, enlève les doublons, et rend une liste triée.

PRINCIPE DE PRUDENCE

Chaque source est isolée : si Lutris n'est pas installé, si un fichier est
corrompu, si une version future change son format — la source concernée rend
une liste vide et les AUTRES continuent. Une bibliothèque qui affiche trois
sources sur quatre reste utile ; une qui plante n'affiche rien.

Ce fichier ne lance rien tout seul : il DÉCRIT comment lancer chaque jeu
(une liste argv), et c'est l'appelant qui décide. Il s'utilise aussi seul :

    python3 jeux.py --json      la liste, en JSON
    python3 jeux.py --liste     la liste, lisible au terminal
"""
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))


# =============================================================================
#  Outils communs
# =============================================================================

def _texte(chemin, limite=4_000_000):
    """Lit un fichier texte sans jamais lever d'exception ni avaler la RAM."""
    try:
        if chemin.stat().st_size > limite:
            return ""
        return chemin.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _dossiers_donnees():
    """Les dossiers où les .desktop peuvent vivre, système et utilisateur,
    Flatpak et Snap compris. XDG_DATA_DIRS est respecté quand il est posé."""
    dirs = []
    xdg = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    dirs += [Path(p) for p in xdg.split(":") if p]
    xdg_home = os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))
    dirs.append(Path(xdg_home))
    dirs += [Path("/var/lib/flatpak/exports/share"),
             Path(xdg_home) / "flatpak/exports/share",
             Path("/var/lib/snapd/desktop")]
    vus, sortie = set(), []
    for d in dirs:
        if d not in vus:
            vus.add(d)
            sortie.append(d)
    return sortie


# =============================================================================
#  Source 1 — Steam
# =============================================================================
#  Steam décrit chaque jeu installé dans un fichier appmanifest_<appid>.acf,
#  au format VDF (des paires "clé" "valeur" imbriquées). On n'écrit pas un
#  analyseur VDF complet pour deux champs : une expression régulière sur
#  "appid" et "name" suffit, et elle ne peut pas s'étrangler sur une
#  nouveauté de format — au pire elle ne trouve rien.
#
#  Les jeux ne sont pas tous dans le dossier de Steam : l'utilisateur peut
#  ajouter des bibliothèques sur d'autres disques (fréquent quand on garde le
#  SSD pour le système). Elles sont listées dans libraryfolders.vdf, qu'on lit
#  aussi — sans quoi la moitié des jeux d'un joueur équipé manquerait.

def _steam_racines():
    racines = [HOME / ".local/share/Steam", HOME / ".steam/steam",
               HOME / ".steam/root", HOME / ".var/app/com.valvesoftware.Steam"
               / "data/Steam"]
    trouvees, vus = [], set()
    for r in racines:
        steamapps = r / "steamapps"
        if steamapps.is_dir() and steamapps not in vus:
            vus.add(steamapps)
            trouvees.append(steamapps)
        # Bibliothèques sur d'autres disques
        vdf = steamapps / "libraryfolders.vdf"
        for chemin in re.findall(r'"path"\s+"([^"]+)"', _texte(vdf)):
            autre = Path(chemin) / "steamapps"
            if autre.is_dir() and autre not in vus:
                vus.add(autre)
                trouvees.append(autre)
    return trouvees


def steam():
    jeux = []
    for steamapps in _steam_racines():
        try:
            manifestes = sorted(steamapps.glob("appmanifest_*.acf"))
        except OSError:
            continue
        for m in manifestes:
            contenu = _texte(m)
            appid = re.search(r'"appid"\s+"(\d+)"', contenu, re.I)
            nom = re.search(r'"name"\s+"([^"]*)"', contenu, re.I)
            if not appid:
                continue
            # Les outils (Proton, Steam Linux Runtime…) sont installés comme
            # des « jeux » : ils encombreraient la bibliothèque sans jamais
            # servir à jouer. On les écarte sur leur nom.
            titre = (nom.group(1) if nom else f"Steam {appid.group(1)}").strip()
            if re.match(r'^(Proton|Steam Linux Runtime|Steamworks|SteamVR)',
                        titre, re.I):
                continue
            jeux.append({
                "id": f"steam:{appid.group(1)}",
                "nom": titre,
                "source": "Steam",
                "lancer": ["steam", f"steam://rungameid/{appid.group(1)}"],
            })
    return jeux


# =============================================================================
#  Source 2 — Lutris
# =============================================================================
#  Lutris tient sa liste dans une base SQLite (pga.db). On l'ouvre en LECTURE
#  SEULE et en mode immutable : Lutris peut tourner en même temps, on ne veut
#  ni le gêner, ni risquer d'écrire dans sa base. Si le schéma change, la
#  requête échoue et la source rend une liste vide — les autres continuent.

def lutris():
    base = Path(os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))) \
        / "lutris/pga.db"
    if not base.is_file():
        return []
    jeux = []
    try:
        uri = f"file:{base}?immutable=1&mode=ro"
        with sqlite3.connect(uri, uri=True, timeout=2) as cx:
            lignes = cx.execute(
                "SELECT id, name, slug, runner FROM games "
                "WHERE installed = 1 ORDER BY name").fetchall()
        for ident, nom, slug, runner in lignes:
            jeux.append({
                "id": f"lutris:{ident}",
                "nom": (nom or slug or "Jeu Lutris").strip(),
                "source": "Lutris" + (f" ({runner})" if runner else ""),
                "lancer": ["lutris", f"lutris:rungameid/{ident}"],
            })
    except (sqlite3.Error, OSError):
        return []
    return jeux


# =============================================================================
#  Source 3 — RetroArch
# =============================================================================
#  RetroArch range ses ROMs dans des « listes de lecture » .lpl, en JSON
#  depuis la version 1.7. Les très anciennes versions utilisaient un format
#  ligne à ligne ; on gère les deux, parce qu'un émulateur installé depuis
#  Debian stable n'est pas toujours de la dernière version.

def _lpl_entrees(contenu):
    contenu = contenu.strip()
    if not contenu:
        return []
    if contenu.startswith("{"):
        try:
            return json.loads(contenu).get("items", []) or []
        except (json.JSONDecodeError, AttributeError):
            return []
    # Ancien format : 6 lignes par entrée (chemin, étiquette, cœur, …)
    lignes = contenu.splitlines()
    entrees = []
    for i in range(0, len(lignes) - 5, 6):
        entrees.append({"path": lignes[i].strip(),
                        "label": lignes[i + 1].strip(),
                        "core_path": lignes[i + 2].strip()})
    return entrees


def retroarch():
    dossier = Path(os.environ.get("XDG_CONFIG_HOME", str(HOME / ".config"))) \
        / "retroarch/playlists"
    if not dossier.is_dir():
        return []
    jeux, vus = [], set()
    try:
        listes = sorted(dossier.glob("*.lpl"))
    except OSError:
        return []
    for liste in listes:
        console = liste.stem.replace(".lpl", "")
        for entree in _lpl_entrees(_texte(liste)):
            if not isinstance(entree, dict):
                continue
            rom = (entree.get("path") or "").strip()
            nom = (entree.get("label") or "").strip() or Path(rom).stem
            coeur = (entree.get("core_path") or "").strip()
            if not rom or rom in vus:
                continue
            vus.add(rom)
            argv = ["retroarch"]
            if coeur and coeur.upper() != "DETECT":
                argv += ["-L", coeur]
            argv.append(rom)
            jeux.append({
                "id": f"retroarch:{rom}",
                "nom": nom,
                "source": f"RetroArch — {console}",
                "lancer": argv,
            })
    return jeux


# =============================================================================
#  Source 4 — les lanceurs du menu, catégorie « Game »
# =============================================================================
#  C'est par là qu'arrivent les jeux installés par Debian (SuperTuxKart, 0 A.D.
#  …) ET les jeux Flatpak, qui posent tous un .desktop. On ne garde que la
#  catégorie Game, on écarte ce qui est caché (NoDisplay) et les lanceurs des
#  boutiques elles-mêmes : Steam et Lutris ne sont pas des jeux, et leurs
#  propres jeux sont déjà listés plus haut — sans quoi Steam apparaîtrait
#  deux fois, une fois comme boutique et une fois par jeu.

_PAS_DES_JEUX = {
    "steam", "steam-native", "lutris", "net.lutris.Lutris",
    "com.valvesoftware.Steam", "retroarch", "org.libretro.RetroArch",
    "mangohud", "goverlay", "corectrl", "antimicrox", "piper",
    "input-remapper-gtk", "jstest-gtk", "obs-studio", "com.obsproject.Studio",
    "winetricks", "protontricks", "lexos-jeux",
}


def _desktop_champs(contenu):
    """Lit la section [Desktop Entry] uniquement : un fichier peut contenir
    des actions supplémentaires ([Desktop Action …]) avec leurs propres Name
    et Exec, qu'il ne faut surtout pas confondre avec ceux du lanceur."""
    champs, dans_entree = {}, False
    for ligne in contenu.splitlines():
        ligne = ligne.strip()
        if ligne.startswith("["):
            dans_entree = ligne.lower() == "[desktop entry]"
            continue
        if not dans_entree or "=" not in ligne or ligne.startswith("#"):
            continue
        cle, _, valeur = ligne.partition("=")
        cle = cle.strip()
        # « Name[fr]=… » : on préfère le français quand il est là.
        if cle == "Name[fr]":
            champs["Name"] = valeur.strip()
        elif cle not in champs:
            champs[cle] = valeur.strip()
    return champs


def _exec_propre(ligne_exec):
    """Retire les codes %f %u %i %c… que la spécification .desktop autorise :
    passés tels quels à la commande, ils la feraient échouer."""
    morceaux = [m for m in ligne_exec.split()
                if not re.fullmatch(r"%[a-zA-Z]", m)]
    return morceaux


def menu():
    jeux, vus = [], set()
    for base in _dossiers_donnees():
        dossier = base / "applications"
        if not dossier.is_dir():
            continue
        try:
            fichiers = sorted(dossier.glob("*.desktop"))
        except OSError:
            continue
        for fichier in fichiers:
            ident = fichier.stem
            if ident in _PAS_DES_JEUX or ident in vus:
                continue
            champs = _desktop_champs(_texte(fichier, limite=200_000))
            categories = champs.get("Categories", "")
            if "Game" not in categories.split(";"):
                continue
            if champs.get("NoDisplay", "").lower() == "true":
                continue
            if champs.get("Hidden", "").lower() == "true":
                continue
            argv = _exec_propre(champs.get("Exec", ""))
            if not argv:
                continue
            vus.add(ident)
            # La source se lit sur la COMMANDE, pas sur le dossier : un jeu
            # Flatpak exporte son .desktop à des endroits qui varient selon
            # l'installation (système ou utilisateur), alors que sa commande
            # commence toujours par « flatpak run ».
            source = "Flatpak" if argv[0] == "flatpak" else "Installé"
            jeux.append({
                "id": f"menu:{ident}",
                "nom": champs.get("Name", ident),
                "source": source,
                "lancer": argv,
                "icone": champs.get("Icon", ""),
            })
    return jeux


# =============================================================================
#  Réunion des sources
# =============================================================================

SOURCES = (("Steam", steam), ("Lutris", lutris),
           ("RetroArch", retroarch), ("Menu", menu))


def _cle_doublon(jeu):
    """Deux entrées désignent le même jeu si leur nom se ramène au même texte.
    Un jeu Steam pose souvent AUSSI un .desktop : sans ce regroupement, il
    apparaîtrait deux fois dans la bibliothèque."""
    return re.sub(r"[^a-z0-9]", "", jeu["nom"].lower())


def tous(inclure_erreurs=False):
    """La bibliothèque complète. Chaque source est protégée : celle qui échoue
    est signalée, les autres sont rendues quand même."""
    jeux, erreurs = [], []
    for nom_source, fonction in SOURCES:
        try:
            jeux += fonction()
        except Exception as e:                      # noqa: BLE001
            erreurs.append(f"{nom_source} : {e}")

    # Steam et Lutris d'abord : quand un jeu est vu deux fois, on garde
    # l'entrée qui sait le lancer avec ses réglages (Proton, script Lutris)
    # plutôt que le .desktop générique.
    rang = {"Steam": 0, "Lutris": 1, "RetroArch": 2}
    jeux.sort(key=lambda j: (rang.get(j["source"].split(" —")[0].split(" (")[0], 3),
                             j["nom"].lower()))
    uniques, vus = [], set()
    for jeu in jeux:
        cle = _cle_doublon(jeu)
        if not cle or cle in vus:
            continue
        vus.add(cle)
        uniques.append(jeu)
    uniques.sort(key=lambda j: j["nom"].lower())
    if inclure_erreurs:
        return uniques, erreurs
    return uniques


def par_id(identifiant):
    for jeu in tous():
        if jeu["id"] == identifiant:
            return jeu
    return None


# =============================================================================
#  Lancement
# =============================================================================
#  On ne lance JAMAIS un jeu par le shell : argv part en liste, donc un nom de
#  fichier contenant une apostrophe ou un point-virgule ne peut rien exécuter.
#  Le passage par « lexos-game » n'est pas cosmétique : il bascule la machine
#  en profil performant le temps de la partie, branche GameMode et MangoHud,
#  puis remet le profil d'avant en sortant.

def lancer(identifiant, avec_reglages=True):
    jeu = par_id(identifiant)
    if jeu is None:
        return {"ok": False, "erreur": f"Jeu introuvable : {identifiant}"}
    argv = list(jeu["lancer"])
    if shutil.which(argv[0]) is None:
        return {"ok": False,
                "erreur": f"« {argv[0]} » n'est pas installé sur cette machine."}
    if avec_reglages and shutil.which("lexos-game"):
        argv = ["lexos-game"] + argv
    try:
        subprocess.Popen(argv, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": True, "nom": jeu["nom"]}


# =============================================================================
#  Utilisation directe, au terminal
# =============================================================================

def _principal(argv):
    if "--json" in argv:
        jeux, erreurs = tous(inclure_erreurs=True)
        print(json.dumps({"jeux": jeux, "erreurs": erreurs},
                         ensure_ascii=False, indent=1))
        return 0
    if "--lancer" in argv:
        i = argv.index("--lancer")
        if i + 1 >= len(argv):
            print("Il manque l'identifiant du jeu.", file=sys.stderr)
            return 2
        r = lancer(argv[i + 1])
        print(r.get("erreur") or f"Lancement : {r.get('nom')}",
              file=sys.stderr if not r["ok"] else sys.stdout)
        return 0 if r["ok"] else 1

    jeux, erreurs = tous(inclure_erreurs=True)
    if not jeux:
        print("Aucun jeu trouvé.")
        print("Installe des jeux avec Steam, Lutris ou la Logithèque,")
        print("puis reviens : ils apparaîtront ici tout seuls.")
    else:
        largeur = max(len(j["nom"]) for j in jeux)
        for jeu in jeux:
            print(f"  {jeu['nom']:<{largeur}}   {jeu['source']}")
        print(f"\n  {len(jeux)} jeu(x).")
    for e in erreurs:
        print(f"  (source ignorée — {e})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(_principal(sys.argv[1:]))
