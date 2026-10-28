"""LexOS Pilotes — quels paquets graphiques peuvent être mis à jour, et comment.

Ce module est partagé par l'interface (qui tourne en utilisateur) et par
l'aide root lexos-pilotes-maj (lancée par pkexec). Il ne fait QUE lire :
`dpkg-query` et `apt-cache policy`. L'installation elle-même est dans maj.py.

═══ POURQUOI ON NE FAIT PAS SIMPLEMENT « apt-get upgrade » ═══
Deux pièges propres à LexOS, et chacun a déjà coûté une ISO :

  · LA PILE NVIDIA EST ÉPINGLÉE sur une branche (fichier
    /etc/apt/preferences.d/lexos-nvidia-pin, priorité 1001), parce que la
    branche 610 coupe le signal HDMI vers une télé. apt respecte l'épingle
    tout seul : on ne la contourne JAMAIS ici. On se contente de DIRE qu'une
    branche plus récente existe, pour que ce soit un choix conscient.

  · MESA ET LES MICROLOGICIELS PEUVENT VENIR DE BACKPORTS (hook 0257).
    backports est à priorité 100 : pour un paquet déjà installé depuis
    backports, le « candidat » d'apt est la version de trixie, PLUS VIEILLE,
    qu'apt refuse d'installer (pas de rétrogradation sous 1000). Un simple
    upgrade laisserait donc ces paquets figés pour toujours, en silence.
    On les demande explicitement par « paquet/trixie-backports ».

Règle du module, comme utils.py du Diagnostic : aucune fonction ne lève
d'exception vers l'appelant. MAIS un outil absent ou en échec ne donne
JAMAIS une liste vide : une liste vide se lit « À jour » dans la page et
« déjà à jour » dans l'aide root. etat_mises_a_jour() distingue donc « rien
à faire » de « impossible de savoir », et dit pourquoi.
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Optional

#  Ce que l'appli a le droit de toucher. Rien d'autre ne passe, même si apt
#  propose cinquante mises à jour : ce n'est pas un gestionnaire de paquets,
#  c'est l'appli de la carte graphique.
MOTIF_GRAPHIQUE = re.compile(
    r"^("
    r"nvidia-.*|libnvidia-.*|libcuda.*|libnvcuvid.*|libnvoptix.*|libxnvctrl.*"
    r"|cuda-drivers.*|xserver-xorg-video-.*"
    r"|firmware-(misc-nonfree|amd-graphics|intel-graphics|nvidia-gsp|nvidia-graphics|linux|linux-nonfree)"
    r"|mesa-.*|libgl1-mesa-dri|libglx-mesa0|libegl-mesa0|libgbm1|libglapi-mesa|libosmesa6"
    r"|libdrm.*|libvulkan1|intel-media-va-driver.*|i965-va-driver.*|vainfo"
    r")(:[a-z0-9]+)?$"
)

FICHIER_EPINGLE = "/etc/apt/preferences.d/lexos-nvidia-pin"
#  Les index téléchargés par « apt-get update ». L'ISO est construite avec
#  « --apt-indices false » : sur une session live, ce dossier est VIDE tant
#  que personne n'a cliqué « Vérifier maintenant ». Le banc le détourne.
LISTES_APT = Path(os.environ.get("LEXOS_PILOTES_LISTES_APT", "/var/lib/apt/lists"))


def _lancer_outil(cmd: list, timeout: float = 30.0, env: Optional[dict] = None) -> tuple:
    """(code, sortie, raison) ; code None si l'outil n'a pas pu tourner."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env, check=False)
    except FileNotFoundError:
        return None, "", f"{cmd[0]} est introuvable"
    except subprocess.TimeoutExpired:
        return None, "", f"{cmd[0]} n'a pas répondu en {int(timeout)} s"
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "", f"{cmd[0]} n'a pas pu être lancé ({exc})"
    if r.returncode != 0:
        derniere = next((l.strip() for l in reversed((r.stderr or r.stdout or "").splitlines()) if l.strip()), "")
        return r.returncode, r.stdout or "", (f"{cmd[0]} a échoué (code {r.returncode})"
                                              + (f" : {derniere}" if derniere else ""))
    return 0, r.stdout or "", ""


def _executer(cmd: list, timeout: float = 30.0) -> Optional[str]:
    code, sortie, _raison = _lancer_outil(cmd, timeout)
    return sortie if code == 0 else None


def derniere_verification() -> Optional[float]:
    """Quand les index apt ont été rafraîchis pour la dernière fois (None : jamais)."""
    try:
        dates = [p.stat().st_mtime for p in LISTES_APT.iterdir()
                 if p.name.endswith("Packages") or "_Packages" in p.name]
    except OSError:
        return None
    return max(dates) if dates else None


def version_plus_grande(a: str, b: str) -> bool:
    """True si la version Debian a > b (règles dpkg, pas l'ordre alphabétique)."""
    try:
        r = subprocess.run(["dpkg", "--compare-versions", a, "gt", b],
                           capture_output=True, timeout=5, check=False)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def paquets_graphiques_installes(sortie_dpkg: Optional[str] = None) -> list:
    """Noms (avec « :i386 » s'il y a lieu) des paquets graphiques installés."""
    if sortie_dpkg is None:
        sortie_dpkg = _executer(
            ["dpkg-query", "-W", "-f", "${db:Status-Abbrev} ${binary:Package}\n"]) or ""
    noms = []
    for ligne in sortie_dpkg.splitlines():
        morceaux = ligne.split()
        if len(morceaux) == 2 and morceaux[0].startswith("ii") and MOTIF_GRAPHIQUE.match(morceaux[1]):
            noms.append(morceaux[1])
    return sorted(set(noms))


def lire_politique(sortie: str) -> dict:
    """Analyse « apt-cache policy p1 p2… ».

    Rend {paquet: {"installe", "candidat", "versions": [(version, [suites])]}}.
    Une « suite » est par exemple « trixie-backports » ou « trixie » ; la
    ligne /var/lib/dpkg/status est ignorée.
    """
    resultat: dict = {}
    courant = None
    version_courante = None
    for ligne in sortie.splitlines():
        if ligne and not ligne.startswith(" ") and ligne.endswith(":"):
            courant = ligne[:-1]
            resultat[courant] = {"installe": None, "candidat": None, "versions": []}
            version_courante = None
            continue
        if courant is None:
            continue
        brut = ligne.strip()
        if brut.startswith("Installed:") or brut.startswith("Installé :"):
            v = brut.split(":", 1)[1].strip()
            resultat[courant]["installe"] = None if v in ("(none)", "(aucun)") else v
        elif brut.startswith("Candidate:") or brut.startswith("Candidat :"):
            v = brut.split(":", 1)[1].strip()
            resultat[courant]["candidat"] = None if v in ("(none)", "(aucun)") else v
        elif re.match(r"^(\*\*\* )?\S+ -?\d+$", brut) and not brut.startswith("/"):
            #  « *** 1.2-3 100 » ou « 1.2-3 500 » : une version.
            v = brut.replace("*** ", "").rsplit(" ", 1)[0]
            version_courante = [v, []]
            resultat[courant]["versions"].append(version_courante)
        elif version_courante is not None and re.match(r"^-?\d+ ", brut):
            #  « 500 http://deb.debian.org/debian trixie/main amd64 Packages »
            #  Le dépôt NVIDIA est « plat » (pas de suite) : on garde alors
            #  le nom d'hôte, « developer.download.nvidia.com ».
            morceaux = brut.split()
            if len(morceaux) >= 3 and not morceaux[1].startswith("/"):
                if "/" in morceaux[2]:
                    version_courante[1].append(morceaux[2].split("/", 1)[0])
                else:
                    hote = re.sub(r"^\w+://", "", morceaux[1]).split("/", 1)[0]
                    version_courante[1].append(hote)
    return resultat


def _suites_de(info: dict, version: str) -> list:
    for v, suites in info["versions"]:
        if v == version:
            return suites
    return []


def planifier(politique: dict) -> list:
    """Décide, paquet par paquet, quoi demander à apt.

    Rend une liste de dicts {paquet, installe, cible, demande, source} où
    « demande » est exactement l'argument à passer à apt-get install.
    """
    plan = []
    for paquet, info in sorted(politique.items()):
        installe = info.get("installe")
        if not installe:
            continue
        suites_installe = _suites_de(info, installe)
        bpo = next((s for s in suites_installe if s.endswith("-backports")), None)
        if bpo:
            #  Installé depuis backports : on reste sur backports.
            cible = installe
            for v, suites in info["versions"]:
                if bpo in suites and version_plus_grande(v, cible):
                    cible = v
            if cible != installe:
                plan.append({"paquet": paquet, "installe": installe, "cible": cible,
                             "demande": f"{paquet}/{bpo}", "source": bpo})
            continue
        candidat = info.get("candidat")
        if candidat and candidat != installe and version_plus_grande(candidat, installe):
            suites = _suites_de(info, candidat)
            plan.append({"paquet": paquet, "installe": installe, "cible": candidat,
                         "demande": paquet, "source": suites[0] if suites else "?"})
    return plan


def etat_mises_a_jour() -> dict:
    """Le plan complet sur la machine réelle (lecture seule).

    Rend {"disponible", "raison", "plan"}. disponible=False veut dire « on ne
    SAIT PAS » — jamais « à jour » : sans index apt, ou avec apt-cache en
    échec, aucune version distante n'est connue, et une liste vide serait
    une valeur inventée. C'est la distinction que font déjà le Diagnostic et
    LEXOS PRO (pro/services/maj.py : « Les confondre ferait dire « système à
    jour » à une machine qui ne s'est pas connectée depuis un mois »).
    """
    if derniere_verification() is None:
        return {"disponible": False, "plan": [],
                "raison": "la liste des paquets n'a jamais été téléchargée sur cette machine "
                          f"(aucun index dans {LISTES_APT}) : clique « Vérifier maintenant »"}
    code, sortie, raison = _lancer_outil(
        ["dpkg-query", "-W", "-f", "${db:Status-Abbrev} ${binary:Package}\n"])
    if code != 0:
        return {"disponible": False, "plan": [], "raison": raison}
    noms = paquets_graphiques_installes(sortie)
    if not noms:
        return {"disponible": True, "plan": [], "raison": None}
    code, sortie, raison = _lancer_outil(["apt-cache", "policy", *noms], timeout=60.0)
    if code != 0 or not sortie.strip():
        return {"disponible": False, "plan": [],
                "raison": raison or "apt-cache policy n'a rien répondu"}
    return {"disponible": True, "plan": planifier(lire_politique(sortie)), "raison": None}


#  La commande d'installation, au mot près : maj.py l'appelle en simulation
#  (« -s »), puis pour de vrai (« -y »), et la page en simulation. Une seule
#  définition, pour que ce qu'on simule soit ce qu'on installe.
#  « --no-remove » : si le résolveur veut retirer un paquet (Breaks d'une
#  nouvelle Mesa, binaire abandonné), apt ABANDONNE au lieu de retirer — le
#  hook 0260 fait déjà de même « pour éviter de supprimer DKMS ». La
#  simulation, elle, s'en passe : avec lui, apt échoue sans dire QUOI il
#  aurait retiré ; sans lui, il liste les lignes « Remv ».
def commande_installation(demandes: list, mode: str) -> list:
    if mode not in ("-s", "-y"):
        raise ValueError(mode)
    garde = [] if mode == "-s" else ["--no-remove"]
    return ["install", mode, "-q", "--only-upgrade", *garde,
            "-o", "Dpkg::Options::=--force-confold", *demandes]


def lire_simulation(sortie: str) -> dict:
    """Les lignes « Inst » / « Remv » / « Purg » d'un « apt-get -s »."""
    retraits, installations = [], []
    for ligne in sortie.splitlines():
        m = re.match(r"^(Remv|Purg) (\S+)", ligne)
        if m:
            retraits.append(m.group(2))
            continue
        m = re.match(r"^Inst (\S+)", ligne)
        if m:
            installations.append(m.group(1))
    return {"retraits": sorted(set(retraits)), "installations": installations}


def simuler(demandes: list) -> dict:
    """« apt-get -s » : ce que la VRAIE commande ferait, sans rien toucher.

    Tourne aussi sans root (apt prévient « This is only a simulation! »).
    Rend {"ok", "raison", "retraits", "installations", "sortie"}.
    """
    #  LC_ALL=C : on lit des mots-clés d'apt (« Remv »), pas une traduction.
    code, sortie, raison = _lancer_outil(["apt-get", *commande_installation(demandes, "-s")],
                                         timeout=120.0, env=dict(os.environ, LC_ALL="C.UTF-8"))
    if code is None:
        return {"ok": False, "raison": raison, "retraits": [], "installations": [], "sortie": ""}
    lu = lire_simulation(sortie)
    return {"ok": code == 0, "raison": raison or None, "sortie": sortie, **lu}


def branche_epinglee(texte: Optional[str] = None) -> Optional[str]:
    """« 595 » si la pile NVIDIA est épinglée, sinon None."""
    if texte is None:
        try:
            with open(FICHIER_EPINGLE, encoding="utf-8") as f:
                texte = f.read()
        except OSError:
            return None
    m = re.search(r"^Pin:\s*version\s+(\d+)\.\*", texte, re.MULTILINE)
    return m.group(1) if m else None


def etat_epingle() -> tuple:
    """(branche, raison). (None, None) : pas d'épingle — un vrai « aucune ».
    (None, raison) : on ne sait pas, et la page doit le dire."""
    try:
        with open(FICHIER_EPINGLE, encoding="utf-8") as f:
            texte = f.read()
    except FileNotFoundError:
        return None, None
    except OSError as exc:
        return None, f"{FICHIER_EPINGLE} est illisible ({exc.strerror or exc})"
    branche = branche_epinglee(texte)
    if branche is None:
        return None, f"{FICHIER_EPINGLE} existe mais ne contient pas de ligne « Pin: version N.* »"
    return branche, None


def branche_plus_recente(politique_pilote: Optional[dict] = None) -> Optional[str]:
    """La version NVIDIA la plus haute publiée, épingle ou pas (pour information)."""
    if politique_pilote is None:
        sortie = _executer(["apt-cache", "policy", "nvidia-driver-cuda"], timeout=30.0)
        if not sortie:
            return None
        politique_pilote = lire_politique(sortie).get("nvidia-driver-cuda")
    if not politique_pilote:
        return None
    meilleure = None
    for v, _suites in politique_pilote["versions"]:
        if meilleure is None or version_plus_grande(v, meilleure):
            meilleure = v
    return meilleure
