#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Version nécessaire}"
OUT="${2:?Dossier de sortie nécessaire}"
[[ "$VERSION" =~ ^[0-9]{14}\+[0-9a-f]{7,40}$ ]] || exit 1
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/lib" "$STAGE/usr/share" "$STAGE/etc/xdg/autostart"
cp -a "$ROOT/config/includes.chroot/usr/bin" "$STAGE/usr/"
cp -a "$ROOT/config/includes.chroot/usr/lib/lexos" "$STAGE/usr/lib/"
for dir in lexos icons applications bash-completion; do
    cp -a "$ROOT/config/includes.chroot/usr/share/$dir" "$STAGE/usr/share/"
done
python3 - "$STAGE/usr/share/icons/LexOS" <<'PY'
import pathlib, sys
theme = pathlib.Path(sys.argv[1])
dirs = sorted(p for category in ('apps', 'places', 'devices')
              for p in (theme/category).glob('*') if p.is_dir() and any(p.iterdir()))
lines = ['[Icon Theme]', 'Name=LexOS', 'Inherits=Papirus-Dark,Papirus,Adwaita,hicolor',
         'Directories='+','.join(str(p.relative_to(theme)) for p in dirs)]
for path in dirs:
    relative = str(path.relative_to(theme))
    context = {'apps': 'Applications', 'places': 'Places', 'devices': 'Devices'}[path.parent.name]
    lines += ['', '['+relative+']', 'Context='+context]
    if path.name == 'scalable':
        lines += ['Size=512', 'MinSize=8', 'MaxSize=512', 'Type=Scalable']
    else:
        lines += ['Size='+path.name.split('x')[0], 'Type=Fixed']
(theme/'index.theme').write_text('\n'.join(lines)+'\n')
PY
mkdir -p "$STAGE/usr/share/lexos/branding"
cp -a "$ROOT/branding/." "$STAGE/usr/share/lexos/branding/"
cp "$ROOT/config/includes.chroot/etc/skel/.config/autostart/lexos-overview-button.desktop" "$STAGE/etc/xdg/autostart/"
chmod +x "$STAGE/usr/bin/"*
python3 - "$STAGE" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for directory in (root/'usr/bin', root/'usr/lib/lexos'):
    for path in directory.rglob('*'):
        if path.is_file() and not path.is_symlink():
            data = path.read_bytes()
            if path.suffix in ('.py', '.sh') or data.startswith(b'#!'):
                path.write_bytes(data.replace(b'\r\n', b'\n'))
PY
for source in "$ROOT"/branding/icon-*.svg "$ROOT"/branding/icon-*.png; do
    name="$(basename "$source")"; name="${name%.*}"; name="lexos-${name#icon-}"
    for size in 16 22 24 32 48 64 128 256; do
        dest="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "$dest"
        case "$source" in
            *.svg) rsvg-convert -w "$size" -h "$size" -o "$dest/$name.png" "$source" ;;
            *.png) convert "$source" -resize "${size}x${size}" -background none -gravity center -extent "${size}x${size}" "$dest/$name.png" ;;
        esac
    done
done
cat > "$STAGE/usr/share/applications/lexos-applications.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Bureaux et applications
Exec=lexos-overview
Icon=lexos-applications
Categories=System;Utility;
Terminal=false
EOF
cat > "$STAGE/usr/share/applications/lexos-nvidia.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Paramètres NVIDIA
Exec=nvidia-settings
Icon=nvidia-settings
Categories=Settings;HardwareSettings;
Terminal=false
EOF
cat > "$STAGE/DEBIAN/control" <<EOF
Package: lexos-system
Version: $VERSION
Architecture: amd64
Maintainer: LexOS <263750361+alexmarceauprevost812-source@users.noreply.github.com>
Depends: python3, python3-pyside6.qtwidgets, python3-pyside6.qtwebenginewidgets, wmctrl, libglib2.0-bin, util-linux, nvidia-settings
Description: Applications et interface de LexOS Pro
 Mise à jour des fichiers LexOS sans réinstaller le système Debian.
EOF
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/LexOS || true
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi
EOF
chmod 755 "$STAGE/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT/lexos-system_${VERSION}_amd64.deb"
