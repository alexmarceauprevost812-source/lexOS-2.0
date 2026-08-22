#!/usr/bin/env bash
# =============================================================================
#  test_verifier_parametres.sh — le contrôle 16 doit dire la MÊME chose partout
# =============================================================================
#  NÉ D'UNE CI ROUGE POUR RIEN. Le contrôle 16 employait la classe [à-ÿ] pour
#  attraper les alias accentués du dispatcheur. Un intervalle de caractères
#  non ASCII dépend de la locale : sur le runner, grep et sed ont répondu
#  « Invalid collation character » — deux lignes noyées dans la sortie — et
#  l'extraction des alias a rendu du vide. Trois outils parfaitement branchés
#  ont été déclarés « absents de l'aide », et la CI est passée au rouge.
#
#  Ce test empêche le retour du défaut sous toutes ses formes :
#    1. le même verdict dans plusieurs locales ;
#    2. aucune plainte de motif (collation, invalid range…) ;
#    3. les alias accentués sont VRAIMENT lus ;
#    4. le garde-fou s'arrête quand l'extraction ne rend rien.
# =============================================================================
set -u

ICI="$(cd "$(dirname "$0")" && pwd)"
RACINE="$ICI/.."
cd "$RACINE" || exit 2

NB_OK=0; NB_KO=0
ok() { NB_OK=$((NB_OK+1)); echo "  ✅ $1"; }
ko() { NB_KO=$((NB_KO+1)); echo "  ❌ $1"; }

echo "═══ 1. Le même verdict dans plusieurs locales ═══"
#  UNE LOCALE ABSENTE NE DOIT PAS FAIRE SEMBLANT DE PASSER.
#  Si fr_CA.UTF-8 n'est pas engendrée sur la machine, setlocale échoue en
#  silence et grep retombe en C : le test dirait « ✅ » sans avoir rien
#  éprouvé. On le DIT, et on exige qu'au moins une locale non-C soit là,
#  sinon ce test ne garde plus rien et vaut mieux qu'il le crie.
DISPOS="$(locale -a 2>/dev/null || true)"
#  « fr_CA.UTF-8 » et « fr_CA.utf8 » désignent la MÊME locale : locale -a
#  l'écrit d'une façon, on l'appelle de l'autre. On compare donc les deux
#  côtés une fois le tiret ôté et la casse rabattue — sinon on croit
#  absente une locale parfaitement là.
DISPOS_N="$(printf '%s\n' "$DISPOS" | tr -d '-' | tr 'A-Z' 'a-z')"
locale_la() {
	[ "$1" = "C" ] && return 0
	printf '%s\n' "$DISPOS_N" \
		| grep -qxF "$(printf '%s' "$1" | tr -d '-' | tr 'A-Z' 'a-z')"
}

REF=""; NB_UTF8=0
for L in C C.UTF-8 en_US.UTF-8 fr_CA.UTF-8; do
	if ! locale_la "$L"; then
		echo "  ⏭  locale $L absente de cette machine — non éprouvée"
		continue
	fi
	[ "$L" = "C" ] || NB_UTF8=$((NB_UTF8+1))
	SORTIE="$(LC_ALL="$L" ./verifier-parametres.sh 2>&1)"
	BILAN="$(printf '%s\n' "$SORTIE" | tail -1)"
	case "$SORTIE" in
		*collation*|*"Invalid range"*|*"invalid character class"*)
			ko "locale $L : le motif se plaint — « $(printf '%s\n' "$SORTIE" | grep -m1 -i 'collation\|invalid')" ;;
		*) ok "locale $L : aucune plainte de motif" ;;
	esac
	if [ -z "$REF" ]; then
		REF="$BILAN"
	elif [ "$BILAN" = "$REF" ]; then
		ok "locale $L : même bilan qu'en C — « $BILAN »"
	else
		ko "locale $L : bilan DIFFÉRENT — « $BILAN » au lieu de « $REF »"
	fi
done
if [ "$NB_UTF8" = "0" ]; then
	ko "aucune locale UTF-8 sur cette machine : le test n'a rien pu éprouver"
	echo "     (engendrer p. ex. « locale-gen fr_CA.UTF-8 » avant de le relancer)"
fi

echo "═══ 2. Les alias accentués sont lus ═══"
#  Trois outils dont le nom court n'apparaît PAS dans l'aide : ils ne
#  passent que si l'alias accentué (température, écran) a été lu.
for OUTIL in lexos-temp lexos-brightness lexos-display; do
	if LC_ALL=C ./verifier-parametres.sh 2>/dev/null | grep -q "✓ $OUTIL\$"; then
		ok "$OUTIL est reconnu par son alias"
	else
		ko "$OUTIL n'est pas reconnu — les alias ne sont pas lus"
	fi
done

echo "═══ 3. Le garde-fou s'arrête au lieu d'accuser ═══"
SAUV="$(mktemp)"
cp config/includes.chroot/usr/bin/lexos "$SAUV"
: > config/includes.chroot/usr/bin/lexos
SORTIE="$(./verifier-parametres.sh 2>&1)"; CODE=$?
cp "$SAUV" config/includes.chroot/usr/bin/lexos
chmod +x config/includes.chroot/usr/bin/lexos
rm -f "$SAUV"
[ "$CODE" = "2" ] && ok "sortie 2 quand rien n'est lisible" \
	|| ko "sortie $CODE au lieu de 2 — le contrôle a continué sur du vide"
case "$SORTIE" in
	*"aucune branche lue"*) ok "et il DIT pourquoi il s'arrête" ;;
	*) ko "il s'arrête sans expliquer" ;;
esac

echo
echo "$NB_OK réussi(s), $NB_KO échoué(s)"
exit $((NB_KO > 0))
