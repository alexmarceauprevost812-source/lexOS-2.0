#!/usr/bin/env bash
# =============================================================================
#  Test de lexos-mac — le classement du matériel Apple
# =============================================================================
#  Ce que dit « lexos mac » décide si quelqu'un passe la soirée à écrire une
#  clé USB pour rien. Une erreur de table ne se voit pas : le script répond
#  toujours quelque chose. On lui pose donc la question pour trente-six
#  machines dont on connaît la réponse.
#
#  Aucun Mac n'est requis : le script lit son matériel dans le dossier
#  indiqué par LEXOS_DMI_DIR, qu'on fabrique ici.
# =============================================================================
set -uo pipefail

BIN="${1:-config/includes.chroot/usr/bin/lexos-mac}"
[[ -x "$BIN" ]] || { echo "introuvable ou non exécutable : $BIN" >&2; exit 1; }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
ECHECS=0
N=0

essai() { # vendeur  modèle  architecture  attendu
	local d obtenu
	N=$((N + 1))
	d="$BASE/cas$N"; mkdir -p "$d"
	printf '%s\n' "$1" > "$d/sys_vendor"
	printf '%s\n' "$2" > "$d/product_name"
	printf '%s\n' "$1" > "$d/board_vendor"
	obtenu="$(LEXOS_DMI_DIR="$d" LEXOS_MACHINE="$3" NO_COLOR=1 "$BIN" classe)"
	if [[ "$obtenu" == "$4" ]]; then
		printf 'ok    %-16s %-8s → %s\n' "${2:-（vide）}" "$3" "$obtenu"
	else
		printf 'ÉCHEC %-16s %-8s → %s (attendu %s)\n' "${2:-（vide）}" "$3" "$obtenu" "$4"
		ECHECS=$((ECHECS + 1))
	fi
}

echo "── Mac Intel 2008-2017 : pris en charge ──────────────────────"
essai "Apple Inc." "MacBookPro11,3" x86_64  intel
essai "Apple Inc." "MacBookPro9,2"  x86_64  intel
essai "Apple Inc." "MacBookAir7,2"  x86_64  intel
essai "Apple Inc." "iMac18,3"       x86_64  intel
essai "Apple Inc." "Macmini7,1"     x86_64  intel
essai "Apple Inc." "MacBookPro14,3" x86_64  intel
essai "Apple Inc." "MacPro6,1"      x86_64  intel
#  Deux pièges : un iMac et un Mac mini d'avant Apple Silicon ne doivent
#  surtout pas tomber dans la règle « Mac13 et au-delà ».
essai "Apple Inc." "iMac12,1"       x86_64  intel
essai "Apple Inc." "Macmini6,2"     x86_64  intel

echo "── Puce T2 2017-2020 : démarre avec réserves ─────────────────"
essai "Apple Inc." "MacBookPro15,1" x86_64  t2
essai "Apple Inc." "MacBookPro16,1" x86_64  t2
essai "Apple Inc." "MacBookAir8,1"  x86_64  t2
essai "Apple Inc." "MacBookAir9,1"  x86_64  t2
essai "Apple Inc." "iMacPro1,1"     x86_64  t2
essai "Apple Inc." "Macmini8,1"     x86_64  t2
essai "Apple Inc." "MacPro7,1"      x86_64  t2
essai "Apple Inc." "iMac20,1"       x86_64  t2

echo "── EFI 32 bits : amorçage BIOS seulement ────────────────────"
essai "Apple Inc." "MacBook4,1"     x86_64  efi32
essai "Apple Inc." "MacBookPro3,1"  x86_64  efi32
essai "Apple Inc." "iMac7,1"        x86_64  efi32
essai "Apple Inc." "MacPro1,1"      x86_64  efi32

echo "── Processeur 32 bits : hors de portée d'une ISO amd64 ──────"
essai "Apple Inc." "MacBook1,1"     i686    cpu32
essai "Apple Inc." "MacBookPro1,1"  i686    cpu32
essai "Apple Inc." "Macmini1,1"     i686    cpu32

echo "── Apple Silicon : impossible ────────────────────────────────"
essai "Apple Inc." "MacBookAir10,1" aarch64 silicon
essai "Apple Inc." "MacBookPro18,3" aarch64 silicon
essai "Apple Inc." "Mac14,3"        aarch64 silicon
essai "Apple Inc." "Mac13,1"        aarch64 silicon
essai "Apple Inc." "Mac16,10"       aarch64 silicon
essai "Apple Inc." "iMac21,1"       aarch64 silicon
essai "Apple Inc." "Macmini9,1"     aarch64 silicon
#  La nomenclature courte suffit : même lue sur du x86 (une VM mal
#  renseignée), un Mac15 reste une machine ARM.
essai "Apple Inc." "Mac15,3"        x86_64  silicon

echo "── Pas des Mac : rien ne doit être appliqué ─────────────────"
essai "LENOVO"     "20BE"           x86_64  pas-apple
essai "Dell Inc."  "XPS 13 9360"    x86_64  pas-apple
essai "QEMU"       "Standard PC"    x86_64  pas-apple
essai ""           ""               x86_64  pas-apple

echo
echo "── « --auto » doit être muet, rapide, et sans mot de passe ──"
#  lexos-firstrun l'appelle pendant l'ouverture de session, sortie
#  redirigée : un sudo qui demande un mot de passe bloquerait la session
#  sur un écran vide. On vérifie donc qu'il ne lit jamais l'entrée.
d="$BASE/auto"; mkdir -p "$d"
printf 'Dell Inc.\n' > "$d/sys_vendor"; printf 'XPS 13\n' > "$d/product_name"
sortie="$(timeout 10 env LEXOS_DMI_DIR="$d" LEXOS_MACHINE=x86_64 "$BIN" --auto </dev/null 2>&1)"
code=$?
if [[ $code -eq 0 && -z "$sortie" ]]; then
	echo "ok    machine ordinaire : sortie 0, rien affiché"
else
	echo "ÉCHEC machine ordinaire : code=$code sortie=«$sortie»"; ECHECS=$((ECHECS + 1))
fi
printf 'Apple Inc.\n' > "$d/sys_vendor"; printf 'MacBookPro11,3\n' > "$d/product_name"
sortie="$(timeout 10 env LEXOS_DMI_DIR="$d" LEXOS_MACHINE=x86_64 "$BIN" --auto </dev/null 2>&1)"
code=$?
if [[ $code -eq 0 ]]; then
	echo "ok    Mac sans droits root : sortie 0, aucune attente"
else
	echo "ÉCHEC Mac sans droits root : code=$code sortie=«$sortie»"; ECHECS=$((ECHECS + 1))
fi

echo
echo "── Le bon pilote Broadcom pour chaque identifiant PCI ───────"
carte() { # id-pci  mot-attendu
	local f="$BASE/lspci.txt" vu
	printf '02:00.0 Network controller [0280]: Broadcom Inc. Device [%s]\n' "$1" > "$f"
	vu="$(LEXOS_DMI_DIR="$d" LEXOS_MACHINE=x86_64 LEXOS_LSPCI="$f" NO_COLOR=1 "$BIN" wifi)"
	if grep -q "$2" <<< "$vu" ; then
		printf 'ok    %s → %s\n' "$1" "$2"
	else
		printf 'ÉCHEC %s : « %s » attendu, obtenu :\n%s\n' "$1" "$2" "$vu"
		ECHECS=$((ECHECS + 1))
	fi
}
carte 14e4:4331 "firmware-b43-installer"
carte 14e4:43a0 "broadcom-sta-dkms"
carte 14e4:43ba "firmware-brcm80211"
carte 14e4:4364 "puce T2"
carte 14e4:4488 "puce T2"
#  Une carte inconnue doit le dire, pas rester muette : un champ vide
#  voudrait dire que le découpage des trois colonnes a glissé.
carte 14e4:9999 "non répertoriée"

echo
if (( ECHECS )); then
	echo "$ECHECS échec(s) sur $((N + 8)) vérifications."
	exit 1
fi
echo "Tout passe : $N modèles classés + démarrage automatique + 6 cartes Wi-Fi."
