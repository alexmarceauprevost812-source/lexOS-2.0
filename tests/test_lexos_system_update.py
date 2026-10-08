import hashlib
import ast
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('update', ROOT/'config/includes.chroot/usr/lib/lexos/system_update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


def asset(version='20261008180000+abcdef0', contents=b'package'):
    name = f'lexos-system_{version}_amd64.deb'
    return {'name': name, 'digest': 'sha256:'+hashlib.sha256(contents).hexdigest(),
            'state': 'uploaded', 'size': len(contents),
            'browser_download_url': f'https://github.com/{update.REPO}/releases/download/updates-pro/{name}'}


class UpdateTests(unittest.TestCase):
    def test_gui_reports_both_lexos_actions(self):
        tree = ast.parse((ROOT/'config/includes.chroot/usr/lib/lexos/settings.py').read_text(encoding='utf-8'))
        nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('_maj_etat', 'act_maj')]
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            scope = {'ETC_DIR': Path(directory), 'Path': Path,
                     '_outils': SimpleNamespace(commande_existe=lambda name: False),
                     '_maj_progres': lambda key: {'en_cours': False, 'ok': True},
                     '_terminal_suivi': lambda *args: calls.append(args) or {'ok': True}}
            exec(compile(ast.Module(body=nodes, type_ignores=[]), 'settings', 'exec'), scope)
            self.assertIn('lexos', scope['_maj_etat']()['progres'])
            self.assertIn('lexos-verifier', scope['_maj_etat']()['progres'])
            scope['act_maj']('lexos')
            self.assertEqual(calls[0][1:], ('lexos-system-update --install', 'lexos'))

    def test_latest_complete_package_wins(self):
        old, new = asset(), asset('20261009180000+abcdef1')
        with patch.object(update.urllib.request, 'urlopen', return_value=io.BytesIO(
                json.dumps({'assets': [old, new]}).encode())):
            self.assertEqual(update.latest()[1], '20261009180000+abcdef1')

    def test_foreign_url_and_missing_digest_rejected(self):
        for field, value in [('browser_download_url', 'https://example.org/file.deb'), ('digest', '')]:
            bad = asset(); bad[field] = value
            with patch.object(update.urllib.request, 'urlopen', return_value=io.BytesIO(
                    json.dumps({'assets': [bad]}).encode())):
                with self.assertRaises(RuntimeError):
                    update.latest()

    def test_download_hash_and_size_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'package.deb'
            with patch.object(update.urllib.request, 'urlopen', return_value=io.BytesIO(b'package')):
                update.download(asset(), target)
            self.assertEqual(target.read_bytes(), b'package')
            with patch.object(update.urllib.request, 'urlopen', return_value=io.BytesIO(b'corrupt')):
                with self.assertRaises(RuntimeError):
                    update.download(asset(), target)
            with patch.object(update.urllib.request, 'urlopen', return_value=io.BytesIO(b'short')):
                with self.assertRaises(RuntimeError):
                    update.download(asset(), target)


if __name__ == '__main__':
    unittest.main()
