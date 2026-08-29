#!/usr/bin/env bash
# =============================================================================
#  Éprouver le fond d'écran OFFICIEL — le démon, plutôt que le rendu SVG
# =============================================================================
#  ALEX, après avoir envoyé le logo TI·LEX·AL : « pour la prochaine ios sa
#  va etre le fond ecren officiel » — puis, en deux messages qui précisent
#  le premier : « mais toute noir » et « avec le demon ».
#
#  wallpaper-demon.png (le démon sur fond noir) EXISTAIT déjà dans le hook
#  0300 — c'était déjà l'une des variantes du sélecteur Paramètres → Bureau
#  LexOS. Ce qui manquait : que ce soit CELUI-LÀ, et pas le rendu de
#  branding/wallpaper.svg, que lexos-firstrun pose au premier lancement et
#  que le repli XFCE plus bas dans le même hook recopie. Trois lecteurs de
#  « wallpaper.png », un seul endroit à corriger : ce que ce fichier
#  contient.
#
#  UN LIEN SYMBOLIQUE, PAS UNE COPIE. settings.py (FONDS) garde deux noms,
#  « defaut » et « demon », qui pointent chacun vers son propre fichier sur
#  le disque. Une copie de wallpaper-demon.png vers wallpaper.png les
#  rendrait identiques AUJOURD'HUI, mais un correctif qui ne toucherait que
#  l'un des deux les ferait diverger EN SILENCE demain. Le lien symbolique
#  rend cette divergence impossible par construction.
#
#  CE QU'ON ÉPROUVE, ET CE QU'ON NE PEUT PAS. On n'a pas de serveur X ni de
#  vraie chroot Debian ici — mais on a un VRAI ImageMagick (installé dans ce
#  bac), donc on fait tourner le VRAI extrait du hook, avec un VRAI logo
#  (minuscule) et une VRAIE composition. Ce banc ne relit pas le script :
#  il l'exécute.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
FIRSTRUN="$RACINE/config/includes.chroot/usr/bin/lexos-firstrun"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$HOOK" ] || { non "hook 0300 introuvable"; echo; exit 1; }

# =============================================================================
#  Extraction du bloc « wallpaper-demon devient l'officiel », par repère —
#  pas par numéro de ligne, qui bougerait au premier correctif voisin.
# =============================================================================
extrait() {
	awk '/^if \[ -r "\$BRAND\/logo-ti-lex-al-icon.png" \] && have convert; then$/{f=1}
	     f{print} f && /^fi$/{exit}' "$HOOK"
}
BLOC="$(extrait)"
[ -n "$BLOC" ] || { non "extraction ratée : le bloc du démon officiel n'a pas été trouvé dans le hook"; echo; exit 1; }
echo "$BLOC" | grep -q 'ln -sf wallpaper-demon.png' \
	|| { non "extraction ratée : le lien symbolique n'est pas dans le bloc extrait — repère déplacé ?"; echo; exit 1; }

# =============================================================================
titre "1. Le vrai extrait, avec un vrai ImageMagick — wallpaper.png devient le démon"
# =============================================================================
prepare() {
	rm -rf "${BANC:?}/racine"
	mkdir -p "$BANC/racine/brand" "$BANC/racine/bg"
	#  Un vrai (minuscule) PNG, pas un fichier vide : « convert » sur un
	#  fichier vide échouerait, et le banc ne prouverait rien.
	convert -size 20x20 xc:orange "$BANC/racine/brand/logo-ti-lex-al-icon.png"
}
lance() {
	BRAND="$BANC/racine/brand" BG="$BANC/racine/bg" \
		sh -c '
			have() { command -v "$1" >/dev/null 2>&1; }
			'"$BLOC"'
		' 2>&1
}

prepare
SORTIE="$(lance)"
DEMON="$BANC/racine/bg/wallpaper-demon.png"
OFFICIEL="$BANC/racine/bg/wallpaper.png"

[ -s "$DEMON" ] \
	&& ok "wallpaper-demon.png est composé (un vrai fichier, pas vide)" \
	|| non "wallpaper-demon.png n'existe pas ou est vide — sortie : $SORTIE"

[ -L "$OFFICIEL" ] \
	&& ok "wallpaper.png est un LIEN SYMBOLIQUE (pas une copie qui pourrait diverger)" \
	|| non "wallpaper.png n'est pas un lien symbolique — $(ls -la "$OFFICIEL" 2>&1)"

CIBLE="$(readlink "$OFFICIEL" 2>/dev/null)"
[ "$CIBLE" = "wallpaper-demon.png" ] \
	&& ok "…et il pointe précisément sur wallpaper-demon.png" \
	|| non "wallpaper.png pointe sur « $CIBLE » au lieu de wallpaper-demon.png"

#  Le lien SUIVI doit donner EXACTEMENT le même contenu — pas une copie qui
#  aurait pu partir d'une source différente.
if [ -r "$OFFICIEL" ] && cmp -s "$OFFICIEL" "$DEMON"; then
	ok "le contenu lu à travers le lien est identique, octet pour octet, au démon"
else
	non "le contenu de wallpaper.png (suivi) diffère de wallpaper-demon.png"
fi

# =============================================================================
titre "2. Sans logo ou sans ImageMagick : ni crash, ni lien fantôme"
# =============================================================================
prepare
rm -f "$BANC/racine/brand/logo-ti-lex-al-icon.png"
SORTIE="$(lance)"
[ ! -e "$BANC/racine/bg/wallpaper-demon.png" ] \
	&& ok "sans logo source, rien n'est composé (pas de fichier fantôme)" \
	|| non "un wallpaper-demon.png est apparu sans logo source"
[ ! -e "$BANC/racine/bg/wallpaper.png" ] \
	&& ok "…et wallpaper.png n'est pas touché — pas de lien vers un fichier qui n'existe pas" \
	|| non "wallpaper.png a été créé alors qu'il n'y avait rien à composer"

# =============================================================================
titre "3. lexos-firstrun : le commentaire ne raconte plus l'ancienne règle"
# =============================================================================
#  Le piège exact que ce correctif corrige : un commentaire qui continuerait
#  à dire « le démon n'est qu'une des variantes, pas le défaut » alors que
#  c'est maintenant FAUX induirait le prochain lecteur en erreur.
grep -q "n'est qu'une des quatre" "$FIRSTRUN" \
	&& non "lexos-firstrun affirme encore que le démon N'EST PAS le défaut — commentaire perimé" \
	|| ok "lexos-firstrun ne prétend plus que le démon n'est qu'une variante parmi d'autres"
grep -q 'WALL="/usr/share/backgrounds/lexos/wallpaper.png"' "$FIRSTRUN" \
	&& ok "lexos-firstrun continue de lire wallpaper.png — rien à changer là, le lien suffit" \
	|| non "lexos-firstrun ne pointe plus sur wallpaper.png — le lien symbolique ne servirait à rien"

# =============================================================================
titre "4. Les mutations — un banc qui ne peut pas échouer ne prouve rien"
# =============================================================================
mutation() { # mutation <libelle> <fichier> <sed>
	cp "$2" "$BANC/sauve"
	sed -i "$3" "$2"
	if bash "$0" --enfant >/dev/null 2>&1; then
		non "MUTATION NON DÉTECTÉE : $1"
	else
		ok "mutation détectée : $1"
	fi
	cp "$BANC/sauve" "$2"
}

if [ "${1:-}" != "--enfant" ]; then
	mutation "le lien symbolique du démon officiel est retiré" "$HOOK" \
		's|^\t\tln -sf wallpaper-demon.png "\$BG/wallpaper.png" \\$|\t\ttrue \\|'
	mutation "le vieux commentaire de lexos-firstrun revient" "$FIRSTRUN" \
		's|#  wallpaper.png EST le fond de marque officiel\. ALEX|#  n'"'"'est qu'"'"'une des quatre variantes — wallpaper.png EST le fond de marque officiel. ALEX|'
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
