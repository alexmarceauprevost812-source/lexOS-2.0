#!/usr/bin/env python3
"""LexOS Pro USB AI — prévol Ollama, strictement en lecture seule.

Ne configure pas Ollama, ne télécharge rien, ne monte aucun volume et
n'écrit jamais sur les disques. Usage : python3 usb-ai/ollama/doctor.py
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

DONNEES = Path("/data")
UNITE = Path("/etc/systemd/system/ollama.service.d/10-lexos-usb-ai.conf")


def verifier(racine=DONNEES, unite=UNITE):
    """Retourne les prérequis détectés ; jamais une autorisation d'écriture."""
    racine = Path(racine)
    unite = Path(unite)
    volume_monte = not racine.is_symlink() and os.path.ismount(str(racine))
    dossier_modeles = volume_monte and (racine / "ollama" / "models").is_dir()
    ollama_installe = shutil.which("ollama") is not None
    unite_presente = unite.is_file()
    pre_requis = all((volume_monte, dossier_modeles, ollama_installe, unite_presente))
    return {
        "lecture_seule": True,
        "racine": str(racine),
        "volume_donnees_monte": bool(volume_monte),
        "dossier_modeles_present": bool(dossier_modeles),
        "ollama_installe": bool(ollama_installe),
        "gabarit_systemd_installe": bool(unite_presente),
        "pre_requis_presents": bool(pre_requis),
        "inference_hors_ligne_testee": False,
        "message": (
            "Pré-requis présents ; il faut encore vérifier les modèles, "
            "les droits d'accès, le service actif et une inférence sans réseau."
            if pre_requis
            else "Préparation incomplète : ne pas activer Ollama sur un dossier "
            "qui n'est pas un volume de données monté."
        ),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Diagnostic Ollama portable sans modification de disque"
    )
    parser.add_argument("--json", action="store_true", help="Sortie JSON")
    parser.add_argument("--strict", action="store_true",
                        help="Code 1 si les prérequis ne sont pas tous présents")
    arguments = parser.parse_args(argv)
    etat = verifier()
    if arguments.json:
        print(json.dumps(etat, indent=2, ensure_ascii=False))
    else:
        print("LEXOS PRO USB AI — PRÉVOL OLLAMA (LECTURE SEULE)")
        for cle in ("volume_donnees_monte", "dossier_modeles_present",
                    "ollama_installe", "gabarit_systemd_installe"):
            print(f"  {cle}: {'oui' if etat[cle] else 'non'}")
        print(etat["message"])
        print("Aucun disque n'a été partitionné, monté ou modifié.")
    return 1 if arguments.strict and not etat["pre_requis_presents"] else 0


if __name__ == "__main__":
    sys.exit(main())
