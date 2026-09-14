#!/usr/bin/env bash
# =============================================================================
#  LES OUTILS DU SYSTÈME, DEMANDÉS UNE FOIS — mesuré en comptant les balayages
# =============================================================================
#  ALEX : « j'aimerais qu'on crée un moteur pour tous les paramètres, que ça
#  soit encore plus fluide et rapide ».
#
#  COMPTÉ : « shutil.which » apparaissait 110 fois dans usr/lib/lexos/ — 75
#  dans settings.py, 16 dans volet.py — et la plupart étaient relues à CHAQUE
#  lecture d'état. Chacune balaie le PATH répertoire par répertoire. Pris un
#  par un ce n'est rien ; quarante collecteurs qui demandent les mêmes dix
#  outils, c'est du gaspillage pur.
#
#  ═══ CE BANC NE RELIT PAS LE CODE, IL COMPTE ═══
#  On remplace shutil.which par un compteur, on lance une lecture d'état
#  complète, et on regarde combien de fois le même outil a été cherché. Un
#  grep sur « lru_cache » aurait été vert même si la mémoire ne servait à rien.
#
#  ⚠ ET LE PIÈGE QUI A FAILLI PASSER. commande_existe() rend un BOOLÉEN, là où
#  shutil.which rendait un chemin ou None. Les vingt-quatre gardes écrites
#  « … is None » seraient devenues TOUJOURS FAUSSES — « si l'outil est absent »
#  serait devenu « jamais », en silence, dans un fichier qui se parse
#  parfaitement. Le point 3 éprouve ces gardes-là pour de vrai.
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

[ -d "$LIB/moteur" ] || { echo "introuvable : $LIB/moteur"; exit 1; }

# ===========================================================================
titre "1. PLUS PERSONNE N'APPELLE shutil.which DIRECTEMENT"
# ===========================================================================
#  On ne lit que les lignes de CODE : les commentaires de ce dépôt citent le
#  nom de ce qu'ils remplacent, et un grep naïf se déclencherait sur
#  l'explication du correctif lui-même — un faux rouge coûte le même prix
#  qu'un faux vert.
RESTANTS=""
for F in "$LIB"/*.py; do
  N="$(grep -v '^[[:space:]]*#' "$F" | grep -c 'shutil\.which' || true)"
  [ "$N" -gt 0 ] && RESTANTS="$RESTANTS $(basename "$F"):$N"
done
if [ -z "$RESTANTS" ]; then
  ok "aucun module de usr/lib/lexos/ n'appelle shutil.which en direct"
else
  non "des appels directs subsistent :$RESTANTS"
fi
#  La liste ne doit que RÉTRÉCIR. boost/ n'est pas encore migré, et c'est
#  écrit : il migrera en dernier, quand le moteur aura fait ses preuves.
BOOST="$(grep -v '^[[:space:]]*#' "$LIB/boost/systeme.py" | grep -c 'shutil\.which' || true)"
if [ "$BOOST" -le 1 ]; then
  ok "boost/systeme.py garde son unique appel (il est la source, pas un doublon)"
else
  non "boost/systeme.py a $BOOST appels — il n'en avait qu'un"
fi

# ===========================================================================
titre "2. LE PATH N'EST BALAYÉ QU'UNE FOIS PAR OUTIL"
# ===========================================================================
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : rien n'a été compté"
else
cat > "$BANC/compte.py" <<'PY'
import collections, importlib.util, json, shutil, sys, types
LIB = sys.argv[1]
sys.path.insert(0, LIB)

#  Le compteur : on remplace shutil.which AVANT d'importer quoi que ce soit,
#  pour que moteur/outils.py lui-même passe par lui.
vrai = shutil.which
appels = collections.Counter()
def espion(nom, *a, **k):
    appels[nom] += 1
    return vrai(nom, *a, **k)
shutil.which = espion

from moteur import outils                      # noqa: E402
outils.oublier()

spec = importlib.util.spec_from_file_location("lexsettings", LIB + "/settings.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                          # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit

appels.clear()
try:
    mod.etat()
except Exception as e:                          # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit
une_lecture = dict(appels)

#  Deuxième lecture immédiate : la mémoire tient encore, on ne doit RIEN
#  rebalayer.
appels.clear()
mod.etat()
deuxieme = sum(appels.values())

#  Apres un clic, on rebalaie : la memoire n'est pas eternelle, et c'est ce
#  qui permet a un outil installe pendant la session d'etre vu.
#
#  ⚠ ON PASSE PAR LE VRAI CHEMIN, ET CE BANC A DU L'APPRENDRE. Appeler
#  outils.oublier() TOUT SEUL ne suffit plus : le cache d'etat (arrive a
#  l'etape 3) repond desormais de memoire, et les collecteurs ne sont meme
#  pas rappeles — donc aucun balayage du PATH, et le controle accusait une
#  memoire qui s'oublie tres bien. Les deux caches se composent, et c'est
#  _apres_action() qui les jette ENSEMBLE : c'est ce que fait un vrai clic,
#  c'est donc ce qu'il faut mesurer.
mod._apres_action("une-action-quelconque")
appels.clear()
mod.etat()
apres_oubli = sum(appels.values())

print(json.dumps({
    "distincts": len(une_lecture),
    "total": sum(une_lecture.values()),
    "pire": max(une_lecture.values()) if une_lecture else 0,
    "pire_nom": max(une_lecture, key=une_lecture.get) if une_lecture else "",
    "deuxieme": deuxieme,
    "apres_oubli": apres_oubli,
}))
PY
  R="$(HOME="$BANC/h" XDG_CONFIG_HOME="$BANC/h/.config" \
       LEXOS_ETAT_DELAI=3 timeout 200 python3 "$BANC/compte.py" "$LIB" 2>"$BANC/compte.err")"
  if [ -z "$R" ]; then
    muet "settings.py n'a pas pu tourner ici : $(head -2 "$BANC/compte.err" | tr '\n' ' ') — non mesuré"
  else
    ERRM="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("erreur",""))' "$R" 2>/dev/null || echo illisible)"
    if [ -n "$ERRM" ]; then
      muet "etat() a levé ici : $ERRM — non mesuré"
    else
      lit(){ python3 -c 'import json,sys;print(json.loads(sys.argv[1])[sys.argv[2]])' "$R" "$1"; }
      DIST="$(lit distincts)"; TOT="$(lit total)"; PIRE="$(lit pire)"
      PNOM="$(lit pire_nom)"; DEUX="$(lit deuxieme)"; OUB="$(lit apres_oubli)"
      printf '     une lecture d'"'"'état : %s outils distincts, %s balayages en tout\n' "$DIST" "$TOT"
      printf '     deuxième lecture ..... %s balayages   |   après oubli : %s\n' "$DEUX" "$OUB"
      if [ "$PIRE" -le 1 ]; then
        ok "aucun outil n'est cherché deux fois dans une même lecture (le pire, « $PNOM », l'est $PIRE fois)"
      else
        non "« $PNOM » a été cherché $PIRE fois dans UNE lecture d'état — la mémoire ne sert à rien"
      fi
      if [ "$DEUX" -eq 0 ]; then
        ok "une deuxième lecture ne rebalaie plus rien du tout"
      else
        non "la deuxième lecture a rebalayé $DEUX fois — la mémoire ne tient pas d'une lecture à l'autre"
      fi
      if [ "$OUB" -ge "$DIST" ]; then
        ok "après un clic, tout est rebalayé ($OUB) : un outil installé pendant la session sera vu"
      else
        non "après un clic, seuls $OUB balayages ont eu lieu pour $DIST outils — un outil installé resterait « absent »"
      fi
    fi
  fi
fi

# ===========================================================================
titre "3. LES GARDES « OUTIL ABSENT » N'ONT PAS ÉTÉ RETOURNÉES"
# ===========================================================================
#  ═══ LE PIÈGE DE CETTE ÉTAPE, ÉPROUVÉ POUR DE VRAI ═══
#  shutil.which rend un chemin ou None ; commande_existe rend un booléen.
#  Les vingt-quatre gardes « … is None » seraient devenues toujours fausses.
#  On ne relit pas le texte : on fait DISPARAÎTRE les outils (un PATH vide)
#  et on regarde si les fonctions disent bien qu'ils sont absents.
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : les gardes n'ont pas été éprouvées"
else
cat > "$BANC/gardes.py" <<'PY'
import importlib.util, json, os, sys
LIB = sys.argv[1]
sys.path.insert(0, LIB)
#  PATH vide : plus AUCUN outil externe n'existe sur cette machine.
os.environ["PATH"] = os.path.join(LIB, "..", "vide-exprès")
from moteur import outils                      # noqa: E402
outils.oublier()
spec = importlib.util.spec_from_file_location("lexsettings", LIB + "/settings.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                          # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit
out = {}
#  _run doit REFUSER, avec le motif — et surtout ne pas prétendre réussir.
#  ⚠ ET IL NE DOIT PAS LEVER NON PLUS. Première version de ce banc : la
#  garde retournée laissait _run() lancer la commande, subprocess levait
#  FileNotFoundError, le sondage mourait — et le banc annonçait « non
#  mesuré » au lieu de rouge. Un défaut réel sortait en « je n'ai pas pu
#  regarder », ce qui passe en CI. Une garde qui laisse passer EST le
#  défaut : on l'attrape et on le compte comme tel.
try:
    r = mod._run(["nmcli", "radio", "wifi"])
    out["run_ok"] = bool(r.get("ok"))
    out["run_motif"] = r.get("erreur", "")
    out["run_leve"] = ""
except Exception as e:                          # noqa: BLE001
    out["run_ok"] = False
    out["run_motif"] = ""
    out["run_leve"] = f"{type(e).__name__}: {e}"
#  Un collecteur dont l'outil manque doit le DIRE, pas inventer.
try:
    out["wifi"] = mod._wifi_etat()
except Exception as e:                          # noqa: BLE001
    out["wifi"] = {"leve": f"{type(e).__name__}: {e}"}
out["existe"] = outils.commande_existe("nmcli")
print(json.dumps(out, default=str))
PY
  G="$(HOME="$BANC/h" XDG_CONFIG_HOME="$BANC/h/.config" timeout 120 python3 "$BANC/gardes.py" "$LIB" 2>"$BANC/gardes.err")"
  if [ -z "$G" ]; then
    muet "l'épreuve des gardes n'a pas pu tourner : $(head -2 "$BANC/gardes.err" | tr '\n' ' ')"
  else
    EXISTE="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("existe"))' "$G")"
    RUNOK="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("run_ok"))' "$G")"
    MOTIF="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("run_motif",""))' "$G")"
    [ "$EXISTE" = "False" ] \
      && ok "avec un PATH vide, commande_existe() dit bien « absent »" \
      || non "avec un PATH vide, commande_existe() prétend encore que nmcli est là"
    LEVE="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("run_leve",""))' "$G")"
    if [ -n "$LEVE" ]; then
      non "_run() a LANCÉ la commande alors qu'aucun outil n'existe ($LEVE) — la garde a été retournée"
    elif [ "$RUNOK" = "False" ]; then
      ok "_run() refuse un outil absent au lieu de prétendre avoir réussi"
    else
      non "_run() a rendu ok=True sans aucun outil sur la machine — la garde « is None » a été retournée"
    fi
    case "$MOTIF" in
      *absent*) ok "et il DIT lequel : « $MOTIF »" ;;
      "")       if [ -n "$LEVE" ]; then non "aucun motif : la commande a levé au lieu d'être refusée"
                else non "le refus ne porte aucun motif — un bouton mort sans explication"; fi ;;
      *)        ok "le refus porte un motif : « $MOTIF »" ;;
    esac
  fi
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
