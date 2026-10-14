#!/usr/bin/env python3
"""LexOS — choisir la présentation des fichiers dans Thunar 4.20/XFCE.

La source de vérité de Thunar 4.20 est le canal XFCONF « thunar ».
Le vieux ~/.config/Thunar/thunarrc n'est lu qu'une fois pour migration :
le modifier sur un compte existant ne change pas son affichage.

Ce module ne change PAS les dialogues « Sélectionner des fichiers »
de Firefox/Chromium/GTK, qui appartiennent à leurs applications.
Il ne touche pas aux fichiers personnels, aux icônes du bureau ou aux
pilotes graphiques. Chaque choix est borné à des propriétés XFCONF connues.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from moteur import outils as _outils

CHANNEL = "thunar"
TIMEOUT = 4
# Clés documentées par thunar-preferences.c (Thunar 4.20, Debian 13).
KEYS = {
    "/last-view": "string",
    "/last-icon-view-zoom-level": "string",
    "/last-image-preview-visible": "bool",
    "/misc-image-preview-mode": "string",
    "/misc-thumbnail-mode": "string",
}
VIEWS = {
    "liste": {
        "/last-view": "ThunarDetailsView",
    },
    "icones": {
        "/last-view": "ThunarIconView",
        "/last-icon-view-zoom-level": "THUNAR_ZOOM_LEVEL_100_PERCENT",
    },
    "grandes": {
        "/last-view": "ThunarIconView",
        "/last-icon-view-zoom-level": "THUNAR_ZOOM_LEVEL_200_PERCENT",
        "/misc-thumbnail-mode": "THUNAR_THUMBNAIL_MODE_ONLY_LOCAL",
        "/misc-image-preview-mode": "THUNAR_IMAGE_PREVIEW_MODE_STANDALONE",
        "/last-image-preview-visible": True,
    },
    "compact": {
        "/last-view": "ThunarCompactView",
    },
}
MODES = {
    **VIEWS,
    "apercu-on": {
        "/misc-image-preview-mode": "THUNAR_IMAGE_PREVIEW_MODE_STANDALONE",
        "/last-image-preview-visible": True,
    },
    "apercu-off": {
        "/last-image-preview-visible": False,
    },
    "miniatures-on": {
        "/misc-thumbnail-mode": "THUNAR_THUMBNAIL_MODE_ONLY_LOCAL",
    },
    "miniatures-off": {
        "/misc-thumbnail-mode": "THUNAR_THUMBNAIL_MODE_NEVER",
    },
}
NOMS = {
    "liste": "Liste détaillée",
    "icones": "Icônes classiques",
    "grandes": "Grandes miniatures avec aperçu à droite",
    "compact": "Liste compacte",
    "apercu-on": "Grand aperçu à droite activé",
    "apercu-off": "Grand aperçu à droite désactivé",
    "miniatures-on": "Miniatures des images locales activées",
    "miniatures-off": "Miniatures désactivées",
}
TITRE = "Choisir l'affichage des fichiers — LexOS"


class ReglageErreur(Exception):
    """Erreur du canal Thunar avec un motif explicite pour l'interface."""


def _commande(argv: list[str]) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            argv, capture_output=True, text=True, timeout=TIMEOUT, check=False
        )
    except subprocess.TimeoutExpired as e:
        raise ReglageErreur("Le service des réglages XFCE ne répond pas.") from e
    except OSError as e:
        raise ReglageErreur(f"Impossible de contacter XFCE : {e}") from e


def _present() -> bool:
    return (_outils.commande_existe("xfconf-query")
            and _outils.commande_existe("thunar"))


def _lire(cle: str) -> Optional[str]:
    if cle not in KEYS:
        raise ReglageErreur("Propriété Thunar interdite.")
    r = _commande(["xfconf-query", "-c", CHANNEL, "-p", cle])
    return r.stdout.strip() if r.returncode == 0 else None


def _poser(cle: str, valeur: object, deja_existe: bool) -> None:
    if cle not in KEYS:
        raise ReglageErreur("Propriété Thunar interdite.")
    typ = KEYS[cle]
    if typ == "bool" and not isinstance(valeur, bool):
        raise ReglageErreur(f"Valeur booléenne invalide pour {cle}.")
    if typ == "string" and not isinstance(valeur, str):
        raise ReglageErreur(f"Valeur texte invalide pour {cle}.")
    chaine = ("true" if valeur else "false") if typ == "bool" else str(valeur)
    args = ["xfconf-query", "-c", CHANNEL, "-p", cle]
    if not deja_existe:
        args += ["--create", "--type", typ]
    args += ["--set", chaine]
    r = _commande(args)
    if r.returncode != 0:
        raise ReglageErreur((r.stderr or r.stdout).strip()
                            or f"XFCE a refusé la valeur de {cle}.")


def _retirer(cle: str) -> None:
    if cle not in KEYS:
        return
    _commande(["xfconf-query", "-c", CHANNEL, "-p", cle, "--reset"])


def etat() -> dict:
    """État réel, sans inventer une vue si XFCONF ne répond pas."""
    if not _present():
        return {"disponible": False, "vue": None, "grandes": False,
                "apercu": None, "miniatures": None}
    view = _lire("/last-view")
    zoom = _lire("/last-icon-view-zoom-level")
    preview = _lire("/last-image-preview-visible")
    mode = _lire("/misc-thumbnail-mode")
    retour = {
        "ThunarDetailsView": "liste",
        "ThunarIconView": "icones",
        "ThunarCompactView": "compact",
    }.get(view)
    grandes = (view == "ThunarIconView" and
               zoom == "THUNAR_ZOOM_LEVEL_200_PERCENT")
    if grandes:
        retour = "grandes"
    return {
        "disponible": True,
        "vue": retour,
        "grandes": grandes,
        "apercu": (preview.lower() == "true") if preview is not None else None,
        "miniatures": (mode != "THUNAR_THUMBNAIL_MODE_NEVER")
        if mode is not None else None,
    }


def choisir(mode: str) -> dict:
    """Modifier la configuration Thunar, en restaurant en cas d'échec partiel."""
    if not isinstance(mode, str) or mode not in MODES:
        return {"ok": False, "erreur": "Mode non autorisé."}
    if not _present():
        return {"ok": False, "erreur": "Thunar ou xfconf-query n'est pas installé."}
    valeurs = MODES[mode]
    precedentes = {}
    modifiees = []
    try:
        for cle in valeurs:
            precedentes[cle] = _lire(cle)
        for cle, nouvelle in valeurs.items():
            ancienne = precedentes[cle]
            if ancienne is not None:
                canon = ("true" if nouvelle else "false") if isinstance(
                    nouvelle, bool) else str(nouvelle)
                if ancienne.lower() == canon.lower():
                    continue
            _poser(cle, nouvelle, ancienne is not None)
            modifiees.append(cle)
    except ReglageErreur as erreur:
        # Un profil « grandes » modifie plusieurs clés. Ne pas laisser
        # une moitié de profil en cas de refus de la dernière propriété.
        for cle in reversed(modifiees):
            ancienne = precedentes[cle]
            try:
                if ancienne is None:
                    _retirer(cle)
                else:
                    _poser(cle, ancienne.lower() == "true"
                           if KEYS[cle] == "bool" else ancienne, True)
            except ReglageErreur:
                pass
        return {"ok": False, "erreur": str(erreur)}
    return {"ok": True, "message":
            NOMS[mode] + ". Ferme et rouvre Fichiers si la fenêtre est déjà ouverte."}


def usage() -> str:
    return f"""\
{TITRE}

  lexos vue-fichiers grandes          Grandes miniatures + aperçu à droite
  lexos vue-fichiers icones           Vue icônes classiques
  lexos vue-fichiers liste            Vue liste avec détails
  lexos vue-fichiers compact          Vue compacte
  lexos vue-fichiers apercu on|off    Afficher/masquer l'aperçu à droite
  lexos vue-fichiers miniatures on|off
  lexos vue-fichiers etat             Montrer les réglages actuels

Ces options règlent THUNAR, pas tous les sélecteurs d'images de Firefox
ou des autres applications. Les changements des fenêtres déjà ouvertes
peuvent demander leur fermeture puis leur réouverture.
"""


def main(argv: list[str]) -> int:
    mode = argv[0] if argv else "aide"
    if mode in ("aide", "help", "-h", "--help"):
        print(usage())
        return 0
    if mode in ("etat", "status"):
        print(json.dumps(etat(), ensure_ascii=False, indent=2))
        return 0
    if mode in ("apercu", "miniatures") and len(argv) == 2:
        mode += "-" + argv[1]
    resultat = choisir(mode)
    print(("✓ " + resultat.get("message", "")) if resultat["ok"]
          else ("✗ " + resultat["erreur"]),
          file=sys.stdout if resultat["ok"] else sys.stderr)
    return 0 if resultat["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
