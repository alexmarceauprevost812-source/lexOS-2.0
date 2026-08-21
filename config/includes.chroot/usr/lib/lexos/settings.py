#!/usr/bin/env python3
"""
LexOS — Paramètres : une seule fenêtre, une barre latérale, tous les réglages.

Même patron que Cartes LexOS (cartes.py) : une fenêtre Qt (PySide6) qui
affiche une page web servie par un petit serveur HTTP local. La page est
l'interface ; les actions réelles passent par une API locale (/api/…) que
le serveur exécute côté Python.

Pourquoi une API HTTP plutôt que QWebChannel : aucune dépendance de plus
(http.server est dans la bibliothèque standard, déjà utilisé par cartes.py),
et le pont est une LISTE BLANCHE — la page ne peut demander que les actions
définies ici, jamais une commande arbitraire.

Le serveur n'écoute que 127.0.0.1, sur un port libre tiré au lancement.
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
from pathlib import Path

APP_NAME = "Paramètres LexOS"
BASE_DIR = Path(os.environ.get("LEXOS_SETTINGS_DIR", "/usr/share/lexos/settings"))
WEB_DIR = BASE_DIR / "web"

#  Racines réglables — MÊME PRINCIPE QUE LEXOS_RACINE DANS gpu-garde. En
#  usage réel ces variables n'existent pas et tout pointe au vrai endroit.
#  Elles ne servent qu'au banc d'essai : il donne à ce fichier une fausse
#  machine (fausse batterie, faux /etc) et vérifie que chaque section lit
#  et affiche l'état SANS avoir besoin de deux ordinateurs différents.
PSU_DIR = Path(os.environ.get("LEXOS_PSU", "/sys/class/power_supply"))
BL_DIR = Path(os.environ.get("LEXOS_BL", "/sys/class/backlight"))
ETC_DIR = Path(os.environ.get("LEXOS_ETC", "/etc"))
DMI_DIR = Path(os.environ.get("LEXOS_DMI", "/sys/class/dmi/id"))


# =============================================================================
#  Actions — la liste blanche.
#  Chaque entrée : nom -> fonction(arg) -> dict sérialisable en JSON.
#  Les arguments venant de la page sont validés contre des ensembles fermés :
#  jamais interpolés dans un shell.
# =============================================================================

def _run(argv, *, detach=False):
    """Lance une commande. detach=True pour les fenêtres graphiques."""
    if shutil.which(argv[0]) is None:
        return {"ok": False, "erreur": f"Outil absent : {argv[0]}"}
    if detach:
        subprocess.Popen(argv, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True}
    r = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    return {"ok": r.returncode == 0,
            "sortie": (r.stdout or r.stderr).strip()[-4000:]}


def _terminal(titre, commande):
    """Ouvre un outil en ligne de commande dans un terminal, comme le faisait
    l'ancien routeur bash — même forme d'appel que les .desktop du hook 0400
    (xfce4-terminal --hold -e "commande; bash"). `commande` est une chaîne
    fixe définie ICI, jamais construite depuis la page ; elle part telle
    quelle comme UN SEUL élément d'argv (pas de ré-interprétation shell côté
    Python : subprocess.Popen reçoit une liste, jamais shell=True)."""
    return _run(["xfce4-terminal", f"--title={titre}", "--hold", "-e",
                 f"{commande}; bash"], detach=True)


def _xfce(module):
    """Ouvre le bon panneau de réglages XFCE.

    CE QUI ÉTAIT CASSÉ, ET POURQUOI PERSONNE NE LE VOYAIT.
    Cette fonction lançait « xfce4-settings-manager -s <module> ». L'option
    « -s » n'existe pas : xfce4-settings-manager refusait et mourait aussitôt.
    Comme l'appel est en detach=True (on ne lit pas le code de retour d'une
    fenêtre graphique, elle vit sa vie), l'échec était TOTALEMENT SILENCIEUX.
    Neuf sections des Paramètres avaient donc un bouton qui ne faisait rien,
    sans le moindre message : son, apparence, bureau, multi-tâches, souris,
    supports amovibles, tablette, accessibilité, clavier.

    XFCE ne s'ouvre pas par module : chaque panneau est un PROGRAMME à part
    (xfce4-appearance-settings, xfce4-mouse-settings…). On les nomme donc
    directement, et on garde des solutions de rechange : si le programme
    précis manque, on ouvre le gestionnaire de réglages complet plutôt que
    de ne rien faire. Un bouton doit toujours mener quelque part."""
    for argv in module if isinstance(module, list) else [[module]]:
        if shutil.which(argv[0]):
            return _run(argv, detach=True)
    #  Rien de précis n'est installé : le gestionnaire général vaut mieux que
    #  le silence — l'utilisateur trouvera son réglage à la main.
    if shutil.which("xfce4-settings-manager"):
        return _run(["xfce4-settings-manager"], detach=True)
    return {"ok": False, "erreur": "Aucun outil de réglages XFCE installé"}


PERFS = {"petit", "medium", "performant", "max"}
THEMES = {"sombre", "clair"}
ACCENTS = {"orange", "orange-rouge", "bleu", "rouge", "vert", "gris",
           "violet", "neon"}
#  LES POLICES D'ÉCRITURE. Trois familles génériques, puis DOUZE écritures à
#  la main embarquées par LexOS (licence OFL, dans
#  /usr/share/fonts/truetype/lexos, chacune avec son fichier de licence).
#
#  Pourquoi douze plutôt qu'une : Alex a repéré une écriture qui lui plaisait
#  sans savoir la nommer, et deviner à sa place gaspillait son temps comme le
#  mien. Il les a maintenant toutes sous les yeux, sur SA machine, à sa taille
#  et sur son fond — c'est là qu'on juge une police, pas sur une capture.
#
#  Cette liste est la SEULE source de vérité côté machine : le nom qui arrive
#  de la page est refusé s'il n'y est pas. Elle doit rester alignée avec
#  POLICES dans app.js (l'affichage) et cmd_police dans /usr/bin/lexos (le
#  terminal) — les trois nomment les mêmes clés.
POLICES = {
    "defaut", "classique", "mono",
    "manuscrite", "bulle", "carnet", "ronde", "crayon", "plume",
    "marqueur", "architecte", "fleur", "cursive", "tableau", "craie",
}
DOCKS = {"droite", "gauche", "bas", "haut"}
CADRAGES = {"remplir", "ajuster", "etirer", "centrer", "mosaique"}
FONDS = {
    "defaut":  "/usr/share/backgrounds/lexos/wallpaper.png",
    "secu":    "/usr/share/backgrounds/lexos/wallpaper-secu.png",
    "demon":   "/usr/share/backgrounds/lexos/wallpaper-demon.png",
    "keyart":  "/usr/share/backgrounds/lexos/wallpaper-keyart.png",
}
LANGUES = {
    "fr_CA.UTF-8", "fr_FR.UTF-8", "en_US.UTF-8", "en_CA.UTF-8", "en_GB.UTF-8",
    "es_ES.UTF-8", "es_MX.UTF-8", "de_DE.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8",
    "ru_RU.UTF-8", "zh_CN.UTF-8", "ja_JP.UTF-8", "ko_KR.UTF-8", "ar_SA.UTF-8",
}


def act_ouvrir(arg):
    """Ouvre l'outil complet d'une section — reprise exacte de l'ancien
    routeur bash (hook 0450)."""
    outils = {
        "wifi":       lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "reseau":     lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "bluetooth":  lambda: _terminal("Bluetooth — LexOS", "lexos bt scan"),
        "ecrans":     lambda: _run(["lexos-display", "gui"], detach=True),
        "son":        lambda: _xfce([["pavucontrol"], ["xfce4-mixer"]]),
        "energie":    lambda: _terminal("Énergie — LexOS", "lexos perf status; echo; lexos lumiere"),
        "usb":        lambda: _terminal("USB — LexOS", "lexos usb; echo; echo 'Formater un support : lexos format'"),
        "mac":        lambda: _terminal("Mac (Apple) — LexOS", "lexos mac"),
        "apparence":  lambda: _xfce([["xfce4-appearance-settings"]]),
        "bureau":     lambda: _xfce([["xfdesktop-settings"]]),
        "multitaches": lambda: _xfce([["xfwm4-workspace-settings"], ["xfwm4-settings"]]),
        "applications": lambda: _run(["exo-preferred-applications"], detach=True),
        "notifications": lambda: _run(["xfce4-notifyd-config"], detach=True),
        "recherche":  lambda: _run(["xfce4-appfinder", "--collapsed"], detach=True),
        "partage":    lambda: _run(["lexos-share", "devices"], detach=True),
        "souris":     lambda: _xfce([["xfce4-mouse-settings"]]),
        "couleurs":   lambda: _run(["gcm-viewer"], detach=True),
        "imprimantes": lambda: _run(["system-config-printer"], detach=True),
        "amovibles":  lambda: _xfce([["thunar-volman-settings"]]),
        "tablette":   lambda: _xfce([["xfce4-wacom-settings"], ["wacom-settings"]]),
        "confidentialite": lambda: _terminal("Confidentialité et sécurité — LexOS",
                                             "lexos net status; echo; lexos secure"),
        "maj":        lambda: _terminal("Mises à jour — LexOS", "lexos doctor"),
        "accessibilite": lambda: _xfce([["xfce4-accessibility-settings"]]),
        "utilisateurs": lambda: _terminal("Utilisateurs — LexOS",
                                          "printf '%s\\n' 'Comptes locaux de LexOS :' '' "
                                          "'  lex     — Principal, administrateur' "
                                          "'  invite  — Invité, session limitée sans mot de passe' ''"),
        "clavier":    lambda: _xfce([["xfce4-keyboard-settings"]]),
        "datetime":   lambda: _terminal("Date et heure — LexOS", "timedatectl"),
        "defaut":     lambda: _run(["exo-preferred-applications"], detach=True),
        "distant":    lambda: _terminal("Bureau à distance — LexOS", "lexos distant"),
        "comptes":    lambda: _terminal("Comptes en ligne — LexOS", "lexos comptes"),
        "bienetre":   lambda: _terminal("Bien-être numérique — LexOS", "lexos bienetre"),
        "apropos":    lambda: _run(["lexos-welcome", "--about"], detach=True),
    }
    fn = outils.get(arg)
    if fn is None:
        return {"ok": False, "erreur": f"Section inconnue : {arg}"}
    return fn()


def act_avion(arg):
    if arg not in {"toggle", "on", "off"}:
        return {"ok": False, "erreur": "avion : toggle|on|off"}
    return _run(["lexos-net", "avion", arg])


def act_perf(arg):
    if arg not in PERFS:
        return {"ok": False, "erreur": "profil inconnu"}
    return _run(["lexos-perf", arg])


def act_lumiere(arg):
    try:
        n = int(arg)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "luminosité : un nombre 5-100"}
    n = max(5, min(100, n))
    return _run(["lexos-brightness", str(n)])


def act_theme(arg):
    if arg not in THEMES:
        return {"ok": False, "erreur": "thème : sombre|clair"}
    return _run(["lexos", "theme", arg])


def act_accent(arg):
    if arg not in ACCENTS:
        return {"ok": False, "erreur": "accent inconnu"}
    return _run(["lexos", "accent", arg])


def act_police(arg):
    if arg not in POLICES:
        return {"ok": False, "erreur": "police inconnue"}
    return _run(["lexos", "police", arg])


def act_dock(arg):
    if arg not in DOCKS:
        return {"ok": False, "erreur": "position : droite|gauche|bas|haut"}
    return _run(["lexos", "dock", arg])


def act_fond(arg):
    chemin = FONDS.get(arg)
    if chemin is None:
        return {"ok": False, "erreur": "fond inconnu"}
    if not Path(chemin).exists():
        return {"ok": False, "erreur": f"Image absente : {chemin}"}
    return _run(["lexos", "wallpaper", chemin, "remplir"])


#  Les scènes animées sont LUES SUR LE DISQUE, jamais recopiées dans une liste.
#  L'aide du terminal annonçait « ciel » alors que le fichier s'appelle
#  « etoiles » : la commande copiée de la documentation échouait mot pour mot.
#  Une liste écrite à la main finit toujours par mentir ; celle-ci ne peut pas.
FONDS_ANIMES_DIRS = ("/usr/share/lexos/fonds", "~/.config/lexos/fonds")


def _animes_disponibles():
    noms = set()
    for d in FONDS_ANIMES_DIRS:
        try:
            for f in Path(d).expanduser().glob("*.json"):
                # « modele » est le gabarit à copier, pas une scène à poser.
                if f.stem != "modele":
                    noms.add(f.stem)
        except OSError:
            continue
    return noms


def act_fond_anime(arg):
    """Pose un fond animé, ou le retire. Le nom vient de la page : il est donc
    validé contre ce qui existe RÉELLEMENT sur le disque avant tout appel."""
    if arg in ("off", "stop", "arret"):
        return _run(["lexos", "wallpaper", "anime", "off"])
    dispo = _animes_disponibles()
    if arg not in dispo:
        connues = " · ".join(sorted(dispo)) or "aucune"
        return {"ok": False, "erreur": f"scène inconnue. Installées : {connues}"}
    return _run(["lexos", "wallpaper", "anime", arg])


def act_fond_capture(arg):
    """Capture l'écran et en fait le fond d'écran — les deux outils existaient
    déjà mais rien ne les reliait, il fallait retenir le chemin du fichier."""
    mode = arg if arg in ("plein", "zone") else "plein"
    if shutil.which("lexos-capture") is None:
        return {"ok": False, "erreur": "lexos-capture absent"}
    return _run(["lexos-capture", "fond", mode], detach=True)


def act_fond_perso(arg):
    """Ouvre un sélecteur de fichier (zenity) puis applique l'image choisie.
    Le chemin vient du sélecteur local, pas de la page."""
    if shutil.which("zenity") is None:
        return {"ok": False, "erreur": "zenity absent"}
    r = subprocess.run(
        ["zenity", "--file-selection", "--title=Choisir un fond d'écran",
         "--file-filter=Images | *.jpg *.jpeg *.png *.webp *.avif *.bmp *.tif *.tiff *.gif"],
        capture_output=True, text=True, timeout=600)
    chemin = r.stdout.strip()
    if r.returncode != 0 or not chemin:
        return {"ok": False, "erreur": "Aucun fichier choisi"}
    cadrage = arg if arg in CADRAGES else "remplir"
    return _run(["lexos", "wallpaper", chemin, cadrage])


def act_langue(arg):
    if arg not in LANGUES:
        return {"ok": False, "erreur": "langue inconnue"}
    return _run(["lexos", "lang", arg])


def act_capture(arg):
    modes = {"photo": ["lexos-capture"], "zone": ["lexos-capture", "zone"],
             "fenetre": ["lexos-capture", "fenetre"]}
    argv = modes.get(arg)
    if argv is None:
        return {"ok": False, "erreur": "capture : photo|zone|fenetre"}
    return _run(argv, detach=True)


# =============================================================================
#  Les actions qui CHANGENT quelque chose pour de vrai.
#
#  Règle de la maison, sans exception : l'argument venu de la page est
#  comparé à un ensemble FERMÉ avant d'être utilisé. Jamais de chaîne
#  interpolée dans une commande, jamais de shell=True. La page ne peut donc
#  demander que ce qui est prévu ici — pas une commande de son choix.
# =============================================================================

def act_wifi(arg):
    """Allume ou éteint la radio Wi-Fi."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _wifi_etat()["radio"] == "enabled" else "on"
    return _run(["nmcli", "radio", "wifi", arg])


def act_son_muet(arg):
    """Coupe ou rétablit le son."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    valeur = {"on": "1", "off": "0", "toggle": "toggle"}[arg]
    return _run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", valeur])


def act_son_volume(arg):
    """Règle le volume. Le curseur envoie un nombre : on le BORNE à 0-100
    avant de le transmettre. Sans cette borne, un « 400 » venu de la page
    monterait le gain bien au-delà du niveau du matériel — de la distorsion,
    et de quoi abîmer un haut-parleur."""
    if arg in ("moins", "plus"):
        return _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@",
                     "-5%" if arg == "moins" else "+5%"])
    try:
        n = int(arg)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "valeur inattendue"}
    n = max(0, min(100, n))
    return _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{n}%"])


def act_notif(arg):
    """Ne pas déranger."""
    if arg != "silence":
        return {"ok": False, "erreur": "valeur inattendue"}
    actuel = _notif_etat()["silence"]
    return _run(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb",
                 "-n", "-t", "bool", "-s", "false" if actuel else "true"])


def act_amovibles(arg):
    """Ce que LexOS fait quand on branche quelque chose. Le nom du réglage
    est cherché dans la table VOLMAN : la page ne peut pas désigner une clé
    xfconf de son choix."""
    if arg not in VOLMAN:
        return {"ok": False, "erreur": "valeur inattendue"}
    actuel = _amovibles_etat()[arg]
    return _run(["xfconf-query", "-c", "thunar-volman", "-p", VOLMAN[arg],
                 "-n", "-t", "bool", "-s", "false" if actuel else "true"])


def act_access(arg):
    """Deux réglages d'accessibilité qui se règlent sans redémarrer :
    le curseur large et le contraste élevé."""
    if arg == "curseur":
        grand = _access_etat()["curseurLarge"]
        return _run(["xfconf-query", "-c", "xsettings", "-p", "/Gtk/CursorThemeSize",
                     "-n", "-t", "int", "-s", "24" if grand else "48"])
    if arg == "contraste":
        fort = _access_etat()["contraste"]
        #  On revient au thème de LexOS plutôt qu'à un thème GTK quelconque :
        #  c'est celui que le reste du bureau attend.
        return _run(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName",
                     "-n", "-t", "string",
                     "-s", "Adwaita-dark" if fort else "HighContrast"])
    if arg in ("orca", "onboard"):
        outil = {"orca": ["orca"], "onboard": ["onboard"]}[arg]
        return _run(outil, detach=True)
    return {"ok": False, "erreur": "valeur inattendue"}


def act_securite(arg):
    """Les outils d'autodéfense s'ouvrent dans un terminal : ils demandent
    tous les droits d'administration et posent des questions. Les lancer en
    silence derrière un interrupteur cacherait justement ce qu'il faut lire."""
    outils = {
        "pare-feu":  ("Pare-feu — LexOS", "lexos secure firewall"),
        "antivirus": ("Antivirus — LexOS", "lexos secure scan"),
        "rootkit":   ("Anti-rootkit — LexOS", "sudo rkhunter --check --sk"),
        "etat":      ("Sécurité — LexOS", "lexos secure"),
    }
    if arg not in outils:
        return {"ok": False, "erreur": "valeur inattendue"}
    return _terminal(*outils[arg])


def act_maj(arg):
    """Mises à jour. Tout passe par un terminal : une mise à jour pose des
    questions, prend du temps, et il faut pouvoir lire ce qui se passe."""
    outils = {
        "verifier":  ("Mises à jour — LexOS", "lexos doctor"),
        "tout":      ("Mise à jour — LexOS", "lexos upgrade"),
        "firmware":  ("Micrologiciel — LexOS", "lexos firmware"),
    }
    if arg not in outils:
        return {"ok": False, "erreur": "valeur inattendue"}
    return _terminal(*outils[arg])


def act_usb(arg):
    """Les trois gestes de la démo, en vrai. « ejecter:/dev/sdb » démonte
    proprement ; le chemin est VÉRIFIÉ contre la liste des appareils
    réellement amovibles, jamais pris au mot. Sans ce contrôle, la page
    pourrait demander d'éjecter le disque système."""
    quoi, _, cible = str(arg).partition(":")
    if quoi == "vide-memoire":
        return _terminal("Vide mémoire — LexOS", "lexos vide-memoire")
    if quoi == "terminal":
        return _terminal("Terminal de l'appareil — LexOS", "lexos usb terminal")
    if quoi == "formater":
        return _terminal("Formater un support — LexOS", "lexos format")
    if quoi == "ejecter":
        connus = {a["dev"] for a in _usb_etat()}
        if cible not in connus:
            return {"ok": False, "erreur": "Appareil inconnu ou non amovible"}
        return _run(["udisksctl", "power-off", "-b", cible])
    return {"ok": False, "erreur": "valeur inattendue"}


def act_crt(arg):
    """Effets d'ouverture façon téléviseur cathodique."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _crt_etat() else "on"
    return _run(["lexos", "crt", arg])


def act_barre_cachee(arg):
    """Cacher ou montrer la barre du haut."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _barre_cachee() else "on"
    return _run(["xfconf-query", "-c", "xfce4-panel",
                 "-p", "/panels/panel-1/autohide-behavior",
                 "-n", "-t", "int", "-s", "1" if arg == "on" else "0"])


def act_bureaux(arg):
    """Ajouter ou enlever un bureau virtuel. Bornes : 1 au moins, 5 au plus —
    les mêmes que la démo, et que les raccourcis Super+1 … Super+5."""
    if arg not in ("plus", "moins"):
        return {"ok": False, "erreur": "valeur inattendue"}
    nb = _bureaux_etat()["nb"]
    nouveau = nb + 1 if arg == "plus" else nb - 1
    if nouveau < 1:
        return {"ok": False, "erreur": "Il faut garder au moins un bureau"}
    if nouveau > 5:
        return {"ok": False, "erreur": "5 bureaux au maximum"}
    return _run(["xfconf-query", "-c", "xfwm4", "-p", "/general/workspace_count",
                 "-n", "-t", "int", "-s", str(nouveau)])


def act_horloge(arg):
    """Composer le format de l'horloge de la barre du haut.

    POURQUOI ON RECOMPOSE LA CHAÎNE ENTIÈRE plutôt que de la rafistoler :
    une chaîne de format est un tout. Chercher « %S » pour l'enlever marche
    une fois, puis échoue le jour où quelqu'un a mis « %H:%M:%S » à la main
    avec un autre séparateur, et on se retrouve avec « 14 h 32 : ». On repart
    donc des trois choix — 12/24 h, secondes, jour — et on écrit la chaîne
    complète. C'est prévisible, et ça se relit dans l'état."""
    if arg not in ("12h", "24h", "secondes", "jour"):
        return {"ok": False, "erreur": "valeur inattendue"}

    etat_h = _heure_etat()
    h12 = etat_h["h12"]
    secondes = etat_h["secondes"]
    jour = etat_h["jour"]
    if arg == "12h":
        h12 = True
    elif arg == "24h":
        h12 = False
    elif arg == "secondes":
        secondes = not secondes
    else:
        jour = not jour

    #  « lexOS » en tête : c'est la signature de la barre, elle reste.
    morceaux = ["lexOS "]
    morceaux.append(" %a %d %b " if jour else " %d %b ")
    if h12:
        morceaux.append(" %I h %M" + (" %S" if secondes else "") + " %p")
    else:
        morceaux.append(" %H h %M" + (" %S" if secondes else ""))
    fmt = "".join(morceaux)

    #  Les deux propriétés portent le même format : selon les versions, le
    #  greffon lit l'une ou l'autre. En écrire une seule donne un réglage qui
    #  « ne prend pas » sur la moitié des machines.
    for propriete in ("digital-format", "digital-time-format"):
        r = _run(["xfconf-query", "-c", "xfce4-panel",
                  "-p", f"/plugins/plugin-3/{propriete}",
                  "-n", "-t", "string", "-s", fmt])
        if not r.get("ok"):
            return r
    return {"ok": True, "format": fmt}


def act_fuseau_auto(arg):
    """Le fuseau horaire d'après la position.

    CE QU'ON NE FAIT PAS : deviner la position par l'adresse IP dans le dos
    de l'utilisateur. LexOS a déjà une position — celle que « lexos cartes »
    ou « lexos meteo » ont enregistrée parce qu'on la lui a DONNÉE. C'est
    celle-là qu'on utilise, et s'il n'y en a pas, on le dit au lieu
    d'interroger un service."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    return _run(["lexos-datetime", "fuseau-auto", arg])


def act_autocollant(arg):
    """Poser un personnage sur le fond d'écran, ou tout enlever. Les noms
    forment un ensemble fermé — le shell ne voit jamais la valeur brute."""
    if arg not in ("rock", "salut", "prevost", "enlever"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "enlever":
        return _run(["lexos-fond-ecran", "autocollant", "enlever"])
    return _run(["lexos-fond-ecran", "autocollant", "poser", arg])


def act_coin(arg):
    """Le coin haut-gauche ouvre la vue d'ensemble, comme sous Ubuntu."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _apercu_etat()["coin"] else "on"
    return _run(["lexos-apercu", "coin", arg])


def act_super_apercu(arg):
    """La touche Super seule ouvre la vue d'ensemble. Super+1…5 continuent
    d'aller aux bureaux : c'est xcape qui fait la différence."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _apercu_etat()["super"] else "on"
    return _run(["lexos-apercu", "super", arg])


def act_apercu(arg):
    """Ouvre la vue d'ensemble tout de suite — le bouton « Voir mes bureaux ».
    detach : c'est une fenêtre, elle vit sa vie."""
    return _run(["lexos-apercu", "ouvrir"], detach=True)


def act_bureau_va(arg):
    """Aller à un bureau donné. Le numéro est borné, jamais interpolé."""
    if not str(arg).isdigit():
        return {"ok": False, "erreur": "valeur inattendue"}
    n = max(0, min(4, int(arg)))
    return _run(["wmctrl", "-s", str(n)])


def act_bluetooth(arg):
    """Allume ou éteint la radio Bluetooth."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        actuel = _bluetooth_etat()
        if actuel is None:
            return {"ok": False, "erreur": "Aucun contrôleur Bluetooth"}
        arg = "off" if actuel else "on"
    return _run(["bluetoothctl", "power", arg])


def act_energie_dim_batterie(arg):
    """Abaisser ou non la luminosité quand le secteur est débranché."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    actif = _energie_etat()["dimBat"]
    if arg == "toggle":
        arg = "off" if actif else "on"
    niveau = "40" if arg == "on" else "100"
    return _run(["xfconf-query", "-c", "xfce4-power-manager",
                 "-p", "/xfce4-power-manager/brightness-on-battery",
                 "-n", "-t", "int", "-s", niveau])


def act_energie_delai(arg):
    """« ecranOff:10 » ou « veille:30 » — en minutes, 0 pour jamais.
    Le nom du réglage est cherché dans une table FERMÉE : la page ne peut pas
    désigner une clé xfconf de son choix."""
    cles = {"ecranOff": ("blank-on-ac", "blank-on-battery"),
            "veille": ("inactivity-on-ac", "inactivity-on-battery")}
    quoi, _, valeur = str(arg).partition(":")
    if quoi not in cles or not valeur.isdigit():
        return {"ok": False, "erreur": "valeur inattendue"}
    minutes = max(0, min(600, int(valeur)))
    dernier = {"ok": False, "erreur": "xfconf-query absent"}
    for prop in cles[quoi]:
        dernier = _run(["xfconf-query", "-c", "xfce4-power-manager",
                        "-p", f"/xfce4-power-manager/{prop}",
                        "-n", "-t", "int", "-s", str(minutes)])
    return dernier


def act_souris(arg):
    """Bascule un réglage du pavé tactile (tape-pour-cliquer, défilement
    naturel). Le chemin xfconf est reconstruit ICI depuis l'état lu, jamais
    reçu de la page — sinon la page pourrait écrire n'importe quelle clé."""
    if arg not in ("tape", "inverse"):
        return {"ok": False, "erreur": "valeur inattendue"}
    s = _souris_etat()
    if not s["pave"]:
        return {"ok": False, "erreur": "Aucun pavé tactile détecté"}
    cle = {"tape": "libinput_Tapping_Enabled",
           "inverse": "libinput_Natural_Scrolling_Enabled"}[arg]
    nouveau = "false" if s[arg] else "true"
    return _run(["xfconf-query", "-c", "pointers",
                 "-p", f"{s['pave']}/Properties/{cle}",
                 "-n", "-t", "bool", "-s", nouveau])


def act_heure_auto(arg):
    """Synchronisation automatique de l'heure (NTP)."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _heure_etat()["auto"] else "on"
    #  pkexec : changer l'heure demande les droits d'administration, et on
    #  veut la fenêtre de mot de passe habituelle plutôt qu'un échec muet.
    outil = "pkexec" if shutil.which("pkexec") else "timedatectl"
    argv = ([outil, "timedatectl", "set-ntp", arg] if outil == "pkexec"
            else ["timedatectl", "set-ntp", arg])
    return _run(argv)


ACTIONS = {
    "ouvrir": act_ouvrir,
    "wifi-radio": act_wifi,
    "son-muet": act_son_muet,
    "son-volume": act_son_volume,
    "souris": act_souris,
    "bluetooth-radio": act_bluetooth,
    "crt": act_crt,
    "usb": act_usb,
    "amovibles": act_amovibles,
    "notif": act_notif,
    "access": act_access,
    "securite": act_securite,
    "maj": act_maj,
    "barre-cachee": act_barre_cachee,
    "bureaux": act_bureaux,
    "horloge": act_horloge,
    "fuseau-auto": act_fuseau_auto,
    "autocollant": act_autocollant,
    "coin": act_coin,
    "super_apercu": act_super_apercu,
    "apercu": act_apercu,
    "bureau-va": act_bureau_va,
    "energie-dim-batterie": act_energie_dim_batterie,
    "energie-delai": act_energie_delai,
    "heure-auto": act_heure_auto,
    "avion": act_avion,
    "perf": act_perf,
    "lumiere": act_lumiere,
    "theme": act_theme,
    "accent": act_accent,
    "police": act_police,
    "dock": act_dock,
    "fond": act_fond,
    "fond-perso": act_fond_perso,
    "fond-anime": act_fond_anime,
    "fond-capture": act_fond_capture,
    "langue": act_langue,
    "capture": act_capture,
}


# =============================================================================
#  État — ce que la page affiche au chargement.
# =============================================================================

def _sortie(argv):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


# =============================================================================
#  Lire l'état RÉEL de la machine.
#
#  Pourquoi ces fonctions existent : les sections des Paramètres n'étaient que
#  des boutons « ouvrir l'outil complet ». On voyait la liste des réglages,
#  jamais leur VALEUR — impossible de savoir si le Wi-Fi était allumé sans
#  ouvrir un terminal. Un panneau de réglages qui ne dit pas l'état des choses
#  n'est pas un panneau de réglages, c'est un menu de raccourcis.
#
#  Chacune de ces fonctions ne fait que LIRE, ne lève jamais, et renvoie une
#  valeur neutre quand l'outil manque : une machine sans batterie ou sans
#  pactl ne doit pas casser la page, juste afficher moins de choses.
# =============================================================================

def _wifi_etat():
    """Radio Wi-Fi allumée ? réseau connecté ? force du signal ?"""
    if not shutil.which("nmcli"):
        return {"radio": "absent", "reseau": "", "signal": 0}
    #  « -t » (terse) donne des mots-clés fixes, jamais traduits — la sortie
    #  normale de nmcli suit la langue du système (fr_CA sur LexOS).
    radio = _sortie(["nmcli", "-t", "radio", "wifi"]) or "absent"
    reseau, signal = "", 0
    for ligne in _sortie(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL",
                          "device", "wifi"]).splitlines():
        champs = ligne.split(":")
        if len(champs) >= 3 and champs[0] == "yes":
            reseau = champs[1]
            signal = int(champs[2]) if champs[2].isdigit() else 0
            break
    return {"radio": radio, "reseau": reseau, "signal": signal}


def _son_etat():
    """Volume en pour-cent et sourdine, via PipeWire/PulseAudio."""
    if not shutil.which("pactl"):
        return {"volume": -1, "muet": False}
    volume = -1
    sortie = _sortie(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
    for morceau in sortie.replace("/", " ").split():
        if morceau.endswith("%") and morceau[:-1].isdigit():
            volume = int(morceau[:-1])
            break
    muet = _sortie(["pactl", "get-sink-mute", "@DEFAULT_SINK@"]).endswith("yes")
    return {"volume": volume, "muet": muet, "casque": _casque_branche()}


def _batterie_etat():
    """Charge et source d'alimentation. Une tour n'a pas de batterie : on
    renvoie alors -1, et la page n'affiche simplement pas la ligne."""
    niveau, secteur = -1, True
    base = PSU_DIR
    try:
        for d in sorted(base.glob("BAT*")):
            try:
                niveau = int((d / "capacity").read_text().strip())
                break
            except (OSError, ValueError):
                continue
        for d in sorted(base.glob("A*")):          # ADP*, AC*
            try:
                secteur = (d / "online").read_text().strip() == "1"
                break
            except OSError:
                continue
    except OSError:
        pass
    return {"niveau": niveau, "secteur": secteur}


def _ecrans_etat():
    """Les sorties vidéo BRANCHÉES, avec leur définition courante."""
    ecrans = []
    if not shutil.which("xrandr"):
        return ecrans
    for ligne in _sortie(["xrandr", "--query"]).splitlines():
        if " connected" not in ligne:
            continue
        mots = ligne.split()
        nom = mots[0]
        definition = ""
        for m in mots:
            #  « 1920x1080+0+0 » — la géométrie active, s'il y en a une.
            if "x" in m and "+" in m and m[0].isdigit():
                definition = m.split("+")[0]
                break
        ecrans.append({"nom": nom, "definition": definition,
                       "principal": "primary" in mots})
    return ecrans


def _souris_etat():
    """Réglages du pavé tactile, lus dans xfconf (là où XFCE les garde)."""
    def prop(chemin, defaut=False):
        if not shutil.which("xfconf-query"):
            return defaut
        v = _sortie(["xfconf-query", "-c", "pointers", "-p", chemin])
        return v == "true" if v in ("true", "false") else defaut

    #  Le nom du périphérique fait partie du chemin xfconf et varie d'une
    #  machine à l'autre : on cherche le premier qui ressemble à un pavé.
    pave = ""
    if shutil.which("xfconf-query"):
        for p in _sortie(["xfconf-query", "-c", "pointers", "-l"]).splitlines():
            bas = p.lower()
            if "touchpad" in bas or "synaptics" in bas or "trackpad" in bas:
                pave = "/" + p.strip("/").split("/")[0]
                break
    if not pave:
        return {"pave": "", "tape": False, "inverse": False}
    return {"pave": pave,
            "tape": prop(f"{pave}/Properties/libinput_Tapping_Enabled"),
            "inverse": prop(f"{pave}/Properties/libinput_Natural_Scrolling_Enabled")}


def _bluetooth_etat():
    """La radio Bluetooth est-elle allumée ? « Powered: yes » dans la sortie
    de bluetoothctl. Renvoie None quand la machine n'a pas de Bluetooth du
    tout — la page n'affiche alors pas l'interrupteur plutôt que d'en montrer
    un qui ne servirait à rien."""
    if not shutil.which("bluetoothctl"):
        return None
    sortie = _sortie(["bluetoothctl", "show"])
    if not sortie:
        return None
    for ligne in sortie.splitlines():
        if ligne.strip().startswith("Powered:"):
            return ligne.split(":", 1)[1].strip() == "yes"
    return None


def _casque_branche():
    """Un casque est-il branché ? On lit le port ACTIF de la sortie audio.
    Sert à l'afficher, pas à le changer : on ne débranche pas un casque en
    logiciel, et un faux interrupteur serait un mensonge."""
    if not shutil.which("pactl"):
        return False
    sortie = _sortie(["pactl", "list", "sinks"]).lower()
    for ligne in sortie.splitlines():
        if ligne.strip().startswith("active port:"):
            return "headphone" in ligne or "headset" in ligne
    return False


def _lumiere_etat():
    """Luminosité du rétroéclairage, en pour-cent. -1 quand la machine n'a pas
    de rétroéclairage pilotable (une tour avec un écran externe, par exemple)."""
    base = BL_DIR
    try:
        for d in sorted(base.iterdir()):
            try:
                actuel = int((d / "brightness").read_text().strip())
                maxi = int((d / "max_brightness").read_text().strip())
                if maxi > 0:
                    return round(actuel * 100 / maxi)
            except (OSError, ValueError):
                continue
    except OSError:
        pass
    return -1


def _xfconf_lire(canal, propriete):
    if not shutil.which("xfconf-query"):
        return ""
    return _sortie(["xfconf-query", "-c", canal, "-p", propriete])


def _energie_etat():
    """Les délais d'extinction et de veille, là où XFCE les garde. Les valeurs
    sont en MINUTES ; 0 veut dire jamais, des deux côtés."""
    c = "xfce4-power-manager"
    def entier(prop, defaut):
        v = _xfconf_lire(c, f"/xfce4-power-manager/{prop}")
        return v if v.isdigit() else str(defaut)

    dim = _xfconf_lire(c, "/xfce4-power-manager/brightness-on-battery")
    return {
        #  « brightness-on-battery » vaut le niveau visé sur batterie ; s'il
        #  est posé et inférieur à 100, c'est que l'abaissement est actif.
        "dimBat": bool(dim.isdigit() and int(dim) < 100),
        "ecranOff": entier("blank-on-ac", 10),
        "veille": entier("inactivity-on-ac", 30),
    }


def _dock_etat():
    """Position du dock, telle que LexOS l'a notée."""
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        v = (conf / "dock").read_text().strip()
        return v if v in DOCKS else "droite"
    except OSError:
        return "droite"


def _crt_etat():
    """Les effets d'ouverture façon téléviseur cathodique sont-ils demandés ?
    « demandés » et pas « actifs » : ils exigent Compiz, qui ne démarre que
    s'il y a une accélération 3D. lexos-wm replie sur xfwm4 sinon."""
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        return (conf / "crt").read_text().strip() != "off"
    except OSError:
        return True


def _libre_etat():
    """Ce qui, dans CETTE machine, n'est pas du logiciel libre.

    La démo affiche la liste des trois exceptions (micrologiciels, Steam,
    pilote Broadcom) comme un texte fixe — elle ne peut pas faire mieux, elle
    n'a pas de machine sous elle. L'ISO, elle, peut REGARDER : « Steam est
    installé » et « Steam pourrait être installé » ne sont pas la même
    phrase, et c'est justement la précision qui donne du poids au reste.

    On ne regarde que la présence, jamais l'usage. Rien n'est envoyé nulle
    part : dpkg et /sys répondent depuis le disque."""
    def paquet(nom):
        r = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Status}", nom],
                           capture_output=True, text=True)
        return r.returncode == 0 and r.stdout.strip() == "installed"

    #  Les micrologiciels : on compte les paquets « firmware-* » plutôt que
    #  d'en nommer un, la liste dépendant entièrement du matériel.
    firmwares = []
    try:
        r = subprocess.run(["dpkg-query", "-W", "-f=${binary:Package}\n",
                            "firmware-*"], capture_output=True, text=True)
        firmwares = [l for l in r.stdout.split() if l]
    except OSError:
        pass

    return {
        "firmwares": len(firmwares),
        "steam": paquet("steam-installer") or paquet("steam"),
        "broadcom": (paquet("broadcom-sta-dkms")
                     or paquet("firmware-brcm80211")),
    }


def _apercu_etat():
    """La vue d'ensemble des bureaux : par quoi elle s'ouvre, et par quoi on
    la déclenche.

    « moteur » n'est pas décoratif : sans xfdashboard on retombe sur la liste
    des fenêtres de xfdesktop, qui montre les mêmes bureaux mais pas en
    vignettes. La page le dit plutôt que de laisser croire à la vue de la
    démo. Et « super » ne peut s'allumer que si xcape est là — lui seul sait
    distinguer une touche Super relâchée seule d'un Super+1."""
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def drapeau(nom):
        try:
            return (conf / nom).read_text().strip() == "on"
        except OSError:
            return False

    if shutil.which("xfdashboard"):
        moteur = "xfdashboard"
    elif shutil.which("xfdesktop"):
        moteur = "xfdesktop"
    else:
        moteur = ""
    return {
        "moteur": moteur,
        "coin": drapeau("coin-actif"),
        "super": drapeau("super-apercu"),
        "xcape": bool(shutil.which("xcape")),
    }


def _barre_cachee():
    """La barre du haut se cache-t-elle toute seule ? XFCE range ça dans
    autohide-behavior : 0 = toujours visible, 1 = intelligent, 2 = toujours
    cachée. On considère « cachée » dès que ce n'est plus 0."""
    v = _xfconf_lire("xfce4-panel", "/panels/panel-1/autohide-behavior")
    return v.isdigit() and int(v) != 0


def _bureaux_etat():
    """Combien de bureaux virtuels, où l'on est, et combien de fenêtres sur
    chacun. wmctrl répond aux trois — c'est lui qui parle au gestionnaire de
    fenêtres, pas une supposition."""
    nb = _xfconf_lire("xfwm4", "/general/workspace_count")
    nb = int(nb) if nb.isdigit() else 0
    courant, fenetres = 0, []
    if shutil.which("wmctrl"):
        for ligne in _sortie(["wmctrl", "-d"]).splitlines():
            champs = ligne.split()
            if len(champs) >= 2 and champs[1] == "*":
                courant = int(champs[0]) if champs[0].isdigit() else 0
        if not nb:
            nb = len(_sortie(["wmctrl", "-d"]).splitlines())
        #  Une fenêtre par ligne, son bureau en deuxième colonne.
        compte = {}
        for ligne in _sortie(["wmctrl", "-l"]).splitlines():
            champs = ligne.split()
            if len(champs) >= 2 and champs[1].lstrip("-").isdigit():
                d = int(champs[1])
                if d >= 0:
                    compte[d] = compte.get(d, 0) + 1
        fenetres = [compte.get(i, 0) for i in range(max(nb, 1))]
    return {"nb": max(nb, 1), "courant": courant, "fenetres": fenetres}


def _usb_etat():
    """Les supports AMOVIBLES branchés — clés, disques externes, cartes.
    lsblk répond en JSON, ce qui évite d'avoir à découper du texte aligné qui
    change de forme d'une version à l'autre.

    On ne liste QUE l'amovible (RM=1) ou l'USB (TRAN=usb) : le disque système
    n'a rien à faire dans une liste où le bouton d'à côté s'appelle
    « Formater ». C'est le genre de confusion qui coûte des données."""
    if not shutil.which("lsblk"):
        return []
    brut = _sortie(["lsblk", "-J", "-b", "-o",
                    "NAME,SIZE,LABEL,RM,TYPE,TRAN,MOUNTPOINT,MODEL"])
    try:
        arbre = json.loads(brut).get("blockdevices", [])
    except (ValueError, AttributeError):
        return []

    def taille(octets):
        try:
            o = int(octets)
        except (TypeError, ValueError):
            return ""
        for unite, seuil in (("To", 1e12), ("Go", 1e9), ("Mo", 1e6)):
            if o >= seuil:
                n = o / seuil
                return f"{n:.0f} {unite}" if n >= 10 else f"{n:.1f} {unite}"
        return f"{o} o"

    appareils = []
    for d in arbre:
        amovible = d.get("rm") in (True, 1, "1") or d.get("tran") == "usb"
        if not amovible or d.get("type") != "disk":
            continue
        #  Le nom montré : l'étiquette d'une partition si elle en a une, sinon
        #  le modèle, sinon le nom brut. C'est ce qui est écrit sur la clé.
        nom = (d.get("model") or d.get("name") or "").strip()
        monte = ""
        for part in d.get("children") or []:
            if part.get("label"):
                nom = part["label"].strip()
            if part.get("mountpoint"):
                monte = part["mountpoint"]
        #  Une clé (petite) ou un disque externe (gros) : l'icône change.
        try:
            gros = int(d.get("size") or 0) >= 256 * 10**9
        except (TypeError, ValueError):
            gros = False
        appareils.append({"nom": nom or d.get("name", ""),
                          "dev": "/dev/" + d.get("name", ""),
                          "taille": taille(d.get("size")),
                          "monte": monte, "disque": gros})
    return appareils


def _service_actif(nom):
    """Un service systemd tourne-t-il ? Renvoie None s'il n'est même pas
    installé — « éteint » et « absent » ne veulent pas dire la même chose,
    et la page doit pouvoir le dire."""
    if not shutil.which("systemctl"):
        return None
    etat_unite = _sortie(["systemctl", "is-enabled", nom])
    if not etat_unite or "not-found" in etat_unite:
        return None
    return _sortie(["systemctl", "is-active", nom]) == "active"


def _securite_etat():
    """L'état réel de l'autodéfense. Chaque entrée vaut True (en marche),
    False (installé mais arrêté) ou None (pas installé) — trois états, parce
    que « le pare-feu est éteint » et « il n'y a pas de pare-feu » appellent
    des gestes différents."""
    #  ufw status demande les droits root ; sans eux on lit le fichier de
    #  configuration, qui dit la même chose et se lit sans privilège.
    feu = None
    if shutil.which("ufw"):
        feu = False
        try:
            for ligne in Path(ETC_DIR / "ufw/ufw.conf").read_text().splitlines():
                if ligne.strip().startswith("ENABLED="):
                    feu = ligne.split("=", 1)[1].strip().lower() == "yes"
        except OSError:
            pass
    #  Le disque est-il chiffré ? Un périphérique de type « crypt » suffit.
    chiffre = False
    if shutil.which("lsblk"):
        chiffre = "crypt" in _sortie(["lsblk", "-o", "TYPE", "-n"]).split()
    return {
        "pareFeu": feu,
        "chiffre": chiffre,
        "antivirus": _service_actif("clamav-freshclam.service"),
        "intrusion": _service_actif("fail2ban.service"),
        "rootkit": bool(shutil.which("rkhunter") or shutil.which("chkrootkit")),
        "apparmor": _service_actif("apparmor.service"),
    }


VOLMAN = {
    "ouvrir":  "/autobrowse/enabled",
    "photos":  "/autophoto/enabled",
    "musique": "/autoplay-audio-cds/enabled",
    "monter":  "/automount-media/enabled",
}


def _amovibles_etat():
    """Ce que LexOS fait quand on branche quelque chose. thunar-volman garde
    ces réglages dans xfconf ; on lit les vrais, pas des valeurs supposées."""
    return {cle: _xfconf_lire("thunar-volman", prop) == "true"
            for cle, prop in VOLMAN.items()}


def _access_etat():
    """Accessibilité : ce qui est réglable, et ce qui est installé.
    La taille du curseur est un nombre ; au-delà de 32 on parle de « curseur
    large » — c'est le seuil où la différence se voit vraiment."""
    taille = _xfconf_lire("xsettings", "/Gtk/CursorThemeSize")
    theme = _xfconf_lire("xsettings", "/Net/ThemeName").lower()
    return {
        "contraste": "highcontrast" in theme.replace("-", "").replace(" ", ""),
        "curseurLarge": taille.isdigit() and int(taille) >= 32,
        "orca": bool(shutil.which("orca")),
        "onboard": bool(shutil.which("onboard")),
    }


def _maj_etat():
    """Mises à jour automatiques, et micrologiciel. On lit la configuration
    d'unattended-upgrades telle qu'elle est sur la machine."""
    secu, tout = False, False
    for f in (ETC_DIR / "apt/apt.conf.d/20auto-upgrades",
              ETC_DIR / "apt/apt.conf.d/50unattended-upgrades"):
        try:
            texte = Path(f).read_text()
        except OSError:
            continue
        for ligne in texte.splitlines():
            l = ligne.strip()
            if l.startswith("//") or l.startswith("#"):
                continue
            if "Unattended-Upgrade" in l and '"1"' in l:
                secu = True
            if "Update-Package-Lists" in l and '"1"' in l:
                secu = secu or True
    #  « Tout mettre à jour » = la ligne des dépôts autres que sécurité est
    #  décommentée dans 50unattended-upgrades.
    try:
        for ligne in Path(ETC_DIR / "apt/apt.conf.d/50unattended-upgrades").read_text().splitlines():
            l = ligne.strip()
            if l.startswith('"') and "-updates" in l and not l.startswith("//"):
                tout = True
    except OSError:
        pass
    return {"secu": secu, "tout": tout, "fwupd": bool(shutil.which("fwupdmgr"))}


def _utilisateurs_etat():
    """Les VRAIS comptes de la machine. On lit /etc/passwd et on garde les
    comptes humains : UID >= 1000 et un shell qui n'est pas nologin. Les
    dizaines de comptes de service (www-data, systemd-*) n'ont rien à faire
    dans une liste d'utilisateurs."""
    gens = []
    try:
        admins = set()
        for ligne in Path(ETC_DIR / "group").read_text().splitlines():
            champs = ligne.split(":")
            if len(champs) >= 4 and champs[0] in ("sudo", "wheel", "adm"):
                admins.update(m for m in champs[3].split(",") if m)
        for ligne in Path(ETC_DIR / "passwd").read_text().splitlines():
            champs = ligne.split(":")
            if len(champs) < 7:
                continue
            nom, _, uid, _, complet, foyer, shell = champs[:7]
            if not uid.isdigit() or int(uid) < 1000 or int(uid) >= 65000:
                continue
            if shell.endswith(("nologin", "false")):
                continue
            gens.append({"nom": nom,
                         "complet": (complet.split(",")[0] or nom).strip(),
                         "admin": nom in admins,
                         "moi": nom == os.environ.get("USER", "")})
    except OSError:
        pass
    return gens


def _imprimantes_etat():
    """Les imprimantes connues de CUPS, et laquelle est par défaut."""
    if not shutil.which("lpstat"):
        return {"dispo": False, "liste": []}
    defaut = ""
    sortie = _sortie(["lpstat", "-d"])
    if ":" in sortie:
        defaut = sortie.split(":", 1)[1].strip()
    liste = []
    for ligne in _sortie(["lpstat", "-p"]).splitlines():
        mots = ligne.split()
        if len(mots) >= 2 and mots[0] == "printer":
            nom = mots[1]
            liste.append({"nom": nom,
                          "etat": "prête" if "idle" in ligne else "occupée",
                          "defaut": nom == defaut})
    return {"dispo": True, "liste": liste}


def _clavier_etat():
    """Les dispositions de clavier actives, et laquelle est en service."""
    dispos, courante = [], ""
    if shutil.which("setxkbmap"):
        for ligne in _sortie(["setxkbmap", "-query"]).splitlines():
            if ligne.startswith("layout:"):
                dispos = [d for d in ligne.split(":", 1)[1].strip().split(",") if d]
    if shutil.which("xkb-switch"):
        courante = _sortie(["xkb-switch"])
    return {"dispositions": dispos, "courante": courante or (dispos[0] if dispos else "")}


def _distant_etat():
    """Le bureau à distance : le serveur est-il installé, et tourne-t-il ?"""
    outil = ""
    for c in ("x11vnc", "wayvnc", "krfb"):
        if shutil.which(c):
            outil = c
            break
    actif = False
    if outil and shutil.which("pgrep"):
        actif = bool(_sortie(["pgrep", "-x", outil]))
    return {"outil": outil, "actif": actif}


def _reseau_etat():
    """Le filaire : branché ou non, et avec quelle adresse. Une question
    simple qu'aucune section ne savait répondre."""
    if not shutil.which("nmcli"):
        return {"filaire": None, "ip": ""}
    filaire, ip = None, ""
    for ligne in _sortie(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE",
                          "device"]).splitlines():
        champs = ligne.split(":")
        if len(champs) >= 3 and champs[1] == "ethernet":
            filaire = champs[2] == "connected"
            if filaire:
                sortie = _sortie(["nmcli", "-t", "-f", "IP4.ADDRESS",
                                  "device", "show", champs[0]])
                for l in sortie.splitlines():
                    if ":" in l:
                        ip = l.split(":", 1)[1].split("/")[0]
                        break
            break
    return {"filaire": filaire, "ip": ip}


def _defaut_etat():
    """Quel logiciel ouvre quoi. xdg-settings dit le navigateur ; pour le
    reste on lit le fichier d'associations, celui que le bureau consulte."""
    nav = _sortie(["xdg-settings", "get", "default-web-browser"]) if shutil.which("xdg-settings") else ""
    assoc = {}
    chemins = [Path.home() / ".config/mimeapps.list",
               Path("/usr/share/applications/mimeapps.list")]
    interesse = {"text/plain": "texte", "image/png": "image",
                 "application/pdf": "pdf", "audio/mpeg": "musique",
                 "video/mp4": "video"}
    for f in chemins:
        try:
            dedans = False
            for ligne in f.read_text().splitlines():
                l = ligne.strip()
                if l.startswith("["):
                    dedans = l == "[Default Applications]"
                    continue
                if dedans and "=" in l:
                    mime, appli = l.split("=", 1)
                    cle = interesse.get(mime.strip())
                    if cle and cle not in assoc:
                        assoc[cle] = appli.split(";")[0].replace(".desktop", "")
        except OSError:
            continue
    return {"navigateur": nav.replace(".desktop", ""), "assoc": assoc}


def _couleurs_etat():
    """Les écrans connus de colord, et s'ils ont un profil de couleur."""
    if not shutil.which("colormgr"):
        return {"dispo": False, "ecrans": []}
    ecrans, courant = [], None
    for ligne in _sortie(["colormgr", "get-devices"]).splitlines():
        l = ligne.strip()
        if l.startswith("Model:"):
            courant = {"nom": l.split(":", 1)[1].strip(), "profil": ""}
            ecrans.append(courant)
        elif courant is not None and l.startswith("Default Profile:"):
            courant["profil"] = l.split(":", 1)[1].strip()
    return {"dispo": True, "ecrans": ecrans}


def _tablette_etat():
    """Une tablette graphique est-elle branchée ? xsetwacom la voit quand le
    pilote est chargé ; sinon on cherche dans les périphériques d'entrée."""
    if shutil.which("xsetwacom"):
        lignes = [l for l in _sortie(["xsetwacom", "--list", "devices"]).splitlines() if l.strip()]
        if lignes:
            return {"branchee": True,
                    "noms": [l.split("id:")[0].strip() for l in lignes]}
    return {"branchee": False, "noms": []}


def _notif_etat():
    """Ne pas déranger, et combien de temps une notification reste à l'écran."""
    c = "xfce4-notifyd"
    dnd = _xfconf_lire(c, "/do-not-disturb")
    duree = _xfconf_lire(c, "/expire-timeout")
    return {"silence": dnd == "true",
            "duree": duree if duree.isdigit() else ""}


def _mac_etat():
    """Cette machine est-elle un Mac ? Le fabricant est écrit dans le DMI par
    le BIOS ; c'est la source que tous les outils lisent."""
    try:
        vendeur = (DMI_DIR / "sys_vendor").read_text().strip()
        modele = (DMI_DIR / "product_name").read_text().strip()
    except OSError:
        return {"apple": False, "modele": ""}
    return {"apple": "apple" in vendeur.lower(), "modele": modele}


def _partage_etat():
    """Le serveur de partage tourne-t-il ?"""
    actif = bool(_sortie(["pgrep", "-f", "share-server.py"])) if shutil.which("pgrep") else False
    return {"actif": actif}


def _comptes_etat():
    """Les comptes en ligne reliés. Deux mécanismes cohabitent sous Linux et
    ne font pas la même chose : GNOME Online Accounts ouvre le compte DANS le
    gestionnaire de fichiers (rien n'est copié), rclone sait en plus
    synchroniser pour l'hors-ligne. On dit lequel est disponible."""
    liens = []
    if shutil.which("rclone"):
        for ligne in _sortie(["rclone", "listremotes"]).splitlines():
            nom = ligne.strip().rstrip(":")
            if nom:
                liens.append({"nom": nom, "par": "rclone"})
    return {"rclone": bool(shutil.which("rclone")),
            "goa": bool(shutil.which("gnome-control-center")
                        or Path("/usr/lib/gnome-online-accounts").exists()),
            "liens": liens}


def _bienetre_etat():
    """Temps d'écran du jour, et si le compteur tourne seulement.

    CORRECTION D'UNE ERREUR : cette fonction lisait
    ~/.config/lexos/ecran-aujourdhui, au format « date minutes ». Ce fichier
    n'existe nulle part et personne ne l'écrit. lexos-bienetre range son
    relevé AILLEURS et AUTREMENT : un fichier par jour, nommé AAAA-MM-JJ,
    dans ~/.local/share/lexos/bienetre/, contenant le seul nombre de minutes.
    La section affichait donc éternellement « pas de relevé » alors que le
    compteur faisait son travail.

    ET UNE DISTINCTION QUI COMPTE : le compteur est ARRÊTÉ par défaut —
    mesurer le temps de quelqu'un ne se fait pas sans qu'il le demande. « 0
    minute » et « le compteur ne tourne pas » ne veulent donc pas dire la
    même chose, et la page doit pouvoir les distinguer."""
    from datetime import date
    dossier = Path(os.environ.get(
        "LEXOS_BIENETRE_DIR",
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        / "lexos" / "bienetre"))
    minutes = 0
    try:
        brut = (dossier / date.today().isoformat()).read_text().strip()
        if brut.isdigit():
            minutes = int(brut)
    except (OSError, ValueError):
        pass
    #  Le compteur tourne-t-il ? C'est une minuterie systemd de l'utilisateur.
    tourne = False
    if shutil.which("systemctl"):
        tourne = _sortie(["systemctl", "--user", "is-active",
                          "lexos-bienetre.timer"]) == "active"
    return {"minutes": minutes,
            "tourne": tourne,
            "releve": (dossier / date.today().isoformat()).exists(),
            "pauses": bool(shutil.which("workrave")),
            "soir": bool(shutil.which("redshift") or shutil.which("gammastep"))}


def _heure_etat():
    """Fuseau et synchronisation automatique, via timedatectl."""
    if not shutil.which("timedatectl"):
        return {"fuseau": "", "auto": False}
    fuseau, auto = "", False
    for ligne in _sortie(["timedatectl", "show"]).splitlines():
        if ligne.startswith("Timezone="):
            fuseau = ligne.split("=", 1)[1]
        elif ligne.startswith("NTP="):
            auto = ligne.split("=", 1)[1] == "yes"
    #  Ce que l'horloge de la barre affiche VRAIMENT. La démo propose
    #  « 24 h / 12 h », « secondes » et « jour de la semaine » ; côté XFCE ces
    #  trois réglages ne sont qu'UN seul : la chaîne de format du greffon
    #  horloge. On la lit et on la décompose, plutôt que de garder trois
    #  drapeaux à part qui finiraient par mentir sur ce qui est affiché.
    fmt = _xfconf_lire("xfce4-panel", "/plugins/plugin-3/digital-time-format")
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        fuseau_auto = (conf / "fuseau-auto").read_text().strip() == "on"
    except OSError:
        fuseau_auto = False
    #  « Fuseau automatique » n'est proposable que si un lieu est connu — et
    #  le seul lieu que LexOS connaisse est celui qu'on lui a donné pour la
    #  météo. Sans ça, l'interrupteur promettrait une devinette qu'on refuse
    #  de faire (voir lexos-datetime : jamais de géolocalisation par IP).
    lieu_connu = False
    try:
        contenu = (conf / "meteo.conf").read_text()
        lieu_connu = "LEXOS_METEO_LAT=" in contenu and "LEXOS_METEO_LON=" in contenu
    except OSError:
        pass
    return {
        "fuseau": fuseau,
        "auto": auto,
        "fuseau_auto": fuseau_auto,
        "lieu_connu": lieu_connu,
        "maintenant": _sortie(["date", "+%A %d %B %Y, %H:%M:%S"]),
        "format": fmt,
        "h12": "%I" in fmt or "%l" in fmt,
        "secondes": "%S" in fmt,
        "jour": "%a" in fmt or "%A" in fmt,
    }


def etat():
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def fichier(nom, defaut):
        try:
            return (conf / nom).read_text().strip() or defaut
        except OSError:
            return defaut

    #  Même règle que avion_state() dans lexos-net : « -t » (terse) donne des
    #  mots-clés fixes, jamais traduits — contrairement à la sortie normale de
    #  nmcli, qui suit la langue du système (fr_CA par défaut sur LexOS).
    avion = "off"
    if shutil.which("nmcli"):
        wifi = _sortie(["nmcli", "-t", "radio", "wifi"]) or "?"
        wwan = _sortie(["nmcli", "-t", "radio", "wwan"]) or "?"
        if wifi == "disabled" and wwan in ("disabled", "missing"):
            avion = "on"

    version = ""
    try:
        for ligne in Path(ETC_DIR / "os-release").read_text().splitlines():
            if ligne.startswith("PRETTY_NAME="):
                version = ligne.split("=", 1)[1].strip('"')
                break
    except OSError:
        pass

    try:
        perf = Path(ETC_DIR / "lexos/performance").read_text().strip() or "medium"
    except OSError:
        perf = "medium"

    return {
        "perf": perf,
        "theme": fichier("mode", "sombre"),
        "accent": fichier("accent", "orange"),
        "police": fichier("police", "defaut"),
        "avion": avion,
        "hote": socket.gethostname(),
        "version": version or "LexOS 2.0.0 « Nomad »",
        "noyau": _sortie(["uname", "-r"]),
        "libre": _libre_etat(),
        #  L'état réel du matériel, pour que les sections montrent des
        #  VALEURS et pas seulement des boutons.
        "wifi": _wifi_etat(),
        "son": _son_etat(),
        "batterie": _batterie_etat(),
        "ecrans": _ecrans_etat(),
        "souris": _souris_etat(),
        "heure": _heure_etat(),
        "lumiere": _lumiere_etat(),
        "energie": _energie_etat(),
        "bluetooth": _bluetooth_etat(),
        "dock": _dock_etat(),
        "crt": _crt_etat(),
        "barreCachee": _barre_cachee(),
        "bureaux": _bureaux_etat(),
        "apercu": _apercu_etat(),
        "usb": _usb_etat(),
        "securite": _securite_etat(),
        "amovibles": _amovibles_etat(),
        "access": _access_etat(),
        "maj": _maj_etat(),
        "utilisateurs": _utilisateurs_etat(),
        "imprimantes": _imprimantes_etat(),
        "clavier": _clavier_etat(),
        "distant": _distant_etat(),
        "reseau": _reseau_etat(),
        "defaut": _defaut_etat(),
        "couleurs": _couleurs_etat(),
        "tablette": _tablette_etat(),
        "notif": _notif_etat(),
        "mac": _mac_etat(),
        "partage": _partage_etat(),
        "comptes": _comptes_etat(),
        "bienetre": _bienetre_etat(),
        "langue": _sortie(["sh", "-c", "printf %s \"${LANG:-}\""]) or os.environ.get("LANG", ""),
    }


# =============================================================================
#  Serveur : fichiers statiques + API.
# =============================================================================

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path == "/api/etat":
            return self._json(200, etat())
        return super().do_GET()

    def do_POST(self):
        if not self.path.startswith("/api/action"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        action = ACTIONS.get(requete.get("action", ""))
        if action is None:
            return self._json(400, {"ok": False, "erreur": "action inconnue"})
        try:
            return self._json(200, action(requete.get("arg")))
        except subprocess.TimeoutExpired:
            return self._json(200, {"ok": False, "erreur": "délai dépassé"})
        except Exception as e:  # la fenêtre doit survivre à un outil qui casse
            return self._json(200, {"ok": False, "erreur": str(e)})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")

    section = ""
    if len(sys.argv) > 1 and sys.argv[1].replace("-", "").isalnum():
        section = sys.argv[1]

    port = _port_libre()
    handler = functools.partial(Handler, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-settings-http").start()

    url = f"http://127.0.0.1:{port}/index.html"
    if section:
        url += f"#{section}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)

    #  La fenêtre s'ouvrait à 980 x 700, quel que soit l'écran. Sur le
    #  ThinkPad (1366 x 768), 700 pixels de haut coupaient la barre latérale
    #  au milieu : Alex voyait la liste s'arrêter à « Partage » et pensait
    #  qu'il manquait des sections. Les 32 sections sont bien là et la barre
    #  défile — mais une fenêtre qui n'utilise pas l'écran donne l'impression
    #  contraire.
    #
    #  Ubuntu ouvre ses Paramètres à la taille de l'écran disponible. On fait
    #  pareil : on prend ce que le bureau laisse (barre du haut et dock
    #  déduits, c'est ce que renvoie availableGeometry), sans jamais dépasser
    #  une largeur confortable en lecture ni descendre sous une taille
    #  utilisable.
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(900, min(1180, int(dispo.width() * 0.92)))
        hauteur = max(600, min(900, int(dispo.height() * 0.94)))
        fenetre.resize(largeur, hauteur)
        #  Centrer : sur un petit écran, une fenêtre presque aussi grande que
        #  le bureau posée en haut à gauche déborde à droite et en bas.
        fenetre.move(
            dispo.x() + (dispo.width() - largeur) // 2,
            dispo.y() + (dispo.height() - hauteur) // 2,
        )
    else:
        fenetre.resize(980, 700)
    icone = "/usr/share/icons/hicolor/128x128/apps/lexos-reglages.png"
    if Path(icone).exists():
        fenetre.setWindowIcon(QIcon(icone))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)
    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
