"use strict";
/* Paramètres LexOS — la même barre latérale que la démo (SETTINGS_NAV),
   branchée sur l'API locale servie par settings.py. */

const NAV = [
  {grp:"Réseau", items:[
    ["wifi","📶","Wi-Fi"], ["reseau","🌐","Réseau"], ["bluetooth","🅱","Bluetooth"]]},
  {grp:"Matériel", items:[
    ["ecrans","🖥","Écrans"], ["son","🔊","Son"], ["energie","🔋","Énergie"],
    ["usb","🔌","Appareils USB"], ["mac","🍎","Mac (Apple)"]]},
  {grp:"Personnalisation", items:[
    ["apparence","🎨","Apparence"], ["bureau","🖼","Bureau LexOS"],
    ["multitaches","🗔","Multi-tâches"], ["applications","🧩","Applications"],
    ["notifications","🔔","Notifications"], ["recherche","🔍","Recherche"]]},
  {grp:"Comptes", items:[
    ["comptes","👤","Comptes en ligne"], ["partage","📤","Partage"],
    ["bienetre","🌱","Bien-être numérique"]]},
  {grp:"Périphériques", items:[
    ["souris","🖱","Souris et pavé tactile"], ["couleurs","🌈","Gestion des couleurs"],
    ["imprimantes","🖨","Imprimantes"], ["amovibles","💾","Supports amovibles"],
    ["tablette","🖊","Tablette graphique"]]},
  {grp:"Système", items:[
    ["confidentialite","🛡","Confidentialité et sécurité"], ["maj","⬆","Mises à jour"],
    ["accessibilite","♿","Accessibilité"], ["utilisateurs","🧑‍💻","Utilisateurs"],
    ["region","🌍","Région et langue"], ["clavier","⌨","Clavier"],
    ["datetime","🕒","Date et heure"], ["defaut","🧭","Applications par défaut"],
    ["distant","🖥","Bureau à distance"], ["apropos","◆","À propos"]]},
];

const ACCENTS = {orange:"#E8590C", "orange-rouge":"#D97757", bleu:"#1A5FB4",
                 rouge:"#C4211E", vert:"#1F8F4E", gris:"#8A8A8A",
                 violet:"#8B5CF6", neon:"#39FF14"};

/*  Les DEUX styles mis en avant, en haut de la section Apparence. Les sept
    pastilles restent en dessous pour qui veut fouiller, mais l'immense
    majorité du temps le choix se résume à ces deux-là — et une rangée de
    pastilles sans nom ne dit pas laquelle est laquelle. */
const STYLES = [
  ["orange",       "Classique",      "L'orange franc de LexOS"],
  ["orange-rouge", "Orange et rouge","Du terracotta au rouge brique"],
];

/*  Les polices sont montrées DANS leur propre police : lire le mot
    « Manuscrite » écrit à la main dit en un coup d'oeil ce que ça donnera,
    là où une liste de noms tous rendus pareil ne dit rien du tout.
    « Patrick Hand » est la seule embarquée par LexOS (OFL, dans
    /usr/share/fonts/truetype/lexos) — les autres sont des alias génériques
    que fontconfig sait toujours résoudre. */
const POLICES = [
  ["defaut",     "Défaut",     "system-ui,sans-serif"],
  ["classique",  "Classique",  "'Noto Serif',Georgia,serif"],
  ["mono",       "Machine",    "ui-monospace,monospace"],
  ["manuscrite", "Manuscrite", "'Patrick Hand',cursive"],
];
const LANGUES = [
  ["fr_CA.UTF-8","Français (Québec)"], ["fr_FR.UTF-8","Français (France)"],
  ["en_US.UTF-8","English (US)"], ["en_CA.UTF-8","English (Canada)"],
  ["en_GB.UTF-8","English (UK)"], ["es_ES.UTF-8","Español (España)"],
  ["es_MX.UTF-8","Español (México)"], ["de_DE.UTF-8","Deutsch"],
  ["it_IT.UTF-8","Italiano"], ["pt_BR.UTF-8","Português (Brasil)"],
  ["ru_RU.UTF-8","Русский"], ["zh_CN.UTF-8","中文（简体）"],
  ["ja_JP.UTF-8","日本語"], ["ko_KR.UTF-8","한국어"], ["ar_SA.UTF-8","العربية"],
];

let etat = {perf:"medium", theme:"sombre", accent:"orange", police:"defaut",
            avion:"off", hote:"", version:"", noyau:""};
let sectionActive = "wifi";

/* --- API ------------------------------------------------------------------ */
async function api(action, arg){
  try{
    const r = await fetch("/api/action", {method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action, arg})});
    const j = await r.json();
    if(!j.ok && j.erreur) toast("✗ " + j.erreur);
    return j;
  }catch(e){ toast("✗ Le pont local ne répond pas"); return {ok:false}; }
}
async function chargeEtat(){
  try{ etat = Object.assign(etat, await (await fetch("/api/etat")).json()); }
  catch(e){}
}

let toastT = null;
function toast(msg){
  const t = document.getElementById("toast");
  t.textContent = msg; t.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(()=>{ t.hidden = true; }, 2600);
}

/* --- Briques d'interface -------------------------------------------------- */
const esc = s => String(s).replace(/[&<>"]/g,
  c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

function srow(titre, desc, droite){
  return `<div class="srow"><div><div class="t">${titre}</div>
    ${desc?`<div class="d">${desc}</div>`:""}</div>${droite||""}</div>`;
}
function sw(on, onclick){
  return `<div class="sw${on?" on":""}" onclick="${onclick}"><i></i></div>`;
}
/*  LE COMPTE-TOURS DE PERFORMANCE, repris TEL QUEL de la démo web.
    C'est le même dessin, le même cadran, la même aiguille : la démo est le
    cahier des charges, et un réglage qui n'a pas la même tête des deux
    côtés n'est pas le même réglage aux yeux de celui qui s'en sert. */
const PERF_LABEL = {petit:"Petit — machine modeste, autonomie maximale",
  medium:"Médium — équilibre, réglage par défaut",
  performant:"Performant — priorité à la vitesse",
  max:"Performance max — tout à fond, secteur recommandé"};

/* --- Compte-tours de performance ----------------------------------------
   Un vrai cadran plutôt qu'une image figée : seule l'aiguille tourne, et la
   transition CSS la fait BALAYER jusqu'à la nouvelle valeur au lieu de sauter.
   Échelle 0-9, comme un compte-tours : petit 2 · medium 4 · performant 6 ·
   max 9, zone rouge à partir de 8. */
const PERF_RPM = {petit:2, medium:4, performant:6, max:9};
const G_A0 = -125, G_A1 = 125, G_VMAX = 9;
function gaugeAngle(v){ return G_A0 + (G_A1-G_A0)*(v/G_VMAX); }
function gaugePt(a, r){
  const t=(a-90)*Math.PI/180;
  return [256+r*Math.cos(t), 256+r*Math.sin(t)];
}
function gaugeArc(v0, v1, r){
  const [x0,y0]=gaugePt(gaugeAngle(v0),r), [x1,y1]=gaugePt(gaugeAngle(v1),r);
  return `M ${x0.toFixed(1)} ${y0.toFixed(1)} A ${r} ${r} 0 0 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`;
}
function gaugeDial(){
  let tk="", nb="";
  for(let i=0;i<=9;i++){
    const a=gaugeAngle(i);
    const [x0,y0]=gaugePt(a,126), [x1,y1]=gaugePt(a,152);
    tk+=`<line x1="${x0.toFixed(1)}" y1="${y0.toFixed(1)}" x2="${x1.toFixed(1)}" y2="${y1.toFixed(1)}" stroke-width="13"/>`;
    const [mx,my]=gaugePt(a,100);
    nb+=`<text x="${mx.toFixed(1)}" y="${(my+13).toFixed(1)}" text-anchor="middle">${i}</text>`;
    if(i<9){
      const a2=gaugeAngle(i+0.5);
      const [u0,v0]=gaugePt(a2,139), [u1,v1]=gaugePt(a2,152);
      tk+=`<line x1="${u0.toFixed(1)}" y1="${v0.toFixed(1)}" x2="${u1.toFixed(1)}" y2="${v1.toFixed(1)}" stroke-width="7"/>`;
    }
  }
  return `<path d="${gaugeArc(0,9,150)}" fill="none" stroke="currentColor" stroke-width="11" stroke-linecap="round" opacity=".35"/>`+
         `<path d="${gaugeArc(8,9,150)}" fill="none" stroke="#FF3B30" stroke-width="11" stroke-linecap="round"/>`+
         `<g stroke="currentColor" stroke-linecap="round" opacity=".85">${tk}</g>`+
         `<g fill="currentColor" opacity=".85" font-family="ui-monospace,monospace" font-weight="700" font-size="38">${nb}</g>`;
}
//  size : côté en pixels. profil : clé de PERF_RPM (défaut : profil courant).
function perfGauge(size, profil){
  const v = PERF_RPM[profil || state.perf] ?? 4;
  return `<svg class="gauge" viewBox="0 0 512 512" width="${size}" height="${size}" aria-hidden="true">`+
    gaugeDial()+
    `<g class="needle" style="transform:rotate(${gaugeAngle(v)}deg)">`+
      `<line x1="256" y1="284" x2="256" y2="138" stroke="currentColor" stroke-width="17" stroke-linecap="round"/>`+
    `</g>`+
    `<circle cx="256" cy="256" r="25" fill="currentColor"/>`+
    `<circle cx="256" cy="256" r="10" fill="var(--bg)"/>`+
  `</svg>`;
}

/*  Deux indicateurs qui valent mieux qu'un nombre seul : on lit une force
    de signal ou une charge d'un coup d'oeil, sans convertir mentalement.
    Pas d'image ni de police d'icônes — quatre <i> et un peu de CSS. */
function barres(force){
  const n = force >= 75 ? 4 : force >= 50 ? 3 : force >= 25 ? 2 : force > 0 ? 1 : 0;
  return `<div class="barres" title="${force} %">` +
    [1,2,3,4].map(i=>`<i class="${i<=n?"on":""}"></i>`).join("") + `</div>`;
}
function jauge(pct){
  const p = Math.max(0, Math.min(100, pct));
  return `<div class="jauge" title="${p} %"><span style="width:${p}%"></span></div>`;
}
/*  Un menu déroulant, avec le même habillage que le reste. La valeur part
    vers la machine au changement ; « 0 » veut dire « jamais ». */
/*  Le disque dur, d'après l'image fournie par Alex. Même dessin que la démo
    web — la démo est le cahier des charges, et une icône qui n'a pas la même
    tête des deux côtés n'est pas la même icône pour celui qui la regarde.
    viewBox serré sur le dessin : sinon l'icône flotte dans un carré vide et
    paraît deux fois plus petite que sa boîte. */
/*  La clé USB — même famille de dessin que le disque dur : silhouette pleine,
    trait noir franc, deux gris. Elles se ressemblent assez pour aller
    ensemble, et diffèrent assez pour qu'on ne les confonde pas d'un coup
    d'oeil — ce qui compte quand le bouton d'à côté formate. */
function usbGlyph(size){
  return `<svg viewBox="60 150 392 212" width="${size}" height="${size}" aria-hidden="true">`+
    `<g stroke="#111827" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">`+
      `<rect x="150" y="176" width="286" height="160" rx="30" fill="#E8590C"/>`+
      `<rect x="76" y="212" width="80" height="88" rx="12" fill="#94A3B8"/>`+
      `<rect x="176" y="206" width="150" height="100" rx="16" fill="#F1F5F9"/>`+
    `</g>`+
  `</svg>`;
}
function diskGlyph(size){
  return `<svg viewBox="96 18 320 476" width="${size}" height="${size}" aria-hidden="true">`+
    `<g stroke="#111827" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">`+
      `<rect x="104" y="26" width="304" height="460" rx="40" fill="#6B7280"/>`+
      `<circle cx="252" cy="188" r="132" fill="#CBD5E1"/>`+
      `<path d="M 120 258 L 120 464 L 336 464 Z" fill="#CBD5E1"/>`+
      `<path d="M 306 206 L 176 300 L 214 344 Z" fill="#F1F5F9"/>`+
      `<circle cx="252" cy="188" r="44" fill="#94A3B8"/>`+
    `</g>`+
    `<g fill="#111827">`+
      `<circle cx="252" cy="166" r="8.5"/><circle cx="252" cy="210" r="8.5"/>`+
      `<circle cx="230" cy="188" r="8.5"/><circle cx="274" cy="188" r="8.5"/>`+
      `<circle cx="196" cy="322" r="11"/><circle cx="156" cy="426" r="11"/>`+
    `</g>`+
  `</svg>`;
}
function menu(quoi, valeur, choix){
  return `<select onchange="setMinutes('${quoi}', this.value)"
    style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
           border-radius:6px;padding:6px 8px;font:inherit">` +
    choix.map(([v,t])=>`<option value="${v}"${String(v)===String(valeur)?" selected":""}>${t}</option>`).join("") +
    `</select>`;
}
function btnOuvrir(section, libelle){
  return `<div class="row"><button class="btn" onclick="ouvrir('${section}')">
    ${libelle || "Ouvrir l'outil complet"}</button></div>`;
}

/* --- Actions déclenchées par la page ------------------------------------- */
async function ouvrir(section){ await api("ouvrir", section); }

/*  Après chaque changement on RELIT l'état depuis la machine au lieu de le
    deviner. Un interrupteur qui bascule à l'écran alors que la commande a
    échoué est un mensonge — et c'est comme ça qu'on croit avoir éteint le
    Wi-Fi sans l'avoir éteint. */
async function rafraichir(msg){
  await chargeEtat();
  rendSection();
  if(msg) toast(msg);
}
async function basculeWifi(){
  const r = await api("wifi-radio", "toggle");
  await rafraichir(r.ok ? "Wi-Fi basculé" : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeMuet(){
  const r = await api("son-muet", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
/*  Le nombre à côté du curseur suit le doigt SANS parler à la machine :
    envoyer une commande à chaque pixel de glissement noierait pactl sous les
    appels. On n'agit qu'au relâchement (onchange), et l'aperçu garde l'écran
    vivant entre-temps. */
function apercuVolume(v){
  const z = document.getElementById("volVal");
  if(z) z.textContent = v + " %";
}
function apercuLum(v){
  const z = document.getElementById("lumVal");
  if(z) z.textContent = v + " %";
}
async function setVolume(v){
  const r = await api("son-volume", String(v));
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function setDock(d){
  const r = await api("dock", d);
  await rafraichir(r.ok ? "Dock : " + d : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeBarre(){
  const r = await api("barre-cachee", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeCrt(){
  const r = await api("crt", "toggle");
  await rafraichir(r.ok ? "À la prochaine ouverture de session" : "Échec : " + (r.erreur || "commande refusée"));
}
async function setBureaux(sens){
  const r = await api("bureaux", sens);
  await rafraichir(r.ok ? null : (r.erreur || "commande refusée"));
}
async function vaBureau(n){
  const r = await api("bureau-va", String(n));
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function actionUsb(quoi){
  const r = await api("usb", quoi);
  if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
}
async function ejecte(dev){
  const r = await api("usb", "ejecter:" + dev);
  await rafraichir(r.ok ? "Tu peux débrancher" : "Échec : " + (r.erreur || "appareil occupé"));
}
async function basculeBluetooth(){
  const r = await api("bluetooth-radio", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeDimBat(){
  const r = await api("energie-dim-batterie", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function setMinutes(quoi, v){
  const r = await api("energie-delai", quoi + ":" + v);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeSouris(quoi){
  const r = await api("souris", quoi);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeHeureAuto(){
  const r = await api("heure-auto", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "mot de passe refusé"));
}
async function basculeAvion(){
  const r = await api("avion", "toggle");
  if(r.ok){ etat.avion = etat.avion === "on" ? "off" : "on"; rendSection(); }
}
async function setPerf(p){
  const r = await api("perf", p);
  if(r.ok){ etat.perf = p; rendSection(); toast("Profil : " + p); }
}
async function setLum(n){ await api("lumiere", n); }
async function setTheme(t){
  const r = await api("theme", t);
  if(r.ok){ etat.theme = t; rendSection(); toast("Thème : " + t); }
}
async function setPolice(p){
  const r = await api("police", p);
  if(r.ok){ etat.police = p; rendSection(); toast("Police : " + p); }
}
async function setAccent(a){
  const r = await api("accent", a);
  if(r.ok){ etat.accent = a; rendSection(); toast("Accent : " + a); }
}
async function setDock(d){
  const r = await api("dock", d);
  if(r.ok) toast("Barre d'outils : " + d);
}
async function setFond(f){
  const r = await api("fond", f);
  if(r.ok) toast("Fond d'écran appliqué");
}
async function fondPerso(){
  const r = await api("fond-perso", "remplir");
  if(r.ok) toast("Fond d'écran appliqué");
}
/* Fonds animés : le nom part tel quel au moteur, qui le valide contre les
   scènes RÉELLEMENT présentes sur le disque avant de lancer quoi que ce soit. */
async function setFondAnime(nom){
  const r = await api("fond-anime", nom);
  if(r.ok) toast(nom === "off" ? "Fond animé retiré" : "Fond animé : " + nom);
  else toast(r.erreur || "Scène indisponible");
}
/* Capture d'écran → fond d'écran, en un seul geste. */
async function fondCapture(mode){
  const r = await api("fond-capture", mode);
  if(r.ok) toast(mode === "zone" ? "Cadre la zone à la souris…" : "Capture en cours…");
}
async function setLangue(l){
  const r = await api("langue", l);
  if(r.ok) toast("Langue changée — reconnecte-toi pour l'appliquer partout");
}
async function capture(mode){ await api("capture", mode); }

/* --- Sections ------------------------------------------------------------- */
function contenu(cle){
  switch(cle){
    case "wifi": {
      //  On montre l'ÉTAT avant les boutons : allumé ou non, sur quel réseau,
      //  avec quelle force. C'est ce qu'on vient vérifier neuf fois sur dix.
      const w = etat.wifi || {};
      const absent = w.radio === "absent";
      const allume = w.radio === "enabled";
      return `<h2>Wi-Fi</h2><div class="sub">Réseaux, connexion, mots de passe</div>
      ${absent
        ? `<p class="notice">Aucune carte Wi-Fi détectée sur cette machine.</p>`
        : srow("Wi-Fi", allume ? "Carte radio allumée" : "Carte radio éteinte",
               sw(allume, "basculeWifi()"))}
      ${allume && w.reseau
        ? srow("Réseau connecté", `${esc(w.reseau)} — signal ${w.signal} %`, barres(w.signal))
        : (allume ? srow("Réseau connecté", "Aucun — ouvre l'outil réseau pour en choisir un") : "")}
      ${btnOuvrir("wifi","Ouvrir l'outil réseau")}
      <p class="notice">En ligne de commande : <code>lexos wifi</code> ·
      <code>lexos net password "&lt;réseau&gt;"</code> pour un mot de passe oublié.</p>`;
    }
    case "reseau": return `<h2>Réseau</h2><div class="sub">Filaire, mode avion, VPN</div>
      ${srow("Mode avion","Coupe Wi-Fi, Bluetooth et données",
             sw(etat.avion==="on","basculeAvion()"))}
      ${btnOuvrir("reseau","Ouvrir l'outil réseau")}
      <p class="notice">VPN : <code>lexos vpn import fichier.ovpn</code> (OpenVPN) ou un
      <code>.conf</code> WireGuard, puis <code>lexos vpn connect "&lt;nom&gt;"</code>.</p>`;
    case "bluetooth": {
      const bt = etat.bluetooth;
      return `<h2>Bluetooth</h2><div class="sub">Appareils appairés</div>
      ${bt === null || bt === undefined
        ? `<p class="notice">Aucun contrôleur Bluetooth sur cette machine.</p>`
        : srow("Bluetooth", bt ? "Allumé, prêt à appairer" : "Éteint",
               sw(bt, "basculeBluetooth()"))}
      ${srow("Rechercher des appareils","Balayage et appairage")}
      ${btnOuvrir("bluetooth","Rechercher (lexos bt scan)")}`;
    }
    case "ecrans": {
      //  La question qu'on se pose devant cette section est « qu'est-ce qui
      //  est branché, et en quelle définition ? ». On y répond tout de suite.
      const ec = etat.ecrans || [];
      return `<h2>Écrans</h2><div class="sub">Disposition multi-écrans</div>
      ${ec.length
        ? ec.map(e=>srow(esc(e.nom) + (e.principal ? " — principal" : ""),
                         e.definition ? esc(e.definition) : "branchée, aucune image")).join("")
        : `<p class="notice">Aucune sortie vidéo lue (xrandr absent ou session Wayland).</p>`}
      ${srow("Étendre, dupliquer, écran principal","Résolution et disposition de chaque écran")}
      ${btnOuvrir("ecrans","Ouvrir Écrans")}`;
    }
    case "son": {
      const so = etat.son || {};
      const connu = so.volume >= 0;
      return `<h2>Son</h2><div class="sub">Volume, périphériques</div>
      ${connu ? srow("Sourdine", so.muet ? "Le son est coupé" : "Le son passe",
                     sw(so.muet, "basculeMuet()")) : ""}
      ${connu ? `<div class="srow"><div class="t">Volume de sortie</div>
        <div style="display:flex;align-items:center;gap:12px;flex:1;max-width:420px">
          <input type="range" min="0" max="100" value="${so.volume}"
                 style="flex:1;accent-color:var(--ac)"
                 oninput="apercuVolume(this.value)" onchange="setVolume(this.value)">
          <span id="volVal" style="min-width:44px;text-align:right;font-weight:600">${so.volume} %</span>
        </div></div>`
        : `<p class="notice">Volume illisible : pactl est absent.</p>`}
      ${so.casque ? srow("Casque audio","Branché — le son sort dans le casque") : ""}
      ${btnOuvrir("son","Ouvrir le mélangeur")}`;
    }
    case "energie": return `<h2>Énergie</h2><div class="sub">Profil de performance</div>
      ${(etat.batterie && etat.batterie.niveau >= 0)
        ? srow("Batterie", `${etat.batterie.niveau} %` +
               (etat.batterie.secteur ? " — branché sur le secteur" : " — sur batterie"),
               jauge(etat.batterie.niveau))
        : srow("Alimentation","Aucune batterie — machine de bureau")}
      <div class="row">${["petit","medium","performant","max"].map(p=>
        `<button class="btn ${p===etat.perf?"sel":"ghost"}" onclick="setPerf('${p}')">${p}</button>`).join("")}</div>
      <div style="display:flex;align-items:center;gap:18px;margin-top:12px">
        <span style="color:var(--ac)">${perfGauge(132, etat.perf)}</span>
        <div><div class="t" style="font-weight:600">${etat.perf} — ${(PERF_RPM[etat.perf]||4)}000 tr/min</div>
        <div class="d">${PERF_LABEL[etat.perf] || ""}</div></div>
      </div>
      <p class="notice">Chaque profil règle vraiment le gouverneur du processeur, zram,
      le compositing et les services (<code>lexos perf</code>).</p>

      <div class="srow" style="display:block;margin-top:16px">
        <div class="t" style="margin-bottom:6px">Luminosité de l'écran</div>
        <div style="display:flex;align-items:center;gap:12px">
          <input type="range" min="5" max="100" value="${etat.lumiere ?? 70}"
                 style="flex:1;accent-color:var(--ac)"
                 oninput="apercuLum(this.value)" onchange="setLum(this.value)">
          <span id="lumVal" style="min-width:44px;text-align:right;font-weight:600">${etat.lumiere ?? 70} %</span>
        </div>
      </div>
      ${srow("Baisser la luminosité sur batterie","Quand le secteur est débranché",
             sw(etat.energie && etat.energie.dimBat, "basculeDimBat()"))}
      ${srow("Éteindre l'écran après","L'écran s'éteint, la machine continue de tourner",
             menu("ecranOff", (etat.energie && etat.energie.ecranOff) || "10",
                  [["1","1 min"],["5","5 min"],["10","10 min"],["30","30 min"],["0","jamais"]]))}
      ${srow("Mise en veille après","La machine s'endort pour de bon",
             menu("veille", (etat.energie && etat.energie.veille) || "30",
                  [["15","15 min"],["30","30 min"],["60","60 min"],["120","120 min"],["0","jamais"]]))}
      <p class="notice">La luminosité est réglée pour de vrai —
      <code>lexos lumiere 60</code>, <code>lexos lumiere eco</code>, ou
      <code>lexos lumiere +10</code>. LexOS pilote le rétroéclairage quand la
      machine en a un ; sinon il assombrit l'image et le dit clairement, parce
      que ça n'économise alors aucune batterie.</p>
      ${btnOuvrir("energie","État détaillé (terminal)")}`;
    case "usb": {
      const app = etat.usb || [];
      return `<h2>Appareils USB</h2><div class="sub">Branchements détectés</div>
      ${app.length ? app.map(a=>`
        <div class="srow">
          <span style="width:56px;height:56px;display:flex;align-items:center;
                       justify-content:center;flex:none">${
            a.disque ? diskGlyph(46) : usbGlyph(44)}</span>
          <div style="flex:1">
            <div class="t">${esc(a.nom)} — ${esc(a.taille)}</div>
            <div class="d">${a.monte ? "Monté sur " + esc(a.monte)
                                     : "Branché, pas encore ouvert"} · ${esc(a.dev)}</div>
          </div>
          <button class="btn ghost" onclick="ejecte('${esc(a.dev)}')">Éjecter</button>
        </div>`).join("")
        : `<p class="notice">Aucun support amovible branché. Branche une clé ou un
           disque : il apparaîtra ici. Le disque système n'est jamais listé —
           le bouton d'à côté s'appelle « Formater ».</p>`}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Actions sur l'appareil</div>
        <div class="row">
          <button class="btn" onclick="actionUsb('vide-memoire')">Vide mémoire +</button>
          <button class="btn ghost" onclick="actionUsb('terminal')">Terminal de l'appareil</button>
          <button class="btn ghost" onclick="actionUsb('formater')">⚠ Formater…</button>
        </div>
      </div>
      <p class="notice"><code>lexos vide-memoire</code> copie en un clic tout le contenu
      d'un téléphone (MTP/iPhone) ou d'une clé. <code>lexos usb terminal</code> ouvre un
      terminal <b>sur le téléphone</b> (adb, débogage USB requis).
      <code>lexos format</code> formate une clé ou un téléphone — jamais le disque
      système, et seulement après confirmation explicite.</p>`;
    }
    case "mac": return `<h2>Mac (Apple)</h2><div class="sub">Wi-Fi Broadcom, ventilateurs, touches F1-F12</div>
      ${srow("Ce Mac","Classement du modèle et réglages propres au matériel Apple")}
      ${btnOuvrir("mac","Ouvrir l'outil Mac")}`;
    case "apparence": return `<h2>Apparence</h2><div class="sub">Thème, accent, barre d'outils</div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Thème du bureau</div>
        <div class="row">
          <button class="btn ${etat.theme==="sombre"?"sel":"ghost"}" onclick="setTheme('sombre')">🌑 Sombre — LexOS Noir</button>
          <button class="btn ${etat.theme==="clair"?"sel":"ghost"}" onclick="setTheme('clair')">☀ Clair — thème de jour</button>
        </div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Couleur de l'interface</div>
        <div class="row">${STYLES.map(([n,titre,desc])=>
          `<button class="btn ${n===etat.accent?"sel":"ghost"}" onclick="setAccent('${n}')"
             title="${desc}"><span class="pastille" style="background:${ACCENTS[n]}"></span>${titre}</button>`
          ).join("")}</div>
        <div class="sub" style="margin-top:6px">${
          STYLES.map(([,t,d])=>`${t} — ${d}`).join(" · ")}</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Autres couleurs</div>
        <div class="row">${Object.entries(ACCENTS).map(([n,c])=>
          `<button class="swatch${n===etat.accent?" sel":""}" style="background:${c}"
             title="${n}" onclick="setAccent('${n}')"></button>`).join("")}</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Police d'écriture</div>
        <div class="row">${POLICES.map(([n,titre,fam])=>
          `<button class="btn ${n===etat.police?"sel":"ghost"}" style="font-family:${fam}"
             onclick="setPolice('${n}')">${titre}</button>`).join("")}</div>
        <div class="sub" style="margin-top:6px">Les fenêtres déjà ouvertes gardent
          l'ancienne police — ferme-les et rouvre-les.</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Position du dock</div>
        <div class="row">${["droite","gauche","bas","haut"].map(d=>
          `<button class="btn ${d===etat.dock?"sel":"ghost"}" onclick="setDock('${d}')">${
            d.charAt(0).toUpperCase()+d.slice(1)}</button>`).join("")}</div>
      </div>
      ${srow("Masquer la barre d'outils","Elle glisse hors de l'écran ; la poignée du bord la ramène",
             sw(etat.barreCachee, "basculeBarre()"))}
      ${srow("Effets d'ouverture/fermeture (TV 1980)","Fenêtres façon téléviseur cathodique",
             sw(etat.crt, "basculeCrt()"))}
      ${btnOuvrir("apparence","Réglages fins (XFCE)")}
      <p class="notice">Les effets exigent une accélération 3D : sans elle,
      LexOS replie sur xfwm4 et le dit dans <code>lexos crt status</code>.
      Le changement s'applique à la prochaine ouverture de session.</p>`;
    case "bureau": return `<h2>Bureau LexOS</h2><div class="sub">Fond d'écran</div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Fond d'écran</div>
        <div class="row">
          <button class="btn ghost" onclick="setFond('defaut')">Défaut</button>
          <button class="btn ghost" onclick="setFond('secu')">Sécurité</button>
          <button class="btn ghost" onclick="setFond('demon')">LexOS 1.0</button>
          <button class="btn ghost" onclick="setFond('keyart')">Explorateur</button>
          <button class="btn" onclick="fondPerso()">🖼 Une image à moi…</button>
        </div>
      </div>

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Fonds animés</div>
        <div class="sub" style="margin-bottom:8px">Dessinés en direct, et figés
        tout seuls dès le passage sur batterie.</div>
        <div class="row">
          <button class="btn ghost" onclick="setFondAnime('code')">⌨ Le code s'écrit</button>
          <button class="btn ghost" onclick="setFondAnime('pluie')">🌧 Pluie</button>
          <button class="btn ghost" onclick="setFondAnime('braises')">🔥 Braises</button>
          <button class="btn ghost" onclick="setFondAnime('etoiles')">✨ Ciel</button>
          <button class="btn ghost" onclick="setFondAnime('atelier')">🛠 Atelier</button>
          <button class="btn" onclick="setFondAnime('off')">Revenir au fond fixe</button>
        </div>
      </div>

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Depuis une capture d'écran</div>
        <div class="sub" style="margin-bottom:8px">Prend une image de l'écran et
        la pose aussitôt en fond.</div>
        <div class="row">
          <button class="btn ghost" onclick="fondCapture('plein')">📷 Tout l'écran</button>
          <button class="btn ghost" onclick="fondCapture('zone')">✂ Une zone</button>
        </div>
      </div>

      <p class="notice">Aussi : clic droit sur une image dans Fichiers →
      « Définir comme fond d'écran », ou <code>lexos wallpaper ~/Images/photo.jpg</code>.
      Vidéo en fond : <code>lexos wallpaper video ~/Vidéos/boucle.mp4</code>.
      Pour fabriquer ton propre fond animé :
      <code>lexos wallpaper anime nouveau mon-fond</code> — un fichier de couches
      commenté, avec <code>… apercu mon-fond</code> pour voir avant de poser.</p>
      ${btnOuvrir("bureau","Réglages fins (XFCE)")}`;
    case "multitaches": {
      const b = etat.bureaux || {nb:1, courant:0, fenetres:[]};
      return `<h2>Multi-tâches</h2><div class="sub">Bureaux virtuels</div>
      ${srow("Bureaux virtuels",
             `${b.nb} bureau${b.nb>1?"x":""} en ce moment, 5 au maximum — ` +
             `plusieurs écrans sur le même écran. Tu es sur le bureau <b>${b.courant+1}</b>.`,
             `<div class="row" style="flex:none">` +
             Array.from({length:b.nb},(_,n)=>
               `<button class="btn ${n===b.courant?"sel":"ghost"}" onclick="vaBureau(${n})">${n+1}</button>`).join("") +
             (b.nb < 5 ? `<button class="btn ghost" title="Ajouter un bureau" onclick="setBureaux('plus')">+</button>` : "") +
             (b.nb > 1 ? `<button class="btn ghost" title="Enlever un bureau" onclick="setBureaux('moins')">−</button>` : "") +
             `</div>`)}
      ${b.fenetres && b.fenetres.length
        ? srow("Fenêtres par bureau",
               b.fenetres.map((n,i)=>`Bureau ${i+1} : ${n}`).join(" · "))
        : ""}
      ${btnOuvrir("multitaches","Ouvrir les réglages de bureaux")}
      <p class="notice"><b>Ctrl+Alt+←</b> et <b>Ctrl+Alt+→</b> passent au bureau
      précédent ou suivant, <b>Super+1</b> à <b>Super+${b.nb}</b> vont directement
      à l'un d'eux. Rien n'est fermé en changeant de bureau — les fenêtres sont
      mises de côté et retrouvées telles quelles.</p>`;
    }
    case "applications": return `<h2>Applications</h2><div class="sub">Applications par défaut</div>
      ${srow("Navigateur, courrier, gestionnaire de fichiers","Quelle application ouvre quoi")}
      ${btnOuvrir("applications")}
      <p class="notice">Firefox et Chromium sont installés. Google Chrome, lui,
      n'est pas libre : il ne peut pas être livré dans l'ISO. Son icône est
      quand même dans le dock — le premier clic l'installe depuis le dépôt
      officiel de Google (aussi : <code>lexos chrome</code>, ou
      <code>lexos install chrome</code>).</p>`;
    case "notifications": return `<h2>Notifications</h2><div class="sub">Alertes système</div>
      ${srow("Notifications","Position, durée, applications autorisées")}
      ${btnOuvrir("notifications")}`;
    case "recherche": return `<h2>Recherche</h2><div class="sub">Trouver une application</div>
      ${srow("Recherche d'applications","Super+S, ou le bouton Applications du panneau")}
      ${btnOuvrir("recherche","Ouvrir la recherche")}`;
    case "comptes": return `<h2>Comptes en ligne</h2><div class="sub">Google, Microsoft, Nextcloud…</div>
      <p class="notice">Pas encore disponible dans LexOS 1.0 — prévu pour une prochaine
      version. Les applications (Thunderbird, navigateur) gardent leurs propres comptes.</p>`;
    case "partage": return `<h2>Partage</h2><div class="sub">Fichiers, QR code, Bluetooth</div>
      ${srow("Envoyer vers un téléphone","QR code, KDE Connect, Bluetooth")}
      ${btnOuvrir("partage","Ouvrir Partager")}`;
    case "bienetre": return `<h2>Bien-être numérique</h2><div class="sub">Temps d'écran</div>
      <p class="notice">Pas encore disponible dans LexOS 1.0 — prévu pour une prochaine version.</p>`;
    case "souris": {
      const m = etat.souris || {};
      return `<h2>Souris et pavé tactile</h2><div class="sub">Vitesse, boutons, défilement</div>
      ${m.pave ? `
        ${srow("Taper pour cliquer","Une tape sur le pavé vaut un clic",
               sw(m.tape, "basculeSouris('tape')"))}
        ${srow("Défilement naturel","Le contenu suit le doigt, comme sur un téléphone",
               sw(m.inverse, "basculeSouris('inverse')"))}`
        : `<p class="notice">Aucun pavé tactile détecté — ces réglages ne
           concernent que les portables.</p>`}
      ${srow("Pointeur","Vitesse, gaucher/droitier, thème du curseur")}
      ${btnOuvrir("souris")}`;
    }
    case "couleurs": return `<h2>Gestion des couleurs</h2><div class="sub">Profils ICC</div>
      ${srow("Profils des écrans et imprimantes","Charger un profil ICC")}
      ${btnOuvrir("couleurs")}`;
    case "imprimantes": return `<h2>Imprimantes</h2><div class="sub">Appareils installés</div>
      ${srow("Imprimantes","Ajouter, retirer, imprimer une page de test")}
      ${btnOuvrir("imprimantes")}`;
    case "amovibles": return `<h2>Supports amovibles</h2><div class="sub">Clés, disques, cartes</div>
      ${srow("À l'insertion","Monter automatiquement, ouvrir le dossier")}
      ${btnOuvrir("amovibles")}`;
    case "tablette": return `<h2>Tablette graphique</h2><div class="sub">Stylet et boutons</div>
      ${srow("Tablette","Pression du stylet, boutons, zone active")}
      ${btnOuvrir("tablette")}`;
    case "confidentialite": return `<h2>Confidentialité et sécurité</h2><div class="sub">Pare-feu, antivirus, chiffrement</div>
      ${srow("Autodéfense","Pare-feu, antivirus, anti-intrusion, anti-rootkit")}
      ${btnOuvrir("confidentialite","Ouvrir Sécurité")}`;
    case "maj": return `<h2>Mises à jour</h2><div class="sub">Sécurité automatique, reste sur demande</div>
      ${srow("Mises à jour de sécurité","S'installent toutes seules (unattended-upgrades)")}
      ${btnOuvrir("maj","Vérifier maintenant (lexos doctor)")}`;
    case "accessibilite": return `<h2>Accessibilité</h2><div class="sub">Voir, entendre, taper</div>
      ${srow("Aides","Touches rémanentes, rebond, contraste")}
      ${btnOuvrir("accessibilite")}`;
    case "utilisateurs": return `<h2>Utilisateurs</h2><div class="sub">Comptes locaux</div>
      ${srow("lex","Principal, administrateur")}
      ${srow("invite","Invité — session limitée, sans mot de passe, sans droits admin")}
      ${btnOuvrir("utilisateurs","Détails (terminal)")}`;
    case "region": return `<h2>Région et langue</h2><div class="sub">Langue du système</div>
      <div class="srow"><div><div class="t">Langue</div>
        <div class="d">locales-all fournit déjà toutes les langues</div></div>
        <select onchange="if(this.value)setLangue(this.value)">
          <option value="">Choisir…</option>
          ${LANGUES.map(([v,l])=>`<option value="${v}">${esc(l)}</option>`).join("")}
        </select></div>
      <p class="notice">Reconnecte-toi (ou redémarre) pour l'appliquer partout.</p>`;
    case "clavier": return `<h2>Clavier</h2><div class="sub">Dispositions, raccourcis</div>
      ${srow("Dispositions et raccourcis","Ajouter une disposition, changer les raccourcis")}
      ${btnOuvrir("clavier")}`;
    case "datetime": {
      const h = etat.heure || {};
      return `<h2>Date et heure</h2><div class="sub">Fuseau horaire</div>
      ${h.fuseau ? srow("Fuseau horaire", esc(h.fuseau)) : ""}
      ${srow("Mise à l'heure automatique",
             h.auto ? "L'heure se règle seule sur internet (NTP)"
                    : "L'heure ne se règle pas toute seule",
             sw(h.auto, "basculeHeureAuto()"))}
      ${btnOuvrir("datetime","État (timedatectl)")}`;
    }
    case "defaut": return `<h2>Applications par défaut</h2><div class="sub">Quelle application ouvre quoi</div>
      ${srow("Navigateur, courrier, fichiers","Choisir les applications préférées")}
      ${btnOuvrir("defaut")}`;
    case "distant": return `<h2>Bureau à distance</h2><div class="sub">Voir cet écran depuis une autre machine</div>
      ${srow("Accès à distance","x11vnc, à installer au besoin")}
      ${btnOuvrir("distant","Comment faire")}`;
    case "apropos": return `<h2>À propos de LexOS</h2><div class="sub">1.0 « Nomad »</div>
      ${srow("Système", esc(etat.version))}
      ${srow("Nom de la machine", esc(etat.hote))}
      ${srow("Noyau", esc(etat.noyau))}
      ${btnOuvrir("apropos","La fenêtre À propos complète")}`;
    default: return `<h2>Paramètres</h2><div class="sub">Choisis une section à gauche</div>`;
  }
}

/* --- Rendu ---------------------------------------------------------------- */
function rendNav(){
  const nav = document.getElementById("sidebar");
  nav.innerHTML = NAV.map(g =>
    `<div class="grp">${g.grp}</div>` +
    g.items.map(([cle,pic,label]) =>
      `<button class="nav-item${cle===sectionActive?" sel":""}" data-cle="${cle}">
         <span class="pic">${pic}</span><span>${label}</span></button>`).join("")
  ).join("");
  nav.querySelectorAll(".nav-item").forEach(b =>
    b.onclick = () => { sectionActive = b.dataset.cle;
                        location.hash = sectionActive; rend(); });
}
function rendSection(){
  document.getElementById("content").innerHTML = contenu(sectionActive);
}
function rend(){ rendNav(); rendSection(); }

/* --- Démarrage ------------------------------------------------------------ */
(async function(){
  const h = location.hash.replace("#","");
  if(h && NAV.some(g=>g.items.some(([c])=>c===h))) sectionActive = h;
  await chargeEtat();
  rend();
})();
