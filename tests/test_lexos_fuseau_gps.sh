#!/usr/bin/env bash
# =============================================================================
#  Test du fuseau horaire par position réelle (GPS puis IP)
# =============================================================================
#  LexOS s'installait TOUJOURS à l'heure de Toronto, même à l'autre bout du
#  monde. lexos-fuseau-position détecte la vraie position (GPS matériel, puis
#  géolocalisation IP, puis repli) ; lexos-fuseau-confirmer décide s'il faut
#  le proposer et l'applique seulement si l'utilisateur dit oui.
#
#  Rien de réel n'est requis : ni GPS, ni réseau, ni root, ni Calamares.
#  Le GPS est simulé par un fichier texte contenant des trames NMEA (le
#  détecteur lit LEXOS_GPS_DEV comme n'importe quel chemin) ; la
#  géolocalisation IP par une commande qui imprime un JSON en boîte ; et
#  l'application du fuseau par un faux timedatectl qui note ce qu'on lui
#  demande sans jamais toucher au système.
# =============================================================================
set -uo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
DETECTEUR="${1:-$ICI/../config/includes.chroot/usr/lib/lexos/lexos-fuseau-position}"
CONFIRMEUR="$ICI/../config/includes.chroot/usr/lib/lexos/lexos-fuseau-confirmer"

[[ -x "$DETECTEUR" ]] || { echo "introuvable ou non exécutable : $DETECTEUR" >&2; exit 1; }
[[ -x "$CONFIRMEUR" ]] || { echo "introuvable ou non exécutable : $CONFIRMEUR" >&2; exit 1; }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
ECHECS=0
N=0

lire_champ() { # $1 = sortie complète, $2 = clé (SOURCE|FUSEAU)
	printf '%s\n' "$1" | sed -n "s/^$2=//p"
}

essai_detecteur() { # libellé  attendu-source  attendu-fuseau  -- env...
	local libelle="$1" src_attendue="$2" fuseau_attendu="$3"; shift 3
	N=$((N + 1))
	local sortie src fuseau
	sortie="$(env "$@" "$DETECTEUR" 2>/dev/null)"
	src="$(lire_champ "$sortie" SOURCE)"
	fuseau="$(lire_champ "$sortie" FUSEAU)"
	if [[ "$src" == "$src_attendue" && "$fuseau" == "$fuseau_attendu" ]]; then
		printf 'ok    %-42s → %s / %s\n' "$libelle" "$src" "$fuseau"
	else
		printf 'ÉCHEC %-42s → %s / %s (attendu %s / %s)\n' \
			"$libelle" "$src" "$fuseau" "$src_attendue" "$fuseau_attendu"
		ECHECS=$((ECHECS + 1))
	fi
}

# --- Fixtures GPS : trames NMEA réelles ---------------------------------------
#  Toronto exactement : +4339-07923, l'entrée même de zone1970.tab, pour ne
#  laisser aucune place à l'approximation du point le plus proche.
GGA_TORONTO="$BASE/gga_toronto.nmea"
cat > "$GGA_TORONTO" <<'EOF'
$GPGGA,123519,4339.00,N,07923.00,W,1,08,0.9,76.0,M,-34.0,M,,*7A
EOF

RMC_TORONTO="$BASE/rmc_toronto.nmea"
cat > "$RMC_TORONTO" <<'EOF'
$GPRMC,123519,A,4339.00,N,07923.00,W,022.4,084.4,230394,003.1,W*6A
EOF

GGA_SANS_CORRECTION="$BASE/gga_sans_correction.nmea"
cat > "$GGA_SANS_CORRECTION" <<'EOF'
$GPGGA,123519,4339.00,N,07923.00,W,0,00,,,M,,M,,*66
EOF

RMC_INVALIDE="$BASE/rmc_invalide.nmea"
cat > "$RMC_INVALIDE" <<'EOF'
$GPRMC,123519,V,4339.00,N,07923.00,W,022.4,084.4,230394,003.1,W*67
EOF

GEOIP_TOKYO="$BASE/geoip_tokyo.json"
echo '{"ip":"1.2.3.4","city":"Tokyo","timezone":"Asia/Tokyo"}' > "$GEOIP_TOKYO"

GEOIP_INCONNU="$BASE/geoip_inconnu.json"
echo '{"ip":"1.2.3.4","timezone":"Pas/UnVraiFuseau"}' > "$GEOIP_INCONNU"

GEOIP_SANS_CHAMP="$BASE/geoip_sans_champ.json"
echo '{"ip":"1.2.3.4","city":"Nulle part"}' > "$GEOIP_SANS_CHAMP"

DEV_ABSENT="$BASE/aucun-port-ici"

echo "── Détecteur : GPS d'abord ────────────────────────────────────────────"
essai_detecteur "GGA, correction valide (Toronto)" gps America/Toronto \
	LEXOS_GPS_DEV="$GGA_TORONTO"
essai_detecteur "RMC, statut actif (Toronto)" gps America/Toronto \
	LEXOS_GPS_DEV="$RMC_TORONTO"

echo "── Détecteur : GPS muet ou invalide → IP -------------------------------"
essai_detecteur "GGA sans correction (qualité 0) → IP" ip Asia/Tokyo \
	LEXOS_GPS_DEV="$GGA_SANS_CORRECTION" LEXOS_GEOIP_CMD="cat $GEOIP_TOKYO"
essai_detecteur "RMC invalide (statut V) → IP" ip Asia/Tokyo \
	LEXOS_GPS_DEV="$RMC_INVALIDE" LEXOS_GEOIP_CMD="cat $GEOIP_TOKYO"
essai_detecteur "aucun port GPS → IP" ip Asia/Tokyo \
	LEXOS_GPS_DEV="$DEV_ABSENT" LEXOS_GEOIP_CMD="cat $GEOIP_TOKYO"

echo "── Détecteur : IP invalide ou muette → repli ---------------------------"
essai_detecteur "JSON sans champ timezone → repli" repli America/Toronto \
	LEXOS_GPS_DEV="$DEV_ABSENT" LEXOS_GEOIP_CMD="cat $GEOIP_SANS_CHAMP"
essai_detecteur "fuseau inconnu de zoneinfo → repli" repli America/Toronto \
	LEXOS_GPS_DEV="$DEV_ABSENT" LEXOS_GEOIP_CMD="cat $GEOIP_INCONNU"
essai_detecteur "commande IP en échec → repli" repli America/Toronto \
	LEXOS_GPS_DEV="$DEV_ABSENT" LEXOS_GEOIP_CMD="false"
essai_detecteur "tout échoue, repli personnalisé" repli Europe/Paris \
	LEXOS_GPS_DEV="$DEV_ABSENT" LEXOS_GEOIP_CMD="false" LEXOS_FALLBACK_TZ="Europe/Paris"

echo
echo "── Confirmeur : ne demande que si ça change quelque chose ─────────────"

FAUX_DETECTEUR_TOKYO="$BASE/faux-detecteur-tokyo"
cat > "$FAUX_DETECTEUR_TOKYO" <<'EOF'
#!/bin/sh
echo "SOURCE=ip"
echo "FUSEAU=Asia/Tokyo"
EOF
chmod +x "$FAUX_DETECTEUR_TOKYO"

FAUX_DETECTEUR_REPLI="$BASE/faux-detecteur-repli"
cat > "$FAUX_DETECTEUR_REPLI" <<'EOF'
#!/bin/sh
echo "SOURCE=repli"
echo "FUSEAU=America/Toronto"
EOF
chmod +x "$FAUX_DETECTEUR_REPLI"

FAUX_DETECTEUR_DEJA="$BASE/faux-detecteur-deja"
cat > "$FAUX_DETECTEUR_DEJA" <<'EOF'
#!/bin/sh
echo "SOURCE=ip"
echo "FUSEAU=America/Toronto"
EOF
chmod +x "$FAUX_DETECTEUR_DEJA"

TZFILE="$BASE/timezone"
echo "America/Toronto" > "$TZFILE"

JOURNAL="$BASE/timedatectl.log"
FAUX_TIMEDATECTL="$BASE/faux-timedatectl"
cat > "$FAUX_TIMEDATECTL" <<EOF
#!/bin/sh
echo "\$*" >> "$JOURNAL"
exit 0
EOF
chmod +x "$FAUX_TIMEDATECTL"

essai_confirmeur() { # libellé  détecteur  réponse-test  applique-attendu(0/1)  fuseau-attendu-dans-journal
	local libelle="$1" detecteur="$2" reponse="$3" applique_attendu="$4" fuseau_attendu="${5:-}"
	N=$((N + 1))
	rm -f "$JOURNAL"
	LEXOS_FUSEAU_POSITION="$detecteur" \
	LEXOS_TIMEZONE_FILE="$TZFILE" \
	LEXOS_TIMEDATECTL="$FAUX_TIMEDATECTL" \
	LEXOS_REPONSE_TEST="$reponse" \
		"$CONFIRMEUR" >/dev/null 2>&1
	local code=$?
	local applique=0
	[[ -s "$JOURNAL" ]] && applique=1
	if [[ "$code" -ne 0 ]]; then
		printf 'ÉCHEC %-42s code de sortie %s (attendu 0)\n' "$libelle" "$code"
		ECHECS=$((ECHECS + 1))
	elif [[ "$applique" -ne "$applique_attendu" ]]; then
		printf 'ÉCHEC %-42s application=%s (attendu %s)\n' "$libelle" "$applique" "$applique_attendu"
		ECHECS=$((ECHECS + 1))
	elif [[ "$applique" -eq 1 ]] && ! grep -q "$fuseau_attendu" "$JOURNAL"; then
		printf 'ÉCHEC %-42s journal inattendu : %s\n' "$libelle" "$(cat "$JOURNAL")"
		ECHECS=$((ECHECS + 1))
	else
		printf 'ok    %s\n' "$libelle"
	fi
}

essai_confirmeur "détection différente, réponse oui → applique" \
	"$FAUX_DETECTEUR_TOKYO" oui 1 "Asia/Tokyo"
essai_confirmeur "détection différente, réponse non → conserve" \
	"$FAUX_DETECTEUR_TOKYO" non 0
essai_confirmeur "déjà le bon fuseau → ne demande rien, n'applique rien" \
	"$FAUX_DETECTEUR_DEJA" oui 0
essai_confirmeur "source = repli → ne redemande pas Toronto" \
	"$FAUX_DETECTEUR_REPLI" oui 0

echo
echo "── Le confirmeur ne bloque jamais l'installation ───────────────────────"
N=$((N + 1))
DETECTEUR_ABSENT="$BASE/n-existe-pas"
if LEXOS_FUSEAU_POSITION="$DETECTEUR_ABSENT" LEXOS_TIMEZONE_FILE="$TZFILE" "$CONFIRMEUR" >/dev/null 2>&1; then
	echo "ok    détecteur absent : le confirmeur rend 0 quand même"
else
	echo "ÉCHEC détecteur absent : le confirmeur a échoué au lieu de laisser passer"
	ECHECS=$((ECHECS + 1))
fi

echo
echo "── lexos-install appelle bien le confirmeur, sans jamais bloquer ──────"
N=$((N + 1))
INSTALL="$ICI/../config/includes.chroot/usr/bin/lexos-install"
if grep -q 'lexos-fuseau-confirmer.*||.*true' "$INSTALL"; then
	echo "ok    lexos-install appelle lexos-fuseau-confirmer (best-effort)"
else
	echo "ÉCHEC lexos-install n'appelle pas lexos-fuseau-confirmer en best-effort"
	ECHECS=$((ECHECS + 1))
fi

echo
if (( ECHECS )); then
	echo "$ECHECS échec(s) sur $N vérifications."
	exit 1
fi
echo "Tout passe : $N vérifications (détecteur GPS/IP/repli, confirmeur, intégration)."
