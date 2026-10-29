# Kit PLAY — sources de PLAY.exe

`PLAY.exe` est le seul fichier visible sous Windows sur la partition FAT32
« LEXOS » d'une clé LexOS nomade. Il demande les droits administrateur
(`play.manifest`), puis lance `.lexos\jouer.ps1`, qui démarre le LexOS de la
clé dans VirtualBox (accès direct aux AUTRES partitions de la clé).

Le kit prêt à poser est dans
`config/includes.chroot/usr/share/lexos/kit-play/` ; c'est
`usr/lib/lexos/kit-play` (minuteur `lexos-kit-play.timer`) qui le recopie
sur la clé.

## Reconstruire PLAY.exe (depuis Linux)

```bash
sudo apt install gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64
cd tools/play-kit
x86_64-w64-mingw32-windres play.rc -O coff -o play.res
x86_64-w64-mingw32-gcc -municode -mwindows -Os -s play.c play.res -o PLAY.exe
cp PLAY.exe ../../config/includes.chroot/usr/share/lexos/kit-play/PLAY.exe
cp play.ico ../../config/includes.chroot/usr/share/lexos/kit-play/.lexos/lexos.ico
```

`play-1024.png` est l'image source de l'icône (`play.ico`).
