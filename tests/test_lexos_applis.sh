#!/usr/bin/env bash
# =============================================================================
#  lexos-applis — lister et lancer les applications installées
# =============================================================================
#  Le banc construit une fausse arborescence de .desktop (XDG_DATA_HOME et
#  XDG_DATA_DIRS pointés dessus) et un faux PATH : l'outil ne voit QUE ce
#  qu'on lui montre. Aucune des applications de la machine n'entre dans la
#  mesure — sans ça les contrôles diraient des choses différentes selon le
#  coureur.
#
#  TROIS DÉFAUTS MESURÉS SUR LA VERSION D'ORIGINE, chacun a son contrôle :
#    · « --liste <mot> » rendait TOUTES les applications, filtre ignoré ;
#    · « lexos applis <mot> | … » aussi — la branche « sortie non-terminal »
#      imprimait la liste complète ;
#    · un « ; » NON protégé dans Exec lançait une seconde commande, parce
#      que la ligne partait dans « eval ».
#  Les deux premiers sont la pire sorte d'erreur : la commande répond, sans
#  message, avec une liste plausible qui n'est pas la réponse à la question.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-applis"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-applis introuvable ou non exécutable"; exit 1; }

APPS="$BANC/data/applications"
FAUXBIN="$BANC/bin"
mkdir -p "$APPS" "$FAUXBIN"

#  De faux binaires : l'outil masque une application dont le programme
#  n'est pas installé, et ce contrôle-là n'a de sens qu'avec un PATH fermé.
for b in vrai-editeur vrai-texte; do
	printf '#!/bin/sh\necho "lance: %s $*"\n' "$b" > "$FAUXBIN/$b"
	chmod +x "$FAUXBIN/$b"
done

desktop() { # desktop <fichier> <lignes…>
	local f="$APPS/$1"; shift
	{ echo "[Desktop Entry]"; printf '%s\n' "$@"; } > "$f"
}

lancer() { # lancer <arguments…> — PATH fermé, XDG pointé sur le banc
	env -i HOME="$BANC" PATH="$FAUXBIN:/usr/bin:/bin" \
		XDG_DATA_HOME="$BANC/data" XDG_DATA_DIRS="$BANC/data" \
		NO_COLOR=1 LC_ALL=C \
		bash "$OUTIL" "$@" 2>&1
}

# --- la scène commune -------------------------------------------------------
desktop "editeur.desktop" "Type=Application" "Name=Mon Editeur" \
	"Name[fr]=Mon Éditeur" "Comment=Ecrire du texte" \
	"Exec=vrai-editeur %U"
desktop "texte.desktop" "Type=Application" "Name=Console Texte" \
	"Comment=outil de bureau" "Terminal=true" "Exec=vrai-texte bonjour"
#  Une troisième, pour qu'un filtre puisse correspondre à PLUSIEURS : avec une
#  seule correspondance l'outil LANCE au lieu de lister, et c'est voulu. Mon
#  premier contrôle « filtre canalisé » choisissait justement un mot à une
#  seule correspondance : il mesurait donc le lancement, pas la liste, et
#  rougissait pour la mauvaise raison.
desktop "notes.desktop" "Type=Application" "Name=Bloc Notes" \
	"Comment=outil de bureau" "Exec=vrai-editeur"
desktop "absent.desktop" "Type=Application" "Name=Programme Absent" \
	"Exec=binaire-qui-nexiste-pas"
desktop "cache.desktop" "Type=Application" "Name=Entree Cachee" \
	"NoDisplay=true" "Exec=vrai-editeur"
desktop "pasappli.desktop" "Type=Directory" "Name=Pas Une Appli" \
	"Exec=vrai-editeur"

# =============================================================================
titre "1. Il ne liste que ce qui est VRAIMENT installé"
# =============================================================================
S="$(lancer --liste)"
grep -qx 'Mon Editeur' <<< "$S" \
	&& ok "une application dont le binaire existe est listée" \
	|| non "l'éditeur manque :\n$S"
grep -qx 'Programme Absent' <<< "$S" \
	&& non "une application dont le binaire est ABSENT est proposée" \
	|| ok "une application dont le binaire est absent est écartée"
grep -qx 'Entree Cachee' <<< "$S" \
	&& non "une entrée NoDisplay est proposée" \
	|| ok "une entrée NoDisplay reste cachée"
grep -qx 'Pas Une Appli' <<< "$S" \
	&& non "une entrée Type=Directory est proposée" \
	|| ok "une entrée qui n'est pas Type=Application est écartée"

S="$(lancer --liste --tout)"
grep -qx 'Entree Cachee' <<< "$S" \
	&& ok "« --tout » fait bien apparaître les entrées cachées" \
	|| non "« --tout » ne change rien :\n$S"

# =============================================================================
titre "2. LE FILTRE S'APPLIQUE — les deux défauts silencieux"
# =============================================================================
TOUS="$(lancer --liste | wc -l)"
FILTRE="$(lancer --liste editeur | wc -l)"
[ "$TOUS" -gt "$FILTRE" ] && [ "$FILTRE" -ge 1 ] \
	&& ok "« --liste <mot> » filtre ($FILTRE sur $TOUS), il ne rend plus tout" \
	|| non "« --liste <mot> » rend $FILTRE lignes sur $TOUS — filtre ignoré"

#  Sortie canalisée : bash ici n'a pas de terminal, donc ce simple appel
#  emprunte déjà la branche « non-terminal ». C'est exactement le chemin
#  qui rendait la liste entière.
CANAL="$(lancer bureau | wc -l)"
[ "$CANAL" -eq 2 ] && [ "$CANAL" -lt "$TOUS" ] \
	&& ok "un filtre canalisé rend les 2 correspondances, pas les $TOUS" \
	|| non "un filtre canalisé rend $CANAL lignes sur $TOUS — filtre ignoré"

S="$(lancer --liste editeur)"
grep -qx 'Mon Editeur' <<< "$S" \
	&& ok "et c'est bien la bonne application qui ressort" \
	|| non "le filtre ne rend pas l'application attendue :\n$S"

# =============================================================================
titre "3. La ligne Exec n'est JAMAIS rendue à un shell"
# =============================================================================
PREUVE="$BANC/PREUVE-INJECTION"
desktop "piege.desktop" "Type=Application" "Name=Piege Point Virgule" \
	"Terminal=true" "Exec=vrai-texte bonjour; touch $PREUVE"
rm -f "$PREUVE"
S="$(lancer 'piege point')"
[ -e "$PREUVE" ] \
	&& non "INJECTION : le « ; » non protégé a lancé une seconde commande" \
	|| ok "un « ; » non protégé dans Exec ne lance PAS de seconde commande"
grep -q 'bonjour; touch' <<< "$S" \
	&& ok "…et il reste un ARGUMENT, transmis tel quel au programme" \
	|| non "l'argument n'est pas arrivé entier :\n$S"

PREUVE2="$BANC/PREUVE-GUILLEMETS"
desktop "piege2.desktop" "Type=Application" "Name=Piege Guillemets" \
	"Terminal=true" "Exec=vrai-texte \"titre; touch $PREUVE2\""
rm -f "$PREUVE2"
S="$(lancer 'piege guillemets')"
[ -e "$PREUVE2" ] \
	&& non "INJECTION depuis un argument entre guillemets" \
	|| ok "un argument entre guillemets reste un seul argument"

#  GARDE STRUCTURELLE. On lit le CODE, pas la prose : les commentaires de
#  l'outil citent « eval » pour expliquer pourquoi il n'y en a plus, et un
#  contrôle qui rougirait là-dessus se déclencherait sur sa propre
#  justification — le piège que ce dépôt s'est déjà pris sept fois.
CODE="$(sed 's/#.*//' "$OUTIL")"
grep -qE '(^|[^[:alnum:]_])eval[[:space:]]' <<< "$CODE" \
	&& non "« eval » est réapparu dans le code de l'outil" \
	|| ok "aucun « eval » dans le code (commentaires exclus)"
grep -qE 'bash[[:space:]]+-c' <<< "$CODE" \
	&& non "« bash -c » est réapparu — même problème qu'eval" \
	|| ok "aucun « bash -c » non plus"

# =============================================================================
titre "4. Les codes de champ et les guillemets de la spécification"
# =============================================================================
desktop "codes.desktop" "Type=Application" "Name=Codes De Champ" \
	"Terminal=true" "Exec=vrai-texte %U debut %f fin %%"
S="$(lancer 'codes de champ')"
grep -q 'lance: vrai-texte debut fin %' <<< "$S" \
	&& ok "%%U et %%f sont retirés, %%%% redevient un %% littéral" \
	|| non "les codes de champ sont mal traités :\n$S"

desktop "espace.desktop" "Type=Application" "Name=Argument Avec Espaces" \
	"Terminal=true" "Exec=vrai-texte \"un deux trois\" quatre"
S="$(lancer 'argument avec')"
grep -q 'lance: vrai-texte un deux trois quatre' <<< "$S" \
	&& ok "un argument entre guillemets n'est pas coupé en trois" \
	|| non "les guillemets ne sont pas respectés :\n$S"

# =============================================================================
titre "5. Le nom suit la locale, et une application se lance"
# =============================================================================
S="$(env -i HOME="$BANC" PATH="$FAUXBIN:/usr/bin:/bin" \
	XDG_DATA_HOME="$BANC/data" XDG_DATA_DIRS="$BANC/data" \
	NO_COLOR=1 LC_ALL=fr_FR.UTF-8 LANG=fr_FR.UTF-8 \
	bash "$OUTIL" --liste 2>&1)"
grep -qx 'Mon Éditeur' <<< "$S" \
	&& ok "en locale française, « Name[fr] » est préféré" \
	|| non "la locale française n'est pas suivie :\n$S"

S="$(lancer 'console texte')"
grep -q 'lance: vrai-texte bonjour' <<< "$S" \
	&& ok "une application Terminal=true s'exécute ici même" \
	|| non "l'application texte ne s'est pas lancée :\n$S"

# =============================================================================
titre "6. Ce qu'il répond quand il ne trouve rien"
# =============================================================================
S="$(lancer zzz-rien-de-tel)"
grep -q 'aucune application installée ne correspond' <<< "$S" \
	&& ok "un mot introuvable donne un message clair" \
	|| non "aucun message sur un mot introuvable :\n$S"
lancer zzz-rien-de-tel >/dev/null 2>&1
[ "$?" -ne 0 ] \
	&& ok "…et un code de sortie non nul" \
	|| non "code de sortie 0 alors que rien n'a été trouvé"

# =============================================================================
titre "7. L'outil est joignable comme les autres"
# =============================================================================
grep -q 'applis|applications)' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos applis » existe dans le dispatcheur" \
	|| non "le dispatcheur ne connaît pas « applis »"
grep -q 'applis' <<< "$(sed -n '/^aide()/,/^}/p' "$RACINE/config/includes.chroot/usr/bin/lexos")" \
	|| grep -q '${A}applis${R}' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "…et il figure dans l'aide" \
	|| non "l'outil n'apparaît nulle part dans l'aide"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
