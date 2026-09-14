#!/usr/bin/env bash
# =============================================================================
#  La barre : la flèche des Paramètres rapides, et la cloche qui s'en va
# =============================================================================
#  DEUX DEMANDES D'ALEX, LE MÊME JOUR, SUR LA MÊME BARRE.
#
#  1. « Changer l'image pour une flèche qui pointe vers le bas — pour les
#     paramètres rapides. » Le bouton portait icon-reglages, la roue dentée :
#     exactement la MÊME image que les Paramètres complets, deux boutons
#     voisins dans la barre et rien pour les distinguer. Une flèche vers le
#     bas dit ce que le bouton FAIT — elle tire un volet, comme sur un
#     téléphone.
#
#  2. « Notifications, on peut l'ôter de là, pis juste le garder dans les
#     Paramètres. » La cloche quitte la barre ; la section Notifications des
#     Paramètres, elle, doit rester entière — sinon on ne retire pas un
#     bouton, on supprime une fonction.
#
#  ── CE QUE CE BANC ÉPROUVE, ET POURQUOI CES CONTRÔLES-LÀ ───────────────────
#  Une icône déclarée dans un lanceur mais jamais RENDUE en image donne un
#  bouton vide — c'est très exactement le défaut qui a rongé l'icône du
#  gestionnaire de fichiers pendant des semaines : le fichier existait, mais
#  la chaîne qui mène de la source à l'écran était coupée quelque part. On
#  éprouve donc la CHAÎNE ENTIÈRE : la source existe, le crochet la rend, le
#  lanceur demande ce nom-là.
#
#  Et pour la cloche, on vérifie les DEUX bouts : qu'elle a quitté l'ordre de
#  la barre, et que ce qu'elle servait reste joignable ailleurs.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
LANCEUR="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/panel/launcher-12/lexos-volet-rapides.desktop"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
SVG="$RACINE/branding/icon-volet-bas.svg"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. La flèche existe VRAIMENT, de la source jusqu'au bouton"
# =============================================================================
#  MAILLON 1 : la source. Un lanceur qui demande une icône inexistante
#  n'affiche rien du tout.
if [[ -r "$SVG" ]]; then
	ok "la source du dessin est là (branding/icon-volet-bas.svg)"
else
	non "branding/icon-volet-bas.svg manque — le bouton serait vide"
fi

#  MAILLON 1 bis : c'est un vrai SVG, pas un fichier qui en porte le nom.
if python3 -c "import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1])" "$SVG" 2>/dev/null; then
	ok "et c'est un SVG que le rendu saura lire"
else
	non "le SVG ne se parse pas — rsvg-convert échouerait à la construction"
fi

#  ET IL SE REND POUR DE VRAI. Un SVG peut se parser et ne rien produire
#  (formes hors cadre, syntaxe de tracé fautive). Quand le moteur de l'ISO est
#  disponible, on l'emploie ; sinon on le DIT plutôt que de faire semblant.
if command -v rsvg-convert >/dev/null 2>&1; then
	TMP="$(mktemp -u).png"
	if rsvg-convert -w 64 -h 64 -o "$TMP" "$SVG" 2>/dev/null && [[ -s "$TMP" ]]; then
		ok "rsvg-convert (le moteur de l'ISO) en produit bien une image"
	else
		non "rsvg-convert n'arrive pas à en faire une image"
	fi
	rm -f "$TMP"
else
	printf '  \033[33m•\033[0m rsvg-convert absent ici : le rendu réel n%s'"'"'a pas pu être éprouvé\n' ""
fi

#  MAILLON 2 : le crochet doit RENDRE cette icône. C'est le maillon qui avait
#  sauté pour le gestionnaire de fichiers — le fichier était là, personne ne
#  le regardait.
if grep -qE '^\s+reglages volet-bas |[[:space:]]volet-bas[[:space:]]' "$HOOK"; then
	ok "le crochet 0300 rend « volet-bas » en icône hicolor"
else
	non "« volet-bas » n'est pas dans la liste du crochet 0300 : aucune image ne serait produite"
fi

#  MAILLON 3 : le bouton de la barre demande CE nom-là. Le crochet produit
#  « lexos-<nom> » ; le lanceur doit donc dire « lexos-volet-bas ».
if grep -q '^Icon=lexos-volet-bas$' "$LANCEUR"; then
	ok "le bouton de la barre demande « lexos-volet-bas »"
else
	non "le lanceur demande autre chose : $(grep '^Icon=' "$LANCEUR" 2>/dev/null)"
fi

#  ET IL NE PORTE PLUS LA ROUE DENTÉE. C'est la demande d'Alex, mot pour mot :
#  deux boutons voisins ne doivent plus porter la même image.
if grep -q '^Icon=lexos-reglages$' "$LANCEUR"; then
	non "le bouton porte encore la roue dentée — la même image que les Paramètres"
else
	ok "il ne porte plus la roue dentée des Paramètres complets"
fi

# =============================================================================
titre "2. La cloche a quitté la barre"
# =============================================================================
#  ON LIT LE XML COMME XFCE LE LIT, pas au grep : une propriété commentée
#  ressemble beaucoup à une propriété vivante quand on cherche une chaîne.
ETAT="$(python3 - "$PANEL" <<'PY'
import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
ids, declares = [], []
for p in r.iter("property"):
    nom = p.get("name") or ""
    if nom == "plugin-ids":
        ids = [v.get("value") for v in p]
    if nom.startswith("plugin-"):
        declares.append(nom)
print("IDS:" + ",".join(ids))
print("DECLARES:" + ",".join(declares))
#  TOUT identifiant de l'ordre doit avoir sa déclaration, sinon xfce4-panel
#  affiche un trou à cette place. Retirer un greffon à moitié fait ça.
print("ORPHELINS:" + ",".join(i for i in ids if f"plugin-{i}" not in declares))
PY
)"
lire() { printf '%s' "$ETAT" | grep "^$1:" | cut -d: -f2-; }

IDS="$(lire IDS)"
if grep -q ',15,' < <(printf '%s' ",$IDS,"); then
	non "le greffon 15 (la cloche) est encore dans l'ordre de la barre"
else
	ok "la cloche ne figure plus dans l'ordre de la barre"
fi

if grep -qw 'plugin-15' < <(printf '%s' "$(lire DECLARES)"); then
	non "« plugin-15 » est encore déclaré : le greffon reviendrait"
else
	ok "« plugin-15 » n'est plus déclaré"
fi

#  LE PIÈGE DU RETRAIT À MOITIÉ : un identifiant listé sans déclaration laisse
#  un TROU dans la barre. C'est plus laid que la cloche qu'on enlevait.
ORPH="$(lire ORPHELINS)"
if [[ -z "$ORPH" ]]; then
	ok "chaque greffon de l'ordre est bien déclaré — aucun trou dans la barre"
else
	non "identifiant(s) listés sans déclaration, la barre aurait un trou : $ORPH"
fi

#  ET LA BARRE N'EST PAS VIDE : un banc qui n'a rien lu ne prouve rien.
N="$(printf '%s' "$IDS" | tr ',' '\n' | grep -c .)"
if [[ "$N" -ge 10 ]]; then
	ok "$N greffons dans la barre — le fichier a bien été lu"
else
	non "seulement $N greffons : le XML n'a pas été lu comme prévu"
fi

# =============================================================================
titre "3. …mais les notifications restent joignables dans les Paramètres"
# =============================================================================
#  RETIRER UN BOUTON N'EST PAS SUPPRIMER UNE FONCTION. Alex a dit « juste le
#  garder dans les Paramètres » : si cette section-là disparaissait un jour,
#  le retrait de la cloche deviendrait rétroactivement une perte.
if grep -q '"notifications"' "$APP"; then
	ok "la page des Paramètres porte toujours sa section Notifications"
else
	non "la section Notifications a disparu des Paramètres — la fonction serait perdue"
fi
if grep -q 'Ne pas déranger' "$APP"; then
	ok "« Ne pas déranger » y est toujours, d'un clic"
else
	non "« Ne pas déranger » a disparu"
fi
if grep -q 'xfce4-notifyd-config' "$MOTEUR"; then
	ok "les réglages fins s'ouvrent toujours (xfce4-notifyd-config)"
else
	non "plus rien n'ouvre les réglages fins des notifications"
fi
#  ET LE JOURNAL CONTINUE D'ÊTRE TENU. La cloche était ce qui le donnait à
#  lire ; le garder rempli laisse la porte ouverte à un retour en arrière.
NOTIFYD="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"
if grep -q 'notification-log.*value="true"' "$NOTIFYD"; then
	ok "le journal des notifications reste tenu — rien n'est jeté"
else
	non "le journal n'est plus tenu : remettre la cloche ne ramènerait rien"
fi

# =============================================================================
titre "4. LE SON QUITTE LA BARRE — mais les touches du clavier, JAMAIS"
# =============================================================================
#  ALEX : « le volume, je veux qu'il s'en aille en haut du volet ».
#
#  ═══ CES DEUX CONTRÔLES VONT ENSEMBLE, ET C'EST TOUT LEUR INTÉRÊT ═══
#  « enable-keyboard-shortcuts » du greffon 6 (pulseaudio) est ce qui faisait
#  marcher les touches ↑ ↓ 🔇 du ThinkPad. Un greffon retiré du tableau
#  « plugin-ids » n'est pas caché : il n'est plus CHARGÉ DU TOUT, et les
#  touches deviennent mortes. Un banc qui vérifierait le retrait sans le
#  remplacement VALIDERAIT LA PANNE — il serait vert le jour où les touches
#  cessent de répondre. Les deux sont donc dans le même test.
RACCOURCIS="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

#  Le tableau plugin-ids, sans les commentaires : un « 6 » cité dans une
#  explication ne doit pas passer pour un greffon actif. C'est le piège du
#  contrôle qui lit la prose, et ce fichier-ci en est plein.
IDS="$(python3 - "$PANEL" <<'PYIDS'
import sys, xml.etree.ElementTree as E
a = E.parse(sys.argv[1]).getroot()
for p in a.iter("property"):
    if p.get("name") == "plugin-ids":
        print(" ".join(v.get("value") for v in p.findall("value")))
        break
PYIDS
)"
if [[ -z "$IDS" ]]; then
	non "le tableau plugin-ids n'a pas pu être lu : rien n'est mesuré ici"
elif grep -qw 6 <<< "$IDS"; then
	non "le greffon 6 (pulseaudio) est ENCORE dans la barre : plugin-ids = $IDS"
else
	ok "le greffon 6 (pulseaudio) a quitté la barre — le volume est dans le volet"
fi

#  …ET LES QUATRE TOUCHES SONT REPRISES. Sans elles, le retrait ci-dessus est
#  une régression, pas une amélioration.
MANQUE=""
for T in XF86AudioRaiseVolume XF86AudioLowerVolume XF86AudioMute XF86AudioMicMute; do
	grep -q "name=\"$T\"" "$RACCOURCIS" || MANQUE="$MANQUE $T"
done
if [[ -z "$MANQUE" ]]; then
	ok "les quatre touches de volume sont reprises dans xfce4-keyboard-shortcuts.xml"
else
	non "touches PERDUES avec le greffon 6 :$MANQUE — elles ne répondraient plus"
fi

#  Elles doivent appeler « lexos son », pas du pactl écrit en dur : le moteur
#  du son reste à un seul endroit.
#  « grep -q » S'ARRÊTE AU PREMIER RÉSULTAT et ferme le tuyau : sous
#  « pipefail », le producteur reçoit une erreur d'écriture et TOUT le tuyau
#  échoue — dans un contrôle inversé comme celui-ci, ça donne un FAUX VERT.
#  On met donc le texte en mémoire d'abord, et on l'interroge par here-string.
LIGNES_AUDIO="$(grep -E 'name="XF86Audio' "$RACCOURCIS" || true)"
HORS="$(grep -v 'value="lexos son' <<< "$LIGNES_AUDIO" || true)"
if [[ -n "$HORS" ]]; then
	non "une touche de volume n'appelle pas « lexos son » : $HORS"
else
	ok "…et toutes appellent « lexos son », pas du pactl écrit dans le XML"
fi

#  ═══ ET LES VERBES APPELÉS EXISTENT VRAIMENT DANS lexos-son ═══
#  Premier jet de ce banc : il vérifiait que les touches appellent « lexos
#  son … » et s'arrêtait là. Il était vert avec « lexos son plus », un verbe
#  QUI N'EXISTE PAS — lexos-son ne connaît que « +5 », « muet », « micro ».
#  Un raccourci qui appelle un verbe inconnu affiche « Commande inconnue » et
#  ne change pas le volume : exactement la panne qu'on prétendait éviter.
SON="$RACINE/config/includes.chroot/usr/bin/lexos-son"
for T in XF86AudioRaiseVolume XF86AudioLowerVolume XF86AudioMute XF86AudioMicMute; do
	V="$(sed -n "s/.*name=\"$T\"[^>]*value=\"lexos son \([^\"]*\)\".*/\1/p" "$RACCOURCIS" | head -1)"
	[[ -n "$V" ]] || { non "$T : aucune valeur « lexos son … » lue"; continue; }
	REPONSE="$(NO_COLOR=1 LEXOS_SON_BULLE=0 bash "$SON" $V </dev/null 2>&1 || true)"
	if grep -q "Commande inconnue" <<< "$REPONSE"; then
		non "$T appelle « lexos son $V », que lexos-son ne connaît pas"
	else
		ok "$T -> « lexos son $V » : un verbe que lexos-son connaît"
	fi
done

#  La bulle : le greffon avait « show-notifications=true ». Sans elle, monter
#  le volume au clavier ne montre plus rien, et on lit ça comme une touche
#  morte. On exige l'identifiant de REMPLACEMENT : sans lui, dix appuis
#  empileraient dix bulles.
if grep -q 'replace-id' "$SON"; then
	ok "lexos-son affiche une bulle avec un identifiant de remplacement (pas dix bulles empilées)"
else
	non "aucune bulle dans lexos-son : monter le volume au clavier ne montrerait rien"
fi

#  La définition du greffon reste, commentée, avec sa raison — comme pour le
#  greffon 8. Ce dépôt explique ses retraits.
if grep -q 'plugin-6.*pulseaudio' "$PANEL"; then
	ok "la définition du greffon 6 reste dans le fichier, pour qu'on sache pourquoi elle n'est plus active"
else
	non "la définition du greffon 6 a été SUPPRIMÉE : la raison de son absence n'est plus lisible"
fi

# =============================================================================
titre "5. LE BANDEAU DE SON DANS LE VOLET — et « indisponible » plutôt qu'un faux"
# =============================================================================
VOLET_APP="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/app.js"
VOLET_PY="$RACINE/config/includes.chroot/usr/lib/lexos/volet.py"
SETTINGS_PY="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
SON_PY="$RACINE/config/includes.chroot/usr/lib/lexos/son.py"

[[ -r "$SON_PY" ]] \
	&& ok "le module partagé /usr/lib/lexos/son.py existe" \
	|| non "son.py manque : le volet et les Paramètres auraient deux moteurs"

#  ═══ UN SEUL ENDROIT OÙ pactl EST APPELÉ POUR LE VOLUME ═══
#  C'est la raison d'être du module. Ce contrôle échoue le jour où quelqu'un
#  recopie un « pactl set-sink-volume » dans l'une des deux pages.
for F in "$VOLET_PY" "$SETTINGS_PY"; do
	if grep -q 'set-sink-volume\|set-sink-mute\|set-source-mute' "$F"; then
		non "$(basename "$F") appelle pactl en direct : deux moteurs pour un réglage"
	else
		ok "$(basename "$F") ne contient aucun appel pactl : tout passe par son.py"
	fi
done
grep -q 'import son' "$VOLET_PY" && grep -q 'import son' "$SETTINGS_PY" \
	&& ok "…et les deux importent bien le module partagé" \
	|| non "l'un des deux n'importe pas son.py"

#  ═══ LE VOLUME EST BORNÉ — 0-100, JAMAIS AU-DELÀ ═══
#  Un « 400 » venu de la page monterait le gain bien au-delà du niveau du
#  matériel : distorsion, et de quoi abîmer un haut-parleur. On FAIT TOURNER
#  le module avec un faux exécuteur qui note ce qui partirait à pactl.
BORNE="$(python3 - "$SON_PY" <<'PYB'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("son", sys.argv[1])
son = importlib.util.module_from_spec(spec); spec.loader.exec_module(son)
vus = []
son._run = lambda argv: (vus.append(argv[-1]), {"ok": True})[1]
son.disponible = lambda: True
for v in (-20, 250, 400, 0, 100, 55, "70"):
    son.regle_volume(v)
print(" ".join(vus))
PYB
)"
MAUVAIS=""
for V in $BORNE; do
	N="${V%\%}"
	case "$N" in ''|*[!0-9]*) MAUVAIS="$MAUVAIS $V"; continue ;; esac
	{ [ "$N" -ge 0 ] && [ "$N" -le 100 ]; } || MAUVAIS="$MAUVAIS $V"
done
if [[ -z "$BORNE" ]]; then
	non "le module n'a produit aucun appel : la borne n'est pas mesurée"
elif [[ -z "$MAUVAIS" ]]; then
	ok "volume borné : -20, 250 et 400 donnent des appels dans 0-100 ($BORNE)"
else
	non "des appels pactl SORTENT de 0-100 :$MAUVAIS (tous : $BORNE)"
fi

#  ═══ pactl ABSENT : LE BANDEAU DISPARAÎT, IL N'EST PAS CASSÉ ═══
#  Une saveur sans PulseAudio ne doit pas montrer un curseur qui ne fait
#  rien. « volume: -1 » est la façon de dire INDISPONIBLE, et app.js doit
#  rendre une chaîne VIDE dans ce cas — mesuré en exécutant sonHTML().
SANS="$(python3 - "$SON_PY" <<'PYS'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("son", sys.argv[1])
son = importlib.util.module_from_spec(spec); spec.loader.exec_module(son)
son.shutil.which = lambda n: None          # pactl introuvable
print(son.etat())
PYS
)"
grep -q "'volume': -1" <<< "$SANS" && grep -q "'micro': None" <<< "$SANS" \
	&& ok "sans pactl : volume -1 et micro None — « indisponible », pas un zéro inventé" \
	|| non "sans pactl, le module rend : $SANS"

if command -v node >/dev/null 2>&1; then
	#  ═══ ON FAIT TOURNER LE VRAI sonHTML(), ON NE LE RELIT PAS ═══
	#  Le fichier est un script de navigateur : il n'exporte rien et appelle
	#  « fetch » au chargement. On le charge donc dans un contexte node où
	#  les deux seules choses dont sonHTML() a besoin — « esc » et « etat » —
	#  sont posées d'avance, et où tout le reste est inoffensif.
	#  PREMIER JET : un « eval » sur un morceau découpé à l'expression
	#  régulière. Il ne s'accrochait plus dès que le code bougeait d'une
	#  ligne, et le contrôle rendait « ERREUR » — un rouge qui n'accusait
	#  rien. On charge le fichier ENTIER, dans une vraie sandbox.
	rendu_son() { # rendu_son <volume> <muet> <micro: true|false|null>
		node - "$VOLET_APP" "$1" "$2" "$3" <<'PYNODE' 2>/dev/null || echo ERREUR
const fs = require("fs"), vm = require("vm");

//  ═══ LA PAGE TELLE QUE LE NAVIGATEUR LA CHARGE ═══
//  index.html charge /moteur/client.js AVANT app.js : esc(), api(), litEtat()
//  et le bandeau y vivent maintenant, pour les quatre fenêtres à la fois. Un
//  banc qui ne lirait qu'app.js mesurerait une page amputée — « LexOS is not
//  defined » dès la première ligne, et un rouge qui n'accuse que le harnais.
//  On ne se tait PAS si le client manque : un banc qui mesure une page sans
//  son client mesure autre chose que la page.
function lireLaPage(chemin){
  const i = String(chemin).indexOf("/usr/share/lexos/");
  if(i < 0 || !String(chemin).endsWith(".js")) return fs.readFileSync(chemin, "utf8");
  const client = String(chemin).slice(0, i) + "/usr/lib/lexos/moteur/web/client.js";
  if(!fs.existsSync(client)) throw new Error("client commun introuvable : " + client);
  return fs.readFileSync(client, "utf8") + "\n" + fs.readFileSync(chemin, "utf8");
}

const [, , fichier, vol, muet, micro] = process.argv;
const bac = {
  //  fetch et les minuteurs ne doivent RIEN faire : la page en appelle au
  //  chargement, et on ne mesure ici que le rendu.
  fetch: () => new Promise(() => {}),
  setTimeout: () => 0, clearTimeout: () => {}, requestAnimationFrame: () => {},
  addEventListener: () => {}, console,
  document: { getElementById: () => null, documentElement: { dataset: {} } },
  location: { hash: "#rapides" },
};
bac.window = bac; bac.globalThis = bac;
vm.createContext(bac);
vm.runInContext(lireLaPage(fichier), bac);
//  ═══ « etat » EST UN « let », PAS UNE PROPRIÉTÉ DU GLOBAL ═══
//  Premier jet : « bac.etat = {…} » depuis l'extérieur. Une déclaration
//  « let » au premier niveau vit dans la portée lexicale du contexte, PAS
//  sur l'objet global : l'affectation créait une deuxième variable que
//  sonHTML() ne voyait pas, et la fonction rendait "" à tous les coups.
//  Le contrôle « sans pactl, le bandeau disparaît » était donc VERT SANS
//  RIEN MESURER — il l'aurait été avec n'importe quel volume. On affecte
//  maintenant DANS le contexte, où le « let » est visible.
const m = micro === "null" ? "null" : (micro === "true" ? "true" : "false");
const r = vm.runInContext(
  `etat = { rapides: { volume: ${Number(vol)}, muet: ${muet === "true"}, micro: ${m} } }; sonHTML();`,
  bac);
process.stdout.write(JSON.stringify(r));
PYNODE
	}
	#  ═══ LE HARNAIS PROUVE D'ABORD QU'IL SAIT RENDRE QUELQUE CHOSE ═══
	#  Sans ce contrôle-ci, « le bandeau disparaît quand volume vaut -1 » est
	#  vert aussi bien quand la règle marche que quand le harnais est cassé.
	#  C'est très exactement le faux vert qu'on vient de corriger.
	TEMOIN="$(rendu_son 40 false false)"
	if grep -q 'qs-son-curseur' <<< "$TEMOIN"; then
		ok "le harnais rend bien le bandeau sur un cas normal — les contrôles qui suivent mesurent quelque chose"
	else
		non "le harnais ne rend RIEN sur un cas normal ($TEMOIN) : tout ce qui suit serait un faux vert"
	fi
	VIDE="$(rendu_son -1 false null)"
	if [[ "$VIDE" == '""' ]]; then
		ok "app.js : avec volume -1, sonHTML() rend une chaîne VIDE — pas de curseur mort"
	elif [[ "$VIDE" == "ERREUR" ]]; then
		non "app.js : sonHTML() n'a pas pu être exécuté — le rendu n'est PAS mesuré"
	else
		non "app.js : sans serveur de son, sonHTML() rend quand même quelque chose ($VIDE)"
	fi
	#  Avec un micro absent, c'est le BOUTON MICRO qui disparaît — pas le
	#  bandeau entier. Même raisonnement que la tuile Bluetooth « Absent ».
	SANS_MIC="$(rendu_son 40 false null)"
	AVEC_MIC="$(rendu_son 40 false true)"
	if [[ "$SANS_MIC" == "ERREUR" || "$AVEC_MIC" == "ERREUR" ]]; then
		non "le rendu avec micro n'a pas pu être exécuté"
	elif grep -q 'qs-son-curseur' <<< "$SANS_MIC" && ! grep -q 'qs-son-micro' <<< "$SANS_MIC" \
	     && grep -q 'qs-son-micro' <<< "$AVEC_MIC"; then
		ok "…et sans micro, seul le bouton micro disparaît — le curseur reste"
	else
		non "le bouton micro ne suit pas l'état « absent »"
	fi
	#  ═══ L'ICÔNE SUIT LE NIVEAU, ET LE MUET GAGNE SUR TOUT ═══
	#  Trois dessins (muet / bas / haut) : c'est ce qui permet de lire l'état
	#  sans lire le chiffre. Le cas qui compte est « muet à 80 % » : l'icône
	#  doit dire coupé, pas fort.
	I_BAS="$(rendu_son 20 false false)"
	I_HAUT="$(rendu_son 80 false false)"
	I_MUET="$(rendu_son 80 true false)"
	if grep -q '🔉' <<< "$I_BAS" && grep -q '🔊' <<< "$I_HAUT" && grep -q '🔇' <<< "$I_MUET"; then
		ok "l'icône suit le niveau (🔉 à 20 %, 🔊 à 80 %) et le MUET l'emporte (🔇 même à 80 %)"
	else
		non "l'icône du haut-parleur ne suit pas l'état"
	fi
	#  Et le curseur affiché tombe à 0 quand c'est coupé : montrer 80 % sur
	#  un son muet est une valeur juste qui raconte une chose fausse.
	#  Le rendu revient en JSON, donc les guillemets y sont échappés :
	#  « value=\"0\" » et non « value="0" ». Écrit sans ça, ce contrôle
	#  cherchait un motif qui ne pouvait PAS exister et rougissait sur du
	#  code juste — un faux rouge coûte autant qu'un faux vert, il envoie
	#  réparer ce qui n'est pas cassé.
	grep -q 'value=\\"0\\"' <<< "$I_MUET" \
		&& ok "…et le curseur retombe à 0 quand le son est coupé (montrer 80 % sur un son muet serait une valeur juste qui raconte une chose fausse)" \
		|| non "le curseur affiche encore le niveau alors que le son est coupé : $I_MUET"
else
	printf '  \033[33m—\033[0m  node absent : le rendu de sonHTML() n'\''est PAS mesuré\n'
fi

#  Les trois actions existent côté Python.
for A in rapides-volume rapides-muet rapides-micro; do
	grep -q "\"$A\"" "$VOLET_PY" \
		&& ok "l'action « $A » est enregistrée dans ACTIONS" \
		|| non "l'action « $A » manque dans ACTIONS : le bandeau ne ferait rien"
done

#  L'étranglement : un <input type="range"> émet un événement par pixel.
grep -q 'SON_ETRANGLE' "$VOLET_APP" && grep -qE 'SON_ETRANGLE *= *[0-9]+' "$VOLET_APP" \
	&& ok "le curseur est étranglé (un appel toutes les ~80 ms), pas un pactl par pixel" \
	|| non "aucun étranglement du curseur : pactl serait appelé soixante fois par seconde"
grep -q 'clearTimeout(sonMinuteur)' "$VOLET_APP" \
	&& ok "…et le minuteur en attente est ANNULÉ au relâchement (sinon une valeur périmée écraserait la bonne)" \
	|| non "le minuteur n'est pas annulé au relâchement : une valeur périmée peut arriver après la finale"

# =============================================================================
titre "6. L'APPAREIL PHOTO — trois modes, et le volet parti avant la photo"
# =============================================================================
#  ALEX : « quand on va cliquer sur appareil photo il va apparaître le menu » —
#  écran complet, une partie, et à côté vidéo.
CAPTURE="$RACINE/config/includes.chroot/usr/bin/lexos-capture"
grep -q 'qsTileHTML("photo"' "$VOLET_APP" \
	&& ok "la tuile « appareil photo » est dans la grille" \
	|| non "aucune tuile appareil photo dans le volet"
for M in plein zone video; do
	grep -q "photoLance('$M')" "$VOLET_APP" \
		&& ok "le choix « $M » est proposé" \
		|| non "le mode « $M » manque dans le choix"
done

#  ═══ LES TROIS MODES DOIVENT ÊTRE ACCEPTÉS PAR lexos-capture ═══
#  Un bouton qui appelle un mode inconnu meurt sur « Commande inconnue ».
for M in plein zone video; do
	grep -qE "^\s+[^)]*\b$M\b[^)]*\)" "$CAPTURE" \
		&& ok "lexos-capture connaît le mode « $M »" \
		|| non "lexos-capture ne connaît pas « $M » : le bouton ne ferait rien"
done

#  ═══ start_new_session=True EST OBLIGATOIRE ═══
#  Le commentaire du dépôt le dit déjà pour act_rapides_partage : « le volet
#  doit pouvoir se refermer sans l'emporter ». Un enfant dans le même groupe
#  de processus mourrait avec le volet — donc PAS DE CAPTURE DU TOUT.
BLOC_PHOTO="$(sed -n '/^def act_rapides_photo/,/^def /p' "$VOLET_PY")"
grep -q 'start_new_session=True' <<< "$BLOC_PHOTO" \
	&& ok "act_rapides_photo lance lexos-capture en start_new_session : la capture survit à la fermeture du volet" \
	|| non "start_new_session manque : la capture mourrait avec le volet"
grep -q 'lexos-capture' <<< "$BLOC_PHOTO" \
	&& ok "…et c'est bien lexos-capture qui est appelé, pas un outil réécrit" \
	|| non "act_rapides_photo n'appelle pas lexos-capture"

#  ═══ LE MODE EST VALIDÉ CONTRE UN ENSEMBLE FERMÉ ═══
#  La doctrine du fichier : « les arguments sont validés contre des ensembles
#  fermés ». On le MESURE en appelant l'action avec une valeur inventée.
REFUS="$(python3 - "$VOLET_PY" <<'PYR'
import sys, re
src = open(sys.argv[1], encoding="utf-8").read()
#  On n'exécute que le bloc de l'action et sa table, sans le reste du module
#  (qui importerait PySide6). C'est le code réel, découpé.
bloc = re.search(r"CAPTURE_MODES = .*?\n\n\ndef act_rapides_photo.*?\n\n", src, re.S)
ns = {"shutil": __import__("shutil"), "subprocess": __import__("subprocess")}
exec(bloc.group(0), ns)
print(ns["act_rapides_photo"]("rm -rf"), ns["act_rapides_photo"](None))
PYR
)"
grep -q "inattendu" <<< "$REFUS" \
	&& ok "un mode inventé est REFUSÉ (ensemble fermé), pas transmis à un shell" \
	|| non "un mode inventé n'est pas refusé : $REFUS"

#  ═══ LE DÉLAI : SANS LUI, LE VOLET EST SUR LA PHOTO ═══
grep -q '"--delai"' "$VOLET_PY" \
	&& ok "un délai est passé à lexos-capture : la photo attend que le volet s'éteigne" \
	|| non "aucun délai : la capture prendrait le volet en photo"
grep -q 'DELAI_CAPTURE' "$CAPTURE" \
	&& ok "lexos-capture sait tenir ce délai (option --delai)" \
	|| non "lexos-capture n'a pas d'option --delai : le délai serait ignoré"
#  Le délai ne doit PAS changer le comportement des autres portes d'entrée.
DEF="$(sed -n 's/^DELAI_CAPTURE=\([0-9]*\)$/\1/p' "$CAPTURE" | head -1)"
[[ "$DEF" == "0" ]] \
	&& ok "…et il vaut 0 par défaut : touche Impr écr et lanceurs de la barre inchangés" \
	|| non "le délai par défaut vaut « $DEF » : toutes les captures attendraient"
#  Et le volet se ferme APRÈS avoir demandé l'action, pas avant.
APRES_PHOTO="$(grep -A2 "await api(\"rapides-photo\"" "$VOLET_APP" || true)"
grep -q 'window.close()' <<< "$APRES_PHOTO" \
	&& ok "le volet se ferme APRÈS avoir lancé la capture (l'ordre compte)" \
	|| non "le volet ne se ferme pas après la demande de capture"

# =============================================================================
titre "7. L'ANIMATION DU VOLET — la règle picom, et son ordre"
# =============================================================================
#  ALEX : « qu'il ouvre fluidement, et se ferme avec l'animation de vieille
#  télévision ». picom applique la PREMIÈRE règle qui correspond et s'arrête
#  là (manuel, section RULES). Le volet est en Qt.Tool, donc
#  _NET_WM_WINDOW_TYPE_UTILITY : il tombait dans la règle générique qui
#  attrape « utility », et recevait son fondu de 80 ms.
#  L'ORDRE N'EST PAS UNE PRÉFÉRENCE DE LECTURE : c'est ce qui fait marcher la
#  chose. Ce contrôle porte sur les NUMÉROS DE LIGNE des deux « match », et
#  rien d'autre ne protégerait la règle d'un déplacement futur.
TV="$RACINE/config/includes.chroot/usr/share/lexos/picom/lexos-tv.conf"
#  ═══ ON LIT LES LIGNES DE CODE, JAMAIS LES COMMENTAIRES ═══
#  Écrit d'abord avec un simple grep sur « window_type = 'utility' ». Il
#  tombait sur le COMMENTAIRE de la règle du volet — qui cite la règle
#  générique pour expliquer pourquoi il faut passer avant elle — et
#  annonçait donc que la règle venait après elle-même. Le contrôle se
#  déclenchait sur sa propre justification, exactement le piège que ce
#  dépôt a déjà payé ailleurs. On n'accepte que les lignes qui COMMENCENT
#  par « match = » (après l'indentation) : ce sont les seules qui comptent
#  pour picom.
L_VOLET="$(grep -nE "^[[:space:]]*match = \"name = 'Volet LexOS'\"" "$TV" | cut -d: -f1 | head -1)"
L_GENERIQUE="$(grep -nE "^[[:space:]]*match = \"window_type .*utility" "$TV" | cut -d: -f1 | head -1)"
if [[ -z "$L_VOLET" ]]; then
	non "aucune règle picom pour le volet : il garderait le fondu court des menus"
elif [[ -z "$L_GENERIQUE" ]]; then
	non "la règle générique « utility » est introuvable : l'ordre n'est pas mesuré"
elif (( L_VOLET < L_GENERIQUE )); then
	ok "la règle du volet (ligne $L_VOLET) précède la générique (ligne $L_GENERIQUE)"
else
	non "la règle du volet (ligne $L_VOLET) vient APRÈS la générique (ligne $L_GENERIQUE) : elle ne serait jamais atteinte"
fi

#  ═══ LE SÉLECTEUR EST LE MÊME DES DEUX CÔTÉS ═══
#  La règle matche « name = 'Volet LexOS' », et le volet POSE ce titre. Une
#  règle accrochée à une valeur que Qt déduirait se décrocherait en silence à
#  la prochaine version. Les deux chaînes doivent rester identiques.
#
#  ⚠ LE setWindowTitle A CHANGÉ DE FICHIER, PAS DE VALEUR. Il vit maintenant
#  dans moteur/fenetre.vue_transparente(), avec les trois autres gestes qui
#  vont avec (fond transparent, Qt.Tool, pas d'ombre) ; volet.py lui passe la
#  chaîne. On éprouve donc la CHAÎNE là où elle est écrite, des deux côtés —
#  chercher la ligne « setWindowTitle » dans volet.py aurait accusé un code
#  juste, et un faux rouge coûte le même prix qu'un faux vert.
FABRIQUE="$(dirname "$VOLET_PY")/moteur/fenetre.py"
if grep -q 'vue_transparente("Volet LexOS")' "$VOLET_PY" \
   && grep -q 'setWindowTitle(titre)' "$FABRIQUE"; then
	ok "le volet pose lui-même le titre « Volet LexOS » (par moteur/fenetre.py) que la règle picom attend"
elif grep -q 'setWindowTitle("Volet LexOS")' "$VOLET_PY"; then
	ok "volet.py pose lui-même le titre « Volet LexOS » que la règle picom attend"
else
	non "personne ne pose ce titre : la règle picom ne s'accrocherait à rien"
fi

#  ═══ LE BLOC « close » EST COMPLET ═══
#  Chacune de ces quatre lignes corrige un piège documenté en tête de
#  lexos-tv.conf. Un bloc « close » qui n'aurait que scale-y donnerait une
#  fenêtre qui s'écrase vers son coin, sans ligne, et invisible dès la
#  première image.
BLOC_TV="$(sed -n "${L_VOLET},/^	},$/p" "$TV")"
MANQUE_TV=""
for C in 'offset-x' 'offset-y' 'shadow-opacity' 'scale-y' 'scale-x'; do
	grep -q "$C" <<< "$BLOC_TV" || MANQUE_TV="$MANQUE_TV $C"
done
[[ -z "$MANQUE_TV" ]] \
	&& ok "le bloc « close » du volet porte scale-x/y, offset-x/y et shadow-opacity" \
	|| non "il manque dans le bloc « close » du volet :$MANQUE_TV"
#  L'opacité RETARDÉE : sans le delay, la fenêtre serait invisible dès la
#  première image et l'écrasement ne se verrait jamais.
grep -Pzoq 'opacity = \{[^}]*delay = 0\.24' <<< "$BLOC_TV" \
	&& ok "…et son opacité est RETARDÉE (delay 0,24 s) : l'écrasement a le temps de se voir" \
	|| non "l'opacité du volet n'est pas retardée : la fenêtre disparaîtrait avant de s'écraser"

#  ═══ L'OUVERTURE N'EST PAS L'ALLUMAGE TÉLÉ ═══
#  La page a DÉJÀ son animation d'ouverture (.shade, 0,34 s). Si picom étirait
#  en plus la fenêtre, les deux gestes se superposeraient.
BLOC_OPEN="$(sed -n "${L_VOLET},${L_GENERIQUE}p" "$TV" | sed -n '/triggers = \[ "open" \]/,/},/p')"
if grep -qE 'scale-x|scale-y' <<< "$BLOC_OPEN"; then
	non "l'OUVERTURE du volet étire la fenêtre : elle se superposerait à l'animation CSS de .shade"
else
	ok "l'ouverture n'est qu'un fondu court — une seule animation d'ouverture, celle du CSS"
fi

#  ═══ ET LE CSS N'ANIME PLUS max-height ═══
#  Animer une hauteur force le navigateur à refaire la mise en page à chaque
#  image ; transform et opacity ne coûtent presque rien. C'est la correction
#  qui se voit sur une machine à graphiques Intel — le ThinkPad.
CSS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/style.css"
SHADE="$(sed -n '/^\.shade{/,/^\.shade\.on{/p' "$CSS")"
TRANS="$(sed -n '/transition:/,/;/p' <<< "$SHADE")"
if grep -q 'max-height' <<< "$TRANS"; then
	non "max-height est encore dans la transition de .shade : le dépliage saccade"
else
	ok ".shade n'anime plus max-height — transform et opacity seulement"
fi
grep -q 'transform-origin:top center' <<< "$SHADE" \
	&& ok "…et l'origine du scaleY est bien en haut (sinon le volet se déplierait par le milieu)" \
	|| non "transform-origin n'est plus en haut : le volet ne se déplierait pas depuis la barre"
grep -q 'prefers-reduced-motion' "$CSS" \
	&& ok "le réglage « moins d'animations » du système est toujours respecté" \
	|| non "prefers-reduced-motion a disparu du CSS"

# =============================================================================
titre "8. UNE TUILE QU'ON N'A PAS PU LIRE NE MENT PAS, ET NE SE CLIQUE PAS"
# =============================================================================
#  ═══ LE DÉFAUT LE PLUS NUISIBLE DE TOUT CE CHANTIER ═══
#  Les lectures du volet partent de front, bornées par une échéance. La
#  première version donnait à chacune une valeur de repli « raisonnable » :
#  Wi-Fi → False. Résultat : la lecture dépasse l'échéance (ou nmcli manque),
#  la tuile affiche « Désactivé » — une valeur INVENTÉE — et le clic, lui,
#  appelle act_rapides_wifi() qui relit la VRAIE radio et bascule à partir
#  d'elle. L'étiquette disait « allumer », le geste ÉTEIGNAIT un Wi-Fi qui
#  marchait. Le bogue du dock, avec une action nuisible au bout.
#
#  On éprouve les DEUX moitiés : que la machine DÉCLARE ce qu'elle n'a pas
#  pu lire, et que la page en fasse une tuile grise, muette et NON CLIQUABLE.
if ! command -v python3 >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
	non "python3 ou node absent : les tuiles inconnues n'ont pas été éprouvées"
else
	#  Côté machine : aucun outil sur le PATH, donc rien n'est lisible.
	#  ⚠ ON VIDE LE PATH DEPUIS L'INTÉRIEUR, PAS AVANT. Le faire devant la
	#  commande emporte python3 lui-même : le sondage ne démarre pas, et le
	#  banc annonce « pas pu mesurer » là où il croyait mesurer. Vu en le
	#  faisant.
	ETAT_NU="$(LEXOS_VOLET_DELAI=1 python3 - "$VOLET_PY" <<'PYEOF' 2>/dev/null
import importlib.util, json, os, sys
os.environ["PATH"] = "/nulle-part"          # aucun outil n'existe plus
sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
spec = importlib.util.spec_from_file_location("v", sys.argv[1])
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
r = v.etat("rapides")["rapides"]
print(json.dumps({"inconnu": r.get("inconnu"), "wifi": r.get("wifi"),
                  "theme": r.get("theme")}))
PYEOF
)"
	if [ -z "$ETAT_NU" ]; then
		non "volet.py n'a pas pu tourner ici : l'état inconnu n'a pas été mesuré"
	else
		INC="$(python3 -c 'import json,sys;print(",".join(json.loads(sys.argv[1])["inconnu"] or []))' "$ETAT_NU" 2>/dev/null || echo ERR)"
		case ",$INC," in
			*,wifi,*) ok "sans nmcli, la machine DÉCLARE le Wi-Fi inconnu au lieu d'inventer « Désactivé » ($INC)" ;;
			*)        non "sans nmcli, « wifi » n'est pas déclaré inconnu (inconnu = « $INC ») : la tuile affirmerait un état qu'elle ignore" ;;
		esac
	fi

	#  Côté page : la tuile inconnue est grise, dit « Inconnu », et n'a AUCUN
	#  gestionnaire de clic. Le troisième point est celui qui protège le Wi-Fi.
	RENDU="$(node - "$VOLET_APP" "$(dirname "$VOLET_PY")/moteur/web/client.js" <<'JSEOF' 2>/dev/null
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(process.argv[3], "utf8") + "\n"
          + fs.readFileSync(process.argv[2], "utf8")
          + "\n;globalThis.__b = {rapidesHTML, pose: e => { etat = e; }};\n";
const el = () => ({innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
  classList:{add(){},remove(){},toggle(){},contains:()=>false},
  querySelectorAll:()=>[], querySelector:()=>null, appendChild(){}, focus(){}, addEventListener(){}});
const bac = vm.createContext({document:{getElementById:()=>el(), querySelectorAll:()=>[],
  querySelector:()=>null, body:el(), createElement:()=>el(),
  documentElement:{style:{setProperty(){}}, dataset:{}}, addEventListener(){}},
  location:{hash:"#rapides"}, window:{}, navigator:{}, fetch:()=>new Promise(()=>{}),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, setInterval:()=>0, clearInterval,
  console, JSON, Math, Date, encodeURIComponent, addEventListener(){}});
bac.globalThis = bac;
vm.runInContext(src, bac, {filename:"app.js"});
const B = bac.__b;
function tuile(html, titre){
  for (const b of html.split('<div class="qs-tile').slice(1)) {
    if (((b.match(/<span class="ti">([^<]*)</) || [])[1]) !== titre) continue;
    const tete = b.slice(0, b.indexOf(">"));
    return {gris: tete.includes("qs-disabled"), cliquable: tete.includes("onclick"),
            sous: (b.match(/<span class="su">([^<]*)</) || [])[1]};
  }
  return null;
}
const base = {wifi:true, bt:true, avion:false, crt:true, perf:"medium",
              perfLabel:"Médium", volume:50, muet:false, micro:false};
B.pose({rapides: Object.assign({inconnu: []}, base)});
const lu = tuile(B.rapidesHTML(), "Wi-Fi");
B.pose({rapides: Object.assign({}, base, {inconnu: ["wifi", "avion"], wifi:false})});
const pasLu = tuile(B.rapidesHTML(), "Wi-Fi");
console.log(JSON.stringify({lu, pasLu}));
JSEOF
)"
	if [ -z "$RENDU" ]; then
		non "la page n'a pas pu être rendue : la tuile inconnue n'a pas été mesurée"
	else
		L_SOUS="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["lu"]["sous"])' "$RENDU" 2>/dev/null || echo ERR)"
		P_SOUS="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["pasLu"]["sous"])' "$RENDU" 2>/dev/null || echo ERR)"
		P_CLIC="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["pasLu"]["cliquable"])' "$RENDU" 2>/dev/null || echo ERR)"
		P_GRIS="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["pasLu"]["gris"])' "$RENDU" 2>/dev/null || echo ERR)"
		[ "$L_SOUS" = "Activé" ] \
			&& ok "quand la lecture aboutit, la tuile dit ce qu'elle a lu ($L_SOUS)" \
			|| non "la tuile lue affiche « $L_SOUS » — le témoin ne mesure rien, le reste est sans valeur"
		[ "$P_SOUS" = "Inconnu" ] \
			&& ok "quand elle n'aboutit pas, la tuile dit « Inconnu », ni Activé ni Désactivé" \
			|| non "la tuile non lue affiche « $P_SOUS » — une valeur inventée"
		[ "$P_GRIS" = "True" ] \
			&& ok "…et elle est grisée" \
			|| non "la tuile non lue n'est pas grisée : rien ne signale qu'elle ne sait pas"
		[ "$P_CLIC" = "False" ] \
			&& ok "…et elle n'a AUCUN gestionnaire de clic : impossible d'éteindre un Wi-Fi allumé en croyant l'allumer" \
			|| non "la tuile non lue reste CLIQUABLE — le clic relirait la vraie radio et ferait l'inverse de l'étiquette"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
