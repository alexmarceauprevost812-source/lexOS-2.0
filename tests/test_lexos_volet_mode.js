/* =============================================================================
 *  Éprouver le mode jour/nuit DANS le volet des paramètres rapides
 * =============================================================================
 *  ALEX : « le thème jour/nuit qui fonctionne pas dans les boutons en haut
 *  à droite » — la tuile « Thème » du volet ouvert par le bouton ▲.
 *
 *  CE QUI SE PASSAIT VRAIMENT. Le mode arrive une seule fois, par ?mode=…
 *  dans l'adresse (le lanceur Python lit ~/.config/lexos/mode). Cliquer la
 *  tuile change bien le réglage réel (act_rapides_theme, côté volet.py) et
 *  rafraichir() relit l'état — le LIBELLÉ de la tuile (☀/🌑, « Style clair »/
 *  « Style sombre ») suivait donc déjà. Ce qui NE suivait pas : la SURFACE
 *  DU VOLET elle-même, encore peinte dans l'ancien mode jusqu'à fermer la
 *  fenêtre et la rouvrir — exactement ce qu'Alex a vu comme « ça ne
 *  fonctionne pas ». Paramètres avait déjà ce correctif (appliqueApparence()
 *  dans settings/web/app.js) ; le volet, une page à part, ne l'avait jamais
 *  reçu.
 *
 *  MÊME TECHNIQUE QUE test_lexos_wifi.js : on charge le VRAI app.js dans un
 *  décor minimal et on regarde ce qu'il fait à document.documentElement,
 *  pas une relecture à l'œil.
 * ========================================================================== */
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const RACINE = path.join(__dirname, "..");
const APP = path.join(RACINE, "config/includes.chroot/usr/share/lexos/volet/web/app.js");

let reussis = 0, echoues = 0;
const ok  = m => { console.log("  \x1b[32m✅\x1b[0m " + m); reussis++; };
const non = m => { console.log("  \x1b[31m❌\x1b[0m " + m); echoues++; };
const titre = m => console.log("\n\x1b[1m═══ " + m + " ═══\x1b[0m");

/* --- Le décor minimal : ce que la page touche au chargement --------------- */
function faux() {
  const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                      classList:{add(){}, remove(){}, toggle(){}},
                      querySelectorAll:() => [], appendChild(){}, focus(){} });
  return {
    document: { getElementById: el, querySelectorAll: () => [], body: el(),
                //  dataset EST un objet mutable : c'est justement ce que
                //  appliqueModeVolet() lit et écrit. Un piège figé ({}) ne
                //  dirait rien d'une régression.
                documentElement: { style:{ setProperty(){} }, dataset:{} },
                addEventListener(){} },
    //  #rapides : sans ça QUOI vaudrait « agenda » (repli de la ligne 15 de
    //  app.js) et rend() n'appellerait jamais rapidesHTML().
    location: { hash: "#rapides" },
    window: { confirm: () => true },
    fetch: () => Promise.reject(new Error("pas de pont dans le banc")),
    requestAnimationFrame: cb => cb(),
    addEventListener(){},   // Échap ferme le volet — hors de portée de ce banc
    setTimeout, clearTimeout, console,
  };
}

const source = fs.readFileSync(APP, "utf8")
  + "\n;globalThis.__banc = { appliqueModeVolet, rend, rapidesClic,"
  + "  pose: e => { etat = e; } };\n";
const bac = vm.createContext(faux());
bac.globalThis = bac;
vm.runInContext(source, bac, { filename: "app.js" });
const T = bac.__banc;
const html = () => bac.document.documentElement;

/* ========================================================================== */
titre("1. La surface du volet suit le mode réel, pas seulement la tuile");
/* ========================================================================== */
T.pose({ rapides: { theme: "clair" } });
T.appliqueModeVolet();
if (html().dataset.mode === "clair") ok("mode « clair » → data-mode posé sur <html>");
else non("mode « clair » n'a pas posé data-mode : " + JSON.stringify(html().dataset));

T.pose({ rapides: { theme: "sombre" } });
T.appliqueModeVolet();
if (!("mode" in html().dataset)) ok("mode « sombre » → data-mode retiré (c'est le défaut)");
else non("mode « sombre » a laissé data-mode en place : " + JSON.stringify(html().dataset));

/* --- Un autre volet ouvert (météo, agenda) : rien à casser ---------------- */
T.pose({});   // etat.rapides est absent hors du volet « rapides »
try {
  T.appliqueModeVolet();
  ok("etat.rapides absent (autre volet) : aucune exception, rien ne change à l'aveugle");
} catch (e) {
  non("etat.rapides absent a fait planter appliqueModeVolet() : " + e.message);
}

/* ========================================================================== */
titre("2. rend() applique le mode à chaque rafraîchissement — pas qu'au chargement");
/* ========================================================================== */
//  C'est LE bogue d'Alex : rend() (appelé par rafraichir(), après CHAQUE
//  clic sur la tuile) doit reposer le mode lui-même — sinon la tuile change
//  de libellé pendant que la fenêtre autour d'elle reste figée.
T.pose({ rapides: { theme: "clair" } });
T.rend();
if (html().dataset.mode === "clair")
  ok("rend() applique bien le mode à chaque appel, pas seulement au premier rendu");
else
  non("rend() n'a pas mis à jour data-mode : le bogue de la photo d'Alex reviendrait");

console.log(`\n\x1b[1m${reussis} réussis, ${echoues} échoués\x1b[0m`);
process.exit(echoues === 0 ? 0 : 1);
