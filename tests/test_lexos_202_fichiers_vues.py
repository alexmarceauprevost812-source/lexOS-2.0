#!/usr/bin/env python3
"""Tests sans bureau : changer la vue Thunar passe par XFCONF, jamais thunarrc.

Reproduit le vrai canal thunar de Thunar 4.20 :
/last-view, /last-icon-view-zoom-level, /misc-thumbnail-mode,
/last-image-preview-visible et /misc-image-preview-mode.
"""
import importlib.util
from pathlib import Path
import subprocess
import sys
from unittest import TestCase, main, mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/includes.chroot/usr/lib/lexos/fichiers_vues.py"
spec = importlib.util.spec_from_file_location("lexos_fichiers_vues", SOURCE)
vues = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = vues
spec.loader.exec_module(vues)


class FakeXfconf:
    def __init__(self, valeurs=None, refuser=None):
        self.valeurs = dict(valeurs or {})
        self.refuser = refuser
        self.appels = []

    def __call__(self, argv):
        self.appels.append(list(argv))
        assert argv[0] == "xfconf-query"
        assert argv[1:3] == ["-c", "thunar"]
        assert argv[3] == "-p"
        cle = argv[4]
        if "--set" in argv:
            if cle == self.refuser:
                return subprocess.CompletedProcess(argv, 1, "", "accès refusé")
            value = argv[argv.index("--set") + 1]
            if cle not in self.valeurs and "--create" not in argv:
                return subprocess.CompletedProcess(argv, 1, "", "pas de propriété")
            self.valeurs[cle] = value
            return subprocess.CompletedProcess(argv, 0, "", "")
        if "--reset" in argv:
            self.valeurs.pop(cle, None)
            return subprocess.CompletedProcess(argv, 0, "", "")
        if cle in self.valeurs:
            return subprocess.CompletedProcess(argv, 0, self.valeurs[cle] + "\n", "")
        return subprocess.CompletedProcess(argv, 1, "", "Property does not exist")


class ThunarViews(TestCase):
    def executer(self, fake, fn):
        with (mock.patch.object(vues, "_present", return_value=True),
              mock.patch.object(vues, "_commande", side_effect=fake)):
            return fn()

    def test_grandes_images_and_right_side_preview(self):
        fake = FakeXfconf()
        resultat = self.executer(fake, lambda: vues.choisir("grandes"))
        self.assertTrue(resultat["ok"], resultat)
        self.assertEqual(fake.valeurs["/last-view"], "ThunarIconView")
        self.assertEqual(fake.valeurs["/last-icon-view-zoom-level"],
                         "THUNAR_ZOOM_LEVEL_200_PERCENT")
        self.assertEqual(fake.valeurs["/misc-thumbnail-mode"],
                         "THUNAR_THUMBNAIL_MODE_ONLY_LOCAL")
        self.assertEqual(fake.valeurs["/misc-image-preview-mode"],
                         "THUNAR_IMAGE_PREVIEW_MODE_STANDALONE")
        self.assertEqual(fake.valeurs["/last-image-preview-visible"], "true")
        self.assertEqual(
            self.executer(fake, vues.etat),
            {"disponible": True, "vue": "grandes", "grandes": True,
             "apercu": True, "miniatures": True})

    def test_all_four_view_modes(self):
        fake = FakeXfconf()
        for mode, expected in (
            ("liste", "ThunarDetailsView"),
            ("compact", "ThunarCompactView"),
            ("icones", "ThunarIconView"),
            ("grandes", "ThunarIconView"),
        ):
            with self.subTest(mode=mode):
                self.assertTrue(self.executer(
                    fake, lambda: vues.choisir(mode))["ok"])
                self.assertEqual(fake.valeurs["/last-view"], expected)
        self.assertTrue(self.executer(
            fake, lambda: vues.choisir("apercu-off"))["ok"])
        self.assertEqual(fake.valeurs["/last-image-preview-visible"], "false")
        self.assertTrue(self.executer(
            fake, lambda: vues.choisir("miniatures-off"))["ok"])
        self.assertEqual(fake.valeurs["/misc-thumbnail-mode"],
                         "THUNAR_THUMBNAIL_MODE_NEVER")
        self.assertTrue(self.executer(
            fake, lambda: vues.choisir("miniatures-on"))["ok"])
        self.assertEqual(fake.valeurs["/misc-thumbnail-mode"],
                         "THUNAR_THUMBNAIL_MODE_ONLY_LOCAL")

    def test_refuses_unknown_or_shell_inputs(self):
        fake = FakeXfconf()
        with mock.patch.object(vues, "_commande", side_effect=fake):
            for bad in ("../../etc/passwd", "; rm -rf", "preview",
                        "2000", "", None, ["grandes"]):
                with self.subTest(bad=bad):
                    self.assertFalse(vues.choisir(bad)["ok"])
        self.assertEqual(fake.appels, [])

    def test_no_tools_provides_explicit_failure(self):
        with mock.patch.object(vues, "_present", return_value=False):
            self.assertFalse(vues.choisir("grandes")["ok"])
            self.assertIsNone(vues.etat()["vue"])

    def test_partial_failure_rolls_back_existing_and_new(self):
        fake = FakeXfconf(
            {"/last-view": "ThunarDetailsView",
             "/last-icon-view-zoom-level": "THUNAR_ZOOM_LEVEL_100_PERCENT"},
            refuser="/misc-image-preview-mode")
        old = dict(fake.valeurs)
        resultat = self.executer(fake, lambda: vues.choisir("grandes"))
        self.assertFalse(resultat["ok"])
        self.assertEqual(fake.valeurs, old)
        self.assertTrue(any("--reset" in a for a in fake.appels),
                        "La nouvelle clé miniatures doit être restaurée à absente.")

    def test_same_property_is_not_rewritten(self):
        fake = FakeXfconf({"/last-view": "ThunarDetailsView"})
        self.assertTrue(self.executer(fake, lambda: vues.choisir("liste"))["ok"])
        self.assertEqual([a for a in fake.appels if "--set" in a], [])

    def test_backend_and_web_ui_reuse_one_source_of_truth(self):
        backend = (ROOT / "config/includes.chroot/usr/lib/lexos/settings.py").read_text()
        frontend = (ROOT / "config/includes.chroot/usr/share/lexos/settings/web/app.js").read_text()
        dispatcher = (ROOT / "config/includes.chroot/usr/bin/lexos").read_text()
        self.assertIn('"fichiers-vue": act_fichiers_vue', backend)
        self.assertIn('"fichiers_vue": _fichiers_vues.etat', backend)
        self.assertIn('fichiers:    ["fichiers_vue"]', frontend)
        self.assertIn('"fichiers-vue"', frontend)
        self.assertIn('case "fichiers":', frontend)
        for mode in vues.MODES:
            self.assertIn(mode, frontend)
        self.assertIn("vue-fichiers|vues-fichiers|images-vue)", dispatcher)
        self.assertIn("fichiers_vues.py", dispatcher)
        # Le réglage du sélecteur navigateur n'est volontairement PAS prétendu
        # modifiable par XFCONF Thunar.
        self.assertIn("sélecteur", frontend.lower())


if __name__ == "__main__":
    main()
