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
    ("abo", "Mon abonnement", "🌐"),
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

#  ─── Le bureau démon (saveur nomade) ─────────────────────────────────────
#  Les cases du dock et des icônes de demon.html : (clé, nom, .desktop
#  candidats). La clé dit à la page QUEL dessin poser ; l'identifiant, lui,
#  reste opaque et passe par la même table que tout le reste — la page ne
#  peut toujours rien lancer qui ne soit pas ici.
#  Le navigateur : Chromium d'abord, c'est le navigateur officiel de LexOS
#  (hook 0445) et il est DANS l'image ; lexos-chrome ne vient qu'en dernier,
#  parce qu'au premier clic il propose de télécharger Chrome — pas ce qu'on
#  attend d'une clé légère.
DEMON = [
    ("terminal", "Terminal", ["lexos-pro-terminal.desktop", "xfce4-terminal.desktop"]),
    ("fichiers", "Fichiers", ["thunar.desktop", "org.xfce.Thunar.desktop"]),
    ("navigateur", "Navigateur", ["chromium.desktop", "firefox-esr.desktop", "firefox.desktop",
                                  "lexos-chrome.desktop"]),
    ("parametres", "Paramètres", ["lexos-settings.desktop", "xfce-settings-manager.desktop"]),
    #  L'installateur n'a de sens qu'en session live (sur la clé) : voir
    #  est_live(). lexos-install demande confirmation avant tout effacement.
    ("installer", "Installer LexOS", ["lexos-install.desktop"]),
]
CMDLINE = Path(os.environ.get("LEXOS_CMDLINE", "/proc/cmdline"))
#  La tuile GitHub du bureau démon : le dépôt de LexOS. L'adresse est ÉCRITE
#  ICI, côté serveur — la page ne fournit qu'un identifiant, jamais une URL.
GITHUB = "https://github.com/alexmarceauprevost812-source/lexOS-2.0"


def est_live() -> bool:
    """Session démo démarrée de la clé ? Même signe que lexos-install :
    « boot=live » sur la ligne de commande du noyau."""
    try:
        return "boot=live" in CMDLINE.read_text(encoding="utf-8", errors="replace").split()
    except OSError:
        return False


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
MAX_APPLIS = 600


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


def nom_lisible(nom: str) -> str:
    """Un nom de fichier qui n'est pas de l'UTF-8 valide (vieille clé USB,
    archive Windows) arrive en « surrogateescape » ; tel quel, il fait
    planter json.dumps et TOUTES les icônes disparaissent. On remplace les
    octets illisibles par « � » — pour l'affichage seulement : le chemin
    gardé dans la table, lui, reste exact."""
    return nom.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


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
    #  « cache » : ce qu'un menu d'applications ne montre pas (NoDisplay, ou
    #  réservé à un autre bureau que XFCE). Seule la liste « Toutes les
    #  applications » du labo s'en sert.
    seul = [x for x in (e.get("OnlyShowIn") or "").split(";") if x]
    sauf = [x for x in (e.get("NotShowIn") or "").split(";") if x]
    cache = (e.get("NoDisplay", "").lower() == "true" or (seul and "XFCE" not in seul) or "XFCE" in sauf)
    return {"nom": nom.strip()[:60], "icone": (e.get("Icon") or "").strip(),
            "type": e.get("Type", "Application").strip(), "url": (e.get("URL") or "").strip(),
            "cache": bool(cache), "categories": [x for x in (e.get("Categories") or "").split(";") if x]}


#  Les rayons du menu d'XFCE, dans son ordre, avec les catégories freedesktop
#  qui y mènent. Le ti démon (🎛️ Mes outils) range « Toutes les applications »
#  dans ces rayons. La PREMIÈRE ligne qui correspond gagne : un navigateur
#  porte souvent « Network;WebBrowser;Utility » et va dans Internet.
RAYONS = [
    ("Paramètres", ("Settings", "DesktopSettings", "HardwareSettings", "X-XFCE-SettingsDialog")),
    ("Internet", ("Network", "WebBrowser", "Email", "Chat", "InstantMessaging")),
    ("Multimédia", ("AudioVideo", "Audio", "Video", "Player", "Recorder", "Music")),
    ("Graphisme", ("Graphics", "Photography", "2DGraphics", "3DGraphics", "RasterGraphics", "VectorGraphics")),
    ("Développement", ("Development", "IDE", "TextEditor")),
    ("Bureautique", ("Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar")),
    ("Jeux", ("Game",)),
    ("Éducation", ("Education", "Science")),
    ("Système", ("System", "Monitor", "TerminalEmulator", "Emulator", "PackageManager", "FileManager", "Security")),
    ("Accessoires", ("Utility", "Accessories", "Archiving", "Compression", "Calculator", "Viewer")),
]


def rayon(categories: list[str]) -> str:
    for nom, cles in RAYONS:
        if any(c in cles for c in categories):
            return nom
    return "Autres"


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

    def section_demon(self) -> list[dict]:
        """Le dock et les icônes du bureau démon : {"id", "cle", "nom"}.
        Le dossier personnel et la corbeille y sont aussi, avec les MÊMES
        identifiants que dans « Mon bureau »."""
        out = []
        for cle, nom, candidats in DEMON:
            if cle == "installer" and not est_live():
                continue
            for c in candidats:
                p = trouver_desktop(c)
                if p and lire_desktop(p):
                    ident = _ident("a-", str(p))
                    self._ajouter(ident, "desktop", str(p), None)
                    out.append({"id": ident, "cle": cle, "nom": nom})
                    break
        for ident, cle, nom, cible in (("s-maison", "maison", "Dossier personnel", str(MAISON)),
                                       ("s-corbeille", "corbeille", "Corbeille", "trash:///")):
            self._ajouter(ident, "ouvrir", cible, visuel(cle))
            out.append({"id": ident, "cle": cle, "nom": nom})
        self._ajouter("s-github", "url", GITHUB, None)
        out.append({"id": "s-github", "cle": "github", "nom": "GitHub"})
        return out

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
                #  Un lanceur du dossier Bureau n'est PAS un lanceur du système :
                #  n'importe quel téléchargement peut y atterrir. Il passe par la
                #  même porte que dans XFCE (voir lanceur_approuve).
                genre = "lien" if info["type"] == "Link" else "desktop-bureau"
                self._ajouter(ident, genre, str(p), chemin_icone(info["icone"]))
                out.append({"id": ident, "nom": nom_lisible(info["nom"]), "icone": ident in self.icones,
                            "emoji": "🔗" if genre == "lien" else "🚀"})
            elif _est_dossier(p):
                self._ajouter(ident, "ouvrir", str(p), visuel("fichiers"))
                out.append({"id": ident, "nom": nom_lisible(p.name)[:60], "emoji": "📁", "icone": ident in self.icones})
            else:
                ext = p.suffix.lower().lstrip(".")
                #  Une IMAGE se montre elle-même, en vignette — les autres
                #  fichiers prennent l'icône de la planche selon leur genre.
                image = ext in ("png", "jpg", "jpeg", "webp", "gif", "svg") and _poids_ok(p)
                icone = p if image else visuel(VISUEL_FICHIER.get(ext, "texte"))
                self._ajouter(ident, "ouvrir", str(p), icone)
                out.append({"id": ident, "nom": nom_lisible(p.name)[:60], "icone": ident in self.icones,
                            "vignette": image, "emoji": EMOJI_FICHIER.get(ext, "📄")})
        return self._marquer(out)


    def section_applis(self) -> list[dict]:
        """TOUTES les applications installées, pour le labo (« ＋ Ajouter »).
        Même identifiant qu'une icône LexOS pour le même fichier (« a- » +
        empreinte du chemin) : une appli épinglée garde sa place partout.
        Le premier dossier XDG gagne, comme dans un menu : une appli que
        l'utilisateur a copiée dans ~/.local/share/applications passe avant
        celle du système."""
        vus: set[str] = set()
        out = []
        for d in dossiers_applications():
            try:
                fichiers = sorted(list(d.glob("*.desktop")) + list(d.glob("*/*.desktop")))
            except OSError:
                continue
            for p in fichiers:
                id_xdg = str(p.relative_to(d)).replace("/", "-")
                if id_xdg in vus or len(out) >= MAX_APPLIS:
                    continue
                vus.add(id_xdg)
                if not _est_fichier(p):
                    continue
                info = lire_desktop(p)
                if not info or info["cache"] or info["type"] != "Application":
                    continue
                ident = _ident("a-", str(p))
                if ident not in self.actions:
                    self._ajouter(ident, "desktop", str(p), chemin_icone(info["icone"]))
                out.append({"id": ident, "nom": nom_lisible(info["nom"]), "icone": ident in self.icones, "emoji": "🧩",
                            "rayon": rayon(info["categories"])})
        out.sort(key=lambda e: e["nom"].lower())
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


def lanceur_approuve(chemin: str) -> bool:
    """La même règle que Thunar et xfdesktop 4.18 pour un .desktop du Bureau :
    le fichier doit être EXÉCUTABLE, et son empreinte sha256 doit être celle
    qu'XFCE a notée quand l'utilisateur l'a approuvé (métadonnée
    « metadata::xfce-exe-checksum »). Les deux, sinon un .desktop téléchargé
    (Exec= n'importe quoi, Name=« Facture.pdf ») se lancerait d'un clic.
    Les lanceurs qu'Alex a déjà approuvés dans XFCE passent tels quels."""
    if not os.access(chemin, os.X_OK) or not shutil.which("gio"):
        return False
    try:
        r = subprocess.run(["gio", "info", "-a", "metadata::xfce-exe-checksum", chemin],
                           capture_output=True, text=True, timeout=5, check=False)
        m = re.search(r"metadata::xfce-exe-checksum:\s*([0-9a-f]{64})", r.stdout)
        if not m:
            return False
        return hashlib.sha256(Path(chemin).read_bytes()).hexdigest() == m.group(1)
    except (OSError, subprocess.SubprocessError):
        return False


def lancer(genre: str, cible: str) -> bool | str:
    """True si c'est parti ; False si rien n'a pu être lancé ; une chaîne
    pour un refus VOULU que la page doit expliquer."""
    if genre == "desktop-bureau":
        if lanceur_approuve(cible):
            genre = "desktop"
        else:
            #  On ouvre Fichiers sur le dossier : un double-clic y montre la
            #  question de sécurité d'XFCE, qui approuve le lanceur pour de bon.
            if shutil.which("thunar"):
                _detache(["thunar", str(Path(cible).parent)])
            return "non-approuve"
    if genre == "lien":
        info = lire_desktop(Path(cible)) or {}
        url = info.get("url", "")
        if not re.match(r"^https?://", url):
            return "lien-refuse"
        for outil in ("exo-open", "xdg-open"):
            if shutil.which(outil):
                return _detache([outil, url])
        return False
    if genre == "url":
        #  Seulement les adresses écrites dans CE fichier (GITHUB) : la table
        #  ne contient rien d'autre sous ce genre.
        if not re.match(r"^https://", cible):
            return False
        for outil in ("exo-open", "xdg-open"):
            if shutil.which(outil):
                return _detache([outil, cible])
        return False
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
