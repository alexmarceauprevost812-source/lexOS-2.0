#!/usr/bin/env bash
# =============================================================================
#  « sudo miss a jour » — poser le dépôt sans reconstruire l'ISO
# =============================================================================
#  LE PROBLÈME. Chaque modification d'un script ou d'une feuille CSS demandait
#  une ISO complète : une heure de CI, la gravure, la réinstallation. Ces
#  fichiers-là sont de simples scripts — ils n'ont aucune raison d'exiger une
#  image.
#
#  CE N'EST PAS LE CANAL DE MISE À JOUR DÉFINITIF (paquet .deb + dépôt APT),
#  et ce banc ne prétend pas qu'il l'est.
#
#  ═══ POURQUOI CE FICHIER NE S'APPELLE PAS test_lexos_maj.sh ═══
#  Ce nom est PRIS, et par un autre sujet : test_lexos_maj.sh éprouve la PAGE
#  des mises à jour des Paramètres (« la page sait, elle ne devine plus »).
#  Écraser un banc existant pour respecter un nom aurait supprimé sa
#  couverture sans que personne ne le voie.
#
#  ═══ CE QUE CE BANC TIENT, ET DANS QUEL ORDRE D'IMPORTANCE ═══
#  1. « --essai » n'écrit RIEN. C'est l'assertion la plus importante : un
#     essai qui écrit est pire que pas d'essai du tout, parce qu'on lui fait
#     confiance pour regarder avant d'agir. On compare les empreintes de
#     TOUTE la destination, avant et après.
#  2. Ce qui vit dans l'image (/boot, build.conf, version) n'est JAMAIS
#     touché, même avec --tout. On pose des témoins et on les relit.
#  3. Toutes les portes mènent au même endroit, et AUCUNE ne duplique la
#     logique de copie.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IC="$RACINE/config/includes.chroot"
OUTIL="$IC/usr/bin/lexos-mise-a-jour"
MISS="$IC/usr/bin/miss"
DISPATCH="$IC/usr/bin/lexos"
GARDE="$RACINE/config/hooks/normal/0255-lexos-noms-reserves.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$MISS" "$DISPATCH" "$GARDE"; do
	if [ ! -r "$F" ]; then
		non "fichier introuvable : $F"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
		exit 1
	fi
done

# =============================================================================
titre "1. Un faux clone, et un faux système"
# =============================================================================
#  On monte un dépôt crédible : les deux marqueurs que l'outil exige, des
#  fichiers dans chaque arbre autorisé, et un outil en 755 pour éprouver que
#  le bit d'exécution survit.
SRC="$BANC/clone"
DST="$BANC/systeme"
mkdir -p "$SRC/config/includes.chroot/usr/bin" \
         "$SRC/config/includes.chroot/usr/share/lexos" \
         "$SRC/config/includes.chroot/usr/lib/lexos" \
         "$SRC/config/includes.chroot/boot" \
         "$SRC/config/includes.chroot/etc/lexos" \
         "$DST/usr/bin" "$DST/etc/lexos" "$DST/boot"
: > "$SRC/lexos.conf"
printf '#!/bin/sh\necho neuf\n' > "$SRC/config/includes.chroot/usr/bin/lexos-truc"
chmod 755 "$SRC/config/includes.chroot/usr/bin/lexos-truc"
printf 'body{color:red}\n'      > "$SRC/config/includes.chroot/usr/share/lexos/ui.css"
printf 'panneau neuf\n'         > "$SRC/config/includes.chroot/usr/share/lexos/gtk-panneau.css"
printf 'print("neuf")\n'        > "$SRC/config/includes.chroot/usr/lib/lexos/settings.py"

#  ═══ LES TÉMOINS : CE QUI NE DOIT JAMAIS BOUGER ═══
#  On les met des DEUX côtés : dans le clone (pour que l'outil ait la
#  tentation de les copier) et dans le système (pour vérifier qu'ils sont
#  intacts). Sans le côté clone, le contrôle serait vert faute de candidat.
printf 'NOYAU DE L IMAGE\n'     > "$SRC/config/includes.chroot/boot/vmlinuz"
printf 'LEXOS_BUILD=neuf\n'     > "$SRC/config/includes.chroot/etc/lexos/build.conf"
printf '999\n'                  > "$SRC/config/includes.chroot/etc/lexos/version"
printf 'NOYAU D ORIGINE\n'      > "$DST/boot/vmlinuz"
printf 'LEXOS_BUILD=110\n'      > "$DST/etc/lexos/build.conf"
printf '110\n'                  > "$DST/etc/lexos/version"
#  Un fichier déjà présent, DIFFÉRENT : c'est lui qui doit être sauvegardé.
printf '#!/bin/sh\necho vieux\n' > "$DST/usr/bin/lexos-truc"
chmod 755 "$DST/usr/bin/lexos-truc"

lance() { # lance <arguments…>
	LEXOS_MAJ_DEST="$DST" \
	LEXOS_MAJ_ETC="$DST/etc/lexos" \
	LEXOS_MAJ_SRC_DEFAUT="$BANC/inexistant" \
	bash "$OUTIL" --depuis "$SRC" "$@" 2>&1
}
empreintes() { find "$DST" -type f -exec md5sum {} + 2>/dev/null | sort; }

ok "faux clone monté ($(find "$SRC/config/includes.chroot" -type f | wc -l) fichiers)"

# =============================================================================
titre "2. « --essai » n'écrit RIEN — l'assertion qui compte"
# =============================================================================
#  Un essai qui écrit est pire que pas d'essai du tout : on lui fait confiance
#  pour vérifier AVANT d'agir. On ne se contente donc pas de regarder un
#  fichier ou deux — on prend l'empreinte de TOUTE la destination.
AVANT="$(empreintes)"
SORTIE_ESSAI="$(lance --essai)"
APRES="$(empreintes)"
if [ "$AVANT" = "$APRES" ]; then
	ok "après « --essai », pas un octet n'a changé dans la destination"
else
	non "« --essai » A MODIFIÉ la destination :"
	diff <(printf '%s\n' "$AVANT") <(printf '%s\n' "$APRES") | head -8 | sed 's/^/       /'
fi
if printf '%s' "$SORTIE_ESSAI" | grep -q 'usr/bin/lexos-truc'; then
	ok "… et il DIT quand même ce qui serait copié"
else
	non "« --essai » ne dit pas ce qu'il copierait — il ne sert à rien"
fi
if [ ! -e "$DST/etc/lexos/maj" ]; then
	ok "« --essai » n'écrit pas non plus la trace /etc/lexos/maj"
else
	non "« --essai » a écrit la trace : la machine se croirait à jour"
fi

# =============================================================================
titre "3. Le vrai passage"
# =============================================================================
SORTIE="$(lance)"

if [ -x "$DST/usr/bin/lexos-truc" ] && grep -q neuf "$DST/usr/bin/lexos-truc"; then
	ok "le fichier est copié ET reste exécutable (755 préservé)"
else
	non "le fichier n'est pas copié, ou a perdu son bit d'exécution"
fi
#  Un chmod perdu et la commande n'existe plus : on lit le mode, pas le seul
#  drapeau -x.
MODE="$(stat -c '%a' "$DST/usr/bin/lexos-truc" 2>/dev/null)"
[ "$MODE" = "755" ] \
	&& ok "le mode est exactement 755" \
	|| non "le mode est $MODE au lieu de 755"

[ -r "$DST/usr/share/lexos/ui.css" ] \
	&& ok "usr/share/lexos est copié lui aussi" \
	|| non "usr/share/lexos n'a pas été copié"
[ -r "$DST/usr/lib/lexos/settings.py" ] \
	&& ok "usr/lib/lexos est copié lui aussi" \
	|| non "usr/lib/lexos n'a pas été copié"

#  ═══ LA SAUVEGARDE ═══
#  Un fichier qu'Alex aurait ajusté à la main ne doit pas disparaître sans
#  trace.
BAK="$(find "$DST/usr/bin" -name 'lexos-truc.lexos-bak-*' | head -1)"
if [ -n "$BAK" ] && grep -q vieux "$BAK"; then
	ok "l'ancien fichier est sauvegardé en $(basename "$BAK")"
else
	non "aucune sauvegarde .lexos-bak-* de l'ancien fichier"
fi

#  ═══ LA TRACE ═══
#  Sans elle, un système mis à jour et un système d'origine se ressemblent
#  trait pour trait, et on perd deux heures à déboguer un fichier qu'on
#  croyait posé.
if [ -r "$DST/etc/lexos/maj" ]; then
	if grep -qE '[0-9a-f]{7}|hors git' "$DST/etc/lexos/maj"; then
		ok "/etc/lexos/maj note la date et le commit : $(tail -1 "$DST/etc/lexos/maj" | cut -c1-46)…"
	else
		non "/etc/lexos/maj existe mais ne contient pas de commit"
	fi
else
	non "/etc/lexos/maj n'est pas écrit — on ne saurait pas ce que porte la machine"
fi

# =============================================================================
titre "4. Ce qui vit dans l'image n'est JAMAIS touché"
# =============================================================================
#  Même avec --tout. /boot rendrait la machine non démarrable ; build.conf et
#  version feraient mentir le système sur ce qu'il est, et on ne saurait plus
#  quelle ISO il porte.
lance --tout >/dev/null 2>&1
for PAIRE in "boot/vmlinuz|NOYAU D ORIGINE" "etc/lexos/build.conf|LEXOS_BUILD=110" "etc/lexos/version|110"; do
	CHEMIN="${PAIRE%%|*}"; ATTENDU="${PAIRE##*|}"
	if grep -qxF "$ATTENDU" "$DST/$CHEMIN" 2>/dev/null; then
		ok "$CHEMIN est intact, même avec --tout"
	else
		non "$CHEMIN a été écrasé : « $(head -1 "$DST/$CHEMIN" 2>/dev/null) » au lieu de « $ATTENDU »"
	fi
done

# =============================================================================
titre "5. Les refus"
# =============================================================================
#  ═══ UN CHEMIN AU HASARD EST REFUSÉ ═══
#  Sans ce contrôle, un chemin tapé de travers déverserait n'importe quoi dans
#  /usr/bin — et il n'y a pas de retour en arrière pour ça.
mkdir -p "$BANC/pasunclone"
if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
   bash "$OUTIL" --depuis "$BANC/pasunclone" --essai >/dev/null 2>&1; then
	non "un dossier qui n'est pas un clone a été ACCEPTÉ"
else
	ok "un dossier qui n'est pas un clone est refusé (code non nul)"
fi

#  ═══ IL FAUT LES DEUX MARQUEURS, PAS UN ═══
#  Un dossier avec « config/includes.chroot » mais sans « lexos.conf » doit
#  être refusé lui aussi. Le cas ci-dessus (un dossier VIDE) ne le prouve
#  pas : il échoue déjà sur le premier marqueur, et une mutation qui retire
#  le second passerait inaperçue. C'est le piège « protégé deux fois » —
#  trouvé par une mutation, exactement comme il se doit.
mkdir -p "$BANC/moitie/config/includes.chroot"
if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
   bash "$OUTIL" --depuis "$BANC/moitie" --essai >/dev/null 2>&1; then
	non "un dossier SANS lexos.conf a été accepté — un seul marqueur suffisait"
else
	ok "un dossier sans lexos.conf est refusé (les DEUX marqueurs comptent)"
fi

#  ═══ LA LISTE DES INTERDITS, ÉPROUVÉE DIRECTEMENT ═══
#  ET VOICI POURQUOI IL LE FAUT. Les témoins /boot et build.conf plus haut
#  restent intacts même si on VIDE la liste des interdits — parce que la
#  liste BLANCHE (usr/bin, usr/lib/lexos, usr/share/…) ne visite déjà ni
#  « boot » ni « etc ». interdit() est une SECONDE ceinture qui, pour ces
#  chemins-là, n'est jamais atteinte : trois mutations l'ont montré en
#  restant vertes.
#  Une ceinture qu'aucun test ne serre finit par se détacher sans qu'on le
#  sache. On extrait donc la fonction et sa liste, et on les appelle
#  directement — le jour où quelqu'un élargit ARBRES, elle sera prête.
{
	sed -n '/^INTERDITS="/,/^"$/p' "$OUTIL"
	sed -n '/^interdit() {/,/^}/p' "$OUTIL"
	cat <<'JS'
for CAS in "boot/vmlinuz|1" "etc/lexos/build.conf|1" "etc/lexos/version|1" \
           "etc/lexos/release|1" "lib/live/config|1" \
           "usr/bin/lexos-truc|0" "usr/share/lexos/ui.css|0" "etc/lexos/maj|0"; do
	C="${CAS%%|*}"; ATTENDU="${CAS##*|}"
	if interdit "$C"; then VU=1; else VU=0; fi
	[ "$VU" = "$ATTENDU" ] && printf 'OK   %s -> %s\n' "$C" "$VU" \
	                       || printf 'RATE %s -> %s (attendu %s)\n' "$C" "$VU" "$ATTENDU"
done
JS
} > "$BANC/interdits.sh"
RES="$(bash "$BANC/interdits.sh" 2>&1)"
if printf '%s' "$RES" | grep -q 'RATE'; then
	non "interdit() se trompe :"
	printf '%s\n' "$RES" | sed 's/^/       /'
else
	ok "interdit() répond juste sur les huit chemins (5 refusés, 3 permis)"
fi

#  ═══ ET LE POINT D'APPEL, PAS SEULEMENT LA FONCTION ═══
#  Le test ci-dessus prouve qu'interdit() répond juste ; il ne prouve pas
#  qu'on l'APPELLE. Une mutation qui retirait l'appel de copier_un() restait
#  verte, parce qu'aucun chemin interdit n'entre dans le circuit avec la
#  liste blanche par défaut.
#  On élargit donc la liste à « etc » — le clone en a un, avec build.conf
#  dedans — et on exige que le témoin soit TOUJOURS intact. Si l'appel
#  disparaît, build.conf est écrasé et ce contrôle rougit.
printf 'LEXOS_BUILD=110\n' > "$DST/etc/lexos/build.conf"
LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
LEXOS_MAJ_ARBRES="etc" \
	bash "$OUTIL" --depuis "$SRC" --tout >/dev/null 2>&1
if grep -qxF 'LEXOS_BUILD=110' "$DST/etc/lexos/build.conf" 2>/dev/null; then
	ok "même en poussant « etc » dans le circuit, build.conf est refusé à la copie"
else
	non "build.conf a été écrasé quand « etc » entre dans le circuit : le garde-fou n'est pas appelé"
fi

#  ═══ UN DÉPÔT EN COURS D'ÉDITION EST REFUSÉ ═══
#  Copier un arbre qui porte des modifications non commitées, c'est poser du
#  code à moitié écrit — et le symptôme sera incompréhensible, parce que le
#  fichier fautif n'existe dans aucun commit qu'on puisse relire.
if ! command -v git >/dev/null 2>&1; then
	saut "git absent : le refus d'un dépôt sale n'a PAS été éprouvé"
else
	git -C "$SRC" init -q 2>/dev/null
	git -C "$SRC" config user.email banc@lexos >/dev/null 2>&1
	git -C "$SRC" config user.name  banc       >/dev/null 2>&1
	git -C "$SRC" add -A >/dev/null 2>&1
	git -C "$SRC" commit -qm "banc" >/dev/null 2>&1
	printf 'sale\n' > "$SRC/config/includes.chroot/usr/bin/lexos-sale"
	if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
	   bash "$OUTIL" --depuis "$SRC" --essai >/dev/null 2>&1; then
		non "un dépôt avec des modifications non commitées a été ACCEPTÉ"
	else
		ok "un dépôt en cours d'édition est refusé (code non nul)"
	fi
	rm -f "$SRC/config/includes.chroot/usr/bin/lexos-sale"
fi

#  ═══ SANS --paquets, AUCUN apt-get ═══
#  Vérifié en LISANT le programme, pas en le lançant : on ne veut pas
#  déclencher une vraie mise à jour Debian sur la machine de construction pour
#  savoir qu'elle n'aurait pas dû se déclencher.
CODE="$(sed 's/[[:space:]]*#.*$//' "$OUTIL")"
NB_APT="$(printf '%s' "$CODE" | grep -c 'apt-get\|apt ')"
if [ "$NB_APT" = "0" ]; then
	ok "aucun appel à apt dans le programme — Debian n'est touché que par « lexos upgrade »"
else
	non "$NB_APT appel(s) à apt dans le code : la mise à jour Debian pourrait partir seule"
fi

#  Sans --skel, on ne touche pas au compte courant.
if printf '%s' "$SORTIE" | grep -q "n'a PAS été reporté"; then
	ok "sans --skel, le compte courant n'est pas touché — et c'est DIT"
else
	non "rien ne signale que /etc/skel n'a pas été reporté : on croirait la mise à jour complète"
fi

# =============================================================================
titre "6. Toutes les portes mènent au même endroit"
# =============================================================================
for F in "$OUTIL" "$MISS"; do
	[ -x "$F" ] \
		&& ok "$(basename "$F") est exécutable" \
		|| non "$(basename "$F") n'est pas exécutable"
done

#  L'enrobage doit pardonner l'accent et l'espace : c'est une commande qu'on
#  tape vite, dix fois par jour.
FAUX="$BANC/cible"
printf '#!/bin/sh\nprintf "RECU:[%%s]\\n" "$*"\n' > "$FAUX"; chmod 755 "$FAUX"
sed "s|^CIBLE=.*|CIBLE=$FAUX|" "$MISS" > "$BANC/miss"; chmod 755 "$BANC/miss"

essai_porte() { # essai_porte <libellé> <args…>
	local lib="$1"; shift
	local vu
	vu="$(sh "$BANC/miss" "$@" 2>&1)"
	case "$vu" in
		RECU:*) ok "« miss $lib » atteint lexos-mise-a-jour ($vu)" ;;
		*)      non "« miss $lib » n'atteint pas la cible : $vu" ;;
	esac
}
essai_porte "a jour"  a jour
essai_porte "à jour"  à jour
essai_porte "ajour"   ajour
essai_porte "(rien)"
essai_porte "a jour --essai" a jour --essai

#  ═══ ET IL REFUSE CE QU'IL NE COMPREND PAS ═══
#  Un enrobage qui avale n'importe quoi en silence fera croire un jour qu'une
#  mise à jour a eu lieu alors qu'il y avait une faute de frappe.
SORTIE_F="$(sh "$BANC/miss" mizajour 2>&1)"; CODE_F=$?
if [ "$CODE_F" -ne 0 ] && printf '%s' "$SORTIE_F" | grep -q 'sudo miss a jour'; then
	ok "« miss mizajour » est refusé, et le message dit quoi taper"
else
	non "« miss mizajour » : code $CODE_F, sortie « $SORTIE_F »"
fi

#  ═══ LE DISPATCHEUR AUSSI ═══
CODE_D="$(sed 's/[[:space:]]*#.*$//' "$DISPATCH")"
if printf '%s' "$CODE_D" | grep -q 'maj|mise-a-jour'; then
	ok "« lexos maj » et « lexos mise-a-jour » sont dans le dispatcheur"
else
	non "le dispatcheur ne connaît pas « maj »"
fi
if printf '%s' "$CODE_D" | grep -q 'exec /usr/bin/lexos-mise-a-jour'; then
	ok "le dispatcheur fait EXEC vers l'outil — il ne réimplémente rien"
else
	non "le dispatcheur n'appelle pas l'outil par exec"
fi
#  L'aide doit distinguer les trois, sinon personne ne saura laquelle taper.
if grep -q 'Mettre à jour LexOS lui-même depuis le dépôt' "$DISPATCH"; then
	ok "l'aide distingue « maj » de « update » et « upgrade »"
else
	non "l'aide ne dit pas en quoi « maj » diffère des deux autres"
fi

#  ═══ AUCUNE LOGIQUE DE COPIE DUPLIQUÉE ═══
#  ON LIT LE CODE, PAS LES COMMENTAIRES. Les deux fichiers EXPLIQUENT en
#  commentaire qu'ils ne doivent contenir ni rsync, ni « cp -a », ni
#  « .lexos-bak » — et un grep naïf trouverait ces mots-là dans l'explication
#  elle-même. C'est le piège qui s'est refermé cinq fois dans ce chantier ;
#  on décommente d'abord.
DOUBLON=0
for F in "$MISS" "$DISPATCH"; do
	NU="$(sed 's/[[:space:]]*#.*$//' "$F")"
	for MOTIF in 'rsync' 'cp -a' '\.lexos-bak'; do
		if printf '%s' "$NU" | grep -q -- "$MOTIF"; then
			non "$(basename "$F") contient « $MOTIF » : la logique de copie est dupliquée"
			DOUBLON=1
		fi
	done
done
[ "$DOUBLON" = 0 ] && ok "ni miss ni lexos ne dupliquent la logique de copie"

# =============================================================================
titre "7. Le garde de construction — « miss » est-il libre ?"
# =============================================================================
#  LA QUESTION NE PEUT PAS SE RÉPONDRE DEPUIS LE DÉPÔT. « apt-file » demande
#  un index qu'on n'a pas toujours, et « dpkg -S » sur la machine de
#  développement ne répond que pour les paquets installés LÀ — pas pour la
#  suite Debian qu'on assemble. La seule machine qui connaisse la vérité,
#  c'est le chroot en cours de construction.
#
#  Le hook 0255 pose donc la question À DPKG, dans le chroot, et ARRÊTE la
#  construction en cas de collision. Ici on éprouve le hook lui-même.
if ! command -v dpkg >/dev/null 2>&1; then
	saut "dpkg absent : le garde n'a PAS été éprouvé"
else
	#  Cas négatif : un dossier de faux binaires, dpkg n'en connaît aucun.
	FAUXBIN="$BANC/bin"
	mkdir -p "$FAUXBIN"; : > "$FAUXBIN/lexos-truc"; : > "$FAUXBIN/miss"
	if LEXOS_BIN_DIR="$FAUXBIN" sh "$GARDE" >/dev/null 2>&1; then
		ok "sans collision, le garde laisse passer"
	else
		non "le garde échoue alors qu'il n'y a aucune collision"
	fi

	#  ═══ CAS POSITIF : ON PROVOQUE UNE VRAIE COLLISION ═══
	#  Un contrôle qui ne sait que dire « rien à signaler » ne prouve rien.
	#  On fait passer un binaire RÉELLEMENT possédé par un paquet pour un des
	#  nôtres, et on exige que le garde s'arrête. Sans ça, on ne saurait pas
	#  s'il regarde vraiment.
	POSSEDE=""
	for C in ls cat sh; do
		if dpkg -S "/usr/bin/$C" >/dev/null 2>&1; then POSSEDE="$C"; break; fi
	done
	if [ -z "$POSSEDE" ]; then
		saut "aucun binaire dpkg trouvé ici : le cas positif n'a PAS été éprouvé"
	else
		sed "s/^\t\tlexos\*|miss) ;;/\t\tlexos*|miss|$POSSEDE) ;;/" "$GARDE" > "$BANC/garde"
		if LEXOS_BIN_DIR=/usr/bin sh "$BANC/garde" >/dev/null 2>&1; then
			non "le garde N'A PAS vu une collision réelle (/usr/bin/$POSSEDE) — il ne protège rien"
		else
			ok "face à une collision réelle (/usr/bin/$POSSEDE), le garde ARRÊTE la construction"
		fi
	fi
fi

#  Et il examine bien « miss », pas seulement les noms en « lexos » : c'est
#  précisément le nom générique qui a motivé tout ce contrôle.
if grep -q 'lexos\*|miss)' "$GARDE"; then
	ok "le garde surveille « miss » nommément"
else
	non "le garde ne surveille pas « miss » — le nom le plus exposé"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mToutes les portes mènent au même endroit, et « --essai » n'\''écrit rien.\033[0m\n'
