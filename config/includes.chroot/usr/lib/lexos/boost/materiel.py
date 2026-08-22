"""Détection matérielle pour LexOS Boost.

Aucune dépendance externe : uniquement /proc, /sys et la bibliothèque
standard. Doit fonctionner sur un live USB sans réseau et sans paquet
supplémentaire installé.

Toutes les valeurs sont lues de façon défensive : sur du vieux matériel,
des fichiers /sys attendus peuvent être absents. Une lecture ratée donne
None, jamais une exception.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field, asdict


# --------------------------------------------------------------------------
# petits utilitaires de lecture tolérants
# --------------------------------------------------------------------------

def _lire(chemin: str) -> str | None:
    """Contenu d'un fichier texte, ou None si illisible."""
    try:
        with open(chemin, "r", encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except (OSError, UnicodeError):
        return None


def _lire_entier(chemin: str) -> int | None:
    brut = _lire(chemin)
    if brut is None:
        return None
    try:
        return int(brut.split()[0])
    except (ValueError, IndexError):
        return None


def _existe(commande: str) -> bool:
    """La commande est-elle disponible dans le PATH ?"""
    return shutil.which(commande) is not None


def _sortie(argv: list[str], delai: int = 5) -> str | None:
    """Exécute une commande et renvoie sa sortie, ou None si elle échoue."""
    try:
        res = subprocess.run(
            argv, capture_output=True, text=True, timeout=delai, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0:
        return None
    return res.stdout.strip()


# --------------------------------------------------------------------------
# mémoire
# --------------------------------------------------------------------------

def _meminfo() -> dict[str, int]:
    """/proc/meminfo en dictionnaire, valeurs en kio."""
    infos: dict[str, int] = {}
    brut = _lire("/proc/meminfo")
    if not brut:
        return infos
    for ligne in brut.splitlines():
        cle, _, reste = ligne.partition(":")
        morceaux = reste.split()
        if not morceaux:
            continue
        try:
            infos[cle.strip()] = int(morceaux[0])
        except ValueError:
            continue
    return infos


# --------------------------------------------------------------------------
# disque
# --------------------------------------------------------------------------

def _disque_racine() -> str | None:
    """Nom du disque physique qui porte / (ex. « sda », « nvme0n1 »).

    On part du périphérique monté sur /, puis on remonte les couches
    (partition -> disque, LVM/LUKS -> disque sous-jacent) via /sys/block.
    """
    try:
        st = os.stat("/")
    except OSError:
        return None
    majeur, mineur = os.major(st.st_dev), os.minor(st.st_dev)

    depart = f"/sys/dev/block/{majeur}:{mineur}"
    if not os.path.exists(depart):
        return None

    vu: set[str] = set()
    courant = depart
    for _ in range(8):  # garde-fou contre une boucle de mappings
        reel = os.path.realpath(courant)
        if reel in vu:
            break
        vu.add(reel)

        # une partition possède un lien « ../ » vers son disque parent
        parent = os.path.join(reel, "..")
        if os.path.exists(os.path.join(reel, "partition")):
            courant = parent
            continue

        # device-mapper (LVM, LUKS) : descendre vers l'esclave
        esclaves = os.path.join(reel, "slaves")
        if os.path.isdir(esclaves):
            entrees = sorted(os.listdir(esclaves))
            if entrees:
                courant = os.path.join(esclaves, entrees[0])
                continue

        nom = os.path.basename(reel)
        return nom if nom and os.path.exists(f"/sys/block/{nom}") else None
    return None


def _type_disque(nom: str | None) -> str:
    """« ssd », « nvme », « emmc », « hdd » ou « inconnu »."""
    if not nom:
        return "inconnu"
    if nom.startswith("nvme"):
        return "nvme"
    if nom.startswith("mmcblk"):
        return "emmc"
    rotationnel = _lire_entier(f"/sys/block/{nom}/queue/rotational")
    if rotationnel == 0:
        return "ssd"
    if rotationnel == 1:
        return "hdd"
    return "inconnu"


def _ordonnanceur(nom: str | None) -> tuple[str | None, list[str]]:
    """Ordonnanceur d'E/S actif et liste des choix disponibles."""
    if not nom:
        return None, []
    brut = _lire(f"/sys/block/{nom}/queue/scheduler")
    if not brut:
        return None, []
    dispo = [m.strip("[]") for m in brut.split()]
    actif = next((m.strip("[]") for m in brut.split() if m.startswith("[")), None)
    return actif, dispo


# --------------------------------------------------------------------------
# processeur
# --------------------------------------------------------------------------

def _modele_cpu() -> str | None:
    brut = _lire("/proc/cpuinfo")
    if not brut:
        return None
    for ligne in brut.splitlines():
        if ligne.lower().startswith(("model name", "hardware", "processor\t: ")):
            _, _, valeur = ligne.partition(":")
            valeur = valeur.strip()
            if valeur and not valeur.isdigit():
                return valeur
    return None


def _annee_cpu(modele: str | None) -> int | None:
    """Estimation grossière de la génération, pour situer l'âge de la machine.

    On ne cherche pas la précision : juste distinguer « très vieux »,
    « vieux » et « récent ». Renvoie None si on ne sait pas.
    """
    if not modele:
        return None
    m = modele.lower()

    # Intel Core i3/i5/i7/i9 : le chiffre après le tiret donne la génération
    correspondance = re.search(r"i[3579][- ]\s?(\d{4,5})", m)
    if correspondance:
        numero = correspondance.group(1)
        generation = int(numero[:-3]) if len(numero) == 4 else int(numero[:-3])
        # gen 1 = 2010, +1 an par génération (approximation volontaire)
        return min(2010 + max(generation - 1, 0), 2025)

    # familles clairement anciennes
    for motif, annee in (
        ("pentium 4", 2003), ("pentium d", 2005), ("core 2", 2007),
        ("pentium dual", 2007), ("atom", 2009), ("celeron", 2011),
        ("pentium", 2010), ("phenom", 2009), ("athlon", 2008),
    ):
        if motif in m:
            return annee

    if "ryzen" in m:
        return 2018
    return None


# --------------------------------------------------------------------------
# le portrait complet de la machine
# --------------------------------------------------------------------------

@dataclass
class Machine:
    """Portrait matériel de la machine, tel que le moteur le voit."""

    ram_mo: int = 0
    ram_disponible_mo: int = 0
    swap_mo: int = 0
    zram_actif: bool = False

    cpu_modele: str | None = None
    cpu_coeurs: int = 1
    cpu_annee_estimee: int | None = None
    gouverneurs_disponibles: list[str] = field(default_factory=list)
    gouverneur_actif: str | None = None

    disque: str | None = None
    disque_type: str = "inconnu"
    disque_taille_go: float = 0.0
    disque_libre_go: float = 0.0
    ordonnanceur_actif: str | None = None
    ordonnanceurs_disponibles: list[str] = field(default_factory=list)

    portable: bool = False
    session_graphique: bool = False
    bureau: str | None = None
    compositeur_actif: bool | None = None

    a_bluetooth: bool = False
    a_imprimante_usb: bool = False
    live_usb: bool = False
    systemd: bool = False

    def resume(self) -> str:
        """Une ligne lisible par un humain."""
        chassis = "portable" if self.portable else "ordinateur fixe"
        age = f"~{self.cpu_annee_estimee}" if self.cpu_annee_estimee else "âge inconnu"
        return (
            f"{self.ram_mo} Mo de RAM · {self.cpu_coeurs} cœur(s) "
            f"({self.cpu_modele or 'processeur inconnu'}, {age}) · "
            f"disque {self.disque_type} {self.disque_taille_go:.0f} Go · {chassis}"
        )

    def en_dict(self) -> dict:
        return asdict(self)


def _est_portable() -> bool:
    """Présence d'une batterie ou châssis déclaré portable."""
    chassis = _lire("/sys/class/dmi/id/chassis_type")
    if chassis and chassis.isdigit():
        # 8=portable, 9=laptop, 10=notebook, 11=handheld, 14=sub-notebook
        if int(chassis) in (8, 9, 10, 11, 14, 30, 31, 32):
            return True
    alim = "/sys/class/power_supply"
    if os.path.isdir(alim):
        for entree in os.listdir(alim):
            if _lire(f"{alim}/{entree}/type") == "Battery":
                return True
    return False


def _est_live() -> bool:
    """La session tourne-t-elle depuis un live USB (système en lecture seule) ?"""
    montages = _lire("/proc/mounts") or ""
    for ligne in montages.splitlines():
        morceaux = ligne.split()
        if len(morceaux) >= 3 and morceaux[1] == "/" and morceaux[2] in ("overlay", "aufs", "squashfs"):
            return True
    return os.path.exists("/run/live/medium")


def _bureau() -> str | None:
    for variable in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION"):
        valeur = os.environ.get(variable)
        if valeur:
            return valeur
    return None


def _compositeur_xfce() -> bool | None:
    """État du compositeur XFCE, None si xfconf n'est pas joignable."""
    if not _existe("xfconf-query"):
        return None
    sortie = _sortie(["xfconf-query", "-c", "xfwm4", "-p", "/general/use_compositing"])
    if sortie is None:
        return None
    return sortie.strip().lower() == "true"


def detecter() -> Machine:
    """Construit le portrait de la machine courante."""
    m = Machine()

    infos = _meminfo()
    m.ram_mo = infos.get("MemTotal", 0) // 1024
    m.ram_disponible_mo = infos.get("MemAvailable", 0) // 1024
    m.swap_mo = infos.get("SwapTotal", 0) // 1024
    m.zram_actif = any(
        n.startswith("zram") for n in (os.listdir("/sys/block") if os.path.isdir("/sys/block") else [])
    ) and m.swap_mo > 0

    m.cpu_modele = _modele_cpu()
    m.cpu_coeurs = os.cpu_count() or 1
    m.cpu_annee_estimee = _annee_cpu(m.cpu_modele)

    base_cpu = "/sys/devices/system/cpu/cpu0/cpufreq"
    dispo = _lire(f"{base_cpu}/scaling_available_governors")
    m.gouverneurs_disponibles = dispo.split() if dispo else []
    m.gouverneur_actif = _lire(f"{base_cpu}/scaling_governor")

    m.disque = _disque_racine()
    m.disque_type = _type_disque(m.disque)
    if m.disque:
        secteurs = _lire_entier(f"/sys/block/{m.disque}/size")
        if secteurs:
            m.disque_taille_go = secteurs * 512 / 1_000_000_000
    m.ordonnanceur_actif, m.ordonnanceurs_disponibles = _ordonnanceur(m.disque)
    try:
        stats = os.statvfs("/")
        m.disque_libre_go = stats.f_bavail * stats.f_frsize / 1_000_000_000
    except OSError:
        pass

    m.portable = _est_portable()
    m.session_graphique = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    m.bureau = _bureau()
    m.compositeur_actif = _compositeur_xfce()

    m.a_bluetooth = os.path.isdir("/sys/class/bluetooth") and bool(os.listdir("/sys/class/bluetooth"))
    m.a_imprimante_usb = _detecter_imprimante()
    m.live_usb = _est_live()
    m.systemd = os.path.isdir("/run/systemd/system")

    return m


def _detecter_imprimante() -> bool:
    """Une imprimante USB est-elle branchée ? (classe USB 7 = printer)"""
    racine = "/sys/bus/usb/devices"
    if not os.path.isdir(racine):
        return False
    try:
        entrees = os.listdir(racine)
    except OSError:
        return False
    for entree in entrees:
        classe = _lire(f"{racine}/{entree}/bInterfaceClass")
        if classe and classe.strip() == "07":
            return True
    return False


if __name__ == "__main__":  # petit test manuel : python3 materiel.py
    import json
    machine = detecter()
    print(machine.resume())
    print(json.dumps(machine.en_dict(), indent=2, ensure_ascii=False))
