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
    for m in ("reglages", "applis", "gestes", "serveur"):
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
        self.assertEqual(r["mode"], "classique")
        self.assertEqual(r["anim"], "constellation")
        self.assertEqual(r["accent"], "#ff7a18")

    def test_valeurs_refusees(self):
        r = self.rg.ecrire({"mode": "pirate", "anim": "rm -rf", "accent": "rouge;", "taille": 9999,
                            "police": "Comic", "image": "relatif.png", "orbes": "oui", "inconnu": 1})
        self.assertEqual(r["mode"], "classique")
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

    def test_labo(self):
        r = self.rg.lire()
        self.assertEqual((r["labo"], r["labo_delai"], r["labo_apps"]), (True, 1000, ["*"]))
        self.assertEqual(self.rg._propre("labo_apps", ["t-chat", "t-chat", "../x", 3, "a-0123456789abcd"]),
                         ["t-chat", "a-0123456789abcd"])
        self.assertIsNone(self.rg._propre("labo_apps", "t-chat"))
        self.assertEqual(len(self.rg._propre("labo_apps", [f"a-{i:014d}" for i in range(500)])), self.rg.MAX_LABO)
        self.assertEqual(self.rg._propre("labo_delai", 50), 300)
        self.assertEqual(self.rg._propre("labo_delai", 99999), 3000)
        #  La liste par défaut n'est pas partagée entre deux lectures.
        self.rg.lire()["labo_apps"].append("t-x")
        self.assertEqual(self.rg.lire()["labo_apps"], ["*"])

    def test_outils(self):
        r = self.rg.lire()
        self.assertEqual((r["outils"], r["outils_apps"]), (True, ["*"]))
        self.assertEqual(self.rg._propre("outils_apps", ["a-0123456789abcd", "/bin/sh"]), ["a-0123456789abcd"])
        self.assertIsNone(self.rg._propre("outils", "oui"))

    def test_logo_du_centre(self):
        r = self.rg.lire()
        self.assertEqual((r["embleme"], r["code"]), ("nomad", False))
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
        self.assertEqual(self.rg.lire()["mode"], "classique")
        self.rg.FICHIER.write_text(json.dumps({"mode": "moteur", "taille": "grand"}))
        r = self.rg.lire()
        self.assertEqual((r["mode"], r["taille"]), ("moteur", 100))

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

    def test_toutes_les_applis(self):
        """Le labo propose TOUTES les applis d'un menu : pas NoDisplay, pas
        celles d'un autre bureau qu'XFCE ; la copie de l'utilisateur gagne."""
        d = self.maison / "partage"
        sys_apps, mes_apps = d / "sys/applications", d / "moi/applications"
        (sys_apps / "kde").mkdir(parents=True)
        mes_apps.mkdir(parents=True)
        entree = "[Desktop Entry]\nType=Application\nExec=true\nName={}\n{}"
        (sys_apps / "gimp.desktop").write_text(entree.format("GIMP", ""))
        (sys_apps / "cache.desktop").write_text(entree.format("Caché", "NoDisplay=true\n"))
        (sys_apps / "kde-seul.desktop").write_text(entree.format("KDE seul", "OnlyShowIn=KDE;\n"))
        (sys_apps / "pas-xfce.desktop").write_text(entree.format("Pas XFCE", "NotShowIn=XFCE;\n"))
        (sys_apps / "kde" / "outil.desktop").write_text(entree.format("Sous-dossier", ""))
        (sys_apps / "lien.desktop").write_text("[Desktop Entry]\nType=Link\nName=Lien\nURL=https://x\n")
        (sys_apps / "editeur.desktop").write_text(entree.format("Éditeur système", ""))
        (mes_apps / "editeur.desktop").write_text(entree.format("Mon éditeur", ""))
        avant = dict(os.environ)
        os.environ["XDG_DATA_HOME"] = str(d / "moi")
        os.environ["XDG_DATA_DIRS"] = str(d / "sys")
        try:
            t = self.ap.Table()
            noms = [e["nom"] for e in t.section_applis()]
        finally:
            os.environ.clear(); os.environ.update(avant)
        self.assertEqual(noms, ["GIMP", "Mon éditeur", "Sous-dossier"])
        ident = self.ap._ident("a-", str(sys_apps / "gimp.desktop"))
        self.assertEqual(t.actions[ident], ("desktop", str(sys_apps / "gimp.desktop")))

    def test_rayons(self):
        """Le ti démon range les applis comme le menu d'XFCE."""
        self.assertEqual(self.ap.rayon(["Network", "WebBrowser", "Utility"]), "Internet")
        self.assertEqual(self.ap.rayon(["AudioVideo", "Player"]), "Multimédia")
        self.assertEqual(self.ap.rayon(["Game", "ArcadeGame"]), "Jeux")
        self.assertEqual(self.ap.rayon(["X-Inconnu"]), "Autres")
        self.assertEqual(self.ap.rayon([]), "Autres")

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


class SaveurNomade(unittest.TestCase):
    """La saveur nomade (clé USB-C) démarre sur le bureau démon ; les autres
    gardent le classique. Le serveur sert demon.html à « / » quand le
    réglage « interface » le dit, et la page du démon ne lance que la table."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        (d / "Bureau").mkdir()
        (d / "build.conf").write_text('LEXOS_NAME="LexOS"\nLEXOS_VERSION="2.0.2"\nLEXOS_FLAVOUR="nomade"\n')
        (d / "cmdline").write_text("BOOT_IMAGE=/live/vmlinuz boot=live\n")
        os.environ["LEXOS_BUILD_CONF"] = str(d / "build.conf")
        os.environ["LEXOS_CMDLINE"] = str(d / "cmdline")
        self.rg, self.ap, self.sv = charger(d)

    def tearDown(self):
        os.environ.pop("LEXOS_BUILD_CONF", None)
        os.environ.pop("LEXOS_CMDLINE", None)
        self.tmp.cleanup()

    def test_defauts_nomade(self):
        r = self.rg.lire()
        self.assertEqual((r["mode"], r["interface"], r["demon_theme"]), ("moteur", "demon", "sang"))
        self.assertEqual(self.rg.ecrire({"interface": "ailleurs", "demon_theme": "rose"})["interface"], "demon")
        self.assertEqual(self.rg.ecrire({"demon_presence": 5})["demon_presence"], 20)

    def test_disposition_demon_aller_retour(self):
        """Le mode « modifier » du bureau démon : l'ordre de la grille et du
        dock, et la place du terminal, de l'heure et de la date, gardés côté
        serveur ; tout ce qui n'est pas valide est ramené ou refusé."""
        r = self.rg.lire()
        self.assertEqual((r["demon_grille"], r["demon_dock"], r["demon_places"]), (["*"], ["*"], {}))
        self.assertFalse(r["outils"])            # nomade : pas de barre qui tombe du haut
        self.rg.ecrire({"demon_grille": ["s-maison", "x-apropos", "s-maison", "../etc", 7],
                        "demon_dock": ["x-yeux", "s-github"],
                        "demon_places": {"terminal": [120, -40.6], "horloge": [5000, 3],
                                         "fenetre": [1, 1], "date": "loin"}})
        r = self.rg.lire()
        self.assertEqual(r["demon_grille"], ["s-maison", "x-apropos"])
        self.assertEqual(r["demon_dock"], ["x-yeux", "s-github"])
        self.assertEqual(r["demon_places"], {"terminal": [120, -40], "horloge": [1000, 3]})
        self.rg.ecrire({"demon_grille": ["*"], "demon_dock": ["*"], "demon_places": {}})
        r = self.rg.lire()
        self.assertEqual((r["demon_grille"], r["demon_dock"], r["demon_places"]), (["*"], ["*"], {}))

    def test_page_demon_a_la_racine(self):
        etat = self.sv.Etat()
        srv = ThreadingHTTPServer(("127.0.0.1", 0), self.sv.fabriquer(etat))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            def get(chemin, jeton=False):
                c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1], timeout=10)
                c.request("GET", chemin, headers={"X-Jeton": etat.jeton} if jeton else {})
                r = c.getresponse()
                return r.status, r.read(), r.getheader("Cache-Control")
            code, corps, cache = get("/?t=x")
            self.assertEqual(code, 200)
            self.assertIn(b'src="demon.js"', corps)
            self.assertEqual(cache, "no-store")
            self.assertIn(b'src="bureau.js"', get("/index.html")[1])
            for f in ("/demon.css", "/demon.js", "/logo-ti-lexos.png", "/github-perso.png",
                      "/avatar-alex.png", "/tux.png"):
                self.assertEqual(get(f)[0], 200, f)
            #  La vidéo d'ouverture : servie en video/webm, sinon elle ne joue pas.
            c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1], timeout=10)
            c.request("GET", "/demarrage-flammes.webm")
            r = c.getresponse(); r.read()
            self.assertEqual((r.status, r.getheader("Content-Type")), (200, "video/webm"))
            e = json.loads(get("/api/etat", jeton=True)[1])
            self.assertEqual(e["systeme"]["saveur"], "nomade")
            for d in e["demon"]:
                self.assertIn(d["id"], etat.table.actions)
            #  GitHub : l'adresse vient du serveur, jamais de la page.
            self.assertEqual(etat.table.actions["s-github"], ("url", self.ap.GITHUB))
            self.assertTrue(self.ap.GITHUB.startswith("https://github.com/"))
            self.assertIn("noyau", e["systeme"])
            #  Ce que portait la barre du haut : réseau et son, en lecture.
            for route in ("/api/reseau", "/api/son"):
                self.assertEqual(get(route, jeton=True)[0], 200, route)
            self.assertIn(json.loads(get("/api/reseau", jeton=True)[1])["etat"], ("connecte", "deconnecte", "inconnu"))
            self.assertEqual(get("/api/reseau")[0], 403)
            self.assertIn("reseau", self.sv.ACTIONS)
            self.rg.ecrire({"interface": "moteur"})
            self.assertIn(b'src="bureau.js"', get("/")[1])
        finally:
            srv.shutdown()
            srv.server_close()

    def test_page_sans_mot_de_passe_ni_reseau(self):
        html = (BUREAU / "web/demon.html").read_text(encoding="utf-8")
        js = (BUREAU / "web/demon.js").read_text(encoding="utf-8")
        self.assertNotIn('type="password"', html)
        self.assertNotIn("googleapis", html)
        self.assertIn("/api/lancer", js)
        self.assertIn("prefers-reduced-motion", js)


class Serveur(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        (Path(cls.tmp.name) / "Bureau").mkdir()
        rg, cls.ap, cls.sv = charger(Path(cls.tmp.name))
        #  Le défaut est « classique » : ces tests font tourner le Moteur.
        rg.ecrire({"mode": "moteur"})
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

    def test_labo(self):
        """🧪 Mon labo : la page, la liste (par défaut : les onglets de
        ti-lex IA puis les outils), et un clic qui lance une appli du labo."""
        self.assertEqual(self.req("GET", "/labo.html", jeton=False)[0], 200)
        self.assertEqual(self.req("GET", "/labo.js", jeton=False)[0], 200)
        self.assertEqual(self.req("GET", "/api/labo", jeton=False)[0], 403)
        L = json.loads(self.req("GET", "/api/labo")[1])
        titres = [s["titre"] for s in L["sections"]]
        self.assertIn("Mon bureau", titres)
        tous = {e["id"] for s in L["sections"] for e in s["elements"]}
        self.assertTrue({e["id"] for e in L["apps"]} <= tous)
        #  Le choix d'Alex, dans SON ordre ; un identifiant disparu ne casse rien.
        self.req("POST", "/api/reglages", {"labo_apps": ["s-corbeille", "a-00000000000000", "s-maison"]})
        L = json.loads(self.req("GET", "/api/labo")[1])
        self.assertEqual([e["id"] for e in L["apps"]], ["s-corbeille", "s-maison"])
        etat = json.loads(self.req("GET", "/api/etat")[1])
        self.assertEqual(etat["labo"], ["s-corbeille", "s-maison"])
        self.lances.clear()
        self.req("POST", "/api/lancer", {"id": "s-maison"})
        self.assertEqual(self.lances, [("ouvrir", str(Path(self.tmp.name)))])
        self.etat.derniers.clear()          # la garde du double-clic ne doit pas gêner les autres tests
        self.req("POST", "/api/reglages", {"labo_apps": ["*"]})

    def test_outils(self):
        """🎛️ Mes outils : la page, le ti démon, et des gestes fermés."""
        for f in ("/outils.html", "/outils.js", "/outils.css", "/ti-demon.png"):
            self.assertEqual(self.req("GET", f, jeton=False)[0], 200, f)
        self.assertEqual(self.req("GET", "/api/outils", jeton=False)[0], 403)
        O = json.loads(self.req("GET", "/api/outils")[1])
        for cle in ("apps", "sections", "son", "notifs", "dnd", "reglages"):
            self.assertIn(cle, O)
        tous = {e["id"] for s in O["sections"] for e in s["elements"]}
        self.assertTrue({e["id"] for e in O["apps"]} <= tous)
        #  Rien d'autre que les trois captures et les cinq gestes.
        self.assertFalse(json.loads(self.req("POST", "/api/capture", {"mode": "; rm -rf ~"})[1])["ok"])
        self.assertFalse(json.loads(self.req("POST", "/api/session", {"geste": "rm"})[1])["ok"])
        r = json.loads(self.req("POST", "/api/son", {"volume": "fort"})[1])
        self.assertFalse(r["ok"])
        self.req("POST", "/api/reglages", {"outils_apps": ["s-maison"]})
        O = json.loads(self.req("GET", "/api/outils")[1])
        self.assertEqual([e["id"] for e in O["apps"]], ["s-maison"])
        self.req("POST", "/api/reglages", {"outils_apps": ["*"]})

    def test_notifications(self):
        journal = Path(self.tmp.name, ".cache/xfce4/notifyd/log")
        journal.parent.mkdir(parents=True, exist_ok=True)
        journal.write_text("[1792000000]\napp_name=lexos-usb\nsummary=Clé USB branchée\nbody=LEXOS\n\n"
                           "[1792000100]\napp_name=x\nsummary=Plus récente\n", encoding="utf-8")
        avant = self.sv.gestes.JOURNAL_NOTIFS
        self.sv.gestes.JOURNAL_NOTIFS = journal
        try:
            O = json.loads(self.req("GET", "/api/outils")[1])
            self.assertEqual([n["titre"] for n in O["notifs"]], ["Plus récente", "Clé USB branchée"])
            r = json.loads(self.req("POST", "/api/notifs", {"vider": True})[1])
            self.assertEqual(r["notifs"], [])
            self.assertEqual(journal.read_text(), "")      # écrasé, pas supprimé
        finally:
            self.sv.gestes.JOURNAL_NOTIFS = avant

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

    def test_labo_et_relance(self):
        b = (INC / "usr/bin/lexos-bureau").read_text()
        self.assertIn("labo)", b)
        self.assertIn('pkill -USR1 -u "$(id -u)"', b)
        #  « relancer » n'est pas une chute : trois de suite ne laissent plus
        #  le bureau classique pour toute la session.
        self.assertIn('if [ -e "$RELANCE" ]; then', b)
        self.assertIn(': >"$RELANCE"', b)
        f = (BUREAU / "fenetre.py").read_text()
        self.assertIn("setSwapInterval(0)", f)       # le gel de glXSwapBuffers
        self.assertIn("query_pointer", f)            # QCursor.pos restait figé
        self.assertNotIn("QCursor.pos()\n", f)
        s = (BUREAU / "serveur.py").read_text()
        self.assertIn("signal.SIGUSR1, signal.SIG_IGN", s)   # SIGUSR1 tue par défaut
        raccourcis = (INC / "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml").read_text()
        self.assertIn('value="lexos-bureau labo"', raccourcis)

    def test_outils_et_tele(self):
        b = (INC / "usr/bin/lexos-bureau").read_text()
        self.assertIn("outils)", b)
        self.assertIn('pkill -USR2 -u "$(id -u)"', b)
        s = (BUREAU / "serveur.py").read_text()
        self.assertIn("signal.SIGUSR2, signal.SIG_IGN", s)
        f = (BUREAU / "fenetre.py").read_text()
        self.assertIn("class Outils(Tiroir)", f)
        self.assertIn("grabWindow(0)", f)                 # la photo de l'écran pour la télé
        self.assertIn('"systemctl", "poweroff"', f)        # le filet si l'arrêt ne vient pas
        self.assertIn("rendre_l_ecran", f)                 # jamais un écran noir pour toujours
        self.assertIn("set_input_focus", f)                # la recherche reçoit le clavier
        js = (BUREAU / "web/outils.js").read_text()
        self.assertIn('classList.contains("arme")', js)    # éteindre demande un 2e clic
        raccourcis = (INC / "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml").read_text()
        self.assertIn('value="lexos-bureau outils"', raccourcis)

    def test_relancer_ne_compte_pas_comme_chute(self):
        """La vraie boucle, avec un faux moteur qui sort aussitôt : après
        trois « relance » marquées, elle tourne encore."""
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            ici = d / "bureau"; ici.mkdir()
            (ici / "reglages.py").write_text((BUREAU / "reglages.py").read_text())
            compte = d / "compte"
            (ici / "serveur.py").write_text(
                "import os,sys\n"
                f"p='{compte}'\n"
                "n=int(open(p).read()) if os.path.exists(p) else 0\n"
                "open(p,'w').write(str(n+1))\n"
                f"r='{d}/run/lexos-bureau-'+str(os.getuid())+'.relance'\n"
                "if n < 3: open(r,'w').close()\n"
                "sys.exit(143)\n")
            (d / "run").mkdir()
            (d / ".config/lexos").mkdir(parents=True)
            (d / ".config/lexos/bureau.json").write_text('{"mode": "moteur"}')
            script = (INC / "usr/bin/lexos-bureau").read_text().replace("ICI=/usr/lib/lexos/bureau", f"ICI={ici}")
            (d / "lexos-bureau").write_text(script)
            faux = d / "bin"; faux.mkdir()
            for nom, corps in (("xfdesktop", "exit 0"), ("notify-send", "exit 0"),
                               ("xprop", "exit 0"), ("python3", f'case "$*" in *PySide6*) exit 0;; esac; exec {sys.executable} "$@"')):
                (faux / nom).write_text("#!/bin/sh\n" + corps + "\n"); (faux / nom).chmod(0o755)
            env = dict(os.environ, HOME=str(d), XDG_RUNTIME_DIR=str(d / "run"), XDG_CONFIG_HOME=str(d / ".config"),
                       XDG_CACHE_HOME=str(d / "cache"), PATH=f"{faux}:{os.environ['PATH']}", DISPLAY=":99")
            subprocess.run(["sh", str(d / "lexos-bureau")], env=env, timeout=60,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            #  3 relances voulues + 3 vraies chutes = 6 démarrages ; sans la
            #  marque, la boucle abandonnait au 3e.
            self.assertEqual(compte.read_text(), "6")

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
