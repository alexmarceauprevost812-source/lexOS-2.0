#!/usr/bin/python3
"""Vraies icônes du menu Kali : téléchargement facultatif, jamais de Kali installé.

L'archive source officielle, publiée par Kali, est figée par sa somme SHA-256.
Seuls les SVG de menu-icons/scalable/apps sont lus ; aucun code de l'archive
n'est exécuté, et aucun fichier personnel n'est écrasé hors du dossier LexOS.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

KALI_SOURCE_URL = (
    "https://archive.kali.org/kali/pool/main/k/kali-menu/"
    "kali-menu_2026.3.4.tar.xz"
)
# Publiée dans le manifeste Checksums-Sha256 de pkg.kali.org
KALI_SOURCE_SHA256 = "0f977fb202b94e0850e45cc4c5a97fa648936f325e6d5857f9839915ae032aa6"
KALI_SOURCE_BYTES = 1534748
MAX_ARCHIVE = 5 * 1024 * 1024
MAX_SVG = 400 * 1024
# Même sélection que le catalogue : chaque image doit correspondre à un outil.
MANIFESTE = Path(__file__).resolve().parents[3] / 'share/lexos/audit-tools.packages'
CIBLES = tuple(line.strip() for line in MANIFESTE.read_text().splitlines()
               if line.strip() and not line.startswith('#')) + ('johnny',)
IMAGES_SYSTEME = MANIFESTE.parent / 'audit/icones'
ALIASES = {
    "john": ("john", "johnny", "john-the-ripper"),
    "aircrack-ng": ("aircrack-ng", "aircrack"),
    "testdisk": ("testdisk", "photorec"),
    "netcat-openbsd": ("netcat-openbsd", "netcat"),
    "python3-impacket": ("impacket", "impacket-scripts"),
    "python3-scapy": ("scapy",),
    "libimage-exiftool-perl": ("exiftool",),
    "bind9-dnsutils": ("dnsutils", "dig"),
    "gddrescue": ("gddrescue", "ddrescue"),
    "mtr-tiny": ("mtr",),
}
SVG_PATH = "/menu-icons/scalable/apps/"


def repertoire() -> Path:
    base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    return base / "lexos" / "audit" / "icones"


def candidats(paquet: str) -> tuple[str, ...]:
    variantes = ALIASES.get(paquet, (paquet,))
    return tuple(dict.fromkeys(
        nom for v in variantes for nom in (v, "kali-" + v)
    ))


def icone_locale(paquet: str, base: Path | None = None) -> Path | None:
    """Fichiers du compte utilisateur, pas un faux logo généré par LexOS."""
    if paquet not in CIBLES:
        return None
    chemin = (base if base is not None else repertoire()) / (paquet + ".svg")
    try:
        if chemin.is_file() and chemin.stat().st_size > 0:
            return chemin
        if base is None:
            systeme = IMAGES_SYSTEME / (paquet + '.svg')
            if systeme.is_file() and systeme.stat().st_size > 0:
                return systeme
        return None
    except OSError:
        return None


def telecharger() -> bytes:
    req = urllib.request.Request(
        KALI_SOURCE_URL,
        headers={"User-Agent": "LexOS-Official-Menu-Icons/2.0.2"}
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as reponse:
            if not reponse.geturl().startswith("https://"):
                raise ValueError("Redirection non sécurisée refusée.")
            if reponse.headers.get("Content-Length", "").isdigit():
                if int(reponse.headers["Content-Length"]) > MAX_ARCHIVE:
                    raise ValueError("Archive trop volumineuse.")
            donnees = reponse.read(MAX_ARCHIVE + 1)
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise ValueError("Source officielle indisponible : " + str(exc)) from exc
    if len(donnees) != KALI_SOURCE_BYTES:
        raise ValueError("Taille de l'archive incorrecte.")
    return donnees


def svg_valide(data: bytes) -> bool:
    if not data or len(data) > MAX_SVG:
        return False
    bas = data.lower()
    if any(x in bas for x in (
            b"<!doctype", b"<!entity", b"<script", b"<iframe",
            b"javascript:", b"<foreignobject")):
        return False
    try:
        racine = ET.fromstring(data)
    except ET.ParseError:
        return False
    if racine.tag not in ("svg", "{http://www.w3.org/2000/svg}svg"):
        return False
    for element in racine.iter():
        for cle, valeur in element.attrib.items():
            cle = cle.rsplit("}", 1)[-1].lower()
            if cle.startswith("on") or (cle == "href" and
                                         valeur and not valeur.startswith("#")):
                return False
    return True


def analyser(donnees: bytes,
            somme_attendue: str = KALI_SOURCE_SHA256) -> dict[str, bytes]:
    if hashlib.sha256(donnees).hexdigest() != somme_attendue:
        raise ValueError("Empreinte SHA-256 différente de celle publiée par Kali.")
    possibles = {
        nom + ".svg"
        for p in CIBLES for nom in candidats(p)
    }
    trouvés = {}
    try:
        with tarfile.open(fileobj=io.BytesIO(donnees), mode="r:xz") as tar:
            for membre in tar:
                if not membre.isfile() or not (0 < membre.size < MAX_SVG):
                    continue
                if SVG_PATH not in "/" + membre.name:
                    continue
                nom = membre.name.rsplit("/", 1)[-1]
                if nom not in possibles or not re.fullmatch(r"[a-zA-Z0-9_.+-]+\.svg", nom):
                    continue
                fichier = tar.extractfile(membre)
                if fichier is None:
                    continue
                image = fichier.read(MAX_SVG + 1)
                if svg_valide(image):
                    trouvés[nom] = image
    except (tarfile.TarError, OSError, EOFError) as exc:
        raise ValueError("Archive Kali illisible : " + str(exc)) from exc
    retenus = {}
    for paquet in CIBLES:
        for nom in candidats(paquet):
            if nom + ".svg" in trouvés:
                retenus[paquet] = trouvés[nom + ".svg"]
                break
    return retenus


def installer(donnees: bytes, somme_attendue: str = KALI_SOURCE_SHA256,
              base: Path | None = None) -> dict:
    icones = analyser(donnees, somme_attendue)
    if not icones:
        raise ValueError("Aucune icône correspondante dans la source Kali.")
    base = base if base is not None else repertoire()
    if base.is_symlink():
        raise ValueError("Dossier d'icônes symbolique refusé.")
    base.mkdir(parents=True, exist_ok=True, mode=0o700)
    copies = []
    for paquet, image in icones.items():
        destination = base / (paquet + ".svg")
        if destination.is_symlink():
            raise ValueError("Icône symbolique refusée : " + paquet)
        temporaire = None
        try:
            with tempfile.NamedTemporaryFile(
                    mode="wb", dir=base, prefix=".icone-",
                    delete=False) as fichier:
                temporaire = Path(fichier.name)
                fichier.write(image)
            os.chmod(temporaire, 0o600)
            os.replace(temporaire, destination)
            copies.append(paquet)
        finally:
            if temporaire is not None:
                temporaire.unlink(missing_ok=True)
    return {"presentes": copies,
            "absentes": [p for p in CIBLES if p not in icones],
            "repertoire": str(base)}


def etat(base: Path | None = None) -> dict:
    base = base if base is not None else repertoire()
    dispo = [p for p in CIBLES if icone_locale(p, base) is not None]
    return {"presentes": dispo,
            "absentes": [p for p in CIBLES if p not in dispo],
            "repertoire": str(base)}


def main(argv: list[str]) -> int:
    action = argv[0] if argv else "aide"
    if len(argv) > 1 or action not in ("installer", "etat", "status", "aide",
                                      "--help", "-h"):
        print("Usage : lexos audit-icones [installer|etat]", file=sys.stderr)
        return 2
    if action in ("aide", "--help", "-h"):
        print("lexos audit-icones installer : récupérer uniquement les SVG du menu Kali\n"
              "lexos audit-icones etat : afficher les vraies icônes présentes\n"
              "Sans sudo : aucun dépôt ou logiciel Kali n'est installé.")
        return 0
    if action in ("etat", "status"):
        print(json.dumps(etat(), ensure_ascii=False, indent=2))
        return 0
    if os.geteuid() == 0:
        print("Ne pas utiliser sudo : les icônes vont dans ton compte.",
              file=sys.stderr)
        return 1
    try:
        resultat = installer(telecharger())
    except ValueError as exc:
        print("✗ " + str(exc), file=sys.stderr)
        return 1
    print("✓ %d icône(s) authentique(s) trouvée(s)." % len(resultat["presentes"]))
    print("Trouvées :", ", ".join(resultat["presentes"]))
    print("Absentes :", ", ".join(resultat["absentes"]))
    print("Dossier :", resultat["repertoire"])
    print("Rouvre le catalogue pour voir les nouvelles images.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
