#!/usr/bin/env python3
"""
LexOS — serveur de partage local (envoi et réception de fichiers)

Sert un dossier en HTTP sur le réseau local, avec une page d'accueil sobre :
    · liste des fichiers partagés, téléchargeables d'un clic
    · formulaire d'envoi pour recevoir des fichiers depuis un téléphone

Pensé pour durer quelques minutes, le temps d'un transfert, puis s'arrêter.
Il n'écoute que sur le réseau local et ne demande aucune application côté
téléphone : on scanne le QR code et c'est tout.

Usage :
    share-server.py --dir <dossier> [--port 0] [--recv <dossier>] [--minutes 15]
"""

import argparse
import html
import http.server
import os
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

CSS = """
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 24px 16px 48px;
  background: #000; color: #fff;
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.wrap { max-width: 640px; margin: 0 auto; }
h1 { font-size: 26px; margin: 0 0 4px; letter-spacing: -.5px; }
h1 span { color: #E8590C; }
.sub { color: #8A8A90; font-size: 14px; margin: 0 0 28px; }
h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 1.5px;
     color: #8A8A90; margin: 32px 0 12px; font-weight: 600; }
ul { list-style: none; padding: 0; margin: 0; }
li { border-bottom: 1px solid #1C1C20; }
li:first-child { border-top: 1px solid #1C1C20; }
a.file {
  display: flex; justify-content: space-between; gap: 12px; align-items: center;
  padding: 14px 4px; color: #fff; text-decoration: none;
}
a.file:hover { background: #0E0E10; }
a.file .name { overflow-wrap: anywhere; }
a.file .size { color: #8A8A90; font-size: 13px; white-space: nowrap; }
form { border: 1px dashed #2A2A30; border-radius: 10px; padding: 20px; }
input[type=file] { width: 100%; color: #B8B8BC; margin-bottom: 14px; }
button {
  background: #E8590C; color: #fff; border: 1px solid #A84007;
  border-radius: 6px; padding: 11px 20px; font-size: 15px; font-weight: 600;
  cursor: pointer; width: 100%;
}
button:hover { background: #FF7A33; }
.msg { background: #0E1A10; border: 1px solid #1F8F4E; color: #2DBF6B;
       border-radius: 8px; padding: 12px 14px; margin-bottom: 20px; font-size: 15px; }
.empty { color: #8A8A90; padding: 14px 4px; }
footer { margin-top: 40px; color: #4A4A50; font-size: 12px; text-align: center; }
"""

PAGE = """<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Partage LexOS</title>
<style>{css}</style>
</head><body><div class="wrap">
<h1>Lex<span>OS</span></h1>
<p class="sub">Partage local &middot; {host}</p>
{message}
<h2>Fichiers partagés</h2>
{files}
{upload}
<footer>Ce partage s'arrête tout seul dans {minutes} minutes.</footer>
</div></body></html>
"""

UPLOAD_FORM = """<h2>M'envoyer un fichier</h2>
<form method="post" enctype="multipart/form-data">
  <input type="file" name="fichier" multiple required>
  <button type="submit">Envoyer vers l'ordinateur</button>
</form>
"""


def human(size):
    for unit in ("o", "Kio", "Mio", "Gio"):
        if size < 1024 or unit == "Gio":
            return f"{size:.0f} {unit}" if unit == "o" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} Gio"


class Handler(http.server.SimpleHTTPRequestHandler):
    share_dir = "."
    recv_dir = None
    minutes = 15
    message = ""

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s %s\n" % (self.address_string(), fmt % args))

    # --- Page d'accueil ------------------------------------------------------
    def render_index(self):
        try:
            names = sorted(
                n for n in os.listdir(self.share_dir)
                if os.path.isfile(os.path.join(self.share_dir, n))
            )
        except OSError:
            names = []

        if names:
            items = []
            for n in names:
                size = os.path.getsize(os.path.join(self.share_dir, n))
                items.append(
                    '<li><a class="file" href="{href}" download>'
                    '<span class="name">{name}</span>'
                    '<span class="size">{size}</span></a></li>'.format(
                        href=urllib.parse.quote(n),
                        name=html.escape(n),
                        size=human(size),
                    )
                )
            files = "<ul>" + "".join(items) + "</ul>"
        else:
            files = '<p class="empty">Aucun fichier partagé pour l\'instant.</p>'

        msg = f'<p class="msg">{html.escape(self.message)}</p>' if self.message else ""
        Handler.message = ""

        body = PAGE.format(
            css=CSS,
            host=html.escape(self.headers.get("Host", "")),
            message=msg,
            files=files,
            upload=UPLOAD_FORM if self.recv_dir else "",
            minutes=self.minutes,
        ).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if urllib.parse.urlparse(self.path).path in ("/", "/index.html"):
            self.render_index()
            return
        super().do_GET()

    def copyfile(self, source, outputfile):
        # Un téléphone qui annule un téléchargement ferme brutalement la
        # connexion : c'est normal, ça n'a pas à polluer le journal.
        try:
            super().copyfile(source, outputfile)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # --- Réception -----------------------------------------------------------
    #  Parseur multipart maison, en flux. Le module cgi de la bibliothèque
    #  standard aurait fait l'affaire, mais il disparaît en Python 3.13 :
    #  autant ne pas dépendre d'une pièce condamnée.
    #
    #  Toutes les lectures sont bornées par Content-Length. En HTTP/1.1 la
    #  connexion reste ouverte après le corps : lire « jusqu'à EOF » bloquerait
    #  indéfiniment.
    def _read(self, n):
        """Lit n octets au plus, en vidant d'abord le tampon d'avance.

        Après un délimiteur, `_pending` contient déjà des octets lus au réseau —
        typiquement les en-têtes de la partie suivante. Toute lecture doit
        passer par ici : sinon ces octets sont perdus et, dans un envoi
        multiple, tous les fichiers après le premier disparaissent.
        """
        data = b""
        if self._pending:
            data, self._pending = self._pending[:n], self._pending[n:]
            if len(data) >= n:
                return data
        return data + self._raw_read(n - len(data))

    def _raw_read(self, n):
        n = min(n, self._remaining)
        if n <= 0:
            return b""
        data = self.rfile.read(n)
        self._remaining -= len(data)
        return data

    def _readline(self):
        """Une ligne d'en-tête, tampon d'avance compris."""
        idx = self._pending.find(b"\n")
        if idx != -1:
            line, self._pending = self._pending[:idx + 1], self._pending[idx + 1:]
            return line
        line, self._pending = self._pending, b""
        if self._remaining > 0:
            more = self.rfile.readline(min(8192, self._remaining))
            self._remaining -= len(more)
            line += more
        return line

    def _read_part_headers(self):
        headers = {}
        while True:
            line = self._readline()
            if not line or line in (b"\r\n", b"\n"):
                return headers
            name, _, value = line.decode("utf-8", "replace").partition(":")
            if name:
                headers[name.strip().lower()] = value.strip()

    @staticmethod
    def _filename_of(disposition):
        for piece in disposition.split(";"):
            piece = piece.strip()
            if piece.startswith("filename="):
                return piece[9:].strip().strip('"')
        return None

    def _stream_until_boundary(self, delim, out):
        """Recopie la partie courante dans `out` jusqu'au délimiteur.

        Renvoie True si le délimiteur a été trouvé, False si le corps s'est
        terminé avant (envoi tronqué).
        """
        keep = len(delim)
        buf = b""
        while True:
            idx = buf.find(delim)
            if idx != -1:
                if out is not None:
                    out.write(buf[:idx])
                self._pending = buf[idx + keep:]
                return True
            # On garde de quoi reconnaître un délimiteur à cheval sur deux blocs.
            if len(buf) > keep:
                if out is not None:
                    out.write(buf[:-keep])
                buf = buf[-keep:]
            chunk = self._read(1 << 16)
            if not chunk:
                if out is not None and buf:
                    out.write(buf)
                return False
            buf += chunk

    def _unique_path(self, name):
        # Seul le nom de base compte : aucun chemin ne vient du client.
        name = os.path.basename(name).replace("\\", "_").lstrip(".") or "fichier"
        dest = os.path.join(self.recv_dir, name)
        stem, ext = os.path.splitext(dest)
        i = 1
        while os.path.exists(dest):
            dest = f"{stem}-{i}{ext}"
            i += 1
        return dest

    def do_POST(self):
        if not self.recv_dir:
            self.send_error(403, "Reception desactivee")
            return

        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype or "boundary=" not in ctype:
            self.send_error(400, "Envoi illisible")
            return

        try:
            self._remaining = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(411, "Content-Length manquant")
            return
        if self._remaining <= 0:
            self.send_error(400, "Corps vide")
            return

        boundary = ctype.split("boundary=", 1)[1].strip().strip('"').encode("utf-8")
        delim = b"\r\n--" + boundary
        self._pending = b""

        first = self._readline()
        if not first.startswith(b"--" + boundary):
            self.send_error(400, "Envoi mal forme")
            return

        saved = []
        while self._remaining > 0 or self._pending:
            headers = self._read_part_headers()
            if not headers:
                break

            name = self._filename_of(headers.get("content-disposition", ""))
            if name:
                dest = self._unique_path(name)
                with open(dest, "wb") as out:
                    found = self._stream_until_boundary(delim, out)
                saved.append(os.path.basename(dest))
                print(f"  reçu : {dest}", flush=True)
            else:
                # Champ de formulaire sans fichier : consommé et oublié.
                found = self._stream_until_boundary(delim, None)

            if not found:
                break

            # Après le délimiteur vient soit "--" (fin), soit CRLF (suite).
            tail = self._read(2)
            if tail.startswith(b"--"):
                break

        Handler.message = (
            "Reçu : " + ", ".join(saved) if saved else "Aucun fichier reçu."
        )
        self.send_response(303)
        self.send_header("Location", "/")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def translate_path(self, path):
        # Sert exclusivement depuis le dossier de partage.
        path = urllib.parse.urlparse(path).path
        name = os.path.basename(urllib.parse.unquote(path))
        return os.path.join(self.share_dir, name)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def local_ip():
    """Adresse de cette machine sur le réseau local.

    connect() en UDP n'envoie aucun paquet : il se contente de demander au
    noyau quelle interface servirait à joindre cette destination.
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 9))
        addr = s.getsockname()[0]
    except OSError:
        addr = ""
    finally:
        s.close()

    if addr and not addr.startswith("127."):
        return addr

    # Repli : première adresse non-locale trouvée sur la machine.
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            cand = info[4][0]
            if not cand.startswith("127."):
                return cand
    except OSError:
        pass
    return "127.0.0.1"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--recv", default=None)
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--minutes", type=int, default=15)
    args = ap.parse_args()

    Handler.share_dir = os.path.abspath(args.dir)
    Handler.recv_dir = os.path.abspath(args.recv) if args.recv else None
    Handler.minutes = args.minutes

    httpd = Server(("0.0.0.0", args.port), Handler)
    port = httpd.server_address[1]
    url = f"http://{local_ip()}:{port}/"

    print(url, flush=True)

    def stop_later():
        time.sleep(args.minutes * 60)
        print("  temps écoulé — partage fermé", flush=True)
        httpd.shutdown()

    threading.Thread(target=stop_later, daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
