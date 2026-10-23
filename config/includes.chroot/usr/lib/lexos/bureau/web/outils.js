/* 🎛️ Mes outils — la barre mince qui descend du haut de l'écran.

   fenetre.py (« MES OUTILS ») montre la fenêtre quand la souris reste collée
   en haut, puis appelle outils.ouvrir() ; il la cache quand la souris part.
   La page lui parle en changeant son titre : « taille-… » (la hauteur qu'il
   faut), « fermer-… », « clavier-… » (la recherche du ti démon veut le
   clavier), « arret-eteindre-… » puis « arret-pret-eteindre-… ». */
"use strict";

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const JETON = new URLSearchParams(location.search).get("t") || "";
const echapper = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const sansAccent = (t) => String(t).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

async function api(chemin, corps) {
  const r = await fetch(chemin, corps === undefined
    ? { headers: { "X-Jeton": JETON }, cache: "no-store" }
    : { method: "POST", headers: { "X-Jeton": JETON, "Content-Type": "application/json" }, body: JSON.stringify(corps) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

/*  UN SIGNE À LA FOIS. Deux changements de titre dans la même image, et
    fenetre.py ne voit que le dernier : « taille » et « clavier » partent
    ensemble quand le ti démon s'ouvre. On les met en file. */
const FILE = [];
let fileOccupee = false;
function signe(t) {
  FILE.push(t);
  if (fileOccupee) return;
  fileOccupee = true;
  const suivant = () => {
    const x = FILE.shift();
    if (x === undefined) { fileOccupee = false; return; }
    document.title = x + "-" + Date.now();
    setTimeout(suivant, 40);
  };
  suivant();
}

let O = null;            // la réponse de /api/outils
let menu = null;         // "son" | "capture" | "notifs" | "arret" | "tout" | null
let choix = false;       // « ＋ » : placer des outils dans la barre
let rayon = "tout";
let fermeture = null;

/* ── La couleur et la police du bureau (comme le labo) ── */
let minuteurArc = null;
function poserTheme(r) {
  const st = document.documentElement.style;
  const couleur = (hex) => {
    st.setProperty("--orange", hex);
    st.setProperty("--orange-2", melanger(hex, "#ffffff", .35));
    st.setProperty("--orange-fonce", melanger(hex, "#000000", .22));
    st.setProperty("--acc-rgb", hexVersRgb(hex).join(","));
    st.setProperty("--sur-accent", luminance(hex) > .45 ? "#0a0a0a" : "#ffffff");
  };
  clearInterval(minuteurArc);
  if (r.accent === "arc-en-ciel") { let t = 20; minuteurArc = setInterval(() => { t = (t + 1.2) % 360; couleur(hslVersHex(t, 95, 58)); }, 60); }
  else couleur(/^#[0-9a-f]{6}$/i.test(r.accent) ? r.accent : "#ff7a18");
  st.setProperty("--police", r.police === "Système" ? "system-ui, sans-serif"
    : r.police === "Serif classique" ? "Georgia, 'DejaVu Serif', serif" : `'LX ${r.police}', system-ui, sans-serif`);
}

const image = (e) => e.icone
  ? `<img ${e.plein ? 'class="vignette"' : ""} src="/icone/${encodeURIComponent(e.id)}?t=${encodeURIComponent(JETON)}" alt="">`
  : echapper(e.emoji || "🚀");
function secoursImages(el) {
  el.querySelectorAll("img:not([data-ok])").forEach((i) => {
    i.dataset.ok = "1";
    i.addEventListener("error", () => i.replaceWith(i.closest("[data-emoji]")?.dataset.emoji || "🚀"), { once: true });
  });
}

/* ════════ La barre ════════ */
function dessinerBarre() {
  if (!O) return;
  $("#mes-outils").innerHTML = O.apps.map((e, k) =>
    `<button class="outil" data-id="${echapper(e.id)}" data-emoji="${echapper(e.emoji || "🚀")}" title="${echapper(e.nom)}" style="animation-delay:${80 + k * 40}ms"><span>${image(e)}</span></button>`).join("");
  secoursImages($("#mes-outils"));
  dessinerSon();
  dessinerBureaux();
  $("#audit").hidden = !O.audit;
  const n = O.notifs.length;
  $("#nb").hidden = !n; $("#nb").textContent = n > 99 ? "99+" : n;
}

/* 🔊 Le son — l'emoji seul dans la barre, le réglage dans son menu.
   ALEX : « le bouton du volume qui prend pas toute la place, on garde
   l'emoji, et ensuite on clique dessus pour voir le choix d'ajuster ». La
   glissière de 170 px et son « 100 % » occupaient la barre à eux seuls. */
let minuteurSon = null, rouletteSon = 0, versionSon = 0;
const iconeSon = (v, muet) => muet ? "🔇" : v < 34 ? "🔈" : v < 67 ? "🔉" : "🔊";
function dessinerSon() {
  const s = O.son;
  $("#son").hidden = !(s && s.volume >= 0);
  if ($("#son").hidden) {
    //  Plus de son (pactl parti, carte débranchée) : son menu ne reste pas
    //  ouvert sur une glissière qui ne règle plus rien.
    if (menu === "son") { fermerMenus(); menu = null; demanderTaille(); }
    return;
  }
  if (document.activeElement !== $("#volume")) $("#volume").value = s.volume;
  majCurseur();
}
function majCurseur() {
  const g = +$("#volume").value, muet = !!O?.son?.muet, reel = O?.son?.volume;
  //  Au-delà de 100 % (la touche « volume + » de LexOS monte jusqu'à 150 %),
  //  la glissière s'arrête à 100 : on affiche quand même le VRAI niveau.
  const v = reel > 100 && g === 100 ? reel : g;
  $("#volume").style.setProperty("--v", g + "%");
  $("#pct").textContent = v + " %";
  //  L'emoji de la barre DIT le niveau : 🔈 🔉 🔊, et 🔇 quand c'est coupé.
  $("#son-icone").textContent = $("#muet").textContent = iconeSon(v, muet);
  $("#son").classList.toggle("coupe", muet);
  $("#reglage-son").classList.toggle("coupe", muet);
  $("#son").title = muet ? `Son coupé (${v} %) — clique pour régler` : `Volume : ${v} % — clique pour régler`;
}
function envoyerVolume() {
  //  CHAQUE GESTE PORTE UN NUMÉRO. Une réponse arrivée après un geste plus
  //  récent est périmée : l'appliquer remettrait la glissière en arrière, et
  //  la roulette perdrait ses crans — 6 crans vers soi restaient bloqués à
  //  95 % (relecture du 2026-10-23, vraie fenêtre Qt, /api/son à 25 ms).
  const n = ++versionSon;
  clearTimeout(minuteurSon);
  minuteurSon = setTimeout(async () => {
    const corps = { volume: +$("#volume").value };
    //  Régler le volume remet le son : sinon la roulette sur 🔇 changerait
    //  un niveau que personne n'entend, sans que rien ne le montre.
    if (O?.son?.muet) corps.muet = "off";
    try {
      const r = await api("/api/son", corps);
      if (n !== versionSon) return;
      O.son = r; dessinerSon();
      if (r.ok === false) bulle("Le son ne répond pas");
    } catch {
      if (n !== versionSon) return;
      //  Rien n'a été appliqué : on revient au niveau connu, et on le dit.
      if (O?.son) { $("#volume").value = O.son.volume; majCurseur(); }
      bulle("Le son ne répond pas");
    }
  }, 60);
}
$("#volume").addEventListener("input", () => { majCurseur(); envoyerVolume(); });
$("#muet").addEventListener("click", async () => {
  try { O.son = await api("/api/son", { muet: "toggle" }); dessinerSon(); } catch { bulle("Le son ne répond pas"); }
});
//  La roulette sur 🔊 (ou dans son menu) : 5 % par cran, vers soi = moins
//  fort. Un pavé tactile envoie de petits pas : on les additionne.
function rouletteVolume(e) {
  e.preventDefault();
  if (!O?.son || O.son.volume < 0) return;
  rouletteSon += e.deltaY || e.deltaX;
  if (Math.abs(rouletteSon) < 40) return;
  const pas = rouletteSon > 0 ? -5 : 5;
  rouletteSon = 0;
  const g = +$("#volume").value;
  if (O.son.volume > 100 && g === 100) {
    //  Au-delà de 100 % : un cran « plus fort » ne doit pas RAMENER le son à
    //  100, et un cran « moins fort » redescend à 100, pas d'un coup à 95.
    if (pas > 0) return;
    O.son.volume = 100;
  } else {
    $("#volume").value = Math.max(0, Math.min(100, g + pas));
  }
  majCurseur(); envoyerVolume();
}
$("#son").addEventListener("wheel", rouletteVolume, { passive: false });
$("#menu-son").addEventListener("wheel", rouletteVolume, { passive: false });

/* ▪▪▪▪ Les bureaux virtuels — les points de l'ancienne barre du haut.
   Un clic sur un point : ce bureau. La roulette n'importe où sur la barre
   (sauf sur le volume) : le bureau voisin, tout de suite, sans animation —
   demande d'Alex : « la souris en haut, la petite roulette, ça change de
   bureau, ça affiche rien ». */
function dessinerBureaux() {
  const b = O.bureaux || { n: 0, actuel: 0 };
  const zone = $("#bureaux");
  zone.hidden = !(b.n > 1);
  if (zone.hidden) return;
  if (zone.children.length !== b.n) {
    zone.innerHTML = Array.from({ length: b.n }, (_, i) =>
      `<button class="point" data-bureau="${i}" title="Bureau ${i + 1}" aria-label="Bureau ${i + 1}"></button>`).join("");
  }
  [...zone.children].forEach((p, i) => { p.classList.toggle("actuel", i === b.actuel); p.setAttribute("aria-pressed", i === b.actuel); });
}
async function allerBureau(corps) {
  try { const r = await api("/api/bureau", corps); if (r && r.n) { O.bureaux = { n: r.n, actuel: r.actuel }; dessinerBureaux(); } } catch {}
}
$("#bureaux").addEventListener("click", (e) => {
  const p = e.target.closest("[data-bureau]");
  if (p) allerBureau({ aller: +p.dataset.bureau });
});
let roulette = 0, rouletteLibre = 0;
$("#barre").addEventListener("wheel", (e) => {
  if (e.target.closest("#son")) return;            // la roulette sur 🔊 règle le volume (rouletteVolume)
  e.preventDefault();
  //  Un pavé tactile envoie des dizaines de petits pas : on les additionne,
  //  et un seul bureau par geste (pas plus d'un tous les 180 ms).
  roulette += e.deltaY || e.deltaX;
  const maintenant = performance.now();
  if (Math.abs(roulette) < 40 || maintenant < rouletteLibre) return;
  const pas = roulette > 0 ? 1 : -1;
  roulette = 0; rouletteLibre = maintenant + 180;
  allerBureau({ pas });
}, { passive: false });

/* ════════ Les menus qui tombent ════════ */
function placerSous(el, bouton) {
  const b = bouton.getBoundingClientRect();
  el.hidden = false;
  const l = el.offsetWidth;
  el.style.left = Math.max(14, Math.min(innerWidth - l - 14, b.left + b.width / 2 - l / 2)) + "px";
}
function ouvrirMenu(nom, bouton) {
  fermerMenus();
  if (menu === nom) { menu = null; demanderTaille(); return; }
  menu = nom;
  $$(".bouton-outil").forEach((b) => b.classList.toggle("actif", b.dataset.menu === nom));
  if (nom === "notifs") dessinerNotifs();
  if (nom === "arret") $("#arret-titre").textContent = `À plus tard${O?.prenom ? ", " + O.prenom : ""} ?`;
  placerSous($("#menu-" + nom), bouton);
  demanderTaille();
}
function fermerMenus() {
  $$(".menu, #tout").forEach((m) => { m.hidden = true; });
  $$(".bouton-outil, .demon").forEach((b) => b.classList.remove("actif"));
  $$(".gestes .arme").forEach(desarmer);
}
$$(".bouton-outil").forEach((b) => b.addEventListener("click", () => {
  const avant = menu;
  fermerMenus(); menu = null;
  if (avant !== b.dataset.menu) ouvrirMenu(b.dataset.menu, b); else demanderTaille();
}));

/* 📷 La capture : la barre remonte d'abord, la photo vient après (gestes.py attend). */
$$("[data-capture]").forEach((b) => b.addEventListener("click", async () => {
  fermer();
  try { const r = await api("/api/capture", { mode: b.dataset.capture }); if (!r.ok) bulle("La capture d'écran n'est pas disponible"); } catch {}
}));

/* 🔔 Les notifications */
function dessinerNotifs() {
  const l = O?.notifs || [];
  $("#liste-notifs").innerHTML = l.length
    ? l.map((n, k) => `<li style="animation-delay:${k * 30}ms"><small>${echapper(n.quand)}</small><b>${echapper(n.titre || n.app || "Notification")}</b>${n.corps ? `<p>${echapper(n.corps)}</p>` : ""}</li>`).join("")
    : `<li class="rien">Aucune notification 🎉</li>`;
  $("#dnd").classList.toggle("allume", !!O?.dnd);
  $("#dnd").textContent = O?.dnd ? "🔕 Ne pas déranger : oui" : "🔔 Ne pas déranger : non";
}
$("#dnd").addEventListener("click", async () => {
  try { Object.assign(O, await api("/api/notifs", { dnd: !O.dnd })); dessinerNotifs(); dessinerBarre(); } catch {}
});
$("#vider").addEventListener("click", async () => {
  try { Object.assign(O, await api("/api/notifs", { vider: true })); dessinerNotifs(); dessinerBarre(); demanderTaille(); } catch {}
});

/* ⏻ L'arrêt. Éteindre et redémarrer : un DEUXIÈME clic (dans les 3 s) — un
   clic de travers ne doit jamais éteindre l'ordinateur d'Alex. */
const NOMS = { eteindre: "Éteindre", redemarrer: "Redémarrer" };
function desarmer(b) { b.classList.remove("arme"); $("b", b).textContent = NOMS[b.dataset.geste] || $("b", b).textContent; clearTimeout(b._t); }
$$("[data-geste]").forEach((b) => b.addEventListener("click", async () => {
  const g = b.dataset.geste;
  if (g === "eteindre" || g === "redemarrer") {
    if (!b.classList.contains("arme")) {
      $$(".gestes .arme").forEach(desarmer);
      b.classList.add("arme"); $("b", b).textContent = "Clique encore";
      b._t = setTimeout(() => desarmer(b), 3000);
      return;
    }
    desarmer(b);
    signe("arret-" + g);          // fenetre.py : photo de l'écran, puis la télé s'éteint
    return;
  }
  fermer();
  try { const r = await api("/api/session", { geste: g }); if (!r.ok) bulle("Ce geste n'est pas disponible ici"); } catch {}
}));

/* ════════ 😈 Tout LexOS ════════ */
const ICONES_RAYON = { "Ma barre": "⭐", "ti-lex IA": "🤖", "LexOS": "🐧", "Mon bureau": "🗂️", "Internet": "🌐", "Multimédia": "🎵",
  "Graphisme": "🎨", "Développement": "💻", "Bureautique": "📝", "Jeux": "🎮", "Éducation": "🎓", "Système": "⚙️",
  "Paramètres": "🛠️", "Accessoires": "🧰", "Autres": "📦" };
const ORDRE_RAYONS = ["Internet", "Multimédia", "Graphisme", "Développement", "Bureautique", "Jeux", "Éducation", "Accessoires", "Système", "Paramètres", "Autres"];
function groupes() {
  if (!O) return [];
  const g = [];
  if (!choix && O.apps.length) g.push({ titre: "Ma barre", elements: O.apps });
  for (const s of O.sections) {
    if (s.titre !== "Toutes les applications") { g.push({ titre: s.titre, elements: s.elements }); continue; }
    const par = {};
    for (const e of s.elements) (par[e.rayon || "Autres"] ||= []).push(e);
    for (const r of ORDRE_RAYONS) if (par[r]) g.push({ titre: r, elements: par[r] });
  }
  return g;
}
const tuile = (e, k, dans) => `<button class="tuile${e.id.startsWith("t-") ? " lanceur" : ""}${dans ? " dedans" : ""}" data-id="${echapper(e.id)}" data-emoji="${echapper(e.emoji || "🚀")}" title="${echapper(e.nom)}" style="animation-delay:${Math.min(k, 40) * 18}ms"><span>${image(e)}</span><b>${echapper(e.nom)}</b></button>`;
function dessinerTout() {
  const G = groupes();
  if (!G.some((g) => g.titre === rayon) && rayon !== "tout") rayon = "tout";
  const total = new Set(G.flatMap((g) => g.elements.map((e) => e.id))).size;
  $("#rayons").innerHTML = `<button data-rayon="tout" class="${rayon === "tout" ? "actif" : ""}">📚 Tout<em>${total}</em></button>`
    + G.map((g) => `<button data-rayon="${echapper(g.titre)}" class="${rayon === g.titre ? "actif" : ""}">${ICONES_RAYON[g.titre] || "📦"} ${echapper(g.titre)}<em>${g.elements.length}</em></button>`).join("");
  const dans = new Set((O?.apps || []).map((e) => e.id));
  const q = sansAccent($("#cherche").value.trim());
  let k = 0, html = choix ? `<div class="bandeau-choix">＋ Clique sur un outil pour le mettre dans ta barre (ou l'en retirer) · ✕ quand c'est fini</div>` : "";
  if (q) {
    const vus = new Set(), trouves = [];
    for (const g of G) for (const e of g.elements) if (!vus.has(e.id) && sansAccent(e.nom).includes(q)) { vus.add(e.id); trouves.push(e); }
    html += trouves.length ? trouves.map((e) => tuile(e, k++, dans.has(e.id))).join("") : `<div class="vide">Rien ne s'appelle « ${echapper($("#cherche").value)} »</div>`;
  } else {
    for (const g of G) {
      if (rayon !== "tout" && g.titre !== rayon) continue;
      if (rayon === "tout") html += `<div class="titre-groupe">${ICONES_RAYON[g.titre] || "📦"} ${echapper(g.titre)}</div>`;
      html += g.elements.map((e) => tuile(e, k++, dans.has(e.id))).join("");
    }
  }
  $("#grille").innerHTML = html;
  $("#grille").classList.toggle("choix", choix);
  $("#grille").scrollTop = 0;
  secoursImages($("#grille"));
  $("#tout-sous").textContent = choix ? "Choisis ce qui va dans ta barre d'outils" : "Toutes tes applications et tous tes outils";
}
function ouvrirTout(avecChoix) {
  fermerMenus();
  choix = !!avecChoix; rayon = choix ? "LexOS" : "tout"; menu = "tout";
  $("#cherche").value = "";
  $(".demon").classList.toggle("actif", !choix);
  const t = $("#tout");
  t.style.height = Math.round(Math.min(680, Math.max(380, screen.height * .66))) + "px";
  t.hidden = false;
  dessinerTout();
  demanderTaille();
  signe("clavier");                       // la recherche veut le clavier
  setTimeout(() => $("#cherche").focus(), 120);
}
$("#demon").addEventListener("click", () => { if (menu === "tout" && !choix) { fermerMenus(); menu = null; demanderTaille(); } else ouvrirTout(false); });
$("#ajouter").addEventListener("click", () => ouvrirTout(true));
$("#audit").addEventListener("click", async () => {
  try { const r = await api("/api/action", { nom: "audit" }); if (r.ok) fermer(); else bulle("Les outils d'audit ne sont pas installés"); }
  catch { bulle("Le bureau ne répond pas"); }
});
$("#tout-fermer").addEventListener("click", () => { fermerMenus(); menu = null; choix = false; demanderTaille(); });
$("#cherche").addEventListener("input", dessinerTout);
$("#rayons").addEventListener("click", (e) => { const b = e.target.closest("[data-rayon]"); if (!b) return; rayon = b.dataset.rayon; $("#cherche").value = ""; dessinerTout(); });

async function placer(id) {
  const ids = O.apps.map((e) => e.id);
  const nouveaux = ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id];
  try {
    const r = await api("/api/reglages", { outils_apps: nouveaux });
    const parId = new Map(O.sections.flatMap((s) => s.elements.map((e) => [e.id, e])));
    O.apps = r.reglages.outils_apps.map((i) => parId.get(i)).filter(Boolean);
  } catch { bulle("La barre n'a pas pu être gardée"); }
  dessinerBarre(); dessinerTout();
}

/* ── Lancer (la barre et le ti démon) ── */
const DERNIERS = new Map();
async function lancer(id, titre) {
  const t = performance.now();
  if (t - (DERNIERS.get(id) || -1e9) < 1200) return;
  DERNIERS.set(id, t);
  try {
    const r = await api("/api/lancer", { id });
    if (r.raison === "non-approuve") return bulle("« " + titre + " » n'est pas encore approuvé : Fichiers s'ouvre — double-clique-le là");
    if (r.raison === "lien-refuse") return bulle("Ce raccourci ne mène pas à une page web");
    if (!r.ok && !r.deja) return bulle("Impossible d'ouvrir « " + titre + " »");
    fermer();
  } catch { bulle("Le bureau ne répond pas"); }
}
$("#mes-outils").addEventListener("click", (e) => { const b = e.target.closest(".outil"); if (b) lancer(b.dataset.id, b.title); });
$("#mes-outils").addEventListener("contextmenu", (e) => { const b = e.target.closest(".outil"); if (b) { placer(b.dataset.id); bulle("Retiré de ta barre"); } });
$("#grille").addEventListener("click", (e) => {
  const b = e.target.closest(".tuile"); if (!b) return;
  if (choix) placer(b.dataset.id); else lancer(b.dataset.id, b.title);
});
document.addEventListener("contextmenu", (e) => e.preventDefault());
for (const t of ["dragover", "drop", "dragstart"]) document.addEventListener(t, (e) => e.preventDefault());
document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  if (menu) { fermerMenus(); menu = null; choix = false; demanderTaille(); } else fermer();
});
//  Un clic dans le vide transparent (sous la barre, hors des menus) ferme le menu ouvert.
document.addEventListener("mousedown", (e) => {
  if (menu && !e.target.closest(".barre, .menu, #tout")) { fermerMenus(); menu = null; choix = false; demanderTaille(); }
});

/* ── La hauteur que la fenêtre doit avoir ── */
function demanderTaille() {
  requestAnimationFrame(() => {
    let bas = $(".barre").getBoundingClientRect().bottom + 18;
    for (const m of $$(".menu, #tout")) if (!m.hidden) bas = Math.max(bas, m.offsetTop + m.offsetHeight + 24);
    signe("taille-" + Math.ceil(bas));
  });
}

let minuteurBulle = null;
function bulle(texte) {
  const b = $("#bulle");
  b.textContent = texte; b.hidden = false;
  clearTimeout(minuteurBulle);
  minuteurBulle = setTimeout(() => { b.hidden = true; }, 3200);
}

async function charger() {
  try { O = await api("/api/outils"); poserTheme(O.reglages); } catch { bulle("Le bureau ne répond pas"); }
  dessinerBarre();
  if (menu === "notifs") dessinerNotifs();
  if (menu === "tout") dessinerTout();
}

/* ── Ouvrir / fermer (appelés par fenetre.py) ── */
function ouvrir() {
  clearTimeout(fermeture);
  fermerMenus(); menu = null; choix = false;
  document.body.classList.remove("ouvert"); void document.body.offsetWidth;
  dessinerBarre();
  requestAnimationFrame(() => document.body.classList.add("ouvert"));
  demanderTaille();
  charger();
}
function fermer() {
  if (!document.body.classList.contains("ouvert")) return;
  fermerMenus(); menu = null; choix = false;
  document.body.classList.remove("ouvert");
  clearTimeout(fermeture);
  fermeture = setTimeout(() => signe("fermer"), 300);
}

/* ════════ 📺 L'arrêt façon télé des années 80 ════════
   fenetre.py a caché la barre, photographié l'écran, puis étendu cette
   fenêtre à tout l'écran : on pose la photo, et on éteint la « télé » —
   l'image s'écrase en une ligne, la ligne en un point blanc, le point
   s'éteint. Alors seulement on dit « prêt » : la machine s'éteint. */
function tele(photo, geste) {
  fermerMenus(); menu = null;
  document.body.classList.remove("ouvert");
  const t = $("#tele");
  $("#tele-image").style.backgroundImage = photo ? `url("${photo}")` : "radial-gradient(circle, #1a1a1c, #050505)";
  t.classList.remove("joue"); t.hidden = false; void t.offsetWidth;
  t.classList.add("joue");
  setTimeout(() => signe("arret-pret-" + geste), 1900);
}
function teleRatee() {
  const t = $("#tele");
  t.hidden = true; t.classList.remove("joue");
  bulle("L'ordinateur ne s'est pas éteint — essaie « systemctl poweroff » dans un terminal");
}

window.outils = { ouvrir, fermer, tele, teleRatee };
charger();
