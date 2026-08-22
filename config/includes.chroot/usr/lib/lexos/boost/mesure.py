"""Mesures avant / après.

Sans chiffres, une optimisation est une promesse. Ce module en prend
quelques-uns, simples et honnêtes, pour que l'utilisateur voie ce qui a
changé au lieu de nous croire sur parole.

Les mesures sont volontairement légères : sur les machines visées, un
banc d'essai lourd fausserait le résultat autant qu'il le mesurerait.
"""

from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass, asdict

from . import systeme
from .materiel import _meminfo


@dataclass
class Mesure:
    """Photographie chiffrée de l'état de la machine."""

    horodatage: float = 0.0
    ram_disponible_mo: int = 0
    ram_utilisee_mo: int = 0
    swap_utilise_mo: int = 0
    disque_libre_go: float = 0.0
    services_actifs: int = 0
    temps_demarrage_s: float | None = None
    lecture_disque_mo_s: float | None = None

    def en_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def depuis_dict(donnees: dict) -> "Mesure":
        connues = {c for c in Mesure.__dataclass_fields__}  # type: ignore[attr-defined]
        return Mesure(**{c: v for c, v in (donnees or {}).items() if c in connues})


def _temps_demarrage() -> float | None:
    """Durée du dernier démarrage, en secondes, via systemd-analyze."""
    if not systeme.commande_existe("systemd-analyze"):
        return None
    code, sortie, _ = systeme.executer(["systemd-analyze", "time"], delai=20)
    if code != 0 or not sortie:
        return None
    # « ... = 24.512s » en fin de première ligne
    correspondance = re.search(r"=\s*([\d.]+)s", sortie)
    if correspondance:
        try:
            return float(correspondance.group(1))
        except ValueError:
            return None
    correspondance = re.search(r"([\d.]+)min\s+([\d.]+)s", sortie)
    if correspondance:
        try:
            return float(correspondance.group(1)) * 60 + float(correspondance.group(2))
        except ValueError:
            return None
    return None


def _services_actifs() -> int:
    if not systeme.systemd_present():
        return 0
    code, sortie, _ = systeme.executer(
        ["systemctl", "list-units", "--type=service", "--state=running", "--no-legend", "--plain"],
        delai=30,
    )
    if code != 0:
        return 0
    return len([l for l in sortie.splitlines() if l.strip()])


def _lecture_disque(disque: str | None, mo: int = 48) -> float | None:
    """Débit de lecture séquentielle brute, en Mo/s.

    Lecture directe (sans passer par le cache) d'une petite zone du
    disque. On lit 48 Mo par défaut : assez pour un chiffre stable, assez
    peu pour ne pas faire attendre une minute sur un disque de 2008.

    Ne modifie rien : lecture seule, et seulement si on est root.
    """
    if not disque or os.geteuid() != 0:
        return None
    peripherique = f"/dev/{disque}"
    if not os.path.exists(peripherique):
        return None

    taille_bloc = 1024 * 1024
    try:
        descripteur = os.open(peripherique, os.O_RDONLY | getattr(os, "O_DIRECT", 0))
    except OSError:
        try:
            descripteur = os.open(peripherique, os.O_RDONLY)
        except OSError:
            return None

    try:
        tampon = None
        debut = time.monotonic()
        lus = 0
        for _ in range(mo):
            tampon = os.pread(descripteur, taille_bloc, lus)
            if not tampon:
                break
            lus += len(tampon)
        duree = time.monotonic() - debut
    except OSError:
        return None
    finally:
        try:
            os.close(descripteur)
        except OSError:
            pass

    if duree <= 0 or lus == 0:
        return None
    return round(lus / duree / 1_000_000, 1)


def prendre(machine=None, complete: bool = False) -> Mesure:
    """Prend une mesure. `complete=True` ajoute le test de lecture disque."""
    infos = _meminfo()
    total = infos.get("MemTotal", 0) // 1024
    disponible = infos.get("MemAvailable", 0) // 1024
    swap_total = infos.get("SwapTotal", 0) // 1024
    swap_libre = infos.get("SwapFree", 0) // 1024

    mesure = Mesure(
        horodatage=time.time(),
        ram_disponible_mo=disponible,
        ram_utilisee_mo=max(total - disponible, 0),
        swap_utilise_mo=max(swap_total - swap_libre, 0),
        services_actifs=_services_actifs(),
        temps_demarrage_s=_temps_demarrage(),
    )

    try:
        stats = os.statvfs("/")
        mesure.disque_libre_go = round(stats.f_bavail * stats.f_frsize / 1_000_000_000, 1)
    except OSError:
        pass

    if complete and machine is not None:
        mesure.lecture_disque_mo_s = _lecture_disque(machine.disque)

    return mesure


# --------------------------------------------------------------------------
# comparaison
# --------------------------------------------------------------------------

def comparer(avant: Mesure, apres: Mesure) -> list[str]:
    """Différences lisibles entre deux mesures, en français simple."""
    lignes: list[str] = []

    delta_ram = apres.ram_disponible_mo - avant.ram_disponible_mo
    if abs(delta_ram) >= 20:
        sens = "libérés" if delta_ram > 0 else "consommés en plus"
        lignes.append(f"mémoire vive : {abs(delta_ram)} Mo {sens}")

    delta_disque = apres.disque_libre_go - avant.disque_libre_go
    if abs(delta_disque) >= 0.1:
        sens = "récupérés" if delta_disque > 0 else "occupés en plus"
        lignes.append(f"espace disque : {abs(delta_disque):.1f} Go {sens}")

    delta_services = apres.services_actifs - avant.services_actifs
    if delta_services:
        sens = "arrêtés" if delta_services < 0 else "démarrés"
        lignes.append(f"services : {abs(delta_services)} {sens}")

    if avant.temps_demarrage_s and apres.temps_demarrage_s:
        delta = avant.temps_demarrage_s - apres.temps_demarrage_s
        if abs(delta) >= 0.5:
            sens = "gagnées" if delta > 0 else "perdues"
            lignes.append(f"démarrage : {abs(delta):.1f} s {sens}")

    if avant.lecture_disque_mo_s and apres.lecture_disque_mo_s:
        delta = apres.lecture_disque_mo_s - avant.lecture_disque_mo_s
        if abs(delta) >= 1:
            sens = "plus rapide" if delta > 0 else "plus lent"
            lignes.append(f"lecture disque : {abs(delta):.1f} Mo/s {sens}")

    if not lignes:
        lignes.append(
            "rien de mesurable dans l'immédiat — plusieurs réglages "
            "(démarrage, disque) ne se voient qu'au prochain redémarrage"
        )
    return lignes


def resumer(mesure: Mesure) -> list[str]:
    """Mesure isolée, présentée simplement."""
    lignes = [
        f"mémoire disponible : {mesure.ram_disponible_mo} Mo",
        f"espace disque libre : {mesure.disque_libre_go:.1f} Go",
        f"services en fonctionnement : {mesure.services_actifs}",
    ]
    if mesure.swap_utilise_mo:
        lignes.append(f"mémoire déchargée : {mesure.swap_utilise_mo} Mo")
    if mesure.temps_demarrage_s:
        lignes.append(f"dernier démarrage : {mesure.temps_demarrage_s:.1f} s")
    if mesure.lecture_disque_mo_s:
        lignes.append(f"lecture disque : {mesure.lecture_disque_mo_s} Mo/s")
    return lignes
