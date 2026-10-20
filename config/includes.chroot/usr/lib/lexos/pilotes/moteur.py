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
#  La signature du pilote : le certificat LexOS que l'ISO embarque, et
#  l'identifiant de sa clé noté à la construction (hook 9890).
CERT_LEXOS = Path(os.environ.get("LEXOS_PILOTES_CERT", "/usr/share/lexos/secure-boot/lexos-mok.der"))
BUILD_CONF = Path(os.environ.get("LEXOS_PILOTES_BUILD_CONF", "/etc/lexos/build.conf"))
PROC_MODULES = Path(os.environ.get("LEXOS_PILOTES_PROC_MODULES", "/proc/modules"))
CMDLINE = Path(os.environ.get("LEXOS_PILOTES_CMDLINE", "/proc/cmdline"))
#  modinfo vit dans /usr/sbin, hors du PATH d'un utilisateur Debian.
MODINFO = next((c for c in ("/usr/sbin/modinfo", "/sbin/modinfo") if os.path.exists(c)), "modinfo")


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


def _lire_build_conf(cle: str) -> Optional[str]:
    try:
        for ligne in BUILD_CONF.read_text(encoding="utf-8").splitlines():
            if ligne.startswith(cle + "="):
                return ligne.split("=", 1)[1].strip().strip('"') or None
    except OSError:
        pass
    return None


def _module_charge(nom: str) -> bool:
    try:
        return any(l.split(" ", 1)[0] == nom for l in PROC_MODULES.read_text(encoding="utf-8").splitlines())
    except OSError:
        return False


def _cle_inscrite(cert: Path) -> Optional[bool]:
    """« mokutil --test-key » ne fait que LIRE la liste MOK. None = impossible à savoir."""
    try:
        r = subprocess.run(["mokutil", "--test-key", str(cert)], capture_output=True, text=True,
                           timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    texte = (r.stdout + r.stderr).lower()
    if "already enrolled" in texte:
        return True
    if "not enrolled" in texte:
        return False
    return None


def signature_pilote(secure_boot_actif: Optional[bool]) -> dict:
    """Où en est le pilote NVIDIA face au Secure Boot, et QUELLE étape montrer.

    Étapes : « ok » (chargé), « sans-secure-boot », « inscrire-lexos »
    (signé LexOS, certificat pas encore inscrit), « redemarrer » (inscrit mais
    pas chargé), « cle-machine » (signé par une autre clé : lexos-signer-pilote),
    « inconnu ».
    """
    id_lexos = (_lire_build_conf("LEXOS_SIGNATURE_CLE_ID") or "").upper() or None
    sortie = _executer([MODINFO, "-F", "sig_key", "nvidia"])
    id_module = sortie.strip().splitlines()[0].replace(" ", "").upper() if sortie and sortie.strip() else None
    par_lexos = bool(id_lexos and id_module and id_lexos == id_module)
    charge = _module_charge("nvidia")
    inscrite = _cle_inscrite(CERT_LEXOS) if CERT_LEXOS.is_file() else None
    try:
        en_live = "boot=live" in CMDLINE.read_text(encoding="utf-8")
    except OSError:
        en_live = False

    if charge:
        etape = "ok"
    elif secure_boot_actif is False:
        etape = "sans-secure-boot"
    elif par_lexos and inscrite is False:
        etape = "inscrire-lexos"
    elif par_lexos and inscrite:
        etape = "redemarrer"
    elif id_module and not par_lexos:
        etape = "cle-machine"
    else:
        etape = "inconnu"
    return {
        "etape": etape,
        "signe_par_lexos": par_lexos,
        "cle_module": id_module,
        "cle_lexos": id_lexos,
        "certificat": str(CERT_LEXOS) if CERT_LEXOS.is_file() else None,
        "certificat_inscrit": inscrite,
        "module_charge": charge,
        "en_live": en_live,
    }


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
    sb = secure_boot()
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
        "secure_boot": sb,
        "signature": signature_pilote(sb) if a_nvidia else None,
        "verifie_le": derniere_verification(),
        "maintenant": time.time(),
        "mises_a_jour": [{k: p[k] for k in ("paquet", "installe", "cible", "source")} for p in plan],
    }
