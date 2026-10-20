#!/usr/bin/env python3
"""Banc de LexOS Pilotes — l'appli des mises à jour de la carte graphique.

Ce qu'on éprouve, sans apt ni carte graphique réelle :
  · le filtre : seuls les paquets graphiques passent ;
  · la lecture d'« apt-cache policy », y compris le dépôt NVIDIA « plat » ;
  · le plan : un paquet installé depuis backports est redemandé à backports
    (sinon apt le laisserait figé), l'épingle NVIDIA n'est jamais contournée ;
  · la détection des cartes par lspci ;
  · le serveur refuse les appels qui ne viennent pas de la boucle locale ;
  · l'aide root refuse de tourner sans root et sans action connue.
"""
import http.client
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

R = Path(__file__).resolve().parents[1]
DOSSIER = R / "config/includes.chroot/usr/lib/lexos/pilotes"
sys.path.insert(0, str(DOSSIER))

import paquets  # noqa: E402
import moteur  # noqa: E402
import serveur  # noqa: E402

POLITIQUE = """\
libgl1-mesa-dri:
  Installed: 25.0.7-2~bpo13+1
  Candidate: 25.0.7-2
  Version table:
     25.2.4-1~bpo13+1 100
        100 http://deb.debian.org/debian trixie-backports/main amd64 Packages
 *** 25.0.7-2~bpo13+1 100
        100 http://deb.debian.org/debian trixie-backports/main amd64 Packages
        100 /var/lib/dpkg/status
     25.0.7-2 500
        500 http://deb.debian.org/debian trixie/main amd64 Packages
nvidia-driver-cuda:
  Installed: 595.71.05-1
  Candidate: 595.91.07-1
  Version table:
     610.57.04-1 500
        500 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
     595.91.07-1 1001
       1001 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
 *** 595.71.05-1 1001
       1001 https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64  Packages
        100 /var/lib/dpkg/status
firmware-misc-nonfree:
  Installed: 20250410-2
  Candidate: 20250410-2
  Version table:
 *** 20250410-2 500
        500 http://deb.debian.org/debian trixie/non-free-firmware amd64 Packages
        100 /var/lib/dpkg/status
"""

LSPCI = """\
00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 520 [8086:1916] (rev 07)
\tSubsystem: Lenovo ThinkPad T460 [17aa:2233]
\tKernel driver in use: i915
\tKernel modules: i915
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GB206 [GeForce RTX 5060] [10de:2d05] (rev a1)
\tKernel driver in use: nvidia
02:00.0 Ethernet controller [0200]: Realtek RTL8111 [10ec:8168]
\tKernel driver in use: r8169
"""


class Filtre(unittest.TestCase):
    def test_ne_garde_que_le_graphique(self):
        dpkg = "\n".join([
            "ii nvidia-driver-cuda", "ii libnvidia-ml1:amd64", "ii libgl1-mesa-dri:i386",
            "ii firmware-amd-graphics", "ii mesa-vulkan-drivers", "ii xserver-xorg-video-nvidia",
            "ii firefox-esr", "ii sudo", "ii linux-image-amd64", "ii openssh-server",
            "rc nvidia-old-thing",
        ])
        noms = paquets.paquets_graphiques_installes(dpkg)
        self.assertIn("nvidia-driver-cuda", noms)
        self.assertIn("libgl1-mesa-dri:i386", noms)
        self.assertIn("firmware-amd-graphics", noms)
        for interdit in ("firefox-esr", "sudo", "linux-image-amd64", "openssh-server", "nvidia-old-thing"):
            self.assertNotIn(interdit, noms)


class Plan(unittest.TestCase):
    def setUp(self):
        self.pol = paquets.lire_politique(POLITIQUE)

    def test_lecture(self):
        mesa = self.pol["libgl1-mesa-dri"]
        self.assertEqual(mesa["installe"], "25.0.7-2~bpo13+1")
        self.assertEqual(mesa["candidat"], "25.0.7-2")
        self.assertEqual(len(mesa["versions"]), 3)
        nv = self.pol["nvidia-driver-cuda"]
        self.assertIn("developer.download.nvidia.com", nv["versions"][0][1])

    def test_backports_reste_sur_backports(self):
        plan = {p["paquet"]: p for p in paquets.planifier(self.pol)}
        mesa = plan["libgl1-mesa-dri"]
        self.assertEqual(mesa["cible"], "25.2.4-1~bpo13+1")
        self.assertEqual(mesa["demande"], "libgl1-mesa-dri/trixie-backports")

    def test_epingle_nvidia_respectee(self):
        plan = {p["paquet"]: p for p in paquets.planifier(self.pol)}
        nv = plan["nvidia-driver-cuda"]
        #  La 610 existe, mais le candidat d'apt (épingle 1001) est la 595.91.
        self.assertEqual(nv["cible"], "595.91.07-1")
        self.assertEqual(nv["demande"], "nvidia-driver-cuda")

    def test_rien_si_a_jour(self):
        plan = {p["paquet"] for p in paquets.planifier(self.pol)}
        self.assertNotIn("firmware-misc-nonfree", plan)

    def test_branche(self):
        epingle = "Package: nvidia-* libnvidia-*\nPin: version 595.*\nPin-Priority: 1001\n"
        self.assertEqual(paquets.branche_epinglee(epingle), "595")
        self.assertIsNone(paquets.branche_epinglee("rien"))
        self.assertEqual(paquets.branche_plus_recente(self.pol["nvidia-driver-cuda"]), "610.57.04-1")


class Cartes(unittest.TestCase):
    def test_lspci(self):
        cartes = moteur.lire_cartes(LSPCI)
        self.assertEqual(len(cartes), 2)
        self.assertEqual(cartes[0]["marque"], "Intel")
        self.assertEqual(cartes[0]["pilote"], "i915")
        self.assertEqual(cartes[1]["marque"], "NVIDIA")
        self.assertEqual(cartes[1]["nom"], "NVIDIA Corporation GB206 [GeForce RTX 5060]")
        self.assertEqual(cartes[1]["pilote"], "nvidia")


class Serveur(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), serveur.Gestionnaire)
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def req(self, methode, chemin, entetes=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request(methode, chemin, headers=entetes or {})
        r = c.getresponse()
        r.read()
        return r.status

    def test_page(self):
        self.assertEqual(self.req("GET", "/"), 200)
        self.assertEqual(self.req("GET", "/app.js"), 200)

    def test_hote_etranger(self):
        self.assertEqual(self.req("GET", "/api/tache", {"Host": "evil.example"}), 403)

    def test_post_sans_entete(self):
        self.assertEqual(self.req("POST", "/api/installer"), 403)

    def test_post_autre_origine(self):
        self.assertEqual(self.req("POST", "/api/installer",
                                  {"X-LexOS": "1", "Origin": "https://evil.example"}), 403)

    def test_traversee(self):
        self.assertIn(self.req("GET", "/../serveur.py"), (403, 404))


class AideRoot(unittest.TestCase):
    def test_refuse_sans_root(self):
        if os.geteuid() == 0:
            self.skipTest("le banc tourne en root")
        r = subprocess.run([sys.executable, str(DOSSIER / "maj.py"), "installer"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("LEXOS-RESULTAT", r.stdout)

    def test_module_absent_detecte(self):
        import maj  # noqa: E402
        with tempfile.TemporaryDirectory() as d:
            racine = Path(d)
            (racine / "6.12.48+deb13-amd64/updates/dkms").mkdir(parents=True)
            (racine / "6.12.48+deb13-amd64/updates/dkms/nvidia.ko.xz").write_text("")
            (racine / "6.16.12+bpo-amd64").mkdir()
            ancien = maj.RACINE_MODULES
            maj.RACINE_MODULES = racine
            try:
                self.assertEqual(maj.noyau_le_plus_recent(), "6.16.12+bpo-amd64")
                self.assertFalse(maj.module_nvidia_present("6.16.12+bpo-amd64"))
                self.assertTrue(maj.module_nvidia_present("6.12.48+deb13-amd64"))
            finally:
                maj.RACINE_MODULES = ancien


class SignatureMOK(unittest.TestCase):
    """Le guide d'inscription du certificat LexOS : quelle étape montrer.

    modinfo et mokutil sont remplacés : on décrit une machine, on lit l'étape.
    """

    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        d = Path(self.dossier.name)
        (d / "build.conf").write_text('LEXOS_SIGNATURE_CLE_ID="43:CF:A1:4C"\n', encoding="utf-8")
        (d / "lexos-mok.der").write_bytes(b"\x30\x82")
        (d / "cmdline").write_text("boot=live components\n", encoding="utf-8")
        (d / "modules").write_text("snd 1 - Live 0x0\n", encoding="utf-8")
        self.anciens = (moteur.BUILD_CONF, moteur.CERT_LEXOS, moteur.CMDLINE, moteur.PROC_MODULES,
                        moteur._executer, moteur._cle_inscrite)
        moteur.BUILD_CONF, moteur.CERT_LEXOS = d / "build.conf", d / "lexos-mok.der"
        moteur.CMDLINE, moteur.PROC_MODULES = d / "cmdline", d / "modules"
        self.cle_module = "43:cf:a1:4c"
        self.inscrite = False
        moteur._executer = lambda cmd, timeout=10.0: self.cle_module + "\n" if "sig_key" in cmd else None
        moteur._cle_inscrite = lambda cert: self.inscrite

    def tearDown(self):
        (moteur.BUILD_CONF, moteur.CERT_LEXOS, moteur.CMDLINE, moteur.PROC_MODULES,
         moteur._executer, moteur._cle_inscrite) = self.anciens
        self.dossier.cleanup()

    def test_signe_lexos_pas_inscrit(self):
        s = moteur.signature_pilote(True)
        self.assertEqual(s["etape"], "inscrire-lexos")
        self.assertTrue(s["signe_par_lexos"])
        self.assertTrue(s["en_live"])

    def test_inscrit_mais_pas_charge(self):
        self.inscrite = True
        self.assertEqual(moteur.signature_pilote(True)["etape"], "redemarrer")

    def test_charge(self):
        moteur.PROC_MODULES.write_text("nvidia 1 - Live 0x0\n", encoding="utf-8")
        self.assertEqual(moteur.signature_pilote(True)["etape"], "ok")

    def test_secure_boot_inactif(self):
        self.assertEqual(moteur.signature_pilote(False)["etape"], "sans-secure-boot")

    def test_autre_cle(self):
        self.cle_module = "DE:AD:BE:EF"
        s = moteur.signature_pilote(True)
        self.assertEqual(s["etape"], "cle-machine")
        self.assertFalse(s["signe_par_lexos"])

    def test_assistant_ligne_fixe(self):
        # La page ne fournit rien : la commande lancée est figée dans le serveur.
        self.assertEqual(serveur.ASSISTANT_SIGNATURE[0], "x-terminal-emulator")
        self.assertIn("sudo lexos-signer-pilote", serveur.ASSISTANT_SIGNATURE[-1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
