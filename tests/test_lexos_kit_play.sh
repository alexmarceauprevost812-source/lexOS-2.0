#!/usr/bin/env bash
# =============================================================================
#  Banc : le kit PLAY de la clé nomade (usr/lib/lexos/kit-play, hook 0505)
# =============================================================================
#  Le script réel tourne avec de faux lsblk, findmnt, mount, umount,
#  mountpoint, fatlabel et mattrib sur un PATH à part : la « partition
#  LEXOS » est un dossier. On vérifie :
#    1. il pose le kit quand la partition est vide, et le cache (mattrib) ;
#    2. il ne réécrit RIEN quand le kit est à jour (montage en lecture seule) ;
#    3. il remplace un PLAY.exe différent (mise à jour de LexOS) ;
#    4. il ne touche à rien : saveur non nomade, session démo, deux
#       candidates, partition EFI nommée LEXOS, partition déjà montée ;
#    5. le hook 0505 ajoute LEXOS en tête de partitionLayout, sans point de
#       montage, et laisse /boot et / tels quels ;
#    6. le partition.conf LIVRÉ (autres saveurs) n'a pas d'entrée LEXOS.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/usr/lib/lexos/kit-play"
KIT="$RACINE/config/includes.chroot/usr/share/lexos/kit-play"
HOOK="$RACINE/config/hooks/normal/0505-lexos-kit-play.hook.chroot"
PCONF="$RACINE/config/includes.chroot/etc/calamares/modules/partition.conf"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
mkdir -p "$B/bin" "$B/run" "$B/part"
#  De vrais périphériques bloc existent pour les tests -b du script ; leurs
#  noms seuls servent, rien n'y est lu ni écrit.
DISQUE=/dev/loop0; RACINE_DEV=/dev/loop1; PART=/dev/loop2
for d in $DISQUE $RACINE_DEV $PART; do
	[ -b "$d" ] || { echo "  (pas de $d ici : banc non joué)"; exit 0; }
done

cat > "$B/bin/lsblk" <<EOF
#!/bin/sh
case "\$*" in
	*NAME,TYPE\ $RACINE_DEV*) printf '%s part\n%s disk\n' "$RACINE_DEV" "$DISQUE" ;;
	*NAME,TYPE,FSTYPE,PARTTYPE,LABEL,PARTLABEL*) cat "$B/table" ;;
	*LABEL\ $PART*) cat "$B/etiquette" 2>/dev/null ;;
esac
EOF
cat > "$B/bin/findmnt" <<EOF
#!/bin/sh
case "\$*" in
	*SOURCE\ /) echo "$RACINE_DEV" ;;
	*TARGET\ $PART) cat "$B/deja-monte" 2>/dev/null ;;
esac
EOF
cat > "$B/bin/mount" <<EOF
#!/bin/sh
eval "dernier=\\\${\$#}"
echo "\$*" >> "$B/montages"
rmdir "\$dernier" && ln -s "$B/part" "\$dernier"
EOF
cat > "$B/bin/umount" <<'EOF'
#!/bin/sh
[ -L "$1" ] && rm "$1" && mkdir "$1"
EOF
cat > "$B/bin/mountpoint" <<'EOF'
#!/bin/sh
[ -L "$2" ]
EOF
printf '#!/bin/sh\necho "$*" >> "%s/fatlabel"\n' "$B" > "$B/bin/fatlabel"
printf '#!/bin/sh\necho "$*" >> "%s/mattrib"\n' "$B" > "$B/bin/mattrib"
chmod +x "$B"/bin/*
echo 'LEXOS_FLAVOUR="nomade"' > "$B/build.conf"
echo 'BOOT_IMAGE=/vmlinuz root=UUID=x ro quiet splash' > "$B/cmdline"
ESP="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; DATA="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
printf '%s part vfat %s LEXOS_EFI LEXOS_EFI\n%s part vfat %s  LEXOS\n%s part ext4 x LEXOS_ROOT LEXOS_ROOT\n' \
	/dev/loop9 "$ESP" "$PART" "$DATA" "$RACINE_DEV" > "$B/table"

jouer() {
	rm -f "$B/montages"
	env PATH="$B/bin:$PATH" LEXOS_KIT_PLAY="$KIT" LEXOS_BUILD_CONF="$B/build.conf" \
		LEXOS_CMDLINE="$B/cmdline" LEXOS_RUN="$B/run" sh "$SCRIPT" 2>&1
}
memes() { for f in PLAY.exe autorun.inf .lexos/jouer.ps1 .lexos/lexos.ico; do cmp -s "$KIT/$f" "$B/part/$f" || return 1; done; }

# =============================================================================
titre "1. Partition vide : le kit est posé, caché, étiqueté"
SORTIE="$(jouer)"; echo "$SORTIE" | sed 's/^/      /'
memes && ok "les quatre fichiers du kit sont sur la partition" || non "kit incomplet sur la partition"
grep -q '^-t vfat -o rw' "$B/montages" 2>/dev/null && ok "monté en écriture pour copier" || non "jamais monté en écriture"
grep -q "+h +s ::/.lexos ::/autorun.inf" "$B/mattrib" 2>/dev/null && ok ".lexos et autorun.inf cachés (mattrib, partition démontée)" || non "rien n'a été caché"
grep -q "$PART LEXOS" "$B/fatlabel" 2>/dev/null && ok "étiquette FAT LEXOS posée (Windows affiche « LEXOS »)" || non "étiquette FAT non posée"
ls "$B/part" "$B/part/.lexos" | grep -q nouveau && non "un fichier .nouveau traîne" || ok "aucun fichier .nouveau ne traîne"
[ -z "$(ls -A "$B/run")" ] && ok "le point de montage temporaire est rendu" || non "un point de montage reste dans /run"

# =============================================================================
titre "2. Kit à jour : lecture seule, rien n'est réécrit"
echo LEXOS > "$B/etiquette"
AVANT="$(stat -c %Y "$B/part/PLAY.exe")"; sleep 1
SORTIE="$(jouer)"
grep -q 'rw' "$B/montages" && non "remonté en écriture alors que tout est à jour" || ok "monté en lecture seule seulement"
[ "$(stat -c %Y "$B/part/PLAY.exe")" = "$AVANT" ] && ok "PLAY.exe n'a pas été réécrit" || non "PLAY.exe réécrit pour rien"
echo "$SORTIE" | grep -q "déjà à jour" && ok "le journal dit « déjà à jour »" || non "journal muet"

# =============================================================================
titre "3. PLAY.exe différent (mise à jour de LexOS) : remplacé"
echo "vieux" > "$B/part/PLAY.exe"
jouer >/dev/null
memes && ok "le PLAY.exe livré remplace l'ancien" || non "l'ancien PLAY.exe est resté"

# =============================================================================
titre "4. Ce qu'il ne touche jamais"
rm -rf "$B/part"/* "$B/part/.lexos"
echo 'LEXOS_FLAVOUR="pro"' > "$B/build.conf"; jouer >/dev/null
[ ! -e "$B/montages" ] && ok "saveur pro : rien monté" || non "saveur pro : une partition a été montée"
echo 'LEXOS_FLAVOUR="nomade"' > "$B/build.conf"
echo 'BOOT_IMAGE=/live/vmlinuz boot=live' > "$B/cmdline"; jouer >/dev/null
[ ! -e "$B/montages" ] && ok "session démo : rien monté" || non "session démo : une partition a été montée"
echo 'BOOT_IMAGE=/vmlinuz root=UUID=x ro' > "$B/cmdline"
cp "$B/table" "$B/table.bon"
printf '/dev/loop3 part vfat %s LEXOS LEXOS\n' "$DATA" >> "$B/table"; jouer >/dev/null
[ ! -e "$B/montages" ] && ok "deux partitions LEXOS : on s'abstient" || non "deux candidates : une a été choisie au hasard"
printf '%s part vfat %s LEXOS LEXOS\n' "$PART" "$ESP" > "$B/table"; jouer >/dev/null
[ ! -e "$B/montages" ] && ok "partition EFI nommée LEXOS : refusée" || non "la partition EFI a été montée"
cp "$B/table.bon" "$B/table"; echo /media/ailleurs > "$B/deja-monte"; jouer >/dev/null
[ ! -e "$B/montages" ] && ok "partition déjà montée : on n'y touche pas" || non "partition déjà montée : remontée"
rm -f "$B/deja-monte"

# =============================================================================
titre "5. Hook 0505 : LEXOS en tête de partitionLayout, sans point de montage"
H="$B/hook"; mkdir -p "$H/etc/calamares/modules" "$H/etc/lexos" "$H/sys"
cp "$PCONF" "$H/etc/calamares/modules/"
echo 'LEXOS_FLAVOUR="nomade"' > "$H/etc/lexos/build.conf"
: > "$H/sys/lexos-kit-play.service"; : > "$H/sys/lexos-kit-play.timer"; : > "$H/kit-play"
sed -e "s#/etc/calamares#$H/etc/calamares#g; s#/etc/lexos/build.conf#$H/etc/lexos/build.conf#g" \
    -e "s#/usr/share/lexos/kit-play#$KIT#; s#/usr/lib/lexos/kit-play#$H/kit-play#g; s#/usr/lib/systemd/system#$H/sys#g" \
    "$HOOK" > "$H/hook.sh"
if env PATH="/usr/bin:/bin" sh "$H/hook.sh" > "$H/journal" 2>&1; then ok "le hook passe"; else non "le hook échoue :"; sed 's/^/      /' "$H/journal"; fi
if python3 -c 'import yaml' 2>/dev/null; then
	V="$(python3 - "$H/etc/calamares/modules/partition.conf" <<'PY'
import sys, yaml
lay = yaml.safe_load(open(sys.argv[1]))["partitionLayout"]
e = lay[0]
ok = (e["name"] == "LEXOS" and e["filesystem"] == "fat32" and e.get("noEncrypt") is True
      and "mountPoint" not in e and str(e["size"]) == "2G"
      and [p.get("mountPoint") for p in lay[1:]] == ["/boot", "/"])
print("OK" if ok else repr(lay))
PY
)"
	[ "$V" = OK ] && ok "LEXOS (fat32, 2G, sans mountPoint, jamais chiffrée) puis /boot puis /" || non "partitionLayout inattendu : $V"
fi
env PATH="/usr/bin:/bin" sh "$H/hook.sh" >/dev/null 2>&1
[ "$(grep -c 'name: "LEXOS"' "$H/etc/calamares/modules/partition.conf")" = 1 ] && ok "rejoué : une seule entrée LEXOS" || non "rejoué : entrée LEXOS en double"

# =============================================================================
titre "6. Les autres saveurs gardent le partition.conf livré"
grep -q 'name: "LEXOS"' "$PCONF" && non "le partition.conf LIVRÉ contient LEXOS (toutes les saveurs l'auraient)" \
	|| ok "le partition.conf livré n'a pas d'entrée LEXOS"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" = 0 ]
