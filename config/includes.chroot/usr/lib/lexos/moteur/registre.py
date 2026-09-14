"""Ne pas relire ce qu'on vient de lire — et le PÉRIMER dès qu'on y touche.

═══ POURQUOI ═══
ALEX : « que ça soit encore plus fluide et rapide ».

Cliquer une tuile, c'est aujourd'hui : l'action, puis on relit TOUT le bloc
depuis zéro — nmcli, bluetoothctl, pactl, chacun un sous-processus. Deux
clics d'affilée paient deux fois exactement la même lecture, à deux secondes
d'intervalle.

═══ DEUX RÈGLES, ET LA SECONDE PRIME ═══

1. UN TTL COURT. Assez pour que deux clics rapprochés ne relisent pas deux
   fois ; trop court pour mentir longtemps.

   ⚠ LE VRAI DANGER D'UN CACHE, C'EST LA VALEUR CHANGÉE EN DEHORS DE LEXOS.
   Alex coupe le Wi-Fi par la touche du clavier, ou par nmcli en ligne de
   commande : le volet montrerait encore « Activé ». Un TTL d'une seconde et
   demie borne ça à une seconde et demie, ce qui est acceptable. NE PAS
   MONTER AU-DELÀ DE DEUX SECONDES en croyant gagner : c'est là que le cache
   commence à raconter des histoires, et une valeur fausse coûte plus cher
   que la lenteur qu'elle évite.

2. L'INVALIDATION PRIME SUR LE TTL. Une action qui change une chose PÉRIME
   sa lecture tout de suite — sinon la tuile revient à son ancienne valeur
   une demi-seconde après le clic, et c'est pire que lent : c'est FAUX.

   ⚠ ET LE DÉFAUT EST « TOUT PÉRIMER ». Une action qui ne déclare rien
   périme l'état entier. On n'opte pas OUT de la justesse : on opte IN dans
   la précision. Une liste à tenir aurait fini par oublier une action, et
   l'oubli aurait produit un affichage faux — silencieux, donc cher. Même
   raisonnement que l'oubli de la mémoire des outils après chaque action.

═══ CE QUI NE COÛTE RIEN NE SE CACHE PAS ═══
Lire un fichier de configuration est déjà instantané ; un cache là-dessus
n'ajoute que du risque de périmé. etat() fait déjà cette distinction (« CE
QUI NE COÛTE RIEN : toujours là ») — ce module ne voit JAMAIS ces clés-là.

═══ ET IL VIT EN MÉMOIRE, POINT ═══
Pas de fichier, pas de base. Un cache qui survit à un redémarrage est un
cache qui ment au démarrage suivant.
"""

from __future__ import annotations

import os
import threading
import time

from . import etat as _etat

#  Une seconde et demie : voir la règle 1 ci-dessus, et son plafond.
TTL_DEFAUT = float(os.environ.get("LEXOS_CACHE_TTL", "1.5"))
#  Le plafond est DANS le code, pas seulement dans un commentaire : une
#  variable d'environnement mal réglée ne doit pas faire mentir le volet
#  pendant dix secondes.
TTL_MAX = 2.0


class Cache:
    """Le cache d'un module : ses lectures, leur âge, et ce qui les périme."""

    def __init__(self, ttl: float = TTL_DEFAUT):
        self.ttl = max(0.0, min(ttl, TTL_MAX))
        self._valeurs: dict = {}      # clé -> (expire_a, valeur)
        self._verrou = threading.Lock()

    # -- lecture -----------------------------------------------------------
    def lire(self, collecteurs, delai, fronts=_etat.FRONTS, replis=None):
        """Rend {clé: valeur} pour TOUS les collecteurs demandés, en ne
        relançant que ceux dont la valeur a vieilli.

        La forme du retour est exactement celle de etat.de_front() : un
        appelant ne voit pas la différence, et c'est voulu — le cache doit
        pouvoir être retiré sans réécrire personne."""
        if not collecteurs:
            return {}
        maintenant = time.monotonic()
        frais, a_lire = {}, {}
        with self._verrou:
            for cle, fonction in collecteurs.items():
                garde = self._valeurs.get(cle)
                if garde is not None and garde[0] > maintenant:
                    frais[cle] = garde[1]
                else:
                    a_lire[cle] = fonction
        #  ⚠ LES LECTURES SE FONT HORS DU VERROU. Elles durent des secondes ;
        #  le tenir pendant ce temps ferait attendre le clic suivant derrière
        #  la lecture en cours — exactement la lenteur qu'on retire.
        neuves = _etat.de_front(a_lire, delai, fronts, replis) if a_lire else {}
        if neuves and self.ttl > 0:
            expire = time.monotonic() + self.ttl
            with self._verrou:
                for cle, valeur in neuves.items():
                    self._valeurs[cle] = (expire, valeur)
        frais.update(neuves)
        return frais

    # -- invalidation ------------------------------------------------------
    def perime(self, cles=None) -> None:
        """Jeter ce qu'on croit savoir — tout, ou seulement ces clés-là.

        Appelée après CHAQUE action. Sans argument : tout, parce que le
        défaut doit être la justesse."""
        with self._verrou:
            if cles is None:
                self._valeurs.clear()
            else:
                for cle in cles:
                    self._valeurs.pop(cle, None)

    # -- pour les bancs ----------------------------------------------------
    def garde(self) -> int:
        """Combien de valeurs sont en mémoire. Sert aux bancs, et à personne
        d'autre : un module qui consulte la TAILLE d'un cache pour décider
        quelque chose s'appuierait sur un détail qui n'est pas un contrat."""
        with self._verrou:
            return len(self._valeurs)


class Registre:
    """Ce qu'une action périme. Le défaut, faute de déclaration : tout."""

    def __init__(self, cache: Cache):
        self.cache = cache
        self._perime: dict = {}

    def action_perime(self, nom: str, cles) -> None:
        """Déclarer qu'une action ne touche QUE ces clés-là.

        À n'écrire que lorsqu'on en est sûr. Se tromper ici ne fait pas
        planter : ça fait afficher une valeur périmée, sans un mot — le genre
        de défaut qui se cherche des heures."""
        self._perime[nom] = tuple(cles)

    def apres(self, nom: str = None) -> None:
        """Après une action : périmer ce qu'elle a pu changer.

        Une action INCONNUE périme tout. C'est le cas par défaut, et c'est le
        bon : un nom mal orthographié doit coûter une relecture, jamais un
        affichage faux."""
        self.cache.perime(self._perime.get(nom))
