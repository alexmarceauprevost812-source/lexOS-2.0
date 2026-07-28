"""Test du serveur de partage : téléchargement, envoi, sécurité des chemins."""
import importlib.util, os, shutil, tempfile, threading, urllib.request, urllib.error, uuid, sys

# Sans ça, l'import écrit un __pycache__ dans config/includes.chroot, que
# live-build recopierait tel quel dans l'ISO si on construit après un test.
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    "share", "config/includes.chroot/usr/lib/lexos/share-server.py")
share = importlib.util.module_from_spec(spec); spec.loader.exec_module(share)

tmp = tempfile.mkdtemp()
out, inbox = os.path.join(tmp, "out"), os.path.join(tmp, "in")
os.makedirs(out); os.makedirs(inbox)

big = os.urandom(3_000_000)
open(os.path.join(out, "gros.bin"), "wb").write(big)
open(os.path.join(out, "photo.png"), "wb").write(b"\x89PNG\r\n\x1a\n" + os.urandom(50_000))

share.Handler.share_dir, share.Handler.recv_dir = out, inbox
# Le serveur exige un jeton dans l'adresse (main() en tire un au hasard) :
# on en pose un fixe ici pour que les tests soient reproductibles.
TOKEN = "jeton-de-test"
share.Handler.token = TOKEN
httpd = share.Server(("127.0.0.1", 0), share.Handler)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{port}"
U = f"{BASE}/{TOKEN}"

fails = []
def check(name, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {name}{(' — ' + extra) if extra and not cond else ''}")
    if not cond: fails.append(name)

def post(parts):
    b = "----lexos" + uuid.uuid4().hex
    body = b""
    for fname, data in parts:
        body += (f"--{b}\r\nContent-Disposition: form-data; name=\"fichier\"; "
                 f"filename=\"{fname}\"\r\nContent-Type: application/octet-stream\r\n\r\n"
                 ).encode() + data + b"\r\n"
    body += f"--{b}--\r\n".encode()
    r = urllib.request.Request(U + "/", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={b}"})
    return urllib.request.urlopen(r, timeout=30)

print("\n— Page d'accueil —")
page = urllib.request.urlopen(U + "/", timeout=10).read().decode()
check("liste les fichiers", "gros.bin" in page and "photo.png" in page)
check("affiche les tailles", "2.9 Mio" in page, page[:200])
check("formulaire d'envoi présent", "M'envoyer un fichier" in page)

print("\n— Téléchargement —")
got = urllib.request.urlopen(f"{U}/gros.bin", timeout=30).read()
check("3 Mo binaires intacts", got == big, f"{len(got)} octets reçus")

print("\n— Envoi (téléphone → PC) —")
payload = os.urandom(1_500_000)
post([("envoi.dat", payload)])
p = os.path.join(inbox, "envoi.dat")
check("fichier écrit", os.path.exists(p))
check("1,5 Mo intacts", os.path.exists(p) and open(p, "rb").read() == payload)

print("\n— Envoi multiple —")
a, bb = os.urandom(300_000), os.urandom(200_000)
post([("un.dat", a), ("deux.dat", bb)])
check("les deux fichiers reçus",
      open(os.path.join(inbox, "un.dat"), "rb").read() == a and
      open(os.path.join(inbox, "deux.dat"), "rb").read() == bb)

print("\n— Collision de noms —")
post([("envoi.dat", b"nouveau contenu")])
check("l'original n'est pas écrasé", open(p, "rb").read() == payload)
check("suffixe -1 ajouté", os.path.exists(os.path.join(inbox, "envoi-1.dat")))

print("\n— Cas limites du parseur —")
post([("vide.dat", b"")])
check("fichier vide accepté", os.path.exists(os.path.join(inbox, "vide.dat")))
# Données contenant une séquence proche du délimiteur
tricky = b"X" * 1000 + b"\r\n--fauxdelimiteur\r\n" + b"Y" * 1000
post([("piege.dat", tricky)])
check("délimiteur factice dans les données",
      open(os.path.join(inbox, "piege.dat"), "rb").read() == tricky)

print("\n— Sécurité : remontée de chemin —")
for attaque in ["../../../../etc/passwd", "%2e%2e%2f%2e%2e%2fetc%2fpasswd", "/etc/passwd"]:
    try:
        r = urllib.request.urlopen(f"{U}/{attaque}", timeout=10).read()
        leaked = b"root:" in r
    except Exception:
        leaked = False
    check(f"GET {attaque[:32]} bloqué", not leaked)

evil = os.path.join(tmp, "EVIL.txt")
post([("../../../../" + os.path.relpath(evil, "/"), b"pwn")])
check("nom d'envoi malveillant neutralisé", not os.path.exists(evil))
check("écrit dans le dossier de réception",
      any(f.startswith("EVIL") for f in os.listdir(inbox)))

print("\n— Sécurité : jeton d'accès —")
def status(url, data=None, ctype=None):
    """Code HTTP renvoyé, sans lever d'exception sur 4xx."""
    req = urllib.request.Request(url, data=data)
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        return urllib.request.urlopen(req, timeout=10).status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0

# Ce que voit un inconnu sur le même réseau : rien.
for chemin in ["/", "/index.html", "/gros.bin", "/mauvais-jeton/gros.bin"]:
    check(f"sans jeton, {chemin} refusé", status(BASE + chemin) == 404)

b = "----lexos" + uuid.uuid4().hex
corps = (f"--{b}\r\nContent-Disposition: form-data; name=\"fichier\"; "
         f"filename=\"intrus.txt\"\r\nContent-Type: application/octet-stream\r\n\r\n"
         ).encode() + b"intrus" + f"\r\n--{b}--\r\n".encode()
check("sans jeton, envoi refusé",
      status(BASE + "/", corps, f"multipart/form-data; boundary={b}") == 404)
check("aucun fichier déposé sans jeton",
      not any(f.startswith("intrus") for f in os.listdir(inbox)))

# Et le bon jeton continue de marcher.
check("avec le bon jeton, la page répond", status(U + "/") == 200)
check("avec le bon jeton, le fichier se télécharge", status(U + "/gros.bin") == 200)

httpd.shutdown(); shutil.rmtree(tmp, ignore_errors=True)
print(f"\n{'TOUS LES TESTS PASSENT' if not fails else 'ÉCHECS : ' + ', '.join(fails)}\n")
sys.exit(1 if fails else 0)
