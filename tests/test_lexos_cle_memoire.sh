#!/usr/bin/env bash
# =============================================================================
#  Éprouver la clé mémoire — une clé USB comme espace BONUS pour LexOS
# =============================================================================
#  ALEX : LexOS vit sur le disque du PC (80 Go) ; « la clé va juste servir de
#  mémoire de plus […] de bonus ». Sans elle, tout marche pareil.
#  On fait tourner le vrai « preparer » avec de faux outils disque qui NOTENT
#  ce qu'on leur demande, un faux fstab et un faux /etc/lexos.
# =============================================================================
set -uo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INC="$RACINE/config/includes.chroot"
OUTIL="$INC/usr/bin/lexos-cle-memoire"
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
REUSSIS=0; ECHOUES=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }

[ -x "$OUTIL" ] && ok "lexos-cle-memoire exécutable" || non "pas exécutable"
bash -n "$OUTIL" && ok "syntaxe valide" || non "syntaxe invalide"
grep -q 'exec lexos-cle-memoire' "$INC/usr/bin/lexos" && ok "« lexos cle-memoire » branché" || non "commande lexos absente"
SERVICE="$INC/usr/lib/systemd/system/lexos-cle-memoire.service"
FUSION="$INC/usr/lib/lexos/cle-memoire-fusion"
grep -q 'ConditionPathExists=/etc/lexos/cle-memoire' "$SERVICE" && ok "service : ne fait rien sans clé préparée" || non "service sans condition"
grep -q 'Before=display-manager.service' "$SERVICE" && ok "service : fusion AVANT l'écran de connexion" || non "fusion après la connexion"
grep -q 'systemctl enable lexos-cle-memoire.service' "$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot" && ok "service activé à la construction" || non "service jamais activé"
grep -qx 'mergerfs' "$RACINE/config/package-lists/lexos-core.list.chroot" && ok "mergerfs dans l'ISO" || non "mergerfs absent de l'ISO"

#  ── Un faux système : la clé /dev/sdz (USB, 64G), LexOS sur /dev/sda ──
mkdir -p "$B/bin" "$B/etc"
echo "UUID=racine / ext4 defaults 0 1" > "$B/etc/fstab"
cat > "$B/bin/lsblk" <<'EOF'
#!/bin/sh
dev=""; for a in "$@"; do case "$a" in /dev/*) dev="$a";; esac; done
case "$*" in
	*"-dno TYPE"*)        [ "$dev" = /dev/sdz1 ] && echo part || echo disk ;;
	*"-dno TRAN"*)        [ "$dev" = /dev/sdz ] && echo usb || echo sata ;;
	*"-dno RM"*)          [ "$dev" = /dev/sdz ] && echo 1 || echo 0 ;;
	*"-dno SIZE"*)        echo 64G ;;
	*"-dno MODEL"*)       echo "Cle Test" ;;
	*"MOUNTPOINT"*)       : ;;
	*"NAME,TYPE /dev/sda2"*) printf '/dev/sda2 part\n/dev/sda disk\n' ;;
	*"NAME,TYPE /dev/sdz"*)  printf '/dev/sdz disk\n/dev/sdz1 part\n' ;;
esac
EOF
printf '#!/bin/sh\necho /dev/sda2\n' > "$B/bin/findmnt"
printf '#!/bin/sh\necho 1234-cafe\n' > "$B/bin/blkid"
for c in wipefs parted partprobe udevadm mkfs.ext4 mount umount chown systemctl systemd-escape sleep; do
	printf '#!/bin/sh\necho "%s $*" >> "%s/appels"\n' "$c" "$B" > "$B/bin/$c"
done
chmod +x "$B/bin/"*

jouer() { # jouer <réponse> <args…>
	local rep="$1"; shift
	printf '%s\n' "$rep" | env PATH="$B/bin:$PATH" SUDO_USER="" NO_COLOR=1 \
		LEXOS_CLE_MEMOIRE_CONF="$B/etc/lexos/cle-memoire" LEXOS_FSTAB="$B/etc/fstab" \
		LEXOS_CLE_MEMOIRE_POINT="$B/mnt" bash -c '
			#  Les « -b » de ce banc : nos faux périphériques existent (sed ci-dessous).
			readlink() { [ "$1" = -f ] && shift; echo "$1"; }
			id() { [ "${1:-}" = -u ] && echo 0 || command id "$@"; }
			source <(sed "s/\[\[ -b \"\$dev\" \]\]/true/; s/\[\[ -b \"\$part\" \]\]/true/" "$0")
		' "$OUTIL" "$@" > "$B/journal" 2>&1
}

rm -f "$B/appels"
jouer "non" preparer /dev/sdz
grep -q "Annulé, rien n'a été touché" "$B/journal" && [ ! -e "$B/appels" ] \
	&& ok "sans « OUI » : la clé n'est pas touchée" || non "la clé a été touchée sans confirmation"

jouer "OUI" preparer /dev/sda
grep -q "est le disque où LexOS est installé" "$B/journal" && ok "le disque de LexOS est refusé" || non "le disque de LexOS accepté !"

jouer "OUI" preparer /dev/sdz1
grep -q "est une partition" "$B/journal" && ok "une partition seule est refusée" || non "partition acceptée"

rm -f "$B/appels"
jouer "OUI" preparer /dev/sdz
grep -q "mkfs.ext4 .*LEXOS-MEMOIRE" "$B/appels" 2>/dev/null && ok "OUI : la clé est formatée (ext4, LEXOS-MEMOIRE)" || { non "formatage absent"; sed 's/^/      /' "$B/journal"; }
grep -q '^UUID=1234-cafe$' "$B/etc/lexos/cle-memoire" 2>/dev/null && ok "la clé est reconnue par son UUID" || non "UUID non noté"
grep -q '^MODE=fusion$' "$B/etc/lexos/cle-memoire" 2>/dev/null && ok "fusion par défaut (« comme 1 seul espace »)" || non "le mode par défaut n'est pas la fusion"
grep -q '^MARGE=10G$' "$B/etc/lexos/cle-memoire" 2>/dev/null && ok "10 Go gardés sur le PC pour les mises à jour" || non "aucune marge pour les mises à jour"
L="$(grep 'lexos-cle-memoire$' "$B/etc/fstab")"
case "$L" in *nofail*) case "$L" in *automount*) non "fusion : la clé ne doit pas être en automontage" ;; *) ok "fstab fusion : « nofail », montée au démarrage — sans clé, LexOS démarre pareil" ;; esac ;; *) non "fstab : $L" ;; esac
grep -q '^UUID=racine' "$B/etc/fstab" && ok "le reste de fstab est intact" || non "fstab abîmé"
[ -e "$B/etc/fstab.avant-cle-memoire" ] && ok "sauvegarde de fstab avant changement" || non "pas de sauvegarde de fstab"

jouer "OUI" preparer /dev/sdz
[ "$(grep -c 'lexos-cle-memoire$' "$B/etc/fstab")" = 1 ] && ok "refaire « preparer » ne double pas la ligne" || non "ligne fstab en double"

jouer "OUI" preparer /dev/sdz --dossier
grep -q '^MODE=dossier$' "$B/etc/lexos/cle-memoire" && grep 'lexos-cle-memoire$' "$B/etc/fstab" | grep -q 'x-systemd.automount' \
	&& ok "--dossier : la clé à part (~/Mémoire), en automontage" || non "--dossier mal réglé"

jouer "" oublier
! grep -q 'lexos-cle-memoire$' "$B/etc/fstab" && [ ! -e "$B/etc/lexos/cle-memoire" ] \
	&& ok "oublier : fstab et réglage nettoyés" || non "oublier incomplet"

#  ── La fusion au démarrage : le vrai script, de faux findmnt et mergerfs ──
fusion() { # fusion <uuid monté sur la clé> <mode>
	rm -rf "$B/f"; mkdir -p "$B/f/home" "$B/f/cle/home" "$B/fb"
	printf 'UUID=1234-cafe\nMODE=%s\nMARGE=10G\n' "$2" > "$B/f/conf"
	echo "$1" > "$B/f/uuid"
	cat > "$B/fb/findmnt" <<EOF
#!/bin/sh
case "\$*" in *UUID*) cat "$B/f/uuid" ;; *FSTYPE*) echo ext4 ;; esac
EOF
	for c in mount mergerfs umount df; do printf '#!/bin/sh\necho "%s $*" >> "%s/f/appels"\n' "$c" "$B" > "$B/fb/$c"; done
	chmod +x "$B/fb/"*
	env PATH="$B/fb:$PATH" LEXOS_CLE_MEMOIRE_CONF="$B/f/conf" LEXOS_CLE_MEMOIRE_POINT="$B/f/cle" \
		LEXOS_CLE_MEMOIRE_HOME="$B/f/home" LEXOS_CLE_MEMOIRE_PC="$B/f/pc" sh "$FUSION" > "$B/f/journal" 2>&1
}
[ -x "$FUSION" ] && sh -n "$FUSION" && ok "cle-memoire-fusion exécutable, syntaxe valide" || non "cle-memoire-fusion invalide"
fusion "1234-cafe" fusion
grep -q "mergerfs .*category.create=ff,minfreespace=10G" "$B/f/appels" 2>/dev/null \
	&& ok "clé là : /home = PC d'abord, puis la clé quand le PC n'a plus que 10 Go" || { non "fusion non faite"; cat "$B/f/journal"; }
grep -q "mergerfs .*$B/f/pc:$B/f/cle/home $B/f/home" "$B/f/appels" && ok "les deux morceaux : le /home du PC, puis le home de la clé" || non "mauvais morceaux"
grep -q "mount --bind $B/f/home $B/f/pc" "$B/f/appels" && ok "le /home du PC est gardé visible avant d'être recouvert" || non "le /home du PC serait perdu de vue"
fusion "" fusion
! grep -q mergerfs "$B/f/appels" 2>/dev/null && grep -q "clé absente" "$B/f/journal" \
	&& ok "clé absente : rien ne change, LexOS marche sur le PC seul" || non "clé absente : quelque chose a été touché"
fusion "1234-cafe" dossier
[ ! -s "$B/f/appels" ] && ok "mode dossier : pas de fusion" || non "mode dossier fusionné par erreur"

printf '\n%d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
