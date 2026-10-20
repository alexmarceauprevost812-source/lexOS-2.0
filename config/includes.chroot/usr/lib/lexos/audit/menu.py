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

# Images du paquet source Kali, téléchargées volontairement et vérifiées
# par SHA-256 : aucune dépendance obligatoire au réseau.
# Le catalogue est importé par des bancs d'essai hors de son répertoire.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from icones import icone_locale

DATA = Path('/usr/share/lexos/audit-tools.packages')
DESKTOP = 'lexos-audit.desktop'
LOGO = Path('/usr/share/lexos/audit-kali-logo.png')
GUI = {'johnny': 'johnny', 'wireshark': 'wireshark', 'zenmap': 'zenmap',
       'ophcrack': 'ophcrack'}
LABELS = {'Reseau et DNS': 'Réseau et DNS',
          'Analyse de fichiers et recuperation': 'Analyse de fichiers et récupération',
          'Debogage et inspection': 'Débogage et inspection',
          'Audit systeme et donnees': 'Audit système et données'}
EMOJIS = {'Réseau et DNS': '🌐', 'Web et protocoles': '🌍',
          'Wi-Fi et interfaces': '📡', 'Mots de passe': '🔑',
          'Analyse de fichiers et récupération': '📁',
          'Débogage et inspection': '🔧', 'Audit système et données': '🛡️'}


def titre_categorie(nom):
    return f"{EMOJIS.get(nom, '🧰')} {nom}"


def catalogue(path=None):
    if path is None:
        path = DATA
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


def paquets_installes(paquets):
    """UNE seule question à dpkg pour tous les outils (au lieu d'une par
    outil : 277 appels, c'était les ~4 secondes d'attente à l'ouverture)."""
    paquets = [x for x in paquets if x != 'johnny']
    dispo = set()
    if paquets:
        try:
            p = subprocess.run(['dpkg-query', '-W', '-f=${Package} ${Status}\\n', *paquets],
                               capture_output=True, text=True, timeout=10)
            for ligne in p.stdout.splitlines():
                nom, _, etat = ligne.partition(' ')
                if etat == 'install ok installed':
                    dispo.add(nom.split(':')[0])
        except (OSError, subprocess.SubprocessError):
            pass
    if shutil.which('johnny'):
        dispo.add('johnny')
    return dispo


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


def commandes_package(paquet: str, liste_fichiers: str | None = None) -> list[str]:
    """Les commandes RÉELLEMENT installées par un paquet, sans les exécuter.

    Ni options d'attaque, ni commandes construites par supposition : seulement
    les exécutables lus dans la base dpkg. L'ordre est stable et les doublons
    sont éliminés, y compris sur Debian usrmerge.
    """
    if paquet == "johnny":
        executable = shutil.which("johnny")
        return [executable] if executable else []
    if liste_fichiers is None:
        if not re.fullmatch(r"[a-z0-9][a-z0-9.+-]*", paquet):
            return []
        try:
            r = subprocess.run(
                ["dpkg-query", "-L", paquet], capture_output=True,
                text=True, timeout=6, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return []
        if r.returncode != 0:
            return []
        liste_fichiers = r.stdout
    programmes = set()
    for ligne in liste_fichiers.splitlines():
        if not re.fullmatch(
                r"/(?:usr/(?:local/)?(?:s?bin)|s?bin)/[^/]+", ligne):
            continue
        if not os.access(ligne, os.X_OK):
            continue
        programmes.add(ligne)
    return sorted(programmes, key=lambda nom: (Path(nom).name.lower(), nom))


def toutes_commandes(groupes=None, ecrire=print) -> int:
    """Catalogue lecture seule de tous les exécutables des 100 entrées."""
    groupes = groupes if groupes is not None else catalogue()
    nombre = 0
    for categorie, paquets in groupes.items():
        ecrire("\n" + categorie)
        ecrire("=" * len(categorie))
        for paquet in paquets:
            if not installed(paquet):
                ecrire("  " + paquet + " — non installé")
                continue
            commandes = commandes_package(paquet)
            ecrire("  " + paquet + " :")
            if not commandes:
                ecrire("    Aucune commande directe détectée dans les chemins système.")
            for commande in commandes:
                ecrire("    " + commande)
            nombre += len(commandes)
    ecrire("\n%d commandes exécutables recensées (aucune lancée)." % nombre)
    return nombre


def logo_banner(package, files, stream=None):
    stream = stream or sys.stdout
    colour = stream.isatty() and not os.environ.get('NO_COLOR') and os.environ.get('TERM') != 'dumb'
    if colour:
        #  Le TITRE porte « LexOS » : il prend le vert de l'invite. Les deux
        #  filets sont décoratifs : ils gardent l'accent du thème.
        filet = '\033[1;%sm%s\033[0m' % (_accent(), '━' * 44)
        titre = '\033[1;%sm  %s · Outils d’audit LexOS\033[0m' % (_role('LOGO', '38;5;35'), package)
        print(filet + '\n' + titre + '\n' + filet, file=stream)
    else:
        print(package + ' · Outils d’audit LexOS', file=stream)
    if not colour:
        return
    image = icone_locale(package) or tool_logo(package, files)
    if image is None:
        return
    #  ⚠ L'ICÔNE EST DESSINÉE EN COULEUR VRAIE — on ne la tente donc QUE si le
    #  terminal l'annonce. Sans ce test, une console texte ou un vieux ssh
    #  affiche « 38;2;18;18;20m▀ » en clair, caractère par caractère, sur
    #  vingt-quatre lignes. C'est la règle que interactive.sh applique à
    #  l'invite depuis longtemps ; ce fichier-ci ne l'avait jamais appliquée.
    #  Le menu reste entier sans l'icône : elle est décorative.
    if not _vrai_couleur():
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


#  ═══ LES COULEURS VIENNENT DU THÈME, PLUS DE CE FICHIER ═══
#  ALEX : « la couleur de marceau pour l'orange et le vert pour LEXOS », puis
#  « les couleurs, on les retrouve dans les autres terminaux aussi ».
#  Ce menu écrivait « LexOS » en 1;38;5;208 — l'orange que l'invite donne
#  maintenant au NOM de l'utilisateur. Les deux rôles étaient inversés : le
#  mot LexOS est une IDENTITÉ, il prend le vert de l'invite ; l'accent reste
#  l'accent, pour ce qui est décoratif.
#  On lit donc ~/.config/lexos/terminal.env, le fichier que lexos-theme-gen
#  écrit et que l'invite relit — jamais une valeur recopiée ici, sinon ce
#  menu et l'invite finiraient par dire deux verts différents. Même motif
#  qu'ia-agent.py, qui a déjà fait ce chemin.
def _terminal_env():
    """Lit terminal.env SANS l'exécuter : c'est un fichier que bash source,
    mais nous n'avons pas à lui donner ce pouvoir pour trois couleurs. Un
    fichier absent ou tordu rend {} — le menu doit s'afficher quand même."""
    base = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    valeurs = {}
    try:
        with open(os.path.join(base, 'lexos', 'terminal.env'), encoding='utf-8') as f:
            for ligne in f:
                ligne = ligne.strip()
                if not ligne or ligne.startswith('#') or '=' not in ligne:
                    continue
                cle, _, val = ligne.partition('=')
                valeurs[cle.strip()] = val.strip().strip("'\"")
    except (OSError, UnicodeDecodeError):
        pass
    return valeurs


def _vrai_couleur():
    """Le terminal annonce-t-il la couleur vraie ? Même bascule que
    __lexos_couleurs dans interactive.sh : la console texte afficherait
    « 38;2;… » en clair au milieu du menu."""
    return os.environ.get('COLORTERM', '') in ('truecolor', '24bit')


def _role(nom, repli):
    """La séquence SGR d'un rôle de l'invite (MACHINE, LOGO, UTILISATEUR…),
    en couleur vraie si le terminal la comprend, en palette 256 sinon."""
    env = _terminal_env()
    cle = 'LEXOS_PS_%s' % nom if _vrai_couleur() else 'LEXOS_PS_%s_256' % nom
    return env.get(cle) or repli


def _accent(repli='38;5;208'):
    """L'accent du thème — curseur, sélection, onglet actif.

    IL SE LIT COMME LES SIX AUTRES RÔLES, ET C'EST NEUF. Avant, cette
    fonction convertissait elle-même LEXOS_TERM_CURSEUR, qui est rangé en
    #RRGGBB — elle n'y arrivait donc QUE sous COLORTERM, et la palette 256
    gardait le 208 de nuit quel que soit le thème. Sur la console texte en
    thème de jour, les titres de ce menu sortaient en orange vif sur le
    crème : 2,21:1, sous le seuil AA de 4,5. Le générateur écrit maintenant
    LEXOS_PS_ACCENT et LEXOS_PS_ACCENT_256 (94 de jour, 5,26:1 ; 208 de
    nuit, inchangé) — il n'y a plus rien à convertir ici."""
    return _role('ACCENT', repli)


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
            #  Titre de section d'une aide tierce : décoratif, donc l'accent
            #  du thème — et non plus un 208 figé, qui laissait un menu orange
            #  à qui a choisi « lexos accent bleu ».
            result.append('\033[1;' + _accent() + 'm' + body + '\033[0m' + line[len(body):])
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
    # Fiche courte : l'image reste visible, sans une longue aide automatique.
    result = subprocess.run(['dpkg-query', '-L', package], capture_output=True, text=True)
    if use_colour():
        print('\033[2J\033[H', end='', flush=True)
    logo_banner(package, result.stdout.splitlines())
    notice = 'Aucune opération lancée. Exécutables fournis par le paquet :'
    print(('\033[38;5;250m' + notice + '\033[0m') if use_colour() else notice, flush=True)
    paths = commandes_package(package, result.stdout)
    for p in paths[:8]:
        print(('\033[38;5;81m  ' + p + '\033[0m') if use_colour() else '  ' + p)
    if len(paths) > 8:
        print(f'  … {len(paths) - 8} autres : bouton « Commandes » dans le menu.')
    print('\nAide : man NOM_DE_COMMANDE. Tape exit pour fermer.\n', flush=True)
    os.execv('/bin/bash', ['/bin/bash', '-i'])


def menu_terminal(lire=input, ecrire=print):
    """Navigateur texte des 100 entrées, dans LexOS Pro Terminal.

    Les entrées sont exclusivement les noms du manifeste audité. Aucun choix
    n'exécute nmap, hashcat, john ou un autre outil : seule la liste de fichiers
    du paquet est consultée pour indiquer où trouver ses commandes.
    Ctrl+C ou fin de l'entrée retourne proprement au shell.
    """
    groupes = catalogue()
    noms = list(groupes)
    ecrire("\n\033[1;%sm⚜ LexOS Pro · Catalogue d'audit\033[0m" % _role('LOGO', '38;5;35'))
    ecrire("Consultation seulement — aucun outil n'est exécuté automatiquement.")
    def demander(texte):
        try:
            return lire(texte).strip().lower()
        except (KeyboardInterrupt, EOFError):
            return "q"

    while True:
        ecrire("\nCatégories :")
        for numero, categorie in enumerate(noms, 1):
            ecrire(f"  {numero:2}. {titre_categorie(categorie)} ({len(groupes[categorie])})")
        entree = demander("Catégorie [numéro, q pour quitter] : ")
        if entree in ("q", "quitter", "exit", "0"):
            return
        if not entree.isascii() or not entree.isdecimal():
            ecrire("Choisis un numéro valide.")
            continue
        indice = int(entree)
        if indice < 1 or indice > len(noms):
            ecrire("Catégorie inconnue.")
            continue
        nom = noms[indice - 1]
        paquets = groupes[nom]
        while True:
            ecrire("\n\033[1;%sm%s\033[0m" % (_accent(), titre_categorie(nom)))
            for numero, paquet in enumerate(paquets, 1):
                ecrire(f"  {numero:2}. {paquet}")
            entree = demander("Paquet [numéro, b retour, q quitter] : ")
            if entree in ("q", "quitter", "exit", "0"):
                return
            if entree in ("b", "retour", ""):
                break
            if not entree.isascii() or not entree.isdecimal():
                ecrire("Choisis un numéro valide.")
                continue
            choix = int(entree)
            if choix < 1 or choix > len(paquets):
                ecrire("Paquet inconnu.")
                continue
            paquet = paquets[choix - 1]
            if not installed(paquet):
                ecrire(f"{paquet} : non installé. Aucune opération lancée.")
                continue
            if paquet == "johnny":
                ecrire("johnny : interface graphique installée (aucun démarrage automatique).")
                continue
            chemins = commandes_package(paquet)
            # Si une icône Kali vérifiée existe, la rendre sans protocole
            # propriétaire : de petits blocs de couleur ANSI. Sinon titre.
            # La fiche commence en haut du terminal après sélection.
            if use_colour():
                ecrire('\033[2J\033[H')
            logo_banner(paquet, [])
            ecrire(f"\n{paquet} : exécutables installés :")
            for chemin in chemins:
                ecrire("  " + chemin)
            if not chemins:
                ecrire("  Aucun exécutable direct détecté.")
            ecrire("Tu restes dans ton terminal habituel. Aucun outil n'a été lancé.")


def launch(package):
    if package in GUI:
        executable = shutil.which(GUI[package])
        if not executable:
            raise RuntimeError('Application indisponible : ' + package)
        subprocess.Popen([executable])
    else:
        # Une seule application de terminal pour tout LexOS. Le menu GTK
        # reste un catalogue facultatif, mais ses fiches s'ouvrent désormais
        # dans LexOS Pro Terminal au lieu de xfce4-terminal.
        terminal = shutil.which('lexos-pro-terminal')
        if not terminal:
            raise RuntimeError('LexOS Pro Terminal est indisponible.')
        subprocess.Popen([terminal, '-e', '/usr/bin/python3',
                          str(Path(__file__).resolve()), '--console', package])


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


def montrer_commandes(paquet, fenetre, Gtk):
    """Fenêtre consultable et copiable ; ne lance AUCUN exécutable d'audit."""
    chemins = commandes_package(paquet)
    texte = (
        "Commandes réellement installées : " + paquet + "\n\n"
        + ("\n".join(chemins) if chemins else
           "Aucune commande directe dans les dossiers exécutables classiques.")
        + "\n\nListe informative : aucune analyse lancée."
    )
    fen = Gtk.Dialog(
        title="Commandes disponibles — " + paquet,
        transient_for=fenetre, flags=Gtk.DialogFlags.MODAL)
    fen.set_name('lexos-audit-menu')
    fen.add_button("Fermer", Gtk.ResponseType.CLOSE).get_style_context().add_class('audit-principal')
    fen.set_default_size(680, 440)
    defile = Gtk.ScrolledWindow()
    defile.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
    defile.set_hexpand(True)
    defile.set_vexpand(True)
    texte_vue = Gtk.TextView()
    texte_vue.set_editable(False)
    texte_vue.set_cursor_visible(False)
    texte_vue.set_monospace(True)
    texte_vue.get_buffer().set_text(texte)
    defile.add(texte_vue)
    fen.get_content_area().pack_start(defile, True, True, 8)
    fen.show_all()
    try:
        fen.run()
    finally:
        fen.destroy()


REGLAGES_BUREAU = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'lexos' / 'bureau.json'
MASCOTTE = Path('/usr/lib/lexos/bureau/web/mascotte-audit.png')
ACCENT_LEXOS = '#ff7a18'
DESCENTE_MS = 480        # le panneau qui se baisse
APPARITION_MS = 420      # puis le menu s'allume comme une vieille télé
#  Total ≈ 0,9 s : tout est là en moins d'une seconde.


def accent_bureau(chemin=None):
    """La couleur d'accent choisie dans les Paramètres du bureau LexOS
    (~/.config/lexos/bureau.json), pour que la fenêtre ait le MÊME orange
    que la plateforme. L'arc-en-ciel ou un fichier absent → orange LexOS."""
    import json
    try:
        valeur = json.loads(Path(chemin or REGLAGES_BUREAU).read_text()).get('accent', '')
    except (OSError, ValueError, AttributeError):
        return ACCENT_LEXOS
    return valeur.lower() if re.fullmatch(r'#[0-9a-fA-F]{6}', str(valeur)) else ACCENT_LEXOS


def _rgb(hexa):
    return tuple(int(hexa[i:i + 2], 16) for i in (1, 3, 5))


def _melanger(hexa, autre, t):
    a, b = _rgb(hexa), _rgb(autre)
    return '#' + ''.join(f'{round(x + (y - x) * t):02x}' for x, y in zip(a, b))


def css_audit(accent=ACCENT_LEXOS):
    """Le thème de la fenêtre : verre noir, liseré et boutons orange LexOS —
    les mêmes couleurs que la barre « Mes outils » (outils.css)."""
    r, g, b = _rgb(accent)
    clair = _melanger(accent, '#ffffff', .35)
    fonce = _melanger(accent, '#000000', .22)
    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    sur = '#0a0a0a' if lum > .45 else '#ffffff'
    a = lambda x: f'rgba({r},{g},{b},{x})'
    return f"""
        window#lexos-audit-menu {{ background-color: transparent; }}
        dialog#lexos-audit-menu, window.dialog#lexos-audit-menu {{ background-color: #0e0e0f; }}
        #lexos-audit-menu * {{ font-family: "LX Space Grotesk", "Space Grotesk", "Cantarell", sans-serif; }}
        #lexos-audit-menu .carte {{
            background-color: #0e0e0f;
            background-image: linear-gradient(180deg, rgba(22,22,24,0.99), rgba(9,9,10,0.995));
            border: 1px solid {a(.45)}; border-radius: 18px;
            box-shadow: 0 10px 26px rgba(0,0,0,0.6), 0 0 18px {a(.18)};
        }}
        #lexos-audit-menu .carte box, #lexos-audit-menu list, #lexos-audit-menu viewport,
        #lexos-audit-menu scrolledwindow, #lexos-audit-menu paned {{
            background-color: transparent; background-image: none; color: #e9e9ec;
        }}
        #lexos-audit-menu .tete {{ padding: 10px 12px 8px 14px; }}
        #lexos-audit-menu .tete-titre {{ font-size: 17px; color: #ffffff; }}
        #lexos-audit-menu .lueur {{
            min-height: 2px; margin: 0 60px; border-radius: 2px;
            background-image: linear-gradient(90deg, transparent, {accent}, {clair}, {accent}, transparent);
            box-shadow: 0 0 12px {a(.8)};
        }}
        #lexos-audit-menu label {{ color: #e9e9ec; }}
        #lexos-audit-menu entry {{
            background-color: #161617; background-image: none; color: #ffffff;
            border: 1px solid {a(.32)}; border-radius: 12px; padding: 6px 10px; box-shadow: none;
        }}
        #lexos-audit-menu entry:focus {{ border-color: {accent}; box-shadow: 0 0 10px {a(.35)}; }}
        #lexos-audit-menu entry image {{ color: {accent}; }}
        #lexos-audit-menu row {{ border-radius: 10px; padding: 6px 8px; transition: all 200ms ease; }}
        #lexos-audit-menu row:hover {{ background-color: {a(.12)}; }}
        #lexos-audit-menu row:selected {{
            background-color: {accent};
            background-image: linear-gradient(90deg, {accent}, {fonce});
            box-shadow: 0 0 12px {a(.4)};
        }}
        #lexos-audit-menu row:selected label {{ color: {sur}; font-weight: bold; }}
        #lexos-audit-menu row:disabled label {{ color: #6f6f76; }}
        #lexos-audit-menu .audit-heading {{ color: {clair}; font-weight: bold; font-size: 15px; }}
        #lexos-audit-menu button {{
            background-color: #1a1a1d; background-image: none; color: #e9e9ec;
            border: 1px solid {a(.35)}; border-radius: 10px; box-shadow: none;
            text-shadow: none; -gtk-icon-shadow: none; padding: 5px 14px;
            transition: all 220ms ease;
        }}
        #lexos-audit-menu button:hover {{
            background-color: {a(.2)}; border-color: {accent}; color: #ffffff;
            box-shadow: 0 0 10px {a(.35)};
        }}
        #lexos-audit-menu button:active {{ background-color: {a(.35)}; }}
        #lexos-audit-menu button.audit-principal {{
            background-color: {accent}; background-image: linear-gradient(180deg, {clair}, {accent});
            color: {sur}; border-color: {accent}; font-weight: bold;
        }}
        #lexos-audit-menu button.audit-principal label {{ color: {sur}; }}
        #lexos-audit-menu button.audit-x {{ border-radius: 50%; padding: 2px 9px; min-width: 0; min-height: 0; }}
        #lexos-audit-menu button.audit-x:hover {{ background-color: {accent}; color: {sur}; }}
        #lexos-audit-menu paned > separator {{ background-color: #26262a; background-image: none; min-width: 1px; padding: 0; margin: 0; border: none; box-shadow: none; }}
        #lexos-audit-menu scrollbar {{ background-color: transparent; border: none; }}
        #lexos-audit-menu scrollbar slider {{ background-color: {a(.45)}; border-radius: 8px; min-width: 6px; border: none; }}
        #lexos-audit-menu scrollbar slider:hover {{ background-color: {accent}; }}
        #lexos-audit-menu textview, #lexos-audit-menu textview text {{
            background-color: #0e0e0f; color: #e9e9ec;
        }}
        #lexos-audit-menu tooltip, tooltip {{ background-color: #161617; color: #ffffff; border: 1px solid {a(.4)}; border-radius: 8px; }}
    """.encode()


def _animer(duree_ms, pas, fin=None):
    """Appelle pas(t) avec t de 0 à 1 (adouci), à ~60 images/s."""
    from gi.repository import GLib
    import time
    debut = time.monotonic()
    def tic():
        t = min(1.0, (time.monotonic() - debut) * 1000 / max(1, duree_ms))
        pas(1 - (1 - t) ** 3)
        if t >= 1:
            if fin:
                fin()
            return False
        return True
    GLib.timeout_add(16, tic)


def show():
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, GdkPixbuf, GLib
    if not Gtk.init_check()[0]:
        raise SystemExit('Outils d’audit : aucun affichage graphique disponible.')
    accent = accent_bureau()
    # XFCE peut couper les animations GTK (xsettings « EnableAnimations ») :
    # le rideau sautait alors directement à la fin. Pour CETTE fenêtre, on
    # les rallume — la descente doit se voir.
    try:
        Gtk.Settings.get_default().set_property('gtk-enable-animations', True)
    except Exception:
        pass
    window = Gtk.Window(title='Outils d’audit — LexOS Pro')
    window.set_name('lexos-audit-menu')
    # Sans la barre de titre du vieux thème : notre propre en-tête orange.
    window.set_decorated(False)
    window.set_app_paintable(True)
    ecran = window.get_screen()
    compose = ecran.is_composited()
    visuel = ecran.get_rgba_visual()
    if visuel is not None and compose:
        window.set_visual(visuel)
    LARGEUR, HAUTEUR, MARGE = 780, 600, 16
    window.set_default_size(LARGEUR + 2 * MARGE, HAUTEUR + 2 * MARGE)
    # Taille FIXE pendant que le rideau descend : sinon la fenêtre se
    # redimensionnerait à chaque image et l'animation saccaderait.
    window.set_size_request(LARGEUR + 2 * MARGE, HAUTEUR + 2 * MARGE)
    window.set_resizable(False)
    if LOGO.is_file():
        window.set_icon_from_file(str(LOGO))
    else:
        window.set_icon_name('lexos-kali-audit')
    window.connect('destroy', Gtk.main_quit)
    css = Gtk.CssProvider()
    css.load_from_data(css_audit(accent))
    Gtk.StyleContext.add_provider_for_screen(ecran, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    # ── Le panneau qui se baisse : un Revealer « glisse vers le bas » ──
    rideau = Gtk.Revealer()
    rideau.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
    rideau.set_transition_duration(DESCENTE_MS if compose else 0)
    rideau.set_valign(Gtk.Align.START)
    window.add(rideau)
    carte = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    carte.get_style_context().add_class('carte')
    carte.set_margin_start(MARGE)
    carte.set_margin_end(MARGE)
    carte.set_margin_bottom(MARGE)
    carte.set_size_request(LARGEUR, HAUTEUR)
    rideau.add(carte)

    # En-tête : la mascotte, le titre, ✕ — on peut traîner la fenêtre par là.
    poignee = Gtk.EventBox()
    tete = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    tete.get_style_context().add_class('tete')
    poignee.add(tete)
    image_tete = MASCOTTE if MASCOTTE.is_file() else LOGO
    if image_tete.is_file():
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(image_tete), 40, 40, True)
            tete.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
        except Exception:
            pass
    titre = Gtk.Label(xalign=0)
    titre.set_markup(f'Outils <span foreground="{accent}" weight="bold">d’audit</span>'
                     '  <span foreground="#9a9aa2" size="small">LexOS Pro</span>')
    titre.get_style_context().add_class('tete-titre')
    tete.pack_start(titre, True, True, 0)
    croix = Gtk.Button(label='✕')
    croix.get_style_context().add_class('audit-x')
    croix.set_tooltip_text('Fermer (Échap)')
    croix.set_valign(Gtk.Align.CENTER)
    tete.pack_end(croix, False, False, 0)
    def trainer(_widget, event):
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            window.begin_move_drag(event.button, int(event.x_root), int(event.y_root), event.time)
        return False
    poignee.connect('button-press-event', trainer)
    carte.pack_start(poignee, False, False, 0)
    lueur = Gtk.Box()
    lueur.get_style_context().add_class('lueur')
    carte.pack_start(lueur, False, False, 0)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.set_border_width(12)
    # La « vieille télé » : un écran noir posé PAR-DESSUS le menu. Une ligne
    # lumineuse s'étire au centre, puis s'ouvre en hauteur et dévoile le menu.
    ecran_tele = Gtk.Overlay()
    ecran_tele.add(box)
    tele = Gtk.DrawingArea()
    tele.set_halign(Gtk.Align.FILL)
    tele.set_valign(Gtk.Align.FILL)
    tele.progres = 0.0
    ar, ag, ab = (x / 255 for x in _rgb(accent))
    def dessiner_tele(zone, cr):
        p = zone.progres
        w, h = zone.get_allocated_width(), zone.get_allocated_height()
        if p >= 1:
            return False
        if p < .35:                       # 1) le point devient une ligne
            q = p / .35
            cr.set_source_rgb(0.03, 0.03, 0.035)
            cr.paint()
            lw = w * (0.04 + 0.96 * q)
            cr.set_source_rgba(1, 1, 1, .95)
            cr.rectangle((w - lw) / 2, h / 2 - 1.5, lw, 3)
            cr.fill()
            cr.set_source_rgba(ar, ag, ab, .55)
            cr.rectangle((w - lw) / 2, h / 2 - 7, lw, 14)
            cr.fill()
        else:                             # 2) la ligne s'ouvre en hauteur
            q = (p - .35) / .65
            ouvert = h * q
            haut = (h - ouvert) / 2
            cr.set_source_rgb(0.03, 0.03, 0.035)
            cr.rectangle(0, 0, w, haut)
            cr.rectangle(0, haut + ouvert, w, haut + 1)
            cr.fill()
            cr.set_source_rgba(1, 1, 1, .25 * (1 - q))   # éclair qui s'éteint
            cr.rectangle(0, haut, w, ouvert)
            cr.fill()
            cr.set_source_rgba(0, 0, 0, .18 * (1 - q))   # lignes de balayage
            for y in range(int(haut), int(haut + ouvert), 3):
                cr.rectangle(0, y, w, 1)
            cr.fill()
            for bord in (haut, haut + ouvert):            # bords lumineux
                cr.set_source_rgba(ar, ag, ab, .7 * (1 - q))
                cr.rectangle(0, bord - 1.5, w, 3)
                cr.fill()
        return False
    tele.connect('draw', dessiner_tele)
    try:                 # le dessin de la télé a besoin de python3-gi-cairo
        gi.require_foreign('cairo')
        ecran_tele.add_overlay(tele)
        ecran_tele.set_overlay_pass_through(tele, True)
    except (ImportError, AttributeError):
        tele = None
    carte.pack_start(ecran_tele, True, True, 0)
    window.audit_contenu = box
    search = Gtk.SearchEntry(placeholder_text='Rechercher un outil ou une catégorie…')
    box.pack_start(search, False, False, 0)
    split = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
    split.set_position(260)
    split.set_wide_handle(False)
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
    for category in categories:
        row = Gtk.ListBoxRow()
        label = Gtk.Label(label='🧰 Tous les outils' if category is None else titre_categorie(category), xalign=0)
        label.set_line_wrap(True)
        row.add(label)
        sidebar.add(row)
    rows = []
    theme = Gtk.IconTheme.get_default()
    dispo = paquets_installes([x for paquets in groups.values() for x in paquets])
    for category, packages in groups.items():
        for package in packages:
            available = package in dispo
            row = Gtk.ListBoxRow()
            row.set_activatable(available)
            row.set_sensitive(available)
            line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            logo = icone_locale(package)
            image = None
            if logo:
                # Le SVG officiel peut faire 512 px : il doit être RENDU en
                # vignette 36x36, sinon toute la liste grandit d'un coup.
                # Si librsvg manque, revenir à l'icône GTK existante.
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        str(logo), 36, 36, True)
                    image = Gtk.Image.new_from_pixbuf(pixbuf)
                except Exception:
                    image = None
            if image is None:
                icon = (package if theme.has_icon(package) else
                        ('application-x-executable' if package in GUI else 'utilities-terminal'))
                image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
            line.pack_start(image, False, False, 0)
            label = Gtk.Label(label=package + (' — non installé' if not available else ''), xalign=0)
            line.pack_start(label, True, True, 0)
            if available:
                ouvrir = Gtk.Button(label="Ouvrir" if package in GUI else "Terminal")
                ouvrir.set_tooltip_text('Ouvrir cet outil' if package in GUI else
                                        'Ouvrir la fiche avec son image en haut du terminal')
                ouvrir.connect('clicked', lambda _bouton, p=package: activate(None, p, window))
                line.pack_end(ouvrir, False, False, 0)
                bouton = Gtk.Button(label="Commandes")
                bouton.set_tooltip_text("Afficher toutes les commandes installées — lecture seule")
                bouton.connect(
                    'clicked',
                    lambda _bouton, p=package: montrer_commandes(p, window, Gtk))
                line.pack_end(bouton, False, False, 0)
            row.add(line)
            row.set_tooltip_text('Ouvrir l’application' if package in GUI else 'Ouvrir une fiche dans LexOS Pro Terminal')
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
    close.get_style_context().add_class('audit-principal')
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
        heading.set_text(('Résultats de recherche' if query else titre_categorie(category) if category else '🧰 Tous les outils') + f' ({count})')
        empty.set_visible(count == 0)
    search.connect('search-changed', refresh)
    sidebar.connect('row-selected', refresh)

    # ── Fermer en douceur : le menu s'efface, le panneau remonte ──
    fermeture = {'en_cours': False}
    def fermer(*_args):
        if fermeture['en_cours']:
            return True
        fermeture['en_cours'] = True
        def remonter():
            if not compose:
                x, y = cible['x'], cible['y']
                depart = y
                _animer(int(DESCENTE_MS * .6),
                        lambda t: window.move(x, round(depart + (cible['haut'] - depart) * t)),
                        window.destroy)
                return
            rideau.set_transition_duration(int(DESCENTE_MS * .6))
            rideau.set_reveal_child(False)
            GLib.timeout_add(int(DESCENTE_MS * .6) + 120, lambda: (window.destroy(), False)[1])
        _animer(140, lambda t: box.set_opacity(1 - t), remonter)
        return True
    croix.connect('clicked', fermer)
    close.connect('clicked', fermer)
    def keyboard(_window, event):
        if event.keyval == Gdk.KEY_Escape:
            return fermer()
        return False
    window.connect('key-press-event', keyboard)

    # ── Placée en haut, centrée sur l'écran où est la souris ──
    cible = {'x': 0, 'y': 0, 'haut': -700}
    def placer():
        affichage = Gdk.Display.get_default()
        moniteur = None
        try:
            _ecran, px, py = affichage.get_default_seat().get_pointer().get_position()[:3]
            moniteur = affichage.get_monitor_at_point(px, py)
        except Exception:
            moniteur = affichage.get_primary_monitor() or affichage.get_monitor(0)
        if moniteur is None:
            window.set_position(Gtk.WindowPosition.CENTER)
            return
        zone = moniteur.get_workarea()
        largeur = LARGEUR + 2 * MARGE
        cible['x'] = zone.x + max(0, (zone.width - largeur) // 2)
        cible['y'] = zone.y + 8
        cible['haut'] = zone.y - (HAUTEUR + 2 * MARGE)
        # Sans compositeur (pas de transparence), c'est la fenêtre entière
        # qui descend : on la pose au-dessus de l'écran, puis on la glisse.
        window.move(cible['x'], cible['y'] if compose else cible['haut'])
    placer()

    # ── Ouvrir : le panneau descend, puis « pouf », le menu apparaît ──
    box.set_opacity(0)
    window.show_all()
    sidebar.select_row(sidebar.get_row_at_index(0))
    refresh()
    search.grab_focus()
    def allumer_tele():
        if tele is None:                  # sans cairo : un simple fondu
            _animer(APPARITION_MS, box.set_opacity)
            return
        box.set_opacity(1)
        def pas(t):
            tele.progres = t
            tele.queue_draw()
        _animer(APPARITION_MS, pas, tele.hide)
    def pouf(*_args):
        if compose and rideau.get_child_revealed() and not fermeture['en_cours']:
            allumer_tele()
    rideau.connect('notify::child-revealed', pouf)
    def descendre():
        rideau.set_reveal_child(True)
        if not compose:
            x, depart = cible['x'], cible['haut']
            _animer(DESCENTE_MS,
                    lambda t: window.move(x, round(depart + (cible['y'] - depart) * t)),
                    allumer_tele)
        return False
    GLib.timeout_add(40, descendre)
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
    parser.add_argument('--terminal', action='store_true',
                        help='Parcourir les outils dans LexOS Pro Terminal')
    parser.add_argument('--toutes-commandes', action='store_true',
                        help='Lister les exécutables installés de toutes les catégories')
    parser.add_argument('--colorer-aide', action='store_true', help='Colorer une aide reçue sur stdin')
    args = parser.parse_args()
    if args.colorer_aide:
        print(colour_help(sys.stdin.read(), use_colour()), end='')
    elif args.installer_squelette is not None:
        skeleton(args.installer_squelette)
    elif args.toutes_commandes:
        toutes_commandes()
    elif args.terminal:
        menu_terminal()
    elif args.console:
        if args.console not in {p for group in catalogue().values() for p in group}:
            parser.error('Outil inconnu')
        console(args.console)
    else:
        show()
