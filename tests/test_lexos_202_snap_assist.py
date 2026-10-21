#!/usr/bin/env python3
"""Banc sans X11 : ne doit jamais ouvrir ni déplacer les fenêtres du runner."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

R = Path(__file__).resolve().parents[1]
CHROOT = R / "config/includes.chroot"
SCRIPT = CHROOT / "usr/lib/lexos/assistant-mosaique.py"

spec = importlib.util.spec_from_file_location("lexos_snap_assist", SCRIPT)
snap = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = snap
spec.loader.exec_module(snap)


class Geometry(unittest.TestCase):
    def test_odd_width_secondary_monitor(self):
        left, right = snap.halves(snap.Rect(1920, 32, 1001, 768))
        self.assertEqual(left, snap.Rect(1920, 32, 500, 768))
        self.assertEqual(right, snap.Rect(2420, 32, 501, 768))
        self.assertEqual(left.width + right.width, 1001)

    def test_left_tile_and_panel_workarea(self):
        work = snap.Rect(0, 42, 1920, 1038)
        self.assertTrue(snap.is_left_tile(snap.Rect(1, 43, 959, 1036), work))
        self.assertFalse(snap.is_left_tile(snap.Rect(960, 42, 960, 1038), work))
        self.assertFalse(snap.is_left_tile(snap.Rect(0, 0, 1920, 1080), work))
        self.assertFalse(snap.is_left_tile(snap.Rect(0, 42, 500, 1038), work))

    def test_candidates_cannot_cross_workspaces(self):
        self.assertTrue(snap.desktop_ok(None, 2))
        self.assertTrue(snap.desktop_ok(0xFFFFFFFF, 2))
        self.assertTrue(snap.desktop_ok(2, 2))
        self.assertFalse(snap.desktop_ok(1, 2))


class FakeX:
    class X:
        Button1Mask = 256
    def __init__(self):
        self.geometry = snap.Rect(160, 50, 800, 620)
        self.button = True
        self.pointer_x = 60
        self.desktop = 0
    def active(self):
        return 7
    def win(self, xid):
        return xid
    def is_normal(self, _window):
        return True
    def first(self, _win, _name):
        return self.desktop
    def workspace(self):
        return 0
    def frame(self, _win):
        return self.geometry
    def pointer(self):
        return type("Pointer", (), dict(mask=self.X.Button1Mask if self.button else 0,
                                        root_x=self.pointer_x, root_y=180))()
    def candidates(self, exclude):
        return [(8, "Thunar"), (9, "Navigateur")] if exclude == 7 else []


class Gesture(unittest.TestCase):
    def new_watcher(self):
        x = FakeX()
        w = snap.Watcher(x)
        w.workarea = lambda _frame: snap.Rect(0, 40, 1200, 760)
        events = []
        w.chooser.show = lambda source, area, items: events.append((source, area, items))
        return x, w, events

    def test_left_mouse_drop_opens_chooser_once(self):
        x, w, events = self.new_watcher()
        # Pendant le glisser la souris rejoint le bord gauche.
        x.pointer_x = 3
        with mock.patch.object(snap, "enabled", return_value=True):
            with mock.patch.object(snap.time, "monotonic", return_value=1.0):
                w.step()
            x.button = False
            x.geometry = snap.Rect(0, 40, 600, 760)
            with mock.patch.object(snap.time, "monotonic", return_value=1.2):
                w.step()
            self.assertEqual(events, [])  # Éviter popup pendant redimensionnement.
            with mock.patch.object(snap.time, "monotonic", return_value=1.7):
                w.step()
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0][0], 7)
            self.assertEqual(events[0][2][0], (8, "Thunar"))
            with mock.patch.object(snap.time, "monotonic", return_value=1.9):
                w.step()
            self.assertEqual(len(events), 1)

    def test_initial_tiled_window_does_not_trigger_chooser(self):
        x, w, events = self.new_watcher()
        x.geometry = snap.Rect(0, 40, 600, 760)
        x.button = False
        x.pointer_x = 500
        with mock.patch.object(snap, "enabled", return_value=True):
            with mock.patch.object(snap.time, "monotonic", return_value=1.0):
                w.step()
            with mock.patch.object(snap.time, "monotonic", return_value=2.0):
                w.step()
        self.assertEqual(events, [])

    def test_other_workspace_rejected(self):
        x, w, events = self.new_watcher()
        x.desktop = 1
        with mock.patch.object(snap, "enabled", return_value=True):
            w.step()
        self.assertEqual(events, [])


class Integration(unittest.TestCase):
    def test_cli_can_disable_and_enable_without_display(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ,
                       XDG_CONFIG_HOME=str(Path(tmp) / "config"),
                       XDG_CACHE_HOME=str(Path(tmp) / "cache"))
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            for action, expected in [("status", "activé"), ("off", "désactivé"),
                                     ("on", "activé"), ("off", "désactivé")]:
                result = subprocess.run([sys.executable, str(SCRIPT), action],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)
            self.assertEqual(
                (Path(tmp) / "config/lexos/assistant-mosaique").read_text(), "off\n")

    def test_xfwm4_native_tiling_preserved(self):
        path = CHROOT / "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
        xml = ET.parse(path)
        prop = xml.find(".//property[@name='tile_on_move']")
        self.assertIsNotNone(prop)
        self.assertEqual(prop.get("value"), "true")
        #  Glisser au bord doit DIVISER l'écran, pas changer de bureau :
        #  wrap_windows est vrai par défaut dans xfwm4.
        wrap = xml.find(".//property[@name='wrap_windows']")
        self.assertIsNotNone(wrap)
        self.assertEqual(wrap.get("value"), "false")
        #  Et c'est réappliqué à chaque session, pour les comptes existants.
        source = SCRIPT.read_text()
        self.assertIn('"/general/wrap_windows", "false"', source)
        corner = (CHROOT / "usr/lib/lexos/coin-actif").read_text()
        self.assertIn("boutons & BOUTONS_TENUS", corner)
        start =(CHROOT / "etc/xdg/autostart/lexos-assistant-mosaique.desktop").read_text()
        self.assertIn("OnlyShowIn=XFCE;", start)
        self.assertIn("--watch", start)
        self.assertIn("NoDisplay=true", start)
        cli = (CHROOT / "usr/bin/lexos").read_text()
        self.assertIn("mosaique|mosaïque|snap)", cli)
        packages = (R / "flavours/standard/desktop.list.chroot").read_text()
        self.assertIn("gir1.2-gtk-3.0", packages)
        self.assertIn("python3-gi", packages)

    def test_no_compositor_changes(self):
        source = SCRIPT.read_text()
        self.assertNotIn("xfwm4 --replace", source)
        self.assertNotIn("picom --config", source)
        self.assertNotIn("xrandr --output", source)
        self.assertIn("_NET_MOVERESIZE_WINDOW", source)
        self.assertIn("_NET_WM_DESKTOP", source)


if __name__ == "__main__":
    unittest.main()
