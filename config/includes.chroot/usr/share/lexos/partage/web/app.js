/* =============================================================================
   Partager — ce que fait la page
   =============================================================================
   ELLE NE DÉCIDE RIEN. Tout ce qu'elle affiche vient de /api/etat, servi par
   partage.py ; tout ce qu'elle déclenche passe par /api/action, dont la liste
   est FERMÉE côté serveur. La page ne construit aucun chemin de fichier et ne
   lance aucune commande — même règle que le Volet et les Paramètres.

   LE COMPTE À REBOURS EST CALCULÉ SUR UNE FIN, PAS DÉCRÉMENTÉ.
   Un compteur qui fait « moins un » chaque seconde dérive : setInterval n'est
   pas garanti à la milliseconde, et il s'arrête net quand l'onglet passe en
   arrière-plan ou que la machine se met en veille. Au réveil, il afficherait
   encore 12 minutes sur un partage déjà fermé — c'est-à-dire un mensonge à
   l'écran. On garde donc l'HEURE DE FIN et on recalcule l'écart à chaque
   affichage : la veille n'y change rien.
   ========================================================================== */
(function () {
  "use strict";

  var fin = null;          //  horodatage de fin, en millisecondes
  var minuteur = null;

  function $(id) { return document.getElementById(id); }

  /*  Le nom de fichier vient du disque de l'utilisateur : il peut contenir
      n'importe quoi, y compris des chevrons. On le pose donc par
      textContent — jamais par innerHTML. */
  function ligneFichier(f) {
    var d = document.createElement("div");
    d.className = "fichier";
    var n = document.createElement("span");
    n.className = "nom";
    n.textContent = f.nom;
    var t = document.createElement("span");
    t.className = "taille";
    t.textContent = f.taille;
    d.appendChild(n);
    d.appendChild(t);
    return d;
  }

  function moyen(m) {
    var b = document.createElement("div");
    b.className = "moyen";
    var g = document.createElement("span");
    var t = document.createElement("span");
    t.className = "t";
    t.textContent = m.nom;
    var d = document.createElement("span");
    d.className = "d";
    d.textContent = m.detail;
    g.appendChild(t);
    g.appendChild(d);
    var e = document.createElement("span");
    e.className = "etat" + (m.pret ? " on" : "");
    e.textContent = m.etat;
    b.appendChild(g);
    b.appendChild(e);
    return b;
  }

  function affiche(e) {
    $("url").textContent = e.url;
    $("recus").textContent = e.recus;
    if (e.qr) { $("qr").src = e.qr; }

    var box = $("fichiers");
    box.textContent = "";
    if (!e.fichiers.length) {
      var v = document.createElement("p");
      v.className = "vide";
      v.textContent = "Rien pour l'instant — la page sert quand même à recevoir.";
      box.appendChild(v);
    } else {
      e.fichiers.forEach(function (f) { box.appendChild(ligneFichier(f)); });
    }

    var a = $("autres");
    a.textContent = "";
    e.moyens.forEach(function (m) { a.appendChild(moyen(m)); });

    fin = Date.now() + e.secondes * 1000;
    tic();
    if (!minuteur) { minuteur = setInterval(tic, 1000); }
  }

  function tic() {
    var reste = Math.max(0, Math.round((fin - Date.now()) / 1000));
    var m = Math.floor(reste / 60);
    var s = reste % 60;
    $("reste").textContent = m + ":" + (s < 10 ? "0" : "") + s;
    if (reste === 0) {
      clearInterval(minuteur);
      minuteur = null;
      $("temoin").classList.add("mort");
      $("reste").parentNode.childNodes[2].textContent = " Partage fermé";
      $("reste").textContent = "";
    }
  }

  function action(quoi) {
    return fetch("api/action", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: quoi })
    });
  }

  $("copier").addEventListener("click", function () {
    var b = this;
    var texte = $("url").textContent;
    /*  navigator.clipboard exige un contexte sûr. 127.0.0.1 en est un aux
        yeux de Chromium — mais QtWebEngine peut être bâti sans l'API, et une
        promesse rejetée laisserait le bouton sans réponse. Le repli par
        execCommand marche partout. */
    var fait = function () {
      b.textContent = "Copié";
      b.classList.add("fait");
      setTimeout(function () {
        b.textContent = "Copier";
        b.classList.remove("fait");
      }, 1600);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(texte).then(fait, replis);
    } else {
      replis();
    }
    function replis() {
      var z = document.createElement("textarea");
      z.value = texte;
      z.setAttribute("readonly", "");
      z.style.position = "absolute";
      z.style.left = "-9999px";
      document.body.appendChild(z);
      z.select();
      try { document.execCommand("copy"); fait(); } catch (err) { /* tant pis */ }
      document.body.removeChild(z);
    }
  });

  $("ouvrir").addEventListener("click", function () { action("ouvrir-recus"); });
  $("fermer").addEventListener("click", function () { action("fermer"); });

  fetch("api/etat")
    .then(function (r) { return r.json(); })
    .then(affiche)
    .catch(function () {
      /*  Si l'état ne vient pas, la page ne doit pas rester muette avec des
          points de suspension : on le dit, et on laisse le bouton Fermer. */
      $("url").textContent = "le serveur de partage n'a pas répondu";
    });
})();
