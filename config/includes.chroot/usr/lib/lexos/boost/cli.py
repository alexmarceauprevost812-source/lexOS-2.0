"""Interface en ligne de commande de LexOS Boost.

Le texte s'adresse à quelqu'un qui n'est pas informaticien : pas de
jargon non expliqué, et toujours la raison derrière chaque choix.
"""

from __future__ import annotations

import argparse
import json
import sys

from . import __version__, mesure as module_mesure
from .actions import NIVEAUX
from .moteur import DroitsInsuffisants, Moteur, Rapport


# --------------------------------------------------------------------------
# mise en forme
# --------------------------------------------------------------------------

class Style:
    def __init__(self, actif: bool):
        self.actif = actif

    def _peindre(self, code: str, texte: str) -> str:
        return f"\033[{code}m{texte}\033[0m" if self.actif else texte

    def gras(self, t: str) -> str:
        return self._peindre("1", t)

    def vert(self, t: str) -> str:
        return self._peindre("32", t)

    def jaune(self, t: str) -> str:
        return self._peindre("33", t)

    def rouge(self, t: str) -> str:
        return self._peindre("31", t)

    def gris(self, t: str) -> str:
        return self._peindre("90", t)


def _titre(style: Style, texte: str) -> None:
    print()
    print(style.gras(texte))
    print(style.gris("─" * len(texte)))


# --------------------------------------------------------------------------
# affichages
# --------------------------------------------------------------------------

def afficher_analyse(moteur: Moteur, niveau: str, style: Style) -> None:
    machine = moteur.machine
    profil = moteur.calculer_profil(niveau)

    _titre(style, "Ta machine")
    print(f"  {machine.resume()}")
    print(f"  Classement : {style.gras(profil.classe_lisible())}")
    if machine.live_usb:
        print(style.jaune("  Session live USB : les réglages disque ne seront pas permanents."))

    _titre(style, f"Ce que le niveau « {niveau} » ferait")
    for note in profil.notes:
        print(f"  · {note}")
    print()
    print(f"  Gain attendu : {style.gras(profil.gain_attendu)}")

    _titre(style, "Optimisations")
    for etape in moteur.plan(niveau):
        if etape.deja_appliquee:
            marque, couleur = "≡", style.gris
            detail = "déjà appliquée"
        elif etape.retenue:
            marque, couleur = "+", style.vert
            detail = etape.gain
        else:
            marque, couleur = "-", style.gris
            detail = etape.raison
        print(f"  {couleur(marque)} {etape.action.titre}")
        if detail:
            print(f"      {style.gris(detail)}")

    retenues = sum(1 for e in moteur.plan(niveau) if e.retenue)
    print()
    if retenues:
        print(f"  {retenues} optimisation(s) à appliquer.")
        print(style.gris("  Pour les appliquer :  sudo lexos-boost --appliquer " + niveau))
        print(style.gris("  Pour voir sans rien changer :  sudo lexos-boost --appliquer "
                         + niveau + " --simulation"))
    else:
        print("  Rien à faire : cette machine est déjà au mieux de ce que LexOS peut régler.")


def afficher_rapport(rapport: Rapport, style: Style) -> None:
    entete = {
        "appliquer": "Optimisation",
        "annuler": "Retour en arrière",
        "rejouer": "Réapplication au démarrage",
    }.get(rapport.operation, rapport.operation)
    if rapport.simulation:
        entete += " (simulation — rien n'a été modifié)"
    _titre(style, entete)

    for titre, message in rapport.reussies:
        print(f"  {style.vert('✓')} {titre}")
        print(f"      {style.gris(message)}")
    for titre, message in rapport.ignorees:
        print(f"  {style.gris('·')} {style.gris(titre)}")
        print(f"      {style.gris(message)}")
    for titre, message in rapport.echouees:
        print(f"  {style.rouge('✗')} {titre}")
        print(f"      {style.rouge(message)}")

    if rapport.avant and rapport.apres and not rapport.simulation:
        _titre(style, "Avant / après")
        for ligne in module_mesure.comparer(rapport.avant, rapport.apres):
            print(f"  · {ligne}")

    print()
    if rapport.simulation:
        print(style.gris("  Relance sans --simulation pour appliquer."))
    elif rapport.operation == "appliquer" and rapport.reussies:
        print(f"  {rapport.total_agi()} optimisation(s) en place.")
        print(style.gris("  Pour tout défaire à tout moment :  sudo lexos-boost --annuler"))
        print(style.gris("  Un redémarrage rendra visible ce qui touche au démarrage."))
    elif rapport.operation == "annuler" and rapport.reussies:
        print("  La machine est revenue à son état d'origine.")


def afficher_etat(moteur: Moteur, style: Style) -> None:
    lignes = moteur.etat()
    _titre(style, "Modifications en place")
    if not lignes:
        print("  Aucune. LexOS Boost n'a rien changé sur cette machine.")
        return
    for titre, quand, note in lignes:
        print(f"  · {style.gras(titre)}  {style.gris(quand)}")
        if note:
            print(f"      {style.gris(note)}")
    print()
    print(style.gris("  Pour tout défaire :  sudo lexos-boost --annuler"))


def afficher_mesure(moteur: Moteur, style: Style) -> None:
    _titre(style, "Mesure de l'état actuel")
    releve = module_mesure.prendre(moteur.machine, complete=True)
    for ligne in module_mesure.resumer(releve):
        print(f"  · {ligne}")


# --------------------------------------------------------------------------
# sortie machine
# --------------------------------------------------------------------------

def sortie_json(moteur: Moteur, niveau: str) -> str:
    profil = moteur.calculer_profil(niveau)
    return json.dumps(
        {
            "version": __version__,
            "machine": moteur.machine.en_dict(),
            "classe": profil.classe,
            "niveau": niveau,
            "niveau_conseille": moteur.niveau_conseille(),
            "reglages": profil.reglages,
            "notes": profil.notes,
            "gain_attendu": profil.gain_attendu,
            "plan": [
                {
                    "action": e.action.identifiant,
                    "titre": e.action.titre,
                    "retenue": e.retenue,
                    "raison": e.raison,
                    "deja_appliquee": e.deja_appliquee,
                }
                for e in moteur.plan(niveau)
            ],
            "mesure": module_mesure.prendre(moteur.machine).en_dict(),
        },
        indent=2,
        ensure_ascii=False,
    )


# --------------------------------------------------------------------------
# point d'entrée
# --------------------------------------------------------------------------

def construire_analyseur() -> argparse.ArgumentParser:
    analyseur = argparse.ArgumentParser(
        prog="lexos-boost",
        description=(
            "Analyse ta machine et la règle au mieux de ce qu'elle peut donner. "
            "Tout est réversible : « lexos-boost --annuler » remet l'état d'origine."
        ),
        epilog=(
            "Exemples :\n"
            "  lexos-boost                          voir ce qui serait fait, sans rien changer\n"
            "  sudo lexos-boost --appliquer max     pousser la machine à son maximum\n"
            "  sudo lexos-boost --appliquer max --simulation   voir le détail sans agir\n"
            "  sudo lexos-boost --annuler           tout remettre comme avant\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    analyseur.add_argument("--version", action="version", version=f"LexOS Boost {__version__}")
    analyseur.add_argument(
        "--appliquer", nargs="?", const="", metavar="NIVEAU",
        help="applique le profil (doux, equilibre, max ; défaut : celui conseillé)",
    )
    analyseur.add_argument("--annuler", action="store_true", help="défait toutes les modifications")
    analyseur.add_argument("--etat", action="store_true", help="liste ce qui est en place")
    analyseur.add_argument("--mesure", action="store_true", help="mesure l'état actuel de la machine")
    analyseur.add_argument(
        "--niveau", choices=NIVEAUX, help="niveau à analyser (sans appliquer)",
    )
    analyseur.add_argument(
        "--simulation", action="store_true",
        help="montre ce qui serait fait sans toucher au système",
    )
    analyseur.add_argument("--json", action="store_true", help="sortie lisible par un programme")
    analyseur.add_argument(
        "--rejouer", action="store_true",
        help=argparse.SUPPRESS,  # usage interne : service de démarrage
    )
    analyseur.add_argument(
        "--sans-couleur", action="store_true", help="désactive la couleur",
    )
    return analyseur


def main(argv: list[str] | None = None) -> int:
    analyseur = construire_analyseur()
    options = analyseur.parse_args(argv)
    style = Style(actif=sys.stdout.isatty() and not options.sans_couleur)

    try:
        moteur = Moteur()
    except Exception as erreur:
        print(f"Impossible d'analyser la machine : {erreur}", file=sys.stderr)
        return 2

    try:
        if options.rejouer:
            rapport = moteur.rejouer()
            for titre, message in rapport.reussies:
                print(f"{titre} : {message}")
            return 0

        if options.annuler:
            rapport = moteur.annuler(simulation=options.simulation)
            afficher_rapport(rapport, style)
            return 1 if rapport.echouees else 0

        if options.etat:
            afficher_etat(moteur, style)
            return 0

        if options.mesure:
            afficher_mesure(moteur, style)
            return 0

        if options.appliquer is not None:
            niveau = options.appliquer or moteur.niveau_conseille()
            if niveau not in NIVEAUX:
                print(
                    f"Niveau inconnu : « {niveau} ». Choisis parmi : {', '.join(NIVEAUX)}.",
                    file=sys.stderr,
                )
                return 2

            def progression(titre: str, index: int, total: int) -> None:
                print(f"  [{index}/{total}] {titre}…")

            rapport = moteur.appliquer(
                niveau, simulation=options.simulation, progression=progression
            )
            afficher_rapport(rapport, style)
            return 1 if rapport.echouees else 0

        # sans argument : on analyse, on ne touche à rien
        niveau = options.niveau or moteur.niveau_conseille()
        if options.json:
            print(sortie_json(moteur, niveau))
        else:
            afficher_analyse(moteur, niveau, style)
        return 0

    except DroitsInsuffisants as erreur:
        print()
        print(style.jaune(str(erreur)), file=sys.stderr)
        return 3
    except KeyboardInterrupt:
        print()
        print("Interrompu. Rien n'a été laissé à moitié : "
              "« lexos-boost --etat » montre ce qui est en place.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
