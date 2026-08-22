#!/usr/bin/env python3
"""
LexOS — IA locale : un modèle de langage sur la machine, sans nuage.

Même patron que les Paramètres (settings.py) et le volet (volet.py) : une
fenêtre Qt affiche une page servie en local, et le pont Python exécute les
vraies commandes derrière une LISTE BLANCHE fermée. La page ne peut demander
que ce qui est écrit ici.

CE QUE CE PANNEAU REFUSE DE FAIRE, ET POURQUOI.

  · Il n'embarque aucun modèle. Un modèle pèse 4 à 5 Go, sa licence n'est
    souvent PAS libre, et celui de 2026 sera vieux en 2027. LexOS livre le
    moteur, jamais les poids — et rend l'ajout de n'importe lequel facile.
    C'est la même chose que « tous les modèles », sans les 40 Go ni le
    problème de licence.

  · Il ne dit jamais « GPU non disponible ». Ce message ne sert à personne :
    « pas de carte », « carte là mais pilote absent » et « pilote là mais
    backend processeur » sont trois pannes différentes avec trois solutions
    différentes. On dit LAQUELLE.

  · Il ne calcule pas le verdict « est-ce que ça rentre ? » depuis le
    catalogue. Le catalogue dit ce que le modèle demande ; c'est CETTE
    machine qui dit ce qu'elle a. Un verdict écrit dans le catalogue serait
    faux pour tout le monde sauf celui qui l'a écrit.

  · Il n'installe rien sans un clic. Ni Ollama, ni un backend, ni un modèle.
"""
import functools
import http.server
import json
import mimetypes
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

APP_NAME = "IA locale — LexOS"
BASE_DIR = Path(os.environ.get("LEXOS_IA_DIR", "/usr/share/lexos/ia"))
WEB_DIR = BASE_DIR / "web"
CATALOGUE_SECOURS = BASE_DIR / "catalogue-secours.json"

#  Racines réglables : elles n'existent pas en usage réel, elles ne servent
#  qu'au banc d'essai, qui donne à ce fichier une fausse machine.
ETC_DIR = Path(os.environ.get("LEXOS_ETC", "/etc"))
#  /sys/module ne contient QUE les modules chargés. Réglable pour la même
#  raison que les autres racines : sans ça, le banc d'essai ne peut pas
#  reproduire « carte là, pilote absent » — et c'est justement la panne dont
#  le diagnostic compte le plus.
MODULE_DIR = Path(os.environ.get("LEXOS_SYS_MODULE", "/sys/module"))
CACHE_DIR = Path(os.environ.get("LEXOS_IA_CACHE", "/var/cache/lexos-ia"))
CONF = Path(os.environ.get("LEXOS_CONF",
                           str(Path.home() / ".config" / "lexos"))) / "ia-locale.json"

#  Le catalogue vit EN LIGNE, pour la même raison que la logithèque Flatpak :
#  ce qui périme ne doit pas être gravé dans l'image. Une copie de secours
#  voyage quand même dans l'ISO, pour que le panneau ne soit jamais vide.
CATALOGUE_URL = os.environ.get(
    "LEXOS_IA_CATALOGUE",
    "https://raw.githubusercontent.com/alexmarceauprevost812-source/"
    "lexOS-2.0/main/catalogue-ia.json")
CATALOGUE_TTL = 86400  # une fois par jour, pas plus

OLLAMA_HOTE = "127.0.0.1:11434"


# =============================================================================
#  Outils de base
# =============================================================================

def _sortie(argv, *, timeout=15):
    """La sortie d'une commande, ou une chaîne vide. Ne lève jamais."""
    if shutil.which(argv[0]) is None:
        return ""
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.stdout or ""
    except (subprocess.SubprocessError, OSError):
        return ""


def _run(argv, *, detach=False, timeout=120):
    if shutil.which(argv[0]) is None:
        return {"ok": False, "erreur": f"Outil absent : {argv[0]}"}
    if detach:
        subprocess.Popen(argv, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True}
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": r.returncode == 0,
            "erreur": (r.stderr or "").strip()[:400] if r.returncode else ""}


def _terminal(titre, commande):
    """Une commande qui pose des questions a besoin d'une fenêtre où répondre."""
    for term, gabarit in (("xfce4-terminal", ["--title", titre, "-e", commande]),
                          ("x-terminal-emulator", ["-e", commande])):
        if shutil.which(term):
            return _run([term] + gabarit, detach=True)
    return {"ok": False, "erreur": "aucun terminal trouvé"}


def _reglages():
    try:
        return json.loads(CONF.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _ecrire_reglages(d):
    CONF.parent.mkdir(parents=True, exist_ok=True)
    CONF.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")


def dossier_modeles():
    """Où vivent les modèles.

    LE RÉGLAGE LE PLUS IMPORTANT DU PANNEAU. Un double démarrage laisse
    parfois 40 Go de libre en tout, et un modèle en pèse 5 : il faut pouvoir
    pointer vers un disque externe ou la partition Windows (ntfs-3g est déjà
    au socle). Par défaut on va dans /var/lib/lexos-ia s'il est accessible en
    écriture, sinon dans le dossier de l'utilisateur — jamais d'échec parce
    qu'un dossier système n'est pas à lui.
    """
    choisi = _reglages().get("dossier")
    if choisi:
        return Path(choisi)
    systeme = Path("/var/lib/lexos-ia/modeles")
    if os.access(systeme.parent if systeme.parent.exists() else "/var/lib", os.W_OK):
        return systeme
    return Path.home() / ".local" / "share" / "lexos-ia" / "modeles"


# =============================================================================
#  Écran 1 — le diagnostic : dire LEQUEL des trois problèmes on a
# =============================================================================

def _carte():
    """La carte graphique : marque, modèle, mémoire.

    Trois sources, de la plus précise à la plus générale. nvidia-smi donne la
    VRAM au mégaoctet près ; vulkaninfo la donne pour toutes les marques ;
    lspci ne donne que le nom, mais il est toujours là.
    """
    info = {"presente": False, "nom": "", "marque": "", "vram_go": 0.0,
            "source": ""}

    #  lspci : le nom, quoi qu'il arrive.
    for ligne in _sortie(["lspci"]).splitlines():
        if re.search(r"(VGA compatible controller|3D controller|Display controller)",
                     ligne):
            nom = ligne.split(":", 2)[-1].strip()
            info["presente"] = True
            info["nom"] = nom
            bas = nom.lower()
            if "nvidia" in bas:
                info["marque"] = "nvidia"
            elif "amd" in bas or "ati " in bas or "radeon" in bas:
                info["marque"] = "amd"
            elif "intel" in bas:
                info["marque"] = "intel"
            #  Une carte dédiée l'emporte sur le circuit intégré : sur un
            #  portable à deux cartes, c'est elle qui fera le travail.
            if info["marque"] in ("nvidia", "amd"):
                break

    #  nvidia-smi : la VRAM exacte, si NVIDIA.
    smi = _sortie(["nvidia-smi", "--query-gpu=name,memory.total",
                   "--format=csv,noheader,nounits"])
    if smi.strip():
        premier = smi.strip().splitlines()[0]
        morceaux = [m.strip() for m in premier.split(",")]
        if len(morceaux) >= 2:
            info["presente"] = True
            info["marque"] = "nvidia"
            info["nom"] = morceaux[0]
            try:
                info["vram_go"] = round(float(morceaux[1]) / 1024.0, 1)
                info["source"] = "nvidia-smi"
            except ValueError:
                pass

    #  vulkaninfo : la VRAM pour AMD et Intel aussi.
    if not info["vram_go"]:
        vk = _sortie(["vulkaninfo", "--summary"], timeout=20)
        octets = [int(m) for m in re.findall(r"size\s*=\s*(\d{9,})", vk)]
        if octets:
            info["vram_go"] = round(max(octets) / (1024 ** 3), 1)
            info["source"] = "vulkaninfo"

    return info


def _pilote(marque):
    """Le pilote est-il CHARGÉ ? Pas « installé » : chargé."""
    modules = {"nvidia": ["nvidia"], "amd": ["amdgpu", "radeon"],
               "intel": ["i915", "xe"]}.get(marque, [])
    #  /sys/module ne contient QUE les modules chargés : c'est la réponse à
    #  « est-ce qu'il pilote la carte en ce moment », pas à « est-ce que le
    #  paquet est installé ». Les deux questions ont l'air pareilles et ne le
    #  sont pas — c'est la deuxième des trois pannes.
    for m in modules:
        if (MODULE_DIR / m).exists():
            return {"charge": True, "nom": m}
    return {"charge": False, "nom": ""}


def _backend():
    """Quel backend le moteur utilisera VRAIMENT.

    Le rapport de construction (/etc/lexos/ia-moteur) dit ce qui a été mis
    dans l'image. On le recoupe avec ce que la machine montre aujourd'hui :
    un backend Vulkan ne sert à rien si le pilote ne charge pas, et
    l'utilisateur a pu en ajouter un après coup.
    """
    rapport = {}
    fichier = ETC_DIR / "lexos" / "ia-moteur"
    try:
        for ligne in fichier.read_text(encoding="utf-8").splitlines():
            if "=" in ligne:
                cle, _, val = ligne.partition("=")
                rapport[cle.strip()] = val.strip()
    except OSError:
        pass

    vulkan = bool(_sortie(["vulkaninfo", "--summary"], timeout=20).strip())
    nom = rapport.get("backend", "")
    if nom in ("", "aucun"):
        actif = "processeur"
    elif "vulkan" in nom and not vulkan:
        #  Le paquet est là mais Vulkan ne répond pas : presque toujours un
        #  pilote qui ne charge pas. Le dire plutôt que de promettre le GPU.
        actif = "processeur"
    else:
        actif = "vulkan" if "vulkan" in nom else "gpu"
    return {"paquet": nom, "actif": actif, "vulkan_repond": vulkan,
            "moteur": rapport.get("moteur", "")}


def _moteurs():
    return {
        "llama": bool(shutil.which("llama-cli") or shutil.which("llama-server")),
        "ollama": bool(shutil.which("ollama")),
        "ollama_actif": _ollama_repond(),
    }


def _ollama_repond():
    try:
        with urllib.request.urlopen(f"http://{OLLAMA_HOTE}/api/tags", timeout=2):
            return True
    except (urllib.error.URLError, OSError, ValueError):
        return False


def _espace():
    d = dossier_modeles()
    sonde = d
    while not sonde.exists() and sonde != sonde.parent:
        sonde = sonde.parent
    try:
        u = shutil.disk_usage(sonde)
        return {"dossier": str(d), "libre_go": round(u.free / (1024 ** 3), 1),
                "total_go": round(u.total / (1024 ** 3), 1)}
    except OSError:
        return {"dossier": str(d), "libre_go": 0.0, "total_go": 0.0}


def _ram_go():
    try:
        for ligne in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            if ligne.startswith("MemAvailable:"):
                return round(int(ligne.split()[1]) / (1024 ** 2), 1)
    except (OSError, ValueError, IndexError):
        pass
    return 0.0


def _diagnostic():
    """Les trois pannes possibles, nommées.

    C'est la règle qui vient de l'écran noir de la RTX 5060 : on nous a servi
    « GPU non disponible » pendant des jours, alors que la vraie phrase était
    « le pilote charge, mais il n'y a pas de backend ». Trois situations,
    trois solutions, trois messages.
    """
    carte = _carte()
    pil = _pilote(carte["marque"])
    back = _backend()

    if not carte["presente"]:
        cas = "sans-carte"
        titre = "Aucune carte graphique dédiée"
        detail = ("Le moteur tournera sur le processeur. C'est plus lent, "
                  "mais ça marche — et rien n'est cassé.")
    elif not pil["charge"]:
        cas = "sans-pilote"
        titre = "Carte présente, pilote non chargé"
        detail = (f"{carte['nom']} est là, mais aucun pilote ne la pilote. "
                  "Sans lui, la carte ne peut rien faire pour l'IA.")
    elif back["actif"] == "processeur" and back["paquet"] not in ("", "aucun"):
        #  Le paquet est bien là, mais Vulkan ne répond pas. Dire « il manque
        #  le backend » enverrait réinstaller ce qui est déjà installé — on
        #  perdrait une soirée sur le mauvais problème.
        cas = "backend-muet"
        titre = "Le backend est installé, mais il ne répond pas"
        detail = (f"{back['paquet']} est là, et pourtant Vulkan ne répond pas. "
                  "C'est presque toujours le pilote graphique : il est chargé, "
                  "mais sans sa partie Vulkan.")
    elif back["actif"] == "processeur":
        cas = "sans-backend"
        titre = "Carte et pilote là, mais backend processeur"
        detail = ("C'est la panne qui ne se voit pas : tout répond, dix fois "
                  "trop lentement. Il manque le backend GPU du moteur.")
    else:
        cas = "ok"
        titre = "La carte graphique sera utilisée"
        detail = f"Backend {back['paquet'] or back['actif']} — c'est ce qu'on veut."

    return {"cas": cas, "titre": titre, "detail": detail,
            "carte": carte, "pilote": pil, "backend": back}


# =============================================================================
#  Le catalogue — en ligne, en cache, et de secours
# =============================================================================

def _catalogue_charge(forcer=False):
    cache = CACHE_DIR / "catalogue.json"

    #  Cache frais : on s'en contente. Pas une requête réseau à chaque
    #  ouverture de fenêtre — au plus une par jour, comme le cache de paquets.
    try:
        if (cache.exists() and not forcer
                and (time.time() - cache.stat().st_mtime) < CATALOGUE_TTL):
            return json.loads(cache.read_text(encoding="utf-8")), "cache"
    except (OSError, ValueError):
        pass

    try:
        with urllib.request.urlopen(CATALOGUE_URL, timeout=10) as r:
            donnees = json.loads(r.read().decode("utf-8"))
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(donnees, ensure_ascii=False),
                             encoding="utf-8")
        except OSError:
            pass
        return donnees, "en ligne"
    except (urllib.error.URLError, OSError, ValueError):
        pass

    try:
        if cache.exists():
            return json.loads(cache.read_text(encoding="utf-8")), "cache (hors ligne)"
    except (OSError, ValueError):
        pass
    try:
        return json.loads(CATALOGUE_SECOURS.read_text(encoding="utf-8")), "secours"
    except (OSError, ValueError):
        return {"modeles": []}, "vide"


def _verdict(modele, vram_go, ram_go):
    """Est-ce que ça rentre ? Calculé ICI, sur CETTE machine.

    Trois chiffres qu'on confond tout le temps : un modèle « 8B » ne pèse pas
    8 Go. En Q4_K_M il occupe ~4,5 Go sur le disque et ~6-7 Go en mémoire vive
    graphique avec le contexte. Le catalogue donne les deux ; la machine donne
    le troisième.
    """
    besoin = float(modele.get("vram_go") or 0)
    taille = float(modele.get("taille_go") or 0)
    if vram_go and besoin and besoin <= vram_go - 1:
        return {"code": "ok", "texte": "entre au complet — rapide"}
    if ram_go and taille and taille <= ram_go:
        return {"code": "limite",
                "texte": "déborde sur le processeur — ça marche, tu vas le sentir"}
    return {"code": "non", "texte": "trop gros pour cette machine"}


def _modeles_installes():
    """Ce qui est déjà là, des deux moteurs."""
    noms = []
    for f in sorted(dossier_modeles().glob("*.gguf")):
        noms.append({"nom": f.name, "moteur": "llama.cpp",
                     "taille_go": round(f.stat().st_size / (1024 ** 3), 1)})
    if _ollama_repond():
        try:
            with urllib.request.urlopen(f"http://{OLLAMA_HOTE}/api/tags",
                                        timeout=3) as r:
                for m in json.loads(r.read().decode("utf-8")).get("models", []):
                    noms.append({"nom": m.get("name", ""), "moteur": "ollama",
                                 "taille_go": round(
                                     float(m.get("size", 0)) / (1024 ** 3), 1)})
        except (urllib.error.URLError, OSError, ValueError):
            pass
    return noms


# =============================================================================
#  L'état complet, tel que la page le lit
# =============================================================================

def etat():
    diag = _diagnostic()
    esp = _espace()
    ram = _ram_go()
    cat, origine = _catalogue_charge()
    vram = diag["carte"]["vram_go"]
    modeles = []
    for m in cat.get("modeles", []):
        e = dict(m)
        e["verdict"] = _verdict(m, vram, ram)
        modeles.append(e)
    #  Les modèles vraiment libres d'abord — informer, pas décider à la place
    #  des gens : rien n'est caché, c'est l'ordre qui parle.
    modeles.sort(key=lambda m: (not m.get("libre"), m.get("taille_go", 0)))

    reg = _reglages()
    return {
        "diagnostic": diag,
        "moteurs": _moteurs(),
        "espace": esp,
        "ram_go": ram,
        "catalogue": {"origine": origine, "modeles": modeles,
                      "mis_a_jour": cat.get("mis_a_jour", "")},
        "installes": _modeles_installes(),
        "reglages": {"dossier": esp["dossier"],
                     "contexte": int(reg.get("contexte", 8192)),
                     "modele": reg.get("modele", ""),
                     "libres_seulement": bool(reg.get("libres_seulement", False))},
    }


# =============================================================================
#  Actions — la liste blanche
# =============================================================================

def act_ouvrir(arg):
    """Ouvrir un outil LexOS voisin, jamais une commande quelconque."""
    cibles = {"ia": ["lexos", "ia"], "medecin": ["lexos", "medecin"],
              "journal": ["lexos", "journal"]}
    if arg not in cibles:
        return {"ok": False, "erreur": "cible inconnue"}
    return _terminal(f"LexOS — {arg}", " ".join(cibles[arg]))


def act_installer_ollama(arg):
    """Ollama n'est pas dans Debian et n'y sera probablement pas.

    Traité comme rustup : jamais dans l'ISO, proposé ici, installé par son
    script officiel — dans un TERMINAL, où l'on voit ce qui se passe et où
    sudo peut demander le mot de passe. Une installation silencieuse d'un
    script venu du réseau, c'est exactement ce qu'on ne fait pas.
    """
    del arg
    if shutil.which("ollama"):
        return {"ok": True, "message": "Ollama est déjà installé."}
    return _terminal("Installer Ollama — LexOS", "lexos ia setup")


def act_installer_backend(arg):
    """Ajouter le backend GPU qui manque, après coup."""
    if arg not in ("vulkan", "cuda"):
        return {"ok": False, "erreur": "backend inattendu"}
    return _terminal(f"Ajouter le backend {arg} — LexOS",
                     f"lexos install ia-backend-{arg}")


def act_telecharger(arg):
    """Télécharger un modèle — après avoir vérifié la place.

    L'ARGUMENT EST VÉRIFIÉ CONTRE LE CATALOGUE, pas seulement contre un
    motif : on ne télécharge que ce que le catalogue nomme, ou une référence
    tapée à la main dont chaque caractère est contrôlé. Et subprocess reçoit
    une liste — même une référence tordue ne peut pas devenir une commande.
    """
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    ref = str(arg.get("ref", "")).strip()
    moteur = arg.get("moteur", "")
    if moteur not in ("ollama", "llama"):
        return {"ok": False, "erreur": "moteur inattendu"}
    if not ref or len(ref) > 200:
        return {"ok": False, "erreur": "il faut une référence de modèle"}
    if not all(c.isalnum() or c in "._:-/" for c in ref):
        return {"ok": False, "erreur": "référence invalide"}

    #  Vérifier la place AVANT. Un disque plein à 80 % du téléchargement
    #  laisse un fichier à moitié écrit et une soirée perdue.
    esp = _espace()
    besoin = float(arg.get("taille_go") or 0)
    if besoin and esp["libre_go"] and esp["libre_go"] < besoin + 2:
        return {"ok": False,
                "erreur": (f"Il reste {esp['libre_go']} Go dans {esp['dossier']} "
                           f"et il en faut {besoin} + 2 de marge.")}

    if moteur == "ollama":
        if not shutil.which("ollama"):
            return {"ok": False, "erreur": "Ollama n'est pas installé"}
        return _terminal(f"Télécharger {ref} — LexOS", f"ollama pull {ref}")
    if not shutil.which("llama-cli"):
        return {"ok": False, "erreur": "llama.cpp n'est pas installé"}
    return _terminal(f"Télécharger {ref} — LexOS",
                     f"llama-cli -hf {ref} --no-conversation -p bonjour -n 1")


def act_dossier(arg):
    """Changer le dossier des modèles.

    ⚠ IL Y A DEUX ENDROITS À CHANGER, PAS UN. Si on ne passe pas aussi
    OLLAMA_MODELS, Ollama continue de remplir ~/.ollama et l'utilisateur se
    retrouve avec 10 Go disparus sans comprendre où. On écrit donc les deux.
    """
    chemin = str(arg or "").strip()
    if not chemin or len(chemin) > 400 or "\n" in chemin or "\0" in chemin:
        return {"ok": False, "erreur": "chemin invalide"}
    d = Path(chemin).expanduser()
    try:
        d.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        return {"ok": False, "erreur": f"dossier impossible à créer : {e}"}
    if not os.access(d, os.W_OK):
        return {"ok": False, "erreur": "dossier non accessible en écriture"}

    reg = _reglages()
    reg["dossier"] = str(d)
    try:
        _ecrire_reglages(reg)
    except OSError as e:
        return {"ok": False, "erreur": str(e)}

    #  Le second endroit : Ollama, qui ne lit pas nos réglages.
    env = Path.home() / ".config" / "environment.d"
    try:
        env.mkdir(parents=True, exist_ok=True)
        (env / "lexos-ia.conf").write_text(
            f"OLLAMA_MODELS={d}\n", encoding="utf-8")
    except OSError:
        return {"ok": True,
                "message": "Dossier changé. Ollama, lui, gardera l'ancien : "
                           "son réglage n'a pas pu être écrit."}
    return {"ok": True,
            "message": "Dossier changé — pour Ollama aussi, à la prochaine session."}


def act_contexte(arg):
    """La taille de contexte. Monter coûte de la mémoire graphique."""
    valeurs = {"2048", "4096", "8192", "16384", "32768"}
    if str(arg) not in valeurs:
        return {"ok": False, "erreur": "valeur inattendue"}
    reg = _reglages()
    reg["contexte"] = int(arg)
    try:
        _ecrire_reglages(reg)
    except OSError as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": True}


def act_modele(arg):
    """Choisir le modèle courant parmi CEUX QUI SONT LÀ."""
    connus = {m["nom"] for m in _modeles_installes()}
    if arg not in connus:
        return {"ok": False, "erreur": "ce modèle n'est pas installé"}
    reg = _reglages()
    reg["modele"] = arg
    try:
        _ecrire_reglages(reg)
    except OSError as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": True}


def act_libres(arg):
    """N'afficher que les modèles vraiment libres. Décoché par défaut :
    informer, pas décider à la place des gens."""
    if arg not in (True, False, "on", "off"):
        return {"ok": False, "erreur": "valeur inattendue"}
    reg = _reglages()
    reg["libres_seulement"] = arg in (True, "on")
    try:
        _ecrire_reglages(reg)
    except OSError as e:
        return {"ok": False, "erreur": str(e)}
    return {"ok": True}


def act_decharger(arg):
    """Rendre la mémoire graphique. Utile quand on veut jouer ou compiler."""
    del arg
    if _ollama_repond():
        try:
            req = urllib.request.Request(
                f"http://{OLLAMA_HOTE}/api/generate",
                data=json.dumps({"model": _reglages().get("modele", ""),
                                 "keep_alive": 0}).encode(),
                headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=10).read()
            return {"ok": True}
        except (urllib.error.URLError, OSError, ValueError) as e:
            return {"ok": False, "erreur": str(e)}
    return {"ok": True, "message": "Rien n'était chargé."}


def act_machine(arg):
    """Les infos de la machine, à coller dans une question.

    C'est le pont avec lexos-medecin et lexos-journal : « voici mon erreur,
    qu'est-ce que ça veut dire ». Tout reste sur la machine — c'est justement
    l'intérêt d'un modèle local.
    """
    del arg
    txt = _sortie(["inxi", "-b"], timeout=20)
    if not txt.strip():
        txt = (_sortie(["uname", "-a"]) + "\n"
               + _sortie(["lsb_release", "-ds"]) + "\n"
               + _sortie(["lspci"]))
    return {"ok": True, "texte": txt.strip()[:4000]}


ACTIONS = {
    "ouvrir": act_ouvrir,
    "installer-ollama": act_installer_ollama,
    "installer-backend": act_installer_backend,
    "telecharger": act_telecharger,
    "dossier": act_dossier,
    "contexte": act_contexte,
    "modele": act_modele,
    "libres": act_libres,
    "decharger": act_decharger,
    "machine": act_machine,
}


# =============================================================================
#  La discussion — en flux, parce qu'attendre un pavé complet est pénible
# =============================================================================

def _flux_ollama(question, modele, ecrire):
    corps = json.dumps({
        "model": modele, "prompt": question, "stream": True,
        "system": "Tu es l'assistant de LexOS. Réponds en français, "
                  "clairement et brièvement.",
    }).encode()
    req = urllib.request.Request(f"http://{OLLAMA_HOTE}/api/generate",
                                 data=corps,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        for ligne in r:
            if not ligne.strip():
                continue
            try:
                bout = json.loads(ligne.decode("utf-8"))
            except ValueError:
                continue
            if bout.get("response"):
                ecrire(bout["response"])
            if bout.get("done"):
                return


def _flux_llama(question, ecrire):
    """llama-cli en direct : une question, une réponse, pas de serveur à tenir."""
    modeles = sorted(dossier_modeles().glob("*.gguf"))
    if not modeles:
        ecrire("Aucun modèle n'est installé. Va dans « Modèles » pour en "
               "télécharger un.")
        return
    reg = _reglages()

    #  Le modèle CHOISI, pas le premier par ordre alphabétique. act_modele a
    #  pris soin d'enregistrer reg["modele"] ; s'en tenir à modeles[0] écrasait
    #  ce choix en silence dès qu'il y avait deux .gguf dans le dossier.
    #  Le réglage peut aussi nommer un modèle Ollama (aucun fichier ici) ou un
    #  .gguf effacé depuis : on retombe sur le premier, et on le DIT — répondre
    #  avec un autre modèle sans prévenir, c'est se demander longtemps pourquoi
    #  la réponse ne ressemble pas à ce qu'on attendait.
    choisi = reg.get("modele", "")
    modele = next((m for m in modeles if m.name == choisi), None)
    if modele is None:
        modele = modeles[0]
        if choisi.endswith(".gguf"):
            ecrire(f"[« {choisi} » est introuvable — réponse avec "
                   f"{modele.name}]\n")

    argv = ["llama-cli", "-m", str(modele),
            "-c", str(int(reg.get("contexte", 8192))),
            "--no-conversation", "-no-cnv", "-p", question]
    try:
        p = subprocess.Popen(argv, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except (OSError, subprocess.SubprocessError) as e:
        ecrire(f"Le moteur n'a pas démarré : {e}")
        return
    for ligne in p.stdout:
        ecrire(ligne)
    p.wait(timeout=10)


# =============================================================================
#  Le pont HTTP
# =============================================================================

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path == "/api/etat":
            return self._json(200, etat())
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/discussion"):
            return self._discussion()
        if not self.path.startswith("/api/action"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        action = ACTIONS.get(requete.get("action", ""))
        if action is None:
            return self._json(400, {"ok": False, "erreur": "action inconnue"})
        try:
            return self._json(200, action(requete.get("arg")))
        except Exception as e:                      # noqa: BLE001
            return self._json(200, {"ok": False, "erreur": str(e)})

    def _discussion(self):
        """La réponse arrive mot par mot, pas d'un bloc.

        Un modèle local met dix à trente secondes à finir une réponse. Servie
        d'un seul coup à la fin, la fenêtre a l'air plantée pendant tout ce
        temps — et on la ferme avant la réponse.
        """
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        question = str(requete.get("question", "")).strip()
        if not question or len(question) > 8000:
            return self._json(400, {"ok": False, "erreur": "question vide"})

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

        def ecrire(texte):
            try:
                self.wfile.write(texte.encode("utf-8"))
                self.wfile.flush()
            except (BrokenPipeError, OSError):
                raise

        modele = _reglages().get("modele", "")
        try:
            if _ollama_repond() and modele:
                _flux_ollama(question, modele, ecrire)
            elif shutil.which("llama-cli"):
                _flux_llama(question, ecrire)
            elif _ollama_repond():
                _flux_ollama(question, "", ecrire)
            else:
                ecrire("Aucun moteur n'est prêt. Installe Ollama, ou "
                       "télécharge un modèle pour llama.cpp.")
        except (BrokenPipeError, OSError):
            return
        except Exception as e:                      # noqa: BLE001
            try:
                ecrire(f"\n[erreur : {e}]")
            except OSError:
                pass


def _port_libre():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def main():
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")

    if len(sys.argv) > 1 and sys.argv[1] in ("--etat", "etat"):
        print(json.dumps(etat(), ensure_ascii=False, indent=2))
        return

    port = _port_libre()
    handler = functools.partial(Handler, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-ia-http").start()

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)
    fenetre.resize(1000, 720)
    icone = "/usr/share/icons/hicolor/128x128/apps/lexos-ia.png"
    if Path(icone).exists():
        fenetre.setWindowIcon(QIcon(icone))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)
    vue.load(QUrl(f"http://127.0.0.1:{port}/index.html"))
    fenetre.show()

    code = app.exec()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
