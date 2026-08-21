"""Moteur de LexOS Boost — l'orchestrateur.

La ligne de commande et le panneau graphique passent tous les deux par
ici. Aucune logique d'optimisation ne doit vivre dans l'interface : si
les deux interfaces donnaient des résultats différents, la promesse de
réversibilité ne tiendrait plus.

Déroulé d'une optimisation :

    analyser()  →  plan()  →  appliquer()  →  rapport

et à tout moment :

    annuler()   →  la machine revient exactement à son état d'origine
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from . import actions as catalogue
from . import materiel, mesure, profil as module_profil
from .journal import Journal, journal_accessible


@dataclass
class Etape:
    """Une action et la décision prise à son sujet."""

    action: catalogue.Action
    retenue: bool
    raison: str = ""
    gain: str = ""
    deja_appliquee: bool = False


@dataclass
class Rapport:
    """Ce que l'opération a produit, pour affichage."""

    operation: str                       # « appliquer » ou « annuler »
    niveau: str = ""
    simulation: bool = False
    reussies: list[tuple[str, str]] = field(default_factory=list)   # (titre, message)
    ignorees: list[tuple[str, str]] = field(default_factory=list)
    echouees: list[tuple[str, str]] = field(default_factory=list)
    avant: mesure.Mesure | None = None
    apres: mesure.Mesure | None = None
    redemarrage_conseille: bool = False

    def total_agi(self) -> int:
        return len(self.reussies)


class DroitsInsuffisants(RuntimeError):
    """Levée quand l'opération demande les droits administrateur."""


class Moteur:
    """Point d'entrée unique pour les deux interfaces."""

    def __init__(self) -> None:
        self.machine = materiel.detecter()
        self._journal: Journal | None = None

    # ------------------------------------------------------------- journal

    @property
    def journal(self) -> Journal:
        if self._journal is None:
            self._journal = Journal()
        return self._journal

    @staticmethod
    def est_root() -> bool:
        return os.geteuid() == 0

    def verifier_droits(self) -> None:
        if not self.est_root():
            raise DroitsInsuffisants(
                "LexOS Boost doit modifier des réglages système : relance-le avec "
                "« sudo lexos-boost » (ou par le panneau, qui demandera le mot de passe)."
            )
        possible, explication = journal_accessible()
        if not possible:
            raise DroitsInsuffisants(
                f"le journal des modifications ne peut pas être écrit — {explication}. "
                "Rien n'a été touché : sans journal, aucun retour en arrière ne serait garanti."
            )

    # ------------------------------------------------------------- analyse

    def niveau_conseille(self) -> str:
        return module_profil.niveau_conseille(self.machine)

    def calculer_profil(self, niveau: str) -> module_profil.Profil:
        return module_profil.calculer(self.machine, niveau)

    def plan(self, niveau: str) -> list[Etape]:
        """Ce qui serait fait à ce niveau, action par action, avec les raisons."""
        etapes: list[Etape] = []
        journal_lisible = self.est_root() or os.path.exists(Journal().chemin)
        deja = set()
        if journal_lisible:
            try:
                deja = {e.action for e in self.journal.actives()}
            except OSError:
                deja = set()

        for action in catalogue.CATALOGUE:
            if not catalogue.niveau_atteint(niveau, action.niveau_minimum):
                etapes.append(Etape(
                    action, False,
                    f"réservée au niveau « {action.niveau_minimum} » et au-dessus",
                ))
                continue

            if action.identifiant in deja:
                etapes.append(Etape(
                    action, False, "déjà appliquée", action.gain_estime(self.machine),
                    deja_appliquee=True,
                ))
                continue

            utile, raison = action.pertinente(self.machine)
            etapes.append(Etape(
                action,
                utile,
                raison if not utile else "",
                action.gain_estime(self.machine) if utile else "",
            ))
        return etapes

    # ------------------------------------------------------------ appliquer

    def appliquer(
        self,
        niveau: str,
        simulation: bool = False,
        progression=None,
    ) -> Rapport:
        """Applique le profil. `progression(titre, index, total)` est optionnel."""
        if not simulation:
            self.verifier_droits()

        profil = self.calculer_profil(niveau)
        rapport = Rapport(operation="appliquer", niveau=niveau, simulation=simulation)
        rapport.avant = mesure.prendre(self.machine, complete=not simulation)

        retenues = [e for e in self.plan(niveau) if e.retenue]
        total = len(retenues)

        for index, etape in enumerate(retenues, start=1):
            action = etape.action
            if progression:
                progression(action.titre, index, total)

            try:
                resultat = action.appliquer(self.machine, profil.reglages, simulation)
            except Exception as erreur:  # une action fautive ne doit pas tout arrêter
                rapport.echouees.append((action.titre, f"erreur inattendue : {erreur}"))
                continue

            if not resultat.reussi:
                rapport.echouees.append((action.titre, resultat.message))
                continue

            if resultat.ignoree:
                rapport.ignorees.append((action.titre, resultat.message))
                continue

            if not simulation:
                try:
                    self.journal.ajouter(
                        action=action.identifiant,
                        niveau=niveau,
                        restauration=resultat.restauration,
                        note=resultat.message,
                    )
                except OSError as erreur:
                    # le journal a échoué : on défait tout de suite, sinon on
                    # laisserait une modification sans moyen de revenir en arrière
                    action.annuler(resultat.restauration, simulation=False)
                    rapport.echouees.append((
                        action.titre,
                        f"annulée aussitôt — le journal n'a pas pu être écrit ({erreur})",
                    ))
                    continue

            rapport.reussies.append((action.titre, resultat.message))
            if action.redemarrage_requis:
                rapport.redemarrage_conseille = True

        if not simulation:
            self.machine = materiel.detecter()
            rapport.apres = mesure.prendre(self.machine, complete=True)
        return rapport

    # -------------------------------------------------------------- annuler

    def annuler(self, simulation: bool = False, progression=None) -> Rapport:
        """Défait toutes les modifications, de la plus récente à la plus ancienne."""
        if not simulation:
            self.verifier_droits()

        rapport = Rapport(operation="annuler", simulation=simulation)
        rapport.avant = mesure.prendre(self.machine, complete=not simulation)

        entrees = self.journal.actives()
        total = len(entrees)
        if total == 0:
            rapport.ignorees.append(("Aucune modification", "il n'y a rien à annuler"))
            return rapport

        for index, entree in enumerate(entrees, start=1):
            action = catalogue.action(entree.action)
            if action is None:
                rapport.echouees.append((
                    entree.action,
                    "optimisation inconnue de cette version — entrée laissée au journal",
                ))
                continue

            if progression:
                progression(action.titre, index, total)

            try:
                resultat = action.annuler(entree.restauration, simulation)
            except Exception as erreur:
                rapport.echouees.append((action.titre, f"erreur inattendue : {erreur}"))
                continue

            if resultat.reussi:
                if not simulation:
                    self.journal.marquer_annulee(entree.identifiant)
                rapport.reussies.append((action.titre, resultat.message))
            else:
                rapport.echouees.append((action.titre, resultat.message))

        if not simulation:
            self.machine = materiel.detecter()
            rapport.apres = mesure.prendre(self.machine, complete=True)
        return rapport

    # ---------------------------------------------------------------- état

    def etat(self) -> list[tuple[str, str, str]]:
        """Modifications en place : (titre, date lisible, note)."""
        import datetime

        lignes = []
        for entree in self.journal.actives():
            action = catalogue.action(entree.action)
            titre = action.titre if action else entree.action
            quand = datetime.datetime.fromtimestamp(entree.horodatage).strftime("%d/%m/%Y %H:%M")
            lignes.append((titre, quand, entree.note))
        return lignes

    # ------------------------------------------------------------- rejouer

    def rejouer(self) -> Rapport:
        """Réapplique au démarrage les réglages qui ne survivent pas au redémarrage.

        Le gouverneur du processeur, l'anticipation de lecture et la file
        d'attente du disque vivent dans /sys : ils repartent à zéro à
        chaque démarrage. Cette méthode les remet d'après le journal.
        Appelée par lexos-boost-demarrage.service.
        """
        rapport = Rapport(operation="rejouer")
        volatiles = {"gouverneur_cpu", "readahead_disque", "ordonnanceur_disque"}

        for entree in self.journal.actives():
            if entree.action not in volatiles:
                continue
            action = catalogue.action(entree.action)
            if action is None:
                continue

            restauration = entree.restauration
            if entree.action == "gouverneur_cpu":
                vise = restauration.get("vise")
                if not vise:
                    continue
                remis = 0
                for cpu in restauration.get("anciens", {}):
                    ok, _ = _ecrire_gouverneur(cpu, vise)
                    remis += 1 if ok else 0
                rapport.reussies.append((action.titre, f"{remis} cœur(s) remis en « {vise} »"))
            else:
                chemin, vise = restauration.get("chemin"), restauration.get("vise")
                if not chemin or vise is None:
                    continue
                from . import systeme
                ok, message = systeme.ecrire_sysfs(chemin, str(vise))
                if ok:
                    rapport.reussies.append((action.titre, f"remis à « {vise} »"))
                else:
                    rapport.echouees.append((action.titre, message))

        return rapport


def _ecrire_gouverneur(cpu: str, valeur: str) -> tuple[bool, str]:
    from . import systeme
    return systeme.ecrire_sysfs(
        f"/sys/devices/system/cpu/{cpu}/cpufreq/scaling_governor", valeur
    )
