/* =============================================================================
 *  Éprouver la règle polkit qui rend le bouton « Éteindre » du greeter utile
 * =============================================================================
 *  ALEX : « les boutons étaient plus activés, j'avais beau cliquer pour sortir
 *  ou arrêter l'ordinateur et j'étais pas capable de arrêter — dans la page
 *  pour connecter utilisateur une fois sorti du bureau ».
 *
 *  CE QUI SE PASSAIT VRAIMENT. Le menu ~power n'était pas cassé : il demandait
 *  une autorisation qu'on ne pouvait pas lui donner. systemd-logind protège
 *  l'extinction par DEUX actions selon l'état de la machine — « power-off »
 *  (autorisée pour une session active) et « power-off-multiple-sessions »
 *  (mot de passe administrateur). Or « changer d'utilisateur » LAISSE la
 *  session de départ ouverte : arriver au greeter par ce chemin met toujours
 *  la machine dans le second cas. Aucun agent d'authentification ne tourne sur
 *  l'écran de connexion pour réclamer ce mot de passe : la demande est refusée
 *  en silence, le clic ne fait rien.
 *
 *  POURQUOI CE BANC EXISTE, ET PAS SEULEMENT UNE RELECTURE. Cette règle
 *  ACCORDE un pouvoir. Une faute de frappe dans un nom d'action ne se voit
 *  pas (la règle ne rendrait simplement jamais rien, et le bouton resterait
 *  muet — la panne d'origine, inchangée) ; une règle trop LARGE ne se voit pas
 *  non plus (elle donnerait à un compte ordinaire des droits qu'il ne doit pas
 *  avoir). Les deux moitiés se prouvent, elles ne se relisent pas.
 *
 *  MÊME TECHNIQUE QUE test_lexos_volet_mode.js : on charge le VRAI fichier
 *  dans un décor minimal et on regarde ce qu'il répond.
 * ========================================================================== */
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const RACINE = path.join(__dirname, "..");
const REGLE = path.join(RACINE,
  "config/includes.chroot/etc/polkit-1/rules.d/49-lexos-connexion-arret.rules");

let reussis = 0, echoues = 0;
const ok  = m => { console.log("  \x1b[32m✅\x1b[0m " + m); reussis++; };
const non = m => { console.log("  \x1b[31m❌\x1b[0m " + m); echoues++; };
const titre = m => console.log("\n\x1b[1m═══ " + m + " ═══\x1b[0m");

/* --- Le décor : le polkit que polkitd donne à une règle ------------------- */
const posees = [];
const polkit = {
  addRule: f => posees.push(f),
  //  Les valeurs réelles sont des objets opaques ; seule leur IDENTITÉ compte.
  Result: { YES: "YES", NO: "NO", AUTH_ADMIN: "AUTH_ADMIN",
            AUTH_ADMIN_KEEP: "AUTH_ADMIN_KEEP", NOT_HANDLED: "NOT_HANDLED" },
  log: () => {},
};

const bac = vm.createContext({ polkit });
vm.runInContext(fs.readFileSync(REGLE, "utf8"), bac, { filename: "49-lexos-connexion-arret.rules" });

titre("0. Le fichier se charge comme polkitd le chargerait");
if (posees.length === 1) ok("la règle s'enregistre (une seule fois) auprès de polkit");
else non("nombre de règles enregistrées : " + posees.length + " — polkitd n'en verrait pas une seule");

const regle = posees[0];
const juge = (utilisateur, action) => regle({ id: action }, { user: utilisateur });

/* ========================================================================== */
titre("1. Le greeter peut enfin éteindre — le bogue d'Alex");
/* ========================================================================== */
//  Le cas EXACT de la photo : sorti du bureau par « changer d'utilisateur »,
//  donc une autre session encore ouverte, donc la forme « -multiple-sessions ».
[
  ["org.freedesktop.login1.power-off-multiple-sessions", "éteindre alors qu'une autre session est ouverte (LE cas d'Alex)"],
  ["org.freedesktop.login1.reboot-multiple-sessions",    "redémarrer alors qu'une autre session est ouverte"],
  ["org.freedesktop.login1.suspend-multiple-sessions",   "mettre en veille alors qu'une autre session est ouverte"],
  ["org.freedesktop.login1.hibernate-multiple-sessions", "hiberner alors qu'une autre session est ouverte"],
].forEach(([action, quoi]) => {
  const r = juge("lightdm", action);
  if (r === "YES") ok(quoi);
  else non(quoi + " : la règle répond « " + r + " » — le clic resterait sans effet");
});

//  Les formes simples passaient DÉJÀ (Debian les autorise pour une session
//  active). On les nomme quand même : sans elles, « Éteindre » marcherait ou
//  non selon qu'une autre session traîne — le genre d'incohérence qui donne
//  l'impression que le bouton est cassé une fois sur deux.
[
  ["org.freedesktop.login1.power-off", "éteindre quand on est seul (déjà permis, mais cohérent)"],
  ["org.freedesktop.login1.reboot",    "redémarrer quand on est seul"],
].forEach(([action, quoi]) => {
  const r = juge("lightdm", action);
  if (r === "YES") ok(quoi);
  else non(quoi + " : « " + r + " »");
});

/* ========================================================================== */
titre("2. Et personne d'autre ne gagne quoi que ce soit");
/* ========================================================================== */
//  LA MOITIÉ QUI COMPTE AUTANT. Une règle trop large ne se voit jamais à
//  l'usage : tout marche, y compris ce qui ne devrait pas.
[
  ["alex",    "org.freedesktop.login1.power-off-multiple-sessions", "un compte ORDINAIRE n'obtient pas l'extinction forcée"],
  ["root",    "org.freedesktop.login1.power-off-multiple-sessions", "même « root » n'est pas traité à part ici (ses droits viennent d'ailleurs)"],
  ["invite",  "org.freedesktop.login1.reboot-multiple-sessions",    "le compte invité non plus"],
].forEach(([utilisateur, action, quoi]) => {
  const r = juge(utilisateur, action);
  if (r === undefined) ok(quoi + " — la règle se tait, les défauts de Debian s'appliquent");
  else non(quoi + " : la règle répond « " + r + " » alors qu'elle devrait se taire");
});

//  Et le compte lightdm ne gagne rien HORS du menu ~power.
[
  ["org.freedesktop.systemd1.manage-units",     "lightdm ne peut pas piloter les services"],
  ["org.freedesktop.login1.set-user-linger",    "lightdm ne peut pas changer les réglages de session"],
  ["org.lexos.boost.executer",                  "LexOS Boost reste protégé par son mot de passe"],
  ["org.freedesktop.packagekit.package-install","lightdm ne peut pas installer de paquets"],
].forEach(([action, quoi]) => {
  const r = juge("lightdm", action);
  if (r === undefined) ok(quoi);
  else non(quoi + " : la règle répond « " + r + " » — elle est trop large");
});

/* ========================================================================== */
titre("3. Les noms d'actions sont ceux de logind, pas des approximations");
/* ========================================================================== */
//  UNE FAUTE DE FRAPPE ICI EST INVISIBLE À L'USAGE : la règle ne rendrait
//  jamais rien pour l'action mal nommée, et le bouton resterait exactement
//  aussi muet qu'avant le correctif. On relit donc le texte du fichier.
const texte = fs.readFileSync(REGLE, "utf8");
const attendues = [
  "org.freedesktop.login1.power-off",
  "org.freedesktop.login1.power-off-multiple-sessions",
  "org.freedesktop.login1.reboot",
  "org.freedesktop.login1.reboot-multiple-sessions",
  "org.freedesktop.login1.suspend",
  "org.freedesktop.login1.suspend-multiple-sessions",
  "org.freedesktop.login1.hibernate",
  "org.freedesktop.login1.hibernate-multiple-sessions",
];
const manquantes = attendues.filter(a => !texte.includes('"' + a + '"'));
if (manquantes.length === 0) ok("les huit actions de logind sont nommées exactement");
else non("actions absentes ou mal orthographiées : " + manquantes.join(", "));

//  Le fichier doit se nommer « 49- » ou moins : polkitd lit dans l'ordre
//  alphabétique et s'arrête à la première règle qui répond. Les défauts de
//  Debian vivent dans 50-default.rules — passer après ne servirait à rien.
const nom = path.basename(REGLE);
const rang = parseInt(nom.slice(0, 2), 10);
if (Number.isFinite(rang) && rang < 50)
  ok("le fichier est lu AVANT les défauts de Debian (« " + nom + " » < 50-default.rules)");
else
  non("« " + nom + " » serait lu après 50-default.rules — la règle ne servirait à rien");

//  .pkla : polkitd de Debian trixie ne les lit plus. Un tel fichier serait
//  ignoré en silence — la panne muette qu'on vient justement de corriger.
if (!REGLE.endsWith(".pkla")) ok("règle écrite en JavaScript (.rules), pas en .pkla que trixie ignore");
else non("un .pkla ne serait jamais lu par polkitd sur trixie");

console.log(`\n\x1b[1m${reussis} réussis, ${echoues} échoués\x1b[0m`);
process.exit(echoues === 0 ? 0 : 1);
