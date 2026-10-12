#!/usr/bin/env python3
"""Banc du menu d'animations : sans Qt, X11, GPU, apt ni effets réels."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main, mock
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/includes.chroot/usr/lib/lexos/volet.py"
spec = importlib.util.spec_from_file_location("lexos_volet_effets_test", SOURCE)
volet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(volet)


class MenuEffets(TestCase):
    def test_actions_and_profiles_are_allowlisted(self):
        self.assertIn("rapides-effet", volet.ACTIONS)
        self.assertEqual(
            volet.EFFETS_PROFILS,
            ("crt", "fluide", "hologramme", "neon", "portail", "off"))
        for bad in ("../../etc/passwd", "neon;sh", "glitch", None, "", "CRT"):
            with self.subTest(bad=bad):
                with mock.patch.object(volet.subprocess, "run") as execute:
                    result = volet.act_rapides_effet(bad)
                    self.assertFalse(result["ok"])
                    execute.assert_not_called()

    def test_no_custom_script_disables_choice(self):
        with TemporaryDirectory() as tmp:
            with mock.patch.object(volet, "EFFETS_SCRIPT", Path(tmp)/"non-existant"):
                self.assertEqual(volet._effets_rapides_profil(), "indisponible")
                result = volet.act_rapides_effet("neon")
                self.assertFalse(result["ok"])

    def test_stored_profile_and_default_crt(self):
        with TemporaryDirectory() as tmp:
            base = Path(tmp)
            script = base / "lexos-effets"
            script.write_text("#!/usr/bin/env bash\n")
            (base / "effets").mkdir()
            with (mock.patch.object(volet, "EFFETS_SCRIPT", script),
                  mock.patch.object(volet, "CONF", base)):
                (base / "crt").write_text("on\n")
                self.assertEqual(volet._effets_rapides_profil(), "crt")
                (base / "effets/profil").write_text("neon\n")
                self.assertEqual(volet._effets_rapides_profil(), "neon")
                (base / "effets/profil").write_text("bad\n")
                self.assertEqual(volet._effets_rapides_profil(), "crt")
                (base / "crt").write_text("off\n")
                self.assertEqual(volet._effets_rapides_profil(), "off")

    def test_profile_uses_fixed_argv_and_reinstalls_autostart(self):
        with TemporaryDirectory() as tmp:
            script = Path(tmp) / "lexos-effets"
            script.write_text("#!/usr/bin/env bash\n")
            success = subprocess.CompletedProcess([], 0, "effect ready", "")
            with (mock.patch.object(volet, "EFFETS_SCRIPT", script),
                  mock.patch.object(volet.subprocess, "run",
                                    return_value=success) as run):
                self.assertTrue(volet.act_rapides_effet("neon")["ok"])
                self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args_list[0].args[0],
                                 ["bash", str(script), "installer"])
                self.assertEqual(run.call_args_list[1].args[0],
                                 ["bash", str(script), "neon"])
                self.assertFalse(any(k.get("shell") is True
                                     for _, k in run.call_args_list))
                self.assertEqual(run.call_args_list[1].kwargs["timeout"], 30)
                run.reset_mock()
                self.assertTrue(volet.act_rapides_effet("crt")["ok"])
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[0],
                                 ["bash", str(script), "crt"])
                run.reset_mock()
                self.assertTrue(volet.act_rapides_effet("off")["ok"])
                self.assertEqual(run.call_count, 1)

    def test_failure_carries_reason_without_claiming_success(self):
        with TemporaryDirectory() as tmp:
            script = Path(tmp) / "lexos-effets"
            script.write_text("#!/usr/bin/env bash\n")
            failure = subprocess.CompletedProcess([], 1, "", "Picom encore en marche")
            with (mock.patch.object(volet, "EFFETS_SCRIPT", script),
                  mock.patch.object(volet.subprocess, "run",
                                    side_effect=[subprocess.CompletedProcess([], 0, "", ""),
                                                 failure])):
                result = volet.act_rapides_effet("portail")
                self.assertFalse(result["ok"])
                self.assertIn("Picom encore en marche", result["erreur"])
            with (mock.patch.object(volet, "EFFETS_SCRIPT", script),
                  mock.patch.object(volet.subprocess, "run",
                                    side_effect=subprocess.TimeoutExpired("bash", 30))):
                self.assertFalse(volet.act_rapides_effet("neon")["ok"])

    def test_script_is_shipped_in_update_tree(self):
        script = ROOT / "config/includes.chroot/usr/share/lexos/picom/lexos-effets"
        text = script.read_text()
        self.assertIn("attendre_picom_libre()", text)
        self.assertIn("picom_personnalise()", text)
        self.assertIn('"$CRT" off || return 1', text)
        self.assertIn("Exec=/bin/bash $SELF --autostart", text)
        self.assertIn('nohup bash "$SELF" --superviser', text)
        crt = (ROOT / "config/includes.chroot/usr/bin/lexos-crt").read_text()
        self.assertIn("CRT désactivé — aucune relance", crt)
        self.assertIn("CRT éteint par l'utilisateur", crt)


if __name__ == "__main__":
    main()
