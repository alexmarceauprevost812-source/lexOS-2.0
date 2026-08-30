#!/usr/bin/env bash
# =============================================================================
#  Le gestionnaire de fichiers doit porter le dossier orange, pas un engrenage
# =============================================================================
#  ALEX, TROISIÈME SIGNALEMENT SUR LE MÊME SUJET : « le gestionnaire de
#  fichiers est toujours avec un engrenage au lieu du fichier. » Quatrième
#  icône du dock, juste après le terminal.
#
#  ═══ DEUX CORRECTIFS LIVRÉS, ZÉRO EFFET — ET IL FAUT LE DIRE ═══
#  1) Cinq alias posés dans le thème (Thunar, thunar, org.xfce.thunar,
#     file-manager, system-file-manager → folder-open).
#  2) « apps/scalable » ajouté au Directories= d'index.theme.
#  Le second était un NON-ÉVÉNEMENT : le crochet 0605 réécrit index.theme
#  d'après le disque à chaque construction, donc apps/scalable y figurait
#  déjà. On a livré un correctif en croyant réparer quelque chose.
#
#  Les deux partageaient le même pari : que Thunar réclame une des écritures
#  devinées, et que GTK aille la chercher là où on croit. Deux inconnues,
#  aucune vérifiable depuis ce dépôt — la machine de construction n'a pas
#  accès aux miroirs Debian et il n'y a pas d'écran pour REGARDER une icône.
#
#  ═══ CE QUI CHANGE : ON N'ESPÈRE PLUS, ON ÉCRIT LA DEMANDE ═══
#  Une copie du .desktop de Thunar est posée dans /usr/local/share/applications
#  (qui passe avant /usr/share dans XDG_DATA_DIRS) avec « Icon=folder-open ».
#  Ce nom n'est pas un pari : c'est le dossier orange de places/scalable, le
#  seul dossier dont les photos d'Alex prouvent qu'il est bien parcouru.
#
#  ═══ CE QUE CE BANC ÉPROUVE ═══
#  Il EXÉCUTE le vrai fragment du crochet 0400 (découpé entre ses marqueurs)
#  sur trois disques fabriqués : le nom Debian classique, le nom renommé, et
#  un .desktop sans ligne Icon= du tout. Puis il vérifie ce qui compte
#  vraiment — pas « le code a tourné », mais : l'icône est-elle écrite, dans
#  le BON groupe, le dock pointe-t-il sur la copie, et les références par
#  identifiant suivent-elles le renommage.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# --- On découpe le VRAI fragment, pas une copie qui dériverait --------------
FRAGMENT="$BANC/fragment.sh"
sed -n '/^# >>> banc: fichiers$/,/^# <<< banc: fichiers$/p' "$HOOK" > "$FRAGMENT"
if [[ "$(grep -c . "$FRAGMENT")" -lt 20 ]]; then
	non "fragment « banc: fichiers » introuvable dans le crochet 0400 — rien à éprouver"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi
ok "fragment découpé du crochet 0400 ($(grep -c . "$FRAGMENT") lignes) — c'est le vrai code qui tourne"

# --- Un faux disque, monté comme la construction le trouverait --------------
monte() { # monte <dossier> <nom-du-desktop> <avec-icone 0/1>
	local d="$1" nom="$2" avec="$3"
	mkdir -p "$d/apps" "$d/local" "$d/skel/.config/plank/dock1/launchers" \
	         "$d/skel/.config/xfce4/xfconf/xfce-perchannel-xml" "$d/etc"
	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Name=Thunar File Manager"
		[[ "$avec" == "1" ]] && echo "Icon=org.xfce.thunar"
		echo "Exec=thunar %F"
		echo "MimeType=inode/directory;"
		echo ""
		echo "[Desktop Action open-home]"
		echo "Name=Home"
		echo "Exec=thunar ~"
	} > "$d/apps/$nom"
	#  Une fenêtre annexe de Thunar, pour vérifier qu'elle n'est PAS prise
	#  quand le nom principal a changé : elle porte NoDisplay=true.
	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Name=Thunar Settings"
		echo "NoDisplay=true"
		echo "Icon=preferences-system"
	} > "$d/apps/thunar-settings.desktop"
	printf '[PlankDockItemPreferences]\nLauncher=file:///usr/share/applications/thunar.desktop\n' \
		> "$d/skel/.config/plank/dock1/launchers/02-files.dockitem"
	printf '<value type="string" value="thunar.desktop"/>\n' \
		> "$d/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
	printf 'inode/directory=thunar.desktop\n' > "$d/etc/mimeapps.list"
}

joue() { # joue <dossier>
	LEXOS_APPS="$1/apps" LEXOS_APPS_LOCAL="$1/local" LEXOS_SKEL="$1/skel" \
		LEXOS_MIMEAPPS="$1/etc/mimeapps.list" \
		sh "$FRAGMENT" > "$1/journal.txt" 2>&1
}

# =============================================================================
titre "1. Le cas d'aujourd'hui : thunar.desktop, avec son Icon= à lui"
# =============================================================================
D="$BANC/classique"; monte "$D" "thunar.desktop" 1; joue "$D"
COPIE="$D/local/thunar.desktop"

if [[ -r "$COPIE" ]]; then
	ok "la copie masquante est posée dans /usr/local/share/applications"
else
	non "aucune copie : le menu et le dock garderaient l'icône d'origine"
fi
if grep -q '^Icon=folder-open$' "$COPIE" 2>/dev/null; then
	ok "elle réclame « folder-open » — le dossier orange que le thème porte"
else
	non "l'icône n'a pas été remplacée : $(grep '^Icon=' "$COPIE" 2>/dev/null | tr '\n' ' ')"
fi
#  ET PLUS AUCUNE TRACE de l'ancien nom : s'il restait une ligne Icon=
#  org.xfce.thunar quelque part, c'est elle qui pourrait gagner.
if ! grep -q '^Icon=org\.xfce\.thunar$' "$COPIE" 2>/dev/null; then
	ok "aucune ligne Icon= n'a survécu au remplacement"
else
	non "l'ancienne ligne Icon= est toujours là — deux icônes déclarées"
fi
#  Le fichier doit rester UN .desktop valide : un remplacement à la hache
#  qui casserait le groupe rendrait le lanceur inutilisable.
if python3 -c "
import configparser,sys
c=configparser.ConfigParser(interpolation=None,strict=False)
c.read(sys.argv[1],encoding='utf-8')
assert 'Desktop Entry' in c
assert c['Desktop Entry'].get('exec','').startswith('thunar')
assert c['Desktop Entry'].get('icon')=='folder-open'
" "$COPIE" 2>/dev/null; then
	ok "le fichier reste un .desktop valide, avec son Exec intact"
else
	non "le .desktop est cassé ou a perdu son Exec — le lanceur ne lancerait rien"
fi
#  LE DOCK. C'est le seul endroit qui porte un CHEMIN et pas un identifiant :
#  sans cette ligne, le dock resterait le dernier à montrer l'engrenage.
DOCK="$D/skel/.config/plank/dock1/launchers/02-files.dockitem"
if grep -q "Launcher=file://$D/local/thunar.desktop" "$DOCK"; then
	ok "le dock pointe sur la copie — Plank ne lit pas XDG_DATA_DIRS"
else
	non "le dock pointe encore ailleurs : $(sed -n 's/^Launcher=//p' "$DOCK")"
fi
#  Le nom n'ayant pas changé, les références par identifiant ne DOIVENT PAS
#  bouger : un banc qui accepterait une réécriture inutile laisserait passer
#  un sed trop gourmand.
if grep -q 'value="thunar.desktop"' "$D/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"; then
	ok "les favoris du menu sont laissés tels quels (le nom n'a pas changé)"
else
	non "les favoris ont été réécrits sans raison"
fi

# =============================================================================
titre "2. Le cas qu'on n'a JAMAIS pu vérifier : Debian a renommé le fichier"
# =============================================================================
#  Si c'est ça, alors les trois références en dur pointaient déjà dans le
#  vide — et un lanceur introuvable est exactement ce qui fait afficher un
#  engrenage générique. Cette hypothèse-là n'avait jamais été couverte.
D2="$BANC/renomme"; monte "$D2" "org.xfce.thunar.desktop" 1; joue "$D2"

if [[ -r "$D2/local/org.xfce.thunar.desktop" ]]; then
	ok "le fichier renommé est trouvé tout seul"
else
	non "le renommage n'est pas détecté : tout le correctif tomberait à l'eau"
fi
if grep -q "Launcher=file://$D2/local/org.xfce.thunar.desktop" \
	"$D2/skel/.config/plank/dock1/launchers/02-files.dockitem"; then
	ok "le dock suit le nouveau nom"
else
	non "le dock garde un lanceur mort"
fi
if grep -q 'value="org.xfce.thunar.desktop"' \
	"$D2/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"; then
	ok "les favoris du menu suivent"
else
	non "les favoris gardent un identifiant qui ne désigne plus rien"
fi
if grep -q '^inode/directory=org.xfce.thunar.desktop$' "$D2/etc/mimeapps.list"; then
	ok "double-cliquer un dossier ouvrira bien le gestionnaire"
else
	non "les applications par défaut gardent l'ancien identifiant : un dossier n'ouvrirait rien"
fi
#  ET SURTOUT PAS la fenêtre de réglages : elle s'appelle aussi « thunar ».
if ! grep -q 'Thunar Settings' "$D2/local/org.xfce.thunar.desktop"; then
	ok "la fenêtre de réglages (NoDisplay=true) a bien été écartée"
else
	non "c'est le .desktop des RÉGLAGES qui a été retenu — le dock ouvrirait la mauvaise fenêtre"
fi

# =============================================================================
titre "3. Un .desktop sans aucune ligne Icon="
# =============================================================================
#  Le sed n'a alors rien à remplacer. Ajouter la ligne à la FIN du fichier la
#  poserait dans la dernière action ([Desktop Action open-home]) — elle n'y
#  servirait à rien, et le défaut serait invisible.
D3="$BANC/sans-icone"; monte "$D3" "thunar.desktop" 0; joue "$D3"
C3="$D3/local/thunar.desktop"
if grep -q '^Icon=folder-open$' "$C3" 2>/dev/null; then
	ok "l'icône a été ajoutée"
else
	non "aucune icône ajoutée : le lanceur resterait sans image"
fi
if python3 -c "
import configparser,sys
c=configparser.ConfigParser(interpolation=None,strict=False)
c.read(sys.argv[1],encoding='utf-8')
assert c['Desktop Entry'].get('icon')=='folder-open', 'pas dans [Desktop Entry]'
" "$C3" 2>/dev/null; then
	ok "et elle est dans [Desktop Entry], pas égarée dans une action"
else
	non "la ligne existe mais hors du bon groupe : elle ne serait jamais lue"
fi

# =============================================================================
titre "4. Aucun gestionnaire de fichiers du tout : ça se DIT"
# =============================================================================
D4="$BANC/vide"
mkdir -p "$D4/apps" "$D4/local" "$D4/skel" "$D4/etc"
LEXOS_APPS="$D4/apps" LEXOS_APPS_LOCAL="$D4/local" LEXOS_SKEL="$D4/skel" \
	LEXOS_MIMEAPPS="$D4/etc/mimeapps.list" sh "$FRAGMENT" > "$D4/journal.txt" 2>&1
CODE=$?
if [[ "$CODE" -eq 0 ]]; then
	ok "le fragment ne fait pas échouer la construction quand Thunar manque"
else
	non "il sort en erreur ($CODE) : sous « set -e », toute l'ISO échouerait"
fi
if grep -q 'AUCUN .desktop de gestionnaire' "$D4/journal.txt"; then
	ok "et il le DIT dans le journal au lieu de se taire"
else
	non "silence complet : on découvrirait le lanceur mort sur une photo"
fi

# =============================================================================
titre "5. Le journal porte la preuve qui manquait depuis trois ISO"
# =============================================================================
#  On n'a jamais pu vérifier, depuis ce dépôt, quel nom d'icône Thunar
#  réclame vraiment. Le crochet l'écrit maintenant dans le journal de
#  construction : si la prochaine ISO montre encore un engrenage, la réponse
#  sera là au lieu d'une quatrième hypothèse.
if grep -q 'il réclamait : Icon=org.xfce.thunar' "$D/journal.txt"; then
	ok "le journal dit le nom d'icône que le vrai fichier réclame"
else
	non "le journal ne dit pas ce que Thunar demandait : on resterait aveugle"
fi
if grep -q 'gestionnaire de fichiers : thunar.desktop' "$D/journal.txt"; then
	ok "et le nom du fichier retenu"
else
	non "le journal ne dit pas quel fichier a été retenu"
fi

# =============================================================================
titre "6. QUATRIÈME SIGNALEMENT : plus aucune recherche par nom"
# =============================================================================
#  ALEX : « le gestionnaire de fichiers, c'est toujours le même problème » —
#  et, la fois d'avant, le détail qui explique tout : « quand on passe dessus
#  avec la souris, il change d'image ».
#
#  ═══ CE QUE « AU SURVOL » NOUS APPREND ═══
#  Le dock grossit l'icône au survol (130 % de 64 px, soit ~83 px). Une image
#  qui CHANGE entre 64 et 83, c'est une recherche PAR NOM qui ne rend pas la
#  même chose selon la taille : à 64 un dossier de taille fixe existe et
#  gagne ; à 83 aucun ne correspond, GTK bascule sur le « scalable », et si ce
#  SVG ne se charge pas la chaîne d'héritage continue jusqu'à un engrenage
#  générique. Au repos le bon dessin, au survol l'engrenage.
#
#  Trois correctifs ont parié que la recherche finirait par tomber juste :
#  les alias dans le thème, « apps/scalable » déclaré, puis « Icon=folder-open ».
#  Le quatrième ne parie plus — le .desktop reçoit un CHEMIN ABSOLU, et GTK
#  ouvre ce fichier-là quelle que soit la taille demandée.
#
#  Ce contrôle enchaîne les DEUX crochets, dans l'ordre de la construction
#  (0400 pose la copie, 0605 rend les PNG puis y écrit le chemin), et regarde
#  le résultat — pas le code.
HOOK_ICONES="$RACINE/config/hooks/normal/0605-lexos-icones.hook.chroot"
SVG_SOURCE="$RACINE/config/includes.chroot/usr/share/icons/LexOS/places/scalable/folder-open.svg"

if ! command -v rsvg-convert >/dev/null 2>&1; then
	non "rsvg-convert absent : la chaîne complète n'a PAS été éprouvée"
elif [[ ! -r "$HOOK_ICONES" || ! -r "$SVG_SOURCE" ]]; then
	non "crochet 0605 ou folder-open.svg introuvable — rien à enchaîner"
else
	CH="$BANC/chaine"
	mkdir -p "$CH/apps" "$CH/local" "$CH/skel" "$CH/etc" "$CH/theme/places/scalable"
	cp "$SVG_SOURCE" "$CH/theme/places/scalable/"
	printf '[Icon Theme]\nName=LexOS\nDirectories=places/scalable\n' > "$CH/theme/index.theme"
	{
		echo "[Desktop Entry]"; echo "Type=Application"; echo "Name=Thunar"
		echo "Icon=org.xfce.thunar"; echo "Exec=thunar %F"
	} > "$CH/apps/thunar.desktop"

	LEXOS_APPS="$CH/apps" LEXOS_APPS_LOCAL="$CH/local" LEXOS_SKEL="$CH/skel" \
		LEXOS_MIMEAPPS="$CH/etc/mimeapps.list" sh "$FRAGMENT" >/dev/null 2>&1
	LEXOS_ICONES="$CH/theme" LEXOS_RAPPORT_ICONES="$CH/rapport" \
		LEXOS_APPS_LOCAL="$CH/local" sh "$HOOK_ICONES" > "$CH/journal.txt" 2>&1

	ICO="$(sed -n 's/^Icon=//p' "$CH/local/thunar.desktop" 2>/dev/null | head -1)"
	if [[ "$ICO" == /* ]]; then
		ok "l'icône est un CHEMIN, plus un nom à chercher"
	else
		non "l'icône vaut encore « ${ICO:-rien} » : la recherche par nom reste en jeu"
	fi
	if [[ -n "$ICO" && -r "$ICO" ]]; then
		ok "…et le fichier désigné existe vraiment"
	else
		non "le chemin « $ICO » ne mène à rien — pire que le nom qu'il remplace"
	fi
	#  UN PNG, PAS UN SVG. C'est la leçon des PNG de secours du crochet 0605 :
	#  un SVG demande un greffon gdk-pixbuf, un PNG ne demande rien. Si la
	#  chaîne retombe sur le SVG alors que les PNG sont là, on a reintroduit
	#  la dependance qu'on voulait supprimer.
	if [[ "$ICO" == *.png ]]; then
		ok "c'est un PNG — aucun moteur de rendu à espérer au survol"
	else
		non "c'est « ${ICO##*.} » et non un PNG : le survol dépendrait encore d'un greffon"
	fi
	#  ET C'EST BIEN NOTRE DOSSIER ORANGE, pas un fichier quelconque.
	if python3 -c "import PIL" 2>/dev/null && [[ "$ICO" == *.png ]]; then
		ORANGE="$(python3 - "$ICO" <<'PY2'
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGBA")
L, H = im.size
px = im.load()
n = 0
for y in range(0, H, 3):
    for x in range(0, L, 3):
        r, g, b, a = px[x, y]
        if a > 100 and r > 150 and 40 < g < 170 and b < 100:
            n += 1
print(n)
PY2
)"
		if [[ "${ORANGE:-0}" -ge 200 ]]; then
			ok "le fichier porte bien le dossier orange ($ORANGE points relevés)"
		else
			non "seulement ${ORANGE:-0} points orange : ce n'est pas notre dossier"
		fi
	else
		non "Pillow absent : le contenu de l'icône n'a PAS été vérifié"
	fi
	#  Le journal doit le DIRE : sans cette ligne, un jour où le bloc ne
	#  trouverait aucun .desktop, personne ne s'en apercevrait.
	if grep -q 'gestionnaire de fichiers : 1 .desktop' "$CH/journal.txt"; then
		ok "le journal de construction nomme le fichier retenu"
	else
		non "le journal ne dit pas quelle icône a été posée : on resterait aveugle"
	fi

	#  ═══ LE REPLI ═══ Sans aucun PNG rendu (pas de rsvg-convert sur la
	#  machine de construction), le bloc doit se rabattre sur le SVG plutôt
	#  que de laisser un nom — un SVG qui marche parfois vaut mieux qu'un
	#  engrenage garanti.
	CH2="$BANC/chaine-sans-png"
	mkdir -p "$CH2/local" "$CH2/theme/places/scalable"
	cp "$SVG_SOURCE" "$CH2/theme/places/scalable/"
	printf '[Icon Theme]\nName=LexOS\nDirectories=places/scalable\n' > "$CH2/theme/index.theme"
	cp "$CH/local/thunar.desktop" "$CH2/local/"
	sed -i 's|^Icon=.*|Icon=org.xfce.thunar|' "$CH2/local/thunar.desktop"
	#  ON NEUTRALISE VRAIMENT LE RENDU. Premier jet : un dossier vide en tête
	#  de PATH — mais /usr/bin restait derrière, rsvg-convert répondait, des
	#  PNG étaient rendus, et ce contrôle passait au vert sans jamais éprouver
	#  le repli. Un banc vert pour la mauvaise raison est pire qu'un rouge.
	#  Un faux rsvg-convert qui ÉCHOUE le met en situation : la commande
	#  existe, aucun PNG ne sort.
	mkdir -p "$BANC/sansrendu"
	printf '#!/bin/sh\nexit 1\n' > "$BANC/sansrendu/rsvg-convert"
	chmod +x "$BANC/sansrendu/rsvg-convert"
	PATH="$BANC/sansrendu:$PATH" LEXOS_ICONES="$CH2/theme" \
		LEXOS_RAPPORT_ICONES="$CH2/rapport" LEXOS_APPS_LOCAL="$CH2/local" \
		sh "$HOOK_ICONES" >/dev/null 2>&1
	#  Et on vérifie que la mise en situation a bien pris : sans ça, on
	#  éprouverait de nouveau le beau temps.
	if ls "$CH2/theme/places"/[0-9]*/folder-open.png >/dev/null 2>&1; then
		non "des PNG ont quand même été rendus : le repli n'a PAS été mis à l'épreuve"
	else
		ok "aucun PNG rendu — le repli est bien mis à l'épreuve"
	fi
	ICO2="$(sed -n 's/^Icon=//p' "$CH2/local/thunar.desktop" | head -1)"
	if [[ "$ICO2" == /* && -r "$ICO2" && "$ICO2" == *.svg ]]; then
		ok "sans PNG, il se rabat sur le SVG — un chemin qui existe quand même"
	else
		non "sans PNG rendu, l'icône retombe sur « ${ICO2:-rien} » : le nom revient"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
