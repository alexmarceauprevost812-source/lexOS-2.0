"""LexOS Bureau — ce que le bureau montre : applis, dossier Bureau, icônes.

Tout est LU, rien n'est écrit : le bureau affiche les fichiers et les
lanceurs du dossier Bureau de l'utilisateur tels qu'ils sont — il ne les
déplace pas, ne les renomme pas, ne les touche jamais (demande d'Alex :
« les fichiers, les images, garder les mêmes »).

Chaque élément affichable reçoit un identifiant opaque. Le serveur ne lance
QUE ce qui est dans la table construite ici : la page ne peut pas lui faire
ouvrir un chemin qu'elle aurait inventé.
"""
from __future__ import annotations

import configparser
import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

MAISON = Path.home()

#  ─── Les sections ─────────────────────────────────────────────────────────
#  « ti-lex IA » : les onglets du Moteur d'Alex (ti-lex-ia). Mêmes noms et
#  mêmes émojis que son Bureau (bureau.js, LANCEURS) — c'est son dessin.
TILEX = [
    ("chat", "ti-lex Chat", "💬"),
    ("codex", "Codex", "⌨️"),
    ("equipe", "Codex équipe", "👥"),
    ("images", "Images", "🎨"),
    ("schemas", "Schémas animés", "🎬"),
    ("modeles", "Modèles", "🧠"),
    ("nuage", "IA en ligne", "☁️"),
    ("variables", "Variables", "🔑"),
]

#  « LexOS » : les applis du système, dans cet ordre, si elles sont là.
#  Plusieurs candidats par case : le premier .desktop trouvé gagne.
#  ═══ LES ICÔNES D'ALEX ═══
#  Sa planche « LEXOS Linux OS » (branding/icones-bureau-planche.png),
#  découpée dans /usr/share/lexos/bureau-icones/<nom>.png. Elles passent
#  AVANT l'icône du thème : c'est le dessin qu'il a choisi pour son bureau.
#  L'émoji ne sert que si ni sa planche ni le thème n'ont l'image.
VISUELS = Path(os.environ.get("LEXOS_BUREAU_ICONES", "/usr/share/lexos/bureau-icones"))

#  (émoji de secours, icône de la planche, NOM DE LA PLANCHE, .desktop candidats)
#  Le nom affiché est celui qu'Alex a écrit sous chaque icône ; vide = le nom
#  de l'appli elle-même.
LEXOS = [
    ("📁", "fichiers", "Fichiers", ["thunar.desktop", "org.xfce.Thunar.desktop"]),
    ("⌨️", "terminal", "Terminal TI-LEX", ["lexos-pro-terminal.desktop", "xfce4-terminal.desktop"]),
    ("🌐", "navigateur", "Navigateur Web", ["lexos-chrome.desktop", "google-chrome.desktop", "firefox-esr.desktop", "firefox.desktop"]),
    ("⚙️", "parametres", "Paramètres", ["lexos-settings.desktop"]),
    ("🛍️", "boutique", "Boutique d'applications", ["lexos-logitheque.desktop"]),
    ("🛡️", "securite", "Sécurité", ["lexos-secure.desktop"]),
    ("🎮", "outils", "Pilotes", ["lexos-pilotes.desktop"]),
    ("🩺", "moniteur", "Moniteur système", ["lexos-diagnostic.desktop"]),
    ("💽", "disques", "Gestion des disques", ["lexos-disques.desktop"]),
    ("🎵", "musique", "Musique", ["lexos-musique.desktop"]),
    ("🕹️", "", "", ["lexos-jeux.desktop"]),
    ("📸", "capture", "Capture d'écran", ["lexos-capture.desktop"]),
    ("📤", "synchro", "Partage", ["lexos-share.desktop"]),
]

#  Les fichiers du dossier Bureau, par extension -> icône de la planche.
VISUEL_FICHIER = {
    "pdf": "pdf",
    "txt": "texte", "md": "notes", "odt": "texte", "doc": "texte", "docx": "texte", "rtf": "texte",
    "zip": "archives", "gz": "archives", "xz": "archives", "7z": "archives", "tar": "archives", "rar": "archives",
    "mp3": "musique", "ogg": "musique", "flac": "musique", "wav": "musique", "m4a": "musique",
    "mp4": "videos", "mkv": "videos", "webm": "videos", "mov": "videos", "avi": "videos",
    "py": "ide", "js": "ide", "sh": "ide", "html": "ide", "css": "ide", "json": "ide", "ts": "ide",
    "csv": "base-donnees", "ods": "base-donnees", "xlsx": "base-donnees", "db": "base-donnees", "sqlite": "base-donnees",
}


def visuel(nom: str) -> Path | None:
    p = VISUELS / f"{nom}.png" if nom else None
    return p if p and _est_fichier(p) else None

EMOJI_FICHIER = {
    "png": "🖼️", "jpg": "🖼️", "jpeg": "🖼️", "webp": "🖼️", "gif": "🖼️", "svg": "🖼️", "bmp": "🖼️",
    "mp4": "🎞️", "mkv": "🎞️", "webm": "🎞️", "mov": "🎞️", "avi": "🎞️",
    "mp3": "🎵", "ogg": "🎵", "flac": "🎵", "wav": "🎵", "m4a": "🎵",
    "pdf": "📕", "txt": "📄", "md": "📝", "odt": "📄", "docx": "📄", "doc": "📄",
    "ods": "📊", "xlsx": "📊", "csv": "📊", "odp": "📽️", "pptx": "📽️",
    "zip": "🗜️", "gz": "🗜️", "xz": "🗜️", "7z": "🗜️", "tar": "🗜️", "deb": "📦", "iso": "💿",
    "py": "🐍", "sh": "⚙️", "js": "📜", "html": "🌐", "json": "🧾",
}
MAX_BUREAU = 80


def _est_fichier(p: Path) -> bool:
    """is_file() qui ne lève JAMAIS. Sous Python 3.13, Path.is_file() laisse
    passer « permission refusée » — vu en vrai : un dossier illisible dans
    XDG_DATA_DIRS faisait tomber tout le bureau au démarrage."""
    try:
        return p.is_file()
    except OSError:
        return False


def _est_dossier(p: Path) -> bool:
    try:
        return p.is_dir()
    except OSError:
        return False


def _ident(prefixe: str, cle: str) -> str:
    return prefixe + hashlib.sha1(cle.encode("utf-8", "surrogateescape")).hexdigest()[:14]


#  ─── Les dossiers XDG ─────────────────────────────────────────────────────
def dossiers_applications() -> list[Path]:
    donnees = [os.environ.get("XDG_DATA_HOME") or str(MAISON / ".local/share")]
    donnees += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [Path(d) / "applications" for d in donnees if d]


def dossier_bureau() -> Path:
    """XDG_DESKTOP_DIR, comme xfdesktop : « Bureau » en français, sinon Desktop."""
    try:
        for ligne in (MAISON / ".config/user-dirs.dirs").read_text("utf-8").splitlines():
            m = re.match(r'\s*XDG_DESKTOP_DIR="(.+)"\s*$', ligne)
            if m:
                return Path(m.group(1).replace("$HOME", str(MAISON)))
    except OSError:
        pass
    for nom in ("Bureau", "Desktop"):
        if _est_dossier(MAISON / nom):
            return MAISON / nom
    return MAISON / "Bureau"


#  ─── Les fichiers .desktop ────────────────────────────────────────────────
def lire_desktop(chemin: Path) -> dict | None:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read(chemin, encoding="utf-8")
    except (configparser.Error, OSError, UnicodeDecodeError):
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    e = cp["Desktop Entry"]
    if e.get("Hidden", "").lower() == "true":
        return None
    nom = e.get("Name[fr_CA]") or e.get("Name[fr]") or e.get("Name")
    if not nom:
        return None
    return {"nom": nom.strip()[:60], "icone": (e.get("Icon") or "").strip(),
            "type": e.get("Type", "Application"), "url": e.get("URL", "")}


def trouver_desktop(nom: str) -> Path | None:
    nom = nom if nom.endswith(".desktop") else nom + ".desktop"
    for d in dossiers_applications():
        p = d / nom
        if _est_fichier(p):
            return p
    return None


#  ─── Les icônes ───────────────────────────────────────────────────────────
#  Index construit UNE fois : nom -> meilleur fichier. Les thèmes dans l'ordre
#  de LexOS (le sien d'abord), et dans chaque thème la plus grande taille.
_THEMES = ["LexOS", "Papirus-Dark", "Papirus", "Yaru-dark", "Yaru", "elementary-xfce-dark",
           "Adwaita", "hicolor"]
_INDEX: dict[str, tuple[int, Path]] | None = None


def _score(chemin: Path, rang_theme: int) -> int:
    texte = str(chemin)
    if chemin.suffix == ".svg" or "/scalable/" in texte:
        taille = 512
    else:
        m = re.search(r"/(\d+)x\d+(@\d+x)?/", texte) or re.search(r"/(\d+)/", texte)
        taille = int(m.group(1)) if m else 48
    return (len(_THEMES) - rang_theme) * 10000 + min(taille, 512)


def _indexer() -> dict[str, tuple[int, Path]]:
    global _INDEX
    if _INDEX is not None:
        return _INDEX
    index: dict[str, tuple[int, Path]] = {}
    racines = [MAISON / ".local/share/icons", MAISON / ".icons", Path("/usr/share/icons")]
    for rang, theme in enumerate(_THEMES):
        for r in racines:
            base = r / theme
            if not _est_dossier(base):
                continue
            for dossier, _sous, fichiers in os.walk(base):
                if not any(c in dossier for c in ("apps", "places", "devices", "mimetypes", "categories", "status", "actions")):
                    continue
                for f in fichiers:
                    if not f.endswith((".png", ".svg")):
                        continue
                    p = Path(dossier) / f
                    s = _score(p, rang)
                    nom = f.rsplit(".", 1)[0]
                    if nom not in index or s > index[nom][0]:
                        index[nom] = (s, p)
    try:
        for p in Path("/usr/share/pixmaps").glob("*"):
            if p.suffix in (".png", ".svg"):
                index.setdefault(p.stem, (1, p))
    except OSError:
        pass
    _INDEX = index
    return index


def chemin_icone(nom: str) -> Path | None:
    if not nom:
        return None
    if nom.startswith("/"):
        p = Path(nom)
        return p if _est_fichier(p) and p.suffix.lower() in (".png", ".svg", ".jpg", ".jpeg", ".webp") else None
    trouve = _indexer().get(nom)
    return trouve[1] if trouve else None


#  ─── La table de ce que le bureau montre ──────────────────────────────────
class Table:
    """Ce qui est à l'écran, et comment l'ouvrir. Reconstruite à chaque état."""

    def __init__(self) -> None:
        self.actions: dict[str, tuple[str, str]] = {}   # id -> (genre, cible)
        self.icones: dict[str, Path] = {}               # id -> fichier image

    def _ajouter(self, ident: str, genre: str, cible: str, icone: Path | None) -> None:
        self.actions[ident] = (genre, cible)
        if icone:
            self.icones[ident] = icone

    def _marquer(self, elements: list[dict]) -> list[dict]:
        """« plein » : l'image remplit la tuile (icône de la planche d'Alex,
        ou vignette d'une photo) au lieu d'être posée au milieu."""
        for e in elements:
            p = self.icones.get(e["id"])
            e["plein"] = bool(p) and (p.parent == VISUELS or e.get("vignette", False))
        return elements

    def section_tilex(self) -> list[dict]:
        if not shutil.which("ti-lex-ia"):
            return []
        out = []
        for onglet, nom, emoji in TILEX:
            ident = "t-" + onglet
            self._ajouter(ident, "tilex", onglet, None)
            out.append({"id": ident, "nom": nom, "emoji": emoji})
        return out

    def section_lexos(self) -> list[dict]:
        out = []
        for emoji, nom_visuel, nom_planche, candidats in LEXOS:
            for c in candidats:
                p = trouver_desktop(c)
                d = lire_desktop(p) if p else None
                if d:
                    ident = _ident("a-", str(p))
                    self._ajouter(ident, "desktop", str(p), visuel(nom_visuel) or chemin_icone(d["icone"]))
                    out.append({"id": ident, "nom": nom_planche or d["nom"],
                                "icone": ident in self.icones, "emoji": emoji})
                    break
        return self._marquer(out)

    def section_bureau(self) -> list[dict]:
        out = []
        #  Les deux icônes que xfdesktop pose d'office : on les garde, à la
        #  même place qu'avant pour Alex (en tête).
        for ident, nom, emoji, cible, vis in (("s-maison", "Dossier personnel", "🏠", str(MAISON), "maison"),
                                              ("s-corbeille", "Corbeille", "🗑️", "trash:///", "corbeille")):
            self._ajouter(ident, "ouvrir", cible, visuel(vis))
            out.append({"id": ident, "nom": nom, "emoji": emoji, "icone": ident in self.icones})
        d = dossier_bureau()
        try:
            entrees = sorted((p for p in d.iterdir() if not p.name.startswith(".")),
                             key=lambda p: (not _est_dossier(p), p.name.lower()))
        except OSError:
            entrees = []
        for p in entrees[:MAX_BUREAU]:
            ident = _ident("b-", str(p))
            if p.suffix == ".desktop" and _est_fichier(p):
                info = lire_desktop(p)
                if not info:
                    continue
                self._ajouter(ident, "desktop", str(p), chemin_icone(info["icone"]))
                out.append({"id": ident, "nom": info["nom"], "icone": ident in self.icones,
                            "emoji": "🚀"})
            elif _est_dossier(p):
                self._ajouter(ident, "ouvrir", str(p), visuel("fichiers"))
                out.append({"id": ident, "nom": p.name[:60], "emoji": "📁", "icone": ident in self.icones})
            else:
                ext = p.suffix.lower().lstrip(".")
                #  Une IMAGE se montre elle-même, en vignette — les autres
                #  fichiers prennent l'icône de la planche selon leur genre.
                image = ext in ("png", "jpg", "jpeg", "webp", "gif", "svg") and _poids_ok(p)
                icone = p if image else visuel(VISUEL_FICHIER.get(ext, "texte"))
                self._ajouter(ident, "ouvrir", str(p), icone)
                out.append({"id": ident, "nom": p.name[:60], "icone": ident in self.icones,
                            "vignette": image, "emoji": EMOJI_FICHIER.get(ext, "📄")})
        return self._marquer(out)


def _poids_ok(p: Path, maxi: int = 15 * 1024 * 1024) -> bool:
    try:
        return p.stat().st_size <= maxi
    except OSError:
        return False


def empreinte_bureau() -> str:
    """Change dès qu'un fichier apparaît, disparaît ou est renommé dans Bureau."""
    d = dossier_bureau()
    try:
        noms = sorted(p.name for p in d.iterdir())
        return hashlib.sha1(("\0".join(noms) + str(d.stat().st_mtime)).encode("utf-8", "surrogateescape")).hexdigest()[:12]
    except OSError:
        return "absent"


#  ─── Lancer ───────────────────────────────────────────────────────────────
def _detache(cmd: list[str]) -> bool:
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True, cwd=str(MAISON))
        return True
    except OSError:
        return False


def lancer(genre: str, cible: str) -> bool:
    if genre == "tilex":
        return _detache(["ti-lex-ia", cible])
    if genre == "desktop":
        if shutil.which("gio"):
            return _detache(["gio", "launch", cible])
        if shutil.which("exo-open"):
            return _detache(["exo-open", cible])
        return _detache(["gtk-launch", Path(cible).name])
    if genre == "ouvrir":
        if cible == "trash:///" and shutil.which("thunar"):
            return _detache(["thunar", "trash:///"])
        for outil in ("exo-open", "xdg-open", "gio"):
            if shutil.which(outil):
                return _detache([outil, "open", cible] if outil == "gio" else [outil, cible])
    return False
