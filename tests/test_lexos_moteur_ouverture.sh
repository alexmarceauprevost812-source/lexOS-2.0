#!/usr/bin/env bash
# =============================================================================
#  L'OUVERTURE DES PARAMÈTRES — mesurée, pas supposée
# =============================================================================
#  ALEX : « quand on ouvre la page des paramètres ça prend environ 3 secondes
#  avant de voir de quoi ».
#
#  CE QUI SE PASSAIT. L'ouverture appelait chargeEtat() SANS argument, et
#  attendait donc les quarante collecteurs — imprimantes, Bluetooth, comptes
#  en ligne, utilisateurs — avant de dessiner UNE section. Mesuré avec des
#  outils qui répondent en 1,5 s (ce que fait une vraie machine quand nmcli
#  interroge la radio ou lpstat une imprimante réseau) : 4001 ms. Pas 3800,
#  pas 4200 : 4001 — l'ouverture touchait le PLAFOND de _ETAT_DELAI. Elle
#  n'attendait pas les collecteurs, elle attendait qu'ils ABANDONNENT.
#
#  ET LA MACHINERIE POUR DEMANDER MOINS EXISTAIT DÉJÀ. clesDeSection() est
#  dans le fichier depuis longtemps, et la NAVIGATION s'en sert. Seule
#  l'OUVERTURE ne l'avait jamais eue.
#
#  ═══ CE QUE CE BANC ÉPROUVE, ET POURQUOI CHAQUE POINT EXISTE ═══
#
#  Demander moins ouvre un trou que la lenteur cachait : une section peut
#  LIRE une clé qu'elle ne DEMANDE pas. Avant, tout était chargé, donc la clé
#  était là par accident. Maintenant elle serait vide — et la section ne la
#  redemanderait JAMAIS. C'est un défaut PIRE que la lenteur, parce qu'il est
#  silencieux. Le point 1 le mesure sur les trente-sept sections.
#
#  Le point 2 éprouve l'autre sens : une clé DEMANDÉE qui n'existe nulle part
#  côté machine. Ce n'est pas théorique — c'est comme ça que « barreCachee »
#  a été trouvée : app.js l'affichait depuis toujours, etat() ne l'a JAMAIS
#  produite, et l'interrupteur « Masquer la barre » était donc éteint pour
#  tout le monde, barre cachée ou non. Le bogue du dock, à un autre endroit.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$PAGE" ]   || { echo "introuvable : $PAGE"; exit 1; }
[ -r "$MOTEUR" ] || { echo "introuvable : $MOTEUR"; exit 1; }

# ---------------------------------------------------------------------------
#  Les clés que la machine rend TOUJOURS, quelle que soit la section demandée.
#  Elles sont lues DANS settings.py — les recopier ici garantirait qu'un jour
#  les deux listes diffèrent et que ce banc accuse une section innocente.
# ---------------------------------------------------------------------------
python3 - "$MOTEUR" > "$BANC/cles-machine.json" <<'PY'
import ast, json, sys
src = open(sys.argv[1]).read()
arbre = ast.parse(src)
gratuit, collecteurs = [], []
for n in ast.walk(arbre):
    if not isinstance(n, ast.FunctionDef) or n.name != "etat":
        continue
    for a in ast.walk(n):
        if not isinstance(a, ast.Assign) or not isinstance(a.value, ast.Dict):
            continue
        cible = a.targets[0]
        if not isinstance(cible, ast.Name):
            continue
        noms = [c.value for c in a.value.keys
                if isinstance(c, ast.Constant) and isinstance(c.value, str)]
        if cible.id == "base":
            gratuit = noms
        elif cible.id == "collecteurs":
            collecteurs = noms
print(json.dumps({"gratuit": gratuit, "collecteurs": collecteurs}))
PY
GRATUIT_N="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["gratuit"]))' "$BANC/cles-machine.json" 2>/dev/null || echo 0)"
COLL_N="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["collecteurs"]))' "$BANC/cles-machine.json" 2>/dev/null || echo 0)"

titre "0. LE BANC SAIT CE QU'IL MESURE"
if [ "$GRATUIT_N" -ge 5 ] && [ "$COLL_N" -ge 30 ]; then
  ok "les clés de la machine ont été lues dans settings.py : $GRATUIT_N gratuites, $COLL_N collecteurs"
else
  non "clés illisibles dans settings.py ($GRATUIT_N gratuites, $COLL_N collecteurs) — les points 1 et 2 ne mesureraient rien"
  echo; echo "Bilan : $REUSSIS réussis, $ECHOUES échoués"; exit 1
fi

# ===========================================================================
titre "1. AUCUNE SECTION NE LIT UNE CLÉ QU'ELLE NE DEMANDE PAS"
# ===========================================================================
#  On ne relit pas le TEXTE du fichier : un case peut appeler un helper qui
#  lit l'état, et un grep ne le verrait pas. On RENFD chaque section pour de
#  vrai, avec un état qui est un Proxy notant toute clé consultée.
if ! command -v node >/dev/null 2>&1; then
  muet "node absent : aucune section n'a été rendue"
else
cat > "$BANC/sonde.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");

//  ═══ LA PAGE TELLE QUE LE NAVIGATEUR LA CHARGE ═══
//  index.html charge /moteur/client.js AVANT app.js : esc(), api(), litEtat()
//  et le bandeau y vivent maintenant, pour les quatre fenêtres à la fois. Un
//  banc qui ne lirait qu'app.js mesurerait une page amputée — « LexOS is not
//  defined » dès la première ligne, et un rouge qui n'accuse que le harnais.
//  On ne se tait PAS si le client manque : un banc qui mesure une page sans
//  son client mesure autre chose que la page.
function lireLaPage(chemin){
  const i = String(chemin).indexOf("/usr/share/lexos/");
  if(i < 0 || !String(chemin).endsWith(".js")) return fs.readFileSync(chemin, "utf8");
  const client = String(chemin).slice(0, i) + "/usr/lib/lexos/moteur/web/client.js";
  if(!fs.existsSync(client)) throw new Error("client commun introuvable : " + client);
  return fs.readFileSync(client, "utf8") + "\n" + fs.readFileSync(chemin, "utf8");
}

const src = lireLaPage(process.argv[2])
  + "\n;globalThis.__b = { contenu, pose: e => { etat = e; }, cles: clesDeSection,"
  + " nav: NAV, tbl: CLES_SECTION, charge: chargeEtat, apparence: appliqueApparence,"
  + " allerA, tout: rafraichirTout, rendNav,"
  + " racine: () => document.documentElement };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){},contains:()=>false},
                    querySelectorAll:()=>[], querySelector:()=>null,
                    appendChild(){}, focus(){}, addEventListener(){}, remove(){} });
//  ═══ LA BARRE LATÉRALE REND DE VRAIS BOUTONS ═══
//  rendNav() pose son onclick sur ce que querySelectorAll(".nav-item") lui
//  rend. Avec un stub qui rend [], l'onclick n'est JAMAIS posé — et un banc
//  qui n'éprouve que allerA() laisse passer le chemin qu'Alex emprunte
//  réellement neuf fois sur dix : le bouton du menu.
const boutonsNav = [];
const sidebar = el();
sidebar.querySelectorAll = sel => (sel === ".nav-item" ? boutonsNav : []);
const racine = {style:{setProperty(){}}, dataset:{}};
const vues = [];
const bac = vm.createContext({
  document:{ getElementById:(id)=> (id === "sidebar" ? sidebar : el()),
             querySelectorAll:()=>[], querySelector:()=>null,
             body:el(), createElement:()=>el(),
             documentElement:racine, addEventListener(){} },
  location:{hash:"", href:""}, window:{confirm:()=>true, matchMedia:()=>({matches:false})},
  navigator:{},
  //  On N'APPELLE PAS la machine : on note seulement l'adresse demandée.
  fetch:(u)=>{ vues.push(String(u)); return new Promise(()=>{}); },
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, setInterval:()=>0,
  clearInterval, console, JSON, Math, Date, encodeURIComponent, decodeURIComponent });
bac.globalThis = bac;
vm.runInContext(src, bac, {filename:"app.js"});
const B = bac.__b;
const sections = [];
for (const g of B.nav) for (const it of g.items) sections.push(it[0]);
const rap = [];
for (const s of sections) {
  const lues = new Set();
  const mouchard = new Proxy({}, {
    get(c, p){ if (typeof p === "string") lues.add(p); return undefined; },
    has(c, p){ if (typeof p === "string") lues.add(p); return false; },
    ownKeys(){ return []; },
  });
  B.pose(mouchard);
  let leve = null;
  try { B.contenu(s); } catch (e) { leve = String((e && e.message) || e); }
  B.pose({});
  rap.push({section:s, declare:B.cles(s), lues:[...lues].sort(), leve});
}
//  ═══ NAVIGUER DOIT ALLER LIRE ═══
//  Ce point-ci manquait, et son absence a coute une nuit. Ce banc rendait
//  les 37 sections sur un etat VIDE et verifiait qu'aucune ne leve : il
//  CERTIFIAIT DONC VERT l'etat permanent du defaut au lieu de le detecter.
//  Tant que l'ouverture lisait les quarante collecteurs, la navigation
//  n'avait rien a relire. Depuis qu'elle ne demande que SA section, les
//  trente-deux autres s'ouvraient vides ET LE RESTAIENT — aucun hashchange,
//  aucun minuteur, rien. On CLIQUE donc pour de vrai, et on regarde ce qui
//  part sur le reseau.
vues.length = 0;
const nav = [];
for (const g of B.nav) for (const it of g.items) nav.push(it[0]);
const apresClic = {};
for (const cible of ["bluetooth", "imprimantes", "utilisateurs"]) {
  vues.length = 0;
  B.allerA(cible);
  apresClic[cible] = vues.slice();
}
//  Et le chemin du BOUTON DU MENU, qui est celui qu'on emprunte vraiment.
//  On peuple la barre, on la fait rendre, puis on appelle l'onclick que
//  rendNav() vient de poser — exactement ce qu'un clic déclenche.
boutonsNav.length = 0;
for (const cle of nav) {
  boutonsNav.push({dataset: {cle}, onclick: null, classList: {add(){}, remove(){}}});
}
B.rendNav();
const parMenu = {};
for (const cible of ["bluetooth", "imprimantes"]) {
  const b = boutonsNav.find(x => x.dataset.cle === cible);
  vues.length = 0;
  if (b && typeof b.onclick === "function") { b.onclick(); parMenu[cible] = vues.slice(); }
  else { parMenu[cible] = null; }   // null = le bouton n'a pas de gestionnaire
}

//  Ce que chargeEtat() met VRAIMENT dans l'adresse, pour les trois cas.
//  ⚠ On vide d'abord : le démarrage de la page a DÉJÀ interrogé /api/etat au
//  moment où le fichier s'est exécuté. Lire les trois premières adresses
//  plutôt que les nôtres décalait tout d'un cran, et le banc accusait un
//  code juste — un faux rouge coûte le même prix qu'un faux vert.
vues.length = 0;
vues.length = 0;
B.charge(undefined); B.charge([]); B.charge(["wifi","avion"]);
const vues0 = vues.slice();
//  Le mode d'affichage quand le thème n'est pas encore connu.
racine.dataset.mode = "clair";
B.pose({});            // état vide : vu("theme") vaut undefined
B.apparence();
const modeApresVide = racine.dataset.mode === undefined ? null : racine.dataset.mode;
B.pose({theme:"sombre"});
B.apparence();
const modeApresSombre = racine.dataset.mode === undefined ? null : racine.dataset.mode;
//  « tout relire » doit vraiment tout relire.
vues.length = 0;
B.tout();
const adressesTout = vues.slice();
console.log(JSON.stringify({rap, adresses:vues0, apresClic, parMenu, adressesTout,
                            modeApresVide, modeApresSombre}));
JS
  if ! node "$BANC/sonde.js" "$PAGE" > "$BANC/sonde.json" 2>"$BANC/sonde.err"; then
    non "la page n'a pas pu être chargée par le banc : $(head -3 "$BANC/sonde.err" | tr '\n' ' ')"
  else
    python3 - "$BANC/sonde.json" "$BANC/cles-machine.json" > "$BANC/verdict1.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = json.load(open(sys.argv[2]))
gratuit = set(m["gratuit"])
leves = [r for r in d["rap"] if r["leve"]]
trous = {}
for r in d["rap"]:
    manque = sorted(set(r["lues"]) - set(r["declare"]) - gratuit)
    if manque:
        trous[r["section"]] = manque
print(json.dumps({"n": len(d["rap"]), "leves": leves, "trous": trous}))
PY
    N="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["n"])' "$BANC/verdict1.txt")"
    LEVES="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(" ".join(x["section"] for x in d["leves"]))' "$BANC/verdict1.txt")"
    TROUS="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["trous"];print("; ".join(f"{k} lit {v} sans le demander" for k,v in d.items()))' "$BANC/verdict1.txt")"
    if [ "$N" -lt 30 ]; then
      non "seules $N sections ont été rendues — le balayage ne couvre pas la fenêtre"
    else
      ok "les $N sections déclarées ont toutes été rendues"
    fi
    if [ -n "$LEVES" ]; then non "des sections lèvent sur un état vide : $LEVES"
    else ok "aucune section ne lève quand l'état est vide (c'est l'instant de l'ouverture)"; fi
    if [ -n "$TROUS" ]; then non "$TROUS"
    else ok "toute clé lue est soit demandée par sa section, soit gratuite côté machine"; fi
  fi
fi

# ===========================================================================
titre "2. TOUTE CLÉ DEMANDÉE EXISTE VRAIMENT CÔTÉ MACHINE"
# ===========================================================================
#  Le sens inverse du point 1. Une clé demandée que personne ne produit ne
#  fait pas d'erreur : elle rend « undefined », l'interrupteur reste éteint,
#  et la page ment sans le dire. C'est exactement ce qu'a fait « barreCachee ».
python3 - "$PAGE" "$BANC/cles-machine.json" > "$BANC/verdict2.txt" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
m = json.load(open(sys.argv[2]))
connues = set(m["gratuit"]) | set(m["collecteurs"])
bloc = re.search(r"const CLES_SECTION = \{(.*?)\n\};", src, re.S)
if not bloc:
    print("ILLISIBLE"); raise SystemExit
inconnues = {}
for mm in re.finditer(r"^\s*([A-Za-z_]+)\s*:\s*\[([^\]]*)\]", bloc.group(1), re.M):
    dem = [x.strip().strip('"').strip("'") for x in mm.group(2).split(",") if x.strip()]
    perdues = [k for k in dem if k not in connues]
    if perdues:
        inconnues[mm.group(1)] = perdues
print(json.dumps(inconnues))
PY
V2="$(cat "$BANC/verdict2.txt")"
if [ "$V2" = "ILLISIBLE" ]; then
  non "la table CLES_SECTION n'a pas été retrouvée dans app.js — rien n'a été mesuré"
elif [ "$V2" = "{}" ]; then
  ok "chaque clé demandée par une section est produite par etat()"
else
  non "des sections demandent une clé que la machine ne produit pas : $V2"
fi

# ===========================================================================
titre "3. LA PAGE DESSINE AVANT D'INTERROGER LA MACHINE"
# ===========================================================================
DEM="$(sed -n '/--- Démarrage/,$p' "$PAGE")"
if grep -q 'rend();' <<< "$DEM" && \
   [ "$(grep -n 'rend();' <<< "$DEM" | head -1 | cut -d: -f1)" -lt \
     "$(grep -n 'await chargeEtat' <<< "$DEM" | head -1 | cut -d: -f1)" ]; then
  ok "le premier rend() a lieu AVANT le premier await — la fenêtre est habitée tout de suite"
else
  non "le démarrage attend la machine avant de dessiner : c'est l'écran vide qu'Alex décrit"
fi
if grep -q 'await chargeEtat(clesDeSection(sectionActive))' <<< "$DEM"; then
  ok "l'ouverture ne demande que les clés de la section affichée"
else
  non "l'ouverture demande encore tout l'état"
fi

# ===========================================================================
titre "4. UNE LISTE VIDE VEUT DIRE « RIEN », PAS « TOUT »"
# ===========================================================================
#  Des deux côtés — la distinction ne sert à rien si un seul des deux la fait.
if [ -s "$BANC/sonde.json" ]; then
  python3 - "$BANC/sonde.json" > "$BANC/verdict4.txt" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))["adresses"]
#  Trois appels dans l'ordre : undefined, [], ["wifi","avion"].
print(json.dumps(a))
PY
  A="$(cat "$BANC/verdict4.txt")"
  SANS="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])[0])' "$A" 2>/dev/null || echo "?")"
  VIDE="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])[1])' "$A" 2>/dev/null || echo "?")"
  DEUX="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])[2])' "$A" 2>/dev/null || echo "?")"
  [ "$SANS" = "/api/etat" ] \
    && ok "chargeEtat() sans argument demande tout : $SANS" \
    || non "chargeEtat() sans argument devrait demander tout, il demande « $SANS »"
  [ "$VIDE" = "/api/etat?cles=" ] \
    && ok "chargeEtat([]) demande explicitement RIEN : $VIDE" \
    || non "chargeEtat([]) retombe sur le plein tarif : « $VIDE »"
  [ "$DEUX" = "/api/etat?cles=wifi%2Cavion" ] \
    && ok "chargeEtat([wifi,avion]) ne demande que ces deux-là : $DEUX" \
    || non "chargeEtat([wifi,avion]) demande « $DEUX »"
else
  muet "la page n'a pas été chargée : les adresses n'ont pas été mesurées"
fi
#  ═══ LE CÔTÉ SERVEUR SE MESURE AILLEURS, ET VOICI POURQUOI ═══
#  Ce contrôle-ci cherchait la bonne ligne au GREP. Il était VERT pendant que
#  le serveur, lui, rendait les cinquante et une clés pour « ?cles= » : par
#  défaut parse_qs JETTE les valeurs vides, donc « cles » n'était pas dans la
#  requête, donc « paramètre absent », donc tout. La ligne était juste et le
#  comportement faux — un faux vert de manuel, et c'est moi qui l'avais écrit.
#  La distinction est maintenant éprouvée sur un VRAI serveur, sur un vrai
#  port, dans tests/test_lexos_moteur_service.sh (point 2). On garde ici la
#  seule chose qu'un grep sait dire sans mentir : que l'ancienne forme a bien
#  disparu du code.
CODE_SRV="$(grep -v '^[[:space:]]*#' "$MOTEUR")"
if grep -q 'etat(demande) if demande else etat()' <<< "$CODE_SRV"; then
  non "l'ancienne forme « etat(demande) if demande else etat() » est revenue"
else
  ok "l'ancienne forme du serveur a disparu (le comportement, lui, est mesuré dans test_lexos_moteur_service.sh)"
fi

# ===========================================================================
titre "4 bis. CHANGER DE SECTION VA LIRE CETTE SECTION-LÀ"
# ===========================================================================
#  ═══ LE DÉFAUT QUE CE BANC A LAISSÉ PASSER UNE NUIT ENTIÈRE ═══
#  Il rendait les 37 sections sur un état VIDE et vérifiait qu'aucune ne
#  lève. C'est exactement l'état permanent du défaut : il le CERTIFIAIT
#  VERT. Cliquer « Bluetooth » sur un portable qui en a un affichait
#  « Aucun contrôleur Bluetooth sur cette machine. » définitivement — et la
#  section vide ne rend aucun bouton, donc pas même un geste pour relire.
#  On clique pour de vrai, et on regarde ce qui part sur le réseau.
if [ -s "$BANC/sonde.json" ]; then
  for CIBLE in bluetooth imprimantes utilisateurs; do
    A="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["apresClic"].get(sys.argv[2], [])
print(" ".join(d) if d else "RIEN")' "$BANC/sonde.json" "$CIBLE")"
    case "$A" in
      RIEN) non "aller sur « $CIBLE » ne demande RIEN à la machine : la section resterait vide pour toujours" ;;
      *"cles="*"$CIBLE"*) ok "aller sur « $CIBLE » demande ses clés : $A" ;;
      *) non "aller sur « $CIBLE » demande « $A » — pas ses clés à elle" ;;
    esac
  done
  for CIBLE in bluetooth imprimantes; do
    A="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["parMenu"].get(sys.argv[2])
print("PAS_DE_GESTIONNAIRE" if d is None else (" ".join(d) if d else "RIEN"))' "$BANC/sonde.json" "$CIBLE")"
    case "$A" in
      PAS_DE_GESTIONNAIRE) non "le bouton « $CIBLE » du menu n'a aucun gestionnaire — le banc ne mesure pas le vrai chemin" ;;
      RIEN) non "CLIQUER « $CIBLE » dans le menu ne demande RIEN : la section resterait vide pour toujours" ;;
      *"cles="*"$CIBLE"*) ok "cliquer « $CIBLE » dans le menu demande ses clés : $A" ;;
      *) non "cliquer « $CIBLE » demande « $A » — pas ses clés à elle" ;;
    esac
  done
  T="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["adressesTout"]
print(" ".join(d) if d else "RIEN")' "$BANC/sonde.json")"
  case "$T" in
    "/api/etat") ok "« tout relire » demande bien tout l'etat : $T" ;;
    RIEN)        non "« tout relire » ne demande RIEN — un bouton qui ne relit rien, sans un mot" ;;
    *)           non "« tout relire » demande « $T » au lieu de tout" ;;
  esac
else
  muet "la page n'''a pas été chargée : la navigation n'''a pas été mesurée"
fi

# ===========================================================================
titre "5. LE RENDU IMMÉDIAT N'EFFACE PAS LE MODE VENU DE L'ADRESSE"
# ===========================================================================
#  Dessiner avant de lire veut dire qu'appliqueApparence() tourne une fois
#  SANS connaître le thème. Avec un « else » sans condition, elle effaçait
#  alors l'attribut posé par index.html d'après ?mode= : quelqu'un en clair
#  voyait sa fenêtre s'ouvrir NOIRE puis redevenir claire. Un éclair à
#  l'envers, causé par la correction de l'attente elle-même.
if [ -s "$BANC/sonde.json" ]; then
  MV="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["modeApresVide"])' "$BANC/sonde.json")"
  MS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["modeApresSombre"])' "$BANC/sonde.json")"
  [ "$MV" = "clair" ] \
    && ok "thème inconnu : le mode de l'adresse est laissé tel quel ($MV)" \
    || non "thème inconnu : le mode de l'adresse a été effacé (devenu « $MV ») — la fenêtre clignote au noir"
  [ "$MS" = "None" ] \
    && ok "thème connu et sombre : le mode clair est bien retiré" \
    || non "thème sombre : le mode est resté « $MS »"
else
  muet "la page n'a pas été chargée : le mode n'a pas été mesuré"
fi

# ===========================================================================
titre "6. LA MESURE — avec des outils qui traînent, comme une vraie machine"
# ===========================================================================
#  On ne croit pas la théorie : on met devant le PATH des outils qui répondent
#  en 1,2 s, et on chronomètre etat() dans les deux formes. Si demander moins
#  ne gagne rien de mesurable, tout le reste de ce banc ne prouve rien.
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : rien n'a été chronométré"
else
  LENT="$BANC/lent"; mkdir -p "$LENT"
  for OUTIL in nmcli bluetoothctl lpstat pactl upower wmctrl xfconf-query xrandr; do
    printf '#!/bin/sh\nsleep 1.2\nexit 0\n' > "$LENT/$OUTIL"
    chmod +x "$LENT/$OUTIL"
  done
  cat > "$BANC/chrono.py" <<'PY'
import importlib.util, json, os, sys, time
spec = importlib.util.spec_from_file_location("lexsettings", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                      # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit
def chrono(*a):
    t = time.monotonic()
    try:
        mod.etat(*a)
    except Exception as e:                  # noqa: BLE001
        return None, f"{type(e).__name__}: {e}"
    return int((time.monotonic() - t) * 1000), None
tout, e1 = chrono()
peu,  e2 = chrono(["dock", "crt", "barreCachee"])
rien, e3 = chrono([])
print(json.dumps({"tout": tout, "peu": peu, "rien": rien,
                  "erreurs": [x for x in (e1, e2, e3) if x]}))
PY
  CH="$(PATH="$LENT:$PATH" HOME="$BANC/home" XDG_CONFIG_HOME="$BANC/home/.config" \
        LEXOS_ETAT_DELAI=4 timeout 120 python3 "$BANC/chrono.py" "$MOTEUR" 2>"$BANC/chrono.err")"
  if [ -z "$CH" ]; then
    muet "settings.py n'a pas pu être chargé hors de sa machine : $(head -2 "$BANC/chrono.err" | tr '\n' ' ') — rien n'a été chronométré, et c'est un « non mesuré », pas un vert"
  else
    TOUT="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("tout"))' "$CH")"
    PEU="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("peu"))' "$CH")"
    RIEN="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("rien"))' "$CH")"
    ERR="$(python3 -c 'import json,sys;print(" | ".join(json.loads(sys.argv[1]).get("erreurs") or []))' "$CH")"
    if [ -n "$ERR" ]; then
      muet "etat() a levé sur cette machine : $ERR — non mesuré"
    elif [ "$TOUT" = "None" ] || [ "$PEU" = "None" ]; then
      muet "chronométrage incomplet — non mesuré"
    else
      printf '     tout l'"'"'état ........ %s ms\n     une section ....... %s ms\n     liste vide ........ %s ms\n' "$TOUT" "$PEU" "$RIEN"
      if [ "$PEU" -lt "$TOUT" ]; then
        ok "demander sa seule section coûte moins que tout demander ($PEU ms contre $TOUT ms)"
      else
        non "demander moins ne gagne rien ($PEU ms contre $TOUT ms) — le correctif ne tient pas"
      fi
      if [ "$RIEN" -lt 1000 ]; then
        ok "une section sans collecteur répond sans attendre un seul outil ($RIEN ms)"
      else
        non "une liste vide attend encore les outils ($RIEN ms) — le « vide = tout » est revenu"
      fi
    fi
  fi
fi

# ===========================================================================
titre "7. DES COLLECTEURS MUETS N'EMPORTENT PAS L'ÉCHÉANCE"
# ===========================================================================
#  ═══ CE POINT EXISTE AVANT LE DÉMÉNAGEMENT, ET DOIT RESTER VERT APRÈS ═══
#  _de_front() va quitter settings.py pour le moteur commun. Son commentaire
#  raconte un bogue qui a coûté cher : sans « pool.shutdown(wait=False) », la
#  sortie du pool ATTEND les fils mêmes que l'échéance venait d'abandonner,
#  et etat() rendait la main au bout de 63 s au lieu de 4. Une fonction qu'on
#  déplace emporte ses lignes ; elle n'emporte pas forcément la RAISON de
#  chacune. C'est ce point-ci qui la tient — s'il passe au rouge après le
#  déménagement, une ligne est tombée en route.
#
#  ⚠ IL A FALLU DEUX ESSAIS POUR QUE CE CONTRÔLE MESURE QUELQUE CHOSE.
#  Avec UN SEUL outil muet, « wait=True » et « wait=False » donnent le même
#  chiffre : le collecteur unique est borné par SON PROPRE délai de lecture
#  (deux secondes), pas par l'échéance commune. Le contrôle était vert dans
#  les deux cas — un faux vert, et sur exactement la ligne la plus chère du
#  fichier. Il faut TOUS les outils muets et une échéance COURTE pour que
#  l'écart apparaisse. Mesuré ici : 300 ms contre 12 040 ms, quarante fois.
if ! command -v python3 >/dev/null 2>&1; then
  muet "python3 absent : l'échéance n'a pas été éprouvée"
else
  MUR="$BANC/mur"; mkdir -p "$MUR"
  for OUTIL in nmcli bluetoothctl lpstat pactl upower wmctrl xfconf-query \
               xrandr uname df gsettings systemctl busctl; do
    printf '#!/bin/sh\nsleep 600\n' > "$MUR/$OUTIL"; chmod +x "$MUR/$OUTIL"
  done
  cat > "$BANC/mur.py" <<'PY2'
import importlib.util, json, sys, time
spec = importlib.util.spec_from_file_location("lexsettings", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                      # noqa: BLE001
    print(json.dumps({"erreur": f"{type(e).__name__}: {e}"})); raise SystemExit
t = time.monotonic()
try:
    e = mod.etat()
except Exception as ex:                     # noqa: BLE001
    print(json.dumps({"erreur": f"{type(ex).__name__}: {ex}"})); raise SystemExit
ms = int((time.monotonic() - t) * 1000)
#  « inventees » : des clés de collecteur qui rendent autre chose que None
#  alors qu'AUCUN outil n'a répondu. C'est la valeur inventée du bogue du dock.
print(json.dumps({"ms": ms, "cles": len(e),
                  "inconnues": sum(1 for v in e.values() if v is None)}))
PY2
  #  Échéance très courte : c'est elle que le pool doit respecter.
  R="$(PATH="$MUR:$PATH" HOME="$BANC/home2" XDG_CONFIG_HOME="$BANC/home2/.config" \
       LEXOS_ETAT_DELAI=0.3 timeout 200 python3 "$BANC/mur.py" "$MOTEUR" 2>"$BANC/mur.err")"
  if [ -z "$R" ]; then
    muet "etat() n'a pas pu tourner ici : $(head -2 "$BANC/mur.err" | tr '\n' ' ') — non mesuré"
  else
    ERRM="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("erreur",""))' "$R" 2>/dev/null || echo illisible)"
    if [ -n "$ERRM" ]; then
      muet "etat() a levé sur cette machine : $ERRM — non mesuré"
    else
      MS="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["ms"])' "$R")"
      INC="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["inconnues"])' "$R")"
      NBC="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["cles"])' "$R")"
      printf '     tous les outils muets, échéance 0,3 s : %s ms, %s clés dont %s « je ne sais pas »\n' \
             "$MS" "$NBC" "$INC"
      #  Large marge : on ne mesure pas 300 ms au millimètre, on mesure que
      #  le pool ne rattrape PAS les fils lâchés. L'écart est de 40 fois.
      if [ "$MS" -lt 4000 ]; then
        ok "l'échéance tient quand tout est muet ($MS ms pour 0,3 s demandées)"
      else
        non "etat() a mis $MS ms pour une échéance de 0,3 s — le pool réattend les fils abandonnés, c'est le bogue des 63 s"
      fi
      if [ "$INC" -ge 20 ]; then
        ok "les collecteurs qui n'ont rien lu rendent « je ne sais pas » ($INC clés à None), aucune valeur inventée"
      else
        non "seules $INC clés valent None alors qu'aucun outil n'a répondu — des valeurs ont été inventées"
      fi
    fi
  fi
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
