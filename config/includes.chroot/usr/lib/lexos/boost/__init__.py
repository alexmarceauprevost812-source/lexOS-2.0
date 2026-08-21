"""LexOS Boost — remettre une vieille machine en état de marche.

Le moteur analyse le matériel, calcule ce que CETTE machine précise peut
donner de mieux, applique les réglages qui la concernent, et sait tout
défaire.

Rien n'est appliqué sans que le moyen de revenir en arrière ait été
écrit d'abord. C'est la règle qui tient tout le reste.
"""

__version__ = "1.0.0"
__all__ = ["materiel", "systeme", "journal", "actions", "profil", "mesure", "moteur", "cli"]
