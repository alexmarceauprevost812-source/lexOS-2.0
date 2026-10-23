#!/usr/bin/env python3
"""LE CODEX ET GITHUB — récupérer un dépôt avec le jeton, puis le repousser.

ALEX : « j'aimerais que le Codex soit capable, avec le token, de récupérer
les repos et être capable de pousser sur GitHub ».

Ce banc ne relit pas le code : il fait tourner les vrais outils de l'agent
(turbo_rea.TurboREA) contre un faux GitHub en mémoire (même API REST), et
regarde ce qui arrive VRAIMENT sur le dépôt :
  1. list_github_repos voit les dépôts privés avec le jeton ;
  2. clone_github récupère un dépôt privé, garde les scripts exécutables,
     ne recrée pas les liens symboliques, et se souvient du dépôt d'origine ;
  3. push_github renvoie un changement AU MÊME dépôt, sur SA branche,
     n'envoie que le fichier modifié, n'efface rien, et jamais le .env ;
  4. sans jeton, un message clair (pas de plantage).
"""
from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path

ICI = Path(__file__).resolve().parent
LIB = ICI.parent / "config/includes.chroot/usr/lib/lexos/ti-lex-ia"
sys.path.insert(0, str(LIB))

import github_envoi  # noqa: E402
import turbo_rea      # noqa: E402

REUSSIS = ECHOUES = 0


def verifier(cond: bool, texte: str) -> None:
    global REUSSIS, ECHOUES
    if cond:
        REUSSIS += 1
        print(f"  ✅ {texte}")
    else:
        ECHOUES += 1
        print(f"  ❌ {texte}")


def sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


# ─── Un faux GitHub : un dépôt privé alex/secret, branche « dev » + « main » ───
class FauxGitHub:
    JETON = "ghp_faux"

    def __init__(self):
        self.blobs: dict[str, bytes] = {}
        self.arbres: dict[str, list[dict]] = {}
        self.commits: dict[str, dict] = {}
        self.refs: dict[str, str] = {}
        self.envoyes: list[str] = []
        fichiers = {"README.md": (b"# secret\n", "100644"), "build.sh": (b"#!/bin/sh\necho ok\n", "100755"),
                    "src/app.py": (b"print('v1')\n", "100644"), "docs/garde.md": (b"ne pas effacer\n", "100644")}
        entrees = []
        for chemin, (data, mode) in fichiers.items():
            self.blobs[sha(data)] = data
            entrees.append({"path": chemin, "mode": mode, "type": "blob", "sha": sha(data)})
        self.arbres["t1"] = entrees
        self.commits["c1"] = {"sha": "c1", "tree": {"sha": "t1"}}
        self.refs = {"main": "c1", "dev": "c1"}

    def zip(self) -> bytes:
        tampon = io.BytesIO()
        with zipfile.ZipFile(tampon, "w") as z:
            for e in self.arbres[self.commits[self.refs["dev"]]["tree"]["sha"]]:
                info = zipfile.ZipInfo("alex-secret-c1/" + e["path"])
                info.external_attr = (0o100755 if e["mode"] == "100755" else 0o100644) << 16
                z.writestr(info, self.blobs[e["sha"]])
            lien = zipfile.ZipInfo("alex-secret-c1/raccourci")
            lien.external_attr = 0o120777 << 16
            z.writestr(lien, "/etc/passwd")
        return tampon.getvalue()

    def appel(self, jeton, methode, chemin, corps=None, ok404=False):
        if jeton != self.JETON:
            raise github_envoi.ErreurGitHub("GitHub refuse le jeton")
        base = "/repos/alex/secret"
        if chemin == "/user":
            return {"login": "alex"}
        if chemin.startswith("/user/repos"):
            if "page=1" not in chemin:
                return []
            return [{"full_name": "alex/secret", "private": True, "default_branch": "main",
                     "permissions": {"push": True}, "pushed_at": "2026-10-23T00:00:00Z", "description": "privé"},
                    {"full_name": "alex/lexOS-2.0", "private": False, "default_branch": "main",
                     "permissions": {"push": True}, "pushed_at": "2026-10-22T00:00:00Z"}]
        if chemin == base:
            return {"default_branch": "main", "html_url": "https://github.com/alex/secret"}
        if chemin.startswith(base + "/git/ref/heads/"):
            b = chemin.rsplit("/", 1)[1]
            return {"object": {"sha": self.refs[b]}} if b in self.refs else None
        if chemin.startswith(base + "/git/commits/") and methode == "GET":
            return self.commits[chemin.rsplit("/", 1)[1]]
        if chemin.startswith(base + "/git/trees/") and methode == "GET":
            return {"tree": self.arbres[chemin.rsplit("/", 1)[1].split("?")[0]]}
        if chemin == base + "/git/blobs":
            data = base64.b64decode(corps["content"])
            self.blobs[sha(data)] = data
            self.envoyes.append(sha(data))
            return {"sha": sha(data)}
        if chemin == base + "/git/trees":
            arbre = {e["path"]: e for e in (self.arbres[corps["base_tree"]] if "base_tree" in corps else [])}
            arbre.update({e["path"]: e for e in corps["tree"]})
            n = f"t{len(self.arbres) + 1}"
            self.arbres[n] = list(arbre.values())
            return {"sha": n}
        if chemin == base + "/git/commits":
            n = f"c{len(self.commits) + 1}"
            self.commits[n] = {"sha": n, "tree": {"sha": corps["tree"]}, "message": corps["message"]}
            return {"sha": n}
        if chemin.startswith(base + "/git/refs/heads/") and methode == "PATCH":
            self.refs[chemin.rsplit("/", 1)[1]] = corps["sha"]
            return {}
        raise AssertionError(f"appel inattendu : {methode} {chemin}")

    def contenu(self, branche: str) -> dict[str, tuple[bytes, str]]:
        arbre = self.arbres[self.commits[self.refs[branche]]["tree"]["sha"]]
        return {e["path"]: (self.blobs[e["sha"]], e["mode"]) for e in arbre}


def main() -> int:
    gh = FauxGitHub()
    github_envoi._appel = gh.appel
    turbo_rea._telecharger = lambda url, limite, accept="*/*", entetes=None, progres=None: (
        (gh.zip(), "application/zip") if entetes and entetes.get("Authorization") == f"Bearer {gh.JETON}"
        else (_ for _ in ()).throw(turbo_rea.ErreurOutil("404")))
    os.environ["GITHUB_TOKEN"] = gh.JETON

    with tempfile.TemporaryDirectory() as tmp:
        projet = Path(tmp) / "mon-projet"
        projet.mkdir()
        agent = turbo_rea.TurboREA(projet, "http://127.0.0.1:1", "x", None, None, lambda e: None)
        noms = {o["function"]["name"] for o in turbo_rea.OUTILS}

        print("\n═══ 1. Le Codex voit tes dépôts ═══")
        verifier({"list_github_repos", "clone_github", "push_github"} <= noms, "les trois outils GitHub sont offerts au modèle")
        r = agent.appeler("list_github_repos", {})
        verifier("alex/secret · privé" in r and "alex/lexOS-2.0" in r, "les dépôts privés sont listés avec le jeton")
        verifier("alex/secret" in agent.appeler("list_github_repos", {"search": "sec"})
                 and "lexOS" not in agent.appeler("list_github_repos", {"search": "sec"}), "le filtre par nom marche")

        print("\n═══ 2. Il récupère un dépôt privé ═══")
        r = agent.appeler("clone_github", {"url": "alex/secret", "branch": "dev"})
        d = projet / "secret"
        verifier(r.startswith("Dépôt alex/secret") and (d / "src/app.py").is_file(), "le dépôt privé est cloné avec le jeton")
        verifier(os.access(d / "build.sh", os.X_OK), "build.sh reste exécutable")
        verifier(not (d / "raccourci").exists(), "le lien symbolique du zip n'est pas recréé")
        lien = github_envoi.lire_lien(d)
        verifier(lien.get("depot") == "alex/secret" and lien.get("branche") == "dev" and not lien.get("miroir"),
                 "le clone se souvient : alex/secret, branche dev, jamais miroir")

        print("\n═══ 3. Il repousse au même endroit ═══")
        (d / "src/app.py").write_text("print('v2')\n")
        (d / ".env").write_text("SECRET=1\n")
        (d / "docs/garde.md").unlink()                        # effacé localement…
        r = agent.appeler("push_github", {"path": "secret", "message": "v2 depuis le Codex"})
        dev, main_ = gh.contenu("dev"), gh.contenu("main")
        verifier(r.startswith("Poussé sur alex/secret (branche dev)"), "poussé sur alex/secret, branche dev")
        verifier(dev["src/app.py"][0] == b"print('v2')\n", "le changement est sur GitHub")
        verifier(main_["src/app.py"][0] == b"print('v1')\n", "la branche main n'est pas touchée")
        verifier(len(gh.envoyes) == 1, "un seul fichier envoyé (les inchangés ne repartent pas)")
        verifier(".env" not in dev, "le .env ne part jamais")
        verifier("docs/garde.md" in dev, "rien n'est effacé sur un dépôt qui existait déjà")
        verifier(dev["build.sh"][1] == "100755", "build.sh garde son mode exécutable sur GitHub")
        verifier(gh.commits[gh.refs["dev"]]["message"] == "v2 depuis le Codex", "le message de commit est gardé")
        r = agent.appeler("push_github", {"path": "secret", "message": "encore"})
        verifier(r.startswith("Déjà à jour"), "un 2e envoi sans changement ne crée pas de commit vide")

        print("\n═══ 4. Sans jeton ═══")
        del os.environ["GITHUB_TOKEN"]
        r = agent.appeler("push_github", {"message": "x"})
        verifier(r.startswith("Erreur") and "GITHUB_TOKEN" in r, "message clair : ajoute GITHUB_TOKEN")
        r = agent.appeler("list_github_repos", {})
        verifier(r.startswith("Erreur") and "GITHUB_TOKEN" in r, "pareil pour la liste des dépôts")

    print(f"\n{REUSSIS} réussis, {ECHOUES} échoués")
    return 1 if ECHOUES else 0


if __name__ == "__main__":
    sys.exit(main())
