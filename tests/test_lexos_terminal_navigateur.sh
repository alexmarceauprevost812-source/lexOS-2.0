#!/usr/bin/env bash
# =============================================================================
#  Éprouver LexOS Pro Terminal DANS UN VRAI NAVIGATEUR, contre le VRAI pont
# =============================================================================
#  ══ POURQUOI CE BANC EXISTE À CÔTÉ DES AUTRES ══
#
#  test_lexos_terminal_pty.sh éprouve le pont : le pseudo-terminal, les
#  quatre routes, les trois serrures. Il ne peut RIEN dire de l'affichage.
#  Or c'est là qu'était toute la moitié visible du travail : xterm.js, la
#  grille de caractères, les frappes qui partent, la taille qui suit.
#
#  Un bac à sable avec un « fetch » simulé ne l'aurait pas vu — et ce dépôt
#  en a déjà payé le prix : « printf "%s" "$HOME" » sans saut de ligne collait
#  le dossier personnel au nom d'utilisateur (« /rootroot »), et seul le
#  chargement de la VRAIE page dans un VRAI navigateur contre un VRAI pont
#  l'a montré. Alors on charge la vraie page dans Chromium, on TAPE au
#  clavier, et on lit ce que le terminal affiche vraiment.
#
#  ══ CE QUE CE BANC A TROUVÉ EN ÉTANT ÉCRIT ══
#
#  1. « ACCUEIL is not defined » — la déclaration avait disparu en même temps
#     que l'ancien pont. La page ne s'ouvrait pas du tout. Aucune relecture
#     de code ne l'avait attrapé ; le navigateur l'a dit en une ligne.
#  2. Les polices allaient chez Google à CHAQUE ouverture
#     (ERR_CONNECTION_RESET hors ligne). Le terminal principal du système
#     attendait une réponse qui ne vient jamais avant de peindre.
#  3. /favicon.ico réclamé puis 404 à chaque lancement.
#
#  ══ ET ON LIT LE TAMPON, PAS LE DOM ══
#  Première version : les contrôles lisaient « .xterm-rows > div ». Trois
#  d'entre eux étaient rouges alors que le terminal marchait parfaitement —
#  le DOM ne porte que les lignes VISIBLES, et pas sous une forme qu'on lit
#  au texte. Le tampon de xterm.js (buffer.active) est la seule source
#  honnête de ce que le terminal affiche.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

titre "LexOS Pro Terminal dans un vrai navigateur"

#  ═══ DE QUOI ON A BESOIN, ET CE QU'ON DIT QUAND ÇA MANQUE ═══
#  Ce banc demande trois choses qu'une machine de construction n'a pas
#  forcément. Quand elles manquent on le DIT — « sauté » et non « réussi » :
#  un banc qui s'annonce vert sans avoir rien éprouvé est pire que pas de banc.
NODE="$(command -v node || echo /opt/node22/bin/node)"
PW=""
for D in /opt/node22/lib/node_modules/playwright /usr/lib/node_modules/playwright \
         /usr/local/lib/node_modules/playwright "$RACINE/node_modules/playwright"; do
	[ -f "$D/index.mjs" ] && { PW="$D/index.mjs"; break; }
done

#  ═══ ON DEMANDE À PLAYWRIGHT OÙ IL A MIS CHROMIUM ═══
#  CE QUE ÇA FAISAIT AVANT : on devinait la disposition —
#  « chromium-XXXX/chrome-linux/chrome » — et on cherchait à deux ou trois
#  endroits connus. Ça a tenu jusqu'à ce que playwright change de version.
#  Relevé sur le coureur, journal à l'appui : le navigateur ÉTAIT bien posé
#
#      navigateurs posés dans /home/runner/work/_temp/lexos-navigateurs :
#      chromium-1243
#      chromium_headless_shell-1243
#
#  et le banc disait quand même « absent : chromium », parce que le binaire
#  n'était plus sous « chrome-linux/ ». Deviner la disposition interne d'un
#  outil, c'est se condamner à la corriger à chaque version — le dépôt le
#  dit déjà ailleurs à propos des noms de bibliothèques.
#  playwright, lui, SAIT. « chromium.executablePath() » rend le chemin exact,
#  quelle que soit la version et quel que soit PLAYWRIGHT_BROWSERS_PATH.
CHROME=""
if [ -n "$PW" ] && [ -x "$NODE" ]; then
	CHROME="$("$NODE" --input-type=module -e "
		import('$PW').then(p => console.log(p.chromium.executablePath()))
		  .catch(() => process.exit(1));
	" 2>/dev/null | tail -1)"
	[ -n "$CHROME" ] && [ -x "$CHROME" ] || CHROME=""
fi
#  REPLI : une machine qui a un Chromium de playwright mais pas le paquet
#  playwright lui-même (l'image de ce conteneur, par exemple).
if [ -z "$CHROME" ]; then
	for C in "${PLAYWRIGHT_BROWSERS_PATH:-/nonexistent}"/chromium-*/chrome-linux*/chrome \
	         /opt/pw-browsers/chromium-*/chrome-linux*/chrome \
	         /opt/pw-browsers/chromium/chrome-linux*/chrome \
	         "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome; do
		[ -x "$C" ] && { CHROME="$C"; break; }
	done
fi
XTERM_JS=""; XTERM_CSS=""; XTERM_FIT=""
for R in /usr/share/nodejs /usr/lib/nodejs /tmp/faux/nodejs; do
	[ -f "$R/xterm/lib/xterm.js" ] && XTERM_JS="$R/xterm/lib/xterm.js"
	[ -f "$R/xterm/css/xterm.css" ] && XTERM_CSS="$R/xterm/css/xterm.css"
	[ -f "$R/xterm-addon-fit/lib/xterm-addon-fit.js" ] && XTERM_FIT="$R/xterm-addon-fit/lib/xterm-addon-fit.js"
done

MANQUE=""
[ -x "$NODE" ]        || MANQUE="$MANQUE node"
[ -n "$CHROME" ]      || MANQUE="$MANQUE chromium"
[ -n "$PW" ]          || MANQUE="$MANQUE playwright"
[ -n "$XTERM_JS" ]    || MANQUE="$MANQUE node-xterm"
python3 -c "import os,pty; m,e=pty.openpty(); os.close(m); os.close(e)" 2>/dev/null \
                      || MANQUE="$MANQUE /dev/pts"
if [ -n "$MANQUE" ]; then
	#  ═══ SAUTER EST PERMIS SUR UNE MACHINE, PAS SUR LE COUREUR ═══
	#  CE QUE ÇA FAISAIT AVANT : ce banc se sautait et rendait 0 — donc VERT
	#  — dès qu'il manquait un outil. Sur le coureur GitHub, il manquait
	#  TOUJOURS quelque chose : l'étape de la CI n'installait ni node-xterm,
	#  ni playwright, ni Chromium, et elle ne cherchait le navigateur que
	#  dans /opt, où playwright ne le pose jamais là-bas. Résultat mesurable
	#  dans le journal : l'étape « Le terminal s'affiche pour de vrai » dure
	#  ZÉRO SECONDE à chaque construction depuis qu'elle existe.
	#
	#  Autrement dit : le SEUL banc qui éprouve l'affichage du terminal
	#  principal n'a jamais tourné, et il annonçait vert. C'est exactement le
	#  faux vert que ce dépôt traque partout ailleurs.
	#
	#  Sauter garde son sens sur la machine de quelqu'un qui n'a pas
	#  Chromium. Sur la CI, non : LEXOS_EXIGER_NAVIGATEUR=1 en fait un ROUGE.
	if [ "${LEXOS_EXIGER_NAVIGATEUR:-0}" = "1" ]; then
		non "absent :$MANQUE — et LEXOS_EXIGER_NAVIGATEUR=1 : ici, l'affichage DOIT être éprouvé"
		printf '\n\033[1m═══ TOTAL ═══\033[0m\n  réussis : %d\n  échoués : %d\n' "$REUSSIS" "$ECHOUES"
		exit 1
	fi
	saute "absent :$MANQUE — l'AFFICHAGE du terminal n'a PAS été éprouvé ici"
	saute "  (le pont, lui, l'est par tests/test_lexos_terminal_pty.sh)"
	printf '\n\033[1m═══ TOTAL ═══\033[0m\n  réussis : 0\n  sauté   : ce banc demande un vrai navigateur\n'
	exit 0
fi

#  vendor/ : exactement ce que le hook 0455 pose sur l'ISO.
mkdir -p "$WEB/vendor"
NETTOYER=0
[ -e "$WEB/vendor/xterm.js" ] || NETTOYER=1
ln -sf "$XTERM_JS"  "$WEB/vendor/xterm.js"
ln -sf "$XTERM_CSS" "$WEB/vendor/xterm.css"
ln -sf "$XTERM_FIT" "$WEB/vendor/xterm-addon-fit.js"
if [ "$NETTOYER" = "1" ]; then
	trap 'rm -f "$WEB/vendor/xterm.js" "$WEB/vendor/xterm.css" "$WEB/vendor/xterm-addon-fit.js"; rmdir "$WEB/vendor" 2>/dev/null' EXIT
fi

ESSAI="$(mktemp -d)"
cat > "$ESSAI/page.mjs" <<'JS'
//  « import » ne prend qu'un chemin littéral ; le nôtre vient de
//  l'environnement (playwright n'est pas au même endroit partout).
//  « import() » dynamique, lui, accepte une variable.
import { spawn, spawnSync } from 'node:child_process';
import fsb from 'node:fs';
const { chromium } = await import(process.env.LEXOS_PW);

const BACKEND = process.env.LEXOS_BACKEND, WEB = process.env.LEXOS_WEB;
const py = `
import importlib.util, time
spec = importlib.util.spec_from_file_location("tp", "${BACKEND}")
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
srv, port, jeton = tp.demarrer_serveur()
print("PRET %d %s" % (port, jeton), flush=True)
time.sleep(600)`;
//  ⚠ 600 s ET PAS 240. L'essai a droit à « timeout 420 » (voir la fin de ce
//  fichier) depuis que les points du démarrage bloqué attendent exprès. Avec
//  240, le pont principal s'arrêtait AU MILIEU sur une machine lente, et
//  toutes les sections qui réutilisent son adresse rougissaient — un rouge
//  qui ne dit pas ce qui ne va pas. C'est moi qui ai créé cet écart en
//  portant la limite de l'essai à 420 sans toucher à celle du pont ; la
//  règle est simple : le pont survit à l'essai, jamais l'inverse.
//  UN PONT = UN PROCESSUS. Les identifiants de volets sont comptés par la
//  PAGE (1, 2, 3…) : deux pages sur le même pont se disputeraient les mêmes
//  numéros de session. Le contrôle de la grille rattrapée ouvre donc une
//  seconde page contre un SECOND pont, à lui.
//  Un thème COMPLET — les cinq clefs que poserTheme() exige en bloc, et les
//  seize ANSI. Il sert au point de la guérison : on remplace le tube nommé par
//  ce fichier-là, et la page doit pouvoir repeindre pour de bon.
const THEME_ENTIER = ['LEXOS_TERM_MODE=nuit', 'LEXOS_TERM_EFFECTIF=nuit',
  'LEXOS_TERM_BG=#0B0B0C', 'LEXOS_TERM_FG=#7BD88F', 'LEXOS_TERM_CURSEUR=#FF8A2B',
  'LEXOS_TERM_TEXTE=#E8E6E3',
  'LEXOS_TERM_PALETTE=' + Array.from({length: 16},
    (_, i) => '#' + String(i).padStart(2, '0') + '1122').join(';'),
].join('\n') + '\n';

//  ═══ ET UN BANC N'HÉRITE PAS DU FOYER DE CELUI QUI LE LANCE ═══
//  DIXIÈME FOIS pour ce chantier, et cette fois dans ce fichier-ci.
//  CE QUE ÇA FAISAIT, mesuré : « pont() » passait {...process.env} tel quel,
//  donc le pont lisait et ÉCRIVAIT dans le VRAI « ~/.config/lexos ». Le
//  contrôle de persistance poste 18,5 px — il changeait donc pour de bon la
//  taille du texte de celui qui lance le banc, et il la LISAIT de lui : sur
//  une machine dont terminal-pro.json disait déjà 18,5, le contrôle passait
//  sans rien discriminer ; sur un dossier de configuration en lecture seule,
//  il rougissait sur du code juste. Les deux faux verdicts, dans un banc écrit
//  pour les traquer.
//  On épingle HOME **et** XDG_CONFIG_HOME sous le dossier d'essai : le pont
//  retombe sur « $HOME/.config » quand la variable ne porte rien (c'est
//  « dossier_theme() »), donc en épingler une seule laisserait la porte ouverte.
const FOYER = process.env.LEXOS_BANC + '/foyer';
fsb.mkdirSync(FOYER + '/.config/lexos', {recursive: true});

//  « sur » : un cas qui a besoin de son PROPRE foyer en passe un (le contrôle
//  du thème bloqué, plus bas, y pose un tube nommé — il ne doit pas le poser
//  dans le foyer que tous les autres partagent).
const pont = async (sur) => {
  const foyer = sur || FOYER;
  //  ⚠ LE PATH DU DÉPÔT EST OBLIGATOIRE. Le menu de réglages lance
  //  « lexos-terminal jour|nuit|auto », qui n'est pas INSTALLÉ sur le coureur :
  //  il est DANS L'ARBRE. Sans cette ligne, le pont répond « Indisponible :
  //  lexos-terminal est introuvable dans le PATH » — le bon message, pour la
  //  mauvaise raison — et le point du menu rougit sur du code juste. C'est
  //  exactement ce qui est arrivé en CI : « coché ["auto"], fond #000000 ».
  //  ⚠ ET LE COUREUR N'EST PAS ROOT, contrairement à mon conteneur : c'est
  //  donc la branche du SUCCÈS qui s'exécute là-bas, pas celle du refus. Un
  //  banc qui ne tourne qu'en root n'aurait jamais vu ce défaut.
  const pr = spawn('python3', ['-c', py], {env: {...process.env,
    HOME: foyer, XDG_CONFIG_HOME: foyer + '/.config',
    LEXOS_TERMINAL_PRO_WEB: WEB,
    PATH: process.env.LEXOS_BIN + ':' + process.env.PATH}});
  const [, p, j] = await new Promise(r => pr.stdout.on('data', d => {
    const m = String(d).match(/PRET (\d+) (\S+)/); if (m) r(m);
  }));
  return {proc: pr, port: p, jeton: j, foyer};
};
//  ═══ UN PONT QU'ON PEUT ARRÊTER À L'INSTANT CHOISI ═══
//  Le pont ci-dessus vit 240 s, quelle que soit la fenêtre. LE VRAI NON :
//  le navigateur livré est un QWebEngineView dans LE MÊME processus que le
//  pont, et main() enchaîne « app.exec() → fermer_toutes() → grâce →
//  serveur.shutdown() → sys.exit() » sans un souffle. Un banc qui mesure la
//  fermeture contre un pont immortel mesure la mansuétude de page.close(),
//  pas le produit. Celui-ci reproduit l'ordonnancement : on ferme la page,
//  puis on dit au pont d'attendre sa grâce et de s'arrêter.
//  ⚠ LA GRÂCE VIENT DU PONT, pas de ce fichier. Le stub l'imprime au
//  démarrage : le point mesure donc la valeur LIVRÉE, et pas une constante
//  réécrite ici qui finirait par ne plus dire la même chose.
const pyArret = `
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("tp", "${BACKEND}")
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
srv, port, jeton = tp.demarrer_serveur()
print("PRET %d %s %s" % (port, jeton, tp.GRACE_FERMETURE), flush=True)
grace = float((sys.stdin.readline() or "0").strip() or "0")
time.sleep(grace)
srv.shutdown()
print("ARRETE", flush=True)
time.sleep(10)`;

//  ═══ UN PONT DONT LA LECTURE DU THÈME NE REND JAMAIS LA MAIN ═══
//  ⚠ POURQUOI PAS UN TUBE NOMMÉ, COMME AVANT : le pont REFUSE maintenant
//  d'ouvrir ce qui n'est pas un fichier ordinaire — un tube ne bloque donc
//  plus rien, et le point qui s'en servait passerait au vert sans rien
//  éprouver. Ce garde est bon, mais il ne couvre PAS un montage mort : stat()
//  y bloque aussi. C'est pour ce cas-là que la page garde ses deux ceintures,
//  et c'est ce cas-là qu'on injecte ici — dans le VRAI pont, en arrêtant la
//  SEULE fonction qu'un montage mort arrêterait. Toutes les autres routes
//  vivent : le pty, les frappes, les réglages.
//  LE TÉMOIN EST UN FICHIER : tant qu'il existe, la lecture dort. L'effacer
//  rend le pont sain, ce qui permet d'éprouver la guérison sur le même pont.
const pontSourd = async (foyer) => {
  const temoin = foyer + '/.sourd';
  fsb.writeFileSync(temoin, '');
  const pySourd = `
import importlib.util, os, time
spec = importlib.util.spec_from_file_location("tp", "${BACKEND}")
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
_vrai = tp.lire_theme
def _sourd(*a, **k):
    while os.path.exists("${temoin}"):
        time.sleep(0.05)
    return _vrai(*a, **k)
tp.lire_theme = _sourd
srv, port, jeton = tp.demarrer_serveur()
print("PRET %d %s" % (port, jeton), flush=True)
time.sleep(600)`;
  const pr = spawn('python3', ['-c', pySourd], {env: {...process.env,
    HOME: foyer, XDG_CONFIG_HOME: foyer + '/.config',
    LEXOS_TERMINAL_PRO_WEB: WEB,
    PATH: process.env.LEXOS_BIN + ':' + process.env.PATH}});
  pr.stderr.on('data', () => {});
  const [, p, j] = await new Promise(r => pr.stdout.on('data', d => {
    const m = String(d).match(/PRET (\d+) (\S+)/); if (m) r(m);
  }));
  return {proc: pr, port: p, jeton: j, guerir: () => fsb.unlinkSync(temoin)};
};

const pontArretable = async (foyer) => {
  const pr = spawn('python3', ['-c', pyArret], {env: {...process.env,
    HOME: foyer, XDG_CONFIG_HOME: foyer + '/.config',
    LEXOS_TERMINAL_PRO_WEB: WEB,
    PATH: process.env.LEXOS_BIN + ':' + process.env.PATH}});
  pr.stderr.on('data', () => {});
  const [, p, j, g] = await new Promise(r => pr.stdout.on('data', d => {
    const m = String(d).match(/PRET (\d+) (\S+) (\S+)/); if (m) r(m);
  }));
  return {proc: pr, port: p, jeton: j, grace: parseFloat(g),
          //  « 0 » = l'ancien enchaînement, sans grâce : le témoin négatif.
          arreter: (g2) => new Promise(r => {
            pr.stdout.on('data', d => { if (/ARRETE/.test(String(d))) r(); });
            pr.stdin.write(String(g2) + '\n');
          })};
};

const {proc, port, jeton} = await pont();

const nav = await chromium.launch({executablePath: process.env.LEXOS_CHROME, args: ['--no-sandbox']});
const page = await nav.newPage({viewport: {width: 1200, height: 760}});
const ennuis = [];
page.on('pageerror', e => ennuis.push('erreur JS : ' + e.message));
page.on('requestfailed', r => ennuis.push('requête échouée : ' + r.url().slice(0, 70)));
page.on('response', r => { if (!r.ok()) ennuis.push('HTTP ' + r.status() + ' ' + r.url().slice(0, 70)); });

const dit = (b, m) => console.log((b ? 'OK|' : 'NON|') + m);
//  LE TAMPON, PAS LE DOM : voir l'en-tête de ce fichier.
//  ═══ ET UNE LIGNE QUI SE REPLIE EST **UNE** LIGNE ═══
//  MESURÉ, et ça a coûté une construction rouge. xterm.js range une ligne
//  trop longue sur DEUX lignes de tampon, la seconde marquée « isWrapped ».
//  Ce lecteur les recollait avec un saut de ligne au milieu — donc le texte
//  affiché à l'écran, celui qu'un humain lit d'un trait, arrivait coupé en
//  deux au banc.
//  Sur le coureur GitHub, l'invite de bash est « runner@fv-az…:~$ » (24
//  caractères) dans une grille de 80 colonnes. Le contrôle des soixante
//  frappes rapides écrit « echo » + 60 caractères : 89 colonnes, donc la
//  ligne se replie. Le banc ne retrouvait la rafale qu'UNE fois au lieu de
//  deux et criait « frappes mélangées » — alors que le shell avait tout reçu
//  dans l'ordre. Reproduit ici à l'identique en forçant 80 colonnes et cette
//  invite-là : lecture brute 1 / lecture recollée 2.
//  Un banc qui accuse la frappe pour une histoire de largeur de fenêtre ne
//  mesure pas ce qu'il annonce.
const ecran = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); if (!f || !f.term) return '';
  const b = f.term.buffer.active, out = [];
  for (let i = 0; i < b.length; i++) {
    const l = b.getLine(i); if (!l) continue;
    const t = l.translateToString(true);
    if (l.isWrapped && out.length) out[out.length - 1] += t;
    else out.push(t);
  }
  return out.join('\n');
});
//  LE MÊME ÉCRAN, LU BRUTALEMENT : une ligne de tampon = une ligne. Il ne
//  sert qu'à UN contrôle — celui qui prouve que le recollement ci-dessus
//  change vraiment quelque chose. Sans cette seconde lecture, un contrôle
//  « sur une ligne repliée » resterait vert le jour où la ligne cesse de se
//  replier, et ne prouverait plus rien.
const ecranBrut = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); if (!f || !f.term) return '';
  const b = f.term.buffer.active, out = [];
  for (let i = 0; i < b.length; i++) { const l = b.getLine(i); if (l) out.push(l.translateToString(true)); }
  return out.join('\n');
});
//  L'ÉCRAN VISIBLE SEUL, sans l'historique. « clear » efface l'écran mais ne
//  jette pas les lignes derrière : les chercher dans le tampon entier ferait
//  échouer le contrôle de l'effacement pour une raison qui n'a rien à voir.
const vue = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); const b = f.term.buffer.active, out = [];
  for (let i = 0; i < f.term.rows; i++) {
    const l = b.getLine(b.viewportY + i); out.push(l ? l.translateToString(true) : '');
  }
  return out.join('\n');
});
//  ═══ insertText, PAS type() — ET CE N'EST PAS UN DÉTAIL DE CONFORT ═══
//  MESURÉ : « page.keyboard.type("echo APRES=$(tput cols)") » arrivait dans
//  le shell sous la forme « echo APRES=($tput cols) ». Les caractères qui
//  demandent Maj ($ ( _ …) se réordonnent en chemin — une course entre les
//  événements clavier de Playwright et la zone de saisie de xterm.js, du
//  côté du BANC, pas du produit. Quatre contrôles étaient rouges à cause de
//  ça, dont trois qui n'avaient rien à voir avec la frappe.
//  insertText pose le texte d'un coup, sans passer par les touches — et un
//  contrôle plus bas garde exprès la vraie frappe touche par touche, pour
//  que ce chemin-là reste éprouvé lui aussi.
const tape = async (t) => { await page.keyboard.insertText(t); await page.keyboard.press('Enter');
                            await page.waitForTimeout(1100); };

const adresse = `http://127.0.0.1:${port}/index.html?port=${port}&jeton=${jeton}`;
await page.goto(adresse);
await page.waitForTimeout(2500);

dit(await page.evaluate(() => !!document.querySelector('.xterm-rows')),
    'xterm.js a ouvert une vraie grille de caractères dans le volet');

const t0 = await ecran();
dit(/LexOS/.test(t0), 'la bannière est écrite DANS le terminal (séquences ANSI, plus de HTML)');
//  L'invite de bash, avec le VRAI nom d'utilisateur et le VRAI dossier : la
//  page n'en dessine plus aucune, et n'a plus à demander $HOME au démarrage.
dit(/[$#]\s*$/m.test(t0.replace(/\s+$/, '') + '\n'), 'bash a écrit SA propre invite — le shell est vivant');

await page.click('.fen.actif .xterm-screen');
//  ═══ LA VRAIE FRAPPE, TOUCHE PAR TOUCHE ═══
//  Ce contrôle-ci n'utilise PAS insertText : il tape pour de vrai, comme un
//  humain, pour éprouver le chemin clavier complet (keydown → xterm.js →
//  onData → /api/saisie → le pty). Sans lettres accentuées ni caractères qui
//  demandent Maj, pour ne pas retomber sur la course décrite plus haut.
await page.keyboard.type('echo bonjour depuis le navigateur');
await page.keyboard.press('Enter');
await page.waitForTimeout(1200);
const t1 = await ecran();
//  Deux fois : l'écho de la frappe par le pty, puis la sortie de la commande.
dit((t1.match(/bonjour depuis le navigateur/g) || []).length >= 2,
    'une frappe RÉELLE touche par touche part au shell et sa sortie revient');

//  ═══ CE QU'ON TAPE VITE ARRIVE DANS L'ORDRE, ET RIEN NE SE PERD ═══
//  Ces deux contrôles viennent d'un vrai défaut, mesuré ici même : en
//  tapant « echo tres tot » dès l'ouverture, le shell recevait « trse tot ».
//  Deux causes distinctes, chacune suffisante :
//    · ce qui était tapé AVANT que le flux réponde partait vers une session
//      qui n'existait pas encore → 404 → caractères perdus EN SILENCE ;
//    · chaque touche partait dans SA propre requête, sans attendre la
//      précédente → deux requêtes en vol → le serveur les traite dans
//      l'ordre d'arrivée, pas dans celui de la frappe.
//  Mesuré : sans la file d'attente sérialisée, SIX rafales sur six
//  arrivaient mélangées. C'est le genre de panne qu'on met sur le compte du
//  clavier, et qu'on ne trouve jamais.
{
  const RAFALE = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwx';
  await page.evaluate((t) => {
    const f = window.LexOS.fenetreActive();
    f.envoyer('echo ');
    for (const c of t) f.envoyer(c);   // une frappe = un appel, sans attendre
    f.envoyer('\r');
  }, RAFALE);
  await page.waitForTimeout(2000);
  const apres = await ecran();
  dit((apres.match(new RegExp(RAFALE, 'g')) || []).length >= 2,
      'soixante frappes rapides arrivent au shell DANS L\'ORDRE (rien de mélangé)');

  //  ═══ LA MÊME RAFALE, MAIS SUR UNE LIGNE QUI SE REPLIE ═══
  //  C'est la géométrie EXACTE du coureur GitHub : une invite longue
  //  (« runner@fv-az…:~$ ») dans une grille étroite. La ligne tapée dépasse
  //  la largeur et xterm.js la range sur deux lignes de tampon.
  //  Sans le recollement des lignes repliées (voir ecran(), plus haut), ce
  //  contrôle-ci est ROUGE — vérifié en le rejouant sans : rafale trouvée
  //  UNE fois au lieu de deux. Il garde donc la lecture honnête, et il
  //  continue de mesurer l'ORDRE des frappes, pas la largeur de la fenêtre.
  await page.setViewportSize({width: 470, height: 600});
  await page.waitForTimeout(1400);
  const etroit = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
  await page.evaluate((t) => {
    const f = window.LexOS.fenetreActive();
    f.envoyer('echo ');
    for (const c of t) f.envoyer(c);
    f.envoyer('\r');
  }, RAFALE);
  await page.waitForTimeout(2000);
  const cpt = (t) => (t.match(new RegExp(RAFALE, 'g')) || []).length;
  const nRec = cpt(await ecran()), nBrut = cpt(await ecranBrut());
  //  DEUX EXIGENCES, ET LA SECONDE EST CE QUI DONNE DES DENTS AU CONTRÔLE :
  //   · recollée ≥ 2  → la rafale est bien arrivée dans l'ordre ;
  //   · brute    < 2  → la ligne s'est VRAIMENT repliée, donc la lecture
  //                     naïve (celle du coureur, avant ce correctif) aurait
  //                     échoué ici. Si la géométrie cessait de replier, ce
  //                     contrôle deviendrait rouge au lieu de devenir muet.
  dit(nRec >= 2 && nBrut < 2,
      'et sur une ligne qui SE REPLIE (' + etroit + ' colonnes) : toujours dans l\'ordre '
      + '(lue brute ' + nBrut + ', recollée ' + nRec + ')');
  await page.setViewportSize({width: 1200, height: 760});
  await page.waitForTimeout(1400);
}

await tape("printf 'ACCENTS: éàüç 🙂\\n'");
dit(/ACCENTS: éàüç/.test(await ecran()),
    'accents et emoji traversent le flux base64 et s\'affichent intacts');

//  ═══ LA PREUVE QU'IL S'AGIT D'UNE GRILLE, PAS D'UN JOURNAL ═══
//  Effacer l'écran et placer le curseur en (10,20) : deux ordres que
//  l'ancienne page RETIRAIT en silence, faute de savoir quoi en faire.
await tape('clear; printf "\\033[2J\\033[H\\033[10;20HPLACE_EN_10_20"');
const t2 = await vue();
const ligne10 = t2.split('\n')[9] || '';
dit(/PLACE_EN_10_20/.test(t2) && !/bonjour depuis/.test(t2) && !/ACCENTS/.test(t2),
    'l\'écran s\'efface pour de vrai : une grille, pas un journal qui défile');
//  La colonne exacte, pas seulement « le texte est là » : c'est le
//  déplacement du curseur que l'ancienne page retirait en silence.
dit(ligne10.indexOf('PLACE_EN_10_20') === 19,
    'le curseur se place à la colonne demandée (ligne 10, colonne 20)');

//  ═══ LA TAILLE : ce que la grille montre et ce que le shell croit ═══
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
const c1 = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
const l1 = await page.evaluate(() => window.LexOS.fenetreActive().term.rows);
await tape('echo TAILLE=$(tput cols)x$(tput lines)');
const vu1 = ((await ecran()).match(/TAILLE=\d+x\d+/g) || []).pop();
dit(vu1 === 'TAILLE=' + c1 + 'x' + l1,
    'le shell voit EXACTEMENT la grille affichée (' + vu1 + ')');

await page.setViewportSize({width: 780, height: 600});
await page.waitForTimeout(1200);
const c2 = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
await tape('echo APRES=$(tput cols)');
const vu2 = ((await ecran()).match(/APRES=\d+/g) || []).pop();
dit(c2 !== c1 && vu2 === 'APRES=' + c2,
    'redimensionner la fenêtre change ce que le shell voit (' + c1 + ' → ' + c2 + ')');

//  ═══ DEUX VOLETS, DEUX SHELLS — validation n° 10 ═══
await page.click('.fen.actif [data-a="droite"]');
await page.waitForTimeout(2500);
dit(await page.evaluate(() => document.querySelectorAll('.xterm-rows').length) === 2,
    'diviser ouvre un SECOND terminal');
const pids = await page.evaluate(async () => {
  const f = [...document.querySelectorAll('.fen')];
  return f.length;
});
await page.click('.fen:not(.actif) .xterm-screen');
await page.waitForTimeout(300);
await tape('echo VOLET=$$');
const droite = await ecran();
await page.click('.fen:not(.actif) .xterm-screen');
await page.waitForTimeout(300);
await tape('echo VOLET=$$');
const gauche = await ecran();
const pd = (droite.match(/VOLET=(\d+)/) || [])[1];
const pg = (gauche.match(/VOLET=(\d+)/) || [])[1];
dit(pids === 2 && pd && pg && pd !== pg,
    'chaque volet a SON shell, avec son propre pid (' + pg + ' ≠ ' + pd + ')');

dit(ennuis.length === 0,
    'aucune erreur ni requête échouée dans la page' + (ennuis.length ? ' — ' + ennuis.slice(0, 3).join(' | ') : ''));

//  ═══ TAPER TOUT DE SUITE, SUR UNE FENÊTRE NEUVE ═══
//  Le geste le plus banal qui soit : Super+T, et on tape. Une page fraîche,
//  et on frappe dès que le terminal existe — sans laisser le flux s'établir.
//  Répété plusieurs fois, parce que c'est une COURSE : une seule tentative
//  peut passer par chance, et un banc qui passe par chance est pire que pas
//  de banc (il apprend à ignorer les rouges).
{
  let bons = 0;
  const N = 4;
  for (let i = 0; i < N; i++) {
    const neuve = await nav.newPage({viewport: {width: 1000, height: 600}});
    await neuve.goto(adresse);
    await neuve.waitForFunction(() =>
      window.LexOS && window.LexOS.fenetreActive() && window.LexOS.fenetreActive().term);
    await neuve.evaluate(() => window.LexOS.fenetreActive().term.focus());
    await neuve.keyboard.type('echo tres tot');
    await neuve.keyboard.press('Enter');
    await neuve.waitForTimeout(2500);
    const t = await neuve.evaluate(() => {
      const b = window.LexOS.fenetreActive().term.buffer.active, o = [];
      for (let j = 0; j < b.length; j++) { const l = b.getLine(j); if (l) o.push(l.translateToString(true)); }
      return o.join('\n');
    });
    if ((t.match(/tres tot/g) || []).length >= 2) bons++;
    await neuve.close();
  }
  dit(bons === N,
      'ce qu\'on tape AVANT que le shell soit prêt n\'est pas perdu (' + bons + '/' + N + ')');
}

//  ═══ HUIT VOLETS, ET LE TERMINAL RÉPOND TOUJOURS ═══
//  Un navigateur n'accorde que SIX connexions simultanées par origine en
//  HTTP/1.1. Tant que chaque volet tenait SON flux ouvert, le sixième
//  épuisait le quota et TOUT se figeait — plus une frappe, plus un
//  redimensionnement, et rien à l'écran pour le dire. MESURÉ avant le
//  correctif, dans ce même Chromium : 1 à 5 volets → /api/saisie en 3 à
//  6 ms ; 6 volets et au-delà → aucune réponse en 5 secondes.
//  Le pont suit maintenant tous les volets sur UN flux (fens=*), et ouvrir
//  un volet est une requête courte. Ce contrôle le vérifie là où ça se
//  joue : dans un vrai navigateur, avec ses vraies limites.
{
  const r = await page.evaluate(async ({jeton, n}) => {
    const lents = [];
    for (let i = 900; i < 900 + n; i++) {
      await fetch('/api/ouvrir', {method:'POST',
        headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
        body: JSON.stringify({fen:String(i), colonnes:80, lignes:24})});
      const t0 = performance.now();
      try {
        const ctl = new AbortController();
        const m = setTimeout(() => ctl.abort(), 4000);
        await fetch('/api/saisie', {method:'POST', signal: ctl.signal,
          headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
          body: JSON.stringify({fen:String(i), texte:''})});
        clearTimeout(m);
      } catch (e) { lents.push(i - 899); }
      const ms = performance.now() - t0;
      if (ms > 2000 && !lents.includes(i - 899)) lents.push(i - 899);
    }
    for (let i = 900; i < 900 + n; i++)
      fetch('/api/fermer', {method:'POST',
        headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
        body: JSON.stringify({fen:String(i)})});
    return lents;
  }, {jeton, n: 8});
  dit(r.length === 0,
      r.length === 0
        ? 'huit volets ouverts : le terminal répond toujours (le 6e ne fige plus rien)'
        : 'le terminal se fige à partir du volet ' + r[0] + ' — le quota de connexions du navigateur est épuisé');
}

//  ═══ LA GRILLE REMPLIT LA FENÊTRE, MÊME QUAND LA MESURE ARRIVE EN RETARD ═══
//  D'OÙ ÇA VIENT : sur le coureur GitHub, ce banc a mesuré « TAILLE=80x24 »
//  dans une fenêtre de 1200×760 — la grille PAR DÉFAUT de xterm.js. Le shell
//  y voyait 80 colonnes et repliait ses lignes au milieu de l'écran, pour
//  toujours : rien ne réajustait après coup.
//  LA CAUSE : xterm.js ne peut pas mesurer la largeur d'un caractère tant que
//  rien n'est dessiné ; fit() ne fait alors RIEN, et ne le dit pas.
//  ON LE REPRODUIT POUR DE VRAI, dans une seconde page : « body{display:none} »
//  posé AVANT que le script ne construise le terminal, puis retiré. Mesuré
//  avant le correctif — grille 80x24, corps 1198x670, proposé 154x36 : la
//  fenêtre était prête et la grille ne bougeait plus.
{
  const deux = await pont();
  const p2 = await nav.newPage({viewport: {width: 1200, height: 760}});
  await p2.addInitScript(() => {
    const poser = () => {
      if (!document.documentElement) { setTimeout(poser, 0); return; }
      if (document.getElementById('cachette')) return;
      const s = document.createElement('style');
      s.id = 'cachette';
      s.textContent = 'body{display:none !important}';
      document.documentElement.appendChild(s);
    };
    poser();
  });
  await p2.goto(`http://127.0.0.1:${deux.port}/index.html?port=${deux.port}&jeton=${deux.jeton}`);
  await p2.waitForTimeout(1500);
  const cachee = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive();
    return f && f.term ? f.term.cols : 0;
  });
  await p2.evaluate(() => { const c = document.getElementById('cachette'); if (c) c.remove(); });
  await p2.waitForTimeout(3000);
  const g = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive();
    let p; try { p = f.ajust.proposeDimensions(); } catch (e) { p = null; }
    return {cols: f.term.cols, rows: f.term.rows, veut: p ? p.cols : 0};
  });
  //  La grille suit ce que la fenêtre permet — et 80 n'est pas une largeur
  //  qu'on choisit, c'est celle qu'on subit quand personne n'a mesuré.
  dit(g.veut > 0 && g.cols === g.veut && g.cols > 80,
      'la grille remplit la fenêtre même si la mesure arrive en retard ('
      + cachee + ' colonnes cachée → ' + g.cols + 'x' + g.rows + ' révélée)');
  //  ET LE SHELL DOIT L'APPRENDRE. Une grille rattrapée dont le pty garde
  //  80 colonnes ne corrige rien : bash replierait toujours au même endroit.
  await p2.click('.fen.actif .xterm-screen');
  //  « stty size » plutôt que « echo …$(tput cols) » : pas une majuscule ni
  //  une parenthèse, donc aucune course entre les touches de Playwright et
  //  la zone de saisie de xterm.js (voir tape(), plus haut). Il rend
  //  « lignes colonnes », c'est-à-dire ce que le PTY croit, pas la page.
  await p2.keyboard.type('stty size');
  await p2.keyboard.press('Enter');
  await p2.waitForTimeout(1800);
  const vuShell = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive(); const b = f.term.buffer.active, out = [];
    for (let i = 0; i < b.length; i++) {
      const l = b.getLine(i); if (!l) continue;
      const t = l.translateToString(true);
      if (l.isWrapped && out.length) out[out.length - 1] += t; else out.push(t);
    }
    return (out.join('\n').match(/^\d+ \d+$/gm) || []).pop();
  });
  dit(vuShell === g.rows + ' ' + g.cols,
      'et le PTY apprend la nouvelle taille (stty size → ' + vuShell + ')');
  await p2.close(); deux.proc.kill();
}

//  ═══ LA TAILLE DU TEXTE : CINQ TOUCHES, ET RIEN NE FUIT VERS LE SHELL ═══
//  CE QUE ÇA FAISAIT, mesuré ici même en écoutant /api/saisie :
//  « Control+Shift+Minus | taille 13,5 → 12,5 | envoyé au shell : ^_(0x1f) ».
//  Le texte rapetissait ET readline recevait son « undo » — une annulation
//  invisible au milieu de la ligne qu'on écrivait.
//  preventDefault() ne suffisait pas : clavier() est en phase de CAPTURE sur
//  « window », donc il passe bien avant, mais il n'empêche que le NAVIGATEUR,
//  et la propagation continue jusqu'à la zone de saisie de xterm.js. Les
//  quatre autres combinaisons s'en sortaient par chance — xterm.js ne connaît
//  aucune séquence pour Ctrl+= , Ctrl+- ni Ctrl+0 ; pour Ctrl+_ , si.
//  ⚠ ET LE TÉMOIN EST OBLIGATOIRE : il serait trivial de faire taire ces
//  touches en faisant taire TOUT. Ctrl+C doit continuer de passer.
{
  const p3 = await nav.newPage({viewport: {width: 1200, height: 760}});
  await p3.goto(adresse);
  await p3.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await p3.evaluate(() => {
    window.__SAISIES = [];
    const vrai = window.fetch;
    window.fetch = function(u, o){
      if(String(u).indexOf("/api/saisie") !== -1 && o && o.body){
        try{
          const t = String(JSON.parse(o.body).texte || "");
          window.__SAISIES.push([...t].map(c => {
            const n = c.charCodeAt(0);
            return n < 32 ? "^" + String.fromCharCode(64 + n) + "(0x" + n.toString(16) + ")" : c;
          }).join(""));
        }catch(e){ window.__SAISIES.push("?"); }
      }
      return vrai.apply(this, arguments);
    };
  });
  await p3.locator('.xterm-helper-textarea').first().focus();
  const fuites = [], bouge = [];
  for (const combo of ['Control+Equal', 'Control+Shift+Equal', 'Control+Minus',
                       'Control+Shift+Minus']) {
    await p3.evaluate(() => { window.__SAISIES = []; });
    const avant = await p3.evaluate(() => window.__banc.TAILLE);
    await p3.keyboard.press(combo);
    await p3.waitForTimeout(250);
    const r = await p3.evaluate(() => ({t: window.__banc.TAILLE, s: window.__SAISIES}));
    if (r.s.length) fuites.push(combo + ' → ' + JSON.stringify(r.s));
    if (r.t !== avant) bouge.push(combo);
  }
  dit(fuites.length === 0,
      'les touches de taille n\'envoient RIEN au shell'
      + (fuites.length ? ' — fuites : ' + fuites.join(' | ') : ''));
  dit(bouge.length === 4,
      'et chacune des quatre change bien la taille (' + bouge.length + '/4)');
  //  LE TÉMOIN.
  await p3.evaluate(() => { window.__SAISIES = []; });
  await p3.keyboard.press('Control+c');
  await p3.waitForTimeout(250);
  const ctrlc = await p3.evaluate(() => window.__SAISIES);
  dit(ctrlc.length === 1 && /0x3/.test(ctrlc[0]),
      'TÉMOIN : Ctrl+C atteint toujours le shell (' + JSON.stringify(ctrlc)
      + ') — on n\'a pas fait taire tout le clavier');
  await p3.close();
}

//  ═══ ET LA TAILLE CHOISIE SURVIT À UNE RELANCE, SUR UN AUTRE PORT ═══
//  LE DÉFAUT, MESURÉ. Le réglage vivait dans le localStorage, cloisonné PAR
//  ORIGINE ; le pont se lie au port 0, donc le système lui donne un port
//  éphémère DIFFÉRENT à chaque lancement (deux tirages mesurés : 42839 puis
//  57411). Taille posée à 18,5, pont relancé → retour à 12,5 px. C'est
//  exactement ce qu'Alex aurait vu en rouvrant sa fenêtre.
//  ⚠ CE CONTRÔLE DOIT DISCRIMINER. Trouver 18,5 des deux côtés ne prouve
//  rien : l'adoption écrit la valeur du pont DANS le localStorage, en miroir.
//  On les met donc en DÉSACCORD — le pont dit 18,5, le navigateur dit 9 — et
//  c'est le pont qui doit gagner.
{
  const trois = await pont();
  dit(trois.port !== port,
      'le pont relancé prend bien un AUTRE port (' + port + ' → ' + trois.port
      + ') — sans quoi ce contrôle ne mesurerait rien');
  const p4 = await nav.newPage({viewport: {width: 1200, height: 760}});
  const adr3 = `http://127.0.0.1:${trois.port}/index.html?port=${trois.port}&jeton=${trois.jeton}`;
  await p4.goto(adr3);
  await p4.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await p4.evaluate(() => window.__banc.poserTaille(18.5, false));
  await p4.waitForTimeout(1500);            // > les 400 ms de regroupement
  await p4.close();

  const quatre = await pont();
  const p5 = await nav.newPage({viewport: {width: 1200, height: 760}});
  //  LE DÉSACCORD, semé avant que la page ne démarre.
  await p5.addInitScript(() => {
    try{ localStorage.setItem('lexos.terminal.taille', '9'); }catch(e){}
  });
  await p5.goto(`http://127.0.0.1:${quatre.port}/index.html?port=${quatre.port}&jeton=${quatre.jeton}`);
  await p5.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await p5.waitForTimeout(900);
  const apres = await p5.evaluate(() => {
    const v = [...window.__banc.FLUX.volets.values()][0];
    return {T: window.__banc.TAILLE, police: v && v.term.options.fontSize};
  });
  dit(apres.T === 18.5 && apres.police === 18.5,
      'la taille survit à la relance sur un autre port, et le PONT a le dernier'
      + ' mot contre un navigateur qui disait 9 (lu : ' + apres.T
      + ', police posée : ' + apres.police + ')');
  await p5.close(); trois.proc.kill(); quatre.proc.kill();
}

//  ═══ LE MENU « PARAMÈTRES DU TERMINAL », CLIQUÉ POUR DE VRAI ═══
//  ALEX : « aimerai on metre en haut de la fenetre capable de changer les
//  couleur du terminal » · « un ti menu » · « parametre du termnal ».
//  Il ne peint RIEN : chaque clic lance « lexos-terminal jour|nuit|auto » par
//  le pont et repeint avec le thème que le pont REND. terminal.env reste la
//  seule source de couleur de tout LexOS.
{
  const pm = await nav.newPage({viewport: {width: 1200, height: 760}});
  await pm.goto(adresse);
  await pm.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pm.waitForTimeout(700);
  const lire = () => pm.evaluate(() => {
    const p = document.getElementById("panneau-reglages");
    const r = document.getElementById("pan-raison");
    const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
    const v = [...window.__banc.FLUX.volets.values()][0];
    return {
      ouvert: !p.hidden,
      aria: document.getElementById("reglages").getAttribute("aria-expanded"),
      coche: [...p.querySelectorAll("[data-mode]")].filter(b => b.getAttribute("aria-checked") === "true").map(b => b.dataset.mode),
      grises: [...p.querySelectorAll("[data-mode]")].filter(b => b.disabled).map(b => b.dataset.mode),
      raison: r.hidden ? "" : r.textContent,
      fond: css("--noir"),
      fondTerm: v && v.term.options.theme && v.term.options.theme.background,
      taille: document.getElementById("pan-taille").textContent,
    };
  });
  const ferme = await lire();
  await pm.click('#reglages');
  const ouvert = await lire();
  dit(ferme.ouvert === false && ferme.aria === "false"
      && ouvert.ouvert === true && ouvert.aria === "true",
      'le menu s\'ouvre au clic et le dit aux lecteurs d\'écran (aria-expanded '
      + ferme.aria + ' → ' + ouvert.aria + ')');

  //  ═══ CE QUE LE CLIC FAIT, ET CE QU'IL DIT QUAND IL NE PEUT PAS ═══
  //  ⚠ CE BANC TOURNE EN ROOT SUR LE COUREUR, et la route refuse en root —
  //  en root le thème changé serait celui de root, donc l'action aurait l'air
  //  d'avoir marché sans rien changer pour Alex. On mesure donc la BRANCHE
  //  qui s'applique, et on DIT laquelle : en root, que le refus du pont est
  //  montré TEL QUEL ; autrement, que la fenêtre repeint vraiment.
  const fondAvant = (await lire()).fond;
  await pm.click('[data-mode="jour"]');
  await pm.waitForTimeout(3000);
  const apres = await lire();
  if (process.geteuid && process.geteuid() === 0) {
    dit(/root/.test(apres.raison) && apres.fond === fondAvant,
        'lancé EN ROOT : le menu montre la raison du pont TELLE QUELLE et ne '
        + 'repeint rien (« ' + apres.raison.slice(0, 80) + ' »)');
  } else {
    dit(apres.coche.join() === "jour" && apres.fond === "#F0EEE6"
        && apres.fondTerm === "#F0EEE6",
        'un clic sur « Jour » lance la commande du système et repeint la page '
        + 'ET le terminal (coché ' + JSON.stringify(apres.coche) + ', fond '
        + apres.fond + ', fond du terminal ' + apres.fondTerm + ')');
  }

  //  La taille, par les boutons du menu — elle ne passe pas par le pont, donc
  //  elle marche dans les deux cas.
  //  ⚠ ON MESURE UN ÉCART, PAS UNE VALEUR. Première écriture de ce point :
  //  « grandi === "14,5 px" », en supposant qu'on partait du défaut. Faux —
  //  le contrôle de persistance, quelques lignes plus haut dans CE banc, a
  //  laissé 18,5 px dans la configuration, et deux clics ont donné 20,5. Le
  //  point rougissait sur du code juste. Un banc ne doit rien supposer de
  //  l'état qu'il trouve : il lit avant, il lit après, il compare.
  const avantT = parseFloat((await lire()).taille.replace(",", "."));
  await pm.click('#pan-plus');
  await pm.click('#pan-plus');
  const grandi = parseFloat((await lire()).taille.replace(",", "."));
  await pm.click('#pan-zero');
  const remis = parseFloat((await lire()).taille.replace(",", "."));
  const defaut = await pm.evaluate(() => window.__banc.TAILLE_DEFAUT);
  dit(grandi === avantT + 2 && remis === defaut,
      'les boutons de taille du menu agrandissent de deux crans et remettent '
      + 'au défaut (' + avantT + ' → ' + grandi + ' → ' + remis
      + ', défaut ' + defaut + ')');

  //  ═══ ÉCHAP DOIT ENCORE MARCHER APRÈS UN CLIC SUR UN MODE ═══
  //  CE QUE ÇA FAISAIT, MESURÉ au clavier : rafraichir() grisait les trois
  //  modes pendant la commande, DONT celui qui avait le focus, et le
  //  navigateur renvoyait le focus à <body>. L'écouteur d'Échap étant posé sur
  //  le PANNEAU, il ne se déclenchait plus : le panneau restait ouvert et plus
  //  aucune touche ne le fermait. Rien ne rendait le focus.
  //  Ce point vient APRÈS le clic sur un mode, exprès — avant, il passait.
  const apresClic = await lire();
  await pm.keyboard.press('Escape');
  await pm.waitForTimeout(300);
  const ferme2 = await lire();
  dit(ferme2.ouvert === false,
      'Échap referme le menu MÊME après un clic sur un mode (focus après le '
      + 'clic : ' + apresClic.focus + ')');
  dit(apresClic.grises.length === 0,
      '…et les modes ne sont pas grisés pendant la commande — griser le bouton '
      + 'qui a le focus l\'arrache (grisés : ' + JSON.stringify(apresClic.grises) + ')');

  //  ═══ AUX BORNES DE LA TAILLE, ON DIT QU'ON Y EST ═══
  //  Les deux boutons étaient grisés EN SILENCE : à 32 px « + » devenait
  //  inerte, sortait de l'ordre de tabulation, et le bloc de raison juste en
  //  dessous restait vide. Mesuré :
  //  {"taille":"32 px","plusOff":true,"raison":"","titreplus":null}.
  //  La consigne du projet est celle que ce même menu applique aux trois
  //  modes ; elle vaut aussi pour ces deux boutons.
  await pm.click('#reglages');
  await pm.evaluate(() => window.__banc.poserTaille(window.__banc.TAILLE_MAX, false));
  await pm.waitForTimeout(300);
  const haut = await pm.evaluate(() => ({
    t: document.getElementById("pan-taille").textContent,
    off: document.getElementById("pan-plus").disabled,
    titre: document.getElementById("pan-plus").title }));
  await pm.evaluate(() => window.__banc.poserTaille(7, false));
  await pm.waitForTimeout(300);
  const bas = await pm.evaluate(() => ({
    t: document.getElementById("pan-taille").textContent,
    off: document.getElementById("pan-moins").disabled,
    titre: document.getElementById("pan-moins").title }));
  dit(haut.off && /maximum/.test(haut.t) && /plus grande/.test(haut.titre)
      && bas.off && /minimum/.test(bas.t) && /plus petite/.test(bas.titre),
      'aux deux bornes, le bouton grisé DIT pourquoi — dans la valeur et dans '
      + 'son infobulle (« ' + haut.t + ' » / « ' + bas.t + ' »)');
  await pm.evaluate(() => window.__banc.poserTaille(window.__banc.TAILLE_DEFAUT, false));
  await pm.close();
}

//  ═══ LE MENU NE RÉPÈTE PAS LE « ✓ » DU SYSTÈME SI RIEN N'A ÉTÉ PEINT ═══
//  TROUVÉ PAR UNE RELECTURE INDÉPENDANTE, puis reproduit ici. poserMode()
//  affichait r.dit SANS regarder si poserTheme() avait peint. Or poserTheme()
//  refuse EN BLOC un thème qui ne porte pas ses cinq clefs — et c'est un cas
//  RÉEL : « page neuve, générateur ancien », ce que dev-sync produit quand il
//  ne pose qu'une moitié du dépôt. La commande rend 0, le panneau cochait
//  « jour » et affichait « ✓ Terminal de jour — fond crème », et la fenêtre
//  restait ENTIÈREMENT NOIRE. Le mot « ✓ » devant une fenêtre qui n'a pas
//  bougé, c'est exactement ce que ce projet interdit.
//
//  ⚠ ON NE PEUT PAS PÉRIMER LE FICHIER À LA MAIN POUR CE CONTRÔLE : le vrai
//  lexos-terminal RÉGÉNÈRE terminal.env en entier, donc le clic effacerait la
//  péremption qu'on vient de poser. Mesuré — la première version de cette
//  sonde a fait exactement ça et a conclu à tort. On met donc un FAUX
//  lexos-terminal en tête du PATH : il réussit, imprime sa confirmation, et
//  écrit un terminal.env incomplet.
{
  const faux = process.env.LEXOS_BANC + '/faux-bin';
  fsb.mkdirSync(faux, {recursive: true});
  fsb.writeFileSync(faux + '/lexos-terminal',
    '#!/usr/bin/env bash\n'
    + 'CONF="${XDG_CONFIG_HOME:-$HOME/.config}/lexos"\n'
    + 'mkdir -p "$CONF"\n'
    + 'cat > "$CONF/terminal.env" <<EOF\n'
    + 'LEXOS_TERM_EFFECTIF=jour\n'
    + 'LEXOS_TERM_BG=#F7F5F0\n'
    + 'LEXOS_TERM_FG=#0B6B3A\n'
    + 'LEXOS_TERM_CURSEUR=#A84007\n'
    + 'EOF\n'
    + 'printf jour > "$CONF/terminal-mode"\n'
    + 'echo "OK Terminal de jour - fond creme."\n', {mode: 0o755});
  //  ⚠ CELUI-CI AUSSI PREND UN FOYER À LUI, et c'est le plus urgent des trois.
  //  MESURÉ, en non-root (en root la commande est refusée et la branche root
  //  masquait tout) : le faux lexos-terminal posé en tête du PATH écrit
  //  « ${XDG_CONFIG_HOME:-$HOME/.config}/lexos/terminal.env » avec QUATRE
  //  clefs. Ce pont n'épinglait rien, donc ces quatre clefs atterrissaient
  //  dans le VRAI thème de celui qui lance le banc. Thème semé à 8 lignes
  //  avec un marqueur à moi → après le banc : 4 lignes, marqueur disparu,
  //  LEXOS_TERM_TEXTE et LEXOS_TERM_PALETTE perdues. Autrement dit : lancer
  //  ce banc cassait la palette du terminal de son auteur.
  const foyerFaux = process.env.LEXOS_BANC + '/faux-theme';
  fsb.mkdirSync(foyerFaux + '/.config/lexos', {recursive: true});
  const py2 = py;   // même pont, PATH différent
  const pr = spawn('python3', ['-c', py2], {env: {...process.env,
    HOME: foyerFaux, XDG_CONFIG_HOME: foyerFaux + '/.config',
    LEXOS_TERMINAL_PRO_WEB: WEB, PATH: faux + ':' + process.env.LEXOS_BIN + ':' + process.env.PATH}});
  const [, p2, j2] = await new Promise(r => pr.stdout.on('data', d => {
    const m = String(d).match(/PRET (\d+) (\S+)/); if (m) r(m);
  }));
  const pf = await nav.newPage({viewport: {width: 1200, height: 760}});
  await pf.goto(`http://127.0.0.1:${p2}/index.html?port=${p2}&jeton=${j2}`);
  await pf.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pf.click('#reglages');
  //  ⚠ ON COMPARE AVANT/APRÈS, PAS À UNE CONSTANTE. Première écriture de ce
  //  point : « e.noir === "#000000" ». Faux — la page a déjà appliqué, AU
  //  DÉMARRAGE, le thème complet que les sections précédentes de ce banc ont
  //  laissé dans la configuration, et il peut être de JOUR. Le point rougissait
  //  sur du code juste (fond #F7F5F0). Ce qu'on veut dire est « ce clic-ci n'a
  //  rien repeint », donc on lit le fond AVANT.
  const noirAvant = await pf.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--noir").trim());
  await pf.click('[data-mode="jour"]');
  await pf.waitForTimeout(3000);
  const e = await pf.evaluate(() => ({
    raison: document.getElementById("pan-raison").textContent,
    noir: getComputedStyle(document.documentElement).getPropertyValue("--noir").trim() }));
  dit(/PAS été repeinte/.test(e.raison) && e.noir === noirAvant,
      'un thème incomplet : le menu relaie le « ✓ » du système MAIS dit que la '
      + 'fenêtre n\'a pas été repeinte (fond inchangé : ' + noirAvant + ' → '
      + e.noir + ')');
  dit(/LEXOS_TERM_TEXTE/.test(e.raison),
      '…et il NOMME ce qui manque, pour qu\'on sache quoi régénérer');
  await pf.close(); pr.kill();
}

//  ═══ EN DÉMONSTRATION, LE MENU EST GRISÉ *AVEC SA RAISON* ═══
//  La consigne du projet l'exige : toute action indisponible est désactivée
//  avec une raison explicite — jamais grisée en silence, jamais présentée
//  comme faite. Sans pont, « lexos terminal » ne peut pas être lancée.
//  ⚠ ET LA TAILLE DOIT RESTER UTILISABLE : elle est locale, elle ne passe pas
//  par le pont. Tout griser serait plus simple et faux.
{
  const pd = await nav.newPage({viewport: {width: 1200, height: 760}});
  //  La page SANS ?port= ni ?jeton= : c'est exactement le mode démonstration.
  await pd.goto(`http://127.0.0.1:${port}/index.html`);
  await pd.waitForTimeout(1500);
  await pd.click('#reglages');
  const e = await pd.evaluate(() => {
    const p = document.getElementById("panneau-reglages");
    const r = document.getElementById("pan-raison");
    return {grises: [...p.querySelectorAll("[data-mode]")].filter(b => b.disabled).map(b => b.dataset.mode),
            raison: r.hidden ? "" : r.textContent};
  });
  dit(e.grises.length === 3 && /Indisponible/.test(e.raison)
      && /lexos terminal/.test(e.raison),
      'en démonstration les trois modes sont grisés AVEC leur raison ('
      + JSON.stringify(e.grises) + ' — « ' + e.raison.slice(0, 70) + '… »)');
  //  Même règle : un ÉCART, pas une valeur — le localStorage de cette origine
  //  garde ce que les pages précédentes de ce banc y ont laissé.
  const dAvant = await pd.evaluate(() => window.__banc.TAILLE);
  await pd.click('#pan-plus');
  const dApres = await pd.evaluate(() => window.__banc.TAILLE);
  dit(dApres === dAvant + 1,
      '…et la taille du texte reste utilisable sans pont — on n\'a pas tout '
      + 'grisé (' + dAvant + ' → ' + dApres + ')');
  await pd.close();
}

//  ═══ LE TERMINAL NE DÉPEND D'AUCUNE LECTURE DE CONFIGURATION ═══
//  LE DÉFAUT, MESURÉ dans ce navigateur-ci avant d'être corrigé : le
//  démarrage attendait /api/theme et /api/reglages, sans aucun délai, avant
//  de construire le premier volet. Une lecture qui ne se règle JAMAIS —
//  ni succès ni échec — laissait Promise.allSettled en suspens, donc
//  Terminal.init() n'était jamais appelé : ZÉRO volet .xterm, pendant que
//  l'indicateur affirmait « vrai terminal — pty sur 127.0.0.1:36585 ».
//
//  ET ON NE SIMULE PAS LE BLOCAGE. Un faux fetch prouverait que le faux
//  fetch bloque. On le provoque DANS LE PONT RÉEL : « terminal.env » posé en
//  TUBE NOMMÉ sans écrivain. os.path.exists() dit oui, open() ne rend jamais
//  la main, /api/theme ne répond pas. C'est le vrai code, vraiment bloqué.
{
  const foyer = process.env.LEXOS_BANC + '/bloque';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  {
    //  Un thème COMPLET sur le disque : la guérison, plus bas, doit pouvoir
    //  repeindre pour de vrai quand le pont redevient sain.
    fsb.writeFileSync(foyer + '/.config/lexos/terminal.env', THEME_ENTIER);
    fsb.writeFileSync(foyer + '/.config/lexos/terminal-pro.json', '{"taille": 10.0}\n');
    const b = await pontSourd(foyer);
    const pb = await nav.newPage({viewport: {width: 1100, height: 700}});
    const t0 = Date.now();
    await pb.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`,
                  {waitUntil: 'domcontentloaded'});
    let ouvert = true;
    //  HUIT SECONDES : largement au-delà des 2 s du délai et des 400 ms de la
    //  veille. Si rien ne vient en huit secondes, rien ne viendra jamais.
    try { await pb.waitForSelector('.xterm', {timeout: 8000}); }
    catch (e) { ouvert = false; }
    const dt = Date.now() - t0;
    dit(ouvert, 'une lecture de configuration qui ne répond JAMAIS n\'empêche '
              + 'plus le terminal d\'exister (premier volet après ' + dt
              + ' ms, lecture du thème arrêtée DANS le pont — le cas du '
              + 'montage mort, que le garde du fichier ordinaire ne couvre pas)');
    //  ET PAS DEUX FOIS. Les deux chemins qui mènent à Terminal.init() — les
    //  lectures qui se règlent, et la veille — peuvent arriver tous les deux.
    //  ⚠ CE POINT EST UN INVARIANT, PAS LE FILET DE LA DOUBLE INITIALISATION.
    //  Mutation jouée (garde du coup unique retirée) : ce point n'a pas rougi,
    //  il n'a pas été ATTEINT — le banc meurt avant, ailleurs. La double
    //  initialisation est donc bien attrapée, mais par la mort du banc, pas
    //  par cette ligne. Je l'écris plutôt que de compter un vert que je n'ai
    //  pas mesuré.
    //  On regarde APRÈS la nouvelle tentative (4 s) pour que le second chemin
    //  ait eu toutes ses chances de construire un volet de trop.
    await pb.waitForTimeout(6000);
    const volets = await pb.evaluate(() => document.querySelectorAll('.xterm').length);
    dit(volets === 1, 'et il n\'en construit qu\'UN : les deux chemins vers '
                    + 'Terminal.init() ne se doublent pas (volets : ' + volets + ')');
    //  ET IL DIT POURQUOI. Sans ça Alex voit un terminal aux couleurs livrées
    //  sans cause visible — le symptôme qui a lancé ce lot, sans son pourquoi.
    //  ⚠ ON NE CLIQUE PAS. Ma première version de ce point ouvrait le menu
    //  AVANT de lire le message — elle mesurait donc un texte que personne ne
    //  voit. Mesuré sur la page telle quelle : panneau « caché », raison
    //  dedans, et « la raison est-elle dans le texte VISIBLE de la page ?
    //  NON ». Le point passait au vert sur une fenêtre muette. On lit donc ce
    //  qui est RÉELLEMENT à l'écran, et seulement ensuite le détail du menu.
    const vu = await pb.evaluate(() => ({
      barre: ((document.getElementById('backend-ind') || {}).textContent || '').trim(),
      classe: ((document.getElementById('backend-ind') || {}).className || ''),
      ecran: (document.body.innerText || '').replace(/\s+/g, ' '),
    }));
    dit(/thème/.test(vu.barre) && /pas été lu/.test(vu.barre)
        && vu.classe === 'partiel' && /thème/.test(vu.ecran),
        'et la BARRE D\'ÉTAT le dit sans qu\'on ouvre quoi que ce soit — '
        + 'c\'est le seul endroit visible où cette page annonce son état '
        + '(« ' + vu.barre + " », classe " + vu.classe + ')');
    //  Et le détail complet, lui, est bien dans le menu — avec l'accord et
    //  SANS inventer : la taille avait été lue, il ne doit pas la dire perdue.
    await pb.click('#reglages');
    await pb.waitForTimeout(300);
    const raison = await pb.evaluate(() =>
      ((document.getElementById('pan-raison') || {}).textContent || '').replace(/\s+/g, ' ').trim());
    dit(/le thème n'a pas pu être lu/.test(raison)
        && !/taille de texte livrée/.test(raison),
        '…et le menu porte le détail, au singulier et sans rien inventer : la '
        + 'taille, elle, avait bien été lue (« ' + raison.slice(0, 90) + '… »)');
    //  ═══ ET QUAND ÇA RENTRE DANS L'ORDRE, LA PAGE CESSE DE L'ANNONCER ═══
    //  LE DÉFAUT, MESURÉ : le message du démarrage n'avait AUCUN chemin de
    //  retrait. Un thème qui arrivait par la relecture laissait la barre dire
    //  « le thème n'a pas été lu » et le menu annoncer « la fenêtre garde la
    //  palette livrée » — longtemps après qu'elle avait été repeinte. Le
    //  mensonge inverse de celui qu'on venait de corriger.
    //  On remplace le tube par un VRAI thème et on déclenche la relecture
    //  comme le fait un retour de focus ; la barre doit redire la vérité.
    b.guerir();
    await pb.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await pb.waitForTimeout(1200);
    const gueri = await pb.evaluate(() => ({
      barre: ((document.getElementById('backend-ind') || {}).textContent || '').trim(),
      classe: ((document.getElementById('backend-ind') || {}).className || ''),
      raison: ((document.getElementById('pan-raison') || {}).textContent || '').trim(),
    }));
    dit(gueri.classe === 'branche' && !/pas été lu/.test(gueri.barre)
        && !/palette livrée/.test(gueri.raison),
        '…et l\'avertissement PART quand la configuration finit par arriver : '
        + 'la barre et le menu cessent tous les deux de dire le contraire '
        + '(« ' + gueri.barre + ' », classe ' + gueri.classe + ')');
    await pb.close(); b.proc.kill();
  }
}

//  ═══ ET LA TAILLE N'EST PAS PERDUE QUAND LA FENÊTRE SE FERME ═══
//  LE DÉFAUT, MESURÉ : la taille partait au pont 400 ms après le geste, pour
//  ne pas écrire le fichier à chaque cran de molette. Fenêtre fermée dans ces
//  400 ms → AUCUN fichier, et le miroir localStorage ne rattrape rien (le
//  pont change de port, donc d'origine, à chaque lancement). Alex grossit le
//  texte, ferme, relance, et le texte est redevenu petit.
//
//  TROIS POINTS, UN PAR MÉCANIQUE, pour qu'aucun ne couvre la panne d'un
//  autre : le bord montant, le vidage à la fermeture, et la fenêtre tuée.
const taillePosee = async (foyer) => {
  try { return JSON.parse(fsb.readFileSync(foyer + '/.config/lexos/terminal-pro.json', 'utf8')).taille; }
  catch (e) { return null; }
};

{
  //  1. BORD MONTANT : un seul changement, fermée 120 ms après.
  const foyer = process.env.LEXOS_BANC + '/bord1';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const b = await pont(foyer);
  const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  //  ⚠ CE POINT SE MESURE AU TEMPS, PAS À LA FERMETURE. Ma première version
  //  fermait la page à 120 ms et vérifiait que le pont avait rangé. MUTATION
  //  JOUÉE (bord montant retiré) : le point restait VERT — parce que le vidage
  //  à la fermeture rangeait la valeur à sa place. Il mesurait « l'une ou
  //  l'autre mécanique », pas celle que son nom annonce. On ne ferme donc
  //  RIEN : la page reste ouverte, et on exige que la valeur soit déjà sur le
  //  disque avant que le minuteur de 400 ms ait pu tirer.
  await pg.evaluate(() => window.__banc.poserTaille(17, false));
  await pg.waitForTimeout(150);              // BIEN EN DEÇÀ des 400 ms
  const tot = await taillePosee(foyer);      // page TOUJOURS OUVERTE
  //  Et le témoin qui donne son sens au point : 600 ms plus tard, le bord
  //  descendant a de toute façon rangé. Sans lui, un pont muet rendrait ce
  //  point rouge pour la mauvaise raison.
  await pg.waitForTimeout(600);
  const tard = await taillePosee(foyer);
  dit(tot === 17 && tard === 17,
      'la taille est sur le disque AVANT les 400 ms du minuteur, page encore '
      + 'ouverte : c\'est le bord montant qui l\'a envoyée (à 150 ms : ' + tot
      + ', à 750 ms : ' + tard + ')');
  await pg.close();
  b.proc.kill();
}

{
  //  2. VIDAGE À LA FERMETURE : le bord montant a DÉJÀ tiré pour 17, puis on
  //  passe à 20 — seul le minuteur porte cette seconde valeur. Si le vidage
  //  n'existe pas, le pont garde 17 et ce point rougit SANS que le point du
  //  bord montant bouge. Chacun mesure sa propre mécanique.
  const foyer = process.env.LEXOS_BANC + '/bord2';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const b = await pont(foyer);
  const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  await pg.evaluate(() => window.__banc.poserTaille(17, false));
  await pg.waitForTimeout(300);              // le bord montant est revenu
  const inter = await taillePosee(foyer);
  await pg.evaluate(() => window.__banc.poserTaille(20, false));
  await pg.waitForTimeout(120);              // toujours en deçà des 400 ms
  await pg.close();
  await new Promise(r => setTimeout(r, 900));
  const t = await taillePosee(foyer);
  dit(inter === 17 && t === 20,
      'et la DERNIÈRE valeur du geste n\'est pas perdue non plus : le minuteur '
      + 'est vidé quand la page s\'en va (' + inter + ' → ' + t + ', 20 attendu)');
  b.proc.kill();
}

{
  //  3. LA FENÊTRE TUÉE : aucun écouteur ne tire. Le vidage ne peut RIEN ici —
  //  mesuré : avec le seul vidage, ce cas perdait encore tout. C'est le bord
  //  montant qui sauve, et ce qu'on exige est honnête : pas forcément la
  //  dernière valeur, mais PAS le défaut. Le texte reste gros.
  const foyer = process.env.LEXOS_BANC + '/tue';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const b = await pont(foyer);
  const nav2 = await chromium.launch({executablePath: process.env.LEXOS_CHROME,
                                      args: ['--no-sandbox']});
  const pg = await nav2.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  const defaut = await pg.evaluate(() => window.__banc.TAILLE_DEFAUT);
  await pg.evaluate(() => window.__banc.poserTaille(21, false));
  await pg.waitForTimeout(120);
  await nav2.close();                        // la fenêtre entière disparaît
  await new Promise(r => setTimeout(r, 900));
  const t = await taillePosee(foyer);
  dit(t !== null && t !== defaut,
      'fenêtre entière TUÉE 120 ms après le geste : le pont a tout de même une '
      + 'taille, et ce n\'est pas le défaut (lu : ' + t + ', défaut ' + defaut + ')');
  b.proc.kill();
}

//  ═══ LA REPRISE DE CONFIGURATION NE REPREND PAS LE GESTE D'ALEX ═══
//  CE POINT A D'ABORD ÉTÉ UN FAUX VERT, ET LA MUTATION L'A DIT. Je l'avais
//  écrit sur une LECTURE du code — adopterReglages() pose une taille ABSOLUE,
//  donc la reprise à 4 s doit bien rabattre celle d'Alex — sans reproduire le
//  scénario. Garde retirée : le point restait VERT. Raison, et elle est dans
//  mon propre correctif : le bord montant pousse les 20 px d'Alex au pont dans
//  la milliseconde, donc à la reprise le pont dit DÉJÀ 20 et il n'y a rien à
//  rabattre.
//
//  LE DÉFAUT N'EXISTE QUE SI L'ÉCRITURE DU PONT ÉCHOUE — alors le pont garde
//  son ancienne valeur et la reprise la rabat. Construit, et mesuré dans les
//  deux sens, dossier de configuration en LECTURE SEULE :
//      sans la garde : écran 20 → rabattu à 10, le fichier dit toujours 10
//      avec la garde : écran 20, et il y reste
//  Un point écrit sur une déduction mesure la déduction. Celui-ci mesure.
{
  const foyer = process.env.LEXOS_BANC + '/rabat';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const conf = foyer + '/.config/lexos';
  //  Le tube nommé sert à déclencher le chemin du délai, donc la reprise.
  spawnSync('mkfifo', [conf + '/terminal.env']);
  fsb.writeFileSync(conf + '/terminal-pro.json', '{"taille": 10.0}\n');
  fsb.chmodSync(conf, 0o500);                 // lisible, PAS inscriptible
  //  ⚠ ROOT PASSE OUTRE LES PERMISSIONS, et on le VÉRIFIE au lieu de le
  //  supposer : mon conteneur est root, le coureur ne l'est pas, et un banc
  //  qui se croit vert là où la permission ne mord pas ne vaut rien.
  let inscriptible = true;
  try { fsb.writeFileSync(conf + '/.essai', 'x'); fsb.unlinkSync(conf + '/.essai'); }
  catch (e) { inscriptible = false; }
  if (inscriptible) {
    dit(false, 'lancé EN ROOT : le dossier reste inscriptible malgré le chmod, '
             + 'donc le seul scénario où la reprise peut rabattre la taille '
             + 'n\'a PAS été éprouvé ici — le coureur, lui, n\'est pas root');
  } else {
    const b = await pont(foyer);
    const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
    await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
    await pg.waitForSelector('.xterm', {timeout: 12000});
    const adoptee = await pg.evaluate(() => window.__banc.TAILLE);
    //  ALEX AGIT DANS LA FENÊTRE DE REPRISE (armée à +4 s de l'ouverture).
    await pg.evaluate(() => window.__banc.poserTaille(20, false));
    await pg.waitForTimeout(6500);
    const apres = await pg.evaluate(() => window.__banc.TAILLE);
    const range = (() => { try {
      return JSON.parse(fsb.readFileSync(conf + '/terminal-pro.json', 'utf8')).taille;
    } catch (e) { return null; } })();
    dit(adoptee === 10 && range === 10 && apres === 20,
        'la reprise de configuration ne RABAT PAS la taille qu\'Alex vient de '
        + 'choisir, même quand l\'écriture a échoué et que le pont en garde une '
        + 'autre (adoptée ' + adoptee + ' → geste 20 → après la reprise '
        + apres + ', le pont dit toujours ' + range + ')');
    await pg.close(); b.proc.kill();
  }
  //  ON REND LE DOSSIER INSCRIPTIBLE : sans ça le nettoyage du banc ne peut
  //  pas l'effacer, et il laisse deux « rm: Permission denied » sur la sortie
  //  d'erreur plus un dossier derrière lui. Un banc range ce qu'il a posé.
  try { fsb.chmodSync(conf, 0o700); } catch (e) {}
}

//  ═══ ET DANS L'ORDONNANCEMENT DU PRODUIT, PAS CELUI D'UN PONT IMMORTEL ═══
//  C'EST UNE RELECTURE INDÉPENDANTE QUI A EU RAISON CONTRE MON COMMENTAIRE.
//  J'avais écrit que le vidage à la fermeture « couvre la fermeture PROPRE ;
//  mesuré ». Ce mesuré venait d'un pont qui survit à la page et d'un Chromium
//  autonome — deux choses que le produit n'est pas. Dans la vraie coquille, la
//  requête de vidage part puis le pont cesse d'accepter dans le même souffle :
//  elle n'est jamais acceptée. D'où la grâce bornée dans main(), et d'où ces
//  deux points, dont le second est le TÉMOIN NÉGATIF sans lequel le premier ne
//  prouverait rien.
for (const cas of [{avecGrace: true}, {avecGrace: false}]) {
  const nom = cas.avecGrace ? 'grace' : 'sansgrace';
  const foyer = process.env.LEXOS_BANC + '/' + nom;
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const b = await pontArretable(foyer);
  const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  //  Deux crans : le premier part par le bord montant, le second ne vit que
  //  dans le minuteur — c'est LUI que la fermeture doit sauver.
  await pg.evaluate(() => window.__banc.poserTaille(17, false));
  await pg.waitForTimeout(300);
  await pg.evaluate(() => window.__banc.poserTaille(20, false));
  await pg.waitForTimeout(80);
  //  ⚠ L'ARRÊT EST ARMÉ AVANT LA FERMETURE, pas après. Armé après, le temps
  //  d'aller-retour par l'entrée standard du pont (quelques millisecondes)
  //  suffit à la requête de vidage pour atterrir, et le témoin négatif ne
  //  témoigne plus de rien — MESURÉ : il rendait 20 là où il attendait 17.
  //  Armé avant, l'arrêt tombe à la microseconde près sur la fermeture, ce qui
  //  est l'ordonnancement du produit.
  const arret = b.arreter(cas.avecGrace ? b.grace : 0);
  await pg.close();
  await arret;
  await new Promise(r => setTimeout(r, 300));
  const t = await taillePosee(foyer);
  if (cas.avecGrace) {
    dit(t === 20, 'la dernière valeur atterrit MÊME quand le pont s\'arrête '
                + 'juste après la fenêtre, comme dans le produit — grâce de '
                + b.grace + ' s lue dans le pont (rangé : ' + t + ', 20 attendu)');
  } else {
    dit(t === 17, 'TÉMOIN NÉGATIF : sans cette grâce, la dernière valeur est '
                + 'bien perdue et seul le bord montant subsiste (rangé : ' + t
                + ', 17 attendu) — ce point-ci mesure donc la GRÂCE, pas la '
                + 'mansuétude du navigateur');
  }
  b.proc.kill();
}

//  ═══ UN VOLET DONT LE SHELL EST SORTI SUIT QUAND MÊME LES RÉGLAGES ═══
//  LE DÉFAUT : quand un shell sort, le flux partagé RETIRE son volet de
//  FLUX.volets — et finSession() écrit dans ce même volet « Ctrl+B puis X pour
//  fermer ce volet ». Il RESTE donc à l'écran, exprès. Mais le thème et la
//  taille parcouraient FLUX.volets, c'est-à-dire la liste des ABONNEMENTS AU
//  TRANSPORT : ils sautaient tous les volets terminés. Mesuré avant le
//  correctif — « police après le geste : 12.5 pendant que le menu annonce
//  22 ». Alex grossit le texte, et un volet reste petit.
{
  const foyer = process.env.LEXOS_BANC + '/sorti';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  fsb.writeFileSync(foyer + '/.config/lexos/terminal.env', THEME_ENTIER);
  const b = await pont(foyer);
  const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  //  LE SHELL SORT. On attend que le flux l'ait DÉSABONNÉ : sans ça le point
  //  mesurerait un volet encore abonné, donc rien du tout.
  await pg.evaluate(() => window.__banc.Terminal.active.envoyer('exit\n'));
  let desabonne = true;
  try { await pg.waitForFunction(() => window.__banc.FLUX.volets.size === 0,
                                 {timeout: 10000}); }
  catch (e) { desabonne = false; }
  await pg.waitForTimeout(400);
  const etat = await pg.evaluate(() => {
    const f = window.__banc.Terminal.onglets[0].fenetres()[0];
    return { visible: !!document.querySelector('.xterm'),
             avant: f && f.term && f.term.options.fontSize };
  });
  await pg.evaluate(() => window.__banc.poserTaille(22, false));
  await pg.waitForTimeout(400);
  const apres = await pg.evaluate(() => {
    const f = window.__banc.Terminal.onglets[0].fenetres()[0];
    return { police: f && f.term && f.term.options.fontSize,
             annonce: window.__banc.TAILLE };
  });
  if (!desabonne) {
    dit(false, 'le shell n\'a pas rendu la main en dix secondes — le volet '
             + 'terminé n\'a PAS été éprouvé ici');
  } else {
    dit(etat.visible && apres.police === apres.annonce && apres.police === 22,
        'un volet dont le shell est SORTI reste à l\'écran ET suit la taille : '
        + 'il n\'est plus abonné au flux, mais il est toujours un volet ('
        + etat.avant + ' → ' + apres.police + ' px, le menu annonce '
        + apres.annonce + ')');
  }
  await pg.close(); b.proc.kill();
}

{
  //  4. ET LE MINUTEUR FAIT TOUJOURS SON TRAVAIL. Le bord montant ne doit pas
  //  avoir rouvert la porte qu'il ferme : une roulette lancée produit des
  //  dizaines d'événements, et le fichier ne doit pas être écrit des dizaines
  //  de fois. On COMPTE les requêtes — on ne relit pas le code.
  const foyer = process.env.LEXOS_BANC + '/molette';
  fsb.mkdirSync(foyer + '/.config/lexos', {recursive: true});
  const b = await pont(foyer);
  const pg = await nav.newPage({viewport: {width: 1100, height: 700}});
  await pg.goto(`http://127.0.0.1:${b.port}/index.html?port=${b.port}&jeton=${b.jeton}`);
  await pg.waitForFunction(() => window.__banc && window.__banc.FLUX.volets.size > 0);
  await pg.waitForTimeout(1200);
  let posts = 0;
  pg.on('request', r => { if (r.method() === 'POST' && r.url().endsWith('/api/reglages')) posts++; });
  const depart = await pg.evaluate(() => window.__banc.TAILLE);
  await pg.evaluate(async () => {
    for (let i = 0; i < 30; i++) {
      window.__banc.poserTaille(0.5, true);
      await new Promise(r => requestAnimationFrame(r));
    }
  });
  const arrivee = await pg.evaluate(() => window.__banc.TAILLE);
  await pg.waitForTimeout(1500);
  const t = await taillePosee(foyer);
  dit(posts <= 3 && t === arrivee && arrivee !== depart,
      'trente crans de molette coûtent ' + posts + ' écriture(s), pas trente — '
      + 'et c\'est bien la valeur FINALE qui est rangée (' + depart + ' → '
      + arrivee + ', rangé ' + t + ')');
  await pg.close(); b.proc.kill();
}

await nav.close(); proc.kill();
JS

rendu() {
	local vus=0 ligne verdict message
	while IFS='|' read -r verdict message; do
		case "$verdict" in
			OK)  ok  "$message"; vus=$((vus+1)) ;;
			NON) non "$message"; vus=$((vus+1)) ;;
			*)
				ligne="$verdict$message"
				[ -n "$ligne" ] && printf '     %s\n' "$ligne"
				case "$ligne" in Traceback*|*Error:*|*error*) vus=-1000 ;; esac
				;;
		esac
	done
	[ "$vus" -gt 0 ] || non "aucun verdict rendu (l'essai s'est arrêté)"
}

rendu < <(LEXOS_PW="$PW" LEXOS_CHROME="$CHROME" LEXOS_BACKEND="$BACKEND" LEXOS_WEB="$WEB" \
	LEXOS_BIN="$RACINE/config/includes.chroot/usr/bin" LEXOS_BANC="$ESSAI" \
          timeout 420 "$NODE" "$ESSAI/page.mjs" 2>&1)
#  ⚠ 420 s ET PAS 240. Les points du démarrage bloqué attendent exprès : huit
#  secondes pour établir qu'un volet n'arrive JAMAIS, puis six de plus pour
#  voir si un second se construit en douce. Mesuré après l'ajout : l'essai
#  complet tenait en 80 s sur ce conteneur, contre une limite de 240 qui
#  l'aurait coupé au milieu — et un essai coupé rend « aucun verdict », donc
#  un rouge qui ne dit pas ce qui ne va pas.
rm -rf "$ESSAI"

printf '\n\033[1m═══ TOTAL ═══\033[0m\n'
printf '  réussis : \033[32m%d\033[0m\n  échoués : \033[31m%d\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
