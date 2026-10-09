#!/usr/bin/env bash
# Audit de l'arbre d'ISO, sans accès aux disques ni à la NVRAM de l'hôte.
set -euo pipefail
root="${1:-.}"
command -v sbverify >/dev/null || { echo 'sbsigntool requis'; exit 1; }
efi="$root/binary/EFI/boot"
[[ -d $efi ]] || efi="$root/binary/efi/boot"
for name in bootx64.efi grubx64.efi; do
    file=$(find "$efi" -maxdepth 1 -iname "$name" -type f -print -quit)
    [[ -n $file ]] || { echo "EFI signé manquant : $name"; exit 1; }
    report=$(sbverify --list "$file" 2>&1)
    printf '%s\n%s\n' "$file" "$report"
    [[ $report == *'signature 1'* ]] || { echo 'Signature PE absente'; exit 1; }
done
kernel=$(find "$root/binary/live" -maxdepth 1 -name 'vmlinuz*' -type f -print -quit)
[[ -n $kernel ]] || { echo 'Noyau live absent'; exit 1; }
report=$(sbverify --list "$kernel" 2>&1)
printf '%s\n%s\n' "$kernel" "$report"
[[ $report == *'signature 1'* ]] || { echo 'Signature noyau absente'; exit 1; }
printf 'Signatures présentes; confiance UEFI, SBAT et chargement NVIDIA restent à tester.\n'
printf 'Certificat DKMS public :\n'
find "$root/chroot/var/lib/dkms" -name 'mok.pub' -type f -print 2>/dev/null || true
# Ne jamais lire, copier ni afficher une clé privée dans les journaux.
