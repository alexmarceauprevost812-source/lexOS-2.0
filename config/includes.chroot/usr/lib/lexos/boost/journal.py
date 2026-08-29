"""Journal des modifications de LexOS Boost.

C'est la pièce qui rend tout réversible. Aucune action n'a le droit de
toucher au système sans avoir d'abord écrit ici comment revenir en
arrière. Si le journal ne peut pas être écrit, l'action n'est pas
appliquée : mieux vaut ne rien optimiser que d'optimiser sans retour
possible.

Format : un fichier JSON unique, écrit de façon atomique
(fichier temporaire + rename) pour qu'une coupure de courant au mauvais
moment ne laisse jamais un journal tronqué — sur les vieilles machines
visées, ça arrive.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from dataclasses import dataclass, field, asdict

REPERTOIRE = "/var/lib/lexos/boost"
FICHIER = os.path.join(REPERTOIRE, "journal.json")
VERSION_FORMAT = 1


@dataclass
class Entree:
    """Une modification appliquée, et de quoi la défaire."""

    identifiant: str                      # identifiant unique de l'entrée
    action: str                           # identifiant de l'action (ex. « zram »)
    niveau: str                           # doux / equilibre / max
    horodatage: float                     # time.time() au moment de l'application
    restauration: dict = field(default_factory=dict)  # données propres à l'action
    annulee: bool = False
    note: str = ""

    def en_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def depuis_dict(donnees: dict) -> "Entree":
        return Entree(
            identifiant=donnees.get("identifiant", ""),
            action=donnees.get("action", ""),
            niveau=donnees.get("niveau", ""),
            horodatage=float(donnees.get("horodatage", 0.0)),
            restauration=donnees.get("restauration", {}) or {},
            annulee=bool(donnees.get("annulee", False)),
            note=donnees.get("note", ""),
        )


class Journal:
    """Lecture / écriture du journal, avec écriture atomique."""

    def __init__(self, chemin: str = FICHIER):
        self.chemin = chemin
        self.entrees: list[Entree] = []
        self.charger()

    # ---------------------------------------------------------------- lecture

    def charger(self) -> None:
        self.entrees = []
        if not os.path.exists(self.chemin):
            return
        try:
            with open(self.chemin, "r", encoding="utf-8") as f:
                donnees = json.load(f)
        except (OSError, json.JSONDecodeError):
            # Journal illisible : on ne l'écrase pas, on le met de côté
            # pour que l'utilisateur puisse encore le lire à la main.
            secours = self.chemin + ".illisible"
            try:
                os.replace(self.chemin, secours)
            except OSError:
                pass
            return
        for brut in donnees.get("entrees", []):
            self.entrees.append(Entree.depuis_dict(brut))

    # ---------------------------------------------------------------- écriture

    def ecrire(self) -> None:
        """Écrit le journal sur disque de façon atomique.

        Lève OSError si l'écriture est impossible — l'appelant doit
        traiter ça comme un échec de l'action, pas comme un détail.
        """
        #  BOGUE CORRIGÉ ICI : cette ligne créait REPERTOIRE (le chemin
        #  SYSTÈME, /var/lib/lexos/boost) sans se soucier de self.chemin —
        #  même quand l'appelant avait délibérément donné un autre chemin
        #  au constructeur (Journal(chemin=...), fait pour ça). Un Journal
        #  pointé vers un dossier temporaire de test tentait quand même de
        #  créer /var/lib/lexos, avec les droits d'écriture que ça suppose.
        #  Sur un poste installé ça passait inaperçu (Boost tourne en
        #  root) ; sur le banc CI (utilisateur ordinaire) c'est
        #  PermissionError: [Errno 13] à chaque test qui écrit — trois
        #  échecs, TestJournal en entier. Le dossier à créer est celui de
        #  self.chemin, calculé une seule fois et servant aussi au fichier
        #  temporaire juste en dessous — REPERTOIRE reste le bon choix
        #  pour journal_accessible(), qui vérifie explicitement le chemin
        #  SYSTÈME, pas une instance.
        repertoire = os.path.dirname(self.chemin) or "."
        os.makedirs(repertoire, mode=0o755, exist_ok=True)
        contenu = {
            "version": VERSION_FORMAT,
            "ecrit_le": time.time(),
            "entrees": [e.en_dict() for e in self.entrees],
        }
        descripteur, temporaire = tempfile.mkstemp(dir=repertoire, prefix=".journal-", suffix=".tmp")
        try:
            with os.fdopen(descripteur, "w", encoding="utf-8") as f:
                json.dump(contenu, f, indent=2, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(temporaire, 0o644)
            os.replace(temporaire, self.chemin)
        except Exception:
            try:
                os.unlink(temporaire)
            except OSError:
                pass
            raise

    # ---------------------------------------------------------------- usage

    def ajouter(self, action: str, niveau: str, restauration: dict, note: str = "") -> Entree:
        """Enregistre une nouvelle modification et écrit immédiatement."""
        entree = Entree(
            identifiant=f"{action}-{int(time.time() * 1000)}",
            action=action,
            niveau=niveau,
            horodatage=time.time(),
            restauration=restauration,
            note=note,
        )
        self.entrees.append(entree)
        self.ecrire()
        return entree

    def marquer_annulee(self, identifiant: str) -> None:
        for entree in self.entrees:
            if entree.identifiant == identifiant:
                entree.annulee = True
        self.ecrire()

    def actives(self) -> list[Entree]:
        """Modifications encore en place, de la plus récente à la plus ancienne.

        L'ordre inverse est important : on défait toujours dans l'ordre
        contraire de l'application, sinon deux actions qui touchent au
        même fichier se marchent dessus.
        """
        return sorted(
            (e for e in self.entrees if not e.annulee),
            key=lambda e: e.horodatage,
            reverse=True,
        )

    def actives_pour(self, action: str) -> list[Entree]:
        return [e for e in self.actives() if e.action == action]

    def est_applique(self, action: str) -> bool:
        return bool(self.actives_pour(action))

    def purger_annulees(self) -> None:
        """Retire les entrées déjà annulées pour garder le fichier court."""
        self.entrees = [e for e in self.entrees if not e.annulee]
        self.ecrire()


def journal_accessible() -> tuple[bool, str]:
    """Peut-on écrire le journal ? Renvoie (possible, explication)."""
    try:
        os.makedirs(REPERTOIRE, mode=0o755, exist_ok=True)
    except OSError as erreur:
        return False, f"impossible de créer {REPERTOIRE} : {erreur}"
    if not os.access(REPERTOIRE, os.W_OK):
        return False, f"{REPERTOIRE} n'est pas accessible en écriture (essaie avec sudo)"
    return True, ""
