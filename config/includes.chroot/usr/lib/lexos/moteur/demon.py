"""Le démon résident — ce qui reste chaud entre deux ouvertures.

═══ CE QU'IL FAIT GAGNER, MESURÉ ═══
Chaque « lexos-volet » lançait un processus Python neuf. Chronométré ici :

    import de volet.py .................  438 ms
    import de settings.py ..............   86 ms
    etat("rapides") à froid ............ 1812 ms
    etat("rapides"), cache chaud .......    0 ms
    monter le serveur, trouver le port .. 0 à 5 ms

⚠ UNE DES DEUX RAISONS ATTENDUES N'EN ÉTAIT PAS UNE. On croyait que trouver
un port libre et monter le serveur HTTP coûtaient. Mesuré : zéro à cinq
millisecondes. Ce qui coûte, c'est l'IMPORT (438 ms) et la LECTURE D'ÉTAT
(1812 ms) — deux secondes et quart par ouverture, avant même que Chromium
commence. C'est ça que ce démon retient.

═══ ET LE PRÉCHAUFFAGE, QUI EST LE VRAI TOUR DE MAIN ═══
Un cache qui ne vit que 1,5 s (voir registre.py, et la raison : au-delà il
raconte des histoires) ne sert à rien si la fenêtre met deux secondes à
s'afficher. Alors le lanceur PRÉVIENT le démon avant de lancer la fenêtre :
« j'ouvre les rapides ». La lecture part tout de suite et se fait PENDANT le
démarrage de Chromium, au lieu d'après. Quand la page demande enfin son
état, elle rejoint la lecture en cours (registre.Cache le garantit) au lieu
d'en lancer une deuxième.

Coût quand personne n'ouvre rien : ZÉRO. Pas de minuteur, pas de relecture
périodique — sur un portable, un nmcli toutes les deux secondes toute la
journée se paierait en autonomie.

═══ IL NE DOIT JAMAIS DEVENIR UN POINT DE PANNE ═══
Même règle que lexos-intro : un accélérateur qui tombe ne doit rien
empêcher. Le démon arrêté, absent, ou qui ne répond pas, « lexos-volet » et
« lexos-settings » montent leur propre serveur comme avant. C'est le lanceur
qui s'en assure, et un banc l'éprouve en tuant le démon.
"""

from __future__ import annotations

import http.server
import json
import os
import signal
import sys
import threading
import time
from pathlib import Path

_ICI = Path(__file__).resolve().parent.parent
if str(_ICI) not in sys.path:
    sys.path.insert(0, str(_ICI))

from moteur import service as _service      # noqa: E402


#  ═══ OÙ LE DÉMON DIT OÙ IL EST ═══
#  XDG_RUNTIME_DIR est le bon endroit : il est à l'utilisateur, en 0700, et
#  il est NETTOYÉ à la fermeture de session — donc pas de fichier périmé qui
#  désignerait un port mort au prochain démarrage. Quand il manque (session
#  sans systemd-logind), on se replie sur un dossier à nous, créé en 0700.
def dossier_execution() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    if base and Path(base).is_dir():
        d = Path(base) / "lexos"
    else:
        d = Path(f"/tmp/lexos-{os.getuid()}")
    d.mkdir(parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def fichier_ports() -> Path:
    return dossier_execution() / "moteur.json"


#  Les applications que le démon tient chaudes. Le nom sert de clé dans le
#  fichier de ports ET d'argument au préchauffage.
APPS = ("volet", "settings")


class Demon:
    def __init__(self):
        self.modules: dict = {}
        self.serveurs: dict = {}
        self.ports: dict = {}
        self._arret = threading.Event()

    # -- chargement --------------------------------------------------------
    def charge(self, nom: str):
        """Importe une application et monte son serveur. Rend True si ça a
        marché — un module qui ne s'importe pas ne doit pas emporter les
        autres : le démon sert alors ce qu'il peut."""
        import importlib.util
        fichier = _ICI / ("volet.py" if nom == "volet" else "settings.py")
        try:
            spec = importlib.util.spec_from_file_location("lexos_" + nom, fichier)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            serveur, port = _service.servir(mod.WEB_DIR, self._handler(nom, mod),
                                            nom_fil=f"lexos-moteurd-{nom}")
        except Exception as e:                       # noqa: BLE001
            print(f"lexos-moteurd : {nom} indisponible — {type(e).__name__}: {e}",
                  file=sys.stderr, flush=True)
            return False
        self.modules[nom] = mod
        self.serveurs[nom] = serveur
        self.ports[nom] = port
        return True

    def _handler(self, nom: str, mod):
        """Le Handler de l'application, plus la route de préchauffage.

        On SOUS-CLASSE au lieu de modifier le Handler du module : celui-ci
        sert aussi quand le démon n'est pas là, et lui ajouter une route
        ferait diverger les deux chemins — c'est-à-dire deux endroits où un
        bogue pourrait raconter deux choses différentes."""
        demon = self

        class HandlerDemon(mod.Handler):
            def do_GET(self):
                if self.chemin_nu() == "/api/prechauffe":
                    return demon._prechauffe(nom, mod, self)
                return super().do_GET()

        return HandlerDemon

    # -- préchauffage ------------------------------------------------------
    def _prechauffe(self, nom, mod, requete):
        """« Une fenêtre s'ouvre » — on lance la lecture SANS attendre.

        Rend tout de suite : le lanceur ne doit pas être retenu, c'est tout
        l'intérêt. La lecture se fait dans un fil, pendant que Chromium
        démarre. La page, ensuite, rejoint cette lecture-là."""
        from urllib.parse import parse_qs, urlparse
        q = parse_qs(urlparse(requete.path).query)
        quoi = (q.get("quoi") or [""])[0]
        #  Le volet sert TROIS pages (agenda, météo, rapides) et son Handler
        #  garde laquelle dans un attribut de classe. Un seul volet peut être
        #  ouvert à la fois — le lanceur ferme l'autre — donc cet attribut
        #  décrit bien l'unique volet en cours.
        if nom == "volet" and quoi in getattr(mod, "VOLETS", ()):
            mod.Handler.quoi = quoi

        #  ═══ ON NE PRÉCHAUFFE QUE LE VOLET, ET C'EST DÉLIBÉRÉ ═══
        #  Le volet s'ouvre vingt fois par jour et sa page est UNE page : le
        #  nom du volet suffit à savoir quoi lire. Les Paramètres, eux,
        #  s'ouvrent trois fois par semaine et ne lisent que les clés de la
        #  section affichée — et cette table-là (CLES_SECTION) vit dans la
        #  PAGE. La recopier ici en ferait un deuxième endroit à tenir à
        #  jour, donc un deuxième endroit où un oubli ferait lire trop ou
        #  trop peu. Préchauffer « tout l'état » à la place serait pire
        #  encore : quarante sous-processus lancés pour une section qui en
        #  demande trois.
        #  Ce que les Paramètres gagnent quand même : l'import (86 ms) et un
        #  cache déjà chaud d'une ouverture à l'autre.
        if nom != "volet":
            return requete._json(200, {"ok": True, "prechauffe": None,
                                       "motif": "seul le volet se préchauffe"})

        def lire():
            try:
                mod.etat(quoi)
            except Exception:                        # noqa: BLE001
                pass                                  # préchauffer ne doit rien casser

        threading.Thread(target=lire, daemon=True,
                         name=f"lexos-prechauffe-{nom}").start()
        return requete._json(200, {"ok": True, "prechauffe": quoi})

    # -- vie du démon ------------------------------------------------------
    def publie(self):
        f = fichier_ports()
        tmp = f.with_suffix(".tmp")
        tmp.write_text(json.dumps({"pid": os.getpid(), "ports": self.ports}),
                       encoding="utf-8")
        os.chmod(tmp, 0o600)
        #  Remplacement ATOMIQUE : un lanceur qui lit pendant qu'on écrit ne
        #  doit jamais tomber sur un fichier à moitié écrit.
        tmp.replace(f)

    def arrete(self, *_):
        self._arret.set()

    def tourne(self):
        charges = [nom for nom in APPS if self.charge(nom)]
        if not charges:
            print("lexos-moteurd : aucune application n'a pu être chargée",
                  file=sys.stderr, flush=True)
            return 1
        self.publie()
        print(f"lexos-moteurd : {' '.join(charges)} — "
              + " ".join(f"{n}:{p}" for n, p in self.ports.items()), flush=True)
        signal.signal(signal.SIGTERM, self.arrete)
        signal.signal(signal.SIGINT, self.arrete)
        self._arret.wait()
        #  On efface NOTRE fichier, et seulement s'il est encore à nous : un
        #  démon relancé entre-temps aurait écrit le sien, et l'effacer
        #  laisserait les lanceurs sans adresse.
        try:
            f = fichier_ports()
            if json.loads(f.read_text(encoding="utf-8")).get("pid") == os.getpid():
                f.unlink()
        except (OSError, ValueError):
            pass
        for s in self.serveurs.values():
            s.shutdown()
        return 0


def main() -> int:
    return Demon().tourne()


if __name__ == "__main__":
    sys.exit(main())
