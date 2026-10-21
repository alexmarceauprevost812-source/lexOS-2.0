// LexOS Pilotes — interface. Lit /api/etat, lance les tâches, suit /api/tache.
"use strict";

const $ = (id) => document.getElementById(id);
const esc = (t) => String(t ?? "—").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

let suivi = null;

function depuis(secondes, maintenant) {
  if (!secondes) return "jamais vérifié";
  const m = Math.round((maintenant - secondes) / 60);
  if (m < 1) return "vérifié à l'instant";
  if (m < 60) return `vérifié il y a ${m} min`;
  const h = Math.round(m / 60);
  if (h < 48) return `vérifié il y a ${h} h`;
  return `vérifié il y a ${Math.round(h / 24)} jours`;
}

function afficherEtat(e) {
  // --- Les cartes ----------------------------------------------------------
  $("cartes").innerHTML = e.cartes.length
    ? e.cartes.map((c) => `
        <div class="ligne">
          <span><span class="puce">${esc(c.marque)}</span> <span class="nom">${esc(c.nom)}</span></span>
          <span class="doux">pilote : ${esc(c.pilote || "aucun")}</span>
        </div>`).join("")
    : `<div class="ligne doux">Aucune carte détectée (lspci absent ?)</div>`;

  // --- Le pilote ------------------------------------------------------------
  const nv = e.nvidia, k = e.noyau;
  const lignes = [];
  if (e.cartes.some((c) => c.marque === "NVIDIA")) {
    lignes.push(["NVIDIA chargé", nv.version || "non chargé"]);
    lignes.push(["Paquet installé", nv.paquet]);
    lignes.push(["Branche épinglée", nv.branche_epinglee ? `${nv.branche_epinglee}.x` : "aucune (la plus récente)"]);
    lignes.push(["Module pour le prochain démarrage",
      k.module_nvidia_plus_recent ? '<span class="bon">✓ présent</span>' : '<span class="mal">✗ absent</span>', true]);
  }
  lignes.push(["Mesa", e.mesa]);
  lignes.push(["Noyau en service", k.en_service]);
  if (k.plus_recent && k.plus_recent !== k.en_service) lignes.push(["Noyau au prochain démarrage", k.plus_recent]);
  lignes.push(["Secure Boot", e.secure_boot === null ? "—" : e.secure_boot ? "actif" : "inactif"]);
  $("pilote").innerHTML = lignes.map(([a, b, brut]) =>
    `<dt>${esc(a)}</dt><dd>${brut ? b : esc(b)}</dd>`).join("");

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
  $("verifie").textContent = depuis(e.verifie_le, e.maintenant);
  const maj = e.mises_a_jour;
  $("maj").innerHTML = maj.length
    ? maj.map((p) => `
        <div class="ligne">
          <span class="nom">${esc(p.paquet)}</span>
          <span class="doux">${esc(p.installe)} → <span class="bon">${esc(p.cible)}</span> · ${esc(p.source)}</span>
        </div>`).join("")
    : `<div class="ligne"><span class="puce bon">À jour</span><span class="doux">Rien à installer pour la carte graphique.</span></div>`;
  $("btn-installer").disabled = !maj.length || suivi !== null;
  $("btn-installer").textContent = maj.length ? `Mettre à jour (${maj.length})` : "Mettre à jour les pilotes";
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
  const r = await fetch("/api/assistant-signature", { method: "POST", headers: { "X-LexOS": "1" } });
  const rep = await r.json();
  afficherResultat(rep.lance
    ? { ok: true, message: "L'assistant s'est ouvert dans un terminal." }
    : { ok: false, message: rep.message || "Impossible d'ouvrir l'assistant." });
}

async function charger() {
  try {
    const r = await fetch("/api/etat", { cache: "no-store" });
    afficherEtat(await r.json());
  } catch (err) {
    $("cartes").textContent = "Le serveur local ne répond pas.";
  }
}

function afficherResultat(res) {
  const boite = $("resultat");
  boite.hidden = false;
  boite.className = "note " + (res.ok ? "bon" : "mal");
  let html = esc(res.message || (res.ok ? "Terminé." : "Échec."));
  if (res.avertissements && res.avertissements.length) {
    boite.className = "note attention";
    html += "<ul>" + res.avertissements.map((a) => `<li>${esc(a)}</li>`).join("") + "</ul>";
  }
  boite.innerHTML = html;
}

async function lancer(action) {
  $("resultat").hidden = true;
  const journal = $("journal");
  journal.hidden = false;
  journal.textContent = action === "installer"
    ? "Une fenêtre va demander ton mot de passe…\n"
    : "Une fenêtre va demander ton mot de passe pour rafraîchir la liste…\n";
  $("btn-verifier").disabled = true;
  $("btn-installer").disabled = true;
  const r = await fetch("/api/" + action, { method: "POST", headers: { "X-LexOS": "1" } });
  const rep = await r.json();
  if (!rep.lance) {
    afficherResultat({ ok: false, message: rep.message });
    $("btn-verifier").disabled = false;
    return;
  }
  suivi = setInterval(async () => {
    const t = await (await fetch("/api/tache", { cache: "no-store" })).json();
    if (t.journal.length) {
      journal.textContent = t.journal.join("\n");
      journal.scrollTop = journal.scrollHeight;
    }
    if (!t.en_cours) {
      clearInterval(suivi);
      suivi = null;
      $("btn-verifier").disabled = false;
      if (t.resultat) afficherResultat(t.resultat);
      charger();
    }
  }, 800);
}

$("btn-verifier").addEventListener("click", () => lancer("verifier"));
$("btn-installer").addEventListener("click", () => lancer("installer"));
$("btn-signature").addEventListener("click", ouvrirAssistant);
charger();
