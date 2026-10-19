"""LexOS Pilotes — la partie qui écrit sur le système (lancée en root par pkexec).

Deux actions seulement, et aucune entrée venue de l'utilisateur :
    verifier   rafraîchit les index apt
    installer  rafraîchit, puis met à jour LES PAQUETS GRAPHIQUES (et eux seuls)

La liste des paquets ne vient pas de l'interface : elle est recalculée ICI,
en root, par paquets.py. Une page web ne peut donc rien faire installer
d'autre que ce que le filtre MOTIF_GRAPHIQUE laisse passer.

La dernière ligne de la sortie est « LEXOS-RESULTAT {json} » : c'est ce que
lit le serveur de l'interface. Tout ce qui précède est le journal lisible.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import paquets  # noqa: E402

ENV_APT = dict(os.environ, DEBIAN_FRONTEND="noninteractive", LC_ALL="C.UTF-8")
#  Le banc détourne cette racine vers un faux arbre de noyaux.
RACINE_MODULES = Path(os.environ.get("LEXOS_PILOTES_MODULES", "/lib/modules"))


def journal(texte: str) -> None:
    print(texte, flush=True)


def fin(resultat: dict, code: int = 0) -> None:
    print("LEXOS-RESULTAT " + json.dumps(resultat, ensure_ascii=False), flush=True)
    sys.exit(code)


def apt(arguments: list, delai: int) -> tuple:
    try:
        r = subprocess.run(["apt-get", *arguments], capture_output=True, text=True,
                           timeout=delai, env=ENV_APT, check=False)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, f"apt-get {' '.join(arguments[:1])} : délai de {delai} s dépassé"
    except OSError as exc:
        return 127, str(exc)


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


def installer() -> None:
    if not rafraichir():
        fin({"ok": False, "message": "Impossible de rafraîchir les index apt (réseau ou verrou)."}, 1)

    plan = paquets.plan_mises_a_jour()
    if not plan:
        journal("  Tout est déjà à jour.")
        fin({"ok": True, "mis_a_jour": [], "redemarrer": False, "avertissements": [],
             "message": "Les pilotes graphiques sont déjà à jour."})

    journal(f"» {len(plan)} paquet(s) graphique(s) à mettre à jour :")
    for p in plan:
        journal(f"  · {p['paquet']}  {p['installe']} → {p['cible']}  ({p['source']})")

    demandes = [p["demande"] for p in plan]
    journal("» Installation…")
    code, sortie = apt(["install", "-y", "-q", "--only-upgrade",
                        "-o", "Dpkg::Options::=--force-confold", *demandes], delai=1800)
    journal(sortie[-4000:])
    if code != 0:
        #  apt annule une transaction refusée ; on remet quand même dpkg
        #  d'aplomb si elle a été interrompue en cours de route.
        apt(["install", "-f", "-y", "-q"], delai=600)
        fin({"ok": False, "message": "apt a refusé la mise à jour — rien n'a été changé. Le journal est ci-dessus."}, 1)

    avertissements = []
    touche_nvidia = any(p["paquet"].startswith(("nvidia", "libnvidia")) for p in plan)
    if touche_nvidia:
        #  LA VÉRIFICATION QUI COMPTE : le noyau sur lequel la machine VA
        #  redémarrer a-t-il un nvidia.ko ? Sans lui, écran noir au prochain
        #  démarrage — la panne que LexOS traque depuis le build 29.
        noyau = noyau_le_plus_recent()
        if not module_nvidia_present(noyau):
            journal(f"» Module NVIDIA absent pour {noyau} — recompilation (dkms autoinstall)…")
            subprocess.run(["dkms", "autoinstall", "-k", noyau], capture_output=True,
                           text=True, timeout=1800, check=False)
        if module_nvidia_present(noyau):
            journal(f"  ✓ module NVIDIA présent pour le noyau {noyau}")
        else:
            avertissements.append(
                f"Le module NVIDIA n'existe pas pour le noyau {noyau}. NE redémarre PAS "
                "tout de suite : ouvre un terminal et lance « sudo dkms autoinstall », "
                "ou demande de l'aide. Au pire, choisis « Advanced options » dans GRUB "
                "et démarre sur l'ancien noyau.")
        avertissements.extend(_avertissement_secure_boot())

    fin({"ok": True,
         "mis_a_jour": [{k: p[k] for k in ("paquet", "installe", "cible", "source")} for p in plan],
         "redemarrer": True,
         "avertissements": avertissements,
         "message": f"{len(plan)} paquet(s) mis à jour. Redémarre pour utiliser le nouveau pilote."})


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
