/* Démo web du bureau démon — le « serveur » de LexOS, dans le navigateur.

   Le vrai bureau démon (demon.html) parle à bureau/serveur.py par /api/… .
   Sur le site, ce serveur n'existe pas : ce fichier remplace fetch() pour
   ces adresses-là SEULEMENT, et répond comme lui. Tout le reste de la page
   est le vrai code de LexOS. Généré par tools/gen-demo-demon.py. */
"use strict";
(() => {
  const ETAT = /*__ETAT__*/null;
  const CLE = "lexos-demo-demon";
  let version = 1, numero = 0;

  //  Les réglages changés dans la démo (thème, couleur des yeux, disposition)
  //  restent dans CE navigateur. Jamais indispensable : tout marche sans.
  try {
    const garde = JSON.parse(localStorage.getItem(CLE) || "null");
    if (garde && typeof garde === "object") {
      Object.assign(ETAT.reglages, garde.reglages || {});
      if (Array.isArray(garde.bureau)) ETAT.demon.push(...garde.bureau);
    }
  } catch {}
  const garder = () => {
    try {
      localStorage.setItem(CLE, JSON.stringify({
        reglages: ETAT.reglages, bureau: ETAT.demon.filter((e) => e.id.startsWith("b-")) }));
    } catch {}
  };
  const dire = (t) => setTimeout(() => window.bulle && window.bulle(t), 60);
  const nomDe = (id) => (ETAT.demon.find((e) => e.id === id) || {}).nom || "cette appli";

  //  Les applis « installées » de la démo, pour « Ajouter une application ici… ».
  const INSTALLEES = [
    ["a-demo-gimp", "GIMP — retouche photo"], ["a-demo-libreoffice", "LibreOffice Writer"],
    ["a-demo-vlc", "VLC"], ["a-demo-steam", "Steam"], ["a-demo-vscode", "Code"],
    ["a-demo-musique", "LexOS Musique"], ["a-demo-capture", "Capture d'écran"],
    ["a-demo-calculatrice", "Calculatrice"], ["a-demo-agenda", "Agenda"], ["a-demo-claude", "Claude"],
  ].map(([id, nom]) => ({ id, nom, icone: false }));
  const avecAjouts = () => {
    const d = ETAT.demon.filter((e) => !e.ajout);
    for (const id of ETAT.reglages.demon_ajouts || []) {
      const a = INSTALLEES.find((x) => x.id === id);
      if (a) d.push({ id, cle: "appli", nom: a.nom, icone: false, ajout: true });
    }
    ETAT.demon = d;
    return ETAT;
  };
  const reponses = {
    "/api/version": () => ({ v: String(version) }),
    "/api/etat": () => avecAjouts(),
    "/api/reseau": () => ({ etat: "connecte", type: "wifi", nom: "Démo LexOS", signal: 82 }),
    "/api/son": (d) => {
      if (d && typeof d.volume === "number") reponses.son.volume = Math.max(0, Math.min(100, d.volume));
      if (d && d.muet) reponses.son.muet = !reponses.son.muet;
      return reponses.son;
    },
    "/api/outils": () => ({ apps: [], prenom: "toi", reglages: {}, sections: [
      { titre: "LexOS", elements: ETAT.demon.filter((e) => e.id.startsWith("a-") && !e.ajout) },
      { titre: "Toutes les applications", elements: INSTALLEES }] }),
    "/api/reglages": (d) => {
      for (const [k, v] of Object.entries(d || {})) if (k in ETAT.reglages) ETAT.reglages[k] = v;
      ETAT.reglages.interface = "demon";            // la démo, comme la clé nomade : le démon pour de bon
      version++; garder();
      return { ok: true, reglages: ETAT.reglages };
    },
    "/api/lancer": (d) => {
      const id = String((d && d.id) || "");
      if (!nomDe(id) || nomDe(id) === "cette appli") { const a = INSTALLEES.find((x) => x.id === id); if (a) { dire(`Démo : dans le vrai LexOS, « ${a.nom} » s'ouvrirait ici`); return { ok: true }; } }
      if (id === "s-github") { window.open("https://github.com/alexmarceauprevost812-source/lexOS-2.0", "_blank", "noopener"); return { ok: true }; }
      dire(`Démo : dans le vrai LexOS, « ${nomDe(id)} » s'ouvrirait ici`);
      return { ok: true };
    },
    "/api/demander": () => { dire("Démo : dans le vrai LexOS, ti-lex IA répondrait ici"); return { ok: true }; },
    "/api/session": (d) => { dire(`Démo : dans le vrai LexOS, l'ordinateur ferait « ${(d && d.geste) || "?"} »`); return { ok: true }; },
    "/api/action": (d) => {
      const nom = String((d && d.nom) || "");
      if (nom === "nouveau-dossier" || nom === "nouveau-document") {
        numero++;
        const dossier = nom === "nouveau-dossier";
        ETAT.demon.push({ id: `b-demo-${Date.now()}`, cle: dossier ? "dossier" : "document", icone: false,
                          nom: (dossier ? "Nouveau dossier" : "Nouveau document.txt").replace(/(\.txt)?$/, numero > 1 ? ` ${numero}$1` : "$1") });
        version++; garder();
        return { ok: true };
      }
      dire("Démo : dans le vrai LexOS, ça s'ouvrirait ici");
      return { ok: true };
    },
  };
  reponses.son = { volume: 60, muet: false };
  //  Les bureaux virtuels de la démo : quatre, comme LexOS.
  const bureaux = { n: 4, actuel: 0 };
  reponses["/api/bureaux"] = () => bureaux;
  reponses["/api/bureau"] = (d) => {
    const i = Number(d && d.aller);
    if (Number.isInteger(i) && i >= 0 && i < bureaux.n && i !== bureaux.actuel) {
      bureaux.actuel = i;
      dire(`Bureau ${i + 1} — dans le vrai LexOS, ses fenêtres à lui apparaîtraient ici`);
    }
    return { ok: true, ...bureaux };
  };

  const fetchVrai = window.fetch.bind(window);
  window.fetch = async (entree, init) => {
    const url = new URL(typeof entree === "string" ? entree : entree.url, location.href);
    const f = url.origin === location.origin && reponses[url.pathname];
    if (!f) return fetchVrai(entree, init);
    let corps;
    try { corps = init && init.body ? JSON.parse(init.body) : undefined; } catch { corps = undefined; }
    const r = f(corps);
    return new Response(JSON.stringify(r), { status: 200, headers: { "Content-Type": "application/json" } });
  };

  //  Le petit bandeau de la démo : on sait qu'on est sur le site, pas dans LexOS.
  addEventListener("DOMContentLoaded", () => {
    const b = document.createElement("a");
    b.href = "/telecharger";
    b.textContent = "Démo web du bureau LexOS · Télécharger le vrai LexOS →";
    b.style.cssText = "position:fixed;left:12px;bottom:12px;z-index:9999;padding:7px 12px;border-radius:10px;"
      + "background:rgba(0,0,0,.72);border:1px solid rgba(255,90,0,.55);color:#ffb37a;font:600 12px system-ui,sans-serif;"
      + "text-decoration:none;backdrop-filter:blur(6px)";
    document.body.appendChild(b);
  });
})();
