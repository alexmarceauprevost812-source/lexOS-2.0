#!/usr/bin/env python3
"""
LexOS — le volet qui descend de la barre du haut.

CE QUE C'EST, ET POURQUOI CE N'EST PAS UNE FENÊTRE.
Alex a demandé qu'un clic sur l'heure ouvre « comme un menu qui ouvre
tranquillement et fluide en descendant », montrant les notifications et
l'agenda ; pareil pour la météo. Une FENÊTRE et un VOLET ne sont pas la même
chose : une fenêtre se déplace, se redimensionne, se range dans Alt+Tab. Un
volet appartient à la barre — il en descend, un clic ailleurs le referme, et
il ne laisse aucune trace dans la liste des fenêtres.

POURQUOI LA MÊME PAGE WEB QUE LA DÉMO.
La règle qu'Alex a posée : « tout ce qu'on fait sur Vercel on le met aussi
dans l'ISO ». Le seul moyen SÛR que les deux se ressemblent vraiment est
qu'ils partagent le dessin, pas qu'on le recopie à la main d'un côté puis de
l'autre. Le volet est donc une fenêtre Qt sans cadre qui affiche une page
locale — même patron que les Paramètres (settings.py) et Cartes (cartes.py),
et même CSS que la démo. Ce qui change d'un côté se voit de l'autre.

CE QUI REND L'ANIMATION IDENTIQUE À LA DÉMO.
Elle n'est pas jouée par Qt mais par la PAGE, en CSS, avec exactement la même
courbe et la même durée que sur Vercel. Qt se contente d'ouvrir une fenêtre
transparente déjà à sa taille finale ; le volet s'y déplie tout seul. Une
animation jouée par Qt sur la géométrie de la fenêtre aurait redemandé un
redimensionnement au serveur X à chaque image — saccadé sur un portable de
2016 — et surtout elle n'aurait pas eu la même tête que la démo.

LA SÉCURITÉ, comme partout ailleurs dans LexOS : la page ne peut demander que
les actions de la liste blanche ACTIONS, les arguments sont validés contre des
ensembles fermés, et subprocess reçoit toujours une LISTE, jamais un shell.
"""
import functools
import http.server
import json
import mimetypes
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, date
from pathlib import Path

#  ═══ LE MOTEUR DU SON EST PARTAGÉ — IL N'EST PAS ÉCRIT ICI ═══
#  ALEX : « le volume, je veux qu'il s'en aille en haut du volet », « pour le
#  micro juste mettre activé ou désactivé ».
#  La règle est déjà écrite en tête de rapidesHTML() dans app.js : « la
#  dupliquer ici donnerait deux endroits où un bogue pourrait un jour
#  raconter deux choses différentes ». Les Paramètres, ce volet et les
#  touches XF86Audio* du clavier appellent donc TOUS /usr/lib/lexos/son.py —
#  mêmes commandes, mêmes bornes, mêmes replis.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import son as _son  # noqa: E402
#  ═══ LES OUTILS DU SYSTÈME, DEMANDÉS UNE FOIS ═══
#  « shutil.which » balaie le PATH répertoire par répertoire, et il
#  était appelé cent dix fois dans ce dépôt, la plupart à CHAQUE
#  lecture d'état. moteur/outils.py garde la réponse trente secondes
#  et l'oublie sur demande — après une installation, notamment.
from moteur import outils as _outils  # noqa: E402
from moteur import service as _service  # noqa: E402
from moteur import etat as _etat_moteur  # noqa: E402
from moteur import registre as _registre  # noqa: E402
from moteur import fenetre as _fenetre  # noqa: E402

BASE_DIR = Path(os.environ.get("LEXOS_VOLET_DIR", "/usr/share/lexos/volet"))
WEB_DIR = BASE_DIR / "web"

#  Les deux volets existants. La liste est fermée : « lexos-volet <quoi> »
#  n'ouvre rien d'autre, et le nom ne sert jamais à construire un chemin.
VOLETS = {"agenda", "meteo", "rapides"}

CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
DONNEES = Path(os.environ.get("XDG_DATA_HOME",
                              Path.home() / ".local" / "share")) / "lexos"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
AGENDA = DONNEES / "agenda.json"


# =============================================================================
#  Les notifications
# =============================================================================

#  LE MODE D'APPARENCE, POUR LA PAGE.
#  lexos-theme-gen écrit « sombre » ou « clair » dans ~/.config/lexos/mode
#  depuis toujours. Avant ce correctif, personne ne le lisait côté panneau :
#  « lexos theme clair » repeignait les fenêtres GTK en crème et laissait les
#  trois panneaux web NOIRS, en négatif du reste du bureau.
#  On le passe donc en ?mode=… — pas de nouveau point d'entrée, pas de requête
#  supplémentaire, et l'attribut est posé avant le premier rendu.
def _mode_apparence() -> str:
    try:
        base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
        valeur = (Path(base) / "lexos" / "mode").read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError, ValueError):
        #  PAS SEULEMENT OSError. Un fichier « mode » ecrit dans un autre
        #  encodage leve UnicodeDecodeError, qui n'est pas une OSError : le
        #  panneau mourait alors AVANT d'ouvrir sa fenetre, pour un fichier de
        #  six octets. Un reglage d'apparence illisible doit faire retomber sur
        #  le mode sombre, jamais empecher les Parametres de s'ouvrir.
        return "sombre"
    #  Tout ce qui n'est pas explicitement « clair » reste sombre : un fichier
    #  vide, tronqué ou écrit par une version future ne doit pas blanchir
    #  l'écran d'un coup.
    return "clair" if valeur == "clair" else "sombre"

def _notifications():
    """Les notifications récentes, lues dans le journal de xfce4-notifyd.

    POURQUOI CE JOURNAL ET PAS UN À NOUS. xfce4-notifyd est le service qui
    reçoit RÉELLEMENT les notifications du système — batterie faible, clé USB
    branchée, mise à jour disponible. En tenir un deuxième en parallèle
    donnerait deux listes qui ne diraient pas la même chose. On lit donc la
    sienne. C'est aussi pour ça que xfce4-notifyd.xml active
    « notification-log » : sans ça, ce fichier n'existe pas et le volet
    n'aurait rien à montrer.

    Le format est un fichier de clés à la GLib : une section par notification,
    dont le nom est un horodatage. On le lit défensivement — un journal
    corrompu doit donner un volet vide, jamais une fenêtre qui ne s'ouvre pas.
    """
    chemin = CACHE / "xfce4" / "notifyd" / "log"
    if not chemin.is_file():
        return []
    import configparser
    lecteur = configparser.RawConfigParser(strict=False)
    #  Les résumés contiennent des majuscules qu'il ne faut pas écraser.
    lecteur.optionxform = str
    try:
        lecteur.read(chemin, encoding="utf-8")
    except (OSError, configparser.Error):
        return []

    sortie = []
    for nom in lecteur.sections():
        s = lecteur[nom]
        quand = ""
        #  Le nom de section EST l'horodatage, en secondes depuis 1970.
        try:
            quand = datetime.fromtimestamp(int(nom)).strftime("%H:%M")
        except (ValueError, OSError, OverflowError):
            quand = s.get("timestamp", "")
        sortie.append({
            "app": s.get("app_name", "").strip(),
            "titre": s.get("summary", "").strip(),
            "corps": s.get("body", "").strip(),
            "quand": quand,
            "cle": nom,
        })
    #  Les plus récentes en tête, et pas plus de cinquante : un journal de
    #  plusieurs milliers d'entrées ferait ramer l'ouverture du volet.
    sortie.sort(key=lambda n: n["cle"], reverse=True)
    return sortie[:50]


def act_notif_vide(_arg=None):
    """Vider le journal des notifications. On ÉCRASE le fichier au lieu de le
    supprimer : xfce4-notifyd garde son descripteur ouvert et recréerait un
    fichier qu'il serait seul à voir."""
    chemin = CACHE / "xfce4" / "notifyd" / "log"
    try:
        if chemin.is_file():
            chemin.write_text("", encoding="utf-8")
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "erreur": str(e)}


# =============================================================================
#  L'agenda
# =============================================================================
def _agenda_lit():
    """Les rendez-vous, dans un fichier à nous.

    POURQUOI PAS CELUI DE GNOME AGENDA. gnome-calendar range ses événements
    dans Evolution Data Server, qu'on ne peut interroger qu'en passant par
    ses bibliothèques — une dépendance lourde, et un service qui doit tourner.
    Le volet doit s'ouvrir instantanément au clic sur l'heure, y compris juste
    après le démarrage. Il garde donc sa propre liste, simple et lisible.
    gnome-calendar reste là pour qui veut des comptes en ligne : les deux ne
    se gênent pas, ils ne prétendent simplement pas être la même chose.
    """
    try:
        donnees = json.loads(AGENDA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(donnees, dict):
        return {}
    #  On filtre à la lecture : un fichier édité à la main ne doit pas pouvoir
    #  injecter n'importe quoi dans la page.
    propre = {}
    for jour, liste in donnees.items():
        if not isinstance(jour, str) or not isinstance(liste, list):
            continue
        evenements = []
        for e in liste[:50]:
            if not isinstance(e, dict):
                continue
            titre = str(e.get("titre", ""))[:120]
            heure = str(e.get("heure", ""))[:5]
            #  LA FIN AUSSI. Ce filtre ne recopie que les champs qu'il
            #  connaît — c'est sa raison d'être, un fichier édité à la main
            #  ne doit pas pouvoir injecter n'importe quoi dans la page. Mais
            #  un champ NOUVEAU qu'on oublie d'ajouter ici est écrit sur le
            #  disque et jeté à la relecture : le rendez-vous s'enregistre,
            #  et son heure de fin disparaît sans un mot.
            #
            #  C'est exactement ce qui est arrivé en ajoutant « fin » : le
            #  moteur l'acceptait, la page l'envoyait, le fichier la portait
            #  — et elle n'arrivait jamais à l'écran. Trouvé en FAISANT
            #  TOURNER le circuit complet, pas en le relisant.
            fin = str(e.get("fin", ""))[:5]
            if titre:
                evenements.append({"titre": titre, "heure": heure, "fin": fin})
        if evenements:
            propre[jour] = evenements
    return propre


def _agenda_ecrit(donnees):
    try:
        DONNEES.mkdir(parents=True, exist_ok=True)
        #  Écriture par fichier temporaire puis remplacement : une coupure de
        #  courant au mauvais moment ne peut pas laisser un agenda à moitié
        #  écrit, donc illisible.
        temporaire = AGENDA.with_suffix(".json.tmp")
        temporaire.write_text(json.dumps(donnees, ensure_ascii=False, indent=1),
                              encoding="utf-8")
        temporaire.replace(AGENDA)
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "erreur": str(e)}


def _jour_valide(texte):
    """AAAA-MM-JJ, et une VRAIE date. « 2026-02-31 » a la bonne forme mais
    n'existe pas ; le laisser passer donnerait un rendez-vous invisible."""
    try:
        date.fromisoformat(str(texte))
        return True
    except (ValueError, TypeError):
        return False


def act_agenda_ajoute(arg):
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    jour = str(arg.get("jour", ""))
    titre = str(arg.get("titre", "")).strip()[:120]
    heure = str(arg.get("heure", "")).strip()[:5]
    #  ALEX : « ajouter une heure de fin d'événement — dans le calendrier ».
    #  Un rendez-vous n'avait qu'un début : « 09:00 Dentiste » ne disait pas
    #  s'il fallait garder l'avant-midi. La fin reste FACULTATIVE — beaucoup
    #  de rendez-vous n'en ont pas, et en exiger une ferait du tort au geste
    #  rapide qui marchait déjà.
    fin = str(arg.get("fin", "")).strip()[:5]
    if not _jour_valide(jour):
        return {"ok": False, "erreur": "date invalide"}
    if not titre:
        return {"ok": False, "erreur": "il faut un titre"}
    #  UNE SEULE RÈGLE D'HEURE, POUR LES DEUX. Deux copies de la même
    #  vérification, c'est deux chances de diverger — le défaut que ce dépôt
    #  paie le plus cher.
    def _heure_valide(h):
        return (len(h) == 5 and h[2] == ":" and h[:2].isdigit()
                and h[3:].isdigit() and int(h[:2]) < 24 and int(h[3:]) < 60)
    if heure and not _heure_valide(heure):
        return {"ok": False, "erreur": "heure invalide (HH:MM)"}
    if fin and not _heure_valide(fin):
        return {"ok": False, "erreur": "heure de fin invalide (HH:MM)"}
    #  UNE FIN SANS DÉBUT NE VEUT RIEN DIRE. On le dit plutôt que de la
    #  ranger en silence : l'utilisateur croirait l'avoir enregistrée.
    if fin and not heure:
        return {"ok": False, "erreur": "une heure de fin demande une heure de début"}
    #  ET ELLE DOIT VENIR APRÈS. « de 14:00 à 09:00 » n'est pas un
    #  rendez-vous, c'est une faute de frappe — autant la relever tout de
    #  suite, pendant qu'on a encore le clavier sous les doigts.
    if fin and heure and fin <= heure:
        return {"ok": False, "erreur": "la fin doit venir après le début"}
    donnees = _agenda_lit()
    donnees.setdefault(jour, []).append({"titre": titre, "heure": heure, "fin": fin})
    #  Triés par heure : un jour chargé se lit dans l'ordre où il se vivra.
    donnees[jour].sort(key=lambda e: e.get("heure") or "99:99")
    return _agenda_ecrit(donnees)


def act_agenda_enleve(arg):
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    jour = str(arg.get("jour", ""))
    try:
        rang = int(arg.get("rang", -1))
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "rang invalide"}
    donnees = _agenda_lit()
    if jour not in donnees or not (0 <= rang < len(donnees[jour])):
        return {"ok": False, "erreur": "introuvable"}
    donnees[jour].pop(rang)
    if not donnees[jour]:
        del donnees[jour]
    return _agenda_ecrit(donnees)


# =============================================================================
#  La météo — on demande à lexos-meteo, qui sait déjà tout faire
# =============================================================================
def _meteo():
    if not _outils.commande_existe("lexos-meteo"):
        return {"ville": None, "erreur": "lexos-meteo absent"}
    try:
        r = subprocess.run(["lexos-meteo", "--json"],
                           capture_output=True, text=True, timeout=20)
        return json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError) as e:
        return {"ville": None, "erreur": str(e)}


def act_meteo_ville(_arg=None):
    """Ouvre le choix de ville. detach : c'est une fenêtre à part, et le volet
    doit pouvoir se refermer sans l'emporter."""
    if not _outils.commande_existe("lexos-meteo"):
        return {"ok": False, "erreur": "lexos-meteo absent"}
    subprocess.Popen(["lexos-meteo", "--choisir"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


# =============================================================================
#  Les paramètres rapides — la grille de bascules, sous le bouton « ▲ »
# =============================================================================
#  MÊME RÈGLE QUE PARTOUT : « tout ce qu'on fait sur Vercel on le met aussi
#  dans l'ISO ». La démo affiche huit tuiles rondes sous le bouton « ▲ » —
#  Wi-Fi, Bluetooth, mode avion, partager, performance, thème, clavier,
#  effets TV. Avant ce volet, ce bouton (greffon 12 de xfce4-panel.xml)
#  ouvrait directement la fenêtre COMPLÈTE des Paramètres : pas de bascule
#  rapide, contrairement à la démo — c'est ce trou que ce volet comble.
#
#  CE QUI EST VOLONTAIREMENT ABSENT, ET POURQUOI. La démo simule, sous les
#  tuiles Wi-Fi et Bluetooth, une petite liste de réseaux et d'appareils.
#  Cette liste existe déjà, en vrai, dans Paramètres → Réseau et → Bluetooth
#  (settings.py) : la reproduire ici donnerait deux endroits où un bogue
#  pourrait un jour raconter deux choses différentes. La tuile Clavier suit
#  le même principe et ouvre directement Paramètres sur sa page — exactement
#  ce que fait openSettings('clavier') dans la démo.
#
#  LES COMMANDES SONT CELLES DE settings.py, PAS UNE VERSION PARALLÈLE.
#  nmcli pour le Wi-Fi et bluetoothctl pour le Bluetooth se passent de
#  sudo — c'est déjà comme ça que la fenêtre des Paramètres les bascule.
#  « lexos-net avion » et « lexos theme »/« lexos crt », eux, passent par
#  need_root() côté lexos-net : ça demande un mot de passe sur une machine
#  installée (sudo sans mot de passe n'existe que sur la session démo, voir
#  le hook 0400) — une limite déjà présente dans les Paramètres, pas une
#  régression de ce volet.
PERF_LABEL = {"petit": "Petit", "medium": "Médium",
              "performant": "Performant", "max": "Performance max"}


def _wifi_radio_etat():
    if not _outils.commande_existe("nmcli"):
        return False
    try:
        r = subprocess.run(["nmcli", "-t", "radio", "wifi"],
                           capture_output=True, text=True, timeout=5)
    except (subprocess.SubprocessError, OSError):
        return False
    return r.stdout.strip() == "enabled"


def _bt_radio_etat():
    """True/False si on a lu l'état, « absent » s'il n'y a pas de Bluetooth
    sur cette machine, None si on n'a PAS PU lire.

    ═══ TROIS RÉPONSES, PAS DEUX ═══
    Cette fonction rendait None dans les trois cas. « Pas de Bluetooth » et
    « bluetoothctl n'a pas répondu » ne se ressemblent pourtant pas du tout à
    l'écran : le premier est une tuile grisée définitive et juste, le second
    une tuile qui doit dire « Inconnu » et redevenir vraie au prochain coup
    d'œil. Les confondre, c'est annoncer à quelqu'un que sa machine n'a pas
    de Bluetooth parce qu'un outil a traîné une seconde."""
    if not _outils.commande_existe("bluetoothctl"):
        return "absent"
    try:
        r = subprocess.run(["bluetoothctl", "show"],
                           capture_output=True, text=True, timeout=_LIRE_DELAI)
    except (subprocess.SubprocessError, OSError):
        return None
    if not r.stdout:
        #  bluetoothctl est là et ne dit rien : pas de contrôleur.
        return "absent"
    for ligne in r.stdout.splitlines():
        if ligne.strip().startswith("Powered:"):
            return ligne.split(":", 1)[1].strip() == "yes"
    return "absent"


def _avion_radio_etat():
    """Même calcul que avion_state() dans lexos-net et _mode_apparence()
    ici : « -t » (terse) donne des mots-clés fixes, jamais traduits."""
    if not _outils.commande_existe("nmcli"):
        return False
    try:
        wifi = subprocess.run(["nmcli", "-t", "radio", "wifi"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
        wwan = subprocess.run(["nmcli", "-t", "radio", "wwan"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return False
    return wifi == "disabled" and wwan in ("disabled", "missing", "")


def _perf_etat():
    try:
        profil = Path("/etc/lexos/performance").read_text(encoding="utf-8").strip()
    except OSError:
        profil = ""
    return profil if profil in PERF_LABEL else "medium"


def _crt_rapides_etat():
    try:
        return (CONF / "crt").read_text(encoding="utf-8").strip() != "off"
    except OSError:
        return True


#  ═══ SIX SECONDES POUR OUVRIR UN VOLET DE 340 PIXELS ═══
#  ALEX : « quand on ouvre la page des paramètres ça prend environ 3 secondes
#  avant de voir de quoi ». MESURÉ sur ce volet-ci, avec des outils qui
#  répondent en 1,5 s — ce que fait une vraie machine quand nmcli interroge
#  la radio, bluetoothctl un adaptateur, pactl un serveur de son qui démarre :
#
#      volet « rapides », en file (avant) ...... 6032 ms
#      volet « agenda » / « météo » ............    0 ms
#
#  Six secondes, et personne ne s'attendait : ces appels étaient écrits les
#  uns SOUS les autres, donc lancés les uns APRÈS les autres. Sept commandes
#  externes en file — dont TROIS que j'ai ajoutées moi-même avec le bandeau
#  de son. C'est ma correction qui a fait passer ce volet de trois secondes
#  à six.
#
#  LES PARAMÈTRES, EUX, AVAIENT DÉJÀ LE REMÈDE : settings.py mène ses
#  collecteurs de front (_de_front) avec un délai. Ce volet-ci ne l'avait pas.
#  On ne recopie pas ce code — il tient à un pool, un délai et une règle :
#  ce qui n'a pas répondu vaut « je ne sais pas », JAMAIS une valeur inventée.
#  C'est la leçon du bogue du dock, où « je ne sais pas » était devenu
#  « c'est à droite ».
_RAPIDES_DELAI = float(os.environ.get("LEXOS_VOLET_DELAI", "2"))

#  ═══ LE BUDGET DOIT ÊTRE PLUS GRAND QUE CE QU'IL BORNE ═══
#  Première version : budget commun de 2 s, et des lectures à 5 s chacune.
#  L'échéance tombait donc TOUJOURS la première, les délais internes ne
#  servaient plus à rien, et le volet affichait ses valeurs de repli à
#  chaque ouverture un peu lente. Un garde-fou plus court que ce qu'il
#  garde ne garde rien.
#  LIRE N'EST PAS AGIR : une seconde et demie pour demander l'état d'une
#  radio, comme les deux secondes de settings.py. Les ACTIONS gardent leurs
#  dix à vingt secondes — couper un « nmcli radio wifi on » au milieu est
#  pire que d'attendre.
_LIRE_DELAI = float(os.environ.get("LEXOS_VOLET_LIRE", "1.5"))


#  ═══ _de_front EST PARTI DANS moteur/etat.py ═══
#  Il y en avait DEUX exemplaires, ici et dans settings.py, avec le même
#  piège du « with ThreadPoolExecutor » (dont la sortie ATTEND les fils
#  qu'on vient d'abandonner) et la même règle : ce qui n'a pas répondu vaut
#  « je ne sais pas », JAMAIS une valeur inventée.
#  Ce qui reste ICI, c'est la forme d'appel propre au volet : chaque tuile
#  choisit SA valeur de repli — un booléen manquant n'a pas la même tête
#  qu'une liste manquante — là où les Paramètres se contentent de None.
#  ═══ LE VOLET S'OUVRE VINGT FOIS PAR JOUR, ET RELISAIT TOUT À CHAQUE CLIC ═══
#  Le cache vaut encore plus ici que dans les Paramètres : une tuile qu'on
#  bascule relançait nmcli, bluetoothctl et pactl pour redessiner la grille.
#  Une seconde et demie de mémoire, et toute action la jette.
_CACHE = _registre.Cache()
_REGISTRE = _registre.Registre(_CACHE)


def _de_front(taches):
    """taches : {clé: (appelable, valeur de repli)}."""
    return _CACHE.lire(
        {c: f for c, (f, _) in taches.items()},
        _RAPIDES_DELAI,
        replis={c: r for c, (_, r) in taches.items()})


def _apres_action(nom=""):
    """Après un clic : la mémoire des outils et les lectures périmées."""
    _outils.oublier()
    _REGISTRE.apres(nom)


def _radio_nmcli(quoi):
    """Une seule lecture de radio, brute. Rend « enabled », « disabled »,
    « missing » — ou None quand on n'a pas pu lire.

    ═══ « nmcli -t radio wifi » ÉTAIT APPELÉ DEUX FOIS ═══
    Une fois par _avion_radio_etat (qui lit wifi ET wwan pour décider du mode
    avion), une fois par _wifi_radio_etat. Le même processus, la même réponse,
    deux attentes. Ici on lit chaque radio UNE fois, les deux de front, et on
    DÉDUIT les deux réponses. Les deux fonctions d'origine restent : les
    actions (act_rapides_wifi, act_rapides_avion) s'en servent, et elles n'ont
    qu'une seule lecture à faire au moment d'un clic.

    « -t » (terse) donne des mots-clés fixes, jamais traduits — contrairement
    à la sortie normale de nmcli, qui suit la langue du système (fr_CA sur
    LexOS).
    """
    if not _outils.commande_existe("nmcli"):
        return None
    try:
        return subprocess.run(["nmcli", "-t", "radio", quoi],
                              capture_output=True, text=True,
                              timeout=_LIRE_DELAI).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return None


#  ═══ « JE N'AI PAS PU LIRE » N'EST PAS UNE VALEUR ═══
#  Ce jeton est le repli de CHAQUE lecture menée de front. Il ne peut se
#  confondre avec rien : ni avec None (que _bt_radio_etat rend déjà pour
#  « cette machine n'a pas de Bluetooth »), ni avec False, ni avec -1.
#
#  ⚠ POURQUOI IL A FALLU L'INVENTER, ET CE QUE ÇA A COÛTÉ. La première
#  version donnait à chaque lecture une valeur de repli « raisonnable » :
#  Wi-Fi → False, thème → « sombre », effets TV → True. Résultat mesuré sur
#  le chemin du Wi-Fi : la lecture dépasse l'échéance, la tuile affiche
#  « Désactivé » — une valeur INVENTÉE — et le clic, lui, appelle
#  act_rapides_wifi() qui relit la VRAIE radio et bascule à partir d'elle.
#  L'étiquette disait « allumer », le clic ÉTEIGNAIT un Wi-Fi qui marchait.
#  C'est le bogue du dock, avec une action nuisible au bout.
#
#  On ne remplit donc plus les trous : on les DÉCLARE, et la page grise la
#  tuile en disant « Inconnu ». Une tuile qu'on ne peut pas lire est une
#  tuile qu'on ne doit pas laisser cliquer.
_INCONNU = object()


def _rapides_etat():
    #  Tout part en même temps. AUCUNE valeur de repli : ce qui n'a pas
    #  répondu est marqué inconnu, et la page le dit.
    lu = _de_front({
        "r_wifi": (lambda: _radio_nmcli("wifi"), _INCONNU),
        "r_wwan": (lambda: _radio_nmcli("wwan"), _INCONNU),
        "bt_brut": (_bt_radio_etat, _INCONNU),
        "perf": (_perf_etat, _INCONNU),
        "theme": (_mode_apparence, _INCONNU),
        "crt": (_crt_rapides_etat, _INCONNU),
        "son": (_son.etat, _INCONNU),
    })
    inconnu = []
    #  Le même calcul qu'avion_state() dans lexos-net, à partir des deux
    #  lectures brutes. Une radio qu'on n'a PAS pu lire (None) ne compte pas
    #  comme « éteinte » : on ne déclare pas le mode avion sur une absence de
    #  réponse — ce serait afficher Wi-Fi et Bluetooth éteints sur une
    #  machine où ils marchent.
    #  Une radio qu'on n'a PAS pu lire ne compte pas comme « éteinte » : on
    #  ne déclare pas le mode avion sur une absence de réponse. Et si l'une
    #  des deux manque, on ne sait pas non plus si l'avion est actif.
    #  ⚠ « nmcli absent » COMPTE COMME « PAS LU », et il a fallu le mesurer
    #  pour le voir : _radio_nmcli rend None aussi bien quand l'outil manque
    #  que quand la lecture échoue, et « None == "enabled" » vaut False —
    #  donc la tuile affichait « Désactivé » sur une machine sans nmcli, avec
    #  le même clic nuisible au bout. Pour Alex, les deux cas sont le même :
    #  on ne sait pas.
    def _lu(cle):
        return lu[cle] is not _INCONNU and lu[cle] is not None

    radios_lues = _lu("r_wifi") and _lu("r_wwan")
    avion = (radios_lues
             and lu["r_wifi"] == "disabled"
             and lu["r_wwan"] in ("disabled", "missing", ""))
    if not radios_lues:
        inconnu.append("avion")
    if not _lu("r_wifi"):
        inconnu.append("wifi")
    if lu["bt_brut"] is _INCONNU or lu["bt_brut"] is None:
        inconnu.append("bt")
    if lu["crt"] is _INCONNU:
        inconnu.append("crt")
    if lu["perf"] is _INCONNU:
        inconnu.append("perf")
    perf = lu["perf"] if lu["perf"] in PERF_LABEL else "medium"
    son = lu["son"] if lu["son"] is not _INCONNU else {
        #  Pas lu = pas de bandeau, exactement comme « pas de pactl ». Mieux
        #  vaut pas de curseur du tout qu'un curseur posé au hasard.
        "volume": -1, "muet": False, "micro": None}
    return {
        "avion": avion,
        #  La liste de ce qu'on n'a PAS pu lire. La page grise ces tuiles-là
        #  et écrit « Inconnu » : ni allumées, ni éteintes, et pas cliquables.
        "inconnu": inconnu,
        #  Wi-Fi et Bluetooth s'affichent éteints sous le mode avion, comme
        #  dans la démo — même si la radio répond encore « enabled » entre
        #  deux secondes de bascule.
        #  On lit les deux radios de front et on décide ICI, au lieu de
        #  demander d'abord le mode avion puis, selon la réponse, la radio :
        #  deux commandes lancées ensemble coûtent moins qu'une seule en file
        #  derrière une autre.
        "wifi": False if avion else (lu["r_wifi"] == "enabled"),
        #  None = « absent » pour la page (sa convention d'origine) ;
        #  « inconnu » dit le troisième cas.
        "bt": None if (avion or lu["bt_brut"] in (_INCONNU, None, "absent"))
              else lu["bt_brut"],
        "perf": perf,
        "perfLabel": PERF_LABEL[perf] if lu["perf"] is not _INCONNU else "Inconnu",
        #  Le thème non lu reste None : appliqueModeVolet() ne touche alors
        #  à rien, plutôt que de basculer la surface du volet au hasard.
        "theme": None if lu["theme"] is _INCONNU else lu["theme"],
        "crt": False if lu["crt"] is _INCONNU else lu["crt"],
        #  ═══ « volume: -1 » ET « micro: null » VEULENT DIRE INDISPONIBLE ═══
        #  Pas de pactl -> volume -1, et la page n'affiche PAS le bandeau du
        #  tout : une saveur sans serveur de son ne doit pas montrer un
        #  curseur qui ne fait rien. Pas de micro -> micro null, et le bouton
        #  micro n'apparaît pas — le même raisonnement que la tuile Bluetooth,
        #  qui sait déjà dire « Absent ».
        **son,
    }


def act_rapides_wifi(_arg=None):
    if not _outils.commande_existe("nmcli"):
        return {"ok": False, "erreur": "nmcli absent"}
    if _avion_radio_etat():
        return {"ok": False, "erreur": "mode avion actif"}
    allume = _wifi_radio_etat()
    try:
        r = subprocess.run(["nmcli", "radio", "wifi", "off" if allume else "on"],
                           capture_output=True, text=True, timeout=10)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0}


def act_rapides_bt(_arg=None):
    if not _outils.commande_existe("bluetoothctl"):
        return {"ok": False, "erreur": "bluetoothctl absent"}
    if _avion_radio_etat():
        return {"ok": False, "erreur": "mode avion actif"}
    allume = _bt_radio_etat()
    if allume is None:
        return {"ok": False, "erreur": "aucun contrôleur Bluetooth"}
    try:
        r = subprocess.run(["bluetoothctl", "power", "off" if allume else "on"],
                           capture_output=True, text=True, timeout=10)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0}


def act_rapides_avion(_arg=None):
    if not _outils.commande_existe("lexos-net"):
        return {"ok": False, "erreur": "lexos-net absent"}
    try:
        r = subprocess.run(["lexos-net", "avion", "toggle"],
                           capture_output=True, text=True, timeout=15)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0, "erreur": r.stderr.strip() if r.returncode else ""}


def act_rapides_perf(_arg=None):
    if not _outils.commande_existe("lexos-perf"):
        return {"ok": False, "erreur": "lexos-perf absent"}
    ordre = ["petit", "medium", "performant", "max"]
    suivant = ordre[(ordre.index(_perf_etat()) + 1) % len(ordre)]
    try:
        r = subprocess.run(["lexos-perf", suivant],
                           capture_output=True, text=True, timeout=15)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0}


def act_rapides_theme(_arg=None):
    if not _outils.commande_existe("lexos"):
        return {"ok": False, "erreur": "lexos absent"}
    suivant = "clair" if _mode_apparence() == "sombre" else "sombre"
    try:
        r = subprocess.run(["lexos", "theme", suivant],
                           capture_output=True, text=True, timeout=15)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0}


def act_rapides_crt(_arg=None):
    if not _outils.commande_existe("lexos"):
        return {"ok": False, "erreur": "lexos absent"}
    suivant = "off" if _crt_rapides_etat() else "on"
    try:
        r = subprocess.run(["lexos", "crt", suivant],
                           capture_output=True, text=True, timeout=15)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0}


def act_rapides_partage(_arg=None):
    """Ouvre Partager. detach : une fenêtre à part, le volet doit pouvoir se
    refermer sans l'emporter — même raison que act_meteo_ville."""
    if not _outils.commande_existe("lexos-share"):
        return {"ok": False, "erreur": "lexos-share absent"}
    subprocess.Popen(["lexos-share", "devices"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def act_rapides_clavier(_arg=None):
    """Comme openSettings('clavier') dans la démo : la tuile Clavier n'essaie
    pas de changer de disposition elle-même, elle ouvre Paramètres sur sa
    page — voir la note plus haut sur ce qui est volontairement absent."""
    if not _outils.commande_existe("lexos-settings"):
        return {"ok": False, "erreur": "lexos-settings absent"}
    subprocess.Popen(["lexos-settings", "clavier"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def act_rapides_volume(arg=None):
    """Le curseur du bandeau de son. La valeur est un niveau ABSOLU ; la
    borne 0-100 est dans son.py, au même endroit que pour les Paramètres et
    pour les touches du clavier."""
    return _son.regle_volume(arg)


def act_rapides_muet(_arg=None):
    """Un clic sur l'icône haut-parleur : coupe / rétablit. C'est le geste
    attendu sur cette icône — on ne l'invente pas ailleurs."""
    return _son.regle_muet("toggle")


def act_rapides_micro(_arg=None):
    """ALEX : « pour le micro juste mettre activé ou désactivé ». Deux états,
    pas de curseur. son.py refuse proprement quand il n'y a pas de micro,
    avec une phrase qu'on comprend."""
    return _son.regle_micro("toggle")


#  ═══ LE VOLET DOIT AVOIR DISPARU AVANT QUE LA PHOTO SE PRENNE ═══
#  Sinon il EST sur la photo — une capture plein écran où l'on voit le volet
#  en haut à droite, c'est le défaut exact qu'on corrige. Pour « une partie »,
#  c'est pire : le sélecteur s'ouvrirait sous un volet qui lui vole les clics.
#
#  L'enchaînement : le JS demande l'action, le Python lance lexos-capture AVEC
#  SON PROPRE DÉLAI (« --delai »), puis le JS ferme la fenêtre. La capture
#  attend pendant que picom joue l'extinction « vieille télé ». Le délai est
#  tenu par lexos-capture (xfce4-screenshooter -d) et pas par un sleep ici :
#  un sleep dans ce processus bloquerait le serveur du volet.
#
#  « start_new_session=True » est OBLIGATOIRE, et le commentaire du dépôt le
#  dit déjà pour act_rapides_partage : « le volet doit pouvoir se refermer
#  sans l'emporter ». Un enfant dans le même groupe de processus mourrait
#  avec le volet — donc pas de capture du tout.
CAPTURE_MODES = {"plein": "plein", "zone": "zone", "video": "video"}
#  1 seconde : l'extinction du volet dure 0,30 s (lexos-tv.conf : 0,14 +
#  0,10, l'opacité tombant à 0,24). Une seconde couvre ça largement sans
#  qu'on ait l'impression d'attendre. À REVOIR SUR LA MACHINE : ce chiffre-ci
#  est calculé sur les durées écrites dans la configuration de picom, pas
#  constaté sur le ThinkPad.
CAPTURE_DELAI = "1"


def act_rapides_photo(arg=None):
    mode = CAPTURE_MODES.get(arg or "")
    if mode is None:
        return {"ok": False, "erreur": "mode de capture inattendu"}
    if not _outils.commande_existe("lexos-capture"):
        return {"ok": False, "erreur": "lexos-capture absent"}
    subprocess.Popen(["lexos-capture", mode, "--delai", CAPTURE_DELAI],
                     start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


ACTIONS = {
    "notif-vide": act_notif_vide,
    "rapides-photo": act_rapides_photo,
    "rapides-volume": act_rapides_volume,
    "rapides-muet": act_rapides_muet,
    "rapides-micro": act_rapides_micro,
    "agenda-ajoute": act_agenda_ajoute,
    "agenda-enleve": act_agenda_enleve,
    "meteo-ville": act_meteo_ville,
    "rapides-wifi": act_rapides_wifi,
    "rapides-bt": act_rapides_bt,
    "rapides-avion": act_rapides_avion,
    "rapides-perf": act_rapides_perf,
    "rapides-theme": act_rapides_theme,
    "rapides-crt": act_rapides_crt,
    "rapides-partage": act_rapides_partage,
    "rapides-clavier": act_rapides_clavier,
}


def etat(quoi):
    commun = {"quoi": quoi, "aujourdhui": date.today().isoformat()}
    if quoi == "meteo":
        commun["meteo"] = _meteo()
    elif quoi == "rapides":
        commun["rapides"] = _rapides_etat()
    else:
        commun["notifications"] = _notifications()
        commun["agenda"] = _agenda_lit()
    return commun


# =============================================================================
#  Le petit serveur local — même forme que settings.py
# =============================================================================
#  ═══ LA CHARPENTE EST PARTIE DANS moteur/service.py ═══
#  Il en existait six exemplaires dans ce dépôt, dont quatre rigoureusement
#  identiques. Ce qui reste ici, c'est ce qui est PROPRE au volet : lequel
#  des trois volets est ouvert.
class Handler(_service.Service):
    quoi = "agenda"
    actions = ACTIONS
    apres_action = staticmethod(_apres_action)

    #  ⚠ PAS « etat_fn = staticmethod(etat) » : la fonction etat() du volet
    #  prend le NOM du volet, et ce nom est posé sur la classe au lancement
    #  (Handler.quoi = …). On passe donc par une méthode, qui sait le lire.
    def _etat(self):
        return etat(type(self).quoi)


def _hauteur_barre():
    """La hauteur de la barre du haut, pour poser le volet JUSTE en dessous.

    Lue dans xfconf plutôt que codée en dur : quelqu'un qui grossit sa barre
    verrait sinon le volet la chevaucher ou flotter loin d'elle. La marge de
    la feuille GTK (4 px de chaque côté) s'y ajoute."""
    defaut = 32 + 8
    if not _outils.commande_existe("xfconf-query"):
        return defaut
    try:
        r = subprocess.run(["xfconf-query", "-c", "xfce4-panel",
                            "-p", "/panels/panel-1/size"],
                           capture_output=True, text=True, timeout=5)
        v = r.stdout.strip()
        return int(v) + 8 if v.isdigit() else defaut
    except (subprocess.SubprocessError, OSError, ValueError):
        return defaut


def main():
    quoi = sys.argv[1] if len(sys.argv) > 1 else "agenda"
    if quoi not in VOLETS:
        print(f"Volet inconnu : {quoi}   (agenda · meteo · rapides)", file=sys.stderr)
        return 1
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        return 1

    Handler.quoi = quoi
    #  Les types web, le port libre et le fil du serveur : moteur/service.py.
    serveur, port = _service.servir(WEB_DIR, Handler, nom_fil="lexos-volet-http")

    from PySide6.QtCore import QUrl

    app = _fenetre.application("Volet LexOS")
    #  La vue transparente, sans cadre, hors d'Alt+Tab — et le TITRE, qui est
    #  un contrat avec picom : toute la raison est dans moteur/fenetre.py,
    #  avec le commentaire qui explique pourquoi une règle accrochée à une
    #  valeur par défaut de Qt se décroche un jour en silence.
    vue = _fenetre.vue_transparente("Volet LexOS")

    ecran = app.primaryScreen().availableGeometry()
    largeur = min(560, ecran.width() - 24)
    hauteur = min(680, int(ecran.height() * 0.78))
    haut = ecran.y() + _hauteur_barre()

    #  L'agenda descend de l'HEURE, qui est au centre de la barre ; la météo
    #  descend de sa tuile, à gauche ; les paramètres rapides, du bouton
    #  « ▲ », tout à droite (greffon 12, juste avant le bouton rouge).
    #  Chacun tombe donc sous le sien.
    if quoi == "meteo":
        gauche = ecran.x() + 14
    elif quoi == "rapides":
        largeur = min(340, ecran.width() - 24)
        #  460 -> 560 : le bandeau de son (curseur + micro) et la tuile
        #  appareil photo ajoutent une rangée et demie.
        #  LE « min » RESTE, et c'est lui qui compte : « hauteur » vaut déjà
        #  78 % de l'écran disponible. Sur le ThinkPad — un écran de
        #  portable, donc exactement la machine où ce garde-fou sert — le
        #  volet s'arrête à ce plafond au lieu de dépasser en bas.
        hauteur = min(560, hauteur)
        gauche = ecran.x() + ecran.width() - largeur - 14
    else:
        gauche = ecran.x() + (ecran.width() - largeur) // 2
    vue.setGeometry(gauche, haut, largeur, hauteur)

    vue.load(QUrl(f"http://127.0.0.1:{port}/index.html?mode={_mode_apparence()}#{quoi}"))
    vue.show()
    vue.raise_()
    vue.activateWindow()

    #  UN CLIC AILLEURS REFERME — c'est ce qui fait d'un volet un volet.
    #  Le retard et le pas vivent dans moteur/fenetre.py, avec la raison du
    #  retard : la fenêtre n'a pas encore le focus au moment où elle
    #  apparaît, et fermer sur « pas de focus » la tuerait avant qu'elle
    #  s'affiche.
    _fenetre.ferme_au_flou(app, vue)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
