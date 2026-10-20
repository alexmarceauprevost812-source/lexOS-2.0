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
from pathlib import Path

FICHIER = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "lexos" / "bureau.json"

MODES = ("moteur", "classique")
FONDS = ("constellation", "aurore", "etoiles", "pluie", "vagues", "braises", "aucun")
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
    "mode": "moteur",
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
}
BORNES = {"taille": (80, 140), "voile": (0, 90), "flou": (0, 20), "vitesse": (20, 300), "densite": (20, 200)}


def _propre(cle: str, v):
    """La valeur v si elle est valide pour cle, sinon None."""
    if cle == "mode":
        return v if v in MODES else None
    if cle == "anim":
        return v if v in FONDS else None
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
        p = Path(v).expanduser()
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
    tmp = FICHIER.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(r, ensure_ascii=False, indent=2), "utf-8")
    os.replace(tmp, FICHIER)
    return r


def empreinte() -> str:
    try:
        return str(FICHIER.stat().st_mtime_ns)
    except OSError:
        return "0"
