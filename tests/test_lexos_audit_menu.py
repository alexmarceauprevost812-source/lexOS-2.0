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
    def setUp(self):
        manifeste = patch.object(menu, 'DATA', INCLUDE/'usr/share/lexos/audit-tools.packages')
        manifeste.start()
        self.addCleanup(manifeste.stop)

    def test_console_banner_precedes_short_command_list(self):
        output = io.StringIO()
        with patch.object(menu, 'use_colour', return_value=True), \
             patch.object(menu.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
             patch.object(menu, 'commandes_package', return_value=['/usr/bin/outil'] * 12), \
             patch.object(menu, 'logo_banner', side_effect=lambda *args: print('IMAGE OFFICIELLE')), \
             patch.object(menu, 'tool_help') as aide, \
             patch.object(menu.os, 'execv') as shell, \
             patch('sys.stdout', output):
            menu.console('nmap')
        self.assertTrue(output.getvalue().startswith('\033[2J\033[HIMAGE OFFICIELLE'))
        self.assertEqual(output.getvalue().count('/usr/bin/outil'), 8)
        self.assertIn('4 autres', output.getvalue())
        aide.assert_not_called()
        shell.assert_called_once_with('/bin/bash', ['/bin/bash', '-i'])

    def test_categories_have_unique_readable_symbols(self):
        groupes = menu.catalogue(INCLUDE/'usr/share/lexos/audit-tools.packages')
        self.assertEqual(set(groupes), set(menu.EMOJIS))
        for nom in groupes:
            self.assertTrue(menu.titre_categorie(nom).endswith(nom))

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
        with patch.object(menu.shutil, 'which', return_value='/usr/bin/lexos-pro-terminal'), patch.object(menu.subprocess, 'Popen') as popen:
            menu.launch('hashcat')
            args = popen.call_args.args[0]
            self.assertEqual(args[0], '/usr/bin/lexos-pro-terminal')
            self.assertEqual(args[-2:], ['--console', 'hashcat'])
            self.assertIn('-e', args)
            self.assertNotIn('xfce4-terminal', args)
            self.assertNotIn('sudo', args)
            self.assertNotIn('shell', popen.call_args.kwargs)

    def test_terminal_catalogue_has_no_automatic_command_execution(self):
        # Cliquer « Audit » n'exécute aucune commande du catalogue.
        answers = iter(['1', '1', 'b', 'q'])
        sortie = []
        with patch.object(menu, 'installed', return_value=False), \
             patch.object(menu.subprocess, 'Popen') as popen, \
             patch.object(menu.subprocess, 'run') as run:
            menu.menu_terminal(lire=lambda _: next(answers), ecrire=sortie.append)
            popen.assert_not_called()
            run.assert_not_called()
        self.assertIn('aucun outil', '\n'.join(sortie).lower())
        self.assertIn('non installé', '\n'.join(sortie).lower())

    def test_terminal_catalogue_rejects_untrusted_selection(self):
        answers = iter(['; echo MALVEILLANT', '-1', '700', 'q'])
        sortie = []
        with patch.object(menu.subprocess, 'run') as run, \
             patch.object(menu.subprocess, 'Popen') as popen:
            menu.menu_terminal(lire=lambda _: next(answers), ecrire=sortie.append)
        run.assert_not_called()
        popen.assert_not_called()
        self.assertIn('numéro valide', '\n'.join(sortie))

    def test_terminal_catalogue_reads_only_installed_file_list(self):
        answers = iter(['1', '1', 'q'])
        sortie = []
        with patch.object(menu, 'installed', return_value=True), \
             patch.object(menu.os, 'access', return_value=True), \
             patch.object(menu.subprocess, 'run', return_value=subprocess.CompletedProcess(
                 [], 0, '/usr/bin/outil\n/etc/config\n', '')) as run:
            menu.menu_terminal(lire=lambda _: next(answers), ecrire=sortie.append)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][:2], ['dpkg-query', '-L'])
        self.assertIn('/usr/bin/outil', '\n'.join(sortie))
        self.assertNotIn('/etc/config', '\n'.join(sortie))

    def test_commande_listing_filters_only_installed_executables(self):
        fixture = ('/usr/bin/afficher-exemple\n'
                   '/usr/sbin/verifier-exemple\n'
                   '/usr/local/bin/outil-local\n'
                   '/usr/share/doc/test/fichier\n'
                   '/etc/inconnu\n'
                   '/usr/bin/afficher-exemple\n')
        with patch.object(menu.os, 'access', return_value=True), \
             patch.object(menu.subprocess, 'run') as run:
            commandes = menu.commandes_package('exemple', fixture)
            run.assert_not_called()
        self.assertEqual(commandes, [
            '/usr/bin/afficher-exemple', '/usr/local/bin/outil-local',
            '/usr/sbin/verifier-exemple'
        ])

    def test_all_commands_for_every_installed_package_is_read_only(self):
        groupes = {'Diagnostic': ['alpha', 'beta']}
        outputs = []
        with patch.object(menu, 'installed', side_effect=lambda p: p == 'alpha'), \
             patch.object(menu, 'commandes_package',
                          side_effect=lambda p: ['/usr/bin/exemple'] if p == 'alpha' else []), \
             patch.object(menu.subprocess, 'Popen') as popen:
            total = menu.toutes_commandes(groupes, outputs.append)
            popen.assert_not_called()
        self.assertEqual(total, 1)
        contenu = '\n'.join(outputs)
        self.assertIn('alpha', contenu)
        self.assertIn('beta — non installé', contenu)
        self.assertIn('/usr/bin/exemple', contenu)
        self.assertIn('aucune lancée', contenu)

    def test_100_tools_have_access_to_same_command_catalogue(self):
        groupes = menu.catalogue(INCLUDE/'usr/share/lexos/audit-tools.packages')
        vus = []
        with patch.object(menu, 'installed', return_value=True), \
             patch.object(menu, 'commandes_package', side_effect=lambda p: vus.append(p) or []), \
             patch.object(menu.subprocess, 'Popen') as popen:
            menu.toutes_commandes(groupes, lambda _: None)
            popen.assert_not_called()
        self.assertEqual(len(vus), 100)
        self.assertEqual(len(set(vus)), 100)

    def test_cli_and_gui_both_offer_all_command_names(self):
        cli = (INCLUDE/'usr/bin/lexos').read_text()
        page = (INCLUDE/'usr/lib/lexos/audit/menu.py').read_text()
        self.assertIn('--toutes-commandes', page)
        self.assertIn('commandes|--commandes|liste)', cli)
        self.assertIn('audit-icones|icones-audit)', cli)
        self.assertIn('montrer_commandes(paquet, fenetre, Gtk)', page)
        self.assertIn('bouton = Gtk.Button(label="Commandes")', page)
        self.assertNotIn('chemins[:40]', page)

    def test_terminal_audit_button_opens_same_terminal_in_a_new_tab(self):
        page = (INCLUDE/'usr/share/lexos/terminal-pro/web/index.html').read_text()
        cli = (INCLUDE/'usr/bin/lexos').read_text()
        desktop = (INCLUDE/'usr/share/applications/lexos-audit.desktop').read_text()
        hook = (R/'config/hooks/normal/0270-lexos-audit-menu.hook.chroot').read_text()
        panel = (INCLUDE/'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml').read_text()
        self.assertIn('id="audit"', page)
        self.assertIn('ouvrirAudit(){', page)
        self.assertIn('this.nouvelOnglet();', page)
        self.assertIn('this.active.envoyer("lexos audit menu\\r");', page)
        self.assertIn('audit|outils-audit)', cli)
        self.assertIn('exec /usr/bin/python3 /usr/lib/lexos/audit/menu.py --terminal', cli)
        self.assertIn('Exec=/usr/bin/python3 /usr/lib/lexos/audit/menu.py', desktop)
        self.assertNotIn('lexos-audit.desktop', panel)
        self.assertNotIn('--installer-squelette', hook)
        self.assertIn('lexos-pro-terminal.desktop', panel)

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
            # Nouveau modèle : le lanceur Audit est dans le Terminal Pro.
            # Le hook n'ajoute plus un deuxième bouton en haut du bureau.
            self.assertEqual(panel.read_bytes(), original)

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
            search, split = children[:2]
            sidebar = split.get_child1().get_child().get_child()
            right = split.get_child2()
            heading, scroll = right.get_children()[:2]
            tools = scroll.get_child().get_child()
            self.assertEqual(len(sidebar.get_children()), 8)
            sidebar.select_row(sidebar.get_row_at_index(4))
            self.assertIn('Mots de passe', heading.get_text())
            self.assertEqual(len([r for r in tools.get_children() if r.get_visible()]), 12)
            search.set_text('hashcat')
            search.emit('search-changed')
            visible = [r for r in tools.get_children() if r.get_visible()]
            self.assertEqual([r.audit_package for r in visible], ['hashcat'])
            search.set_text('outil-introuvable')
            search.emit('search-changed')
            self.assertFalse(any(r.get_visible() for r in tools.get_children()))
            self.assertTrue(right.get_children()[2].get_visible())
            search.set_text('')
            search.emit('search-changed')
            self.assertEqual(len([r for r in tools.get_children() if r.get_visible()]), 12)
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
            with patch.dict(os.environ, {'TERM': 'xterm-256color', 'NO_COLOR': ''}), patch.object(menu, 'icone_locale', return_value=None), patch.object(menu, 'tool_logo', return_value=image):
                menu.logo_banner('hashcat', [], output)
            self.assertIn('▀', output.getvalue())
            self.assertIn('\033[38;2;255;128;0m', output.getvalue())

    def test_help_colours_preserve_content(self):
        text = 'SCAN TECHNIQUES:\n  -sS --top-ports <number> [default: 100]\n'
        coloured = menu.colour_help(text)
        self.assertIn('\033[1;38;5;208mSCAN TECHNIQUES:', coloured)
        self.assertIn('\033[38;5;114m--top-ports', coloured)
        self.assertIn('\033[38;5;81m<number>', coloured)
        self.assertEqual(menu.ANSI.sub('', coloured), text)
        self.assertEqual(menu.colour_help(text, False), text)
        self.assertEqual(menu.colour_help('\033[32mAlready coloured\033[0m'), '\033[32mAlready coloured\033[0m')

    def test_only_help_runs_without_scan(self):
        with patch.object(menu.shutil, 'which', return_value='/usr/bin/nmap'), patch.object(menu.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = 'SCAN TECHNIQUES:\n'
            with patch('sys.stdout', io.StringIO()):
                menu.tool_help('nmap')
            self.assertEqual(run.call_args.args[0], ['nmap', '--help'])
            self.assertEqual(run.call_args.kwargs['timeout'], 10)
            run.reset_mock()
            menu.tool_help('testdisk')
            run.assert_not_called()

    def test_logo_and_desktop(self):
        ET.parse(INCLUDE/'usr/share/icons/hicolor/scalable/apps/lexos-kali-audit.svg')
        desktop = (INCLUDE/'usr/share/applications/lexos-audit.desktop').read_text()
        self.assertIn('Icon=/usr/share/lexos/audit-kali-logo.png', desktop)
        self.assertEqual((INCLUDE/'usr/share/lexos/audit-kali-logo.png').read_bytes()[:8], b'\x89PNG\r\n\x1a\n')
        self.assertIn('Name=Outils d’audit', desktop)
        self.assertIn('Exec=/usr/bin/python3 /usr/lib/lexos/audit/menu.py', desktop)

if __name__ == '__main__':
    unittest.main()
