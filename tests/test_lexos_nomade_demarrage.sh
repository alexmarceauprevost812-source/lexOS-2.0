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
#    4. le nom de l'ISO nomade ne porte pas « -rtx5060 » ;
#    5. pas de barre du haut, et un vieux bureau.json ne la ramène pas ;
#    6. tools/maj-nomade-live.sh installe le bureau et efface « interface ».
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
for f in lexos-nomade.plymouth lexos-nomade.script yeux.png demon.png; do
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
		LEXOS_LIGHTDM_DIR="$B/r/lightdm" LEXOS_BRANDING="$B/r/brand" LEXOS_GRUB_DEFAULT_D="$B/r/grub.d" sh "$B/hook.sh" > "$B/journal" 2>&1
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
grep -qx "GRUB_DISABLE_OS_PROBER=true" "$B/r/grub.d/zz-lexos-nomade.cfg" 2>/dev/null \
	&& ok "GRUB : os-prober coupé sur la clé (menu caché, pas les systèmes du PC hôte)" || non "GRUB : os-prober encore actif sur la clé"

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
[ ! -e "$B/r/grub.d/zz-lexos-nomade.cfg" ] && ok "GRUB pro : os-prober intact (double démarrage)" || non "GRUB pro : os-prober coupé par erreur"

# =============================================================================
titre "4. Le nom de l'ISO nomade ne prétend pas embarquer le pilote RTX 5060"
for f in build.sh auto/config; do
	grep -qF 'LEXOS_VERSION="${LEXOS_VERSION%-rtx5060}"' "$RACINE/$f" && ok "$f coupe « -rtx5060 » pour la nomade" || non "$f garde « -rtx5060 »"
done
V="$(sh -c '. "$1/lexos.conf"; LEXOS_FLAVOUR=nomade; if [ "$LEXOS_FLAVOUR" = nomade ]; then LEXOS_VERSION="${LEXOS_VERSION%-rtx5060}"; fi; echo "$LEXOS_VERSION"' _ "$RACINE")"
case "$V" in *rtx5060*) non "version nomade : $V" ;; *) ok "version nomade : $V (pro garde $(sh -c '. "$1/lexos.conf"; echo "$LEXOS_VERSION"' _ "$RACINE"))" ;; esac

# =============================================================================
titre "5. Pas de barre du haut dans la nomade"
#  a. Le hook retire xfce4-panel des clients de la session (/etc/skel).
SESSION_SRC="$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml"
for SAVEUR in nomade pro; do
	preparer "$SAVEUR"
	mkdir -p "$B/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
	cp "$SESSION_SRC" "$B/skel/.config/xfce4/xfconf/xfce-perchannel-xml/"
	LEXOS_SKEL="$B/skel" jouer
	S="$(cat "$B/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml")"
	if [ "$SAVEUR" = nomade ]; then
		if ! grep -q 'value="xfce4-panel"' <<< "$S" && grep -q 'name="Count" *type="int" *value="4"' <<< "$S" \
		   && grep -q 'name="Client3_Command"' <<< "$S" && ! grep -q 'name="Client4_' <<< "$S"; then
			ok "nomade : xfce4-panel retiré de la session, clients renumérotés (4)"
		else
			non "nomade : session mal réécrite"
		fi
		python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$B/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" \
			&& ok "nomade : xfce4-session.xml reste un XML valide" || non "nomade : xfce4-session.xml cassé"
	else
		cmp -s "$SESSION_SRC" "$B/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" \
			&& ok "pro : session inchangée (la barre du haut reste)" || non "pro : la session a été modifiée"
	fi
done

#  b. lexos-barre-haut voit le bureau du Moteur PAR DÉFAUT de la nomade,
#     sans bureau.json — c'est ce qui laissait la barre allumée sur la clé.
BARRE="$INC/usr/bin/lexos-barre-haut"
FONCTION="$(sed -n '/^BUREAU_DIR=/,/^}/p' "$BARRE")"
moteur() {   # moteur <saveur> → 0 si lexos-barre-haut voit le Moteur choisi
	mkdir -p "$B/compte/.config/lexos"; rm -f "$B/compte/.config/lexos/bureau.json"
	echo "LEXOS_FLAVOUR=\"$1\"" > "$B/bc.conf"
	env HOME="$B/compte" XDG_CONFIG_HOME="$B/compte/.config" LEXOS_BUILD_CONF="$B/bc.conf" \
		LEXOS_BUREAU_DIR="$INC/usr/lib/lexos/bureau" bash -c "CONF=\"\$XDG_CONFIG_HOME/lexos\"; $FONCTION
moteur_choisi"
}
moteur nomade && ok "nomade sans bureau.json : la barre XFCE est éteinte (Moteur par défaut)" \
	|| non "nomade sans bureau.json : la barre XFCE resterait allumée"
moteur pro && non "pro sans bureau.json : la barre serait éteinte (le classique est son défaut)" \
	|| ok "pro sans bureau.json : la barre reste (bureau classique par défaut)"

#  c. Un « classique » resté dans bureau.json (sans le témoin d'un choix fait
#     à la main) n'allume plus la barre XFCE dans la nomade : le Moteur gagne.
mkdir -p "$B/compte/.config/lexos"
echo '{"mode": "classique", "interface": "moteur"}' > "$B/compte/.config/lexos/bureau.json"
echo 'LEXOS_FLAVOUR="nomade"' > "$B/bc.conf"
VU="$(env HOME="$B/compte" XDG_CONFIG_HOME="$B/compte/.config" LEXOS_BUILD_CONF="$B/bc.conf" \
	python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import reglages; r = reglages.lire(); print(r["mode"], r["interface"])' \
	"$INC/usr/lib/lexos/bureau")"
[ "$VU" = "moteur demon" ] && ok "nomade : un vieux « classique » / « moteur » est ignoré (Moteur + démon)" \
	|| non "nomade : bureau.json d'avant mal lu : « $VU »"

# =============================================================================
titre "6. tools/maj-nomade-live.sh : le démon reste le bureau"
#  Sur une fausse racine : le bureau s'installe, et le réglage « interface »
#  d'avant est effacé de chaque compte (sauvegardé d'abord, le reste gardé).
MAJ="$RACINE/tools/maj-nomade-live.sh"
R="$B/racine"; mkdir -p "$R/etc/lexos" "$R/home/alex/.config/lexos" "$R/home/vide"
echo 'LEXOS_FLAVOUR="nomade"' > "$R/etc/lexos/build.conf"
echo '{"interface": "moteur", "demon_theme": "spectre", "mode": "moteur"}' > "$R/home/alex/.config/lexos/bureau.json"
chmod 600 "$R/home/alex/.config/lexos/bureau.json"
if LEXOS_RACINE="$R" LEXOS_BUILD_CONF="$R/etc/lexos/build.conf" SUDO_USER='' bash "$MAJ" > "$B/maj.log" 2>&1; then
	ok "maj-nomade-live.sh passe sur une fausse racine"
else
	non "maj-nomade-live.sh échoue"; sed 's/^/      /' "$B/maj.log"
fi
cmp -s "$INC/usr/lib/lexos/bureau/web/demon.html" "$R/usr/lib/lexos/bureau/web/demon.html" \
	&& cmp -s "$INC/usr/lib/lexos/bureau/reglages.py" "$R/usr/lib/lexos/bureau/reglages.py" \
	&& ok "le bureau démon du dépôt est installé (demon.html, reglages.py)" || non "bureau non installé"
J="$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print("interface" in d, d.get("demon_theme"), d.get("mode"))' "$R/home/alex/.config/lexos/bureau.json" 2>&1)"
[ "$J" = "False spectre moteur" ] && ok "bureau.json : « interface » effacé, les autres réglages gardés" \
	|| non "bureau.json mal réécrit : $J"
[ "$(stat -c %a "$R/home/alex/.config/lexos/bureau.json")" = 600 ] && ok "bureau.json garde ses droits (600)" \
	|| non "bureau.json a changé de droits"
SAUVE="$(find "$R/var/backups" -maxdepth 1 -type d -name 'lexos-bureau-*' | sort | tail -n1)"
S="$(cat "$SAUVE/fichiers/home/alex/.config/lexos/bureau.json" 2>/dev/null)"
grep -q '"interface": "moteur"' <<< "$S" && ok "l'ancien bureau.json est sauvegardé dans $(basename "$SAUVE")" \
	|| non "pas de sauvegarde de bureau.json"
LEXOS_RACINE="$R" LEXOS_BUILD_CONF="$R/etc/lexos/build.conf" SUDO_USER='' bash "$MAJ" > "$B/maj2.log" 2>&1
grep -q "Déjà à jour" "$B/maj2.log" && ok "rejoué : « déjà à jour », rien de touché" || non "rejoué : il a encore changé quelque chose"
LEXOS_RACINE="$R" LEXOS_BUILD_CONF="$R/etc/lexos/build.conf" SUDO_USER='' bash "$MAJ" --annuler > "$B/maj3.log" 2>&1
grep -q '"interface": "moteur"' "$R/home/alex/.config/lexos/bureau.json" && [ ! -e "$R/usr/lib/lexos/bureau/reglages.py" ] \
	&& ok "--annuler remet l'ancien bureau.json et retire ce qui avait été créé" || non "--annuler incomplet"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" = 0 ]
