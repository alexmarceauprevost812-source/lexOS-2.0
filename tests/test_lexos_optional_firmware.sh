#!/usr/bin/env bash
# =============================================================================
#  Éprouver le hook 0250 — le matériel vital ne disparaît plus en silence
# =============================================================================
#  Relevé sur l'Alienware Aurora ACT1250 d'Alex : firmware-iwlwifi,
#  firmware-realtek, intel-microcode… vivent dans une liste « au mieux ».
#  Avant ce banc, leur absence finissait comme une ligne « !! indisponible »
#  noyée dans une heure de journal de construction — l'ISO sortait sans
#  Wi-Fi, sans un mot de plus. Ce banc rejoue le hook réel (mêmes chemins
#  d'apt, même boucle de reprise) avec de faux apt/dpkg/systemctl/modinfo
#  sur un PATH fermé, et vérifie que :
#    · du matériel vital manquant se voit toujours dans le journal ;
#    · LEXOS_STRICT_FIRMWARE=1 en fait une construction qui échoue ;
#    · sans lui, la construction continue (mieux vaut une ISO qui démarre
#      sans Wi-Fi qu'aucune ISO du tout) ;
#    · la passe groupée qui réussit d'un bloc ne déclenche AUCUNE de ces
#      vérifications — c'est correct, tout est alors garanti présent ;
#    · le rapport iwlwifi (fichiers embarqués / versions réclamées par le
#      noyau) dit VRAIMENT « aucun » quand il n'y a rien — pas le bogue
#      trouvé en écrivant ce banc : un « ls … | sed … || repli » se
#      rattache au code de sortie de sed, qui réussit même sur une entrée
#      vide, et le repli ne se déclenchait donc JAMAIS.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0250-lexos-optional.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -f "$HOOK" ] || { echo "hook 0250 introuvable"; exit 1; }

FAUXBIN="$BANC/bin"
CTRL="$BANC/ctrl"
DIR="$BANC/optional-packages"
REPORT="$BANC/optional-report"
CONF="$BANC/build.conf"
FWDIR="$BANC/firmware"

# --- Les listes de paquets, minimales et déterministes -----------------------
#  FLAVOUR=minimal : LISTS se limite à 00-core.list + 10-installer.list, sans
#  déclencher les « listes absentes » des 25 autres listes du bureau complet
#  — bruit inutile pour ce qu'on éprouve ici.
pose_listes() { # pose_listes <paquets de 00-core.list, un par ligne>
	mkdir -p "$DIR"
	printf '%s\n' "$@" > "$DIR/00-core.list"
	echo "paquet-installateur-inoffensif" > "$DIR/10-installer.list"
}

# --- De faux apt-get / dpkg / systemctl / modinfo ---------------------------
#  L'appel GROUPÉ ("apt-get install … PKG1 PKG2 …", plusieurs paquets)
#  réussit sauf si $CTRL/bulk_echoue existe. L'appel UNITAIRE de la reprise
#  (un seul paquet) échoue seulement pour les noms listés dans
#  $CTRL/echoue_<paquet>.
pose_faux_outils() {
	mkdir -p "$FAUXBIN" "$CTRL"
	cat > "$FAUXBIN/apt-get" <<EOF
#!/bin/sh
if [ "\$1" = "update" ]; then exit 0; fi
if [ "\$1" = "install" ]; then
	shift
	PKGS=""
	for a in "\$@"; do
		case "\$a" in
			-y|--no-install-recommends) ;;
			*) PKGS="\$PKGS \$a" ;;
		esac
	done
	# shellcheck disable=SC2086
	set -- \$PKGS
	if [ "\$#" -gt 1 ]; then
		[ -f "$CTRL/bulk_echoue" ] && exit 1
		exit 0
	fi
	[ -f "$CTRL/echoue_\$1" ] && exit 1
	exit 0
fi
exit 0
EOF
	cat > "$FAUXBIN/dpkg" <<'EOF'
#!/bin/sh
exit 0
EOF
	# dpkg-query : « installé » seulement pour les paquets marqués par
	# $CTRL/dpkg_installe_<paquet> — même patron que modinfo_sortie plus
	# bas (un fichier de contrôle par scénario, rien de plus).
	cat > "$FAUXBIN/dpkg-query" <<EOF
#!/bin/sh
# usage réel : dpkg-query -W -f='\${Status}' <paquet>
paquet="\$3"
if [ -f "$CTRL/dpkg_installe_\$paquet" ]; then
	printf 'install ok installed'
	exit 0
fi
exit 1
EOF
	cat > "$FAUXBIN/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
	# modinfo : sans argument de contrôle, se comporte comme "carte absente"
	# (rien à afficher) — le scénario 6 le fait parler.
	cat > "$FAUXBIN/modinfo" <<EOF
#!/bin/sh
[ -f "$CTRL/modinfo_sortie" ] && cat "$CTRL/modinfo_sortie"
exit 0
EOF
	chmod +x "$FAUXBIN"/apt-get "$FAUXBIN"/dpkg "$FAUXBIN"/dpkg-query "$FAUXBIN"/systemctl "$FAUXBIN"/modinfo
}

reinit() {
	rm -rf "$FAUXBIN" "$CTRL" "$DIR" "$FWDIR"
	rm -f "$REPORT" "$CONF"
	mkdir -p "$FWDIR"
	echo "LEXOS_FLAVOUR=minimal" > "$CONF"
	pose_faux_outils
}

lance() { # lance [LEXOS_STRICT_FIRMWARE=1 ...] -> sortie complète + $? dans $BANC/code
	PATH="$FAUXBIN:$PATH" \
	LEXOS_OPTIONAL_DIR="$DIR" LEXOS_OPTIONAL_REPORT="$REPORT" \
	LEXOS_BUILD_CONF="$CONF" LEXOS_FIRMWARE_DIR="$FWDIR" \
	"$@" sh "$HOOK" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

# =============================================================================
titre "1. firmware-iwlwifi manquant, sans LEXOS_STRICT_FIRMWARE -> ça le DIT, ça continue"
# =============================================================================
reinit
pose_listes "firmware-iwlwifi" "thunar"
touch "$CTRL/bulk_echoue"          # force la reprise un par un
touch "$CTRL/echoue_firmware-iwlwifi"
S="$(lance env)"
CODE="$(cat "$BANC/code")"
if echo "$S" | grep -q "MATÉRIEL VITAL ABSENT :.*firmware-iwlwifi"; then
	ok "l'absence de firmware-iwlwifi est signalée EN CLAIR dans le journal"
else
	non "rien vu sur le matériel vital manquant :\n$S"
fi
[ "$CODE" = "0" ] \
	&& ok "sans LEXOS_STRICT_FIRMWARE, la construction continue (code 0)" \
	|| non "la construction s'est arrêtée sans qu'on le demande (code $CODE)"

# =============================================================================
titre "2. Le même manque, avec LEXOS_STRICT_FIRMWARE=1 -> la construction s'arrête"
# =============================================================================
reinit
pose_listes "firmware-iwlwifi" "thunar"
touch "$CTRL/bulk_echoue"
touch "$CTRL/echoue_firmware-iwlwifi"
S="$(lance env LEXOS_STRICT_FIRMWARE=1)"
CODE="$(cat "$BANC/code")"
[ "$CODE" = "1" ] \
	&& ok "LEXOS_STRICT_FIRMWARE=1 fait échouer la construction (code 1)" \
	|| non "attendu code 1, obtenu $CODE"
echo "$S" | grep -q "on s'arrête ici" \
	&& ok "et le dit explicitement, pas un échec muet" \
	|| non "le journal ne dit pas pourquoi ça s'est arrêté"

# =============================================================================
titre "3. Tout le matériel vital est présent -> aucune alerte, ça le dit calmement"
# =============================================================================
reinit
pose_listes "thunar" "mousepad"
touch "$CTRL/bulk_echoue"          # force quand même la reprise un par un
S="$(lance env)"
CODE="$(cat "$BANC/code")"
[ "$CODE" = "0" ] || non "code inattendu : $CODE"
if echo "$S" | grep -q "MATÉRIEL VITAL ABSENT"; then
	non "une alerte est sortie alors que rien de vital ne manquait :\n$S"
else
	ok "aucune alerte matériel vital quand tout est là"
fi
echo "$S" | grep -q "matériel vital : 6 paquets, tous présents" \
	&& ok "et le journal le confirme positivement (6 paquets vitaux, tous présents)" \
	|| non "le message positif attendu est absent"

# =============================================================================
titre "4. La passe groupée réussit d'un bloc -> aucune vérification matériel, et c'est CORRECT"
# =============================================================================
#  Le doc d'audit prévient : quand l'installation groupée réussit, TOUS les
#  paquets de \$WANTED sont garantis installés — la vérification n'a rien à
#  faire là, et il ne faut pas la déplacer plus haut en croyant réparer un
#  oubli.
reinit
pose_listes "firmware-iwlwifi" "thunar"
# pas de bulk_echoue : la première passe réussit
S="$(lance env)"
CODE="$(cat "$BANC/code")"
[ "$CODE" = "0" ] || non "code inattendu : $CODE"
echo "$S" | grep -q "tous les paquets optionnels installés d'un bloc" \
	&& ok "la passe groupée a bien réussi d'un bloc" \
	|| non "la passe groupée n'a pas pris le chemin attendu :\n$S"
if echo "$S" | grep -qE "MATÉRIEL VITAL|matériel vital :"; then
	non "le bloc matériel vital a tourné après un succès groupé — il ne devrait pas"
else
	ok "le bloc matériel vital ne tourne pas après un succès groupé (comportement voulu)"
fi

# =============================================================================
titre "5. Micrologiciels iwlwifi présents -> le journal les liste vraiment"
# =============================================================================
reinit
pose_listes "thunar"
touch "$FWDIR/iwlwifi-gl-c0-fm-c0-92.ucode"
touch "$FWDIR/iwlwifi-gl-c0-fm-c0.pnvm"
S="$(lance env)"
if echo "$S" | grep -q "iwlwifi-gl-c0-fm-c0-92.ucode" && echo "$S" | grep -q "présents dans l'image"; then
	ok "les fichiers iwlwifi réellement présents sont listés"
else
	non "les fichiers présents n'apparaissent pas dans le journal :\n$S"
fi

# =============================================================================
titre "6. AUCUN micrologiciel iwlwifi -> le journal dit « aucun », pas rien du tout"
# =============================================================================
#  C'est le scénario qui attrape le bogue trouvé en écrivant ce banc : avant
#  la correction, « ls … | sed … || echo aucun » ne se déclenchait JAMAIS,
#  parce que le code de sortie testé était celui de sed (toujours 0), pas
#  celui de ls. Un dossier de micrologiciels vide passait donc en silence.
reinit
pose_listes "thunar"
# $FWDIR existe (via reinit) mais reste VIDE : aucun fichier iwlwifi-gl-*
S="$(lance env)"
if echo "$S" | grep -q "AUCUN fichier iwlwifi-gl"; then
	ok "un dossier de micrologiciels vide est signalé « AUCUN fichier », pas passé sous silence"
else
	non "le repli « aucun fichier » ne s'est PAS déclenché sur un dossier vide :\n$S"
fi

# =============================================================================
titre "7. Le pilote du noyau réclame des versions -> le journal les répète"
# =============================================================================
reinit
pose_listes "thunar"
printf 'firmware: iwlwifi-gl-c0-fm-c0-92.ucode\nfirmware: iwlwifi-gl-c0-fm-c0-93.ucode\n' > "$CTRL/modinfo_sortie"
S="$(lance env)"
if echo "$S" | grep -q "versions réclamées par le pilote iwlwifi" && echo "$S" | grep -q "iwlwifi-gl-c0-fm-c0-92.ucode"; then
	ok "les versions réclamées par le pilote (modinfo) sont répétées dans le journal"
else
	non "les versions réclamées n'apparaissent pas :\n$S"
fi

# =============================================================================
titre "8. modinfo muet (aucune version trouvée) -> le journal le dit, pas un silence"
# =============================================================================
reinit
pose_listes "thunar"
# pas de $CTRL/modinfo_sortie : le faux modinfo ne rend rien
S="$(lance env)"
if echo "$S" | grep -q "modinfo muet"; then
	ok "modinfo sans résultat est signalé, pas silencieusement ignoré"
else
	non "aucun message quand modinfo ne rend rien :\n$S"
fi

# =============================================================================
titre "9. Le son : ni PulseAudio intrus, ni greffon Bluetooth absent -> tout est calme"
# =============================================================================
#  pipewire-audio est passé en STRICT (flavours/pro/pro.list.chroot) : ce
#  hook ne l'installe donc plus jamais lui-même — MATERIEL_VITAL ne le
#  concerne pas. Ce qu'il reste à surveiller, ce n'est plus une absence,
#  c'est une INTRUSION : blueman recommande « pulseaudio-module-bluetooth |
#  libspa-0.2-bluetooth », une alternative dont APT satisfait la première
#  qui se résout — un vrai démon PulseAudio pourrait entrer à côté de
#  PipeWire, deux serveurs de son sur la même carte, et le greffon dont
#  PipeWire a réellement besoin resterait absent : un casque Bluetooth qui
#  s'appaire et reste muet, sans la moindre erreur.
reinit
pose_listes "thunar"
touch "$CTRL/dpkg_installe_libspa-0.2-bluetooth"   # PulseAudio absent, greffon présent
S="$(lance env)"
if echo "$S" | grep -q "son : PipeWire seul, pas de PulseAudio"; then
	ok "PulseAudio absent -> ça le dit calmement, pas d'alerte"
else
	non "rien vu sur l'absence de PulseAudio :\n$S"
fi
if echo "$S" | grep -q "son Bluetooth : greffon libspa-0.2-bluetooth présent"; then
	ok "greffon Bluetooth présent -> ça le dit calmement"
else
	non "rien vu sur la présence du greffon Bluetooth :\n$S"
fi
if echo "$S" | grep -q "PULSEAUDIO EST INSTALLÉ"; then
	non "fausse alerte PulseAudio alors qu'il n'est pas installé :\n$S"
else
	ok "pas de fausse alerte quand tout va bien"
fi

# =============================================================================
titre "10. PulseAudio s'est glissé par la porte de derrière -> alerte, pas un silence"
# =============================================================================
#  LE CAS QUI COMPTE : le casque Bluetooth d'Alex (MEREDO D40) s'appaire, se
#  connecte, apparaît dans la liste des périphériques — et reste muet. Rien
#  dans le journal ne le dirait sans cette vérification.
reinit
pose_listes "thunar"
touch "$CTRL/dpkg_installe_pulseaudio"
S="$(lance env)"
if echo "$S" | grep -q "PULSEAUDIO EST INSTALLÉ alors que LexOS tourne sur PipeWire"; then
	ok "PulseAudio installé -> alerte EN CLAIR dans le journal"
else
	non "PulseAudio installé sans que rien ne le signale :\n$S"
fi
echo "$S" | grep -q "apt-cache rdepends --installed pulseaudio" \
	&& ok "et la commande pour trouver qui l'a tiré est donnée" \
	|| non "aucune piste pour savoir qui a tiré PulseAudio"

# =============================================================================
titre "11. Le greffon Bluetooth manque malgré tout -> alerte, pas un silence"
# =============================================================================
#  N'ARRIVE PLUS EN PRATIQUE UNE FOIS pipewire-audio STRICT (il le tire en
#  dépendance dure) — mais CE hook ne le sait pas : il lit dpkg, pas
#  flavours/pro/pro.list.chroot. Le contrôle doit rester honnête même si le
#  scénario qu'il visait à l'origine est devenu, par construction, très
#  improbable.
reinit
pose_listes "thunar"
# ni $CTRL/dpkg_installe_pulseaudio ni …_libspa-0.2-bluetooth : rien n'est installé
S="$(lance env)"
if echo "$S" | grep -q "GREFFON BLUETOOTH ABSENT"; then
	ok "greffon Bluetooth absent -> alerte EN CLAIR, pas un silence"
else
	non "greffon Bluetooth absent sans que rien ne le signale :\n$S"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
