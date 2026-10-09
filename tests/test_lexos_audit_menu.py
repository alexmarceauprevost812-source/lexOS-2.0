#!/usr/bin/env python3
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
R = Path(__file__).resolve().parents[1]
INCLUDE = R/'config/includes.chroot'
SCRIPT = INCLUDE/'usr/lib/lexos/audit/menu.py'
spec = importlib.util.spec_from_file_location('audit_menu', SCRIPT)
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)

class Menu(unittest.TestCase):
    def test_all_packages_once(self):
        groups = menu.catalogue(INCLUDE/'usr/share/lexos/audit-tools.packages')
        packages = [p for group in groups.values() for p in group]
        self.assertEqual(len(groups), 7)
        self.assertEqual(len(packages), 100)
        self.assertEqual(len(set(packages)), 100)
        self.assertIn('johnny', groups['Mots de passe'])

    def test_skeleton_preserves_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            relative = Path('etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml')
            path = root/relative
            path.parent.mkdir(parents=True)
            shutil.copyfile(INCLUDE/relative, path)
            old = ET.parse(path).getroot()
            old_ids = old.find("./property[@name='panels']/property[@name='panel-1']/property[@name='plugin-ids']")
            ids_before = [v.attrib['value'] for v in old_ids]
            plugins_before = {p.attrib['name']: ET.tostring(p) for p in old.find("./property[@name='plugins']")}
            menu.skeleton(root)
            before = path.read_bytes()
            menu.skeleton(root)
            self.assertEqual(path.read_bytes(), before)
            new = ET.parse(path).getroot()
            ids = new.find("./property[@name='panels']/property[@name='panel-1']/property[@name='plugin-ids']")
            values = [v.attrib['value'] for v in ids]
            self.assertEqual([values[0]] + values[2:], ids_before)
            self.assertEqual(len(set(values)), len(values))
            # Compare attributes/descendants, independent of whitespace formatting.
            for name in plugins_before:
                a = old.find(f"./property[@name='plugins']/property[@name='{name}']")
                b = new.find(f"./property[@name='plugins']/property[@name='{name}']")
                self.assertEqual([n.attrib for n in a.iter()], [n.attrib for n in b.iter()])

    def test_terminal_does_not_run_audit_tool(self):
        with patch.object(menu.shutil, 'which', return_value='/usr/bin/xfce4-terminal'), patch.object(menu.subprocess, 'Popen') as popen:
            menu.launch('hashcat')
            args = popen.call_args.args[0]
            self.assertEqual(args[0], '/usr/bin/xfce4-terminal')
            self.assertEqual(args[-2:], ['--console', 'hashcat'])
            self.assertNotIn('sudo', args)
            self.assertNotIn('shell', popen.call_args.kwargs)

    def test_gui_uses_current_user(self):
        with patch.object(menu.shutil, 'which', return_value='/usr/local/bin/johnny'), patch.object(menu.subprocess, 'Popen') as popen:
            menu.launch('johnny')
            popen.assert_called_once_with(['/usr/local/bin/johnny'])

    def test_hook_only_pro(self):
        hook = R/'config/hooks/normal/0270-lexos-audit-menu.hook.chroot'
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root/'usr/lib/lexos/audit/menu.py'
            script.parent.mkdir(parents=True)
            shutil.copyfile(SCRIPT, script)
            relative = Path('etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml')
            panel = root/relative
            panel.parent.mkdir(parents=True)
            shutil.copyfile(INCLUDE/relative, panel)
            original = panel.read_bytes()
            conf = root/'build.conf'
            import os
            env = dict(os.environ, LEXOS_AUDIT_CONF=str(conf), LEXOS_AUDIT_ROOT=str(root))
            conf.write_text('LEXOS_FLAVOUR=standard\n')
            subprocess.run(['bash', str(hook)], env=env, check=True)
            self.assertEqual(panel.read_bytes(), original)
            conf.write_text('LEXOS_FLAVOUR=pro\n')
            subprocess.run(['bash', str(hook)], env=env, check=True)
            self.assertIn(b'lexos-audit.desktop', panel.read_bytes())

    @unittest.skipUnless(os.environ.get('DISPLAY'), 'Affichage GTK indisponible localement')
    def test_graphic_search(self):
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
        if not Gtk.init_check()[0]:
            if os.environ.get('LEXOS_AUDIT_REQUIRE_GTK') == '1':
                self.fail('Affichage GTK requis par la CI indisponible')
            self.skipTest('Affichage GTK inaccessible localement')
        def measure():
            window = next(w for w in Gtk.Window.list_toplevels() if w.get_title() == 'Outils d’audit — LexOS Pro')
            children = window.get_child().get_children()
            search = children[1]
            search.set_text('hashcat')
            search.emit('search-changed')
            scroll = children[3]
            categories = scroll.get_child().get_child().get_children()
            visible = [c for c in categories if c.get_visible()]
            self.assertEqual(len(visible), 1)
            self.assertEqual(visible[0].get_label(), 'Mots de passe')
            self.assertTrue(visible[0].get_expanded())
            buttons = [b for b in visible[0].get_child().get_children() if b.get_visible()]
            self.assertEqual([b.get_label() for b in buttons], ['hashcat'])
            # Hide first to avoid destroy callback ending a non-running GTK loop.
            window.hide()
        with patch.object(menu, 'DATA', INCLUDE/'usr/share/lexos/audit-tools.packages'), patch.object(menu, 'installed', return_value=True), patch.object(Gtk, 'main', side_effect=measure):
            # Default argument is bound at definition time: override catalogue's
            # data path without changing files under /usr/share on the runner.
            original = menu.catalogue
            with patch.object(menu, 'catalogue', side_effect=lambda: original(INCLUDE/'usr/share/lexos/audit-tools.packages')):
                menu.show()

    def test_banner_plain_when_redirected(self):
        output = io.StringIO()
        with patch.object(menu, 'tool_logo') as lookup:
            menu.logo_banner('hashcat', [], output)
        self.assertIn('hashcat · Outils d’audit LexOS', output.getvalue())
        self.assertNotIn('\033', output.getvalue())
        lookup.assert_not_called()

    def test_banner_missing_logo_keeps_title(self):
        output = io.StringIO()
        output.isatty = lambda: True
        with patch.dict(os.environ, {'TERM': 'xterm-256color', 'NO_COLOR': ''}), patch.object(menu, 'tool_logo', return_value=None):
            menu.logo_banner('hashcat', [], output)
        self.assertIn('hashcat · Outils d’audit LexOS', output.getvalue())

    def test_banner_renders_installed_image(self):
        import gi
        gi.require_version('GdkPixbuf', '2.0')
        from gi.repository import GdkPixbuf
        # Exercise the real pixel renderer with a small installed-asset fixture.
        with tempfile.TemporaryDirectory() as temp:
            image = Path(temp)/'logo.png'
            pixbuf = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 4, 4)
            pixbuf.fill(0xff8000ff)
            pixbuf.savev(str(image), 'png', [], [])
            output = io.StringIO()
            output.isatty = lambda: True
            with patch.dict(os.environ, {'TERM': 'xterm-256color', 'NO_COLOR': ''}), patch.object(menu, 'tool_logo', return_value=image):
                menu.logo_banner('hashcat', [], output)
            self.assertIn('▀', output.getvalue())
            self.assertIn('\033[38;2;255;128;0m', output.getvalue())

    def test_logo_and_desktop(self):
        ET.parse(INCLUDE/'usr/share/icons/hicolor/scalable/apps/lexos-kali-audit.svg')
        desktop = (INCLUDE/'usr/share/applications/lexos-audit.desktop').read_text()
        self.assertIn('Icon=lexos-kali-audit', desktop)
        self.assertIn('Exec=/usr/bin/python3 /usr/lib/lexos/audit/menu.py', desktop)

if __name__ == '__main__':
    unittest.main()
