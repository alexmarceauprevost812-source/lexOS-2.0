#!/usr/bin/env python3
"""Vue native des bureaux, du matériel et des applications installées."""
import configparser
import math
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys

from PySide6.QtCore import Qt, QThread, Signal, QTimer, QVariantAnimation, QSize
from PySide6.QtGui import QColor, QIcon, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QGridLayout, QStackedWidget, QLineEdit, QMessageBox, QScrollArea)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from moteur import outils as _outils


def command(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=2,
                              check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def applications():
    """Respecte les remplacements XDG, y compris les entrées masquées."""
    roots = [Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))]
    roots += [Path(p) for p in os.environ.get('XDG_DATA_DIRS',
                                           '/usr/local/share:/usr/share').split(':')]
    seen, result = set(), []
    desktops = set(os.environ.get('XDG_CURRENT_DESKTOP', 'XFCE').split(':'))
    for root in roots:
        directory = root/'applications'
        for path in sorted(directory.rglob('*.desktop')):
            key = str(path.relative_to(directory)).replace('/', '-')
            if key in seen:
                continue
            seen.add(key)
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(path, encoding='utf-8')
                entry = parser['Desktop Entry']
                if entry.get('Type') != 'Application' or any(
                        entry.get(k, '').lower() == 'true' for k in ('Hidden', 'NoDisplay')):
                    continue
                only = set(filter(None, entry.get('OnlyShowIn', '').split(';')))
                excluded = set(entry.get('NotShowIn', '').split(';'))
                if (only and not desktops.intersection(only)) or desktops.intersection(excluded):
                    continue
                if entry.get('TryExec') and not _outils.commande_existe(entry['TryExec']):
                    continue
                if not entry.get('Exec') and entry.get('DBusActivatable', '').lower() != 'true':
                    continue
                name = entry.get('Name[fr]', entry.get('Name', key))
                result.append((name, entry.get('Icon', ''), str(path)))
            except (OSError, configparser.Error, KeyError, UnicodeError):
                continue
    return sorted(result, key=lambda row: row[0].casefold())


class Poll(QThread):
    ready = Signal(dict)

    def run(self):
        gpu = command(['nvidia-smi', '--query-gpu=name,temperature.gpu,memory.used,memory.total',
                       '--format=csv,noheader,nounits']).splitlines()
        data = {'gpu': None, 'desktops': command(['wmctrl', '-d']),
                'windows': command(['wmctrl', '-lG'])}
        if gpu:
            fields = [p.strip() for p in gpu[0].split(',')]
            if len(fields) == 4:
                try:
                    data['gpu'] = (fields[0], *(float(p) for p in fields[1:]))
                except ValueError:
                    pass
        disk = shutil.disk_usage('/')
        data['disk'] = (disk.used, disk.total, disk.free)
        data['computer'] = platform.node()
        self.ready.emit(data)


class Dial(QWidget):
    def __init__(self, title):
        super().__init__()
        self.title, self.detail, self.ratio = title, 'Lecture…', 0.0
        self.setMinimumHeight(110)
        self.animation = QVariantAnimation(self)
        self.animation.setDuration(550)
        self.animation.valueChanged.connect(self.move_needle)

    def move_needle(self, value):
        self.ratio = value
        self.update()

    def set_value(self, ratio, detail):
        self.detail = detail
        self.animation.stop()
        self.animation.setStartValue(self.ratio)
        self.animation.setEndValue(max(0.0, min(1.0, ratio or 0.0)))
        self.animation.start()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        cx, cy, radius = self.width()/2, 66, 43
        painter.setPen(QPen(QColor('#555555'), 5))
        painter.drawArc(int(cx-radius), int(cy-radius), 86, 86, 30*16, 120*16)
        painter.setPen(QPen(QColor('#ff6a00'), 3))
        angle = math.radians(150 - self.ratio*120)
        painter.drawLine(int(cx), int(cy), int(cx+radius*math.cos(angle)),
                         int(cy-radius*math.sin(angle)))
        painter.setPen(QColor('white'))
        painter.drawText(self.rect().adjusted(4, 0, -4, -85), Qt.AlignmentFlag.AlignCenter, self.title)
        painter.drawText(self.rect().adjusted(4, 75, -4, 0), Qt.AlignmentFlag.AlignCenter, self.detail)


class Pages(QStackedWidget):
    changed = Signal()

    def wheelEvent(self, event):
        step = 1 if event.angleDelta().y() < 0 else -1
        self.setCurrentIndex(max(0, min(self.count()-1, self.currentIndex()+step)))
        self.changed.emit()
        event.accept()


class Overview(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('Vue des bureaux — LexOS Pro')
        self.setStyleSheet('QWidget {background:#080808;color:white;font-size:14px;}'
                          'QPushButton {background:#202020;border:1px solid #444;border-radius:12px;padding:9px;}'
                          'QPushButton:hover {border-color:#ff6a00;background:#302015;}'
                          'QLineEdit {background:#202020;padding:9px;border-radius:10px;}')
        layout = QVBoxLayout(self)
        header = QHBoxLayout()
        header.addWidget(QLabel('LEXOS PRO · Bureaux et applications'))
        header.addStretch()
        close = QPushButton('Fermer · Échap')
        close.clicked.connect(self.close)
        header.addWidget(close)
        layout.addLayout(header)
        self.workspaces = QWidget()
        self.workspace_layout = QHBoxLayout(self.workspaces)
        layout.addWidget(self.workspaces, 4)
        lower = QWidget()
        lower_layout = QVBoxLayout(lower)
        meters = QHBoxLayout()
        self.temp, self.disk, self.vram = Dial('Carte graphique · température'), Dial('Disque système'), Dial('VRAM utilisée')
        for meter in (self.temp, self.disk, self.vram):
            meters.addWidget(meter)
        lower_layout.addLayout(meters)
        self.gpu_label = QLabel('Recherche de la carte graphique…')
        lower_layout.addWidget(self.gpu_label)
        self.search = QLineEdit()
        self.search.setPlaceholderText('Rechercher une application installée…')
        lower_layout.addWidget(self.search)
        self.pages = Pages()
        lower_layout.addWidget(self.pages, 1)
        nav = QHBoxLayout()
        for label, delta in [('↑ Page précédente', -1), ('↓ Page suivante', 1)]:
            button = QPushButton(label)
            button.clicked.connect(lambda checked=False, d=delta: self.change_page(d))
            nav.addWidget(button)
        self.page_label = QLabel()
        nav.addWidget(self.page_label)
        lower_layout.addLayout(nav)
        layout.addWidget(lower, 6)
        self.workspace_signature = None
        self.apps = applications()
        self.search.textChanged.connect(self.populate)
        self.pages.changed.connect(self.page_number)
        self.populate()
        self.poll = Poll(self)
        self.poll.ready.connect(self.refresh)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.sample)
        self.timer.start(2000)
        self.sample()

    def sample(self):
        if not self.poll.isRunning():
            self.poll.start()

    def refresh(self, data):
        gpu = data['gpu']
        gpu_text = gpu[0] if gpu else 'Mesures NVIDIA indisponibles · pilote ou accès au GPU non disponible'
        self.gpu_label.setText(f"{data.get('computer', '')} · {gpu_text}".lstrip(' ·'))
        self.temp.set_value(gpu[1]/100 if gpu else 0, f'{gpu[1]:.0f} °C' if gpu else 'Indisponible')
        self.vram.set_value(gpu[2]/gpu[3] if gpu and gpu[3] else 0,
                            f'{gpu[2]:.0f} / {gpu[3]:.0f} Mio' if gpu else 'Indisponible')
        used, total, free = data['disk']
        self.disk.set_value(used/total, f'{used/2**30:.1f} Go utilisés · {free/2**30:.1f} Go libres')
        signature = (data['desktops'], data['windows'])
        if signature == self.workspace_signature:
            return
        self.workspace_signature = signature
        while self.workspace_layout.count():
            widget = self.workspace_layout.takeAt(0).widget()
            if widget:
                widget.deleteLater()
        windows = []
        for row in data['windows'].splitlines():
            parts = row.split(None, 7)
            if len(parts) == 8 and parts[1].lstrip('-').isdigit() and parts[7] != self.windowTitle():
                windows.append(parts)
        for row in data['desktops'].splitlines():
            parts = row.split()
            if not parts or not parts[0].isdigit():
                continue
            number = int(parts[0])
            card = QWidget()
            box = QVBoxLayout(card)
            switch = QPushButton(f'Bureau {number+1}' + (' · actif' if '*' in parts else ''))
            switch.clicked.connect(lambda checked=False, n=number: self.switch(n))
            box.addWidget(switch)
            for window in windows:
                if int(window[1]) not in (number, -1):
                    continue
                button = QPushButton(window[7][:70])
                pixmap = QApplication.primaryScreen().grabWindow(int(window[0], 16))
                if not pixmap.isNull():
                    button.setIcon(QIcon(pixmap))
                    button.setIconSize(button.iconSize().expandedTo(pixmap.size().scaled(150, 70, Qt.AspectRatioMode.KeepAspectRatio)))
                button.clicked.connect(lambda checked=False, wid=window[0]: self.activate(wid))
                box.addWidget(button)
            box.addStretch()
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            scroll.setWidget(card)
            self.workspace_layout.addWidget(scroll)
        if not data['desktops']:
            self.workspace_layout.addWidget(QLabel('Aperçu des bureaux indisponible (wmctrl / session X11 requis).'))

    def switch(self, number):
        try:
            subprocess.run(['wmctrl', '-s', str(number)], timeout=2, check=True)
            self.close()
        except (OSError, subprocess.SubprocessError):
            QMessageBox.warning(self, 'Bureau', 'Impossible de changer de bureau dans cette session.')

    def activate(self, identifier):
        try:
            subprocess.run(['wmctrl', '-ia', identifier], timeout=2, check=True)
            self.close()
        except (OSError, subprocess.SubprocessError):
            QMessageBox.warning(self, 'Fenêtre', 'Cette fenêtre ne peut plus être activée.')

    def populate(self):
        while self.pages.count():
            widget = self.pages.widget(0)
            self.pages.removeWidget(widget)
            widget.deleteLater()
        items = [a for a in self.apps if self.search.text().casefold() in a[0].casefold()]
        for start in range(0, max(1, len(items)), 12):
            page = QWidget()
            grid = QGridLayout(page)
            for index, (name, icon, path) in enumerate(items[start:start+12]):
                button = QPushButton(name)
                button.setIcon(QIcon(icon) if icon.startswith('/') else QIcon.fromTheme(icon))
                button.clicked.connect(lambda checked=False, p=path: self.launch(p))
                grid.addWidget(button, index//6, index % 6)
            if not items:
                grid.addWidget(QLabel('Aucune application trouvée.'), 0, 0)
            self.pages.addWidget(page)
        self.page_number()

    def page_number(self):
        self.page_label.setText(f'Page {self.pages.currentIndex()+1} / {self.pages.count()} · molette verticale')

    def change_page(self, delta):
        self.pages.setCurrentIndex(max(0, min(self.pages.count()-1, self.pages.currentIndex()+delta)))
        self.page_number()

    def launch(self, path):
        try:
            subprocess.Popen(['gio', 'launch', path])
            self.close()
        except OSError as error:
            QMessageBox.warning(self, 'Application', str(error))

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.close()

    def resizeEvent(self, event):
        self.workspaces.setFixedHeight(int(self.height()*0.4))
        super().resizeEvent(event)

    def closeEvent(self, event):
        self.timer.stop()
        if self.poll.isRunning():
            self.hide()
            self.poll.finished.connect(self.close)
            event.ignore()
            return
        event.accept()


class DockButton(QPushButton):
    """Bouton fixe agrandi au pied du dock de droite, indépendant de son zoom."""
    def __init__(self):
        super().__init__()
        self.setWindowFlags(Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint |
                            Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setWindowTitle('Applications LexOS')
        self.setToolTip('Bureaux, ordinateur et applications')
        self.setFixedSize(96, 116)
        self.setStyleSheet('QPushButton {background:#000;border:1px solid #ff6a00;border-radius:14px;}'
                           'QPushButton:hover {border:3px solid #ff9500;}')
        pixmap = QPixmap(str(Path(os.environ.get('LEXOS_BRANDING_DIR',
                              '/usr/share/lexos/branding'))/'icon-applications.png'))
        self.setIcon(QIcon(pixmap))
        self.setIconSize(self.size()-QSize(8, 8))
        self.clicked.connect(self.open_overview)
        self.child = None
        self.watch = QTimer(self)
        self.watch.setInterval(250)
        self.watch.timeout.connect(self.child_finished)
        self.place()
        QApplication.primaryScreen().availableGeometryChanged.connect(self.place)

    def place(self, *args):
        rect = QApplication.primaryScreen().availableGeometry()
        self.move(rect.right()-self.width()-8, rect.bottom()-self.height()-8)

    def open_overview(self):
        try:
            self.child = subprocess.Popen(['/usr/bin/lexos-overview'])
            self.hide()
            self.watch.start()
        except OSError as error:
            QMessageBox.warning(self, 'Applications', str(error))

    def child_finished(self):
        if self.child is not None and self.child.poll() is not None:
            self.watch.stop()
            self.show()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    if '--dock-button' in sys.argv:
        view = DockButton()
        view.show()
    else:
        view = Overview()
        view.showFullScreen()
        view.fade = QVariantAnimation(view)
        view.fade.setStartValue(0.0)
        view.fade.setEndValue(1.0)
        view.fade.setDuration(220)
        view.fade.valueChanged.connect(view.setWindowOpacity)
        view.fade.start()
    sys.exit(app.exec())
