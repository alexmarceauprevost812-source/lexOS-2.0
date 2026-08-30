/* =============================================================================
 *  L'accent des pages web de LexOS : une seule table, trois surfaces
 * =============================================================================
 *  ALEX : « dans les paramètres les boutons fonctionnent tous, mais c'est la
 *  couleur orange qui ne change pas dans les paramètres — pour le dock
 *  surtout. »
 *
 *  ═══ DEUX DÉFAUTS, PAS UN ═══
 *  1. rafraichir() relisait l'accent sur la machine et n'en faisait RIEN :
 *     seul rend() posait l'apparence, et rend() ne tourne qu'au démarrage.
 *     Une fenêtre déjà ouverte gardait donc son orange quoi qu'il arrive.
 *     C'était un correctif à moitié : la fois d'avant, on avait ajouté
 *     appliqueApparence() aux trois boutons d'apparence « et seulement ici »,
 *     sans regarder le chemin par lequel la page se resynchronise.
 *  2. Le volet des Paramètres rapides ne posait l'accent NULLE PART. Pas un
 *     bogue de rafraîchissement : la ligne n'existait pas. Il était orange à
 *     vie.
 *
 *  ═══ CE QUE CE BANC PROTÈGE ═══
 *  La table des couleurs vit dans ui.css, partagée. Les pastilles offertes,
 *  elles, viennent d'une table JavaScript. Si les deux divergent, cliquer une
 *  pastille ne change RIEN — aucun bloc CSS ne correspond, et la page retombe
 *  sur l'orange par défaut. Exactement le symptôme d'Alex, réintroduit par un
 *  simple ajout de couleur d'un côté seulement. C'est ce que ce banc interdit.
 * ========================================================================== */
"use strict";
const fs = require("fs");
const path = require("path");

const RACINE = path.join(__dirname, "..");
const UI   = path.join(RACINE, "config/includes.chroot/usr/share/lexos/ui.css");
const APP  = path.join(RACINE, "config/includes.chroot/usr/share/lexos/settings/web/app.js");
const VOLET= path.join(RACINE, "config/includes.chroot/usr/share/lexos/volet/web/app.js");
const GEN  = path.join(RACINE, "config/includes.chroot/usr/bin/lexos-theme-gen");

let reussis = 0, echoues = 0;
const ok  = m => { console.log("  \x1b[32m✅\x1b[0m " + m); reussis++; };
const non = m => { console.log("  \x1b[31m❌\x1b[0m " + m); echoues++; };
const titre = m => console.log("\n\x1b[1m═══ " + m + " ═══\x1b[0m");

const ui = fs.readFileSync(UI, "utf8");
const app = fs.readFileSync(APP, "utf8");
const volet = fs.readFileSync(VOLET, "utf8");
const gen = fs.readFileSync(GEN, "utf8");

titre("1. Chaque pastille offerte a bien son bloc de couleurs");

//  Les noms que la page PROPOSE (les pastilles sont rendues depuis ACCENTS).
const mTable = /const ACCENTS = \{([\s\S]*?)\};/.exec(app);
const offerts = mTable
  ? [...mTable[1].matchAll(/["']?([a-z-]+)["']?\s*:\s*"(#[0-9A-Fa-f]{6})"/g)].map(m => [m[1], m[2]])
  : [];
if (offerts.length >= 8) ok(`${offerts.length} pastilles proposées par la page`);
else non(`table ACCENTS introuvable ou trop courte (${offerts.length}) — le reste serait creux`);

//  Les noms que ui.css SAIT peindre.
const connus = new Map(
  [...ui.matchAll(/:root\[data-accent="([a-z-]+)"\][^{]*\{([^}]*)\}/g)].map(m => [m[1], m[2]]));
if (connus.size >= 8) ok(`${connus.size} accents peints par ui.css`);
else non(`ui.css ne connaît que ${connus.size} accents`);

for (const [nom, hex] of offerts) {
  const bloc = connus.get(nom);
  if (!bloc) {
    non(`« ${nom} » est proposé mais ui.css ne le connaît pas — le clic ne changerait rien`);
    continue;
  }
  const ac = /--ac:\s*(#[0-9A-Fa-f]{6})/.exec(bloc);
  if (ac && ac[1].toUpperCase() === hex.toUpperCase())
    ok(`« ${nom} » : la pastille et le bloc CSS portent la même couleur (${hex})`);
  else
    non(`« ${nom} » : pastille ${hex}, CSS ${ac ? ac[1] : "absent"} — deux couleurs pour un nom`);
}

titre("2. Les couleurs sont celles du BUREAU, pas des valeurs inventées");

//  lexos-theme-gen peint le bureau, la barre et le dock. Si les pages web
//  s'en écartent, la fenêtre où l'on choisit la couleur est la seule à ne pas
//  la porter — ce qui est précisément le genre de chose qu'Alex remarque.
//  ON LIT LES ÉTIQUETTES DU « case », PAS UN MOT DANS LE FICHIER.
//  Une première version cherchait le nom de l'accent n'importe où avant un
//  « ACCENT= » : « rouge » tombait alors sur la branche « orange-rouge », et
//  le banc annonçait un désaccord qui n'existait pas. C'était le banc qui
//  avait tort. On construit donc la table en découpant chaque étiquette sur
//  « | » et en comparant les alternatives une à une, exactement.
const bureau = new Map();
for (const m of gen.matchAll(
       /^\s*([a-z|_-]+)\)\s*\n?\s*ACCENT="(#[0-9A-Fa-f]{6})";\s*ACCENT_HI="(#[0-9A-Fa-f]{6})"/gm)) {
  for (const alt of m[1].split("|")) bureau.set(alt, [m[2], m[3]]);
}
if (bureau.size >= 8) ok(`${bureau.size} noms d'accent lus dans lexos-theme-gen`);
else non(`seulement ${bureau.size} noms lus dans lexos-theme-gen — le reste serait creux`);

for (const [nom, bloc] of connus) {
  const ac = /--ac:\s*(#[0-9A-Fa-f]{6})/.exec(bloc);
  const hi = /--ac-hi:\s*(#[0-9A-Fa-f]{6})/.exec(bloc);
  const b = bureau.get(nom);
  if (!b) { non(`« ${nom} » : ce nom n'existe pas dans lexos-theme-gen`); continue; }
  if (ac && hi && ac[1].toUpperCase() === b[0].toUpperCase()
          && hi[1].toUpperCase() === b[1].toUpperCase())
    ok(`« ${nom} » : mêmes teintes que le bureau (${b[0]} / ${b[1]})`);
  else
    non(`« ${nom} » : web ${ac && ac[1]}/${hi && hi[1]} ≠ bureau ${b[0]}/${b[1]}`);
}

titre("3. Le texte posé sur l'accent reste lisible");

//  Le noir était écrit en dur. Sur le bleu il donne 3,34:1 — sous le seuil.
//  Faire suivre la couleur sans corriger le texte aurait échangé un défaut
//  contre un pire ; on mesure donc, on ne suppose pas.
function lum(h){
  const c = [1,3,5].map(i => parseInt(h.slice(i, i+2), 16)/255)
    .map(v => v <= 0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4));
  return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2];
}
function contraste(a, b){
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}
for (const [nom, bloc] of connus) {
  const ac = /--ac:\s*(#[0-9A-Fa-f]{6})/.exec(bloc);
  const txt = /--ac-txt:\s*(#[0-9A-Fa-f]{3,6})/.exec(bloc);
  if (!ac || !txt) { non(`« ${nom} » : --ac ou --ac-txt manquant`); continue; }
  const plein = txt[1].length === 4
    ? "#" + [...txt[1].slice(1)].map(c => c + c).join("") : txt[1];
  const r = contraste(ac[1], plein);
  if (r >= 4.5) ok(`« ${nom} » : texte lisible sur l'accent (${r.toFixed(2)}:1)`);
  else non(`« ${nom} » : ${r.toFixed(2)}:1 seulement — sous le seuil de 4,5:1`);
}

titre("4. Les deux fenêtres posent l'accent, et se rafraîchissent");

//  LE DÉFAUT D'ALEX, NOMMÉMENT : rafraichir() relit l'état et doit reposer
//  l'apparence. Sans cette ligne, une fenêtre ouverte garde sa vieille
//  couleur quoi qu'il arrive.
//  ON DÉPOUILLE LES COMMENTAIRES AVANT DE CHERCHER L'APPEL.
//  Une première version cherchait « appliqueApparence( » dans le corps brut
//  de la fonction — et le trouvait dans le COMMENTAIRE qui explique le
//  correctif, juste au-dessus de l'appel. Le banc restait donc vert même
//  après avoir supprimé l'appel : il éprouvait de la prose. C'est exactement
//  le défaut que ce dépôt traque partout ailleurs, commis dans l'outil censé
//  le détecter.
const sansCommentaires = t => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
const corpsRafraichir = sansCommentaires(
  (/async function rafraichir\([\s\S]*?\n\}/.exec(app) || [""])[0]);
if (/appliqueApparence\(/.test(corpsRafraichir))
  ok("Paramètres : rafraichir() repose l'apparence après avoir relu la machine");
else
  non("Paramètres : rafraichir() ne repose pas l'apparence — la couleur resterait figée");

if (/dataset\.accent\s*=/.test(sansCommentaires(app)))
  ok("Paramètres : la page pose bien l'accent sur la racine");
else
  non("Paramètres : rien ne pose l'accent");

if (/dataset\.accent\s*=/.test(sansCommentaires(volet)))
  ok("Volet : la page pose bien l'accent (elle ne le faisait NULLE PART)");
else
  non("Volet : l'accent n'est toujours posé nulle part — il resterait orange à vie");

titre("5. Plus de couleur écrite en dur par-dessus l'accent");

for (const [nom, f] of [["Paramètres", "settings"], ["Volet", "volet"]]) {
  const css = fs.readFileSync(
    path.join(RACINE, `config/includes.chroot/usr/share/lexos/${f}/web/style.css`), "utf8");
  const dur = [...css.matchAll(/^.*var\(--ac\)[^\n]*color:\s*#[0-9a-fA-F]{3,6}/gm)];
  if (dur.length === 0) ok(`${nom} : aucun texte figé posé sur l'accent`);
  else non(`${nom} : ${dur.length} règle(s) écrivent une couleur en dur sur l'accent`);
}

console.log(`\n\x1b[1m${reussis} réussis, ${echoues} échoués\x1b[0m`);
process.exit(echoues === 0 ? 0 : 1);
