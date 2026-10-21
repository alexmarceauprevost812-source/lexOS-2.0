/* LexOS · ⬆️ Envoyer le projet du Codex sur GitHub — sans git, avec GITHUB_TOKEN.
   ALEX : « capable d'envoyer nos projets à GitHub avec un token, capable
   d'enregistrer tous les fichiers en un seul clic ».
   · 1er envoi d'un projet : on choisit le dépôt (créé s'il n'existe pas).
   · Ensuite : UN clic sur « ⬆️ GitHub » — le fichier ouvert s'enregistre,
     puis TOUS les fichiers du projet partent, sans rien redemander.
     Maj+clic pour changer de dépôt.
   Le serveur (github_envoi.py) n'envoie jamais .env ni les copies .avant-codex. */
"use strict";

const GH = { ctrl: null, info: null };

function ouvrirGh() {
  $("#gh").hidden = false;
  $("#gh-progres").hidden = true; $("#gh-fini").hidden = true; $("#gh-go").hidden = false;
  $(".clone-boite", $("#gh")).classList.remove("erreur");
}
function fermerGh() {
  GH.ctrl?.abort();
  const b = $("#gh .clone-boite");
  b.classList.add("sort");
  setTimeout(() => { $("#gh").hidden = true; b.classList.remove("sort"); }, 300);
}

async function envoyerGithub(choisir) {
  if (!CX.projet) { toast("Choisis d'abord un projet", true); return; }
  if (CX.modifie) {                                  // « tout enregistrer » d'abord
    await sauverFichier();
    if (CX.modifie) return;
  }
  let info;
  try { info = await api(urlProjet(CX.projet) + "/github"); } catch (e) { toast("GitHub : " + e.message, true); return; }
  GH.info = info;
  if (!info.jeton) {
    toast("Ajoute ton jeton GitHub dans 🔑 Variables, sous le nom GITHUB_TOKEN", true);
    if (typeof ouvrirEnv === "function") ouvrirEnv();
    return;
  }
  ouvrirGh();
  $("#gh-sous").textContent = `projet « ${CX.projet} » · tous ses fichiers, sauf .env`;
  $("#gh-depot").value = info.lien?.depot || info.propose || CX.projet;
  $("#gh-message").value = "";
  $("#gh-jeton").textContent = info.lien?.depot ? `🔗 lié à ${info.lien.depot}` : "🔐 GITHUB_TOKEN trouvé";
  //  Déjà lié, et pas de Maj+clic : on part tout de suite — le « un seul clic ».
  if (info.lien?.depot && !choisir) lancerGh();
  else setTimeout(() => { $("#gh-depot").focus(); $("#gh-depot").select(); }, 250);
}

async function lancerGh() {
  const depot = $("#gh-depot").value.trim();
  if (!depot) { $("#gh-depot").focus(); return; }
  $("#gh-go").hidden = true; $("#gh-fini").hidden = true; $("#gh-progres").hidden = false;
  $("#gh-barre").style.width = "6%"; $("#gh-etat").textContent = "connexion à GitHub…";
  const boite = $("#gh .clone-boite"); boite.classList.add("travail"); boite.classList.remove("erreur");
  GH.ctrl = new AbortController();
  let fin = null, erreur = null;
  try {
    const r = await fetch(urlProjet(CX.projet) + "/github", {
      method: "POST", headers: { "Content-Type": "application/json" }, signal: GH.ctrl.signal,
      body: JSON.stringify({ depot, message: $("#gh-message").value.trim(), prive: $("#gh-prive").checked }),
    });
    if (!r.ok || !r.body) { const d = await r.json().catch(() => ({})); throw new Error(d.erreur || "Erreur " + r.status); }
    const lec = r.body.getReader(), dec = new TextDecoder(); let tampon = "";
    for (;;) {
      const { value, done } = await lec.read(); if (done) break;
      tampon += dec.decode(value, { stream: true });
      const lignes = tampon.split("\n"); tampon = lignes.pop();
      for (const l of lignes) {
        let ev; try { ev = JSON.parse(l); } catch { continue; }
        if (ev.type === "etape") $("#gh-etat").textContent = ev.texte;
        if (ev.type === "fichier") {
          $("#gh-etat").textContent = `envoi ${ev.n}/${ev.total} · ${ev.chemin}`;
          $("#gh-barre").style.width = Math.max(8, Math.round(90 * ev.n / ev.total)) + "%";
        }
        if (ev.type === "fin") fin = ev;
        if (ev.type === "erreur") erreur = ev.texte;
      }
    }
  } catch (e) {
    erreur = e.name === "AbortError" ? null : e.message;
  }
  boite.classList.remove("travail");
  $("#gh-progres").hidden = true;
  if (fin) {
    $("#gh-barre").style.width = "100%";
    const quoi = fin.rien ? "Déjà à jour : rien n'a changé depuis le dernier envoi."
      : `${fin.envoyes} fichier${fin.envoyes > 1 ? "s" : ""} envoyé${fin.envoyes > 1 ? "s" : ""}`
        + (fin.retires ? `, ${fin.retires} retiré${fin.retires > 1 ? "s" : ""}` : "")
        + (fin.commit ? ` · commit ${echapper(fin.commit)}` : "") + (fin.cree ? " · dépôt créé" : "");
    $("#gh-fini").innerHTML = `✅ <b>${echapper(fin.depot)}</b><br>${quoi}<br><a href="${echapper(fin.url)}" target="_blank" rel="noopener">Ouvrir sur GitHub ↗</a>`;
    $("#gh-fini").hidden = false;
    $("#gh-jeton").textContent = `🔗 lié à ${fin.depot}`;
    toast(fin.rien ? "GitHub : déjà à jour ✔" : `Envoyé sur GitHub ✔ ${fin.depot}`);
    if (typeof etincelles === "function") etincelles($("#cx-github"), 24);
  } else if (erreur) {
    $("#gh-fini").innerHTML = `❌ ${echapper(erreur)}`;
    $("#gh-fini").hidden = false; $("#gh-go").hidden = false;
    boite.classList.add("erreur");
  } else {
    $("#gh-go").hidden = false;
  }
}

$("#cx-github").addEventListener("click", (e) => envoyerGithub(e.shiftKey));
$("#gh-form").addEventListener("submit", (e) => { e.preventDefault(); lancerGh(); });
$("#gh-fermer").addEventListener("click", fermerGh);
$("#gh").addEventListener("mousedown", (e) => { if (e.target.id === "gh") fermerGh(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#gh").hidden) fermerGh(); });

/* ◧ Le Codex à DROITE de l'éditeur (écran divisé en deux) ou en bas.
   ALEX : « au lieu d'avoir le menu en bas de l'écran, le mettre à droite ».
   À droite par défaut ; la poignée entre les deux se glisse, et la largeur
   comme la disposition sont gardées. */
(() => {
  const vue = $("#vue-codex"), poignee = $("#cx-poignee"), bouton = $("#cx-disposition");
  const poser = (cote) => {
    vue.classList.toggle("cote", cote);
    bouton.textContent = cote ? "⬓" : "◧";
    bouton.title = cote ? "Mettre le Codex en bas" : "Mettre le Codex à droite (écran divisé en deux)";
  };
  const largeur = (px) => {
    const max = Math.max(320, vue.clientWidth * .7);
    const l = Math.round(Math.max(300, Math.min(max, px)));
    vue.style.setProperty("--cx-ia-l", l + "px");
    return l;
  };
  poser(mem.lire("lexos-codex-cote", "1") !== "0");
  const gardee = parseInt(mem.lire("lexos-codex-largeur", "0"), 10);
  if (gardee > 0) vue.style.setProperty("--cx-ia-l", gardee + "px");
  bouton.addEventListener("click", () => {
    const cote = !vue.classList.contains("cote");
    poser(cote); mem.ecrire("lexos-codex-cote", cote ? "1" : "0");
  });
  poignee.addEventListener("pointerdown", (e) => {
    if (!vue.classList.contains("cote")) return;
    e.preventDefault();
    poignee.setPointerCapture(e.pointerId);
    vue.classList.add("glisse");
    const droite = $(".cx-centre", vue).getBoundingClientRect().right;
    const bouger = (ev) => largeur(droite - ev.clientX);
    const lacher = (ev) => {
      vue.classList.remove("glisse");
      mem.ecrire("lexos-codex-largeur", String(largeur(droite - ev.clientX)));
      poignee.removeEventListener("pointermove", bouger);
      poignee.removeEventListener("pointerup", lacher);
    };
    poignee.addEventListener("pointermove", bouger);
    poignee.addEventListener("pointerup", lacher);
  });
  poignee.addEventListener("dblclick", () => { vue.style.removeProperty("--cx-ia-l"); mem.ecrire("lexos-codex-largeur", "0"); });
})();
