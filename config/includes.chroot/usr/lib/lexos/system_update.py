#!/usr/bin/env python3
"""Installer uniquement les paquets LexOS publiés dans le dépôt officiel."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request

REPO = 'alexmarceauprevost812-source/lexOS-2.0'
TAG = 'updates-pro'
PACKAGE = 'lexos-system'
LIMIT = 512 * 1024 * 1024


def latest():
    request = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}/releases/tags/{TAG}',
        headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'LexOS-Updater'})
    with urllib.request.urlopen(request, timeout=20) as response:
        release = json.loads(response.read(2 * 1024 * 1024))
    for asset in sorted(release.get('assets', []), key=lambda a: a.get('name', ''), reverse=True):
        match = re.fullmatch(r'lexos-system_(\d{14}\+[0-9a-f]{7,40})_amd64\.deb', asset.get('name', ''))
        digest = asset.get('digest', '') or ''
        url = asset.get('browser_download_url', '')
        if (match and re.fullmatch(r'sha256:[0-9a-f]{64}', digest)
                and url.startswith(f'https://github.com/{REPO}/releases/download/{TAG}/')
                and asset.get('state') == 'uploaded' and 0 < asset.get('size', 0) <= LIMIT):
            return asset, match[1]
    raise RuntimeError('Aucun paquet de mise à jour complet et vérifiable publié pour LexOS Pro.')


def installed():
    result = subprocess.run(['dpkg-query', '-W', '-f=${Version}', PACKAGE],
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else '0'


def download(asset, target):
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(asset['browser_download_url'], headers={'User-Agent': 'LexOS-Updater'})
    with urllib.request.urlopen(request, timeout=30) as response, target.open('wb') as out:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > LIMIT or total > asset['size']:
                raise RuntimeError('Téléchargement trop volumineux : installation annulée.')
            out.write(chunk)
            digest.update(chunk)
    if total != asset['size'] or 'sha256:' + digest.hexdigest() != asset['digest']:
        raise RuntimeError('Empreinte ou taille incorrecte : installation annulée.')


def main():
    parser = argparse.ArgumentParser(description='Mettre LexOS Pro à jour depuis son GitHub officiel.')
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.install and os.geteuid() != 0:
        os.execvp('sudo', ['sudo', '/usr/bin/lexos-system-update', '--install'])
    try:
        asset, version = latest()
        current = installed()
        if subprocess.run(['dpkg', '--compare-versions', version, 'gt', current]).returncode != 0:
            print(f'LexOS est à jour ({current}).')
            return 0
        print(f'Mise à jour LexOS disponible : {version} (version installée : {current}).')
        if not args.install:
            print('Pour installer : lexos-system-update --install')
            return 0
        if 'boot=live' in Path('/proc/cmdline').read_text():
            raise RuntimeError("Installe d'abord LexOS sur le disque : une session live ne conserve pas cette mise à jour.")
        with tempfile.TemporaryDirectory(prefix='lexos-update-') as directory:
            target = Path(directory)/asset['name']
            download(asset, target)
            for field, expected in [('Package', PACKAGE), ('Version', version), ('Architecture', 'amd64')]:
                actual = subprocess.check_output(['dpkg-deb', '-f', str(target), field], text=True).strip()
                if actual != expected:
                    raise RuntimeError(f'Paquet inattendu ({field}) : installation annulée.')
            # APT gère les dépendances, sans autoriser le retrait d'autres paquets.
            subprocess.run(['apt-get', 'install', '--no-remove', str(target)], check=True)
        print('LexOS mis à jour. Ferme et rouvre les applications LexOS pour charger les nouveaux fichiers.')
        print('Aucune clé USB ni réinstallation nécessaire. Aucun redémarrage automatique.')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Mise à jour interrompue : {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
