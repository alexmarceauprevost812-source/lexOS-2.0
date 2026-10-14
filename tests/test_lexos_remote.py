#!/usr/bin/env python3
"""Tests isolement LexOS Remote : aucun serveur, aucune interface reseau."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
DISTANT = ROOT / "config/includes.chroot/usr/bin/lexos-distant"
MENU = ROOT / "config/includes.chroot/usr/bin/lexos-remote-menu"
APP = ROOT / "config/includes.chroot/usr/share/applications/lexos-remote.desktop"
BUREAU = ROOT / "config/includes.chroot/etc/skel/Bureau/LexOS-Remote.desktop"
DESKTOP = ROOT / "config/includes.chroot/etc/skel/Desktop/LexOS-Remote.desktop"
PAQUETS = ROOT / "flavours/standard/desktop.list.chroot"


def creer_executable(dossier, nom, texte):
    fichier = Path(dossier) / nom
    fichier.write_text("#!/bin/sh\n" + texte + "\n", encoding="utf-8")
    fichier.chmod(0o755)
    return fichier


class LexosRemote(unittest.TestCase):
    def prepare(self, racine, ip=None, partage_actif=False):
        racine = Path(racine)
        binaires = racine / "bin"
        binaires.mkdir()
        creer_executable(binaires, "x11vnc",
                         'echo "NE_DOIT_PAS_DEMARRER" >> "$START_LOG"')
        creer_executable(binaires, "pgrep",
                         "echo 4321; exit 0" if partage_actif else "exit 1")
        creer_executable(binaires, "pkill", "exit 0")
        if ip is not None:
            creer_executable(binaires, "tailscale",
                             'if [ "$1" = ip ]; then printf "%s\\n" "$TEST_IP"; '
                             'else exit 0; fi')
        creer_executable(binaires, "qrencode",
                         'printf "%s\\n" "$*" >> "$QR_LOG"; echo "QR_SIMULE"')
        return {
            **os.environ,
            "PATH": str(binaires) + os.pathsep + os.environ["PATH"],
            "DISPLAY": ":99",
            "XDG_SESSION_TYPE": "x11",
            "HOME": str(racine),
            "XDG_CONFIG_HOME": str(racine / "config"),
            "TEST_IP": ip or "",
            "START_LOG": str(racine / "demarrages.log"),
            "QR_LOG": str(racine / "qr.log"),
            "NO_COLOR": "1",
        }

    def appel(self, *arguments, env):
        return subprocess.run(
            ["bash", str(DISTANT), *arguments],
            env=env, capture_output=True, text=True, timeout=10,
        )

    def test_aide_expose_qr(self):
        sortie = self.appel("--help", env=os.environ.copy())
        self.assertEqual(sortie.returncode, 0, sortie.stderr)
        self.assertIn("qr", sortie.stdout.lower())

    def test_refuse_partage_sans_tailscale(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.prepare(tmp)
            r = self.appel("partager", env=env)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("Tailscale", r.stderr)
            self.assertFalse((Path(tmp) / "demarrages.log").exists())

    def test_refuse_partage_sur_ip_lan(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.prepare(tmp, ip="192.168.1.25")
            r = self.appel("partager", env=env)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("Tailscale", r.stderr)
            self.assertFalse((Path(tmp) / "demarrages.log").exists())

    def test_refuse_qr_sans_partage(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.prepare(tmp, ip="100.111.12.13")
            r = self.appel("qr", env=env)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse((Path(tmp) / "qr.log").exists())

    def test_qr_ne_contient_que_adresse_privee(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.prepare(tmp, ip="100.111.12.13", partage_actif=True)
            r = self.appel("qr", env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            contenu = (Path(tmp) / "qr.log").read_text(encoding="utf-8")
            self.assertIn("vnc://100.111.12.13:5900", contenu)
            self.assertNotIn("password", contenu.lower())
            self.assertNotIn("token", contenu.lower())

    def test_qr_refuse_ip_non_tailscale(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.prepare(tmp, ip="10.0.0.1", partage_actif=True)
            r = self.appel("qr", env=env)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse((Path(tmp) / "qr.log").exists())

    def test_securite_du_serveur(self):
        texte = DISTANT.read_text(encoding="utf-8")
        self.assertIn('-listen "$ip"', texte)
        self.assertIn("tailscale_ipv4()", texte)
        self.assertIn("ipaddress.IPv4Network", texte)
        self.assertIn("demander_mot_de_passe", texte)
        self.assertNotIn("tailscale funnel", texte.lower())

    def test_raccourcis_installation_iso(self):
        for p in (MENU, APP, BUREAU, DESKTOP):
            self.assertTrue(p.is_file(), str(p))
        for p in (APP, BUREAU, DESKTOP):
            contenu = p.read_text(encoding="utf-8")
            self.assertIn("Exec=lexos-remote-menu", contenu)
            self.assertIn("Terminal=false", contenu)
        self.assertIn("x11vnc", PAQUETS.read_text(encoding="utf-8").splitlines())


if __name__ == "__main__":
    unittest.main(verbosity=2)
