#!/usr/bin/env bash
# =============================================================================
#  L'ISO PRO RTX 5060 : NOYAU 7.2.9 PAR DÉFAUT, PILOTE SIGNÉ LEXOS, /boot EN CLAIR
# =============================================================================
#  CE QUE CE BANC ÉPROUVE, sur les fichiers LIVRÉS (pas des copies) :
#  1. hook 0907 — sur le VRAI grub.cfg de l'ISO du 20 octobre (build 122),
#     l'entrée par défaut démarre le noyau le plus récent, celui qui a le
#     pilote ; chaque titre dit vrai, entrée par entrée ; chaque entrée dit
#     ce qu'elle charge ; rejoué (reprise de lb build) ou coupé, le hook ne
#     gâte pas le menu ; un fichier absent, une première entrée sur l'ancien
#     noyau ou un titre qui ment font échouer la construction et remettent
#     le menu ; la même garde, extraite de build-iso.yml, refuse l'ISO du
#     20 octobre ;
#  2. hook 0915 — MokManager entre dans une efi.img PLEINE (reconstruite plus
#     grande, contenu intact) et dans l'arborescence ; deux certificats
#     différents font échouer ;
#  3. hook 9890 — la signature d'un module se retire et se remet sans
#     s'empiler ; sur un vrai module du noyau et le vrai sign-file quand le
#     coureur les a ;
#  4. le hook initramfs retire nouveau et son micrologiciel, et SEULEMENT
#     quand nouveau est en liste noire ;
#  5. partition.conf — un /boot séparé et non chiffré (sinon GRUB bute sur le
#     LUKS2 Argon2id : « Invalid passphrase ») ;
#  6. aucune clé privée versionnée, et le workflow vérifie le squashfs.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$RACINE/config/hooks/normal"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# ===========================================================================
titre "1. LE MENU UEFI DÉMARRE LE NOYAU QUI A LE PILOTE (hook 0907)"
# ===========================================================================
K_ANCIEN="6.12.113+deb13-amd64"; K_RECENT="7.2.9+deb13-amd64"
scene_0907() {
	rm -rf "$BANC/s7"
	mkdir -p "$BANC/s7/binary/boot/grub" "$BANC/s7/binary/live" \
		"$BANC/s7/chroot/lib/modules/$K_RECENT/updates/dkms" "$BANC/s7/chroot/lib/modules/$K_ANCIEN/kernel"
	cp "$RACINE/tests/donnees/grub-iso-build122.cfg" "$BANC/s7/binary/boot/grub/grub.cfg"
	for v in "$K_ANCIEN" "$K_RECENT"; do
		echo x > "$BANC/s7/binary/live/vmlinuz-$v"; echo x > "$BANC/s7/binary/live/initrd.img-$v"
	done
	: > "$BANC/s7/chroot/lib/modules/$K_RECENT/updates/dkms/nvidia.ko.xz"
}
scene_0907
#  On capture, puis on cherche : pas de « grep -q » en bout de tube (règle
#  du dépôt — sous pipefail, -q coupe le tube et le producteur meurt).
DEPART="$(grep -m1 -E '^[[:space:]]*linux' "$BANC/s7/binary/boot/grub/grub.cfg")"
[[ "$DEPART" == *"vmlinuz-$K_ANCIEN"* ]] \
	&& ok "point de départ réel : l'ISO du 20 octobre démarrait $K_ANCIEN par défaut" \
	|| non "la donnée de référence n'est plus celle de l'ISO du 20 octobre"

SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
CFG="$BANC/s7/binary/boot/grub/grub.cfg"
[ "$RC" -eq 0 ] && ok "le hook passe sur le vrai menu" || non "le hook échoue sur le vrai menu : $(printf '%s' "$SORTIE" | tail -3 | tr '\n' ' ')"
#  Le menu réécrit sert de référence aux scènes qui suivent.
cp "$CFG" "$BANC/menu-reecrit.cfg"
PREMIER="$(grep -m1 -E '^[[:space:]]*linux' "$CFG" | awk '{print $2}')"
[ "$PREMIER" = "/live/vmlinuz-$K_RECENT" ] \
	&& ok "l'entrée par défaut démarre $K_RECENT" \
	|| non "l'entrée par défaut démarre ${PREMIER:-rien}"
PREMIER_INITRD="$(grep -m1 -E '^[[:space:]]*initrd' "$CFG" | awk '{print $2}')"
[ "$PREMIER_INITRD" = "/live/initrd.img-$K_RECENT" ] \
	&& ok "…avec l'initrd du même noyau" \
	|| non "noyau et initrd ne correspondent pas : ${PREMIER_INITRD:-rien}"
grep -q "menuentry \"Noyau $K_ANCIEN (sans pilote NVIDIA)\"" "$CFG" \
	&& ok "l'entrée $K_ANCIEN dit qu'elle n'a pas le pilote" \
	|| non "l'entrée $K_ANCIEN ne dit pas qu'elle est sans pilote"
grep -q "menuentry \"LexOS Live - noyau $K_RECENT (pilote NVIDIA)\"" "$CFG" \
	&& ok "l'entrée par défaut dit qu'elle a le pilote" \
	|| non "le titre de l'entrée par défaut ne dit pas qu'elle a le pilote"
grep -q 'echo "LexOS : chargement de l'"'"'initrd' "$CFG" \
	&& ok "chaque entrée affiche ce qu'elle charge (diagnostic si ça s'arrête)" \
	|| non "les entrées n'affichent pas ce qu'elles chargent"
AVANT="$(grep -c '^[[:space:]]*menuentry' "$RACINE/tests/donnees/grub-iso-build122.cfg")"
APRES="$(grep -c '^[[:space:]]*menuentry' "$CFG")"
[ "$AVANT" = "$APRES" ] && ok "aucune entrée perdue ($APRES)" || non "entrées : $AVANT -> $APRES"
grep -q 'lexos\.failsafe=1' "$CFG" && ok "le mode de secours garde son marqueur" || non "le marqueur lexos.failsafe=1 a disparu"
VERIF="$(grep -A3 'Verify integrity' "$CFG")"
[[ "$VERIF" == *"vmlinuz-$K_RECENT"* ]] \
	&& ok "la vérification du support vise aussi le noyau récent" \
	|| non "la vérification du support vise encore l'ancien noyau"

#  LA CARTE DU MENU, ENTRÉE PAR ENTRÉE : titre, noyau démarré, et si la ligne
#  met nvidia en liste noire. Trouver UN bon titre ne dit rien des autres :
#  le mode de secours pouvait s'annoncer « (pilote NVIDIA) » — même titre
#  que l'entrée par défaut, pilote annoncé puis désactivé — sans qu'un seul
#  contrôle bouge. On compare donc le menu ENTIER à ce qu'il doit être.
carte_menu() {
	awk '
	/^[ \t]*menuentry[ \t]+"/ { t = $0; sub(/^[ \t]*menuentry[ \t]+"/, "", t); sub(/".*$/, "", t); dans = 1; next }
	dans && /^[ \t]*}/ { dans = 0 }
	dans && /^[ \t]*linux[ \t]+\/live\// {
		k = $2; sub(/^\/live\/vmlinuz-/, "", k); l = $0 " "
		print t " | " k " | " ((l ~ /module_blacklist=([^ ]*,)?nvidia[, ]/) ? "nvidia en liste noire" : "nvidia permis")
	}' "$1"
}
CARTE_ATTENDUE="LexOS Live - noyau $K_RECENT (pilote NVIDIA) | $K_RECENT | nvidia permis
LexOS Live - mode de secours (noyau $K_RECENT) | $K_RECENT | nvidia en liste noire
Noyau $K_ANCIEN (sans pilote NVIDIA) | $K_ANCIEN | nvidia permis
Noyau $K_ANCIEN - mode de secours | $K_ANCIEN | nvidia en liste noire
Noyau $K_RECENT (pilote NVIDIA) | $K_RECENT | nvidia permis
Noyau $K_RECENT - mode de secours | $K_RECENT | nvidia en liste noire
Verify integrity of the boot medium | $K_RECENT | nvidia permis"
CARTE="$(carte_menu "$CFG")"
[ "$CARTE" = "$CARTE_ATTENDUE" ] \
	&& ok "chaque titre dit ce que l'entrée démarre ; le mode de secours ne s'annonce pas « (pilote NVIDIA) »" \
	|| non "carte du menu inattendue : $(diff <(printf '%s\n' "$CARTE_ATTENDUE") <(printf '%s\n' "$CARTE") | tr '\n' ' ')"
RESTE="$(ls -A "$BANC/s7/binary/boot/grub")"
[ "$RESTE" = "grub.cfg" ] \
	&& ok "aucun fichier de travail ne reste dans /boot/grub (il partirait dans l'ISO)" \
	|| non "/boot/grub contient : $(printf '%s' "$RESTE" | tr '\n' ' ')"

#  REPRISE DE « lb build » après l'échec d'un hook binaire suivant : live-build
#  saute binary_grub_cfg (étape déjà faite) mais rejoue les hooks binaires,
#  et 0907 retrouve SON menu. Rejoué avec les vrais scripts de live-build,
#  l'ancien hook le réécrivait une seconde fois : « Noyau 6.12… (sans pilote
#  NVIDIA) » démarrait 7.2.9 et chaque « echo » était en double.
SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && cmp -s "$BANC/menu-reecrit.cfg" "$CFG" \
	&& ok "rejoué sur son propre menu (reprise de lb build), le hook le laisse identique, octet pour octet" \
	|| non "un second passage change le menu (rc=$RC) : $(diff "$BANC/menu-reecrit.cfg" "$CFG" | head -6 | tr '\n' ' ')"

scene_0907
rm "$BANC/s7/binary/live/initrd.img-$K_ANCIEN"
SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "un fichier absent du menu fait ÉCHOUER la construction" || non "un initrd manquant passe inaperçu"
cmp -s "$RACINE/tests/donnees/grub-iso-build122.cfg" "$CFG" \
	&& ok "…et le menu d'origine est remis en place" \
	|| non "le menu reste à moitié réécrit après l'échec"

#  UNE RÉÉCRITURE COUPÉE (disque plein…) ne laisse pas un menu tronqué qui
#  porte déjà le marqueur « echo » : le passage suivant le croirait fini et
#  ne ferait que le vérifier. Un faux « awk » écrit le début du menu réécrit,
#  puis échoue ; un passage normal suit, comme une reprise de lb build.
scene_0907
VRAI_AWK="$(command -v awk)"
mkdir -p "$BANC/awk-coupe"
cat > "$BANC/awk-coupe/awk" <<EOF
#!/bin/sh
case "\$2" in recent=*) "$VRAI_AWK" "\$@" | head -c 900; exit 1 ;; esac
exec "$VRAI_AWK" "\$@"
EOF
chmod +x "$BANC/awk-coupe/awk"
SORTIE="$(cd "$BANC/s7/binary" && PATH="$BANC/awk-coupe:$PATH" sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
INTACT="ABÎMÉ"; cmp -s "$RACINE/tests/donnees/grub-iso-build122.cfg" "$CFG" && INTACT="intact"
SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC2=$?
[ "$RC" -ne 0 ] && [ "$INTACT" = "intact" ] && [ "$RC2" -eq 0 ] && cmp -s "$BANC/menu-reecrit.cfg" "$CFG" \
	&& ok "une réécriture coupée laisse le menu d'origine, et la reprise le réécrit en entier" \
	|| non "réécriture coupée : rc=$RC, menu d'origine $INTACT, reprise rc=$RC2"

#  LA GARDE « LA PREMIÈRE ENTRÉE DÉMARRE LE NOYAU LE PLUS RÉCENT » DOIT
#  POUVOIR ROUGIR. Sur le vrai menu, la réécriture vise toujours la première
#  entrée : la garde n'y est jamais éprouvée, et on pouvait la retirer sans
#  qu'un contrôle bouge. Ici, la première entrée NOMME son noyau (« Live
#  system, kernel 6.12… ») : la réécriture ne la touche pas, elle démarre
#  l'ancien noyau, et la construction doit échouer.
scene_0907
sed -n '1,2p;12,27p' "$RACINE/tests/donnees/grub-iso-build122.cfg" > "$BANC/menu-sans-generique.cfg"
cp "$BANC/menu-sans-generique.cfg" "$CFG"
SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && [[ "$SORTIE" == *"la première entrée démarre /live/vmlinuz-$K_ANCIEN"* ]] \
   && cmp -s "$BANC/menu-sans-generique.cfg" "$CFG" \
	&& ok "une première entrée sur $K_ANCIEN fait ÉCHOUER la construction, menu remis en place" \
	|| non "première entrée sur $K_ANCIEN acceptée (rc=$RC) : $(printf '%s' "$SORTIE" | tail -2 | tr '\n' ' ')"

#  LA GARDE « CHAQUE TITRE DIT VRAI », sur le menu que l'ancien hook laissait
#  après une reprise : déjà réécrit (le marqueur est là), mais « Noyau 6.12…
#  (sans pilote NVIDIA) » démarre 7.2.9. Le hook ne le réécrit pas : il doit
#  refuser de le laisser partir.
scene_0907
sed "/menuentry \"Noyau $K_ANCIEN (sans pilote NVIDIA)\"/,/^}/ s|vmlinuz-$K_ANCIEN|vmlinuz-$K_RECENT|" \
	"$BANC/menu-reecrit.cfg" > "$BANC/menu-menteur.cfg"
cp "$BANC/menu-menteur.cfg" "$CFG"
SORTIE="$(cd "$BANC/s7/binary" && sh "$HOOKS/0907-lexos-noyau-defaut.hook.binary" 2>&1)"; RC=$?
! cmp -s "$BANC/menu-reecrit.cfg" "$BANC/menu-menteur.cfg" && [ "$RC" -ne 0 ] \
   && [[ "$SORTIE" == *"des titres ne disent pas vrai"*"Noyau $K_ANCIEN (sans pilote NVIDIA)"*"démarre $K_RECENT"* ]] \
	&& ok "un menu déjà réécrit dont un titre ment fait ÉCHOUER la construction" \
	|| non "titre menteur accepté (rc=$RC) : $(printf '%s' "$SORTIE" | tail -2 | tr '\n' ' ')"

#  LA MÊME GARDE, CÔTÉ WORKFLOW : build-iso.yml relit le grub.cfg de l'ISO
#  produite avant de la publier. On joue SES lignes — celles de l'étape
#  « verif » qui nomment PREMIER ou RECENT, extraites, pas recopiées — sur le
#  bon menu et sur celui du 20 octobre. Retirer la garde, ou la rendre
#  incapable d'échouer, laisse passer le second : ce contrôle rougit.
WF_ISO="$RACINE/.github/workflows/build-iso.yml"
GARDE_WF="$(awk '/^[[:space:]]*id: verif[[:space:]]*$/ { dans = 1; next }
	dans && /^[[:space:]]*- name:/ { exit }
	dans && /PREMIER|RECENT/ { sub(/^[[:space:]]+/, ""); print }' "$WF_ISO")"
garde_wf() { # garde_wf <grub.cfg> — code de sortie des lignes du workflow
	rm -rf "$BANC/iso"; mkdir -p "$BANC/iso/boot/grub"
	cp -r "$BANC/s7/binary/live" "$BANC/iso/"
	cp "$1" "$BANC/iso/boot/grub/grub.cfg"
	M="$BANC/iso" bash -e -c "$GARDE_WF" >/dev/null 2>&1
}
garde_wf "$BANC/menu-reecrit.cfg"; RC_BON=$?
garde_wf "$RACINE/tests/donnees/grub-iso-build122.cfg"; RC_ANCIEN=$?
[ -n "$GARDE_WF" ] && [ "$RC_BON" -eq 0 ] && [ "$RC_ANCIEN" -ne 0 ] \
	&& ok "build-iso.yml accepte le menu réécrit et REFUSE celui du 20 octobre (6.12 par défaut)" \
	|| non "contrôle de build-iso.yml : menu réécrit rc=$RC_BON, menu du 20 octobre rc=$RC_ANCIEN — lignes : $(printf '%s' "${GARDE_WF:-aucune}" | tr '\n' ';')"

# ===========================================================================
titre "2. MOKMANAGER DANS UNE efi.img PLEINE (hook 0915)"
# ===========================================================================
if command -v mcopy >/dev/null 2>&1 && command -v mkfs.msdos >/dev/null 2>&1; then
	export MTOOLS_SKIP_CHECK=1
	S="$BANC/s15"
	mkdir -p "$S/binary/boot/grub" "$S/binary/EFI/boot" "$S/chroot/usr/lib/shim" \
		"$S/chroot/usr/share/lexos/secure-boot" "$S/source/EFI/boot" "$S/source/boot/grub"
	head -c 1036152 /dev/urandom > "$S/source/EFI/boot/bootx64.efi"
	head -c 2328000 /dev/urandom > "$S/source/EFI/boot/grubx64.efi"
	printf 'search --file --set=root /.disk/info\n' > "$S/source/boot/grub/grub.cfg"
	head -c 850000 /dev/urandom > "$S/chroot/usr/lib/shim/mmx64.efi.signed"
	cp "$S/source/EFI/boot/bootx64.efi" "$S/binary/EFI/boot/"
	head -c 889 /dev/urandom > "$S/binary/lexos-mok.der"
	cp "$S/binary/lexos-mok.der" "$S/chroot/usr/share/lexos/secure-boot/"
	#  La taille de l'efi.img de l'ISO du 20 octobre : 3 407 872 octets, 10 Ko libres.
	mkfs.msdos -C "$S/binary/boot/grub/efi.img" 3328 >/dev/null
	mcopy -s -i "$S/binary/boot/grub/efi.img" "$S/source/"* ::/
	if mcopy -i "$S/binary/boot/grub/efi.img" "$S/chroot/usr/lib/shim/mmx64.efi.signed" ::/essai 2>/dev/null; then
		muet "l'efi.img d'essai n'est pas pleine : le cas « plus de place » n'est pas joué"
		mdel -i "$S/binary/boot/grub/efi.img" ::/essai
	else
		ok "point de départ réel : MokManager ne rentre PAS dans l'efi.img d'origine"
	fi
	SORTIE="$(cd "$S/binary" && sh "$HOOKS/0915-lexos-mokmanager.hook.binary" 2>&1)"; RC=$?
	[ "$RC" -eq 0 ] && ok "le hook passe" || non "le hook échoue : $(printf '%s' "$SORTIE" | tail -3 | tr '\n' ' ')"
	mkdir -p "$S/relu"
	mcopy -s -n -i "$S/binary/boot/grub/efi.img" '::/*' "$S/relu/" 2>/dev/null
	cmp -s "$S/relu/EFI/boot/mmx64.efi" "$S/chroot/usr/lib/shim/mmx64.efi.signed" \
		&& ok "mmx64.efi est dans la nouvelle efi.img, à côté de shim" \
		|| non "mmx64.efi absent de l'efi.img"
	cmp -s "$S/relu/EFI/boot/grubx64.efi" "$S/source/EFI/boot/grubx64.efi" \
	   && cmp -s "$S/relu/EFI/boot/bootx64.efi" "$S/source/EFI/boot/bootx64.efi" \
	   && cmp -s "$S/relu/boot/grub/grub.cfg" "$S/source/boot/grub/grub.cfg" \
		&& ok "…et shim, GRUB et leur grub.cfg sont intacts, octet pour octet" \
		|| non "le contenu d'origine de l'efi.img a changé"
	[ -f "$S/binary/EFI/boot/mmx64.efi" ] \
		&& ok "mmx64.efi est aussi dans l'arborescence (clé recopiée par Rufus)" \
		|| non "mmx64.efi absent de l'arborescence EFI/boot"
	head -c 889 /dev/urandom > "$S/binary/lexos-mok.der"
	SORTIE="$(cd "$S/binary" && sh "$HOOKS/0915-lexos-mokmanager.hook.binary" 2>&1)"; RC=$?
	[ "$RC" -ne 0 ] && ok "deux certificats différents (clé USB / système) font échouer" \
		|| non "un certificat de racine différent de celui du système passe"
else
	muet "mtools ou dosfstools absents : le hook 0915 n'est pas joué"
fi

# ===========================================================================
titre "3. LA SIGNATURE D'UN MODULE SE RETIRE ET SE REMET (hook 9890)"
# ===========================================================================
H9890="$HOOKS/9890-lexos-signature-verif.hook.chroot"
FONCTIONS="$BANC/fonctions.sh"
{
	printf 'MARQUE="~Module signature appended~"\n'
	for F in normalise retire_signature signe_module cle_du_module; do
		sed -n "/^${F}() {/,/^}/p" "$H9890"
	done
} > "$FONCTIONS"
if grep -q '^retire_signature() {' "$FONCTIONS" && grep -q '^signe_module() {' "$FONCTIONS"; then
	ok "les fonctions sont extraites du hook livré"
else
	non "fonctions introuvables dans le hook 9890"
fi

#  Une signature fabriquée : corps, 10 octets de « PKCS#7 », la structure de
#  12 octets (sig_len = 10, gros-boutiste), la marque.
python3 - "$BANC/faux.ko" <<'PY'
import sys
corps = b"\x7fELF-corps-du-module"
sig = b"S" * 10
struct = bytes([0, 0, 2, 0, 0, 0, 0, 0]) + (10).to_bytes(4, "big")
open(sys.argv[1], "wb").write(corps + sig + struct + b"~Module signature appended~\n")
PY
( . "$FONCTIONS"; retire_signature "$BANC/faux.ko" )
[ "$(cat "$BANC/faux.ko")" = $'\x7fELF-corps-du-module' ] \
	&& ok "retire_signature rend le module exactement à son corps" \
	|| non "retire_signature laisse des octets en trop ou en moins ($(stat -c %s "$BANC/faux.ko") octets)"
printf 'module sans signature' > "$BANC/nu.ko"
( . "$FONCTIONS"; retire_signature "$BANC/nu.ko" )
[ "$(cat "$BANC/nu.ko")" = "module sans signature" ] \
	&& ok "…et ne touche pas à un module non signé" \
	|| non "retire_signature abîme un module non signé"

#  Le vrai : sign-file du noyau du coureur, un vrai module, deux clés de suite.
SF="$(ls /usr/src/linux-headers-"$(uname -r)"/scripts/sign-file /usr/lib/linux-kbuild-*/scripts/sign-file 2>/dev/null | head -1 || true)"
VRAI="$(find /lib/modules/"$(uname -r)"/kernel/drivers -name 'dummy.ko*' 2>/dev/null | head -1 || true)"
[ -n "$VRAI" ] || VRAI="$(find /lib/modules/"$(uname -r)"/kernel -name '*.ko*' -size -40k 2>/dev/null | head -1 || true)"
if [ -n "$SF" ] && [ -n "$VRAI" ] && command -v openssl >/dev/null 2>&1 && command -v modinfo >/dev/null 2>&1; then
	cle_essai() {
		openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 30 -subj "/CN=$1" \
			-addext "extendedKeyUsage=codeSigning" -keyout "$BANC/$1.key" -outform DER -out "$BANC/$1.der" 2>/dev/null
		#  sig_key = numéro de série, sous la forme normalisée du hook.
		openssl x509 -inform DER -in "$BANC/$1.der" -noout -serial | sed 's/^serial=//' \
			| tr -d ' :' | tr 'a-f' 'A-F' | sed 's/^0*//'
	}
	ID_A="$(cle_essai LexOS-essai-A)"; ID_B="$(cle_essai LexOS-essai-B)"
	M="$BANC/$(basename "$VRAI")"; cp "$VRAI" "$M"
	( . "$FONCTIONS"; CLE="$BANC/LexOS-essai-A.key"; CERT="$BANC/LexOS-essai-A.der"; signe_module "$M" "$SF" )
	[ "$( . "$FONCTIONS"; cle_du_module "$M")" = "$ID_A" ] \
		&& ok "un vrai module ($(basename "$VRAI")) porte la clé A après signature" \
		|| non "la signature A n'est pas celle que modinfo lit"
	( . "$FONCTIONS"; CLE="$BANC/LexOS-essai-B.key"; CERT="$BANC/LexOS-essai-B.der"; signe_module "$M" "$SF" )
	[ "$( . "$FONCTIONS"; cle_du_module "$M")" = "$ID_B" ] \
		&& ok "…re-signé par la clé B, modinfo lit B" \
		|| non "la re-signature B n'a pas pris"
	case "$M" in
		*.zst) zstd -qdc "$M" > "$BANC/clair.ko" ;; *.xz) xz -dc "$M" > "$BANC/clair.ko" ;;
		*.gz) gzip -dc "$M" > "$BANC/clair.ko" ;; *) cp "$M" "$BANC/clair.ko" ;;
	esac
	N="$(grep -c -a 'Module signature appended' "$BANC/clair.ko" || true)"
	[ "$N" = "1" ] && ok "…et UNE seule signature : l'ancienne a été retirée, pas empilée" \
		|| non "$N signatures empilées dans le module"
else
	muet "sign-file, module du noyau, openssl ou modinfo absent : signature réelle non jouée"
fi

# ===========================================================================
titre "4. L'INITRAMFS N'EMPORTE PLUS NOUVEAU QUAND IL EST EN LISTE NOIRE"
# ===========================================================================
HOOK_I="$RACINE/config/includes.chroot/etc/initramfs-tools/hooks/zz-lexos-sans-nouveau"
scene_initrd() {
	rm -rf "$BANC/dest"
	mkdir -p "$BANC/dest/usr/lib/modules/7.2.9/kernel/drivers/gpu/drm/nouveau" \
		"$BANC/dest/usr/lib/modules/7.2.9/kernel/drivers/gpu/drm/amd" \
		"$BANC/dest/usr/lib/firmware/nvidia/ga102/gsp" "$BANC/dest/usr/lib/firmware/nvidia/615.71.10" \
		"$BANC/dest/usr/lib/firmware/i915"
	: > "$BANC/dest/usr/lib/modules/7.2.9/kernel/drivers/gpu/drm/nouveau/nouveau.ko.xz"
}
scene_initrd
DESTDIR="$BANC/dest" LEXOS_LISTE_NOIRE="$BANC/absente" sh "$HOOK_I"
[ -d "$BANC/dest/usr/lib/firmware/nvidia/ga102" ] \
	&& ok "sans liste noire : rien n'est retiré (nouveau reste le pilote de ces machines)" \
	|| non "sans liste noire, le micrologiciel de nouveau a été retiré"
: > "$BANC/liste-noire"
DESTDIR="$BANC/dest" LEXOS_LISTE_NOIRE="$BANC/liste-noire" sh "$HOOK_I"
[ ! -d "$BANC/dest/usr/lib/firmware/nvidia/ga102" ] && [ ! -d "$BANC/dest/usr/lib/modules/7.2.9/kernel/drivers/gpu/drm/nouveau" ] \
	&& ok "liste noire : nouveau et son micrologiciel quittent l'initramfs" \
	|| non "nouveau ou son micrologiciel est resté"
[ -d "$BANC/dest/usr/lib/firmware/nvidia/615.71.10" ] && [ -d "$BANC/dest/usr/lib/modules/7.2.9/kernel/drivers/gpu/drm/amd" ] \
	&& ok "…le micrologiciel du pilote NVIDIA officiel et les autres pilotes restent" \
	|| non "le hook a retiré plus que nouveau"

# ===========================================================================
titre "5. L'INSTALLATEUR : /boot SÉPARÉ ET NON CHIFFRÉ"
# ===========================================================================
PCONF="$RACINE/config/includes.chroot/etc/calamares/modules/partition.conf"
VERDICT="$(python3 - "$PCONF" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("SANS-YAML"); sys.exit()
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
lay = d.get("partitionLayout") or []
boot = [p for p in lay if p.get("mountPoint") == "/boot"]
root = [p for p in lay if p.get("mountPoint") == "/"]
ok = (d.get("enableLuksAutomatedPartitioning") is True and len(boot) == 1 and boot[0].get("noEncrypt") is True
      and boot[0].get("filesystem") == "ext4" and len(root) == 1 and not root[0].get("noEncrypt", False))
print("OK" if ok else "NON %r" % lay)
PY
)"
case "$VERDICT" in
	OK) ok "chiffrement proposé, /boot en ext4 exempté (noEncrypt), racine chiffrable" ;;
	SANS-YAML) muet "python3-yaml absent : partition.conf non lu" ;;
	*) non "partition.conf : $VERDICT" ;;
esac

# ===========================================================================
titre "6. LA CLÉ PRIVÉE NE VOYAGE PAS"
# ===========================================================================
DEBUT="-----BEGIN"; FIN="PRIVATE KEY-----"
PEM="$(grep -rIl -- "${DEBUT} .*${FIN}" "$RACINE" --exclude-dir=.git 2>/dev/null | head -3)"
[ -z "$PEM" ] && ok "aucune clé privée dans le dépôt" || non "clé privée versionnée : $PEM"
[ -s "$RACINE/config/includes.chroot/usr/share/lexos/secure-boot/lexos-mok.der" ] \
   && cmp -s "$RACINE/config/includes.chroot/usr/share/lexos/secure-boot/lexos-mok.der" "$RACINE/config/includes.binary/lexos-mok.der" \
	&& ok "le certificat public est le même dans le système et à la racine de la clé" \
	|| non "certificat absent ou différent entre système et racine de la clé"
SORTIE="$(sh "$HOOKS/0258-lexos-signature-dkms.hook.chroot" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [[ "$SORTIE" == *"pas de clé LexOS"* ]] \
	&& ok "sans clé, le hook 0258 ne pose rien et le dit" \
	|| non "le hook 0258 sans clé : $SORTIE"
WF="$RACINE/.github/workflows/build-iso.yml"
grep -q 'unsquashfs' "$WF" && grep -q 'LEXOS_MOK_KEY' "$WF" \
	&& ok "le workflow lit le secret ET fouille le squashfs avant de publier" \
	|| non "le workflow ne vérifie pas que la clé est absente du squashfs"

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
