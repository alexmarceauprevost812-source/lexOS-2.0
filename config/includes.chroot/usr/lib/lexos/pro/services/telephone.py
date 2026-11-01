"""Mon téléphone — le « Lien avec le mobile » de LexOS, côté logique.

ALEX (2026-11-01) : « ajouter une application comme Windows, exemple
partager des fichiers, même l'écran du téléphone ». Rien de neuf sous le
capot : LexOS avait déjà les briques, éparpillées dans le terminal.

    · l'écran du téléphone sur l'ordi ...... scrcpy (Android, via adb)
    · envoyer des fichiers ................. KDE Connect, sinon le QR code
                                             de lexos-share (aucune appli à
                                             installer sur le téléphone)
    · recevoir des fichiers ................ la boîte de réception de
                                             lexos-share (même page web)
    · faire sonner le téléphone ............ KDE Connect

Ce module les réunit, sans Qt : il se teste partout (tests/pro). Chaque
fonction rend un execution.Resultat ou un dict simple ; aucune ne lève.
Les chemins des outils sont ouverts par variables d'environnement pour que
le banc puisse substituer de faux kdeconnect-cli / adb / scrcpy.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

from . import execution

KDE = os.environ.get("LEXOS_TEL_KDE", "kdeconnect-cli")
ADB = os.environ.get("LEXOS_TEL_ADB", "adb")
SCRCPY = os.environ.get("LEXOS_TEL_SCRCPY", "scrcpy")
PARTAGE = os.environ.get("LEXOS_TEL_PARTAGE", "lexos-share")

#  Une adresse IPv4, avec ou sans port : « 192.168.1.42 » ou « …:5555 ».
_IP = re.compile(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?$")


def dossier_recus() -> Path:
    """Là où lexos-share range ce que le téléphone envoie (même règle que
    lui : Téléchargements, sinon Downloads, sinon le dossier personnel)."""
    maison = Path.home()
    base = Path(os.environ.get("XDG_DOWNLOAD_DIR") or maison / "Téléchargements")
    if not base.is_dir():
        base = maison / "Downloads"
    if not base.is_dir():
        base = maison
    return base / "LexOS-reçus"


# --- KDE Connect -------------------------------------------------------------
def appareils_kde() -> list:
    """Les téléphones KDE Connect joignables : [(identifiant, nom), …].
    Vide si KDE Connect manque ou ne répond pas — jamais une exception."""
    if not execution.outil_present(KDE):
        return []
    r = execution.lancer([KDE, "--list-available", "--id-name-only"], delai=6)
    if not r.ok:
        return []
    appareils = []
    for ligne in r.lignes():
        ident, _, nom = ligne.strip().partition(" ")
        if ident:
            appareils.append((ident, nom.strip() or ident))
    return appareils


# --- adb (Android) -----------------------------------------------------------
def appareils_adb() -> list:
    """Les téléphones Android vus par adb : [(série, état), …]. L'état
    « unauthorized » veut dire : accepter la fenêtre sur le téléphone."""
    if not execution.outil_present(ADB):
        return []
    r = execution.lancer([ADB, "devices"], delai=6)
    if not r.ok:
        return []
    appareils = []
    for ligne in r.lignes():
        if ligne.startswith("List of devices") or ligne.startswith("*"):
            continue
        morceaux = ligne.split()
        if len(morceaux) >= 2:
            appareils.append((morceaux[0], morceaux[1]))
    return appareils


def etat() -> dict:
    """Tout ce que la fenêtre affiche, lu en une fois (appelé en fond)."""
    kde = appareils_kde()
    adb = appareils_adb()
    return {
        "kde_installe": execution.outil_present(KDE),
        "kde": kde,
        "adb_installe": execution.outil_present(ADB),
        "adb": adb,
        "adb_prets": [s for s, e in adb if e == "device"],
        "scrcpy_installe": execution.outil_present(SCRCPY),
        "partage_installe": execution.outil_present(PARTAGE),
        "recus": str(dossier_recus()),
    }


# --- Les actions -------------------------------------------------------------
def afficher_ecran(serie: str = "") -> execution.Resultat:
    """Ouvre la fenêtre de l'écran du téléphone (scrcpy), détachée : elle
    reste ouverte même si on ferme Mon téléphone."""
    if not execution.outil_present(SCRCPY):
        return execution.Resultat(
            False, erreur="scrcpy n'est pas installé — l'écran du téléphone "
                          "a besoin du paquet scrcpy.")
    pret = [s for s, e in appareils_adb() if e == "device"]
    if not pret:
        etats = appareils_adb()
        if any(e == "unauthorized" for _, e in etats):
            return execution.Resultat(
                False, erreur="Le téléphone demande une autorisation : accepte "
                              "« Autoriser le débogage USB » sur son écran.")
        return execution.Resultat(
            False, erreur="Aucun téléphone Android trouvé. Branche-le en USB "
                          "avec le débogage USB activé, ou connecte-le en Wi-Fi.")
    argv = [SCRCPY, "--window-title", "Mon téléphone — écran"]
    if serie and serie in pret:
        argv += ["--serial", serie]
    elif len(pret) > 1:
        argv += ["--serial", pret[0]]
    return execution.lancer_detache(argv)


def adresse_valide(adresse: str) -> str:
    """« 192.168.1.42 » → « 192.168.1.42:5555 » ; « » si l'adresse est
    invalide. Rien d'autre qu'une IPv4 n'atteint jamais adb."""
    m = _IP.match((adresse or "").strip())
    if not m:
        return ""
    if any(int(m.group(i)) > 255 for i in range(1, 5)):
        return ""
    port = int(m.group(5) or 5555)
    if not 1 <= port <= 65535:
        return ""
    return f"{'.'.join(m.group(i) for i in range(1, 5))}:{port}"


def connecter_wifi(adresse: str) -> execution.Resultat:
    """adb connect <ip>:<port>. Android 11+ : le port et le jumelage se
    font dans Options développeur → Débogage sans fil."""
    cible = adresse_valide(adresse)
    if not cible:
        return execution.Resultat(
            False, erreur="Adresse invalide : écris l'adresse IP du téléphone, "
                          "par exemple 192.168.1.42 (ou 192.168.1.42:5555).")
    r = execution.lancer([ADB, "connect", cible], delai=12)
    #  adb rend 0 même quand il échoue : on lit ce qu'il a dit.
    texte = (r.sortie or r.erreur).lower()
    if r.ok and ("connected" in texte and "cannot" not in texte and "failed" not in texte):
        return execution.Resultat(True, sortie=f"Téléphone connecté en Wi-Fi ({cible}).")
    return execution.Resultat(
        False, erreur=f"Connexion à {cible} impossible : {r.sortie or r.erreur}".strip())


def envoyer(fichiers, appareil_kde: str = "") -> execution.Resultat:
    """Envoie des fichiers au téléphone. KDE Connect s'il y a un téléphone
    jumelé (direct, rien à scanner), sinon la fenêtre QR de lexos-share."""
    chemins = [str(Path(f)) for f in fichiers if Path(f).is_file()]
    if not chemins:
        return execution.Resultat(False, erreur="Aucun fichier à envoyer.")
    kde = appareils_kde()
    ids = [i for i, _ in kde]
    cible = appareil_kde if appareil_kde in ids else (ids[0] if len(ids) == 1 else "")
    if cible:
        rates = []
        for c in chemins:
            r = execution.lancer([KDE, "--device", cible, "--share", c], delai=20)
            if not r.ok:
                rates.append(Path(c).name)
        nom = dict(kde).get(cible, cible)
        if not rates:
            n = len(chemins)
            return execution.Resultat(
                True, sortie=f"{n} fichier{'s' if n > 1 else ''} envoyé{'s' if n > 1 else ''} à {nom}.")
        return execution.Resultat(
            False, erreur=f"Envoi raté vers {nom} : {', '.join(rates)}.")
    if not execution.outil_present(PARTAGE):
        return execution.Resultat(False, erreur="lexos-share est introuvable.")
    r = execution.lancer_detache([PARTAGE, "qr", *chemins])
    if r.ok:
        return execution.Resultat(
            True, sortie="Un code QR s'ouvre : scanne-le avec l'appareil photo "
                         "du téléphone (même Wi-Fi) pour télécharger.")
    return r


def recevoir() -> execution.Resultat:
    """Ouvre la boîte de réception (code QR) : le téléphone envoie ses
    photos et fichiers depuis son navigateur, sans appli."""
    if not execution.outil_present(PARTAGE):
        return execution.Resultat(False, erreur="lexos-share est introuvable.")
    r = execution.lancer_detache([PARTAGE, "receive"])
    if r.ok:
        return execution.Resultat(
            True, sortie=f"Scanne le code QR avec le téléphone. Les fichiers "
                         f"arrivent dans {dossier_recus()}.")
    return r


def sonner(appareil_kde: str = "") -> execution.Resultat:
    """Fait sonner le téléphone (pour le retrouver), par KDE Connect."""
    ids = [i for i, _ in appareils_kde()]
    cible = appareil_kde if appareil_kde in ids else (ids[0] if ids else "")
    if not cible:
        return execution.Resultat(
            False, erreur="Aucun téléphone KDE Connect jumelé et joignable.")
    r = execution.lancer([KDE, "--device", cible, "--ring"], delai=10)
    return execution.Resultat(True, sortie="Le téléphone sonne.") if r.ok else r


def ouvrir_kde() -> execution.Resultat:
    """L'appli KDE Connect, pour jumeler un nouveau téléphone."""
    for app in ("kdeconnect-app", "kdeconnect-settings"):
        if execution.outil_present(app):
            return execution.lancer_detache([app])
    return execution.Resultat(
        False, erreur="L'application KDE Connect n'est pas installée (paquet kdeconnect).")
