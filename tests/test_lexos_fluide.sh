#!/usr/bin/env bash
# =============================================================================
#  lexos-fluide — rendre la machine plus fluide sans casser autre chose
# =============================================================================
#  Alex a déposé lexos-fluide.sh sans consigne, comme lexos-applis. Comme lui,
#  il a été ÉPROUVÉ EN LE FAISANT TOURNER avant d'être installé — et comme lui,
#  l'analyse statique n'avait rien à dire du tout (le mot exact est évité ici :
#  une ligne de commentaire qui commence par ce nom-là est lue comme une
#  DIRECTIVE par l'outil, et il refuse alors d'analyser le fichier — mesuré).
#  Cinq défauts, tous constatés à l'exécution, aucun déduit de la lecture.
#
#  ═══ POURQUOI UN FAUX systemctl ═══
#  Un banc qui désactiverait pour de vrai rpcbind sur le coureur serait un
#  banc qu'on n'ose plus lancer. Le faux systemctl tient un état sur disque,
#  note ce qu'on lui demande, et sait échouer sur commande — c'est ce dernier
#  point qui compte : les deux défauts les plus graves ne se voient QUE
#  lorsque quelque chose refuse.
#
#  ═══ ET POURQUOI DE FAUSSES MACHINES ═══
#  Le vrai sujet n'est pas le T460 d'Alex, c'est son Alienware : le script
#  d'origine y aurait coupé nvidia-persistenced sur une machine qui A une
#  RTX 5060, parce que « pas de carte NVIDIA » était écrit en commentaire et
#  vérifié nulle part. Les variables LEXOS_FLUIDE_SYS/PROC/FSTAB/DEV
#  permettent de poser cette machine-là devant l'outil.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-fluide"

# =============================================================================
#  CE BANC A BESOIN DES DROITS — ET IL EST ROUGE SANS EUX, PAS VERT
# =============================================================================
#  MESURÉ, ET C'EST MOI QUI ME SUIS FAIT AVOIR. Ce banc était vert sur la
#  machine de développement (root) et ROUGE sur le coureur GitHub (l'usager
#  « runner ») : 15 réussis, 14 échoués. L'outil refuse d'agir sans les
#  droits — c'est son travail — donc aucune des mesures qui comptent ne se
#  faisait. Vert ici, rouge là-bas : le même piège que la locale, une passe
#  de plus dans le même environnement ne l'aurait jamais montré.
#
#  ET DEUX CONTRÔLES ÉTAIENT VERTS SUR ZÉRO : « l'annulation remet bien les
#  0 services ». Un contrôle qui se satisfait de rien est pire qu'un rouge.
#  Ils exigent maintenant qu'il y ait eu quelque chose à remettre.
#
#  On se relance donc sous sudo. Le faux systemctl et LEXOS_FLUIDE_ETC font
#  que RIEN du vrai système n'est touché : tout vit dans un dossier
#  temporaire. Si sudo n'est pas là, on le DIT (« non mesuré ») au lieu de
#  rendre des verts qui n'ont rien éprouvé — et LEXOS_FLUIDE_EXIGER_MESURE=1
#  (posé par la CI) en fait une erreur franche.
if [ "$(id -u)" -ne 0 ]; then
	if sudo -n true 2>/dev/null; then
		exec sudo -n --preserve-env=LEXOS_FLUIDE_EXIGER_MESURE bash "$0" "$@"
	fi
	printf '\n\033[90m— lexos-fluide : NON MESURÉ (ni root, ni sudo sans mot de passe)\033[0m\n'
	printf '\033[90m  L'"'"'outil refuse d'"'"'agir sans les droits : les contrôles ne prouveraient rien.\033[0m\n'
	if [ "${LEXOS_FLUIDE_EXIGER_MESURE:-0}" = "1" ]; then
		printf '\033[31m  LEXOS_FLUIDE_EXIGER_MESURE=1 : c'"'"'est une erreur.\033[0m\n'
		exit 1
	fi
	exit 0
fi

BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; NONMESURE=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
gris() { printf '  \033[90m—\033[0m %s\n' "$1"; NONMESURE=$((NONMESURE+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-fluide introuvable ou non exécutable"; exit 1; }

# --- le faux systemctl ------------------------------------------------------
FAUX="$BANC/bin"; mkdir -p "$FAUX"
cat > "$FAUX/systemctl" <<'SYSD'
#!/bin/sh
ACT="$SYSD_ETAT"
case "$1" in
  is-enabled) grep -qx "$2" "$ACT" && { echo enabled; exit 0; }; echo disabled; exit 1 ;;
  cat|list-unit-files) [ "$SYSD_ZRAM_ABSENT" = "1" ] && exit 1; exit 0 ;;
  disable) shift; [ "$1" = "--now" ] && shift
     for u in "$@"; do
        [ "$u" = "$SYSD_ECHEC" ] && { echo "Failed to disable $u" >&2; exit 1; }
        grep -vx "$u" "$ACT" > "$ACT.n" 2>/dev/null || true; mv "$ACT.n" "$ACT" 2>/dev/null || true
        echo "DISABLE $u" >> "$SYSD_JOURNAL"
     done; exit 0 ;;
  enable) shift; [ "$1" = "--now" ] && shift
     for u in "$@"; do
        [ "$u" = "$SYSD_ECHEC" ] && { echo "Failed to enable $u" >&2; exit 1; }
        echo "$u" >> "$ACT"; echo "ENABLE $u" >> "$SYSD_JOURNAL"
     done; exit 0 ;;
esac
exit 0
SYSD
chmod +x "$FAUX/systemctl"
ln -sf "$(command -v zramctl || echo /bin/true)" "$FAUX/zramctl" 2>/dev/null || true

#  Une machine ordinaire : 8 Go, rien de spécial.
machine() { # machine <ram_mo> [nvidia] [nfs] [modem]
	local M="${BANC:?}/machine"; rm -rf "$M"
	mkdir -p "$M/sys/bus/pci/devices" "$M/sys/class/net" "$M/sys/block" "$M/proc" "$M/dev"
	printf 'MemTotal:       %d kB\nSwapTotal:             0 kB\n' "$(( $1 * 1024 ))" > "$M/proc/meminfo"
	: > "$M/fstab"
	if [ "${2:-}" = "nvidia" ] || [ "${3:-}" = "nvidia" ] || [ "${4:-}" = "nvidia" ]; then
		mkdir -p "$M/sys/bus/pci/devices/0000:01:00.0"
		echo 0x10de > "$M/sys/bus/pci/devices/0000:01:00.0/vendor"
	fi
	for a in "${@:2}"; do
		[ "$a" = "nfs" ]   && printf 'serveur:/export /mnt/nas nfs4 defaults 0 0\n' > "$M/fstab"
		[ "$a" = "modem" ] && mkdir -p "$M/sys/class/net/wwan0"
	done
	export LEXOS_FLUIDE_SYS="$M/sys" LEXOS_FLUIDE_PROC="$M/proc"
	export LEXOS_FLUIDE_FSTAB="$M/fstab" LEXOS_FLUIDE_DEV="$M/dev"
}

TOUS="nvidia-persistenced.service nvidia-powerd.service NetworkManager-wait-online.service
nfs-client.target rpcbind.service rpcbind.socket nfs-blkmap.service ModemManager.service
cups-browsed.service"

scene() { # scene — remet un systemd neuf, tous services actifs, /etc/lexos vide
	export SYSD_ETAT="$BANC/actifs" SYSD_JOURNAL="$BANC/journal"
	export SYSD_ECHEC="${1:-}" SYSD_ZRAM_ABSENT="${2:-0}"
	printf '%s\n' $TOUS > "$SYSD_ETAT"
	: > "$SYSD_JOURNAL"
	#  « ${BANC:?} » ET NON « $BANC » : si la variable était vide, la
	#  ligne deviendrait « rm -rf /etc ». Le banc tourne en root dans ce
	#  dépôt. La forme « :? » fait échouer la commande plutôt que de la
	#  laisser viser la racine.
	rm -rf "${BANC:?}/etc"; mkdir -p "$BANC/etc"
	export LEXOS_FLUIDE_ETC="$BANC/etc"
}

lancer() { NO_COLOR=1 PATH="$FAUX:$PATH" sh "$OUTIL" "$@" 2>&1; }

# =============================================================================
titre "1. Relancer l'outil ne détruit PLUS l'annulation"
# =============================================================================
#  LE DÉFAUT D'ORIGINE, ET LE PLUS GRAVE. Le fichier de restauration était
#  remis à zéro à chaque passage : au second, les services étaient déjà
#  coupés, donc plus rien à enregistrer. « --annuler » répondait « ✓ Tout est
#  revenu comme avant » et ne remettait RIEN. Il se déclenchait au geste le
#  plus banal qui soit : relancer une commande.
machine 8192; scene
lancer >/dev/null
N1="$(grep -c '^service ' "$BANC/etc/fluide.etat" 2>/dev/null || echo 0)"
lancer >/dev/null
N2="$(grep -c '^service ' "$BANC/etc/fluide.etat" 2>/dev/null || echo 0)"
[ "$N1" -gt 0 ] && ok "un passage enregistre $N1 service(s) pour l'annulation" \
	|| non "le premier passage n'enregistre rien"
#  « $N2 = $N1 » ÉTAIT VRAI QUAND LES DEUX VALAIENT ZÉRO, et le contrôle
#  passait donc sur un banc qui n'avait rien fait. On exige d'abord qu'il y
#  ait eu quelque chose — sinon la comparaison ne compare rien.
if [ "$N1" -gt 0 ] && [ "$N2" = "$N1" ]; then
	ok "…et un second passage les conserve tous ($N2)"
else
	non "le second passage a ramené l'enregistrement de $N1 à $N2"
fi

: > "$SYSD_JOURNAL"
S="$(lancer --annuler)"
REMIS="$(grep -c '^ENABLE ' "$SYSD_JOURNAL" || true)"
if [ "$N1" -gt 0 ] && [ "$REMIS" -ge "$N1" ]; then
	ok "après DEUX passages, l'annulation remet bien les $N1 services"
else
	non "l'annulation n'a remis que $REMIS service(s) sur $N1 :\n$S"
fi

# =============================================================================
titre "2. Un service qui refuse est NOMMÉ, pas passé sous silence"
# =============================================================================
machine 8192; scene "rpcbind.service"
S="$(lancer)"; CODE=$?
grep -q "rpcbind.service" <<< "$S" \
	&& ok "le service récalcitrant apparaît dans la sortie" \
	|| non "rpcbind.service a échoué sans un mot :\n$S"
grep -qi "n'a PAS pu être désactivé" <<< "$S" \
	&& ok "…et c'est dit comme un échec" \
	|| non "l'échec n'est pas annoncé comme tel"
[ "$CODE" -ne 0 ] \
	&& ok "…et le code de sortie le dit aussi" \
	|| non "code de sortie 0 alors qu'un service n'a pas pu être désactivé"
#  ET LES AUTRES SONT QUAND MÊME TRAITÉS : un échec n'emporte pas la suite.
[ "$(grep -c '^DISABLE ' "$SYSD_JOURNAL" || true)" -ge 6 ] \
	&& ok "…et les autres services ont quand même été traités" \
	|| non "un seul refus a emporté le reste du travail"

# =============================================================================
titre "3. La mémoire compressée qui échoue n'emporte plus les services"
# =============================================================================
#  Mesuré sur l'original : « set -e » arrêtait tout après avoir écrit
#  zram.conf. Aucun service traité, et pour seul message celui de systemd,
#  en anglais.
machine 8192; scene "lexos-zram.service"
S="$(lancer)"
grep -qi "mémoire compressée" <<< "$S" \
	&& ok "l'échec de la mémoire compressée est annoncé en français" \
	|| non "rien n'est dit sur l'échec de zram :\n$S"
[ "$(grep -c '^DISABLE ' "$SYSD_JOURNAL" || true)" -ge 6 ] \
	&& ok "…et les services sont traités malgré tout" \
	|| non "l'échec de zram a emporté toute la suite (le défaut d'origine)"

# =============================================================================
titre "4. Un réglage zram existant est sauvegardé, et rendu tel quel"
# =============================================================================
machine 8192; scene
printf '# LexOS Boost\nTAILLE_MO=2048\nALGO=lzo\n' > "$BANC/etc/zram.conf"
lancer >/dev/null
[ -r "$BANC/etc/zram.conf.avant-fluide" ] \
	&& ok "le réglage d'avant est sauvegardé avant d'être écrasé" \
	|| non "aucune sauvegarde : le réglage d'avant est perdu"
#  SECOND PASSAGE : la sauvegarde ne doit PAS être refaite sur notre propre
#  écriture. C'est un défaut que j'ai introduit puis mesuré dans MA version.
lancer >/dev/null
grep -q "TAILLE_MO=2048" "$BANC/etc/zram.conf.avant-fluide" \
	&& ok "…et un second passage ne remplace pas cette sauvegarde par la sienne" \
	|| non "la sauvegarde a été refaite sur le réglage de l'outil lui-même"
lancer --annuler >/dev/null
if [ -r "$BANC/etc/zram.conf" ] && grep -q "TAILLE_MO=2048" "$BANC/etc/zram.conf"; then
	ok "après annulation, le réglage d'avant est exactement revenu"
else
	non "le réglage d'avant n'est pas revenu : $(cat "$BANC/etc/zram.conf" 2>/dev/null || echo SUPPRIMÉ)"
fi

#  ET QUAND IL N'Y AVAIT RIEN, ON NE LAISSE RIEN.
machine 8192; scene
lancer >/dev/null; lancer --annuler >/dev/null
[ ! -e "$BANC/etc/zram.conf" ] \
	&& ok "et si rien n'existait avant, l'annulation ne laisse rien derrière" \
	|| non "zram.conf est resté alors qu'il n'existait pas avant"

# =============================================================================
titre "5. Sur l'Alienware, on NE touche PAS à ce qui sert"
# =============================================================================
#  LE CŒUR DE L'AFFAIRE. « pas de carte NVIDIA », « aucun partage NFS »,
#  « aucun modem » : vrai sur le T460, écrit en commentaire, vérifié nulle
#  part. Le même script sur l'Alienware coupait nvidia-persistenced.
machine 32768 nvidia nfs modem; scene
S="$(lancer)"
for U in nvidia-persistenced.service nvidia-powerd.service; do
	grep -q "gardé : $U" <<< "$S" \
		&& ok "gardé sur une machine à carte NVIDIA : $U" \
		|| non "$U serait désactivé sur une machine qui A une carte NVIDIA :\n$S"
done
grep -q "gardé : rpcbind.service" <<< "$S" \
	&& ok "gardé quand un partage NFS est déclaré : rpcbind.service" \
	|| non "rpcbind serait coupé alors qu'un partage NFS est monté"
grep -q "gardé : ModemManager.service" <<< "$S" \
	&& ok "gardé quand un modem est présent : ModemManager.service" \
	|| non "ModemManager serait coupé alors qu'un modem est présent"
#  CHAQUE ÉPARGNE DIT POURQUOI — « gardé » tout court n'apprend rien.
MUETS="$(grep -c 'gardé : [^ ]* *$' <<< "$S" || true)"
[ "$MUETS" = "0" ] \
	&& ok "…et chaque service gardé dit POURQUOI il l'est" \
	|| non "$MUETS service(s) gardés sans raison énoncée"
grep -q "16 Go ou plus" <<< "$S" \
	&& ok "zram est refusée à 32 Go — la règle de LexOS Boost, pas une autre" \
	|| non "zram serait posée sur une machine de 32 Go :\n$S"

# =============================================================================
titre "6. La simulation ne touche à rien"
# =============================================================================
machine 8192; scene
S="$(lancer --simulation)"
[ "$(grep -c '^DISABLE ' "$SYSD_JOURNAL" || true)" = "0" ] \
	&& ok "aucun service n'est touché en simulation" \
	|| non "la simulation a désactivé des services"
[ ! -e "$BANC/etc/zram.conf" ] && [ ! -e "$BANC/etc/fluide.etat" ] \
	&& ok "…et rien n'est écrit sur le disque" \
	|| non "la simulation a écrit dans $BANC/etc"
grep -qi "serait désactivé" <<< "$S" \
	&& ok "…mais elle dit ce qu'elle ferait" \
	|| non "la simulation ne montre rien :\n$S"

# =============================================================================
titre "7. Annuler sans rien à annuler, et les arguments inconnus"
# =============================================================================
machine 8192; scene
S="$(lancer --annuler)"; CODE=$?
grep -qi "rien à annuler" <<< "$S" \
	&& ok "annuler sans état enregistré est refusé clairement" \
	|| non "« --annuler » sans état ne dit rien de clair :\n$S"
[ "$CODE" -ne 0 ] && ok "…avec un code de sortie non nul" \
	|| non "code 0 alors qu'il n'y avait rien à annuler"

S="$(lancer --nawak)"
grep -qi "argument inconnu" <<< "$S" \
	&& ok "un argument inconnu est refusé" \
	|| non "« --nawak » passe sans un mot"

S="$(lancer --etat)"
grep -qi "carte NVIDIA" <<< "$S" \
	&& ok "« --etat » dit ce que l'outil voit de la machine" \
	|| non "« --etat » n'affiche pas l'état du matériel"

# =============================================================================
titre "8. Sans les droits, il refuse d'agir"
# =============================================================================
if [ "$(id -u)" -ne 0 ]; then
	S="$(lancer)"; CODE=$?
	grep -qi "sudo" <<< "$S" && [ "$CODE" -ne 0 ] \
		&& ok "sans les droits, il refuse et dit quoi faire" \
		|| non "il ne refuse pas proprement sans les droits :\n$S"
elif command -v setpriv >/dev/null 2>&1; then
	#  ═══ L'USAGER SANS DROITS DOIT D'ABORD POUVOIR LIRE LE SCRIPT ═══
	#  Mesuré sur le coureur GitHub, et c'est le rouge de la CI 600 :
	#      sh: 0: cannot open …/lexos-fluide: Permission denied
	#  Le depot y vit sous /home/runner/work, que « nobody » n'a pas le
	#  droit de traverser. « sh » echouait donc AVANT que l'outil ne dise
	#  quoi que ce soit, et le controle concluait « il ne refuse pas
	#  proprement » — un rouge qui parlait des permissions du coureur et
	#  pas du tout de l'outil. Le pire genre de rouge : il accuse le bon
	#  code d'un defaut qu'il n'a pas.
	#
	#  On recopie donc l'outil dans un endroit que tout le monde peut
	#  lire, et on mesure LA. Et si malgre tout l'ouverture echoue, on dit
	#  « non mesure » plutot que de rendre un verdict sur rien.
	OUVERT="$BANC/ouvert"
	mkdir -p "$OUVERT"
	chmod 755 "$BANC" "$OUVERT"
	cp "$OUTIL" "$OUVERT/lexos-fluide" && chmod 755 "$OUVERT/lexos-fluide"
	S="$(NO_COLOR=1 setpriv --reuid=65534 --regid=65534 --clear-groups \
		sh "$OUVERT/lexos-fluide" 2>&1)"
	CODE=$?
	if grep -qiE "permission denied|cannot open" <<< "$S"; then
		gris "l'usager sans droits ne peut pas lire le script : refus NON mesuré"
	elif grep -qi "sudo" <<< "$S" && [ "$CODE" -ne 0 ]; then
		ok "sans les droits, il refuse et dit quoi faire"
	else
		non "il ne refuse pas proprement sans les droits :\n$S"
	fi
else
	gris "banc lancé en root et setpriv absent : le refus sans droits n'est PAS mesuré"
fi

# =============================================================================
titre "9. L'outil est joignable comme les autres"
# =============================================================================
D="$RACINE/config/includes.chroot/usr/bin/lexos"
grep -q 'fluide' "$D" \
	&& ok "« lexos fluide » est branché dans le dispatcheur" \
	|| non "le dispatcheur ne connaît pas « fluide »"
grep -q 'lexos-fluide' "$RACINE/verifier-parametres.sh" \
	&& ok "…et il est déclaré AUTONOME (contrôle 16)" \
	|| non "lexos-fluide n'est pas déclaré dans verifier-parametres.sh"

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' \
	"$REUSSIS" "$ECHOUES" "$NONMESURE"

#  ═══ EN CI, RIEN NE RESTE « NON MESURÉ » ═══
#  Une ligne grise dans un journal de deux cents étapes ne se voit pas. La
#  CI pose LEXOS_FLUIDE_EXIGER_MESURE=1 : là, un contrôle qui n'a pas pu
#  mesurer est un échec, au même titre qu'un rouge. Ailleurs — sur une
#  machine sans setpriv, sans sudo — il reste gris et honnête.
if [ "$ECHOUES" -gt 0 ]; then
	exit 1
fi
if [ "${LEXOS_FLUIDE_EXIGER_MESURE:-0}" = "1" ] && [ "$NONMESURE" -gt 0 ]; then
	printf '\033[31m  LEXOS_FLUIDE_EXIGER_MESURE=1 : %d contrôle(s) non mesuré(s), c'"'"'est une erreur.\033[0m\n' \
		"$NONMESURE"
	exit 1
fi
exit 0
