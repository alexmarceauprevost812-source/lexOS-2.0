/* =============================================================================
   IA locale — la page. Même patron que les Paramètres : elle N'EXÉCUTE RIEN.
   Elle demande, le pont Python décide, et la liste des actions possibles est
   fermée côté Python. Ce fichier peut être lu par n'importe qui : il ne
   contient aucun secret, et c'est voulu.
   ========================================================================== */
let etat = {};
let vueActive = "etat";
let enCours = false;

const esc = s => String(s ?? "").replace(/[&<>"]/g,
  c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

async function api(action, arg){
  try{
    const r = await fetch("/api/action", {method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action, arg})});
    const j = await r.json();
    if(!j.ok && j.erreur) toast("✗ " + j.erreur);
    if(j.ok && j.message)  toast(j.message);
    return j;
  }catch(e){ toast("✗ Le pont local ne répond pas"); return {ok:false}; }
}
async function chargeEtat(){
  try{ etat = await (await fetch("/api/etat")).json(); }catch(e){}
}
let toastT = null;
function toast(msg){
  const t = document.getElementById("toast");
  t.textContent = msg; t.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(()=>{ t.hidden = true; }, 3600);
}
function srow(titre, desc, droite){
  return `<div class="srow"><div><div class="t">${titre}</div>
    ${desc?`<div class="d">${desc}</div>`:""}</div>${droite||""}</div>`;
}
async function rafraichir(msg){ await chargeEtat(); rend(); if(msg) toast(msg); }

/* --- Écran 1 : le diagnostic ---------------------------------------------
   La règle qui vient de l'écran noir de la RTX 5060 : « GPU non disponible »
   ne sert à personne. Trois pannes, trois solutions, trois messages — et le
   bouton qui répare celle qu'on a, pas les deux autres. */
function vueEtat(){
  const d = etat.diagnostic || {}, c = d.carte || {}, p = d.pilote || {},
        b = d.backend || {}, m = etat.moteurs || {}, e = etat.espace || {};
  const ton = {ok:"ok","sans-backend":"att","backend-muet":"att",
               "sans-pilote":"att","sans-carte":"non"}[d.cas] || "att";

  const reparation = {
    "sans-backend": `<div class="row">
        <button class="btn" onclick="ajouteBackend('vulkan')">Ajouter le backend Vulkan</button>
        ${c.marque==="nvidia" ? `<button class="btn ghost" onclick="ajouteBackend('cuda')">…ou CUDA (NVIDIA seulement)</button>` : ""}
      </div>
      <p class="notice">Vulkan couvre NVIDIA, AMD et Intel du même coup et pèse
        peu. CUDA irait un peu plus vite, mais seulement sur du NVIDIA et pour
        des gigaoctets de bibliothèques.</p>`,
    "backend-muet": `<p class="notice">Ne réinstalle pas le backend : il est déjà
        là. Le manque est du côté du pilote — sa partie Vulkan. Sur NVIDIA c'est
        <code>libnvidia-gl</code>, sur AMD et Intel c'est
        <code>mesa-vulkan-drivers</code>. <code>vulkaninfo --summary</code> le
        dira en une ligne.</p>`,
    "sans-pilote": `<p class="notice">Le pilote s'installe depuis
        <b>Paramètres → Écrans</b>, ou avec <code>lexos gpu</code>. Sans lui, la
        carte est là mais ne peut rien faire.</p>`,
    "sans-carte": `<p class="notice">Rien n'est cassé : le moteur tournera sur
        le processeur. Compte 5 à 10 mots par seconde au lieu de 50 — un petit
        modèle (3B) reste tout à fait utilisable.</p>`,
    "ok": "",
  }[d.cas] || "";

  return `<h2>État de la machine</h2>
  <div class="sub">Ce que ce panneau vérifie avant de proposer quoi que ce soit</div>

  <div class="diag ${ton}">
    <div class="t">${esc(d.titre)}</div>
    <div class="d">${esc(d.detail)}</div>
  </div>
  ${reparation}

  ${srow("Carte graphique",
         c.presente ? esc(c.nom) + (c.vram_go ? ` — ${c.vram_go} Go` +
             (c.source?` (vu par ${esc(c.source)})`:"") : "")
                    : "Aucune carte dédiée trouvée",
         `<span class="etat ${c.presente?"ok":"abs"}">${c.presente?"détectée":"absente"}</span>`)}
  ${srow("Pilote",
         p.charge ? `Le module <b>${esc(p.nom)}</b> est chargé`
                  : "Aucun pilote chargé pour cette carte",
         `<span class="etat ${p.charge?"ok":"non"}">${p.charge?"chargé":"absent"}</span>`)}
  ${srow("Backend du moteur",
         b.paquet && b.paquet!=="aucun"
           ? `${esc(b.paquet)} — ${b.actif==="processeur"
                ? "installé, mais il ne répond pas" : "la carte servira"}`
           : "Aucun — le moteur utilisera le processeur",
         `<span class="etat ${b.actif==="processeur"?"att":"ok"}">${
            b.actif==="processeur" ? "processeur" : esc(b.actif)}</span>`)}
  ${srow("Espace libre",
         `${e.libre_go} Go dans ${esc(e.dossier)} — un modèle en pèse 4 à 5`,
         `<span class="etat ${e.libre_go>=8?"ok":(e.libre_go>=5?"att":"non")}">${e.libre_go} Go</span>`)}

  <h3>Moteurs</h3>
  ${srow("llama.cpp",
         m.llama ? "Installé — c'est le moteur de référence, en licence MIT"
                 : "Absent. Il vient de trixie-backports.",
         `<span class="etat ${m.llama?"ok":"abs"}">${m.llama?"prêt":"absent"}</span>`)}
  ${srow("Ollama",
         m.ollama ? (m.ollama_actif ? "Installé et en marche" : "Installé, à l'arrêt")
                  : "Pas installé — il n'est pas dans Debian, il s'installe par son script officiel",
         m.ollama ? `<span class="etat ${m.ollama_actif?"ok":"abs"}">${m.ollama_actif?"en marche":"arrêté"}</span>`
                  : `<button class="btn ghost" onclick="poseOllama()">Installer</button>`)}
  <p class="notice">Rien ne s'installe sans un clic : ni Ollama, ni un backend,
    ni un modèle. Et rien de ce que tu écris ici ne quitte la machine.</p>`;
}

/* --- Écran 2 : le catalogue ---------------------------------------------- */
function vueModeles(){
  const cat = etat.catalogue || {modeles:[]};
  const seulsLibres = (etat.reglages||{}).libres_seulement;
  const liste = cat.modeles.filter(m => !seulsLibres || m.libre);
  const inst = etat.installes || [];
  const dejaLa = n => inst.some(i => i.nom === n || i.nom.startsWith(n + ":"));

  const lignes = liste.map(m => {
    const v = m.verdict || {};
    const ton = {ok:"ok", limite:"att", non:"non"}[v.code] || "abs";
    const ref = (etat.moteurs||{}).ollama ? m.ollama : m.gguf;
    const moteur = (etat.moteurs||{}).ollama ? "ollama" : "llama";
    return `<tr>
      <td class="nom">${esc(m.nom)}<div class="note">${esc(m.note||"")}</div></td>
      <td>${m.taille_go} Go<div class="note">${esc(m.quant||"")}</div></td>
      <td class="${m.libre?"libre":"pasl"}">${m.libre?"✅":"⚠"} ${esc(m.licence)}
        <div class="note">${m.libre?"vraiment libre":"poids ouverts, pas libre"}</div></td>
      <td><span class="etat ${ton}">${esc(v.texte||"")}</span></td>
      <td>${dejaLa(m.ollama||m.id)
        ? `<span class="etat ok">installé</span>`
        : `<button class="btn ghost" onclick="tire('${esc(ref)}','${moteur}',${m.taille_go})">Télécharger</button>`}</td>
    </tr>`;
  }).join("");

  return `<h2>Modèles</h2>
  <div class="sub">Catalogue ${esc(cat.origine)}${cat.mis_a_jour?" — "+esc(cat.mis_a_jour):""}.
    Le verdict est calculé pour <b>cette</b> machine.</div>

  ${srow("N'afficher que les modèles vraiment libres",
         "Décoché par défaut : t'informer, pas décider à ta place",
         `<button class="btn ${seulsLibres?"":"ghost"}" onclick="basculeLibres()">${seulsLibres?"activé":"désactivé"}</button>`)}

  <table><thead><tr>
    <th>Modèle</th><th>Taille</th><th>Licence</th><th>Sur ta carte</th><th></th>
  </tr></thead><tbody>${lignes || `<tr><td colspan="5">Catalogue vide.</td></tr>`}</tbody></table>

  <h3>Déjà sur la machine</h3>
  ${inst.length ? inst.map(i => srow(esc(i.nom), `${i.taille_go} Go — ${esc(i.moteur)}`,
      `<button class="btn ghost" onclick="choisit('${esc(i.nom)}')">Utiliser</button>`)).join("")
    : `<p class="notice">Aucun modèle installé pour l'instant. C'est normal :
        LexOS n'en livre aucun. Un modèle pèse 4 à 5 Go, sa licence n'est
        souvent pas libre, et celui de cette année sera vieux l'an prochain.</p>`}

  <p class="notice"><b>« Poids ouverts » n'est pas « open source ».</b> Ouvert
    veut dire qu'on peut télécharger le fichier. Libre veut dire qu'on peut
    s'en servir pour n'importe quoi, sans permission. La colonne Licence dit
    lequel des deux — et les vraiment libres sont en haut.</p>`;
}

/* --- Écran 3 : la discussion --------------------------------------------- */
function vueParler(){
  const r = etat.reglages || {}, m = etat.moteurs || {};
  const pret = (etat.installes||[]).length > 0 || m.ollama_actif;
  return `<h2>Discussion</h2>
  <div class="sub">${pret
    ? `Modèle : <b>${esc(r.modele || (etat.installes[0]||{}).nom || "le premier trouvé")}</b>
       — tout se passe sur cette machine, rien ne part sur internet.`
    : "Aucun modèle n'est prêt. Passe par « Modèles » pour en télécharger un."}</div>
  <div id="fil"></div>
  <div class="row" style="align-items:flex-end">
    <textarea class="champ" id="q" placeholder="Pose ta question…"
      onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();envoie()}"></textarea>
    <button class="btn" id="btnEnv" onclick="envoie()" ${pret?"":"disabled"}>Envoyer</button>
  </div>
  <div class="row">
    <button class="btn ghost" onclick="collerMachine()">Joindre les infos de ma machine</button>
    <button class="btn ghost" onclick="decharge()">Décharger le modèle</button>
  </div>
  <p class="notice">« Joindre les infos de ma machine » colle la sortie
    d'<code>inxi</code> dans ta question — pratique avec une erreur de
    <code>lexos medecin</code> ou <code>lexos journal</code>. Comme le modèle
    tourne ici, ces informations ne sortent pas de la machine.</p>`;
}

/* --- Écran 4 : les réglages ---------------------------------------------- */
function vueReglages(){
  const r = etat.reglages || {}, e = etat.espace || {};
  const ctx = [2048,4096,8192,16384,32768].map(v =>
    `<option value="${v}"${v===r.contexte?" selected":""}>${v} jetons</option>`).join("");
  return `<h2>Réglages</h2><div class="sub">Où vivent les modèles, et comment le moteur tourne</div>

  <div class="srow" style="display:block">
    <div class="t" style="margin-bottom:8px">Dossier des modèles</div>
    <div class="row" style="align-items:center">
      <input class="champ" id="dos" value="${esc(r.dossier)}" spellcheck="false">
      <button class="btn" onclick="setDossier()">Changer</button>
    </div>
    <div class="d" style="margin-top:8px">Le réglage le plus important de cette
      fenêtre. Un double démarrage laisse parfois 40 Go en tout, et un modèle en
      pèse 5 : ça peut pointer vers un disque externe ou la partition Windows.
      <b>Ollama sera changé en même temps</b> — sinon il continuerait à remplir
      ton dossier personnel de son côté, et tu chercherais longtemps les
      gigaoctets disparus. Libre ici : ${e.libre_go} Go.</div>
  </div>

  ${srow("Taille de contexte",
         "Combien le modèle garde en tête. Monter coûte de la mémoire graphique.",
         `<select onchange="setContexte(this.value)">${ctx}</select>`)}
  ${srow("Démarrer avec la session", "Non — un moteur qui dort garde de la mémoire graphique pour rien",
         `<span class="etat abs">jamais</span>`)}

  <h3>Licences</h3>
  ${srow("llama.cpp", "Le moteur de référence — dans Debian, et il ne dépend de personne",
         `<span class="etat ok">MIT</span>`)}
  ${srow("Ollama", "La couche pratique par-dessus — pas dans Debian, script officiel",
         `<span class="etat ok">MIT</span>`)}
  ${srow("Les modèles", "Chacun le sien : la colonne Licence de l'écran Modèles le dit",
         `<span class="etat abs">au cas par cas</span>`)}
  <p class="notice">LexOS ne redistribue aucun modèle, donc n'endosse aucune
    licence de modèle. Les deux moteurs, eux, sont en MIT : du vrai libre.</p>`;
}

/* --- Actions -------------------------------------------------------------- */
async function poseOllama(){
  const r = await api("installer-ollama");
  if(r.ok) toast("Une fenêtre s'ouvre — tu y verras ce qui s'installe.");
}
async function ajouteBackend(q){
  const r = await api("installer-backend", q);
  if(r.ok) toast("Une fenêtre s'ouvre pour l'installation.");
}
async function tire(ref, moteur, taille){
  const r = await api("telecharger", {ref, moteur, taille_go: taille});
  if(r.ok) toast("Téléchargement lancé dans une fenêtre — " + taille + " Go.");
}
async function choisit(nom){
  const r = await api("modele", nom);
  await rafraichir(r.ok ? "Modèle courant : " + nom : null);
}
async function basculeLibres(){
  await api("libres", (etat.reglages||{}).libres_seulement ? "off" : "on");
  await rafraichir();
}
async function setContexte(v){
  const r = await api("contexte", String(v));
  await rafraichir(r.ok ? "Contexte : " + v + " jetons" : null);
}
async function setDossier(){
  const v = document.getElementById("dos").value.trim();
  if(!v){ toast("Il faut un chemin"); return; }
  const r = await api("dossier", v);
  await rafraichir(r.ok ? null : null);
}
async function decharge(){
  const r = await api("decharger");
  if(r.ok) toast("Mémoire graphique rendue.");
}
async function collerMachine(){
  const r = await api("machine");
  if(!r.ok || !r.texte) return;
  const q = document.getElementById("q");
  q.value = (q.value ? q.value + "\n\n" : "") + "Voici ma machine :\n" + r.texte;
  q.focus();
}

/*  La réponse arrive mot par mot. Un modèle local met dix à trente secondes :
    servi d'un bloc à la fin, l'écran a l'air planté tout ce temps-là — et on
    ferme la fenêtre avant la réponse. */
async function envoie(){
  if(enCours) return;
  const q = document.getElementById("q");
  const question = (q.value || "").trim();
  if(!question){ toast("Écris ta question"); return; }
  const fil = document.getElementById("fil");
  fil.insertAdjacentHTML("beforeend",
    `<div class="msg moi"><b>Toi</b>\n${esc(question)}</div>`);
  const bloc = document.createElement("div");
  bloc.className = "msg lui";
  bloc.innerHTML = "<b>Le modèle</b>\n";
  fil.appendChild(bloc);
  fil.scrollTop = fil.scrollHeight;
  q.value = ""; enCours = true;
  document.getElementById("btnEnv").disabled = true;

  try{
    const r = await fetch("/api/discussion", {method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({question})});
    const lect = r.body.getReader();
    const dec = new TextDecoder();
    for(;;){
      const {done, value} = await lect.read();
      if(done) break;
      bloc.appendChild(document.createTextNode(dec.decode(value, {stream:true})));
      fil.scrollTop = fil.scrollHeight;
    }
  }catch(e){
    bloc.appendChild(document.createTextNode("\n[la réponse s'est interrompue]"));
  }finally{
    enCours = false;
    const b = document.getElementById("btnEnv");
    if(b) b.disabled = false;
  }
}

/* --- Rendu ---------------------------------------------------------------- */
function rend(){
  const vues = {etat:vueEtat, modeles:vueModeles, parler:vueParler,
                reglages:vueReglages};
  document.getElementById("contenu").innerHTML = (vues[vueActive] || vueEtat)();
  document.querySelectorAll(".onglet").forEach(b =>
    b.classList.toggle("on", b.dataset.vue === vueActive));
}
document.addEventListener("click", ev => {
  const o = ev.target.closest(".onglet");
  if(!o) return;
  vueActive = o.dataset.vue; rend();
});
(async () => { await chargeEtat(); rend(); })();
