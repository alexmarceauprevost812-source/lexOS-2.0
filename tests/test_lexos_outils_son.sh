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
#  vrai Chromium sans écran, avec un faux serveur à la place de /api. Un
#  scénario y fait ce que ferait Alex — ouvrir la barre, cliquer sur 🔊,
#  glisser, couper le son, tourner la roulette, cliquer à côté — et relève ce
#  que la page montre vraiment : la largeur du bouton, où tombe le menu, ce
#  qui part vers /api/son.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$RACINE/config/includes.chroot/usr/lib/lexos/bureau/web"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }

NAVIGATEUR=""
for C in /opt/pw-browsers/chromium chromium chromium-browser google-chrome google-chrome-stable; do
	if command -v "$C" >/dev/null 2>&1; then NAVIGATEUR="$C"; break; fi
done
if [ -z "$NAVIGATEUR" ]; then
	non "aucun navigateur sans écran : le bouton du volume n'a PAS été éprouvé (installer chromium)"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi

# --- La page d'essai : la vraie page, un faux serveur, un scénario ----------
cp "$WEB/outils.html" "$WEB/outils.css" "$WEB/outils.js" "$WEB/fonds.js" "$BANC/"
cat > "$BANC/faux-serveur.js" <<'JS'
//  Le faux /api : ce que serveur.py rend, sans serveur. Chaque appel est noté.
window.__appels = [];
window.__etat = { volume: 100, muet: false };
const __q = new URLSearchParams(location.search);
if (__q.get("absent")) window.__etat.volume = -1;
window.fetch = async (url, opts) => {
  const corps = opts && opts.body ? JSON.parse(opts.body) : undefined;
  __appels.push([String(url), corps]);
  let rep = { ok: true };
  if (url === "/api/outils") {
    rep = { apps: [], sections: [], son: { ...__etat }, notifs: [], dnd: false, audit: false, prenom: "Alex",
            reglages: { accent: "#ff7a18", police: "Space Grotesk" }, bureaux: { n: 4, actuel: 0 } };
  } else if (url === "/api/son") {
    if (corps && "volume" in corps) __etat.volume = corps.volume;
    if (corps && corps.muet === "toggle") __etat.muet = !__etat.muet;
    rep = { ok: true, ...__etat };
  } else if (url === "/api/bureau") {
    rep = { n: 4, actuel: 1 };
  }
  return { ok: true, json: async () => rep };
};
JS
cat > "$BANC/scenario.js" <<'JS'
(async () => {
  const R = {};
  const dodo = (ms) => new Promise((r) => setTimeout(r, ms));
  const appelsSon = () => __appels.filter(([u]) => u === "/api/son").map(([, c]) => c);
  const q = new URLSearchParams(location.search);
  await dodo(200);
  outils.ouvrir();
  await dodo(900);
  const son = $("#son"), arret = $('[data-menu="arret"]'), menuSon = $("#menu-son");
  R.cache = son.hidden;
  if (q.get("absent")) { document.body.setAttribute("data-resultat", JSON.stringify(R)); return; }
  const rb = son.getBoundingClientRect();
  R.largeur = Math.round(rb.width);
  R.largeurArret = Math.round(arret.getBoundingClientRect().width);
  R.glissiereDansBarre = !!$("#barre").querySelector('input[type="range"]');
  R.pctDansBarre = !!$("#barre").querySelector("#pct");
  R.texteBarre = son.textContent.trim();
  R.titre = son.title;
  R.menuFermeAvant = menuSon.hidden;
  if (q.get("vue") === "barre") { document.body.setAttribute("data-resultat", JSON.stringify(R)); return; }

  son.click(); await dodo(400);
  R.menuOuvert = !menuSon.hidden;
  R.actif = son.classList.contains("actif");
  const mb = menuSon.getBoundingClientRect();
  R.menuSous = mb.top >= rb.bottom - 1;
  R.menuDansEcran = mb.left >= 0 && mb.right <= innerWidth;
  R.glissiere = +$("#volume").value;
  R.pct = $("#pct").textContent;
  if (q.get("vue") === "menu") { document.body.setAttribute("data-resultat", JSON.stringify(R)); return; }

  //  Glisser à 40 %.
  $("#volume").value = 40;
  $("#volume").dispatchEvent(new Event("input", { bubbles: true }));
  await dodo(400);
  R.envoye40 = appelsSon().some((c) => c && c.volume === 40);
  R.icone40 = $("#son-icone").textContent;
  R.titre40 = son.title;
  //  Couper, puis remettre.
  $("#muet").click(); await dodo(300);
  R.iconeMuet = $("#son-icone").textContent;
  R.coupe = son.classList.contains("coupe");
  $("#muet").click(); await dodo(300);
  R.iconeRemis = $("#son-icone").textContent;
  //  La roulette sur l'emoji : un cran vers soi = 5 % de moins, et PAS de
  //  changement de bureau.
  const avantBureau = __appels.filter(([u]) => u === "/api/bureau").length;
  son.dispatchEvent(new WheelEvent("wheel", { deltaY: 100, bubbles: true, cancelable: true }));
  await dodo(400);
  R.apresRouletteBas = __etat.volume;
  son.dispatchEvent(new WheelEvent("wheel", { deltaY: -100, bubbles: true, cancelable: true }));
  son.dispatchEvent(new WheelEvent("wheel", { deltaY: -100, bubbles: true, cancelable: true }));
  await dodo(400);
  R.apresRouletteHaut = __etat.volume;
  R.bureauIntact = __appels.filter(([u]) => u === "/api/bureau").length === avantBureau;
  //  La roulette AILLEURS sur la barre change toujours de bureau.
  $("#bureaux").dispatchEvent(new WheelEvent("wheel", { deltaY: 100, bubbles: true, cancelable: true }));
  await dodo(300);
  R.bureauAilleurs = __appels.filter(([u]) => u === "/api/bureau").length > avantBureau;
  //  Un clic dans le vide ferme le menu ; 🔊 rouvre, 🔊 referme.
  document.body.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
  await dodo(200);
  R.fermeDehors = menuSon.hidden;
  son.click(); await dodo(200);
  const rouvert = !menuSon.hidden;
  son.click(); await dodo(200);
  R.bascule = rouvert && menuSon.hidden;
  //  Ouvrir Capture ferme le menu du son (un seul menu à la fois).
  son.click(); await dodo(200);
  $('[data-menu="capture"]').click(); await dodo(300);
  R.unSeulMenu = menuSon.hidden && !$("#menu-capture").hidden;
  document.body.setAttribute("data-resultat", JSON.stringify(R));
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
#  Un fond sombre, seulement pour la photo : la vraie fenêtre est transparente.
s = s.replace("</head>", "<style>html{background:#0b0b0c}</style>\n</head>")
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY

lancer() { # lancer <requête> → le JSON du scénario
	"$NAVIGATEUR" --headless --disable-gpu --no-sandbox --hide-scrollbars \
		--virtual-time-budget=15000 --window-size=1920,520 \
		--dump-dom "file://$BANC/essai.html$1" 2>/dev/null \
		| python3 -c 'import html,re,sys; m=re.search(r"data-resultat=\"([^\"]*)\"", sys.stdin.read()); print(html.unescape(m.group(1)) if m else "")'
}
champ() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print(json.dumps(v, ensure_ascii=False) if not isinstance(v,str) else v)' "$1" "$2" 2>/dev/null; }

echo "== Dans la barre : l'emoji, et rien d'autre"
R="$(lancer "")"
if [ -z "$R" ]; then
	non "la page d'essai n'a rien rendu dans $NAVIGATEUR : le scénario n'a pas tourné"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi
[ "$(champ "$R" cache)" = "false" ] && ok "le bouton 🔊 est là quand le son répond" || non "le bouton du son est caché alors que le son répond"
L="$(champ "$R" largeur)"; LA="$(champ "$R" largeurArret)"
[ "${L:-999}" -le 48 ] && [ "${L:-0}" -ge 30 ] \
	&& ok "le bouton du son fait $L px de large — un rond, comme ⏻ ($LA px), au lieu d'environ 290 px" \
	|| non "le bouton du son fait « $L » px : il prend encore la place"
[ "$(champ "$R" glissiereDansBarre)" = "false" ] && [ "$(champ "$R" pctDansBarre)" = "false" ] \
	&& ok "ni glissière ni « 100 % » dans la barre elle-même" || non "la glissière ou le pourcentage sont encore dans la barre"
[ "$(champ "$R" texteBarre)" = "🔊" ] && ok "la barre montre l'emoji seul : « 🔊 »" || non "la barre montre « $(champ "$R" texteBarre) »"
grep -q '100 %' <<<"$(champ "$R" titre)" && ok "le niveau reste lisible au survol : « $(champ "$R" titre) »" || non "infobulle : « $(champ "$R" titre) »"
[ "$(champ "$R" menuFermeAvant)" = "true" ] && ok "le réglage est caché tant qu'on ne clique pas" || non "le menu du son est ouvert d'emblée"

echo "== Un clic sur 🔊 : le réglage du volume, juste dessous"
[ "$(champ "$R" menuOuvert)" = "true" ] && [ "$(champ "$R" actif)" = "true" ] \
	&& ok "le menu du volume s'ouvre, et 🔊 s'allume comme Capture et Notifications" || non "le clic sur 🔊 n'ouvre pas le réglage"
[ "$(champ "$R" menuSous)" = "true" ] && [ "$(champ "$R" menuDansEcran)" = "true" ] \
	&& ok "le menu tombe SOUS le bouton, sans sortir de l'écran" || non "le menu du son est mal placé"
[ "$(champ "$R" glissiere)" = "100" ] && [ "$(champ "$R" pct)" = "100 %" ] \
	&& ok "la glissière part du vrai niveau (100 %)" || non "glissière « $(champ "$R" glissiere) », pourcentage « $(champ "$R" pct) »"
[ "$(champ "$R" envoye40)" = "true" ] && ok "glisser à 40 % envoie { volume: 40 } à /api/son" || non "glisser n'a rien envoyé à /api/son"
[ "$(champ "$R" icone40)" = "🔉" ] && grep -q '40 %' <<<"$(champ "$R" titre40)" \
	&& ok "à 40 %, l'emoji de la barre devient 🔉 et l'infobulle dit 40 %" || non "à 40 % : emoji « $(champ "$R" icone40) », infobulle « $(champ "$R" titre40) »"
[ "$(champ "$R" iconeMuet)" = "🔇" ] && [ "$(champ "$R" coupe)" = "true" ] && [ "$(champ "$R" iconeRemis)" = "🔉" ] \
	&& ok "couper : 🔇 dans la barre ; remettre : 🔉 revient" || non "muet : « $(champ "$R" iconeMuet) » puis « $(champ "$R" iconeRemis) »"

echo "== La roulette"
[ "$(champ "$R" apresRouletteBas)" = "35" ] && [ "$(champ "$R" apresRouletteHaut)" = "45" ] \
	&& ok "sur 🔊 : un cran vers soi = 5 % de moins (40 → 35), deux crans vers l'avant = 45 %" \
	|| non "roulette sur 🔊 : 40 → « $(champ "$R" apresRouletteBas) » → « $(champ "$R" apresRouletteHaut) »"
[ "$(champ "$R" bureauIntact)" = "true" ] && ok "…sans changer de bureau" || non "la roulette sur 🔊 a changé de bureau"
[ "$(champ "$R" bureauAilleurs)" = "true" ] && ok "ailleurs sur la barre, la roulette change toujours de bureau" || non "la roulette ne change plus de bureau"

echo "== Fermer"
[ "$(champ "$R" fermeDehors)" = "true" ] && ok "un clic à côté referme le menu du son" || non "le menu du son reste ouvert après un clic à côté"
[ "$(champ "$R" bascule)" = "true" ] && ok "🔊 ouvre, 🔊 referme" || non "re-cliquer sur 🔊 ne referme pas"
[ "$(champ "$R" unSeulMenu)" = "true" ] && ok "ouvrir Capture referme le volume : un seul menu à la fois" || non "deux menus ouverts en même temps"

echo "== Son indisponible"
R="$(lancer "?absent=1")"
[ "$(champ "$R" cache)" = "true" ] && ok "sans son (volume -1), le bouton 🔊 disparaît au lieu de régler du vide" || non "bouton du son affiché sans son : « $R »"

#  La photo, pour qui veut voir (LEXOS_PHOTO_SON=dossier) : la barre, puis
#  le menu ouvert.
if [ -n "${LEXOS_PHOTO_SON:-}" ]; then
	mkdir -p "$LEXOS_PHOTO_SON"
	for vue in barre menu; do
		"$NAVIGATEUR" --headless --disable-gpu --no-sandbox --hide-scrollbars --virtual-time-budget=15000 \
			--window-size=1920,320 --screenshot="$LEXOS_PHOTO_SON/son-$vue.png" "file://$BANC/essai.html?vue=$vue" >/dev/null 2>&1
	done
	echo "  photos : $LEXOS_PHOTO_SON/son-barre.png, son-menu.png"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLe volume tient dans un rond, et se règle d'"'"'un clic.\033[0m\n'
