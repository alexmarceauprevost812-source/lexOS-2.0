"""LexOS Diagnostic — moteur de collecte : l'état complet de la machine, en direct.

C'est l'outil « lexos-materiel » prévu dans lexos-outils-a-ajouter.md :
« Ma machine en une page » + un bouton « mettre à jour le firmware ».

NOTE D'INTÉGRATION — chevauchement possible avec LexOS Boost
--------------------------------------------------------------
Le dépôt contient déjà usr/lib/lexos/boost/materiel.py, systeme.py et
mesure.py (voir lexos-audit-parametres-scan.md). Cette session n'a pas pu
lire leur contenu : dans Supabase, la colonne `contenu` de la table
lexos_fichiers est vide sur les 403 lignes, et le dépôt GitHub répond en
privé. Ce moteur a donc été écrit de façon autonome, sans supposer ce que
Boost fait déjà en dessous.

Avant d'intégrer pour de vrai : comparez avec boost/materiel.py et
boost/mesure.py. S'ils couvrent déjà CPU/RAM/GPU/température par un autre
chemin, préférez IMPORTER ce qu'ils exposent plutôt que de faire tourner
deux moteurs de mesure séparés sur la même machine — exactement le genre de
duplication que vos propres audits signalent ailleurs (lexos-boost et les
Paramètres qui vivent déjà « à côté » l'un de l'autre plutôt qu'ensemble).

Dépendance ajoutée : python3-psutil (à ajouter à 57-python.list ou
59-diagnostic.list — voir integration/59-diagnostic.list fourni à côté).
"""
from __future__ import annotations

import os
import platform
import socket
import threading
import time
from pathlib import Path
from typing import Optional

import psutil

from utils import executable_present, executer, lire_gpu_conf, lire_version_lexos

# --------------------------------------------------------------------------
# Amorçage : psutil calcule les pourcentages CPU / par-processus comme un
# delta depuis le dernier appel. Le tout premier appel n'a rien à comparer
# et renvoie 0 — on l'amorce donc une fois au chargement du module plutôt
# que de laisser le premier instantané mentir à l'utilisateur.
# --------------------------------------------------------------------------
psutil.cpu_percent(percpu=False)
psutil.cpu_percent(percpu=True)

_processus_connus: dict = {}
_reseau_precedent: Optional[dict] = None

# Le serveur (serveur.py) tourne en ThreadingHTTPServer : deux requêtes
# /api/etat en parallèle (deux onglets ouverts, par ex.) ne doivent pas se
# marcher dessus sur _processus_connus / _reseau_precedent.
_verrou = threading.Lock()


# --------------------------------------------------------------------------
# Système
# --------------------------------------------------------------------------

def etat_systeme() -> dict:
    demarrage = psutil.boot_time()
    return {
        "nom_machine": socket.gethostname(),
        "version_lexos": lire_version_lexos(),
        "noyau": platform.release(),
        "demarrage_epoch": demarrage,
        "temps_actif_s": round(time.time() - demarrage),
        "temperature_generale_c": _temperature_cpu(),
    }


# --------------------------------------------------------------------------
# CPU
# --------------------------------------------------------------------------

def _modele_cpu() -> str:
    try:
        for ligne in Path("/proc/cpuinfo").read_text(encoding="utf-8").splitlines():
            if ligne.lower().startswith("model name"):
                return ligne.split(":", 1)[1].strip()
    except OSError:
        pass
    return "inconnu"


def _temperature_cpu() -> Optional[float]:
    try:
        capteurs = psutil.sensors_temperatures()
    except (AttributeError, OSError):
        capteurs = {}
    for cle in ("coretemp", "k10temp", "zenpower", "cpu_thermal"):
        if cle in capteurs and capteurs[cle]:
            valeurs = [c.current for c in capteurs[cle] if c.current is not None]
            if valeurs:
                return round(sum(valeurs) / len(valeurs), 1)
    for entrees in capteurs.values():
        valeurs = [c.current for c in entrees if c.current is not None]
        if valeurs:
            return round(sum(valeurs) / len(valeurs), 1)
    return None


def etat_cpu() -> dict:
    frequence = None
    try:
        frequence = psutil.cpu_freq()
    except (OSError, FileNotFoundError):
        pass
    try:
        charge = list(os.getloadavg())
    except (OSError, AttributeError):
        charge = None

    return {
        "modele": _modele_cpu(),
        "coeurs_physiques": psutil.cpu_count(logical=False),
        "coeurs_logiques": psutil.cpu_count(logical=True),
        "frequence_actuelle_mhz": round(frequence.current) if frequence else None,
        "frequence_max_mhz": round(frequence.max) if frequence and frequence.max else None,
        "utilisation_globale_pct": psutil.cpu_percent(percpu=False),
        "utilisation_par_coeur_pct": psutil.cpu_percent(percpu=True),
        "charge_1_5_15": charge,
        "temperature_c": _temperature_cpu(),
    }


# --------------------------------------------------------------------------
# RAM
# --------------------------------------------------------------------------

def etat_ram() -> dict:
    vm = psutil.virtual_memory()
    swap = psutil.swap_memory()
    return {
        "total_o": vm.total,
        "utilise_o": vm.used,
        "disponible_o": vm.available,
        "pourcentage": vm.percent,
        "swap_total_o": swap.total,
        "swap_utilise_o": swap.used,
        "swap_pourcentage": swap.percent,
    }


# --------------------------------------------------------------------------
# GPU — tient compte de /etc/lexos/gpu.conf (voir lexos-bug-rtx5060.md) :
# sur RTX 50 / Blackwell en pilote nouveau ou en mode sûr, nvidia-smi n'a
# rien à dire et il ne faut pas le faire échouer bruyamment pour ça.
# --------------------------------------------------------------------------

def etat_gpu() -> dict:
    conf = lire_gpu_conf()
    mode = conf.get("gpu_mode", "inconnu")

    if executable_present("nvidia-smi"):
        sortie = executer([
            "nvidia-smi",
            "--query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,fan.speed",
            "--format=csv,noheader,nounits",
        ])
        if sortie and sortie.strip():
            parts = [p.strip() for p in sortie.strip().splitlines()[0].split(",")]
            if len(parts) == 7:
                nom, temp, util, vram_u, vram_t, puissance, ventilo = parts

                def _f(v):
                    try:
                        return float(v)
                    except ValueError:
                        return None

                vram_u_f, vram_t_f = _f(vram_u), _f(vram_t)
                return {
                    "disponible": True,
                    "mode": mode if mode != "inconnu" else "nvidia",
                    "nom": nom,
                    "temperature_c": _f(temp),
                    "utilisation_pct": _f(util),
                    "vram_utilisee_o": vram_u_f * 1024 * 1024 if vram_u_f is not None else None,
                    "vram_totale_o": vram_t_f * 1024 * 1024 if vram_t_f is not None else None,
                    "puissance_w": _f(puissance),
                    "ventilateur_pct": _f(ventilo),
                    "message": None,
                }

    nom_carte = None
    if executable_present("lspci"):
        sortie = executer(["lspci", "-nn"])
        if sortie:
            for ligne in sortie.splitlines():
                if "VGA" in ligne or "3D controller" in ligne:
                    nom_carte = ligne.split(": ", 1)[-1]
                    break

    if mode == "nouveau":
        message = "Pilote nouveau actif : mesures GPU indisponibles. Le pilote NVIDIA propriétaire n'a pas été retenu au démarrage (voir lexos-materiel → Firmware)."
    elif mode == "safe":
        message = "Démarré en mode sûr (nomodeset) : aucune mesure GPU en mode sûr."
    elif not executable_present("nvidia-smi"):
        message = "nvidia-smi indisponible sur cette machine."
    else:
        message = "État du GPU indisponible."

    return {
        "disponible": False,
        "mode": mode,
        "nom": nom_carte,
        "temperature_c": None,
        "utilisation_pct": None,
        "vram_utilisee_o": None,
        "vram_totale_o": None,
        "puissance_w": None,
        "ventilateur_pct": None,
        "message": message,
    }


# --------------------------------------------------------------------------
# Ventilateurs — tout le système, pas seulement le GPU : CPU, boîtier, etc.
# via les capteurs lm-sensors exposés par psutil (nécessite le paquet
# lm-sensors + `sensors-detect` déjà exécuté une fois sur la machine).
# --------------------------------------------------------------------------

def etat_ventilateurs() -> list:
    try:
        capteurs = psutil.sensors_fans()
    except (AttributeError, OSError):
        capteurs = {}
    resultats = []
    for puce, entrees in capteurs.items():
        for entree in entrees:
            resultats.append({
                "puce": puce,
                "nom": entree.label or puce,
                "vitesse_rpm": entree.current,
            })
    # Le ventilateur GPU (en %, pas en RPM) est déjà dans etat_gpu() —
    # on ne le duplique pas ici, l'interface les affiche côte à côte.
    return resultats


# --------------------------------------------------------------------------
# Disques — espace et point de montage seulement ; santé SMART/NVMe dans
# disques.py (plus lent, appelé à la demande plutôt qu'à chaque sondage).
# --------------------------------------------------------------------------

def etat_disques() -> list:
    resultats = []
    try:
        partitions = psutil.disk_partitions(all=False)
    except OSError:
        partitions = []
    for part in partitions:
        if "cdrom" in part.opts or not part.fstype:
            continue
        try:
            usage = psutil.disk_usage(part.mountpoint)
        except (PermissionError, OSError):
            continue
        resultats.append({
            "point_montage": part.mountpoint,
            "peripherique": part.device,
            "type_fs": part.fstype,
            "total_o": usage.total,
            "utilise_o": usage.used,
            "pourcentage": usage.percent,
        })
    return resultats


# --------------------------------------------------------------------------
# Réseau — débit en direct, calculé par différence entre deux sondages.
# --------------------------------------------------------------------------

def etat_reseau() -> dict:
    global _reseau_precedent
    maintenant = time.time()
    try:
        compteurs = psutil.net_io_counters(pernic=True)
        adresses = psutil.net_if_addrs()
        stats = psutil.net_if_stats()
    except OSError:
        return {"interfaces": [], "ssid_wifi": None}

    precedent = _reseau_precedent
    delta_t = None
    if precedent is not None:
        ecart = maintenant - precedent["temps"]
        delta_t = ecart if ecart > 0 else None

    interfaces_info = []
    for nom, compteur in compteurs.items():
        if nom == "lo":
            continue
        envoi_s = reception_s = 0.0
        if precedent and delta_t and nom in precedent["compteurs"]:
            avant = precedent["compteurs"][nom]
            envoi_s = max(0.0, (compteur.bytes_sent - avant.bytes_sent) / delta_t)
            reception_s = max(0.0, (compteur.bytes_recv - avant.bytes_recv) / delta_t)

        adresse_ip = None
        for a in adresses.get(nom, []):
            if a.family == socket.AF_INET:
                adresse_ip = a.address
        actif = stats[nom].isup if nom in stats else False

        interfaces_info.append({
            "nom": nom,
            "actif": actif,
            "adresse_ip": adresse_ip,
            "envoi_octets_s": round(envoi_s),
            "reception_octets_s": round(reception_s),
        })

    _reseau_precedent = {"temps": maintenant, "compteurs": compteurs}

    ssid = None
    if executable_present("nmcli"):
        sortie = executer(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"])
        if sortie:
            for ligne in sortie.splitlines():
                debut = ligne.split(":", 1)[0].lower()
                if debut in ("oui", "yes"):
                    ssid = ligne.split(":", 1)[1]
                    break

    return {"interfaces": interfaces_info, "ssid_wifi": ssid}


# --------------------------------------------------------------------------
# Batterie
# --------------------------------------------------------------------------

def etat_batterie() -> dict:
    try:
        batterie = psutil.sensors_battery()
    except (AttributeError, OSError):
        batterie = None
    if batterie is None:
        return {"presente": False}
    secondes = batterie.secsleft
    if secondes in (psutil.POWER_TIME_UNLIMITED, psutil.POWER_TIME_UNKNOWN):
        secondes = None
    return {
        "presente": True,
        "pourcentage": round(batterie.percent, 1),
        "branche": bool(batterie.power_plugged),
        "secondes_restantes": secondes,
    }


# --------------------------------------------------------------------------
# Processus — amorçage correct de psutil : on retient les objets Process
# d'un sondage à l'autre pour que cpu_percent() mesure un vrai delta.
# --------------------------------------------------------------------------

def _mettre_a_jour_processus() -> list:
    try:
        pids_actuels = set(psutil.pids())
    except OSError:
        return list(_processus_connus.values())

    for pid in list(_processus_connus):
        if pid not in pids_actuels:
            del _processus_connus[pid]

    for pid in pids_actuels:
        if pid not in _processus_connus:
            try:
                p = psutil.Process(pid)
                p.cpu_percent(None)  # amorce ; 0.0 tant qu'un 2e relevé n'a pas eu lieu
                _processus_connus[pid] = p
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
    return list(_processus_connus.values())


def etat_processus(top_n: int = 8) -> dict:
    releves = []
    for p in _mettre_a_jour_processus():
        try:
            releves.append({
                "pid": p.pid,
                "nom": p.name(),
                "cpu_pct": round(p.cpu_percent(None), 1),
                "ram_pct": round(p.memory_percent(), 1),
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    return {
        "top_cpu": sorted(releves, key=lambda r: r["cpu_pct"], reverse=True)[:top_n],
        "top_ram": sorted(releves, key=lambda r: r["ram_pct"], reverse=True)[:top_n],
    }


# --------------------------------------------------------------------------
# L'instantané complet — c'est ce que /api/etat renvoie tel quel.
# --------------------------------------------------------------------------

def instantane() -> dict:
    with _verrou:
        return {
            "horodatage": time.time(),
            "systeme": etat_systeme(),
            "cpu": etat_cpu(),
            "ram": etat_ram(),
            "gpu": etat_gpu(),
            "ventilateurs": etat_ventilateurs(),
            "disques": etat_disques(),
            "reseau": etat_reseau(),
            "batterie": etat_batterie(),
            "processus": etat_processus(),
        }
