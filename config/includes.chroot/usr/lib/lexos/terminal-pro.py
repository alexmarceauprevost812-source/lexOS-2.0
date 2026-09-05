#!/usr/bin/env python3
"""LexOS Pro Terminal — le pont local qui rend le terminal RÉEL.

ALEX : « c'est le new terminal officiel de LexOS Pro, pour le terminal
normal je veux que ce soit lui qui le remplace. »

Le fichier HTML lui-même (usr/share/lexos/terminal-pro/web/index.html) ne
sait faire qu'une chose de réel : afficher des lignes de texte dans une
fenêtre qui a des onglets et des divisions. Toutes les commandes — ls, cd,
cat, et n'importe quel programme installé — passent par CE pont, qui les
exécute pour de vrai sur la machine, dans un vrai bash.

  ═══ CE QUI NE PEUT PAS MARCHER, ET POURQUOI ON NE LE CACHE PAS ═══

Cette fenêtre n'est pas un émulateur de terminal : elle n'a AUCUNE notion de
grille de caractères, de curseur qu'on déplace, d'écran qu'on efface pour le
redessiner. C'est un journal qui défile, comme un fichier qu'on imprime au
fur et à mesure. Un vrai émulateur (xterm, la Console GNOME, xfce4-terminal)
sait tout ça ; construire cette brique reviendrait à réécrire xterm.js à la
main. Donc :

  · les programmes PLEIN ÉCRAN (vim, nano, htop, less, man, tmux…) ne
    peuvent pas s'afficher correctement ici — LISTE_TUI plus bas les
    reconnaît et renvoie un message clair au lieu d'un carnage de codes
    d'échappement ;
  · une commande qui ATTEND une réponse au clavier en cours de route (le mot
    de passe de sudo, une confirmation tapée) ne peut pas en recevoir : son
    entrée standard est fermée (stdin=DEVNULL). Elle échoue proprement — la
    plupart des programmes bien élevés le détectent et le disent — plutôt
    que de rester bloquée indéfiniment ;
  · les couleurs (SGR : gras, rouge, vert…) sont comprises et rendues ; tout
    le reste des séquences ANSI (déplacer le curseur, effacer l'écran) est
    silencieusement retiré, jamais montré tel quel.

Pour tout ce qui précède, le Terminal classique (xfce4-terminal) reste
installé et atteignable — voir lexos-pro-terminal --classique.

  ═══ SÉCURITÉ : CE PONT EXÉCUTE N'IMPORTE QUELLE COMMANDE, EXPRÈS ═══

C'est un terminal : accepter d'exécuter ce qu'on tape est tout le produit.
Le risque n'est donc pas « la commande », c'est « qui peut atteindre ce
pont ». Trois verrous, tous nécessaires :

  1. Écoute UNIQUEMENT 127.0.0.1 (comme lexos-settings et lexos-cartes) —
     rien n'est visible depuis le réseau.
  2. Un JETON tiré au hasard à chaque lancement (secrets.token_urlsafe),
     jamais écrit sur le disque, exigé dans l'en-tête « X-Lexos-Jeton » de
     CHAQUE requête. Sans lui : 403, rien n'est exécuté.
  3. L'en-tête « Origin » de la requête, quand le navigateur en pose un,
     doit être exactement http://127.0.0.1:<notre port>.

Pourquoi le jeton ET l'Origine, et pas l'un ou l'autre ? Parce qu'une simple
requête POST (Content-Type: text/plain, sans en-tête personnalisé) part
AVANT que le navigateur ne demande la permission CORS — une page malveillante
ouverte dans un vrai navigateur pourrait donc l'envoyer en aveugle même si
elle ne lira jamais la réponse. Exiger un en-tête personnalisé (le jeton)
change la nature de la requête : le navigateur DOIT alors demander la
permission au serveur avant de l'envoyer pour de vrai (une requête
« préparée », preflight), et notre serveur refuse cette permission à toute
origine autre que la sienne. C'est le jeton qui ferme la porte ; l'Origine
n'est qu'une deuxième serrure.
"""
import functools
import html
import http.server
import json
import os
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
import threading
from pathlib import Path

APP_NAME = "LexOS Pro Terminal"
WEB_DIR = Path(os.environ.get("LEXOS_TERMINAL_PRO_WEB",
                               "/usr/share/lexos/terminal-pro/web"))
ICON_PATH = Path("/usr/share/icons/hicolor/128x128/apps/lexos-pro-terminal.png")

#  Délai maximal d'une commande. Filet de sécurité : avec stdin fermé, une
#  commande bien élevée qui attend une réponse échoue tout de suite plutôt
#  que d'attendre — ce délai n'attrape que ce qui boucle ou dort vraiment.
DELAI_MAX = float(os.environ.get("LEXOS_TERMINAL_PRO_DELAI", "25"))

#  ═══ PROGRAMMES PLEIN ÉCRAN — RECONNUS, PAS EXÉCUTÉS ═══
#  Premier mot de la commande (après un éventuel sudo/env). Cette liste ne
#  protège de rien niveau sécurité : c'est un confort, pour ne pas montrer un
#  carnage de codes d'échappement à la place d'un message clair.
LISTE_TUI = frozenset((
    "vim", "vi", "nvim", "nano", "emacs", "pico",
    "htop", "top", "btop", "atop", "iotop", "glances",
    "less", "more", "man", "watch",
    "tmux", "screen", "byobu",
    "mc", "ranger", "nnn", "vifm",
    "w3m", "lynx", "links",
    "irssi", "weechat",
    "bash", "sh", "zsh", "fish", "dash",  # un shell interactif nu : même piège
))


def _premier_mot(commande):
    """Le premier mot qui compte, en sautant « sudo » et les affectations de
    variable (VAR=valeur cmd)."""
    try:
        mots = shlex.split(commande, posix=True)
    except ValueError:
        return ""
    i = 0
    while i < len(mots) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", mots[i]):
        i += 1
    while i < len(mots) and mots[i] in ("sudo", "command", "exec", "nice", "ionice", "time"):
        i += 1
        while i < len(mots) and mots[i].startswith("-"):
            i += 1
    return os.path.basename(mots[i]) if i < len(mots) else ""


#  ═══ ANSI → HTML ═══
#  On ne rend QUE les couleurs (SGR). Tout le reste (curseur, effacement)
#  est retiré, jamais montré tel quel — voir l'en-tête du fichier.
_RE_OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
#  UNE CSI COMPLÈTE (ECMA-48), PAS SEULEMENT « ESC[ chiffres m ». Une
#  première version ne reconnaissait que « \x1b[31m » : « \x1b[?25l »
#  (cacher le curseur — quasi tous les programmes interactifs l'émettent)
#  a des octets de paramètre PRIVÉS (0-9 : ; < = > ?) qu'un « [0-9;]* » ne
#  couvre pas. Ratée, cette séquence ressortait telle quelle, en clair,
#  au lieu d'être retirée comme les autres déplacements de curseur.
_RE_CSI = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])")
#  Tout le reste des échappements à deux ou trois octets qu'on ne traite
#  pas explicitement (RIS, sélection de jeu de caractères…) : retirés, pas
#  montrés — même règle que pour les CSI qui ne sont pas des couleurs.
_RE_AUTRE_ECHAP = re.compile(r"\x1b[ -/]*[0-~]")

_SGR_COULEUR = {
    "30": "s0", "31": "r", "32": "g", "33": "j", "34": "m34",
    "35": "m35", "36": "m36", "37": "t2",
    "90": "s", "91": "r", "92": "g", "93": "j", "94": "m34",
    "95": "m35", "96": "m36", "97": "t2",
}


def ansi_vers_html(texte):
    """Convertit la sortie d'un vrai programme en HTML sûr : chaque
    caractère de contenu passe par html.escape AVANT d'être entouré des
    balises de couleur — jamais l'inverse, sinon un « <script> » affiché par
    « cat » s'exécuterait dans la page."""
    texte = _RE_OSC.sub("", texte)

    #  Une ligne de progression (curl, apt, wget) écrit plusieurs fois la
    #  MÊME ligne séparée par des « \r ». Cette fenêtre n'a pas d'écran à
    #  redessiner : on ne garde que ce qui suit le DERNIER « \r » de chaque
    #  ligne — le résultat final de la barre, pas ses cinquante images.
    lignes = []
    for ligne in texte.split("\n"):
        if "\r" in ligne:
            ligne = ligne.rsplit("\r", 1)[1]
        lignes.append(ligne)
    texte = "\n".join(lignes)

    #  UN SEUL SPAN À LA FOIS, AVEC TOUTES LES CLASSES ACTIVES — pas un span
    #  par code. « \x1b[1;32m » (gras ET vert, une combinaison courante :
    #  git, grep --color, npm…) ouvrait un « <span class="gras"> » jamais
    #  refermé PUIS un « <span class="g"> » : la moitié du reste de la ligne
    #  restait en gras. On calcule maintenant l'ensemble des attributs actifs
    #  après chaque code, et un span ne se rouvre que si cet ensemble change.
    out = []
    pos = 0
    couleur = ""
    gras = False
    span_ouvert = False

    def fermer():
        nonlocal span_ouvert
        if span_ouvert:
            out.append("</span>")
            span_ouvert = False

    def rouvrir():
        nonlocal span_ouvert
        fermer()
        classes = ([ "gras"] if gras else []) + ([couleur] if couleur else [])
        if classes:
            out.append('<span class="' + " ".join(classes) + '">')
            span_ouvert = True

    for m in _RE_CSI.finditer(texte):
        out.append(html.escape(texte[pos:m.start()]))
        pos = m.end()
        params, intermediaires, final = m.group(1), m.group(2), m.group(3)
        #  Seule une SGR PURE (paramètres numériques uniquement, aucun octet
        #  intermédiaire, code final « m ») porte une couleur. Un préfixe
        #  privé (« ? », « < », « = », « > ») ou un octet intermédiaire
        #  signale autre chose (mode du curseur, marges…) : retiré en
        #  silence, comme le déplacement du curseur.
        if final != "m" or intermediaires or not re.fullmatch(r"[0-9;]*", params):
            continue
        codes = [c for c in params.split(";") if c != ""] or ["0"]
        change = False
        for code in codes:
            if code == "0":
                change = change or gras or bool(couleur)
                gras, couleur = False, ""
            elif code == "1":
                change = change or not gras
                gras = True
            elif code in _SGR_COULEUR:
                change = change or couleur != _SGR_COULEUR[code]
                couleur = _SGR_COULEUR[code]
        if change:
            rouvrir()
    out.append(html.escape(texte[pos:]))
    fermer()
    #  Ce qui reste (curseur, cloche…) n'a plus sa place : retiré en dernier,
    #  sur le texte déjà échappé donc sans toucher au contenu réel.
    return _RE_AUTRE_ECHAP.sub("", "".join(out))


#  ═══ EXÉCUTION RÉELLE ═══
MARQUEUR = "__LEXOS_PRO_TERMINAL_CWD__"


def executer(commande, cwd):
    """Lance la commande pour de vrai dans bash, depuis « cwd », et rend
    (html_de_la_sortie, nouveau_cwd)."""
    mot = _premier_mot(commande)
    if mot in LISTE_TUI:
        return (
            '<span class="j">« ' + html.escape(mot) + ' » a besoin d\'un vrai '
            'écran de terminal (curseur, redessin) — cette fenêtre ne sait pas '
            'faire ça encore.</span><br><span class="s">Ouvre-le dans le '
            '<b>Terminal classique</b> (clic droit sur l\'icône du dock, ou '
            '<code>lexos-pro-terminal --classique</code>).</span>',
            cwd,
        )
    if not os.path.isdir(cwd):
        cwd = str(Path.home())
    #  Le marqueur porte le RÉPERTOIRE COURANT APRÈS la commande, pour que
    #  « cd », et même « cd .. && ls », changent bien le dossier de la
    #  fenêtre — sans qu'on ait besoin de reconnaître « cd » à part.
    script = (
        "cd -- " + shlex.quote(cwd) + " 2>/dev/null || cd;\n"
        "{ " + commande + "\n} 2>&1\n"
        'printf \'\\n%s%s\' ' + shlex.quote(MARQUEUR) + ' "$PWD"\n'
    )
    try:
        r = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c", script],
            cwd=cwd, stdin=subprocess.DEVNULL,
            capture_output=True, timeout=DELAI_MAX,
        )
        brut = r.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as e:
        partiel = (e.stdout or b"").decode("utf-8", "replace")
        i = partiel.rfind(MARQUEUR)
        avant = partiel[:i] if i >= 0 else partiel
        return (ansi_vers_html(avant) +
                '<br><span class="r">— arrêté après ' + str(int(DELAI_MAX)) +
                ' s (aucune réponse au clavier n\'est encore possible ici)</span>', cwd)
    except OSError as e:
        return ('<span class="r">bash introuvable : ' + html.escape(str(e)) + '</span>', cwd)

    i = brut.rfind(MARQUEUR)
    if i < 0:
        return (ansi_vers_html(brut), cwd)
    sortie = brut[:i]
    nouveau_cwd = brut[i + len(MARQUEUR):].strip("\n") or cwd
    #  Le marqueur laisse un « \n » juste avant lui, propre au format qu'on a
    #  écrit ; on l'enlève pour ne pas ajouter une ligne vide à chaque appel.
    if sortie.endswith("\n"):
        sortie = sortie[:-1]
    return (ansi_vers_html(sortie), nouveau_cwd)


#  ═══ LE SERVEUR ═══
class Handler(http.server.SimpleHTTPRequestHandler):
    jeton = ""
    port = 0

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def _origine_valide(self):
        """Absente : un fetch same-origin depuis notre propre page ne pose
        PAS toujours cet en-tête selon le navigateur — on ne bloque donc que
        l'en-tête présent ET faux, jamais son absence pure."""
        o = self.headers.get("Origin", "")
        return o == "" or o == "http://127.0.0.1:%d" % self.port

    def do_GET(self):
        return super().do_GET()

    def do_POST(self):
        if self.path != "/api/exec":
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        #  ═══ LES DEUX SERRURES ═══
        if not self._origine_valide():
            return self._json(403, {"ok": False, "erreur": "origine refusée"})
        recu = self.headers.get("X-Lexos-Jeton", "")
        if not (recu and secrets.compare_digest(recu, self.jeton)):
            return self._json(403, {"ok": False, "erreur": "jeton absent ou invalide"})
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        commande = requete.get("cmd", "")
        cwd = requete.get("cwd", "") or str(Path.home())
        if not isinstance(commande, str) or not commande.strip():
            return self._json(400, {"ok": False, "erreur": "commande vide"})
        try:
            sortie_html, nouveau_cwd = executer(commande, cwd)
        except Exception as e:  # la fenêtre doit survivre à n'importe quoi
            return self._json(200, {"ok": False, "erreur": str(e), "cwd": cwd})
        return self._json(200, {"ok": True, "sortie": sortie_html, "cwd": nouveau_cwd})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def demarrer_serveur():
    """Démarre le pont sur un port libre, avec un jeton neuf. Rend
    (serveur, port, jeton) — l'appelant décide de la fenêtre."""
    port = _port_libre()
    jeton = secrets.token_urlsafe(32)
    classe = type("HandlerJeton", (Handler,), {"jeton": jeton, "port": port})
    handler = functools.partial(classe, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-terminal-pro-http").start()
    return serveur, port, jeton


def main():
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    serveur, port, jeton = demarrer_serveur()
    url = f"http://127.0.0.1:{port}/index.html?port={port}&jeton={jeton}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(760, min(1280, int(dispo.width() * 0.72)))
        hauteur = max(480, min(860, int(dispo.height() * 0.78)))
        fenetre.resize(largeur, hauteur)
        fenetre.move(dispo.x() + (dispo.width() - largeur) // 2,
                     dispo.y() + (dispo.height() - hauteur) // 2)
    else:
        fenetre.resize(1000, 640)
    if ICON_PATH.exists():
        fenetre.setWindowIcon(QIcon(str(ICON_PATH)))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)

    #  ═══ LE PRESSE-PAPIER, ET POURQUOI IL FAUT DEUX RÉGLAGES ═══
    #  ALEX : le copier-coller ne fonctionnait pas. Deux causes distinctes ;
    #  celle-ci est côté Qt. QtWebEngine DÉSACTIVE PAR DÉFAUT l'accès de
    #  JavaScript au presse-papier — tant que ces attributs ne sont pas
    #  posés, la page ne peut ni écrire ni lire dedans, quoi qu'elle tente.
    #
    #  LES DEUX SONT NÉCESSAIRES ET NE FONT PAS LA MÊME CHOSE :
    #    · JavascriptCanAccessClipboard autorise l'ÉCRITURE (copier) ;
    #    · JavascriptCanPaste          autorise la LECTURE  (coller).
    #  N'en poser qu'un donne un copier-coller à moitié réparé — le collage
    #  marche mais pas la copie, ou l'inverse — et c'est plus long à
    #  diagnostiquer qu'une panne franche.
    #
    #  AVANT le load : après le chargement, les réglages peuvent ne pas
    #  s'appliquer à la page déjà en cours.
    #
    #  ET SOUS try/except, PARCE QU'UN TERMINAL QUI NE S'OUVRE PAS EST PIRE.
    #  Si une version de PySide6 renomme ou déplace ces attributs, la fenêtre
    #  doit s'ouvrir QUAND MÊME, sans presse-papier. Un presse-papier absent
    #  est un désagrément ; une fenêtre qui refuse de s'ouvrir laisse un
    #  système où l'on ne peut plus rien lancer du tout — c'est la règle
    #  écrite en tête de ce fichier. On journalise l'échec, on ne l'avale pas.
    try:
        from PySide6.QtWebEngineCore import QWebEngineSettings
        reglages = vue.settings()
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard, True)
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanPaste, True)
    except Exception as e:  # noqa: BLE001 — voir le commentaire ci-dessus
        print(f"[lexos-terminal-pro] presse-papier non activé : {e}",
              file=sys.stderr)

    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
