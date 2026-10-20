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
const entier = (nom) => { const v = parseInt(PARAMS.get(nom) || "0", 10); return Number.isFinite(v) ? v : 0; };
const ECRAN = { x: entier("gx"), y: entier("gy"), l: entier("gl"), h: entier("gh") };
const MARGES_QT = { haut: entier("haut"), bas: entier("bas"), gauche: entier("gauche"), droite: entier("droite") };
/*  Ce que Qt a vu au démarrage, OU ce que _NET_WORKAREA dit maintenant
    (serveur.py, ZoneTravail) — le plus grand des deux. Sur le PC d'Alex,
    le bureau démarrait avant la barre du haut : Qt voyait l'écran entier,
    et la première rangée d'icônes passait SOUS la barre. */
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
/*  Le dock Plank ne réserve pas sa place (il se cache quand une fenêtre le
    touche) : sur le bureau vide, il est PAR-DESSUS la page. Les colonnes
    d'icônes s'en écartent — « lexos dock droite », et la colonne de droite
    ne passe plus dessous. */
function poserDock(dock) {
  const r = $("#bureau").style;
  const place = dock && dock.taille ? Math.min(200, dock.taille + 22) + "px" : "0px";
  r.setProperty("--dock-g", dock?.cote === "left" ? place : "0px");
  r.setProperty("--dock-d", dock?.cote === "right" ? place : "0px");
  r.setProperty("--dock-h", dock?.cote === "top" ? place : "0px");
  r.setProperty("--dock-b", dock?.cote === "bottom" ? place : "0px");
}
poserMarges(null);
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
/*  ═══ DÉPLACER LES ICÔNES N'IMPORTE OÙ ═══
    ALEX : « déplacer les applications dans tout l'écran ». Une icône jamais
    déplacée reste dans la grille par sections ; glissée, elle se pose là
    où on la lâche — calée sur une grille invisible de 100 x 100, comme
    xfdesktop, pour que le bureau reste rangé — et sa place est gardée dans
    bureau.json (« positions »). Clic droit → « Remettre les icônes en
    ordre » les renvoie toutes dans la grille. */
let POSITIONS = {};
const PAS_X = 100, PAS_Y = 100, MARGE = 18;
const zoom = () => (P ? P.taille / 100 : 1);

function dessinerIcones(sections) {
  //  Deux colonnes, comme la nouvelle version du Moteur : « gauche » (ti-lex
  //  IA, puis Mon bureau) et « droite » (LexOS), collées aux bords.
  let k = 0, libres = "";
  const cotes = { gauche: "", droite: "" };
  for (const s of sections) {
    const restants = s.elements.filter((e) => !POSITIONS[e.id]);
    const cote = s.cote === "droite" ? "droite" : "gauche";
    if (restants.length) cotes[cote] += `<h5 class="groupe">${echapper(s.titre)}</h5><div class="grille-ic">` + restants.map((e) => tuile(e, k++)).join("") + "</div>";
    for (const e of s.elements) {
      const xy = POSITIONS[e.id];
      if (xy) libres += tuile(e, k++).replace('<button class="icone', `<button style="left:${xy[0]}px;top:${xy[1]}px" class="libre icone`);
    }
  }
  $("#cote-gauche").innerHTML = cotes.gauche;
  $("#cote-droite").innerHTML = cotes.droite;
  $("#libres").innerHTML = libres;
  setTimeout(majFondus, 60);
  //  Une image qui ne se charge pas (icône introuvable) retombe sur un émoji
  //  plutôt que de laisser un carré vide.
  document.querySelectorAll("#icones img, #libres img").forEach((i) => i.addEventListener("error", () => {
    i.replaceWith(i.closest(".icone")?.dataset.emoji || "🚀");
  }, { once: true }));
}

const GLISSE = { el: null, x0: 0, y0: 0, dx: 0, dy: 0, bouge: false, empecheClic: false, enCours: false };
function surIcones(e) { return e.target.closest("#icones .icone, #libres .icone"); }
document.addEventListener("pointerdown", (e) => {
  const b = surIcones(e);
  if (!b || e.button !== 0 || SECONDAIRE) return;
  const r = b.getBoundingClientRect();
  Object.assign(GLISSE, { el: b, x0: e.clientX, y0: e.clientY, dx: e.clientX - r.left, dy: e.clientY - r.top, bouge: false });
});
document.addEventListener("pointermove", (e) => {
  const g = GLISSE;
  if (!g.el) return;
  if (!g.bouge) {
    if (Math.hypot(e.clientX - g.x0, e.clientY - g.y0) < 6) return;   // un clic qui tremble n'est pas un glisser
    g.bouge = true; g.enCours = true;
    //  Sortie de la grille : l'icône passe dans la couche libre, à l'endroit exact où elle est.
    const r = g.el.getBoundingClientRect();
    $("#libres").appendChild(g.el);
    g.el.classList.add("libre", "glisse");
    placer(g.el, r.left, r.top);
  }
  placer(g.el, e.clientX - g.dx, e.clientY - g.dy);
});
document.addEventListener("pointerup", async () => {
  const g = GLISSE;
  if (!g.el) return;
  const el = g.el; g.el = null;
  if (!g.bouge) return;
  g.empecheClic = true; setTimeout(() => { g.empecheClic = false; }, 50);
  el.classList.remove("glisse");
  //  Calée sur la grille invisible, et gardée dans l'écran.
  const z = zoom(), boite = $("#bureau").getBoundingClientRect();
  const maxX = Math.max(MARGE, boite.width / z - 96), maxY = Math.max(MARGE, boite.height / z - 100);
  let x = parseFloat(el.style.left), y = parseFloat(el.style.top);
  x = Math.min(maxX, Math.max(MARGE, MARGE + Math.round((x - MARGE) / PAS_X) * PAS_X));
  y = Math.min(maxY, Math.max(MARGE, MARGE + Math.round((y - MARGE) / PAS_Y) * PAS_Y));
  el.style.left = x + "px"; el.style.top = y + "px";
  POSITIONS = { ...POSITIONS, [el.dataset.id]: [Math.round(x), Math.round(y)] };
  try { await api("/api/reglages", { positions: POSITIONS }); } catch { bulle("La place de l'icône n'a pas pu être gardée"); }
  g.enCours = false;
});
function placer(el, clientX, clientY) {
  //  Coordonnées de l'écran -> pixels du bureau, qui peut être zoomé
  //  (Paramètres → taille) : sans la division, l'icône fuirait la souris.
  const z = zoom(), boite = $("#bureau").getBoundingClientRect();
  el.style.left = (clientX - boite.left) / z + "px";
  el.style.top = (clientY - boite.top) / z + "px";
}

/*  Un clic ouvre. Un DOUBLE-clic (le réflexe d'XFCE) ne doit pas ouvrir
    deux fois : on ignore un deuxième clic sur la même icône dans la
    seconde qui suit — et le serveur fait la même garde de son côté. */
const DERNIERS = new Map();
document.addEventListener("click", async (e) => {
  const b = surIcones(e); if (!b) return;
  if (GLISSE.empecheClic) return;          // on vient de la déplacer, pas de l'ouvrir
  const maintenant = performance.now();
  if (maintenant - (DERNIERS.get(b.dataset.id) || -1e9) < 1200) return;
  DERNIERS.set(b.dataset.id, maintenant);
  b.classList.remove("rebond"); void b.offsetWidth; b.classList.add("rebond");
  lancerIcone(b.dataset.id, b.title);
});
async function lancerIcone(id, titre = "") {
  try {
    const r = await api("/api/lancer", { id });
    if (r.raison === "non-approuve") {
      bulle("« " + titre + " » n'est pas encore approuvé : Fichiers s'ouvre — double-clique-le là pour l'approuver");
    } else if (r.raison === "lien-refuse") {
      bulle("Ce raccourci ne mène pas à une page web");
    } else if (!r.ok) {
      bulle(titre ? "Impossible d'ouvrir « " + titre + " »" : "Impossible d'ouvrir ça");
    }
  } catch { bulle("Le bureau ne répond pas"); }
}

/*  Le fondu du bas part quand on est rendu au bout de la colonne. */
function majFondus() { document.querySelectorAll(".cote").forEach((c) => c.classList.toggle("tout-voit", c.scrollTop + c.clientHeight >= c.scrollHeight - 4)); }
document.querySelectorAll(".cote").forEach((c) => c.addEventListener("scroll", majFondus, { passive: true }));
addEventListener("resize", majFondus);

/*  Rien ne se dépose sur le bureau : il n'est pas un dossier. Sans ça, le
    navigateur intégré OUVRAIT le fichier ou le lien glissé à la place du
    bureau (la fenêtre Qt le refuse aussi, voir fenetre.py). */
for (const t of ["dragover", "drop", "dragstart"]) document.addEventListener(t, (e) => e.preventDefault());
//  « dragstart » aussi : une image dans une icône lançait le glisser natif
//  du navigateur, qui annule le nôtre (pointercancel) au premier pixel.

/* ════════════════ L'accueil : horloge, salut, « Demande à ti-lex IA » ════════════════ */
function majHorloge() {
  const d = new Date();
  $("#grande-heure").textContent = d.toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
  const h = d.getHours();
  const salut = h < 5 ? "Bonne nuit" : h < 12 ? "Bon matin" : h < 18 ? "Bon après-midi" : "Bonsoir";
  $("#salut").textContent = `${salut}${PRENOM ? " " + PRENOM : ""} 👋 · ${d.toLocaleDateString("fr-CA", { weekday: "long", day: "numeric", month: "long" })}`;
}
setInterval(majHorloge, 10000);

async function demander(vers) {
  const q = $("#question").value.trim();
  if (!q) {
    if (vers === "abo") { lancerIcone("t-abo"); return; }   // 🌐 sans question : la fenêtre « Mon abonnement »
    return;
  }
  $("#question").value = "";
  try {
    const r = await api("/api/demander", { q, vers });
    bulle(!r.ok ? "ti-lex IA n'est pas installé"
      : vers === "abo" ? "🌐 Mon abonnement s'ouvre avec ta question…" : "ti-lex IA s'ouvre avec ta question…");
  } catch { bulle("Le bureau ne répond pas"); }
}
$("#demande").addEventListener("submit", (e) => { e.preventDefault(); demander("chat"); });
$("#vers-abo").addEventListener("click", () => demander("abo"));

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
  const l = e.target.closest("[data-local]");
  if (l) {
    menu.hidden = true;
    if (l.dataset.local === "logo") changerLogo(true);
    if (l.dataset.local === "code") {
      const actif = !P.code;
      try { await api("/api/reglages", { code: actif }); bulle(actif ? "⌨️ Le code qui s'écrit : activé" : "⌨️ Le code qui s'écrit : désactivé"); verifier(); } catch {}
    }
    return;
  }
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

/* ════════════════ Le grand logo au centre (nouvelle version du Moteur) ════════════════
   Bureau.js du Moteur, « Grand logo au centre du bureau » : la bannière
   LexOS Nomad ou le logo rond ; un clic passe au suivant, et il penche un
   peu vers la souris. Le choix est gardé dans bureau.json (« embleme ») :
   le navigateur de la page n'a pas de mémoire d'une session à l'autre. */
const LOGOS = { nomad: "lexos-nomad.png", rond: "logo.png" };
const ORDRE_LOGOS = ["nomad", "rond"];
const emb = $("#embleme"), embBtn = $("#embleme-btn"), embImg = $("#embleme-img");
let logoAffiche = "";
function appliquerEmbleme() {
  const choix = P && LOGOS[P.embleme] ? P.embleme : (P && P.embleme === "aucun" ? "aucun" : "nomad");
  emb.hidden = choix === "aucun";
  $("#bureau").classList.toggle("sans-code", !P || P.code === false);
  if (choix === "aucun" || choix === logoAffiche) return;
  logoAffiche = choix;
  embImg.src = LOGOS[choix];
  emb.classList.toggle("large", choix === "nomad");
}
//  Une image qui manque (ti-lex IA pas installé) : pas de cadre vide au centre.
embImg.addEventListener("error", () => { emb.hidden = true; });
embImg.addEventListener("load", () => { if (P && P.embleme !== "aucun") emb.hidden = false; });
//  « avecAucun » : le menu du clic droit fait aussi le tour par « pas de logo ».
async function changerLogo(avecAucun) {
  const tour = avecAucun ? [...ORDRE_LOGOS, "aucun"] : ORDRE_LOGOS;
  const suivant = tour[(tour.indexOf(P.embleme) + 1) % tour.length];
  try { await api("/api/reglages", { embleme: suivant }); verifier(); } catch { bulle("Le bureau ne répond pas"); }
}
embBtn.addEventListener("click", () => {
  embBtn.classList.remove("tourne", "onde"); void embBtn.offsetWidth; embBtn.classList.add("tourne", "onde");
  setTimeout(() => changerLogo(false), 400);
});
embBtn.addEventListener("animationend", (e) => { if (e.animationName === "emb-tourne") embBtn.classList.remove("tourne", "onde"); });
document.addEventListener("mousemove", (e) => {
  const x = e.clientX / innerWidth - .5, y = e.clientY / innerHeight - .5;
  embBtn.style.transform = `rotateY(${x * 14}deg) rotateX(${-y * 14}deg)`;
});
document.addEventListener("mouseleave", () => { embBtn.style.transform = ""; });

/* ⌨️ Le code qui s'écrit tout seul derrière la bannière — les morceaux
   d'Alex, mot pour mot (bureau.js du Moteur), avec ses fautes de frappe
   qu'on efface. Il ne tape que si on le voit : bannière Nomad affichée,
   « code » coché, écran principal, page visible. */
(() => {
  const zone = $("#code");
  const MORCEAUX = [
`from pathlib import Path
from lexos import bureau, ia

CLE = Path("/media/LEXOS")`,
`def dessiner_horizon(scene):
    for ligne in scene.lignes:
        scene.afficher(ligne)
    return scene.horizon`,
`# Une lumière discrète
opacite: float = 0.35
mouvement: str = "doux"`,
`def composer_bureau(image, calques):
    resultat = image.copy()
    for calque in calques:
        resultat = calque.appliquer(resultat)
    return resultat`,
`palette = {"texte": "#9c9fa2", "accent": "#ff6a00"}`,
`async def demander(question: str) -> str:
    modele = ia.choisir("qwen3")
    return await modele.repondre(question)`,
`class Nomad:
    version = "2.0.0"
    def demarrer(self):
        bureau.ouvrir(theme="noir")
        print("ti-lex IA est prêt")`,
`for fichier in CLE.glob("**/*.gguf"):
    ia.importer(fichier)  # tout reste sur la clé`,
  ];
  //  Un petit colorieur Python : mots-clés, chaînes, commentaires.
  const MOTS = /^(def|class|return|for|in|from|import|async|await|if|else|elif|while|with|as|print|self|True|False|None|float|str|int)$/;
  const colorier = (l) => l.replace(/(#.*$)|("[^"]*"?|'[^']*'?)|([A-Za-z_]\w*)|([^#"'A-Za-z_]+)/g, (m, com, ch, mot, autre) =>
    com ? `<span class="tk-com">${echapper(com)}</span>`
    : ch ? `<span class="tk-ch">${echapper(ch)}</span>`
    : mot ? (MOTS.test(mot) ? `<span class="tk-mot">${mot}</span>` : mot)
    : echapper(autre));
  const MAX = 15;
  let lignes = [""], morceau = 0, pos = 0, attente = 0, faute = null;
  const peindre = () => {
    zone.innerHTML = lignes.map((l, i) => `<span class="ligne">${colorier(l) || " "}${i === lignes.length - 1 ? '<i class="code-curseur"></i>' : ""}</span>`).join("");
  };
  const taper = () => {
    const visible = !SECONDAIRE && !document.hidden && !emb.hidden && emb.classList.contains("large") && !$("#bureau").classList.contains("sans-code");
    if (!visible) { setTimeout(taper, 800); return; }
    if (attente > 0) { attente--; setTimeout(taper, 90); return; }
    const texte = MORCEAUX[morceau];
    if (faute !== null) {                              // petite faute de frappe… puis on efface
      lignes[lignes.length - 1] = lignes[lignes.length - 1].slice(0, -1);
      faute = null; peindre(); setTimeout(taper, 140); return;
    }
    if (pos >= texte.length) {                         // morceau fini : une ligne vide, et le suivant
      lignes.push(""); morceau = (morceau + 1) % MORCEAUX.length; pos = 0; attente = 12;
    } else {
      const c = texte[pos++];
      if (c === "\n") { lignes.push(""); attente = 2 + Math.floor(Math.random() * 4); }
      else if (/[a-z]/.test(c) && Math.random() < .025) {   // une faute, de temps en temps
        lignes[lignes.length - 1] += String.fromCharCode(97 + Math.floor(Math.random() * 26));
        faute = true; pos--;
      } else lignes[lignes.length - 1] += c;
    }
    while (lignes.length > MAX) lignes.shift();
    peindre();
    const vite = /[ (=:.,]/.test(texte[pos - 1] || "") ? 70 : 28;
    setTimeout(taper, vite + Math.random() * 60);
  };
  if (calme) { lignes = MORCEAUX.slice(0, 3).join("\n\n").split("\n"); peindre(); return; }
  lignes = (MORCEAUX[0] + "\n\n" + MORCEAUX[1] + "\n").split("\n"); morceau = 2;   // on commence avec du code déjà écrit
  peindre(); taper();
})();

/* ════════════════ Charger, puis suivre les changements ════════════════ */
async function charger() {
  const e = await api("/api/etat");
  const avantP = P;
  P = e.reglages; PRENOM = e.prenom || "";
  appliquerTheme();
  appliquerDecor(!avantP || avantP.anim !== P.anim || avantP.densite !== P.densite);
  POSITIONS = (P.positions && typeof P.positions === "object") ? P.positions : {};
  poserMarges(e.zone);
  poserDock(SECONDAIRE ? null : e.dock);
  appliquerEmbleme();
  //  Pendant qu'on glisse une icône, on ne redessine pas sous la souris.
  if (!SECONDAIRE && !GLISSE.enCours) {
    dessinerIcones(e.sections);
    $("#accueil").classList.toggle("cache", !P.horloge);
    $("#demande").hidden = !e.tilex;
    $("#vers-abo").hidden = !e.tilex;
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
          vitesse: 100, densite: 100, orbes: true, grille: true, curseur: true, zoom: true, embleme: "nomad", code: true };
    appliquerEmbleme();
    appliquerTheme(); appliquerDecor(true);
  }
  requestAnimationFrame(boucle);
  setInterval(verifier, 2000);
})();
