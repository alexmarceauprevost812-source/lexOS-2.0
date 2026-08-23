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
    ["bienetre","🌱","Bien-être numérique"], ["session","⏻","Fermer la session"]]},
  {grp:"Périphériques", items:[
    ["souris","🖱","Souris et pavé tactile"], ["couleurs","🌈","Gestion des couleurs"],
    ["imprimantes","🖨","Imprimantes"], ["amovibles","💾","Supports amovibles"],
    ["tablette","🖊","Tablette graphique"]]},
  {grp:"Système", items:[
    ["confidentialite","🛡","Confidentialité et sécurité"], ["maj","⬆","Mises à jour"],
    ["accessibilite","♿","Accessibilité"], ["utilisateurs","🧑‍💻","Utilisateurs"],
    ["region","🌍","Région et langue"], ["clavier","⌨","Clavier"],
    ["datetime","🕒","Date et heure"], ["defaut","🧭","Applications par défaut"],
    ["distant","🖥","Bureau à distance"],
    ["tiers","⚖","Logiciels tiers"], ["apropos","◆","À propos"]]},
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
];
/*  LES ÉCRITURES À LA MAIN. Douze, embarquées par LexOS (licence OFL, dans
    /usr/share/fonts/truetype/lexos) — donc présentes même sur une machine
    qui n'a aucune police manuscrite installée, et lisibles hors ligne.

    Le libellé est en français et décrit le GESTE (bulle, crayon, marqueur…),
    pas le nom de la fonderie : « Gloria Hallelujah » ne dit rien à personne,
    « Tableau noir » dit tout. Le vrai nom reste en infobulle, pour qui veut
    la retrouver ailleurs.

    Chacune est écrite DANS SA PROPRE POLICE dans la liste : c'est la seule
    façon de choisir sans essayer une par une. */
const ECRITURES = [
  ["manuscrite", "Manuscrite",  "Patrick Hand"],
  ["bulle",      "Bulle",       "Comic Neue"],
  ["carnet",     "Carnet",      "Delius"],
  ["ronde",      "Ronde",       "Short Stack"],
  ["crayon",     "Crayon",      "Neucha"],
  ["plume",      "Plume",       "Handlee"],
  ["marqueur",   "Marqueur",    "Kalam"],
  ["architecte", "Architecte",  "Architects Daughter"],
  ["fleur",      "Fleur",       "Indie Flower"],
  ["cursive",    "Cursive",     "Caveat"],
  ["tableau",    "Tableau noir","Gloria Hallelujah"],
  ["craie",      "Craie",       "Shantell Sans"],
];
//  Les deux listes réunies, sous la forme qu'attend appliqueApparence() :
//  [clé, libellé, famille CSS]. Écrit une fois plutôt que recopié.
const TOUTES_POLICES = POLICES.concat(
  ECRITURES.map(([cle, titre, fam]) => [cle, titre, `'${fam}',cursive`]));
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

/*  Le protocole choisi pour aller voir ailleurs vit ICI et pas dans la page :
    rendSection() réécrit tout le panneau à chaque rafraîchissement, et un
    choix rangé dans le HTML disparaîtrait à la première relecture d'état. */
let distantProto = "auto";

/*  Le réseau Wi-Fi qu'on est en train de choisir. Comme le protocole du
    bureau à distance, il vit ICI : rendSection() réécrit tout le panneau à
    chaque relecture d'état, et un choix rangé dans le HTML disparaîtrait. */
let wifiChoisi = "";

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
async function ouvreBoost(){
  const r = await api("ouvrir", "boost");
  if(r.ok) toast("LexOS Boost s'ouvre dans sa fenêtre");
}

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
async function setDefinition(sortie, mode){
  const r = await api("ecran-definition", sortie + "|" + mode);
  await rafraichir(r.ok ? "Définition : " + mode
                        : "Échec : " + (r.erreur || "refusé"));
}
async function setEchelle(v){
  const r = await api("echelle", v);
  await rafraichir(r.ok ? "Affichage à " + v + " % — rouvre les fenêtres"
                        : "Échec : " + (r.erreur || "refusé"));
}
async function setCaptureFormat(v){
  const r = await api("capture-format", v);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "refusé"));
}
async function setFondQualite(v){
  const r = await api("fond-qualite", v);
  await rafraichir(r.ok ? "Au prochain démarrage du fond"
                        : "Échec : " + (r.erreur || "refusé"));
}
async function btBranche(adresse){
  toast("Connexion en cours…");
  const r = await api("bt-connecter", adresse);
  await rafraichir(r.ok ? "Connecté — va dans Son pour y envoyer le son" : null);
}
async function btCoupe(adresse){
  const r = await api("bt-deconnecter", adresse);
  await rafraichir(r.ok ? "Déconnecté" : null);
}
/*  La recherche dure douze secondes CÔTÉ MACHINE : le bouton le dit et se
    désactive pendant ce temps, sinon on clique trois fois et on empile trois
    balayages. */
async function btCherche(){
  const b = document.getElementById("btCherche");
  if(b){ b.disabled = true; b.textContent = "Recherche en cours…"; }
  const r = await api("bt-chercher");
  await rafraichir(r.ok ? "Recherche terminée" : null);
}
function choisitWifi(ssid){ wifiChoisi = ssid; rendSection();
  const c = document.getElementById("wifiMdp"); if(c) c.focus(); }
async function chercheWifi(){
  toast("Recherche des réseaux…");
  await api("wifi-rechercher");
  await rafraichir("Recherche terminée");
}
/*  Le mot de passe est lu au moment de l'envoi et n'est JAMAIS rangé dans une
    variable qui survivrait au rendu : il fait l'aller simple champ → pont
    local → gestionnaire de réseau. */
async function brancheWifi(){
  const ssid = wifiChoisi;
  if(!ssid) return;
  const c = document.getElementById("wifiMdp");
  const r = await api("wifi-connecter", {ssid, mot_de_passe: c ? c.value : ""});
  if(c) c.value = "";
  if(r.ok){ wifiChoisi = ""; await rafraichir("Connecté à " + ssid); }
  else await rafraichir(null);
}
function setDistantProto(p){
  if(["auto","rdp","vnc","ssh"].includes(p)){ distantProto = p; rendSection(); }
}
async function setDistantPartage(){
  const on = !!(etat.distant && etat.distant.actif);
  const r = await api("distant-partage", on ? "off" : "on");
  await rafraichir(r.ok
    ? (on ? "Partage arrêté"
          : "Une fenêtre s'ouvre : elle demande le mot de passe à donner")
    : "Échec : " + (r.erreur || "refusé"));
}
/*  Pas de rafraichir() ici : relire l'état réécrirait le panneau et effacerait
    l'adresse qu'on vient de taper, juste au moment où on voudrait la corriger
    parce que la connexion a raté. */
async function distantVers(){
  const c = document.getElementById("distAdr");
  const adresse = (c ? c.value : "").trim();
  if(!adresse){ toast("Il faut l'adresse de l'autre machine"); return; }
  const r = await api("distant-vers", {protocole: distantProto, adresse});
  if(r.ok) toast("Connexion à " + adresse + " …");
}
async function setSortieSon(nom){
  const r = await api("son-sortie", nom);
  await rafraichir(r.ok ? "Le son sort maintenant par là"
                        : "Échec : " + (r.erreur || "sortie refusée"));
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
/*  LA VUE D'ENSEMBLE. Trois commandes : l'ouvrir tout de suite, et armer
    ses deux déclencheurs. On relit l'état après chaque bascule — « super »
    peut échouer si xcape manque, et l'interrupteur doit alors REVENIR, pas
    rester allumé sur une promesse. */
async function poseAutocollant(quoi){
  const r = await api("autocollant", quoi);
  await rafraichir(r.ok
    ? (quoi === "enlever" ? "Fond d'origine retrouvé" : "Posé sur le fond d'écran")
    : "Échec : " + (r.erreur || "commande refusée"));
}
async function ouvreApercu(){
  const r = await api("apercu");
  if(!r.ok) toast("Échec : " + (r.erreur || "aucun outil de vue d'ensemble"));
}
async function basculeCoin(){
  const r = await api("coin", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeSuperApercu(){
  const r = await api("super_apercu", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "xcape n'est pas installé"));
}
async function vaBureau(n){
  const r = await api("bureau-va", String(n));
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function setLangue(l){
  const r = await api("langue", l);
  await rafraichir(r.ok ? "À la prochaine ouverture de session" : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeNotif(){
  const r = await api("notif", "silence");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeAmovible(quoi){
  const r = await api("amovibles", quoi);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeAccess(quoi){
  const r = await api("access", quoi);
  if(quoi === "orca" || quoi === "onboard"){
    if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
    return;
  }
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function actionSecu(quoi){
  const r = await api("securite", quoi);
  if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
}
async function actionMaj(quoi){
  const r = await api("maj", quoi);
  if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
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
/*  L'HORLOGE DE LA BARRE. Les trois réglages — 12/24 h, secondes, jour —
    ne sont qu'une seule chaîne de format côté XFCE ; c'est le Python qui la
    recompose. On relit l'état ensuite : si xfconf-query manque, l'écran ne
    doit pas montrer un réglage qui n'a pas pris. */
async function setHorloge(quoi){
  const r = await api("horloge", quoi);
  await rafraichir(r.ok ? "L'horloge de la barre suit"
                        : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeFuseauAuto(){
  const r = await api("fuseau-auto", "toggle");
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
  //  appliqueApparence() manquait ICI, et seulement ici : setPolice et
  //  setAccent l'appellent tous les deux depuis toujours. C'est ce qui rendait
  //  le mode clair invisible dans cette fenêtre — le bureau changeait, les
  //  Paramètres restaient noirs.
  if(r.ok){ etat.theme = t; appliqueApparence(); rendSection(); toast("Thème : " + t); }
}
async function setPolice(p){
  const r = await api("police", p);
  if(r.ok){ etat.police = p; appliqueApparence(); rendSection(); toast("Police : " + p); }
}
async function setAccent(a){
  const r = await api("accent", a);
  if(r.ok){ etat.accent = a; appliqueApparence(); rendSection(); toast("Accent : " + a); }
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
        : (allume ? srow("Réseau connecté", "Aucun — choisis-en un ci-dessous") : "")}

      ${allume ? (() => {
        /*  LA LISTE QUI MANQUAIT. Le panneau savait dire « connecté » ou
            « aucun », et rien d'autre : sans réseau, il fallait deviner
            qu'un bouton ouvrait un autre outil. Or au premier démarrage il
            n'y a JAMAIS de réseau — et sans réseau, ni météo, ni catalogue,
            ni mises à jour. C'est le premier geste qu'on fait sur une
            machine neuve, et c'était le seul qu'on ne pouvait pas faire ici. */
        const rs = w.reseaux || [];
        if(!rs.length) return `<h3 class="cpt-h3">Réseaux à portée</h3>
          <p class="notice">Aucun réseau trouvé pour l'instant.
            <button class="btn ghost" onclick="chercheWifi()">Chercher encore</button></p>`;
        return `<h3 class="cpt-h3">Réseaux à portée</h3>
        ${rs.map(r => `<div class="srow wifi-l">
          <div style="flex:1;min-width:0">
            <div class="t">${esc(r.ssid)}
              ${r.protege ? `<span class="cadenas" title="${esc(r.securite)}">🔒</span>`
                          : `<span class="cadenas ouvert" title="Réseau ouvert — tout le monde peut lire ce qui y passe">⚠</span>`}
            </div>
            <div class="d">${r.actif ? "Connecté" : (r.protege ? esc(r.securite) : "Ouvert, sans mot de passe")} — signal ${r.signal} %</div>
          </div>
          ${barres(r.signal)}
          ${r.actif
            ? `<span class="etat ok">connecté</span>`
            : `<button class="btn ghost" onclick="choisitWifi('${esc(r.ssid).replace(/'/g,"&#39;")}')">Se connecter</button>`}
        </div>
        ${wifiChoisi === r.ssid && !r.actif ? `<div class="srow" style="display:block">
          ${r.protege
            ? `<div class="t" style="margin-bottom:8px">Mot de passe de « ${esc(r.ssid)} »</div>
               <div class="row" style="align-items:center">
                 <input class="champ" id="wifiMdp" type="password" autocomplete="off"
                        placeholder="mot de passe du réseau"
                        onkeydown="if(event.key==='Enter')brancheWifi()">
                 <button class="btn" onclick="brancheWifi()">Se connecter</button>
                 <button class="btn ghost" onclick="choisitWifi('')">Annuler</button>
               </div>
               <div class="sub" style="margin-top:8px">Le mot de passe reste sur
                 cette machine : il part au gestionnaire de réseau et n'est
                 écrit dans aucun journal.</div>`
            : `<div class="row"><button class="btn" onclick="brancheWifi()">Se connecter sans mot de passe</button>
               <button class="btn ghost" onclick="choisitWifi('')">Annuler</button></div>
               <div class="sub" style="margin-top:8px">Réseau ouvert : ce qui
                 y passe peut être lu par n'importe qui autour. À éviter pour
                 les mots de passe et les paiements.</div>`}
        </div>` : ""}`).join("")}
        <div class="row"><button class="btn ghost" onclick="chercheWifi()">Chercher encore</button></div>`;
      })() : ""}

      ${btnOuvrir("wifi","Ouvrir l'outil réseau")}
      <p class="notice">En ligne de commande : <code>lexos wifi</code> ·
      <code>lexos net password "&lt;réseau&gt;"</code> pour un mot de passe oublié.</p>`;
    }
    case "reseau": {
      const n = etat.reseau || {};
      return `<h2>Réseau</h2><div class="sub">Filaire, mode avion, VPN</div>
      ${srow("Mode avion","Coupe Wi-Fi, Bluetooth et données",
             sw(etat.avion==="on","basculeAvion()"))}
      ${n.filaire === null || n.filaire === undefined
        ? ""
        : srow("Câble Ethernet",
               n.filaire ? "Branché" + (n.ip ? " — " + esc(n.ip) : "") : "Débranché",
               `<span class="etat ${n.filaire?"ok":"off"}">${n.filaire?"connecté":"absent"}</span>`)}
      ${btnOuvrir("reseau","Ouvrir l'outil réseau")}
      <p class="notice">VPN : <code>lexos vpn import fichier.ovpn</code> (OpenVPN) ou un
      <code>.conf</code> WireGuard, puis <code>lexos vpn connect "&lt;nom&gt;"</code>.</p>`;
    }
    case "bluetooth": {
      /*  LA LISTE QUI MANQUAIT, comme pour le Wi-Fi et pour la même barre de
          son : le panneau disait « prêt à appairer » sans jamais montrer QUOI.
          Le cinéma maison d'Alex était introuvable, faute d'une liste où le
          voir. Appairés d'abord, puis ce que la recherche a entendu. */
      const bt = etat.bluetooth || {};
      const radio = bt.radio;
      const app = bt.appareils || [];
      const GENRES = {"audio-card":"🔊","audio-headset":"🎧","audio-headphones":"🎧",
                      "input-keyboard":"⌨","input-mouse":"🖱","phone":"📱",
                      "computer":"💻","input-gaming":"🎮"};
      return `<h2>Bluetooth</h2><div class="sub">Enceintes, cinéma maison, casques, manettes</div>
      ${radio === null || radio === undefined
        ? `<p class="notice">Aucun contrôleur Bluetooth sur cette machine.</p>`
        : srow("Bluetooth", radio ? "Allumé" : "Éteint",
               sw(radio, "basculeBluetooth()"))}
      ${radio ? `<h3 class="cpt-h3">Appareils</h3>
        ${app.length ? app.map(d => srow(
            `${GENRES[d.genre] || "·"} ${esc(d.nom)}`,
            d.connecte ? "Connecté — le son peut sortir ici"
                       : (d.appaire ? "Appairé, pas connecté" : "À portée, jamais appairé"),
            d.connecte
              ? `<button class="btn ghost" onclick="btCoupe('${d.adresse}')">Déconnecter</button>`
              : `<button class="btn ghost" onclick="btBranche('${d.adresse}')">${d.appaire ? "Connecter" : "Appairer"}</button>`
          )).join("")
          : `<p class="notice">Aucun appareil connu. Mets ton enceinte ou ta
             barre de son en <b>mode appairage</b> (souvent un bouton Bluetooth
             à tenir enfoncé), puis lance la recherche.</p>`}
        <div class="row"><button class="btn ghost" id="btCherche" onclick="btCherche()">Rechercher (12 s)</button></div>
        <p class="notice">Une fois l'enceinte connectée, elle apparaît dans
          <b>Son → Sortie audio</b> — c'est là qu'on lui envoie le son.</p>`
        : ""}
      ${btnOuvrir("bluetooth","L'outil complet (lexos bt)")}`;
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
      ${(() => {
        const ec = etat.ecrans || [];
        const av = (etat.echelle && etat.echelle.pourcent) || "100";
        let h = "";
        //  Une définition par écran : chaque dalle a SA liste, et proposer
        //  celle du voisin donnerait un écran noir.
        for(const e of ec){
          if(!e.modes || e.modes.length < 2) continue;
          h += `<div class="srow" style="display:block">
            <div class="t" style="margin-bottom:8px">Définition — ${esc(e.nom)}${
              e.principal ? " (écran principal)" : ""}</div>
            <div class="row">${e.modes.slice(0,8).map(m =>
              `<button class="btn ${m===e.definition?"sel":"ghost"}"
                 onclick="setDefinition('${esc(e.nom)}','${esc(m)}')">${esc(m)}</button>`
              ).join("")}</div>
          </div>`;
        }
        h += `<div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Taille de l'affichage</div>
          <div class="row">${["100","125","150","175","200"].map(v =>
            `<button class="btn ${v===av?"sel":"ghost"}"
               onclick="setEchelle('${v}')">${v} %</button>`).join("")}</div>
          <div class="sub" style="margin-top:8px">Agrandit le texte et les
            boutons <b>sans rendre l'image floue</b> : les applications
            dessinent plus grand dès le départ, au lieu qu'on étire l'image
            une fois dessinée. Les fenêtres déjà ouvertes suivent après
            réouverture.</div>
        </div>`;
        return h;
      })()}
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
      ${(() => {
        const so = (etat.son && etat.son.sorties) || [];
        if(!so.length) return "";
        //  Une enceinte Bluetooth appairée apparaît ici TOUTE SEULE : PipeWire
        //  en fait une sortie comme les autres. Pas de liste séparée pour le
        //  sans-fil — deux listes finiraient par ne plus dire la même chose.
        return `<div class="sub" style="margin-top:20px">Où sort le son</div>
        <div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Sortie audio</div>
          <div class="row">${so.map(x =>
            `<button class="btn ${x.actif?"sel":"ghost"}"
               onclick="setSortieSon('${esc(x.nom)}')"
               title="${esc(x.nom)}">${esc(x.titre)}</button>`).join("")}</div>
          <div class="sub" style="margin-top:8px">Haut-parleurs, casque, télé en
            HDMI, cinéma maison, enceinte Bluetooth — ce qui joue déjà suit
            aussitôt. Une enceinte sans fil apparaît ici dès qu'elle est
            appairée dans <b>Bluetooth</b>.</div>
        </div>`;
      })()}
      ${btnOuvrir("son","Ouvrir le mélangeur")}
      <p class="notice">En ligne de commande : <code>lexos son</code> —
      volume, sortie, profils, tout au clavier.</p>`;
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

      <h3 class="cpt-h3">Scan matériel</h3>
      ${srow("LexOS Boost",
             "Inventaire de la machine, mesures, optimisations — dans sa fenêtre",
             `<button class="btn ghost" onclick="ouvreBoost()">Ouvrir</button>`)}
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
    case "mac": {
      const m = etat.mac || {};
      return `<h2>Mac (Apple)</h2><div class="sub">Wi-Fi Broadcom, ventilateurs, touches F1-F12</div>
      ${srow("Cette machine",
             m.apple ? "Matériel Apple — " + esc(m.modele || "modèle inconnu")
                     : "Ce n'est pas un Mac" + (m.modele ? " — " + esc(m.modele) : ""),
             `<span class="etat ${m.apple?"ok":"abs"}">${m.apple?"Apple":"autre"}</span>`)}
      ${btnOuvrir("mac","Outils Mac (terminal)")}
      <p class="notice">${m.apple
        ? "Wi-Fi Broadcom, pilotage des ventilateurs et touches F1-F12 : <code>lexos mac</code> s'en occupe."
        : "Ces réglages ne servent que sur du matériel Apple. Ils restent là au cas où tu déplacerais ce disque."}</p>`;
    }
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
        <div class="t" style="margin:16px 0 8px">Écritures à la main</div>
        <div class="row">${ECRITURES.map(([n,titre,fam])=>
          `<button class="btn ${n===etat.police?"sel":"ghost"}"
             style="font-family:'${fam}',cursive;font-size:16px"
             title="${fam}" onclick="setPolice('${n}')">${titre}</button>`).join("")}</div>
        <div class="sub" style="margin-top:8px">Douze écritures livrées avec LexOS —
          chacune s'affiche ici dans sa propre police. Les fenêtres déjà ouvertes
          gardent l'ancienne : ferme-les et rouvre-les.</div>
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
          <button class="btn ghost" onclick="setFondAnime('lexis-3d')">🧊 Lexis 3D — suit la souris</button>
          <button class="btn" onclick="setFondAnime('off')">Revenir au fond fixe</button>
        </div>
      </div>

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Autocollants sur le fond</div>
        <div class="sub" style="margin-bottom:8px">Un personnage posé sur ton
        fond d'écran, comme dans la démo. Ils s'empilent ; « Enlever »
        retrouve le fond d'origine tel quel.</div>
        <div class="row">
          <button class="btn ghost" onclick="poseAutocollant('rock')">🤘 Lex — bebeilles</button>
          <button class="btn ghost" onclick="poseAutocollant('salut')">👋 Lex — salut</button>
          <button class="btn ghost" onclick="poseAutocollant('prevost')">🛡 Badge PREVOST</button>
          <button class="btn" onclick="poseAutocollant('enlever')">Enlever</button>
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
      ${(() => {
        const q = (etat.image && etat.image.fond) || "equilibre";
        const CH = [["economie","Économie","Décodage par la carte graphique, 24 images/s"],
                    ["equilibre","Équilibré","Le réglage par défaut"],
                    ["belle","Belle image","Haute qualité — ça chauffe, secteur conseillé"]];
        return `<div class="sub" style="margin-top:20px">Qualité du fond animé</div>
        <div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Qualité d'image</div>
          <div class="row">${CH.map(([v,t,d]) =>
            `<button class="btn ${v===q?"sel":"ghost"}" title="${d}"
               onclick="setFondQualite('${v}')">${t}</button>`).join("")}</div>
          <div class="sub" style="margin-top:8px">Un fond animé décode une vidéo
            <b>en continu, pour toujours</b> — sur un portable, c'est une à deux
            heures d'autonomie. Le changement prend effet au prochain démarrage
            du fond.</div>
        </div>`;
      })()}
      ${(() => {
        //  Les captures n'ont pas de section à elles, et en créer une pour un
        //  seul réglage donnerait une page presque vide. Elles vivent donc
        //  ici, sous le même titre que l'autre qualité d'image : c'est ainsi
        //  qu'Alex les a demandées, ensemble.
        const f = (etat.image && etat.image.capture) || "png";
        return `<div class="sub" style="margin-top:20px">Qualité des captures d'écran</div>
        <div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Format des images</div>
          <div class="row">
            <button class="btn ${f==="png"?"sel":"ghost"}"
              onclick="setCaptureFormat('png')">PNG — sans perte</button>
            <button class="btn ${f==="jpeg"?"sel":"ghost"}"
              onclick="setCaptureFormat('jpeg')">JPEG — plus léger</button>
          </div>
          <div class="sub" style="margin-top:8px">Une capture sert souvent à
            <b>montrer du texte</b> : le PNG le garde parfaitement net. Le JPEG
            pèse deux à quatre fois moins — pratique pour envoyer par message,
            au prix d'un texte très légèrement adouci.</div>
        </div>`;
      })()}
      ${btnOuvrir("bureau","Réglages fins (XFCE)")}`;
    case "multitaches": {
      const b = etat.bureaux || {nb:1, courant:0, fenetres:[]};
      const ap = etat.apercu || {moteur:"", coin:false, super:false, xcape:false};
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
      <div class="sub">Vue d'ensemble</div>
      ${srow("Voir tous mes bureaux",
             ap.moteur
               ? `Tout s'écarte : les bureaux en rangée, les fenêtres du bureau
                  courant en aperçus. On clique un bureau pour y aller, une
                  fenêtre pour l'ouvrir.` +
                 (ap.moteur === "xfdashboard" ? "" :
                  ` <b>xfdashboard n'est pas installé</b> — on ouvre la liste
                    des fenêtres, qui montre les mêmes bureaux sans les
                    vignettes.`)
               : `Aucun outil de vue d'ensemble n'est installé sur cette
                  machine — il n'y a rien à ouvrir.`,
             ap.moteur
               ? `<button class="btn" onclick="ouvreApercu()">Ouvrir</button>`
               : `<span class="etat abs">absent</span>`)}
      ${srow("Touche Super seule",
             ap.xcape
               ? `Relâcher <b>Super</b> sans rien taper d'autre ouvre la vue,
                  comme sous Ubuntu. <b>Super+1</b> à <b>Super+${b.nb}</b>
                  continuent d'aller aux bureaux.`
               : `Demande <code>xcape</code>, qui n'est pas installé :
                  lui seul sait reconnaître une touche Super relâchée seule.`,
             ap.xcape ? sw(ap.super, "basculeSuperApercu()")
                      : `<span class="etat abs">absent</span>`)}
      ${srow("Coin actif",
             `Pousser la souris dans le coin <b>haut-gauche</b> ouvre la vue.
              Il faut y rester un court instant : viser le logo Applications,
              qui habite ce coin, ne déclenche rien.`,
             sw(ap.coin, "basculeCoin()"))}
      ${btnOuvrir("multitaches","Ouvrir les réglages de bureaux")}
      <div class="sub" style="margin-top:20px">Partager l'écran entre plusieurs fenêtres</div>
      ${srow("Placer une fenêtre où on veut",
             `Huit positions, au clavier ou en glissant la fenêtre vers un bord.
              Les touches <b>Début</b>, <b>Fin</b>, <b>Page↑</b> et <b>Page↓</b>
              forment un carré sur le clavier, à la même place que les quatre
              coins de l'écran — le geste est le dessin de ce qu'on veut.`,
             `<div class="tuiles" aria-hidden="true">
                <i class="hg"></i><i class="hd"></i><i class="bg"></i><i class="bd"></i>
              </div>`)}
      <div class="srow" style="display:block">
        <div class="raccourcis">
          <div><kbd>Super</kbd>+<kbd>Début</kbd><span>coin haut-gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>Page↑</kbd><span>coin haut-droit</span></div>
          <div><kbd>Super</kbd>+<kbd>Fin</kbd><span>coin bas-gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>Page↓</kbd><span>coin bas-droit</span></div>
          <div><kbd>Super</kbd>+<kbd>←</kbd><span>moitié gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>→</kbd><span>moitié droite</span></div>
          <div><kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>↑</kbd><span>moitié haute</span></div>
          <div><kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>↓</kbd><span>moitié basse</span></div>
          <div><kbd>Super</kbd>+<kbd>↑</kbd><span>plein écran</span></div>
          <div><kbd>Super</kbd>+<kbd>↓</kbd><span>rendre sa taille</span></div>
        </div>
        <div class="sub" style="margin-top:8px">À la souris : glisse la fenêtre
          vers un bord pour la moitié, vers un coin pour le quart.</div>
      </div>
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
    case "notifications": {
      const n = etat.notif || {};
      return `<h2>Notifications</h2><div class="sub">Ce qui apparaît, et combien de temps</div>
      ${srow("Ne pas déranger", n.silence ? "Les notifications sont mises de côté"
                                          : "Les notifications s'affichent",
             sw(n.silence, "basculeNotif()"))}
      ${n.duree ? srow("Durée d'affichage", n.duree + " secondes") : ""}
      ${btnOuvrir("notifications","Réglages fins")}
      <p class="notice">En « ne pas déranger », rien n'est perdu : les
      notifications s'empilent et se relisent après.</p>`;
    }
    case "recherche": {
      return `<h2>Recherche</h2><div class="sub">Trouver un fichier ou une application</div>
      ${srow("Chercher une application","Le menu Applications filtre à la frappe")}
      ${srow("Chercher un fichier","Par nom ou par contenu — <code>lexos recherche</code>")}
      ${btnOuvrir("recherche","Ouvrir la recherche")}
      <p class="notice">LexOS n'indexe pas le disque en tâche de fond : rien ne
      tourne en permanence à lire tes fichiers, et rien ne ralentit la machine
      pour un service qu'on utilise trois fois par semaine. La recherche
      parcourt au moment où on la demande.</p>`;
    }
    case "comptes": {
      const c = etat.comptes || {};
      return `<h2>Comptes en ligne</h2><div class="sub">Drive, OneDrive, Nextcloud, Dropbox…</div>
      ${c.liens && c.liens.length
        ? c.liens.map(l=>srow(esc(l.nom), "Relié par " + esc(l.par),
            `<span class="etat ok">relié</span>`)).join("")
        : srow("Comptes reliés", "Aucun pour l'instant",
               `<span class="etat abs">aucun</span>`)}
      ${srow("rclone", c.rclone ? "Disponible — synchronise ou monte comme un disque"
                                : "Pas installé",
             `<span class="etat ${c.rclone?"ok":"abs"}">${c.rclone?"prêt":"absent"}</span>`)}
      ${btnOuvrir("comptes","Relier un compte")}
      <p class="notice">Deux façons de faire, qui ne se valent pas :
      <b>monter</b> le compte l'ouvre dans le gestionnaire de fichiers sans rien
      copier — pratique, mais inutilisable hors ligne ; <b>synchroniser</b> en
      garde une copie sur le disque, disponible même sans réseau. LexOS propose
      les deux, et le dit avant de choisir pour toi.</p>`;
    }
    case "partage": {
      const p = etat.partage || {};
      return `<h2>Partage</h2><div class="sub">Envoyer un fichier à un téléphone ou à un autre poste</div>
      ${srow("Serveur de partage",
             p.actif ? "En marche — un QR code suffit à recevoir"
                     : "Arrêté — il démarre quand tu partages quelque chose",
             `<span class="etat ${p.actif?"ok":"abs"}">${p.actif?"actif":"au repos"}</span>`)}
      ${btnOuvrir("partage","Ouvrir le partage")}
      <p class="notice">Le partage montre un QR code et sert une page locale :
      ça marche avec <b>n'importe quel</b> téléphone, sans rien y installer.
      Le serveur ne tourne que le temps du transfert.</p>`;
    }
    case "bienetre": {
      const b = etat.bienetre || {};
      const h = Math.floor((b.minutes||0)/60), m = (b.minutes||0)%60;
      return `<h2>Bien-être numérique</h2><div class="sub">Temps d'écran, pauses, lumière du soir</div>
      ${srow("Temps d'écran aujourd'hui",
             !b.tourne
               ? "Le compteur est arrêté — il ne mesure rien tant qu'on ne le demande pas"
               : (b.minutes
                   ? `${h} h ${String(m).padStart(2,"0")}` +
                     " — compté depuis la dernière activité, pas depuis l'allumage"
                   : "Compteur en marche, rien d'enregistré encore aujourd'hui"),
             b.tourne && b.minutes
               ? jauge(Math.min(100, Math.round(b.minutes/480*100)))
               : `<span class="etat ${b.tourne?"ok":"abs"}">${b.tourne?"en marche":"arrêté"}</span>`)}
      ${srow("Rappels de pause", b.pauses ? "workrave est là — il rappelle de lever les yeux"
                                          : "Pas installé",
             `<span class="etat ${b.pauses?"ok":"abs"}">${b.pauses?"prêt":"absent"}</span>`)}
      ${srow("Lumière du soir", b.soir ? "Réchauffe l'écran à la tombée du jour"
                                       : "Pas installé",
             `<span class="etat ${b.soir?"ok":"abs"}">${b.soir?"prêt":"absent"}</span>`)}
      ${btnOuvrir("bienetre","Ouvrir le détail")}
      <p class="notice">Le temps d'écran compte l'usage RÉEL : un ordinateur
      laissé ouvert toute la nuit ne compte pas huit heures. Un compteur qui
      prétendrait le contraire ne vaudrait rien.</p>`;
    }
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
    case "couleurs": {
      const c = etat.couleurs || {};
      return `<h2>Gestion des couleurs</h2><div class="sub">Profils des écrans</div>
      ${!c.dispo
        ? `<p class="notice">colord n'est pas là : les profils de couleur ne
           peuvent pas être gérés.</p>`
        : (c.ecrans && c.ecrans.length
            ? c.ecrans.map(e=>srow(esc(e.nom),
                e.profil ? "Profil : " + esc(e.profil) : "Aucun profil — couleurs par défaut",
                `<span class="etat ${e.profil?"ok":"abs"}">${e.profil?"calibré":"non calibré"}</span>`)).join("")
            : `<p class="notice">Aucun écran connu de colord pour l'instant.</p>`)}
      ${btnOuvrir("couleurs","Ouvrir la gestion des couleurs")}
      <p class="notice">Un profil de couleur sert surtout à celui qui imprime ou
      retouche des photos : il fait correspondre ce qu'on voit à l'écran et ce
      qui sort de l'imprimante.</p>`;
    }
    case "imprimantes": {
      const im = etat.imprimantes || {};
      return `<h2>Imprimantes</h2><div class="sub">Ajouter et gérer les imprimantes</div>
      ${!im.dispo
        ? `<p class="notice">CUPS n'est pas là : aucune imprimante ne peut être gérée.</p>`
        : (im.liste && im.liste.length
            ? im.liste.map(i=>srow(esc(i.nom) + (i.defaut ? " — par défaut" : ""), esc(i.etat),
                `<span class="etat ${i.etat==="prête"?"ok":"abs"}">${esc(i.etat)}</span>`)).join("")
            : `<p class="notice">Aucune imprimante installée. Branche-la ou ajoute-la
               par le réseau : LexOS trouve seul la plupart des modèles récents
               (pilotes sans pilote, via IPP).</p>`)}
      ${btnOuvrir("imprimantes","Ajouter une imprimante")}`;
    }
    case "amovibles": {
      const v = etat.amovibles || {};
      return `<h2>Supports amovibles</h2><div class="sub">Ce que LexOS fait quand tu branches quelque chose</div>
      ${srow("Monter automatiquement","La clé est prête sans rien demander",
             sw(v.monter, "basculeAmovible('monter')"))}
      ${srow("Ouvrir le gestionnaire de fichiers","Une fenêtre s'ouvre sur le contenu",
             sw(v.ouvrir, "basculeAmovible('ouvrir')"))}
      ${srow("Proposer d'importer les photos","Quand c'est un appareil photo ou un téléphone",
             sw(v.photos, "basculeAmovible('photos')"))}
      ${srow("Lancer la musique","Quand c'est un disque audio",
             sw(v.musique, "basculeAmovible('musique')"))}
      ${btnOuvrir("amovibles","Réglages fins (XFCE)")}
      <p class="notice">Ces réglages sont ceux de thunar-volman : ils s'appliquent
      tout de suite, sans rouvrir la session.</p>`;
    }
    case "tablette": {
      const t = etat.tablette || {};
      return `<h2>Tablette graphique</h2><div class="sub">Stylet, pression, zones</div>
      ${t.branchee
        ? t.noms.map(n=>srow(esc(n), "Reconnue et prête",
            `<span class="etat ok">branchée</span>`)).join("")
        : srow("Tablette", "Aucune tablette branchée",
               `<span class="etat abs">absente</span>`)}
      ${btnOuvrir("tablette","Réglages du stylet")}
      <p class="notice">Le pilote Wacom est déjà embarqué : une tablette
      branchée est reconnue sans rien installer.</p>`;
    }
    case "confidentialite": {
      const q = etat.securite || {};
      //  Trois états et non deux : « en marche », « installé mais arrêté »,
      //  et « pas installé ». Un pare-feu éteint et un pare-feu absent
      //  n'appellent pas le même geste.
      const dit = (v, oui, non) =>
        v === null || v === undefined ? "Pas installé" : (v ? oui : non);
      const pastille = v =>
        `<span class="etat ${v===null||v===undefined?"abs":(v?"ok":"off")}">${
          v===null||v===undefined?"absent":(v?"actif":"arrêté")}</span>`;
      return `<h2>Confidentialité et sécurité</h2><div class="sub">Pare-feu, chiffrement, autodéfense</div>
      ${srow("Chiffrement du disque (LUKS2)",
             q.chiffre ? "Ce disque est chiffré" : "Ce disque n'est pas chiffré — proposé à l'installation",
             `<span class="etat ${q.chiffre?"ok":"off"}">${q.chiffre?"actif":"non"}</span>`)}
      ${srow("Pare-feu (ufw)", dit(q.pareFeu,"Refuse tout entrant, laisse sortir","Installé, mais éteint"),
             pastille(q.pareFeu))}
      ${srow("Antivirus (ClamAV)", dit(q.antivirus,"Base de signatures à jour","Installé, mise à jour arrêtée"),
             pastille(q.antivirus))}
      ${srow("Anti-intrusion (fail2ban)", dit(q.intrusion,"Bannit les tentatives répétées","Installé, mais arrêté"),
             pastille(q.intrusion))}
      ${srow("Cloisonnement (AppArmor)", dit(q.apparmor,"Les applications sont cloisonnées","Installé, mais arrêté"),
             pastille(q.apparmor))}
      ${srow("Anti-rootkit", q.rootkit ? "rkhunter et chkrootkit sont là" : "Pas installé",
             pastille(q.rootkit ? true : null))}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Vérifier maintenant</div>
        <div class="row">
          <button class="btn" onclick="actionSecu('etat')">État complet</button>
          <button class="btn ghost" onclick="actionSecu('pare-feu')">Pare-feu</button>
          <button class="btn ghost" onclick="actionSecu('antivirus')">Analyser</button>
          <button class="btn ghost" onclick="actionSecu('rootkit')">Anti-rootkit</button>
        </div>
      </div>
      ${srow("Fichiers privés",
             "Un coffre chiffré (gocryptfs) pour ce qui ne regarde personne",
             `<button class="btn ghost" onclick="api('ouvrir','prive').then(()=>toast('Fichiers privés s\'ouvre'))">Ouvrir</button>`)}
      <p class="notice">Ces outils demandent les droits d'administration et posent
      des questions : ils s'ouvrent dans un terminal, pour qu'on puisse LIRE ce
      qu'ils font. Les lancer en silence derrière un interrupteur cacherait
      justement ce qu'il faut voir. En ligne de commande :
      <code>lexos secure</code> · <code>lexos prive</code>.</p>`;
    }
    case "maj": {
      const m = etat.maj || {};
      return `<h2>Mises à jour</h2><div class="sub">${esc(etat.version || "LexOS")}</div>
      ${srow("Version installée", esc(etat.version || "") + " · noyau " + esc(etat.noyau || ""))}
      ${srow("Mises à jour de sécurité automatiques",
             m.secu ? "Appliquées toutes seules" : "Désactivées",
             `<span class="etat ${m.secu?"ok":"off"}">${m.secu?"actif":"arrêté"}</span>`)}
      ${srow("Tout mettre à jour automatiquement",
             m.tout ? "Y compris les mises à jour ordinaires" : "Seule la sécurité est automatique",
             `<span class="etat ${m.tout?"ok":"off"}">${m.tout?"actif":"non"}</span>`)}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Maintenant</div>
        <div class="row">
          <button class="btn" onclick="actionMaj('verifier')">Vérifier</button>
          <button class="btn ghost" onclick="actionMaj('tout')">Tout mettre à jour</button>
          ${m.fwupd ? `<button class="btn ghost" onclick="actionMaj('firmware')">Micrologiciel (BIOS, SSD)</button>` : ""}
        </div>
      </div>
      <p class="notice">Les mises à jour de sécurité s'installent seules ; le reste
      attend que tu le demandes. Une mise à jour pose des questions et prend du
      temps : elle s'ouvre dans un terminal pour qu'on voie ce qui se passe.</p>`;
    }
    case "accessibilite": {
      const a = etat.access || {};
      return `<h2>Accessibilité</h2><div class="sub">Voir, entendre, taper</div>
      ${srow("Contraste élevé","Couleurs franches, bordures nettes",
             sw(a.contraste, "basculeAccess('contraste')"))}
      ${srow("Curseur large","Un pointeur qu'on retrouve du premier coup d'oeil",
             sw(a.curseurLarge, "basculeAccess('curseur')"))}
      ${srow("Lecteur d'écran (Orca)",
             a.orca ? "Lit à voix haute ce qui est à l'écran" : "Pas installé",
             a.orca ? `<button class="btn ghost" onclick="basculeAccess('orca')">Lancer</button>` : "")}
      ${srow("Clavier visuel (Onboard)",
             a.onboard ? "Taper à la souris ou au doigt, sans clavier physique" : "Pas installé",
             a.onboard ? `<button class="btn ghost" onclick="basculeAccess('onboard')">Lancer</button>` : "")}
      ${btnOuvrir("accessibilite","Réglages fins (XFCE)")}
      <p class="notice">En ligne de commande : <code>lexos access</code>.</p>
      <p class="notice">Un système sans lecteur d'écran n'est pas utilisable par
      tout le monde : Orca est embarqué d'office, pas en option.</p>`;
    }
    case "utilisateurs": {
      const g = etat.utilisateurs || [];
      return `<h2>Utilisateurs</h2><div class="sub">Comptes de cette machine</div>
      ${g.length ? g.map(u=>srow(
          esc(u.complet) + (u.moi ? " — c'est toi" : ""),
          esc(u.nom) + (u.admin ? " · administrateur" : " · session ordinaire"),
          `<span class="etat ${u.admin?"ok":"abs"}">${u.admin?"admin":"normal"}</span>`)).join("")
        : `<p class="notice">Aucun compte lu.</p>`}
      ${btnOuvrir("utilisateurs","Détail (terminal)")}
      <p class="notice">Ajouter ou retirer un compte touche à tout le système :
      ça passe par <code>lexos utilisateurs</code>, dans un terminal, avec le
      mot de passe d'administration — pas par un bouton qu'on clique sans y penser.</p>`;
    }
    case "session": {
      /*  Le bouton rouge de la barre du haut ouvre exactement cette fenêtre.
          Cette section ne la double pas : elle la RETROUVE. Un geste du
          système qui n'existe qu'à un seul endroit de l'écran disparaît le
          jour où cet endroit change — et il change, on vient de le déplacer. */
      return `<h2>Fermer la session</h2><div class="sub">Éteindre, changer d'utilisateur, se déconnecter</div>
      <p class="notice">Le bouton rouge, tout à droite de la barre du haut,
      ouvre la même fenêtre. Veille et redémarrage sont juste à sa gauche,
      dans la barre.</p>
      ${btnOuvrir("session","Ouvrir")}`;
    }
    case "region": {
      return `<h2>Région et langue</h2><div class="sub">Langue, formats, clavier</div>
      ${srow("Langue du système", esc(etat.langue || "inconnue"))}
      ${srow("Fuseau horaire", esc((etat.heure && etat.heure.fuseau) || "inconnu"))}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Changer la langue</div>
        <div class="row">${[["fr_CA.UTF-8","Français (Québec)"],["fr_FR.UTF-8","Français (France)"],
                            ["en_CA.UTF-8","English (Canada)"],["en_US.UTF-8","English (US)"]].map(([v,t])=>
          `<button class="btn ${v===etat.langue?"sel":"ghost"}" onclick="setLangue('${v}')">${t}</button>`).join("")}</div>
      </div>
      <p class="notice">Le changement s'applique à la prochaine ouverture de session :
      les applications lisent leur langue au démarrage, pas en cours de route.</p>`;
    }
    case "clavier": {
      const k = etat.clavier || {};
      const d = k.dispositions || [];
      return `<h2>Clavier</h2><div class="sub">Dispositions et raccourcis</div>
      ${d.length
        ? srow("Dispositions actives", d.join(" · ") +
               (d.length > 1 ? " — Maj+Alt bascule de l'une à l'autre" : ""),
               `<span class="etat ok">${esc(k.courante || d[0])}</span>`)
        : `<p class="notice">Disposition illisible (setxkbmap absent ou session Wayland).</p>`}
      ${btnOuvrir("clavier","Réglages du clavier")}
      <p class="notice">En ligne de commande : <code>lexos clavier</code> ajoute une
      disposition, en enlève une, ou change la touche de bascule.</p>`;
    }
    case "datetime": {
      const h = etat.heure || {};
      return `<h2>Date et heure</h2><div class="sub">Fuseau, format, synchronisation</div>
      ${h.maintenant ? srow("Maintenant", esc(h.maintenant)) : ""}
      ${srow("Mise à l'heure automatique",
             h.auto ? "L'heure se règle seule sur internet (NTP)"
                    : "L'heure ne se règle pas toute seule",
             sw(h.auto, "basculeHeureAuto()"))}
      ${srow("Fuseau horaire automatique",
             h.lieu_connu
               ? `D'après la ville que tu as choisie pour la météo. LexOS ne
                  cherche jamais ta position par ton adresse internet.`
               : `Aucun lieu connu — choisis ta ville une fois avec
                  <code>lexos meteo ville Toronto</code> et le fuseau suivra.
                  LexOS ne devine pas ta position.`,
             h.lieu_connu ? sw(h.fuseau_auto, "basculeFuseauAuto()")
                          : `<span class="etat abs">aucun lieu</span>`)}
      ${h.fuseau ? srow("Fuseau horaire", esc(h.fuseau)) : ""}

      <div class="sub" style="margin-top:20px">Horloge de la barre du haut</div>
      ${srow("Format de l'heure",
             `Ce que montre l'horloge, au milieu de la barre.`,
             `<div class="row" style="flex:none">
                <button class="btn ${h.h12?"ghost":"sel"}" onclick="setHorloge('24h')">24 heures</button>
                <button class="btn ${h.h12?"sel":"ghost"}" onclick="setHorloge('12h')">12 heures</button>
              </div>`)}
      ${srow("Afficher les secondes", "Dans la barre du haut",
             sw(!!h.secondes, "setHorloge('secondes')"))}
      ${srow("Afficher le jour de la semaine", "Dans la barre du haut",
             sw(!!h.jour, "setHorloge('jour')"))}
      ${btnOuvrir("datetime","État complet (timedatectl)")}`;
    }
    case "defaut": {
      const d = etat.defaut || {};
      const a = d.assoc || {};
      const noms = {texte:"Fichiers texte", image:"Images", pdf:"Documents PDF",
                    musique:"Musique", video:"Vidéos"};
      return `<h2>Applications par défaut</h2><div class="sub">Quel logiciel ouvre quoi</div>
      ${srow("Navigateur web", esc(d.navigateur || "non défini"))}
      ${Object.keys(noms).map(k=>
        a[k] ? srow(noms[k], esc(a[k])) : "").join("")}
      ${btnOuvrir("defaut","Changer les applications par défaut")}
      <p class="notice">Autre façon de faire, souvent plus rapide : clic droit sur
      un fichier → <b>Ouvrir avec</b> → <b>Définir par défaut</b>. En ligne de
      commande : <code>lexos defaut</code>.</p>`;
    }
    case "distant": {
      const r = etat.distant || {};
      const PROTOS = [["auto","Deviner"], ["rdp","RDP"], ["vnc","VNC"], ["ssh","SSH"]];
      /*  Ce qu'on affiche quand le partage tourne, c'est L'ADRESSE À DICTER
          au téléphone : « tape ça chez toi ». Sans elle, un partage allumé ne
          sert à rien — l'autre bout ne sait pas où frapper. On donne l'IP de
          chaque carte réseau, port compris, parce qu'un portable branché en
          Wi-Fi ET en câble n'a pas la même adresse des deux côtés. */
      const port = (r.ports || "").split(/[\s,]+/).filter(Boolean)[0] || "";
      const adresses = r.adresses || [];
      return `<h2>Bureau à distance</h2>
      <div class="sub">Montrer cet écran à quelqu'un, ou aller voir une autre machine</div>

      <h3 class="cpt-h3">Montrer cet écran</h3>
      ${r.outil
        ? srow("Partager mon bureau",
               r.actif ? `En marche — ${esc(r.outil)} montre cet écran sur le réseau local`
                       : `Arrêté. À l'allumage, ${esc(r.outil)} demande un mot de passe : c'est celui-là qu'on donne à l'autre.`,
               sw(r.actif, "setDistantPartage()"))
        : srow("Partager mon bureau", "Aucun serveur installé sur cette machine",
               `<span class="etat abs">absent</span>`)}
      ${(r.actif && adresses.length)
        ? `<div class="srow" style="display:block">
             <div class="t" style="margin-bottom:8px">L'adresse à donner</div>
             <div class="row">${adresses.map(a =>
               `<span class="adr" title="${esc(a.interface)}">${esc(a.ip)}${port?":"+esc(port):""}</span>`
             ).join("")}</div>
             <div class="sub" style="margin-top:8px">Une adresse par carte réseau.
               Si l'autre est dans la même maison, n'importe laquelle marche ;
               de l'extérieur, il faut passer par un VPN — jamais ouvrir ce
               port sur la box.</div>
           </div>`
        : ""}
      ${r.actif
        ? `<p class="notice">Le partage s'arrête tout seul à l'extinction. Il ne
             revient pas au démarrage suivant : il faut le rallumer à la main,
             exprès, chaque fois.</p>`
        : ""}

      <h3 class="cpt-h3">Aller voir une autre machine</h3>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Adresse de l'autre machine</div>
        <div class="row" style="gap:8px;align-items:center">
          <input class="champ" id="distAdr" type="text" spellcheck="false"
                 autocomplete="off" placeholder="192.168.1.42  ou  compte@machine"
                 onkeydown="if(event.key==='Enter')distantVers()">
          <button class="btn" onclick="distantVers()">Se connecter</button>
        </div>
        <div class="row" style="margin-top:10px">${PROTOS.map(([v,t]) =>
          `<button class="btn ${distantProto===v?"sel":"ghost"}"
             onclick="setDistantProto('${v}')">${t}</button>`).join("")}</div>
        <div class="sub" style="margin-top:8px">« Deviner » essaie RDP puis VNC
          d'après le port qui répond en face — c'est le bon choix neuf fois sur
          dix. SSH ouvre un terminal, pas une image.</div>
      </div>
      ${srow("Visionneuse (RDP / VNC)",
             r.remmina ? "Remmina est installé" : "Remmina n'est pas installé",
             `<span class="etat ${r.remmina?"ok":"abs"}">${r.remmina?"prête":"absente"}</span>`)}
      ${srow("Terminal à distance (SSH)",
             r.ssh ? "Le client SSH est installé" : "Le client SSH n'est pas installé",
             `<span class="etat ${r.ssh?"ok":"abs"}">${r.ssh?"prêt":"absent"}</span>`)}
      ${btnOuvrir("distant","Détail (terminal)")}
      <p class="notice">${r.outil
        ? "Un bureau à distance ouvre ta machine au réseau : il ne démarre jamais tout seul, et jamais sans mot de passe."
        : "Pour se laisser voir, il faut d'abord un serveur : <code>lexos install x11vnc</code>. Pour aller voir ailleurs, il faut Remmina : <code>lexos install remmina</code>."}</p>`;
    }
    case "tiers": {
      /*  LexOS dit « 100 % Linux », et c'est vrai. Mais « libre » et
          « gratuit » ne sont pas la même chose, et une distribution qui se
          réclame du libre doit pouvoir montrer SA propre liste d'exceptions
          plutôt que de la laisser deviner. Cette page la montre — et elle
          REGARDE la machine : « Steam est installé » et « Steam pourrait
          être installé » ne sont pas la même phrase. */
      const t = etat.tiers || {livres:[], absents:[]};
      const carte = x => `<div class="srow tr" style="display:block">
        <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
          <span class="t">${esc(x.nom)}</span>
          <span class="etat ${x.libre?"ok":"att"}">${x.libre?"libre":"propriétaire"}</span>
          <span class="lic">${esc(x.licence)}</span>
          <span class="etat ${x.present?"ok":"abs"}" style="margin-left:auto">${
            x.present ? "sur cette machine" : (x.livre?"pas installé":"pas téléchargé")}</span>
        </div>
        <div class="d" style="margin-top:6px">${esc(x.role)}</div>
        <div class="d" style="margin-top:4px;opacity:.75">Vient de : ${esc(x.origine)}</div>
      </div>`;

      return `<h2>Logiciels tiers</h2>
      <div class="sub">Ce qui, dans LexOS, n'est pas du Debian ordinaire — et sous quelle licence</div>

      <div class="verite">
        <div class="v-l"><span class="v-oui">Libre ≠ gratuit.</span>
          <b>Libre</b> veut dire qu'on peut lire le code, le modifier et le
          redistribuer. <b>Propriétaire</b> veut dire qu'on peut s'en servir,
          et c'est tout — même quand ça ne coûte rien. Les deux sont sur cette
          page, nommés.</div>
        <div class="v-l"><span class="v-oui">LexOS lui-même est libre.</span>
          Le système, ses outils, cette fenêtre : tout est lisible dans le
          dépôt, copiable et modifiable. Ce qui est fermé ci-dessous vient
          d'ailleurs, et on dit d'où.</div>
      </div>

      <h3 class="cpt-h3">Dans l'ISO</h3>
      ${t.livres.map(carte).join("")}

      <h3 class="cpt-h3">Pas dans l'ISO — téléchargé seulement si tu le demandes</h3>
      <p class="notice">LexOS ne distribue rien de tout ça, donc n'endosse
        aucune de ces licences. Chacun arrive de chez son éditeur, à ta
        demande, et jamais en silence.</p>
      ${t.absents.map(carte).join("")}

      <h3 class="cpt-h3">Ce qui n'est pas là du tout</h3>
      <div class="verite">
        <div class="v-l"><span class="v-oui">Zéro Windows.</span>
          Aucun composant Microsoft, aucune licence Microsoft, rien de Windows
          n'est démarré. Wine, ci-dessus, est une réécriture libre — il ne
          contient pas une ligne de Windows.</div>
        <div class="v-l"><span class="v-oui">Aucun mouchard.</span>
          LexOS n'envoie pas de statistiques d'usage, ne compte pas les
          démarrages et n'a pas de compte. Ce qui parle au réseau le fait
          parce que tu le lances : le navigateur, la Logithèque, les mises à
          jour Debian.</div>
      </div>

      ${btnOuvrir("apropos","La fenêtre À propos complète")}`;
    }
    case "apropos": {
      const lb = etat.libre || {firmwares:0, steam:false, broadcom:false};
      return `<h2>À propos de LexOS</h2><div class="sub">2.0.0 « Nomad »</div>
      ${srow("Système", esc(etat.version))}
      ${srow("Nom de la machine", esc(etat.hote))}
      ${srow("Noyau", esc(etat.noyau))}

      <h3 class="cpt-h3">100 % Linux</h3>
      <div class="verite">
        <div class="v-l"><span class="v-oui">Zéro Windows.</span>
          LexOS n'a besoin d'aucun composant Microsoft, d'aucune licence, et ne
          démarre jamais rien de Windows. Le système entier est assemblé à partir
          des paquets Debian.</div>
        <div class="v-l"><span class="v-oui">Wine non plus.</span>
          Beaucoup croient que Wine réclame une copie de Windows. C'est faux :
          <b>Wine Is Not an Emulator</b> — c'est une réécriture libre des
          fonctions de Windows, faite de zéro, qui tourne nativement sur Linux.
          Pas une ligne de code Microsoft, pas de licence à posséder. Un jeu
          Windows lancé par Wine s'exécute sur du Linux, du début à la fin.</div>
      </div>

      <h3 class="cpt-h3">Ce qui n'est pas libre, et pourquoi</h3>
      <p class="notice">Dire « 100 % Linux » serait malhonnête sans préciser
        ceci. Trois choses peuvent ne pas être du logiciel libre, et voici ce
        qu'il en est <b>sur cette machine</b> :</p>
      ${srow("Micrologiciels (<code>non-free-firmware</code>)",
             `Des petits fichiers chargés <b>dans le matériel</b> — carte Wi-Fi,
              carte graphique — pas des programmes qui tournent sur ton
              processeur. Sans eux, beaucoup de portables n'ont tout simplement
              pas de Wi-Fi. C'est le compromis que fait Debian elle-même depuis
              la version 12.`,
             lb.firmwares
               ? `<span class="etat ok">${lb.firmwares} paquet${lb.firmwares>1?"s":""}</span>`
               : `<span class="etat off">aucun</span>`)}
      ${srow("Steam",
             `Le client de Valve est propriétaire. Il n'est installé que si tu
              le demandes — <code>lexos logitheque install jeux</code>.`,
             lb.steam ? `<span class="etat ok">installé</span>`
                      : `<span class="etat off">non installé</span>`)}
      ${srow("Pilote Wi-Fi Broadcom",
             `Certaines cartes n'ont pas de pilote libre qui fonctionne.
              <code>lexos mac wifi</code> ne le propose que quand la carte
              l'exige vraiment.`,
             lb.broadcom ? `<span class="etat ok">présent</span>`
                         : `<span class="etat off">absent</span>`)}
      <p class="notice">Tout le reste — noyau, bureau, navigateur, outils LexOS —
        est du logiciel libre. Le code de LexOS lui-même est sous licence MIT,
        lisible et modifiable, le branding TI-LEX-AL excepté. Construit avec
        <code>make build</code> depuis le dépôt GitHub.</p>
      ${btnOuvrir("apropos","La fenêtre À propos complète")}`;
    }
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
/*  LA FENÊTRE DOIT OBÉIR À CE QU'ON Y CHOISIT.
    Défaut trouvé en essayant pour de vrai : on choisissait « Manuscrite »,
    tout le bureau passait à l'écriture à la main… et CETTE fenêtre-ci
    restait en Noto Sans. Pareil pour l'accent : on prenait « Bleu », les
    boutons des Paramètres restaient orange. La feuille de style codait les
    deux en dur.

    C'est le pire endroit où rater ça : c'est ici qu'on fait le choix, donc
    ici qu'on regarde pour voir s'il a pris. Une fenêtre qui montre autre
    chose que ce qu'elle vient d'appliquer fait douter du réglage entier.

    On pose donc les deux en variables CSS sur la racine, à chaque rendu.
    « rendu » et pas « au chargement » : après setPolice(), la page doit
    changer TOUT DE SUITE, sans attendre une réouverture. */
function appliqueApparence(){
  const r = document.documentElement.style;
  const pol = TOUTES_POLICES.find(([n]) => n === etat.police);
  //  Repli sur la famille par défaut si l'état nomme une police inconnue —
  //  mieux qu'une page sans police déclarée du tout.
  r.setProperty("--police", pol ? pol[2] : TOUTES_POLICES[0][2]);
  const ac = ACCENTS[etat.accent];
  if(ac){
    r.setProperty("--ac", ac);
    //  La teinte survolée : la même, éclaircie. Sans elle, un accent bleu
    //  garderait un survol orange — le défaut se verrait au premier bouton.
    r.setProperty("--ac-hi", eclaircir(ac, 0.22));
  }
  //  LE MODE, À CHAUD. La page reçoit déjà le mode par ?mode= au démarrage
  //  (le lanceur lit ~/.config/lexos/mode). Mais c'est ICI qu'on en change :
  //  cliquer « ☀ Clair » sans cette ligne repeignait tout le bureau et
  //  laissait CETTE fenêtre-là noire, la seule qu'Alex regardait à ce
  //  moment précis. etat.theme vient de /api/etat, qui l'expose depuis
  //  toujours sous cette clé — rien de nouveau à brancher.
  if(etat.theme === "clair"){ document.documentElement.dataset.mode = "clair"; }
  else { delete document.documentElement.dataset.mode; }
}
/*  Éclaircir une couleur #rrggbb vers le blanc, d'une fraction donnée.
    Calcul plutôt que table : un accent ajouté un jour aura son survol
    sans qu'on ait à penser à l'écrire quelque part. */
function eclaircir(hex, part){
  const m = /^#?([0-9a-f]{6})$/i.exec(hex);
  if(!m) return hex;
  const n = parseInt(m[1], 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255]
    .map(v => Math.round(v + (255 - v) * part));
  return "#" + c.map(v => v.toString(16).padStart(2, "0")).join("");
}

function rend(){ appliqueApparence(); rendNav(); rendSection(); }

/* --- Démarrage ------------------------------------------------------------ */
(async function(){
  const h = location.hash.replace("#","");
  if(h && NAV.some(g=>g.items.some(([c])=>c===h))) sectionActive = h;
  await chargeEtat();
  rend();
})();
