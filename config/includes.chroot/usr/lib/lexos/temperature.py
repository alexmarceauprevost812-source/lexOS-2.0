#!/usr/bin/env python3
"""
LexOS — Températures et ventilateurs, en direct.

POURQUOI

Sur une machine de jeu compacte comme l'Alienware Aurora, la chaleur décide
de tout. Un processeur qui atteint sa limite ne plante pas : il RALENTIT, en
silence. On croit alors que le jeu est mal optimisé, ou que la carte
graphique est trop faible, alors qu'il suffisait de nettoyer un ventilateur.
Sans chiffres, « ça rame » reste une impression.

D'OÙ VIENNENT LES CHIFFRES

  · /sys/class/hwmon — le noyau Linux y expose TOUS les capteurs de la carte
    mère : cœurs du processeur, ventilateurs, disques NVMe, châssis. C'est
    lu directement, sans aucun paquet à installer et sans droits root.
    (« sensors », de lm-sensors, lit exactement la même chose ; on évite
    ainsi une dépendance et l'analyse d'un texte qui change de forme.)
  · nvidia-smi — pour la carte graphique : température, ventilateur, charge,
    mémoire vidéo utilisée. Livré avec le pilote NVIDIA, donc déjà là.

LA MÉMOIRE VIDÉO EST ICI POUR UNE RAISON

La RTX 5060 a 8 Go. Quand un jeu les remplit, il ne tombe pas en panne : il
se met à saccader. Voir « 7,8 / 8,0 Go » à l'écran explique d'un coup d'œil
un problème qu'on mettrait des heures à deviner.

PRUDENCE

Chaque source est isolée. Pas de NVIDIA, pas de capteur de ventilateur,
noyau qui range ses fichiers autrement : la source concernée rend une liste
vide et les autres continuent de s'afficher.

    python3 temperature.py            un relevé, en texte
    python3 temperature.py --json     un relevé, en JSON
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HWMON = Path(os.environ.get("LEXOS_HWMON", "/sys/class/hwmon"))

#  Seuils d'alerte, en °C. Ce ne sont pas des limites matérielles (un
#  processeur moderne se protège tout seul vers 100 °C) mais le seuil à
#  partir duquel la machine commence à se brider, donc à perdre des images
#  par seconde. C'est ce qui intéresse un joueur.
SEUILS = {"processeur": (80, 90), "carte graphique": (80, 87),
          "disque": (60, 70), "machine": (75, 85)}


def _lire(chemin, defaut=None):
    """Lit un fichier de /sys sans jamais lever d'exception : un capteur peut
    disparaître entre le moment où on le liste et celui où on le lit."""
    try:
        return chemin.read_text(errors="replace").strip()
    except OSError:
        return defaut


def _entier(chemin):
    valeur = _lire(chemin)
    if valeur is None:
        return None
    try:
        return int(valeur)
    except ValueError:
        return None


def _famille(nom_puce, etiquette):
    """Range un capteur dans une famille lisible, à partir du nom que le
    noyau donne à la puce. « coretemp » ne dit rien à personne ;
    « processeur », si."""
    n = (nom_puce or "").lower()
    e = (etiquette or "").lower()
    if n in ("coretemp", "k10temp", "zenpower", "cpu_thermal") or "package" in e:
        return "processeur"
    if n.startswith("nvme") or n in ("drivetemp",):
        return "disque"
    if n in ("amdgpu", "nouveau", "radeon", "i915"):
        return "carte graphique"
    return "machine"


def _niveau(famille, valeur):
    tiede, chaud = SEUILS.get(famille, SEUILS["machine"])
    if valeur >= chaud:
        return "chaud"
    if valeur >= tiede:
        return "tiede"
    return "ok"


# =============================================================================
#  Capteurs de la carte mère (processeur, disques, châssis, ventilateurs)
# =============================================================================

def capteurs():
    temperatures, ventilateurs = [], []
    try:
        puces = sorted(HWMON.glob("hwmon*"))
    except OSError:
        return temperatures, ventilateurs

    for puce in puces:
        nom_puce = _lire(puce / "name", "") or ""

        # --- Températures ---------------------------------------------------
        try:
            entrees = sorted(puce.glob("temp*_input"))
        except OSError:
            entrees = []
        for entree in entrees:
            brut = _entier(entree)
            #  Le noyau donne des millidegrés. Une valeur nulle ou absurde
            #  signale un capteur non branché : on l'écarte plutôt que
            #  d'afficher « 0 °C » et d'inquiéter pour rien.
            if brut is None or brut <= 0 or brut > 200_000:
                continue
            prefixe = entree.name[:-len("_input")]
            etiquette = _lire(puce / f"{prefixe}_label", "") or ""
            famille = _famille(nom_puce, etiquette)
            valeur = round(brut / 1000.0, 1)
            temperatures.append({
                "nom": etiquette or nom_puce or prefixe,
                "puce": nom_puce,
                "famille": famille,
                "valeur": valeur,
                "unite": "°C",
                "niveau": _niveau(famille, valeur),
            })

        # --- Ventilateurs ---------------------------------------------------
        try:
            souffles = sorted(puce.glob("fan*_input"))
        except OSError:
            souffles = []
        for souffle in souffles:
            tours = _entier(souffle)
            if tours is None or tours < 0:
                continue
            prefixe = souffle.name[:-len("_input")]
            etiquette = _lire(puce / f"{prefixe}_label", "") or ""
            ventilateurs.append({
                "nom": etiquette or f"{nom_puce} {prefixe}",
                "puce": nom_puce,
                "valeur": tours,
                "unite": "tr/min",
                #  Un ventilateur à 0 n'est pas forcément en panne : beaucoup
                #  de machines les arrêtent au repos (mode « zéro RPM »).
                "niveau": "arret" if tours == 0 else "ok",
            })

    #  Les cœurs d'un processeur sont nombreux et bougent ensemble : on trie
    #  pour que le plus chaud — le seul qui compte — sorte en premier.
    temperatures.sort(key=lambda t: -t["valeur"])
    return temperatures, ventilateurs


# =============================================================================
#  Carte graphique NVIDIA
# =============================================================================
#  nvidia-smi rend du CSV sans en-tête : une ligne par carte, des nombres
#  nus. On demande explicitement les colonnes, dans l'ordre, plutôt que
#  d'analyser l'affichage décoré — qui change d'une version à l'autre.

_CHAMPS_NV = ("name", "temperature.gpu", "fan.speed", "utilization.gpu",
              "memory.used", "memory.total", "power.draw")


def nvidia():
    if shutil.which("nvidia-smi") is None:
        return []
    try:
        r = subprocess.run(
            ["nvidia-smi", f"--query-gpu={','.join(_CHAMPS_NV)}",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0:
        return []

    cartes = []
    for ligne in r.stdout.strip().splitlines():
        morceaux = [m.strip() for m in ligne.split(",")]
        if len(morceaux) < len(_CHAMPS_NV):
            continue
        nom, temp, vent, charge, vram_u, vram_t, watts = morceaux[:7]

        def nombre(texte):
            #  nvidia-smi écrit « [N/A] » quand une carte ne rend pas une
            #  mesure — un portable sans ventilateur piloté, par exemple.
            try:
                return float(texte)
            except ValueError:
                return None

        temp_v = nombre(temp)
        vram_utilisee, vram_totale = nombre(vram_u), nombre(vram_t)
        carte = {
            "nom": nom or "Carte NVIDIA",
            "temperature": temp_v,
            "niveau": _niveau("carte graphique", temp_v) if temp_v else "ok",
            "ventilateur": nombre(vent),
            "charge": nombre(charge),
            "vram_utilisee": vram_utilisee,
            "vram_totale": vram_totale,
            "watts": nombre(watts),
        }
        #  Le rapport mémoire vidéo : c'est LUI qui explique les saccades
        #  quand une carte de 8 Go se remplit.
        if vram_utilisee is not None and vram_totale:
            carte["vram_pourcent"] = round(100.0 * vram_utilisee / vram_totale)
        cartes.append(carte)
    return cartes


# =============================================================================
#  Relevé complet
# =============================================================================

def releve():
    resultat = {"temperatures": [], "ventilateurs": [], "gpu": [], "erreurs": []}
    try:
        resultat["temperatures"], resultat["ventilateurs"] = capteurs()
    except Exception as e:                                  # noqa: BLE001
        resultat["erreurs"].append(f"capteurs carte mère : {e}")
    try:
        resultat["gpu"] = nvidia()
    except Exception as e:                                  # noqa: BLE001
        resultat["erreurs"].append(f"NVIDIA : {e}")
    return resultat


def _texte(d):
    lignes = []
    plus_chaud = {}
    for t in d["temperatures"]:
        #  Une seule ligne par famille : afficher les 16 cœurs d'un processeur
        #  noie l'information. Le plus chaud est celui qui décide du bridage.
        if t["famille"] not in plus_chaud:
            plus_chaud[t["famille"]] = t
    for famille, t in plus_chaud.items():
        lignes.append(f"  {famille:<18} {t['valeur']:>5.1f} °C   ({t['niveau']})")
    for g in d["gpu"]:
        if g["temperature"] is not None:
            lignes.append(f"  {'carte graphique':<18} {g['temperature']:>5.1f} °C"
                          f"   ({g['niveau']})   {g['nom']}")
        if g.get("vram_pourcent") is not None:
            lignes.append(f"  {'mémoire vidéo':<18} "
                          f"{g['vram_utilisee']:.0f} / {g['vram_totale']:.0f} Mo"
                          f"   ({g['vram_pourcent']} %)")
        if g["ventilateur"] is not None:
            lignes.append(f"  {'ventilateur GPU':<18} {g['ventilateur']:>5.0f} %")
    for v in d["ventilateurs"]:
        etat = " (à l'arrêt)" if v["niveau"] == "arret" else ""
        lignes.append(f"  {v['nom']:<18} {v['valeur']:>5d} tr/min{etat}")
    if not lignes:
        lignes.append("  Aucun capteur lisible sur cette machine.")
    return "\n".join(lignes)


def _principal(argv):
    d = releve()
    if "--json" in argv:
        print(json.dumps(d, ensure_ascii=False, indent=1))
    else:
        print(_texte(d))
        for e in d["erreurs"]:
            print(f"  (source ignorée — {e})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(_principal(sys.argv[1:]))
