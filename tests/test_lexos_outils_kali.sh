#!/usr/bin/env bash
# Vérifie que la simulation ne rafraîchit ni n'installe de paquets.
set -euo pipefail
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-outils-kali"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT
export TRACE_KALI="$BANC/trace"
mkdir "$BANC/bin"
cat > "$BANC/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TRACE_KALI"
[[ "${APT_ECHEC:-0}" = 0 ]]
EOF
cat > "$BANC/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
    sqlmap) printf 'install ok installed' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$BANC/bin/apt-get" "$BANC/bin/dpkg-query"
export PATH="$BANC/bin:$PATH"
bash "$OUTIL" liste > "$BANC/liste"
[[ ! -e "$TRACE_KALI" ]]
bash "$OUTIL" installer reseau --essai > /dev/null
[[ "$(cat "$TRACE_KALI")" = '--simulate --no-remove install nmap wireshark tshark' ]]
if APT_ECHEC=1 bash "$OUTIL" installer wifi --essai > /dev/null; then
    echo 'Échec APT masqué' >&2; exit 1
fi
LIGNES="$(wc -l < "$TRACE_KALI")"
if bash "$OUTIL" installer inconnu --essai 2>/dev/null; then exit 1; fi
if bash "$OUTIL" installer web wifi --essai 2>/dev/null; then exit 1; fi
if bash "$OUTIL" etat --essai 2>/dev/null; then exit 1; fi
[[ "$(wc -l < "$TRACE_KALI")" = "$LIGNES" ]]
bash "$OUTIL" etat web > "$BANC/etat"
grep -q '^sqlmap : installé$' "$BANC/etat"
bash "$OUTIL" etat wifi > "$BANC/etat"
grep -q '^aircrack-ng : non installé$' "$BANC/etat"
printf 'OK : simulation seule, échec APT propagé, arguments rejetés et état des paquets.\n'
