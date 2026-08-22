"""Opérations système de bas niveau, toutes réversibles.

Ce module ne décide rien : il exécute, et il sait rendre compte de ce
qu'il faut faire pour revenir en arrière. Toute la logique de décision
est dans profil.py et actions.py.

Règle appliquée partout ici : on capture l'état AVANT de modifier, et on
renvoie cet état à l'appelant pour qu'il l'écrive au journal.
"""

from __future__ import annotations

import os
import pwd
import shutil
import subprocess
import time

REPERTOIRE_SAUVEGARDES = "/var/lib/lexos/boost/sauvegardes"


# --------------------------------------------------------------------------
# exécution de commandes
# --------------------------------------------------------------------------

def executer(argv: list[str], delai: int = 30, entree: str | None = None) -> tuple[int, str, str]:
    """Exécute une commande. Renvoie (code_retour, sortie, erreur).

    Ne lève jamais : un exécutable absent renvoie le code 127, comme un
    shell le ferait.
    """
    try:
        res = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=delai,
            input=entree,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", f"commande introuvable : {argv[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"délai dépassé : {' '.join(argv)}"
    except OSError as erreur:
        return 1, "", str(erreur)
    return res.returncode, res.stdout.strip(), res.stderr.strip()


def commande_existe(nom: str) -> bool:
    return shutil.which(nom) is not None


# --------------------------------------------------------------------------
# fichiers de configuration
# --------------------------------------------------------------------------

def capturer_fichier(chemin: str) -> dict:
    """Photographie un fichier avant modification.

    Renvoie un dictionnaire sérialisable qui suffit à le remettre
    exactement dans son état d'origine — y compris son absence.
    """
    if not os.path.exists(chemin):
        return {"chemin": chemin, "existait": False}
    try:
        with open(chemin, "r", encoding="utf-8", errors="surrogateescape") as f:
            contenu = f.read()
        infos = os.stat(chemin)
    except OSError as erreur:
        return {"chemin": chemin, "existait": True, "erreur_lecture": str(erreur)}
    return {
        "chemin": chemin,
        "existait": True,
        "contenu": contenu,
        "mode": infos.st_mode & 0o777,
    }


def copie_de_securite(chemin: str) -> str | None:
    """Copie horodatée d'un fichier sensible, en plus du journal.

    Utilisé pour /etc/fstab et /etc/default/grub : si le journal était
    perdu, il reste une copie sur disque que l'utilisateur peut remettre
    à la main depuis un live USB.
    """
    if not os.path.exists(chemin):
        return None
    try:
        os.makedirs(REPERTOIRE_SAUVEGARDES, mode=0o755, exist_ok=True)
        nom = os.path.basename(chemin) + "." + time.strftime("%Y%m%d-%H%M%S")
        destination = os.path.join(REPERTOIRE_SAUVEGARDES, nom)
        shutil.copy2(chemin, destination)
        return destination
    except OSError:
        return None


def ecrire_fichier(chemin: str, contenu: str, mode: int = 0o644) -> None:
    """Écrit un fichier de configuration, en créant les dossiers manquants."""
    repertoire = os.path.dirname(chemin)
    if repertoire:
        os.makedirs(repertoire, mode=0o755, exist_ok=True)
    temporaire = chemin + ".lexos-tmp"
    with open(temporaire, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(temporaire, mode)
    os.replace(temporaire, chemin)


def restaurer_fichier(capture: dict) -> tuple[bool, str]:
    """Remet un fichier dans l'état décrit par capturer_fichier()."""
    chemin = capture.get("chemin")
    if not chemin:
        return False, "capture sans chemin"

    if not capture.get("existait"):
        # le fichier n'existait pas avant : on le retire
        try:
            if os.path.exists(chemin):
                os.unlink(chemin)
            return True, f"{chemin} retiré"
        except OSError as erreur:
            return False, f"impossible de retirer {chemin} : {erreur}"

    if "contenu" not in capture:
        return False, f"{chemin} : contenu d'origine non capturé, restauration impossible"

    try:
        ecrire_fichier(chemin, capture["contenu"], capture.get("mode", 0o644))
        return True, f"{chemin} restauré"
    except OSError as erreur:
        return False, f"impossible de restaurer {chemin} : {erreur}"


# --------------------------------------------------------------------------
# /sys et /proc
# --------------------------------------------------------------------------

def lire_sysfs(chemin: str) -> str | None:
    try:
        with open(chemin, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def ecrire_sysfs(chemin: str, valeur: str) -> tuple[bool, str]:
    """Écrit une valeur dans /sys ou /proc. Échoue proprement si interdit."""
    try:
        with open(chemin, "w", encoding="utf-8") as f:
            f.write(valeur)
        return True, ""
    except OSError as erreur:
        return False, f"{chemin} : {erreur}"


def ecrire_sysctl_direct(cle: str, valeur: str) -> tuple[bool, str]:
    """Applique un sysctl tout de suite (sans attendre le redémarrage)."""
    chemin = "/proc/sys/" + cle.replace(".", "/")
    return ecrire_sysfs(chemin, valeur)


def lire_sysctl(cle: str) -> str | None:
    return lire_sysfs("/proc/sys/" + cle.replace(".", "/"))


# --------------------------------------------------------------------------
# systemd
# --------------------------------------------------------------------------

def systemd_present() -> bool:
    return os.path.isdir("/run/systemd/system") and commande_existe("systemctl")


def unite_existe(unite: str) -> bool:
    code, sortie, _ = executer(["systemctl", "list-unit-files", unite, "--no-legend"])
    return code == 0 and bool(sortie)


def etat_unite(unite: str) -> dict:
    """État actuel d'une unité systemd : activée au démarrage ? en cours ?"""
    _, activee, _ = executer(["systemctl", "is-enabled", unite])
    _, active, _ = executer(["systemctl", "is-active", unite])
    return {"unite": unite, "activee": activee.strip(), "active": active.strip()}


def desactiver_unite(unite: str) -> tuple[bool, str]:
    code, _, erreur = executer(["systemctl", "disable", "--now", unite], delai=60)
    if code != 0:
        return False, f"{unite} : {erreur or 'échec de la désactivation'}"
    return True, f"{unite} désactivé"


def restaurer_unite(etat: dict) -> tuple[bool, str]:
    """Remet une unité dans l'état capturé par etat_unite()."""
    unite = etat.get("unite")
    if not unite:
        return False, "état d'unité sans nom"

    messages = []
    if etat.get("activee") == "enabled":
        code, _, erreur = executer(["systemctl", "enable", unite], delai=60)
        if code != 0:
            return False, f"{unite} : {erreur or 'échec de la réactivation'}"
        messages.append("réactivé au démarrage")
    if etat.get("active") == "active":
        code, _, erreur = executer(["systemctl", "start", unite], delai=60)
        if code != 0:
            messages.append(f"redémarrage manuel nécessaire ({erreur})")
        else:
            messages.append("redémarré")
    return True, f"{unite} : " + (", ".join(messages) or "était déjà inactif")


def recharger_systemd() -> None:
    executer(["systemctl", "daemon-reload"], delai=60)


# --------------------------------------------------------------------------
# session graphique de l'utilisateur
# --------------------------------------------------------------------------

def utilisateur_bureau() -> tuple[str, int] | None:
    """Utilisateur derrière la session graphique, même quand on est root.

    Quand LexOS Boost tourne sous sudo/pkexec, les réglages XFCE doivent
    être appliqués au vrai utilisateur, pas à root — sinon ils ne
    changent rien à l'écran.
    """
    nom = os.environ.get("PKEXEC_UID")
    if nom and nom.isdigit():
        try:
            return pwd.getpwuid(int(nom)).pw_name, int(nom)
        except KeyError:
            pass

    nom = os.environ.get("SUDO_USER")
    if nom and nom != "root":
        try:
            return nom, pwd.getpwnam(nom).pw_uid
        except KeyError:
            pass

    if os.geteuid() != 0:
        try:
            infos = pwd.getpwuid(os.geteuid())
            return infos.pw_name, infos.pw_uid
        except KeyError:
            return None

    # dernier recours : la première session graphique trouvée par loginctl
    code, sortie, _ = executer(["loginctl", "list-sessions", "--no-legend"])
    if code == 0:
        for ligne in sortie.splitlines():
            morceaux = ligne.split()
            if len(morceaux) >= 3 and morceaux[2] != "root":
                try:
                    return morceaux[2], pwd.getpwnam(morceaux[2]).pw_uid
                except KeyError:
                    continue
    return None


def xfconf(arguments: list[str]) -> tuple[int, str, str]:
    """Appelle xfconf-query dans la session de l'utilisateur du bureau."""
    if not commande_existe("xfconf-query"):
        return 127, "", "xfconf-query absent (bureau non XFCE ?)"

    cible = utilisateur_bureau()
    if cible is None:
        return 1, "", "aucune session graphique identifiée"
    nom, uid = cible

    if os.geteuid() == 0 and os.getuid() != uid:
        environnement = f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
        return executer(
            ["sudo", "-u", nom, "env", environnement, "DISPLAY=:0", "xfconf-query"] + arguments
        )
    return executer(["xfconf-query"] + arguments)
