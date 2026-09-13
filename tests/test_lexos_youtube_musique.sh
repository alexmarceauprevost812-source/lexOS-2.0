#!/usr/bin/env bash
# =============================================================================
#  lexos-youtube-musique — une application, pas un lien au fond d'une page
# =============================================================================
#  Alex : « 1 youtube musique ». Un lien « YouTube Music ↗ » existait déjà au
#  fond de la page de lexOS_musique — donc un onglet, qui se perd. L'outil lui
#  donne une entrée de menu, une icône et une fenêtre.
#
#  ═══ CE QUE CE BANC MESURE ═══
#  « Fenêtre dédiée » est une promesse que tous les navigateurs ne tiennent
#  pas. On lui fabrique donc trois mondes — chromium présent, seulement
#  firefox, aucun navigateur — avec un PATH FERMÉ, et on relève l'argument
#  EXACT reçu dans chacun. Un lanceur qui promet une fenêtre et ouvre un
#  onglet sans le dire est le genre de petit mensonge qui use la confiance.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-youtube-musique"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-youtube-musique introuvable ou non exécutable"; exit 1; }

#  Un PATH refermé : seul ce qu'on y met existe. Sans ça, le chromium ou le
#  firefox du coureur entrerait dans la mesure et les trois mondes n'en
#  feraient plus qu'un.
MINI="$BANC/mini"; mkdir -p "$MINI"
for d in /usr/bin /bin; do
	[ -d "$d" ] || continue
	for c in "$d"/*; do
		[ -x "$c" ] || continue
		case "$(basename "$c")" in
			chromium|chromium-browser|google-chrome|google-chrome-stable|\
			brave-browser|microsoft-edge|vivaldi-stable|firefox|firefox-esr|xdg-open) continue ;;
		esac
		ln -sf "$c" "$MINI/$(basename "$c")" 2>/dev/null || true
	done
done

faux() { # faux <nom> — un navigateur qui écrit ce qu'on lui a passé
	printf '#!/bin/sh\nprintf "%%s\\n" "$0" "$@" > "$TRACE"\n' > "$BANC/$1"
	chmod +x "$BANC/$1"
}
TRACE="$BANC/recu"

lancer() { # lancer <PATH> [args…]
	rm -f "$TRACE"
	env -i HOME="$BANC" PATH="$1" TRACE="$TRACE" NO_COLOR=1 LC_ALL=C \
		bash "$OUTIL" "${@:2}" 2>&1
}

# =============================================================================
titre "1. Avec chromium : une VRAIE fenêtre d'application"
# =============================================================================
faux chromium
SORTIE="$(lancer "$BANC:$MINI")"
if [ -s "$TRACE" ]; then
	ok "chromium a bien été lancé"
	grep -qx -- "--app=https://music.youtube.com" "$TRACE" \
		&& ok "…en mode application (--app=), pas en onglet" \
		|| non "pas de « --app= » : ce serait un onglet, pas une fenêtre :\n$(cat "$TRACE")"
	grep -qx -- "--class=lexOS-youtube-musique" "$TRACE" \
		&& ok "…avec sa classe de fenêtre (le dock le reconnaît)" \
		|| non "aucune classe de fenêtre : le dock le confondrait avec le navigateur"
else
	non "chromium n'a pas été lancé du tout :\n$SORTIE"
fi

#  ET L'ADRESSE EST LA BONNE, EN UN SEUL MORCEAU. Un argument coupé en deux
#  enverrait le navigateur sur une page d'erreur — visible, mais après coup.
if [ -s "$TRACE" ]; then
	grep -q "music.youtube.com" "$TRACE" \
		&& ok "l'adresse passée est bien celle de YouTube Music" \
		|| non "l'adresse n'est pas dans ce que le navigateur a reçu"
fi

# =============================================================================
titre "2. Sans chromium, avec firefox : il LE DIT"
# =============================================================================
#  firefox n'a pas de mode application. Ouvrir quand même est le bon choix ;
#  laisser croire à une fenêtre dédiée ne l'est pas.
rm -f "$BANC/chromium"
faux firefox-esr
SORTIE="$(lancer "$BANC:$MINI")"
if [ -s "$TRACE" ]; then
	ok "firefox-esr a bien pris le relais"
	grep -qx -- "--new-window" "$TRACE" \
		&& ok "…avec --new-window (une fenêtre, pas un onglet de plus)" \
		|| non "firefox n'a pas reçu --new-window :\n$(cat "$TRACE")"
else
	non "firefox-esr n'a pas été lancé :\n$SORTIE"
fi
grep -qi "mode application" <<< "$SORTIE" \
	&& ok "…et l'outil annonce que ce ne sera pas une fenêtre d'application" \
	|| non "aucun mot sur la différence : l'utilisateur croirait à une fenêtre dédiée"

# =============================================================================
titre "3. Aucun navigateur : un refus clair, pas un silence"
# =============================================================================
rm -f "$BANC/firefox-esr"
SORTIE="$(lancer "$BANC:$MINI")"
CODE=$?
grep -qi "aucun navigateur" <<< "$SORTIE" \
	&& ok "il dit qu'aucun navigateur n'est installé" \
	|| non "aucun message quand rien n'est installé :\n$SORTIE"
grep -qi "logitheque\|logithèque" <<< "$SORTIE" \
	&& ok "…et il dit quoi faire (la Logithèque)" \
	|| non "il constate la panne sans donner la sortie"
[ "$CODE" -ne 0 ] \
	&& ok "…avec un code de sortie non nul" \
	|| non "code de sortie 0 alors que rien n'a été ouvert"

# =============================================================================
titre "4. L'aide, et un argument inconnu"
# =============================================================================
SORTIE="$(lancer "$BANC:$MINI" --aide)"
grep -qi "service en ligne" <<< "$SORTIE" \
	&& ok "l'aide dit que c'est un service en ligne (et non local comme lexos musique)" \
	|| non "l'aide ne dit pas que les écoutes partent chez Google"
grep -qi "lexos musique" <<< "$SORTIE" \
	&& ok "…et renvoie au lecteur local pour qui ne veut rien envoyer" \
	|| non "l'aide ne propose pas l'alternative locale"

SORTIE="$(lancer "$BANC:$MINI" --nawak)"
grep -qi "argument inconnu" <<< "$SORTIE" \
	&& ok "un argument inconnu est refusé au lieu d'être ignoré" \
	|| non "« --nawak » passe sans un mot"

# =============================================================================
titre "5. Le lanceur, l'icône et le branchement"
# =============================================================================
HOOK="$RACINE/config/hooks/normal/0431-lexos-youtube-musique.hook.chroot"
[ -x "$HOOK" ] && ok "le hook 0431 existe et est exécutable" \
	|| non "le hook 0431 manque : aucune entrée de menu ne serait posée"

SVG="$RACINE/branding/icon-youtube-musique.svg"
[ -r "$SVG" ] && ok "l'icône existe dans branding/" \
	|| non "branding/icon-youtube-musique.svg manque — icône générique"
if command -v xmllint >/dev/null 2>&1; then
	xmllint --noout "$SVG" 2>/dev/null \
		&& ok "…et c'est du XML valide (la CI le refuserait sinon)" \
		|| non "l'icône n'est pas un SVG valide"
fi

#  LE DESSIN NE DOIT PAS ÊTRE CELUI DE LA MARQUE. Le dépôt s'est donné cette
#  règle pour toutes ses icônes : on ouvre un service, on n'imite pas son logo.
if grep -qiE '#ff0000|#f00\b|rouge de youtube' "$SVG"; then
	non "l'icône emprunte le rouge de la marque"
else
	ok "l'icône est un dessin LexOS, sans couleur empruntée à la marque"
fi

DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
grep -q 'youtube-musique|ytmusic' "$DISPATCH" \
	&& ok "« lexos youtube-musique » est branché dans le dispatcheur" \
	|| non "le dispatcheur ne connaît pas « youtube-musique »"
grep -q 'youtube-musique' <<< "$(sed -n '/^aide()/,/^}/p' "$DISPATCH")" \
	|| grep -q 'youtube-musique.*R}     ' "$DISPATCH" \
	&& ok "…et il figure dans l'aide" \
	|| non "l'outil n'apparaît nulle part dans l'aide"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
