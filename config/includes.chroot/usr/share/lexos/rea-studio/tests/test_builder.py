import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from rea_studio.builder import generate_application, load_application, parse_plan, save_application, validate_plan
from rea_studio.providers import Codex


def sample():
    return {'title': 'Test', 'summary': 'Petit exemple', 'target': 'desktop', 'entrypoint': 'main.py',
            'files': [{'path': 'main.py', 'content': 'print("bonjour")\n'},
                      {'path': 'README.md', 'content': 'Lancer python3 main.py'}]}


class BuilderTests(unittest.TestCase):
    def test_rejects_paths_outside_project_and_special_files(self):
        for path in ['../out.py', '/tmp/out.py', 'a/../../out.py', 'a//x.py', 'a\\x.py',
                     'C:/x.py', '.git/config', 'a/.hidden.py', 'sudo.sh', 'test.desktop', 'rea-project.json', 'bad\x00.py']:
            value = sample()
            value['files'].append({'path': path, 'content': 'test'})
            with self.subTest(path=path), self.assertRaises(ValueError):
                validate_plan(value)

    def test_requires_real_entrypoint_and_consistent_target(self):
        value = sample()
        value['entrypoint'] = 'absent.py'
        with self.assertRaises(ValueError):
            validate_plan(value)
        with self.assertRaises(ValueError):
            validate_plan(sample(), 'web')

    def test_rejects_duplicate_file_and_directory_collision(self):
        for path in ['MAIN.PY', 'main.py/test.txt']:
            value = sample()
            value['files'].append({'path': path, 'content': 'text'})
            with self.assertRaises(ValueError):
                validate_plan(value)

    def test_checks_python_syntax_without_execution(self):
        value = sample()
        value['files'][0]['content'] = 'if broken\n'
        with self.assertRaisesRegex(ValueError, 'Syntaxe Python'):
            validate_plan(value)
        value['files'][0]['content'] = 'raise RuntimeError("must not execute")'
        self.assertEqual(validate_plan(value), value)

    def test_limits_size_and_file_count(self):
        value = sample()
        value['files'][1]['content'] = 'x' * 1_000_001
        with self.assertRaises(ValueError):
            validate_plan(value)
        value = sample()
        value['files'] = []
        with self.assertRaises(ValueError):
            validate_plan(value)

    def test_versions_never_overwrite_existing_or_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'application').mkdir()
            (root / 'application/keep.txt').write_text('keep')
            (root / 'application-2').symlink_to(root / 'absent', target_is_directory=True)
            output = save_application({'path': directory}, sample())
            self.assertEqual(output.name, 'application-3')
            self.assertEqual((root / 'application/keep.txt').read_text(), 'keep')
            self.assertEqual(load_application(output), sample())
            self.assertEqual(list(root.glob('.rea-build-*')), [])

    def test_write_failure_cleans_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch('pathlib.Path.write_text', side_effect=OSError('disk full')):
                with self.assertRaises(OSError):
                    save_application({'path': directory}, sample())
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_loading_rejects_symlink_and_reads_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            output = save_application({'path': directory}, sample())
            (output / 'main.py').write_text('print("edited")')
            self.assertEqual(load_application(output)['files'][0]['content'], 'print("edited")')
            (output / 'main.py').unlink()
            (output / 'main.py').symlink_to(Path(directory) / 'other.py')
            with self.assertRaises((ValueError, OSError)):
                load_application(output)

    def test_one_repair_only_and_original_plan_kept(self):
        client = Mock()
        client.structured.side_effect = ['bad json', json.dumps(sample())]
        result = generate_application(client, 'local', 'Un exemple', 'desktop')
        self.assertEqual(result, sample())
        self.assertEqual(client.structured.call_count, 2)
        client.structured.side_effect = ['bad json', 'still bad']
        with self.assertRaises(ValueError):
            generate_application(client, 'local', 'Un exemple', 'desktop')
        original = sample()
        client.structured.side_effect = None
        client.structured.return_value = json.dumps(original)
        generate_application(client, 'local', 'Améliore', 'desktop', original)
        self.assertEqual(original, sample())

    def test_markdown_json_and_invalid_json(self):
        self.assertEqual(parse_plan('```json\n' + json.dumps(sample()) + '\n```'), sample())
        with self.assertRaises(ValueError):
            parse_plan('{truncated')

    def test_codex_command_is_read_only_and_schema_bound(self):
        process = Mock(returncode=0)
        captured = {}
        def launch(argv, **kwargs):
            captured['argv'], captured['kwargs'] = argv, kwargs
            Path(argv[argv.index('--output-last-message') + 1]).write_text(json.dumps(sample()))
            return process
        with patch('rea_studio.providers.codex_executable', return_value='/bin/codex'), patch('rea_studio.providers.subprocess.Popen', side_effect=launch):
            value = Codex().structured('', [{'role': 'user', 'content': 'test'}], {})
        self.assertEqual(json.loads(value), sample())
        self.assertIn('read-only', captured['argv'])
        self.assertIn('--ignore-user-config', captured['argv'])
        self.assertIn('--output-schema', captured['argv'])
        self.assertNotIn('sudo', captured['argv'])
        self.assertFalse(captured['kwargs'].get('shell', False))
