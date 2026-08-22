#!/usr/bin/env bash
# =============================================================================
#  test_lexos_materiel.sh — la page matériel dit-elle vrai, et se tait-elle
#                           sur ce qui ne doit pas sortir ?
# =============================================================================
#  CE QUI EST ÉPROUVÉ ICI, ET POURQUOI.
#
#  1. LA FUITE. « lexos materiel rapport » est fait pour être collé dans
#     lexos ia-locale. dmidecode donne le numéro de série de CHAQUE barrette
#     en prime, sans qu'on l'ait demandé. Un identifiant unique qui part
#     dans un modèle, même local, a fui une fois de trop.
#
#  2. L'EXÉCUTION. Le nom de modèle d'un disque vient du MATÉRIEL. Une clé
#     USB peut annoncer « $(commande) ». La première version de ce script
#     employait eval sur la sortie de lsblk : la clé aurait gagné.
#
#  3. LA RÉPONSE UTILE. « Puis-je ajouter de la RAM ? » — fentes libres ou
#     non, le verdict doit changer, et nommer le type à acheter.
#
#  4. LE SILENCE. Sans dmidecode, sans lspci, sans root, la page doit DIRE
#     ce qu'elle ne peut pas lire, avec la commande qui l'ouvrirait. Une
#     section qui disparaît sans un mot, c'est le défaut qu'on traque ici
#     depuis le début.
#
#  Aucun vrai matériel n'est nécessaire : /sys est surchargé par LEXOS_SYS
#  et les outils par le PATH.
# =============================================================================
set -u

ICI="$(cd "$(dirname "$0")" && pwd)"
OUTIL="$ICI/../config/includes.chroot/usr/bin/lexos-materiel"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

NB_OK=0; NB_KO=0
ok() { NB_OK=$((NB_OK+1)); echo "  ✅ $1"; }
ko() { NB_KO=$((NB_KO+1)); echo "  ❌ $1"; }

# --- la fausse machine -------------------------------------------------------
machine() {           # $1 = nom du profil
	rm -rf "${BANC:?}/bin" "${BANC:?}/sys"
	mkdir -p "$BANC/bin" "$BANC/sys/class/dmi/id"
	printf 'Alienware\n'        > "$BANC/sys/class/dmi/id/sys_vendor"
	printf 'Alienware m16 R2\n' > "$BANC/sys/class/dmi/id/product_name"
	printf '10\n'               > "$BANC/sys/class/dmi/id/chassis_type"
}
lance() { PATH="$BANC/bin:$PATH" LEXOS_SYS="$BANC/sys" DISPLAY='' NO_COLOR=1 \
	bash "$OUTIL" "$@" 2>&1; }

# =============================================================================
echo "═══ 1. Les numéros de série ne sortent jamais ═══"
machine
cat > "$BANC/bin/dmidecode" <<'EOF'
#!/bin/sh
cat <<'DMI'
Physical Memory Array
	Maximum Capacity: 64 GB
	Number Of Devices: 2
Memory Device
	Locator: DIMM A
	Size: 32 GB
	Type: DDR5
	Configured Memory Speed: 5600 MT/s
	Serial Number: 4F2B91CE
	Asset Tag: 9931-ALEX
Memory Device
	Locator: DIMM B
	Size: No Module Installed
DMI
EOF
chmod +x "$BANC/bin/dmidecode"
RAPPORT="$(lance rapport)"
for SECRET in 4F2B91CE 9931-ALEX; do
	if printf '%s' "$RAPPORT" | grep -q -- "$SECRET"; then
		ko "« $SECRET » se retrouve dans le rapport — fuite"
	else
		ok "« $SECRET » ne sort pas du rapport"
	fi
done
printf '%s' "$RAPPORT" | grep -qi 'serial number' \
	&& ko "la ligne « Serial Number » elle-même est recopiée" \
	|| ok "aucune ligne « Serial Number » recopiée"
#  Un rapport destiné au copier-coller ne doit porter aucun code couleur.
printf '%s' "$RAPPORT" | grep -q "$(printf '\033')" \
	&& ko "des codes d'échappement restent dans le rapport" \
	|| ok "le rapport est du texte brut"

# =============================================================================
echo "═══ 2. Un disque au nom hostile n'exécute rien ═══"
TEMOIN="$BANC/PWNED"
cat > "$BANC/bin/lsblk" <<EOF
#!/bin/sh
printf '%s\n' 'NAME="sda" SIZE="14.5G" MODEL="\$(touch $TEMOIN)\`touch $TEMOIN\`" ROTA="1" TRAN="usb"'
EOF
chmod +x "$BANC/bin/lsblk"
SORTIE="$(lance)"
if [ -e "$TEMOIN" ]; then
	ko "le nom du disque a été EXÉCUTÉ — injection réussie"
else
	ok "le nom du disque n'est pas exécuté"
fi
printf '%s' "$SORTIE" | grep -qF '$(touch' \
	&& ok "il est affiché tel quel, en toutes lettres" \
	|| ko "le nom du disque n'apparaît pas — il a été mangé quelque part"

# =============================================================================
echo "═══ 3. « Puis-je ajouter de la RAM ? » ═══"
SORTIE="$(lance memoire)"
printf '%s' "$SORTIE" | grep -q 'fente(s) libre(s)' \
	&& ok "une fente libre : la page le dit" \
	|| ko "une fente est libre et la page ne le dit pas"
printf '%s' "$SORTIE" | grep -q 'DDR5' \
	&& ok "et elle nomme le type à acheter (DDR5)" \
	|| ko "elle ne dit pas quoi acheter"
printf '%s' "$SORTIE" | grep -q 'DIMM B.*libre' \
	&& ok "la fente vide est nommée « libre »" \
	|| ko "la fente vide n'est pas signalée"

#  Toutes les fentes pleines : le verdict doit CHANGER, sinon il ne veut
#  rien dire. Une page qui répond « oui » quoi qu'il arrive ne répond pas.
cat > "$BANC/bin/dmidecode" <<'EOF'
#!/bin/sh
cat <<'DMI'
Physical Memory Array
	Maximum Capacity: 64 GB
	Number Of Devices: 2
Memory Device
	Locator: DIMM A
	Size: 32 GB
	Type: DDR5
Memory Device
	Locator: DIMM B
	Size: 32 GB
	Type: DDR5
DMI
EOF
chmod +x "$BANC/bin/dmidecode"
SORTIE="$(lance memoire)"
printf '%s' "$SORTIE" | grep -q 'fente(s) libre(s)' \
	&& ko "toutes les fentes sont pleines et la page promet un ajout" \
	|| ok "toutes pleines : la page ne promet plus d'ajout"
printf '%s' "$SORTIE" | grep -q 'REMPLACER' \
	&& ok "et elle dit qu'il faut remplacer, pas ajouter" \
	|| ko "elle ne dit pas quoi faire à la place"

# =============================================================================
echo "═══ 4. Une NVIDIA sous « nouveau » est signalée ═══"
machine
cat > "$BANC/bin/lspci" <<'EOF'
#!/bin/sh
if [ "$1" = "-k" ]; then
  echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD107M"
  echo "	Kernel driver in use: nouveau"
  exit 0
fi
echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [RTX 4060]"
EOF
chmod +x "$BANC/bin/lspci"
SORTIE="$(lance)"
printf '%s' "$SORTIE" | grep -qi 'nouveau.*plus lent\|plus lent' \
	&& ok "le pilote libre sur une NVIDIA est signalé comme un problème" \
	|| ko "une NVIDIA sous nouveau passe inaperçue — c'est une machine qui rame en silence"

#  Le même matériel avec le BON pilote ne doit PAS crier au loup.
cat > "$BANC/bin/lspci" <<'EOF'
#!/bin/sh
if [ "$1" = "-k" ]; then
  echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD107M"
  echo "	Kernel driver in use: nvidia"
  exit 0
fi
echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [RTX 4060]"
EOF
chmod +x "$BANC/bin/lspci"
lance | grep -qi 'plus lent' \
	&& ko "le bon pilote déclenche quand même l'alerte — un contrôle qui crie au loup" \
	|| ok "avec le pilote nvidia, aucune alerte"

# =============================================================================
echo "═══ 5. Ce qui manque est DIT, pas escamoté ═══"
machine     # aucun outil dans le PATH du banc
SORTIE="$(lance)"
printf '%s' "$SORTIE" | grep -q 'dmidecode absent' \
	&& ok "dmidecode absent : la page le dit" \
	|| ko "dmidecode absent et la section mémoire disparaît en silence"
printf '%s' "$SORTIE" | grep -q 'sudo apt install dmidecode' \
	&& ok "et elle donne la commande qui l'installe" \
	|| ko "elle ne dit pas comment obtenir l'information"
printf '%s' "$SORTIE" | grep -qi 'pciutils absent' \
	&& ok "lspci absent : la page le dit aussi" \
	|| ko "la carte graphique disparaît sans un mot"

#  Le cas d'Alex : les outils sont là, mais on n'est pas root.
cat > "$BANC/bin/dmidecode" <<'EOF'
#!/bin/sh
echo "dmidecode: Permission denied" >&2
exit 1
EOF
chmod +x "$BANC/bin/dmidecode"
SORTIE="$(lance memoire)"
printf '%s' "$SORTIE" | grep -q 'sudo lexos materiel memoire' \
	&& ok "sans root : la page nomme la commande exacte à retaper" \
	|| ko "sans root : la page se tait au lieu d'expliquer"

# =============================================================================
echo "═══ 6. Les bases ═══"
lance aide | grep -q 'materiel memoire' \
	&& ok "l'aide s'affiche et nomme la sous-commande mémoire" \
	|| ko "l'aide est muette"
lance teleporter >/dev/null 2>&1 \
	&& ko "une sous-commande inventée est acceptée" \
	|| ok "une sous-commande inventée est refusée"

#  Les colonnes : « Modèle » (accent, 7 octets pour 6 caractères) doit
#  s'aligner sur « Type ». printf %-Ns remplit en OCTETS — c'est le piège.
machine
#  ON MESURE EN CARACTÈRES, PAS EN OCTETS — et ce test s'est trompé
#  DEUX fois avant d'être juste. D'abord avec index() d'awk, qui compte
#  les octets ; puis avec ${#chaine} dans un shell SANS locale UTF-8, où
#  bash compte les octets lui aussi. Mesurer un défaut d'octets avec un
#  outil qui compte les octets ne prouve jamais rien : les deux erreurs
#  s'annulaient et accusaient un code correct.
#  Sans locale UTF-8 sur la machine, ce contrôle ne peut RIEN affirmer :
#  il le dit et s'abstient, plutôt que de donner un ✅ qui ne vaut rien.
MESURE="$(locale -a 2>/dev/null | grep -im1 -E '^(C|en_US|fr_CA|fr_FR)\.utf-?8$')"
if [ -z "$MESURE" ]; then
	echo "  ⏭  aucune locale UTF-8 : l'alignement n'est pas mesurable ici"
else
	COLS="$(lance | grep -E '^  (Modèle|Type) ' | while IFS= read -r l; do
		pre="$(printf '%s' "$l" | sed -E 's/^(  [^ ]+ +).*/\1/')"
		LC_ALL="$MESURE" bash -c 'printf "%s\n" "${#1}"' _ "$pre"
	done | sort -u | wc -l)"
	[ "$COLS" -le 1 ] \
		&& ok "les colonnes restent alignées malgré les accents" \
		|| ko "les colonnes ondulent : l'alignement compte les octets"
fi

echo
echo "$NB_OK réussi(s), $NB_KO échoué(s)"
exit $((NB_KO > 0))
