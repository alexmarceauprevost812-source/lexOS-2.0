#!/usr/bin/env bash
# =============================================================================
#  UNE SEULE COPIE DE CHAQUE LECTURE — la preuve du moteur
# =============================================================================
#  La consigne d'Alex le dit ainsi : « si le volet marche identique avec
#  200 lignes de moins et une seule copie de chaque lecture, le moteur a tenu
#  sa promesse ».
#
#  CE QUI ÉTAIT DOUBLÉ, ET CE QUE ÇA COÛTAIT DÉJÀ :
#
#      ce qu'on lit   | settings.py        | volet.py
#      Wi-Fi          | _wifi_etat         | _wifi_radio_etat
#      Bluetooth      | _bluetooth_etat    | _bt_radio_etat
#      mode avion     | _avion_etat        | _avion_radio_etat
#
#  ⚠ ET LES DEUX COPIES DU MODE AVION NE CALCULAIENT PAS LA MÊME CHOSE :
#
#      volet.py    : wwan dans ("disabled", "missing", "")   ← le vide compte
#      settings.py : wwan dans ("disabled", "missing")       ← il ne compte pas
#
#  Sur une machine sans modem, où « nmcli -t radio wwan » rend une ligne
#  vide, le volet annonçait « mode avion » et les Paramètres « non ». Ce
#  n'était donc pas un risque théorique : app.js du volet écrivait « deux
#  endroits où un bogue pourrait un jour raconter deux choses différentes »,
#  et le jour était déjà passé.
#
#  ═══ CE BANC NE COMPTE PAS DES LIGNES, IL COMPARE DES RÉPONSES ═══
#  Un grep sur les noms de fonctions serait vert le jour où quelqu'un
#  recopierait le calcul sous un autre nom. On fait donc répondre les DEUX
#  modules sur les MÊMES fausses machines, et on exige la même réponse.
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

command -v python3 >/dev/null 2>&1 || { muet "python3 absent : rien n'a été comparé"; exit 0; }
[ -r "$LIB/moteur/radios.py" ] || { echo "introuvable : $LIB/moteur/radios.py"; exit 1; }

# ===========================================================================
titre "1. LES DEUX FENÊTRES DONNENT LA MÊME RÉPONSE, SUR LES MÊMES MACHINES"
# ===========================================================================
#  Six machines de faux nmcli, dont CELLE QUI SÉPARAIT LES DEUX COPIES : le
#  wwan qui rend une ligne vide.
CAS="$(python3 - "$LIB" <<'PY' 2>&1
import importlib.util, json, os, shutil, subprocess, sys, tempfile

LIB = sys.argv[1]
MACHINES = {
    "tout allume":        {"wifi": "enabled",  "wwan": "enabled"},
    "wifi coupe seul":    {"wifi": "disabled", "wwan": "enabled"},
    "avion, wwan absent": {"wifi": "disabled", "wwan": "missing"},
    #  ⚠ LE CAS QUI SÉPARAIT LES DEUX COPIES : pas de modem du tout, nmcli
    #  rend une ligne vide. Le volet disait « mode avion », les Paramètres
    #  « non ». C'est le cas d'une machine de bureau sans 4G — donc la
    #  plupart des machines.
    "avion, wwan vide":   {"wifi": "disabled", "wwan": ""},
    "wifi absent":        {"wifi": "missing",  "wwan": "missing"},
}

def charge(nom, fichier):
    spec = importlib.util.spec_from_file_location(nom, LIB + "/" + fichier)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

resultats = {}
for nom, rep in MACHINES.items():
    faux = tempfile.mkdtemp()
    script = faux + "/nmcli"
    with open(script, "w") as f:
        f.write("#!/bin/sh\ncase \"$3\" in\n")
        for quoi, val in rep.items():
            f.write(f"  {quoi}) echo '{val}' ;;\n")
        f.write("esac\nexit 0\n")
    os.chmod(script, 0o755)
    vieux = os.environ["PATH"]
    os.environ["PATH"] = faux + ":" + vieux
    try:
        sys.path.insert(0, LIB)
        for mod in [m for m in list(sys.modules) if m.startswith(("moteur", "lexos_"))]:
            del sys.modules[mod]
        from moteur import outils, radios
        outils.oublier()
        s = charge("lexos_s", "settings.py")
        v = charge("lexos_v", "volet.py")
        resultats[nom] = {
            "settings_avion": s._avion_etat(),
            "volet_avion": v._radios.avion(),
            "radios_avion": radios.avion(),
        }
    finally:
        os.environ["PATH"] = vieux
        shutil.rmtree(faux, ignore_errors=True)
print(json.dumps(resultats))
PY
)"
if ! python3 -c 'import json,sys;json.loads(sys.argv[1])' "$CAS" 2>/dev/null; then
	muet "les modules n'ont pas pu être comparés ici : $(head -c 300 <<< "$CAS")"
else
	DESACCORDS="$(python3 - "$CAS" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
mauvais = []
for nom, r in d.items():
    #  « on »/« off » côté Paramètres, True/False côté volet : on compare le
    #  SENS, pas la forme.
    s = {"on": True, "off": False, "inconnu": None}.get(r["settings_avion"], "?")
    if s != r["volet_avion"] or s != r["radios_avion"]:
        mauvais.append(f"{nom} (Paramètres={r['settings_avion']}, volet={r['volet_avion']})")
print(" ; ".join(mauvais))
PY
)"
	N="$(python3 -c 'import json,sys;print(len(json.loads(sys.argv[1])))' "$CAS")"
	if [ "$N" -lt 4 ]; then
		non "seules $N machines ont été éprouvées — trop peu pour prouver quoi que ce soit"
	elif [ -z "$DESACCORDS" ]; then
		ok "les $N machines donnent la même réponse des deux côtés, y compris « wwan vide »"
	else
		non "les deux fenêtres se contredisent : $DESACCORDS"
	fi
	#  ⚠ S'ACCORDER N'EST PAS AVOIR RAISON, et ce banc a dû l'apprendre.
	#  Depuis que les deux côtés appellent la même fonction, ils s'accordent
	#  forcément — y compris sur une erreur. Une mutation qui remettait
	#  l'ancienne règle (le vide ne compte pas) restait donc VERTE au point
	#  du dessus. Il faut aussi dire ce que la bonne réponse EST.
	#  « wwan vide » = machine sans modem = toutes les radios coupées = mode
	#  avion. C'est la règle du volet, et c'est elle qu'on a gardée : traiter
	#  le vide comme un refus empêchait le mode avion de jamais s'afficher
	#  sur ces machines-là.
	VIDE="$(python3 -c '
import json,sys
print(json.loads(sys.argv[1]).get("avion, wwan vide", {}).get("radios_avion"))' "$CAS" 2>/dev/null || echo ERR)"
	[ "$VIDE" = "True" ] \
		&& ok "…et sur « wwan vide » la réponse est bien « mode avion » (la règle du volet, gardée)" \
		|| non "sur « wwan vide » la réponse est « $VIDE » : une machine sans modem ne pourrait jamais afficher le mode avion"
fi

# ===========================================================================
titre "2. IL N'Y A PLUS QU'UN SEUL ENDROIT QUI LIT UNE RADIO"
# ===========================================================================
#  On ne lit que les lignes de CODE : les commentaires de ce dépôt citent ce
#  qu'ils remplacent, et un grep naïf se déclencherait sur l'explication du
#  correctif lui-même — ce dépôt a déjà payé ce faux rouge trois fois.
#  ⚠ LE MOTIF DOIT SÉPARER LIRE D'AGIR, et ma première version ne le faisait
#  pas : elle comptait « nmcli radio wifi on » — qui ALLUME la radio — comme
#  une lecture en double, et accusait donc un code juste. Le discriminant est
#  « -t » (terse) : les LECTURES le passent, pour avoir des mots-clés fixes
#  jamais traduits ; les ACTIONS ne l'ont pas. Les actions restent chez elles,
#  c'est voulu — leurs délais sont ceux d'une action, pas d'une lecture.
for FICHIER in settings.py volet.py; do
	N="$(grep -v '^[[:space:]]*#' "$LIB/$FICHIER" | grep -c '"-t", "radio"' || true)"
	[ "$N" = "0" ] \
		&& ok "$FICHIER ne LIT plus la radio lui-même (ses actions, elles, restent)" \
		|| non "$FICHIER lit encore la radio $N fois — la lecture est revenue en double"
done
N_BT="$(grep -v '^[[:space:]]*#' "$LIB/volet.py" "$LIB/settings.py" | grep -c 'bluetoothctl", "show' || true)"
[ "$N_BT" = "0" ] \
	&& ok "plus personne ne lance « bluetoothctl show » hors du moteur" \
	|| non "« bluetoothctl show » est appelé $N_BT fois hors du moteur"
N_MOTEUR="$(grep -c '"-t", "radio"' "$LIB/moteur/radios.py" || true)"
[ "$N_MOTEUR" = "1" ] \
	&& ok "…et le moteur, lui, la lit UNE fois" \
	|| non "le moteur lit la radio $N_MOTEUR fois — il devrait y en avoir exactement une"

# ===========================================================================
titre "3. « JE N'AI PAS PU LIRE » REMONTE JUSQU'À LA PAGE"
# ===========================================================================
#  Une lecture ratée ne doit pas se déguiser en « éteint ». C'est le défaut
#  qui, dans le volet, faisait ÉTEINDRE un Wi-Fi allumé : la tuile affichait
#  « Désactivé », et le clic bascule à partir de la VRAIE radio.
#  ⚠ ON VIDE LE PATH DEPUIS L'INTÉRIEUR. Le faire devant la commande emporte
#  python3 lui-même : le sondage ne démarre pas, et le banc annonce « non
#  mesuré » là où il croyait mesurer. Déjà vu une fois dans ce dépôt.
SANS="$(python3 - "$LIB" <<'PY' 2>/dev/null
import importlib.util, json, os, sys
LIB = sys.argv[1]; sys.path.insert(0, LIB)
os.environ["PATH"] = "/nulle-part"
def charge(n, f):
    spec = importlib.util.spec_from_file_location(n, LIB + "/" + f)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
s = charge("lexos_s", "settings.py")
v = charge("lexos_v", "volet.py")
print(json.dumps({
    "settings_avion": s._avion_etat(),
    "volet_inconnu": v.etat("rapides")["rapides"]["inconnu"],
}))
PY
)"
if [ -z "$SANS" ]; then
	muet "les modules n'ont pas pu tourner sans outils — non mesuré"
else
	AV="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["settings_avion"])' "$SANS" 2>/dev/null || echo ERR)"
	INC="$(python3 -c 'import json,sys;print(",".join(json.loads(sys.argv[1])["volet_inconnu"]))' "$SANS" 2>/dev/null || echo ERR)"
	[ "$AV" = "inconnu" ] \
		&& ok "Paramètres, sans nmcli : le mode avion vaut « inconnu », pas « off »" \
		|| non "Paramètres, sans nmcli : le mode avion vaut « $AV » — l'interrupteur inverserait une valeur inventée"
	case ",$INC," in
		*,avion,*) ok "volet, sans nmcli : « avion » est déclaré inconnu ($INC)" ;;
		*)         non "volet, sans nmcli : « avion » n'est pas déclaré inconnu (inconnu = « $INC »)" ;;
	esac
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
