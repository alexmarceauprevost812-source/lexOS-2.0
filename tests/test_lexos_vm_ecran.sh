#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-vm-ecran — l'écran de LexOS suit la fenêtre VirtualBox
# =============================================================================
#  ALEX : « améliorer la qualité de l'image de LexOS dans la VM ». On fait
#  tourner le vrai script avec un faux xrandr qui NOTE ce qu'on lui demande.
# =============================================================================
set -uo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-vm-ecran"
AUTO="$RACINE/config/includes.chroot/etc/xdg/autostart/lexos-vm-ecran.desktop"
PLAY="$RACINE/config/includes.chroot/usr/share/lexos/kit-play/.lexos/jouer.ps1"
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
REUSSIS=0; ECHOUES=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }

[ -x "$OUTIL" ] && ok "lexos-vm-ecran exécutable" || non "lexos-vm-ecran pas exécutable"
sh -n "$OUTIL" && ok "syntaxe sh valide" || non "syntaxe sh invalide"
grep -qx 'Exec=/usr/bin/lexos-vm-ecran' "$AUTO" && ok "lancé à l'ouverture de session" || non "autostart absent"

mkdir -p "$B/bin"
faux_xrandr() { # $1 = sortie de xrandr --query
	printf '%s\n' "$1" > "$B/query"
	cat > "$B/bin/xrandr" <<EOF
#!/bin/sh
if [ "\$1" = "--query" ]; then cat "$B/query"; else echo "\$*" >> "$B/appels"; fi
EOF
	chmod +x "$B/bin/xrandr"; rm -f "$B/appels"
}
jouer() { env PATH="$B/bin:$PATH" DISPLAY=:0 LEXOS_VM_ECRAN_VIRT="$1" sh "$OUTIL" --une-fois; }

AGRANDIE='Screen 0: minimum 1 x 1, current 1024 x 768, maximum 16384 x 16384
Virtual-1 connected primary 1024x768+0+0 0mm x 0mm
   1912x1006     60.00 +
   1024x768      60.00*
   800x600       60.00
Virtual-2 disconnected'
faux_xrandr "$AGRANDIE"
jouer oracle
grep -qx -- '--output Virtual-1 --auto' "$B/appels" 2>/dev/null \
	&& ok "fenêtre agrandie : l'écran prend la taille de la fenêtre" || non "fenêtre agrandie : rien appliqué"

DEJA='Screen 0: minimum 1 x 1, current 1912 x 1006, maximum 16384 x 16384
Virtual-1 connected primary 1912x1006+0+0 0mm x 0mm
   1912x1006     60.00*+
   1024x768      60.00'
faux_xrandr "$DEJA"
jouer oracle
[ ! -s "$B/appels" ] && ok "déjà à la bonne taille : rien n'est touché" || non "xrandr relancé pour rien"

faux_xrandr "$AGRANDIE"
jouer none
[ ! -s "$B/appels" ] && ok "vrai PC : aucun écran touché" || non "vrai PC : xrandr appelé"
jouer vmware
[ -s "$B/appels" ] && ok "VMware : même ajustement" || non "VMware : rien appliqué"

grep -q "EfiGraphicsResolution" "$PLAY" && ok "kit PLAY : démarrage en haute résolution (plus de 800 x 600 flou)" || non "kit PLAY : résolution EFI absente"
grep -q "GUI/AutoresizeGuest" "$PLAY" && ok "kit PLAY : la fenêtre demande l'ajustement" || non "kit PLAY : ajustement automatique absent"

printf '\n%d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
