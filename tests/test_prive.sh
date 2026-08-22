#!/usr/bin/env bash
# =============================================================================
#  test_prive.sh — le coffre chiffré, testé sans jamais chiffrer
# =============================================================================
#  lexos-prive est le plus gros outil du dépôt (36 Ko) et celui où une
#  régression silencieuse coûte le plus : des fichiers qu'on croit protégés.
#  Il n'avait AUCUN test — c'est l'audit d'Alex qui l'a nommé.
#
#  On ne teste pas gocryptfs (c'est son travail, pas le nôtre) : on teste que
#  NOTRE script raisonne juste autour — refuse ce qui doit l'être, dit l'état
#  vrai, et n'invente jamais un coffre qui n'existe pas. Un faux gocryptfs
#  sur le PATH note ce qu'on lui demande ; le vrai n'est jamais appelé.
# =============================================================================
set -u

ICI="$(cd "$(dirname "$0")" && pwd)"
PRIVE="$ICI/../config/includes.chroot/usr/bin/lexos-prive"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

NB_OK=0; NB_KO=0
ok() { NB_OK=$((NB_OK+1)); echo "  ✅ $1"; }
ko() { NB_KO=$((NB_KO+1)); echo "  ❌ $1"; }
verifie() {  # $1 libellé, $2 attendu (0/1), $3 code obtenu
	if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (attendu $2, obtenu $3)"; fi
}

# --- Le faux gocryptfs --------------------------------------------------------
mkdir -p "$BAC/faux" "$BAC/home"
cat > "$BAC/faux/gocryptfs" <<'EOF'
#!/bin/sh
echo "gocryptfs $*" >> "$FAUX_JOURNAL"
exit 0
EOF
cat > "$BAC/faux/fusermount" <<'EOF'
#!/bin/sh
echo "fusermount $*" >> "$FAUX_JOURNAL"
exit 0
EOF
chmod +x "$BAC/faux/gocryptfs" "$BAC/faux/fusermount"
export FAUX_JOURNAL="$BAC/journal"

lance() {
	env PATH="$BAC/faux:/usr/bin:/bin" HOME="$BAC/home" NO_COLOR=1 \
		XDG_CONFIG_HOME="$BAC/home/.config" XDG_DATA_HOME="$BAC/home/.local/share" \
		bash "$PRIVE" "$@"
}

echo "═══ 1. La base ═══"
bash -n "$PRIVE" 2>/dev/null; verifie "la syntaxe bash est valide" 0 $?
lance --help >/dev/null 2>&1; verifie "--help sort sans erreur" 0 $?
SORTIE="$(lance --help 2>&1)"
case "$SORTIE" in *ouvrir*|*coffre*|*Coffre*) ok "l'aide parle du coffre" ;; *) ko "l'aide ne dit rien du coffre" ;; esac

echo "═══ 2. L'état, sans coffre ═══"
SORTIE="$(lance etat 2>&1)"; CODE=$?
verifie "« etat » sort proprement même sans coffre" 0 $CODE
case "$SORTIE" in
	*aucun*|*Aucun*|*pas\ *cr*|*existe\ pas*|*créé*) ok "et dit qu'il n'y a PAS de coffre — pas d'invention" ;;
	*) ko "l'état devrait dire qu'aucun coffre n'existe : $SORTIE" ;;
esac

echo "═══ 3. Ce qui doit être refusé ═══"
lance commande-qui-nexiste-pas >/dev/null 2>&1
[ $? -ne 0 ] && ok "une commande inconnue est refusée" || ko "une commande inconnue passe sans bruit"
#  Refermer un coffre déjà fermé RÉUSSIT en silence — c'est un choix
#  idempotent (vérifié dans fermer() : est_ouvert faux → return 0), comme
#  arrêter un service déjà arrêté. Ce qu'on vérifie : ça ne CASSE pas.
lance fermer >/dev/null 2>&1
verifie "« fermer » sans coffre ouvert réussit sans casser (idempotent)" 0 $?

echo "═══ 4. Rien ne part chiffrer en douce ═══"
if [ -f "$FAUX_JOURNAL" ] && grep -q 'gocryptfs -init\|gocryptfs.*-init' "$FAUX_JOURNAL"; then
	ko "un simple etat/aide a tenté de CRÉER un coffre"
else
	ok "aucune création de coffre n'a été tentée par les commandes de lecture"
fi

echo
echo "$NB_OK réussi(s), $NB_KO échoué(s)"
exit $((NB_KO > 0))
