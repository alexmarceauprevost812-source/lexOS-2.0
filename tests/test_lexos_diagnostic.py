"""Tests de fumée pour LexOS Diagnostic.

Usage (depuis la racine du dépôt, une fois les fichiers copiés — voir
integration/README-integration.md) :

    python3 -m unittest tests/test_lexos_diagnostic.py -v

Zéro dépendance au-delà de la bibliothèque standard + psutil (déjà requis
par le moteur lui-même). Comme lexos-prive n'a « aucun test — c'est celui où
une régression silencieuse fait le plus de dégâts » (lexos-carte-des-trous.md,
section 5), ce fichier part avec ce nouvel outil plutôt que d'attendre.

Ne vérifie pas des valeurs précises (elles dépendent de la machine qui fait
tourner les tests) mais que :
  - chaque instantané se construit sans lever d'exception, même sans les
    outils externes (inxi, smartctl, nvidia-smi…) — condition réelle d'une
    machine de CI, et déjà la condition dans laquelle ce fichier a été
    écrit et vérifié ;
  - la forme du JSON renvoyé a les clés attendues, pour attraper une
    régression qui romprait le contrat entre le moteur et l'interface web
    (web/app.js lit ces clés par leur nom).
"""
import http.client
import socket
import sys
import threading
import unittest
from pathlib import Path

RACINE_MOTEUR = Path(__file__).resolve().parent.parent / "config/includes.chroot/usr/lib/lexos/diagnostic"
sys.path.insert(0, str(RACINE_MOTEUR))

import disques  # noqa: E402
import medecin  # noqa: E402
import moteur  # noqa: E402


class TestMoteur(unittest.TestCase):
    def test_instantane_ne_plante_pas(self):
        snap = moteur.instantane()
        for cle in ("systeme", "cpu", "ram", "gpu", "ventilateurs", "disques", "reseau", "batterie", "processus"):
            self.assertIn(cle, snap)

    def test_deux_instantanes_de_suite(self):
        # Le premier amorce les compteurs delta (réseau, processus) ; le
        # deuxième doit rester silencieux lui aussi.
        moteur.instantane()
        snap = moteur.instantane()
        self.assertIsInstance(snap["reseau"]["interfaces"], list)
        self.assertIsInstance(snap["processus"]["top_cpu"], list)

    def test_cpu_pourcentage_dans_les_bornes(self):
        pct = moteur.instantane()["cpu"]["utilisation_globale_pct"]
        self.assertIsNotNone(pct)
        self.assertGreaterEqual(pct, 0)
        self.assertLessEqual(pct, 100)

    def test_gpu_a_toujours_un_message_si_indisponible(self):
        gpu = moteur.instantane()["gpu"]
        if not gpu["disponible"]:
            self.assertIsNotNone(gpu["message"])


class TestMedecin(unittest.TestCase):
    def test_bilan_complet_ne_plante_pas(self):
        bilan = medecin.bilan_complet()
        for cle in ("outils", "son", "wifi", "disques_pleins", "journal"):
            self.assertIn(cle, bilan)

    def test_rapport_texte_est_une_chaine_non_vide(self):
        rapport = medecin.rapport_texte()
        self.assertIsInstance(rapport, str)
        self.assertIn("Bilan LexOS Médecin", rapport)

    def test_no_entries_journalctl_ne_compte_pas_comme_erreur(self):
        # Régression trouvée pendant l'écriture : journalctl répond
        # "-- No entries --" quand tout va bien, et ça ne doit jamais
        # gonfler le compte d'erreurs.
        resultat = medecin.verifier_erreurs_journal()
        for ligne in resultat["lignes"]:
            self.assertNotIn("No entries", ligne)


class TestDisques(unittest.TestCase):
    def test_rapport_disques_ne_plante_pas(self):
        rapport = disques.rapport_disques()
        for cle in ("sante", "espace", "outils"):
            self.assertIn(cle, rapport)

    def test_outils_disponibles_est_bien_forme(self):
        outils = disques.outils_disponibles()
        for cle in ("smartctl", "nvme", "rmlint", "f3"):
            self.assertIn(cle, outils)
            self.assertIsInstance(outils[cle], bool)


if __name__ == "__main__":
    unittest.main()


class TestServeurLocal(unittest.TestCase):
    """Le serveur n'obéit qu'à la machine elle-même.

    ═══ POURQUOI CE CONTRÔLE EXISTE ═══
    Ce module écoute sur un port FIXE (7861), contrairement au serveur des
    Paramètres qui tire un port libre au lancement (settings.py, bind sur le
    port 0). Un port local prévisible est joignable par n'importe quelle page
    web que l'utilisateur ouvre : le navigateur l'empêchera de LIRE la
    réponse, mais rien n'empêche l'envoi — un site pourrait déclencher en
    boucle un scan de doublons de trente secondes. Et le nom « localhost »
    peut être repointé vers une adresse extérieure (« DNS rebinding »), ce qui
    fait tomber l'en-tête Host hors de la boucle locale.

    Deux vérifications dans serveur.py suffisent (_appelant_local). Elles ne
    coûtent rien à l'usage normal — et sans banc, les retirer un jour ne se
    verrait nulle part.
    """

    @classmethod
    def setUpClass(cls):
        import serveur  # noqa: PLC0415 - importé ici : il démarre un serveur

        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            cls.port = s.getsockname()[1]
        from http.server import ThreadingHTTPServer  # noqa: PLC0415

        cls.httpd = ThreadingHTTPServer(("127.0.0.1", cls.port), serveur.Gestionnaire)
        cls.fil = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.fil.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def _demander(self, chemin, methode="GET", entetes=None, hote=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        try:
            en = dict(entetes or {})
            en.setdefault("Host", hote or f"127.0.0.1:{self.port}")
            conn.request(methode, chemin, headers=en)
            return conn.getresponse().status
        finally:
            conn.close()

    def test_notre_propre_page_est_servie(self):
        self.assertEqual(self._demander("/"), 200)
        self.assertEqual(self._demander("/api/etat"), 200)

    def test_notre_propre_origine_est_acceptee(self):
        origine = f"http://127.0.0.1:{self.port}"
        self.assertEqual(self._demander("/api/etat", entetes={"Origin": origine}), 200)

    def test_une_page_etrangere_est_refusee(self):
        for methode in ("GET", "POST"):
            with self.subTest(methode=methode):
                code = self._demander(
                    "/api/etat", methode=methode,
                    entetes={"Origin": "https://exemple-mechant.invalid"})
                self.assertEqual(code, 403)

    def test_un_host_etranger_est_refuse(self):
        #  Le cas du « DNS rebinding » : la connexion arrive bien sur la
        #  boucle locale, mais le navigateur croit parler à un autre domaine.
        code = self._demander("/api/etat", hote="exemple-mechant.invalid")
        self.assertEqual(code, 403)

    def test_pas_de_traversee_de_chemin(self):
        self.assertIn(self._demander("/../../etc/passwd"), (403, 404))


if __name__ == "__main__":
    unittest.main()
