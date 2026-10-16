import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from rea_studio.core import Projects, atomic_write, launch_tool, note_path, tool_command, validate_tools


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.store = Projects(self.root / 'data')

    def test_project_lifecycle_preserves_existing_files(self):
        project = self.store.create(self.root, 'Mon atelier é')
        file = Path(project['path']) / 'existant.txt'
        file.write_text('original')
        self.assertEqual(self.store.add(project['path'])['id'], project['id'])
        self.store.rename(project['id'], 'Nouveau nom')
        self.assertEqual(Projects(self.root / 'data').list()[0]['name'], 'Nouveau nom')
        self.store.forget(project['id'])
        self.assertEqual(self.store.list(), [])
        self.assertEqual(file.read_text(), 'original')

    def test_invalid_and_existing_names_never_overwrite(self):
        for name in ['../escape', '.', '..', '', '/tmp/out', 'a/b', 'a\\b', 'bad\x00']:
            with self.subTest(name=name), self.assertRaises((ValueError, OSError)):
                self.store.create(self.root, name)
        self.store.create(self.root, 'unique')
        with self.assertRaises(FileExistsError):
            self.store.create(self.root, 'unique')

    def test_corrupt_registry_is_preserved(self):
        self.store.directory.mkdir()
        self.store.file.write_text('{bad')
        with self.assertRaises(ValueError):
            self.store.create(self.root, 'do-not-create')
        self.assertFalse((self.root / 'do-not-create').exists())
        self.assertEqual(self.store.file.read_text(), '{bad')
        self.store.file.write_text('[{"id": 4}]')
        with self.assertRaises(ValueError):
            self.store.list()

    def test_notes_and_symlinks(self):
        project = self.store.create(self.root, 'notes')
        path = note_path(project)
        atomic_write(path, 'été\nseconde ligne')
        self.assertEqual(path.read_text(), 'été\nseconde ligne')
        outside = self.root / 'outside'
        outside.mkdir()
        path.unlink()
        path.parent.rmdir()
        path.parent.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            note_path(project)

    def test_atomic_failure_retains_old_notes(self):
        path = self.root / 'notes'
        path.write_text('original')
        with patch('rea_studio.core.os.replace', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                atomic_write(path, 'new')
        self.assertEqual(path.read_text(), 'original')
        self.assertEqual(list(self.root.glob('.rea-*')), [])

    def test_multiple_store_instances_keep_updates(self):
        other = Projects(self.root / 'data')
        self.store.create(self.root, 'one')
        other.create(self.root, 'two')
        self.assertEqual(len(self.store.list()), 2)

    def test_tool_arguments_do_not_invoke_shell(self):
        project = self.store.create(self.root, 'a ; touch bad')
        tool = {'name': 'Test', 'argv': [sys.executable, '-c', 'print(1)', '{project}', '$(touch bad)']}
        with patch('rea_studio.core.subprocess.Popen') as popen:
            launch_tool(tool, project)
        args, kwargs = popen.call_args
        self.assertEqual(args[0][-2], project['path'])
        self.assertEqual(args[0][-1], '$(touch bad)')
        self.assertFalse(kwargs.get('shell', False))
        self.assertEqual(kwargs['cwd'], Path(project['path']))

    def test_tools_validation_and_missing_executable(self):
        for tools in [{}, [{'name': 'X', 'argv': 'ls'}], [{'name': 'X', 'argv': ['ls'], 'terminal': 'yes'}]]:
            with self.assertRaises(ValueError):
                validate_tools(tools)
        project = self.store.create(self.root, 'tool')
        with self.assertRaisesRegex(ValueError, 'Outil absent'):
            tool_command({'name': 'missing', 'argv': ['rea-tool-that-does-not-exist']}, project)
        with patch('rea_studio.core.shutil.which', side_effect=lambda x: None if x == 'xfce4-terminal' else '/bin/echo'):
            with self.assertRaisesRegex(ValueError, 'xfce4-terminal'):
                tool_command({'name': 'T', 'argv': ['echo', 'test'], 'terminal': True}, project)


if __name__ == '__main__':
    unittest.main()
