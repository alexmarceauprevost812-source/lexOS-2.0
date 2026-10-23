"""LexOS · ⬆️ Envoyer un projet sur GitHub — sans git, avec le jeton du coffre.

ALEX : « capable d'envoyer nos projets à GitHub avec un token ». Comme le
📦 Cloner (turbo_rea.cloner_github), tout passe par l'API de GitHub : le
Moteur tourne aussi depuis la clé sur un Windows où git n'est pas installé.

LE JETON. C'est GITHUB_TOKEN, une variable GLOBALE du coffre (🔑 Variables),
déjà chargée dans l'environnement quand le Moteur est déverrouillé — la même
que le Cloner utilise pour les dépôts privés. Il ne s'écrit nulle part
ailleurs : ni dans le projet, ni dans un fichier de configuration.

CE QUI PART. Tous les fichiers du projet, SAUF :
  · les secrets : .env, .env.* (le coffre les écrit EN CLAIR — jamais sur GitHub)
  · les copies de sécurité du Codex (*.avant-codex) et ce fichier-ci de lien
  · les dossiers lourds ou générés (SAUTER : node_modules, .venv, .git…)
  · ce que le .gitignore du projet exclut (motifs simples)
Un fichier inchangé n'est pas renvoyé : on compare l'empreinte git (sha1 du
blob) avec celle déjà sur GitHub.

NE JAMAIS EFFACER LE TRAVAIL DE QUELQU'UN D'AUTRE. Un dépôt que LexOS a créé
(lien gardé dans .lexos-github.json, « miroir ») est un MIROIR du projet :
un fichier effacé dans le projet s'efface sur GitHub. Un dépôt qui existait
déjà reçoit les fichiers PAR-DESSUS ce qu'il contient, à chaque envoi :
rien n'y est jamais effacé.
"""
from __future__ import annotations

import base64
import fnmatch
import hashlib
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.github.com"
LIEN = ".lexos-github.json"
NOM_DEPOT = re.compile(r"^[A-Za-z0-9_.-]{1,100}$")
MAX_FICHIERS = 3000
MAX_FICHIER = 50 * 1024 * 1024        # GitHub refuse au-delà de 100 Mo ; on reste prudent
MAX_TOTAL = 400 * 1024 * 1024


class ErreurGitHub(Exception):
    pass


# ─── L'API ─────────────────────────────────────────────────────────────────
def _appel(jeton: str, methode: str, chemin: str, corps: dict | None = None, ok404: bool = False):
    req = urllib.request.Request(API + chemin, method=methode,
                                 data=json.dumps(corps).encode() if corps is not None else None)
    req.add_header("Authorization", f"Bearer {jeton}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "LexOS-Moteur")
    if corps is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            brut = r.read()
            return json.loads(brut) if brut else {}
    except urllib.error.HTTPError as e:
        if ok404 and e.code == 404:
            return None
        try:
            msg = json.loads(e.read() or b"{}").get("message", "")
        except ValueError:
            msg = ""
        if e.code == 401:
            raise ErreurGitHub("GitHub refuse le jeton : GITHUB_TOKEN est expiré ou faux (🔑 Variables)") from None
        if e.code == 403 and "rate limit" in msg.lower():
            raise ErreurGitHub("GitHub limite les envois pour l'instant : réessaie dans quelques minutes") from None
        if e.code in (403, 404):
            raise ErreurGitHub("Le jeton n'a pas le droit d'écrire ici : il lui faut l'accès « repo » "
                               "(ou, jeton fin : « Contents » et « Administration » en écriture)") from None
        if e.code == 409:
            raise ErreurGitHub("vide") from None
        if e.code == 422:
            raise ErreurGitHub(f"GitHub a refusé : {msg or 'requête invalide'}") from None
        raise ErreurGitHub(f"GitHub répond {e.code} : {msg or e.reason}") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ErreurGitHub("Impossible de joindre GitHub : vérifie la connexion internet") from None


# ─── Les fichiers à envoyer ────────────────────────────────────────────────
def _motifs_gitignore(projet: Path) -> list[str]:
    gi = projet / ".gitignore"
    try:
        lignes = gi.read_text("utf-8", errors="replace").splitlines() if gi.is_file() else []
    except OSError:
        return []
    return [l.strip().rstrip("/") for l in lignes if l.strip() and not l.lstrip().startswith(("#", "!"))]


def _ignore(rel: str, motifs: list[str]) -> bool:
    morceaux = rel.split("/")
    for m in motifs:
        m2 = m.lstrip("/")
        if fnmatch.fnmatch(rel, m2) or fnmatch.fnmatch(rel, m2 + "/*"):
            return True
        if "/" not in m2 and any(fnmatch.fnmatch(p, m2) for p in morceaux):
            return True
    return False


def _secret_ou_interne(nom: str) -> bool:
    return (nom == ".env" or nom.startswith(".env.") or nom.endswith(".avant-codex")
            or nom == LIEN or nom.startswith(".lexos-"))


def lister(projet: Path, sauter: set[str]) -> list[tuple[str, Path, str]]:
    """[(chemin relatif, fichier, mode git)] — ce qui partira."""
    motifs = _motifs_gitignore(projet)
    out, total = [], 0
    for racine, dossiers, fichiers in os.walk(projet):
        rel_racine = Path(racine).relative_to(projet).as_posix()
        dossiers[:] = sorted(d for d in dossiers if d not in sauter and d != ".git"
                             and not _ignore((rel_racine + "/" + d).lstrip("./"), motifs))
        for f in sorted(fichiers):
            p = Path(racine) / f
            rel = p.relative_to(projet).as_posix()
            if _secret_ou_interne(f) or _ignore(rel, motifs) or p.is_symlink():
                continue
            try:
                taille = p.stat().st_size
            except OSError:
                continue
            if taille > MAX_FICHIER:
                raise ErreurGitHub(f"« {rel} » est trop gros pour GitHub ({taille // 1048576} Mo) : "
                                   "ajoute-le au .gitignore")
            total += taille
            if total > MAX_TOTAL or len(out) >= MAX_FICHIERS:
                raise ErreurGitHub("Le projet est trop gros pour un envoi (ajoute les gros dossiers au .gitignore)")
            mode = "100755" if os.access(p, os.X_OK) and not os.name == "nt" else "100644"
            out.append((rel, p, mode))
    return out


def sha_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


# ─── Le lien projet ↔ dépôt ────────────────────────────────────────────────
def lire_lien(projet: Path) -> dict:
    try:
        d = json.loads((projet / LIEN).read_text("utf-8"))
        return d if isinstance(d, dict) and isinstance(d.get("depot"), str) else {}
    except (OSError, ValueError):
        return {}


def _ecrire_lien(projet: Path, d: dict) -> None:
    (projet / LIEN).write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", "utf-8")


def lier_clone(dossier: Path, complet: str, branche: str = "") -> None:
    """Un dépôt cloné se souvient d'où il vient : « ⬆️ GitHub » le renverra
    au MÊME dépôt (et à la même branche), sans rien redemander. Jamais miroir :
    le dépôt existait avant LexOS, donc on n'y efface rien."""
    _ecrire_lien(dossier, {"depot": complet, "branche": branche, "miroir": False, "clone": True})


def lister_depots(jeton: str, recherche: str = "", maximum: int = 100) -> list[dict]:
    """Les dépôts que le jeton peut voir (privés compris), les plus récents d'abord."""
    if not jeton:
        raise ErreurGitHub("Ajoute ton jeton GitHub dans 🔑 Variables, sous le nom GITHUB_TOKEN (variable globale)")
    filtre, out = recherche.strip().lower(), []
    for page in range(1, 6):
        lot = _appel(jeton, "GET", f"/user/repos?per_page=100&sort=updated&page={page}"
                                   "&affiliation=owner,collaborator,organization_member") or []
        for d in lot:
            if filtre and filtre not in (d.get("full_name") or "").lower():
                continue
            out.append({"depot": d.get("full_name", ""), "prive": bool(d.get("private")),
                        "branche": d.get("default_branch") or "main",
                        "ecriture": bool((d.get("permissions") or {}).get("push")),
                        "maj": (d.get("pushed_at") or "")[:10], "description": d.get("description") or ""})
            if len(out) >= maximum:
                return out
        if len(lot) < 100:
            break
    return out


def analyser_depot(texte: str, defaut_proprio: str) -> tuple[str, str]:
    """« nom », « proprio/nom » ou une adresse github.com → (proprio, nom)."""
    t = texte.strip().removesuffix(".git").rstrip("/")
    m = re.search(r"github\.com[/:]([\w.-]+)/([\w.-]+)$", t)
    if m:
        proprio, nom = m.group(1), m.group(2)
    elif "/" in t:
        proprio, nom = t.split("/", 1)
    else:
        proprio, nom = defaut_proprio, t
    if not NOM_DEPOT.match(nom) or not NOM_DEPOT.match(proprio) or nom in (".", ".."):
        raise ErreurGitHub("Nom de dépôt invalide : lettres, chiffres, - _ .")
    return proprio, nom


def nom_depot_pour(projet_nom: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", projet_nom).strip("-.")[:100] or "projet-lexos"


# ─── L'envoi ───────────────────────────────────────────────────────────────
def envoyer(projet: Path, jeton: str, depot: str, prive: bool, message: str,
            sauter: set[str], progres=lambda e: None) -> dict:
    if not jeton:
        raise ErreurGitHub("Ajoute ton jeton GitHub dans 🔑 Variables, sous le nom GITHUB_TOKEN (variable globale)")
    moi = _appel(jeton, "GET", "/user")
    login = moi.get("login") or ""
    lien = lire_lien(projet)
    proprio, nom = analyser_depot(depot or lien.get("depot") or nom_depot_pour(projet.name), login)
    complet = f"{proprio}/{nom}"
    deja_lie = lien.get("depot", "").lower() == complet.lower()

    progres({"type": "etape", "texte": f"dépôt {complet}…"})
    info = _appel(jeton, "GET", f"/repos/{proprio}/{nom}", ok404=True)
    cree = False
    if info is None:
        if proprio.lower() != login.lower():
            corps_cree, chemin_cree = {"name": nom, "private": prive, "auto_init": True}, f"/orgs/{proprio}/repos"
        else:
            corps_cree, chemin_cree = {"name": nom, "private": prive, "auto_init": True}, "/user/repos"
        info = _appel(jeton, "POST", chemin_cree, corps_cree)
        cree = True
    branche = info.get("default_branch") or "main"
    #  Un dépôt cloné (ou déjà lié) retourne sur SA branche, pas forcément celle par défaut.
    voulue = (lien.get("branche") or "").strip() if deja_lie else ""
    if voulue and voulue != branche:
        try:
            if _appel(jeton, "GET", f"/repos/{proprio}/{nom}/git/ref/heads/{voulue}", ok404=True):
                branche = voulue
        except ErreurGitHub:
            pass
    #  Miroir seulement pour un dépôt que LexOS a créé (le lien s'en souvient).
    miroir = cree or (deja_lie and bool(lien.get("miroir")))

    # Le dernier commit de la branche (un dépôt vide n'en a pas : on le crée)
    try:
        ref = _appel(jeton, "GET", f"/repos/{proprio}/{nom}/git/ref/heads/{branche}", ok404=True)
    except ErreurGitHub as e:
        if str(e) != "vide":
            raise
        ref = None
    if ref is None:
        _appel(jeton, "PUT", f"/repos/{proprio}/{nom}/contents/.lexos-init",
               {"message": "Initialisation par LexOS", "content": "", "branch": branche})
        ref = _appel(jeton, "GET", f"/repos/{proprio}/{nom}/git/ref/heads/{branche}")
        miroir = True
    parent = ref["object"]["sha"]
    commit_parent = _appel(jeton, "GET", f"/repos/{proprio}/{nom}/git/commits/{parent}")
    arbre_parent = commit_parent["tree"]["sha"]
    distant = _appel(jeton, "GET", f"/repos/{proprio}/{nom}/git/trees/{arbre_parent}?recursive=1")
    deja = {e["path"]: e["sha"] for e in distant.get("tree", []) if e.get("type") == "blob"}

    fichiers = lister(projet, sauter)
    if not fichiers:
        raise ErreurGitHub("Le projet est vide : rien à envoyer")
    entrees, a_envoyer = [], []
    for rel, p, mode in fichiers:
        data = p.read_bytes()
        s = sha_blob(data)
        entrees.append({"path": rel, "mode": mode, "type": "blob", "sha": s})
        if deja.get(rel) != s:
            a_envoyer.append((rel, data))
    for i, (rel, data) in enumerate(a_envoyer, 1):
        progres({"type": "fichier", "chemin": rel, "n": i, "total": len(a_envoyer)})
        _appel(jeton, "POST", f"/repos/{proprio}/{nom}/git/blobs",
               {"content": base64.b64encode(data).decode(), "encoding": "base64"})

    locaux = {e["path"] for e in entrees}
    retires = sorted(k for k in deja if k not in locaux) if miroir else []
    if not a_envoyer and not retires:
        _ecrire_lien(projet, {**(lien if deja_lie else {}), "depot": complet, "branche": branche, "miroir": miroir})
        return {"ok": True, "depot": complet, "url": info.get("html_url", f"https://github.com/{complet}"),
                "rien": True, "envoyes": 0, "retires": 0, "cree": cree}

    progres({"type": "etape", "texte": "création du commit…"})
    if miroir:
        arbre = _appel(jeton, "POST", f"/repos/{proprio}/{nom}/git/trees", {"tree": entrees})
    else:                       # premier envoi dans un dépôt d'avant : on n'efface rien
        arbre = _appel(jeton, "POST", f"/repos/{proprio}/{nom}/git/trees",
                       {"base_tree": arbre_parent, "tree": entrees})
    msg = (message or "").strip()[:500] or "Mise à jour depuis LexOS"
    commit = _appel(jeton, "POST", f"/repos/{proprio}/{nom}/git/commits",
                    {"message": msg, "tree": arbre["sha"], "parents": [parent]})
    _appel(jeton, "PATCH", f"/repos/{proprio}/{nom}/git/refs/heads/{branche}", {"sha": commit["sha"]})
    _ecrire_lien(projet, {**(lien if deja_lie else {}), "depot": complet, "branche": branche, "miroir": miroir})
    return {"ok": True, "depot": complet, "url": info.get("html_url", f"https://github.com/{complet}"),
            "commit": commit["sha"][:7], "envoyes": len(a_envoyer), "retires": len(retires),
            "total": len(entrees), "cree": cree, "branche": branche}
