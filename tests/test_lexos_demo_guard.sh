#!/usr/bin/env bash
# =============================================================================
#  Éprouver le garde-fou de démo — le correctif du 12 août, enfin protégé
# =============================================================================
#  CE QU'IL GARDE. Le 12 août, commit bd7b999 : « le système installé ouvrait
#  la session de démo, jamais celle de l'utilisateur ». Le compte était bien
#  créé par l'installateur — mais la machine installée ouvrait toute seule la
#  session « lex » de la démo, donc on n'arrivait JAMAIS à l'écran où choisir
#  son propre compte. On accusait l'installateur ; il avait fait son travail.
#
#  /usr/lib/lexos/demo-guard est ce correctif. Il n'était couvert par AUCUN
#  banc et par AUCUN contrôle de CI : la construction tolérait sa disparition
#  complète en silence (« || true », « || echo »), et l'ISO serait sortie avec
#  le bogue revenu à l'identique. Ce banc-ci, plus les « exit 1 » du hook
#  0400, ferment ce trou.
#
#  LES DEUX SENS, PAS UN SEUL. Un garde-fou trop zélé casserait la DÉMO, où
#  l'ouverture automatique est exactement ce qu'on veut. Un garde-fou trop
#  timide laisserait le bogue. Le banc éprouve donc les deux.
# =============================================================================
set -uo pipefail

RACINE_DEPOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GARDE="$RACINE_DEPOT/config/includes.chroot/usr/lib/lexos/demo-guard"
HOOK="$RACINE_DEPOT/config/hooks/normal/0400-lexos-desktop.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$GARDE" ] || { echo "demo-guard introuvable"; exit 1; }

TROIS=(
	"etc/sudoers.d/lexos-live"
	"etc/lightdm/lightdm.conf.d/60-lexos-autologin.conf"
	"etc/systemd/system/getty@tty1.service.d/lexos-autologin.conf"
)

#  Fabrique une fausse racine portant les trois réglages de démo, plus le
#  50-lexos.conf qu'on ne doit PAS effacer.
fausse_racine() { # fausse_racine <chemin>
	local r="$1"
	rm -rf "$r"; mkdir -p "$r"
	local f
	for f in "${TROIS[@]}"; do
		mkdir -p "$r/$(dirname "$f")"
		printf 'reglage de demo\n' > "$r/$f"
	done
	printf '[Seat:*]\nuser-session=xfce\ngreeter-hide-users=false\nallow-guest=true\n' \
		> "$r/etc/lightdm/lightdm.conf.d/50-lexos.conf"
}

joue() { # joue <racine> <contenu-de-cmdline>
	local r="$1"
	printf '%s\n' "$2" > "$BANC/cmdline"
	LEXOS_RACINE="$r" LEXOS_CMDLINE="$BANC/cmdline" sh "$GARDE" 2>&1
}

# =============================================================================
titre "1. En session DÉMO — on ne touche à rien"
# =============================================================================
#  Le piège symétrique de celui d'Alex : un garde-fou zélé qui effacerait
#  l'ouverture automatique SUR LA CLÉ casserait la démo pour tout le monde.
R="$BANC/live"
fausse_racine "$R"
SORTIE="$(joue "$R" "BOOT_IMAGE=/live/vmlinuz boot=live components quiet")"
RC=$?
[ "$RC" = "0" ] && ok "en live, le garde-fou sort proprement (code 0)" \
                || non "en live, code de sortie $RC"

MANQUANTS=0
for f in "${TROIS[@]}"; do
	[ -e "$R/$f" ] || { non "en live, « $f » a été effacé — la démo est cassée"; MANQUANTS=1; }
done
[ "$MANQUANTS" -eq 0 ] && ok "en live, les trois réglages de démo sont TOUJOURS là"

[ ! -e "$R/etc/lightdm/lightdm.conf.d/70-lexos-installe.conf" ] \
	&& ok "en live, aucun « allow-guest=false » n'est posé — la session invité reste offerte" \
	|| non "en live, 70-lexos-installe.conf a été écrit : la session invité de la démo est coupée"

# =============================================================================
titre "2. Sur un système INSTALLÉ — les trois disparaissent"
# =============================================================================
R="$BANC/installe"
fausse_racine "$R"
SORTIE="$(joue "$R" "BOOT_IMAGE=/vmlinuz root=/dev/sda2 ro quiet")"
RC=$?
[ "$RC" = "0" ] && ok "sur système installé, le garde-fou sort proprement (code 0)" \
                || non "sur système installé, code de sortie $RC"

RESTANTS=0
for f in "${TROIS[@]}"; do
	[ -e "$R/$f" ] && { non "« $f » est RESTÉ — c'est le bogue du 12 août"; RESTANTS=1; }
done
[ "$RESTANTS" -eq 0 ] && ok "les trois réglages de démo ont bien disparu"

#  CELUI-CI EST LE PLUS IMPORTANT DES TROIS : c'est lui qui ouvrait la session
#  de démo et empêchait d'atteindre l'écran où choisir son compte.
[ ! -e "$R/etc/lightdm/lightdm.conf.d/60-lexos-autologin.conf" ] \
	&& ok "l'ouverture automatique sur « lex » est retirée — on atteint enfin l'écran de connexion" \
	|| non "60-lexos-autologin.conf est resté : la machine installée rouvrira la session de démo"

grep -q "réglages de démo retirés" <<< "$SORTIE" \
	&& ok "le garde-fou DIT ce qu'il a retiré, au lieu d'agir en silence" \
	|| non "rien n'a été annoncé dans le journal : « $SORTIE »"

# =============================================================================
titre "3. La session invité est coupée, sans casser 50-lexos.conf"
# =============================================================================
[ -e "$R/etc/lightdm/lightdm.conf.d/70-lexos-installe.conf" ] \
	&& ok "70-lexos-installe.conf est posé sur le système installé" \
	|| non "aucun fichier ne coupe la session invité : elle reste offerte sur la machine d'Alex"

grep -q 'allow-guest=false' "$R/etc/lightdm/lightdm.conf.d/70-lexos-installe.conf" 2>/dev/null \
	&& ok "…et il porte bien « allow-guest=false »" \
	|| non "le fichier existe mais ne coupe pas la session invité"

#  Il doit passer APRÈS 50-lexos.conf dans l'ordre alphabétique, sinon
#  LightDM lirait notre « false » en premier et le « true » de 50 gagnerait.
PREMIER="$(ls "$R/etc/lightdm/lightdm.conf.d/" | sort | head -1)"
[ "$PREMIER" = "50-lexos.conf" ] \
	&& ok "70-… passe bien APRÈS 50-lexos.conf — c'est notre valeur qui gagne" \
	|| non "l'ordre de lecture est mauvais : « $PREMIER » vient en premier"

grep -q 'greeter-hide-users=false' "$R/etc/lightdm/lightdm.conf.d/50-lexos.conf" \
	&& ok "50-lexos.conf est intact — la liste des comptes reste visible" \
	|| non "50-lexos.conf a été abîmé : le compte de l'utilisateur pourrait devenir invisible"

# =============================================================================
titre "4. Deuxième démarrage installé — il se relance sans erreur"
# =============================================================================
#  C'est le piège que le fichier .service documente : l'unité précédente
#  portait un ConditionPathExists et ne se relançait donc PLUS JAMAIS après
#  le premier démarrage. Ce banc garde ce comportement pour toujours.
SORTIE2="$(joue "$R" "BOOT_IMAGE=/vmlinuz root=/dev/sda2 ro quiet")"
RC2=$?
[ "$RC2" = "0" ] \
	&& ok "relancé sur un système déjà nettoyé, il sort proprement (code 0)" \
	|| non "au deuxième passage, code de sortie $RC2 — l'unité tomberait en échec à chaque démarrage"

grep -q "réglages de démo retirés" <<< "$SORTIE2" \
	&& non "au deuxième passage il annonce encore des retraits alors qu'il n'y avait plus rien" \
	|| ok "au deuxième passage, il n'annonce rien : il n'y avait plus rien à faire"

# =============================================================================
titre "5. Cohérence hook 0400 ↔ garde-fou (sans rien exécuter)"
# =============================================================================
#  Le contrôle qui rattrapera le jour où quelqu'un renomme un fichier dans le
#  hook 0400 sans le reporter dans le garde-fou. Il se fait par simple lecture
#  des deux fichiers du dépôt.
for f in "${TROIS[@]}"; do
	if grep -qF "/$f" "$GARDE" && grep -qF "/$f" "$HOOK"; then
		ok "« /$f » est écrit par le hook 0400 ET effacé par le garde-fou"
	else
		non "« /$f » n'est pas dans les deux fichiers — un réglage de démo resterait sur la machine"
	fi
done

# =============================================================================
titre "6. La construction ÉCHOUE si le garde-fou disparaît"
# =============================================================================
#  Avant ce chantier, le hook 0400 disait « !! garde-fou démo non activé » et
#  CONTINUAIT : l'ISO sortait avec le bogue. On vérifie qu'il n'y a plus de
#  « || true » ni de « || echo » dans cette zone, et qu'un exit 1 la garde.
ZONE="$(grep -n 'demo-guard\|demo_guard' "$HOOK" | grep -c '|| true\|&& echo.*|| echo')"
[ "$ZONE" -eq 0 ] \
	&& ok "plus aucun « || true » ni « ... || echo » sur le garde-fou dans le hook 0400" \
	|| non "$ZONE ligne(s) tolèrent encore l'absence du garde-fou en silence"

grep -q 'demo-guard ABSENT' "$HOOK" \
	&& ok "le hook 0400 arrête la construction si le garde-fou manque" \
	|| non "rien n'arrête la construction quand /usr/lib/lexos/demo-guard est absent"

grep -q 'refuse de s.activer' "$HOOK" \
	&& ok "…et aussi si le service refuse de s'activer" \
	|| non "un service qui refuse de s'activer passerait encore inaperçu"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
