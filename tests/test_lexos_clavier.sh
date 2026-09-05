#!/usr/bin/env bash
# =============================================================================
#  Éprouver le CLAVIER — la page qui ne savait que regarder
# =============================================================================
#  ALEX, SUR LA VRAIE MACHINE : « dans les paramètres de clavier, une fois
#  installé, on n'est pas capable de changer de clavier », puis « comme pour
#  le @, je suis pas capable de le faire », et enfin « faire en sorte qu'on
#  puisse avoir tous les paramètres de clavier ».
#
#  DEUX IMPASSES, ET AUCUNE NE DISAIT SON NOM.
#
#  1. La page Clavier des Paramètres AFFICHAIT les dispositions et, pour en
#     changer, renvoyait au dialogue de XFCE. Aucun réglage de son côté.
#
#  2. Ce dialogue s'ouvre TOUT GRISÉ. Relevé dans le GtkBuilder du binaire
#     lui-même — pas supposé :
#         <object class="GtkSwitch" id="xkb_use_system_default_switch">
#           <property name="active">True</property>
#     « Utiliser les réglages système » est actif par défaut, et tant qu'il
#     l'est, XFCE grise la liste des dispositions, le modèle et la bascule.
#     LexOS ne livrait aucun keyboard-layout.xml pour dire le contraire.
#
#  Conséquence : on reste sur la disposition posée à l'installation, et le
#  « @ » n'est pas là où Alex le cherche.
#
#  CE BANC ÉPROUVE LES DEUX BOUTS : le déverrouillage livré dans l'ISO, et
#  les gestes qui changent VRAIMENT la disposition — en les faisant tourner,
#  pas en lisant le code.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-clavier"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
XML="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$MOTEUR" "$PAGE"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE DÉVERROUILLAGE — sans lui, la page de XFCE reste grise"
# =============================================================================
if [ ! -r "$XML" ]; then
	non "aucun keyboard-layout.xml dans le squelette — le dialogue XFCE s'ouvrira grisé"
else
	ok "le squelette livre keyboard-layout.xml"
	if command -v xmllint >/dev/null 2>&1; then
		xmllint --noout "$XML" 2>/dev/null \
			&& ok "il se parse — xfconf ne l'ignorera pas en silence" \
			|| non "XML invalide : xfconf le jetterait sans rien dire"
	fi
	#  ═══ LE NOM DE LA PROPRIÉTÉ, ET IL A ÉTÉ FAUX PENDANT DEUX IMAGES ═══
	#  Ce fichier écrivait « XkbDisableAll ». Ce nom N'EXISTE PAS dans XFCE :
	#  le fichier était inerte, le dialogue restait grisé, et — plus grave —
	#  xfsettingsd n'appliquait pas non plus les dispositions écrites par
	#  « lexos clavier », puisque la vraie propriété gardait sa valeur par
	#  défaut (TRUE = « s'en remettre aux réglages système »).
	#
	#  Le vrai nom est « XkbDisable » (xfsettingsd/keyboard-layout.c:106).
	if grep -q 'name="XkbDisable"[^/]*value="false"' "$XML"; then
		ok "XkbDisable=false : la liste des dispositions est cliquable"
	else
		non "XkbDisable n'est pas à false — XFCE grisera tout"
	fi
	if grep -q 'name="XkbDisableAll"' "$XML"; then
		non "« XkbDisableAll » est de retour : ce nom n'existe pas, le fichier serait inerte"
	else
		ok "aucun « XkbDisableAll » — ce nom n'a jamais été lu par XFCE"
	fi

	#  ═══ ET ON LE DEMANDE AU BINAIRE, PAS À NOTRE MÉMOIRE ═══
	#  C'est ce contrôle qui aurait évité la faute : xfsettingsd porte en
	#  clair les noms des propriétés qu'il lit. Quand il est là, on compare.
	if command -v xfsettingsd >/dev/null 2>&1 && command -v strings >/dev/null 2>&1; then
		strings /usr/bin/xfsettingsd 2>/dev/null | grep -E '^/Default/Xkb' | sort -u > "$BANC/props" || true
		if [ ! -s "$BANC/props" ]; then
			saute "xfsettingsd ne livre pas ses noms de propriétés — comparaison impossible"
		else
			grep -qx '/Default/XkbDisable' "$BANC/props" \
				&& ok "xfsettingsd lit bien « /Default/XkbDisable » (relevé dans le binaire)" \
				|| non "xfsettingsd ne lit pas « /Default/XkbDisable » : notre fichier viserait à côté"
			grep -qx '/Default/XkbDisableAll' "$BANC/props" \
				&& non "xfsettingsd lirait « XkbDisableAll » — alors le correctif était inutile" \
				|| ok "et il n'a jamais lu « /Default/XkbDisableAll »"
			#  Les propriétés que l'outil écrit doivent exister aussi.
			MANQUE_P=""
			for P in XkbLayout XkbVariant; do
				grep -qx "/Default/$P" "$BANC/props" || MANQUE_P="$MANQUE_P $P"
			done
			[ -z "$MANQUE_P" ] \
				&& ok "les propriétés écrites par lexos-clavier existent dans xfsettingsd" \
				|| non "propriétés inconnues de xfsettingsd :$MANQUE_P"
		fi
	else
		saute "xfsettingsd absent : les noms de propriétés n'ont PAS été confrontés au binaire"
	fi
	#  ET IL NE DOIT IMPOSER AUCUNE DISPOSITION. La disposition est choisie à
	#  l'installation et vit dans /etc/default/keyboard ; l'écraser depuis le
	#  squelette imposerait le clavier d'Alex à tout le monde.
	if grep -q 'name="XkbLayout"' "$XML"; then
		non "le squelette impose une disposition — celle choisie à l'installation serait écrasée"
	else
		ok "aucune disposition imposée : on ouvre la porte, on ne choisit pas à la place"
	fi
fi

#  ET L'OUTIL ÉCRIT LE MÊME NOM QUE LE SQUELETTE. Ils étaient tous les deux
#  faux ; les corriger l'un sans l'autre aurait laissé « lexos clavier » sans
#  effet durable, ce qui est le défaut le plus difficile à voir : la
#  disposition change à l'écran (setxkbmap l'applique tout de suite) et
#  revient à la session suivante.
#  ON LIT LE CODE, COMMENTAIRES RETIRÉS : l'explication du correctif cite
#  justement le mauvais nom pour dire de ne plus l'employer. Un contrôle rouge
#  à cause du texte qui explique le correctif est le pire des faux positifs.
sed 's/#.*$//' "$OUTIL" > "$BANC/outil-nu.sh"
if grep -q 'XkbDisableAll' "$BANC/outil-nu.sh"; then
	non "lexos-clavier écrit encore « XkbDisableAll » : xfsettingsd ignorerait ses dispositions"
else
	ok "lexos-clavier écrit « XkbDisable », le nom que XFCE lit vraiment"
fi

# =============================================================================
titre "2. « --json » — le catalogue passe au reste du système"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le JSON n'a PAS été éprouvé"
else
	SORTIE="$(LEXOS_SANS_X=1 HOME="$BANC" bash "$OUTIL" --json 2>/dev/null)"
	if printf '%s' "$SORTIE" | python3 -m json.tool >/dev/null 2>&1; then
		ok "« lexos-clavier --json » rend du JSON valide"
		LU="$(printf '%s' "$SORTIE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(len(d.get('catalogue', [])), len(d.get('bascules', [])), d.get('max', 0))
")"
		read -r NCAT NBAS NMAX <<< "$LU"
		[ "${NCAT:-0}" -ge 15 ] \
			&& ok "il publie les ${NCAT} dispositions du catalogue" \
			|| non "seulement ${NCAT:-0} dispositions publiées"
		[ "${NBAS:-0}" -ge 4 ] \
			&& ok "et les ${NBAS} touches de bascule" \
			|| non "seulement ${NBAS:-0} bascules publiées"
		[ "${NMAX:-0}" = "4" ] \
			&& ok "la limite de X (4 dispositions) est dite au lieu d'être devinée" \
			|| non "la limite n'est pas publiée"
	else
		non "« --json » ne rend pas du JSON valide :\\n$SORTIE"
	fi
fi

# =============================================================================
titre "3. LES GESTES CHANGENT VRAIMENT LA DISPOSITION — on les fait tourner"
# =============================================================================
#  On ne lit pas le code : on appelle l'action du moteur, comme la page le
#  fait, et on regarde l'état AVANT et APRÈS. Un contrôle qui vérifierait la
#  présence d'une fonction serait vert avec une fonction qui ne fait rien.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : les gestes n'ont PAS été éprouvés"
else
	cat > "$BANC/gestes.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import settings

try:
    def cles():
        return [a["cle"] for a in settings._clavier_etat()["actives"]]

    def bascule():
        return settings._clavier_etat()["bascule"]

    depart = cles()
    if depart != ["ca-fr"]:
        print("NON|l'état de départ n'est pas « ca-fr » mais %s" % depart)

    r = settings.act_clavier("ajouter:us")
    print(("OK|" if (r.get("ok") and "us" in cles()) else "NON|") +
          "« ajouter » met une deuxième disposition (%s)" % cles())

    r = settings.act_clavier("dabord:us")
    print(("OK|" if (r.get("ok") and cles()[:1] == ["us"]) else "NON|") +
          "« dabord » change celle du démarrage (%s)" % cles())

    r = settings.act_clavier("bascule:ctrl-maj")
    print(("OK|" if (r.get("ok") and bascule() == "ctrl-maj") else "NON|") +
          "« bascule » change les touches (%s)" % bascule())

    r = settings.act_clavier("retirer:ca-fr")
    print(("OK|" if (r.get("ok") and "ca-fr" not in cles()) else "NON|") +
          "« retirer » enlève une disposition (%s)" % cles())

    #  ═══ CE QUI DOIT ÊTRE REFUSÉ ═══
    #  Ces valeurs viennent d'une page web. Aucune ne peut atteindre un shell —
    #  _run() reçoit une liste d'arguments, il n'y en a pas — mais toutes doivent
    #  être refusées AVEC UN MOTIF.
    for mauvais, quoi in (("ajouter:; rm -rf /", "une commande glissée dans la clé"),
                          ("effacer:us",          "un geste inconnu"),
                          ("ajouter:",            "une clé vide"),
                          ("bascule:us",          "une disposition donnée comme bascule")):
        r = settings.act_clavier(mauvais)
        print(("OK|" if not r.get("ok") else "NON|") +
              "refusé : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  ET LE REFUS VIENT DES PARAMÈTRES, PAS SEULEMENT DE L'OUTIL.
    #  lexos-clavier refuse aussi une clé inconnue — « Disposition inconnue ».
    #  Un contrôle qui se contenterait de « ok vaut faux » serait donc VERT même
    #  si le moteur ne vérifiait plus rien : la mutation est passée inaperçue à
    #  la première écriture de ce banc. On exige le motif du moteur, celui qui
    #  nomme le catalogue, parce que c'est lui qui permet à la page de dire à
    #  l'utilisateur ce qui ne va pas.
    r = settings.act_clavier("ajouter:pas-une-cle")
    print(("OK|" if (not r.get("ok") and "catalogue" in r.get("erreur", "")) else "NON|") +
          "une clé hors catalogue est refusée PAR LES PARAMÈTRES (%s)" % r.get("erreur", "ACCEPTÉE !"))
except Exception as _e:
    #  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception
    #  au milieu emporte tous les contrôles qui suivent : le banc affiche
    #  moins de coches et reste vert.
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")
PY
	SORTIE_G="$(cd "$RACINE" && PATH="$RACINE/config/includes.chroot/usr/bin:$PATH" \
		LEXOS_SANS_X=1 HOME="$BANC/foyer" python3 "$BANC/gestes.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_G" ]; then
		non "les gestes n'ont rien rendu — le moteur n'a pas pu être appelé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_G"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_G
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_G
EOF
	fi
fi

# =============================================================================
titre "4. LA PAGE A DE QUOI CLIQUER — elle ne fait plus que regarder"
# =============================================================================
#  On lit le code de la page, commentaires retirés : une explication qui
#  parle d'un bouton ne prouve pas qu'il existe.
#  ON ÉCRIT LE TEXTE DÉPOUILLÉ DANS UN FICHIER, ET ON GREPPE LE FICHIER.
#  « printf … | grep -q » est un piège que ce dépôt a déjà payé : grep ferme
#  le tuyau dès la première correspondance, printf reçoit un SIGPIPE, et avec
#  « set -o pipefail » la commande rend 141 — un rouge qui ne parle pas du
#  code. Pire, c'est une COURSE : selon que printf a fini d'écrire ou non, le
#  même contrôle passe ou échoue. La première version de ce banc annonçait
#  « 3/4 branchés » sur un fichier qui en a quatre.
sed 's|//.*$||' "$PAGE" > "$BANC/page.js"
MANQUE=""
for F in clavierDabord clavierAjouter clavierRetirer clavierBascule; do
	grep -q "async function $F(" "$BANC/page.js" || MANQUE="$MANQUE $F"
done
[ -z "$MANQUE" ] \
	&& ok "les quatre gestes existent dans la page" \
	|| non "gestes absents de la page :$MANQUE"

#  ET ILS SONT BRANCHÉS À QUELQUE CHOSE DE CLIQUABLE. Une fonction que rien
#  n'appelle est une fonction morte — exactement le défaut des trois
#  sélecteurs de l'écran de connexion, qui existaient et ne visaient rien.
BRANCHES=0
for F in clavierDabord clavierAjouter clavierRetirer clavierBascule; do
	grep -qE "(onclick|onchange)=\"$F\(" "$BANC/page.js" && BRANCHES=$((BRANCHES + 1))
done
[ "$BRANCHES" = "4" ] \
	&& ok "les quatre sont appelés par un bouton ou une liste déroulante" \
	|| non "seulement ${BRANCHES}/4 gestes sont reliés à quelque chose de cliquable"

#  LE MOTEUR CONNAÎT L'ACTION. Sans cette ligne, chaque clic reviendrait
#  « action inconnue » sans que la page sache pourquoi.
grep -q '"clavier": act_clavier' "$MOTEUR" \
	&& ok "le moteur des Paramètres connaît l'action « clavier »" \
	|| non "l'action « clavier » n'est pas dans la table ACTIONS"

# =============================================================================
titre "5. ON NE RECOPIE PAS LE CATALOGUE — une seule source"
# =============================================================================
#  Vingt dispositions écrites deux fois finiraient par ne plus dire la même
#  chose. C'est le raisonnement déjà tenu dans settings.py pour lexos-distant,
#  et la faute qui a donné trois palettes de panneaux dans ce dépôt.
if grep -q "lexos-clavier" "$MOTEUR"; then
	ok "le moteur demande son catalogue à lexos-clavier"
else
	non "le moteur ne passe pas par lexos-clavier"
fi
if grep -qE '"(ca-multi|us-intl|colemak)"' "$MOTEUR" "$PAGE"; then
	non "des clés du catalogue sont recopiées dans les Paramètres — deux sources"
else
	ok "aucune clé du catalogue recopiée dans les Paramètres"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
