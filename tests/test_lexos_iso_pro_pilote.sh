#!/usr/bin/env bash
# =============================================================================
#  UNE ISO « pro » SANS PILOTE NVIDIA NE PART PLUS EN SILENCE
# =============================================================================
#  CE QUE FAISAIT LA CASCADE. Le hook 0260 a quatre branches, et la dernière
#  s'appelle « rien — l'ISO reste exactement comme avant ce hook ». Elle
#  faisait « exit 0 » : la construction passait au VERT, l'ISO était publiée,
#  et rien nulle part ne disait qu'elle ne contenait pas de pilote. On le
#  découvrait en démarrant la machine — écran en console, et une soirée à
#  chercher du côté du BIOS.
#
#  C'est un piège pour la saveur « pro » PRÉCISÉMENT parce que c'est la seule
#  qui promette les cartes NVIDIA récentes.
#
#  ═══ CE QUE CE BANC ÉPROUVE ═══
#  1. Le résultat de la cascade est ÉCRIT dans build.conf, sur CHAQUE chemin
#     de sortie du hook — y compris ceux qui réussissent et ceux qui ne
#     concernent pas la saveur.
#  2. Une saveur « pro » sans pilote fait ÉCHOUER la construction. Une
#     construction rouge se corrige en une heure ; une ISO verte qui ne
#     démarre pas coûte une soirée et une clé USB.
#  3. La porte de sortie (LEXOS_NVIDIA_FACULTATIF=1) laisse passer, mais
#     l'ISO part marquée — une porte de sortie silencieuse est une porte
#     qu'on finit par laisser ouverte.
#  4. Et ça SE LIT sur la machine : lexfetch et lexos tv le disent en une
#     seconde, sans qu'on ait à connaître l'existence d'un rapport.
#
#  TROIS RÉPONSES, PAS DEUX. « sans-objet » (saveur standard) n'est pas
#  « absent » (échec), et une clé manquante veut dire « ISO d'avant ce
#  changement ». Confondre les trois, c'est le bogue du dock, encore.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0260-lexos-nvidia.hook.chroot"
LEXFETCH="$RACINE/config/includes.chroot/usr/bin/lexfetch"
TV="$RACINE/config/includes.chroot/usr/bin/lexos-tv"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$HOOK" "$LEXFETCH" "$TV"; do
	[ -r "$F" ] || { non "fichier manquant : $F"; printf '\n'; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { muet "python3 absent : rien n'a été mesuré"; exit 0; }

# ===========================================================================
titre "1. conf_pose ÉCRIT, PUIS REMPLACE — il n'empile pas les doublons"
# ===========================================================================
#  Une clé posée deux fois donnerait deux lignes, et « . build.conf » garderait
#  la DERNIÈRE. Ça marcherait par accident aujourd'hui et mentirait le jour où
#  quelqu'un lirait le fichier avec grep. On exécute la vraie fonction.
POSE="$(python3 - "$HOOK" "$BANC" <<'PY' 2>&1
import subprocess, sys, os
hook, banc = sys.argv[1:3]
src = open(hook, encoding="utf-8").read()
i = src.index("conf_pose() {"); j = src.index("\n}", i) + 2
frag = src[i:j].replace("/etc/lexos", banc + "/etc/lexos")
script = frag + """
conf_pose LEXOS_NVIDIA_ETAT ok
conf_pose LEXOS_NVIDIA_VERSION 610.43.02
conf_pose LEXOS_NVIDIA_ETAT absent
cat %s/etc/lexos/build.conf
""" % banc
r = subprocess.run(["sh", "-c", script], capture_output=True, text=True)
print(r.stdout.strip().replace("\n", " | ") or ("ERREUR " + r.stderr.strip()[:120]))
PY
)"
case "$POSE" in
	'LEXOS_NVIDIA_ETAT="absent" | LEXOS_NVIDIA_VERSION="610.43.02"')
		ok "la clé est remplacée en place, la seconde n'est pas perdue" ;;
	*ok*absent*) non "la clé a été empilée au lieu d'être remplacée : $POSE" ;;
	*) non "conf_pose ne se comporte pas comme attendu : $POSE" ;;
esac

# ===========================================================================
titre "2. CHAQUE SORTIE DU HOOK INSCRIT SON RÉSULTAT"
# ===========================================================================
#  ═══ LE TROU QU'ON BOUCHE ICI ═══
#  Une sortie qui n'écrit rien laisse build.conf dans l'état de la
#  construction PRÉCÉDENTE, ou sans la clé du tout. La console, lexfetch et
#  lexos tv concluraient alors « ISO d'avant ce changement » sur une ISO
#  toute neuve — c'est-à-dire qu'ils se tairaient, exactement le défaut du
#  jour. On vérifie donc que chaque « exit » est précédé, dans sa branche,
#  d'une inscription de LEXOS_NVIDIA_ETAT.
SORTIES="$(python3 - "$HOOK" <<'PY' 2>&1
import sys
lignes = open(sys.argv[1], encoding="utf-8").read().split("\n")
nues = []
for n, l in enumerate(lignes):
    if l.strip() in ("exit 0", "exit 1"):
        #  On remonte dans la branche : l'inscription doit être proche.
        fenetre = "\n".join(lignes[max(0, n - 45):n])
        if 'conf_pose LEXOS_NVIDIA_ETAT' not in fenetre:
            nues.append("%d (%s)" % (n + 1, l.strip()))
print("NUES " + ", ".join(nues) if nues else "TOUTES")
PY
)"
case "$SORTIES" in
	TOUTES) ok "les $(grep -c '^\s*exit [01]' "$HOOK") sorties du hook inscrivent toutes LEXOS_NVIDIA_ETAT" ;;
	NUES*)  non "des sorties n'inscrivent rien — build.conf garderait l'état d'une autre construction : ${SORTIES#NUES }" ;;
	*)      muet "les sorties n'ont pas pu être examinées : $SORTIES" ;;
esac

#  Et le chemin qui RÉUSSIT, qui ne se termine pas par un « exit ».
grep -q 'conf_pose LEXOS_NVIDIA_ETAT "ok"' "$HOOK" \
	&& ok "…et le chemin qui réussit inscrit « ok »" \
	|| non "le chemin qui réussit n'inscrit rien : une ISO avec pilote passerait pour une ISO d'avant"
grep -q 'conf_pose LEXOS_NVIDIA_MODULE' "$HOOK" \
	&& ok "…et dit si le MODULE NOYAU est compilé, pas seulement si apt a dit oui" \
	|| non "le module noyau n'est pas inscrit : deux ISO ont déjà été livrées sur la foi d'un « apt a dit oui »"

# ===========================================================================
titre "3. LA DÉCISION : « pro » SANS PILOTE FAIT ÉCHOUER LA CONSTRUCTION"
# ===========================================================================
#  ═══ ON EXÉCUTE LA DÉCISION, ON NE LA RELIT PAS ═══
#  Le bloc est extrait du hook et joué avec conf_pose bouchonné, dans les deux
#  cas. Ce qui compte est le CODE DE SORTIE : c'est lui que live-build lit.
decide() {   # decide <valeur de LEXOS_NVIDIA_FACULTATIF> -> "<code> <etat>"
	python3 - "$HOOK" "$BANC" "$1" <<'PY' 2>&1
import subprocess, sys
hook, banc, facultatif = sys.argv[1:4]
src = open(hook, encoding="utf-8").read()
#  ⚠ SI L'ANCRE A DISPARU, ON LE DIT EN FRANÇAIS. Une trace Python dans un
#  banc, c'est un rouge qu'on prend pour une panne du banc — alors que
#  l'ancre qui manque EST le défaut : quelqu'un a retiré la décision.
try:
    i = src.index('if [ "${LEXOS_NVIDIA_FACULTATIF:-0}" = "1" ]')
    j = src.index("\n\t\texit 1\n", i) + len("\n\t\texit 1\n")
except ValueError:
    print("SANS_DECISION")
    raise SystemExit
frag = src[i:j]
#  On désindente le bloc (il vit dans un « else » imbriqué) et on bouchonne
#  ce qui n'a rien à voir avec la décision.
frag = "\n".join(l[2:] if l.startswith("\t\t") else l for l in frag.split("\n"))
script = """
conf_pose() { printf '%s=%s\\n' "$1" "$2" >> ETATS; }
REPORT=REPORTFILE
: > ETATS
: > REPORTFILE
#  ⚠ UN MARQUEUR QUI NE PEUT PAS SE CONFONDRE AVEC LE NOM DE LA VARIABLE.
#  Première version : le marqueur s'appelait « FACULTATIF », et le remplacement
#  a aussi frappé « LEXOS_NVIDIA_FACULTATIF= », qui est devenu
#  « LEXOS_NVIDIA_1= ». La porte de sortie ne s'ouvrait jamais, et le banc
#  accusait le hook d'un défaut qui était le sien.
LEXOS_NVIDIA_FACULTATIF=@@FAC@@
""".replace("ETATS", banc + "/etats").replace("REPORTFILE", banc + "/report") \
   .replace("@@FAC@@", facultatif) + frag
r = subprocess.run(["sh", "-c", script], capture_output=True, text=True)
etats = open(banc + "/etats", encoding="utf-8").read().replace("\n", " ").strip()
print("%d %s" % (r.returncode, etats))
PY
}

VU_STRICT="$(decide 0)"
case "$VU_STRICT" in
	1*LEXOS_NVIDIA_ETAT=absent*)
		ok "sans porte de sortie : la construction ÉCHOUE (code 1) et l'ISO est marquée « absent »" ;;
	SANS_DECISION) non "le hook n'a PLUS de décision : une ISO « pro » sans pilote repasserait au vert en silence" ;;
	0*) non "la construction passe au VERT sans pilote : c'est le défaut d'origine ($VU_STRICT)" ;;
	*)  non "la décision n'a pas pu être jouée : $VU_STRICT" ;;
esac

VU_SOUPLE="$(decide 1)"
case "$VU_SOUPLE" in
	0*LEXOS_NVIDIA_ETAT=absent-accepte*)
		ok "avec LEXOS_NVIDIA_FACULTATIF=1 : ça passe, mais l'ISO part MARQUÉE" ;;
	1*) non "la porte de sortie ne s'ouvre pas : LEXOS_NVIDIA_FACULTATIF=1 échoue quand même ($VU_SOUPLE)" ;;
	SANS_DECISION) non "le hook n'a plus de porte de sortie : LEXOS_NVIDIA_FACULTATIF ne sert plus à rien" ;;
	*0*absent\ *) non "la porte de sortie laisse passer SANS marquer l'ISO : elle deviendrait silencieuse ($VU_SOUPLE)" ;;
	*)  non "la porte de sortie n'a pas pu être jouée : $VU_SOUPLE" ;;
esac

# ===========================================================================
titre "4. ÇA SE LIT SUR LA MACHINE — lexfetch"
# ===========================================================================
#  « Pilote NVIDIA : absent de cette ISO » doit se lire en une seconde, sans
#  savoir qu'un rapport existe quelque part dans /etc.
fetch() {   # fetch <contenu de build.conf>
	printf '%s' "$1" > "$BANC/build.conf"
	LEXOS_BUILD_CONF="$BANC/build.conf" NO_COLOR=1 TERM=dumb \
		bash "$LEXFETCH" 2>/dev/null | grep -i 'Pilote NV' | sed 's/.*Pilote NV *: *//'
}

VU="$(fetch 'LEXOS_NVIDIA_ETAT="absent"
')"
case "$VU" in
	*"ABSENT DE CETTE ISO"*) ok "une ISO sans pilote l'écrit en clair dans lexfetch" ;;
	"") non "lexfetch ne dit RIEN sur une ISO sans pilote : c'est l'écran joyeux du départ" ;;
	*)  non "lexfetch dit « $VU » au lieu d'annoncer l'absence" ;;
esac

VU="$(fetch 'LEXOS_NVIDIA_ETAT="ok"
LEXOS_NVIDIA_VERSION="610.43.02"
LEXOS_NVIDIA_MODULE="oui"
')"
[ "$VU" = "610.43.02" ] \
	&& ok "…et une ISO avec pilote affiche sa version" \
	|| non "la version du pilote ne s'affiche pas : « $VU »"

VU="$(fetch 'LEXOS_NVIDIA_ETAT="ok"
LEXOS_NVIDIA_VERSION="610.43.02"
LEXOS_NVIDIA_MODULE="non"
')"
case "$VU" in
	*"module noyau ABSENT"*) ok "…et un pilote SANS module noyau le dit : rien ne prendra la carte" ;;
	*) non "un pilote sans module noyau passe pour un pilote qui marche : « $VU »" ;;
esac

VU="$(fetch 'LEXOS_NVIDIA_ETAT="sans-objet"
')"
[ -z "$VU" ] \
	&& ok "…et une saveur qui ne promet aucun pilote n'inquiète personne (aucune ligne)" \
	|| non "une saveur standard affiche « $VU » : elle alarmerait pour rien"

VU="$(fetch '')"
[ -z "$VU" ] \
	&& ok "…comme une ISO d'avant ce changement (clé absente = on ne sait pas, on se tait)" \
	|| non "sans la clé, lexfetch affirme « $VU » — il invente"

# ===========================================================================
titre "5. ÇA SE LIT SUR LA MACHINE — lexos tv"
# ===========================================================================
#  Le rapport du hook fait jusqu'à trente lignes. Devant une machine qui ne
#  démarre pas, la réponse doit venir AVANT, en clair. Le bloc est extrait et
#  exécuté avec « titre » bouchonné : on mesure ce qu'il imprime.
tv() {   # tv <contenu de build.conf>
	printf '%s' "$1" > "$BANC/build.conf"
	python3 - "$TV" "$BANC" <<'PY' 2>&1
import subprocess, sys
tv, banc = sys.argv[1:3]
src = open(tv, encoding="utf-8").read()
try:
    i = src.index('\tif [ -r /etc/lexos/build.conf ]; then')
    j = src.index('\n\tif [ -r /etc/lexos/nvidia-report ]; then', i)
except ValueError:
    print("SANS_RESUME")
    raise SystemExit
frag = src[i:j].replace("/etc/lexos/build.conf", banc + "/build.conf")
frag = "\n".join(l[1:] if l.startswith("\t") else l for l in frag.split("\n"))
script = "titre() { printf '== %s\\n' \"$1\"; }\n" + frag
r = subprocess.run(["sh", "-c", script], capture_output=True, text=True)
print((r.stdout or r.stderr).strip().replace("\n", " ⏎ "))
PY
}

VU="$(tv 'LEXOS_NVIDIA_ETAT="absent"
')"
case "$VU" in
	*"ABSENT DE CETTE ISO"*"rien à régler sur cette machine"*)
		ok "lexos tv annonce l'absence AVANT le rapport, et dit qu'il faut une autre ISO" ;;
	SANS_RESUME) non "lexos tv n'a plus de résumé : la réponse est noyée dans trente lignes de rapport" ;;
	*) non "lexos tv ne distingue pas une ISO sans pilote d'un problème de machine : $VU" ;;
esac

VU="$(tv 'LEXOS_NVIDIA_ETAT="absent-accepte"
')"
case "$VU" in
	*"FACULTATIF=1"*) ok "…et dit quand l'absence a été acceptée sciemment à la construction" ;;
	*ABSENT*) non "« absent-accepte » est affiché comme un échec : on chercherait une cause qui n'existe pas" ;;
	SANS_RESUME) non "lexos tv n'a plus de résumé : « absent-accepte » ne se lit nulle part" ;;
	*) non "le cas « absent-accepte » ne donne rien de reconnaissable : $VU" ;;
esac

VU="$(tv 'LEXOS_NVIDIA_ETAT="ok"
LEXOS_NVIDIA_VERSION="610.43.02"
LEXOS_NVIDIA_MODULE="non"
LEXOS_NVIDIA_SOURCE="dépôt officiel NVIDIA"
')"
case "$VU" in
	*"610.43.02"*"MODULE NOYAU"*) ok "…et signale un pilote dont le module noyau manque" ;;
	*610.43.02*) non "lexos tv affiche la version mais tait le module manquant : $VU" ;;
	SANS_RESUME) non "lexos tv n'a plus de résumé : la version du pilote ne se lit plus en une seconde" ;;
	*) non "le cas « ok » ne donne rien de reconnaissable : $VU" ;;
esac

# ===========================================================================
titre "6. LA SAVEUR SE VOIT — et l'exemple du README ne ment plus"
# ===========================================================================
#  ═══ POURQUOI LA SAVEUR EST UNE INFORMATION DE PANNE ═══
#  Six saveurs existent (minimal, standard, dev, full, gaming, pro) et elles
#  se ressemblent toutes une fois démarrées. Or SEULE « pro » embarque un
#  pilote NVIDIA : c'est exactement la question qu'on se pose devant un écran
#  resté en console, et rien ne permettait d'y répondre DEPUIS la machine.
#  ⚠ LA SAVEUR VIENT D'ABORD DE /etc/os-release, ET C'EST MESURÉ ICI.
#  Le hook 0100 y écrit LEXOS_FLAVOUR, et lexfetch source os-release avant
#  d'arriver à ce bloc : la variable est donc DÉJÀ posée. La première version
#  de ce contrôle ne jouait que build.conf, sur une machine de construction
#  dont l'os-release n'a pas la clé — il certifiait donc verte une branche
#  « clé absente » qui, sur une VRAIE machine LexOS, n'est jamais atteinte.
#  On mesure maintenant les deux sources, et le cas où aucune ne répond.
saveur() {   # saveur <contenu de build.conf> [VAR=val…] -> la ligne OS
	local conf="$1"; shift
	printf '%s' "$conf" > "$BANC/build.conf"
	env -u LEXOS_FLAVOUR "$@" LEXOS_BUILD_CONF="$BANC/build.conf" \
		NO_COLOR=1 TERM=dumb PATH="$PATH" HOME="$HOME" \
		bash "$LEXFETCH" 2>/dev/null | grep -E 'OS  *:' | sed 's/.*OS  *: *//'
}

#  1. Par os-release — le chemin normal sur une machine LexOS. Sourcer
#     os-release, c'est exactement poser la variable dans l'environnement.
VU="$(saveur '' LEXOS_FLAVOUR=gaming)"
case "$VU" in
	*"· gaming ·"*) ok "la saveur d'os-release se lit sur la ligne « OS » (le chemin normal)" ;;
	"")   non "lexfetch n'affiche plus de ligne OS du tout" ;;
	*)    non "la saveur d'os-release ne se voit pas : « $VU »" ;;
esac

#  2. Par build.conf — le recours, si l'os-release a été remplacé.
VU="$(saveur 'LEXOS_FLAVOUR="pro"
')"
case "$VU" in
	*"· pro ·"*) ok "…et build.conf sert de second recours quand os-release se tait" ;;
	*)    non "sans os-release, la saveur de build.conf ne se voit pas : « $VU »" ;;
esac

#  3. Ni l'une ni l'autre : on n'invente pas « standard ».
VU="$(saveur '')"
case "$VU" in
	*"·"*) non "sans aucune source, lexfetch affiche un séparateur vide : « $VU »" ;;
	"")    non "lexfetch n'affiche plus de ligne OS du tout" ;;
	*)     ok "…et quand aucune des deux ne répond, la ligne reste celle d'avant, sans rien inventer" ;;
esac

#  ═══ L'EXEMPLE DU README, COMPARÉ À LA CONFIGURATION RÉELLE ═══
#  Il affichait « Debian bookworm (12.5) » et un noyau « 6.1.0-18 ». LexOS 2.0
#  est construit sur trixie avec un noyau 6.12. Alex l'a collé en croyant
#  qu'il venait de son Alienware — c'est dire à quel point il a l'air vrai.
#  On ne relit donc pas l'exemple : on le COMPARE à lexos.conf.
CONF="$RACINE/lexos.conf"
LISEZ="$RACINE/README.md"
if [[ ! -r "$CONF" || ! -r "$LISEZ" ]]; then
	muet "lexos.conf ou README.md introuvable : l'exemple n'a pas été comparé"
else
	SUITE="$(sed -n 's/^LEXOS_DEBIAN_SUITE="\([^"]*\)".*/\1/p' "$CONF" | head -1)"
	EXEMPLE="$(sed -n '/lex@lexos/,/^```$/p' "$LISEZ")"
	if [ -z "$SUITE" ]; then
		muet "LEXOS_DEBIAN_SUITE n'a pas pu être lu dans lexos.conf"
	elif [ -z "$EXEMPLE" ]; then
		non "l'exemple de lexfetch a disparu du README : le contrôle ne contrôle plus rien"
	else
		BASE_VUE="$(printf '%s' "$EXEMPLE" | sed -n 's/.*Base  *: *Debian \([a-z]*\).*/\1/p' | head -1)"
		if [ "$BASE_VUE" = "$SUITE" ]; then
			ok "l'exemple du README nomme la même base que lexos.conf ($SUITE)"
		else
			non "l'exemple du README dit « $BASE_VUE » alors que lexos.conf construit sur « $SUITE »"
		fi
		#  Le noyau : on vérifie la SÉRIE, pas le numéro exact (il change à
		#  chaque point de Debian, et l'exiger ferait rougir le banc pour rien).
		NOYAU_VU="$(printf '%s' "$EXEMPLE" | sed -n 's/.*Noyau  *: *\([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
		case "$NOYAU_VU" in
			6.1) non "l'exemple du README montre un noyau 6.1 — c'est celui de bookworm, pas de $SUITE" ;;
			"")  non "le noyau n'a pas pu être lu dans l'exemple du README" ;;
			*)   ok "…et un noyau de la série $NOYAU_VU, pas celui d'une Debian précédente" ;;
		esac
	fi
	grep -q "pas une capture d'une vraie machine" "$LISEZ" \
		&& ok "…et l'encadré dit que c'est un EXEMPLE : on ne le recopiera plus comme un relevé" \
		|| non "rien ne dit que l'exemple n'est pas une capture réelle — c'est ce qui a trompé une fois"

	#  ═══ ET LA VERSION MONTRÉE DOIT ÊTRE LIVRABLE ═══
	#  L'exemple a affiché « 610.43.02 » — la SEULE branche que le hook 0260
	#  écarte exprès (régression HDMI sur téléviseur). Un exemple qui montre
	#  précisément ce que la construction est bâtie pour ne jamais livrer.
	#  On lit la liste des branches écartées dans le hook, on ne la recopie pas.
	ECARTEES="$(sed -n 's/^BRANCHES_ECARTEES="\([^"]*\)".*/\1/p' \
		"$RACINE/config/hooks/normal/0260-lexos-nvidia.hook.chroot" | head -1)"
	VER_README="$(printf '%s' "$EXEMPLE" | sed -n 's/.*Pilote NV *: *\([0-9]*\)\..*/\1/p' | head -1)"
	if [ -z "$ECARTEES" ]; then
		muet "la liste des branches écartées n'a pas pu être lue dans le hook 0260"
	elif [ -z "$VER_README" ]; then
		muet "l'exemple du README n'affiche pas de ligne « Pilote NV »"
	elif printf '%s' " $ECARTEES " | grep -q " $VER_README "; then
		non "l'exemple du README montre la branche $VER_README, que le hook 0260 écarte exprès ($ECARTEES)"
	else
		ok "…et la version montrée est d'une branche que la cascade peut vraiment retenir (écartées : $ECARTEES)"
	fi
fi

# ===========================================================================
titre "7. LA PORTE DE SORTIE S'OUVRE VRAIMENT — par le chemin réel"
# ===========================================================================
#  ═══ UN VERROU SANS CLÉ ═══
#  Le hook fait échouer la construction, et annonçait pour remède
#  « LEXOS_NVIDIA_FACULTATIF=1 dans build.conf ou dans l'environnement ».
#  MESURÉ : les deux voies étaient FERMÉES.
#    · « sudo ./build.sh » — la seule façon documentée de construire — efface
#      l'environnement (« Defaults env_reset ») ;
#    · live-build lance les hooks .chroot sous « env -i », donc rien ne
#      traverse sans un config/environment.chroot, que ce dépôt n'a pas ;
#    · et build.sh RÉÉCRIT build.conf depuis un gabarit figé avant chaque
#      construction : la clé posée à la main disparaissait.
#  Le seul recours aurait été d'éditer le hook et de repousser — c'est-à-dire
#  de désactiver le contrôle, exactement ce qu'on voulait éviter.
#
#  ⚠ ET LE BANC NE LE VOYAIT PAS : la section 3 pose la variable DANS le shell
#  du hook. Elle éprouve la DÉCISION, ce qui reste juste ; elle n'éprouvait
#  pas le CHEMIN. On joue donc ici les vraies lignes de build.sh.
SOUPAPE="$RACINE/tests/aide/soupape-build.py"
if [[ ! -r "$SOUPAPE" ]]; then
	non "tests/aide/soupape-build.py manquant : le chemin de la soupape n'est pas éprouvé"
else
	AIDE="$(bash "$RACINE/build.sh" --help 2>&1 || true)"
	case "$AIDE" in
		*--sans-pilote*) ok "« build.sh --help » documente --sans-pilote" ;;
		*) non "le drapeau --sans-pilote n'est pas dans l'aide : personne ne le trouvera" ;;
	esac

	VU="$(python3 "$SOUPAPE" "$RACINE" 0 0 2>&1)"
	case "$VU" in
		"CONF=0 ENV=0") ok "sans drapeau : la clé part à 0 dans build.conf" ;;
		SANS_ANCRE) non "build.sh n'a plus les lignes qui portent la soupape : le contrôle ne contrôle rien" ;;
		*) non "sans drapeau, build.sh écrit « $VU » — attendu CONF=0 ENV=0" ;;
	esac

	VU="$(python3 "$SOUPAPE" "$RACINE" 1 1 2>&1)"
	case "$VU" in
		"CONF=1 ENV=1")
			ok "avec --sans-pilote : la clé arrive dans build.conf, que le hook du chroot SOURCE" ;;
		"CONF=0"*) non "--sans-pilote n'atteint pas build.conf : la porte reste fermée, le « exit 1 » est un verrou sans clé" ;;
		SANS_ANCRE) non "build.sh n'a plus les lignes qui portent la soupape" ;;
		*) non "avec drapeau, build.sh écrit « $VU » — attendu CONF=1 ENV=1" ;;
	esac

	#  Et le hook doit bien LIRE build.conf pour y trouver la clé : c'est le
	#  seul chemin qui traverse « env -i ».
	sed -n '1,60p' "$HOOK" | grep -q '\. /etc/lexos/build\.conf' \
		&& ok "…et le hook source bien build.conf en tête, donc il la voit" \
		|| non "le hook ne source plus build.conf : la clé n'arriverait nulle part"

	#  Le message d'échec doit nommer la commande qui MARCHE, pas la variable.
	grep -q -- '--sans-pilote' "$HOOK" \
		&& ok "…et le message d'échec nomme « --sans-pilote », pas une variable qui ne passe pas" \
		|| non "le message d'échec envoie encore poser une variable d'environnement : elle n'arrivera jamais"
fi

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
