/* LexOS Bureau — la page du bureau.
   Lit /api/etat (réglages + sections d'icônes), dessine le fond animé du
   Moteur (fonds.js), et suit /api/version : un réglage changé dans les
   Paramètres, ou un fichier posé dans le dossier Bureau, s'affichent tout
   seuls en deux secondes, sans relancer quoi que ce soit. */
"use strict";

const $ = (s, el = document) => el.querySelector(s);
const PARAMS = new URLSearchParams(location.search);
const JETON = PARAMS.get("t") || "";
const SECONDAIRE = PARAMS.get("ecran") === "autre";
const echapper = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

let P = null;            // les réglages (reglages.py)
let PRENOM = "";
let VERSION = "";

async function api(chemin, corps) {
  const r = await fetch(chemin, corps === undefined
    ? { headers: { "X-Jeton": JETON }, cache: "no-store" }
    : { method: "POST", headers: { "X-Jeton": JETON, "Content-Type": "application/json" }, body: JSON.stringify(corps) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

/* ════════════════ Marges : la barre du haut et le dock ════════════════ */
for (const cote of ["haut", "bas", "gauche", "droite"]) {
  const v = parseInt(PARAMS.get(cote) || "0", 10);
  document.documentElement.style.setProperty("--" + cote, (Number.isFinite(v) ? Math.max(0, Math.min(v, 400)) : 0) + "px");
}
if (SECONDAIRE) document.body.classList.add("secondaire");

/* ════════════════ Thème : couleur + police (comme fond.js du Moteur) ════════════════ */
const pileDe = (nom) => nom === "Système" ? "system-ui, -apple-system, 'Segoe UI', Ubuntu, sans-serif"
  : nom === "Serif classique" ? "Georgia, 'DejaVu Serif', 'Times New Roman', serif"
  : `'LX ${nom}', system-ui, sans-serif`;

function poserCouleur(hex) {
  const r = document.documentElement.style;
  THEME.hex = hex; THEME.rgb = hexVersRgb(hex).join(",");
  THEME.clair = melanger(hex, "#ffffff", .35); THEME.fonce = melanger(hex, "#000000", .22);
  r.setProperty("--orange", hex); r.setProperty("--orange-2", THEME.clair); r.setProperty("--orange-fonce", THEME.fonce);
  r.setProperty("--acc-rgb", THEME.rgb);
  r.setProperty("--sur-accent", luminance(hex) > .45 ? "#0a0a0a" : "#ffffff");
}
let teinteArc = 20, minuteurArc = null;
function appliquerTheme() {
  clearInterval(minuteurArc);
  if (P.accent === "arc-en-ciel") minuteurArc = setInterval(() => { teinteArc = (teinteArc + 1.2) % 360; poserCouleur(hslVersHex(teinteArc, 95, 58)); }, 60);
  else poserCouleur(/^#[0-9a-f]{6}$/i.test(P.accent) ? P.accent : "#ff7a18");
  document.documentElement.style.setProperty("--police", pileDe(P.police));
  $("#bureau").style.zoom = P.taille / 100;
}

/* ════════════════ Le fond animé (moteur d'animation du Moteur) ════════════════ */
const toile = $("#fond"), ctx = toile.getContext("2d");
const PLEIN = { L: 0, H: 0, etat: null, anim: "constellation" };
const SOURIS = { x: -9999, y: -9999 };
const calme = matchMedia("(prefers-reduced-motion: reduce)").matches;

function preparerPlein() {
  const dpr = Math.min(devicePixelRatio || 1, 2);
  toile.width = innerWidth * dpr; toile.height = innerHeight * dpr;
  toile.style.width = innerWidth + "px"; toile.style.height = innerHeight + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  PLEIN.L = innerWidth; PLEIN.H = innerHeight;
  PLEIN.anim = FONDS[P.anim] ? P.anim : "constellation";
  ctx.clearRect(0, 0, PLEIN.L, PLEIN.H);
  PLEIN.etat = FONDS[PLEIN.anim].init(PLEIN.L, PLEIN.H, P.densite / 100);
}
addEventListener("resize", () => P && preparerPlein());
addEventListener("mousemove", (e) => {
  SOURIS.x = e.clientX; SOURIS.y = e.clientY;
  const g = $("#curseur"); g.style.left = e.clientX + "px"; g.style.top = e.clientY + "px";
});
document.addEventListener("mouseleave", () => { SOURIS.x = SOURIS.y = -9999; });

let avant = performance.now();
function boucle(t) {
  const dt = Math.min(4, (t - avant) / 16.67) * ((P ? P.vitesse : 100) / 100); avant = t;
  //  Une fenêtre de bureau cachée par une appli plein écran reste « visible »
  //  pour Chromium : document.hidden ne suffit pas toujours, mais il coupe
  //  déjà l'animation quand l'écran est verrouillé ou la session en veille.
  if (P && !document.hidden) FONDS[PLEIN.anim].dessine(ctx, PLEIN.etat, PLEIN.L, PLEIN.H, dt, SOURIS);
  if (!calme) requestAnimationFrame(boucle);
}

function appliquerDecor(reinit) {
  const img = $("#fond-image");
  img.style.backgroundImage = P.image ? `url("/fond?t=${encodeURIComponent(JETON)}&v=${encodeURIComponent(VERSION)}")` : "none";
  img.style.filter = `blur(${P.flou}px)`;
  img.style.inset = P.flou ? `-${P.flou * 2}px` : "0";
  img.classList.toggle("zoom", P.zoom && !!P.image);
  $("#fond-voile").style.opacity = P.image ? P.voile / 100 : 0;
  toile.style.opacity = P.anim === "aucun" ? 0 : P.image ? .85 : 1;
  $("#orbes").style.display = P.orbes ? "" : "none";
  $(".grille").style.display = P.grille ? "" : "none";
  $("#curseur").style.display = P.curseur ? "" : "none";
  if (reinit) preparerPlein();
}

/* ════════════════ Les icônes ════════════════ */
function tuile(el, k) {
  let dedans;
  if (el.icone) {
    dedans = `<img ${el.plein ? 'class="vignette"' : ""} src="/icone/${encodeURIComponent(el.id)}?t=${encodeURIComponent(JETON)}" alt="" loading="lazy">`;
  } else {
    dedans = echapper(el.emoji || "🚀");
  }
  const lanceur = el.id.startsWith("t-") ? " lanceur" : "";
  return `<button class="icone${lanceur}" data-id="${echapper(el.id)}" data-emoji="${echapper(el.emoji || "🚀")}" title="${echapper(el.nom)}" style="animation-delay:${Math.min(k, 40) * 30}ms"><span>${dedans}</span><b>${echapper(el.nom)}</b></button>`;
}
function dessinerIcones(sections) {
  let k = 0, html = "";
  for (const s of sections) {
    if (!s.elements.length) continue;
    html += `<h5 class="groupe">${echapper(s.titre)}</h5>` + s.elements.map((e) => tuile(e, k++)).join("");
  }
  $("#icones").innerHTML = html;
  //  Une image qui ne se charge pas (icône introuvable) retombe sur un émoji
  //  plutôt que de laisser un carré vide.
  $("#icones").querySelectorAll("img").forEach((i) => i.addEventListener("error", () => {
    i.replaceWith(i.closest(".icone")?.dataset.emoji || "🚀");
  }, { once: true }));
}

$("#icones").addEventListener("click", async (e) => {
  const b = e.target.closest(".icone"); if (!b) return;
  b.classList.remove("rebond"); void b.offsetWidth; b.classList.add("rebond");
  try {
    const r = await api("/api/lancer", { id: b.dataset.id });
    if (!r.ok) bulle("Impossible d'ouvrir « " + b.title + " »");
  } catch { bulle("Le bureau ne répond pas"); }
});

/* ════════════════ L'accueil : horloge, salut, « Demande à ti-lex IA » ════════════════ */
function majHorloge() {
  const d = new Date();
  $("#grande-heure").textContent = d.toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
  const h = d.getHours();
  const salut = h < 5 ? "Bonne nuit" : h < 12 ? "Bon matin" : h < 18 ? "Bon après-midi" : "Bonsoir";
  $("#salut").textContent = `${salut}${PRENOM ? " " + PRENOM : ""} 👋 · ${d.toLocaleDateString("fr-CA", { weekday: "long", day: "numeric", month: "long" })}`;
}
setInterval(majHorloge, 10000);

$("#demande").addEventListener("submit", async (e) => {
  e.preventDefault();
  const q = $("#question").value.trim(); if (!q) return;
  $("#question").value = "";
  try {
    const r = await api("/api/demander", { q });
    bulle(r.ok ? "ti-lex IA s'ouvre avec ta question…" : "ti-lex IA n'est pas installé");
  } catch { bulle("Le bureau ne répond pas"); }
});

/* ════════════════ Clic droit ════════════════ */
const menu = $("#menu");
document.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  if (SECONDAIRE || e.target.closest(".demande")) return;
  menu.hidden = false;
  const L = menu.offsetWidth, H = menu.offsetHeight;
  menu.style.left = Math.min(e.clientX, innerWidth - L - 8) + "px";
  menu.style.top = Math.min(e.clientY, innerHeight - H - 8) + "px";
});
document.addEventListener("click", (e) => { if (!e.target.closest("#menu")) menu.hidden = true; });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") menu.hidden = true; });
menu.addEventListener("click", async (e) => {
  const b = e.target.closest("[data-action]"); if (!b) return;
  menu.hidden = true;
  try { await api("/api/action", { nom: b.dataset.action }); verifier(); } catch {}
});

let minuteurBulle = null;
function bulle(texte) {
  const b = $("#bulle");
  b.textContent = texte; b.hidden = false;
  clearTimeout(minuteurBulle);
  minuteurBulle = setTimeout(() => { b.hidden = true; }, 3500);
}

/* ════════════════ Charger, puis suivre les changements ════════════════ */
async function charger() {
  const e = await api("/api/etat");
  const avantP = P;
  P = e.reglages; PRENOM = e.prenom || "";
  appliquerTheme();
  appliquerDecor(!avantP || avantP.anim !== P.anim || avantP.densite !== P.densite);
  if (!SECONDAIRE) {
    dessinerIcones(e.sections);
    $("#accueil").classList.toggle("cache", !P.horloge);
    $("#demande").hidden = !e.tilex;
    majHorloge();
  }
}
async function verifier() {
  try {
    const { v } = await api("/api/version");
    if (v !== VERSION) { VERSION = v; await charger(); }
  } catch {}
}

(async () => {
  try {
    VERSION = (await api("/api/version")).v;
    await charger();
  } catch {
    //  Sans le serveur, le bureau reste un fond noir propre plutôt qu'une
    //  erreur : lexos-bureau relance xfdesktop si le moteur est tombé.
    P = { accent: "#ff7a18", police: "Space Grotesk", taille: 100, anim: "constellation", image: "", voile: 35, flou: 0,
          vitesse: 100, densite: 100, orbes: true, grille: true, curseur: true, zoom: true };
    appliquerTheme(); appliquerDecor(true);
  }
  requestAnimationFrame(boucle);
  setInterval(verifier, 2000);
})();
