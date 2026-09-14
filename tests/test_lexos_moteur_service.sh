#!/usr/bin/env bash
# =============================================================================
#  UN SEUL SERVEUR LOCAL, UNE SEULE FENÊTRE — et ils répondent pour de vrai
# =============================================================================
#  ALEX : « un moteur pour tous les paramètres ».
#
#  COMPTÉ AVANT : la classe « Handler » existait en SIX exemplaires
#  (settings, volet, partage, ia-locale, terminal-pro, share-server) et la
#  fenêtre Qt en six aussi. Quatre des Handlers avaient rigoureusement la
#  même charpente — journal muet, _json, /api/etat, /api/action — recopiée
#  avec de petites divergences : « ensure_ascii » posé ici et pas là, un
#  « Cache-Control » chez un seul, un plafond de corps chez un seul.
#
#  ═══ CE BANC N'EST PAS UN grep ═══
#  Il MONTE chaque serveur sur un port réel et lui PARLE. Un « class Handler
#  hérite de Service » vérifié au texte serait vert même si la fusion avait
#  cassé /api/action — et c'est exactement ce qu'une fusion casse.
#
#  ⚠ LE PIÈGE DE CETTE ÉTAPE, ÉPROUVÉ AU POINT 4. Une fonction rangée dans un
#  attribut de CLASSE est un descripteur : « self.etat_fn() » passe le
#  handler en premier argument — une TypeError à la première requête, dans du
#  code qui s'importe parfaitement. Rien ne le voit avant qu'on demande
#  vraiment un état.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$RACINE/config/includes.chroot/usr/lib/lexos"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# ===========================================================================
titre "1. LA LISTE DES COPIES RÉTRÉCIT, ET ON DIT LESQUELLES RESTENT"
# ===========================================================================
#  On ne lit que les lignes de CODE : les commentaires de ce dépôt citent ce
#  qu'ils remplacent, et un grep naïf se déclencherait sur l'explication du
#  correctif lui-même.
#
#  DEUX Handlers restent dehors, et c'est écrit dans moteur/service.py :
#  terminal-pro.py (validation d'origine, jeton, flux PTY) et share-server.py
#  (réception de fichiers, multipart, chemins). Ce ne sont pas des fenêtres
#  de réglages ; les fondre ici ne ferait pas UNE classe, ça en ferait une
#  avec trois métiers. Cette liste doit RÉTRÉCIR, jamais grossir.
ATTENDUS="terminal-pro.py share-server.py"
TROUVES=""
for F in "$LIB"/*.py; do
  if grep -v '^[[:space:]]*#' "$F" | grep -q 'class Handler(http\.server\.'; then
    TROUVES="$TROUVES $(basename "$F")"
  fi
done
TROUVES="$(tr ' ' '\n' <<< "$TROUVES" | grep -v '^$' | sort | tr '\n' ' ' | sed 's/ $//')"
ATTENDUS_T="$(tr ' ' '\n' <<< "$ATTENDUS" | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$TROUVES" = "$ATTENDUS_T" ]; then
  ok "il ne reste que les deux non migrés, nommés : $TROUVES"
elif [ -z "$TROUVES" ]; then
  ok "plus aucun Handler indépendant — tout est passé au moteur"
else
  #  Grossir est un échec ; rétrécir ne l'est pas.
  SURPLUS=""
  for T in $TROUVES; do
    case " $ATTENDUS_T " in *" $T "*) ;; *) SURPLUS="$SURPLUS $T";; esac
  done
  if [ -n "$SURPLUS" ]; then
    non "de nouveaux Handlers indépendants sont apparus :$SURPLUS (la liste doit rétrécir)"
  else
    ok "la liste a rétréci : il reste $TROUVES"
  fi
fi
#  Et une seule fabrique de fenêtre pour les quatre fenêtres de réglages.
NUS=""
for F in settings volet partage ia-locale; do
  if grep -v '^[[:space:]]*#' "$LIB/$F.py" | grep -q 'QApplication(sys\.argv)'; then
    NUS="$NUS $F"
  fi
done
[ -z "$NUS" ] \
  && ok "les quatre fenêtres passent par moteur/fenetre.application()" \
  || non "des fenêtres montent encore leur QApplication à la main :$NUS"

# ===========================================================================
titre "2. CHAQUE SERVEUR RÉPOND POUR DE VRAI SUR SON PORT"
# ===========================================================================
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : aucun serveur n'a été monté"
else
cat > "$BANC/parle.py" <<'PY'
"""Monte le vrai serveur de chaque module et lui parle. Rend un verdict JSON."""
import importlib.util, json, sys, urllib.error, urllib.request

LIB = sys.argv[1]
sys.path.insert(0, LIB)

def charge(nom):
    spec = importlib.util.spec_from_file_location("lex_" + nom.replace("-", "_"),
                                                  f"{LIB}/{nom}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def lit(url, delai=20):
    with urllib.request.urlopen(url, timeout=delai) as r:
        return r.status, r.read().decode("utf-8", "replace"), dict(r.headers)

def poste(url, charge_utile, delai=20):
    req = urllib.request.Request(url, data=json.dumps(charge_utile).encode(),
                                 headers={"Content-Type": "application/json"},
                                 method="POST")
    try:
        with urllib.request.urlopen(req, timeout=delai) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")

verdict = {}
for nom, fil in (("settings", "banc-settings"), ("volet", "banc-volet"),
                 ("ia-locale", "banc-ia")):
    v = {}
    try:
        mod = charge(nom)
        if nom == "volet":
            mod.Handler.quoi = "rapides"
        serveur, port = mod._service.servir(mod.WEB_DIR, mod.Handler, fil)
        base = f"http://127.0.0.1:{port}"
        #  /api/etat doit rendre du JSON, pas une trace d'erreur.
        code, corps, _ = lit(base + "/api/etat")
        v["etat_code"] = code
        try:
            e = json.loads(corps)
            v["etat_cles"] = len(e) if isinstance(e, dict) else -1
        except ValueError:
            v["etat_cles"] = -1
        #  Une action INCONNUE doit être refusée proprement, avec un motif —
        #  et surtout ne pas faire tomber le serveur.
        code, corps = poste(base + "/api/action", {"action": "zzz-inexistante"})
        v["action_inconnue_code"] = code
        v["action_inconnue_motif"] = "erreur" in corps
        #  Une route inconnue en POST : 404, pas une pile d'appels.
        code, _ = poste(base + "/api/zzz", {})
        v["route_inconnue"] = code
        #  Et la page elle-même est toujours servie.
        code, corps, _ = lit(base + "/index.html")
        v["page_code"] = code
        v["page_html"] = "<" in corps
        #  ═══ LE CLIENT COMMUN, SERVI AUX QUATRE FENÊTRES ═══
        #  index.html le charge AVANT app.js. S'il ne sort pas d'ici, la page
        #  s'arrête sur « LexOS is not defined » à sa première ligne.
        code, corps, ent = lit(base + "/moteur/client.js")
        v["client_code"] = code
        v["client_vrai"] = "var LexOS" in corps
        v["client_genre"] = ent.get("Content-Type", "")
        #  Un nom qui n'est pas dans la liste fermée n'est pas servi — et une
        #  remontée de dossier encore moins : la page n'a aucun besoin
        #  d'inventer des noms de fichiers.
        #  ⚠ ON PARLE EN SOCKET NUE, ET C'EST TOUT LE POINT. urllib NORMALISE
        #  le chemin avant de l'envoyer : « /moteur/../x » part en « /x », et
        #  le serveur ne voit JAMAIS de remontée. Un contrôle écrit avec
        #  urllib était donc vert quoi qu'il arrive — il a d'ailleurs
        #  survécu, tout vert, à une mutation qui servait n'importe quel nom.
        #  Une requête brute, elle, arrive telle qu'on l'écrit.
        import socket as _sock
        def brut(chemin):
            c = _sock.create_connection(("127.0.0.1", port), timeout=10)
            try:
                c.sendall(f"GET {chemin} HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                          f"Connection: close\r\n\r\n".encode())
                morceaux = []
                while True:
                    bout = c.recv(65536)
                    if not bout:
                        break
                    morceaux.append(bout)
                return b"".join(morceaux)
            finally:
                c.close()
        #  ⚠ LES CIBLES SONT CHOISIES POUR EXISTER VRAIMENT. Une remontée
        #  vers un fichier ABSENT rend 404 même sans garde-fou : le contrôle
        #  serait vert par accident. « /moteur/../service.py » vise
        #  moteur/web/../service.py, c'est-à-dire moteur/service.py — qui
        #  existe, et qui est le code du serveur lui-même. C'est en cherchant
        #  pourquoi une mutation restait verte qu'on l'a vu.
        for essai in ("/moteur/zzz.js",
                      "/moteur/../service.py",
                      "/moteur/../outils.py",
                      "/moteur/../../settings.py",
                      "/moteur/..%2fservice.py",
                      "/moteur/web/client.js"):
            rep = brut(essai)
            tete = rep.split(b"\r\n", 1)[0].decode("latin1")
            if " 200" in tete:
                v.setdefault("fuites", []).append(f"{essai} -> {tete.strip()}")
        serveur.shutdown()
    except Exception as ex:                      # noqa: BLE001
        v["erreur"] = f"{type(ex).__name__}: {ex}"
    verdict[nom] = v

#  settings seul sait « ?cles= » : vide veut dire RIEN, absent veut dire TOUT.
try:
    mod = charge("settings")
    serveur, port = mod._service.servir(mod.WEB_DIR, mod.Handler, "banc-cles")
    base = f"http://127.0.0.1:{port}"
    _, tout, _ = lit(base + "/api/etat")
    _, vide, _ = lit(base + "/api/etat?cles=")
    _, deux, _ = lit(base + "/api/etat?cles=wifi,son")
    verdict["cles"] = {"tout": len(json.loads(tout)),
                       "vide": len(json.loads(vide)),
                       "deux": len(json.loads(deux))}
    serveur.shutdown()
except Exception as ex:                          # noqa: BLE001
    verdict["cles"] = {"erreur": f"{type(ex).__name__}: {ex}"}

#  partage garde SES entêtes : c'est le contrat « fusionner n'est pas
#  uniformiser ».
try:
    mod = charge("partage")
    verdict["partage"] = {
        "no_store": ("Cache-Control", "no-store") in tuple(mod.Handler.entetes_json),
        "cap": mod.Handler.corps_max,
    }
except Exception as ex:                          # noqa: BLE001
    verdict["partage"] = {"erreur": f"{type(ex).__name__}: {ex}"}

print(json.dumps(verdict))
PY
  #  Les pages vivent dans le dépôt, pas dans /usr/share : sans ces trois
  #  variables, chaque module servirait un dossier absent et rendrait 404
  #  pour index.html — un rouge qui n'accuserait que le banc.
  PART="$RACINE/config/includes.chroot/usr/share/lexos"
  V="$(HOME="$BANC/h" XDG_CONFIG_HOME="$BANC/h/.config" LEXOS_ETAT_DELAI=3 \
       LEXOS_SETTINGS_DIR="$PART/settings" \
       LEXOS_VOLET_DIR="$PART/volet" \
       LEXOS_IA_DIR="$PART/ia" \
       timeout 300 python3 "$BANC/parle.py" "$LIB" 2>"$BANC/parle.err")"
  if [ -z "$V" ]; then
    muet "aucun serveur n'a pu être monté ici : $(tail -3 "$BANC/parle.err" | tr '\n' ' ') — non mesuré"
  else
    lit(){ python3 -c 'import json,sys;d=json.loads(sys.argv[1]);
import functools
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(d)' "$V" "$1"; }
    for M in settings volet ia-locale; do
      ERR="$(lit "$M.erreur")"
      if [ "$ERR" != "None" ]; then
        non "$M : le serveur n'a pas tenu — $ERR"
        continue
      fi
      EC="$(lit "$M.etat_code")"; ECL="$(lit "$M.etat_cles")"
      AC="$(lit "$M.action_inconnue_code")"; AM="$(lit "$M.action_inconnue_motif")"
      RI="$(lit "$M.route_inconnue")"; PC="$(lit "$M.page_code")"; PH="$(lit "$M.page_html")"
      [ "$EC" = "200" ] && [ "$ECL" -gt 0 ] 2>/dev/null \
        && ok "$M : /api/etat rend $ECL clés en JSON" \
        || non "$M : /api/etat a rendu $EC et $ECL clés — la fusion a cassé la lecture d'état"
      [ "$AC" = "400" ] && [ "$AM" = "True" ] \
        && ok "$M : une action inconnue est refusée avec un motif" \
        || non "$M : action inconnue → code $AC, motif $AM"
      [ "$RI" = "404" ] \
        && ok "$M : une route POST inconnue rend 404" \
        || non "$M : route inconnue → $RI"
      [ "$PC" = "200" ] && [ "$PH" = "True" ] \
        && ok "$M : la page elle-même est toujours servie" \
        || non "$M : index.html → $PC (html : $PH)"
      CC="$(lit "$M.client_code")"; CV="$(lit "$M.client_vrai")"; CG="$(lit "$M.client_genre")"
      FU="$(lit "$M.fuites")"
      if [ "$CC" = "200" ] && [ "$CV" = "True" ]; then
        case "$CG" in
          *javascript*) ok "$M : /moteur/client.js est servi, et en text/javascript" ;;
          *) non "$M : /moteur/client.js sort en « $CG » — Chromium ne l'exécutera pas" ;;
        esac
      else
        non "$M : /moteur/client.js → $CC (contenu réel : $CV) — la page s'arrêterait sur « LexOS is not defined »"
      fi
      [ "$FU" = "None" ] \
        && ok "$M : rien d'autre ne sort de /moteur/ (ni nom inconnu, ni remontée de dossier)" \
        || non "$M : /moteur/ sert des fichiers qu'il ne devrait pas : $FU"
    done
    CT="$(lit cles.tout)"; CV="$(lit cles.vide)"; CD="$(lit cles.deux)"
    if [ "$CT" = "None" ]; then
      non "les clés partielles n'ont pas pu être mesurées : $(lit cles.erreur)"
    else
      [ "$CV" -lt "$CT" ] 2>/dev/null \
        && ok "« ?cles= » vide rend moins que tout ($CV contre $CT) — le piège du « vide = tout » ne revient pas par le moteur" \
        || non "« ?cles= » vide rend $CV clés, autant que tout ($CT)"
      [ "$CD" -gt "$CV" ] 2>/dev/null && [ "$CD" -le "$CT" ] 2>/dev/null \
        && ok "« ?cles=wifi,son » rend entre les deux ($CD)" \
        || non "« ?cles=wifi,son » rend $CD — hors des bornes $CV…$CT"
    fi
    PN="$(lit partage.no_store)"; PP="$(lit partage.cap)"
    [ "$PN" = "True" ] \
      && ok "partage garde son « Cache-Control: no-store » (fusionner n'est pas uniformiser)" \
      || non "partage a perdu son « no-store » : son compte à rebours peut être relu d'un cache"
    [ "$PP" = "4096" ] \
      && ok "partage garde son plafond de corps à 4096 octets" \
      || non "partage a un plafond de $PP au lieu de 4096"
  fi
fi

# ===========================================================================
titre "2 bis. CHAQUE PAGE CHARGE LE CLIENT, ET AVANT SON PROPRE app.js"
# ===========================================================================
#  ═══ CE CONTRÔLE MANQUAIT, ET SON ABSENCE ÉTAIT UN FAUX VERT ═══
#  Les bancs qui rendent les pages hors d'un navigateur ajoutent le client
#  eux-mêmes (lireLaPage). Ils resteraient donc TOUS VERTS avec la balise
#  retirée d'index.html — pendant que la vraie fenêtre s'arrêterait sur
#  « LexOS is not defined » à la première ligne d'app.js, et resterait VIDE.
#  Mesuré : la balise enlevée, pages_vides annonçait 79 verts.
#  L'ORDRE compte autant que la présence : app.js s'en sert dès son
#  exécution, pas seulement au premier clic.
for PAGE in settings volet ia; do
  IDX="$RACINE/config/includes.chroot/usr/share/lexos/$PAGE/web/index.html"
  if [ ! -r "$IDX" ]; then
    muet "$PAGE : index.html introuvable — le chargement du client n'a pas été vérifié"
    continue
  fi
  L_CLIENT="$(grep -n 'src="/moteur/client.js"' "$IDX" | head -1 | cut -d: -f1)"
  L_APP="$(grep -n 'src="app.js"' "$IDX" | head -1 | cut -d: -f1)"
  if [ -z "$L_CLIENT" ]; then
    non "$PAGE : index.html ne charge pas /moteur/client.js — la fenêtre s'ouvrirait VIDE"
  elif [ -z "$L_APP" ]; then
    non "$PAGE : index.html ne charge pas app.js — l'ordre n'est pas mesurable"
  elif [ "$L_CLIENT" -lt "$L_APP" ]; then
    ok "$PAGE : le client (ligne $L_CLIENT) est chargé avant app.js (ligne $L_APP)"
  else
    non "$PAGE : le client (ligne $L_CLIENT) est chargé APRÈS app.js (ligne $L_APP) : trop tard"
  fi
done

# ===========================================================================
titre "3. LES DEUX FABRIQUES DE FENÊTRE EXISTENT ET SE LISENT"
# ===========================================================================
#  PySide6 n'est pas installé sur le bâti de construction : on ne peut pas
#  OUVRIR une fenêtre ici. On éprouve donc ce qui se mesure sans écran — que
#  les fabriques existent, et que le titre contractuel avec picom est bien
#  celui que la règle attend. Le reste est « non mesuré », pas « vert ».
FEN="$LIB/moteur/fenetre.py"
for F in application taille_ecran fenetre_cadree vue_transparente ferme_au_flou; do
  grep -q "^def $F(" "$FEN" \
    && ok "moteur/fenetre.py fournit $F()" \
    || non "moteur/fenetre.py n'a pas $F()"
done
#  ═══ LE CONTRAT AVEC PICOM, DES DEUX CÔTÉS ═══
#  Le titre de la fenêtre du volet est ce sur quoi la règle picom s'accroche.
#  Il a changé de fichier dans cette étape : s'il a changé de VALEUR au
#  passage, l'extinction « vieille télé » se débranche en silence.
PICOM="$RACINE/config/includes.chroot/usr/share/lexos/picom/lexos-tv.conf"
if [ -r "$PICOM" ]; then
  if grep -q "Volet LexOS" "$FEN" || grep -q 'vue_transparente("Volet LexOS")' "$LIB/volet.py"; then
    grep -q "Volet LexOS" "$PICOM" \
      && ok "le titre « Volet LexOS » est écrit des deux côtés : la règle picom tient" \
      || non "picom ne connaît plus « Volet LexOS » : l'extinction télé se débranche"
  else
    non "le volet ne pose plus le titre « Volet LexOS » — la règle picom s'accroche à du vide"
  fi
else
  muet "lexos-tv.conf introuvable : le contrat picom n'a pas été vérifié"
fi

# ===========================================================================
titre "4. LE FILET DU DESCRIPTEUR TIENT, MÊME SANS staticmethod"
# ===========================================================================
#  ═══ CE POINT A ÉTÉ ÉCRIT DEUX FOIS, ET LA PREMIÈRE NE PROUVAIT RIEN ═══
#  Une fonction rangée dans un attribut de CLASSE est un descripteur :
#  « self.etat_fn() » passe le handler en premier argument. La base lit donc
#  « type(self).etat_fn », qui rend la fonction telle quelle.
#
#  La première mutation censée l'éprouver — remplacer type(self) par self —
#  est restée VERTE. Pas parce que le filet est inutile : parce que le
#  collecteur du banc acceptait un argument, et avalait le handler sans
#  broncher. Un contrôle qui ne casse pas quand on casse le code ne prouve
#  rien du tout, et il valait mieux le découvrir ici qu'après.
#  On éprouve donc le VRAI cas : un collecteur SANS argument, déclaré SANS
#  staticmethod — exactement ce qu'écrira le prochain module qui rejoindra
#  le moteur, en recopiant l'exemple d'à côté.
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : le filet n'a pas été éprouvé"
else
  F="$(python3 - "$LIB" <<'PYEOF' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from moteur import service

def etat_sans_argument():        # AUCUN argument : c'est là que ça casse
    return {"a": 1}

class Nue(service.Service):
    etat_fn = etat_sans_argument  # SANS staticmethod, comme on l'écrira un jour
    def __init__(self):
        pass                      # on n'ouvre aucune socket
    path = "/api/etat"

try:
    print("OK" if Nue()._etat() == {"a": 1} else "FAUX")
except Exception as e:            # noqa: BLE001
    print(f"CASSE {type(e).__name__}")
PYEOF
)"
  case "$F" in
    OK) ok "un collecteur sans argument, déclaré sans staticmethod, est appelé correctement" ;;
    CASSE*) non "la base passe le handler au collecteur ($F) — « self.etat_fn » au lieu de « type(self).etat_fn »" ;;
    *) muet "le filet n'a pas pu être éprouvé ici : $F" ;;
  esac
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
