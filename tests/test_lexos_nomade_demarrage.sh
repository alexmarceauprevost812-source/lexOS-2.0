#!/usr/bin/env bash
# =============================================================================
#  Banc : le démarrage de la saveur nomade (hook 0415, thème lexos-nomade)
# =============================================================================
#  Plymouth → LightDM → bureau démon : les mêmes yeux rouges, et rien de
#  lourd dans l'initramfs. On vérifie :
#    1. le thème lexos-nomade : trois fichiers, une seule petite image, et
#       un script qui n'appelle QUE des fonctions du module (la liste gelée
#       de test_lexos_plymouth.sh), sans Math.* ni « for » ni GetTime, avec
#       l'invite de la phrase secrète (disque chiffré) ;
#    2. le hook 0415, saveur nomade : thème désigné, thème « lexos » retiré,
#       fond de connexion posé, vidéos de lexos-intro retirées ;
#    3. le hook 0415, saveur pro : thème, fond et vidéo nomade retirés,
#       rien d'autre touché ;
#    4. le nom de l'ISO nomade ne porte pas « -rtx5060 ».
#  Aucun texte n'est passé à « grep -q » par un tuyau : sous pipefail, le
#  tuyau cassé ferait mentir un contrôle (règle de la CI).
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INC="$RACINE/config/includes.chroot"
THEME="$INC/usr/share/plymouth/themes/lexos-nomade"
HOOK="$RACINE/config/hooks/normal/0415-lexos-nomade-demarrage.hook.chroot"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. Le thème Plymouth lexos-nomade"
for f in lexos-nomade.plymouth lexos-nomade.script yeux.png; do
	[ -s "$THEME/$f" ] && ok "$f présent" || non "$f absent"
done
TAILLE="$(du -cb "$THEME"/* | tail -n1 | cut -f1)"
[ "$TAILLE" -lt 65536 ] && ok "thème entier : $TAILLE octets (< 64 Kio dans l'initramfs)" || non "thème trop lourd : $TAILLE octets"
PLY="$(cat "$THEME/lexos-nomade.plymouth")"
grep -q '^ModuleName=script$' <<< "$PLY" && grep -q '^ScriptFile=/usr/share/plymouth/themes/lexos-nomade/lexos-nomade.script$' <<< "$PLY" \
	&& ok ".plymouth : module script, chemin du script juste" || non ".plymouth mal formé"
API="SetRefreshRate SetRefreshFunction SetBootProgressFunction SetRootMountedFunction
SetKeyboardInputFunction SetUpdateStatusFunction SetDisplayNormalFunction
SetDisplayPasswordFunction SetDisplayQuestionFunction SetDisplayPromptFunction
SetDisplayMessageFunction SetDisplayHotplugFunction SetHideMessageFunction
SetMessageFunction SetQuitFunction SetSystemUpdateFunction SetValidateInputFunction
GetMode GetCapslockState"
CODE="$(sed 's|//.*$||' "$THEME/lexos-nomade.script")"
APPELS="$(grep -oE 'Plymouth\.[A-Za-z_]+' <<< "$CODE" | sed 's/^Plymouth\.//' | sort -u)"
INCONNUS=""
for f in $APPELS; do
	grep -qxF "$f" <<< "$(printf '%s\n' $API)" || INCONNUS="$INCONNUS $f"
done
[ -z "$INCONNUS" ] && ok "appels Plymouth.* tous connus du module :$(printf ' %s' $APPELS)" || non "fonctions inconnues :$INCONNUS"
grep -qE 'Math\.|GetTime|\bfor *\(|%' <<< "$CODE" && non "Math.*, GetTime, « for » ou « % » dans le script" \
	|| ok "pas de Math.*, GetTime, « for » ni « % » (noms que l'interpréteur avalerait en silence)"
grep -q 'SetDisplayPasswordFunction' <<< "$CODE" && ok "l'invite de la phrase secrète est dessinée (disque chiffré)" \
	|| non "aucune invite de phrase secrète : un disque chiffré attendrait sur un écran noir"
grep -q 'rafraichissements = rafraichissements + 1' <<< "$CODE" && ok "la respiration avance à chaque image" || non "compteur figé"

# =============================================================================
titre "2. Hook 0415, saveur nomade"
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
preparer() {   # preparer <saveur>
	rm -rf "$B/r"; mkdir -p "$B/r/etc/lexos" "$B/r/lightdm" "$B/r/brand" "$B/r/ply" "$B/r/web" "$B/r/nomade" "$B/bin"
	echo "LEXOS_FLAVOUR=\"$1\"" > "$B/r/etc/lexos/build.conf"
	cp -a "$THEME" "$B/r/ply/lexos-nomade"
	mkdir -p "$B/r/ply/lexos"; : > "$B/r/ply/lexos/lexos.script"
	cp "$INC/usr/share/lexos/nomade/fond-connexion-nomade.png" "$B/r/nomade/"
	cp "$INC/usr/lib/lexos/bureau/web/demarrage-flammes.webm" "$B/r/web/"
	printf '[greeter]\nbackground=/usr/share/lexos/branding/fond-connexion.png\ntheme-name=X\n' > "$B/r/lightdm/lightdm-gtk-greeter.conf"
	: > "$B/r/brand/apres-connexion-16-9.mp4"; : > "$B/r/brand/apres-connexion-16-9-courte.mp4"
	printf '#!/bin/sh\necho "$*" > "%s/theme-choisi"\n' "$B" > "$B/bin/plymouth-set-default-theme"
	chmod +x "$B/bin/plymouth-set-default-theme"; rm -f "$B/theme-choisi"
	sed "s#/etc/lexos/build.conf#$B/r/etc/lexos/build.conf#g" "$HOOK" > "$B/hook.sh"
}
jouer() {
	env PATH="$B/bin:$PATH" LEXOS_PLYMOUTH_NOMADE="$B/r/ply/lexos-nomade" LEXOS_PLYMOUTH_LEXOS="$B/r/ply/lexos" \
		LEXOS_FOND_NOMADE="$B/r/nomade/fond-connexion-nomade.png" LEXOS_VIDEO_NOMADE="$B/r/web/demarrage-flammes.webm" \
		LEXOS_LIGHTDM_DIR="$B/r/lightdm" LEXOS_BRANDING="$B/r/brand" sh "$B/hook.sh" > "$B/journal" 2>&1
}
preparer nomade
jouer && ok "le hook passe" || { non "le hook échoue"; sed 's/^/      /' "$B/journal"; }
[ "$(cat "$B/theme-choisi" 2>/dev/null)" = lexos-nomade ] && ok "Plymouth : lexos-nomade désigné" || non "lexos-nomade non désigné"
[ ! -d "$B/r/ply/lexos" ] && ok "thème « lexos » (≈ 20 Mo d'entrée en matière) retiré" || non "thème « lexos » encore là"
grep -qx "background=$B/r/nomade/fond-connexion-nomade.png" "$B/r/lightdm/lightdm-gtk-greeter.conf" \
	&& ok "LightDM : fond noir aux yeux rouges" || non "LightDM : fond inchangé"
grep -qx 'theme-name=X' "$B/r/lightdm/lightdm-gtk-greeter.conf" && ok "LightDM : le reste de la configuration intact" || non "LightDM : configuration abîmée"
[ ! -e "$B/r/brand/apres-connexion-16-9.mp4" ] && [ ! -e "$B/r/brand/apres-connexion-16-9-courte.mp4" ] \
	&& ok "vidéos de lexos-intro retirées (le bureau démon joue la sienne)" || non "deux vidéos coup sur coup"
[ -s "$B/r/web/demarrage-flammes.webm" ] && ok "vidéo du bureau démon gardée" || non "vidéo du bureau démon retirée"

#  Si Plymouth refuse le thème, « lexos » doit RESTER : c'est lui qui servira.
preparer nomade
printf '#!/bin/sh\nexit 1\n' > "$B/bin/plymouth-set-default-theme"
jouer
[ -d "$B/r/ply/lexos" ] && ok "thème refusé : « lexos » gardé en secours" || non "thème refusé ET « lexos » retiré : écran de démarrage vide"

# =============================================================================
titre "3. Hook 0415, saveur pro : rien de la nomade"
preparer pro
jouer && ok "le hook passe" || non "le hook échoue"
[ ! -e "$B/theme-choisi" ] && ok "thème Plymouth non touché" || non "le thème a été changé pour pro"
[ -d "$B/r/ply/lexos" ] && ok "thème « lexos » gardé" || non "thème « lexos » retiré pour pro"
[ ! -d "$B/r/ply/lexos-nomade" ] && [ ! -e "$B/r/nomade/fond-connexion-nomade.png" ] && [ ! -e "$B/r/web/demarrage-flammes.webm" ] \
	&& ok "thème, fond et vidéo nomade retirés de l'image" || non "des fichiers nomade restent dans l'image pro"
grep -qx 'background=/usr/share/lexos/branding/fond-connexion.png' "$B/r/lightdm/lightdm-gtk-greeter.conf" \
	&& ok "LightDM pro inchangé" || non "LightDM pro modifié"
[ -e "$B/r/brand/apres-connexion-16-9.mp4" ] && ok "vidéo de lexos-intro gardée pour pro" || non "vidéo de lexos-intro retirée pour pro"

# =============================================================================
titre "4. Le nom de l'ISO nomade ne prétend pas embarquer le pilote RTX 5060"
for f in build.sh auto/config; do
	grep -qF 'LEXOS_VERSION="${LEXOS_VERSION%-rtx5060}"' "$RACINE/$f" && ok "$f coupe « -rtx5060 » pour la nomade" || non "$f garde « -rtx5060 »"
done
V="$(sh -c '. "$1/lexos.conf"; LEXOS_FLAVOUR=nomade; if [ "$LEXOS_FLAVOUR" = nomade ]; then LEXOS_VERSION="${LEXOS_VERSION%-rtx5060}"; fi; echo "$LEXOS_VERSION"' _ "$RACINE")"
case "$V" in *rtx5060*) non "version nomade : $V" ;; *) ok "version nomade : $V (pro garde $(sh -c '. "$1/lexos.conf"; echo "$LEXOS_VERSION"' _ "$RACINE"))" ;; esac

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" = 0 ]
