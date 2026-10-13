#!/usr/bin/env bash
# Régression du 12 octobre 2026 : nvidia-smi répondait sur RTX 5060,
# mais les bibliothèques GLX et nvidia_drv.so manquaient. Xorg utilisait
# llvmpipe ; picom v12 échouait sur GLX_EXT_texture_from_pixmap.
# Fixture isolée : n'installe RIEN et n'accède pas au vrai matériel.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$R/config/hooks/normal/0260-lexos-nvidia.hook.chroot"
sh -n "$HOOK"
grep -Fq 'apt-get install -y --no-remove' "$HOOK"
grep -Fq '"nvidia-driver-libs=$VERSION_GL"' "$HOOK"
grep -Fq '"xserver-xorg-video-nvidia=$VERSION_GL"' "$HOOK"
grep -Fq 'libglx-nvidia0' "$HOOK"
grep -Fq 'MODULE_XORG=' "$HOOK"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
sed -n '/^# --- PILOTE XORG/,/^# --- GARDER LA PILE/p' "$HOOK" | sed '1d;$d' > "$T/fragment.sh"
[ -s "$T/fragment.sh" ]
sh -n "$T/fragment.sh"

cat > "$T/bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_APT_LOG"
[ "$MOCK_APT_FAIL" != 1 ]
SH
cat > "$T/bin/dpkg-query" <<'SH'
#!/bin/sh
for arg do paquet="$arg"; done
if [ "$paquet" = "$MOCK_BAD_PKG" ]; then
    printf '%s' '999.0-mauvaise-version'
else
    printf '%s' "$MOCK_VERSION"
fi
SH
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
export MOCK_APT_LOG="$T/apt.log"
export MOCK_VERSION=615.71.09-2
export MOCK_APT_FAIL=0
export MOCK_BAD_PKG=aucun
export MOCK_REUSSITE=ok
export LEXOS_NVIDIA_XORG_MODULE="$T/nvidia_drv.so"
touch "$LEXOS_NVIDIA_XORG_MODULE"

run_guard() (
    REUSSITE="$MOCK_REUSSITE"
    version_pilote_reel() { printf '%s\n' "$MOCK_VERSION"; }
    conf_pose() { printf '%s=%s\n' "$1" "$2" > "$T/result"; }
    . "$T/fragment.sh"
)

: > "$MOCK_APT_LOG"
run_guard
grep -Fxq 'LEXOS_NVIDIA_OPENGL=paquets-valides' "$T/result"
grep -Fq 'nvidia-driver-libs=615.71.09-2' "$MOCK_APT_LOG"
grep -Fq 'xserver-xorg-video-nvidia=615.71.09-2' "$MOCK_APT_LOG"
grep -Fq 'nvidia-driver=615.71.09-2' "$MOCK_APT_LOG"

# Version GLX erronée : la construction DOIT s'arrêter.
if (MOCK_BAD_PKG=libglx-nvidia0; run_guard > /dev/null 2>&1); then
    echo "ÉCHEC : version GLX incorrecte acceptée" >&2; exit 1
fi

# Dépendances impossibles / suppressions refusées : aucune publication.
if (MOCK_APT_FAIL=1; run_guard > /dev/null 2>&1); then
    echo "ÉCHEC : apt a échoué mais la construction continue" >&2; exit 1
fi

# Pilote Xorg réellement absent : refuser même si apt annonce OK.
rm "$LEXOS_NVIDIA_XORG_MODULE"
if run_guard > /dev/null 2>&1; then
    echo "ÉCHEC : Xorg absent accepté" >&2; exit 1
fi

# Aucune pile NVIDIA voulue : ne pas installer de paquet graphique.
: > "$MOCK_APT_LOG"
MOCK_REUSSITE="" run_guard
[ ! -s "$MOCK_APT_LOG" ]
printf '✓ Garde Xorg/GLX RTX5060 : 5 scénarios vérifiés\n'
