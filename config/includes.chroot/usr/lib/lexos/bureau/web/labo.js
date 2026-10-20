/* 🧪 Mon labo — le panneau qui monte du bas de l'écran.

   C'est fenetre.py (« LE LABO ») qui montre la fenêtre quand la souris
   reste collée en bas, puis appelle labo.ouvrir() ; et qui la cache quand
   la souris part. La page, elle, dit « ferme-moi » en changeant son titre
   (« fermer-… ») : après un lancement, ou sur ✕. */
"use strict";

const $ = (s, el = document) => el.querySelector(s);
const JETON = new URLSearchParams(location.search).get("t") || "";
const echapper = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

async function api(chemin, corps) {
  const r = await fetch(chemin, corps === undefined
    ? { headers: { "X-Jeton": JETON }, cache: "no-store" }
    : { method: "POST", headers: { "X-Jeton": JETON, "Content-Type": "application/json" }, body: JSON.stringify(corps) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

let L = null;            // la réponse de /api/labo
let choix = false;       // mode « ＋ Ajouter »
let fermeture = null;

/* ── La couleur et la police du bureau ── */
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

/* ── Les tuiles ── */
function tuile(e, k, extra = "") {
  const dedans = e.icone
    ? `<img ${e.plein ? 'class="vignette"' : ""} src="/icone/${encodeURIComponent(e.id)}?t=${encodeURIComponent(JETON)}" alt="">`
    : echapper(e.emoji || "🚀");
  const lanceur = e.id.startsWith("t-") ? " lanceur" : "";
  return `<button class="icone${lanceur}${extra}" data-id="${echapper(e.id)}" data-emoji="${echapper(e.emoji || "🚀")}" title="${echapper(e.nom)}" style="animation-delay:${Math.min(k, 30) * 28}ms"><span>${dedans}</span><b>${echapper(e.nom)}</b>${choix ? "" : '<i class="retirer" title="Retirer du labo">×</i>'}</button>`;
}
function dessiner() {
  if (!L) return;
  const corps = $("#corps");
  $("#ajouter").textContent = choix ? "✓ Terminé" : "＋ Ajouter";
  $("#ajouter").classList.toggle("plein", choix);
  let k = 0;
  if (choix) {
    const dans = new Set(L.apps.map((e) => e.id));
    $("#sous").textContent = "Clique pour mettre une appli dans ton labo, ou l'en retirer";
    corps.className = "corps choix";
    corps.innerHTML = L.sections.map((s) => `<h5 class="groupe">${echapper(s.titre)}</h5><div class="grille">`
      + s.elements.map((e) => tuile(e, k++, dans.has(e.id) ? " dedans" : "")).join("") + "</div>").join("");
  } else {
    const n = L.apps.length;
    $("#sous").textContent = n ? `Tes IA et tes outils de travail · ${n} appli${n > 1 ? "s" : ""}` : "Tes IA et tes outils de travail";
    corps.className = "corps";
    corps.innerHTML = n ? `<div class="grille">${L.apps.map((e) => tuile(e, k++)).join("")}</div>`
      : `<div class="vide"><b>🧪</b>Ton labo est vide.<br>Clique sur <strong>＋ Ajouter</strong> pour y mettre tes IA et tes applis.</div>`;
  }
  corps.querySelectorAll("img").forEach((i) => i.addEventListener("error", () => {
    i.replaceWith(i.closest(".icone")?.dataset.emoji || "🚀");
  }, { once: true }));
  demanderTaille(sortieChoix);
  sortieChoix = false;
}
let sortieChoix = false;

/*  La hauteur qu'il faut : juste ce que les applis prennent (le labo de
    onze applis ne monte pas jusqu'au milieu de l'écran), tout ce qui est
    permis en mode « ＋ Ajouter ». fenetre.py lit le titre « taille-… » et
    ajuste la fenêtre, collée au bas de l'écran. */
//  « plusTard » : en sortant de « ＋ Ajouter », on ne rapetisse PAS sous la
//  souris (elle se retrouverait au-dessus du labo, qui se fermerait) — la
//  nouvelle hauteur sert à la prochaine ouverture.
function demanderTaille(plusTard = false) {
  requestAnimationFrame(() => {
    const tete = $(".tete").offsetHeight + $(".poignee").offsetHeight + 10 + 24;
    //  PAS scrollHeight : il vaut au moins la hauteur actuelle du corps, et
    //  le labo n'aurait jamais pu rapetisser. On additionne son contenu.
    const contenu = [...$("#corps").children].reduce((h, c) => {
      const st = getComputedStyle(c);
      return h + c.offsetHeight + parseFloat(st.marginTop) + parseFloat(st.marginBottom);
    }, 0) + 26;
    const voulu = choix ? 99999 : Math.ceil(tete + contenu + 6);
    document.title = `taille-${voulu}-${Date.now()}${plusTard ? "-plus-tard" : ""}`;
  });
}

async function charger() {
  try {
    L = await api("/api/labo");
    poserTheme(L.reglages);
  } catch { bulle("Le bureau ne répond pas"); }
  dessiner();
}

async function enregistrer(ids) {
  try {
    const r = await api("/api/reglages", { labo_apps: ids });
    if (!r.ok) throw new Error();
    const parId = new Map(L.sections.flatMap((s) => s.elements.map((e) => [e.id, e])));
    L.apps = r.reglages.labo_apps.map((i) => parId.get(i)).filter(Boolean);
  } catch { bulle("Le labo n'a pas pu être gardé"); }
  dessiner();
}

/* ── Les clics ── */
const DERNIERS = new Map();
$("#corps").addEventListener("click", async (ev) => {
  const b = ev.target.closest(".icone"); if (!b) return;
  const id = b.dataset.id;
  const ids = L.apps.map((e) => e.id);
  if (choix) {                                   // mettre / retirer
    enregistrer(ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id]);
    return;
  }
  if (ev.target.closest(".retirer")) { enregistrer(ids.filter((x) => x !== id)); bulle("Retiré du labo"); return; }
  const t = performance.now();
  if (t - (DERNIERS.get(id) || -1e9) < 1200) return;      // un double-clic n'ouvre pas deux fois
  DERNIERS.set(id, t);
  b.classList.remove("part"); void b.offsetWidth; b.classList.add("part");
  try {
    const r = await api("/api/lancer", { id });
    if (r.raison === "non-approuve") return bulle("« " + b.title + " » n'est pas encore approuvé : Fichiers s'ouvre — double-clique-le là");
    if (r.raison === "lien-refuse") return bulle("Ce raccourci ne mène pas à une page web");
    if (!r.ok && !r.deja) return bulle("Impossible d'ouvrir « " + b.title + " »");
    setTimeout(fermer, 380);                     // c'est parti : le labo redescend
  } catch { bulle("Le bureau ne répond pas"); }
});
document.addEventListener("contextmenu", (ev) => {
  ev.preventDefault();
  const b = ev.target.closest(".icone");
  if (b && !choix && L) { enregistrer(L.apps.map((e) => e.id).filter((x) => x !== b.dataset.id)); bulle("Retiré du labo"); }
});
$("#ajouter").addEventListener("click", () => { sortieChoix = choix; choix = !choix; dessiner(); });
$("#fermer").addEventListener("click", () => fermer());
for (const t of ["dragover", "drop", "dragstart"]) document.addEventListener(t, (e) => e.preventDefault());

let minuteurBulle = null;
function bulle(texte) {
  const b = $("#bulle");
  b.textContent = texte; b.hidden = false;
  clearTimeout(minuteurBulle);
  minuteurBulle = setTimeout(() => { b.hidden = true; }, 3200);
}

/* ── Ouvrir / fermer (appelés par fenetre.py) ── */
function ouvrir() {
  clearTimeout(fermeture);
  choix = false;
  const p = $("#panneau");
  p.classList.remove("ouvert"); void p.offsetWidth;
  dessiner();                                    // tout de suite, avec ce qu'on sait déjà…
  requestAnimationFrame(() => p.classList.add("ouvert"));
  charger();                                     // …puis à jour (une appli installée entre-temps)
}
function fermer() {
  const p = $("#panneau");
  if (!p.classList.contains("ouvert")) return;
  p.classList.remove("ouvert");
  clearTimeout(fermeture);
  //  Le titre change APRÈS la descente : fenetre.py cache alors la fenêtre.
  fermeture = setTimeout(() => { document.title = "fermer-" + Date.now(); }, 330);
}
window.labo = { ouvrir, fermer };
charger();
