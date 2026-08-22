"""Calcul du profil d'optimisation adapté à UNE machine précise.

C'est le cœur de l'idée : « LV MAX » ne veut pas dire « appliquer les
mêmes réglages agressifs partout ». Ça veut dire pousser chaque machine
au maximum de CE QU'ELLE PEUT DONNER.

Un portable de 2009 avec 2 Go de RAM et un disque mécanique reçoit un
traitement lourd, parce qu'il a beaucoup à gagner. Une machine récente
avec 16 Go et un NVMe reçoit presque rien, parce qu'il n'y a rien à
récupérer — et le dire honnêtement vaut mieux que d'inventer un gain.

Les valeurs ci-dessous ne sont pas des constantes magiques : chacune est
dérivée du matériel détecté, et la raison du choix est conservée dans
`notes` pour être affichée à l'utilisateur.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .actions import NIVEAUX


# --------------------------------------------------------------------------
# classement de la machine
# --------------------------------------------------------------------------

CLASSES = {
    "tres_ancienne": "très ancienne",
    "ancienne": "ancienne",
    "modeste": "modeste",
    "correcte": "correcte",
    "recente": "récente",
}


def classer(machine) -> str:
    """Situe la machine sur une échelle de cinq crans.

    Le classement combine la RAM (le facteur le plus déterminant sur un
    bureau moderne), le type de disque et l'âge estimé du processeur.
    """
    points = 0

    if machine.ram_mo < 2048:
        points += 0
    elif machine.ram_mo < 4096:
        points += 1
    elif machine.ram_mo < 8192:
        points += 2
    elif machine.ram_mo < 16384:
        points += 3
    else:
        points += 4

    if machine.disque_type == "hdd":
        points += 0
    elif machine.disque_type in ("emmc", "inconnu"):
        points += 1
    elif machine.disque_type == "ssd":
        points += 2
    else:  # nvme
        points += 3

    annee = machine.cpu_annee_estimee
    if annee is None:
        points += 1
    elif annee < 2010:
        points += 0
    elif annee < 2014:
        points += 1
    elif annee < 2018:
        points += 2
    else:
        points += 3

    if points <= 1:
        return "tres_ancienne"
    if points <= 3:
        return "ancienne"
    if points <= 5:
        return "modeste"
    if points <= 8:
        return "correcte"
    return "recente"


# --------------------------------------------------------------------------
# le profil
# --------------------------------------------------------------------------

@dataclass
class Profil:
    """Ce qu'on va appliquer, et pourquoi."""

    niveau: str
    classe: str
    reglages: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)
    gain_attendu: str = ""

    def classe_lisible(self) -> str:
        return CLASSES.get(self.classe, self.classe)


def _algorithme_compression(machine) -> str:
    """lz4 compresse moins bien mais beaucoup plus vite.

    Sur un processeur ancien ou à deux cœurs, zstd coûterait plus de
    temps processeur qu'il n'en fait gagner en accès disque.
    """
    annee = machine.cpu_annee_estimee
    if machine.cpu_coeurs <= 2 or (annee is not None and annee < 2012):
        return "lz4"
    return "zstd"


PLAFOND_ZRAM_MO = 4096


def _taille_zram(machine) -> int:
    """Taille de la zone compressée, en Mo.

    Elle peut dépasser la RAM libre : le contenu y est compressé d'un
    facteur 2 à 3. Plus la machine manque de mémoire, plus on en met, en
    proportion.

    Les seuils sont inclusifs (« 2 Go ou moins », pas « moins de 2 Go ») :
    une machine qui annonce exactement 2048 Mo est une machine à 2 Go, et
    elle doit recevoir le traitement des machines à 2 Go.

    Le plafond évite la discontinuité qu'un simple découpage en paliers
    produirait : sans lui, 8191 Mo de RAM donnerait deux fois plus de
    zram que 8193 Mo, ce qui n'aurait aucun sens physique.
    """
    ram = machine.ram_mo
    if ram <= 0 or ram >= 16384:
        return 0
    if ram <= 2048:
        facteur = 1.5
    elif ram <= 4096:
        facteur = 1.0
    elif ram <= 8192:
        facteur = 0.5
    else:
        facteur = 0.25
    return min(int(ram * facteur), PLAFOND_ZRAM_MO)


def _swappiness(machine, zram_prevu: bool) -> int:
    """À quel point le noyau doit préférer décharger la mémoire.

    Avec zram, décharger est bon marché : on encourage. Sans zram et
    avec un disque mécanique, décharger coûte très cher : on freine.
    """
    if zram_prevu:
        return 150
    if machine.disque_type in ("ssd", "nvme"):
        return 20
    return 10


def _gouverneur(machine, niveau: str) -> str | None:
    dispo = machine.gouverneurs_disponibles
    if not dispo:
        return None

    if machine.portable:
        # sur batterie, on ne bloque jamais la fréquence au maximum
        for candidat in ("schedutil", "ondemand", "conservative"):
            if candidat in dispo:
                return candidat
        return None

    if niveau == "max" and "performance" in dispo:
        return "performance"
    for candidat in ("schedutil", "ondemand", "performance"):
        if candidat in dispo:
            return candidat
    return None


def _ordonnanceur(machine) -> str | None:
    dispo = machine.ordonnanceurs_disponibles
    if not dispo:
        return None
    if machine.disque_type == "nvme":
        prefere = ("none", "mq-deadline")
    elif machine.disque_type in ("ssd",):
        prefere = ("mq-deadline", "none", "bfq")
    else:  # hdd, emmc, inconnu
        prefere = ("bfq", "mq-deadline")
    for candidat in prefere:
        if candidat in dispo:
            return candidat
    return None


def _plafond_journaux(machine) -> int:
    """Taille maximale des journaux système, en Mo."""
    taille = machine.disque_taille_go
    if taille and taille < 64:
        return 50
    if taille and taille < 256:
        return 100
    return 200


def _limite_miniatures(machine) -> int:
    if machine.ram_mo < 2048:
        return 2
    if machine.ram_mo < 4096:
        return 8
    return 32


def calculer(machine, niveau: str = "max") -> Profil:
    """Construit le profil pour cette machine à ce niveau."""
    if niveau not in NIVEAUX:
        niveau = "max"

    classe = classer(machine)
    profil = Profil(niveau=niveau, classe=classe)
    notes = profil.notes
    reglages = profil.reglages

    # ---------------------------------------------------------- mémoire
    taille_zram = _taille_zram(machine) if niveau in ("doux", "equilibre", "max") else 0
    if taille_zram:
        reglages["zram_taille_mo"] = taille_zram
        reglages["zram_algo"] = _algorithme_compression(machine)
        raison_algo = ""
        if reglages["zram_algo"] == "lz4":
            if machine.cpu_coeurs <= 2:
                raison_algo = f", en lz4 car {machine.cpu_coeurs} cœur(s) seulement"
            else:
                raison_algo = ", en lz4 car le processeur est ancien"
        notes.append(
            f"{taille_zram} Mo de mémoire compressée dimensionnés pour "
            f"{machine.ram_mo} Mo de RAM{raison_algo}"
        )
    elif machine.zram_actif:
        notes.append("mémoire compressée déjà en place, on n'y touche pas")
    elif machine.ram_mo >= 16384:
        notes.append("16 Go de RAM ou plus : la mémoire compressée n'apporterait rien")

    sysctl = {
        "vm.swappiness": _swappiness(machine, bool(taille_zram)),
        "vm.vfs_cache_pressure": 50,
    }
    if taille_zram:
        # lire page par page depuis la zram, plutôt que par paquets de 8
        sysctl["vm.page-cluster"] = 0
    if machine.ram_mo < 4096:
        # écrire plus tôt et par petits paquets : évite les gels de plusieurs secondes
        sysctl["vm.dirty_background_ratio"] = 5
        sysctl["vm.dirty_ratio"] = 10
        notes.append("écritures disque lissées pour éviter les gels sur machine peu dotée")
    reglages["sysctl"] = sysctl

    # ---------------------------------------------------------- processeur
    gouverneur = _gouverneur(machine, niveau)
    if gouverneur:
        reglages["gouverneur"] = gouverneur
        if machine.portable and gouverneur != "performance":
            notes.append(f"processeur en « {gouverneur} » — portable détecté, batterie ménagée")
        else:
            notes.append(f"processeur en « {gouverneur} »")

    # ---------------------------------------------------------- disque
    if machine.disque_type in ("hdd", "emmc", "inconnu"):
        reglages["readahead_kio"] = 2048 if niveau == "max" else 1024
        notes.append(
            f"anticipation de lecture à {reglages['readahead_kio']} Kio — "
            f"disque {machine.disque_type} détecté"
        )

    ordonnanceur = _ordonnanceur(machine)
    if ordonnanceur:
        reglages["ordonnanceur"] = ordonnanceur

    reglages["journal_max_mo"] = _plafond_journaux(machine)

    # ---------------------------------------------------------- bureau
    bureau_charge = (
        machine.ram_mo < 4096
        or machine.disque_type == "hdd"
        or (machine.cpu_annee_estimee is not None and machine.cpu_annee_estimee < 2014)
    )
    reglages["couper_effets"] = bool(bureau_charge)
    if bureau_charge:
        notes.append("effets visuels coupés — cette machine les calcule au prix du confort")
    else:
        notes.append("effets visuels conservés — la machine les encaisse sans peine")

    reglages["miniatures_limite_mo"] = _limite_miniatures(machine)

    # ---------------------------------------------------------- services
    reglages["couper_services"] = niveau == "max"

    # ---------------------------------------------------------- honnêteté
    profil.gain_attendu = _gain_attendu(classe, niveau)
    if classe == "recente" and niveau == "max":
        notes.append(
            "cette machine est déjà rapide : le gain sera faible, et c'est normal — "
            "LexOS Boost ne va pas inventer de la vitesse qui n'existe pas"
        )

    return profil


def _gain_attendu(classe: str, niveau: str) -> str:
    tableau = {
        "tres_ancienne": {
            "doux": "sensible : la machine respire déjà mieux",
            "equilibre": "important : bureau fluide, démarrage nettement plus court",
            "max": "spectaculaire pour une machine de cet âge — c'est le cas où LexOS Boost sert le plus",
        },
        "ancienne": {
            "doux": "sensible",
            "equilibre": "important",
            "max": "très important : la machine redevient agréable au quotidien",
        },
        "modeste": {
            "doux": "léger",
            "equilibre": "sensible",
            "max": "sensible : surtout au démarrage et sous plusieurs applications",
        },
        "correcte": {
            "doux": "léger",
            "equilibre": "léger à sensible",
            "max": "modéré",
        },
        "recente": {
            "doux": "négligeable",
            "equilibre": "faible",
            "max": "faible : cette machine n'a pas grand-chose à récupérer",
        },
    }
    return tableau.get(classe, {}).get(niveau, "variable")


def niveau_conseille(machine) -> str:
    """Niveau que LexOS Boost proposerait par défaut à cette machine."""
    classe = classer(machine)
    if classe in ("tres_ancienne", "ancienne"):
        return "max"
    if classe == "modeste":
        return "equilibre"
    return "doux"
