#!/usr/bin/env bash
# =============================================================================
#  🔊 Le volume de la barre du Moteur : l'emoji seul, le réglage dans un menu
# =============================================================================
#  ALEX, photo de la barre du haut du Moteur à l'appui : « le bouton du
#  volume qui prend pas toute la place, on garde l'emoji en tant que volume,
#  pour ensuite on clique dessus pour voir le choix d'ajuster le volume ».
#  La glissière de 170 px et son « 100 % » prenaient autant de place que
#  Capture et Notifications réunis.
#
#  ═══ CE BANC NE RELIT PAS LE CODE, IL CLIQUE ═══
#  La VRAIE page (outils.html, outils.css, outils.js) est chargée dans un
#  vrai Chromium sans écran, avec un faux serveur à la place de /api. Des
#  scénarios y font ce que ferait Alex — ouvrir la barre, cliquer sur 🔊,
#  glisser, couper le son, tourner la roulette, cliquer à côté — et relèvent
#  ce que la page montre vraiment : la largeur du bouton, où tombe le menu,
#  la hauteur que la fenêtre demande, ce qui part vers /api/son.
#
#  ═══ CE QUE LA RELECTURE A APPRIS À CE BANC ═══
#   · Sous --virtual-time-budget, les transitions CSS n'avancent pas : la
#     barre était mesurée HORS de l'écran (top = -68 px), et « le menu tombe
#     sous le bouton » ne pouvait pas échouer. Les animations sont donc
#     coupées, et la barre doit être visible avant toute mesure.
#   · Un faux serveur qui répond tout de suite cache la course qui faisait
#     perdre les crans de la roulette : un scénario répond en 25 ms, avec un
#     cran toutes les 70 ms, comme le vrai pactl.
#   · Une erreur JS rattrapée nulle part passait au vert : elles sont toutes
#     relevées, et la bulle « Le son ne répond pas » aussi.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$RACINE/config/includes.chroot/usr/lib/lexos/bureau/web"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
bilan() { printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; }

NAVIGATEUR=""
for C in /opt/pw-browsers/chromium chromium chromium-browser google-chrome google-chrome-stable; do
	if command -v "$C" >/dev/null 2>&1; then NAVIGATEUR="$C"; break; fi
done
if [ -z "$NAVIGATEUR" ]; then
	non "aucun navigateur sans écran : le bouton du volume n'a PAS été éprouvé (installer chromium)"
	bilan; exit 1
fi

# --- La page d'essai : la vraie page, un faux serveur, des scénarios --------
cp "$WEB/outils.html" "$WEB/outils.css" "$WEB/outils.js" "$WEB/fonds.js" "$BANC/"
cat > "$BANC/faux-serveur.js" <<'JS'
//  Le faux /api : ce que serveur.py rend, sans serveur. Chaque appel est noté.
//  ?depart=N (niveau de départ), ?coupe=1, ?absent=1 (pas de son),
//  ?latence=MS (le vrai /api/son lance trois pactl), ?panne=1 (/api/son
//  injoignable), ?disparait=1 (le son disparaît au premier réglage).
window.__erreurs = [];
addEventListener("error", (e) => __erreurs.push(String(e.message)));
addEventListener("unhandledrejection", (e) => __erreurs.push(String(e.reason)));
//  Les images d'animation, au pas du temps virtuel : sinon un
//  requestAnimationFrame peut passer APRÈS la mesure.
window.requestAnimationFrame = (f) => setTimeout(() => f(performance.now()), 16);
const __q = new URLSearchParams(location.search);
window.__appels = [];
window.__etat = { volume: +(__q.get("depart") || 100), muet: !!__q.get("coupe") };
if (__q.get("absent")) window.__etat.volume = -1;
const __latence = +(__q.get("latence") || 0);
let __reglages = 0;
window.fetch = async (url, opts) => {
  const corps = opts && opts.body ? JSON.parse(opts.body) : undefined;
  __appels.push([String(url), corps]);
  let rep = { ok: true };
  if (url === "/api/outils") {
    rep = { apps: [], sections: [], son: { ...__etat }, notifs: [], dnd: false, audit: false, prenom: "Alex",
            reglages: { accent: "#ff7a18", police: "Space Grotesk" }, bureaux: { n: 4, actuel: 0 } };
  } else if (url === "/api/son") {
    if (__q.get("panne")) throw new TypeError("Failed to fetch");
    __reglages++;
    if (__q.get("disparait")) {
      rep = { ok: false, volume: -1, muet: false };
    } else {
      //  Comme gestes.son : on règle TOUT DE SUITE, la réponse part ensuite.
      if (corps && "volume" in corps) __etat.volume = Math.max(0, Math.min(100, corps.volume));
      if (corps && corps.muet === "toggle") __etat.muet = !__etat.muet;
      if (corps && corps.muet === "off") __etat.muet = false;
      rep = { ok: true, ...__etat };
    }
    if (__latence) await new Promise((r) => setTimeout(r, __latence));
  } else if (url === "/api/bureau") {
    rep = { n: 4, actuel: 1 };
  }
  return { ok: true, json: async () => rep };
};
JS
cat > "$BANC/scenario.js" <<'JS'
(async () => {
  const R = {};
  const q = new URLSearchParams(location.search), cas = q.get("cas") || "principal";
  const dodo = (ms) => new Promise((r) => setTimeout(r, ms));
  const appelsSon = () => __appels.filter(([u]) => u === "/api/son").map(([, c]) => c);
  const nbBureau = () => __appels.filter(([u]) => u === "/api/bureau").length;
  const roue = (el, dy) => el.dispatchEvent(new WheelEvent("wheel", { deltaY: dy, bubbles: true, cancelable: true }));
  const fin = () => {
    R.erreurs = __erreurs;
    R.bulle = $("#bulle").hidden ? "" : $("#bulle").textContent;
    document.body.setAttribute("data-resultat", JSON.stringify(R));
  };
  try {
    await dodo(200);
    outils.ouvrir();
    await dodo(900);
    const son = $("#son"), menuSon = $("#menu-son"), barre = $("#barre");
    R.cache = son.hidden;
    R.icone = $("#son-icone").textContent;
    R.titre = son.title;
    if (son.hidden) return fin();

    if (cas === "principal") {
      const rb = son.getBoundingClientRect();
      R.barreVisible = barre.getBoundingClientRect().top >= 0 && rb.top >= 0;
      R.largeur = Math.round(rb.width);
      R.largeurArret = Math.round($('[data-menu="arret"]').getBoundingClientRect().width);
      R.glissiereDansBarre = !!barre.querySelector('input[type="range"]');
      R.pourcentDansBarre = barre.innerText.includes("%");
      R.texteBarre = son.textContent.trim();
      R.menuFermeAvant = menuSon.hidden;

      son.click(); await dodo(400);
      R.menuOuvert = !menuSon.hidden;
      R.actif = son.classList.contains("actif");
      const mb = menuSon.getBoundingClientRect(), cs = getComputedStyle(menuSon);
      const centre = rb.left + rb.width / 2;
      R.ecart = Math.round(mb.top - rb.bottom);
      R.sousLeBouton = mb.top >= rb.bottom && mb.top - rb.bottom < 60 && mb.left <= centre && centre <= mb.right;
      R.dansEcran = mb.left >= 0 && mb.right <= innerWidth && mb.bottom <= innerHeight;
      R.visibleVraiment = cs.display !== "none" && cs.visibility !== "hidden" && +cs.opacity === 1;
      const gl = $("#volume").getBoundingClientRect();
      R.glissiereLarge = Math.round(gl.width);
      const t = /^taille-(\d+)-/.exec(document.title);
      R.tailleDemandee = t ? +t[1] : -1;
      R.basMenu = Math.ceil(mb.bottom);
      R.glissiere = +$("#volume").value;
      R.pct = $("#pct").textContent;
      //  Saisir la glissière (pointerdown, mousedown) ne referme pas le menu.
      for (const type of ["pointerdown", "mousedown"]) $("#volume").dispatchEvent(new MouseEvent(type, { bubbles: true }));
      await dodo(100);
      R.saisieGardeMenu = !menuSon.hidden;
      for (const type of ["pointerup", "mouseup"]) $("#volume").dispatchEvent(new MouseEvent(type, { bubbles: true }));

      const glisser = async (v) => { $("#volume").value = v; $("#volume").dispatchEvent(new Event("input", { bubbles: true })); await dodo(400); };
      await glisser(20); R.icone20 = $("#son-icone").textContent;
      await glisser(80); R.icone80 = $("#son-icone").textContent;
      await glisser(40);
      R.envoye40 = appelsSon().some((c) => c && c.volume === 40);
      R.icone40 = $("#son-icone").textContent;
      R.titre40 = son.title;
      $("#muet").click(); await dodo(300);
      R.iconeMuet = $("#son-icone").textContent;
      R.coupe = son.classList.contains("coupe");
      R.titreMuet = son.title;
      $("#muet").click(); await dodo(300);
      R.iconeRemis = $("#son-icone").textContent;

      const b0 = nbBureau();
      roue(son, 100); await dodo(400);
      R.rouletteBas = __etat.volume;
      roue(son, -100); roue(son, -100); await dodo(400);
      R.rouletteHaut = __etat.volume;
      roue($("#volume"), 100); await dodo(400);
      R.rouletteMenu = __etat.volume;
      for (let k = 0; k < 12; k++) roue(son, 4);
      await dodo(400);
      R.paveTactile = __etat.volume;
      R.bureauIntact = nbBureau() === b0;
      roue($("#bureaux"), 100); await dodo(300);
      R.bureauAilleurs = nbBureau() > b0;

      document.body.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
      await dodo(200);
      R.fermeDehors = menuSon.hidden;
      son.click(); await dodo(200);
      const rouvert = !menuSon.hidden;
      son.click(); await dodo(200);
      R.bascule = rouvert && menuSon.hidden;
      son.click(); await dodo(200);
      $('[data-menu="capture"]').click(); await dodo(300);
      R.unSeulMenu = menuSon.hidden && !$("#menu-capture").hidden;
    } else if (cas === "rafale") {
      //  Six crans vers soi, un toutes les 70 ms, /api/son qui répond en 25 ms.
      for (let k = 0; k < 6; k++) { roue(son, 100); await dodo(70); }
      await dodo(600);
      R.final = __etat.volume;
      R.dernierEnvoi = appelsSon().slice(-1)[0];
      R.glissiere = +$("#volume").value;
    } else if (cas === "coupe") {
      roue(son, -100); await dodo(400);
      R.envoi = appelsSon().slice(-1)[0];
      R.etat = { ...__etat };
      R.iconeApres = $("#son-icone").textContent;
    } else if (cas === "panne") {
      roue(son, 100); await dodo(400);
      R.glissiere = +$("#volume").value;
      R.titreApres = son.title;
      R.bulleTexte = $("#bulle").hidden ? "" : $("#bulle").textContent;
    } else if (cas === "disparait") {
      son.click(); await dodo(300);
      R.menuOuvert = !menuSon.hidden;
      $("#volume").value = 50; $("#volume").dispatchEvent(new Event("input", { bubbles: true }));
      await dodo(400);
      R.boutonCacheApres = son.hidden;
      R.menuFermeApres = menuSon.hidden;
    } else if (cas === "au-dela") {
      const avant = appelsSon().length;
      roue(son, -100); await dodo(400);
      R.envoisHaut = appelsSon().length - avant;
      R.etatHaut = __etat.volume;
      roue(son, 100); await dodo(400);
      R.envoiBas = appelsSon().slice(-1)[0];
      R.etatBas = __etat.volume;
      roue(son, 100); await dodo(400);
      R.etatBas2 = __etat.volume;
    }
  } catch (e) {
    __erreurs.push("scénario : " + e);
  }
  fin();
})();
JS
python3 - "$BANC/outils.html" "$BANC/essai.html" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
avant = '<script src="fonds.js"></script>'
apres = '<script src="outils.js"></script>'
assert s.count(avant) == 1 and s.count(apres) == 1, "outils.html a changé de forme : le banc doit suivre"
s = s.replace(avant, '<script src="faux-serveur.js"></script>\n' + avant)
s = s.replace(apres, apres + '\n<script src="scenario.js"></script>')
#  Un fond sombre pour la photo (la vraie fenêtre est transparente), et les
#  animations coupées : sous le temps virtuel, une transition n'avance pas,
#  et la barre serait mesurée là où elle part, hors de l'écran.
s = s.replace("</head>", "<style>html{background:#0b0b0c}"
              "*,*::before,*::after{transition:none!important;animation:none!important}</style>\n</head>")
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY

lancer() { # lancer <requête> → le JSON du scénario
	"$NAVIGATEUR" --headless --disable-gpu --no-sandbox --hide-scrollbars \
		--virtual-time-budget=20000 --window-size=1920,520 \
		--dump-dom "file://$BANC/essai.html$1" 2>/dev/null \
		| python3 -c 'import html,re,sys; m=re.search(r"data-resultat=\"([^\"]*)\"", sys.stdin.read()); print(html.unescape(m.group(1)) if m else "")'
}
champ() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print(v if isinstance(v,str) else json.dumps(v, ensure_ascii=False))' "$1" "$2" 2>/dev/null; }
propre() { # propre <JSON> <nom du cas> — aucune erreur JS, aucune bulle
	local e b
	e="$(champ "$1" erreurs)"; b="$(champ "$1" bulle)"
	[ "$e" = "[]" ] && ok "$2 : aucune erreur JS" || non "$2 : erreurs JS : $e"
	[ -z "$b" ] && ok "$2 : aucune bulle d'erreur" || non "$2 : bulle « $b »"
}

echo "== Dans la barre : l'emoji, et rien d'autre"
R="$(lancer "")"
if [ -z "$R" ]; then
	non "la page d'essai n'a rien rendu dans $NAVIGATEUR : le scénario n'a pas tourné"
	bilan; exit 1
fi
propre "$R" "parcours complet"
[ "$(champ "$R" cache)" = "false" ] && ok "le bouton 🔊 est là quand le son répond" || non "le bouton du son est caché alors que le son répond"
[ "$(champ "$R" barreVisible)" = "true" ] && ok "la barre est à l'écran au moment des mesures (pas à -68 px)" || non "la barre est mesurée hors de l'écran : les mesures suivantes ne prouvent rien"
L="$(champ "$R" largeur)"; LA="$(champ "$R" largeurArret)"
[ "${L:-999}" -le 48 ] && [ "${L:-0}" -ge 30 ] \
	&& ok "le bouton du son fait $L px de large — un rond, comme ⏻ ($LA px), au lieu d'environ 290 px" \
	|| non "le bouton du son fait « $L » px : il prend encore la place"
[ "$(champ "$R" glissiereDansBarre)" = "false" ] && [ "$(champ "$R" pourcentDansBarre)" = "false" ] \
	&& ok "ni glissière ni pourcentage nulle part dans la barre" || non "une glissière ou un « % » est encore dans la barre"
[ "$(champ "$R" texteBarre)" = "🔊" ] && ok "la barre montre l'emoji seul : « 🔊 »" || non "la barre montre « $(champ "$R" texteBarre) »"
grep -q '100 %' <<<"$(champ "$R" titre)" && ok "le niveau reste lisible au survol : « $(champ "$R" titre) »" || non "infobulle : « $(champ "$R" titre) »"
[ "$(champ "$R" menuFermeAvant)" = "true" ] && ok "le réglage est caché tant qu'on ne clique pas" || non "le menu du son est ouvert d'emblée"

echo "== Un clic sur 🔊 : le réglage du volume, juste dessous"
[ "$(champ "$R" menuOuvert)" = "true" ] && [ "$(champ "$R" actif)" = "true" ] \
	&& ok "le menu du volume s'ouvre, et 🔊 s'allume comme Capture et Notifications" || non "le clic sur 🔊 n'ouvre pas le réglage"
[ "$(champ "$R" sousLeBouton)" = "true" ] \
	&& ok "le menu tombe SOUS 🔊 ($(champ "$R" ecart) px plus bas), centré sur lui" || non "le menu n'est pas sous 🔊 (écart « $(champ "$R" ecart) » px)"
[ "$(champ "$R" dansEcran)" = "true" ] && ok "le menu reste dans l'écran, bas compris" || non "le menu du son sort de l'écran"
[ "$(champ "$R" visibleVraiment)" = "true" ] && [ "$(champ "$R" glissiereLarge)" -ge 100 ] \
	&& ok "il se VOIT (opacité 1), et la glissière fait $(champ "$R" glissiereLarge) px" || non "menu invisible ou glissière écrasée ($(champ "$R" glissiereLarge) px)"
TD="$(champ "$R" tailleDemandee)"; BM="$(champ "$R" basMenu)"
[ "${TD:--1}" -ge "${BM:-9999}" ] \
	&& ok "la fenêtre du Moteur est priée de grandir assez (taille-$TD ≥ bas du menu, $BM px)" \
	|| non "la fenêtre demandée (taille-$TD) est plus petite que le menu ($BM px) : il serait coupé"
[ "$(champ "$R" glissiere)" = "100" ] && [ "$(champ "$R" pct)" = "100 %" ] \
	&& ok "la glissière part du vrai niveau (100 %)" || non "glissière « $(champ "$R" glissiere) », pourcentage « $(champ "$R" pct) »"
[ "$(champ "$R" saisieGardeMenu)" = "true" ] && ok "saisir la glissière ne referme pas le menu" || non "appuyer sur la glissière referme le menu : on ne peut pas la tirer"
[ "$(champ "$R" envoye40)" = "true" ] && ok "glisser à 40 % envoie { volume: 40 } à /api/son" || non "glisser n'a rien envoyé à /api/son"
[ "$(champ "$R" icone20)" = "🔈" ] && [ "$(champ "$R" icone40)" = "🔉" ] && [ "$(champ "$R" icone80)" = "🔊" ] \
	&& ok "l'emoji suit le niveau : 🔈 à 20 %, 🔉 à 40 %, 🔊 à 80 %" \
	|| non "emoji : « $(champ "$R" icone20) » à 20, « $(champ "$R" icone40) » à 40, « $(champ "$R" icone80) » à 80"
grep -q '40 %' <<<"$(champ "$R" titre40)" && ok "l'infobulle suit aussi : « $(champ "$R" titre40) »" || non "infobulle à 40 % : « $(champ "$R" titre40) »"
[ "$(champ "$R" iconeMuet)" = "🔇" ] && [ "$(champ "$R" coupe)" = "true" ] && [ "$(champ "$R" iconeRemis)" = "🔉" ] \
	&& grep -q '40 %' <<<"$(champ "$R" titreMuet)" \
	&& ok "couper : 🔇, et l'infobulle garde le niveau (« $(champ "$R" titreMuet) ») ; remettre : 🔉" \
	|| non "muet : « $(champ "$R" iconeMuet) » / « $(champ "$R" titreMuet) » puis « $(champ "$R" iconeRemis) »"

echo "== La roulette"
[ "$(champ "$R" rouletteBas)" = "35" ] && [ "$(champ "$R" rouletteHaut)" = "45" ] \
	&& ok "sur 🔊 : un cran vers soi = 5 % de moins (40 → 35), deux crans vers l'avant = 45 %" \
	|| non "roulette sur 🔊 : 40 → « $(champ "$R" rouletteBas) » → « $(champ "$R" rouletteHaut) »"
[ "$(champ "$R" rouletteMenu)" = "40" ] && ok "dans le menu aussi : 45 → 40" || non "la roulette dans le menu : « $(champ "$R" rouletteMenu) »"
[ "$(champ "$R" paveTactile)" = "35" ] && ok "les petits pas d'un pavé tactile s'additionnent : 12 × 4 = un cran (40 → 35)" || non "pavé tactile : « $(champ "$R" paveTactile) »"
[ "$(champ "$R" bureauIntact)" = "true" ] && ok "…sans jamais changer de bureau" || non "la roulette sur le volume a changé de bureau"
[ "$(champ "$R" bureauAilleurs)" = "true" ] && ok "ailleurs sur la barre, la roulette change toujours de bureau" || non "la roulette ne change plus de bureau"

echo "== Fermer"
[ "$(champ "$R" fermeDehors)" = "true" ] && ok "un clic à côté referme le menu du son" || non "le menu du son reste ouvert après un clic à côté"
[ "$(champ "$R" bascule)" = "true" ] && ok "🔊 ouvre, 🔊 referme" || non "re-cliquer sur 🔊 ne referme pas"
[ "$(champ "$R" unSeulMenu)" = "true" ] && ok "ouvrir Capture referme le volume : un seul menu à la fois" || non "deux menus ouverts en même temps"

echo "== La roulette en rafale, avec un /api/son qui met 25 ms (trois pactl)"
R="$(lancer "?cas=rafale&latence=25")"
propre "$R" "rafale"
[ "$(champ "$R" final)" = "70" ] && [ "$(champ "$R" glissiere)" = "70" ] \
	&& ok "six crans, un toutes les 70 ms : 100 → 70 %, aucun cran perdu" \
	|| non "six crans : le volume finit à « $(champ "$R" final) » (glissière « $(champ "$R" glissiere) ») au lieu de 70 — une réponse en retard a effacé des crans"

echo "== Départ à 60 % : l'emoji vient du vrai niveau, pas du HTML"
R="$(lancer "?cas=depart&depart=60")"
[ "$(champ "$R" icone)" = "🔉" ] && grep -q '60 %' <<<"$(champ "$R" titre)" \
	&& ok "à 60 %, la barre montre 🔉 et « 60 % » au survol" || non "à 60 % : « $(champ "$R" icone) » / « $(champ "$R" titre) »"

echo "== Son coupé : la roulette remet le son"
R="$(lancer "?cas=coupe&depart=60&coupe=1")"
propre "$R" "son coupé"
[ "$(champ "$R" icone)" = "🔇" ] && grep -q '60 %' <<<"$(champ "$R" titre)" \
	&& ok "coupé : 🔇, et l'infobulle dit encore le niveau (« $(champ "$R" titre) »)" || non "coupé : « $(champ "$R" icone) » / « $(champ "$R" titre) »"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); e=r["envoi"] or {}; s=r["etat"]; sys.exit(0 if e.get("volume")==65 and e.get("muet")=="off" and s=={"volume":65,"muet":False} and r["iconeApres"]=="🔉" else 1)' "$R" \
	&& ok "un cran vers l'avant sur 🔇 : le son revient, à 65 %, et l'emoji le montre (🔉)" \
	|| non "roulette sur 🔇 : envoi $(champ "$R" envoi), état $(champ "$R" etat), emoji « $(champ "$R" iconeApres) »"

echo "== /api/son injoignable"
R="$(lancer "?cas=panne&panne=1")"
[ "$(champ "$R" erreurs)" = "[]" ] && ok "panne : aucune erreur JS" || non "panne : erreurs JS : $(champ "$R" erreurs)"
[ "$(champ "$R" glissiere)" = "100" ] && grep -q '100 %' <<<"$(champ "$R" titreApres)" \
	&& ok "rien n'a été appliqué : la barre revient au niveau connu (100 %), pas à un 95 % inventé" \
	|| non "après la panne : glissière « $(champ "$R" glissiere) », infobulle « $(champ "$R" titreApres) »"
grep -q 'Le son ne répond pas' <<<"$(champ "$R" bulleTexte)" && ok "…et c'est dit : « Le son ne répond pas »" || non "aucune bulle après la panne"

echo "== Le son disparaît pendant que le menu est ouvert"
R="$(lancer "?cas=disparait&disparait=1")"
[ "$(champ "$R" menuOuvert)" = "true" ] && [ "$(champ "$R" boutonCacheApres)" = "true" ] && [ "$(champ "$R" menuFermeApres)" = "true" ] \
	&& ok "le bouton 🔊 s'en va, et son menu se ferme au lieu de rester sur une glissière morte" \
	|| non "son disparu : bouton caché « $(champ "$R" boutonCacheApres) », menu fermé « $(champ "$R" menuFermeApres) »"

echo "== Au-delà de 100 % (la touche « volume + » monte jusqu'à 150 %)"
R="$(lancer "?cas=au-dela&depart=130")"
propre "$R" "au-delà de 100 %"
grep -q '130 %' <<<"$(champ "$R" titre)" && ok "à 130 %, l'infobulle dit 130 %, pas 100" || non "à 130 % : « $(champ "$R" titre) »"
[ "$(champ "$R" envoisHaut)" = "0" ] && [ "$(champ "$R" etatHaut)" = "130" ] \
	&& ok "un cran « plus fort » ne RAMÈNE pas le son à 100 %" || non "un cran « plus fort » à 130 % a envoyé $(champ "$R" envoisHaut) réglage(s), état « $(champ "$R" etatHaut) »"
[ "$(champ "$R" etatBas)" = "100" ] && [ "$(champ "$R" etatBas2)" = "95" ] \
	&& ok "un cran « moins fort » redescend à 100, le suivant à 95 — pas de chute de 35 points" \
	|| non "vers soi depuis 130 : « $(champ "$R" etatBas) » puis « $(champ "$R" etatBas2) »"

echo "== Son indisponible"
R="$(lancer "?absent=1")"
[ "$(champ "$R" cache)" = "true" ] && ok "sans son (volume -1), le bouton 🔊 disparaît au lieu de régler du vide" || non "bouton du son affiché sans son : « $R »"

#  La photo, pour qui veut voir (LEXOS_PHOTO_SON=dossier) : la barre, puis
#  le menu ouvert.
if [ -n "${LEXOS_PHOTO_SON:-}" ]; then
	mkdir -p "$LEXOS_PHOTO_SON"
	cat > "$BANC/photo.js" <<'JS'
(async () => { await new Promise((r) => setTimeout(r, 200)); outils.ouvrir();
  await new Promise((r) => setTimeout(r, 900));
  if (new URLSearchParams(location.search).get("vue") === "menu") $("#son").click(); })();
JS
	sed 's#<script src="scenario.js"></script>#<script src="photo.js"></script>#' "$BANC/essai.html" > "$BANC/photo.html"
	for vue in barre menu; do
		"$NAVIGATEUR" --headless --disable-gpu --no-sandbox --hide-scrollbars --virtual-time-budget=15000 \
			--window-size=1920,320 --screenshot="$LEXOS_PHOTO_SON/son-$vue.png" "file://$BANC/photo.html?vue=$vue" >/dev/null 2>&1
	done
	echo "  photos : $LEXOS_PHOTO_SON/son-barre.png, son-menu.png"
fi

# =============================================================================
bilan
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLe volume tient dans un rond, et se règle d'"'"'un clic.\033[0m\n'
