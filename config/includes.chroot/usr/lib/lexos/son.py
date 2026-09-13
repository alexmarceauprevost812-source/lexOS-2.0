"""LexOS — le son, à UN seul endroit.

═══ POURQUOI CE MODULE EXISTE ═══
Le volume et la sourdine étaient réglés par settings.py (la page Paramètres).
Le volet « Paramètres rapides » en a besoin aussi — ALEX : « le volume, je
veux qu'il s'en aille en haut du volet ». Et les touches de volume du clavier
en ont besoin une troisième fois, depuis que le greffon pulseaudio a quitté la
barre du haut.

Deux pages pour un même réglage, c'est deux endroits où un bogue pourrait un
jour raconter deux choses différentes — et la règle est déjà écrite en tête de
rapidesHTML() dans app.js : « la dupliquer ici donnerait deux endroits où un
bogue pourrait un jour raconter deux choses différentes ». Les deux pages
appellent donc ce module, et rien d'autre :

    · /usr/lib/lexos/settings.py   (la page Paramètres)
    · /usr/lib/lexos/volet.py      (le volet « rapides »)

═══ ET L'AUTRE MOTEUR, CELUI QU'ON NE REMPLACE PAS ═══
/usr/bin/lexos-son (« lexos son … », et les touches XF86Audio* du clavier qui
l'appellent) NE PASSE PAS PAR ICI, et c'est voulu. Ce n'est pas la même
question :

  · lexos-son est un PANNEAU. Il liste les sorties et les entrées, les nomme,
    permet d'en CHOISIR une, et retient ce choix. Pour ça il parle à
    WirePlumber par wpctl — le chef d'orchestre de PipeWire, le seul qui
    connaisse les identifiants de nœuds et qui retienne le périphérique par
    défaut d'une session à l'autre. pactl ne sait pas faire ça : il n'affiche
    que des noms techniques (alsa_output.pci-0000_00_1f.3…).
  · ce module ne répond qu'à trois questions — quel volume, coupé ou non,
    micro coupé ou non — et n'en pose aucune sur les périphériques. pactl
    suffit, il est toujours là (pipewire-pulse le fournit), et l'importer
    depuis Python coûte deux lignes.

Les deux lisent la MÊME machine et écrivent le MÊME réglage : wpctl et pactl
sont deux portes sur PipeWire, pas deux états. Une valeur réglée ici se lit
là-bas, et l'inverse. Ce qui devait être unifié — les trois appels pactl
recopiés entre settings.py et le volet — l'est.

═══ CE QU'IL PROMET, ET CE QU'IL NE PROMET PAS ═══
· Il ne lève JAMAIS. Une machine sans PulseAudio, sans micro, ou dont pactl
  met trop de temps à répondre, obtient une valeur neutre — pas une trace.
· Il BORNE le volume à 0-100 avant de le transmettre. Sans cette borne, un
  « 400 » venu d'une page monterait le gain bien au-delà du niveau du
  matériel : de la distorsion, et de quoi abîmer un haut-parleur.
· Une mesure indisponible se dit « indisponible » : volume -1 et micro None,
  jamais une valeur inventée. C'est ce qui permet à la page de CACHER le
  bandeau au lieu d'afficher un curseur qui ne fait rien.
"""

import shutil
import subprocess

#  pactl répond en quelques millisecondes quand tout va bien. La borne est là
#  pour le cas où le serveur de son est en train de démarrer ou de mourir :
#  un volet qui attend son curseur est un volet qui a l'air planté.
DELAI = 4

SINK = "@DEFAULT_SINK@"
SOURCE = "@DEFAULT_SOURCE@"


def disponible():
    """pactl est-il là ? C'est la seule question qui décide si le bandeau de
    son s'affiche du tout."""
    return shutil.which("pactl") is not None


def _sortie(argv):
    """La sortie d'une commande, ou une chaîne vide. Ne lève jamais."""
    try:
        r = subprocess.run(argv, capture_output=True, text=True,
                           timeout=DELAI, stdin=subprocess.DEVNULL)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _run(argv):
    """Lance une commande et rend la même forme que settings._run :
    {"ok": bool} et, en cas d'échec, {"erreur": "…"}. La page n'affiche un
    motif que si la réponse porte la clé « erreur » — sans elle, on voit
    « Échec : commande refusée » et on cherche du côté du bouton."""
    if shutil.which(argv[0]) is None:
        return {"ok": False, "erreur": f"Outil absent : {argv[0]}"}
    try:
        r = subprocess.run(argv, capture_output=True, text=True,
                           timeout=DELAI, stdin=subprocess.DEVNULL)
    except Exception as e:
        return {"ok": False, "erreur": str(e)}
    if r.returncode == 0:
        return {"ok": True}
    motif = ((r.stderr or r.stdout).strip().splitlines() or [""])[-1]
    return {"ok": False,
            "erreur": motif or f"« {argv[0]} » a échoué (code {r.returncode})"}


# =============================================================================
#  LIRE
# =============================================================================
def volume():
    """Le volume en pour-cent, ou -1 s'il n'a pas pu être lu.

    pactl rend une ligne du genre :
        Volume: front-left: 45875 /  70% / -9,29 dB, front-right: …
    On prend le PREMIER pourcentage. Les canaux peuvent différer (balance) ;
    en afficher un est honnête, en afficher la moyenne serait un chiffre que
    la machine ne connaît pas.
    """
    if not disponible():
        return -1
    for morceau in _sortie(["pactl", "get-sink-volume", SINK]).replace("/", " ").split():
        if morceau.endswith("%") and morceau[:-1].isdigit():
            return int(morceau[:-1])
    return -1


def muet():
    """Le son est-il coupé ? False quand la question ne peut pas être posée —
    et c'est le bon défaut : une icône « coupé » sur une machine dont on ne
    sait rien ferait chercher un problème qui n'existe pas."""
    return _sortie(["pactl", "get-sink-mute", SINK]).endswith("yes")


def micro_muet():
    """Le micro est-il coupé ?

    Rend None quand IL N'Y A PAS DE MICRO, ou que la question n'a pas pu être
    posée — et ce None compte : il dit à la page de ne pas afficher le bouton
    du tout, comme la tuile Bluetooth sait déjà afficher « Absent ».
    Un interrupteur de micro sur une machine sans micro est un interrupteur
    qui ne fait rien, et on met ça sur le dos du logiciel.
    """
    if not disponible():
        return None
    #  « get-source-mute » répond « Mute: yes|no ». Sur une machine sans
    #  entrée, @DEFAULT_SOURCE@ ne résout pas et la commande échoue : _sortie
    #  rend alors la chaîne vide, qui ne finit ni par yes ni par no.
    reponse = _sortie(["pactl", "get-source-mute", SOURCE])
    if reponse.endswith("yes"):
        return True
    if reponse.endswith("no"):
        return False
    return None


def etat():
    """Tout ce que le volet et les Paramètres ont besoin de savoir.

    « volume: -1 » et « micro: None » sont les deux façons de dire
    INDISPONIBLE. La page s'en sert pour ne pas dessiner ce qui ne marcherait
    pas — jamais pour afficher un zéro à la place.
    """
    if not disponible():
        return {"volume": -1, "muet": False, "micro": None}
    return {"volume": volume(), "muet": muet(), "micro": micro_muet()}


# =============================================================================
#  ÉCRIRE
# =============================================================================
def regle_volume(valeur, relatif=False):
    """Règle le volume.

    · relatif=False (le défaut) : « valeur » est un niveau ABSOLU, borné
      0-100. C'est ce qu'envoie le curseur du volet.
    · relatif=True : « valeur » est un PAS, en pour-cent, signé (« +5 »,
      « -5 »), ou le mot « plus » / « moins » (qui valent ±5). C'est ce
      qu'envoient les touches de volume du clavier.

    ═══ POURQUOI UN DRAPEAU PLUTÔT QUE DE DEVINER AU SIGNE ═══
    Première écriture : « un nombre signé est un pas, un nombre nu est un
    niveau ». Le curseur qui enverrait « -20 » — une valeur aberrante, mais
    qui arrive quand une page se trompe — aurait alors BAISSÉ de 20 au lieu
    d'être ramené à 0. Deux gestes très différents derrière une même chaîne,
    départagés par un caractère : c'est la sorte d'ambiguïté qui se paie une
    fois, tard, et qu'on ne retrouve pas. L'appelant DIT ce qu'il veut.

    ═══ LA BORNE N'EST PAS UNE PRÉCAUTION DE STYLE ═══
    Un « 400 » venu d'une page monterait le gain bien au-delà du niveau du
    matériel : de la distorsion, et de quoi abîmer un haut-parleur. Elle est
    ICI, dans le moteur, et pas dans chacune des trois pages qui l'appellent
    — une borne recopiée trois fois est une borne oubliée une fois.

    Un PAS passe par la forme relative de pactl, qui borne elle-même au
    maximum du matériel. On n'ajoute pas notre propre calcul : il faudrait
    relire le volume d'abord, et entre la lecture et l'écriture quelqu'un
    d'autre peut l'avoir changé.
    """
    if not disponible():
        return {"ok": False, "erreur": "pactl absent (paquet pulseaudio-utils)"}
    texte = str(valeur).strip()
    if relatif:
        if texte == "plus":
            texte = "+5"
        elif texte == "moins":
            texte = "-5"
        if texte[:1] not in ("+", "-") or not texte[1:].isdigit():
            return {"ok": False, "erreur": "pas de volume inattendu"}
        #  Un pas au-delà de 100 n'a aucun sens : le volume entier fait 100.
        n = min(100, int(texte[1:]))
        return _run(["pactl", "set-sink-volume", SINK, f"{texte[0]}{n}%"])
    try:
        n = int(texte)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "valeur inattendue"}
    n = max(0, min(100, n))
    return _run(["pactl", "set-sink-volume", SINK, f"{n}%"])


def regle_muet(arg="toggle"):
    """Coupe, rétablit, ou bascule le son."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if not disponible():
        return {"ok": False, "erreur": "pactl absent (paquet pulseaudio-utils)"}
    return _run(["pactl", "set-sink-mute", SINK,
                 {"on": "1", "off": "0", "toggle": "toggle"}[arg]])


def regle_micro(arg="toggle"):
    """Coupe, rétablit, ou bascule le MICRO.

    ALEX : « pour le micro juste mettre activé ou désactivé ». Pas de
    curseur — deux états, et c'est tout ce que cette fonction sait faire.

    ON REFUSE QUAND IL N'Y A PAS DE MICRO, au lieu de laisser pactl échouer
    avec un message d'outil : « aucun micro » est une phrase qu'on comprend,
    « Failure: No such entity » ne l'est pas.
    """
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if not disponible():
        return {"ok": False, "erreur": "pactl absent (paquet pulseaudio-utils)"}
    if micro_muet() is None:
        return {"ok": False, "erreur": "aucun micro sur cette machine"}
    return _run(["pactl", "set-source-mute", SOURCE,
                 {"on": "1", "off": "0", "toggle": "toggle"}[arg]])
