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
echo "OK : contrôles LexOS Pro 2.0.1 (NVIDIA, démarrage, shell)"
