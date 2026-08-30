"""LexOS Médecin — bilan de santé de la machine INSTALLÉE.

C'est le pendant de verifier.sh (lexos-avant-de-construire.md), mais après
coup : verifier.sh regarde le dépôt avant de construire une ISO ; lexos-medecin
regarde la machine sous vos pieds, une fois installée. Même esprit : ne rien
laisser un trou silencieux, tout mettre en un rapport qu'on peut coller
quand quelqu'un écrit « ça marche pas ».

Plutôt que de faire vivre ici une liste figée des ~63 outils lexos-*
(qui se périmerait au premier outil ajouté), le contrôle des outils se
fait par DÉCOUVERTE : on regarde ce qui existe réellement sous /usr/bin
sur CETTE machine, exactement comme le fait le script bash de
lexos-carte-des-trous.md :

    for f in config/includes.chroot/usr/bin/lexos-*; do
      o=$(basename "$f"); s=${o#lexos-}
      grep -q "^[[:space:]]*$s)" config/includes.chroot/usr/bin/lexos \
        || echo "PAS DANS LE case : $o"
    done

— la même logique, rejouée en direct sur la machine plutôt que sur le dépôt.
"""
from __future__ import annotations

import datetime as _dt
import os
import re
from pathlib import Path

import moteur
from utils import executable_present, executer, lire_version_lexos

CHEMIN_DISPATCHEUR = Path("/usr/bin/lexos")
DOSSIER_BIN = Path("/usr/bin")
DOSSIER_LANCEURS = Path("/usr/share/applications")
SEUIL_DISQUE_ALERTE = 90  # pourcentage


def _outils_lexos_installes() -> list:
    if not DOSSIER_BIN.is_dir():
        return []
    return sorted(p.name for p in DOSSIER_BIN.glob("lexos-*") if p.is_file())


def _texte_dispatcheur():
    if CHEMIN_DISPATCHEUR.is_file():
        try:
            return CHEMIN_DISPATCHEUR.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return None
    return None


def _branche_dans_dispatcheur(nom_outil: str, texte):
    if texte is None:
        return None
    suffixe = nom_outil[len("lexos-"):]
    motif = re.compile(rf"^\s*{re.escape(suffixe)}\)", re.MULTILINE)
    return bool(motif.search(texte))


def _a_un_lanceur(nom_outil: str):
    if not DOSSIER_LANCEURS.is_dir():
        return None
    for fichier in DOSSIER_LANCEURS.glob("*.desktop"):
        try:
            if nom_outil in fichier.read_text(encoding="utf-8", errors="ignore"):
                return True
        except OSError:
            continue
    return False


def verifier_outils() -> dict:
    outils = _outils_lexos_installes()
    texte = _texte_dispatcheur()

    releve = []
    for nom in outils:
        chemin = DOSSIER_BIN / nom
        releve.append({
            "nom": nom,
            "executable": os.access(chemin, os.X_OK),
            "branche_dispatcheur": _branche_dans_dispatcheur(nom, texte),
            "a_un_lanceur": _a_un_lanceur(nom),
        })

    problemes = [r for r in releve if not r["executable"] or r["branche_dispatcheur"] is False]
    return {
        "total": len(releve),
        "outils": releve,
        "problemes": problemes,
        "dispatcheur_trouve": texte is not None,
    }


def verifier_son() -> dict:
    for cmd in (["wpctl", "status"], ["pactl", "info"]):
        if executable_present(cmd[0]):
            sortie = executer(cmd)
            return {"teste_avec": cmd[0], "fonctionne": sortie is not None}
    return {"teste_avec": None, "fonctionne": None}


def verifier_wifi() -> dict:
    if not executable_present("nmcli"):
        return {"disponible": None, "connecte": None}
    radio = executer(["nmcli", "-t", "-f", "WIFI", "g"])
    actif = bool(radio) and radio.strip().lower() in ("enabled", "activé", "active", "oui", "yes")
    sortie = executer(["nmcli", "-t", "-f", "TYPE,STATE", "dev"])
    connecte = False
    if sortie:
        for ligne in sortie.splitlines():
            if ligne.startswith("wifi:") and "connect" in ligne.split(":", 1)[1].lower():
                connecte = True
    return {"disponible": actif, "connecte": connecte}


def verifier_espace_disque(seuil: int = SEUIL_DISQUE_ALERTE) -> list:
    return [d for d in moteur.etat_disques() if d["pourcentage"] >= seuil]


def verifier_erreurs_journal(nb_lignes: int = 20) -> dict:
    if not executable_present("journalctl"):
        return {"disponible": False, "lignes": [], "nombre": 0}
    sortie = executer(
        ["journalctl", "-p", "err", "-b", "--no-pager", "-n", str(nb_lignes), "-o", "short"],
        timeout=6.0,
    )
    # journalctl écrit lui-même "-- No entries --" quand il n'y a rien à
    # montrer : ce n'est pas une ligne d'erreur, il ne faut pas la compter
    # comme telle.
    lignes = [
        l for l in (sortie or "").splitlines()
        if l.strip() and "No entries" not in l
    ]
    return {"disponible": True, "lignes": lignes, "nombre": len(lignes)}


def bilan_complet() -> dict:
    return {
        "outils": verifier_outils(),
        "son": verifier_son(),
        "wifi": verifier_wifi(),
        "disques_pleins": verifier_espace_disque(),
        "journal": verifier_erreurs_journal(),
    }


def rapport_texte() -> str:
    """Le rapport en une page, en français, prêt à copier-coller."""
    b = bilan_complet()
    maintenant = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lignes = [
        f"=== Bilan LexOS Médecin — {maintenant} ===",
        f"Version LexOS : {lire_version_lexos()}",
        "",
    ]

    outils = b["outils"]
    if outils["dispatcheur_trouve"]:
        lignes.append(f"Outils lexos-* : {outils['total']} trouvés, {len(outils['problemes'])} problème(s).")
        for p in outils["problemes"]:
            raisons = []
            if not p["executable"]:
                raisons.append("pas exécutable")
            if p["branche_dispatcheur"] is False:
                raisons.append("absent du dispatcheur (case)")
            lignes.append(f"  - {p['nom']} : {', '.join(raisons)}")
    else:
        lignes.append("Outils lexos-* : /usr/bin/lexos introuvable, vérification impossible.")

    son = b["son"]
    if son["fonctionne"] is None:
        lignes.append("Son : aucun outil de diagnostic (wpctl/pactl) trouvé.")
    else:
        lignes.append(f"Son : {'OK' if son['fonctionne'] else 'NE RÉPOND PAS'} (testé avec {son['teste_avec']})")

    wifi = b["wifi"]
    if wifi["disponible"] is None:
        lignes.append("Wi-Fi : nmcli absent, vérification impossible.")
    else:
        etat = "radio activée" if wifi["disponible"] else "radio désactivée"
        connexion = "connecté" if wifi["connecte"] else "non connecté"
        lignes.append(f"Wi-Fi : {etat}, {connexion}")

    disques = b["disques_pleins"]
    if disques:
        lignes.append(f"Espace disque : {len(disques)} partition(s) au-delà de {SEUIL_DISQUE_ALERTE} % :")
        for d in disques:
            lignes.append(f"  - {d['point_montage']} : {d['pourcentage']} %")
    else:
        lignes.append("Espace disque : toutes les partitions sont sous le seuil d'alerte.")

    journal = b["journal"]
    if journal["disponible"]:
        lignes.append(f"Erreurs journal (démarrage courant) : {journal['nombre']}")
        for l in journal["lignes"][:10]:
            lignes.append(f"  {l}")
    else:
        lignes.append("Erreurs journal : journalctl indisponible.")

    lignes.append("")
    lignes.append("=== Fin du rapport — copiez-collez tel quel pour demander de l'aide ===")
    return "\n".join(lignes)
