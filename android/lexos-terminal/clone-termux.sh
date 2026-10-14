#!/usr/bin/env bash
# Clone officiel de Termux, applique une couche graphique LexOS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PIN="8629e632fcb95da272221be327db653fb24befe9"
TARGET="$PWD/lexos-termux-source"
if [ "$#" -gt 0 ]; then TARGET="$1"; fi
if [ -e "$TARGET" ]; then
  echo "Refus : dossier deja existant : $TARGET" >&2
  exit 1
fi
command -v git >/dev/null || { echo "git requis" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 requis" >&2; exit 1; }
git init "$TARGET"
git -C "$TARGET" remote add origin https://github.com/termux/termux-app.git
git -C "$TARGET" fetch --depth=1 origin "$PIN"
git -C "$TARGET" checkout --detach FETCH_HEAD
python3 "$HERE/style_termux.py" "$TARGET"
echo "Sources de Termux clonees et interface LexOS appliquee."
echo "Prototype SOURCE : ne pas installer cet APK; voir README.md pour package/bootstraps."
