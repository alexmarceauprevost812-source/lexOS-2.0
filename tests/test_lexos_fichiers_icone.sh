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

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
