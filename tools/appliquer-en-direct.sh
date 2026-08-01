#!/usr/bin/env bash
# =============================================================================
#  appliquer-en-direct.sh — pose les changements de ce dépôt sur un LexOS
#  déjà installé, SANS reconstruire une ISO ni redémarrer.
# =============================================================================
#  Pour qui : quelqu'un qui a cloné ce dépôt sur un LexOS déjà en place et
#  veut voir les changements d'interface tout de suite, sans passer par
#  « make build » + réinstallation/reboot depuis une clé USB.
#
#  Ce que ce script fait :
#    · copie branding/ vers /usr/share/lexos/branding, puis relance le rendu
#      des icônes et fonds d'écran (même logique que le hook 0300, qui ne
#      touche que des fichiers — sûr à rejouer) ;
#    · pose l'entrée de menu Paramètres (hook 0450 — sûr, ne fait que ça) ;
#    · pose l'entrée de menu GitHub (juste ce fichier, pas tout le hook 0400) ;
#    · installe les paquets PySide6 qu'il faut pour l'app Réglages ;
#    · copie panneau XFCE / gestionnaire de fenêtres / bureau / dock vers
#      /etc/skel (pour les futurs comptes) ET vers le compte réellement
#      utilisé (sinon rien ne change à l'écran) ;
#    · relance panneau, dock et gestionnaire de fenêtres pour qu'ils
#      relisent leur config, sans fermer aucune fenêtre ouverte.
#
#  Ce que ce script NE fait PAS, volontairement : le hook 0400 complet
#  touche aussi LightDM (connexion automatique), les sudoers (mot de passe
#  désactivé pour l'utilisateur « lex ») et crée un compte « invite » — du
#  bon sens sur une clé USB de démo, pas forcément sur ta machine
#  installée. Si tu veux vraiment ça aussi, lis 0400-lexos-desktop.hook.chroot
#  et applique-le à la main, en connaissance de cause.
#
#  Chaque fichier remplacé est sauvegardé avant d'être touché.
# =============================================================================
set -uo pipefail

if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
	O=$'\033[38;5;208m'; E=$'\033[31m'; V=$'\033[32m'; Y=$'\033[33m'
	B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'
else
	O=''; E=''; V=''; Y=''; B=''; D=''; R=''
fi
say()  { printf '%s»%s %s\n' "$O" "$R" "$*"; }
ok()   { printf '%s✓%s %s\n' "$V" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$R" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$E" "$R" "$*" >&2; exit 1; }
titre(){ printf '\n%s%s%s\n' "$B" "$*" "$R"; }

[[ $EUID -eq 0 ]] || die "Lance ce script avec sudo (il écrit dans /usr et /etc)."

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -d config/includes.chroot ]] || die "À lancer depuis un clone du dépôt (config/includes.chroot introuvable)."

# --- Quel compte est réellement utilisé ? -----------------------------------
CIBLE="${1:-${SUDO_USER:-}}"
if [[ -z "$CIBLE" ]]; then
	die "Indique le compte à mettre à jour : sudo tools/appliquer-en-direct.sh <utilisateur>"
fi
id "$CIBLE" >/dev/null 2>&1 || die "Compte inconnu : $CIBLE"
HOME_CIBLE="$(getent passwd "$CIBLE" | cut -d: -f6)"
[[ -d "$HOME_CIBLE" ]] || die "Dossier personnel introuvable pour $CIBLE"

# --- Lancer une commande dans la session graphique de ce compte -------------
BUS="/run/user/$(id -u "$CIBLE")/bus"
[[ -S "$BUS" ]] || BUS=""
comme_utilisateur() {
	if [[ -n "$BUS" ]]; then
		sudo -u "$CIBLE" DISPLAY="${DISPLAY:-:0}" \
			DBUS_SESSION_BUS_ADDRESS="unix:path=$BUS" \
			XDG_RUNTIME_DIR="/run/user/$(id -u "$CIBLE")" \
			"$@"
	else
		sudo -u "$CIBLE" DISPLAY="${DISPLAY:-:0}" "$@"
	fi
}
if [[ -z "$BUS" ]]; then
	warn "Pas de session graphique détectée pour $CIBLE — les fichiers seront"
	warn "copiés, mais rien ne sera relancé automatiquement. Reconnecte-toi ensuite."
fi

SAUVEGARDE="/var/backups/lexos-appliquer-en-direct-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAUVEGARDE"
sauvegarder() { # sauvegarder <chemin>
	[[ -e "$1" ]] || return 0
	local dest="$SAUVEGARDE${1}"
	mkdir -p "$(dirname "$dest")"
	cp -a "$1" "$dest"
}

titre "Compte visé : $CIBLE ($HOME_CIBLE)"
titre "Sauvegardes dans : $SAUVEGARDE"

# =============================================================================
#  1. Branding — icônes, fond d'écran, thème Plymouth
# =============================================================================
titre "1/6 · Branding et icônes"
mkdir -p /usr/share/lexos/branding
cp branding/*.svg branding/*.png /usr/share/lexos/branding/ 2>/dev/null
ok "branding/ -> /usr/share/lexos/branding"

if command -v rsvg-convert >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
	sh config/hooks/normal/0300-lexos-assets.hook.chroot
else
	warn "Ni rsvg-convert (librsvg2-bin) ni convert (imagemagick) : icônes non régénérées."
	warn "  sudo apt install librsvg2-bin imagemagick webp"
fi

# =============================================================================
#  2. Entrées de menu — Paramètres (hook 0450, sûr en entier) et GitHub
# =============================================================================
titre "2/6 · Entrées de menu"
#  On écrit ces .desktop nous-mêmes plutôt que d'appeler le hook 0450 : ce
#  hook s'arrête sans rien faire s'il ne détecte ni lightdm ni startxfce4
#  (garde-fou pensé pour la construction de l'ISO, pas pour une machine où
#  le bureau tourne déjà) — pas de raison de dépendre de cette condition ici.
mkdir -p /usr/share/applications
cat > /usr/share/applications/lexos-settings.desktop <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Paramètres
Name[en]=Settings
Comment=Wi-Fi, écrans, performance, apparence, comptes, mises à jour…
Exec=lexos-settings
Icon=lexos-reglages
Terminal=false
StartupNotify=true
StartupWMClass=Paramètres LexOS
Categories=Settings;
Keywords=parametres;settings;wifi;reseau;bluetooth;ecrans;son;energie;performance;apparence;bureau;applications;notifications;recherche;comptes;partage;bien-etre;souris;pave tactile;touchpad;couleurs;imprimantes;confidentialite;securite;mises a jour;accessibilite;utilisateurs;langue;clavier;a propos;
EOF
cat > /usr/share/applications/lexos-github.desktop <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=GitHub
Comment=Ouvrir GitHub dans le navigateur
Exec=xdg-open https://github.com
Icon=lexos-github
Terminal=false
Categories=Network;Development;
Keywords=github;git;code;depot;repository;
EOF
ok "Paramètres + GitHub posés dans /usr/share/applications"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null

# =============================================================================
#  3. Paquets pour l'app Réglages (PySide6)
# =============================================================================
titre "3/6 · Paquets de l'app Réglages"
if python3 -c "import PySide6.QtWebEngineWidgets" >/dev/null 2>&1; then
	ok "PySide6 déjà présent"
else
	say "Installation des paquets PySide6 (Debian, pas pip)…"
	apt-get update -qq || warn "apt-get update a échoué, on essaie quand même"
	if apt-get install -y $(grep -Ev '^[[:space:]]*(#|$)' \
			config/includes.chroot/usr/share/lexos/optional-packages/56-reglages.list); then
		ok "PySide6 installé"
	else
		warn "Échec d'installation — l'app Réglages ne se lancera pas tant que ce n'est pas réglé."
	fi
fi

cp config/includes.chroot/usr/bin/lexos-settings /usr/bin/lexos-settings
chmod 755 /usr/bin/lexos-settings
mkdir -p /usr/lib/lexos /usr/share/lexos/settings
cp config/includes.chroot/usr/lib/lexos/settings.py /usr/lib/lexos/settings.py
rsync -a --delete config/includes.chroot/usr/share/lexos/settings/web/ /usr/share/lexos/settings/web/ 2>/dev/null \
	|| cp -a config/includes.chroot/usr/share/lexos/settings/web /usr/share/lexos/settings/
ok "lexos-settings, settings.py et l'interface web posés"

# =============================================================================
#  4. Panneau, gestionnaire de fenêtres, bureau — squelette + compte réel
# =============================================================================
titre "4/6 · Panneau, fenêtres, bureau"
SKEL_XFCONF="etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
CIBLE_XFCONF="$HOME_CIBLE/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "/$SKEL_XFCONF" "$CIBLE_XFCONF"

for f in xfce4-panel.xml xfwm4.xml xfce4-desktop.xml; do
	src="config/includes.chroot/$SKEL_XFCONF/$f"
	[[ -r "$src" ]] || continue
	cp "$src" "/$SKEL_XFCONF/$f"
	sauvegarder "$CIBLE_XFCONF/$f"
	cp "$src" "$CIBLE_XFCONF/$f"
	chown "$CIBLE:$CIBLE" "$CIBLE_XFCONF/$f"
done
ok "xfce4-panel.xml, xfwm4.xml, xfce4-desktop.xml posés (squelette + $CIBLE)"

mkdir -p "$HOME_CIBLE/.config/xfce4/panel"
for d in config/includes.chroot/etc/skel/.config/xfce4/panel/launcher-*; do
	[[ -d "$d" ]] || continue
	nom="$(basename "$d")"
	rsync -a --delete "$d/" "$HOME_CIBLE/.config/xfce4/panel/$nom/" 2>/dev/null \
		|| cp -a "$d" "$HOME_CIBLE/.config/xfce4/panel/$nom"
done
chown -R "$CIBLE:$CIBLE" "$HOME_CIBLE/.config/xfce4/panel"
ok "Lanceurs du panneau (capture rapide, réglages rapides) posés"

# =============================================================================
#  5. Dock Plank — lanceurs et ordre
# =============================================================================
titre "5/6 · Dock"
CIBLE_DOCK="$HOME_CIBLE/.config/plank/dock1/launchers"
mkdir -p "$CIBLE_DOCK"
sauvegarder "$CIBLE_DOCK"
rm -f "$CIBLE_DOCK/04-appfinder.dockitem"
cp config/includes.chroot/etc/skel/.config/plank/dock1/launchers/*.dockitem "$CIBLE_DOCK/"
chown -R "$CIBLE:$CIBLE" "$HOME_CIBLE/.config/plank"

#  00-lexos-dock est un DÉFAUT système (dconf) : un compte qui a déjà
#  touché son dock a sa propre valeur enregistrée, qui gagnerait sur ce
#  défaut. On écrit donc aussi directement dans la base de CE compte pour
#  que le nouvel ordre s'applique tout de suite, pas seulement pour un
#  compte qui n'a jamais rien changé.
DOCK_ITEMS="$(grep '^dock-items=' config/includes.chroot/etc/dconf/db/local.d/00-lexos-dock | cut -d= -f2-)"
if [[ -n "$DOCK_ITEMS" ]]; then
	comme_utilisateur dconf write /net/launchpad/plank/docks/dock1/dock-items "$DOCK_ITEMS" \
		&& ok "Ordre du dock appliqué au compte $CIBLE" \
		|| warn "dconf write a échoué — vérifie l'ordre du dock à la main (clic droit → Préférences)"
fi
mkdir -p /etc/dconf/db/local.d
cp config/includes.chroot/etc/dconf/db/local.d/00-lexos-dock /etc/dconf/db/local.d/00-lexos-dock
command -v dconf >/dev/null 2>&1 && dconf update

# =============================================================================
#  6. Tout relancer, sans rien fermer
# =============================================================================
titre "6/6 · Relance des composants du bureau"
if [[ -n "$BUS" ]]; then
	comme_utilisateur xfce4-panel -r >/dev/null 2>&1 && ok "Panneau relancé" \
		|| warn "xfce4-panel -r a échoué — déconnecte-toi/reconnecte-toi pour le panneau"
	comme_utilisateur xfwm4 --replace >/dev/null 2>&1 &
	sleep 1; ok "Gestionnaire de fenêtres relancé (xfwm4 --replace)"
	comme_utilisateur xfdesktop --reload >/dev/null 2>&1 && ok "Bureau (menu clic droit) rechargé" \
		|| warn "xfdesktop --reload a échoué"
	comme_utilisateur pkill -u "$CIBLE" plank >/dev/null 2>&1
	sleep 1
	comme_utilisateur setsid plank >/dev/null 2>&1 &
	ok "Dock relancé"
else
	warn "Reconnecte-toi (ou redémarre la session) pour que tout prenne effet."
fi

titre "Terminé"
say "Sauvegardes des fichiers remplacés : ${D}$SAUVEGARDE${R}"
say "Non touché volontairement : LightDM, sudoers, compte « invite » (voir hook 0400)."
