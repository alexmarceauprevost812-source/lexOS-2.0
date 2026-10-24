// LexOS Pilotes — interface. Lit /api/etat, lance les tâches, suit /api/tache.
"use strict";

const $ = (id) => document.getElementById(id);
// Pas de « — » de remplacement : une valeur absente passe par mesure(), qui
// dit « Indisponible » ET pourquoi. Un tiret muet ne dit rien à personne.
const esc = (t) => String(t ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const indisponible = (raison) =>
  `<span class="mal">Indisponible</span> <span class="doux">— ${esc(raison || "le serveur n'a pas donné de raison")}</span>`;
const mesure = (v, raison) => (v === null || v === undefined || v === "" ? indisponible(raison) : esc(v));
// Un paquet que dpkg ne connaît pas n'est PAS « indisponible » : c'est une
// vraie réponse (« aucun »), utile quand une carte NVIDIA est vue sans pilote.
const versionPaquet = (v, raison, noms) => (v ? esc(v) : raison ? indisponible(raison)
  : `<span class="mal">aucun</span> <span class="doux">(${esc(noms)} : non installé)</span>`);

// Le jeton de la session : posé par le serveur dans le FRAGMENT de l'adresse
// (« #j=… »), qui ne part jamais sur le réseau. Toute l'API l'exige — c'est
// ce qui empêche un autre programme de la machine de pousser les boutons.
const JETON = new URLSearchParams((location.hash || "").replace(/^#/, "")).get("j") || "";

function api(chemin, options = {}) {
  const entetes = { "X-Jeton": JETON };
  if (options.method === "POST") entetes["X-LexOS"] = "1";
  return fetch(chemin, { cache: "no-store", ...options, headers: entetes });
}

const SANS_JETON = "Cette page n'a pas (ou plus) son jeton de session : ferme-la et rouvre " +
  "LexOS Pilotes depuis le menu. Le serveur refuse toute commande qui ne vient pas de la page qu'il a ouverte.";

let suivi = null;
let dernierEtat = null;

function depuis(secondes, maintenant) {
  if (!secondes) return "jamais vérifié";
  const m = Math.round((maintenant - secondes) / 60);
  if (m < 1) return "vérifié à l'instant";
  if (m < 60) return `vérifié il y a ${m} min`;
  const h = Math.round(m / 60);
  if (h < 48) return `vérifié il y a ${h} h`;
  return `vérifié il y a ${Math.round(h / 24)} jours`;
}

// Un bouton désactivé dit TOUJOURS pourquoi : dans son infobulle, et en
// clair sous les boutons.
function boutons() {
  const verifier = $("btn-verifier"), installer = $("btn-installer"), raison = $("raison-actions");
  let pourquoiVerifier = "", pourquoiInstaller = "";
  if (suivi !== null) {
    pourquoiVerifier = pourquoiInstaller = "Une tâche est en cours : son journal s'affiche ci-dessous.";
  } else if (!dernierEtat) {
    pourquoiInstaller = "L'état de la machine n'a pas encore pu être lu.";
  } else {
    const m = dernierEtat.mises_a_jour;
    if (!m.disponible) pourquoiInstaller = `Indisponible : ${m.raison}.`;
    else if (m.retraits.length) pourquoiInstaller = `Cette mise à jour retirerait ${m.retraits.join(", ")} : LexOS Pilotes ne retire jamais rien à ta place.`;
    else if (!m.paquets.length) pourquoiInstaller = "Rien à installer pour la carte graphique.";
  }
  verifier.disabled = Boolean(pourquoiVerifier);
  verifier.title = pourquoiVerifier;
  installer.disabled = Boolean(pourquoiInstaller);
  installer.title = pourquoiInstaller;
  raison.textContent = pourquoiVerifier || pourquoiInstaller;
  raison.hidden = !raison.textContent;
}

function afficherEtat(e) {
  dernierEtat = e;
  const R = e.raisons || {};
  // --- Les cartes ----------------------------------------------------------
  $("cartes").innerHTML = e.cartes.length
    ? e.cartes.map((c) => `
        <div class="ligne">
          <span><span class="puce">${esc(c.marque)}</span> <span class="nom">${esc(c.nom)}</span></span>
          <span class="doux">pilote : ${esc(c.pilote || "aucun")}</span>
        </div>`).join("")
    : `<div class="ligne">${R.cartes ? indisponible(R.cartes) : '<span class="doux">Aucune carte graphique vue par lspci.</span>'}</div>`;

  // --- Le pilote ------------------------------------------------------------
  const nv = e.nvidia, k = e.noyau;
  const lignes = [];
  if (e.cartes.some((c) => c.marque === "NVIDIA")) {
    lignes.push(["NVIDIA chargé", esc(nv.version || "non chargé")]);
    lignes.push(["Paquet installé", versionPaquet(nv.paquet, R.paquet_nvidia, "nvidia-driver-cuda, nvidia-driver")]);
    lignes.push(["Branche épinglée", nv.branche_epinglee ? esc(`${nv.branche_epinglee}.x`)
      : R.branche_epinglee ? indisponible(R.branche_epinglee) : "aucune (la plus récente)"]);
    lignes.push(["Module pour le prochain démarrage",
      k.module_nvidia_plus_recent === true ? '<span class="bon">✓ présent</span>'
        : k.module_nvidia_plus_recent === false ? '<span class="mal">✗ absent</span>' : indisponible(R.noyau)]);
  }
  lignes.push(["Mesa", versionPaquet(e.mesa, R.mesa, "libgl1-mesa-dri")]);
  lignes.push(["Noyau en service", mesure(k.en_service, "platform.release() vide")]);
  if (!k.plus_recent) lignes.push(["Noyau au prochain démarrage", indisponible(R.noyau)]);
  else if (k.plus_recent !== k.en_service) lignes.push(["Noyau au prochain démarrage", esc(k.plus_recent)]);
  lignes.push(["Secure Boot", e.secure_boot === null ? indisponible(R.secure_boot) : e.secure_boot ? "actif" : "inactif"]);
  $("pilote").innerHTML = lignes.map(([a, b]) => `<dt>${esc(a)}</dt><dd>${b}</dd>`).join("");

  const alerte = $("alerte-branche");
  const pin = nv.branche_epinglee, pub = nv.plus_recente_publiee;
  if (pin && pub && !pub.startsWith(pin + ".")) {
    alerte.hidden = false;
    alerte.innerHTML = `NVIDIA publie la version <b>${esc(pub)}</b>, mais LexOS reste sur la branche
      <b>${esc(pin)}</b> exprès : la branche 610 coupe le signal HDMI vers une télé. Les mises à jour
      ci-dessous restent dans la branche ${esc(pin)}. Pour changer de branche, il faut retirer
      <code>/etc/apt/preferences.d/lexos-nvidia-pin</code> à la main — en connaissance de cause.`;
  } else {
    alerte.hidden = true;
  }

  afficherSignature(e.signature);

  // --- Les mises à jour ------------------------------------------------------
  // Trois cas qu'on ne confond plus : « on ne sait pas » (pas d'index apt,
  // apt-cache en échec), « elle retirerait des paquets », « rien à faire ».
  $("verifie").textContent = depuis(e.verifie_le, e.maintenant);
  const m = e.mises_a_jour;
  const liste = m.paquets.map((p) => `
        <div class="ligne">
          <span class="nom">${esc(p.paquet)}</span>
          <span class="doux">${esc(p.installe)} → <span class="bon">${esc(p.cible)}</span> · ${esc(p.source)}</span>
        </div>`).join("");
  if (!m.disponible) {
    $("maj").innerHTML = `<div class="ligne"><span class="puce mal">Indisponible</span><span class="doux">${esc(m.raison)}</span></div>`;
  } else if (m.retraits.length) {
    $("maj").innerHTML = liste + `<div class="note mal">Cette mise à jour <b>retirerait</b> : ${esc(m.retraits.join(", "))}.
      LexOS Pilotes ne retire jamais rien à ta place : le bouton reste désactivé. Pour décider toi-même,
      lance <code>sudo apt install --only-upgrade</code> dans un terminal — apt montre la liste et demande confirmation.</div>`;
  } else if (m.paquets.length) {
    $("maj").innerHTML = liste;
  } else {
    $("maj").innerHTML = `<div class="ligne"><span class="puce bon">À jour</span><span class="doux">Rien à installer pour la carte graphique.</span></div>`;
  }
  $("btn-installer").textContent = m.paquets.length && !m.retraits.length ? `Mettre à jour (${m.paquets.length})` : "Mettre à jour les pilotes";
  boutons();
}

// Le guide d'inscription du certificat LexOS (MOK). Rien ne s'affiche quand
// le pilote est chargé ou que Secure Boot est inactif : il n'y a rien à faire.
const ETAPES_MOK = `
  <ol class="etapes">
    <li>Clique sur <b>Ouvrir l'assistant d'inscription</b>. Il demande ton mot de passe,
      puis un <b>mot de passe d'inscription</b>, deux fois : choisis-en un simple et note-le,
      il ne sert qu'une fois.</li>
    <li><b>Redémarre</b>@LIVE@. Un écran bleu apparaît : <b>MokManager</b>, en anglais.</li>
    <li>Choisis <b>Enroll MOK</b> → <b>Continue</b> → <b>Yes</b>, tape le mot de passe d'inscription,
      puis <b>Reboot</b>.</li>
    <li>LexOS redémarre avec le pilote NVIDIA. Secure Boot reste actif.</li>
  </ol>
  <p class="note">Si l'écran bleu passe trop vite, rien n'est cassé : relance l'assistant.
    Garde la clé de récupération BitLocker de Windows à portée de main avant de changer quoi
    que ce soit au démarrage.</p>`;

function afficherSignature(s) {
  const boite = $("signature"), texte = $("signature-texte"), btn = $("btn-signature");
  if (!s || s.etape === "ok" || s.etape === "sans-secure-boot") {
    boite.hidden = true;
    return;
  }
  boite.hidden = false;
  btn.hidden = true;
  if (s.etape === "inscrire-lexos") {
    const live = s.en_live ? " <b>sur la clé USB</b> (laisse-la branchée)" : "";
    texte.innerHTML = `<p>Le pilote NVIDIA est signé par la <b>clé LexOS</b>, mais cette machine ne la
      connaît pas encore : avec Secure Boot actif, elle refuse de le charger. Il faut inscrire
      le certificat LexOS <b>une seule fois</b> — ensuite toutes les ISO LexOS et le système
      installé sont acceptés.</p>` + ETAPES_MOK.replace("@LIVE@", live);
    btn.hidden = false;
  } else if (s.etape === "redemarrer") {
    texte.innerHTML = `<p class="note bon">Le certificat LexOS est inscrit. Le pilote n'est pas encore
      chargé : <b>redémarre</b>. S'il ne l'est toujours pas après, lance <code>sudo lexos tv</code>.</p>`;
  } else if (s.etape === "cle-machine") {
    texte.innerHTML = `<p>Le pilote a été recompilé sur cette machine et signé par sa propre clé
      (DKMS), pas par la clé LexOS. L'assistant propose d'inscrire cette clé-là, une fois.</p>`;
    btn.hidden = false;
  } else {
    texte.innerHTML = `<p class="note attention">Le pilote NVIDIA n'est pas chargé et sa signature n'a pas pu
      être lue. L'assistant fait le point sans rien changer avant de te demander.</p>`;
    btn.hidden = false;
  }
}

async function ouvrirAssistant() {
  const r = await api("/api/assistant-signature", { method: "POST" });
  if (r.status === 403) return afficherResultat({ ok: false, message: SANS_JETON });
  const rep = await r.json();
  afficherResultat(rep.lance
    ? { ok: true, message: "L'assistant s'est ouvert dans un terminal." }
    : { ok: false, message: rep.message || "Impossible d'ouvrir l'assistant." });
}

async function charger() {
  try {
    const r = await api("/api/etat");
    if (r.status === 403) {
      $("cartes").textContent = SANS_JETON;
      return;
    }
    afficherEtat(await r.json());
  } catch (err) {
    $("cartes").textContent = "Le serveur local ne répond pas.";
  }
}

function afficherResultat(res, prefixe = "") {
  const boite = $("resultat");
  boite.hidden = false;
  boite.className = "note " + (res.ok ? "bon" : "mal");
  let html = esc(prefixe + (res.message || (res.ok ? "Terminé." : "Échec.")));
  if (res.avertissements && res.avertissements.length) {
    boite.className = "note attention";
    html += "<ul>" + res.avertissements.map((a) => `<li>${esc(a)}</li>`).join("") + "</ul>";
  }
  boite.innerHTML = html;
}

// Suit la tâche en cours sur le serveur — celle que cette page vient de
// lancer, OU celle qu'un autre onglet (ou cette page avant un rechargement)
// a lancée : sans ça, un onglet rouvert pendant une installation montrait
// « Mettre à jour » actif, puis le perdait sans raison au premier clic.
function suivre() {
  if (suivi !== null) return;
  const journal = $("journal");
  journal.hidden = false;
  suivi = setInterval(async () => {
    const r = await api("/api/tache");
    if (r.status === 403) return;
    const t = await r.json();
    if (t.journal.length) {
      journal.textContent = t.journal.join("\n");
      journal.scrollTop = journal.scrollHeight;
    }
    if (!t.en_cours) {
      clearInterval(suivi);
      suivi = null;
      if (t.resultat) afficherResultat(t.resultat);
      boutons();
      charger();
    }
  }, 800);
  boutons();
}

async function lancer(action) {
  $("resultat").hidden = true;
  const journal = $("journal");
  journal.hidden = false;
  journal.textContent = action === "installer"
    ? "Une fenêtre va demander ton mot de passe…\n"
    : "Une fenêtre peut demander ton mot de passe pour rafraîchir la liste…\n";
  const r = await api("/api/" + action, { method: "POST" });
  if (r.status === 403) return afficherResultat({ ok: false, message: SANS_JETON });
  const rep = await r.json();
  if (!rep.lance && !rep.en_cours) {
    afficherResultat({ ok: false, message: rep.message });
    return;
  }
  // Lancée ici, ou déjà en cours ailleurs (409) : dans les deux cas, on suit.
  suivre();
}

// Au chargement : une tâche tourne-t-elle déjà ? Et la dernière installation
// a-t-elle laissé un avertissement (« NE redémarre PAS ») à montrer ?
async function reprendre() {
  try {
    const r = await api("/api/tache");
    if (r.status !== 200) return;
    const t = await r.json();
    if (t.en_cours) {
      $("journal").textContent = t.journal.join("\n");
      suivre();
    } else if (t.action === "installer" && t.resultat) {
      afficherResultat(t.resultat, "Dernière mise à jour : ");
    }
  } catch (err) {
    // charger() dit déjà que le serveur ne répond pas.
  }
}

$("btn-verifier").addEventListener("click", () => lancer("verifier"));
$("btn-installer").addEventListener("click", () => lancer("installer"));
$("btn-signature").addEventListener("click", ouvrirAssistant);
boutons();
reprendre().then(charger);
