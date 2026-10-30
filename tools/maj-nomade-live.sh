#!/usr/bin/env bash
# =============================================================================
#  maj-nomade-live.sh — essayer le nouveau bureau démon sur une clé nomade
#  DÉJÀ INSTALLÉE, sans reconstruire l'ISO
# =============================================================================
#  ALEX : tester les changements directement depuis le terminal de LexOS.
#  Depuis une copie du dépôt (la branche à essayer) :
#
#      sudo bash tools/maj-nomade-live.sh            installer
#      sudo bash tools/maj-nomade-live.sh --annuler  revenir à la sauvegarde
#
#  CE QU'IL FAIT, ET RIEN D'AUTRE :
#    1. refuse si ce n'est pas une LexOS « nomade » (/etc/lexos/build.conf) ;
#    2. compare, fichier par fichier, une LISTE FERMÉE de fichiers que l'image
#       livre pour le bureau démon (le dossier /usr/lib/lexos/bureau, ses deux
#       lanceurs, lexos-barre-haut et leurs autostarts) avec ceux du dépôt ;
#    3. sauvegarde ceux qu'il va remplacer dans /var/backups/lexos-bureau-<date>/
#       (et note ceux qu'il crée), puis les installe ;
#    4. retire la barre du haut XFCE (xfce4-panel) de la session de /etc/skel
#       ET de chaque compte de /home — comme le hook 0415 le fait pour l'image —
#       et la ferme tout de suite dans la session ouverte de celui qui lance ;
#    5. relance le bureau démon de celui qui lance (lexos-bureau relancer).
#  Rejoué sans rien de neuf, il ne fait rien (« déjà à jour »).
# =============================================================================
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPOT="$(cd "$ICI/.." && pwd)"
SRC="$DEPOT/config/includes.chroot"
CONF="${LEXOS_BUILD_CONF:-/etc/lexos/build.conf}"
RACINE="${LEXOS_RACINE:-}"                 # « / » ; surchargeable pour un banc
SAUVEGARDES="${RACINE}/var/backups"
SESSION_REL=".config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml"

dire()  { printf '\033[38;5;208m[lexos]\033[0m %s\n' "$*"; }
mourir(){ printf '\033[31m[lexos] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || [ -n "$RACINE" ] || mourir "À lancer avec sudo : sudo bash $0 ${1:-}"
grep -qs '^LEXOS_FLAVOUR="\{0,1\}nomade"\{0,1\}$' "$CONF" \
	|| mourir "Ce n'est pas une LexOS « nomade » ($CONF) — rien n'a été touché."
[ -d "$SRC/usr/lib/lexos/bureau" ] || mourir "Lance-moi depuis une copie du dépôt LexOS (introuvable : $SRC)."

#  LA LISTE FERMÉE : seulement ce que l'image livre pour ces fonctions-là.
fichiers_du_depot() {
	( cd "$SRC" && find usr/lib/lexos/bureau -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sort )
	for f in usr/bin/lexos-bureau usr/bin/lexos-barre-haut \
	         etc/xdg/autostart/lexos-bureau.desktop etc/xdg/autostart/lexos-barre-haut.desktop; do
		[ -f "$SRC/$f" ] && echo "$f"
	done
}

#  L'environnement de la session graphique d'un compte (DISPLAY, D-Bus…),
#  lu chez son xfce4-session : sudo l'a effacé, et sans lui rien ne s'adresse
#  à son bureau.
env_session() {   # env_session <compte> → lignes VAR=valeur
	local pid
	pid="$(pgrep -u "$1" -x xfce4-session | head -n1)"
	[ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 1
	tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)='
}
en_session() {    # en_session <compte> <commande…>
	local compte="$1" vars
	shift
	vars="$(env_session "$compte")" || return 1
	# shellcheck disable=SC2046
	sudo -u "$compte" env $(printf '%s\n' "$vars" | tr '\n' ' ') HOME="$(getent passwd "$compte" | cut -d: -f6)" "$@"
}

relancer_bureau() {
	local compte="${SUDO_USER:-}"
	[ -n "$compte" ] && [ "$compte" != root ] || { dire "Pas de compte à relancer (lance-moi avec sudo depuis ta session)."; return; }
	if en_session "$compte" xfce4-panel --quit >/dev/null 2>&1; then
		dire "Barre du haut fermée dans ta session."
	fi
	if en_session "$compte" /usr/bin/lexos-bureau relancer >/dev/null 2>&1; then
		dire "Bureau démon relancé — quelques secondes."
	else
		dire "Ta session n'est pas joignable d'ici : déconnecte-toi puis reconnecte-toi pour voir le nouveau bureau."
	fi
}

# --- --annuler -----------------------------------------------------------------
if [ "${1:-}" = "--annuler" ]; then
	DERNIERE="$(find "$SAUVEGARDES" -maxdepth 1 -type d -name 'lexos-bureau-*' ! -name '*.annulee' 2>/dev/null | sort | tail -n1)"
	[ -n "$DERNIERE" ] || mourir "Aucune sauvegarde dans $SAUVEGARDES — rien à annuler."
	dire "Retour à la sauvegarde $DERNIERE"
	if [ -d "$DERNIERE/fichiers" ]; then
		( cd "$DERNIERE/fichiers" && find . -type f | sed 's|^\./||' ) | while IFS= read -r f; do
			install -D -m "$(stat -c %a "$DERNIERE/fichiers/$f")" "$DERNIERE/fichiers/$f" "$RACINE/$f"
		done
	fi
	if [ -r "$DERNIERE/nouveaux" ]; then
		while IFS= read -r f; do
			[ -n "$f" ] && rm -f "$RACINE/$f"
		done < "$DERNIERE/nouveaux"
	fi
	mv "$DERNIERE" "$DERNIERE.annulee"
	dire "Fait. (La sauvegarde reste dans $DERNIERE.annulee.)"
	relancer_bureau
	exit 0
fi

# --- Installer -------------------------------------------------------------------
SAUVE="$SAUVEGARDES/lexos-bureau-$(date +%Y%m%d-%H%M%S)"
CHANGES=0
sauver() {   # sauver <chemin relatif à la racine> — avant de le remplacer
	if [ -e "$RACINE/$1" ]; then
		install -D -m "$(stat -c %a "$RACINE/$1")" "$RACINE/$1" "$SAUVE/fichiers/$1"
	else
		mkdir -p "$SAUVE"; echo "$1" >> "$SAUVE/nouveaux"
	fi
}

while IFS= read -r f; do
	if ! cmp -s "$SRC/$f" "$RACINE/$f"; then
		sauver "$f"
		case "$f" in
			usr/bin/*) MODE=755 ;;
			*) MODE=644 ;;
		esac
		install -D -m "$MODE" "$SRC/$f" "$RACINE/$f"
		dire "mis à jour : /$f"
		CHANGES=$((CHANGES + 1))
	fi
done < <(fichiers_du_depot)
rm -rf "$RACINE/usr/lib/lexos/bureau/__pycache__"

#  La barre du haut hors de la session : /etc/skel ET les comptes existants.
#  Même réécriture que le hook 0415 ; un fichier qui ne la lance déjà plus
#  n'est pas touché.
retirer_barre() {   # retirer_barre <xfce4-session.xml> <chemin relatif pour la sauvegarde>
	[ -f "$1" ] && grep -q 'value="xfce4-panel"' "$1" || return 0
	sauver "$2"
	if python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
blocs = re.findall(r'(\n[ \t]*<property name="Client(\d+)_Command".*?(?=\n[ \t]*<property name="Client\d+_Command"|\n[ \t]*</property>\s*\n[ \t]*</property>))', s, re.S)
garder = [b for b, n in blocs if 'value="xfce4-panel"' not in b]
if len(garder) != len(blocs) - 1:
    sys.exit(1)
debut = s.index(blocs[0][0]); fin = s.index(blocs[-1][0]) + len(blocs[-1][0])
neufs = [re.sub(r'Client\d+_', f"Client{i}_", b) for i, b in enumerate(garder)]
s = s[:debut] + "".join(neufs) + s[fin:]
s = re.sub(r'(<property name="Count"\s+type="int"\s+value=")\d+(")', rf"\g<1>{len(garder)}\2", s, count=1)
open(p, "w", encoding="utf-8").write(s)
PY
	then
		dire "barre du haut retirée de la session : $1"
		CHANGES=$((CHANGES + 1))
	else
		dire "!! $1 : forme inattendue, laissé tel quel (lexos-barre-haut fermera la barre à chaque session)"
	fi
}
retirer_barre "$RACINE/etc/skel/$SESSION_REL" "etc/skel/$SESSION_REL"
for MAISON in "$RACINE"/home/*; do
	[ -d "$MAISON" ] || continue
	retirer_barre "$MAISON/$SESSION_REL" "${MAISON#"$RACINE"/}/$SESSION_REL"
done

if [ "$CHANGES" = 0 ]; then
	dire "Déjà à jour — rien n'a été changé."
	exit 0
fi
dire "Sauvegarde de ce qui a été remplacé : $SAUVE"
relancer_bureau
dire "Pour revenir en arrière : sudo bash $0 --annuler"
