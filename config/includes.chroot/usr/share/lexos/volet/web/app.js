/* =============================================================================
 *  Volet LexOS — notifications, agenda, météo, paramètres rapides
 * =============================================================================
 *  Ce fichier fait, sur la VRAIE machine, ce que la démo web fait pour de faux :
 *  les notifications viennent du journal de xfce4-notifyd, les rendez-vous d'un
 *  fichier à nous, la météo d'Open-Meteo par lexos-meteo, et les bascules
 *  rapides (Wi-Fi, Bluetooth, mode avion, performance, thème, effets TV…)
 *  parlent aux mêmes commandes que la fenêtre des Paramètres. Le dessin, lui,
 *  est le même des deux côtés — c'est la règle qu'Alex a posée.
 * ===========================================================================*/
const esc = s => String(s).replace(/[&<>"]/g,
  c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

let etat = {};
const QUOI = (location.hash || "#agenda").slice(1);

async function api(action, arg){
  try{
    const r = await fetch("/api/action", {method:"POST",
      headers:{"Content-Type":"application/json"},
      body: JSON.stringify({action, arg})});
    return await r.json();
  }catch(e){ return {ok:false, erreur:String(e)}; }
}
async function chargeEtat(){
  try{ etat = await (await fetch("/api/etat")).json(); }
  catch(e){ etat = {}; }
}

/* --- Les ciels — LA MÊME TABLE QUE LA DÉMO -------------------------------- */
/*  Deux pictogrammes par ciel : celui de la barre (petit, où un dessin chargé
    devient une tache) et celui du volet (grand, sur un disque teinté). Et un
    jeu de nuit, parce qu'un grand soleil à 23 h est faux.
    La clé (soleil, voile, nuages, pluie, averse, neige) est décidée par
    lexos-meteo d'après le code de l'OMM : la correspondance vit à un seul
    endroit, pas ici en plus. */
const CIELS = {
  soleil: {grand:"☀️", nuit:"🌙", nom:"Ensoleillé", nomNuit:"Ciel dégagé",
           teinte:"rgba(245,166,35,.16)", bord:"rgba(245,166,35,.35)"},
  voile:  {grand:"🌤️", nuit:"☁️", nom:"Partiellement nuageux", nomNuit:"Quelques nuages",
           teinte:"rgba(160,180,205,.14)", bord:"rgba(160,180,205,.30)"},
  nuages: {grand:"🌥️", nuit:"☁️", nom:"Nuageux", nomNuit:"Nuageux",
           teinte:"rgba(140,148,160,.14)", bord:"rgba(140,148,160,.30)"},
  pluie:  {grand:"🌦️", nuit:"🌧️", nom:"Pluie", nomNuit:"Pluie",
           teinte:"rgba(90,140,200,.16)", bord:"rgba(90,140,200,.34)"},
  averse: {grand:"⛈️", nuit:"⛈️", nom:"Orage", nomNuit:"Orage",
           teinte:"rgba(120,110,190,.16)", bord:"rgba(120,110,190,.34)"},
  neige:  {grand:"❄️", nuit:"🌨️", nom:"Neige", nomNuit:"Neige",
           teinte:"rgba(180,205,230,.16)", bord:"rgba(180,205,230,.34)"},
};
const estNuit = h => h < 6 || h >= 20;

/* --- Notifications -------------------------------------------------------- */
function notifHTML(){
  const n = etat.notifications || [];
  const liste = n.length
    ? n.map(x=>`<div class="nf-item">
         <div style="min-width:0">
           <div class="t">${esc(x.titre || x.app || "Notification")}</div>
           ${x.corps ? `<div class="c">${esc(x.corps)}</div>` : ""}
         </div>
         <div class="h">${esc(x.quand || "")}</div>
       </div>`).join("")
    : `<div class="nf-vide">Aucune notification.
         Les messages du système s'afficheront ici.</div>`;
  return `<div class="nf-tete">
      <span class="nf-titre">🔔 Notifications</span>
      ${n.length ? `<span class="nf-cpt">${n.length}</span>` : ""}
      <button class="btn ghost mini" style="margin-left:auto"
              onclick="videNotifs()">Tout effacer</button>
    </div>
    <div class="nf-liste">${liste}</div>`;
}
async function videNotifs(){
  await api("notif-vide");
  await rafraichir();
}

/* --- Agenda --------------------------------------------------------------- */
/*  L'état de navigation vit ICI et pas dans le Python : changer de mois ne
    regarde pas la machine, et faire un aller-retour réseau pour ça rendrait
    les flèches molles. */
const JOURS = ["LUN","MAR","MER","JEU","VEN","SAM","DIM"];
const MOIS = ["janvier","février","mars","avril","mai","juin","juillet",
              "août","septembre","octobre","novembre","décembre"];
let vue = null;

function cle(a,m,j){
  return `${a}-${String(m+1).padStart(2,"0")}-${String(j).padStart(2,"0")}`;
}
function agInit(){
  const auj = etat.aujourdhui || new Date().toISOString().slice(0,10);
  const [a,m,j] = auj.split("-").map(Number);
  if(!vue) vue = {a, m:m-1, sel:auj, auj};
}
function agNav(pas){
  let m = vue.m + pas, a = vue.a;
  if(m < 0){ m = 11; a--; }
  if(m > 11){ m = 0; a++; }
  vue.m = m; vue.a = a;
  rend();
}
function agAujourdhui(){
  const [a,m] = vue.auj.split("-").map(Number);
  vue.a = a; vue.m = m-1; vue.sel = vue.auj;
  rend();
}
function agChoisit(k){ vue.sel = k; rend(); }

function agendaHTML(){
  agInit();
  const evts = etat.agenda || {};
  //  Le premier du mois, ramené au lundi de sa semaine. getDay() donne 0 pour
  //  dimanche : la formule le remet en fin de semaine, comme au Québec.
  const premier = new Date(vue.a, vue.m, 1);
  const decalage = (premier.getDay() + 6) % 7;
  const nbJours = new Date(vue.a, vue.m + 1, 0).getDate();

  let cases = "";
  for(let i = 0; i < decalage; i++) cases += `<span class="ag-c hors"></span>`;
  for(let j = 1; j <= nbJours; j++){
    const k = cle(vue.a, vue.m, j);
    const classes = ["ag-c"];
    if(k === vue.auj) classes.push("auj");
    if(k === vue.sel && k !== vue.auj) classes.push("sel");
    cases += `<button class="${classes.join(" ")}" onclick="agChoisit('${k}')">
        ${j}${evts[k] ? '<span class="ag-pt"></span>' : ""}</button>`;
  }

  const duJour = evts[vue.sel] || [];
  const listeJour = duJour.length
    ? duJour.map((e,i)=>`<div class="ag-evt">
        <span class="h">${esc(e.heure || "—")}${e.fin ? " → " + esc(e.fin) : ""}</span>
        <span class="t">${esc(e.titre)}</span>
        <button class="btn ghost mini" style="margin-left:auto"
                onclick="agEnleve('${vue.sel}',${i})">✕</button>
      </div>`).join("")
    : `<div class="notice">Rien de prévu ce jour-là.</div>`;

  return `<div class="nf-sep"><span>📅 Agenda</span></div>
    <div class="ag-tete">
      <button class="btn ghost mini" onclick="agNav(-1)">‹</button>
      <div class="ag-titre">${MOIS[vue.m]} ${vue.a}</div>
      <button class="btn ghost mini" onclick="agNav(1)">›</button>
      <button class="btn mini" style="margin-left:auto"
              onclick="agAujourdhui()">Aujourd'hui</button>
    </div>
    <div class="ag-grille">
      ${JOURS.map(j=>`<div class="ag-jn">${j}</div>`).join("")}
      ${cases}
    </div>
    <div class="ag-jour">
      ${listeJour}
      <div class="ag-ajout">
        <input class="h" id="agH" placeholder="09:00" maxlength="5"
               aria-label="Heure de début">
        <!--  ALEX : « ajouter une heure de fin d'événement ». Facultative :
              beaucoup de rendez-vous n'en ont pas, et l'exiger casserait le
              geste rapide qui marchait déjà. Le « à » entre les deux champs
              dit à quoi sert le second sans mot d'explication. -->
        <span class="ag-a">à</span>
        <input class="h" id="agF" placeholder="10:00" maxlength="5"
               aria-label="Heure de fin (facultative)"
               onkeydown="if(event.key==='Enter')agAjoute()">
        <input class="t" id="agT" placeholder="Ajouter un rendez-vous…"
               maxlength="120" aria-label="Titre"
               onkeydown="if(event.key==='Enter')agAjoute()">
        <button class="btn" onclick="agAjoute()">Ajouter</button>
      </div>
    </div>`;
}
async function agAjoute(){
  const t = document.getElementById("agT");
  const h = document.getElementById("agH");
  const f = document.getElementById("agF");
  if(!t || !t.value.trim()) return;
  const r = await api("agenda-ajoute",
    {jour: vue.sel, titre: t.value.trim(),
     heure: h ? h.value.trim() : "", fin: f ? f.value.trim() : ""});
  //  LE MOTIF DU REFUS, PAS UN « ajout refusé » GÉNÉRIQUE. Le moteur sait
  //  déjà dire « la fin doit venir après le début » ou « une heure de fin
  //  demande une heure de début » : le taire obligerait à deviner ce qu'on
  //  a mal tapé.
  if(!r.ok){ alert(r.erreur || "Ajout refusé"); return; }
  t.value = ""; h.value = ""; if(f) f.value = "";
  await rafraichir();
}
async function agEnleve(jour, rang){
  await api("agenda-enleve", {jour, rang});
  await rafraichir();
}

/* --- Météo ---------------------------------------------------------------- */
function meteoHTML(){
  const m = etat.meteo || {};
  if(!m.maintenant){
    return `<div style="padding:22px 18px">
        <div style="font-size:38px;margin-bottom:10px">🌫️</div>
        <div style="font-weight:600;margin-bottom:6px">Pas de relevé</div>
        <p class="notice">${esc(m.erreur === "aucune ville choisie"
          ? "Aucune ville n'est choisie. LexOS ne devine pas où tu es."
          : (m.erreur || "Le service météo n'a pas répondu — connexion ?"))}</p>
        <button class="btn" style="margin-top:12px"
                onclick="choisitVille()">Choisir ma ville</button>
      </div>`;
  }
  const h = new Date().getHours();
  const nuit = estNuit(h);
  const c = CIELS[m.maintenant.cle] || CIELS.nuages;
  const glyphe = nuit ? c.nuit : c.grand;
  const nom = nuit ? c.nomNuit : c.nom;

  //  Le jour 0 est aujourd'hui : il est déjà en grand au-dessus.
  const etiquettes = ["Demain","Après-demain","Dans 3 jours"];
  const jours = (m.jours || []).slice(1, 4).map((j, i)=>{
    const cj = CIELS[j.cle] || CIELS.nuages;
    return `<div class="mt-j">
        <div class="mt-j-n">${etiquettes[i] || ""}</div>
        <div class="mt-j-i">${cj.grand}</div>
        <div class="mt-j-t">${j.max}°</div>
        <div class="mt-j-d">${esc(cj.nom)}</div>
      </div>`;
  }).join("");

  return `<div style="--mt-teinte:${c.teinte};--mt-bord:${c.bord}">
      <div class="mt-grand">
        <div class="mt-grand-i">${glyphe}</div>
        <div>
          <div class="mt-grand-t">${m.maintenant.temp}<span>°C</span></div>
          <div class="mt-grand-d">${esc(nom)}</div>
          <div class="mt-grand-v">${esc(m.ville || "")}${
            m.maintenant.vent ? ` · vent ${m.maintenant.vent} km/h` : ""}</div>
        </div>
      </div>
      ${jours ? `<div class="mt-jours">${jours}</div>` : ""}
      <div style="padding:0 16px 16px">
        <button class="btn ghost mini" onclick="choisitVille()">Changer de ville</button>
      </div>
    </div>`;
}
async function choisitVille(){ await api("meteo-ville"); }

/* --- Paramètres rapides ---------------------------------------------------
 *  MÊME GRILLE QUE LA DÉMO (.qs-grid/.qs-tile), sans le sous-menu Wi-Fi/
 *  Bluetooth ni le mode compact : la vraie liste de réseaux et d'appareils
 *  vit déjà dans Paramètres, la dupliquer ici donnerait deux endroits où un
 *  bogue pourrait un jour raconter deux choses différentes.
 * -------------------------------------------------------------------------*/
function qsTileHTML(cle, icone, titre, sous, actif, desactive){
  const classes = `qs-tile${actif ? " on" : ""}${desactive ? " qs-disabled" : ""}`;
  const clic = desactive ? "" : ` onclick="rapidesClic('${cle}')"`;
  return `<div class="${classes}"${clic} title="${esc(titre)}" role="button" tabindex="0">
      <span class="ic">${icone}</span>
      <span class="ti">${esc(titre)}</span>
      <span class="su">${esc(sous)}</span>
    </div>`;
}
function rapidesHTML(){
  const r = etat.rapides || {};
  const wifiOn = !!r.wifi, btOn = !!r.bt, avionOn = !!r.avion;
  const tuiles = [
    qsTileHTML("wifi", "📶", "Wi-Fi", avionOn ? "Mode avion" : (wifiOn ? "Activé" : "Désactivé"),
               wifiOn, avionOn),
    qsTileHTML("bt", "🔵", "Bluetooth", avionOn ? "Mode avion" : (r.bt === null ? "Absent" : (btOn ? "Activé" : "Désactivé")),
               btOn, avionOn || r.bt === null),
    qsTileHTML("avion", "✈️", "Mode avion", avionOn ? "Activé" : "Désactivé", avionOn, false),
    qsTileHTML("partage", "📤", "Partager", "Envoyer un fichier", false, false),
    qsTileHTML("perf", "⚡", "Performance", r.perfLabel || "", r.perf === "performant" || r.perf === "max", false),
    //  ═══ PAS DE TUILE JOUR/NUIT ICI ═══
    //  ALEX : « les paramètres rapides, supprimer pour le thème de jour et de
    //  nuit, et garder le thème de nuit officiel. » LexOS Noir EST le thème,
    //  pas une option parmi deux : une bascule à portée de pouce invitait à
    //  quitter le seul mode que tout le reste de l'ISO suppose.
    //
    //  Le thème de jour n'est pas supprimé pour autant — « lexos theme clair »
    //  le donne toujours, et cette page le suit (voir appliqueModeVolet()).
    //  Ce qui disparaît, c'est le raccourci, pas la possibilité.
    qsTileHTML("clavier", "⌨️", "Clavier", "Français (Québec)", false, false),
    qsTileHTML("crt", "📺", "Effets TV 1980", r.crt ? "Activés" : "Désactivés", r.crt, false),
  ];
  //  ═══ LA PLAQUE GRISE ═══
  //  ALEX : « autour des boutons c'est déjà joli, mais on pourrait mettre du
  //  gris où les espaces vides pour que ça fasse encore plus joli » — puis,
  //  pour lever le doute : « les boutons sont bien parfaits, juste ajouter
  //  du gris autour des boutons. »
  //
  //  Les tuiles ne bougent donc PAS d'un pixel. Ce qui change, c'est le vide
  //  autour : elles touchaient presque le bord du volet (2 px), posées à même
  //  le noir. Elles reposent maintenant sur une plaque grise qui prend toute
  //  la hauteur restante — le gris remplit les gouttières entre les tuiles,
  //  le pourtour, et le grand vide sous la dernière rangée.
  return `<div class="qs">
      <div class="qs-head"><span class="t">Paramètres rapides</span></div>
      <div class="qs-plaque"><div class="qs-grid">${tuiles.join("")}</div></div>
    </div>`;
}
async function rapidesClic(cle){
  await api(`rapides-${cle}`);
  await rafraichir();
}

/* --- Rendu ---------------------------------------------------------------- */
//  LE MODE, À CHAUD — même correctif que Paramètres (appliqueApparence()),
//  jamais reporté ici. La page reçoit ?mode= au tout premier lancement (voir
//  index.html), mais rien ne le remettait à jour ensuite : cliquer la tuile
//  « Thème » du volet changeait bien ~/.config/lexos/mode (rafraichir()
//  relit l'état, le libellé ☀/🌑 de la tuile suivait) — la SURFACE DU VOLET,
//  elle, restait figée dans le mode où elle avait ouvert jusqu'à la fermer
//  et la rouvrir. C'est exactement ce qui ressemblait à « le thème jour/nuit
//  ne fonctionne pas ». etat.rapides.theme n'existe que pendant que ce
//  volet-ci est ouvert (_rapides_etat() n'est peuplé que pour lui) — c'est
//  justement le seul moment où ce bouton peut avoir été cliqué.
function appliqueModeVolet(){
  const theme = etat.rapides && etat.rapides.theme;
  if(theme === "clair") document.documentElement.dataset.mode = "clair";
  else if(theme === "sombre") delete document.documentElement.dataset.mode;
  //  ═══ ET L'ACCENT, QUI N'ÉTAIT POSÉ NULLE PART ═══
  //  ALEX : « c'est la couleur orange qui ne change pas. » Ce volet-ci était
  //  le pire cas : il ne remplaçait JAMAIS l'accent. ui.css en pose un par
  //  défaut — l'orange — et rien ici ne l'écrasait, donc les tuiles
  //  restaient orange même avec un accent bleu partout ailleurs sur le
  //  bureau. Pas un bogue de rafraîchissement : la ligne n'existait pas.
  //
  //  « etat.accent » vient du même /api/etat que tout le reste de cette
  //  page ; il était donc déjà reçu, et simplement ignoré. La table des
  //  couleurs vit dans ui.css, partagée avec les Paramètres : poser
  //  l'attribut suffit, et les deux fenêtres ne peuvent plus diverger.
  if(etat.accent) document.documentElement.dataset.accent = etat.accent;
}
function rend(){
  document.getElementById("dedans").innerHTML =
    QUOI === "meteo" ? meteoHTML()
    : QUOI === "rapides" ? rapidesHTML()
    : (notifHTML() + agendaHTML());
  appliqueModeVolet();
}
async function rafraichir(){ await chargeEtat(); rend(); }

/*  Échap referme — Qt écoute la fermeture de la fenêtre, mais une page qui ne
    répond pas à Échap ne ressemble pas à un menu. */
addEventListener("keydown", e => { if(e.key === "Escape") window.close(); });

(async function(){
  await chargeEtat();
  rend();
  //  Deux images successives avant d'ouvrir : la première pose le contenu à
  //  l'état fermé, la seconde déclenche la transition. Tout faire d'un coup
  //  ferait apparaître le volet déjà ouvert, sans animation — c'est
  //  exactement le piège qu'on a évité côté démo.
  requestAnimationFrame(()=>requestAnimationFrame(()=>
    document.getElementById("volet").classList.add("on")));
})();
