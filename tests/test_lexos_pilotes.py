#!/usr/bin/env python3
"""Banc de LexOS Pilotes — l'appli des mises à jour de la carte graphique.

Ce qu'on éprouve, sans apt ni carte graphique réelle :
  · le filtre : seuls les paquets graphiques passent ;
  · la lecture d'« apt-cache policy », y compris le dépôt NVIDIA « plat » ;
  · le plan : un paquet installé depuis backports est redemandé à backports
    (sinon apt le laisserait figé), l'épingle NVIDIA n'est jamais contournée ;
  · « on ne sait pas » n'est jamais « à jour » (pas d'index, apt-cache en
    échec), et chaque mesure absente a sa raison ;
  · L'AIDE ROOT POUR DE VRAI : maj.installer() tourne, avec de faux apt-get,
    apt-cache, dpkg, dpkg-query et dkms qui jouent une machine. On lit
    l'argv exact d'apt, ce qu'elle refuse (un retrait), ce qu'elle dit
    quand dpkg s'arrête en route, et la vérification de nvidia.ko ;
  · LE SERVEUR POUR DE VRAI : serveur._lancer() lance un faux pkexec, dont
    on lit l'argv ; l'API refuse ce qui n'a pas le jeton de la session, et
    ACCEPTE la page légitime ;
  · le lanceur ne rouvre que NOTRE serveur, jamais un squatteur du port ;
  · LE JETON NE SORT JAMAIS PAR UN ARGV NI UN ENVIRONNEMENT : le vrai
    lanceur et le vrai serveur tournent, un faux navigateur suit la page
    d'ouverture, et un espion relit /proc/*/cmdline et /proc/*/environ
    pendant toute leur vie (classe Fuite) ;
  · la règle polkit : « installer » redemande le mot de passe à chaque fois ;
  · la page (app.js sous node) : « Indisponible » + raison, boutons
    désactivés avec leur raison, reprise d'une tâche déjà en cours.

JAMAIS LE VRAI PKEXEC. Le banc remplace le PATH par un dossier de faux
outils (plus un « sort » réel) et REFUSE DE TOURNER si « pkexec », « apt-get »
ou « dkms » se résolvent ailleurs. Avant, un garde-fou qui régressait
laissait passer un POST jusqu'au vrai « pkexec /usr/bin/lexos-pilotes-maj
installer » de la machine qui faisait tourner le banc.

Lancer avec /usr/bin/python3 (celui du conteneur de travail, en
/usr/local/bin, plante à la fermeture).
"""
import base64
import hashlib
import hmac
import http.client
import http.server
import importlib
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import xml.etree.ElementTree as ET
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

#  Pas de __pycache__ dans config/includes.chroot : il partirait dans l'ISO
#  (même raison que l'étape « Syntaxe Python des rouages internes » de la CI).
sys.dont_write_bytecode = True

R = Path(__file__).resolve().parents[1]
DOSSIER = R / "config/includes.chroot/usr/lib/lexos/pilotes"
POLITIQUE_POLKIT = R / "config/includes.chroot/usr/share/polkit-1/actions/org.lexos.pilotes.policy"
LANCEUR = R / "config/includes.chroot/usr/bin/lexos-pilotes"
APP_JS = DOSSIER / "web/app.js"

#  ═══ DES NOMS DE MODULES QUI NE DÉBORDENT PAS ═══
#  LexOS Diagnostic a AUSSI un moteur.py et un serveur.py. Lancés dans le
#  même interpréteur (« python3 -m unittest tests.test_lexos_diagnostic
#  tests.test_lexos_pilotes »), le premier chargé restait dans sys.modules et
#  l'autre banc testait le mauvais code (AttributeError: module 'moteur' has
#  no attribute 'lire_cartes'). On importe donc les nôtres, on garde les
#  objets, puis on rend sys.modules et sys.path tels qu'on les a trouvés.
_NOMS = ("paquets", "moteur", "serveur", "maj")
_deja_la = {n: sys.modules.pop(n) for n in _NOMS if n in sys.modules}
sys.path.insert(0, str(DOSSIER))
try:
    paquets = importlib.import_module("paquets")
    moteur = importlib.import_module("moteur")
    serveur = importlib.import_module("serveur")
    maj = importlib.import_module("maj")
finally:
    sys.path[:] = [p for p in sys.path if p != str(DOSSIER)]
    for _n in _NOMS:
        sys.modules.pop(_n, None)
    sys.modules.update(_deja_la)

#  L'interpréteur des faux outils et de l'aide root : /usr/bin/python3 si
#  possible (règle du dépôt), sinon celui du banc.
PY = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else sys.executable

POLITIQUE = """\
libgl1-mesa-dri:
  Installed: 25.0.7-2~bpo13+1
  Candidate: 25.0.7-2
  Version table:
     25.2.4-1~bpo13+1 100
        100 http://deb.debian.org/debian trixie-backports/main amd64 Packages
 *** 25.0.7-2~bpo13+1 100
        100 http://deb.debian.org/debian trixie-backports/main amd64 Packages
        100 /var/lib/dpkg/status
     25.0.7-2 500
        500 http://deb.debian.org/debian trixie/main amd64 Packages
nvidia-driver-cuda:
  Installed: 595.71.05-1
  Candidate: 595.91.07-1
  Version table:
     610.57.04-1 500
        500 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
     595.91.07-1 1001
       1001 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
 *** 595.71.05-1 1001
       1001 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
        100 /var/lib/dpkg/status
firmware-misc-nonfree:
  Installed: 20250410-2
  Candidate: 20250410-2
  Version table:
 *** 20250410-2 500
        500 http://deb.debian.org/debian trixie/non-free-firmware amd64 Packages
        100 /var/lib/dpkg/status
"""

POLITIQUE_A_JOUR = """\
libgl1-mesa-dri:
  Installed: 25.2.4-1~bpo13+1
  Candidate: 25.0.7-2
  Version table:
 *** 25.2.4-1~bpo13+1 100
        100 http://deb.debian.org/debian trixie-backports/main amd64 Packages
        100 /var/lib/dpkg/status
     25.0.7-2 500
        500 http://deb.debian.org/debian trixie/main amd64 Packages
"""

LSPCI = """\
00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 520 [8086:1916] (rev 07)
\tSubsystem: Lenovo ThinkPad T460 [17aa:2233]
\tKernel driver in use: i915
\tKernel modules: i915
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GB206 [GeForce RTX 5060] [10de:2d05] (rev a1)
\tKernel driver in use: nvidia
02:00.0 Ethernet controller [0200]: Realtek RTL8111 [10ec:8168]
\tKernel driver in use: r8169
"""

#  La machine décrite par défaut : Mesa venue de backports (amd64 ET i386,
#  comme LexOS Pro pour Steam), le pilote NVIDIA, un micrologiciel à jour,
#  et un paquet NON graphique qui ne doit jamais être demandé.
DPKG_DEFAUT = {
    "libgl1-mesa-dri:amd64": ["25.0.7-2~bpo13+1", "ii"],
    "libgl1-mesa-dri:i386": ["25.0.7-2~bpo13+1", "ii"],
    "nvidia-driver-cuda": ["595.71.05-1", "ii"],
    "firmware-misc-nonfree": ["20250410-2", "ii"],
    "firefox-esr": ["128.3.0esr-1", "ii"],
    "monappli": ["1.0", "ii"],
}
SIMULATION_SANS_RETRAIT = (
    "Inst libgl1-mesa-dri [25.0.7-2~bpo13+1] (25.2.4-1~bpo13+1 Debian Backports:trixie-backports [amd64])\n"
    "Inst nvidia-driver-cuda [595.71.05-1] (595.91.07-1 cuda [amd64])\n")
TRANSACTION_REUSSIE = {"changer": {"libgl1-mesa-dri:amd64": ["25.2.4-1~bpo13+1", "ii"],
                                   "libgl1-mesa-dri:i386": ["25.2.4-1~bpo13+1", "ii"],
                                   "nvidia-driver-cuda": ["595.91.07-1", "ii"]},
                       "sortie": "Setting up nvidia-driver-cuda (595.91.07-1) ...\n", "code": 0}
NOYAU_EN_SERVICE_FICTIF = "6.9.12+deb13-amd64"   # a son nvidia.ko
NOYAU_PROCHAIN = "6.16.12+bpo-amd64"             # « 6.9 » > « 6.16 » en ordre alphabétique : piège voulu

#  ═══ LES FAUX OUTILS ═══
#  Un seul programme, écrit sous chaque nom. Ils lisent la machine décrite
#  dans $BANC_DIR (scenario.json, dpkg.json) et notent chaque appel. Le faux
#  pkexec NE LANCE RIEN : il note son argv et rend ce qu'on lui dit.
CODE_FAUX = r'''
import atexit, json, os, sys, time
from pathlib import Path
B = Path(os.environ["BANC_DIR"])
args = sys.argv[1:]
def lire(nom, defaut):
    try:
        return json.loads((B / nom).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return defaut
S = lire("scenario.json", {})
def etat():
    return lire("dpkg.json", {})
def ecrire(e):
    (B / "dpkg.json").write_text(json.dumps(e), encoding="utf-8")
#  Chaque faux note son argv ET son environnement : la preuve, sans course,
#  qu'aucun enfant du serveur ne porte le jeton (classe Fuite). « vivre » le
#  garde en vie un moment, comme un vrai navigateur ou une vraie fenêtre
#  polkit, pour que l'espion de /proc le voie aussi.
with open(B / "enfants.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"nom": NOM, "argv": sys.argv, "env": dict(os.environ)}) + "\n")
atexit.register(time.sleep, S.get("vivre", {}).get(NOM, 0))
if NOM == "xdg-open":
    #  Le faux navigateur. « suivre » : il fait ce que ferait Chromium avec
    #  la page d'ouverture, puis ce que fait app.js (échanger le ticket).
    note = {"argv": args}
    if S.get("navigateur") == "suivre" and args and args[0].startswith("file://"):
        import http.client, re
        from urllib.parse import unquote, urlparse
        page = Path(unquote(urlparse(args[0]).path))
        s, sd = page.stat(), page.parent.stat()
        note.update(page=str(page), mode=s.st_mode & 0o777, uid=s.st_uid,
                    mode_dossier=sd.st_mode & 0o777, uid_dossier=sd.st_uid)
        m = re.search(r'location\.replace\("http://127\.0\.0\.1:(\d+)/#o=([^"]+)"\)',
                      page.read_text(encoding="utf-8"))
        if m:
            port, ticket = int(m.group(1)), m.group(2)
            note["ticket"] = ticket
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            o = f"http://127.0.0.1:{port}"
            c.request("POST", "/api/entree", headers={"Origin": o, "X-LexOS": "1", "X-Ticket": ticket})
            r = c.getresponse()
            corps = r.read()
            note["entree"] = r.status
            note["jeton"] = json.loads(corps).get("jeton", "") if r.status == 200 else ""
            note["page_apres"] = page.exists()
            c.request("GET", "/api/etat", headers={"Origin": o, "X-Jeton": note["jeton"]})
            r = c.getresponse()
            r.read()
            note["etat"] = r.status
    with open(B / "navigateur.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(note) + "\n")
    sys.exit(0)
if NOM == "pkexec":
    with open(B / "pkexec.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(args) + "\n")
    P = lire("pkexec.json", {})
    if P.get("attendre"):
        limite = time.time() + 10
        while not os.path.exists(P["attendre"]) and time.time() < limite:
            time.sleep(0.05)
    sys.stdout.write(P.get("sortie", ""))
    sys.stdout.flush()
    sys.exit(P.get("code", 0))
with open(B / "appels.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps([NOM, *args]) + "\n")
if NOM == "dpkg-query":
    if S.get("dpkg_query_code"):
        print("dpkg-query: erreur simulée", file=sys.stderr)
        sys.exit(S["dpkg_query_code"])
    fmt, noms, i = "${binary:Package}\t${Version}\n", [], 0
    while i < len(args):
        if args[i] == "-f":
            fmt = args[i + 1]
            i += 2
            continue
        if not args[i].startswith("-"):
            noms.append(args[i])
        i += 1
    e, sortie, vus = etat(), [], set()
    for cle in sorted(e):
        base = cle.split(":")[0]
        if noms and not any(n in (cle, base) for n in noms):
            continue
        vus.update(n for n in noms if n in (cle, base))
        v, st = e[cle]
        sortie.append(fmt.replace("${binary:Package}", cle).replace("${Package}", base)
                      .replace("${Version}", v).replace("${db:Status-Abbrev}", st + " "))
    sys.stdout.write("".join(sortie))
    manquants = [n for n in noms if n not in vus]
    for n in manquants:
        print(f"dpkg-query: no packages found matching {n}", file=sys.stderr)
    sys.exit(1 if manquants else 0)
if NOM == "apt-cache":
    if S.get("apt_cache_code"):
        print("E: Could not open lock file (simulé)", file=sys.stderr)
        sys.exit(S["apt_cache_code"])
    sys.stdout.write(S.get("politique", ""))
    sys.exit(0)
if NOM == "apt-get":
    if "update" in args:
        if S.get("update_code"):
            print("E: Could not get lock /var/lib/apt/lists/lock (simulé)", file=sys.stderr)
            sys.exit(S["update_code"])
        listes = Path(os.environ["LEXOS_PILOTES_LISTES_APT"])
        listes.mkdir(parents=True, exist_ok=True)
        (listes / "deb.debian.org_debian_dists_trixie_main_binary-amd64_Packages").write_text("")
        sys.exit(0)
    if "-s" in args:
        print("NOTE: This is only a simulation!")
        sys.stdout.write(S.get("simulation", ""))
        sys.exit(S.get("simulation_code", 0))
    if "-f" in args:
        if "--no-remove" not in args and S.get("f_retirer"):
            e = etat()
            for n in S["f_retirer"]:
                e.pop(n, None)
            ecrire(e)
        sys.exit(0)
    if "-y" in args:
        T = S.get("transaction", {})
        retirer = T.get("retirer", [])
        if retirer and "--no-remove" in args:
            print("E: Packages need to be removed but remove is disabled.", file=sys.stderr)
            sys.exit(100)
        e = etat()
        for n in retirer:
            e.pop(n, None)
        for n, ve in T.get("changer", {}).items():
            e[n] = ve
        ecrire(e)
        sys.stdout.write(T.get("sortie", ""))
        sys.exit(T.get("code", 0))
    sys.exit(0)
if NOM == "dpkg":
    if "--compare-versions" in args:
        os.execv(os.environ["BANC_VRAI_DPKG"], ["dpkg", *args])
    if "--audit" in args:
        for n, (v, st) in sorted(etat().items()):
            if not st.startswith("ii"):
                print(f" {n}  {v}  {st}")
        sys.exit(0)
    if "--configure" in args:
        sys.exit(S.get("configure_code", 0))
    sys.exit(0)
if NOM == "dkms":
    mode = S.get("dkms", "construit")
    if mode == "lent":
        time.sleep(30)
    if mode == "construit" and "-k" in args:
        k = args[args.index("-k") + 1]
        d = Path(os.environ["LEXOS_PILOTES_MODULES"]) / k / "updates" / "dkms"
        d.mkdir(parents=True, exist_ok=True)
        (d / "nvidia.ko.xz").write_text("")
        print(f"nvidia/595.91.07, {k}, x86_64: installed")
        sys.exit(0)
    print("Error! Bad return status for module build on kernel (simulé)")
    sys.exit(10)
if NOM == "mokutil":
    if "--sb-state" in args:
        print(S.get("sb", "SecureBoot disabled"))
        sys.exit(0)
    print("lexos-mok.der is not enrolled")
    sys.exit(0)
if NOM == "lspci":
    sys.stdout.write(S.get("lspci", ""))
    sys.exit(0)
sys.exit(0)
'''

FAUX_OUTILS = ("pkexec", "apt-get", "apt-cache", "dpkg", "dpkg-query", "dkms", "mokutil", "lspci",
               "x-terminal-emulator", "xdg-open")
#  Ceux qui ne doivent JAMAIS se résoudre hors du dossier des faux.
DANGEREUX = ("pkexec", "apt-get", "apt", "dpkg", "dkms", "sudo", "x-terminal-emulator")

BANC = Path()
FAUX = Path()
_avant: dict = {}
NODE = None


def _garde_faux_outils() -> None:
    """Le banc refuse de tourner si un outil dangereux est le vrai."""
    for outil in DANGEREUX:
        chemin = shutil.which(outil)
        if chemin is not None and Path(chemin).parent != FAUX:
            raise RuntimeError(f"REFUS : « {outil} » se résout en {chemin}, pas dans le dossier des faux "
                               f"outils ({FAUX}). Le banc ne lancera jamais un vrai {outil}.")
    if shutil.which("pkexec") != str(FAUX / "pkexec"):
        raise RuntimeError("REFUS : le faux pkexec n'est pas celui du PATH.")


def setUpModule():
    global BANC, FAUX, NODE
    NODE = shutil.which("node")
    vrai_dpkg = shutil.which("dpkg")
    vrai_sort = shutil.which("sort")
    if not vrai_dpkg or not vrai_sort:
        raise RuntimeError("dpkg et sort réels requis : le banc compare des versions Debian (dpkg "
                           "--compare-versions) et trie les noyaux (sort -V).")
    BANC = Path(tempfile.mkdtemp(prefix="banc-pilotes-"))
    FAUX = BANC / "faux"
    outils = BANC / "outils"
    FAUX.mkdir()
    outils.mkdir()
    for nom in FAUX_OUTILS:
        (FAUX / nom).write_text(f"#!{PY}\nNOM = {nom!r}\n{CODE_FAUX}", encoding="utf-8")
        (FAUX / nom).chmod(0o755)
    (outils / "sort").symlink_to(vrai_sort)
    #  Le vrai lanceur fait « exec python3 serveur.py » (classe Fuite).
    (outils / "python3").symlink_to(PY)
    _avant.update(PATH=os.environ.get("PATH"), BANC_DIR=os.environ.get("BANC_DIR"),
                  BANC_VRAI_DPKG=os.environ.get("BANC_VRAI_DPKG"),
                  XDG_RUNTIME_DIR=os.environ.get("XDG_RUNTIME_DIR"),
                  LEXOS_PILOTES_LISTES_APT=os.environ.get("LEXOS_PILOTES_LISTES_APT"),
                  LEXOS_PILOTES_MODULES=os.environ.get("LEXOS_PILOTES_MODULES"),
                  attributs=(paquets.LISTES_APT, paquets.FICHIER_EPINGLE, moteur.RACINE_MODULES, moteur.EFI))
    #  PAS de /usr/bin ni /bin : seulement les faux, et un vrai « sort ».
    os.environ["PATH"] = f"{FAUX}:{outils}"
    os.environ["BANC_DIR"] = str(BANC)
    os.environ["BANC_VRAI_DPKG"] = vrai_dpkg
    os.environ["XDG_RUNTIME_DIR"] = str(BANC / "run")
    (BANC / "run").mkdir(mode=0o700)
    try:
        _garde_faux_outils()
    except RuntimeError:
        #  unittest n'appelle pas tearDownModule si setUpModule échoue.
        tearDownModule()
        raise


def tearDownModule():
    for cle, valeur in _avant.items():
        if cle == "attributs":
            paquets.LISTES_APT, paquets.FICHIER_EPINGLE, moteur.RACINE_MODULES, moteur.EFI = valeur
        elif valeur is None:
            os.environ.pop(cle, None)
        else:
            os.environ[cle] = valeur
    shutil.rmtree(BANC, ignore_errors=True)


def preparer_machine(scenario: dict, dpkg: dict = None, noyaux: tuple = (), entetes: tuple = (),
                     listes: bool = True) -> Path:
    """Écrit la machine décrite dans BANC : état dpkg, scénario, noyaux, index apt."""
    for f in ("appels.jsonl", "pkexec.jsonl", "pkexec.json", "enfants.jsonl", "navigateur.jsonl", "delais.jsonl"):
        (BANC / f).unlink(missing_ok=True)
    (BANC / "scenario.json").write_text(json.dumps(scenario), encoding="utf-8")
    (BANC / "dpkg.json").write_text(json.dumps(DPKG_DEFAUT if dpkg is None else dpkg), encoding="utf-8")
    modules = BANC / "modules"
    shutil.rmtree(modules, ignore_errors=True)
    modules.mkdir()
    for k, avec_module in noyaux:
        (modules / k).mkdir()
        if avec_module:
            (modules / k / "updates/dkms").mkdir(parents=True)
            (modules / k / "updates/dkms/nvidia.ko.xz").write_text("")
    for k in entetes:
        (modules / k / "build").mkdir(parents=True, exist_ok=True)
    lst = BANC / "listes"
    shutil.rmtree(lst, ignore_errors=True)
    lst.mkdir()
    (lst / "partial").mkdir()
    if listes:
        (lst / "deb.debian.org_debian_dists_trixie_main_binary-amd64_Packages").write_text("")
    os.environ["LEXOS_PILOTES_LISTES_APT"] = str(lst)
    os.environ["LEXOS_PILOTES_MODULES"] = str(modules)
    paquets.LISTES_APT = lst
    paquets.FICHIER_EPINGLE = str(BANC / "pas-d-epingle")
    moteur.RACINE_MODULES = modules
    return modules


def appels(outil: str = None) -> list:
    try:
        lignes = (BANC / "appels.jsonl").read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    tous = [json.loads(l) for l in lignes]
    return [a[1:] for a in tous if outil is None or a[0] == outil]


def appels_pkexec() -> list:
    try:
        return [json.loads(l) for l in (BANC / "pkexec.jsonl").read_text(encoding="utf-8").splitlines()]
    except FileNotFoundError:
        return []


#  Note le délai de CHAQUE subprocess.run de l'aide root (outil, argv, délai).
#  Au niveau de subprocess, pas de maj.apt : un appel direct avec timeout=1800
#  ne passerait pas entre les mailles.
PRELUDE_DELAIS = r'''
import subprocess as _sp
_vrai_run = _sp.run
def _run(cmd, *a, **k):
    with open(os.path.join(os.environ["BANC_DIR"], "delais.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps([list(cmd), k.get("timeout")]) + "\n")
    return _vrai_run(cmd, *a, **k)
_sp.run = _run
'''


def lancer_aide(argv: list = None, prelude: str = "") -> tuple:
    """maj.installer() POUR DE VRAI, dans un processus à part (il sort par
    sys.exit), avec le PATH des faux outils. Rend (code, sortie, résultat).
    Avec argv : maj.main() tel que pkexec le lancerait (euid 0 simulé).
    Le prélude tourne après « import maj » (un délai raccourci, un outil noté)."""
    debut = f"import os, sys, json; sys.path.insert(0, {str(DOSSIER)!r}); import maj\n{prelude}\n"
    if argv is None:
        prog = debut + "maj.installer()"
    else:
        prog = (f"import os; os.geteuid = lambda: 0\n{debut}"
                f"sys.argv = {['maj.py', *argv]!r}\nmaj.main()")
    r = subprocess.run([PY, "-I", "-B", "-c", prog], capture_output=True, text=True, timeout=120,
                       env=dict(os.environ))
    lignes = [l for l in r.stdout.splitlines() if l.startswith("LEXOS-RESULTAT ")]
    resultat = json.loads(lignes[-1][len("LEXOS-RESULTAT "):]) if lignes else None
    return r.returncode, r.stdout + r.stderr, resultat


class Filtre(unittest.TestCase):
    def test_ne_garde_que_le_graphique(self):
        dpkg = "\n".join([
            "ii nvidia-driver-cuda", "ii libnvidia-ml1:amd64", "ii libgl1-mesa-dri:i386",
            "ii firmware-amd-graphics", "ii mesa-vulkan-drivers", "ii xserver-xorg-video-nvidia",
            "ii firefox-esr", "ii sudo", "ii linux-image-amd64", "ii openssh-server",
            "rc nvidia-old-thing",
        ])
        noms = paquets.paquets_graphiques_installes(dpkg)
        self.assertIn("nvidia-driver-cuda", noms)
        self.assertIn("libgl1-mesa-dri:i386", noms)
        self.assertIn("firmware-amd-graphics", noms)
        for interdit in ("firefox-esr", "sudo", "linux-image-amd64", "openssh-server", "nvidia-old-thing"):
            self.assertNotIn(interdit, noms)


class Plan(unittest.TestCase):
    def setUp(self):
        self.pol = paquets.lire_politique(POLITIQUE)

    def test_lecture(self):
        mesa = self.pol["libgl1-mesa-dri"]
        self.assertEqual(mesa["installe"], "25.0.7-2~bpo13+1")
        self.assertEqual(mesa["candidat"], "25.0.7-2")
        self.assertEqual(len(mesa["versions"]), 3)
        nv = self.pol["nvidia-driver-cuda"]
        self.assertIn("developer.download.nvidia.com", nv["versions"][0][1])

    def test_backports_reste_sur_backports(self):
        plan = {p["paquet"]: p for p in paquets.planifier(self.pol)}
        mesa = plan["libgl1-mesa-dri"]
        self.assertEqual(mesa["cible"], "25.2.4-1~bpo13+1")
        self.assertEqual(mesa["demande"], "libgl1-mesa-dri/trixie-backports")

    def test_epingle_nvidia_respectee(self):
        plan = {p["paquet"]: p for p in paquets.planifier(self.pol)}
        nv = plan["nvidia-driver-cuda"]
        #  La 610 existe, mais le candidat d'apt (épingle 1001) est la 595.91.
        self.assertEqual(nv["cible"], "595.91.07-1")
        self.assertEqual(nv["demande"], "nvidia-driver-cuda")

    def test_rien_si_a_jour(self):
        plan = {p["paquet"] for p in paquets.planifier(self.pol)}
        self.assertNotIn("firmware-misc-nonfree", plan)

    def test_branche(self):
        epingle = "Package: nvidia-* libnvidia-*\nPin: version 595.*\nPin-Priority: 1001\n"
        self.assertEqual(paquets.branche_epinglee(epingle), "595")
        self.assertIsNone(paquets.branche_epinglee("rien"))
        self.assertEqual(paquets.branche_plus_recente(self.pol["nvidia-driver-cuda"]), "610.57.04-1")


class Simulation(unittest.TestCase):
    """Ce qu'on simule est ce qu'on installe, et la vraie commande ne retire rien."""

    def test_lire_simulation(self):
        lu = paquets.lire_simulation("NOTE: x\nRemv monappli [1.0]\nPurg autre:i386 [2]\n"
                                     "Inst libgl1-mesa-dri [1.0] (2.0 x [amd64])\nConf libgl1-mesa-dri (2.0)\n")
        self.assertEqual(lu["retraits"], ["autre:i386", "monappli"])
        self.assertEqual(lu["installations"], ["libgl1-mesa-dri"])

    def test_commande(self):
        vraie = paquets.commande_installation(["a", "b/trixie-backports"], "-y")
        self.assertEqual(vraie, ["install", "-y", "-q", "--only-upgrade", "--no-remove",
                                 "-o", "Dpkg::Options::=--force-confold", "a", "b/trixie-backports"])
        simulee = paquets.commande_installation(["a"], "-s")
        self.assertEqual(simulee[:2], ["install", "-s"])
        #  Sans --no-remove, la simulation LISTE les retraits au lieu d'échouer.
        self.assertNotIn("--no-remove", simulee)


class Cartes(unittest.TestCase):
    def test_lspci(self):
        cartes = moteur.lire_cartes(LSPCI)
        self.assertEqual(len(cartes), 2)
        self.assertEqual(cartes[0]["marque"], "Intel")
        self.assertEqual(cartes[0]["pilote"], "i915")
        self.assertEqual(cartes[1]["marque"], "NVIDIA")
        self.assertEqual(cartes[1]["nom"], "NVIDIA Corporation GB206 [GeForce RTX 5060]")
        self.assertEqual(cartes[1]["pilote"], "nvidia")


class Mesures(unittest.TestCase):
    """« Indisponible » + raison, jamais une valeur inventée."""

    def setUp(self):
        preparer_machine({"politique": POLITIQUE, "simulation": SIMULATION_SANS_RETRAIT, "lspci": LSPCI},
                         noyaux=((NOYAU_EN_SERVICE_FICTIF, True), (NOYAU_PROCHAIN, False)))
        moteur.EFI = BANC / "efi"
        (BANC / "efi").mkdir(exist_ok=True)

    def test_mesa_deux_architectures_pas_collees(self):
        #  amd64 et i386 à la même version : UNE version, pas les deux bout à bout.
        self.assertEqual(moteur.version_paquet("libgl1-mesa-dri"), ("25.0.7-2~bpo13+1", None))

    def test_mesa_architectures_divergentes_montrees(self):
        d = dict(DPKG_DEFAUT, **{"libgl1-mesa-dri:i386": ["25.0.7-2", "ii"]})
        (BANC / "dpkg.json").write_text(json.dumps(d), encoding="utf-8")
        v, raison = moteur.version_paquet("libgl1-mesa-dri")
        self.assertIsNone(raison)
        self.assertEqual(v, "25.0.7-2 (i386) · 25.0.7-2~bpo13+1 (amd64)")

    def test_paquet_absent_ou_inconnu(self):
        self.assertEqual(moteur.version_paquet("nvidia-driver"), (None, None))
        (BANC / "scenario.json").write_text(json.dumps({"dpkg_query_code": 2}), encoding="utf-8")
        v, raison = moteur.version_paquet("libgl1-mesa-dri")
        self.assertIsNone(v)
        self.assertIn("dpkg-query a échoué", raison)

    def test_instantane_complet(self):
        e = moteur.instantane()
        self.assertEqual(e["mesa"], "25.0.7-2~bpo13+1")
        self.assertEqual(e["nvidia"]["paquet"], "595.71.05-1")
        self.assertEqual(e["noyau"]["plus_recent"], NOYAU_PROCHAIN)
        self.assertIs(e["noyau"]["module_nvidia_plus_recent"], False)
        self.assertIs(e["secure_boot"], False)
        m = e["mises_a_jour"]
        self.assertTrue(m["disponible"])
        self.assertEqual([p["paquet"] for p in m["paquets"]], ["libgl1-mesa-dri", "nvidia-driver-cuda"])
        self.assertEqual(m["retraits"], [])
        self.assertEqual(e["raisons"], {})

    def test_chaque_mesure_absente_a_sa_raison(self):
        #  Pas de mokutil (machine UEFI), /lib/modules illisible, lspci absent.
        (FAUX / "mokutil").rename(BANC / "mokutil.de-cote")
        (FAUX / "lspci").rename(BANC / "lspci.de-cote")
        moteur.RACINE_MODULES = BANC / "n-existe-pas"
        try:
            e = moteur.instantane()
        finally:
            (BANC / "mokutil.de-cote").rename(FAUX / "mokutil")
            (BANC / "lspci.de-cote").rename(FAUX / "lspci")
        self.assertIsNone(e["secure_boot"])
        self.assertIn("mokutil", e["raisons"]["secure_boot"])
        self.assertIsNone(e["noyau"]["module_nvidia_plus_recent"], "illisible n'est pas « absent »")
        self.assertIn("illisible", e["raisons"]["noyau"])
        self.assertIn("lspci", e["raisons"]["cartes"])

    def test_sans_index_apt_pas_a_jour(self):
        #  L'ISO est construite avec « --apt-indices false ».
        preparer_machine({"politique": POLITIQUE_A_JOUR}, listes=False)
        m = moteur.instantane()["mises_a_jour"]
        self.assertFalse(m["disponible"])
        self.assertIn("jamais été téléchargée", m["raison"])
        self.assertEqual(m["paquets"], [])

    def test_apt_cache_en_echec_pas_a_jour(self):
        preparer_machine({"apt_cache_code": 100})
        m = moteur.instantane()["mises_a_jour"]
        self.assertFalse(m["disponible"])
        self.assertIn("apt-cache a échoué (code 100)", m["raison"])

    def test_retrait_vu_avant_le_clic(self):
        preparer_machine({"politique": POLITIQUE, "simulation": "Remv monappli [1.0]\n" + SIMULATION_SANS_RETRAIT})
        m = moteur.instantane()["mises_a_jour"]
        self.assertEqual(m["retraits"], ["monappli"])

    def test_dpkg_query_en_echec_pas_a_jour(self):
        #  Sans la liste des paquets installés, « rien à faire » serait inventé.
        preparer_machine({"politique": POLITIQUE, "dpkg_query_code": 2})
        m = paquets.etat_mises_a_jour()
        self.assertEqual((m["disponible"], m["plan"]), (False, []))
        self.assertIn("dpkg-query a échoué (code 2)", m["raison"])
        self.assertFalse(moteur.instantane()["mises_a_jour"]["disponible"])

    def test_apt_cache_muet_pas_a_jour(self):
        #  apt-cache qui rend 0 sans RIEN écrire : aucune version connue.
        preparer_machine({"politique": ""})
        m = paquets.etat_mises_a_jour()
        self.assertFalse(m["disponible"])
        self.assertIn("apt-cache", m["raison"])

    def test_simulation_en_echec_bouton_indisponible(self):
        #  apt refuse la transaction (paquets retenus) sans ligne « Remv » :
        #  le bouton ne doit pas proposer ce qu'apt refusera.
        preparer_machine({"politique": POLITIQUE, "simulation_code": 100,
                          "simulation": "E: Unable to correct problems, you have held broken packages.\n"})
        m = moteur.instantane()["mises_a_jour"]
        self.assertFalse(m["disponible"])
        self.assertIn("simulation", m["raison"])
        self.assertIn("held broken packages", m["raison"])

    def test_raisons_paquets_et_epingle_gardees(self):
        #  dpkg-query en échec ET un fichier d'épingle illisible (un dossier :
        #  open() lève IsADirectoryError, même en root). instantane() doit
        #  rendre la raison de CHAQUE trou, pas seulement le trou.
        (BANC / "scenario.json").write_text(json.dumps({"dpkg_query_code": 2, "lspci": LSPCI}), encoding="utf-8")
        epingle = BANC / "epingle-illisible"
        epingle.mkdir(exist_ok=True)
        paquets.FICHIER_EPINGLE = str(epingle)
        e = moteur.instantane()
        self.assertIsNone(e["mesa"])
        self.assertIn("dpkg-query a échoué", e["raisons"].get("mesa", ""))
        self.assertIsNone(e["nvidia"]["paquet"])
        self.assertIn("dpkg-query a échoué", e["raisons"].get("paquet_nvidia", ""))
        self.assertIsNone(e["nvidia"]["branche_epinglee"])
        self.assertIn("illisible", e["raisons"].get("branche_epinglee", ""))


class AideRoot(unittest.TestCase):
    """maj.installer() tourne VRAIMENT, face aux faux apt/dpkg/dkms."""

    def setUp(self):
        _garde_faux_outils()

    def machine(self, **scenario):
        base = {"politique": POLITIQUE, "simulation": SIMULATION_SANS_RETRAIT,
                "transaction": TRANSACTION_REUSSIE, "dkms": "construit"}
        base.update(scenario)
        return base

    def test_refuse_sans_root(self):
        if os.geteuid() == 0:
            self.skipTest("le banc tourne en root")
        r = subprocess.run([PY, "-B", str(DOSSIER / "maj.py"), "installer"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("LEXOS-RESULTAT", r.stdout)

    def test_module_absent_detecte(self):
        with tempfile.TemporaryDirectory() as d:
            racine = Path(d)
            (racine / "6.12.48+deb13-amd64/updates/dkms").mkdir(parents=True)
            (racine / "6.12.48+deb13-amd64/updates/dkms/nvidia.ko.xz").write_text("")
            (racine / "6.16.12+bpo-amd64").mkdir()
            ancien = maj.RACINE_MODULES
            maj.RACINE_MODULES = racine
            try:
                self.assertEqual(maj.noyau_le_plus_recent(), "6.16.12+bpo-amd64")
                self.assertFalse(maj.module_nvidia_present("6.16.12+bpo-amd64"))
                self.assertTrue(maj.module_nvidia_present("6.12.48+deb13-amd64"))
            finally:
                maj.RACINE_MODULES = ancien

    def test_installation_normale(self):
        modules = preparer_machine(self.machine(), noyaux=((NOYAU_EN_SERVICE_FICTIF, True), (NOYAU_PROCHAIN, False)),
                                   entetes=(NOYAU_PROCHAIN,))
        code, sortie, res = lancer_aide()
        self.assertEqual(code, 0, sortie)
        apt = appels("apt-get")
        demandes = ["libgl1-mesa-dri/trixie-backports", "nvidia-driver-cuda"]
        options = ["-q", "--only-upgrade"]
        self.assertEqual(apt, [
            ["update", "-q"],
            ["install", "-s", *options, "-o", "Dpkg::Options::=--force-confold", *demandes],
            ["install", "-y", *options, "--no-remove", "-o", "Dpkg::Options::=--force-confold", *demandes],
        ], "l'argv exact d'apt : la liste recalculée en root, rien d'autre")
        tout = json.dumps(appels())
        self.assertNotIn("firefox-esr", tout)
        self.assertNotIn("monappli", tout)
        for verbe in ("upgrade", "dist-upgrade", "full-upgrade", "remove", "purge"):
            self.assertNotIn(verbe, [a[0] for a in apt])
        #  Le noyau du PROCHAIN démarrage (sort -V), pas celui en service.
        self.assertEqual(appels("dkms"), [["autoinstall", "-k", NOYAU_PROCHAIN]])
        self.assertTrue((modules / NOYAU_PROCHAIN / "updates/dkms/nvidia.ko.xz").exists())
        self.assertTrue(res["ok"])
        self.assertTrue(res["redemarrer"])
        self.assertIn("Redémarre", res["message"])
        self.assertEqual(res["avertissements"], [])
        self.assertEqual({m["paquet"] for m in res["modifies"]},
                         {"libgl1-mesa-dri:amd64", "libgl1-mesa-dri:i386", "nvidia-driver-cuda"})

    def test_noms_en_trop_ignores(self):
        #  Même si quelqu'un appelait l'aide avec des noms de paquets, la
        #  liste reste celle que root recalcule.
        preparer_machine(self.machine(), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide(["installer", "firefox-esr", "sudo"])
        self.assertTrue(res["ok"], sortie)
        tout = json.dumps(appels("apt-get"))
        self.assertNotIn("firefox-esr", tout)
        self.assertNotIn("sudo", tout)

    def test_retrait_refuse_avant_toute_installation(self):
        preparer_machine(self.machine(simulation="Remv monappli [1.0]\n" + SIMULATION_SANS_RETRAIT),
                         noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertEqual(code, 1, sortie)
        self.assertFalse(res["ok"])
        self.assertEqual(res["retraits"], ["monappli"])
        self.assertIn("monappli", res["message"])
        self.assertIn("rien n'a été changé", res["message"])
        self.assertFalse([a for a in appels("apt-get") if "-y" in a], "aucune vraie installation")
        self.assertEqual(json.loads((BANC / "dpkg.json").read_text()), DPKG_DEFAUT)

    def test_no_remove_seconde_serrure(self):
        #  La simulation n'a rien vu, mais la vraie transaction voudrait
        #  retirer : --no-remove fait abandonner apt, et dpkg n'a pas bougé.
        transaction = {"retirer": ["monappli"], "changer": TRANSACTION_REUSSIE["changer"], "code": 0}
        preparer_machine(self.machine(transaction=transaction), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertIn("monappli", json.loads((BANC / "dpkg.json").read_text()))
        self.assertFalse(res["ok"])
        self.assertIn("rien n'a été changé", res["message"])

    def test_dpkg_arrete_en_route(self):
        #  Le postinst DKMS échoue : paquets dépaquetés, apt rend 100.
        transaction = {"changer": {"nvidia-driver-cuda": ["595.91.07-1", "iU"]}, "code": 100,
                       "sortie": "Error! Bad return status for module build\nE: Sub-process /usr/bin/dpkg "
                                 "returned an error code (1)\n"}
        preparer_machine(self.machine(transaction=transaction, configure_code=1, dkms="echec",
                                      f_retirer=["monappli"]),
                         noyaux=((NOYAU_PROCHAIN, False),), entetes=(NOYAU_PROCHAIN,))
        code, sortie, res = lancer_aide()
        self.assertEqual(code, 1, sortie)
        self.assertFalse(res["ok"])
        self.assertNotIn("rien n'a été changé", res["message"])
        self.assertIn("INTERROMPUE", res["message"])
        self.assertIn("NE redémarre PAS", res["message"])
        self.assertIn("nvidia-driver-cuda", res["message"])
        self.assertFalse(res["redemarrer"])
        #  Réparation SANS retrait : dpkg --configure -a, puis -f avec --no-remove.
        self.assertIn(["--configure", "-a", "--force-confold"], appels("dpkg"))
        for a in appels("apt-get"):
            if "-f" in a:
                self.assertIn("--no-remove", a)
        self.assertIn("monappli", json.loads((BANC / "dpkg.json").read_text()))
        #  Et nvidia.ko est vérifié quand même.
        self.assertEqual(appels("dkms"), [["autoinstall", "-k", NOYAU_PROCHAIN]])
        self.assertTrue(any("module NVIDIA" in a for a in res["avertissements"]))

    def test_apt_arrete_avant_dpkg(self):
        #  Téléchargement en échec : dpkg n'a rien touché, et ÇA se prouve.
        transaction = {"changer": {}, "code": 100, "sortie": "E: Failed to fetch http://x (simulé)\n"}
        preparer_machine(self.machine(transaction=transaction), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertFalse(res["ok"])
        self.assertIn("rien n'a été changé", res["message"])
        self.assertEqual([a for a in appels("dpkg") if "--compare-versions" not in a], [],
                         "aucune réparation quand rien n'a bougé")

    def test_noyau_sans_entetes(self):
        preparer_machine(self.machine(), noyaux=((NOYAU_EN_SERVICE_FICTIF, True), (NOYAU_PROCHAIN, False)))
        code, sortie, res = lancer_aide()
        self.assertEqual(appels("dkms"), [], "sans en-têtes, dkms ne peut rien compiler")
        self.assertTrue(res["ok"])
        self.assertFalse(res["redemarrer"])
        self.assertNotIn("Redémarre pour", res["message"])
        self.assertIn("NE redémarre PAS", res["message"])
        self.assertTrue(any(f"linux-headers-{NOYAU_PROCHAIN}" in a for a in res["avertissements"]))

    def test_dkms_en_echec_dit_pourquoi(self):
        preparer_machine(self.machine(dkms="echec"), noyaux=((NOYAU_PROCHAIN, False),), entetes=(NOYAU_PROCHAIN,))
        code, sortie, res = lancer_aide()
        #  Dans le JOURNAL : la ligne LEXOS-RESULTAT cite déjà la dernière
        #  ligne de dkms (dans l'avertissement), elle ne prouve rien ici.
        journal = "\n".join(l for l in sortie.splitlines() if not l.startswith("LEXOS-RESULTAT "))
        self.assertIn("Bad return status", journal, "la sortie de dkms est au journal")
        self.assertFalse(res["redemarrer"])
        self.assertTrue(any("Bad return status" in a for a in res["avertissements"]))

    def test_dkms_absent_avertissement_garde(self):
        preparer_machine(self.machine(), noyaux=((NOYAU_PROCHAIN, False),), entetes=(NOYAU_PROCHAIN,))
        (FAUX / "dkms").rename(BANC / "dkms.de-cote")
        try:
            code, sortie, res = lancer_aide()
        finally:
            (BANC / "dkms.de-cote").rename(FAUX / "dkms")
        self.assertIsNotNone(res, "l'aide plantait sans LEXOS-RESULTAT : " + sortie[-300:])
        self.assertFalse(res["redemarrer"])
        self.assertTrue(any("dkms est introuvable" in a for a in res["avertissements"]))

    def test_apt_cache_en_echec_jamais_a_jour(self):
        preparer_machine(self.machine(apt_cache_code=100), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertFalse(res["ok"])
        self.assertIn("apt-cache", res["message"])
        self.assertNotIn("déjà à jour", res["message"])
        self.assertFalse([a for a in appels("apt-get") if "install" in a])

    def test_deja_a_jour(self):
        preparer_machine(self.machine(politique=POLITIQUE_A_JOUR), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertTrue(res["ok"])
        self.assertIn("déjà à jour", res["message"])
        self.assertFalse([a for a in appels("apt-get") if "install" in a])

    def test_on_ne_sait_pas_jamais_deja_a_jour(self):
        #  dpkg-query en échec, ou apt-cache qui ne répond rien : l'aide root
        #  ne sait pas quoi mettre à jour. Elle le dit, et n'installe rien.
        cas = {"dpkg-query": self.machine(dpkg_query_code=2), "apt-cache": self.machine(politique="")}
        for outil, scenario in cas.items():
            with self.subTest(outil):
                preparer_machine(scenario, noyaux=((NOYAU_PROCHAIN, True),))
                code, sortie, res = lancer_aide()
                self.assertIsNotNone(res, sortie[-300:])
                self.assertFalse(res["ok"])
                self.assertIn("Impossible de savoir", res["message"])
                self.assertIn(outil, res["message"])
                self.assertNotIn("déjà à jour", res["message"])
                self.assertFalse([a for a in appels("apt-get") if "install" in a])

    def test_simulation_en_echec_rien_installe(self):
        preparer_machine(self.machine(simulation="E: Unable to correct problems, you have held broken packages.\n",
                                      simulation_code=100), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide()
        self.assertEqual(code, 1, sortie)
        self.assertFalse(res["ok"])
        self.assertIn("simulation a échoué", res["message"])
        self.assertIn("rien n'a été changé", res["message"])
        self.assertFalse([a for a in appels("apt-get") if "-y" in a], "aucune vraie installation")

    def test_aucun_delai_qui_tue_apt_ou_dpkg(self):
        #  Tuer apt-get ou « dpkg --configure -a » en pleine transaction, c'est
        #  laisser l'ancien module retiré et le nouveau pas construit. On lit
        #  le délai de CHAQUE subprocess.run : la vraie installation, puis la
        #  réparation après un arrêt en route.
        transaction = {"changer": {"nvidia-driver-cuda": ["595.91.07-1", "iU"]}, "code": 100,
                       "sortie": "E: Sub-process /usr/bin/dpkg returned an error code (1)\n"}
        preparer_machine(self.machine(transaction=transaction), noyaux=((NOYAU_PROCHAIN, True),))
        lancer_aide(prelude=PRELUDE_DELAIS)
        delais = [json.loads(l) for l in (BANC / "delais.jsonl").read_text(encoding="utf-8").splitlines()]
        motifs = {"apt-get install -y": ["apt-get", "install", "-y"],
                  "apt-get install -f": ["apt-get", "install", "-f"],
                  "dpkg --configure -a": ["dpkg", "--configure", "-a"]}
        for cle, motif in motifs.items():
            with self.subTest(cle):
                liste = [d for cmd, d in delais if cmd[:len(motif)] == motif]
                self.assertTrue(liste, f"« {cle} » n'a pas été lancé")
                self.assertEqual(set(liste), {None}, f"« {cle} » a un délai qui le tuerait en route")

    def test_dkms_trop_lent_avertissement_garde(self):
        #  Un VRAI dépassement : le faux dkms dort 30 s, le délai est raccourci
        #  à 1 s. L'aide doit rendre un résultat, pas une trace Python.
        preparer_machine(self.machine(dkms="lent"), noyaux=((NOYAU_PROCHAIN, False),), entetes=(NOYAU_PROCHAIN,))
        debut = time.time()
        code, sortie, res = lancer_aide(prelude="maj.DELAI_DKMS = 1")
        self.assertLess(time.time() - debut, 25, "dkms aurait dû être arrêté au bout d'1 s")
        self.assertIsNotNone(res, "plantage sans LEXOS-RESULTAT : " + sortie[-300:])
        self.assertTrue(res["ok"])
        self.assertFalse(res["redemarrer"])
        self.assertIn("NE redémarre PAS", res["message"])
        self.assertTrue(any("n'a pas fini en 1 s" in a for a in res["avertissements"]), res["avertissements"])

    def test_dpkg_query_muet_jamais_rien_change(self):
        #  apt rend 100 et dpkg-query ne répond plus : rien n'est PROUVÉ, donc
        #  pas de « rien n'a été changé ».
        transaction = {"changer": {}, "code": 100, "sortie": "E: Failed to fetch http://x (simulé)\n"}
        preparer_machine(self.machine(transaction=transaction), noyaux=((NOYAU_PROCHAIN, True),))
        code, sortie, res = lancer_aide(prelude="maj.etat_dpkg = lambda: None")
        self.assertFalse(res["ok"])
        self.assertNotIn("rien n'a été changé", res["message"])
        self.assertIn("impossible de savoir ce qui a été modifié", res["message"])
        self.assertIn("NE redémarre PAS", res["message"])

    def test_journal_garde_le_debut_et_la_fin(self):
        #  « will be REMOVED » est au DÉBUT de la sortie d'apt.
        sortie = "The following packages will be REMOVED:\n  monappli\n" + "x" * 20000 + "\nFIN\n"
        e = maj._extrait(sortie)
        self.assertIn("REMOVED", e)
        self.assertIn("monappli", e)
        self.assertIn("FIN", e)
        self.assertLess(len(e), len(sortie))

    def test_pas_de_shell(self):
        for f in DOSSIER.glob("*.py"):
            self.assertNotIn("shell=True", f.read_text(encoding="utf-8"), f.name)


class Lancement(unittest.TestCase):
    """serveur._lancer() POUR DE VRAI, face au faux pkexec."""

    def setUp(self):
        _garde_faux_outils()
        preparer_machine({})

    def lancer(self, action, pkexec):
        (BANC / "pkexec.json").write_text(json.dumps(pkexec), encoding="utf-8")
        self.assertTrue(serveur._lancer(action))
        limite = time.time() + 10
        while serveur._tache["en_cours"] and time.time() < limite:
            time.sleep(0.02)
        self.assertFalse(serveur._tache["en_cours"])
        return serveur._tache["resultat"]

    def test_argv_exact(self):
        res = self.lancer("installer", {"sortie": "» Installation…\nLEXOS-RESULTAT {\"ok\": true, "
                                                  "\"message\": \"fait\"}\n"})
        self.assertEqual(appels_pkexec(), [["/usr/bin/lexos-pilotes-maj", "installer"]],
                         "pkexec reçoit l'aide et l'action, AUCUN nom de paquet")
        self.assertEqual(res, {"ok": True, "message": "fait"})
        self.assertEqual(serveur._tache["journal"], ["» Installation…"])

    def test_codes_de_pkexec(self):
        cas = {
            "fermée": ("Error executing command as another user: Request dismissed\n", 126),
            "aucun agent polkit": ("Error executing command as another user: No authentication agent found.\n", 127),
            "refusée par polkit": ("Error executing command as another user: Not authorized\n\nThis incident "
                                   "has been reported.\n", 127),
            #  Le 127 « générique » (programme absent…) : ni agent, ni refus.
            "code 127": ("Error executing command as another user: Cannot run program "
                         "/usr/bin/lexos-pilotes-maj: No such file or directory\n", 127),
        }
        for attendu, (texte, code) in cas.items():
            with self.subTest(attendu):
                res = self.lancer("verifier", {"sortie": texte, "code": code})
                self.assertIn(attendu, res["message"])
                self.assertIn("rien n'a été changé", res["message"])
                if code == 127:
                    self.assertNotIn("annulé", res["message"])

    def test_une_tache_a_la_fois(self):
        feu = BANC / "feu-vert"
        feu.unlink(missing_ok=True)
        (BANC / "pkexec.json").write_text(json.dumps({"attendre": str(feu)}), encoding="utf-8")
        self.assertTrue(serveur._lancer("installer"))
        try:
            self.assertFalse(serveur._lancer("installer"), "deux apt en parallèle")
        finally:
            feu.write_text("")
            limite = time.time() + 10
            while serveur._tache["en_cours"] and time.time() < limite:
                time.sleep(0.02)
        self.assertEqual(len(appels_pkexec()), 1)


class Serveur(unittest.TestCase):
    """Le vrai Gestionnaire : refuse l'étranger, ACCEPTE la page légitime."""

    @classmethod
    def setUpClass(cls):
        _garde_faux_outils()
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), serveur.Gestionnaire)
        cls.port = cls.srv.server_address[1]
        cls.origine = f"http://127.0.0.1:{cls.port}"
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        preparer_machine({"politique": POLITIQUE, "simulation": SIMULATION_SANS_RETRAIT, "lspci": LSPCI},
                         noyaux=((NOYAU_PROCHAIN, True),))
        (BANC / "pkexec.json").write_text(json.dumps({"sortie": "LEXOS-RESULTAT {\"ok\": true, "
                                                                "\"message\": \"Index à jour.\"}\n"}))

    def req(self, methode, chemin, entetes=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request(methode, chemin, headers=entetes or {})
        r = c.getresponse()
        corps = r.read()
        return r.status, corps

    def legitime(self, **autres):
        return {"Origin": self.origine, "X-LexOS": "1", "X-Jeton": serveur.JETON, **autres}

    def attendre_fin(self):
        limite = time.time() + 10
        while serveur._tache["en_cours"] and time.time() < limite:
            time.sleep(0.02)

    def test_page_statique_sans_jeton(self):
        self.assertEqual(self.req("GET", "/")[0], 200)
        self.assertEqual(self.req("GET", "/app.js")[0], 200)

    def test_api_sans_jeton_refusee(self):
        self.assertEqual(self.req("GET", "/api/etat")[0], 403)
        self.assertEqual(self.req("GET", "/api/tache")[0], 403)
        sans = self.legitime()
        del sans["X-Jeton"]
        for chemin in ("/api/installer", "/api/verifier", "/api/assistant-signature"):
            self.assertEqual(self.req("POST", chemin, sans)[0], 403)
            self.assertEqual(self.req("POST", chemin, self.legitime(**{"X-Jeton": "devine"}))[0], 403)
        self.assertEqual(appels_pkexec(), [], "aucun refus ne doit atteindre pkexec")

    def test_hote_etranger(self):
        self.assertEqual(self.req("GET", "/api/tache", {"Host": "evil.example", "X-Jeton": serveur.JETON})[0], 403)

    def test_origine_etrangere_get_et_post(self):
        for o in ("https://evil.example", "http://127.0.0.1:1", f"https://127.0.0.1:{self.port}"):
            with self.subTest(o):
                self.assertEqual(self.req("GET", "/api/etat", {"Origin": o, "X-Jeton": serveur.JETON})[0], 403)
                self.assertEqual(self.req("POST", "/api/installer", self.legitime(Origin=o))[0], 403)
        self.assertEqual(appels_pkexec(), [])

    def test_post_sans_entete_maison(self):
        entetes = self.legitime()
        del entetes["X-LexOS"]
        self.assertEqual(self.req("POST", "/api/installer", entetes)[0], 403)
        self.assertEqual(appels_pkexec(), [])

    def test_traversee(self):
        self.assertIn(self.req("GET", "/../serveur.py")[0], (403, 404))

    def test_ecoute_boucle_locale_seulement(self):
        src = (DOSSIER / "serveur.py").read_text(encoding="utf-8")
        ecoutes = re.findall(r'ThreadingHTTPServer\(\("([^"]*)"', src)
        self.assertEqual(ecoutes, ["127.0.0.1"])

    def test_action_legitime_passe(self):
        statut, corps = self.req("POST", "/api/verifier", self.legitime())
        self.assertEqual((statut, json.loads(corps)), (200, {"lance": True}))
        self.attendre_fin()
        self.assertEqual(appels_pkexec(), [["/usr/bin/lexos-pilotes-maj", "verifier"]])
        statut, corps = self.req("GET", "/api/tache", {"X-Jeton": serveur.JETON})
        tache = json.loads(corps)
        self.assertEqual(statut, 200)
        self.assertFalse(tache["en_cours"])
        self.assertEqual(tache["resultat"], {"ok": True, "message": "Index à jour."})

    def test_etat_rend_ce_que_lit_la_page(self):
        statut, corps = self.req("GET", "/api/etat", {"X-Jeton": serveur.JETON, "Origin": self.origine})
        self.assertEqual(statut, 200, corps[:200])
        e = json.loads(corps)
        js = APP_JS.read_text(encoding="utf-8")
        attendu = {"": ["cartes", "nvidia", "mesa", "noyau", "secure_boot", "signature", "verifie_le",
                        "maintenant", "mises_a_jour", "raisons"],
                   "nvidia": ["version", "paquet", "branche_epinglee", "plus_recente_publiee"],
                   "noyau": ["en_service", "plus_recent", "module_nvidia_plus_recent"],
                   "mises_a_jour": ["disponible", "raison", "paquets", "retraits"]}
        for parent, cles in attendu.items():
            for cle in cles:
                with self.subTest(f"{parent}.{cle}"):
                    self.assertIn(cle, e[parent] if parent else e)
                    self.assertIn(cle, js, "app.js lit cette clé par son nom")

    def test_poignee_de_main(self):
        defi = secrets.token_hex(16)
        statut, corps = self.req("GET", f"/api/bonjour?defi={defi}")
        self.assertEqual(statut, 200)
        preuve = json.loads(corps)["preuve"]
        self.assertEqual(preuve, hmac.new(serveur.JETON.encode(), b"bonjour:" + defi.encode(),
                                          hashlib.sha256).hexdigest())
        self.assertNotIn(serveur.JETON, corps.decode())
        #  Seulement de l'hexadécimal : « ouvrir:<nonce> » (le message d'un
        #  sceau de ticket) n'est jamais signé.
        for mauvais in ("ouvrir:" + secrets.token_hex(16), "x" * 20, "0" * 8):
            with self.subTest(mauvais):
                self.assertEqual(self.req("GET", f"/api/bonjour?defi={mauvais}")[0], 400)

    def test_contrat_app_js(self):
        js = APP_JS.read_text(encoding="utf-8")
        self.assertIn('"X-Jeton"', js)
        self.assertIn('"X-LexOS"', js)
        self.assertIn('"X-Ticket"', js)
        self.assertIn("location.hash", js)
        routes = set(re.findall(r'"/api/([a-z-]+)"', js))
        if '"/api/" + action' in js:
            routes |= set(re.findall(r'lancer\("([a-z]+)"\)', js))
        self.assertLessEqual({"entree", "etat", "tache", "verifier", "installer", "assistant-signature"}, routes)
        src = (DOSSIER / "serveur.py").read_text(encoding="utf-8")
        for route in sorted(routes):
            with self.subTest(route):
                self.assertIn(f'"/api/{route}"', src, f"app.js appelle /api/{route}, que serveur.py ignore")


class Lanceur(unittest.TestCase):
    """Le deuxième clic ne rouvre que NOTRE serveur."""

    def setUp(self):
        self.run = Path(tempfile.mkdtemp(dir=BANC))
        self.run.chmod(0o700)
        os.environ["XDG_RUNTIME_DIR"] = str(self.run)

    def tearDown(self):
        os.environ["XDG_RUNTIME_DIR"] = str(BANC / "run")

    def ecrire_etat_a_la_main(self, port, jeton):
        d = self.run / "lexos"
        d.mkdir(mode=0o700, exist_ok=True)
        f = d / "pilotes.json"
        f.write_text(json.dumps({"port": port, "jeton": jeton, "pid": 1}), encoding="utf-8")
        f.chmod(0o600)

    def test_squatteur_jamais_ouvert(self):
        class Squatteur(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                b = b'{"preuve": "0000"}'
                self.send_response(200)
                self.send_header("Content-Length", str(len(b)))
                self.end_headers()
                self.wfile.write(b)

            def log_message(self, *a):
                pass
        srv = http.server.HTTPServer(("127.0.0.1", 0), Squatteur)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            self.ecrire_etat_a_la_main(srv.server_address[1], "jeton-d-un-serveur-mort")
            self.assertIsNone(serveur.serveur_existant())
        finally:
            srv.shutdown()
            srv.server_close()

    def test_notre_serveur_retrouve(self):
        srv = ThreadingHTTPServer(("127.0.0.1", 0), serveur.Gestionnaire)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            f = serveur.ecrire_etat(srv.server_address[1])
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
            self.assertEqual(f.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(serveur.serveur_existant(), (srv.server_address[1], serveur.JETON))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_fichier_ou_dossier_trop_ouvert_ignore(self):
        #  Un VRAI serveur vivant, avec le bon jeton : si le fichier est
        #  ignoré, c'est à cause de son mode ou de son propriétaire, pas d'une
        #  connexion refusée (l'ancien test visait le port 1).
        srv = ThreadingHTTPServer(("127.0.0.1", 0), serveur.Gestionnaire)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            f = serveur.ecrire_etat(srv.server_address[1])
            self.assertIsNotNone(serveur.serveur_existant(), "témoin : serveur vivant, bon jeton, fichier 0600")
            f.chmod(0o644)
            self.assertIsNone(serveur.serveur_existant(), "fichier lisible par tous : ignoré")
            f.chmod(0o600)
            if os.geteuid() == 0:
                os.chown(f, 65534, 65534)
                self.assertIsNone(serveur.serveur_existant(), "fichier d'un autre compte : ignoré")
                os.chown(f, 0, 0)
            self.assertIsNotNone(serveur.serveur_existant(), "témoin final")
        finally:
            srv.shutdown()
            srv.server_close()
        (self.run / "lexos").chmod(0o755)
        self.assertIsNone(serveur.dossier_execution())

    def test_jeton_neuf_et_long_a_chaque_demarrage(self):
        #  Tous les autres tests lisent serveur.JETON : un jeton FIXE (écrit
        #  dans serveur.py, lisible par tous) ou de 2 octets y passait vert.
        prog = f"import sys; sys.path.insert(0, {str(DOSSIER)!r}); import serveur; print(serveur.JETON)"
        jetons = [subprocess.run([PY, "-I", "-B", "-c", prog], capture_output=True, text=True,
                                 check=True, timeout=30).stdout.strip() for _ in range(3)]
        self.assertEqual(len(set(jetons)), 3, "le même jeton d'un démarrage à l'autre")
        for j in jetons:
            self.assertRegex(j, r"^[A-Za-z0-9_-]+$")
            brut = base64.urlsafe_b64decode(j + "=" * (-len(j) % 4))
            self.assertGreaterEqual(len(brut) * 8, 128, f"jeton de {len(brut) * 8} bits seulement")

    def test_lanceur_ne_sonde_plus_de_port(self):
        code = "\n".join(l for l in LANCEUR.read_text(encoding="utf-8").splitlines()
                         if not l.lstrip().startswith("#"))
        for interdit in ("curl", "xdg-open", "7862"):
            self.assertNotIn(interdit, code)
        self.assertIn('serveur.py', code)


def _ticket_de(page: Path) -> tuple:
    """(port, ticket) que la page d'ouverture fait suivre au navigateur."""
    m = re.search(r'location\.replace\("http://127\.0\.0\.1:(\d+)/#o=([^"]+)"\)', page.read_text(encoding="utf-8"))
    return (int(m.group(1)), m.group(2)) if m else (None, None)


class Ouverture(unittest.TestCase):
    """La page d'ouverture et l'échange du ticket, face au vrai Gestionnaire."""

    @classmethod
    def setUpClass(cls):
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), serveur.Gestionnaire)
        cls.port = cls.srv.server_address[1]
        cls.origine = f"http://127.0.0.1:{cls.port}"
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        self.run = Path(tempfile.mkdtemp(dir=BANC))
        self.run.chmod(0o700)
        os.environ["XDG_RUNTIME_DIR"] = str(self.run)

    def tearDown(self):
        os.environ["XDG_RUNTIME_DIR"] = str(BANC / "run")

    def entrer(self, ticket, **entetes):
        e = {"Origin": self.origine, "X-LexOS": "1", **entetes}
        if ticket is not None:
            e["X-Ticket"] = ticket
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("POST", "/api/entree", headers={k: v for k, v in e.items() if v is not None})
        r = c.getresponse()
        return r.status, r.read()

    def test_page_privee_sans_le_jeton(self):
        page = serveur.ecrire_ouverture(self.port, serveur.JETON)
        self.assertEqual(page.parent, self.run / "lexos", "dans $XDG_RUNTIME_DIR/lexos")
        st = page.stat()
        self.assertEqual(st.st_mode & 0o777, 0o600)
        self.assertEqual(st.st_uid, os.getuid())
        self.assertEqual(page.parent.stat().st_mode & 0o777, 0o700)
        texte = page.read_text(encoding="utf-8")
        port, ticket = _ticket_de(page)
        self.assertEqual(port, self.port)
        nonce, sceau = ticket.split(".")
        #  Le jeton n'y est pas : seulement un ticket, dont le SCEAU n'est
        #  que dans le contenu (0600), jamais dans le chemin passé à l'argv.
        self.assertNotIn(serveur.JETON, texte)
        self.assertNotIn(serveur.JETON, page.as_uri())
        self.assertNotIn(sceau, page.as_uri())
        self.assertIn('content="no-referrer"', texte)
        #  UNE seule navigation : un « meta refresh » en plus du script
        #  chargerait la page deux fois, et la seconde trouverait le ticket
        #  déjà dépensé. Le refresh n'a sa place que dans <noscript>.
        self.assertEqual(texte.count("location.replace("), 1)
        self.assertNotIn("http-equiv", re.sub(r"<noscript>.*?</noscript>", "", texte, flags=re.S),
                         "une seule navigation : un ticket ne sert qu'une fois")
        self.assertEqual(list(page.parent.glob(".pilotes-ouvrir-*")), [], "aucun fichier temporaire laissé")

    def test_ticket_echange_une_seule_fois_et_page_effacee(self):
        page = serveur.ecrire_ouverture(self.port, serveur.JETON)
        _port, ticket = _ticket_de(page)
        statut, corps = self.entrer(ticket)
        self.assertEqual((statut, json.loads(corps)), (200, {"jeton": serveur.JETON}))
        self.assertFalse(page.exists(), "la page d'ouverture est effacée dès qu'elle a servi")
        self.assertEqual(self.entrer(ticket)[0], 403, "un ticket ne sert qu'une fois")

    def test_page_d_un_deuxieme_clic_effacee(self):
        #  Écrite par un AUTRE processus (le deuxième clic) : ce serveur ne l'a
        #  pas dans sa mémoire, il la retrouve par son nom.
        page = serveur.ecrire_ouverture(self.port, serveur.JETON)
        with serveur._verrou_tickets:
            serveur._ouvertures.clear()
        self.assertEqual(self.entrer(_ticket_de(page)[1])[0], 200)
        self.assertFalse(page.exists())

    def test_tickets_forges_refuses(self):
        page = serveur.ecrire_ouverture(self.port, serveur.JETON)
        _port, ticket = _ticket_de(page)
        nonce, sceau = ticket.split(".")
        #  /api/bonjour signe ce qu'on lui donne, sans jeton : son HMAC ne doit
        #  JAMAIS valoir un sceau de ticket.
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", f"/api/bonjour?defi={nonce}")
        preuve = json.loads(c.getresponse().read())["preuve"]
        c.request("GET", f"/api/bonjour?defi=ouvrir:{nonce}")
        r = c.getresponse()
        corps = r.read()
        par_bonjour = json.loads(corps).get("preuve", "") if r.status == 200 else ""
        cas = {
            "sans ticket": (None, {}),
            "sceau au hasard": (f"{nonce}.{secrets.token_hex(32)}", {}),
            "nonce changé": (f"{secrets.token_hex(16)}.{sceau}", {}),
            "sceau signé par /api/bonjour": (f"{nonce}.{preuve}", {}),
            "sceau signé par /api/bonjour (ouvrir:)": (f"{nonce}.{par_bonjour or '0' * 64}", {}),
            "le jeton en guise de ticket": (serveur.JETON, {}),
            "forme invalide": ("../../pilotes.json", {}),
            "origine étrangère": (ticket, {"Origin": "http://127.0.0.1:1"}),
            "sans en-tête maison": (ticket, {"X-LexOS": None}),
        }
        for nom, (t, entetes) in cas.items():
            with self.subTest(nom):
                self.assertEqual(self.entrer(t, **entetes)[0], 403)
        self.assertTrue(page.exists(), "un refus ne dépense pas le ticket")
        self.assertEqual(self.entrer(ticket)[0], 200, "témoin : le vrai ticket passe toujours")

    def test_arret_efface_les_pages_non_servies(self):
        a_moi = serveur.ecrire_ouverture(self.port, serveur.JETON)
        deuxieme_clic = self.run / "lexos" / f"pilotes-ouvrir-{self.port}-{secrets.token_hex(16)}.html"
        deuxieme_clic.write_text("x")
        autre_serveur = self.run / "lexos" / f"pilotes-ouvrir-{self.port + 1}-{secrets.token_hex(16)}.html"
        autre_serveur.write_text("x")
        serveur.effacer_ouvertures(self.port)
        self.assertFalse(a_moi.exists())
        self.assertFalse(deuxieme_clic.exists())
        self.assertTrue(autre_serveur.exists(), "les pages d'un AUTRE serveur ne sont pas les nôtres")

    def test_dossier_prive_inutilisable_repli_0700(self):
        #  $XDG_RUNTIME_DIR/lexos trop ouvert : jamais là, mais dans un dossier
        #  neuf 0700 au nom imprévisible, effacé à l'arrêt.
        (self.run / "lexos").mkdir(mode=0o755)
        (self.run / "lexos").chmod(0o755)
        page = serveur.ecrire_ouverture(self.port, serveur.JETON)
        self.assertNotEqual(page.parent, self.run / "lexos")
        self.assertEqual(page.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(page.stat().st_mode & 0o777, 0o600)
        serveur.effacer_ouvertures(self.port)
        self.assertFalse(page.parent.exists())


class Espion(threading.Thread):
    """Relit /proc/*/cmdline et /proc/*/environ de TOUS les processus
    lisibles, sans arrêt, et garde chaque contenu distinct vu."""

    def __init__(self):
        super().__init__(daemon=True)
        self.vus = {}            # (pid, "cmdline"|"environ") -> {contenus}
        self.halte = threading.Event()
        self.tours = 0

    def run(self):
        while not self.halte.is_set():
            for pid in os.listdir("/proc"):
                if not pid.isdigit():
                    continue
                for quoi in ("cmdline", "environ"):
                    try:
                        with open(f"/proc/{pid}/{quoi}", "rb") as f:
                            contenu = f.read()
                    except OSError:
                        continue
                    if contenu:
                        self.vus.setdefault((int(pid), quoi), set()).add(contenu)
            self.tours += 1
            time.sleep(0.002)

    def arreter(self):
        self.halte.set()
        self.join(10)

    def contenus(self, quoi=None):
        return [c for (_p, q), cs in self.vus.items() if quoi in (None, q) for c in cs]


class Fuite(unittest.TestCase):
    """LE JETON NE PASSE NI PAR UN ARGV NI PAR UN ENVIRONNEMENT.

    Le vrai lanceur, le vrai serveur.py, sans --sans-navigateur. Le faux
    xdg-open suit la page d'ouverture comme le ferait Chromium, puis échange
    le ticket comme app.js. Pendant TOUTE la vie du lanceur et du serveur
    (trois clics, une vérification, l'assistant de signature, puis SIGTERM),
    l'Espion relit /proc. On exige aussi qu'il ait VU ces enfants : sinon
    « rien trouvé » ne prouverait rien. Avant, l'URL « #j=JETON » partait
    dans l'argv de xdg-open, et uid 65534 la lisait dans /proc."""

    def setUp(self):
        _garde_faux_outils()
        preparer_machine({"politique": POLITIQUE, "simulation": SIMULATION_SANS_RETRAIT, "lspci": LSPCI,
                          "navigateur": "suivre",
                          "vivre": {"xdg-open": 0.6, "x-terminal-emulator": 0.6, "pkexec": 0.6}},
                         noyaux=((NOYAU_PROCHAIN, True),))
        (BANC / "pkexec.json").write_text(json.dumps(
            {"sortie": 'LEXOS-RESULTAT {"ok": true, "message": "Index à jour."}\n'}), encoding="utf-8")
        self.run = Path(tempfile.mkdtemp(dir=BANC))
        self.run.chmod(0o700)
        texte = LANCEUR.read_text(encoding="utf-8")
        self.assertEqual(texte.count("MOTEUR_DIR=/usr/lib/lexos/pilotes\n"), 1)
        self.lanceur = BANC / "lexos-pilotes"
        self.lanceur.write_text(texte.replace("MOTEUR_DIR=/usr/lib/lexos/pilotes\n", f"MOTEUR_DIR={DOSSIER}\n"),
                                encoding="utf-8")
        self.env = {k: v for k, v in os.environ.items() if k != "BROWSER"}
        #  DISPLAY : sans lui, webbrowser n'essaie même pas xdg-open.
        self.env.update(XDG_RUNTIME_DIR=str(self.run), DISPLAY=":99", PYTHONDONTWRITEBYTECODE="1")
        self.journaux = []
        self.serveur = None

    def tearDown(self):
        if self.serveur is not None and self.serveur.poll() is None:
            self.serveur.kill()
            self.serveur.wait(10)

    def lancer(self, nom):
        journal = BANC / f"{nom}.log"
        self.journaux.append(journal)
        sortie = open(journal, "w", encoding="utf-8")
        try:
            return subprocess.Popen(["/bin/sh", str(self.lanceur)], env=self.env, stdout=sortie,
                                    stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        finally:
            sortie.close()

    def navigations(self, n, delai=15):
        limite = time.time() + delai
        while time.time() < limite:
            try:
                notes = [json.loads(l) for l in (BANC / "navigateur.jsonl").read_text(encoding="utf-8").splitlines()]
            except FileNotFoundError:
                notes = []
            if len(notes) >= n:
                return notes
            time.sleep(0.05)
        self.fail(f"le navigateur n'a pas été ouvert {n} fois : " + " / ".join(
            j.read_text(encoding="utf-8", errors="replace")[-300:] for j in self.journaux if j.exists()))

    def req(self, port, methode, chemin, entetes):
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        c.request(methode, chemin, headers=entetes)
        r = c.getresponse()
        return r.status, r.read()

    def test_jeton_jamais_dans_un_argv_ni_un_environnement(self):
        #  Un squatteur sur l'ancien port fixe : il ne doit rien empêcher.
        squatteur = socket.socket()
        try:
            squatteur.bind(("127.0.0.1", 7862))
            squatteur.listen(1)
        except OSError:
            pass                       # déjà pris : le test reste valable
        espion = Espion()
        espion.start()
        try:
            self._scenario_complet(espion)
        finally:
            espion.arreter()
            squatteur.close()
        self._rien_ne_fuit(espion)

    def _scenario_complet(self, espion):
        etat = self.run / "lexos" / "pilotes.json"
        self.serveur = self.lancer("serveur")
        limite = time.time() + 15
        while not etat.exists() and time.time() < limite and self.serveur.poll() is None:
            time.sleep(0.05)
        self.assertTrue(etat.exists(), (BANC / "serveur.log").read_text(encoding="utf-8", errors="replace"))
        lu = json.loads(etat.read_text(encoding="utf-8"))
        self.port, self.jeton, self.pid = lu["port"], lu["jeton"], lu["pid"]
        self.assertNotEqual(self.port, 7862)
        origine = f"http://127.0.0.1:{self.port}"

        # ── Premier clic : le navigateur ne reçoit QUE le chemin file:// ──
        nav = self.navigations(1)[0]
        self.assertEqual(len(nav["argv"]), 1)
        uri = nav["argv"][0]
        self.assertTrue(uri.startswith((self.run / "lexos").as_uri() + "/pilotes-ouvrir-"), uri)
        self.assertEqual((nav["mode"], nav["uid"]), (0o600, os.getuid()), "page d'ouverture 0600, à nous")
        self.assertEqual((nav["mode_dossier"], nav["uid_dossier"]), (0o700, os.getuid()))
        self.assertEqual(nav["entree"], 200, "le ticket s'échange")
        self.assertEqual(nav["jeton"], self.jeton)
        self.assertFalse(nav["page_apres"], "la page d'ouverture est effacée dès qu'elle a servi")
        self.assertEqual(nav["etat"], 200)
        self.tickets = [nav["ticket"]]

        # ── La page légitime pousse les boutons (pkexec et terminal vivent un moment) ──
        legitime = {"Origin": origine, "X-LexOS": "1", "X-Jeton": self.jeton}
        self.assertEqual(self.req(self.port, "POST", "/api/verifier", legitime)[0], 200)
        limite = time.time() + 10
        while time.time() < limite:
            t = json.loads(self.req(self.port, "GET", "/api/tache", legitime)[1])
            if not t["en_cours"]:
                break
            time.sleep(0.05)
        self.assertEqual(t["resultat"], {"ok": True, "message": "Index à jour."})
        self.assertEqual(self.req(self.port, "POST", "/api/assistant-signature", legitime)[0], 200)

        # ── Refus : sans jeton, mauvais jeton, ticket rejoué ou forgé ──
        mauvais = secrets.token_urlsafe(32)
        for nom, e in {"sans jeton": {"Origin": origine, "X-LexOS": "1"},
                       "mauvais jeton": {"Origin": origine, "X-LexOS": "1", "X-Jeton": mauvais},
                       "jeton tronqué": {"Origin": origine, "X-LexOS": "1", "X-Jeton": self.jeton[:-1]}}.items():
            for methode, chemin in (("GET", "/api/etat"), ("GET", "/api/tache"), ("POST", "/api/installer"),
                                    ("POST", "/api/verifier"), ("POST", "/api/assistant-signature")):
                with self.subTest(f"{nom} {methode} {chemin}"):
                    self.assertEqual(self.req(self.port, methode, chemin, e)[0], 403)
        nonce = self.tickets[0].split(".")[0]
        _s, corps = self.req(self.port, "GET", f"/api/bonjour?defi={nonce}", {})
        forges = {"rejoué": self.tickets[0], "au hasard": f"{secrets.token_hex(16)}.{secrets.token_hex(32)}",
                  "signé par bonjour": f"{nonce}.{json.loads(corps)['preuve']}"}
        for nom, t in forges.items():
            with self.subTest(f"ticket {nom}"):
                self.assertEqual(self.req(self.port, "POST", "/api/entree",
                                          {"Origin": origine, "X-LexOS": "1", "X-Ticket": t})[0], 403)
        time.sleep(0.2)
        self.assertEqual(appels_pkexec(), [["/usr/bin/lexos-pilotes-maj", "verifier"]],
                         "seule l'action légitime a atteint pkexec")

        # ── Deuxième clic : un autre processus, un ticket neuf, le même serveur ──
        deuxieme = self.lancer("deuxieme-clic")
        self.assertEqual(deuxieme.wait(15), 0)
        nav = self.navigations(2)[1]
        self.assertTrue(nav["argv"][0].startswith((self.run / "lexos").as_uri() + f"/pilotes-ouvrir-{self.port}-"))
        self.assertEqual((nav["entree"], nav["jeton"], nav["page_apres"]), (200, self.jeton, False))
        self.assertNotEqual(nav["ticket"], self.tickets[0])
        self.tickets.append(nav["ticket"])

        # ── Troisième clic, navigateur fermé avant de charger la page ──
        scenario = json.loads((BANC / "scenario.json").read_text(encoding="utf-8"))
        scenario["navigateur"] = "noter"
        (BANC / "scenario.json").write_text(json.dumps(scenario), encoding="utf-8")
        troisieme = self.lancer("troisieme-clic")
        self.assertEqual(troisieme.wait(15), 0)
        nav = self.navigations(3)[2]
        oubliee = Path(unquote(urlparse(nav["argv"][0]).path))
        self.assertTrue(oubliee.exists(), "jamais chargée : encore là")
        self.tickets.append(_ticket_de(oubliee)[1])

        # ── Arrêt par SIGTERM (fin de session) : rien ne reste derrière ──
        self.serveur.send_signal(signal.SIGTERM)
        self.assertEqual(self.serveur.wait(15), 0)
        self.assertFalse(etat.exists(), "fichier d'état effacé à l'arrêt")
        self.assertFalse(oubliee.exists(), "page d'ouverture jamais servie effacée à l'arrêt")
        self.assertEqual(list((self.run / "lexos").glob("*pilotes-ouvrir-*")), [])

    def _rien_ne_fuit(self, espion):
        jeton = self.jeton.encode()
        sceaux = [t.split(".")[1].encode() for t in self.tickets]
        #  L'espion a bien vu le serveur, le navigateur, pkexec et le terminal.
        cmdlines = espion.contenus("cmdline")
        self.assertIn((self.pid, "cmdline"), espion.vus, "l'espion n'a jamais vu le serveur")
        for vu in ((b"xdg-open", b"pilotes-ouvrir-"), (b"pkexec", b"lexos-pilotes-maj"), (b"x-terminal-emulator",),
                   (b"serveur.py",)):
            with self.subTest(b" ".join(vu).decode()):
                self.assertTrue(any(all(m in c for m in vu) for c in cmdlines), f"l'espion n'a pas vu {vu}")
        self.assertIn((self.pid, "environ"), espion.vus, "l'environnement du serveur n'a pas été lu")
        #  /proc/*/cmdline et /proc/*/environ : ni le jeton, ni un sceau de ticket.
        for c in espion.contenus():
            self.assertNotIn(jeton, c, "jeton lu dans /proc : " + c[:200].decode(errors="replace"))
            for s in sceaux:
                self.assertNotIn(s, c, "sceau de ticket lu dans /proc")
        #  Et, sans course possible, ce que chaque faux a reçu (argv + environnement).
        enfants = (BANC / "enfants.jsonl").read_text(encoding="utf-8")
        self.assertIn('"nom": "xdg-open"', enfants)
        self.assertNotIn(self.jeton, enfants)
        for s in sceaux:
            self.assertNotIn(s.decode(), enfants)
        #  Ni dans le journal du lanceur et du serveur.
        for j in self.journaux:
            texte = j.read_text(encoding="utf-8", errors="replace")
            self.assertNotIn(self.jeton, texte, j.name)
            for s in sceaux:
                self.assertNotIn(s.decode(), texte, j.name)


class Polkit(unittest.TestCase):
    """L'action que pkexec choisit pour chaque verbe (pkexec.c:272-330)."""

    @classmethod
    def setUpClass(cls):
        cls.actions = []
        for a in ET.parse(POLITIQUE_POLKIT).getroot().iter("action"):
            notes = {n.get("key"): n.text for n in a.iter("annotate")}
            cls.actions.append({"id": a.get("id"), "notes": notes,
                                "actif": a.find("defaults/allow_active").text})

    def action_pour(self, argv1):
        #  Même règle que find_action_for_path : exec.path égal, et exec.argv1
        #  égal QUAND il est posé ; à défaut, org.freedesktop.policykit.exec.
        for a in self.actions:
            n = a["notes"]
            if n.get("org.freedesktop.policykit.exec.path") != serveur.AIDE_ROOT:
                continue
            if n.get("org.freedesktop.policykit.exec.argv1") not in (None, argv1):
                continue
            return a
        return None

    def test_installer_redemande_le_mot_de_passe(self):
        a = self.action_pour("installer")
        self.assertIsNotNone(a)
        self.assertEqual(a["actif"], "auth_admin", "auth_admin_keep : 5 min d'installations sans fenêtre")

    def test_verifier_a_son_action(self):
        a = self.action_pour("verifier")
        self.assertIsNotNone(a)
        self.assertNotEqual(a["id"], self.action_pour("installer")["id"])

    def test_chaque_action_vise_un_verbe(self):
        for a in self.actions:
            self.assertIn("org.freedesktop.policykit.exec.argv1", a["notes"], a["id"])


#  La page, sous node, avec un DOM minimal, un faux fetch, un faux
#  sessionStorage et un faux history. Le scénario (JSON) décrit l'adresse
#  (« hash »), le stockage de l'onglet, les réponses du serveur, et les
#  boutons à cliquer une fois la page chargée. « evenements » garde l'ordre
#  de ce que la page fait (replaceState, fetch).
RENDU_JS = r"""
"use strict";
const fs = require("fs"), vm = require("vm");
const [, , appjs, scenarioF] = process.argv;
const S = JSON.parse(fs.readFileSync(scenarioF, "utf8"));
const el = {}, appels = [], evenements = [], stockage = Object.assign({}, S.stockage || {});
const get = (id) => el[id] || (el[id] = { innerHTML: "", textContent: "", disabled: false, hidden: false,
  title: "", className: "", scrollTop: 0, scrollHeight: 0, ecouteurs: {},
  addEventListener(type, f) { this.ecouteurs[type] = f; } });
const location = { hash: S.hash || "", pathname: "/", search: "" };
const ctx = { document: { getElementById: get }, location, URLSearchParams, console,
  history: { replaceState(_e, _t, url) { evenements.push("replaceState " + url); location.hash = ""; } },
  sessionStorage: { getItem: (k) => (k in stockage ? stockage[k] : null),
                    setItem: (k, v) => { stockage[k] = String(v); } },
  setInterval: () => 1, clearInterval() {},
  fetch: async (url, o = {}) => {
    const methode = o.method || "GET";
    appels.push({ url, methode, entetes: o.headers || {} });
    evenements.push("fetch " + methode + " " + url);
    const r = (S.reponses || {})[methode + " " + url];
    if (r) return { status: r.status, json: async () => r.corps };
    const corps = url === "/api/etat" ? S.etat : url === "/api/tache" ? S.tache : { lance: true };
    return { status: 200, json: async () => corps };
  } };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(appjs, "utf8"), ctx);
setTimeout(() => {
  for (const id of S.clics || []) get(id).ecouteurs.click();
  setTimeout(() => {
    const sortie = {};
    for (const [id, e] of Object.entries(el)) sortie[id] = { html: e.innerHTML, texte: e.textContent,
      disabled: e.disabled, title: e.title, hidden: e.hidden };
    console.log(JSON.stringify({ el: sortie, appels, evenements, stockage, hash: location.hash }));
  }, 100);
}, 100);
"""

#  Ce que la page reçoit par défaut : un ticket dans l'adresse, que le
#  serveur échange contre le jeton.
TICKET_PAGE = "0123456789abcdef0123456789abcdef." + "ab" * 32
JETON_PAGE = "JETON-DE-LA-PAGE"
CLE_JETON = "lexos-pilotes-jeton"


class Page(unittest.TestCase):
    """app.js sous node : ce que la page AFFICHE, pas seulement ce que l'API rend."""

    @classmethod
    def setUpClass(cls):
        if not NODE:
            raise unittest.SkipTest("node absent : la page n'est pas rendue ici (la CI l'a)")
        cls.rendu = BANC / "rendu.js"
        cls.rendu.write_text(RENDU_JS, encoding="utf-8")

    def etat(self, **remplace):
        e = {"cartes": [{"nom": "NVIDIA GB206", "marque": "NVIDIA", "pilote": "nvidia"}],
             "nvidia": {"version": "595.71.05", "paquet": "595.71.05-1", "branche_epinglee": "595",
                        "plus_recente_publiee": "595.91.07-1"},
             "mesa": "25.0.7-2~bpo13+1",
             "noyau": {"en_service": "6.16.12+bpo-amd64", "plus_recent": "6.16.12+bpo-amd64",
                       "module_nvidia_plus_recent": True},
             "secure_boot": False, "signature": None, "verifie_le": 1000, "maintenant": 1060,
             "mises_a_jour": {"disponible": True, "raison": None, "retraits": [],
                              "paquets": [{"paquet": "nvidia-driver-cuda", "installe": "595.71.05-1",
                                           "cible": "595.91.07-1", "source": "cuda"}]},
             "raisons": {}}
        e.update(remplace)
        return e

    def rendre(self, etat, tache=None, hash_=f"#o={TICKET_PAGE}", stockage=None, reponses=None, clics=()):
        tout = {"POST /api/entree": {"status": 200, "corps": {"jeton": JETON_PAGE}}}
        tout.update(reponses or {})
        scenario = {"etat": etat, "tache": tache or {"action": None, "en_cours": False, "journal": [],
                                                      "resultat": None},
                    "hash": hash_, "stockage": stockage or {}, "reponses": tout, "clics": list(clics)}
        (BANC / "page.json").write_text(json.dumps(scenario), encoding="utf-8")
        r = subprocess.run([NODE, str(self.rendu), str(APP_JS), str(BANC / "page.json")],
                           capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_bouton_actif_quand_tout_va_bien(self):
        el = self.rendre(self.etat())["el"]
        self.assertFalse(el["btn-installer"]["disabled"])
        self.assertTrue(el["raison-actions"]["hidden"])

    def test_tache_deja_en_cours_reprise(self):
        el = self.rendre(self.etat(), {"action": "installer", "en_cours": True,
                                       "journal": ["» Installation…"], "resultat": None})["el"]
        for b in ("btn-installer", "btn-verifier"):
            self.assertTrue(el[b]["disabled"], b)
            self.assertIn("en cours", el[b]["title"])
        self.assertIn("en cours", el["raison-actions"]["texte"])
        self.assertFalse(el["raison-actions"]["hidden"], "la raison est écrite EN CLAIR, pas dans un élément caché")
        self.assertIn("» Installation…", el["journal"]["texte"])

    def test_clic_pendant_une_tache_lancee_ailleurs_suit(self):
        #  Le serveur répond 409 (une tâche lancée par un autre onglet) : la
        #  page suit cette tâche et désactive ses boutons, en disant pourquoi.
        r409 = {"status": 409, "corps": {"lance": False, "en_cours": True, "message": "Une tâche est déjà en cours."}}
        el = self.rendre(self.etat(), reponses={"POST /api/installer": r409}, clics=["btn-installer"])["el"]
        self.assertTrue(el["btn-installer"]["disabled"], "409 : la page suit la tâche déjà en cours")
        self.assertIn("en cours", el["btn-installer"]["title"])
        self.assertFalse(el["journal"]["hidden"])

    def test_indisponible_avec_raison_pas_a_jour(self):
        m = {"disponible": False, "raison": "la liste des paquets n'a jamais été téléchargée",
             "paquets": [], "retraits": []}
        el = self.rendre(self.etat(mises_a_jour=m, verifie_le=None))["el"]
        self.assertNotIn("À jour", el["maj"]["html"])
        self.assertIn("Indisponible", el["maj"]["html"])
        self.assertIn("jamais été téléchargée", el["maj"]["html"])
        self.assertTrue(el["btn-installer"]["disabled"])
        self.assertIn("jamais été téléchargée", el["btn-installer"]["title"])
        self.assertFalse(el["raison-actions"]["hidden"])

    def test_retrait_bouton_desactive_avec_raison(self):
        m = {"disponible": True, "raison": None, "retraits": ["monappli"],
             "paquets": self.etat()["mises_a_jour"]["paquets"]}
        el = self.rendre(self.etat(mises_a_jour=m))["el"]
        self.assertTrue(el["btn-installer"]["disabled"])
        self.assertIn("monappli", el["btn-installer"]["title"])
        self.assertIn("retirerait", el["maj"]["html"])

    def test_mesures_absentes_disent_pourquoi(self):
        e = self.etat(secure_boot=None, mesa=None,
                      noyau={"en_service": "6.16", "plus_recent": None, "module_nvidia_plus_recent": None},
                      raisons={"secure_boot": "mokutil est introuvable", "mesa": "dpkg-query a échoué",
                               "noyau": "/lib/modules est illisible"})
        html = self.rendre(e)["el"]["pilote"]["html"]
        for raison in ("mokutil est introuvable", "dpkg-query a échoué", "/lib/modules est illisible"):
            self.assertIn(raison, html)
        self.assertNotIn("<dd>—</dd>", html)
        self.assertNotIn("✗ absent", html, "illisible n'est pas absent")

    def test_chaque_raison_de_la_page_affichee(self):
        #  Le paquet NVIDIA inconnu, l'épingle illisible, le module du
        #  prochain noyau illisible (le noyau, LUI, est connu : sa ligne ne
        #  porte pas la raison), puis lspci en échec.
        e = self.etat(cartes=[{"nom": "NVIDIA GB206", "marque": "NVIDIA", "pilote": None}],
                      nvidia={"version": None, "paquet": None, "branche_epinglee": None,
                              "plus_recente_publiee": None},
                      noyau={"en_service": "6.16", "plus_recent": "7.2.9", "module_nvidia_plus_recent": None},
                      raisons={"paquet_nvidia": "R-PAQUET", "branche_epinglee": "R-EPINGLE", "noyau": "R-MODULE"})
        html = self.rendre(e)["el"]["pilote"]["html"]
        for r in ("R-PAQUET", "R-EPINGLE", "R-MODULE"):
            with self.subTest(r):
                self.assertIn(r, html)
        self.assertNotIn("aucune (la plus récente)", html, "épingle illisible n'est pas « aucune »")
        cartes = self.rendre(self.etat(cartes=[], raisons={"cartes": "R-LSPCI"}))["el"]["cartes"]["html"]
        self.assertIn("R-LSPCI", cartes)
        self.assertIn("Indisponible", cartes)
        self.assertNotIn("Aucune carte", cartes, "lspci en échec n'est pas « aucune carte »")

    def test_jeton_envoye_sur_toute_l_api(self):
        appels_ = self.rendre(self.etat())["appels"]
        self.assertEqual(appels_[0]["url"], "/api/entree", "le ticket s'échange avant tout")
        self.assertEqual(appels_[0]["entetes"].get("X-Ticket"), TICKET_PAGE)
        self.assertNotIn("X-Jeton", appels_[0]["entetes"])
        self.assertGreater(len(appels_), 1)
        for a in appels_[1:]:
            self.assertEqual(a["entetes"].get("X-Jeton"), JETON_PAGE, a["url"])
            self.assertNotIn(JETON_PAGE, a["url"], "jamais le jeton dans une adresse")

    def test_ticket_retire_de_l_adresse_avant_l_echange(self):
        sortie = self.rendre(self.etat())
        ev = sortie["evenements"]
        self.assertIn("replaceState /", ev)
        self.assertLess(ev.index("replaceState /"), ev.index("fetch POST /api/entree"),
                        "le ticket quitte la barre d'adresse avant d'être échangé")
        self.assertEqual(sortie["hash"], "")
        self.assertFalse([e for e in ev if JETON_PAGE in e or TICKET_PAGE in e], "ni jeton ni ticket dans une adresse")
        self.assertEqual(sortie["stockage"].get(CLE_JETON), JETON_PAGE, "gardé par l'onglet pour F5")

    def test_rechargement_garde_le_jeton_de_l_onglet(self):
        sortie = self.rendre(self.etat(), hash_="", stockage={CLE_JETON: "JETON-GARDE"})
        self.assertNotIn("/api/entree", [a["url"] for a in sortie["appels"]])
        for a in sortie["appels"]:
            self.assertEqual(a["entetes"].get("X-Jeton"), "JETON-GARDE", a["url"])

    def test_ticket_deja_depense_jeton_de_l_onglet(self):
        #  Bouton Précédent : le ticket a déjà servi (403), l'onglet a son jeton.
        sortie = self.rendre(self.etat(), stockage={CLE_JETON: "JETON-GARDE"},
                             reponses={"POST /api/entree": {"status": 403, "corps": {}}})
        for a in sortie["appels"][1:]:
            self.assertEqual(a["entetes"].get("X-Jeton"), "JETON-GARDE", a["url"])
        self.assertFalse(sortie["el"]["btn-installer"]["disabled"])

    def test_sans_jeton_le_dit(self):
        sortie = self.rendre(self.etat(), hash_="", reponses={"GET /api/etat": {"status": 403, "corps": {}},
                                                               "GET /api/tache": {"status": 403, "corps": {}}})
        self.assertIn("jeton de session", sortie["el"]["cartes"]["texte"])

    def test_aucun_referer_ni_titre_qui_porte_le_jeton(self):
        html = (DOSSIER / "web/index.html").read_text(encoding="utf-8")
        self.assertRegex(html, r'<meta name="referrer" content="no-referrer">')
        self.assertNotRegex(html, r"https?://", "la page ne charge rien d'ailleurs")
        #  Le titre de la fenêtre (que le gestionnaire de fenêtres montre à
        #  tous) est fixe : app.js ne le réécrit jamais.
        self.assertIn("<title>LexOS Pilotes</title>", html)
        self.assertNotIn("document.title", APP_JS.read_text(encoding="utf-8"))


class SignatureMOK(unittest.TestCase):
    """Le guide d'inscription du certificat LexOS : quelle étape montrer.

    modinfo et mokutil sont remplacés : on décrit une machine, on lit l'étape.
    """

    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        d = Path(self.dossier.name)
        (d / "build.conf").write_text('LEXOS_SIGNATURE_CLE_ID="43:CF:A1:4C"\n', encoding="utf-8")
        (d / "lexos-mok.der").write_bytes(b"\x30\x82")
        (d / "cmdline").write_text("boot=live components\n", encoding="utf-8")
        (d / "modules").write_text("snd 1 - Live 0x0\n", encoding="utf-8")
        self.anciens = (moteur.BUILD_CONF, moteur.CERT_LEXOS, moteur.CMDLINE, moteur.PROC_MODULES,
                        moteur._executer, moteur._cle_inscrite)
        moteur.BUILD_CONF, moteur.CERT_LEXOS = d / "build.conf", d / "lexos-mok.der"
        moteur.CMDLINE, moteur.PROC_MODULES = d / "cmdline", d / "modules"
        self.cle_module = "43:cf:a1:4c"
        self.inscrite = False
        moteur._executer = lambda cmd, timeout=10.0: self.cle_module + "\n" if "sig_key" in cmd else None
        moteur._cle_inscrite = lambda cert: self.inscrite

    def tearDown(self):
        (moteur.BUILD_CONF, moteur.CERT_LEXOS, moteur.CMDLINE, moteur.PROC_MODULES,
         moteur._executer, moteur._cle_inscrite) = self.anciens
        self.dossier.cleanup()

    def test_signe_lexos_pas_inscrit(self):
        s = moteur.signature_pilote(True)
        self.assertEqual(s["etape"], "inscrire-lexos")
        self.assertTrue(s["signe_par_lexos"])
        self.assertTrue(s["en_live"])

    def test_inscrit_mais_pas_charge(self):
        self.inscrite = True
        self.assertEqual(moteur.signature_pilote(True)["etape"], "redemarrer")

    def test_charge(self):
        moteur.PROC_MODULES.write_text("nvidia 1 - Live 0x0\n", encoding="utf-8")
        self.assertEqual(moteur.signature_pilote(True)["etape"], "ok")

    def test_secure_boot_inactif(self):
        self.assertEqual(moteur.signature_pilote(False)["etape"], "sans-secure-boot")

    def test_autre_cle(self):
        self.cle_module = "DE:AD:BE:EF"
        s = moteur.signature_pilote(True)
        self.assertEqual(s["etape"], "cle-machine")
        self.assertFalse(s["signe_par_lexos"])

    def test_assistant_ligne_fixe(self):
        # La page ne fournit rien : la commande lancée est figée dans le serveur.
        self.assertEqual(serveur.ASSISTANT_SIGNATURE[0], "x-terminal-emulator")
        self.assertIn("sudo lexos-signer-pilote", serveur.ASSISTANT_SIGNATURE[-1])


class GardeFou(unittest.TestCase):
    """Le banc refuse de tourner si le PATH n'est plus celui des faux."""

    def test_refus_si_vrai_pkexec_devant(self):
        autre = BANC / "pas-les-faux"
        autre.mkdir(exist_ok=True)
        (autre / "pkexec").write_text("#!/bin/false\n")
        (autre / "pkexec").chmod(0o755)
        ancien = os.environ["PATH"]
        os.environ["PATH"] = f"{autre}:{ancien}"
        try:
            with self.assertRaises(RuntimeError):
                _garde_faux_outils()
        finally:
            os.environ["PATH"] = ancien
        _garde_faux_outils()


if __name__ == "__main__":
    unittest.main(verbosity=2)
