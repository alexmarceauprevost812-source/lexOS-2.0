"""LexOS · 🔌 Les IA d'une clé USB branchée, utilisables tout de suite.

ALEX : « capable de lire les IA quand elles sont branchées au PC, capable de
travailler avec ». Le Moteur installé dans LexOS ne voyait que les modèles de
LexOS (OLLAMA_MODELS). Une clé LEXOS branchée, avec ses modèles dans
lexos-ia/ia/modeles, restait invisible.

COMMENT. Un veilleur regarde les clés montées (/media/<compte>/…,
/run/media/<compte>/…) toutes les quelques secondes. Pour chaque dossier de
modèles Ollama trouvé dessus, il démarre UN Ollama de plus, à part, sur un
port libre, avec OLLAMA_MODELS = ce dossier : les modèles restent SUR la clé,
rien n'est copié. Ses modèles apparaissent dans les listes du Moteur avec le
préfixe « usb: » (affiché 🔌), et les demandes qui les nomment partent vers
cet Ollama-là. La clé débranchée : son Ollama s'arrête, ses modèles quittent
les listes.

PRUDENCES.
  · OLLAMA_NOPRUNE=1 : un Ollama qui démarre peut faire le ménage dans les
    fichiers « orphelins » de son dossier — jamais sur la clé de quelqu'un.
  · On ne supprime jamais un modèle d'une clé depuis le Moteur.
  · Le moteur de la clé (exFAT, sans droit d'exécution) est copié une fois
    dans le cache du PC, comme le fait déjà trouver_ollama() ; l'Ollama de
    LexOS est préféré quand il existe.
"""
from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import threading
import time
import http.client
from pathlib import Path

def _monter_cles(journal) -> None:
    """Monte les clés USB pas encore montées, comme un disque dur."""
    global _MONTEUR
    if _MONTEUR is None:
        try:
            import importlib.machinery, importlib.util
            chargeur = importlib.machinery.SourceFileLoader("lexos_monter_cles", "/usr/bin/lexos-monter-cles")
            spec = importlib.util.spec_from_loader("lexos_monter_cles", chargeur)
            _MONTEUR = importlib.util.module_from_spec(spec)
            chargeur.exec_module(_MONTEUR)
        except (OSError, ImportError, SyntaxError):
            _MONTEUR = False
    if _MONTEUR:
        try:
            _MONTEUR.monter(journal)
        except Exception as e:                     # jamais tomber
            journal(f"[clés IA] montage : {e}")


_MONTEUR = None
PREFIXE = "usb:"
PORTS = range(11451, 11471)
SOUS_DOSSIERS = ("lexos-ia/ia/modeles", "LEXOS/lexos-ia/ia/modeles", "ollama-models",
                 ".ollama/models", "ollama/models", "models")


def _compter(d: Path) -> int:
    n = 0
    for sous in ("manifests", "manifests-v2"):
        m = d / sous
        if m.is_dir():
            for _, _, f in os.walk(m):
                n += len(f)
    return n


def _racines_montees() -> list[Path]:
    try:
        import pwd
        compte = pwd.getpwuid(os.getuid()).pw_name
    except (ImportError, KeyError):
        compte = os.environ.get("USER", "")
    bases = [Path("/media") / compte, Path("/run/media") / compte, Path("/media")]
    out = []
    for b in bases:
        try:
            for p in b.iterdir():
                if p.is_dir() and os.path.ismount(p) and p not in out:
                    out.append(p)
        except OSError:
            continue
    return out


def chercher(exclure: Path | None = None) -> dict[Path, str]:
    """{dossier de modèles: nom de la clé} pour toutes les clés branchées."""
    trouves: dict[Path, str] = {}
    for racine in _racines_montees():
        for sous in SOUS_DOSSIERS:
            d = racine / sous
            try:
                if d.is_dir() and _compter(d) and (exclure is None or d.resolve() != exclure.resolve()):
                    trouves[d] = racine.name
                    break
            except OSError:
                continue
    return trouves


def _repond(port: int) -> bool:
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        c.request("GET", "/api/version")
        ok = c.getresponse().status == 200
        c.close()
        return ok
    except OSError:
        return False


def _port_libre(pris: set[int]) -> int | None:
    import socket
    for p in PORTS:
        if p in pris:
            continue
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    return None


def _binaire(dossier: Path, cache: Path) -> Path | None:
    systeme = shutil.which("ollama")
    if systeme:
        return Path(systeme)
    # Le moteur de la clé elle-même : lexos-ia/ia/ollama-linux-<arch>/bin/ollama
    arch = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64",
            "arm64": "arm64"}.get(platform.machine().lower(), "amd64")
    for parent in [dossier, *dossier.parents][:4]:
        src = parent / f"ollama-linux-{arch}"
        b = src / "bin" / "ollama"
        if b.is_file():
            if os.access(b, os.X_OK):
                return b
            local = cache / f"ollama-linux-{arch}"
            lb = local / "bin" / "ollama"
            try:
                if not lb.is_file() or lb.stat().st_size != b.stat().st_size:
                    shutil.rmtree(local, ignore_errors=True)
                    shutil.copytree(src, local)
                    lb.chmod(0o755)
                return lb
            except OSError:
                return None
    return None


class ClesIA:
    """Les Ollama des clés branchées : {dossier: {"port", "proc", "nom"}}."""

    def __init__(self, cache: Path, exclure: Path | None = None, journal=print):
        self.cache = cache
        self.exclure = exclure
        self.dire = journal
        self.actifs: dict[Path, dict] = {}
        self.verrou = threading.Lock()
        self.fin = threading.Event()
        self.carte: dict[str, int] = {}          # « usb:qwen3:8b » → port

    # ── le veilleur ──
    def demarrer(self) -> None:
        threading.Thread(target=self._veiller, name="lexos-cles-ia", daemon=True).start()

    def _veiller(self) -> None:
        while not self.fin.is_set():
            try:
                self._tour()
            except Exception as e:                 # jamais tomber : le Moteur continue
                self.dire(f"[clés IA] {e}")
            self.fin.wait(5)

    def _tour(self) -> None:
        #  ALEX (2026-11-01) : « connecter la clé USB comme si elle serait un
        #  disque dur » — une clé branchée mais pas montée est montée d'abord
        #  (udisks2, voir /usr/bin/lexos-monter-cles), puis ses modèles lus.
        _monter_cles(self.dire)
        vus = chercher(self.exclure)
        with self.verrou:
            for d in [d for d in self.actifs if d not in vus]:
                self._arreter(d, "débranchée")
            for d, nom in vus.items():
                a = self.actifs.get(d)
                if a:
                    if a["proc"].poll() is None:
                        continue
                    #  Pas de moteur, ou il est tombé : on réessaie, mais au
                    #  plus une fois par minute — pas un message toutes les 5 s.
                    if a["port"] is None or time.time() - a["t"] < 60:
                        continue
                    self._arreter(d, "tombée")
                self._lancer(d, nom)

    def _lancer(self, d: Path, nom: str) -> None:
        b = _binaire(d, self.cache)
        if not b:
            self.dire(f"🔌 Clé « {nom} » : des modèles, mais aucun moteur Ollama pour les lire")
            self.actifs[d] = {"port": None, "proc": _Mort(), "nom": nom, "t": time.time()}
            return
        port = _port_libre({a["port"] for a in self.actifs.values() if a["port"]})
        if not port:
            return
        env = dict(os.environ, OLLAMA_MODELS=str(d), OLLAMA_HOST=f"127.0.0.1:{port}", OLLAMA_NOPRUNE="1")
        self.cache.mkdir(parents=True, exist_ok=True)
        log = open(self.cache / f"ollama-cle-{port}.log", "wb")
        proc = subprocess.Popen([str(b), "serve"], env=env, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True)
        t0 = time.time()
        while time.time() - t0 < 60 and proc.poll() is None and not _repond(port):
            time.sleep(.5)
        if proc.poll() is not None:
            self.dire(f"🔌 Clé « {nom} » : le moteur n'a pas démarré (journal : {log.name})")
        else:
            self.dire(f"🔌 Clé « {nom} » branchée : ses modèles sont prêts (port {port})")
        self.actifs[d] = {"port": port, "proc": proc, "nom": nom, "t": time.time()}

    def _arreter(self, d: Path, pourquoi: str) -> None:
        a = self.actifs.pop(d, None)
        if not a:
            return
        p = a["proc"]
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(8)
            except subprocess.TimeoutExpired:
                p.kill()
        self.carte = {k: v for k, v in self.carte.items() if v != a["port"]}
        self.dire(f"🔌 Clé « {a['nom']} » {pourquoi} : ses modèles quittent les listes")

    def arreter_tout(self) -> None:
        self.fin.set()
        with self.verrou:
            for d in list(self.actifs):
                self._arreter(d, "fermée")

    # ── pour le serveur du Moteur ──
    def tags(self) -> list[dict]:
        """Les modèles des clés, renommés « usb:… », avec le nom de la clé."""
        out, carte = [], {}
        with self.verrou:
            actifs = [(a["port"], a["nom"]) for a in self.actifs.values() if a["port"]]
        for port, nom in actifs:
            try:
                c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
                c.request("GET", "/api/tags")
                modeles = json.loads(c.getresponse().read() or b"{}").get("models") or []
                c.close()
            except (OSError, ValueError):
                continue
            for m in modeles:
                n = PREFIXE + str(m.get("name") or m.get("model") or "")
                if n in carte:
                    continue
                carte[n] = port
                out.append({**m, "name": n, "model": n, "lexos_cle": nom})
        self.carte = carte
        return out

    def route(self, nom: str | None) -> tuple[int, str] | None:
        """« usb:qwen3:8b » → (port de sa clé, « qwen3:8b ») ; None sinon."""
        if not nom or not str(nom).startswith(PREFIXE):
            return None
        if nom not in self.carte:
            self.tags()                            # une clé branchée depuis la dernière liste
        port = self.carte.get(nom)
        return (port, str(nom)[len(PREFIXE):]) if port else None


class _Mort:
    def poll(self):
        return 0

    def terminate(self):
        pass
