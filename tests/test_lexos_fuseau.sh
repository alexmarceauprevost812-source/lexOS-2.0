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

if grep -q '^FAIL' <<< "$ZONES_PY" ; then
	non "au moins un fuseau n'est pas un vrai fuseau IANA : $(echo "$ZONES_PY" | grep '^FAIL')"
else
	ok "les onze fuseaux sont de VRAIS fuseaux IANA (zoneinfo les reconnaît tous)"
fi

# =============================================================================
titre "2. Les quatre provinces/territoires qui manquaient sont bien là"
# =============================================================================
for Z in America/Regina America/Whitehorse America/Yellowknife America/Iqaluit; do
	grep -q "^Z $Z\$" <<< "$ZONES_PY" \
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

#  ═══ ON JOUE UN COMPTE ORDINAIRE, PAS root ═══
#  act_fuseau passe maintenant par _run_admin(), qui n'enveloppe dans pkexec
#  QUE si l'euid n'est pas 0 — un banc lancé en root ne verrait donc jamais
#  pkexec, et le contrôle mesurerait le compte du coureur au lieu du code.
#  On force donc l'euid et la présence d'un agent d'authentification.
#
#  ET CET AGENT COMPTE. pkexec ne dessine PAS lui-même la fenêtre du mot de
#  passe : il la demande à un agent qui doit tourner dans la session. Sans
#  agent, pkexec échoue sans fenêtre et sans message — c'est exactement la
#  panne « le bouton ne fait rien » qu'Alex a décrite sur son vieil
#  ordinateur. Le moteur refuse donc désormais AVANT de lancer un pkexec
#  qui se tairait, et les deux cas sont éprouvés ici.
appelle_fuseau() { # appelle_fuseau <zone> [agent:oui|non]
	: > "$JOURNAL"
	PATH="$BANC:/usr/bin:/bin" AGENT="${2:-oui}" python3 -c "
import os, importlib.util
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.os.geteuid = lambda: 1000
m._agent_polkit = lambda: os.environ.get('AGENT') == 'oui'
print(m.act_fuseau('$1'))
"
	cat "$JOURNAL" 2>/dev/null
}

SORTIE="$(appelle_fuseau "America/Toronto" oui)"
case "$SORTIE" in
	*"'ok': True"*"pkexec timedatectl set-timezone America/Toronto"*)
		ok "un fuseau VALIDE (Ontario) -> pkexec timedatectl set-timezone, avec la fenêtre de mot de passe" ;;
	*) non "America/Toronto (valide) n'a pas donné le bon appel : $SORTIE" ;;
esac

#  SANS AGENT : il doit REFUSER en le disant, et ne RIEN lancer.
SORTIE="$(appelle_fuseau "America/Toronto" non)"
case "$SORTIE" in
	*"'ok': False"*)
		if printf '%s' "$SORTIE" > "$BANC/sortie-sans-agent" && grep -q "timedatectl set-timezone" "$BANC/sortie-sans-agent"; then
			non "sans agent d'authentification, timedatectl a quand même été lancé : $SORTIE"
		else
			printf '%s' "$SORTIE" > "$BANC/sortie-sans-agent"
			grep -qi "agent" "$BANC/sortie-sans-agent" \
				&& ok "sans agent d'authentification : il refuse et DIT ce qui manque, au lieu d'un bouton muet" \
				|| non "il refuse sans dire pourquoi : le bouton paraîtrait mort ($SORTIE)"
		fi ;;
	*) non "sans agent, changer le fuseau aurait dû être refusé : $SORTIE" ;;
esac

SORTIE="$(appelle_fuseau "America/New_York")"
case "$SORTIE" in
	*"'ok': False"*)
		grep -q "pkexec\|timedatectl" <<< "$SORTIE" \
			&& non "America/New_York (hors liste) a quand même appelé timedatectl : $SORTIE" \
			|| ok "un fuseau HORS LISTE (America/New_York, réel mais pas canadien) est refusé, rien n'est exécuté" ;;
	*) non "America/New_York aurait dû être refusé : $SORTIE" ;;
esac

SORTIE="$(appelle_fuseau "America/Toronto; rm -rf /tmp/rien")"
case "$SORTIE" in
	*"'ok': False"*)
		grep -q "pkexec\|timedatectl" <<< "$SORTIE" \
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
	if ! grep -qxF "$Z" <<< "$ZONES_JS" ; then
		non "« $Z » est dans settings.py mais AUCUN bouton ne l'offre dans app.js"
		DESACCORD=1
	fi
	if ! grep -qxF "$Z" <<< "$ZONES_SH" ; then
		non "« $Z » est dans settings.py mais n'est pas dans LIEUX_CANADA (lexos-datetime)"
		DESACCORD=1
	fi
done <<< "$ZONES_PY_LISTE"
[ "$DESACCORD" -eq 0 ] \
	&& ok "les onze fuseaux de settings.py sont TOUS offerts par app.js ET connus de lexos-datetime"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
