"""Les outils du système, demandés UNE fois plutôt qu'à chaque rendu.

═══ POURQUOI CE MODULE EXISTE ═══
ALEX : « j'aimerais qu'on crée un moteur pour tous les paramètres, que ça
soit encore plus fluide et rapide ».

Compté, pas supposé : `shutil.which` apparaît 74 fois dans settings.py,
16 dans volet.py, 9 dans ia-locale.py, 4 dans partage.py — cent huit en
tout, et la plupart sont relues À CHAQUE lecture d'état. Chacune balaie le
PATH répertoire par répertoire. Prise une par une ce n'est rien ; à chaque
rafraîchissement d'un volet qui s'ouvre vingt fois par jour, c'est du
gaspillage pur.

boost/systeme.py a DÉJÀ `commande_existe()` et `executer()`. Ce module ne
les réécrit pas : il les enveloppe, et ajoute ce qui manquait — la mémoire,
et UNE politique de délai au lieu de trois.

⚠ À NE PAS CONFONDRE AVEC boost/moteur.py, qui porte le même mot et fait
autre chose : lui applique les profils de performance (voir sa propre
en-tête, qui renvoie ici en retour). Ce paquet-ci, usr/lib/lexos/moteur/,
est le socle commun des Paramètres, du volet et de leurs voisins.

═══ LA MÉMOIRE, ET POURQUOI ELLE N'EST PAS ÉTERNELLE ═══
Un outil peut APPARAÎTRE pendant la vie du processus : les Paramètres
installent des paquets (lexos-ouvrir, les mises à jour), et la page relit
son état juste après. Une mémoire éternelle ferait dire « Outil absent »
pour un outil qu'on vient d'installer sous les yeux d'Alex — et avec le
démon résident qui vient, « éternel » voudrait dire « jusqu'au prochain
redémarrage ».

D'où : une mémoire à ÉCHÉANCE, et un oubli explicite après toute action
qui installe. Trente secondes, et non les une à deux secondes du cache
d'état : ce qu'on retient ici n'est pas une VALEUR qui change (le Wi-Fi
qu'Alex coupe au clavier), c'est la présence d'un fichier exécutable, qui
ne bouge qu'à une installation — et l'installation, elle, nous prévient.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

#  boost/ est le voisin de ce paquet dans usr/lib/lexos/. On l'ajoute au
#  chemin pour pouvoir l'importer comme paquet, sans dépendre de la façon
#  dont l'appelant a été lancé.
_ICI = Path(__file__).resolve().parent.parent
if str(_ICI) not in sys.path:
    sys.path.insert(0, str(_ICI))

try:
    from boost import systeme as _boost
except Exception:                                        # noqa: BLE001
    #  ═══ « INDISPONIBLE » N'EST PAS « CASSÉ » ═══
    #  Si boost/ manque — un module copié seul, un banc qui n'emporte qu'un
    #  fichier — on ne tombe pas : on perd seulement l'enveloppe, pas la
    #  fonction. _boost vaut None et executer() fait le travail lui-même,
    #  avec exactement le même contrat de retour.
    _boost = None


# ---------------------------------------------------------------------------
#  UNE SEULE POLITIQUE DE DÉLAI
# ---------------------------------------------------------------------------
#  Il y en avait trois, écrites à trois endroits : 2 s pour lire dans
#  settings.py (_LIRE_DELAI), 120 s pour agir (_run), 30 s par défaut dans
#  boost/systeme.executer. Ce ne sont pas trois oublis, ce sont deux vrais
#  besoins et un défaut : LIRE et AGIR n'ont pas le même droit à l'attente.
#
#  LIRE : deux secondes. Le défaut était de dix, et la page entière
#  attendait. bluetoothctl sans adaptateur, nmcli pendant un balayage, une
#  imprimante réseau éteinte : ce qui ne répond pas tout de suite ne
#  répondra pas.
#
#  AGIR : deux minutes. Une mise à jour, une installation, un formatage
#  prennent légitimement du temps, et les couper au milieu est pire que
#  d'attendre.
DELAI_LIRE = float(os.environ.get("LEXOS_LIRE_DELAI", "2"))
DELAI_AGIR = float(os.environ.get("LEXOS_AGIR_DELAI", "120"))

#  Combien de temps on se souvient qu'un outil est là (ou n'y est pas).
MEMOIRE_OUTILS = float(os.environ.get("LEXOS_MEMOIRE_OUTILS", "30"))

_memo: dict[str, tuple[float, str | None]] = {}
_verrou = threading.Lock()


def chemin(nom: str) -> str | None:
    """Où est cet outil, ou None. Mémorisé le temps de MEMOIRE_OUTILS.

    Rend le CHEMIN et pas un booléen parce que quelques appelants en ont
    besoin (« shutil.which("lexos-net") or "/usr/bin/lexos-net" ») : deux
    mémoires pour la même question auraient fini par se contredire."""
    #  ⚠ LA RECHERCHE SE FAIT SOUS LE VERROU, ET C'EST UN CHOIX MESURÉ.
    #  Première version : on cherchait HORS du verrou, pour ne pas sérialiser
    #  les collecteurs menés de front. Le banc a compté 49 balayages pour 47
    #  outils distincts — deux fils avaient cherché le même outil en même
    #  temps, avant que l'un ait eu le temps d'écrire. Rien de faux, mais un
    #  contrat qu'on ne peut plus énoncer simplement, ni éprouver sans une
    #  marge floue. Or ce que coûte le verrou tenu, c'est quelques appels
    #  stat() — des microsecondes, une fois par outil. On le tient donc, et
    #  le contrat devient exact : UNE recherche par outil et par échéance.
    maintenant = time.monotonic()
    with _verrou:
        trouve = _memo.get(nom)
        if trouve is not None and trouve[0] > maintenant:
            return trouve[1]
        ou = shutil.which(nom)
        _memo[nom] = (maintenant + MEMOIRE_OUTILS, ou)
        return ou


def commande_existe(nom: str) -> bool:
    """Cet outil est-il installé ? C'est la question posée cent huit fois
    dans ce dépôt. Même mémoire que chemin(), même échéance."""
    return chemin(nom) is not None


def oublier(nom: str | None = None) -> None:
    """Oublier ce qu'on croit savoir des outils — tout, ou un seul.

    À APPELER APRÈS TOUTE ACTION QUI INSTALLE OU DÉSINSTALLE. Sans ça, la
    page dirait « Outil absent » pour un outil qu'Alex vient de voir
    s'installer, et pendant trente secondes il n'y aurait rien à comprendre.
    C'est le seul entretien que ce module demande."""
    with _verrou:
        if nom is None:
            _memo.clear()
        else:
            _memo.pop(nom, None)


def executer(argv, delai: float | None = None, entree: str | None = None):
    """Lance une commande et rend (code, sortie, erreur). Ne lève jamais.

    Le contrat est celui de boost/systeme.executer, dont c'est l'enveloppe :
    127 pour un exécutable introuvable, 124 pour un délai dépassé — les
    codes qu'un shell rendrait. On ne le duplique que si boost/ manque."""
    if delai is None:
        delai = DELAI_LIRE
    if _boost is not None:
        return _boost.executer(list(argv), delai=int(delai), entree=entree)
    try:
        r = subprocess.run(list(argv), capture_output=True, text=True,
                           timeout=delai, input=entree, check=False)
    except FileNotFoundError:
        return 127, "", f"commande introuvable : {argv[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"délai dépassé : {' '.join(argv)}"
    except OSError as erreur:
        return 1, "", str(erreur)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def lire(argv, delai: float | None = None) -> str | None:
    """Ce que dit cet outil — ou None quand on n'a PAS PU lui demander.

    ═══ LA DIFFÉRENCE AVEC sortie(), ET POURQUOI LES DEUX EXISTENT ═══
    sortie() rend "" aussi bien pour « l'outil a répondu, et sa réponse est
    vide » que pour « l'outil est absent, ou muet, ou en erreur ». Les deux
    ne se ressemblent pas à l'écran : l'un veut dire « aucun réseau », et
    l'autre « je ne sais pas s'il y en a ». C'est exactement la confusion du
    bogue du dock, qui affirmait « c'est à droite » quand il n'avait rien pu
    lire.

    lire() est la forme honnête, pour le code neuf. sortie() reste, à
    l'identique, pour les cent appels qui existent déjà : les changer d'un
    coup mêlerait un déménagement et un changement de comportement, et
    quand ça casserait on ne saurait plus lequel des deux accuser."""
    code, texte, _ = executer(argv, delai=delai)
    return texte if code == 0 else None


def sortie(argv, delai: float | None = None) -> str:
    """Ce que dit cet outil, "" si ça n'a pas marché.

    Repris tel quel de settings.py (_sortie) — même contrat, y compris son
    défaut : "" ne distingue pas « vide » de « pas pu lire ». Voir lire()."""
    texte = lire(argv, delai=delai)
    return texte or ""
