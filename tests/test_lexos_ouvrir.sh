#!/usr/bin/env bash
# =============================================================================
#  Éprouver « ce qu'on télécharge s'installe sans terminal » — et l'agent
#  d'authentification sans lequel tous les boutons d'administration sont muets
# =============================================================================
#  ALEX, deux demandes du même jour :
#    « peux-tu faire aussi que tout ce qu'on télécharge, on puisse les exécuter
#      comme Windows, pas avoir besoin de passer par le terminal tout le temps »
#    « quand on télécharge, l'application soit déjà installée au lieu de passer
#      par le terminal »
#  et, sur son vieil ordinateur :
#    « les boutons dans les paramètres ne fonctionnaient pas »
#
#  ══ CE QUE CE BANC SURVEILLE, ET CE QUE CHAQUE POINT A COÛTÉ ══
#
#  1. LE FORMAT SE LIT DANS LES OCTETS, PAS DANS LE NOM. Un fichier téléchargé
#     porte le nom que le serveur a bien voulu. Et « file --mime-type » ne peut
#     pas servir de référence : mesuré, il annonce une AppImage comme
#     « application/x-pie-executable » — un type qui n'existe même pas dans
#     shared-mime-info — et un .rpm comme « text/plain ».
#
#  2. RIEN NE S'EXÉCUTE SANS ACCORD. C'est la doctrine écrite de la maison
#     (lexos-run-ins:9-23) : « Il n'y a pas de mode "ne plus demander". Ce
#     serait la seule option vraiment dangereuse de tout LexOS. » Rendre
#     l'installation cliquable ne lève pas cette règle. Le banc fabrique un
#     script PIÈGE qui laisse une trace, et vérifie qu'il ne laisse RIEN tant
#     que le mot n'a pas été tapé.
#
#  3. LE PIÈGE QUI REND UNE ASSOCIATION MUETTE : GIO IGNORE EN SILENCE un
#     .desktop dont le programme « Exec= » n'existe pas. Il ne le dit nulle
#     part, et update-desktop-database l'inscrit quand même dans
#     mimeinfo.cache — on croit l'association posée, et « gio mime » répond
#     « No default applications ». Le banc vérifie donc que le programme
#     nommé par Exec= existe VRAIMENT dans l'ISO.
#
#  4. L'AGENT POLKIT. Le dépôt affirmait, pour justifier de n'en nommer aucun,
#     que « l'agent qui affiche les demandes de mot de passe arrive par les
#     Recommends de xfce4-session ». C'est faux — ces Recommends ne nomment
#     que dbus, logind, un économiseur d'écran, upower, xfdesktop4 et xfwm4.
#     Sans agent, pkexec échoue SANS FENÊTRE ET SANS MESSAGE : tous les
#     boutons d'administration des Paramètres sont muets. C'est le symptôme
#     décrit. Le banc refuse que cette phrase revienne, exige que des
#     candidats soient nommés, et exige que le moteur DISE le motif au lieu
#     de lancer un pkexec qui échouera en silence.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-ouvrir"
BUREAU="$RACINE/config/includes.chroot/usr/share/applications/lexos-ouvrir.desktop"
AGENT="$RACINE/config/includes.chroot/usr/lib/lexos/polkit-agent"
AUTOSTART="$RACINE/config/includes.chroot/etc/xdg/autostart/lexos-polkit-agent.desktop"
HOOK="$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot"
LISTE="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages/15-essentiel.list"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
COMPLETION="$RACINE/config/includes.chroot/usr/share/bash-completion/completions/lexos"
DEFAUT="$RACINE/config/includes.chroot/usr/bin/lexos-defaut"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

#  Le banc ne doit JAMAIS toucher au vrai foyer : lexos-ouvrir écrit dans
#  ~/Applications et ~/.local/share/applications. Les deux coutures les
#  déplacent dans le décor.
export LEXOS_APPIMAGE_DIR="$BANC/foyer/Applications"
export LEXOS_APPS_LOCAL_USER="$BANC/foyer/.local/share/applications"
mkdir -p "$LEXOS_APPIMAGE_DIR" "$LEXOS_APPS_LOCAL_USER"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$BUREAU" "$AGENT" "$AUTOSTART" "$HOOK" "$LISTE" "$MOTEUR" \
         "$DISPATCH" "$COMPLETION" "$DEFAUT"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

#  Sans DISPLAY, lexos-ouvrir prend le chemin terminal : c'est celui qu'on peut
#  éprouver sans écran, et c'est le même garde-fou.
sans_ecran() { env -u DISPLAY -u WAYLAND_DISPLAY "$@"; }

# =============================================================================
titre "1. LE FORMAT SE LIT DANS LES OCTETS, PAS DANS LE NOM"
# =============================================================================
D="$BANC/fichiers"; mkdir -p "$D"
python3 - "$D" <<'PY' 2>/dev/null
import os, sys
d = sys.argv[1]
def ecrire(nom, octets):
    with open(os.path.join(d, nom), "wb") as f:
        f.write(octets)

#  AppImage : ELF, « AI » (0x41 0x49) aux octets 8-9, type à l'octet 10.
elf = bytearray(b'\x7fELF\x02\x01\x01\x00' + b'\x00' * 56)
elf[8], elf[9], elf[10] = 0x41, 0x49, 0x02
ecrire("appli.AppImage", bytes(elf) + b'squashfs')
elf[10] = 0x01
ecrire("vieille.AppImage", bytes(elf) + b'iso9660')
#  … et la MÊME AppImage sans extension : le nom ne doit rien changer.
elf[10] = 0x02
ecrire("sans-nom-parlant", bytes(elf) + b'squashfs')
#  Un ELF ordinaire : surtout PAS reconnu comme AppImage.
ecrire("binaire", bytes(bytearray(b'\x7fELF\x02\x01\x01\x00' + b'\x00' * 56)))
#  .deb : archive « ar » dont la première entrée est « debian-binary ».
ecrire("paquet.deb", b'!<arch>\n' + b'debian-binary   1700000000  0     0     100644  4         `\n2.0\n')
#  … et le même sans extension.
ecrire("paquet-sans-nom", b'!<arch>\n' + b'debian-binary   1700000000  0     0     100644  4         `\n2.0\n')
#  Une archive « ar » qui n'est PAS un .deb.
ecrire("biblio.a", b'!<arch>\n' + b'objet.o/        1700000000  0     0     100644  4         `\n')
ecrire("paquet.rpm", b'\xed\xab\xee\xdb' + b'\x00' * 40)
ecrire("script.sh", b'#!/bin/sh\necho salut\n')
ecrire("appli.flatpakref", b'[Flatpak Ref]\nName=org.exemple.App\n')
ecrire("depot.flatpakrepo", b'[Flatpak Repo]\nUrl=https://exemple\n')
ecrire("mystere.dat", b'\x00\x01\x02\x03n-importe-quoi')
#  Un .run sans la moindre signature : le SEUL cas où le nom est tout ce
#  qu'on a. Il n'existe aucun motif « .run » dans toute la base MIME du
#  système — vérifié : aucune ligne « run » dans /usr/share/mime/globs.
ecrire("installeur.run", b'#!/bin/sh\n# auto-extractible\n')
PY
printf 'a' > "$D/a.txt"
( cd "$D" && tar czf arch.tar.gz a.txt 2>/dev/null && tar cf arch.tar a.txt 2>/dev/null )
command -v zip >/dev/null 2>&1 && ( cd "$D" && zip -q arch.zip a.txt )

attendu() { # $1 = fichier, $2 = sorte attendue, $3 = pourquoi
	local vu
	vu="$(sans_ecran bash "$OUTIL" --quoi "$D/$1" 2>/dev/null)"
	if [ "$vu" = "$2" ]; then
		ok "$3"
	else
		non "$1 : lu « $vu » au lieu de « $2 » — $3"
	fi
}
attendu paquet.deb        deb         "un .deb est reconnu"
attendu paquet-sans-nom   deb         "…et même SANS extension : c'est le contenu qui parle"
attendu biblio.a          archive     "une archive « ar » qui n'est pas un .deb ne passe pas pour un paquet"
attendu appli.AppImage    appimage    "une AppImage de type 2 est reconnue"
attendu vieille.AppImage  appimage    "…et une de type 1 aussi (la majorité de celles en circulation)"
attendu sans-nom-parlant  appimage    "…et sans extension : le nom ne décide de rien"
attendu binaire           programme   "un ELF ordinaire n'est PAS pris pour une AppImage"
attendu paquet.rpm        rpm         "un .rpm est reconnu — pour pouvoir dire qu'il n'est pas pour LexOS"
attendu script.sh         script      "un script à shebang est reconnu"
attendu installeur.run    script      "un .run est traité comme un script (aucune signature n'existe pour lui)"
attendu appli.flatpakref  flatpakref  "un .flatpakref est reconnu"
attendu depot.flatpakrepo flatpakrepo "un .flatpakrepo est reconnu"
attendu arch.tar.gz       archive     "une archive part vers l'outil d'archives, pas vers un installeur"
attendu arch.tar          archive     "…un tar simple aussi (« ustar » à l'octet 257)"
attendu mystere.dat       inconnu     "devant un format inconnu on ne devine RIEN"
if [ -f "$D/arch.zip" ]; then
	attendu arch.zip archive "…un .zip aussi"
else
	saute "zip absent : le .zip n'a PAS été éprouvé"
fi

#  ET LA RECONNAISSANCE NE DOIT PAS ÉCRIRE SUR LA SORTIE D'ERREUR. Un
#  avertissement de bash à chaque double-clic (« ignored null byte in input »)
#  finit dans le journal de session de tout le monde.
BRUIT="$(sans_ecran bash "$OUTIL" --quoi "$D/binaire" 2>&1 >/dev/null)"
[ -z "$BRUIT" ] \
	&& ok "aucun bruit sur la sortie d'erreur en lisant un binaire" \
	|| non "la reconnaissance écrit sur la sortie d'erreur : $BRUIT"

# =============================================================================
titre "2. RIEN NE S'EXÉCUTE SANS ACCORD — la doctrine de la maison"
# =============================================================================
TRACE="$BANC/JE-SUIS-PARTI"
cat > "$D/piege.sh" <<PIEGE
#!/bin/sh
touch "$TRACE"
PIEGE
chmod +x "$D/piege.sh"

essai_script() { # $1 = ce qu'on tape, $2 = trace attendue (oui/non), $3 = libellé
	rm -f "$TRACE"
	printf '%s\n' "$1" | sans_ecran bash "$OUTIL" "$D/piege.sh" >/dev/null 2>&1
	if [ "$2" = "non" ]; then
		[ ! -e "$TRACE" ] && ok "$3" || non "$3 — LE SCRIPT A TOURNÉ"
	else
		[ -e "$TRACE" ] && ok "$3" || non "$3 — le script n'a PAS tourné"
	fi
}
essai_script $'non'          non "on refuse la première question : rien ne tourne"
essai_script $'\n'           non "on appuie sur Entrée sans rien taper : rien ne tourne"
essai_script $'oui\noui'     non "on accepte de VOIR, puis on tape « oui » au lieu de « lancer » : rien ne tourne"
essai_script $'oui\nLANCER'  non "« LANCER » en majuscules ne compte pas : rien ne tourne"
essai_script $'oui\nlancer'  oui "« lancer » écrit exactement : là, il tourne"
#  UNE INVERSION BANALE — « accepter seulement "oui" » DEVENU « refuser
#  seulement "non" » — doit rougir ce banc. Une seule réponse ne suffit pas :
#  mesuré, "ok" seul repasse par la 2ᵉ porte (« lancer ») qui, elle, annule
#  sur EOF — donc "ok" seul ne tue pas la mutation. Il faut la paire.
essai_script $'ok\nlancer'   non "« ok » n'est pas un accord à la 1ʳᵉ question : rien ne tourne"
rm -f "$TRACE"

#  LE MOT EST DANS LE CODE, ET IL N'Y A PAS DE PORTE DÉROBÉE.
SANS_COM="$BANC/outil-nu"
sed 's/#.*$//' "$OUTIL" > "$SANS_COM"
grep -q '"lancer"' "$SANS_COM" \
	&& ok "le mot « lancer » est exigé dans le code, pas seulement dans le texte" \
	|| non "le mot « lancer » n'apparaît plus dans le code"
grep -qiE 'ne_plus_demander|nplusdemander|--force|--sans-question|--yes' "$SANS_COM" \
	&& non "une option contourne la confirmation — c'est précisément ce que le dépôt interdit" \
	|| ok "aucune option ne contourne la confirmation"

#  ET LE BOUTON QUI AGIT PORTE LA CONSÉQUENCE, jamais « OK ». C'est le
#  précédent de lexos-format:180 (« Tout effacer et formater »).
if grep -q -- '--ok-label' "$SANS_COM"; then
	if grep -qE -- '--ok-label="?(OK|Ok|ok)"?' "$SANS_COM"; then
		non "un bouton dit « OK » : il doit dire ce qu'il fait"
	else
		ok "chaque bouton qui agit porte sa conséquence dans son libellé"
	fi
	grep -q -- '--default-cancel' "$SANS_COM" \
		&& ok "le refus est le bouton par défaut" \
		|| non "le refus n'est pas le bouton par défaut"
else
	non "aucune boîte de dialogue graphique : le double-clic n'aurait rien pour demander"
fi

#  UN .deb NE DOIT PAS S'INSTALLER SANS ACCORD NON PLUS. On lui donne un faux
#  apt-get qui NOTE au lieu d'installer, et on refuse — sur DEUX réponses
#  différentes : "non" seul ne tuerait pas la même inversion de porte que
#  ci-dessus (« accepter seulement "oui" » -> « refuser seulement "non" »).
mkdir -p "$BANC/bin"
cat > "$BANC/bin/apt-get" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$BANC/apt-appels"
SH
chmod +x "$BANC/bin/apt-get"
for R in non ok; do
	: > "$BANC/apt-appels"
	printf '%s\n' "$R" | env -u DISPLAY -u WAYLAND_DISPLAY PATH="$BANC/bin:$PATH" \
		bash "$OUTIL" "$D/paquet.deb" >/dev/null 2>&1
	[ ! -s "$BANC/apt-appels" ] \
		&& ok "un paquet non accepté (« $R ») n'appelle jamais apt" \
		|| non "apt a été appelé sur « $R » : $(cat "$BANC/apt-appels")"
done

#  UNE AppImage REFUSÉE NE DOIT RIEN COPIER.
printf 'non\n' | sans_ecran bash "$OUTIL" "$D/appli.AppImage" >/dev/null 2>&1
[ -z "$(ls -A "$LEXOS_APPIMAGE_DIR" 2>/dev/null)" ] \
	&& ok "une AppImage refusée n'est pas copiée" \
	|| non "une AppImage a été copiée alors qu'on avait refusé"

#  … ET ACCEPTÉE, ELLE DOIT ARRIVER AU MENU. C'est ce qui manquait à
#  lexos-run-ins:140-145 : il copiait dans ~/Applications, un dossier que rien
#  d'autre dans le dépôt ne connaît, et disait « lance-la depuis Fichiers ».
printf 'oui\n' | sans_ecran bash "$OUTIL" "$D/appli.AppImage" >/dev/null 2>&1
if [ -x "$LEXOS_APPIMAGE_DIR/appli.AppImage" ]; then
	ok "une AppImage acceptée est copiée ET rendue exécutable"
else
	non "l'AppImage n'a pas été copiée, ou pas rendue exécutable"
fi
if ls "$LEXOS_APPS_LOCAL_USER"/*.desktop >/dev/null 2>&1; then
	ok "…et elle entre dans le menu (un .desktop est écrit)"
	D_APP="$(ls "$LEXOS_APPS_LOCAL_USER"/*.desktop | head -1)"
	grep -q "^Exec=.*appli.AppImage" "$D_APP" \
		&& ok "…dont le Exec= pointe sur la copie, pas sur le fichier téléchargé" \
		|| non "le .desktop du menu ne pointe pas sur la copie"
else
	non "aucun .desktop écrit : l'AppImage n'apparaîtra nulle part"
fi
#  Aucun fichier « .part » ne doit rester : une copie interrompue ne doit pas
#  laisser d'exécutable à moitié écrit (précédent lexos-install-chrome:39-50).
[ -z "$(ls "$LEXOS_APPIMAGE_DIR"/*.part 2>/dev/null)" ] \
	&& ok "aucune copie partielle laissée derrière" \
	|| non "un fichier .part traîne dans le dossier des applications"

#  UN NOM D'AppImage AVEC DES CARACTÈRES PIÉGÉS NE DOIT PAS PRODUIRE UNE
#  ENTRÉE DE MENU MORTE. printf %q cite pour bash ; le format key-file du
#  .desktop, lui, n'admet que \s \n \t \r \\ — tout le reste (espace, \(,
#  \", \$…) rend la valeur ININTERPRÉTABLE et GIO laisse l'entrée sans Exec,
#  en silence. On ne peut pas s'appuyer sur un vrai GLib ici (python3-gi est
#  cassé dans ce bac à sable, comme il l'était pendant la revue) : on
#  réimplémente donc les DEUX règles réelles (décodage key-file, puis
#  g_shell_parse_argv pour une valeur entre guillemets doubles) et on
#  vérifie que le chemin RESSORT identique à ce qu'on a copié.
cat > "$BANC/decode_desktop_entry.py" <<'PY'
import sys

def decode_keyfile(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\':
            if i + 1 >= len(s):
                raise ValueError("barre oblique inverse en fin de valeur")
            n = s[i+1]
            m = {'s': ' ', 'n': '\n', 't': '\t', 'r': '\r', '\\': '\\'}
            if n not in m:
                raise ValueError("échappement key-file invalide: \\%s" % n)
            out.append(m[n]); i += 2
        else:
            out.append(c); i += 1
    return ''.join(out)

def shell_parse_argv0_dquote(s):
    assert s.startswith('"'), "la valeur ne commence pas par un guillemet double"
    out, i = [], 1
    while i < len(s):
        c = s[i]
        if c == '"':
            return out and ''.join(out)
        if c == '\\' and i + 1 < len(s) and s[i+1] in '"$`\\':
            out.append(s[i+1]); i += 2
        else:
            out.append(c); i += 1
    raise ValueError("guillemet fermant manquant")

fichier, attendu = sys.argv[1], sys.argv[2]
brut = open(fichier, encoding="utf-8").read()
ligne = next((l[len("Exec="):] for l in brut.splitlines() if l.startswith("Exec=")), None)
if ligne is None:
    print("NON : aucune ligne Exec= dans %s" % fichier); sys.exit(1)
try:
    argv0 = shell_parse_argv0_dquote(decode_keyfile(ligne))
except Exception as e:
    print("NON : %s (Exec=%s)" % (e, ligne)); sys.exit(1)
if argv0 == attendu:
    print("OK"); sys.exit(0)
print("NON : décodé « %s », attendu « %s » (Exec=%s)" % (argv0, attendu, ligne)); sys.exit(1)
PY
essai_nom_piege() { # $1 = nom de fichier piégé
	local nom="$1" dest desktop res
	rm -f "$LEXOS_APPS_LOCAL_USER"/*.desktop
	cp -- "$D/appli.AppImage" "$D/$nom"
	printf 'oui\n' | sans_ecran bash "$OUTIL" "$D/$nom" >/dev/null 2>&1
	dest="$LEXOS_APPIMAGE_DIR/$nom"
	desktop="$(ls "$LEXOS_APPS_LOCAL_USER"/*.desktop 2>/dev/null | head -1)"
	if [ -z "$desktop" ]; then
		non "aucune AppImage nommée « $nom » : aucun .desktop écrit"
		return
	fi
	res="$(python3 "$BANC/decode_desktop_entry.py" "$desktop" "$dest" 2>&1)"
	if [ "$res" = "OK" ] && [ -x "$dest" ]; then
		ok "« $nom » : l'entrée de menu retrouve exactement le bon programme"
	else
		non "« $nom » : $res"
	fi
}
essai_nom_piege "App (1)'s.AppImage"
essai_nom_piege 'App"Q\W.AppImage'

#  ET LE GESTE PRINCIPAL — UN .deb ACCEPTÉ DOIT VRAIMENT PARTIR CHEZ apt. Sans
#  ce contrôle en sens positif, on peut vider poser_paquet() de tout son
#  travail (elle annonce « Installé. » et sort) sans que le banc bronche.
#  On masque aussi les terminaux : hors root ET sans agent polkit, le geste
#  passe par terminal_admin, qui « exec » un terminal — sans ce masque, la
#  mesure dépendrait de qui lance ce banc (root en CI, un compte ordinaire
#  ailleurs).
for T in xfce4-terminal x-terminal-emulator gnome-terminal xterm sudo; do
	cp "$BANC/bin/apt-get" "$BANC/bin/$T"
done
: > "$BANC/apt-appels"
printf 'oui\n' | env -u DISPLAY -u WAYLAND_DISPLAY PATH="$BANC/bin:$PATH" \
	bash "$OUTIL" "$D/paquet.deb" >/dev/null 2>&1
grep -q 'install' "$BANC/apt-appels" \
	&& ok "un paquet accepté est bel et bien remis à apt" \
	|| non "un paquet accepté n'appelle jamais apt : rien ne s'installe"

#  ANNULER DANS gdebi (fenêtre fermée, rc=0 — qui NE VEUT PAS DIRE installé)
#  NE DOIT RIEN RELANCER DE PLUS PRIVILÉGIÉ. Il faut un DISPLAY et un zenity
#  pour atteindre la branche graphique où vit gdebi-gtk.
mkdir -p "$BANC/bin-gdebi"
printf '#!/bin/sh\ncase "$1" in --question) exit 0 ;; *) exit 1 ;; esac\n' \
	> "$BANC/bin-gdebi/zenity"; chmod +x "$BANC/bin-gdebi/zenity"
printf '#!/bin/sh\nexit 0\n' > "$BANC/bin-gdebi/gdebi-gtk"; chmod +x "$BANC/bin-gdebi/gdebi-gtk"
for T in pkexec xfce4-terminal x-terminal-emulator gnome-terminal xterm sudo apt-get; do
	printf '#!/bin/sh\nprintf '"'"'%%s\n'"'"' "$*" >> "%s"\n' "$BANC/traces-gdebi" > "$BANC/bin-gdebi/$T"
	chmod +x "$BANC/bin-gdebi/$T"
done
: > "$BANC/traces-gdebi"
SORTIE_GDEBI="$(DISPLAY=:99 PATH="$BANC/bin-gdebi:$PATH" bash "$OUTIL" "$D/paquet.deb" 2>&1)"
if [ -s "$BANC/traces-gdebi" ]; then
	non "après gdebi, autre chose a quand même été appelé : $(cat "$BANC/traces-gdebi")"
elif printf '%s' "$SORTIE_GDEBI" | grep -qi 'installé'; then
	#  LE VRAI DÉFAUT (constat #6, point « CE QUI SE REPRODUIT QUAND MÊME ») :
	#  gdebi-gtk rend 0 aussi bien quand il a installé QUE quand sa fenêtre a
	#  simplement été fermée sans rien faire (SimpleGtkbuilderApp.run() ->
	#  Gtk.main_quit() -> retour normal). Annoncer « Installé » sur ce rc=0 est
	#  un FAUX succès ; seul « rien de plus tenté » est vrai dans les deux cas.
	non "gdebi a rendu la main (fenêtre fermée), mais lexos-ouvrir annonce quand même un succès : $SORTIE_GDEBI"
else
	ok "gdebi a rendu la main (fenêtre fermée) : ni faux succès, ni tentative plus privilégiée"
fi

#  REFUSER LE MOT DE PASSE DE pkexec (code 126) EST UN REFUS, PAS UNE PANNE DE
#  MÉCANISME : ça ne doit PAS retomber sur un terminal + sudo, plus privilégié.
#  gdebi-gtk est ABSENT ici (on veut atteindre la branche pkexec), pgrep est
#  faussé pour dire qu'un agent tourne, et « id » pour dire qu'on n'est pas
#  root (sinon la branche root, qui vient avant, absorberait tout le test).
mkdir -p "$BANC/bin-pkexec"
cp "$BANC/bin-gdebi/zenity" "$BANC/bin-pkexec/zenity"
printf '#!/bin/sh\ncase "$1" in -u) echo 1000 ;; *) exec /usr/bin/id "$@" ;; esac\n' \
	> "$BANC/bin-pkexec/id"; chmod +x "$BANC/bin-pkexec/id"
#  pgrep -x DOIT IMPRIMER un pid pour que agent_polkit() (qui lit la SORTIE,
#  pas le code de retour) voie un agent : un simple « exit 0 » muet équivaut
#  à « rien trouvé ».
printf '#!/bin/sh\necho 12345\n' > "$BANC/bin-pkexec/pgrep"; chmod +x "$BANC/bin-pkexec/pgrep"
printf '#!/bin/sh\nexit 126\n' > "$BANC/bin-pkexec/pkexec"; chmod +x "$BANC/bin-pkexec/pkexec"
for T in xfce4-terminal x-terminal-emulator gnome-terminal xterm sudo apt-get; do
	printf '#!/bin/sh\nprintf '"'"'%%s\n'"'"' "$*" >> "%s"\n' "$BANC/traces-pkexec" > "$BANC/bin-pkexec/$T"
	chmod +x "$BANC/bin-pkexec/$T"
done
: > "$BANC/traces-pkexec"
DISPLAY=:99 PATH="$BANC/bin-pkexec:$PATH" bash "$OUTIL" "$D/paquet.deb" >/dev/null 2>&1
[ ! -s "$BANC/traces-pkexec" ] \
	&& ok "le mot de passe pkexec refusé (126) n'est pas converti en tentative supplémentaire" \
	|| non "un refus pkexec a quand même relancé quelque chose de plus privilégié : $(cat "$BANC/traces-pkexec")"

# =============================================================================
titre "3. LE DOUBLE-CLIC EST VRAIMENT BRANCHÉ"
# =============================================================================
#  Le piège mesuré : GIO ignore EN SILENCE un .desktop dont le programme
#  Exec= n'existe pas, et update-desktop-database l'inscrit quand même.
EXEC_PROG="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$BUREAU" | head -1)"
case "$EXEC_PROG" in
	/*) CIBLE="$RACINE/config/includes.chroot${EXEC_PROG}" ;;
	*)  CIBLE="$RACINE/config/includes.chroot/usr/bin/$EXEC_PROG" ;;
esac
[ -x "$CIBLE" ] \
	&& ok "le programme nommé par « Exec= » existe dans l'ISO ($EXEC_PROG)" \
	|| non "« Exec=$EXEC_PROG » ne désigne aucun programme livré — GIO ignorerait ce .desktop EN SILENCE"

grep -q '^Exec=.*%f' "$BUREAU" \
	&& ok "le .desktop reçoit bien le fichier (%f)" \
	|| non "le .desktop ne reçoit aucun fichier : le double-clic n'aurait rien à ouvrir"
grep -q '^Terminal=false' "$BUREAU" \
	&& ok "il ne s'ouvre pas dans un terminal — c'est toute la demande d'Alex" \
	|| non "le .desktop ouvre un terminal"

for T in application/vnd.debian.binary-package application/vnd.appimage \
         application/x-iso9660-appimage application/vnd.flatpak.ref \
         application/x-shellscript application/x-executable; do
	grep -q "MimeType=.*$T" "$BUREAU" \
		&& ok "le .desktop se déclare pour $T" \
		|| non "le .desktop ne se déclare pas pour $T"
done

#  LES DEUX TYPES D'AppImage, PAS UN SEUL : le motif « *.appimage » pèse 60
#  pour vnd.appimage et 50 pour x-iso9660-appimage. Sur le seul nom c'est
#  vnd.appimage qui gagne, mais dès que le CONTENU est reniflé — et Thunar le
#  renifle — une AppImage de type 1 redevient x-iso9660-appimage.
#  ═══ ON GREPPE UN FICHIER, JAMAIS UN TUYAU ═══
#  « quelquechose | grep -q motif » sous « set -o pipefail » : grep sort dès la
#  première correspondance, ferme le tuyau, l'amont reçoit SIGPIPE, et le
#  pipeline rend 141 — un ÉCHEC, alors que le motif a été trouvé. Ça dépend du
#  moment où grep s'arrête, donc ça passe au vert une fois sur deux. Chaque
#  sortie qu'on veut fouiller est donc écrite dans un fichier d'abord.
HEREDOC="$BANC/mimeapps-heredoc"
sed -n '/cat > \/etc\/xdg\/mimeapps.list/,/^EOF$/p' "$HOOK" > "$HEREDOC"
if [ ! -s "$HEREDOC" ]; then
	non "le bloc qui écrit mimeapps.list est introuvable dans le crochet 0400"
else
	for T in application/vnd.debian.binary-package application/vnd.appimage \
	         application/x-iso9660-appimage application/vnd.flatpak.ref \
	         application/x-rpm application/x-shellscript application/x-executable; do
		grep -q "^$T=" "$HEREDOC" \
			&& ok "mimeapps.list désigne un gestionnaire pour $T" \
			|| non "mimeapps.list ne dit rien de $T — le double-clic ne fera rien"
	done
	grep -q 'lexos-ouvrir.desktop\|OUVRIR_DESKTOP' "$HEREDOC" \
		&& ok "…et c'est lexos-ouvrir qui répond" \
		|| non "mimeapps.list ne renvoie pas à lexos-ouvrir"
fi

#  INDISPENSABLE, SINON LE CÂBLAGE CI-DESSUS EST ANNULÉ EN SILENCE : si
#  lexos-defaut range encore application/x-shellscript dans sa catégorie
#  « texte », le premier réglage « Éditeur de texte » des Paramètres écrit
#  ~/.config/mimeapps.list, qui l'emporte sur /etc/xdg — le .sh repart vers
#  Mousepad au premier passage dans les Paramètres.
#  Sur le CODE, jamais sur le fichier entier : son propre commentaire NOMME
#  x-shellscript pour expliquer pourquoi il n'y est plus.
sed 's/#.*$//' "$DEFAUT" > "$BANC/defaut-nu"
grep -q 'application/x-shellscript' "$BANC/defaut-nu" \
	&& non "lexos-defaut range encore x-shellscript dans une catégorie : Paramètres > Éditeur de texte annulerait le câblage vers lexos-ouvrir" \
	|| ok "lexos-defaut ne range plus x-shellscript nulle part — le câblage tient"

#  LE FICHIER A UN SEUL AUTEUR. Si quelqu'un ajoute un jour un mimeapps.list
#  ailleurs, le heredoc du 0400 l'écrasera sans prévenir.
AUTEURS="$(grep -rlF 'mimeapps.list' "$RACINE/config/hooks/normal" 2>/dev/null | wc -l)"
[ "$AUTEURS" -le 2 ] \
	&& ok "mimeapps.list garde peu d'auteurs ($AUTEURS crochet(s)) — pas d'écrasement surprise" \
	|| non "$AUTEURS crochets touchent mimeapps.list : le dernier écrasera les autres"

# =============================================================================
titre "4. L'AGENT QUI AFFICHE LA FENÊTRE DU MOT DE PASSE"
# =============================================================================
#  LA PHRASE FAUSSE NE DOIT PAS REVENIR.
grep -q 'Recommends de xfce4-session' "$LISTE" \
	&& non "la liste affirme encore que l'agent arrive par les Recommends de xfce4-session — c'est faux, vérifié" \
	|| ok "la phrase fausse sur les Recommends de xfce4-session a disparu"

NOMMES=0
for P in policykit-1-gnome lxpolkit mate-polkit; do
	grep -qx "$P" "$LISTE" && NOMMES=$((NOMMES+1))
done
[ "$NOMMES" -ge 2 ] \
	&& ok "$NOMMES agents d'authentification sont nommés (liste « au mieux » : un nom absent ne casse rien)" \
	|| non "moins de deux agents nommés : une seule absence et tous les boutons d'administration redeviennent muets"

#  L'AUTOSTART EXISTE ET POINTE SUR UN PROGRAMME LIVRÉ — même piège qu'au
#  point 3 : un Exec= qui ne mène nulle part ne dit rien.
A_EXEC="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$AUTOSTART" | head -1)"
[ -x "$RACINE/config/includes.chroot${A_EXEC}" ] \
	&& ok "l'autostart pointe sur un programme livré ($A_EXEC)" \
	|| non "l'autostart pointe sur « $A_EXEC », qui n'est pas livré"
grep -q '^OnlyShowIn=.*XFCE' "$AUTOSTART" \
	&& ok "…et il se déclare pour XFCE, le bureau de LexOS" \
	|| non "l'autostart ne se déclare pas pour XFCE"

#  LES TROIS COMPORTEMENTS DU LANCEUR.
#  LEXOS_POLKIT_DEJA=non : sans cette couture, un agent RÉELLEMENT en marche
#  sur la machine qui lance ce banc (session XFCE de développement, ou un
#  résidu d'un tour précédent) ferait rougir ces deux contrôles — deja_la()
#  répondrait vrai pour de bonnes raisons, mais pour la mauvaise mesure.
mkdir -p "$BANC/agents"
LEXOS_POLKIT_DEJA=non LEXOS_POLKIT_AGENTS="$BANC/agents/absent" bash "$AGENT" > "$BANC/ag1" 2>&1; CODE=$?
SORTIE="$(cat "$BANC/ag1")"
if [ "$CODE" -ne 0 ] && grep -qi 'aucun agent' "$BANC/ag1"; then
	ok "aucun agent installé : il le DIT et sort en erreur (au lieu de se taire)"
else
	non "aucun agent installé : code $CODE, message « $SORTIE » — la panne resterait invisible"
fi

printf '#!/bin/sh\necho AGENT-LANCE\n' > "$BANC/agents/faux"; chmod +x "$BANC/agents/faux"
LEXOS_POLKIT_DEJA=non LEXOS_POLKIT_AGENTS="$BANC/agents/absent
$BANC/agents/faux" bash "$AGENT" > "$BANC/ag2" 2>&1 || true
SORTIE="$(cat "$BANC/ag2")"
grep -q 'AGENT-LANCE' "$BANC/ag2" \
	&& ok "un agent présent est lancé, même si un candidat plus prioritaire manque" \
	|| non "l'agent présent n'a pas été lancé (sortie : $SORTIE)"

#  UN CANDIDAT DONT LE FOURNISSEUR DÉMARRE DÉJÀ TOUT SEUL (autostart actif,
#  non masqué) NE DOIT PAS ÊTRE RELANCÉ ICI (constat #10) : ça ferait un
#  doublon dont l'enregistrement auprès de polkitd échoue à coup sûr.
mkdir -p "$BANC/autostart-fournisseur" "$BANC/agents-fournisseur"
cat > "$BANC/autostart-fournisseur/polkit-gnome-authentication-agent-1.desktop" <<EOF
[Desktop Entry]
Type=Application
OnlyShowIn=XFCE;
EOF
printf '#!/bin/sh\necho AGENT-LANCE\n' > "$BANC/agents-fournisseur/polkit-gnome-authentication-agent-1"
chmod +x "$BANC/agents-fournisseur/polkit-gnome-authentication-agent-1"
LEXOS_POLKIT_DEJA=non LEXOS_AUTOSTART_DIR="$BANC/autostart-fournisseur" \
LEXOS_POLKIT_AGENTS="$BANC/agents-fournisseur/polkit-gnome-authentication-agent-1" \
	bash "$AGENT" > "$BANC/ag4" 2>&1
grep -q 'AGENT-LANCE' "$BANC/ag4" \
	&& non "un candidat dont le fournisseur démarre déjà seul a quand même été relancé — doublon garanti" \
	|| ok "…et un candidat dont le fournisseur démarre déjà seul (autostart non masqué) est sauté"

#  DÉJÀ EN MARCHE : ON NE DOIT PAS EN LANCER UN DEUXIÈME. Une COPIE de « sh »
#  nommée « lxpolkit » suffit : ce qui compte est /proc/<pid>/comm, c'est-à-dire
#  le nom du FICHIER exécuté — « exec -a » ne le changerait pas.
if command -v pgrep >/dev/null 2>&1 && command -v sh >/dev/null 2>&1; then
	cp "$(command -v sh)" "$BANC/agents/lxpolkit"
	"$BANC/agents/lxpolkit" -c 'sleep 20' & FAUX_PID=$!
	sleep 0.5
	LEXOS_POLKIT_AGENTS="$BANC/agents/faux" bash "$AGENT" > "$BANC/ag3" 2>&1 || true
	#  ON TUE PAR PID, jamais par motif : « pkill -f » frappe tout ce qui cite
	#  le motif, y compris le shell qui lance ce banc. Vécu.
	kill "$FAUX_PID" 2>/dev/null; wait "$FAUX_PID" 2>/dev/null
	grep -q 'AGENT-LANCE' "$BANC/ag3" \
		&& non "un deuxième agent a été lancé alors qu'un agent tournait déjà" \
		|| ok "un agent tourne déjà : on n'en lance pas un deuxième"

	#  LE MÊME ESSAI, MAIS AVEC LE NOM QUI SE FAIT TRONQUER. « lxqt-policykit »
	#  (sans le tiret final) ne correspond à AUCUN /proc/<pid>/comm réel — le
	#  noyau tronque « lxqt-policykit-agent » à 15 caractères, tiret compris.
	#  C'est le cas que la copie « lxpolkit » ci-dessus, trop courte pour être
	#  tronquée, ne peut structurellement pas révéler.
	cp "$(command -v sh)" "$BANC/agents/lxqt-policykit-agent"
	"$BANC/agents/lxqt-policykit-agent" -c 'sleep 20' & FAUX_PID2=$!
	sleep 0.5
	LEXOS_POLKIT_AGENTS="$BANC/agents/faux" bash "$AGENT" > "$BANC/ag3b" 2>&1 || true
	kill "$FAUX_PID2" 2>/dev/null; wait "$FAUX_PID2" 2>/dev/null
	grep -q 'AGENT-LANCE' "$BANC/ag3b" \
		&& non "l'agent LXQt (comm tronqué « lxqt-policykit- ») n'a pas été reconnu comme déjà en marche" \
		|| ok "…et le nom tronqué de l'agent LXQt (« lxqt-policykit- ») est bien reconnu"
else
	saute "pgrep ou sh absent : le doublon d'agent n'a PAS été éprouvé"
fi

# =============================================================================
titre "5. LE MOTEUR DES PARAMÈTRES NE FAIT PLUS SEMBLANT"
# =============================================================================
#  pkexec sans agent échoue SANS FENÊTRE ET SANS MESSAGE : le bouton paraît
#  mort. Le moteur doit rendre un motif que la page peut écrire.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le moteur n'a PAS été éprouvé"
else
	SORTIE_M="$(cd "$RACINE/config/includes.chroot/usr/lib/lexos" && python3 - <<'PY' 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true
import sys
sys.path.insert(0, ".")
try:
    import settings

    def dit(bon, texte):
        print(("OK|" if bon else "NON|") + texte)

    dit(hasattr(settings, "_run_admin") and hasattr(settings, "_agent_polkit"),
        "le moteur a un chemin d'administration à lui (_run_admin/_agent_polkit)")

    #  1. pkexec là, AUCUN agent -> il doit REFUSER en nommant l'agent.
    #  On remplace _run AVANT : sinon, si la garde saute, on mesurerait
    #  l'absence de pkexec sur la machine du banc au lieu de la garde
    #  elle-même — un rouge qui parle de la mauvaise chose.
    vus = []
    settings.shutil.which = lambda n, *a, **k: "/usr/bin/pkexec" if n == "pkexec" else None
    settings._run = lambda argv, **k: (vus.append(list(argv)), {"ok": True})[1]
    settings._agent_polkit = lambda: False
    settings.os.geteuid = lambda: 1000
    r = settings._run_admin(["timedatectl", "set-ntp", "on"])
    dit(r.get("ok") is False and "agent" in r.get("erreur", "").lower(),
        "sans agent : il refuse et NOMME ce qui manque (%s)" % r.get("erreur", "")[:60])

    #  2. agent là -> il doit vraiment passer par pkexec.
    vus.clear()
    settings._agent_polkit = lambda: True
    settings._run_admin(["timedatectl", "set-ntp", "on"])
    dit(bool(vus) and vus[0][0] == "pkexec",
        "avec un agent : il passe bien par pkexec")

    #  3. root -> jamais de pkexec.
    vus.clear()
    settings.os.geteuid = lambda: 0
    settings._run_admin(["timedatectl", "set-ntp", "on"])
    dit(bool(vus) and vus[0][0] != "pkexec",
        "en root : il n'appelle pas pkexec pour rien")

    #  (Le contrôle « jamais pgrep -f » se fait plus bas, sur le TEXTE des
    #   fichiers : ici _agent_polkit vient d'être remplacée par une fonction
    #   d'essai, il n'y aurait plus rien de vrai à lire dedans.)
except Exception as _e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")
PY
)"
	if [ -z "$SORTIE_M" ]; then
		non "le moteur n'a rien rendu"
	elif ! printf '%s\n' "$SORTIE_M" > "$BANC/moteur-sortie" || ! grep -q '^FIN|' "$BANC/moteur-sortie"; then
		non "le banc du moteur s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_M
EOF
	fi
fi

#  « pgrep -f » EST INTERDIT DANS LES DEUX FICHIERS. Le dépôt s'est fait
#  prendre trois fois (lexos-share, lexos-crt, et un pkill qui a tué le shell
#  du banc lui-même).
for F in "$AGENT" "$OUTIL"; do
	sed 's/#.*$//' "$F" > "$BANC/nu"
	grep -q 'pgrep -f' "$BANC/nu" \
		&& non "$(basename "$F") emploie « pgrep -f » : il se reconnaîtra lui-même" \
		|| ok "$(basename "$F") n'emploie pas « pgrep -f »"
done
sed 's/#.*$//' "$MOTEUR" > "$BANC/moteur-nu"
grep -q '"pgrep", *"-f"' "$BANC/moteur-nu" \
	&& non "settings.py emploie « pgrep -f »" \
	|| ok "settings.py n'emploie pas « pgrep -f »"

# =============================================================================
titre "6. TOUT EST BRANCHÉ — le terminal aussi, pour ceux qui le préfèrent"
# =============================================================================
grep -qE '(^|[^a-z-])ouvrir[^a-z-].*exec lexos-ouvrir' "$DISPATCH" \
	&& ok "« lexos ouvrir » mène à l'outil" \
	|| non "aucune branche « ouvrir » dans le dispatcheur"
sed 's/\${[A-Z]*}//g' "$DISPATCH" | awk '/^cmd_help\(\)/,0' > "$BANC/aide-nue"
grep -qE '(^|[[:space:]])ouvrir([[:space:]]|$)' "$BANC/aide-nue" \
	&& ok "…et l'aide en parle" \
	|| non "« ouvrir » n'apparaît pas dans l'aide : la commande existe à moitié"
grep -q 'ouvrir' "$COMPLETION" \
	&& ok "…et la touche Tab la propose" \
	|| non "« ouvrir » manque à la complétion : Tab resterait muet dessus"
grep -q 'lexos-ouvrir' "$MOTEUR" \
	&& ok "les Paramètres savent qu'il existe" \
	|| non "aucune trace de lexos-ouvrir dans les Paramètres"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
