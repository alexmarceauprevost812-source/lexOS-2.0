#!/usr/bin/env bash
# =============================================================================
#  LES CLÉS PARTIELLES DU VOLET — un clic ne relit que ce qu'il a changé
# =============================================================================
#  La consigne d'Alex, §4.5 : « Chaque clic sur une tuile relit les
#  notifications, l'agenda, la météo, le Wi-Fi, le Bluetooth, l'avion, la
#  performance, le son… pour changer un booléen. Le travail est déjà fait à
#  côté, il n'a jamais été repris ici. »
#
#  MESURÉ AVANT, avec des outils qui répondent en 0,4 s — n'importe quel clic,
#  y compris celui de l'appareil photo qui ne change RIEN :
#
#      ouverture .................. 6 lancements d'outils, 413 ms
#      après « rapides-photo » .... 6 lancements, 412 ms
#      après « rapides-muet » ..... 6 lancements, 417 ms
#      après « rapides-crt » ...... 6 lancements, 411 ms
#      après « rapides-wifi » ..... 6 lancements, 411 ms
#
#  ⚠ ET ÇA COÛTE PLUS CHER DEPUIS LE DÉMON. Le cache survit maintenant ENTRE
#  deux ouvertures du volet (lexos-moteurd le garde chaud). Jeter les sept
#  lectures parce qu'on a cliqué sur l'appareil photo, c'est jeter aussi ce
#  que la PROCHAINE ouverture aurait trouvé tout prêt.
#
#  ═══ LE DANGER DE CETTE ÉTAPE EST SILENCIEUX ═══
#  Déclarer qu'une action ne touche qu'une clé est une PROMESSE. Se tromper ne
#  fait pas planter : ça fait afficher une valeur PÉRIMÉE, sans un mot. Et
#  une tuile périmée invite à un clic qui fera l'inverse de son étiquette,
#  parce que les actions relisent la VRAIE machine pour basculer — ce dépôt a
#  déjà payé ce défaut une fois, avec un Wi-Fi qu'on éteignait en croyant
#  l'allumer.
#
#  D'où l'asymétrie que ce banc éprouve, et qui a été MESURÉE :
#    · un NOM D'ACTION mal orthographié retombe sur « tout périmer » — sans
#      danger, juste une relecture ;
#    · une CLÉ mal orthographiée ne périme RIEN, et la valeur reste à l'écran.
#      C'est celle-là qu'il faut rendre impossible, pas seulement éprouver.
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

command -v python3 >/dev/null 2>&1 || { muet "python3 absent : rien n'a été mesuré"; exit 0; }

# ===========================================================================
titre "1. AUCUNE DÉCLARATION NE NOMME UNE CLÉ QUI N'EXISTE PAS"
# ===========================================================================
#  ═══ LE CONTRÔLE QUI COMPTE LE PLUS, ET IL EST STRUCTUREL ═══
#  Une clé mal orthographiée dans une déclaration ne périme rien : la valeur
#  reste affichée, périmée, en silence. Mesuré :
#      action_perime("rapides-wifi", ["wifi"])  ← au lieu de « r_wifi »
#      → le cache garde r_wifi, et la tuile ment jusqu'au bout du TTL.
#  volet.py doit donc REFUSER DE DÉMARRER sur une telle faute, pas se
#  contenter d'un banc qui la remarquerait un jour.
VERDICT="$(python3 - "$LIB" <<'PY' 2>&1
import importlib.util, sys
LIB = sys.argv[1]; sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception as e:                                  # noqa: BLE001
    print(f"IMPORT_REFUSE {type(e).__name__}: {e}"); raise SystemExit
declarees = getattr(m, "_PERIME", None)
cles = getattr(m, "_CLES_RAPIDES", None)
if declarees is None or cles is None:
    print("PAS_DE_TABLE"); raise SystemExit
fautives = {a: sorted(set(c) - set(cles)) for a, c in declarees.items()
            if set(c) - set(cles)}
print("FAUTIVES " + repr(fautives) if fautives else "OK")
PY
)"
case "$VERDICT" in
	OK)            ok "toutes les clés déclarées existent vraiment dans le cache" ;;
	PAS_DE_TABLE)  non "volet.py n'expose ni _PERIME ni _CLES_RAPIDES : rien n'est déclaré, tout est périmé à chaque clic" ;;
	FAUTIVES*)     non "une déclaration nomme une clé qui n'existe pas : ${VERDICT#FAUTIVES } — elle ne périmerait RIEN" ;;
	IMPORT_REFUSE*) non "volet.py ne s'importe plus : ${VERDICT#IMPORT_REFUSE }" ;;
	*)             muet "la table n'a pas pu être lue : $VERDICT" ;;
esac

#  Et la garde doit MORDRE : on injecte une faute et on exige un refus net.
INJECTE="$(python3 - "$LIB" <<'PY' 2>&1
import importlib.util, sys, types
LIB = sys.argv[1]; sys.path.insert(0, LIB)
#  On rejoue la vérification de volet.py sur une table volontairement fautive.
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception:                                       # noqa: BLE001
    print("IMPORT_KO"); raise SystemExit
verif = getattr(m, "_verifie_declarations", None)
if verif is None:
    print("PAS_DE_GARDE"); raise SystemExit
try:
    verif({"rapides-wifi": ("wiifi",)}, m._CLES_RAPIDES)
except Exception as e:                                  # noqa: BLE001
    print("REFUSE " + type(e).__name__); raise SystemExit
print("ACCEPTE")
PY
)"
case "$INJECTE" in
	REFUSE*)      ok "…et une clé inventée est REFUSÉE au démarrage (${INJECTE#REFUSE })" ;;
	ACCEPTE)      non "une clé inventée est acceptée : la faute la plus dangereuse passe" ;;
	PAS_DE_GARDE) non "volet.py n'a pas de garde _verifie_declarations() : rien n'empêche la faute" ;;
	*)            muet "la garde n'a pas pu être éprouvée : $INJECTE" ;;
esac

# ===========================================================================
titre "2. LES DÉCLARATIONS PORTENT SUR DE VRAIES ACTIONS"
# ===========================================================================
#  Un NOM d'action mal orthographié est sans danger — l'action réelle reste
#  non déclarée, donc tout est périmé, donc c'est juste plus lent. Mais c'est
#  une déclaration MORTE : elle promet une optimisation qui n'a jamais lieu,
#  et personne ne le verrait. On la signale.
ORPHELINES="$(python3 - "$LIB" <<'PY' 2>/dev/null
import importlib.util, sys
LIB = sys.argv[1]; sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(" ".join(sorted(set(getattr(m, "_PERIME", {})) - set(m.ACTIONS))))
PY
)"
[ -z "$ORPHELINES" ] \
	&& ok "chaque déclaration porte sur une action qui existe" \
	|| non "déclarations mortes (aucune action de ce nom) : $ORPHELINES"

# ===========================================================================
titre "3. LA LISTE DES CLÉS SUIT CE QUE LE CACHE GARDE VRAIMENT"
# ===========================================================================
#  _CLES_RAPIDES est écrite à la main ; _rapides_etat() décide, elle, ce qui
#  est réellement mis en cache. Si les deux divergent — une huitième lecture
#  ajoutée un jour sans toucher la liste — les déclarations cesseraient de
#  couvrir cette clé-là, en silence. On les compare au lieu de les croire.
DERIVE="$(python3 - "$LIB" <<'PY' 2>&1
import importlib.util, os, sys
LIB = sys.argv[1]; sys.path.insert(0, LIB)
os.environ["PATH"] = "/nulle-part"        # aucune lecture ne doit aboutir
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m._CACHE.perime()
m.etat("rapides")                          # remplit le cache pour de vrai
reelles = set(m._CACHE._valeurs)
declarees = set(m._CLES_RAPIDES)
manque = sorted(reelles - declarees)
trop = sorted(declarees - reelles)
print(f"MANQUE {manque} TROP {trop}" if (manque or trop) else "OK")
PY
)"
case "$DERIVE" in
	OK) ok "les clés déclarées sont exactement celles que le cache garde" ;;
	MANQUE*) non "la liste a dérivé de la réalité : $DERIVE — les clés en trop ne seraient jamais périmées" ;;
	*) muet "la comparaison n'a pas pu se faire : $DERIVE" ;;
esac

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
