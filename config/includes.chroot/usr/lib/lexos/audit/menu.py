#!/usr/bin/python3
"""Catalogue d'audit : aucune opération ni élévation lancée automatiquement."""
import argparse
import configparser
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

DATA = Path('/usr/share/lexos/audit-tools.packages')
DESKTOP = 'lexos-audit.desktop'
GUI = {'johnny': 'johnny', 'wireshark': 'wireshark', 'zenmap': 'zenmap',
       'ophcrack': 'ophcrack'}
LABELS = {'Reseau et DNS': 'Réseau et DNS',
          'Analyse de fichiers et recuperation': 'Analyse de fichiers et récupération',
          'Debogage et inspection': 'Débogage et inspection',
          'Audit systeme et donnees': 'Audit système et données'}


def catalogue(path=DATA):
    groups = {}
    current = None
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith('# '):
            current = LABELS.get(line[2:], line[2:])
            groups.setdefault(current, [])
        elif line:
            if current is None or not re.fullmatch(r'[a-z0-9][a-z0-9.+-]*', line):
                raise ValueError('Manifeste invalide')
            groups[current].append(line)
    groups['Mots de passe'].append('johnny')
    return groups


def installed(package):
    if package == 'johnny':
        return shutil.which('johnny') is not None
    p = subprocess.run(['dpkg-query', '-W', '-f=${Status}', package],
                       capture_output=True, text=True)
    return p.returncode == 0 and p.stdout == 'install ok installed'


def tool_logo(package, files):
    """Utiliser uniquement une icône fournie par le paquet ou le thème installé."""
    names = []
    for filename in files:
        if filename.endswith('.desktop') and Path(filename).is_file():
            desktop = configparser.ConfigParser(interpolation=None)
            try:
                desktop.read(filename, encoding='utf-8')
                icon = desktop.get('Desktop Entry', 'Icon', fallback='').strip()
                if icon:
                    names.append(icon)
            except (OSError, UnicodeError, configparser.Error):
                continue
    names.append(package)
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
        if Gtk.init_check()[0]:
            theme = Gtk.IconTheme.get_default()
            for name in names:
                if Path(name).is_absolute() and Path(name).is_file():
                    return Path(name)
                info = theme.lookup_icon(name, 48, 0)
                if info and info.get_filename():
                    return Path(info.get_filename())
    except (ImportError, ValueError, RuntimeError):
        pass
    # Le terminal peut aussi fonctionner sans affichage GTK (SSH, console).
    for name in names:
        if Path(name).is_absolute() and Path(name).is_file():
            return Path(name)
        if '/' in name:
            continue
        for size in ('scalable', '48x48', '32x32', '24x24'):
            for extension in ('.svg', '.png', '.xpm'):
                path = Path('/usr/share/icons/hicolor') / size / 'apps' / (name + extension)
                if path.is_file():
                    return path
    return None


def logo_banner(package, files, stream=None):
    stream = stream or sys.stdout
    colour = stream.isatty() and not os.environ.get('NO_COLOR') and os.environ.get('TERM') != 'dumb'
    if colour:
        print('\033[1;38;5;208m' + '━' * 44 + '\n  ' + package + ' · Outils d’audit LexOS\n' + '━' * 44 + '\033[0m', file=stream)
    else:
        print(package + ' · Outils d’audit LexOS', file=stream)
    if not colour:
        return
    image = tool_logo(package, files)
    if image is None:
        return
    try:
        import gi
        gi.require_version('GdkPixbuf', '2.0')
        from gi.repository import GdkPixbuf
        # Deux pixels verticaux par caractère : image fidèle en petits blocs,
        # compatible XFCE sans protocole d'images Kitty/Sixel ni paquet ajouté.
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(image), 24, 24, True)
        width, height = pixbuf.get_width(), pixbuf.get_height()
        pixels, stride, channels = pixbuf.get_pixels(), pixbuf.get_rowstride(), pixbuf.get_n_channels()
        def rgb(x, y):
            if y >= height:
                return (18, 18, 20)
            offset = y * stride + x * channels
            values = pixels[offset:offset+3]
            alpha = pixels[offset+3] if channels == 4 else 255
            return tuple((int(value)*alpha + bg*(255-alpha))//255 for value, bg in zip(values, (18, 18, 20)))
        for y in range(0, height, 2):
            row = []
            for x in range(width):
                top, bottom = rgb(x, y), rgb(x, y+1)
                row.append('\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm▀' % (*top, *bottom))
            print(''.join(row) + '\033[0m', file=stream)
        print(file=stream)
    except Exception:
        # Une icône illisible ne doit jamais empêcher l'ouverture du terminal.
        print('\033[0m', end='', file=stream)


def console(package):
    # Ne pas lancer les outils avec un --help supposé : certains travaillent
    # dès le démarrage. Afficher les exécutables et ouvrir un shell ordinaire.
    result = subprocess.run(['dpkg-query', '-L', package], capture_output=True, text=True)
    logo_banner(package, result.stdout.splitlines())
    print('Aucune opération lancée. Exécutables fournis par le paquet :', flush=True)
    paths = [p for p in result.stdout.splitlines()
             if re.match(r'^/usr/(s?bin)/[^/]+$', p) and os.access(p, os.X_OK)]
    for p in paths:
        print('  ' + p)
    print('\nAide : man NOM_DE_COMMANDE. Tape exit pour fermer.\n', flush=True)
    os.execv('/bin/bash', ['/bin/bash', '-i'])


def launch(package):
    if package in GUI:
        executable = shutil.which(GUI[package])
        if not executable:
            raise RuntimeError('Application indisponible : ' + package)
        subprocess.Popen([executable])
    else:
        terminal = shutil.which('xfce4-terminal')
        if not terminal:
            raise RuntimeError('Le terminal XFCE est indisponible.')
        subprocess.Popen([terminal, '--disable-server', '--title=Audit — ' + package,
                          '-x', '/usr/bin/python3', str(Path(__file__).resolve()),
                          '--console', package])


def skeleton(root):
    path = root / 'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml'
    tree = ET.parse(path)
    channel = tree.getroot()
    plugins = channel.find("./property[@name='plugins']")
    ids = channel.find("./property[@name='panels']/property[@name='panel-1']/property[@name='plugin-ids']")
    if plugins is None or ids is None:
        raise ValueError('Barre XFCE principale introuvable')
    for p in plugins:
        if p.find("./property[@name='items']/value[@value='lexos-audit.desktop']") is not None:
            return
    used = {int(p.attrib['name'].split('-')[-1]) for p in plugins}
    used.update(int(v.attrib['value']) for v in ids)
    number = max(used, default=0) + 1
    plugin = ET.SubElement(plugins, 'property', name=f'plugin-{number}', type='string', value='launcher')
    items = ET.SubElement(plugin, 'property', name='items', type='array')
    ET.SubElement(items, 'value', type='string', value=DESKTOP)
    ids.insert(1, ET.Element('value', type='int', value=str(number)))
    ET.indent(tree, space='  ')
    tree.write(path, encoding='UTF-8', xml_declaration=True)


def show():
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
    if not Gtk.init_check()[0]:
        raise SystemExit('Outils d’audit : aucun affichage graphique disponible.')
    window = Gtk.Window(title='Outils d’audit — LexOS Pro')
    window.set_default_size(620, 540)
    window.set_icon_name('lexos-kali-audit')
    window.connect('destroy', Gtk.main_quit)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    box.set_border_width(16)
    window.add(box)
    box.pack_start(Gtk.Label(label='Outils d’audit', xalign=0), False, False, 0)
    search = Gtk.SearchEntry(placeholder_text='Rechercher un outil…')
    box.pack_start(search, False, False, 0)
    hint = Gtk.Label(label='Applications graphiques ou terminal avec la liste des commandes.', xalign=0)
    hint.set_line_wrap(True)
    box.pack_start(hint, False, False, 0)
    scroll = Gtk.ScrolledWindow()
    box.pack_start(scroll, True, True, 0)
    listing = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    scroll.add(listing)
    rows = []
    for category, packages in catalogue().items():
        expander = Gtk.Expander(label=category)
        listing.pack_start(expander, False, False, 0)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        expander.add(content)
        children = []
        for package in packages:
            available = installed(package)
            button = Gtk.Button(label=package + (' — non installé' if not available else ''))
            button.set_sensitive(available)
            button.set_tooltip_text('Ouvrir l’application' if package in GUI else 'Ouvrir un terminal avec les commandes du paquet')
            button.connect('clicked', activate, package, window)
            content.pack_start(button, False, False, 0)
            children.append((package, button))
        rows.append((expander, children))
    def filter_rows(entry):
        query = entry.get_text().casefold().strip()
        for expander, children in rows:
            visible = 0
            for package, button in children:
                match = not query or query in package.casefold() or query in expander.get_label().casefold()
                button.set_visible(match)
                visible += match
            expander.set_visible(bool(visible))
            expander.set_expanded(bool(query and visible))
    search.connect('search-changed', filter_rows)
    window.show_all()
    Gtk.main()


def activate(_button, package, window):
    try:
        launch(package)
    except (OSError, RuntimeError) as error:
        from gi.repository import Gtk
        dialog = Gtk.MessageDialog(transient_for=window, modal=True,
            message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.CLOSE,
            text=str(error))
        dialog.run()
        dialog.destroy()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installer-squelette', type=Path)
    parser.add_argument('--console')
    args = parser.parse_args()
    if args.installer_squelette is not None:
        skeleton(args.installer_squelette)
    elif args.console:
        if args.console not in {p for group in catalogue().values() for p in group}:
            parser.error('Outil inconnu')
        console(args.console)
    else:
        show()
