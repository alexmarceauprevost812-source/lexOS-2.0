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

/* ════════════════ La grille, le dock ════════════════
   CHAQUE TUILE VIT À UN SEUL ENDROIT : dans la grille OU dans le dock. Leur
   ordre est gardé côté serveur (réglages « demon_grille » et « demon_dock »,
   reglages.py) — pas dans le navigateur de la page, qui oublie tout d'une
   session à l'autre. ["*"] = la disposition d'origine.
   La grille est découpée en PAGES à la hauteur que le milieu de l'écran lui
   laisse (mettreEnPages) : elle ne passe plus jamais sous la recherche, à
   1280 × 800 comme à 1920 × 1080. Les points changent de page, la molette
   aussi. */
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
//  Des PHOTOS plutôt que des traits pour deux tuiles : le gars de GitHub
//  (le dépôt de LexOS) et Tux (« à propos »). Petites (≤ 192 px), dans web/.
const PHOTOS = { github: "github-perso.png" };
const LIBELLES = { fichiers: "mes fichiers", maison: "dossier perso", installer: "installer lexos", github: "github" };
//  La disposition d'origine, par clé (applis.DEMON) ou tuile de la page.
const ORIGINE_GRILLE = ["fichiers", "parametres", "maison", "corbeille", "installer", "x-apropos"];
const ORIGINE_DOCK = ["terminal", "navigateur", "github", "x-yeux"];
const DOCK_MAX = 7;
//  Les deux tuiles qui ne lancent rien : elles ouvrent un panneau de la page.
const SPECIALES = {
  "x-apropos": { id: "x-apropos", cle: "apropos", nom: "à propos", special: "apropos" },
  "x-yeux": { id: "x-yeux", cle: "yeux", nom: "yeux", special: "yeux" },
};
const trait = (cle) => `<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${DESSINS[cle] || DESSINS.appli}"/></svg>`;
const yeuxTuile = `<svg viewBox="0 0 220 60" aria-hidden="true"><path style="fill:var(--oeil)" d="${OEIL}" transform="translate(4 4)"/><path style="fill:var(--oeil)" d="${OEIL}" transform="translate(216 4) scale(-1 1)"/></svg>`;
function tuile(e) {
  const nom = LIBELLES[e.cle] || e.nom;
  let image, classe = "";
  if (e.special === "yeux") { image = yeuxTuile; classe = " yeux-tuile"; }
  else if (e.special === "apropos") { image = `<img src="tux.png" alt="">`; classe = " tux"; }
  else if (PHOTOS[e.cle]) { image = `<img src="${PHOTOS[e.cle]}" alt="">`; classe = " photo"; }
  else if (e.icone) image = `<img src="/icone/${encodeURIComponent(e.id)}?t=${encodeURIComponent(JETON)}" alt="">`;
  else image = trait(e.cle);
  return `<button class="appli" data-id="${echapper(e.id)}" data-nom="${echapper(e.nom)}" title="${echapper(e.nom)}" draggable="false">`
    + `<span class="tuile${classe}">${image}</span><span class="nom">${echapper(nom)}</span></button>`;
}

const CONNUS = new Map();                   // id -> tuile
const ORDRE = { grille: [], dock: [] };     // les identifiants, dans l'ordre
let PAGE = 0, PAR_PAGE = 8, trouvees = [], RECHERCHE = false;

function calculerOrdre() {
  CONNUS.clear();
  for (const e of (E && E.demon) || []) CONNUS.set(e.id, e);
  for (const e of Object.values(SPECIALES)) CONNUS.set(e.id, e);
  const parCle = new Map([...CONNUS.values()].map((e) => [e.cle, e.id]));
  const origine = (liste) => liste.map((k) => (k.startsWith("x-") ? k : parCle.get(k))).filter((id) => id && CONNUS.has(id));
  const sg = P && Array.isArray(P.demon_grille) ? P.demon_grille : ["*"];
  const sd = P && Array.isArray(P.demon_dock) ? P.demon_dock : ["*"];
  let dock = sd[0] === "*" ? origine(ORIGINE_DOCK) : sd.filter((id) => CONNUS.has(id));
  dock = [...new Set(dock)].slice(0, DOCK_MAX);
  let grille = sg[0] === "*" ? origine(ORIGINE_GRILLE) : sg.filter((id) => CONNUS.has(id));
  grille = [...new Set(grille)].filter((id) => !dock.includes(id));
  //  Une appli arrivée depuis (ou rendue par une mise à jour) va au bout de
  //  la grille : rien ne disparaît parce qu'il n'était pas dans la liste.
  for (const id of CONNUS.keys()) if (!grille.includes(id) && !dock.includes(id)) grille.push(id);
  ORDRE.grille = grille; ORDRE.dock = dock;
}

//  Combien de rangées tiennent dans le cadre : mesuré sur une vraie tuile,
//  pas deviné — la taille des tuiles suit la hauteur de l'écran (CSS).
function mettreEnPages() {
  const cadre = $("#grille-cadre"), g = $("#grille");
  const t = $(".appli", g);
  if (!t) { PAR_PAGE = 8; return; }
  const ecart = parseFloat(getComputedStyle(g).rowGap) || 12;
  const rangees = Math.max(1, Math.floor((cadre.clientHeight + ecart) / (t.offsetHeight + ecart)));
  PAR_PAGE = rangees * 4;
}
function dessinerPoints(n) {
  $("#points").innerHTML = Array.from({ length: n }, (_, i) =>
    `<button class="${i === PAGE ? "actif" : ""}" data-page="${i}" role="tab" aria-selected="${i === PAGE}" aria-label="Page ${i + 1}"></button>`).join("");
}
function dessinerGrille() {
  if (RECHERCHE) return;
  const g = $("#grille");
  //  Un premier passage pour mesurer, puis la vraie page.
  g.innerHTML = ORDRE.grille.slice(0, 1).map((id) => tuile(CONNUS.get(id))).join("");
  mettreEnPages();
  const pages = Math.max(1, Math.ceil(ORDRE.grille.length / PAR_PAGE));
  PAGE = Math.min(PAGE, pages - 1);
  const debut = PAGE * PAR_PAGE;
  g.innerHTML = ORDRE.grille.slice(debut, debut + PAR_PAGE).map((id) => tuile(CONNUS.get(id))).join("");
  dessinerPoints(pages);
}
function dessinerDock() {
  $("#dock").innerHTML = ORDRE.dock.map((id) => tuile(CONNUS.get(id))).join("");
}
function dessinerApplis() {
  calculerOrdre();
  if (!SECONDAIRE) { dessinerGrille(); dessinerDock(); }
}
function allerPage(i) {
  const pages = Math.max(1, Math.ceil(ORDRE.grille.length / PAR_PAGE));
  const p = Math.max(0, Math.min(pages - 1, i));
  if (p !== PAGE) { PAGE = p; dessinerGrille(); }
}
$("#points").addEventListener("click", (e) => { const b = e.target.closest("[data-page]"); if (b) allerPage(+b.dataset.page); });
let roue = 0;
$("#grille-cadre").addEventListener("wheel", (e) => {
  if (RECHERCHE || performance.now() - roue < 350) return;
  roue = performance.now();
  allerPage(PAGE + (e.deltaY > 0 ? 1 : -1));
}, { passive: true });
let minuteurTaille = null;
addEventListener("resize", () => { clearTimeout(minuteurTaille); minuteurTaille = setTimeout(() => { dessinerGrille(); poserPlaces(); }, 150); });

function ouvrirTuile(b) {
  const id = b.dataset.id;
  if (id === "x-yeux") { ouvrirPanneau(!$("#panneau").classList.contains("ouvert")); return; }
  if (id === "x-apropos") { ouvrirApropos(!$("#apropos").classList.contains("ouvert")); return; }
  lancer(id, b.dataset.nom || "");
}
document.addEventListener("click", (e) => {
  const b = e.target.closest(".appli[data-id]");
  if (!b || MODIF || GLISSE.vientDeGlisser) return;
  ouvrirTuile(b);
});

/* ════════════════ Déplacer : les tuiles, le terminal, l'heure, la date ════════════════
   ALEX : « être capable de déplacer les outils ». Un appui LONG (½ s) sur
   une tuile, ou « Modifier la disposition » dans Yeux, passe en mode
   « modifier » : les tuiles tremblent, un clic ne lance plus rien, et on
   glisse. Une tuile va d'une place à l'autre de la grille, de la grille au
   dock et retour, et sur un point pour changer de page. Le terminal,
   l'heure et la date se posent où l'on veut. Tout est gardé côté serveur.
   Des événements « pointer » seulement — souris et doigt, sans bibliothèque. */
let MODIF = false;
const GLISSE = { tuile: null, id: null, fantome: null, x0: 0, y0: 0, attente: null, vientDeGlisser: false, cible: null, survolPage: null };

function modeModifier(oui) {
  MODIF = oui && !SECONDAIRE;
  document.body.classList.toggle("modifier", MODIF);
  $("#barre-modif").hidden = !MODIF;
  if (MODIF) { ouvrirPanneau(false); ouvrirApropos(false); fermerMenuSys(); if (RECHERCHE) { $("#question").value = ""; chercher(); } }
}
$("#modif-fini").addEventListener("click", () => modeModifier(false));
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && MODIF) modeModifier(false); });

function garderOrdre() { garder({ demon_grille: ORDRE.grille, demon_dock: ORDRE.dock }); }
async function reinitialiser() {
  try {
    await api("/api/reglages", { demon_grille: ["*"], demon_dock: ["*"], demon_places: {} });
    P.demon_grille = ["*"]; P.demon_dock = ["*"]; P.demon_places = {};
    PAGE = 0; dessinerApplis(); poserPlaces();
    bulle("Disposition d'origine remise");
  } catch { bulle("Le bureau ne répond pas"); }
}
$("#modif-reinit").addEventListener("click", reinitialiser);

function nettoyerCibles() {
  $$(".cible-avant, .cible-apres").forEach((x) => x.classList.remove("cible-avant", "cible-apres"));
  $$(".dock.cible, .grille-cadre.cible, .points .cible").forEach((x) => x.classList.remove("cible"));
}
//  Où la tuile tomberait si on la lâchait ici : {liste, index} ou null.
function viser(x, y) {
  nettoyerCibles();
  const sous = document.elementFromPoint(x, y);
  if (!sous) return null;
  const point = sous.closest(".points [data-page]");
  if (point) {
    point.classList.add("cible");
    //  Rester un instant sur un point change de page, la tuile en main.
    if (!GLISSE.survolPage || GLISSE.survolPage.page !== +point.dataset.page) {
      clearTimeout(GLISSE.survolPage && GLISSE.survolPage.t);
      GLISSE.survolPage = { page: +point.dataset.page, t: setTimeout(() => allerPage(+point.dataset.page), 450) };
    }
    return { liste: "grille", index: (+point.dataset.page) * PAR_PAGE };
  }
  const t = sous.closest(".appli[data-id]");
  if (t && t.dataset.id !== GLISSE.id) {
    const r = t.getBoundingClientRect(), apres = x > r.left + r.width / 2;
    t.classList.add(apres ? "cible-apres" : "cible-avant");
    const dansDock = !!t.closest("#dock");
    const liste = dansDock ? ORDRE.dock : ORDRE.grille;
    let index = liste.indexOf(t.dataset.id) + (apres ? 1 : 0);
    return { liste: dansDock ? "dock" : "grille", index };
  }
  if (sous.closest("#dock")) { $("#dock").classList.add("cible"); return { liste: "dock", index: ORDRE.dock.length }; }
  if (sous.closest("#grille-cadre")) {
    $("#grille-cadre").classList.add("cible");
    return { liste: "grille", index: Math.min(ORDRE.grille.length, (PAGE + 1) * PAR_PAGE) };
  }
  return null;
}
function commencerGlisse(b, x, y) {
  GLISSE.tuile = b; GLISSE.id = b.dataset.id;
  const f = b.cloneNode(true);
  f.classList.add("fantome");
  f.style.left = x + "px"; f.style.top = y + "px"; f.style.width = b.offsetWidth + "px";
  document.body.appendChild(f);
  GLISSE.fantome = f;
  b.classList.add("parti");
}
function lacher(x, y) {
  const c = viser(x, y);
  nettoyerCibles();
  clearTimeout(GLISSE.survolPage && GLISSE.survolPage.t); GLISSE.survolPage = null;
  if (GLISSE.fantome) GLISSE.fantome.remove();
  const id = GLISSE.id;
  GLISSE.fantome = null; GLISSE.tuile = null; GLISSE.id = null;
  if (!c) { dessinerGrille(); dessinerDock(); return; }
  const de = ORDRE.dock.includes(id) ? "dock" : "grille";
  if (c.liste === "dock" && de !== "dock" && ORDRE.dock.length >= DOCK_MAX) {
    bulle(`Le dock est plein (${DOCK_MAX} tuiles) : sors-en une d'abord`);
    dessinerGrille(); dessinerDock(); return;
  }
  let index = c.index;
  const avant = ORDRE[de].indexOf(id);
  ORDRE[de].splice(avant, 1);
  if (de === c.liste && avant < index) index -= 1;
  ORDRE[c.liste].splice(Math.max(0, Math.min(index, ORDRE[c.liste].length)), 0, id);
  dessinerGrille(); dessinerDock();
  garderOrdre();
}

document.addEventListener("pointerdown", (e) => {
  if (e.button !== 0 || RECHERCHE) return;
  const b = e.target.closest(".appli[data-id]");
  if (b && (b.closest("#grille") || b.closest("#dock"))) {
    GLISSE.x0 = e.clientX; GLISSE.y0 = e.clientY; GLISSE.candidat = b;
    if (!MODIF) {
      clearTimeout(GLISSE.attente);
      //  L'appui long : le mode « modifier », et la tuile est déjà en main.
      GLISSE.attente = setTimeout(() => {
        modeModifier(true);
        commencerGlisse(b, GLISSE.x0, GLISSE.y0);
        GLISSE.vientDeGlisser = true;
      }, 500);
    }
    return;
  }
  const bloc = MODIF && e.target.closest("[data-deplacable]");
  if (bloc) {
    e.preventDefault();
    const base = places()[bloc.dataset.deplacable] || [0, 0];
    GLISSE.bloc = { el: bloc, x0: e.clientX, y0: e.clientY, dx: base[0] * innerWidth / 1000, dy: base[1] * innerHeight / 1000 };
    bloc.setPointerCapture && bloc.setPointerCapture(e.pointerId);
  }
});
document.addEventListener("pointermove", (e) => {
  if (GLISSE.bloc) {
    const g = GLISSE.bloc;
    g.el.style.translate = `${g.dx + e.clientX - g.x0}px ${g.dy + e.clientY - g.y0}px`;
    return;
  }
  if (GLISSE.fantome) {
    GLISSE.fantome.style.left = e.clientX + "px"; GLISSE.fantome.style.top = e.clientY + "px";
    viser(e.clientX, e.clientY);
    return;
  }
  if (GLISSE.candidat && Math.hypot(e.clientX - GLISSE.x0, e.clientY - GLISSE.y0) > 8) {
    clearTimeout(GLISSE.attente);
    if (MODIF) { commencerGlisse(GLISSE.candidat, e.clientX, e.clientY); GLISSE.vientDeGlisser = true; }
    GLISSE.candidat = null;
  }
});
document.addEventListener("pointerup", (e) => {
  clearTimeout(GLISSE.attente);
  GLISSE.candidat = null;
  if (GLISSE.bloc) {
    const g = GLISSE.bloc, cle = g.el.dataset.deplacable;
    GLISSE.bloc = null;
    const nouvelles = { ...places(), [cle]: [Math.round((g.dx + e.clientX - g.x0) * 1000 / innerWidth), Math.round((g.dy + e.clientY - g.y0) * 1000 / innerHeight)] };
    if (P) P.demon_places = nouvelles;
    poserPlaces();
    garder({ demon_places: nouvelles });
    return;
  }
  if (GLISSE.fantome) lacher(e.clientX, e.clientY);
  //  Le clic qui suit le lâcher ne doit pas lancer l'appli.
  if (GLISSE.vientDeGlisser) setTimeout(() => { GLISSE.vientDeGlisser = false; }, 0);
});
document.addEventListener("pointercancel", () => {
  clearTimeout(GLISSE.attente); GLISSE.candidat = null; GLISSE.bloc = null;
  if (GLISSE.fantome) { GLISSE.fantome.remove(); GLISSE.fantome = null; GLISSE.id = null; nettoyerCibles(); dessinerGrille(); dessinerDock(); }
});
//  Pas de menu contextuel sur l'appui long d'un doigt.
document.addEventListener("contextmenu", (e) => { if (e.target.closest(".appli") || MODIF) e.preventDefault(); });

//  Le terminal, l'heure, la date : décalés de leur place, en millièmes de
//  l'écran (réglage « demon_places »), et jamais hors de l'écran.
const places = () => (P && P.demon_places && typeof P.demon_places === "object" ? P.demon_places : {});
function poserPlaces() {
  for (const el of $$("[data-deplacable]")) {
    const xy = places()[el.dataset.deplacable];
    el.style.translate = "";
    if (!xy) continue;
    let dx = xy[0] * innerWidth / 1000, dy = xy[1] * innerHeight / 1000;
    const r = el.getBoundingClientRect();
    dx = Math.max(-r.left, Math.min(innerWidth - r.right, dx));
    dy = Math.max(-r.top, Math.min(innerHeight - r.bottom, dy));
    el.style.translate = `${dx}px ${dy}px`;
  }
}

/* ════════════════ La recherche : « $ chercher… ou ? pc » ════════════════
   Ce qu'on tape filtre TOUTES les applis installées (la liste du labo,
   /api/outils, chargée au premier caractère) ; Entrée ouvre la première.
   « ? question » la pose à ti-lex IA, quand il est là. Les résultats
   prennent la place de la grille, sur une seule page. */
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
async function chercher() {
  const q = $("#question").value.trim();
  if (!q || q.startsWith("?")) { trouvees = []; RECHERCHE = false; dessinerGrille(); return; }
  let liste = [];
  try { liste = await toutesLesApplis(); } catch { bulle("Le bureau ne répond pas"); return; }
  if ($("#question").value.trim() !== q) return;                         // on a retapé entre-temps
  if (MODIF) modeModifier(false);
  const m = sansAccents(q);
  trouvees = liste.filter((e) => sansAccents(e.nom).includes(m))
    .sort((a, b) => sansAccents(a.nom).indexOf(m) - sansAccents(b.nom).indexOf(m)).slice(0, Math.max(4, PAR_PAGE));
  RECHERCHE = true;
  $("#grille").innerHTML = trouvees.length ? trouvees.map(tuile).join("")
    : `<p class="vide">aucune appli ne s'appelle « ${echapper(q)} »</p>`;
  dessinerPoints(1);
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

/* ════════════════ Réseau, son, arrêt : ce que portait la barre du haut ════════════════
   La nomade n'a plus la barre XFCE du haut. Ses trois services utiles
   reviennent ici, par les routes que le serveur a déjà ou qu'il FERME
   lui-même : /api/reseau (nmcli, lecture seule), /api/action « reseau »
   (les Paramètres, section Wi-Fi), /api/son, /api/session (lexos-session :
   verrouiller, déconnexion, redémarrer, éteindre). La page n'envoie jamais
   de commande, seulement un nom pris dans une liste. */
let RESEAU = { etat: "inconnu" }, menuOuvert = "";
function fermerMenuSys() {
  $("#menu-sys").hidden = true; menuOuvert = "";
  $$(".sys").forEach((b) => b.setAttribute("aria-expanded", "false"));
}
function placerMenu(bouton) {
  const r = bouton.getBoundingClientRect(), m = $("#menu-sys");
  m.style.top = Math.min(innerHeight - 20 - m.offsetHeight, r.bottom + 8) + "px";
  m.style.left = Math.max(12, Math.min(innerWidth - m.offsetWidth - 12, r.right - m.offsetWidth)) + "px";
}
async function majReseau() {
  if (document.hidden || SECONDAIRE) return;
  try { RESEAU = await api("/api/reseau"); } catch { RESEAU = { etat: "inconnu" }; }
  const b = $("#sys-reseau");
  b.classList.toggle("coupe", RESEAU.etat === "deconnecte");
  b.title = texteReseau();
  if (menuOuvert === "reseau") ouvrirMenuSys("reseau", true);
}
function texteReseau() {
  if (RESEAU.etat === "deconnecte") return "Pas de réseau";
  if (RESEAU.etat !== "connecte") return "Réseau : état inconnu";
  if (RESEAU.type === "ethernet") return `Câble : ${RESEAU.nom || "connecté"}`;
  return `Wi-Fi : ${RESEAU.nom || "connecté"}${RESEAU.signal >= 0 ? ` (${RESEAU.signal} %)` : ""}`;
}
async function ouvrirMenuSys(quoi, rafraichir = false) {
  const m = $("#menu-sys"), bouton = $(`#sys-${quoi}`);
  if (!rafraichir && menuOuvert === quoi) { fermerMenuSys(); return; }
  menuOuvert = quoi;
  $$(".sys").forEach((b) => b.setAttribute("aria-expanded", String(b === bouton)));
  if (quoi === "reseau") {
    m.innerHTML = `<p><b>Réseau</b></p><p class="etat">${echapper(texteReseau())}</p>`
      + `<button data-faire="reglages-reseau">Réglages du réseau et du Wi-Fi…</button>`;
  } else if (quoi === "son") {
    let s = { volume: -1, muet: false };
    try { s = await api("/api/son"); } catch {}
    m.innerHTML = s.volume < 0 ? `<p><b>Son</b></p><p class="etat">Pas de réglage du son disponible ici</p>`
      : `<p><b>Son</b> · <span id="son-pct">${s.volume}</span> %</p>`
        + `<input type="range" min="0" max="100" step="5" value="${s.volume}" id="son-niveau" aria-label="Volume">`
        + `<button data-faire="muet">${s.muet ? "Rétablir le son" : "Couper le son"}</button>`;
  } else {
    m.innerHTML = `<p><b>Session</b></p>`
      + `<button data-geste="verrouiller">Verrouiller</button>`
      + `<button data-geste="deconnexion">Se déconnecter</button>`
      + `<button data-geste="redemarrer">Redémarrer</button>`
      + `<button data-geste="eteindre">Éteindre</button>`;
  }
  m.hidden = false;
  placerMenu(bouton);
}
$("#systeme").addEventListener("click", (e) => {
  const b = e.target.closest("[data-sys]");
  if (b && !MODIF) ouvrirMenuSys(b.dataset.sys);
});
document.addEventListener("pointerdown", (e) => {
  if (menuOuvert && !e.target.closest("#menu-sys") && !e.target.closest("#systeme")) fermerMenuSys();
});
document.addEventListener("keydown", (e) => { if (e.key === "Escape") fermerMenuSys(); });
const NOMS_GESTES = { eteindre: "Éteindre", redemarrer: "Redémarrer" };
$("#menu-sys").addEventListener("click", async (e) => {
  const b = e.target.closest("button"); if (!b) return;
  if (b.dataset.faire === "reglages-reseau") {
    fermerMenuSys();
    try { const r = await api("/api/action", { nom: "reseau" }); if (!r.ok) bulle("Les réglages du réseau ne sont pas installés"); } catch { bulle("Le bureau ne répond pas"); }
    return;
  }
  if (b.dataset.faire === "muet") {
    try { await api("/api/son", { muet: "toggle" }); ouvrirMenuSys("son", true); } catch { bulle("Le bureau ne répond pas"); }
    return;
  }
  const g = b.dataset.geste; if (!g) return;
  //  Éteindre et redémarrer demandent un DEUXIÈME clic, comme dans Mes outils.
  if ((g === "eteindre" || g === "redemarrer") && !b.classList.contains("arme")) {
    $$("#menu-sys .arme").forEach((x) => { x.classList.remove("arme"); x.textContent = NOMS_GESTES[x.dataset.geste]; });
    b.classList.add("arme"); b.textContent = `${NOMS_GESTES[g]} — clique encore`;
    setTimeout(() => { if (b.isConnected) { b.classList.remove("arme"); b.textContent = NOMS_GESTES[g]; } }, 3000);
    return;
  }
  fermerMenuSys();
  try { const r = await api("/api/session", { geste: g }); if (!r.ok) bulle("Ce geste n'est pas disponible ici"); } catch { bulle("Le bureau ne répond pas"); }
});
let minuteurSon = null;
$("#menu-sys").addEventListener("input", (e) => {
  if (e.target.id !== "son-niveau") return;
  const v = +e.target.value;
  $("#son-pct").textContent = v;
  clearTimeout(minuteurSon);
  minuteurSon = setTimeout(() => api("/api/son", { volume: v }).catch(() => {}), 120);
});

/* ════════════════ « À propos » : lexfetch, sans terminal ════════════════ */
function ouvrirApropos(ouvert) {
  if (ouvert) {
    ouvrirPanneau(false);
    const s = (E && E.systeme) || {};
    const lignes = [
      ["os", `${s.nom || "LexOS"}${s.version ? " " + s.version : ""}${s.saveur ? " (" + s.saveur + ")" : ""}`],
      ["base", "Debian trixie"], ["noyau", s.noyau], ["cpu", s.processeur], ["mémoire", s.memoire],
      ["allumé", s.allume], ["bureau", "LexOS démon"], ["créateur", "Alex Marceau Prevost"],
    ].filter(([, v]) => v);
    $("#apropos-corps").innerHTML = lignes.map(([k, v]) =>
      `<p><span class="cle">${echapper(k)}</span>${echapper(v)}</p>`).join("");
  }
  $("#apropos").classList.toggle("ouvert", ouvert);
  $("#apropos").setAttribute("aria-hidden", String(!ouvert));
}
$("#apropos-fermer").addEventListener("click", () => ouvrirApropos(false));
document.addEventListener("keydown", (e) => { if (e.key === "Escape") ouvrirApropos(false); });

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
$("#vers-modif").addEventListener("click", () => modeModifier(true));
$("#reinit-disposition").addEventListener("click", () => { ouvrirPanneau(false); reinitialiser(); });
//  🎛️ Mes outils : la barre ne descend plus toute seule du haut de l'écran
//  dans la nomade (réglage « outils »). Elle reste à un bouton : changer le
//  titre de la page est le signe que fenetre.py écoute (« outils-… »).
$("#vers-outils").addEventListener("click", () => { ouvrirPanneau(false); document.title = "outils-" + Date.now(); });
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
  //  Pendant qu'une tuile ou un bloc est en main, on ne redessine rien sous
  //  la souris : la prochaine vérification le fera.
  if (GLISSE.fantome || GLISSE.bloc) { VERSION = ""; return; }
  dessinerApplis();
  poserPlaces();
}
async function verifier() {
  try {
    const { v } = await api("/api/version");
    if (v !== VERSION) { VERSION = v; await charger(); }
  } catch {}
}

/* ════════════════ L'ouverture ════════════════
   1. LA VIDÉO : le démon de flammes « TI-LEXOS », le zoom dans ses yeux,
      et ses deux amandes rouges qui clignent dans le noir (13 s, muette,
      demarrage-flammes.webm, VP9 960 × 540, 2 Mo). Quand elle finit : un
      éclat là où étaient ses yeux, et le bureau.
   2. SINON, les yeux en CSS : noir → seuls les yeux de la page s'allument
      et clignent (≈ 2 s) → éclat → le bureau. C'est le cas en mode allégé
      (pas de GPU : décoder de la vidéo au processeur pendant que le bureau
      se charge, non), sur un écran secondaire (une seule vidéo à la fois),
      et si la vidéo ne part pas dans les 2,5 s (fichier absent, codec).
   Un clic ou une touche abrège les deux. Rien du tout si « les yeux
   s'ouvrent au démarrage » est éteint, ou si le système demande moins
   d'animations. */
function ouverture() {
  const intro = $("#intro"), corps = document.body, eclat = $("#eclat");
  let fini = false;
  const minuteurs = [];
  const plus_tard = (f, ms) => minuteurs.push(setTimeout(f, ms));
  const finir = () => {
    if (fini) return; fini = true;
    minuteurs.forEach(clearTimeout);
    const v = $("video", intro); if (v) v.pause();
    intro.classList.add("parti");
    setTimeout(() => { intro.remove(); corps.classList.remove("en-intro", "eveil"); }, 650);
  };
  if (CALME || !P || !P.demon_intro) { finir(); return; }
  addEventListener("keydown", finir, { once: true });
  intro.addEventListener("click", finir, { once: true });

  const yeuxCss = () => {
    if (fini) return;
    const r = $("#yeux").getBoundingClientRect();
    eclat.style.left = (r.left + r.width / 2) + "px"; eclat.style.top = (r.top + r.height / 2) + "px";
    corps.classList.add("en-intro", "eveil");
    plus_tard(() => intro.classList.add("eclate"), 2000);
    plus_tard(finir, 2700);
  };
  if (LEGER || SECONDAIRE) { yeuxCss(); return; }

  //  Pendant la vidéo, les yeux de la page restent SOUS le voile : ce sont
  //  ceux du démon qu'on regarde.
  corps.classList.remove("en-intro");
  const v = document.createElement("video");
  v.muted = true; v.playsInline = true; v.preload = "auto"; v.autoplay = true;
  v.src = "demarrage-flammes.webm";
  let partie = false;
  const repli = () => { if (partie || fini) return; partie = true; v.remove(); yeuxCss(); };
  v.addEventListener("playing", () => { partie = true; }, { once: true });
  v.addEventListener("error", repli, { once: true });
  v.addEventListener("ended", () => {
    //  La vidéo finit sur les yeux du démon, au centre, un peu au-dessus de
    //  la mi-hauteur : l'éclat part de là.
    eclat.style.left = "50%"; eclat.style.top = "42%";
    intro.classList.add("eclate");
    plus_tard(finir, 700);
  }, { once: true });
  intro.appendChild(v);
  const essai = v.play(); if (essai && essai.catch) essai.catch(repli);
  plus_tard(repli, 2500);           // rien ne joue au bout de 2,5 s : les yeux en CSS
  plus_tard(finir, 16000);          // et jamais plus de 16 s, quoi qu'il arrive
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
  majReseau();
  setInterval(majReseau, 15000);
})();
