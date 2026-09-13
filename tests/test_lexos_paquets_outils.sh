#!/usr/bin/env bash
# =============================================================================
#  Sortir les applications de l'ISO sans emporter les outils de LexOS
# =============================================================================
#  ALEX : « on a toutes les applications téléchargées dans l'ISO — j'aimerais,
#  pour faire de la place, que les applications restent dans la Logithèque et
#  qu'on puisse les télécharger à partir de là. Là, elles sont toutes
#  téléchargées d'avance, ça prend la place pour rien. »
#
#  Quatre familles sont donc sorties de la construction : 46-studio, 50-dev,
#  60-full, 75-pro-gamer — environ 1,6 Go, les deux tiers de tout l'optionnel,
#  en 136 paquets.
#
#  ═══ LE DANGER, ET C'EST TOUT L'OBJET DE CE BANC ═══
#  Onze paquets de ces listes n'étaient pas des applications pour
#  l'utilisateur, mais des OUTILS QUE LEXOS APPELLE LUI-MÊME. Les sortir avec
#  le reste aurait cassé une fonction par paquet, en silence.
#
#  LE CAS QUI RÉSUME TOUT : « npm » vivait dans la liste « développement ».
#  C'est lui qui installe et met à jour Claude Code. Sortir la liste dev sans
#  le rapatrier aurait retiré Claude Code de l'ISO — précisément ce qu'Alex
#  demandait de GARDER dans la même phrase.
#
#  ═══ POURQUOI CE BANC EST ÉTROIT, ET PAS UNIVERSEL ═══
#  Un premier jet exigeait que TOUT outil appelé par LexOS soit dans l'ISO.
#  Il a relevé 181 outils et crié sur une soixantaine — parce que la moitié
#  de ces appels sont des « si l'outil est là, on s'en sert » parfaitement
#  volontaires (7z, adb, borg, clamscan…), et que LexOS s'appelle lui-même
#  (lexos, lexfetch) sans être un paquet Debian. Un garde-fou qui crie pour
#  rien finit ignoré, et c'est pire que pas de garde-fou du tout. On pose
#  donc la question PRÉCISE qui vient d'être dangereuse : parmi ce qu'on
#  RETIRE, y a-t-il quelque chose que LexOS appelle ?
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0250-lexos-optional.hook.chroot"
DIR="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages"
LOGI="$RACINE/config/includes.chroot/usr/bin/lexos-logitheque"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for f in "$HOOK" "$LOGI"; do
	[ -r "$f" ] || { non "$(basename "$f") introuvable"; echo; exit 1; }
done

SORTIES="46-studio.list 50-dev.list 60-full.list 75-pro-gamer.list"

# =============================================================================
titre "1. Les quatre familles sont bien SORTIES de la construction"
# =============================================================================
#  La vérité vit dans le hook, pas dans une copie qu'on oublierait de tenir à
#  jour : on lit BUREAU_COMPLET tel qu'il y est écrit.
INSTALLEES="$(sed -n '/^BUREAU_COMPLET="/,/"$/p' "$HOOK" | tr -d '\\' | tr ' ' '\n' | grep '\.list$' || true)"
[ -n "$INSTALLEES" ] || non "BUREAU_COMPLET est introuvable ou vide dans le hook 0250"

for L in $SORTIES; do
	if grep -qx "$L" <<< "$INSTALLEES"; then
		non "$L est encore installée d'avance — la place n'est pas rendue"
	else
		ok "$L n'est plus pré-installée"
	fi
done

# =============================================================================
titre "2. …mais leurs listes voyagent toujours dans l'ISO"
# =============================================================================
#  Sortir des applications sans laisser le moyen de les faire revenir serait
#  une perte, pas un gain. Les fichiers restent livrés : « lexos logitheque
#  famille studio » les réinstalle d'une commande.
for L in $SORTIES; do
	[ -r "$DIR/$L" ] \
		&& ok "$L est toujours livrée (la Logithèque peut la réinstaller)" \
		|| non "$L a disparu du dépôt — la famille serait irrécupérable"
done

# =============================================================================
titre "3. AUCUN outil de LexOS n'est parti avec les applications"
# =============================================================================
#  LE CONTRÔLE QUI COMPTE. On relève ce que le code de LexOS déclare
#  lui-même avoir besoin (« command -v X », « shutil.which("X") ») et on
#  vérifie qu'aucun de ces X ne se trouve UNIQUEMENT dans une liste sortie.
SORTIE_PY="$(python3 - "$RACINE" "$HOOK" "$DIR" <<'PY'
import glob, os, re, sys
racine, hook, dossier = sys.argv[1:4]

src = open(hook, encoding="utf-8").read()
installees = set()
for var in ("LISTS", "BUREAU_COMPLET"):
    m = re.search(rf'^{var}="(.*?)"\s*$', src, re.M | re.S)
    if m:
        installees |= {x for x in m.group(1).replace("\\\n", " ").split() if x.endswith(".list")}

def paquets(fichier):
    p = os.path.join(dossier, fichier)
    out = set()
    if not os.path.isfile(p):
        return out
    for ligne in open(p, encoding="utf-8"):
        ligne = ligne.strip()
        if ligne and not ligne.startswith("#"):
            for alt in ligne.split("|"):
                out.add(alt.split(":")[0].strip())
    return out

fournis = set()
for l in installees:
    fournis |= paquets(l)
for f in glob.glob(os.path.join(racine, "config/package-lists/*.list.chroot")):
    for ligne in open(f, encoding="utf-8"):
        ligne = ligne.strip()
        if ligne and not ligne.startswith("#"):
            fournis.add(ligne.split(":")[0].strip())

sorties = {"46-studio.list", "50-dev.list", "60-full.list", "75-pro-gamer.list"}
retires = set()
for l in sorties:
    retires |= paquets(l)

#  Ce que LexOS déclare appeler.
appels = {}
for pat in ("config/includes.chroot/usr/bin/*",
            "config/includes.chroot/usr/lib/lexos/*",
            "config/includes.chroot/usr/share/lexos/shell/*"):
    for f in glob.glob(os.path.join(racine, pat)):
        if not os.path.isfile(f):
            continue
        txt = open(f, errors="ignore", encoding="utf-8").read()
        for rx in (r'command -v ([A-Za-z0-9][A-Za-z0-9._+-]*)',
                   r'shutil\.which\(["\']([A-Za-z0-9][A-Za-z0-9._+-]*)["\']\)'):
            for m in re.finditer(rx, txt):
                appels.setdefault(m.group(1), set()).add(os.path.basename(f))

#  Nom du programme -> nom du paquet, pour les cas où ils diffèrent.
PAQUET = {"node": "nodejs", "batcat": "bat", "gamemoderun": "gamemode"}

perdus = []
for outil, ou in sorted(appels.items()):
    p = PAQUET.get(outil, outil)
    #  Le seul cas dangereux : LexOS l'appelle, il était dans une liste
    #  qu'on retire, et RIEN d'installé ne le fournit plus.
    if (p in retires or outil in retires) and not (p in fournis or outil in fournis):
        perdus.append(f"{outil} (utilisé par {', '.join(sorted(ou)[:3])})")

print("PERDUS=%d" % len(perdus))
for x in perdus:
    print("  - " + x)
PY
)"

NB="$(sed -n 's/^PERDUS=//p' <<< "$SORTIE_PY")"
if [ "${NB:-1}" = "0" ]; then
	ok "aucun outil appelé par LexOS n'a été emporté par la coupe"
else
	non "$NB outil(s) de LexOS ont disparu de l'ISO :"
	sed -n '/^  - /p' <<< "$SORTIE_PY" | while read -r l; do printf '        %s\n' "$l"; done
fi

# =============================================================================
titre "4. La liste de rapatriement existe et est installée"
# =============================================================================
grep -qx "85-outils-lexos.list" <<< "$INSTALLEES" \
	&& ok "85-outils-lexos.list est bien installée d'avance" \
	|| non "85-outils-lexos.list n'est pas dans BUREAU_COMPLET — les onze outils manqueraient"

[ -r "$DIR/85-outils-lexos.list" ] \
	&& ok "…et le fichier existe" || non "85-outils-lexos.list est déclarée mais absente du dépôt"

#  npm NOMMÉMENT : c'est lui qui installe Claude Code, et c'est le paquet
#  dont la perte serait passée le plus inaperçue — tout marche, sauf la mise
#  à jour de Claude Code, et seulement le jour où on en a besoin.
grep -qx "npm" "$DIR/85-outils-lexos.list" 2>/dev/null \
	&& ok "npm est rapatrié — Claude Code reste installable et à jour" \
	|| non "npm n'est pas rapatrié : Claude Code ne pourrait plus être installé ni mis à jour"

# =============================================================================
titre "5. La Logithèque sait réinstaller ces familles"
# =============================================================================
#  LA SORTIE EST CAPTURÉE UNE FOIS, PUIS RELUE — jamais « script | grep -q ».
#  Ce banc tourne sous « set -o pipefail », et « grep -q » ferme le tube dès
#  qu'il a trouvé : le script en amont reçoit alors SIGPIPE, le pipeline rend
#  141, et le « if » part dans la mauvaise branche EN CAS DE SUCCÈS. Quatre
#  contrôles verts se présentaient ainsi comme des échecs.
FAMILLES_VUES="$(NO_COLOR=1 LEXOS_OPTIONAL_DIR="$DIR" bash "$LOGI" familles 2>/dev/null || true)"

[ -n "$FAMILLES_VUES" ] \
	&& ok "« lexos logitheque familles » répond quelque chose" \
	|| non "« familles » ne rend rien — les contrôles suivants ne prouveraient rien"

for f in studio dev bureautique jeux; do
	grep -q "^  $f " <<< "$FAMILLES_VUES" \
		&& ok "« famille $f » est proposée" \
		|| non "la famille « $f » n'apparaît pas dans « lexos logitheque familles »"
done

#  ET LES COMPTES SONT VRAIS : une famille annoncée à « ? paquets » voudrait
#  dire que la liste n'est pas trouvée là où le script la cherche.
if grep -q "? paquets" <<< "$FAMILLES_VUES"; then
	non "au moins une famille affiche « ? paquets » — sa liste est introuvable"
else
	ok "chaque famille annonce un vrai nombre de paquets"
fi

#  Un nom inconnu doit être REFUSÉ, pas silencieusement ignoré.
INCONNUE="$(NO_COLOR=1 LEXOS_OPTIONAL_DIR="$DIR" bash "$LOGI" famille nexistepas 2>&1 || true)"
if grep -qi "inconnue" <<< "$INCONNUE"; then
	ok "une famille inconnue est refusée avec un message clair"
else
	non "« famille nexistepas » n'est pas refusée proprement"
fi

# =============================================================================
titre "6. Rien ne dort dans la liste de rapatriement"
# =============================================================================
#  LE CONTRÔLE 3 REGARDE DANS UN SEUL SENS : un outil appelé doit être
#  installé. Rien ne regardait l'autre sens — un paquet rapatrié « parce
#  qu'on croit que LexOS s'en sert ». Et le sens manquant coûtait :
#  « shellcheck » a dormi ici sur une justification fausse (« lexos theme
#  relit ses propres scripts »), 18,5 Mo dans chaque ISO, alors qu'AUCUNE
#  commande de LexOS ne l'appelle — les seules occurrences dans le code sont
#  des directives « # shellcheck disable=… », qui sont des annotations pour
#  l'outil, pas des appels. C'est ce contrôle-ci qui l'a trouvé.
#
#  On exige donc que chaque paquet d'ici soit VRAIMENT invoqué. La
#  correspondance nom-de-commande / nom-de-paquet est la même qu'au
#  contrôle 3 (node→nodejs, batcat→bat, gamemoderun→gamemode).
SORTIE_INV="$(python3 - "$RACINE" "$DIR" <<'PY'
import glob, os, re, sys
racine, dossier = sys.argv[1:3]

appels = {}
for pat in ("config/includes.chroot/usr/bin/*",
            "config/includes.chroot/usr/lib/lexos/*",
            "config/includes.chroot/usr/share/lexos/shell/*"):
    for f in glob.glob(os.path.join(racine, pat)):
        if not os.path.isfile(f):
            continue
        txt = open(f, errors="ignore", encoding="utf-8").read()
        for rx in (r'command -v ([A-Za-z0-9][A-Za-z0-9._+-]*)',
                   r'shutil\.which\(["\']([A-Za-z0-9][A-Za-z0-9._+-]*)["\']\)'):
            for m in re.finditer(rx, txt):
                appels.setdefault(m.group(1), set()).add(os.path.basename(f))

PAQUET = {"node": "nodejs", "batcat": "bat", "gamemoderun": "gamemode"}

#  Un paquet est « invoqué » si l'une de ses commandes l'est.
invoques = {}
for outil, ou in appels.items():
    invoques.setdefault(PAQUET.get(outil, outil), set()).update(ou)

rapatries = []
for ligne in open(os.path.join(dossier, "85-outils-lexos.list"), encoding="utf-8"):
    ligne = ligne.strip()
    if ligne and not ligne.startswith("#"):
        rapatries.append(ligne.split(":")[0].strip())

orphelins = [p for p in rapatries if p not in invoques]

print("NOMBRE=%d" % len(rapatries))
print("ORPHELINS=%d" % len(orphelins))
for p in orphelins:
    print("  - " + p)
PY
)"

NB_RAP="$(sed -n 's/^NOMBRE=//p' <<< "$SORTIE_INV")"
NB_ORP="$(sed -n 's/^ORPHELINS=//p' <<< "$SORTIE_INV")"

if [ "${NB_ORP:-1}" = "0" ]; then
	ok "les $NB_RAP paquets rapatriés sont tous vraiment appelés par LexOS"
else
	non "$NB_ORP paquet(s) rapatriés que RIEN dans LexOS n'appelle :"
	sed -n '/^  - /p' <<< "$SORTIE_INV" | while read -r l; do printf '        %s\n' "$l"; done
fi

#  ET LE COMPTE ÉCRIT DANS LA PROSE DIT VRAI. Il avait déjà dérivé : trois
#  fichiers annonçaient « douze » quand la liste en portait onze. Un chiffre
#  faux dans un commentaire est une petite chose ; c'est aussi ce qu'on lit
#  quand on cherche à comprendre, et il n'y a pas de raison de le laisser.
case "$NB_RAP" in
	9)  MOT="neuf" ;; 10) MOT="dix"    ;; 11) MOT="onze"  ;;
	12) MOT="douze" ;; 13) MOT="treize" ;; 14) MOT="quatorze" ;;
	*)  MOT="" ;;
esac
if [ -z "$MOT" ]; then
	non "le banc ne sait pas écrire $NB_RAP en toutes lettres — ajoute-le au « case »"
else
	PROSE_KO=""
	for f in "$DIR/85-outils-lexos.list" "$HOOK"; do
		#  UN FICHIER SANS PHRASE DE COMPTE EST UN ÉCHEC, PAS UN SAUT.
		#  La première écriture faisait « continue » quand rien ne
		#  correspondait — et le hook 0250 coupait justement « Onze » et
		#  « paquets » sur deux lignes. Le contrôle annonçait deux fichiers
		#  et n'en regardait qu'un : mesuré, il restait vert alors que le
		#  hook mentait. Un contrôle qui saute est un contrôle qui dort.
		LIGNE="$(grep -iE "[^a-zà-ÿ](neuf|dix|onze|douze|treize|quatorze) paquets" "$f" || true)"
		if [ -z "$LIGNE" ]; then
			PROSE_KO="$PROSE_KO $(basename "$f")(aucun compte écrit)"
		elif ! grep -qiE "[^a-zà-ÿ]$MOT paquets" <<< "$LIGNE"; then
			PROSE_KO="$PROSE_KO $(basename "$f")"
		fi
	done
	if [ -z "$PROSE_KO" ]; then
		ok "la prose dit « $MOT paquets » — c'est bien ce que la liste contient"
	else
		non "le compte écrit ne correspond plus à la liste ($NB_RAP =« $MOT ») :$PROSE_KO"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
