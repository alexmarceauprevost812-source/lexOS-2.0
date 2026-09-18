"""Les radios de la machine — Wi-Fi, Bluetooth, mode avion — lues UNE fois.

═══ POURQUOI CE MODULE EXISTE ═══
Ces trois lectures existaient en DEUX exemplaires, dans settings.py et dans
volet.py. app.js du volet nommait déjà le risque :

    « la dupliquer ici donnerait deux endroits où un bogue pourrait un jour
      raconter deux choses différentes »

Ce n'était plus un risque. Les deux copies du MODE AVION ne calculaient déjà
pas la même chose :

    volet.py    : wwan dans ("disabled", "missing", "")   ← la chaîne vide compte
    settings.py : wwan dans ("disabled", "missing")       ← elle ne compte pas

Sur une machine sans modem, où « nmcli -t radio wwan » rend une ligne vide,
le volet annonçait « mode avion » et les Paramètres « non ». Deux fenêtres du
même système, deux réponses, et aucune façon de savoir laquelle croire.

═══ LA RÈGLE DE CE FICHIER ═══
None veut dire « je n'ai pas pu lire », JAMAIS « c'est éteint ». Les deux se
ressemblent dans un booléen et pas du tout à l'écran — et les confondre a
déjà coûté cher ici : la tuile Wi-Fi du volet affichait « Désactivé » faute
de réponse, et le clic, qui relit la vraie radio pour basculer à partir
d'elle, ÉTEIGNAIT un Wi-Fi qui marchait. L'étiquette disait « allumer », le
geste faisait l'inverse.

« absent » est une quatrième réponse, distincte de None : la machine n'a pas
ce matériel. C'est une tuile grisée définitive et juste ; None est une tuile
qui dit « Inconnu » et redevient vraie au prochain coup d'œil.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

_ICI = Path(__file__).resolve().parent.parent
if str(_ICI) not in sys.path:
    sys.path.insert(0, str(_ICI))

from moteur import outils as _outils        # noqa: E402

#  LIRE N'EST PAS AGIR. Une seconde et demie pour demander l'état d'une
#  radio : ce qui n'a pas répondu en une seconde et demie ne répondra pas, et
#  pendant ce temps une fenêtre entière attend. Les ACTIONS, elles, gardent
#  leurs dix à vingt secondes ailleurs — couper un « nmcli radio wifi on » au
#  milieu est pire que d'attendre.
DELAI = float(os.environ.get("LEXOS_RADIO_DELAI", "1.5"))

#  Ce que « nmcli -t radio <quoi> » peut répondre. « -t » (terse) donne des
#  mots-clés FIXES, jamais traduits — la sortie normale suit la langue du
#  système, et LexOS parle français.
MOTS = ("enabled", "disabled", "missing")


def lire(quoi: str):
    """« enabled », « disabled », « missing », « » — ou None si on n'a pas pu.

    « quoi » vaut « wifi » ou « wwan ». Rendre la chaîne BRUTE plutôt qu'un
    booléen est voulu : c'est le mode avion qui a besoin de distinguer
    « missing » (pas de modem) de « disabled » (modem éteint), et lui seul."""
    if not _outils.commande_existe("nmcli"):
        return None
    try:
        r = subprocess.run(["nmcli", "-t", "radio", quoi],
                           capture_output=True, text=True, timeout=DELAI)
    except (subprocess.SubprocessError, OSError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def wifi():
    """True, False, ou None quand on n'a pas pu lire."""
    v = lire("wifi")
    if v is None:
        return None
    if v == "missing":
        return "absent"
    return v == "enabled"


def bluetooth():
    """True, False, « absent » (pas de Bluetooth ici), ou None (pas pu lire).

    ═══ QUATRE RÉPONSES, ET IL EN FALLAIT QUATRE ═══
    Cette lecture rendait None dans trois cas différents : pas de
    bluetoothctl, pas de contrôleur, et pas pu lire. Annoncer à quelqu'un que
    sa machine n'a pas de Bluetooth parce qu'un outil a traîné une seconde,
    c'est le bogue du dock."""
    if not _outils.commande_existe("bluetoothctl"):
        return "absent"
    try:
        r = subprocess.run(["bluetoothctl", "show"],
                           capture_output=True, text=True, timeout=DELAI)
    except (subprocess.SubprocessError, OSError):
        return None
    if not r.stdout:
        #  bluetoothctl est là et ne dit rien : pas de contrôleur.
        return "absent"
    for ligne in r.stdout.splitlines():
        if ligne.strip().startswith("Powered:"):
            return ligne.split(":", 1)[1].strip() == "yes"
    return "absent"


def avion(wifi_brut=None, wwan_brut=None):
    """Le mode avion : toutes les radios éteintes. True, False, ou None.

    ═══ UNE SEULE DÉFINITION, ET C'EST TOUT L'INTÉRÊT ═══
    Il y en avait deux, et elles divergeaient sur la CHAÎNE VIDE : le volet la
    comptait comme « pas de modem », les Paramètres non. Celle qui reste est
    celle du volet, et voici pourquoi : « nmcli -t radio wwan » rend une ligne
    vide sur une machine sans modem du tout, exactement comme il rend
    « missing » sur d'autres versions. Traiter le vide comme un refus
    empêchait le mode avion de jamais s'afficher sur ces machines-là.

    Les deux lectures brutes peuvent être PASSÉES quand l'appelant les a déjà
    faites — le volet lit les deux radios de front pour ses tuiles, et les
    relire ici doublerait deux sous-processus pour rien.

    ⚠ ET SI L'UNE DES DEUX MANQUE, ON NE SAIT PAS. Décider « pas de mode
    avion » sur une lecture absente, c'est afficher Wi-Fi et Bluetooth
    allumés sur une machine où ils sont coupés."""
    w = lire("wifi") if wifi_brut is None else wifi_brut
    m = lire("wwan") if wwan_brut is None else wwan_brut
    if w is None or m is None:
        return None
    return w == "disabled" and m in ("disabled", "missing", "")
