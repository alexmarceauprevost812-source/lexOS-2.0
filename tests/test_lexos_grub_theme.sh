#!/usr/bin/env bash
# Le nouveau fond ne contient aucun cadre de menu : vérifier la boîte GRUB.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import hashlib, re, sys, struct
r=Path(sys.argv[1]); b=r/'config/includes.binary/boot/grub/themes/lexos'; c=r/'config/includes.chroot/usr/share/grub/themes/lexos'
for p in b.rglob("*"):
    if not p.is_file(): continue
    assert p.read_bytes()==(c/p.relative_to(b)).read_bytes(),p.name
image=(b/'background.png').read_bytes()
assert image[:8]==b'\x89PNG\r\n\x1a\n'
assert hashlib.sha256(image).hexdigest()==(r/'docs/grub-background.sha256').read_text().split()[0]
txt=(b/'theme.txt').read_text(); menu=re.search(r'\+ boot_menu \{(.*?)\}',txt,re.S).group(1)
def value(key): return re.search(r'^\s*'+key+r'\s*=\s*(.+)',menu,re.M).group(1).strip()
left,top,width,height=[int(value(k).rstrip('%')) for k in ('left','top','width','height')]
assert 2*left+width==100
assert 'menu_box_*.png' in value('menu_pixmap_style')
assert value('scrollbar')=='true'
assert value('item_color')=='"#ffffff"'
for w,h in [(1920,1080),(1280,720),(1024,768),(1920,1200),(2560,1440),(3840,2160)]:
    assert left*w//100+width*w//100<=w
    assert top*h//100+height*h//100<=h
    assert (height*h//100)//(int(value('item_height'))+int(value('item_spacing')))>=6
# Le centre noir du panneau est indépendant de la luminosité du fond.
from PIL import Image
with Image.open(b/'menu_box_c.png') as im:
    assert all(px[:3]==(0,0,0) and (len(px)<4 or px[3]==255) for px in im.convert('RGBA').getdata())
hook=(r/'config/hooks/normal/0910-lexos-grub-theme.hook.binary').read_text()
for key in ['set gfxmode=', 'set theme=', 'set timeout=8','set timeout_style=menu']:
    assert key in hook,key
print('OK : fond approuvé, copies identiques, menu centré, panneau opaque, six lignes aux six résolutions, défilement et délai.')
PY
