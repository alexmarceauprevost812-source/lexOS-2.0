#!/usr/bin/env bash
# =============================================================================
#  SIGNER LE PILOTE PLUTÔT QUE COUPER LE SECURE BOOT
# =============================================================================
#  LE PROBLÈME. Le module NVIDIA est compilé sur la machine par DKMS. Un
#  module compilé n'est pas signé par la clé de Debian : avec Secure Boot
#  actif, le noyau le REFUSE. Et comme LexOS écarte « nouveau » à raison (il
#  ne sait pas piloter les RTX 50), il ne reste AUCUN pilote graphique.
#
#  LA RÉPONSE QU'ON DONNAIT, ET CE QU'ELLE COÛTE. « Va couper le Secure Boot
#  dans le BIOS. » Sur une machine en double démarrage — celle d'Alex l'est —
#  BitLocker réclame sa clé de récupération au démarrage suivant de Windows,
#  et plusieurs jeux exigent le Secure Boot actif.
#
#  LA VRAIE RÉPONSE est de faire ACCEPTER la clé locale par le micrologiciel.
#  Le Secure Boot reste actif : ni BitLocker ni les jeux ne sont touchés.
#
#  ═══ CE QUE CE BANC ÉPROUVE ═══
#  1. L'outil REFUSE là où ça ne peut pas marcher (session live), et dit
#     pourquoi — une clé MOK s'inscrit au redémarrage, et une session live
#     oublie tout en redémarrant.
#  2. Il ne promet rien qu'il n'ait vérifié : certificat absent, mokutil
#     absent, module non signé — trois refus distincts, trois marches à
#     suivre différentes. « Je ne sais pas » est une réponse, pas un échec.
#  3. Quand tout est prêt, il dit les TROIS choses qui font de cette voie la
#     bonne : Secure Boot actif, BitLocker intact, jeux intacts.
#  4. « --etat » ne touche à RIEN.
#  5. ET AUCUNE CLÉ PRIVÉE NULLE PART. Ni dans l'outil, ni dans le dépôt.
#     Une clé embarquée dans l'ISO serait la même pour tout le monde : ce ne
#     serait plus une signature, ce serait une porte.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-signer-pilote"
SHELL_DIR="$RACINE/config/includes.chroot/usr/share/lexos/shell"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$OUTIL" ] || { non "lexos-signer-pilote introuvable ($OUTIL)"; printf '\n'; exit 1; }

# --- La scène : une machine fabriquée de toutes pièces ----------------------
mkdir -p "$BANC/bin" "$BANC/efi-on" "$BANC/efi-off" "$BANC/dkms" "$BANC/dkms/conf.d"
python3 - "$BANC/efi-on/SecureBoot-8be4df61" <<'PY' 2>/dev/null || muet "python3 absent : Secure Boot actif ne sera pas joué"
import sys
#  5 octets : 4 d'attributs, puis la valeur. Le cinquième vaut 1 = ACTIF.
open(sys.argv[1], "wb").write(bytes([6, 0, 0, 0, 1]))
PY
printf 'boot=live components quiet\n'      > "$BANC/cmdline-live"
printf 'root=/dev/nvme0n1p2 quiet\n'       > "$BANC/cmdline-installe"
printf 'nvidia 1 - Live 0x0\n'             > "$BANC/modules"
: > "$BANC/cert.pub"

#  Les faux outils enregistrent qu'on les a appelés : c'est comme ça qu'on
#  mesure « --etat ne touche à rien » au lieu de le croire sur parole.
cat > "$BANC/bin/modinfo" <<'EOF'
#!/bin/sh
case "$*" in
	*sig_id*) [ "${FAUX_SIGNE:-1}" = "1" ] && echo "PKCS#7"; exit 0 ;;
esac
exit 0
EOF
cat > "$BANC/bin/mokutil" <<'EOF'
#!/bin/sh
printf 'APPELE %s\n' "$*" >> "$LEXOS_BANC_TRACE"
exit 0
EOF
cat > "$BANC/bin/dkms" <<'EOF'
#!/bin/sh
printf 'APPELE %s\n' "$*" >> "$LEXOS_BANC_TRACE"
exit 0
EOF
chmod +x "$BANC/bin"/*

joue() {   # joue <cmdline> <efivars> <framework.conf> [VAR=val…]
	local cmd="$1" efi="$2" conf="$3"; shift 3
	: > "$BANC/trace"
	env -i PATH="$BANC/bin:/usr/bin:/bin" HOME="$BANC" NO_COLOR=1 TERM=dumb \
		LEXOS_CMDLINE="$cmd" LEXOS_EFIVARS="$efi" \
		LEXOS_DKMS_CONF="$conf" LEXOS_DKMS_CONF_D="$BANC/dkms/conf.d" \
		LEXOS_SHELL_DIR="$SHELL_DIR" LEXOS_MODULES="$BANC/modules" \
		LEXOS_BANC_TRACE="$BANC/trace" \
		"$@" bash "$OUTIL" --etat 2>&1
}
printf 'mok_certificate="%s"\n' "$BANC/cert.pub" > "$BANC/dkms/framework.conf"
printf 'mok_certificate="%s"\n' "$BANC/absent.pub" > "$BANC/dkms/sans-cert.conf"

# ===========================================================================
titre "1. IL REFUSE LÀ OÙ ÇA NE PEUT PAS MARCHER"
# ===========================================================================
VU="$(joue "$BANC/cmdline-live" "$BANC/efi-on" "$BANC/dkms/framework.conf")"
case "$VU" in
	*"session LIVE"*"MokManager"*"oublie tout"*)
		ok "en session live, il refuse et dit pourquoi (l'inscription se termine au redémarrage)" ;;
	*) non "la session live n'est pas reconnue, ou le refus n'explique rien : $(printf '%s' "$VU" | tail -3 | tr '\n' ' ')" ;;
esac
case "$VU" in
	*"mot de passe"*) non "il propose quand même l'inscription en session live : le mot de passe serait tapé pour rien" ;;
	*) ok "…et il ne propose PAS l'inscription : rien ne sera tapé pour rien" ;;
esac

VU="$(joue "$BANC/cmdline-installe" "$BANC/efi-off" "$BANC/dkms/framework.conf")"
case "$VU" in
	*"Secure Boot est INACTIF"*"pile CMOS"*)
		ok "Secure Boot inactif : rien à faire aujourd'hui — mais il dit que ça peut revenir" ;;
	*"Secure Boot est INACTIF"*) non "il dit « inactif » sans prévenir qu'une mise à jour du BIOS le réactive" ;;
	*) non "Secure Boot inactif n'est pas reconnu : $(printf '%s' "$VU" | tail -2 | tr '\n' ' ')" ;;
esac

# ===========================================================================
titre "2. TROIS REFUS DISTINCTS, TROIS MARCHES À SUIVRE"
# ===========================================================================
#  Un outil qui dirait « ça n'a pas marché » dans les trois cas renverrait
#  chercher au hasard. Chaque manque a sa propre réponse.
VU="$(joue "$BANC/cmdline-installe" "$BANC/efi-on" "$BANC/dkms/sans-cert.conf")"
case "$VU" in
	*"n'existe pas encore"*"generate_mok"*) ok "certificat absent → « dkms generate_mok », pas un message vague" ;;
	*) non "certificat absent : la marche à suivre ne nomme pas dkms generate_mok" ;;
esac

VU="$(env -i PATH="/usr/bin:/bin" HOME="$BANC" NO_COLOR=1 TERM=dumb \
	LEXOS_CMDLINE="$BANC/cmdline-installe" LEXOS_EFIVARS="$BANC/efi-on" \
	LEXOS_DKMS_CONF="$BANC/dkms/framework.conf" LEXOS_DKMS_CONF_D="$BANC/dkms/conf.d" \
	LEXOS_SHELL_DIR="$SHELL_DIR" LEXOS_MODULES="$BANC/modules" \
	bash "$OUTIL" --etat 2>&1)"
case "$VU" in
	*"mokutil"*"apt install mokutil"*) ok "mokutil absent → la commande exacte pour l'installer" ;;
	*) non "mokutil absent : l'outil ne dit pas comment l'obtenir" ;;
esac

VU="$(joue "$BANC/cmdline-installe" "$BANC/efi-on" "$BANC/dkms/framework.conf" FAUX_SIGNE=0)"
case "$VU" in
	*"n'est PAS signé"*"dkms autoinstall"*)
		ok "module non signé → recompiler d'abord, parce qu'inscrire ne servirait à rien" ;;
	*) non "un module non signé n'est pas distingué : on inscrirait une clé pour rien" ;;
esac

# ===========================================================================
titre "3. QUAND TOUT EST PRÊT : LES TROIS CHOSES QUI FONT LA DIFFÉRENCE"
# ===========================================================================
#  ═══ C'EST LE CŒUR DE CETTE ÉTAPE ═══
#  Si le message ne dit PAS que le Secure Boot reste actif, que BitLocker ne
#  bronchera pas et que les jeux continueront, alors rien ne distingue cette
#  voie de « va couper le Secure Boot » — et personne ne comprendra pourquoi
#  elle est meilleure. Les trois affirmations sont la raison d'être de l'outil.
VU="$(joue "$BANC/cmdline-installe" "$BANC/efi-on" "$BANC/dkms/framework.conf")"
printf '%s' "$VU" | grep -qE 'Secure Boot reste ACTIF' \
	&& ok "il dit que le Secure Boot reste ACTIF" \
	|| non "il ne dit pas que le Secure Boot reste actif : rien ne distingue cette voie de l'autre"
printf '%s' "$VU" | grep -qE 'BitLocker ne bronchera pas' \
	&& ok "…que BitLocker ne réclamera aucune clé de récupération" \
	|| non "il ne rassure pas sur BitLocker — c'est pourtant le premier risque de l'autre voie"
printf '%s' "$VU" | grep -qE 'jeux Windows' \
	&& ok "…et que les jeux à anti-triche continueront de fonctionner" \
	|| non "il ne dit rien des jeux : Alex se sert de Windows pour ça"
printf '%s' "$VU" | grep -qE 'Enroll MOK' \
	&& ok "…et il nomme l'écran bleu et ses boutons, en anglais comme à l'écran" \
	|| non "il ne décrit pas MokManager : l'écran bleu passera vite et sans rien faire"

# ===========================================================================
titre "4. « --etat » NE TOUCHE À RIEN"
# ===========================================================================
#  Les faux mokutil et dkms écrivent dans une trace quand on les appelle. La
#  trace doit être VIDE : on ne relit pas le code, on regarde ce qui a été
#  lancé.
TRACE="$(cat "$BANC/trace" 2>/dev/null || true)"
[ -z "$TRACE" ] \
	&& ok "aucun outil qui MODIFIE la machine n'a été lancé (ni mokutil, ni dkms)" \
	|| non "« --etat » a lancé quelque chose : $TRACE"

# ===========================================================================
titre "5. AUCUNE CLÉ PRIVÉE — NI DANS L'OUTIL, NI DANS LE DÉPÔT"
# ===========================================================================
#  ═══ LA RÈGLE LA PLUS DURE DE CETTE ÉTAPE ═══
#  Une clé privée livrée dans l'ISO serait la même pour tout le monde : ce ne
#  serait plus une signature, ce serait une porte ouverte, et elle signerait
#  n'importe quel module sur n'importe quelle machine. La clé de DKMS reste
#  là où DKMS l'a mise, sur la machine, et l'outil n'y touche jamais.
SALE="$(grep -vE '^\s*#' "$OUTIL" | grep -cE 'mok\.key|mok_signing_key' || true)"
[ "${SALE:-0}" = "0" ] \
	&& ok "l'outil ne nomme JAMAIS la clé privée dans son code (il ne parle que du certificat)" \
	|| non "l'outil manipule la clé privée ($SALE occurrence(s)) : elle doit rester où DKMS l'a mise"

#  Et le dépôt entier : aucun fichier ne doit contenir un en-tête PEM de clé
#  privée. On cherche le CONTENU, pas le nom de fichier — une clé renommée
#  « notes.txt » reste une clé.
#  ⚠ LE MOTIF EST ASSEMBLÉ, PAS ÉCRIT EN TOUTES LETTRES. Première version :
#  il était littéral, et le contrôle s'est dénoncé LUI-MÊME — ce fichier
#  contenait l'en-tête qu'il cherche. Un contrôle qui rougit sur sa propre
#  prose finit par être désactivé, et c'est le pire des dénouements pour
#  celui-ci. On le construit donc en morceaux.
DEBUT="-----BEGIN"; FIN="PRIVATE KEY-----"
PEM="$(grep -rIl -- "${DEBUT} .*${FIN}" "$RACINE" \
	--exclude-dir=.git --exclude-dir=node_modules 2>/dev/null | head -5)"
[ -z "$PEM" ] \
	&& ok "aucune clé privée dans le dépôt (recherche sur le CONTENU, pas sur le nom)" \
	|| non "des clés privées sont versionnées : $PEM"

# ===========================================================================
titre "6. ET C'EST ATTEIGNABLE — sinon personne ne le trouvera"
# ===========================================================================
if [[ ! -r "$DISPATCH" ]]; then
	non "le dispatcheur lexos est introuvable"
else
	grep -qE '^\s*signer-pilote\)' "$DISPATCH" \
		&& ok "« lexos signer-pilote » mène à l'outil" \
		|| non "le dispatcheur n'a pas de branche « signer-pilote » : la commande n'existe pas"
	#  ⚠ PAS DE « grep -q » EN BOUT DE TUBE. Sous « pipefail », -q sort au
	#  premier résultat, referme le tube, et le producteur meurt d'un SIGPIPE :
	#  le tube rend alors non-zéro ALORS QUE LA CHAÎNE EST BIEN LÀ. Ce contrôle
	#  a rougi comme ça sur une aide qui contenait pourtant le mot. On capture,
	#  puis on cherche.
	AIDE="$(bash "$DISPATCH" aide 2>/dev/null || true)"
	case "$AIDE" in
		*signer-pilote*) ok "…et il apparaît dans « lexos aide »" ;;
		"") non "« lexos aide » ne rend rien : le sommaire n'a pas pu être lu" ;;
		*)  non "l'outil est absent du sommaire des commandes" ;;
	esac
fi

#  Le message du Secure Boot ne doit le proposer QUE s'il est installé — sinon
#  il envoie taper une commande introuvable devant une console sans bureau.
SB="$SHELL_DIR/secure-boot.sh"
if grep -q 'lexos-signer-pilote' "$SB"; then
	grep -B2 'lexos-signer-pilote' "$SB" | grep -q 'command -v lexos-signer-pilote' \
		&& ok "…et le message du Secure Boot ne le propose que si la commande existe" \
		|| non "le message propose la commande sans vérifier qu'elle est là"
else
	muet "le message du Secure Boot ne mentionne pas l'outil"
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
