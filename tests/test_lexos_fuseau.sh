#!/usr/bin/env bash
# =============================================================================
#  Éprouver le choix manuel du fuseau horaire — treize provinces, pas sept
# =============================================================================
#  ALEX a envoyé une maquette PySide6 avec TOUTES les régions du Canada
#  (province, ville, fuseau horaire) et a demandé que « tout soit rempli ».
#  La vraie infrastructure existait déjà (lexos-datetime, LIEUX_CANADA) mais
#  ne couvrait que sept fuseaux sur onze, et rien ne l'exposait dans la page
#  web des Paramètres — seule la ligne de commande le savait.
#
#  TROIS FICHIERS DOIVENT RESTER D'ACCORD, ET C'EST CE QUE CE BANC PROUVE :
#    · lexos-datetime   (LIEUX_CANADA)   — la commande, et lieu_vers_zone()
#    · settings.py      (FUSEAUX_CANADA) — la liste blanche du pont web
#    · app.js            (FUSEAUX_CANADA) — les boutons de la page
#  Un fuseau qui existe dans l'un et pas les deux autres est un bouton qui
#  ment, ou une commande qui refuse ce que le bouton vient d'offrir.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
DATETIME="$RACINE/config/includes.chroot/usr/bin/lexos-datetime"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. FUSEAUX_CANADA (settings.py) — onze vrais fuseaux IANA, pas devinés"
# =============================================================================
ZONES_PY="$(python3 -c "
import sys, importlib.util, zoneinfo
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
zones = sorted(m.FUSEAUX_CANADA.keys())
print(len(zones))
for z in zones:
    try:
        zoneinfo.ZoneInfo(z)
        print('OK', z)
    except Exception as e:
        print('FAIL', z, e)
for z in zones:
    print('Z', z)
")"

N="$(echo "$ZONES_PY" | head -1)"
[ "$N" = "11" ] \
	&& ok "onze fuseaux dans FUSEAUX_CANADA (les treize provinces/territoires, deux partagent)" \
	|| non "FUSEAUX_CANADA porte $N fuseaux, pas 11"

if echo "$ZONES_PY" | grep -q '^FAIL'; then
	non "au moins un fuseau n'est pas un vrai fuseau IANA : $(echo "$ZONES_PY" | grep '^FAIL')"
else
	ok "les onze fuseaux sont de VRAIS fuseaux IANA (zoneinfo les reconnaît tous)"
fi

# =============================================================================
titre "2. Les quatre provinces/territoires qui manquaient sont bien là"
# =============================================================================
for Z in America/Regina America/Whitehorse America/Yellowknife America/Iqaluit; do
	echo "$ZONES_PY" | grep -q "^Z $Z\$" \
		&& ok "$Z présent (manquait avant)" \
		|| non "$Z toujours absent"
done

# =============================================================================
titre "3. act_fuseau() — liste fermée, jamais une commande à l'aveugle"
# =============================================================================
faux_outil() { # faux_outil <nom> <journal>
	cat > "$BANC/$1" <<EOS
#!/bin/sh
echo "$1 \$*" >> "$2"
exit 0
EOS
	chmod +x "$BANC/$1"
}
JOURNAL="$BANC/appels.txt"
faux_outil pkexec "$JOURNAL"
faux_outil timedatectl "$JOURNAL"

appelle_fuseau() { # appelle_fuseau <zone>
	: > "$JOURNAL"
	PATH="$BANC:/usr/bin:/bin" python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.act_fuseau('$1'))
"
	cat "$JOURNAL" 2>/dev/null
}

SORTIE="$(appelle_fuseau "America/Toronto")"
case "$SORTIE" in
	*"'ok': True"*"pkexec timedatectl set-timezone America/Toronto"*)
		ok "un fuseau VALIDE (Ontario) -> pkexec timedatectl set-timezone, avec la fenêtre de mot de passe" ;;
	*) non "America/Toronto (valide) n'a pas donné le bon appel : $SORTIE" ;;
esac

SORTIE="$(appelle_fuseau "America/New_York")"
case "$SORTIE" in
	*"'ok': False"*)
		echo "$SORTIE" | grep -q "pkexec\|timedatectl" \
			&& non "America/New_York (hors liste) a quand même appelé timedatectl : $SORTIE" \
			|| ok "un fuseau HORS LISTE (America/New_York, réel mais pas canadien) est refusé, rien n'est exécuté" ;;
	*) non "America/New_York aurait dû être refusé : $SORTIE" ;;
esac

SORTIE="$(appelle_fuseau "America/Toronto; rm -rf /tmp/rien")"
case "$SORTIE" in
	*"'ok': False"*)
		echo "$SORTIE" | grep -q "pkexec\|timedatectl" \
			&& non "une tentative d'injection a quand même déclenché une commande : $SORTIE" \
			|| ok "une chaîne avec un point-virgule est refusée telle quelle, jamais découpée par un shell" ;;
	*) non "l'injection aurait dû être refusée : $SORTIE" ;;
esac

# =============================================================================
titre "4. lexos-datetime — les nouveaux alias parlés retrouvent le bon fuseau"
# =============================================================================
lieu_vers_zone() { # lieu_vers_zone <mot>
	bash -c "
source <(sed -n '/^lieu_vers_zone()/,/^}/p' '$DATETIME')
lieu_vers_zone '$1'
"
}
declare -A ALIAS_ATTENDUS=(
	[saskatchewan]=America/Regina
	[regina]=America/Regina
	[yukon]=America/Whitehorse
	[whitehorse]=America/Whitehorse
	[tno]=America/Yellowknife
	[yellowknife]=America/Yellowknife
	[nunavut]=America/Iqaluit
	[iqaluit]=America/Iqaluit
)
for MOT in "${!ALIAS_ATTENDUS[@]}"; do
	VU="$(lieu_vers_zone "$MOT")"
	[ "$VU" = "${ALIAS_ATTENDUS[$MOT]}" ] \
		&& ok "« $MOT » -> ${ALIAS_ATTENDUS[$MOT]}" \
		|| non "« $MOT » a donné « $VU », attendu « ${ALIAS_ATTENDUS[$MOT]} »"
done

# =============================================================================
titre "5. Les trois fichiers restent d'accord entre eux"
# =============================================================================
ZONES_JS="$(grep -oE '"America/[A-Za-z_]+"' "$APPJS" | tr -d '"' | sort -u)"
ZONES_SH="$(grep -oE '\|America/[A-Za-z_]+"' "$DATETIME" | tr -d '|"' | sort -u)"
ZONES_PY_LISTE="$(echo "$ZONES_PY" | sed -n 's/^Z //p' | sort -u)"

DESACCORD=0
while read -r Z; do
	[ -n "$Z" ] || continue
	if ! echo "$ZONES_JS" | grep -qxF "$Z"; then
		non "« $Z » est dans settings.py mais AUCUN bouton ne l'offre dans app.js"
		DESACCORD=1
	fi
	if ! echo "$ZONES_SH" | grep -qxF "$Z"; then
		non "« $Z » est dans settings.py mais n'est pas dans LIEUX_CANADA (lexos-datetime)"
		DESACCORD=1
	fi
done <<< "$ZONES_PY_LISTE"
[ "$DESACCORD" -eq 0 ] \
	&& ok "les onze fuseaux de settings.py sont TOUS offerts par app.js ET connus de lexos-datetime"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
