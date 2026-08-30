"""LexOS Disques — santé SMART/NVMe, espace, doublons.

Complète moteur.etat_disques() (espace/point de montage, rapide, appelé à
chaque sondage) avec ce qui est plus lent et se vérifie à la demande plutôt
qu'en boucle : état SMART, usure NVMe, doublons.

Le test de clé USB (f3write/f3read) n'est PAS automatisé ici : il écrit sur
le périphérique choisi, et se tromper de cible efface des données. L'onglet
Disques affiche la commande à lancer soi-même dans un terminal plutôt qu'un
bouton — même logique que « le mode sûr doit rester laid » dans
lexos-theme-demarrage.md : un geste destructeur mérite un geste délibéré.
"""
from __future__ import annotations

import json
import re
import tempfile
from pathlib import Path
from typing import Optional

import moteur
from utils import executable_present, executer, executer_json


def _peripheriques_physiques() -> list:
    """/dev/sda, /dev/nvme0n1… — les disques physiques, pas les partitions."""
    base = Path("/sys/block")
    if not base.is_dir():
        return []
    resultats = []
    for entree in sorted(base.iterdir()):
        if re.match(r"^(sd[a-z]+|nvme\d+n\d+|mmcblk\d+|vd[a-z]+)$", entree.name):
            resultats.append(f"/dev/{entree.name}")
    return resultats


def _sante_smart(peripherique: str) -> dict:
    if not executable_present("smartctl"):
        return {
            "peripherique": peripherique,
            "disponible": False,
            "sain": None,
            "message": "smartmontools non installé",
        }

    donnees = executer_json(["smartctl", "-H", "-j", peripherique], timeout=8.0)
    if donnees is None:
        # smartctl renvoie parfois un code non nul même disque sain (bits
        # d'avertissement) : on retente sans -j pour distinguer « absent »
        # de « en échec avec un vrai message à lire ».
        sortie = executer(["smartctl", "-H", peripherique], timeout=8.0)
        if sortie is None:
            return {
                "peripherique": peripherique,
                "disponible": False,
                "sain": None,
                "message": "lecture SMART impossible (permissions ? périphérique USB endormi ?)",
            }
        sain = "PASSED" in sortie or "OK" in sortie.upper()
        return {"peripherique": peripherique, "disponible": True, "sain": sain, "message": None}

    sain = None
    bloc_statut = donnees.get("smart_status")
    if isinstance(bloc_statut, dict):
        sain = bloc_statut.get("passed")

    temperature = None
    bloc_temp = donnees.get("temperature")
    if isinstance(bloc_temp, dict):
        temperature = bloc_temp.get("current")

    return {
        "peripherique": peripherique,
        "disponible": True,
        "sain": sain,
        "modele": donnees.get("model_name") or donnees.get("model_family"),
        "temperature_c": temperature,
        "message": None,
    }


def _sante_nvme(peripherique: str) -> Optional[dict]:
    if "nvme" not in peripherique or not executable_present("nvme"):
        return None
    donnees = executer_json(["nvme", "smart-log", peripherique, "-o", "json"], timeout=8.0)
    if donnees is None:
        return None
    return {
        "temperature_c": donnees.get("temperature"),
        "usure_pourcentage": donnees.get("percentage_used"),
        "avertissements_critiques": donnees.get("critical_warning"),
    }


def sante_disques() -> list:
    resultats = []
    for peripherique in _peripheriques_physiques():
        entree = _sante_smart(peripherique)
        detail_nvme = _sante_nvme(peripherique)
        if detail_nvme:
            entree["nvme"] = detail_nvme
        resultats.append(entree)
    return resultats


def espace_et_usage() -> list:
    return moteur.etat_disques()


def outils_disponibles() -> dict:
    """Pour que l'interface explique honnêtement ce qu'elle peut faire ici,
    plutôt que d'afficher un onglet vide sans dire pourquoi."""
    return {
        "smartctl": executable_present("smartctl"),
        "nvme": executable_present("nvme"),
        "rmlint": executable_present("rmlint"),
        "f3": executable_present("f3read") and executable_present("f3write"),
    }


def chercher_doublons(dossier: Optional[str] = None, limite: int = 200) -> dict:
    """Doublons dans `dossier` (défaut : dossier personnel). Jamais lancé
    automatiquement dans la boucle de sondage — un scan peut prendre du
    temps, c'est une action explicite depuis l'onglet Disques."""
    if not executable_present("rmlint"):
        return {"disponible": False, "doublons": [], "message": "rmlint non installé"}

    cible = dossier or str(Path.home())
    if not Path(cible).is_dir():
        return {"disponible": True, "doublons": [], "message": f"dossier introuvable : {cible}"}

    with tempfile.TemporaryDirectory() as tmp:
        sortie_json = Path(tmp) / "rmlint.json"
        executer(["rmlint", cible, "-o", f"json:{sortie_json}", "-T", "duplicates"], timeout=30.0)
        if not sortie_json.exists():
            return {
                "disponible": True,
                "doublons": [],
                "dossier": cible,
                "message": "aucun résultat (dossier vide, ou trop volumineux — réessayez avec un sous-dossier)",
            }
        try:
            donnees = json.loads(sortie_json.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {"disponible": True, "doublons": [], "dossier": cible, "message": "sortie rmlint illisible"}

    doublons = [
        {"chemin": d.get("path"), "taille_o": d.get("size"), "groupe": d.get("checksum")}
        for d in donnees
        if isinstance(d, dict) and d.get("type") == "duplicate_file"
    ][:limite]
    return {"disponible": True, "doublons": doublons, "dossier": cible, "message": None}


def rapport_disques() -> dict:
    return {
        "sante": sante_disques(),
        "espace": espace_et_usage(),
        "outils": outils_disponibles(),
    }
