#!/usr/bin/env python3
"""Tests isolés du diagnostic LexOS USB AI : aucun périphérique réel requis."""

import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import unittest
from contextlib import redirect_stdout, redirect_stderr
from unittest.mock import patch

RACINE = pathlib.Path(__file__).resolve().parent.parent
MODULE = RACINE / "tools" / "lexos-usb-ai-inventaire.py"
spec = importlib.util.spec_from_file_location("lexos_usb_ai_inventaire", MODULE)
inventaire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventaire)

DONNEES = {
    "blockdevices": [
        {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk", "size": 512000000000,
         "tran": "nvme", "model": "System disk", "mountpoints": [None],
         "children": [{"type": "part", "mountpoints": ["/", "/boot/efi"]}]},
        {"name": "sdb", "path": "/dev/sdb", "type": "disk", "size": 1000204886016,
         "tran": "usb", "model": "External SSD", "mountpoints": [None],
         "children": [{"type": "part", "mountpoints": ["/media/LEXOS"]}]},
        {"name": "sdc", "path": "/dev/sdc", "type": "disk", "size": 1000204886016,
         "tran": "usb", "model": "Empty USB SSD", "mountpoints": [None]},
    ]
}


class InventaireTests(unittest.TestCase):
    def test_protege_le_disque_systeme(self):
        disques = inventaire.analyser(DONNEES)
        self.assertIn("NE PAS TOUCHER", disques[0]["statut"])
        self.assertIn("/", disques[0]["montages"])

    def test_protege_un_support_usb_monte(self):
        disques = inventaire.analyser(DONNEES)
        self.assertIn("NE PAS MODIFIER", disques[1]["statut"])
        self.assertIn("/media/LEXOS", disques[1]["montages"])

    def test_usb_non_monte_reste_a_confirmer(self):
        disques = inventaire.analyser(DONNEES)
        self.assertIn("À CONFIRMER", disques[2]["statut"])
        self.assertNotIn("PRÊT À EFFACER", disques[2]["statut"])

    def test_modeles_non_fiables_sans_echappements_terminal(self):
        donnees = {"blockdevices": [{"type": "disk", "name": "sda",
                                      "model": "SSD\x1b[31mMalicieux", "tran": "usb"}]}
        self.assertNotIn("\x1b", inventaire.analyser(donnees)[0]["modele"])

    def test_pas_de_disque(self):
        self.assertEqual(inventaire.analyser({"blockdevices": []}), [])

    def test_structure_malformee_refusee(self):
        with self.assertRaises(ValueError):
            inventaire.analyser({"unknown": []})

    def test_lsblk_uniquement_sans_sudo(self):
        resultat = subprocess.CompletedProcess(inventaire.LSBLK_CMD, 0, json.dumps(DONNEES), "")
        with patch.object(inventaire.subprocess, "run", return_value=resultat) as appel:
            with patch.object(sys, "argv", ["inventaire"]), redirect_stdout(io.StringIO()) as sortie:
                self.assertEqual(inventaire.main(), 0)
            self.assertIn("LECTURE SEULE", sortie.getvalue())
            appel.assert_called_once_with(inventaire.LSBLK_CMD, capture_output=True, text=True, check=True)
            self.assertEqual(appel.call_args.args[0][0], "lsblk")

    def test_sortie_json(self):
        resultat = subprocess.CompletedProcess(inventaire.LSBLK_CMD, 0, json.dumps(DONNEES), "")
        with patch.object(inventaire.subprocess, "run", return_value=resultat):
            with patch.object(sys, "argv", ["inventaire", "--json"]), redirect_stdout(io.StringIO()) as sortie:
                self.assertEqual(inventaire.main(), 0)
            self.assertTrue(json.loads(sortie.getvalue())["lecture_seule"])

    def test_lsblk_indisponible(self):
        with patch.object(inventaire.subprocess, "run", side_effect=FileNotFoundError("lsblk")):
            with patch.object(sys, "argv", ["inventaire"]), redirect_stderr(io.StringIO()) as erreurs:
                self.assertEqual(inventaire.main(), 2)
            self.assertIn("Échec", erreurs.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
