"""Les applications ouvertes, pour le dock du bureau démon.

ALEX (2026-11-01) : « ajouter dans le new dock les applications ouvertes ».
Comme une barre des tâches : une tuile par fenêtre ouverte, sous les
lanceurs du dock. Un clic la ramène devant (même sur un autre bureau
virtuel) ; un clic sur celle qui est déjà devant la réduit.

Tout passe par python3-xlib (déjà dans l'ISO pour la fenêtre du bureau) et
les propriétés EWMH que xfwm4 tient à jour : _NET_CLIENT_LIST (les
fenêtres, dans l'ordre d'ouverture), _NET_ACTIVE_WINDOW, _NET_WM_STATE.
Un Display NEUF par appel, comme gestes.py : le serveur répond depuis ses
propres fils, et une connexion Xlib partagée entre fils n'est pas sûre.
"""
from __future__ import annotations

import os
from pathlib import Path

import applis

#  Les fenêtres qui ne sont pas « une appli ouverte » : le bureau lui-même,
#  les barres, les menus, les bulles. Celles qui demandent à rester hors de
#  la barre des tâches (_NET_WM_STATE_SKIP_TASKBAR) restent aussi dehors.
TYPES_EXCLUS = {
    "_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_DOCK", "_NET_WM_WINDOW_TYPE_TOOLBAR",
    "_NET_WM_WINDOW_TYPE_MENU", "_NET_WM_WINDOW_TYPE_SPLASH", "_NET_WM_WINDOW_TYPE_UTILITY",
    "_NET_WM_WINDOW_TYPE_NOTIFICATION", "_NET_WM_WINDOW_TYPE_TOOLTIP",
    "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", "_NET_WM_WINDOW_TYPE_POPUP_MENU",
}
MAX_FENETRES = 8

#  classe de fenêtre -> fichier d'icône (ou None), trouvé une fois.
_ICONES: dict[str, Path | None] = {}


def _display():
    try:
        from Xlib import display  # noqa: PLC0415
        return display.Display()
    except Exception:
        return None


def _fermer(d) -> None:
    try:
        d.close()
    except Exception:
        pass


def _icone_classe(classes: tuple[str, ...]) -> Path | None:
    """L'icône d'une appli à partir de sa classe de fenêtre (WM_CLASS) : le
    .desktop du même nom, ou celui dont StartupWMClass correspond, puis son
    Icon= ; à défaut, une icône du thème qui porte le nom de la classe."""
    cle = "|".join(classes)
    if cle in _ICONES:
        return _ICONES[cle]
    trouve: Path | None = None
    noms = [c for c in classes if c]
    candidats = []
    for c in noms:
        candidats += [c, c.lower(), c.lower().replace(" ", "-")]
    for c in candidats:
        p = applis.trouver_desktop(c)
        info = applis.lire_desktop(p) if p else None
        if info and info["icone"]:
            trouve = applis.chemin_icone(info["icone"])
            if trouve:
                break
    if trouve is None:
        voulus = {c.lower() for c in noms}
        for dossier in applis.dossiers_applications():
            try:
                fichiers = list(dossier.glob("*.desktop"))
            except OSError:
                continue
            for f in fichiers:
                try:
                    texte = f.read_text("utf-8", errors="ignore")
                except OSError:
                    continue
                for ligne in texte.splitlines():
                    if ligne.startswith("StartupWMClass=") and ligne.split("=", 1)[1].strip().lower() in voulus:
                        info = applis.lire_desktop(f)
                        trouve = applis.chemin_icone(info["icone"]) if info else None
                        break
                if trouve:
                    break
            if trouve:
                break
    if trouve is None:
        for c in candidats:
            trouve = applis.chemin_icone(c)
            if trouve:
                break
    _ICONES[cle] = trouve
    return trouve


def _texte(d, fen, nom: str) -> str:
    try:
        p = fen.get_full_property(d.intern_atom(nom), 0)
    except Exception:
        return ""
    if p is None or p.value is None:
        return ""
    v = p.value
    if isinstance(v, bytes):
        return v.decode("utf-8", errors="replace")
    return str(v)


def lister() -> dict:
    """{"fenetres": [{"id": "0x3a00007", "nom": …, "classe": …, "active": bool,
    "reduite": bool}, …]} — vide sans serveur graphique."""
    d = _display()
    if d is None:
        return {"fenetres": []}
    out = []
    try:
        racine = d.screen().root
        atome = d.intern_atom
        liste = racine.get_full_property(atome("_NET_CLIENT_LIST"), 0)
        ids = list(liste.value) if liste is not None else []
        act = racine.get_full_property(atome("_NET_ACTIVE_WINDOW"), 0)
        active = int(act.value[0]) if act is not None and len(act.value) else 0
        exclus = {atome(t) for t in TYPES_EXCLUS}
        sauter = atome("_NET_WM_STATE_SKIP_TASKBAR")
        cache = atome("_NET_WM_STATE_HIDDEN")
        moi = os.getpid()
        for wid in ids:
            fen = d.create_resource_object("window", wid)
            try:
                types = fen.get_full_property(atome("_NET_WM_WINDOW_TYPE"), 0)
                if types is not None and any(t in exclus for t in types.value):
                    continue
                etats = fen.get_full_property(atome("_NET_WM_STATE"), 0)
                etats = set(etats.value) if etats is not None else set()
                if sauter in etats:
                    continue
                pid = fen.get_full_property(atome("_NET_WM_PID"), 0)
                if pid is not None and len(pid.value) and int(pid.value[0]) == moi:
                    continue        # les fenêtres du bureau lui-même
                classe = fen.get_wm_class() or ("", "")
                nom = _texte(d, fen, "_NET_WM_NAME") or _texte(d, fen, "WM_NAME") or classe[-1] or "fenêtre"
            except Exception:       # une fenêtre fermée entre-temps
                continue
            out.append({"id": hex(wid), "nom": nom.strip()[:80], "classe": (classe[-1] or "")[:60],
                        "active": wid == active, "reduite": cache in etats,
                        "_classes": tuple(classe)})
    except Exception:
        out = []
    finally:
        _fermer(d)
    return {"fenetres": out[-MAX_FENETRES:]}


def icone(ident: str) -> Path | None:
    """Le fichier d'icône de la fenêtre ident (« 0x… »), ou None."""
    for f in lister()["fenetres"]:
        if f["id"] == ident:
            return _icone_classe(f["_classes"])
    return None


def publique(etat: dict) -> dict:
    """Ce que la page reçoit : sans les classes brutes, avec « icone »."""
    out = []
    for f in etat["fenetres"]:
        g = {k: v for k, v in f.items() if not k.startswith("_")}
        g["icone"] = _icone_classe(f["_classes"]) is not None
        out.append(g)
    return {"fenetres": out}


def _message(d, fen, type_atome: str, donnees: list[int]) -> None:
    from Xlib import X  # noqa: PLC0415
    from Xlib.protocol import event  # noqa: PLC0415
    racine = d.screen().root
    ev = event.ClientMessage(window=fen, client_type=d.intern_atom(type_atome),
                             data=(32, (donnees + [0] * 5)[:5]))
    racine.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)


def geste(ident: str, quoi: str) -> bool:
    """quoi : « basculer » (devant, ou réduite si elle l'est déjà), ou
    « fermer » (la fenêtre demande poliment à l'appli de se fermer)."""
    try:
        wid = int(ident, 16)
    except (TypeError, ValueError):
        return False
    #  Seulement une fenêtre que lister() montre : la page ne peut pas viser
    #  n'importe quelle fenêtre de l'écran.
    connue = next((f for f in lister()["fenetres"] if f["id"] == hex(wid)), None)
    if connue is None:
        return False
    d = _display()
    if d is None:
        return False
    try:
        fen = d.create_resource_object("window", wid)
        if quoi == "fermer":
            _message(d, fen, "_NET_CLOSE_WINDOW", [0, 2])
        elif connue["active"] and not connue["reduite"]:
            #  WM_CHANGE_STATE IconicState (3) : la façon ICCCM de réduire.
            _message(d, fen, "WM_CHANGE_STATE", [3])
        else:
            #  Source 2 = « un pager / une barre des tâches » : xfwm4 obéit
            #  sans le garde-fou anti-vol de focus, et change de bureau
            #  virtuel si la fenêtre est sur un autre.
            _message(d, fen, "_NET_ACTIVE_WINDOW", [2, 0, 0])
        d.flush()
        return True
    except Exception:
        return False
    finally:
        _fermer(d)
