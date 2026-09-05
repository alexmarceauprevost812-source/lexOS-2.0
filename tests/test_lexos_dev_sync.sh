#!/usr/bin/env bash
# =============================================================================
#  lexos dev-sync — poser le dépôt sans reconstruire l'ISO
# =============================================================================
#  Changer une ligne d'un script demandait une ISO complète. Cet outil pose
#  les fichiers du dépôt sur le système en marche — et comme il écrit dans
#  /usr en root, presque tout ce banc porte sur ce qu'il REFUSE de faire.
#
#  ═══ L'ASSERTION QUI COMPTE LE PLUS ═══
#  Que « --essai » n'écrive RIEN. Un essai auquel on fait confiance et qui
#  écrit quand même est pire que pas d'essai du tout : on le lance justement
#  pour regarder avant de décider. On compare donc les sommes de contrôle de
#  toute la destination, avant et après.
#
#  Le banc travaille dans un faux clone et une fausse racine, par le seam
#  LEXOS_DEV_SYNC_DEST — même convention que LEXOS_RACINE ailleurs. Rien de
#  ce qui suit ne touche la machine qui fait tourner le banc.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-dev-sync"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[[ -x "$OUTIL" ]] || { echo "lexos-dev-sync introuvable ou non exécutable"; exit 1; }

CLONE="$BANC/clone"
DEST="$BANC/dest"
INC="$CLONE/config/includes.chroot"

#  Un faux clone : les deux repères que l'outil exige, et un fichier par arbre.
monte_clone() {
	rm -rf "$CLONE"
	mkdir -p "$INC/usr/bin" "$INC/usr/share/lexos" "$INC/usr/lib/lexos" \
	         "$INC/etc/skel/.config"
	: > "$CLONE/lexos.conf"
	printf '#!/bin/sh\necho version-du-depot\n' > "$INC/usr/bin/lexos-truc"
	chmod 755 "$INC/usr/bin/lexos-truc"
	printf 'body{color:red}\n'  > "$INC/usr/share/lexos/ui.css"
	printf 'x = 1\n'            > "$INC/usr/lib/lexos/module.py"
	printf 'reglage=depot\n'    > "$INC/etc/skel/.config/truc.conf"
	git -C "$CLONE" init -q >/dev/null 2>&1 || true
	git -C "$CLONE" add -A >/dev/null 2>&1 || true
	git -C "$CLONE" -c user.email=b@b -c user.name=b commit -qm init >/dev/null 2>&1 || true
}

#  Une fausse racine, avec des TÉMOINS dans les zones interdites.
monte_dest() {
	rm -rf "$DEST"
	mkdir -p "$DEST/usr/share/lexos" "$DEST/boot" "$DEST/etc/lexos"
	#  Un fichier déjà présent et DIFFÉRENT : c'est lui qui doit être sauvegardé.
	printf 'body{color:blue}\n' > "$DEST/usr/share/lexos/ui.css"
	printf 'NOYAU — INTOUCHABLE\n' > "$DEST/boot/vmlinuz"
	printf '2.0.0\n'              > "$DEST/etc/lexos/version"
	printf 'LEXOS_ACCENT_NAME=orange\n' > "$DEST/etc/lexos/build.conf"
}

empreinte() { find "$DEST" -type f -exec md5sum {} \; 2>/dev/null | sort; }

lance() { NO_COLOR=1 LEXOS_DEV_SYNC_DEST="$DEST" bash "$OUTIL" "$@" 2>&1; }
code()  { NO_COLOR=1 LEXOS_DEV_SYNC_DEST="$DEST" bash "$OUTIL" "$@" >/dev/null 2>&1; printf '%s' "$?"; }

# =============================================================================
titre "1. --essai n'écrit RIEN — l'assertion la plus importante"
# =============================================================================
#  On lui fait confiance pour décider : s'il écrit, il trahit la seule chose
#  qu'on lui demande.
monte_clone; monte_dest
AVANT="$(empreinte)"
SORTIE="$(lance --depuis "$CLONE" --essai)"
APRES="$(empreinte)"

if [[ "$AVANT" == "$APRES" ]]; then
	ok "--essai ne modifie aucun fichier de la destination"
else
	non "--essai A ÉCRIT :\n$(diff <(printf '%s' "$AVANT") <(printf '%s' "$APRES") | head -6)"
fi

grep -q "ESSAI" <<< "$SORTIE" \
	&& ok "…et il annonce clairement qu'il est en essai" \
	|| non "l'essai ne se signale pas dans la sortie"

grep -q "usr/bin/lexos-truc" <<< "$SORTIE" \
	&& ok "…tout en disant ce qu'il COPIERAIT" \
	|| non "l'essai ne montre pas les fichiers concernés"

#  ET IL NE DOIT PAS CRÉER LA TRACE NON PLUS. Une trace écrite en essai
#  ferait croire, plus tard, à une synchronisation qui n'a jamais eu lieu.
[[ -e "$DEST/etc/lexos/dev-sync" ]] \
	&& non "--essai a écrit /etc/lexos/dev-sync : la machine mentirait sur son état" \
	|| ok "…et il n'écrit pas la trace /etc/lexos/dev-sync"

# =============================================================================
titre "2. Un chemin qui n'est pas un clone de lexOS-2.0 est REFUSÉ"
# =============================================================================
#  Sans ce contrôle, un chemin tapé de travers copierait n'importe quoi dans
#  /usr/bin, en root.
monte_dest
mkdir -p "$BANC/pasclone"
C="$(code --depuis "$BANC/pasclone")"
[[ "$C" != "0" ]] \
	&& ok "un dossier quelconque est refusé (code $C)" \
	|| non "un dossier quelconque a été ACCEPTÉ — il aurait pu écrire dans /usr"

#  Les DEUX repères sont exigés, pas un seul : un dossier peut avoir un
#  « config/ » par hasard, pas les deux.
mkdir -p "$BANC/moitie/config/includes.chroot"
C="$(code --depuis "$BANC/moitie")"
[[ "$C" != "0" ]] \
	&& ok "…un clone à moitié ressemblant l'est aussi (lexos.conf manque)" \
	|| non "un dossier sans lexos.conf a été accepté"

C="$(code --depuis "$BANC/nexiste-pas-du-tout")"
[[ "$C" != "0" ]] \
	&& ok "…et un chemin inexistant également" \
	|| non "un chemin inexistant a été accepté"

# =============================================================================
titre "3. Les permissions survivent au voyage"
# =============================================================================
#  Les outils du dépôt sont en 755. Un bit d'exécution perdu et la commande
#  n'existe plus — une panne muette et pénible à comprendre.
monte_clone; monte_dest
lance --depuis "$CLONE" >/dev/null
if [[ -x "$DEST/usr/bin/lexos-truc" ]]; then
	MODE="$(stat -c '%a' "$DEST/usr/bin/lexos-truc" 2>/dev/null)"
	[[ "$MODE" == "755" ]] \
		&& ok "un fichier source en 755 arrive en 755" \
		|| non "le mode a changé en chemin : $MODE au lieu de 755"
else
	non "le fichier copié n'est plus exécutable — la commande n'existerait plus"
fi

#  Et le contenu est bien celui du dépôt, pas l'ancien.
grep -q "version-du-depot" "$DEST/usr/bin/lexos-truc" 2>/dev/null \
	&& ok "…et c'est bien le contenu du dépôt qui est arrivé" \
	|| non "le contenu copié n'est pas celui du dépôt"

# =============================================================================
titre "4. Les zones interdites ne sont JAMAIS touchées — même avec --tout"
# =============================================================================
#  Le noyau, l'initramfs et GRUB ne se posent pas à chaud. version, release
#  et build.conf sont estampillés à la construction : les réécrire ferait
#  mentir la machine sur ce qu'elle est.
monte_clone; monte_dest
#  On tend un piège : le clone contient des fichiers DANS les zones interdites.
mkdir -p "$INC/boot" "$INC/etc/lexos"
printf 'FAUX NOYAU\n'      > "$INC/boot/vmlinuz"
printf '9.9.9\n'           > "$INC/etc/lexos/version"
printf 'LEXOS_ACCENT_NAME=vert\n' > "$INC/etc/lexos/build.conf"

lance --depuis "$CLONE" --tout >/dev/null
#  ═══ CE QUI SUIT TESTE LA LISTE DES ARBRES, PAS LE GARDE-FOU ═══
#  Découvert en cassant le garde-fou exprès : les témoins restaient intacts
#  quand même. C'est normal — boot/ et etc/lexos ne sont dans AUCUN des arbres
#  parcourus, donc le garde-fou n'est jamais atteint par ce chemin-là. Les
#  deux protections existent, elles ne se recouvrent pas, et il faut donc
#  éprouver la seconde SÉPARÉMENT (juste en dessous).
for T in "boot/vmlinuz:NOYAU — INTOUCHABLE" "etc/lexos/version:2.0.0" "etc/lexos/build.conf:LEXOS_ACCENT_NAME=orange"; do
	F="${T%%:*}"; ATTENDU="${T#*:}"
	REEL="$(cat "$DEST/$F" 2>/dev/null)"
	if [[ "$REEL" == "$ATTENDU" ]]; then
		ok "/$F est intact, même avec --tout"
	else
		non "/$F A ÉTÉ ÉCRASÉ : « $REEL » au lieu de « $ATTENDU »"
	fi
done

#  ═══ LE GARDE-FOU LUI-MÊME, ÉPROUVÉ DIRECTEMENT ═══
#  Il existe pour le jour où quelqu'un ajoutera un arbre sans y penser : ce
#  jour-là, il sera la SEULE protection. On extrait donc sa liste et sa
#  fonction du vrai fichier, et on les interroge — pas une copie, le code lui
#  même.
GARDE="$(sed -n '/^INTERDITS=(/,/^}/p' "$OUTIL")"
if [[ -z "$GARDE" ]]; then
	non "impossible d'extraire le garde-fou du fichier"
else
	interroge() { # interroge <chemin relatif> -> REFUSE ou PASSE
		bash -c "$GARDE"$'\n''interdit "$1" && echo REFUSE || echo PASSE' _ "$1" 2>/dev/null
	}
	for CHEMIN in "boot/vmlinuz" "boot/initrd.img" "etc/lexos/version" \
	              "etc/lexos/release" "etc/lexos/build.conf" \
	              "etc/initramfs-tools/conf.d/x" "etc/default/grub" "lib/live/config"; do
		if [[ "$(interroge "$CHEMIN")" == "REFUSE" ]]; then
			ok "le garde-fou refuse $CHEMIN"
		else
			non "le garde-fou LAISSE PASSER $CHEMIN — s'il devenait la seule protection, il ne protégerait rien"
		fi
	done
	#  Et il ne doit pas refuser ce qui est légitime, sinon il bloquerait la
	#  synchronisation utile en croyant bien faire.
	for CHEMIN in "usr/bin/lexos-truc" "usr/share/lexos/ui.css" "etc/skel/.config/truc.conf"; do
		if [[ "$(interroge "$CHEMIN")" == "PASSE" ]]; then
			ok "…et il laisse passer $CHEMIN"
		else
			non "le garde-fou refuse $CHEMIN, qui est pourtant à synchroniser"
		fi
	done
fi

# =============================================================================
titre "5. L'ancien fichier est sauvegardé avant d'être écrasé"
# =============================================================================
#  Un réglage ajusté à la main ne doit pas disparaître sans trace.
monte_clone; monte_dest
SORTIE="$(lance --depuis "$CLONE")"
SAUVES=$(find "$DEST" -name '*.lexos-bak-*' 2>/dev/null | wc -l)
if (( SAUVES > 0 )); then
	ok "l'ancien fichier est sauvegardé ($SAUVES fichier(s) .lexos-bak-*)"
	BAK="$(find "$DEST" -name 'ui.css.lexos-bak-*' | head -1)"
	if [[ -n "$BAK" ]] && grep -q "color:blue" "$BAK" 2>/dev/null; then
		ok "…et la sauvegarde contient bien l'ANCIEN contenu"
	else
		non "la sauvegarde ne contient pas l'ancien contenu"
	fi
else
	non "aucune sauvegarde : un réglage ajusté à la main disparaîtrait sans trace"
fi

grep -q "sauvegardé" <<< "$SORTIE" \
	&& ok "…et le bilan dit combien de fichiers ont été sauvegardés" \
	|| non "le bilan ne mentionne pas les sauvegardes"

#  UN FICHIER IDENTIQUE NE SE SAUVEGARDE PAS. Sans ça, chaque passage
#  laisserait une copie de plus d'un fichier qui n'a jamais changé.
monte_dest
cp "$INC/usr/share/lexos/ui.css" "$DEST/usr/share/lexos/ui.css"
lance --depuis "$CLONE" --tout >/dev/null
IDENT=$(find "$DEST" -name 'ui.css.lexos-bak-*' 2>/dev/null | wc -l)
(( IDENT == 0 )) \
	&& ok "un fichier identique n'est pas sauvegardé pour rien" \
	|| non "un fichier identique a quand même été sauvegardé ($IDENT copie(s))"

# =============================================================================
titre "6. La trace dit ce que la machine porte vraiment"
# =============================================================================
#  Sans elle, un système synchronisé et un système d'origine sont
#  indiscernables : on déboguerait un fichier qu'on croit à jour.
monte_clone; monte_dest
lance --depuis "$CLONE" >/dev/null
TRACE="$DEST/etc/lexos/dev-sync"
if [[ -r "$TRACE" ]]; then
	ok "/etc/lexos/dev-sync est écrit"
	COMMIT="$(sed -n 's/^commit=//p' "$TRACE")"
	if [[ "$COMMIT" =~ ^[0-9a-f]{7,}$ ]]; then
		ok "…et il contient un commit court ($COMMIT)"
	else
		non "la trace ne contient pas de commit exploitable : « $COMMIT »"
	fi
	grep -q '^date=' "$TRACE" \
		&& ok "…et la date de la synchronisation" \
		|| non "la trace ne porte pas de date"
else
	non "aucune trace écrite : impossible de savoir ce que la machine porte"
fi

# =============================================================================
titre "7. Sans --skel, aucun fichier du compte n'est modifié"
# =============================================================================
#  C'est le piège principal de l'outil, et il doit rester explicite : les
#  fichiers de /etc/skel ne servent qu'aux comptes créés ENSUITE. Les
#  reporter dans un compte existant écrase des réglages — ça se demande.
monte_clone; monte_dest
FOYER="$DEST/home/essai"
mkdir -p "$FOYER/.config"
printf 'reglage=a-moi\n' > "$FOYER/.config/truc.conf"
AV_FOYER="$(find "$FOYER" -type f -exec md5sum {} \; | sort)"

SUDO_USER="essai" HOME="$FOYER" lance --depuis "$CLONE" >/dev/null
AP_FOYER="$(find "$FOYER" -type f -exec md5sum {} \; | sort)"
[[ "$AV_FOYER" == "$AP_FOYER" ]] \
	&& ok "sans --skel, le compte n'est pas touché" \
	|| non "sans --skel, un fichier du compte a été modifié :\n$(diff <(printf '%s' "$AV_FOYER") <(printf '%s' "$AP_FOYER") | head -4)"

#  ET IL DOIT LE DIRE, sinon la synchronisation a l'air d'avoir échoué.
SORTIE="$(lance --depuis "$CLONE")"
grep -q "N'ATTEINT AUCUN COMPTE" <<< "$SORTIE" \
	&& ok "…et il explique pourquoi /etc/skel ne change rien pour un compte existant" \
	|| non "rien n'explique que /etc/skel n'atteint aucun compte : on croirait à un échec"

grep -q -- "--skel" <<< "$SORTIE" \
	&& ok "…et il nomme l'option qui le ferait" \
	|| non "le message ne dit pas quelle option reporte les fichiers"

# =============================================================================
titre "8. Le bilan et le branchement"
# =============================================================================
SORTIE="$(lance --depuis "$CLONE" --essai)"
grep -q "DEMANDE UNE ISO" <<< "$SORTIE" \
	&& ok "le bilan rappelle ce qui exige encore une ISO" \
	|| non "rien ne rappelle ce que la synchronisation ne peut pas faire"

grep -qi "relancer" <<< "$SORTIE" \
	&& ok "…et ce qu'il faut relancer selon ce qui a changé" \
	|| non "rien ne dit quoi relancer après la copie"

#  ON NE RELANCE RIEN D'AUTORITÉ : Alex peut travailler dans une fenêtre.
if grep -qE '^\s*(xfce4-panel -r|systemctl restart|pkill)' "$OUTIL"; then
	non "l'outil relance quelque chose de lui-même — il couperait le travail en cours"
else
	ok "l'outil ne relance rien tout seul, il se contente de le dire"
fi

grep -q 'dev-sync' "$DISPATCH" \
	&& ok "« lexos dev-sync » est branché dans le dispatcheur" \
	|| non "la commande n'est pas atteignable par « lexos dev-sync »"

grep -q 'dev-sync' "$DISPATCH" && grep -qE 'dev-sync.*lexos-dev-sync' "$DISPATCH" \
	&& ok "…et elle appelle bien lexos-dev-sync" \
	|| non "la branche du dispatcheur n'appelle pas lexos-dev-sync"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
