#!/usr/bin/env python3
"""Installation par utilisateur, sans sudo ni téléchargement."""
import argparse
import os
from pathlib import Path
import shutil
import sys

SOURCE = Path(__file__).resolve().parent


def desktop_quote(value):
    # Desktop Entry : échappement du fichier puis de l'argument Exec.
    value = str(value).replace('%', '%%')
    for old, new in [('\\', '\\\\'), ('"', '\\"'), ('`', '\\`'), ('$', '\\$')]:
        value = value.replace(old, new)
    return '"' + value.replace('\\', '\\\\') + '"'


def install(prefix, data_home):
    destination = prefix / 'share/rea-studio'
    if destination.resolve() == SOURCE:
        raise ValueError('Le dossier source doit différer du dossier installé.')
    destination.mkdir(parents=True, exist_ok=True)
    # Répertoire applicatif dédié ; les projets vivent ailleurs et restent intacts.
    for name in ('rea_studio', 'assets'):
        shutil.copytree(SOURCE / name, destination / name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(SOURCE / 'rea-studio', destination / 'rea-studio')
    launcher = prefix / 'bin/rea-studio'
    launcher.parent.mkdir(parents=True, exist_ok=True)
    if launcher.exists() and not launcher.is_symlink():
        raise ValueError(f'Un lanceur non géré existe déjà : {launcher}')
    if launcher.is_symlink():
        if launcher.resolve() != (destination / 'rea-studio').resolve():
            raise ValueError(f'Lien existant vers un autre programme : {launcher}')
        launcher.unlink()
    launcher.symlink_to(destination / 'rea-studio')
    applications = data_home / 'applications'
    applications.mkdir(parents=True, exist_ok=True)
    # Chemin absolu : le menu n'exige pas que ~/.local/bin soit dans PATH.
    desktop = applications / 'rea-studio.desktop'
    desktop.write_text('[Desktop Entry]\nType=Application\nVersion=1.0\nName=REA Studio\n'
                       'Comment=Atelier de projets et IA locale pour LexOS Pro\n'
                       f'Exec={desktop_quote(launcher)}\n'
                       f'Icon={destination / "assets/rea-studio.png"}\n'
                       'Terminal=false\nCategories=Development;\n'
                       'Keywords=REA;LexOS;Ollama;Projets;\nStartupNotify=false\n', encoding='utf-8')
    print(f'Installé : {launcher}\nMenu Applications : {desktop}')
    return desktop


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, default=Path.home() / '.local')
    parser.add_argument('--data-home', type=Path, default=Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')))
    options = parser.parse_args()
    try:
        import tkinter  # noqa: F401 — validation avant toute copie
        install(options.prefix.expanduser().absolute(), options.data_home.expanduser().absolute())
    except (ImportError, OSError, ValueError) as exc:
        sys.exit(f'Installation impossible : {exc}\nPrérequis : sudo apt install python3 python3-tk')


if __name__ == '__main__':
    main()
