#!/usr/bin/env bash
# =============================================================================
#  Éprouver le fond d'écran (images téléchargées) et la pile des Paramètres
# =============================================================================
#  DEUX DEMANDES D'ALEX, LE MÊME JOUR.
#
#  1. « fais que dans les images qu'on télécharge, on peut les utiliser comme
#     fond d'écran aussi — pour les utilisateurs qui veulent utiliser un autre
#     fond d'écran, ils vont être capables aussi. »
#
#     Une image téléchargée atterrit dans Téléchargements. Ce dossier n'était
#     PAS ratissé : « liste », « aleatoire » et le compte de la commande nue
#     l'ignoraient, et le sélecteur graphique s'ouvrait dans /usr/share. On
#     pouvait poser l'image en tapant son chemin complet — c'est-à-dire jamais.
#
#     ET LE PIÈGE PLUS GRAVE, TROUVÉ EN LISANT : le fond animé « code » démarre
#     à la première session (lexos-firstrun). Il RECOUVRE le fond fixe. Le
#     chemin du menu ne l'arrêtait pas : on choisissait sa photo, elle était
#     bien posée… sous une animation. « Ça n'a pas marché. »
#
#  2. « utiliser ces images pour les utiliser dans les paramètres de la
#     batterie » — quatre piles, verte pleine à rouge vide.
#
#  CE QUE CE BANC NE PEUT PAS FAIRE : afficher un bureau. Il n'y a pas de
#  serveur X ici. Il éprouve donc ce qui est éprouvable sans écran — quels
#  dossiers sont ratissés, quel ordre, ce qui est appelé et DANS QUEL ORDRE —
#  en donnant à chaque programme un PATH fermé et de faux outils qui ÉCRIVENT
#  ce qu'on leur demande au lieu de le faire.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOND="$RACINE/config/includes.chroot/usr/bin/lexos-fond-ecran"
FIRSTRUN="$RACINE/config/includes.chroot/usr/bin/lexos-firstrun"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
DEMO="$RACINE/web-demo/index.html"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. Une image téléchargée est un fond comme un autre"
# =============================================================================
#  Un faux foyer avec les trois écritures possibles du dossier : le nom
#  français des ISO fr_CA, l'anglais d'une session créée avant la traduction,
#  et Images pour comparer.
FOYER="$BANC/foyer"
mkdir -p "$FOYER/Images" "$FOYER/Téléchargements" "$FOYER/Downloads"
: > "$FOYER/Images/deja-la.png"
: > "$FOYER/Téléchargements/photo-telechargee.jpg"
: > "$FOYER/Downloads/autre-telechargement.webp"
: > "$FOYER/Téléchargements/document.pdf"          # ne doit PAS être proposé
: > "$FOYER/Téléchargements/moderne.avif"          # format récent, doit passer

liste() {
	HOME="$FOYER" XDG_PICTURES_DIR="" XDG_DOWNLOAD_DIR="" \
		bash "$FOND" liste 2>/dev/null
}

L="$(liste)"
grep -q 'photo-telechargee.jpg' <<< "$L" \
	&& ok "une image de ~/Téléchargements est proposée" \
	|| non "~/Téléchargements est encore ignoré — l'image reste inutilisable"
grep -q 'autre-telechargement.webp' <<< "$L" \
	&& ok "~/Downloads aussi (session créée avant la traduction des dossiers)" \
	|| non "~/Downloads n'est pas ratissé"
grep -q 'deja-la.png' <<< "$L" \
	&& ok "et ~/Images n'a pas été perdu au passage" \
	|| non "~/Images a disparu du ratissage"
grep -q 'moderne.avif' <<< "$L" \
	&& ok "le format AVIF est accepté (le clic droit de Fichiers le proposait déjà)" \
	|| non "AVIF refusé ici alors que l'action Thunar l'accepte — deux vérités"
grep -q 'document.pdf' <<< "$L" \
	&& non "un PDF est proposé comme fond d'écran" \
	|| ok "un PDF n'est pas proposé"

#  XDG_DOWNLOAD_DIR : le dossier peut s'appeler autrement. On le suit.
mkdir -p "$BANC/ailleurs"
: > "$BANC/ailleurs/rangee-ailleurs.png"
L2="$(HOME="$FOYER" XDG_PICTURES_DIR="" XDG_DOWNLOAD_DIR="$BANC/ailleurs" \
	bash "$FOND" liste 2>/dev/null)"
grep -q 'rangee-ailleurs.png' <<< "$L2" \
	&& ok "un dossier de téléchargement renommé est suivi par XDG_DOWNLOAD_DIR" \
	|| non "XDG_DOWNLOAD_DIR n'est pas lu"

# =============================================================================
titre "2. Le sélecteur s'ouvre chez l'utilisateur, pas dans /usr/share"
# =============================================================================
#  On donne un faux zenity qui ÉCRIT le dossier de départ qu'on lui passe.
#  LE FAUX ZENITY ÉCRIT DANS UN FICHIER, PAS SUR L'ERREUR.
#  Le vrai appel se termine par « 2>/dev/null » — un faux qui parle sur
#  l'erreur standard est donc muet pour le banc, qui conclurait « départ
#  vide » quoi qu'il arrive. Un outil de banc qui ne peut rien dire mesure
#  toujours la même chose : rien.
BIN="$BANC/bin"; mkdir -p "$BIN"
TRACE_SEL="$BANC/depart.txt"
cat > "$BIN/zenity" <<ZEN
#!/bin/sh
for a in "\$@"; do
	case "\$a" in --filename=*) printf '%s\n' "\${a#--filename=}" > "$TRACE_SEL" ;; esac
done
exit 1
ZEN
chmod +x "$BIN/zenity"
: > "$TRACE_SEL"
HOME="$FOYER" PATH="$BIN:$PATH" bash "$FOND" choisir >/dev/null 2>&1
DEPART="$(cat "$TRACE_SEL")"
case "$DEPART" in
	"$FOYER/Images/") ok "le sélecteur s'ouvre dans les images de l'utilisateur" ;;
	*"/usr/share"*)   non "le sélecteur s'ouvre encore dans /usr/share — il faut remonter à la main" ;;
	*)                non "dossier de départ inattendu : « $DEPART »" ;;
esac
#  Sans ~/Images, il doit descendre sur les téléchargements — pas sur /usr.
FOYER2="$BANC/foyer2"; mkdir -p "$FOYER2/Téléchargements"
: > "$TRACE_SEL"
HOME="$FOYER2" PATH="$BIN:$PATH" bash "$FOND" choisir >/dev/null 2>&1
DEPART="$(cat "$TRACE_SEL")"
case "$DEPART" in
	"$FOYER2/Téléchargements/") ok "sans dossier Images, il s'ouvre dans les téléchargements" ;;
	*) non "sans ~/Images, départ : « $DEPART »" ;;
esac

# =============================================================================
titre "3. Poser un fond ARRÊTE l'animation qui le recouvrirait"
# =============================================================================
#  LE DÉFAUT QUI RENDAIT TOUT LE RESTE INUTILE. lexos-firstrun démarre le fond
#  animé « code » à la première session. Il recouvre le fond fixe. « lexos
#  wallpaper » l'arrêtait déjà ; le chemin du MENU — celui que tout le monde
#  prend — ne l'arrêtait pas. L'image était posée, et invisible.
BIN2="$BANC/bin2"; mkdir -p "$BIN2"
JOURNAL="$BANC/appels.txt"; : > "$JOURNAL"
cat > "$BIN2/lexos-fond-anime" <<ANIM
#!/bin/sh
printf 'anime %s\n' "\$*" >> "$JOURNAL"
exit 0
ANIM
cat > "$BIN2/xfconf-query" <<XFC
#!/bin/sh
case "\$*" in
	*-l*) printf '/backdrop/screen0/monitorDP-1/workspace0/last-image\n' ;;
	*-s*) printf 'xfconf %s\n' "\$*" >> "$JOURNAL" ;;
esac
exit 0
XFC
cat > "$BIN2/readlink" <<'RL'
#!/bin/sh
[ "$1" = "-f" ] && shift
printf '%s\n' "$1"
RL
chmod +x "$BIN2"/*
: > "$FOYER/Images/choisie.png"
HOME="$FOYER" PATH="$BIN2:$PATH" DISPLAY=":0" \
	bash "$FOND" "$FOYER/Images/choisie.png" >/dev/null 2>&1

grep -q '^anime off' "$JOURNAL" \
	&& ok "l'animation est arrêtée — l'image choisie se voit vraiment" \
	|| non "l'animation continue par-dessus : l'image est posée et invisible"
#  ET DANS CET ORDRE. En arrêtant APRÈS, l'arrêt remet le fond d'avant
#  par-dessus celui qu'on vient de choisir.
LIGNE_ANIME="$(grep -n '^anime off' "$JOURNAL" | head -1 | cut -d: -f1)"
LIGNE_POSE="$(grep -n '^xfconf.*last-image' "$JOURNAL" | head -1 | cut -d: -f1)"
if [ -n "$LIGNE_ANIME" ] && [ -n "$LIGNE_POSE" ] && [ "$LIGNE_ANIME" -lt "$LIGNE_POSE" ]; then
	ok "et AVANT la pose (sinon l'arrêt remettrait le fond d'avant par-dessus)"
else
	non "ordre : anime=$LIGNE_ANIME pose=$LIGNE_POSE"
fi
#  « fais les images sur un fond noir avec les images » : l'image ENTIÈRE
#  (style 4 — une photo de téléphone est verticale, le style 5 n'en montrait
#  que la bande du milieu), et ce qui dépasse est NOIR, pas le bleu de XFCE.
grep -q 'image-style .*4' "$JOURNAL" \
	&& ok "l'image entière (style « ajusté ») — la photo verticale garde sa tête" \
	|| non "le style posé n'est pas « ajusté » : une photo verticale serait recadrée"
grep -q 'color-style .*0' "$JOURNAL" \
	&& ok "la couleur de fond passe en « unie »" \
	|| non "color-style absent : ce qui dépasse resterait au bleu de XFCE"
grep -Eq 'rgba1 .*0\.0 .*0\.0 .*0\.0 .*1\.0' "$JOURNAL" \
	&& ok "et cette couleur unie est le NOIR (la composition du fond « démon »)" \
	|| non "rgba1 n'est pas posé à noir"

#  Le clic droit de Fichiers dit la même chose que le menu.
grep -q 'lexos wallpaper %f ajuster' \
	"$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot" \
	&& ok "le clic droit « fond d'écran » emploie le même cadrage" \
	|| non "le clic droit recadre encore (remplir) — deux portes, deux résultats"

# =============================================================================
titre "4. Le fond de marque ne revient PAS effacer le choix de l'utilisateur"
# =============================================================================
#  lexos-firstrun repose le fond de marque toutes les cinq secondes pendant une
#  minute, pour gagner une course contre xfdesktop. Quelqu'un qui ouvre sa
#  première session, va au menu et pose sa photo dans ce laps de temps se la
#  faisait effacer — par nous. « J'ai mis mon image et elle est revenue toute
#  seule » est une panne pire que celle qu'on corrigeait.
grep -q 'actuel=' "$FIRSTRUN" \
	&& ok "la boucle relit ce qui est posé avant de réécrire" \
	|| non "la boucle réécrit sans regarder — le choix de l'utilisateur est effacé"
grep -q '\[\[ -n "$actuel" && "$actuel" != "$WALL" \]\] && break' "$FIRSTRUN" \
	&& ok "et elle s'arrête dès que ce n'est plus notre image" \
	|| non "elle ne s'arrête jamais : une minute d'écrasement"

# =============================================================================
titre "5. La pile d'Alex dans les Paramètres — quatre états, quatre couleurs"
# =============================================================================
#  On charge le vrai code de la page et on lui demande des piles. Une relecture
#  dirait « ça a l'air juste » ; ceci dit ce que l'écran montrera.
cat > "$BANC/pile.js" <<'JS'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
const deb = src.indexOf("const BAT_PALIERS");
const fin = src.indexOf("\n}", src.indexOf("function batGlyph")) + 2;
eval(src.slice(deb, fin));
const out = {};
for (const p of [100, 90, 76, 75, 60, 51, 40, 26, 20, 5, 0]) {
  const g = batGlyph(p, false, 40);
  out[p] = {
    barres: (g.match(/<rect x="12"/g) || []).length,
    couleur: (g.match(/stroke-width="4"[\s\S]*?/) ? (g.match(/stroke="([^"]+)"\s*$/m) || [])[1] : null)
             || (g.match(/<rect x="17"[^>]*fill="([^"]+)"/) || [])[1],
    eclair: /d="M25 20/.test(g),
  };
}
out.charge = { eclair: /d="M25 20/.test(batGlyph(50, true, 40)) };
console.log(JSON.stringify(out));
JS
verifie_pile() { # verifie_pile <fichier> <étiquette>
	local J
	J="$(node "$BANC/pile.js" "$1" 2>/dev/null)" || { non "$2 : le glyphe ne s'évalue pas"; return; }
	local MAUVAIS=0
	attendu() { # attendu <pct> <barres> <couleur>
		local got
		got="$(node -e "const o=$J;console.log(o['$1'].barres+' '+o['$1'].couleur)")"
		[ "$got" = "$2 $3" ] || { non "$2 barres/$3 attendus à $1 % — obtenu « $got »"; MAUVAIS=1; }
	}
	attendu 100 4 "var(--ok)"
	attendu 90  4 "var(--ok)"
	attendu 76  4 "var(--ok)"
	attendu 75  3 "var(--warn)"     # le seuil lui-même bascule
	attendu 60  3 "var(--warn)"
	attendu 51  3 "var(--warn)"
	attendu 40  2 "#E8590C"
	attendu 26  2 "#E8590C"
	attendu 20  1 "var(--off)"
	attendu 0   1 "var(--off)"
	[ "$MAUVAIS" = 0 ] && ok "$2 : les quatre paliers d'Alex (vert 4 · jaune 3 · orange 2 · rouge 1)"
	local E
	E="$(node -e "const o=$J;console.log(o.charge.eclair, o['51'].eclair)")"
	[ "$E" = "true false" ] \
		&& ok "$2 : l'éclair n'apparaît QUE sur le secteur" \
		|| non "$2 : éclair (secteur, batterie) = $E"
}
verifie_pile "$APP"  "ISO"
verifie_pile "$DEMO" "démo"

#  Et la section Énergie la porte vraiment — un glyphe défini et jamais appelé
#  ne s'affiche pas plus qu'un glyphe absent.
grep -q 'batGlyph(etat.batterie.niveau' "$APP" \
	&& ok "la section Énergie de l'ISO affiche la pile" \
	|| non "la pile est définie mais jamais posée dans la page"
grep -q 'batGlyph(state.batt' "$DEMO" \
	&& ok "celle de la démo aussi (les deux disent la même chose)" \
	|| non "la démo n'affiche pas la pile — l'ISO et la démo divergent"

#  LES COULEURS D'ÉTAT NE SUIVENT PAS L'ACCENT. Une batterie à plat doit
#  rester rouge sur une ISO montée en bleu, comme l'antenne Wi-Fi coupée.
if grep -A 6 'const BAT_PALIERS' "$APP" | grep -q 'var(--ac)'; then
	non "un palier suit l'accent — une batterie à plat deviendrait bleue"
else
	ok "aucun palier ne suit l'accent : le rouge reste rouge"
fi

# =============================================================================
titre "6. La galerie des Paramètres — vraies fonctions, vraie liste blanche"
# =============================================================================
#  On charge settings.py comme module (il ne démarre son serveur que sous
#  __main__) et on appelle les vraies fonctions sur le faux foyer.
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
galerie() { # galerie <script-python>  — HOME est le faux foyer
	HOME="$FOYER" python3 - "$SETTINGS" <<PYG
import sys, importlib.util, json, os
spec = importlib.util.spec_from_file_location("s", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
$1
PYG
}

R="$(galerie 'print(json.dumps([p.split("/")[-1] for p in m._fonds_perso()]))' 2>/dev/null)"
grep -q 'photo-telechargee.jpg' <<< "$R" \
	&& ok "la galerie propose l'image téléchargée" \
	|| non "la galerie ignore Téléchargements : $R"
grep -q 'document.pdf' <<< "$R" \
	&& non "un PDF dans la galerie de fonds" \
	|| ok "et n'y met pas les PDF"

#  LE TRI : la plus récente d'abord — celle qu'on vient de télécharger est
#  celle qu'on vient chercher.
touch -d '2020-01-01' "$FOYER/Images/deja-la.png"
touch "$FOYER/Téléchargements/photo-telechargee.jpg"
R="$(galerie 'print(json.dumps([p.split("/")[-1] for p in m._fonds_perso()]))' 2>/dev/null)"
PREMIER="$(printf '%s' "$R" | python3 -c "import json,sys; print(json.load(sys.stdin)[0])" 2>/dev/null)"
[ "$PREMIER" = "photo-telechargee.jpg" ] \
	&& ok "la plus récente arrive en tête de la galerie" \
	|| non "en tête : « $PREMIER » au lieu de la plus récente"

#  LA LISTE BLANCHE. La page ne connaît que des indices ; un chemin libre
#  refusé, un indice hors de la galerie refusé, et un nom qui ne correspond
#  plus (la galerie a bougé entre l'affichage et le clic) refusé aussi.
#  _run EST REMPLACÉ PAR UN FAUX QUI RÉUSSIT. Sans ça, le refus observé
#  pouvait venir de l'environnement (« lexos » absent du conteneur) et pas de
#  la liste blanche : une liste blanche trouée serait passée verte. Le banc
#  s'en est accusé lui-même à la mutation C, première version.
R="$(galerie 'm._run = lambda argv, **k: {"ok": True, "argv": argv}
print(json.dumps(m.act_fond_fichier("/etc/passwd")))' 2>/dev/null)"
grep -q '"ok": false' <<< "$R" \
	&& ok "un chemin libre est refusé (« /etc/passwd » ne passe pas)" \
	|| non "act_fond_fichier a accepté un chemin : $R"
R="$(galerie 'm._run = lambda argv, **k: {"ok": True, "argv": argv}
print(json.dumps(m.act_fond_fichier(999)))' 2>/dev/null)"
grep -q '"ok": false' <<< "$R" \
	&& ok "un indice hors de la galerie est refusé" \
	|| non "indice 999 accepté : $R"
R="$(galerie 'print(json.dumps(m.act_fond_fichier({"i": 0, "nom": "autre-nom.png"})))' 2>/dev/null)"
grep -q 'rouvre la section' <<< "$R" \
	&& ok "un nom qui ne correspond plus fait refuser (la galerie avait bougé)" \
	|| non "indice + mauvais nom acceptés — on poserait la mauvaise photo : $R"

#  Et le chemin heureux : l'indice 0 avec le BON nom part vers lexos wallpaper
#  en « ajuster » — le fond noir, encore.
R="$(galerie 'm._run = lambda argv, **k: {"ok": True, "argv": argv}
print(json.dumps(m.act_fond_fichier({"i": 0, "nom": "photo-telechargee.jpg"})))' 2>/dev/null)"
grep -q '"ajuster"' <<< "$R" && grep -q 'photo-telechargee.jpg' <<< "$R" \
	&& ok "l'indice valide applique l'image en « ajuster » (entière, sur noir)" \
	|| non "chemin heureux : $R"

#  LA ROUTE DES VIGNETTES ne sert que des indices — jamais un chemin. On
#  vérifie la propriété sur le CODE : la route relit _fonds_perso() et
#  n'accepte qu'un entier borné.
grep -q 'api/fond-vignette' "$SETTINGS" \
	&& ok "la route des vignettes existe" || non "pas de route de vignettes"
if sed -n '/fond-vignette/,/return super().do_GET()/p' "$SETTINGS" | grep -q 'self.path.split\|os.path.join(.*query\|open(.*query'; then
	non "la route compose un chemin depuis la requête — traversée possible"
else
	ok "la route ne lit que par indice revalidé (aucun chemin ne vient de la page)"
fi

#  Et la page pose ses vignettes sur NOIR, en « contain » : l'aperçu montre
#  ce que le bureau montrera.
grep -q "#000 url('/api/fond-vignette" "$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js" \
	&& ok "les vignettes de la page sont sur fond noir, image entière" \
	|| non "les vignettes ne montrent pas la composition réelle"

# =============================================================================
titre "7. Un nom de fichier ne peut pas s'exécuter dans la page"
# =============================================================================
#  UN NOM DE FICHIER TÉLÉCHARGÉ N'EST PAS CHOISI PAR L'UTILISATEUR : le site
#  d'en face le dicte (Content-Disposition). La galerie l'affiche. Si ce nom
#  arrive dans du HTML sans être neutralisé, on vient d'ouvrir une porte par
#  celle qu'on ouvrait — et la page des Paramètres exécute des commandes.
#
#  Le premier jet interpolait le nom dans un attribut onclick délimité par une
#  APOSTROPHE, via JSON.stringify — qui n'échappe ni l'apostrophe ni « < ».
#  On ne « mieux échappe » pas : on ne met plus AUCUNE chaîne dans le HTML.
#  Le banc le vérifie en rendant vraiment la galerie avec un nom piégé.
#  Le rendu passe par un fichier plutôt qu'un heredoc imbriqué : un heredoc
#  dans une substitution de commande dans un heredoc se referme au mauvais
#  endroit, et node ne recevait rien. Le banc affichait alors « pas de script
#  exécutable » — sur une sortie VIDE. Un contrôle qui passe sur du vide ne
#  contrôle rien ; d'où le garde-fou sur la longueur, juste en dessous.
cat > "$BANC/rendu-galerie.js" <<'JS'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
const deb = src.indexOf("const fp = etat.fonds_perso || [];");
const fin = src.indexOf("})()}", deb);
if (deb < 0 || fin < 0) { console.error("galerie introuvable"); process.exit(1); }
const esc = s => String(s).replace(/[&<>"]/g,
  c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
//  LE NOM PIÉGÉ : apostrophe, guillemet, chevron. Un nom de fichier
//  téléchargé n'est pas choisi par l'utilisateur — le site d'en face le
//  dicte par Content-Disposition.
const etat = { fonds_perso: [{ i: 0, nom: "x'\"><img src=x onerror=alert(1)>.png" }] };
console.log(new Function("etat", "esc", src.slice(deb, fin))(etat, esc));
JS
GAL="$(node "$BANC/rendu-galerie.js" "$APP" 2>/dev/null)"

[ "${#GAL}" -gt 200 ] \
	&& ok "la galerie se rend vraiment (sinon les contrôles suivants ne diraient rien)" \
	|| non "rendu vide (${#GAL} caractères) — les contrôles d'échappement seraient creux"
#  CE QU'IL FAUT CHERCHER, C'EST L'ÉVASION — PAS LA CHAÎNE.
#  « onerror=alert » APPARAÎT dans le rendu, et c'est normal : le nom du
#  fichier s'affiche en infobulle, échappé (« &lt;img … onerror=alert(1)&gt; »).
#  Du texte inerte dans un attribut correctement clos. Le premier jet de ce
#  banc cherchait cette chaîne et se déclarait rouge sur un rendu SAIN.
#  Ce qui trahit une vraie évasion, c'est une BALISE non échappée : après
#  échappement, « < » devient « &lt; » et « <img » ne peut plus exister.
case "$GAL" in
	*"<img"*) non "une balise non échappée est sortie du nom de fichier — script exécutable" ;;
	*) ok "aucune balise ne sort du nom de fichier (le « < » est échappé)" ;;
esac
#  Et l'apostrophe : c'est elle qui refermait l'attribut onclick du premier
#  jet. Aucun attribut ne doit plus être délimité par une apostrophe ici.
case "$GAL" in
	*"onclick='"*) non "un attribut onclick délimité par une apostrophe — une seule dans un nom le referme" ;;
	*) ok "aucun attribut délimité par une apostrophe" ;;
esac
case "$GAL" in
	*"setFondFichier(0)"*) ok "le gestionnaire ne reçoit qu'un ENTIER (aucune chaîne dans le HTML)" ;;
	*) non "le gestionnaire reçoit autre chose qu'un entier" ;;
esac
case "$GAL" in
	*"&quot;&gt;&lt;img"*) ok "et l'infobulle est échappée (guillemet et chevrons)" ;;
	*) non "l'infobulle laisse passer du balisage" ;;
esac

grep -q '"nom": Path(c).name' "$SETTINGS" \
	&& ok "l'état ne publie que le nom, jamais le chemin" \
	|| non "l'état publie des chemins vers la page"

# =============================================================================
titre "8. Une vignette ne charge pas un fichier de n'importe quelle taille"
# =============================================================================
#  Le pont sert le fichier TEL QUEL (il n'a pas de quoi redimensionner). Sans
#  plafond, ouvrir la section chargeait en mémoire, jusqu'à 24 fois en
#  parallèle, des fichiers dont la taille est dictée par le site d'en face.
python3 - "$FOYER/Téléchargements/enorme.bmp" <<'PYB'
import sys, os
#  41 Mio, creux : le fichier occupe la taille annoncée sans coûter le disque.
with open(sys.argv[1], "wb") as f:
    f.truncate(41 * 1024 * 1024)
PYB
R="$(galerie 'print(json.dumps([p.split("/")[-1] for p in m._fonds_perso()]))' 2>/dev/null)"
grep -q 'enorme.bmp' <<< "$R" \
	&& non "un fichier de 41 Mio est proposé en vignette" \
	|| ok "un fichier au-delà du plafond n'entre pas dans la galerie"
#  Et le plafond est REVÉRIFIÉ au service : le fichier a pu grossir depuis.
grep -q 'FONDS_PERSO_POIDS_MAX' "$SETTINGS" \
	&& [ "$(grep -c 'FONDS_PERSO_POIDS_MAX' "$SETTINGS")" -ge 3 ] \
	&& ok "le plafond est vérifié à l'énumération ET au service" \
	|| non "le plafond n'est vérifié qu'à un seul endroit"
rm -f "$FOYER/Téléchargements/enorme.bmp"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
