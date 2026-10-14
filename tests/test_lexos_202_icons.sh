#!/usr/bin/env bash
# LexOS Pro 2.0.2 : verifier les noms d'icones effectivement demandes par XFCE/GTK.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS="$ROOT/config/includes.chroot/usr/share/icons/LexOS"
for ic in user-trash user-trash-full; do
  test -s "$ICONS/places/scalable/$ic.svg" || { echo "Icone absente : $ic" >&2; exit 1; }
done
for ic in lexos-reglages preferences-system system-settings org.xfce.settings.manager; do
  test -s "$ICONS/apps/scalable/$ic.svg" || { echo "Icone absente : $ic" >&2; exit 1; }
done
grep -q 'Icon=lexos-reglages' "$ROOT/config/hooks/normal/0450-lexos-settings.hook.chroot"
grep -q 'for CAT in apps devices' "$ROOT/config/hooks/normal/0605-lexos-icones.hook.chroot"
grep -q 'LEXOS_VERSION="2.0.2-rtx5060"' "$ROOT/lexos.conf"
if command -v python3 >/dev/null 2>&1; then
  ROOT="$ROOT" python3 - <<'PY'
import os, pathlib, xml.etree.ElementTree as ET
icons=pathlib.Path(os.environ['ROOT'])/'config/includes.chroot/usr/share/icons/LexOS'
for path in (icons/'places/scalable').glob('user-trash*.svg'):
    ET.parse(path)
for path in (icons/'apps/scalable').glob('*.svg'):
    if path.stem in ('lexos-reglages','preferences-system','system-settings','org.xfce.settings.manager'):
        ET.parse(path)
print("OK: XML des icones valide")
PY
fi
echo 'OK: corbeille et Parametres LexOS 2.0.2'
