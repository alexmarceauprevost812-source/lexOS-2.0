#!/usr/bin/env python3
"""Génère la démo web du VRAI bureau démon (website/demo-demon/).

ALEX, 31 octobre : « dans la version démo qu'on voit sur Vercel, la vraie
version démon ». Le bureau démon de LexOS est une page web (bureau/web/
demon.html) qui parle à un petit serveur local (bureau/serveur.py). Sur
Vercel il n'y a pas ce serveur : on copie la VRAIE page, telle quelle, et
on lui glisse demo-api.js, qui répond à ses /api/… dans le navigateur.

Rien n'est réécrit à la main : thèmes, yeux, tuiles, panneau Yeux, menus du
réseau, du son et de la session sont ceux de LexOS. Les réglages par défaut
viennent du vrai reglages.py (saveur nomade). Relancer ce script après un
changement du bureau démon :  python3 tools/gen-demo-demon.py
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
BUREAU = RACINE / "config/includes.chroot/usr/lib/lexos/bureau"
WEB = BUREAU / "web"
POLICES = RACINE / "config/includes.chroot/usr/lib/lexos/ti-lex-ia/interface"
SORTIE = RACINE / "website/demo-demon"
FICHIERS = ["demon.css", "demon.js", "logo-ti-lexos.png", "tux.png", "avatar-alex.png",
            "github-perso.png", "demarrage-flammes.webm"]


def reglages_nomade() -> dict:
    """Les VRAIS défauts du bureau démon, saveur nomade (reglages.py)."""
    with tempfile.TemporaryDirectory() as t:
        conf = Path(t) / "build.conf"
        conf.write_text('LEXOS_FLAVOUR="nomade"\n', encoding="utf-8")
        os.environ["LEXOS_BUILD_CONF"] = str(conf)
        os.environ["XDG_CONFIG_HOME"] = str(Path(t) / "config")
        sys.path.insert(0, str(BUREAU))
        import reglages  # noqa: PLC0415
        r = reglages.lire()
        return {"reglages": r, "couleurs": reglages.COULEURS, "polices": reglages.POLICES}


def main() -> None:
    d = reglages_nomade()
    #  Ce que serveur.py rendrait sur la clé nomade, en session démo (live) :
    #  les tuiles de applis.DEMON (« installer » compris), le dossier, la
    #  corbeille et GitHub.
    demon = [{"id": f"a-{cle}", "cle": cle, "nom": nom} for cle, nom in (
        ("terminal", "Terminal"), ("fichiers", "Fichiers"), ("navigateur", "Navigateur"),
        ("parametres", "Paramètres"), ("installer", "Installer LexOS"))]
    demon += [{"id": "s-maison", "cle": "maison", "nom": "Dossier personnel"},
              {"id": "s-corbeille", "cle": "corbeille", "nom": "Corbeille"},
              {"id": "s-github", "cle": "github", "nom": "GitHub"}]
    #  La démo montre tout : l'ouverture des yeux au chargement, même si la
    #  clé nomade la laisse éteinte par défaut.
    d["reglages"]["demon_intro"] = True
    etat = {
        "prenom": "toi", "reglages": d["reglages"], "sections": [], "tilex": False,
        "dock": {"cote": "", "taille": 0}, "zone": [], "labo": [],
        "couleurs": d["couleurs"], "polices": d["polices"], "demon": demon,
        "systeme": {"nom": "LexOS", "version": "2.0.3", "saveur": "nomade", "compte": "toi",
                    "noyau": "6.12 (démo web)", "processeur": "ton navigateur",
                    "memoire": "", "allume": ""},
    }
    if SORTIE.exists():
        shutil.rmtree(SORTIE)
    SORTIE.mkdir(parents=True)
    for f in FICHIERS:
        shutil.copy2(WEB / f, SORTIE / f)
    shutil.copy2(POLICES / "polices.css", SORTIE / "polices.css")
    shutil.copytree(POLICES / "polices", SORTIE / "polices",
                    ignore=shutil.ignore_patterns("*.txt"))
    for lic in (POLICES / "polices").glob("LICENCE-*.txt"):
        shutil.copy2(lic, SORTIE / "polices" / lic.name)

    api = (RACINE / "tools/demo-demon-api.js").read_text(encoding="utf-8")
    (SORTIE / "demo-api.js").write_text(
        api.replace("/*__ETAT__*/null", json.dumps(etat, ensure_ascii=False, indent=1)), encoding="utf-8")

    page = (WEB / "demon.html").read_text(encoding="utf-8")
    page = page.replace('<script src="demon.js"', '<script src="demo-api.js"></script>\n<script src="demon.js"', 1)
    assert "demo-api.js" in page, "demon.html a changé : le point d'injection du script n'est plus là"
    page = page.replace("<title>LexOS Bureau — démon</title>", "<title>Démo web — Bureau LexOS</title>", 1)
    (SORTIE / "index.html").write_text(page, encoding="utf-8")
    print(f"démo du bureau démon : {SORTIE.relative_to(RACINE)} "
          f"({sum(p.stat().st_size for p in SORTIE.rglob('*') if p.is_file()) // 1024} Ko)")


if __name__ == "__main__":
    main()
