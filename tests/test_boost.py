"""Tests de LexOS Boost.

On ne teste pas « est-ce que la machine va plus vite » — ça se mesure
sur du vrai matériel. On teste les deux propriétés qui doivent tenir
partout, sur n'importe quelle machine :

  1. le profil calculé est cohérent avec le matériel décrit,
  2. toute action qui réussit fournit de quoi revenir en arrière.

La deuxième est la plus importante. Si une action s'applique sans
produire ses données de restauration, l'utilisateur se retrouve avec une
machine modifiée qu'il ne peut plus remettre d'aplomb — c'est exactement
ce que LexOS Boost promet de ne jamais faire.

Usage :  python3 -m pytest tests/test_boost.py -v
    ou :  python3 tests/test_boost.py
"""

import os
import sys
import tempfile
import unittest

RACINE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "config", "includes.chroot", "usr", "lib", "lexos",
)
sys.path.insert(0, RACINE)

from boost import actions, journal, profil  # noqa: E402
from boost.materiel import Machine  # noqa: E402


# --------------------------------------------------------------------------
# machines de référence
# --------------------------------------------------------------------------

def portable_2009() -> Machine:
    """Le cas d'usage central : un vieux portable qu'on veut ressusciter."""
    return Machine(
        ram_mo=2048, ram_disponible_mo=400, swap_mo=1024,
        cpu_modele="Intel(R) Core(TM)2 Duo CPU T6400", cpu_coeurs=2,
        cpu_annee_estimee=2007,
        gouverneurs_disponibles=["ondemand", "conservative", "performance"],
        gouverneur_actif="ondemand",
        disque="sda", disque_type="hdd", disque_taille_go=160.0, disque_libre_go=12.0,
        ordonnanceur_actif="mq-deadline", ordonnanceurs_disponibles=["mq-deadline", "bfq", "none"],
        portable=True, session_graphique=True, bureau="XFCE", compositeur_actif=True,
        a_bluetooth=False, a_imprimante_usb=False, systemd=True,
    )


def bureau_2014() -> Machine:
    return Machine(
        ram_mo=8192, ram_disponible_mo=5000, swap_mo=2048,
        cpu_modele="Intel(R) Core(TM) i5-4590", cpu_coeurs=4, cpu_annee_estimee=2014,
        gouverneurs_disponibles=["powersave", "performance"], gouverneur_actif="powersave",
        disque="sda", disque_type="ssd", disque_taille_go=240.0, disque_libre_go=90.0,
        ordonnanceur_actif="mq-deadline", ordonnanceurs_disponibles=["mq-deadline", "none"],
        portable=False, session_graphique=True, bureau="XFCE", compositeur_actif=True,
        a_bluetooth=True, a_imprimante_usb=False, systemd=True,
    )


def station_2023() -> Machine:
    return Machine(
        ram_mo=32768, ram_disponible_mo=28000, swap_mo=8192,
        cpu_modele="AMD Ryzen 7 7700X", cpu_coeurs=16, cpu_annee_estimee=2022,
        gouverneurs_disponibles=["schedutil", "performance"], gouverneur_actif="schedutil",
        disque="nvme0n1", disque_type="nvme", disque_taille_go=2000.0, disque_libre_go=1200.0,
        ordonnanceur_actif="none", ordonnanceurs_disponibles=["none", "mq-deadline"],
        portable=False, session_graphique=True, bureau="XFCE", compositeur_actif=True,
        a_bluetooth=True, a_imprimante_usb=True, systemd=True,
    )


# --------------------------------------------------------------------------
# le profil s'adapte-t-il vraiment à la machine ?
# --------------------------------------------------------------------------

class TestProfil(unittest.TestCase):

    def test_classement_ordonne(self):
        """Une machine plus récente ne doit jamais être classée plus bas."""
        rang = ["tres_ancienne", "ancienne", "modeste", "correcte", "recente"]
        classes = [profil.classer(m()) for m in (portable_2009, bureau_2014, station_2023)]
        indices = [rang.index(c) for c in classes]
        self.assertEqual(indices, sorted(indices), f"classement incohérent : {classes}")

    def test_zram_inversement_proportionnel_a_la_ram(self):
        """Moins il y a de RAM, plus la zone compressée est grande, en proportion."""
        faible = profil.calculer(portable_2009(), "max").reglages
        moyen = profil.calculer(bureau_2014(), "max").reglages
        self.assertEqual(faible["zram_taille_mo"], 3072)     # 2 Go × 1.5
        self.assertEqual(moyen["zram_taille_mo"], 4096)      # 8 Go × 0.5, au plafond
        self.assertLess(
            moyen["zram_taille_mo"] / 8192,
            faible["zram_taille_mo"] / 2048,
            "la proportion de zram devrait décroître avec la RAM disponible",
        )

    def test_pas_de_saut_brutal_autour_des_seuils(self):
        """Deux machines quasi identiques doivent recevoir des réglages proches.

        Sans plafond, 8191 Mo de RAM aurait donné deux fois plus de zram
        que 8193 Mo — une falaise absurde de part et d'autre d'un seuil.
        """
        for bas, haut in ((2047, 2049), (4095, 4097), (8191, 8193)):
            machine_basse, machine_haute = bureau_2014(), bureau_2014()
            machine_basse.ram_mo, machine_haute.ram_mo = bas, haut
            taille_basse = profil.calculer(machine_basse, "max").reglages.get("zram_taille_mo", 0)
            taille_haute = profil.calculer(machine_haute, "max").reglages.get("zram_taille_mo", 0)
            with self.subTest(seuil=(bas, haut)):
                ecart = abs(taille_basse - taille_haute)
                self.assertLessEqual(
                    ecart, max(taille_basse, taille_haute) * 0.5,
                    f"saut de {ecart} Mo entre {bas} et {haut} Mo de RAM",
                )

    def test_pas_de_zram_sur_grosse_machine(self):
        reglages = profil.calculer(station_2023(), "max").reglages
        self.assertNotIn("zram_taille_mo", reglages)

    def test_algorithme_choisi_selon_le_processeur(self):
        """lz4 sur un processeur faible, zstd quand il y a de la marge."""
        self.assertEqual(profil.calculer(portable_2009(), "max").reglages["zram_algo"], "lz4")
        self.assertEqual(profil.calculer(bureau_2014(), "max").reglages["zram_algo"], "zstd")

    def test_portable_jamais_bloque_en_performance(self):
        """Sur batterie, on ne verrouille pas le processeur au maximum."""
        reglages = profil.calculer(portable_2009(), "max").reglages
        self.assertNotEqual(reglages.get("gouverneur"), "performance")

    def test_bureau_en_performance_au_niveau_max(self):
        machine = bureau_2014()
        machine.gouverneurs_disponibles = ["powersave", "ondemand", "performance"]
        self.assertEqual(profil.calculer(machine, "max").reglages["gouverneur"], "performance")

    def test_swappiness_suit_la_presence_de_zram(self):
        """Avec zram, décharger est bon marché ; sans, sur disque dur, c'est cher."""
        avec = profil.calculer(portable_2009(), "max").reglages["sysctl"]["vm.swappiness"]
        self.assertGreater(avec, 100)

        sans = station_2023()
        self.assertLess(
            profil.calculer(sans, "max").reglages["sysctl"]["vm.swappiness"], 100
        )

    def test_ordonnanceur_selon_le_type_de_disque(self):
        self.assertEqual(profil.calculer(portable_2009(), "max").reglages["ordonnanceur"], "bfq")
        self.assertEqual(profil.calculer(station_2023(), "max").reglages["ordonnanceur"], "none")

    def test_readahead_seulement_sur_disque_lent(self):
        self.assertIn("readahead_kio", profil.calculer(portable_2009(), "max").reglages)
        self.assertNotIn("readahead_kio", profil.calculer(station_2023(), "max").reglages)

    def test_effets_coupes_seulement_si_utile(self):
        self.assertTrue(profil.calculer(portable_2009(), "max").reglages["couper_effets"])
        self.assertFalse(profil.calculer(station_2023(), "max").reglages["couper_effets"])

    def test_services_coupes_uniquement_au_niveau_max(self):
        for niveau in ("doux", "equilibre"):
            self.assertFalse(profil.calculer(portable_2009(), niveau).reglages["couper_services"])
        self.assertTrue(profil.calculer(portable_2009(), "max").reglages["couper_services"])

    def test_honnetete_sur_machine_recente(self):
        """On doit dire que le gain sera faible, pas promettre un miracle."""
        resultat = profil.calculer(station_2023(), "max")
        self.assertIn("faible", resultat.gain_attendu)

    def test_niveau_conseille(self):
        self.assertEqual(profil.niveau_conseille(portable_2009()), "max")
        self.assertEqual(profil.niveau_conseille(station_2023()), "doux")


# --------------------------------------------------------------------------
# la promesse de réversibilité
# --------------------------------------------------------------------------

class TestReversibilite(unittest.TestCase):

    def test_toute_action_sait_se_defaire(self):
        """Aucune action ne doit exister sans son inverse."""
        for action in actions.CATALOGUE:
            with self.subTest(action=action.identifiant):
                self.assertTrue(action.identifiant, "action sans identifiant")
                self.assertTrue(action.titre, f"{action.identifiant} : pas de titre")
                self.assertTrue(action.explication, f"{action.identifiant} : pas d'explication")
                self.assertIn(action.niveau_minimum, actions.NIVEAUX)
                for methode in ("appliquer", "annuler"):
                    self.assertIsNot(
                        getattr(type(action), methode),
                        getattr(actions.Action, methode),
                        f"{action.identifiant} n'implémente pas {methode}()",
                    )

    def test_simulation_produit_les_donnees_de_restauration(self):
        """En simulation, une action retenue doit déjà savoir comment revenir."""
        machine = portable_2009()
        reglages = profil.calculer(machine, "max").reglages

        for action in actions.CATALOGUE:
            utile, _ = action.pertinente(machine)
            if not utile:
                continue
            with self.subTest(action=action.identifiant):
                resultat = action.appliquer(machine, reglages, simulation=True)
                self.assertTrue(resultat.reussi, f"{action.identifiant} : {resultat.message}")
                self.assertTrue(resultat.message, "un résultat doit toujours s'expliquer")
                if not resultat.ignoree:
                    self.assertTrue(
                        resultat.restauration,
                        f"{action.identifiant} s'applique sans données de restauration",
                    )

    def test_simulation_ne_touche_a_rien(self):
        """Aucun fichier système ne doit apparaître pendant une simulation."""
        machine = portable_2009()
        reglages = profil.calculer(machine, "max").reglages
        surveilles = [
            actions.SysctlMemoire.FICHIER,
            actions.Zram.CONF,
            actions.JournalSystemd.FICHIER,
            actions.MiniaturesFichiers.FICHIER,
        ]
        avant = {c: os.path.exists(c) for c in surveilles}
        for action in actions.CATALOGUE:
            action.appliquer(machine, reglages, simulation=True)
        for chemin, existait in avant.items():
            self.assertEqual(
                os.path.exists(chemin), existait,
                f"la simulation a touché {chemin}",
            )

    def test_readahead_ne_degrade_jamais(self):
        """Si le noyau règle déjà mieux que nous, on ne touche à rien.

        Certains noyaux et certaines cartes RAID montent l'anticipation de
        lecture bien plus haut que notre cible. Écraser cette valeur
        ralentirait la machine au lieu de l'accélérer.
        """
        import tempfile
        from boost import systeme

        machine = portable_2009()
        action = actions.ReadaheadDisque()
        vrai_lire = systeme.lire_sysfs

        for actuel, doit_ignorer in (("128", False), ("2048", True), ("8192", True)):
            systeme.lire_sysfs = lambda _chemin, v=actuel: v
            try:
                resultat = action.appliquer(machine, {"readahead_kio": 2048}, simulation=True)
            finally:
                systeme.lire_sysfs = vrai_lire
            with self.subTest(actuel=actuel):
                self.assertTrue(resultat.reussi)
                self.assertEqual(
                    resultat.ignoree, doit_ignorer,
                    f"anticipation à {actuel} Kio : décision incorrecte "
                    f"({resultat.message})",
                )

    def test_niveaux_ordonnes(self):
        self.assertTrue(actions.niveau_atteint("max", "doux"))
        self.assertTrue(actions.niveau_atteint("max", "max"))
        self.assertFalse(actions.niveau_atteint("doux", "max"))
        self.assertFalse(actions.niveau_atteint("equilibre", "max"))
        self.assertFalse(actions.niveau_atteint("n'importe quoi", "doux"))


# --------------------------------------------------------------------------
# le journal
# --------------------------------------------------------------------------

class TestJournal(unittest.TestCase):

    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        self.chemin = os.path.join(self.dossier.name, "journal.json")

    def tearDown(self):
        self.dossier.cleanup()

    def test_aller_retour(self):
        j = journal.Journal(self.chemin)
        j.ajouter("zram", "max", {"fichier": {"chemin": "/etc/lexos/zram.conf", "existait": False}})
        self.assertTrue(j.est_applique("zram"))

        relu = journal.Journal(self.chemin)
        self.assertEqual(len(relu.actives()), 1)
        self.assertEqual(relu.actives()[0].action, "zram")
        self.assertFalse(relu.actives()[0].annulee)

    def test_annulation_retire_de_la_liste_active(self):
        j = journal.Journal(self.chemin)
        entree = j.ajouter("zram", "max", {})
        j.marquer_annulee(entree.identifiant)
        self.assertEqual(journal.Journal(self.chemin).actives(), [])

    def test_ordre_inverse_de_l_application(self):
        """On défait toujours dans l'ordre contraire de l'application."""
        j = journal.Journal(self.chemin)
        for identifiant in ("sysctl_memoire", "zram", "noatime"):
            j.ajouter(identifiant, "max", {})
        self.assertEqual(
            [e.action for e in j.actives()],
            ["noatime", "zram", "sysctl_memoire"],
        )

    def test_journal_corrompu_est_mis_de_cote(self):
        """Un journal illisible ne doit jamais être écrasé en silence."""
        with open(self.chemin, "w", encoding="utf-8") as f:
            f.write("{ceci n'est pas du JSON")
        j = journal.Journal(self.chemin)
        self.assertEqual(j.entrees, [])
        self.assertTrue(
            os.path.exists(self.chemin + ".illisible"),
            "le journal corrompu doit être conservé pour inspection",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
