"""LexOS Bureau — les réglages du bureau (~/.config/lexos/bureau.json).

UNE seule source pour trois lecteurs : le bureau lui-même, son menu du clic
droit, et la section « Bureau » des Paramètres de LexOS. Chacun passe par
lire() / ecrire() : une valeur inconnue ou hors bornes est ramenée au
défaut, jamais écrite telle quelle — un fichier abîmé à la main ne peut pas
casser le bureau.

Les choix (couleurs, polices, fonds animés) sont ceux du Moteur d'Alex
(fond.js : COULEURS, POLICES, FONDS) — mêmes noms, mêmes valeurs.
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path

FICHIER = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "lexos" / "bureau.json"

MODES = ("moteur", "classique")
#  « pluie » (Pluie de code, l'effet Matrix) : retirée le 2026-10-22, RAMENÉE
#  le 2026-10-23 à la demande d'Alex — elle reste maintenant SOUS la barre du haut.
FONDS = ("constellation", "aurore", "etoiles", "pluie", "vagues", "braises", "aucun")
EMBLEMES = ("nomad", "rond", "aucun")
POLICES = ("Space Grotesk", "Inter", "Poppins", "Montserrat", "Lexend", "Nunito", "Quicksand",
           "Fredoka", "Comfortaa", "Exo 2", "Rajdhani", "Oxanium", "Orbitron", "Audiowide",
           "Righteous", "Bebas Neue", "Press Start 2P", "JetBrains Mono", "Système", "Serif classique")
COULEURS = (
    ("Orange LexOS", "#ff7a18"), ("Rouge feu", "#ff3b30"), ("Sang", "#c81e1e"), ("Corail", "#ff6b6b"),
    ("Saumon", "#ff8f70"), ("Rose néon", "#ff2d95"), ("Rose bonbon", "#ff7ac6"), ("Magenta", "#e040fb"),
    ("Violet", "#8b5cf6"), ("Lavande", "#c4b5fd"), ("Indigo", "#6366f1"), ("Bleu Québec", "#1e6bff"),
    ("Bleu ciel", "#38bdf8"), ("Cyan", "#22d3ee"), ("Turquoise", "#14b8a6"), ("Émeraude", "#10b981"),
    ("Menthe", "#5eead4"), ("Vert néon", "#39ff14"), ("Lime", "#a3e635"), ("Jaune", "#facc15"),
    ("Or", "#e8b04a"), ("Ambre", "#f59e0b"), ("Cuivre", "#c87533"), ("Argent", "#cbd5e1"),
    ("Blanc pur", "#f4f4f5"), ("Arc-en-ciel", "arc-en-ciel"),
)
EXT_IMAGES = (".png", ".jpg", ".jpeg", ".webp", ".gif")

DEFAUTS = {
    #  Classique par défaut (2026-10-20, demande d'Alex) : la télé perd le
    #  signal au démarrage sur l'Alienware ; on repart du bureau XFCE, le
    #  Moteur reste installé et se rallume dans Paramètres → Bureau LexOS.
    "mode": "classique",
    "accent": "#ff7a18",
    "police": "Space Grotesk",
    "taille": 100,
    "anim": "constellation",
    "image": "",
    "voile": 35,
    "flou": 0,
    "vitesse": 100,
    "densite": 100,
    "orbes": True,
    "grille": True,
    "curseur": True,
    "zoom": True,
    "horloge": True,
    "tilex": True,
    "lexos": True,
    "bureau": True,
    #  Le grand logo au centre (nouvelle version du Moteur d'Alex) : la
    #  bannière LexOS Nomad, le logo rond, ou rien. Un clic dessus passe au
    #  suivant ; le choix est gardé ici, pas dans le navigateur de la page.
    "embleme": "nomad",
    #  Le code qui s'écrit tout seul derrière la bannière Nomad — RETIRÉ du
    #  bureau à la demande d'Alex (« enlever les lignes de code en fond
    #  d'écran ») ; la clé reste pour les réglages déjà écrits.
    "code": False,
    #  🧪 Mon labo : le panneau qui monte quand la souris reste collée en
    #  bas de l'écran. « labo_delai » : combien de temps elle doit y rester
    #  (ms). « labo_apps » : ce qu'Alex y a mis, dans l'ordre ; ["*"] = pas
    #  encore choisi → les onglets de ti-lex IA, le terminal et Fichiers.
    "labo": True,
    "labo_delai": 1000,
    "labo_apps": ["*"],
    #  🎛️ Mes outils : la barre mince qui descend du HAUT de l'écran, sous la
    #  barre du haut (volume, capture, notifications, arrêt, et les outils
    #  qu'Alex y place). ["*"] = pas encore choisi → quelques outils LexOS.
    "outils": True,
    #  ALEX (2026-11-01) : « on va le voir juste quand on met la souris
    #  [en haut], 0.3 sec avant son apparition ». Son propre délai, séparé
    #  de celui du labo (1 s en bas) : le haut doit répondre plus vite.
    "outils_delai": 300,
    "outils_apps": ["*"],
    #  Où Alex a posé ses icônes : {identifiant: [x, y]} en pixels du bureau.
    #  Vide = la grille par sections. Une icône qu'on n'a jamais déplacée
    #  reste dans la grille.
    "positions": {},
}
BORNES = {"labo_delai": (300, 3000), "outils_delai": (100, 3000), "taille": (80, 140), "voile": (0, 90), "flou": (0, 20), "vitesse": (20, 300), "densite": (20, 200)}


MAX_POSITIONS = 400
MAX_LABO = 60
_ID_ICONE = re.compile(r"^[a-z]-[a-z0-9-]{1,40}$")


def _positions(v):
    if not isinstance(v, dict) or len(v) > MAX_POSITIONS:
        return None
    propre = {}
    for cle, xy in v.items():
        if not (isinstance(cle, str) and _ID_ICONE.match(cle)):
            continue
        if (isinstance(xy, (list, tuple)) and len(xy) == 2
                and all(isinstance(n, (int, float)) and not isinstance(n, bool) for n in xy)):
            propre[cle] = [int(min(10000, max(0, xy[0]))), int(min(10000, max(0, xy[1])))]
    return propre


def _propre(cle: str, v):
    """La valeur v si elle est valide pour cle, sinon None."""
    if cle == "positions":
        return _positions(v)
    if cle in ("labo_apps", "outils_apps"):
        if v == ["*"]:
            return ["*"]
        if not isinstance(v, list):
            return None
        propre = []
        for x in v[:MAX_LABO * 2]:
            if isinstance(x, str) and _ID_ICONE.match(x) and x not in propre:
                propre.append(x)
        return propre[:MAX_LABO]
    if cle == "mode":
        return v if v in MODES else None
    if cle == "anim":
        return v if v in FONDS else None
    if cle == "embleme":
        return v if v in EMBLEMES else None
    if cle == "police":
        return v if v in POLICES else None
    if cle == "accent":
        if v == "arc-en-ciel" or (isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v)):
            return v.lower()
        return None
    if cle == "image":
        if v == "":
            return ""
        if not isinstance(v, str) or len(v) > 1000 or "\0" in v:
            return None
        try:
            #  « ~inconnu/… » fait lever RuntimeError à expanduser() — un
            #  fichier abîmé à la main ne doit JAMAIS faire tomber lire().
            p = Path(v).expanduser()
        except (RuntimeError, ValueError):
            return None
        return str(p) if p.is_absolute() and p.suffix.lower() in EXT_IMAGES else None
    if cle in BORNES:
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        a, b = BORNES[cle]
        return int(min(b, max(a, v)))
    if isinstance(DEFAUTS.get(cle), bool):
        return v if isinstance(v, bool) else None
    return None


def lire() -> dict:
    r = dict(DEFAUTS)
    r["positions"] = {}
    r["labo_apps"] = list(DEFAUTS["labo_apps"])
    r["outils_apps"] = list(DEFAUTS["outils_apps"])
    try:
        brut = json.loads(FICHIER.read_text("utf-8"))
    except (OSError, ValueError):
        return r
    if isinstance(brut, dict):
        for cle in DEFAUTS:
            if cle in brut:
                v = _propre(cle, brut[cle])
                if v is not None:
                    r[cle] = v
    return r


def ecrire(partiel: dict) -> dict:
    """Fusionne les clés VALIDES de partiel ; ignore le reste. Rend l'état."""
    r = lire()
    if isinstance(partiel, dict):
        for cle, v in partiel.items():
            if cle in DEFAUTS:
                propre = _propre(cle, v)
                if propre is not None:
                    r[cle] = propre
    FICHIER.parent.mkdir(parents=True, exist_ok=True)
    #  Un fichier temporaire À SOI : la page, les Paramètres et « lexos
    #  wallpaper » peuvent écrire en même temps — un nom fixe les faisait se
    #  marcher dessus (os.replace d'un fichier déjà déplacé par l'autre).
    fd, tmp = tempfile.mkstemp(prefix=".bureau-", suffix=".json", dir=str(FICHIER.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(r, f, ensure_ascii=False, indent=2)
        os.replace(tmp, FICHIER)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return r


def empreinte() -> str:
    try:
        return str(FICHIER.stat().st_mtime_ns)
    except OSError:
        return "0"


def image_du_fond(chemin: str) -> None:
    """Pour « lexos wallpaper » et lexos-fond-ecran : le fond choisi passe
    aussi au bureau du Moteur. Un format qu'il ne sait pas afficher (avif,
    bmp, tif, svg…) RETIRE l'image au lieu de garder la précédente : sinon
    Alex choisirait un fond et verrait encore l'ancien."""
    p = Path(chemin)
    ecrire({"image": str(p) if p.suffix.lower() in EXT_IMAGES else ""})


if __name__ == "__main__":
    #  python3 reglages.py image /chemin/vers/fond.jpg
    if len(sys.argv) == 3 and sys.argv[1] == "image":
        image_du_fond(os.path.realpath(sys.argv[2]))
    else:
        print("usage : reglages.py image <chemin>", file=sys.stderr)
        sys.exit(2)
