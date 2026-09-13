"""Le petit serveur local des fenêtres LexOS — écrit UNE fois.

═══ POURQUOI CE MODULE EXISTE ═══
Compté dans le dépôt : la classe « Handler » existait en SIX exemplaires —
settings.py, volet.py, partage.py, ia-locale.py, terminal-pro.py,
share-server.py. Quatre d'entre eux avaient rigoureusement la même
charpente : un journal muet, un _json, un /api/etat, un /api/action. Les
mêmes vingt-cinq lignes, recopiées, avec les mêmes petites divergences —
« ensure_ascii » posé ici et pas là, un « Cache-Control » chez l'un seul.

app.js du volet nommait déjà le risque, à propos d'autre chose :
« la dupliquer ici donnerait deux endroits où un bogue pourrait un jour
raconter deux choses différentes ». Ce n'était plus un risque, c'était fait.

⚠ CE MODULE NE CHANGE AUCUN COMPORTEMENT. C'est une fusion, pas une
réécriture : chaque particularité des quatre copies est devenue un RÉGLAGE
de classe, pas une décision prise ici. Un module qui avait « no-store » le
garde ; celui qui capait son corps à 4 Ko le cape encore. La règle de ce
paquet est de DÉPLACER, parce que les commentaires de ces fichiers
consignent de vrais bogues et qu'une réécriture les perdrait en silence.

DEUX HANDLERS RESTENT DEHORS, ET C'EST DIT : terminal-pro.py (un vrai
serveur de terminal : validation d'origine, jeton, flux) et share-server.py
(réception de fichiers, multipart, chemins). Ce ne sont pas des fenêtres de
réglages ; les fondre ici ne ferait pas UNE classe, ça en ferait une avec
trois métiers. Ils migreront quand — et si — ça a un sens. Le banc les
nomme explicitement : la liste des non-migrés doit RÉTRÉCIR, jamais grossir.
"""

from __future__ import annotations

import http.server
import json
import mimetypes
import socket
import threading
from urllib.parse import parse_qs, urlparse


def port_libre() -> int:
    """Un port que personne n'utilise, sur la boucle locale uniquement.

    Déplacé à l'identique des quatre copies. « 127.0.0.1 » et pas « 0.0.0.0 » :
    cette fenêtre n'est pas un serveur web, et rien de ce qu'elle sert n'a
    à sortir de la machine."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def types_web() -> None:
    """Les types que le serveur de fichiers de Python ne connaît pas toujours.

    Sans ça, un .js servi en « text/plain » n'est pas exécuté par Chromium et
    la page reste nue, sans la moindre erreur visible."""
    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")


class Service(http.server.SimpleHTTPRequestHandler):
    """La charpente commune : /api/etat, /api/action, et des fichiers.

    Ce qu'un module règle en héritant :
        etat_fn      callable rendant l'état. Reçoit la liste des clés
                     demandées si « etat_par_cles » vaut True, rien sinon.
        actions      {nom: callable(arg) -> dict}
        etat_par_cles  True si etat_fn accepte « ?cles=a,b,c »
        apres_action callable() appelée après TOUTE action, quelle qu'en soit
                     l'issue (settings.py y oublie sa mémoire des outils)
        corps_max    taille maximale d'un corps de requête, en octets
        entetes_json entêtes supplémentaires sur les réponses JSON
        json_ascii   False pour laisser passer les accents tels quels
    """

    #  ⚠ etat_fn ET apres_action SE LISENT PAR « type(self) », JAMAIS « self ».
    #  Une fonction rangée dans un attribut de CLASSE est un descripteur :
    #  « self.etat_fn » rendrait une méthode LIÉE, et l'appeler passerait le
    #  handler en premier argument — une TypeError à la première requête, dans
    #  du code qui s'importe parfaitement. « type(self).etat_fn » rend la
    #  fonction telle quelle. C'est la seule subtilité de ce fichier.
    etat_fn = None
    actions: dict = {}
    etat_par_cles = False
    apres_action = None
    corps_max = 1 << 20
    entetes_json: tuple = ()
    json_ascii = False

    # -- journal -----------------------------------------------------------
    def log_message(self, fmt, *args):
        pass  # pas de journal : la fenêtre n'est pas un serveur web

    # -- réponses ----------------------------------------------------------
    def _json(self, code, donnees):
        corps = json.dumps(donnees, ensure_ascii=self.json_ascii).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        for nom, valeur in self.entetes_json:
            self.send_header(nom, valeur)
        self.end_headers()
        self.wfile.write(corps)

    def _requete(self):
        """Le corps JSON d'un POST, ou (None, réponse d'erreur déjà envoyée).

        Le plafond de taille n'est pas décoratif : sans lui, un Content-Length
        annoncé énorme fait lire au serveur autant d'octets qu'on lui en
        envoie. C'est partage.py qui l'avait, seul des quatre ; il vaut
        maintenant pour tout le monde, à la valeur que chacun choisit."""
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            if taille > self.corps_max:
                self._json(400, {"ok": False, "erreur": "requête trop longue"})
                return None
            return json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError, OSError):
            self._json(400, {"ok": False, "erreur": "requête invalide"})
            return None

    # -- routes ------------------------------------------------------------
    def chemin_nu(self) -> str:
        """Le chemin sans sa requête. Trois des quatre copies faisaient
        « self.path.split("?")[0] », la quatrième comparait self.path tel
        quel — et ratait donc « /api/etat?x=1 »."""
        return urlparse(self.path).path

    def do_GET(self):
        if self.chemin_nu() == "/api/etat":
            return self._json(200, self._etat())
        return super().do_GET()

    def _etat(self):
        """L'état, limité aux clés demandées quand le module sait le faire.

        ═══ « ?cles= » VIDE VEUT DIRE « RIEN », PAS « TOUT » ═══
        Le piège vient de settings.py, où il coûtait cher : une section qui
        n'a besoin d'AUCUN collecteur redemandait les quarante, c'est-à-dire
        exactement le contraire de ce qu'elle demandait. On distingue le
        paramètre ABSENT (tout) du paramètre PRÉSENT ET VIDE (rien que le
        gratuit).

        ⚠ « keep_blank_values=True » EST LA MOITIÉ DU CORRECTIF, ET IL A
        MANQUÉ UNE PREMIÈRE FOIS. Par défaut, parse_qs JETTE les valeurs
        vides : « ?cles= » donne {} — donc « cles » n'est pas dans q, donc
        « paramètre absent », donc TOUT. La distinction qu'on vient d'écrire
        ne servait à rien, et le banc qui la gardait la cherchait au GREP :
        il voyait la bonne ligne et disait vert pendant que le serveur
        rendait les cinquante et une clés. C'est un vrai serveur qu'on
        interroge maintenant, sur un vrai port."""
        if type(self).etat_fn is None:
            return {}
        if not self.etat_par_cles:
            return type(self).etat_fn()
        q = parse_qs(urlparse(self.path).query, keep_blank_values=True)
        if "cles" not in q:
            return type(self).etat_fn()
        demande = [c for c in q["cles"][0].split(",") if c]
        return type(self).etat_fn(demande)

    def do_POST(self):
        if not self.chemin_nu().startswith("/api/action"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        requete = self._requete()
        if requete is None:
            return None
        action = self.actions.get(requete.get("action", ""))
        if action is None:
            return self._json(400, {"ok": False, "erreur": "action inconnue"})
        try:
            reponse = action(requete.get("arg"))
        except Exception as e:      # la fenêtre doit survivre à un outil qui casse
            reponse = {"ok": False, "erreur": str(e)}
        apres = type(self).apres_action
        if apres is not None:
            apres()
        return self._json(200, reponse)


def servir(dossier_web, classe, nom_fil: str):
    """Monte le serveur local et rend (serveur, port). Déplacé des quatre mains.

    Le fil est « daemon » : quand la fenêtre se ferme, il ne retient pas le
    processus. ThreadingHTTPServer et pas HTTPServer parce qu'une lecture
    d'état lente bloquerait sinon le chargement de la page elle-même."""
    import functools
    types_web()
    port = port_libre()
    handler = functools.partial(classe, directory=str(dossier_web))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name=nom_fil).start()
    return serveur, port
