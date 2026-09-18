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

# ===========================================================================
titre "6. CE QU'UNE ACTION PÉRIME PENDANT UNE LECTURE NE SORT PAS QUAND MÊME"
# ===========================================================================
#  ═══ LE DÉFAUT QU'AUCUNE CLÉ N'AURAIT RÉPARÉ ═══
#  Les lectures durent des secondes et se font HORS du verrou — c'est voulu,
#  sinon le clic suivant attendrait derrière la lecture en cours. Mais une
#  lecture partie AVANT un clic se termine APRÈS lui, et rendait alors l'état
#  d'AVANT : rangé dans le cache avec un TTL tout neuf, puis servi à la page,
#  qui REMPLACE toute la grille. La tuile se rallumait par-dessus l'optimiste,
#  et le clic suivant faisait l'inverse de son étiquette.
#
#  Deux moitiés, et la première version n'en avait corrigé qu'une :
#    · la clé RELUE pendant l'action — corrigée d'abord ;
#    · la clé servie DEPUIS LE CACHE dans le même appel, jugée fraîche à
#      l'entrée et rendue à la sortie sans jamais être revérifiée. C'est le
#      cas ORDINAIRE depuis les clés partielles : un clic ne périme qu'une
#      clé, donc la lecture d'après a une clé à relire et six succès de cache.
#
#  Ce qui sort d'un appel traversé par une action ne vaut pas « faux » : ça
#  vaut « je n'ai pas pu lire ». On exige donc le REPLI, pas la valeur d'avant.
COURSE="$(python3 - "$LIB" <<'COURSE_PY' 2>&1
import sys, threading, importlib
LIB = sys.argv[1]; sys.path.insert(0, LIB)
moteur = importlib.import_module("moteur.registre")

def course(perime_quoi, cle_lente="a"):
    """Renvoie (rendu_a, rendu_b) pour une action tombée PENDANT la lecture."""
    C = moteur.Cache()
    #  Cache chaud sur les deux clés.
    C.lire({"a": lambda: "A0", "b": lambda: "B0"}, 5)
    parti, liberer = threading.Event(), threading.Event()

    def lente():
        parti.set(); liberer.wait(5); return "A1"

    res = {}
    fil = threading.Thread(target=lambda: res.update(C.lire(
        {"a": lente, "b": lambda: "B1"}, 5,
        replis={"a": "REPLI", "b": "REPLI"})))
    #  « a » a expiré (on le périme avant) pour qu'il soit RELU, « b » reste
    #  en mémoire et sera un succès de cache.
    C.perime(["a"])
    fil.start()
    if not parti.wait(5):
        return ("PAS_PARTI", "PAS_PARTI")
    C.perime(perime_quoi)          # LE CLIC, pendant la lecture
    liberer.set(); fil.join(5)
    return (res.get("a"), res.get("b"))

a, b = course(["b"])               # l'action périme la clé SERVIE DU CACHE
print("HIT a=%r b=%r" % (a, b))
a, b = course(["a"])               # l'action périme la clé RELUE
print("RELUE a=%r b=%r" % (a, b))
a, b = course(None)                # invalidation TOTALE
print("TOTAL a=%r b=%r" % (a, b))
COURSE_PY
)"

#  ⚠ UNE LIGNE PRÉSENTE MAIS DIFFÉRENTE EST UN ROUGE, PAS UN « NON MESURÉ ».
#  Première version : le fourre-tout de fin retombait sur « muet ». Une
#  mutation qui faisait tout jeter au lieu de la seule clé périmée ne rendait
#  donc AUCUNE des deux formes attendues, tombait dans le fourre-tout, et le
#  banc annonçait « rien n'a été mesuré » au lieu de rougir. Un contrôle qui
#  se déclare incompétent devant un comportement inattendu ne garde rien.
attendu_ligne() {   # attendu_ligne <étiquette> <valeur attendue> <phrase ok> <phrase rouge>
	local ligne; ligne="$(printf '%s\n' "$COURSE" | grep "^$1 " || true)"
	if [ -z "$ligne" ]; then
		muet "« $1 » n'a pas été mesuré : $(printf '%s' "$COURSE" | tail -2 | tr '\n' ' ')"
	elif [ "${ligne#"$1" }" = "$2" ]; then
		ok "$3"
	else
		non "$4 — mesuré : ${ligne#"$1" }"
	fi
}

case "$COURSE" in
	*PAS_PARTI*) muet "le collecteur ne s'est pas bloqué : la course n'a pas pu être forcée" ;;
	*)
		attendu_ligne HIT "a='A1' b='REPLI'" \
			"une clé servie du cache et périmée pendant l'appel sort en « je n'ai pas pu lire »" \
			"la clé servie du cache ne sort pas comme elle devrait : sa valeur d'AVANT le clic ferait mentir la tuile"
		attendu_ligne RELUE "a='REPLI' b='B0'" \
			"…et une clé RELUE pendant l'appel aussi, sans toucher à la clé saine" \
			"la clé relue pendant l'action, ou la clé saine à côté, n'est pas celle attendue"
		attendu_ligne TOTAL "a='REPLI' b='REPLI'" \
			"…et une invalidation TOTALE emporte les deux, y compris la clé du cache" \
			"l'invalidation totale ne prend pas exactement les deux clés"
		;;
esac

#  ═══ ET SURTOUT : SANS ACTION, ON NE JETTE RIEN ═══
#  Le risque symétrique de tout ce qui précède : un filtre trop large qui
#  remplacerait des valeurs FRAÎCHES par le repli. Le cache ne servirait alors
#  plus jamais, silencieusement — la lenteur d'avant, sans un mot.
SANS_CLIC="$(python3 - "$LIB" <<'SANS_PY' 2>&1
import sys, importlib
LIB = sys.argv[1]; sys.path.insert(0, LIB)
moteur = importlib.import_module("moteur.registre")
C = moteur.Cache()
r1 = C.lire({"a": lambda: "A", "b": lambda: "B"}, 5, replis={"a": "REPLI", "b": "REPLI"})
rappels = []
r2 = C.lire({"a": lambda: (rappels.append(1), "A2")[1], "b": lambda: "B2"}, 5,
            replis={"a": "REPLI", "b": "REPLI"})
print("SANS_CLIC r1=%r r2=%r relu=%s"
      % (sorted(r1.items()), sorted(r2.items()), "oui" if rappels else "non"))
SANS_PY
)"
case "$SANS_CLIC" in
	"SANS_CLIC r1=[('a', 'A'), ('b', 'B')] r2=[('a', 'A'), ('b', 'B')] relu=non")
		ok "sans action, aucune valeur fraîche n'est jetée et le cache sert bien" ;;
	SANS_CLIC*) non "une lecture sans action ne rend pas ses vraies valeurs : $SANS_CLIC" ;;
	*) muet "la lecture sans action n'a pas pu être mesurée : $SANS_CLIC" ;;
esac

#  Et le cache doit rester VIDE de ce qu'on vient de périmer : ce qui a bougé
#  ne doit pas non plus avoir été rangé au passage.
GARDE="$(python3 - "$LIB" <<'GARDE_PY' 2>&1
import sys, threading, importlib
LIB = sys.argv[1]; sys.path.insert(0, LIB)
moteur = importlib.import_module("moteur.registre")
C = moteur.Cache()
parti, liberer = threading.Event(), threading.Event()
def lente():
    parti.set(); liberer.wait(5); return "AVANT"
fil = threading.Thread(target=lambda: C.lire({"x": lente}, 5))
fil.start(); parti.wait(5)
C.perime(["x"])
liberer.set(); fil.join(5)
rappels = []
C.lire({"x": lambda: (rappels.append(1), "APRES")[1]}, 5)
print("RANGE %s" % ("non" if rappels else "oui"))
GARDE_PY
)"
case "$GARDE" in
	"RANGE non") ok "…et rien de périmé n'a été rangé au passage : la demande suivante relit" ;;
	"RANGE oui") non "la valeur d'avant le clic a été RANGÉE : elle sera servie pendant tout le TTL" ;;
	*) muet "le rangement n'a pas pu être vérifié : $GARDE" ;;
esac

# ===========================================================================
titre "7. L'ÂGE SERVI NE DÉPASSE JAMAIS LE TTL, MÊME QUAND UN OUTIL TRAÎNE"
# ===========================================================================
#  ═══ LE TTL PARTAIT DE LA FIN DU LOT, PAS DE LA LECTURE ═══
#  de_front lance les collecteurs ENSEMBLE et rend la main au plus lent.
#  L'échéance était calculée après ce retour : une clé lue en 0 ms recevait
#  donc la même que celle lue en 1,9 s, et le périmé servi valait « durée du
#  lot + TTL » au lieu de « TTL ».
#
#  Ce n'est pas un réglage qu'on pourrait discuter : ce fichier GRAVE son
#  plafond dans le code (TTL_MAX = 2.0) en écrivant qu'« une variable
#  d'environnement mal réglée ne doit pas faire mentir le volet pendant dix
#  secondes ». Un outil lent le faisait mentir pendant 3,25 s dans le volet et
#  5,25 s dans les Paramètres. Et le cas est nommé par le dépôt lui-même :
#  « une imprimante réseau éteinte, bluetoothctl sans adaptateur, nmcli
#  pendant un balayage ».
#
#  ON MESURE LE COMPORTEMENT : un lot où une clé répond tout de suite et
#  l'autre traîne, puis on attend et on regarde LAQUELLE est relue.
AGE="$(python3 - "$LIB" <<'AGE_PY' 2>&1
import sys, time, importlib
LIB = sys.argv[1]; sys.path.insert(0, LIB)
moteur = importlib.import_module("moteur.registre")

TTL, LENT = 1.5, 0.8
C = moteur.Cache(TTL)
rappels = []

def vite():
    rappels.append("vite"); return "V"

def lent():
    time.sleep(LENT); rappels.append("lent"); return "L"

C.lire({"vite": vite, "lent": lent}, 5)      # le lot dure LENT
rappels.clear()
#  On se place APRÈS l'échéance de « vite » (lue à t+0) et AVANT celle de
#  « lent » (lue à t+0,8) : à t+1,7 avec un TTL de 1,5.
time.sleep(TTL - LENT + 0.2)
C.lire({"vite": vite, "lent": lent}, 5)
print("RELUES " + ",".join(sorted(rappels)) if rappels else "RELUES -")
AGE_PY
)"
case "$AGE" in
	"RELUES vite")
		ok "chaque clé porte l'heure de SA lecture : la rapide expire à l'heure, la lente garde la sienne" ;;
	"RELUES -")
		non "aucune clé n'est relue : l'échéance part de la fin du lot, donc la clé rapide est servie bien au-delà du TTL" ;;
	"RELUES lent,vite")
		muet "les deux ont été relues : la machine du banc est trop lente pour distinguer les deux échéances" ;;
	*) muet "l'âge servi n'a pas pu être mesuré : $AGE" ;;
esac

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
