#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — le profil « vif » et l'arrondi de la RAM
# =============================================================================
#  CE QU'IL GARDE, ET POURQUOI ÇA VAUT UN BANC.
#
#  1. L'ARRONDI DE LA RAM. detect_profile() tronquait au lieu d'arrondir :
#     MemTotal est toujours inférieur à la capacité annoncée (noyau, microcode,
#     mémoire réservée au GPU intégré), donc 8 Go rapportait 7,66 Gio → 7 →
#     « medium ». AUCUNE machine de 8 Go n'atteignait « performant ». C'est le
#     genre de bogue qui ne fait jamais planter personne et que personne ne
#     remarque : il faut donc une machine pour le remarquer à notre place.
#
#  2. LA COHÉRENCE DE « VIF ». Le profil ne vaut que si ses deux moitiés
#     tiennent ensemble — processeur à fond ET zéro fioriture. Un jour,
#     quelqu'un remettra P_COMPOSITING=1 « pour que ce soit plus joli » et le
#     profil ne servira plus à rien. Le banc refuse ce changement-là.
#
#  3. zram ET SWAPPINESS VONT ENSEMBLE. Poser zram sans monter la swappiness
#     laisse le noyau ignorer le swap compressé. C'est une erreur naturelle,
#     parce que « swappiness basse = bon » est le conseil qu'on lit partout —
#     conseil qui vise le swap sur DISQUE.
#
#  Aucun de ces contrôles n'exige un bureau graphique ni les droits root : on
#  lit le script, on ne l'exécute pas.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERF="$RACINE/config/includes.chroot/usr/bin/lexos-perf"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
REGLAGES="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
POLKIT="$RACINE/config/includes.chroot/usr/share/polkit-1/actions/org.lexos.perf.policy"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0

ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

verifie() { # description, motif
	if grep -qE "$2" "$PERF"; then ok "$1"; else non "$1"; fi
}
refuse() { # description, motif qui ne doit PAS être là
	if grep -qE "$2" "$PERF"; then non "$1"; else ok "$1"; fi
}

# -----------------------------------------------------------------------------
titre "1. Le fichier est là et il se tient debout"
if [[ -r "$PERF" ]]; then ok "lexos-perf lisible"; else
	non "lexos-perf introuvable ($PERF)"; printf '\n'; exit 1
fi
if bash -n "$PERF" 2>/dev/null; then ok "syntaxe bash valide"
else non "erreur de syntaxe bash"; fi

# -----------------------------------------------------------------------------
titre "2. L'arrondi de la RAM"
refuse "la troncature 'ram_kb / 1024 / 1024' a disparu" \
       'ram_gb=\$\(\( *ram_kb */ *1024 */ *1024 *\)\)'
verifie "l'arrondi au demi-Gio est en place (524288)" \
        'ram_gb=\$\(\( *\( *ram_kb *\+ *524288 *\) */ *1048576 *\)\)'

#  On rejoue le calcul sur des tailles réelles plutôt que de croire le motif :
#  ce sont les VALEURS qui comptent, pas la forme de la ligne.
titre "3. Le calcul donne le bon palier sur du vrai matériel"
palier() { # kB -> Go arrondis
	printf '%s' "$(( ( $1 + 524288 ) / 1048576 ))"
}
for essai in "4008000:4:4 Go" "8039000:8:8 Go" "12210000:12:12 Go" \
             "16310000:16:16 Go" "32780000:31:32 Go"; do
	kb="${essai%%:*}"; reste="${essai#*:}"
	attendu="${reste%%:*}"; nom="${reste#*:}"
	obtenu="$(palier "$kb")"
	if [[ "$obtenu" == "$attendu" ]]; then
		ok "$nom → palier $obtenu"
	else
		non "$nom → $obtenu, attendu $attendu"
	fi
done

# -----------------------------------------------------------------------------
titre "4. Le profil « vif » existe partout où il doit"
verifie "reconnu par normalize()"        '\|vif\||vif\|'
verifie "un libellé dans label()"        'vif\).*printf'
verifie "un bloc dans load_profile()"    '^[[:space:]]*vif\)'

titre "5. « vif » tient ses deux promesses"
bloc="$(sed -n '/^[[:space:]]*vif)/,/;;/p' "$PERF")"
verifie_bloc() { # description, motif
	if grep -qE "$2" <<< "$bloc"; then ok "$1"; else non "$1"; fi
}
verifie_bloc "gouverneur 'performance'"          'P_GOVERNOR="performance"'
verifie_bloc "turbo débloqué (P_NO_TURBO=0)"     'P_NO_TURBO=0'
verifie_bloc "composition coupée"                'P_COMPOSITING=0'
verifie_bloc "effets CRT coupés"                 'P_CRT="off"'
verifie_bloc "zoom du dock coupé"                'P_DOCK_ZOOM=false'
verifie_bloc "vignettes coupées"                 'P_THUMBNAILS=0'

titre "6. zram et swappiness vont ensemble"
zram="$(grep -oE 'P_ZRAM=[0-9]+' <<< "$bloc" | head -1 | cut -d= -f2)"
swap="$(grep -oE 'P_SWAPPINESS=[0-9]+' <<< "$bloc" | head -1 | cut -d= -f2)"
if [[ -n "$zram" && "$zram" -gt 0 ]]; then
	ok "zram activé (${zram} %)"
	if [[ -n "$swap" && "$swap" -ge 80 ]]; then
		ok "swappiness à $swap — assez haute pour que le zram serve"
	else
		non "swappiness à ${swap:-?} : trop basse, le noyau ignorera le zram"
	fi
else
	non "zram désactivé dans « vif » — c'est pourtant la moitié du profil"
fi

# -----------------------------------------------------------------------------
titre "7. Les profils existants n'ont pas bougé"
for p in petit medium performant max; do
	if grep -qE "^[[:space:]]*${p}\)" "$PERF"; then ok "« $p » toujours là"
	else non "« $p » a disparu"; fi
done
for p in performant max; do
	b="$(sed -n "/^[[:space:]]*${p})/,/;;/p" "$PERF")"
	if grep -qE 'P_ZRAM=0' <<< "$b"; then ok "« $p » garde P_ZRAM=0"
	else non "« $p » ne devrait pas activer zram"; fi
done

# -----------------------------------------------------------------------------
titre "8. Le panneau des Paramètres connaît « vif »"
if [[ -r "$APPJS" ]]; then
	#  Frontière de mot obligatoire : « vif » se cache dans des mots français
	#  ordinaires (« vif » dans un commentaire, « vive »…), et un grep nu
	#  passait au vert sans que le profil soit déclaré nulle part.
	if grep -qE '"vif"|\bvif:' "$APPJS"; then ok "app.js déclare « vif »"
	else non "app.js ne connaît pas « vif » — la liste du panneau est incomplète"; fi
	if grep -qE 'PERF_RPM *=.*vif' "$APPJS"; then
		ok "PERF_RPM a une valeur pour « vif »"
	else
		non "PERF_RPM n'a pas de valeur pour « vif » : l'aiguille restera à zéro"
	fi
else
	non "app.js introuvable ($APPJS)"
fi

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
titre "9. « vif » est bien SUGGÉRÉ aux portables — la raison d'être du profil"
# -----------------------------------------------------------------------------
#  ═══ ON EXÉCUTE detect_profile(), ON NE RELIT PAS SA FORME ═══
#  Une mutation qui retirait la suggestion aux portables est restée VERTE sur
#  la première version de ce banc : tout y était vérifié SAUF le cœur de la
#  demande. Et le rejeu du calcul, plus haut, recopie la formule — il
#  éprouve la copie, pas le code.
#  On extrait donc les deux vraies fonctions et on les lance sur un faux
#  matériel, par les coutures LEXOS_PERF_MEMINFO et LEXOS_PERF_POWER.
FONCS="$(sed -n '/^on_battery()/,/^}/p;/^detect_profile()/,/^}/p' "$PERF")"
BANC_VIF="$(mktemp -d)"
trap 'rm -rf "$BANC_VIF"' EXIT

suggere() { # suggere <ram_kb> <coeurs> <portable:oui|non>
	rm -rf "$BANC_VIF/faux"; mkdir -p "$BANC_VIF/faux/power"
	printf 'MemTotal:       %s kB\n' "$1" > "$BANC_VIF/faux/meminfo"
	[ "$3" = "oui" ] && mkdir -p "$BANC_VIF/faux/power/BAT0"
	LEXOS_PERF_MEMINFO="$BANC_VIF/faux/meminfo" \
	LEXOS_PERF_POWER="$BANC_VIF/faux/power" \
		bash -c "nproc() { printf '%s' $2; }
$FONCS
detect_profile" 2>/dev/null
}

#  Les cas qui comptent, et pourquoi chacun est là.
for CAS in \
	"2000000:4:oui:petit:2 Go, portable" \
	"8039000:2:oui:petit:8 Go mais 2 fils — les cœurs priment" \
	"4008000:4:oui:medium:4 Go, portable" \
	"8039000:4:oui:vif:8 Go portable — LE cas qui a motivé le profil" \
	"8039000:4:non:performant:8 Go en tour — elle garde performant" \
	"12210000:4:oui:vif:12 Go portable" \
	"16310000:8:non:max:16 Go, tour" \
	"32780000:8:oui:max:32 Go, portable puissant" \
; do
	KB="${CAS%%:*}"; R1="${CAS#*:}"
	COEURS="${R1%%:*}"; R2="${R1#*:}"
	BAT="${R2%%:*}"; R3="${R2#*:}"
	ATTENDU="${R3%%:*}"; NOM="${R3#*:}"
	VU="$(suggere "$KB" "$COEURS" "$BAT")"
	if [ "$VU" = "$ATTENDU" ]; then
		ok "$NOM → $VU"
	else
		non "$NOM → « $VU », attendu « $ATTENDU »"
	fi
done

# -----------------------------------------------------------------------------
titre "10. Les deux listes de profils disent la même chose"
# -----------------------------------------------------------------------------
#  ═══ LE BOGUE QUI A MOTIVÉ CETTE SECTION ═══
#  PERFS, dans settings.py, valait { petit, medium, performant, max }. « vif »
#  y manquait. ⚠ CETTE NOTE A DIT « et nulle part ailleurs » PENDANT DES
#  SEMAINES, et c'était faux trois fois : il manquait aussi dans volet.py
#  (section 15), dans lexos-game (section 16) et dans la complétion bash.
#  Une phrase qui dit « nulle part ailleurs » porte sur tout le dépôt : elle
#  se vérifie, ou elle ne s'écrit pas. Le bouton partait, la réponse revenait
#  « profil inconnu », et le seul profil que detect_profile() RECOMMANDE à un
#  portable de 8 Go était le seul qu'on refusait de lui appliquer.
#
#  ON EXTRAIT LES DEUX LISTES ET ON LES COMPARE. Chercher « vif » dans
#  settings.py aurait été vert dès le premier commentaire qui le nomme : ce
#  fichier en contient plusieurs. On lit donc la ligne PERFS elle-même, et les
#  sorties de normalize() dans lexos-perf.
if [[ -r "$REGLAGES" ]]; then
	#  Côté page : le contenu de l'accolade de PERFS.
	COTE_PAGE="$(sed -n 's/^PERFS *= *{\(.*\)}.*/\1/p' "$REGLAGES" \
	            | tr -d '"' | tr ',' '\n' | tr -d ' ' | grep . | sort -u)"
	#  Côté outil : tout ce que normalize() peut IMPRIMER, c'est-à-dire les
	#  noms canoniques — pas les alias, qui sont à gauche du « ) ».
	#  normalize() écrit « printf 'vif' » — le nom canonique est le SEUL
	#  argument. Les alias (« snappy », « rapide-sobre »…) sont à gauche du
	#  « ) » et ne doivent pas entrer dans la comparaison : la page n'a pas à
	#  les connaître.
	COTE_OUTIL="$(sed -n "/^normalize()/,/^}/p" "$PERF" \
	             | sed -n "s/.*printf '\([a-z]*\)'.*/\1/p" | sort -u)"
	if [[ -z "$COTE_PAGE" ]]; then
		non "PERFS n'a pas pu être extrait de settings.py — le contrôle ne contrôle rien"
	elif [[ -z "$COTE_OUTIL" ]]; then
		non "normalize() n'a pas pu être extrait de lexos-perf — le contrôle ne contrôle rien"
	elif [[ "$COTE_PAGE" == "$COTE_OUTIL" ]]; then
		ok "les $(printf '%s' "$COTE_PAGE" | grep -c .) profils sont les mêmes des deux côtés"
	else
		non "PERFS et normalize() divergent :"
		diff <(printf '%s\n' "$COTE_OUTIL") <(printf '%s\n' "$COTE_PAGE") \
			| sed 's/^/      /' >&2
	fi
	#  Et le cas précis, nommé, pour que le message soit lisible s'il revient.
	if grep -qx 'vif' <<< "$COTE_PAGE"; then
		ok "settings.py accepte « vif »"
	else
		non "PERFS refuse « vif » : le bouton rendra « profil inconnu »"
	fi
else
	non "settings.py introuvable ($REGLAGES)"
fi

# -----------------------------------------------------------------------------
titre "11. Le plan système peut demander son mot de passe depuis une fenêtre"
# -----------------------------------------------------------------------------
#  sudo demande le mot de passe SUR UN TERMINAL. Depuis les Paramètres il n'y
#  en a pas : sudo renonce, et le bouton « ne fait rien ». La règle polkit rend
#  la demande possible dans une fenêtre — c'est la voie de LexOS Boost.
if [[ -r "$POLKIT" ]]; then
	ok "la règle polkit existe"
	if command -v python3 >/dev/null 2>&1; then
		if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" \
		           "$POLKIT" 2>/dev/null; then
			ok "elle est du XML bien formé"
		else
			non "XML mal formé : polkitd l'ignorera en silence"
		fi
	fi
	if grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/bin/lexos-perf<' "$POLKIT"; then
		ok "elle désigne bien /usr/bin/lexos-perf"
	else
		non "l'annotation exec.path ne désigne pas /usr/bin/lexos-perf"
	fi
else
	non "org.lexos.perf.policy manquant : le plan système restera muet en fenêtre"
fi
refuse "plus de « sudo \$0 » en dur : le choix passe par elevateur()" \
       'sudo "\$0" apply-system'
verifie "elevateur() existe"                     '^elevateur\(\)'
verifie "self_path() rend un chemin absolu"      '^self_path\(\)'
verifie "la couture de banc LEXOS_ELEVATEUR est là" 'LEXOS_ELEVATEUR'

#  ═══ ON EXÉCUTE LE CHOIX, ON NE RELIT PAS SA FORME ═══
#  Un faux sudo et un faux pkexec, un PATH qui ne contient qu'eux, et on
#  demande à elevateur() ce qu'il choisit. Aucun mot de passe n'est demandé à
#  personne : les deux faux outils rendent 0 sans rien faire.
BANC_ELEV="$(mktemp -d)"
trap 'rm -rf "$BANC_VIF" "$BANC_ELEV"' EXIT
mkdir -p "$BANC_ELEV/bin"
FONCS_ELEV="$(sed -n '/^elevateur()/,/^}/p' "$PERF")"
pose() { rm -f "$BANC_ELEV/bin/sudo" "$BANC_ELEV/bin/pkexec"
         for n in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$BANC_ELEV/bin/$n"
                           chmod +x "$BANC_ELEV/bin/$n"; done; }
#  ═══ LE PATH DOIT ÊTRE RÉDUIT AU FAUX RÉPERTOIRE ═══
#  Sinon le vrai /usr/bin/pkexec de la machine répond à la place du nôtre, et
#  le banc mesure la machine au lieu de mesurer le code. Attrapé ici même :
#  « sudo seul » rendait « pkexec » tant que le vrai PATH suivait derrière.
#  bash, lui, est appelé par son chemin absolu — il n'est pas dans le faux
#  répertoire, et le mettre dans le PATH d'essai ferait revenir le défaut.
#
#  On écrit la fonction dans un fichier plutôt que de la passer à « bash -c » :
#  ses commentaires sont en français et contiennent des apostrophes, qui
#  refermaient la chaîne au milieu.
printf '%s\nelevateur\n' "$FONCS_ELEV" > "$BANC_ELEV/choix.sh"
choix() { env -i PATH="$BANC_ELEV/bin" "$BASH" "$BANC_ELEV/choix.sh" < /dev/null; }
choix_tty() {
	script -qec "env -i PATH=$BANC_ELEV/bin $BASH $BANC_ELEV/choix.sh" /dev/null \
		2>/dev/null | tr -d '\r\n'
}
attend() { # description, obtenu, attendu
	if [[ "$2" == "$3" ]]; then ok "$1 → ${2:-（rien）}"; else non "$1 → « $2 », attendu « $3 »"; fi
}
pose sudo pkexec; attend "sans terminal, les deux présents" "$(choix)" "pkexec"
if command -v script >/dev/null 2>&1; then
	pose sudo pkexec
	attend "avec terminal, les deux présents" "$(choix_tty)" "sudo"
else
	ok "avec terminal : « script » absent de cette machine, contrôle sauté"
fi
pose pkexec;      attend "sans sudo"        "$(choix)" "pkexec"
pose sudo;        attend "sans pkexec"      "$(choix)" "sudo"
pose;             attend "aucun des deux"   "$(choix)" ""

# -----------------------------------------------------------------------------
titre "12. Un plan système refusé n'emporte plus le plan session"
# -----------------------------------------------------------------------------
#  ═══ CE QUE CETTE SECTION EMPÊCHE DE REVENIR ═══
#  Il y avait « || die » : un mot de passe refusé et on abandonnait TOUT, y
#  compris la composition, les effets CRT, le zoom du dock et les vignettes,
#  qui ne demandent aucun droit. Sur la machine d'Alex, « vif » n'éteignait
#  donc même pas la composition — la moitié la plus visible du profil.
refuse "le « die » sur le plan système a disparu" \
       'apply-system "\$PROFILE" \|\| die'
#  ═══ CE CONTRÔLE ÉTAIT CREUX, ET LA MUTATION L'A DIT ═══
#  Première version : « ^[[:space:]]*[[ "$SCOPE" != "system" ]] && apply_user »
#  sur tout le fichier. Or cette ligne existe DEUX fois — dans set_profile, et
#  dans la branche « apply ) » du répartiteur, à deux tabulations. Remettre
#  apply_user à l'intérieur du bloc système laissait donc l'autre satisfaire le
#  motif, et le banc restait vert sur exactement la régression qu'il surveille.
#
#  On lit maintenant le corps de set_profile SEUL, et on exige UNE SEULE
#  tabulation : c'est le premier niveau de la fonction. Deux tabulations ou
#  plus voudraient dire « imbriqué dans le if », c'est-à-dire le défaut.
#  LA TABULATION PASSE PAR printf, PAS PAR LE MOTIF. « \t » n'est pas une
#  échappée de grep -E : GNU grep y lit un « t » ordinaire, et le motif ne
#  correspondait donc à rien — le contrôle rougissait sur du code juste. Même
#  famille que le « \Q\E » d'un autre banc, qui n'existe qu'en PCRE.
CORPS_SP="$(sed -n '/^set_profile() {/,/^}/p' "$PERF")"
MOTIF_AU="$(printf '^\t\\[\\[ "\\$SCOPE" != "system" \\]\\] && apply_user')"
if grep -qE "$MOTIF_AU" <<< "$CORPS_SP"; then
	ok "dans set_profile, apply_user est au premier niveau — hors du bloc système"
else
	non "dans set_profile, apply_user est imbriqué (ou absent) : un refus l'emporterait encore"
fi

#  On le JOUE, sous un uid quelconque, avec un faux élévateur qui ÉCHOUE.
BANC_REF="$BANC_ELEV/refus"; mkdir -p "$BANC_REF/bin" "$BANC_REF/home"
printf '#!/bin/sh\necho "Request dismissed" >&2\nexit 126\n' > "$BANC_REF/bin/refus"
chmod +x "$BANC_REF/bin/refus"
if [[ "$EUID" -ne 0 ]]; then
	SORTIE="$(HOME="$BANC_REF/home" XDG_CONFIG_HOME="$BANC_REF/home/.config" \
		PATH="$BANC_REF/bin:$PATH" LEXOS_ELEVATEUR=refus \
		DISPLAY= WAYLAND_DISPLAY= \
		bash "$PERF" vif 2>/dev/null)"; CODE=$?
	if [[ "$CODE" -ne 0 ]]; then
		ok "l'échec du plan système se voit dans le code de sortie ($CODE)"
	else
		non "code 0 alors que le plan système a été refusé — la page croira à un succès"
	fi
	if [[ -r "$BANC_REF/home/.config/lexos/perf" ]]; then
		ok "le plan session s'est appliqué quand même ($(cat "$BANC_REF/home/.config/lexos/perf"))"
	else
		non "le plan session n'a rien écrit : le refus l'a encore emporté"
	fi
	#  LA DERNIÈRE LIGNE DE stdout EST CE QUE LA PAGE AFFICHE. settings.py,
	#  _run() : « sortie = (stdout or stderr) », puis « splitlines()[-1] ».
	#  Dès que stdout contient quelque chose — et apply_user vient d'écrire —
	#  stderr est JETÉ. Un motif posé seulement sur stderr n'arriverait jamais
	#  à l'écran. Ce contrôle tient les deux bouts ensemble.
	DERNIERE="$(printf '%s\n' "$SORTIE" | grep . | tail -1)"
	if [[ "$DERNIERE" == *"plan système refusé"* ]]; then
		ok "le motif est la dernière ligne de stdout — la page pourra l'afficher"
	else
		non "dernière ligne de stdout : « $DERNIERE » — la page dira « commande refusée »"
	fi
else
	ok "lancé en root : le chemin d'élévation ne s'exerce pas, contrôle sauté"
	ok "(relancer ce banc sous un compte ordinaire pour l'éprouver)"
fi
#  Et le lecteur, côté Python, doit bien être celui qu'on suppose.
if grep -q 'sortie = (r.stdout or r.stderr)' "$REGLAGES"; then
	ok "settings.py lit toujours « (stdout or stderr) » — l'hypothèse tient"
else
	non "settings.py ne lit plus « (stdout or stderr) » : revoir où lexos-perf écrit son motif"
fi
#  LES DEUX MOITIÉS D'UNE MÊME PHRASE. act_perf() n'ajoute son message sur
#  l'agent polkit que s'il RECONNAÎT la phrase de lexos-perf. Changer l'une
#  sans l'autre ne casse rien de visible : le message cesse simplement
#  d'apparaître, en silence. On les compare donc ici.
PHRASE='plan système refusé'
if grep -qF "$PHRASE" "$PERF" && grep -qF "$PHRASE" "$REGLAGES"; then
	ok "lexos-perf écrit « $PHRASE » et settings.py le reconnaît"
else
	non "« $PHRASE » n'est plus des deux côtés : le message sur l'agent polkit ne sortira plus"
fi
#  ET IL NE DOIT PAS SORTIR À TORT. Un profil refusé pour une autre raison —
#  outil absent, /etc non inscriptible — ne doit pas envoyer chercher un agent
#  polkit. La garde est ce filtre-là.
if grep -q 'in (r.get("erreur") or "")' "$REGLAGES"; then
	ok "le message n'est ajouté que sur CETTE cause, pas sur n'importe quel échec"
else
	non "act_perf() met le message du mot de passe sur tout échec, même sans rapport"
fi

# -----------------------------------------------------------------------------
titre "13. L'aiguille balaie au lieu de sauter"
# -----------------------------------------------------------------------------
#  La transition CSS existait depuis toujours et n'a jamais joué : setPerf()
#  passait par rendSection(), qui refait « content.innerHTML = … ». Le <g
#  class="needle"> était détruit puis recréé DÉJÀ tourné à sa valeur
#  d'arrivée — et une transition n'interpole qu'entre deux valeurs
#  successives d'un même élément.
if [[ -r "$APPJS" ]]; then
	#  ═══ PAS DE TUYAU VERS grep -q, ET ICI ÇA COMPTE DOUBLE ═══
	#  grep -q ferme le tuyau au premier résultat ; sous « pipefail », sed
	#  reçoit une erreur d'écriture et TOUT le tuyau échoue alors que le
	#  motif A ÉTÉ TROUVÉ. Ce contrôle-ci est INVERSÉ — « si rendSection est
	#  là, rougis » — donc la course y donnerait un faux VERT sur exactement
	#  la régression qu'il surveille. La substitution de processus sort sed
	#  du tuyau : son code ne compte plus dans PIPESTATUS.
	if grep -qE 'async function setPerf' "$APPJS" && \
	   grep -q 'rendSection()' < <(sed -n '/^async function setPerf/,/^}/p' "$APPJS"); then
		non "setPerf() reconstruit encore la section : l'aiguille sautera"
	else
		ok "setPerf() ne reconstruit plus la section"
	fi
	if grep -qE 'querySelector\("\.needle"\)|querySelector\(.\.needle.\)' "$APPJS"; then
		ok "l'aiguille EXISTANTE est retrouvée puis retournée"
	else
		non "personne ne va chercher le <g class=\"needle\"> déjà en place"
	fi
	if grep -qE '\belse\b' < <(sed -n '/^async function setPerf/,/^}/p' "$APPJS"); then
		ok "setPerf() lit la réponse au lieu de la jeter"
	else
		non "setPerf() jette encore l'échec : un refus resterait sans message"
	fi
else
	non "app.js introuvable ($APPJS)"
fi

# -----------------------------------------------------------------------------
titre "14. Le jeu d'icônes figées est parti en entier"
# -----------------------------------------------------------------------------
#  branding/icon-perf-*.svg : quatre cadrans DESSINÉS À LA MAIN, pour quatre
#  profils sur cinq — « vif » n'en a jamais eu. Rien ne les référençait : ni
#  lexos-theme-gen (sa liste d'icônes teintées est fixe et ne les nomme pas),
#  ni un .desktop, ni un hook. Ils partaient pourtant sur chaque ISO, puisque
#  build.sh recopie branding/*.svg en entier. Le compte-tours de la page est
#  un VRAI cadran en SVG, calculé — c'est lui qui les a remplacés.
RESTES="$(find "$RACINE/branding" -maxdepth 1 -name 'icon-perf-*.svg' 2>/dev/null | wc -l)"
if [[ "$RESTES" -eq 0 ]]; then
	ok "aucun icon-perf-*.svg ne traîne plus dans branding/"
else
	non "$RESTES icon-perf-*.svg subsistent — jeu incomplet, embarqué pour rien"
fi


# -----------------------------------------------------------------------------
titre "15. LE VOLET connaît les mêmes cinq profils — et n'en invente aucun"
# -----------------------------------------------------------------------------
#  ═══ CE BANC A DÉJÀ LAISSÉ PASSER « VIF » UNE FOIS ═══
#  La section 10 compare settings.py à lexos-perf, et le commentaire de
#  settings.py affirmait que « vif manquait ici, et NULLE PART AILLEURS ».
#  C'était faux : il manquait AUSSI dans le volet — PERF_LABEL n'avait que
#  quatre entrées — et ce banc ne regardait pas ce fichier-là, donc personne
#  ne l'a vu. Une phrase qui dit « nulle part ailleurs » est une affirmation
#  sur tout le dépôt : elle se vérifie, ou elle ne s'écrit pas.
#
#  ET LE SYMPTÔME ÉTAIT LE PIRE DE TOUS. _perf_etat() rendait « medium » sur
#  un profil qu'il ne connaissait pas. Pas une tuile grisée : une tuile qui
#  AFFIRME « Médium » sur une machine réglée en « vif ». Une valeur inventée,
#  exactement ce que le jeton _INCONNU du volet existe pour interdire — et
#  « vif » est justement ce que detect_profile() recommande à un portable,
#  donc à la machine d'Alex. On MESURE donc le comportement, on ne relit pas
#  la forme des listes.
VOLET_PY="$RACINE/config/includes.chroot/usr/lib/lexos/volet.py"
if [[ ! -r "$VOLET_PY" ]]; then
	non "volet.py introuvable ($VOLET_PY)"
elif ! command -v python3 >/dev/null 2>&1; then
	non "python3 absent : le comportement du volet n'a pas été mesuré"
else
	BANC_VOLET="$(mktemp -d)"
	FAUX_PERF="$BANC_VOLET/bin"; mkdir -p "$FAUX_PERF"
	cat > "$FAUX_PERF/lexos-perf" <<'OUTIL'
#!/bin/sh
printf '%s\n' "$1" > "$LEXOS_BANC_PROFIL"
OUTIL
	chmod +x "$FAUX_PERF/lexos-perf"

	VOLET_VU="$(LEXOS_BANC_PROFIL="$BANC_VOLET/demande" \
	            python3 - "$RACINE" "$FAUX_PERF" "$BANC_VOLET" <<'VOLET_PY_FIN' 2>&1
import importlib.util, os, sys
RACINE, BIN, BANC = sys.argv[1:4]
LIB = RACINE + "/config/includes.chroot/usr/lib/lexos"
os.environ["PATH"] = BIN
os.environ["XDG_CONFIG_HOME"] = BANC
sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

#  1. Les listes du volet, telles que le module les expose.
print("LABEL " + ",".join(sorted(m.PERF_LABEL)))
print("ORDRE " + ",".join(m.PERF_ORDRE))

def grille(valeur):
    """La grille telle que la page la recevrait, avec « perf » déjà en cache."""
    m._CACHE.perime()
    m._CACHE.lire({"perf": lambda: valeur}, 2)
    return m.etat("rapides")["rapides"]

g = grille("profil-que-personne-ne-connait")
print("INCONNU label=%r grise=%r" % (g["perfLabel"], "perf" in g["inconnu"]))
g = grille("vif")
print("VIF label=%r grise=%r" % (g["perfLabel"], "perf" in g["inconnu"]))

#  2. Le clic. On remplace la LECTURE (qui vise /etc/lexos/performance, hors
#     de portée d'un banc) et on regarde ce que l'action DEMANDE vraiment au
#     faux lexos-perf.
#     ⚠ ON ENVELOPPE LES DEUX APPELS. Sans ça, une mutation qui fait LEVER
#     l'action tuait le script du banc, et le contrôle se plaignait de « n'a
#     pas pu être éprouvé » : un rouge vrai, mais qui ne dit pas ce qui s'est
#     passé. Une exception ici, c'est une erreur 500 dans le volet — on veut
#     le lire en toutes lettres.
m._perf_etat = lambda: "vif"
try:
    m.act_rapides_perf()
    try:
        demande = open(os.environ["LEXOS_BANC_PROFIL"], encoding="utf-8").read().strip()
    except OSError:
        demande = "<rien>"
except Exception as e:                                  # noqa: BLE001
    demande = "leve=%s" % type(e).__name__
print("APRES_VIF " + demande)

m._perf_etat = lambda: None
try:
    r = m.act_rapides_perf()
    print("SANS_PROFIL ok=%r erreur=%r" % (r.get("ok"), r.get("erreur", "")))
except Exception as e:                                  # noqa: BLE001
    print("SANS_PROFIL leve=%s: %s" % (type(e).__name__, e))
VOLET_PY_FIN
)"
	rm -rf "$BANC_VOLET"

	lit() { printf '%s\n' "$VOLET_VU" | grep "^$1 " | sed "s/^$1 //"; }

	#  Les noms canoniques, repris de la section 10 : la source de vérité est
	#  normalize() dans lexos-perf, pas une liste écrite à la main ici.
	CANON="$(sed -n "/^normalize()/,/^}/p" "$PERF" \
	        | sed -n "s/.*printf '\([a-z]*\)'.*/\1/p" | sort -u | tr '\n' ',' | sed 's/,$//')"
	VU_LABEL="$(lit LABEL)"
	if [ -z "$VU_LABEL" ]; then
		non "volet.py n'a pas pu être importé : $(printf '%s' "$VOLET_VU" | tail -2 | tr '\n' ' ')"
	elif [ "$VU_LABEL" = "$CANON" ]; then
		ok "PERF_LABEL du volet = les profils de normalize() ($CANON)"
	else
		non "PERF_LABEL du volet diverge de lexos-perf : « $VU_LABEL » contre « $CANON »"
	fi

	VU_ORDRE="$(lit ORDRE)"
	if [ "$(printf '%s' "$VU_ORDRE" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')" = "$CANON" ]; then
		ok "le cycle du clic parcourt les cinq profils ($VU_ORDRE)"
	else
		non "le cycle du volet n'a pas les mêmes profils : « $VU_ORDRE » contre « $CANON »"
	fi

	#  ═══ LE CONTRÔLE QUI AURAIT ATTRAPÉ LE DÉFAUT ═══
	case "$(lit INCONNU)" in
		"label='Inconnu' grise=True")
			ok "un profil inconnu grise la tuile et dit « Inconnu »" ;;
		"label='Médium'"*)
			non "un profil inconnu s'affiche « Médium » : une valeur INVENTÉE, et le clic partira de là" ;;
		"") non "la grille n'a pas pu être lue pour un profil inconnu" ;;
		*)  non "un profil inconnu donne $(lit INCONNU) — attendu label='Inconnu' grise=True" ;;
	esac

	case "$(lit VIF)" in
		"label='Vif' grise=False") ok "« vif » s'affiche « Vif », tuile vivante" ;;
		"") non "la grille n'a pas pu être lue pour « vif »" ;;
		*)  non "« vif » donne $(lit VIF) — attendu label='Vif' grise=False" ;;
	esac

	#  Le cycle, mesuré sur ce que l'action DEMANDE au vrai outil.
	case "$(lit APRES_VIF)" in
		performant) ok "un clic depuis « vif » demande « performant » — l'ordre de lexos-perf" ;;
		"<rien>")   non "un clic depuis « vif » ne lance rien : le profil n'est pas dans le cycle" ;;
		leve=*)     non "un clic depuis « vif » LÈVE ($(lit APRES_VIF)) : « vif » n'est pas dans PERF_ORDRE" ;;
		*)          non "un clic depuis « vif » demande « $(lit APRES_VIF) », attendu « performant »" ;;
	esac

	case "$(lit SANS_PROFIL)" in
		"ok=False erreur="*inconnu*) ok "…et sans profil lisible, une phrase claire au lieu d'une erreur 500" ;;
		leve=*) non "sans profil lisible, l'action LÈVE ($(lit SANS_PROFIL)) : c'est une erreur 500 dans le volet, pas un refus" ;;
		"") non "l'action n'a pas pu être éprouvée sans profil" ;;
		*)  non "sans profil lisible, l'action rend $(lit SANS_PROFIL) — attendu un refus explicite" ;;
	esac

	#  ═══ ET LE CORPS DE _perf_etat() EXÉCUTÉ POUR DE VRAI ═══
	#  ⚠ CE BANC A LAISSÉ PASSER LA MOITIÉ DU CORRECTIF. Les points ci-dessus
	#  éprouvent les LISTES et l'affichage, mais tous court-circuitent le
	#  lecteur : deux le remplacent (« m._perf_etat = lambda: … »), les deux
	#  autres pré-remplissent le cache, donc le collecteur n'est jamais lancé.
	#  MESURÉ : remettre le « else "medium" » dans _perf_etat() laissait 31
	#  points sur 31 au vert, dans ce banc et dans tous les autres du dépôt.
	#  Un banc qui verdit sur le défaut qu'il raconte coûte plus cher que pas
	#  de banc, parce qu'il rassure.
	#  On lui donne donc un vrai fichier à lire, par la couture
	#  LEXOS_PERF_ETAT — comme lexos-perf le fait déjà avec LEXOS_PERF_MEMINFO.
	BANC_PROFIL="$(mktemp -d)"
	CORPS="$(LEXOS_PERF_ETAT="$BANC_PROFIL/performance" \
	         python3 - "$RACINE" "$BANC_PROFIL" <<'CORPS_PY' 2>&1
import importlib.util, os, pathlib, sys
RACINE, BANC = sys.argv[1:3]
LIB = RACINE + "/config/includes.chroot/usr/lib/lexos"
FICHIER = pathlib.Path(BANC) / "performance"
os.environ["LEXOS_PERF_ETAT"] = str(FICHIER)
os.environ["XDG_CONFIG_HOME"] = BANC
sys.path.insert(0, LIB)
spec = importlib.util.spec_from_file_location("v", LIB + "/volet.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

if str(getattr(m, "PERF_FICHIER", "")) != str(FICHIER):
    print("PAS_DE_COUTURE %r" % (getattr(m, "PERF_FICHIER", None),))
    raise SystemExit

def essai(contenu):
    if contenu is None:
        FICHIER.unlink(missing_ok=True)
    else:
        FICHIER.write_text(contenu, encoding="utf-8")
    m._CACHE.perime()
    #  AUCUN pré-remplissage, aucun remplacement : c'est _perf_etat() qui est
    #  lancé par _de_front, comme dans le volet.
    g = m.etat("rapides")["rapides"]
    return "%r/%s/%s" % (m._perf_etat(), g["perfLabel"], "perf" in g["inconnu"])

print("VIF      " + essai("vif\n"))
print("INCONNU  " + essai("turbo\n"))
print("VIDE     " + essai(""))
print("ABSENT   " + essai(None))
CORPS_PY
)"
	rm -rf "$BANC_PROFIL"

	corps() { printf '%s\n' "$CORPS" | grep "^$1 " | sed "s/^$1  *//"; }
	verdict_corps() {   # verdict_corps <étiquette> <attendu> <phrase>
		local vu; vu="$(corps "$1")"
		if [ -z "$vu" ]; then
			muet_ou_non "$1"
		elif [ "$vu" = "$2" ]; then
			ok "$3"
		else
			non "$3 — mesuré : $vu (attendu : $2)"
		fi
	}
	muet_ou_non() {
		case "$CORPS" in
			PAS_DE_COUTURE*) non "volet.py n'expose pas la couture PERF_FICHIER : le corps de _perf_etat() reste intestable ($CORPS)" ;;
			*) non "« $1 » n'a pas pu être mesuré : $(printf '%s' "$CORPS" | tail -2 | tr '\n' ' ')" ;;
		esac
	}

	verdict_corps VIF     "'vif'/Vif/False"      "_perf_etat() lit « vif » dans le vrai fichier et la tuile l'affiche"
	verdict_corps INCONNU "None/Inconnu/True"    "…un profil qu'il ne connaît pas rend None, PAS « medium » — la tuile est grisée"
	verdict_corps VIDE    "None/Inconnu/True"    "…un fichier vide aussi"
	verdict_corps ABSENT  "None/Inconnu/True"    "…et un fichier absent aussi"
fi


# -----------------------------------------------------------------------------
titre "16. « VIF » N'EST OUBLIÉ NULLE PART — et cette fois on cherche partout"
# -----------------------------------------------------------------------------
#  ═══ TROIS FOIS LA MÊME FAUTE, DONT DEUX FOIS DANS LA CORRECTION ═══
#  La note de settings.py disait « vif manquait ici, et NULLE PART AILLEURS ».
#  Faux : il manquait aussi dans volet.py. Corrigée, elle a dit « ici et dans
#  le volet » — faux encore : il manquait AUSSI dans lexos-game, dans la
#  complétion bash, et dans le contrôle de lexos.conf de l'intégration
#  continue. Énumérer des endroits, c'est se tromper une fois de plus à chaque
#  correction. On CHERCHE, au lieu d'énumérer.
#
#  LA RÈGLE : dans tout ce qui part sur l'ISO, une ligne qui nomme « petit »,
#  « medium » ET « max » énumère les profils. Si « vif » n'y est pas, c'est un
#  oubli. (README et web-demo/ sont hors ISO : la démo est le modèle d'Alex,
#  pas du code livré — ils ne sont pas dans le périmètre.)
OUBLIS=""
for D in "$RACINE/config/includes.chroot/usr/bin" \
         "$RACINE/config/includes.chroot/usr/lib/lexos" \
         "$RACINE/config/includes.chroot/usr/share/lexos" \
         "$RACINE/config/includes.chroot/usr/share/bash-completion" \
         "$RACINE/.github/workflows"; do
	[ -e "$D" ] || continue
	TROUVE="$(grep -rIn 'petit' "$D" 2>/dev/null | grep 'medium' | grep 'max' | grep -v 'vif' || true)"
	[ -n "$TROUVE" ] && OUBLIS="$OUBLIS$TROUVE
"
done
if [ -z "$(printf '%s' "$OUBLIS" | grep . || true)" ]; then
	ok "aucune énumération de profils sans « vif » dans ce qui part sur l'ISO"
else
	non "« vif » manque dans une liste de profils livrée :"
	printf '%s\n' "$OUBLIS" | grep . | sed 's|'"$RACINE"'/||' | cut -c1-150 | sed 's/^/      /' >&2
fi

#  ═══ lexos-game : LA VALEUR INVENTÉE Y ÉTAIT ÉCRITE SUR LA MACHINE ═══
#  current_profile() rendait « medium » sur un fichier illisible — et cette
#  valeur REVIENT sur la machine à la fin de la partie (« lexos perf $prev »).
#  Ce n'est pas un libellé faux, c'est un réglage imposé.
#  Et son « case » ne connaissait que performant|max : un portable réglé en
#  « vif » — ce que detect_profile lui SUGGÈRE — se voyait pousser à
#  « performant », c'est-à-dire rallumer composition, effets TV, zoom du dock
#  et vignettes, pour zéro gain processeur (même gouverneur).
GAME="$RACINE/config/includes.chroot/usr/bin/lexos-game"
if [[ ! -r "$GAME" ]]; then
	non "lexos-game introuvable ($GAME)"
else
	BANC_GAME="$(mktemp -d)"
	#  On EXÉCUTE la vraie fonction, extraite du fichier.
	FONC="$(sed -n '/^current_profile()/,/^}/p' "$GAME")"
	lu() { PERF_STATE="$1" bash -c "$FONC
current_profile" 2>/dev/null; }
	printf 'vif\n' > "$BANC_GAME/p"
	[ "$(lu "$BANC_GAME/p")" = "vif" ] \
		&& ok "lexos-game lit le vrai profil quand le fichier est là" \
		|| non "lexos-game ne lit pas le profil : « $(lu "$BANC_GAME/p") »"
	VIDE="$(lu "$BANC_GAME/absent")"
	if [ -z "$VIDE" ]; then
		ok "…et rend le VIDE quand il ne peut pas lire, au lieu d'inventer « medium »"
	else
		non "lexos-game invente « $VIDE » sur un fichier illisible — et cette valeur est RÉÉCRITE sur la machine à la fin de la partie"
	fi

	#  Le « case » lui-même, exécuté avec des say/warn bouchonnés.
	CASE="$(sed -n '/case "\$prev" in/,/^	esac/p' "$GAME")"
	decide() { prev="$1" bash -c '
say()  { printf "SAY %s\n" "$*"; }
warn() { printf "WARN %s\n" "$*"; }
'"$CASE"'' 2>/dev/null | head -1; }
	case "$(decide vif)" in
		"SAY Profil déjà vif"*) ok "un portable réglé en « vif » est laissé tranquille" ;;
		"SAY Passage temporaire"*) non "lexos-game pousse un « vif » vers « performant » : zéro gain processeur, et il rallume composition, effets TV, zoom et vignettes" ;;
		*) non "le cas « vif » n'a pas pu être éprouvé : « $(decide vif) »" ;;
	esac
	case "$(decide '')" in
		"WARN Profil de performance illisible"*) ok "…et un profil illisible ne déclenche aucune bascule à restaurer" ;;
		"SAY "*) non "un profil illisible déclenche quand même une bascule : « $(decide '') »" ;;
		*) non "le cas du profil illisible n'a pas pu être éprouvé : « $(decide '') »" ;;
	esac
	case "$(decide medium)" in
		"SAY Passage temporaire"*) ok "…tandis qu'un profil sobre est bien poussé pour la partie" ;;
		*) non "un profil sobre n'est plus poussé : « $(decide medium) »" ;;
	esac
	rm -rf "$BANC_GAME"
fi

printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
