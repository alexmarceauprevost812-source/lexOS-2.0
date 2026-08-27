#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-app-settings — les réglages de LA FENÊTRE, pas de l'ordinateur
# =============================================================================
#  Alex : « le bouton vert doit ouvrir les paramètres de la fenêtre ouverte,
#  pas les paramètres de l'ordinateur ». lexos-app-settings lit la fenêtre au
#  premier plan (xdotool) et lance les VRAIES préférences de l'application —
#  jamais une commande inventée : xfce4-terminal --preferences et
#  thunar-settings sont vérifiés dans leurs propres manuels avant d'être
#  écrits ici. Ce banc rejoue chaque fenêtre reconnue, la casse mêlée, les
#  deux façons d'échouer proprement (fenêtre inconnue, xdotool absent), et
#  vérifie qu'aucune n'atterrit ailleurs que sur le repli déclaré :
#  lexos-settings, jamais un plantage ni un silence.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-app-settings"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-app-settings introuvable ou non exécutable"; exit 1; }

FAUXBIN="$BANC/bin"
CLASSE_F="$BANC/classe"
APPELE_F="$BANC/appele"

# --- Fabrique un faux xdotool qui rend la classe voulue --------------------
#  Vide ou absent -> aucune fenêtre active (comportement d'xdotool quand
#  _NET_ACTIVE_WINDOW ne pointe sur rien).
pose_classe() {
	mkdir -p "$FAUXBIN"
	printf '%s' "${1:-}" > "$CLASSE_F"
	cat > "$FAUXBIN/xdotool" <<EOF
#!/bin/sh
if [ "\$1" = "getactivewindow" ] && [ "\$2" = "getwindowclassname" ]; then
	cat "$CLASSE_F" 2>/dev/null
	[ -s "$CLASSE_F" ]
	exit \$?
fi
exit 1
EOF
	chmod +x "$FAUXBIN/xdotool"
}

# --- Un faux exécutable qui note qu'on l'a appelé, avec ses arguments ------
pose_faux() { # pose_faux <nom>
	mkdir -p "$FAUXBIN"
	cat > "$FAUXBIN/$1" <<EOF
#!/bin/sh
printf '%s %s\n' "$1" "\$*" > "$APPELE_F"
exit 0
EOF
	chmod +x "$FAUXBIN/$1"
}

retire_faux() { rm -f "$FAUXBIN/$1"; } # simule un binaire absent du système

lance() { # lance -> ce que APPELE_F contient après un run (vidé avant)
	rm -f "$APPELE_F"
	PATH="$FAUXBIN:$PATH" "$OUTIL" >/dev/null 2>&1
	cat "$APPELE_F" 2>/dev/null
}

reinit() { # repart d'un dossier de faux binaires vide, à chaque scénario
	rm -rf "$FAUXBIN"; mkdir -p "$FAUXBIN"
	pose_faux lexos-settings
}

# =============================================================================
titre "1. Firefox actif -> SES préférences (about:preferences), pas celles de l'ordinateur"
# =============================================================================
reinit
pose_classe "Firefox-esr"
pose_faux firefox-esr
R="$(lance)"
case "$R" in
	"firefox-esr about:preferences") ok "Firefox-esr -> firefox-esr about:preferences" ;;
	*) non "attendu « firefox-esr about:preferences », obtenu « $R »" ;;
esac

# =============================================================================
titre "2. La casse ne doit pas compter (« FIREFOX » majuscule, WM_CLASS variable)"
# =============================================================================
reinit
pose_classe "FIREFOX"
pose_faux firefox-esr
R="$(lance)"
case "$R" in
	"firefox-esr about:preferences") ok "FIREFOX (majuscules) reconnu pareil que Firefox-esr" ;;
	*) non "la casse a fait rater la reconnaissance : « $R »" ;;
esac

# =============================================================================
titre "3. Thunar actif -> thunar-settings, le vrai binaire dédié (pas de --preferences sur thunar)"
# =============================================================================
reinit
pose_classe "Thunar"
pose_faux thunar-settings
R="$(lance)"
case "$R" in
	"thunar-settings ") ok "Thunar -> thunar-settings, sans option (c'est tout ce qu'il accepte)" ;;
	*) non "attendu « thunar-settings », obtenu « $R »" ;;
esac

# =============================================================================
titre "4. xfce4-terminal actif -> --preferences (vérifié dans man xfce4-terminal(1))"
# =============================================================================
reinit
pose_classe "Xfce4-terminal"
pose_faux xfce4-terminal
R="$(lance)"
case "$R" in
	"xfce4-terminal --preferences") ok "Xfce4-terminal -> xfce4-terminal --preferences" ;;
	*) non "attendu « xfce4-terminal --preferences », obtenu « $R »" ;;
esac

# =============================================================================
titre "5. Fenêtre reconnue mais son binaire de préférences est absent -> repli, pas de plantage"
# =============================================================================
reinit
pose_classe "Thunar"
retire_faux thunar-settings   # jamais posé : Thunar est présent, ses réglages non
R="$(lance)"
case "$R" in
	"lexos-settings ") ok "thunar-settings manquant -> repli propre sur lexos-settings" ;;
	*) non "attendu le repli lexos-settings, obtenu « $R »" ;;
esac

# =============================================================================
titre "6. Application non reconnue (Mousepad — aucun réglage exposé en CLI) -> repli"
# =============================================================================
reinit
pose_classe "Mousepad"
R="$(lance)"
case "$R" in
	"lexos-settings ") ok "Mousepad (sans porte connue) -> repli sur lexos-settings" ;;
	*) non "attendu le repli lexos-settings, obtenu « $R »" ;;
esac

# =============================================================================
titre "7. Aucune fenêtre active (xdotool ne rend rien) -> repli, jamais un plantage"
# =============================================================================
reinit
pose_classe ""
R="$(lance)"
case "$R" in
	"lexos-settings ") ok "aucune fenêtre active -> repli sur lexos-settings" ;;
	*) non "attendu le repli lexos-settings, obtenu « $R »" ;;
esac

# =============================================================================
titre "8. xdotool absent du système -> repli immédiat, pas d'erreur bruyante"
# =============================================================================
reinit
rm -f "$FAUXBIN/xdotool"
R="$(lance)"
case "$R" in
	"lexos-settings ") ok "xdotool absent -> repli sur lexos-settings" ;;
	*) non "attendu le repli lexos-settings, obtenu « $R »" ;;
esac

# =============================================================================
titre "9. Firefox détecté mais AUCUN binaire firefox(-esr) présent -> repli, rien d'inventé"
# =============================================================================
reinit
pose_classe "Firefox-esr"
R="$(lance)"
case "$R" in
	"lexos-settings ") ok "Firefox reconnu sans binaire disponible -> repli, pas de commande fantôme" ;;
	*) non "attendu le repli lexos-settings, obtenu « $R »" ;;
esac

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
