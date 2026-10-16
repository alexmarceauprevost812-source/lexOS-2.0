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
