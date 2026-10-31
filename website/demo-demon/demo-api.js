/* Démo web du bureau démon — le « serveur » de LexOS, dans le navigateur.

   Le vrai bureau démon (demon.html) parle à bureau/serveur.py par /api/… .
   Sur le site, ce serveur n'existe pas : ce fichier remplace fetch() pour
   ces adresses-là SEULEMENT, et répond comme lui. Tout le reste de la page
   est le vrai code de LexOS. Généré par tools/gen-demo-demon.py. */
"use strict";
(() => {
  const ETAT = {
 "prenom": "toi",
 "reglages": {
  "mode": "moteur",
  "interface": "demon",
  "demon_theme": "sang",
  "demon_oeil": "rouge",
  "demon_suivre": true,
  "demon_intro": true,
  "demon_pluie": true,
  "demon_presence": 60,
  "demon_grille": [
   "*"
  ],
  "demon_dock": [
   "*"
  ],
  "demon_places": {},
  "accent": "#ff7a18",
  "police": "Space Grotesk",
  "taille": 100,
  "anim": "constellation",
  "image": "",
  "voile": 35,
  "flou": 0,
  "vitesse": 100,
  "densite": 100,
  "orbes": true,
  "grille": true,
  "curseur": true,
  "zoom": true,
  "horloge": true,
  "tilex": true,
  "lexos": true,
  "bureau": true,
  "embleme": "nomad",
  "code": false,
  "labo": true,
  "labo_delai": 1000,
  "labo_apps": [
   "*"
  ],
  "outils": false,
  "outils_fixe": true,
  "outils_apps": [
   "*"
  ],
  "positions": {}
 },
 "sections": [],
 "tilex": false,
 "dock": {
  "cote": "",
  "taille": 0
 },
 "zone": [],
 "labo": [],
 "couleurs": [
  [
   "Orange LexOS",
   "#ff7a18"
  ],
  [
   "Rouge feu",
   "#ff3b30"
  ],
  [
   "Sang",
   "#c81e1e"
  ],
  [
   "Corail",
   "#ff6b6b"
  ],
  [
   "Saumon",
   "#ff8f70"
  ],
  [
   "Rose néon",
   "#ff2d95"
  ],
  [
   "Rose bonbon",
   "#ff7ac6"
  ],
  [
   "Magenta",
   "#e040fb"
  ],
  [
   "Violet",
   "#8b5cf6"
  ],
  [
   "Lavande",
   "#c4b5fd"
  ],
  [
   "Indigo",
   "#6366f1"
  ],
  [
   "Bleu Québec",
   "#1e6bff"
  ],
  [
   "Bleu ciel",
   "#38bdf8"
  ],
  [
   "Cyan",
   "#22d3ee"
  ],
  [
   "Turquoise",
   "#14b8a6"
  ],
  [
   "Émeraude",
   "#10b981"
  ],
  [
   "Menthe",
   "#5eead4"
  ],
  [
   "Vert néon",
   "#39ff14"
  ],
  [
   "Lime",
   "#a3e635"
  ],
  [
   "Jaune",
   "#facc15"
  ],
  [
   "Or",
   "#e8b04a"
  ],
  [
   "Ambre",
   "#f59e0b"
  ],
  [
   "Cuivre",
   "#c87533"
  ],
  [
   "Argent",
   "#cbd5e1"
  ],
  [
   "Blanc pur",
   "#f4f4f5"
  ],
  [
   "Arc-en-ciel",
   "arc-en-ciel"
  ]
 ],
 "polices": [
  "Space Grotesk",
  "Inter",
  "Poppins",
  "Montserrat",
  "Lexend",
  "Nunito",
  "Quicksand",
  "Fredoka",
  "Comfortaa",
  "Exo 2",
  "Rajdhani",
  "Oxanium",
  "Orbitron",
  "Audiowide",
  "Righteous",
  "Bebas Neue",
  "Press Start 2P",
  "JetBrains Mono",
  "Système",
  "Serif classique"
 ],
 "demon": [
  {
   "id": "a-terminal",
   "cle": "terminal",
   "nom": "Terminal"
  },
  {
   "id": "a-fichiers",
   "cle": "fichiers",
   "nom": "Fichiers"
  },
  {
   "id": "a-navigateur",
   "cle": "navigateur",
   "nom": "Navigateur"
  },
  {
   "id": "a-parametres",
   "cle": "parametres",
   "nom": "Paramètres"
  },
  {
   "id": "a-installer",
   "cle": "installer",
   "nom": "Installer LexOS"
  },
  {
   "id": "s-maison",
   "cle": "maison",
   "nom": "Dossier personnel"
  },
  {
   "id": "s-corbeille",
   "cle": "corbeille",
   "nom": "Corbeille"
  },
  {
   "id": "s-github",
   "cle": "github",
   "nom": "GitHub"
  }
 ],
 "systeme": {
  "nom": "LexOS",
  "version": "2.0.3",
  "saveur": "nomade",
  "compte": "toi",
  "noyau": "6.12 (démo web)",
  "processeur": "ton navigateur",
  "memoire": "",
  "allume": ""
 }
};
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

  const reponses = {
    "/api/version": () => ({ v: String(version) }),
    "/api/etat": () => ETAT,
    "/api/reseau": () => ({ etat: "connecte", type: "wifi", nom: "Démo LexOS", signal: 82 }),
    "/api/son": (d) => {
      if (d && typeof d.volume === "number") reponses.son.volume = Math.max(0, Math.min(100, d.volume));
      if (d && d.muet) reponses.son.muet = !reponses.son.muet;
      return reponses.son;
    },
    "/api/outils": () => ({ apps: [], sections: [{ titre: "LexOS", elements: ETAT.demon.filter((e) => e.id.startsWith("a-")) }], prenom: "toi", reglages: {} }),
    "/api/reglages": (d) => {
      for (const [k, v] of Object.entries(d || {})) if (k in ETAT.reglages) ETAT.reglages[k] = v;
      ETAT.reglages.interface = "demon";            // la démo, comme la clé nomade : le démon pour de bon
      version++; garder();
      return { ok: true, reglages: ETAT.reglages };
    },
    "/api/lancer": (d) => {
      const id = String((d && d.id) || "");
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
    b.textContent = "Démo web du bureau démon · Télécharger le vrai LexOS →";
    b.style.cssText = "position:fixed;left:12px;bottom:12px;z-index:9999;padding:7px 12px;border-radius:10px;"
      + "background:rgba(0,0,0,.72);border:1px solid rgba(255,90,0,.55);color:#ffb37a;font:600 12px system-ui,sans-serif;"
      + "text-decoration:none;backdrop-filter:blur(6px)";
    document.body.appendChild(b);
  });
})();
