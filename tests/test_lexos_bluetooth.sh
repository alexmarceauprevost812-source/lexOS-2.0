#!/usr/bin/env bash
# =============================================================================
#  Éprouver la recherche Bluetooth — un échec ne se déguise plus en succès
# =============================================================================
#  ALEX : « dans les paramètres Bluetooth, il ne trouve rien ».
#
#  CE QUI ÉTAIT CASSÉ, ET DANS LES DEUX OUTILS À LA FOIS. « bluetoothctl
#  --timeout 12 scan on » peut échouer (contrôleur pas prêt, balayage déjà
#  en cours, radio coupée entre-temps) — et le code IGNORAIT son code de
#  retour dans les deux endroits qui l'appellent :
#    · settings.py / act_bt_chercher() : rendait {"ok": True} même en cas
#      d'échec — la page affichait « Recherche terminée » sans avoir
#      cherché.
#    · lexos-net / cmd_bt scan : « || true » avalait l'échec — le terminal
#      affichait « Aucun appareil trouvé », qui est le message d'une
#      recherche qui A EU LIEU et n'a rien vu, pas d'une recherche qui n'a
#      jamais eu lieu.
#
#  Un succès affiché à la place d'un échec est pire qu'un échec brut : on
#  cherche alors du côté de l'enceinte, de la distance, du mode appairage —
#  jamais du côté du programme, qui pourtant savait.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
NET="$RACINE/config/includes.chroot/usr/bin/lexos-net"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. settings.py — act_bt_chercher() dit la vérité"
# =============================================================================
BIN="$BANC/bin"; mkdir -p "$BIN"

faux_bluetoothctl() { # faux_bluetoothctl <0|1> [message-stderr]
	cat > "$BIN/bluetoothctl" <<EOS
#!/bin/sh
$( [ -n "${2:-}" ] && printf '%s\n' "printf '%s\\n' '$2' >&2" )
exit $1
EOS
	chmod +x "$BIN/bluetoothctl"
}

appelle() { # appelle -> imprime le dict Python rendu par act_bt_chercher()
	PATH="$BIN:/usr/bin:/bin" python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.act_bt_chercher(None))
"
}

faux_bluetoothctl 0
R="$(appelle)"
case "$R" in
	*"'ok': True"*) ok "bluetoothctl réussi (code 0) -> {\"ok\": True}" ;;
	*) non "code 0 mais la réponse est « $R »" ;;
esac

faux_bluetoothctl 1 "Failed to start discovery: org.bluez.Error.InProgress"
R="$(appelle)"
case "$R" in
	*"'ok': False"*"InProgress"*) ok "bluetoothctl en échec -> {\"ok\": False}, avec la VRAIE raison" ;;
	*"'ok': True"*) non "bluetoothctl a échoué (code 1) mais la réponse dit quand même {\"ok\": True} — le bogue d'Alex" ;;
	*) non "réponse inattendue : « $R »" ;;
esac

faux_bluetoothctl 1 ""
R="$(appelle)"
case "$R" in
	*"'ok': False"*"échoué (code 1)"*) ok "échec SANS message : un motif de repli est quand même donné, jamais une chaîne vide" ;;
	*) non "échec sans message : « $R »" ;;
esac

# =============================================================================
titre "2. lexos-net (le terminal) — même vérité, même endroit"
# =============================================================================
#  On ne relance pas la vraie machine Bluetooth : on isole juste le bloc
#  « scan) » et on lui fournit un faux bluetoothctl, comme les autres bancs
#  de ce dépôt le font pour lexos-session ou lexos-firstrun.
extraire_scan() {
	sed -n '/^\tscan)$/,/^\t\t;;$/p' "$NET"
}
LIGNES="$(extraire_scan | wc -l)"
[ "$LIGNES" -gt 5 ] \
	&& ok "le bloc « scan) » de lexos-net a bien été retrouvé" \
	|| non "bloc « scan) » introuvable ou vide ($LIGNES lignes) — le découpage a raté"

joue_scan() { # joue_scan <0|1> [message]
	faux_bluetoothctl "$1" "${2:-}"
	cat > "$BIN/bt_powered" <<'EOS'
#!/bin/sh
exit 0
EOS
	chmod +x "$BIN/bt_powered"
	{
		echo '#!/bin/bash'
		echo 'set -uo pipefail'
		echo 'PROG=lexos-net'
		echo 'say() { :; }'
		echo 'warn() { printf "WARN:%s\n" "$*"; }'
		echo 'die() { exit 1; }'
		echo 'need_bt() { return 0; }'
		echo 'bt_powered() { return 0; }'
		echo 'case "scan" in'
		extraire_scan
		echo 'esac'
	} > "$BANC/scan.sh"
	PATH="$BIN:/usr/bin:/bin" bash "$BANC/scan.sh" 2>&1
}

SORTIE="$(joue_scan 1 'Failed to start discovery: org.bluez.Error.InProgress')"
case "$SORTIE" in
	*"WARN:La recherche a échoué"*"InProgress"*)
		ok "un balayage refusé est annoncé comme un ÉCHEC, avec la raison réelle" ;;
	*"WARN:Aucun appareil trouvé"*)
		non "un balayage REFUSÉ affiche « Aucun appareil trouvé » — exactement le bogue d'Alex" ;;
	*) non "sortie inattendue : $SORTIE" ;;
esac

SORTIE="$(joue_scan 0)"
case "$SORTIE" in
	*"WARN:La recherche a échoué"*) non "un balayage RÉUSSI est signalé comme un échec" ;;
	*"WARN:Aucun appareil trouvé"*) ok "un balayage réussi qui ne voit rien dit « Aucun appareil trouvé » — pas d'échec inventé" ;;
	*) non "sortie inattendue : $SORTIE" ;;
esac

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
