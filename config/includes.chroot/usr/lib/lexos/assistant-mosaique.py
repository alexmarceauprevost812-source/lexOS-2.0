#!/usr/bin/env python3
# LexOS Pro 2.0.2 — assistant mosaïque XFCE/X11 (glisser à gauche → choisir à droite).
#
# Le geste et le placement GAUCHE sont natifs à xfwm4 (tile_on_move=true).
# Ce programme ne remplace ni xfwm4 ni picom. Il attend la fin du glisser
# au bord gauche et propose les autres fenêtres du MÊME bureau.
# La fenêtre choisie rejoint la moitié DROITE via EWMH, sans envoyer de
# raccourcis clavier synthétiques. Une seule instance par session.
#
# Désactivable : lexos mosaique off | on | status
# Dépendances : python3-xlib (core), python3-gi + gir1.2-gtk-3.0 (desktop).
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time
from dataclasses import dataclass

BASE = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "lexos"
STATE = BASE / "assistant-mosaique"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "lexos"
LOCK = CACHE / "assistant-mosaique.lock"
POLL_MS = 160
EDGE_PX = 48
STABLE_SEC = 0.32
ARMED_SEC = 2.0


@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    width: int
    height: int


def halves(work):
    """Moitié gauche/droite sans pixel perdu, y compris sur écran secondaire."""
    n = work.width // 2
    return (Rect(work.x, work.y, n, work.height),
            Rect(work.x + n, work.y, work.width - n, work.height))


def is_left_tile(frame, work, tolerance=36):
    """Comparer le CADRE de fenêtre à la moitié utilisable (panels exclus)."""
    if min(frame.width, frame.height, work.width, work.height) <= 0:
        return False
    left, _ = halves(work)
    return (abs(frame.x - left.x) <= tolerance
            and abs(frame.y - left.y) <= tolerance
            and abs(frame.width - left.width) <= tolerance
            and abs(frame.height - left.height) <= tolerance)


def desktop_ok(window_desktop, current):
    return window_desktop is None or window_desktop in (current, 0xFFFFFFFF)


def enabled():
    try:
        return STATE.read_text(encoding="utf-8").strip() != "off"
    except FileNotFoundError:
        return True  # Nouveau LexOS : assistant proposé, modifiable par compte.
    except OSError:
        return False


def write_enabled(value):
    BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = STATE.with_name(STATE.name + "." + str(os.getpid()))
    try:
        temporary.write_text("on\n" if value else "off\n", encoding="utf-8")
        os.chmod(temporary, 0o600)
        os.replace(temporary, STATE)
    finally:
        temporary.unlink(missing_ok=True)


def lock_handle():
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = LOCK.open("a+")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fd.close()
        return None
    return fd


def running():
    fd = lock_handle()
    if fd is None:
        return True
    fd.close()
    return False


def x11_session():
    return bool(os.environ.get("DISPLAY")) and os.environ.get("XDG_SESSION_TYPE", "x11").lower() != "wayland"


def command(mode):
    if mode in ("on", "off"):
        want = mode == "on"
        write_enabled(want)
        if want:
            # Action explicite de l'utilisateur : rétablir le geste XFWM4.
            if x11_session():
                subprocess.run(["xfconf-query", "-c", "xfwm4", "-p",
                                "/general/tile_on_move", "-s", "true"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               check=False)
            if x11_session() and not running():
                subprocess.Popen([sys.executable, __file__, "--watch"],
                                 start_new_session=True, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            # Le veilleur se ferme de lui-même au prochain cycle (160 ms).
            # On ne désactive PAS le carrelage natif de xfwm4.
            pass
    elif mode != "status":
        print("Usage : lexos mosaique on | off | status")
        return 2

    print("Assistant mosaïque :", "activé" if enabled() else "désactivé")
    print("Surveillance :", "en cours" if running() else "à l'arrêt")
    print("Glisser au bord gauche : XFCE/xfwm4 (fonction native)")
    return 0


class X11:
    def __init__(self):
        from Xlib import display, X, protocol
        self.X = X
        self.protocol = protocol
        self.d = display.Display()
        self.root = self.d.screen().root
        self.atoms = {}

    def atom(self, name):
        if name not in self.atoms:
            self.atoms[name] = self.d.intern_atom(name)
        return self.atoms[name]

    def prop(self, win, name):
        try:
            item = win.get_full_property(self.atom(name), self.X.AnyPropertyType)
            return item.value if item is not None else []
        except Exception:
            return []

    def first(self, win, name, default=None):
        vals = self.prop(win, name)
        return int(vals[0]) if len(vals) else default

    def win(self, xid):
        return self.d.create_resource_object("window", int(xid))

    def active(self):
        return self.first(self.root, "_NET_ACTIVE_WINDOW")

    def workspace(self):
        return self.first(self.root, "_NET_CURRENT_DESKTOP", 0)

    def clients(self):
        ids = self.prop(self.root, "_NET_CLIENT_LIST_STACKING")
        if not len(ids):
            ids = self.prop(self.root, "_NET_CLIENT_LIST")
        return [int(item) for item in ids]

    def is_normal(self, win):
        types = [int(t) for t in self.prop(win, "_NET_WM_WINDOW_TYPE")]
        normal = self.atom("_NET_WM_WINDOW_TYPE_NORMAL")
        if types and normal not in types:
            return False
        states = [int(t) for t in self.prop(win, "_NET_WM_STATE")]
        if self.atom("_NET_WM_STATE_FULLSCREEN") in states:
            return False
        if self.atom("_NET_WM_STATE_MODAL") in states:
            return False
        return True

    def frame(self, win):
        geo = win.get_geometry()
        loc = win.translate_coords(self.root, 0, 0)
        ext = [int(v) for v in self.prop(win, "_NET_FRAME_EXTENTS")[:4]]
        if len(ext) != 4:
            ext = [0, 0, 0, 0]
        l, r, top, bottom = ext
        return Rect(loc.x - l, loc.y - top,
                    geo.width + l + r, geo.height + top + bottom)

    def title(self, win):
        val = self.prop(win, "_NET_WM_NAME")
        if len(val):
            try:
                title = bytes(val).decode("utf-8", "replace").strip()
                if title:
                    return title[:160]
            except (TypeError, ValueError):
                pass
        try:
            name = win.get_wm_name()
            return (name.decode("utf-8", "replace") if isinstance(name, bytes)
                    else str(name or "Fenêtre"))[:160]
        except Exception:
            return "Fenêtre"

    def candidates(self, excluded):
        current = self.workspace()
        found = []
        for xid in reversed(self.clients()):
            if xid == excluded:
                continue
            try:
                w = self.win(xid)
                if (not self.is_normal(w)
                        or not desktop_ok(self.first(w, "_NET_WM_DESKTOP"), current)):
                    continue
                name = self.title(w).strip()
                if name:
                    found.append((xid, name))
            except Exception:
                continue  # Une fenêtre peut se fermer entre deux lectures.
        return found[:20]

    def pointer(self):
        return self.root.query_pointer()

    def send(self, win, name, values):
        event = self.protocol.event.ClientMessage(
            window=win, client_type=self.atom(name),
            data=(32, (values + [0, 0, 0, 0, 0])[:5]))
        self.root.send_event(event, event_mask=self.X.SubstructureRedirectMask
                             | self.X.SubstructureNotifyMask)
        self.d.flush()

    def place_right(self, xid, work):
        """Utiliser _NET_MOVERESIZE_WINDOW : le WM reste propriétaire du cadre."""
        win = self.win(xid)
        if not self.is_normal(win):
            return
        _, right = halves(work)
        ext = [int(v) for v in self.prop(win, "_NET_FRAME_EXTENTS")[:4]]
        if len(ext) != 4:
            ext = [0, 0, 0, 0]
        l, r, top, bottom = ext
        # Respecter les décorations du gestionnaire de fenêtres XFWM4.
        client_w = max(120, right.width - l - r)
        client_h = max(120, right.height - top - bottom)
        # Restaurer avant de redimensionner une fenêtre maximisée.
        self.send(win, "_NET_WM_STATE", [0,
                  self.atom("_NET_WM_STATE_MAXIMIZED_VERT"),
                  self.atom("_NET_WM_STATE_MAXIMIZED_HORZ"), 2, 0])
        # Source=application (2) : demande légitime au gestionnaire.
        self.send(win, "_NET_ACTIVE_WINDOW", [2, self.X.CurrentTime, 0, 0, 0])
        try:
            win.map()  # Une fenêtre réduite peut être choisie aussi.
            self.d.flush()
        except Exception:
            pass
        return (right.x, right.y, client_w, client_h, xid)

    def finish_right(self, placement):
        x, y, w, h, xid = placement
        # EWMH : gravity=NorthWest(1), présence de x/y/w/h (bits 8..11),
        # source application=2 (bits 12..15).
        flags = 1 | (15 << 8) | (2 << 12)
        self.send(self.win(xid), "_NET_MOVERESIZE_WINDOW",
                  [flags, x, y, w, h])


class Chooser:
    def __init__(self, watcher):
        self.watcher = watcher
        self.win = None
        self.source = None
        self.work = None
        self.deadline = 0.0

    def hide(self):
        if self.win:
            self.win.destroy()
            self.win = None
        self.source = None

    def show(self, source, work, choices):
        from gi.repository import Gtk, Gdk, Pango
        self.hide()
        self.source, self.work = source, work
        self.deadline = time.monotonic() + 15.0
        win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        self.win = win
        win.set_title("LexOS — Choisis la deuxième fenêtre")
        win.set_decorated(False)
        win.set_keep_above(True)
        win.set_skip_taskbar_hint(True)
        win.set_skip_pager_hint(True)
        win.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        win.connect("key-press-event", self.on_key)
        win.connect("destroy", self.on_destroy)
        provider = Gtk.CssProvider()
        provider.load_from_data(b"""
            window.lexos-snap { background: #111827; border: 2px solid #ff8c28; border-radius: 12px; }
            label.lexos-heading { color: #ffffff; font-weight: bold; font-size: 16px; }
            label.lexos-sub { color: #f5b57a; font-size: 12px; }
            button.lexos-choice { background: #222d3b; color: #ffffff; border-radius: 7px; padding: 9px; }
            button.lexos-choice:hover { background: #79441b; }
            button.lexos-close { background: transparent; color: #ffffff; }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        win.get_style_context().add_class("lexos-snap")
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=9)
        outer.set_border_width(15)
        titlebar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        heading = Gtk.Label(label="Choisis la 2e fenêtre")
        heading.set_xalign(0)
        heading.get_style_context().add_class("lexos-heading")
        titlebar.pack_start(heading, True, True, 0)
        close = Gtk.Button(label="✕")
        close.get_style_context().add_class("lexos-close")
        close.connect("clicked", lambda *_: self.hide())
        titlebar.pack_end(close, False, False, 0)
        outer.pack_start(titlebar, False, False, 0)
        sub = Gtk.Label(label="La fenêtre choisie remplira la moitié droite (50/50).")
        sub.set_xalign(0)
        sub.set_line_wrap(True)
        sub.get_style_context().add_class("lexos-sub")
        outer.pack_start(sub, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        items = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        for xid, label in choices:
            button = Gtk.Button()
            button.get_style_context().add_class("lexos-choice")
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=9)
            icon = Gtk.Image.new_from_icon_name("window-new", Gtk.IconSize.MENU)
            row.pack_start(icon, False, False, 0)
            text = Gtk.Label(label=label)
            text.set_xalign(0)
            text.set_ellipsize(Pango.EllipsizeMode.END)
            row.pack_start(text, True, True, 0)
            button.add(row)
            button.connect("clicked", self.choose, xid)
            items.pack_start(button, False, False, 0)
        scroll.add(items)
        outer.pack_start(scroll, True, True, 0)
        win.add(outer)
        width = min(460, max(220, halves(work)[1].width - 30))
        height = min(work.height - 24, max(175, min(350, 110 + 51 * len(choices))))
        win.set_default_size(width, height)
        win.show_all()
        right = halves(work)[1]
        win.move(right.x + (right.width - width)//2,
                 right.y + (right.height - height)//2)

    def on_destroy(self, *_args):
        self.win = None
        self.source = None

    def on_key(self, _win, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape:
            self.hide()
            return True
        return False

    def choose(self, _button, xid):
        from gi.repository import GLib
        work = self.work
        self.hide()
        self.watcher.suppress_until = time.monotonic() + 2.0
        try:
            placement = self.watcher.x.place_right(xid, work)
            if placement:
                # XFWM4 doit traiter la suppression d'état maximisé avant
                # la demande de nouvelle géométrie.
                GLib.timeout_add(160, self._finish, placement)
        except Exception as exc:
            print("LexOS mosaïque : placement impossible :", exc, file=sys.stderr)

    def _finish(self, placement):
        try:
            self.watcher.x.finish_right(placement)
        except Exception as exc:
            print("LexOS mosaïque : géométrie refusée :", exc, file=sys.stderr)
        return False


class Watcher:
    def __init__(self, x):
        self.x = x
        self.chooser = Chooser(self)
        self.armed = None
        self.previous_frame = {}
        self.left_seen = {}
        self.suppress_until = 0.0
        self.last_shown = (None, 0)

    def workarea(self, frame):
        from gi.repository import Gdk
        display = Gdk.Display.get_default()
        if display is None:
            return None
        cx = frame.x + frame.width//2
        cy = frame.y + frame.height//2
        monitor = display.get_monitor_at_point(cx, cy)
        if monitor is None:
            return None
        a = monitor.get_workarea()
        return Rect(a.x, a.y, a.width, a.height)

    def step(self):
        now = time.monotonic()
        if not enabled():
            self.chooser.hide()
            from gi.repository import Gtk
            Gtk.main_quit()
            return False
        if self.chooser.win and now > self.chooser.deadline:
            self.chooser.hide()
        if now < self.suppress_until:
            return True
        try:
            xid = self.x.active()
            if not xid:
                return True
            win = self.x.win(xid)
            if not self.x.is_normal(win):
                return True
            if not desktop_ok(self.x.first(win, "_NET_WM_DESKTOP"),
                              self.x.workspace()):
                return True
            frame = self.x.frame(win)
            work = self.workarea(frame)
            if not work:
                return True
            pointer = self.x.pointer()
            pressed = bool(pointer.mask & self.x.X.Button1Mask)
            near_left = (work.x <= pointer.root_x <= work.x + EDGE_PX
                         and work.y <= pointer.root_y < work.y + work.height)
            if pressed and near_left:
                self.armed = (xid, now)
            last = self.previous_frame.get(xid)
            self.previous_frame[xid] = frame
            if self.chooser.win:
                return True
            tiled = is_left_tile(frame, work)
            if not tiled or pressed:
                self.left_seen.pop(xid, None)
                return True
            intentional_drag = (
                (self.armed and self.armed[0] == xid
                 and now - self.armed[1] < ARMED_SEC)
                or (last is not None and last != frame and near_left))
            # La géométrie peut rester stable après le relâchement. Garder
            # le déclencheur pendant STABLE_SEC, sinon le choix n'apparaît
            # jamais si l'événement n'a été vu qu'un seul sondage.
            if intentional_drag:
                self.left_seen.setdefault(xid, now)
            first = self.left_seen.get(xid)
            if first is None:
                return True
            if now - first < STABLE_SEC or self.last_shown[0] == xid and now - self.last_shown[1] < 5:
                return True
            choices = self.x.candidates(xid)
            self.armed = None
            self.left_seen.pop(xid, None)
            if choices:
                self.chooser.show(xid, work, choices)
                self.last_shown = (xid, now)
        except Exception:
            # Fenêtre détruite ou écran débranché au moment du sondage.
            # L'assistant ne doit JAMAIS faire tomber le bureau XFCE.
            return True
        return True


def watch():
    if not enabled() or not x11_session():
        return 0
    handle = lock_handle()
    if handle is None:
        return 0  # Une instance surveille déjà cette session.
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk, GLib
        x = X11()
        watcher = Watcher(x)
        GLib.timeout_add(POLL_MS, watcher.step)
        Gtk.main()
    except (ImportError, RuntimeError, OSError) as exc:
        print("LexOS mosaïque : assistant indisponible :", exc, file=sys.stderr)
        return 1
    finally:
        handle.close()
    return 0


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "status"
    sys.exit(watch() if arg == "--watch" else command(arg))
