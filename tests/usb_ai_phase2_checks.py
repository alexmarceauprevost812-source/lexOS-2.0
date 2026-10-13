#!/usr/bin/env python3
"""Banc isolé de la phase 2 : zéro manipulation de disque réel."""
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "usb-ai" / "ollama" / "doctor.py"
UNIT = ROOT / "usb-ai" / "systemd" / "ollama.service.d" / "10-lexos-usb-ai.conf"
ENV = ROOT / "usb-ai" / "ollama" / "offline.env.example"
spec = importlib.util.spec_from_file_location("lexos_usb_ai_doctor", SOURCE)
doctor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doctor)


class Phase2Tests(unittest.TestCase):
    def test_refuse_volume_absent_meme_si_repertoire_existe(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ollama" / "models").mkdir(parents=True)
            with patch.object(doctor.os.path, "ismount", return_value=False):
                etat = doctor.verifier(root, root / "inconnue.conf")
            self.assertFalse(etat["volume_donnees_monte"])
            self.assertFalse(etat["dossier_modeles_present"])
            self.assertFalse(etat["pre_requis_presents"])

    def test_volume_monte_avec_outils_indique_seulement_pre_requis(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ollama" / "models").mkdir(parents=True)
            unit = root / "unit.conf"
            unit.write_text("[Unit]\n", encoding="utf-8")
            with patch.object(doctor.os.path, "ismount", return_value=True), \
                 patch.object(doctor.shutil, "which", return_value="/usr/local/bin/ollama"):
                etat = doctor.verifier(root, unit)
            self.assertTrue(etat["pre_requis_presents"])
            self.assertFalse(etat["inference_hors_ligne_testee"])

    def test_modele_absent_bloquant(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(doctor.os.path, "ismount", return_value=True):
                etat = doctor.verifier(Path(tmp), Path(tmp) / "unit.conf")
            self.assertFalse(etat["dossier_modeles_present"])

    def test_symlink_ne_remplace_pas_volume_donnees(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            link = root / "data"
            link.symlink_to(root, target_is_directory=True)
            with patch.object(doctor.os.path, "ismount", return_value=True):
                etat = doctor.verifier(link, root / "unit.conf")
            self.assertFalse(etat["volume_donnees_monte"])

    def test_diagnostic_json_en_mode_non_strict(self):
        with patch.object(doctor, "verifier", return_value={
                "pre_requis_presents": False, "lecture_seule": True
        }):
            with redirect_stdout(io.StringIO()) as capture:
                code = doctor.main(["--json"])
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(capture.getvalue())["lecture_seule"])

    def test_diagnostic_strict_refuse_pre_requis_absents(self):
        with patch.object(doctor, "verifier", return_value={
                "pre_requis_presents": False, "lecture_seule": True
        }):
            with redirect_stdout(io.StringIO()):
                code = doctor.main(["--json", "--strict"])
        self.assertEqual(code, 1)

    def test_unite_systemd_ne_demarre_pas_si_data_absent(self):
        contenu = UNIT.read_text(encoding="utf-8")
        for attendu in (
            "ConditionPathIsMountPoint=/data",
            "RequiresMountsFor=/data",
            "ExecStartPre=/usr/bin/test -d /data/ollama/models",
            "OLLAMA_MODELS=/data/ollama/models",
            "OLLAMA_HOST=127.0.0.1:11434",
            "OLLAMA_NO_CLOUD=1",
        ):
            self.assertIn(attendu, contenu)
        self.assertNotIn("ExecStart=", contenu)

    def test_configuration_exemple_coherente(self):
        texte = ENV.read_text(encoding="utf-8")
        for ligne in (
            "OLLAMA_HOST=127.0.0.1:11434",
            "OLLAMA_NO_CLOUD=1",
            "OLLAMA_MODELS=/data/ollama/models",
        ):
            self.assertIn(ligne, texte)

    def test_aucune_commande_de_partitionnement_dans_le_script(self):
        texte = SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("subprocess", texte)
        self.assertNotIn("os.system(", texte)
        self.assertNotIn("shutil.rmtree(", texte)


if __name__ == "__main__":
    unittest.main(verbosity=2)
