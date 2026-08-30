"""LexOS Diagnostic — utilitaires communs à moteur.py / medecin.py / disques.py.

Règle du module : aucune fonction ici ne lève d'exception vers l'appelant.
Un outil absent, en échec ou trop lent doit produire un champ manquant
(None / valeur par défaut), jamais un plantage du moteur de collecte.
C'est la même philosophie que verifier.sh : signaler le trou, ne jamais
casser silencieusement ni faire planter tout le reste.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional


def executable_present(nom: str) -> bool:
    """True si la commande `nom` est disponible dans le PATH."""
    return shutil.which(nom) is not None


def executer(cmd: list, timeout: float = 3.0) -> Optional[str]:
    """Exécute une commande et renvoie sa sortie standard, ou None en cas d'échec.

    Ne lève jamais d'exception : outil absent, permission refusée, code de
    sortie non nul ou dépassement du délai renvoient tous None.
    """
    try:
        resultat = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if resultat.returncode != 0:
            return None
        return resultat.stdout
    except (OSError, subprocess.TimeoutExpired, subprocess.SubprocessError):
        return None


def executer_json(cmd: list, timeout: float = 3.0):
    """Comme executer(), mais parse la sortie en JSON. None si absent ou invalide."""
    sortie = executer(cmd, timeout=timeout)
    if sortie is None:
        return None
    try:
        return json.loads(sortie)
    except (json.JSONDecodeError, ValueError):
        return None


def formater_octets(valeur: Optional[float]) -> str:
    """1234567 -> '1,2 Mo' (unités françaises, base 1024)."""
    if valeur is None:
        return "—"
    unites = ["o", "Ko", "Mo", "Go", "To"]
    v = float(valeur)
    for unite in unites:
        if abs(v) < 1024.0:
            return f"{v:.1f} {unite}".replace(".", ",")
        v /= 1024.0
    return f"{v:.1f} Po".replace(".", ",")


def lire_gpu_conf() -> dict:
    """Lit /etc/lexos/gpu.conf, posé par gpu-select au démarrage (voir
    lexos-bug-rtx5060.md). Fichier clé=valeur simple :
        gpu_pci=10de:2c05
        gpu_mode=nvidia|nouveau|safe

    Absent hors d'une vraie installation LexOS (ex. machine de
    développement) — ce n'est pas une erreur, juste une information qu'on
    n'a pas ici.
    """
    chemin = Path("/etc/lexos/gpu.conf")
    valeurs: dict = {}
    try:
        for ligne in chemin.read_text(encoding="utf-8").splitlines():
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            cle, _, val = ligne.partition("=")
            valeurs[cle.strip()] = val.strip()
    except (FileNotFoundError, OSError):
        pass
    return valeurs


def lire_version_lexos() -> str:
    """/etc/lexos/version, sinon PRETTY_NAME de /etc/os-release, sinon 'inconnue'."""
    try:
        contenu = Path("/etc/lexos/version").read_text(encoding="utf-8").strip()
        if contenu:
            return contenu
    except (FileNotFoundError, OSError):
        pass
    try:
        for ligne in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if ligne.startswith("PRETTY_NAME="):
                return ligne.split("=", 1)[1].strip().strip('"')
    except (FileNotFoundError, OSError):
        pass
    return "inconnue"


def horodatage() -> float:
    return time.time()
