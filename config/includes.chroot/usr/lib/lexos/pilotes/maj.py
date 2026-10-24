"""LexOS Pilotes — la partie qui écrit sur le système (lancée en root par pkexec).

Deux actions seulement, et aucune entrée venue de l'utilisateur :
    verifier   rafraîchit les index apt
    installer  rafraîchit, puis met à jour LES PAQUETS GRAPHIQUES (et eux seuls)

La liste des paquets ne vient pas de l'interface : elle est recalculée ICI,
en root, par paquets.py. Une page web ne peut donc rien faire installer
d'autre que ce que le filtre MOTIF_GRAPHIQUE laisse passer.

RIEN N'EST JAMAIS RETIRÉ. Le filtre porte sur les noms DEMANDÉS, pas sur la
transaction : une nouvelle Mesa qui porte un « Breaks », et apt -y retirait
en silence un paquet que la page n'avait jamais montré. Donc : simulation
d'abord (apt-get -s), refus avec la liste si elle retire quoi que ce soit,
puis la vraie commande avec --no-remove. Et on ne dit « rien n'a été
changé » que si l'état de dpkg, relu avant et après, le PROUVE.

La dernière ligne de la sortie est « LEXOS-RESULTAT {json} » : c'est ce que
lit le serveur de l'interface. Tout ce qui précède est le journal lisible.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

import paquets  # noqa: E402

ENV_APT = dict(os.environ, DEBIAN_FRONTEND="noninteractive", LC_ALL="C.UTF-8")
#  Le banc détourne cette racine vers un faux arbre de noyaux.
RACINE_MODULES = Path(os.environ.get("LEXOS_PILOTES_MODULES", "/lib/modules"))
#  dkms seul, HORS de toute transaction dpkg : le tuer ne laisse pas dpkg à
#  moitié configuré, et l'avertissement dit de le relancer. Le banc le
#  raccourcit pour éprouver ce chemin avec un vrai dépassement.
DELAI_DKMS = 1800


def journal(texte: str) -> None:
    try:
        print(texte, flush=True)
    except OSError:
        #  Le lecteur a disparu (sortie coupée, disque plein) : on ne
        #  s'arrête JAMAIS pour autant au milieu d'une transaction dpkg. La
        #  suite part dans /dev/null ; apt, dpkg et le contrôle du module
        #  NVIDIA vont au bout. Avant, BrokenPipeError arrêtait l'aide
        #  juste après le retour d'apt-get.
        try:
            nul = os.open(os.devnull, os.O_WRONLY)
            os.dup2(nul, sys.stdout.fileno())
            os.close(nul)
            sys.stdout.flush()
        except (OSError, ValueError):
            pass


def fin(resultat: dict, code: int = 0) -> None:
    journal("LEXOS-RESULTAT " + json.dumps(resultat, ensure_ascii=False))
    sys.exit(code)


def _outil(cmd: list, delai: Optional[int]) -> tuple:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=delai, env=ENV_APT, check=False)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, f"{cmd[0]} {' '.join(cmd[1:2])} : délai de {delai} s dépassé"
    except OSError as exc:
        return 127, f"{cmd[0]} : {exc}"


def apt(arguments: list, delai: Optional[int]) -> tuple:
    return _outil(["apt-get", *arguments], delai)


def _extrait(sortie: str, tete: int = 1500, queue: int = 4000) -> str:
    #  Le DÉBUT compte autant que la fin : c'est là qu'apt écrit « The
    #  following packages will be REMOVED ». Le journal ne gardait que les
    #  4000 derniers caractères.
    if len(sortie) <= tete + queue:
        return sortie
    return sortie[:tete] + "\n  […]\n" + sortie[-queue:]


def rafraichir() -> bool:
    journal("» Recherche des nouvelles versions (apt-get update)…")
    code, sortie = apt(["update", "-q"], delai=300)
    if code != 0:
        journal(sortie[-1500:])
        if "lock" in sortie.lower() or "verrou" in sortie.lower():
            journal("!! Une autre installation est en cours. Réessaie dans une minute.")
        return False
    journal("  index à jour")
    return True


def noyau_le_plus_recent() -> str:
    try:
        noms = [p.name for p in RACINE_MODULES.iterdir() if p.is_dir()]
    except OSError:
        return ""
    if not noms:
        return ""
    r = subprocess.run(["sort", "-V"], input="\n".join(noms), capture_output=True, text=True, check=False)
    lignes = [l for l in r.stdout.splitlines() if l.strip()]
    return lignes[-1] if lignes else ""


def module_nvidia_present(noyau: str) -> bool:
    if not noyau:
        return False
    for _ in (RACINE_MODULES / noyau).rglob("nvidia.ko*"):
        return True
    return False


def etat_dpkg() -> Optional[dict]:
    """{paquet: (version, état)} — la preuve de ce qui a changé, ou pas.
    None si dpkg-query ne répond pas : on ne sait pas, et on le dira."""
    try:
        r = subprocess.run(["dpkg-query", "-W", "-f", "${binary:Package}\t${Version}\t${db:Status-Abbrev}\n"],
                           capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    etat = {}
    for ligne in r.stdout.splitlines():
        morceaux = ligne.split("\t")
        if len(morceaux) == 3 and morceaux[0]:
            etat[morceaux[0]] = (morceaux[1], morceaux[2].strip())
    return etat


def _lisible(v: tuple) -> str:
    version, etat = v
    if etat.startswith("ii"):
        return version
    if etat.startswith(("rc", "un", "pn")) or not version:
        return "retiré"
    #  « iU » dépaqueté, « iF » à moitié configuré : le cas de l'écran noir.
    return f"{version} (état {etat})"


def differences(avant: dict, apres: dict) -> list:
    """Ce que dpkg a VRAIMENT changé : [{paquet, avant, apres}]."""
    changes = []
    for nom in sorted(set(avant) | set(apres)):
        a, b = avant.get(nom), apres.get(nom)
        if a != b:
            changes.append({"paquet": nom,
                            "avant": _lisible(a) if a else "absent",
                            "apres": _lisible(b) if b else "retiré"})
    return changes


def verifier_module(avertissements: list) -> bool:
    """LA VÉRIFICATION QUI COMPTE : le noyau sur lequel la machine VA
    redémarrer a-t-il un nvidia.ko ? Sans lui, écran noir au prochain
    démarrage — la panne que LexOS traque depuis le build 29.

    Rend True si le module est là. Sinon, ajoute un avertissement qui dit
    POURQUOI et QUOI faire — un remède qui échouerait pour la même raison
    (« sudo dkms autoinstall » sans en-têtes) n'en est pas un.
    """
    noyau = noyau_le_plus_recent()
    if not noyau:
        avertissements.append(
            f"Impossible de lire {RACINE_MODULES} : la présence du module NVIDIA pour le prochain "
            "démarrage n'a pas pu être vérifiée. NE redémarre PAS avant d'avoir vérifié "
            "(« ls /lib/modules/*/updates/dkms/ » dans un terminal).")
        return False
    if module_nvidia_present(noyau):
        journal(f"  ✓ module NVIDIA présent pour le noyau {noyau}")
        return True
    journal(f"» Module NVIDIA absent pour {noyau} — recompilation (dkms autoinstall)…")
    secours = ("Au pire, choisis « Advanced options » dans GRUB et démarre sur l'ancien noyau.")
    if not (RACINE_MODULES / noyau / "build").exists():
        #  Sans en-têtes, dkms ne peut RIEN compiler : on ne le lance pas, et
        #  on nomme le paquet qui manque.
        journal(f"!! Les en-têtes du noyau {noyau} manquent ({RACINE_MODULES / noyau / 'build'} absent).")
        avertissements.append(
            f"Le module NVIDIA n'existe pas pour le noyau {noyau}, et il ne peut pas être compilé : "
            f"les en-têtes de ce noyau manquent (paquet linux-headers-{noyau}). NE redémarre PAS "
            f"tout de suite : ouvre un terminal et lance « sudo apt install linux-headers-{noyau} », "
            f"puis « sudo dkms autoinstall -k {noyau} ». " + secours)
        return False
    try:
        r = subprocess.run(["dkms", "autoinstall", "-k", noyau], capture_output=True,
                           text=True, timeout=DELAI_DKMS, env=ENV_APT, check=False)
        sortie_dkms = ((r.stdout or "") + (r.stderr or "")).strip()
        if sortie_dkms:
            journal(_extrait(sortie_dkms, 500, 2500))
        if r.returncode != 0:
            journal(f"!! dkms a échoué (code {r.returncode})")
    except FileNotFoundError:
        journal("!! dkms est introuvable")
        avertissements.append(
            f"Le module NVIDIA n'existe pas pour le noyau {noyau}, et dkms est introuvable : "
            "le pilote ne peut pas être recompilé. NE redémarre PAS tout de suite : lance "
            "« sudo apt install dkms » dans un terminal, puis « sudo dkms autoinstall -k "
            f"{noyau} ». " + secours)
        return False
    except subprocess.TimeoutExpired:
        duree = f"{DELAI_DKMS // 60} minutes" if DELAI_DKMS >= 60 else f"{DELAI_DKMS} s"
        journal(f"!! dkms n'a pas fini en {duree}")
        avertissements.append(
            f"La recompilation du module NVIDIA pour le noyau {noyau} n'a pas fini en {duree}. "
            f"NE redémarre PAS : lance « sudo dkms autoinstall -k {noyau} » dans un terminal et "
            "attends qu'il rende la main. " + secours)
        return False
    except OSError as exc:
        avertissements.append(f"dkms n'a pas pu être lancé ({exc}). NE redémarre PAS. " + secours)
        return False
    if module_nvidia_present(noyau):
        journal(f"  ✓ module NVIDIA présent pour le noyau {noyau}")
        return True
    derniere = next((l.strip() for l in reversed(sortie_dkms.splitlines()) if l.strip()), "")
    avertissements.append(
        f"Le module NVIDIA n'existe pas pour le noyau {noyau}"
        + (f" (dkms : « {derniere[:200]} »)" if derniere else "")
        + f". NE redémarre PAS tout de suite : lance « sudo dkms autoinstall -k {noyau} » dans un "
        "terminal pour voir l'erreur entière, ou demande de l'aide. " + secours)
    return False


def _reparer() -> None:
    """dpkg s'est arrêté en pleine transaction : finir ce qui peut l'être,
    SANS RIEN RETIRER. L'ancien repli « apt-get install -f -y » retirait,
    en root et sans question, tout paquet aux dépendances cassées."""
    journal("» Remise d'aplomb de dpkg (dpkg --configure -a, sans rien retirer)…")
    #  Pas de délai ici non plus : « dpkg --configure -a » relance le postinst
    #  DKMS de nvidia (une compilation), et le tuer au bout de 30 minutes
    #  laissait dpkg à moitié configuré une DEUXIÈME fois — la panne même
    #  qu'on répare.
    code, sortie = _outil(["dpkg", "--configure", "-a", "--force-confold"], delai=None)
    if sortie.strip():
        journal(_extrait(sortie, 500, 2500))
    code, sortie = apt(["install", "-f", "-y", "-q", "--no-remove",
                        "-o", "Dpkg::Options::=--force-confold"], delai=None)
    if sortie.strip():
        journal(_extrait(sortie, 500, 2500))
    if code != 0:
        journal(f"!! apt-get install -f --no-remove a échoué (code {code}) : rien n'a été retiré.")
    code, sortie = _outil(["dpkg", "--audit"], delai=120)
    if sortie.strip():
        journal("» Paquets laissés à moitié installés (dpkg --audit) :")
        journal(_extrait(sortie, 500, 2500))


def installer() -> None:
    if not rafraichir():
        fin({"ok": False, "message": "Impossible de rafraîchir les index apt (réseau ou verrou). "
                                     "Rien n'a été changé."}, 1)

    etat = paquets.etat_mises_a_jour()
    if not etat["disponible"]:
        journal(f"!! {etat['raison']}")
        fin({"ok": False, "message": f"Impossible de savoir quoi mettre à jour : {etat['raison']}. "
                                     "Rien n'a été changé."}, 1)
    plan = etat["plan"]
    if not plan:
        journal("  Tout est déjà à jour.")
        fin({"ok": True, "mis_a_jour": [], "redemarrer": False, "avertissements": [],
             "message": "Les pilotes graphiques sont déjà à jour."})

    journal(f"» {len(plan)} paquet(s) graphique(s) à mettre à jour :")
    for p in plan:
        journal(f"  · {p['paquet']}  {p['installe']} → {p['cible']}  ({p['source']})")
    demandes = [p["demande"] for p in plan]
    touche_nvidia = any(p["paquet"].startswith(("nvidia", "libnvidia")) for p in plan)

    #  1. LA SIMULATION : ce qu'apt ferait, au paquet près, sans rien toucher.
    journal("» Simulation (apt-get -s)…")
    sim = paquets.simuler(demandes)
    for ligne in sim["sortie"].splitlines():
        if ligne.startswith(("Inst ", "Remv ", "Purg ")):
            journal("  " + ligne)
    if sim["retraits"]:
        liste = ", ".join(sim["retraits"])
        journal(f"!! Cette mise à jour RETIRERAIT : {liste}")
        fin({"ok": False, "retraits": sim["retraits"],
             "message": f"Refusé : cette mise à jour retirerait {len(sim['retraits'])} paquet(s) "
                        f"({liste}). LexOS Pilotes ne retire jamais rien à ta place — rien n'a été "
                        "changé. Pour décider toi-même, lance dans un terminal « sudo apt install "
                        f"--only-upgrade {' '.join(demandes)} » : apt montre la liste et demande "
                        "confirmation."}, 1)
    if not sim["ok"]:
        journal(_extrait(sim["sortie"]))
        fin({"ok": False, "message": "apt refuse cette mise à jour (la simulation a échoué"
                                     + (f" : {sim['raison']}" if sim["raison"] else "")
                                     + ") — rien n'a été changé. Le journal est ci-dessus."}, 1)

    #  2. LA VRAIE COMMANDE. Pas de délai qui tue apt-get : un dpkg
    #  interrompu en pleine transaction, c'est exactement la panne qu'on
    #  veut éviter (ancien module retiré, nouveau pas construit).
    avant = etat_dpkg()
    journal("» Installation…")
    code, sortie = apt(paquets.commande_installation(demandes, "-y"), delai=None)
    journal(_extrait(sortie))
    apres = etat_dpkg()
    changes = differences(avant, apres) if avant is not None and apres is not None else None

    avertissements: list = []
    if code != 0:
        if changes == []:
            #  dpkg n'a rien touché (téléchargement en échec, résolution
            #  refusée) : CETTE fois, « rien n'a été changé » est prouvé.
            fin({"ok": False, "message": f"apt s'est arrêté (code {code}) avant de toucher au système "
                                         "— rien n'a été changé (état de dpkg identique avant et "
                                         "après). Le journal est ci-dessus."}, 1)
        journal("!! L'installation s'est arrêtée EN COURS DE ROUTE.")
        _reparer()
        apres = etat_dpkg()
        changes = differences(avant, apres) if avant is not None and apres is not None else None
        if touche_nvidia:
            verifier_module(avertissements)
        if changes is None:
            quoi = "impossible de savoir ce qui a été modifié (dpkg-query ne répond pas)"
        else:
            quoi = (f"{len(changes)} paquet(s) ont été modifiés avant l'arrêt : "
                    + ", ".join(f"{c['paquet']} {c['avant']} → {c['apres']}" for c in changes[:12])
                    + (" …" if len(changes) > 12 else ""))
        fin({"ok": False, "redemarrer": False, "avertissements": avertissements,
             "modifies": changes or [],
             "message": f"Installation INTERROMPUE (apt, code {code}) : {quoi}. NE redémarre PAS "
                        "avant d'avoir lu le journal ci-dessus ; demande de l'aide si un paquet "
                        "reste à moitié installé."}, 1)

    module_ok = True
    if touche_nvidia:
        module_ok = verifier_module(avertissements)
        avertissements.extend(_avertissement_secure_boot())

    nombre = len(changes) if changes else len(plan)
    if module_ok:
        message = f"{nombre} paquet(s) mis à jour. Redémarre pour utiliser le nouveau pilote."
    else:
        message = (f"{nombre} paquet(s) mis à jour, mais le pilote n'est PAS prêt pour le prochain "
                   "démarrage : NE redémarre PAS tout de suite (voir ci-dessous).")
    fin({"ok": True,
         "mis_a_jour": [{k: p[k] for k in ("paquet", "installe", "cible", "source")} for p in plan],
         "modifies": changes or [],
         "redemarrer": module_ok,
         "avertissements": avertissements,
         "message": message})


def _avertissement_secure_boot() -> list:
    try:
        r = subprocess.run(["mokutil", "--sb-state"], capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        return []
    if "enabled" in (r.stdout or "").lower():
        return ["Secure Boot est actif : si l'écran reste en basse résolution après le "
                "redémarrage, lance « sudo lexos-signer-pilote » pour faire accepter le module."]
    return []


def main() -> None:
    if os.geteuid() != 0:
        fin({"ok": False, "message": "Cette action doit être lancée par pkexec (root)."}, 2)
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "verifier":
        ok = rafraichir()
        fin({"ok": ok, "message": "Index à jour." if ok else "Impossible de rafraîchir les index apt."},
            0 if ok else 1)
    elif action == "installer":
        installer()
    else:
        fin({"ok": False, "message": "usage : lexos-pilotes-maj verifier|installer"}, 2)


if __name__ == "__main__":
    main()
