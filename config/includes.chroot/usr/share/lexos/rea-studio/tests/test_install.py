import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_install_and_launch_version_with_special_path(self):
        with tempfile.TemporaryDirectory(prefix='rea espace $ dollar ') as directory:
            root = Path(directory)
            desktop = installer.install(root / 'prefix', root / 'xdg')
            subprocess.run(['desktop-file-validate', str(desktop)], check=True)
            result = subprocess.run([str(root / 'prefix/bin/rea-studio'), '--version'], capture_output=True, text=True, check=True)
            self.assertIn('REA Studio 0.2.0', result.stdout)
            self.assertIn('Icon=', desktop.read_text())
            installer.install(root / 'prefix', root / 'xdg')
            self.assertTrue((root / 'prefix/bin/rea-studio').is_symlink())

    def test_existing_unmanaged_launcher_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            launcher = root / 'bin/rea-studio'
            launcher.write_text('keep')
            with self.assertRaises(ValueError):
                installer.install(root, root / 'data')
            self.assertEqual(launcher.read_text(), 'keep')
