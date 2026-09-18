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
        #  ═══ DEUX LECTURES EN MÊME TEMPS N'EN FONT QU'UNE ═══
        #  Le démon PRÉCHAUFFE : il lance la lecture d'état dès qu'on lui dit
        #  qu'une fenêtre s'ouvre, pour qu'elle se fasse PENDANT le démarrage
        #  de Chromium au lieu d'après. Mais la page, une seconde plus tard,
        #  demande la même chose — et sans ce verrou elle lancerait une
        #  SECONDE lecture complète en parallèle de la première : deux fois
        #  les sous-processus, et le préchauffage ne servirait à rien.
        #  Ici, la deuxième ATTEND la première et repart avec son résultat.
        #  Ce n'est pas un cache plus long : c'est la même lecture, partagée.
        self._en_vol = threading.Lock()
        #  ═══ UNE LECTURE PARTIE AVANT L'ACTION NE DOIT PAS REVENIR APRÈS ═══
        #  Les lectures durent des secondes et se font HORS du verrou (voir
        #  plus bas, c'est voulu). Une lecture partie AVANT un clic peut donc
        #  se terminer APRÈS lui — et, telle quelle, elle réinsérait sa valeur
        #  d'AVANT avec un TTL tout neuf. La tuile affichait alors l'état
        #  d'avant le clic pendant une seconde et demie, exactement le périmé
        #  silencieux que ce module existe pour empêcher. Le défaut était
        #  antérieur aux clés partielles et identique avec l'ancien
        #  « tout périmer » : ce n'est pas une clé qui manquait, c'est une
        #  ESTAMPILLE.
        #  On marque donc chaque clé : « _epoque » compte les invalidations
        #  totales, « _gen[clé] » les invalidations ciblées. Une lecture note
        #  la marque avant de partir et ne range son résultat que si la marque
        #  n'a pas bougé. Sinon elle rend sa valeur à SON appelant — qui a
        #  demandé avant le clic, et a droit à ce qu'il a demandé — mais ne la
        #  garde pas.
        self._epoque = 0
        self._gen: dict = {}

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
            #  ═══ LA MARQUE EST PRISE POUR TOUTES LES CLÉS, PAS SEULEMENT
            #      CELLES QU'ON VA RELIRE ═══
            #  La première version de l'estampille ne marquait que « reste ».
            #  Une clé servie DEPUIS LE CACHE était jugée fraîche à l'entrée
            #  de l'appel et rendue à la sortie, des secondes plus tard, sans
            #  jamais être reconfrontée à une invalidation survenue entre les
            #  deux. MESURÉ sur les sept clés du volet : clic Wi-Fi, la page
            #  relit (un nmcli lent), deuxième clic sur Bluetooth pendant ce
            #  nmcli — et la réponse rendait « bt_brut=True », l'état d'AVANT,
            #  pendant que r_wifi, seule clé marquée, était juste. La page
            #  REMPLACE toute la grille : la tuile Bluetooth se rallumait
            #  par-dessus l'optimiste, et le clic suivant rallumait pour de
            #  bon. Le clic qui fait l'inverse de son étiquette, la troisième
            #  fois dans ce dépôt.
            epoque = self._epoque
            marques = {cle: self._gen.get(cle, 0) for cle in collecteurs}
            for cle, fonction in collecteurs.items():
                garde = self._valeurs.get(cle)
                if garde is not None and garde[0] > maintenant:
                    frais[cle] = garde[1]
                else:
                    a_lire[cle] = fonction
        if not a_lire:
            return self._encore_valides(frais, epoque, marques, replis)
        #  ⚠ LES LECTURES SE FONT HORS DU VERROU DE LA MÉMOIRE. Elles durent
        #  des secondes ; le tenir pendant ce temps ferait attendre le clic
        #  suivant derrière la lecture en cours — exactement la lenteur qu'on
        #  retire. En revanche on prend « _en_vol », qui ne protège pas des
        #  données mais empêche DEUX lectures identiques de partir ensemble.
        with self._en_vol:
            #  Pendant qu'on attendait notre tour, l'autre lecture a peut-être
            #  déjà rempli le cache. On revérifie avant de payer.
            maintenant = time.monotonic()
            reste = {}
            with self._verrou:
                for cle, fonction in a_lire.items():
                    garde = self._valeurs.get(cle)
                    if garde is not None and garde[0] > maintenant:
                        frais[cle] = garde[1]
                    else:
                        reste[cle] = fonction
            #  ═══ CHAQUE CLÉ PORTE L'HEURE DE SA PROPRE LECTURE ═══
            #  L'expiration se calculait APRÈS le retour du lot, donc une clé
            #  lue en 0 ms recevait la même échéance que celle lue en 1,9 s :
            #  le périmé servi valait « durée du lot + TTL », pas « TTL ».
            #  MESURÉ, avec un outil qui traîne (le cas que etat.py nomme
            #  lui-même : imprimante éteinte, bluetoothctl sans adaptateur) :
            #  3,25 s d'âge dans le volet, 5,25 s dans les Paramètres — au
            #  DESSUS du plafond TTL_MAX = 2,0 que ce fichier grave dans le
            #  code deux écrans plus haut. Chaque collecteur note donc l'heure
            #  à laquelle IL a fini.
            debut = time.monotonic()
            horodate: dict = {}

            def _date(cle, fonction):
                def _appel():
                    try:
                        return fonction()
                    finally:
                        horodate[cle] = time.monotonic()
                return _appel

            neuves = (_etat.de_front({c: _date(c, f) for c, f in reste.items()},
                                     delai, fronts, replis)
                      if reste else {})
        if neuves and self.ttl > 0:
            with self._verrou:
                for cle, valeur in neuves.items():
                    #  Une action a-t-elle périmé cette clé PENDANT la lecture ?
                    #  Alors ce qu'on tient est l'état d'AVANT : on ne le range
                    #  pas. La prochaine demande relira, et c'est le prix juste.
                    if (self._epoque != epoque
                            or self._gen.get(cle, 0) != marques.get(cle, 0)):
                        continue
                    #  Pas d'horodate = le collecteur n'a jamais fini (délai
                    #  dépassé, c'est un repli) : on prend le début du lot,
                    #  c'est-à-dire la borne la plus courte.
                    self._valeurs[cle] = (horodate.get(cle, debut) + self.ttl,
                                          valeur)
        frais.update(neuves)
        return self._encore_valides(frais, epoque, marques, replis)

    def _encore_valides(self, lu, epoque, marques, replis):
        """Retire de la réponse ce qu'une action a périmé PENDANT l'appel.

        Ce qui a bougé ne vaut pas « faux » : ça vaut « je n'ai pas pu lire ».
        On rend donc le repli de l'appelant — dans le volet, le jeton qui
        grise la tuile — et jamais la valeur d'avant le clic. Une tuile grise
        pendant un rafraîchissement se rattrape ; une tuile qui ment invite à
        un clic qui fait l'inverse de son étiquette."""
        replis = replis or {}
        with self._verrou:
            bouge = [cle for cle in lu
                     if self._epoque != epoque
                     or self._gen.get(cle, 0) != marques.get(cle, 0)]
        for cle in bouge:
            lu[cle] = replis.get(cle)
        return lu

    # -- invalidation ------------------------------------------------------
    def perime(self, cles=None) -> None:
        """Jeter ce qu'on croit savoir — tout, ou seulement ces clés-là.

        Appelée après CHAQUE action. Sans argument : tout, parce que le
        défaut doit être la justesse."""
        with self._verrou:
            if cles is None:
                self._valeurs.clear()
                #  L'époque couvre AUSSI les clés qu'on n'a jamais vues : une
                #  lecture en vol sur une clé absente de _gen doit être jetée
                #  elle aussi.
                self._epoque += 1
            else:
                for cle in cles:
                    self._valeurs.pop(cle, None)
                    self._gen[cle] = self._gen.get(cle, 0) + 1

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
