#!/usr/bin/env bash
# =============================================================================
#  Éprouver TOUTES les sections des Paramètres — une par une, rendues pour de vrai
# =============================================================================
#  CE BANC EXISTE À CAUSE D'UNE PAGE QUI NE S'AFFICHAIT PAS DU TOUT.
#
#  « Diagnostic » écrivait « corps.innerHTML = … » puis « break », alors que
#  toutes les autres sections RENDENT une chaîne. Deux fautes d'un coup :
#  « corps » n'existe nulle part dans le fichier — une ReferenceError à chaque
#  clic — et la fonction ne rendait rien.
#
#  ET LE SYMPTÔME NE RESSEMBLAIT PAS À UNE ERREUR. rendSection() fait
#  « content.innerHTML = contenu(...) » : quand contenu() lève, la droite
#  n'est jamais évaluée, l'affectation n'a pas lieu, et l'écran GARDE LA
#  SECTION PRÉCÉDENTE. On cliquait « Diagnostic » et il ne se passait rien —
#  pas de page blanche, pas de message : rien. « node --check » ne dit que
#  ceci : le fichier se parse. Il se parsait très bien.
#
#  Trente-six sections, et aucun banc ne les rendait une par une. Il y en a un
#  maintenant, et il éprouve quatre choses pour CHACUNE :
#
#    1. elle ne lève pas ;
#    2. elle rend quelque chose (pas « undefined », pas du vide) ;
#    3. chaque bouton vise une fonction QUI EXISTE — un gestionnaire mort est
#       un bouton muet, et ce dépôt en a déjà eu trois d'un coup sur l'écran
#       de connexion ;
#    4. chaque entrée du menu de gauche a bien une section derrière elle.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$PAGE" ] || { echo "introuvable : $PAGE"; exit 1; }
command -v node >/dev/null 2>&1 || { saute "node absent : rien n'a été rendu"; exit 0; }

cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; }, nav: NAV };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont dans le banc")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);

try {
  /*  DEUX ÉTATS, ET LES DEUX COMPTENT.
      « rien » est l'état d'une machine qui ne répond à aucune question : une
      page doit tenir DEBOUT là-dessus, parce que c'est ce que voit quelqu'un
      dont l'outil manque ou plante. « plein » est l'état réel de la machine
      qui fait tourner le banc, tel que settings.py le rend. */
  const plein = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const sections = [];
  for (const g of T.nav) for (const it of g.items) sections.push(it);

  dit(sections.length >= 30,
      `le menu de gauche annonce ${sections.length} sections`);

  for (const [nom, etat] of [["sans rien", {}], ["état réel", plein]]) {
    T.pose(etat);
    const casses = [], vides = [];
    for (const [cle, , label] of sections) {
      let h;
      try { h = T.contenu(cle); }
      catch (e) { casses.push(`${cle} (${e.message})`); continue; }
      if (typeof h !== "string" || h.trim().length < 20) vides.push(cle);
    }
    dit(casses.length === 0,
        `${nom} : aucune section ne lève (${casses.join(", ") || "36/36"})`);
    dit(vides.length === 0,
        `${nom} : aucune section ne rend du vide (${vides.join(", ") || "toutes rendent"})`);
  }

  /*  CHAQUE BOUTON VISE UNE FONCTION QUI EXISTE.
      Un gestionnaire mort ne se voit pas : le bouton s'affiche, se clique, et
      la console — que personne n'ouvre — dit « x is not defined ». */
  T.pose(plein);
  const manquantes = new Set();
  const vues = new Set();
  for (const [cle] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    for (const m of h.matchAll(/on(?:click|change|input|keydown)="([^"]*)"/g)) {
      for (const f of m[1].matchAll(/\b([A-Za-z_$][\w$]*)\s*\(/g)) {
        const nom = f[1];
        //  Les mots-clés et les méthodes ne sont pas des fonctions de la page.
        if (["if", "for", "while", "return", "typeof", "event"].includes(nom)) continue;
        if (m[1].includes("." + nom + "(")) continue;
        vues.add(nom);
        if (typeof bac[nom] !== "function") manquantes.add(`${nom} (${cle})`);
      }
    }
  }
  dit(vues.size >= 20, `${vues.size} fonctions différentes sont appelées par les boutons`);
  dit(manquantes.size === 0,
      `chaque bouton vise une fonction qui existe (${[...manquantes].join(", ") || "aucune manquante"})`);

  /*  ET CHAQUE SECTION A UN TITRE. Une page sans <h2> est une page dont on ne
      sait pas où l'on est. */
  const sansTitre = [];
  for (const [cle] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    if (!/<h2[ >]/.test(h)) sansTitre.push(cle);
  }
  dit(sansTitre.length === 0,
      `chaque section a un titre (${sansTitre.join(", ") || "toutes"})`);

  /*  L'INVENTAIRE, pour mémoire — pas un contrôle : une section sans réglage
      n'est pas forcément un défaut (« À propos » n'a rien à régler), et
      figer ces nombres empêcherait la page d'évoluer. */
  const compte = [];
  for (const [cle, , label] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    const sansOuvrir = h.replace(/onclick="ouvrir\('[^']*'\)"/g, "");
    const n = (sansOuvrir.match(/on(?:click|change|input|keydown)=/g) || []).length;
    if (n === 0) compte.push(label);
  }
  console.log("INFO|sections sans réglage sur CETTE machine : " +
              (compte.join(", ") || "aucune"));
} catch (e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS

# =============================================================================
titre "Les 36 sections, rendues une par une"
# =============================================================================
#  L'état réel de la machine vient de settings.py lui-même : c'est ce que la
#  page reçoit vraiment. S'il n'est pas lisible ici (python3 absent, outils
#  manquants), on se rabat sur un état vide — les contrôles « sans rien »
#  restent joués, ceux « état réel » se répètent dessus.
ETAT="$BANC/etat.json"
if command -v python3 >/dev/null 2>&1; then
	( cd "$RACINE" && PATH="$RACINE/config/includes.chroot/usr/bin:$PATH" \
		timeout 180 python3 -c "
import sys, json
sys.path.insert(0, 'config/includes.chroot/usr/lib/lexos')
import settings
print(json.dumps(settings.etat(), ensure_ascii=False, default=str))
" > "$ETAT" 2>/dev/null ) || : > "$ETAT"
fi
[ -s "$ETAT" ] || printf '{}' > "$ETAT"

SORTIE="$(node "$BANC/rendu.js" "$PAGE" "$ETAT" 2>&1 | grep -E '^(OK|NON|INFO|FIN)\|' || true)"
if [ -z "$SORTIE" ]; then
	non "rien n'a été rendu — app.js n'a pas pu être chargé"
elif ! printf '%s\n' "$SORTIE" | grep -q '^FIN|'; then
	non "le rendu s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
	printf '%s\n' "$SORTIE" | while IFS='|' read -r V M; do
		[ "$V" = "NON" ] && printf '  \033[31m❌\033[0m %s\n' "$M"
	done
	ECHOUES=$((ECHOUES + 1))
else
	while IFS='|' read -r V M; do
		case "$V" in
			OK)   ok "$M" ;;
			NON)  non "$M" ;;
			INFO) saute "$M" ;;
		esac
	done <<EOF
$SORTIE
EOF
fi

# =============================================================================
titre "Aucune section ne se rend en écrivant dans le document"
# =============================================================================
#  C'est la forme exacte du défaut de « Diagnostic ». contenu() RENVOIE du
#  HTML ; une section qui écrit dans le document au lieu de rendre laisse la
#  page précédente à l'écran, sans erreur visible.
#  On greppe un FICHIER, commentaires retirés — l'explication du correctif
#  cite justement « corps.innerHTML », et elle est dans un bloc /* … */, pas
#  derrière un « // ». Retirer les deux formes, donc : un contrôle rouge à
#  cause du texte qui explique le correctif est le pire des faux positifs.
python3 - "$PAGE" > "$BANC/page.js" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
src = re.sub(r"(?m)//.*$", "", src)
sys.stdout.write(src)
PY
if grep -nE '\bcorps\.innerHTML' "$BANC/page.js"; then
	non "une section écrit encore dans « corps », qui n'existe pas"
else
	ok "aucune section n'écrit dans « corps »"
fi
if grep -nE '^\s+break;\s*$' "$BANC/page.js" | grep -q .; then
	non "un « break » traîne dans contenu() : la section rendrait « undefined »"
else
	ok "aucun « break » ne remplace un « return » dans contenu()"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
