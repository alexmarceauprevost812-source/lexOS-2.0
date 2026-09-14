/* =============================================================================
 *  Le client commun des pages LexOS — écrit UNE fois
 * =============================================================================
 *  ALEX : « un moteur pour tous les paramètres, que ça soit encore plus fluide
 *  et rapide ».
 *
 *  COMPTÉ AVANT : esc() existait en TROIS exemplaires (settings, volet, ia),
 *  api() en trois, chargeEtat() en trois, toast() en deux. Les mêmes gestes,
 *  et les mêmes divergences : un esc() qui rendait « null » là où l'autre
 *  rendait du vide, un api() qui annonce l'erreur là où l'autre la rend en
 *  silence, un chargeEtat() qui fusionne là où l'autre remplace.
 *
 *  app.js du volet nommait déjà le risque : « la dupliquer ici donnerait deux
 *  endroits où un bogue pourrait un jour raconter deux choses différentes ».
 *
 *  ⚠ CE FICHIER NE DÉCIDE DE RIEN À LA PLACE DES PAGES. Chaque divergence
 *  utile est devenue un ARGUMENT, pas un choix pris ici : le volet annonce
 *  toujours ses refus dans ses tuiles, les Paramètres toujours dans leur
 *  bandeau, et chargeEtat() RETOURNE l'état au lieu de l'affecter — c'est la
 *  page qui sait si elle fusionne ou remplace.
 *
 *  Servi par moteur/service.py sur /moteur/client.js, pour les quatre
 *  fenêtres à la fois. Pas de cadriciel, pas d'étape de construction : ce
 *  fichier se lit et se répare tel quel, comme tout le reste de ce dépôt.
 * ===========================================================================*/
"use strict";

/*  ⚠ « var » ET PAS « window.LexOS », ET C'EST DÉLIBÉRÉ.
    Un « var » au premier niveau crée un global dans un navigateur COMME dans
    un contexte vm de node — c'est-à-dire dans les treize bancs de ce dépôt
    qui chargent les pages hors d'un navigateur pour les éprouver pour de
    vrai. « window.LexOS » aurait obligé chacun d'eux à fabriquer un objet
    « window » qui soit AUSSI son global, et un banc qui monte mal son
    harnais mesure autre chose que la page. */
var LexOS = (function(){

  /* --- Échapper ----------------------------------------------------------- */
  /*  ⚠ LA SEULE DIVERGENCE QUE LA FUSION TRANCHE, ET ELLE EST DITE.
      Il y avait deux formes : « String(s) » (settings, volet) et
      « String(s ?? "") » (ia). Sur une valeur absente, la première AFFICHE le
      mot « null » — une chaîne qui a l'air d'une donnée et n'en est pas. On
      ne peut pas fusionner trois fonctions qui diffèrent sans en choisir une ;
      celle-ci rend du vide, ce que la doctrine de ce dépôt demande partout
      ailleurs : ne rien afficher plutôt qu'afficher quelque chose de faux.

      ET ELLE N'ÉCHAPPE PAS L'APOSTROPHE — c'est voulu, et c'est documenté
      dans settings/web/app.js : pour une valeur posée dans un
      onclick="f('…')", c'est escJs() qu'il faut, pas celle-ci. */
  const esc = s => String(s ?? "").replace(/[&<>"]/g,
    c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

  /* --- Annoncer ----------------------------------------------------------- */
  let toastT = null;
  /*  Le bandeau du bas. « duree » parce que les Paramètres l'affichent 2,6 s
      et l'IA 3,6 s : une réponse de modèle se lit plus lentement qu'un
      « Thème : sombre ». */
  function toast(msg, duree){
    const t = document.getElementById("toast");
    if(!t) return;
    t.textContent = msg; t.hidden = false;
    clearTimeout(toastT);
    toastT = setTimeout(()=>{ t.hidden = true; }, duree || 2600);
  }

  /* --- Agir --------------------------------------------------------------- */
  /*  opts.annonce      : fonction qui montre un message. Absente, l'appelant
                          se charge lui-même de dire le refus — c'est ce que
                          fait le volet, qui l'écrit dans la tuile concernée.
      opts.motifReseau  : ce qu'on dit quand le pont local ne répond pas.
                          Absent, on rend l'erreur brute du navigateur.
      opts.annonceSucces: annoncer aussi j.message quand tout va bien. */
  async function api(action, arg, opts){
    const o = opts || {};
    try{
      const r = await fetch("/api/action", {method:"POST",
        headers:{"Content-Type":"application/json"},
        body:JSON.stringify({action, arg})});
      const j = await r.json();
      if(!j.ok && j.erreur && o.annonce) o.annonce("✗ " + j.erreur);
      if(j.ok && j.message && o.annonce && o.annonceSucces) o.annonce(j.message);
      return j;
    }catch(e){
      const motif = o.motifReseau || String(e);
      if(o.annonce){ o.annonce("✗ " + motif); return {ok:false}; }
      return {ok:false, erreur:motif};
    }
  }

  /* --- Lire --------------------------------------------------------------- */
  /*  ═══ SANS ARGUMENT : TOUT. AVEC UNE LISTE, MÊME VIDE : SEULEMENT ELLE ═══
      « cles && cles.length » confondait les deux, et une section qui n'a
      besoin de RIEN redemandait donc les quarante collecteurs — exactement
      le contraire. Le serveur fait la même distinction ; elle ne sert à rien
      si un seul des deux côtés la fait.

      ET ON RETOURNE L'ÉTAT, ON NE L'AFFECTE PAS. Les Paramètres FUSIONNENT
      (ils ne demandent qu'une section à la fois, le reste doit survivre) ; le
      volet REMPLACE. Décider ici aurait cassé l'un des deux. */
  async function litEtat(cles){
    const q = cles === undefined ? ""
            : "?cles=" + encodeURIComponent(cles.join(","));
    try{ return await (await fetch("/api/etat" + q)).json(); }
    catch(e){ return null; }
  }

  return {esc, toast, api, litEtat};
})();
