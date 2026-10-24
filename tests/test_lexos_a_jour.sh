#!/usr/bin/env bash
# =============================================================================
#  Éprouver le hook 0257 — Mesa et micrologiciels depuis trixie-backports
# =============================================================================
#  Le hook tourne dans le chroot de live-build, en root, et son apt peut
#  RETIRER des paquets : on ne le lance donc jamais pour de vrai ici. Ce banc
#  rejoue le fichier LIVRÉ (pas une copie) avec de faux apt-get, apt-cache,
#  dpkg et dpkg-query devant le PATH, et des chemins surchargés
#  (LEXOS_BUILD_CONF, LEXOS_APT_ETC, LEXOS_A_JOUR_JOURNAL).
#
#  CE QUE LES RELECTURES DU HOOK ONT TROUVÉ, ET QUE CE BANC TIENT FERMÉ.
#  Chaque défaut a d'abord été reproduit avec le VRAI apt (2.8.3) et le VRAI
#  dpkg (1.22.6) sur une racine neuve, puis la correction mesurée de même ;
#  les faux d'ici ne prouvent pas le comportement d'apt, ils vérifient que
#  le hook lui pose la bonne question et lit sa réponse comme lui la donne :
#    · apt -y SANS --no-remove retirait le Mesa 32 bits et Steam quand
#      backports n'avait que l'amd64, rendait 0, et effaçait le journal ;
#    · « paquet/trixie-backports » trié par « apt-cache madison » exigeait
#      une version de backports PLUS ANCIENNE que l'installée : refus, et
#      plus rien ne montait ;
#    · « Mesa : AVANT -> APRÈS » collait les versions amd64 et i386 ;
#    · Mesa amd64 monté seul, sans épingle : le Mesa 32 bits de « lexos
#      logitheque famille jeux » ne pouvait plus s'installer ;
#    · la garde i386 et l'épingle ne regardaient que src:mesa : une
#      bibliothèque « Multi-Arch: same » d'une autre source (libdrm2), tirée
#      vers backports par Mesa, rendait encore « famille jeux » impossible ;
#    · « rien de plus récent dans backports » écrit alors que la garde
#      venait de retenir un Mesa plus récent ;
#    · « remontés : N » comptait les noms demandés, pas ce qui avait changé ;
#    · l'épingle prenait la source d'AVANT : une dépendance dont backports a
#      renommé la source restait hors épingle, et « famille jeux » échouait ;
#    · une dépendance devenue « Multi-Arch: same » (« libfoo1 » avant,
#      « libfoo1:amd64 » après) sortait en faux « RETIRÉ » / « a DISPARU ».
#
#  LE FAUX apt-cache RÉPOND COMME LE VRAI. Pour un nom inconnu dans une
#  architecture, le vrai apt 2.8.3 ne rend RIEN (mesuré) : ce faux-là aussi.
#  Un faux qui rendait « Candidate: (none) » à la place laissait une moitié
#  de la garde sans jamais servir — et le banc vert.
#
#  LES MUTATIONS (section 14) REJOUENT TOUT LE BANC sur un hook muté et
#  exigent qu'un contrôle NOMMÉ rougisse : c'est le corps du banc qui doit
#  avoir des dents, pas une copie de ses contrôles.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${LEXOS_A_JOUR_HOOK:-$RACINE/config/hooks/normal/0257-lexos-a-jour.hook.chroot}"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -f "$HOOK" ] || { echo "hook 0257 introuvable : $HOOK"; exit 1; }

FAUXBIN="$BANC/bin"
CTRL="$BANC/ctrl"
APT_ETC="$BANC/etc-apt"
CONF="$BANC/build.conf"
JOURNAL="$BANC/lexos-a-jour.log"
EPINGLE="$APT_ETC/preferences.d/lexos-a-jour-backports.pref"

T=25.0.7-2+deb13u1
B=25.2.4-1~bpo13+1
DRM_T=2.4.124-2
DRM_B=2.4.125-1~bpo13+1

# --- Les faux -----------------------------------------------------------------
#  $CTRL/status     : « paquet:arch source version », ce qui est installé ;
#  $CTRL/candidats  : « paquet:arch version », ce qu'apt prendrait avec -t
#                     (« (none) » : un nom connu sans candidat ; un nom
#                     absent du fichier n'existe pas pour apt) ;
#  $CTRL/tire       : « demandeur dep:arch source version » — quand le
#                     demandeur monte, apt tire aussi cette dépendance ;
#  $CTRL/multiarch  : « nom valeur » — « Multi-Arch » d'un nom (same sinon) ;
#  $CTRL/foreign    : la sortie de dpkg --print-foreign-architectures ;
#  $CTRL/refuse     : un nom par ligne — une transaction (ou sa simulation)
#                     qui en contient un est refusée comme apt le fait sous
#                     --no-remove ;
#  $CTRL/retire     : un nom par ligne — retiré d'une transaction « réussie »
#                     (ce qu'apt ne fait pas sous --no-remove : sert à
#                     vérifier que le hook le VERRAIT quand même) ;
#  $CTRL/crochets   : un nom par ligne — sa ligne « Inst » de simulation
#                     finit par « [] », comme celle des noms Mesa ;
#  $CTRL/inst       : les lignes « Inst » que la simulation a rendues ;
#  $CTRL/appels     : chaque appel, avec la valeur de LC_ALL.
#  Le faux compare les noms SANS « :amd64 » (l'architecture native), comme
#  dpkg remplace « libfoo1 » par « libfoo1:amd64 » quand la nouvelle version
#  est « Multi-Arch: same » ; et une version montée prend la source de son
#  plan (une source renommée dans backports).
pose_faux_outils() {
	mkdir -p "$FAUXBIN" "$CTRL"
	: > "$CTRL/appels"
	cat > "$FAUXBIN/apt-get" <<'EOF'
#!/bin/sh
C="$FAUX_CTRL"
echo "apt-get $* |LC_ALL=${LC_ALL:-}" >> "$C/appels"
SIM=""
if [ "$1" = "-s" ]; then SIM=1; shift; fi
[ "$1" = "install" ] || exit 0
shift
NOMS=""
while [ $# -gt 0 ]; do
	case "$1" in
		-t) shift ;;
		-*) ;;
		*) NOMS="$NOMS $1" ;;
	esac
	shift
done
[ -n "$NOMS" ] || exit 0
for n in $NOMS; do
	if [ -f "$C/refuse" ] && grep -qxF "$n" "$C/refuse"; then
		echo "The following packages will be REMOVED:"
		echo "  appli-qui-gene"
		echo "E: Packages need to be removed but remove is disabled."
		exit 100
	fi
done
#  Le plan : « nom source version » de ce qui monte ou arrive.
: > "$C/plan"
for n in $NOMS; do
	c="$(awk -v p="$n" '$1 == p { print $2 }' "$C/candidats" 2>/dev/null)"
	l="$(awk -v p="$n" '$1 == p { print $2, $3 }' "$C/status")"
	if [ -n "$c" ] && [ "$c" != "(none)" ] && [ -n "$l" ] && [ "$c" != "${l#* }" ]; then
		echo "$n ${l% *} $c" >> "$C/plan"
	fi
done
if [ -f "$C/tire" ]; then
	awk 'NR == FNR { monte[$1] = 1; next } ($1 in monte) { print $2, $3, $4 }' "$C/plan" "$C/tire" \
		| sort -u | while read -r d s v; do
			cur="$(awk -v p="${d%:amd64}" '{ m = $1; sub(/:amd64$/, "", m) } m == p { print $3 }' "$C/status")"
			[ "$cur" = "$v" ] || echo "$d $s $v" >> "$C/plan"
		done
fi
MONTES=0; NEUFS=0
while read -r n s v; do
	if awk -v p="${n%:amd64}" '{ m = $1; sub(/:amd64$/, "", m) } m == p { t = 1 } END { exit !t }' "$C/status"; then MONTES=$((MONTES + 1)); else NEUFS=$((NEUFS + 1)); fi
done < "$C/plan"
if [ -n "$SIM" ]; then
	#  La forme du vrai apt -s (LC_ALL=C) : nom natif ou « all » sans
	#  suffixe, nom étranger qualifié ; un libellé d'archive AVEC une
	#  espace, et parfois un « [] » après la parenthèse — sur les noms Mesa
	#  et ceux de $C/crochets (le vrai apt en met aussi sur une dépendance).
	: > "$C/inst"
	while read -r n s v; do
		case "$n" in
			*:amd64) nom="${n%:amd64}"; a=amd64 ;;
			*:*)     nom="$n"; a="${n##*:}" ;;
			*)       nom="$n"; a=all ;;
		esac
		cur="$(awk -v p="$nom" '{ m = $1; sub(/:amd64$/, "", m) } m == p { print $3 }' "$C/status")"
		suite=""
		case "$nom" in *mesa*) suite=" []" ;; esac
		if [ -f "$C/crochets" ] && grep -qxF "$nom" "$C/crochets"; then suite=" []"; fi
		echo "Inst $nom ${cur:+[$cur] }($v Faux Backports:stable-backports [$a])$suite" | tee -a "$C/inst"
	done < "$C/plan"
	echo "$MONTES upgraded, $NEUFS newly installed, 0 to remove and 0 not upgraded."
	exit 0
fi
awk 'function cle(n) { sub(/:amd64$/, "", n); return n }
     NR == FNR { k = cle($1); nv[k] = $3; ns[k] = $2; nn[k] = $1; next }
     (cle($1) in nv) { k = cle($1); $1 = nn[k]; $2 = ns[k]; $3 = nv[k]; vu[k] = 1 }
     { print }
     END { for (p in nv) if (!(p in vu)) print nn[p], ns[p], nv[p] }' "$C/plan" "$C/status" > "$C/status.n"
mv "$C/status.n" "$C/status"
if [ -f "$C/retire" ]; then
	awk 'NR == FNR { r[$1] = 1; next } !($1 in r)' "$C/retire" "$C/status" > "$C/status.n"
	mv "$C/status.n" "$C/status"
fi
echo "$MONTES upgraded, $NEUFS newly installed, 0 to remove and 0 not upgraded."
exit 0
EOF
	cat > "$FAUXBIN/apt-cache" <<'EOF'
#!/bin/sh
C="$FAUX_CTRL"
echo "apt-cache $* |LC_ALL=${LC_ALL:-}" >> "$C/appels"
eval "q=\${$#}"
case "$1" in
	policy)
		c="$(awk -v p="$q" '$1 == p { print $2 }' "$C/candidats" 2>/dev/null)"
		#  Comme le vrai apt 2.8.3 : un nom inconnu ne rend RIEN.
		[ -n "$c" ] || exit 0
		echo "$q:"
		echo "  Installed: (none)"
		echo "  Candidate: $c"
		echo "  Version table:"
		;;
	show)
		n="${q%%=*}"; v="${q#*=}"
		c="$(awk -v p="$n" '$1 == p { print $2 }' "$C/candidats" 2>/dev/null)"
		if [ -z "$c" ] || [ "$c" != "$v" ]; then echo "E: No packages found" >&2; exit 100; fi
		m="$(awk -v p="${n%:*}" '$1 == p { print $2 }' "$C/multiarch" 2>/dev/null)"
		echo "Package: ${n%:*}"
		echo "Version: $v"
		echo "Architecture: ${n##*:}"
		[ "${m:-same}" = "no" ] || echo "Multi-Arch: ${m:-same}"
		echo "Description: paquet de banc"
		echo ""
		;;
esac
exit 0
EOF
	cat > "$FAUXBIN/dpkg" <<'EOF'
#!/bin/sh
C="$FAUX_CTRL"
echo "dpkg $*" >> "$C/appels"
case "$1" in
	--print-architecture) echo amd64 ;;
	--print-foreign-architectures) [ -f "$C/foreign" ] && cat "$C/foreign" ;;
esac
exit 0
EOF
	#  dpkg-query : le format est VÉRIFIÉ. Si le hook change sa question, le
	#  faux le dit au lieu de répondre à côté et de laisser le banc vert.
	cat > "$FAUXBIN/dpkg-query" <<'EOF'
#!/bin/sh
C="$FAUX_CTRL"
echo "dpkg-query $*" >> "$C/appels"
ATTENDU='-f=${db:Status-Abbrev} ${binary:Package} ${source:Package} ${Version}\n'
if [ "$1" != "-W" ] || [ "$2" != "$ATTENDU" ]; then
	echo "FORMAT INATTENDU : $*" >> "$C/appels"
	exit 3
fi
awk 'NF == 3 { printf "ii  %s %s %s\n", $1, $2, $3 }' "$C/status"
exit 0
EOF
	chmod +x "$FAUXBIN"/apt-get "$FAUXBIN"/apt-cache "$FAUXBIN"/dpkg "$FAUXBIN"/dpkg-query
}

reinit() { # reinit [canal]
	rm -rf "$FAUXBIN" "$CTRL" "$APT_ETC"
	rm -f "$CONF" "$JOURNAL"
	mkdir -p "$APT_ETC/sources.list.d" "$APT_ETC/preferences.d"
	echo "deb https://deb.debian.org/debian/ trixie-backports main contrib non-free-firmware" \
		> "$APT_ETC/sources.list.d/backports.list"
	printf 'LEXOS_KERNEL_CHANNEL="%s"\nLEXOS_DEBIAN_SUITE="trixie"\n' "${1:-backports}" > "$CONF"
	pose_faux_outils
	: > "$CTRL/status"
	: > "$CTRL/candidats"
}

installe() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$CTRL/status"; }   # installe <paquet:arch> <source> <version>
candidat() { printf '%s %s\n' "$1" "$2" >> "$CTRL/candidats"; }        # candidat <paquet:arch> <version>
tire()     { printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> "$CTRL/tire"; }  # tire <demandeur> <dep:arch> <source> <version>
multiarch(){ printf '%s %s\n' "$1" "$2" >> "$CTRL/multiarch"; }        # multiarch <nom> <valeur>

#  Mesa minimal : quatre binaires « Multi-Arch: same ».
MESA_BIN="mesa-libgallium libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers"
installe_mesa() { local b; for b in $MESA_BIN; do installe "$b:$1" mesa "$2"; done; }
candidat_mesa() { local b; for b in $MESA_BIN; do candidat "$b:$1" "$2"; done; }

lance() { # lance -> sortie dans $BANC/sortie, code dans $BANC/code
	FAUX_CTRL="$CTRL" PATH="$FAUXBIN:$PATH" \
	LEXOS_BUILD_CONF="$CONF" LEXOS_APT_ETC="$APT_ETC" LEXOS_A_JOUR_JOURNAL="$JOURNAL" \
	sh "$HOOK" > "$BANC/sortie" 2>&1
	echo "$?" > "$BANC/code"
	cat "$BANC/sortie"
}

#  Les appels « apt-get install » qui portent des paquets (pas « -f »), et
#  les simulations (« apt-get -s install »).
transactions() { grep '^apt-get install' "$CTRL/appels" | grep -v ' -f ' || true; }
simulations()  { grep '^apt-get -s install' "$CTRL/appels" || true; }

#  Les sources de l'épingle, triées, sur une ligne ; et la forme exacte
#  d'une strophe (« Package: src:<s>:any » puis Pin et Pin-Priority).
sources_epingle() { [ -f "$EPINGLE" ] && sed -n 's/^Package: src:\(.*\):any$/\1/p' "$EPINGLE" | sort | tr '\n' ' ' | sed 's/ $//'; }
strophe_ok() {
	[ -f "$EPINGLE" ] && awk -v s="Package: src:$1:any" '
		$0 == s { l = NR }
		l && NR == l + 1 && $0 == "Pin: release n=trixie-backports" { p = 1 }
		l && NR == l + 2 && $0 == "Pin-Priority: 500" && p { ok = 1 }
		END { exit !ok }' "$EPINGLE"
}

#  La scène de référence : Mesa amd64, i386 activé, backports a Mesa dans
#  les deux architectures ; trois micrologiciels — un plus récent dans
#  backports, un SANS version backports, un dont backports est PLUS ANCIEN
#  que la version installée (une mise à jour de trixie l'a dépassé).
scene_reference() {
	reinit
	echo i386 > "$CTRL/foreign"
	installe_mesa amd64 "$T"
	candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
	installe firmware-misc-nonfree firmware-nonfree 20250410-2
	candidat firmware-misc-nonfree 20250917-1~bpo13+1
	installe firmware-intel-graphics firmware-nonfree 20250410-2
	candidat firmware-intel-graphics 20250410-2
	installe firmware-amd-graphics firmware-nonfree 20250808-1+deb13u1
	candidat firmware-amd-graphics 20250808-1+deb13u1
}

# =============================================================================
titre "1. Canal « stock » -> rien, et apt n'est pas appelé"
# =============================================================================
reinit stock
installe_mesa amd64 "$T"
S="$(lance)"
grep -qF "canal « stock » : rien à remonter" <<< "$S" \
	&& ok "le hook le dit et s'arrête" || non "message attendu absent :
$S"
[ "$(cat "$BANC/code")" = "0" ] && ok "code 0" || non "code $(cat "$BANC/code")"
grep -q '^apt-get' "$CTRL/appels" && non "apt-get appelé sur le canal stock" || ok "aucun appel à apt-get"

# =============================================================================
titre "2. backports pas ouvert -> on garde trixie, sans transaction"
# =============================================================================
reinit
rm -f "$APT_ETC/sources.list.d/backports.list"
installe_mesa amd64 "$T"
S="$(lance)"
grep -qF "trixie-backports n'est pas ouvert" <<< "$S" \
	&& ok "le hook le dit" || non "message attendu absent :
$S"
[ -z "$(transactions)" ] && ok "aucune transaction" || non "transaction lancée : $(transactions)"

# =============================================================================
titre "3. Scène de référence -> la BONNE question à apt, et ce qui a VRAIMENT changé"
# =============================================================================
scene_reference
S="$(lance)"
TX="$(transactions)"
SIMS="$(simulations)"
[ "$(cat "$BANC/code")" = "0" ] && ok "code 0" || non "code $(cat "$BANC/code")"
grep -q 'FORMAT INATTENDU' "$CTRL/appels" \
	&& non "dpkg-query interrogé avec un format que ce banc ne connaît pas : $(grep 'FORMAT INATTENDU' "$CTRL/appels")" \
	|| ok "dpkg-query interrogé avec le format attendu (une ligne par architecture)"
NB_TX="$(grep -c . <<< "$TX" || true)"
[ "$NB_TX" = "2" ] && ok "deux transactions : micrologiciels, puis Mesa" || non "$NB_TX transaction(s) au lieu de 2 :
$TX"
#  Chaque contrôle « chaque transaction … » exige d'abord qu'il Y AIT des
#  transactions : sur une liste vide, « aucune n'est mauvaise » est vrai
#  et ne prouve rien (le hook d'avant passait ces contrôles à vide).
MAUVAISES="$(grep -v -- ' --no-remove ' <<< "$TX" || true)"
[ -n "$TX" ] && [ -z "$MAUVAISES" ] && ok "chaque transaction porte --no-remove : apt ne peut rien retirer" \
	|| non "transaction SANS --no-remove (apt pourrait retirer en silence), ou aucune transaction :
$MAUVAISES"
MAUVAISES="$(grep -v -- ' -t trixie-backports ' <<< "$TX" || true)"
[ -n "$TX" ] && [ -z "$MAUVAISES" ] && ok "chaque transaction passe par « -t trixie-backports »" \
	|| non "transaction sans -t trixie-backports, ou aucune transaction :
$MAUVAISES"
MAUVAISES="$(awk 'index($0, " -y ") == 0 || index($0, " --no-install-recommends ") == 0' <<< "$TX")"
[ -n "$TX" ] && [ -z "$MAUVAISES" ] && ok "et -y --no-install-recommends, comme avant" || non "options manquantes :
$MAUVAISES"
MAUVAISES="$(grep -vE '\|LC_ALL=C$' <<< "$TX" || true)"
[ -n "$TX" ] && [ -z "$MAUVAISES" ] && ok "apt-get install lancé sous LC_ALL=C (son bilan est relu en anglais)" \
	|| non "transaction hors LC_ALL=C, ou aucune transaction :
$MAUVAISES"
if [ -z "$TX" ]; then
	non "aucune transaction : « pas de paquet/trixie-backports » ne prouverait rien"
elif grep -qF '/trixie-backports' <<< "$TX"; then
	non "une demande « paquet/trixie-backports » est revenue (elle rétrograde) : $TX"
else
	ok "aucune demande « paquet/trixie-backports » (celle qui exigeait une rétrogradation)"
fi
if [ -z "$TX" ]; then
	non "aucune transaction : « pas de madison » ne prouverait rien"
elif grep -q '^apt-cache madison' "$CTRL/appels"; then
	non "« apt-cache madison » est revenu (le tri architecture par architecture)"
else
	ok "plus de tri par « apt-cache madison »"
fi
#  La simulation doit poser EXACTEMENT la question de la vraie transaction :
#  sans -t, elle verrait trixie ; sans --no-remove, une autre solution.
NB_SIM="$(grep -c . <<< "$SIMS" || true)"
MAUVAISES="$(awk 'index($0, " -t trixie-backports ") == 0 || index($0, " --no-remove ") == 0 || index($0, " --no-install-recommends ") == 0 || $NF != "|LC_ALL=C"' <<< "$SIMS")"
[ "$NB_SIM" = "2" ] && [ -z "$MAUVAISES" ] \
	&& ok "chaque transaction est d'abord SIMULÉE (apt-get -s), avec ses options, sous LC_ALL=C" \
	|| non "simulations absentes ou différentes de la vraie transaction ($NB_SIM) :
$SIMS"
TX_FW="$(grep -F 'firmware-misc-nonfree' <<< "$TX" || true)"
if grep -qF 'firmware-intel-graphics' <<< "$TX_FW" && grep -qF 'firmware-amd-graphics' <<< "$TX_FW"; then
	ok "TOUS les micrologiciels sont demandés — même sans version backports, même plus récents dans trixie"
else
	non "un micrologiciel a été trié avant apt : $TX_FW"
fi
grep -qF 'mesa' <<< "$TX_FW" && non "Mesa mêlé à la transaction des micrologiciels : $TX_FW" \
	|| ok "Mesa n'est pas dans la transaction des micrologiciels (un refus côté Mesa ne les prive pas)"
TX_MESA="$(grep -F 'libgl1-mesa-dri:amd64' <<< "$TX" || true)"
MANQUE=""
for b in $MESA_BIN; do grep -qF "$b:amd64" <<< "$TX_MESA" || MANQUE="$MANQUE $b"; done
[ -z "$MANQUE" ] && ok "les quatre binaires Mesa partent dans UNE transaction" || non "absents de la transaction Mesa :$MANQUE"
grep -qxF "[lexos]   changés par la remontée : 5 paquet(s), dépendances comprises" <<< "$S" \
	&& ok "« changés : 5 » — ce qui a changé (4 Mesa + 1 micrologiciel), pas les 7 noms demandés" \
	|| non "décompte faux :
$S"
grep -qF "[lexos]     · firmware-amd-graphics :" <<< "$S" \
	&& non "un paquet inchangé est compté comme changé" || ok "un paquet inchangé n'est pas compté"
grep -qxF "[lexos]     · libgl1-mesa-dri:amd64 : $T -> $B" <<< "$S" \
	&& ok "chaque paquet changé a sa ligne « avant -> après »" || non "ligne par paquet absente :
$S"
grep -qxF "[lexos]   Mesa (amd64) : $T -> $B" <<< "$S" \
	&& ok "« Mesa (amd64) : $T -> $B »" || non "ligne Mesa absente ou fausse :
$S"
grep -qF "[lexos]   Mesa (i386)" <<< "$S" \
	&& non "une ligne Mesa (i386) alors qu'aucun Mesa i386 n'est installé" || ok "pas de ligne i386 inventée"
grep -qE '^\[lexos\]   apt \(Mesa\) : [0-9]+ upgraded, ' <<< "$S" \
	&& ok "le bilan d'apt est recopié dans le journal de construction AVANT d'effacer le sien" \
	|| non "bilan d'apt absent :
$S"
grep -qF "rien de plus récent" <<< "$S" && non "« rien de plus récent » alors que tout a monté" || ok "pas de « rien de plus récent » quand tout a monté"
[ ! -e "$JOURNAL" ] && ok "le journal temporaire est effacé" || non "journal temporaire laissé derrière"
if strophe_ok mesa && strophe_ok firmware-nonfree && [ "$(sources_epingle)" = "firmware-nonfree mesa" ]; then
	ok "épingle : une strophe src:<source>:any, n=trixie-backports, 500 par source qui a bougé (mesa, firmware-nonfree)"
else
	non "épingle absente ou fausse ($(sources_epingle)) : $(cat "$EPINGLE" 2>/dev/null || echo absente)"
fi
CACHE="$(grep -E '^apt-cache' "$CTRL/appels" || true)"
HORS_C="$(grep -vE '\|LC_ALL=C$' <<< "$CACHE" || true)"
if grep -qE '^apt-cache policy -t trixie-backports ' <<< "$CACHE" && [ -z "$HORS_C" ]; then
	ok "apt-cache policy -t lu sous LC_ALL=C (« Candidate: » non traduit)"
else
	non "apt-cache absent ou appelé hors LC_ALL=C : $CACHE"
fi

# =============================================================================
titre "4. Mesa installé en amd64 ET en i386 -> une ligne par architecture, rien de collé"
# =============================================================================
reinit
echo i386 > "$CTRL/foreign"
installe_mesa amd64 "$T"; installe_mesa i386 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
S="$(lance)"
grep -qxF "[lexos]   Mesa (amd64) : $T -> $B" <<< "$S" && grep -qxF "[lexos]   Mesa (i386) : $T -> $B" <<< "$S" \
	&& ok "« Mesa (amd64) » et « Mesa (i386) », chacune avec SA version" \
	|| non "lignes Mesa par architecture absentes :
$S"
grep -qF "$T$T" <<< "$S" && non "deux versions collées : $(grep -F "$T$T" <<< "$S")" || ok "aucune version collée (« $T$T »)"
TX="$(transactions)"
grep -qF 'libgl1-mesa-dri:i386' <<< "$TX" && grep -qF 'libgl1-mesa-dri:amd64' <<< "$TX" \
	&& ok "amd64 et i386 demandés dans la même transaction" || non "une architecture manque : $TX"
grep -qxF "[lexos]   changés par la remontée : 8 paquet(s), dépendances comprises" <<< "$S" && ok "8 paquets changés (4 × 2 architectures)" || non "décompte faux :
$S"

# =============================================================================
titre "5. backports n'a pas Mesa à la même version en i386 -> Mesa reste sur trixie"
# =============================================================================
#  « i386 installé » : comme le vrai apt, la simulation est REFUSÉE (il
#  faudrait retirer le Mesa 32 bits) ; la garde doit quand même nommer
#  l'écart, depuis les noms demandés.
for variante in "i386 absent (cas de l'ISO)" "i386 installé (Steam 32 bits)" "un seul binaire en retard" "rien d'autre ne monte"; do
	reinit
	echo i386 > "$CTRL/foreign"
	installe_mesa amd64 "$T"
	candidat_mesa amd64 "$B"
	case "$variante" in
		"un seul binaire"*)
			#  mesa-vulkan-drivers n'est PAS le premier dans l'ordre de tri :
			#  une garde qui ne regarderait que le premier binaire le raterait.
			for b in mesa-libgallium libgl1-mesa-dri libglx-mesa0; do candidat "$b:i386" "$B"; done
			candidat mesa-vulkan-drivers:i386 "$T" ;;
		*) candidat_mesa i386 "$T" ;;
	esac
	case "$variante" in
		*installé*) installe_mesa i386 "$T"; echo "mesa-libgallium:i386" > "$CTRL/refuse" ;;
	esac
	installe firmware-misc-nonfree firmware-nonfree 20250410-2
	case "$variante" in
		"rien d'autre"*) candidat firmware-misc-nonfree 20250410-2 ;;
		*) candidat firmware-misc-nonfree 20250917-1~bpo13+1 ;;
	esac
	S="$(lance)"
	TX="$(transactions)"
	grep -qF 'mesa' <<< "$TX" && non "[$variante] Mesa demandé quand même : $TX" \
		|| ok "[$variante] Mesa n'est PAS demandé à apt"
	RAISONS="$(grep -F '[lexos]      · ' <<< "$S" || true)"
	case "$variante" in
		"un seul binaire"*)
			[ "$RAISONS" = "[lexos]      · mesa-vulkan-drivers : $B en amd64, $T en i386" ] \
				&& ok "[$variante] la raison nomme CE binaire seul, versions à l'appui" \
				|| non "[$variante] raison fausse :
$S" ;;
		*)
			grep -qF "Mesa reste sur trixie : backports n'a pas la même version pour chaque architecture" <<< "$S" \
				&& grep -qxF "[lexos]      · libgl1-mesa-dri : $B en amd64, $T en i386" <<< "$RAISONS" \
				&& ok "[$variante] le journal dit pourquoi, versions à l'appui" \
				|| non "[$variante] raison absente :
$S" ;;
	esac
	case "$variante" in
		*installé*)
			grep -qF 'mesa-libgallium:i386' <<< "$(simulations)" \
				&& ok "[$variante] la simulation a été tentée (et refusée, comme le vrai apt)" \
				|| non "[$variante] Mesa n'a pas été simulé : $(simulations)" ;;
	esac
	grep -qF 'firmware-misc-nonfree' <<< "$TX" && ok "[$variante] les micrologiciels ont quand même leur transaction" \
		|| non "[$variante] micrologiciels privés de leur transaction : $TX"
	strophe_ok mesa && non "[$variante] Mesa épinglé alors qu'il n'a pas monté" || ok "[$variante] pas de strophe src:mesa (Mesa n'a pas monté)"
	grep -qxF "[lexos]   Mesa (amd64) : $T -> $T" <<< "$S" && ok "[$variante] « Mesa (amd64) : $T -> $T »" || non "[$variante] ligne Mesa fausse :
$S"
	case "$variante" in
		"rien d'autre"*)
			#  Rien n'a bougé, mais PAS faute de mieux : Mesa a été retenu.
			grep -qF "rien de plus récent" <<< "$S" \
				&& non "[$variante] « rien de plus récent dans backports » alors que la garde a retenu un Mesa plus récent :
$S" \
				|| ok "[$variante] pas de « rien de plus récent » mensonger"
			grep -qxF "[lexos]   rien n'a changé — retenu par la garde : Mesa (voir plus haut)" <<< "$S" \
				&& ok "[$variante] « rien n'a changé — retenu par la garde : Mesa »" || non "[$variante] bilan faux :
$S"
			[ ! -e "$EPINGLE" ] && ok "[$variante] aucune épingle (rien n'a bougé)" || non "[$variante] épingle posée sans rien de changé" ;;
	esac
done

# =============================================================================
titre "6. Un binaire Mesa qui n'existe pas en i386 n'est pas un écart"
# =============================================================================
#  6a : le vrai apt ne répond RIEN pour un nom inconnu en i386 (mesuré).
#  6b : « Candidate: (none) », pour un nom connu sans candidat.
for variante in "sortie vide (nom inconnu en i386)" "Candidate: (none)"; do
	reinit
	echo i386 > "$CTRL/foreign"
	installe_mesa amd64 "$T"
	installe mesa-opencl-icd:amd64 mesa "$T"
	candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
	candidat mesa-opencl-icd:amd64 "$B"
	case "$variante" in *none*) candidat mesa-opencl-icd:i386 "(none)" ;; esac
	S="$(lance)"
	grep -qF 'mesa-opencl-icd:amd64' <<< "$(transactions)" \
		&& ok "[$variante] Mesa monte quand même" \
		|| non "[$variante] un binaire sans pendant i386 a bloqué Mesa :
$S"
done

# =============================================================================
titre "7. Sans i386 activé (ISO minimal) -> pas de vérification i386"
# =============================================================================
reinit
installe_mesa amd64 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$T"
S="$(lance)"
grep -q '^apt-cache' "$CTRL/appels" && non "apt-cache interrogé sans i386 activé" || ok "apt-cache n'est pas interrogé"
[ -z "$(simulations)" ] && ok "aucune simulation" || non "simulation lancée sans i386 : $(simulations)"
grep -qF 'libgl1-mesa-dri:amd64' <<< "$(transactions)" && ok "Mesa monte" || non "Mesa bloqué sans raison :
$S"
strophe_ok mesa && ok "et Mesa est épinglé (un mesa-opencl-icd installé plus tard suivra)" || non "épingle Mesa absente sans i386"

# =============================================================================
titre "8. apt REFUSE la transaction Mesa -> le dit, garde trixie, sans épingle Mesa"
# =============================================================================
scene_reference
echo "mesa-libgallium:amd64" > "$CTRL/refuse"
S="$(lance)"
[ "$(cat "$BANC/code")" = "0" ] && ok "code 0 : l'ISO se construit quand même" || non "code $(cat "$BANC/code")"
grep -qF "Mesa : remontée refusée par apt — on garde les versions de trixie" <<< "$S" \
	&& ok "le refus est annoncé, côté Mesa" || non "refus non annoncé :
$S"
grep -qF "E: Packages need to be removed but remove is disabled." <<< "$S" \
	&& ok "et la ligne E: d'apt est recopiée" || non "ligne E: absente"
grep -qxF "[lexos]     · firmware-misc-nonfree : 20250410-2 -> 20250917-1~bpo13+1" <<< "$S" \
	&& ok "les micrologiciels ont monté malgré le refus côté Mesa" || non "micrologiciels non remontés :
$S"
strophe_ok mesa && non "Mesa épinglé après un refus : il tirerait Mesa de backports contre celui de trixie" \
	|| ok "pas de strophe src:mesa : elle tirerait Mesa de backports contre celui de trixie"
[ ! -e "$JOURNAL" ] && ok "journal temporaire effacé" || non "journal temporaire laissé derrière"

# =============================================================================
titre "8b. apt REFUSE Mesa et aucun micrologiciel ne monte -> pas de « rien de plus récent »"
# =============================================================================
#  Le contrôle de la scène 8 ne pouvait pas rougir : un micrologiciel y
#  monte, et la branche « rien de plus récent » n'est jamais atteinte.
reinit
echo i386 > "$CTRL/foreign"
installe_mesa amd64 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
installe firmware-misc-nonfree firmware-nonfree 20250410-2
candidat firmware-misc-nonfree 20250410-2
echo "mesa-libgallium:amd64" > "$CTRL/refuse"
S="$(lance)"
grep -qF "rien de plus récent" <<< "$S" && non "« rien de plus récent » après un refus : faux :
$S" || ok "pas de « rien de plus récent » mensonger"
grep -qxF "[lexos]   rien n'a changé — refusé par apt : Mesa (voir plus haut)" <<< "$S" \
	&& ok "« rien n'a changé — refusé par apt : Mesa »" || non "bilan faux :
$S"

# =============================================================================
titre "8c. apt REFUSE les micrologiciels -> l'ISO se construit quand même"
# =============================================================================
#  Un .deb que l'index annonce et que le miroir n'a pas encore (synchro en
#  cours) : le vrai apt 2.8.3 rend 100 (« E: Unable to fetch some
#  archives », mesuré). Le hook doit le dire et rendre 0 : sous set -e, un
#  code non nul arrêterait live-build. Aucune autre scène ne refusait les
#  micrologiciels — leur « || true » pouvait tomber sans qu'on le voie.
reinit
installe_mesa amd64 "$T"
candidat_mesa amd64 "$T"
installe firmware-misc-nonfree firmware-nonfree 20250410-2
candidat firmware-misc-nonfree 20250917-1~bpo13+1
echo "firmware-misc-nonfree" > "$CTRL/refuse"
S="$(lance)"
[ "$(cat "$BANC/code")" = "0" ] && ok "[micrologiciels refusés] code 0 : l'ISO se construit quand même" \
	|| non "[micrologiciels refusés] code $(cat "$BANC/code") : la construction s'arrêterait :
$S"
grep -qF "micrologiciels : remontée refusée par apt — on garde les versions de trixie" <<< "$S" \
	&& ok "[micrologiciels refusés] le refus est annoncé" || non "[micrologiciels refusés] refus non annoncé :
$S"
grep -qxF "[lexos]   rien n'a changé — refusé par apt : micrologiciels (voir plus haut)" <<< "$S" \
	&& ok "[micrologiciels refusés] « rien n'a changé — refusé par apt : micrologiciels »" \
	|| non "[micrologiciels refusés] bilan faux :
$S"

# =============================================================================
titre "9. Rien de plus récent dans backports -> le dit, pas d'épingle"
# =============================================================================
reinit
installe_mesa amd64 "$T"
candidat_mesa amd64 "$T"
installe firmware-misc-nonfree firmware-nonfree 20250410-2
candidat firmware-misc-nonfree 20250410-2
S="$(lance)"
grep -qxF "[lexos]   rien de plus récent dans backports — on garde trixie" <<< "$S" \
	&& ok "« rien de plus récent dans backports »" || non "message absent :
$S"
grep -qF "changés par la remontée" <<< "$S" && non "« changés » annoncé alors que rien n'a changé" || ok "aucun changement annoncé"
[ ! -e "$EPINGLE" ] && ok "pas d'épingle" || non "épingle posée sans remontée"

# =============================================================================
titre "10. Un paquet DISPARAÎT malgré tout -> le journal le crie"
# =============================================================================
scene_reference
echo "firmware-intel-graphics" > "$CTRL/retire"
S="$(lance)"
grep -qxF "[lexos]     · firmware-intel-graphics : 20250410-2 -> RETIRÉ" <<< "$S" \
	&& grep -qF "!! un paquet a DISPARU pendant la remontée" <<< "$S" \
	&& ok "la disparition est nommée, pas noyée dans un décompte" || non "disparition non signalée :
$S"

# =============================================================================
titre "11. Aucun paquet Mesa ni micrologiciel -> rien à faire"
# =============================================================================
reinit
installe thunar:amd64 thunar 4.20.0-1
S="$(lance)"
grep -qF "aucun paquet Mesa ou micrologiciel installé" <<< "$S" && ok "le hook le dit" || non "message absent :
$S"
[ -z "$(transactions)" ] && ok "aucune transaction" || non "transaction lancée : $(transactions)"

# =============================================================================
titre "12. Mesa tire une bibliothèque d'une AUTRE source vers backports"
# =============================================================================
#  Mesuré avec le vrai apt 2.8.3 : Mesa de backports exige libdrm2
#  (>= 2.4.125), que seul backports a. Avec la garde et l'épingle limitées
#  à src:mesa, « famille jeux » échouait ensuite : « mesa-libgallium:i386 :
#  Depends: libdrm2:i386 (>= 2.4.125) but it is not going to be installed ».
scene_libdrm() { # scene_libdrm <candidat libdrm2:i386> [source de libdrm2 dans backports]
	reinit
	echo i386 > "$CTRL/foreign"
	installe_mesa amd64 "$T"
	candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
	installe libdrm2:amd64 libdrm "$DRM_T"
	candidat libdrm2:amd64 "$DRM_B"; candidat libdrm2:i386 "$1"
	tire mesa-libgallium:amd64 libdrm2:amd64 "${2:-libdrm}" "$DRM_B"
}

#  12a : backports a libdrm2 dans les deux architectures -> tout monte,
#  libdrm2 est NOMMÉ et ÉPINGLÉ.
scene_libdrm "$DRM_B"
S="$(lance)"
grep -qF 'libgl1-mesa-dri:amd64' <<< "$(transactions)" && ok "[libdrm2 aligné] Mesa monte" || non "[libdrm2 aligné] Mesa bloqué à tort :
$S"
grep -qxF "[lexos]     · libdrm2:amd64 : $DRM_T -> $DRM_B" <<< "$S" \
	&& ok "[libdrm2 aligné] libdrm2 est nommé dans le journal (il passait sous silence)" \
	|| non "[libdrm2 aligné] libdrm2:amd64 absent du journal :
$S"
grep -qxF "[lexos]   changés par la remontée : 5 paquet(s), dépendances comprises" <<< "$S" \
	&& ok "[libdrm2 aligné] « changés : 5 », comme le « 5 upgraded » d'apt" || non "[libdrm2 aligné] décompte faux :
$S"
if strophe_ok libdrm && strophe_ok mesa && [ "$(sources_epingle)" = "libdrm mesa" ]; then
	ok "[libdrm2 aligné] épingle src:libdrm:any ET src:mesa:any — libdrm2:i386 suivra"
else
	non "[libdrm2 aligné] épingle incomplète ($(sources_epingle)) : $(cat "$EPINGLE" 2>/dev/null || echo absente)"
fi

#  12b : backports n'a libdrm2 qu'en amd64 -> Mesa reste sur trixie, et
#  la raison nomme libdrm2 (pas un binaire Mesa : Mesa, lui, est aligné).
#  Les deux formes de la ligne « Inst » d'une dépendance, vues avec le vrai
#  apt 2.8.3 dans la même simulation : rien après « [amd64]) » (libdrm2),
#  ou « [] » (libdrm-amdgpu1). La garde ne connaît cette dépendance QUE par
#  la simulation : une lecture qui ne tolère plus le « [] » la perdait, et
#  Mesa montait seul (mesuré : « famille jeux » rc=100 ensuite).
for variante in "libdrm2 en retard en i386" "libdrm2 en retard en i386, suivi de « [] »"; do
	scene_libdrm "$DRM_T"
	FIN=""
	case "$variante" in *"[]"*) echo libdrm2 > "$CTRL/crochets"; FIN=" []" ;; esac
	S="$(lance)"
	grep -qxF "Inst libdrm2 [$DRM_T] ($DRM_B Faux Backports:stable-backports [amd64])$FIN" "$CTRL/inst" \
		&& ok "[$variante] la simulation rend bien cette forme de ligne « Inst »" \
		|| non "[$variante] ligne « Inst libdrm2 » inattendue : $(cat "$CTRL/inst")"
	grep -qF 'mesa' <<< "$(transactions)" && non "[$variante] Mesa demandé quand même : $(transactions)" \
		|| ok "[$variante] Mesa n'est PAS demandé à apt"
	RAISONS="$(grep -F '[lexos]      · ' <<< "$S" || true)"
	[ "$RAISONS" = "[lexos]      · libdrm2 : $DRM_B en amd64, $DRM_T en i386" ] \
		&& ok "[$variante] la raison nomme libdrm2, versions à l'appui" \
		|| non "[$variante] raison absente ou fausse :
$S"
	grep -qF 'libgl1-mesa-dri' <<< "$(simulations)" \
		&& ok "[$variante] l'écart vient de la SIMULATION de la transaction Mesa" \
		|| non "[$variante] la transaction Mesa n'a pas été simulée : $(simulations)"
	[ ! -e "$EPINGLE" ] && ok "[$variante] aucune épingle (rien n'a bougé)" || non "[$variante] épingle posée : $(sources_epingle)"
done

#  12c : une dépendance NEUVE (pas installée avant) -> « absent -> V »,
#  et sa source épinglée.
reinit
echo i386 > "$CTRL/foreign"
installe_mesa amd64 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
candidat libneuve1:amd64 1.1-1~bpo13+1; candidat libneuve1:i386 1.1-1~bpo13+1
tire mesa-libgallium:amd64 libneuve1:amd64 libneuve 1.1-1~bpo13+1
S="$(lance)"
grep -qxF "[lexos]     · libneuve1:amd64 : absent -> 1.1-1~bpo13+1" <<< "$S" \
	&& ok "[dépendance neuve] « libneuve1:amd64 : absent -> 1.1-1~bpo13+1 »" || non "[dépendance neuve] absente du journal :
$S"
strophe_ok libneuve && ok "[dépendance neuve] src:libneuve:any épinglé" || non "[dépendance neuve] source non épinglée ($(sources_epingle))"

#  12d : une dépendance qui n'est PAS « Multi-Arch: same » (un outil
#  « foreign ») peut n'exister qu'en amd64 dans backports : pas un écart.
reinit
echo i386 > "$CTRL/foreign"
installe_mesa amd64 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
candidat outil-gl:amd64 1.1-1~bpo13+1; candidat outil-gl:i386 1.0-1
multiarch outil-gl foreign
tire mesa-libgallium:amd64 outil-gl:amd64 outil-gl 1.1-1~bpo13+1
S="$(lance)"
grep -qF 'libgl1-mesa-dri:amd64' <<< "$(transactions)" \
	&& ok "[dépendance « foreign »] Mesa monte : seul « Multi-Arch: same » impose la même version" \
	|| non "[dépendance « foreign »] Mesa retenu à tort :
$S"

#  12e : backports a RENOMMÉ la source de la dépendance (libdrm ->
#  libdrm-nouvelle). L'épingle doit nommer la source D'APRÈS : avec le vrai
#  apt 2.8.3, « src:libdrm:any » ne couvrait pas le libdrm2:i386 de
#  backports, et « famille jeux » rendait 100.
scene_libdrm "$DRM_B" libdrm-nouvelle
S="$(lance)"
if strophe_ok libdrm-nouvelle && strophe_ok mesa && [ "$(sources_epingle)" = "libdrm-nouvelle mesa" ]; then
	ok "[source renommée] épingle src:libdrm-nouvelle:any — la source de la version installée, pas l'ancienne"
else
	non "[source renommée] épingle sur la mauvaise source ($(sources_epingle)) : $(cat "$EPINGLE" 2>/dev/null || echo absente)"
fi

#  12f : une dépendance qui DEVIENT « Multi-Arch: same » dans backports.
#  dpkg l'appelait « libfoo1 » avant, « libfoo1:amd64 » après : elle a
#  seulement monté (vrai apt 2.8.3 : « 5 upgraded, 0 newly installed »).
reinit
echo i386 > "$CTRL/foreign"
installe_mesa amd64 "$T"
candidat_mesa amd64 "$B"; candidat_mesa i386 "$B"
installe libfoo1 libfoo 1.0-1
candidat libfoo1:amd64 1.1-1~bpo13+1; candidat libfoo1:i386 1.1-1~bpo13+1
tire mesa-libgallium:amd64 libfoo1:amd64 libfoo 1.1-1~bpo13+1
S="$(lance)"
if grep -qE 'RETIRÉ|DISPARU' <<< "$S"; then
	non "[devenue « Multi-Arch: same »] faux « RETIRÉ » / « a DISPARU » : rien n'a disparu :
$S"
else
	ok "[devenue « Multi-Arch: same »] ni « RETIRÉ » ni « a DISPARU » : elle a seulement monté"
fi
grep -qxF "[lexos]     · libfoo1:amd64 : 1.0-1 -> 1.1-1~bpo13+1" <<< "$S" \
	&& grep -qxF "[lexos]   changés par la remontée : 5 paquet(s), dépendances comprises" <<< "$S" \
	&& ok "[devenue « Multi-Arch: same »] une seule ligne, au nom d'après, et « changés : 5 » comme apt" \
	|| non "[devenue « Multi-Arch: same »] ligne ou décompte faux :
$S"

# =============================================================================
titre "13. Les micrologiciels seuls -> leur source est épinglée, pas Mesa"
# =============================================================================
reinit
installe firmware-misc-nonfree firmware-nonfree 20250410-2
candidat firmware-misc-nonfree 20250917-1~bpo13+1
S="$(lance)"
[ "$(sources_epingle)" = "firmware-nonfree" ] && strophe_ok firmware-nonfree \
	&& ok "épingle src:firmware-nonfree:any seule" || non "épingle fausse ($(sources_epingle)) :
$S"

# =============================================================================
#  Les mutations relancent CE banc sur un hook muté : on s'arrête ici.
[ -n "${LEXOS_A_JOUR_SANS_MUTATIONS:-}" ] && {
	printf '\n%d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
	[ "$ECHOUES" -eq 0 ]; exit
}

# =============================================================================
titre "14. Mutations : le banc a des dents"
# =============================================================================
#  Chaque défense retirée du hook (une à la fois) DOIT faire rougir un
#  contrôle NOMMÉ des sections 1 à 13 : on rejoue tout le banc sur le hook
#  muté. Une mutation qui ne change rien au fichier est signalée — le hook
#  a bougé, la mutation est à revoir.
#  mutation <nom> <texte d'origine> <texte muté> <début du contrôle qui doit rougir>
mutation() {
	local nom="$1" ancien="$2" nouveau="$3" attendu="$4" m="$BANC/mutant-$1.sh" contenu sortie rouges
	contenu="$(cat "$HOOK"; printf x)"; contenu="${contenu%x}"
	if [[ "$contenu" != *"$ancien"* ]]; then
		non "mutation « $nom » : texte d'origine introuvable — le hook a bougé, ce contrôle est à revoir"
		return
	fi
	printf '%s' "${contenu/"$ancien"/"$nouveau"}" > "$m"
	sortie="$(LEXOS_A_JOUR_HOOK="$m" LEXOS_A_JOUR_SANS_MUTATIONS=1 bash "${BASH_SOURCE[0]}" 2>&1)"
	rouges="$(grep -F '❌' <<< "$sortie" || true)"
	if grep -qF "$attendu" <<< "$rouges"; then
		ok "mutation « $nom » attrapée : $attendu…"
	else
		non "mutation « $nom » NON attrapée par « $attendu » — rouges : ${rouges:-aucun}"
	fi
}

mutation sans-no-remove \
	'apt-get install -y --no-install-recommends --no-remove -t "$BPO" "$@" \' \
	'apt-get install -y --no-install-recommends -t "$BPO" "$@" \' \
	"transaction SANS --no-remove"
mutation sans-garde \
	'[ -n "$ETRANGERES" ] || return 0' \
	'return 0' \
	"[i386 absent (cas de l'ISO)] Mesa demandé quand même"
mutation garde-sans-simulation \
	'printf '"'"'%s\n'"'"' "$@"; simule "$@"; } | sort -u' \
	'printf '"'"'%s\n'"'"' "$@"; } | sort -u' \
	"[libdrm2 en retard en i386] Mesa demandé quand même"
mutation garde-sans-noms-demandes \
	'printf '"'"'%s\n'"'"' "$@"; simule "$@"; } | sort -u' \
	'simule "$@"; } | sort -u' \
	"[i386 installé (Steam 32 bits)] Mesa demandé quand même"
mutation simulation-sans-t \
	'apt-get -s install -y --no-install-recommends --no-remove -t "$BPO" "$@"' \
	'apt-get -s install -y --no-install-recommends --no-remove "$@"' \
	"simulations absentes ou différentes de la vraie transaction"
mutation garde-premier-seulement \
	'simule "$@"; } | sort -u); do' \
	'simule "$@"; } | sort -u | head -n 1); do' \
	"[un seul binaire en retard] Mesa demandé quand même"
mutation vide-compte-pour-ecart \
	'{ [ -n "$C" ] && [ "$C" != "(none)" ]; } || continue' \
	'{ [ "$C" != "(none)" ]; } || continue' \
	"[sortie vide (nom inconnu en i386)] un binaire sans pendant i386 a bloqué Mesa"
mutation none-compte-pour-ecart \
	'{ [ -n "$C" ] && [ "$C" != "(none)" ]; } || continue' \
	'{ [ -n "$C" ]; } || continue' \
	"[Candidate: (none)] un binaire sans pendant i386 a bloqué Mesa"
mutation multiarch-ignore \
	'			same|"") ;;' \
	'			*) ;;' \
	"[dépendance « foreign »] Mesa retenu à tort"
mutation retenu-oublie \
	'elif [ -n "$REFUS" ] || [ -n "$RETENU" ]; then' \
	'elif [ -n "$REFUS" ]; then' \
	"[rien d'autre ne monte] « rien de plus récent dans backports » alors que la garde"
mutation refus-oublie \
	'elif [ -n "$REFUS" ] || [ -n "$RETENU" ]; then' \
	'elif [ -n "$RETENU" ]; then' \
	"« rien de plus récent » après un refus"
mutation etat-limite-aux-cibles \
	"| awk '\$1 ~ /^ii/ { print \$2, \$3, \$4 }' \\" \
	"| awk '\$1 ~ /^ii/ && (\$3 == \"mesa\" || \$3 ~ /^firmware-/) { print \$2, \$3, \$4 }' \\" \
	"[libdrm2 aligné] libdrm2:amd64 absent du journal"
mutation epingle-mesa-seule \
	'awk '"'"'NF == 4 && $4 != "RETIRÉ" { print $2 }'"'"'' \
	'awk '"'"'NF == 4 && $4 != "RETIRÉ" && $2 == "mesa" { print $2 }'"'"'' \
	"[libdrm2 aligné] épingle incomplète"
mutation epingle-sans-any \
	'echo "Package: src:${S}:any"' \
	'echo "Package: src:${S}"' \
	"épingle absente ou fausse"
mutation epingle-sur-tout-l-installe \
	'SOURCES="$(printf '"'"'%s\n'"'"' "$CHANGES" | awk '"'"'NF == 4 && $4 != "RETIRÉ" { print $2 }'"'"'' \
	'SOURCES="$(printf '"'"'%s\n'"'"' "$AVANT" | awk '"'"'NF == 3 { print $2 }'"'"'' \
	"Mesa épinglé après un refus"
mutation sed-sans-crochets-finaux \
	'\[\([a-z0-9-]*\)\]).*$/\1 \2/p' \
	'\[\([a-z0-9-]*\)\])$/\1 \2/p' \
	"[libdrm2 en retard en i386, suivi de « [] »] Mesa demandé quand même"
mutation refus-micrologiciels-fatal \
	'remonte "micrologiciels" $MICROLOGICIELS || true' \
	'remonte "micrologiciels" $MICROLOGICIELS' \
	"[micrologiciels refusés] code"
mutation epingle-source-d-avant \
	'else if (v[k] != w[k]) print nb[k], t[k], v[k], w[k]' \
	'else if (v[k] != w[k]) print nb[k], s[k], v[k], w[k]' \
	"[source renommée] épingle sur la mauvaise source"
mutation cle-avec-architecture \
	'return substr(n, 1, length(n) - length(nat))' \
	'return n' \
	"[devenue « Multi-Arch: same »] faux « RETIRÉ »"
mutation format-colle \
	'${Version}\n'"'"' 2>/dev/null' \
	'${Version}'"'"' 2>/dev/null' \
	"dpkg-query interrogé avec un format que ce banc ne connaît pas"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
