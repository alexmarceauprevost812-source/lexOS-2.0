"""Test de _wifi_etat() : le réseau connecté vient de l'état de l'appareil,
pas d'un balayage de bornes qui peut être en retard sur la vraie connexion —
c'est ce qui affichait « Aucun » à Alex alors qu'il était bel et bien
connecté (nmcli device wifi ne montrait pas encore ACTIVE=yes)."""
import importlib.util, os, stat, sys, tempfile

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    "settings", "config/includes.chroot/usr/lib/lexos/settings.py")
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)

fails = []
def check(name, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {name}{(' — ' + extra) if extra and not cond else ''}")
    if not cond: fails.append(name)

def nmcli_faux(rep):
    """Un nmcli en trois lignes : dispatche selon les arguments reçus,
    exactement comme les faux binaires des autres bancs de ce dépôt."""
    d = tempfile.mkdtemp()
    chemin = os.path.join(d, "nmcli")
    with open(chemin, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\n" + rep)
    os.chmod(chemin, os.stat(chemin).st_mode | stat.S_IEXEC)
    return d

VIEUX_PATH = os.environ.get("PATH", "")

def avec_nmcli(rep, fonction):
    d = nmcli_faux(rep)
    os.environ["PATH"] = d + os.pathsep + VIEUX_PATH
    try:
        return fonction()
    finally:
        os.environ["PATH"] = VIEUX_PATH

# --- 1. LE BOGUE D'ALEX : connecté pour de vrai, absent du balayage --------
#  « device status » dit que wlan0 est connecté à BELL507. « device wifi »
#  (le balayage) ne montre AUCUNE ligne ACTIVE=yes pour BELL507 — exactement
#  la situation d'un balayage en retard sur la connexion. L'ancien code (qui
#  ne lisait QUE le balayage) aurait rapporté "" ; le nouveau doit rapporter
#  BELL507 quand même.
REP_BOGUE = '''
case "$*" in
  *"radio wifi"*) echo "enabled" ;;
  *"device status"*) echo "wlan0:wifi:connected:BELL507" ;;
  *"networking connectivity"*) echo "full" ;;
  *"device wifi list --rescan auto"*) echo "no:COGECO:70:WPA2" ;;
  *"device wifi"*) echo "no:COGECO:70" ;;
esac
'''
r = avec_nmcli(REP_BOGUE, settings._wifi_etat)
check("réseau connecté trouvé même absent du balayage (le bogue d'Alex)",
      r["reseau"] == "BELL507", f"reseau={r['reseau']!r}")
check("signal à 0 quand la borne connectée n'est pas dans le balayage",
      r["signal"] == 0, f"signal={r['signal']!r}")
check("internet reflète connectivity", r["internet"] == "full")

# --- 2. Cas normal : la borne connectée EST dans le balayage ---------------
REP_NORMAL = '''
case "$*" in
  *"radio wifi"*) echo "enabled" ;;
  *"device status"*) echo "wlan0:wifi:connected:BELL507" ;;
  *"networking connectivity"*) echo "full" ;;
  *"device wifi list --rescan auto"*) printf "yes:BELL507:88:WPA2\\nno:COGECO:52:WPA2\\n" ;;
  *"device wifi"*) printf "BELL507:88\\nCOGECO:52\\n" ;;
esac
'''
r = avec_nmcli(REP_NORMAL, settings._wifi_etat)
check("réseau et signal corrects quand tout concorde",
      r["reseau"] == "BELL507" and r["signal"] == 88, f"{r['reseau']!r} {r['signal']!r}")

# --- 3. Vraiment pas connecté : aucun réseau ne doit apparaître ------------
REP_AUCUN = '''
case "$*" in
  *"radio wifi"*) echo "enabled" ;;
  *"device status"*) echo "wlan0:wifi:disconnected:" ;;
  *"networking connectivity"*) echo "none" ;;
  *"device wifi list --rescan auto"*) printf "no:BELL507:70:WPA2\\n" ;;
  *"device wifi"*) printf "BELL507:70\\n" ;;
esac
'''
r = avec_nmcli(REP_AUCUN, settings._wifi_etat)
check("pas de réseau rapporté quand l'appareil est vraiment déconnecté",
      r["reseau"] == "", f"reseau={r['reseau']!r}")

# --- 4. Un SSID avec « : » dedans (ce que _terse() existe pour régler) -----
#  Chaîne SIMPLE-QUOTÉE dans le faux script : le shell ne touche pas au
#  « \: » à l'intérieur, et printf %s ne l'interprète pas non plus — la
#  ligne produite porte donc EXACTEMENT l'échappement que le vrai nmcli
#  écrit pour un SSID contenant un deux-points.
REP_DEUXPOINTS = r'''
case "$*" in
  *"radio wifi"*) echo "enabled" ;;
  *"device status"*) printf '%s\n' 'wlan0:wifi:connected:Chez L\:ea' ;;
  *"networking connectivity"*) echo "full" ;;
  *"device wifi list --rescan auto"*) printf '%s\n' 'yes:Chez L\:ea:60:WPA2' ;;
  *"device wifi"*) printf '%s\n' 'Chez L\:ea:60' ;;
esac
'''
r = avec_nmcli(REP_DEUXPOINTS, settings._wifi_etat)
check("un SSID avec un « : » dedans n'est pas tronqué (device status)",
      r["reseau"] == "Chez L:ea", f"reseau={r['reseau']!r}")
check("...ni dans la recherche du signal (device wifi)",
      r["signal"] == 60, f"signal={r['signal']!r}")

# --- 4. SE DÉCONNECTER : le bouton qui manquait --------------------------
#  ALEX, photo à l'appui : « quand je suis connecté sur le wi-fi, il dit pas
#  de déconnecter une fois connecté — là je suis connecté à BELL507 mais il
#  dit pas déconnecter ». La ligne du réseau actif ne portait qu'une pastille
#  « connecté », sans rien à cliquer : couper le Wi-Fi demandait le terminal,
#  alors que le Bluetooth a son bouton « Déconnecter » dans la même fenêtre.
#
#  CE QUI EST ÉPROUVÉ ICI, C'EST L'ARGUMENT QU'ON NE PASSE PAS. act_wifi_
#  deconnecter() ne prend RIEN de la page : elle relit elle-même quel
#  appareil Wi-Fi est connecté. Le banc vérifie donc que la commande lancée
#  vise bien CET appareil-là, et jamais un nom venu d'ailleurs.
JOURNAL = os.path.join(tempfile.mkdtemp(), "appels")

REP_DECO = '''
echo "$*" >> "%s"
case "$*" in
  *"device status"*) echo "eth0:ethernet:connected:Filaire"
                     echo "wlan0:wifi:connected:BELL507" ;;
  *"device disconnect"*) exit 0 ;;
esac
''' % JOURNAL

r = avec_nmcli(REP_DECO, lambda: settings.act_wifi_deconnecter(None))
check("la déconnexion réussit quand un Wi-Fi est actif", r.get("ok") is True, repr(r))
appels = open(JOURNAL, encoding="utf-8").read() if os.path.exists(JOURNAL) else ""
check("c'est bien l'appareil WI-FI qui est coupé, pas le filaire",
      "device disconnect wlan0" in appels, f"appels={appels!r}")
check("...et le filaire n'est jamais touché",
      "disconnect eth0" not in appels, f"appels={appels!r}")

#  RIEN À COUPER : un refus clair, jamais un succès inventé — la même règle
#  que partout ailleurs dans ce fichier.
REP_RIEN = '''
case "$*" in
  *"device status"*) echo "eth0:ethernet:connected:Filaire"
                     echo "wlan0:wifi:disconnected:" ;;
esac
'''
r = avec_nmcli(REP_RIEN, lambda: settings.act_wifi_deconnecter(None))
check("sans Wi-Fi actif, la fonction refuse au lieu de prétendre avoir coupé",
      r.get("ok") is False and "aucune" in r.get("erreur", "").lower(), repr(r))

#  nmcli qui échoue : le motif remonte à la page, il ne disparaît pas.
REP_ECHEC = '''
case "$*" in
  *"device status"*) echo "wlan0:wifi:connected:BELL507" ;;
  *"device disconnect"*) echo "Error: not authorized." >&2; exit 4 ;;
esac
'''
r = avec_nmcli(REP_ECHEC, lambda: settings.act_wifi_deconnecter(None))
check("un échec de nmcli remonte son motif au lieu d'être avalé",
      r.get("ok") is False and "not authorized" in r.get("erreur", ""), repr(r))

#  ET LA LISTE BLANCHE : une action qui existe mais n'est branchée nulle part
#  est une action que le bouton de la page appelle dans le vide.
check("« wifi-deconnecter » est branchée dans ACTIONS",
      settings.ACTIONS.get("wifi-deconnecter") is settings.act_wifi_deconnecter)

print()
if fails:
    print(f"{len(fails)} échoué(s) : {', '.join(fails)}")
    sys.exit(1)
print("tout est bon")
