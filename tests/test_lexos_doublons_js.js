/* =============================================================================
 *  Aucune fonction des Paramètres ne doit être déclarée deux fois
 * =============================================================================
 *  ALEX : « quand je clique sur le bouton pour changer le dock de position,
 *  il change de position, mais dans les paramètres il change pas — il reste
 *  à droite ».
 *
 *  ═══ LA CAUSE, ET POURQUOI ELLE ÉTAIT INVISIBLE ═══
 *  setDock() était déclarée DEUX FOIS dans app.js, à 190 lignes d'écart.
 *  La première rafraîchissait la page (rafraichir(), qui relit l'état de la
 *  machine) ; la seconde se contentait d'un toast. En JavaScript, deux
 *  déclarations de fonction du même nom dans la même portée ne cohabitent
 *  pas : LA DERNIÈRE ÉCRASE LA PREMIÈRE. La bonne version était donc du code
 *  mort qui avait l'air vivant — elle se lisait très bien, elle ne
 *  s'exécutait jamais.
 *
 *  Le symptôme est exactement celui d'Alex : le dock bougeait (l'appel à la
 *  machine partait dans les deux versions) mais le bouton en surbrillance
 *  suit « etat.dock », que seule la version morte mettait à jour.
 *
 *  setLangue() portait le même doublon, avec la même conséquence silencieuse.
 *  DEUX fonctions cassées de la même façon, et rien pour le dire : ni
 *  « node --check » (le fichier se parse parfaitement — c'est du JavaScript
 *  valide), ni aucun banc, qui éprouvent le RENDU et pas la structure.
 *
 *  ═══ CE QUE CE BANC FAIT ═══
 *  Il relève chaque déclaration de fonction de la page et refuse qu'un nom
 *  apparaisse deux fois. C'est un contrôle de structure, pas de
 *  comportement : il ne dit pas si setDock est juste, il dit qu'il n'y en a
 *  qu'une — et c'est précisément ce que personne ne vérifiait.
 * ========================================================================== */
"use strict";
const fs = require("fs");
const path = require("path");

const RACINE = path.join(__dirname, "..");
//  Les deux vitrines : l'ISO et la démo. La démo est le cahier des charges
//  de l'ISO ; un doublon y produirait exactement la même panne muette.
const FICHIERS = [
  "config/includes.chroot/usr/share/lexos/settings/web/app.js",
  "config/includes.chroot/usr/share/lexos/volet/web/app.js",
];

let reussis = 0, echoues = 0;
const ok  = m => { console.log("  \x1b[32m✅\x1b[0m " + m); reussis++; };
const non = m => { console.log("  \x1b[31m❌\x1b[0m " + m); echoues++; };
const titre = m => console.log("\n\x1b[1m═══ " + m + " ═══\x1b[0m");

titre("Chaque fonction n'est déclarée qu'une fois");

//  On ne relève que les déclarations DE PREMIER NIVEAU (colonne 0) : une
//  fonction imbriquée peut légitimement porter le même nom qu'une autre
//  dans une portée différente, et crier là-dessus serait un faux positif.
//  C'est le premier niveau qui s'écrase silencieusement.
const DECL = /^(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)/gm;

let vus = 0;
for (const rel of FICHIERS) {
  const abs = path.join(RACINE, rel);
  if (!fs.existsSync(abs)) continue;      // le volet peut ne pas exister
  vus++;
  const src = fs.readFileSync(abs, "utf8");
  const compte = new Map();
  let m;
  while ((m = DECL.exec(src)) !== null) {
    compte.set(m[1], (compte.get(m[1]) || 0) + 1);
  }
  const doubles = [...compte.entries()].filter(([, n]) => n > 1);
  const nom = path.basename(path.dirname(path.dirname(rel))) + "/" + path.basename(rel);
  if (doubles.length === 0) {
    ok(`${nom} : ${compte.size} fonctions, aucune en double`);
  } else {
    for (const [f, n] of doubles) {
      non(`${nom} : « ${f} » est déclarée ${n} fois — la dernière écrase les autres, en silence`);
    }
  }
}

//  UN BANC QUI N'A RIEN LU NE PROUVE RIEN. Si les chemins changent un jour,
//  ce contrôle doit devenir rouge plutôt que vert par défaut.
if (vus > 0) ok(`${vus} fichier(s) réellement analysé(s)`);
else non("aucun fichier analysé — les chemins ont changé, le contrôle est creux");

//  ═══ ET LES DEUX FONCTIONS D'ALEX, NOMMÉMENT ═══
//  Le contrôle général ci-dessus suffirait. Celui-ci nomme les deux cas
//  vécus : si l'un revient, le message dit tout de suite de quoi il s'agit,
//  au lieu de laisser rechercher pourquoi « un bouton ne se met pas à jour ».
const APP = path.join(RACINE, FICHIERS[0]);
const src = fs.readFileSync(APP, "utf8");
for (const f of ["setDock", "setLangue"]) {
  const n = (src.match(new RegExp(`^(?:async\\s+)?function\\s+${f}\\b`, "gm")) || []).length;
  if (n === 1) ok(`${f}() n'est déclarée qu'une fois`);
  else non(`${f}() est déclarée ${n} fois — le bogue du dock d'Alex est de retour`);
}

//  Et celle qui reste doit bien RAFRAÎCHIR : sans ça, le bouton en
//  surbrillance ne suivrait toujours pas, doublon ou pas.
for (const [f, cle] of [["setDock", "dock"], ["setLangue", "langue"]]) {
  const corps = (src.match(new RegExp(`^(?:async\\s+)?function\\s+${f}\\b[\\s\\S]*?\\n\\}`, "m")) || [""])[0];
  if (/rafraichir\(/.test(corps))
    ok(`${f}() rafraîchit la page — le bouton sélectionné suivra « etat.${cle} »`);
  else
    non(`${f}() ne rafraîchit pas : le réglage s'appliquerait sans que la page le montre`);
}

console.log(`\n\x1b[1m${reussis} réussis, ${echoues} échoués\x1b[0m`);
process.exit(echoues === 0 ? 0 : 1);
