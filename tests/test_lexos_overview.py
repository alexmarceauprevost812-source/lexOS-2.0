"""Tests hors écran : filtrage XDG, navigation et mesures indisponibles."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('overview', ROOT/'config/includes.chroot/usr/lib/lexos/overview.py')
overview = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(overview)


class OverviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = overview.QApplication.instance() or overview.QApplication([])

    def test_xdg_hidden_override_and_desktop_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('user', 'system'):
                (root/name/'applications').mkdir(parents=True)
            def entry(folder, name, extra=''):
                (root/folder/'applications'/name).write_text(
                    '[Desktop Entry]\nType=Application\nName=Example\nExec=true\n'+extra,
                    encoding='utf-8')
            entry('system', 'hidden.desktop')
            entry('user', 'hidden.desktop', 'Hidden=true\n')
            entry('system', 'foreign.desktop', 'OnlyShowIn=GNOME;\n')
            entry('system', 'visible.desktop', 'OnlyShowIn=XFCE;\nName[fr]=Visible\n')
            entry('system', 'missing.desktop', 'TryExec=lexos-does-not-exist-987654\n')
            with patch.dict(os.environ, {'XDG_DATA_HOME': str(root/'user'),
                    'XDG_DATA_DIRS': str(root/'system'), 'XDG_CURRENT_DESKTOP': 'XFCE'}):
                rows = overview.applications()
            self.assertEqual([row[0] for row in rows], ['Visible'])

    def test_pages_search_and_unavailable_gpu(self):
        rows = [(f'Application {n}', '', '/tmp/example.desktop') for n in range(25)]
        with patch.object(overview, 'applications', return_value=rows), \
                patch.object(overview.Overview, 'sample'):
            view = overview.Overview()
        try:
            self.assertEqual(view.pages.count(), 3)
            view.change_page(1)
            self.assertEqual(view.pages.currentIndex(), 1)
            view.search.setText('absent')
            self.assertEqual(view.pages.count(), 1)
            view.refresh({'gpu': None, 'disk': (50, 100, 50),
                          'desktops': '0 * DG: 100x100 VP: 0,0 WA: 0,0 100x100 Bureau 1\n'
                                      '1 - DG: 100x100 VP: 0,0 WA: 0,0 100x100 Bureau 2',
                          'windows': ''})
            self.assertEqual(view.workspace_layout.count(), 2)
            self.assertEqual(view.temp.detail, 'Indisponible')
            self.assertEqual(view.vram.detail, 'Indisponible')
            view.refresh({'gpu': ('RTX 5060', 55, 2048, 8192), 'disk': (50, 100, 50),
                          'desktops': '', 'windows': ''})
            self.assertEqual(view.gpu_label.text(), 'RTX 5060')
            self.assertEqual(view.temp.detail, '55 °C')
            self.assertEqual(view.vram.detail, '2048 / 8192 Mio')
        finally:
            view.close()

    def test_command_failure_and_launch_no_shell(self):
        with patch.object(overview.subprocess, 'run', side_effect=FileNotFoundError):
            self.assertEqual(overview.command(['missing']), '')
        with patch.object(overview, 'applications', return_value=[]), \
                patch.object(overview.Overview, 'sample'):
            view = overview.Overview()
        with patch.object(overview.subprocess, 'Popen') as launch:
            view.launch('/tmp/name; echo ignored.desktop')
            launch.assert_called_once_with(['gio', 'launch', '/tmp/name; echo ignored.desktop'])


if __name__ == '__main__':
    unittest.main()
