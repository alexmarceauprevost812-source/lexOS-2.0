"""LexOS Pilotes — l'état de la carte graphique, en lecture seule.

Tourne en utilisateur, sans sudo. Chaque champ manquant (outil absent,
fichier illisible) devient None : l'interface affiche « — » plutôt que de
planter, même règle que le Diagnostic.
"""
from __future__ import annotations

import os
import platform
import re
import subprocess
import time
from pathlib import Path
from typing import Optional

import paquets

RACINE_MODULES = Path(os.environ.get("LEXOS_PILOTES_MODULES", "/lib/modules"))
LISTES_APT = Path("/var/lib/apt/lists")


def _executer(cmd: list, timeout: float = 10.0) -> Optional[str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def lire_cartes(sortie_lspci: Optional[str] = None) -> list:
    """Les cartes graphiques vues par « lspci -nnk », avec le pilote en service."""
    if sortie_lspci is None:
        sortie_lspci = _executer(["lspci", "-nnk"]) or ""
    cartes = []
    courante = None
    for ligne in sortie_lspci.splitlines():
        if ligne and not ligne[0].isspace():
            courante = None
            if re.search(r"(VGA compatible controller|3D controller|Display controller)", ligne):
                nom = ligne.split(": ", 1)[1] if ": " in ligne else ligne
                nom = re.sub(r"\s*\[[0-9a-f]{4}:[0-9a-f]{4}\]", "", nom)
                nom = re.sub(r"\s*\(rev [0-9a-f]+\)", "", nom).strip()
                bas = nom.lower()
                #  Mots entiers : « ati » est caché dans « Corporation ».
                marque = ("NVIDIA" if "nvidia" in bas else
                          "Intel" if re.search(r"\bintel\b", bas) else
                          "AMD" if re.search(r"\b(amd|ati|radeon)\b", bas) else "Autre")
                courante = {"nom": nom, "marque": marque, "pilote": None}
                cartes.append(courante)
        elif courante is not None and "Kernel driver in use:" in ligne:
            courante["pilote"] = ligne.split(":", 1)[1].strip()
    return cartes


def version_nvidia() -> Optional[str]:
    try:
        texte = Path("/proc/driver/nvidia/version").read_text(encoding="utf-8")
        m = re.search(r"Kernel Module(?: for x86_64)?\s+(\d+\.\d+(?:\.\d+)?)", texte)
        if m:
            return m.group(1)
    except OSError:
        pass
    sortie = _executer(["nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader"])
    return sortie.strip().splitlines()[0] if sortie and sortie.strip() else None


def version_paquet(nom: str) -> Optional[str]:
    sortie = _executer(["dpkg-query", "-W", "-f", "${Version}", nom])
    return sortie.strip() if sortie and sortie.strip() else None


def noyaux() -> dict:
    try:
        noms = sorted((p.name for p in RACINE_MODULES.iterdir() if p.is_dir()))
    except OSError:
        noms = []
    if noms:
        r = subprocess.run(["sort", "-V"], input="\n".join(noms), capture_output=True, text=True, check=False)
        noms = [l for l in r.stdout.splitlines() if l.strip()]
    plus_recent = noms[-1] if noms else None
    module = False
    if plus_recent:
        module = any(True for _ in (RACINE_MODULES / plus_recent).rglob("nvidia.ko*"))
    return {"en_service": platform.release(), "plus_recent": plus_recent,
            "module_nvidia_plus_recent": module}


def secure_boot() -> Optional[bool]:
    sortie = _executer(["mokutil", "--sb-state"])
    if sortie is None:
        return None
    return "enabled" in sortie.lower()


def derniere_verification() -> Optional[float]:
    """Quand les index apt ont été rafraîchis pour la dernière fois."""
    try:
        dates = [p.stat().st_mtime for p in LISTES_APT.iterdir() if p.name.endswith("Packages") or "_Packages" in p.name]
    except OSError:
        return None
    return max(dates) if dates else None


def instantane() -> dict:
    cartes = lire_cartes()
    a_nvidia = any(c["marque"] == "NVIDIA" for c in cartes)
    epingle = paquets.branche_epinglee()
    plus_recente = paquets.branche_plus_recente() if a_nvidia else None
    plan = paquets.plan_mises_a_jour()
    return {
        "cartes": cartes,
        "nvidia": {
            "version": version_nvidia() if a_nvidia else None,
            "paquet": version_paquet("nvidia-driver-cuda") or version_paquet("nvidia-driver"),
            "branche_epinglee": epingle,
            "plus_recente_publiee": plus_recente,
        },
        "mesa": version_paquet("libgl1-mesa-dri"),
        "noyau": noyaux(),
        "secure_boot": secure_boot(),
        "verifie_le": derniere_verification(),
        "maintenant": time.time(),
        "mises_a_jour": [{k: p[k] for k in ("paquet", "installe", "cible", "source")} for p in plan],
    }
