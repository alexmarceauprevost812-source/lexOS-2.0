"""Mon téléphone — la logique, avec de faux kdeconnect-cli, adb, scrcpy et
lexos-share. Chaque faux outil note ce qu'on lui a demandé dans un journal :
on vérifie ce qui est RÉELLEMENT envoyé, pas seulement le message affiché.
"""
import os
import stat
import tempfile
import time
import unittest
from pathlib import Path

from pro.services import telephone as svc


def faux(dossier: Path, nom: str, corps: str) -> str:
    p = dossier / nom
    p.write_text("#!/bin/sh\necho \"$0 $*\" >> \"$JOURNAL\"\n" + corps + "\n", encoding="utf-8")
    p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return str(p)


class Banc(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.journal = self.tmp / "journal"
        os.environ["JOURNAL"] = str(self.journal)
        self.anciens = (svc.KDE, svc.ADB, svc.SCRCPY, svc.PARTAGE)
        svc.PARTAGE = faux(self.tmp, "lexos-share", "exit 0")
        svc.SCRCPY = faux(self.tmp, "scrcpy", "exit 0")
        self.fichier = self.tmp / "photo.jpg"
        self.fichier.write_bytes(b"jpg")

    def tearDown(self):
        svc.KDE, svc.ADB, svc.SCRCPY, svc.PARTAGE = self.anciens

    def kde(self, liste: str, partage_rc: int = 0):
        svc.KDE = faux(self.tmp, "kdeconnect-cli", f"""
case "$*" in
  *--list-available*) printf '{liste}' ;;
  *--share*) exit {partage_rc} ;;
esac
exit 0""")

    def adb(self, devices: str, connect: str = "connected to 192.168.1.42:5555"):
        svc.ADB = faux(self.tmp, "adb", f"""
case "$1" in
  devices) printf 'List of devices attached\\n{devices}' ;;
  connect) echo "{connect}" ;;
esac
exit 0""")

    def lu(self) -> str:
        time.sleep(0.3)  # les lancements détachés écrivent un peu plus tard
        return self.journal.read_text(encoding="utf-8") if self.journal.exists() else ""


class TestEtat(Banc):
    def test_appareils_lus(self):
        self.kde("abc123 Pixel de Alex\\n")
        self.adb("R5CT1 device\\nZZ9 unauthorized\\n")
        e = svc.etat()
        self.assertEqual(e["kde"], [("abc123", "Pixel de Alex")])
        self.assertEqual(e["adb_prets"], ["R5CT1"])
        self.assertIn(("ZZ9", "unauthorized"), e["adb"])

    def test_outils_absents_sans_exception(self):
        svc.KDE = str(self.tmp / "absent-kde")
        svc.ADB = str(self.tmp / "absent-adb")
        e = svc.etat()
        self.assertFalse(e["kde_installe"])
        self.assertEqual(e["kde"], [])
        self.assertEqual(e["adb"], [])


class TestEnvoyer(Banc):
    def test_kde_direct_si_un_telephone(self):
        self.kde("abc123 Pixel\\n")
        r = svc.envoyer([str(self.fichier)])
        self.assertTrue(r.ok, r.erreur)
        self.assertIn(f"--device abc123 --share {self.fichier}", self.lu())
        self.assertNotIn("lexos-share", self.lu())

    def test_qr_sans_telephone_jumele(self):
        self.kde("")
        r = svc.envoyer([str(self.fichier)])
        self.assertTrue(r.ok, r.erreur)
        self.assertIn(f"lexos-share qr {self.fichier}", self.lu())

    def test_echec_kde_dit_quel_fichier(self):
        self.kde("abc123 Pixel\\n", partage_rc=1)
        r = svc.envoyer([str(self.fichier)])
        self.assertFalse(r.ok)
        self.assertIn("photo.jpg", r.erreur)

    def test_rien_a_envoyer(self):
        self.assertFalse(svc.envoyer([str(self.tmp / "absent.txt")]).ok)


class TestEcran(Banc):
    def test_scrcpy_lance_si_android_pret(self):
        self.adb("R5CT1 device\\n")
        r = svc.afficher_ecran()
        self.assertTrue(r.ok, r.erreur)
        self.assertIn("scrcpy --window-title", self.lu())

    def test_autorisation_demandee(self):
        self.adb("R5CT1 unauthorized\\n")
        r = svc.afficher_ecran()
        self.assertFalse(r.ok)
        self.assertIn("Autoriser le débogage USB", r.erreur)

    def test_aucun_telephone(self):
        self.adb("")
        r = svc.afficher_ecran()
        self.assertFalse(r.ok)
        self.assertNotIn("scrcpy", self.lu())


class TestWifi(Banc):
    def test_adresse_validee(self):
        self.assertEqual(svc.adresse_valide("192.168.1.42"), "192.168.1.42:5555")
        self.assertEqual(svc.adresse_valide(" 10.0.0.7:41234 "), "10.0.0.7:41234")
        for mauvaise in ("", "300.1.1.1", "abc", "1.2.3.4; rm -rf /", "1.2.3.4:99999"):
            self.assertEqual(svc.adresse_valide(mauvaise), "", mauvaise)

    def test_connexion_reussie(self):
        self.adb("")
        r = svc.connecter_wifi("192.168.1.42")
        self.assertTrue(r.ok, r.erreur)
        self.assertIn("adb connect 192.168.1.42:5555", self.lu())

    def test_adb_rend_0_mais_echoue(self):
        self.adb("", connect="failed to connect to 192.168.1.42:5555")
        self.assertFalse(svc.connecter_wifi("192.168.1.42").ok)

    def test_adresse_invalide_n_atteint_pas_adb(self):
        self.adb("")
        self.assertFalse(svc.connecter_wifi("1.2.3.4; reboot").ok)
        self.assertNotIn("connect", self.lu())


class TestAutres(Banc):
    def test_recevoir_ouvre_la_boite(self):
        self.assertTrue(svc.recevoir().ok)
        self.assertIn("lexos-share receive", self.lu())

    def test_sonner(self):
        self.kde("abc123 Pixel\\n")
        self.assertTrue(svc.sonner().ok)
        self.assertIn("--device abc123 --ring", self.lu())

    def test_sonner_sans_telephone(self):
        self.kde("")
        self.assertFalse(svc.sonner().ok)


if __name__ == "__main__":
    unittest.main()
