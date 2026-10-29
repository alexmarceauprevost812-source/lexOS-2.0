/* LexOS Bureau — le bureau « démon » (saveur nomade), au style du lanceur
   du téléphone d'Alex.

   Même serveur que index.html (serveur.py) : /api/etat pour les réglages et
   les applis, /api/lancer pour ouvrir une appli DE LA TABLE, /api/outils
   pour la liste de toutes les applis (la recherche), /api/demander pour
   « ? question » (ti-lex IA), /api/reglages pour garder les choix du
   panneau « Yeux », /api/version pour voir un réglage changé ailleurs.

   PAS DE MOT DE PASSE ICI. La page d'origine faisait semblant de vérifier
   un mot de passe en JavaScript (n'importe lequel ouvrait). LightDM a déjà
   authentifié la session ; « Verrouiller » appelle le vrai verrou du
   système (/api/session → lexos-session verrouiller). Il ne reste que
   l'ouverture : les yeux qui s'allument dans le noir, un éclat, le bureau.

   LÉGER : une seule minuterie de dessin (la pluie, dix images par seconde
   au plus, arrêtée page cachée, figée en mode allégé) ; les mouvements de
   souris sont regroupés par requestAnimationFrame ; le reste est en CSS. */
"use strict";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const PARAMS = new URLSearchParams(location.search);
const JETON = PARAMS.get("t") || "";
const SECONDAIRE = PARAMS.get("ecran") === "autre";
const LEGER = PARAMS.get("leger") === "1";
const CALME = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (LEGER) document.documentElement.classList.add("leger");
if (SECONDAIRE) document.body.classList.add("secondaire");
document.body.classList.add("en-intro");

let P = null;            // les réglages (reglages.py)
let E = null;            // le dernier /api/etat
let VERSION = "";

async function api(chemin, corps) {
  const r = await fetch(chemin, corps === undefined
    ? { headers: { "X-Jeton": JETON }, cache: "no-store" }
    : { method: "POST", headers: { "X-Jeton": JETON, "Content-Type": "application/json" }, body: JSON.stringify(corps) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}
const garder = (partiel) => api("/api/reglages", partiel).catch(() => bulle("Le bureau ne répond pas — réglage non gardé"));
const echapper = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const sansAccents = (t) => String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

let minuteurBulle = null;
function bulle(texte) {
  const b = $("#bulle");
  b.textContent = texte; b.hidden = false;
  clearTimeout(minuteurBulle);
  minuteurBulle = setTimeout(() => { b.hidden = true; }, 3500);
}

/* ════════════════ Marges : la barre du haut et le dock Plank ════════════════
   Même calcul que bureau.js : ce que Qt a vu au démarrage, ou ce que
   _NET_WORKAREA dit maintenant — le plus grand des deux. */
const entier = (nom) => { const v = parseInt(PARAMS.get(nom) || "0", 10); return Number.isFinite(v) ? v : 0; };
const ECRAN = { x: entier("gx"), y: entier("gy"), l: entier("gl"), h: entier("gh") };
const MARGES_QT = { haut: entier("haut"), bas: entier("bas"), gauche: entier("gauche"), droite: entier("droite") };
function poserMarges(zone) {
  const m = { ...MARGES_QT };
  if (Array.isArray(zone) && zone.length === 4 && ECRAN.l > 0 && ECRAN.h > 0) {
    const [x, y, l, h] = zone, borne = (v, max) => Math.max(0, Math.min(v, max));
    m.haut = Math.max(m.haut, borne(y - ECRAN.y, ECRAN.h / 3));
    m.gauche = Math.max(m.gauche, borne(x - ECRAN.x, ECRAN.l / 3));
    m.bas = Math.max(m.bas, borne(ECRAN.y + ECRAN.h - (y + h), ECRAN.h / 3));
    m.droite = Math.max(m.droite, borne(ECRAN.x + ECRAN.l - (x + l), ECRAN.l / 3));
  }
  for (const [cote, v] of Object.entries(m)) {
    document.documentElement.style.setProperty("--" + cote, Math.round(Math.max(0, Math.min(v, 400))) + "px");
  }
}
function poserDock(dock) {
  const r = document.documentElement.style;
  const place = dock && dock.taille ? Math.min(200, dock.taille + 22) + "px" : "0px";
  r.setProperty("--dock-g", dock?.cote === "left" ? place : "0px");
  r.setProperty("--dock-d", dock?.cote === "right" ? place : "0px");
  r.setProperty("--dock-h", dock?.cote === "top" ? place : "0px");
  r.setProperty("--dock-b", dock?.cote === "bottom" ? place : "0px");
}

/* ════════════════ Les yeux en amande ════════════════
   Un aplat, coins extérieurs pointus : la forme du lanceur du téléphone. */
const OEIL = "M2 3 C26 8 62 20 97 34 C99 42 92 49 78 50 C56 51 34 42 20 30 C10 21 4 12 2 3 Z";
$$(".oeil-trace").forEach((p) => p.setAttribute("d", OEIL));

/* ════════════════ Les thèmes ════════════════
   Sang (le rouge du téléphone) par défaut ; Brasier et Spectre repeignent
   la même page. Les YEUX restent rouges dans les trois : ce sont les yeux
   du démon. */
const THEMES = {
  sang:    { nom: "Sang",    ac: "#e02424", fonce: "#7a1010", pluie: "#e02424", filtre: "none" },
  brasier: { nom: "Brasier", ac: "#ff6a1a", fonce: "#7a2a06", pluie: "#ff6a1a", filtre: "none" },
  spectre: { nom: "Spectre", ac: "#3aa0ff", fonce: "#0d3f73", pluie: "#3aa0ff", filtre: "hue-rotate(190deg) saturate(1.2)" },
};
$("#themes").innerHTML = Object.entries(THEMES).map(([k, T]) =>
  `<button class="theme" data-theme="${k}" style="--t:${T.ac}"><i></i>${T.nom}</button>`).join("");
let THEME = THEMES.sang;
function appliquerTheme(k) {
  THEME = THEMES[k] || THEMES.sang;
  const r = document.documentElement.style;
  r.setProperty("--ac", THEME.ac); r.setProperty("--ac-fonce", THEME.fonce); r.setProperty("--filtre-logo", THEME.filtre);
  $$(".theme").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.theme === k)));
  pluieFixe();
}
$("#themes").addEventListener("click", (e) => {
  const b = e.target.closest(".theme"); if (!b || !P) return;
  P.demon_theme = b.dataset.theme; appliquerTheme(P.demon_theme); majTerminal();
  garder({ demon_theme: P.demon_theme });
});

/* ════════════════ La pluie de 0 et de 1 ════════════════
   Une toile à la résolution CSS (pas de facteur d'écran : ce sont des
   chiffres flous à 55 % d'opacité, personne ne verra la différence, et ça
   divise le travail par quatre sur un écran HiDPI). Dix images par seconde
   au plus, aucune quand la page est cachée. En mode allégé, avec « réduire
   les animations », ou pluie éteinte : une seule image fixe, ou rien. */
const toile = $("#pluie"), ctx = toile.getContext("2d");
const PAS = 18;
let colonnes = [], minuteurPluie = null;
function preparerPluie() {
  toile.width = innerWidth; toile.height = innerHeight;
  colonnes = Array.from({ length: Math.ceil(innerWidth / PAS) }, () => Math.random() * innerHeight / PAS);
  ctx.font = "15px 'LX JetBrains Mono', monospace";
}
function goutte() {
  ctx.fillStyle = "rgba(6,6,6,.16)";
  ctx.fillRect(0, 0, toile.width, toile.height);
  ctx.fillStyle = THEME.pluie;
  ctx.globalAlpha = .55;
  for (let i = 0; i < colonnes.length; i++) {
    if (Math.random() < .55) continue;            // des colonnes clairsemées
    ctx.fillText(Math.random() < .5 ? "0" : "1", i * PAS, colonnes[i] * PAS);
    colonnes[i] = colonnes[i] * PAS > toile.height && Math.random() > .96 ? 0 : colonnes[i] + 1;
  }
  ctx.globalAlpha = 1;
}
function pluieFixe() {
  //  Une image immobile : les colonnes de chiffres, sans mouvement.
  ctx.clearRect(0, 0, toile.width, toile.height);
  if (!P || !P.demon_pluie) return;
  ctx.fillStyle = THEME.pluie; ctx.globalAlpha = .35;
  for (let i = 0; i < colonnes.length; i += 1) {
    if ((i * 7) % 3 === 0) continue;
    for (let y = (i * 37) % 90; y < toile.height; y += PAS * 1.4) ctx.fillText(((i + y) % 2) ? "1" : "0", i * PAS, y);
  }
  ctx.globalAlpha = 1;
}
function pluie() {
  clearInterval(minuteurPluie); minuteurPluie = null;
  if (!P || !P.demon_pluie || LEGER || CALME) { pluieFixe(); return; }
  minuteurPluie = setInterval(() => { if (!document.hidden) goutte(); }, 100);
}
addEventListener("resize", () => { preparerPluie(); pluie(); });
preparerPluie();

/* ════════════════ L'horloge et la date ════════════════ */
const JOURS = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."];
const MOIS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];
function majHorloge() {
  const d = new Date(), p = (n) => String(n).padStart(2, "0");
  const h = `${p(d.getHours())}:${p(d.getMinutes())}`, j = `${JOURS[d.getDay()]} ${d.getDate()} ${MOIS[d.getMonth()]}`;
  if ($("#horloge").textContent !== h) $("#horloge").textContent = h;
  if ($("#date").textContent !== j) $("#date").textContent = j;
}
majHorloge(); setInterval(majHorloge, 1000);

/* ════════════════ Le petit terminal (ce que dirait neofetch) ════════════════ */
function majTerminal() {
  const s = (E && E.systeme) || {}, compte = s.compte || "moi", hote = "lexos" + (s.saveur ? "-" + s.saveur : "");
  $("#term-titre").textContent = `${compte}@${hote}: ~`;
  $("#term-invite").textContent = `${compte}@${hote}`;
  const lignes = [
    ["os", `${s.nom || "LexOS"}${s.version ? " " + s.version : ""}${s.saveur ? " (" + s.saveur + ")" : ""}`],
    ["base", "Debian trixie"],
    ["bureau", "LexOS démon"],
    ["thème", (THEME.nom || "Sang").toLowerCase()],
    ["shell", "bash"],
  ];
  const corps = $("#term-corps");
  $$("p.info", corps).forEach((p) => p.remove());
  corps.insertAdjacentHTML("beforeend", lignes.map(([k, v]) =>
    `<p class="info"><span class="cle">${echapper(k)}</span>${echapper(v)}</p>`).join(""));
}

/* ════════════════ Les yeux suivent la souris ════════════════ */
const SOURIS = { x: 0, y: 0, attente: false };
function regarder(lx, ly) {
  $("#yeux").style.transform = `translate(${(lx * 18).toFixed(1)}px,${(ly * 10).toFixed(1)}px) rotate(${(lx * 2).toFixed(1)}deg)`;
}
function suivre() {
  SOURIS.attente = false;
  if (!P || !P.demon_suivre) return;
  const r = $("#yeux").getBoundingClientRect();
  const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
  regarder(Math.max(-1, Math.min(1, (SOURIS.x - cx) / (innerWidth / 2))),
           Math.max(-1, Math.min(1, (SOURIS.y - cy) / (innerHeight / 2))));
}
addEventListener("mousemove", (e) => {
  SOURIS.x = e.clientX; SOURIS.y = e.clientY;
  if (!SOURIS.attente) { SOURIS.attente = true; requestAnimationFrame(suivre); }
});
document.addEventListener("mouseleave", () => regarder(0, 0));

/* ════════════════ La plongée : les yeux foncent vers toi ════════════════
   Une appli s'ouvre : une copie des deux yeux est posée EXACTEMENT sur les
   vrais (leurs rectangles à l'écran, transformations comprises), grossit
   jusqu'à remplir l'écran (0,65 s, en accélérant) et s'efface. La demande
   de lancement part AVANT : l'appli n'attend jamais le spectacle. Ni en
   mode allégé (pas de GPU), ni avec « réduire les animations ». */
let finPlongee = null;
function plonger() {
  if (LEGER || CALME || SECONDAIRE) return;
  const rects = $$("#yeux .oeil").map((o) => o.getBoundingClientRect());
  if (rects.length !== 2) return;
  const g = Math.min(rects[0].left, rects[1].left), h = Math.min(rects[0].top, rects[1].top);
  const l = Math.max(rects[0].right, rects[1].right) - g, ht = Math.max(rects[0].bottom, rects[1].bottom) - h;
  if (l < 2 || ht < 2) return;
  const boite = $("#plongee-yeux"), voile = $("#plongee");
  boite.style.cssText = `left:${g}px;top:${h}px;width:${l}px;height:${ht}px`;
  boite.innerHTML = rects.map((r, i) =>
    `<svg viewBox="0 0 100 52" preserveAspectRatio="none" style="left:${r.left - g}px;top:${r.top - h}px;width:${r.width}px;height:${r.height}px">`
    + `<path d="${OEIL}" style="fill:var(--oeil)"${i === 1 ? ' transform="translate(100 0) scale(-1 1)"' : ""}/></svg>`).join("");
  //  Assez grand pour que les amandes débordent l'écran de partout, d'où
  //  qu'elles partent ; borné pour ne pas créer une texture géante.
  const cx = g + l / 2, cy = h + ht / 2;
  const besoin = Math.max(Math.max(cx, innerWidth - cx) * 2 / l, Math.max(cy, innerHeight - cy) * 2 / ht);
  boite.style.setProperty("--echelle", Math.min(40, Math.max(6, besoin * 1.6)).toFixed(2));
  clearTimeout(finPlongee);
  voile.classList.remove("en-cours"); void voile.offsetWidth; voile.classList.add("en-cours");
  finPlongee = setTimeout(() => { voile.classList.remove("en-cours"); boite.textContent = ""; }, 980);
}

/* ════════════════ Ouvrir une appli ════════════════ */
const DERNIERS = new Map();
async function lancer(id, nom) {
  const maintenant = performance.now();
  if (maintenant - (DERNIERS.get(id) || -1e9) < 1200) return;   // le double-clic d'XFCE
  DERNIERS.set(id, maintenant);
  const demande = api("/api/lancer", { id });                    // part tout de suite
  plonger();
  try {
    const r = await demande;
    if (r.raison === "non-approuve") bulle(`« ${nom} » n'est pas encore approuvé : Fichiers s'ouvre — double-clique-le là pour l'approuver`);
    else if (!r.ok) bulle(`Impossible d'ouvrir « ${nom} »`);
  } catch { bulle("Le bureau ne répond pas"); }
}

/* ════════════════ La grille, le dock ════════════════ */
const DESSINS = {
  terminal: "M4 5h16v14H4z M7 10l3 2-3 2 M12 15h5",
  fichiers: "M8 4h7l4 4v12H8z M15 4v4h4 M5 7v13h10",
  navigateur: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z M3 12h18 M12 3c3 3 3 15 0 18 M12 3c-3 3-3 15 0 18",
  parametres: "M12 8.8a3.2 3.2 0 1 0 0 6.4 3.2 3.2 0 0 0 0-6.4z M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.1 2.1 M17 17l2.1 2.1 M4.9 19.1 7 17 M17 7l2.1-2.1",
  installer: "M12 3v11 M7 9l5 5 5-5 M4 17v3h16v-3",
  maison: "M3 11l9-7 9 7 M5 10v10h14V10 M10 20v-6h4v6",
  corbeille: "M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13",
  appli: "M5 5h6v6H5z M13 5h6v6h-6z M5 13h6v6H5z M13 13h6v6h-6z",
};
const LIBELLES = { fichiers: "mes fichiers", maison: "dossier perso", installer: "installer lexos" };
const ORDRE_GRILLE = ["terminal", "fichiers", "navigateur", "parametres", "maison", "corbeille", "installer"];
const ORDRE_DOCK = ["terminal", "fichiers", "navigateur", "parametres"];
const trait = (cle) => `<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${DESSINS[cle] || DESSINS.appli}"/></svg>`;
const yeuxTuile = `<svg viewBox="0 0 220 60" aria-hidden="true"><path style="fill:var(--oeil)" d="${OEIL}" transform="translate(4 4)"/><path style="fill:var(--oeil)" d="${OEIL}" transform="translate(216 4) scale(-1 1)"/></svg>`;
function tuile(e) {
  const nom = LIBELLES[e.cle] || e.nom;
  const image = e.icone ? `<img src="/icone/${encodeURIComponent(e.id)}?t=${encodeURIComponent(JETON)}" alt="">` : trait(e.cle);
  return `<button class="appli" data-id="${echapper(e.id)}" data-nom="${echapper(e.nom)}" title="${echapper(e.nom)}">`
    + `<span class="tuile">${image}</span><span class="nom">${echapper(nom)}</span></button>`;
}
const TUILE_YEUX = `<button class="appli yeux-appli" data-yeux title="Yeux — réglages du bureau démon">`
  + `<span class="tuile yeux-tuile">${yeuxTuile}</span><span class="nom">yeux</span></button>`;
let empreinteApplis = "";
function dessinerApplis(liste) {
  const empreinte = JSON.stringify(liste || []);
  if (empreinte === empreinteApplis) return;
  empreinteApplis = empreinte;
  const parCle = new Map((liste || []).map((e) => [e.cle, e]));
  if (!$("#question").value.trim()) dessinerGrille();
  $("#dock").innerHTML = ORDRE_DOCK.filter((k) => parCle.has(k)).map((k) => tuile(parCle.get(k))).join("") + TUILE_YEUX;
}
function dessinerGrille() {
  const parCle = new Map(((E && E.demon) || []).map((e) => [e.cle, e]));
  $("#grille").innerHTML = ORDRE_GRILLE.filter((k) => parCle.has(k)).map((k) => tuile(parCle.get(k))).join("") + TUILE_YEUX;
}
document.addEventListener("click", (e) => {
  if (e.target.closest("[data-yeux]")) { ouvrirPanneau(!$("#panneau").classList.contains("ouvert")); return; }
  const b = e.target.closest("[data-id]");
  if (b) lancer(b.dataset.id, b.dataset.nom || "");
});

/* ════════════════ La recherche : « $ chercher… ou ? pc » ════════════════
   Ce qu'on tape filtre TOUTES les applis installées (la liste du labo,
   /api/outils, chargée au premier caractère) ; Entrée ouvre la première.
   « ? question » la pose à ti-lex IA, quand il est là. */
let TOUTES = null;
async function toutesLesApplis() {
  if (TOUTES) return TOUTES;
  const o = await api("/api/outils");
  const vus = new Set(), liste = [];
  for (const s of o.sections || []) for (const e of s.elements || []) {
    if (!e.id || vus.has(e.id) || e.id.startsWith("b-")) continue;    // pas les fichiers du dossier Bureau
    vus.add(e.id); liste.push({ id: e.id, nom: e.nom, icone: !!e.icone, cle: "appli" });
  }
  TOUTES = liste;
  return liste;
}
let trouvees = [];
async function chercher() {
  const q = $("#question").value.trim();
  if (!q || q.startsWith("?")) { trouvees = []; dessinerGrille(); return; }
  let liste = [];
  try { liste = await toutesLesApplis(); } catch { bulle("Le bureau ne répond pas"); return; }
  if ($("#question").value.trim() !== q) return;                         // on a retapé entre-temps
  const m = sansAccents(q);
  trouvees = liste.filter((e) => sansAccents(e.nom).includes(m))
    .sort((a, b) => sansAccents(a.nom).indexOf(m) - sansAccents(b.nom).indexOf(m)).slice(0, 8);
  $("#grille").innerHTML = trouvees.length ? trouvees.map(tuile).join("")
    : `<p class="vide">aucune appli ne s'appelle « ${echapper(q)} »</p>`;
}
async function demander(q) {
  if (!q) { bulle("Écris ta question après le « ? »"); return; }
  if (!(E && E.tilex)) { bulle("ti-lex IA n'est pas installé sur cette clé"); return; }
  try { const r = await api("/api/demander", { q }); if (!r.ok) bulle("ti-lex IA ne répond pas"); else $("#question").value = ""; }
  catch { bulle("Le bureau ne répond pas"); }
}
let minuteurRecherche = null;
$("#question").addEventListener("input", () => { clearTimeout(minuteurRecherche); minuteurRecherche = setTimeout(chercher, 120); });
$("#question").addEventListener("keydown", (e) => { if (e.key === "Escape") { e.target.value = ""; chercher(); } });
$("#recherche").addEventListener("submit", async (e) => {
  e.preventDefault();
  const q = $("#question").value.trim();
  if (q.startsWith("?")) return demander(q.slice(1).trim());
  await chercher();
  if (trouvees[0]) { lancer(trouvees[0].id, trouvees[0].nom); $("#question").value = ""; chercher(); }
});
$("#vers-ia").addEventListener("click", () => demander($("#question").value.trim().replace(/^\?\s*/, "")));

/* ════════════════ L'appli « Yeux » : son panneau ════════════════ */
function ouvrirPanneau(ouvert) {
  $("#panneau").classList.toggle("ouvert", ouvert);
  $("#panneau").setAttribute("aria-hidden", String(!ouvert));
}
$("#term-yeux").addEventListener("click", () => ouvrirPanneau(!$("#panneau").classList.contains("ouvert")));
$("#panneau-fermer").addEventListener("click", () => ouvrirPanneau(false));
document.addEventListener("keydown", (e) => { if (e.key === "Escape") ouvrirPanneau(false); });

const INTERRUPTEURS = [
  ["demon_suivre", "les yeux suivent la souris"],
  ["demon_intro", "les yeux s'ouvrent au démarrage"],
  ["demon_pluie", "pluie de 0 et de 1"],
];
$("#interrupteurs").innerHTML = INTERRUPTEURS.map(([k, l]) =>
  `<button class="inter" data-cle="${k}" aria-pressed="true"><span>${l}</span><span class="piste"><span class="bouton"></span></span></button>`).join("");
$("#interrupteurs").addEventListener("click", (e) => {
  const b = e.target.closest(".inter"); if (!b || !P) return;
  const k = b.dataset.cle; P[k] = !P[k];
  b.setAttribute("aria-pressed", String(P[k]));
  if (k === "demon_suivre" && !P[k]) regarder(0, 0);
  if (k === "demon_pluie") pluie();
  garder({ [k]: P[k] });
});
function appliquerPresence() {
  const v = P ? P.demon_presence : 60;
  document.documentElement.style.setProperty("--presence", (v / 100).toFixed(2));
  $("#presence").value = v; $("#presence-pct").textContent = v;
}
$("#presence").addEventListener("input", (e) => { if (P) { P.demon_presence = parseInt(e.target.value, 10) || 60; appliquerPresence(); } });
//  Gardé au relâchement seulement : pas une écriture de fichier par cran.
$("#presence").addEventListener("change", () => P && garder({ demon_presence: P.demon_presence }));

$("#verrouiller").addEventListener("click", async () => {
  ouvrirPanneau(false);
  try { const r = await api("/api/session", { geste: "verrouiller" }); if (!r.ok) bulle("Le verrou de l'écran n'a pas répondu"); }
  catch { bulle("Le bureau ne répond pas"); }
});
$("#parametres").addEventListener("click", async () => {
  ouvrirPanneau(false);
  try { await api("/api/action", { nom: "parametres" }); } catch { bulle("Le bureau ne répond pas"); }
});
$("#vers-moteur").addEventListener("click", async () => {
  try { await api("/api/reglages", { interface: "moteur" }); location.reload(); }
  catch { bulle("Le bureau ne répond pas"); }
});

/* ════════════════ Charger, puis suivre les changements ════════════════ */
async function charger() {
  E = await api("/api/etat");
  const avant = P;
  P = E.reglages;
  //  L'autre page a été choisie (Paramètres, ou ce panneau) : « / » la sert.
  if (P.interface !== "demon") { location.reload(); return; }
  poserMarges(E.zone);
  poserDock(SECONDAIRE ? null : E.dock);
  appliquerTheme(P.demon_theme);
  if (!avant || avant.demon_pluie !== P.demon_pluie) pluie();
  appliquerPresence();
  $$(".inter").forEach((b) => b.setAttribute("aria-pressed", String(!!P[b.dataset.cle])));
  if (!P.demon_suivre) regarder(0, 0);
  $("#vers-ia").hidden = !E.tilex;
  const s = E.systeme || {};
  $("#pied").textContent = `${s.nom || "LexOS"}${s.version ? " " + s.version : ""}${s.saveur ? " (" + s.saveur + ")" : ""} · Debian trixie`;
  majTerminal();
  TOUTES = null;                            // une appli installée entre-temps
  if (!SECONDAIRE) dessinerApplis(E.demon);
}
async function verifier() {
  try {
    const { v } = await api("/api/version");
    if (v !== VERSION) { VERSION = v; await charger(); }
  } catch {}
}

/* ════════════════ L'ouverture ════════════════
   Noir → seuls les yeux s'allument et clignent (≈ 2 s) → éclat → le
   bureau. Un clic ou une touche l'abrège. Sautée si « les yeux s'ouvrent
   au démarrage » est éteint, ou si le système demande moins d'animations. */
function ouverture() {
  const intro = $("#intro"), corps = document.body;
  let fini = false;
  const finir = () => {
    if (fini) return; fini = true;
    intro.classList.add("parti");
    setTimeout(() => { intro.remove(); corps.classList.remove("en-intro", "eveil"); }, 650);
  };
  if (CALME || !P || !P.demon_intro) { finir(); return; }
  const r = $("#yeux").getBoundingClientRect();
  const eclat = $("#eclat");
  eclat.style.left = (r.left + r.width / 2) + "px"; eclat.style.top = (r.top + r.height / 2) + "px";
  corps.classList.add("eveil");
  const t1 = setTimeout(() => intro.classList.add("eclate"), 2000);
  const t2 = setTimeout(finir, 2700);
  const abreger = () => { clearTimeout(t1); clearTimeout(t2); finir(); };
  addEventListener("keydown", abreger, { once: true });
  intro.addEventListener("click", abreger, { once: true });
}

(async () => {
  poserMarges(null);
  appliquerTheme("sang");
  majTerminal();
  try {
    VERSION = (await api("/api/version")).v;
    await charger();
  } catch {
    //  Sans le serveur : le décor et les yeux, sans applis, plutôt qu'une
    //  erreur. lexos-bureau relance xfdesktop si le moteur du bureau tombe.
    P = { interface: "demon", demon_theme: "sang", demon_suivre: true, demon_intro: false, demon_pluie: true, demon_presence: 60 };
    appliquerTheme(P.demon_theme); appliquerPresence(); pluie();
  }
  ouverture();
  setInterval(verifier, 2000);
})();
