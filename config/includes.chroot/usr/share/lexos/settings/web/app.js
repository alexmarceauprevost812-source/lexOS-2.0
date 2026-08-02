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

const ACCENTS = {orange:"#E8590C", bleu:"#1A5FB4", rouge:"#C4211E",
                 vert:"#1F8F4E", gris:"#8A8A8A", violet:"#8B5CF6", neon:"#39FF14"};
const LANGUES = [
  ["fr_CA.UTF-8","Français (Québec)"], ["fr_FR.UTF-8","Français (France)"],
  ["en_US.UTF-8","English (US)"], ["en_CA.UTF-8","English (Canada)"],
  ["en_GB.UTF-8","English (UK)"], ["es_ES.UTF-8","Español (España)"],
  ["es_MX.UTF-8","Español (México)"], ["de_DE.UTF-8","Deutsch"],
  ["it_IT.UTF-8","Italiano"], ["pt_BR.UTF-8","Português (Brasil)"],
  ["ru_RU.UTF-8","Русский"], ["zh_CN.UTF-8","中文（简体）"],
  ["ja_JP.UTF-8","日本語"], ["ko_KR.UTF-8","한국어"], ["ar_SA.UTF-8","العربية"],
];

let etat = {perf:"medium", theme:"sombre", accent:"orange", avion:"off",
            hote:"", version:"", noyau:""};
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
function btnOuvrir(section, libelle){
  return `<div class="row"><button class="btn" onclick="ouvrir('${section}')">
    ${libelle || "Ouvrir l'outil complet"}</button></div>`;
}

/* --- Actions déclenchées par la page ------------------------------------- */
async function ouvrir(section){ await api("ouvrir", section); }
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
async function setLangue(l){
  const r = await api("langue", l);
  if(r.ok) toast("Langue changée — reconnecte-toi pour l'appliquer partout");
}
async function capture(mode){ await api("capture", mode); }

/* --- Sections ------------------------------------------------------------- */
function contenu(cle){
  switch(cle){
    case "wifi": return `<h2>Wi-Fi</h2><div class="sub">Réseaux, connexion, mots de passe</div>
      ${srow("Réseaux et VPN","Liste des réseaux, état de la connexion, mots de passe enregistrés")}
      ${btnOuvrir("wifi","Ouvrir l'outil réseau")}
      <p class="notice">En ligne de commande : <code>lexos wifi</code> ·
      <code>lexos net password "&lt;réseau&gt;"</code> pour un mot de passe oublié.</p>`;
    case "reseau": return `<h2>Réseau</h2><div class="sub">Filaire, mode avion, VPN</div>
      ${srow("Mode avion","Coupe Wi-Fi, Bluetooth et données",
             sw(etat.avion==="on","basculeAvion()"))}
      ${btnOuvrir("reseau","Ouvrir l'outil réseau")}
      <p class="notice">VPN : <code>lexos vpn import fichier.ovpn</code> (OpenVPN) ou un
      <code>.conf</code> WireGuard, puis <code>lexos vpn connect "&lt;nom&gt;"</code>.</p>`;
    case "bluetooth": return `<h2>Bluetooth</h2><div class="sub">Appareils appairés</div>
      ${srow("Rechercher des appareils","Balayage et appairage")}
      ${btnOuvrir("bluetooth","Rechercher (lexos bt scan)")}`;
    case "ecrans": return `<h2>Écrans</h2><div class="sub">Disposition multi-écrans</div>
      ${srow("Étendre, dupliquer, écran principal","Résolution et disposition de chaque écran")}
      ${btnOuvrir("ecrans","Ouvrir Écrans")}`;
    case "son": return `<h2>Son</h2><div class="sub">Volume, périphériques</div>
      ${srow("Volume et périphériques","Sortie, entrée, applications")}
      ${btnOuvrir("son","Ouvrir le mélangeur")}`;
    case "energie": return `<h2>Énergie</h2><div class="sub">Profil de performance</div>
      <div class="row">${["petit","medium","performant","max"].map(p=>
        `<button class="btn ${p===etat.perf?"sel":"ghost"}" onclick="setPerf('${p}')">${p}</button>`).join("")}</div>
      <p class="notice">Chaque profil règle vraiment le gouverneur du processeur, zram,
      le compositing et les services (<code>lexos perf</code>).</p>
      <div class="srow" style="display:block;margin-top:16px">
        <div class="t" style="margin-bottom:6px">Luminosité de l'écran</div>
        <div style="display:flex;align-items:center;gap:12px">
          <input type="range" min="5" max="100" value="70"
                 onchange="setLum(this.value)">
        </div>
      </div>
      ${btnOuvrir("energie","État détaillé (terminal)")}`;
    case "usb": return `<h2>Appareils USB</h2><div class="sub">Branchements détectés</div>
      ${srow("Liste des appareils","Clés, disques, téléphones — éjection comprise")}
      ${btnOuvrir("usb","Ouvrir l'outil USB")}
      <p class="notice"><code>lexos vide-memoire</code> copie en un clic tout le contenu
      d'un téléphone ou d'une clé. <code>lexos format</code> formate un support amovible —
      jamais le disque système.</p>`;
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
        <div class="t" style="margin-bottom:8px">Couleur d'accent</div>
        <div class="row">${Object.entries(ACCENTS).map(([n,c])=>
          `<button class="swatch${n===etat.accent?" sel":""}" style="background:${c}"
             title="${n}" onclick="setAccent('${n}')"></button>`).join("")}</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Position de la barre d'outils</div>
        <div class="row">${[["droite","Droite"],["gauche","Gauche"],["bas","Bas"],["haut","Haut"]].map(([v,l])=>
          `<button class="btn ghost" onclick="setDock('${v}')">${l}</button>`).join("")}</div>
      </div>
      ${btnOuvrir("apparence","Réglages fins (XFCE)")}`;
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
      <p class="notice">Aussi : clic droit sur une image dans Fichiers →
      « Définir comme fond d'écran », ou <code>lexos wallpaper ~/Images/photo.jpg</code>.
      Vidéo en fond : <code>lexos wallpaper video ~/Vidéos/boucle.mp4</code>.
      Le fond qui s'écrit tout seul — du vrai code, caractère par caractère,
      figé sur batterie : <code>lexos wallpaper code</code>
      (<code>lexos wallpaper code off</code> remet le fond fixe).</p>
      ${btnOuvrir("bureau","Réglages fins (XFCE)")}`;
    case "multitaches": return `<h2>Multi-tâches</h2><div class="sub">Bureaux virtuels</div>
      ${srow("Bureaux virtuels","Nombre et noms des espaces de travail")}
      ${btnOuvrir("multitaches")}`;
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
    case "souris": return `<h2>Souris et pavé tactile</h2><div class="sub">Vitesse, boutons, défilement</div>
      ${srow("Pointeur","Vitesse, gaucher/droitier, défilement naturel")}
      ${btnOuvrir("souris")}`;
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
    case "datetime": return `<h2>Date et heure</h2><div class="sub">Fuseau horaire</div>
      ${srow("Horloge du système","Fuseau, synchronisation automatique (NTP)")}
      ${btnOuvrir("datetime","État (timedatectl)")}`;
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
