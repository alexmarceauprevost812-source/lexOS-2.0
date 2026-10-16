import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch


@unittest.skipUnless(os.environ.get('DISPLAY'), 'Écran graphique nécessaire')
class GuiTests(unittest.TestCase):
    def setUp(self):
        from rea_studio.app import Studio
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app = Studio(self.root / 'data', self.root / 'config')
        self.addCleanup(self.app.destroy)
        self.app.update()

    def select(self, project):
        self.app.choose(project)
        self.app.update()

    def test_window_project_notes_and_unsaved_cancel(self):
        app = self.app
        first = app.projects.create(self.root, 'premier')
        second = app.projects.create(self.root, 'second')
        self.select(first)
        app.notes.insert('1.0', 'Mes idées')
        app.update()
        self.assertTrue(app.dirty)
        with patch('rea_studio.app.messagebox.askyesnocancel', return_value=None):
            app.project_list.selection_set(second['id'])
            app._select_project()
            app.update()
        self.assertEqual(app.current['id'], first['id'])
        app.save_notes()
        self.select(second)
        self.select(first)
        self.assertEqual(app.notes.get('1.0', 'end-1c'), 'Mes idées')
        app.notebook.select(1)
        app.update()
        self.assertGreater(app.notes.winfo_height(), 50)
        app.geometry('800x600')
        app.update()
        self.assertGreater(app.send_button.winfo_reqheight(), 20)
        app.configure_tools()
        app.update()
        self.assertEqual(len([w for w in app.winfo_children() if w.winfo_class() == 'Toplevel']), 1)

    def test_chat_runs_off_ui_and_preserves_new_draft(self):
        app = self.app
        self.select(app.projects.create(self.root, 'IA'))
        app.models['values'] = ['test:1']
        app.model.set('test:1')
        app.prompt.insert('1.0', 'Bonjour')
        def reply(*args):
            time.sleep(0.05)
            return 'Salut'
        with patch('rea_studio.ollama.Ollama.chat', side_effect=reply):
            app.send()
            self.assertTrue(app.busy)
            app.prompt.delete('1.0', 'end')
            app.prompt.insert('1.0', 'Nouvelle idée')
            deadline = time.monotonic() + 3
            while app.busy and time.monotonic() < deadline:
                app.update()
                time.sleep(0.01)
        self.assertFalse(app.busy)
        self.assertEqual(app.history()[-1]['content'], 'Salut')
        self.assertEqual(app.prompt.get('1.0', 'end-1c'), 'Nouvelle idée')
        self.assertFalse((Path(app.current['path']) / '.rea-studio').exists())

    def test_network_failure_keeps_prompt_and_recovers_controls(self):
        app = self.app
        self.select(app.projects.create(self.root, 'Erreur'))
        app.models['values'] = ['test:1']
        app.model.set('test:1')
        app.prompt.insert('1.0', 'À conserver')
        with patch('rea_studio.ollama.Ollama.chat', side_effect=ValueError('indisponible')), patch('rea_studio.app.messagebox.showerror'):
            app.send()
            deadline = time.monotonic() + 3
            while app.busy and time.monotonic() < deadline:
                app.update()
                time.sleep(0.01)
        self.assertFalse(app.busy)
        self.assertEqual(app.prompt.get('1.0', 'end-1c'), 'À conserver')
        self.assertEqual(app.history(), [])
        self.assertFalse(app.send_button.instate(['disabled']))

    def test_workshop_generates_saves_and_keeps_versions(self):
        from test_builder import sample
        app = self.app
        self.select(app.projects.create(self.root, 'Création'))
        app.models['values'] = ['test:1']
        app.model.set('test:1')
        workshop = app.workshop
        workshop.example()
        with patch('rea_studio.workshop.generate_application', return_value=sample()):
            workshop.generate_app()
            deadline = time.monotonic() + 3
            while app.busy and time.monotonic() < deadline:
                app.update()
                time.sleep(0.01)
        self.assertFalse(app.busy)
        self.assertFalse((Path(app.current['path']) / 'application').exists())
        self.assertEqual(workshop.files.size(), 2)
        workshop.save_files()
        first = workshop.saved
        self.assertTrue((first / 'main.py').exists())
        self.assertFalse(workshop.run.instate(['disabled']))
        with patch('rea_studio.workshop.messagebox.askyesno', return_value=True), patch('rea_studio.workshop.subprocess.Popen') as popen:
            workshop.run_application()
        argv = popen.call_args.args[0]
        self.assertEqual(argv[-1], str(first / 'main.py'))
        self.assertNotIn('sudo', argv)
        workshop.save_files()
        self.assertNotEqual(workshop.saved, first)
        self.assertTrue((first / 'main.py').exists())
        from rea_studio.app import Studio
        reopened = Studio(self.root / 'data', self.root / 'config')
        try:
            self.assertEqual(reopened.current['id'], app.current['id'])
            self.assertEqual(reopened.workshop.saved, workshop.saved)
            self.assertEqual(reopened.workshop.plan, workshop.plan)
        finally:
            reopened.destroy()

    def test_provider_choice_and_terminal_use_account_rights(self):
        app = self.app
        self.select(app.projects.create(self.root, 'Terminal ; test'))
        app.provider.set('Codex en ligne')
        app.provider_changed()
        client, model = app.selected_client(generation=True)
        self.assertEqual(type(client).__name__, 'Codex')
        self.assertTrue(app.models.instate(['disabled']))
        with patch('rea_studio.workshop.shutil.which', return_value='/usr/bin/xfce4-terminal'), patch('rea_studio.workshop.subprocess.Popen') as popen:
            app.workshop.open_terminal()
        argv = popen.call_args.args[0]
        self.assertEqual(argv[1], '--working-directory=' + app.current['path'])
        self.assertNotIn('sudo', argv)
        self.assertFalse(popen.call_args.kwargs.get('shell', False))
