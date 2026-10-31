#!/usr/bin/env bash
# =============================================================================
#  Éprouver 45_lexos-menu-cache — menu GRUB caché quand LexOS est SEUL
# =============================================================================
#  ALEX : « ça affiche encore l'écran GRUB » sur sa clé USB-C, « va falloir
#  le faire à tout le monde ». On fait tourner le vrai script contre de faux
#  grub.cfg en cours d'écriture (seam LEXOS_GRUB_SORTIE).
# =============================================================================
set -uo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/etc/grub.d/45_lexos-menu-cache"
BANC="$(mktemp -d)"; trap 'rm -rf "$BANC"' EXIT
REUSSIS=0; ECHOUES=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }

[ -x "$SCRIPT" ] && ok "script exécutable (grub-mkconfig ignore les autres)" || non "script pas exécutable"
sh -n "$SCRIPT" && ok "syntaxe sh valide" || non "syntaxe sh invalide"

cfg() { # $1 = contenu du bloc os-prober
	printf '### BEGIN /etc/grub.d/10_linux ###\nmenuentry "LexOS" {\n}\n### END /etc/grub.d/10_linux ###\n'
	printf '### BEGIN /etc/grub.d/30_os-prober ###\n%b### END /etc/grub.d/30_os-prober ###\n' "$1"
}

cfg "" > "$BANC/seul.cfg"
OUT=$(LEXOS_GRUB_SORTIE="$BANC/seul.cfg" LEXOS_MENU_DEMARRAGE_FICHIER=/nulle/part sh "$SCRIPT" 2>/dev/null)
echo "$OUT" | grep -q 'set timeout_style=hidden' && ok "LexOS seul : menu caché" || non "LexOS seul : menu pas caché"
echo "$OUT" | grep -q 'saved_entry' && ok "LexOS seul : garde saved_entry au démarrage" || non "garde saved_entry absente"

cfg 'menuentry "Windows Boot Manager (on /dev/sda1)" --class windows --class os {\n}\n' > "$BANC/win.cfg"
OUT=$(LEXOS_GRUB_SORTIE="$BANC/win.cfg" LEXOS_MENU_DEMARRAGE_FICHIER=/nulle/part sh "$SCRIPT" 2>/dev/null)
[ -z "$OUT" ] && ok "Windows à côté : menu 8 s intact" || non "Windows à côté : le menu serait caché"

cfg 'menuentry "Ubuntu 26.04.1 LTS (on /dev/sda3)" --class ubuntu --class linux --class os {\n}\n' > "$BANC/ubu.cfg"
OUT=$(LEXOS_GRUB_SORTIE="$BANC/ubu.cfg" LEXOS_MENU_DEMARRAGE_FICHIER=/nulle/part sh "$SCRIPT" 2>/dev/null)
[ -z "$OUT" ] && ok "Ubuntu à côté : menu 8 s intact" || non "Ubuntu à côté : le menu serait caché"

OUT=$(LEXOS_GRUB_SORTIE="pas-un-chemin" LEXOS_MENU_DEMARRAGE_FICHIER=/nulle/part sh "$SCRIPT" 2>/dev/null)
[ -z "$OUT" ] && ok "sortie inconnue : on ne touche à rien" || non "sortie inconnue : menu caché à l'aveugle"

echo toujours > "$BANC/choix"
OUT=$(LEXOS_GRUB_SORTIE="$BANC/seul.cfg" LEXOS_MENU_DEMARRAGE_FICHIER="$BANC/choix" sh "$SCRIPT" 2>/dev/null)
[ -z "$OUT" ] && ok "« toujours » : menu forcé visible" || non "« toujours » ignoré"

# Le vrai chemin : grub-mkconfig redirige stdout vers grub.cfg.new
( exec > "$BANC/vrai.cfg"; cat "$BANC/seul.cfg"; LEXOS_MENU_DEMARRAGE_FICHIER=/nulle/part sh "$SCRIPT" 2>/dev/null )
grep -q 'timeout_style=hidden' "$BANC/vrai.cfg" && ok "lecture via /proc/$$/fd/1 (comme grub-mkconfig)" || non "/proc/self/fd/1 non lu"

printf '\n%d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
