#!/usr/bin/env bash
# Contrôle isolé : génère les profils sans session X ni vrais pilotes NVIDIA.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
OUTIL="$R/config/includes.chroot/usr/share/lexos/picom/lexos-effets"
bash -n "$OUTIL"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/tv.conf" <<'EOF'
backend = "glx";
vsync = true;
shadow-radius = 6;
shadow-opacity = 0.6;
shadow-color = "#000000";

animations = (
    {
       triggers = [ "close" ];
       opacity = { duration = 0.30; start = 1; end = 0; };
    }
);

#  ═══ CE QUI NE DOIT PAS S'ÉTEINDRE COMME UN TÉLÉVISEUR ═══
rules = (
    { match = "name = 'Volet LexOS'"; shadow = true; }
);
EOF
cat > "$T/bin/glxinfo" <<'SH'
#!/bin/sh
printf 'name of display: :99\nOpenGL vendor string: NVIDIA Corporation\nOpenGL renderer string: NVIDIA GeForce RTX 5060\n'
SH
cat > "$T/bin/picom" <<'SH'
#!/bin/sh
if [ "${1:-}" = --version ]; then echo v12.5; exit 0; fi
echo "picom ne doit pas tourner dans ce banc" >&2
exit 1
SH
cat > "$T/bin/xfconf-query" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$T/bin/lexos-crt" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$T/bin/"*
export XDG_CONFIG_HOME="$T/foyer"
export DISPLAY=:99
export XDG_SESSION_TYPE=x11
export PATH="$T/bin:$PATH"
export LEXOS_EFFETS_SOURCE="$T/tv.conf"
export LEXOS_EFFETS_CRT="$T/bin/lexos-crt"

sha_before="$(sha256sum "$T/tv.conf" | cut -d ' ' -f 1)"
bash "$OUTIL" installer
sha_after="$(sha256sum "$T/tv.conf" | cut -d ' ' -f 1)"
[ "$sha_before" = "$sha_after" ] || {
    echo "Le CRT original a été modifié" >&2; exit 1;
}
for p in fluide hologramme neon portail; do
    f="$XDG_CONFIG_HOME/lexos/effets/$p.conf"
    test -s "$f"
    grep -Fq 'backend = "glx";' "$f"
    grep -Fq 'rules = (' "$f"
    grep -Fq 'triggers = [ "open" ];' "$f"
    grep -Fq 'triggers = [ "close" ];' "$f"
    grep -Fq 'offset-x = "(1 - scale-x) * window-width / 2";' "$f"
    grep -Fq 'opacity = {' "$f"
done
grep -Fq 'shadow-color = "#ff8428";' "$XDG_CONFIG_HOME/lexos/effets/neon.conf"
grep -Fq 'start = 0.08;' "$XDG_CONFIG_HOME/lexos/effets/portail.conf"
test ! -e "$XDG_CONFIG_HOME/lexos/effets/crt.conf"
grep -Fq "Exec=" "$XDG_CONFIG_HOME/autostart/lexos-effets.desktop"
grep -Fq "OnlyShowIn=XFCE;" "$XDG_CONFIG_HOME/autostart/lexos-effets.desktop"

# Un fichier source non reconnu doit échouer sans endommager le profil original.
printf 'format inconnu\n' > "$T/invalide.conf"
export LEXOS_EFFETS_SOURCE="$T/invalide.conf"
if bash "$OUTIL" installer >/dev/null 2>&1; then
    echo "Le générateur accepte une config CRT inconnue" >&2; exit 1;
fi
printf '✓ Tests de génération des effets LexOS : OK\n'
