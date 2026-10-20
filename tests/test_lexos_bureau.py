#!/usr/bin/env python3
"""Banc du bureau du Moteur (lexos-bureau) et de ti-lex IA installé.

Ce qu'il éprouve, sans serveur graphique :
  · reglages.py ne garde que des valeurs valides, même d'un fichier abîmé ;
  · applis.Table lit le dossier Bureau SANS le modifier, met les icônes de
    la planche d'Alex, et survit à un dossier illisible (vu en vraie
    session : Path.is_file() lève sous Python 3.13) ;
  · le serveur exige le jeton, refuse un hôte ou une origine étrangère, ne
    lance que ce qui est dans sa table, et sert bien « /fonds.js » (qui
    commence comme la route protégée « /fond » — le 403 a été vu) ;
  · fonds.js est la copie CONFORME des fonds animés du Moteur ;
  · le Moteur installé range ses données dans le compte, pas dans /usr/lib ;
  · les Paramètres écrivent les réglages par la même validation.

Ce qui a été éprouvé À LA MAIN, sous Xvfb avec xfce4-session, xfwm4 et
xfdesktop 4.18 réels (pas reproductible ici sans serveur X) :
  · la fenêtre sort en _NET_WM_WINDOW_TYPE_DESKTOP, sans cadre, en (0, 0) ;
  · xfdesktop s'arrête, et la session ne le relance pas ;
  · moteur tué (kill -9) → xfdesktop revient tout de suite, puis le moteur ;
  · « lexos-bureau classique » / « moteur » basculent dans les deux sens.
"""
import hashlib
import http.client
import importlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

R = Path(__file__).resolve().parents[1]
INC = R / "config/includes.chroot"
BUREAU = INC / "usr/lib/lexos/bureau"
TILEX = INC / "usr/lib/lexos/ti-lex-ia"
ICONES = INC / "usr/share/lexos/bureau-icones"


def charger(maison: Path):
    """Importe reglages/applis/serveur avec HOME détourné (ils lisent HOME à l'import)."""
    os.environ["HOME"] = str(maison)
    os.environ["XDG_CONFIG_HOME"] = str(maison / ".config")
    os.environ["LEXOS_BUREAU_ICONES"] = str(ICONES)
    os.environ["LEXOS_BUREAU_MOTEUR_UI"] = str(TILEX / "interface")
    sys.path.insert(0, str(BUREAU))
    for m in ("reglages", "applis", "serveur"):
        sys.modules.pop(m, None)
    import reglages, applis, serveur  # noqa: E401
    return reglages, applis, serveur


class Reglages(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.rg, _, _ = charger(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def test_defauts(self):
        r = self.rg.lire()
        self.assertEqual(r["mode"], "moteur")
        self.assertEqual(r["anim"], "constellation")
        self.assertEqual(r["accent"], "#ff7a18")

    def test_valeurs_refusees(self):
        r = self.rg.ecrire({"mode": "pirate", "anim": "rm -rf", "accent": "rouge;", "taille": 9999,
                            "police": "Comic", "image": "relatif.png", "orbes": "oui", "inconnu": 1})
        self.assertEqual(r["mode"], "moteur")
        self.assertEqual(r["anim"], "constellation")
        self.assertEqual(r["accent"], "#ff7a18")
        self.assertEqual(r["taille"], 140)          # borné, pas refusé
        self.assertEqual(r["police"], "Space Grotesk")
        self.assertEqual(r["image"], "")
        self.assertIs(r["orbes"], True)
        self.assertNotIn("inconnu", json.loads(self.rg.FICHIER.read_text()))

    def test_valeurs_acceptees(self):
        r = self.rg.ecrire({"anim": "braises", "accent": "#1E6BFF", "image": "/home/x/fond.webp",
                            "police": "Orbitron", "orbes": False})
        self.assertEqual((r["anim"], r["accent"], r["police"], r["orbes"]), ("braises", "#1e6bff", "Orbitron", False))
        self.assertEqual(r["image"], "/home/x/fond.webp")
        self.assertEqual(self.rg.ecrire({"image": "/x/photo.avif"})["image"], "/home/x/fond.webp")

    def test_image_inconnue_ne_fait_pas_tomber(self):
        #  « ~inconnu/… » : expanduser() lève RuntimeError (relu par la relecture)
        self.rg.FICHIER.parent.mkdir(parents=True, exist_ok=True)
        self.rg.FICHIER.write_text(json.dumps({"image": "~utilisateur-qui-nexiste-pas/a.png"}))
        self.assertEqual(self.rg.lire()["image"], "")

    def test_fond_non_affichable_retire_image(self):
        self.rg.ecrire({"image": "/x/ancien.png"})
        self.rg.image_du_fond("/x/nouveau.bmp")
        self.assertEqual(self.rg.lire()["image"], "")
        self.rg.image_du_fond("/x/nouveau.jpg")
        self.assertEqual(self.rg.lire()["image"], "/x/nouveau.jpg")

    def test_ecritures_simultanees(self):
        erreurs = []
        def ecrire(i):
            try:
                for _ in range(20):
                    self.rg.ecrire({"densite": 20 + i})
            except Exception as e:  # noqa: BLE001
                erreurs.append(e)
        fils = [threading.Thread(target=ecrire, args=(i,)) for i in range(6)]
        [f.start() for f in fils]; [f.join() for f in fils]
        self.assertEqual(erreurs, [])
        self.assertIn(self.rg.lire()["densite"], range(20, 26))

    def test_logo_du_centre(self):
        r = self.rg.lire()
        self.assertEqual((r["embleme"], r["code"]), ("nomad", True))
        self.assertIsNone(self.rg._propre("embleme", "/etc/passwd"))
        self.assertEqual(self.rg._propre("embleme", "aucun"), "aucun")

    def test_positions(self):
        r = self.rg.ecrire({"positions": {"s-corbeille": [918, 980], "a-0123456789abcd": [1.7, -5],
                                          "../piege": [1, 1], "b-x": "pas une position",
                                          "t-chat": [True, 3]}})
        self.assertEqual(r["positions"], {"s-corbeille": [918, 980], "a-0123456789abcd": [1, 0]})
        self.assertEqual(self.rg.ecrire({"positions": {}})["positions"], {})
        self.assertEqual(self.rg.ecrire({"positions": {f"b-{i}": [1, 1] for i in range(500)}})["positions"], {})

    def test_fichier_abime(self):
        self.rg.FICHIER.parent.mkdir(parents=True, exist_ok=True)
        self.rg.FICHIER.write_text("{ pas du json")
        self.assertEqual(self.rg.lire()["mode"], "moteur")
        self.rg.FICHIER.write_text(json.dumps({"mode": "classique", "taille": "grand"}))
        r = self.rg.lire()
        self.assertEqual((r["mode"], r["taille"]), ("classique", 100))

    def test_memes_choix_que_le_moteur(self):
        fond = (TILEX / "interface/fond.js").read_text(encoding="utf-8")
        for _nom, hexa in self.rg.COULEURS:
            self.assertIn(f'"{hexa}"', fond, hexa)
        for p in self.rg.POLICES:
            self.assertIn(f'["{p}"', fond, p)
        for f in self.rg.FONDS:
            self.assertRegex(fond, rf"\n  {f}: \{{", f)


class Table(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        m = Path(self.tmp.name)
        b = m / "Bureau"
        (b / "Projets").mkdir(parents=True)
        (b / "notes.txt").write_text("x")
        (b / "facture.pdf").write_text("%PDF")
        (b / "photo.png").write_bytes(b"\x89PNG")
        (b / ".cache-cachee").write_text("x")
        (b / "outil.desktop").write_text("[Desktop Entry]\nType=Application\nName=Mon outil\nExec=true\nIcon=folder\n")
        (b / "casse.desktop").write_text("pas un desktop")
        (b / "site.desktop").write_text("[Desktop Entry]\nType=Link\nName=Mon site\nURL=https://example.org\n")
        (b / "piege.desktop").write_text("[Desktop Entry]\nType=Link\nName=Piège\nURL=file:///bin/sh\n")
        os.close(os.open(os.path.join(str(b).encode(), b"caf\xe9.txt"), os.O_CREAT | os.O_WRONLY))
        self.maison = m
        self.avant = sorted((p.name, p.stat().st_mtime_ns) for p in b.iterdir())
        self._detache_orig = None
        _, self.ap, _ = charger(m)

    def tearDown(self):
        self.tmp.cleanup()

    def test_bureau(self):
        t = self.ap.Table()
        el = {e["nom"]: e for e in t.section_bureau()}
        self.assertIn("Dossier personnel", el)
        self.assertIn("Corbeille", el)
        self.assertIn("Projets", el)
        self.assertIn("Mon outil", el)
        self.assertNotIn(".cache-cachee", el)
        self.assertNotIn("casse.desktop", el)
        #  Les icônes de la planche d'Alex, selon le genre de fichier
        self.assertEqual(t.icones[el["facture.pdf"]["id"]].name, "pdf.png")
        self.assertEqual(t.icones[el["notes.txt"]["id"]].name, "texte.png")
        self.assertEqual(t.icones[el["Projets"]["id"]].name, "fichiers.png")
        self.assertEqual(t.icones[el["Corbeille"]["id"]].name, "corbeille.png")
        self.assertTrue(el["facture.pdf"]["plein"])
        #  Une photo se montre elle-même
        self.assertEqual(t.icones[el["photo.png"]["id"]].name, "photo.png")
        self.assertEqual(t.actions[el["Corbeille"]["id"]], ("ouvrir", "trash:///"))

    def test_lanceur_du_bureau_doit_etre_approuve(self):
        t = self.ap.Table()
        el = {e["nom"]: e for e in t.section_bureau()}
        self.assertEqual(t.actions[el["Mon outil"]["id"]][0], "desktop-bureau")
        lances = []
        self.ap._detache = lambda cmd: lances.append(cmd) or True
        #  ni exécutable ni empreinte XFCE : refusé, et Fichiers s'ouvre
        r = self.ap.lancer(*t.actions[el["Mon outil"]["id"]])
        self.assertEqual(r, "non-approuve")
        self.assertFalse(any(c[:2] == ["gio", "launch"] for c in lances))

    def test_liens_web_seulement(self):
        t = self.ap.Table()
        el = {e["nom"]: e for e in t.section_bureau()}
        lances = []
        self.ap._detache = lambda cmd: lances.append(cmd) or True
        self.assertEqual(self.ap.lancer(*t.actions[el["Piège"]["id"]]), "lien-refuse")
        self.ap.lancer(*t.actions[el["Mon site"]["id"]])
        self.assertTrue(any("https://example.org" in c for c in lances))

    def test_nom_non_utf8(self):
        t = self.ap.Table()
        noms = [e["nom"] for e in t.section_bureau()]
        self.assertIn("caf\ufffd.txt", noms)
        json.dumps(noms, ensure_ascii=False).encode("utf-8")      # ne lève plus

    def test_rien_ne_bouge(self):
        self.ap.Table().section_bureau()
        apres = sorted((p.name, p.stat().st_mtime_ns) for p in (self.maison / "Bureau").iterdir())
        self.assertEqual(self.avant, apres)

    def test_dossier_illisible(self):
        if os.geteuid() == 0:
            #  root lit tout : on simule l'exception de Python 3.13 à la place.
            from unittest import mock
            with mock.patch.object(Path, "is_file", side_effect=PermissionError("refusé")):
                self.assertFalse(self.ap._est_fichier(Path("/nulle/part")))
            return
        d = self.maison / "interdit"
        d.mkdir()
        (d / "applications").mkdir()
        d.chmod(0)
        try:
            os.environ["XDG_DATA_DIRS"] = f"{d}:/usr/share"
            self.assertIsNone(self.ap.trouver_desktop("absent-de-partout.desktop"))
        finally:
            d.chmod(0o755)

    def test_planche_complete(self):
        pngs = sorted(p.stem for p in ICONES.glob("*.png"))
        self.assertEqual(len(pngs), 32)
        for _e, vis, _n, _c in self.ap.LEXOS:
            if vis:
                self.assertIn(vis, pngs)
        for v in set(self.ap.VISUEL_FICHIER.values()):
            self.assertIn(v, pngs)


class Serveur(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        (Path(cls.tmp.name) / "Bureau").mkdir()
        _, cls.ap, cls.sv = charger(Path(cls.tmp.name))
        cls.etat = cls.sv.Etat()
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), cls.sv.fabriquer(cls.etat))
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.lances = []
        cls.ap.lancer = lambda genre, cible: cls.lances.append((genre, cible)) or True

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        cls.tmp.cleanup()

    def req(self, methode, chemin, corps=None, entetes=None, jeton=True):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        h = dict(entetes or {})
        if jeton:
            h.setdefault("X-Jeton", self.etat.jeton)
        b = json.dumps(corps).encode() if corps is not None else None
        if b is not None:
            h["Content-Type"] = "application/json"
        c.request(methode, chemin, body=b, headers=h)
        r = c.getresponse()
        return r.status, r.read()

    def test_page_et_fonds_js(self):
        self.assertEqual(self.req("GET", "/", jeton=False)[0], 200)
        #  « /fonds.js » commence comme « /fond » : il doit rester public.
        code, corps = self.req("GET", "/fonds.js", jeton=False)
        self.assertEqual(code, 200)
        self.assertIn(b"const FONDS", corps)
        self.assertEqual(self.req("GET", "/polices.css", jeton=False)[0], 200)

    def test_jeton_exige(self):
        self.assertEqual(self.req("GET", "/api/etat", jeton=False)[0], 403)
        self.assertEqual(self.req("GET", "/api/etat", entetes={"X-Jeton": "faux"})[0], 403)
        self.assertEqual(self.req("GET", "/api/etat")[0], 200)

    def test_hote_et_origine(self):
        self.assertEqual(self.req("GET", "/api/etat", entetes={"Host": "evil.example"})[0], 403)
        self.assertEqual(self.req("POST", "/api/lancer", {"id": "s-maison"},
                                  entetes={"Origin": "https://evil.example"})[0], 403)

    def test_ne_lance_que_sa_table(self):
        self.req("GET", "/api/etat")
        self.lances.clear()
        code, corps = self.req("POST", "/api/lancer", {"id": "/bin/sh"})
        self.assertEqual(json.loads(corps)["ok"], False)
        self.req("POST", "/api/lancer", {"id": "s-maison"})
        self.assertEqual(self.lances, [("ouvrir", str(Path(self.tmp.name)))])

    def test_traversee(self):
        self.assertIn(self.req("GET", "/../serveur.py", jeton=False)[0], (403, 404))
        self.assertIn(self.req("GET", "/polices/../../moteur.py", jeton=False)[0], (403, 404))

    def test_reglages_par_la_page(self):
        code, corps = self.req("POST", "/api/reglages", {"anim": "vagues", "mode": "pirate"})
        r = json.loads(corps)["reglages"]
        self.assertEqual((r["anim"], r["mode"]), ("vagues", "moteur"))
        self.assertFalse(self.etat.fin.is_set())

    def test_deux_colonnes_et_logo(self):
        """Nouvelle version du Moteur : ti-lex IA et Mon bureau à gauche,
        LexOS à droite ; la bannière LexOS Nomad servie avec le logo rond."""
        etat = json.loads(self.req("GET", "/api/etat")[1])
        cotes = {s["titre"]: s["cote"] for s in etat["sections"]}
        self.assertEqual(cotes.get("Mon bureau"), "gauche")
        for titre, cote in (("ti-lex IA", "gauche"), ("LexOS", "droite")):
            if titre in cotes:
                self.assertEqual(cotes[titre], cote)
        self.assertIn("dock", etat)
        self.assertIn("zone", etat)
        code, corps = self.req("GET", "/lexos-nomad.png", jeton=False)
        self.assertEqual(code, 200)
        self.assertTrue(corps.startswith(b"\x89PNG"))
        self.assertEqual(self.req("GET", "/logo.png", jeton=False)[0], 200)
        page = self.req("GET", "/", jeton=False)[1].decode()
        for ident in ("embleme", "embleme-img", "code", "cote-gauche", "cote-droite", "vers-abo"):
            self.assertIn(f'id="{ident}"', page, ident)

    def test_demander_seulement_chat_ou_abo(self):
        lances = []
        avant_d, avant_w = self.sv.applis._detache, self.sv.shutil.which
        self.sv.applis._detache = lambda cmd: lances.append(cmd) or True
        self.sv.shutil.which = lambda nom: "/usr/bin/" + nom
        try:
            self.req("POST", "/api/demander", {"q": "salut", "vers": "abo"})
            self.req("POST", "/api/demander", {"q": "salut", "vers": "--rm"})
            self.req("POST", "/api/demander", {"q": "salut"})
        finally:
            self.sv.applis._detache, self.sv.shutil.which = avant_d, avant_w
        self.assertEqual([c[1] for c in lances], ["abo", "chat", "chat"])

    def test_logo_par_la_page(self):
        r = json.loads(self.req("POST", "/api/reglages", {"embleme": "rond", "code": False})[1])["reglages"]
        self.assertEqual((r["embleme"], r["code"]), ("rond", False))
        r = json.loads(self.req("POST", "/api/reglages", {"embleme": "../x", "code": "oui"})[1])["reglages"]
        self.assertEqual((r["embleme"], r["code"]), ("rond", False))
        self.req("POST", "/api/reglages", {"embleme": "nomad", "code": True})

    def test_double_clic_un_seul_lancement(self):
        self.req("GET", "/api/etat")
        self.lances.clear()
        self.req("POST", "/api/lancer", {"id": "s-corbeille"})
        _, corps = self.req("POST", "/api/lancer", {"id": "s-corbeille"})
        self.assertTrue(json.loads(corps).get("deja"))
        self.assertEqual(len(self.lances), 1)

    def test_icones_en_bac_a_sable(self):
        Path(self.tmp.name, "Bureau", "x.svg").write_text("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>")
        etat = json.loads(self.req("GET", "/api/etat")[1])
        ident = next(e["id"] for s in etat["sections"] for e in s["elements"] if e["nom"] == "x.svg")
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", f"/icone/{ident}?t={self.etat.jeton}")
        r = c.getresponse(); r.read()
        self.assertEqual(r.status, 200)
        self.assertIn("sandbox", r.getheader("Content-Security-Policy") or "")

    def test_ranger(self):
        self.req("POST", "/api/reglages", {"positions": {"s-maison": [400, 300]}})
        self.req("POST", "/api/action", {"nom": "ranger"})
        etat = json.loads(self.req("GET", "/api/etat")[1])
        self.assertEqual(etat["reglages"]["positions"], {})

    def test_action_inconnue(self):
        self.assertEqual(json.loads(self.req("POST", "/api/action", {"nom": "rm"})[1])["ok"], False)


class CopieConforme(unittest.TestCase):
    def test_fonds_identiques_au_moteur(self):
        moteur = (TILEX / "interface/fond.js").read_text(encoding="utf-8")
        copie = (BUREAU / "web/fonds.js").read_text(encoding="utf-8")
        def bloc(t):
            i = t.index("const OR = ")
            j = t.index("\n};", t.index("const FONDS = {")) + 3
            return t[i:j]
        self.assertEqual(bloc(moteur), bloc(copie))


class MoteurInstalle(unittest.TestCase):
    def test_donnees_dans_le_compte(self):
        with tempfile.TemporaryDirectory() as d:
            code = (
                "import sys; sys.path.insert(0, sys.argv[1]); import moteur as m; "
                "print(m.INSTALLE, m.DONNEES, m.ACCES.parent, m.CONVERSATIONS.parent)")
            env = dict(os.environ, LEXOS_MOTEUR_DONNEES=d + "/tilex", HOME=d)
            out = subprocess.run([sys.executable, "-c", code, str(TILEX)], env=env,
                                 capture_output=True, text=True, check=True).stdout.split()
            self.assertEqual(out[0], "True")
            self.assertTrue(all(x == str(Path(d) / "tilex") for x in out[1:]), out)
            env.pop("LEXOS_MOTEUR_DONNEES")
            out = subprocess.run([sys.executable, "-c", code, str(TILEX)], env=env,
                                 capture_output=True, text=True, check=True).stdout.split()
            self.assertEqual(out[0], "False")          # la clé : inchangé

    def test_lien_onglets_connus(self):
        app = (TILEX / "interface/app.js").read_text(encoding="utf-8")
        self.assertIn("Object.hasOwn(LANCEURS, id)", app)
        lanceur = (INC / "usr/bin/ti-lex-ia").read_text(encoding="utf-8")
        onglets = set(re.search(r'""\|([a-z|]+)\) ;;', lanceur).group(1).split("|"))
        bureau = (TILEX / "interface/bureau.js").read_text(encoding="utf-8")
        for o in onglets:
            self.assertRegex(bureau, rf"\n  {o}: \{{", o)

    def test_abonnement(self):
        """🌐 Mon abonnement (nouvelle version du Moteur) : livré, chargé par
        la page, ouvrable par « ti-lex-ia abo » et par une icône du bureau."""
        self.assertTrue((TILEX / "interface/abonnement.js").is_file())
        self.assertTrue((TILEX / "interface/lexos-nomad.png").is_file())
        index = (TILEX / "interface/index.html").read_text(encoding="utf-8")
        self.assertIn('<script src="abonnement.js"></script>', index)
        lanceur = (INC / "usr/bin/ti-lex-ia").read_text(encoding="utf-8")
        self.assertRegex(lanceur, r'\|abo\) ;;')
        sys.path.insert(0, str(BUREAU))
        sys.modules.pop("applis", None)
        import applis
        self.assertIn("abo", [o for o, _, _ in applis.TILEX])

    def test_aucune_donnee_privee_livree(self):
        for nom in ("acces.json", ".env.coffre", "parametres.json", "nuage.json", "compteur.json"):
            self.assertFalse((TILEX / nom).exists(), nom)
        for d in ("conversations", "projets", "images", "schemas", "fonds", "bureau"):
            self.assertFalse((TILEX / d).exists(), d)


class Parametres(unittest.TestCase):
    def test_action(self):
        with tempfile.TemporaryDirectory() as d:
            os.environ["HOME"] = d
            os.environ["XDG_CONFIG_HOME"] = d + "/.config"
            os.environ["LEXOS_BUREAU_DIR"] = str(BUREAU)
            sys.path.insert(0, str(INC / "usr/lib/lexos"))
            for m in ("settings", "reglages"):
                sys.modules.pop(m, None)
            try:
                settings = importlib.import_module("settings")
            except ImportError as e:
                self.skipTest(f"settings.py non importable ici : {e}")
            self.assertIn("bureau-moteur", settings.ACTIONS)
            self.assertFalse(settings.act_bureau_moteur("texte")["ok"])
            self.assertTrue(settings.act_bureau_moteur({"anim": "aurore", "accent": "#facc15"})["ok"])
            e = settings._bureau_moteur_etat()
            self.assertEqual((e["anim"], e["accent"]), ("aurore", "#facc15"))


class Scripts(unittest.TestCase):
    def test_shell(self):
        for s in ("usr/bin/lexos-bureau", "usr/bin/ti-lex-ia"):
            subprocess.run(["sh", "-n", str(INC / s)], check=True)

    def test_autostart(self):
        t = (INC / "etc/xdg/autostart/lexos-bureau.desktop").read_text()
        self.assertIn("Exec=/usr/bin/lexos-bureau", t)
        self.assertIn("OnlyShowIn=XFCE;", t)

    def test_permissions_lisibles(self):
        #  logo.png est sorti du zip en 600 : illisible pour le compte d'Alex,
        #  le bureau montrait une image cassée. Tout doit être lisible.
        for racine in (TILEX, BUREAU, ICONES):
            for p in racine.rglob("*"):
                if p.is_file():
                    self.assertTrue(p.stat().st_mode & 0o004, p)


if __name__ == "__main__":
    unittest.main(verbosity=2)
