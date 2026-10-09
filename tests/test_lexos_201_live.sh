#!/usr/bin/env bash
# Contrôles de régression des symptômes réellement observés sur la clé USB.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$R/config/hooks/normal/0260-lexos-nvidia.hook.chroot"
B="$R/config/hooks/normal/0412-lexos-demarrage-graphique.hook.chroot"
A="$R/auto/config"
S="$R/config/includes.chroot/usr/share/lexos/shell/interactive.sh"

sh -n "$N" && sh -n "$B" && sh -n "$A"
# Une puce de rétroéclairage (nvidia-wmi-ec-backlight.ko) n'est PAS nvidia.ko.
grep -Fq -- "-name 'nvidia.ko*'" "$N"
! grep -Fq -- "-name 'nvidia*.ko*'" "$N"
# Les traces DKMS ne constituent pas une preuve si le .ko est absent.
grep -Fq "DKMS dit installed" "$N"
# L'ISO Pro doit inclure nvidia-smi avec le vrai module.
grep -Fq 'command -v nvidia-smi' "$N"
# Démarrage normal graphique, fail-safe toujours disponible en console.
grep -Fq 'systemctl set-default graphical.target' "$B"
grep -Fq 'systemctl enable lightdm.service' "$B"
grep -Fq 'systemd.unit=multi-user.target' "$A"
# Les messages « commande inconnue » viennent de Bash sur commande ABSENTE
# (command_not_found_handle) : lexsh est un vrai shell et ne bloque pas nvidia-smi.
grep -Fq 'command_not_found_handle()' "$S"
# Exécuter le hook sur une racine temporaire : aucun systemctl de l'hôte.
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/etc/lexos" "$T/usr/sbin" "$T/usr/bin" "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/usr/sbin/lightdm"
cp "$T/usr/sbin/lightdm" "$T/usr/bin/startxfce4"
chmod +x "$T/usr/sbin/lightdm" "$T/usr/bin/startxfce4"
sed "s|/etc/lexos|$T/etc/lexos|g; s|/usr/sbin/lightdm|$T/usr/sbin/lightdm|g; s|/usr/bin/startxfce4|$T/usr/bin/startxfce4|g" "$B" > "$T/hook.sh"
cat > "$T/bin/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$1" in
    set-default) [ "${TEST_FAIL:-}" != set-default ] ;;
    enable) [ "${TEST_FAIL:-}" != enable ] ;;
    get-default) printf '%s\n' "${TEST_TARGET:-graphical.target}" ;;
    is-enabled) printf '%s\n' "${TEST_ENABLED:-enabled}" ;;
    *) exit 97 ;;
esac
SH
chmod +x "$T/bin/systemctl"
export TEST_CALLS="$T/calls"
export PATH="$T/bin:$PATH"
: > "$TEST_CALLS"
sh "$T/hook.sh" > "$T/log"
[ ! -s "$TEST_CALLS" ]
printf 'LEXOS_FLAVOUR="standard"\n' > "$T/etc/lexos/build.conf"
sh "$T/hook.sh" > "$T/log"
[ ! -s "$TEST_CALLS" ]
printf 'LEXOS_FLAVOUR="pro"\n' > "$T/etc/lexos/build.conf"
sh "$T/hook.sh" > "$T/log"
printf 'set-default graphical.target\nenable lightdm.service\nget-default\nis-enabled lightdm.service\n' > "$T/expected"
cmp "$T/expected" "$TEST_CALLS"
for mode in set-default enable; do
    if TEST_FAIL="$mode" sh "$T/hook.sh" > "$T/log" 2>&1; then
        echo "ÉCHEC : erreur systemctl $mode ignorée" >&2; exit 1
    fi
done
if TEST_TARGET=multi-user.target sh "$T/hook.sh" > "$T/log" 2>&1; then exit 1; fi
if TEST_ENABLED=disabled sh "$T/hook.sh" > "$T/log" 2>&1; then exit 1; fi
rm "$T/usr/bin/startxfce4"
: > "$TEST_CALLS"
if sh "$T/hook.sh" > "$T/log" 2>&1; then exit 1; fi
[ ! -s "$TEST_CALLS" ]
mv "$T/usr/sbin/lightdm" "$T/usr/bin/startxfce4"
if sh "$T/hook.sh" > "$T/log" 2>&1; then exit 1; fi
[ ! -s "$TEST_CALLS" ]

# Jouer aussi la décision finale NVIDIA, après nettoyage des paquets.
sed -n '/^if verifie_module >\/dev\/null 2>&1; then/,$p' "$N" > "$T/final.sh"
grep -q 'conf_pose LEXOS_NVIDIA_ETAT "ok"' "$T/final.sh"
final() {
    MODULE="$1" SMI="$2" LEXOS_NVIDIA_FACULTATIF="$3" sh -c '
        conf_pose() { printf "%s=%s\n" "$1" "$2"; }
        verifie_module() { [ "$MODULE" = oui ]; }
        command() { [ "$SMI" = oui ]; }
        VERSION=test REUSSITE=test
        . "$1"
    ' sh "$T/final.sh" > "$T/state" 2>&1
}
final oui oui 0
grep -q '^LEXOS_NVIDIA_ETAT=ok$' "$T/state"
if final non oui 0; then exit 1; fi
grep -q '^LEXOS_NVIDIA_MODULE=non$' "$T/state"
grep -q '^LEXOS_NVIDIA_ETAT=absent$' "$T/state"
final non oui 1
grep -q '^LEXOS_NVIDIA_ETAT=absent-accepte$' "$T/state"
for optional in 0 1; do
    if final oui non "$optional"; then exit 1; fi
    grep -q '^LEXOS_NVIDIA_ETAT=absent$' "$T/state"
done
echo "OK : contrôles LexOS Pro 2.0.1 (NVIDIA, démarrage, shell)"
