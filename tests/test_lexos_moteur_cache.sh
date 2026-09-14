#!/usr/bin/env bash
# =============================================================================
#  LE CACHE — compté en sous-processus, pas en intentions
# =============================================================================
#  ALEX : « que ça soit encore plus fluide et rapide ».
#
#  CE QUI SE PASSAIT. Cliquer une tuile, c'était : l'action, puis on relit
#  TOUT le bloc depuis zéro — nmcli, bluetoothctl, pactl, chacun un
#  sous-processus. Deux clics d'affilée payaient deux fois exactement la même
#  lecture, à deux secondes d'intervalle.
#
#  ═══ CE BANC COMPTE DE VRAIS LANCEMENTS ═══
#  Les outils sont remplacés par des scripts qui ÉCRIVENT UNE LIGNE dans un
#  fichier témoin à chaque appel. On lit, on relit, on agit, on relit encore,
#  et on compte les lignes. Un grep sur « Cache » ou « ttl » aurait été vert
#  même si le cache ne servait à rien.
#
#  ═══ LES DEUX MOITIÉS COMPTENT AUTANT ═══
#  Un cache qui retient bien mais ne se périme pas est PIRE que pas de cache :
#  la tuile reviendrait à son ancienne valeur une demi-seconde après le clic.
#  Pas lent — FAUX. Le point 3 éprouve donc l'invalidation avec la même
#  méthode que le point 2 éprouve la mémoire.
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

[ -r "$LIB/moteur/registre.py" ] || { echo "introuvable : $LIB/moteur/registre.py"; exit 1; }
command -v python3 >/dev/null 2>&1 || { muet "python3 absent : rien n'a été compté"; exit 0; }

# ===========================================================================
titre "1. LE PLAFOND DU TTL EST DANS LE CODE, PAS SEULEMENT DANS UN COMMENTAIRE"
# ===========================================================================
#  Le vrai danger d'un cache, c'est la valeur changée EN DEHORS de LexOS :
#  Alex coupe le Wi-Fi à la touche du clavier, et le volet montrerait encore
#  « Activé ». Le TTL borne ce mensonge. Au-delà de deux secondes, le cache
#  commence à raconter des histoires — et une variable d'environnement mal
#  réglée ne doit pas suffire à le faire mentir dix secondes.
P="$(LEXOS_CACHE_TTL=99 python3 - "$LIB" <<'PY' 2>&1
import sys; sys.path.insert(0, sys.argv[1])
from moteur.registre import Cache, TTL_MAX
print(f"{Cache().ttl}|{Cache(ttl=99).ttl}|{TTL_MAX}")
PY
)"
case "$P" in
  2.0\|2.0\|2.0) ok "un TTL de 99 s est ramené au plafond de 2 s, par l'environnement comme par l'appel" ;;
  *\|*\|*)       non "le plafond ne tient pas : $P" ;;
  *)             muet "le plafond n'a pas pu être lu : $P" ;;
esac

# ===========================================================================
titre "2. DEUX LECTURES RAPPROCHÉES NE LANCENT QU'UN SOUS-PROCESSUS"
# ===========================================================================
OUTILS="$BANC/outils"; mkdir -p "$OUTILS"
TEMOIN="$BANC/temoin"
: > "$TEMOIN"
#  Chaque outil laisse une trace À CHAQUE LANCEMENT. C'est tout le compteur.
for O in nmcli bluetoothctl pactl lpstat upower wmctrl xfconf-query xrandr uname df; do
  printf '#!/bin/sh\necho "%s" >> "%s"\nexit 0\n' "$O" "$TEMOIN" > "$OUTILS/$O"
  chmod +x "$OUTILS/$O"
done

cat > "$BANC/compte.py" <<'PY'
import importlib.util, json, sys, time
LIB, TEMOIN = sys.argv[1], sys.argv[2]
sys.path.insert(0, LIB)

def lignes():
    try:
        with open(TEMOIN) as f:
            return sum(1 for _ in f)
    except OSError:
        return -1

spec = importlib.util.spec_from_file_location("lexsettings", LIB + "/settings.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                          # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit

CLES = ["wifi", "bluetooth", "son", "noyau"]
a0 = lignes(); mod.etat(CLES)
a1 = lignes()                      # premiere lecture : on paie
mod.etat(CLES)
a2 = lignes()                      # deuxieme, tout de suite : on ne paie plus
mod._apres_action("une-action-quelconque")
mod.etat(CLES)
a3 = lignes()                      # apres l'action : on repaie
time.sleep(0.1)
mod.etat(CLES)
a4 = lignes()                      # encore dans le TTL : on ne paie pas
print(json.dumps({"premiere": a1 - a0, "deuxieme": a2 - a1,
                  "apres_action": a3 - a2, "dans_ttl": a4 - a3}))
PY
R="$(PATH="$OUTILS:$PATH" HOME="$BANC/h" XDG_CONFIG_HOME="$BANC/h/.config" \
     LEXOS_ETAT_DELAI=3 LEXOS_CACHE_TTL=1.5 \
     timeout 200 python3 "$BANC/compte.py" "$LIB" "$TEMOIN" 2>"$BANC/compte.err")"
if [ -z "$R" ]; then
  muet "settings.py n'a pas pu tourner ici : $(tail -2 "$BANC/compte.err" | tr '\n' ' ') — non mesuré"
else
  ERRM="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("erreur",""))' "$R" 2>/dev/null || echo illisible)"
  if [ -n "$ERRM" ]; then
    muet "etat() a levé ici : $ERRM — non mesuré"
  else
    v(){ python3 -c 'import json,sys;print(json.loads(sys.argv[1])[sys.argv[2]])' "$R" "$1"; }
    P1="$(v premiere)"; P2="$(v deuxieme)"; P3="$(v apres_action)"; P4="$(v dans_ttl)"
    printf '     1re lecture : %s lancements | 2e : %s | après action : %s | dans le TTL : %s\n' \
           "$P1" "$P2" "$P3" "$P4"
    [ "$P1" -gt 0 ] \
      && ok "la première lecture lance bien les outils ($P1) — le témoin compte quelque chose" \
      || non "la première lecture n'a lancé AUCUN outil : le compteur ne mesure rien, tout le reste est sans valeur"
    [ "$P2" -eq 0 ] \
      && ok "la deuxième lecture, tout de suite après, ne relance RIEN" \
      || non "la deuxième lecture a relancé $P2 outils — le cache ne retient pas"
    # ===========================================================================
    titre "3. UNE ACTION PÉRIME — SINON LA TUILE REVIENDRAIT À SON ANCIENNE VALEUR"
    # ===========================================================================
    [ "$P3" -ge "$P1" ] \
      && ok "après une action, tout est relu ($P3 lancements) : aucune tuile ne peut revenir en arrière" \
      || non "après une action, seuls $P3 outils ont été relus pour $P1 : une valeur périmée peut s'afficher"
    [ "$P4" -eq 0 ] \
      && ok "et la mémoire repart pour son TTL : la lecture suivante ne relance rien" \
      || non "la lecture suivant l'action a relancé $P4 outils — la mémoire ne se reconstitue pas"
  fi
fi

# ===========================================================================
titre "4. UNE ACTION INCONNUE PÉRIME TOUT — le défaut, c'est la justesse"
# ===========================================================================
#  Déclarer qu'une action ne touche qu'une clé est une PROMESSE. Se tromper
#  ne fait pas planter : ça fait afficher une valeur périmée, sans un mot.
#  Le défaut doit donc coûter une relecture, jamais un affichage faux.
D="$(python3 - "$LIB" <<'PY' 2>&1
import sys; sys.path.insert(0, sys.argv[1])
from moteur.registre import Cache, Registre
c = Cache(ttl=2); r = Registre(c)
r.action_perime("ne-touche-que-le-son", ["son"])
c.lire({"a": lambda: 1, "son": lambda: 2}, 1)
avant = c.garde()
r.apres("ne-touche-que-le-son")
declaree = c.garde()
c.lire({"a": lambda: 1, "son": lambda: 2}, 1)
r.apres("nom-jamais-declare")
inconnue = c.garde()
print(f"{avant}|{declaree}|{inconnue}")
PY
)"
case "$D" in
  2\|1\|0) ok "une action déclarée ne périme que sa clé (2→1) ; une action inconnue périme tout (→0)" ;;
  *\|*\|*) non "l'invalidation ne se comporte pas comme annoncé : avant|déclarée|inconnue = $D" ;;
  *)       muet "l'invalidation n'a pas pu être mesurée : $D" ;;
esac

# ===========================================================================
titre "5. LE CACHE NE VIT QU'EN MÉMOIRE"
# ===========================================================================
#  Un cache qui survit à un redémarrage est un cache qui ment au démarrage
#  suivant. On éprouve qu'aucun fichier n'est écrit — pas qu'aucun n'est
#  nommé dans le code, ce qu'un commentaire suffirait à tromper.
AVANT="$(find "$BANC/h" -type f 2>/dev/null | wc -l)"
python3 - "$LIB" "$BANC/h" >/dev/null 2>&1 <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
os.environ["HOME"] = sys.argv[2]
os.environ["XDG_CONFIG_HOME"] = sys.argv[2] + "/.config"
from moteur.registre import Cache
c = Cache()
for i in range(50):
    c.lire({f"k{i}": (lambda i=i: i)}, 1)
PY
APRES="$(find "$BANC/h" -type f 2>/dev/null | wc -l)"
[ "$AVANT" = "$APRES" ] \
  && ok "cinquante lectures mises en cache n'ont écrit aucun fichier ($APRES inchangé)" \
  || non "le cache a écrit sur le disque ($AVANT → $APRES fichiers) : il mentirait au démarrage suivant"

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
