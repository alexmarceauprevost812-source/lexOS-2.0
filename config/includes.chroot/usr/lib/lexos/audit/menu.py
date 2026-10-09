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
LOGO = Path('/usr/share/lexos/audit-kali-logo.png')
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


HELP = {'nmap': ['nmap', '--help'], 'hashcat': ['hashcat', '--help']}
ANSI = re.compile(r'\x1b\[[0-9;]*m')


def use_colour(stream=None):
    stream = stream or sys.stdout
    return stream.isatty() and not os.environ.get('NO_COLOR') and os.environ.get('TERM') != 'dumb'


def colour_help(text, enabled=True):
    if not enabled or '\033' in text:
        return text
    # Only add SGR colours; retain every character and line of the help.
    result = []
    tokens = re.compile(r'(--?[A-Za-z][A-Za-z0-9_-]*|<[^>\n]+>|\[[^]\n]+\])')
    for line in text.splitlines(keepends=True):
        if re.match(r'^[A-Z][A-Z0-9 /(),&_-]+:', line):
            body = line.rstrip('\r\n')
            result.append('\033[1;38;5;208m' + body + '\033[0m' + line[len(body):])
        else:
            def highlight(match):
                colour = '81' if match.group().startswith(('<', '[')) else '114'
                return '\033[38;5;' + colour + 'm' + match.group() + '\033[0m'
            result.append(tokens.sub(highlight, line))
    return ''.join(result)


def tool_help(package):
    args = HELP.get(package)
    if args is None or not shutil.which(args[0]):
        return
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print(colour_help(result.stdout, use_colour()), end='', flush=True)
    except (OSError, subprocess.TimeoutExpired):
        pass


def console(package):
    # Seules les aides explicitement autorisées (Nmap/Hashcat) sont lancées.
    # Les autres outils restent des commandes à exécuter volontairement.
    result = subprocess.run(['dpkg-query', '-L', package], capture_output=True, text=True)
    logo_banner(package, result.stdout.splitlines())
    notice = 'Aucune opération lancée. Exécutables fournis par le paquet :'
    print(('\033[38;5;250m' + notice + '\033[0m') if use_colour() else notice, flush=True)
    paths = [p for p in result.stdout.splitlines()
             if re.match(r'^/usr/(s?bin)/[^/]+$', p) and os.access(p, os.X_OK)]
    for p in paths:
        print(('\033[38;5;81m  ' + p + '\033[0m') if use_colour() else '  ' + p)
    tool_help(package)
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
        subprocess.Popen([terminal, '--disable-server', '--color-text=#E6E6E6',
                          '--color-bg=#121214', '--title=Audit — ' + package,
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
    from gi.repository import Gtk, Gdk, GdkPixbuf
    if not Gtk.init_check()[0]:
        raise SystemExit('Outils d’audit : aucun affichage graphique disponible.')
    window = Gtk.Window(title='Outils d’audit — LexOS Pro')
    window.set_name('lexos-audit-menu')
    window.set_default_size(720, 540)
    window.set_position(Gtk.WindowPosition.MOUSE)
    if LOGO.is_file():
        window.set_icon_from_file(str(LOGO))
    else:
        window.set_icon_name('lexos-kali-audit')
    window.connect('destroy', Gtk.main_quit)
    def keyboard(_window, event):
        if event.keyval == Gdk.KEY_Escape:
            window.destroy()
            return True
        return False
    window.connect('key-press-event', keyboard)
    css = Gtk.CssProvider()
    css.load_from_data(b"""
        #lexos-audit-menu, #lexos-audit-menu box,
        #lexos-audit-menu list, #lexos-audit-menu viewport {
            background-color: #121214; color: #eeeeee;
        }
        #lexos-audit-menu label { color: #eeeeee; }
        #lexos-audit-menu entry { background: #202024; color: #eeeeee; }
        #lexos-audit-menu row { border-radius: 4px; padding: 5px; }
        #lexos-audit-menu row:hover { background-color: #303036; }
        #lexos-audit-menu row:selected { background-color: #874000; }
        #lexos-audit-menu row:selected label { color: #ffffff; }
        #lexos-audit-menu row:disabled label { color: #999999; }
        #lexos-audit-menu .audit-heading { color: #ff9c32; font-weight: bold; }
    """)
    Gtk.StyleContext.add_provider_for_screen(window.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.set_border_width(10)
    window.add(box)
    search = Gtk.SearchEntry(placeholder_text='Rechercher un outil ou une catégorie…')
    box.pack_start(search, False, False, 0)
    split = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
    split.set_position(260)
    box.pack_start(split, True, True, 0)
    sidebar_scroll = Gtk.ScrolledWindow()
    sidebar_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    split.pack1(sidebar_scroll, False, False)
    sidebar = Gtk.ListBox()
    sidebar.set_selection_mode(Gtk.SelectionMode.SINGLE)
    sidebar_scroll.add(sidebar)
    right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    right.set_border_width(8)
    split.pack2(right, True, False)
    heading = Gtk.Label(label='Tous les outils', xalign=0)
    heading.get_style_context().add_class('audit-heading')
    right.pack_start(heading, False, False, 0)
    tools_scroll = Gtk.ScrolledWindow()
    tools_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    right.pack_start(tools_scroll, True, True, 0)
    tools = Gtk.ListBox()
    tools.set_selection_mode(Gtk.SelectionMode.NONE)
    tools_scroll.add(tools)
    groups = catalogue()
    categories = [None] + list(groups)
    for number, category in enumerate(categories):
        row = Gtk.ListBoxRow()
        label = Gtk.Label(label='Tous les outils' if category is None else f'{number:02d} · {category}', xalign=0)
        label.set_line_wrap(True)
        row.add(label)
        sidebar.add(row)
    rows = []
    theme = Gtk.IconTheme.get_default()
    for category, packages in groups.items():
        for package in packages:
            available = installed(package)
            row = Gtk.ListBoxRow()
            row.set_activatable(available)
            row.set_sensitive(available)
            line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            icon = package if theme.has_icon(package) else ('application-x-executable' if package in GUI else 'utilities-terminal')
            line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            label = Gtk.Label(label=package + (' — non installé' if not available else ''), xalign=0)
            line.pack_start(label, True, True, 0)
            row.add(line)
            row.set_tooltip_text('Ouvrir l’application' if package in GUI else 'Ouvrir le terminal d’audit')
            row.audit_package = package
            tools.add(row)
            rows.append((category, package, row))
    tools.connect('row-activated', lambda _list, row: activate(row, row.audit_package, window))
    empty = Gtk.Label(label='Aucun outil trouvé.', xalign=0)
    right.pack_start(empty, False, False, 0)
    footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    if LOGO.is_file():
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(LOGO), 36, 44, True)
            footer.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
        except Exception:
            pass
    footer.pack_start(Gtk.Label(label='Outils d’audit · LexOS Pro', xalign=0), True, True, 0)
    close = Gtk.Button(label='Fermer')
    close.connect('clicked', lambda _button: window.destroy())
    footer.pack_end(close, False, False, 0)
    box.pack_end(footer, False, False, 0)
    def refresh(*_args):
        query = search.get_text().casefold().strip()
        selected = sidebar.get_selected_row()
        category = categories[selected.get_index()] if selected else None
        count = 0
        for group, package, row in rows:
            match = ((query in package.casefold() or query in group.casefold()) if query
                     else category is None or category == group)
            row.set_visible(match)
            count += match
        heading.set_text(('Résultats de recherche' if query else category or 'Tous les outils') + f' ({count})')
        empty.set_visible(count == 0)
    search.connect('search-changed', refresh)
    sidebar.connect('row-selected', refresh)
    window.show_all()
    sidebar.select_row(sidebar.get_row_at_index(0))
    refresh()
    search.grab_focus()
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
    parser.add_argument('--colorer-aide', action='store_true', help='Colorer une aide reçue sur stdin')
    args = parser.parse_args()
    if args.colorer_aide:
        print(colour_help(sys.stdin.read(), use_colour()), end='')
    elif args.installer_squelette is not None:
        skeleton(args.installer_squelette)
    elif args.console:
        if args.console not in {p for group in catalogue().values() for p in group}:
            parser.error('Outil inconnu')
        console(args.console)
    else:
        show()
