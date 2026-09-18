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

# ===========================================================================
titre "4. CE QU'UN CLIC COÛTE VRAIMENT — MESURÉ, OUTIL PAR OUTIL"
# ===========================================================================
#  ═══ ON COMPTE LES LANCEMENTS, PAS LES MILLISECONDES ═══
#  Une durée dépend de la machine qui fait tourner le banc ; un nombre de
#  lancements d'outils, non. Les sept lectures se répartissent ainsi :
#      r_wifi, r_wwan → nmcli (une chacune) · bt_brut → bluetoothctl (une)
#      son → pactl (trois) · perf, theme, crt → un fichier local (zéro)
#  Soit SIX lancements pour une grille complète. C'est ce nombre-là que la
#  table des clés partielles doit faire tomber, et c'est lui qu'on mesure.
#
#  ⚠ CE QUE CE POINT NE PROUVE PAS. Il ne prouve pas que la table dit vrai
#  sur la MACHINE — qu'« éteindre le Bluetooth » change bien le son. Ça, ça
#  se trace dans lexos-net, lexos-perf et son.py, et c'est écrit clé par clé
#  au-dessus de la table, dans volet.py. Ce point-ci prouve l'autre moitié :
#  que la déclaration se traduit vraiment en outils qu'on ne relance plus. Et
#  il ÉPINGLE les chiffres — retirer une clé de la table sans refaire le
#  tracé rougit ici, au lieu de passer inaperçu.
FAUX="$BANC/bin"; mkdir -p "$FAUX"
CPT="$BANC/lancements"; : > "$CPT"
CONF="$BANC/config"; mkdir -p "$CONF/lexos"

cat > "$FAUX/nmcli" <<'OUTIL'
#!/bin/sh
printf 'nmcli\n' >> "$LEXOS_BANC_CPT"
case "$3" in
	wwan) printf 'missing\n' ;;
	*)    printf 'enabled\n' ;;
esac
OUTIL
cat > "$FAUX/bluetoothctl" <<'OUTIL'
#!/bin/sh
printf 'bluetoothctl\n' >> "$LEXOS_BANC_CPT"
printf 'Controller AA:BB:CC:DD:EE:FF\n\tPowered: yes\n'
OUTIL
cat > "$FAUX/pactl" <<'OUTIL'
#!/bin/sh
printf 'pactl\n' >> "$LEXOS_BANC_CPT"
case "$1" in
	get-sink-volume) printf 'Volume: front-left: 45000 /  69%% / -9.32 dB\n' ;;
	*)               printf 'Mute: no\n' ;;
esac
OUTIL
chmod +x "$FAUX"/nmcli "$FAUX"/bluetoothctl "$FAUX"/pactl

MESURE="$(python3 - "$LIB" "$FAUX" "$CPT" "$CONF" <<'MESURE_PY' 2>&1
import importlib.util, os, sys
LIB, BIN, CPT, CONF = sys.argv[1:5]
#  La machine n'existe QUE dans ce dossier : aucun vrai nmcli, aucun vrai
#  pactl ne peut répondre à la place des faux.
os.environ["PATH"] = BIN
os.environ["LEXOS_BANC_CPT"] = CPT
os.environ["XDG_CONFIG_HOME"] = CONF
sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def lus():
    try:
        return sorted(l.strip() for l in open(CPT) if l.strip())
    except OSError:
        return []

def remet():
    open(CPT, "w").close()

def cout(action):
    m._CACHE.perime()
    m.etat("rapides")          # l'ouverture du volet : le cache se remplit
    m._apres_action(action)    # LE CLIC — c'est lui qu'on mesure
    remet()
    m.etat("rapides")          # la grille se redessine
    return lus()

m._CACHE.perime(); remet(); m.etat("rapides")
print("ouverture " + (",".join(lus()) or "-"))
for a in ("rapides-partage", "rapides-crt", "rapides-theme", "rapides-wifi",
          "rapides-muet", "rapides-photo", "rapides-bt", "rapides-avion",
          "rapides-perf", "action-inventee"):
    print(a + " " + (",".join(cout(a)) or "-"))
MESURE_PY
)"

TOUT="bluetoothctl,nmcli,nmcli,pactl,pactl,pactl"
attendu() {          # attendu <action> <liste attendue> <phrase>
	local ligne obtenu
	ligne="$(printf '%s\n' "$MESURE" | grep "^$1 " || true)"
	obtenu="${ligne#"$1" }"
	if [ -z "$ligne" ]; then
		muet "« $1 » n'a pas pu être mesuré : $(printf '%s' "$MESURE" | tail -2 | tr '\n' ' ')"
	elif [ "$obtenu" = "$2" ]; then
		ok "$3"
	else
		non "$3 — mesuré : ${obtenu:-rien} (attendu : $2)"
	fi
}

attendu ouverture "$TOUT" "l'ouverture lit la machine : 6 lancements d'outils"
attendu rapides-partage "-" "« Partager » ne relance RIEN : il n'ouvre qu'une fenêtre (6 → 0)"
attendu rapides-crt "-" "les effets TV ne relancent rien : seul un fichier local a changé (6 → 0)"
attendu rapides-theme "-" "le thème ne relance rien : seul un fichier local a changé (6 → 0)"
attendu rapides-wifi "nmcli" "le Wi-Fi ne relit que le Wi-Fi (6 → 1)"
attendu rapides-muet "pactl,pactl,pactl" "le bouton muet ne relit que le son (6 → 3)"
attendu rapides-photo "pactl,pactl,pactl" "l'appareil photo ne relit que le son — le mode vidéo ouvre un flux de capture (6 → 3)"
attendu rapides-bt "bluetoothctl,pactl,pactl,pactl" "le Bluetooth relit le Bluetooth ET le son — la sortie par défaut a pu disparaître avec lui (6 → 4)"
attendu rapides-avion "$TOUT" "le mode avion relit les trois radios et le son : aucun gain, et c'est juste"
attendu rapides-perf "$TOUT" "« performance » n'est pas déclarée : elle périme TOUT, le défaut sûr"
attendu action-inventee "$TOUT" "une action inconnue périme TOUT — un nom mal orthographié coûte une relecture, jamais un affichage faux"

# ===========================================================================
titre "5. LE CACHE SERT LES VALEURS, IL NE SE CONTENTE PAS DE NE PAS LIRE"
# ===========================================================================
#  ═══ LA FAUTE QUE LE POINT 4 NE VERRAIT PAS ═══
#  Zéro lancement, ça peut vouloir dire deux choses : « la valeur était en
#  mémoire » ou « on n'a rien lu, et on affiche Inconnu ». Les deux comptent
#  zéro. La seconde serait le bogue du dock à l'envers : après un clic sur
#  « Partager », toutes les tuiles deviendraient grises.
#  On coupe donc la machine APRÈS le clic — plus aucun outil joignable — et
#  on exige la MÊME grille, champ pour champ.
SERVIE="$(python3 - "$LIB" "$FAUX" "$CPT" "$CONF" <<'SERVIE_PY' 2>&1
import importlib.util, os, sys
LIB, BIN, CPT, CONF = sys.argv[1:5]
os.environ["PATH"] = BIN
os.environ["LEXOS_BANC_CPT"] = CPT
os.environ["XDG_CONFIG_HOME"] = CONF
sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

#  ⚠ ON NEUTRALISE LE LECTEUR DE PROFIL, ET SEULEMENT LUI. _perf_etat() vise
#  /etc/lexos/performance, un chemin ABSOLU qu'aucun banc ne peut déplacer ;
#  sur une machine de construction ce fichier n'existe pas, et _perf_etat()
#  rend honnêtement None — donc « perf » arrive dans la liste « inconnu » et
#  le garde-fou ci-dessous refuserait de mesurer quoi que ce soit. Ce point-ci
#  éprouve le CACHE, pas la lecture du profil : on lui donne une valeur, et on
#  ne touche à rien d'autre.
m._perf_etat = lambda: "medium"
m._CACHE.perime()
avant = m.etat("rapides")["rapides"]
m._apres_action("rapides-partage")
#  La machine devient injoignable : si quoi que ce soit était relu, la grille
#  se remplirait d'« inconnu ».
os.environ["PATH"] = "/nulle-part"
apres = m.etat("rapides")["rapides"]
if avant.get("inconnu"):
    print("REPERE_FAUX " + repr(avant.get("inconnu")))
elif avant == apres:
    print("IDENTIQUE")
else:
    print("DIFFERENT " + repr(apres.get("inconnu")))
SERVIE_PY
)"
case "$SERVIE" in
	IDENTIQUE)    ok "après un clic sur « Partager », la grille est servie de mémoire, identique — pas une tuile « Inconnu »" ;;
	DIFFERENT*)   non "la grille change après un clic qui ne change rien : ${SERVIE#DIFFERENT } — les tuiles deviennent grises" ;;
	REPERE_FAUX*) muet "les outils factices n'ont pas tous répondu (inconnu dès l'ouverture : ${SERVIE#REPERE_FAUX }) : rien n'a été éprouvé" ;;
	*)            muet "la grille n'a pas pu être comparée : $SERVIE" ;;
esac

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
