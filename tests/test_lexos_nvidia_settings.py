"""Exercise the build hook without modifying the host's packages."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / 'config/hooks/normal/0270-lexos-nvidia-settings.hook.chroot'


class NvidiaSettingsTests(unittest.TestCase):
    def run_hook(self, flavour='pro', fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'build.conf'
            config.write_text('LEXOS_FLAVOUR=' + flavour + '\n')
            apps = root / 'applications'
            log = root / 'apt.log'
            for name, body in {
                'apt-get': 'printf "%s\\n" "$*" >> "$APT_LOG"\n'
                           'case " $* " in *" --no-install-recommends "*) ;; *) exit 9;; esac\n'
                           'case " $* " in *" --no-remove "*) ;; *) exit 10;; esac\n'
                           'exit "$APT_EXIT"\n',
                'apt-mark': 'exit 0\n',
                'nvidia-settings': 'exit 0\n',
            }.items():
                command = root / name
                command.write_text('#!/bin/sh\n' + body)
                command.chmod(0o755)
            script = HOOK.read_text().replace('/etc/lexos/build.conf', str(config))
            script = script.replace('/usr/local/share/applications', str(apps))
            env = dict(os.environ, PATH=str(root)+':'+os.environ['PATH'],
                       APT_LOG=str(log), APT_EXIT='42' if fail else '0')
            result = subprocess.run(['sh'], input=script, text=True, env=env,
                                    capture_output=True)
            return result, log.read_text() if log.exists() else '', (apps/'lexos-nvidia.desktop').exists()

    def test_pro_installs_settings_without_replacing_driver(self):
        result, calls, launcher = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.strip(), 'install -y --no-remove --no-install-recommends nvidia-settings')
        self.assertTrue(launcher)

    def test_dependency_failure_stops_build(self):
        result, _, launcher = self.run_hook(fail=True)
        self.assertEqual(result.returncode, 42)
        self.assertFalse(launcher)

    def test_other_flavours_do_not_install(self):
        result, calls, launcher = self.run_hook('standard')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, '')
        self.assertFalse(launcher)


if __name__ == '__main__':
    unittest.main()
