"""LexOS Bureau — les gestes de 🎛️ Mes outils (la barre qui descend du haut).

Le son, la capture d'écran, les notifications et la fin de session. Rien
n'est réinventé : chaque geste passe par l'outil de LexOS qui le fait déjà,
pour qu'un réglage n'ait jamais deux vérités.

  · le son        → /usr/lib/lexos/son.py (celui du volet et des Paramètres)
  · la capture    → lexos-capture plein | zone | fenetre
  · les notifs    → le journal de xfce4-notifyd, comme le volet « agenda »
  · la session    → lexos-session (le bouton rouge de la barre du haut)

Comme son.py, ce module ne lève JAMAIS : une machine sans son, sans
xfconf-query ou sans journal de notifications obtient une valeur neutre, et
la barre cache ce qui ne marcherait pas au lieu d'afficher un bouton mort.
"""
from __future__ import annotations

import configparser
import os
import shutil
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path

import applis

ICI = Path(__file__).resolve().parent
#  /usr/lib/lexos, où vit son.py — le dossier parent, dans l'image comme
#  dans le dépôt (les bancs le détournent par LEXOS_LIB).
LIB = Path(os.environ.get("LEXOS_LIB") or ICI.parent)
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
JOURNAL_NOTIFS = CACHE / "xfce4" / "notifyd" / "log"

CAPTURES = ("plein", "zone", "fenetre")
GESTES = ("eteindre", "redemarrer", "veille", "deconnexion", "verrouiller")


# ─── Le son ──────────────────────────────────────────────────────────────
def _son():
    try:
        if str(LIB) not in sys.path:
            sys.path.insert(0, str(LIB))
        import son  # noqa: PLC0415
        return son
    except Exception:           # pas de son.py, ou un moteur absent : pas de son
        return None


def son_etat() -> dict:
    """{"volume": 0-100 ou -1 (indisponible), "muet": bool}."""
    s = _son()
    if s is None:
        return {"volume": -1, "muet": False}
    try:
        return {"volume": int(s.volume()), "muet": bool(s.muet())}
    except Exception:
        return {"volume": -1, "muet": False}


def son(d: dict) -> dict:
    """{"volume": n} règle le niveau (borné 0-100 par son.py lui-même) ;
    {"muet": "toggle" | "on" | "off"} coupe ou rétablit."""
    s = _son()
    if s is None or not isinstance(d, dict):
        return {"ok": False, **son_etat()}
    ok = True
    try:
        if "volume" in d:
            v = d["volume"]
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                return {"ok": False, **son_etat()}
            ok = bool(s.regle_volume(max(0, min(100, int(v)))).get("ok"))
        if "muet" in d:
            ok = bool(s.regle_muet(str(d["muet"])).get("ok")) and ok
    except Exception:
        ok = False
    return {"ok": ok, **son_etat()}


# ─── La capture d'écran ──────────────────────────────────────────────────
def capture(mode: str) -> bool:
    """Lance la capture APRÈS que la barre soit remontée : sans ce délai, la
    photo de l'écran entier montrerait la barre elle-même, et le cadre de
    la zone se dessinerait par-dessus elle."""
    if mode not in CAPTURES or not shutil.which("lexos-capture"):
        return False
    t = threading.Timer(0.8, applis._detache, args=(["lexos-capture", mode],))
    t.daemon = True
    t.start()
    return True


# ─── Les notifications ───────────────────────────────────────────────────
def notifications() -> list[dict]:
    """Les plus récentes d'abord, trente au plus — le même journal que le
    volet « agenda » (volet.py, _notifications), lu aussi défensivement :
    un journal abîmé donne une liste vide, jamais une barre qui ne s'ouvre pas."""
    if not applis._est_fichier(JOURNAL_NOTIFS):
        return []
    lecteur = configparser.RawConfigParser(strict=False, interpolation=None)
    lecteur.optionxform = str
    try:
        lecteur.read(JOURNAL_NOTIFS, encoding="utf-8")
    except (OSError, configparser.Error, UnicodeDecodeError):
        return []
    sortie = []
    for nom in lecteur.sections():
        s = lecteur[nom]
        try:
            quand = datetime.fromtimestamp(int(nom)).strftime("%H:%M")
        except (ValueError, OSError, OverflowError):
            quand = ""
        sortie.append({"app": s.get("app_name", "").strip()[:60], "titre": s.get("summary", "").strip()[:200],
                       "corps": s.get("body", "").strip()[:400], "quand": quand, "cle": nom})
    sortie.sort(key=lambda n: n["cle"], reverse=True)
    return sortie[:30]


def _xfconf(*args: str) -> str | None:
    if not shutil.which("xfconf-query"):
        return None
    try:
        r = subprocess.run(["xfconf-query", "-c", "xfce4-notifyd", *args],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def ne_pas_deranger() -> bool:
    return _xfconf("-p", "/do-not-disturb") == "true"


def notifs(d: dict) -> dict:
    """{"vider": true} vide le journal (en l'ÉCRASANT : xfce4-notifyd garde
    son descripteur ouvert — voir act_notif_vide dans volet.py) ;
    {"dnd": bool} allume ou éteint « Ne pas déranger »."""
    ok = True
    if isinstance(d, dict) and d.get("vider") is True:
        try:
            if applis._est_fichier(JOURNAL_NOTIFS):
                JOURNAL_NOTIFS.write_text("", encoding="utf-8")
        except OSError:
            ok = False
    if isinstance(d, dict) and isinstance(d.get("dnd"), bool):
        ok = _xfconf("-p", "/do-not-disturb", "-n", "-t", "bool", "-s",
                     "true" if d["dnd"] else "false") is not None and ok
    return {"ok": ok, "notifs": notifications(), "dnd": ne_pas_deranger()}


# ─── La fin de session ───────────────────────────────────────────────────
def session(geste: str) -> bool:
    """Veille, fermer la session, verrouiller : lexos-session, comme le bouton
    rouge. Éteindre et redémarrer passent d'abord par l'écran qui s'éteint
    comme une vieille télé (fenetre.py, « L'ARRÊT FAÇON TÉLÉ ») — ils ne
    viennent ici que si la fenêtre ne peut pas le faire."""
    if geste not in GESTES or not shutil.which("lexos-session"):
        return False
    return applis._detache(["lexos-session", geste])
