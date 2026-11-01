#!/usr/bin/env python3
"""LexOS Jumelage — le téléphone aide à bien installer LexOS.

ALEX (2026-11-01) : « que l'APK soit capable de jumeler avec l'ISO, par
exemple un problème d'installation, pour le retrouver plus rapidement et
facilement » — « juste pour aider à installer l'ISO correctement ».

Le PC (la clé LexOS ou le système installé) sert un petit diagnostic sur le
réseau local ; le lanceur LexOS PRO du téléphone s'y jumelle avec le code
QR (ou l'adresse + le code à 6 chiffres) et affiche ce qui cloche, avec la
solution connue. Pratique surtout quand l'écran du PC fait défaut : c'est
justement là qu'on a besoin d'un autre écran.

SÉCURITÉ — CE QUI EST FAIT EXPRÈS :
  · LECTURE SEULE. Aucune route n'exécute quoi que ce soit venu du réseau :
    les commandes lancées sont écrites ici, en dur, et ne prennent aucun
    argument de la requête.
  · Rien sans le code secret : un jeton aléatoire, comparé en temps
    constant. Il change à chaque lancement.
  · Le serveur s'arrête tout seul après 2 heures (le temps d'une
    installation), ou à Ctrl+C.
  · Rien ne sort du réseau local : pas d'Internet, pas de service tiers.

Usage : lexos jumelage            (affiche le QR et attend le téléphone)
        python3 serveur.py --json (le diagnostic seul, pour déboguer)
"""
from __future__ import annotations

import argparse
import hmac
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 7870
DUREE_MAX = 2 * 3600


def _cmd(args: list[str], timeout: float = 6) -> str:
    """Une commande FIXE (jamais construite depuis la requête) ; "" si absente."""
    if not shutil.which(args[0]):
        return ""
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                              env={**os.environ, "LC_ALL": "C.UTF-8"}).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _lire(p: str) -> str:
    try:
        return Path(p).read_text("utf-8", errors="replace").strip()
    except OSError:
        return ""


# ─── Ce que le PC voit ──────────────────────────────────────────────────────
def cartes_graphiques() -> list[dict]:
    """Chaque carte graphique, et le pilote qui la tient (lspci -nnk)."""
    out, cur = [], None
    for ligne in _cmd(["lspci", "-nnk"]).splitlines():
        if not ligne.startswith(("\t", " ")):
            cur = None
            if re.search(r"VGA compatible|3D controller|Display controller", ligne):
                nom = ligne.split(": ", 1)[-1]
                cur = {"nom": nom[:120], "pilote": "", "nvidia": "NVIDIA" in nom.upper(),
                       "rtx50": bool(re.search(r"RTX\s*50\d0|GB20\d", nom, re.I))}
                out.append(cur)
        elif cur is not None and "Kernel driver in use:" in ligne:
            cur["pilote"] = ligne.split(":", 1)[1].strip()
    return out


def disques() -> list[dict]:
    try:
        j = json.loads(_cmd(["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,RM,TRAN,MODEL"]) or "{}")
    except ValueError:
        return []
    out = []
    for d in j.get("blockdevices", []):
        if d.get("type") != "disk" or str(d.get("name", "")).startswith(("loop", "zram", "sr")):
            continue
        parts = [{"nom": p.get("name"), "taille": int(p.get("size") or 0), "fs": p.get("fstype") or "",
                  "etiquette": p.get("label") or "", "monte": p.get("mountpoint") or ""}
                 for p in d.get("children") or []]
        out.append({"nom": d.get("name"), "modele": (d.get("model") or "").strip(), "taille": int(d.get("size") or 0),
                    "amovible": bool(d.get("rm")) or d.get("tran") == "usb", "partitions": parts})
    return out


def reseau() -> dict:
    ips = []
    try:
        for i in json.loads(_cmd(["ip", "-j", "addr"]) or "[]"):
            if i.get("ifname") == "lo":
                continue
            for a in i.get("addr_info", []):
                if a.get("family") == "inet":
                    ips.append({"interface": i["ifname"], "ip": a.get("local")})
    except ValueError:
        pass
    route = _cmd(["ip", "route", "show", "default"]).strip()
    return {"adresses": ips, "internet": bool(route)}


def erreurs_demarrage() -> list[str]:
    """Les dernières erreurs du démarrage en cours (journal système, niveau err)."""
    lignes = _cmd(["journalctl", "-b", "-p", "3", "-n", "25", "--no-pager", "-o", "cat"]).splitlines()
    if not lignes:
        lignes = [l for l in _cmd(["dmesg", "--level=err,crit,alert,emerg"]).splitlines()][-25:]
    return [l[:220] for l in lignes if l.strip()][-25:]


def diagnostic() -> dict:
    cmdline = _lire("/proc/cmdline")
    uefi = Path("/sys/firmware/efi").is_dir()
    sb = _cmd(["mokutil", "--sb-state"]).lower()
    modules = _lire("/proc/modules")
    gpus = cartes_graphiques()
    d = {
        "machine": {
            "nom": socket.gethostname(),
            "modele": (_lire("/sys/class/dmi/id/sys_vendor") + " " + _lire("/sys/class/dmi/id/product_name")).strip(),
            "lexos": _lire("/etc/lexos/version") or _lire("/etc/lexos-release"),
            "session_live": Path("/run/live/medium").exists() or "boot=live" in cmdline,
            "demarrage": "UEFI" if uefi else "BIOS (ancien mode)",
            "secure_boot": "activé" if "enabled" in sb else ("désactivé" if "disabled" in sb else "inconnu"),
            "nomodeset": "nomodeset" in cmdline,
            "noyau": os.uname().release,
            "memoire_go": round(int(re.search(r"MemTotal:\s+(\d+)", _lire("/proc/meminfo") or "MemTotal: 0").group(1)) / 1048576, 1),
        },
        "graphique": {"cartes": gpus, "nvidia_charge": bool(re.search(r"^nvidia ", modules, re.M)),
                      "nouveau_charge": bool(re.search(r"^nouveau ", modules, re.M))},
        "disques": disques(),
        "reseau": reseau(),
        "erreurs": erreurs_demarrage(),
    }
    d["conseils"] = conseils(d)
    return d


# ─── Les problèmes connus, et leur solution ─────────────────────────────────
#  Chacun vient d'un vrai pépin rencontré en installant LexOS. Le niveau :
#  « grave » bloque l'installation, « attention » peut la gâcher, « ok » rassure.
def conseils(d: dict) -> list[dict]:
    c = []
    m, g = d["machine"], d["graphique"]
    nvidia = [x for x in g["cartes"] if x["nvidia"]]
    if nvidia and not g["nvidia_charge"]:
        c.append({"niveau": "grave", "titre": "Pilote NVIDIA pas chargé",
                  "detail": "La carte " + nvidia[0]["nom"] + " tourne sans son pilote (pilote : "
                            + (nvidia[0]["pilote"] or "aucun") + "). C'est la cause de l'écran noir ou de la perte de signal.",
                  "solution": "Redémarre la clé ; au menu, appuie sur « e », ajoute nomodeset à la fin de la ligne « linux », puis Ctrl+X. "
                              "Si Secure Boot est activé, désactive-le dans le BIOS (F2) : il bloque le pilote NVIDIA."})
    if g["nouveau_charge"] and nvidia:
        c.append({"niveau": "grave", "titre": "Le pilote « nouveau » a pris la carte NVIDIA",
                  "detail": "nouveau ne gère pas les RTX 50xx : écran noir probable.",
                  "solution": "Utilise l'ISO Pro (pilote NVIDIA inclus) et démarre avec nomodeset le temps d'installer."})
    if nvidia and m["secure_boot"] == "activé":
        c.append({"niveau": "attention", "titre": "Secure Boot activé avec une carte NVIDIA",
                  "detail": "Le pilote NVIDIA n'est pas signé pour Secure Boot.",
                  "solution": "Dans le BIOS (F2 sur Alienware) : Secure Boot → Disabled, puis redémarre sur la clé."})
    if not d["reseau"]["adresses"]:
        c.append({"niveau": "attention", "titre": "Pas de réseau",
                  "detail": "Le PC n'a aucune adresse : le téléphone ne pourra plus le joindre s'il change de réseau.",
                  "solution": "Branche un câble Ethernet, ou connecte le Wi-Fi depuis l'icône réseau."})
    internes = [x for x in d["disques"] if not x["amovible"]]
    if not internes:
        c.append({"niveau": "grave", "titre": "Aucun disque interne vu",
                  "detail": "LexOS ne voit que des clés USB : rien où installer.",
                  "solution": "Dans le BIOS, mode du disque (SATA) : AHCI au lieu de RAID/Intel RST, puis redémarre."})
    for disque in internes:
        if any(p["fs"] in ("ntfs", "BitLocker") or "bitlocker" in p["fs"].lower() for p in disque["partitions"]):
            c.append({"niveau": "attention", "titre": "Windows est sur " + disque["nom"],
                      "detail": "Pour garder Windows, ne choisis JAMAIS « utiliser un disque entier ».",
                      "solution": "Dans l'installateur : « Assisté – utiliser le plus grand espace libre », ou partitionnement manuel "
                                  "dans l'espace non alloué. Fais d'abord de la place depuis Windows (Gestion des disques → Réduire le volume)."})
            break
    if m["demarrage"].startswith("BIOS"):
        c.append({"niveau": "attention", "titre": "Démarré en ancien mode BIOS",
                  "detail": "Si Windows est installé en UEFI, les deux ne se verront pas dans le menu de démarrage.",
                  "solution": "Redémarre (F12 sur Alienware) et choisis l'entrée « UEFI: » de la clé."})
    if m["memoire_go"] and m["memoire_go"] < 3.5:
        c.append({"niveau": "attention", "titre": f"Peu de mémoire ({m['memoire_go']} Go)",
                  "detail": "Le bureau complet peut être lent.", "solution": "LexOS Nomade (version légère) convient mieux."})
    if not [x for x in c if x["niveau"] == "grave"]:
        c.append({"niveau": "ok", "titre": "Rien de bloquant",
                  "detail": "Carte graphique, disques et démarrage ont l'air corrects pour installer.",
                  "solution": "Lance « Installer LexOS » depuis le bureau."})
    return c


# ─── Le serveur ─────────────────────────────────────────────────────────────
def fabriquer(jeton: str, code: str):
    #  Le code à 6 chiffres se devine en un million d'essais : après 15 ratés,
    #  il ne marche PLUS (le jeton du QR, lui, reste bon). Compté pour tous
    #  les fils ensemble — des essais en parallèle ne contournent rien.
    rates = {"n": 0}
    verrou = threading.Lock()

    class G(BaseHTTPRequestHandler):
        server_version = "LexOS-Jumelage"

        def log_message(self, *a):
            pass

        def _ok(self) -> bool:
            q = parse_qs(urlparse(self.path).query)
            donne = (self.headers.get("X-Jeton") or (q.get("t") or [""])[0])[:128]
            if hmac.compare_digest(donne, jeton):
                return True
            with verrou:
                if rates["n"] < 15 and hmac.compare_digest(donne, code):
                    return True
                rates["n"] += 1
            return False

        def _json(self, obj, statut=200):
            corps = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(statut)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(corps)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(corps)

        def do_GET(self):  # noqa: N802
            chemin = urlparse(self.path).path
            if chemin == "/api/bonjour":
                #  Seule route sans code : de quoi reconnaître un PC LexOS, rien de plus.
                return self._json({"lexos": True, "nom": socket.gethostname()})
            if not self._ok():
                time.sleep(0.5)   # freine qui essaierait tous les codes à 6 chiffres
                return self._json({"erreur": "code"}, 403)
            if chemin == "/api/diagnostic":
                return self._json(diagnostic())
            return self._json({"erreur": "inconnu"}, 404)
    return G


def adresse_locale() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))   # aucun paquet n'est envoyé : ça choisit juste l'interface
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def main() -> int:
    a = argparse.ArgumentParser(description="LexOS Jumelage — le téléphone aide à installer LexOS")
    a.add_argument("--json", action="store_true", help="afficher le diagnostic et quitter")
    a.add_argument("--port", type=int, default=PORT)
    args = a.parse_args()
    if args.json:
        print(json.dumps(diagnostic(), ensure_ascii=False, indent=2))
        return 0
    jeton = secrets.token_urlsafe(18)
    code = f"{secrets.randbelow(10**6):06d}"
    try:
        srv = ThreadingHTTPServer(("0.0.0.0", args.port), fabriquer(jeton, code))
    except OSError as e:
        print(f"Port {args.port} occupé ({e}). Un jumelage roule peut-être déjà.", file=sys.stderr)
        return 1
    ip = adresse_locale()
    lien = f"lexos://jumeler?h={ip}&p={args.port}&t={jeton}"
    O, R, B = "\033[38;5;208m", "\033[0m", "\033[1m"
    print(f"\n{O}{B}  LexOS — jumeler ton téléphone{R}\n")
    print("  Dans le lanceur LexOS PRO : ⚙ Paramètres → « Aide à l'installation » → Scanner.\n")
    if shutil.which("qrencode"):
        subprocess.run(["qrencode", "-t", "ANSIUTF8", "-m", "2", lien])
    print(f"  Ou tape à la main :   adresse {B}{ip}{R}   code {O}{B}{code[:3]} {code[3:]}{R}\n")
    print("  Lecture seule : le téléphone voit le diagnostic, il ne contrôle rien.")
    print("  S'arrête tout seul dans 2 heures — ou Ctrl+C.\n")
    minuterie = threading.Timer(DUREE_MAX, srv.shutdown)
    minuterie.daemon = True
    minuterie.start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
