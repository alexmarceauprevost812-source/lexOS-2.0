/* =============================================================================
 *  Volet LexOS — notifications, agenda, météo
 * =============================================================================
 *  Ce fichier fait, sur la VRAIE machine, ce que la démo web fait pour de faux :
 *  les notifications viennent du journal de xfce4-notifyd, les rendez-vous d'un
 *  fichier à nous, la météo d'Open-Meteo par lexos-meteo. Le dessin, lui, est le
 *  même des deux côtés — c'est la règle qu'Alex a posée.
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
        <span class="h">${esc(e.heure || "—")}</span>
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
               aria-label="Heure">
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
  if(!t || !t.value.trim()) return;
  const r = await api("agenda-ajoute",
    {jour: vue.sel, titre: t.value.trim(), heure: h.value.trim()});
  if(!r.ok){ alert(r.erreur || "Ajout refusé"); return; }
  t.value = ""; h.value = "";
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

/* --- Rendu ---------------------------------------------------------------- */
function rend(){
  document.getElementById("dedans").innerHTML =
    QUOI === "meteo" ? meteoHTML() : (notifHTML() + agendaHTML());
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
