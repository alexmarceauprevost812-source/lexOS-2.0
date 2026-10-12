#!/usr/bin/env python3
"""Banc sans réseau pour vraies images Kali : SHA-256, noms, SVG, aucune installation."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/includes.chroot/usr/lib/lexos/audit/icones.py"
spec = importlib.util.spec_from_file_location("audit_icones", SOURCE)
icones = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icones)

SVG = b'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M 1 2 L 3 4"/></svg>'


def archive_essai():
    sortie = io.BytesIO()
    with tarfile.open(fileobj=sortie, mode="w:xz") as tar:
        base = "kali-menu-2026.3.4/menu-icons/scalable/apps/"
        for nom, donnees in (
            ("kali-nmap.svg", SVG),
            ("wireshark.svg", SVG),
            ("kali-hashcat.svg", b'<svg xmlns="http://www.w3.org/2000/svg"><script>evil()</script></svg>'),
            ("nmap-other.svg", SVG),
        ):
            membre = tarfile.TarInfo(base + nom)
            membre.size = len(donnees)
            tar.addfile(membre, io.BytesIO(donnees))
        # Un lien symbolique vers un fichier extérieur ne doit jamais être copié.
        lien = tarfile.TarInfo(base + "hydra.svg")
        lien.type = tarfile.SYMTYPE
        lien.linkname = "/etc/passwd"
        tar.addfile(lien)
    return sortie.getvalue()


class AuditImages(unittest.TestCase):
    def test_source_and_checksum_match_published_kali_release(self):
        self.assertEqual(
            icones.KALI_SOURCE_SHA256,
            "0f977fb202b94e0850e45cc4c5a97fa648936f325e6d5857f9839915ae032aa6"
        )
        self.assertEqual(icones.KALI_SOURCE_BYTES, 1534748)
        self.assertIn("archive.kali.org", icones.KALI_SOURCE_URL)
        self.assertEqual(len(icones.CIBLES), 12)

    def test_archive_must_match_sha_before_reading_files(self):
        archive = archive_essai()
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            icones.analyser(archive)

    def test_only_valid_official_svg_names(self):
        archive = archive_essai()
        somme = hashlib.sha256(archive).hexdigest()
        resultat = icones.analyser(archive, somme)
        self.assertEqual(set(resultat), {"nmap", "wireshark"})
        self.assertEqual(resultat["nmap"], SVG)
        self.assertNotIn("hashcat", resultat)
        self.assertNotIn("hydra", resultat)

    def test_no_package_or_script_executed(self):
        archive = archive_essai()
        somme = hashlib.sha256(archive).hexdigest()
        with tempfile.TemporaryDirectory() as temp, \
             patch.object(icones.os, "system") as system:
            resultat = icones.installer(archive, somme, Path(temp)/"images")
            system.assert_not_called()
            self.assertEqual(resultat["presentes"], ["nmap", "wireshark"])
            self.assertEqual(
                (Path(temp)/"images"/"nmap.svg").read_bytes(), SVG
            )
            self.assertEqual(
                icones.icone_locale("nmap", Path(temp)/"images"),
                Path(temp)/"images"/"nmap.svg"
            )
            self.assertIsNone(icones.icone_locale("hydra", Path(temp)/"images"))
            self.assertEqual(len(list((Path(temp)/"images").iterdir())), 2)

    def test_refuse_symlink_directory_before_writing(self):
        archive = archive_essai()
        somme = hashlib.sha256(archive).hexdigest()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base/"vrai").mkdir()
            (base/"alias").symlink_to(base/"vrai", target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symbolique"):
                icones.installer(archive, somme, base/"alias")
            self.assertEqual(list((base/"vrai").iterdir()), [])

    def test_rejects_active_or_remote_svg(self):
        self.assertFalse(icones.svg_valide(
            b'<svg xmlns="http://www.w3.org/2000/svg" onload="evil()"/>'))
        self.assertFalse(icones.svg_valide(
            b'<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.org/x.png"/></svg>'))
        self.assertFalse(icones.svg_valide(
            b'<!DOCTYPE svg><svg xmlns="http://www.w3.org/2000/svg"/>'))
        self.assertTrue(icones.svg_valide(SVG))

    def test_cli_uses_current_user_not_root(self):
        with patch.object(icones.os, "geteuid", return_value=0), \
             patch.object(icones, "telecharger") as telecharger:
            self.assertEqual(icones.main(["installer"]), 1)
            telecharger.assert_not_called()

    def test_icon_fallback_is_explicit(self):
        menu = (ROOT / "config/includes.chroot/usr/lib/lexos/audit/menu.py").read_text()
        self.assertIn("icone_locale(package)", menu)
        self.assertIn("GdkPixbuf.Pixbuf.new_from_file_at_scale", menu)
        self.assertIn("tool_logo(package, files)", menu)
        self.assertIn("theme.has_icon(package)", menu)


if __name__ == "__main__":
    unittest.main()
