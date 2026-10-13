#!/usr/bin/env python3
"""LexOS Pro USB AI : inventaire en lecture seule des disques.

Cette phase ne choisit jamais de disque cible, ne monte rien et n'écrit rien.
Elle emploie uniquement lsblk pour afficher le matériel présent.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any

LSBLK_CMD = [
    "lsblk", "--json", "--bytes", "--output",
    "NAME,PATH,TYPE,SIZE,TRAN,MODEL,RO,RM,FSTYPE,MOUNTPOINTS",
]


def _texte(valeur: Any) -> str:
    """Neutralise les caractères de contrôle d'un nom de matériel."""
    sans_controles = "".join(c if c.isprintable() else " " for c in str(valeur or ""))
    return " ".join(sans_controles.split())


def _montages(arbre: dict[str, Any]) -> set[str]:
    montages: set[str] = set()
    valeurs = arbre.get("mountpoints")
    if isinstance(valeurs, list):
        montages.update(_texte(p) for p in valeurs if p)
    elif valeurs:
        montages.add(_texte(valeurs))
    if arbre.get("mountpoint"):
        montages.add(_texte(arbre["mountpoint"]))
    for enfant in arbre.get("children") or []:
        if isinstance(enfant, dict):
            montages.update(_montages(enfant))
    return montages


def analyser(contenu: dict[str, Any]) -> list[dict[str, Any]]:
    """Analyse les données lsblk sans jamais élire une cible d'installation."""
    if not isinstance(contenu, dict) or not isinstance(contenu.get("blockdevices"), list):
        raise ValueError("Réponse lsblk invalide : 'blockdevices' absent")

    disques: list[dict[str, Any]] = []
    for entree in contenu["blockdevices"]:
        if not isinstance(entree, dict) or entree.get("type") != "disk":
            continue
        montages = sorted(_montages(entree))
        transport = _texte(entree.get("tran")).lower() or "inconnu"
        racine = "/" in montages
        if racine:
            statut = "SYSTÈME EN COURS — NE PAS TOUCHER"
        elif montages:
            statut = "PARTITIONS MONTÉES — NE PAS MODIFIER"
        elif transport == "usb":
            statut = "USB DÉTECTÉ — IDENTITÉ À CONFIRMER"
        else:
            statut = "INTERNE OU INCONNU — NE PAS TOUCHER"
        try:
            taille = max(0, int(entree.get("size") or 0))
        except (TypeError, ValueError):
            taille = 0
        disque = {
            "chemin": _texte(entree.get("path") or entree.get("name") or "?"),
            "taille_octets": taille,
            "transport": transport,
            "modele": _texte(entree.get("model")) or "inconnu",
            "montages": montages,
            "lecture_seule": str(entree.get("ro") or 0) in ("1", "True", "true"),
            "statut": statut,
        }
        disques.append(disque)
    return disques


def afficher(disques: list[dict[str, Any]]) -> None:
    print("LEXOS PRO USB AI — INVENTAIRE LECTURE SEULE")
    print("Aucune commande de partitionnement, d'installation ni d'effacement.")
    if not disques:
        print("Aucun disque détecté. Aucune action effectuée.")
        return
    for d in disques:
        gib = d["taille_octets"] / 1024**3
        print(f"\nPériphérique : {d['chemin']} | {gib:.1f} Gio | {d['transport']}")
        print(f"Modèle       : {d['modele']}")
        print(f"Montages     : {', '.join(d['montages']) if d['montages'] else 'aucun signalé'}")
        print(f"État         : {d['statut']}")
    print("\nATTENTION : cette liste ne garantit JAMAIS qu'un disque peut être effacé.")
    print("Ne pas utiliser ces chemins avec dd, mkfs, parted ou un installateur.")
    print("Un SSD vendu comme 1 To représente environ 931 Gio avant formatage.")


def main() -> int:
    p = argparse.ArgumentParser(description="Inventaire USB et disques, sans écriture")
    p.add_argument("--json", action="store_true", help="Sortie JSON, sans écriture")
    args = p.parse_args()
    try:
        resultat = subprocess.run(LSBLK_CMD, capture_output=True, text=True, check=True)
        disques = analyser(json.loads(resultat.stdout))
    except (FileNotFoundError, subprocess.CalledProcessError, ValueError, json.JSONDecodeError) as erreur:
        print(f"Échec de l'inventaire en lecture seule : {erreur}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"lecture_seule": True, "disques": disques}, ensure_ascii=False, indent=2))
    else:
        afficher(disques)
    return 0


if __name__ == "__main__":
    sys.exit(main())
