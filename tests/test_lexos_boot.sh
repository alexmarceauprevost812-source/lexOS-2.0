#!/usr/bin/env bash
# =============================================================================
#  Éprouver la « santé du démarrage » — Secure Boot et mode RAID du disque
# =============================================================================
#  DEUX RÉGLAGES DU BIOS FONT PASSER CETTE MACHINE POUR CASSÉE
#
#    · Secure Boot actif  →  le pilote NVIDIA, compilé donc non signé, est
#      refusé par le noyau. Et comme « nouveau » est en liste noire (à raison :
#      il ne sait pas lire les sorties d'une RTX 50), il ne reste AUCUN pilote
#      graphique. Écran noir, sans un mot d'explication.
#
#    · Disque en « RAID On »  →  le NVMe passe derrière un contrôleur Intel
#      RST/VMD que Linux n'ouvre pas. LexOS démarre très bien depuis la clé,
#      et l'installateur affiche une liste de disques VIDE. Sans erreur.
#
#  Dans les deux cas la machine va parfaitement bien. Trois lignes de message
#  changent tout — À CONDITION QU'ELLES SOIENT JUSTES. Un avertissement qui se
#  déclenche à tort envoie chercher dans le BIOS pour rien ; un avertissement
#  qui ne se déclenche jamais ne sert à rien du tout, et c'est le plus
#  probable des deux : personne ne remarque un contrôle qui reste muet.
#
#  D'où ce banc. Les deux fonctions lisent /sys et /dev, qu'on ne peut pas
#  fabriquer ici — elles acceptent donc une racine de rechange (LEXOS_EFIVARS,
#  LEXOS_DEV) et un PATH fermé pour lspci. Chaque cas est JOUÉ.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAG="$RACINE/config/includes.chroot/usr/share/lexos/shell/secure-boot.sh"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# --- Un faux lspci, qui dit ce qu'on lui a écrit -----------------------------
faux_lspci() { # faux_lspci <lignes…>  (rien = pas de lspci du tout)
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	[ "$#" -gt 0 ] || return 0
	{ echo '#!/bin/sh'; printf 'cat <<'"'"'FIN'"'"'\n'; printf '%s\n' "$@"; echo 'FIN'; } \
		> "$BANC/bin/lspci"
	chmod +x "$BANC/bin/lspci"
}

#  Un PATH fermé : le banc ne doit pas retomber par hasard sur le vrai lspci
#  de la machine de construction — il dirait ce que CETTE machine a, pas ce
#  qu'on lui demande de jouer.
NECESSAIRES="sh bash sed awk grep od cat printf echo ls mktemp head rm mkdir chmod"
ferme_path() {
	rm -rf "${BANC:?}/min"; mkdir -p "$BANC/min"
	for c in $NECESSAIRES; do
		reel="$(command -v "$c" 2>/dev/null)" && ln -sf "$reel" "$BANC/min/$c"
	done
}
ferme_path

# --- Poser une fausse variable EFI ------------------------------------------
#  Le fichier fait 5 octets : 4 d'attributs UEFI, puis la valeur. Le cinquième
#  vaut 1 quand Secure Boot est actif. On l'écrit octet par octet — pas de
#  « echo » qui ajouterait un saut de ligne et décalerait tout.
pose_efi() { # pose_efi <valeur|absent>
	rm -rf "${BANC:?}/efi"; mkdir -p "$BANC/efi"
	[ "$1" = "absent" ] && return 0
	printf '\006\000\000\000' > "$BANC/efi/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
	printf "\\$(printf '%03o' "$1")" >> "$BANC/efi/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
}

pose_dev() { # pose_dev <avec-nvme|sans-nvme>
	rm -rf "${BANC:?}/dev"; mkdir -p "$BANC/dev"
	[ "$1" = "avec-nvme" ] && : > "$BANC/dev/nvme0n1"
	return 0
}

demande() { # demande <fonction>  → rend le code de la fonction
	PATH="$BANC/bin:$BANC/min" \
	LEXOS_EFIVARS="$BANC/efi" LEXOS_DEV="$BANC/dev" \
	sh -c ". '$FRAG'; $1" >/dev/null 2>&1
}
dit() { # dit <fonction>  → rend le texte
	PATH="$BANC/bin:$BANC/min" \
	LEXOS_EFIVARS="$BANC/efi" LEXOS_DEV="$BANC/dev" \
	sh -c ". '$FRAG'; $1" 2>&1
}

# =============================================================================
titre "1. Secure Boot — les quatre états d'une machine réelle"
# =============================================================================
pose_dev sans-nvme; faux_lspci

pose_efi 1
demande secure_boot_actif && ok "actif : le cinquième octet vaut 1 → on le dit" \
	|| non "Secure Boot actif non détecté — l'écran noir resterait inexpliqué"
dit secure_boot_dire | grep -q 'SECURE BOOT : ACTIF' \
	&& ok "et le message le nomme en toutes lettres" || non "message d'alerte absent"
dit secure_boot_dire | grep -q 'F2' \
	&& ok "le message dit QUELLE TOUCHE taper (pas « voir le BIOS »)" \
	|| non "le message n'explique pas comment le désactiver"

pose_efi 0
demande secure_boot_actif && non "Secure Boot annoncé actif alors que l'octet vaut 0" \
	|| ok "inactif : on n'accuse pas Secure Boot d'un écran noir dont il n'est pas la cause"

pose_efi absent
demande secure_boot_actif && non "aucune variable EFI, et pourtant « actif »" \
	|| ok "machine en BIOS hérité (pas de variable) : silence, et c'est le bon choix"

#  Le fichier existe mais est illisible/tronqué : le doute doit pencher vers
#  « inactif ». Une alerte à tort renvoie fouiller un BIOS qui va bien.
rm -rf "$BANC/efi"; mkdir -p "$BANC/efi"
: > "$BANC/efi/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
demande secure_boot_actif && non "fichier vide interprété comme « actif »" \
	|| ok "variable tronquée : le doute penche vers « inactif »"

# =============================================================================
titre "2. Le mode RAID — DEUX conditions, jamais une seule"
# =============================================================================
VMD="0000:00:0e.0 RAID bus controller: Intel Corporation Volume Management Device NVMe RAID Controller"
GPU="0000:01:00.0 VGA compatible controller: NVIDIA Corporation GB206 [GeForce RTX 5060]"

pose_efi absent
pose_dev sans-nvme; faux_lspci "$VMD" "$GPU"
demande mode_raid_probable \
	&& ok "contrôleur VMD présent ET aucun NVMe derrière → on prévient" \
	|| non "le cas exact de l'Alienware d'usine n'est pas détecté"
dit mode_raid_dire | grep -q 'AHCI' \
	&& ok "et le message nomme le réglage à changer" || non "le message ne dit pas quoi faire"
dit mode_raid_dire | grep -q 'INACCESSIBLE_BOOT_DEVICE' \
	&& ok "il prévient aussi pour Windows (le piège du double démarrage)" \
	|| non "rien sur Windows — l'utilisateur perdrait son autre système sans être prévenu"

pose_dev avec-nvme; faux_lspci "$VMD" "$GPU"
demande mode_raid_probable \
	&& non "un NVMe est visible et on crie quand même au mode RAID" \
	|| ok "le disque est visible : rien à signaler, même avec un contrôleur RAID"

pose_dev sans-nvme; faux_lspci "$GPU"
demande mode_raid_probable \
	&& non "aucun contrôleur RAID, et pourtant l'alerte se déclenche" \
	|| ok "une machine sans NVMe et sans contrôleur RAID ne déclenche rien"

# =============================================================================
titre "3. Sans lspci : dire « je ne peux pas savoir », pas « tout va bien »"
# =============================================================================
#  C'EST LE PIÈGE QUE LE DOSSIER NOMMAIT : un contrôle qui, faute d'outil,
#  répond toujours « rien à signaler » a l'air de contrôler et ne contrôle
#  rien. On le distingue donc du vrai « non ».
pose_dev sans-nvme; faux_lspci
demande mode_raid_probable && non "sans lspci, il conclut quand même au mode RAID" \
	|| ok "sans lspci, il ne conclut pas au mode RAID"
dit mode_raid_dire | grep -q 'impossible à vérifier' \
	&& ok "et il DIT qu'il n'a pas pu vérifier (pas « rien d'anormal »)" \
	|| non "sans lspci, il annonce « rien d'anormal » — un contrôle qui ne contrôle rien"

# =============================================================================
titre "4. Le fragment reste utilisable par les DEUX outils"
# =============================================================================
#  lexos-tv est en #!/bin/sh, lexos-materiel en bash. Une tournure bash ici et
#  le fragment cesserait de fonctionner dans lexos-tv — EN SILENCE : la
#  fonction deviendrait introuvable et l'appelant conclurait « rien à dire ».
#  LES COMMENTAIRES NE COMPTENT PAS — leçon du build 68, où la moitié des
#  « survivants » d'un rapport étaient des mots de commentaire. Ce fichier-ci
#  EXPLIQUE justement de ne pas employer [[ ]] : sans ce filtre, le banc
#  s'accuserait lui-même de la faute qu'il met en garde contre.
sed 's/#.*//' "$FRAG" > "$BANC/frag-code.sh"
if grep -qE '\[\[|declare |local -a|<<<' "$BANC/frag-code.sh"; then
	non "une tournure bash s'est glissée dans le CODE du fragment POSIX"
else
	ok "aucune tournure bash dans le code : lexos-tv (#!/bin/sh) peut s'en servir"
fi
#  Et la preuve par l'usage : un shell POSIX strict le charge-t-il ?
if (unset BASH_VERSION; sh -c ". '$FRAG'; secure_boot_actif; mode_raid_probable" >/dev/null 2>&1; [ $? -le 1 ]); then
	ok "un /bin/sh strict charge le fragment et trouve les deux fonctions"
else
	non "le fragment ne se charge pas dans un /bin/sh strict"
fi
for OUTIL in lexos-tv lexos-materiel; do
	grep -q 'secure-boot.sh' "$RACINE/config/includes.chroot/usr/bin/$OUTIL" \
		&& ok "$OUTIL charge bien le fragment" \
		|| non "$OUTIL ne charge pas le fragment — son diagnostic reste muet"
done
for OUTIL in lexos-tv lexos-materiel; do
	grep -q 'mode_raid' "$RACINE/config/includes.chroot/usr/bin/$OUTIL" \
		&& ok "$OUTIL parle du mode du disque" \
		|| non "$OUTIL ne dit rien du mode RAID"
	grep -q 'nvidia-report' "$RACINE/config/includes.chroot/usr/bin/$OUTIL" \
		&& ok "$OUTIL montre le rapport du pilote (il n'était affiché nulle part)" \
		|| non "$OUTIL n'affiche pas /etc/lexos/nvidia-report"
done

# =============================================================================
titre "5. La règle de version NVIDIA ne gèle plus l'avenir"
# =============================================================================
HOOK="$RACINE/config/hooks/normal/0260-lexos-nvidia.hook.chroot"
grep -q 'version_avant_610' "$HOOK" \
	&& non "l'ancien nom subsiste : un appel manqué rendrait vide et on retomberait sur la 610" \
	|| ok "plus aucune trace de « version_avant_610 »"
grep -q 'BRANCHES_ECARTEES="610"' "$HOOK" \
	&& ok "la 610 est écartée PAR SON NOM, pas par « tout ce qui est au-dessus »" \
	|| non "la liste des branches écartées a changé de forme"
grep -q 'ne propose rien avant la branche 610' "$HOOK" \
	&& non "un message du journal nomme encore « 610 » en dur" \
	|| ok "les messages du journal nomment la variable, pas un numéro figé"

#  La règle elle-même, JOUÉE sur des listes inventées : c'est le seul moyen de
#  savoir qu'une 615 future serait bien retenue.
regle() { # regle <versions…>
	{ sed -n '/^BRANCHES_ECARTEES=/,/^}/p' "$HOOK"
	  sed -n '/^version_utilisable() {/,/^}/p' "$HOOK"
	  echo 'version_utilisable'
	} > "$BANC/regle.sh"
	VERSIONS_PILOTE="$(printf '%s\n' "$@")" VERSIONS_DISPO="" \
		sh "$BANC/regle.sh" 2>/dev/null
}
[ "$(regle 610.57.04 610.43.02 595.91.07 590.44.01)" = "595.91.07" ] \
	&& ok "aujourd'hui : 595.91.07 est toujours la réponse (rien n'a changé)" \
	|| non "la version retenue a changé : $(regle 610.57.04 610.43.02 595.91.07 590.44.01)"
[ "$(regle 615.10.01 610.57.04 595.91.07)" = "615.10.01" ] \
	&& ok "demain : une 615 serait PRISE (l'ancienne règle l'aurait écartée à jamais)" \
	|| non "une 615 future serait encore écartée — LexOS gelé sur la 595"
[ "$(regle 610.57.04 610.43.02)" = "" ] \
	&& ok "et si le dépôt n'a QUE du 610, il ne rend rien (le repli prend le relais)" \
	|| non "une version écartée a été retenue"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
