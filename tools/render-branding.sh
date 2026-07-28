#!/usr/bin/env bash
# =============================================================================
#  render-branding.sh — rend les SVG de branding/ en PNG (aperçu local)
# =============================================================================
#  Utile pour regarder le fond d'écran et le logo sans construire l'ISO entière.
#  Exige rsvg-convert (paquet librsvg2-bin) ou ImageMagick.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-preview}"
cd "$ROOT"
mkdir -p "$OUT"

if command -v rsvg-convert >/dev/null 2>&1; then
	R() { rsvg-convert -w "$1" -h "$2" -o "$4" "$3"; }
elif command -v convert >/dev/null 2>&1; then
	R() { convert -background none -resize "${1}x${2}" "$3" "$4"; }
else
	echo "Installe librsvg2-bin (rsvg-convert) ou imagemagick." >&2
	exit 1
fi

R 1920 1080 branding/wallpaper.svg     "$OUT/wallpaper.png"
R 1920 1080 branding/wallpaper-crt.svg "$OUT/wallpaper-crt.png"
R  512  512 branding/logo.svg          "$OUT/logo-512.png"
R  128  128 branding/logo.svg          "$OUT/logo-128.png"
R  640  480 config/bootloaders/isolinux/splash.svg "$OUT/boot-splash.png"

printf 'Aperçus rendus dans %s/ :\n' "$OUT"
ls -1 "$OUT"
